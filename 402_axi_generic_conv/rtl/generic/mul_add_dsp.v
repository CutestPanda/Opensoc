`timescale 1ns / 1ps
/********************************************************************
��ģ��: �˼���DSP��Ԫ

����:
�з��ų˼���: mul_add_out = (op_a + op_d) * op_b + op_c
            ��mul_add_out = op_a * op_b + op_c
֧�ֶ�����������ģʽƥ��
��ѡ�Ĳ�����A/B/D����Ĵ���
��ѡ��Ԥ����
2/3����ˮ��

ע�⣺
����xilinxϵ��FPGA, 1��DSP��Ԫ������ɼ���:
	P[47:0] = (A[24:0] + D[24:0]) * B[17:0] + C[47:0]

Э��:
��

����: �¼�ҫ
����: 2024/10/18
********************************************************************/


module mul_add_dsp #(
    parameter en_op_a_in_regs = "true", // �Ƿ�ʹ�ܲ�����A����Ĵ���
    parameter en_op_b_in_regs = "true", // �Ƿ�ʹ�ܲ�����B����Ĵ���
    parameter en_op_d_in_regs = "false", // �Ƿ�ʹ�ܲ�����D����Ĵ���
    parameter en_pre_adder = "true", // �Ƿ�ʹ��Ԥ����
	parameter en_op_b_in_s1_regs = "true", // �Ƿ�ʹ�ܲ�����B��1������Ĵ���
	parameter en_op_c_in_s1_regs = "false", // �Ƿ�ʹ�ܲ�����C��1������Ĵ���
	parameter integer op_a_width = 16, // ������Aλ��(��1λ����λ)
	parameter integer op_b_width = 16, // ������Bλ��(��1λ����λ)
	parameter integer op_c_width = 32, // ������Cλ��(��1λ����λ)
	parameter integer op_d_width = 16, // ������Dλ��(��1λ����λ)
	parameter integer output_width = 32, // ���λ��(��1λ����λ)
	parameter integer pattern_detect_msb_id = 11, // ģʽ���MSB���
	parameter integer pattern_detect_lsb_id = 4, // ģʽ���LSB���
	parameter pattern_detect_cmp = 8'h34, // ģʽ���Ƚ�ֵ
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ��
	input wire clk,
	
	// ʹ��
	input wire ce_s0_op_a,
	input wire ce_s0_op_b,
	input wire ce_s0_op_d,
	input wire ce_s1_pre_adder,
	input wire ce_s1_op_b,
	input wire ce_s1_op_c,
	input wire ce_s2_mul,
	input wire ce_s2_op_c,
	input wire ce_s3_p,
	
	// �˼�������
	input wire signed[op_a_width-1:0] op_a,
	input wire signed[op_b_width-1:0] op_b,
	input wire signed[op_c_width-1:0] op_c,
	input wire signed[op_d_width-1:0] op_d,
	
	// �˼������
	output wire signed[output_width-1:0] res,
	// ģʽ�����
	output wire pattern_detect_res
);
    
    /** �ڲ����� **/
    localparam integer pre_adder_out_width = 25; // Ԥ�������λ��
	
	/** ���� **/
	localparam integer mul_in1_width = (en_pre_adder == "true") ? pre_adder_out_width:op_a_width; // �˷�������1λ��
	localparam integer mul_in2_width = op_b_width; // �˷�������2λ��
    
    /** ��ѡ������Ĵ��� **/
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
	��1��
	
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
	��2��
	
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
	��3��
	
	mul_res ----
	            --> mul_res + op_c_d2 --> mul_add_res
	op_c_d2  ---
	
	ģʽ���
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
