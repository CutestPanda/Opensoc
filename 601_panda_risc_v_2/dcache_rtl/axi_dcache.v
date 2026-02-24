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
本模块: AXI-数据Cache

描述:
写回、写分配、CACHE_WAY_N路、CACHE_ENTRY_N项、CACHE_LINE_DATA_N个数据的组相连数据Cache

注意：
CPU侧AXI从机的读写地址必须对齐到缓存数据位宽对应的字节数, 即能够被(CACHE_DATA_WIDTH/8)所整除

对于访问下级存储器(AXI主机), R通道至少应具有1clk时延(m_axi_arvalid & m_axi_arready -----至少1clk----> m_axi_rvalid)

协议:
AXI-Lite SLAVE
AXI MASTER

作者: 陈家耀
日期: 2026/02/24
********************************************************************/


module axi_dcache #(
	parameter integer CACHE_WAY_N = 4, // 缓存路数(1 | 2 | 4 | 8)
	parameter integer CACHE_ENTRY_N = 512, // 缓存存储条目数
	parameter integer CACHE_DATA_WIDTH = 32, // 缓存数据位宽(32 | 64 | 128 | 256)
	parameter integer CACHE_LINE_DATA_N = 8, // 每个缓存行的数据个数(1 | 2 | 4 | 8 | 16)
	parameter integer CACHE_TAG_WIDTH = 12, // 缓存标签位数
	parameter integer WBUF_ITEM_N = 4, // 写缓存最多可存的缓存行个数(1~8)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// CPU侧AXI从机
	// [AR通道]
	input wire[31:0] s_axi_araddr,
	input wire s_axi_arvalid,
	output wire s_axi_arready,
	// [R通道]
	output wire[CACHE_DATA_WIDTH-1:0] s_axi_rdata,
	output wire[1:0] s_axi_rresp, // const -> 2'b00(OKAY)
	output wire s_axi_rlast, // const -> 1'b1
	output wire s_axi_rvalid,
	input wire s_axi_rready,
	// [AW通道]
	input wire[31:0] s_axi_awaddr,
	input wire s_axi_awvalid,
	output wire s_axi_awready,
	// [B通道]
	output wire[1:0] s_axi_bresp, // const -> 2'b00(OKAY)
	output wire s_axi_bvalid,
	input wire s_axi_bready,
	// [W通道]
	input wire[CACHE_DATA_WIDTH-1:0] s_axi_wdata,
	input wire[CACHE_DATA_WIDTH/8-1:0] s_axi_wstrb,
	input wire s_axi_wlast, // aussumed to be 1'b1
	input wire s_axi_wvalid,
	output wire s_axi_wready,
	
	// 访问下级存储器(AXI主机)
	// [AR通道]
	output wire[31:0] m_axi_araddr,
	output wire[1:0] m_axi_arburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_arlen, // const -> CACHE_LINE_DATA_N - 1
	output wire[2:0] m_axi_arsize, // const -> clogb2(CACHE_DATA_WIDTH/8)
	output wire m_axi_arvalid,
	input wire m_axi_arready,
	// [R通道]
	input wire[CACHE_DATA_WIDTH-1:0] m_axi_rdata,
	input wire[1:0] m_axi_rresp, // ignored
	input wire m_axi_rlast, // ignored
	input wire m_axi_rvalid,
	output wire m_axi_rready, // const -> 1'b1
	// [AW通道]
	output wire[31:0] m_axi_awaddr,
	output wire[1:0] m_axi_awburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_awlen, // const -> CACHE_LINE_DATA_N - 1
	output wire[2:0] m_axi_awsize, // const -> clogb2(CACHE_DATA_WIDTH/8)
	output wire m_axi_awvalid,
	input wire m_axi_awready,
	// [B通道]
	input wire[1:0] m_axi_bresp, // ignored
	input wire m_axi_bvalid,
	output wire m_axi_bready, // const -> 1'b1
	// [W通道]
	output wire[CACHE_DATA_WIDTH-1:0] m_axi_wdata,
	output wire[CACHE_DATA_WIDTH/8-1:0] m_axi_wstrb, // const -> {(CACHE_DATA_WIDTH/8){1'b1}}
	output wire m_axi_wlast,
	output wire m_axi_wvalid,
	input wire m_axi_wready,
	
	// Cache性能监测
	output wire[31:0] cache_access_total_n, // cache访问总次数(计数器)
	output wire[31:0] cache_hit_total_n, // cache命中总次数(计数器)
	output wire[31:0] cache_rd_hit_n, // cache读命中次数(计数器)
	output wire[31:0] cache_wr_hit_n, // cache写命中次数(计数器)
	output wire[31:0] cache_replace_dirty_line_n // cache替换脏的缓存行次数(计数器)
);
	
	/** 数据Cache控制单元 **/
	// 待写的缓存行(AXIS主机)
	wire[32+CACHE_LINE_DATA_N*CACHE_DATA_WIDTH-1:0] m_wbuf_axis_data; // {缓存行地址(32位), 缓存行数据块(CACHE_LINE_DATA_N*CACHE_DATA_WIDTH位)}
	wire m_wbuf_axis_valid;
	wire m_wbuf_axis_ready;
	// 写缓存检索
	wire[31:0] wbuf_sch_addr; // 检索地址
	wire wbuf_cln_found_flag; // 在写缓存里找到缓存行(标志)
	wire[CACHE_LINE_DATA_N*CACHE_DATA_WIDTH-1:0] wbuf_sch_datblk; // 检索到的数据块
	// 查询或更新热度表
	wire hot_tb_en; // 热度表使能
	wire hot_tb_upd_en; // 热度表更新使能
	wire[31:0] hot_tb_cid; // 待查询或更新的缓存项的索引号
	wire[2:0] hot_tb_acs_wid; // 本次访问的缓存路编号
	wire hot_tb_init_item; // 初始化热度项(标志)
	wire hot_tb_swp_lru_item; // 置换最近最少使用项(标志)
	wire[2:0] hot_tb_lru_wid; // 最近最少使用项的缓存路编号
	// 逻辑Cache存储器接口
	// [数据存储器端口A]
	wire[CACHE_WAY_N-1:0] cache_data_en_a; // 数据存储器使能
	wire[CACHE_WAY_N*(CACHE_DATA_WIDTH/8)-1:0] cache_data_byte_wen_a; // 数据存储器字节写使能
	wire[CACHE_WAY_N*32-1:0] cache_data_addr_index_a; // 数据存储器访问索引号
	wire[CACHE_WAY_N*8-1:0] cache_data_addr_ofs_a; // 数据存储器访问数据偏移量
	wire[CACHE_WAY_N*CACHE_DATA_WIDTH-1:0] cache_din_a; // 缓存行写数据
	wire[CACHE_WAY_N*CACHE_DATA_WIDTH-1:0] cache_dout_a; // 缓存行读数据
	// [数据存储器端口B]
	wire[CACHE_WAY_N-1:0] cache_data_en_b; // 数据存储器使能
	wire[CACHE_WAY_N*(CACHE_DATA_WIDTH/8)-1:0] cache_data_byte_wen_b; // 数据存储器字节写使能
	wire[CACHE_WAY_N*32-1:0] cache_data_addr_index_b; // 数据存储器访问索引号
	wire[CACHE_WAY_N*8-1:0] cache_data_addr_ofs_b; // 数据存储器访问数据偏移量
	wire[CACHE_WAY_N*CACHE_DATA_WIDTH-1:0] cache_din_b; // 缓存行写数据
	wire[CACHE_WAY_N*CACHE_DATA_WIDTH-1:0] cache_dout_b; // 缓存行读数据
	// [标签存储器端口A]
	wire[CACHE_WAY_N-1:0] cache_tag_en_a; // 标签存储器使能
	wire[CACHE_WAY_N-1:0] cache_tag_wen_a; // 标签存储器写使能
	wire[CACHE_WAY_N*32-1:0] cache_tag_addr_index_a; // 标签存储器访问索引号
	wire[CACHE_WAY_N*8-1:0] cache_tag_addr_ofs_a; // 标签存储器访问数据偏移量
	wire[CACHE_WAY_N*CACHE_TAG_WIDTH-1:0] cache_tag_addr_tag_a; // 标签存储器访问缓存行标签
	wire[CACHE_WAY_N-1:0] cache_tag_din_valid_a; // 标签存储器待写的有效标志
	wire[CACHE_WAY_N-1:0] cache_tag_din_dirty_a; // 标签存储器待写的脏标志
	wire[CACHE_WAY_N*32-1:0] cache_tag_dout_real_addr_a; // 缓存行的实际基地址
	wire[CACHE_WAY_N*CACHE_TAG_WIDTH-1:0] cache_tag_dout_org_tag_a; // 原来的缓存行地址标签
	wire[CACHE_WAY_N-1:0] cache_tag_dout_hit_a; // 缓存行命中(标志)
	wire[CACHE_WAY_N-1:0] cache_tag_dout_valid_a; // 缓存行有效(标志)
	wire[CACHE_WAY_N-1:0] cache_tag_dout_dirty_a; // 缓存行脏(标志)
	// [标签存储器端口B]
	wire[CACHE_WAY_N-1:0] cache_tag_en_b; // 标签存储器使能
	wire[CACHE_WAY_N-1:0] cache_tag_wen_b; // 标签存储器写使能
	wire[CACHE_WAY_N*32-1:0] cache_tag_addr_index_b; // 标签存储器访问索引号
	wire[CACHE_WAY_N*CACHE_TAG_WIDTH-1:0] cache_tag_din_tag_b; // 标签存储器访问缓存行标签
	wire[CACHE_WAY_N-1:0] cache_tag_din_valid_b; // 标签存储器待写的有效标志
	wire[CACHE_WAY_N-1:0] cache_tag_din_dirty_b; // 标签存储器待写的脏标志
	wire[CACHE_WAY_N-1:0] cache_tag_dout_valid_b; // 缓存行有效(标志)
	wire[CACHE_WAY_N-1:0] cache_tag_dout_dirty_b; // 缓存行脏(标志)
	
	dcache_ctrl #(
		.CACHE_WAY_N(CACHE_WAY_N),
		.CACHE_ENTRY_N(CACHE_ENTRY_N),
		.CACHE_DATA_WIDTH(CACHE_DATA_WIDTH),
		.CACHE_LINE_DATA_N(CACHE_LINE_DATA_N),
		.CACHE_TAG_WIDTH(CACHE_TAG_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)dcache_ctrl_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.s_axi_araddr(s_axi_araddr),
		.s_axi_arvalid(s_axi_arvalid),
		.s_axi_arready(s_axi_arready),
		.s_axi_rdata(s_axi_rdata),
		.s_axi_rresp(s_axi_rresp),
		.s_axi_rlast(s_axi_rlast),
		.s_axi_rvalid(s_axi_rvalid),
		.s_axi_rready(s_axi_rready),
		.s_axi_awaddr(s_axi_awaddr),
		.s_axi_awvalid(s_axi_awvalid),
		.s_axi_awready(s_axi_awready),
		.s_axi_bresp(s_axi_bresp),
		.s_axi_bvalid(s_axi_bvalid),
		.s_axi_bready(s_axi_bready),
		.s_axi_wdata(s_axi_wdata),
		.s_axi_wstrb(s_axi_wstrb),
		.s_axi_wlast(s_axi_wlast),
		.s_axi_wvalid(s_axi_wvalid),
		.s_axi_wready(s_axi_wready),
		
		.m_axi_araddr(m_axi_araddr),
		.m_axi_arburst(m_axi_arburst),
		.m_axi_arlen(m_axi_arlen),
		.m_axi_arsize(m_axi_arsize),
		.m_axi_arvalid(m_axi_arvalid),
		.m_axi_arready(m_axi_arready),
		.m_axi_rdata(m_axi_rdata),
		.m_axi_rresp(m_axi_rresp),
		.m_axi_rlast(m_axi_rlast),
		.m_axi_rvalid(m_axi_rvalid),
		.m_axi_rready(m_axi_rready),
		
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
		
		.cache_data_en_a(cache_data_en_a),
		.cache_data_byte_wen_a(cache_data_byte_wen_a),
		.cache_data_addr_index_a(cache_data_addr_index_a),
		.cache_data_addr_ofs_a(cache_data_addr_ofs_a),
		.cache_din_a(cache_din_a),
		.cache_dout_a(cache_dout_a),
		.cache_data_en_b(cache_data_en_b),
		.cache_data_byte_wen_b(cache_data_byte_wen_b),
		.cache_data_addr_index_b(cache_data_addr_index_b),
		.cache_data_addr_ofs_b(cache_data_addr_ofs_b),
		.cache_din_b(cache_din_b),
		.cache_dout_b(cache_dout_b),
		.cache_tag_en_a(cache_tag_en_a),
		.cache_tag_wen_a(cache_tag_wen_a),
		.cache_tag_addr_index_a(cache_tag_addr_index_a),
		.cache_tag_addr_ofs_a(cache_tag_addr_ofs_a),
		.cache_tag_addr_tag_a(cache_tag_addr_tag_a),
		.cache_tag_din_valid_a(cache_tag_din_valid_a),
		.cache_tag_din_dirty_a(cache_tag_din_dirty_a),
		.cache_tag_dout_real_addr_a(cache_tag_dout_real_addr_a),
		.cache_tag_dout_org_tag_a(cache_tag_dout_org_tag_a),
		.cache_tag_dout_hit_a(cache_tag_dout_hit_a),
		.cache_tag_dout_valid_a(cache_tag_dout_valid_a),
		.cache_tag_dout_dirty_a(cache_tag_dout_dirty_a),
		.cache_tag_en_b(cache_tag_en_b),
		.cache_tag_wen_b(cache_tag_wen_b),
		.cache_tag_addr_index_b(cache_tag_addr_index_b),
		.cache_tag_din_tag_b(cache_tag_din_tag_b),
		.cache_tag_din_valid_b(cache_tag_din_valid_b),
		.cache_tag_din_dirty_b(cache_tag_din_dirty_b),
		.cache_tag_dout_valid_b(cache_tag_dout_valid_b),
		.cache_tag_dout_dirty_b(cache_tag_dout_dirty_b),
		
		.cache_access_total_n(cache_access_total_n),
		.cache_hit_total_n(cache_hit_total_n),
		.cache_rd_hit_n(cache_rd_hit_n),
		.cache_wr_hit_n(cache_wr_hit_n),
		.cache_replace_dirty_line_n(cache_replace_dirty_line_n)
	);
	
	/** 数据Cache写缓存 **/
	// 待写的缓存行(AXIS从机)
	wire[32+CACHE_LINE_DATA_N*CACHE_DATA_WIDTH-1:0] s_wbuf_axis_data; // {缓存行地址(32位), 缓存行数据块(CACHE_LINE_DATA_N*CACHE_DATA_WIDTH位)}
	wire s_wbuf_axis_valid;
	wire s_wbuf_axis_ready;
	
	assign s_wbuf_axis_data = m_wbuf_axis_data;
	assign s_wbuf_axis_valid = m_wbuf_axis_valid;
	assign m_wbuf_axis_ready = s_wbuf_axis_ready;
	
	dcache_wbuffer #(
		.CACHE_DATA_WIDTH(CACHE_DATA_WIDTH),
		.CACHE_LINE_DATA_N(CACHE_LINE_DATA_N),
		.WBUF_ITEM_N(WBUF_ITEM_N),
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
		
		.m_axi_awaddr(m_axi_awaddr),
		.m_axi_awburst(m_axi_awburst),
		.m_axi_awlen(m_axi_awlen),
		.m_axi_awsize(m_axi_awsize),
		.m_axi_awvalid(m_axi_awvalid),
		.m_axi_awready(m_axi_awready),
		.m_axi_bresp(m_axi_bresp),
		.m_axi_bvalid(m_axi_bvalid),
		.m_axi_bready(m_axi_bready),
		.m_axi_wdata(m_axi_wdata),
		.m_axi_wstrb(m_axi_wstrb),
		.m_axi_wlast(m_axi_wlast),
		.m_axi_wvalid(m_axi_wvalid),
		.m_axi_wready(m_axi_wready)
	);
	
	/** Cache路访问热度记录表 **/
	// 记录存储器接口
	// [存储器写端口]
	wire hot_sram_clk_a;
	wire hot_sram_wen_a;
	wire[31:0] hot_sram_waddr_a;
	wire[23:0] hot_sram_din_a;
	// [存储器读端口]
	wire hot_sram_clk_b;
	wire hot_sram_ren_b;
	wire[31:0] hot_sram_raddr_b;
	wire[23:0] hot_sram_dout_b;
	
	dcache_way_access_hot_record #(
		.CACHE_WAY_N(CACHE_WAY_N),
		.CACHE_ENTRY_N(CACHE_ENTRY_N),
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
	// 数据存储器接口
	// [端口A]
	wire data_sram_clk_a[0:CACHE_WAY_N-1];
	wire data_sram_en_a[0:CACHE_WAY_N-1];
	wire[CACHE_DATA_WIDTH/8-1:0] data_sram_wen_a[0:CACHE_WAY_N-1];
	wire[31:0] data_sram_addr_a[0:CACHE_WAY_N-1];
	wire[CACHE_DATA_WIDTH-1:0] data_sram_din_a[0:CACHE_WAY_N-1];
	wire[CACHE_DATA_WIDTH-1:0] data_sram_dout_a[0:CACHE_WAY_N-1];
	// [端口B]
	wire data_sram_clk_b[0:CACHE_WAY_N-1];
	wire data_sram_en_b[0:CACHE_WAY_N-1];
	wire[CACHE_DATA_WIDTH/8-1:0] data_sram_wen_b[0:CACHE_WAY_N-1];
	wire[31:0] data_sram_addr_b[0:CACHE_WAY_N-1];
	wire[CACHE_DATA_WIDTH-1:0] data_sram_din_b[0:CACHE_WAY_N-1];
	wire[CACHE_DATA_WIDTH-1:0] data_sram_dout_b[0:CACHE_WAY_N-1];
	// 标签存储器接口
	// [端口A]
	wire tag_sram_clk_a[0:CACHE_WAY_N-1];
	wire tag_sram_en_a[0:CACHE_WAY_N-1];
	wire tag_sram_wen_a[0:CACHE_WAY_N-1];
	wire[31:0] tag_sram_addr_a[0:CACHE_WAY_N-1];
	wire[2+CACHE_TAG_WIDTH-1:0] tag_sram_din_a[0:CACHE_WAY_N-1]; // {dirty(1位), valid(1位), tag(CACHE_TAG_WIDTH位)}
	wire[2+CACHE_TAG_WIDTH-1:0] tag_sram_dout_a[0:CACHE_WAY_N-1]; // {dirty(1位), valid(1位), tag(CACHE_TAG_WIDTH位)}
	// [端口B]
	wire tag_sram_clk_b[0:CACHE_WAY_N-1];
	wire tag_sram_en_b[0:CACHE_WAY_N-1];
	wire tag_sram_wen_b[0:CACHE_WAY_N-1];
	wire[31:0] tag_sram_addr_b[0:CACHE_WAY_N-1];
	wire[2+CACHE_TAG_WIDTH-1:0] tag_sram_din_b[0:CACHE_WAY_N-1]; // {dirty(1位), valid(1位), tag(CACHE_TAG_WIDTH位)}
	wire[2+CACHE_TAG_WIDTH-1:0] tag_sram_dout_b[0:CACHE_WAY_N-1]; // {dirty(1位), valid(1位), tag(CACHE_TAG_WIDTH位)}
	
	genvar logic_dcache_way_i;
	generate
		for(logic_dcache_way_i = 0;logic_dcache_way_i < CACHE_WAY_N;logic_dcache_way_i = logic_dcache_way_i + 1)
		begin:logic_dcache_way_blk
			logic_dcache_way_mem #(
				.CACHE_DATA_WIDTH(CACHE_DATA_WIDTH),
				.CACHE_ENTRY_N(CACHE_ENTRY_N),
				.CACHE_LINE_DATA_N(CACHE_LINE_DATA_N),
				.CACHE_TAG_WIDTH(CACHE_TAG_WIDTH),
				.SIM_DELAY(SIM_DELAY)
			)logic_dcache_way_mem_u(
				.aclk(aclk),
				
				.cache_data_en_a(cache_data_en_a[logic_dcache_way_i]),
				.cache_data_byte_wen_a(cache_data_byte_wen_a[(logic_dcache_way_i+1)*(CACHE_DATA_WIDTH/8)-1:logic_dcache_way_i*(CACHE_DATA_WIDTH/8)]),
				.cache_data_addr_index_a(cache_data_addr_index_a[(logic_dcache_way_i+1)*32-1:logic_dcache_way_i*32]),
				.cache_data_addr_ofs_a(cache_data_addr_ofs_a[(logic_dcache_way_i+1)*8-1:logic_dcache_way_i*8]),
				.cache_din_a(cache_din_a[(logic_dcache_way_i+1)*CACHE_DATA_WIDTH-1:logic_dcache_way_i*CACHE_DATA_WIDTH]),
				.cache_dout_a(cache_dout_a[(logic_dcache_way_i+1)*CACHE_DATA_WIDTH-1:logic_dcache_way_i*CACHE_DATA_WIDTH]),
				.cache_data_en_b(cache_data_en_b[logic_dcache_way_i]),
				.cache_data_byte_wen_b(cache_data_byte_wen_b[(logic_dcache_way_i+1)*(CACHE_DATA_WIDTH/8)-1:logic_dcache_way_i*(CACHE_DATA_WIDTH/8)]),
				.cache_data_addr_index_b(cache_data_addr_index_b[(logic_dcache_way_i+1)*32-1:logic_dcache_way_i*32]),
				.cache_data_addr_ofs_b(cache_data_addr_ofs_b[(logic_dcache_way_i+1)*8-1:logic_dcache_way_i*8]),
				.cache_din_b(cache_din_b[(logic_dcache_way_i+1)*CACHE_DATA_WIDTH-1:logic_dcache_way_i*CACHE_DATA_WIDTH]),
				.cache_dout_b(cache_dout_b[(logic_dcache_way_i+1)*CACHE_DATA_WIDTH-1:logic_dcache_way_i*CACHE_DATA_WIDTH]),
				
				.cache_tag_en_a(cache_tag_en_a[logic_dcache_way_i]),
				.cache_tag_wen_a(cache_tag_wen_a[logic_dcache_way_i]),
				.cache_tag_addr_index_a(cache_tag_addr_index_a[(logic_dcache_way_i+1)*32-1:logic_dcache_way_i*32]),
				.cache_tag_addr_ofs_a(cache_tag_addr_ofs_a[(logic_dcache_way_i+1)*8-1:logic_dcache_way_i*8]),
				.cache_tag_addr_tag_a(cache_tag_addr_tag_a[(logic_dcache_way_i+1)*CACHE_TAG_WIDTH-1:logic_dcache_way_i*CACHE_TAG_WIDTH]),
				.cache_tag_din_valid_a(cache_tag_din_valid_a[logic_dcache_way_i]),
				.cache_tag_din_dirty_a(cache_tag_din_dirty_a[logic_dcache_way_i]),
				.cache_tag_dout_real_addr_a(cache_tag_dout_real_addr_a[(logic_dcache_way_i+1)*32-1:logic_dcache_way_i*32]),
				.cache_tag_dout_org_tag_a(cache_tag_dout_org_tag_a[(logic_dcache_way_i+1)*CACHE_TAG_WIDTH-1:logic_dcache_way_i*CACHE_TAG_WIDTH]),
				.cache_tag_dout_hit_a(cache_tag_dout_hit_a[logic_dcache_way_i]),
				.cache_tag_dout_valid_a(cache_tag_dout_valid_a[logic_dcache_way_i]),
				.cache_tag_dout_dirty_a(cache_tag_dout_dirty_a[logic_dcache_way_i]),
				.cache_tag_en_b(cache_tag_en_b[logic_dcache_way_i]),
				.cache_tag_wen_b(cache_tag_wen_b[logic_dcache_way_i]),
				.cache_tag_addr_index_b(cache_tag_addr_index_b[(logic_dcache_way_i+1)*32-1:logic_dcache_way_i*32]),
				.cache_tag_din_tag_b(cache_tag_din_tag_b[(logic_dcache_way_i+1)*CACHE_TAG_WIDTH-1:logic_dcache_way_i*CACHE_TAG_WIDTH]),
				.cache_tag_din_valid_b(cache_tag_din_valid_b[logic_dcache_way_i]),
				.cache_tag_din_dirty_b(cache_tag_din_dirty_b[logic_dcache_way_i]),
				.cache_tag_dout_valid_b(cache_tag_dout_valid_b[logic_dcache_way_i]),
				.cache_tag_dout_dirty_b(cache_tag_dout_dirty_b[logic_dcache_way_i]),
				
				.data_sram_clk_a(data_sram_clk_a[logic_dcache_way_i]),
				.data_sram_en_a(data_sram_en_a[logic_dcache_way_i]),
				.data_sram_wen_a(data_sram_wen_a[logic_dcache_way_i]),
				.data_sram_addr_a(data_sram_addr_a[logic_dcache_way_i]),
				.data_sram_din_a(data_sram_din_a[logic_dcache_way_i]),
				.data_sram_dout_a(data_sram_dout_a[logic_dcache_way_i]),
				.data_sram_clk_b(data_sram_clk_b[logic_dcache_way_i]),
				.data_sram_en_b(data_sram_en_b[logic_dcache_way_i]),
				.data_sram_wen_b(data_sram_wen_b[logic_dcache_way_i]),
				.data_sram_addr_b(data_sram_addr_b[logic_dcache_way_i]),
				.data_sram_din_b(data_sram_din_b[logic_dcache_way_i]),
				.data_sram_dout_b(data_sram_dout_b[logic_dcache_way_i]),
				
				.tag_sram_clk_a(tag_sram_clk_a[logic_dcache_way_i]),
				.tag_sram_en_a(tag_sram_en_a[logic_dcache_way_i]),
				.tag_sram_wen_a(tag_sram_wen_a[logic_dcache_way_i]),
				.tag_sram_addr_a(tag_sram_addr_a[logic_dcache_way_i]),
				.tag_sram_din_a(tag_sram_din_a[logic_dcache_way_i]),
				.tag_sram_dout_a(tag_sram_dout_a[logic_dcache_way_i]),
				.tag_sram_clk_b(tag_sram_clk_b[logic_dcache_way_i]),
				.tag_sram_en_b(tag_sram_en_b[logic_dcache_way_i]),
				.tag_sram_wen_b(tag_sram_wen_b[logic_dcache_way_i]),
				.tag_sram_addr_b(tag_sram_addr_b[logic_dcache_way_i]),
				.tag_sram_din_b(tag_sram_din_b[logic_dcache_way_i]),
				.tag_sram_dout_b(tag_sram_dout_b[logic_dcache_way_i])
			);
		end
	endgenerate
	
	/** 热度记录存储器、数据存储器、标签存储器 **/
	bram_true_dual_port #(
		.mem_width(24),
		.mem_depth(CACHE_ENTRY_N),
		.INIT_FILE("no_init"),
		.read_write_mode("read_first"),
		.use_output_register("false"),
		.en_byte_write("false"),
		.simulation_delay(SIM_DELAY)
	)hot_sram_u(
		.clk(hot_sram_clk_a),
		
		.ena(hot_sram_wen_a),
		.wea(hot_sram_wen_a),
		.addra(hot_sram_waddr_a),
		.dina(hot_sram_din_a),
		.douta(),
		
		.enb(hot_sram_ren_b),
		.web(1'b0),
		.addrb(hot_sram_raddr_b),
		.dinb(24'dx),
		.doutb(hot_sram_dout_b)
	);
	
	genvar data_sram_i;
	generate
		for(data_sram_i = 0;data_sram_i < CACHE_WAY_N;data_sram_i = data_sram_i + 1)
		begin:data_sram_blk
			bram_true_dual_port #(
				.mem_width(CACHE_DATA_WIDTH),
				.mem_depth(CACHE_ENTRY_N * CACHE_LINE_DATA_N),
				.INIT_FILE("no_init"),
				.read_write_mode("read_first"),
				.use_output_register("false"),
				.en_byte_write("true"),
				.simulation_delay(SIM_DELAY)
			)data_sram_u(
				.clk(data_sram_clk_a[data_sram_i]),
				
				.ena(data_sram_en_a[data_sram_i]),
				.wea(data_sram_wen_a[data_sram_i]),
				.addra(data_sram_addr_a[data_sram_i]),
				.dina(data_sram_din_a[data_sram_i]),
				.douta(data_sram_dout_a[data_sram_i]),
				
				.enb(data_sram_en_b[data_sram_i]),
				.web(data_sram_wen_b[data_sram_i]),
				.addrb(data_sram_addr_b[data_sram_i]),
				.dinb(data_sram_din_b[data_sram_i]),
				.doutb(data_sram_dout_b[data_sram_i])
			);
		end
	endgenerate
	
	genvar tag_sram_i;
	generate
		for(tag_sram_i = 0;tag_sram_i < CACHE_WAY_N;tag_sram_i = tag_sram_i + 1)
		begin:tag_sram_blk
			bram_true_dual_port #(
				.mem_width(2+CACHE_TAG_WIDTH),
				.mem_depth(CACHE_ENTRY_N),
				.INIT_FILE(""),
				.read_write_mode("read_first"),
				.use_output_register("false"),
				.en_byte_write("false"),
				.simulation_delay(SIM_DELAY)
			)tag_sram_u(
				.clk(tag_sram_clk_a[tag_sram_i]),
				
				.ena(tag_sram_en_a[tag_sram_i]),
				.wea(tag_sram_wen_a[tag_sram_i]),
				.addra(tag_sram_addr_a[tag_sram_i]),
				.dina(tag_sram_din_a[tag_sram_i]),
				.douta(tag_sram_dout_a[tag_sram_i]),
				
				.enb(tag_sram_en_b[tag_sram_i]),
				.web(tag_sram_wen_b[tag_sram_i]),
				.addrb(tag_sram_addr_b[tag_sram_i]),
				.dinb(tag_sram_din_b[tag_sram_i]),
				.doutb(tag_sram_dout_b[tag_sram_i])
			);
		end
	endgenerate
	
endmodule
