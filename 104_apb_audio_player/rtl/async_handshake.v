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
本模块: 基于握手的跨时钟域同步器

描述: 
              req -> req_d2
              |        |
ack    ->   ack_d2     |
 |---------------------

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/03/07
********************************************************************/


module async_handshake #(
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位1
    input wire clk1,
    input wire rst_n1,
    // 时钟和复位2
    input wire clk2,
    input wire rst_n2,
    
    // 时钟域1
    input wire req1, // 数据传输请求(指示)
    output wire busy, // 正在进行数据传输(标志)
    // 时钟域2
    output wire req2 // 数据传输请求(指示)
);
    
    /** 时钟域1 **/
    reg req; // 数据传输请求
    reg busy_reg; // 正在进行数据传输(标志)
    wire ack_w;
    reg ack_d;
    reg ack_d2;
    reg ack_d3;
    wire ack_neg_edge; // ack信号出现下降沿(指示)
    
    assign busy = busy_reg;
    
    assign ack_neg_edge = ack_d3 & (~ack_d2);
    
    // 数据传输请求
    always @(posedge clk1 or negedge rst_n1)
    begin
        if(~rst_n1)
            req <= 1'b0;
        else
            # simulation_delay req <= req ? (~ack_d2):(req1 & (~busy_reg));
    end
    // 正在进行数据传输(标志)
    always @(posedge clk1 or negedge rst_n1)
    begin
        if(~rst_n1)
            busy_reg <= 1'b0;
        else
            # simulation_delay busy_reg <= busy_reg ? (~ack_neg_edge):req1;
    end
    
    // 对来自时钟域2的ack信号打2拍
    always @(posedge clk1 or negedge rst_n1)
    begin
        if(~rst_n1)
            {ack_d2, ack_d} <= 2'b00;
        else
            # simulation_delay {ack_d2, ack_d} <= {ack_d, ack_w};
    end
    // 对同步到时钟域1的ack信号打1拍
    always @(posedge clk1 or negedge rst_n1)
    begin
        if(~rst_n1)
            ack_d3 <= 1'b0;
        else
            # simulation_delay ack_d3 <= ack_d2;
    end
    
    /** 时钟域2 **/
    reg ack; // 数据传输应答
    reg req_d;
    reg req_d2;
    reg req_d3;
    
    assign req2 = (~req_d3) & req_d2;
    
    assign ack_w = ack;
    
    // 数据传输应答
    always @(posedge clk2 or negedge rst_n2)
    begin
        if(~rst_n2)
            ack <= 1'b0;
        else
            # simulation_delay ack <= req_d2;
    end
    
    // 对来自时钟域1的req信号打2拍
    always @(posedge clk2 or negedge rst_n2)
    begin
        if(~rst_n2)
            {req_d2, req_d} <= 2'b00;
        else
            # simulation_delay {req_d2, req_d} <= {req_d, req};
    end
    // 对同步到时钟域2的req信号打1拍
    always @(posedge clk2 or negedge rst_n2)
    begin
        if(~rst_n2)
            req_d3 <= 1'b0;
        else
            # simulation_delay req_d3 <= req_d2;
    end

endmodule
