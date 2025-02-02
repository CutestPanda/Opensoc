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
本模块: AXI写响应通道的边界保护

描述: 
对AXI从机的B通道进行边界保护
32位地址/数据总线

注意：
仅支持INCR突发类型

以下非寄存器输出 ->
    AXI从机B通道: m_axis_b_valid
    AXI主机B通道: m_axi_bready

协议:
AXI MASTER(ONLY B)
AXIS MASTER
FIFO READ

作者: 陈家耀
日期: 2024/05/02
********************************************************************/


module axi_b_boundary_protect #(
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // AXI从机的B
    output wire[7:0] m_axis_b_data, // {保留(6bit), bresp(2bit)}
    output wire m_axis_b_valid,
    input wire m_axis_b_ready,
    
    // AXI主机的B
    input wire[1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready,
    
    // 写跨界标志fifo写端口
    output wire wt_across_boundary_fifo_ren,
    input wire wt_across_boundary_fifo_dout,
    input wire wt_across_boundary_fifo_empty_n
);

    reg bresp_merged; // 写响应合并

    assign m_axis_b_data = {6'dx, m_axi_bresp};
    // 握手条件: wt_across_boundary_fifo_empty_n & m_axi_bvalid & ((~wt_across_boundary_fifo_dout) | bresp_merged) & m_axis_b_ready
    assign m_axis_b_valid = wt_across_boundary_fifo_empty_n & m_axi_bvalid & ((~wt_across_boundary_fifo_dout) | bresp_merged);
    // 握手条件: m_axi_bvalid & wt_across_boundary_fifo_empty_n & m_axis_b_ready
    assign m_axi_bready = wt_across_boundary_fifo_empty_n & m_axis_b_ready;
    
    assign wt_across_boundary_fifo_ren = m_axi_bvalid & ((~wt_across_boundary_fifo_dout) | bresp_merged) & m_axis_b_ready;
    
    // 写响应合并
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            bresp_merged <= 1'b0;
        else if(m_axi_bvalid & m_axi_bready)
            # simulation_delay bresp_merged <= ~((~wt_across_boundary_fifo_dout) | bresp_merged);
    end
    
endmodule
