`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXIS��ͨ��������������

����:
                         {��ͨ��������������}
		                    ################ ---> �������ͼ������
		
		                    ################
		
					                      |----|
					                      V    |
�����ͨ���ۼ��м��� ---> ################   |
				        |            |         |
				        |            |         |
				        |            ----{+}----
		                |
					    |                 |----|
					    |                 V    |
		               ---> ################   |
				                     |         |
				                     |         |
				                     ----{+}----

д��ͨ��������������ÿ��ѡ��1~kernal_prl_n������, ���������������ͼ���һ��ͨ��ʱ����ѡ������kernal_prl_n������
����ͨ��������������ÿ��ѡ��1������

�������ͼ������ -> 
{
	      {ͨ��#0��#0}             {ͨ��#1��#0}       ...       {ͨ��#(�˲�����-1)��#0}
	      {ͨ��#0��#1}             {ͨ��#1��#1}       ...       {ͨ��#(�˲�����-1)��#1}
	                                     :
							             :
	{ͨ��#0��#(���ͼ�߶�-1)} {ͨ��#1��#(���ͼ�߶�-1)} ... {ͨ��#(�˲�����-1)��#(���ͼ�߶�-1)}
}
{
	      {ͨ��#(�˲�����)��#0}             {ͨ��#(�˲�����+1)��#0}        ...        {ͨ��#(�˲�����*2-1)��#0}
	      {ͨ��#(�˲�����)��#1}             {ͨ��#(�˲�����+1)��#1}        ...        {ͨ��#(�˲�����*2-1)��#1}
	                                                    :
							                            :
	{ͨ��#(�˲�����)��#(���ͼ�߶�-1)} {ͨ��#(�˲�����+1)��#(���ͼ�߶�-1)} ... {ͨ��#(�˲�����*2-1)��#(���ͼ�߶�-1)}
} ... ... {

		  {ͨ��#(���ͨ����-?)��#0}        ...        {ͨ��#(���ͨ����-1)��#0}
	      {ͨ��#(���ͨ����-?)��#1}        ...        {ͨ��#(���ͨ����-1)��#1}
	                                        :
							                :
	{ͨ��#(���ͨ����-?)��#(���ͼ�߶�-1)} ... {ͨ��#(���ͨ����-1)��#(���ͼ�߶�-1)}
}

$> 	(���ͨ����-?) = floor(����˸���/�˲�����) * �˲����� - ((����˸��� % �˲�����) == 0) * �˲�����

ע�⣺
��ͨ���������������(out_buffer_n)����>=��ͨ������˵Ĳ��и���(kernal_prl_n)

Э��:
AXIS MASTER/SLAVE

����: �¼�ҫ
����: 2024/12/25
********************************************************************/


module axis_conv_out_buffer #(
	parameter integer ft_ext_width = 32, // ��������չλ��(16 | 32)
	parameter integer ft_vld_width = 20, // ��������Чλ��(����<=ft_ext_width)
	parameter integer kernal_prl_n = 4, // ��ͨ������˵Ĳ��и���(1 | 2 | 4 | 8 | 16)
	parameter integer out_buffer_n = 8, // ��ͨ���������������
	parameter integer max_feature_map_w = 512, // ������������ͼ���
	parameter integer max_feature_map_h = 512, // ������������ͼ�߶�
	parameter integer max_kernal_n = 512, // ���ľ���˸���
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
	input wire clk,
	input wire rst_n,
	
	// ʹ��
	input wire en_conv_cal, // �Ƿ�ʹ�ܾ������
	
	// ����ʱ����
	input wire kernal_type, // ���������(1'b0 -> 1x1, 1'b1 -> 3x3)
	input wire[1:0] padding_en, // �������ʹ��(�������������Ϊ3x3ʱ����, {��, ��})
	input wire[15:0] o_ft_map_w, // �������ͼ��� - 1
	input wire[15:0] o_ft_map_h, // �������ͼ�߶� - 1
	input wire[15:0] kernal_n, // ����˸��� - 1
	
	// �����ͨ���ۼ��м�������(AXIS�ӻ�)
	// {��#(m-1)���, ..., ��#1���, ��#0���}
	// ÿ���м�������ft_vld_widthλ��Ч
	input wire[ft_ext_width*kernal_prl_n-1:0] s_axis_mid_res_data,
	input wire s_axis_mid_res_last, // ��ʾ��β
	input wire s_axis_mid_res_user, // ��ʾ��ǰ�����1����
	input wire s_axis_mid_res_valid,
	output wire s_axis_mid_res_ready,
	
	// �������ͼ���������(AXIS����)
	// ����ͼ���ݽ���ft_vld_widthλ��Ч
	output wire[ft_ext_width-1:0] m_axis_ft_out_data,
	output wire[15:0] m_axis_ft_out_user, // ��ǰ������������ڵ�ͨ����
	output wire m_axis_ft_out_last, // ��ʾ��β
	output wire m_axis_ft_out_valid,
	input wire m_axis_ft_out_ready
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
	
	/** �����ͨ���ۼ��м���дλ�� **/
	reg[clogb2(max_feature_map_w-1):0] mul_chn_conv_mid_res_wt_pos_x; // x����
	reg mul_chn_conv_mid_res_wt_at_first_batch; // ���ڵ�1��(��־)
	reg[clogb2(max_feature_map_h-1):0] mul_chn_conv_mid_res_wt_pos_y; // y����
	wire mul_chn_conv_mid_res_wt_at_last_row; // �������1��(��־)
	reg[clogb2(max_kernal_n/kernal_prl_n-1):0] mul_chn_conv_mid_res_wt_pos_chn_grp; // ͨ�����
	wire mul_chn_conv_mid_res_wt_at_last_chn_grp; // �������1��ͨ����(��־)
	reg[clogb2(kernal_prl_n):0] mul_chn_conv_mid_res_wt_last_chn_grp_vld_n; // ���1��ͨ�������Чͨ������
	reg[kernal_prl_n-1:0] mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask; // ���1��ͨ�������Чͨ������
	
	assign mul_chn_conv_mid_res_wt_at_last_row = mul_chn_conv_mid_res_wt_pos_y == o_ft_map_h[clogb2(max_feature_map_h-1):0];
	assign mul_chn_conv_mid_res_wt_at_last_chn_grp = 
		// ÿ��ͨ�������kernal_prl_n��ͨ��
		mul_chn_conv_mid_res_wt_pos_chn_grp == kernal_n[clogb2(max_kernal_n-1):clogb2(kernal_prl_n)];
	
	// ���1��ͨ�������Чͨ������
	generate
		if(kernal_prl_n > 1)
		begin
			always @(posedge clk)
			begin
				if(en_conv_cal)
					mul_chn_conv_mid_res_wt_last_chn_grp_vld_n <= # simulation_delay 
						kernal_n[clogb2(kernal_prl_n-1):0] + 1'b1;
			end
		end
		else
		begin
			always @(*)
				mul_chn_conv_mid_res_wt_last_chn_grp_vld_n = 1'b1;
		end
	endgenerate
	
	// ���1��ͨ�������Чͨ������
	genvar mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask_i;
	generate
		if(kernal_prl_n > 1)
		begin
			for(mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask_i = 0;mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask_i < kernal_prl_n;
				mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask_i = mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask_i + 1)
			begin
				always @(posedge clk)
				begin
					if(en_conv_cal)
						mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask[mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask_i] <= 
							# simulation_delay kernal_n[clogb2(kernal_prl_n-1):0] >= mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask_i;
				end
			end
		end
		else
		begin
			always @(*)
				mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask = 1'b1;
		end
	endgenerate
	
	// ��ǰд�����ͨ���ۼ��м�����x����
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_mid_res_wt_pos_x <= 0;
		else if(s_axis_mid_res_valid & s_axis_mid_res_ready)
			mul_chn_conv_mid_res_wt_pos_x <= # simulation_delay 
				// s_axis_mid_res_last ? 0:(mul_chn_conv_mid_res_wt_pos_x + 1)
				{(clogb2(max_feature_map_w-1)+1){~s_axis_mid_res_last}} & 
				(mul_chn_conv_mid_res_wt_pos_x + 1);
	end
	
	// ��ǰд�����ͨ���ۼ��м������ڵ�1����־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_mid_res_wt_at_first_batch <= 1'b1;
		else if(s_axis_mid_res_valid & s_axis_mid_res_ready & s_axis_mid_res_last)
			mul_chn_conv_mid_res_wt_at_first_batch <= # simulation_delay s_axis_mid_res_user;
	end
	
	// ��ǰд�����ͨ���ۼ��м�����y����
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_mid_res_wt_pos_y <= 0;
		else if(s_axis_mid_res_valid & s_axis_mid_res_ready & s_axis_mid_res_last 
			& s_axis_mid_res_user)
			mul_chn_conv_mid_res_wt_pos_y <= # simulation_delay 
				// mul_chn_conv_mid_res_wt_at_last_row ? 0:(mul_chn_conv_mid_res_wt_pos_y + 1)
				{(clogb2(max_feature_map_h-1)+1){~mul_chn_conv_mid_res_wt_at_last_row}} & 
				(mul_chn_conv_mid_res_wt_pos_y + 1);
	end
	
	// ��ǰд�����ͨ���ۼ��м�����ͨ�����
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_mid_res_wt_pos_chn_grp <= 0;
		else if(s_axis_mid_res_valid & s_axis_mid_res_ready & s_axis_mid_res_last 
			& s_axis_mid_res_user & mul_chn_conv_mid_res_wt_at_last_row)
			mul_chn_conv_mid_res_wt_pos_chn_grp <= # simulation_delay 
				// mul_chn_conv_mid_res_wt_at_last_chn_grp ? 0:(mul_chn_conv_mid_res_wt_pos_chn_grp + 1)
				{(clogb2(max_kernal_n/kernal_prl_n-1)+1){~mul_chn_conv_mid_res_wt_at_last_chn_grp}} & 
				(mul_chn_conv_mid_res_wt_pos_chn_grp + 1);
	end
	
    /** ��ͨ��������������fifo���� **/
	// fifo�洢����
	reg[clogb2(out_buffer_n):0] mul_chn_conv_res_buf_fifo_str_n; // ��ǰ�Ĵ洢����
	wire[clogb2(out_buffer_n):0] mul_chn_conv_res_buf_fifo_str_n_to_add; // ��ǰд��ʱ���ӵĴ洢����
	// fifoд�˿�
	wire mul_chn_conv_res_buf_fifo_wen;
	wire mul_chn_conv_res_buf_fifo_full_n;
	reg[clogb2(out_buffer_n-1):0] mul_chn_conv_res_buf_fifo_wsel_cur; // ��ǰ��д������ʼ���
	wire[clogb2(out_buffer_n-1)+1:0] mul_chn_conv_res_buf_fifo_wsel_add_res; // ��һд������ʼ���(�������)
	wire[clogb2(out_buffer_n-1):0] mul_chn_conv_res_buf_fifo_wsel_nxt; // ��һд������ʼ���
	// fifo���˿�
	wire mul_chn_conv_res_buf_fifo_ren;
	wire mul_chn_conv_res_buf_fifo_empty_n;
	reg[out_buffer_n-1:0] mul_chn_conv_res_buf_fifo_rptr;
	
	// ��������: s_axis_mid_res_valid & mul_chn_conv_res_buf_fifo_full_n
	assign s_axis_mid_res_ready = mul_chn_conv_res_buf_fifo_full_n;
	
	// ��������: s_axis_mid_res_valid & mul_chn_conv_res_buf_fifo_full_n & s_axis_mid_res_last & s_axis_mid_res_user
	assign mul_chn_conv_res_buf_fifo_wen = s_axis_mid_res_valid & s_axis_mid_res_last & s_axis_mid_res_user;
	
	// ����ʣ��kernal_prl_n�������дʱ����
	assign mul_chn_conv_res_buf_fifo_full_n = mul_chn_conv_res_buf_fifo_str_n <= (out_buffer_n - kernal_prl_n);
	
	// ���ٴ洢��1������ʱ�ǿ�
	assign mul_chn_conv_res_buf_fifo_empty_n = |mul_chn_conv_res_buf_fifo_str_n;
	
	assign mul_chn_conv_res_buf_fifo_str_n_to_add = mul_chn_conv_mid_res_wt_at_last_chn_grp ? 
		mul_chn_conv_mid_res_wt_last_chn_grp_vld_n:
		kernal_prl_n;
	
	assign mul_chn_conv_res_buf_fifo_wsel_add_res = 
		mul_chn_conv_res_buf_fifo_wsel_cur + mul_chn_conv_res_buf_fifo_str_n_to_add;
	assign mul_chn_conv_res_buf_fifo_wsel_nxt = 
		(mul_chn_conv_res_buf_fifo_wsel_add_res >= out_buffer_n) ? 
			(mul_chn_conv_res_buf_fifo_wsel_add_res - out_buffer_n):mul_chn_conv_res_buf_fifo_wsel_add_res;
	
	// ��ǰ�Ĵ洢����
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_res_buf_fifo_str_n <= 0;
		else if((mul_chn_conv_res_buf_fifo_wen & mul_chn_conv_res_buf_fifo_full_n) | 
			(mul_chn_conv_res_buf_fifo_ren & mul_chn_conv_res_buf_fifo_empty_n))
			mul_chn_conv_res_buf_fifo_str_n <= # simulation_delay 
				mul_chn_conv_res_buf_fifo_str_n
				+ ({(clogb2(out_buffer_n)+1){mul_chn_conv_res_buf_fifo_wen & mul_chn_conv_res_buf_fifo_full_n}} & 
					mul_chn_conv_res_buf_fifo_str_n_to_add)
				+ {(clogb2(out_buffer_n)+1){mul_chn_conv_res_buf_fifo_ren & mul_chn_conv_res_buf_fifo_empty_n}};
	end
	
	// ��ǰ��д������ʼ���
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_res_buf_fifo_wsel_cur <= 0;
		else if(mul_chn_conv_res_buf_fifo_wen & mul_chn_conv_res_buf_fifo_full_n)
			mul_chn_conv_res_buf_fifo_wsel_cur <= # simulation_delay mul_chn_conv_res_buf_fifo_wsel_nxt;
	end
	
	// ��ָ��
	generate
		if(out_buffer_n > 1)
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					mul_chn_conv_res_buf_fifo_rptr <= {{(out_buffer_n-1){1'b0}}, 1'b1};
				else if(mul_chn_conv_res_buf_fifo_ren & mul_chn_conv_res_buf_fifo_empty_n)
					mul_chn_conv_res_buf_fifo_rptr <= # simulation_delay 
						{mul_chn_conv_res_buf_fifo_rptr[out_buffer_n-2:0], mul_chn_conv_res_buf_fifo_rptr[out_buffer_n-1]};
			end
		end
		else
		begin
			always @(*)
				mul_chn_conv_res_buf_fifo_rptr = 1'b1;
		end
	endgenerate
	
	/** д��ͨ�������������� **/
	wire[ft_vld_width*out_buffer_n-1:0] mid_res_flattened; // չƽ�ľ���м���
	wire[ft_vld_width*out_buffer_n-1:0] mid_res_shifted; // ��λ�ľ���м���
	wire[ft_vld_width-1:0] mid_res_to_wt[0:out_buffer_n-1]; // ��д�뻺�����ľ���м���
	wire[out_buffer_n-1:0] mul_chn_conv_res_buf_fifo_wmask_org; // ��ʼд����
	wire[out_buffer_n-1:0] mul_chn_conv_res_buf_fifo_wmask; // д����
	
	genvar mid_res_flattened_i;
	generate
		for(mid_res_flattened_i = 0;mid_res_flattened_i < out_buffer_n;mid_res_flattened_i = mid_res_flattened_i + 1)
		begin
			assign mid_res_flattened[(mid_res_flattened_i+1)*ft_vld_width-1:
				mid_res_flattened_i*ft_vld_width] = 
				(mid_res_flattened_i < kernal_prl_n) ? 
				s_axis_mid_res_data[mid_res_flattened_i*ft_ext_width+ft_vld_width-1:
					mid_res_flattened_i*ft_ext_width]:
				{ft_vld_width{1'bx}};
		end
	endgenerate
	
	// ѭ������mul_chn_conv_res_buf_fifo_wsel_cur*ft_vld_widthλ, ������out_buffer_n�����
	assign mid_res_shifted = 
		(mul_chn_conv_res_buf_fifo_wsel_cur >= out_buffer_n) ? 
			{(ft_vld_width*out_buffer_n){1'bx}}:
			((mid_res_flattened << (mul_chn_conv_res_buf_fifo_wsel_cur*ft_vld_width)) | 
			(mid_res_flattened >> ((out_buffer_n - mul_chn_conv_res_buf_fifo_wsel_cur)*ft_vld_width)));
	
	genvar mid_res_to_wt_i;
	generate
		for(mid_res_to_wt_i = 0;mid_res_to_wt_i < out_buffer_n;mid_res_to_wt_i = mid_res_to_wt_i + 1)
		begin
			assign mid_res_to_wt[mid_res_to_wt_i] = mid_res_shifted[(mid_res_to_wt_i+1)*ft_vld_width-1:
				mid_res_to_wt_i*ft_vld_width];
		end
	endgenerate
	
	generate
		if(out_buffer_n == kernal_prl_n)
			assign mul_chn_conv_res_buf_fifo_wmask_org = 
				{kernal_prl_n{~mul_chn_conv_mid_res_wt_at_last_chn_grp}} | mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask;
		else
			assign mul_chn_conv_res_buf_fifo_wmask_org = {
				{(out_buffer_n-kernal_prl_n){1'b0}}, 
				{{kernal_prl_n{~mul_chn_conv_mid_res_wt_at_last_chn_grp}} | mul_chn_conv_mid_res_wt_last_chn_grp_vld_mask}
			};
	endgenerate
	
	// ѭ������mul_chn_conv_res_buf_fifo_wsel_curλ, ������out_buffer_n�����
	assign mul_chn_conv_res_buf_fifo_wmask = 
		(mul_chn_conv_res_buf_fifo_wsel_cur >= out_buffer_n) ? 
			{out_buffer_n{1'bx}}:
			((mul_chn_conv_res_buf_fifo_wmask_org << mul_chn_conv_res_buf_fifo_wsel_cur) | 
			(mul_chn_conv_res_buf_fifo_wmask_org >> (out_buffer_n - mul_chn_conv_res_buf_fifo_wsel_cur)));
	
	/** ����ͨ�������������� **/
	// ���ڸ��¾���м���(����)
	wire[out_buffer_n-1:0] conv_mid_res_updating_vec;
	// ����������ˮ�߿���
	wire mul_chn_conv_res_rd_s0_valid;
	wire mul_chn_conv_res_rd_s0_ready;
	wire mul_chn_conv_res_rd_s0_last;
	reg mul_chn_conv_res_rd_s1_valid;
	wire mul_chn_conv_res_rd_s1_ready;
	reg[ft_vld_width-1:0] mul_chn_conv_res_rd_s1_data;
	wire[clogb2(max_kernal_n-1):0] mul_chn_conv_res_rd_s1_user; // ��ǰ������������ڵ�ͨ����
	reg mul_chn_conv_res_rd_s1_last;
	reg mul_chn_conv_res_rd_s2_valid;
	wire mul_chn_conv_res_rd_s2_ready;
	reg[ft_vld_width-1:0] mul_chn_conv_res_rd_s2_data;
	reg[clogb2(max_kernal_n-1):0] mul_chn_conv_res_rd_s2_user; // ��ǰ������������ڵ�ͨ����
	reg mul_chn_conv_res_rd_s2_last;
	// �ӳ�1clk�Ķ�ͨ��������������fifo��ָ��
	reg[out_buffer_n-1:0] mul_chn_conv_res_buf_fifo_rptr_d;
	// ��ͨ����������������λ��
	reg[clogb2(max_feature_map_w-1):0] mul_chn_conv_res_rd_pos_x; // x����
	wire mul_chn_conv_res_rd_last_col; // �������1��(��־)
	reg[clogb2(max_kernal_n-1):0] mul_chn_conv_res_rd_pos_ochn; // ���ͨ����
	reg[clogb2(max_feature_map_h-1):0] mul_chn_conv_res_rd_pos_y; // y����
	// ��ͨ��������������������
	wire[ft_vld_width-1:0] mul_chn_conv_res_dout[0:out_buffer_n-1];
	wire[ft_vld_width-1:0] mul_chn_conv_res_dout_masked[0:out_buffer_n-1];
	
	generate
		if(ft_ext_width == ft_vld_width)
			assign m_axis_ft_out_data = mul_chn_conv_res_rd_s2_data;
		else
			assign m_axis_ft_out_data = {
				{(ft_ext_width-ft_vld_width){mul_chn_conv_res_rd_s2_data[ft_vld_width-1]}}, // ���з���λ��չ
				mul_chn_conv_res_rd_s2_data
			};
	endgenerate
	
	assign m_axis_ft_out_user = mul_chn_conv_res_rd_s2_user;
	assign m_axis_ft_out_last = mul_chn_conv_res_rd_s2_last;
	// ��������: mul_chn_conv_res_rd_s2_valid & m_axis_ft_out_ready
	assign m_axis_ft_out_valid = mul_chn_conv_res_rd_s2_valid;
	
	// ��������: (~(|(mul_chn_conv_res_buf_fifo_rptr & conv_mid_res_updating_vec))) & 
	//     mul_chn_conv_res_buf_fifo_empty_n & mul_chn_conv_res_rd_s0_ready & mul_chn_conv_res_rd_last_col
	assign mul_chn_conv_res_buf_fifo_ren = 
		// conv_mid_res_updating_vec[��ǰ������] == 1'b0
		(~(|(mul_chn_conv_res_buf_fifo_rptr & conv_mid_res_updating_vec))) & 
		mul_chn_conv_res_rd_last_col & mul_chn_conv_res_rd_s0_ready;
	
	assign mul_chn_conv_res_rd_s0_valid = 
		// conv_mid_res_updating_vec[��ǰ������] == 1'b0
		(~(|(mul_chn_conv_res_buf_fifo_rptr & conv_mid_res_updating_vec))) & 
		mul_chn_conv_res_buf_fifo_empty_n;
	assign mul_chn_conv_res_rd_s0_ready = (~mul_chn_conv_res_rd_s1_valid) | mul_chn_conv_res_rd_s1_ready;
	assign mul_chn_conv_res_rd_s0_last = mul_chn_conv_res_rd_last_col;
	assign mul_chn_conv_res_rd_s1_ready = (~mul_chn_conv_res_rd_s2_valid) | mul_chn_conv_res_rd_s2_ready;
	assign mul_chn_conv_res_rd_s1_user = mul_chn_conv_res_rd_pos_ochn;
	// ��������: mul_chn_conv_res_rd_s2_valid & m_axis_ft_out_ready
	assign mul_chn_conv_res_rd_s2_ready = m_axis_ft_out_ready;
	
	assign mul_chn_conv_res_rd_last_col = mul_chn_conv_res_rd_pos_x == o_ft_map_w[clogb2(max_feature_map_w-1):0];
	
	genvar mul_chn_conv_res_dout_masked_i;
	generate
		for(mul_chn_conv_res_dout_masked_i = 0;mul_chn_conv_res_dout_masked_i < out_buffer_n;
			mul_chn_conv_res_dout_masked_i = mul_chn_conv_res_dout_masked_i + 1)
		begin
			assign mul_chn_conv_res_dout_masked[mul_chn_conv_res_dout_masked_i] = 
				mul_chn_conv_res_dout[mul_chn_conv_res_dout_masked_i] & 
				{ft_vld_width{mul_chn_conv_res_buf_fifo_rptr_d[mul_chn_conv_res_dout_masked_i]}};
		end
	endgenerate
	
	// ����������ˮ�߸���valid�ź�
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_res_rd_s1_valid <= 1'b0;
		else if(mul_chn_conv_res_rd_s0_ready)
			mul_chn_conv_res_rd_s1_valid <= # simulation_delay mul_chn_conv_res_rd_s0_valid;
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_res_rd_s2_valid <= 1'b0;
		else if(mul_chn_conv_res_rd_s1_ready)
			mul_chn_conv_res_rd_s2_valid <= # simulation_delay mul_chn_conv_res_rd_s1_valid;
	end
	
	// ����������ˮ�߸�����data
	integer mul_chn_conv_res_rd_s1_data_i;
	always @(*)
	begin
		mul_chn_conv_res_rd_s1_data = {ft_vld_width{1'b0}};
		
		for(mul_chn_conv_res_rd_s1_data_i = 0;mul_chn_conv_res_rd_s1_data_i < out_buffer_n;
			mul_chn_conv_res_rd_s1_data_i = mul_chn_conv_res_rd_s1_data_i + 1)
		begin
			mul_chn_conv_res_rd_s1_data = mul_chn_conv_res_rd_s1_data | 
				mul_chn_conv_res_dout_masked[mul_chn_conv_res_rd_s1_data_i];
		end
	end
	
	always @(posedge clk)
	begin
		if(mul_chn_conv_res_rd_s1_valid & mul_chn_conv_res_rd_s1_ready)
			mul_chn_conv_res_rd_s2_data <= # simulation_delay mul_chn_conv_res_rd_s1_data;
	end
	
	// ����������ˮ�߸���user�ź�
	always @(posedge clk)
	begin
		if(mul_chn_conv_res_rd_s1_valid & mul_chn_conv_res_rd_s1_ready)
			mul_chn_conv_res_rd_s2_user <= # simulation_delay mul_chn_conv_res_rd_s1_user;
	end
	
	// ����������ˮ�߸���last�ź�
	always @(posedge clk)
	begin
		if(mul_chn_conv_res_rd_s0_valid & mul_chn_conv_res_rd_s0_ready)
			mul_chn_conv_res_rd_s1_last <= # simulation_delay mul_chn_conv_res_rd_s0_last;
	end
	
	always @(posedge clk)
	begin
		if(mul_chn_conv_res_rd_s1_valid & mul_chn_conv_res_rd_s1_ready)
			mul_chn_conv_res_rd_s2_last <= # simulation_delay mul_chn_conv_res_rd_s1_last;
	end
	
	// �ӳ�1clk�Ķ�ͨ��������������fifo��ָ��
	always @(posedge clk)
	begin
		if(mul_chn_conv_res_rd_s0_valid & mul_chn_conv_res_rd_s0_ready)
			mul_chn_conv_res_buf_fifo_rptr_d <= # simulation_delay mul_chn_conv_res_buf_fifo_rptr;
	end
	
	// ��ǰ����ͨ����������������x����
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_res_rd_pos_x <= 0;
		else if(mul_chn_conv_res_rd_s0_valid & mul_chn_conv_res_rd_s0_ready)
			mul_chn_conv_res_rd_pos_x <= # simulation_delay 
				// mul_chn_conv_res_rd_last_col ? 0:(mul_chn_conv_res_rd_pos_x + 1)
				{(clogb2(max_feature_map_w-1)+1){~mul_chn_conv_res_rd_last_col}} & (mul_chn_conv_res_rd_pos_x + 1);
	end
	
	// ��ǰ����ͨ�������������������ͨ����
	generate
		if(kernal_prl_n > 1)
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					mul_chn_conv_res_rd_pos_ochn[clogb2(kernal_prl_n-1):0] <= 0;
				else if(mul_chn_conv_res_rd_s1_valid & mul_chn_conv_res_rd_s1_ready & mul_chn_conv_res_rd_s1_last)
				begin
					mul_chn_conv_res_rd_pos_ochn[clogb2(kernal_prl_n-1):0] <= # simulation_delay 
						// (mul_chn_conv_res_rd_pos_ochn == kernal_n) ? 
						//     0:(mul_chn_conv_res_rd_pos_ochn[clogb2(kernal_prl_n-1):0] + 1)
						{(clogb2(kernal_prl_n-1)+1){mul_chn_conv_res_rd_pos_ochn != kernal_n}} & 
							(mul_chn_conv_res_rd_pos_ochn[clogb2(kernal_prl_n-1):0] + 1);
				end
			end
			
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					mul_chn_conv_res_rd_pos_ochn[clogb2(max_kernal_n-1):clogb2(kernal_prl_n)] <= 0;
				else if(mul_chn_conv_res_rd_s1_valid & mul_chn_conv_res_rd_s1_ready & mul_chn_conv_res_rd_s1_last & 
					((&mul_chn_conv_res_rd_pos_ochn[clogb2(kernal_prl_n-1):0]) | (mul_chn_conv_res_rd_pos_ochn == kernal_n)) & 
					(mul_chn_conv_res_rd_pos_y == o_ft_map_h[clogb2(max_feature_map_h-1):0]))
					mul_chn_conv_res_rd_pos_ochn[clogb2(max_kernal_n-1):clogb2(kernal_prl_n)] <= # simulation_delay 
					// (mul_chn_conv_res_rd_pos_ochn == kernal_n) ? 
					//     0:(mul_chn_conv_res_rd_pos_ochn[clogb2(max_kernal_n-1):clogb2(kernal_prl_n)] + 1)
					{(clogb2(max_kernal_n/kernal_prl_n-1)+1){mul_chn_conv_res_rd_pos_ochn != kernal_n}} & 
						(mul_chn_conv_res_rd_pos_ochn[clogb2(max_kernal_n-1):clogb2(kernal_prl_n)] + 1);
			end
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					mul_chn_conv_res_rd_pos_ochn <= 0;
				else if(mul_chn_conv_res_rd_s1_valid & mul_chn_conv_res_rd_s1_ready & mul_chn_conv_res_rd_s1_last & 
					(mul_chn_conv_res_rd_pos_y == o_ft_map_h[clogb2(max_feature_map_h-1):0]))
					mul_chn_conv_res_rd_pos_ochn <= # simulation_delay 
					// (mul_chn_conv_res_rd_pos_ochn == kernal_n) ? 0:(mul_chn_conv_res_rd_pos_ochn + 1)
					{(clogb2(max_kernal_n-1)+1){mul_chn_conv_res_rd_pos_ochn != kernal_n}} & 
						(mul_chn_conv_res_rd_pos_ochn + 1);
			end
		end
	endgenerate
	
	// ��ǰ����ͨ����������������y����
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mul_chn_conv_res_rd_pos_y <= 0;
		else if(mul_chn_conv_res_rd_s1_valid & mul_chn_conv_res_rd_s1_ready & mul_chn_conv_res_rd_s1_last & 
			((kernal_prl_n == 1) | (&mul_chn_conv_res_rd_pos_ochn[clogb2(kernal_prl_n-1):0]) | 
				(mul_chn_conv_res_rd_pos_ochn == kernal_n)))
			mul_chn_conv_res_rd_pos_y <= # simulation_delay 
			// (mul_chn_conv_res_rd_pos_y == o_ft_map_h[clogb2(max_feature_map_h-1):0]) ? 0:(mul_chn_conv_res_rd_pos_y + 1)
			{(clogb2(max_feature_map_h-1)+1){mul_chn_conv_res_rd_pos_y != o_ft_map_h[clogb2(max_feature_map_h-1):0]}} & 
			(mul_chn_conv_res_rd_pos_y + 1);
	end
	
	/** ��ͨ���������л�����MEM **/
	wire[out_buffer_n-1:0] line_buffer_mem_wen;
	wire[out_buffer_n-1:0] line_buffer_mem_ren;
	wire[clogb2(max_feature_map_w-1):0] line_buffer_mem_addr[0:out_buffer_n-1];
	
	genvar line_buffer_mem_i;
	generate
		for(line_buffer_mem_i = 0;line_buffer_mem_i < out_buffer_n;line_buffer_mem_i = line_buffer_mem_i + 1)
		begin
			assign line_buffer_mem_wen[line_buffer_mem_i] = 
				s_axis_mid_res_valid & mul_chn_conv_res_buf_fifo_full_n & mul_chn_conv_res_buf_fifo_wmask[line_buffer_mem_i];
			
			assign line_buffer_mem_ren[line_buffer_mem_i] = 
				(~(mul_chn_conv_res_buf_fifo_rptr[line_buffer_mem_i] & conv_mid_res_updating_vec[line_buffer_mem_i])) & 
				mul_chn_conv_res_buf_fifo_empty_n & mul_chn_conv_res_rd_s0_ready;
			
			assign line_buffer_mem_addr[line_buffer_mem_i] = line_buffer_mem_wen[line_buffer_mem_i] ? 
				mul_chn_conv_mid_res_wt_pos_x:mul_chn_conv_res_rd_pos_x;
			
			conv_out_line_buffer #(
				.ft_vld_width(ft_vld_width),
				.max_feature_map_w(max_feature_map_w),
				.simulation_delay(simulation_delay)
			)line_buffer_mem(
				.clk(clk),
				.rst_n(rst_n),
				
				.buffer_en(line_buffer_mem_wen[line_buffer_mem_i] | line_buffer_mem_ren[line_buffer_mem_i]),
				.buffer_wen(line_buffer_mem_wen[line_buffer_mem_i]),
				.buffer_addr(line_buffer_mem_addr[line_buffer_mem_i]),
				.buffer_w_first_grp(mul_chn_conv_mid_res_wt_at_first_batch),
				.buffer_din(mid_res_to_wt[line_buffer_mem_i]),
				.buffer_dout(mul_chn_conv_res_dout[line_buffer_mem_i]),
				
				.conv_mid_res_updating(conv_mid_res_updating_vec[line_buffer_mem_i])
			);
		end
	endgenerate
	
endmodule
