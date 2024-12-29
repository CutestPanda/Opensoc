`timescale 1ns / 1ps
/********************************************************************
本模块: 计算结果限幅处理

描述:
下溢时将计算结果设为{1'b1, {(feature_pars_data_width-1){1'b0}}}
上溢时将计算结果设为{1'b0, {(feature_pars_data_width-1){1'b1}}}
未溢出则直接传递计算结果

注意：
无

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2024/12/25
********************************************************************/


module axis_res_amp_lmt #(
	parameter integer feature_pars_data_width = 16, // 特征点和参数位宽(8 | 16 | 32 | 64)
	parameter integer conv_res_ext_int_width = 4, // 卷积结果额外考虑的整数位数(必须<=(feature_pars_data_width-in_ft_quaz_acc))
	parameter integer conv_res_ext_frac_width = 4, // 卷积结果额外考虑的小数位数(必须<=in_ft_quaz_acc)
	parameter en_out_reg_slice_forward_register = "true", // 使能输出AXIS寄存器片的前向寄存器
	parameter en_out_reg_slice_back_register = "false", // 使能输出AXIS寄存器片的后向寄存器
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 计算结果输入(AXIS从机)
	// 仅低(conv_res_ext_int_width+feature_pars_data_width+conv_res_ext_frac_width)位有效
	input wire[feature_pars_data_width*2-1:0] s_axis_amp_lmt_data,
	input wire s_axis_amp_lmt_last, // 表示行尾
	input wire s_axis_amp_lmt_valid,
	output wire s_axis_amp_lmt_ready,
	
	// 限幅后计算结果输出(AXIS主机)
	output wire[feature_pars_data_width-1:0] m_axis_amp_lmt_data,
	output wire m_axis_amp_lmt_last, // 表示行尾
	output wire m_axis_amp_lmt_valid,
	input wire m_axis_amp_lmt_ready
);
	
	// 溢出判定
	wire feature_point_final_up_ovg; // 上溢标志
	wire feature_point_final_down_ovg; // 下溢标志
	// AXIS寄存器片从机输入
	wire[feature_pars_data_width-1:0] s_axis_reg_slice_data;
	wire s_axis_reg_slice_last; // 表示行尾
	wire s_axis_reg_slice_valid;
	wire s_axis_reg_slice_ready;
	// AXIS寄存器片主机输出
	wire[feature_pars_data_width-1:0] m_axis_reg_slice_data;
	wire m_axis_reg_slice_last; // 表示行尾
	wire m_axis_reg_slice_valid;
	wire m_axis_reg_slice_ready;
	
	assign s_axis_reg_slice_data[feature_pars_data_width-1] = 
		s_axis_amp_lmt_data[conv_res_ext_int_width+feature_pars_data_width+conv_res_ext_frac_width-1];
	assign s_axis_reg_slice_data[feature_pars_data_width-2:0] = 
		{(feature_pars_data_width-1){~feature_point_final_down_ovg}} & // 下溢
		({(feature_pars_data_width-1){feature_point_final_up_ovg}} | // 上溢
			s_axis_amp_lmt_data[conv_res_ext_frac_width+feature_pars_data_width-2:conv_res_ext_frac_width]);
	assign s_axis_reg_slice_last = s_axis_amp_lmt_last;
	assign s_axis_reg_slice_valid = s_axis_amp_lmt_valid;
	assign s_axis_amp_lmt_ready = s_axis_reg_slice_ready;
	
	assign m_axis_amp_lmt_data = m_axis_reg_slice_data;
	assign m_axis_amp_lmt_last = m_axis_reg_slice_last;
	assign m_axis_amp_lmt_valid = m_axis_reg_slice_valid;
	assign m_axis_reg_slice_ready = m_axis_amp_lmt_ready;
	
	generate
		if(conv_res_ext_int_width >= 2)
			assign feature_point_final_up_ovg = 
				// 结果为正
				(~s_axis_amp_lmt_data[conv_res_ext_int_width+feature_pars_data_width+conv_res_ext_frac_width-1]) & 
				// 拓展的整数位不全0
				(|s_axis_amp_lmt_data[conv_res_ext_int_width+feature_pars_data_width+conv_res_ext_frac_width-2:
					feature_pars_data_width+conv_res_ext_frac_width]);
		else
			assign feature_point_final_up_ovg = 1'b0;
	endgenerate
	
	generate
		if(conv_res_ext_int_width >= 2)
			assign feature_point_final_down_ovg = 
				// 结果为负
				s_axis_amp_lmt_data[conv_res_ext_int_width+feature_pars_data_width+conv_res_ext_frac_width-1] & 
				// 拓展的整数位不全1
				(~(&s_axis_amp_lmt_data[conv_res_ext_int_width+feature_pars_data_width+conv_res_ext_frac_width-2:
					feature_pars_data_width+conv_res_ext_frac_width]));
		else
			assign feature_point_final_down_ovg = 1'b0;
	endgenerate
	
	axis_reg_slice #(
		.data_width(feature_pars_data_width),
		.user_width(1),
		.forward_registered(en_out_reg_slice_forward_register),
		.back_registered(en_out_reg_slice_back_register),
		.en_ready("true"),
		.simulation_delay(simulation_delay)
	)out_reg_slice(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axis_data(s_axis_reg_slice_data),
		.s_axis_last(s_axis_reg_slice_last),
		.s_axis_valid(s_axis_reg_slice_valid),
		.s_axis_ready(s_axis_reg_slice_ready),
		
		.m_axis_data(m_axis_reg_slice_data),
		.m_axis_last(m_axis_reg_slice_last),
		.m_axis_valid(m_axis_reg_slice_valid),
		.m_axis_ready(m_axis_reg_slice_ready)
	);
	
endmodule
