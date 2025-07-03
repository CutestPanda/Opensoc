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
本模块: UART接收控制器

描述: 
符合AXIS协议的UART接收控制器

注意：
UART接收可能溢出

协议:
AXIS MASTER
UART

作者: 陈家耀
日期: 2023/11/08
********************************************************************/


module uart_rx #(
    parameter integer clk_frequency = 200000000, // 时钟频率
    parameter integer baud_rate = 115200, // 波特率
    parameter real simulation_delay = 1 // 仿真延时
)(
    input wire clk,
    input wire rst_n,
    
    input wire rx,
    
    output wire[7:0] rx_byte_data,
    output wire rx_byte_valid,
    input wire rx_byte_ready,
    
    output wire rx_idle,
    output wire rx_done,
    output wire rx_start
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

    localparam integer clk_n_per_bit = clk_frequency / baud_rate; // 传输每一位所用的时钟周期个数
    
    /** 打两拍消除亚稳态 **/
    reg rx_d;
    reg rx_d2;
    wire rx_stable;
    
    assign rx_stable = rx_d2;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            {rx_d2, rx_d} <= 2'b11;
        else
            # simulation_delay {rx_d2, rx_d} <= {rx_d, rx};
    end
    
    /** 检测下降沿 **/
    reg rx_stable_d;
    reg rx_neg_edge_detected; // 检测到下降沿(脉冲)
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rx_stable_d <= 1'b1;
        else
            # simulation_delay rx_stable_d <= rx_stable;
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rx_neg_edge_detected <= 1'b0;
        else
            # simulation_delay rx_neg_edge_detected <= (~rx_stable) & rx_stable_d;
    end
    
    /** 数据接收状态机 **/
    localparam status_idle = 2'b00; // 状态:空闲
    localparam status_start = 2'b01; // 状态:起始位
    localparam status_data = 2'b10; // 状态:数据位
    localparam status_stop = 2'b11; // 状态:停止位
    
    reg[1:0] now_status;
    
    reg[clogb2(clk_n_per_bit-1):0] cnt; // 波特率计数器
    reg[2:0] now_bit_i; // 当前接收字节位编号
    reg[7:0] byte; // 当前接收的字节
    reg byte_vld; // 接收字节完成(脉冲)
    reg rx_idle_reg; // UART控制器接收空闲(标志)
    
    reg cnt_eq_clk_n_per_bit_div2_sub1; // 波特率计数器 == UART位时钟周期 / 2 - 1(脉冲)
    reg cnt_eq_clk_n_per_bit_sub1; // 波特率计数器 == UART位时钟周期 - 1(脉冲)
    
    assign rx_byte_data = byte;
    assign rx_byte_valid = byte_vld;
    assign rx_idle = rx_idle_reg;
    assign rx_done = byte_vld;
    assign rx_start = rx_neg_edge_detected;
    
    // 波特率计数器比较结果指示
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
        begin
            cnt_eq_clk_n_per_bit_div2_sub1 <= 1'b0;
            cnt_eq_clk_n_per_bit_sub1 <= 1'b0;
        end
        else
        begin
            # simulation_delay;
            
            cnt_eq_clk_n_per_bit_div2_sub1 <= (cnt == clk_n_per_bit / 2 - 2);
            cnt_eq_clk_n_per_bit_sub1 <= (cnt == clk_n_per_bit - 2);
        end
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
        begin
            now_status <= status_idle;
            cnt <= 0;
            now_bit_i <= 3'b000;
            byte_vld <= 1'b0;
            rx_idle_reg <= 1'b1;
        end
        else
        begin
            # simulation_delay;
            
            byte_vld <= 1'b0;
            case(now_status)
                status_idle: // 状态:空闲
                begin
                    rx_idle_reg <= rx_idle_reg | cnt_eq_clk_n_per_bit_div2_sub1; // 为了跳过上一次传输的停止位, idle信号只能在波特率计数器 == UART位时钟周期 / 2 - 1时置为有效
                    
                    if(rx_neg_edge_detected) // 检测到开始位
                    begin
                        now_status <= status_start;
                        cnt <= 0;
                    end
                    else
                    begin
                        now_status <= status_idle;
                        cnt <= cnt + 1;
                    end
                end
                status_start: // 状态:起始位
                begin
                    rx_idle_reg <= 1'b0;
                    
                    if(cnt_eq_clk_n_per_bit_div2_sub1) // 对齐到起始位中央再继续接收
                    begin
                        now_status <= status_data;
                        cnt <= 0;
                    end
                    else
                    begin
                        now_status <= status_start;
                        cnt <= cnt + 1;
                    end
                end
                status_data: // 状态:数据位
                begin
                    rx_idle_reg <= 1'b0;
                    
                    if(cnt_eq_clk_n_per_bit_sub1) // 接收UART数据位
                    begin
                        cnt <= 0;
                        now_bit_i <= now_bit_i + 3'b001;
                        
                        if(now_bit_i == 3'b111)
                            now_status <= status_stop;
                        else
                            now_status <= status_data;
                    end
                    else
                    begin
                        now_status <= status_data;
                        cnt <= cnt + 1;
                    end
                end
                status_stop: // 状态:停止位
                begin
                    rx_idle_reg <= 1'b0;
                    
                    if(cnt_eq_clk_n_per_bit_sub1) // 此时对齐到停止位的中央
                    begin
                        now_status <= status_idle;
                        cnt <= 0;
                        byte_vld <= 1'b1;
                    end
                    else
                    begin
                        now_status <= status_stop;
                        cnt <= cnt + 1;
                    end
                end
                default:
                begin
                    now_status <= status_idle;
                    cnt <= 0;
                    now_bit_i <= 3'b000;
                    rx_idle_reg <= 1'b1;
                end
            endcase
        end
    end
    
    // 当前接收的字节
    always @(posedge clk)
    begin
        # simulation_delay;
        
        if(now_status == status_data)
        begin
            case(now_bit_i)
                3'b000: byte[0] <= rx_stable;
                3'b001: byte[1] <= rx_stable;
                3'b010: byte[2] <= rx_stable;
                3'b011: byte[3] <= rx_stable;
                3'b100: byte[4] <= rx_stable;
                3'b101: byte[5] <= rx_stable;
                3'b110: byte[6] <= rx_stable;
                3'b111: byte[7] <= rx_stable;
            endcase
        end
    end

endmodule
