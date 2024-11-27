`timescale 1ns / 1ps
/********************************************************************
��ģ��: ���ػ�����Ԫ(������/clk)

����:
ʵ���������е����ػ�����(max pool)
������/clk
������ģʽ�̶�Ϊ����
�ػ����ڴ�СΪ2x2
֧�ֲ���Ϊ1��2
֧�ֵ�����Ϊ1ʱ����/��/��/�����

��������ȡ��(����Ĵ�����1clk, [AXIS�Ĵ���Ƭ1clk]) -> 
	����䴦��Ԫ([AXIS�Ĵ���Ƭ1clk]) -> 
	2����ˮ��(�л���MEM���ӳ�1clk, ROI�Ĵ���1clk) -> 
	2����ˮ��(���ػ�����2clk) -> 
	�������������Ԫ([AXIS�Ĵ���Ƭ1clk]) -> 
	������������ռ���Ԫ(�Ĵ���������1clk) -> 
	[����Ĵ���Ƭ1clk]

�����ٶ� = 1������/clk

����       ����     ���
  1      1 1 2 2  [1  1  2  2  2]
         3 4 3 1  [3] 4  4  3 [2]
         1 1 0 0  [3] 4  4  3 [1]
         7 8 0 1  [7] 8  8  1 [1]
		          [7  8  8  1  1]
  2      1 1 2 2
         3 4 3 1      4     3
         1 1 0 0
         7 8 0 1      8     1

ע�⣺
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
BLK CTRL
AXIS MASTER/SLAVE

����: �¼�ҫ
����: 2024/10/11
********************************************************************/


module max_pool_mul_pix #(
    parameter integer feature_n_per_clk = 4, // ÿ��clk���������������(2 | 4 | 8 | 16 | ...)
	parameter integer feature_data_width = 8, // ������λ��(�����ܱ�8����, ��>0)
	parameter integer max_feature_chn_n = 128, // ��������ͼͨ����
	parameter integer max_feature_w = 128, // ������������ͼ���
	parameter integer max_feature_h = 128, // ������������ͼ�߶�
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
	input wire[3:0] padding_vec, // �����������(��������Ϊ1ʱ����, {��, ��, ��, ��})
	input wire[15:0] feature_map_chn_n, // ����ͼͨ���� - 1
	input wire[15:0] feature_map_w, // ����ͼ��� - 1
	input wire[15:0] feature_map_h, // ����ͼ�߶� - 1
	
	// ����������ͼ����������
	input wire[feature_n_per_clk*feature_data_width-1:0] s_axis_data,
	input wire[feature_n_per_clk*feature_data_width/8-1:0] s_axis_keep,
	input wire s_axis_last, // ָʾ����ͼ����
	input wire s_axis_valid,
	output wire s_axis_ready,
	
	// ���������ͼ���������
	output wire[feature_n_per_clk*feature_data_width-1:0] m_axis_data,
	output wire[feature_n_per_clk*feature_data_width/8-1:0] m_axis_keep,
	output wire m_axis_last, // ����ͼ���1��
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
	
	/** �ڲ����� **/
	localparam en_reg_slice_at_feature_row_realign = "false"; // �Ƿ�����������ȡ�����������AXIS�Ĵ���Ƭ
	localparam en_reg_slice_at_row_padding = "false"; // �Ƿ�������䴦��Ԫ���������AXIS�Ĵ���Ƭ
	localparam en_reg_slice_at_item_formator = "true"; // �Ƿ����������������Ԫ���������AXIS�Ĵ���Ƭ
	
	/** ���� **/
	localparam integer in_stream_data_width = feature_n_per_clk*feature_data_width; // ����������λ��
	localparam integer out_stream_data_width = (feature_n_per_clk+1)*feature_data_width; // ���������λ��
	
	/** ����Ĵ���Ƭ **/
	// AXIS�ӻ�
	wire[feature_n_per_clk*feature_data_width-1:0] s_axis_reg_slice_data;
    wire[feature_n_per_clk*feature_data_width/8-1:0] s_axis_reg_slice_keep;
    wire s_axis_reg_slice_last;
    wire s_axis_reg_slice_valid;
    wire s_axis_reg_slice_ready;
	// AXIS����
	wire[feature_n_per_clk*feature_data_width-1:0] m_axis_reg_slice_data;
    wire[feature_n_per_clk*feature_data_width/8-1:0] m_axis_reg_slice_keep;
    wire m_axis_reg_slice_last;
    wire m_axis_reg_slice_valid;
    wire m_axis_reg_slice_ready;
	
	assign m_axis_data = m_axis_reg_slice_data;
	assign m_axis_keep = m_axis_reg_slice_keep;
	assign m_axis_last = m_axis_reg_slice_last;
	assign m_axis_valid = m_axis_reg_slice_valid;
	assign m_axis_reg_slice_ready = m_axis_ready;
	
	axis_reg_slice #(
		.data_width(feature_n_per_clk*feature_data_width),
		.user_width(1),
		.forward_registered(en_out_reg_slice),
		.back_registered(en_out_reg_slice),
		.en_ready("true"),
		.simulation_delay(simulation_delay)
	)out_reg_slice(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axis_data(s_axis_reg_slice_data),
		.s_axis_keep(s_axis_reg_slice_keep),
		.s_axis_user(),
		.s_axis_last(s_axis_reg_slice_last),
		.s_axis_valid(s_axis_reg_slice_valid),
		.s_axis_ready(s_axis_reg_slice_ready),
		
		.m_axis_data(m_axis_reg_slice_data),
		.m_axis_keep(m_axis_reg_slice_keep),
		.m_axis_user(),
		.m_axis_last(m_axis_reg_slice_last),
		.m_axis_valid(m_axis_reg_slice_valid),
		.m_axis_ready(m_axis_reg_slice_ready)
	);
	
	/** �鼶���� **/
	wire row_padding_start;
	wire row_padding_idle;
	wire row_padding_done;
	wire max_pool_start;
	reg max_pool_idle;
	wire max_pool_done;
	
	assign blk_idle = max_pool_idle;
	assign blk_done = max_pool_done;
	
	assign row_padding_start = blk_start;
	assign max_pool_start = blk_start;
	assign max_pool_done = m_axis_valid & m_axis_ready & m_axis_last;
	
	// ���ػ���Ԫ���б�־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			max_pool_idle <= 1'b1;
		else
			max_pool_idle <= # simulation_delay max_pool_idle ? (~max_pool_start):max_pool_done;
	end
	
	/** ��������ȡ�� **/
	// ���������
	wire[in_stream_data_width-1:0] m_axis_ft_gp_data;
	wire[2:0] m_axis_ft_gp_user; // {��ǰ�������1��ͨ��, ��ǰ�������1��, ��ǰ�������1��}
	wire[in_stream_data_width/8-1:0] m_axis_ft_gp_keep;
	wire m_axis_ft_gp_last; // ָʾ���1��������
	wire m_axis_ft_gp_valid;
	wire m_axis_ft_gp_ready;
	
	feature_row_realign #(
		.feature_n_per_clk(feature_n_per_clk),
		.feature_data_width(feature_data_width),
		.max_feature_map_chn_n(max_feature_chn_n),
		.max_feature_map_w(max_feature_w),
		.max_feature_map_h(max_feature_h),
		.en_out_reg_slice(en_reg_slice_at_feature_row_realign),
		.simulation_delay(simulation_delay)
	)feature_row_realign_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.in_stream_en(1'b1),
		
		.feature_map_chn_n(feature_map_chn_n),
		.feature_map_w(feature_map_w),
		.feature_map_h(feature_map_h),
		
		.s_axis_data(s_axis_data),
		.s_axis_keep(s_axis_keep),
		.s_axis_last(s_axis_last),
		.s_axis_valid(s_axis_valid),
		.s_axis_ready(s_axis_ready),
		
		.m_axis_data(m_axis_ft_gp_data),
		.m_axis_user(m_axis_ft_gp_user),
		.m_axis_keep(m_axis_ft_gp_keep),
		.m_axis_last(m_axis_ft_gp_last),
		.m_axis_valid(m_axis_ft_gp_valid),
		.m_axis_ready(m_axis_ft_gp_ready)
	);
	
	/** ����䴦��Ԫ **/
	// ���������
	wire[in_stream_data_width-1:0] s_axis_row_padding_data;
	wire[2:0] s_axis_row_padding_user; // {��ǰ�������1��ͨ��, ��ǰ�������1��, ��ǰ�������1��}
	wire[in_stream_data_width/8-1:0] s_axis_row_padding_keep;
	wire s_axis_row_padding_last; // ָʾ���1��������
	wire s_axis_row_padding_valid;
	wire s_axis_row_padding_ready;
	// ��������
	wire[in_stream_data_width-1:0] m_axis_row_padding_data;
	wire[2:0] m_axis_row_padding_user; // {��ǰ�������1��ͨ��, ��ǰ�������1��, ��ǰ�������1��}
	wire[in_stream_data_width/8-1:0] m_axis_row_padding_keep;
	wire m_axis_row_padding_last; // ָʾ���1��������
	wire m_axis_row_padding_valid;
	wire m_axis_row_padding_ready;
	
	assign s_axis_row_padding_data = m_axis_ft_gp_data;
	assign s_axis_row_padding_user = m_axis_ft_gp_user;
	assign s_axis_row_padding_keep = m_axis_ft_gp_keep;
	assign s_axis_row_padding_last = m_axis_ft_gp_last;
	assign s_axis_row_padding_valid = m_axis_ft_gp_valid;
	assign m_axis_ft_gp_ready = s_axis_row_padding_ready;
	
	max_pool_row_padding #(
		.feature_n_per_clk(feature_n_per_clk),
		.feature_data_width(feature_data_width),
		.max_feature_chn_n(max_feature_chn_n),
		.max_feature_w(max_feature_w),
		.en_out_reg_slice(en_reg_slice_at_row_padding),
		.simulation_delay(simulation_delay)
	)max_pool_row_padding_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.blk_start(row_padding_start),
		.blk_idle(row_padding_idle),
		.blk_done(row_padding_done),
		
		.step_type(step_type),
		.padding_vec(padding_vec[3:2]),
		.feature_map_chn_n(feature_map_chn_n),
		.feature_map_w(feature_map_w),
		
		.s_axis_data(s_axis_row_padding_data),
		.s_axis_user(s_axis_row_padding_user),
		.s_axis_keep(s_axis_row_padding_keep),
		.s_axis_last(s_axis_row_padding_last),
		.s_axis_valid(s_axis_row_padding_valid),
		.s_axis_ready(s_axis_row_padding_ready),
		
		.m_axis_data(m_axis_row_padding_data),
		.m_axis_user(m_axis_row_padding_user),
		.m_axis_keep(m_axis_row_padding_keep),
		.m_axis_last(m_axis_row_padding_last),
		.m_axis_valid(m_axis_row_padding_valid),
		.m_axis_ready(m_axis_row_padding_ready)
	);
	
	/** �л����� **/
	// ����������
	wire[feature_n_per_clk-1:0] feature_in_keep; // ����������
	wire[in_stream_data_width-1:0] feature_in_data_mask; // ������������
	// �л���MEMд�˿�
	wire line_buf_mem_wen_a;
	reg[clogb2(max_feature_w/feature_n_per_clk-1):0] line_buf_mem_addr;
	wire[in_stream_data_width-1:0] line_buf_mem_din_a; // ����������
	// �л���MEM���˿�
	wire line_buf_mem_ren_b;
	wire[in_stream_data_width-1:0] line_buf_mem_dout_b; // ����������
	
	genvar feature_in_keep_i;
	generate
		for(feature_in_keep_i = 0;feature_in_keep_i < feature_n_per_clk;
			feature_in_keep_i = feature_in_keep_i + 1)
		begin
			assign feature_in_keep[feature_in_keep_i] = 
				m_axis_row_padding_keep[feature_in_keep_i*feature_data_width/8];
			
			assign feature_in_data_mask[(feature_in_keep_i+1)*feature_data_width-1:feature_in_keep_i*feature_data_width] = 
				{feature_data_width{feature_in_keep[feature_in_keep_i]}};
		end
	endgenerate
	
	assign line_buf_mem_wen_a = m_axis_row_padding_valid & m_axis_row_padding_ready;
	assign line_buf_mem_din_a = m_axis_row_padding_data & feature_in_data_mask;
	
	assign line_buf_mem_ren_b = m_axis_row_padding_valid & m_axis_row_padding_ready;
	
	// �л���MEM��д��ַ
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			line_buf_mem_addr <= 0;
		else if(m_axis_row_padding_valid & m_axis_row_padding_ready)
			line_buf_mem_addr <= # simulation_delay m_axis_row_padding_user[0] ? 0:(line_buf_mem_addr + 1);
	end
	
	// �л���MEM
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(in_stream_data_width),
		.mem_depth(max_feature_w/feature_n_per_clk),
		.INIT_FILE("no_init"),
		.simulation_delay(simulation_delay)
	)line_buf_mem_u(
		.clk(clk),
		
		.wen_a(line_buf_mem_wen_a),
		.addr_a(line_buf_mem_addr),
		.din_a(line_buf_mem_din_a),
		
		.ren_b(line_buf_mem_ren_b),
		.addr_b(line_buf_mem_addr),
		.dout_b(line_buf_mem_dout_b)
	);
	
	/** �ػ�λ�ü����� **/
	wire[clogb2(max_feature_w-1):0] pool_x; // �ػ�x����(not used!)
	reg pool_x_eq0; // �ػ�x���� == 0(��־)
	reg[clogb2(max_feature_h+1):0] pool_y; // �ػ�y����
	reg pool_y_eq0; // �ػ�y���� == 0(��־)
	
	// feature_n_per_clkΪ2^x, �������Ƽ���
	assign pool_x = line_buf_mem_addr * feature_n_per_clk;
	
	// �ػ�x���� == 0(��־)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			pool_x_eq0 <= 1'b1;
		else if(m_axis_row_padding_valid & m_axis_row_padding_ready)
			pool_x_eq0 <= # simulation_delay m_axis_row_padding_user[0];
	end
	
	// �ػ�y����
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			pool_y <= 0;
		else if(m_axis_row_padding_valid & m_axis_row_padding_ready & m_axis_row_padding_user[0])
			pool_y <= # simulation_delay m_axis_row_padding_user[1] ? 0:(pool_y + 1);
	end
	
	// �ػ�y���� == 0(��־)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			pool_y_eq0 <= 1'b1;
		else if(m_axis_row_padding_valid & m_axis_row_padding_ready & m_axis_row_padding_user[0])
			pool_y_eq0 <= # simulation_delay m_axis_row_padding_user[1];
	end
	
	/** �ػ�ROI������ˮ�߿��� **/
	reg feature_in_vld_d; // �ӳ�1clk��������������Чָʾ
	wire pool_roi_gen_stage1_ready;
	reg pool_roi_vld; // �ػ�ROI��Чָʾ
	wire pool_roi_gen_stage2_ready;
	
	assign m_axis_row_padding_ready = (~feature_in_vld_d) | pool_roi_gen_stage1_ready;
	assign pool_roi_gen_stage1_ready = (~pool_roi_vld) | pool_roi_gen_stage2_ready;
	
	// �ӳ�1clk��������������Чָʾ
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			feature_in_vld_d <= 1'b0;
		else if(m_axis_row_padding_ready)
			feature_in_vld_d <= # simulation_delay m_axis_row_padding_valid;
	end
	
	/**
	�ػ�ROI
	
	���� -> 
		[pool_left_buf_r1] pool_roi_r1
		[pool_left_buf_r2] pool_roi_r2
	
	������ʹ������ -> 
		pool_roi_keep
	**/
	reg[in_stream_data_width-1:0] feature_in_d; // �ӳ�1clk������������
	reg[feature_n_per_clk-1:0] feature_in_keep_d; // �ӳ�1clk������������ʹ������
	reg pool_x_eq0_d; // �ӳ�1clk�ĳػ�x���� == 0(��־)
	reg[clogb2(max_feature_h-1):0] pool_y_d; // �ӳ�1clk�ĳػ�y����
	reg pool_y_eq0_d; // �ӳ�1clk�ĳػ�y���� == 0(��־)
	reg[3:0] pool_roi_user_last_d; // �ӳ�1clk�������������λ�ñ�־({1ast(1bit), user(3bit)})
	reg pool_x_eq0_d2; // �ӳ�2clk�ĳػ�x���� == 0(��־)
	reg[in_stream_data_width-1:0] pool_roi_r1; // �ػ�ROI��1��
	reg[in_stream_data_width-1:0] pool_roi_r2; // �ػ�ROI��2��
	reg[feature_n_per_clk-1:0] pool_roi_keep; // �ػ�ROI������ʹ������
	reg[feature_data_width-1:0] pool_left_buf_r1; // �ػ�ROI��1��ʣ�໺��
	reg[feature_data_width-1:0] pool_left_buf_r2; // �ػ�ROI��2��ʣ�໺��
	reg[3:0] pool_roi_user_last_d2; // �ӳ�2clk�������������λ�ñ�־({1ast(1bit), user(3bit)})
	
	// �ػ�ROI��Чָʾ
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			pool_roi_vld <= 1'b0;
		else if(pool_roi_gen_stage1_ready)
			pool_roi_vld <= # simulation_delay feature_in_vld_d & 
				(~pool_y_eq0_d) & // �ػ�y���� >= 1
				((~step_type) | pool_y_d[0]); // step_type ? pool_y_d[0]:1'b1
	end
	
	// �ӳ�1clk������������
	always @(posedge clk)
	begin
		if(m_axis_row_padding_valid & m_axis_row_padding_ready)
			feature_in_d <= # simulation_delay m_axis_row_padding_data & feature_in_data_mask;
	end
	// �ӳ�1clk������������ʹ������
	always @(posedge clk)
	begin
		if(m_axis_row_padding_valid & m_axis_row_padding_ready)
			feature_in_keep_d <= # simulation_delay feature_in_keep;
	end
	
	// �ӳ�1clk�ĳػ�x���� == 0(��־)
	always @(posedge clk)
	begin
		if(m_axis_row_padding_valid & m_axis_row_padding_ready)
			pool_x_eq0_d <= # simulation_delay pool_x_eq0;
	end
	// �ӳ�1clk�ĳػ�y����
	always @(posedge clk)
	begin
		if(m_axis_row_padding_valid & m_axis_row_padding_ready)
			pool_y_d <= # simulation_delay pool_y;
	end
	// �ӳ�1clk�ĳػ�y���� == 0(��־)
	always @(posedge clk)
	begin
		if(m_axis_row_padding_valid & m_axis_row_padding_ready)
			pool_y_eq0_d <= # simulation_delay pool_y_eq0;
	end
	
	// �ӳ�2clk�ĳػ�x���� == 0(��־)
	always @(posedge clk)
	begin
		if(feature_in_vld_d & pool_roi_gen_stage1_ready)
			pool_x_eq0_d2 <= # simulation_delay pool_x_eq0_d;
	end
	
	// �ػ�ROI��1��
	always @(posedge clk)
	begin
		if(feature_in_vld_d & pool_roi_gen_stage1_ready)
			pool_roi_r1 <= # simulation_delay line_buf_mem_dout_b;
	end
	// �ػ�ROI��2��
	always @(posedge clk)
	begin
		if(feature_in_vld_d & pool_roi_gen_stage1_ready)
			pool_roi_r2 <= # simulation_delay feature_in_d;
	end
	// �ػ�ROI������ʹ������
	always @(posedge clk)
	begin
		if(feature_in_vld_d & pool_roi_gen_stage1_ready)
			pool_roi_keep <= # simulation_delay feature_in_keep_d;
	end
	
	// �ػ�ROI��1��ʣ�໺��
	always @(posedge clk)
	begin
		if(feature_in_vld_d & pool_roi_gen_stage1_ready)
			pool_left_buf_r1 <= # simulation_delay pool_x_eq0_d ? 
				{feature_data_width{1'b0}}:pool_roi_r1[in_stream_data_width-1:in_stream_data_width-feature_data_width];
	end
	// �ػ�ROI��2��ʣ�໺��
	always @(posedge clk)
	begin
		if(feature_in_vld_d & pool_roi_gen_stage1_ready)
			pool_left_buf_r2 <= # simulation_delay pool_x_eq0_d ? 
				{feature_data_width{1'b0}}:pool_roi_r2[in_stream_data_width-1:in_stream_data_width-feature_data_width];
	end
	
	// �ӳ�1clk�������������λ�ñ�־({1ast(1bit), user(3bit)})
	always @(posedge clk)
	begin
		if(m_axis_row_padding_valid & m_axis_row_padding_ready)
			pool_roi_user_last_d <= # simulation_delay {m_axis_row_padding_last, m_axis_row_padding_user};
	end
	// �ӳ�2clk�������������λ�ñ�־({1ast(1bit), user(3bit)})
	always @(posedge clk)
	begin
		if(feature_in_vld_d & pool_roi_gen_stage1_ready)
			pool_roi_user_last_d2 <= # simulation_delay pool_roi_user_last_d;
	end
	
	/** �ػ����� **/
	// �ػ�ROI����
	wire[in_stream_data_width-1:0] cal_unit_pool_roi_r1; // �ػ�ROI��1��
	wire[in_stream_data_width-1:0] cal_unit_pool_roi_r2; // �ػ�ROI��2��
	wire[feature_n_per_clk-1:0] cal_unit_pool_roi_keep; // �ػ�ROI������ʹ������
	wire[feature_data_width-1:0] cal_unit_pool_left_buf_r1; // �ػ�ROI��1��ʣ�໺��
	wire[feature_data_width-1:0] cal_unit_pool_left_buf_r2; // �ػ�ROI��2��ʣ�໺��
	wire cal_unit_pool_x_eq0; // �ػ�x���� == 0(��־)
	wire[2:0] cal_unit_pool_roi_user; // {��ǰ�������1��ͨ��, ��ǰ�������1��, ��ǰ�������1��}
	wire cal_unit_pool_roi_last; // ����ͼ���1��
	wire cal_unit_pool_roi_valid;
	wire cal_unit_pool_roi_ready;
	// ���������
	wire[out_stream_data_width-1:0] cal_unit_pool_res;
	wire[out_stream_data_width/8-1:0] cal_unit_pool_res_keep;
	wire[2:0] cal_unit_pool_res_user; // {��ǰ�������1��ͨ��, ��ǰ�������1��, ��ǰ�������1��}
	wire cal_unit_pool_res_last; // ����ͼ���1��
	wire cal_unit_pool_res_valid;
	wire cal_unit_pool_res_ready;
	
	assign cal_unit_pool_roi_r1 = pool_roi_r1;
	assign cal_unit_pool_roi_r2 = pool_roi_r2;
	assign cal_unit_pool_roi_keep = pool_roi_keep;
	assign cal_unit_pool_left_buf_r1 = pool_left_buf_r1;
	assign cal_unit_pool_left_buf_r2 = pool_left_buf_r2;
	assign cal_unit_pool_x_eq0 = pool_x_eq0_d2;
	assign cal_unit_pool_roi_user = pool_roi_user_last_d2[2:0];
	assign cal_unit_pool_roi_last = pool_roi_user_last_d2[3];
	assign cal_unit_pool_roi_valid = pool_roi_vld;
	assign pool_roi_gen_stage2_ready = cal_unit_pool_roi_ready;
	
	// ���ػ����㵥Ԫ
	max_pool_cal_mul_pix #(
		.feature_n_per_clk(feature_n_per_clk),
		.feature_data_width(feature_data_width),
		.simulation_delay(simulation_delay)
	)max_pool_cal_mul_pix_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.step_type(step_type),
		.padding_vec(padding_vec[1:0]),
		
		.pool_roi_r1(cal_unit_pool_roi_r1),
		.pool_roi_r2(cal_unit_pool_roi_r2),
		.pool_roi_keep(cal_unit_pool_roi_keep),
		.pool_left_buf_r1(cal_unit_pool_left_buf_r1),
		.pool_left_buf_r2(cal_unit_pool_left_buf_r2),
		.pool_x_eq0(cal_unit_pool_x_eq0),
		.pool_roi_user(cal_unit_pool_roi_user),
		.pool_roi_last(cal_unit_pool_roi_last),
		.pool_roi_valid(cal_unit_pool_roi_valid),
		.pool_roi_ready(cal_unit_pool_roi_ready),
		
		.pool_res(cal_unit_pool_res),
		.pool_res_keep(cal_unit_pool_res_keep),
		.pool_res_user(cal_unit_pool_res_user),
		.pool_res_last(cal_unit_pool_res_last),
		.pool_res_valid(cal_unit_pool_res_valid),
		.pool_res_ready(cal_unit_pool_res_ready)
	);
	
	/** �������������Ԫ **/
	// ����Ԫ����
	wire[out_stream_data_width-1:0] s_axis_reorg_data;
	wire[2:0] s_axis_reorg_user; // {��ǰ�������1��ͨ��, ��ǰ�������1��, ��ǰ�������1��}
	wire[out_stream_data_width/8-1:0] s_axis_reorg_keep;
	wire s_axis_reorg_last; // ָʾ���1��������
	wire s_axis_reorg_valid;
	wire s_axis_reorg_ready;
	// ����Ԫ���
	wire[out_stream_data_width-1:0] m_axis_reorg_data;
	wire[2:0] m_axis_reorg_user; // {��ǰ�������1��ͨ��, ��ǰ�������1��, ��ǰ�������1��}
	wire[out_stream_data_width/8-1:0] m_axis_reorg_keep;
	wire m_axis_reorg_last; // ָʾ���1��������
	wire m_axis_reorg_valid;
	wire m_axis_reorg_ready;
	
	assign s_axis_reorg_data = cal_unit_pool_res;
	assign s_axis_reorg_keep = cal_unit_pool_res_keep;
	assign s_axis_reorg_user = cal_unit_pool_res_user;
	assign s_axis_reorg_last = cal_unit_pool_res_last;
	assign s_axis_reorg_valid = cal_unit_pool_res_valid;
	assign cal_unit_pool_res_ready = s_axis_reorg_ready;
	
	max_pool_item_formator #(
		.feature_n_per_clk(feature_n_per_clk),
		.feature_data_width(feature_data_width),
		.en_out_reg_slice(en_reg_slice_at_item_formator),
		.simulation_delay(simulation_delay)
	)max_pool_item_formator_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.step_type(step_type),
		
		.s_axis_data(s_axis_reorg_data),
		.s_axis_user(s_axis_reorg_user),
		.s_axis_keep(s_axis_reorg_keep),
		.s_axis_last(s_axis_reorg_last),
		.s_axis_valid(s_axis_reorg_valid),
		.s_axis_ready(s_axis_reorg_ready),
		
		.m_axis_data(m_axis_reorg_data),
		.m_axis_user(m_axis_reorg_user),
		.m_axis_keep(m_axis_reorg_keep),
		.m_axis_last(m_axis_reorg_last),
		.m_axis_valid(m_axis_reorg_valid),
		.m_axis_ready(m_axis_reorg_ready)
	);
	
	/** ������������ռ���Ԫ **/
	// �����ռ���Ԫ����
	wire[out_stream_data_width-1:0] s_axis_collector_data;
	wire[out_stream_data_width/8-1:0] s_axis_collector_keep;
	wire s_axis_collector_last; // ָʾ���1��������
	wire s_axis_collector_valid;
	wire s_axis_collector_ready;
	// �����ռ���Ԫ���
	wire[feature_n_per_clk*feature_data_width-1:0] m_axis_collector_data;
	wire[feature_n_per_clk*feature_data_width/8-1:0] m_axis_collector_keep;
	wire m_axis_collector_last; // ָʾ�������ͼ�����1������
	wire m_axis_collector_valid;
	wire m_axis_collector_ready;
	
	assign s_axis_collector_data = m_axis_reorg_data;
	assign s_axis_collector_keep = m_axis_reorg_keep;
	assign s_axis_collector_last = m_axis_reorg_last;
	assign s_axis_collector_valid = m_axis_reorg_valid;
	assign m_axis_reorg_ready = s_axis_collector_ready;
	
	assign s_axis_reg_slice_data = m_axis_collector_data;
	assign s_axis_reg_slice_keep = m_axis_collector_keep;
	assign s_axis_reg_slice_last = m_axis_collector_last;
	assign s_axis_reg_slice_valid = m_axis_collector_valid;
	assign m_axis_collector_ready = s_axis_reg_slice_ready;
	
	max_pool_packet_collector #(
		.feature_n_per_clk(feature_n_per_clk),
		.feature_data_width(feature_data_width),
		.simulation_delay(simulation_delay)
	)max_pool_packet_collector_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axis_data(s_axis_collector_data),
		.s_axis_keep(s_axis_collector_keep),
		.s_axis_last(s_axis_collector_last),
		.s_axis_valid(s_axis_collector_valid),
		.s_axis_ready(s_axis_collector_ready),
		
		.m_axis_data(m_axis_collector_data),
		.m_axis_keep(m_axis_collector_keep),
		.m_axis_last(m_axis_collector_last),
		.m_axis_valid(m_axis_collector_valid),
		.m_axis_ready(m_axis_collector_ready)
	);
    
endmodule
