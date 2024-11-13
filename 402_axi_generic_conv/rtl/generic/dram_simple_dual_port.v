`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// ��Ŀ: ��˫�˿�Dram
/* 
����: 
��ѡ������Ĵ���
*/
/*
ע�⣺
��
*/
// ����: �¼�ҫ
// ����: 2022/1/13
//////////////////////////////////////////////////////////////////////////////////


module dram_simple_dual_port #(
    parameter integer mem_width = 24, // �洢��λ��
    parameter integer mem_depth = 32, // �洢�����
    parameter INIT_FILE = "no_init", // ��ʼ���ļ�·��
    parameter use_output_register = "true", // �Ƿ�ʹ������Ĵ���
    parameter output_register_init_v = 0, // ����Ĵ�����λֵ
    parameter real simulation_delay = 10 // ����ʱ�õ���ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // mem
    // write port
    input wire wen_a,
    input wire[clogb2(mem_depth-1):0] addr_a,
    input wire[mem_width-1:0] din_a,
    // read port
    input wire ren_b,
    input wire[clogb2(mem_depth-1):0] addr_b,
    output wire[mem_width-1:0] dout_b
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
    
    (* ram_style="distributed" *) reg[mem_width-1:0] mem[mem_depth-1:0]; // �洢��
    
    generate
    if (INIT_FILE != "")
    begin
        if(INIT_FILE != "no_init")
        begin
            initial
                $readmemh(INIT_FILE, mem, 0, mem_depth - 1);
        end
    end
    else
    begin
        integer ram_index;
        initial
        for (ram_index = 0; ram_index < mem_depth; ram_index = ram_index + 1)
            mem[ram_index] = {mem_width{1'b0}};
    end
    endgenerate
    
    // ��д�����߼�
    generate
        if(use_output_register == "true")
        begin
            reg[mem_width-1:0] dout_b_regs;
            
            assign dout_b = dout_b_regs;
            
            always @(posedge clk)
            begin
                if(wen_a)
                    mem[addr_a] <= # simulation_delay din_a;
            end
            
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    dout_b_regs <= output_register_init_v;
                else if(ren_b)
                    dout_b_regs <= # simulation_delay mem[addr_b];
            end
        end
        else
        begin
            always @(posedge clk)
            begin
                if(wen_a)
                    mem[addr_a] <= # simulation_delay din_a;
            end
            
            assign dout_b = mem[addr_b];
        end
    endgenerate

endmodule