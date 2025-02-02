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
本模块: 用于获取读/写请求描述子的AXI读通道

描述:
通过AXI读通道从读/写请求缓存区获取描述子, 产生描述子流

32位地址64位数据的AXI读通道

每个读请求描述子的长度是64bit -> 
	位编号            内容
	 31~0            基地址
	 33~32      派发目标类型编号
	         (2'b00 -> 线性参数缓存, 
			 2'b01 -> 卷积核参数缓存, 
			 2'b10 -> 输入特征图缓存)
	 35~34         数据包信息
              (见派发信息流的描述)
	 63~36       待读取的字节数

每个写请求描述子的长度是64bit -> 
	位编号            内容
	 31~0            基地址
	 63~32       待写入的字节数

注意：
必须保证读/写请求缓存区首地址能被(axi_rchn_max_burst_len*8)整除, 从而确保每次突发传输不会跨越4KB边界

协议:
BLK CTRL
AXIS MASTER
AXI MASTER(READ ONLY)

作者: 陈家耀
日期: 2024/11/08
********************************************************************/


module axi_rw_req_dsc_dma #(
	parameter integer max_req_n = 1024, // 最大的读/写请求个数
	parameter integer axi_rchn_max_burst_len = 8, // AXI读通道最大突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer rw_req_dsc_buffer_depth = 512, // 读/写请求描述子buffer深度(256 | 512 | 1024 | ...)
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 运行时参数
	input wire[31:0] req_buf_baseaddr, // 读/写请求缓存区首地址
	input wire[31:0] req_n, // 读/写请求个数 - 1
	
	// 块级控制
	input wire blk_start,
	output wire blk_idle,
	output wire blk_done,
	
	// 读/写请求描述子(AXIS主机)
	output wire[63:0] m_axis_dsc_data,
	output wire m_axis_dsc_valid,
	input wire m_axis_dsc_ready,
	
	// AXI主机(读通道)
	// AR
    output wire[31:0] m_axi_araddr,
    output wire[1:0] m_axi_arburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_arlen,
    output wire[2:0] m_axi_arsize, // const -> 3'b011
    output wire m_axi_arvalid,
    input wire m_axi_arready,
    // R
    input wire[63:0] m_axi_rdata,
    input wire[1:0] m_axi_rresp, // ignored
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output wire m_axi_rready
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
	
	/** 块级控制 **/
	reg blk_idle_reg; // DMA空闲标志
	
	assign blk_idle = blk_idle_reg;
	
	// DMA空闲标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			blk_idle_reg <= 1'b1;
		else
			blk_idle_reg <= # simulation_delay blk_idle ? (~blk_start):blk_done;
	end
	
	/** AXI读地址通道 **/
	wire rw_req_dsc_buf_allow_ar_trans; // 读/写请求描述子buffer允许启动读地址传输(标志)
	reg[31:0] araddr; // 读地址
	reg[7:0] arlen; // 读突发长度
	reg arvalid; // 读地址通道有效
	reg[clogb2(max_req_n-1):0] req_n_remaining; // 剩余的读/写请求个数 - 1
	wire[clogb2(max_req_n-1):0] arlen_cmp; // 用于生成读突发长度的(剩余的读/写请求个数 - 1)
	reg ar_last; // 最后1个读地址(标志)
	reg last_rd_burst_processing; // 正在处理最后1个读突发(标志)
	reg rd_burst_processing; // 读突发处理中(标志)
	
	assign blk_done = m_axi_rvalid & m_axi_rready & m_axi_rlast & last_rd_burst_processing;
	
	assign m_axi_araddr = araddr;
	assign m_axi_arburst = 2'b01;
	assign m_axi_arlen = arlen;
	assign m_axi_arsize = 3'b011;
	assign m_axi_arvalid = arvalid;
	
	assign arlen_cmp = (blk_start & blk_idle) ? req_n[clogb2(max_req_n-1):0]:req_n_remaining;
	
	// 读地址
	always @(posedge clk)
	begin
		if((blk_start & blk_idle) | (m_axi_arvalid & m_axi_arready))
			araddr <= # simulation_delay (blk_start & blk_idle) ? 
				req_buf_baseaddr:(araddr + (axi_rchn_max_burst_len * 8));
	end
	
	// 读突发长度
	always @(posedge clk)
	begin
		if((blk_start & blk_idle) | (m_axi_arvalid & m_axi_arready))
			arlen <= # simulation_delay (arlen_cmp <= (axi_rchn_max_burst_len - 1)) ? 
				arlen_cmp:(axi_rchn_max_burst_len - 1);
	end
	
	// 读地址通道有效
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			arvalid <= 1'b0;
		else
			arvalid <= # simulation_delay arvalid ? 
				(~m_axi_arready):((~blk_idle) & rw_req_dsc_buf_allow_ar_trans & (~rd_burst_processing));
	end
	
	// 剩余的读/写请求个数 - 1
	always @(posedge clk)
	begin
		if((blk_start & blk_idle) | (m_axi_arvalid & m_axi_arready))
			req_n_remaining <= # simulation_delay arlen_cmp - axi_rchn_max_burst_len;
	end
	
	// 最后1个读地址(标志)
	always @(posedge clk)
	begin
		if((blk_start & blk_idle) | (m_axi_arvalid & m_axi_arready))
			ar_last <= # simulation_delay arlen_cmp <= (axi_rchn_max_burst_len - 1);
	end
	
	// 正在处理最后1个读突发(标志)
	always @(posedge clk)
	begin
		if(m_axi_arvalid & m_axi_arready)
			last_rd_burst_processing <= # simulation_delay ar_last;
	end
	
	// 读突发处理中(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rd_burst_processing <= 1'b0;
		else if((m_axi_arvalid & m_axi_arready) | (m_axi_rvalid & m_axi_rready & m_axi_rlast))
			// 断言: AR通道握手和R通道握手且处于读突发最后1个数据不可能同时发生!
			rd_burst_processing <= # simulation_delay m_axi_arvalid & m_axi_arready;
	end
	
	/** 读/写请求描述子buffer **/
	wire on_new_rd_burst_start; // 启动新的读突发(指示)
	wire on_fetch_rd_burst_data; // 取走读突发数据(指示)
	reg[clogb2(rw_req_dsc_buffer_depth/axi_rchn_max_burst_len):0] rd_burst_launched; // 已启动的读突发个数(地址通道握手但后级未取走读数据)
	reg rw_req_dsc_buf_full_n; // 读/写请求描述子buffer满标志
	wire m_axis_dsc_last; // 标志读突发最后1个数据
	
	assign rw_req_dsc_buf_allow_ar_trans = rw_req_dsc_buf_full_n;
	
	assign on_new_rd_burst_start = m_axi_arvalid & m_axi_arready;
	assign on_fetch_rd_burst_data = m_axis_dsc_valid & m_axis_dsc_ready & m_axis_dsc_last;
	
	// 已启动的读突发个数
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rd_burst_launched <= 0;
		else if(on_new_rd_burst_start ^ on_fetch_rd_burst_data)
			rd_burst_launched <= # simulation_delay on_new_rd_burst_start ? (rd_burst_launched + 1):(rd_burst_launched - 1);
	end
	
	// 读/写请求描述子buffer满标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rw_req_dsc_buf_full_n <= 1'b1;
		else if(on_new_rd_burst_start ^ on_fetch_rd_burst_data)
			// on_new_rd_burst_start ? (rd_burst_launched != (rw_req_dsc_buffer_depth/axi_rchn_max_burst_len-1)):1'b1
			rw_req_dsc_buf_full_n <= # simulation_delay 
				(~on_new_rd_burst_start) | (rd_burst_launched != (rw_req_dsc_buffer_depth/axi_rchn_max_burst_len-1));
	end
	
	// 读/写请求描述子缓存AXIS数据fifo
	axis_data_fifo #(
		.is_async("false"),
		.en_packet_mode("false"),
		.ram_type("bram"),
		.fifo_depth(rw_req_dsc_buffer_depth),
		.data_width(64),
		.user_width(1),
		.simulation_delay(simulation_delay)
	)rw_req_dsc_buffer(
		.s_axis_aclk(clk),
		.s_axis_aresetn(rst_n),
		.m_axis_aclk(clk),
		.m_axis_aresetn(rst_n),
		
		.s_axis_data(m_axi_rdata),
		.s_axis_keep(8'bxxxx_xxxx),
		.s_axis_strb(8'bxxxx_xxxx),
		.s_axis_user(1'bx),
		.s_axis_last(m_axi_rlast),
		.s_axis_valid(m_axi_rvalid),
		.s_axis_ready(m_axi_rready),
		
		.m_axis_data(m_axis_dsc_data),
		.m_axis_keep(),
		.m_axis_strb(),
		.m_axis_user(),
		.m_axis_last(m_axis_dsc_last),
		.m_axis_valid(m_axis_dsc_valid),
		.m_axis_ready(m_axis_dsc_ready)
	);
	
endmodule
