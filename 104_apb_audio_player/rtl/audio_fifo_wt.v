`timescale 1ns / 1ps
/********************************************************************
本模块: 音频fifo写端口位宽变换

描述:
将上游的音频fifo写端口(8位)转换到下游的音频fifo写端口(16位)

注意：
无

协议:
FIFO WRITE

作者: 陈家耀
日期: 2024/08/06
********************************************************************/


module audio_fifo_wt #(
	parameter real simulation_delay = 0 // 仿真延时
)(
	// AMBA总线时钟和复位
	input wire amba_clk,
	input wire amba_resetn,
	
	// DMA启动(指示)
	input wire on_dma_start,
	
	// 音频数据fifo写端口(上游)
	input wire audio_fifo_wen_up,
	output wire audio_fifo_full_up,
	input wire[7:0] audio_fifo_din_up, // 小端格式
	
	// 音频数据fifo写端口(下游)
	output wire audio_fifo_wen_down,
	input wire audio_fifo_almost_full_down,
	output wire[15:0] audio_fifo_din_down
);
	
	/** 位宽变换 **/
	reg[7:0] audio_fifo_din_buf; // 音频数据fifo写数据缓存
	reg audio_fifo_wen_down_acpt; // 音频数据fifo下游可写(标志)
	
	assign audio_fifo_full_up = audio_fifo_almost_full_down;
	
	assign audio_fifo_wen_down = audio_fifo_wen_up & audio_fifo_wen_down_acpt;
	assign audio_fifo_din_down = {audio_fifo_din_up, audio_fifo_din_buf};
	
	// 音频数据fifo写数据缓存
	always @(posedge amba_clk)
	begin
		if(audio_fifo_wen_up)
			# simulation_delay audio_fifo_din_buf <= audio_fifo_din_up;
	end
	
	// 音频数据fifo下游可写(标志)
	always @(posedge amba_clk or negedge amba_resetn)
	begin
		// 可以无需复位!
		if(~amba_resetn)
			audio_fifo_wen_down_acpt <= 1'b0;
		else if(on_dma_start) // 清零
			# simulation_delay audio_fifo_wen_down_acpt <= 1'b0;
		else if(audio_fifo_wen_up) // 更新
			# simulation_delay audio_fifo_wen_down_acpt <= ~audio_fifo_wen_down_acpt;
	end
	
endmodule
