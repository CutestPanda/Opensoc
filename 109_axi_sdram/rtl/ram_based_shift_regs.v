`timescale 1ns / 1ps
/********************************************************************
��ģ��: ����ram����λ�Ĵ���

����: 
�̶����ӳ�������
֧��ʹ��ram��ff��������λ�Ĵ���
���ô���ram��д��ַ��ʵ�����ӳ�(ͨ������4��)

ע�⣺
ram�Ķ��ӳ�ֻ����1(��Ľ�, ��֧��ram���ӳ�Ϊ2!!!!!!!!)

Э��:
��

����: �¼�ҫ
����: 2023/01/18
********************************************************************/


module ram_based_shift_regs #(
    parameter integer data_width = 8, // ����λ��
    parameter integer delay_n = 16, // �ӳ�������
    parameter shift_type = "ram", // ��λ�Ĵ�������(ram | ff)
    parameter ram_type = "lutram", // ram����(lutram | bram)
    parameter INIT_FILE = "no_init", // RAM��ʼ���ļ�·��
    parameter en_output_register_init = "true", // ����Ĵ����Ƿ���Ҫ��λ
    parameter output_register_init_v = 0, // ����Ĵ�����λֵ
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire resetn,
    
    // ��λ�Ĵ���
    input wire[data_width-1:0] shift_in,
    input wire ce,
    output wire[data_width-1:0] shift_out
);

    // ����bit_depth�������Чλ���(��λ��-1)             
    function integer clogb2 (input integer bit_depth);
        integer temp;
    begin
        temp = bit_depth;
        for(clogb2 = -1;temp > 0;clogb2 = clogb2 + 1)
            temp = temp >> 1;
    end
    endfunction
    
    /** ����FF����λ�Ĵ��� **/
    reg[data_width-1:0] shift_ffs[delay_n-1:0];
    
    genvar shift_ffs_i;
    generate
        for(shift_ffs_i = 0;shift_ffs_i < delay_n;shift_ffs_i = shift_ffs_i + 1)
        begin
            if(en_output_register_init == "false")
            begin
                always @(posedge clk)
                begin
                    if(ce)
                        # simulation_delay shift_ffs[shift_ffs_i] <= (shift_ffs_i == 0) ?
                            shift_in:shift_ffs[shift_ffs_i-1];
                end
            end
            else
            begin
                always @(posedge clk or negedge resetn)
                begin
                    if(~resetn)
                        shift_ffs[shift_ffs_i] <= output_register_init_v;
                    else if(ce)
                        # simulation_delay shift_ffs[shift_ffs_i] <= (shift_ffs_i == 0) ?
                            shift_in:shift_ffs[shift_ffs_i-1];
                end
            end
        end
    endgenerate

    /** ����ram����λ�Ĵ��� **/
    // д�˿�
    wire wen_a;
    reg[clogb2(delay_n-1):0] addr_a;
    wire[data_width-1:0] din_a;
    // ���˿�
    wire ren_b;
    reg[clogb2(delay_n-1):0] addr_b;
    wire[data_width-1:0] dout_b;
    
    assign wen_a = ce;
    assign ren_b = ce;
    assign din_a = shift_in;
    
    generate
		if(shift_type == "ram")
		begin
			if(ram_type == "lutram")
				dram_simple_dual_port #(
					.mem_width(data_width),
					.mem_depth(delay_n),
					.INIT_FILE(INIT_FILE),
					.use_output_register("true"),
					.output_register_init_v(output_register_init_v),
					.simulation_delay(simulation_delay)
				)ram_u(
					.clk(clk),
					.rst_n(resetn),
					.wen_a(wen_a),
					.addr_a(addr_a),
					.din_a(din_a),
					.ren_b(ren_b),
					.addr_b(addr_b),
					.dout_b(dout_b)
				);
			else
				bram_simple_dual_port #(
					.style("LOW_LATENCY"),
					.mem_width(data_width),
					.mem_depth(delay_n),
					.INIT_FILE(INIT_FILE),
					.simulation_delay(simulation_delay)
				)ram_u(
					.clk(clk),
					.wen_a(wen_a),
					.addr_a(addr_a),
					.din_a(din_a),
					.ren_b(ren_b),
					.addr_b(addr_b),
					.dout_b(dout_b)
				);
		end
    endgenerate
    
    // ��д��ַ����
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
        begin
            addr_a <= delay_n - 1;
            addr_b <= 0;
        end
        else if(ce)
        begin
            # simulation_delay;
            
            addr_a <= (addr_a == (delay_n - 1)) ? 0:(addr_a + 1);
            addr_b <= (addr_b == (delay_n - 1)) ? 0:(addr_b + 1);
        end
    end
    
    /** ��λ��� **/
    assign shift_out = (shift_type == "ram") ? dout_b:shift_ffs[delay_n-1];

endmodule
