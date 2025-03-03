`timescale 1ns / 1ps
/********************************************************************
本模块: fifo FWFT缓冲区

描述: 
用于将读延迟为1clk的fifo转换为FWFT的fifo

注意：
无

协议:
FIFO READ

作者: 陈家耀
日期: 2024/05/30
********************************************************************/


module fifo_show_ahead_buffer #(
    parameter integer fifo_data_width = 32, // fifo位宽
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 标准fifo的读端口
    output wire std_fifo_ren,
    input wire[fifo_data_width-1:0] std_fifo_dout,
    input wire std_fifo_empty,
    
    // FWFT fifo的读端口
    input wire fwft_fifo_ren,
    output wire[fifo_data_width-1:0] fwft_fifo_dout,
    output wire fwft_fifo_empty,
    output wire fwft_fifo_empty_n
);
    
    /** 寄存器buffer **/
    reg std_fifo_rvld; // 标准fifo有效读(指示)
    reg[fifo_data_width-1:0] regs_buffer[1:0]; // 寄存器buffer
    reg[2:0] buffer_data_cnt; // buffer存储计数(3'b001 -> 0, 3'b010 -> 1, 3'b100 -> 2)
    wire[2:0] buffer_data_cnt_sub1; // buffer存储计数 - 1(3'b001 -> 0, 3'b010 -> 1, 3'b100 -> 2)
    
    assign buffer_data_cnt_sub1 = {buffer_data_cnt[0], buffer_data_cnt[2:1]};
    
    // 标准fifo有效读(指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            std_fifo_rvld <= 1'b0;
        else
            # simulation_delay std_fifo_rvld <= std_fifo_ren & (~std_fifo_empty);
    end
    
    // 寄存器buffer
    always @(posedge clk)
    begin
        if(std_fifo_rvld & ((fwft_fifo_ren & fwft_fifo_empty_n) ? buffer_data_cnt_sub1[0]:buffer_data_cnt[0]))
            # simulation_delay regs_buffer[0] <= std_fifo_dout;
        else if(fwft_fifo_ren & fwft_fifo_empty_n)
            # simulation_delay regs_buffer[0] <= regs_buffer[1];
    end
    
    always @(posedge clk)
    begin
        if(std_fifo_rvld & ((fwft_fifo_ren & fwft_fifo_empty_n) ? buffer_data_cnt_sub1[1]:buffer_data_cnt[1]))
            # simulation_delay regs_buffer[1] <= std_fifo_dout;
    end
    
    // buffer存储计数独热码
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            buffer_data_cnt <= 3'b001;
        else if(std_fifo_rvld ^ (fwft_fifo_ren & fwft_fifo_empty_n))
            # simulation_delay buffer_data_cnt <= std_fifo_rvld ? {buffer_data_cnt[1:0], buffer_data_cnt[2]}:{buffer_data_cnt[0], buffer_data_cnt[2:1]};
    end
    
    /** 标准fifo的读端口 **/
    assign std_fifo_ren = buffer_data_cnt[0] | fwft_fifo_ren; // buffer存储计数==0或者FWFT-fifo读使能时标准fifo读使能有效
    
    /** FWFT fifo的读端口 **/
    reg fwft_fifo_empty_n_reg;
    
    assign fwft_fifo_dout = regs_buffer[0];
    assign fwft_fifo_empty = buffer_data_cnt[0];
    assign fwft_fifo_empty_n = fwft_fifo_empty_n_reg;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            fwft_fifo_empty_n_reg <= 1'b0;
        else if(std_fifo_rvld ^ (fwft_fifo_ren & fwft_fifo_empty_n))
            # simulation_delay fwft_fifo_empty_n_reg <= std_fifo_rvld ? 1'b1:(~buffer_data_cnt[1]);
    end
    
endmodule
