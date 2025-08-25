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
本模块: 编码器脉冲计数

描述: 
匹配编码器A/B相输入的四阶段变化模式, 驱动定时计数器向上/向下计数

计数递增 -> 
	A相 R 1 F 0
	B相 0 R 1 F

计数递减 -> 
	A相 0 R 1 F
	B相 R 1 F 0

注意：
使用编码器模式时, 捕获/比较通道数(channel_n)必须>=2

协议:
无

作者: 陈家耀
日期: 2025/08/10
********************************************************************/


module timer_encoder_cnt #(
    parameter real simulation_delay = 1 // 仿真延时
)(
    // [时钟]
    input wire clk,
	
	// [编码器输入]
	input wire encoder_i_a, // A相输入
	input wire encoder_i_b, // B相输入
	
	// [定时器状态]
    input wire timer_started, // 是否启动定时器
	input wire in_encoder_mode, // 是否处于编码器模式
	
	// [外部脉冲计数]
	output wire timer_ce, // 计数使能
	output wire timer_down // 计数方向(1'b1 -> 向下计数, 1'b0 -> 向上计数)
);
    
	/** 编码器输入 **/
    reg[4:1] encoder_i_a_dly; // 延迟1~4clk的A相输入
	reg[4:1] encoder_i_b_dly; // 延迟1~4clk的B相输入
	wire on_encoder_i_a_posedge; // 检测到A相输入上升沿
	wire on_encoder_i_a_negedge; // 检测到A相输入下降沿
	wire on_encoder_i_b_posedge; // 检测到B相输入上升沿
	wire on_encoder_i_b_negedge; // 检测到B相输入下降沿
	
	assign on_encoder_i_a_posedge = encoder_i_a_dly[3] & (~encoder_i_a_dly[4]);
	assign on_encoder_i_a_negedge = (~encoder_i_a_dly[3]) & encoder_i_a_dly[4];
	assign on_encoder_i_b_posedge = encoder_i_b_dly[3] & (~encoder_i_b_dly[4]);
	assign on_encoder_i_b_negedge = (~encoder_i_b_dly[3]) & encoder_i_b_dly[4];
	
	// 延迟1~4clk的A相输入, 延迟1~4clk的B相输入
	always @(posedge clk)
	begin
		encoder_i_a_dly <= # simulation_delay {encoder_i_a_dly[3:1], encoder_i_a};
		encoder_i_b_dly <= # simulation_delay {encoder_i_b_dly[3:1], encoder_i_b};
	end
	
	/** 编码器脉冲检测 **/
    reg[3:0] pos_pulse_dt_sts; // 正脉冲检测状态
	reg[3:0] neg_pulse_dt_sts; // 负脉冲检测状态
	reg timer_cnt_incr; // 定时计数器递增
	reg timer_cnt_dcrs; // 定时计数器递减
	
	assign timer_ce = 
		(~in_encoder_mode) | 
		(
			timer_started & 
			(timer_cnt_incr | timer_cnt_dcrs)
		);
	assign timer_down = 
		(~in_encoder_mode) | 
		timer_cnt_dcrs;
	
	// 正脉冲检测状态
	always @(posedge clk)
	begin
		if(~(timer_started & in_encoder_mode))
			pos_pulse_dt_sts <= # simulation_delay 4'b0001;
		else if(
			on_encoder_i_a_posedge | on_encoder_i_a_negedge | on_encoder_i_b_posedge | on_encoder_i_b_negedge
		)
		begin
			case(pos_pulse_dt_sts)
				4'b0001:
					pos_pulse_dt_sts <= # simulation_delay 
						(on_encoder_i_a_posedge & (~encoder_i_b_dly[3]) & (~encoder_i_b_dly[4])) ? 
							4'b0010:
							4'b0001;
				4'b0010:
					pos_pulse_dt_sts <= # simulation_delay 
						(encoder_i_a_dly[3] & encoder_i_a_dly[4] & on_encoder_i_b_posedge) ? 
							4'b0100:
							4'b0001;
				4'b0100:
					pos_pulse_dt_sts <= # simulation_delay 
						(on_encoder_i_a_negedge & encoder_i_b_dly[3] & encoder_i_b_dly[4]) ? 
							4'b1000:
							4'b0001;
				4'b1000:
					pos_pulse_dt_sts <= # simulation_delay 4'b0001;
				default:
					pos_pulse_dt_sts <= # simulation_delay 4'b0001;
			endcase
		end
	end
	
	// 负脉冲检测状态
	always @(posedge clk)
	begin
		if(~(timer_started & in_encoder_mode))
			neg_pulse_dt_sts <= # simulation_delay 4'b0001;
		else if(
			(on_encoder_i_a_posedge | on_encoder_i_a_negedge | on_encoder_i_b_posedge | on_encoder_i_b_negedge)
		)
		begin
			case(neg_pulse_dt_sts)
				4'b0001:
					neg_pulse_dt_sts <= # simulation_delay 
						((~encoder_i_a_dly[3]) & (~encoder_i_a_dly[4]) & on_encoder_i_b_posedge) ? 
							4'b0010:
							4'b0001;
				4'b0010:
					neg_pulse_dt_sts <= # simulation_delay 
						(on_encoder_i_a_posedge & encoder_i_b_dly[3] & encoder_i_b_dly[4]) ? 
							4'b0100:
							4'b0001;
				4'b0100:
					neg_pulse_dt_sts <= # simulation_delay 
						(encoder_i_a_dly[3] & encoder_i_a_dly[4] & on_encoder_i_b_negedge) ? 
							4'b1000:
							4'b0001;
				4'b1000:
					neg_pulse_dt_sts <= # simulation_delay 4'b0001;
				default:
					neg_pulse_dt_sts <= # simulation_delay 4'b0001;
			endcase
		end
	end
	
	// 定时计数器递增
	always @(posedge clk)
	begin
		if(~(timer_started & in_encoder_mode))
			timer_cnt_incr <= # simulation_delay 1'b0;
		else
			timer_cnt_incr <= # simulation_delay 
				(pos_pulse_dt_sts[0] & (on_encoder_i_a_posedge & (~encoder_i_b_dly[3]) & (~encoder_i_b_dly[4]))) | 
				(pos_pulse_dt_sts[1] & (encoder_i_a_dly[3] & encoder_i_a_dly[4] & on_encoder_i_b_posedge)) | 
				(pos_pulse_dt_sts[2] & (on_encoder_i_a_negedge & encoder_i_b_dly[3] & encoder_i_b_dly[4])) | 
				(pos_pulse_dt_sts[3] & ((~encoder_i_a_dly[3]) & (~encoder_i_a_dly[4]) & on_encoder_i_b_negedge));
	end
	// 定时计数器递减
	always @(posedge clk)
	begin
		if(~(timer_started & in_encoder_mode))
			timer_cnt_dcrs <= # simulation_delay 1'b0;
		else
			timer_cnt_dcrs <= # simulation_delay 
				(neg_pulse_dt_sts[0] & ((~encoder_i_a_dly[3]) & (~encoder_i_a_dly[4]) & on_encoder_i_b_posedge)) | 
				(neg_pulse_dt_sts[1] & (on_encoder_i_a_posedge & encoder_i_b_dly[3] & encoder_i_b_dly[4])) | 
				(neg_pulse_dt_sts[2] & (encoder_i_a_dly[3] & encoder_i_a_dly[4] & on_encoder_i_b_negedge)) | 
				(neg_pulse_dt_sts[3] & (on_encoder_i_a_negedge & (~encoder_i_b_dly[3]) & (~encoder_i_b_dly[4])));
	end
	
endmodule
