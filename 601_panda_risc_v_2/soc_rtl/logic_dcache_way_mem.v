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
本模块: 数据Cache逻辑缓存路存储器

描述:
一路Cache的逻辑数据/标签存储器
使用4*CACHE_LINE_WORD_N个位宽 = 8、深度 = CACHE_ENTRY_N的单口RAM作为数据存储器, 总容量为CACHE_ENTRY_N*4*CACHE_LINE_WORD_N字节
使用1个位宽 = CACHE_TAG_WIDTH+2、深度 = CACHE_ENTRY_N的单口RAM作为标签存储器, 总容量为CACHE_ENTRY_N*(CACHE_TAG_WIDTH+2)字节

注意：
RAM的读时延应为1clk, 读写模式应为read_first

协议:
MEM MASTER

作者: 陈家耀
日期: 2025/04/13
********************************************************************/


module logic_dcache_way_mem #(
	parameter integer CACHE_ENTRY_N = 512, // 缓存存储条目数
	parameter integer CACHE_LINE_WORD_N = 8, // 每个缓存行的字数(1 | 2 | 4 | 8 | 16)
	parameter integer CACHE_TAG_WIDTH = 12, // 缓存标签位数
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟
	input wire aclk,
	
	// 逻辑缓存路接口
	// [数据存储器]
	input wire cache_data_en, // 数据存储器使能
	input wire[4*CACHE_LINE_WORD_N-1:0] cache_data_byte_wen, // 数据存储器字节写使能
	input wire[31:0] cache_data_index, // 数据存储器访问索引号
	input wire[4*CACHE_LINE_WORD_N*8-1:0] cache_din, // 缓存行写数据
	output wire[4*CACHE_LINE_WORD_N*8-1:0] cache_dout, // 缓存行读数据
	// [标签存储器]
	input wire cache_tag_en, // 标签存储器使能
	input wire cache_tag_wen, // 标签存储器写使能
	input wire[31:0] cache_tag_index, // 标签存储器访问索引号
	input wire[CACHE_TAG_WIDTH-1:0] cache_tag, // 缓存行标签
	input wire cache_valid_new, // 标签存储器待写的有效标志
	input wire cache_dirty_new, // 标签存储器待写的脏标志
	output wire[31:0] cache_real_addr, // 缓存行的实际基地址
	output wire cache_hit, // 缓存行命中(标志)
	output wire cache_valid, // 缓存行有效(标志)
	output wire cache_dirty, // 缓存行脏(标志)
	
	// 数据存储器接口
	output wire data_sram_clk_a,
	output wire[4*CACHE_LINE_WORD_N-1:0] data_sram_en_a,
	output wire[4*CACHE_LINE_WORD_N-1:0] data_sram_wen_a,
	// 说明: 虽然这里给每个RAM设置了32位的地址, 但实际上并不会用完32位, 未用到的位可以被综合器自动优化掉!
	output wire[4*CACHE_LINE_WORD_N*32-1:0] data_sram_addr_a,
	output wire[4*CACHE_LINE_WORD_N*8-1:0] data_sram_din_a,
	input wire[4*CACHE_LINE_WORD_N*8-1:0] data_sram_dout_a,
	
	// 标签存储器接口
	output wire tag_sram_clk_a,
	output wire tag_sram_en_a,
	output wire tag_sram_wen_a,
	output wire[31:0] tag_sram_addr_a,
	output wire[CACHE_TAG_WIDTH+1:0] tag_sram_din_a, // {dirty(1位), valid(1位), tag(CACHE_TAG_WIDTH位)}
	input wire[CACHE_TAG_WIDTH+1:0] tag_sram_dout_a // {dirty(1位), valid(1位), tag(CACHE_TAG_WIDTH位)}
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
	
	/** 数据存储器接口 **/
	assign data_sram_clk_a = aclk;
	assign data_sram_en_a = {(4*CACHE_LINE_WORD_N){cache_data_en}};
	assign data_sram_wen_a = cache_data_byte_wen;
	
	genvar data_sram_addr_a_i;
	generate
		for(data_sram_addr_a_i = 0;data_sram_addr_a_i < CACHE_LINE_WORD_N;data_sram_addr_a_i = data_sram_addr_a_i + 1)
		begin:data_sram_addr_a_blk
			assign data_sram_addr_a[data_sram_addr_a_i*4*32+127:data_sram_addr_a_i*4*32] = 
				{4{cache_data_index[clogb2(CACHE_ENTRY_N-1):0] | 32'h0000_0000}};
		end
	endgenerate
	
	assign data_sram_din_a = cache_din;
	assign cache_dout = data_sram_dout_a;
	
	/** 标签存储器接口 **/
	reg[clogb2(CACHE_ENTRY_N-1):0] cache_tag_index_d1; // 延迟1clk的标签存储器访问索引号
	reg[CACHE_TAG_WIDTH-1:0] cache_tag_d1; // 延迟1clk的缓存行标签
	
	assign tag_sram_clk_a = aclk;
	assign tag_sram_en_a = cache_tag_en;
	assign tag_sram_wen_a = cache_tag_wen;
	assign tag_sram_addr_a = cache_tag_index[clogb2(CACHE_ENTRY_N-1):0] | 32'h0000_0000;
	assign tag_sram_din_a = {
		cache_dirty_new, // dirty(1位)
		cache_valid_new, // valid(1位)
		cache_tag // tag(CACHE_TAG_WIDTH位)
	};
	assign cache_real_addr = 
		{tag_sram_dout_a[CACHE_TAG_WIDTH-1:0], cache_tag_index_d1, {clogb2(CACHE_LINE_WORD_N*4){1'b0}}} | 32'h0000_0000;
	assign cache_hit = 
		tag_sram_dout_a[CACHE_TAG_WIDTH] & 
		(cache_tag_d1 == tag_sram_dout_a[CACHE_TAG_WIDTH-1:0]);
	assign cache_valid = tag_sram_dout_a[CACHE_TAG_WIDTH];
	assign cache_dirty = tag_sram_dout_a[CACHE_TAG_WIDTH+1];
	
	// 延迟1clk的标签存储器访问索引号, 延迟1clk的缓存行标签
	always @(posedge aclk)
	begin
		if(cache_tag_en)
		begin
			cache_tag_index_d1 <= # SIM_DELAY cache_tag_index;
			cache_tag_d1 <= # SIM_DELAY cache_tag;
		end
	end
	
endmodule
