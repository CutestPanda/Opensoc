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
本模块: Relu激活计算单元

描述:
2级流水线

Relu激活 -> 
	          | cy, 当y < 0时
	z(c, y) = |
	          | y, 当y >= 0时

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/12/29
********************************************************************/


module relu_act #(
	parameter integer act_cal_width = 16, // 激活计算位宽(8 | 16)
	parameter integer act_in_quaz_acc = 10, // 激活输入量化精度(必须在范围[1, act_cal_width-1]内)
	parameter integer act_in_ext_int_width = 4, // 激活输入额外考虑的整数位数(必须<=(act_cal_width-act_in_quaz_acc))
	parameter integer act_in_ext_frac_width = 4, // 激活输入额外考虑的小数位数(必须<=act_in_quaz_acc)
	parameter integer relu_const_quaz_acc = 14, // Relu激活常系数量化精度(必须在范围[1, act_cal_width-1]内)
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 运行时参数
	input wire[act_cal_width-1:0] relu_const_rate, // Relu激活常系数
	
	// 激活输入
	// 仅低(act_in_ext_int_width+act_cal_width+act_in_ext_frac_width)位有效
	input wire[act_cal_width*2-1:0] act_in,
	input wire act_in_vld,
	
	// 激活输出
	// 仅低(act_in_ext_int_width+act_cal_width+act_in_ext_frac_width)位有效
	output wire[act_cal_width*2-1:0] act_out,
	output wire act_out_vld
);
	
	/**
	第1级
	
	生成乘法器的操作数
	**/
	reg[act_in_ext_int_width+act_cal_width+act_in_ext_frac_width-1:0] mul_op_a; // 量化精度 = act_in_quaz_acc+act_in_ext_frac_width
	reg[act_cal_width-1:0] mul_op_b; // 量化精度 = relu_const_quaz_acc
	reg act_in_vld_d; // 延迟1clk的激活输入有效指示
	
	// 乘法器操作数A
	always @(posedge clk)
	begin
		if(act_in_vld)
			mul_op_a <= # simulation_delay act_in[act_in_ext_int_width+act_cal_width+act_in_ext_frac_width-1:0];
	end
	// 乘法器操作数B
	always @(posedge clk)
	begin
		if(act_in_vld)
			mul_op_b <= # simulation_delay 
				act_in[act_in_ext_int_width+act_cal_width+act_in_ext_frac_width-1] ? 
					// 激活输入为负
					relu_const_rate:
					// 激活输入为正
					((relu_const_quaz_acc == (act_cal_width-1)) ? 
						{1'b0, {(act_cal_width-1){1'b1}}}:
						({{(act_cal_width-1){1'b0}}, 1'b1} << relu_const_quaz_acc));
	end
	
	// 延迟1clk的激活输入有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			act_in_vld_d <= 1'b0;
		else
			act_in_vld_d <= # simulation_delay act_in_vld;
	end
	
	/**
	第2级
	
	进行乘法计算
	**/
	wire[act_in_ext_int_width+act_cal_width*2+act_in_ext_frac_width-1:0] relu_mul_res; // 量化精度 = act_in_quaz_acc+
	                                                                                   //     act_in_ext_frac_width+relu_const_quaz_acc
	reg act_in_vld_d2; // 延迟2clk的激活输入有效指示
	
	generate
		if((act_in_ext_int_width+act_cal_width+act_in_ext_frac_width) < act_cal_width*2)
		begin
			assign act_out = {
				{(act_cal_width*2-(act_in_ext_int_width+act_cal_width+act_in_ext_frac_width))
					{relu_mul_res[relu_const_quaz_acc+act_in_ext_int_width+act_cal_width+act_in_ext_frac_width-1]}}, 
				relu_mul_res[relu_const_quaz_acc+act_in_ext_int_width+act_cal_width+act_in_ext_frac_width-1:relu_const_quaz_acc]
			};
		end
		else
		begin
			assign act_out = 
				relu_mul_res[relu_const_quaz_acc+act_in_ext_int_width+act_cal_width+act_in_ext_frac_width-1:relu_const_quaz_acc];
		end
	endgenerate
	
	assign act_out_vld = act_in_vld_d2;
	
	// 延迟2clk的激活输入有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			act_in_vld_d2 <= 1'b0;
		else
			act_in_vld_d2 <= # simulation_delay act_in_vld_d;
	end
	
	// 乘法器
	mul #(
		.op_a_width(act_in_ext_int_width+act_cal_width+act_in_ext_frac_width),
		.op_b_width(act_cal_width),
		.output_width(act_in_ext_int_width+act_cal_width*2+act_in_ext_frac_width),
		.simulation_delay(simulation_delay)
	)relu_mul(
		.clk(clk),
		
		.ce_s0_mul(act_in_vld_d),
		
		.op_a(mul_op_a),
		.op_b(mul_op_b),
		
		.res(relu_mul_res)
	);
	
endmodule
