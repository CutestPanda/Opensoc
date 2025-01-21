`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXI��APB�ŵĵ�ַ������

����: 
֧�ֶ��16��APB�ӻ��ĵ�ַ������

ע�⣺
ÿ���ӻ��ĵ�ַ���䳤�ȱ��� >= 4096(4KB)

Э��:
��

����: �¼�ҫ
����: 2023/12/10
********************************************************************/


module axi_apb_bridge_dec #(
    parameter integer apb_slave_n = 4, // APB�ӻ�����(1~16)
    parameter integer apb_s0_baseaddr = 0, // 0�Ŵӻ�����ַ
    parameter integer apb_s0_range = 4096, // 0�Ŵӻ���ַ���䳤��
    parameter integer apb_s1_baseaddr = 4096, // 1�Ŵӻ�����ַ
    parameter integer apb_s1_range = 4096, // 1�Ŵӻ���ַ���䳤��
    parameter integer apb_s2_baseaddr = 8192, // 2�Ŵӻ�����ַ
    parameter integer apb_s2_range = 4096, // 2�Ŵӻ���ַ���䳤��
    parameter integer apb_s3_baseaddr = 12288, // 3�Ŵӻ�����ַ
    parameter integer apb_s3_range = 4096, // 3�Ŵӻ���ַ���䳤��
    parameter integer apb_s4_baseaddr = 16384, // 4�Ŵӻ�����ַ
    parameter integer apb_s4_range = 4096, // 4�Ŵӻ���ַ���䳤��
    parameter integer apb_s5_baseaddr = 20480, // 5�Ŵӻ�����ַ
    parameter integer apb_s5_range = 4096, // 5�Ŵӻ���ַ���䳤��
    parameter integer apb_s6_baseaddr = 24576, // 6�Ŵӻ�����ַ
    parameter integer apb_s6_range = 4096, // 6�Ŵӻ���ַ���䳤��
    parameter integer apb_s7_baseaddr = 28672, // 7�Ŵӻ�����ַ
    parameter integer apb_s7_range = 4096, // 7�Ŵӻ���ַ���䳤��
    parameter integer apb_s8_baseaddr = 32768, // 8�Ŵӻ�����ַ
    parameter integer apb_s8_range = 4096, // 8�Ŵӻ���ַ���䳤��
    parameter integer apb_s9_baseaddr = 36864, // 9�Ŵӻ�����ַ
    parameter integer apb_s9_range = 4096, // 9�Ŵӻ���ַ���䳤��
    parameter integer apb_s10_baseaddr = 40960, // 10�Ŵӻ�����ַ
    parameter integer apb_s10_range = 4096, // 10�Ŵӻ���ַ���䳤��
    parameter integer apb_s11_baseaddr = 45056, // 11�Ŵӻ�����ַ
    parameter integer apb_s11_range = 4096, // 11�Ŵӻ���ַ���䳤��
    parameter integer apb_s12_baseaddr = 49152, // 12�Ŵӻ�����ַ
    parameter integer apb_s12_range = 4096, // 12�Ŵӻ���ַ���䳤��
    parameter integer apb_s13_baseaddr = 53248, // 13�Ŵӻ�����ַ
    parameter integer apb_s13_range = 4096, // 13�Ŵӻ���ַ���䳤��
    parameter integer apb_s14_baseaddr = 57344, // 14�Ŵӻ�����ַ
    parameter integer apb_s14_range = 4096, // 14�Ŵӻ���ַ���䳤��
    parameter integer apb_s15_baseaddr = 61440, // 15�Ŵӻ�����ַ
    parameter integer apb_s15_range = 4096 // 15�Ŵӻ���ַ���䳤��
)(
    input wire[31:0] addr,
    output wire[15:0] m_apb_psel,
    output wire[3:0] apb_muxsel
);

    // ��һ������
    assign m_apb_psel[0] = (addr >= apb_s0_baseaddr) & (addr < (apb_s0_baseaddr + apb_s0_range));
    assign m_apb_psel[1] = (apb_slave_n >= 2) & (addr >= apb_s1_baseaddr) & (addr < (apb_s1_baseaddr + apb_s1_range));
    assign m_apb_psel[2] = (apb_slave_n >= 3) & (addr >= apb_s2_baseaddr) & (addr < (apb_s2_baseaddr + apb_s2_range));
    assign m_apb_psel[3] = (apb_slave_n >= 4) & (addr >= apb_s3_baseaddr) & (addr < (apb_s3_baseaddr + apb_s3_range));
    assign m_apb_psel[4] = (apb_slave_n >= 5) & (addr >= apb_s4_baseaddr) & (addr < (apb_s4_baseaddr + apb_s4_range));
    assign m_apb_psel[5] = (apb_slave_n >= 6) & (addr >= apb_s5_baseaddr) & (addr < (apb_s5_baseaddr + apb_s5_range));
    assign m_apb_psel[6] = (apb_slave_n >= 7) & (addr >= apb_s6_baseaddr) & (addr < (apb_s6_baseaddr + apb_s6_range));
    assign m_apb_psel[7] = (apb_slave_n >= 8) & (addr >= apb_s7_baseaddr) & (addr < (apb_s7_baseaddr + apb_s7_range));
    assign m_apb_psel[8] = (apb_slave_n >= 9) & (addr >= apb_s8_baseaddr) & (addr < (apb_s8_baseaddr + apb_s8_range));
    assign m_apb_psel[9] = (apb_slave_n >= 10) & (addr >= apb_s9_baseaddr) & (addr < (apb_s9_baseaddr + apb_s9_range));
    assign m_apb_psel[10] = (apb_slave_n >= 11) & (addr >= apb_s10_baseaddr) & (addr < (apb_s10_baseaddr + apb_s10_range));
    assign m_apb_psel[11] = (apb_slave_n >= 12) & (addr >= apb_s11_baseaddr) & (addr < (apb_s11_baseaddr + apb_s11_range));
    assign m_apb_psel[12] = (apb_slave_n >= 13) & (addr >= apb_s12_baseaddr) & (addr < (apb_s12_baseaddr + apb_s12_range));
    assign m_apb_psel[13] = (apb_slave_n >= 14) & (addr >= apb_s13_baseaddr) & (addr < (apb_s13_baseaddr + apb_s13_range));
    assign m_apb_psel[14] = (apb_slave_n >= 15) & (addr >= apb_s14_baseaddr) & (addr < (apb_s14_baseaddr + apb_s14_range));
    assign m_apb_psel[15] = (apb_slave_n >= 16) & (addr >= apb_s15_baseaddr) & (addr < (apb_s15_baseaddr + apb_s15_range));
    
    // ������������
    generate
        if(apb_slave_n == 1)
            assign apb_muxsel = 4'd0;
        else
        begin
            reg[3:0] apb_muxsel_w;
            
            assign apb_muxsel = apb_muxsel_w;
            
            case(apb_slave_n)
                2:
                begin
                    always @(*)
                    begin
                        if((addr >= apb_s0_baseaddr) & (addr < (apb_s0_baseaddr + apb_s0_range)))
                            apb_muxsel_w = 4'd0;
                        else
                            apb_muxsel_w = 4'd1;
                    end
                end
                3:
                begin
                    always @(*)
                    begin
                        if((addr >= apb_s0_baseaddr) & (addr < (apb_s0_baseaddr + apb_s0_range)))
                            apb_muxsel_w = 4'd0;
                        else if((addr >= apb_s1_baseaddr) & (addr < (apb_s1_baseaddr + apb_s1_range)))
                            apb_muxsel_w = 4'd1;
                        else
                            apb_muxsel_w = 4'd2;
                    end
                end
                4:
                begin
                    always @(*)
                    begin
                        if((addr >= apb_s0_baseaddr) & (addr < (apb_s0_baseaddr + apb_s0_range)))
                            apb_muxsel_w = 4'd0;
                        else if((addr >= apb_s1_baseaddr) & (addr < (apb_s1_baseaddr + apb_s1_range)))
                            apb_muxsel_w = 4'd1;
                        else if((addr >= apb_s2_baseaddr) & (addr < (apb_s2_baseaddr + apb_s2_range)))
                            apb_muxsel_w = 4'd2;
                        else
                            apb_muxsel_w = 4'd3;
                    end
                end
                5:
                begin
                    always @(*)
                    begin
                        if((addr >= apb_s0_baseaddr) & (addr < (apb_s0_baseaddr + apb_s0_range)))
                            apb_muxsel_w = 4'd0;
                        else if((addr >= apb_s1_baseaddr) & (addr < (apb_s1_baseaddr + apb_s1_range)))
                            apb_muxsel_w = 4'd1;
                        else if((addr >= apb_s2_baseaddr) & (addr < (apb_s2_baseaddr + apb_s2_range)))
                            apb_muxsel_w = 4'd2;
                        else if((addr >= apb_s3_baseaddr) & (addr < (apb_s3_baseaddr + apb_s3_range)))
                            apb_muxsel_w = 4'd3;
                        else
                            apb_muxsel_w = 4'd4;
                    end
                end
                6:
                begin
                    always @(*)
                    begin
                        if((addr >= apb_s0_baseaddr) & (addr < (apb_s0_baseaddr + apb_s0_range)))
                            apb_muxsel_w = 4'd0;
                        else if((addr >= apb_s1_baseaddr) & (addr < (apb_s1_baseaddr + apb_s1_range)))
                            apb_muxsel_w = 4'd1;
                        else if((addr >= apb_s2_baseaddr) & (addr < (apb_s2_baseaddr + apb_s2_range)))
                            apb_muxsel_w = 4'd2;
                        else if((addr >= apb_s3_baseaddr) & (addr < (apb_s3_baseaddr + apb_s3_range)))
                            apb_muxsel_w = 4'd3;
                        else if((addr >= apb_s4_baseaddr) & (addr < (apb_s4_baseaddr + apb_s4_range)))
                            apb_muxsel_w = 4'd4;
                        else
                            apb_muxsel_w = 4'd5;
                    end
                end
                7:
                begin
                    always @(*)
                    begin
                        if((addr >= apb_s0_baseaddr) & (addr < (apb_s0_baseaddr + apb_s0_range)))
                            apb_muxsel_w = 4'd0;
                        else if((addr >= apb_s1_baseaddr) & (addr < (apb_s1_baseaddr + apb_s1_range)))
                            apb_muxsel_w = 4'd1;
                        else if((addr >= apb_s2_baseaddr) & (addr < (apb_s2_baseaddr + apb_s2_range)))
                            apb_muxsel_w = 4'd2;
                        else if((addr >= apb_s3_baseaddr) & (addr < (apb_s3_baseaddr + apb_s3_range)))
                            apb_muxsel_w = 4'd3;
                        else if((addr >= apb_s4_baseaddr) & (addr < (apb_s4_baseaddr + apb_s4_range)))
                            apb_muxsel_w = 4'd4;
                        else if((addr >= apb_s5_baseaddr) & (addr < (apb_s5_baseaddr + apb_s5_range)))
                            apb_muxsel_w = 4'd5;
                        else
                            apb_muxsel_w = 4'd6;
                    end
                end
                8:
                begin
                    always @(*)
                    begin
                        if((addr >= apb_s0_baseaddr) & (addr < (apb_s0_baseaddr + apb_s0_range)))
                            apb_muxsel_w = 4'd0;
                        else if((addr >= apb_s1_baseaddr) & (addr < (apb_s1_baseaddr + apb_s1_range)))
                            apb_muxsel_w = 4'd1;
                        else if((addr >= apb_s2_baseaddr) & (addr < (apb_s2_baseaddr + apb_s2_range)))
                            apb_muxsel_w = 4'd2;
                        else if((addr >= apb_s3_baseaddr) & (addr < (apb_s3_baseaddr + apb_s3_range)))
                            apb_muxsel_w = 4'd3;
                        else if((addr >= apb_s4_baseaddr) & (addr < (apb_s4_baseaddr + apb_s4_range)))
                            apb_muxsel_w = 4'd4;
                        else if((addr >= apb_s5_baseaddr) & (addr < (apb_s5_baseaddr + apb_s5_range)))
                            apb_muxsel_w = 4'd5;
                        else if((addr >= apb_s6_baseaddr) & (addr < (apb_s6_baseaddr + apb_s6_range)))
                            apb_muxsel_w = 4'd6;
                        else
                            apb_muxsel_w = 4'd7;
                    end
                end
                9:
                begin
                    always @(*)
                    begin
                        if((addr >= apb_s0_baseaddr) & (addr < (apb_s0_baseaddr + apb_s0_range)))
                            apb_muxsel_w = 4'd0;
                        else if((addr >= apb_s1_baseaddr) & (addr < (apb_s1_baseaddr + apb_s1_range)))
                            apb_muxsel_w = 4'd1;
                        else if((addr >= apb_s2_baseaddr) & (addr < (apb_s2_baseaddr + apb_s2_range)))
                            apb_muxsel_w = 4'd2;
                        else if((addr >= apb_s3_baseaddr) & (addr < (apb_s3_baseaddr + apb_s3_range)))
                            apb_muxsel_w = 4'd3;
                        else if((addr >= apb_s4_baseaddr) & (addr < (apb_s4_baseaddr + apb_s4_range)))
                            apb_muxsel_w = 4'd4;
                        else if((addr >= apb_s5_baseaddr) & (addr < (apb_s5_baseaddr + apb_s5_range)))
                            apb_muxsel_w = 4'd5;
                        else if((addr >= apb_s6_baseaddr) & (addr < (apb_s6_baseaddr + apb_s6_range)))
                            apb_muxsel_w = 4'd6;
                        else if((addr >= apb_s7_baseaddr) & (addr < (apb_s7_baseaddr + apb_s7_range)))
                            apb_muxsel_w = 4'd7;
                        else
                            apb_muxsel_w = 4'd8;
                    end
                end
                10:
                begin
                    always @(*)
                    begin
                        if((addr >= apb_s0_baseaddr) & (addr < (apb_s0_baseaddr + apb_s0_range)))
                            apb_muxsel_w = 4'd0;
                        else if((addr >= apb_s1_baseaddr) & (addr < (apb_s1_baseaddr + apb_s1_range)))
                            apb_muxsel_w = 4'd1;
                        else if((addr >= apb_s2_baseaddr) & (addr < (apb_s2_baseaddr + apb_s2_range)))
                            apb_muxsel_w = 4'd2;
                        else if((addr >= apb_s3_baseaddr) & (addr < (apb_s3_baseaddr + apb_s3_range)))
                            apb_muxsel_w = 4'd3;
                        else if((addr >= apb_s4_baseaddr) & (addr < (apb_s4_baseaddr + apb_s4_range)))
                            apb_muxsel_w = 4'd4;
                        else if((addr >= apb_s5_baseaddr) & (addr < (apb_s5_baseaddr + apb_s5_range)))
                            apb_muxsel_w = 4'd5;
                        else if((addr >= apb_s6_baseaddr) & (addr < (apb_s6_baseaddr + apb_s6_range)))
                            apb_muxsel_w = 4'd6;
                        else if((addr >= apb_s7_baseaddr) & (addr < (apb_s7_baseaddr + apb_s7_range)))
                            apb_muxsel_w = 4'd7;
                        else if((addr >= apb_s8_baseaddr) & (addr < (apb_s8_baseaddr + apb_s8_range)))
                            apb_muxsel_w = 4'd8;
                        else
                            apb_muxsel_w = 4'd9;
                    end
                end
                11:
                begin
                    always @(*)
                    begin
                        if((addr >= apb_s0_baseaddr) & (addr < (apb_s0_baseaddr + apb_s0_range)))
                            apb_muxsel_w = 4'd0;
                        else if((addr >= apb_s1_baseaddr) & (addr < (apb_s1_baseaddr + apb_s1_range)))
                            apb_muxsel_w = 4'd1;
                        else if((addr >= apb_s2_baseaddr) & (addr < (apb_s2_baseaddr + apb_s2_range)))
                            apb_muxsel_w = 4'd2;
                        else if((addr >= apb_s3_baseaddr) & (addr < (apb_s3_baseaddr + apb_s3_range)))
                            apb_muxsel_w = 4'd3;
                        else if((addr >= apb_s4_baseaddr) & (addr < (apb_s4_baseaddr + apb_s4_range)))
                            apb_muxsel_w = 4'd4;
                        else if((addr >= apb_s5_baseaddr) & (addr < (apb_s5_baseaddr + apb_s5_range)))
                            apb_muxsel_w = 4'd5;
                        else if((addr >= apb_s6_baseaddr) & (addr < (apb_s6_baseaddr + apb_s6_range)))
                            apb_muxsel_w = 4'd6;
                        else if((addr >= apb_s7_baseaddr) & (addr < (apb_s7_baseaddr + apb_s7_range)))
                            apb_muxsel_w = 4'd7;
                        else if((addr >= apb_s8_baseaddr) & (addr < (apb_s8_baseaddr + apb_s8_range)))
                            apb_muxsel_w = 4'd8;
                        else if((addr >= apb_s9_baseaddr) & (addr < (apb_s9_baseaddr + apb_s9_range)))
                            apb_muxsel_w = 4'd9;
                        else
                            apb_muxsel_w = 4'd10;
                    end
                end
                12:
                begin
                    always @(*)
                    begin
                        if((addr >= apb_s0_baseaddr) & (addr < (apb_s0_baseaddr + apb_s0_range)))
                            apb_muxsel_w = 4'd0;
                        else if((addr >= apb_s1_baseaddr) & (addr < (apb_s1_baseaddr + apb_s1_range)))
                            apb_muxsel_w = 4'd1;
                        else if((addr >= apb_s2_baseaddr) & (addr < (apb_s2_baseaddr + apb_s2_range)))
                            apb_muxsel_w = 4'd2;
                        else if((addr >= apb_s3_baseaddr) & (addr < (apb_s3_baseaddr + apb_s3_range)))
                            apb_muxsel_w = 4'd3;
                        else if((addr >= apb_s4_baseaddr) & (addr < (apb_s4_baseaddr + apb_s4_range)))
                            apb_muxsel_w = 4'd4;
                        else if((addr >= apb_s5_baseaddr) & (addr < (apb_s5_baseaddr + apb_s5_range)))
                            apb_muxsel_w = 4'd5;
                        else if((addr >= apb_s6_baseaddr) & (addr < (apb_s6_baseaddr + apb_s6_range)))
                            apb_muxsel_w = 4'd6;
                        else if((addr >= apb_s7_baseaddr) & (addr < (apb_s7_baseaddr + apb_s7_range)))
                            apb_muxsel_w = 4'd7;
                        else if((addr >= apb_s8_baseaddr) & (addr < (apb_s8_baseaddr + apb_s8_range)))
                            apb_muxsel_w = 4'd8;
                        else if((addr >= apb_s9_baseaddr) & (addr < (apb_s9_baseaddr + apb_s9_range)))
                            apb_muxsel_w = 4'd9;
                        else if((addr >= apb_s10_baseaddr) & (addr < (apb_s10_baseaddr + apb_s10_range)))
                            apb_muxsel_w = 4'd10;
                        else
                            apb_muxsel_w = 4'd11;
                    end
                end
                13:
                begin
                    always @(*)
                    begin
                        if((addr >= apb_s0_baseaddr) & (addr < (apb_s0_baseaddr + apb_s0_range)))
                            apb_muxsel_w = 4'd0;
                        else if((addr >= apb_s1_baseaddr) & (addr < (apb_s1_baseaddr + apb_s1_range)))
                            apb_muxsel_w = 4'd1;
                        else if((addr >= apb_s2_baseaddr) & (addr < (apb_s2_baseaddr + apb_s2_range)))
                            apb_muxsel_w = 4'd2;
                        else if((addr >= apb_s3_baseaddr) & (addr < (apb_s3_baseaddr + apb_s3_range)))
                            apb_muxsel_w = 4'd3;
                        else if((addr >= apb_s4_baseaddr) & (addr < (apb_s4_baseaddr + apb_s4_range)))
                            apb_muxsel_w = 4'd4;
                        else if((addr >= apb_s5_baseaddr) & (addr < (apb_s5_baseaddr + apb_s5_range)))
                            apb_muxsel_w = 4'd5;
                        else if((addr >= apb_s6_baseaddr) & (addr < (apb_s6_baseaddr + apb_s6_range)))
                            apb_muxsel_w = 4'd6;
                        else if((addr >= apb_s7_baseaddr) & (addr < (apb_s7_baseaddr + apb_s7_range)))
                            apb_muxsel_w = 4'd7;
                        else if((addr >= apb_s8_baseaddr) & (addr < (apb_s8_baseaddr + apb_s8_range)))
                            apb_muxsel_w = 4'd8;
                        else if((addr >= apb_s9_baseaddr) & (addr < (apb_s9_baseaddr + apb_s9_range)))
                            apb_muxsel_w = 4'd9;
                        else if((addr >= apb_s10_baseaddr) & (addr < (apb_s10_baseaddr + apb_s10_range)))
                            apb_muxsel_w = 4'd10;
                        else if((addr >= apb_s11_baseaddr) & (addr < (apb_s11_baseaddr + apb_s11_range)))
                            apb_muxsel_w = 4'd11;
                        else
                            apb_muxsel_w = 4'd12;
                    end
                end
                14:
                begin
                    always @(*)
                    begin
                        if((addr >= apb_s0_baseaddr) & (addr < (apb_s0_baseaddr + apb_s0_range)))
                            apb_muxsel_w = 4'd0;
                        else if((addr >= apb_s1_baseaddr) & (addr < (apb_s1_baseaddr + apb_s1_range)))
                            apb_muxsel_w = 4'd1;
                        else if((addr >= apb_s2_baseaddr) & (addr < (apb_s2_baseaddr + apb_s2_range)))
                            apb_muxsel_w = 4'd2;
                        else if((addr >= apb_s3_baseaddr) & (addr < (apb_s3_baseaddr + apb_s3_range)))
                            apb_muxsel_w = 4'd3;
                        else if((addr >= apb_s4_baseaddr) & (addr < (apb_s4_baseaddr + apb_s4_range)))
                            apb_muxsel_w = 4'd4;
                        else if((addr >= apb_s5_baseaddr) & (addr < (apb_s5_baseaddr + apb_s5_range)))
                            apb_muxsel_w = 4'd5;
                        else if((addr >= apb_s6_baseaddr) & (addr < (apb_s6_baseaddr + apb_s6_range)))
                            apb_muxsel_w = 4'd6;
                        else if((addr >= apb_s7_baseaddr) & (addr < (apb_s7_baseaddr + apb_s7_range)))
                            apb_muxsel_w = 4'd7;
                        else if((addr >= apb_s8_baseaddr) & (addr < (apb_s8_baseaddr + apb_s8_range)))
                            apb_muxsel_w = 4'd8;
                        else if((addr >= apb_s9_baseaddr) & (addr < (apb_s9_baseaddr + apb_s9_range)))
                            apb_muxsel_w = 4'd9;
                        else if((addr >= apb_s10_baseaddr) & (addr < (apb_s10_baseaddr + apb_s10_range)))
                            apb_muxsel_w = 4'd10;
                        else if((addr >= apb_s11_baseaddr) & (addr < (apb_s11_baseaddr + apb_s11_range)))
                            apb_muxsel_w = 4'd11;
                        else if((addr >= apb_s12_baseaddr) & (addr < (apb_s12_baseaddr + apb_s12_range)))
                            apb_muxsel_w = 4'd12;
                        else
                            apb_muxsel_w = 4'd13;
                    end
                end
                15:
                begin
                    always @(*)
                    begin
                        if((addr >= apb_s0_baseaddr) & (addr < (apb_s0_baseaddr + apb_s0_range)))
                            apb_muxsel_w = 4'd0;
                        else if((addr >= apb_s1_baseaddr) & (addr < (apb_s1_baseaddr + apb_s1_range)))
                            apb_muxsel_w = 4'd1;
                        else if((addr >= apb_s2_baseaddr) & (addr < (apb_s2_baseaddr + apb_s2_range)))
                            apb_muxsel_w = 4'd2;
                        else if((addr >= apb_s3_baseaddr) & (addr < (apb_s3_baseaddr + apb_s3_range)))
                            apb_muxsel_w = 4'd3;
                        else if((addr >= apb_s4_baseaddr) & (addr < (apb_s4_baseaddr + apb_s4_range)))
                            apb_muxsel_w = 4'd4;
                        else if((addr >= apb_s5_baseaddr) & (addr < (apb_s5_baseaddr + apb_s5_range)))
                            apb_muxsel_w = 4'd5;
                        else if((addr >= apb_s6_baseaddr) & (addr < (apb_s6_baseaddr + apb_s6_range)))
                            apb_muxsel_w = 4'd6;
                        else if((addr >= apb_s7_baseaddr) & (addr < (apb_s7_baseaddr + apb_s7_range)))
                            apb_muxsel_w = 4'd7;
                        else if((addr >= apb_s8_baseaddr) & (addr < (apb_s8_baseaddr + apb_s8_range)))
                            apb_muxsel_w = 4'd8;
                        else if((addr >= apb_s9_baseaddr) & (addr < (apb_s9_baseaddr + apb_s9_range)))
                            apb_muxsel_w = 4'd9;
                        else if((addr >= apb_s10_baseaddr) & (addr < (apb_s10_baseaddr + apb_s10_range)))
                            apb_muxsel_w = 4'd10;
                        else if((addr >= apb_s11_baseaddr) & (addr < (apb_s11_baseaddr + apb_s11_range)))
                            apb_muxsel_w = 4'd11;
                        else if((addr >= apb_s12_baseaddr) & (addr < (apb_s12_baseaddr + apb_s12_range)))
                            apb_muxsel_w = 4'd12;
                        else if((addr >= apb_s13_baseaddr) & (addr < (apb_s13_baseaddr + apb_s13_range)))
                            apb_muxsel_w = 4'd13;
                        else
                            apb_muxsel_w = 4'd14;
                    end
                end
                16:
                begin
                    always @(*)
                    begin
                        if((addr >= apb_s0_baseaddr) & (addr < (apb_s0_baseaddr + apb_s0_range)))
                            apb_muxsel_w = 4'd0;
                        else if((addr >= apb_s1_baseaddr) & (addr < (apb_s1_baseaddr + apb_s1_range)))
                            apb_muxsel_w = 4'd1;
                        else if((addr >= apb_s2_baseaddr) & (addr < (apb_s2_baseaddr + apb_s2_range)))
                            apb_muxsel_w = 4'd2;
                        else if((addr >= apb_s3_baseaddr) & (addr < (apb_s3_baseaddr + apb_s3_range)))
                            apb_muxsel_w = 4'd3;
                        else if((addr >= apb_s4_baseaddr) & (addr < (apb_s4_baseaddr + apb_s4_range)))
                            apb_muxsel_w = 4'd4;
                        else if((addr >= apb_s5_baseaddr) & (addr < (apb_s5_baseaddr + apb_s5_range)))
                            apb_muxsel_w = 4'd5;
                        else if((addr >= apb_s6_baseaddr) & (addr < (apb_s6_baseaddr + apb_s6_range)))
                            apb_muxsel_w = 4'd6;
                        else if((addr >= apb_s7_baseaddr) & (addr < (apb_s7_baseaddr + apb_s7_range)))
                            apb_muxsel_w = 4'd7;
                        else if((addr >= apb_s8_baseaddr) & (addr < (apb_s8_baseaddr + apb_s8_range)))
                            apb_muxsel_w = 4'd8;
                        else if((addr >= apb_s9_baseaddr) & (addr < (apb_s9_baseaddr + apb_s9_range)))
                            apb_muxsel_w = 4'd9;
                        else if((addr >= apb_s10_baseaddr) & (addr < (apb_s10_baseaddr + apb_s10_range)))
                            apb_muxsel_w = 4'd10;
                        else if((addr >= apb_s11_baseaddr) & (addr < (apb_s11_baseaddr + apb_s11_range)))
                            apb_muxsel_w = 4'd11;
                        else if((addr >= apb_s12_baseaddr) & (addr < (apb_s12_baseaddr + apb_s12_range)))
                            apb_muxsel_w = 4'd12;
                        else if((addr >= apb_s13_baseaddr) & (addr < (apb_s13_baseaddr + apb_s13_range)))
                            apb_muxsel_w = 4'd13;
                        else if((addr >= apb_s14_baseaddr) & (addr < (apb_s14_baseaddr + apb_s14_range)))
                            apb_muxsel_w = 4'd14;
                        else
                            apb_muxsel_w = 4'd15;
                    end
                end
            endcase
        end
    endgenerate

endmodule
