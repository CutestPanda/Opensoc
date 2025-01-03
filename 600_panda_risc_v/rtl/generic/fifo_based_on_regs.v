`timescale 1ns / 1ps
/********************************************************************
本模块: 基于寄存器片的同步fifo

描述: 
高性能同步fifo
基于寄存器片
支持first word fall through特性(READ LA = 0)
可选的固定阈值将满/将空信号
当启用FWFT特性时, 可启用低时延模式, 此时当fifo为空时可将写数据直接旁路到读端口

注意：
将满信号当存储计数 >= almost_full_th时有效
将空信号当存储计数 <= almost_empty_th时有效
almost_full_th和almost_empty_th必须在[1, fifo_depth-1]范围内
当启用FWFT特性时, fifo_dout非寄存器输出

协议:
FIFO READ/WRITE

作者: 陈家耀
日期: 2025/01/03
********************************************************************/


module fifo_based_on_regs #(
    parameter fwft_mode = "true", // 是否启用first word fall through特性
	parameter low_latency_mode = "false", // 是否启用低时延模式(仅启用FWFT时可用)
    parameter integer fifo_depth = 4, // fifo深度(必须在范围[2, 8]内)
    parameter integer fifo_data_width = 32, // fifo位宽
    parameter integer almost_full_th = 3, // fifo将满阈值
    parameter integer almost_empty_th = 1, // fifo将空阈值
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
	
    // 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
    end
    endfunction
    
    /** 空满标志和存储计数 **/
	reg[clogb2(fifo_depth):0] data_cnt_regs;
	wire[clogb2(fifo_depth):0] data_cnt_nxt;
    reg fifo_empty_reg;
    reg fifo_full_reg;
    reg fifo_almost_empty_reg;
    reg fifo_almost_full_reg;
    reg fifo_empty_n_reg;
    reg fifo_full_n_reg;
    reg fifo_almost_empty_n_reg;
    reg fifo_almost_full_n_reg;
	
	assign fifo_full = fifo_full_reg;
	assign fifo_full_n = fifo_full_n_reg;
	assign fifo_almost_full = fifo_almost_full_reg;
	assign fifo_almost_full_n = fifo_almost_full_n_reg;
	assign fifo_empty = fifo_empty_reg & (~((fwft_mode == "true") & (low_latency_mode == "true") & fifo_wen));
	assign fifo_empty_n = fifo_empty_n_reg | ((fwft_mode == "true") & (low_latency_mode == "true") & fifo_wen);
	assign fifo_almost_empty = fifo_almost_empty_reg;
	assign fifo_almost_empty_n = fifo_almost_empty_n_reg;
	assign data_cnt = data_cnt_regs;
	
	assign data_cnt_nxt = (fifo_wen & fifo_full_n_reg) ? (data_cnt_regs + 1):(data_cnt_regs - 1);
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			data_cnt_regs <= 0;
		else if(((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg)) & 
			(~((fwft_mode == "true") & (low_latency_mode == "true") & (~fifo_empty_n_reg) & fifo_ren)))
			data_cnt_regs <= # simulation_delay data_cnt_nxt;
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fifo_empty_reg <= 1'b1;
		else if(((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg)) & 
			(~((fwft_mode == "true") & (low_latency_mode == "true") & (~fifo_empty_n_reg) & fifo_ren)))
			// (fifo_wen & fifo_full_n_reg) ? 1'b0:(data_cnt_regs == 1)
			fifo_empty_reg <= # simulation_delay (~(fifo_wen & fifo_full_n_reg)) & (data_cnt_regs == 1);
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fifo_empty_n_reg <= 1'b0;
		else if(((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg)) & 
			(~((fwft_mode == "true") & (low_latency_mode == "true") & (~fifo_empty_n_reg) & fifo_ren)))
			// (fifo_wen & fifo_full_n_reg) ? 1'b1:(data_cnt_regs != 1)
			fifo_empty_n_reg <= # simulation_delay (fifo_wen & fifo_full_n_reg) | (data_cnt_regs != 1);
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fifo_full_reg <= 1'b0;
		else if(((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg)) & 
			(~((fwft_mode == "true") & (low_latency_mode == "true") & (~fifo_empty_n_reg) & fifo_ren)))
			// (fifo_ren & fifo_empty_n_reg) ? 1'b0:(data_cnt_regs == (fifo_depth - 1))
			fifo_full_reg <= # simulation_delay (~(fifo_ren & fifo_empty_n_reg)) & (data_cnt_regs == (fifo_depth - 1));
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fifo_full_n_reg <= 1'b1;
		else if(((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg)) & 
			(~((fwft_mode == "true") & (low_latency_mode == "true") & (~fifo_empty_n_reg) & fifo_ren)))
			// (fifo_ren & fifo_empty_n_reg) ? 1'b1:(data_cnt_regs != (fifo_depth - 1))
			fifo_full_n_reg <= # simulation_delay (fifo_ren & fifo_empty_n_reg) | (data_cnt_regs != (fifo_depth - 1));
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fifo_almost_empty_reg <= 1'b1;
		else if(((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg)) & 
			(~((fwft_mode == "true") & (low_latency_mode == "true") & (~fifo_empty_n_reg) & fifo_ren)))
			fifo_almost_empty_reg <= # simulation_delay data_cnt_nxt <= almost_empty_th;
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fifo_almost_empty_n_reg <= 1'b0;
		else if(((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg)) & 
			(~((fwft_mode == "true") & (low_latency_mode == "true") & (~fifo_empty_n_reg) & fifo_ren)))
			// ~(data_cnt_nxt <= almost_empty_th)
			fifo_almost_empty_n_reg <= # simulation_delay data_cnt_nxt > almost_empty_th;
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fifo_almost_full_reg <= 1'b0;
		else if(((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg)) & 
			(~((fwft_mode == "true") & (low_latency_mode == "true") & (~fifo_empty_n_reg) & fifo_ren)))
			fifo_almost_full_reg <= # simulation_delay data_cnt_nxt >= almost_full_th;
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fifo_almost_full_n_reg <= 1'b1;
		else if(((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg)) & 
			(~((fwft_mode == "true") & (low_latency_mode == "true") & (~fifo_empty_n_reg) & fifo_ren)))
			// ~(data_cnt_nxt >= almost_full_th)
			fifo_almost_full_n_reg <= # simulation_delay data_cnt_nxt < almost_full_th;
	end
    
    /** 读写指针 **/
    reg[clogb2(fifo_depth-1):0] fifo_rptr;
    reg[clogb2(fifo_depth-1):0] fifo_wptr;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            fifo_rptr <= 0;
        else if(fifo_ren & fifo_empty_n_reg & 
			(~((fwft_mode == "true") & (low_latency_mode == "true") & (~fifo_empty_n_reg) & fifo_ren)))
			// (fifo_rptr == (fifo_depth - 1)) ? 0:(fifo_rptr + 1)
			fifo_rptr <= # simulation_delay {(clogb2(fifo_depth-1)+1){fifo_rptr != (fifo_depth - 1)}} & (fifo_rptr + 1);
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            fifo_wptr <= 0;
        else if(fifo_wen & fifo_full_n_reg & 
			(~((fwft_mode == "true") & (low_latency_mode == "true") & (~fifo_empty_n_reg) & fifo_ren)))
			// (fifo_wptr == (fifo_depth - 1)) ? 0:(fifo_wptr + 1)
			fifo_wptr <= # simulation_delay {(clogb2(fifo_depth-1)+1){fifo_wptr != (fifo_depth - 1)}} & (fifo_wptr + 1);
    end
    
    /** 读写数据 **/
    (* ram_style="register" *) reg[fifo_data_width-1:0] fifo_regs[0:fifo_depth-1];
    reg[fifo_data_width-1:0] fifo_dout_regs;
	
    assign fifo_dout = (fwft_mode == "true") ? 
		(((low_latency_mode == "true") & (~fifo_empty_n_reg)) ? fifo_din:fifo_regs[fifo_rptr]):
		fifo_dout_regs;
	
    genvar fifo_regs_w_i;
    generate
        for(fifo_regs_w_i = 0;fifo_regs_w_i < fifo_depth;fifo_regs_w_i = fifo_regs_w_i + 1)
        begin
            always @(posedge clk)
            begin
                if(fifo_wen & fifo_full_n_reg & (fifo_wptr == fifo_regs_w_i) & 
					(~((fwft_mode == "true") & (low_latency_mode == "true") & (~fifo_empty_n_reg) & fifo_ren)))
					fifo_regs[fifo_regs_w_i] <= # simulation_delay fifo_din;
            end
        end
    endgenerate
    
	always @(posedge clk)
	begin
		if(fifo_ren & fifo_empty_n_reg)
			fifo_dout_regs <= # simulation_delay fifo_regs[fifo_rptr];
	end
    
endmodule

