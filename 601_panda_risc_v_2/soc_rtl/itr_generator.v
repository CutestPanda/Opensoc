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
本模块: 中断信号发生器

描述: 
将原始的中断脉冲拓展为一定脉宽的中断信号

注意：
中断脉宽必须 >= 2

协议:
无

作者: 陈家耀
日期: 2023/11/08
********************************************************************/


module itr_generator #(
    parameter integer pulse_w = 100, // 中断脉宽(必须>=1)
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    input wire itr_org, // 原始中断输入
    output wire itr // 中断输出
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
    
    // 产生中断信号
    reg itr_reg; // 中断信号
    reg[clogb2(pulse_w - 1):0] itr_cnt; // 中断计数器
    
    assign itr = itr_reg;
    
    generate
        if(pulse_w == 1)
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    itr_reg <= 1'b0;
                else
                    # simulation_delay itr_reg <= itr_org;
            end
        end
        else
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    itr_reg <= 1'b0;
                else
                begin
                    # simulation_delay;
                    
                    if(~itr_reg) // 等待原始中断脉冲
                        itr_reg <= itr_org;
                    else // 等待计数完成
                        itr_reg <= itr_cnt != pulse_w - 1;
                end
            end
        end
    endgenerate
    
    always @(posedge clk)
        # simulation_delay itr_cnt <= (~itr_reg) ? 0:(itr_cnt + 1);

endmodule
