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
本模块: UART控制器

描述: 
使用发送/接收fifo的UART控制器
可选AXIS接口或FIFO接口

注意：
当使用FIFO接口时, UART发送FIFO请使用标准FIFO
UART接收可能溢出

协议:
AXIS MASTER/SLAVE
FIFO READ/WRITE
UART

作者: 陈家耀
日期: 2023/11/08
********************************************************************/


module uart_rx_tx #(
    parameter integer clk_frequency_MHz = 200, // 时钟频率
    parameter integer baud_rate = 115200, // 波特率
    parameter interface = "fifo", // 接口协议(axis|fifo)
    parameter real simulation_delay = 1 // 仿真延时
)(
    input wire clk,
    input wire resetn,
    
    input wire rx,
    output wire tx,
    
    output wire[7:0] m_axis_rx_byte_data,
    output wire m_axis_rx_byte_valid,
    input wire m_axis_rx_byte_ready,
    
    output wire[7:0] rx_buf_fifo_din,
    output wire rx_buf_fifo_wen,
    input wire rx_buf_fifo_full,
    
    input wire[7:0] s_axis_tx_byte_data,
    input wire s_axis_tx_byte_valid,
    output wire s_axis_tx_byte_ready,
    
    input wire[7:0] tx_buf_fifo_dout,
    input wire tx_buf_fifo_empty,
    input wire tx_buf_fifo_almost_empty,
    output wire tx_buf_fifo_ren,
    
    output wire rx_err,
    output wire tx_idle,
    output wire rx_idle,
    output wire tx_done,
    output wire rx_done,
    output wire rx_start
);
    
    // 检查接收缓冲区是否溢出
    reg rx_err_reg;
    
    assign rx_err = rx_err_reg;
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            rx_err_reg <= 1'b0;
        else
            # simulation_delay rx_err_reg <= (interface == "axis") ? (m_axis_rx_byte_valid & (~m_axis_rx_byte_ready)):(rx_buf_fifo_wen & rx_buf_fifo_full);
    end
    
    /** uart收发 **/
    localparam integer clk_frequency = clk_frequency_MHz * 1000000;
    
    assign rx_buf_fifo_din = m_axis_rx_byte_data;
    assign rx_buf_fifo_wen = m_axis_rx_byte_valid;
    
    uart_rx #(
        .clk_frequency(clk_frequency),
        .baud_rate(baud_rate),
        .simulation_delay(simulation_delay)
    )uart_rx_u(
        .clk(clk),
        .rst_n(resetn),
        .rx(rx),
        .rx_byte_data(m_axis_rx_byte_data),
        .rx_byte_valid(m_axis_rx_byte_valid),
        .rx_byte_ready((interface == "axis") ? m_axis_rx_byte_ready:(~rx_buf_fifo_full)),
        .rx_idle(rx_idle),
        .rx_done(rx_done),
        .rx_start(rx_start)
    );
    
    uart_tx #(
        .clk_frequency(clk_frequency),
        .baud_rate(baud_rate),
        .interface(interface),
        .simulation_delay(simulation_delay)
    )uart_tx_u(
        .clk(clk),    
        .rst_n(resetn),
        .tx(tx),
        .tx_byte_data(s_axis_tx_byte_data),
        .tx_byte_valid(s_axis_tx_byte_valid),
        .tx_byte_ready(s_axis_tx_byte_ready),
        .tx_fifo_dout(tx_buf_fifo_dout),
        .tx_fifo_empty(tx_buf_fifo_empty),
        .tx_fifo_ren(tx_buf_fifo_ren),
        .tx_idle(tx_idle),
        .tx_done(tx_done)
    );

endmodule
