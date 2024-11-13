`timescale 1ns / 1ps
/********************************************************************
本模块: AXIS线性乘加与激活计算单元

描述:
线性乘加 -> 
y = ax + b, 通常用于实现BN层或偏置

Relu激活 -> 
	          | cy, 当y < 0时
	z(c, y) = |
	          | y, 当y >= 0时

时延 = 线性乘加(4clk) + Relu激活(1clk)

变量x/y/z: 位宽 = xyz_ext_int_width + cal_width + xyz_ext_frac_width, 量化精度 = xyz_quaz_acc + xyz_ext_frac_width
系数a/b: 位宽 = cal_width, 量化精度 = ab_quaz_acc
系数c: 位宽 = cal_width, 量化精度 = c_quaz_acc

注意：
无

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2024/11/05
********************************************************************/


module axis_linear_act_cal #(
	parameter integer xyz_quaz_acc = 10, // x/y/z变量量化精度(必须在范围[1, cal_width-1]内)
	parameter integer ab_quaz_acc = 12, // a/b系数量化精度(必须在范围[1, cal_width-1]内)
	parameter integer c_quaz_acc = 14, // c系数量化精度(必须在范围[1, cal_width-1]内)
	parameter integer cal_width = 16, // 计算位宽(对于x/y/z和a/b/c来说, 可选8 | 16)
	parameter integer xyz_ext_int_width = 4, // x/y/z额外考虑的整数位数(必须<=(cal_width-xyz_quaz_acc))
	parameter integer xyz_ext_frac_width = 4, // x/y/z额外考虑的小数位数(必须<=xyz_quaz_acc)
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 运行时参数
	input wire[cal_width-1:0] act_rate_c, // Relu激活系数c
	
	// 多通道卷积计算结果输入(AXIS从机)
	// 仅低(xyz_ext_int_width+cal_width+xyz_ext_frac_width)位有效
	input wire[cal_width*2-1:0] s_axis_conv_res_data,
	input wire[15:0] s_axis_conv_res_user, // 当前输出特征行所在的通道号
	input wire s_axis_conv_res_last, // 表示行尾
	input wire s_axis_conv_res_valid,
	output wire s_axis_conv_res_ready,
	
	// 线性乘加与激活计算结果输出(AXIS主机)
	// 仅低(xyz_ext_int_width+cal_width+xyz_ext_frac_width)位有效
	output wire[cal_width*2-1:0] m_axis_linear_act_res_data,
	output wire m_axis_linear_act_res_last, // 表示行尾
	output wire m_axis_linear_act_res_valid,
	input wire m_axis_linear_act_res_ready,
	
	// 线性参数缓存区加载完成标志
	input wire linear_pars_buf_load_completed,
	
	// 线性参数获取(MEM读)
	output wire linear_pars_buffer_ren_s0,
	output wire linear_pars_buffer_ren_s1,
	output wire[15:0] linear_pars_buffer_raddr,
	input wire[cal_width-1:0] linear_pars_buffer_dout_a,
	input wire[cal_width-1:0] linear_pars_buffer_dout_b
);
    
    /** 输出fifo **/
	// fifo写端口
	wire out_fifo_wen;
	wire out_fifo_almost_full_n;
	wire[xyz_ext_int_width+cal_width+xyz_ext_frac_width-1:0] out_fifo_din; // 量化精度 = xyz_quaz_acc+xyz_ext_frac_width
	wire out_fifo_din_last; // 表示行尾
	// fifo读端口
	wire out_fifo_ren;
	wire out_fifo_empty_n;
	wire[xyz_ext_int_width+cal_width+xyz_ext_frac_width-1:0] out_fifo_dout; // 量化精度 = xyz_quaz_acc+xyz_ext_frac_width
	wire out_fifo_dout_last; // 表示行尾
	
	generate
		if((xyz_ext_int_width+cal_width+xyz_ext_frac_width) == (cal_width*2))
			assign m_axis_linear_act_res_data = out_fifo_dout;
		else
			assign m_axis_linear_act_res_data = 
				{{(cal_width-xyz_ext_int_width-xyz_ext_frac_width)
					{out_fifo_dout[xyz_ext_int_width+cal_width+xyz_ext_frac_width-1]}}, // 进行符号位拓展
				out_fifo_dout};
	endgenerate
	
	assign m_axis_linear_act_res_last = out_fifo_dout_last;
	// 握手条件: out_fifo_empty_n & m_axis_linear_act_res_ready
	assign m_axis_linear_act_res_valid = out_fifo_empty_n;
	// 握手条件: out_fifo_empty_n & m_axis_linear_act_res_ready
	assign out_fifo_ren = m_axis_linear_act_res_ready;
	
	// 输出fifo
	ram_fifo_wrapper #(
		.fwft_mode("true"),
		.ram_type("bram"),
		.en_bram_reg("false"),
		.fifo_depth(512),
		.fifo_data_width(xyz_ext_int_width+cal_width+xyz_ext_frac_width+1),
		.full_assert_polarity("low"),
		.empty_assert_polarity("low"),
		.almost_full_assert_polarity("low"),
		.almost_empty_assert_polarity("no"),
		.en_data_cnt("false"),
		.almost_full_th(512 - 16),
		.almost_empty_th(),
		.simulation_delay(simulation_delay)
	)out_fifo(
		.clk(clk),
		.rst_n(rst_n),
		
		.fifo_wen(out_fifo_wen),
		.fifo_din({out_fifo_din, out_fifo_din_last}),
		.fifo_almost_full_n(out_fifo_almost_full_n),
		
		.fifo_ren(out_fifo_ren),
		.fifo_dout({out_fifo_dout, out_fifo_dout_last}),
		.fifo_empty_n(out_fifo_empty_n)
	);
	
	/** 线性乘加 **/
	reg conv_res_in_vld_d; // 延迟1clk的卷积结果输入有效指示
	reg conv_res_in_vld_d2; // 延迟2clk的卷积结果输入有效指示
	reg conv_res_in_vld_d3; // 延迟3clk的卷积结果输入有效指示
	reg conv_res_in_vld_d4; // 延迟4clk的卷积结果输入有效指示
	reg conv_res_last_d; // 延迟1clk的卷积结果行尾标志
	reg conv_res_last_d2; // 延迟2clk的卷积结果行尾标志
	reg conv_res_last_d3; // 延迟3clk的卷积结果行尾标志
	reg conv_res_last_d4; // 延迟4clk的卷积结果行尾标志
	wire[xyz_ext_int_width+2*cal_width+xyz_ext_frac_width-1:0] linear_mul_add_res; // 线性乘加结果(量化精度 = xyz_quaz_acc+xyz_ext_frac_width+ab_quaz_acc)
	wire[xyz_ext_int_width+cal_width+xyz_ext_frac_width-1:0] linear_mul_add_res_quaz; // 舍入的线性乘加结果(量化精度 = xyz_quaz_acc+xyz_ext_frac_width)
	
	// 握手条件: s_axis_conv_res_valid & out_fifo_almost_full_n & linear_pars_buf_load_completed
	assign s_axis_conv_res_ready = out_fifo_almost_full_n & linear_pars_buf_load_completed;
	
	assign linear_pars_buffer_ren_s0 = s_axis_conv_res_valid & s_axis_conv_res_ready;
	assign linear_pars_buffer_ren_s1 = conv_res_in_vld_d;
	assign linear_pars_buffer_raddr = s_axis_conv_res_user;
	
	assign linear_mul_add_res_quaz = linear_mul_add_res[(xyz_ext_int_width+cal_width+xyz_ext_frac_width+ab_quaz_acc-1):ab_quaz_acc];
	
	// 延迟1clk的卷积结果输入有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			conv_res_in_vld_d <= 1'b0;
		else
			conv_res_in_vld_d <= # simulation_delay s_axis_conv_res_valid & s_axis_conv_res_ready;
	end
	// 延迟2clk的卷积结果输入有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			conv_res_in_vld_d2 <= 1'b0;
		else
			conv_res_in_vld_d2 <= # simulation_delay conv_res_in_vld_d;
	end
	// 延迟3clk的卷积结果输入有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			conv_res_in_vld_d3 <= 1'b0;
		else
			conv_res_in_vld_d3 <= # simulation_delay conv_res_in_vld_d2;
	end
	// 延迟4clk的卷积结果输入有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			conv_res_in_vld_d4 <= 1'b0;
		else
			conv_res_in_vld_d4 <= # simulation_delay conv_res_in_vld_d3;
	end
	
	// 延迟1clk的卷积结果行尾标志
	always @(posedge clk)
	begin
		if(s_axis_conv_res_valid & s_axis_conv_res_ready)
			conv_res_last_d <= # simulation_delay s_axis_conv_res_last;
	end
	// 延迟2clk的卷积结果行尾标志
	always @(posedge clk)
	begin
		if(conv_res_in_vld_d)
			conv_res_last_d2 <= # simulation_delay conv_res_last_d;
	end
	// 延迟3clk的卷积结果行尾标志
	always @(posedge clk)
	begin
		if(conv_res_in_vld_d2)
			conv_res_last_d3 <= # simulation_delay conv_res_last_d2;
	end
	// 延迟4clk的卷积结果行尾标志
	always @(posedge clk)
	begin
		if(conv_res_in_vld_d3)
			conv_res_last_d4 <= # simulation_delay conv_res_last_d3;
	end
	
	/*
	乘加器
	
	op_a ---> {第0级寄存器} ----|
	                           {+} --> {第1级寄存器} ----|
	  0  -----------------------|                       {*} ---> {第2级寄存器} ----|
	op_b ------------------------------------------------|                        {+} ---> {第3级寄存器}
	op_c ------------------------------------------------------> {第2级寄存器} ----|
	*/
	mul_add_dsp #(
		.en_op_a_in_regs("true"),
		.en_op_b_in_regs("false"),
		.en_op_d_in_regs("false"),
		.en_pre_adder("true"),
		.en_op_b_in_s1_regs("false"),
		.en_op_c_in_s1_regs("false"),
		.op_a_width(xyz_ext_int_width+cal_width+xyz_ext_frac_width),
		.op_b_width(cal_width),
		.op_c_width(xyz_ext_int_width+2*cal_width+xyz_ext_frac_width),
		.op_d_width(xyz_ext_int_width+cal_width+xyz_ext_frac_width),
		.output_width(xyz_ext_int_width+2*cal_width+xyz_ext_frac_width),
		.pattern_detect_msb_id(0),
		.pattern_detect_lsb_id(0),
		.pattern_detect_cmp(1'b0),
		.simulation_delay(simulation_delay)
	)linear_mul_add(
		.clk(clk),
		
		.ce_s0_op_a(s_axis_conv_res_valid & s_axis_conv_res_ready),
		.ce_s0_op_b(1'b1),
		.ce_s0_op_d(1'b1),
		.ce_s1_pre_adder(conv_res_in_vld_d),
		.ce_s1_op_b(1'b1),
		.ce_s1_op_c(1'b1),
		.ce_s2_mul(conv_res_in_vld_d2),
		.ce_s2_op_c(conv_res_in_vld_d2),
		.ce_s3_p(conv_res_in_vld_d3),
		
		// 量化精度 = xyz_quaz_acc+xyz_ext_frac_width
		.op_a(s_axis_conv_res_data[xyz_ext_int_width+cal_width+xyz_ext_frac_width-1:0]),
		// 量化精度 = ab_quaz_acc
		.op_b(linear_pars_buffer_dout_a),
		// 量化精度 = xyz_quaz_acc+xyz_ext_frac_width+ab_quaz_acc
		.op_c({{(xyz_ext_int_width+cal_width-xyz_quaz_acc){linear_pars_buffer_dout_b[cal_width-1]}}, // 进行符号位拓展
			linear_pars_buffer_dout_b, 
			{(xyz_quaz_acc+xyz_ext_frac_width){1'b0}}}),
		.op_d({(xyz_ext_int_width+cal_width+xyz_ext_frac_width){1'b0}}),
		
		.res(linear_mul_add_res),
		.pattern_detect_res()
	);
	
	/** Relu激活 **/
	reg conv_res_in_vld_d5; // 延迟5clk的卷积结果输入有效指示
	reg conv_res_last_d5; // 延迟5clk的卷积结果行尾标志
	wire[xyz_ext_int_width+cal_width+xyz_ext_frac_width-1:0] relu_mul_op_a_in; // 量化精度 = xyz_quaz_acc+xyz_ext_frac_width
	wire[cal_width-1:0] relu_mul_op_b_in; // 量化精度 = c_quaz_acc
	wire[xyz_ext_int_width+cal_width*2+xyz_ext_frac_width-1:0] relu_mul_res; // 量化精度 = xyz_quaz_acc+xyz_ext_frac_width+c_quaz_acc
	
	assign out_fifo_wen = conv_res_in_vld_d5;
	assign out_fifo_din = relu_mul_res[(c_quaz_acc+xyz_ext_int_width+cal_width+xyz_ext_frac_width-1):c_quaz_acc];
	assign out_fifo_din_last = conv_res_last_d5;
	
	assign relu_mul_op_a_in = linear_mul_add_res_quaz;
	// (线性乘加结果 < 0) ? 系数c:1
	assign relu_mul_op_b_in = linear_mul_add_res_quaz[xyz_ext_int_width+cal_width+xyz_ext_frac_width-1] ? 
		act_rate_c:((c_quaz_acc == (cal_width-1)) ? 
			{1'b0, {(cal_width-1){1'b1}}}:
			({{(cal_width-1){1'b0}}, 1'b1} << c_quaz_acc));
	
	// 延迟5clk的卷积结果输入有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			conv_res_in_vld_d5 <= 1'b0;
		else
			conv_res_in_vld_d5 <= # simulation_delay conv_res_in_vld_d4;
	end
	
	// 延迟5clk的卷积结果行尾标志
	always @(posedge clk)
	begin
		if(conv_res_in_vld_d4)
			conv_res_last_d5 <= # simulation_delay conv_res_last_d4;
	end
	
	// 乘法器
	mul #(
		.op_a_width(xyz_ext_int_width+cal_width+xyz_ext_frac_width),
		.op_b_width(cal_width),
		.output_width(xyz_ext_int_width+cal_width*2+xyz_ext_frac_width),
		.simulation_delay(simulation_delay)
	)relu_mul(
		.clk(clk),
		
		.ce_s0_mul(conv_res_in_vld_d4),
		
		.op_a(relu_mul_op_a_in),
		.op_b(relu_mul_op_b_in),
		
		.res(relu_mul_res)
	);
	
endmodule
