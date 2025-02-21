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
本模块: AXI-帧缓存

描述:
基于AXI-通用DMA引擎实现的帧缓存

注意：
输入/输出视频流与AXI主机使用相同的时钟和复位

协议:
APB SLAVE
AXI MASTER
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/02/21
********************************************************************/


module axi_frame_buffer #(
	parameter ONLY_FRAME_RD = "false", // 是否仅启用读像素通道
	parameter integer PIX_WIDTH = 16, // 像素位宽
	parameter integer BUS_WIDTH = 32, // 总线数据位宽
	parameter integer FRAME_W = 1920, // 帧宽度(以像素个数计)
	parameter integer FRAME_H = 1080, // 帧高度(以像素个数计)
	parameter integer FRAME_SIZE = FRAME_W * FRAME_H * 2, // 帧大小(以字节计, 必须<2^24)
	parameter integer MAX_BURST_LEN = 32, // 最大的突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter EN_ITR = "true", // 是否启用中断
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// APB从机的时钟和复位
	input wire pclk,
	input wire presetn,
	// AXI主机的时钟和复位
	input wire m_axi_aclk,
	input wire m_axi_aresetn,
	
	// 帧处理控制
	input wire frame_processed_ext, // 外部给出的当前帧已处理标志
	                                // 注意: 仅当不启用中断时可用!
	output wire frame_filled_ext, // 当前帧已填充标志(注意: 取上升沿!)
	output wire frame_fetched_ext, // 当前帧已取走标志(注意: 取上升沿!)
	
	// APB从机
    input wire[31:0] paddr,
    input wire psel,
    input wire penable,
    input wire pwrite,
    input wire[31:0] pwdata,
    output wire pready_out, // const -> 1'b1
    output wire[31:0] prdata_out,
    output wire pslverr_out, // const -> 1'b0
	
	// 输入视频流(AXIS从机)
	input wire[PIX_WIDTH-1:0] s_vin_axis_data,
	input wire s_vin_axis_user, // 帧首标志
	                            // ignored
	input wire s_vin_axis_last, // 行尾标志
	input wire s_vin_axis_valid,
	output wire s_vin_axis_ready,
	// 输出视频流(AXIS主机)
	output wire[PIX_WIDTH-1:0] m_vout_axis_data,
    output wire m_vout_axis_last, // 行尾标志
    output wire m_vout_axis_valid,
    input wire m_vout_axis_ready,
	
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
	output wire frame_wt_itr_req, // 帧写入中断请求
	output wire frame_rd_itr_req // 帧读取中断请求
);
	
	/** 寄存器配置接口 **/
	// 使能信号
	wire en_frame_buffer; // 使能帧缓存
	// 运行时参数
	wire[31:0] frame_buffer_baseaddr; // 帧缓存区基地址
	wire[2:0] frame_buffer_max_store_n_sub1; // 帧缓存区最大存储帧数 - 1
	// 帧处理控制
	wire frame_processed; // 当前帧已处理标志(注意: 取上升沿!)
	wire frame_filled_sync; // 当前帧已填充标志(注意: 取上升沿!)
	wire frame_fetched_sync; // 当前帧已取走标志(注意: 取上升沿!)
	
	/*
	跨时钟域:
		reg_if_for_frame_buffer_u/en_frame_buffer_r -> ...
		reg_if_for_frame_buffer_u/frame_buffer_baseaddr_r[*] -> ...
		reg_if_for_frame_buffer_u/frame_buffer_max_store_n_sub1_r[*] -> ...
		reg_if_for_frame_buffer_u/frame_processed_r -> ...
	*/
	reg_if_for_frame_buffer #(
		.SIM_DELAY(SIM_DELAY)
	)reg_if_for_frame_buffer_u(
		.clk(pclk),
		.resetn(presetn),
		
		.paddr(paddr),
		.psel(psel),
		.penable(penable),
		.pwrite(pwrite),
		.pwdata(pwdata),
		.pready_out(pready_out),
		.prdata_out(prdata_out),
		.pslverr_out(pslverr_out),
		
		.en_frame_buffer(en_frame_buffer),
		
		.frame_buffer_baseaddr(frame_buffer_baseaddr),
		.frame_buffer_max_store_n_sub1(frame_buffer_max_store_n_sub1),
		
		.frame_processed(frame_processed),
		.frame_filled(frame_filled_sync),
		.frame_fetched(frame_fetched_sync),
		
		.frame_wt_itr_req(frame_wt_itr_req),
		.frame_rd_itr_req(frame_rd_itr_req)
	);
	
	/** 帧缓存控制 **/
	// 使能信号
	wire en_frame_buffer_sync; // 使能帧缓存
	// 帧处理控制
	wire frame_processed_sync; // 当前帧已处理标志(注意: 取上升沿!)
	wire frame_filled; // 当前帧已填充标志(注意: 取上升沿!)
	wire frame_fetched; // 当前帧已取走标志(注意: 取上升沿!)
	// MM2S命令(AXIS主机)
	wire[55:0] m_mm2s_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m_mm2s_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	                           // const -> 1'b0
	wire m_mm2s_cmd_axis_last; // 帧尾标志
	                           // const -> 1'b1
	wire m_mm2s_cmd_axis_valid;
	wire m_mm2s_cmd_axis_ready;
	// MM2S数据流(AXIS从机)
	wire[BUS_WIDTH-1:0] s_mm2s_axis_data;
	wire[BUS_WIDTH/8-1:0] s_mm2s_axis_keep; // ignored
	wire[2:0] s_mm2s_axis_user; // {读请求最后1次传输标志(1bit), 
	                            //     错误类型(2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR)}
								// ignored
	wire s_mm2s_axis_last; // ignored
	wire s_mm2s_axis_valid;
	wire s_mm2s_axis_ready;
	// S2MM命令(AXIS主机)
	wire[55:0] m_s2mm_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m_s2mm_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	                           // const -> 1'b0
	wire m_s2mm_cmd_axis_valid;
	wire m_s2mm_cmd_axis_ready;
	// S2MM数据流(AXIS主机)
	wire[BUS_WIDTH-1:0] m_s2mm_axis_data;
	wire[BUS_WIDTH/8-1:0] m_s2mm_axis_keep; // const -> {(BUS_WIDTH/8){1'b1}}
	wire m_s2mm_axis_last;
	wire m_s2mm_axis_valid;
	wire m_s2mm_axis_ready;
	
	assign frame_filled_ext = frame_filled;
	assign frame_fetched_ext = frame_fetched;
	
	single_bit_syn #(
		.SYN_STAGE(3),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)single_bit_syn_u0(
		.clk(m_axi_aclk),
		.rst_n(m_axi_aresetn),
		
		.single_bit_in(en_frame_buffer),
		.single_bit_out(en_frame_buffer_sync)
	);
	single_bit_syn #(
		.SYN_STAGE(3),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)single_bit_syn_u1(
		.clk(m_axi_aclk),
		.rst_n(m_axi_aresetn),
		
		.single_bit_in((EN_ITR == "true") ? frame_processed:frame_processed_ext),
		.single_bit_out(frame_processed_sync)
	);
	single_bit_syn #(
		.SYN_STAGE(3),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)single_bit_syn_u2(
		.clk(pclk),
		.rst_n(presetn),
		
		.single_bit_in(frame_filled),
		.single_bit_out(frame_filled_sync)
	);
	single_bit_syn #(
		.SYN_STAGE(3),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)single_bit_syn_u3(
		.clk(pclk),
		.rst_n(presetn),
		
		.single_bit_in(frame_fetched),
		.single_bit_out(frame_fetched_sync)
	);
	
	/*
	跨时钟域:
		frame_buffer_ctrl_u/frame_filled_r -> ...
		frame_buffer_ctrl_u/frame_fetched_r -> ...
	*/
	frame_buffer_ctrl #(
		.ONLY_FRAME_RD(ONLY_FRAME_RD),
		.PIX_WIDTH(PIX_WIDTH),
		.STREAM_WIDTH(BUS_WIDTH),
		.FRAME_W(FRAME_W),
		.FRAME_H(FRAME_H),
		.FRAME_SIZE(FRAME_SIZE),
		.SIM_DELAY(SIM_DELAY)
	)frame_buffer_ctrl_u(
		.clk(m_axi_aclk),
		.resetn(m_axi_aresetn),
		
		.en_frame_buffer(en_frame_buffer_sync),
		
		.frame_buffer_baseaddr(frame_buffer_baseaddr),
		.frame_buffer_max_store_n_sub1(frame_buffer_max_store_n_sub1),
		
		.frame_processed(frame_processed_sync),
		.frame_filled(frame_filled),
		.frame_fetched(frame_fetched),
		
		.m_mm2s_cmd_axis_data(m_mm2s_cmd_axis_data),
		.m_mm2s_cmd_axis_user(m_mm2s_cmd_axis_user),
		.m_mm2s_cmd_axis_last(m_mm2s_cmd_axis_last),
		.m_mm2s_cmd_axis_valid(m_mm2s_cmd_axis_valid),
		.m_mm2s_cmd_axis_ready(m_mm2s_cmd_axis_ready),
		
		.m_vout_axis_data(m_vout_axis_data),
		.m_vout_axis_last(m_vout_axis_last),
		.m_vout_axis_valid(m_vout_axis_valid),
		.m_vout_axis_ready(m_vout_axis_ready),
		
		.s_mm2s_axis_data(s_mm2s_axis_data),
		.s_mm2s_axis_keep(s_mm2s_axis_keep),
		.s_mm2s_axis_user(s_mm2s_axis_user),
		.s_mm2s_axis_last(s_mm2s_axis_last),
		.s_mm2s_axis_valid(s_mm2s_axis_valid),
		.s_mm2s_axis_ready(s_mm2s_axis_ready),
		
		.m_s2mm_cmd_axis_data(m_s2mm_cmd_axis_data),
		.m_s2mm_cmd_axis_user(m_s2mm_cmd_axis_user),
		.m_s2mm_cmd_axis_valid(m_s2mm_cmd_axis_valid),
		.m_s2mm_cmd_axis_ready(m_s2mm_cmd_axis_ready),
		
		.s_vin_axis_data(s_vin_axis_data),
		.s_vin_axis_user(s_vin_axis_user),
		.s_vin_axis_last(s_vin_axis_last),
		.s_vin_axis_valid(s_vin_axis_valid),
		.s_vin_axis_ready(s_vin_axis_ready),
		
		.m_s2mm_axis_data(m_s2mm_axis_data),
		.m_s2mm_axis_keep(m_s2mm_axis_keep),
		.m_s2mm_axis_last(m_s2mm_axis_last),
		.m_s2mm_axis_valid(m_s2mm_axis_valid),
		.m_s2mm_axis_ready(m_s2mm_axis_ready)
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
	wire[BUS_WIDTH/8-1:0] m_mm2s_axis_keep;
	// 注意: 仅当在MM2S通道不允许非对齐传输时可用!
	wire[2:0] m_mm2s_axis_user; // {读请求最后1次传输标志(1bit), 
	                            //     错误类型(2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR)}
	wire m_mm2s_axis_last;
	wire m_mm2s_axis_valid;
	wire m_mm2s_axis_ready;
	
	assign s_mm2s_cmd_axis_data = m_mm2s_cmd_axis_data;
	assign s_mm2s_cmd_axis_user = m_mm2s_cmd_axis_user;
	assign s_mm2s_cmd_axis_last = m_mm2s_cmd_axis_last;
	assign s_mm2s_cmd_axis_valid = m_mm2s_cmd_axis_valid;
	assign m_mm2s_cmd_axis_ready = s_mm2s_cmd_axis_ready;
	
	assign s_s2mm_cmd_axis_data = m_s2mm_cmd_axis_data;
	assign s_s2mm_cmd_axis_user = m_s2mm_cmd_axis_user;
	assign s_s2mm_cmd_axis_valid = m_s2mm_cmd_axis_valid;
	assign m_s2mm_cmd_axis_ready = s_s2mm_cmd_axis_ready;
	
	assign s_s2mm_axis_data = m_s2mm_axis_data;
	assign s_s2mm_axis_keep = m_s2mm_axis_keep;
	assign s_s2mm_axis_last = m_s2mm_axis_last;
	assign s_s2mm_axis_valid = m_s2mm_axis_valid;
	assign m_s2mm_axis_ready = s_s2mm_axis_ready;
	
	assign s_mm2s_axis_data = m_mm2s_axis_data;
	assign s_mm2s_axis_keep = m_mm2s_axis_keep;
	assign s_mm2s_axis_user = m_mm2s_axis_user;
	assign s_mm2s_axis_last = m_mm2s_axis_last;
	assign s_mm2s_axis_valid = m_mm2s_axis_valid;
	assign m_mm2s_axis_ready = s_mm2s_axis_ready;
	
	axi_dma_engine #(
		.EN_RD_CHN("true"),
		.EN_WT_CHN((ONLY_FRAME_RD == "true") ? "false":"true"),
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
	
endmodule
