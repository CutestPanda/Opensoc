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
本模块: 基于ram的同步fifo控制器

描述: 
全流水的高性能同步fifo控制器
基于ram
支持first word fall through特性(READ LA = 0)
可选的固定阈值将满/将空信号

注意：
将满信号当存储计数 >= almost_full_th时有效
将空信号当存储计数 <= almost_empty_th时有效
almost_full_th和almost_empty_th必须在[1, fifo_depth-1]范围内
不使能FWFT时, 要求ram的读延迟=1或2clk; 使能FWFT时, 要求ram的读延迟=1clk

协议:
FIFO WRITE/READ
MEM WRITE/READ

作者: 陈家耀
日期: 2023/10/29
********************************************************************/


module fifo_based_on_ram #(
    parameter fwft_mode = "true", // 是否启用first word fall through特性
    parameter ram_read_la = 1, // ram读延迟(1|2)(仅在不使能FWFT时可用)
    parameter integer fifo_depth = 32, // fifo深度(必须为2|4|8|16|...)
    parameter integer fifo_data_width = 32, // fifo位宽
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
    
    // MEM WRITE(ram写端口)
    output wire ram_wen,
    output wire[clogb2(fifo_depth-1):0] ram_w_addr,
    output wire[fifo_data_width-1:0] ram_din,
    
    // MEM RAD(ram读端口)
    output wire ram_ren,
    output wire[clogb2(fifo_depth-1):0] ram_r_addr,
    input wire[fifo_data_width-1:0] ram_dout,
    
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
    
    /** 主fifo **/
    wire m_fifo_ren;
    wire[fifo_data_width-1:0] m_fifo_dout;
    wire m_fifo_empty_n;
    
    generate
        if(fwft_mode == "true")
        begin
            // FWFT模式
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
            // 标准模式
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
    
    /** 从fifo(仅FWFT模式下需要) **/
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
