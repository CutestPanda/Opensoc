`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXIS����˲���������

����:
����ͨ������˴���n��������, ��������ʱͬʱ���m����ͨ������˵�ͬһͨ��
д��ͨ�������ʱÿclk���������˲�������ȡ1��������

MEM��ʱ�� = 2clk

		 [------��ͨ�������#0------]  --
         [------��ͨ�������#1------]   |----->
		 [------��ͨ�������#2------]   |----->
		 [------��ͨ�������#3------]  --
 ----->  [------��ͨ�������#4------]
		 [------��ͨ�������#5------]
		 [------��ͨ�������#6------]
		 [------��ͨ�������#7------]

3x3��ͨ������˴洢��ʽ:
	{x3y3, x2y3, x1y3, x3y2, x2y2, x1y2, x3y1, x2y1, x1y1}

ע�⣺
����˲����������(kernal_pars_buffer_n)����>=��ͨ������˵Ĳ��и���(kernal_prl_n)

Э��:
AXIS SLAVE
FIFO READ
MEM READ

����: �¼�ҫ
����: 2024/10/22
********************************************************************/


module axis_kernal_params_buffer #(
	parameter integer kernal_pars_buffer_n = 8, // ����˲����������
	parameter integer kernal_prl_n = 4, // ��ͨ������˵Ĳ��и���
	parameter integer kernal_param_data_width = 16, // ����˲���λ��(8 | 16 | 32 | 64)
	parameter integer max_feature_map_chn_n = 512, // ������������ͼͨ����
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
	input wire clk,
	input wire rst_n,
	
	// ����ʱ����
	input wire kernal_type, // ���������(1'b0 -> 1x1, 1'b1 -> 3x3)
	
	// �������˲�����(AXIS�ӻ�)
	input wire[63:0] s_axis_kernal_pars_data,
	input wire[7:0] s_axis_kernal_pars_keep,
	input wire s_axis_kernal_pars_last, // ��ʾ���1�����˲���
	input wire s_axis_kernal_pars_user, // ��ǰ��ͨ��������Ƿ���Ч
	input wire s_axis_kernal_pars_valid,
	output wire s_axis_kernal_pars_ready, // ע��:�ǼĴ������!
	
	// ����˲����������(fifo���˿�)
	input wire kernal_pars_buf_fifo_ren,
	output wire kernal_pars_buf_fifo_empty_n,
	
	// ����˲�������MEM���˿�
	input wire kernal_pars_buf_mem_buf_ren_s0,
	input wire kernal_pars_buf_mem_buf_ren_s1,
	input wire[15:0] kernal_pars_buf_mem_buf_raddr, // ÿ������ַ��Ӧ1����ͨ�������
	output wire[kernal_prl_n*kernal_param_data_width*9-1:0] kernal_pars_buf_mem_buf_dout // {��#(n-1), ..., ��#1, ��#0}
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
	
	/** ���� **/
	localparam integer kernal_pars_n_per_clk = 64/kernal_param_data_width; // д������ʱÿclk����ľ���˲�������
	
	/** �������˲����� **/
	wire[kernal_param_data_width-1:0] in_kernal_pars[0:kernal_pars_n_per_clk-1]; // �������˲���
	wire[kernal_pars_n_per_clk-1:0] in_kernal_pars_vld_mask; // �������˲�������Ч����
	
	genvar in_kernal_pars_i;
	generate
		for(in_kernal_pars_i = 0;in_kernal_pars_i < kernal_pars_n_per_clk;in_kernal_pars_i = in_kernal_pars_i + 1)
		begin
			assign in_kernal_pars[in_kernal_pars_i] = 
				s_axis_kernal_pars_data[(in_kernal_pars_i+1)*kernal_param_data_width-1:
					in_kernal_pars_i*kernal_param_data_width];
			assign in_kernal_pars_vld_mask[in_kernal_pars_i] = 
				s_axis_kernal_pars_keep[in_kernal_pars_i*kernal_param_data_width/8];
		end
	endgenerate
	
	/** ������д������ **/
	// д������AXIS����
	wire[kernal_param_data_width*9-1:0] m_axis_buf_wt_data;
	wire m_axis_buf_wt_last; // ��ʾ��ͨ������˵����1��ͨ��
	wire m_axis_buf_wt_user; // ��ǰ��ͨ��������Ƿ���Ч
	wire m_axis_buf_wt_valid;
	wire m_axis_buf_wt_ready;
	// ��ͨ������˲�������
	reg[kernal_param_data_width-1:0] single_chn_kernal_pars_buffer[0:7]; // ������
	reg[8:0] single_chn_kernal_pars_saved_vec; // �������(������)
	reg[kernal_pars_n_per_clk-1:0] single_chn_kernal_pars_item_sel_cur; // ��ǰ��ѡ��(������)
	wire[kernal_pars_n_per_clk-1:0] single_chn_kernal_pars_item_sel_nxt; // ��һ��ѡ��(������)
	wire last_kernal_pars_item; // ���1������˲���(��־)
	wire[kernal_param_data_width-1:0] single_chn_kernal_pars_data_selected; // ѡ��ľ���˲���������
	
	// ��������: s_axis_kernal_pars_valid & m_axis_buf_wt_ready & (single_chn_kernal_pars_item_sel_cur[kernal_pars_n_per_clk-1]
	//     | (s_axis_kernal_pars_last & ((single_chn_kernal_pars_item_sel_nxt & in_kernal_pars_vld_mask)
	//         == {kernal_pars_n_per_clk{1'b0}})))
	assign s_axis_kernal_pars_ready = m_axis_buf_wt_ready & (single_chn_kernal_pars_item_sel_cur[kernal_pars_n_per_clk-1] | 
		// s_axis_kernal_pars_last & ((single_chn_kernal_pars_item_sel_nxt & in_kernal_pars_vld_mask)
		//     == {kernal_pars_n_per_clk{1'b0}})
		(s_axis_kernal_pars_last & (~(|(single_chn_kernal_pars_item_sel_nxt & in_kernal_pars_vld_mask)))));
	
	assign m_axis_buf_wt_data = {
		{(kernal_param_data_width*4){kernal_type}},
		{(kernal_param_data_width){1'b1}},
		{(kernal_param_data_width*4){kernal_type}}
	} & {
		single_chn_kernal_pars_data_selected,
		single_chn_kernal_pars_buffer[7],
		single_chn_kernal_pars_buffer[6],
		single_chn_kernal_pars_buffer[5],
		// ���������Ϊ1x1ʱ������x2y2���Ĳ���
		kernal_type ? single_chn_kernal_pars_buffer[4]:single_chn_kernal_pars_data_selected,
		single_chn_kernal_pars_buffer[3],
		single_chn_kernal_pars_buffer[2],
		single_chn_kernal_pars_buffer[1],
		single_chn_kernal_pars_buffer[0]
	};
	assign m_axis_buf_wt_last = last_kernal_pars_item;
	assign m_axis_buf_wt_user = s_axis_kernal_pars_user;
	// ��������: s_axis_kernal_pars_valid & m_axis_buf_wt_ready & 
	//     (single_chn_kernal_pars_saved_vec[8] | (~kernal_type))
	assign m_axis_buf_wt_valid = s_axis_kernal_pars_valid & 
		(single_chn_kernal_pars_saved_vec[8] | last_kernal_pars_item | (~kernal_type));
	
	assign single_chn_kernal_pars_item_sel_nxt = {
		single_chn_kernal_pars_item_sel_cur[((kernal_pars_n_per_clk == 1) ? 0:(kernal_pars_n_per_clk-2)):0], 
		(kernal_pars_n_per_clk == 1) | single_chn_kernal_pars_item_sel_cur[kernal_pars_n_per_clk-1]
	};
	
	assign last_kernal_pars_item = s_axis_kernal_pars_last & 
		// single_chn_kernal_pars_item_sel_cur[kernal_pars_n_per_clk-1]
		//     | ((single_chn_kernal_pars_item_sel_nxt & in_kernal_pars_vld_mask) == {kernal_pars_n_per_clk{1'b0}})
		(single_chn_kernal_pars_item_sel_cur[kernal_pars_n_per_clk-1]
			| (~(|(single_chn_kernal_pars_item_sel_nxt & in_kernal_pars_vld_mask))));
	
	assign single_chn_kernal_pars_data_selected = 
		(in_kernal_pars[0] & 
			{kernal_param_data_width{single_chn_kernal_pars_item_sel_cur[0]}}) | 
		(in_kernal_pars[(kernal_param_data_width <= 32) ? 1:0] & 
			{kernal_param_data_width{single_chn_kernal_pars_item_sel_cur[(kernal_param_data_width <= 32) ? 1:0]}}) | 
		(in_kernal_pars[(kernal_param_data_width <= 16) ? 2:0] & 
			{kernal_param_data_width{single_chn_kernal_pars_item_sel_cur[(kernal_param_data_width <= 16) ? 2:0]}}) | 
		(in_kernal_pars[(kernal_param_data_width <= 16) ? 3:0] & 
			{kernal_param_data_width{single_chn_kernal_pars_item_sel_cur[(kernal_param_data_width <= 16) ? 3:0]}}) | 
		(in_kernal_pars[(kernal_param_data_width == 8) ? 4:0] & 
			{kernal_param_data_width{single_chn_kernal_pars_item_sel_cur[(kernal_param_data_width == 8) ? 4:0]}}) | 
		(in_kernal_pars[(kernal_param_data_width == 8) ? 5:0] & 
			{kernal_param_data_width{single_chn_kernal_pars_item_sel_cur[(kernal_param_data_width == 8) ? 5:0]}}) | 
		(in_kernal_pars[(kernal_param_data_width == 8) ? 6:0] & 
			{kernal_param_data_width{single_chn_kernal_pars_item_sel_cur[(kernal_param_data_width == 8) ? 6:0]}}) | 
		(in_kernal_pars[(kernal_param_data_width == 8) ? 7:0] & 
			{kernal_param_data_width{single_chn_kernal_pars_item_sel_cur[(kernal_param_data_width == 8) ? 7:0]}});
	
	// ��ͨ������˲���������
	genvar single_chn_kernal_pars_buffer_i;
	generate
		for(single_chn_kernal_pars_buffer_i = 0;single_chn_kernal_pars_buffer_i < 8;
			single_chn_kernal_pars_buffer_i = single_chn_kernal_pars_buffer_i + 1)
		begin
			always @(posedge clk)
			begin
				if(s_axis_kernal_pars_valid & m_axis_buf_wt_ready & 
					kernal_type & single_chn_kernal_pars_saved_vec[single_chn_kernal_pars_buffer_i])
				begin
					single_chn_kernal_pars_buffer[single_chn_kernal_pars_buffer_i] <= 
						# simulation_delay single_chn_kernal_pars_data_selected;
				end
			end
		end
	endgenerate
	
	// ��ͨ������˲����������(������)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			single_chn_kernal_pars_saved_vec <= 9'b0_0000_0001;
		else if(s_axis_kernal_pars_valid & m_axis_buf_wt_ready)
			// (last_kernal_pars_item | (~kernal_type)) ? 9'b0_0000_0001:
			//     {single_chn_kernal_pars_saved_vec[7:0], single_chn_kernal_pars_saved_vec[8]}
			single_chn_kernal_pars_saved_vec <= # simulation_delay 
				{{8{~(last_kernal_pars_item | (~kernal_type))}} & single_chn_kernal_pars_saved_vec[7:0], 
					last_kernal_pars_item | (~kernal_type) | single_chn_kernal_pars_saved_vec[8]};
	end
	// ��ͨ������˲�����ǰ��ѡ��(������)
	generate
		if(kernal_pars_n_per_clk == 1)
		begin
			always @(*)
				single_chn_kernal_pars_item_sel_cur = 1'b1;
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					single_chn_kernal_pars_item_sel_cur <= {{(kernal_pars_n_per_clk-1){1'b0}}, 1'b1};
				else if(s_axis_kernal_pars_valid & m_axis_buf_wt_ready)
					// last_kernal_pars_item ? {{(kernal_pars_n_per_clk-1){1'b0}}, 1'b1}:
					//     {single_chn_kernal_pars_item_sel_cur[kernal_pars_n_per_clk-2:0], 
					//         single_chn_kernal_pars_item_sel_cur[kernal_pars_n_per_clk-1]}
					single_chn_kernal_pars_item_sel_cur <= # simulation_delay 
						{{(kernal_pars_n_per_clk-1){~last_kernal_pars_item}} & 
							single_chn_kernal_pars_item_sel_cur[kernal_pars_n_per_clk-2:0], 
							last_kernal_pars_item | single_chn_kernal_pars_item_sel_cur[kernal_pars_n_per_clk-1]};
			end
		end
	endgenerate
	
	/** ���������� **/
	// д�˿�
	wire kernal_pars_buffer_wen; // дʹ��
	reg kernal_pars_buffer_full_n; // ����־
	reg[kernal_pars_buffer_n-1:0] kernal_pars_buffer_wptr; // дָ��
	// ���˿�
	wire kernal_pars_buffer_ren; // ��ʹ��
	reg kernal_pars_buffer_empty_n; // �ձ�־
	reg[kernal_pars_buffer_n-1:0] kernal_pars_buffer_rptr; // ��ָ��
	reg[clogb2(kernal_pars_buffer_n-1):0] kernal_pars_buffer_rd_sel; // ��Ƭѡ
	wire[clogb2(kernal_pars_buffer_n-1):0] kernal_pars_buffer_rd_sel_incr; // ��Ƭѡ����
	reg[clogb2(kernal_pars_buffer_n-1):0] kernal_pars_buffer_rd_sel_d; // �ӳ�1clk�Ķ�Ƭѡ
	// �洢����
	reg[clogb2(kernal_pars_buffer_n):0] kernal_pars_buffer_str_n_cur; // ��ǰ�Ķ�ͨ������˴洢����
	wire[clogb2(kernal_pars_buffer_n):0] kernal_pars_buffer_str_n_nxt; // ��һ�Ķ�ͨ������˴洢����
	wire[clogb2(kernal_pars_buffer_n):0] kernal_pars_buffer_str_n_incr; // ��ͨ������˴洢��������
	
	assign m_axis_buf_wt_ready = kernal_pars_buffer_full_n;
	
	assign kernal_pars_buffer_wen = m_axis_buf_wt_valid & m_axis_buf_wt_last;
	assign kernal_pars_buffer_ren = kernal_pars_buf_fifo_ren;
	assign kernal_pars_buf_fifo_empty_n = kernal_pars_buffer_empty_n;
	
	assign kernal_pars_buffer_rd_sel_incr = (kernal_pars_buffer_rd_sel >= (kernal_pars_buffer_n - kernal_prl_n)) ? 
		// kernal_prl_n - kernal_pars_buffer_n
		((~(kernal_pars_buffer_n - kernal_prl_n)) + 1):
		kernal_prl_n;
	
	assign kernal_pars_buffer_str_n_nxt = kernal_pars_buffer_str_n_cur + kernal_pars_buffer_str_n_incr;
	assign kernal_pars_buffer_str_n_incr = 
		// -kernal_prl_n
		({kernal_pars_buffer_wen & kernal_pars_buffer_full_n, kernal_pars_buffer_ren & kernal_pars_buffer_empty_n}
			== 2'b01) ? ((~kernal_prl_n) + 1):
		// -kernal_prl_n + 1
		({kernal_pars_buffer_wen & kernal_pars_buffer_full_n, kernal_pars_buffer_ren & kernal_pars_buffer_empty_n}
			== 2'b11) ? ((~kernal_prl_n) + 2):
						1;
	
	// ����˲���������дָ��
	generate
		if(kernal_pars_buffer_n == 1)
		begin
			always @(*)
				kernal_pars_buffer_wptr = 1'b1;
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					kernal_pars_buffer_wptr <= {{(kernal_pars_buffer_n-1){1'b0}}, 1'b1};
				else if(kernal_pars_buffer_wen & kernal_pars_buffer_full_n)
					kernal_pars_buffer_wptr <= # simulation_delay 
						{kernal_pars_buffer_wptr[kernal_pars_buffer_n-2:0], kernal_pars_buffer_wptr[kernal_pars_buffer_n-1]};
			end
		end
	endgenerate
	
	// ����˲�������������־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			kernal_pars_buffer_full_n <= 1'b1;
		else if((kernal_pars_buffer_wen & kernal_pars_buffer_full_n) | (kernal_pars_buffer_ren & kernal_pars_buffer_empty_n))
			kernal_pars_buffer_full_n <= # simulation_delay kernal_pars_buffer_str_n_nxt != kernal_pars_buffer_n;
	end
	// ����˲����������ձ�־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			kernal_pars_buffer_empty_n <= 1'b0;
		else if((kernal_pars_buffer_wen & kernal_pars_buffer_full_n) | (kernal_pars_buffer_ren & kernal_pars_buffer_empty_n))
			kernal_pars_buffer_empty_n <= # simulation_delay kernal_pars_buffer_str_n_nxt >= kernal_prl_n;
	end
	
	// ��ǰ�Ķ�ͨ������˴洢����
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			kernal_pars_buffer_str_n_cur <= 0;
		else if((kernal_pars_buffer_wen & kernal_pars_buffer_full_n) | (kernal_pars_buffer_ren & kernal_pars_buffer_empty_n))
			kernal_pars_buffer_str_n_cur <= # simulation_delay kernal_pars_buffer_str_n_nxt;
	end
	
	// ����˲�����������ָ��
	generate
		if(kernal_pars_buffer_n == kernal_prl_n)
		begin
			always @(*)
				kernal_pars_buffer_rptr = {kernal_pars_buffer_n{1'b1}};
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					kernal_pars_buffer_rptr <= {{(kernal_pars_buffer_n-kernal_prl_n){1'b0}}, 
						{kernal_prl_n{1'b1}}};
				else if(kernal_pars_buffer_ren & kernal_pars_buffer_empty_n)
					// ѭ������kernal_prl_nλ
					kernal_pars_buffer_rptr <= # simulation_delay 
						(kernal_pars_buffer_rptr << kernal_prl_n) | 
						(kernal_pars_buffer_rptr >> (kernal_pars_buffer_n-kernal_prl_n));
			end
		end
	endgenerate
	
	// ����˲�����������Ƭѡ
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			kernal_pars_buffer_rd_sel <= 0;
		else if(kernal_pars_buffer_ren & kernal_pars_buffer_empty_n)
			kernal_pars_buffer_rd_sel <= # simulation_delay kernal_pars_buffer_rd_sel + kernal_pars_buffer_rd_sel_incr;
	end
	// �ӳ�1clk�ľ���˲�����������Ƭѡ
	always @(posedge clk)
	begin
		if(kernal_pars_buf_mem_buf_ren_s0)
			kernal_pars_buffer_rd_sel_d <= # simulation_delay kernal_pars_buffer_rd_sel;
	end
	
	/** ��ͨ���������Ϣfifo **/
	reg kernal_msg_fifo[kernal_pars_buffer_n-1:0]; // fifo�洢ʵ��
	wire[kernal_pars_buffer_n-1:0] kernal_vld_vec; // ��ͨ���������Ч��־����
	reg[kernal_pars_buffer_n-1:0] kernal_vld_vec_d; // �ӳ�1clk�Ķ�ͨ���������Ч��־����
	
	genvar kernal_msg_fifo_i;
	generate
		for(kernal_msg_fifo_i = 0;kernal_msg_fifo_i < kernal_pars_buffer_n;kernal_msg_fifo_i = kernal_msg_fifo_i + 1)
		begin
			assign kernal_vld_vec[kernal_msg_fifo_i] = kernal_msg_fifo[kernal_msg_fifo_i];
			
			// ��ͨ���������Ч��־
			always @(posedge clk)
			begin
				if(kernal_pars_buffer_wen & kernal_pars_buffer_full_n & kernal_pars_buffer_wptr[kernal_msg_fifo_i])
					kernal_msg_fifo[kernal_msg_fifo_i] <= # simulation_delay m_axis_buf_wt_user;
			end
		end
	endgenerate
	
	// �ӳ�1clk�Ķ�ͨ���������Ч��־����
	always @(posedge clk)
	begin
		if(kernal_pars_buf_mem_buf_ren_s0)
			kernal_vld_vec_d <= # simulation_delay kernal_vld_vec;
	end
	
	/** ������MEM **/
	// ����˲���������MEMд�˿�
	wire[kernal_pars_buffer_n-1:0] kernal_pars_buffer_mem_wen;
	reg[clogb2(max_feature_map_chn_n-1):0] kernal_pars_buffer_mem_waddr; // ÿ��д��ַ��Ӧ1����ͨ�������
	wire[kernal_param_data_width*9-1:0] kernal_pars_buffer_mem_din;
	// ����˲���������MEM���˿�
	wire[kernal_pars_buffer_n-1:0] kernal_pars_buffer_mem_ren;
	wire[clogb2(max_feature_map_chn_n-1):0] kernal_pars_buffer_mem_raddr; // ÿ������ַ��Ӧ1����ͨ�������
	wire[kernal_param_data_width*9-1:0] kernal_pars_buffer_mem_dout[0:kernal_pars_buffer_n-1];
	wire[kernal_pars_buffer_n*kernal_param_data_width*9-1:0] kernal_pars_buffer_mem_dout_flattened;
	wire[kernal_prl_n*kernal_param_data_width*9-1:0] kernal_pars_buffer_mem_dout_reorg;
	reg[kernal_prl_n*kernal_param_data_width*9-1:0] kernal_pars_buffer_mem_dout_reorg_d;
	
	assign kernal_pars_buffer_mem_wen = {kernal_pars_buffer_n{m_axis_buf_wt_valid & m_axis_buf_wt_ready}} & 
		kernal_pars_buffer_wptr;
	assign kernal_pars_buffer_mem_din = m_axis_buf_wt_data;
	
	assign kernal_pars_buffer_mem_ren = {kernal_pars_buffer_n{kernal_pars_buf_mem_buf_ren_s0}} & kernal_pars_buffer_rptr;
	assign kernal_pars_buffer_mem_raddr = kernal_pars_buf_mem_buf_raddr[clogb2(max_feature_map_chn_n-1):0];
	assign kernal_pars_buf_mem_buf_dout = kernal_pars_buffer_mem_dout_reorg_d;
	
	// ѭ������(kernal_pars_buffer_rd_sel_d * kernal_param_data_width * 9)λ, ������kernal_pars_buffer_n�����
	assign kernal_pars_buffer_mem_dout_reorg = (kernal_pars_buffer_rd_sel_d >= kernal_pars_buffer_n) ? 
		{(kernal_param_data_width*9*kernal_prl_n){1'bx}}: // not care!
		((kernal_pars_buffer_mem_dout_flattened >> (kernal_pars_buffer_rd_sel_d * kernal_param_data_width * 9)) | 
			(kernal_pars_buffer_mem_dout_flattened << 
				((kernal_pars_buffer_n - kernal_pars_buffer_rd_sel_d) * kernal_param_data_width * 9)));
	
	// չƽ�Ķ�����
	genvar kernal_pars_buffer_mem_dout_flattened_i;
	generate
		for(kernal_pars_buffer_mem_dout_flattened_i = 0;kernal_pars_buffer_mem_dout_flattened_i < kernal_pars_buffer_n;
			kernal_pars_buffer_mem_dout_flattened_i = kernal_pars_buffer_mem_dout_flattened_i + 1)
		begin
			assign kernal_pars_buffer_mem_dout_flattened[(kernal_pars_buffer_mem_dout_flattened_i+1)*kernal_param_data_width*9-1:
				kernal_pars_buffer_mem_dout_flattened_i*kernal_param_data_width*9] = 
				kernal_pars_buffer_mem_dout[kernal_pars_buffer_mem_dout_flattened_i] & 
				// ���ݶ�ͨ���������Ч��־�Զ����ݽ����������㴦��
				{(kernal_param_data_width*9){kernal_vld_vec_d[kernal_pars_buffer_mem_dout_flattened_i]}};
		end
	endgenerate
	
	// ����˲���������MEMд��ַ
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			kernal_pars_buffer_mem_waddr <= 0;
		else if(m_axis_buf_wt_valid & m_axis_buf_wt_ready)
			// m_axis_buf_wt_last ? 0:(kernal_pars_buffer_mem_waddr + 1)
			kernal_pars_buffer_mem_waddr <= # simulation_delay 
				{(clogb2(max_feature_map_chn_n-1)+1){~m_axis_buf_wt_last}} & (kernal_pars_buffer_mem_waddr + 1);
	end
	
	// �ӳ�1clk��������ľ���˲���������MEM������
	always @(posedge clk)
	begin
		if(kernal_pars_buf_mem_buf_ren_s1)
			kernal_pars_buffer_mem_dout_reorg_d <= # simulation_delay kernal_pars_buffer_mem_dout_reorg;
	end
	
	// ����MEM
	genvar kernal_pars_buf_mem_i;
	generate
		for(kernal_pars_buf_mem_i = 0;kernal_pars_buf_mem_i < kernal_pars_buffer_n;
			kernal_pars_buf_mem_i = kernal_pars_buf_mem_i + 1)
		begin
			kernal_params_buffer #(
				.kernal_param_data_width(kernal_param_data_width),
				.max_feature_map_chn_n(max_feature_map_chn_n),
				.simulation_delay(simulation_delay)
			)kernal_params_buffer_mem_u(
				.clk(clk),
				
				.buffer_wen(kernal_pars_buffer_mem_wen[kernal_pars_buf_mem_i]),
				.buffer_waddr({{(15-clogb2(max_feature_map_chn_n-1)){1'b0}}, kernal_pars_buffer_mem_waddr}),
				.buffer_din(kernal_pars_buffer_mem_din),
				
				.buffer_ren(kernal_pars_buffer_mem_ren[kernal_pars_buf_mem_i]),
				.buffer_raddr({{(15-clogb2(max_feature_map_chn_n-1)){1'b0}}, kernal_pars_buffer_mem_raddr}),
				.buffer_dout(kernal_pars_buffer_mem_dout[kernal_pars_buf_mem_i])
			);
		end
	endgenerate
	
endmodule
