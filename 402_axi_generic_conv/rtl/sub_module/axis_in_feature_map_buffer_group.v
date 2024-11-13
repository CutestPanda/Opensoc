`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXIS��������ͼ������

����:
����������ͼ����n��������, ��������ʱͬʱ���m��ͬһ�е�������

		 {[------��#0------]  --
          [------��#1------]   |
		  [------��#2------]}  |
                               |----->
		 {[------��#0------]   |
          [------��#1------]   |
		  [------��#2------]} --

		 {[------��#0------]
  ----->  [------��#1------]
		  [------��#2------]}
ע�⣺
��������ͼ�������(in_feature_map_buffer_n)����>=����������ͼ����Ĳ��и���(in_feature_map_buffer_rd_prl_n)

Э��:
AXIS MASTER/SLAVE

����: �¼�ҫ
����: 2024/10/21
********************************************************************/


module axis_in_feature_map_buffer_group #(
	parameter integer in_feature_map_buffer_n = 8, // ��������ͼ�������
	parameter integer in_feature_map_buffer_rd_prl_n = 4, // ����������ͼ����Ĳ��и���
	parameter integer feature_data_width = 16, // ������λ��(8 | 16 | 32 | 64)
	parameter integer max_feature_map_w = 512, // ������������ͼ���
	parameter line_buffer_mem_type = "bram", // �л���MEM����("bram" | "lutram" | "auto")
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
	input wire clk,
	input wire rst_n,
	
	// ����ʱ����
	input wire[15:0] feature_map_w, // ��������ͼ��� - 1
	
	// ��������ͼ(AXIS�ӻ�)
	input wire[63:0] s_axis_ft_data,
	input wire s_axis_ft_last, // ��ʾ����ͼ��β
	input wire[1:0] s_axis_ft_user, // {�����Ƿ���Ч, ��ǰ���������1�б�־}
	input wire s_axis_ft_valid,
	output wire s_axis_ft_ready,
	
	// �������(AXIS����)
	// {����#(n-1)��#2, ����#(n-1)��#1, ����#(n-1)��#0, ..., ����#0��#2, ����#0��#1, ����#0��#0}
	output wire[feature_data_width*3*in_feature_map_buffer_rd_prl_n-1:0] m_axis_buf_data,
	output wire m_axis_buf_last, // ��ʾ����ͼ��β
	output wire[in_feature_map_buffer_rd_prl_n*3-1:0] m_axis_buf_user, // {�������Ƿ���Ч��־����}
	output wire m_axis_buf_valid,
	input wire m_axis_buf_ready
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
	
	/** ������� **/
	// ��������MEM��ˮ��
	// stage0
	wire buffer_out_valid_stage0;
	wire buffer_out_ready_stage0;
	wire buffer_out_last_stage0; // ��ʾ����ͼ��β
	wire[in_feature_map_buffer_rd_prl_n*3-1:0] buffer_out_user_stage0; // {�������Ƿ���Ч��־����}
	// stage1
	reg buffer_out_valid_stage1;
	wire buffer_out_ready_stage1;
	reg buffer_out_last_stage1; // ��ʾ����ͼ��β
	reg[in_feature_map_buffer_rd_prl_n*3-1:0] buffer_out_user_stage1; // {�������Ƿ���Ч��־����}
	// stage2
	reg buffer_out_valid_stage2;
	wire buffer_out_ready_stage2;
	wire[feature_data_width*3*in_feature_map_buffer_rd_prl_n-1:0] buffer_out_data_stage2;
	reg buffer_out_last_stage2; // ��ʾ����ͼ��β
	reg[in_feature_map_buffer_rd_prl_n*3-1:0] buffer_out_user_stage2; // {�������Ƿ���Ч��־����}
	// stage3
	reg buffer_out_valid_stage3;
	wire buffer_out_ready_stage3;
	reg[feature_data_width*3*in_feature_map_buffer_rd_prl_n-1:0] buffer_out_data_stage3;
	reg buffer_out_last_stage3; // ��ʾ����ͼ��β
	reg[in_feature_map_buffer_rd_prl_n*3-1:0] buffer_out_user_stage3; // {�������Ƿ���Ч��־����}
	
	assign m_axis_buf_data = buffer_out_data_stage3;
	assign m_axis_buf_last = buffer_out_last_stage3;
	assign m_axis_buf_user = buffer_out_user_stage3;
	assign m_axis_buf_valid = buffer_out_valid_stage3;
	
	assign buffer_out_ready_stage0 = (~buffer_out_valid_stage1) | buffer_out_ready_stage1;
	assign buffer_out_ready_stage1 = (~buffer_out_valid_stage2) | buffer_out_ready_stage2;
	assign buffer_out_ready_stage2 = (~buffer_out_valid_stage3) | buffer_out_ready_stage3;
	assign buffer_out_ready_stage3 = m_axis_buf_ready;
	
	// ��������MEM��1����ˮ��valid
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_out_valid_stage1 <= 1'b0;
		else if(buffer_out_ready_stage0)
			buffer_out_valid_stage1 <= # simulation_delay buffer_out_valid_stage0;
	end
	// ��������MEM��1����ˮ��last��user
	always @(posedge clk)
	begin
		if(buffer_out_valid_stage0 & buffer_out_ready_stage0)
			{buffer_out_last_stage1, buffer_out_user_stage1} <= # simulation_delay 
				{buffer_out_last_stage0, buffer_out_user_stage0};
	end
	
	// ��������MEM��2����ˮ��valid
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_out_valid_stage2 <= 1'b0;
		else if(buffer_out_ready_stage1)
			buffer_out_valid_stage2 <= # simulation_delay buffer_out_valid_stage1;
	end
	// ��������MEM��2����ˮ��last��user
	always @(posedge clk)
	begin
		if(buffer_out_valid_stage1 & buffer_out_ready_stage1)
			{buffer_out_last_stage2, buffer_out_user_stage2} <= # simulation_delay 
				{buffer_out_last_stage1, buffer_out_user_stage1};
	end
	
	// ��������MEM��3����ˮ��valid
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_out_valid_stage3 <= 1'b0;
		else if(buffer_out_ready_stage2)
			buffer_out_valid_stage3 <= # simulation_delay buffer_out_valid_stage2;
	end
	// ��������MEM��3����ˮ��data, last��user
	always @(posedge clk)
	begin
		if(buffer_out_valid_stage2 & buffer_out_ready_stage2)
			{buffer_out_data_stage3, buffer_out_last_stage3, buffer_out_user_stage3} <= # simulation_delay 
				{buffer_out_data_stage2, buffer_out_last_stage2, buffer_out_user_stage2};
	end
	
	/** �������洢���� **/
	wire buffer_group_wen; // ������дʹ��
	wire buffer_group_ren; // �������ʹ��
	reg[clogb2(in_feature_map_buffer_n):0] buffer_group_n; // ������洢����
	wire[clogb2(in_feature_map_buffer_n):0] buffer_group_n_incr; // ������洢��������
	wire[clogb2(in_feature_map_buffer_n):0] buffer_group_n_nxt; // �µĻ�����洢����
	reg buffer_group_full_n; // ����������־
	reg buffer_group_empty_n; // ������ձ�־
	
	assign buffer_group_n_incr = 
		// -in_feature_map_buffer_rd_prl_n
		({buffer_group_wen & buffer_group_full_n, 
			buffer_group_ren & buffer_group_empty_n} == 2'b01) ? ((~in_feature_map_buffer_rd_prl_n) + 1):
		// -in_feature_map_buffer_rd_prl_n + 1
		({buffer_group_wen & buffer_group_full_n, 
			buffer_group_ren & buffer_group_empty_n} == 2'b11) ? ((~in_feature_map_buffer_rd_prl_n) + 2):
																 1;
	assign buffer_group_n_nxt = buffer_group_n + buffer_group_n_incr;
	
	// ������洢����
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_group_n <= 0;
		else if((buffer_group_wen & buffer_group_full_n) | (buffer_group_ren & buffer_group_empty_n))
			buffer_group_n <= # simulation_delay buffer_group_n_nxt;
	end
	
	// ����������־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_group_full_n <= 1'b1;
		else if((buffer_group_wen & buffer_group_full_n) | (buffer_group_ren & buffer_group_empty_n))
			buffer_group_full_n <= # simulation_delay buffer_group_n_nxt != in_feature_map_buffer_n;
	end
	// ������ձ�־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_group_empty_n <= 1'b0;
		else if((buffer_group_wen & buffer_group_full_n) | (buffer_group_ren & buffer_group_empty_n))
			buffer_group_empty_n <= # simulation_delay buffer_group_n_nxt >= in_feature_map_buffer_rd_prl_n;
	end
	
	/** ������д�˿� **/
	reg[in_feature_map_buffer_n-1:0] buffer_group_wptr; // ������дָ��
	reg[2:0] buffer_row_wptr; // ������дָ��
	reg[1:0] buffer_row_written; // ��������д��־����({��#1��д, ��#0��д})
	
	// ��������: s_axis_ft_valid & buffer_group_full_n
	assign s_axis_ft_ready = buffer_group_full_n;
	
	// ��������: s_axis_ft_valid & s_axis_ft_user[0] & s_axis_ft_last & buffer_group_full_n
	assign buffer_group_wen = s_axis_ft_valid & s_axis_ft_user[0] & s_axis_ft_last;
	
	// ������дָ��
	generate
		if(in_feature_map_buffer_n == 1)
		begin
			always @(*)
				buffer_group_wptr = 1'b1;
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					buffer_group_wptr <= {{(in_feature_map_buffer_n-1){1'b0}}, 1'b1};
				else if(buffer_group_wen & buffer_group_full_n)
					buffer_group_wptr <= # simulation_delay {buffer_group_wptr[in_feature_map_buffer_n-2:0], 
						buffer_group_wptr[in_feature_map_buffer_n-1]};
			end
		end
	endgenerate
	
	// ������дָ��
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_row_wptr <= 3'b001;
		else if(s_axis_ft_valid & s_axis_ft_ready & s_axis_ft_last)
			// s_axis_ft_user[0] ? 3'b001:{buffer_row_wptr[1:0], buffer_row_wptr[2]}
			buffer_row_wptr <= # simulation_delay {{2{~s_axis_ft_user[0]}} & buffer_row_wptr[1:0], 
				s_axis_ft_user[0] | buffer_row_wptr[2]};
	end
	
	// ��������д��־����
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_row_written <= 2'b00;
		else if(s_axis_ft_valid & s_axis_ft_ready & s_axis_ft_last)
			// s_axis_ft_user[0] ? 2'b00:(buffer_row_written | buffer_row_wptr[1:0])
			buffer_row_written <= # simulation_delay {2{~s_axis_ft_user[0]}} & (buffer_row_written | buffer_row_wptr[1:0]);
	end
	
	/** ���������˿� **/
	reg[clogb2(max_feature_map_w-1):0] buffer_rd_col_id; // ���������к�
	wire buffer_rd_last_col; // ��ǰ�����������1��(��־)
	reg[clogb2(in_feature_map_buffer_n-1):0] buffer_rd_sel; // ��������Ƭѡ
	reg[clogb2(in_feature_map_buffer_n-1):0] buffer_rd_sel_d; // �ӳ�1clk�Ļ�������Ƭѡ
	reg[clogb2(in_feature_map_buffer_n-1):0] buffer_rd_sel_d2; // �ӳ�2clk�Ļ�������Ƭѡ
	wire[clogb2(in_feature_map_buffer_n-1):0] buffer_rd_sel_incr; // ��������Ƭѡ����
	reg[in_feature_map_buffer_n-1:0] buffer_group_rptr; // �������ָ��
	reg[in_feature_map_buffer_n-1:0] buffer_group_rptr_d; // �ӳ�1clk�Ļ������ָ��
	
	// ��������: buffer_group_empty_n & buffer_out_ready_stage0
	assign buffer_out_valid_stage0 = buffer_group_empty_n;
	assign buffer_out_last_stage0 = buffer_rd_last_col;
	
	// ��������: buffer_group_empty_n & buffer_out_ready_stage0 & buffer_rd_last_col
	assign buffer_group_ren = buffer_out_ready_stage0 & buffer_rd_last_col;
	
	assign buffer_rd_last_col = buffer_rd_col_id == feature_map_w[clogb2(max_feature_map_w-1):0];
	assign buffer_rd_sel_incr = (buffer_rd_sel >= (in_feature_map_buffer_n - in_feature_map_buffer_rd_prl_n)) ? 
		// in_feature_map_buffer_rd_prl_n - in_feature_map_buffer_n
		((~(in_feature_map_buffer_n - in_feature_map_buffer_rd_prl_n)) + 1):
		in_feature_map_buffer_rd_prl_n;
	
	// ���������к�
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_rd_col_id <= 0;
		else if(buffer_out_valid_stage0 & buffer_out_ready_stage0)
			// buffer_rd_last_col ? 0:(buffer_rd_col_id + 1)
			buffer_rd_col_id <= # simulation_delay 
				{(clogb2(max_feature_map_w-1)+1){~buffer_rd_last_col}} & (buffer_rd_col_id + 1);
	end
	
	// ��������Ƭѡ
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_rd_sel <= 0;
		else if(buffer_group_ren & buffer_group_empty_n)
			buffer_rd_sel <= # simulation_delay buffer_rd_sel + buffer_rd_sel_incr;
	end
	// �ӳ�1clk�Ļ�������Ƭѡ
	always @(posedge clk)
	begin
		if(buffer_out_valid_stage0 & buffer_out_ready_stage0)
			buffer_rd_sel_d <= # simulation_delay buffer_rd_sel;
	end
	// �ӳ�2clk�Ļ�������Ƭѡ
	always @(posedge clk)
	begin
		if(buffer_out_valid_stage1 & buffer_out_ready_stage1)
			buffer_rd_sel_d2 <= # simulation_delay buffer_rd_sel_d;
	end
	
	// �������ָ��
	generate
		if(in_feature_map_buffer_n == in_feature_map_buffer_rd_prl_n)
		begin
			always @(*)
				buffer_group_rptr = {in_feature_map_buffer_n{1'b1}};
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					buffer_group_rptr <= {{(in_feature_map_buffer_n-in_feature_map_buffer_rd_prl_n){1'b0}}, 
						{in_feature_map_buffer_rd_prl_n{1'b1}}};
				else if(buffer_group_ren & buffer_group_empty_n)
					// ѭ������in_feature_map_buffer_rd_prl_nλ
					buffer_group_rptr <= # simulation_delay 
						(buffer_group_rptr << in_feature_map_buffer_rd_prl_n) | 
						(buffer_group_rptr >> (in_feature_map_buffer_n-in_feature_map_buffer_rd_prl_n));
			end
		end
	endgenerate
	
	// �ӳ�1clk�Ļ������ָ��
	always @(posedge clk)
	begin
		if(buffer_out_valid_stage0 & buffer_out_ready_stage0)
			buffer_group_rptr_d <= # simulation_delay buffer_group_rptr;
	end
	
	/** ��������Ϣfifo **/
	reg[2:0] buffer_msg_fifo[0:in_feature_map_buffer_n-1]; // ��������Ϣfifo�Ĵ�����({��#2�Ƿ���Ч, ��#1�Ƿ���Ч, ��#0�Ƿ���Ч})
	wire[in_feature_map_buffer_n*3-1:0] buffer_row_vld_flattened; // չƽ�Ļ������Ƿ���Ч��־
	wire[in_feature_map_buffer_rd_prl_n*3-1:0] buffer_row_vld_vec; // �������Ƿ���Ч��־����
	
	assign buffer_out_user_stage0 = buffer_row_vld_vec;
	
	// �������Ƿ���Ч��־����
	// ѭ������buffer_rd_sel*3λ, ������in_feature_map_buffer_n�����
	assign buffer_row_vld_vec = (buffer_rd_sel >= in_feature_map_buffer_n) ? 
		{(in_feature_map_buffer_rd_prl_n*3){1'bx}}: // not care!
		((buffer_row_vld_flattened >> (buffer_rd_sel*3)) | 
			(buffer_row_vld_flattened << ((in_feature_map_buffer_n - buffer_rd_sel)*3)));
	
	genvar buffer_msg_fifo_i;
	generate
		for(buffer_msg_fifo_i = 0;buffer_msg_fifo_i < in_feature_map_buffer_n;buffer_msg_fifo_i = buffer_msg_fifo_i + 1)
		begin
			// չƽ�Ļ������Ƿ���Ч��־
			assign buffer_row_vld_flattened[(buffer_msg_fifo_i+1)*3-1:buffer_msg_fifo_i*3] = 
				buffer_msg_fifo[buffer_msg_fifo_i];
			
			// ��������Ϣfifo������
			// ��#0�Ƿ���Ч
			always @(posedge clk)
			begin
				if(s_axis_ft_valid & s_axis_ft_ready & s_axis_ft_last & 
					buffer_group_wptr[buffer_msg_fifo_i] & buffer_row_wptr[0])
					buffer_msg_fifo[buffer_msg_fifo_i][0] <= # simulation_delay s_axis_ft_user[1];
			end
			// ��#1�Ƿ���Ч
			always @(posedge clk)
			begin
				if(s_axis_ft_valid & s_axis_ft_ready & s_axis_ft_last & 
					buffer_group_wptr[buffer_msg_fifo_i] & 
					// ���δд����#0�ͽ���д��ǰ������, ����#1��Ϊ��Ч
					(buffer_row_wptr[1] | (s_axis_ft_user[0] & (~buffer_row_written[0]))))
					buffer_msg_fifo[buffer_msg_fifo_i][1] <= # simulation_delay buffer_row_wptr[1] & s_axis_ft_user[1];
			end
			// ��#2�Ƿ���Ч
			always @(posedge clk)
			begin
				if(s_axis_ft_valid & s_axis_ft_ready & s_axis_ft_last & 
					buffer_group_wptr[buffer_msg_fifo_i] & 
					// ���δд����#1�ͽ���д��ǰ������, ����#2��Ϊ��Ч
					(buffer_row_wptr[2] | (s_axis_ft_user[0] & (~buffer_row_written[1]))))
					buffer_msg_fifo[buffer_msg_fifo_i][2] <= # simulation_delay buffer_row_wptr[2] & s_axis_ft_user[1];
			end
		end
	endgenerate
	
	/** ��������ͼ������MEM **/
	// MEMд�˿�
	wire[2:0] buffer_mem_wen[0:in_feature_map_buffer_n-1];
	reg[clogb2(max_feature_map_w*feature_data_width/64-1):0] buffer_mem_waddr; // ÿ��д��ַ��Ӧ64λ����
	wire[63:0] buffer_mem_din; // 64λ����
	wire[64/feature_data_width-1:0] buffer_mem_din_last; // ��β��־
	// MEM���˿�
	wire buffer_mem_ren_s0[0:in_feature_map_buffer_n-1];
	wire buffer_mem_ren_s1[0:in_feature_map_buffer_n-1];
	wire[clogb2(max_feature_map_w-1):0] buffer_mem_raddr; // ÿ������ַ��Ӧ1��������
	wire[feature_data_width-1:0] buffer_mem_dout_r0[0:in_feature_map_buffer_n-1]; // ��#0������
	wire[feature_data_width-1:0] buffer_mem_dout_r1[0:in_feature_map_buffer_n-1]; // ��#1������
	wire[feature_data_width-1:0] buffer_mem_dout_r2[0:in_feature_map_buffer_n-1]; // ��#2������
	wire[feature_data_width*3*in_feature_map_buffer_n-1:0] buffer_mem_dout_flattened; // չƽ�Ķ�����
	// λ�ڶ�������MEM��2����ˮ�ߵĶ���������
	wire[feature_data_width*3*in_feature_map_buffer_rd_prl_n-1:0] buffer_out_data_mask_stage2;
	
	// չƽ�Ķ�����
	genvar buffer_mem_dout_flattened_i;
	generate
		for(buffer_mem_dout_flattened_i = 0;buffer_mem_dout_flattened_i < in_feature_map_buffer_n;
			buffer_mem_dout_flattened_i = buffer_mem_dout_flattened_i + 1)
		begin
			assign buffer_mem_dout_flattened[(buffer_mem_dout_flattened_i+1)*feature_data_width*3-1:
				buffer_mem_dout_flattened_i*feature_data_width*3] = {
					buffer_mem_dout_r2[buffer_mem_dout_flattened_i],
					buffer_mem_dout_r1[buffer_mem_dout_flattened_i],
					buffer_mem_dout_r0[buffer_mem_dout_flattened_i]
				};
		end
	endgenerate
	// ��������MEM��2����ˮ��data
	// ѭ������(buffer_rd_sel_d2 * feature_data_width * 3)λ, ������in_feature_map_buffer_n�����
	assign buffer_out_data_stage2 = ((buffer_rd_sel_d2 >= in_feature_map_buffer_n) ? 
		{(feature_data_width*3*in_feature_map_buffer_rd_prl_n){1'bx}}: // not care!
		((buffer_mem_dout_flattened >> (buffer_rd_sel_d2 * feature_data_width * 3)) | 
			(buffer_mem_dout_flattened << ((in_feature_map_buffer_n - buffer_rd_sel_d2) * feature_data_width * 3)))) & 
		buffer_out_data_mask_stage2;
	
	// λ�ڶ�������MEM��2����ˮ�ߵĶ���������
	genvar buffer_out_data_mask_stage2_i;
	generate
		for(buffer_out_data_mask_stage2_i = 0;buffer_out_data_mask_stage2_i < in_feature_map_buffer_rd_prl_n*3;
			buffer_out_data_mask_stage2_i = buffer_out_data_mask_stage2_i + 1)
		begin
			assign buffer_out_data_mask_stage2[(buffer_out_data_mask_stage2_i+1)*feature_data_width-1:
				buffer_out_data_mask_stage2_i*feature_data_width] = 
					{(feature_data_width){buffer_out_user_stage2[buffer_out_data_mask_stage2_i]}};
		end
	endgenerate
	
	// MEMдʹ��
	genvar buffer_mem_wen_i;
	generate
		for(buffer_mem_wen_i = 0;buffer_mem_wen_i < in_feature_map_buffer_n;buffer_mem_wen_i = buffer_mem_wen_i + 1)
		begin
			assign buffer_mem_wen[buffer_mem_wen_i] = 
				{3{buffer_group_wptr[buffer_mem_wen_i] & s_axis_ft_valid & s_axis_ft_ready}} & buffer_row_wptr;
		end
	endgenerate
	
	// MEMд����
	assign buffer_mem_din = s_axis_ft_data;
	assign buffer_mem_din_last = {(64/feature_data_width){1'bx}}; // not care!
	
	// MEM��ʹ��
	genvar buffer_mem_ren_i;
	generate
		for(buffer_mem_ren_i = 0;buffer_mem_ren_i < in_feature_map_buffer_n;buffer_mem_ren_i = buffer_mem_ren_i + 1)
		begin
			assign buffer_mem_ren_s0[buffer_mem_ren_i] = 
				buffer_out_valid_stage0 & buffer_out_ready_stage0 & buffer_group_rptr[buffer_mem_ren_i];
			assign buffer_mem_ren_s1[buffer_mem_ren_i] = 
				buffer_out_valid_stage1 & buffer_out_ready_stage1 & buffer_group_rptr_d[buffer_mem_ren_i];
		end
	endgenerate
	
	// MEM����ַ
	assign buffer_mem_raddr = buffer_rd_col_id;
	
	// MEMд��ַ
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_mem_waddr <= 0;
		else if(s_axis_ft_valid & s_axis_ft_ready)
			// s_axis_ft_last ? 0:(buffer_mem_waddr + 1)
			buffer_mem_waddr <= # simulation_delay {(clogb2(max_feature_map_w*feature_data_width/64-1)+1){~s_axis_ft_last}} & 
				(buffer_mem_waddr + 1);
	end
	
	// ����MEM
	genvar buffer_mem_i;
	generate
		for(buffer_mem_i = 0;buffer_mem_i < in_feature_map_buffer_n;buffer_mem_i = buffer_mem_i + 1)
		begin
			conv_in_feature_map_buffer #(
				.feature_data_width(feature_data_width),
				.max_feature_map_w(max_feature_map_w),
				.line_buffer_mem_type(line_buffer_mem_type),
				.simulation_delay(simulation_delay)
			)conv_in_feature_map_buffer_u(
				.clk(clk),
				
				.buffer_wen(buffer_mem_wen[buffer_mem_i]),
				.buffer_waddr(buffer_mem_waddr),
				.buffer_din(buffer_mem_din),
				.buffer_din_last(buffer_mem_din_last),
				
				.buffer_ren_s0(buffer_mem_ren_s0[buffer_mem_i]),
				.buffer_ren_s1(buffer_mem_ren_s1[buffer_mem_i]),
				.buffer_raddr(buffer_mem_raddr),
				.buffer_dout_r0(buffer_mem_dout_r0[buffer_mem_i]),
				.buffer_dout_r1(buffer_mem_dout_r1[buffer_mem_i]),
				.buffer_dout_r2(buffer_mem_dout_r2[buffer_mem_i]),
				.buffer_dout_last_r0(),
				.buffer_dout_last_r1(),
				.buffer_dout_last_r2()
			);
		end
	endgenerate
	
endmodule
