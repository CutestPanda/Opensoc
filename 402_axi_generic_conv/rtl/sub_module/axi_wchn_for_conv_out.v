`timescale 1ns / 1ps
/********************************************************************
��ģ��: ����������/BN/�����������AXIдͨ��

����:
���ܼ�����д����, ���������������������ͼ������

32λ��ַ64λ���ݵ�AXIдͨ��
֧�ַǶ��봫��
֧��4KB�߽籣��

�ڲ���AXIд����buffer�����AXIдͻ���Ĵ���Ч��

��ѡ��AXIд��ַͨ��AXIS�Ĵ���Ƭ

ע�⣺
���뱣֤д�������ַ�ܱ�(feature_data_width/8)����, ��д������뵽������λ��
���뱣֤д�����д����ֽ����ܱ�(feature_data_width/8)����, ��д��������������

Э��:
AXIS SLAVE
AXI MASTER(WRITE ONLY)

����: �¼�ҫ
����: 2024/11/08
********************************************************************/


module axi_wchn_for_conv_out #(
	parameter integer feature_data_width = 16, // ������λ��(8 | 16 | 32 | 64)
	parameter integer max_wt_btt = 4 * 512, // ����д�����ֽ���(256 | 512 | 1024 | ...)
	parameter integer axi_wchn_max_burst_len = 32, // AXIдͨ�����ͻ������(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer axi_waddr_outstanding = 4, // AXIд��ַ�������(1 | 2 | 4)
	parameter integer axi_wdata_buffer_depth = 512, // AXIд����buffer���(512 | 1024 | ...)
	parameter en_4KB_boundary_protection = "true", // �Ƿ�ʹ��4KB�߽籣��
	parameter en_axi_aw_reg_slice = "true", // �Ƿ�ʹ��AXIд��ַͨ��AXIS�Ĵ���Ƭ
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
	input wire clk,
	input wire rst_n,
	
	// ���д����(ָʾ)
	output wire wt_req_fns,
	
	// ������д����
	input wire[63:0] s_axis_wt_req_data, // {��д����ֽ���(32bit), ����ַ(32bit)}
	input wire s_axis_wt_req_valid,
	output wire s_axis_wt_req_ready,
	
	// ��������
	input wire[feature_data_width-1:0] s_axis_res_data,
	input wire s_axis_res_last, // ��ʾ����д�������1������
	input wire s_axis_res_valid,
	output wire s_axis_res_ready,
	
	// AXI����(дͨ��)
	// AW
    output wire[31:0] m_axi_awaddr,
    output wire[1:0] m_axi_awburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_awlen,
    output wire[2:0] m_axi_awsize, // const -> 3'b011
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    // B
    input wire[1:0] m_axi_bresp, // ignored
    input wire m_axi_bvalid,
    output wire m_axi_bready, // const -> 1'b1
    // W
    output wire[63:0] m_axi_wdata,
    output wire[7:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready
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
	// д��ַ��Ϣ����״̬��������
	localparam integer STS_WAIT_ALLOW_AW_VLD = 0; // ״̬: �ȴ�����д��ַ��Ч
	localparam integer STS_GEN_AW_LEN = 1; // ״̬: ����дͻ������
	localparam integer STS_UPD_AW_ADDR = 2; // ״̬: ����д��ַ���ȴ�AW����
	// ���õ���Сֵ���㵥Ԫ������1��λ��
	localparam integer MIN_CAL_OP1_WIDTH = (clogb2(max_wt_btt/8-1) > 8) ? (clogb2(max_wt_btt/8-1)+1):9;
	
	/** ����д���� **/
	wire wt_req_msg_fifo_allow_ready; // д������Ϣfifo�������д����(��־)
	reg wt_req_ready; // ׼���ý���д����(��־)
	wire wt_req_done; // д���������(ָʾ)
	wire[clogb2(max_wt_btt):0] wt_btt; // ��д����ֽ���
	wire[31:0] wt_baseaddr; // д�������ַ
	wire[clogb2(max_wt_btt)+1:0] wt_req_termination_addr; // д���������ַ
	/*
	 ��ʼ��ַ[2:0]  ���        ����
	     0         3'b000   8'b1111_1111
	     1         3'b001   8'b1111_1110
	     2         3'b010   8'b1111_1100
	     3         3'b011   8'b1111_1000
	     4         3'b100   8'b1111_0000
	     5         3'b101   8'b1110_0000
	     6         3'b110   8'b1100_0000
	     7         3'b111   8'b1000_0000
	*/
	wire[2:0] first_trans_keep_id; // �״δ�����ֽ���Ч������
	/*
	 ������ַ[2:0]  ���        ����
	     1         3'b000   8'b0000_0001
	     2         3'b001   8'b0000_0011
	     3         3'b010   8'b0000_0111
	     4         3'b011   8'b0000_1111
	     5         3'b100   8'b0001_1111
	     6         3'b101   8'b0011_1111
	     7         3'b110   8'b0111_1111
	     0         3'b111   8'b1111_1111
	*/
	wire[2:0] last_trans_keep_id; // ���1�δ�����ֽ���Ч������
	wire[clogb2(max_wt_btt/8-1):0] wt_trans_n; // д������� - 1
	
	// ��������: s_axis_wt_req_valid & wt_req_msg_fifo_allow_ready & wt_req_ready
	assign s_axis_wt_req_ready = wt_req_ready & wt_req_msg_fifo_allow_ready;
	
	assign {wt_btt, wt_baseaddr} = s_axis_wt_req_data[32+clogb2(max_wt_btt):0];
	assign wt_req_termination_addr = wt_btt + wt_baseaddr[2:0]; // �����ǻ���ַ�ķǶ��벿��, ���벿��Ϊ0
	assign first_trans_keep_id = wt_baseaddr[2:0];
	assign last_trans_keep_id = wt_req_termination_addr[2:0] + 3'b111;
	// wt_req_termination_addr[clogb2(max_wt_btt)+1:3] + (wt_req_termination_addr[2:0] != 3'b000) - 1'b1
	assign wt_trans_n = wt_req_termination_addr[clogb2(max_wt_btt)+1:3] + 
		{(clogb2(max_wt_btt/8-1)+1){~(|wt_req_termination_addr[2:0])}};
	
	// ׼���ý���д����(��־)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wt_req_ready <= 1'b1;
		else
			wt_req_ready <= # simulation_delay wt_req_ready ? 
				(~(s_axis_wt_req_valid & wt_req_msg_fifo_allow_ready)):wt_req_done;
	end
	
	/** д��ַͨ��AXIS�Ĵ���Ƭ **/
	// AXIS�ӻ�
	wire[31:0] s_axis_aw_data; // д��ַ
	wire[7:0] s_axis_aw_user; // дͻ������ - 1
	wire s_axis_aw_valid;
	wire s_axis_aw_ready;
	// AXIS����
	wire[31:0] m_axis_aw_data; // д��ַ
	wire[7:0] m_axis_aw_user; // дͻ������ - 1
	wire m_axis_aw_valid;
	wire m_axis_aw_ready;
	
	assign m_axi_awaddr = m_axis_aw_data;
	assign m_axi_awburst = 2'b01;
	assign m_axi_awlen = m_axis_aw_user;
	assign m_axi_awsize = 3'b011;
	assign m_axi_awvalid = m_axis_aw_valid;
	assign m_axis_aw_ready = m_axi_awready;
	
	// ��ѡ��AXIд��ַͨ��AXIS�Ĵ���Ƭ
	axis_reg_slice #(
		.data_width(32),
		.user_width(8),
		.forward_registered(en_axi_aw_reg_slice),
		.back_registered(en_axi_aw_reg_slice),
		.en_ready("true"),
		.simulation_delay(simulation_delay)
	)axi_aw_reg_slice(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axis_data(s_axis_aw_data),
		.s_axis_keep(4'bxxxx),
		.s_axis_user(s_axis_aw_user),
		.s_axis_last(1'bx),
		.s_axis_valid(s_axis_aw_valid),
		.s_axis_ready(s_axis_aw_ready),
		
		.m_axis_data(m_axis_aw_data),
		.m_axis_keep(),
		.m_axis_user(m_axis_aw_user),
		.m_axis_last(),
		.m_axis_valid(m_axis_aw_valid),
		.m_axis_ready(m_axis_aw_ready)
	);
	
	/** д��ַ��Ϣ�� **/
	// ��Ϣ��Ĵ�����
	reg[39:0] aw_tb_content[0:axi_waddr_outstanding-1]; // ������({дͻ������ - 1(8bit), д��ַ(32bit)})
	reg[1:0] aw_tb_flag[0:axi_waddr_outstanding-1]; // �����������ڱ�־({дͻ����������׼����(1bit), дͻ����Ԥ����(1bit)})
	// ��Ϣ��д�˿�(Ԥ����дͻ��)
	reg[clogb2(axi_waddr_outstanding-1):0] pre_launch_wt_burst_wptr; // дָ��
	wire pre_launch_wt_burst_committing_wen; // Ԥ�����µ�дͻ��(�������ʹ��)
	wire pre_launch_wt_burst_allowed_full_n; // ����Ԥ����дͻ��(��־)
	wire[39:0] wt_burst_msg_din; // �������дͻ����Ϣ({дͻ������ - 1(8bit), д��ַ(32bit)})
	// ��Ϣ����˿�(׼����дͻ��������)
	reg[clogb2(axi_waddr_outstanding-1):0] prepare_wdata_rptr; // ��ָ��
	wire wdata_prepared_ren; // ׼����дͻ��������(�������ʹ��)
	wire wt_burst_msg_available_empty_n; // дͻ����Ϣ����(��־)
	wire[7:0] wt_burst_msg_dout; // дͻ����Ϣ({дͻ������ - 1(8bit)})
	// ��Ϣ����˿�(�ɷ�д��ַ)
	reg[clogb2(axi_waddr_outstanding-1):0] dispatch_waddr_rptr; // ��ָ��
	wire waddr_dispatched_ren; // �ɷ�д��ַ(�������ʹ��)
	wire dispatch_waddr_allowed_empty_n; // �����ɷ�д��ַ(��־)
	wire[39:0] waddr_dispatch_msg_dout; // д��ַ�ɷ���Ϣ({дͻ������ - 1(8bit), д��ַ(32bit)})
	
	assign s_axis_aw_data = waddr_dispatch_msg_dout[31:0];
	assign s_axis_aw_user = waddr_dispatch_msg_dout[39:32];
	assign s_axis_aw_valid = dispatch_waddr_allowed_empty_n;
	assign waddr_dispatched_ren = s_axis_aw_ready;
	
	assign pre_launch_wt_burst_allowed_full_n = aw_tb_flag[pre_launch_wt_burst_wptr] == 2'b00;
	assign wt_burst_msg_available_empty_n = aw_tb_flag[prepare_wdata_rptr] == 2'b01;
	assign dispatch_waddr_allowed_empty_n = aw_tb_flag[dispatch_waddr_rptr] == 2'b11;
	
	assign wt_burst_msg_dout = aw_tb_content[prepare_wdata_rptr][39:32];
	assign waddr_dispatch_msg_dout = aw_tb_content[dispatch_waddr_rptr];
	
	// ������/�����������ڱ�־�Ĵ�����
	genvar aw_tb_i;
	generate
		for(aw_tb_i = 0;aw_tb_i < axi_waddr_outstanding;aw_tb_i = aw_tb_i + 1)
		begin
			// ������
			always @(posedge clk)
			begin
				if(pre_launch_wt_burst_committing_wen & pre_launch_wt_burst_allowed_full_n & 
					(pre_launch_wt_burst_wptr == aw_tb_i))
					aw_tb_content[aw_tb_i] <= # simulation_delay wt_burst_msg_din;
			end
			
			// �����������ڱ�־(дͻ����Ԥ����)
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					aw_tb_flag[aw_tb_i][0] <= 1'b0;
				else if((pre_launch_wt_burst_committing_wen & (aw_tb_flag[aw_tb_i] == 2'b00) & 
					(pre_launch_wt_burst_wptr == aw_tb_i)) | 
					(waddr_dispatched_ren & (aw_tb_flag[aw_tb_i] == 2'b11) & (dispatch_waddr_rptr == aw_tb_i)))
					aw_tb_flag[aw_tb_i][0] <= # simulation_delay aw_tb_flag[aw_tb_i] == 2'b00;
			end
			// �����������ڱ�־(дͻ����������׼����)
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					aw_tb_flag[aw_tb_i][1] <= 1'b0;
				else if((wdata_prepared_ren & (aw_tb_flag[aw_tb_i] == 2'b01) & (prepare_wdata_rptr == aw_tb_i)) | 
					(waddr_dispatched_ren & (aw_tb_flag[aw_tb_i] == 2'b11) & (dispatch_waddr_rptr == aw_tb_i)))
					aw_tb_flag[aw_tb_i][1] <= # simulation_delay aw_tb_flag[aw_tb_i] == 2'b01;
			end
		end
	endgenerate
	
	// ��Ϣ��дָ��(Ԥ����дͻ��)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			pre_launch_wt_burst_wptr <= 0;
		else if(pre_launch_wt_burst_committing_wen & pre_launch_wt_burst_allowed_full_n)
			pre_launch_wt_burst_wptr <= # simulation_delay 
				// (pre_launch_wt_burst_wptr == (axi_waddr_outstanding-1)) ? 0:(pre_launch_wt_burst_wptr + 1)
				{(clogb2(axi_waddr_outstanding-1)+1){pre_launch_wt_burst_wptr != (axi_waddr_outstanding-1)}} & 
				(pre_launch_wt_burst_wptr + 1);
	end
	// ��Ϣ���ָ��(׼����дͻ��������)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			prepare_wdata_rptr <= 0;
		else if(wdata_prepared_ren & wt_burst_msg_available_empty_n)
			prepare_wdata_rptr <= # simulation_delay 
				// (prepare_wdata_rptr == (axi_waddr_outstanding-1)) ? 0:(prepare_wdata_rptr + 1)
				{(clogb2(axi_waddr_outstanding-1)+1){prepare_wdata_rptr != (axi_waddr_outstanding-1)}} & 
				(prepare_wdata_rptr + 1);
	end
	// ��Ϣ���ָ��(�ɷ�д��ַ)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			dispatch_waddr_rptr <= 0;
		else if(waddr_dispatched_ren & dispatch_waddr_allowed_empty_n)
			dispatch_waddr_rptr <= # simulation_delay 
				// (dispatch_waddr_rptr == (axi_waddr_outstanding-1)) ? 0:(dispatch_waddr_rptr + 1)
				{(clogb2(axi_waddr_outstanding-1)+1){dispatch_waddr_rptr != (axi_waddr_outstanding-1)}} & 
				(dispatch_waddr_rptr + 1);
	end
	
	/** ����д��ַ **/
	wire outstanding_stat_allow_aw_vld; // ���⴫��ͳ������AXIд��ַ��Ч(��־)
	wire to_allow_aw_vld; // ����AXIд��ַ��Ч(��־)
	reg[2:0] aw_msg_upd_sts; // д��ַ��Ϣ����״̬(3'b001 -> �ȴ�����д��ַ��Ч, 
	                         //                    3'b010 -> ����дͻ������, 3'b100 -> ����д��ַ���ȴ�AW����)
	reg[31:0] aw_addr; // ��ǰ��д��ַ
	wire[7:0] aw_len; // дͻ������ - 1
	reg[8:0] trans_n_remaining_in_4kB; // ��ǰ4KB����ʣ�ഫ���� - 1
	reg[clogb2(max_wt_btt/8-1):0] trans_n_remaining; // ʣ�ഫ���� - 1
	reg last_wt_burst; // ���1��дͻ��(��־)
	/*
	���õ���Сֵ���㵥Ԫ -> 
	
	ʹ��4KB�߽籣��: 
					   cycle#0                 cycle#1
		op1    trans_n_remaining_in_4kB    trans_n_remaining
		
		op2   axi_wchn_max_burst_len - 1      ǰ����Сֵ
	
	��ʹ��4KB�߽籣��: 
					   cycle#0                       cycle#1
		op1       trans_n_remaining            trans_n_remaining
		
		op2   axi_wchn_max_burst_len - 1   axi_wchn_max_burst_len - 1
	*/
	wire[MIN_CAL_OP1_WIDTH-1:0] min_cal_op1;
	wire[7:0] min_cal_op2;
	wire min_cal_op1_leq_op2;
	reg[7:0] min_cal_res;
	
	assign wt_burst_msg_din[31:0] = aw_addr;
	assign wt_burst_msg_din[39:32] = aw_len;
	assign pre_launch_wt_burst_committing_wen = aw_msg_upd_sts[STS_UPD_AW_ADDR];
	
	assign wt_req_done = pre_launch_wt_burst_committing_wen & pre_launch_wt_burst_allowed_full_n & last_wt_burst;
	
	assign to_allow_aw_vld = outstanding_stat_allow_aw_vld & (~wt_req_ready);
	
	assign aw_len = min_cal_res;
	
	assign min_cal_op1 = 
		(aw_msg_upd_sts[STS_WAIT_ALLOW_AW_VLD] & (en_4KB_boundary_protection == "true")) ? 
			trans_n_remaining_in_4kB:trans_n_remaining;
	assign min_cal_op2 = 
		(aw_msg_upd_sts[STS_WAIT_ALLOW_AW_VLD] | (en_4KB_boundary_protection == "false")) ? 
			(axi_wchn_max_burst_len - 1):min_cal_res;
	assign min_cal_op1_leq_op2 = min_cal_op1 <= min_cal_op2;
	
	// д��ַ��Ϣ����״̬
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			aw_msg_upd_sts <= 3'b001;
		else if((aw_msg_upd_sts[STS_WAIT_ALLOW_AW_VLD] & to_allow_aw_vld) | 
			aw_msg_upd_sts[STS_GEN_AW_LEN] | 
			(aw_msg_upd_sts[STS_UPD_AW_ADDR] & pre_launch_wt_burst_allowed_full_n))
			aw_msg_upd_sts <= # simulation_delay {aw_msg_upd_sts[1:0], aw_msg_upd_sts[2]};
	end
	
	// ��ǰ��д��ַ
	always @(posedge clk)
	begin
		if((s_axis_wt_req_valid & s_axis_wt_req_ready) | 
			(pre_launch_wt_burst_committing_wen & pre_launch_wt_burst_allowed_full_n))
			aw_addr <= # simulation_delay 
				(s_axis_wt_req_valid & s_axis_wt_req_ready) ? {wt_baseaddr[31:3], 3'b000}: // �������ַ
				                                              {aw_addr[31:3] + aw_len + 1'b1, 3'b000}; // ����д��ַ
	end
	
	// ��ǰ4KB����ʣ�ഫ���� - 1
	always @(posedge clk)
	begin
		if((s_axis_wt_req_valid & s_axis_wt_req_ready) | 
			(pre_launch_wt_burst_committing_wen & pre_launch_wt_burst_allowed_full_n))
			// (s_axis_wt_req_valid & s_axis_wt_req_ready) ? 
			//     (9'd511 - wt_baseaddr[11:3]):(trans_n_remaining_in_4kB - aw_len - 1'b1)
			trans_n_remaining_in_4kB <= # simulation_delay (s_axis_wt_req_valid & s_axis_wt_req_ready) ? 
				(~wt_baseaddr[11:3]):(trans_n_remaining_in_4kB + {1'b1, ~aw_len});
	end
	
	// ʣ�ഫ���� - 1
	always @(posedge clk)
	begin
		if((s_axis_wt_req_valid & s_axis_wt_req_ready) | 
			(pre_launch_wt_burst_committing_wen & pre_launch_wt_burst_allowed_full_n))
			// (s_axis_wt_req_valid & s_axis_wt_req_ready) ? 
			//     wt_trans_n:(trans_n_remaining - aw_len - 1'b1)
			trans_n_remaining <= # simulation_delay (s_axis_wt_req_valid & s_axis_wt_req_ready) ? 
				wt_trans_n:(trans_n_remaining + {24'hff_ff_ff, ~aw_len});
	end
	
	// ���1��дͻ��(��־)
	always @(posedge clk)
	begin
		if(aw_msg_upd_sts[STS_GEN_AW_LEN])
			last_wt_burst <= # simulation_delay min_cal_op1_leq_op2;
	end
	
	// ���õ���Сֵ���㵥Ԫ(����Ĵ���)
	always @(posedge clk)
	begin
		if(((en_4KB_boundary_protection == "true") & aw_msg_upd_sts[STS_WAIT_ALLOW_AW_VLD] & to_allow_aw_vld) | 
			aw_msg_upd_sts[STS_GEN_AW_LEN])
			min_cal_res <= # simulation_delay min_cal_op1_leq_op2 ? min_cal_op1[7:0]:min_cal_op2;
	end
	
	/** AXI����д����ͳ�� **/
	wire launch_new_wt_burst; // Ԥ�����µ�дͻ��(ָʾ)
	wire wt_burst_finish; // дͻ�����(ָʾ)
	reg[clogb2(axi_waddr_outstanding):0] outstanding_wt_burst_n; // �����дͻ������
	reg outstanding_wt_burst_full_n; // �����дͻ��ͳ������
	reg outstanding_msg_fifo[0:axi_waddr_outstanding-1]; // ����д������Ϣfifo�Ĵ�����({�Ƿ񱾴�д��������1��ͻ��})
	reg[clogb2(axi_waddr_outstanding-1):0] outstanding_msg_fifo_wptr; // ����д������Ϣfifoдָ��
	reg[clogb2(axi_waddr_outstanding-1):0] outstanding_msg_fifo_rptr; // ����д������Ϣfifo��ָ��
	
	assign wt_req_fns = outstanding_msg_fifo[outstanding_msg_fifo_rptr] & wt_burst_finish;
	
	assign m_axi_bready = 1'b1;
	
	assign outstanding_stat_allow_aw_vld = outstanding_wt_burst_full_n;
	
	assign launch_new_wt_burst = pre_launch_wt_burst_committing_wen & pre_launch_wt_burst_allowed_full_n;
	assign wt_burst_finish = m_axi_bvalid;
	
	// �����дͻ������
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			outstanding_wt_burst_n <= 0;
		else if(launch_new_wt_burst ^ wt_burst_finish)
			outstanding_wt_burst_n <= # simulation_delay wt_burst_finish ? 
				(outstanding_wt_burst_n - 1):(outstanding_wt_burst_n + 1);
	end
	
	// �����дͻ��ͳ������
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			outstanding_wt_burst_full_n <= 1'b1;
		else if(launch_new_wt_burst ^ wt_burst_finish)
			// wt_burst_finish ? 1'b1:(outstanding_wt_burst_n != (axi_waddr_outstanding - 1))
			outstanding_wt_burst_full_n <= # simulation_delay 
				wt_burst_finish | (outstanding_wt_burst_n != (axi_waddr_outstanding - 1));
	end
	
	// ����д������Ϣfifo�Ĵ�����
	genvar outstanding_msg_fifo_i;
	generate
		for(outstanding_msg_fifo_i = 0;outstanding_msg_fifo_i < axi_waddr_outstanding;
			outstanding_msg_fifo_i = outstanding_msg_fifo_i + 1)
		begin
			always @(posedge clk)
			begin
				if(launch_new_wt_burst & (outstanding_msg_fifo_wptr == outstanding_msg_fifo_i))
					outstanding_msg_fifo[outstanding_msg_fifo_i] <= # simulation_delay last_wt_burst;
			end
		end
	endgenerate
	
	// ����д������Ϣfifoдָ��
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			outstanding_msg_fifo_wptr <= 0;
		else if(launch_new_wt_burst)
			outstanding_msg_fifo_wptr <= # simulation_delay 
				// (outstanding_msg_fifo_wptr == (axi_waddr_outstanding-1)) ? 0:(outstanding_msg_fifo_wptr + 1)
				{(clogb2(axi_waddr_outstanding-1)+1){outstanding_msg_fifo_wptr != (axi_waddr_outstanding-1)}} & 
				(outstanding_msg_fifo_wptr + 1);
	end
	
	// ����д������Ϣfifo��ָ��
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			outstanding_msg_fifo_rptr <= 0;
		else if(wt_burst_finish)
			outstanding_msg_fifo_rptr <= # simulation_delay 
				// (outstanding_msg_fifo_rptr == (axi_waddr_outstanding-1)) ? 0:(outstanding_msg_fifo_rptr + 1)
				{(clogb2(axi_waddr_outstanding-1)+1){outstanding_msg_fifo_rptr != (axi_waddr_outstanding-1)}} & 
				(outstanding_msg_fifo_rptr + 1);
	end
	
	/** д������Ϣfifo **/
	// fifoд�˿�
	wire wt_req_msg_fifo_wen;
	wire[5:0] wt_req_msg_fifo_din; // {�״δ�����ֽ���Ч������(3bit), ���1�δ�����ֽ���Ч������(3bit)}
	wire wt_req_msg_fifo_full_n;
	// fifo���˿�
	wire wt_req_msg_fifo_ren;
	wire[5:0] wt_req_msg_fifo_dout; // {�״δ�����ֽ���Ч������(3bit), ���1�δ�����ֽ���Ч������(3bit)}
	wire wt_req_msg_fifo_empty_n;
	
	assign wt_req_msg_fifo_allow_ready = wt_req_msg_fifo_full_n;
	
	// ��������: s_axis_wt_req_valid & wt_req_ready & wt_req_msg_fifo_full_n
	assign wt_req_msg_fifo_wen = s_axis_wt_req_valid & wt_req_ready;
	assign wt_req_msg_fifo_din = {first_trans_keep_id, last_trans_keep_id};
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.fifo_depth(3),
		.fifo_data_width(6),
		.almost_full_th(),
		.almost_empty_th(),
		.simulation_delay(simulation_delay)
	)wt_req_msg_fifo(
		.clk(clk),
		.rst_n(rst_n),
		
		.fifo_wen(wt_req_msg_fifo_wen),
		.fifo_din(wt_req_msg_fifo_din),
		.fifo_full_n(wt_req_msg_fifo_full_n),
		
		.fifo_ren(wt_req_msg_fifo_ren),
		.fifo_dout(wt_req_msg_fifo_dout),
		.fifo_empty_n(wt_req_msg_fifo_empty_n)
	);
	
	/** AXIд����buffer **/
	// �������ռ�
	reg first_feature; // ��1��������(��־)
	wire last_feature; // ���1��������(��־)
	reg[feature_data_width-1:0] feature_set[0:64/feature_data_width-1]; // �����㼯��
	wire on_load_feature; // ������װ��(ָʾ)
	wire[64/feature_data_width-1:0] feature_upd_vec_first; // д�����׸����������ʹ������
	wire[64/feature_data_width-1:0] trm_last_ft_id; // ���1�δ�������1����Ч��������(������)
	wire[64/feature_data_width-1:0] feature_upd_vec_cur; // ��ǰ���������ʹ������
	wire[64/feature_data_width-1:0] feature_upd_vec_nxt; // ��һ���������ʹ������
	reg[64/feature_data_width-1:0] feature_upd_vec_regs; // ���������ʹ�ܼĴ�������
	wire feature_upd_vec_match_trm_last_ft_id; // ��ǰ���������ʹ������ <-> ���1�δ�������1����Ч��������(ƥ���־)
	// д��������
	reg first_trans; // ��1������(��־)
	wire loading_last_of_feature_set; // ���������㼯�ϵ����1��(��־)
	reg[7:0] wt_burst_data_id; // дͻ��������(������)
	wire wt_burst_last_trans; // ����дͻ�����1�δ���(��־)
	wire[7:0] wdata_gen_keep_s0; // д�������ɵ�0��keep
	wire wdata_gen_last_s0; // д�������ɵ�0��last
	wire wdata_gen_valid_s0; // д�������ɵ�0��valid
	wire wdata_gen_ready_s0; // д�������ɵ�0��ready
	reg[7:0] wdata_gen_keep_s1; // д�������ɵ�1��keep
	reg wdata_gen_last_s1; // д�������ɵ�1��last
	reg wdata_gen_valid_s1; // д�������ɵ�1��valid
	wire wdata_gen_ready_s1; // д�������ɵ�1��ready
	// keep�ź�����
	wire[2:0] wdata_first_kid; // д�����1�����ݵ��ֽ�ʹ��������
	wire[2:0] wdata_last_kid; // д�������1�����ݵ��ֽ�ʹ��������
	wire[7:0] wdata_first_keep; // д�����1�����ݵ�keep�ź�
	wire[7:0] wdata_last_keep; // д�������1�����ݵ�keep�ź�
	// д���ݻ���fifoд�˿�
	wire wdata_buf_fifo_wen;
	wire[63:0] wdata_buf_fifo_din;
	wire[64/feature_data_width-1:0] wdata_buf_fifo_din_keep;
	wire wdata_buf_fifo_din_last;
	wire wdata_buf_fifo_full_n;
	// д���ݻ���fifo���˿�
	wire wdata_buf_fifo_ren;
	wire[63:0] wdata_buf_fifo_dout;
	wire[64/feature_data_width-1:0] wdata_buf_fifo_dout_keep;
	wire wdata_buf_fifo_dout_last;
	wire wdata_buf_fifo_empty_n;
	
	// ��������: s_axis_res_valid & wt_req_msg_fifo_empty_n & wt_burst_msg_available_empty_n & 
	//     (loading_last_of_feature_set ? wdata_gen_ready_s0:1'b1)
	assign s_axis_res_ready = wt_req_msg_fifo_empty_n & wt_burst_msg_available_empty_n & 
		((~loading_last_of_feature_set) | wdata_gen_ready_s0);
	
	assign m_axi_wdata = wdata_buf_fifo_dout;
	assign m_axi_wstrb = 
		(feature_data_width == 8) ?  wdata_buf_fifo_dout_keep:
		(feature_data_width == 16) ? {{2{wdata_buf_fifo_dout_keep[3]}}, {2{wdata_buf_fifo_dout_keep[2]}}, 
									     {2{wdata_buf_fifo_dout_keep[1]}}, {2{wdata_buf_fifo_dout_keep[0]}}}:
		(feature_data_width == 32) ? {{4{wdata_buf_fifo_dout_keep[1]}}, {4{wdata_buf_fifo_dout_keep[0]}}}:
		                             8'hff;
	assign m_axi_wlast = wdata_buf_fifo_dout_last;
	assign m_axi_wvalid = wdata_buf_fifo_empty_n;
	assign wdata_buf_fifo_ren = m_axi_wready;
	
	// ��������: s_axis_res_valid & wt_req_msg_fifo_empty_n & wt_burst_msg_available_empty_n & 
	//     wdata_gen_ready_s0 & s_axis_res_last
	// ����: ����д�������1������ʱ�ض����������㼯�ϵ����1��!
	assign wt_req_msg_fifo_ren = s_axis_res_valid & wt_burst_msg_available_empty_n & 
		wdata_gen_ready_s0 & s_axis_res_last;
	// ��������: s_axis_res_valid & wt_req_msg_fifo_empty_n & wt_burst_msg_available_empty_n & 
	//     loading_last_of_feature_set & wdata_gen_ready_s0 & wt_burst_last_trans
	assign wdata_prepared_ren = s_axis_res_valid & loading_last_of_feature_set & 
		wt_req_msg_fifo_empty_n & wdata_gen_ready_s0 & wt_burst_last_trans;
	
	assign last_feature = s_axis_res_last;
	assign on_load_feature = s_axis_res_valid & s_axis_res_ready;
	
	genvar feature_upd_vec_first_trm_i;
	generate
		for(feature_upd_vec_first_trm_i = 0;feature_upd_vec_first_trm_i < 64/feature_data_width;
			feature_upd_vec_first_trm_i = feature_upd_vec_first_trm_i + 1)
		begin
			assign feature_upd_vec_first[feature_upd_vec_first_trm_i] = 
				(feature_data_width == 64) | 
				(wt_req_msg_fifo_dout[5:5-clogb2(64/feature_data_width-1)] == feature_upd_vec_first_trm_i);
			assign trm_last_ft_id[feature_upd_vec_first_trm_i] = 
				(feature_data_width == 64) | 
				(wt_req_msg_fifo_dout[2:2-clogb2(64/feature_data_width-1)] == feature_upd_vec_first_trm_i);
		end
	endgenerate
	
	assign feature_upd_vec_cur = first_feature ? feature_upd_vec_first:feature_upd_vec_regs;
	
	generate
		if(feature_data_width < 64)
		begin
			assign feature_upd_vec_nxt = 
				{feature_upd_vec_cur[64/feature_data_width-2:0], feature_upd_vec_cur[64/feature_data_width-1]};
			assign feature_upd_vec_match_trm_last_ft_id = |(feature_upd_vec_cur & trm_last_ft_id);
		end
		else
		begin
			assign feature_upd_vec_nxt = 1'b1;
			assign feature_upd_vec_match_trm_last_ft_id = 1'b1;
		end
	endgenerate
	
	assign loading_last_of_feature_set = feature_upd_vec_cur[64/feature_data_width-1] | 
		(last_feature & feature_upd_vec_match_trm_last_ft_id);
	assign wt_burst_last_trans = wt_burst_data_id == wt_burst_msg_dout;
	/*
	({first_trans, last_feature} == 2'b00) ? 8'b1111_1111:
	({first_trans, last_feature} == 2'b01) ? wdata_last_keep:
	({first_trans, last_feature} == 2'b10) ? wdata_first_keep:
														 (wdata_first_keep & wdata_last_keep)
	*/
	assign wdata_gen_keep_s0 = 
		({8{~first_trans}} | wdata_first_keep) & 
		({8{~last_feature}} | wdata_last_keep);
	assign wdata_gen_last_s0 = wt_burst_last_trans;
	// ��������: s_axis_res_valid & wt_req_msg_fifo_empty_n & wt_burst_msg_available_empty_n & 
	//     loading_last_of_feature_set & wdata_gen_ready_s0
	assign wdata_gen_valid_s0 = s_axis_res_valid & loading_last_of_feature_set & 
		wt_req_msg_fifo_empty_n & wt_burst_msg_available_empty_n;
	assign wdata_gen_ready_s0 = (~wdata_gen_valid_s1) | wdata_gen_ready_s1;
	assign wdata_gen_ready_s1 = wdata_buf_fifo_full_n;
	
	assign wdata_first_kid = 
		(feature_data_width == 8)  ? wt_req_msg_fifo_dout[5:3]:
		(feature_data_width == 16) ? {wt_req_msg_fifo_dout[5:4], 1'b0}:
		(feature_data_width == 32) ? {wt_req_msg_fifo_dout[5], 2'b00}:
		                             3'b000;
	assign wdata_last_kid = 
		(feature_data_width == 8)  ? wt_req_msg_fifo_dout[2:0]:
		(feature_data_width == 16) ? {wt_req_msg_fifo_dout[2:1], 1'b1}:
		(feature_data_width == 32) ? {wt_req_msg_fifo_dout[2], 2'b11}:
		                             3'b111;
	assign wdata_first_keep = {
		1'b1, wdata_first_kid <= 3'd6,
		wdata_first_kid <= 3'd5, wdata_first_kid <= 3'd4,
		wdata_first_kid <= 3'd3, wdata_first_kid <= 3'd2,
		wdata_first_kid <= 3'd1, wdata_first_kid == 3'd0};
	assign wdata_last_keep = {
		wdata_last_kid == 3'd7, wdata_last_kid >= 3'd6,
		wdata_last_kid >= 3'd5, wdata_last_kid >= 3'd4,
		wdata_last_kid >= 3'd3, wdata_last_kid >= 3'd2,
		wdata_last_kid >= 3'd1, 1'b1};
	
	assign wdata_buf_fifo_wen = wdata_gen_valid_s1;
	assign wdata_buf_fifo_din = 
		(feature_data_width == 8) ?  {feature_set[7], feature_set[6], feature_set[5], feature_set[4], 
			                             feature_set[3], feature_set[2], feature_set[1], feature_set[0]}:
		(feature_data_width == 16) ? {feature_set[3], feature_set[2], feature_set[1], feature_set[0]}:
		(feature_data_width == 32) ? {feature_set[1], feature_set[0]}:
									 feature_set[0];
	
	
	assign wdata_buf_fifo_din_keep = 
		(feature_data_width == 8) ?  wdata_gen_keep_s1:
		(feature_data_width == 16) ? {wdata_gen_keep_s1[6], wdata_gen_keep_s1[4], wdata_gen_keep_s1[2], wdata_gen_keep_s1[0]}:
		(feature_data_width == 32) ? {wdata_gen_keep_s1[4], wdata_gen_keep_s1[0]}:
		                             1'b1;
	assign wdata_buf_fifo_din_last = wdata_gen_last_s1;
	
	// ��1��������(��־)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			first_feature <= 1'b1;
		else if(on_load_feature)
			first_feature <= # simulation_delay last_feature;
	end
	
	// �����㼯��
	genvar feature_set_i;
	generate
		for(feature_set_i = 0;feature_set_i < 64/feature_data_width;feature_set_i = feature_set_i + 1)
		begin
			always @(posedge clk)
			begin
				if(on_load_feature & feature_upd_vec_cur[feature_set_i])
					feature_set[feature_set_i] <= # simulation_delay s_axis_res_data;
			end
		end
	endgenerate
	
	// ���������ʹ�ܼĴ�������
	always @(posedge clk)
	begin
		if(on_load_feature)
			feature_upd_vec_regs <= # simulation_delay feature_upd_vec_nxt;
	end
	
	// ��1������(��־)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			first_trans <= 1'b1;
		else if(wdata_gen_valid_s0 & wdata_gen_ready_s0)
			first_trans <= # simulation_delay last_feature;
	end
	
	// дͻ��������(������)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wt_burst_data_id <= 8'd0;
		else if(wdata_gen_valid_s0 & wdata_gen_ready_s0)
			// wt_burst_last_trans ? 8'd0:(wt_burst_data_id + 8'd1)
			wt_burst_data_id <= # simulation_delay {8{~wt_burst_last_trans}} & (wt_burst_data_id + 8'd1);
	end
	
	// д�������ɵ�1��keep
	always @(posedge clk)
	begin
		if(wdata_gen_valid_s0 & wdata_gen_ready_s0)
			wdata_gen_keep_s1 <= # simulation_delay wdata_gen_keep_s0;
	end
	
	// д�������ɵ�1��last
	always @(posedge clk)
	begin
		if(wdata_gen_valid_s0 & wdata_gen_ready_s0)
			wdata_gen_last_s1 <= # simulation_delay wdata_gen_last_s0;
	end
	
	// д�������ɵ�1��valid
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wdata_gen_valid_s1 <= 1'b0;
		else if(wdata_gen_ready_s0)
			wdata_gen_valid_s1 <= # simulation_delay wdata_gen_valid_s0;
	end
	
	// AXIд����buffer
	ram_fifo_wrapper #(
		.fwft_mode("true"),
		.ram_type("bram"),
		.en_bram_reg("false"),
		.fifo_depth(axi_wdata_buffer_depth),
		.fifo_data_width(64 + 64 / feature_data_width + 1),
		.full_assert_polarity("low"),
		.empty_assert_polarity("low"),
		.almost_full_assert_polarity("no"),
		.almost_empty_assert_polarity("no"),
		.en_data_cnt("false"),
		.almost_full_th(),
		.almost_empty_th(),
		.simulation_delay(simulation_delay)
	)wdata_buf_fifo(
		.clk(clk),
		.rst_n(rst_n),
		
		.fifo_wen(wdata_buf_fifo_wen),
		.fifo_din({wdata_buf_fifo_din, wdata_buf_fifo_din_keep, wdata_buf_fifo_din_last}),
		.fifo_full_n(wdata_buf_fifo_full_n),
		
		.fifo_ren(wdata_buf_fifo_ren),
		.fifo_dout({wdata_buf_fifo_dout, wdata_buf_fifo_dout_keep, wdata_buf_fifo_dout_last}),
		.fifo_empty_n(wdata_buf_fifo_empty_n)
	);
	
endmodule
