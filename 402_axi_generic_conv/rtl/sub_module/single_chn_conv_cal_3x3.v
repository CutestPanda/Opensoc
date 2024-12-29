`timescale 1ns / 1ps
/********************************************************************
本模块: 单通道3x3卷积计算单元

描述:
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

可选1级/2级卷积核粘贴寄存器

9级流水线:
	3x3乘加器(6级流水线)
	3输入加法器(3级流水线)

注意：
对于xilinx系列FPGA, 1个DSP单元可以完成计算:
	P[47:0] = (A[24:0] + D[24:0]) * B[17:0] + C[47:0]

协议:
无

作者: 陈家耀
日期: 2024/12/25
********************************************************************/


module single_chn_conv_cal_3x3 #(
	parameter en_use_dsp_for_add_3 = "false", // 是否使用DSP来实现三输入加法器
	parameter integer mul_add_width = 16, // 乘加位宽
	parameter integer quaz_acc = 10, // 量化精度(必须在范围[1, mul_add_width-1]内)
	parameter integer add_3_input_ext_int_width = 4, // 三输入加法器额外考虑的整数位数(必须<=(mul_add_width-quaz_acc))
	parameter integer add_3_input_ext_frac_width = 4, // 三输入加法器额外考虑的小数位数(必须<=quaz_acc)
	parameter integer kernal_attach_stage_n = 2, // 卷积核粘贴寄存器级数
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 特征图ROI输入
	// {x3y3, x2y3, x1y3, x3y2, x2y2, x1y2, x3y1, x2y1, x1y1}
	input wire[mul_add_width*9-1:0] feature_roi,
	input wire feature_roi_vld,
	input wire feature_roi_last, // 本行最后1个ROI标志
	
	// 乘法器输入有效指示和输入本行最后1个ROI标志
	// {2级乘法器, 1级乘法器, 0级乘法器}
	output wire[2:0] multiplier_in_vld, // 输入有效指示
	output wire[2:0] multiplier_in_last, // 输入本行最后1个ROI标志
	
	// 待粘贴的卷积核输入
	// {x3y3, x2y3, x1y3, x3y2, x2y2, x1y2, x3y1, x2y1, x1y1}
	input wire[mul_add_width*9-1:0] kernal_to_attach,
	// op_b -> [0级卷积核粘贴寄存器] -> 1级卷积核粘贴寄存器
	// {第2列卷积核粘贴寄存器CE, 第1列卷积核粘贴寄存器CE, 第0列卷积核粘贴寄存器CE}
	input wire[2:0] kernal_attach_s0_ce, // 0级系数粘贴使能(仅当卷积核粘贴寄存器级数为2时可用)
	input wire[2:0] kernal_attach_s1_ce, // 1级系数粘贴使能
	
	// 卷积结果输出
	// 卷积结果的小数点在原先的高add_3_input_ext_frac_width位处
	output wire[add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width-1:0] conv_res,
	output wire conv_last,
	output wire conv_res_vld
);
	
	/** 特征图ROI输入有效指示延迟链 **/
	reg feature_roi_vld_d;
	reg feature_roi_vld_d2;
	reg feature_roi_vld_d3;
	reg feature_roi_vld_d4;
	reg feature_roi_vld_d5;
	reg feature_roi_vld_d6;
	reg feature_roi_vld_d7;
	reg feature_roi_vld_d8;
	reg feature_roi_vld_d9;
	
	assign multiplier_in_vld = {feature_roi_vld_d4, feature_roi_vld_d2, feature_roi_vld};
	
	// 延迟1~9clk的特征图ROI输入有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
		begin
			{feature_roi_vld_d9, feature_roi_vld_d8, feature_roi_vld_d7,
			feature_roi_vld_d6, feature_roi_vld_d5, feature_roi_vld_d4,
			feature_roi_vld_d3, feature_roi_vld_d2, feature_roi_vld_d} <= 9'b000_00_00_00;
		end
		else
		begin
			{feature_roi_vld_d9, feature_roi_vld_d8, feature_roi_vld_d7,
			feature_roi_vld_d6, feature_roi_vld_d5, feature_roi_vld_d4,
			feature_roi_vld_d3, feature_roi_vld_d2, feature_roi_vld_d} <= 
				# simulation_delay {feature_roi_vld_d8, feature_roi_vld_d7, feature_roi_vld_d6,
					feature_roi_vld_d5, feature_roi_vld_d4, feature_roi_vld_d3,
					feature_roi_vld_d2, feature_roi_vld_d, feature_roi_vld};
		end
	end
	
	/** 输入本行最后1个ROI标志延迟链 **/
	reg feature_roi_last_d;
	reg feature_roi_last_d2;
	reg feature_roi_last_d3;
	reg feature_roi_last_d4;
	reg feature_roi_last_d5;
	reg feature_roi_last_d6;
	reg feature_roi_last_d7;
	reg feature_roi_last_d8;
	reg feature_roi_last_d9;
	
	assign multiplier_in_last = {feature_roi_last_d4, feature_roi_last_d2, feature_roi_last};
	
	assign conv_last = feature_roi_last_d9;
	
	// 延迟1clk的输入本行最后1个ROI标志
	always @(posedge clk)
	begin
		if(feature_roi_vld)
			feature_roi_last_d <= # simulation_delay feature_roi_last;
	end
	// 延迟2clk的输入本行最后1个ROI标志
	always @(posedge clk)
	begin
		if(feature_roi_vld_d)
			feature_roi_last_d2 <= # simulation_delay feature_roi_last_d;
	end
	// 延迟3clk的输入本行最后1个ROI标志
	always @(posedge clk)
	begin
		if(feature_roi_vld_d2)
			feature_roi_last_d3 <= # simulation_delay feature_roi_last_d2;
	end
	// 延迟4clk的输入本行最后1个ROI标志
	always @(posedge clk)
	begin
		if(feature_roi_vld_d3)
			feature_roi_last_d4 <= # simulation_delay feature_roi_last_d3;
	end
	// 延迟5clk的输入本行最后1个ROI标志
	always @(posedge clk)
	begin
		if(feature_roi_vld_d4)
			feature_roi_last_d5 <= # simulation_delay feature_roi_last_d4;
	end
	// 延迟6clk的输入本行最后1个ROI标志
	always @(posedge clk)
	begin
		if(feature_roi_vld_d5)
			feature_roi_last_d6 <= # simulation_delay feature_roi_last_d5;
	end
	// 延迟7clk的输入本行最后1个ROI标志
	always @(posedge clk)
	begin
		if(feature_roi_vld_d6)
			feature_roi_last_d7 <= # simulation_delay feature_roi_last_d6;
	end
	// 延迟8clk的输入本行最后1个ROI标志
	always @(posedge clk)
	begin
		if(feature_roi_vld_d7)
			feature_roi_last_d8 <= # simulation_delay feature_roi_last_d7;
	end
	// 延迟9clk的输入本行最后1个ROI标志
	always @(posedge clk)
	begin
		if(feature_roi_vld_d8)
			feature_roi_last_d9 <= # simulation_delay feature_roi_last_d8;
	end
	
	/** 乘加器 **/
	wire[mul_add_width*2-1:0] mul_add_dsp_row_res[0:2]; // 各行乘加结果
	
	genvar mul_add_row_i;
	generate
		for(mul_add_row_i = 0;mul_add_row_i < 3;mul_add_row_i = mul_add_row_i + 1)
		begin
			wire[mul_add_width*2-1:0] mul_add_dsp_col0_res; // 第0列乘加结果
			wire[mul_add_width*2-1:0] mul_add_dsp_col1_res; // 第1列乘加结果
			wire[mul_add_width*2-1:0] mul_add_dsp_col2_res; // 第2列乘加结果
			
			assign mul_add_dsp_row_res[mul_add_row_i] = mul_add_dsp_col2_res;
			
			/*
			op_a --------------------------------------|
			                                          {*} ---> 2级寄存器 ------
			op_b ---> [0级寄存器] ---> 1级寄存器 ------|                      |
			                                                                 {+} ---> 3级寄存器 --->
			                                                                  |
			op_c --------------------------------------------> 2级寄存器 ------
			*/
			mul_add_dsp #(
				.en_op_a_in_regs("false"),
				.en_op_b_in_regs((kernal_attach_stage_n == 2) ? "true":"false"),
				.en_op_d_in_regs("false"),
				.en_pre_adder("false"),
				.en_op_b_in_s1_regs("true"),
				.en_op_c_in_s1_regs("false"),
				.op_a_width(mul_add_width),
				.op_b_width(mul_add_width),
				.op_c_width(mul_add_width*2),
				.op_d_width(mul_add_width),
				.output_width(mul_add_width*2),
				.pattern_detect_msb_id(0),
				.pattern_detect_lsb_id(0),
				.pattern_detect_cmp(1'b0),
				.simulation_delay(simulation_delay)
			)mul_add_dsp_col0(
				.clk(clk),
				
				.ce_s0_op_a(1'b1), // not care
				.ce_s0_op_b(kernal_attach_s0_ce[0]),
				.ce_s0_op_d(1'b1), // not care
				.ce_s1_pre_adder(1'b1), // not care
				.ce_s1_op_b(kernal_attach_s1_ce[0]),
				.ce_s1_op_c(1'b1), // not care
				.ce_s2_mul(feature_roi_vld),
				.ce_s2_op_c(feature_roi_vld),
				.ce_s3_p(feature_roi_vld_d),
				
				.op_a(feature_roi[(mul_add_row_i*3+1)*mul_add_width-1:(mul_add_row_i*3)*mul_add_width]), // x1yi
				.op_b(kernal_to_attach[(mul_add_row_i*3+1)*mul_add_width-1:(mul_add_row_i*3)*mul_add_width]), // x1yi
				.op_c({(mul_add_width*2){1'b0}}),
				.op_d({mul_add_width{1'b0}}), // not care
				
				.res(mul_add_dsp_col0_res),
				.pattern_detect_res()
			);
			
			/*
			为op_a增加2级输入寄存器以补偿第0列乘加器
			
			op_d(恒为0) -------------|
			                        {+} ---> 1级寄存器 --|
			op_a ---> 0级寄存器 -----|                   |
			                                            {*} ---> 2级寄存器 ------
			op_b ---> [0级寄存器] ---> 1级寄存器 --------|                      |
			                                                                   {+} ---> 3级寄存器 --->
			                                                                    |
			op_c --------------------------------------------> 2级寄存器 --------
			*/
			mul_add_dsp #(
				.en_op_a_in_regs("true"),
				.en_op_b_in_regs((kernal_attach_stage_n == 2) ? "true":"false"),
				.en_op_d_in_regs("false"),
				.en_pre_adder("true"),
				.en_op_b_in_s1_regs("true"),
				.en_op_c_in_s1_regs("false"),
				.op_a_width(mul_add_width),
				.op_b_width(mul_add_width),
				.op_c_width(mul_add_width*2),
				.op_d_width(mul_add_width),
				.output_width(mul_add_width*2),
				.pattern_detect_msb_id(0),
				.pattern_detect_lsb_id(0),
				.pattern_detect_cmp(1'b0),
				.simulation_delay(simulation_delay)
			)mul_add_dsp_col1(
				.clk(clk),
				
				.ce_s0_op_a(feature_roi_vld),
				.ce_s0_op_b(kernal_attach_s0_ce[1]),
				.ce_s0_op_d(1'b1), // not care
				.ce_s1_pre_adder(feature_roi_vld_d),
				.ce_s1_op_b(kernal_attach_s1_ce[1]),
				.ce_s1_op_c(1'b1), // not care
				.ce_s2_mul(feature_roi_vld_d2),
				.ce_s2_op_c(feature_roi_vld_d2),
				.ce_s3_p(feature_roi_vld_d3),
				
				.op_a(feature_roi[((mul_add_row_i*3+1)+1)*mul_add_width-1:(mul_add_row_i*3+1)*mul_add_width]), // x2yi
				.op_b(kernal_to_attach[((mul_add_row_i*3+1)+1)*mul_add_width-1:(mul_add_row_i*3+1)*mul_add_width]), // x2yi
				.op_c(mul_add_dsp_col0_res),
				.op_d({mul_add_width{1'b0}}),
				
				.res(mul_add_dsp_col1_res),
				.pattern_detect_res()
			);
			
			/*
			为op_a增加2级输入寄存器以补偿第1列乘加器
			
			op_d(恒为0) -------------|
			                        {+} ---> 1级寄存器 --|
			op_a ---> 0级寄存器 -----|                   |
			                                            {*} ---> 2级寄存器 ------
			op_b ---> [0级寄存器] ---> 1级寄存器 --------|                      |
			                                                                   {+} ---> 3级寄存器 --->
			                                                                    |
			op_c --------------------------------------------> 2级寄存器 --------
			*/
			// 为op_a增加2级寄存器以补偿第0列乘加器
			reg[mul_add_width-1:0] mul_add_dsp_col2_op_a_cps_0;
			reg[mul_add_width-1:0] mul_add_dsp_col2_op_a_cps_1;
			
			always @(posedge clk)
			begin
				if(feature_roi_vld)
					mul_add_dsp_col2_op_a_cps_0 <= # simulation_delay 
						feature_roi[((mul_add_row_i*3+2)+1)*mul_add_width-1:(mul_add_row_i*3+2)*mul_add_width]; // x3yi
			end
			
			always @(posedge clk)
			begin
				if(feature_roi_vld_d)
					mul_add_dsp_col2_op_a_cps_1 <= # simulation_delay mul_add_dsp_col2_op_a_cps_0;
			end
			
			mul_add_dsp #(
				.en_op_a_in_regs("true"),
				.en_op_b_in_regs((kernal_attach_stage_n == 2) ? "true":"false"),
				.en_op_d_in_regs("false"),
				.en_pre_adder("true"),
				.en_op_b_in_s1_regs("true"),
				.en_op_c_in_s1_regs("false"),
				.op_a_width(mul_add_width),
				.op_b_width(mul_add_width),
				.op_c_width(mul_add_width*2),
				.op_d_width(mul_add_width),
				.output_width(mul_add_width*2),
				.pattern_detect_msb_id(0),
				.pattern_detect_lsb_id(0),
				.pattern_detect_cmp(1'b0),
				.simulation_delay(simulation_delay)
			)mul_add_dsp_col2(
				.clk(clk),
				
				.ce_s0_op_a(feature_roi_vld_d2),
				.ce_s0_op_b(kernal_attach_s0_ce[2]),
				.ce_s0_op_d(1'b1), // not care
				.ce_s1_pre_adder(feature_roi_vld_d3),
				.ce_s1_op_b(kernal_attach_s1_ce[2]),
				.ce_s1_op_c(1'b1), // not care
				.ce_s2_mul(feature_roi_vld_d4),
				.ce_s2_op_c(feature_roi_vld_d4),
				.ce_s3_p(feature_roi_vld_d5),
				
				.op_a(mul_add_dsp_col2_op_a_cps_1), // x3yi
				.op_b(kernal_to_attach[((mul_add_row_i*3+2)+1)*mul_add_width-1:(mul_add_row_i*3+2)*mul_add_width]), // x3yi
				.op_c(mul_add_dsp_col1_res),
				.op_d({mul_add_width{1'b0}}),
				
				.res(mul_add_dsp_col2_res),
				.pattern_detect_res()
			);
		end
	endgenerate
	
	/** 三输入加法器 **/
	wire[add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width-1:0] add_3_input_res;
	
	assign conv_res = add_3_input_res;
	assign conv_res_vld = feature_roi_vld_d9;
	
	add_3_in_dsp #(
		.en_use_dsp(en_use_dsp_for_add_3),
		.op_a_width(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width),
		.op_c_width(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width),
		.op_d_width(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width),
		.output_width(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width),
		.simulation_delay(simulation_delay)
	)add_3_input(
		.clk(clk),
		
		.ce_s1_pre_adder(feature_roi_vld_d6),
		.ce_s1_op_c(feature_roi_vld_d6),
		.ce_s2_mul(feature_roi_vld_d7),
		.ce_s2_op_c(feature_roi_vld_d7),
		.ce_s3_p(feature_roi_vld_d8),
		
		// 将乘加结果右移(quaz_acc-add_3_input_ext_frac_width)位, 卷积结果的小数点在原先的高add_3_input_ext_frac_width位处
		.op_a(mul_add_dsp_row_res[0][add_3_input_ext_int_width+quaz_acc+mul_add_width-1:quaz_acc-add_3_input_ext_frac_width]),
		.op_c(mul_add_dsp_row_res[1][add_3_input_ext_int_width+quaz_acc+mul_add_width-1:quaz_acc-add_3_input_ext_frac_width]),
		.op_d(mul_add_dsp_row_res[2][add_3_input_ext_int_width+quaz_acc+mul_add_width-1:quaz_acc-add_3_input_ext_frac_width]),
		
		.res(add_3_input_res)
	);
	
endmodule
