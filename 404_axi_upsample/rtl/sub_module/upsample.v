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
本模块: 上采样处理单元

描述:
实现神经网络中的上采样处理(upsample)
多像素/clk
1x1到2x2上采样
2级流水线(行缓存MEM读延迟1clk, 输出寄存器1clk)
输入吞吐率：(feature_n_per_clk*feature_n_per_clk/2)/clk
输出吞吐率：(feature_n_per_clk*feature_n_per_clk*2)/clk

         1 1 2 2
1 2      1 1 2 2
3 4  --> 3 3 4 4
5 6      3 3 4 4
         5 5 6 6
         5 5 6 6

注意：
输入特征图的宽度必须能被每个clk输入的特征点数量*2(feature_n_per_clk*2)整除
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
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2024/09/14
********************************************************************/


module upsample #(
    parameter integer feature_n_per_clk = 8, // 每个clk输入的特征点数量(1 | 2 | 4 | 8 | 16 | ...)
	parameter integer feature_data_width = 8, // 特征点位宽(必须能被8整除, 且>0)
	parameter integer max_feature_w = 128, // 最大的输入特征图宽度
	parameter integer max_feature_h = 128, // 最大的输入特征图高度
	parameter integer max_feature_chn_n = 512, // 最大的输入特征图通道数
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 运行时参数
	input wire[15:0] feature_w, // 输入特征图宽度 - 1
	input wire[15:0] feature_h, // 输入特征图高度 - 1
	input wire[15:0] feature_chn_n, // 输入特征图通道数 - 1
	
	// 输入像素流
	input wire[feature_n_per_clk*feature_data_width-1:0] s_axis_data,
	input wire s_axis_valid,
	output wire s_axis_ready,
	
	// 输出像素流
	output wire[feature_n_per_clk*feature_data_width*2-1:0] m_axis_data,
	output wire[2:0] m_axis_user, // {当前处于最后1个通道, 当前处于最后1行, 当前处于最后1列}
	output wire m_axis_last, // 特征图最后1点
	output wire m_axis_valid,
	input wire m_axis_ready
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
	
	/** 行缓存区 **/
	// 行缓存区MEM写端口
    wire line_buf_wen_a;
    wire[clogb2(max_feature_w/feature_n_per_clk-1):0] line_buf_addr_a;
    wire[feature_n_per_clk*feature_data_width-1:0] line_buf_din_a;
    // 行缓存区MEM读端口
    wire line_buf_ren_b;
    wire[clogb2(max_feature_w/feature_n_per_clk-1):0] line_buf_addr_b;
    wire[feature_n_per_clk*feature_data_width-1:0] line_buf_dout_b;
	
	// 行缓存区MEM
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(feature_n_per_clk*feature_data_width),
		.mem_depth(max_feature_w/feature_n_per_clk),
		.INIT_FILE("no_init"),
		.simulation_delay(simulation_delay)
	)line_buf_mem(
		.clk(clk),
		
		.wen_a(line_buf_wen_a),
		.addr_a(line_buf_addr_a),
		.din_a(line_buf_din_a),
		
		.ren_b(line_buf_ren_b),
		.addr_b(line_buf_addr_b),
		.dout_b(line_buf_dout_b)
	);
	
	/** 流水线控制 **/
	wire valid_stage0;
	wire ready_stage0;
	reg valid_stage1;
	wire ready_stage1;
	reg valid_stage2;
	wire ready_stage2;
	
	// 握手条件：valid_stage0 & ((~valid_stage1) | ready_stage1)
	assign ready_stage0 = (~valid_stage1) | ready_stage1;
	
	// 握手条件：valid_stage1 & ((~valid_stage2) | ready_stage2)
	assign ready_stage1 = (~valid_stage2) | ready_stage2;
	
	// 握手条件：valid_stage2 & m_axis_ready
	assign m_axis_valid = valid_stage2;
	assign ready_stage2 = m_axis_ready;
	
    /** 上采样位置计数器 **/
	reg is_at_row_stuff_stage; // 是否处于行填充阶段(标志)
	reg[1:0] row_stuff_pos; // 行填充位置标志({当前处于最后1个通道, 当前处于最后1行})
	reg[clogb2(max_feature_w/feature_n_per_clk-1):0] upsample_x_cnt; // 上采样x位置计数器
	wire upsample_x_cnt_at_last; // 上采样x位置计数器抵达末尾(标志)
	reg[clogb2(max_feature_h-1):0] in_ft_map_y_cnt; // 输入特征图y位置计数器
	wire in_ft_map_y_cnt_at_last; // 输入特征图y位置计数器抵达末尾(标志)
	reg[clogb2(max_feature_chn_n-1):0] in_ft_map_chn_id_cnt; // 输入特征图通道号计数器
	wire in_ft_map_chn_id_cnt_at_last; // 输入特征图通道号计数器抵达末尾(标志)
	
	// 握手条件：s_axis_valid & (~is_at_row_stuff_stage) & ready_stage0
	assign s_axis_ready = (~is_at_row_stuff_stage) & ready_stage0;
	
	assign line_buf_wen_a = s_axis_valid & (~is_at_row_stuff_stage) & ((~valid_stage1) | ready_stage1);
	assign line_buf_addr_a = upsample_x_cnt;
	assign line_buf_din_a = s_axis_data;
	
	assign line_buf_ren_b = is_at_row_stuff_stage & ((~valid_stage1) | ready_stage1);
	assign line_buf_addr_b = upsample_x_cnt;
	
	// is_at_row_stuff_stage ? 1'b1:s_axis_valid
	assign valid_stage0 = is_at_row_stuff_stage | s_axis_valid;
	
	assign upsample_x_cnt_at_last = upsample_x_cnt == 
		feature_w[clogb2(max_feature_w/feature_n_per_clk-1)+clogb2(feature_n_per_clk):clogb2(feature_n_per_clk)];
	assign in_ft_map_y_cnt_at_last = in_ft_map_y_cnt == feature_h[clogb2(max_feature_h-1):0];
	assign in_ft_map_chn_id_cnt_at_last = in_ft_map_chn_id_cnt == feature_chn_n[clogb2(max_feature_chn_n-1):0];
	
	// 是否处于行填充阶段(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			is_at_row_stuff_stage <= 1'b0;
		else if(valid_stage0 & ready_stage0 & upsample_x_cnt_at_last)
			is_at_row_stuff_stage <= # simulation_delay ~is_at_row_stuff_stage;
	end
	
	// 行填充位置标志
	always @(posedge clk)
	begin
		if(s_axis_valid & s_axis_ready & upsample_x_cnt_at_last)
			row_stuff_pos <= # simulation_delay {in_ft_map_chn_id_cnt_at_last, in_ft_map_y_cnt_at_last};
	end
	
	// 上采样x位置计数器
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			upsample_x_cnt <= 0;
		else if(valid_stage0 & ready_stage0)
			// upsample_x_cnt_at_last ? 0:(upsample_x_cnt + 1)
			upsample_x_cnt <= # simulation_delay 
				{(clogb2(max_feature_w/feature_n_per_clk-1)+1){~upsample_x_cnt_at_last}} & (upsample_x_cnt + 1);
	end
	// 输入特征图y位置计数器
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			in_ft_map_y_cnt <= 0;
		else if(s_axis_valid & s_axis_ready & upsample_x_cnt_at_last)
			// in_ft_map_y_cnt_at_last ? 0:(in_ft_map_y_cnt + 1)
			in_ft_map_y_cnt <= # simulation_delay 
				{(clogb2(max_feature_h-1)+1){~in_ft_map_y_cnt_at_last}} & (in_ft_map_y_cnt + 1);
	end
	// 输入特征图通道号计数器
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			in_ft_map_chn_id_cnt <= 0;
		else if(s_axis_valid & s_axis_ready & upsample_x_cnt_at_last & in_ft_map_y_cnt_at_last)
			// in_ft_map_chn_id_cnt_at_last ? 0:(in_ft_map_chn_id_cnt + 1)
			in_ft_map_chn_id_cnt <= # simulation_delay 
				{(clogb2(max_feature_chn_n-1)+1){~in_ft_map_chn_id_cnt_at_last}} & (in_ft_map_chn_id_cnt + 1);
	end
	
	/** 列填充 **/
	reg[feature_n_per_clk*feature_data_width-1:0] features_d; // 延迟1clk的输入特征点
	reg is_at_row_stuff_stage_d; // 延迟1clk的是否处于行填充阶段(标志)
	reg[feature_n_per_clk*feature_data_width-1:0] col_stuff_feature_d; // 延迟1clk的列填充特征点
	
	genvar col_stuff_i;
	generate
		for(col_stuff_i = 0;col_stuff_i < feature_n_per_clk;col_stuff_i = col_stuff_i + 1)
		begin
			assign m_axis_data[(col_stuff_i+1)*feature_data_width*2-1:col_stuff_i*feature_data_width*2] = 
				{2{col_stuff_feature_d[(col_stuff_i+1)*feature_data_width-1:col_stuff_i*feature_data_width]}};
		end
	endgenerate
	
	// 流水线第1级数据有效
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			valid_stage1 <= 1'b0;
		else if((~valid_stage1) | ready_stage1)
			valid_stage1 <= # simulation_delay valid_stage0;
	end
	
	// 延迟1clk的输入特征点
	always @(posedge clk)
	begin
		if(valid_stage0 & ready_stage0)
			features_d <= # simulation_delay s_axis_data;
	end
	
	// 延迟1clk的是否处于行填充阶段(标志)
	always @(posedge clk)
	begin
		if(valid_stage0 & ready_stage0)
			is_at_row_stuff_stage_d <= # simulation_delay is_at_row_stuff_stage;
	end
	
	// 流水线第2级数据有效
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			valid_stage2 <= 1'b0;
		else if(ready_stage1)
			valid_stage2 <= # simulation_delay valid_stage1;
	end
	
	// 延迟1clk的列填充特征点
	always @(posedge clk)
	begin
		if(valid_stage1 & ready_stage1)
			col_stuff_feature_d <= # simulation_delay is_at_row_stuff_stage_d ? line_buf_dout_b:features_d;
	end
	
	/** 特征点位置标志 **/
	reg feature_col_last_d; // 延迟1clk的最后1列标志
	reg feature_row_last_d; // 延迟1clk的最后1行标志
	reg feature_chn_last_d; // 延迟1clk的最后1通道标志
	reg feature_col_last_d2; // 延迟2clk的最后1列标志
	reg feature_row_last_d2; // 延迟2clk的最后1行标志
	reg feature_chn_last_d2; // 延迟2clk的最后1通道标志
	reg feature_last_d2; // 延迟2clk的最后1个特征点标志
	
	assign m_axis_user = {feature_chn_last_d2, feature_row_last_d2, feature_col_last_d2};
	assign m_axis_last = feature_last_d2;
	
	// 延迟1clk的最后1列标志
	always @(posedge clk)
	begin
		if(valid_stage0 & ready_stage0)
			feature_col_last_d <= # simulation_delay upsample_x_cnt_at_last;
	end
	// 延迟1clk的最后1行标志
	always @(posedge clk)
	begin
		if(valid_stage0 & ready_stage0)
			feature_row_last_d <= # simulation_delay is_at_row_stuff_stage & row_stuff_pos[0];
	end
	// 延迟1clk的最后1通道标志
	always @(posedge clk)
	begin
		if(valid_stage0 & ready_stage0)
			feature_chn_last_d <= # simulation_delay is_at_row_stuff_stage ? row_stuff_pos[1]:in_ft_map_chn_id_cnt_at_last;
	end
	
	// 延迟2clk的最后1列标志
	always @(posedge clk)
	begin
		if(valid_stage1 & ready_stage1)
			feature_col_last_d2 <= # simulation_delay feature_col_last_d;
	end
	// 延迟2clk的最后1行标志
	always @(posedge clk)
	begin
		if(valid_stage1 & ready_stage1)
			feature_row_last_d2 <= # simulation_delay feature_row_last_d;
	end
	// 延迟2clk的最后1通道标志
	always @(posedge clk)
	begin
		if(valid_stage1 & ready_stage1)
			feature_chn_last_d2 <= # simulation_delay feature_chn_last_d;
	end
	// 延迟2clk的最后1个特征点标志
	always @(posedge clk)
	begin
		if(valid_stage1 & ready_stage1)
			feature_last_d2 <= # simulation_delay feature_chn_last_d & feature_row_last_d & feature_col_last_d;
	end
    
endmodule
