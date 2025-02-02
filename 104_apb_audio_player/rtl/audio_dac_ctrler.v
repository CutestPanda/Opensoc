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
本模块: 音频DAC控制器

描述:
根据音频采样率取音频数据, 产生12位DAC输出

注意：
无

协议:
FIFO READ
FIFO WRITE

作者: 陈家耀
日期: 2024/08/05
********************************************************************/

module audio_dac_ctrler #(
	parameter real audio_clk_freq = 20 * 1000 * 1000, // 音频时钟频率(以Hz计)
	parameter init_audio_sample_rate = 3'd3, // 初始的音频采样率
	parameter integer audio_qtz_width = 8, // 音频量化位数(8 | 16)
	parameter real simulation_delay = 0 // 仿真延时
)(
	// AMBA总线时钟和复位
	input wire amba_clk,
	input wire amba_resetn,
	// 音频时钟和复位
	input wire audio_clk,
	input wire audio_resetn,
	
	// 运行时参数
	/*
	音频采样率:
		3'd0 8KHz
		3'd1 16KHz
		3'd2 22.05KHz
		3'd3 24KHz
		3'd4 32KHz
		3'd5 44.1KHz
		3'd6 47.25KHz
		3'd7 48KHz
	*/
	input wire[2:0] audio_sample_rate,
	
	// 音频数据fifo读端口
    output wire audio_fifo_ren,
    input wire audio_fifo_empty,
    input wire[audio_qtz_width-1:0] audio_fifo_dout,
	
	// 取flash读数据(指示)
	output wire on_flash_data_ren,
	
	// 12位DAC输出
	output wire[11:0] dac_out
);
	
	/** 音频采样发生器 **/
	wire to_sample;
	
	audio_sample_gen #(
		.audio_clk_freq(audio_clk_freq),
		.init_audio_sample_rate(init_audio_sample_rate),
		.simulation_delay(simulation_delay)
	)audio_sample_gen_u(
		.audio_clk(audio_clk),
		.audio_resetn(audio_resetn),
		
		.audio_sample_rate(audio_sample_rate),
		
		.to_sample(to_sample)
	);
	
	/**
	DAC数据产生
	
	等待音频采样(音频fifo读使能) -> 锁存音频fifo读数据 -> 产生12位DAC输出
	**/
	reg[2:0] dac_gen_onehot; // I2C命令产生独热码
	reg audio_fifo_empty_d; // 延迟1clk的音频数据fifo空标志
	reg audio_fifo_data_vld; // 音频数据fifo读数据有效
	reg[15:0] audio_fifo_dout_regs; // 音频数据fifo读数据({12位音频数据, 4'd0})
	
	assign audio_fifo_ren = dac_gen_onehot[0] & to_sample;
	
	assign on_flash_data_ren = (audio_qtz_width == 16) ? 
		((audio_fifo_ren & (~audio_fifo_empty)) | audio_fifo_data_vld):(audio_fifo_ren & (~audio_fifo_empty));
	
	// I2C命令产生独热码
	always @(posedge audio_clk or negedge audio_resetn)
	begin
		if(~audio_resetn)
			dac_gen_onehot <= 3'b001;
		else if((dac_gen_onehot[0] & to_sample) | (~dac_gen_onehot[0]))
			# simulation_delay dac_gen_onehot <= {dac_gen_onehot[1:0], dac_gen_onehot[2]};
	end
	
	// 延迟1clk的音频数据fifo空标志
	always @(posedge audio_clk or negedge audio_resetn)
	begin
		if(~audio_resetn)
			audio_fifo_empty_d <= 1'b0;
		else
			# simulation_delay audio_fifo_empty_d <= audio_fifo_empty;
	end
	
	// 音频数据fifo读数据有效
	always @(posedge audio_clk or negedge audio_resetn)
	begin
		if(~audio_resetn)
			audio_fifo_data_vld <= 1'b0;
		else
			# simulation_delay audio_fifo_data_vld <= audio_fifo_ren & (~audio_fifo_empty);
	end
	
	// 音频数据fifo读数据
	always @(posedge audio_clk)
	begin
		if(dac_gen_onehot[1])
			# simulation_delay audio_fifo_dout_regs <= audio_fifo_empty_d ? 
				16'd0:{((audio_qtz_width == 16) ? audio_fifo_dout[15:4]:{audio_fifo_dout, 4'd0}), 4'd0};
	end
	
	/** 12位DAC输出 **/
	reg[11:0] dac_oregs;
	
	assign dac_out = dac_oregs;
	
	// 12位DAC输出
	always @(posedge audio_clk or negedge audio_resetn)
	begin
		if(~audio_resetn)
			dac_oregs <= 12'd0;
		else if(dac_gen_onehot[2])
			# simulation_delay dac_oregs <= audio_fifo_dout_regs[15:4];
	end
	
endmodule
