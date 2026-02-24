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

使用1个位宽 = CACHE_DATA_WIDTH、深度 = CACHE_ENTRY_N * CACHE_LINE_DATA_N的真双口RAM作为数据存储器
使用1个位宽 = CACHE_TAG_WIDTH+2、深度 = CACHE_ENTRY_N的真双口RAM作为标签存储器

缓存行数 = CACHE_ENTRY_N, 缓存数据块的数据个数 = CACHE_LINE_DATA_N, 缓存数据位宽 = CACHE_DATA_WIDTH

注意：
RAM的读时延应为1clk, 读写模式应为read_first

标签存储器的valid字段应初始化为1'b0

协议:
MEM MASTER

作者: 陈家耀
日期: 2026/02/23
********************************************************************/


module logic_dcache_way_mem #(
	parameter integer CACHE_DATA_WIDTH = 32, // 缓存数据位宽(32 | 64 | 128 | 256)
	parameter integer CACHE_ENTRY_N = 512, // 缓存存储条目数
	parameter integer CACHE_LINE_DATA_N = 8, // 每个缓存行的数据个数(1 | 2 | 4 | 8 | 16)
	parameter integer CACHE_TAG_WIDTH = 12, // 缓存标签位数
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟
	input wire aclk,
	
	// 逻辑缓存路接口
	// [数据存储器端口A]
	input wire cache_data_en_a, // 数据存储器使能
	input wire[CACHE_DATA_WIDTH/8-1:0] cache_data_byte_wen_a, // 数据存储器字节写使能
	input wire[31:0] cache_data_addr_index_a, // 数据存储器访问索引号
	input wire[7:0] cache_data_addr_ofs_a, // 数据存储器访问数据偏移量
	input wire[CACHE_DATA_WIDTH-1:0] cache_din_a, // 缓存行写数据
	output wire[CACHE_DATA_WIDTH-1:0] cache_dout_a, // 缓存行读数据
	// [数据存储器端口B]
	input wire cache_data_en_b, // 数据存储器使能
	input wire[CACHE_DATA_WIDTH/8-1:0] cache_data_byte_wen_b, // 数据存储器字节写使能
	input wire[31:0] cache_data_addr_index_b, // 数据存储器访问索引号
	input wire[7:0] cache_data_addr_ofs_b, // 数据存储器访问数据偏移量
	input wire[CACHE_DATA_WIDTH-1:0] cache_din_b, // 缓存行写数据
	output wire[CACHE_DATA_WIDTH-1:0] cache_dout_b, // 缓存行读数据
	// [标签存储器端口A]
	input wire cache_tag_en_a, // 标签存储器使能
	input wire cache_tag_wen_a, // 标签存储器写使能
	input wire[31:0] cache_tag_addr_index_a, // 标签存储器访问索引号
	input wire[7:0] cache_tag_addr_ofs_a, // 标签存储器访问数据偏移量
	input wire[CACHE_TAG_WIDTH-1:0] cache_tag_addr_tag_a, // 标签存储器访问缓存行标签
	input wire cache_tag_din_valid_a, // 标签存储器待写的有效标志
	input wire cache_tag_din_dirty_a, // 标签存储器待写的脏标志
	output wire[31:0] cache_tag_dout_real_addr_a, // 缓存行的实际地址
	output wire[CACHE_TAG_WIDTH-1:0] cache_tag_dout_org_tag_a, // 原来的缓存行地址标签
	output wire cache_tag_dout_hit_a, // 缓存行命中(标志)
	output wire cache_tag_dout_valid_a, // 缓存行有效(标志)
	output wire cache_tag_dout_dirty_a, // 缓存行脏(标志)
	// [标签存储器端口B]
	input wire cache_tag_en_b, // 标签存储器使能
	input wire cache_tag_wen_b, // 标签存储器写使能
	input wire[31:0] cache_tag_addr_index_b, // 标签存储器访问索引号
	input wire[CACHE_TAG_WIDTH-1:0] cache_tag_din_tag_b, // 标签存储器访问缓存行标签
	input wire cache_tag_din_valid_b, // 标签存储器待写的有效标志
	input wire cache_tag_din_dirty_b, // 标签存储器待写的脏标志
	output wire cache_tag_dout_valid_b, // 缓存行有效(标志)
	output wire cache_tag_dout_dirty_b, // 缓存行脏(标志)
	
	// 数据存储器接口
	// [端口A]
	output wire data_sram_clk_a,
	output wire data_sram_en_a,
	output wire[CACHE_DATA_WIDTH/8-1:0] data_sram_wen_a,
	output wire[31:0] data_sram_addr_a,
	output wire[CACHE_DATA_WIDTH-1:0] data_sram_din_a,
	input wire[CACHE_DATA_WIDTH-1:0] data_sram_dout_a,
	// [端口B]
	output wire data_sram_clk_b,
	output wire data_sram_en_b,
	output wire[CACHE_DATA_WIDTH/8-1:0] data_sram_wen_b,
	output wire[31:0] data_sram_addr_b,
	output wire[CACHE_DATA_WIDTH-1:0] data_sram_din_b,
	input wire[CACHE_DATA_WIDTH-1:0] data_sram_dout_b,
	
	// 标签存储器接口
	// [端口A]
	output wire tag_sram_clk_a,
	output wire tag_sram_en_a,
	output wire tag_sram_wen_a,
	output wire[31:0] tag_sram_addr_a,
	output wire[2+CACHE_TAG_WIDTH-1:0] tag_sram_din_a, // {dirty(1位), valid(1位), tag(CACHE_TAG_WIDTH位)}
	input wire[2+CACHE_TAG_WIDTH-1:0] tag_sram_dout_a, // {dirty(1位), valid(1位), tag(CACHE_TAG_WIDTH位)}
	// [端口B]
	output wire tag_sram_clk_b,
	output wire tag_sram_en_b,
	output wire tag_sram_wen_b,
	output wire[31:0] tag_sram_addr_b,
	output wire[2+CACHE_TAG_WIDTH-1:0] tag_sram_din_b, // {dirty(1位), valid(1位), tag(CACHE_TAG_WIDTH位)}
	input wire[2+CACHE_TAG_WIDTH-1:0] tag_sram_dout_b // {dirty(1位), valid(1位), tag(CACHE_TAG_WIDTH位)}
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
	// 标签存储器数据每个字段的起始索引
	localparam integer TAG_RAM_FIELD_TAG_SID = 0;
	localparam integer TAG_RAM_FIELD_VALID_FLAG_SID = CACHE_TAG_WIDTH;
	localparam integer TAG_RAM_FIELD_DIRTY_FLAG_SID = CACHE_TAG_WIDTH + 1;
	
	/** 数据存储器接口 **/
	assign data_sram_clk_a = aclk;
	assign data_sram_en_a = cache_data_en_a;
	assign data_sram_wen_a = cache_data_byte_wen_a;
	assign data_sram_addr_a = 
		((cache_data_addr_index_a[31:0] & (CACHE_ENTRY_N - 1)) * CACHE_LINE_DATA_N) | 
		(cache_data_addr_ofs_a[7:0] & (CACHE_LINE_DATA_N - 1));
	assign data_sram_din_a = cache_din_a;
	assign cache_dout_a = data_sram_dout_a;
	
	assign data_sram_clk_b = aclk;
	assign data_sram_en_b = cache_data_en_b;
	assign data_sram_wen_b = cache_data_byte_wen_b;
	assign data_sram_addr_b = 
		((cache_data_addr_index_b[31:0] & (CACHE_ENTRY_N - 1)) * CACHE_LINE_DATA_N) | 
		(cache_data_addr_ofs_b[7:0] & (CACHE_LINE_DATA_N - 1));
	assign data_sram_din_b = cache_din_b;
	assign cache_dout_b = data_sram_dout_b;
	
	/** 标签存储器接口 **/
	reg[clogb2(CACHE_ENTRY_N-1):0] cache_tag_index_d1; // 延迟1clk的标签存储器访问索引号
	reg[clogb2(CACHE_LINE_DATA_N-1):0] cache_ofs_d1; // 延迟1clk的标签存储器访问数据偏移量
	reg[CACHE_TAG_WIDTH-1:0] cache_tag_d1; // 延迟1clk的缓存行标签
	
	assign tag_sram_clk_a = aclk;
	assign tag_sram_en_a = cache_tag_en_a;
	assign tag_sram_wen_a = cache_tag_wen_a;
	assign tag_sram_addr_a = cache_tag_addr_index_a[clogb2(CACHE_ENTRY_N-1):0] | 32'h0000_0000;
	assign tag_sram_din_a = {
		cache_tag_din_dirty_a, // dirty(1位)
		cache_tag_din_valid_a, // valid(1位)
		cache_tag_addr_tag_a // tag(CACHE_TAG_WIDTH位)
	};
	assign cache_tag_dout_real_addr_a = 
		(
			(tag_sram_dout_a[(CACHE_TAG_WIDTH-1)+TAG_RAM_FIELD_TAG_SID:TAG_RAM_FIELD_TAG_SID] | 32'h0000_0000) * 
			(CACHE_ENTRY_N * CACHE_LINE_DATA_N * CACHE_DATA_WIDTH / 8)
		) | 
		((cache_tag_index_d1[clogb2(CACHE_ENTRY_N-1):0] | 32'h0000_0000) * (CACHE_LINE_DATA_N * CACHE_DATA_WIDTH / 8)) | 
		(((cache_ofs_d1 & (CACHE_LINE_DATA_N - 1)) | 32'h0000_0000) * (CACHE_DATA_WIDTH / 8));
	assign cache_tag_dout_org_tag_a = cache_tag_d1;
	assign cache_tag_dout_hit_a = 
		tag_sram_dout_a[TAG_RAM_FIELD_VALID_FLAG_SID] & // 缓存行valid
		(cache_tag_d1 == tag_sram_dout_a[(CACHE_TAG_WIDTH-1)+TAG_RAM_FIELD_TAG_SID:TAG_RAM_FIELD_TAG_SID]); // 缓存行tag匹配
	assign cache_tag_dout_valid_a = tag_sram_dout_a[TAG_RAM_FIELD_VALID_FLAG_SID];
	assign cache_tag_dout_dirty_a = tag_sram_dout_a[TAG_RAM_FIELD_DIRTY_FLAG_SID];
	
	assign tag_sram_clk_b = aclk;
	assign tag_sram_en_b = cache_tag_en_b;
	assign tag_sram_wen_b = cache_tag_wen_b;
	assign tag_sram_addr_b = cache_tag_addr_index_b[clogb2(CACHE_ENTRY_N-1):0] | 32'h0000_0000;
	assign tag_sram_din_b = 
		{
			cache_tag_din_dirty_b, // dirty(1位)
			cache_tag_din_valid_b, // valid(1位)
			cache_tag_din_tag_b // tag(CACHE_TAG_WIDTH位)
		};
	assign cache_tag_dout_valid_b = tag_sram_dout_b[TAG_RAM_FIELD_VALID_FLAG_SID];
	assign cache_tag_dout_dirty_b = tag_sram_dout_b[TAG_RAM_FIELD_DIRTY_FLAG_SID];
	
	// 延迟1clk的标签存储器访问索引号, 延迟1clk的标签存储器访问数据偏移量, 延迟1clk的缓存行标签
	always @(posedge aclk)
	begin
		if(cache_tag_en_a)
		begin
			cache_tag_index_d1 <= # SIM_DELAY cache_tag_addr_index_a[clogb2(CACHE_ENTRY_N-1):0];
			cache_ofs_d1 <= # SIM_DELAY cache_tag_addr_ofs_a[clogb2(CACHE_LINE_DATA_N-1):0];
			cache_tag_d1 <= # SIM_DELAY cache_tag_addr_tag_a[CACHE_TAG_WIDTH-1:0];
		end
	end
	
endmodule
