`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXIS���Բ���������

����:
��AXIS�ӻ��������Բ�����, д�뻺����
ͨ��MEM���˿ڻ�ȡ���Բ���

��ʱ�� = 2clk

���Բ���(A, B): AX + B

ע�⣺
��

Э��:
AXIS SLAVE
MEM READ

����: �¼�ҫ
����: 2024/10/21
********************************************************************/


module axis_linear_params_buffer #(
	parameter integer kernal_param_data_width = 16, // ����˲���λ��(8 | 16 | 32 | 64)
	parameter integer max_kernal_n = 512, // ���ľ���˸���
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
	input wire clk,
	input wire rst_n,
	
	// ��λ���Բ���������
	input wire rst_linear_pars_buf,
	// ���Բ���������������ɱ�־
	output wire linear_pars_buf_load_completed,
	
	// �������Բ�����(AXIS�ӻ�)
	input wire[63:0] s_axis_linear_pars_data,
	input wire[7:0] s_axis_linear_pars_keep,
	input wire s_axis_linear_pars_last, // ��ʾ���1�����Բ���
	input wire[1:0] s_axis_linear_pars_user, // {���Բ����Ƿ���Ч, ���Բ�������(1'b0 -> A, 1'b1 -> B)}
	input wire s_axis_linear_pars_valid,
	output wire s_axis_linear_pars_ready,
	
	// ���Բ�����ȡ(MEM��)
	input wire linear_pars_buffer_ren_s0,
	input wire linear_pars_buffer_ren_s1,
	input wire[15:0] linear_pars_buffer_raddr,
	output wire[kernal_param_data_width-1:0] linear_pars_buffer_dout_a,
	output wire[kernal_param_data_width-1:0] linear_pars_buffer_dout_b
);
    
	// ����bit_depth�������Чλ���(��λ��-1)
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
	
	/** �������Բ����� **/
	wire[kernal_param_data_width-1:0] linear_pars[0:64/kernal_param_data_width-1]; // ���Բ���
	wire[64/kernal_param_data_width-1:0] linear_pars_vld; // ���Բ�����Ч��־
	
	genvar linear_pars_i;
	generate
		for(linear_pars_i = 0;linear_pars_i < 64/kernal_param_data_width;linear_pars_i = linear_pars_i + 1)
		begin
			assign linear_pars[linear_pars_i] = s_axis_linear_pars_data[(linear_pars_i+1)*kernal_param_data_width-1:
				linear_pars_i*kernal_param_data_width];
			assign linear_pars_vld[linear_pars_i] = s_axis_linear_pars_keep[linear_pars_i*kernal_param_data_width/8];
		end
	endgenerate
	
	/** ������д�˿� **/
	wire buffer_wen_a; // ���Բ���A������дʹ��
	wire buffer_wen_b; // ���Բ���B������дʹ��
	reg[clogb2(max_kernal_n-1):0] buffer_waddr; // ÿ��д��ַ��Ӧ1�����Բ���
	wire[kernal_param_data_width-1:0] buffer_din_a; // ���Բ���A������д����
	wire[kernal_param_data_width-1:0] buffer_din_b; // ���Բ���B������д����
	reg[64/kernal_param_data_width-1:0] linear_pars_sel_onehot; // ���Բ���ѡ��(������)
	reg[clogb2(64/kernal_param_data_width-1):0] linear_pars_sel_bin; // ���Բ���ѡ��(��������)
	wire[kernal_param_data_width-1:0] linear_pars_buffer_mem_dout_a; // ����MEM���Բ���A������
	wire[kernal_param_data_width-1:0] linear_pars_buffer_mem_dout_b; // ����MEM���Բ���B������
	
	// ��������: s_axis_linear_pars_valid & linear_pars_sel_onehot[64/kernal_param_data_width-1]
	assign s_axis_linear_pars_ready = linear_pars_sel_onehot[64/kernal_param_data_width-1];
	
	assign buffer_wen_a = s_axis_linear_pars_valid & (~s_axis_linear_pars_user[0]) & 
		(|(linear_pars_vld & linear_pars_sel_onehot));
	assign buffer_wen_b = s_axis_linear_pars_valid & s_axis_linear_pars_user[0] & 
		(|(linear_pars_vld & linear_pars_sel_onehot));
	assign buffer_din_a = linear_pars[linear_pars_sel_bin];
	assign buffer_din_b = linear_pars[linear_pars_sel_bin];
	
	// ���Բ���������д��ַ
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_waddr <= 0;
		else if(s_axis_linear_pars_valid)
			// (s_axis_linear_pars_last & linear_pars_sel_onehot[64/kernal_param_data_width-1]) ? 0:(buffer_waddr + 1)
			buffer_waddr <= # simulation_delay 
				{(clogb2(max_kernal_n-1)+1){~(s_axis_linear_pars_last &
					linear_pars_sel_onehot[64/kernal_param_data_width-1])}} & (buffer_waddr + 1);
	end
	
	// ���Բ���ѡ��(������)
	generate
		if(kernal_param_data_width == 64)
		begin
			always @(*)
				linear_pars_sel_onehot = 1'b1;
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					linear_pars_sel_onehot <= {{(64/kernal_param_data_width-1){1'b0}}, 1'b1};
				else if(s_axis_linear_pars_valid)
					linear_pars_sel_onehot <= # simulation_delay {linear_pars_sel_onehot[64/kernal_param_data_width-2:0], 
						linear_pars_sel_onehot[64/kernal_param_data_width-1]};
			end
		end
	endgenerate
	// ���Բ���ѡ��(��������)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			linear_pars_sel_bin <= 0;
		else if(s_axis_linear_pars_valid)
			// linear_pars_sel_onehot[64/kernal_param_data_width-1] ? 0:(linear_pars_sel_bin + 1)
			linear_pars_sel_bin <= # simulation_delay 
				{(clogb2(64/kernal_param_data_width-1)+1){~linear_pars_sel_onehot[64/kernal_param_data_width-1]}} & 
				(linear_pars_sel_bin + 1);
	end
	
	// ���Բ���������MEM
	linear_params_buffer #(
		.kernal_param_data_width(kernal_param_data_width),
		.max_kernal_n(max_kernal_n),
		.simulation_delay(simulation_delay)
	)linear_params_buffer_u(
		.clk(clk),
		
		.buffer_wen_a(buffer_wen_a),
		.buffer_wen_b(buffer_wen_b),
		.buffer_waddr({{(15-clogb2(max_kernal_n-1)){1'b0}}, buffer_waddr}),
		.buffer_din_a(buffer_din_a),
		.buffer_din_b(buffer_din_b),
		
		.buffer_ren(linear_pars_buffer_ren_s0),
		.buffer_raddr(linear_pars_buffer_raddr),
		.buffer_dout_a(linear_pars_buffer_mem_dout_a),
		.buffer_dout_b(linear_pars_buffer_mem_dout_b)
	);
	
	/** ���Բ�����Ч���� **/
	reg linear_pars_a_vld; // ���Բ���A��Ч��־
	reg linear_pars_b_vld; // ���Բ���B��Ч��־
	reg linear_pars_a_vld_d; // ���뵽����MEM���Բ���A�����ݵ���Ч��־
	reg linear_pars_b_vld_d; // ���뵽����MEM���Բ���B�����ݵ���Ч��־
	reg[kernal_param_data_width-1:0] linear_pars_buffer_dout_a_regs; // ���Բ���A����������Ĵ���
	reg[kernal_param_data_width-1:0] linear_pars_buffer_dout_b_regs; // ���Բ���B����������Ĵ���
	
	assign linear_pars_buffer_dout_a = linear_pars_buffer_dout_a_regs;
	assign linear_pars_buffer_dout_b = linear_pars_buffer_dout_b_regs;
	
	// ���Բ���A��Ч��־
	always @(posedge clk)
	begin
		if(s_axis_linear_pars_valid & s_axis_linear_pars_ready & s_axis_linear_pars_last & (~s_axis_linear_pars_user[0]))
			linear_pars_a_vld <= #simulation_delay s_axis_linear_pars_user[1];
	end
	// ���Բ���B��Ч��־
	always @(posedge clk)
	begin
		if(s_axis_linear_pars_valid & s_axis_linear_pars_ready & s_axis_linear_pars_last & s_axis_linear_pars_user[0])
			linear_pars_b_vld <= #simulation_delay s_axis_linear_pars_user[1];
	end
	
	// ���뵽����MEM���Բ���A�����ݵ���Ч��־
	always @(posedge clk)
	begin
		if(linear_pars_buffer_ren_s0)
			linear_pars_a_vld_d <= # simulation_delay linear_pars_a_vld;
	end
	// ���뵽����MEM���Բ���B�����ݵ���Ч��־
	always @(posedge clk)
	begin
		if(linear_pars_buffer_ren_s0)
			linear_pars_b_vld_d <= # simulation_delay linear_pars_b_vld;
	end
	
	// ���Բ���A����������Ĵ���
	always @(posedge clk)
	begin
		if(linear_pars_buffer_ren_s1)
			// linear_pars_a_vld_d ? {kernal_param_data_width{1'b0}}:linear_pars_buffer_mem_dout_a
			linear_pars_buffer_dout_a_regs <= # simulation_delay {kernal_param_data_width{linear_pars_a_vld_d}} & 
				linear_pars_buffer_mem_dout_a;
	end
	// ���Բ���B����������Ĵ���
	always @(posedge clk)
	begin
		if(linear_pars_buffer_ren_s1)
			// linear_pars_b_vld_d ? {kernal_param_data_width{1'b0}}:linear_pars_buffer_mem_dout_b
			linear_pars_buffer_dout_b_regs <= # simulation_delay {kernal_param_data_width{linear_pars_b_vld_d}} & 
				linear_pars_buffer_mem_dout_b;
	end
	
	/** ���Բ�������������״̬ **/
	reg linear_pars_a_loaded; // ���Բ���A������ɱ�־
	reg linear_pars_b_loaded; // ���Բ���B������ɱ�־
	
	assign linear_pars_buf_load_completed = linear_pars_a_loaded & linear_pars_b_loaded;
	
	// ���Բ���A������ɱ�־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			linear_pars_a_loaded <= 1'b0;
		else if(rst_linear_pars_buf | 
			(s_axis_linear_pars_valid & s_axis_linear_pars_ready & s_axis_linear_pars_last & (~s_axis_linear_pars_user[0])))
			linear_pars_a_loaded <= ~rst_linear_pars_buf;
	end
	// ���Բ���B������ɱ�־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			linear_pars_b_loaded <= 1'b0;
		else if(rst_linear_pars_buf | 
			(s_axis_linear_pars_valid & s_axis_linear_pars_ready & s_axis_linear_pars_last & s_axis_linear_pars_user[0]))
			linear_pars_b_loaded <= ~rst_linear_pars_buf;
	end
	
endmodule
