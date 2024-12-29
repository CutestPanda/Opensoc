`timescale 1ns / 1ps
/********************************************************************
��ģ��: �˷���DSP��Ԫ

����:
�з��ų˼���: mul_out = op_a * op_b
ʱ�� = 1clk

ע�⣺
����xilinxϵ��FPGA, 1��DSP��Ԫ������ɼ���:
	P[42:0] = A[24:0] * B[17:0]

Э��:
��

����: �¼�ҫ
����: 2024/11/06
********************************************************************/


module mul #(
	parameter integer op_a_width = 16, // ������Aλ��(��1λ����λ)
	parameter integer op_b_width = 16, // ������Bλ��(��1λ����λ)
	parameter integer output_width = 32, // ���λ��(��1λ����λ)
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ��
	input wire clk,
	
	// ʹ��
	input wire ce_s0_mul,
	
	// �˼�������
	input wire signed[op_a_width-1:0] op_a,
	input wire signed[op_b_width-1:0] op_b,
	
	// �˼������
	output wire signed[output_width-1:0] res
);
    
	wire signed[op_a_width-1:0] mul_in1;
	wire signed[op_b_width-1:0] mul_in2;
	reg signed[(op_a_width+op_b_width)-1:0] mul_res;
	
	assign res = mul_res;
	
	assign mul_in1 = op_a;
	assign mul_in2 = op_b;
	
	always @(posedge clk)
	begin
		if(ce_s0_mul)
			mul_res <= # simulation_delay mul_in1 * mul_in2;
	end
	
endmodule
