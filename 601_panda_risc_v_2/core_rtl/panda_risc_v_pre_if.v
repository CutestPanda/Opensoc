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
本模块: 预取指单元

描述:
处理复位/冲刷请求, 开展分支预测, 向指令总线控制单元发送访问请求, 访问地址可能是 -> 
	(1)复位/冲刷地址
	(2)预测地址
	(3)分支信息广播给出的真实BTA
	(4)PC + 指令长度

在指令总线控制单元接受访问请求的同时进行分支预测, 这样下一clk就可得到新的PC

对于以下2种情况, 属于分支预测特例, 此时会从取指阶段或发射阶段的分支信息广播获取真实的BTA -> 
	(1)BTB命中, 分支指令类型为JALR, RAS出栈标志无效
	(2)BTB缺失, 方向预测为跳

向指令总线控制单元广播预测信息, 可为替换BTB条目、更新全局历史分支预测器、检查分支预测是否正确提供参考

注意：
要求指令总线控制单元从接受访问请求到返回应答(发送取指阶段的分支信息广播)至少有2clk时延

协议:
MEM MASTER

作者: 陈家耀
日期: 2025/06/12
********************************************************************/


module panda_risc_v_pre_if #(
	// 指令总线控制单元配置
	parameter integer IBUS_TID_WIDTH = 8, // 指令总线事务ID位宽(1~16)
	parameter integer IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH = 1, // 指令总线访问请求附带信息的位宽(正整数)
	parameter integer PRDT_MSG_WIDTH = 96, // 分支预测信息的位宽(正整数)
	// 全局历史分支预测配置
	parameter EN_PC_FOR_PHT_ADDR = "true", // 生成PHT地址时是否考虑PC
	parameter EN_GHR_FOR_PHT_ADDR = "true", // 生成PHT地址时是否考虑GHR
	parameter integer GHR_WIDTH = 8, // 全局分支历史寄存器的位宽(<=16)
	// BTB配置
	parameter integer BTB_WAY_N = 2, // BTB路数(1 | 2 | 4)
	parameter integer BTB_ENTRY_N = 512, // BTB项数(<=65536)
	parameter integer PC_TAG_WIDTH = 21, // PC标签的位宽(不要修改)
	parameter integer BTB_MEM_WIDTH = PC_TAG_WIDTH + 32 + 3 + 1 + 1 + 2, // BTB存储器的数据位宽(不要修改)
	// RAS配置
	parameter integer RAS_ENTRY_N = 4, // 返回地址堆栈的条目数(2 | 4 | 8 | 16)
	// 仿真配置
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 复位/冲刷
	input wire sys_reset_req, // 系统复位请求
	input wire[31:0] rst_pc, // 复位时的PC
	input wire flush_req, // 冲刷请求
	input wire[31:0] flush_addr, // 冲刷地址
	output wire rst_ack, // 复位应答
	output wire flush_ack, // 冲刷应答
	
	// 指令总线控制单元
	// [清空指令缓存指示]
	output wire clr_inst_buf,
	// [访问请求]
	output wire[31:0] ibus_access_req_addr,
	output wire[IBUS_TID_WIDTH-1:0] ibus_access_req_tid,
	output wire[IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH-1:0] ibus_access_req_extra_msg,
	output wire ibus_access_req_valid,
	input wire ibus_access_req_ready,
	
	// 预测信息广播
	output wire prdt_bdcst_vld, // 广播有效
	output wire[IBUS_TID_WIDTH-1:0] prdt_bdcst_tid, // 事务ID
	output wire[PRDT_MSG_WIDTH-1:0] prdt_bdcst_msg, // 分支预测信息
	
	// 分支信息广播
	// [取指阶段]
	input wire brc_bdcst_iftc_vld, // 广播有效
	input wire[IBUS_TID_WIDTH-1:0] brc_bdcst_iftc_tid, // 事务ID
	input wire brc_bdcst_iftc_is_b_inst, // 是否B指令
	input wire brc_bdcst_iftc_is_jal_inst, // 是否JAL指令
	input wire brc_bdcst_iftc_is_jalr_inst, // 是否JALR指令
	input wire[31:0] brc_bdcst_iftc_bta, // 分支目标地址
	// [发射阶段]
	input wire brc_bdcst_luc_vld, // 广播有效
	input wire[IBUS_TID_WIDTH-1:0] brc_bdcst_luc_tid, // 事务ID
	input wire brc_bdcst_luc_is_b_inst, // 是否B指令
	input wire brc_bdcst_luc_is_jal_inst, // 是否JAL指令
	input wire brc_bdcst_luc_is_jalr_inst, // 是否JALR指令
	input wire[31:0] brc_bdcst_luc_bta, // 分支目标地址
	
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
	
	// BTB置换
	input wire btb_rplc_req, // 置换请求
	input wire btb_rplc_strgy, // 置换策略(1'b0 -> 随机, 1'b1 -> 定向)
	input wire[1:0] btb_rplc_sel_wid, // 置换选定的缓存路编号
	input wire[31:0] btb_rplc_pc, // 分支指令对应的PC
	input wire[2:0] btb_rplc_btype, // 分支指令类型
	input wire[31:0] btb_rplc_bta, // 分支指令对应的目标地址
	input wire btb_rplc_jpdir, // 分支跳转方向(1'b1 -> 向后, 1'b0 -> 向前)
	input wire btb_rplc_push_ras, // RAS压栈标志
	input wire btb_rplc_pop_ras, // RAS出栈标志
	
	// BTB存储器
	// [端口A]
	output wire[BTB_WAY_N-1:0] btb_mem_clka,
	output wire[BTB_WAY_N-1:0] btb_mem_ena,
	output wire[BTB_WAY_N-1:0] btb_mem_wea,
	output wire[BTB_WAY_N*16-1:0] btb_mem_addra,
	output wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_dina,
	input wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_douta,
	// [端口B]
	output wire[BTB_WAY_N-1:0] btb_mem_clkb,
	output wire[BTB_WAY_N-1:0] btb_mem_enb,
	output wire[BTB_WAY_N-1:0] btb_mem_web,
	output wire[BTB_WAY_N*16-1:0] btb_mem_addrb,
	output wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_dinb,
	input wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_doutb
);
	
	/** 常量 **/
	// 分支指令类型常量
	localparam BRANCH_TYPE_JAL = 3'b000; // JAL指令
	localparam BRANCH_TYPE_JALR = 3'b001; // JALR指令
	localparam BRANCH_TYPE_B = 3'b010; // B指令
	// 分支预测信息各字段的起始索引
	localparam integer PRDT_MSG_TARGET_ADDR_SID = 0; // 跳转地址
	localparam integer PRDT_MSG_BTYPE_SID = 32; // 分支指令类型
	localparam integer PRDT_MSG_IS_TAKEN_SID = 35; // 是否跳转
	localparam integer PRDT_MSG_BTB_HIT_SID = 36; // BTB命中
	localparam integer PRDT_MSG_BTB_WID_SID = 37; // BTB命中的缓存路编号
	localparam integer PRDT_MSG_BTB_WVLD_SID = 39; // BTB缓存路有效标志
	localparam integer PRDT_MSG_GLB_SAT_CNT_SID = 43; // 全局历史分支预测给出的2bit饱和计数器
	localparam integer PRDT_MSG_BTB_BTA_SID = 45; // BTB分支目标地址
	localparam integer PRDT_MSG_PUSH_RAS_SID = 77; // RAS压栈标志
	localparam integer PRDT_MSG_POP_RAS_SID = 78; // RAS出栈标志
	// 指令总线访问请求附带信息各字段的起始索引
	localparam integer IBUS_ACCESS_REQ_EXTRA_MSG_IS_FIRST_INST_SID = 0; // 是否复位释放后的第1条指令
	
	/** 分支预测单元 **/
	// 分支预测单元正在初始化(标志)
	wire prdt_unit_initializing;
	// 预测输入
	wire prdt_i_req; // 预测请求
	wire[31:0] prdt_i_pc; // 待预测的PC
	wire[31:0] prdt_i_nxt_pc; // 待预测的下一PC
	wire[15:0] prdt_i_tid; // 事务ID
	// 预测结果
	wire prdt_o_vld; // 预测结果有效
	wire[31:0] prdt_o_pc; // 预测得到的PC
	wire[2:0] prdt_o_brc_type; // 预测得到的分支指令类型
	wire prdt_o_push_ras; // 预测得到的RAS压栈标志
	wire prdt_o_pop_ras; // 预测得到的RAS出栈标志
	wire prdt_o_taken; // 是否预测跳转
	wire prdt_o_btb_hit; // BTB命中
	wire[1:0] prdt_o_btb_wid; // BTB命中的缓存路编号
	wire[BTB_WAY_N-1:0] prdt_o_btb_wvld; // BTB缓存路有效标志
	wire[31:0] prdt_o_btb_bta; // BTB分支目标地址
	wire[GHR_WIDTH-1:0] prdt_o_glb_speculative_ghr; // 推测GHR
	wire[1:0] prdt_o_glb_2bit_sat_cnt; // 全局历史分支预测给出的2bit饱和计数器
	wire[15:0] prdt_o_tid; // 事务ID
	
	panda_risc_v_brc_prdt #(
		.EN_PC_FOR_PHT_ADDR(EN_PC_FOR_PHT_ADDR),
		.EN_GHR_FOR_PHT_ADDR(EN_GHR_FOR_PHT_ADDR),
		.GHR_WIDTH(GHR_WIDTH),
		.BTB_WAY_N(BTB_WAY_N),
		.BTB_ENTRY_N(BTB_ENTRY_N),
		.PC_TAG_WIDTH(PC_TAG_WIDTH),
		.BTB_MEM_WIDTH(BTB_MEM_WIDTH),
		.RAS_ENTRY_N(RAS_ENTRY_N),
		.SIM_DELAY(SIM_DELAY)
	)brc_prdt_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.prdt_unit_initializing(prdt_unit_initializing),
		
		.glb_brc_prdt_on_clr_retired_ghr(glb_brc_prdt_on_clr_retired_ghr),
		.glb_brc_prdt_on_upd_retired_ghr(glb_brc_prdt_on_upd_retired_ghr),
		.glb_brc_prdt_retired_ghr_shift_in(glb_brc_prdt_retired_ghr_shift_in),
		.glb_brc_prdt_rstr_speculative_ghr(glb_brc_prdt_rstr_speculative_ghr),
		.glb_brc_prdt_upd_i_req(glb_brc_prdt_upd_i_req),
		.glb_brc_prdt_upd_i_pc(glb_brc_prdt_upd_i_pc),
		.glb_brc_prdt_upd_i_ghr(glb_brc_prdt_upd_i_ghr),
		.glb_brc_prdt_upd_i_brc_taken(glb_brc_prdt_upd_i_brc_taken),
		.glb_brc_prdt_retired_ghr_o(glb_brc_prdt_retired_ghr_o),
		
		.btb_rplc_req(btb_rplc_req),
		.btb_rplc_strgy(btb_rplc_strgy),
		.btb_rplc_sel_wid(btb_rplc_sel_wid),
		.btb_rplc_pc(btb_rplc_pc),
		.btb_rplc_btype(btb_rplc_btype),
		.btb_rplc_bta(btb_rplc_bta),
		.btb_rplc_jpdir(btb_rplc_jpdir),
		.btb_rplc_push_ras(btb_rplc_push_ras),
		.btb_rplc_pop_ras(btb_rplc_pop_ras),
		
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
		.btb_mem_doutb(btb_mem_doutb),
		
		.prdt_i_req(prdt_i_req),
		.prdt_i_pc(prdt_i_pc),
		.prdt_i_nxt_pc(prdt_i_nxt_pc),
		.prdt_i_tid(prdt_i_tid),
		
		.prdt_o_vld(prdt_o_vld),
		.prdt_o_pc(prdt_o_pc),
		.prdt_o_brc_type(prdt_o_brc_type),
		.prdt_o_push_ras(prdt_o_push_ras),
		.prdt_o_pop_ras(prdt_o_pop_ras),
		.prdt_o_taken(prdt_o_taken),
		.prdt_o_btb_hit(prdt_o_btb_hit),
		.prdt_o_btb_wid(prdt_o_btb_wid),
		.prdt_o_btb_wvld(prdt_o_btb_wvld),
		.prdt_o_btb_bta(prdt_o_btb_bta),
		.prdt_o_glb_speculative_ghr(prdt_o_glb_speculative_ghr),
		.prdt_o_glb_2bit_sat_cnt(prdt_o_glb_2bit_sat_cnt),
		.prdt_o_tid(prdt_o_tid)
	);
	
	/** 预取指控制 **/
	reg first_inst_flag; // 首条指令(标志)
	reg[IBUS_TID_WIDTH-1:0] inst_id; // 指令ID
	reg rst_pre_if_pending; // 复位预取指令(等待标志)
	reg flush_pre_if_pending; // 冲刷预取指令(等待标志)
	reg common_pre_if_pending; // 普通预取指令(等待标志)
	reg btb_hit_jalr_pending; // BTB命中的无法从RAS得到BTA的JALR指令(等待标志)
	reg btb_miss_pending; // BTB缺失(等待标志)
	reg btb_hit_jalr_bdcst_gotten; // BTB命中的无法从RAS得到BTA的JALR指令得到分支信息广播(标志)
	reg btb_miss_bdcst_gotten; // BTB缺失得到分支信息广播(标志)
	wire to_rst; // 正在处理复位(标志)
	wire to_flush; // 正在处理冲刷(标志)
	reg[31:0] flush_addr_saved; // 保存的冲刷地址
	wire[31:0] flush_addr_cur; // 当前的冲刷地址
	wire[31:0] prdt_addr_cur; // 当前的预测地址
	wire[31:0] pc_nxt; // 下一PC
	reg[31:0] pc_r; // PC寄存器
	reg[31:0] bdcst_bta_saved; // 保存的广播分支目标地址
	
	assign rst_ack = (~prdt_unit_initializing) & to_rst & ibus_access_req_ready;
	assign flush_ack = (~prdt_unit_initializing) & to_flush & (~sys_reset_req) & ibus_access_req_ready;
	
	assign clr_inst_buf = flush_req | sys_reset_req;
	assign ibus_access_req_addr = pc_nxt;
	assign ibus_access_req_tid = inst_id;
	assign ibus_access_req_extra_msg[IBUS_ACCESS_REQ_EXTRA_MSG_IS_FIRST_INST_SID] = first_inst_flag;
	assign ibus_access_req_valid = 
		(~prdt_unit_initializing) & (
			(to_rst | to_flush) | 
			(
				prdt_o_vld & 
				// 排除分支预测特例
				(~(
					prdt_o_btb_hit ? 
						((prdt_o_brc_type == BRANCH_TYPE_JALR) & (~prdt_o_pop_ras)):
						prdt_o_taken
				))
			) | 
			common_pre_if_pending | 
			(btb_hit_jalr_pending & btb_hit_jalr_bdcst_gotten) | 
			(btb_miss_pending & btb_miss_bdcst_gotten)
		);
	
	assign prdt_bdcst_vld = prdt_o_vld;
	assign prdt_bdcst_tid = prdt_o_tid[IBUS_TID_WIDTH-1:0];
	/*
	说明: 对于分支预测特例(BTB缺失, 方向预测为跳; BTB命中, BTB给出的分支指令类型为JALR, RAS出栈标志无效), 
		预测地址会在发射阶段作修正, 这里还是先把分支预测器给出的预测结果广播给总线控制单元
	*/
	assign prdt_bdcst_msg[PRDT_MSG_TARGET_ADDR_SID+31:PRDT_MSG_TARGET_ADDR_SID] = prdt_addr_cur;
	assign prdt_bdcst_msg[PRDT_MSG_BTYPE_SID+2:PRDT_MSG_BTYPE_SID] = prdt_o_brc_type;
	assign prdt_bdcst_msg[PRDT_MSG_IS_TAKEN_SID] = prdt_o_taken;
	assign prdt_bdcst_msg[PRDT_MSG_BTB_HIT_SID] = prdt_o_btb_hit;
	assign prdt_bdcst_msg[PRDT_MSG_BTB_WID_SID+1:PRDT_MSG_BTB_WID_SID] = prdt_o_btb_wid;
	assign prdt_bdcst_msg[PRDT_MSG_BTB_WVLD_SID+3:PRDT_MSG_BTB_WVLD_SID] = prdt_o_btb_wvld;
	assign prdt_bdcst_msg[PRDT_MSG_GLB_SAT_CNT_SID+1:PRDT_MSG_GLB_SAT_CNT_SID] = prdt_o_glb_2bit_sat_cnt;
	assign prdt_bdcst_msg[PRDT_MSG_BTB_BTA_SID+31:PRDT_MSG_BTB_BTA_SID] = prdt_o_btb_bta;
	assign prdt_bdcst_msg[PRDT_MSG_PUSH_RAS_SID] = prdt_o_push_ras;
	assign prdt_bdcst_msg[PRDT_MSG_POP_RAS_SID] = prdt_o_pop_ras;
	
	assign prdt_i_req = ibus_access_req_valid & ibus_access_req_ready;
	assign prdt_i_pc = pc_nxt;
	assign prdt_i_nxt_pc = pc_nxt + 3'd4;
	assign prdt_i_tid = inst_id | 16'h0000;
	
	assign to_rst = sys_reset_req | rst_pre_if_pending;
	assign to_flush = flush_req | flush_pre_if_pending;
	assign flush_addr_cur = 
		flush_pre_if_pending ? 
			flush_addr_saved:
			flush_addr;
	
	assign prdt_addr_cur = 
		prdt_o_taken ? 
			prdt_o_pc:
			(pc_r + 3'd4);
	
	assign pc_nxt = 
		(to_rst | to_flush) ? 
			(
				to_rst ? 
					rst_pc:
					flush_addr_cur
			):(
				(btb_hit_jalr_pending | btb_miss_pending) ? 
					bdcst_bta_saved:
					prdt_addr_cur
			);
	
	// 首条指令(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			first_inst_flag <= 1'b1;
		else if(first_inst_flag)
			first_inst_flag <= # SIM_DELAY ~(ibus_access_req_valid & ibus_access_req_ready);
	end
	
	// 指令ID
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			inst_id <= {IBUS_TID_WIDTH{1'b0}};
		else if(ibus_access_req_valid & ibus_access_req_ready)
			inst_id <= # SIM_DELAY inst_id + 1'b1;
	end
	
	// 复位预取指令(等待标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rst_pre_if_pending <= 1'b0;
		else
			rst_pre_if_pending <= # SIM_DELAY 
				/*
				rst_pre_if_pending ? 
					(~((~prdt_unit_initializing) & ibus_access_req_ready)):
					(sys_reset_req & (prdt_unit_initializing | (~ibus_access_req_ready)))
				*/
				(rst_pre_if_pending | sys_reset_req) & 
				(prdt_unit_initializing | (~ibus_access_req_ready));
	end
	// 冲刷预取指令(等待标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			flush_pre_if_pending <= 1'b0;
		else
			flush_pre_if_pending <= # SIM_DELAY 
				/*
				flush_pre_if_pending ? 
					(~(sys_reset_req | ((~prdt_unit_initializing) & ibus_access_req_ready))):
					(flush_req & (~sys_reset_req) & (prdt_unit_initializing | (~ibus_access_req_ready)))
				*/
				(flush_pre_if_pending | flush_req) & 
				(~(sys_reset_req | ((~prdt_unit_initializing) & ibus_access_req_ready)));
	end
	// 普通预取指令(等待标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			common_pre_if_pending <= 1'b0;
		else
			common_pre_if_pending <= # SIM_DELAY 
				/*
				common_pre_if_pending ? 
					(~(
						(flush_req | sys_reset_req) | 
						((~prdt_unit_initializing) & ibus_access_req_ready)
					)):(
						(~(flush_req | sys_reset_req)) & 
						(prdt_unit_initializing | (~ibus_access_req_ready)) & 
						prdt_o_vld & (
							prdt_o_btb_hit ? 
								(~((prdt_o_brc_type == BRANCH_TYPE_JALR) & (~prdt_o_pop_ras))):
								(~prdt_o_taken)
						)
					)
				*/
				(~(flush_req | sys_reset_req)) & 
				(prdt_unit_initializing | (~ibus_access_req_ready)) & 
				(common_pre_if_pending | (
					prdt_o_vld & (~(
						prdt_o_btb_hit ? 
							((prdt_o_brc_type == BRANCH_TYPE_JALR) & (~prdt_o_pop_ras)):
							prdt_o_taken
					))
				));
	end
	// BTB命中的无法从RAS得到BTA的JALR指令(等待标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			btb_hit_jalr_pending <= 1'b0;
		else
			btb_hit_jalr_pending <= # SIM_DELAY 
				btb_hit_jalr_pending ? 
					(~(
						(flush_req | sys_reset_req) | 
						(btb_hit_jalr_bdcst_gotten & ibus_access_req_ready)
					)):
					/*
					说明: 从取指请求被接受到该标志有效, 需要经过2clk, 但是
						这条指令至多完成了取指阶段, 尚未返回发射阶段的分支信息广播, 因此这是安全的
					*/
					(
						(~(flush_req | sys_reset_req)) & 
						prdt_o_vld & prdt_o_btb_hit & (prdt_o_brc_type == BRANCH_TYPE_JALR) & (~prdt_o_pop_ras)
					);
	end
	// BTB缺失(等待标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			btb_miss_pending <= 1'b0;
		else
			btb_miss_pending <= # SIM_DELAY 
				btb_miss_pending ? 
					(~(
						(flush_req | sys_reset_req) | 
						(btb_miss_bdcst_gotten & ibus_access_req_ready)
					)):
					/*
					说明: 从取指请求被接受到该标志有效, 需要经过2clk, 但是
					      这条指令至多完成了取指阶段, 最快的情况是该标志有效的那个clk得到取指阶段的分支信息广播, 因此这是安全的
					*/
					(
						(~(flush_req | sys_reset_req)) & 
						prdt_o_vld & prdt_o_taken & (~prdt_o_btb_hit)
					);
	end
	
	// BTB命中的无法从RAS得到BTA的JALR指令得到分支信息广播(标志)
	always @(posedge aclk)
	begin
		if(
			btb_hit_jalr_pending ? 
				(
					// 在取指阶段得到"预测基准指令"的类型不是JALR, 可以立刻重新生成预测地址
					(
						brc_bdcst_iftc_vld & (brc_bdcst_iftc_tid == prdt_o_tid[IBUS_TID_WIDTH-1:0]) & 
						(~brc_bdcst_iftc_is_jalr_inst)
					) | 
					// 否则就继续等待发射阶段的分支信息广播
					(brc_bdcst_luc_vld & (brc_bdcst_luc_tid == prdt_o_tid[IBUS_TID_WIDTH-1:0]))
				):
				(
					(~(flush_req | sys_reset_req)) & 
					prdt_o_vld & prdt_o_btb_hit & (prdt_o_brc_type == BRANCH_TYPE_JALR) & (~prdt_o_pop_ras)
				)
		)
			btb_hit_jalr_bdcst_gotten <= # SIM_DELAY btb_hit_jalr_pending;
	end
	// BTB缺失得到分支信息广播(标志)
	always @(posedge aclk)
	begin
		if(
			btb_miss_pending ? 
				(
					// 在取指阶段得到"预测基准指令"的类型不是JALR, 可以立刻重新生成预测地址
					(
						brc_bdcst_iftc_vld & (brc_bdcst_iftc_tid == prdt_o_tid[IBUS_TID_WIDTH-1:0]) & 
						(~brc_bdcst_iftc_is_jalr_inst)
					) | 
					// 否则就继续等待发射阶段的分支信息广播
					(brc_bdcst_luc_vld & (brc_bdcst_luc_tid == prdt_o_tid[IBUS_TID_WIDTH-1:0]))
				):
				(
					(~(flush_req | sys_reset_req)) & 
					prdt_o_vld & prdt_o_taken & (~prdt_o_btb_hit)
				)
		)
			btb_miss_bdcst_gotten <= # SIM_DELAY btb_miss_pending;
	end
	
	// 保存的冲刷地址
	always @(posedge aclk)
	begin
		if(flush_req & (~sys_reset_req) & (prdt_unit_initializing | (~ibus_access_req_ready)))
			flush_addr_saved <= # SIM_DELAY flush_addr;
	end
	
	// PC寄存器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			// 说明: PC寄存器的异步复位值无意义
			pc_r <= 32'h0000_0000;
		else if(ibus_access_req_valid & ibus_access_req_ready)
			pc_r <= # SIM_DELAY pc_nxt;
	end
	
	// 保存的广播分支目标地址
	always @(posedge aclk)
	begin
		if(
			(btb_hit_jalr_pending | btb_miss_pending) & 
			(
				(
					brc_bdcst_iftc_vld & (brc_bdcst_iftc_tid == prdt_o_tid[IBUS_TID_WIDTH-1:0]) & 
					(~brc_bdcst_iftc_is_jalr_inst)
				) | 
				(
					brc_bdcst_luc_vld & (brc_bdcst_luc_tid == prdt_o_tid[IBUS_TID_WIDTH-1:0]) & 
					brc_bdcst_luc_is_jalr_inst
				)
			)
		)
			bdcst_bta_saved <= # SIM_DELAY 
				(
					brc_bdcst_iftc_vld & (brc_bdcst_iftc_tid == prdt_o_tid[IBUS_TID_WIDTH-1:0]) & 
					(~brc_bdcst_iftc_is_jalr_inst)
				) ? 
					brc_bdcst_iftc_bta:
					brc_bdcst_luc_bta;
	end
	
	/** 未使用的信号 **/
	wire unused;
	
	assign unused = |prdt_o_glb_speculative_ghr;
	
endmodule
