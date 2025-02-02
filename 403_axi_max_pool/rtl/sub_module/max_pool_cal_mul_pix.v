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
本模块: 最大池化计算单元(多像素/clk)

描述:
实现神经网络中的最大池化计算(max pool)
支持当步长为1时向左/右填充
池化窗口大小为2x2
2级流水线

步长 = 2时, 
1 1 2 2
3 4 3 1  -->  4 3

步长 = 1时, 
[2] 1 1 2 2
[7] 3 4 3 1  -->  [7] 4 4 3 [2]

注意：
最大值比较均为有符号比较

协议:
无

作者: 陈家耀
日期: 2024/09/13
********************************************************************/


module max_pool_cal_mul_pix #(
	parameter integer feature_n_per_clk = 2, // 每个clk输入的特征点数量(2 | 4 | 8 | 16 | ...)
	parameter integer feature_data_width = 8, // 特征点位宽(必须能被8整除, 且>0)
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 运行时参数
	input wire step_type, // 步长类型(1'b0 -> 步长为1, 1'b1 -> 步长为2)
	input wire[1:0] padding_vec, // 外拓填充向量(仅当步长为1时可用, {左, 右})
	
	// 池化ROI输入
	input wire[feature_n_per_clk*feature_data_width-1:0] pool_roi_r1, // 池化ROI第1行
	input wire[feature_n_per_clk*feature_data_width-1:0] pool_roi_r2, // 池化ROI第2行
	input wire[feature_n_per_clk-1:0] pool_roi_keep, // 池化ROI特征项使能掩码
	input wire[feature_data_width-1:0] pool_left_buf_r1, // 池化ROI第1行剩余缓存
	input wire[feature_data_width-1:0] pool_left_buf_r2, // 池化ROI第2行剩余缓存
	input wire pool_x_eq0, // 池化x坐标 == 0(标志)
	input wire[2:0] pool_roi_user, // {当前处于最后1个通道, 当前处于最后1行, 当前处于最后1列}
	input wire pool_roi_last, // 特征图最后1点
	input wire pool_roi_valid,
	output wire pool_roi_ready,
	
	// 计算结果输出
	output wire[(feature_n_per_clk+1)*feature_data_width-1:0] pool_res,
	output wire[(feature_n_per_clk+1)*feature_data_width/8-1:0] pool_res_keep,
	output wire[2:0] pool_res_user, // {当前处于最后1个通道, 当前处于最后1行, 当前处于最后1列}
	output wire pool_res_last, // 特征图最后1点
	output wire pool_res_valid,
	input wire pool_res_ready
);
	
	/**
	池化ROI特征点
	
	行1 [剩余缓存] #0 #1 ... #(feature_n_per_clk-1)
	行2 [剩余缓存] #0 #1 ... #(feature_n_per_clk-1)
	**/
	wire[feature_data_width-1:0] pool_roi_r1_features[feature_n_per_clk:0]; // 池化ROI第1行特征点
	wire[feature_data_width-1:0] pool_roi_r2_features[feature_n_per_clk:0]; // 池化ROI第2行特征点
	
	assign pool_roi_r1_features[0] = pool_left_buf_r1;
	assign pool_roi_r2_features[0] = pool_left_buf_r2;
	
	genvar pool_roi_feature_i;
	generate
		for(pool_roi_feature_i = 0;pool_roi_feature_i < feature_n_per_clk;pool_roi_feature_i = pool_roi_feature_i + 1)
		begin
			assign pool_roi_r1_features[pool_roi_feature_i+1] = 
				pool_roi_r1[(pool_roi_feature_i+1)*feature_data_width-1:pool_roi_feature_i*feature_data_width];
			assign pool_roi_r2_features[pool_roi_feature_i+1] = 
				pool_roi_r2[(pool_roi_feature_i+1)*feature_data_width-1:pool_roi_feature_i*feature_data_width];
		end
	endgenerate
	
	/** 流水线控制 **/
	reg valid_stage1;
	wire ready_stage1;
	reg valid_stage2;
	wire ready_stage2;
	
	assign pool_roi_ready = (~valid_stage1) | ready_stage1;
	assign ready_stage1 = (~valid_stage2) | ready_stage2;
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			valid_stage1 <= 1'b0;
		else if(pool_roi_ready)
			valid_stage1 <= # simulation_delay pool_roi_valid;
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			valid_stage2 <= 1'b0;
		else if(ready_stage1)
			valid_stage2 <= # simulation_delay valid_stage1;
	end
	
	/** 输出流处理 **/
	// 原始结果
	wire[(feature_n_per_clk+1)*feature_data_width-1:0] pool_res_flattened; // 原始的池化结果
	wire[feature_n_per_clk:0] org_keep; // 原始的结果特征点有效标志
	wire[2:0] org_pos_flag; // 原始的像素流位置标志
	wire org_last_flag; // 原始的特征图最后1点标志
	
	assign pool_res = pool_res_flattened;
	
	genvar org_keep_i;
	generate
		for(org_keep_i = 0;org_keep_i < feature_n_per_clk + 1;org_keep_i = org_keep_i + 1)
		begin
			assign pool_res_keep[(org_keep_i+1)*feature_data_width/8-1:org_keep_i*feature_data_width/8] = 
				{(feature_data_width/8){org_keep[org_keep_i]}};
		end
	endgenerate
	
	assign pool_res_user = org_pos_flag;
	assign pool_res_last = org_last_flag;
	assign pool_res_valid = valid_stage2;
	
	assign ready_stage2 = pool_res_ready;
	
	/**
	第1级
	
	池化ROI列内取最大值
	
	[2] 1 1 2 2
	[7] 3 4 3 1  -->  [7] 3 4 3 2
	**/
	reg[feature_data_width-1:0] pool_roi_col_max[feature_n_per_clk:0]; // 列内最大值
	reg pool_x_neq0_d; // 延迟1clk的池化x坐标 != 0(标志)
	reg[2:0] pool_roi_user_d; // 延迟1clk的像素流的位置标志
	reg pool_roi_last_d; // 延迟1clk的特征图最后1点(标志)
	reg[feature_n_per_clk-1:0] pool_roi_keep_d; // 延迟1clk的池化ROI特征项使能掩码
	
	// (feature_n_per_clk + 1)个最大值求解器用于计算列内最大值
	genvar pool_roi_col_max_i;
	generate
		for(pool_roi_col_max_i = 0;pool_roi_col_max_i < feature_n_per_clk + 1;pool_roi_col_max_i = pool_roi_col_max_i + 1)
		begin
			always @(posedge clk)
			begin
				if(pool_roi_valid & pool_roi_ready)
					pool_roi_col_max[pool_roi_col_max_i] <= # simulation_delay 
						($signed(pool_roi_r1_features[pool_roi_col_max_i]) > $signed(pool_roi_r2_features[pool_roi_col_max_i])) ?
							pool_roi_r1_features[pool_roi_col_max_i]:pool_roi_r2_features[pool_roi_col_max_i];
			end
		end
	endgenerate
	
	// 延迟1clk的池化x坐标 != 0(标志)
	always @(posedge clk)
	begin
		if(pool_roi_valid & pool_roi_ready)
			pool_x_neq0_d <= # simulation_delay ~pool_x_eq0;
	end
	
	// 延迟1clk的像素流的位置标志
	always @(posedge clk)
	begin
		if(pool_roi_valid & pool_roi_ready)
			pool_roi_user_d <= # simulation_delay pool_roi_user;
	end
	
	// 延迟1clk的特征图最后1点(标志)
	always @(posedge clk)
	begin
		if(pool_roi_valid & pool_roi_ready)
			pool_roi_last_d <= # simulation_delay pool_roi_last;
	end
	
	// 延迟1clk的池化ROI特征项使能掩码
	always @(posedge clk)
	begin
		if(pool_roi_valid & pool_roi_ready)
			pool_roi_keep_d <= # simulation_delay pool_roi_keep;
	end
	
	/**
	第2级
	
	合并列内最大值, 得到池化结果
	
	[7] 3 4 3 2 --> [7] 4 4 3 [2]
	**/
	reg[feature_data_width-1:0] pool_res_max[feature_n_per_clk:0]; // 池化结果
	reg[feature_n_per_clk:0] pool_res_item_keep; // 池化结果特征项使能掩码
	reg[2:0] pool_roi_user_d2; // 延迟2clk的像素流的位置标志
	reg pool_roi_last_d2; // 延迟2clk的特征图最后1点(标志)
	
	// 将池化结果平坦化
	genvar pool_res_flattened_i;
	generate
		for(pool_res_flattened_i = 0;pool_res_flattened_i < feature_n_per_clk + 1;pool_res_flattened_i = pool_res_flattened_i + 1)
		begin
			assign pool_res_flattened[(pool_res_flattened_i+1)*feature_data_width-1:pool_res_flattened_i*feature_data_width] = 
				pool_res_max[pool_res_flattened_i];
		end
	endgenerate
	
	assign org_keep = pool_res_item_keep;
	assign org_pos_flag = pool_roi_user_d2;
	assign org_last_flag = pool_roi_last_d2;
	
	// 第0~(feature_n_per_clk-1)个池化结果, 需要feature_n_per_clk个最大值求解器
	genvar pool_res_max_i;
	generate
		for(pool_res_max_i = 0;pool_res_max_i < feature_n_per_clk;pool_res_max_i = pool_res_max_i + 1)
		begin
			always @(posedge clk)
			begin
				if(valid_stage1 & ready_stage1)
					pool_res_max[pool_res_max_i] <= # simulation_delay 
						($signed(pool_roi_col_max[pool_res_max_i]) > $signed(pool_roi_col_max[pool_res_max_i + 1])) ? 
						pool_roi_col_max[pool_res_max_i]:pool_roi_col_max[pool_res_max_i + 1];
			end
		end
	endgenerate
	// 第feature_n_per_clk个池化结果直接由最后1列最大值得到
	always @(posedge clk)
	begin
		if(valid_stage1 & ready_stage1)
			pool_res_max[feature_n_per_clk] <= # simulation_delay pool_roi_col_max[feature_n_per_clk];
	end
	
	// 池化结果特征项使能掩码
	always @(posedge clk)
	begin
		if(valid_stage1 & ready_stage1)
			pool_res_item_keep <= # simulation_delay 
				step_type ? 
					// 步长为2
					{1'b0, {(feature_n_per_clk/2){2'b10}} & pool_roi_keep_d}
					// 步长为1
					:(({1'b0, pool_roi_keep_d} & {{feature_n_per_clk{1'b1}}, padding_vec[1] | pool_x_neq0_d}) // 左填充
						| ({pool_roi_keep_d, 1'b0} & {(feature_n_per_clk+1){pool_roi_user_d[0] & padding_vec[0]}})); // 右填充
	end
	
	// 延迟2clk的像素流的位置标志
	always @(posedge clk)
	begin
		if(valid_stage1 & ready_stage1)
			pool_roi_user_d2 <= # simulation_delay pool_roi_user_d;
	end
	
	// 延迟2clk的特征图最后1点(标志)
	always @(posedge clk)
	begin
		if(valid_stage1 & ready_stage1)
			pool_roi_last_d2 <= # simulation_delay pool_roi_last_d;
	end
	
endmodule
