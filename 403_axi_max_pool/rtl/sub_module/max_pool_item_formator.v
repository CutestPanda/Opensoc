`timescale 1ns / 1ps
/********************************************************************
本模块: 最大池化输出特征项整理单元

描述:
根据输出特征组的子项使能掩码, 将有效子项对齐到特征组低位

特征组: 2 3 1 0 4  -->  X X 3 1 0
掩码:   0 1 1 1 0  -->  0 0 1 1 1

注意：
无

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2024/10/12
********************************************************************/


module max_pool_item_formator #(
    parameter integer feature_n_per_clk = 4, // 每个clk输入的特征点数量(2 | 4 | 8 | 16 | ...)
	parameter integer feature_data_width = 8, // 特征点位宽(必须能被8整除, 且>0)
	parameter en_out_reg_slice = "true", // 是否使用输出寄存器片
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 运行时参数
	input wire step_type, // 步长类型(1'b0 -> 步长为1, 1'b1 -> 步长为2)
	
	// 整理单元输入
	input wire[(feature_n_per_clk+1)*feature_data_width-1:0] s_axis_data,
	input wire[2:0] s_axis_user, // {当前处于最后1个通道, 当前处于最后1行, 当前处于最后1列}
	input wire[(feature_n_per_clk+1)*feature_data_width/8-1:0] s_axis_keep,
	input wire s_axis_last, // 指示最后1个特征组
	input wire s_axis_valid,
	output wire s_axis_ready,
	
	// 整理单元输出
	output wire[(feature_n_per_clk+1)*feature_data_width-1:0] m_axis_data,
	output wire[2:0] m_axis_user, // {当前处于最后1个通道, 当前处于最后1行, 当前处于最后1列}
	output wire[(feature_n_per_clk+1)*feature_data_width/8-1:0] m_axis_keep,
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
	localparam integer stream_data_width = (feature_n_per_clk+1)*feature_data_width; // 像素流位宽
	
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
	
	/** 输入特征组 **/
	wire[feature_data_width-1:0] feature_data[feature_n_per_clk:0]; // 特征组数据
	wire[feature_n_per_clk:0] feature_item_keep; // 特征项使能掩码
	
	genvar feature_item_i;
	generate
		for(feature_item_i = 0;feature_item_i < feature_n_per_clk + 1;feature_item_i = feature_item_i + 1)
		begin
			assign feature_data[feature_item_i] = s_axis_data[(feature_item_i + 1) * feature_data_width - 1:
				feature_item_i * feature_data_width];
			assign feature_item_keep[feature_item_i] = s_axis_keep[feature_item_i * feature_data_width / 8];
		end
	endgenerate
	
	/** 整理特征项 **/
	// 步长为1时的特征组数据和子项使能掩码
	wire[feature_data_width-1:0] feature_data_1step[feature_n_per_clk:0]; // 特征组数据
	wire[feature_n_per_clk:0] feature_item_keep_1step; // 特征项使能掩码
	// 步长为2时的特征组数据和子项使能掩码
	wire[feature_data_width-1:0] feature_data_2step[feature_n_per_clk:0]; // 特征组数据
	wire[feature_n_per_clk:0] feature_item_keep_2step; // 特征项使能掩码
	// 整理后的特征组数据和子项使能掩码
	wire[feature_data_width-1:0] feature_data_reorg[feature_n_per_clk:0]; // 特征组数据
	wire[feature_n_per_clk:0] feature_item_keep_reorg; // 特征项使能掩码
	
	genvar feature_item_1step_i;
	generate
		for(feature_item_1step_i = 0;feature_item_1step_i < feature_n_per_clk;
			feature_item_1step_i = feature_item_1step_i + 1)
		begin
			assign feature_data_1step[feature_item_1step_i] = feature_item_keep[0] ? 
				feature_data[feature_item_1step_i]:feature_data[feature_item_1step_i + 1];
			assign feature_item_keep_1step[feature_item_1step_i] = feature_item_keep[0] ? 
				feature_item_keep[feature_item_1step_i]:feature_item_keep[feature_item_1step_i + 1];
		end
	endgenerate
	
	assign feature_data_1step[feature_n_per_clk] = feature_data[feature_n_per_clk];
	// feature_item_keep[0] ? feature_item_keep[feature_n_per_clk]:1'b0
	assign feature_item_keep_1step[feature_n_per_clk] = feature_item_keep[0] & feature_item_keep[feature_n_per_clk];
	
	genvar feature_item_2step_i;
	generate
		for(feature_item_2step_i = 0;feature_item_2step_i < feature_n_per_clk + 1;
			feature_item_2step_i = feature_item_2step_i + 1)
		begin
			if(feature_item_2step_i < feature_n_per_clk / 2)
			begin
				assign feature_data_2step[feature_item_2step_i] = feature_data[feature_item_2step_i * 2 + 1];
				assign feature_item_keep_2step[feature_item_2step_i] = feature_item_keep[feature_item_2step_i * 2 + 1];
			end
			else
			begin
				assign feature_data_2step[feature_item_2step_i] = {feature_data_width{1'bx}};
				assign feature_item_keep_2step[feature_item_2step_i] = 1'b0;
			end
		end
	endgenerate
	
	genvar feature_item_reorg_i;
	generate
		for(feature_item_reorg_i = 0;feature_item_reorg_i < feature_n_per_clk + 1;
			feature_item_reorg_i = feature_item_reorg_i + 1)
		begin
			assign feature_data_reorg[feature_item_reorg_i] = 
				step_type ? feature_data_2step[feature_item_reorg_i]:feature_data_1step[feature_item_reorg_i];
			assign feature_item_keep_reorg[feature_item_reorg_i] = 
				step_type ? feature_item_keep_2step[feature_item_reorg_i]:feature_item_keep_1step[feature_item_reorg_i];
		end
	endgenerate
	
	/** 输出特征组 **/
	assign s_axis_reg_slice_user = s_axis_user;
	assign s_axis_reg_slice_last = s_axis_last;
	assign s_axis_reg_slice_valid = s_axis_valid;
	assign s_axis_ready = s_axis_reg_slice_ready;
	
	genvar feature_item_keep_reorg_i;
	generate
		for(feature_item_keep_reorg_i = 0;feature_item_keep_reorg_i < feature_n_per_clk + 1;
			feature_item_keep_reorg_i = feature_item_keep_reorg_i + 1)
		begin
			assign s_axis_reg_slice_keep[(feature_item_keep_reorg_i+1)*(feature_data_width/8)-1:
				feature_item_keep_reorg_i*(feature_data_width/8)] = 
				{(feature_data_width/8){feature_item_keep_reorg[feature_item_keep_reorg_i]}};
		end
	endgenerate
	
	genvar feature_data_reorg_i;
	generate
		for(feature_data_reorg_i = 0;feature_data_reorg_i < feature_n_per_clk + 1;
			feature_data_reorg_i = feature_data_reorg_i + 1)
		begin
			assign s_axis_reg_slice_data[(feature_data_reorg_i+1)*feature_data_width-1:
				feature_data_reorg_i*feature_data_width] = 
				feature_data_reorg[feature_data_reorg_i];
		end
	endgenerate
    
endmodule
