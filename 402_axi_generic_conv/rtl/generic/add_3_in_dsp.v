`timescale 1ns / 1ps
/********************************************************************
��ģ��: ������ӷ���

����:
�з��żӷ���: add_out = (op_a + op_d) + op_c
��ѡʹ��DSP
3����ˮ��

ע�⣺
����xilinxϵ��FPGA, 1��DSP��Ԫ������ɼ���:
	P[47:0] = A[24:0] + D[24:0] + C[47:0]

Э��:
��

����: �¼�ҫ
����: 2024/12/25
********************************************************************/


module add_3_in_dsp #(
	parameter en_use_dsp = "false", // �Ƿ�ʹ��DSP
	parameter integer op_a_width = 16, // ������Aλ��(��1λ����λ)
	parameter integer op_c_width = 16, // ������Cλ��(��1λ����λ)
	parameter integer op_d_width = 16, // ������Dλ��(��1λ����λ)
	parameter integer output_width = 16, // ���λ��(��1λ����λ)
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ��
	input wire clk,
	
	// ʹ��
	input wire ce_s1_pre_adder, // ��ʹ��DSPʱ����
	input wire ce_s1_op_c,
	input wire ce_s2_mul, // ��ʹ��DSPʱ����
	input wire ce_s2_op_c,
	input wire ce_s3_p,
	
	// �ӷ�������
	input wire signed[op_a_width-1:0] op_a,
	input wire signed[op_c_width-1:0] op_c,
	input wire signed[op_d_width-1:0] op_d,
	
	// �ӷ������
	output wire signed[output_width-1:0] res
);
    
	localparam integer adder_s1_res_width = (op_a_width > op_d_width) ? (op_a_width + 1):(op_d_width + 1);
	
	reg signed[adder_s1_res_width-1:0] adder_s1_res;
	reg signed[op_c_width-1:0] op_c_d;
	reg signed[output_width-1:0] adder_s2_res;
	reg signed[output_width-1:0] adder_3_res;
	wire signed[output_width-1:0] dsp_res;
	
	assign res = (en_use_dsp == "true") ? dsp_res:adder_3_res;
	
	always @(posedge clk)
	begin
		if(ce_s1_op_c)
			adder_s1_res <= # simulation_delay op_a + op_d;
	end
	
	always @(posedge clk)
	begin
		if(ce_s1_op_c)
			op_c_d <= # simulation_delay op_c;
	end
	
	always @(posedge clk)
	begin
		if(ce_s2_op_c)
			adder_s2_res <= # simulation_delay adder_s1_res + op_c_d;
	end
	
	always @(posedge clk)
	begin
		if(ce_s3_p)
			adder_3_res <= # simulation_delay adder_s2_res;
	end
	
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
        
        .res(dsp_res),
        .pattern_detect_res()
    );
	
endmodule
