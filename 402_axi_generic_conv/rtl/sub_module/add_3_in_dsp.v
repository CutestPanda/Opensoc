`timescale 1ns / 1ps
/********************************************************************
本模块: 三输入加法器DSP单元

描述:
有符号加法器: add_out = (op_a + op_d) + op_c
3级流水线

注意：
对于xilinx系列FPGA, 1个DSP单元可以完成计算:
	P[47:0] = A[24:0] + D[24:0] + C[47:0]

协议:
无

作者: 陈家耀
日期: 2024/10/23
********************************************************************/


module add_3_in_dsp #(
	parameter integer op_a_width = 16, // 操作数A位宽(含1位符号位)
	parameter integer op_c_width = 16, // 操作数C位宽(含1位符号位)
	parameter integer op_d_width = 16, // 操作数D位宽(含1位符号位)
	parameter integer output_width = 16, // 输出位宽(含1位符号位)
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟
	input wire clk,
	
	// 使能
	input wire ce_s1_pre_adder,
	input wire ce_s1_op_c,
	input wire ce_s2_mul,
	input wire ce_s2_op_c,
	input wire ce_s3_p,
	
	// 加法器输入
	input wire signed[op_a_width-1:0] op_a,
	input wire signed[op_c_width-1:0] op_c,
	input wire signed[op_d_width-1:0] op_d,
	
	// 加法器输出
	output wire signed[output_width-1:0] res
);
    
    mul_add_dsp #(
        .en_op_a_in_regs("false"),
        .en_op_b_in_regs("false"),
        .en_op_d_in_regs("false"),
        .en_pre_adder("true"),
		.en_op_b_in_s1_regs("true"),
		.en_op_c_in_s1_regs("true"),
        .op_a_width(op_a_width),
        .op_b_width(18),
        .op_c_width(op_c_width),
        .op_d_width(op_d_width),
        .output_width(output_width),
        .pattern_detect_msb_id(0),
        .pattern_detect_lsb_id(0),
        .pattern_detect_cmp(1'b0),
        .simulation_delay(simulation_delay)
    )mul_add_dsp_u(
        .clk(clk),
        
        .ce_s0_op_a(1'b1), // not care
        .ce_s0_op_b(1'b1), // not care
        .ce_s0_op_d(1'b1), // not care
        .ce_s1_pre_adder(ce_s1_pre_adder),
        .ce_s1_op_b(1'b1),
        .ce_s1_op_c(ce_s1_op_c),
        .ce_s2_mul(ce_s2_mul),
        .ce_s2_op_c(ce_s2_op_c),
        .ce_s3_p(ce_s3_p),
        
        .op_a(op_a),
        .op_b(18'sd1),
        .op_c(op_c),
        .op_d(op_d),
        
        .res(res),
        .pattern_detect_res()
    );
	
endmodule
