`timescale 1ns / 1ps
/********************************************************************
��ģ��: ���ڻ�ȡ��/д���������ӵ�AXI��ͨ��

����:
ͨ��AXI��ͨ���Ӷ�/д���󻺴�����ȡ������, ������������

32λ��ַ64λ���ݵ�AXI��ͨ��

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

ÿ��д���������ӵĳ�����64bit -> 
	λ���            ����
	 31~0            ����ַ
	 63~32       ��д����ֽ���

ע�⣺
���뱣֤��/д���󻺴����׵�ַ�ܱ�(axi_rchn_max_burst_len*8)����, �Ӷ�ȷ��ÿ��ͻ�����䲻���Խ4KB�߽�

Э��:
BLK CTRL
AXIS MASTER
AXI MASTER(READ ONLY)

����: �¼�ҫ
����: 2024/11/08
********************************************************************/


module axi_rw_req_dsc_dma #(
	parameter integer max_req_n = 1024, // ���Ķ�/д�������
	parameter integer axi_rchn_max_burst_len = 8, // AXI��ͨ�����ͻ������(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer rw_req_dsc_buffer_depth = 512, // ��/д����������buffer���(256 | 512 | 1024 | ...)
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
	input wire clk,
	input wire rst_n,
	
	// ����ʱ����
	input wire[31:0] req_buf_baseaddr, // ��/д���󻺴����׵�ַ
	input wire[31:0] req_n, // ��/д������� - 1
	
	// �鼶����
	input wire blk_start,
	output wire blk_idle,
	output wire blk_done,
	
	// ��/д����������(AXIS����)
	output wire[63:0] m_axis_dsc_data,
	output wire m_axis_dsc_valid,
	input wire m_axis_dsc_ready,
	
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
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
    end
    endfunction
	
	/** �鼶���� **/
	reg blk_idle_reg; // DMA���б�־
	
	assign blk_idle = blk_idle_reg;
	
	// DMA���б�־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			blk_idle_reg <= 1'b1;
		else
			blk_idle_reg <= # simulation_delay blk_idle ? (~blk_start):blk_done;
	end
	
	/** AXI����ַͨ�� **/
	wire rw_req_dsc_buf_allow_ar_trans; // ��/д����������buffer������������ַ����(��־)
	reg[31:0] araddr; // ����ַ
	reg[7:0] arlen; // ��ͻ������
	reg arvalid; // ����ַͨ����Ч
	reg[clogb2(max_req_n-1):0] req_n_remaining; // ʣ��Ķ�/д������� - 1
	wire[clogb2(max_req_n-1):0] arlen_cmp; // �������ɶ�ͻ�����ȵ�(ʣ��Ķ�/д������� - 1)
	reg ar_last; // ���1������ַ(��־)
	reg last_rd_burst_processing; // ���ڴ������1����ͻ��(��־)
	reg rd_burst_processing; // ��ͻ��������(��־)
	
	assign blk_done = m_axi_rvalid & m_axi_rready & m_axi_rlast & last_rd_burst_processing;
	
	assign m_axi_araddr = araddr;
	assign m_axi_arburst = 2'b01;
	assign m_axi_arlen = arlen;
	assign m_axi_arsize = 3'b011;
	assign m_axi_arvalid = arvalid;
	
	assign arlen_cmp = (blk_start & blk_idle) ? req_n[clogb2(max_req_n-1):0]:req_n_remaining;
	
	// ����ַ
	always @(posedge clk)
	begin
		if((blk_start & blk_idle) | (m_axi_arvalid & m_axi_arready))
			araddr <= # simulation_delay (blk_start & blk_idle) ? 
				req_buf_baseaddr:(araddr + (axi_rchn_max_burst_len * 8));
	end
	
	// ��ͻ������
	always @(posedge clk)
	begin
		if((blk_start & blk_idle) | (m_axi_arvalid & m_axi_arready))
			arlen <= # simulation_delay (arlen_cmp <= (axi_rchn_max_burst_len - 1)) ? 
				arlen_cmp:(axi_rchn_max_burst_len - 1);
	end
	
	// ����ַͨ����Ч
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			arvalid <= 1'b0;
		else
			arvalid <= # simulation_delay arvalid ? 
				(~m_axi_arready):((~blk_idle) & rw_req_dsc_buf_allow_ar_trans & (~rd_burst_processing));
	end
	
	// ʣ��Ķ�/д������� - 1
	always @(posedge clk)
	begin
		if((blk_start & blk_idle) | (m_axi_arvalid & m_axi_arready))
			req_n_remaining <= # simulation_delay arlen_cmp - axi_rchn_max_burst_len;
	end
	
	// ���1������ַ(��־)
	always @(posedge clk)
	begin
		if((blk_start & blk_idle) | (m_axi_arvalid & m_axi_arready))
			ar_last <= # simulation_delay arlen_cmp <= (axi_rchn_max_burst_len - 1);
	end
	
	// ���ڴ������1����ͻ��(��־)
	always @(posedge clk)
	begin
		if(m_axi_arvalid & m_axi_arready)
			last_rd_burst_processing <= # simulation_delay ar_last;
	end
	
	// ��ͻ��������(��־)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rd_burst_processing <= 1'b0;
		else if((m_axi_arvalid & m_axi_arready) | (m_axi_rvalid & m_axi_rready & m_axi_rlast))
			// ����: ARͨ�����ֺ�Rͨ�������Ҵ��ڶ�ͻ�����1�����ݲ�����ͬʱ����!
			rd_burst_processing <= # simulation_delay m_axi_arvalid & m_axi_arready;
	end
	
	/** ��/д����������buffer **/
	wire on_new_rd_burst_start; // �����µĶ�ͻ��(ָʾ)
	wire on_fetch_rd_burst_data; // ȡ�߶�ͻ������(ָʾ)
	reg[clogb2(rw_req_dsc_buffer_depth/axi_rchn_max_burst_len):0] rd_burst_launched; // �������Ķ�ͻ������(��ַͨ�����ֵ���δȡ�߶�����)
	reg rw_req_dsc_buf_full_n; // ��/д����������buffer����־
	wire m_axis_dsc_last; // ��־��ͻ�����1������
	
	assign rw_req_dsc_buf_allow_ar_trans = rw_req_dsc_buf_full_n;
	
	assign on_new_rd_burst_start = m_axi_arvalid & m_axi_arready;
	assign on_fetch_rd_burst_data = m_axis_dsc_valid & m_axis_dsc_ready & m_axis_dsc_last;
	
	// �������Ķ�ͻ������
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rd_burst_launched <= 0;
		else if(on_new_rd_burst_start ^ on_fetch_rd_burst_data)
			rd_burst_launched <= # simulation_delay on_new_rd_burst_start ? (rd_burst_launched + 1):(rd_burst_launched - 1);
	end
	
	// ��/д����������buffer����־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rw_req_dsc_buf_full_n <= 1'b1;
		else if(on_new_rd_burst_start ^ on_fetch_rd_burst_data)
			// on_new_rd_burst_start ? (rd_burst_launched != (rw_req_dsc_buffer_depth/axi_rchn_max_burst_len-1)):1'b1
			rw_req_dsc_buf_full_n <= # simulation_delay 
				(~on_new_rd_burst_start) | (rd_burst_launched != (rw_req_dsc_buffer_depth/axi_rchn_max_burst_len-1));
	end
	
	// ��/д���������ӻ���AXIS����fifo
	axis_data_fifo #(
		.is_async("false"),
		.en_packet_mode("false"),
		.ram_type("bram"),
		.fifo_depth(rw_req_dsc_buffer_depth),
		.data_width(64),
		.user_width(1),
		.simulation_delay(simulation_delay)
	)rw_req_dsc_buffer(
		.s_axis_aclk(clk),
		.s_axis_aresetn(rst_n),
		.m_axis_aclk(clk),
		.m_axis_aresetn(rst_n),
		
		.s_axis_data(m_axi_rdata),
		.s_axis_keep(8'bxxxx_xxxx),
		.s_axis_strb(8'bxxxx_xxxx),
		.s_axis_user(1'bx),
		.s_axis_last(m_axi_rlast),
		.s_axis_valid(m_axi_rvalid),
		.s_axis_ready(m_axi_rready),
		
		.m_axis_data(m_axis_dsc_data),
		.m_axis_keep(),
		.m_axis_strb(),
		.m_axis_user(),
		.m_axis_last(m_axis_dsc_last),
		.m_axis_valid(m_axis_dsc_valid),
		.m_axis_ready(m_axis_dsc_ready)
	);
	
endmodule
