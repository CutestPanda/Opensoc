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
本模块: ICB-数据Cache

描述:
写回、写分配、CACHE_WAY_N路、CACHE_ENTRY_N项、CACHE_LINE_WORD_N字的组相连数据Cache

使用CACHE_WAY_N*4*CACHE_LINE_WORD_N个位宽 = 8、深度 = CACHE_ENTRY_N的单口RAM作为数据存储器, 
	总容量为CACHE_WAY_N*CACHE_ENTRY_N*4*CACHE_LINE_WORD_N字节
使用CACHE_WAY_N个位宽 = CACHE_TAG_WIDTH+2、深度 = CACHE_ENTRY_N的单口RAM作为标签存储器, 
	总容量为CACHE_WAY_N*CACHE_ENTRY_N*(CACHE_TAG_WIDTH+2)字节
使用1个位宽 = max(clogb2(CACHE_WAY_N), 1)*CACHE_WAY_N、深度 = CACHE_ENTRY_N的简单双口RAM作为记录存储器

注意：
处理器核ICB从机给出的访问地址必须对齐到字(能被4整除)
应将标签存储器的每1项初始化为0

协议:
ICB MASTER/SLAVE
MEM MASTER

作者: 陈家耀
日期: 2025/04/16
********************************************************************/


module icb_dcache #(
	parameter integer CACHE_WAY_N = 4, // 缓存路数(1 | 2 | 4 | 8)
	parameter integer CACHE_ENTRY_N = 512, // 缓存存储条目数
	parameter integer CACHE_LINE_WORD_N = 8, // 每个缓存行的字数(1 | 2 | 4 | 8 | 16)
	parameter integer CACHE_TAG_WIDTH = 12, // 缓存标签位数
	parameter integer WBUF_ITEM_N = 4, // 写缓存最多可存的缓存行个数(1~8)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 处理器核ICB从机
	// [命令通道]
	input wire[31:0] s_icb_cmd_addr,
	input wire s_icb_cmd_read,
	input wire[31:0] s_icb_cmd_wdata,
	input wire[3:0] s_icb_cmd_wmask,
	input wire s_icb_cmd_valid,
	output wire s_icb_cmd_ready,
	// [响应通道]
	output wire[31:0] s_icb_rsp_rdata,
	output wire s_icb_rsp_err, // const -> 1'b0
	output wire s_icb_rsp_valid,
	input wire s_icb_rsp_ready,
	
	// 访问下级存储器ICB主机
	// [命令通道]
	output wire[31:0] m_icb_cmd_addr,
	output wire m_icb_cmd_read,
	output wire[31:0] m_icb_cmd_wdata,
	output wire[3:0] m_icb_cmd_wmask,
	output wire m_icb_cmd_valid,
	input wire m_icb_cmd_ready,
	// [响应通道]
	input wire[31:0] m_icb_rsp_rdata,
	input wire m_icb_rsp_err, // ignored
	input wire m_icb_rsp_valid,
	output wire m_icb_rsp_ready,
	
	// 数据存储器接口
	output wire[CACHE_WAY_N-1:0] data_sram_clk_a,
	output wire[CACHE_WAY_N*4*CACHE_LINE_WORD_N-1:0] data_sram_en_a,
	output wire[CACHE_WAY_N*4*CACHE_LINE_WORD_N-1:0] data_sram_wen_a,
	// 说明: 虽然这里给每个RAM设置了32位的地址, 但实际上并不会用完32位, 未用到的位可以被综合器自动优化掉!
	output wire[CACHE_WAY_N*4*CACHE_LINE_WORD_N*32-1:0] data_sram_addr_a,
	output wire[CACHE_WAY_N*4*CACHE_LINE_WORD_N*8-1:0] data_sram_din_a,
	input wire[CACHE_WAY_N*4*CACHE_LINE_WORD_N*8-1:0] data_sram_dout_a,
	
	// 标签存储器接口
	output wire[CACHE_WAY_N-1:0] tag_sram_clk_a,
	output wire[CACHE_WAY_N-1:0] tag_sram_en_a,
	output wire[CACHE_WAY_N-1:0] tag_sram_wen_a,
	output wire[CACHE_WAY_N*32-1:0] tag_sram_addr_a,
	output wire[CACHE_WAY_N*(CACHE_TAG_WIDTH+2)-1:0] tag_sram_din_a, // {dirty(1位), valid(1位), tag(CACHE_TAG_WIDTH位)}
	input wire[CACHE_WAY_N*(CACHE_TAG_WIDTH+2)-1:0] tag_sram_dout_a, // {dirty(1位), valid(1位), tag(CACHE_TAG_WIDTH位)}
	
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
	
	/** 数据Cache控制单元 **/
	// 读下级存储器ICB主机
	// [命令通道]
	wire[31:0] m_rd_icb_cmd_addr;
	wire m_rd_icb_cmd_read; // const -> 1'b1
	wire[31:0] m_rd_icb_cmd_wdata; // not care
	wire[3:0] m_rd_icb_cmd_wmask; // const -> 4'b0000
	wire m_rd_icb_cmd_valid;
	wire m_rd_icb_cmd_ready;
	// [响应通道]
	wire[31:0] m_rd_icb_rsp_rdata;
	wire m_rd_icb_rsp_err; // ignored
	wire m_rd_icb_rsp_valid;
	wire m_rd_icb_rsp_ready;
	// 待写的缓存行(AXIS主机)
	wire[CACHE_LINE_WORD_N*32+32-1:0] m_wbuf_axis_data; // {缓存行地址(32位), 缓存行数据块(CACHE_LINE_WORD_N*32位)}
	wire m_wbuf_axis_valid;
	wire m_wbuf_axis_ready;
	// 写缓存检索
	wire[31:0] wbuf_sch_addr; // 检索地址
	wire wbuf_cln_found_flag; // 在写缓存里找到缓存行(标志)
	wire[CACHE_LINE_WORD_N*32-1:0] wbuf_sch_datblk; // 检索到的数据块
	// 查询或更新热度表
	wire hot_tb_en; // 热度表使能
	wire hot_tb_upd_en; // 热度表更新使能
	wire[31:0] hot_tb_cid; // 待查询或更新的缓存项的索引号
	wire[2:0] hot_tb_acs_wid; // 本次访问的缓存路编号
	wire hot_tb_init_item; // 初始化热度项(标志)
	wire hot_tb_swp_lru_item; // 置换最近最少使用项(标志)
	wire[2:0] hot_tb_lru_wid; // 最近最少使用项的缓存路编号
	// 逻辑Cache存储器接口
	// [数据存储器]
	wire[CACHE_WAY_N-1:0] cache_data_en; // 数据存储器使能
	wire[CACHE_WAY_N*CACHE_LINE_WORD_N*4-1:0] cache_data_byte_wen; // 数据存储器字节写使能
	wire[CACHE_WAY_N*32-1:0] cache_data_index; // 数据存储器访问索引号
	wire[CACHE_WAY_N*CACHE_LINE_WORD_N*4*8-1:0] cache_din; // 缓存行写数据
	wire[CACHE_WAY_N*CACHE_LINE_WORD_N*4*8-1:0] cache_dout; // 缓存行读数据
	// [标签存储器]
	wire[CACHE_WAY_N-1:0] cache_tag_en; // 标签存储器使能
	wire[CACHE_WAY_N-1:0] cache_tag_wen; // 标签存储器写使能
	wire[CACHE_WAY_N*32-1:0] cache_tag_index; // 标签存储器访问索引号
	wire[CACHE_WAY_N*CACHE_TAG_WIDTH-1:0] cache_tag; // 缓存行标签
	wire[CACHE_WAY_N-1:0] cache_valid_new; // 标签存储器待写的有效标志
	wire[CACHE_WAY_N-1:0] cache_dirty_new; // 标签存储器待写的脏标志
	wire[CACHE_WAY_N*32-1:0] cache_real_addr; // 缓存行的实际基地址
	wire[CACHE_WAY_N-1:0] cache_hit; // 缓存行命中(标志)
	wire[CACHE_WAY_N-1:0] cache_valid; // 缓存行有效(标志)
	wire[CACHE_WAY_N-1:0] cache_dirty; // 缓存行脏(标志)
	
	dcache_ctrl #(
		.CACHE_WAY_N(CACHE_WAY_N),
		.CACHE_ENTRY_N(CACHE_ENTRY_N),
		.CACHE_LINE_WORD_N(CACHE_LINE_WORD_N),
		.CACHE_TAG_WIDTH(CACHE_TAG_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)dcache_ctrl_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.s_icb_cmd_addr(s_icb_cmd_addr),
		.s_icb_cmd_read(s_icb_cmd_read),
		.s_icb_cmd_wdata(s_icb_cmd_wdata),
		.s_icb_cmd_wmask(s_icb_cmd_wmask),
		.s_icb_cmd_valid(s_icb_cmd_valid),
		.s_icb_cmd_ready(s_icb_cmd_ready),
		.s_icb_rsp_rdata(s_icb_rsp_rdata),
		.s_icb_rsp_err(s_icb_rsp_err),
		.s_icb_rsp_valid(s_icb_rsp_valid),
		.s_icb_rsp_ready(s_icb_rsp_ready),
		
		.m_icb_cmd_addr(m_rd_icb_cmd_addr),
		.m_icb_cmd_read(m_rd_icb_cmd_read),
		.m_icb_cmd_wdata(m_rd_icb_cmd_wdata),
		.m_icb_cmd_wmask(m_rd_icb_cmd_wmask),
		.m_icb_cmd_valid(m_rd_icb_cmd_valid),
		.m_icb_cmd_ready(m_rd_icb_cmd_ready),
		.m_icb_rsp_rdata(m_rd_icb_rsp_rdata),
		.m_icb_rsp_err(m_rd_icb_rsp_err),
		.m_icb_rsp_valid(m_rd_icb_rsp_valid),
		.m_icb_rsp_ready(m_rd_icb_rsp_ready),
		
		.m_wbuf_axis_data(m_wbuf_axis_data),
		.m_wbuf_axis_valid(m_wbuf_axis_valid),
		.m_wbuf_axis_ready(m_wbuf_axis_ready),
		
		.wbuf_sch_addr(wbuf_sch_addr),
		.wbuf_cln_found_flag(wbuf_cln_found_flag),
		.wbuf_sch_datblk(wbuf_sch_datblk),
		
		.hot_tb_en(hot_tb_en),
		.hot_tb_upd_en(hot_tb_upd_en),
		.hot_tb_cid(hot_tb_cid),
		.hot_tb_acs_wid(hot_tb_acs_wid),
		.hot_tb_init_item(hot_tb_init_item),
		.hot_tb_swp_lru_item(hot_tb_swp_lru_item),
		.hot_tb_lru_wid(hot_tb_lru_wid),
		
		.cache_data_en(cache_data_en),
		.cache_data_byte_wen(cache_data_byte_wen),
		.cache_data_index(cache_data_index),
		.cache_din(cache_din),
		.cache_dout(cache_dout),
		.cache_tag_en(cache_tag_en),
		.cache_tag_wen(cache_tag_wen),
		.cache_tag_index(cache_tag_index),
		.cache_tag(cache_tag),
		.cache_valid_new(cache_valid_new),
		.cache_dirty_new(cache_dirty_new),
		.cache_real_addr(cache_real_addr),
		.cache_hit(cache_hit),
		.cache_valid(cache_valid),
		.cache_dirty(cache_dirty)
	);
	
	/** 数据Cache写缓存 **/
	// 待写的缓存行(AXIS从机)
	wire[CACHE_LINE_WORD_N*32+32-1:0] s_wbuf_axis_data; // {缓存行地址(32位), 缓存行数据块(CACHE_LINE_WORD_N*32位)}
	wire s_wbuf_axis_valid;
	wire s_wbuf_axis_ready;
	// 写下级存储器ICB主机
	// [命令通道]
	wire[31:0] m_wt_icb_cmd_addr;
	wire m_wt_icb_cmd_read; // const -> 1'b0
	wire[31:0] m_wt_icb_cmd_wdata;
	wire[3:0] m_wt_icb_cmd_wmask; // const -> 4'b1111
	wire m_wt_icb_cmd_valid;
	wire m_wt_icb_cmd_ready;
	// [响应通道]
	wire[31:0] m_wt_icb_rsp_rdata; // ignored
	wire m_wt_icb_rsp_err; // ignored
	wire m_wt_icb_rsp_valid;
	wire m_wt_icb_rsp_ready; // const -> 1'b1
	
	assign s_wbuf_axis_data = m_wbuf_axis_data;
	assign s_wbuf_axis_valid = m_wbuf_axis_valid;
	assign m_wbuf_axis_ready = s_wbuf_axis_ready;
	
	dcache_wbuffer #(
		.CACHE_LINE_WORD_N(CACHE_LINE_WORD_N),
		.WBUF_ITEM_N(WBUF_ITEM_N),
		.EN_WBUF_ITEM_IMDT_OVR("true"),
		.EN_LOW_LA_ICB_CMD("false"),
		.SIM_DELAY(SIM_DELAY)
	)dcache_wbuffer_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.cache_line_sch_addr(wbuf_sch_addr),
		.cache_line_in_wbuf_flag(wbuf_cln_found_flag),
		.cache_line_sch_datblk(wbuf_sch_datblk),
		
		.s_cache_line_axis_data(s_wbuf_axis_data),
		.s_cache_line_axis_valid(s_wbuf_axis_valid),
		.s_cache_line_axis_ready(s_wbuf_axis_ready),
		
		.m_icb_cmd_addr(m_wt_icb_cmd_addr),
		.m_icb_cmd_read(m_wt_icb_cmd_read),
		.m_icb_cmd_wdata(m_wt_icb_cmd_wdata),
		.m_icb_cmd_wmask(m_wt_icb_cmd_wmask),
		.m_icb_cmd_valid(m_wt_icb_cmd_valid),
		.m_icb_cmd_ready(m_wt_icb_cmd_ready),
		.m_icb_rsp_rdata(m_wt_icb_rsp_rdata),
		.m_icb_rsp_err(m_wt_icb_rsp_err),
		.m_icb_rsp_valid(m_wt_icb_rsp_valid),
		.m_icb_rsp_ready(m_wt_icb_rsp_ready)
	);
	
	/** Cache路访问热度记录表 **/
	dcache_way_access_hot_record #(
		.CACHE_ENTRY_N(CACHE_ENTRY_N),
		.CACHE_WAY_N(CACHE_WAY_N),
		.SIM_DELAY(SIM_DELAY)
	)dcache_way_access_hot_record_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.hot_tb_en(hot_tb_en),
		.hot_tb_upd_en(hot_tb_upd_en),
		.cache_index(hot_tb_cid),
		.cache_access_wid(hot_tb_acs_wid),
		.to_init_hot_item(hot_tb_init_item),
		.to_swp_lru_item(hot_tb_swp_lru_item),
		.hot_tb_lru_wid(hot_tb_lru_wid),
		
		.hot_sram_clk_a(hot_sram_clk_a),
		.hot_sram_wen_a(hot_sram_wen_a),
		.hot_sram_waddr_a(hot_sram_waddr_a),
		.hot_sram_din_a(hot_sram_din_a),
		.hot_sram_clk_b(hot_sram_clk_b),
		.hot_sram_ren_b(hot_sram_ren_b),
		.hot_sram_raddr_b(hot_sram_raddr_b),
		.hot_sram_dout_b(hot_sram_dout_b)
	);
	
	/** 数据Cache逻辑缓存路存储器 **/
	genvar logic_dcache_way_mem_i;
	generate
		for(logic_dcache_way_mem_i = 0;logic_dcache_way_mem_i < CACHE_WAY_N;logic_dcache_way_mem_i = logic_dcache_way_mem_i + 1)
		begin:logic_dcache_way_mem_blk
			logic_dcache_way_mem #(
				.CACHE_ENTRY_N(CACHE_ENTRY_N),
				.CACHE_LINE_WORD_N(CACHE_LINE_WORD_N),
				.CACHE_TAG_WIDTH(CACHE_TAG_WIDTH),
				.SIM_DELAY(SIM_DELAY)
			)logic_dcache_way_mem_u(
				.aclk(aclk),
				
				.cache_data_en(cache_data_en[logic_dcache_way_mem_i]),
				.cache_data_byte_wen(cache_data_byte_wen[(logic_dcache_way_mem_i+1)*CACHE_LINE_WORD_N*4-1:logic_dcache_way_mem_i*CACHE_LINE_WORD_N*4]),
				.cache_data_index(cache_data_index[(logic_dcache_way_mem_i+1)*32-1:logic_dcache_way_mem_i*32]),
				.cache_din(cache_din[(logic_dcache_way_mem_i+1)*CACHE_LINE_WORD_N*4*8-1:logic_dcache_way_mem_i*CACHE_LINE_WORD_N*4*8]),
				.cache_dout(cache_dout[(logic_dcache_way_mem_i+1)*CACHE_LINE_WORD_N*4*8-1:logic_dcache_way_mem_i*CACHE_LINE_WORD_N*4*8]),
				.cache_tag_en(cache_tag_en[logic_dcache_way_mem_i]),
				.cache_tag_wen(cache_tag_wen[logic_dcache_way_mem_i]),
				.cache_tag_index(cache_tag_index[(logic_dcache_way_mem_i+1)*32-1:logic_dcache_way_mem_i*32]),
				.cache_tag(cache_tag[(logic_dcache_way_mem_i+1)*CACHE_TAG_WIDTH-1:logic_dcache_way_mem_i*CACHE_TAG_WIDTH]),
				.cache_valid_new(cache_valid_new[logic_dcache_way_mem_i]),
				.cache_dirty_new(cache_dirty_new[logic_dcache_way_mem_i]),
				.cache_real_addr(cache_real_addr[(logic_dcache_way_mem_i+1)*32-1:logic_dcache_way_mem_i*32]),
				.cache_hit(cache_hit[logic_dcache_way_mem_i]),
				.cache_valid(cache_valid[logic_dcache_way_mem_i]),
				.cache_dirty(cache_dirty[logic_dcache_way_mem_i]),
				
				.data_sram_clk_a(data_sram_clk_a[logic_dcache_way_mem_i]),
				.data_sram_en_a(data_sram_en_a[(logic_dcache_way_mem_i+1)*CACHE_LINE_WORD_N*4-1:logic_dcache_way_mem_i*CACHE_LINE_WORD_N*4]),
				.data_sram_wen_a(data_sram_wen_a[(logic_dcache_way_mem_i+1)*CACHE_LINE_WORD_N*4-1:logic_dcache_way_mem_i*CACHE_LINE_WORD_N*4]),
				.data_sram_addr_a(data_sram_addr_a[(logic_dcache_way_mem_i+1)*4*CACHE_LINE_WORD_N*32-1:logic_dcache_way_mem_i*4*CACHE_LINE_WORD_N*32]),
				.data_sram_din_a(data_sram_din_a[(logic_dcache_way_mem_i+1)*4*CACHE_LINE_WORD_N*8-1:logic_dcache_way_mem_i*4*CACHE_LINE_WORD_N*8]),
				.data_sram_dout_a(data_sram_dout_a[(logic_dcache_way_mem_i+1)*4*CACHE_LINE_WORD_N*8-1:logic_dcache_way_mem_i*4*CACHE_LINE_WORD_N*8]),
				
				.tag_sram_clk_a(tag_sram_clk_a[logic_dcache_way_mem_i]),
				.tag_sram_en_a(tag_sram_en_a[logic_dcache_way_mem_i]),
				.tag_sram_wen_a(tag_sram_wen_a[logic_dcache_way_mem_i]),
				.tag_sram_addr_a(tag_sram_addr_a[(logic_dcache_way_mem_i+1)*32-1:logic_dcache_way_mem_i*32]),
				.tag_sram_din_a(tag_sram_din_a[(logic_dcache_way_mem_i+1)*(CACHE_TAG_WIDTH+2)-1:logic_dcache_way_mem_i*(CACHE_TAG_WIDTH+2)]),
				.tag_sram_dout_a(tag_sram_dout_a[(logic_dcache_way_mem_i+1)*(CACHE_TAG_WIDTH+2)-1:logic_dcache_way_mem_i*(CACHE_TAG_WIDTH+2)])
			);
		end
	endgenerate
	
	/** 读/写ICB主机仲裁 **/
	// 读下级存储器ICB从机
	// [命令通道]
	wire[31:0] s_rd_icb_cmd_addr;
	wire s_rd_icb_cmd_read;
	wire[31:0] s_rd_icb_cmd_wdata;
	wire[3:0] s_rd_icb_cmd_wmask;
	wire s_rd_icb_cmd_valid;
	wire s_rd_icb_cmd_ready;
	// [响应通道]
	wire[31:0] s_rd_icb_rsp_rdata;
	wire s_rd_icb_rsp_err;
	wire s_rd_icb_rsp_valid;
	wire s_rd_icb_rsp_ready;
	// 写下级存储器ICB从机
	// [命令通道]
	wire[31:0] s_wt_icb_cmd_addr;
	wire s_wt_icb_cmd_read;
	wire[31:0] s_wt_icb_cmd_wdata;
	wire[3:0] s_wt_icb_cmd_wmask;
	wire s_wt_icb_cmd_valid;
	wire s_wt_icb_cmd_ready;
	// [响应通道]
	wire[31:0] s_wt_icb_rsp_rdata;
	wire s_wt_icb_rsp_err;
	wire s_wt_icb_rsp_valid;
	wire s_wt_icb_rsp_ready;
	
	assign s_rd_icb_cmd_addr = m_rd_icb_cmd_addr;
	assign s_rd_icb_cmd_read = m_rd_icb_cmd_read;
	assign s_rd_icb_cmd_wdata = m_rd_icb_cmd_wdata;
	assign s_rd_icb_cmd_wmask = m_rd_icb_cmd_wmask;
	assign s_rd_icb_cmd_valid = m_rd_icb_cmd_valid;
	assign m_rd_icb_cmd_ready = s_rd_icb_cmd_ready;
	assign m_rd_icb_rsp_rdata = s_rd_icb_rsp_rdata;
	assign m_rd_icb_rsp_err = s_rd_icb_rsp_err;
	assign m_rd_icb_rsp_valid = s_rd_icb_rsp_valid;
	assign s_rd_icb_rsp_ready = m_rd_icb_rsp_ready;
	
	assign s_wt_icb_cmd_addr = m_wt_icb_cmd_addr;
	assign s_wt_icb_cmd_read = m_wt_icb_cmd_read;
	assign s_wt_icb_cmd_wdata = m_wt_icb_cmd_wdata;
	assign s_wt_icb_cmd_wmask = m_wt_icb_cmd_wmask;
	assign s_wt_icb_cmd_valid = m_wt_icb_cmd_valid;
	assign m_wt_icb_cmd_ready = s_wt_icb_cmd_ready;
	assign m_wt_icb_rsp_rdata = s_wt_icb_rsp_rdata;
	assign m_wt_icb_rsp_err = s_wt_icb_rsp_err;
	assign m_wt_icb_rsp_valid = s_wt_icb_rsp_valid;
	assign s_wt_icb_rsp_ready = m_wt_icb_rsp_ready;
	
	dcache_nxt_lv_mem_icb #(
		.ARB_METHOD("round-robin"),
		.CACHE_LINE_WORD_N(CACHE_LINE_WORD_N),
		.SIM_DELAY(SIM_DELAY)
	)dcache_nxt_lv_mem_icb_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.s_rd_icb_cmd_addr(s_rd_icb_cmd_addr),
		.s_rd_icb_cmd_read(s_rd_icb_cmd_read),
		.s_rd_icb_cmd_wdata(s_rd_icb_cmd_wdata),
		.s_rd_icb_cmd_wmask(s_rd_icb_cmd_wmask),
		.s_rd_icb_cmd_valid(s_rd_icb_cmd_valid),
		.s_rd_icb_cmd_ready(s_rd_icb_cmd_ready),
		.s_rd_icb_rsp_rdata(s_rd_icb_rsp_rdata),
		.s_rd_icb_rsp_err(s_rd_icb_rsp_err),
		.s_rd_icb_rsp_valid(s_rd_icb_rsp_valid),
		.s_rd_icb_rsp_ready(s_rd_icb_rsp_ready),
		
		.s_wt_icb_cmd_addr(s_wt_icb_cmd_addr),
		.s_wt_icb_cmd_read(s_wt_icb_cmd_read),
		.s_wt_icb_cmd_wdata(s_wt_icb_cmd_wdata),
		.s_wt_icb_cmd_wmask(s_wt_icb_cmd_wmask),
		.s_wt_icb_cmd_valid(s_wt_icb_cmd_valid),
		.s_wt_icb_cmd_ready(s_wt_icb_cmd_ready),
		.s_wt_icb_rsp_rdata(s_wt_icb_rsp_rdata),
		.s_wt_icb_rsp_err(s_wt_icb_rsp_err),
		.s_wt_icb_rsp_valid(s_wt_icb_rsp_valid),
		.s_wt_icb_rsp_ready(s_wt_icb_rsp_ready),
		
		.m_icb_cmd_addr(m_icb_cmd_addr),
		.m_icb_cmd_read(m_icb_cmd_read),
		.m_icb_cmd_wdata(m_icb_cmd_wdata),
		.m_icb_cmd_wmask(m_icb_cmd_wmask),
		.m_icb_cmd_valid(m_icb_cmd_valid),
		.m_icb_cmd_ready(m_icb_cmd_ready),
		.m_icb_rsp_rdata(m_icb_rsp_rdata),
		.m_icb_rsp_err(m_icb_rsp_err),
		.m_icb_rsp_valid(m_icb_rsp_valid),
		.m_icb_rsp_ready(m_icb_rsp_ready)
	);
	
endmodule
