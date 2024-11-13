`timescale 1ns / 1ps
/********************************************************************
��ģ��: ��/д��������������AXI������ͨ���ٲ�

����:
�Զ�/д����������DMA��AXI������ͨ�������ٲ�, �ϲ���1��AXI������ͨ��

ע�⣺
��

Э��:
AXI MASTER/SLAVE(READ ONLY)

����: �¼�ҫ
����: 2024/11/10
********************************************************************/


module axi_arb_for_rw_req_dsc #(
	parameter integer arb_msg_fifo_depth = 4, // �ٲ���Ϣfifo���
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
	input wire clk,
	input wire rst_n,
	
	// �ٲ�����#0
	// AR
    input wire[31:0] s_axi_rd_req_dsc_araddr,
    input wire[1:0] s_axi_rd_req_dsc_arburst, // ignored
    input wire[7:0] s_axi_rd_req_dsc_arlen,
    input wire[2:0] s_axi_rd_req_dsc_arsize, // ignored
    input wire s_axi_rd_req_dsc_arvalid,
    output wire s_axi_rd_req_dsc_arready,
    // R
    output wire[63:0] s_axi_rd_req_dsc_rdata,
    output wire[1:0] s_axi_rd_req_dsc_rresp,
    output wire s_axi_rd_req_dsc_rlast,
    output wire s_axi_rd_req_dsc_rvalid,
    input wire s_axi_rd_req_dsc_rready,
	
	// �ٲ�����#1
	// AR
    input wire[31:0] s_axi_wt_req_dsc_araddr,
    input wire[1:0] s_axi_wt_req_dsc_arburst, // ignored
    input wire[7:0] s_axi_wt_req_dsc_arlen,
    input wire[2:0] s_axi_wt_req_dsc_arsize, // ignored
    input wire s_axi_wt_req_dsc_arvalid,
    output wire s_axi_wt_req_dsc_arready,
    // R
    output wire[63:0] s_axi_wt_req_dsc_rdata,
    output wire[1:0] s_axi_wt_req_dsc_rresp,
    output wire s_axi_wt_req_dsc_rlast,
    output wire s_axi_wt_req_dsc_rvalid,
    input wire s_axi_wt_req_dsc_rready,
	
	// �ٲ����
	// AR
    output wire[31:0] m_axi_rw_req_dsc_araddr,
    output wire[1:0] m_axi_rw_req_dsc_arburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_rw_req_dsc_arlen,
    output wire[2:0] m_axi_rw_req_dsc_arsize, // const -> 3'b011
    output wire m_axi_rw_req_dsc_arvalid,
    input wire m_axi_rw_req_dsc_arready,
    // R
    input wire[63:0] m_axi_rw_req_dsc_rdata,
    input wire[1:0] m_axi_rw_req_dsc_rresp,
    input wire m_axi_rw_req_dsc_rlast,
    input wire m_axi_rw_req_dsc_rvalid,
    output wire m_axi_rw_req_dsc_rready
);
    
	/** �ٲ���Ϣfifo **/
	// fifoд�˿�
	wire arb_msg_fifo_wen;
	wire[1:0] arb_msg_fifo_din; // {ѡ��ͨ��#1, ѡ��ͨ��#0}
	wire arb_msg_fifo_full_n;
	// fifo���˿�
	wire arb_msg_fifo_ren;
	wire[1:0] arb_msg_fifo_dout; // {ѡ��ͨ��#1, ѡ��ͨ��#0}
	wire arb_msg_fifo_empty_n;
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.fifo_depth(arb_msg_fifo_depth),
		.fifo_data_width(2),
		.almost_full_th(),
		.almost_empty_th(),
		.simulation_delay(simulation_delay)
	)arb_msg_fifo(
		.clk(clk),
		.rst_n(rst_n),
		
		.fifo_wen(arb_msg_fifo_wen),
		.fifo_din(arb_msg_fifo_din),
		.fifo_full_n(arb_msg_fifo_full_n),
		
		.fifo_ren(arb_msg_fifo_ren),
		.fifo_dout(arb_msg_fifo_dout),
		.fifo_empty_n(arb_msg_fifo_empty_n)
	);
	
	/** ����ַͨ���ٲ� **/
	wire[1:0] rd_access_req; // ������({ͨ��#1, ͨ��#0})
	wire[1:0] rd_access_grant; // �����({ͨ��#1, ͨ��#0})
	reg ar_valid; // ����ַͨ����valid�ź�
	reg[1:0] ar_ready; // ����ַͨ����ready�ź�({ͨ��#1, ͨ��#0})
	reg[31:0] araddr_latched; // ����Ķ���ַ
	reg[7:0] arlen_latched; // �����(��ͻ������ - 1)
	
	assign {s_axi_wt_req_dsc_arready, s_axi_rd_req_dsc_arready} = ar_ready;
	
	assign m_axi_rw_req_dsc_araddr = araddr_latched;
	assign m_axi_rw_req_dsc_arburst = 2'b01;
	assign m_axi_rw_req_dsc_arlen = arlen_latched;
	assign m_axi_rw_req_dsc_arsize = 3'b011;
	assign m_axi_rw_req_dsc_arvalid = ar_valid;
	
	assign arb_msg_fifo_wen = (~ar_valid) & (s_axi_wt_req_dsc_arvalid | s_axi_rd_req_dsc_arvalid);
	assign arb_msg_fifo_din = rd_access_grant;
	
	assign rd_access_req = {2{(~ar_valid) & arb_msg_fifo_full_n}} & {s_axi_wt_req_dsc_arvalid, s_axi_rd_req_dsc_arvalid};
	
	// ����ַͨ����valid�ź�
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			ar_valid <= 1'b0;
		else
			ar_valid <= # simulation_delay ar_valid ? 
				(~m_axi_rw_req_dsc_arready):(arb_msg_fifo_full_n & (s_axi_wt_req_dsc_arvalid | s_axi_rd_req_dsc_arvalid));
	end
	
	// ����ַͨ����ready�ź�
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			ar_ready <= 2'b00;
		else
			ar_ready <= # simulation_delay rd_access_grant;
	end
	
	// ����Ķ���ַ
	always @(posedge clk)
	begin
		if((~ar_valid) & arb_msg_fifo_full_n & (s_axi_wt_req_dsc_arvalid | s_axi_rd_req_dsc_arvalid))
			araddr_latched <= # simulation_delay rd_access_grant[0] ? s_axi_rd_req_dsc_araddr:s_axi_wt_req_dsc_araddr;
	end
	
	// �����(��ͻ������ - 1)
	always @(posedge clk)
	begin
		if((~ar_valid) & arb_msg_fifo_full_n & (s_axi_wt_req_dsc_arvalid | s_axi_rd_req_dsc_arvalid))
			arlen_latched <= # simulation_delay rd_access_grant[0] ? s_axi_rd_req_dsc_arlen:s_axi_wt_req_dsc_arlen;
	end
	
	// Round-Robin�ٲ���
	round_robin_arbitrator #(
		.chn_n(2),
		.simulation_delay(simulation_delay)
	)round_robin_arbitrator_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.req(rd_access_req),
		.grant(rd_access_grant),
		.sel(),
		.arb_valid()
	);
	
	/** ������ѡ�� **/
	assign s_axi_rd_req_dsc_rdata = m_axi_rw_req_dsc_rdata;
	assign s_axi_rd_req_dsc_rresp = m_axi_rw_req_dsc_rresp;
	assign s_axi_rd_req_dsc_rlast = m_axi_rw_req_dsc_rlast;
	// ��������: arb_msg_fifo_empty_n & arb_msg_fifo_dout[0] & s_axi_rd_req_dsc_rready & m_axi_rw_req_dsc_rvalid
	assign s_axi_rd_req_dsc_rvalid = arb_msg_fifo_empty_n & arb_msg_fifo_dout[0] & m_axi_rw_req_dsc_rvalid;
	
	assign s_axi_wt_req_dsc_rdata = m_axi_rw_req_dsc_rdata;
	assign s_axi_wt_req_dsc_rresp = m_axi_rw_req_dsc_rresp;
	assign s_axi_wt_req_dsc_rlast = m_axi_rw_req_dsc_rlast;
	// ��������: arb_msg_fifo_empty_n & (~arb_msg_fifo_dout[0]) & s_axi_wt_req_dsc_rready & m_axi_rw_req_dsc_rvalid
	assign s_axi_wt_req_dsc_rvalid = arb_msg_fifo_empty_n & (~arb_msg_fifo_dout[0]) & m_axi_rw_req_dsc_rvalid;
	
	// ��������: arb_msg_fifo_empty_n & (arb_msg_fifo_dout[0] ? s_axi_rd_req_dsc_rready:s_axi_wt_req_dsc_rready) & 
	//     m_axi_rw_req_dsc_rvalid
	assign m_axi_rw_req_dsc_rready = arb_msg_fifo_empty_n & 
		(arb_msg_fifo_dout[0] ? s_axi_rd_req_dsc_rready:s_axi_wt_req_dsc_rready);
	
	// ��������: arb_msg_fifo_empty_n & (arb_msg_fifo_dout[0] ? s_axi_rd_req_dsc_rready:s_axi_wt_req_dsc_rready) & 
	//     m_axi_rw_req_dsc_rvalid & m_axi_rw_req_dsc_rlast
	assign arb_msg_fifo_ren = (arb_msg_fifo_dout[0] ? s_axi_rd_req_dsc_rready:s_axi_wt_req_dsc_rready) & 
		m_axi_rw_req_dsc_rvalid & m_axi_rw_req_dsc_rlast;
	
endmodule
