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
本模块: 帧缓存控制

描述:
(1)帧读取
产生MM2S命令, MM2S数据流 -> 输出视频流
帧缓存未启动时输出{PIX_WIDTH{1'b1}}
提前若干行检查帧缓存是否启动和下一帧是否已处理, 以确定是否要开始视频输出和是否要重复当前帧

(2)帧写入
产生S2MM命令, 输入视频流 -> S2MM数据流
提前若干行检查下一帧是否未填充, 以确定是否要忽略输入视频流

帧的生命周期: 未填充 -> 已填充 -> 已处理

注意：
帧缓存区最大存储帧数必须>=3

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/02/21
********************************************************************/


module frame_buffer_ctrl #(
	parameter ONLY_FRAME_RD = "false", // 是否仅启用读像素通道
	parameter integer PIX_WIDTH = 16, // 像素位宽
	parameter integer STREAM_WIDTH = 32, // 数据流位宽
	parameter integer FRAME_W = 1920, // 帧宽度(以像素个数计)
	parameter integer FRAME_H = 1080, // 帧高度(以像素个数计)
	parameter integer FRAME_SIZE = FRAME_W * FRAME_H * 2, // 帧大小(以字节计, 必须<2^24)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// 使能信号
	input wire en_frame_buffer,
	
	// 运行时参数
	input wire[31:0] frame_buffer_baseaddr, // 帧缓存区基地址
	input wire[2:0] frame_buffer_max_store_n_sub1, // 帧缓存区最大存储帧数 - 1
	
	// 帧处理控制
	input wire frame_processed, // 当前帧已处理标志(注意: 取上升沿!)
	output wire frame_filled, // 当前帧已填充标志(注意: 取上升沿!)
	output wire frame_fetched, // 当前帧已取走标志(注意: 取上升沿!)
	
	// MM2S命令(AXIS主机)
	output wire[55:0] m_mm2s_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire m_mm2s_cmd_axis_user, // {固定(1'b1)/递增(1'b0)传输(1bit)}
	                                  // const -> 1'b0
	output wire m_mm2s_cmd_axis_last, // 帧尾标志
	                                  // const -> 1'b1
	output wire m_mm2s_cmd_axis_valid,
	input wire m_mm2s_cmd_axis_ready,	
	// 输出视频流(AXIS主机)
	output wire[PIX_WIDTH-1:0] m_vout_axis_data,
    output wire m_vout_axis_last, // 行尾标志
    output wire m_vout_axis_valid,
    input wire m_vout_axis_ready,
	// MM2S数据流(AXIS从机)
	input wire[STREAM_WIDTH-1:0] s_mm2s_axis_data,
	input wire[STREAM_WIDTH/8-1:0] s_mm2s_axis_keep, // ignored
	input wire[2:0] s_mm2s_axis_user, // {读请求最后1次传输标志(1bit), 
	                                  //     错误类型(2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR)}
									  // ignored
	input wire s_mm2s_axis_last, // ignored
	input wire s_mm2s_axis_valid,
	output wire s_mm2s_axis_ready,
	
	// S2MM命令(AXIS主机)
	output wire[55:0] m_s2mm_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire m_s2mm_cmd_axis_user, // {固定(1'b1)/递增(1'b0)传输(1bit)}
	                                  // const -> 1'b0
	output wire m_s2mm_cmd_axis_valid,
	input wire m_s2mm_cmd_axis_ready,
	// 输入视频流(AXIS从机)
	input wire[PIX_WIDTH-1:0] s_vin_axis_data,
	input wire s_vin_axis_user, // 帧首标志
	                            // ignored
	input wire s_vin_axis_last, // 行尾标志
	input wire s_vin_axis_valid,
	output wire s_vin_axis_ready,
	// S2MM数据流(AXIS主机)
	output wire[STREAM_WIDTH-1:0] m_s2mm_axis_data,
	output wire[STREAM_WIDTH/8-1:0] m_s2mm_axis_keep, // const -> {(STREAM_WIDTH/8){1'b1}}
	output wire m_s2mm_axis_last,
	output wire m_s2mm_axis_valid,
	input wire m_s2mm_axis_ready
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
	
	/** 内部配置 **/
	localparam integer MM2S_CMD_CHECK_RID = FRAME_H - 16; // MM2S命令端检查点行编号
	localparam integer S2MM_CMD_CHECK_RID = FRAME_H - 16; // S2MM命令端检查点行编号
	
	/** MM2S数据流位宽变换(STREAM_WIDTH -> PIX_WIDTH) **/
	wire[PIX_WIDTH-1:0] m_mm2s_axis_data;
	wire m_mm2s_axis_valid;
	wire m_mm2s_axis_ready;
	
	axis_dw_cvt #(
		.slave_data_width(STREAM_WIDTH),
		.master_data_width(PIX_WIDTH),
		.slave_user_width_foreach_byte(1),
		.en_keep("false"),
		.en_last("false"),
		.en_out_isolation("true"),
		.simulation_delay(SIM_DELAY)
	)mm2s_dw_cvt_u(
		.clk(clk),
		.rst_n(resetn),
		
		.s_axis_data(s_mm2s_axis_data),
		.s_axis_keep(),
		.s_axis_user(),
		.s_axis_last(),
		.s_axis_valid(s_mm2s_axis_valid),
		.s_axis_ready(s_mm2s_axis_ready),
		
		.m_axis_data(m_mm2s_axis_data),
		.m_axis_keep(),
		.m_axis_user(),
		.m_axis_last(),
		.m_axis_valid(m_mm2s_axis_valid),
		.m_axis_ready(m_mm2s_axis_ready)
	);
	
	/** S2MM数据流位宽变换(PIX_WIDTH -> STREAM_WIDTH) **/
	wire[PIX_WIDTH-1:0] s_s2mm_axis_data;
	wire s_s2mm_axis_last;
	wire s_s2mm_axis_valid;
	wire s_s2mm_axis_ready;
	
	assign m_s2mm_axis_keep = {(STREAM_WIDTH/8){1'b1}};
	
	axis_dw_cvt #(
		.slave_data_width(PIX_WIDTH),
		.master_data_width(STREAM_WIDTH),
		.slave_user_width_foreach_byte(1),
		.en_keep("false"),
		.en_last("true"),
		.en_out_isolation("true"),
		.simulation_delay(SIM_DELAY)
	)s2mm_dw_cvt_u(
		.clk(clk),
		.rst_n(resetn),
		
		.s_axis_data(s_s2mm_axis_data),
		.s_axis_keep(),
		.s_axis_user(),
		.s_axis_last(s_s2mm_axis_last),
		.s_axis_valid(s_s2mm_axis_valid),
		.s_axis_ready(s_s2mm_axis_ready),
		
		.m_axis_data(m_s2mm_axis_data),
		.m_axis_keep(),
		.m_axis_user(),
		.m_axis_last(m_s2mm_axis_last),
		.m_axis_valid(m_s2mm_axis_valid),
		.m_axis_ready(m_s2mm_axis_ready)
	);
	
	/** 帧处理控制 **/
	reg frame_processed_d; // 延迟1clk的当前帧已处理标志
	wire on_frame_processed; // 当前帧已处理指示
	wire frame_processing_wen; // 帧处理写使能
	reg[7:0] frame_processing_ptr; // 帧处理指针
	wire[7:0] frame_processing_ptr_add1; // 帧处理指针 + 1
	reg[7:0] frame_processed_vec; // 帧已处理(标志向量)
	reg frame_filled_r; // 当前帧已填充标志
	reg[9:0] frame_filled_flag_ext_cnt; // 当前帧已填充标志展宽计数器
	reg frame_fetched_r; // 当前帧已取走标志
	reg[9:0] frame_fetched_flag_ext_cnt; // 当前帧已取走标志展宽计数器
	
	assign frame_filled = frame_filled_r;
	assign frame_fetched = frame_fetched_r;
	
	assign on_frame_processed = frame_processed & (~frame_processed_d);
	assign frame_processing_ptr_add1 = 
		(|(frame_processing_ptr & (8'b0000_0001 << frame_buffer_max_store_n_sub1))) ? 
			8'b0000_0001:
			{frame_processing_ptr[6:0], frame_processing_ptr[7]};
	
	// 延迟1clk的当前帧已处理标志
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			frame_processed_d <= 1'b0;
		else
			frame_processed_d <= # SIM_DELAY frame_processed;
	end
	
	// 当前帧已填充标志展宽计数器
	always @(posedge clk)
	begin
		frame_filled_flag_ext_cnt <= # SIM_DELAY 
			{10{frame_filled_r}} & (frame_filled_flag_ext_cnt + 1'b1);
	end
	// 当前帧已取走标志展宽计数器
	always @(posedge clk)
	begin
		frame_fetched_flag_ext_cnt <= # SIM_DELAY 
			{10{frame_fetched_r}} & (frame_fetched_flag_ext_cnt + 1'b1);
	end
	
	/** 帧缓存控制 **/
	reg[7:0] frame_filled_vec; // 帧已填充(标志向量)
	wire frame_buffer_wen; // 帧缓存写使能
	wire frame_buffer_nxt_w_filled; // 帧缓存下1个待写帧已填充(标志)
	reg[7:0] frame_buffer_wptr; // 帧缓存写指针
	wire[7:0] frame_buffer_wptr_add1; // 帧缓存写指针 + 1
	wire frame_buffer_ren; // 帧缓存读使能
	wire frame_buffer_nxt_r_processed; // 帧缓存下1个待读帧已处理(标志)
	reg[7:0] frame_buffer_rptr; // 帧缓存读指针
	wire[7:0] frame_buffer_rptr_add1; // 帧缓存读指针 + 1
	
	assign frame_processing_wen = on_frame_processed & 
		((ONLY_FRAME_RD == "true") ? 
			((~|(frame_processing_ptr & frame_processed_vec))):
			(|(frame_processing_ptr & frame_filled_vec))
		);
	
	assign frame_buffer_wptr_add1 = 
		(|(frame_buffer_wptr & (8'b0000_0001 << frame_buffer_max_store_n_sub1))) ? 
			8'b0000_0001:
			{frame_buffer_wptr[6:0], frame_buffer_wptr[7]};
	assign frame_buffer_rptr_add1 = 
		(|(frame_buffer_rptr & (8'b0000_0001 << frame_buffer_max_store_n_sub1))) ? 
			8'b0000_0001:
			{frame_buffer_rptr[6:0], frame_buffer_rptr[7]};
	
	assign frame_buffer_nxt_w_filled = |(frame_filled_vec & frame_buffer_wptr_add1);
	assign frame_buffer_nxt_r_processed = |(frame_processed_vec & frame_buffer_rptr_add1);
	
	// 帧处理指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			frame_processing_ptr <= 8'b0000_0001;
		else if(frame_processing_wen)
			frame_processing_ptr <= # SIM_DELAY frame_processing_ptr_add1;
	end
	
	// 帧已处理(标志向量)
	genvar frame_processed_vec_i;
	generate
		for(frame_processed_vec_i = 0;frame_processed_vec_i < 8;frame_processed_vec_i = frame_processed_vec_i + 1)
		begin
			always @(posedge clk or negedge resetn)
			begin
				if(~resetn)
					frame_processed_vec[frame_processed_vec_i] <= 1'b0;
				else if((frame_processing_wen & frame_processing_ptr[frame_processed_vec_i]) | 
					(frame_buffer_ren & frame_buffer_rptr[frame_processed_vec_i])
				)
					frame_processed_vec[frame_processed_vec_i] <= # SIM_DELAY 
						(frame_processing_wen & frame_processing_ptr[frame_processed_vec_i]) | 
						(~(frame_buffer_ren & frame_buffer_rptr[frame_processed_vec_i]));
			end
		end
	endgenerate
	
	// 当前帧已填充标志
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			frame_filled_r <= 1'b0;
		else if(frame_filled_r ? 
			(&frame_filled_flag_ext_cnt):
			frame_buffer_wen
		)
			frame_filled_r <= # SIM_DELAY ~frame_filled_r;
	end
	// 当前帧已取走标志
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			frame_fetched_r <= 1'b0;
		else if(frame_fetched_r ? 
			(&frame_fetched_flag_ext_cnt):
			frame_buffer_ren
		)
			frame_fetched_r <= # SIM_DELAY ~frame_fetched_r;
	end
	
	// 帧已填充(标志向量)
	genvar frame_filled_vec_i;
	generate
		for(frame_filled_vec_i = 0;frame_filled_vec_i < 8;frame_filled_vec_i = frame_filled_vec_i + 1)
		begin
			always @(posedge clk or negedge resetn)
			begin
				if(~resetn)
					frame_filled_vec[frame_filled_vec_i] <= 1'b0;
				else if((frame_buffer_wen & frame_buffer_wptr[frame_filled_vec_i]) | 
					(frame_buffer_ren & frame_buffer_rptr[frame_filled_vec_i])
				)
					frame_filled_vec[frame_filled_vec_i] <= # SIM_DELAY 
						(frame_buffer_wen & frame_buffer_wptr[frame_filled_vec_i]) | 
						(~(frame_buffer_ren & frame_buffer_rptr[frame_filled_vec_i]));
			end
		end
	endgenerate
	
	// 帧缓存写指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			frame_buffer_wptr <= 8'b0000_0001;
		else if(frame_buffer_wen)
			frame_buffer_wptr <= # SIM_DELAY frame_buffer_wptr_add1;
	end
	// 帧缓存读指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			frame_buffer_rptr <= 8'b0000_0001;
		else if(frame_buffer_ren)
			frame_buffer_rptr <= # SIM_DELAY frame_buffer_rptr_add1;
	end
	
	/** 输出视频流 **/
	reg[clogb2(FRAME_W-1):0] vout_cid; // 输出视频流列编号
	reg[clogb2(FRAME_H-1):0] vout_rid; // 输出视频流行编号
	reg vout_prepare_start; // 准备开始视频输出(标志)
	reg vout_started; // 开始视频输出(标志)
	reg vout_to_repeat_frame; // 重复当前帧(标志)
	
	assign m_vout_axis_data = {PIX_WIDTH{~vout_started}} | m_mm2s_axis_data;
	assign m_vout_axis_last = vout_cid == (FRAME_W - 1);
	assign m_vout_axis_valid = (~vout_started) | m_mm2s_axis_valid;
	
	assign m_mm2s_axis_ready = vout_started & m_vout_axis_ready;
	
	assign frame_buffer_ren = 
		m_vout_axis_valid & m_vout_axis_ready & m_vout_axis_last & (vout_rid == (FRAME_H - 1)) & 
		(~vout_to_repeat_frame);
	
	// 输出视频流列编号
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			vout_cid <= 0;
		else if(m_vout_axis_valid & m_vout_axis_ready)
			vout_cid <= # SIM_DELAY {(clogb2(FRAME_W-1)+1){~m_vout_axis_last}} & (vout_cid + 1);
	end
	// 输出视频流行编号
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			vout_rid <= 0;
		else if(m_vout_axis_valid & m_vout_axis_ready & m_vout_axis_last)
			vout_rid <= # SIM_DELAY {(clogb2(FRAME_H-1)+1){vout_rid != (FRAME_H - 1)}} & (vout_rid + 1);
	end
	
	// 准备开始视频输出(标志)
	always @(posedge clk)
	begin
		if(m_vout_axis_valid & m_vout_axis_ready & m_vout_axis_last & (vout_rid == MM2S_CMD_CHECK_RID))
			// 提前若干行检查是否要开始视频输出
			vout_prepare_start <= # SIM_DELAY en_frame_buffer & frame_processed_vec[0];
	end
	// 开始视频输出(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			vout_started <= 1'b0;
		else if((~vout_started) & 
			m_vout_axis_valid & m_vout_axis_ready & m_vout_axis_last & (vout_rid == (FRAME_H - 1))
		)
			vout_started <= # SIM_DELAY vout_prepare_start;
	end
	
	// 重复当前帧(标志)
	always @(posedge clk)
	begin
		if(m_vout_axis_valid & m_vout_axis_ready & m_vout_axis_last & (vout_rid == MM2S_CMD_CHECK_RID))
			// 提前若干行检查是否要重复当前帧
			vout_to_repeat_frame <= # SIM_DELAY (~frame_buffer_nxt_r_processed) | (~vout_started);
	end
	
	/** 输入视频流 **/
	reg[clogb2(FRAME_H-1):0] vin_rid; // 输入视频流行编号
	reg prepare_to_ignore_vin; // 准备忽略输入视频流(标志)
	reg to_ignore_vin; // 忽略输入视频流(标志)
	
	assign s_vin_axis_ready = (ONLY_FRAME_RD == "true") | to_ignore_vin | s_s2mm_axis_ready;
	
	assign s_s2mm_axis_data = (ONLY_FRAME_RD == "true") ? {PIX_WIDTH{1'b0}}:s_vin_axis_data;
	assign s_s2mm_axis_last = (ONLY_FRAME_RD == "false") & s_vin_axis_last & (vin_rid == (FRAME_H - 1));
	assign s_s2mm_axis_valid = (ONLY_FRAME_RD == "false") & (~to_ignore_vin) & s_vin_axis_valid;
	
	assign frame_buffer_wen = 
		(ONLY_FRAME_RD == "false") & 
		s_vin_axis_valid & s_vin_axis_ready & s_vin_axis_last & (vin_rid == (FRAME_H - 1)) & 
		(~to_ignore_vin);
	
	// 输入视频流行编号
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			vin_rid <= 0;
		else if(s_vin_axis_valid & s_vin_axis_ready & s_vin_axis_last)
			vin_rid <= # SIM_DELAY {(clogb2(FRAME_H-1)+1){vin_rid != (FRAME_H - 1)}} & (vin_rid + 1);
	end
	
	// 准备忽略输入视频流(标志)
	always @(posedge clk)
	begin
		if(s_vin_axis_valid & s_vin_axis_ready & s_vin_axis_last & (vin_rid == S2MM_CMD_CHECK_RID))
			prepare_to_ignore_vin <= # SIM_DELAY ~(en_frame_buffer & (~frame_buffer_nxt_w_filled));
	end
	// 忽略输入视频流(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			to_ignore_vin <= 1'b1;
		else if(s_vin_axis_valid & s_vin_axis_ready & s_vin_axis_last & (vin_rid == (FRAME_H - 1)))
			to_ignore_vin <= # SIM_DELAY prepare_to_ignore_vin;
	end
	
	/** MM2S命令 **/
	reg[31:0] mm2s_baseaddr; // MM2S命令端当前帧传输基地址
	wire[31:0] mm2s_baseaddr_nxf; // MM2S命令端下一帧传输基地址
	reg mm2s_cmd_valid; // MM2S命令端的valid信号
	wire send_mm2s_cmd; // 发送MM2S命令(指示)
	
	assign m_mm2s_cmd_axis_data = {
		FRAME_SIZE[23:0],
		mm2s_baseaddr
	};
	assign m_mm2s_cmd_axis_user = 1'b0;
	assign m_mm2s_cmd_axis_last = 1'b1;
	assign m_mm2s_cmd_axis_valid = mm2s_cmd_valid;
	
	assign mm2s_baseaddr_nxf = 
		(|(frame_buffer_rptr & (8'b0000_0001 << frame_buffer_max_store_n_sub1))) ? 
			frame_buffer_baseaddr:
			(mm2s_baseaddr + FRAME_SIZE[23:0]);
	assign send_mm2s_cmd = 
		m_vout_axis_valid & m_vout_axis_ready & m_vout_axis_last & (vout_rid == MM2S_CMD_CHECK_RID) & 
		(vout_started | (en_frame_buffer & frame_processed_vec[0]));
	
	// MM2S命令端当前帧传输基地址
	always @(posedge clk)
	begin
		if(send_mm2s_cmd & ((~vout_started) | frame_buffer_nxt_r_processed))
		begin
			mm2s_baseaddr <= # SIM_DELAY vout_started ? 
				mm2s_baseaddr_nxf:
				frame_buffer_baseaddr;
		end
	end
	
	// MM2S命令端的valid信号
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mm2s_cmd_valid <= 1'b0;
		else if(mm2s_cmd_valid ? m_mm2s_cmd_axis_ready:send_mm2s_cmd)
			mm2s_cmd_valid <= # SIM_DELAY ~mm2s_cmd_valid;
	end
	
	/** S2MM命令 **/
	reg[31:0] s2mm_baseaddr; // S2MM命令端当前帧传输基地址
	wire[31:0] s2mm_baseaddr_nxf; // S2MM命令端下一帧传输基地址
	reg s2mm_cmd_valid; // S2MM命令端的valid信号
	wire send_s2mm_cmd; // 发送S2MM命令(指示)
	
	assign m_s2mm_cmd_axis_data = {
		FRAME_SIZE[23:0],
		(ONLY_FRAME_RD == "true") ? 32'd0:s2mm_baseaddr
	};
	assign m_s2mm_cmd_axis_user = 1'b0;
	assign m_s2mm_cmd_axis_valid = (ONLY_FRAME_RD == "false") & s2mm_cmd_valid;
	
	assign s2mm_baseaddr_nxf = 
		(|(frame_buffer_wptr & (8'b0000_0001 << frame_buffer_max_store_n_sub1))) ? 
			frame_buffer_baseaddr:
			(s2mm_baseaddr + FRAME_SIZE[23:0]);
	assign send_s2mm_cmd = 
		s_vin_axis_valid & s_vin_axis_ready & s_vin_axis_last & (vin_rid == S2MM_CMD_CHECK_RID) & 
		en_frame_buffer & (~frame_buffer_nxt_w_filled);
	
	// S2MM命令端当前帧传输基地址
	always @(posedge clk)
	begin
		if(~en_frame_buffer)
			s2mm_baseaddr <= # SIM_DELAY frame_buffer_baseaddr;
		else if(send_s2mm_cmd)
			s2mm_baseaddr <= # SIM_DELAY s2mm_baseaddr_nxf;
	end
	
	// S2MM命令端的valid信号
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			s2mm_cmd_valid <= 1'b0;
		else if(s2mm_cmd_valid ? m_s2mm_cmd_axis_ready:send_s2mm_cmd)
			s2mm_cmd_valid <= # SIM_DELAY ~s2mm_cmd_valid;
	end
	
endmodule
