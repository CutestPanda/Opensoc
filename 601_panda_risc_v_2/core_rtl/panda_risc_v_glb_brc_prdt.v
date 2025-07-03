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
本模块: 基于全局历史的分支预测

描述:
只使用1个分支模式历史表(PHT)
生成PHT地址时考虑PC和GHR的异或
若查询请求指示信号无效, 那么查询结果保持不变
支持PHT存储器使用寄存器组或SRAM实现

注意：
PHT存储器的读延迟为1clk
若PHT使用SRAM实现, 则PHT需要进行初始化, 全局历史分支预测查询/更新只能在初始化完成后进行

协议:
MEM MASTER

作者: 陈家耀
日期: 2025/06/10
********************************************************************/


module panda_risc_v_glb_brc_prdt #(
	parameter EN_PC_FOR_PHT_ADDR = "true", // 生成PHT地址时是否考虑PC
	parameter EN_GHR_FOR_PHT_ADDR = "true", // 生成PHT地址时是否考虑GHR
	parameter integer GHR_WIDTH = 8, // 全局分支历史寄存器的位宽(<=16)
	parameter PHT_MEM_IMPL = "reg", // PHT存储器的实现方式(reg | sram)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// GHR控制/状态
	input wire on_clr_retired_ghr, // 清零退休GHR
	input wire on_upd_retired_ghr, // 退休GHR更新指示
	input wire retired_ghr_shift_in, // 退休GHR移位输入
	input wire rstr_speculative_ghr, // 恢复推测GHR指示
	input wire on_upd_speculative_ghr, // 推测GHR更新指示
	input wire speculative_ghr_shift_in, // 推测GHR移位输入
	output wire[GHR_WIDTH-1:0] speculative_ghr_o, // 最新的推测GHR
	output wire[GHR_WIDTH-1:0] retired_ghr_o, // 当前的退休GHR
	
	// PHT正在初始化(标志)
	output wire pht_initializing,
	
	// 全局历史分支预测查询
	input wire query_i_req, // 查询请求
	input wire[31:0] query_i_pc, // 待查询的PC
	output wire[1:0] query_o_2bit_sat_cnt, // 查询得到的2bit饱和计数器
	output wire query_o_vld, // 查询结果有效(指示)
	
	// 全局历史分支预测更新
	input wire update_i_req, // 更新请求
	input wire[31:0] update_i_pc, // 待更新项的PC
	input wire[GHR_WIDTH-1:0] update_i_ghr, // 待更新项的GHR
	// 说明: PHT_MEM_IMPL == "sram"时可用
	input wire[1:0] update_i_2bit_sat_cnt, // 待更新项的2bit饱和计数器
	// 说明: PHT_MEM_IMPL == "reg"时可用
	input wire update_i_brc_taken, // 待更新项的实际分支跳转方向
	
	// PHT存储器
	// 说明: PHT_MEM_IMPL == "sram"时可用
	// [端口A]
	output wire pht_mem_clka,
	output wire pht_mem_ena,
	output wire pht_mem_wea,
	output wire[15:0] pht_mem_addra,
	output wire[1:0] pht_mem_dina,
	input wire[1:0] pht_mem_douta,
	// [端口B]
	output wire pht_mem_clkb,
	output wire pht_mem_enb,
	output wire pht_mem_web,
	output wire[15:0] pht_mem_addrb,
	output wire[1:0] pht_mem_dinb,
	input wire[1:0] pht_mem_doutb,
	
	// PHT存储器
	// 说明: PHT_MEM_IMPL == "reg"时可用
	// [读端口]
	output wire pht_mem_ren,
	output wire[15:0] pht_mem_raddr,
	input wire[1:0] pht_mem_dout,
	// [更新端口]
	output wire pht_mem_upd_en,
	output wire[15:0] pht_mem_upd_addr,
	output wire pht_mem_upd_brc_taken
);
	
	/** 全局分支历史寄存器(GHR) **/
	reg[GHR_WIDTH-1:0] speculative_ghr; // 推测GHR
	reg[GHR_WIDTH-1:0] retired_ghr; // 退休GHR
	wire[GHR_WIDTH-1:0] speculative_ghr_nxt; // 下一推测GHR
	wire[GHR_WIDTH-1:0] retired_ghr_nxt; // 下一退休GHR
	
	assign speculative_ghr_o = speculative_ghr_nxt;
	assign retired_ghr_o = retired_ghr;
	
	/*
	说明: 由于前级从发送取指请求到更新此GHR有1clk时延, 因此将"下一推测GHR"作为PHT读地址
		由于复位/冲刷时是对复位/冲刷地址处的指令作分支预测, 因此将"下一退休GHR"作为PHT读地址
	*/
	assign speculative_ghr_nxt = 
		rstr_speculative_ghr ? 
			retired_ghr_nxt:(
				on_upd_speculative_ghr ? 
					{speculative_ghr[GHR_WIDTH-2:0], speculative_ghr_shift_in}:
					speculative_ghr
			);
	assign retired_ghr_nxt = 
		{GHR_WIDTH{~on_clr_retired_ghr}} & 
		(
			on_upd_retired_ghr ? 
				{retired_ghr[GHR_WIDTH-2:0], retired_ghr_shift_in}:
				retired_ghr
		);
	
	// 推测GHR
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			speculative_ghr <= {GHR_WIDTH{1'b0}};
		else if(rstr_speculative_ghr | on_upd_speculative_ghr)
			speculative_ghr <= # SIM_DELAY speculative_ghr_nxt;
	end
	
	// 退休GHR
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			retired_ghr <= {GHR_WIDTH{1'b0}};
		else if(on_clr_retired_ghr | on_upd_retired_ghr)
			retired_ghr <= # SIM_DELAY retired_ghr_nxt;
	end
	
	/** 初始化PHT **/
	// PHT初始化状态
	reg[2:0] pht_init_sts;
	// [初始化PHT给出的MEM端口]
	wire pht_mem_init_en;
	wire pht_mem_init_wen;
	reg[GHR_WIDTH-1:0] pht_mem_init_addr;
	wire[1:0] pht_mem_init_din;
	wire[1:0] pht_mem_init_dout;
	
	assign pht_initializing = (PHT_MEM_IMPL == "sram") & (~pht_init_sts[2]);
	
	assign pht_mem_init_en = pht_init_sts[1];
	assign pht_mem_init_wen = pht_init_sts[1];
	assign pht_mem_init_din = 2'b01; // 初始为弱不跳
	assign pht_mem_init_dout = pht_mem_douta;
	
	// PHT初始化状态
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			pht_init_sts <= 3'b001;
		else if(
			(PHT_MEM_IMPL == "sram") & 
			(
				pht_init_sts[0] | 
				(pht_init_sts[1] & (&pht_mem_init_addr))
			)
		)
			pht_init_sts <= # SIM_DELAY pht_init_sts << 1;
	end
	
	// PHT存储器初始化地址
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			pht_mem_init_addr <= 0;
		else if(
			(PHT_MEM_IMPL == "sram") & 
			pht_init_sts[1]
		)
			pht_mem_init_addr <= # SIM_DELAY pht_mem_init_addr + 1;
	end
	
	/** 全局历史分支预测查询 **/
	reg query_o_vld_r; // 查询结果有效(指示)
	wire[GHR_WIDTH-1:0] pht_query_addr; // PHT查询地址
	// [查询给出的MEM端口]
	wire pht_mem_query_en;
	wire pht_mem_query_wen;
	wire[GHR_WIDTH-1:0] pht_mem_query_addr;
	wire[1:0] pht_mem_query_din;
	wire[1:0] pht_mem_query_dout;
	
	assign query_o_2bit_sat_cnt = 
		(PHT_MEM_IMPL == "reg") ? 
			pht_mem_dout:
			pht_mem_query_dout;
	assign query_o_vld = query_o_vld_r;
	
	assign pht_query_addr = 
		({GHR_WIDTH{EN_PC_FOR_PHT_ADDR == "true"}} & query_i_pc[2+GHR_WIDTH-1:2]) ^ 
		({GHR_WIDTH{EN_GHR_FOR_PHT_ADDR == "true"}} & speculative_ghr_nxt);
	
	assign pht_mem_query_en = query_i_req & pht_init_sts[2];
	assign pht_mem_query_wen = 1'b0;
	assign pht_mem_query_addr = pht_query_addr;
	assign pht_mem_query_din = 2'b00;
	assign pht_mem_query_dout = pht_mem_doutb;
	
	assign pht_mem_ren = (PHT_MEM_IMPL == "reg") & query_i_req;
	assign pht_mem_raddr = 
		(PHT_MEM_IMPL == "reg") ? 
			(pht_query_addr | 16'h0000):
			16'h0000;
	
	// 查询结果有效(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			query_o_vld_r <= 1'b0;
		else
			query_o_vld_r <= # SIM_DELAY query_i_req & (~pht_initializing);
	end
	
	/** 全局历史分支预测更新 **/
	// [更新给出的MEM端口]
	wire pht_mem_update_en;
	wire pht_mem_update_wen;
	wire[GHR_WIDTH-1:0] pht_mem_update_addr;
	wire[1:0] pht_mem_update_din;
	wire[1:0] pht_mem_update_dout;
	
	assign pht_mem_update_en = update_i_req & pht_init_sts[2];
	assign pht_mem_update_wen = update_i_req & pht_init_sts[2];
	assign pht_mem_update_addr = 
		({GHR_WIDTH{EN_PC_FOR_PHT_ADDR == "true"}} & update_i_pc[2+GHR_WIDTH-1:2]) ^ 
		({GHR_WIDTH{EN_GHR_FOR_PHT_ADDR == "true"}} & update_i_ghr);
	assign pht_mem_update_din = update_i_2bit_sat_cnt;
	assign pht_mem_update_dout = pht_mem_douta;
	
	assign pht_mem_upd_en = 
		(PHT_MEM_IMPL == "reg") & update_i_req;
	assign pht_mem_upd_addr = 
		(PHT_MEM_IMPL == "reg") ? 
			(pht_mem_update_addr | 16'h0000):
			16'h0000;
	assign pht_mem_upd_brc_taken = 
		(PHT_MEM_IMPL == "reg") & update_i_brc_taken;
	
	/** PHT存储器(SRAM实现方式) **/
	assign pht_mem_clka = 
		(PHT_MEM_IMPL == "sram") & aclk;
	assign pht_mem_ena = 
		(PHT_MEM_IMPL == "sram") & (pht_init_sts[2] ? pht_mem_update_en:pht_mem_init_en);
	assign pht_mem_wea = 
		(PHT_MEM_IMPL == "sram") & (pht_init_sts[2] ? pht_mem_update_wen:pht_mem_init_wen);
	assign pht_mem_addra = 
		(PHT_MEM_IMPL == "sram") ? 
			((pht_init_sts[2] ? pht_mem_update_addr:pht_mem_init_addr) | 16'h0000):
			16'h0000;
	assign pht_mem_dina = 
		(PHT_MEM_IMPL == "sram") ? 
			(pht_init_sts[2] ? pht_mem_update_din:pht_mem_init_din):
			2'b00;
	
	assign pht_mem_clkb = 
		(PHT_MEM_IMPL == "sram") & aclk;
	assign pht_mem_enb = 
		(PHT_MEM_IMPL == "sram") & pht_mem_query_en;
	assign pht_mem_web = 
		(PHT_MEM_IMPL == "sram") & pht_mem_query_wen;
	assign pht_mem_addrb = 
		(PHT_MEM_IMPL == "sram") ? 
			(pht_mem_query_addr | 16'h0000):
			16'h0000;
	assign pht_mem_dinb = 
		(PHT_MEM_IMPL == "sram") ? 
			pht_mem_query_din:
			2'b00;
	
endmodule
