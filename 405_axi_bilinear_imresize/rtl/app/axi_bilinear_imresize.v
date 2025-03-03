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
本模块: AXI双线性插值处理模块

描述:
位于存储映射的源图片 ----读取----> 双线性插值处理 ----写回----> 位于存储映射的结果缓存区
支持32/64位AXI总线

注意：
无

协议:
APB SLAVE
AXI MASTER

作者: 陈家耀
日期: 2025/02/23
********************************************************************/


module axi_bilinear_imresize #(
	parameter integer BUS_WIDTH = 32, // AXI总线数据位宽(32 | 64)
	parameter integer MAX_BURST_LEN = 32, // AXI总线最大突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer RESIZE_SCALE_QUAZ_N = 8, // 缩放比例量化精度(必须在范围[4, 12]内)
	parameter integer SRC_BUF_MEM_DEPTH = 1024, // 源图片缓存MEM深度(512 | 1024 | 2048 | 4096)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// APB从机的时钟和复位
	input wire pclk,
	input wire presetn,
	// AXI主机的时钟和复位
	input wire m_axi_aclk,
	input wire m_axi_aresetn,
	
	// APB从机
    input wire[31:0] paddr,
    input wire psel,
    input wire penable,
    input wire pwrite,
    input wire[31:0] pwdata,
    output wire pready_out, // const -> 1'b1
    output wire[31:0] prdata_out,
    output wire pslverr_out, // const -> 1'b0
	
	// AXI主机
	// AR通道
	output wire[31:0] m_axi_araddr,
	// 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
	output wire[1:0] m_axi_arburst,
	output wire[3:0] m_axi_arcache, // const -> 4'b0011
	output wire[7:0] m_axi_arlen,
	output wire[2:0] m_axi_arprot, // const -> 3'b000
	output wire[2:0] m_axi_arsize, // const -> clogb2(BUS_WIDTH/8)
	output wire m_axi_arvalid,
	input wire m_axi_arready,
	// R通道
	input wire[BUS_WIDTH-1:0] m_axi_rdata,
	// 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
	input wire[1:0] m_axi_rresp,
	input wire m_axi_rlast,
	input wire m_axi_rvalid,
	output wire m_axi_rready,
	// AW通道
	output wire[31:0] m_axi_awaddr,
	// 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
	output wire[1:0] m_axi_awburst,
	output wire[3:0] m_axi_awcache, // const -> 4'b0011
	output wire[7:0] m_axi_awlen,
	output wire[2:0] m_axi_awprot, // const -> 3'b000
	output wire[2:0] m_axi_awsize, // const -> clogb2(BUS_WIDTH/8)
	output wire m_axi_awvalid,
	input wire m_axi_awready,
	// B通道
	// 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
	input wire[1:0] m_axi_bresp,
	input wire m_axi_bvalid,
	output wire m_axi_bready, // const -> 1'b1
	// W通道
	output wire[BUS_WIDTH-1:0] m_axi_wdata,
	output wire[BUS_WIDTH/8-1:0] m_axi_wstrb,
	output wire m_axi_wlast,
	output wire m_axi_wvalid,
	input wire m_axi_wready,
	
	// 中断请求
	output wire resize_fns_itr_req // 缩放完成中断请求
);
	
	/** 内部配置 **/
	// 双线性插值请求的数据位宽
	localparam integer REQ_WIDTH = 216;
	
	/** 配置寄存器区 **/
	// 双线性插值请求(AXIS主机, 上游)
	/*
	请求格式:{
		保留(6bit), 
		图片通道数 - 1(2bit), 
		源图片宽度 - 1(16bit), 
		源图片高度 - 1(16bit), 
		目标图片宽度 - 1(16bit), 
		目标图片高度 - 1(16bit), 
		水平缩放比例(无符号定点数: 源图片宽度 / 目标图标宽度, 16bit), 
		竖直缩放比例(无符号定点数: 源图片高度 / 目标图标高度, 16bit), 
		源图片行跨度(以字节计, 16bit), 
		目标图片行跨度(以字节计, 16bit), 
		结果缓存区行跨度(以字节计, 16bit), 
		源图片基地址(32bit), 
		结果缓存区基地址(32bit)
	}
	*/
	wire[REQ_WIDTH-1:0] m_up_req_axis_data;
	wire m_up_req_axis_valid;
	wire m_up_req_axis_ready;
	// 缩放控制
	wire resize_fns; // 位于AXI时钟域的缩放完成标志(注意: 取上升沿!)
	wire resize_fns_sync; // 同步到APB时钟域的缩放完成标志(注意: 取上升沿!)
	
	single_bit_syn #(
		.SYN_STAGE(3),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)single_bit_syn_u0(
		.clk(pclk),
		.rst_n(presetn),
		
		.single_bit_in(resize_fns),
		.single_bit_out(resize_fns_sync)
	);
	
	reg_if_for_imresize #(
		.BUS_WIDTH(BUS_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)reg_if_for_imresize_u(
		.pclk(pclk),
		.presetn(presetn),
		.m_axi_aclk(m_axi_aclk),
		.m_axi_aresetn(m_axi_aresetn),
		
		.paddr(paddr),
		.psel(psel),
		.penable(penable),
		.pwrite(pwrite),
		.pwdata(pwdata),
		.pready_out(pready_out),
		.prdata_out(prdata_out),
		.pslverr_out(pslverr_out),
		
		.resize_fns(resize_fns_sync),
		
		.m_req_axis_data(m_up_req_axis_data),
		.m_req_axis_valid(m_up_req_axis_valid),
		.m_req_axis_ready(m_up_req_axis_ready),
		
		.resize_fns_itr_req(resize_fns_itr_req)
	);
	
	/** AXI通用DMA引擎 **/
	// MM2S命令AXIS从机
	wire[55:0] s_mm2s_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire s_mm2s_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire s_mm2s_cmd_axis_last; // 帧尾标志
	wire s_mm2s_cmd_axis_valid;
	wire s_mm2s_cmd_axis_ready;
	// S2MM命令AXIS从机
	wire[55:0] s_s2mm_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire s_s2mm_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire s_s2mm_cmd_axis_valid;
	wire s_s2mm_cmd_axis_ready;
	// 输入数据流AXIS从机
	wire[BUS_WIDTH-1:0] s_s2mm_axis_data;
	wire[BUS_WIDTH/8-1:0] s_s2mm_axis_keep;
	wire s_s2mm_axis_last;
	wire s_s2mm_axis_valid;
	wire s_s2mm_axis_ready;
	// 输出数据流AXIS主机
	wire[BUS_WIDTH-1:0] m_mm2s_axis_data;
	wire[BUS_WIDTH/8-1:0] m_mm2s_axis_keep; // not used!
	// 注意: 仅当在MM2S通道不允许非对齐传输时可用!
	wire[2:0] m_mm2s_axis_user; // {读请求最后1次传输标志(1bit), 
	                            //     错误类型(2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR)}
								// not used!
	wire m_mm2s_axis_last;
	wire m_mm2s_axis_valid;
	wire m_mm2s_axis_ready;
	
	axi_dma_engine #(
		.EN_RD_CHN("true"),
		.EN_WT_CHN("true"),
		.DATA_WIDTH(BUS_WIDTH),
		.MAX_BURST_LEN(MAX_BURST_LEN),
		.S_CMD_AXIS_COMMON_CLOCK("true"),
		.M_MM2S_AXIS_COMMON_CLOCK("true"),
		.S_S2MM_AXIS_COMMON_CLOCK("true"),
		.EN_WT_BYTES_N_STAT("false"),
		.EN_MM2S_UNALIGNED_TRANS("false"),
		.EN_S2MM_UNALIGNED_TRANS("false"),
		.SIM_DELAY(SIM_DELAY)
	)axi_dma_engine_u(
		.s_cmd_axis_aclk(m_axi_aclk),
		.s_cmd_axis_aresetn(m_axi_aresetn),
		.s_s2mm_axis_aclk(m_axi_aclk),
		.s_s2mm_axis_aresetn(m_axi_aresetn),
		.m_mm2s_axis_aclk(m_axi_aclk),
		.m_mm2s_axis_aresetn(m_axi_aresetn),
		.m_axi_aclk(m_axi_aclk),
		.m_axi_aresetn(m_axi_aresetn),
		
		.s_mm2s_cmd_axis_data(s_mm2s_cmd_axis_data),
		.s_mm2s_cmd_axis_user(s_mm2s_cmd_axis_user),
		.s_mm2s_cmd_axis_last(s_mm2s_cmd_axis_last),
		.s_mm2s_cmd_axis_valid(s_mm2s_cmd_axis_valid),
		.s_mm2s_cmd_axis_ready(s_mm2s_cmd_axis_ready),
		
		.s_s2mm_cmd_axis_data(s_s2mm_cmd_axis_data),
		.s_s2mm_cmd_axis_user(s_s2mm_cmd_axis_user),
		.s_s2mm_cmd_axis_valid(s_s2mm_cmd_axis_valid),
		.s_s2mm_cmd_axis_ready(s_s2mm_cmd_axis_ready),
		
		.s_s2mm_axis_data(s_s2mm_axis_data),
		.s_s2mm_axis_keep(s_s2mm_axis_keep),
		.s_s2mm_axis_last(s_s2mm_axis_last),
		.s_s2mm_axis_valid(s_s2mm_axis_valid),
		.s_s2mm_axis_ready(s_s2mm_axis_ready),
		
		.m_mm2s_axis_data(m_mm2s_axis_data),
		.m_mm2s_axis_keep(m_mm2s_axis_keep),
		.m_mm2s_axis_user(m_mm2s_axis_user),
		.m_mm2s_axis_last(m_mm2s_axis_last),
		.m_mm2s_axis_valid(m_mm2s_axis_valid),
		.m_mm2s_axis_ready(m_mm2s_axis_ready),
		
		.m_axi_araddr(m_axi_araddr),
		.m_axi_arburst(m_axi_arburst),
		.m_axi_arcache(m_axi_arcache),
		.m_axi_arlen(m_axi_arlen),
		.m_axi_arprot(m_axi_arprot),
		.m_axi_arsize(m_axi_arsize),
		.m_axi_arvalid(m_axi_arvalid),
		.m_axi_arready(m_axi_arready),
		.m_axi_rdata(m_axi_rdata),
		.m_axi_rresp(m_axi_rresp),
		.m_axi_rlast(m_axi_rlast),
		.m_axi_rvalid(m_axi_rvalid),
		.m_axi_rready(m_axi_rready),
		.m_axi_awaddr(m_axi_awaddr),
		.m_axi_awburst(m_axi_awburst),
		.m_axi_awcache(m_axi_awcache),
		.m_axi_awlen(m_axi_awlen),
		.m_axi_awprot(m_axi_awprot),
		.m_axi_awsize(m_axi_awsize),
		.m_axi_awvalid(m_axi_awvalid),
		.m_axi_awready(m_axi_awready),
		.m_axi_wdata(m_axi_wdata),
		.m_axi_wstrb(m_axi_wstrb),
		.m_axi_wlast(m_axi_wlast),
		.m_axi_wvalid(m_axi_wvalid),
		.m_axi_wready(m_axi_wready),
		.m_axi_bresp(m_axi_bresp),
		.m_axi_bvalid(m_axi_bvalid),
		.m_axi_bready(m_axi_bready),
		
		.s2mm_err_flag()
	);
	
	/** DMA命令生成 **/
	// 双线性插值请求(AXIS从机, 上游)
	wire[REQ_WIDTH-1:0] s_up_req_axis_data;
	wire s_up_req_axis_valid;
	wire s_up_req_axis_ready;
	// 双线性插值请求(AXIS主机, 下游)
	wire[REQ_WIDTH-1:0] m_down_req_axis_data;
	wire m_down_req_axis_valid;
	wire m_down_req_axis_ready;
	// MM2S命令(AXIS主机)
	wire[55:0] m_mm2s_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m_mm2s_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	                           // const -> 1'b0
	wire m_mm2s_cmd_axis_last; // 帧尾标志
	                           // const -> 1'b1
	wire m_mm2s_cmd_axis_valid;
	wire m_mm2s_cmd_axis_ready;
	// S2MM命令(AXIS主机)
	wire[55:0] m_s2mm_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m_s2mm_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	                           // const -> 1'b0
	wire m_s2mm_cmd_axis_valid;
	wire m_s2mm_cmd_axis_ready;
	
	assign s_up_req_axis_data = m_up_req_axis_data;
	assign s_up_req_axis_valid = m_up_req_axis_valid;
	assign m_up_req_axis_ready = s_up_req_axis_ready;
	
	assign s_mm2s_cmd_axis_data = m_mm2s_cmd_axis_data;
	assign s_mm2s_cmd_axis_user = m_mm2s_cmd_axis_user;
	assign s_mm2s_cmd_axis_last = m_mm2s_cmd_axis_last;
	assign s_mm2s_cmd_axis_valid = m_mm2s_cmd_axis_valid;
	assign m_mm2s_cmd_axis_ready = s_mm2s_cmd_axis_ready;
	
	assign s_s2mm_cmd_axis_data = m_s2mm_cmd_axis_data;
	assign s_s2mm_cmd_axis_user = m_s2mm_cmd_axis_user;
	assign s_s2mm_cmd_axis_valid = m_s2mm_cmd_axis_valid;
	assign m_s2mm_cmd_axis_ready = s_s2mm_cmd_axis_ready;
	
	axis_dma_cmd_gen_for_imresize #(
		.RESIZE_SCALE_QUAZ_N(RESIZE_SCALE_QUAZ_N),
		.SIM_DELAY(SIM_DELAY)
	)axis_dma_cmd_gen_for_imresize_u(
		.clk(m_axi_aclk),
		.resetn(m_axi_aresetn),
		
		.s_req_axis_data(s_up_req_axis_data),
		.s_req_axis_valid(s_up_req_axis_valid),
		.s_req_axis_ready(s_up_req_axis_ready),
		
		.m_req_axis_data(m_down_req_axis_data),
		.m_req_axis_valid(m_down_req_axis_valid),
		.m_req_axis_ready(m_down_req_axis_ready),
		
		.m_mm2s_cmd_axis_data(m_mm2s_cmd_axis_data),
		.m_mm2s_cmd_axis_user(m_mm2s_cmd_axis_user),
		.m_mm2s_cmd_axis_last(m_mm2s_cmd_axis_last),
		.m_mm2s_cmd_axis_valid(m_mm2s_cmd_axis_valid),
		.m_mm2s_cmd_axis_ready(m_mm2s_cmd_axis_ready),
		
		.m_s2mm_cmd_axis_data(m_s2mm_cmd_axis_data),
		.m_s2mm_cmd_axis_user(m_s2mm_cmd_axis_user),
		.m_s2mm_cmd_axis_valid(m_s2mm_cmd_axis_valid),
		.m_s2mm_cmd_axis_ready(m_s2mm_cmd_axis_ready)
	);
	
	/** 源图片行缓存 **/
	// 源图片像素流(AXIS从机)
	wire[BUS_WIDTH-1:0] s_src_buf_axis_data;
	wire s_src_buf_axis_last; // 行尾指示
	wire s_src_buf_axis_valid;
	wire s_src_buf_axis_ready;
	// 源图片缓存虚拟fifo读端口
	wire src_img_vfifo_ren;
	wire src_img_vfifo_empty_n;
	// 源图片缓存MEM读端口
	wire src_img_mem_ren;
	wire[15:0] src_img_mem_raddr; // 以字节计
	wire[7:0] src_img_mem_dout_0;
	wire[7:0] src_img_mem_dout_1;
	
	assign s_src_buf_axis_data = m_mm2s_axis_data;
	assign s_src_buf_axis_last = m_mm2s_axis_last;
	assign s_src_buf_axis_valid = m_mm2s_axis_valid;
	assign m_mm2s_axis_ready = s_src_buf_axis_ready;
	
	axis_in_rows_buffer_for_imresize #(
		.STREAM_WIDTH(BUS_WIDTH),
		.BUF_MEM_DEPTH(SRC_BUF_MEM_DEPTH),
		.USE_DUAL_PORT_RAM("true"),
		.SIM_DELAY(SIM_DELAY)
	)axis_in_rows_buffer_for_imresize_u(
		.clk(m_axi_aclk),
		.resetn(m_axi_aresetn),
		
		.s_axis_data(s_src_buf_axis_data),
		.s_axis_last(s_src_buf_axis_last),
		.s_axis_valid(s_src_buf_axis_valid),
		.s_axis_ready(s_src_buf_axis_ready),
		
		.src_img_vfifo_ren(src_img_vfifo_ren),
		.src_img_vfifo_empty_n(src_img_vfifo_empty_n),
		
		.src_img_mem_ren(src_img_mem_ren),
		.src_img_mem_raddr(src_img_mem_raddr),
		.src_img_mem_dout_0(src_img_mem_dout_0),
		.src_img_mem_dout_1(src_img_mem_dout_1)
	);
	
	/** 双线性插值计算模块 **/
	// 双线性插值请求(AXIS从机, 下游)
	wire[REQ_WIDTH-1:0] s_down_req_axis_data;
	wire s_down_req_axis_valid;
	wire s_down_req_axis_ready;
	// 计算结果流(AXIS主机)
	wire[BUS_WIDTH-1:0] m_res_axis_data;
	wire[BUS_WIDTH/8-1:0] m_res_axis_keep;
	wire m_res_axis_last; // 行尾标志
	wire m_res_axis_valid;
	wire m_res_axis_ready;
	
	assign s_down_req_axis_data = m_down_req_axis_data;
	assign s_down_req_axis_valid = m_down_req_axis_valid;
	assign m_down_req_axis_ready = s_down_req_axis_ready;
	
	assign s_s2mm_axis_data = m_res_axis_data;
	assign s_s2mm_axis_keep = m_res_axis_keep;
	assign s_s2mm_axis_last = m_res_axis_last;
	assign s_s2mm_axis_valid = m_res_axis_valid;
	assign m_res_axis_ready = s_s2mm_axis_ready;
	
	axis_bilinear_imresize #(
		.STREAM_WIDTH(BUS_WIDTH),
		.RESIZE_SCALE_QUAZ_N(RESIZE_SCALE_QUAZ_N),
		.SIM_DELAY(SIM_DELAY)
	)axis_bilinear_imresize_u(
		.clk(m_axi_aclk),
		.resetn(m_axi_aresetn),
		
		.s_req_axis_data(s_down_req_axis_data),
		.s_req_axis_valid(s_down_req_axis_valid),
		.s_req_axis_ready(s_down_req_axis_ready),
		
		.src_img_vfifo_ren(src_img_vfifo_ren),
		.src_img_vfifo_empty_n(src_img_vfifo_empty_n),
		
		.src_img_mem_ren(src_img_mem_ren),
		.src_img_mem_raddr(src_img_mem_raddr),
		.src_img_mem_dout_0(src_img_mem_dout_0),
		.src_img_mem_dout_1(src_img_mem_dout_1),
		
		.m_res_axis_data(m_res_axis_data),
		.m_res_axis_keep(m_res_axis_keep),
		.m_res_axis_last(m_res_axis_last),
		.m_res_axis_valid(m_res_axis_valid),
		.m_res_axis_ready(m_res_axis_ready),
		
		.resize_fns(resize_fns)
	);
	
endmodule
