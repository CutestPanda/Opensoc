/*
MIT License

Copyright (c) 2024 Panda, 2257691535@qq.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

`timescale 1ns / 1ps
/********************************************************************
本模块: AHB到APB桥的地址译码器

描述: 
支持多达16个APB从机的地址译码器

注意：
每个从机的地址区间长度必须 >= 4096(4KB)

协议:
无

作者: 陈家耀
日期: 2024/04/20
********************************************************************/


module ahb_apb_bridge_dec #(
    parameter integer apb_slave_n = 4, // APB从机个数(1~16)
    parameter integer apb_s0_baseaddr = 0, // 0号从机基地址
    parameter integer apb_s0_range = 4096, // 0号从机地址区间长度
    parameter integer apb_s1_baseaddr = 4096, // 1号从机基地址
    parameter integer apb_s1_range = 4096, // 1号从机地址区间长度
    parameter integer apb_s2_baseaddr = 8192, // 2号从机基地址
    parameter integer apb_s2_range = 4096, // 2号从机地址区间长度
    parameter integer apb_s3_baseaddr = 12288, // 3号从机基地址
    parameter integer apb_s3_range = 4096, // 3号从机地址区间长度
    parameter integer apb_s4_baseaddr = 16384, // 4号从机基地址
    parameter integer apb_s4_range = 4096, // 4号从机地址区间长度
    parameter integer apb_s5_baseaddr = 20480, // 5号从机基地址
    parameter integer apb_s5_range = 4096, // 5号从机地址区间长度
    parameter integer apb_s6_baseaddr = 24576, // 6号从机基地址
    parameter integer apb_s6_range = 4096, // 6号从机地址区间长度
    parameter integer apb_s7_baseaddr = 28672, // 7号从机基地址
    parameter integer apb_s7_range = 4096, // 7号从机地址区间长度
    parameter integer apb_s8_baseaddr = 32768, // 8号从机基地址
    parameter integer apb_s8_range = 4096, // 8号从机地址区间长度
    parameter integer apb_s9_baseaddr = 36864, // 9号从机基地址
    parameter integer apb_s9_range = 4096, // 9号从机地址区间长度
    parameter integer apb_s10_baseaddr = 40960, // 10号从机基地址
    parameter integer apb_s10_range = 4096, // 10号从机地址区间长度
    parameter integer apb_s11_baseaddr = 45056, // 11号从机基地址
    parameter integer apb_s11_range = 4096, // 11号从机地址区间长度
    parameter integer apb_s12_baseaddr = 49152, // 12号从机基地址
    parameter integer apb_s12_range = 4096, // 12号从机地址区间长度
    parameter integer apb_s13_baseaddr = 53248, // 13号从机基地址
    parameter integer apb_s13_range = 4096, // 13号从机地址区间长度
    parameter integer apb_s14_baseaddr = 57344, // 14号从机基地址
    parameter integer apb_s14_range = 4096, // 14号从机地址区间长度
    parameter integer apb_s15_baseaddr = 61440, // 15号从机基地址
    parameter integer apb_s15_range = 4096 // 15号从机地址区间长度
)(
    input wire[31:0] addr,
    output wire[15:0] m_apb_psel,
    output wire[3:0] apb_muxsel
);
    
    // 独一码译码
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
    
    // 二进制码译码
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
