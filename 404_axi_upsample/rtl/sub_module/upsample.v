`timescale 1ns / 1ps
/********************************************************************
��ģ��: �ϲ�������Ԫ

����:
ʵ���������е��ϲ�������(upsample)
������/clk
1x1��2x2�ϲ���
2����ˮ��(�л���MEM���ӳ�1clk, ����Ĵ���1clk)
���������ʣ�(feature_n_per_clk*feature_n_per_clk/2)/clk
��������ʣ�(feature_n_per_clk*feature_n_per_clk*2)/clk

         1 1 2 2
1 2      1 1 2 2
3 4  --> 3 3 4 4
5 6      3 3 4 4
         5 5 6 6
         5 5 6 6

ע�⣺
��������ͼ�Ŀ�ȱ����ܱ�ÿ��clk���������������*2(feature_n_per_clk*2)����
��������ͼ�Ŀ��/�߶�/ͨ��������<=������������ͼ���/�߶�/ͨ����
����/�������ͼ������ ->
	[x1, y1, c1] ... [xn, y1, c1]
				  .
				  .
	[x1, yn, c1] ... [x1, yn, c1]
	
	              .
	              .
				  .
	
	[x1, y1, cn] ... [xn, y1, cn]
				  .
				  .
	[x1, yn, cn] ... [x1, yn, cn]

Э��:
AXIS MASTER/SLAVE

����: �¼�ҫ
����: 2024/09/14
********************************************************************/


module upsample #(
    parameter integer feature_n_per_clk = 8, // ÿ��clk���������������(1 | 2 | 4 | 8 | 16 | ...)
	parameter integer feature_data_width = 8, // ������λ��(�����ܱ�8����, ��>0)
	parameter integer max_feature_w = 128, // ������������ͼ���
	parameter integer max_feature_h = 128, // ������������ͼ�߶�
	parameter integer max_feature_chn_n = 512, // ������������ͼͨ����
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
	input wire clk,
	input wire rst_n,
	
	// ����ʱ����
	input wire[15:0] feature_w, // ��������ͼ��� - 1
	input wire[15:0] feature_h, // ��������ͼ�߶� - 1
	input wire[15:0] feature_chn_n, // ��������ͼͨ���� - 1
	
	// ����������
	input wire[feature_n_per_clk*feature_data_width-1:0] s_axis_data,
	input wire s_axis_valid,
	output wire s_axis_ready,
	
	// ���������
	output wire[feature_n_per_clk*feature_data_width*2-1:0] m_axis_data,
	output wire[2:0] m_axis_user, // {��ǰ�������1��ͨ��, ��ǰ�������1��, ��ǰ�������1��}
	output wire m_axis_last, // ����ͼ���1��
	output wire m_axis_valid,
	input wire m_axis_ready
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
	
	/** �л����� **/
	// �л�����MEMд�˿�
    wire line_buf_wen_a;
    wire[clogb2(max_feature_w/feature_n_per_clk-1):0] line_buf_addr_a;
    wire[feature_n_per_clk*feature_data_width-1:0] line_buf_din_a;
    // �л�����MEM���˿�
    wire line_buf_ren_b;
    wire[clogb2(max_feature_w/feature_n_per_clk-1):0] line_buf_addr_b;
    wire[feature_n_per_clk*feature_data_width-1:0] line_buf_dout_b;
	
	// �л�����MEM
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(feature_n_per_clk*feature_data_width),
		.mem_depth(max_feature_w/feature_n_per_clk),
		.INIT_FILE("no_init"),
		.simulation_delay(simulation_delay)
	)line_buf_mem(
		.clk(clk),
		
		.wen_a(line_buf_wen_a),
		.addr_a(line_buf_addr_a),
		.din_a(line_buf_din_a),
		
		.ren_b(line_buf_ren_b),
		.addr_b(line_buf_addr_b),
		.dout_b(line_buf_dout_b)
	);
	
	/** ��ˮ�߿��� **/
	wire valid_stage0;
	wire ready_stage0;
	reg valid_stage1;
	wire ready_stage1;
	reg valid_stage2;
	wire ready_stage2;
	
	// ����������valid_stage0 & ((~valid_stage1) | ready_stage1)
	assign ready_stage0 = (~valid_stage1) | ready_stage1;
	
	// ����������valid_stage1 & ((~valid_stage2) | ready_stage2)
	assign ready_stage1 = (~valid_stage2) | ready_stage2;
	
	// ����������valid_stage2 & m_axis_ready
	assign m_axis_valid = valid_stage2;
	assign ready_stage2 = m_axis_ready;
	
    /** �ϲ���λ�ü����� **/
	reg is_at_row_stuff_stage; // �Ƿ��������׶�(��־)
	reg[1:0] row_stuff_pos; // �����λ�ñ�־({��ǰ�������1��ͨ��, ��ǰ�������1��})
	reg[clogb2(max_feature_w/feature_n_per_clk-1):0] upsample_x_cnt; // �ϲ���xλ�ü�����
	wire upsample_x_cnt_at_last; // �ϲ���xλ�ü������ִ�ĩβ(��־)
	reg[clogb2(max_feature_h-1):0] in_ft_map_y_cnt; // ��������ͼyλ�ü�����
	wire in_ft_map_y_cnt_at_last; // ��������ͼyλ�ü������ִ�ĩβ(��־)
	reg[clogb2(max_feature_chn_n-1):0] in_ft_map_chn_id_cnt; // ��������ͼͨ���ż�����
	wire in_ft_map_chn_id_cnt_at_last; // ��������ͼͨ���ż������ִ�ĩβ(��־)
	
	// ����������s_axis_valid & (~is_at_row_stuff_stage) & ready_stage0
	assign s_axis_ready = (~is_at_row_stuff_stage) & ready_stage0;
	
	assign line_buf_wen_a = s_axis_valid & (~is_at_row_stuff_stage) & ((~valid_stage1) | ready_stage1);
	assign line_buf_addr_a = upsample_x_cnt;
	assign line_buf_din_a = s_axis_data;
	
	assign line_buf_ren_b = is_at_row_stuff_stage & ((~valid_stage1) | ready_stage1);
	assign line_buf_addr_b = upsample_x_cnt;
	
	// is_at_row_stuff_stage ? 1'b1:s_axis_valid
	assign valid_stage0 = is_at_row_stuff_stage | s_axis_valid;
	
	assign upsample_x_cnt_at_last = upsample_x_cnt == 
		feature_w[clogb2(max_feature_w/feature_n_per_clk-1)+clogb2(feature_n_per_clk):clogb2(feature_n_per_clk)];
	assign in_ft_map_y_cnt_at_last = in_ft_map_y_cnt == feature_h[clogb2(max_feature_h-1):0];
	assign in_ft_map_chn_id_cnt_at_last = in_ft_map_chn_id_cnt == feature_chn_n[clogb2(max_feature_chn_n-1):0];
	
	// �Ƿ��������׶�(��־)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			is_at_row_stuff_stage <= 1'b0;
		else if(valid_stage0 & ready_stage0 & upsample_x_cnt_at_last)
			is_at_row_stuff_stage <= # simulation_delay ~is_at_row_stuff_stage;
	end
	
	// �����λ�ñ�־
	always @(posedge clk)
	begin
		if(s_axis_valid & s_axis_ready & upsample_x_cnt_at_last)
			row_stuff_pos <= # simulation_delay {in_ft_map_chn_id_cnt_at_last, in_ft_map_y_cnt_at_last};
	end
	
	// �ϲ���xλ�ü�����
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			upsample_x_cnt <= 0;
		else if(valid_stage0 & ready_stage0)
			// upsample_x_cnt_at_last ? 0:(upsample_x_cnt + 1)
			upsample_x_cnt <= # simulation_delay 
				{(clogb2(max_feature_w/feature_n_per_clk-1)+1){~upsample_x_cnt_at_last}} & (upsample_x_cnt + 1);
	end
	// ��������ͼyλ�ü�����
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			in_ft_map_y_cnt <= 0;
		else if(s_axis_valid & s_axis_ready & upsample_x_cnt_at_last)
			// in_ft_map_y_cnt_at_last ? 0:(in_ft_map_y_cnt + 1)
			in_ft_map_y_cnt <= # simulation_delay 
				{(clogb2(max_feature_h-1)+1){~in_ft_map_y_cnt_at_last}} & (in_ft_map_y_cnt + 1);
	end
	// ��������ͼͨ���ż�����
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			in_ft_map_chn_id_cnt <= 0;
		else if(s_axis_valid & s_axis_ready & upsample_x_cnt_at_last & in_ft_map_y_cnt_at_last)
			// in_ft_map_chn_id_cnt_at_last ? 0:(in_ft_map_chn_id_cnt + 1)
			in_ft_map_chn_id_cnt <= # simulation_delay 
				{(clogb2(max_feature_chn_n-1)+1){~in_ft_map_chn_id_cnt_at_last}} & (in_ft_map_chn_id_cnt + 1);
	end
	
	/** ����� **/
	reg[feature_n_per_clk*feature_data_width-1:0] features_d; // �ӳ�1clk������������
	reg is_at_row_stuff_stage_d; // �ӳ�1clk���Ƿ��������׶�(��־)
	reg[feature_n_per_clk*feature_data_width-1:0] col_stuff_feature_d; // �ӳ�1clk�������������
	
	genvar col_stuff_i;
	generate
		for(col_stuff_i = 0;col_stuff_i < feature_n_per_clk;col_stuff_i = col_stuff_i + 1)
		begin
			assign m_axis_data[(col_stuff_i+1)*feature_data_width*2-1:col_stuff_i*feature_data_width*2] = 
				{2{col_stuff_feature_d[(col_stuff_i+1)*feature_data_width-1:col_stuff_i*feature_data_width]}};
		end
	endgenerate
	
	// ��ˮ�ߵ�1��������Ч
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			valid_stage1 <= 1'b0;
		else if((~valid_stage1) | ready_stage1)
			valid_stage1 <= # simulation_delay valid_stage0;
	end
	
	// �ӳ�1clk������������
	always @(posedge clk)
	begin
		if(valid_stage0 & ready_stage0)
			features_d <= # simulation_delay s_axis_data;
	end
	
	// �ӳ�1clk���Ƿ��������׶�(��־)
	always @(posedge clk)
	begin
		if(valid_stage0 & ready_stage0)
			is_at_row_stuff_stage_d <= # simulation_delay is_at_row_stuff_stage;
	end
	
	// ��ˮ�ߵ�2��������Ч
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			valid_stage2 <= 1'b0;
		else if(ready_stage1)
			valid_stage2 <= # simulation_delay valid_stage1;
	end
	
	// �ӳ�1clk�������������
	always @(posedge clk)
	begin
		if(valid_stage1 & ready_stage1)
			col_stuff_feature_d <= # simulation_delay is_at_row_stuff_stage_d ? line_buf_dout_b:features_d;
	end
	
	/** ������λ�ñ�־ **/
	reg feature_col_last_d; // �ӳ�1clk�����1�б�־
	reg feature_row_last_d; // �ӳ�1clk�����1�б�־
	reg feature_chn_last_d; // �ӳ�1clk�����1ͨ����־
	reg feature_col_last_d2; // �ӳ�2clk�����1�б�־
	reg feature_row_last_d2; // �ӳ�2clk�����1�б�־
	reg feature_chn_last_d2; // �ӳ�2clk�����1ͨ����־
	reg feature_last_d2; // �ӳ�2clk�����1���������־
	
	assign m_axis_user = {feature_chn_last_d2, feature_row_last_d2, feature_col_last_d2};
	assign m_axis_last = feature_last_d2;
	
	// �ӳ�1clk�����1�б�־
	always @(posedge clk)
	begin
		if(valid_stage0 & ready_stage0)
			feature_col_last_d <= # simulation_delay upsample_x_cnt_at_last;
	end
	// �ӳ�1clk�����1�б�־
	always @(posedge clk)
	begin
		if(valid_stage0 & ready_stage0)
			feature_row_last_d <= # simulation_delay is_at_row_stuff_stage & row_stuff_pos[0];
	end
	// �ӳ�1clk�����1ͨ����־
	always @(posedge clk)
	begin
		if(valid_stage0 & ready_stage0)
			feature_chn_last_d <= # simulation_delay is_at_row_stuff_stage ? row_stuff_pos[1]:in_ft_map_chn_id_cnt_at_last;
	end
	
	// �ӳ�2clk�����1�б�־
	always @(posedge clk)
	begin
		if(valid_stage1 & ready_stage1)
			feature_col_last_d2 <= # simulation_delay feature_col_last_d;
	end
	// �ӳ�2clk�����1�б�־
	always @(posedge clk)
	begin
		if(valid_stage1 & ready_stage1)
			feature_row_last_d2 <= # simulation_delay feature_row_last_d;
	end
	// �ӳ�2clk�����1ͨ����־
	always @(posedge clk)
	begin
		if(valid_stage1 & ready_stage1)
			feature_chn_last_d2 <= # simulation_delay feature_chn_last_d;
	end
	// �ӳ�2clk�����1���������־
	always @(posedge clk)
	begin
		if(valid_stage1 & ready_stage1)
			feature_last_d2 <= # simulation_delay feature_chn_last_d & feature_row_last_d & feature_col_last_d;
	end
    
endmodule
