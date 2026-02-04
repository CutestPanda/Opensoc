/*
MIT License

Copyright (c) 2024 Panda, 2257691535@qq.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

`timescale 1ns / 1ps
/********************************************************************
本模块: 分支预测单元

描述:
B指令跳转方向预测 -> 基于全局历史的分支预测

JALR指令跳转目标地址预测 -> 返回地址堆栈(RAS)
JAL/B指令跳转目标地址预测 -> 分支目标缓存(BTB)

分支预测单元时延 = 1clk

若预测请求指示信号无效, 那么预测结果保持不变

注意：
若分支预测单元正在初始化, 则不能给出预测请求
对于BTB中分支指令类型为JALR的条目, 其BTA是无意义的

协议:
MEM MASTER

作者: 陈家耀
日期: 2026/01/22
********************************************************************/


module panda_risc_v_brc_prdt #(
	// 全局历史分支预测配置
	parameter EN_PC_FOR_PHT_ADDR = "true", // 生成PHT地址时是否考虑PC
	parameter EN_GHR_FOR_PHT_ADDR = "true", // 生成PHT地址时是否考虑GHR
	parameter integer GHR_WIDTH = 8, // 全局分支历史寄存器的位宽(<=16)
	// BTB配置
	parameter integer BTB_WAY_N = 2, // BTB路数(1 | 2 | 4)
	parameter integer BTB_ENTRY_N = 512, // BTB项数(<=65536)
	parameter integer PC_TAG_WIDTH = 21, // PC标签的位宽(不要修改, 应为30 - clogb2(BTB_ENTRY_N))
	parameter integer BTB_MEM_WIDTH = PC_TAG_WIDTH + 32 + 3 + 1 + 1 + 2, // BTB存储器的数据位宽(不要修改)
	parameter NO_INIT_BTB = "false", // 是否无需初始化BTB存储器
	// RAS配置
	parameter integer RAS_ENTRY_N = 4, // 返回地址堆栈的条目数(2 | 4 | 8 | 16)
	// 仿真配置
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 分支预测单元正在初始化
	output wire prdt_unit_initializing,
	
	// 全局历史分支预测
	// [更新退休GHR]
	input wire glb_brc_prdt_on_clr_retired_ghr, // 清零退休GHR
	input wire glb_brc_prdt_on_upd_retired_ghr, // 退休GHR更新指示
	input wire glb_brc_prdt_retired_ghr_shift_in, // 退休GHR移位输入
	// [更新推测GHR]
	input wire glb_brc_prdt_rstr_speculative_ghr, // 恢复推测GHR指示
	// [更新PHT]
	input wire glb_brc_prdt_upd_i_req, // 更新请求
	input wire[31:0] glb_brc_prdt_upd_i_pc, // 待更新项的PC
	input wire[GHR_WIDTH-1:0] glb_brc_prdt_upd_i_ghr, // 待更新项的GHR
	input wire glb_brc_prdt_upd_i_brc_taken, // 待更新项的实际分支跳转方向
	// [GHR值]
	output wire[GHR_WIDTH-1:0] glb_brc_prdt_retired_ghr_o, // 当前的退休GHR
	
	// 分支目标缓存
	// [BTB置换]
	input wire btb_rplc_req, // 置换请求
	input wire btb_rplc_strgy, // 置换策略(1'b0 -> 随机, 1'b1 -> 定向)
	input wire[1:0] btb_rplc_sel_wid, // 置换选定的缓存路编号
	input wire[31:0] btb_rplc_pc, // 分支指令对应的PC
	input wire[2:0] btb_rplc_btype, // 分支指令类型
	input wire[31:0] btb_rplc_bta, // 分支指令对应的目标地址
	input wire btb_rplc_jpdir, // BTFN跳转方向(1'b1 -> 向后, 1'b0 -> 向前)
	input wire btb_rplc_push_ras, // RAS压栈标志
	input wire btb_rplc_pop_ras, // RAS出栈标志
	input wire btb_rplc_vld_flag, // 有效标志
	// [BTB存储器]
	// (端口A)
	output wire[BTB_WAY_N-1:0] btb_mem_clka,
	output wire[BTB_WAY_N-1:0] btb_mem_ena,
	output wire[BTB_WAY_N-1:0] btb_mem_wea,
	output wire[BTB_WAY_N*16-1:0] btb_mem_addra,
	output wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_dina,
	input wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_douta,
	// (端口B)
	output wire[BTB_WAY_N-1:0] btb_mem_clkb,
	output wire[BTB_WAY_N-1:0] btb_mem_enb,
	output wire[BTB_WAY_N-1:0] btb_mem_web,
	output wire[BTB_WAY_N*16-1:0] btb_mem_addrb,
	output wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_dinb,
	input wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_doutb,
	
	// 预测输入
	input wire prdt_i_req, // 预测请求
	input wire[31:0] prdt_i_pc, // 待预测的PC
	input wire[31:0] prdt_i_nxt_pc, // 待预测的下一PC
	input wire[15:0] prdt_i_tid, // 事务ID
	
	// 预测结果
	output wire prdt_o_vld, // 预测结果有效
	output wire[31:0] prdt_o_pc, // 预测得到的PC
	output wire[2:0] prdt_o_brc_type, // 预测得到的分支指令类型
	output wire prdt_o_push_ras, // 预测得到的RAS压栈标志
	output wire prdt_o_pop_ras, // 预测得到的RAS出栈标志
	output wire prdt_o_taken, // 是否预测跳转
	output wire prdt_o_btb_hit, // BTB命中
	output wire[1:0] prdt_o_btb_wid, // BTB命中的缓存路编号
	output wire[BTB_WAY_N-1:0] prdt_o_btb_wvld, // BTB缓存路有效标志
	output wire[31:0] prdt_o_btb_bta, // BTB分支目标地址
	output wire[GHR_WIDTH-1:0] prdt_o_glb_speculative_ghr, // 推测GHR
	output wire[1:0] prdt_o_glb_2bit_sat_cnt, // 全局历史分支预测给出的2bit饱和计数器
	output wire[15:0] prdt_o_tid // 事务ID
);
	
	/** 常量 **/
	// 分支指令类型常量
	localparam BRANCH_TYPE_JAL = 3'b000; // JAL指令
	localparam BRANCH_TYPE_JALR = 3'b001; // JALR指令
	localparam BRANCH_TYPE_B = 3'b010; // B指令
	
	/** 基于全局历史的分支预测 **/
	// 更新推测GHR
	wire glb_brc_prdt_on_upd_speculative_ghr; // 推测GHR更新指示
	wire glb_brc_prdt_speculative_ghr_shift_in; // 推测GHR移位输入
	wire[GHR_WIDTH-1:0] glb_brc_prdt_speculative_ghr_o; // 最新的推测GHR
	// PHT正在初始化(标志)
	wire glb_brc_prdt_pht_initializing;
	// 查询PHT
	wire glb_brc_prdt_query_i_req; // 查询请求
	wire[31:0] glb_brc_prdt_query_i_pc; // 待查询的PC
	wire[1:0] glb_brc_prdt_query_o_2bit_sat_cnt; // 查询得到的2bit饱和计数器
	wire glb_brc_prdt_query_o_vld; // 查询结果有效(指示)
	// PHT存储器
	// 说明: PHT_MEM_IMPL == "reg"时可用
	// [读端口]
	wire glb_brc_prdt_pht_mem_ren;
	wire[15:0] glb_brc_prdt_pht_mem_raddr;
	wire[1:0] glb_brc_prdt_pht_mem_dout;
	// [更新端口]
	wire glb_brc_prdt_pht_mem_upd_en;
	wire[15:0] glb_brc_prdt_pht_mem_upd_addr;
	wire glb_brc_prdt_pht_mem_upd_brc_taken;
	
	panda_risc_v_glb_brc_prdt #(
		.EN_PC_FOR_PHT_ADDR(EN_PC_FOR_PHT_ADDR),
		.EN_GHR_FOR_PHT_ADDR(EN_GHR_FOR_PHT_ADDR),
		.GHR_WIDTH(GHR_WIDTH),
		.PHT_MEM_IMPL("reg"),
		.SIM_DELAY(SIM_DELAY)
	)glb_brc_prdt_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.on_clr_retired_ghr(glb_brc_prdt_on_clr_retired_ghr),
		.on_upd_retired_ghr(glb_brc_prdt_on_upd_retired_ghr),
		.retired_ghr_shift_in(glb_brc_prdt_retired_ghr_shift_in),
		.rstr_speculative_ghr(glb_brc_prdt_rstr_speculative_ghr),
		.on_upd_speculative_ghr(glb_brc_prdt_on_upd_speculative_ghr),
		.speculative_ghr_shift_in(glb_brc_prdt_speculative_ghr_shift_in),
		.speculative_ghr_o(glb_brc_prdt_speculative_ghr_o),
		.retired_ghr_o(glb_brc_prdt_retired_ghr_o),
		
		.pht_initializing(glb_brc_prdt_pht_initializing),
		
		.query_i_req(glb_brc_prdt_query_i_req),
		.query_i_pc(glb_brc_prdt_query_i_pc),
		.query_o_2bit_sat_cnt(glb_brc_prdt_query_o_2bit_sat_cnt),
		.query_o_vld(glb_brc_prdt_query_o_vld),
		
		.update_i_req(glb_brc_prdt_upd_i_req),
		.update_i_pc(glb_brc_prdt_upd_i_pc),
		.update_i_ghr(glb_brc_prdt_upd_i_ghr),
		.update_i_2bit_sat_cnt(2'b00),
		.update_i_brc_taken(glb_brc_prdt_upd_i_brc_taken),
		
		.pht_mem_clka(),
		.pht_mem_ena(),
		.pht_mem_wea(),
		.pht_mem_addra(),
		.pht_mem_dina(),
		.pht_mem_douta(2'b00),
		
		.pht_mem_clkb(),
		.pht_mem_enb(),
		.pht_mem_web(),
		.pht_mem_addrb(),
		.pht_mem_dinb(),
		.pht_mem_doutb(2'b00),
		
		.pht_mem_ren(glb_brc_prdt_pht_mem_ren),
		.pht_mem_raddr(glb_brc_prdt_pht_mem_raddr),
		.pht_mem_dout(glb_brc_prdt_pht_mem_dout),
		
		.pht_mem_upd_en(glb_brc_prdt_pht_mem_upd_en),
		.pht_mem_upd_addr(glb_brc_prdt_pht_mem_upd_addr),
		.pht_mem_upd_brc_taken(glb_brc_prdt_pht_mem_upd_brc_taken)
	);
	
	panda_risc_v_pht #(
		.INIT_2BIT_SAT_CNT_V(2'b01), // 初始为"弱不跳"
		.PHT_MEM_DEPTH(2**GHR_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)pht_reg_file_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.pht_mem_ren(glb_brc_prdt_pht_mem_ren),
		.pht_mem_raddr(glb_brc_prdt_pht_mem_raddr),
		.pht_mem_dout(glb_brc_prdt_pht_mem_dout),
		
		.pht_mem_upd_en(glb_brc_prdt_pht_mem_upd_en),
		.pht_mem_upd_addr(glb_brc_prdt_pht_mem_upd_addr),
		.pht_mem_upd_brc_taken(glb_brc_prdt_pht_mem_upd_brc_taken)
	);
	
	/** 返回地址堆栈(RAS) **/
	// RAS压栈
	wire ras_push_req;
	wire[31:0] ras_push_addr;
	// RAS出栈
	wire ras_pop_req;
	// RAS查询
	wire ras_query_req;
	wire[31:0] ras_query_addr;
	
	panda_risc_v_ras #(
		.RAS_ENTRY_WIDTH(32),
		.RAS_ENTRY_N(RAS_ENTRY_N),
		.SIM_DELAY(SIM_DELAY)
	)ras_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.ras_push_req(ras_push_req),
		.ras_push_addr(ras_push_addr),
		
		.ras_pop_req(ras_pop_req),
		.ras_pop_addr(),
		
		.ras_query_req(ras_query_req),
		.ras_query_addr(ras_query_addr)
	);
	
	/** 分支目标缓存(BTB) **/
	// BTB正在初始化(标志)
	wire btb_initializing;
	// BTB查询
	wire btb_query_i_req; // 查询请求
	wire[31:0] btb_query_i_pc; // 待查询的PC
	wire[31:0] btb_query_i_nxt_pc; // 待查询的下一PC
	wire btb_query_o_hit; // 查询命中
	wire[1:0] btb_query_o_wid; // 查询命中的缓存路编号
	wire[BTB_WAY_N-1:0] btb_query_o_wvld; // 查询得到的缓存路有效标志
	wire[2:0] btb_query_o_btype; // 查询得到的分支指令类型
	wire btb_query_o_push_ras; // 查询得到的RAS压栈标志
	wire btb_query_o_pop_ras; // 查询得到的RAS出栈标志
	wire[31:0] btb_query_o_bta; // 查询得到的分支目标地址
	wire btb_query_o_jpdir; // 查询得到的BTFN跳转方向(1'b1 -> 向后, 1'b0 -> 向前)
	wire[31:0] btb_query_o_nxt_pc; // 查询得到的下一PC
	wire btb_query_o_vld; // 查询结果有效
	
	panda_risc_v_btb #(
		.BTB_WAY_N(BTB_WAY_N),
		.BTB_ENTRY_N(BTB_ENTRY_N),
		.PC_TAG_WIDTH(PC_TAG_WIDTH),
		.BTB_MEM_WIDTH(BTB_MEM_WIDTH),
		.NO_INIT_BTB(NO_INIT_BTB),
		.SIM_DELAY(SIM_DELAY)
	)btb_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.btb_initializing(btb_initializing),
		
		.btb_query_i_req(btb_query_i_req),
		.btb_query_i_pc(btb_query_i_pc),
		.btb_query_i_nxt_pc(btb_query_i_nxt_pc),
		.btb_query_o_hit(btb_query_o_hit),
		.btb_query_o_wid(btb_query_o_wid),
		.btb_query_o_wvld(btb_query_o_wvld),
		.btb_query_o_btype(btb_query_o_btype),
		.btb_query_o_push_ras(btb_query_o_push_ras),
		.btb_query_o_pop_ras(btb_query_o_pop_ras),
		.btb_query_o_bta(btb_query_o_bta),
		.btb_query_o_jpdir(btb_query_o_jpdir),
		.btb_query_o_nxt_pc(btb_query_o_nxt_pc),
		.btb_query_o_vld(btb_query_o_vld),
		
		.btb_rplc_req(btb_rplc_req),
		.btb_rplc_strgy(btb_rplc_strgy),
		.btb_rplc_sel_wid(btb_rplc_sel_wid),
		.btb_rplc_pc(btb_rplc_pc),
		.btb_rplc_btype(btb_rplc_btype),
		.btb_rplc_bta(btb_rplc_bta),
		.btb_rplc_jpdir(btb_rplc_jpdir),
		.btb_rplc_push_ras(btb_rplc_push_ras),
		.btb_rplc_pop_ras(btb_rplc_pop_ras),
		.btb_rplc_vld_flag(btb_rplc_vld_flag),
		
		.btb_mem_clka(btb_mem_clka),
		.btb_mem_ena(btb_mem_ena),
		.btb_mem_wea(btb_mem_wea),
		.btb_mem_addra(btb_mem_addra),
		.btb_mem_dina(btb_mem_dina),
		.btb_mem_douta(btb_mem_douta),
		
		.btb_mem_clkb(btb_mem_clkb),
		.btb_mem_enb(btb_mem_enb),
		.btb_mem_web(btb_mem_web),
		.btb_mem_addrb(btb_mem_addrb),
		.btb_mem_dinb(btb_mem_dinb),
		.btb_mem_doutb(btb_mem_doutb)
	);
	
	/** 分支预测控制 **/
	reg[GHR_WIDTH-1:0] prdt_o_glb_speculative_ghr_r; // 推测GHR
	reg[15:0] prdt_o_tid_r; // 事务ID
	
	assign prdt_unit_initializing = glb_brc_prdt_pht_initializing | btb_initializing;
	
	assign prdt_o_vld = btb_query_o_vld & glb_brc_prdt_query_o_vld;
	assign prdt_o_pc = 
		(btb_query_o_hit & (btb_query_o_btype == BRANCH_TYPE_JALR)) ? 
			ras_query_addr: // BTB命中, 并指示这是1条JALR指令, 那么预测地址从RAS取得
			btb_query_o_bta;
	assign prdt_o_brc_type = btb_query_o_btype;
	assign prdt_o_push_ras = btb_query_o_push_ras;
	assign prdt_o_pop_ras = btb_query_o_pop_ras;
	assign prdt_o_taken = 
		btb_query_o_hit & 
		(
			((btb_query_o_btype == BRANCH_TYPE_JAL) | (btb_query_o_btype == BRANCH_TYPE_JALR)) | 
			((btb_query_o_btype == BRANCH_TYPE_B) & glb_brc_prdt_query_o_2bit_sat_cnt[1])
		);
	assign prdt_o_btb_hit = btb_query_o_hit;
	assign prdt_o_btb_wid = btb_query_o_wid;
	assign prdt_o_btb_wvld = btb_query_o_wvld;
	assign prdt_o_btb_bta = btb_query_o_bta;
	assign prdt_o_glb_speculative_ghr = prdt_o_glb_speculative_ghr_r;
	assign prdt_o_glb_2bit_sat_cnt = glb_brc_prdt_query_o_2bit_sat_cnt;
	assign prdt_o_tid = prdt_o_tid_r;
	
	assign glb_brc_prdt_on_upd_speculative_ghr = 
		btb_query_o_vld & 
		(btb_query_o_hit & (btb_query_o_btype == BRANCH_TYPE_B)); // BTB命中, 并指示这是1条B指令
	assign glb_brc_prdt_speculative_ghr_shift_in = 
		glb_brc_prdt_query_o_2bit_sat_cnt[1];
	assign glb_brc_prdt_query_i_req = prdt_i_req;
	assign glb_brc_prdt_query_i_pc = prdt_i_pc;
	
	assign btb_query_i_req = prdt_i_req;
	assign btb_query_i_pc = prdt_i_pc;
	assign btb_query_i_nxt_pc = prdt_i_nxt_pc;
	
	assign ras_push_req = 
		btb_query_o_vld & btb_query_o_hit & 
		((btb_query_o_btype == BRANCH_TYPE_JAL) | (btb_query_o_btype == BRANCH_TYPE_JALR)) & 
		btb_query_o_push_ras;
	assign ras_push_addr = 
		btb_query_o_nxt_pc;
	assign ras_pop_req = 
		btb_query_o_vld & btb_query_o_hit & 
		(btb_query_o_btype == BRANCH_TYPE_JALR) & 
		btb_query_o_pop_ras;
	assign ras_query_req = 
		prdt_i_req;
	
	// 推测GHR, 事务ID
	always @(posedge aclk)
	begin
		if(prdt_i_req & (~prdt_unit_initializing))
		begin
			prdt_o_glb_speculative_ghr_r <= # SIM_DELAY glb_brc_prdt_speculative_ghr_o;
			prdt_o_tid_r <= # SIM_DELAY prdt_i_tid;
		end
	end
	
endmodule
