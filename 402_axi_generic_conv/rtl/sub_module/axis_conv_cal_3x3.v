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
本模块: n通道并行m核并行3x3卷积计算单元

描述:
通道X卷积结果:
    [(ROI x1y1) * (卷积核 x1y1)]
                |
				|-------------------> [前置结果 + (ROI x2y1) * (卷积核 x2y1)]
				                                        |
												        |-------------------> [前置结果 + (ROI x3y1) * (卷积核 x3y1)] -------------
	                                                                                                                              |
	[(ROI x1y2) * (卷积核 x1y2)]                                                                                                  |
                |                                                                                                                 |
				|-------------------> [前置结果 + (ROI x2y2) * (卷积核 x2y2)]                                                     |
				                                        |                                                                         V
												        |-------------------> [前置结果 + (ROI x3y2) * (卷积核 x3y2)] ---> [三输入加法器] --->
	                                                                                                                              ^
	[(ROI x1y3) * (卷积核 x1y3)]                                                                                                  |
                |                                                                                                                 |
				|-------------------> [前置结果 + (ROI x2y3) * (卷积核 x2y3)]                                                     |
				                                        |                                                                         |
												        |-------------------> [前置结果 + (ROI x3y3) * (卷积核 x3y3)] -------------

卷积核X通道累加中间结果:
	[通道1卷积结果] ---|
	                  [+]----
	[通道2卷积结果] ---|    |
	                       [+]---->
	[通道3卷积结果] ---|    |
	                  [+]----
	[通道4卷积结果] ---|

中间结果输出:
	[卷积核1通道累加中间结果]---->
	[卷积核2通道累加中间结果]---->
	[卷积核3通道累加中间结果]---->
	[卷积核4通道累加中间结果]---->

注意：
无

协议:
AXIS MASTER/SLAVE
FIFO READ
MEM READ

作者: 陈家耀
日期: 2024/12/26
********************************************************************/


module axis_conv_cal_3x3 #(
	parameter en_use_dsp_for_add_3 = "false", // 是否使用DSP来实现三输入加法器
	parameter integer mul_add_width = 16, // 乘加位宽(8 | 16)
	parameter integer quaz_acc = 10, // 量化精度(必须在范围[1, mul_add_width-1]内)
	parameter integer add_3_input_ext_int_width = 4, // 三输入加法器额外考虑的整数位数(必须<=(mul_add_width-quaz_acc))
	parameter integer add_3_input_ext_frac_width = 4, // 三输入加法器额外考虑的小数位数(必须<=quaz_acc)
	parameter integer in_feature_map_buffer_rd_prl_n = 4, // 读输入特征图缓存的并行个数(1 | 2 | 4 | 8 | 16)
	parameter integer kernal_prl_n = 4, // 多通道卷积核的并行个数(1 | 2 | 4 | 8 | 16)
	parameter integer max_feature_map_w = 512, // 最大的输入特征图宽度
	parameter integer max_feature_map_h = 512, // 最大的输入特征图高度
	parameter integer max_feature_map_chn_n = 512, // 最大的输入特征图通道数
	parameter integer max_kernal_n = 512, // 最大的卷积核个数
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 同步复位
	input wire rst_kernal_buf, // 复位卷积核缓存
	
	// 使能
	input wire en_conv_cal, // 是否使能卷积计算
	
	// 运行时参数
	input wire kernal_type, // 卷积核类型(1'b0 -> 1x1, 1'b1 -> 3x3)
	input wire[1:0] padding_en, // 外拓填充使能(仅当卷积核类型为3x3时可用, {左, 右})
	input wire[15:0] feature_map_h, // 输入特征图高度 - 1
	input wire[15:0] feature_map_chn_n, // 输入特征图通道数 - 1
	input wire[15:0] kernal_n, // 卷积核个数 - 1
	input wire[15:0] o_ft_map_w, // 输出特征图宽度 - 1
	input wire[15:0] o_ft_map_h, // 输出特征图高度 - 1
	input wire[2:0] horizontal_step, // 水平步长 - 1
	input wire step_type, // 步长类型(1'b0 -> 从第1个ROI开始, 1'b1 -> 舍弃第1个ROI)
	
	// 特征图输入(AXIS从机)
	// {缓存#(n-1)行#2, 缓存#(n-1)行#1, 缓存#(n-1)行#0, ..., 缓存#0行#2, 缓存#0行#1, 缓存#0行#0}
	input wire[mul_add_width*3*in_feature_map_buffer_rd_prl_n-1:0] s_axis_feature_map_data,
	input wire s_axis_feature_map_last, // 表示特征图行尾
	input wire s_axis_feature_map_valid,
	output wire s_axis_feature_map_ready,
	
	// 卷积核参数缓存控制(fifo读端口)
	output wire kernal_pars_buf_fifo_ren,
	input wire kernal_pars_buf_fifo_empty_n,
	
	// 卷积核参数缓存MEM读端口
	output wire kernal_pars_buf_mem_buf_ren_s0,
	output wire kernal_pars_buf_mem_buf_ren_s1,
	output wire[15:0] kernal_pars_buf_mem_buf_raddr, // 每个读地址对应1个单通道卷积核
	input wire[kernal_prl_n*mul_add_width*9-1:0] kernal_pars_buf_mem_buf_dout, // {核#(m-1), ..., 核#1, 核#0}
	
	// 卷积核通道累加中间结果输出(AXIS主机)
	// {核#(m-1)结果, ..., 核#1结果, 核#0结果}
	// 每个中间结果仅低(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)位有效
	output wire[mul_add_width*2*kernal_prl_n-1:0] m_axis_res_data,
	output wire m_axis_res_last, // 表示行尾
	output wire m_axis_res_user, // 表示当前行最后1组结果
	output wire m_axis_res_valid,
	input wire m_axis_res_ready
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
	
	/** 输出fifo **/
	// 输出fifo写端口
	wire[(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)*kernal_prl_n-1:0] out_fifo_din;
	wire out_fifo_din_last; // 表示行尾
	wire out_fifo_din_user; // 表示当前行最后1组结果
	wire out_fifo_wen;
	wire out_fifo_almost_full_n;
	// 输出fifo读端口
	wire[(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)*kernal_prl_n-1:0] out_fifo_dout;
	wire out_fifo_dout_last; // 表示行尾
	wire out_fifo_dout_user; // 表示当前行最后1组结果
	wire out_fifo_empty_n;
	wire out_fifo_ren;
	
	genvar m_axis_res_data_i;
	generate
		for(m_axis_res_data_i = 0;m_axis_res_data_i < kernal_prl_n;m_axis_res_data_i = m_axis_res_data_i + 1)
		begin
			if((add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width) == (mul_add_width*2))
				assign m_axis_res_data[mul_add_width*2*(m_axis_res_data_i+1)-1:mul_add_width*2*m_axis_res_data_i] = 
					out_fifo_dout[(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)*(m_axis_res_data_i+1)-1:
					(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)*m_axis_res_data_i];
			else
				assign m_axis_res_data[mul_add_width*2*(m_axis_res_data_i+1)-1:mul_add_width*2*m_axis_res_data_i] = {
					{(mul_add_width-add_3_input_ext_int_width-add_3_input_ext_frac_width)
						{out_fifo_dout[(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)*
							(m_axis_res_data_i+1)-1]}}, // 进行符号位拓展
					out_fifo_dout[(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)*(m_axis_res_data_i+1)-1:
					(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)*m_axis_res_data_i]
				};
		end
	endgenerate
	
	assign m_axis_res_last = out_fifo_dout_last;
	assign m_axis_res_user = out_fifo_dout_user;
	// 握手条件: out_fifo_empty_n & m_axis_res_ready
	assign m_axis_res_valid = out_fifo_empty_n;
	assign out_fifo_ren = m_axis_res_ready;
	
	ram_fifo_wrapper #(
		.fwft_mode("true"),
		.ram_type("bram"),
		.en_bram_reg("false"),
		.fifo_depth(512),
		.fifo_data_width((add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)*kernal_prl_n + 2),
		.full_assert_polarity("low"),
		.empty_assert_polarity("low"),
		.almost_full_assert_polarity("low"),
		.almost_empty_assert_polarity("no"),
		.en_data_cnt("false"),
		.almost_full_th(512 - 32),
		.almost_empty_th(),
		.simulation_delay(simulation_delay)
	)out_fifo(
		.clk(clk),
		.rst_n(rst_n),
		
		.fifo_wen(out_fifo_wen),
		.fifo_din({out_fifo_din, out_fifo_din_last, out_fifo_din_user}),
		.fifo_full(),
		.fifo_full_n(),
		.fifo_almost_full(),
		.fifo_almost_full_n(out_fifo_almost_full_n),
		
		.fifo_ren(out_fifo_ren),
		.fifo_dout({out_fifo_dout, out_fifo_dout_last, out_fifo_dout_user}),
		.fifo_empty(),
		.fifo_empty_n(out_fifo_empty_n),
		.fifo_almost_empty(),
		.fifo_almost_empty_n(),
		
		.data_cnt()
	);
	
	/** 卷积结果所处位置 **/
	wire[(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)*kernal_prl_n-1:0] mul_chn_conv_res; // 多通道卷积结果
	wire mul_chn_conv_res_at_last_col; // 多通道卷积结果处于行尾(标志)
	wire mul_chn_conv_res_at_last_chn_grp; // 多通道卷积结果处于最后1个通道组(标志)
	wire mul_chn_conv_res_vld; // 多通道卷积结果有效(指示)
	reg[clogb2(max_feature_map_chn_n/in_feature_map_buffer_rd_prl_n-1):0] mul_chn_conv_res_chn_grp_cnt; // 多通道卷积结果所处的通道组(计数器)
	
	assign out_fifo_din = mul_chn_conv_res;
	assign out_fifo_din_last = mul_chn_conv_res_at_last_col;
	assign out_fifo_din_user = mul_chn_conv_res_at_last_chn_grp;
	assign out_fifo_wen = mul_chn_conv_res_vld;
	
	assign mul_chn_conv_res_at_last_chn_grp = mul_chn_conv_res_chn_grp_cnt == 
		feature_map_chn_n[clogb2(max_feature_map_chn_n-1):clogb2(in_feature_map_buffer_rd_prl_n)];
	
	// 多通道卷积结果所处的通道组(计数器)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_res_chn_grp_cnt <= 0;
		else if(mul_chn_conv_res_vld & mul_chn_conv_res_at_last_col)
			mul_chn_conv_res_chn_grp_cnt <= # simulation_delay 
				// mul_chn_conv_res_at_last_chn_grp ? 0:(mul_chn_conv_res_chn_grp_cnt + 1)
				{(clogb2(max_feature_map_chn_n/in_feature_map_buffer_rd_prl_n-1)+1){~mul_chn_conv_res_at_last_chn_grp}} & 
				(mul_chn_conv_res_chn_grp_cnt + 1);
	end
	
	/** 特征列输入 **/
	// {行#2, 行#1, 行#0}
	wire[mul_add_width*3-1:0] s_axis_feature_col_data[0:in_feature_map_buffer_rd_prl_n-1];
	wire s_axis_feature_col_last; // 表示特征图行尾
	wire s_axis_feature_col_user; // 表示最后1组特征图
	// {核#(m-1)通道#(n-1), ..., 核#(m-1)通道#0, ..., 核#0通道#(n-1), ..., 核#0通道#0}
	wire[in_feature_map_buffer_rd_prl_n*kernal_prl_n-1:0] s_axis_feature_col_valid;
	wire[in_feature_map_buffer_rd_prl_n*kernal_prl_n-1:0] s_axis_feature_col_ready;
	// 特征组位置
	reg[clogb2(max_feature_map_chn_n/in_feature_map_buffer_rd_prl_n-1):0] ft_grp_ichn_id; // 输入通道编号
	wire ft_grp_at_last_ichn; // 特征组处于最后1个输入通道(标志)
	reg[clogb2(max_feature_map_h-1):0] ft_grp_yid; // 行编号
	wire ft_grp_at_last_row; // 特征组处于最后1行(标志)
	reg[clogb2(max_kernal_n/kernal_prl_n-1):0] ft_grp_ochn_id; // 输出通道编号
	wire ft_grp_at_last_ochn; // 特征组处于最后1个输出通道(标志)
	
	// 握手条件: s_axis_feature_map_valid & out_fifo_almost_full_n & en_conv_cal & (&s_axis_feature_col_ready)
	assign s_axis_feature_map_ready = out_fifo_almost_full_n & en_conv_cal & (&s_axis_feature_col_ready);
	
	genvar s_axis_feature_col_data_i;
	generate
		for(s_axis_feature_col_data_i = 0;s_axis_feature_col_data_i < in_feature_map_buffer_rd_prl_n;
			s_axis_feature_col_data_i = s_axis_feature_col_data_i + 1)
		begin
			assign s_axis_feature_col_data[s_axis_feature_col_data_i] = 
				s_axis_feature_map_data[(mul_add_width*3)*(s_axis_feature_col_data_i+1)-1:
					(mul_add_width*3)*s_axis_feature_col_data_i];
		end
	endgenerate
	
	assign s_axis_feature_col_last = s_axis_feature_map_last;
	assign s_axis_feature_col_user = ft_grp_at_last_ichn & ft_grp_at_last_row & ft_grp_at_last_ochn;
	
	genvar s_axis_feature_col_valid_i;
	generate
		for(s_axis_feature_col_valid_i = 0;s_axis_feature_col_valid_i < in_feature_map_buffer_rd_prl_n*kernal_prl_n;
			s_axis_feature_col_valid_i = s_axis_feature_col_valid_i + 1)
		begin
			// 握手条件: s_axis_feature_map_valid & out_fifo_almost_full_n & en_conv_cal & (&s_axis_feature_col_ready)
			if(in_feature_map_buffer_rd_prl_n*kernal_prl_n > 1)
				assign s_axis_feature_col_valid[s_axis_feature_col_valid_i] = 
					s_axis_feature_map_valid & 
					out_fifo_almost_full_n & en_conv_cal & 
						// 排除掉当前计算单元的ready
						(&(s_axis_feature_col_ready | 
							({{(in_feature_map_buffer_rd_prl_n*kernal_prl_n-1){1'b0}}, 1'b1} << s_axis_feature_col_valid_i)));
			else
				assign s_axis_feature_col_valid[s_axis_feature_col_valid_i] = s_axis_feature_map_valid & 
					out_fifo_almost_full_n & en_conv_cal;
		end
	endgenerate
	
	assign ft_grp_at_last_ichn = ft_grp_ichn_id == 
		feature_map_chn_n[clogb2(max_feature_map_chn_n-1):clogb2(in_feature_map_buffer_rd_prl_n)];
	assign ft_grp_at_last_row = ft_grp_yid == o_ft_map_h[clogb2(max_feature_map_h-1):0];
	assign ft_grp_at_last_ochn = ft_grp_ochn_id == kernal_n[clogb2(max_kernal_n-1):clogb2(kernal_prl_n)];
	
	// 特征组输入通道编号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			ft_grp_ichn_id <= 0;
		else if(s_axis_feature_map_valid & s_axis_feature_map_ready & s_axis_feature_map_last)
			ft_grp_ichn_id <= # simulation_delay 
				// ft_grp_at_last_ichn ? 0:(ft_grp_ichn_id + 1)
				{(clogb2(max_feature_map_chn_n/in_feature_map_buffer_rd_prl_n-1)+1){~ft_grp_at_last_ichn}} & 
				(ft_grp_ichn_id + 1);
	end
	// 特征组行编号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			ft_grp_yid <= 0;
		else if(s_axis_feature_map_valid & s_axis_feature_map_ready & s_axis_feature_map_last & ft_grp_at_last_ichn)
			ft_grp_yid <= # simulation_delay 
				// ft_grp_at_last_row ? 0:(ft_grp_yid + 1)
				{(clogb2(max_feature_map_h-1)+1){~ft_grp_at_last_row}} & (ft_grp_yid + 1);
	end
	// 特征组输出通道编号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			ft_grp_ochn_id <= 0;
		else if(s_axis_feature_map_valid & s_axis_feature_map_ready & s_axis_feature_map_last & ft_grp_at_last_ichn & ft_grp_at_last_row)
			ft_grp_ochn_id <= # simulation_delay 
				// ft_grp_at_last_ochn ? 0:(ft_grp_ochn_id + 1)
				{(clogb2(max_kernal_n/kernal_prl_n-1)+1){~ft_grp_at_last_ochn}} & (ft_grp_ochn_id + 1);
	end
	
	/**
	卷积核输入
	
	每个多通道卷积核重复(输入特征图高度 - 2 + 
		((卷积核类型为1x1 | 是否上填充) ? 1:0) + ((卷积核类型为1x1 | 是否下填充) ? 1:0))次 -> 
		       chn#0             chn#(通道并行数)             chn#(通道数-通道并行数)
		       chn#1            chn#(通道并行数+1)     ...   chn#(通道数-通道并行数+1)
		         :                       :                               :
	   chn#(通道并行数-1)      chn#(通道并行数*2-1)                chn#(通道数-1)
	**/
	// {x3y3, x2y3, x1y3, x3y2, x2y2, x1y2, x3y1, x2y1, x1y1}
	reg[clogb2(max_feature_map_chn_n-1):0] kernal_pars_chn_id; // 卷积核通道号
	wire kernal_pars_at_last_chn; // 卷积核抵达最后1个通道(标志)
	reg[clogb2(max_feature_map_h-1):0] kernal_pars_h_id; // 卷积核对应输出特征图y位置
	wire kernal_pars_at_last_row; // 卷积核对应输出特征图y位置抵达最后1行(标志)
	// 读卷积核参数流水线控制
	wire rd_kernal_pars_s0_valid;
	wire rd_kernal_pars_s0_ready;
	reg rd_kernal_pars_s1_valid;
	wire rd_kernal_pars_s1_ready;
	reg rd_kernal_pars_s2_valid;
	wire rd_kernal_pars_s2_ready;
	// 计算单元卷积核输入
	reg[in_feature_map_buffer_rd_prl_n-1:0] kernal_pars_chn_sel; // 卷积核对应计算单元通道选择
	wire[mul_add_width*9-1:0] s_axis_kernal_data[0:kernal_prl_n-1];
	wire[in_feature_map_buffer_rd_prl_n-1:0] s_axis_kernal_valid[0:kernal_prl_n-1];
	wire[in_feature_map_buffer_rd_prl_n-1:0] s_axis_kernal_ready[0:kernal_prl_n-1];
	wire[kernal_prl_n-1:0] kernal_ready_sel_by_chn;
	
	// 握手条件: kernal_pars_at_last_chn & kernal_pars_at_last_row & rd_kernal_pars_s0_valid & rd_kernal_pars_s0_ready
	assign kernal_pars_buf_fifo_ren = kernal_pars_at_last_chn & kernal_pars_at_last_row & rd_kernal_pars_s0_ready;
	
	assign kernal_pars_buf_mem_buf_ren_s0 = rd_kernal_pars_s0_valid & rd_kernal_pars_s0_ready;
	assign kernal_pars_buf_mem_buf_ren_s1 = rd_kernal_pars_s1_valid & rd_kernal_pars_s1_ready;
	assign kernal_pars_buf_mem_buf_raddr = {{(15-clogb2(max_feature_map_chn_n-1)){1'b0}}, kernal_pars_chn_id};
	
	assign kernal_pars_at_last_chn = kernal_pars_chn_id == 
		(feature_map_chn_n[clogb2(max_feature_map_chn_n-1):0] | (in_feature_map_buffer_rd_prl_n - 1));
	assign kernal_pars_at_last_row = kernal_pars_h_id == o_ft_map_h[clogb2(max_feature_map_h-1):0];
	
	// 握手条件: rd_kernal_pars_s0_valid & rd_kernal_pars_s0_ready
	assign rd_kernal_pars_s0_valid = kernal_pars_buf_fifo_empty_n;
	assign rd_kernal_pars_s0_ready = (~rd_kernal_pars_s1_valid) | rd_kernal_pars_s1_ready;
	assign rd_kernal_pars_s1_ready = (~rd_kernal_pars_s2_valid) | rd_kernal_pars_s2_ready;
	
	// 握手条件: en_conv_cal & rd_kernal_pars_s2_valid & (&kernal_ready_sel_by_chn)
	assign rd_kernal_pars_s2_ready = en_conv_cal & (&kernal_ready_sel_by_chn);
	
	genvar s_axis_kernal_data_i;
	generate
		for(s_axis_kernal_data_i = 0;s_axis_kernal_data_i < kernal_prl_n;s_axis_kernal_data_i = s_axis_kernal_data_i + 1)
		begin
			assign s_axis_kernal_data[s_axis_kernal_data_i] = 
				kernal_pars_buf_mem_buf_dout[(mul_add_width*9)*(s_axis_kernal_data_i+1)-1:(mul_add_width*9)*s_axis_kernal_data_i];
		end
	endgenerate
	
	genvar s_axis_kernal_valid_i;
	generate
		for(s_axis_kernal_valid_i = 0;s_axis_kernal_valid_i < kernal_prl_n;
			s_axis_kernal_valid_i = s_axis_kernal_valid_i + 1)
		begin
			assign kernal_ready_sel_by_chn[s_axis_kernal_valid_i] = 
				|(s_axis_kernal_ready[s_axis_kernal_valid_i] & kernal_pars_chn_sel);
			
			// 握手条件: en_conv_cal & rd_kernal_pars_s2_valid & kernal_pars_chn_sel[计算单元通道号] & 
			//     (&kernal_ready_sel_by_chn)
			if(kernal_prl_n > 1)
			begin
				assign s_axis_kernal_valid[s_axis_kernal_valid_i] = 
					{in_feature_map_buffer_rd_prl_n{en_conv_cal & rd_kernal_pars_s2_valid & 
					// 排除掉当前计算单元的ready
					(&(kernal_ready_sel_by_chn | ({{(kernal_prl_n-1){1'b0}}, 1'b1} << s_axis_kernal_valid_i)))}} & 
					kernal_pars_chn_sel;
			end
			else
			begin
				assign s_axis_kernal_valid[s_axis_kernal_valid_i] = 
					{in_feature_map_buffer_rd_prl_n{en_conv_cal & rd_kernal_pars_s2_valid}} & kernal_pars_chn_sel;
			end
		end
	endgenerate
	
	// 卷积核通道号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			kernal_pars_chn_id <= 0;
		else if(rd_kernal_pars_s0_valid & rd_kernal_pars_s0_ready)
			// kernal_pars_at_last_chn ? 0:(kernal_pars_chn_id + 1)
			kernal_pars_chn_id <= # simulation_delay {(clogb2(max_feature_map_chn_n-1)+1){~kernal_pars_at_last_chn}} & 
				(kernal_pars_chn_id + 1);
	end
	
	// 卷积核对应输出特征图y位置
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			kernal_pars_h_id <= 0;
		else if(rd_kernal_pars_s0_valid & rd_kernal_pars_s0_ready & kernal_pars_at_last_chn)
			// kernal_pars_at_last_row ? 0:(kernal_pars_h_id + 1)
			kernal_pars_h_id <= # simulation_delay {(clogb2(max_feature_map_h-1)+1){~kernal_pars_at_last_row}} & 
				(kernal_pars_h_id + 1);
	end
	
	// 读卷积核参数流水线各级valid信号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rd_kernal_pars_s1_valid <= 1'b0;
		else if(rd_kernal_pars_s0_ready)
			rd_kernal_pars_s1_valid <= # simulation_delay rd_kernal_pars_s0_valid;
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rd_kernal_pars_s2_valid <= 1'b0;
		else if(rd_kernal_pars_s1_ready)
			rd_kernal_pars_s2_valid <= # simulation_delay rd_kernal_pars_s1_valid;
	end
	
	// 卷积核对应计算单元通道选择
	generate
		if(in_feature_map_buffer_rd_prl_n == 1)
		begin
			always @(*)
				kernal_pars_chn_sel = 1'b1;
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					kernal_pars_chn_sel <= {{(in_feature_map_buffer_rd_prl_n-1){1'b0}}, 1'b1};
				else if(rd_kernal_pars_s2_valid & rd_kernal_pars_s2_ready)
					kernal_pars_chn_sel <= # simulation_delay {
						kernal_pars_chn_sel[in_feature_map_buffer_rd_prl_n-2:0], 
						kernal_pars_chn_sel[in_feature_map_buffer_rd_prl_n-1]};
			end
		end
	endgenerate
	
	/**
	AXIS单通道3x3卷积计算单元
	
	  核#0通道#0     核#0通道#1   ...   核#0通道#(n-1)   -> n输入加法
	  核#1通道#0     核#1通道#1   ...   核#1通道#(n-1)   -> n输入加法
	                      :
					      :
	核#(m-1)通道#0 核#(m-1)通道#1 ... 核#(m-1)通道#(n-1) -> n输入加法
	**/
	// 单通道卷积结果
	// 断言: 所有单通道卷积结果同时到达!
	wire[add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width-1:0] single_chn_conv_res[0:in_feature_map_buffer_rd_prl_n*kernal_prl_n-1];
	wire[(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)*in_feature_map_buffer_rd_prl_n-1:0] single_chn_conv_res_flattened[0:kernal_prl_n-1];
	wire[in_feature_map_buffer_rd_prl_n*kernal_prl_n-1:0] single_chn_conv_res_vld;
	wire[in_feature_map_buffer_rd_prl_n*kernal_prl_n-1:0] single_chn_conv_res_last;
	// 通道组求和结果
	// 断言: 所有求和结果同时到达!
	wire[add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width-1:0] chn_grp_conv_sum[0:kernal_prl_n-1];
	wire[kernal_prl_n-1:0] chn_grp_conv_sum_vld;
	wire[kernal_prl_n-1:0] chn_grp_conv_sum_last;
	
	genvar mul_chn_conv_res_i;
	generate
		for(mul_chn_conv_res_i = 0;mul_chn_conv_res_i < kernal_prl_n;mul_chn_conv_res_i = mul_chn_conv_res_i + 1)
		begin
			assign mul_chn_conv_res[(mul_chn_conv_res_i+1)*(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)-1:
				mul_chn_conv_res_i*(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)] = 
				chn_grp_conv_sum[mul_chn_conv_res_i];
		end
	endgenerate
	
	assign mul_chn_conv_res_at_last_col = chn_grp_conv_sum_last[0];
	assign mul_chn_conv_res_vld = chn_grp_conv_sum_vld[0];
	
	genvar single_chn_conv_unit_i;
	genvar single_chn_conv_unit_j;
	generate
		for(single_chn_conv_unit_i = 0;single_chn_conv_unit_i < kernal_prl_n;
			single_chn_conv_unit_i = single_chn_conv_unit_i + 1)
		begin
			for(single_chn_conv_unit_j = 0;single_chn_conv_unit_j < in_feature_map_buffer_rd_prl_n;
				single_chn_conv_unit_j = single_chn_conv_unit_j + 1)
			begin
				assign single_chn_conv_res_flattened[single_chn_conv_unit_i]
					[(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)*(single_chn_conv_unit_j+1)-1:
						(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)*single_chn_conv_unit_j] = 
					single_chn_conv_res[single_chn_conv_unit_i*in_feature_map_buffer_rd_prl_n+
						single_chn_conv_unit_j];
				
				axis_single_chn_conv_cal_3x3 #(
					.en_use_dsp_for_add_3(en_use_dsp_for_add_3),
					.mul_add_width(mul_add_width),
					.quaz_acc(quaz_acc),
					.add_3_input_ext_int_width(add_3_input_ext_int_width),
					.add_3_input_ext_frac_width(add_3_input_ext_frac_width),
					.max_feature_map_w(max_feature_map_w),
					.simulation_delay(simulation_delay)
				)axis_single_chn_conv_cal_3x3_u(
					.clk(clk),
					.rst_n(rst_n),
					
					.kernal_type(kernal_type),
					.padding_en(padding_en),
					.o_ft_map_w(o_ft_map_w),
					.horizontal_step(horizontal_step),
					.step_type(step_type),
					
					.rst_kernal_buf(rst_kernal_buf),
					
					.s_axis_ft_col_data(s_axis_feature_col_data[single_chn_conv_unit_j]),
					.s_axis_ft_col_last(s_axis_feature_col_last),
					.s_axis_ft_col_user(s_axis_feature_col_user),
					.s_axis_ft_col_valid(s_axis_feature_col_valid[single_chn_conv_unit_i*in_feature_map_buffer_rd_prl_n+
						single_chn_conv_unit_j]),
					.s_axis_ft_col_ready(s_axis_feature_col_ready[single_chn_conv_unit_i*in_feature_map_buffer_rd_prl_n+
						single_chn_conv_unit_j]),
					
					.s_axis_kernal_data(s_axis_kernal_data[single_chn_conv_unit_i]),
					.s_axis_kernal_valid(s_axis_kernal_valid[single_chn_conv_unit_i][single_chn_conv_unit_j]),
					.s_axis_kernal_ready(s_axis_kernal_ready[single_chn_conv_unit_i][single_chn_conv_unit_j]),
					
					// 位宽(mul_add_width*2)与位宽(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)不符, 取低位
					.m_axis_res_data(single_chn_conv_res[single_chn_conv_unit_i*in_feature_map_buffer_rd_prl_n+
						single_chn_conv_unit_j]),
					.m_axis_res_last(single_chn_conv_res_last[single_chn_conv_unit_i*in_feature_map_buffer_rd_prl_n+
						single_chn_conv_unit_j]),
					.m_axis_res_valid(single_chn_conv_res_vld[single_chn_conv_unit_i*in_feature_map_buffer_rd_prl_n+
						single_chn_conv_unit_j])
				);
			end
		end
	endgenerate
	
	genvar chn_grp_conv_sum_i;
	generate
		for(chn_grp_conv_sum_i = 0;chn_grp_conv_sum_i < kernal_prl_n;chn_grp_conv_sum_i = chn_grp_conv_sum_i + 1)
		begin
			if(in_feature_map_buffer_rd_prl_n > 1)
			begin
				add_tree_2_4_8_16 #(
					.add_input_n(in_feature_map_buffer_rd_prl_n),
					.add_width(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width),
					.simulation_delay(simulation_delay)
				)add_tree_2_4_8_16_u(
					.clk(clk),
					.rst_n(rst_n),
					
					.add_in(single_chn_conv_res_flattened[chn_grp_conv_sum_i]),
					.add_in_vld(single_chn_conv_res_vld[chn_grp_conv_sum_i*in_feature_map_buffer_rd_prl_n]),
					.add_in_last(single_chn_conv_res_last[chn_grp_conv_sum_i*in_feature_map_buffer_rd_prl_n]),
					
					.add_out(chn_grp_conv_sum[chn_grp_conv_sum_i]),
					.add_out_vld(chn_grp_conv_sum_vld[chn_grp_conv_sum_i]),
					.add_out_last(chn_grp_conv_sum_last[chn_grp_conv_sum_i])
				);
			end
			else
			begin
				assign chn_grp_conv_sum[chn_grp_conv_sum_i] = single_chn_conv_res_flattened[chn_grp_conv_sum_i];
				assign chn_grp_conv_sum_vld[chn_grp_conv_sum_i] = single_chn_conv_res_vld[chn_grp_conv_sum_i];
				assign chn_grp_conv_sum_last[chn_grp_conv_sum_i] = single_chn_conv_res_last[chn_grp_conv_sum_i];
			end
		end
	endgenerate
	
endmodule
