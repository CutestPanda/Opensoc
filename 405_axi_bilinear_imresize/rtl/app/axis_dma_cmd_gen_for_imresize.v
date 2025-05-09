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
本模块: AXIS DMA命令生成

描述:
接收双线性插值请求, 将请求传递给后级的计算模块, 并为DMA引擎生成MM2S/S2MM命令

注意：
无

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/02/22
********************************************************************/


module axis_dma_cmd_gen_for_imresize #(
	parameter integer RESIZE_SCALE_QUAZ_N = 8, // 缩放比例量化精度(必须在范围[4, 12]内)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// 双线性插值请求(AXIS从机)
	/*
	请求格式:{
		保留(6bit), 
		图片通道数 - 1(2bit), 
		源缓存区行跨度(16bit), 
		源图片宽度 - 1(16bit), 
		源图片高度 - 1(16bit), 
		目标图片宽度 - 1(16bit), 
		目标图片高度 - 1(16bit), 
		水平缩放比例(无符号定点数: 源图片宽度 / 目标图标宽度, 16bit), 
		竖直缩放比例(无符号定点数: 源图片高度 / 目标图标高度, 16bit), 
		源图片行跨度(以字节计, 16bit), 
		目标图片行跨度(以字节计, 16bit), 
		结果缓存区行跨度(以字节计, 16bit), 
		源图片基地址(32bit), 
		结果缓存区基地址(32bit)
	}
	*/
	input wire[231:0] s_req_axis_data,
	input wire s_req_axis_valid,
	output wire s_req_axis_ready,
	
	// 双线性插值请求(AXIS主机)
	/*
	请求格式: 同上
	*/
	output wire[231:0] m_req_axis_data,
	output wire m_req_axis_valid,
	input wire m_req_axis_ready,
	
	// MM2S命令(AXIS主机)
	output wire[55:0] m_mm2s_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire m_mm2s_cmd_axis_user, // {固定(1'b1)/递增(1'b0)传输(1bit)}
	                                  // const -> 1'b0
	output wire m_mm2s_cmd_axis_last, // 帧尾标志
	                                  // const -> 1'b1
	output wire m_mm2s_cmd_axis_valid,
	input wire m_mm2s_cmd_axis_ready,
	// S2MM命令(AXIS主机)
	output wire[55:0] m_s2mm_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire m_s2mm_cmd_axis_user, // {固定(1'b1)/递增(1'b0)传输(1bit)}
	                                  // const -> 1'b0
	output wire m_s2mm_cmd_axis_valid,
	input wire m_s2mm_cmd_axis_ready
);
	
	/** 内部配置 **/
	// 双线性插值请求的数据位宽
	localparam integer REQ_WIDTH = 232;
	// 双线性插值请求处理状态常量
	localparam integer RESIZE_REQ_STS_IDLE_ID = 0;
	localparam integer RESIZE_REQ_STS_START_ID = 1;
	localparam integer RESIZE_REQ_STS_PROCESSING_ID = 2;
	localparam integer RESIZE_REQ_STS_DONE_ID = 3;
	
	/** 双线性插值请求寄存器fifo **/
	// fifo写端口
	wire req_fifo_wen;
	wire[REQ_WIDTH-1:0] req_fifo_din;
	wire req_fifo_full_n;
	// fifo读端口
	wire req_fifo_ren;
	wire[REQ_WIDTH-1:0] req_fifo_dout;
	wire req_fifo_empty_n;
	
	assign m_req_axis_data = req_fifo_dout;
	assign m_req_axis_valid = req_fifo_empty_n;
	assign req_fifo_ren = m_req_axis_ready;
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(2),
		.fifo_data_width(REQ_WIDTH),
		.almost_full_th(1),
		.almost_empty_th(1),
		.simulation_delay(SIM_DELAY)
	)req_fifo(
		.clk(clk),
		.rst_n(resetn),
		
		.fifo_wen(req_fifo_wen),
		.fifo_din(req_fifo_din),
		.fifo_full_n(req_fifo_full_n),
		
		.fifo_ren(req_fifo_ren),
		.fifo_dout(req_fifo_dout),
		.fifo_empty_n(req_fifo_empty_n)
	);
	
	/** DMA命令生成给出的双线性插值请求AXIS从机 **/
	wire[REQ_WIDTH-1:0] s_cmd_gen_req_axis_data;
	reg[5:0] cmd_gen_req_reserved; // 保留位
	reg[1:0] cmd_gen_req_chn_sub1; // 图片通道数 - 1
	reg[15:0] cmd_gen_req_sbuf_stride; // 源缓存区行跨度
	reg[15:0] cmd_gen_req_src_w_sub1; // 源图片宽度 - 1
	reg[15:0] cmd_gen_req_src_h_sub1; // 源图片高度 - 1
	reg[15:0] cmd_gen_req_dst_w_sub1; // 目标图片宽度 - 1
	reg[15:0] cmd_gen_req_dst_h_sub1; // 目标图片高度 - 1
	reg[15:0] cmd_gen_req_scale_x; // 水平缩放比例
	reg[15:0] cmd_gen_req_scale_y; // 竖直缩放比例
	reg[15:0] cmd_gen_req_src_stride; // 源图片行跨度
	reg[15:0] cmd_gen_req_dst_stride; // 目标图片行跨度
	reg[15:0] cmd_gen_req_res_stride; // 结果缓存区行跨度
	reg[31:0] cmd_gen_req_src_baseaddr; // 源图片基地址
	reg[31:0] cmd_gen_req_res_baseaddr; // 结果缓存区基地址
	wire s_cmd_gen_req_axis_valid;
	wire s_cmd_gen_req_axis_ready;
	
	assign s_req_axis_ready = s_cmd_gen_req_axis_ready & req_fifo_full_n;
	
	assign req_fifo_wen = s_req_axis_valid & s_cmd_gen_req_axis_ready;
	assign req_fifo_din = s_req_axis_data;
	
	assign s_cmd_gen_req_axis_data = s_req_axis_data;
	assign s_cmd_gen_req_axis_valid = s_req_axis_valid & req_fifo_full_n;
	
	// 锁存的双线性插值请求
	always @(posedge clk)
	begin
		if(s_cmd_gen_req_axis_valid & s_cmd_gen_req_axis_ready)
			{
				cmd_gen_req_reserved, 
				cmd_gen_req_chn_sub1, 
				cmd_gen_req_sbuf_stride, 
				cmd_gen_req_src_w_sub1, 
				cmd_gen_req_src_h_sub1, 
				cmd_gen_req_dst_w_sub1, 
				cmd_gen_req_dst_h_sub1, 
				cmd_gen_req_scale_x, 
				cmd_gen_req_scale_y, 
				cmd_gen_req_src_stride, 
				cmd_gen_req_dst_stride, 
				cmd_gen_req_res_stride, 
				cmd_gen_req_src_baseaddr, 
				cmd_gen_req_res_baseaddr
			} <= # SIM_DELAY s_cmd_gen_req_axis_data;
	end
	
	/**
	DMA引擎MM2S命令生成
	
	伪代码:
		float ii_d = 1.0f / dst_height * src_height; // 竖直缩放比例
		float ii = 0.0f; // 插值y坐标
		
		for(int di = 0;di <= dst_height - 1;di++){
			int i = (int)ii;
			unsigned char is_i_exceed = i >= src_height - 1;
			int i1 = is_i_exceed ? (src_height - 1):(i + 1);
			
			取源图片第i行, 基地址 = src_baseaddr + i * src_stride
			取源图片第i1行, 基地址 = src_baseaddr + i1 * src_stride
			
			ii += ii_d;
		}
	**/
	wire on_start_mm2s_cmd_gen; // 启动MM2S命令生成(指示)
	wire on_clr_mm2s_cmd_gen_fns; // 清零MM2S命令生成完成标志(指示)
	reg mm2s_cmd_gen_fns; // MM2S命令生成完成(标志)
	reg[15:0] mm2s_cmd_dst_rid; // MM2S命令端目标图片行号(计数器)
	reg mm2s_cmd_access_i1; // MM2S命令端访问第i1行(标志)
	reg[27:0] mm2s_cmd_ii; // MM2S命令端插值y坐标(无符号定点数, 量化精度 = RESIZE_SCALE_QUAZ_N)
	wire[15:0] mm2s_cmd_i; // MM2S命令端取整的插值y坐标
	reg[15:0] mm2s_cmd_i1; // MM2S命令端取整的插值y1坐标
	wire mm2s_cmd_dst_last_row; // MM2S命令端处于目标图片最后1行(标志)
	wire[31:0] mm2s_cmd_s0_data_src_baseaddr; // MM2S命令生成流水线第0级源图片基地址
	wire[15:0] mm2s_cmd_s0_data_src_stride; // MM2S命令生成流水线第0级源图片行跨度
	wire[31:0] mm2s_cmd_s0_data_src_row_ofs; // MM2S命令生成流水线第0级待取行偏移量
	reg mm2s_cmd_s0_valid; // MM2S命令生成流水线第0级valid信号
	wire mm2s_cmd_s0_ready; // MM2S命令生成流水线第0级ready信号
	reg[31:0] mm2s_cmd_s1_data_src_baseaddr; // MM2S命令生成流水线第1级源图片基地址
	reg[15:0] mm2s_cmd_s1_data_src_stride; // MM2S命令生成流水线第1级源图片行跨度
	reg[31:0] mm2s_cmd_s1_data_src_row_ofs; // MM2S命令生成流水线第1级待取行偏移量
	reg mm2s_cmd_s1_valid; // MM2S命令生成流水线第1级valid信号
	wire mm2s_cmd_s1_ready; // MM2S命令生成流水线第1级ready信号
	reg[15:0] mm2s_cmd_s2_data_src_stride; // MM2S命令生成流水线第2级源图片行跨度
	reg[31:0] mm2s_cmd_s2_data_src_row_addr; // MM2S命令生成流水线第2级待取行地址
	reg mm2s_cmd_s2_valid; // MM2S命令生成流水线第2级valid信号
	wire mm2s_cmd_s2_ready; // MM2S命令生成流水线第2级ready信号
	
	assign m_mm2s_cmd_axis_data = {
		{8'h00, mm2s_cmd_s2_data_src_stride}, // 待传输字节数
		mm2s_cmd_s2_data_src_row_addr // 传输首地址
	};
	assign m_mm2s_cmd_axis_user = 1'b0;
	assign m_mm2s_cmd_axis_last = 1'b1;
	assign m_mm2s_cmd_axis_valid = mm2s_cmd_s2_valid;
	
	assign mm2s_cmd_i = mm2s_cmd_ii[RESIZE_SCALE_QUAZ_N+15:RESIZE_SCALE_QUAZ_N];
	assign mm2s_cmd_dst_last_row = mm2s_cmd_dst_rid == cmd_gen_req_dst_h_sub1;
	
	assign mm2s_cmd_s0_data_src_baseaddr = cmd_gen_req_src_baseaddr;
	assign mm2s_cmd_s0_data_src_stride = cmd_gen_req_src_stride;
	assign mm2s_cmd_s0_data_src_row_ofs = 
		(mm2s_cmd_access_i1 ? mm2s_cmd_i1:mm2s_cmd_i) * cmd_gen_req_sbuf_stride;
	
	assign mm2s_cmd_s0_ready = (~mm2s_cmd_s1_valid) | mm2s_cmd_s1_ready;
	assign mm2s_cmd_s1_ready = (~mm2s_cmd_s2_valid) | mm2s_cmd_s2_ready;
	assign mm2s_cmd_s2_ready = m_mm2s_cmd_axis_ready;
	
	// MM2S命令生成完成(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mm2s_cmd_gen_fns <= 1'b0;
		else if((mm2s_cmd_s0_valid & mm2s_cmd_s0_ready & mm2s_cmd_dst_last_row & mm2s_cmd_access_i1) | 
			on_clr_mm2s_cmd_gen_fns
		)
			mm2s_cmd_gen_fns <= # SIM_DELAY 
				(mm2s_cmd_s0_valid & mm2s_cmd_s0_ready & mm2s_cmd_dst_last_row & mm2s_cmd_access_i1) | 
				(~on_clr_mm2s_cmd_gen_fns);
	end
	
	// MM2S命令端目标图片行号(计数器)
	always @(posedge clk)
	begin
		if(on_start_mm2s_cmd_gen | 
			(mm2s_cmd_s0_valid & mm2s_cmd_s0_ready & mm2s_cmd_access_i1)
		)
			mm2s_cmd_dst_rid <= # SIM_DELAY 
				// on_start_mm2s_cmd_gen ? 16'h0000:(mm2s_cmd_dst_rid + 1'b1)
				{16{~on_start_mm2s_cmd_gen}} & (mm2s_cmd_dst_rid + 1'b1);
	end
	// MM2S命令端访问第i1行(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mm2s_cmd_access_i1 <= 1'b0;
		else if(mm2s_cmd_s0_valid & mm2s_cmd_s0_ready)
			mm2s_cmd_access_i1 <= # SIM_DELAY ~mm2s_cmd_access_i1;
	end
	// MM2S命令端插值y坐标
	always @(posedge clk)
	begin
		if(on_start_mm2s_cmd_gen | 
			(mm2s_cmd_s0_valid & mm2s_cmd_s0_ready & mm2s_cmd_access_i1)
		)
			mm2s_cmd_ii <= # SIM_DELAY 
				// on_start_mm2s_cmd_gen ? 28'h000_0000:(mm2s_cmd_ii + cmd_gen_req_scale_y)
				{28{~on_start_mm2s_cmd_gen}} & (mm2s_cmd_ii + cmd_gen_req_scale_y);
	end
	
	// MM2S命令端取整的插值y1坐标
	always @(posedge clk)
	begin
		if(mm2s_cmd_s0_valid & mm2s_cmd_s0_ready & (~mm2s_cmd_access_i1))
			mm2s_cmd_i1 <= # SIM_DELAY 
				(mm2s_cmd_i >= cmd_gen_req_src_h_sub1) ? 
					cmd_gen_req_src_h_sub1:
					(mm2s_cmd_i + 1'b1);
	end
	
	// MM2S命令生成流水线第0级valid信号
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mm2s_cmd_s0_valid <= 1'b0;
		else if(mm2s_cmd_s0_valid ? 
			(mm2s_cmd_s0_valid & mm2s_cmd_s0_ready & mm2s_cmd_dst_last_row & mm2s_cmd_access_i1):
			on_start_mm2s_cmd_gen
		)
			mm2s_cmd_s0_valid <= # SIM_DELAY ~mm2s_cmd_s0_valid;
	end
	// MM2S命令生成流水线第1级valid信号
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mm2s_cmd_s1_valid <= 1'b0;
		else if(mm2s_cmd_s0_ready)
			mm2s_cmd_s1_valid <= # SIM_DELAY mm2s_cmd_s0_valid;
	end
	// MM2S命令生成流水线第2级valid信号
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mm2s_cmd_s2_valid <= 1'b0;
		else if(mm2s_cmd_s1_ready)
			mm2s_cmd_s2_valid <= # SIM_DELAY mm2s_cmd_s1_valid;
	end
	
	// MM2S命令生成流水线第1级源图片基地址, MM2S命令生成流水线第1级源图片行跨度, MM2S命令生成流水线第1级待取行偏移量
	always @(posedge clk)
	begin
		if(mm2s_cmd_s0_valid & mm2s_cmd_s0_ready)
			{mm2s_cmd_s1_data_src_baseaddr, mm2s_cmd_s1_data_src_stride, mm2s_cmd_s1_data_src_row_ofs} <= # SIM_DELAY 
				{mm2s_cmd_s0_data_src_baseaddr, mm2s_cmd_s0_data_src_stride, mm2s_cmd_s0_data_src_row_ofs};
	end
	
	// MM2S命令生成流水线第2级源图片行跨度, MM2S命令生成流水线第2级待取行地址
	always @(posedge clk)
	begin
		if(mm2s_cmd_s1_valid & mm2s_cmd_s1_ready)
		begin
			mm2s_cmd_s2_data_src_stride <= # SIM_DELAY mm2s_cmd_s1_data_src_stride;
			mm2s_cmd_s2_data_src_row_addr <= # SIM_DELAY mm2s_cmd_s1_data_src_baseaddr + mm2s_cmd_s1_data_src_row_ofs;
		end
	end
	
	/** DMA引擎S2MM命令生成 **/
	wire on_start_s2mm_cmd_gen; // 启动S2MM命令生成(指示)
	wire on_clr_s2mm_cmd_gen_fns; // 清零S2MM命令生成完成标志(指示)
	reg s2mm_cmd_gen_fns; // S2MM命令生成完成(标志)
	reg[31:0] dma_s2mm_baseaddr; // S2MM传输基地址
	reg dma_s2mm_valid; // S2MM传输valid信号
	reg[15:0] s2mm_cmd_dst_rid; // S2MM命令端目标图片行号(计数器)
	wire s2mm_cmd_dst_last_row; // S2MM命令端处于目标图片最后1行(标志)
	
	assign m_s2mm_cmd_axis_data = {
		{8'h00, cmd_gen_req_dst_stride}, // 待传输字节数
		dma_s2mm_baseaddr // 传输首地址
	};
	assign m_s2mm_cmd_axis_user = 1'b0;
	assign m_s2mm_cmd_axis_valid = dma_s2mm_valid;
	
	assign s2mm_cmd_dst_last_row = s2mm_cmd_dst_rid == cmd_gen_req_dst_h_sub1;
	
	// S2MM命令生成完成(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			s2mm_cmd_gen_fns <= 1'b0;
		else if((m_s2mm_cmd_axis_valid & m_s2mm_cmd_axis_ready & s2mm_cmd_dst_last_row) | 
			on_clr_s2mm_cmd_gen_fns
		)
			s2mm_cmd_gen_fns <= # SIM_DELAY 
				(m_s2mm_cmd_axis_valid & m_s2mm_cmd_axis_ready & s2mm_cmd_dst_last_row) | 
				(~on_clr_s2mm_cmd_gen_fns);
	end
	
	// S2MM传输基地址
	always @(posedge clk)
	begin
		if(on_start_s2mm_cmd_gen | 
			(m_s2mm_cmd_axis_valid & m_s2mm_cmd_axis_ready)
		)
			dma_s2mm_baseaddr <= # SIM_DELAY 
				on_start_s2mm_cmd_gen ? 
					cmd_gen_req_res_baseaddr:
					(dma_s2mm_baseaddr + cmd_gen_req_res_stride);
	end
	// S2MM传输valid信号
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			dma_s2mm_valid <= 1'b0;
		else if(dma_s2mm_valid ? 
			(m_s2mm_cmd_axis_valid & m_s2mm_cmd_axis_ready & s2mm_cmd_dst_last_row):
			on_start_s2mm_cmd_gen
		)
			dma_s2mm_valid <= # SIM_DELAY ~dma_s2mm_valid;
	end
	
	// S2MM命令端目标图片行号(计数器)
	always @(posedge clk)
	begin
		if(on_start_s2mm_cmd_gen | 
			(m_s2mm_cmd_axis_valid & m_s2mm_cmd_axis_ready)
		)
			s2mm_cmd_dst_rid <= # SIM_DELAY 
				// on_start_s2mm_cmd_gen ? 16'h0000:(s2mm_cmd_dst_rid + 1'b1)
				{16{~on_start_s2mm_cmd_gen}} & (s2mm_cmd_dst_rid + 1'b1);
	end
	
	/** 双线性插值请求处理流程控制 **/
	reg[3:0] resize_req_sts; // 双线性插值请求处理状态
	
	assign s_cmd_gen_req_axis_ready = resize_req_sts[RESIZE_REQ_STS_IDLE_ID];
	
	assign on_start_mm2s_cmd_gen = resize_req_sts[RESIZE_REQ_STS_START_ID];
	assign on_clr_mm2s_cmd_gen_fns = resize_req_sts[RESIZE_REQ_STS_DONE_ID];
	
	assign on_start_s2mm_cmd_gen = resize_req_sts[RESIZE_REQ_STS_START_ID];
	assign on_clr_s2mm_cmd_gen_fns = resize_req_sts[RESIZE_REQ_STS_DONE_ID];
	
	// 双线性插值请求处理状态
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			resize_req_sts <= 4'b0001 << RESIZE_REQ_STS_IDLE_ID;
		else if(
			(resize_req_sts[RESIZE_REQ_STS_IDLE_ID] & s_cmd_gen_req_axis_valid) | 
			resize_req_sts[RESIZE_REQ_STS_START_ID] | 
			(resize_req_sts[RESIZE_REQ_STS_PROCESSING_ID] & mm2s_cmd_gen_fns & s2mm_cmd_gen_fns) | 
			resize_req_sts[RESIZE_REQ_STS_DONE_ID]
		)
			resize_req_sts <= # SIM_DELAY {resize_req_sts[2:0], resize_req_sts[3]};
	end
	
endmodule
