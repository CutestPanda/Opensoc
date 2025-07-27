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
本模块: 基本定时器

描述: 
带预分频和自动装载功能
8~32位基本定时器

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/06/10
********************************************************************/


module basic_timer #(
    parameter integer timer_width = 16, // 定时器位宽(8~32)
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire resetn,
    
    // 预分频系数 - 1
    input wire[timer_width-1:0] prescale,
    // 自动装载值 - 1
    input wire[timer_width-1:0] autoload,
    
    // 定时器计数值
    input wire timer_cnt_to_set,
    input wire[timer_width-1:0] timer_cnt_set_v,
    output wire[timer_width-1:0] timer_cnt_now_v,
    
    // 是否启动定时器
    input wire timer_started,
    
    // 定时器计数溢出(指示)
    output wire timer_expired,
    
    // 计数溢出中断请求
    output wire timer_expired_itr_req
);
    
    /** 预分频计数器 **/
    reg[timer_width-1:0] prescale_shadow; // 预分频系数 - 1(影子寄存器)
    wire prescale_cnt_rst; // 预分频计数器(回零指示)
    reg[timer_width-1:0] prescale_cnt; // 预分频计数器
    
    assign prescale_cnt_rst = prescale_cnt == prescale_shadow;
    
    // 预分频系数 - 1(影子寄存器)
    always @(posedge clk)
    begin
        if((~timer_started) | prescale_cnt_rst)
            prescale_shadow <= # simulation_delay prescale;
    end
    
    // 预分频计数器
    always @(posedge clk)
    begin
        if(~timer_started)
            prescale_cnt <= # simulation_delay 0;
        else
            prescale_cnt <= # simulation_delay prescale_cnt_rst ? 0:(prescale_cnt + 1);
    end
    
    /** 定时计数器 **/
    reg[timer_width-1:0] timer_cnt; // 定时计数器
    reg timer_expired_d; // 延迟1clk的定时器计数溢出(指示)
    
    assign timer_cnt_now_v = timer_cnt;
    assign timer_expired = timer_started & prescale_cnt_rst & (timer_cnt == 0);
    
    assign timer_expired_itr_req = timer_expired_d;
    
    // 定时计数器
    always @(posedge clk)
    begin
        if(timer_cnt_to_set)
            timer_cnt <= # simulation_delay timer_cnt_set_v;
        else if(timer_started & prescale_cnt_rst)
            timer_cnt <= # simulation_delay (timer_cnt == 0) ? autoload:(timer_cnt - 1);
    end
    
    // 延迟1clk的定时器计数溢出(指示)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            timer_expired_d <= 1'b0;
        else
            timer_expired_d <= # simulation_delay timer_expired;
    end
    
endmodule
