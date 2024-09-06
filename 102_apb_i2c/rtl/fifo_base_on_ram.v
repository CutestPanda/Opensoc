`timescale 1ns / 1ps
/********************************************************************
��ģ��: ����ram��ͬ��fifo������

����: 
ȫ��ˮ�ĸ�����ͬ��fifo������
����ram
֧��first word fall through����(READ LA = 0)
��ѡ�Ĺ̶���ֵ����/�����ź�

ע�⣺
�����źŵ��洢���� >= almost_full_thʱ��Ч
�����źŵ��洢���� <= almost_empty_thʱ��Ч
almost_full_th��almost_empty_th������[1, fifo_depth-1]��Χ��
��ʹ��FWFTʱ, Ҫ��ram�Ķ��ӳ�=1��2clk; ʹ��FWFTʱ, Ҫ��ram�Ķ��ӳ�=1clk

Э��:
FIFO WRITE/READ
MEM WRITE/READ

����: �¼�ҫ
����: 2023/10/29
********************************************************************/


module fifo_based_on_ram #(
    parameter fwft_mode = "true", // �Ƿ�����first word fall through����
    parameter ram_read_la = 1, // ram���ӳ�(1|2)(���ڲ�ʹ��FWFTʱ����)
    parameter integer fifo_depth = 32, // fifo���(����Ϊ2|4|8|16|...)
    parameter integer fifo_data_width = 32, // fifoλ��
    parameter integer almost_full_th = 20, // fifo������ֵ
    parameter integer almost_empty_th = 5, // fifo������ֵ
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // FIFO WRITE(fifoд�˿�)
    input wire fifo_wen,
    input wire[fifo_data_width-1:0] fifo_din,
    output wire fifo_full,
    output wire fifo_full_n,
    output wire fifo_almost_full,
    output wire fifo_almost_full_n,
    
    // FIFO READ(fifo���˿�)
    input wire fifo_ren,
    output wire[fifo_data_width-1:0] fifo_dout,
    output wire fifo_empty,
    output wire fifo_empty_n,
    output wire fifo_almost_empty,
    output wire fifo_almost_empty_n,
    
    // MEM WRITE(ramд�˿�)
    output wire ram_wen,
    output wire[clogb2(fifo_depth-1):0] ram_w_addr,
    output wire[fifo_data_width-1:0] ram_din,
    
    // MEM RAD(ram���˿�)
    output wire ram_ren,
    output wire[clogb2(fifo_depth-1):0] ram_r_addr,
    input wire[fifo_data_width-1:0] ram_dout,
    
    // �洢����
    output wire[clogb2(fifo_depth):0] data_cnt
);

    // ����log2(bit_depth)               
    function integer clogb2 (input integer bit_depth);
        integer temp;
    begin
        temp = bit_depth;
        for(clogb2 = -1;temp > 0;clogb2 = clogb2 + 1)                   
            temp = temp >> 1;                                 
    end                                        
    endfunction
    
    /** ��fifo **/
    wire m_fifo_ren;
    wire[fifo_data_width-1:0] m_fifo_dout;
    wire m_fifo_empty_n;
    
    generate
        if(fwft_mode == "true")
        begin
            // FWFTģʽ
            fifo_based_on_ram_std #(
                .fifo_depth(fifo_depth),
                .fifo_data_width(fifo_data_width),
                .almost_full_th(almost_full_th),
                .almost_empty_th(almost_empty_th),
                .simulation_delay(simulation_delay)
            )fifo_based_on_ram_std_u(
                .clk(clk),
                .rst_n(rst_n),
                .fifo_wen(fifo_wen),
                .fifo_din(fifo_din),
                .fifo_full(fifo_full),
                .fifo_full_n(fifo_full_n),
                .fifo_almost_full(fifo_almost_full),
                .fifo_almost_full_n(fifo_almost_full_n),
                .fifo_ren(m_fifo_ren),
                .fifo_dout(m_fifo_dout),
                .fifo_empty(),
                .fifo_empty_n(m_fifo_empty_n),
                .fifo_almost_empty(fifo_almost_empty),
                .fifo_almost_empty_n(fifo_almost_empty_n),
                .ram_wen(ram_wen),
                .ram_w_addr(ram_w_addr),
                .ram_din(ram_din),
                .ram_ren(ram_ren),
                .ram_r_addr(ram_r_addr),
                .ram_dout(ram_dout),
                .data_cnt(data_cnt)
            );
        end
        else
        begin
            // ��׼ģʽ
            fifo_based_on_ram_std #(
                .fifo_depth(fifo_depth),
                .fifo_data_width(fifo_data_width),
                .almost_full_th(almost_full_th),
                .almost_empty_th(almost_empty_th),
                .simulation_delay(simulation_delay)
            )fifo_based_on_ram_std_u(
                .clk(clk),
                .rst_n(rst_n),
                .fifo_wen(fifo_wen),
                .fifo_din(fifo_din),
                .fifo_full(fifo_full),
                .fifo_full_n(fifo_full_n),
                .fifo_almost_full(fifo_almost_full),
                .fifo_almost_full_n(fifo_almost_full_n),
                .fifo_ren(fifo_ren),
                .fifo_dout(fifo_dout),
                .fifo_empty(fifo_empty),
                .fifo_empty_n(fifo_empty_n),
                .fifo_almost_empty(fifo_almost_empty),
                .fifo_almost_empty_n(fifo_almost_empty_n),
                .ram_wen(ram_wen),
                .ram_w_addr(ram_w_addr),
                .ram_din(ram_din),
                .ram_ren(ram_ren),
                .ram_r_addr(ram_r_addr),
                .ram_dout(ram_dout),
                .data_cnt(data_cnt)
            );
        end
    endgenerate
    
    /** ��fifo(��FWFTģʽ����Ҫ) **/
    generate
        if(fwft_mode == "true")
        begin
            fifo_show_ahead_buffer #(
                .fifo_data_width(fifo_data_width),
                .simulation_delay(simulation_delay)
            )fifo_show_ahead_buffer_u(
                .clk(clk),
                .rst_n(rst_n),
                
                .std_fifo_ren(m_fifo_ren),
                .std_fifo_dout(m_fifo_dout),
                .std_fifo_empty(~m_fifo_empty_n),
                
                .fwft_fifo_ren(fifo_ren),
                .fwft_fifo_dout(fifo_dout),
                .fwft_fifo_empty(fifo_empty),
                .fwft_fifo_empty_n(fifo_empty_n)
            );
        end
    endgenerate
    
endmodule
