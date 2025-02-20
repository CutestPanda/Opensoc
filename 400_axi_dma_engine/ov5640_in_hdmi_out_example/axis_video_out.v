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
本模块: AXIS视频输出

描述: 
将AXIS的像素流转换为VIO视频输出
支持动态VIO时序生成

注意：
无

协议:
AXIS SLAVE
VIO

作者: 陈家耀
日期: 2023/10/23
********************************************************************/


module axis_video_out #(
    parameter en_dyn_vio_timing = "false", // 是否使能动态VIO时序生成
	parameter integer pix_data_width = 24, // 像素位宽
    parameter integer h_active = 1280, // 水平有效长度
    // 以下仅在不启用动态VIO时序生成时有效
    parameter integer h_fp = 110, // 水平前肩长度
    parameter integer h_sync = 40, // 水平同步长度
    parameter integer h_bp = 220, // 水平后肩
    parameter integer v_active = 720, // 垂直有效长度
    parameter integer v_fp = 5, // 垂直前肩长度
    parameter integer v_sync = 5, // 垂直同步长度
    parameter integer v_bp = 20, // 垂直后肩
    parameter hs_posedge = "true", // 上升沿触发的水平同步信号
    parameter vs_posedge = "true", // 上升沿触发的垂直同步信号
    // 以上仅在不启用动态VIO时序生成时有效
    parameter integer buffer_fifo_depth = 1024, // 缓冲fifo的深度
    parameter real simulation_delay = 1 // 仿真延时
)(
    // AXIS从机时钟和复位
    input wire s_axis_aclk,
    input wire s_axis_aresetn,
	// 像素时钟和复位
    input wire pix_aclk,
    input wire pix_aresetn,
    
    // vio(video timing in)
    // 以下仅当使能动态VIO时序生成时有效
    input wire hs_in, // 行同步
	input wire vs_in, // 场同步
	input wire de_in, // 数据有效
	input wire next_pix_in, // 获取下一个像素(标志)
	input wire pix_line_end_in, // 获取当前行最后一个像素(标志)
	input wire pix_last_in, // 获取当前帧最后一个像素(标志)
	// 以上仅当使能动态VIO时序生成时有效
    
    // 写像素数据(AXIS从机)
    input wire[pix_data_width-1:0] s_axis_data,
    input wire s_axis_last, // 指示当前像素是行尾
    input wire s_axis_valid,
    output wire s_axis_ready,
    
    // 缓冲状态
    output wire write_too_fast, // 写像素过快
    output wire write_too_slow, // 写像素过慢
    
    // vio(video out)
	output wire hs_out, // 行同步
	output wire vs_out, // 场同步
	output wire de_out, // 数据有效
	output wire[pix_data_width-1:0] pix_out // 像素输出
);
	
    /** 缓冲fifo */
    wire next_pix; // 获取下一个像素(标志)
    wire pix_line_end; // 获取当前行最后一个像素(标志)
	wire pix_last; // 获取当前帧最后一个像素(标志)
    wire[pix_data_width-1:0] pix_out_w; // 像素输出
	reg start_display; // 开始显示(标志)
	wire video_o_fifo_empty_n;
	
	assign write_too_fast = ~s_axis_ready;
	assign write_too_slow = next_pix & start_display & (~video_o_fifo_empty_n);
	
	// 开始显示(标志)
	always @(posedge pix_aclk or negedge pix_aresetn)
	begin
		if(~pix_aresetn)
			start_display <= 1'b0;
		else if(~start_display)
			start_display <= # simulation_delay video_o_fifo_empty_n & next_pix & pix_last;
	end
	
	async_fifo_with_ram #(
		.fwft_mode("false"),
		.ram_type("bram"),
		.depth(buffer_fifo_depth),
		.data_width(pix_data_width),
		.simulation_delay(simulation_delay)
	)video_o_fifo_u(
		.clk_wt(s_axis_aclk),
		.rst_n_wt(s_axis_aresetn),
		.clk_rd(pix_aclk),
		.rst_n_rd(pix_aresetn),
		.fifo_wen(s_axis_valid),
		.fifo_din(s_axis_data),
		.fifo_full_n(s_axis_ready),
		.fifo_ren(next_pix & start_display),
		.fifo_dout(pix_out_w),
		.fifo_empty_n(video_o_fifo_empty_n)
	);
    
    /** 视频信号输出 **/
    generate
        if(en_dyn_vio_timing == "false")
            video_output #(
                .h_active(h_active),
                .h_fp(h_fp),
                .h_sync(h_sync),
                .h_bp(h_bp),
                .v_active(v_active),
                .v_fp(v_fp),
                .v_sync(v_sync),
                .v_bp(v_bp),
                .hs_posedge(hs_posedge),
                .vs_posedge(vs_posedge),
                .pix_data_width(pix_data_width),
                .en_ext_pix_read_la("false"),
                .simulation_delay(simulation_delay)
            )video_output_u(
                .clk(pix_aclk),
                .rst_n(pix_aresetn),
                .next_pix(next_pix),
                .pix_line_end(pix_line_end),
				.pix_last(pix_last),
                .in_pix(pix_out_w),
                .hs(hs_out),
                .vs(vs_out),
                .de(de_out),
                .pix(pix_out)
            );
        else
        begin
            assign pix_out = pix_out_w;
            assign hs_out = hs_in;
            assign vs_out = vs_in;
            assign de_out = de_in;
            
            assign next_pix = next_pix_in;
            assign pix_line_end = pix_line_end_in;
			assign pix_last = pix_last_in;
        end
    endgenerate

endmodule
