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
本模块: 帧读写传输事务fifo

描述: 
基于寄存器的fifo
位宽 = 1
深度 = axi_rwaddr_outstanding
FWFT = true

注意：
无

协议:
FIFO READ/WRITE

作者: 陈家耀
日期: 2024/05/08
********************************************************************/


module rw_frame_trans_fifo #(
    parameter integer axi_rwaddr_outstanding = 2, // AXI读写地址缓冲深度(1 | 2 | 4 | 8 | 16)
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // fifo写端口
    input wire rw_frame_trans_fifo_wen,
    output wire rw_frame_trans_fifo_full,
    input wire rw_frame_trans_fifo_din, // 当前是否帧内最后1次传输
    // fifo读端口
    input wire rw_frame_trans_fifo_ren,
    output wire rw_frame_trans_fifo_empty,
    output wire rw_frame_trans_fifo_dout // 当前是否帧内最后1次传输
);

    generate
        if(axi_rwaddr_outstanding > 1)
        begin
            fifo_based_on_regs #(
                .fwft_mode("true"),
                .fifo_depth(axi_rwaddr_outstanding),
                .fifo_data_width(1),
                .almost_full_th(),
                .almost_empty_th(),
                .simulation_delay(simulation_delay)
            )fifo_based_on_regs_u(
                .clk(clk),
                .rst_n(rst_n),
                .fifo_wen(rw_frame_trans_fifo_wen),
                .fifo_din(rw_frame_trans_fifo_din),
                .fifo_full(rw_frame_trans_fifo_full),
                .fifo_ren(rw_frame_trans_fifo_ren),
                .fifo_dout(rw_frame_trans_fifo_dout),
                .fifo_empty(rw_frame_trans_fifo_empty)
            );
        end
        else
        begin
            reg rw_frame_trans_fifo_buf;
            reg rw_frame_trans_fifo_full_reg;
            reg rw_frame_trans_fifo_empty_reg;
            
            assign rw_frame_trans_fifo_full = rw_frame_trans_fifo_full_reg;
            assign rw_frame_trans_fifo_empty = rw_frame_trans_fifo_empty_reg;
            assign rw_frame_trans_fifo_dout = rw_frame_trans_fifo_buf;
            
            always @(posedge clk)
            begin
                if(rw_frame_trans_fifo_wen & (~rw_frame_trans_fifo_full))
                    # simulation_delay rw_frame_trans_fifo_buf <= rw_frame_trans_fifo_din;
            end
            
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rw_frame_trans_fifo_full_reg <= 1'b0;
                else
                    # simulation_delay rw_frame_trans_fifo_full_reg <= rw_frame_trans_fifo_full_reg ? (~rw_frame_trans_fifo_ren):rw_frame_trans_fifo_wen;
            end
            
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rw_frame_trans_fifo_empty_reg <= 1'b1;
                else
                    # simulation_delay rw_frame_trans_fifo_empty_reg <= rw_frame_trans_fifo_empty_reg ? (~rw_frame_trans_fifo_wen):rw_frame_trans_fifo_ren;
            end
        end
    endgenerate
    
endmodule
