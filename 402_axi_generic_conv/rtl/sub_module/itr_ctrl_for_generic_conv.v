`timescale 1ns / 1ps
/********************************************************************
本模块: 通用卷积计算单元的中断控制模块

描述:
产生中断请求 -> 
	读请求描述子DMA请求处理完成
	写请求描述子DMA请求处理完成
	完成写请求

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/11/12
********************************************************************/


module itr_ctrl_for_generic_conv #(
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
	
	// 中断事件指示
	input wire rd_req_dsc_dma_blk_done, // 读请求描述子DMA请求处理完成(指示)
	input wire wt_req_dsc_dma_blk_done, // 写请求描述子DMA请求处理完成(指示)
	input wire wt_req_fns, // 完成写请求(指示)
	
	// 中断使能
	input wire en_wt_req_fns_itr, // 是否使能写请求处理完成中断
	
	// 中断阈值
	input wire[31:0] wt_req_itr_th, // 写请求处理完成中断阈值
	
	// 中断请求
	output wire[2:0] itr_req
);
	
	reg rd_req_dsc_dma_blk_done_d;
	reg wt_req_dsc_dma_blk_done_d;
	reg[31:0] wt_req_fns_n; // 已完成的写请求个数
	reg wt_req_fns_itr_req; // 写完成中断请求
	reg wt_req_fns_d;
	
	assign itr_req = {wt_req_fns_itr_req, wt_req_dsc_dma_blk_done_d, rd_req_dsc_dma_blk_done_d};
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rd_req_dsc_dma_blk_done_d <= 1'b0;
		else
			rd_req_dsc_dma_blk_done_d <= # simulation_delay rd_req_dsc_dma_blk_done;
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wt_req_dsc_dma_blk_done_d <= 1'b0;
		else
			wt_req_dsc_dma_blk_done_d <= # simulation_delay wt_req_dsc_dma_blk_done;
	end
	
	// 已完成的写请求个数
	always @(posedge clk)
	begin
		if((~en_wt_req_fns_itr) | wt_req_fns)
			wt_req_fns_n <= # simulation_delay 
				// ((~en_wt_req_fns_itr) | (wt_req_fns_n == wt_req_itr_th)) ? 32'd0:(wt_req_fns_n + 32'd1)
				{32{en_wt_req_fns_itr & (wt_req_fns_n != wt_req_itr_th)}} & (wt_req_fns_n + 32'd1);
	end
	
	// 写完成中断请求
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wt_req_fns_itr_req <= 1'b0;
		else
			wt_req_fns_itr_req <= # simulation_delay wt_req_fns_d & (wt_req_fns_n == wt_req_itr_th);
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wt_req_fns_d <= 1'b0;
		else
			wt_req_fns_d <= # simulation_delay en_wt_req_fns_itr & wt_req_fns;
	end
	
endmodule
