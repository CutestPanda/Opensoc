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
本模块: Cache路访问热度记录表

描述:
对每个Cache条目记录各个Way的访问频率排序

使用1个位宽 = max(clogb2(CACHE_WAY_N), 1)*CACHE_WAY_N、深度 = CACHE_ENTRY_N的简单双口RAM作为记录存储器

注意：
RAM的读时延应为1clk
读出最近最少使用项的索引相对于热度表使能具有1clk的读时延, 且上1clk的热度更新并未生效

协议:
MEM MASTER

作者: 陈家耀
日期: 2025/04/14
********************************************************************/


module dcache_way_access_hot_record #(
	parameter integer CACHE_ENTRY_N = 512, // 缓存存储条目数
	parameter integer CACHE_WAY_N = 4, // 缓存路数(1 | 2 | 4 | 8)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 查询或更新热度
	input wire hot_tb_en, // 热度表使能
	input wire hot_tb_upd_en, // 热度表更新使能
	input wire[31:0] cache_index, // 缓存项索引号
	input wire[2:0] cache_access_wid, // 本次访问的缓存路编号
	input wire to_init_hot_item, // 初始化热度项(标志)
	input wire to_swp_lru_item, // 置换最近最少使用项(标志)
	output wire[2:0] hot_tb_lru_wid, // 最近最少使用项的缓存路编号
	
	// 记录存储器接口
	// [存储器写端口]
	output wire hot_sram_clk_a,
	output wire hot_sram_wen_a,
	output wire[31:0] hot_sram_waddr_a,
	output wire[23:0] hot_sram_din_a,
	// [存储器读端口]
	output wire hot_sram_clk_b,
	output wire hot_sram_ren_b,
	output wire[31:0] hot_sram_raddr_b,
	input wire[23:0] hot_sram_dout_b
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
	localparam integer WID_WIDTH = 
		(CACHE_WAY_N == 1) ? 1:clogb2(CACHE_WAY_N); // 缓存路编号的位宽
	
	/** 写热度表 **/
	reg hot_tb_wen; // 热度表写使能
	reg[clogb2(CACHE_ENTRY_N-1):0] hot_tb_upd_eid; // 待更新项的索引
	reg[WID_WIDTH-1:0] hot_tb_upd_wid; // 待提升热度的缓存路编号
	reg to_init_hot_item_r; // 初始化热度项(标志)
	reg to_swp_lru_item_r; // 置换最近最少使用项(标志)
	wire[WID_WIDTH*CACHE_WAY_N-1:0] hot_tb_dout; // 热度表读数据
	wire[WID_WIDTH*CACHE_WAY_N-1:0] hot_code_new; // 新的访问频率排序
	
	assign hot_sram_clk_a = aclk;
	assign hot_sram_wen_a = hot_tb_wen;
	assign hot_sram_waddr_a = hot_tb_upd_eid | 32'h0000_0000;
	assign hot_sram_din_a = hot_code_new | 24'h000000;
	
	assign hot_code_new = 
		to_init_hot_item_r ? (
			(CACHE_WAY_N == 1) ? 1'b0:
			(CACHE_WAY_N == 2) ? 2'b10:
			(CACHE_WAY_N == 4) ? 8'b11_10_01_00:
			                     24'b111_110_101_100_011_010_001_000
		):
		to_swp_lru_item_r ? (
			(CACHE_WAY_N == 1) ? 1'b0:
			(CACHE_WAY_N == 2) ? {hot_tb_dout[0], hot_tb_dout[1]}:
			(CACHE_WAY_N == 4) ? {hot_tb_dout[1:0], hot_tb_dout[7:2]}:
			                     {hot_tb_dout[2:0], hot_tb_dout[23:3]}
		):(
			(CACHE_WAY_N == 1) ? 1'b0:
			(CACHE_WAY_N == 2) ? (
				(hot_tb_dout[0] == hot_tb_upd_wid) ? {hot_tb_dout[0], hot_tb_dout[1]}:
														 hot_tb_dout[1:0]
			):
			(CACHE_WAY_N == 4) ? (
				(hot_tb_dout[1:0] == hot_tb_upd_wid) ? {hot_tb_dout[1:0], hot_tb_dout[7:2]}:
				(hot_tb_dout[3:2] == hot_tb_upd_wid) ? {hot_tb_dout[3:2], hot_tb_dout[7:4], hot_tb_dout[1:0]}:
				(hot_tb_dout[5:4] == hot_tb_upd_wid) ? {hot_tb_dout[5:4], hot_tb_dout[7:6], hot_tb_dout[3:0]}:
														   hot_tb_dout[7:0]
			):(
				(hot_tb_dout[2:0] == hot_tb_upd_wid)   ? {hot_tb_dout[2:0], hot_tb_dout[23:3]}:
				(hot_tb_dout[5:3] == hot_tb_upd_wid)   ? {hot_tb_dout[5:3], hot_tb_dout[23:6], hot_tb_dout[2:0]}:
				(hot_tb_dout[8:6] == hot_tb_upd_wid)   ? {hot_tb_dout[8:6], hot_tb_dout[23:9], hot_tb_dout[5:0]}:
				(hot_tb_dout[11:9] == hot_tb_upd_wid)  ? {hot_tb_dout[11:9], hot_tb_dout[23:12], hot_tb_dout[8:0]}:
				(hot_tb_dout[14:12] == hot_tb_upd_wid) ? {hot_tb_dout[14:12], hot_tb_dout[23:15], hot_tb_dout[11:0]}:
				(hot_tb_dout[17:15] == hot_tb_upd_wid) ? {hot_tb_dout[17:15], hot_tb_dout[23:18], hot_tb_dout[14:0]}:
				(hot_tb_dout[20:18] == hot_tb_upd_wid) ? {hot_tb_dout[20:18], hot_tb_dout[23:21], hot_tb_dout[17:0]}:
															 hot_tb_dout[23:0]
			)
		);
	
	// 热度表写使能
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			hot_tb_wen <= 1'b0;
		else
			hot_tb_wen <= # SIM_DELAY hot_tb_en & hot_tb_upd_en;
	end
	
	// 待更新项的索引, 待提升热度的缓存路编号, 初始化热度项(标志), 置换最近最少使用项(标志)
	always @(posedge aclk)
	begin
		if(hot_tb_en & hot_tb_upd_en)
		begin
			hot_tb_upd_eid <= # SIM_DELAY cache_index[clogb2(CACHE_ENTRY_N-1):0];
			hot_tb_upd_wid <= # SIM_DELAY (CACHE_WAY_N == 1) ? 0:cache_access_wid[WID_WIDTH-1:0];
			to_init_hot_item_r <= # SIM_DELAY to_init_hot_item;
			to_swp_lru_item_r <= # SIM_DELAY to_swp_lru_item;
		end
	end
	
	/** 读热度表 **/
	reg sel_hot_code_new; // 选择新的访问频率排序(标志)
	reg[WID_WIDTH*CACHE_WAY_N-1:0] hot_code_new_d1; // 延迟1clk的新的访问频率排序
	
	assign hot_sram_clk_b = aclk;
	assign hot_sram_ren_b = hot_tb_en;
	assign hot_sram_raddr_b = cache_index[clogb2(CACHE_ENTRY_N-1):0] | 32'h0000_0000;
	assign hot_tb_lru_wid = hot_tb_dout[WID_WIDTH-1:0] | 3'b000;
	
	assign hot_tb_dout = sel_hot_code_new ? hot_code_new_d1:hot_sram_dout_b[WID_WIDTH*CACHE_WAY_N-1:0];
	
	// 选择新的访问频率排序(标志)
	always @(posedge aclk)
	begin
		if(hot_tb_en)
			sel_hot_code_new <= # SIM_DELAY hot_tb_wen & (hot_tb_upd_eid == cache_index[clogb2(CACHE_ENTRY_N-1):0]);
	end
	
	// 延迟1clk的新的访问频率排序
	always @(posedge aclk)
	begin
		if(hot_tb_en & hot_tb_wen & (hot_tb_upd_eid == cache_index[clogb2(CACHE_ENTRY_N-1):0]))
			hot_code_new_d1 <= # SIM_DELAY hot_code_new;
	end
	
endmodule
