`timescale 1ns / 1ps
/********************************************************************
本模块: 基于ram的标准同步fifo控制器

描述: 
全流水的高性能同步fifo控制器
基于ram
标准fifo(READ LA = 1|2)
可选的固定阈值将满/将空信号

注意：
将满信号当存储计数 >= almost_full_th时有效
将空信号当存储计数 <= almost_empty_th时有效
almost_full_th和almost_empty_th必须在[1, fifo_depth-1]范围内
要求ram的读延迟=1clk

协议:
FIFO WRITE/READ
MEM WRITE/READ

作者: 陈家耀
日期: 2023/10/29
********************************************************************/


module fifo_based_on_ram_std #(
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
    
    // MEM WRITE(ram写端口)
    output wire ram_wen,
    output wire[clogb2(fifo_depth-1):0] ram_w_addr,
    output wire[fifo_data_width-1:0] ram_din,
    
    // MEM RAD(ram读端口)
    output wire ram_ren,
    output wire[clogb2(fifo_depth-1):0] ram_r_addr,
    input wire[fifo_data_width-1:0] ram_dout,
    
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
        else if(
            (({fifo_wen, fifo_ren} == 2'b01) & fifo_empty_n_reg) | 
            (({fifo_wen, fifo_ren} == 2'b10) & fifo_full_n_reg) |
            (({fifo_wen, fifo_ren} == 2'b11) & (fifo_empty_n_reg ^ fifo_full_n_reg))
        )begin
            # simulation_delay;
        
            if(({fifo_wen, fifo_ren} == 2'b10) | (({fifo_wen, fifo_ren} == 2'b11) & fifo_full_n_reg))
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
    assign ram_wen = fifo_wen & fifo_full_n_reg;
    assign ram_w_addr = fifo_wptr;
    assign ram_din = fifo_din;
    
    assign ram_ren = fifo_ren & fifo_empty_n_reg;
    assign ram_r_addr = fifo_rptr;
    assign fifo_dout = ram_dout;
    
endmodule

