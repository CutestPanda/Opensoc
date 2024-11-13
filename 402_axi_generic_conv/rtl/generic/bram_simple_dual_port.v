`timescale 1ns / 1ps
/********************************************************************
��ģ��: ��˫�˿�Bram

����: 
��ѡ���ӳ�1clk��2clk

ע�⣺
��

Э��:
MEM READ/WRITE

����: �¼�ҫ
����: 2022/1/11
********************************************************************/


module bram_simple_dual_port #(
    parameter style = "HIGH_PERFORMANCE", // �洢����ʽ(HIGH_PERFORMANCE|LOW_LATENCY)
    parameter integer mem_width = 32, // �洢��λ��
    parameter integer mem_depth = 4096, // �洢�����
    parameter INIT_FILE = "no_init", // ��ʼ���ļ�·��
    parameter byte_write_mode = "false", // �Ƿ�ʹ��д�ֽ�����
    parameter integer simulation_delay = 1 // ������ʱ
)
(
    // clk
    input wire clk,
    
    // mem write
    input wire[((byte_write_mode == "true") ? mem_width/8:1)-1:0] wen_a,
    input wire[clogb2(mem_depth-1):0] addr_a,
    input wire[mem_width-1:0] din_a,
    
    // mem read
    input wire ren_b,
    input wire[clogb2(mem_depth-1):0] addr_b,
    output wire[mem_width-1:0] dout_b
);

    // ����bit_depth�������Чλ���(��λ��-1)             
    function integer clogb2 (input integer bit_depth);              
    begin                                                           
        for(clogb2=-1; bit_depth>0; clogb2=clogb2+1)                   
          bit_depth = bit_depth >> 1;                                 
        end                                        
    endfunction
    
    (* ram_style="block" *) reg[mem_width-1:0] mem[mem_depth-1:0]; // �洢��
    reg[mem_width-1:0] ram_data_b;
    
    generate
        if (INIT_FILE != "")
        begin
            if(INIT_FILE == "default")
            begin
                integer ram_index;
                initial
                for (ram_index = 0; ram_index < mem_depth; ram_index = ram_index + 1)
                    mem[ram_index] = ram_index;
            end
            else if(INIT_FILE != "no_init")
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
    genvar byte_write_i;
    generate
        if(byte_write_mode == "true")
        begin
            for(byte_write_i = 0;byte_write_i < mem_width/8;byte_write_i = byte_write_i + 1)
            begin
                always @(posedge clk)
                begin
                    if(wen_a[byte_write_i])
                        mem[addr_a][(byte_write_i+1)*8-1:byte_write_i*8] <= # simulation_delay din_a[(byte_write_i+1)*8-1:byte_write_i*8];
                end
            end
        end
        else
        begin
            always @(posedge clk)
            begin
                if(wen_a)
                    mem[addr_a] <= # simulation_delay din_a;
            end
        end
    endgenerate
    
    always @(posedge clk)
    begin
        if(ren_b)
            ram_data_b <= # simulation_delay mem[addr_b];
    end
    
    generate
        if(style == "HIGH_PERFORMANCE")
        begin
            // ʹ������Ĵ���
            reg[mem_width-1:0] data_b;
            
            assign dout_b = data_b;
            
            always @(posedge clk)
                data_b <= #simulation_delay ram_data_b;
        end
        else
        begin
            // ��ʹ������Ĵ���
            assign dout_b = ram_data_b;
        end
    endgenerate
    
endmodule
