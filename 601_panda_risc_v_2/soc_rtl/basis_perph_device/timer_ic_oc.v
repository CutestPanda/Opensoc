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
本模块: 通用定时器的输入捕获/输出比较通道

描述: 
输入捕获/输出比较

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/06/10
********************************************************************/


module timer_ic_oc #(
    parameter integer timer_width = 16, // 定时器位宽(8~32)
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire resetn,
    
    // 捕获/比较
    input wire cap_in, // 捕获输入
    output wire cmp_out, // 比较输出
    
    // 定时器计数值
    input wire[timer_width-1:0] timer_cnt_now_v,
    // 是否启动定时器
    input wire timer_started,
    
    // 定时器计数溢出(指示)
    input wire timer_expired,
    
    // 捕获/比较选择
    // 1'b0 -> 捕获, 1'b1 -> 比较
    input wire cap_cmp_sel,
    // 捕获/比较值
    input wire[timer_width-1:0] timer_cmp,
    output wire[timer_width-1:0] timer_cap_cmp_o,
    
    // 输入滤波阈值
    input wire[7:0] timer_cap_filter_th,
    // 边沿检测类型
    // 2'b00 -> 上升沿, 2'b01 -> 下降沿, 2'b10 -> 上升/下降沿, 2'b11 -> 保留
    input wire[1:0] timer_cap_edge,
    
    // 输入捕获中断请求
    output wire timer_cap_itr_req
);

    /** 常量 **/
    // 输入捕获边沿类型
    localparam IN_CAP_EDGE_POS = 2'b00; // 边沿类型:上升沿
    localparam IN_CAP_EDGE_NEG = 2'b01; // 边沿类型:下降沿
    localparam IN_CAP_EDGE_BOTH = 2'b10; // 边沿类型:上升/下降沿
    // 输入捕获状态常量
    localparam IN_CAP_STS_IDLE = 2'b00; // 状态:空闲
    localparam IN_CAP_STS_DELAY = 2'b01; // 状态:延迟
    localparam IN_CAP_STS_COMFIRM = 2'b10; // 状态:确认
    localparam IN_CAP_STS_CAP = 2'b11; // 状态:捕获
    
    /** 捕获/比较寄存器 **/
    wire to_in_cap; // 输入捕获(指示)
    reg to_in_cap_d; // 延迟1clk的输入捕获(指示)
    reg[timer_width-1:0] timer_cap_v_latched; // 锁存的捕获值
    reg[timer_width-1:0] timer_cap_cmp; // 捕获/比较寄存器
    
    assign timer_cap_cmp_o = timer_cap_cmp;
    assign timer_cap_itr_req = to_in_cap_d;
    
    // 捕获/比较寄存器
    // 如果当前模式是比较模式, 则保证捕获/比较寄存器仅在定时器未启动或定时器计数溢出时载入设置值!
    always @(posedge clk)
    begin
        if(cap_cmp_sel ? ((~timer_started) | timer_expired):to_in_cap)
            # simulation_delay timer_cap_cmp <= cap_cmp_sel ? timer_cmp:timer_cap_v_latched;
    end
    
    // 延迟1clk的输入捕获(指示)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            to_in_cap_d <= 1'b0;
        else
            # simulation_delay to_in_cap_d <= to_in_cap;
    end
    
    /** 输入捕获 **/
    reg[2:0] cap_in_d1_to_d3; // 延迟1~3clk的捕获输入
    wire cap_in_posedge_detected; // 捕获输入检测到上升沿
    wire cap_in_negedge_detected; // 捕获输入检测到下降沿
    wire cap_vld_edge; // 检测到有效边沿(指示)
    reg cap_in_edge_type_latched; // 锁存的捕获输入边沿类型(1'b0 -> 下降沿, 1'b1 -> 上升沿)
    reg[7:0] cap_in_filter_th_latched; // 锁存的输入滤波阈值
    reg[7:0] cap_in_filter_cnt; // 输入滤波计数器
    wire cap_in_filter_done; // 输入滤波完成(指示)
    reg[1:0] in_cap_sts; // 输入捕获状态
    
    assign to_in_cap = in_cap_sts == IN_CAP_STS_CAP;
    
    assign cap_in_posedge_detected = cap_in_d1_to_d3[1] & (~cap_in_d1_to_d3[2]);
    assign cap_in_negedge_detected = (~cap_in_d1_to_d3[1]) & cap_in_d1_to_d3[2];
    assign cap_vld_edge = (((timer_cap_edge == IN_CAP_EDGE_POS) & cap_in_posedge_detected) |
        ((timer_cap_edge == IN_CAP_EDGE_NEG) & cap_in_negedge_detected) |
        ((timer_cap_edge == IN_CAP_EDGE_BOTH) & (cap_in_posedge_detected | cap_in_negedge_detected)))
            & timer_started & (~cap_cmp_sel);
    assign cap_in_filter_done = cap_in_filter_cnt == cap_in_filter_th_latched;
    
    // 延迟1~3clk的捕获输入
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            cap_in_d1_to_d3 <= 3'b000;
        else
            # simulation_delay cap_in_d1_to_d3 <= {cap_in_d1_to_d3[1:0], cap_in};
    end
    
    // 锁存的捕获值
    always @(posedge clk)
    begin
        if((in_cap_sts == IN_CAP_STS_IDLE) & cap_vld_edge)
            # simulation_delay timer_cap_v_latched <= timer_cnt_now_v;
    end
    // 锁存的捕获输入边沿类型
    always @(posedge clk)
    begin
        if((in_cap_sts == IN_CAP_STS_IDLE) & cap_vld_edge)
            # simulation_delay cap_in_edge_type_latched <= cap_in_posedge_detected;
    end
    // 锁存的输入滤波阈值
    always @(posedge clk)
    begin
        if((in_cap_sts == IN_CAP_STS_IDLE) & cap_vld_edge)
            # simulation_delay cap_in_filter_th_latched <= timer_cap_filter_th;
    end
    
    // 输入滤波计数器
    always @(posedge clk)
    begin
        if(in_cap_sts == IN_CAP_STS_IDLE)
            # simulation_delay cap_in_filter_cnt <= 8'd0;
        else if(in_cap_sts == IN_CAP_STS_DELAY)
            # simulation_delay cap_in_filter_cnt <= cap_in_filter_cnt + 8'd1;
    end
    
    // 输入捕获状态
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            in_cap_sts <= IN_CAP_STS_IDLE;
        else
        begin
            # simulation_delay;
            
            case(in_cap_sts)
                IN_CAP_STS_IDLE: // 状态:空闲
                    if(cap_vld_edge)
                        in_cap_sts <= IN_CAP_STS_DELAY; // -> 状态:延迟
                IN_CAP_STS_DELAY: // 状态:延迟
                    if(cap_in_filter_done)
                        in_cap_sts <= IN_CAP_STS_COMFIRM; // -> 状态:确认
                IN_CAP_STS_COMFIRM: // 状态:确认
                    if(cap_in_d1_to_d3[1] == cap_in_edge_type_latched)
                        in_cap_sts <= IN_CAP_STS_CAP; // -> 状态:捕获
                    else
                        in_cap_sts <= IN_CAP_STS_IDLE; // -> 状态:空闲
                IN_CAP_STS_CAP: // 状态:捕获
                    in_cap_sts <= IN_CAP_STS_IDLE; // -> 状态:空闲
                default:
                    in_cap_sts <= IN_CAP_STS_IDLE;
            endcase
        end
    end
    
    /** 输出比较 **/
    wire cmp_o; // 输出比较值
    reg cmp_o_d; // 延迟1clk的输出比较值
    
    assign cmp_out = cmp_o_d;
    
    assign cmp_o = timer_started & cap_cmp_sel & (timer_cnt_now_v >= timer_cap_cmp);
    
    // 延迟1clk的输出比较值
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            cmp_o_d <= 1'b0;
        else
            # simulation_delay cmp_o_d <= cmp_o;
    end
    
endmodule
