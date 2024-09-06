`timescale 1ns / 1ps
/********************************************************************
本模块: 音频采样发生器

描述:
根据音频采样率产生音频采样指示信号

支持的采样率 ->
	8KHz
	11.025KHz
	22.05KHz
	24KHz
	32KHz
	44.1KHz
	47.25KHz
	48KHz

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/08/05
********************************************************************/

module audio_sample_gen #(
	parameter real audio_clk_freq = 20 * 1000 * 1000, // 音频时钟频率(以Hz计)
	parameter init_audio_sample_rate = 3'd3, // 初始的音频采样率
	parameter real simulation_delay = 0 // 仿真延时
)(
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
	
	// 音频采样(指示)
	output wire to_sample
);
	
	// 计算log2(bit_depth)               
    function integer clogb2 (input integer bit_depth);
        integer temp;
    begin
        temp = bit_depth;
        for(clogb2 = -1;temp > 0;clogb2 = clogb2 + 1)                   
            temp = temp >> 1;                                 
    end                                        
    endfunction
	
	/** 常量 **/
	// 各种音频采样率下的分频系数
	localparam integer rate1_div_rate = audio_clk_freq / 8000 - 1;
	localparam integer rate2_div_rate = audio_clk_freq / 16000 - 1;
	localparam integer rate3_div_rate = audio_clk_freq / 22050 - 1;
	localparam integer rate4_div_rate = audio_clk_freq / 24000 - 1;
	localparam integer rate5_div_rate = audio_clk_freq / 32000 - 1;
	localparam integer rate6_div_rate = audio_clk_freq / 44100 - 1;
	localparam integer rate7_div_rate = audio_clk_freq / 47250 - 1;
	localparam integer rate8_div_rate = audio_clk_freq / 48000 - 1;
	
	/** 分频计数器 **/
	reg[clogb2(rate1_div_rate+1):0] div_cnt; // 分频计数器
	reg[2:0] audio_sample_rate_shadow; // 音频采样率(影子寄存器)
	reg to_sample_reg; // 音频采样(指示)
	
	assign to_sample = to_sample_reg;
	
	// 分频计数器
	always @(posedge audio_clk or negedge audio_resetn)
	begin
		if(~audio_resetn)
			div_cnt <= 0;
		else
			div_cnt <= # simulation_delay to_sample_reg ? 0:(div_cnt + 1);
	end
	
	// 音频采样率(影子寄存器)
	always @(posedge audio_clk or negedge audio_resetn)
	begin
		if(~audio_resetn)
			audio_sample_rate_shadow <= init_audio_sample_rate;
		else if(to_sample_reg)
			# simulation_delay audio_sample_rate_shadow <= audio_sample_rate;
	end
	
	// 音频采样(指示)
	always @(posedge audio_clk or negedge audio_resetn)
	begin
		if(~audio_resetn)
			to_sample_reg <= 1'b0;
		else
		begin
			# simulation_delay;
			
			case(audio_sample_rate_shadow)
				3'd0: to_sample_reg <= div_cnt == (rate1_div_rate - 1);
				3'd1: to_sample_reg <= div_cnt == (rate2_div_rate - 1);
				3'd2: to_sample_reg <= div_cnt == (rate3_div_rate - 1);
				3'd3: to_sample_reg <= div_cnt == (rate4_div_rate - 1);
				3'd4: to_sample_reg <= div_cnt == (rate5_div_rate - 1);
				3'd5: to_sample_reg <= div_cnt == (rate6_div_rate - 1);
				3'd6: to_sample_reg <= div_cnt == (rate7_div_rate - 1);
				default: to_sample_reg <= div_cnt == (rate8_div_rate - 1);
			endcase
		end
	end
	
endmodule
