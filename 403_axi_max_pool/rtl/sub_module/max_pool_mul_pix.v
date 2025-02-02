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
本模块: 最大池化处理单元(多像素/clk)

描述:
实现神经网络中的最大池化处理(max pool)
多像素/clk
流控制模式固定为阻塞
池化窗口大小为2x2
支持步长为1或2
支持当步长为1时向上/下/左/右填充

特征组提取器(缓存寄存器区1clk, [AXIS寄存器片1clk]) -> 
	行填充处理单元([AXIS寄存器片1clk]) -> 
	2级流水线(行缓存MEM读延迟1clk, ROI寄存器1clk) -> 
	2级流水线(最大池化计算2clk) -> 
	输出特征项整理单元([AXIS寄存器片1clk]) -> 
	输出特征数据收集单元(寄存器缓存区1clk) -> 
	[输出寄存器片1clk]

处理速度 = 1特征组/clk

步长       输入     输出
  1      1 1 2 2  [1  1  2  2  2]
         3 4 3 1  [3] 4  4  3 [2]
         1 1 0 0  [3] 4  4  3 [1]
         7 8 0 1  [7] 8  8  1 [1]
		          [7  8  8  1  1]
  2      1 1 2 2
         3 4 3 1      4     3
         1 1 0 0
         7 8 0 1      8     1

注意：
输入特征图的宽度/高度/通道数必须<=最大的输入特征图宽度/高度/通道数

输入/输出特征图数据流 ->
	[x1, y1, c1] ... [xn, y1, c1]
				  .
				  .
	[x1, yn, c1] ... [x1, yn, c1]
	
	              .
	              .
				  .
	
	[x1, y1, cn] ... [xn, y1, cn]
				  .
				  .
	[x1, yn, cn] ... [x1, yn, cn]

协议:
BLK CTRL
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2024/10/11
********************************************************************/


module max_pool_mul_pix #(
    parameter integer feature_n_per_clk = 4, // 每个clk输入的特征点数量(2 | 4 | 8 | 16 | ...)
	parameter integer feature_data_width = 8, // 特征点位宽(必须能被8整除, 且>0)
	parameter integer max_feature_chn_n = 128, // 最大的特征图通道数
	parameter integer max_feature_w = 128, // 最大的输入特征图宽度
	parameter integer max_feature_h = 128, // 最大的输入特征图高度
	parameter en_out_reg_slice = "true", // 是否使用输出寄存器片
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 块级控制
	input wire blk_start,
	output wire blk_idle,
	output wire blk_done,
	
	// 运行时参数
	input wire step_type, // 步长类型(1'b0 -> 步长为1, 1'b1 -> 步长为2)
	input wire[3:0] padding_vec, // 外拓填充向量(仅当步长为1时可用, {上, 下, 左, 右})
	input wire[15:0] feature_map_chn_n, // 特征图通道数 - 1
	input wire[15:0] feature_map_w, // 特征图宽度 - 1
	input wire[15:0] feature_map_h, // 特征图高度 - 1
	
	// 待处理特征图像素流输入
	input wire[feature_n_per_clk*feature_data_width-1:0] s_axis_data,
	input wire[feature_n_per_clk*feature_data_width/8-1:0] s_axis_keep,
	input wire s_axis_last, // 指示特征图结束
	input wire s_axis_valid,
	output wire s_axis_ready,
	
	// 处理后特征图像素流输出
	output wire[feature_n_per_clk*feature_data_width-1:0] m_axis_data,
	output wire[feature_n_per_clk*feature_data_width/8-1:0] m_axis_keep,
	output wire m_axis_last, // 特征图最后1点
	output wire m_axis_valid,
	input wire m_axis_ready
);
    
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
        for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
			bit_depth = bit_depth >> 1;
    end
    endfunction
	
	/** 内部配置 **/
	localparam en_reg_slice_at_feature_row_realign = "false"; // 是否在特征组提取器的输出插入AXIS寄存器片
	localparam en_reg_slice_at_row_padding = "false"; // 是否在行填充处理单元的输出插入AXIS寄存器片
	localparam en_reg_slice_at_item_formator = "true"; // 是否在输出特征项整理单元的输出插入AXIS寄存器片
	
	/** 常量 **/
	localparam integer in_stream_data_width = feature_n_per_clk*feature_data_width; // 输入像素流位宽
	localparam integer out_stream_data_width = (feature_n_per_clk+1)*feature_data_width; // 输出像素流位宽
	
	/** 输出寄存器片 **/
	// AXIS从机
	wire[feature_n_per_clk*feature_data_width-1:0] s_axis_reg_slice_data;
    wire[feature_n_per_clk*feature_data_width/8-1:0] s_axis_reg_slice_keep;
    wire s_axis_reg_slice_last;
    wire s_axis_reg_slice_valid;
    wire s_axis_reg_slice_ready;
	// AXIS主机
	wire[feature_n_per_clk*feature_data_width-1:0] m_axis_reg_slice_data;
    wire[feature_n_per_clk*feature_data_width/8-1:0] m_axis_reg_slice_keep;
    wire m_axis_reg_slice_last;
    wire m_axis_reg_slice_valid;
    wire m_axis_reg_slice_ready;
	
	assign m_axis_data = m_axis_reg_slice_data;
	assign m_axis_keep = m_axis_reg_slice_keep;
	assign m_axis_last = m_axis_reg_slice_last;
	assign m_axis_valid = m_axis_reg_slice_valid;
	assign m_axis_reg_slice_ready = m_axis_ready;
	
	axis_reg_slice #(
		.data_width(feature_n_per_clk*feature_data_width),
		.user_width(1),
		.forward_registered(en_out_reg_slice),
		.back_registered(en_out_reg_slice),
		.en_ready("true"),
		.simulation_delay(simulation_delay)
	)out_reg_slice(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axis_data(s_axis_reg_slice_data),
		.s_axis_keep(s_axis_reg_slice_keep),
		.s_axis_user(),
		.s_axis_last(s_axis_reg_slice_last),
		.s_axis_valid(s_axis_reg_slice_valid),
		.s_axis_ready(s_axis_reg_slice_ready),
		
		.m_axis_data(m_axis_reg_slice_data),
		.m_axis_keep(m_axis_reg_slice_keep),
		.m_axis_user(),
		.m_axis_last(m_axis_reg_slice_last),
		.m_axis_valid(m_axis_reg_slice_valid),
		.m_axis_ready(m_axis_reg_slice_ready)
	);
	
	/** 块级控制 **/
	wire row_padding_start;
	wire row_padding_idle;
	wire row_padding_done;
	wire max_pool_start;
	reg max_pool_idle;
	wire max_pool_done;
	
	assign blk_idle = max_pool_idle;
	assign blk_done = max_pool_done;
	
	assign row_padding_start = blk_start;
	assign max_pool_start = blk_start;
	assign max_pool_done = m_axis_valid & m_axis_ready & m_axis_last;
	
	// 最大池化单元空闲标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			max_pool_idle <= 1'b1;
		else
			max_pool_idle <= # simulation_delay max_pool_idle ? (~max_pool_start):max_pool_done;
	end
	
	/** 特征组提取器 **/
	// 特征组输出
	wire[in_stream_data_width-1:0] m_axis_ft_gp_data;
	wire[2:0] m_axis_ft_gp_user; // {当前处于最后1个通道, 当前处于最后1行, 当前处于最后1列}
	wire[in_stream_data_width/8-1:0] m_axis_ft_gp_keep;
	wire m_axis_ft_gp_last; // 指示最后1个特征组
	wire m_axis_ft_gp_valid;
	wire m_axis_ft_gp_ready;
	
	feature_row_realign #(
		.feature_n_per_clk(feature_n_per_clk),
		.feature_data_width(feature_data_width),
		.max_feature_map_chn_n(max_feature_chn_n),
		.max_feature_map_w(max_feature_w),
		.max_feature_map_h(max_feature_h),
		.en_out_reg_slice(en_reg_slice_at_feature_row_realign),
		.simulation_delay(simulation_delay)
	)feature_row_realign_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.in_stream_en(1'b1),
		
		.feature_map_chn_n(feature_map_chn_n),
		.feature_map_w(feature_map_w),
		.feature_map_h(feature_map_h),
		
		.s_axis_data(s_axis_data),
		.s_axis_keep(s_axis_keep),
		.s_axis_last(s_axis_last),
		.s_axis_valid(s_axis_valid),
		.s_axis_ready(s_axis_ready),
		
		.m_axis_data(m_axis_ft_gp_data),
		.m_axis_user(m_axis_ft_gp_user),
		.m_axis_keep(m_axis_ft_gp_keep),
		.m_axis_last(m_axis_ft_gp_last),
		.m_axis_valid(m_axis_ft_gp_valid),
		.m_axis_ready(m_axis_ft_gp_ready)
	);
	
	/** 行填充处理单元 **/
	// 行填充输入
	wire[in_stream_data_width-1:0] s_axis_row_padding_data;
	wire[2:0] s_axis_row_padding_user; // {当前处于最后1个通道, 当前处于最后1行, 当前处于最后1列}
	wire[in_stream_data_width/8-1:0] s_axis_row_padding_keep;
	wire s_axis_row_padding_last; // 指示最后1个特征组
	wire s_axis_row_padding_valid;
	wire s_axis_row_padding_ready;
	// 行填充输出
	wire[in_stream_data_width-1:0] m_axis_row_padding_data;
	wire[2:0] m_axis_row_padding_user; // {当前处于最后1个通道, 当前处于最后1行, 当前处于最后1列}
	wire[in_stream_data_width/8-1:0] m_axis_row_padding_keep;
	wire m_axis_row_padding_last; // 指示最后1个特征组
	wire m_axis_row_padding_valid;
	wire m_axis_row_padding_ready;
	
	assign s_axis_row_padding_data = m_axis_ft_gp_data;
	assign s_axis_row_padding_user = m_axis_ft_gp_user;
	assign s_axis_row_padding_keep = m_axis_ft_gp_keep;
	assign s_axis_row_padding_last = m_axis_ft_gp_last;
	assign s_axis_row_padding_valid = m_axis_ft_gp_valid;
	assign m_axis_ft_gp_ready = s_axis_row_padding_ready;
	
	max_pool_row_padding #(
		.feature_n_per_clk(feature_n_per_clk),
		.feature_data_width(feature_data_width),
		.max_feature_chn_n(max_feature_chn_n),
		.max_feature_w(max_feature_w),
		.en_out_reg_slice(en_reg_slice_at_row_padding),
		.simulation_delay(simulation_delay)
	)max_pool_row_padding_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.blk_start(row_padding_start),
		.blk_idle(row_padding_idle),
		.blk_done(row_padding_done),
		
		.step_type(step_type),
		.padding_vec(padding_vec[3:2]),
		.feature_map_chn_n(feature_map_chn_n),
		.feature_map_w(feature_map_w),
		
		.s_axis_data(s_axis_row_padding_data),
		.s_axis_user(s_axis_row_padding_user),
		.s_axis_keep(s_axis_row_padding_keep),
		.s_axis_last(s_axis_row_padding_last),
		.s_axis_valid(s_axis_row_padding_valid),
		.s_axis_ready(s_axis_row_padding_ready),
		
		.m_axis_data(m_axis_row_padding_data),
		.m_axis_user(m_axis_row_padding_user),
		.m_axis_keep(m_axis_row_padding_keep),
		.m_axis_last(m_axis_row_padding_last),
		.m_axis_valid(m_axis_row_padding_valid),
		.m_axis_ready(m_axis_row_padding_ready)
	);
	
	/** 行缓存区 **/
	// 特征组掩码
	wire[feature_n_per_clk-1:0] feature_in_keep; // 特征项掩码
	wire[in_stream_data_width-1:0] feature_in_data_mask; // 特征数据掩码
	// 行缓存MEM写端口
	wire line_buf_mem_wen_a;
	reg[clogb2(max_feature_w/feature_n_per_clk-1):0] line_buf_mem_addr;
	wire[in_stream_data_width-1:0] line_buf_mem_din_a; // 特征组数据
	// 行缓存MEM读端口
	wire line_buf_mem_ren_b;
	wire[in_stream_data_width-1:0] line_buf_mem_dout_b; // 特征组数据
	
	genvar feature_in_keep_i;
	generate
		for(feature_in_keep_i = 0;feature_in_keep_i < feature_n_per_clk;
			feature_in_keep_i = feature_in_keep_i + 1)
		begin
			assign feature_in_keep[feature_in_keep_i] = 
				m_axis_row_padding_keep[feature_in_keep_i*feature_data_width/8];
			
			assign feature_in_data_mask[(feature_in_keep_i+1)*feature_data_width-1:feature_in_keep_i*feature_data_width] = 
				{feature_data_width{feature_in_keep[feature_in_keep_i]}};
		end
	endgenerate
	
	assign line_buf_mem_wen_a = m_axis_row_padding_valid & m_axis_row_padding_ready;
	assign line_buf_mem_din_a = m_axis_row_padding_data & feature_in_data_mask;
	
	assign line_buf_mem_ren_b = m_axis_row_padding_valid & m_axis_row_padding_ready;
	
	// 行缓存MEM读写地址
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			line_buf_mem_addr <= 0;
		else if(m_axis_row_padding_valid & m_axis_row_padding_ready)
			line_buf_mem_addr <= # simulation_delay m_axis_row_padding_user[0] ? 0:(line_buf_mem_addr + 1);
	end
	
	// 行缓存MEM
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(in_stream_data_width),
		.mem_depth(max_feature_w/feature_n_per_clk),
		.INIT_FILE("no_init"),
		.simulation_delay(simulation_delay)
	)line_buf_mem_u(
		.clk(clk),
		
		.wen_a(line_buf_mem_wen_a),
		.addr_a(line_buf_mem_addr),
		.din_a(line_buf_mem_din_a),
		
		.ren_b(line_buf_mem_ren_b),
		.addr_b(line_buf_mem_addr),
		.dout_b(line_buf_mem_dout_b)
	);
	
	/** 池化位置计数器 **/
	wire[clogb2(max_feature_w-1):0] pool_x; // 池化x坐标(not used!)
	reg pool_x_eq0; // 池化x坐标 == 0(标志)
	reg[clogb2(max_feature_h+1):0] pool_y; // 池化y坐标
	reg pool_y_eq0; // 池化y坐标 == 0(标志)
	
	// feature_n_per_clk为2^x, 仅做左移计算
	assign pool_x = line_buf_mem_addr * feature_n_per_clk;
	
	// 池化x坐标 == 0(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			pool_x_eq0 <= 1'b1;
		else if(m_axis_row_padding_valid & m_axis_row_padding_ready)
			pool_x_eq0 <= # simulation_delay m_axis_row_padding_user[0];
	end
	
	// 池化y坐标
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			pool_y <= 0;
		else if(m_axis_row_padding_valid & m_axis_row_padding_ready & m_axis_row_padding_user[0])
			pool_y <= # simulation_delay m_axis_row_padding_user[1] ? 0:(pool_y + 1);
	end
	
	// 池化y坐标 == 0(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			pool_y_eq0 <= 1'b1;
		else if(m_axis_row_padding_valid & m_axis_row_padding_ready & m_axis_row_padding_user[0])
			pool_y_eq0 <= # simulation_delay m_axis_row_padding_user[1];
	end
	
	/** 池化ROI生成流水线控制 **/
	reg feature_in_vld_d; // 延迟1clk的输入特征组有效指示
	wire pool_roi_gen_stage1_ready;
	reg pool_roi_vld; // 池化ROI有效指示
	wire pool_roi_gen_stage2_ready;
	
	assign m_axis_row_padding_ready = (~feature_in_vld_d) | pool_roi_gen_stage1_ready;
	assign pool_roi_gen_stage1_ready = (~pool_roi_vld) | pool_roi_gen_stage2_ready;
	
	// 延迟1clk的输入特征组有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			feature_in_vld_d <= 1'b0;
		else if(m_axis_row_padding_ready)
			feature_in_vld_d <= # simulation_delay m_axis_row_padding_valid;
	end
	
	/**
	池化ROI
	
	数据 -> 
		[pool_left_buf_r1] pool_roi_r1
		[pool_left_buf_r2] pool_roi_r2
	
	特征项使能掩码 -> 
		pool_roi_keep
	**/
	reg[in_stream_data_width-1:0] feature_in_d; // 延迟1clk的输入特征组
	reg[feature_n_per_clk-1:0] feature_in_keep_d; // 延迟1clk的输入特征项使能掩码
	reg pool_x_eq0_d; // 延迟1clk的池化x坐标 == 0(标志)
	reg[clogb2(max_feature_h-1):0] pool_y_d; // 延迟1clk的池化y坐标
	reg pool_y_eq0_d; // 延迟1clk的池化y坐标 == 0(标志)
	reg[3:0] pool_roi_user_last_d; // 延迟1clk的输出像素流的位置标志({1ast(1bit), user(3bit)})
	reg pool_x_eq0_d2; // 延迟2clk的池化x坐标 == 0(标志)
	reg[in_stream_data_width-1:0] pool_roi_r1; // 池化ROI第1行
	reg[in_stream_data_width-1:0] pool_roi_r2; // 池化ROI第2行
	reg[feature_n_per_clk-1:0] pool_roi_keep; // 池化ROI特征项使能掩码
	reg[feature_data_width-1:0] pool_left_buf_r1; // 池化ROI第1行剩余缓存
	reg[feature_data_width-1:0] pool_left_buf_r2; // 池化ROI第2行剩余缓存
	reg[3:0] pool_roi_user_last_d2; // 延迟2clk的输出像素流的位置标志({1ast(1bit), user(3bit)})
	
	// 池化ROI有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			pool_roi_vld <= 1'b0;
		else if(pool_roi_gen_stage1_ready)
			pool_roi_vld <= # simulation_delay feature_in_vld_d & 
				(~pool_y_eq0_d) & // 池化y坐标 >= 1
				((~step_type) | pool_y_d[0]); // step_type ? pool_y_d[0]:1'b1
	end
	
	// 延迟1clk的输入特征组
	always @(posedge clk)
	begin
		if(m_axis_row_padding_valid & m_axis_row_padding_ready)
			feature_in_d <= # simulation_delay m_axis_row_padding_data & feature_in_data_mask;
	end
	// 延迟1clk的输入特征项使能掩码
	always @(posedge clk)
	begin
		if(m_axis_row_padding_valid & m_axis_row_padding_ready)
			feature_in_keep_d <= # simulation_delay feature_in_keep;
	end
	
	// 延迟1clk的池化x坐标 == 0(标志)
	always @(posedge clk)
	begin
		if(m_axis_row_padding_valid & m_axis_row_padding_ready)
			pool_x_eq0_d <= # simulation_delay pool_x_eq0;
	end
	// 延迟1clk的池化y坐标
	always @(posedge clk)
	begin
		if(m_axis_row_padding_valid & m_axis_row_padding_ready)
			pool_y_d <= # simulation_delay pool_y;
	end
	// 延迟1clk的池化y坐标 == 0(标志)
	always @(posedge clk)
	begin
		if(m_axis_row_padding_valid & m_axis_row_padding_ready)
			pool_y_eq0_d <= # simulation_delay pool_y_eq0;
	end
	
	// 延迟2clk的池化x坐标 == 0(标志)
	always @(posedge clk)
	begin
		if(feature_in_vld_d & pool_roi_gen_stage1_ready)
			pool_x_eq0_d2 <= # simulation_delay pool_x_eq0_d;
	end
	
	// 池化ROI第1行
	always @(posedge clk)
	begin
		if(feature_in_vld_d & pool_roi_gen_stage1_ready)
			pool_roi_r1 <= # simulation_delay line_buf_mem_dout_b;
	end
	// 池化ROI第2行
	always @(posedge clk)
	begin
		if(feature_in_vld_d & pool_roi_gen_stage1_ready)
			pool_roi_r2 <= # simulation_delay feature_in_d;
	end
	// 池化ROI特征项使能掩码
	always @(posedge clk)
	begin
		if(feature_in_vld_d & pool_roi_gen_stage1_ready)
			pool_roi_keep <= # simulation_delay feature_in_keep_d;
	end
	
	// 池化ROI第1行剩余缓存
	always @(posedge clk)
	begin
		if(feature_in_vld_d & pool_roi_gen_stage1_ready)
			pool_left_buf_r1 <= # simulation_delay pool_x_eq0_d ? 
				{feature_data_width{1'b0}}:pool_roi_r1[in_stream_data_width-1:in_stream_data_width-feature_data_width];
	end
	// 池化ROI第2行剩余缓存
	always @(posedge clk)
	begin
		if(feature_in_vld_d & pool_roi_gen_stage1_ready)
			pool_left_buf_r2 <= # simulation_delay pool_x_eq0_d ? 
				{feature_data_width{1'b0}}:pool_roi_r2[in_stream_data_width-1:in_stream_data_width-feature_data_width];
	end
	
	// 延迟1clk的输出像素流的位置标志({1ast(1bit), user(3bit)})
	always @(posedge clk)
	begin
		if(m_axis_row_padding_valid & m_axis_row_padding_ready)
			pool_roi_user_last_d <= # simulation_delay {m_axis_row_padding_last, m_axis_row_padding_user};
	end
	// 延迟2clk的输出像素流的位置标志({1ast(1bit), user(3bit)})
	always @(posedge clk)
	begin
		if(feature_in_vld_d & pool_roi_gen_stage1_ready)
			pool_roi_user_last_d2 <= # simulation_delay pool_roi_user_last_d;
	end
	
	/** 池化计算 **/
	// 池化ROI输入
	wire[in_stream_data_width-1:0] cal_unit_pool_roi_r1; // 池化ROI第1行
	wire[in_stream_data_width-1:0] cal_unit_pool_roi_r2; // 池化ROI第2行
	wire[feature_n_per_clk-1:0] cal_unit_pool_roi_keep; // 池化ROI特征项使能掩码
	wire[feature_data_width-1:0] cal_unit_pool_left_buf_r1; // 池化ROI第1行剩余缓存
	wire[feature_data_width-1:0] cal_unit_pool_left_buf_r2; // 池化ROI第2行剩余缓存
	wire cal_unit_pool_x_eq0; // 池化x坐标 == 0(标志)
	wire[2:0] cal_unit_pool_roi_user; // {当前处于最后1个通道, 当前处于最后1行, 当前处于最后1列}
	wire cal_unit_pool_roi_last; // 特征图最后1点
	wire cal_unit_pool_roi_valid;
	wire cal_unit_pool_roi_ready;
	// 计算结果输出
	wire[out_stream_data_width-1:0] cal_unit_pool_res;
	wire[out_stream_data_width/8-1:0] cal_unit_pool_res_keep;
	wire[2:0] cal_unit_pool_res_user; // {当前处于最后1个通道, 当前处于最后1行, 当前处于最后1列}
	wire cal_unit_pool_res_last; // 特征图最后1点
	wire cal_unit_pool_res_valid;
	wire cal_unit_pool_res_ready;
	
	assign cal_unit_pool_roi_r1 = pool_roi_r1;
	assign cal_unit_pool_roi_r2 = pool_roi_r2;
	assign cal_unit_pool_roi_keep = pool_roi_keep;
	assign cal_unit_pool_left_buf_r1 = pool_left_buf_r1;
	assign cal_unit_pool_left_buf_r2 = pool_left_buf_r2;
	assign cal_unit_pool_x_eq0 = pool_x_eq0_d2;
	assign cal_unit_pool_roi_user = pool_roi_user_last_d2[2:0];
	assign cal_unit_pool_roi_last = pool_roi_user_last_d2[3];
	assign cal_unit_pool_roi_valid = pool_roi_vld;
	assign pool_roi_gen_stage2_ready = cal_unit_pool_roi_ready;
	
	// 最大池化计算单元
	max_pool_cal_mul_pix #(
		.feature_n_per_clk(feature_n_per_clk),
		.feature_data_width(feature_data_width),
		.simulation_delay(simulation_delay)
	)max_pool_cal_mul_pix_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.step_type(step_type),
		.padding_vec(padding_vec[1:0]),
		
		.pool_roi_r1(cal_unit_pool_roi_r1),
		.pool_roi_r2(cal_unit_pool_roi_r2),
		.pool_roi_keep(cal_unit_pool_roi_keep),
		.pool_left_buf_r1(cal_unit_pool_left_buf_r1),
		.pool_left_buf_r2(cal_unit_pool_left_buf_r2),
		.pool_x_eq0(cal_unit_pool_x_eq0),
		.pool_roi_user(cal_unit_pool_roi_user),
		.pool_roi_last(cal_unit_pool_roi_last),
		.pool_roi_valid(cal_unit_pool_roi_valid),
		.pool_roi_ready(cal_unit_pool_roi_ready),
		
		.pool_res(cal_unit_pool_res),
		.pool_res_keep(cal_unit_pool_res_keep),
		.pool_res_user(cal_unit_pool_res_user),
		.pool_res_last(cal_unit_pool_res_last),
		.pool_res_valid(cal_unit_pool_res_valid),
		.pool_res_ready(cal_unit_pool_res_ready)
	);
	
	/** 输出特征项整理单元 **/
	// 整理单元输入
	wire[out_stream_data_width-1:0] s_axis_reorg_data;
	wire[2:0] s_axis_reorg_user; // {当前处于最后1个通道, 当前处于最后1行, 当前处于最后1列}
	wire[out_stream_data_width/8-1:0] s_axis_reorg_keep;
	wire s_axis_reorg_last; // 指示最后1个特征组
	wire s_axis_reorg_valid;
	wire s_axis_reorg_ready;
	// 整理单元输出
	wire[out_stream_data_width-1:0] m_axis_reorg_data;
	wire[2:0] m_axis_reorg_user; // {当前处于最后1个通道, 当前处于最后1行, 当前处于最后1列}
	wire[out_stream_data_width/8-1:0] m_axis_reorg_keep;
	wire m_axis_reorg_last; // 指示最后1个特征组
	wire m_axis_reorg_valid;
	wire m_axis_reorg_ready;
	
	assign s_axis_reorg_data = cal_unit_pool_res;
	assign s_axis_reorg_keep = cal_unit_pool_res_keep;
	assign s_axis_reorg_user = cal_unit_pool_res_user;
	assign s_axis_reorg_last = cal_unit_pool_res_last;
	assign s_axis_reorg_valid = cal_unit_pool_res_valid;
	assign cal_unit_pool_res_ready = s_axis_reorg_ready;
	
	max_pool_item_formator #(
		.feature_n_per_clk(feature_n_per_clk),
		.feature_data_width(feature_data_width),
		.en_out_reg_slice(en_reg_slice_at_item_formator),
		.simulation_delay(simulation_delay)
	)max_pool_item_formator_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.step_type(step_type),
		
		.s_axis_data(s_axis_reorg_data),
		.s_axis_user(s_axis_reorg_user),
		.s_axis_keep(s_axis_reorg_keep),
		.s_axis_last(s_axis_reorg_last),
		.s_axis_valid(s_axis_reorg_valid),
		.s_axis_ready(s_axis_reorg_ready),
		
		.m_axis_data(m_axis_reorg_data),
		.m_axis_user(m_axis_reorg_user),
		.m_axis_keep(m_axis_reorg_keep),
		.m_axis_last(m_axis_reorg_last),
		.m_axis_valid(m_axis_reorg_valid),
		.m_axis_ready(m_axis_reorg_ready)
	);
	
	/** 输出特征数据收集单元 **/
	// 数据收集单元输入
	wire[out_stream_data_width-1:0] s_axis_collector_data;
	wire[out_stream_data_width/8-1:0] s_axis_collector_keep;
	wire s_axis_collector_last; // 指示最后1个特征组
	wire s_axis_collector_valid;
	wire s_axis_collector_ready;
	// 数据收集单元输出
	wire[feature_n_per_clk*feature_data_width-1:0] m_axis_collector_data;
	wire[feature_n_per_clk*feature_data_width/8-1:0] m_axis_collector_keep;
	wire m_axis_collector_last; // 指示输出特征图的最后1组数据
	wire m_axis_collector_valid;
	wire m_axis_collector_ready;
	
	assign s_axis_collector_data = m_axis_reorg_data;
	assign s_axis_collector_keep = m_axis_reorg_keep;
	assign s_axis_collector_last = m_axis_reorg_last;
	assign s_axis_collector_valid = m_axis_reorg_valid;
	assign m_axis_reorg_ready = s_axis_collector_ready;
	
	assign s_axis_reg_slice_data = m_axis_collector_data;
	assign s_axis_reg_slice_keep = m_axis_collector_keep;
	assign s_axis_reg_slice_last = m_axis_collector_last;
	assign s_axis_reg_slice_valid = m_axis_collector_valid;
	assign m_axis_collector_ready = s_axis_reg_slice_ready;
	
	max_pool_packet_collector #(
		.feature_n_per_clk(feature_n_per_clk),
		.feature_data_width(feature_data_width),
		.simulation_delay(simulation_delay)
	)max_pool_packet_collector_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axis_data(s_axis_collector_data),
		.s_axis_keep(s_axis_collector_keep),
		.s_axis_last(s_axis_collector_last),
		.s_axis_valid(s_axis_collector_valid),
		.s_axis_ready(s_axis_collector_ready),
		
		.m_axis_data(m_axis_collector_data),
		.m_axis_keep(m_axis_collector_keep),
		.m_axis_last(m_axis_collector_last),
		.m_axis_valid(m_axis_collector_valid),
		.m_axis_ready(m_axis_collector_ready)
	);
    
endmodule
