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
本模块: AXIS多通道卷积结果缓存区

描述:
                         {多通道卷积结果缓存区}
		                    ################ ---> 输出特征图数据流
		
		                    ################
		
					                      |----|
					                      V    |
卷积核通道累加中间结果 ---> ################   |
				        |            |         |
				        |            |         |
				        |            ----{+}----
		                |
					    |                 |----|
					    |                 V    |
		               ---> ################   |
				                     |         |
				                     |         |
				                     ----{+}----

写多通道卷积结果缓存区每次选定1~kernal_prl_n个缓存, 仅当处于输出特征图最后一组通道时可能选定少于kernal_prl_n个缓存
读多通道卷积结果缓存区每次选定1个缓存

输出特征图数据流 -> 
{
	      {通道#0行#0}             {通道#1行#0}       ...       {通道#(核并行数-1)行#0}
	      {通道#0行#1}             {通道#1行#1}       ...       {通道#(核并行数-1)行#1}
	                                     :
							             :
	{通道#0行#(输出图高度-1)} {通道#1行#(输出图高度-1)} ... {通道#(核并行数-1)行#(输出图高度-1)}
}
{
	      {通道#(核并行数)行#0}             {通道#(核并行数+1)行#0}        ...        {通道#(核并行数*2-1)行#0}
	      {通道#(核并行数)行#1}             {通道#(核并行数+1)行#1}        ...        {通道#(核并行数*2-1)行#1}
	                                                    :
							                            :
	{通道#(核并行数)行#(输出图高度-1)} {通道#(核并行数+1)行#(输出图高度-1)} ... {通道#(核并行数*2-1)行#(输出图高度-1)}
} ... ... {

		  {通道#(输出通道数-?)行#0}        ...        {通道#(输出通道数-1)行#0}
	      {通道#(输出通道数-?)行#1}        ...        {通道#(输出通道数-1)行#1}
	                                        :
							                :
	{通道#(输出通道数-?)行#(输出图高度-1)} ... {通道#(输出通道数-1)行#(输出图高度-1)}
}

$> 	(输出通道数-?) = floor(卷积核个数/核并行数) * 核并行数 - ((卷积核个数 % 核并行数) == 0) * 核并行数

注意：
多通道卷积结果缓存个数(out_buffer_n)必须>=多通道卷积核的并行个数(kernal_prl_n)

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2024/12/25
********************************************************************/


module axis_conv_out_buffer #(
	parameter integer ft_ext_width = 32, // 特征点拓展位宽(16 | 32)
	parameter integer ft_vld_width = 20, // 特征点有效位宽(必须<=ft_ext_width)
	parameter integer kernal_prl_n = 4, // 多通道卷积核的并行个数(1 | 2 | 4 | 8 | 16)
	parameter integer out_buffer_n = 8, // 多通道卷积结果缓存个数
	parameter integer max_feature_map_w = 512, // 最大的输入特征图宽度
	parameter integer max_feature_map_h = 512, // 最大的输入特征图高度
	parameter integer max_kernal_n = 512, // 最大的卷积核个数
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 使能
	input wire en_conv_cal, // 是否使能卷积计算
	
	// 运行时参数
	input wire kernal_type, // 卷积核类型(1'b0 -> 1x1, 1'b1 -> 3x3)
	input wire[1:0] padding_en, // 外拓填充使能(仅当卷积核类型为3x3时可用, {左, 右})
	input wire[15:0] o_ft_map_w, // 输出特征图宽度 - 1
	input wire[15:0] o_ft_map_h, // 输出特征图高度 - 1
	input wire[15:0] kernal_n, // 卷积核个数 - 1
	
	// 卷积核通道累加中间结果输入(AXIS从机)
	// {核#(m-1)结果, ..., 核#1结果, 核#0结果}
	// 每个中间结果仅低ft_vld_width位有效
	input wire[ft_ext_width*kernal_prl_n-1:0] s_axis_mid_res_data,
	input wire s_axis_mid_res_last, // 表示行尾
	input wire s_axis_mid_res_user, // 表示当前行最后1组结果
	input wire s_axis_mid_res_valid,
	output wire s_axis_mid_res_ready,
	
	// 输出特征图数据流输出(AXIS主机)
	// 特征图数据仅低ft_vld_width位有效
	output wire[ft_ext_width-1:0] m_axis_ft_out_data,
	output wire[15:0] m_axis_ft_out_user, // 当前输出特征行所在的通道号
	output wire m_axis_ft_out_last, // 表示行尾
	output wire m_axis_ft_out_valid,
	input wire m_axis_ft_out_ready
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
	
	/** 卷积核通道累加中间结果写位置 **/
	reg[clogb2(max_feature_map_w-1):0] mul_chn_conv_mid_res_wt_pos_x; // x坐标
	reg mul_chn_conv_mid_res_wt_at_first_batch; // 处于第1批(标志)
	reg[clogb2(max_feature_map_h-1):0] mul_chn_conv_mid_res_wt_pos_y; // y坐标
	wire mul_chn_conv_mid_res_wt_at_last_row; // 处于最后1行(标志)
	reg[clogb2(max_kernal_n/kernal_prl_n-1):0] mul_chn_conv_mid_res_wt_pos_chn_grp; // 通道组号
	wire mul_chn_conv_mid_res_wt_at_last_chn_grp; // 处于最后1个通道组(标志)
	reg[clogb2(kernal_prl_n):0] mul_chn_conv_mid_res_wt_last_chn_grp_vld_n; // 最后1个通道组的有效通道个数
	reg[kernal_prl_n-1:0] mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask; // 最后1个通道组的有效通道掩码
	
	assign mul_chn_conv_mid_res_wt_at_last_row = mul_chn_conv_mid_res_wt_pos_y == o_ft_map_h[clogb2(max_feature_map_h-1):0];
	assign mul_chn_conv_mid_res_wt_at_last_chn_grp = 
		// 每个通道组包含kernal_prl_n个通道
		mul_chn_conv_mid_res_wt_pos_chn_grp == kernal_n[clogb2(max_kernal_n-1):clogb2(kernal_prl_n)];
	
	// 最后1个通道组的有效通道个数
	generate
		if(kernal_prl_n > 1)
		begin
			always @(posedge clk)
			begin
				if(en_conv_cal)
					mul_chn_conv_mid_res_wt_last_chn_grp_vld_n <= # simulation_delay 
						kernal_n[clogb2(kernal_prl_n-1):0] + 1'b1;
			end
		end
		else
		begin
			always @(*)
				mul_chn_conv_mid_res_wt_last_chn_grp_vld_n = 1'b1;
		end
	endgenerate
	
	// 最后1个通道组的有效通道掩码
	genvar mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask_i;
	generate
		if(kernal_prl_n > 1)
		begin
			for(mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask_i = 0;mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask_i < kernal_prl_n;
				mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask_i = mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask_i + 1)
			begin
				always @(posedge clk)
				begin
					if(en_conv_cal)
						mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask[mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask_i] <= 
							# simulation_delay kernal_n[clogb2(kernal_prl_n-1):0] >= mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask_i;
				end
			end
		end
		else
		begin
			always @(*)
				mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask = 1'b1;
		end
	endgenerate
	
	// 当前写卷积核通道累加中间结果的x坐标
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_mid_res_wt_pos_x <= 0;
		else if(s_axis_mid_res_valid & s_axis_mid_res_ready)
			mul_chn_conv_mid_res_wt_pos_x <= # simulation_delay 
				// s_axis_mid_res_last ? 0:(mul_chn_conv_mid_res_wt_pos_x + 1)
				{(clogb2(max_feature_map_w-1)+1){~s_axis_mid_res_last}} & 
				(mul_chn_conv_mid_res_wt_pos_x + 1);
	end
	
	// 当前写卷积核通道累加中间结果处于第1批标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_mid_res_wt_at_first_batch <= 1'b1;
		else if(s_axis_mid_res_valid & s_axis_mid_res_ready & s_axis_mid_res_last)
			mul_chn_conv_mid_res_wt_at_first_batch <= # simulation_delay s_axis_mid_res_user;
	end
	
	// 当前写卷积核通道累加中间结果的y坐标
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_mid_res_wt_pos_y <= 0;
		else if(s_axis_mid_res_valid & s_axis_mid_res_ready & s_axis_mid_res_last 
			& s_axis_mid_res_user)
			mul_chn_conv_mid_res_wt_pos_y <= # simulation_delay 
				// mul_chn_conv_mid_res_wt_at_last_row ? 0:(mul_chn_conv_mid_res_wt_pos_y + 1)
				{(clogb2(max_feature_map_h-1)+1){~mul_chn_conv_mid_res_wt_at_last_row}} & 
				(mul_chn_conv_mid_res_wt_pos_y + 1);
	end
	
	// 当前写卷积核通道累加中间结果的通道组号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_mid_res_wt_pos_chn_grp <= 0;
		else if(s_axis_mid_res_valid & s_axis_mid_res_ready & s_axis_mid_res_last 
			& s_axis_mid_res_user & mul_chn_conv_mid_res_wt_at_last_row)
			mul_chn_conv_mid_res_wt_pos_chn_grp <= # simulation_delay 
				// mul_chn_conv_mid_res_wt_at_last_chn_grp ? 0:(mul_chn_conv_mid_res_wt_pos_chn_grp + 1)
				{(clogb2(max_kernal_n/kernal_prl_n-1)+1){~mul_chn_conv_mid_res_wt_at_last_chn_grp}} & 
				(mul_chn_conv_mid_res_wt_pos_chn_grp + 1);
	end
	
    /** 多通道卷积结果缓存区fifo控制 **/
	// fifo存储计数
	reg[clogb2(out_buffer_n):0] mul_chn_conv_res_buf_fifo_str_n; // 当前的存储个数
	wire[clogb2(out_buffer_n):0] mul_chn_conv_res_buf_fifo_str_n_to_add; // 当前写入时增加的存储个数
	// fifo写端口
	wire mul_chn_conv_res_buf_fifo_wen;
	wire mul_chn_conv_res_buf_fifo_full_n;
	reg[clogb2(out_buffer_n-1):0] mul_chn_conv_res_buf_fifo_wsel_cur; // 当前的写缓存起始编号
	wire[clogb2(out_buffer_n-1)+1:0] mul_chn_conv_res_buf_fifo_wsel_add_res; // 下一写缓存起始编号(增量结果)
	wire[clogb2(out_buffer_n-1):0] mul_chn_conv_res_buf_fifo_wsel_nxt; // 下一写缓存起始编号
	// fifo读端口
	wire mul_chn_conv_res_buf_fifo_ren;
	wire mul_chn_conv_res_buf_fifo_empty_n;
	reg[out_buffer_n-1:0] mul_chn_conv_res_buf_fifo_rptr;
	
	// 握手条件: s_axis_mid_res_valid & mul_chn_conv_res_buf_fifo_full_n
	assign s_axis_mid_res_ready = mul_chn_conv_res_buf_fifo_full_n;
	
	// 握手条件: s_axis_mid_res_valid & mul_chn_conv_res_buf_fifo_full_n & s_axis_mid_res_last & s_axis_mid_res_user
	assign mul_chn_conv_res_buf_fifo_wen = s_axis_mid_res_valid & s_axis_mid_res_last & s_axis_mid_res_user;
	
	// 至少剩余kernal_prl_n个缓存可写时非满
	assign mul_chn_conv_res_buf_fifo_full_n = mul_chn_conv_res_buf_fifo_str_n <= (out_buffer_n - kernal_prl_n);
	
	// 至少存储了1个缓存时非空
	assign mul_chn_conv_res_buf_fifo_empty_n = |mul_chn_conv_res_buf_fifo_str_n;
	
	assign mul_chn_conv_res_buf_fifo_str_n_to_add = mul_chn_conv_mid_res_wt_at_last_chn_grp ? 
		mul_chn_conv_mid_res_wt_last_chn_grp_vld_n:
		kernal_prl_n;
	
	assign mul_chn_conv_res_buf_fifo_wsel_add_res = 
		mul_chn_conv_res_buf_fifo_wsel_cur + mul_chn_conv_res_buf_fifo_str_n_to_add;
	assign mul_chn_conv_res_buf_fifo_wsel_nxt = 
		(mul_chn_conv_res_buf_fifo_wsel_add_res >= out_buffer_n) ? 
			(mul_chn_conv_res_buf_fifo_wsel_add_res - out_buffer_n):mul_chn_conv_res_buf_fifo_wsel_add_res;
	
	// 当前的存储个数
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_res_buf_fifo_str_n <= 0;
		else if((mul_chn_conv_res_buf_fifo_wen & mul_chn_conv_res_buf_fifo_full_n) | 
			(mul_chn_conv_res_buf_fifo_ren & mul_chn_conv_res_buf_fifo_empty_n))
			mul_chn_conv_res_buf_fifo_str_n <= # simulation_delay 
				mul_chn_conv_res_buf_fifo_str_n
				+ ({(clogb2(out_buffer_n)+1){mul_chn_conv_res_buf_fifo_wen & mul_chn_conv_res_buf_fifo_full_n}} & 
					mul_chn_conv_res_buf_fifo_str_n_to_add)
				+ {(clogb2(out_buffer_n)+1){mul_chn_conv_res_buf_fifo_ren & mul_chn_conv_res_buf_fifo_empty_n}};
	end
	
	// 当前的写缓存起始编号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_res_buf_fifo_wsel_cur <= 0;
		else if(mul_chn_conv_res_buf_fifo_wen & mul_chn_conv_res_buf_fifo_full_n)
			mul_chn_conv_res_buf_fifo_wsel_cur <= # simulation_delay mul_chn_conv_res_buf_fifo_wsel_nxt;
	end
	
	// 读指针
	generate
		if(out_buffer_n > 1)
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					mul_chn_conv_res_buf_fifo_rptr <= {{(out_buffer_n-1){1'b0}}, 1'b1};
				else if(mul_chn_conv_res_buf_fifo_ren & mul_chn_conv_res_buf_fifo_empty_n)
					mul_chn_conv_res_buf_fifo_rptr <= # simulation_delay 
						{mul_chn_conv_res_buf_fifo_rptr[out_buffer_n-2:0], mul_chn_conv_res_buf_fifo_rptr[out_buffer_n-1]};
			end
		end
		else
		begin
			always @(*)
				mul_chn_conv_res_buf_fifo_rptr = 1'b1;
		end
	endgenerate
	
	/** 写多通道卷积结果缓存区 **/
	wire[ft_vld_width*out_buffer_n-1:0] mid_res_flattened; // 展平的卷积中间结果
	wire[ft_vld_width*out_buffer_n-1:0] mid_res_shifted; // 移位的卷积中间结果
	wire[ft_vld_width-1:0] mid_res_to_wt[0:out_buffer_n-1]; // 待写入缓存区的卷积中间结果
	wire[out_buffer_n-1:0] mul_chn_conv_res_buf_fifo_wmask_org; // 起始写掩码
	wire[out_buffer_n-1:0] mul_chn_conv_res_buf_fifo_wmask; // 写掩码
	
	genvar mid_res_flattened_i;
	generate
		for(mid_res_flattened_i = 0;mid_res_flattened_i < out_buffer_n;mid_res_flattened_i = mid_res_flattened_i + 1)
		begin
			assign mid_res_flattened[(mid_res_flattened_i+1)*ft_vld_width-1:
				mid_res_flattened_i*ft_vld_width] = 
				(mid_res_flattened_i < kernal_prl_n) ? 
				s_axis_mid_res_data[mid_res_flattened_i*ft_ext_width+ft_vld_width-1:
					mid_res_flattened_i*ft_ext_width]:
				{ft_vld_width{1'bx}};
		end
	endgenerate
	
	// 循环左移mul_chn_conv_res_buf_fifo_wsel_cur*ft_vld_width位, 仅保留out_buffer_n种情况
	assign mid_res_shifted = 
		(mul_chn_conv_res_buf_fifo_wsel_cur >= out_buffer_n) ? 
			{(ft_vld_width*out_buffer_n){1'bx}}:
			((mid_res_flattened << (mul_chn_conv_res_buf_fifo_wsel_cur*ft_vld_width)) | 
			(mid_res_flattened >> ((out_buffer_n - mul_chn_conv_res_buf_fifo_wsel_cur)*ft_vld_width)));
	
	genvar mid_res_to_wt_i;
	generate
		for(mid_res_to_wt_i = 0;mid_res_to_wt_i < out_buffer_n;mid_res_to_wt_i = mid_res_to_wt_i + 1)
		begin
			assign mid_res_to_wt[mid_res_to_wt_i] = mid_res_shifted[(mid_res_to_wt_i+1)*ft_vld_width-1:
				mid_res_to_wt_i*ft_vld_width];
		end
	endgenerate
	
	generate
		if(out_buffer_n == kernal_prl_n)
			assign mul_chn_conv_res_buf_fifo_wmask_org = 
				{kernal_prl_n{~mul_chn_conv_mid_res_wt_at_last_chn_grp}} | mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask;
		else
			assign mul_chn_conv_res_buf_fifo_wmask_org = {
				{(out_buffer_n-kernal_prl_n){1'b0}}, 
				{{kernal_prl_n{~mul_chn_conv_mid_res_wt_at_last_chn_grp}} | mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask}
			};
	endgenerate
	
	// 循环左移mul_chn_conv_res_buf_fifo_wsel_cur位, 仅保留out_buffer_n种情况
	assign mul_chn_conv_res_buf_fifo_wmask = 
		(mul_chn_conv_res_buf_fifo_wsel_cur >= out_buffer_n) ? 
			{out_buffer_n{1'bx}}:
			((mul_chn_conv_res_buf_fifo_wmask_org << mul_chn_conv_res_buf_fifo_wsel_cur) | 
			(mul_chn_conv_res_buf_fifo_wmask_org >> (out_buffer_n - mul_chn_conv_res_buf_fifo_wsel_cur)));
	
	/** 读多通道卷积结果缓存区 **/
	// 正在更新卷积中间结果(向量)
	wire[out_buffer_n-1:0] conv_mid_res_updating_vec;
	// 读缓存区流水线控制
	wire mul_chn_conv_res_rd_s0_valid;
	wire mul_chn_conv_res_rd_s0_ready;
	wire mul_chn_conv_res_rd_s0_last;
	reg mul_chn_conv_res_rd_s1_valid;
	wire mul_chn_conv_res_rd_s1_ready;
	reg[ft_vld_width-1:0] mul_chn_conv_res_rd_s1_data;
	wire[clogb2(max_kernal_n-1):0] mul_chn_conv_res_rd_s1_user; // 当前输出特征行所在的通道号
	reg mul_chn_conv_res_rd_s1_last;
	reg mul_chn_conv_res_rd_s2_valid;
	wire mul_chn_conv_res_rd_s2_ready;
	reg[ft_vld_width-1:0] mul_chn_conv_res_rd_s2_data;
	reg[clogb2(max_kernal_n-1):0] mul_chn_conv_res_rd_s2_user; // 当前输出特征行所在的通道号
	reg mul_chn_conv_res_rd_s2_last;
	// 延迟1clk的多通道卷积结果缓存区fifo读指针
	reg[out_buffer_n-1:0] mul_chn_conv_res_buf_fifo_rptr_d;
	// 多通道卷积结果缓存区读位置
	reg[clogb2(max_feature_map_w-1):0] mul_chn_conv_res_rd_pos_x; // x坐标
	wire mul_chn_conv_res_rd_last_col; // 处于最后1列(标志)
	reg[clogb2(max_kernal_n-1):0] mul_chn_conv_res_rd_pos_ochn; // 输出通道号
	reg[clogb2(max_feature_map_h-1):0] mul_chn_conv_res_rd_pos_y; // y坐标
	// 多通道卷积结果缓存区读数据
	wire[ft_vld_width-1:0] mul_chn_conv_res_dout[0:out_buffer_n-1];
	wire[ft_vld_width-1:0] mul_chn_conv_res_dout_masked[0:out_buffer_n-1];
	
	generate
		if(ft_ext_width == ft_vld_width)
			assign m_axis_ft_out_data = mul_chn_conv_res_rd_s2_data;
		else
			assign m_axis_ft_out_data = {
				{(ft_ext_width-ft_vld_width){mul_chn_conv_res_rd_s2_data[ft_vld_width-1]}}, // 进行符号位拓展
				mul_chn_conv_res_rd_s2_data
			};
	endgenerate
	
	assign m_axis_ft_out_user = mul_chn_conv_res_rd_s2_user;
	assign m_axis_ft_out_last = mul_chn_conv_res_rd_s2_last;
	// 握手条件: mul_chn_conv_res_rd_s2_valid & m_axis_ft_out_ready
	assign m_axis_ft_out_valid = mul_chn_conv_res_rd_s2_valid;
	
	// 握手条件: (~(|(mul_chn_conv_res_buf_fifo_rptr & conv_mid_res_updating_vec))) & 
	//     mul_chn_conv_res_buf_fifo_empty_n & mul_chn_conv_res_rd_s0_ready & mul_chn_conv_res_rd_last_col
	assign mul_chn_conv_res_buf_fifo_ren = 
		// conv_mid_res_updating_vec[当前读索引] == 1'b0
		(~(|(mul_chn_conv_res_buf_fifo_rptr & conv_mid_res_updating_vec))) & 
		mul_chn_conv_res_rd_last_col & mul_chn_conv_res_rd_s0_ready;
	
	assign mul_chn_conv_res_rd_s0_valid = 
		// conv_mid_res_updating_vec[当前读索引] == 1'b0
		(~(|(mul_chn_conv_res_buf_fifo_rptr & conv_mid_res_updating_vec))) & 
		mul_chn_conv_res_buf_fifo_empty_n;
	assign mul_chn_conv_res_rd_s0_ready = (~mul_chn_conv_res_rd_s1_valid) | mul_chn_conv_res_rd_s1_ready;
	assign mul_chn_conv_res_rd_s0_last = mul_chn_conv_res_rd_last_col;
	assign mul_chn_conv_res_rd_s1_ready = (~mul_chn_conv_res_rd_s2_valid) | mul_chn_conv_res_rd_s2_ready;
	assign mul_chn_conv_res_rd_s1_user = mul_chn_conv_res_rd_pos_ochn;
	// 握手条件: mul_chn_conv_res_rd_s2_valid & m_axis_ft_out_ready
	assign mul_chn_conv_res_rd_s2_ready = m_axis_ft_out_ready;
	
	assign mul_chn_conv_res_rd_last_col = mul_chn_conv_res_rd_pos_x == o_ft_map_w[clogb2(max_feature_map_w-1):0];
	
	genvar mul_chn_conv_res_dout_masked_i;
	generate
		for(mul_chn_conv_res_dout_masked_i = 0;mul_chn_conv_res_dout_masked_i < out_buffer_n;
			mul_chn_conv_res_dout_masked_i = mul_chn_conv_res_dout_masked_i + 1)
		begin
			assign mul_chn_conv_res_dout_masked[mul_chn_conv_res_dout_masked_i] = 
				mul_chn_conv_res_dout[mul_chn_conv_res_dout_masked_i] & 
				{ft_vld_width{mul_chn_conv_res_buf_fifo_rptr_d[mul_chn_conv_res_dout_masked_i]}};
		end
	endgenerate
	
	// 读缓存区流水线各级valid信号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_res_rd_s1_valid <= 1'b0;
		else if(mul_chn_conv_res_rd_s0_ready)
			mul_chn_conv_res_rd_s1_valid <= # simulation_delay mul_chn_conv_res_rd_s0_valid;
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_res_rd_s2_valid <= 1'b0;
		else if(mul_chn_conv_res_rd_s1_ready)
			mul_chn_conv_res_rd_s2_valid <= # simulation_delay mul_chn_conv_res_rd_s1_valid;
	end
	
	// 读缓存区流水线各级的data
	integer mul_chn_conv_res_rd_s1_data_i;
	always @(*)
	begin
		mul_chn_conv_res_rd_s1_data = {ft_vld_width{1'b0}};
		
		for(mul_chn_conv_res_rd_s1_data_i = 0;mul_chn_conv_res_rd_s1_data_i < out_buffer_n;
			mul_chn_conv_res_rd_s1_data_i = mul_chn_conv_res_rd_s1_data_i + 1)
		begin
			mul_chn_conv_res_rd_s1_data = mul_chn_conv_res_rd_s1_data | 
				mul_chn_conv_res_dout_masked[mul_chn_conv_res_rd_s1_data_i];
		end
	end
	
	always @(posedge clk)
	begin
		if(mul_chn_conv_res_rd_s1_valid & mul_chn_conv_res_rd_s1_ready)
			mul_chn_conv_res_rd_s2_data <= # simulation_delay mul_chn_conv_res_rd_s1_data;
	end
	
	// 读缓存区流水线各级user信号
	always @(posedge clk)
	begin
		if(mul_chn_conv_res_rd_s1_valid & mul_chn_conv_res_rd_s1_ready)
			mul_chn_conv_res_rd_s2_user <= # simulation_delay mul_chn_conv_res_rd_s1_user;
	end
	
	// 读缓存区流水线各级last信号
	always @(posedge clk)
	begin
		if(mul_chn_conv_res_rd_s0_valid & mul_chn_conv_res_rd_s0_ready)
			mul_chn_conv_res_rd_s1_last <= # simulation_delay mul_chn_conv_res_rd_s0_last;
	end
	
	always @(posedge clk)
	begin
		if(mul_chn_conv_res_rd_s1_valid & mul_chn_conv_res_rd_s1_ready)
			mul_chn_conv_res_rd_s2_last <= # simulation_delay mul_chn_conv_res_rd_s1_last;
	end
	
	// 延迟1clk的多通道卷积结果缓存区fifo读指针
	always @(posedge clk)
	begin
		if(mul_chn_conv_res_rd_s0_valid & mul_chn_conv_res_rd_s0_ready)
			mul_chn_conv_res_buf_fifo_rptr_d <= # simulation_delay mul_chn_conv_res_buf_fifo_rptr;
	end
	
	// 当前读多通道卷积结果缓存区的x坐标
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_res_rd_pos_x <= 0;
		else if(mul_chn_conv_res_rd_s0_valid & mul_chn_conv_res_rd_s0_ready)
			mul_chn_conv_res_rd_pos_x <= # simulation_delay 
				// mul_chn_conv_res_rd_last_col ? 0:(mul_chn_conv_res_rd_pos_x + 1)
				{(clogb2(max_feature_map_w-1)+1){~mul_chn_conv_res_rd_last_col}} & (mul_chn_conv_res_rd_pos_x + 1);
	end
	
	// 当前读多通道卷积结果缓存区的输出通道号
	generate
		if(kernal_prl_n > 1)
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					mul_chn_conv_res_rd_pos_ochn[clogb2(kernal_prl_n-1):0] <= 0;
				else if(mul_chn_conv_res_rd_s1_valid & mul_chn_conv_res_rd_s1_ready & mul_chn_conv_res_rd_s1_last)
				begin
					mul_chn_conv_res_rd_pos_ochn[clogb2(kernal_prl_n-1):0] <= # simulation_delay 
						// (mul_chn_conv_res_rd_pos_ochn == kernal_n) ? 
						//     0:(mul_chn_conv_res_rd_pos_ochn[clogb2(kernal_prl_n-1):0] + 1)
						{(clogb2(kernal_prl_n-1)+1){mul_chn_conv_res_rd_pos_ochn != kernal_n}} & 
							(mul_chn_conv_res_rd_pos_ochn[clogb2(kernal_prl_n-1):0] + 1);
				end
			end
			
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					mul_chn_conv_res_rd_pos_ochn[clogb2(max_kernal_n-1):clogb2(kernal_prl_n)] <= 0;
				else if(mul_chn_conv_res_rd_s1_valid & mul_chn_conv_res_rd_s1_ready & mul_chn_conv_res_rd_s1_last & 
					((&mul_chn_conv_res_rd_pos_ochn[clogb2(kernal_prl_n-1):0]) | (mul_chn_conv_res_rd_pos_ochn == kernal_n)) & 
					(mul_chn_conv_res_rd_pos_y == o_ft_map_h[clogb2(max_feature_map_h-1):0]))
					mul_chn_conv_res_rd_pos_ochn[clogb2(max_kernal_n-1):clogb2(kernal_prl_n)] <= # simulation_delay 
					// (mul_chn_conv_res_rd_pos_ochn == kernal_n) ? 
					//     0:(mul_chn_conv_res_rd_pos_ochn[clogb2(max_kernal_n-1):clogb2(kernal_prl_n)] + 1)
					{(clogb2(max_kernal_n/kernal_prl_n-1)+1){mul_chn_conv_res_rd_pos_ochn != kernal_n}} & 
						(mul_chn_conv_res_rd_pos_ochn[clogb2(max_kernal_n-1):clogb2(kernal_prl_n)] + 1);
			end
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					mul_chn_conv_res_rd_pos_ochn <= 0;
				else if(mul_chn_conv_res_rd_s1_valid & mul_chn_conv_res_rd_s1_ready & mul_chn_conv_res_rd_s1_last & 
					(mul_chn_conv_res_rd_pos_y == o_ft_map_h[clogb2(max_feature_map_h-1):0]))
					mul_chn_conv_res_rd_pos_ochn <= # simulation_delay 
					// (mul_chn_conv_res_rd_pos_ochn == kernal_n) ? 0:(mul_chn_conv_res_rd_pos_ochn + 1)
					{(clogb2(max_kernal_n-1)+1){mul_chn_conv_res_rd_pos_ochn != kernal_n}} & 
						(mul_chn_conv_res_rd_pos_ochn + 1);
			end
		end
	endgenerate
	
	// 当前读多通道卷积结果缓存区的y坐标
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_res_rd_pos_y <= 0;
		else if(mul_chn_conv_res_rd_s1_valid & mul_chn_conv_res_rd_s1_ready & mul_chn_conv_res_rd_s1_last & 
			((kernal_prl_n == 1) | (&mul_chn_conv_res_rd_pos_ochn[clogb2(kernal_prl_n-1):0]) | 
				(mul_chn_conv_res_rd_pos_ochn == kernal_n)))
			mul_chn_conv_res_rd_pos_y <= # simulation_delay 
			// (mul_chn_conv_res_rd_pos_y == o_ft_map_h[clogb2(max_feature_map_h-1):0]) ? 0:(mul_chn_conv_res_rd_pos_y + 1)
			{(clogb2(max_feature_map_h-1)+1){mul_chn_conv_res_rd_pos_y != o_ft_map_h[clogb2(max_feature_map_h-1):0]}} & 
			(mul_chn_conv_res_rd_pos_y + 1);
	end
	
	/** 多通道卷积结果行缓存区MEM **/
	wire[out_buffer_n-1:0] line_buffer_mem_wen;
	wire[out_buffer_n-1:0] line_buffer_mem_ren;
	wire[clogb2(max_feature_map_w-1):0] line_buffer_mem_addr[0:out_buffer_n-1];
	
	genvar line_buffer_mem_i;
	generate
		for(line_buffer_mem_i = 0;line_buffer_mem_i < out_buffer_n;line_buffer_mem_i = line_buffer_mem_i + 1)
		begin
			assign line_buffer_mem_wen[line_buffer_mem_i] = 
				s_axis_mid_res_valid & mul_chn_conv_res_buf_fifo_full_n & mul_chn_conv_res_buf_fifo_wmask[line_buffer_mem_i];
			
			assign line_buffer_mem_ren[line_buffer_mem_i] = 
				(~(mul_chn_conv_res_buf_fifo_rptr[line_buffer_mem_i] & conv_mid_res_updating_vec[line_buffer_mem_i])) & 
				mul_chn_conv_res_buf_fifo_empty_n & mul_chn_conv_res_rd_s0_ready;
			
			assign line_buffer_mem_addr[line_buffer_mem_i] = line_buffer_mem_wen[line_buffer_mem_i] ? 
				mul_chn_conv_mid_res_wt_pos_x:mul_chn_conv_res_rd_pos_x;
			
			conv_out_line_buffer #(
				.ft_vld_width(ft_vld_width),
				.max_feature_map_w(max_feature_map_w),
				.simulation_delay(simulation_delay)
			)line_buffer_mem(
				.clk(clk),
				.rst_n(rst_n),
				
				.buffer_en(line_buffer_mem_wen[line_buffer_mem_i] | line_buffer_mem_ren[line_buffer_mem_i]),
				.buffer_wen(line_buffer_mem_wen[line_buffer_mem_i]),
				.buffer_addr(line_buffer_mem_addr[line_buffer_mem_i]),
				.buffer_w_first_grp(mul_chn_conv_mid_res_wt_at_first_batch),
				.buffer_din(mid_res_to_wt[line_buffer_mem_i]),
				.buffer_dout(mul_chn_conv_res_dout[line_buffer_mem_i]),
				
				.conv_mid_res_updating(conv_mid_res_updating_vec[line_buffer_mem_i])
			);
		end
	endgenerate
	
endmodule
