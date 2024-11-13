`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXIS���Գ˼��뼤����㵥Ԫ

����:
���Գ˼� -> 
y = ax + b, ͨ������ʵ��BN���ƫ��

Relu���� -> 
	          | cy, ��y < 0ʱ
	z(c, y) = |
	          | y, ��y >= 0ʱ

ʱ�� = ���Գ˼�(4clk) + Relu����(1clk)

����x/y/z: λ�� = xyz_ext_int_width + cal_width + xyz_ext_frac_width, �������� = xyz_quaz_acc + xyz_ext_frac_width
ϵ��a/b: λ�� = cal_width, �������� = ab_quaz_acc
ϵ��c: λ�� = cal_width, �������� = c_quaz_acc

ע�⣺
��

Э��:
AXIS MASTER/SLAVE

����: �¼�ҫ
����: 2024/11/05
********************************************************************/


module axis_linear_act_cal #(
	parameter integer xyz_quaz_acc = 10, // x/y/z������������(�����ڷ�Χ[1, cal_width-1]��)
	parameter integer ab_quaz_acc = 12, // a/bϵ����������(�����ڷ�Χ[1, cal_width-1]��)
	parameter integer c_quaz_acc = 14, // cϵ����������(�����ڷ�Χ[1, cal_width-1]��)
	parameter integer cal_width = 16, // ����λ��(����x/y/z��a/b/c��˵, ��ѡ8 | 16)
	parameter integer xyz_ext_int_width = 4, // x/y/z���⿼�ǵ�����λ��(����<=(cal_width-xyz_quaz_acc))
	parameter integer xyz_ext_frac_width = 4, // x/y/z���⿼�ǵ�С��λ��(����<=xyz_quaz_acc)
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
	input wire clk,
	input wire rst_n,
	
	// ����ʱ����
	input wire[cal_width-1:0] act_rate_c, // Relu����ϵ��c
	
	// ��ͨ���������������(AXIS�ӻ�)
	// ����(xyz_ext_int_width+cal_width+xyz_ext_frac_width)λ��Ч
	input wire[cal_width*2-1:0] s_axis_conv_res_data,
	input wire[15:0] s_axis_conv_res_user, // ��ǰ������������ڵ�ͨ����
	input wire s_axis_conv_res_last, // ��ʾ��β
	input wire s_axis_conv_res_valid,
	output wire s_axis_conv_res_ready,
	
	// ���Գ˼��뼤����������(AXIS����)
	// ����(xyz_ext_int_width+cal_width+xyz_ext_frac_width)λ��Ч
	output wire[cal_width*2-1:0] m_axis_linear_act_res_data,
	output wire m_axis_linear_act_res_last, // ��ʾ��β
	output wire m_axis_linear_act_res_valid,
	input wire m_axis_linear_act_res_ready,
	
	// ���Բ���������������ɱ�־
	input wire linear_pars_buf_load_completed,
	
	// ���Բ�����ȡ(MEM��)
	output wire linear_pars_buffer_ren_s0,
	output wire linear_pars_buffer_ren_s1,
	output wire[15:0] linear_pars_buffer_raddr,
	input wire[cal_width-1:0] linear_pars_buffer_dout_a,
	input wire[cal_width-1:0] linear_pars_buffer_dout_b
);
    
    /** ���fifo **/
	// fifoд�˿�
	wire out_fifo_wen;
	wire out_fifo_almost_full_n;
	wire[xyz_ext_int_width+cal_width+xyz_ext_frac_width-1:0] out_fifo_din; // �������� = xyz_quaz_acc+xyz_ext_frac_width
	wire out_fifo_din_last; // ��ʾ��β
	// fifo���˿�
	wire out_fifo_ren;
	wire out_fifo_empty_n;
	wire[xyz_ext_int_width+cal_width+xyz_ext_frac_width-1:0] out_fifo_dout; // �������� = xyz_quaz_acc+xyz_ext_frac_width
	wire out_fifo_dout_last; // ��ʾ��β
	
	generate
		if((xyz_ext_int_width+cal_width+xyz_ext_frac_width) == (cal_width*2))
			assign m_axis_linear_act_res_data = out_fifo_dout;
		else
			assign m_axis_linear_act_res_data = 
				{{(cal_width-xyz_ext_int_width-xyz_ext_frac_width)
					{out_fifo_dout[xyz_ext_int_width+cal_width+xyz_ext_frac_width-1]}}, // ���з���λ��չ
				out_fifo_dout};
	endgenerate
	
	assign m_axis_linear_act_res_last = out_fifo_dout_last;
	// ��������: out_fifo_empty_n & m_axis_linear_act_res_ready
	assign m_axis_linear_act_res_valid = out_fifo_empty_n;
	// ��������: out_fifo_empty_n & m_axis_linear_act_res_ready
	assign out_fifo_ren = m_axis_linear_act_res_ready;
	
	// ���fifo
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
	
	/** ���Գ˼� **/
	reg conv_res_in_vld_d; // �ӳ�1clk�ľ�����������Чָʾ
	reg conv_res_in_vld_d2; // �ӳ�2clk�ľ�����������Чָʾ
	reg conv_res_in_vld_d3; // �ӳ�3clk�ľ�����������Чָʾ
	reg conv_res_in_vld_d4; // �ӳ�4clk�ľ�����������Чָʾ
	reg conv_res_last_d; // �ӳ�1clk�ľ�������β��־
	reg conv_res_last_d2; // �ӳ�2clk�ľ�������β��־
	reg conv_res_last_d3; // �ӳ�3clk�ľ�������β��־
	reg conv_res_last_d4; // �ӳ�4clk�ľ�������β��־
	wire[xyz_ext_int_width+2*cal_width+xyz_ext_frac_width-1:0] linear_mul_add_res; // ���Գ˼ӽ��(�������� = xyz_quaz_acc+xyz_ext_frac_width+ab_quaz_acc)
	wire[xyz_ext_int_width+cal_width+xyz_ext_frac_width-1:0] linear_mul_add_res_quaz; // ��������Գ˼ӽ��(�������� = xyz_quaz_acc+xyz_ext_frac_width)
	
	// ��������: s_axis_conv_res_valid & out_fifo_almost_full_n & linear_pars_buf_load_completed
	assign s_axis_conv_res_ready = out_fifo_almost_full_n & linear_pars_buf_load_completed;
	
	assign linear_pars_buffer_ren_s0 = s_axis_conv_res_valid & s_axis_conv_res_ready;
	assign linear_pars_buffer_ren_s1 = conv_res_in_vld_d;
	assign linear_pars_buffer_raddr = s_axis_conv_res_user;
	
	assign linear_mul_add_res_quaz = linear_mul_add_res[(xyz_ext_int_width+cal_width+xyz_ext_frac_width+ab_quaz_acc-1):ab_quaz_acc];
	
	// �ӳ�1clk�ľ�����������Чָʾ
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			conv_res_in_vld_d <= 1'b0;
		else
			conv_res_in_vld_d <= # simulation_delay s_axis_conv_res_valid & s_axis_conv_res_ready;
	end
	// �ӳ�2clk�ľ�����������Чָʾ
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			conv_res_in_vld_d2 <= 1'b0;
		else
			conv_res_in_vld_d2 <= # simulation_delay conv_res_in_vld_d;
	end
	// �ӳ�3clk�ľ�����������Чָʾ
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			conv_res_in_vld_d3 <= 1'b0;
		else
			conv_res_in_vld_d3 <= # simulation_delay conv_res_in_vld_d2;
	end
	// �ӳ�4clk�ľ�����������Чָʾ
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			conv_res_in_vld_d4 <= 1'b0;
		else
			conv_res_in_vld_d4 <= # simulation_delay conv_res_in_vld_d3;
	end
	
	// �ӳ�1clk�ľ�������β��־
	always @(posedge clk)
	begin
		if(s_axis_conv_res_valid & s_axis_conv_res_ready)
			conv_res_last_d <= # simulation_delay s_axis_conv_res_last;
	end
	// �ӳ�2clk�ľ�������β��־
	always @(posedge clk)
	begin
		if(conv_res_in_vld_d)
			conv_res_last_d2 <= # simulation_delay conv_res_last_d;
	end
	// �ӳ�3clk�ľ�������β��־
	always @(posedge clk)
	begin
		if(conv_res_in_vld_d2)
			conv_res_last_d3 <= # simulation_delay conv_res_last_d2;
	end
	// �ӳ�4clk�ľ�������β��־
	always @(posedge clk)
	begin
		if(conv_res_in_vld_d3)
			conv_res_last_d4 <= # simulation_delay conv_res_last_d3;
	end
	
	/*
	�˼���
	
	op_a ---> {��0���Ĵ���} ----|
	                           {+} --> {��1���Ĵ���} ----|
	  0  -----------------------|                       {*} ---> {��2���Ĵ���} ----|
	op_b ------------------------------------------------|                        {+} ---> {��3���Ĵ���}
	op_c ------------------------------------------------------> {��2���Ĵ���} ----|
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
		
		// �������� = xyz_quaz_acc+xyz_ext_frac_width
		.op_a(s_axis_conv_res_data[xyz_ext_int_width+cal_width+xyz_ext_frac_width-1:0]),
		// �������� = ab_quaz_acc
		.op_b(linear_pars_buffer_dout_a),
		// �������� = xyz_quaz_acc+xyz_ext_frac_width+ab_quaz_acc
		.op_c({{(xyz_ext_int_width+cal_width-xyz_quaz_acc){linear_pars_buffer_dout_b[cal_width-1]}}, // ���з���λ��չ
			linear_pars_buffer_dout_b, 
			{(xyz_quaz_acc+xyz_ext_frac_width){1'b0}}}),
		.op_d({(xyz_ext_int_width+cal_width+xyz_ext_frac_width){1'b0}}),
		
		.res(linear_mul_add_res),
		.pattern_detect_res()
	);
	
	/** Relu���� **/
	reg conv_res_in_vld_d5; // �ӳ�5clk�ľ�����������Чָʾ
	reg conv_res_last_d5; // �ӳ�5clk�ľ�������β��־
	wire[xyz_ext_int_width+cal_width+xyz_ext_frac_width-1:0] relu_mul_op_a_in; // �������� = xyz_quaz_acc+xyz_ext_frac_width
	wire[cal_width-1:0] relu_mul_op_b_in; // �������� = c_quaz_acc
	wire[xyz_ext_int_width+cal_width*2+xyz_ext_frac_width-1:0] relu_mul_res; // �������� = xyz_quaz_acc+xyz_ext_frac_width+c_quaz_acc
	
	assign out_fifo_wen = conv_res_in_vld_d5;
	assign out_fifo_din = relu_mul_res[(c_quaz_acc+xyz_ext_int_width+cal_width+xyz_ext_frac_width-1):c_quaz_acc];
	assign out_fifo_din_last = conv_res_last_d5;
	
	assign relu_mul_op_a_in = linear_mul_add_res_quaz;
	// (���Գ˼ӽ�� < 0) ? ϵ��c:1
	assign relu_mul_op_b_in = linear_mul_add_res_quaz[xyz_ext_int_width+cal_width+xyz_ext_frac_width-1] ? 
		act_rate_c:((c_quaz_acc == (cal_width-1)) ? 
			{1'b0, {(cal_width-1){1'b1}}}:
			({{(cal_width-1){1'b0}}, 1'b1} << c_quaz_acc));
	
	// �ӳ�5clk�ľ�����������Чָʾ
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			conv_res_in_vld_d5 <= 1'b0;
		else
			conv_res_in_vld_d5 <= # simulation_delay conv_res_in_vld_d4;
	end
	
	// �ӳ�5clk�ľ�������β��־
	always @(posedge clk)
	begin
		if(conv_res_in_vld_d4)
			conv_res_last_d5 <= # simulation_delay conv_res_last_d4;
	end
	
	// �˷���
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
