`timescale 1ns / 1ps
/********************************************************************
��ģ��: ��ͨ���������л�����

����:
�洢�������ͼĳ��ͨ����ĳ1��

д�л�����ʱ�ȶ���ԭ�����ټ����µ��м�����д��

MEMλ�� = ft_vld_width
MEM��� = max_feature_map_w
MEMд�ӳ� = 2clk
MEM���ӳ� = 1clk

ע�⣺
��

Э��:
MEM READ/WRITE

����: �¼�ҫ
����: 2024/11/02
********************************************************************/


module conv_out_line_buffer #(
	parameter integer ft_vld_width = 20, // ��������Чλ��(����<=ft_ext_width)
	parameter integer max_feature_map_w = 512, // ������������ͼ���
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
	input wire clk,
	input wire rst_n,
	
	// �л�������/д�˿�
	input wire buffer_en,
	input wire buffer_wen,
	input wire[15:0] buffer_addr,
	input wire buffer_w_first_grp, // д��1���м���(��־)
	input wire[ft_vld_width-1:0] buffer_din,
	output wire[ft_vld_width-1:0] buffer_dout,
	
	// �л�����״̬
	output wire conv_mid_res_updating // ���ڸ��¾���м���
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
	
	/** �л�����MEM **/
	// MEMд�˿�
	wire mem_wen_a;
	wire[clogb2(max_feature_map_w-1):0] mem_addr_a;
    wire[ft_vld_width-1:0] mem_din_a;
	// MEM���˿�
	wire mem_ren_b;
    wire[clogb2(max_feature_map_w-1):0] mem_addr_b;
    wire[ft_vld_width-1:0] mem_dout_b;
	// д���µ��м���
	reg on_mem_wen_d; // �ӳ�1clk����Ч��MEMдʹ��
	reg on_mem_wen_d2; // �ӳ�2clk����Ч��MEMдʹ��
	reg buffer_w_first_grp_d; // �ӳ�1clk��д��1���м�����־
	reg[ft_vld_width-1:0] buffer_din_d; // �ӳ�1clk��д����
	reg[clogb2(max_feature_map_w-1):0] buffer_waddr_d; // �ӳ�1clk��д��ַ
	reg[clogb2(max_feature_map_w-1):0] buffer_waddr_d2; // �ӳ�2clk��д��ַ
	reg[ft_vld_width-1:0] new_conv_mid_res; // �µľ���м���
	// �л�����״̬
	reg buffer_updating; // ���ڸ��¾���м���(��־)
	
	assign mem_wen_a = on_mem_wen_d2;
	assign mem_addr_a = buffer_waddr_d2;
	assign mem_din_a = new_conv_mid_res;
	
	assign mem_ren_b = buffer_en & ((~buffer_wen) | (~buffer_w_first_grp));
	assign mem_addr_b = buffer_addr;
	assign buffer_dout = mem_dout_b;
	
	assign conv_mid_res_updating = buffer_updating;
	
	// �ӳ�1clk����Ч��MEMдʹ��
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			on_mem_wen_d <= 1'b0;
		else
			on_mem_wen_d <= # simulation_delay buffer_en & buffer_wen;
	end
	// �ӳ�2clk����Ч��MEMдʹ��
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			on_mem_wen_d2 <= 1'b0;
		else
			on_mem_wen_d2 <= # simulation_delay on_mem_wen_d;
	end
	
	// �ӳ�1clk��д��1���м�����־
	always @(posedge clk)
	begin
		if(buffer_en & buffer_wen)
			buffer_w_first_grp_d <= # simulation_delay buffer_w_first_grp;
	end
	
	// �ӳ�1clk��д����
	always @(posedge clk)
	begin
		if(buffer_en & buffer_wen)
			buffer_din_d <= # simulation_delay buffer_din;
	end
	
	// �ӳ�1clk��д��ַ
	always @(posedge clk)
	begin
		if(buffer_en & buffer_wen)
			buffer_waddr_d <= # simulation_delay buffer_addr[clogb2(max_feature_map_w-1):0];
	end
	// �ӳ�2clk��д��ַ
	always @(posedge clk)
	begin
		if(on_mem_wen_d)
			buffer_waddr_d2 <= # simulation_delay buffer_waddr_d;
	end
	
	// �µľ���м���
	always @(posedge clk)
	begin
		if(on_mem_wen_d)
			// buffer_w_first_grp_d ? buffer_din_d:(buffer_din_d + mem_dout_b)
			new_conv_mid_res <= # simulation_delay buffer_din_d + 
				({ft_vld_width{~buffer_w_first_grp_d}} & mem_dout_b);
	end
	
	// ���ڸ��¾���м���(��־)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_updating <= 1'b0;
		else
			buffer_updating <= # simulation_delay (buffer_en & buffer_wen) | on_mem_wen_d;
	end
	
	// �л�����MEM
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(ft_vld_width),
		.mem_depth(max_feature_map_w),
		.INIT_FILE("no_init"),
		.byte_write_mode("false"),
		.simulation_delay(simulation_delay)
	)line_buffer_mem(
		.clk(clk),
		
		.wen_a(mem_wen_a),
		.addr_a(mem_addr_a),
		.din_a(mem_din_a),
		
		.ren_b(mem_ren_b),
		.addr_b(mem_addr_b),
		.dout_b(mem_dout_b)
	);
	
endmodule
