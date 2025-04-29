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
本模块: 基于lutram的同步fifo

描述: 
全流水的高性能同步fifo
基于lutram
支持first word fall through特性(READ LA = 0)
可选的固定阈值将满/将空信号

注意：
将满信号当存储计数 >= almost_full_th时有效
将空信号当存储计数 <= almost_empty_th时有效
almost_full_th和almost_empty_th必须在[1, fifo_depth-1]范围内

协议:
FIFO WRITE/READ

作者: 陈家耀
日期: 2023/10/13
********************************************************************/


module fifo_based_on_lutram #(
    parameter fwft_mode = "true", // 是否启用first word fall through特性
    parameter integer fifo_depth = 32, // fifo深度(必须为2|4|8|16|...)
    parameter integer fifo_data_width = 32, // fifo位宽
    parameter integer almost_full_th = 20, // fifo将满阈值
    parameter integer almost_empty_th = 5, // fifo将空阈值
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // FIFO WRITE(fifo写端口)
    input wire fifo_wen,
    input wire[fifo_data_width-1:0] fifo_din,
    output wire fifo_full,
    output wire fifo_full_n,
    output wire fifo_almost_full,
    output wire fifo_almost_full_n,
    
    // FIFO READ(fifo读端口)
    input wire fifo_ren,
    output wire[fifo_data_width-1:0] fifo_dout,
    output wire fifo_empty,
    output wire fifo_empty_n,
    output wire fifo_almost_empty,
    output wire fifo_almost_empty_n,
    
    // 存储计数
    output wire[clogb2(fifo_depth):0] data_cnt
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
    
    /** 参数 **/
    localparam integer use_cnt_th = 8;
    
    /** 空满标志和存储计数 **/
    reg fifo_empty_reg;
    reg fifo_full_reg;
    reg fifo_almost_empty_reg;
    reg fifo_almost_full_reg;
    reg fifo_empty_n_reg;
    reg fifo_full_n_reg;
    reg fifo_almost_empty_n_reg;
    reg fifo_almost_full_n_reg;
    reg[clogb2(fifo_depth):0] data_cnt_regs;
    reg[fifo_depth:0] data_cnt_onehot_regs;
    
    assign {fifo_empty, fifo_full} = {fifo_empty_reg, fifo_full_reg};
    assign {fifo_empty_n, fifo_full_n} = {fifo_empty_n_reg, fifo_full_n_reg};
    assign {fifo_almost_empty, fifo_almost_full} = {fifo_almost_empty_reg, fifo_almost_full_reg};
    assign {fifo_almost_empty_n, fifo_almost_full_n} = {fifo_almost_empty_n_reg, fifo_almost_full_n_reg};
    assign data_cnt = data_cnt_regs;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
        begin
            fifo_empty_reg <= 1'b1;
            fifo_empty_n_reg <= 1'b0;
            fifo_full_reg <= 1'b0;
            fifo_full_n_reg <= 1'b1;
            fifo_almost_empty_reg <= 1'b1;
            fifo_almost_empty_n_reg <= 1'b0;
            fifo_almost_full_reg <= 1'b0;
            fifo_almost_full_n_reg <= 1'b1;
            
            data_cnt_regs <= 0;
            data_cnt_onehot_regs <= 1;
        end
        else if((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg))
		begin
            # simulation_delay;
			
            if(fifo_wen & fifo_full_n_reg)
            begin
                // fifo数据增加1个
                fifo_empty_reg <= 1'b0;
                fifo_empty_n_reg <= 1'b1;
                fifo_full_reg <= (fifo_depth >= use_cnt_th) ? data_cnt_regs == fifo_depth - 1:data_cnt_onehot_regs[fifo_depth-1];
                fifo_full_n_reg <= (fifo_depth >= use_cnt_th) ? data_cnt_regs != fifo_depth - 1:(~data_cnt_onehot_regs[fifo_depth-1]);
                fifo_almost_empty_reg <= (data_cnt_regs <= almost_empty_th - 1);
                fifo_almost_empty_n_reg <= ~(data_cnt_regs <= almost_empty_th - 1);
                fifo_almost_full_reg <= (data_cnt_regs >= almost_full_th - 1);
                fifo_almost_full_n_reg <= ~(data_cnt_regs >= almost_full_th - 1);
                
                data_cnt_regs <= data_cnt_regs + 1;
                data_cnt_onehot_regs <= {data_cnt_onehot_regs[fifo_depth-1:0], 1'b0}; // 左移
            end
            else
            begin
                // fifo数据减少1个
                fifo_empty_reg <= (fifo_depth >= use_cnt_th) ? data_cnt_regs == 1:data_cnt_onehot_regs[1];
                fifo_empty_n_reg <= (fifo_depth >= use_cnt_th) ? data_cnt_regs != 1:(~data_cnt_onehot_regs[1]);
                fifo_full_reg <= 1'b0;
                fifo_full_n_reg <= 1'b1;
                fifo_almost_empty_reg <= (data_cnt_regs <= almost_empty_th + 1);
                fifo_almost_empty_n_reg <= ~(data_cnt_regs <= almost_empty_th + 1);
                fifo_almost_full_reg <= (data_cnt_regs >= almost_full_th + 1);
                fifo_almost_full_n_reg <= ~(data_cnt_regs >= almost_full_th + 1);
                
                data_cnt_regs <= data_cnt_regs - 1;
                data_cnt_onehot_regs <= {1'b0, data_cnt_onehot_regs[fifo_depth:1]}; // 右移
            end
        end
    end
    
    /** 读写指针 **/
    reg[clogb2(fifo_depth-1):0] fifo_rptr;
    reg[clogb2(fifo_depth-1):0] fifo_rptr_add1;
    reg[clogb2(fifo_depth-1):0] fifo_wptr;
    reg[fifo_depth-1:0] fifo_wptr_onehot;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            fifo_rptr <= 0;
        else if(fifo_ren & fifo_empty_n_reg)
            #simulation_delay fifo_rptr <= fifo_rptr + 1;
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            fifo_rptr_add1 <= 1;
        else if(fifo_ren & fifo_empty_n_reg)
            #simulation_delay fifo_rptr_add1 <= fifo_rptr_add1 + 1;
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            fifo_wptr <= 0;
        else if(fifo_wen & fifo_full_n_reg)
            #simulation_delay fifo_wptr <= fifo_wptr + 1;
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            fifo_wptr_onehot <= 1;
        else if(fifo_wen & fifo_full_n_reg)
            #simulation_delay fifo_wptr_onehot <= {fifo_wptr_onehot[fifo_depth-2:0], fifo_wptr_onehot[fifo_depth-1]}; // 循环左移
    end
    
    /** 读写数据 **/
    (* ram_style="distributed" *) reg[fifo_data_width-1:0] fifo_regs[fifo_depth-1:0];
    reg[fifo_data_width-1:0] fifo_dout_regs;
    
    assign fifo_dout = fifo_dout_regs;
    
    always @(posedge clk)
    begin
        if(fifo_wen & fifo_full_n_reg)
            #simulation_delay fifo_regs[fifo_wptr] <= fifo_din;
    end
    
    generate
        if(fwft_mode == "true")
        begin
            always @(posedge clk)
            begin
                if({fifo_empty_n_reg, fifo_ren} != 2'b10)
                    #simulation_delay fifo_dout_regs <= fifo_empty_n_reg & (~(fifo_wen & ((fifo_depth >= use_cnt_th) ? data_cnt_regs == 1:data_cnt_onehot_regs[1]))) ?
                        fifo_regs[fifo_rptr_add1]:fifo_din;
            end
        end
        else
        begin
            always @(posedge clk)
            begin
                if(fifo_ren & fifo_empty_n_reg)
                    #simulation_delay fifo_dout_regs <= fifo_regs[fifo_rptr];
            end
        end
    endgenerate

endmodule

