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
本模块: AXIS输入特征图缓存组

描述:
将输入特征图存入n个缓存区, 读缓存区时同时输出m行同一列的特征点

		 {[------行#0------]  --
          [------行#1------]   |
		  [------行#2------]}  |
                               |----->
		 {[------行#0------]   |
          [------行#1------]   |
		  [------行#2------]} --

		 {[------行#0------]
  ----->  [------行#1------]
		  [------行#2------]}
注意：
输入特征图缓存个数(in_feature_map_buffer_n)必须>=读输入特征图缓存的并行个数(in_feature_map_buffer_rd_prl_n)

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2024/10/21
********************************************************************/


module axis_in_feature_map_buffer_group #(
	parameter integer in_feature_map_buffer_n = 8, // 输入特征图缓存个数
	parameter integer in_feature_map_buffer_rd_prl_n = 4, // 读输入特征图缓存的并行个数
	parameter integer feature_data_width = 16, // 特征点位宽(8 | 16 | 32 | 64)
	parameter integer max_feature_map_w = 512, // 最大的输入特征图宽度
	parameter line_buffer_mem_type = "bram", // 行缓存MEM类型("bram" | "lutram" | "auto")
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 运行时参数
	input wire[15:0] feature_map_w, // 输入特征图宽度 - 1
	
	// 输入特征图(AXIS从机)
	input wire[63:0] s_axis_ft_data,
	input wire s_axis_ft_last, // 表示特征图行尾
	input wire[1:0] s_axis_ft_user, // {本行是否有效, 当前缓存区最后1行标志}
	input wire s_axis_ft_valid,
	output wire s_axis_ft_ready,
	
	// 缓存输出(AXIS主机)
	// {缓存#(n-1)行#2, 缓存#(n-1)行#1, 缓存#(n-1)行#0, ..., 缓存#0行#2, 缓存#0行#1, 缓存#0行#0}
	output wire[feature_data_width*3*in_feature_map_buffer_rd_prl_n-1:0] m_axis_buf_data,
	output wire m_axis_buf_last, // 表示特征图行尾
	output wire[in_feature_map_buffer_rd_prl_n*3-1:0] m_axis_buf_user, // {缓存行是否有效标志向量}
	output wire m_axis_buf_valid,
	input wire m_axis_buf_ready
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
	
	/** 缓存输出 **/
	// 读缓存区MEM流水线
	// stage0
	wire buffer_out_valid_stage0;
	wire buffer_out_ready_stage0;
	wire buffer_out_last_stage0; // 表示特征图行尾
	wire[in_feature_map_buffer_rd_prl_n*3-1:0] buffer_out_user_stage0; // {缓存行是否有效标志向量}
	// stage1
	reg buffer_out_valid_stage1;
	wire buffer_out_ready_stage1;
	reg buffer_out_last_stage1; // 表示特征图行尾
	reg[in_feature_map_buffer_rd_prl_n*3-1:0] buffer_out_user_stage1; // {缓存行是否有效标志向量}
	// stage2
	reg buffer_out_valid_stage2;
	wire buffer_out_ready_stage2;
	wire[feature_data_width*3*in_feature_map_buffer_rd_prl_n-1:0] buffer_out_data_stage2;
	reg buffer_out_last_stage2; // 表示特征图行尾
	reg[in_feature_map_buffer_rd_prl_n*3-1:0] buffer_out_user_stage2; // {缓存行是否有效标志向量}
	// stage3
	reg buffer_out_valid_stage3;
	wire buffer_out_ready_stage3;
	reg[feature_data_width*3*in_feature_map_buffer_rd_prl_n-1:0] buffer_out_data_stage3;
	reg buffer_out_last_stage3; // 表示特征图行尾
	reg[in_feature_map_buffer_rd_prl_n*3-1:0] buffer_out_user_stage3; // {缓存行是否有效标志向量}
	
	assign m_axis_buf_data = buffer_out_data_stage3;
	assign m_axis_buf_last = buffer_out_last_stage3;
	assign m_axis_buf_user = buffer_out_user_stage3;
	assign m_axis_buf_valid = buffer_out_valid_stage3;
	
	assign buffer_out_ready_stage0 = (~buffer_out_valid_stage1) | buffer_out_ready_stage1;
	assign buffer_out_ready_stage1 = (~buffer_out_valid_stage2) | buffer_out_ready_stage2;
	assign buffer_out_ready_stage2 = (~buffer_out_valid_stage3) | buffer_out_ready_stage3;
	assign buffer_out_ready_stage3 = m_axis_buf_ready;
	
	// 读缓存区MEM第1级流水线valid
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_out_valid_stage1 <= 1'b0;
		else if(buffer_out_ready_stage0)
			buffer_out_valid_stage1 <= # simulation_delay buffer_out_valid_stage0;
	end
	// 读缓存区MEM第1级流水线last和user
	always @(posedge clk)
	begin
		if(buffer_out_valid_stage0 & buffer_out_ready_stage0)
			{buffer_out_last_stage1, buffer_out_user_stage1} <= # simulation_delay 
				{buffer_out_last_stage0, buffer_out_user_stage0};
	end
	
	// 读缓存区MEM第2级流水线valid
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_out_valid_stage2 <= 1'b0;
		else if(buffer_out_ready_stage1)
			buffer_out_valid_stage2 <= # simulation_delay buffer_out_valid_stage1;
	end
	// 读缓存区MEM第2级流水线last和user
	always @(posedge clk)
	begin
		if(buffer_out_valid_stage1 & buffer_out_ready_stage1)
			{buffer_out_last_stage2, buffer_out_user_stage2} <= # simulation_delay 
				{buffer_out_last_stage1, buffer_out_user_stage1};
	end
	
	// 读缓存区MEM第3级流水线valid
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_out_valid_stage3 <= 1'b0;
		else if(buffer_out_ready_stage2)
			buffer_out_valid_stage3 <= # simulation_delay buffer_out_valid_stage2;
	end
	// 读缓存区MEM第3级流水线data, last和user
	always @(posedge clk)
	begin
		if(buffer_out_valid_stage2 & buffer_out_ready_stage2)
			{buffer_out_data_stage3, buffer_out_last_stage3, buffer_out_user_stage3} <= # simulation_delay 
				{buffer_out_data_stage2, buffer_out_last_stage2, buffer_out_user_stage2};
	end
	
	/** 缓存区存储计数 **/
	wire buffer_group_wen; // 缓存组写使能
	wire buffer_group_ren; // 缓存组读使能
	reg[clogb2(in_feature_map_buffer_n):0] buffer_group_n; // 缓存组存储个数
	wire[clogb2(in_feature_map_buffer_n):0] buffer_group_n_incr; // 缓存组存储个数增量
	wire[clogb2(in_feature_map_buffer_n):0] buffer_group_n_nxt; // 新的缓存组存储个数
	reg buffer_group_full_n; // 缓存组满标志
	reg buffer_group_empty_n; // 缓存组空标志
	
	assign buffer_group_n_incr = 
		// -in_feature_map_buffer_rd_prl_n
		({buffer_group_wen & buffer_group_full_n, 
			buffer_group_ren & buffer_group_empty_n} == 2'b01) ? ((~in_feature_map_buffer_rd_prl_n) + 1):
		// -in_feature_map_buffer_rd_prl_n + 1
		({buffer_group_wen & buffer_group_full_n, 
			buffer_group_ren & buffer_group_empty_n} == 2'b11) ? ((~in_feature_map_buffer_rd_prl_n) + 2):
																 1;
	assign buffer_group_n_nxt = buffer_group_n + buffer_group_n_incr;
	
	// 缓存组存储个数
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_group_n <= 0;
		else if((buffer_group_wen & buffer_group_full_n) | (buffer_group_ren & buffer_group_empty_n))
			buffer_group_n <= # simulation_delay buffer_group_n_nxt;
	end
	
	// 缓存组满标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_group_full_n <= 1'b1;
		else if((buffer_group_wen & buffer_group_full_n) | (buffer_group_ren & buffer_group_empty_n))
			buffer_group_full_n <= # simulation_delay buffer_group_n_nxt != in_feature_map_buffer_n;
	end
	// 缓存组空标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_group_empty_n <= 1'b0;
		else if((buffer_group_wen & buffer_group_full_n) | (buffer_group_ren & buffer_group_empty_n))
			buffer_group_empty_n <= # simulation_delay buffer_group_n_nxt >= in_feature_map_buffer_rd_prl_n;
	end
	
	/** 缓存区写端口 **/
	reg[in_feature_map_buffer_n-1:0] buffer_group_wptr; // 缓存组写指针
	reg[2:0] buffer_row_wptr; // 缓存行写指针
	reg[1:0] buffer_row_written; // 缓存行已写标志向量({行#1已写, 行#0已写})
	
	// 握手条件: s_axis_ft_valid & buffer_group_full_n
	assign s_axis_ft_ready = buffer_group_full_n;
	
	// 握手条件: s_axis_ft_valid & s_axis_ft_user[0] & s_axis_ft_last & buffer_group_full_n
	assign buffer_group_wen = s_axis_ft_valid & s_axis_ft_user[0] & s_axis_ft_last;
	
	// 缓存组写指针
	generate
		if(in_feature_map_buffer_n == 1)
		begin
			always @(*)
				buffer_group_wptr = 1'b1;
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					buffer_group_wptr <= {{(in_feature_map_buffer_n-1){1'b0}}, 1'b1};
				else if(buffer_group_wen & buffer_group_full_n)
					buffer_group_wptr <= # simulation_delay {buffer_group_wptr[in_feature_map_buffer_n-2:0], 
						buffer_group_wptr[in_feature_map_buffer_n-1]};
			end
		end
	endgenerate
	
	// 缓存行写指针
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_row_wptr <= 3'b001;
		else if(s_axis_ft_valid & s_axis_ft_ready & s_axis_ft_last)
			// s_axis_ft_user[0] ? 3'b001:{buffer_row_wptr[1:0], buffer_row_wptr[2]}
			buffer_row_wptr <= # simulation_delay {{2{~s_axis_ft_user[0]}} & buffer_row_wptr[1:0], 
				s_axis_ft_user[0] | buffer_row_wptr[2]};
	end
	
	// 缓存行已写标志向量
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_row_written <= 2'b00;
		else if(s_axis_ft_valid & s_axis_ft_ready & s_axis_ft_last)
			// s_axis_ft_user[0] ? 2'b00:(buffer_row_written | buffer_row_wptr[1:0])
			buffer_row_written <= # simulation_delay {2{~s_axis_ft_user[0]}} & (buffer_row_written | buffer_row_wptr[1:0]);
	end
	
	/** 缓存区读端口 **/
	reg[clogb2(max_feature_map_w-1):0] buffer_rd_col_id; // 缓存区读列号
	wire buffer_rd_last_col; // 当前读缓存区最后1列(标志)
	reg[clogb2(in_feature_map_buffer_n-1):0] buffer_rd_sel; // 缓存区读片选
	reg[clogb2(in_feature_map_buffer_n-1):0] buffer_rd_sel_d; // 延迟1clk的缓存区读片选
	reg[clogb2(in_feature_map_buffer_n-1):0] buffer_rd_sel_d2; // 延迟2clk的缓存区读片选
	wire[clogb2(in_feature_map_buffer_n-1):0] buffer_rd_sel_incr; // 缓存区读片选增量
	reg[in_feature_map_buffer_n-1:0] buffer_group_rptr; // 缓存组读指针
	reg[in_feature_map_buffer_n-1:0] buffer_group_rptr_d; // 延迟1clk的缓存组读指针
	
	// 握手条件: buffer_group_empty_n & buffer_out_ready_stage0
	assign buffer_out_valid_stage0 = buffer_group_empty_n;
	assign buffer_out_last_stage0 = buffer_rd_last_col;
	
	// 握手条件: buffer_group_empty_n & buffer_out_ready_stage0 & buffer_rd_last_col
	assign buffer_group_ren = buffer_out_ready_stage0 & buffer_rd_last_col;
	
	assign buffer_rd_last_col = buffer_rd_col_id == feature_map_w[clogb2(max_feature_map_w-1):0];
	assign buffer_rd_sel_incr = (buffer_rd_sel >= (in_feature_map_buffer_n - in_feature_map_buffer_rd_prl_n)) ? 
		// in_feature_map_buffer_rd_prl_n - in_feature_map_buffer_n
		((~(in_feature_map_buffer_n - in_feature_map_buffer_rd_prl_n)) + 1):
		in_feature_map_buffer_rd_prl_n;
	
	// 缓存区读列号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_rd_col_id <= 0;
		else if(buffer_out_valid_stage0 & buffer_out_ready_stage0)
			// buffer_rd_last_col ? 0:(buffer_rd_col_id + 1)
			buffer_rd_col_id <= # simulation_delay 
				{(clogb2(max_feature_map_w-1)+1){~buffer_rd_last_col}} & (buffer_rd_col_id + 1);
	end
	
	// 缓存区读片选
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_rd_sel <= 0;
		else if(buffer_group_ren & buffer_group_empty_n)
			buffer_rd_sel <= # simulation_delay buffer_rd_sel + buffer_rd_sel_incr;
	end
	// 延迟1clk的缓存区读片选
	always @(posedge clk)
	begin
		if(buffer_out_valid_stage0 & buffer_out_ready_stage0)
			buffer_rd_sel_d <= # simulation_delay buffer_rd_sel;
	end
	// 延迟2clk的缓存区读片选
	always @(posedge clk)
	begin
		if(buffer_out_valid_stage1 & buffer_out_ready_stage1)
			buffer_rd_sel_d2 <= # simulation_delay buffer_rd_sel_d;
	end
	
	// 缓存组读指针
	generate
		if(in_feature_map_buffer_n == in_feature_map_buffer_rd_prl_n)
		begin
			always @(*)
				buffer_group_rptr = {in_feature_map_buffer_n{1'b1}};
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					buffer_group_rptr <= {{(in_feature_map_buffer_n-in_feature_map_buffer_rd_prl_n){1'b0}}, 
						{in_feature_map_buffer_rd_prl_n{1'b1}}};
				else if(buffer_group_ren & buffer_group_empty_n)
					// 循环左移in_feature_map_buffer_rd_prl_n位
					buffer_group_rptr <= # simulation_delay 
						(buffer_group_rptr << in_feature_map_buffer_rd_prl_n) | 
						(buffer_group_rptr >> (in_feature_map_buffer_n-in_feature_map_buffer_rd_prl_n));
			end
		end
	endgenerate
	
	// 延迟1clk的缓存组读指针
	always @(posedge clk)
	begin
		if(buffer_out_valid_stage0 & buffer_out_ready_stage0)
			buffer_group_rptr_d <= # simulation_delay buffer_group_rptr;
	end
	
	/** 缓存区信息fifo **/
	reg[2:0] buffer_msg_fifo[0:in_feature_map_buffer_n-1]; // 缓存区信息fifo寄存器区({行#2是否有效, 行#1是否有效, 行#0是否有效})
	wire[in_feature_map_buffer_n*3-1:0] buffer_row_vld_flattened; // 展平的缓存行是否有效标志
	wire[in_feature_map_buffer_rd_prl_n*3-1:0] buffer_row_vld_vec; // 缓存行是否有效标志向量
	
	assign buffer_out_user_stage0 = buffer_row_vld_vec;
	
	// 缓存区是否有效标志向量
	// 循环右移buffer_rd_sel*3位, 仅保留in_feature_map_buffer_n种情况
	assign buffer_row_vld_vec = (buffer_rd_sel >= in_feature_map_buffer_n) ? 
		{(in_feature_map_buffer_rd_prl_n*3){1'bx}}: // not care!
		((buffer_row_vld_flattened >> (buffer_rd_sel*3)) | 
			(buffer_row_vld_flattened << ((in_feature_map_buffer_n - buffer_rd_sel)*3)));
	
	genvar buffer_msg_fifo_i;
	generate
		for(buffer_msg_fifo_i = 0;buffer_msg_fifo_i < in_feature_map_buffer_n;buffer_msg_fifo_i = buffer_msg_fifo_i + 1)
		begin
			// 展平的缓存行是否有效标志
			assign buffer_row_vld_flattened[(buffer_msg_fifo_i+1)*3-1:buffer_msg_fifo_i*3] = 
				buffer_msg_fifo[buffer_msg_fifo_i];
			
			// 缓存区信息fifo数据项
			// 行#0是否有效
			always @(posedge clk)
			begin
				if(s_axis_ft_valid & s_axis_ft_ready & s_axis_ft_last & 
					buffer_group_wptr[buffer_msg_fifo_i] & buffer_row_wptr[0])
					buffer_msg_fifo[buffer_msg_fifo_i][0] <= # simulation_delay s_axis_ft_user[1];
			end
			// 行#1是否有效
			always @(posedge clk)
			begin
				if(s_axis_ft_valid & s_axis_ft_ready & s_axis_ft_last & 
					buffer_group_wptr[buffer_msg_fifo_i] & 
					// 如果未写完行#0就结束写当前缓存区, 将行#1设为无效
					(buffer_row_wptr[1] | (s_axis_ft_user[0] & (~buffer_row_written[0]))))
					buffer_msg_fifo[buffer_msg_fifo_i][1] <= # simulation_delay buffer_row_wptr[1] & s_axis_ft_user[1];
			end
			// 行#2是否有效
			always @(posedge clk)
			begin
				if(s_axis_ft_valid & s_axis_ft_ready & s_axis_ft_last & 
					buffer_group_wptr[buffer_msg_fifo_i] & 
					// 如果未写完行#1就结束写当前缓存区, 将行#2设为无效
					(buffer_row_wptr[2] | (s_axis_ft_user[0] & (~buffer_row_written[1]))))
					buffer_msg_fifo[buffer_msg_fifo_i][2] <= # simulation_delay buffer_row_wptr[2] & s_axis_ft_user[1];
			end
		end
	endgenerate
	
	/** 输入特征图缓存区MEM **/
	// MEM写端口
	wire[2:0] buffer_mem_wen[0:in_feature_map_buffer_n-1];
	reg[clogb2(max_feature_map_w*feature_data_width/64-1):0] buffer_mem_waddr; // 每个写地址对应64位数据
	wire[63:0] buffer_mem_din; // 64位数据
	wire[64/feature_data_width-1:0] buffer_mem_din_last; // 行尾标志
	// MEM读端口
	wire buffer_mem_ren_s0[0:in_feature_map_buffer_n-1];
	wire buffer_mem_ren_s1[0:in_feature_map_buffer_n-1];
	wire[clogb2(max_feature_map_w-1):0] buffer_mem_raddr; // 每个读地址对应1个特征点
	wire[feature_data_width-1:0] buffer_mem_dout_r0[0:in_feature_map_buffer_n-1]; // 行#0特征点
	wire[feature_data_width-1:0] buffer_mem_dout_r1[0:in_feature_map_buffer_n-1]; // 行#1特征点
	wire[feature_data_width-1:0] buffer_mem_dout_r2[0:in_feature_map_buffer_n-1]; // 行#2特征点
	wire[feature_data_width*3*in_feature_map_buffer_n-1:0] buffer_mem_dout_flattened; // 展平的读数据
	// 位于读缓存区MEM第2级流水线的读数据掩码
	wire[feature_data_width*3*in_feature_map_buffer_rd_prl_n-1:0] buffer_out_data_mask_stage2;
	
	// 展平的读数据
	genvar buffer_mem_dout_flattened_i;
	generate
		for(buffer_mem_dout_flattened_i = 0;buffer_mem_dout_flattened_i < in_feature_map_buffer_n;
			buffer_mem_dout_flattened_i = buffer_mem_dout_flattened_i + 1)
		begin
			assign buffer_mem_dout_flattened[(buffer_mem_dout_flattened_i+1)*feature_data_width*3-1:
				buffer_mem_dout_flattened_i*feature_data_width*3] = {
					buffer_mem_dout_r2[buffer_mem_dout_flattened_i],
					buffer_mem_dout_r1[buffer_mem_dout_flattened_i],
					buffer_mem_dout_r0[buffer_mem_dout_flattened_i]
				};
		end
	endgenerate
	// 读缓存区MEM第2级流水线data
	// 循环右移(buffer_rd_sel_d2 * feature_data_width * 3)位, 仅保留in_feature_map_buffer_n种情况
	assign buffer_out_data_stage2 = ((buffer_rd_sel_d2 >= in_feature_map_buffer_n) ? 
		{(feature_data_width*3*in_feature_map_buffer_rd_prl_n){1'bx}}: // not care!
		((buffer_mem_dout_flattened >> (buffer_rd_sel_d2 * feature_data_width * 3)) | 
			(buffer_mem_dout_flattened << ((in_feature_map_buffer_n - buffer_rd_sel_d2) * feature_data_width * 3)))) & 
		buffer_out_data_mask_stage2;
	
	// 位于读缓存区MEM第2级流水线的读数据掩码
	genvar buffer_out_data_mask_stage2_i;
	generate
		for(buffer_out_data_mask_stage2_i = 0;buffer_out_data_mask_stage2_i < in_feature_map_buffer_rd_prl_n*3;
			buffer_out_data_mask_stage2_i = buffer_out_data_mask_stage2_i + 1)
		begin
			assign buffer_out_data_mask_stage2[(buffer_out_data_mask_stage2_i+1)*feature_data_width-1:
				buffer_out_data_mask_stage2_i*feature_data_width] = 
					{(feature_data_width){buffer_out_user_stage2[buffer_out_data_mask_stage2_i]}};
		end
	endgenerate
	
	// MEM写使能
	genvar buffer_mem_wen_i;
	generate
		for(buffer_mem_wen_i = 0;buffer_mem_wen_i < in_feature_map_buffer_n;buffer_mem_wen_i = buffer_mem_wen_i + 1)
		begin
			assign buffer_mem_wen[buffer_mem_wen_i] = 
				{3{buffer_group_wptr[buffer_mem_wen_i] & s_axis_ft_valid & s_axis_ft_ready}} & buffer_row_wptr;
		end
	endgenerate
	
	// MEM写数据
	assign buffer_mem_din = s_axis_ft_data;
	assign buffer_mem_din_last = {(64/feature_data_width){1'bx}}; // not care!
	
	// MEM读使能
	genvar buffer_mem_ren_i;
	generate
		for(buffer_mem_ren_i = 0;buffer_mem_ren_i < in_feature_map_buffer_n;buffer_mem_ren_i = buffer_mem_ren_i + 1)
		begin
			assign buffer_mem_ren_s0[buffer_mem_ren_i] = 
				buffer_out_valid_stage0 & buffer_out_ready_stage0 & buffer_group_rptr[buffer_mem_ren_i];
			assign buffer_mem_ren_s1[buffer_mem_ren_i] = 
				buffer_out_valid_stage1 & buffer_out_ready_stage1 & buffer_group_rptr_d[buffer_mem_ren_i];
		end
	endgenerate
	
	// MEM读地址
	assign buffer_mem_raddr = buffer_rd_col_id;
	
	// MEM写地址
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_mem_waddr <= 0;
		else if(s_axis_ft_valid & s_axis_ft_ready)
			// s_axis_ft_last ? 0:(buffer_mem_waddr + 1)
			buffer_mem_waddr <= # simulation_delay {(clogb2(max_feature_map_w*feature_data_width/64-1)+1){~s_axis_ft_last}} & 
				(buffer_mem_waddr + 1);
	end
	
	// 缓存MEM
	genvar buffer_mem_i;
	generate
		for(buffer_mem_i = 0;buffer_mem_i < in_feature_map_buffer_n;buffer_mem_i = buffer_mem_i + 1)
		begin
			conv_in_feature_map_buffer #(
				.feature_data_width(feature_data_width),
				.max_feature_map_w(max_feature_map_w),
				.line_buffer_mem_type(line_buffer_mem_type),
				.simulation_delay(simulation_delay)
			)conv_in_feature_map_buffer_u(
				.clk(clk),
				
				.buffer_wen(buffer_mem_wen[buffer_mem_i]),
				.buffer_waddr(buffer_mem_waddr),
				.buffer_din(buffer_mem_din),
				.buffer_din_last(buffer_mem_din_last),
				
				.buffer_ren_s0(buffer_mem_ren_s0[buffer_mem_i]),
				.buffer_ren_s1(buffer_mem_ren_s1[buffer_mem_i]),
				.buffer_raddr(buffer_mem_raddr),
				.buffer_dout_r0(buffer_mem_dout_r0[buffer_mem_i]),
				.buffer_dout_r1(buffer_mem_dout_r1[buffer_mem_i]),
				.buffer_dout_r2(buffer_mem_dout_r2[buffer_mem_i]),
				.buffer_dout_last_r0(),
				.buffer_dout_last_r1(),
				.buffer_dout_last_r2()
			);
		end
	endgenerate
	
endmodule
