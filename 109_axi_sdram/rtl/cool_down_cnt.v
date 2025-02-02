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
本模块: 冷却计数器

描述:
就绪 -> 触发 -> 冷却 -> 就绪 -> ...

注意：
冷却量仅在计数器就绪或者回零时采样
冷却量是指从触发到下一次就绪经过的时钟周期数

协议:
无

作者: 陈家耀
日期: 2024/04/13
********************************************************************/


module cool_down_cnt #(
    parameter integer max_cd = 20000 // 冷却量的最大值
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 运行时参数
    input wire[clogb2(max_cd-1):0] cd, // 冷却量 - 1
    
    // 计数器控制/状态
    input wire timer_trigger, // 触发
    output wire timer_done, // 完成
    output wire timer_ready, // 就绪
    output wire[clogb2(max_cd-1):0] timer_v // 当前计数值
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
    
    /** 冷却计数器 **/
    reg[clogb2(max_cd-1):0] cd_cnt; // 冷却计数值
    reg timer_ready_reg; // 计数器就绪
    
    assign timer_done = timer_ready ? (timer_trigger & cd == 0):(cd_cnt == 1);
    assign timer_ready = timer_ready_reg;
    assign timer_v = cd_cnt;
    
    // 冷却计数值
    always @(posedge clk)
    begin
        if(timer_ready | (cd_cnt == 0))
            cd_cnt <= cd;
        else if((~timer_ready) | timer_trigger)
            cd_cnt <= cd_cnt - 1;
    end
    
    // 计数器就绪
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            timer_ready_reg <= 1'b1;
        else
            timer_ready_reg <= timer_ready_reg ? (~(timer_trigger & (cd != 0))):(cd_cnt == 1);
    end

endmodule
