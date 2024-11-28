`timescale 1ns / 1ps
/********************************************************************
��ģ��: ����lutram��bram��ͬ��fifo

����: 
ȫ��ˮ�ĸ�����ͬ��fifo
����lutram��bram
֧��first word fall through����(READ LA = 0)
��ѡ�Ĺ̶���ֵ����/�����ź�
��ѡ�Ĵ洢�������

ע�⣺
�����źŵ��洢���� >= almost_full_thʱ��Ч
�����źŵ��洢���� <= almost_empty_thʱ��Ч
almost_full_th��almost_empty_th������[1, fifo_depth-1]��Χ��
��ģ������fpga, ��ģ��fifo_based_on_ram������asic���
�Ĵ���fifo������ģ��fifo_based_on_regs

Э��:
FIFO WRITE/READ

����: �¼�ҫ
����: 2023/10/29
********************************************************************/


module ram_fifo_wrapper #(
    parameter fwft_mode = "true", // �Ƿ�����first word fall through����
    parameter ram_type = "lutram", // RAM����(lutram|bram)
    parameter en_bram_reg = "false", // �Ƿ�����BRAM����Ĵ���
    parameter integer fifo_depth = 32, // fifo���(����Ϊ2|4|8|16|...)
    parameter integer fifo_data_width = 32, // fifoλ��
    parameter full_assert_polarity = "low", // ���ź���Ч����(low|high)
    parameter empty_assert_polarity = "low", // ���ź���Ч����(low|high)
    parameter almost_full_assert_polarity = "no", // �����ź���Ч����(low|high|no)
    parameter almost_empty_assert_polarity = "no", // �����ź���Ч����(low|high|no)
    parameter en_data_cnt = "false", // �Ƿ����ô洢������
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
    
    wire fifo_full_w;
    wire fifo_full_n_w;
    wire fifo_almost_full_w;
    wire fifo_almost_full_n_w;
    wire fifo_empty_w;
    wire fifo_empty_n_w;
    wire fifo_almost_empty_w;
    wire fifo_almost_empty_n_w;
    wire[clogb2(fifo_depth):0] data_cnt_w;
    
    generate
        if(full_assert_polarity == "low")
            assign fifo_full_n = fifo_full_n_w;
        else
            assign fifo_full = fifo_full_w;
        
        if(almost_full_assert_polarity == "low")
            assign fifo_almost_full_n = fifo_almost_full_n_w;
        else if(almost_full_assert_polarity == "high")
            assign fifo_almost_full = fifo_almost_full_w;
        
        if(empty_assert_polarity == "low")
            assign fifo_empty_n = fifo_empty_n_w;
        else
            assign fifo_empty = fifo_empty_w;
        
        if(almost_empty_assert_polarity == "low")
            assign fifo_almost_empty_n = fifo_almost_empty_n_w;
        else if(almost_empty_assert_polarity == "high")
            assign fifo_almost_empty = fifo_almost_empty_w;
        
        if(en_data_cnt == "true")
            assign data_cnt = data_cnt_w;
    
        if(ram_type == "lutram")
        begin
            fifo_based_on_lutram #(
                .fwft_mode(fwft_mode),
                .fifo_depth(fifo_depth),
                .fifo_data_width(fifo_data_width),
                .almost_full_th(almost_full_th),
                .almost_empty_th(almost_empty_th),
                .simulation_delay(simulation_delay)
            )fifo(
                .clk(clk),
                .rst_n(rst_n),
                .fifo_wen(fifo_wen),
                .fifo_din(fifo_din),
                .fifo_full(fifo_full_w),
                .fifo_full_n(fifo_full_n_w),
                .fifo_almost_full(fifo_almost_full_w),
                .fifo_almost_full_n(fifo_almost_full_n_w),
                .fifo_ren(fifo_ren),
                .fifo_dout(fifo_dout),
                .fifo_empty(fifo_empty_w),
                .fifo_empty_n(fifo_empty_n_w),
                .fifo_almost_empty(fifo_almost_empty_w),
                .fifo_almost_empty_n(fifo_almost_empty_n_w),
                .data_cnt(data_cnt_w)
            );
        end
        else
        begin
            wire ram_wen_a;
            wire[clogb2(fifo_depth-1):0] ram_addr_a;
            wire[fifo_data_width-1:0] ram_din_a;
            wire ram_ren_b;
            wire[clogb2(fifo_depth-1):0] ram_addr_b;
            wire[fifo_data_width-1:0] ram_dout_b;
    
            fifo_based_on_ram #(
                .fwft_mode(fwft_mode),
                .ram_read_la((en_bram_reg == "true") ? 2:1),
                .fifo_depth(fifo_depth),
                .fifo_data_width(fifo_data_width),
                .almost_full_th(almost_full_th),
                .almost_empty_th(almost_empty_th),
                .simulation_delay(simulation_delay)
            )fifo_ctrler(
                .clk(clk),
                .rst_n(rst_n),
                .fifo_wen(fifo_wen),
                .fifo_din(fifo_din),
                .fifo_full(fifo_full_w),
                .fifo_full_n(fifo_full_n_w),
                .fifo_almost_full(fifo_almost_full_w),
                .fifo_almost_full_n(fifo_almost_full_n_w),
                .fifo_ren(fifo_ren),
                .fifo_dout(fifo_dout),
                .fifo_empty(fifo_empty_w),
                .fifo_empty_n(fifo_empty_n_w),
                .fifo_almost_empty(fifo_almost_empty_w),
                .fifo_almost_empty_n(fifo_almost_empty_n_w),
                .ram_wen(ram_wen_a),
                .ram_w_addr(ram_addr_a),
                .ram_din(ram_din_a),
                .ram_ren(ram_ren_b),
                .ram_r_addr(ram_addr_b),
                .ram_dout(ram_dout_b),
                .data_cnt(data_cnt_w)
            );
            
            bram_simple_dual_port #(
                .style((en_bram_reg == "true") ? "HIGH_PERFORMANCE":"LOW_LATENCY"),
                .mem_width(fifo_data_width),
                .mem_depth(fifo_depth),
                .INIT_FILE("no_init"),
				.byte_write_mode("false"),
                .simulation_delay(simulation_delay)
            )fifo_ram(
                .clk(clk),
                .wen_a(ram_wen_a),
                .addr_a(ram_addr_a),
                .din_a(ram_din_a),
                .ren_b(ram_ren_b),
                .addr_b(ram_addr_b),
                .dout_b(ram_dout_b)
            );
        end
    endgenerate
    
endmodule
