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
本模块: AXIS视频输入

描述:
收集来自DVP接口的视频流, 存入异步fifo并以AXIS主机的方式输出

注意：
必须保证异步fifo非满, 即写像素不溢出

协议:
DVP SLAVE
AXIS MASTER

作者: 陈家耀
日期: 2025/02/16
********************************************************************/


module axis_video_in #(
	parameter integer PIX_WIDTH = 8, // DVP像素位宽
	parameter integer STREAM_WIDTH = 16, // 像素流数据位宽
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 像素时钟和复位
	input wire pclk,
	input wire presetn,
	// AXIS主机时钟和复位
	input wire m_axis_aclk,
	input wire m_axis_aresetn,
	
	// 使能信号
	input wire en_video_in,
	
	// DVP接口
	input wire href,
	input wire vsync,
	input wire[PIX_WIDTH-1:0] pix,
	
	// 像素流(AXIS主机)
	output wire[STREAM_WIDTH-1:0] m_axis_data,
	output wire m_axis_user, // 帧首标志
	output wire m_axis_last, // 行尾标志
	output wire m_axis_valid,
	input wire m_axis_ready,
	
	// 错误标志
    output wire video_in_ovf // 写像素溢出标志
);
	
	/** 延迟1~2clk的DVP信号 **/
	reg href_d;
	reg vsync_d;
	reg vsync_d2;
	reg[PIX_WIDTH-1:0] pix_d;
	
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			href_d <= 1'b0;
		else
			href_d <= # SIM_DELAY href;
	end
	
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			{vsync_d2, vsync_d} <= 2'b00;
		else
			{vsync_d2, vsync_d} <= # SIM_DELAY {vsync_d, vsync};
	end
	
	always @(posedge pclk)
	begin
		if(href)
			pix_d <= # SIM_DELAY pix;
	end
	
	/** 行尾和帧首指示 **/
	wire eol; // 行尾标志
	reg sof; // 帧首标志
	
	assign eol = (~href) & href_d;
	
	// 帧首指示
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			sof <= 1'b1;
		else if(sof ? 
			href_d:
			(vsync_d & (~vsync_d2))
		)
			sof <= # SIM_DELAY ~sof;
	end
	
	/** 帧写入使能 **/
	wire en_frame_wt; // 帧写入使能
	reg[2:0] frame_init_onehot; // 帧初始化独热码
	reg[4:0] frame_n_ignored; // 已忽略的帧数
	
	assign en_frame_wt = frame_init_onehot[2];
	
	// 帧初始化独热码
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			frame_init_onehot <= 3'b001;
		else if((frame_init_onehot[0] & en_video_in) | 
			// 忽略前30帧
			(frame_init_onehot[1] & (frame_n_ignored == 5'd29) & vsync_d & (~vsync_d2) & (~sof))
		)
			frame_init_onehot <= # SIM_DELAY {frame_init_onehot[1:0], frame_init_onehot[2]};
	end
	
	// 已忽略的帧数
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			frame_n_ignored <= 5'd0;
		else if(frame_init_onehot[1] & vsync_d & (~vsync_d2) & (~sof))
			frame_n_ignored <= # SIM_DELAY frame_n_ignored + 5'd1;
	end
	
	/** 异步fifo **/
	// fifo写端口
	wire[PIX_WIDTH-1:0] s_fifo_axis_data;
	wire s_fifo_axis_user; // 帧首标志
	wire s_fifo_axis_last; // 行尾标志
	wire s_fifo_axis_valid;
	wire s_fifo_axis_ready;
	// fifo读端口
	wire[PIX_WIDTH-1:0] m_fifo_axis_data;
	wire m_fifo_axis_user; // 帧首标志
	wire m_fifo_axis_last; // 行尾标志
	wire m_fifo_axis_valid;
	wire m_fifo_axis_ready;
	
	assign s_fifo_axis_data = pix_d;
	assign s_fifo_axis_user = sof;
	assign s_fifo_axis_last = eol;
	assign s_fifo_axis_valid = en_frame_wt & href_d;
	
	axis_data_fifo #(
		.is_async("true"),
		.en_packet_mode("false"),
		.ram_type("bram"),
		.fifo_depth(2048),
		.data_width(PIX_WIDTH),
		.user_width(1),
		.simulation_delay(SIM_DELAY)
	)async_fifo(
		.s_axis_aclk(pclk),
		.s_axis_aresetn(presetn),
		.m_axis_aclk(m_axis_aclk),
		.m_axis_aresetn(m_axis_aresetn),
		
		.s_axis_data(s_fifo_axis_data),
		.s_axis_keep(1'bx),
		.s_axis_strb(1'bx),
		.s_axis_user(s_fifo_axis_user),
		.s_axis_last(s_fifo_axis_last),
		.s_axis_valid(s_fifo_axis_valid),
		.s_axis_ready(s_fifo_axis_ready),
		
		.m_axis_data(m_fifo_axis_data),
		.m_axis_keep(),
		.m_axis_strb(),
		.m_axis_user(m_fifo_axis_user),
		.m_axis_last(m_fifo_axis_last),
		.m_axis_valid(m_fifo_axis_valid),
		.m_axis_ready(m_fifo_axis_ready)
	);
	
	/** 像素流位宽变换 **/
	// AXIS从机
	wire[PIX_WIDTH-1:0] s_dw_cvt_axis_data;
	wire s_dw_cvt_axis_user; // 帧首标志
	wire s_dw_cvt_axis_last; // 行尾标志
	wire s_dw_cvt_axis_valid;
	wire s_dw_cvt_axis_ready;
	// AXIS主机
	wire[STREAM_WIDTH-1:0] m_dw_cvt_axis_data;
	wire m_dw_cvt_axis_user; // 帧首标志
	wire m_dw_cvt_axis_last; // 行尾标志
	wire m_dw_cvt_axis_valid;
	wire m_dw_cvt_axis_ready;
	
	assign s_dw_cvt_axis_data = m_fifo_axis_data;
	assign s_dw_cvt_axis_user = m_fifo_axis_user;
	assign s_dw_cvt_axis_last = m_fifo_axis_last;
	assign s_dw_cvt_axis_valid = m_fifo_axis_valid;
	assign m_fifo_axis_ready = s_dw_cvt_axis_ready;
	
	assign m_axis_data = m_dw_cvt_axis_data;
	assign m_axis_user = m_dw_cvt_axis_user;
	assign m_axis_last = m_dw_cvt_axis_last;
	assign m_axis_valid = m_dw_cvt_axis_valid;
	assign m_dw_cvt_axis_ready = m_axis_ready;
	
	axis_dw_cvt #(
		.slave_data_width(PIX_WIDTH),
		.master_data_width(STREAM_WIDTH),
		.slave_user_width_foreach_byte(1),
		.en_keep("false"),
		.en_last("true"),
		.en_out_isolation("true"),
		.simulation_delay(SIM_DELAY)
	)axis_dw_cvt_u(
		.clk(m_axis_aclk),
		.rst_n(m_axis_aresetn),
		
		.s_axis_data(s_dw_cvt_axis_data),
		.s_axis_keep({(PIX_WIDTH/8){1'b1}}),
		.s_axis_user({(PIX_WIDTH/8){s_dw_cvt_axis_user}}),
		.s_axis_last(s_dw_cvt_axis_last),
		.s_axis_valid(s_dw_cvt_axis_valid),
		.s_axis_ready(s_dw_cvt_axis_ready),
		
		.m_axis_data(m_dw_cvt_axis_data),
		.m_axis_keep(),
		.m_axis_user(m_dw_cvt_axis_user), // 位宽(STREAM_WIDTH/8)与位宽1不符, 取低位
		.m_axis_last(m_dw_cvt_axis_last),
		.m_axis_valid(m_dw_cvt_axis_valid),
		.m_axis_ready(m_dw_cvt_axis_ready)
	);
	
	/** 错误标志 **/
	reg video_in_ovf_r; // 写像素溢出标志
	
	assign video_in_ovf = video_in_ovf_r;
	
	// 写像素溢出标志
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			video_in_ovf_r <= 1'b0;
		else if(~video_in_ovf_r)
			video_in_ovf_r <= # SIM_DELAY s_fifo_axis_valid & (~s_fifo_axis_ready);
	end

endmodule
