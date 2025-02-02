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
本模块: AXI写数据/写响应通道路由

描述: 
将给定从机的写数据(W)通道选通给主机
将主机的写响应通道(B)路由到给定的从机

注意：
无

协议:
FIFO READ

作者: 陈家耀
日期: 2024/04/29
********************************************************************/


module axi_wchn_router #(
    parameter integer master_n = 4, // 主机个数(必须在范围[2, 8]内)
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // AXI从机W通道
    input wire[35:0] s0_w_payload, // 0号从机W通道的负载
    input wire[35:0] s1_w_payload, // 1号从机W通道的负载
    input wire[35:0] s2_w_payload, // 2号从机W通道的负载
    input wire[35:0] s3_w_payload, // 3号从机W通道的负载
    input wire[35:0] s4_w_payload, // 4号从机W通道的负载
    input wire[35:0] s5_w_payload, // 5号从机W通道的负载
    input wire[35:0] s6_w_payload, // 6号从机W通道的负载
    input wire[35:0] s7_w_payload, // 7号从机W通道的负载
    input wire[7:0] s_w_last, // 每个从机W通道的last信号
    input wire[7:0] s_w_valid, // 每个从机W通道的valid信号
    output wire[7:0] s_w_ready, // 每个从机W通道的ready信号
    
    // AXI从机B通道
    output wire[7:0] s_b_valid, // 从机B通道的valid信号
    input wire[7:0] s_b_ready, // 从机B通道的ready信号
    
    // AXI主机W通道
    output wire[35:0] m_w_payload, // 主机W通道负载
    output wire m_w_last,
    output wire m_w_valid,
    input wire m_w_ready,
    // AXI主机B通道
    input wire m_b_valid,
    output wire m_b_ready,
    
    // 授权主机编号fifo读端口
    output wire grant_mid_fifo_ren,
    input wire grant_mid_fifo_empty_n,
    input wire[master_n-1:0] grant_mid_fifo_dout_onehot, // 独热码编号
    input wire[clogb2(master_n-1):0] grant_mid_fifo_dout_bin // 二进制码编号
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

    /** AXI从机W通道的负载 **/
    wire[35:0] s_w_payload[7:0];
    
    assign s_w_payload[0] = s0_w_payload;
    assign s_w_payload[1] = s1_w_payload;
    assign s_w_payload[2] = s2_w_payload;
    assign s_w_payload[3] = s3_w_payload;
    assign s_w_payload[4] = s4_w_payload;
    assign s_w_payload[5] = s5_w_payload;
    assign s_w_payload[6] = s6_w_payload;
    assign s_w_payload[7] = s7_w_payload;
    
    /** AXI写数据通道路由 **/
    // 当W通道通道突发结束但是B通道未握手时不使能W通道
    reg w_chn_en; // W通道使能
    
    // 写数据使能
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            w_chn_en <= 1'b1;
        else
            # simulation_delay w_chn_en <= w_chn_en ? 
                (~((m_w_valid & m_w_ready & m_w_last) & (~(m_b_valid & m_b_ready)))):(m_b_valid & m_b_ready);
    end
    
    // 将从机写数据通道的payload和last路由给主机
    assign m_w_payload = s_w_payload[grant_mid_fifo_dout_bin];
    assign m_w_last = s_w_last[grant_mid_fifo_dout_bin];
    // 对于每个从机的W通道, 握手条件是: w_chn_en & s_w_valid[i] & grant_mid_fifo_empty_n & m_w_ready & grant_mid_fifo_dout_onehot[i]
    assign m_w_valid = w_chn_en & grant_mid_fifo_empty_n & ((grant_mid_fifo_dout_onehot & s_w_valid[master_n-1:0]) != {master_n{1'b0}});
    assign s_w_ready = {{(8-master_n){1'b1}}, {master_n{w_chn_en & grant_mid_fifo_empty_n & m_w_ready}} & grant_mid_fifo_dout_onehot};
    
    /** AXI写响应通道路由 **/
    // 对于每个从机的B通道, 握手条件是: m_b_valid & grant_mid_fifo_dout_onehot[i] & s_b_ready[i]
    assign s_b_valid = {{(8-master_n){1'b1}}, {master_n{m_b_valid}} & grant_mid_fifo_dout_onehot};
    assign m_b_ready = (grant_mid_fifo_dout_onehot & s_b_ready[master_n-1:0]) != {master_n{1'b0}};
    
    /** 授权主机编号fifo读端口 **/
    assign grant_mid_fifo_ren = m_b_valid & m_b_ready;
    
endmodule
