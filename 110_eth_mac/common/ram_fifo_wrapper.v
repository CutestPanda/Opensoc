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
本模块: 基于lutram或bram的同步fifo

描述: 
全流水的高性能同步fifo
基于lutram或bram
支持first word fall through特性(READ LA = 0)
可选的固定阈值将满/将空信号
可选的存储计数输出

注意：
将满信号当存储计数 >= almost_full_th时有效
将空信号当存储计数 <= almost_empty_th时有效
almost_full_th和almost_empty_th必须在[1, fifo_depth-1]范围内
本模块用于fpga, 子模块fifo_based_on_ram可用于asic设计
寄存器fifo请用子模块fifo_based_on_regs

协议:
FIFO WRITE/READ

作者: 陈家耀
日期: 2023/10/29
********************************************************************/


module ram_fifo_wrapper #(
    parameter fwft_mode = "true", // 是否启用first word fall through特性
    parameter ram_type = "lutram", // RAM类型(lutram|bram)
    parameter en_bram_reg = "false", // 是否启用BRAM输出寄存器
    parameter integer fifo_depth = 32, // fifo深度(必须为2|4|8|16|...)
    parameter integer fifo_data_width = 32, // fifo位宽
    parameter full_assert_polarity = "low", // 满信号有效极性(low|high)
    parameter empty_assert_polarity = "low", // 空信号有效极性(low|high)
    parameter almost_full_assert_polarity = "no", // 将满信号有效极性(low|high|no)
    parameter almost_empty_assert_polarity = "no", // 将空信号有效极性(low|high|no)
    parameter en_data_cnt = "false", // 是否启用存储计数器
    parameter integer almost_full_th = 20, // fifo将满阈值
    parameter integer almost_empty_th = 5, // fifo将空阈值
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // FIFO WRITE(fifo写端口)
    input wire fifo_wen,
    input wire[fifo_data_width-1:0] fifo_din,
    output wire fifo_full,
    output wire fifo_full_n,
    output wire fifo_almost_full,
    output wire fifo_almost_full_n,
    
    // FIFO READ(fifo读端口)
    input wire fifo_ren,
    output wire[fifo_data_width-1:0] fifo_dout,
    output wire fifo_empty,
    output wire fifo_empty_n,
    output wire fifo_almost_empty,
    output wire fifo_almost_empty_n,
    
    // 存储计数
    output wire[clogb2(fifo_depth):0] data_cnt
);

    // 计算log2(bit_depth)               
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
