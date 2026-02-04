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
本模块: 分支目标缓存

描述:
BTB置换采取定向(外部给出)或随机原则(使用LFSR实现)
若查询请求指示信号无效, 那么查询结果保持不变

BTB条目 -> 
	[PC标签(PC_TAG_WIDTH bit)], 分支目标地址(32bit), RAS出栈标志(1bit), RAS压栈标志(1bit),
	分支指令类型(3bit), BTFN跳转方向(1bit), [有效标志(1bit)]

注意：
BTB存储器的读延迟为1clk
BTB需要进行初始化/清零, BTB查询/置换只能在初始化完成后进行

协议:
MEM MASTER

作者: 陈家耀
日期: 2026/01/22
********************************************************************/


module panda_risc_v_btb #(
	parameter integer BTB_WAY_N = 2, // BTB路数(1 | 2 | 4)
	parameter integer BTB_ENTRY_N = 512, // BTB项数(<=65536)
	parameter integer PC_TAG_WIDTH = 21, // PC标签的位宽(不要修改, 应为30 - clogb2(BTB_ENTRY_N))
	parameter integer BTB_MEM_WIDTH = PC_TAG_WIDTH + 32 + 3 + 1 + 1 + 2, // BTB存储器的数据位宽(不要修改)
	parameter NO_INIT_BTB = "false", // 是否无需初始化BTB存储器
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// BTB正在初始化(标志)
	output wire btb_initializing,
	
	// BTB查询
	input wire btb_query_i_req, // 查询请求
	input wire[31:0] btb_query_i_pc, // 待查询的PC
	input wire[31:0] btb_query_i_nxt_pc, // 待查询的下一PC
	output wire btb_query_o_hit, // 查询命中
	output wire[1:0] btb_query_o_wid, // 查询命中的缓存路编号
	output wire[BTB_WAY_N-1:0] btb_query_o_wvld, // 查询得到的缓存路有效标志
	output wire[2:0] btb_query_o_btype, // 查询得到的分支指令类型
	output wire btb_query_o_push_ras, // 查询得到的RAS压栈标志
	output wire btb_query_o_pop_ras, // 查询得到的RAS出栈标志
	output wire[31:0] btb_query_o_bta, // 查询得到的分支目标地址
	output wire btb_query_o_jpdir, // 查询得到的BTFN跳转方向(1'b1 -> 向后, 1'b0 -> 向前)
	output wire[31:0] btb_query_o_nxt_pc, // 查询得到的下一PC
	output wire btb_query_o_vld, // 查询结果有效
	
	// BTB置换
	input wire btb_rplc_req, // 置换请求
	input wire btb_rplc_strgy, // 置换策略(1'b0 -> 随机, 1'b1 -> 定向)
	input wire[1:0] btb_rplc_sel_wid, // 置换选定的缓存路编号
	input wire[31:0] btb_rplc_pc, // 分支指令对应的PC
	input wire[2:0] btb_rplc_btype, // 分支指令类型
	input wire[31:0] btb_rplc_bta, // 分支指令对应的目标地址
	input wire btb_rplc_jpdir, // BTFN跳转方向(1'b1 -> 向后, 1'b0 -> 向前)
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
	
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
    end
    endfunction
	
	/** 常量 **/
	// 分支指令类型常量
	localparam BRANCH_TYPE_JAL = 3'b000; // JAL指令
	localparam BRANCH_TYPE_JALR = 3'b001; // JALR指令
	localparam BRANCH_TYPE_B = 3'b010; // B指令
	// 分支指令跳转方向
	localparam BRANCH_JUMP_FWD = 1'b0; // 向前跳
	localparam BRANCH_JUMP_BCK = 1'b1; // 向后跳
	
	/** 初始化BTB **/
	// BTB初始化状态
	reg[2:0] btb_init_sts;
	// [初始化BTB给出的MEM端口]
	wire[BTB_WAY_N-1:0] btb_mem_init_en;
	wire[BTB_WAY_N-1:0] btb_mem_init_wen;
	reg[clogb2(BTB_ENTRY_N-1):0] btb_mem_init_addr;
	wire[BTB_MEM_WIDTH-1:0] btb_mem_init_din;
	
	assign btb_initializing = ~btb_init_sts[2];
	
	assign btb_mem_init_en = {BTB_WAY_N{btb_init_sts[1]}};
	assign btb_mem_init_wen = {BTB_WAY_N{btb_init_sts[1]}};
	assign btb_mem_init_din = {
		{PC_TAG_WIDTH{1'bx}}, // PC标签
		32'hxxxx_xxxx, // 分支目标地址
		1'bx, // RAS出栈标志
		1'bx, // RAS压栈标志
		3'bxxx, // 分支指令类型
		1'bx, // BTFN跳转方向(1'b1 -> 向后, 1'b0 -> 向前)
		1'b0 // 有效标志
	};
	
	// BTB初始化状态
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			btb_init_sts <= 
				(NO_INIT_BTB == "false") ? 
					3'b001:
					3'b100;
		else if(
			btb_init_sts[0] | 
			(btb_init_sts[1] & (btb_mem_init_addr == (BTB_ENTRY_N-1)))
		)
			btb_init_sts <= # SIM_DELAY btb_init_sts << 1;
	end
	
	// BTB存储器初始化地址
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			btb_mem_init_addr <= 0;
		else if(btb_init_sts[1])
			btb_mem_init_addr <= # SIM_DELAY btb_mem_init_addr + 1;
	end
	
	/** BTB查询 **/
	// [查询BTB项给出的MEM端口]
	wire[BTB_WAY_N-1:0] btb_mem_query_en;
	wire[BTB_WAY_N-1:0] btb_mem_query_wen;
	wire[clogb2(BTB_ENTRY_N-1):0] btb_mem_query_addr;
	wire[BTB_MEM_WIDTH-1:0] btb_mem_query_din;
	wire[BTB_MEM_WIDTH-1:0] btb_mem_query_dout[0:BTB_WAY_N-1];
	// 待查询的PC的标签
	reg[PC_TAG_WIDTH-1:0] btb_query_pc_tag_d1;
	// BTB项查询结果
	wire[BTB_WAY_N-1:0] btb_query_hit_vec; // 命中情况(向量)
	reg[31:0] btb_query_o_nxt_pc_r; // 查询得到的下一PC
	reg btb_query_o_vld_r; // 查询结果有效
	
	assign btb_mem_query_en = {BTB_WAY_N{btb_init_sts[2] & btb_query_i_req}};
	assign btb_mem_query_wen = {BTB_WAY_N{1'b0}};
	assign btb_mem_query_addr = btb_query_i_pc[clogb2(BTB_ENTRY_N-1)+2:2];
	assign btb_mem_query_din = {BTB_MEM_WIDTH{1'bx}};
	
	assign btb_query_o_hit = |btb_query_hit_vec;
	// 问题: 考虑会不会出现某个Set有多个Tag相同的Line的情况, 是否要使用优先编码器???
	assign btb_query_o_wid = 
		(BTB_WAY_N == 1) ? 2'b00:
		(BTB_WAY_N == 2) ? (btb_query_hit_vec[0] ? 2'b00:2'b01):
		                   (btb_query_hit_vec[0] ? 2'b00:(btb_query_hit_vec[1] ? 2'b01:(btb_query_hit_vec[2] ? 2'b10:2'b11)));
	assign {btb_query_o_bta, btb_query_o_pop_ras, btb_query_o_push_ras, btb_query_o_btype, btb_query_o_jpdir} = 
		btb_mem_query_dout[btb_query_o_wid][38:1];
	assign btb_query_o_nxt_pc = btb_query_o_nxt_pc_r;
	assign btb_query_o_vld = btb_query_o_vld_r;
	
	genvar btb_mem_query_i;
	generate
		for(btb_mem_query_i = 0;btb_mem_query_i < BTB_WAY_N;btb_mem_query_i = btb_mem_query_i + 1)
		begin:btb_mem_query_blk
			assign btb_query_o_wvld[btb_mem_query_i] = btb_mem_query_dout[btb_mem_query_i][0];
			
			assign btb_mem_query_dout[btb_mem_query_i] = 
				btb_mem_doutb[BTB_MEM_WIDTH*btb_mem_query_i+BTB_MEM_WIDTH-1:BTB_MEM_WIDTH*btb_mem_query_i];
			
			assign btb_query_hit_vec[btb_mem_query_i] = 
				btb_mem_query_dout[btb_mem_query_i][0] & // BTB项有效
				(btb_mem_query_dout[btb_mem_query_i][39+PC_TAG_WIDTH-1:39] == btb_query_pc_tag_d1); // PC标签匹配
		end
	endgenerate
	
	// 待查询的PC的标签
	always @(posedge aclk)
	begin
		if(btb_init_sts[2] & btb_query_i_req)
			btb_query_pc_tag_d1 <= # SIM_DELAY btb_query_i_pc[31:32-PC_TAG_WIDTH];
	end
	
	// 查询得到的下一PC
	always @(posedge aclk)
	begin
		if(btb_init_sts[2] & btb_query_i_req)
			btb_query_o_nxt_pc_r <= # SIM_DELAY btb_query_i_nxt_pc;
	end
	
	// 查询结果有效
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			btb_query_o_vld_r <= 1'b0;
		else
			btb_query_o_vld_r <= # SIM_DELAY btb_init_sts[2] & btb_query_i_req;
	end
	
	/** BTB置换 **/
	// [分支指令对应的PC]
	wire[clogb2(BTB_ENTRY_N-1):0] btb_rplc_pc_index; // 分支指令对应PC的index部分
	wire[PC_TAG_WIDTH-1:0] btb_rplc_pc_tag; // 分支指令对应PC的tag部分
	// 当前置换的BTB路编号
	reg[7:0] btb_rplc_lfsr;
	wire[clogb2(BTB_WAY_N-1):0] btb_rplc_wid;
	// [置换BTB项给出的MEM端口]
	wire[BTB_WAY_N-1:0] btb_mem_rplc_en;
	wire[BTB_WAY_N-1:0] btb_mem_rplc_wen;
	wire[clogb2(BTB_ENTRY_N-1):0] btb_mem_rplc_addr;
	wire[BTB_MEM_WIDTH-1:0] btb_mem_rplc_din;
	
	assign {btb_rplc_pc_tag, btb_rplc_pc_index} = btb_rplc_pc[31:2];
	
	assign btb_rplc_wid = 
		(BTB_WAY_N == 1) ? 
			0:
			(btb_rplc_strgy ? btb_rplc_sel_wid[clogb2(BTB_WAY_N-1):0]:btb_rplc_lfsr[clogb2(BTB_WAY_N-1):0]);
	
	assign btb_mem_rplc_en = 
		{BTB_WAY_N{btb_init_sts[2] & btb_rplc_req}} & (
			(BTB_WAY_N == 1) ? 1'b1:
			(BTB_WAY_N == 2) ? {btb_rplc_wid == 1, btb_rplc_wid == 0}:
		                       {btb_rplc_wid == 3, btb_rplc_wid == 2, btb_rplc_wid == 1, btb_rplc_wid == 0}
		);
	assign btb_mem_rplc_wen = 
		(BTB_WAY_N == 1) ? 1'b1:
		(BTB_WAY_N == 2) ? {btb_rplc_wid == 1, btb_rplc_wid == 0}:
		                   {btb_rplc_wid == 3, btb_rplc_wid == 2, btb_rplc_wid == 1, btb_rplc_wid == 0};
	assign btb_mem_rplc_addr = btb_rplc_pc_index;
	assign btb_mem_rplc_din = {
		btb_rplc_pc_tag, // PC标签
		btb_rplc_bta, // 分支目标地址
		btb_rplc_pop_ras, // RAS出栈标志
		btb_rplc_push_ras, // RAS压栈标志
		btb_rplc_btype, // 分支指令类型
		btb_rplc_jpdir, // BTFN跳转方向(1'b1 -> 向后, 1'b0 -> 向前)
		1'b1 // 有效标志
	};
	
	// 当前置换的BTB路编号(LFSR)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			btb_rplc_lfsr <= 1;
		else if(btb_init_sts[2] & btb_rplc_req & (~btb_rplc_strgy))
			btb_rplc_lfsr <= # SIM_DELAY 
				{btb_rplc_lfsr[6:0], btb_rplc_lfsr[7] ^ btb_rplc_lfsr[5] ^ btb_rplc_lfsr[4] ^ btb_rplc_lfsr[3]};
	end
	
	/**
	BTB存储器接口
	
	端口A: 用于初始化或置换
	端口B: 用于查询
	**/
	assign btb_mem_clka = {BTB_WAY_N{aclk}};
	assign btb_mem_ena = btb_init_sts[2] ? btb_mem_rplc_en:btb_mem_init_en;
	assign btb_mem_wea = btb_init_sts[2] ? btb_mem_rplc_wen:btb_mem_init_wen;
	
	assign btb_mem_clkb = {BTB_WAY_N{aclk}};
	assign btb_mem_enb = btb_mem_query_en;
	assign btb_mem_web = btb_mem_query_wen;
	
	genvar btb_mem_i;
	generate
		for(btb_mem_i = 0;btb_mem_i < BTB_WAY_N;btb_mem_i = btb_mem_i + 1)
		begin:btb_mem_blk
			assign btb_mem_addra[btb_mem_i*16+15:btb_mem_i*16] = 
				(btb_init_sts[2] ? btb_mem_rplc_addr:btb_mem_init_addr) | 16'h0000;
			assign btb_mem_dina[btb_mem_i*BTB_MEM_WIDTH+(BTB_MEM_WIDTH-1):btb_mem_i*BTB_MEM_WIDTH] = 
				btb_init_sts[2] ? btb_mem_rplc_din:btb_mem_init_din;
			
			assign btb_mem_addrb[btb_mem_i*16+15:btb_mem_i*16] = 
				btb_mem_query_addr | 16'h0000;
			assign btb_mem_dinb[btb_mem_i*BTB_MEM_WIDTH+(BTB_MEM_WIDTH-1):btb_mem_i*BTB_MEM_WIDTH] = 
				btb_mem_query_din;
		end
	endgenerate
	
endmodule
