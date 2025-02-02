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
本模块: 非线性激活计算单元

描述:
基于查表法实现Sigmoid和Tanh激活

使用1片2k深度 * 16位宽的Sigmoid/Tanh查找表

3级流水线

采用非均匀量化 -> 
(1)Sigmoid
  自变量范围 | 量化点数
--------------------------
    [0, 2)   |   1024
    [2, 4)   |   512
    [4, 8)   |   512
(2)Tanh
  自变量范围 | 量化点数
--------------------------
    [0, 1)   |   1024
    [1, 2)   |   512
    [2, 4)   |   512

注意：
Sigmoid/Tanh查找表的读延迟应为1clk

协议:
MEM READ

作者: 陈家耀
日期: 2024/12/27
********************************************************************/


module non_linear_act #(
	parameter integer act_cal_width = 16, // 激活计算位宽(8 | 16)
	parameter integer act_in_quaz_acc = 10, // 激活输入量化精度(必须在范围[1, act_cal_width-1]内)
	parameter integer act_in_ext_int_width = 4, // 激活输入额外考虑的整数位数(必须<=(act_cal_width-act_in_quaz_acc))
	parameter integer act_in_ext_frac_width = 4, // 激活输入额外考虑的小数位数(必须<=act_in_quaz_acc)
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 运行时参数
	input wire non_ln_act_type, // 非线性激活类型(1'b0 -> Sigmoid, 1'b1 -> Tanh)
	
	// 非线性激活查找表(读端口)
	output wire non_ln_act_lut_ren,
	output wire[10:0] non_ln_act_lut_raddr,
	input wire[15:0] non_ln_act_lut_dout, // Q15
	
	// 激活输入
	// 仅低(act_in_ext_int_width+act_cal_width+act_in_ext_frac_width)位有效
	input wire[act_cal_width*2-1:0] act_in,
	input wire act_in_vld,
	
	// 激活输出
	// 仅低(act_in_ext_int_width+act_cal_width+act_in_ext_frac_width)位有效
	output wire[act_cal_width*2-1:0] act_out,
	output wire act_out_vld
);
	
	/** 常量 **/
	// 非线性激活类型
	localparam NON_LN_ACT_SIGMOID = 1'b0;
	localparam NON_LN_ACT_TANH = 1'b1;
	
	/** 激活输入 **/
	wire signed[act_in_ext_int_width+act_cal_width+act_in_ext_frac_width-1:0] act_in_unpacked;
	
	assign act_in_unpacked = act_in[act_in_ext_int_width+act_cal_width+act_in_ext_frac_width-1:0];
	
	/**
	第1级
	
	确定量化级别
	计算激活输入的绝对值
	**/
	wire abs_act_in_geq_1; // 激活输入的绝对值大于等于1(标志)
	wire abs_act_in_geq_2; // 激活输入的绝对值大于等于2(标志)
	wire abs_act_in_geq_4; // 激活输入的绝对值大于等于4(标志)
	wire abs_act_in_geq_8; // 激活输入的绝对值大于等于8(标志)
	reg[1:0] quaz_lv; // 量化级别
	reg[act_in_ext_int_width+act_cal_width+act_in_ext_frac_width-1:0] abs_act_in; // 激活输入的绝对值
	reg is_act_in_neg; // 激活输入为负(标志)
	reg act_in_vld_d; // 延迟1clk的激活输入有效指示
	
	assign abs_act_in_geq_1 = 
		(act_in_unpacked >= $signed(1 * (2 ** (act_in_quaz_acc + act_in_ext_frac_width)))) | 
		(act_in_unpacked <= $signed(-1 * (2 ** (act_in_quaz_acc + act_in_ext_frac_width))));
	assign abs_act_in_geq_2 = 
		(act_in_unpacked >= $signed(2 * (2 ** (act_in_quaz_acc + act_in_ext_frac_width)))) | 
		(act_in_unpacked <= $signed(-2 * (2 ** (act_in_quaz_acc + act_in_ext_frac_width))));
	assign abs_act_in_geq_4 = 
		(act_in_unpacked >= $signed(4 * (2 ** (act_in_quaz_acc + act_in_ext_frac_width)))) | 
		(act_in_unpacked <= $signed(-4 * (2 ** (act_in_quaz_acc + act_in_ext_frac_width))));
	assign abs_act_in_geq_8 = 
		(act_in_unpacked >= $signed(8 * (2 ** (act_in_quaz_acc + act_in_ext_frac_width)))) | 
		(act_in_unpacked <= $signed(-8 * (2 ** (act_in_quaz_acc + act_in_ext_frac_width))));
	
	// 量化级别
	always @(posedge clk)
	begin
		if(act_in_vld)
			quaz_lv <= # simulation_delay 
				(non_ln_act_type == NON_LN_ACT_SIGMOID) ? 
					(({2{abs_act_in_geq_8}} & 2'b11) | // [8, 正无穷)
					({2{(~abs_act_in_geq_8) & abs_act_in_geq_4}} & 2'b10) | // [4, 8)
					({2{(~abs_act_in_geq_4) & abs_act_in_geq_2}} & 2'b01) | // [2, 4)
					({2{~abs_act_in_geq_2}} & 2'b00)): // [0, 2)
					(({2{abs_act_in_geq_4}} & 2'b11) | // [4, 正无穷)
					({2{(~abs_act_in_geq_4) & abs_act_in_geq_2}} & 2'b10) | // [2, 4)
					({2{(~abs_act_in_geq_2) & abs_act_in_geq_1}} & 2'b01) | // [1, 2)
					({2{~abs_act_in_geq_1}} & 2'b00)); // [0, 1)
	end
	
	// 激活输入的绝对值
	always @(posedge clk)
	begin
		if(act_in_vld)
			abs_act_in <= # simulation_delay 
				// act_in_unpacked[act_in_ext_int_width+act_cal_width+act_in_ext_frac_width-1] ? 
				//     ((~act_in_unpacked) + 1'b1):act_in_unpacked
				({(act_in_ext_int_width+act_cal_width+act_in_ext_frac_width)
					{act_in_unpacked[act_in_ext_int_width+act_cal_width+act_in_ext_frac_width-1]}} ^ act_in_unpacked) + 
					act_in_unpacked[act_in_ext_int_width+act_cal_width+act_in_ext_frac_width-1];
	end
	
	// 激活输入为负(标志)
	always @(posedge clk)
	begin
		if(act_in_vld)
			is_act_in_neg <= # simulation_delay act_in_unpacked[act_in_ext_int_width+act_cal_width+act_in_ext_frac_width-1];
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
	
	读Sigmoid/Tanh查找表
	**/
	wire[act_in_ext_int_width+act_cal_width+act_in_ext_frac_width+13:0] abs_act_in_ext; // 整数/小数拓展的激活输入绝对值
	reg act_res_up_ovf; // 激活计算结果的绝对值达到上限(标志)
	reg is_act_in_neg_d; // 延迟1clk的激活输入为负(标志)
	reg act_in_vld_d2; // 延迟2clk的激活输入有效指示
	
	assign non_ln_act_lut_ren = act_in_vld_d & (quaz_lv != 2'b11);
	assign non_ln_act_lut_raddr = 
		// [0, 2), 1024点
		({11{(non_ln_act_type == NON_LN_ACT_SIGMOID) & (quaz_lv == 2'b00)}} & 
			{1'b0, abs_act_in_ext[act_in_quaz_acc+act_in_ext_frac_width+10:act_in_quaz_acc+act_in_ext_frac_width+1]}) | 
		// [2, 4), 512点
		({11{(non_ln_act_type == NON_LN_ACT_SIGMOID) & (quaz_lv == 2'b01)}} & 
			{2'b10, abs_act_in_ext[act_in_quaz_acc+act_in_ext_frac_width+10:act_in_quaz_acc+act_in_ext_frac_width+2]}) | 
		// [4, 8), 512点
		({11{(non_ln_act_type == NON_LN_ACT_SIGMOID) & (quaz_lv == 2'b10)}} & 
			{2'b11, abs_act_in_ext[act_in_quaz_acc+act_in_ext_frac_width+11:act_in_quaz_acc+act_in_ext_frac_width+3]}) | 
		// [0, 1), 1024点
		({11{(non_ln_act_type == NON_LN_ACT_TANH) & (quaz_lv == 2'b00)}} & 
			{1'b0, abs_act_in_ext[act_in_quaz_acc+act_in_ext_frac_width+9:act_in_quaz_acc+act_in_ext_frac_width]}) | 
		// [1, 2), 512点
		({11{(non_ln_act_type == NON_LN_ACT_TANH) & (quaz_lv == 2'b01)}} & 
			{2'b10, abs_act_in_ext[act_in_quaz_acc+act_in_ext_frac_width+9:act_in_quaz_acc+act_in_ext_frac_width+1]}) | 
		// [2, 4), 512点
		({11{(non_ln_act_type == NON_LN_ACT_TANH) & (quaz_lv == 2'b10)}} & 
			{2'b11, abs_act_in_ext[act_in_quaz_acc+act_in_ext_frac_width+10:act_in_quaz_acc+act_in_ext_frac_width+2]});
	// 小数: (act_in_quaz_acc + act_in_ext_frac_width + 10)位, 整数: (act_in_ext_int_width + act_cal_width - act_in_quaz_acc + 4)位
	assign abs_act_in_ext = {4'b0000, abs_act_in, 10'b00_0000_0000};
	
	// 激活计算结果的绝对值达到上限(标志)
	always @(posedge clk)
	begin
		if(act_in_vld_d)
			act_res_up_ovf <= # simulation_delay quaz_lv == 2'b11;
	end
	
	// 延迟1clk的激活输入为负(标志)
	always @(posedge clk)
	begin
		if(act_in_vld_d)
			is_act_in_neg_d <= # simulation_delay is_act_in_neg;
	end
	
	// 延迟2clk的激活输入有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			act_in_vld_d2 <= 1'b0;
		else
			act_in_vld_d2 <= # simulation_delay act_in_vld_d;
	end
	
	/**
	第3级
	
	生成激活输出
	**/
	wire signed[16:0] non_ln_act_lut_dout_with_sign; // 符号修正后的非线性激活查找表数据输出
	wire signed[16:0] non_ln_act_ovf_v; // 溢出时的非线性激活结果
	wire signed[16:0] act_v; // 激活值(Q15)
	wire signed[31:0] act_v_ext; // 符号位拓展后的激活值(Q15)
	reg signed[31:0] act_v_fmt; // 格式化后的激活值(小数位数 = act_in_quaz_acc + act_in_ext_frac_width)
	reg act_in_vld_d3; // 延迟3clk的激活输入有效指示
	
	assign act_out = act_v_fmt[act_cal_width*2-1:0];
	assign act_out_vld = act_in_vld_d3;
	
	// is_act_in_neg_d ? ({1'b1, ~non_ln_act_lut_dout} + 1'b1):{1'b0, non_ln_act_lut_dout}
	assign non_ln_act_lut_dout_with_sign = 
		{is_act_in_neg_d, {16{is_act_in_neg_d}} ^ non_ln_act_lut_dout} + is_act_in_neg_d;
	assign non_ln_act_ovf_v = is_act_in_neg_d ? 
		// 负溢出
		((non_ln_act_type == NON_LN_ACT_SIGMOID) ? 
			// -0.5
			{2'b11, 15'b100_0000_0000_0000}:
			// -1
			{2'b11, 15'b000_0000_0000_0000}):
		// 正溢出
		((non_ln_act_type == NON_LN_ACT_SIGMOID) ? 
			// 0.5
			{2'b00, 15'b100_0000_0000_0000}:
			// 1
			{2'b01, 15'b000_0000_0000_0000});
	assign act_v = 
		(act_res_up_ovf ? non_ln_act_ovf_v:non_ln_act_lut_dout_with_sign) + 
		// 对于Sigmoid激活, 需要在查找表数据输出后加上0.5来进行修正
		{2'b00, non_ln_act_type == NON_LN_ACT_SIGMOID, 14'b00_0000_0000_0000};
	assign act_v_ext = {{15{act_v[16]}}, act_v};
	
	// 格式化后的激活值
	always @(posedge clk)
	begin
		if(act_in_vld_d2)
			act_v_fmt <= # simulation_delay 
				((act_in_quaz_acc + act_in_ext_frac_width) >= 15) ? 
					(act_v_ext << (act_in_quaz_acc + act_in_ext_frac_width - 15)):
					(act_v_ext >>> (15 - (act_in_quaz_acc + act_in_ext_frac_width)));
	end
	
	// 延迟3clk的激活输入有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			act_in_vld_d3 <= 1'b0;
		else
			act_in_vld_d3 <= # simulation_delay act_in_vld_d2;
	end
	
endmodule
