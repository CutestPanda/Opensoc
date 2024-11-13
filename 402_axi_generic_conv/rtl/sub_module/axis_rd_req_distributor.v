`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXIS�������ɷ���Ԫ

����:
����������������, ������������ͼ/�����/���Բ�����������ɷ���Ϣ��

ÿ�������������ӵĳ�����64bit -> 
	λ���            ����
	 31~0            ����ַ
	 33~32      �ɷ�Ŀ�����ͱ��
	         (2'b00 -> ���Բ�������, 
			 2'b01 -> ����˲�������, 
			 2'b10 -> ��������ͼ����)
	 35~34         ���ݰ���Ϣ
              (���ɷ���Ϣ��������)
	 63~36       ����ȡ���ֽ���

ע�⣺
��

Э��:
AXIS MASTER/SLAVE

����: �¼�ҫ
����: 2024/11/07
********************************************************************/


module axis_rd_req_distributor #(
	parameter integer max_rd_btt = 4 * 512, // ���Ķ������ֽ���(256 | 512 | 1024 | ...)
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
	input wire clk,
	input wire rst_n,
	
	// ������������(AXIS�ӻ�)
	input wire[63:0] s_axis_dsc_data,
	input wire s_axis_dsc_valid,
	output wire s_axis_dsc_ready,
	
	// ��������ͼ/�����/���Բ���������(AXIS����)
	output wire[63:0] m_axis_rd_req_data, // {����ȡ���ֽ���(32bit), ����ַ(32bit)}
	output wire m_axis_rd_req_valid,
	input wire m_axis_rd_req_ready,
	
	// �ɷ���Ϣ��(AXIS����)
	/*
	λ���
     7~5    ����
	 4~3    �ɷ�����������ͼ���� -> {�����Ƿ���Ч, ��ǰ���������1�б�־}
	        �ɷ�������˲������� -> {��ǰ��ͨ��������Ƿ���Ч, 1'bx}
	        �ɷ������Բ�������   -> {���Բ����Ƿ���Ч, ���Բ�������(1'b0 -> A, 1'b1 -> B)}
	  2     �ɷ�����������ͼ����
	  1     �ɷ�������˲�������
	  0     �ɷ������Բ�������
	*/
	output wire[7:0] m_axis_dispatch_msg_data,
	output wire m_axis_dispatch_msg_valid,
	input wire m_axis_dispatch_msg_ready
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
	// �ɷ�Ŀ�����ͱ��
	localparam DISPATCH_TARGET_LINEAR_PARS = 2'b00; // �ɷ�Ŀ������: ���Բ�������
	localparam DISPATCH_TARGET_KERNAL_PARS = 2'b01; // �ɷ�Ŀ������: ����˲�������
	localparam DISPATCH_TARGET_FT_MAP = 2'b10; // �ɷ�Ŀ������: ��������ͼ����
	
	/** ������������ **/
	wire[31:0] rd_req_baseaddr; // ���������ַ
	wire[clogb2(max_rd_btt):0] rd_req_btt; // ����ȡ���ֽ���
	wire[1:0] dispatch_target; // �ɷ�Ŀ�����ͱ��
	wire[1:0] pkt_msg; // ���ݰ���Ϣ
	
	assign rd_req_baseaddr = s_axis_dsc_data[31:0];
	assign dispatch_target = s_axis_dsc_data[33:32];
	assign pkt_msg = s_axis_dsc_data[35:34];
	assign rd_req_btt = s_axis_dsc_data[63:36];
	
	/** ������������AXIS�ӻ� **/
	wire ft_map_pars_fifo_full_n; // ��������ͼ/�����/���Բ���������fifo����־
	wire dispatch_msg_fifo_full_n; // �ɷ���Ϣfifo����־
	
	// ��������: s_axis_dsc_valid & ft_map_pars_fifo_full_n & dispatch_msg_fifo_full_n
	assign s_axis_dsc_ready = ft_map_pars_fifo_full_n & dispatch_msg_fifo_full_n;
	
	/** ��������ͼ/�����/���Բ���������fifo **/
	// fifoд�˿�
	wire ft_map_pars_fifo_wen;
	wire[32+clogb2(max_rd_btt):0] ft_map_pars_fifo_din;
	// fifo���˿�
	wire ft_map_pars_fifo_ren;
	wire[32+clogb2(max_rd_btt):0] ft_map_pars_fifo_dout;
	wire ft_map_pars_fifo_empty_n;
	
	// ��������: s_axis_dsc_valid & ft_map_pars_fifo_full_n & dispatch_msg_fifo_full_n & pkt_msg[1]
	assign ft_map_pars_fifo_wen = s_axis_dsc_valid & dispatch_msg_fifo_full_n & pkt_msg[1];
	assign ft_map_pars_fifo_din = {rd_req_btt, rd_req_baseaddr};
	
	assign m_axis_rd_req_data = ft_map_pars_fifo_dout;
	assign m_axis_rd_req_valid = ft_map_pars_fifo_empty_n;
	assign ft_map_pars_fifo_ren = m_axis_rd_req_ready;
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.fifo_depth(4),
		.fifo_data_width(32+clogb2(max_rd_btt)+1),
		.almost_full_th(),
		.almost_empty_th(),
		.simulation_delay(simulation_delay)
	)ft_map_pars_fifo(
		.clk(clk),
		.rst_n(rst_n),
		
		.fifo_wen(ft_map_pars_fifo_wen),
		.fifo_din(ft_map_pars_fifo_din),
		.fifo_full_n(ft_map_pars_fifo_full_n),
		
		.fifo_ren(ft_map_pars_fifo_ren),
		.fifo_dout(ft_map_pars_fifo_dout),
		.fifo_empty_n(ft_map_pars_fifo_empty_n)
	);
	
	/** �ɷ���Ϣfifo **/
	// fifoд�˿�
	wire dispatch_msg_fifo_wen;
	wire[3:0] dispatch_msg_fifo_din;
	// fifo���˿�
	wire dispatch_msg_fifo_ren;
	wire[3:0] dispatch_msg_fifo_dout;
	wire dispatch_msg_fifo_empty_n;
	
	// ��������: s_axis_dsc_valid & ft_map_pars_fifo_full_n & dispatch_msg_fifo_full_n
	assign dispatch_msg_fifo_wen = s_axis_dsc_valid & ft_map_pars_fifo_full_n;
	assign dispatch_msg_fifo_din = {pkt_msg, dispatch_target};
	
	assign m_axis_dispatch_msg_data = {
		3'b000, 
		dispatch_msg_fifo_dout[3:2], 
		dispatch_msg_fifo_dout[1:0] == DISPATCH_TARGET_FT_MAP,
		dispatch_msg_fifo_dout[1:0] == DISPATCH_TARGET_KERNAL_PARS,
		dispatch_msg_fifo_dout[1:0] == DISPATCH_TARGET_LINEAR_PARS
	};
	assign m_axis_dispatch_msg_valid = dispatch_msg_fifo_empty_n;
	assign dispatch_msg_fifo_ren = m_axis_dispatch_msg_ready;
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.fifo_depth(4),
		.fifo_data_width(4),
		.almost_full_th(),
		.almost_empty_th(),
		.simulation_delay(simulation_delay)
	)dispatch_msg_fifo(
		.clk(clk),
		.rst_n(rst_n),
		
		.fifo_wen(dispatch_msg_fifo_wen),
		.fifo_din(dispatch_msg_fifo_din),
		.fifo_full_n(dispatch_msg_fifo_full_n),
		
		.fifo_ren(dispatch_msg_fifo_ren),
		.fifo_dout(dispatch_msg_fifo_dout),
		.fifo_empty_n(dispatch_msg_fifo_empty_n)
	);
	
endmodule
