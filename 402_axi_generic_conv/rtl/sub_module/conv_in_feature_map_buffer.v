`timescale 1ns / 1ps
/********************************************************************
��ģ��: �����Ԫ����������ͼ������

����:
�л���MEM: 3�� * (max_feature_map_w * feature_data_width / 64)��� * (64 + 64 / feature_data_width)λ��
��ʱ�� = 2clk

д������ʱ��64λ����Ϊ��λ, ��ѡ��дĳЩ��; ��������ʱ��������Ϊ��λ, ֻ�ܽ�3��ͬʱ����

ע�⣺
��

Э��:
MEM READ/WRITE

����: �¼�ҫ
����: 2024/10/18
********************************************************************/


module conv_in_feature_map_buffer #(
	parameter integer feature_data_width = 16, // ������λ��(8 | 16 | 32 | 64)
	parameter integer max_feature_map_w = 512, // ������������ͼ���
	parameter line_buffer_mem_type = "bram", // �л���MEM����("bram" | "lutram" | "auto")
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ��
	input wire clk,
	
	// ������д�˿�
	input wire[2:0] buffer_wen,
	input wire[15:0] buffer_waddr, // ÿ��д��ַ��Ӧ64λ����
	input wire[63:0] buffer_din, // 64λ����
	input wire[64/feature_data_width-1:0] buffer_din_last, // ��β��־
	
	// ���������˿�
	input wire buffer_ren_s0,
	input wire buffer_ren_s1,
	input wire[15:0] buffer_raddr, // ÿ������ַ��Ӧ1��������
	output wire[feature_data_width-1:0] buffer_dout_r0, // ��#0������
	output wire[feature_data_width-1:0] buffer_dout_r1, // ��#1������
	output wire[feature_data_width-1:0] buffer_dout_r2, // ��#2������
	output wire buffer_dout_last_r0, // ��#0��β��־
	output wire buffer_dout_last_r1, // ��#1��β��־
	output wire buffer_dout_last_r2 // ��#2��β��־
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
	
	/** ���� **/
	localparam integer line_buffer_mem_data_width = 64 + 64 / feature_data_width; // �л���MEMλ��
	localparam integer line_buffer_mem_depth = max_feature_map_w * feature_data_width / 64; // �л���MEM���
	localparam line_buffer_mem_type_confirmed = (line_buffer_mem_type == "auto") ? 
		((line_buffer_mem_depth <= 64) ? "lutram":"bram"):line_buffer_mem_type; // ȷ��ʹ�õ��л���MEM����
	
	/** �л���MEM **/
	// MEMд�˿�
    wire[2:0] line_buffer_mem_wen_a;
    wire[clogb2(line_buffer_mem_depth-1):0] line_buffer_mem_addr_a[2:0];
    wire[line_buffer_mem_data_width-1:0] line_buffer_mem_din_a[2:0]; // {��β��־, 64λ����}
    // MEM���˿�
	wire[clogb2(line_buffer_mem_depth-1):0] line_buffer_mem_raddr;
    wire[2:0] line_buffer_mem_ren_b;
    wire[clogb2(line_buffer_mem_depth-1):0] line_buffer_mem_addr_b[2:0];
    wire[line_buffer_mem_data_width-1:0] line_buffer_mem_dout_b[2:0]; // {��β��־, 64λ����}
	
	assign line_buffer_mem_wen_a = buffer_wen;
	assign line_buffer_mem_addr_a[2] = buffer_waddr[clogb2(line_buffer_mem_depth-1):0];
	assign line_buffer_mem_addr_a[1] = buffer_waddr[clogb2(line_buffer_mem_depth-1):0];
	assign line_buffer_mem_addr_a[0] = buffer_waddr[clogb2(line_buffer_mem_depth-1):0];
	assign line_buffer_mem_din_a[2] = {buffer_din_last, buffer_din};
	assign line_buffer_mem_din_a[1] = {buffer_din_last, buffer_din};
	assign line_buffer_mem_din_a[0] = {buffer_din_last, buffer_din};
	
	assign line_buffer_mem_ren_b = {3{buffer_ren_s0}};
	assign line_buffer_mem_addr_b[2] = line_buffer_mem_raddr;
	assign line_buffer_mem_addr_b[1] = line_buffer_mem_raddr;
	assign line_buffer_mem_addr_b[0] = line_buffer_mem_raddr;
	
	assign line_buffer_mem_raddr = buffer_raddr[clogb2(max_feature_map_w-1):
		((feature_data_width == 64) ? 0:(clogb2(64/feature_data_width-1)+1))];
	
	// ��˫��RAM
	genvar line_buffer_mem_i;
	
	generate
		for(line_buffer_mem_i = 0;line_buffer_mem_i < 3;line_buffer_mem_i = line_buffer_mem_i + 1)
		begin
			if(line_buffer_mem_type_confirmed == "bram")
			begin
				bram_simple_dual_port #(
					.style("LOW_LATENCY"),
					.mem_width(line_buffer_mem_data_width),
					.mem_depth(line_buffer_mem_depth),
					.INIT_FILE("no_init"),
					.byte_write_mode("false"),
					.simulation_delay(simulation_delay)
				)line_buffer_mem(
					.clk(clk),
					
					.wen_a(line_buffer_mem_wen_a[line_buffer_mem_i]),
					.addr_a(line_buffer_mem_addr_a[line_buffer_mem_i]),
					.din_a(line_buffer_mem_din_a[line_buffer_mem_i]),
					
					.ren_b(line_buffer_mem_ren_b[line_buffer_mem_i]),
					.addr_b(line_buffer_mem_addr_b[line_buffer_mem_i]),
					.dout_b(line_buffer_mem_dout_b[line_buffer_mem_i])
				);
			end
			else
			begin
				dram_simple_dual_port #(
					.mem_width(line_buffer_mem_data_width),
					.mem_depth(line_buffer_mem_depth),
					.INIT_FILE("no_init"),
					.use_output_register("true"),
					.output_register_init_v(0),
					.simulation_delay(simulation_delay)
				)line_buffer_mem(
					.clk(clk),
					.rst_n(1'b1), // ���ظ�λ����Ĵ���
					
					.wen_a(line_buffer_mem_wen_a[line_buffer_mem_i]),
					.addr_a(line_buffer_mem_addr_a[line_buffer_mem_i]),
					.din_a(line_buffer_mem_din_a[line_buffer_mem_i]),
					
					.ren_b(line_buffer_mem_ren_b[line_buffer_mem_i]),
					.addr_b(line_buffer_mem_addr_b[line_buffer_mem_i]),
					.dout_b(line_buffer_mem_dout_b[line_buffer_mem_i])
				);

			end
		end
	endgenerate
	
	/** ��������� **/
	reg[clogb2(max_feature_map_w-1):0] buffer_raddr_d; // �ӳ�1clk���л���������ַ
	reg[feature_data_width:0] buffer_dout_regs[2:0]; // �л����������ݼĴ���({��β��־, ������})
	
	assign {buffer_dout_last_r2, buffer_dout_r2} = buffer_dout_regs[2];
	assign {buffer_dout_last_r1, buffer_dout_r1} = buffer_dout_regs[1];
	assign {buffer_dout_last_r0, buffer_dout_r0} = buffer_dout_regs[0];
	
	// �ӳ�1clk���л���������ַ
	always @(posedge clk)
	begin
		if(buffer_ren_s0)
			buffer_raddr_d <= # simulation_delay buffer_raddr[clogb2(max_feature_map_w-1):0];
	end
	
	// �л����������ݼĴ���
	genvar buffer_dout_i;
	generate
		for(buffer_dout_i = 0;buffer_dout_i < 3;buffer_dout_i = buffer_dout_i + 1)
		begin
			// ������
			always @(posedge clk)
			begin
				if(buffer_ren_s1)
					buffer_dout_regs[buffer_dout_i][feature_data_width-1:0] <= # simulation_delay 
						line_buffer_mem_dout_b[buffer_dout_i][63:0] >> 
							(buffer_raddr_d[clogb2(64/feature_data_width-1):0] * feature_data_width * (feature_data_width != 64));
			end
			// ��β��־
			always @(posedge clk)
			begin
				if(buffer_ren_s1)
					buffer_dout_regs[buffer_dout_i][feature_data_width] <= # simulation_delay 
						line_buffer_mem_dout_b[buffer_dout_i][line_buffer_mem_data_width-1:64] >> 
							(buffer_raddr_d[clogb2(64/feature_data_width-1):0] * (feature_data_width != 64));
			end
		end
	endgenerate
	
endmodule
