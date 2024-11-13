`timescale 1ns / 1ps
/********************************************************************
本模块: AXIS单通道3x3卷积计算单元

描述:
全流水(9级流水线)的单通道3x3卷积计算数据通路
包含了卷积核粘贴控制逻辑, 在本行最后1个ROI后切换下1个卷积核

注意：
无

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2024/10/29
********************************************************************/


module axis_single_chn_conv_cal_3x3 #(
	parameter integer mul_add_width = 16, // 乘加位宽(8 | 16)
	parameter integer quaz_acc = 10, // 量化精度(必须在范围[1, mul_add_width-1]内)
	parameter integer add_3_input_ext_int_width = 4, // 三输入加法器额外考虑的整数位数(必须<=(mul_add_width-quaz_acc))
	parameter integer add_3_input_ext_frac_width = 4, // 三输入加法器额外考虑的小数位数(必须<=quaz_acc)
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 运行时参数
	input wire kernal_type, // 卷积核类型(1'b0 -> 1x1, 1'b1 -> 3x3)
	input wire[1:0] padding_en, // 外拓填充使能(仅当卷积核类型为3x3时可用, {左, 右})
	
	// 同步复位
	input wire rst_kernal_buf, // 复位卷积核缓存
	
	// 特征图列输入(AXIS从机)
	// {行#2, 行#1, 行#0}
	input wire[mul_add_width*3-1:0] s_axis_ft_col_data,
	input wire s_axis_ft_col_last, // 表示特征图行尾
	input wire s_axis_ft_col_user, // 表示最后1组特征图
	input wire s_axis_ft_col_valid,
	output wire s_axis_ft_col_ready,
	
	// 待粘贴的卷积核输入(AXIS从机)
	// {x3y3, x2y3, x1y3, x3y2, x2y2, x1y2, x3y1, x2y1, x1y1}
	input wire[mul_add_width*9-1:0] s_axis_kernal_data,
	input wire s_axis_kernal_valid,
	output wire s_axis_kernal_ready,
	
	// 卷积结果输出
	// 卷积结果的小数点在原先的高add_3_input_ext_frac_width位处
	// 仅低(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)位有效
	output wire[mul_add_width*2-1:0] m_axis_res_data,
	output wire m_axis_res_last, // 表示特征图行尾
	output wire m_axis_res_valid
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
	
	/** 特征图ROI生成 **/
	// 特征图ROI输出(AXIS主机)
	// {x3y3, x2y3, x1y3, x3y2, x2y2, x1y2, x3y1, x2y1, x1y1}
	wire[mul_add_width*9-1:0] m_axis_ft_roi_data;
	wire m_axis_ft_roi_last; // 指示本行最后1个ROI
	wire m_axis_ft_roi_user; // 表示最后1组特征图
	wire m_axis_ft_roi_valid;
	wire m_axis_ft_roi_ready;
	// 特征图ROI生成
	wire[mul_add_width-1:0] ft_roi[0:8]; // 特征图ROI
	wire[mul_add_width-1:0] ft_col_now[0:2]; // 当前特征列
	reg[mul_add_width-1:0] ft_col_remaining_buf0[0:2]; // 特征列剩余缓存#0
	reg[mul_add_width-1:0] ft_col_remaining_buf1[0:2]; // 特征列剩余缓存#1
	reg[3:0] ft_col_pos; // 特征图列位置(4'b0001 -> 第1列, 4'b0010 -> 第2列, 4'b0100 -> 第3列及以后, 4'b1000 -> 右填充)
	wire need_left_padding; // 需要左填充(标志)
	wire need_right_padding; // 需要右填充(标志)
	reg last_ft_map_grp_flag; // 锁存的最后1组特征图(标志)
	
	/*
	握手条件: 
		(ft_col_pos[0] & s_axis_ft_col_valid) | 
		(ft_col_pos[1] & s_axis_ft_col_valid & ((~need_left_padding) | m_axis_ft_roi_ready)) | 
		(ft_col_pos[2] & s_axis_ft_col_valid & m_axis_ft_roi_ready)
	*/
	assign s_axis_ft_col_ready = 
		ft_col_pos[0] | 
		(ft_col_pos[1] & ((~need_left_padding) | m_axis_ft_roi_ready)) | 
		(ft_col_pos[2] & m_axis_ft_roi_ready);
	
	assign m_axis_ft_roi_data = {
		ft_roi[8], ft_roi[7], ft_roi[6], 
		ft_roi[5], ft_roi[4], ft_roi[3],
		ft_roi[2], ft_roi[1], ft_roi[0]
	};
	assign m_axis_ft_roi_last = need_right_padding ? ft_col_pos[3]:s_axis_ft_col_last;
	assign m_axis_ft_roi_user = need_right_padding ? last_ft_map_grp_flag:s_axis_ft_col_user;
	/*
	握手条件: 
		(ft_col_pos[1] & s_axis_ft_col_valid & need_left_padding & m_axis_ft_roi_ready) | 
		(ft_col_pos[2] & s_axis_ft_col_valid & m_axis_ft_roi_ready) | 
		(ft_col_pos[3] & need_right_padding & m_axis_ft_roi_ready)
	*/
	assign m_axis_ft_roi_valid = 
		(ft_col_pos[1] & s_axis_ft_col_valid & need_left_padding) | 
		(ft_col_pos[2] & s_axis_ft_col_valid) | 
		(ft_col_pos[3] & need_right_padding);
	
	assign ft_roi[0] = ft_col_remaining_buf1[0]; // x1y1
	assign ft_roi[1] = ft_col_remaining_buf0[0]; // x2y1
	assign ft_roi[2] = ft_col_now[0]; // x3y1
	assign ft_roi[3] = ft_col_remaining_buf1[1]; // x1y2
	assign ft_roi[4] = ft_col_remaining_buf0[1]; // x2y2
	assign ft_roi[5] = ft_col_now[1]; // x3y2
	assign ft_roi[6] = ft_col_remaining_buf1[2]; // x1y3
	assign ft_roi[7] = ft_col_remaining_buf0[2]; // x2y3
	assign ft_roi[8] = ft_col_now[2]; // x3y3
	
	// 右填充时当前特征列全为0
	assign ft_col_now[0] = {mul_add_width{~ft_col_pos[3]}} & s_axis_ft_col_data[mul_add_width-1:0];
	assign ft_col_now[1] = {mul_add_width{~ft_col_pos[3]}} & s_axis_ft_col_data[mul_add_width*2-1:mul_add_width];
	assign ft_col_now[2] = {mul_add_width{~ft_col_pos[3]}} & s_axis_ft_col_data[mul_add_width*3-1:mul_add_width*2];
	
	// 卷积核类型为1x1时固定需要左/右填充
	assign need_left_padding = (~kernal_type) | padding_en[1];
	assign need_right_padding = (~kernal_type) | padding_en[0];
	
	// 特征列剩余缓存#0
	always @(posedge clk)
	begin
		if(s_axis_ft_col_valid & s_axis_ft_col_ready)
			{ft_col_remaining_buf0[2], ft_col_remaining_buf0[1], ft_col_remaining_buf0[0]} <= # simulation_delay 
				{ft_col_now[2], ft_col_now[1], ft_col_now[0]};
	end
	// 特征列剩余缓存#1
	always @(posedge clk)
	begin
		if(s_axis_ft_col_valid & s_axis_ft_col_ready)
			{ft_col_remaining_buf1[2], ft_col_remaining_buf1[1], ft_col_remaining_buf1[0]} <= # simulation_delay 
				{(mul_add_width*3){~ft_col_pos[0]}} & // 取走第1列后清零特征列剩余缓存#1
				{ft_col_remaining_buf0[2], ft_col_remaining_buf0[1], ft_col_remaining_buf0[0]};
	end
	
	// 特征图列位置
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			ft_col_pos <= 4'b0001;
		else if((ft_col_pos[0] & s_axis_ft_col_valid) | 
			(ft_col_pos[1] & s_axis_ft_col_valid & ((~need_left_padding) | m_axis_ft_roi_ready)) | 
			(ft_col_pos[2] & s_axis_ft_col_valid & m_axis_ft_roi_ready & s_axis_ft_col_last) | 
			(ft_col_pos[3] & ((~need_right_padding) | m_axis_ft_roi_ready)))
			ft_col_pos <= # simulation_delay {ft_col_pos[2:0], ft_col_pos[3]};
	end
	
	// 锁存的最后1组特征图(标志)
	always @(posedge clk)
	begin
		if(ft_col_pos[2] & s_axis_ft_col_valid & m_axis_ft_roi_ready & s_axis_ft_col_last)
			last_ft_map_grp_flag <= # simulation_delay s_axis_ft_col_user;
	end
	
	/** 卷积计算数据通路 **/
	// 特征图ROI输入
	// {x3y3, x2y3, x1y3, x3y2, x2y2, x1y2, x3y1, x2y1, x1y1}
	wire[mul_add_width*9-1:0] feature_roi;
	wire feature_roi_vld;
	wire feature_roi_last; // 本行最后1个ROI标志
	// 乘法器输入有效指示和输入本行最后1个ROI标志
	// {2级乘法器, 1级乘法器, 0级乘法器}
	wire[2:0] multiplier_in_vld; // 输入有效指示
	wire[2:0] multiplier_in_last; // 输入本行最后1个ROI标志
	// 待粘贴的卷积核输入
	// {x3y3, x2y3, x1y3, x3y2, x2y2, x1y2, x3y1, x2y1, x1y1}
	wire[mul_add_width*9-1:0] kernal_to_attach;
	// {第2列卷积核粘贴寄存器CE, 第1列卷积核粘贴寄存器CE, 第0列卷积核粘贴寄存器CE}
	wire[2:0] kernal_attach_s0_ce; // 0级系数粘贴使能
	wire[2:0] kernal_attach_s1_ce; // 1级系数粘贴使能
	// 卷积结果输出
	// 注意: 卷积结果的小数点在原先的高add_3_input_ext_frac_width位处
	wire[add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width-1:0] conv_res;
	wire conv_last;
	wire conv_res_vld;
	
	assign feature_roi = m_axis_ft_roi_data;
	assign feature_roi_vld = m_axis_ft_roi_valid & m_axis_ft_roi_ready;
	assign feature_roi_last = m_axis_ft_roi_last;
	
	assign kernal_to_attach = s_axis_kernal_data;
	
	generate
		if((add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width) == (mul_add_width*2))
			assign m_axis_res_data = conv_res;
		else
			assign m_axis_res_data = {
				{(mul_add_width-add_3_input_ext_int_width-add_3_input_ext_frac_width)
					{conv_res[add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width-1]}}, // 进行符号位拓展
				conv_res
			};
	endgenerate
	
	assign m_axis_res_last = conv_last;
	assign m_axis_res_valid = conv_res_vld;
	
	single_chn_conv_cal_3x3 #(
		.mul_add_width(mul_add_width),
		.quaz_acc(quaz_acc),
		.add_3_input_ext_int_width(add_3_input_ext_int_width),
		.add_3_input_ext_frac_width(add_3_input_ext_frac_width),
		.kernal_attach_stage_n(2),
		.simulation_delay(simulation_delay)
	)single_chn_conv_cal_3x3_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.feature_roi(feature_roi),
		.feature_roi_vld(feature_roi_vld),
		.feature_roi_last(feature_roi_last),
		
		.multiplier_in_vld(multiplier_in_vld),
		.multiplier_in_last(multiplier_in_last),
		
		.kernal_to_attach(kernal_to_attach),
		.kernal_attach_s0_ce(kernal_attach_s0_ce),
		.kernal_attach_s1_ce(kernal_attach_s1_ce),
		
		.conv_res(conv_res),
		.conv_last(conv_last),
		.conv_res_vld(conv_res_vld)
	);
	
	/** 固定卷积核参数 **/
	// 卷积核粘贴状态
	reg to_init_kernal; // 加载初始的卷积核(标志)
	reg on_init_kernal; // 现在加载初始的卷积核(指示)
	reg kernal_buffered; // 卷积核已缓存(标志)
	reg kernal_updating; // 正在更新卷积核(标志)
	
	// 握手条件: m_axis_ft_roi_valid & (~(to_init_kernal | on_init_kernal)) & 
	//     ((~m_axis_ft_roi_last) | m_axis_ft_roi_user | (kernal_buffered & (~kernal_updating)))
	assign m_axis_ft_roi_ready = 
		(~(to_init_kernal | on_init_kernal)) & // 等待加载初始的卷积核
		((~m_axis_ft_roi_last) | m_axis_ft_roi_user | (kernal_buffered & (~kernal_updating))); // 本行最后1个ROI进入计算单元时必须确保卷积核已缓存
	// 握手条件: s_axis_kernal_valid & ((~kernal_buffered) | to_init_kernal | (multiplier_in_vld[2] & multiplier_in_last[2]))
	assign s_axis_kernal_ready = 
		(~kernal_buffered) | 
		to_init_kernal | // 加载初始的卷积核时缓存区可用
		(multiplier_in_vld[2] & multiplier_in_last[2]); // 更新第2级乘法器的卷积核时缓存区可用
	
	assign kernal_attach_s0_ce = {3{s_axis_kernal_valid & s_axis_kernal_ready}};
	assign kernal_attach_s1_ce = {3{on_init_kernal}} | // 加载初始的卷积核
		(multiplier_in_vld & multiplier_in_last); // 计算本行最后1个ROI, 切换卷积核
	
	// 加载初始的卷积核(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			to_init_kernal <= 1'b1;
		else if(rst_kernal_buf | to_init_kernal)
			// rst_kernal_buf ? 1'b1:(~s_axis_kernal_valid)
			to_init_kernal <= # simulation_delay rst_kernal_buf | (~s_axis_kernal_valid);
	end
	
	// 现在加载初始的卷积核(指示)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			on_init_kernal <= 1'b0;
		else
			on_init_kernal <= # simulation_delay to_init_kernal & s_axis_kernal_valid;
	end
	
	// 卷积核已缓存(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			kernal_buffered <= 1'b0;
		else if(rst_kernal_buf | on_init_kernal | s_axis_kernal_ready)
			// (rst_kernal_buf | on_init_kernal) ? 1'b0:s_axis_kernal_valid
			kernal_buffered <= # simulation_delay (~(rst_kernal_buf | on_init_kernal)) & s_axis_kernal_valid;
	end
	
	// 正在更新卷积核(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			kernal_updating <= 1'b0;
		else if((multiplier_in_vld[0] & multiplier_in_last[0]) | (multiplier_in_vld[2] & multiplier_in_last[2]))
			// 断言: 不会同时更新第0级和第2级乘法器的卷积核!
			kernal_updating <= # simulation_delay multiplier_in_vld[0] & multiplier_in_last[0];
	end
	
endmodule
