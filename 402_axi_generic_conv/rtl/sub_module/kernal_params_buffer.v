`timescale 1ns / 1ps
/********************************************************************
��ģ��: �����Ԫ�ľ���˲���������

����:
���ڻ������˲���
�ɴ洢1����ͨ�������

����˲�������MEM: max_feature_map_chn_n��� * (9*kernal_param_data_width)λ��
��ʱ�� = 1clk

ע�⣺
��

Э��:
MEM READ/WRITE

����: �¼�ҫ
����: 2024/10/22
********************************************************************/


module kernal_params_buffer #(
	parameter integer kernal_param_data_width = 16, // ����˲���λ��(8 | 16 | 32 | 64)
	parameter integer max_feature_map_chn_n = 512, // ������������ͼͨ����
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ��
	input wire clk,
	
	// ����˲���������д�˿�
	input wire buffer_wen,
	input wire[15:0] buffer_waddr, // ÿ��д��ַ��Ӧ1����ͨ�������
	input wire[kernal_param_data_width*9-1:0] buffer_din,
	
	// ����˲������������˿�
	input wire buffer_ren,
	input wire[15:0] buffer_raddr, // ÿ������ַ��Ӧ1����ͨ�������
	output wire[kernal_param_data_width*9-1:0] buffer_dout // ����˲���������������
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
	
	/** �ڲ����� **/
	localparam sim_mode = "false"; // �Ƿ��ڷ���ģʽ
	
	/** ����˲�������MEM **/
	wire[kernal_param_data_width*9-1:0] kernal_pars_buffer_mem_dout; // ����˲�������MEM������
	
	assign buffer_dout = kernal_pars_buffer_mem_dout;
	
	// ��˫��RAM
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(9*kernal_param_data_width),
		.mem_depth(max_feature_map_chn_n),
		.INIT_FILE((sim_mode == "true") ? "default":"no_init"),
		.byte_write_mode("false"),
		.simulation_delay(simulation_delay)
	)kernal_pars_buffer_mem(
		.clk(clk),
		
		.wen_a(buffer_wen),
		.addr_a(buffer_waddr[clogb2(max_feature_map_chn_n-1):0]),
		.din_a(buffer_din),
		
		.ren_b(buffer_ren),
		.addr_b(buffer_raddr[clogb2(max_feature_map_chn_n-1):0]),
		.dout_b(kernal_pars_buffer_mem_dout)
	);
	
endmodule
