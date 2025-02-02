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
本模块: 最大池化行填充处理单元

描述:
当步长为1时, 对输入特征图进行可选的上/下边界填充
填充上边界 -> 有效特征图 -> 填充下边界

注意：
无

协议:
BLK CTRL
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2024/10/11
********************************************************************/


module max_pool_row_padding #(
    parameter integer feature_n_per_clk = 4, // 每个clk输入的特征点数量(2 | 4 | 8 | 16 | ...)
	parameter integer feature_data_width = 8, // 特征点位宽(必须能被8整除, 且>0)
	parameter integer max_feature_chn_n = 128, // 最大的特征图通道数
	parameter integer max_feature_w = 128, // 最大的输入特征图宽度
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
	input wire[1:0] padding_vec, // 外拓填充向量(仅当步长为1时可用, {上, 下})
	input wire[15:0] feature_map_chn_n, // 特征图通道数 - 1
	input wire[15:0] feature_map_w, // 特征图宽度 - 1
	
	// 行填充输入
	input wire[feature_n_per_clk*feature_data_width-1:0] s_axis_data,
	input wire[2:0] s_axis_user, // {当前处于最后1个通道, 当前处于最后1行, 当前处于最后1列}
	input wire[feature_n_per_clk*feature_data_width/8-1:0] s_axis_keep,
	input wire s_axis_last, // 指示最后1个特征组
	input wire s_axis_valid,
	output wire s_axis_ready,
	
	// 行填充输出
	output wire[feature_n_per_clk*feature_data_width-1:0] m_axis_data,
	output wire[2:0] m_axis_user, // {当前处于最后1个通道, 当前处于最后1行, 当前处于最后1列}
	output wire[feature_n_per_clk*feature_data_width/8-1:0] m_axis_keep,
	output wire m_axis_last, // 指示最后1个特征组
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
	
	/** 常量 **/
	localparam integer stream_data_width = feature_n_per_clk*feature_data_width; // 像素流位宽
	
	/** 输出寄存器片 **/
	// AXIS从机
	wire[stream_data_width-1:0] s_axis_reg_slice_data;
    wire[stream_data_width/8-1:0] s_axis_reg_slice_keep;
    wire[2:0] s_axis_reg_slice_user;
    wire s_axis_reg_slice_last;
    wire s_axis_reg_slice_valid;
    wire s_axis_reg_slice_ready;
	// AXIS主机
	wire[stream_data_width-1:0] m_axis_reg_slice_data;
    wire[stream_data_width/8-1:0] m_axis_reg_slice_keep;
    wire[2:0] m_axis_reg_slice_user;
    wire m_axis_reg_slice_last;
    wire m_axis_reg_slice_valid;
    wire m_axis_reg_slice_ready;
	
	assign m_axis_data = m_axis_reg_slice_data;
	assign m_axis_user = m_axis_reg_slice_user;
	assign m_axis_keep = m_axis_reg_slice_keep;
	assign m_axis_last = m_axis_reg_slice_last;
	assign m_axis_valid = m_axis_reg_slice_valid;
	assign m_axis_reg_slice_ready = m_axis_ready;
	
	axis_reg_slice #(
		.data_width(stream_data_width),
		.user_width(3),
		.forward_registered(en_out_reg_slice),
		.back_registered(en_out_reg_slice),
		.en_ready("true"),
		.simulation_delay(simulation_delay)
	)out_reg_slice(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axis_data(s_axis_reg_slice_data),
		.s_axis_keep(s_axis_reg_slice_keep),
		.s_axis_user(s_axis_reg_slice_user),
		.s_axis_last(s_axis_reg_slice_last),
		.s_axis_valid(s_axis_reg_slice_valid),
		.s_axis_ready(s_axis_reg_slice_ready),
		
		.m_axis_data(m_axis_reg_slice_data),
		.m_axis_keep(m_axis_reg_slice_keep),
		.m_axis_user(m_axis_reg_slice_user),
		.m_axis_last(m_axis_reg_slice_last),
		.m_axis_valid(m_axis_reg_slice_valid),
		.m_axis_ready(m_axis_reg_slice_ready)
	);
	
	/** 块级控制 **/
	reg blk_idle_reg;
	
	assign blk_idle = blk_idle_reg;
	
	// 行填充器空闲标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			blk_idle_reg <= 1'b1;
		else
			blk_idle_reg <= # simulation_delay blk_idle ? (~blk_start):blk_done;
	end
	
	/** 行填充 **/
	reg[2:0] row_padding_sts; // 行填充状态(3'b001 -> 填充上边界, 3'b010 -> 有效特征图, 3'b100 -> 填充下边界)
	reg[clogb2(max_feature_w/feature_n_per_clk-1):0] padding_col_id_cnt; // 行填充列号计数器
	wire padding_last_col; // 填充最后1列(标志)
	reg[clogb2(max_feature_chn_n-1):0] chn_id_cnt; // 通道号计数器
	wire last_chn; // 最后1通道(标志)
	wire[stream_data_width/8-1:0] padding_keep; // 填充时的字节有效标志
	
	assign blk_done = (~blk_idle) & 
		row_padding_sts[2] & (step_type | (~padding_vec[0]) | (s_axis_reg_slice_ready & padding_last_col)) & last_chn;
	
	assign s_axis_ready = (~blk_idle) & row_padding_sts[1] & s_axis_reg_slice_ready;
	
	assign s_axis_reg_slice_data = {stream_data_width{row_padding_sts[1]}} & s_axis_data; // row_padding_sts[1] ? s_axis_data:{stream_data_width{1'b0}}
	assign s_axis_reg_slice_keep = row_padding_sts[1] ? s_axis_keep:padding_keep;
	assign s_axis_reg_slice_user = {
		last_chn,
		(row_padding_sts[1] & s_axis_user[1] & (step_type | (~padding_vec[0]))) | row_padding_sts[2],
		((row_padding_sts[0] | row_padding_sts[2]) & padding_last_col) | (row_padding_sts[1] & s_axis_user[0])
	};
	assign s_axis_reg_slice_last = (row_padding_sts[1] & s_axis_last & (step_type | (~padding_vec[0])))
		| (row_padding_sts[2] & last_chn & padding_last_col);
	assign s_axis_reg_slice_valid = (~blk_idle)
		& ((row_padding_sts[0] & (~step_type) & padding_vec[1])
			| (row_padding_sts[1] & s_axis_valid)
			| (row_padding_sts[2] & (~step_type) & padding_vec[0]));
	
	assign padding_last_col = padding_col_id_cnt == feature_map_w[15:clogb2(feature_n_per_clk)];
	assign last_chn = chn_id_cnt == feature_map_chn_n;
	
	// 填充时的字节有效标志
	genvar padding_keep_i;
	generate
		for(padding_keep_i = 0;padding_keep_i < feature_n_per_clk;padding_keep_i = padding_keep_i + 1)
		begin
			assign padding_keep[(padding_keep_i+1)*feature_data_width/8-1:padding_keep_i*feature_data_width/8] = 
				{(feature_data_width/8){(~padding_last_col) | (padding_keep_i <= feature_map_w[clogb2(feature_n_per_clk-1):0])}};
		end
	endgenerate
	
	// 行填充状态
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			row_padding_sts <= 3'b001;
		else if((~blk_idle)
			& ((row_padding_sts[0] & (step_type | (~padding_vec[1]) | (s_axis_reg_slice_ready & padding_last_col)))
				| (row_padding_sts[1] & (s_axis_valid & s_axis_reg_slice_ready & s_axis_user[0] & s_axis_user[1]))
				| (row_padding_sts[2] & (step_type | (~padding_vec[0]) | (s_axis_reg_slice_ready & padding_last_col)))))
			row_padding_sts <= # simulation_delay {row_padding_sts[1:0], row_padding_sts[2]};
	end
	
	// 行填充列号计数器
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			padding_col_id_cnt <= 0;
		else if((~blk_idle)
			& ((row_padding_sts[0] & (~step_type) & padding_vec[1])
				| (row_padding_sts[2] & (~step_type) & padding_vec[0]))
			& s_axis_reg_slice_ready)
			padding_col_id_cnt <= # simulation_delay padding_last_col ? 0:(padding_col_id_cnt + 1);
	end
	
	// 通道号计数器
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			chn_id_cnt <= 0;
		else if(row_padding_sts[2] & (step_type | (~padding_vec[0]) | (s_axis_reg_slice_ready & padding_last_col)))
			chn_id_cnt <= # simulation_delay last_chn ? 0:(chn_id_cnt + 1);
	end
    
endmodule
