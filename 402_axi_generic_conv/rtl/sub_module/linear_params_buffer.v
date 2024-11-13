`timescale 1ns / 1ps
/********************************************************************
��ģ��: �����Ԫ�����Բ���������

����:
���ڻ������Բ���

���Բ�������MEM: max_kernal_n��� * (2*kernal_param_data_width)λ��
��ʱ�� = 1clk

���Բ���(A, B): AX + B

ע�⣺
��

Э��:
MEM READ/WRITE

����: �¼�ҫ
����: 2024/10/19
********************************************************************/


module linear_params_buffer #(
	parameter integer kernal_param_data_width = 16, // ����˲���λ��(8 | 16 | 32 | 64)
	parameter integer max_kernal_n = 512, // ���ľ���˸���
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ��
	input wire clk,
	
	// ���Բ���������д�˿�
	input wire buffer_wen_a, // ���Բ���A������дʹ��
	input wire buffer_wen_b, // ���Բ���B������дʹ��
	input wire[15:0] buffer_waddr, // ÿ��д��ַ��Ӧ1�����Բ���
	input wire[kernal_param_data_width-1:0] buffer_din_a, // ���Բ���A������д����
	input wire[kernal_param_data_width-1:0] buffer_din_b, // ���Բ���B������д����
	
	// ���Բ������������˿�
	input wire buffer_ren,
	input wire[15:0] buffer_raddr, // ÿ������ַ��Ӧ1�����Բ���
	output wire[kernal_param_data_width-1:0] buffer_dout_a, // ���Բ���A������������
	output wire[kernal_param_data_width-1:0] buffer_dout_b // ���Բ���B������������
);
    
	// ����bit_depth�������Чλ���(��λ��-1)
    function integer clogb2(input integer bit_depth);
    begin
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
    end
    endfunction
	
	/** ���Բ�������MEM **/
	wire[kernal_param_data_width*2-1:0] linear_pars_buffer_mem_dout; // ���Բ�������MEM������
	
	assign {buffer_dout_b, buffer_dout_a} = linear_pars_buffer_mem_dout;
	
	// ��˫��RAM
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(2*kernal_param_data_width),
		.mem_depth(max_kernal_n),
		.INIT_FILE("no_init"),
		.byte_write_mode("true"),
		.simulation_delay(simulation_delay)
	)linear_pars_buffer_mem(
		.clk(clk),
		
		.wen_a({{(kernal_param_data_width/8){buffer_wen_b}}, 
			{(kernal_param_data_width/8){buffer_wen_a}}}),
		.addr_a(buffer_waddr[clogb2(max_kernal_n-1):0]),
		.din_a({buffer_din_b, buffer_din_a}),
		
		.ren_b(buffer_ren),
		.addr_b(buffer_raddr[clogb2(max_kernal_n-1):0]),
		.dout_b(linear_pars_buffer_mem_dout)
	);
	
endmodule
