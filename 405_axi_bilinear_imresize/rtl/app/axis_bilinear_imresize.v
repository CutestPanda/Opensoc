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
本模块: AXIS双线性插值计算模块

描述:
处理双线性插值请求, 计算插值系数, 读源图片缓存MEM, 进行加权求和来生成插值像素

6级流水线 ->
	clk         内容
	 0   生成源图片访问地址
	     生成插值系数乘法器操作数:
			float u1_v1 = (1 - u) * (1 - v), u_v1 = u * (1 - v);
			float u1_v = (1 - u) * v, u_v = u * v;
	 1   源图片缓存MEM读使能
	     插值系数乘法器计算
     2   源图片缓存MEM读延迟
	     插值系数乘法器延迟
     3   插值像素乘法器计算:
			u1_v1 * 源像素(i, j), u_v1 * 源像素(i1, j)
			u1_v * 源像素(i, j1), u_v * 源像素(i1, j1)
	 4   生成插值像素部分和:
			u1_v1 * 源像素(i, j) + u_v1 * 源像素(i1, j)
			u1_v * 源像素(i, j1) + u_v * 源像素(i1, j1)
	 5   生成插值像素:
			累加部分和
	 6   计算结果缓存fifo写使能

注意：
无

协议:
AXIS MASTER/SLAVE
VFIFO MASTER
MEM MASTER

作者: 陈家耀
日期: 2025/02/23
********************************************************************/


module axis_bilinear_imresize #(
	parameter integer STREAM_WIDTH = 32, // 数据流位宽(8 | 16 | 32 | 64)
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
	
	// 源图片缓存虚拟fifo读端口
	output wire src_img_vfifo_ren,
	input wire src_img_vfifo_empty_n,
	
	// 源图片缓存MEM读端口
	output wire src_img_mem_ren,
	output wire[15:0] src_img_mem_raddr, // 以字节计
	input wire[7:0] src_img_mem_dout_0,
	input wire[7:0] src_img_mem_dout_1,
	
	// 计算结果流(AXIS主机)
	output wire[STREAM_WIDTH-1:0] m_res_axis_data,
	output wire[STREAM_WIDTH/8-1:0] m_res_axis_keep,
	output wire m_res_axis_last, // 行尾标志
	output wire m_res_axis_valid,
	input wire m_res_axis_ready,
	
	// 缩放控制
	output wire resize_fns // 缩放完成标志(注意: 取上升沿!)
);
	
	/** 内部配置 **/
	// 双线性插值请求的数据位宽
	localparam integer REQ_WIDTH = 216;
	// 双线性插值请求处理状态常量
	localparam integer RESIZE_REQ_STS_IDLE_ID = 0;
	localparam integer RESIZE_REQ_STS_START_ID = 1;
	localparam integer RESIZE_REQ_STS_PROCESSING_ID = 2;
	localparam integer RESIZE_REQ_STS_DONE_ID = 3;
	
	/** 锁存的双线性插值请求 **/
	reg[5:0] resize_cal_req_reserved; // 保留位
	reg[1:0] resize_cal_req_chn_sub1; // 图片通道数 - 1
	reg[15:0] resize_cal_req_sbuf_stride; // 源缓存区行跨度
	reg[15:0] resize_cal_req_src_w_sub1; // 源图片宽度 - 1
	reg[15:0] resize_cal_req_src_h_sub1; // 源图片高度 - 1
	reg[15:0] resize_cal_req_dst_w_sub1; // 目标图片宽度 - 1
	reg[15:0] resize_cal_req_dst_h_sub1; // 目标图片高度 - 1
	reg[15:0] resize_cal_req_scale_x; // 水平缩放比例
	reg[15:0] resize_cal_req_scale_y; // 竖直缩放比例
	reg[15:0] resize_cal_req_src_stride; // 源图片行跨度
	reg[15:0] resize_cal_req_dst_stride; // 目标图片行跨度
	reg[15:0] resize_cal_req_res_stride; // 结果缓存区行跨度
	reg[31:0] resize_cal_req_src_baseaddr; // 源图片基地址
	reg[31:0] resize_cal_req_res_baseaddr; // 结果缓存区基地址
	
	// 锁存的双线性插值请求
	always @(posedge clk)
	begin
		if(s_req_axis_valid & s_req_axis_ready)
			{
				resize_cal_req_reserved, 
				resize_cal_req_chn_sub1, 
				resize_cal_req_sbuf_stride, 
				resize_cal_req_src_w_sub1, 
				resize_cal_req_src_h_sub1, 
				resize_cal_req_dst_w_sub1, 
				resize_cal_req_dst_h_sub1, 
				resize_cal_req_scale_x, 
				resize_cal_req_scale_y, 
				resize_cal_req_src_stride, 
				resize_cal_req_dst_stride, 
				resize_cal_req_res_stride, 
				resize_cal_req_src_baseaddr, 
				resize_cal_req_res_baseaddr
			} <= # SIM_DELAY s_req_axis_data;
	end
	
	/** 计算结果位宽变换(8 -> STREAM_WIDTH) **/
	// AXIS从机
	wire[7:0] s_res_dw_cvt_axis_data;
	wire s_res_dw_cvt_axis_last; // 行尾标志
	wire s_res_dw_cvt_axis_valid;
	wire s_res_dw_cvt_axis_ready;
	// AXIS主机
	wire[STREAM_WIDTH-1:0] m_res_dw_cvt_axis_data;
	wire[STREAM_WIDTH/8-1:0] m_res_dw_cvt_axis_keep;
	wire m_res_dw_cvt_axis_last; // 行尾标志
	wire m_res_dw_cvt_axis_valid;
	wire m_res_dw_cvt_axis_ready;
	
	assign m_res_axis_data = m_res_dw_cvt_axis_data;
	assign m_res_axis_keep = m_res_dw_cvt_axis_keep;
	assign m_res_axis_last = m_res_dw_cvt_axis_last;
	assign m_res_axis_valid = m_res_dw_cvt_axis_valid;
	assign m_res_dw_cvt_axis_ready = m_res_axis_ready;
	
	axis_dw_cvt #(
		.slave_data_width(8),
		.master_data_width(STREAM_WIDTH),
		.slave_user_width_foreach_byte(1),
		.en_keep("true"),
		.en_last("true"),
		.en_out_isolation("true"),
		.simulation_delay(SIM_DELAY)
	)axis_dw_cvt_u(
		.clk(clk),
		.rst_n(resetn),
		
		.s_axis_data(s_res_dw_cvt_axis_data),
		.s_axis_keep(1'b1),
		.s_axis_user(1'bx),
		.s_axis_last(s_res_dw_cvt_axis_last),
		.s_axis_valid(s_res_dw_cvt_axis_valid),
		.s_axis_ready(s_res_dw_cvt_axis_ready),
		
		.m_axis_data(m_res_dw_cvt_axis_data),
		.m_axis_keep(m_res_dw_cvt_axis_keep),
		.m_axis_user(),
		.m_axis_last(m_res_dw_cvt_axis_last),
		.m_axis_valid(m_res_dw_cvt_axis_valid),
		.m_axis_ready(m_res_dw_cvt_axis_ready)
	);
	
	/** 计算结果缓存fifo **/
	// fifo写端口
	wire res_fifo_wen;
	wire[7:0] res_fifo_din_data;
	wire res_fifo_din_last; // 行尾标志
	wire res_fifo_full_n;
	wire res_fifo_almost_full_n;
	// fifo读端口
	wire res_fifo_ren;
	wire[7:0] res_fifo_dout_data;
	wire res_fifo_dout_last; // 行尾标志
	wire res_fifo_empty_n;
	
	assign s_res_dw_cvt_axis_data = res_fifo_dout_data;
	assign s_res_dw_cvt_axis_last = res_fifo_dout_last;
	assign s_res_dw_cvt_axis_valid = res_fifo_empty_n;
	assign res_fifo_ren = s_res_dw_cvt_axis_ready;
	
	ram_fifo_wrapper #(
		.fwft_mode("true"),
		.ram_type("bram"),
		.en_bram_reg("false"),
		.fifo_depth(2048),
		.fifo_data_width(9),
		.full_assert_polarity("low"),
		.empty_assert_polarity("low"),
		.almost_full_assert_polarity("low"),
		.almost_empty_assert_polarity("no"),
		.en_data_cnt("false"),
		.almost_full_th(2000),
		.almost_empty_th(5),
		.simulation_delay(SIM_DELAY)
	)res_fifo_u(
		.clk(clk),
		.rst_n(resetn),
		
		.fifo_wen(res_fifo_wen),
		.fifo_din({res_fifo_din_data, res_fifo_din_last}),
		.fifo_full_n(res_fifo_full_n),
		.fifo_almost_full_n(res_fifo_almost_full_n),
		
		.fifo_ren(res_fifo_ren),
		.fifo_dout({res_fifo_dout_data, res_fifo_dout_last}),
		.fifo_empty_n(res_fifo_empty_n)
	);
	
	/**
	源图片访问地址生成
	
	伪代码:
		float ii_d = 1.0f / dst_height * src_height; // 竖直缩放比例
		float jj_d = 1.0f / dst_width * src_width; // 水平缩放比例
		
		float ii = 0.0f; // 插值y坐标
		float jj; // 插值x坐标
		
		for(int di = 0;di <= dst_height - 1;di++){
			jj = 0.0f;
			
			for (int dj = 0;dj <= dst_width - 1;dj++){
				int j = (int)jj; // 整数部分
				unsigned char is_j_exceed = j >= src_width - 1;
				int j1 = is_j_exceed ? (src_width - 1):(j + 1);
				
				for (int k = 0;k < chn;k++){
					取x坐标为j的源像素(i, j)和(i1, j), 行偏移地址 = j * chn + k
					取x坐标为j1的源像素(i, j1)和(i1, j1), 行偏移地址 = j1 * chn + k
				}
				
				jj += jj_d;
			}
			
			ii += ii_d;
		}
	**/
	wire is_resize_rgb565; // 图片像素格式为rgb565(标志)
	wire on_start_resize_cal; // 启动双线性插值计算(指示)
	wire on_clr_resize_cal_fns; // 清零双线性插值计算完成标志(指示)
	reg resize_cal_fns; // 双线性插值计算完成(标志)
	reg resize_cal_started; // 双线性插值计算已启动(标志)
	wire resize_cal_done; // 双线性插值计算完成(指示)
	reg[15:0] dst_y; // 目标图片y坐标
	reg[15:0] dst_x; // 目标图片x坐标
	reg[1:0] src_k_ofs; // 源图片通道号偏移量
	wire dst_last_row; // 当前处于目标图片最后1行(标志)
	wire dst_last_col; // 当前处于目标图片最后1列(标志)
	wire dst_last_chn; // 当前处于目标图片最后1通道(标志)
	reg is_access_src_x1; // 当前访问源图片x1坐标(标志)
	reg[27:0] src_itplt_ii; // 源图片插值y坐标(无符号定点数, 量化精度 = RESIZE_SCALE_QUAZ_N)
	reg[27:0] src_itplt_jj; // 源图片插值x坐标(无符号定点数, 量化精度 = RESIZE_SCALE_QUAZ_N)
	wire[15:0] src_x; // 源图片x坐标
	reg[15:0] src_x1; // 源图片x1坐标
	reg src_img_mem_ren_r; // 源图片缓存MEM读使能
	reg[15:0] src_img_mem_raddr_r; // 源图片缓存MEM读地址(以字节计)
	
	assign src_img_vfifo_ren = 
		resize_cal_started & res_fifo_almost_full_n & 
		dst_last_col & dst_last_chn & is_access_src_x1;
	
	assign src_img_mem_ren = src_img_mem_ren_r;
	assign src_img_mem_raddr = src_img_mem_raddr_r;
	
	assign is_resize_rgb565 = resize_cal_req_chn_sub1 == 2'b01;
	assign resize_cal_done = 
		resize_cal_started & src_img_vfifo_empty_n & res_fifo_almost_full_n & 
		dst_last_row & dst_last_col & dst_last_chn & is_access_src_x1;
	
	assign dst_last_row = dst_y == resize_cal_req_dst_h_sub1;
	assign dst_last_col = dst_x == resize_cal_req_dst_w_sub1;
	assign dst_last_chn = 
		src_k_ofs == (
			is_resize_rgb565 ? 2'b10:resize_cal_req_chn_sub1
		);
	
	assign src_x = src_itplt_jj[15+RESIZE_SCALE_QUAZ_N:RESIZE_SCALE_QUAZ_N];
	
	// 双线性插值计算完成(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			resize_cal_fns <= 1'b0;
		else if(resize_cal_done | on_clr_resize_cal_fns)
			resize_cal_fns <= # SIM_DELAY resize_cal_done | (~on_clr_resize_cal_fns);
	end
	// 双线性插值计算已启动(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			resize_cal_started <= 1'b0;
		else if(resize_cal_started ? 
			resize_cal_done:
			on_start_resize_cal
		)
			resize_cal_started <= # SIM_DELAY ~resize_cal_started;
	end
	
	// 目标图片y坐标
	always @(posedge clk)
	begin
		if(on_start_resize_cal | 
			(resize_cal_started & src_img_vfifo_empty_n & res_fifo_almost_full_n & 
				dst_last_col & dst_last_chn & is_access_src_x1))
			dst_y <= # SIM_DELAY {16{~on_start_resize_cal}} & (dst_y + 1'b1);
	end
	// 目标图片x坐标
	always @(posedge clk)
	begin
		if(on_start_resize_cal | 
			(resize_cal_started & src_img_vfifo_empty_n & res_fifo_almost_full_n & 
				dst_last_chn & is_access_src_x1))
			dst_x <= # SIM_DELAY {16{~(on_start_resize_cal | dst_last_col)}} & (dst_x + 1'b1);
	end
	// 源图片通道号偏移量
	always @(posedge clk)
	begin
		if(on_start_resize_cal | 
			(resize_cal_started & src_img_vfifo_empty_n & res_fifo_almost_full_n & 
				is_access_src_x1))
			src_k_ofs <= # SIM_DELAY 
				{2{~(on_start_resize_cal | dst_last_chn)}} & 
				(src_k_ofs + 1'b1);
	end
	// 当前访问源图片x1坐标(标志)
	always @(posedge clk)
	begin
		if(on_start_resize_cal | 
			(resize_cal_started & src_img_vfifo_empty_n & res_fifo_almost_full_n))
			is_access_src_x1 <= # SIM_DELAY (~on_start_resize_cal) & (~is_access_src_x1);
	end
	
	// 源图片缓存MEM读使能
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			src_img_mem_ren_r <= 1'b0;
		else
			src_img_mem_ren_r <= # SIM_DELAY resize_cal_started & src_img_vfifo_empty_n & res_fifo_almost_full_n;
	end
	// 源图片缓存MEM读地址
	always @(posedge clk)
	begin
		if(resize_cal_started & src_img_vfifo_empty_n & res_fifo_almost_full_n)
			src_img_mem_raddr_r <= # SIM_DELAY 
				((is_access_src_x1 ? src_x1:src_x) * ({1'b0, resize_cal_req_chn_sub1} + 1'b1)) + 
					((is_resize_rgb565 & src_k_ofs[1]) ? 2'b01:src_k_ofs);
	end
	
	// 源图片插值y坐标
	always @(posedge clk)
	begin
		if(on_start_resize_cal | 
			(resize_cal_started & src_img_vfifo_empty_n & res_fifo_almost_full_n & 
				dst_last_col & dst_last_chn & is_access_src_x1))
			src_itplt_ii <= # SIM_DELAY {28{~on_start_resize_cal}} & (src_itplt_ii + resize_cal_req_scale_y);
	end
	// 源图片插值x坐标
	always @(posedge clk)
	begin
		if(on_start_resize_cal | 
			(resize_cal_started & src_img_vfifo_empty_n & res_fifo_almost_full_n & 
				dst_last_chn & is_access_src_x1))
			src_itplt_jj <= # SIM_DELAY {28{~(on_start_resize_cal | dst_last_col)}} & (src_itplt_jj + resize_cal_req_scale_x);
	end
	
	// 源图片x1坐标
	always @(posedge clk)
	begin
		if(resize_cal_started & src_img_vfifo_empty_n & res_fifo_almost_full_n & (~is_access_src_x1))
			src_x1 <= # SIM_DELAY (src_x >= resize_cal_req_src_w_sub1) ? resize_cal_req_src_w_sub1:(src_x + 1'b1);
	end
	
	/**
	双线性插值加权求和
	
	伪代码:
		对于目标图片的每个像素 -> 
			int i = (int)ii, j = (int)jj; // 整数部分
			float u = ii - i, v = jj - j; // 小数部分
			
			// 插值系数
			float u_v = u * v;
			float u1_v1 = (1 - u) * (1 - v);
			float u1_v = (1 - u) * v;
			float u_v1 = u * (1 - v);
			
			// 加权求和
			float out_pix = u1_v1 * 源像素(i, j)
				+ u1_v * 源像素(i, j1)
				+ u_v1 * 源像素(i1, j)
				+ u_v * 源像素(i1, j1);
	
	说明:
		源图片2x2 ROI分2次取得, 先取源像素(i, j)和(i1, j), 再取源像素(i, j1)和(i1, j1)
	**/
	wire itplt_rate_mul_en; // 插值系数乘法器使能
	reg[RESIZE_SCALE_QUAZ_N:0] itplt_rate_mul_op_a[0:1]; // 插值系数乘法器操作数A(量化精度 = RESIZE_SCALE_QUAZ_N)
	reg[RESIZE_SCALE_QUAZ_N:0] itplt_rate_mul_op_b; // 插值系数乘法器操作数B(量化精度 = RESIZE_SCALE_QUAZ_N)
	reg itplt_rate_mul_res_vld; // 插值系数乘法器计算结果有效(指示)
	reg[RESIZE_SCALE_QUAZ_N*2+1:0] itplt_rate_mul_res[0:1]; // 插值系数乘法器计算结果(量化精度 = RESIZE_SCALE_QUAZ_N * 2)
	reg itplt_rate_vld; // 插值系数有效(指示)
	reg[RESIZE_SCALE_QUAZ_N+3:0] itplt_rate[0:1]; // 插值系数(量化精度 = RESIZE_SCALE_QUAZ_N + 3)
	reg[23:0] src_pix[0:1]; // 源像素
	wire[7:0] src_rgb565_b[0:1]; // rgb565模式下的b通道
	wire[7:0] src_rgb565_g[0:1]; // rgb565模式下的g通道
	wire[7:0] src_rgb565_r[0:1]; // rgb565模式下的r通道
	wire src_pix_vld; // 源像素有效(指示)
	reg[RESIZE_SCALE_QUAZ_N+11:0] itplt_pix_mul_res[0:1]; // 插值像素乘法器计算结果(量化精度 = RESIZE_SCALE_QUAZ_N + 3)
	reg itplt_pix_mul_res_vld; // 插值像素乘法器计算结果有效(指示)
	reg[RESIZE_SCALE_QUAZ_N+12:0] itplt_pix_part_sum; // 插值像素部分和(量化精度 = RESIZE_SCALE_QUAZ_N + 3)
	reg itplt_pix_part_sum_vld; // 插值像素部分和有效(指示)
	reg[RESIZE_SCALE_QUAZ_N+13:0] itplt_pix; // 插值像素(量化精度 = RESIZE_SCALE_QUAZ_N + 3)
	wire[7:0] itplt_pix_to_wt_cur; // 当前待写的插值像素
	reg[7:0] itplt_pix_to_wt_pre; // 上一个待写的插值像素
	reg itplt_pix_loaded; // 插值像素累加已载入(标志)
	reg itplt_pix_vld; // 插值像素有效(指示)
	reg[5:0] dst_rlast_delay_chain; // 行尾标志延迟链
	reg[5:0] is_resize_rgb565_delay_chain; // 图片像素格式为rgb565标志延迟链
	reg[1:0] src_k_ofs_delay_chain[0:5]; // 源图片通道号偏移量延迟链
	
	assign res_fifo_wen = (~(is_resize_rgb565_delay_chain[5] & (src_k_ofs_delay_chain[5] == 2'b00))) & itplt_pix_vld;
	assign res_fifo_din_data = 
		is_resize_rgb565_delay_chain[5] ? 
			(
				src_k_ofs_delay_chain[5][1] ? 
					{itplt_pix_to_wt_pre[4:2], itplt_pix_to_wt_cur[7:3]}:
					{itplt_pix_to_wt_pre[7:3], itplt_pix_to_wt_cur[7:5]}
			):itplt_pix_to_wt_cur;
	assign res_fifo_din_last = dst_rlast_delay_chain[5];
	
	assign itplt_rate_mul_en = src_img_mem_ren_r;
	assign src_pix_vld = itplt_rate_vld;
	
	assign src_rgb565_b[0] = {src_pix[0][7:3], 3'b000};
	assign src_rgb565_b[1] = {src_pix[1][7:3], 3'b000};
	assign src_rgb565_g[0] = {src_pix[0][18:16], src_pix[0][7:5], 2'b00};
	assign src_rgb565_g[1] = {src_pix[1][18:16], src_pix[1][7:5], 2'b00};
	assign src_rgb565_r[0] = {src_pix[0][4:0], 3'b000};
	assign src_rgb565_r[1] = {src_pix[1][4:0], 3'b000};
	
	assign itplt_pix_to_wt_cur = itplt_pix[RESIZE_SCALE_QUAZ_N+10:RESIZE_SCALE_QUAZ_N+3];
	
	// 插值系数乘法器操作数A
	always @(posedge clk)
	begin
		if(resize_cal_started & src_img_vfifo_empty_n & res_fifo_almost_full_n & (~is_access_src_x1))
		begin
			itplt_rate_mul_op_a[0] <= # SIM_DELAY 
				{1'b1, {RESIZE_SCALE_QUAZ_N{1'b0}}} - {1'b0, src_itplt_ii[RESIZE_SCALE_QUAZ_N-1:0]}; // 1 - u
			itplt_rate_mul_op_a[1] <= # SIM_DELAY 
				{1'b0, src_itplt_ii[RESIZE_SCALE_QUAZ_N-1:0]}; // u
		end
	end
	// 插值系数乘法器操作数B
	always @(posedge clk)
	begin
		if(resize_cal_started & src_img_vfifo_empty_n & res_fifo_almost_full_n)
		begin
			itplt_rate_mul_op_b <= # SIM_DELAY 
				is_access_src_x1 ? 
					{1'b0, src_itplt_jj[RESIZE_SCALE_QUAZ_N-1:0]}: // v
					({1'b1, {RESIZE_SCALE_QUAZ_N{1'b0}}} - {1'b0, src_itplt_jj[RESIZE_SCALE_QUAZ_N-1:0]}); // 1 - v
		end
	end
	
	// 插值系数乘法器计算结果
	always @(posedge clk)
	begin
		if(itplt_rate_mul_en)
		begin
			itplt_rate_mul_res[0] <= # SIM_DELAY itplt_rate_mul_op_a[0] * itplt_rate_mul_op_b;
			itplt_rate_mul_res[1] <= # SIM_DELAY itplt_rate_mul_op_a[1] * itplt_rate_mul_op_b;
		end
	end
	
	// 插值系数
	always @(posedge clk)
	begin
		if(itplt_rate_mul_res_vld)
		begin
			itplt_rate[0] <= # SIM_DELAY itplt_rate_mul_res[0][RESIZE_SCALE_QUAZ_N*2:RESIZE_SCALE_QUAZ_N-3];
			itplt_rate[1] <= # SIM_DELAY itplt_rate_mul_res[1][RESIZE_SCALE_QUAZ_N*2:RESIZE_SCALE_QUAZ_N-3];
		end
	end
	
	// 源像素
	always @(posedge clk)
	begin
		if(itplt_rate_mul_res_vld)
		begin
			src_pix[0] <= # SIM_DELAY {src_pix[0][15:0], src_img_mem_dout_0};
			src_pix[1] <= # SIM_DELAY {src_pix[1][15:0], src_img_mem_dout_1};
		end
	end
	
	// 插值像素乘法器计算结果
	always @(posedge clk)
	begin
		if(itplt_rate_vld) // 插值系数和源像素同时有效
		begin
			itplt_pix_mul_res[0] <= # SIM_DELAY 
				itplt_rate[0] * (
					src_k_ofs_delay_chain[2] ? (
						(src_k_ofs_delay_chain[2] == 2'b00) ? src_rgb565_b[0]:
						(src_k_ofs_delay_chain[2] == 2'b01) ? src_rgb565_g[0]:
															  src_rgb565_r[0]
					):src_pix[0][7:0]
				);
			
			itplt_pix_mul_res[1] <= # SIM_DELAY 
				itplt_rate[1] * (
					src_k_ofs_delay_chain[2] ? (
						(src_k_ofs_delay_chain[2] == 2'b00) ? src_rgb565_b[1]:
						(src_k_ofs_delay_chain[2] == 2'b01) ? src_rgb565_g[1]:
															  src_rgb565_r[1]
					):src_pix[1][7:0]
				);
		end
	end
	
	// 插值像素部分和
	always @(posedge clk)
	begin
		if(itplt_pix_mul_res_vld)
			itplt_pix_part_sum <= # SIM_DELAY itplt_pix_mul_res[0] + itplt_pix_mul_res[1];
	end
	
	// 插值像素
	always @(posedge clk)
	begin
		if(itplt_pix_part_sum_vld)
			itplt_pix <= # SIM_DELAY 
				itplt_pix_loaded ? 
					(itplt_pix + itplt_pix_part_sum):
					{1'b0, itplt_pix_part_sum};
	end
	
	// 插值像素累加已载入(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			itplt_pix_loaded <= 1'b0;
		else if(itplt_pix_part_sum_vld)
			itplt_pix_loaded <= # SIM_DELAY ~itplt_pix_loaded;
	end
	
	// 上一个待写的插值像素
	always @(posedge clk)
	begin
		if(itplt_pix_vld)
			itplt_pix_to_wt_pre <= # SIM_DELAY itplt_pix_to_wt_cur;
	end
	
	// 插值系数乘法器计算结果有效(指示)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			itplt_rate_mul_res_vld <= 1'b0;
		else
			itplt_rate_mul_res_vld <= # SIM_DELAY itplt_rate_mul_en;
	end
	
	// 插值系数有效(指示)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			itplt_rate_vld <= 1'b0;
		else
			itplt_rate_vld <= # SIM_DELAY itplt_rate_mul_res_vld;
	end
	
	// 插值像素乘法器计算结果有效(指示)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			itplt_pix_mul_res_vld <= 1'b0;
		else
			itplt_pix_mul_res_vld <= # SIM_DELAY itplt_rate_vld;
	end
	
	// 插值像素部分和有效(指示)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			itplt_pix_part_sum_vld <= 1'b0;
		else
			itplt_pix_part_sum_vld <= # SIM_DELAY itplt_pix_mul_res_vld;
	end
	
	// 插值像素有效(指示)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			itplt_pix_vld <= 1'b0;
		else
			itplt_pix_vld <= # SIM_DELAY itplt_pix_part_sum_vld & itplt_pix_loaded;
	end
	
	// 行尾标志延迟链
	// 源图片通道号偏移量延迟链
	// 图片像素格式为rgb565标志延迟链
	always @(posedge clk)
	begin
		if(resize_cal_started & src_img_vfifo_empty_n & res_fifo_almost_full_n)
		begin
			dst_rlast_delay_chain[0] <= # SIM_DELAY dst_last_col & dst_last_chn;
			src_k_ofs_delay_chain[0] <= # SIM_DELAY src_k_ofs;
			is_resize_rgb565_delay_chain[0] <= # SIM_DELAY is_resize_rgb565;
		end
	end
	always @(posedge clk)
	begin
		if(itplt_rate_mul_en)
		begin
			dst_rlast_delay_chain[1] <= # SIM_DELAY dst_rlast_delay_chain[0];
			src_k_ofs_delay_chain[1] <= # SIM_DELAY src_k_ofs_delay_chain[0];
			is_resize_rgb565_delay_chain[1] <= # SIM_DELAY is_resize_rgb565_delay_chain[0];
		end
	end
	always @(posedge clk)
	begin
		if(itplt_rate_mul_res_vld)
		begin
			dst_rlast_delay_chain[2] <= # SIM_DELAY dst_rlast_delay_chain[1];
			src_k_ofs_delay_chain[2] <= # SIM_DELAY src_k_ofs_delay_chain[1];
			is_resize_rgb565_delay_chain[2] <= # SIM_DELAY is_resize_rgb565_delay_chain[1];
		end
	end
	always @(posedge clk)
	begin
		if(itplt_rate_vld)
		begin
			dst_rlast_delay_chain[3] <= # SIM_DELAY dst_rlast_delay_chain[2];
			src_k_ofs_delay_chain[3] <= # SIM_DELAY src_k_ofs_delay_chain[2];
			is_resize_rgb565_delay_chain[3] <= # SIM_DELAY is_resize_rgb565_delay_chain[2];
		end
	end
	always @(posedge clk)
	begin
		if(itplt_pix_mul_res_vld)
		begin
			dst_rlast_delay_chain[4] <= # SIM_DELAY dst_rlast_delay_chain[3];
			src_k_ofs_delay_chain[4] <= # SIM_DELAY src_k_ofs_delay_chain[3];
			is_resize_rgb565_delay_chain[4] <= # SIM_DELAY is_resize_rgb565_delay_chain[3];
		end
	end
	always @(posedge clk)
	begin
		if(itplt_pix_part_sum_vld & itplt_pix_loaded)
		begin
			dst_rlast_delay_chain[5] <= # SIM_DELAY dst_rlast_delay_chain[4];
			src_k_ofs_delay_chain[5] <= # SIM_DELAY src_k_ofs_delay_chain[4];
			is_resize_rgb565_delay_chain[5] <= # SIM_DELAY is_resize_rgb565_delay_chain[4];
		end
	end
	
	/** 双线性插值请求处理流程 **/
	reg[3:0] resize_req_sts; // 双线性插值请求处理状态
	reg resize_fns_r; // 缩放完成标志
	reg[7:0] resize_fns_flag_ext_cnt; // 缩放完成标志展宽计数器
	
	assign s_req_axis_ready = resize_req_sts[RESIZE_REQ_STS_IDLE_ID];
	
	assign resize_fns = resize_fns_r;
	
	assign on_start_resize_cal = resize_req_sts[RESIZE_REQ_STS_START_ID];
	assign on_clr_resize_cal_fns = resize_req_sts[RESIZE_REQ_STS_DONE_ID];
	
	// 双线性插值请求处理状态
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			resize_req_sts <= 4'b0001 << RESIZE_REQ_STS_IDLE_ID;
		else if(
			(resize_req_sts[RESIZE_REQ_STS_IDLE_ID] & s_req_axis_valid) | 
			resize_req_sts[RESIZE_REQ_STS_START_ID] | 
			(resize_req_sts[RESIZE_REQ_STS_PROCESSING_ID] & resize_cal_fns) | 
			resize_req_sts[RESIZE_REQ_STS_DONE_ID]
		)
			resize_req_sts <= # SIM_DELAY {resize_req_sts[2:0], resize_req_sts[3]};
	end
	
	// 缩放完成标志
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			resize_fns_r <= 1'b0;
		else if(resize_fns_r ? 
			(&resize_fns_flag_ext_cnt):
			resize_cal_done
		)
			resize_fns_r <= # SIM_DELAY ~resize_fns_r;
	end
	
	// 缩放完成标志展宽计数器
	always @(posedge clk)
	begin
		resize_fns_flag_ext_cnt <= # SIM_DELAY 
			{8{resize_fns_r}} & (resize_fns_flag_ext_cnt + 1'b1);
	end
	
endmodule
