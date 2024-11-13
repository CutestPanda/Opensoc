`timescale 1ns / 1ps
/********************************************************************
本模块: 乘加器DSP单元

描述:
有符号乘加器: mul_add_out = (op_a + op_d) * op_b + op_c
            或mul_add_out = op_a * op_b + op_c
支持对输出结果进行模式匹配
可选的操作数A/B/D输入寄存器
可选的预加器
2/3级流水线

注意：
对于xilinx系列FPGA, 1个DSP单元可以完成计算:
	P[47:0] = (A[24:0] + D[24:0]) * B[17:0] + C[47:0]

协议:
无

作者: 陈家耀
日期: 2024/10/18
********************************************************************/


module mul_add_dsp #(
    parameter en_op_a_in_regs = "true", // 是否使能操作数A输入寄存器
    parameter en_op_b_in_regs = "true", // 是否使能操作数B输入寄存器
    parameter en_op_d_in_regs = "false", // 是否使能操作数D输入寄存器
    parameter en_pre_adder = "true", // 是否使能预加器
	parameter en_op_b_in_s1_regs = "true", // 是否使能操作数B第1级输入寄存器
	parameter en_op_c_in_s1_regs = "false", // 是否使能操作数C第1级输入寄存器
	parameter integer op_a_width = 16, // 操作数A位宽(含1位符号位)
	parameter integer op_b_width = 16, // 操作数B位宽(含1位符号位)
	parameter integer op_c_width = 32, // 操作数C位宽(含1位符号位)
	parameter integer op_d_width = 16, // 操作数D位宽(含1位符号位)
	parameter integer output_width = 32, // 输出位宽(含1位符号位)
	parameter integer pattern_detect_msb_id = 11, // 模式检测MSB编号
	parameter integer pattern_detect_lsb_id = 4, // 模式检测LSB编号
	parameter pattern_detect_cmp = 8'h34, // 模式检测比较值
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟
	input wire clk,
	
	// 使能
	input wire ce_s0_op_a,
	input wire ce_s0_op_b,
	input wire ce_s0_op_d,
	input wire ce_s1_pre_adder,
	input wire ce_s1_op_b,
	input wire ce_s1_op_c,
	input wire ce_s2_mul,
	input wire ce_s2_op_c,
	input wire ce_s3_p,
	
	// 乘加器输入
	input wire signed[op_a_width-1:0] op_a,
	input wire signed[op_b_width-1:0] op_b,
	input wire signed[op_c_width-1:0] op_c,
	input wire signed[op_d_width-1:0] op_d,
	
	// 乘加器输出
	output wire signed[output_width-1:0] res,
	// 模式检测结果
	output wire pattern_detect_res
);
    
    /** 内部配置 **/
    localparam integer pre_adder_out_width = 25; // 预加器输出位宽
	
	/** 常量 **/
	localparam integer mul_in1_width = (en_pre_adder == "true") ? pre_adder_out_width:op_a_width; // 乘法器输入1位宽
	localparam integer mul_in2_width = op_b_width; // 乘法器输入2位宽
    
    /** 可选的输入寄存器 **/
    wire signed[op_a_width-1:0] op_a_in;
	wire signed[op_b_width-1:0] op_b_in;
	wire signed[op_d_width-1:0] op_d_in;
	reg signed[op_a_width-1:0] op_a_in_regs;
	reg signed[op_b_width-1:0] op_b_in_regs;
	reg signed[op_d_width-1:0] op_d_in_regs;
	
	assign op_a_in = (en_op_a_in_regs == "true") ? op_a_in_regs:op_a;
	assign op_b_in = (en_op_b_in_regs == "true") ? op_b_in_regs:op_b;
	assign op_d_in = (en_op_d_in_regs == "true") ? op_d_in_regs:op_d;
	
	always @(posedge clk)
	begin
		if(ce_s0_op_a)
			op_a_in_regs <= # simulation_delay op_a;
	end
	
	always @(posedge clk)
	begin
		if(ce_s0_op_b)
			op_b_in_regs <= # simulation_delay op_b;
	end
	
	always @(posedge clk)
	begin
		if(ce_s0_op_d)
			op_d_in_regs <= # simulation_delay op_d;
	end
    
	/**
	第1级
	
	[
		op_a_in  ---
					--> op_a_in + op_d_in --> pre_adder_res
		op_d_in  ---
	]
	
	[op_b_in ----------------------------> op_b_d]
	[op_c -------------------------------> op_c_in_regs]
	**/
	reg signed[pre_adder_out_width-1:0] pre_adder_res;
	reg signed[op_b_width-1:0] op_b_d;
	wire signed[op_c_width-1:0] op_c_in;
	reg signed[op_c_width-1:0] op_c_in_regs;
	
	assign op_c_in = (en_op_c_in_s1_regs == "true") ? op_c_in_regs:op_c;
	
	always @(posedge clk)
	begin
		if(ce_s1_pre_adder)
			pre_adder_res <= # simulation_delay op_a_in + op_d_in;
	end
	
	always @(posedge clk)
	begin
		if(ce_s1_op_b)
			op_b_d <= # simulation_delay op_b_in;
	end
	
	always @(posedge clk)
	begin
		if(ce_s1_op_c)
			op_c_in_regs <= # simulation_delay op_c;
	end
	
	/**
	第2级
	
	mul_in1  ---------
	                  --> mul_in1 * mul_in2 --> mul_res
	mul_in2  ---------
	
	op_c_in  --------------------------------------> op_c_d2
	**/	
	wire signed[mul_in1_width-1:0] mul_in1;
	wire signed[mul_in2_width-1:0] mul_in2;
	reg signed[(mul_in1_width+mul_in2_width)-1:0] mul_res;
	reg signed[op_c_width-1:0] op_c_d2;
	
	assign mul_in1 = (en_pre_adder == "true") ? pre_adder_res:op_a_in;
	assign mul_in2 = (en_op_b_in_s1_regs == "true") ? op_b_d:op_b_in;
	
	always @(posedge clk)
	begin
		if(ce_s2_mul)
			mul_res <= # simulation_delay mul_in1 * mul_in2;
	end
	
	always @(posedge clk)
	begin
		if(ce_s2_op_c)
			op_c_d2 <= # simulation_delay op_c_in;
	end
	
	/**
	第3级
	
	mul_res ----
	            --> mul_res + op_c_d2 --> mul_add_res
	op_c_d2  ---
	
	模式检测
	**/
	wire signed[output_width-1:0] mul_add;
	reg signed[output_width-1:0] mul_add_res;
	reg pattern_detect_res_reg;
	
	assign res = mul_add_res;
	assign pattern_detect_res = pattern_detect_res_reg;
	
	assign mul_add = mul_res + op_c_d2;
	
	always @(posedge clk)
	begin
		if(ce_s3_p)
			mul_add_res <= # simulation_delay mul_add;
	end
	
	always @(posedge clk)
	begin
	    if(ce_s3_p)
	    	pattern_detect_res_reg <= # simulation_delay 
	        	(mul_add[pattern_detect_msb_id:pattern_detect_lsb_id] == pattern_detect_cmp) ? 1'b1:1'b0;
	end
	
endmodule
