`timescale 1ns / 1ps
/********************************************************************
本模块: 异步fifo控制器

描述: 
使用简单双口RAM作为fifo存储器

注意：
简单双口RAM的读延迟 = 1clk
仅支持标准模式

协议:
FIFO READ/WRITE
MEM READ/WRITE

作者: 陈家耀
日期: 2024/05/09
********************************************************************/


module async_fifo #(
    parameter integer depth = 32, // fifo深度(16 | 32 | 64 | ...)
    parameter integer data_width = 32, // 数据位宽
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk_wt,
    input wire rst_n_wt,
    input wire clk_rd,
    input wire rst_n_rd,
    
    // mem
    output wire ram_clk_w,
    output wire[clogb2(depth-1):0] ram_waddr,
    output wire ram_wen,
    output wire[data_width-1:0] ram_din,
    output wire ram_clk_r,
    output wire ram_ren,
    output wire[clogb2(depth-1):0] ram_raddr,
    input wire[data_width-1:0] ram_dout,
    
    // fifo
    input wire fifo_wen,
    output wire fifo_full,
    input wire[data_width-1:0] fifo_din,
    input wire fifo_ren,
    output wire fifo_empty,
    output wire[data_width-1:0] fifo_dout
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
    
    /** 常量 **/
    localparam integer rw_ptr_width = clogb2(depth-1) + 2; // 读写指针位宽
    
    /** 写端口 **/
    reg[rw_ptr_width-1:0] wptr_bin_at_w; // 位于写端口的写指针(二进制码)
    reg[rw_ptr_width-1:0] wptr_add1_bin_at_w; // 位于写端口的写指针+1(二进制码)
    wire[rw_ptr_width-1:0] wptr_gray_at_w_cvt_cmb; // 位于写端口的写指针的格雷码转换组合逻辑
    wire[rw_ptr_width-1:0] wptr_add1_gray_at_w_cvt_cmb; // 位于写端口的写指针+1的格雷码转换组合逻辑
    reg[rw_ptr_width-1:0] wptr_gray_at_w; // 位于写端口的写指针(格雷码)
    wire[rw_ptr_width-1:0] rptr_gray_at_w; // 同步到写端口的读指针(格雷码)
    reg fifo_full_reg; // fifo满标志
    
    assign ram_clk_w = clk_wt;
    assign ram_waddr = wptr_bin_at_w[rw_ptr_width-2:0];
    assign ram_wen = fifo_wen & (~fifo_full);
    assign ram_din = fifo_din;
    
    assign fifo_full = fifo_full_reg;
    
    assign wptr_gray_at_w_cvt_cmb = {1'b0, wptr_bin_at_w[rw_ptr_width-1:1]} ^ wptr_bin_at_w;
    assign wptr_add1_gray_at_w_cvt_cmb = {1'b0, wptr_add1_bin_at_w[rw_ptr_width-1:1]} ^ wptr_add1_bin_at_w;
    
    // 位于写端口的写指针(二进制码)
    always @(posedge clk_wt or negedge rst_n_wt)
    begin
        if(~rst_n_wt)
            wptr_bin_at_w <= 0;
        else if(fifo_wen & (~fifo_full))
            # simulation_delay wptr_bin_at_w <= wptr_bin_at_w + 1;
    end
    // 位于写端口的写指针+1(二进制码)
    always @(posedge clk_wt or negedge rst_n_wt)
    begin
        if(~rst_n_wt)
            wptr_add1_bin_at_w <= 1;
        else if(fifo_wen & (~fifo_full))
            # simulation_delay wptr_add1_bin_at_w <= wptr_add1_bin_at_w + 1;
    end
    // 位于写端口的写指针(格雷码)
    always @(posedge clk_wt or negedge rst_n_wt)
    begin
        if(~rst_n_wt)
            wptr_gray_at_w <= 0;
        else
            # simulation_delay wptr_gray_at_w <= wptr_gray_at_w_cvt_cmb;
    end
    
    // fifo满标志
    // 同步到写端口的读指针滞后几个clk, 会产生"虚满"
    always @(posedge clk_wt or negedge rst_n_wt)
    begin
        if(~rst_n_wt)
            fifo_full_reg <= 1'b0;
        else
            # simulation_delay fifo_full_reg <= ((fifo_wen & (~fifo_full)) ? wptr_add1_gray_at_w_cvt_cmb:wptr_gray_at_w_cvt_cmb) == 
                {~rptr_gray_at_w[rw_ptr_width-1:rw_ptr_width-2], rptr_gray_at_w[rw_ptr_width-3:0]};
    end
    
    /** 读端口 **/
    reg[rw_ptr_width-1:0] rptr_bin_at_r; // 位于读端口的读指针(二进制码)
    reg[rw_ptr_width-1:0] rptr_add1_bin_at_r; // 位于读端口的读指针+1(二进制码)
    wire[rw_ptr_width-1:0] rptr_gray_at_r_cvt_cmb; // 位于读端口的读指针的格雷码转换组合逻辑
    wire[rw_ptr_width-1:0] rptr_add1_gray_at_r_cvt_cmb; // 位于读端口的读指针+1的格雷码转换组合逻辑
    reg[rw_ptr_width-1:0] rptr_gray_at_r; // 位于读端口的读指针(格雷码)
    wire[rw_ptr_width-1:0] wptr_gray_at_r; // 同步到读端口的写指针(格雷码)
    reg fifo_empty_reg; // fifo空标志
    
    assign ram_clk_r = clk_rd;
    assign ram_ren = fifo_ren & (~fifo_empty);
    assign ram_raddr = rptr_bin_at_r[rw_ptr_width-2:0];
    
    assign fifo_empty = fifo_empty_reg;
    assign fifo_dout = ram_dout;
    
    assign rptr_gray_at_r_cvt_cmb = {1'b0, rptr_bin_at_r[rw_ptr_width-1:1]} ^ rptr_bin_at_r;
    assign rptr_add1_gray_at_r_cvt_cmb = {1'b0, rptr_add1_bin_at_r[rw_ptr_width-1:1]} ^ rptr_add1_bin_at_r;
    
    // 位于读端口的读指针(二进制码)
    always @(posedge clk_rd or negedge rst_n_rd)
    begin
        if(~rst_n_rd)
            rptr_bin_at_r <= 0;
        else if(fifo_ren & (~fifo_empty))
            # simulation_delay rptr_bin_at_r <= rptr_bin_at_r + 1;
    end
    // 位于读端口的读指针+1(二进制码)
    always @(posedge clk_rd or negedge rst_n_rd)
    begin
        if(~rst_n_rd)
            rptr_add1_bin_at_r <= 1;
        else if(fifo_ren & (~fifo_empty))
            # simulation_delay rptr_add1_bin_at_r <= rptr_add1_bin_at_r + 1;
    end
    // 位于读端口的读指针(格雷码)
    always @(posedge clk_rd or negedge rst_n_rd)
    begin
        if(~rst_n_rd)
            rptr_gray_at_r <= 0;
        else
            # simulation_delay rptr_gray_at_r <= rptr_gray_at_r_cvt_cmb;
    end
    
    // fifo空标志
    // 同步到读端口的写指针滞后几个clk, 会产生"虚空"
    always @(posedge clk_rd or negedge rst_n_rd)
    begin
        if(~rst_n_rd)
            fifo_empty_reg <= 1'b1;
        else
            # simulation_delay fifo_empty_reg <= ((fifo_ren & (~fifo_empty)) ? rptr_add1_gray_at_r_cvt_cmb:rptr_gray_at_r_cvt_cmb) == 
                wptr_gray_at_r;
    end
    
    /** 读写指针同步 **/
    // 同步读指针
    reg[rw_ptr_width-1:0] rptr_gray_at_w_p2;
    reg[rw_ptr_width-1:0] rptr_gray_at_w_p1;
    // 同步写指针
    reg[rw_ptr_width-1:0] wptr_gray_at_r_p2;
    reg[rw_ptr_width-1:0] wptr_gray_at_r_p1;
    
    assign rptr_gray_at_w = rptr_gray_at_w_p1;
    assign wptr_gray_at_r = wptr_gray_at_r_p1;
    
    // 用写时钟来同步读端口的读指针
    always @(posedge clk_wt or negedge rst_n_wt)
    begin
        if(~rst_n_wt)
        begin
            rptr_gray_at_w_p2 <= 0;
            rptr_gray_at_w_p1 <= 0;
        end
        else
            # simulation_delay {rptr_gray_at_w_p1, rptr_gray_at_w_p2} <= {rptr_gray_at_w_p2, rptr_gray_at_r};
    end
    
    // 用读时钟来同步写端口的写指针
    always @(posedge clk_rd or negedge rst_n_rd)
    begin
        if(~rst_n_rd)
        begin
            wptr_gray_at_r_p2 <= 0;
            wptr_gray_at_r_p1 <= 0;
        end
        else
            # simulation_delay {wptr_gray_at_r_p1, wptr_gray_at_r_p2} <= {wptr_gray_at_r_p2, wptr_gray_at_w};
    end
    
endmodule
