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
本模块: AXI读数据通道路由

描述: 
将主机的读数据通道(R)路由到给定的从机

注意：
无

协议:
FIFO READ

作者: 陈家耀
日期: 2024/04/29
********************************************************************/


module axi_rchn_router #(
    parameter integer master_n = 4, // 主机个数(必须在范围[2, 8]内)
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // AXI从机R通道的控制信号组
    output wire[7:0] s_rvalid, // 每个从机的valid
    input wire[7:0] s_rready, // 每个从机的ready
    
    // AXI主机R通道的控制信号组
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output wire m_axi_rready,
    
    // 授权主机编号fifo读端口
    output wire grant_mid_fifo_ren,
    input wire grant_mid_fifo_empty_n,
    input wire[master_n-1:0] grant_mid_fifo_dout_onehot // 独热码编号
);
    
    // 对于每个从机的R通道, 握手条件是: grant_mid_fifo_empty_n & m_axi_rvalid & grant_mid_fifo_dout_onehot[i] & s_rready[i]
    assign s_rvalid = {{(8-master_n){1'b1}}, {master_n{grant_mid_fifo_empty_n & m_axi_rvalid}} & grant_mid_fifo_dout_onehot};
    assign m_axi_rready = grant_mid_fifo_empty_n & ((s_rready[master_n-1:0] & grant_mid_fifo_dout_onehot) != {master_n{1'b0}});
    assign grant_mid_fifo_ren = m_axi_rvalid & ((s_rready[master_n-1:0] & grant_mid_fifo_dout_onehot) != {master_n{1'b0}}) & m_axi_rlast;
    
endmodule
