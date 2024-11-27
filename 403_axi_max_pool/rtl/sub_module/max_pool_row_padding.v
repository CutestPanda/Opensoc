`timescale 1ns / 1ps
/********************************************************************
��ģ��: ���ػ�����䴦��Ԫ

����:
������Ϊ1ʱ, ����������ͼ���п�ѡ����/�±߽����
����ϱ߽� -> ��Ч����ͼ -> ����±߽�

ע�⣺
��

Э��:
BLK CTRL
AXIS MASTER/SLAVE

����: �¼�ҫ
����: 2024/10/11
********************************************************************/


module max_pool_row_padding #(
    parameter integer feature_n_per_clk = 4, // ÿ��clk���������������(2 | 4 | 8 | 16 | ...)
	parameter integer feature_data_width = 8, // ������λ��(�����ܱ�8����, ��>0)
	parameter integer max_feature_chn_n = 128, // ��������ͼͨ����
	parameter integer max_feature_w = 128, // ������������ͼ���
	parameter en_out_reg_slice = "true", // �Ƿ�ʹ������Ĵ���Ƭ
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
	input wire clk,
	input wire rst_n,
	
	// �鼶����
	input wire blk_start,
	output wire blk_idle,
	output wire blk_done,
	
	// ����ʱ����
	input wire step_type, // ��������(1'b0 -> ����Ϊ1, 1'b1 -> ����Ϊ2)
	input wire[1:0] padding_vec, // �����������(��������Ϊ1ʱ����, {��, ��})
	input wire[15:0] feature_map_chn_n, // ����ͼͨ���� - 1
	input wire[15:0] feature_map_w, // ����ͼ��� - 1
	
	// ���������
	input wire[feature_n_per_clk*feature_data_width-1:0] s_axis_data,
	input wire[2:0] s_axis_user, // {��ǰ�������1��ͨ��, ��ǰ�������1��, ��ǰ�������1��}
	input wire[feature_n_per_clk*feature_data_width/8-1:0] s_axis_keep,
	input wire s_axis_last, // ָʾ���1��������
	input wire s_axis_valid,
	output wire s_axis_ready,
	
	// ��������
	output wire[feature_n_per_clk*feature_data_width-1:0] m_axis_data,
	output wire[2:0] m_axis_user, // {��ǰ�������1��ͨ��, ��ǰ�������1��, ��ǰ�������1��}
	output wire[feature_n_per_clk*feature_data_width/8-1:0] m_axis_keep,
	output wire m_axis_last, // ָʾ���1��������
	output wire m_axis_valid,
	input wire m_axis_ready
);
    
	// ����bit_depth�������Чλ���(��λ��-1)
    function integer clogb2(input integer bit_depth);
    begin
        for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
			bit_depth = bit_depth >> 1;
    end
    endfunction
	
	/** ���� **/
	localparam integer stream_data_width = feature_n_per_clk*feature_data_width; // ������λ��
	
	/** ����Ĵ���Ƭ **/
	// AXIS�ӻ�
	wire[stream_data_width-1:0] s_axis_reg_slice_data;
    wire[stream_data_width/8-1:0] s_axis_reg_slice_keep;
    wire[2:0] s_axis_reg_slice_user;
    wire s_axis_reg_slice_last;
    wire s_axis_reg_slice_valid;
    wire s_axis_reg_slice_ready;
	// AXIS����
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
	
	/** �鼶���� **/
	reg blk_idle_reg;
	
	assign blk_idle = blk_idle_reg;
	
	// ����������б�־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			blk_idle_reg <= 1'b1;
		else
			blk_idle_reg <= # simulation_delay blk_idle ? (~blk_start):blk_done;
	end
	
	/** ����� **/
	reg[2:0] row_padding_sts; // �����״̬(3'b001 -> ����ϱ߽�, 3'b010 -> ��Ч����ͼ, 3'b100 -> ����±߽�)
	reg[clogb2(max_feature_w/feature_n_per_clk-1):0] padding_col_id_cnt; // ������кż�����
	wire padding_last_col; // ������1��(��־)
	reg[clogb2(max_feature_chn_n-1):0] chn_id_cnt; // ͨ���ż�����
	wire last_chn; // ���1ͨ��(��־)
	wire[stream_data_width/8-1:0] padding_keep; // ���ʱ���ֽ���Ч��־
	
	assign blk_done = (~blk_idle) & 
		row_padding_sts[2] & (step_type | (~padding_vec[0]) | (s_axis_reg_slice_ready & padding_last_col)) & last_chn;
	
	assign s_axis_ready = (~blk_idle) & row_padding_sts[1] & s_axis_reg_slice_ready;
	
	assign s_axis_reg_slice_data = {stream_data_width{row_padding_sts[1]}} & s_axis_data; // row_padding_sts[1] ? s_axis_data:{stream_data_width{1'b0}}
	assign s_axis_reg_slice_keep = row_padding_sts[1] ? s_axis_keep:padding_keep;
	assign s_axis_reg_slice_user = {
		last_chn,
		(row_padding_sts[1] & s_axis_user[1] & (step_type | (~padding_vec[0]))) | row_padding_sts[2],
		((row_padding_sts[0] | row_padding_sts[2]) & padding_last_col) | (row_padding_sts[1] & s_axis_user[0])
	};
	assign s_axis_reg_slice_last = (row_padding_sts[1] & s_axis_last & (step_type | (~padding_vec[0])))
		| (row_padding_sts[2] & last_chn & padding_last_col);
	assign s_axis_reg_slice_valid = (~blk_idle)
		& ((row_padding_sts[0] & (~step_type) & padding_vec[1])
			| (row_padding_sts[1] & s_axis_valid)
			| (row_padding_sts[2] & (~step_type) & padding_vec[0]));
	
	assign padding_last_col = padding_col_id_cnt == feature_map_w[15:clogb2(feature_n_per_clk)];
	assign last_chn = chn_id_cnt == feature_map_chn_n;
	
	// ���ʱ���ֽ���Ч��־
	genvar padding_keep_i;
	generate
		for(padding_keep_i = 0;padding_keep_i < feature_n_per_clk;padding_keep_i = padding_keep_i + 1)
		begin
			assign padding_keep[(padding_keep_i+1)*feature_data_width/8-1:padding_keep_i*feature_data_width/8] = 
				{(feature_data_width/8){(~padding_last_col) | (padding_keep_i <= feature_map_w[clogb2(feature_n_per_clk-1):0])}};
		end
	endgenerate
	
	// �����״̬
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			row_padding_sts <= 3'b001;
		else if((~blk_idle)
			& ((row_padding_sts[0] & (step_type | (~padding_vec[1]) | (s_axis_reg_slice_ready & padding_last_col)))
				| (row_padding_sts[1] & (s_axis_valid & s_axis_reg_slice_ready & s_axis_user[0] & s_axis_user[1]))
				| (row_padding_sts[2] & (step_type | (~padding_vec[0]) | (s_axis_reg_slice_ready & padding_last_col)))))
			row_padding_sts <= # simulation_delay {row_padding_sts[1:0], row_padding_sts[2]};
	end
	
	// ������кż�����
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			padding_col_id_cnt <= 0;
		else if((~blk_idle)
			& ((row_padding_sts[0] & (~step_type) & padding_vec[1])
				| (row_padding_sts[2] & (~step_type) & padding_vec[0]))
			& s_axis_reg_slice_ready)
			padding_col_id_cnt <= # simulation_delay padding_last_col ? 0:(padding_col_id_cnt + 1);
	end
	
	// ͨ���ż�����
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			chn_id_cnt <= 0;
		else if(row_padding_sts[2] & (step_type | (~padding_vec[0]) | (s_axis_reg_slice_ready & padding_last_col)))
			chn_id_cnt <= # simulation_delay last_chn ? 0:(chn_id_cnt + 1);
	end
    
endmodule
