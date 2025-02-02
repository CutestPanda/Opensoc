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
本模块: 全流水的单精度浮点乘法器

描述:
3级流水线完成生成符号位、阶码相加、尾数相乘、标准化与溢出判断

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/11/29
********************************************************************/


module float_mul_pipelined #(
	parameter en_round_in_frac_mul_res = "true", // 是否对尾数相乘结果进行四舍五入
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 浮点乘法器输入
	input wire[31:0] float_in_a,
	input wire[31:0] float_in_b,
	input wire float_in_valid,
	
	// 浮点乘法器输出
	output wire[31:0] float_out,
	output wire[1:0] float_ovf, // {上溢标志, 下溢标志}
	output wire float_out_valid
);
    
	/** 浮点数输入 **/
	wire in_float_sgn[0:1]; // 符号位
	wire[7:0] in_float_exp[0:1]; // 阶码
	wire[22:0] in_float_frac[0:1]; // 尾数
	
	assign {in_float_sgn[0], in_float_exp[0], in_float_frac[0]} = float_in_a;
	assign {in_float_sgn[1], in_float_exp[1], in_float_frac[1]} = float_in_b;
	
	/**
	第1级流水线
	
	生成符号位
	计算浮点数A有效指数: 有效指数 = 阶码 - 127
	尾数相乘(阶段1): 部分积#0 -> $signed({2'b01, 浮点数A尾数[22:0]}) * $signed({1'b0, 浮点数B尾数[16:0]})
	**/
	reg out_float_sgn; // 输出浮点数符号位
	reg[8:0] float_in_a_vld_exp; // 浮点数A有效指数(范围: -127~128)
	reg[7:0] float_in_b_d; // 延迟1clk的浮点数B阶码(范围: 0~255)
	wire[42:0] frac_mul_part_res_0; // 尾数相乘部分积#0
	reg float_in_valid_d; // 延迟1clk的浮点乘法器输入有效指示
	
	// 浮点数A有效指数
	always @(posedge clk)
	begin
		if(float_in_valid)
			// in_float_exp[0] - 9'd127
			float_in_a_vld_exp <= # simulation_delay {1'b0, in_float_exp[0]} + 9'b1_1000_0001;
	end
	
	// 浮点数B有效指数
	always @(posedge clk)
	begin
		if(float_in_valid)
			float_in_b_d <= # simulation_delay in_float_exp[1];
	end
	
	// 输出浮点数符号位
	always @(posedge clk)
	begin
		if(float_in_valid)
			out_float_sgn <= # simulation_delay in_float_sgn[0] ^ in_float_sgn[1];
	end
	
	// 延迟1clk的浮点乘法器输入有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			float_in_valid_d <= 1'b0;
		else
			float_in_valid_d <= # simulation_delay float_in_valid;
	end
	
	// 尾数乘法器#0
	mul #(
		.op_a_width(25),
		.op_b_width(18),
		.output_width(43),
		.simulation_delay(simulation_delay)
	)frac_mul_u0(
		.clk(clk),
		
		.ce_s0_mul(float_in_valid),
		
		// 有符号乘法
		.op_a({2'b01, in_float_frac[0]}), // {2'b01, 浮点数A尾数[22:0]}
		.op_b({1'b0, in_float_frac[1][16:0]}), // {1'b0, 浮点数B尾数[16:0]}
		
		.res(frac_mul_part_res_0) // 尾数相乘部分积#0
	);
	
	/**
	第2级流水线
	
	阶码相加: {浮点数A有效指数[8], 浮点数A有效指数[8:0]} + {2'b00, 延迟1clk的浮点数B阶码[7:0]}
	尾数相乘(阶段2): (部分积#0 >> 17) + 部分积#1
	**/
	reg out_float_sgn_d; // 延迟1clk的输出浮点数符号位
	reg[9:0] exp_sum; // 阶码相加结果(范围: -127~383)
	wire[30:0] frac_mul_add_res; // 尾数乘加器计算结果
	wire[24:0] frac_mul_res; // 尾数相乘结果(Q23)
	wire frac_mul_res_round_bit; // 尾数相乘结果的舍入位
	reg float_in_valid_d2; // 延迟2clk的浮点乘法器输入有效指示
	
	assign frac_mul_res = frac_mul_add_res[30:6];
	assign frac_mul_res_round_bit = frac_mul_add_res[5];
	
	// 延迟1clk的输出浮点数符号位
	always @(posedge clk)
	begin
		if(float_in_valid_d)
			out_float_sgn_d <= # simulation_delay out_float_sgn;
	end
	
	// 阶码相加结果
	always @(posedge clk)
	begin
		if(float_in_valid_d)
			exp_sum <= # simulation_delay {float_in_a_vld_exp[8], float_in_a_vld_exp} + {2'b00, float_in_b_d};
	end
	
	// 延迟2clk的浮点乘法器输入有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			float_in_valid_d2 <= 1'b0;
		else
			float_in_valid_d2 <= # simulation_delay float_in_valid_d;
	end
	
	/*
	尾数乘加器
	
	部分积#1 -> $signed({2'b01, 浮点数A尾数[22:0]}) * $signed({2'b01, 浮点数B尾数[22:17]})
	尾数相乘结果 = 部分积#0[40:17] + 部分积#1[32:0], 取低31位
	*/
	mul_add_dsp #(
		.en_op_a_in_regs("false"),
		.en_op_b_in_regs("false"),
		.en_op_d_in_regs("false"),
		.en_pre_adder("false"),
		.en_op_b_in_s1_regs("false"),
		.en_op_c_in_s1_regs("false"),
		.en_op_c_in_s2_regs("false"),
		.op_a_width(25),
		.op_b_width(8),
		.op_c_width(33),
		.op_d_width(25),
		.output_width(31),
		.pattern_detect_msb_id(0),
		.pattern_detect_lsb_id(0),
		.pattern_detect_cmp(1'b1),
		.simulation_delay(simulation_delay)
	)frac_mul_add(
		.clk(clk),
		
		.ce_s0_op_a(1'b1),
		.ce_s0_op_b(1'b1),
		.ce_s0_op_d(1'b1),
		.ce_s1_pre_adder(1'b1),
		.ce_s1_op_b(1'b1),
		.ce_s1_op_c(1'b1),
		.ce_s2_mul(float_in_valid),
		.ce_s2_op_c(1'b1),
		.ce_s3_p(float_in_valid_d),
		
		// 有符号乘法
		.op_a({2'b01, in_float_frac[0]}), // {2'b01, 浮点数A尾数[22:0]}
		.op_b({2'b01, in_float_frac[1][22:17]}), // {2'b01, 浮点数B尾数[22:17]}
		// 部分积相加
		.op_c({9'd0, frac_mul_part_res_0[40:17]}), // 部分积#0 >> 17
		.op_d(25'd0),
		
		.res(frac_mul_add_res),
		.pattern_detect_res()
	);
	
	/**
	第3级流水线
	
	[对尾数进行四舍五入]
	标准化与溢出判断
	**/
	wire[24:0] frac_mul_res_rounded; // 四舍五入后的尾数相乘结果(Q23)
	reg out_float_sgn_d2; // 延迟2clk的输出浮点数符号位
	wire[9:0] exp_normalized; // 标准化后的阶码(范围: -127~384)
	wire[22:0] frac_normalized; // 标准化后的尾数
	wire up_ovf_flag; // 上溢标志
	wire down_ovf_flag; // 下溢标志
	reg[7:0] out_float_exp; // 输出浮点数的阶码
	reg[22:0] out_float_frac; // 输出浮点数的尾数
	reg[1:0] out_float_ovf; // 输出浮点数的溢出标志({上溢标志, 下溢标志})
	reg float_in_valid_d3; // 延迟3clk的浮点乘法器输入有效指示
	
	assign float_out = {out_float_sgn_d2, out_float_exp, out_float_frac};
	assign float_ovf = out_float_ovf;
	assign float_out_valid = float_in_valid_d3;
	
	assign frac_mul_res_rounded = (en_round_in_frac_mul_res == "true") ? (frac_mul_res + frac_mul_res_round_bit):frac_mul_res;
	assign exp_normalized = exp_sum + frac_mul_res_rounded[24];
	// frac_mul_res_rounded >> frac_mul_res_rounded[24]
	assign frac_normalized = frac_mul_res_rounded[24] ? frac_mul_res_rounded[23:1]:frac_mul_res_rounded[22:0];
	assign up_ovf_flag = exp_normalized[9:8] == 2'b01;
	assign down_ovf_flag = exp_normalized[9];
	
	// 延迟2clk的输出浮点数符号位
	always @(posedge clk)
	begin
		if(float_in_valid_d2)
			out_float_sgn_d2 <= # simulation_delay out_float_sgn_d;
	end
	
	// 输出浮点数的阶码
	always @(posedge clk)
	begin
		if(float_in_valid_d2)
			out_float_exp <= # simulation_delay {8{~down_ovf_flag}} & ({8{up_ovf_flag}} | exp_normalized[7:0]);
	end
	
	// 输出浮点数的尾数
	always @(posedge clk)
	begin
		if(float_in_valid_d2)
			out_float_frac <= # simulation_delay {23{~down_ovf_flag}} & ({23{up_ovf_flag}} | frac_normalized);
	end
	
	// 输出浮点数的溢出标志
	always @(posedge clk)
	begin
		if(float_in_valid_d2)
			out_float_ovf <= # simulation_delay {up_ovf_flag, down_ovf_flag};
	end
	
	// 延迟3clk的浮点乘法器输入有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			float_in_valid_d3 <= 1'b0;
		else
			float_in_valid_d3 <= # simulation_delay float_in_valid_d2;
	end
    
endmodule
