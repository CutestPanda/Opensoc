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
本模块: Round-Robin仲裁器

描述: 
基于Round-Robin算法的0时延仲裁器

注意：
无

协议:
ARB SLAVE

作者: 陈家耀
日期: 2024/04/28
********************************************************************/


module round_robin_arbitrator #(
    parameter integer chn_n = 4, // 通道个数(必须>=2)
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 仲裁器
    input wire[chn_n-1:0] req, // 请求
    output wire[chn_n-1:0] grant, // 授权(独热码)
    output wire[clogb2(chn_n-1):0] sel, // 选择(相当于授权的二进制表示)
    output wire arb_valid // 仲裁结果有效
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
    // 独热码 -> 二进制码
    function [clogb2(chn_n-1):0] onehot_to_bin(input[chn_n-1:0] onehot);
        integer i;
    begin
        onehot_to_bin = 0;
        
        for(i = 0;i < chn_n;i = i + 1)
        begin
            if(onehot[i])
                onehot_to_bin = i;
        end
    end
    endfunction

    /** 仲裁优先级 **/
    reg[chn_n-1:0] priority_cnt; // 优先级独热码计数器
    
    // 优先级独热码计数器
    // 1的位置表征最高优先级的通道
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            priority_cnt <= {{(chn_n-1){1'b0}}, 1'b1};
        else if(|req) // 当前有请求
            # simulation_delay priority_cnt <= {grant[chn_n-2:0], grant[chn_n-1]};
    end
    
    /** 仲裁授权与选择 **/
    wire[chn_n*2-1:0] double_req;
    wire[chn_n*2-1:0] double_grant;
    
    assign double_req = {req, req};
    assign double_grant = double_req & (~(double_req - priority_cnt));
    
    assign grant = double_grant[chn_n-1:0] | double_grant[chn_n*2-1:chn_n];
    assign sel = onehot_to_bin(grant);
    assign arb_valid = |req;
    
endmodule
