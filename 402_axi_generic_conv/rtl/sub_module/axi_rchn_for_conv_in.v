`timescale 1ns / 1ps
/********************************************************************
��ģ��: ���ڻ�ȡ��������ͼ/�����/���Բ�����AXI��ͨ��

����:
������������ͼ/�����/���Բ���������, ͨ��AXI��ͨ����������ͼ/�����/���Բ���������,
	������������ͼ/�����/���Բ���������

32λ��ַ64λ���ݵ�AXI��ͨ��
֧�ַǶ��봫��
֧��4KB�߽籣��

��ѡ��AXI������buffer

��ѡ��AXI����ַͨ��AXIS�Ĵ���Ƭ
��ѡ�Ķ�����AXIS�Ĵ���Ƭ

ע�⣺
AXI����ַ�������(axi_raddr_outstanding)��AXI������buffer���(axi_rdata_buffer_depth)��ͬ����ARͨ��������

Э��:
AXIS MASTER/SLAVE
AXI MASTER(READ ONLY)

����: �¼�ҫ
����: 2024/10/15
********************************************************************/


module axi_rchn_for_conv_in #(
	parameter integer max_rd_btt = 4 * 512, // ���Ķ������ֽ���(256 | 512 | 1024 | ...)
	parameter integer axi_rchn_max_burst_len = 32, // AXI��ͨ�����ͻ������(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer axi_raddr_outstanding = 4, // AXI����ַ�������(1 | 2 | 4)
	parameter integer axi_rdata_buffer_depth = 512, // AXI������buffer���(0 -> ������ | 512 | 1024 | ...)
	parameter en_axi_ar_reg_slice = "true", // �Ƿ�ʹ��AXI����ַͨ��AXIS�Ĵ���Ƭ
	parameter en_rdata_reg_slice = "true", // �Ƿ�ʹ�ܶ�����AXIS�Ĵ���Ƭ
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
	input wire clk,
	input wire rst_n,
	
	// ��������ͼ/�����/���Բ���������
	input wire[63:0] s_axis_rd_req_data, // {����ȡ���ֽ���(32bit), ����ַ(32bit)}
	input wire s_axis_rd_req_valid,
	output wire s_axis_rd_req_ready,
	
	// ��������ͼ/�����/���Բ���������
	output wire[63:0] m_axis_ft_par_data,
	output wire[7:0] m_axis_ft_par_keep,
	output wire m_axis_ft_par_last,
	output wire m_axis_ft_par_valid,
	input wire m_axis_ft_par_ready,
	
	// AXI����(��ͨ��)
	// AR
    output wire[31:0] m_axi_araddr,
    output wire[1:0] m_axi_arburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_arlen,
    output wire[2:0] m_axi_arsize, // const -> 3'b011
    output wire m_axi_arvalid,
    input wire m_axi_arready,
    // R
    input wire[63:0] m_axi_rdata,
    input wire[1:0] m_axi_rresp, // ignored
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output wire m_axi_rready
);
    
	// ����bit_depth�������Чλ���(��λ��-1)
    function integer clogb2(input integer bit_depth);
    begin
        for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
			bit_depth = bit_depth >> 1;
    end
    endfunction
	
	// ����������1�ĸ���
    function integer count1_of_integer(input integer data, input integer data_width);
        integer i;
    begin
        count1_of_integer = 0;
        
        for(i = 0;i < data_width;i = i + 1)
			count1_of_integer = count1_of_integer + data[i];
    end
	endfunction
	
	/** ���� **/
	localparam integer max_rdata_buffer_store_burst_n = (axi_rdata_buffer_depth == 0) ? 
		(1024 / axi_rchn_max_burst_len):(axi_rdata_buffer_depth / axi_rchn_max_burst_len); // ������bufferԤ������ͻ������
	
	/** ��������� **/
	reg rd_req_ready; // ׼���ý��ܶ�����(��־)
	wire rd_req_done; // �����������(ָʾ)
	wire[clogb2(max_rd_btt):0] rd_btt; // ����ȡ���ֽ���
	wire[31:0] rd_baseaddr; // ���������ַ
	wire[clogb2(max_rd_btt)+1:0] rd_req_termination_addr; // �����������ַ
	reg[2:0] first_trans_keep_id; // �״δ�����ֽ���Ч����(���)
	reg[2:0] last_trans_keep_id; // ���1�δ�����ֽ���Ч����(���)
	
	assign s_axis_rd_req_ready = rd_req_ready;
	
	assign {rd_btt, rd_baseaddr} = s_axis_rd_req_data[32 + clogb2(max_rd_btt):0];
	
	assign rd_req_termination_addr = rd_btt + rd_baseaddr[2:0]; // �����ǻ���ַ�ķǶ��벿��, ���벿��Ϊ0
	
	// ׼���ý��ܶ�����(��־)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rd_req_ready <= 1'b1;
		else
			rd_req_ready <= # simulation_delay rd_req_ready ? (~s_axis_rd_req_valid):rd_req_done;
	end
	
	// �״δ�����ֽ���Ч����(���)
	always @(posedge clk)
	begin
		if(s_axis_rd_req_valid & s_axis_rd_req_ready)
			first_trans_keep_id <= # simulation_delay rd_baseaddr[2:0];
	end
	// ���1�δ�����ֽ���Ч����(���)
	always @(posedge clk)
	begin
		if(s_axis_rd_req_valid & s_axis_rd_req_ready)
			last_trans_keep_id <= # simulation_delay rd_req_termination_addr[2:0] - 3'b001;
	end
	
	/** AXI����ַͨ�� **/
	wire raddr_outstanding_allow_arvalid; // ����ַoutstanding�������ַ��Ч(��־)
	wire rdata_buffer_allow_arvalid; // ������buffer�������ַ��Ч(��־)
	reg first_burst; // ��1��ͻ��(��־)
	wire last_burst; // ���1��ͻ��(��־)
	reg[31:0] now_ar; // ��ǰ����ַ
	reg[clogb2(max_rd_btt/8):0] trans_n_remaining; // ʣ�ഫ����
	reg[8:0] trans_n_remaining_in_4kB_sub1; // ��ǰ4KB����ʣ�ഫ���� - 1
	wire[9:0] trans_n_remaining_in_4kB; // ��ǰ4KB����ʣ�ഫ����
	wire[8:0] min_trans_n_remaining_max_burst_len; // min(ʣ�ഫ����, AXI��ͨ�����ͻ������)
	wire[8:0] min_trans_n_remaining_in_4kB_max_burst_len; // min(��ǰ4KB����ʣ�ഫ����, AXI��ͨ�����ͻ������)
	wire[8:0] now_burst_trans_n; // ����ͻ���Ĵ�����
	// ����ַͨ��AXIS�Ĵ���Ƭ
	// AXIS�Ĵ���Ƭ�ӻ�
	wire[31:0] s_axis_ar_reg_slice_data;
    wire[7:0] s_axis_ar_reg_slice_user;
    wire s_axis_ar_reg_slice_valid;
    wire s_axis_ar_reg_slice_ready;
	// AXIS�Ĵ���Ƭ����
	wire[31:0] m_axis_ar_reg_slice_data;
    wire[7:0] m_axis_ar_reg_slice_user;
    wire m_axis_ar_reg_slice_valid;
    wire m_axis_ar_reg_slice_ready;
	
	assign m_axi_araddr = m_axis_ar_reg_slice_data;
	assign m_axi_arburst = 2'b01;
	assign m_axi_arlen = m_axis_ar_reg_slice_user;
	assign m_axi_arsize = 3'b011;
	assign m_axi_arvalid = m_axis_ar_reg_slice_valid;
	assign m_axis_ar_reg_slice_ready = m_axi_arready;
	
	assign s_axis_ar_reg_slice_data = now_ar;
	assign s_axis_ar_reg_slice_user = now_burst_trans_n - 1'b1; // ͻ������ - 1
	assign s_axis_ar_reg_slice_valid = raddr_outstanding_allow_arvalid & rdata_buffer_allow_arvalid & (~rd_req_ready);
	
	assign rd_req_done = s_axis_ar_reg_slice_valid & s_axis_ar_reg_slice_ready & last_burst;
	
	assign trans_n_remaining_in_4kB = trans_n_remaining_in_4kB_sub1 + 1'b1;
	
	assign min_trans_n_remaining_max_burst_len = (trans_n_remaining <= axi_rchn_max_burst_len) ? 
		trans_n_remaining:axi_rchn_max_burst_len;
	assign min_trans_n_remaining_in_4kB_max_burst_len = (trans_n_remaining_in_4kB_sub1 <= (axi_rchn_max_burst_len - 1)) ? 
		trans_n_remaining_in_4kB:axi_rchn_max_burst_len;
	// ����ͻ���Ĵ����� = min(ʣ�ഫ����, ��ǰ4KB����ʣ�ഫ����, AXI��ͨ�����ͻ������)
	assign now_burst_trans_n = (min_trans_n_remaining_max_burst_len <= min_trans_n_remaining_in_4kB_max_burst_len) ? 
		min_trans_n_remaining_max_burst_len:min_trans_n_remaining_in_4kB_max_burst_len;
	
	assign last_burst = (trans_n_remaining <= axi_rchn_max_burst_len) & (trans_n_remaining <= trans_n_remaining_in_4kB);
	
	// ��1��ͻ��(��־)
	always @(posedge clk)
	begin
		if((s_axis_rd_req_valid & s_axis_rd_req_ready) | (s_axis_ar_reg_slice_valid & s_axis_ar_reg_slice_ready))
			first_burst <= # simulation_delay s_axis_rd_req_valid & s_axis_rd_req_ready;
	end
	// ��ǰ����ַ
	always @(posedge clk)
	begin
		if((s_axis_rd_req_valid & s_axis_rd_req_ready) | (s_axis_ar_reg_slice_valid & s_axis_ar_reg_slice_ready))
			now_ar <= # simulation_delay (s_axis_rd_req_valid & s_axis_rd_req_ready) ? 
				{rd_baseaddr[31:3], 3'b000}:{now_ar[31:3] + now_burst_trans_n, 3'b000};
	end
	// ʣ�ഫ����
	always @(posedge clk)
	begin
		if((s_axis_rd_req_valid & s_axis_rd_req_ready) | (s_axis_ar_reg_slice_valid & s_axis_ar_reg_slice_ready))
			trans_n_remaining <= # simulation_delay (s_axis_rd_req_valid & s_axis_rd_req_ready) ? 
				(rd_req_termination_addr[clogb2(max_rd_btt)+1:3] + (rd_req_termination_addr[2:0] != 3'b000)):
				(trans_n_remaining - now_burst_trans_n);
	end
	// ��ǰ4KB����ʣ�ഫ���� - 1
	always @(posedge clk)
	begin
		if((s_axis_rd_req_valid & s_axis_rd_req_ready) | (s_axis_ar_reg_slice_valid & s_axis_ar_reg_slice_ready))
			trans_n_remaining_in_4kB_sub1 <= # simulation_delay (s_axis_rd_req_valid & s_axis_rd_req_ready) ? 
				(~rd_baseaddr[11:3]):(trans_n_remaining_in_4kB_sub1 - now_burst_trans_n);
	end
	
	// ��ѡ��AXI����ַͨ��AXIS�Ĵ���Ƭ
	axis_reg_slice #(
		.data_width(32),
		.user_width(8),
		.forward_registered(en_axi_ar_reg_slice),
		.back_registered(en_axi_ar_reg_slice),
		.en_ready("true"),
		.simulation_delay(simulation_delay)
	)axi_ar_reg_slice(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axis_data(s_axis_ar_reg_slice_data),
		.s_axis_keep(4'bxxxx),
		.s_axis_user(s_axis_ar_reg_slice_user),
		.s_axis_last(1'bx),
		.s_axis_valid(s_axis_ar_reg_slice_valid),
		.s_axis_ready(s_axis_ar_reg_slice_ready),
		
		.m_axis_data(m_axis_ar_reg_slice_data),
		.m_axis_keep(),
		.m_axis_user(m_axis_ar_reg_slice_user),
		.m_axis_last(),
		.m_axis_valid(m_axis_ar_reg_slice_valid),
		.m_axis_ready(m_axis_ar_reg_slice_ready)
	);
	
	/** AXI����ַoutstandingͳ�� **/
	wire on_start_outstanding_ar; // ��������AXI������(ָʾ)
	wire on_finish_outstanding_ar; // �������AXI������(ָʾ)
	reg[clogb2(axi_raddr_outstanding):0] outstanding_ar_n; // ����AXI���������
	reg outstanding_ar_full_n; // ����AXI����������־
	// ����ַ��Ϣfifo
	reg[axi_raddr_outstanding-1:0] ar_msg_fifo_wptr; // дָ��
	reg[axi_raddr_outstanding-1:0] ar_msg_fifo_rptr; // ��ָ��
	reg ar_msg_fifo_last_burst_flag[0:axi_raddr_outstanding-1]; // �Ĵ���fifo(���1��ͻ����־)
	reg[2:0] ar_msg_fifo_first_trans_keep_id[0:axi_raddr_outstanding-1]; // �Ĵ���fifo(�״δ�����ֽ���Ч����)
	reg[2:0] ar_msg_fifo_last_trans_keep_id[0:axi_raddr_outstanding-1]; // �Ĵ���fifo(���1�δ�����ֽ���Ч����)
	wire ar_msg_fifo_last_burst_flag_dout; // ������(���1��ͻ����־)
	wire[2:0] ar_msg_fifo_first_trans_keep_id_dout; // ������(�״δ�����ֽ���Ч����)
	wire[2:0] ar_msg_fifo_last_trans_keep_id_dout; // ������(���1�δ�����ֽ���Ч����)
	
	assign raddr_outstanding_allow_arvalid = outstanding_ar_full_n;
	
	assign on_start_outstanding_ar = s_axis_ar_reg_slice_valid & s_axis_ar_reg_slice_ready;
	assign on_finish_outstanding_ar = m_axi_rvalid & m_axi_rready & m_axi_rlast;
	
	// ����ַ��Ϣfifo������
	generate
		if(axi_raddr_outstanding == 1)
		begin
			assign ar_msg_fifo_last_burst_flag_dout = ar_msg_fifo_last_burst_flag[0];
			assign ar_msg_fifo_first_trans_keep_id_dout = ar_msg_fifo_first_trans_keep_id[0];
			assign ar_msg_fifo_last_trans_keep_id_dout = ar_msg_fifo_last_trans_keep_id[0];
		end
		else if(axi_raddr_outstanding == 2)
		begin
			assign ar_msg_fifo_last_burst_flag_dout = 
				(ar_msg_fifo_rptr[0] & ar_msg_fifo_last_burst_flag[0])
				| (ar_msg_fifo_rptr[1] & ar_msg_fifo_last_burst_flag[1]);
			assign ar_msg_fifo_first_trans_keep_id_dout = 
				({8{ar_msg_fifo_rptr[0]}} & ar_msg_fifo_first_trans_keep_id[0])
				| ({8{ar_msg_fifo_rptr[1]}} & ar_msg_fifo_first_trans_keep_id[1]);
			assign ar_msg_fifo_last_trans_keep_id_dout = 
				({8{ar_msg_fifo_rptr[0]}} & ar_msg_fifo_last_trans_keep_id[0])
				| ({8{ar_msg_fifo_rptr[1]}} & ar_msg_fifo_last_trans_keep_id[1]);
		end
		else
		begin
			assign ar_msg_fifo_last_burst_flag_dout = 
				(ar_msg_fifo_rptr[0] & ar_msg_fifo_last_burst_flag[0])
				| (ar_msg_fifo_rptr[1] & ar_msg_fifo_last_burst_flag[1])
				| (ar_msg_fifo_rptr[2] & ar_msg_fifo_last_burst_flag[2])
				| (ar_msg_fifo_rptr[3] & ar_msg_fifo_last_burst_flag[3]);
			assign ar_msg_fifo_first_trans_keep_id_dout = 
				({8{ar_msg_fifo_rptr[0]}} & ar_msg_fifo_first_trans_keep_id[0])
				| ({8{ar_msg_fifo_rptr[1]}} & ar_msg_fifo_first_trans_keep_id[1])
				| ({8{ar_msg_fifo_rptr[2]}} & ar_msg_fifo_first_trans_keep_id[2])
				| ({8{ar_msg_fifo_rptr[3]}} & ar_msg_fifo_first_trans_keep_id[3]);
			assign ar_msg_fifo_last_trans_keep_id_dout = 
				({8{ar_msg_fifo_rptr[0]}} & ar_msg_fifo_last_trans_keep_id[0])
				| ({8{ar_msg_fifo_rptr[1]}} & ar_msg_fifo_last_trans_keep_id[1])
				| ({8{ar_msg_fifo_rptr[2]}} & ar_msg_fifo_last_trans_keep_id[2])
				| ({8{ar_msg_fifo_rptr[3]}} & ar_msg_fifo_last_trans_keep_id[3]);
		end
	endgenerate
	
	// ����AXI���������
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			outstanding_ar_n <= 0;
		else if(on_start_outstanding_ar ^ on_finish_outstanding_ar)
			outstanding_ar_n <= # simulation_delay on_start_outstanding_ar ? (outstanding_ar_n + 1):(outstanding_ar_n - 1);
	end
	// ����AXI����������־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			outstanding_ar_full_n <= 1'b1;
		else if(on_start_outstanding_ar ^ on_finish_outstanding_ar)
			// on_start_outstanding_ar ? (outstanding_ar_n != (axi_raddr_outstanding - 1)):1'b1;
			outstanding_ar_full_n <= # simulation_delay (~on_start_outstanding_ar) 
				| (outstanding_ar_n != (axi_raddr_outstanding - 1));
	end
	
	// ����ַ��Ϣfifoдָ��
	generate
		if(axi_raddr_outstanding == 1)
		begin
			always @(*)
				ar_msg_fifo_wptr = 1'b1;
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					ar_msg_fifo_wptr <= {{(axi_raddr_outstanding-1){1'b0}}, 1'b1};
				else if(on_start_outstanding_ar)
					ar_msg_fifo_wptr <= # simulation_delay 
						{ar_msg_fifo_wptr[axi_raddr_outstanding-2:0], ar_msg_fifo_wptr[axi_raddr_outstanding-1]};
			end
		end
	endgenerate
	// ����ַ��Ϣfifo��ָ��
	generate
		if(axi_raddr_outstanding == 1)
		begin
			always @(*)
				ar_msg_fifo_rptr = 1'b1;
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					ar_msg_fifo_rptr <= {{(axi_raddr_outstanding-1){1'b0}}, 1'b1};
				else if(on_finish_outstanding_ar)
					ar_msg_fifo_rptr <= # simulation_delay 
						{ar_msg_fifo_rptr[axi_raddr_outstanding-2:0], ar_msg_fifo_rptr[axi_raddr_outstanding-1]};
			end
		end
	endgenerate
	// ����ַ��Ϣfifo�洢����
	genvar ar_msg_fifo_item_i;
	generate
		for(ar_msg_fifo_item_i = 0;ar_msg_fifo_item_i < axi_raddr_outstanding;ar_msg_fifo_item_i = ar_msg_fifo_item_i + 1)
		begin
			// ���1��ͻ����־
			always @(posedge clk)
			begin
				if(on_start_outstanding_ar & ar_msg_fifo_wptr[ar_msg_fifo_item_i])
					ar_msg_fifo_last_burst_flag[ar_msg_fifo_item_i] <= # simulation_delay last_burst;
			end
			// �״δ�����ֽ���Ч����
			always @(posedge clk)
			begin
				if(on_start_outstanding_ar & ar_msg_fifo_wptr[ar_msg_fifo_item_i])
					ar_msg_fifo_first_trans_keep_id[ar_msg_fifo_item_i] <= # simulation_delay first_trans_keep_id;
			end
			// ���1�δ�����ֽ���Ч����
			always @(posedge clk)
			begin
				if(on_start_outstanding_ar & ar_msg_fifo_wptr[ar_msg_fifo_item_i])
					ar_msg_fifo_last_trans_keep_id[ar_msg_fifo_item_i] <= # simulation_delay last_trans_keep_id;
			end
		end
	endgenerate
	
	/** AXI�����ݴ��� **/
	// ����last�ź�
	wire rd_req_last_trans; // ���������1������
	// ����last�źŲ����user�źź��AXI��������
	wire[63:0] s_axis_axi_data;
	wire[6:0] s_axis_axi_user; // {�״δ�����ֽ���Ч������, ���1�δ�����ֽ���Ч������, AXI��ͻ�����1������(��־)}
    wire s_axis_axi_last;
    wire s_axis_axi_valid;
    wire s_axis_axi_ready;
	
	assign s_axis_axi_data = m_axi_rdata;
	assign s_axis_axi_user = {ar_msg_fifo_first_trans_keep_id_dout, ar_msg_fifo_last_trans_keep_id_dout, m_axi_rlast};
	assign s_axis_axi_last = rd_req_last_trans;
	assign s_axis_axi_valid = m_axi_rvalid;
	assign m_axi_rready = s_axis_axi_ready;
	
	assign rd_req_last_trans = m_axi_rlast & ar_msg_fifo_last_burst_flag_dout;
	
	/** ������buffer **/
	wire on_rdata_buffer_store; // ������bufferԤ��1��ͻ��(ָʾ)
	wire on_rdata_buffer_fetch; // ������bufferȡ��1��ͻ��(ָʾ)
	reg[clogb2(max_rdata_buffer_store_burst_n):0] rdata_buffer_store_burst_n; // ������bufferԤ���ͻ������
	reg rdata_buffer_full_n; // ������buffer����־
	// ����keep�ź�
	reg rdata_first; // �����ݰ���1��������(��־)
	wire[7:0] rdata_first_keep; // ��1�������ݵ�keep�ź�
	wire[7:0] rdata_last_keep; // ���1�������ݵ�keep�ź�
	// ������buffer�����
	wire[63:0] m_axis_rdata_buffer_data;
	wire[7:0] m_axis_rdata_buffer_keep;
	wire[6:0] m_axis_rdata_buffer_user; // {�״δ�����ֽ���Ч������, ���1�δ�����ֽ���Ч������, AXI��ͻ�����1������(��־)}
    wire m_axis_rdata_buffer_last;
    wire m_axis_rdata_buffer_valid;
    wire m_axis_rdata_buffer_ready;
	
	assign rdata_buffer_allow_arvalid = (axi_rdata_buffer_depth == 0) | rdata_buffer_full_n;
	
	assign on_rdata_buffer_store = s_axis_ar_reg_slice_valid & s_axis_ar_reg_slice_ready;
	assign on_rdata_buffer_fetch = m_axis_rdata_buffer_valid & m_axis_rdata_buffer_ready & m_axis_rdata_buffer_user[0];
	
	// ���ֽ���Ч����������keep�ź�
	assign rdata_first_keep = {
		1'b1, m_axis_rdata_buffer_user[6:4] <= 3'd6,
		m_axis_rdata_buffer_user[6:4] <= 3'd5, m_axis_rdata_buffer_user[6:4] <= 3'd4,
		m_axis_rdata_buffer_user[6:4] <= 3'd3, m_axis_rdata_buffer_user[6:4] <= 3'd2,
		m_axis_rdata_buffer_user[6:4] <= 3'd1, m_axis_rdata_buffer_user[6:4] == 3'd0};
	assign rdata_last_keep = {
		m_axis_rdata_buffer_user[3:1] == 3'd7, m_axis_rdata_buffer_user[3:1] >= 3'd6,
		m_axis_rdata_buffer_user[3:1] >= 3'd5, m_axis_rdata_buffer_user[3:1] >= 3'd4,
		m_axis_rdata_buffer_user[3:1] >= 3'd3, m_axis_rdata_buffer_user[3:1] >= 3'd2,
		m_axis_rdata_buffer_user[3:1] >= 3'd1, 1'b1};
	/*
	({rdata_first, m_axis_rdata_buffer_last} == 2'b00) ? 8'b1111_1111:
	({rdata_first, m_axis_rdata_buffer_last} == 2'b01) ? rdata_last_keep:
	({rdata_first, m_axis_rdata_buffer_last} == 2'b10) ? rdata_first_keep:
														 (rdata_first_keep & rdata_last_keep)
	*/
	assign m_axis_rdata_buffer_keep = 
		({8{~rdata_first}} | rdata_first_keep) & 
		({8{~m_axis_rdata_buffer_last}} | rdata_last_keep);
	
	// ������bufferԤ���ͻ������
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rdata_buffer_store_burst_n <= 0;
		else if(on_rdata_buffer_store ^ on_rdata_buffer_fetch)
			rdata_buffer_store_burst_n <= # simulation_delay on_rdata_buffer_store ? (rdata_buffer_store_burst_n + 1):
				(rdata_buffer_store_burst_n - 1);
	end
	// ������buffer����־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rdata_buffer_full_n <= 1'b1;
		else if(on_rdata_buffer_store ^ on_rdata_buffer_fetch)
			// on_rdata_buffer_store ? (rdata_buffer_store_burst_n != (max_rdata_buffer_store_burst_n - 1)):1'b1;
			rdata_buffer_full_n <= # simulation_delay (~on_rdata_buffer_store) 
				| (rdata_buffer_store_burst_n != (max_rdata_buffer_store_burst_n - 1));
	end
	
	// �����ݰ���1��������(��־)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rdata_first <= 1'b1;
		else if(m_axis_rdata_buffer_valid & m_axis_rdata_buffer_ready)
			rdata_first <= # simulation_delay m_axis_rdata_buffer_last;
	end
	
	// ��ѡ��AXI�����ݻ���fifo
	generate
		if(axi_rdata_buffer_depth != 0)
		begin
			axis_data_fifo #(
				.is_async("false"),
				.en_packet_mode("false"),
				.ram_type("bram"),
				.fifo_depth(axi_rdata_buffer_depth),
				.data_width(64),
				.user_width(7),
				.simulation_delay(simulation_delay)
			)axi_rdata_buffer(
				.s_axis_aclk(clk),
				.s_axis_aresetn(rst_n),
				.m_axis_aclk(clk),
				.m_axis_aresetn(rst_n),
				
				.s_axis_data(s_axis_axi_data),
				.s_axis_keep(8'bxxxx_xxxx),
				.s_axis_strb(8'bxxxx_xxxx),
				.s_axis_user(s_axis_axi_user),
				.s_axis_last(s_axis_axi_last),
				.s_axis_valid(s_axis_axi_valid),
				.s_axis_ready(s_axis_axi_ready),
				
				.m_axis_data(m_axis_rdata_buffer_data),
				.m_axis_keep(),
				.m_axis_strb(),
				.m_axis_user(m_axis_rdata_buffer_user),
				.m_axis_last(m_axis_rdata_buffer_last),
				.m_axis_valid(m_axis_rdata_buffer_valid),
				.m_axis_ready(m_axis_rdata_buffer_ready)
			);
		end
		else
		begin
			// pass
			assign m_axis_rdata_buffer_data = s_axis_axi_data;
			assign m_axis_rdata_buffer_user = s_axis_axi_user;
			assign m_axis_rdata_buffer_last = s_axis_axi_last;
			assign m_axis_rdata_buffer_valid = s_axis_axi_valid;
			assign s_axis_axi_ready = m_axis_rdata_buffer_ready;
		end
	endgenerate
	
	/** ������AXIS�Ĵ���Ƭ **/
	// AXIS�Ĵ���Ƭ�ӻ�
	wire[63:0] s_axis_rdata_reg_slice_data;
    wire[7:0] s_axis_rdata_reg_slice_keep;
	wire s_axis_rdata_reg_slice_last;
    wire s_axis_rdata_reg_slice_valid;
    wire s_axis_rdata_reg_slice_ready;
	// AXIS�Ĵ���Ƭ����
	wire[63:0] m_axis_rdata_reg_slice_data;
    wire[7:0] m_axis_rdata_reg_slice_keep;
	wire m_axis_rdata_reg_slice_last;
    wire m_axis_rdata_reg_slice_valid;
    wire m_axis_rdata_reg_slice_ready;
	
	assign m_axis_ft_par_data = m_axis_rdata_reg_slice_data;
	assign m_axis_ft_par_keep = m_axis_rdata_reg_slice_keep;
	assign m_axis_ft_par_last = m_axis_rdata_reg_slice_last;
	assign m_axis_ft_par_valid = m_axis_rdata_reg_slice_valid;
	assign m_axis_rdata_reg_slice_ready = m_axis_ft_par_ready;
	
	// ��ѡ�Ķ�����AXIS�Ĵ���Ƭ
	axis_reg_slice #(
		.data_width(64),
		.user_width(1),
		.forward_registered(en_rdata_reg_slice),
		.back_registered(((axi_rdata_buffer_depth == 0) && (en_rdata_reg_slice == "true")) ? "true":"false"),
		.en_ready("true"),
		.simulation_delay(simulation_delay)
	)rdata_reg_slice(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axis_data(s_axis_rdata_reg_slice_data),
		.s_axis_keep(s_axis_rdata_reg_slice_keep),
		.s_axis_user(1'bx),
		.s_axis_last(s_axis_rdata_reg_slice_last),
		.s_axis_valid(s_axis_rdata_reg_slice_valid),
		.s_axis_ready(s_axis_rdata_reg_slice_ready),
		
		.m_axis_data(m_axis_rdata_reg_slice_data),
		.m_axis_keep(m_axis_rdata_reg_slice_keep),
		.m_axis_user(),
		.m_axis_last(m_axis_rdata_reg_slice_last),
		.m_axis_valid(m_axis_rdata_reg_slice_valid),
		.m_axis_ready(m_axis_rdata_reg_slice_ready)
	);
	
	/** ����������� **/
	reg first_trans_to_reorg; // ��1����������(��־)
	wire last_trans_to_reorg; // ���1����������(��־)
	reg to_flush_reorg_buffer; // ��ˢƴ�ӻ�����(��־)
	reg[2:0] reorg_method; // ƴ�ӷ�ʽ
	wire[2:0] reorg_method_nxt; // �µ�ƴ�ӷ�ʽ
	reg[7:0] flush_keep_mask; // ��ˢʱ��keep����
	reg[7:0] reorg_first_keep; // ��1���ֽ���Ч����
	reg[63:0] data_reorg_buffer; // ƴ�ӻ�����(����)
	reg[7:0] keep_reorg_buffer; // ƴ�ӻ�����(�ֽ���Ч����)
	wire reorg_pkt_only_one_trans; // ���������ݰ�������1������(��־)
	
	// ��������: (~to_flush_reorg_buffer) & m_axis_rdata_buffer_valid & s_axis_rdata_reg_slice_ready
	assign m_axis_rdata_buffer_ready = (~to_flush_reorg_buffer) & s_axis_rdata_reg_slice_ready;
	
	assign s_axis_rdata_reg_slice_data = reorg_pkt_only_one_trans ? 
		// ����ͻ��ֻ��1������, ����Ч�ֽڶ��뵽���ұߺ����, ����8�����
		((m_axis_rdata_buffer_data >> (reorg_method_nxt * 8)) | (64'dx << (64 - reorg_method_nxt * 8))):
		// ����ƴ�ӷ�ʽ, �ϲ�ƴ�ӻ������͵�ǰ����, ����8�����
		((data_reorg_buffer >> (reorg_method * 8)) | (m_axis_rdata_buffer_data << (64 - reorg_method * 8)));
	assign s_axis_rdata_reg_slice_keep = 
		// ��ˢƴ�ӻ�����ʱ��Ҫ���ݵ�1���������ݵ�keepȡ����
		(flush_keep_mask | {8{~to_flush_reorg_buffer}}) &
		// ����ͻ��ֻ��1������, ��keep�źŶ��뵽LSB�����, ����8�����
		(reorg_pkt_only_one_trans ? (m_axis_rdata_buffer_keep >> reorg_method_nxt):
			// ����ƴ�ӷ�ʽ, �ϲ�ƴ�ӻ������͵�ǰkeep�ź�, ����8�����
			((keep_reorg_buffer >> reorg_method) | (m_axis_rdata_buffer_keep << (4'd8 - {1'b0, reorg_method}))));
	assign s_axis_rdata_reg_slice_last = to_flush_reorg_buffer | 
		// ��������1����������ȡ�����û����Ч�ֽ�, ��ô�����ˢƴ�ӻ�����, ��ǰ�������1���������
		((first_trans_to_reorg | (~(|(m_axis_rdata_buffer_keep & reorg_first_keep)))) & last_trans_to_reorg);
	// ��������: (to_flush_reorg_buffer & s_axis_rdata_reg_slice_ready) | 
	//     (m_axis_rdata_buffer_valid & s_axis_rdata_reg_slice_ready & (~(first_trans_to_reorg & (~last_trans_to_reorg))))
	assign s_axis_rdata_reg_slice_valid = to_flush_reorg_buffer | 
		(m_axis_rdata_buffer_valid & (~(first_trans_to_reorg & (~last_trans_to_reorg))));
    
	assign last_trans_to_reorg = m_axis_rdata_buffer_last;
	// ����ƴ�ӷ�ʽ
	assign reorg_method_nxt = count1_of_integer(~{
		m_axis_rdata_buffer_keep[0],
		|m_axis_rdata_buffer_keep[1:0],
		|m_axis_rdata_buffer_keep[2:0],
		|m_axis_rdata_buffer_keep[3:0],
		|m_axis_rdata_buffer_keep[4:0],
		|m_axis_rdata_buffer_keep[5:0],
		|m_axis_rdata_buffer_keep[6:0]}, 7);
	assign reorg_pkt_only_one_trans = first_trans_to_reorg & last_trans_to_reorg & (~to_flush_reorg_buffer);
	
	// ��1����������(��־)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			first_trans_to_reorg <= 1'b1;
		else if(m_axis_rdata_buffer_valid & m_axis_rdata_buffer_ready)
			first_trans_to_reorg <= # simulation_delay last_trans_to_reorg;
	end
	
	// ��ˢƴ�ӻ�����(��־)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			to_flush_reorg_buffer <= 1'b0;
		else
			to_flush_reorg_buffer <= # simulation_delay 
				to_flush_reorg_buffer ? (~s_axis_rdata_reg_slice_ready):
					(m_axis_rdata_buffer_valid & s_axis_rdata_reg_slice_ready & 
					// ��������1����������ȡ�����û����Ч�ֽ�, ��ô�����ˢƴ�ӻ�����
					(~first_trans_to_reorg) & last_trans_to_reorg & (|(m_axis_rdata_buffer_keep & reorg_first_keep)));
	end
	
	// ƴ�ӷ�ʽ
	always @(posedge clk)
	begin
		if(m_axis_rdata_buffer_valid & m_axis_rdata_buffer_ready & first_trans_to_reorg)
			reorg_method <= # simulation_delay reorg_method_nxt;
	end
	// ��ˢʱ��keep����
	always @(posedge clk)
	begin
		if(m_axis_rdata_buffer_valid & m_axis_rdata_buffer_ready & first_trans_to_reorg)
			flush_keep_mask <= # simulation_delay {
				m_axis_rdata_buffer_keep[0],
				|m_axis_rdata_buffer_keep[1:0],
				|m_axis_rdata_buffer_keep[2:0],
				|m_axis_rdata_buffer_keep[3:0],
				|m_axis_rdata_buffer_keep[4:0],
				|m_axis_rdata_buffer_keep[5:0],
				|m_axis_rdata_buffer_keep[6:0],
				1'b1
			};
	end
	// ��1���ֽ���Ч����
	always @(posedge clk)
	begin
		if(m_axis_rdata_buffer_valid & m_axis_rdata_buffer_ready & first_trans_to_reorg)
			reorg_first_keep <= # simulation_delay m_axis_rdata_buffer_keep;
	end
	
	// ƴ�ӻ�����(����)
	always @(posedge clk)
	begin
		if(m_axis_rdata_buffer_valid & m_axis_rdata_buffer_ready)
			data_reorg_buffer <= # simulation_delay m_axis_rdata_buffer_data;
	end
	// ƴ�ӻ�����(�ֽ���Ч����)
	always @(posedge clk)
	begin
		if(m_axis_rdata_buffer_valid & m_axis_rdata_buffer_ready)
			keep_reorg_buffer <= # simulation_delay m_axis_rdata_buffer_keep;
	end
	
endmodule
