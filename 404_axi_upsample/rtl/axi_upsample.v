`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXI-�ϲ���������

����:
ʵ���������е��ϲ�������(upsample)
������/clk
1x1��2x2�ϲ���

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
AXI-Lite SLAVE
AXI MASTER

����: �¼�ҫ
����: 2024/11/28
********************************************************************/


module axi_upsample #(
	// DMA����
	parameter integer axi_max_burst_len = 32, // AXI�������ͻ������(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer axi_addr_outstanding = 4, // AXI��ַ�������(1~16)
	parameter integer max_rd_btt = 4 * 512, // ���Ķ��������ֽ���(256 | 512 | 1024 | ...)
	parameter integer axi_rdata_buffer_depth = 512, // AXI������buffer���(0 -> ������ | 512 | 1024 | ...)
	parameter integer max_wt_btt = 4 * 512, // ����д�������ֽ���(256 | 512 | 1024 | ...)
	parameter integer axi_wdata_buffer_depth = 512, // AXIд����buffer���(512 | 1024 | ...)
	// �ϲ��������������
    parameter integer feature_n_per_clk = 1, // ÿ��clk���������������(1 | 2 | 4 | 8 | 16 | ...)
	parameter integer feature_data_width = 16, // ������λ��(�����ܱ�8����, ��>0)
	parameter integer max_feature_w = 128, // ������������ͼ���
	parameter integer max_feature_h = 128, // ������������ͼ�߶�
	parameter integer max_feature_chn_n = 512, // ������������ͼͨ����
	// �����������
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
	input wire clk,
	input wire resetn,
	
	// �Ĵ������ýӿ�(AXI-Lite�ӻ�)
    // ����ַͨ��
    input wire[31:0] s_axi_lite_araddr,
	input wire[2:0] s_axi_lite_arprot, // ignored
    input wire s_axi_lite_arvalid,
    output wire s_axi_lite_arready,
    // д��ַͨ��
    input wire[31:0] s_axi_lite_awaddr,
	input wire[2:0] s_axi_lite_awprot, // ignored
    input wire s_axi_lite_awvalid,
    output wire s_axi_lite_awready,
    // д��Ӧͨ��
    output wire[1:0] s_axi_lite_bresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_bvalid,
    input wire s_axi_lite_bready,
    // ������ͨ��
    output wire[31:0] s_axi_lite_rdata,
    output wire[1:0] s_axi_lite_rresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_rvalid,
    input wire s_axi_lite_rready,
    // д����ͨ��
    input wire[31:0] s_axi_lite_wdata,
	input wire[3:0] s_axi_lite_wstrb,
    input wire s_axi_lite_wvalid,
    output wire s_axi_lite_wready,
	
	// AXI����
	// AR
    output wire[31:0] m_axi_araddr,
    output wire[1:0] m_axi_arburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_arlen,
    output wire[2:0] m_axi_arsize, // const -> 3'b011
    output wire[3:0] m_axis_arcache, // const -> 4'b0011
    output wire m_axi_arvalid,
    input wire m_axi_arready,
	// AW
    output wire[31:0] m_axi_awaddr,
    output wire[1:0] m_axi_awburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_awlen,
    output wire[2:0] m_axi_awsize, // const -> 3'b011
    output wire[3:0] m_axis_awcache, // const -> 4'b0011
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    // B
    input wire[1:0] m_axi_bresp, // ignored
    input wire m_axi_bvalid,
    output wire m_axi_bready, // const -> 1'b1
    // R
    input wire[63:0] m_axi_rdata,
    input wire[1:0] m_axi_rresp, // ignored
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output wire m_axi_rready,
    // W
    output wire[63:0] m_axi_wdata,
    output wire[7:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready,
	
	// �ж��ź�
	output wire itr
);
    
	/** �Ĵ������ýӿ� **/
	// DMA��ͨ������
	wire dma_mm2s_start;
	wire dma_mm2s_idle;
	wire dma_mm2s_done;
	// DMAдͨ������
	wire dma_s2mm_start;
	wire dma_s2mm_idle;
	wire dma_s2mm_done;
	// ����ʱ����
	wire[31:0] in_ft_map_buf_baseaddr; // ��������ͼ����������ַ
	wire[31:0] in_ft_map_buf_len; // ��������ͼ���������� - 1(���ֽڼ�)
	wire[31:0] out_ft_map_buf_baseaddr; // �������ͼ����������ַ
	wire[31:0] out_ft_map_buf_len; // �������ͼ���������� - 1(���ֽڼ�)
	wire[15:0] feature_map_chn_n; // ����ͼͨ���� - 1
	wire[15:0] feature_map_w; // ����ͼ��� - 1
	wire[15:0] feature_map_h; // ����ͼ�߶� - 1
	
	reg_if_for_upsample #(
		.simulation_delay(simulation_delay)
	)reg_if_for_upsample_u(
		.clk(clk),
		.rst_n(resetn),
		
		.s_axi_lite_araddr(s_axi_lite_araddr),
		.s_axi_lite_arprot(s_axi_lite_arprot),
		.s_axi_lite_arvalid(s_axi_lite_arvalid),
		.s_axi_lite_arready(s_axi_lite_arready),
		.s_axi_lite_awaddr(s_axi_lite_awaddr),
		.s_axi_lite_awprot(s_axi_lite_awprot),
		.s_axi_lite_awvalid(s_axi_lite_awvalid),
		.s_axi_lite_awready(s_axi_lite_awready),
		.s_axi_lite_bresp(s_axi_lite_bresp),
		.s_axi_lite_bvalid(s_axi_lite_bvalid),
		.s_axi_lite_bready(s_axi_lite_bready),
		.s_axi_lite_rdata(s_axi_lite_rdata),
		.s_axi_lite_rresp(s_axi_lite_rresp),
		.s_axi_lite_rvalid(s_axi_lite_rvalid),
		.s_axi_lite_rready(s_axi_lite_rready),
		.s_axi_lite_wdata(s_axi_lite_wdata),
		.s_axi_lite_wstrb(s_axi_lite_wstrb),
		.s_axi_lite_wvalid(s_axi_lite_wvalid),
		.s_axi_lite_wready(s_axi_lite_wready),
		
		.dma_mm2s_start(dma_mm2s_start),
		.dma_mm2s_idle(dma_mm2s_idle),
		.dma_mm2s_done(dma_mm2s_done),
		
		.dma_s2mm_start(dma_s2mm_start),
		.dma_s2mm_idle(dma_s2mm_idle),
		.dma_s2mm_done(dma_s2mm_done),
		
		.in_ft_map_buf_baseaddr(in_ft_map_buf_baseaddr),
		.in_ft_map_buf_len(in_ft_map_buf_len),
		.out_ft_map_buf_baseaddr(out_ft_map_buf_baseaddr),
		.out_ft_map_buf_len(out_ft_map_buf_len),
		.feature_map_chn_n(feature_map_chn_n),
		.feature_map_w(feature_map_w),
		.feature_map_h(feature_map_h),
		
		.itr(itr)
	);
	
	/** ����/�������ͼDMA **/
	// ����������ͼ������
	wire[63:0] s_axis_out_ft_map_data;
	wire[7:0] s_axis_out_ft_map_keep;
	wire s_axis_out_ft_map_last;
	wire s_axis_out_ft_map_valid;
	wire s_axis_out_ft_map_ready;
	// �������������ͼ������
	wire[63:0] m_axis_in_ft_map_data;
	wire[7:0] m_axis_in_ft_map_keep;
	wire m_axis_in_ft_map_last;
	wire m_axis_in_ft_map_valid;
	wire m_axis_in_ft_map_ready;
	
	axi_dma_for_upsample #(
		.axi_max_burst_len(axi_max_burst_len),
		.axi_addr_outstanding(axi_addr_outstanding),
		.max_rd_btt(max_rd_btt),
		.axi_rdata_buffer_depth(axi_rdata_buffer_depth),
		.max_wt_btt(max_wt_btt),
		.axi_wdata_buffer_depth(axi_wdata_buffer_depth),
		.simulation_delay(simulation_delay)
	)axi_dma_for_upsample_u(
		.clk(clk),
		.rst_n(resetn),
		
		.in_ft_map_buf_baseaddr(in_ft_map_buf_baseaddr),
		.in_ft_map_buf_len(in_ft_map_buf_len),
		.out_ft_map_buf_baseaddr(out_ft_map_buf_baseaddr),
		.out_ft_map_buf_len(out_ft_map_buf_len),
		
		.mm2s_start(dma_mm2s_start),
		.mm2s_idle(dma_mm2s_idle),
		.mm2s_done(dma_mm2s_done),
		
		.s2mm_start(dma_s2mm_start),
		.s2mm_idle(dma_s2mm_idle),
		.s2mm_done(dma_s2mm_done),
		
		.s_axis_out_ft_map_data(s_axis_out_ft_map_data),
		.s_axis_out_ft_map_keep(s_axis_out_ft_map_keep),
		.s_axis_out_ft_map_last(s_axis_out_ft_map_last),
		.s_axis_out_ft_map_valid(s_axis_out_ft_map_valid),
		.s_axis_out_ft_map_ready(s_axis_out_ft_map_ready),
		
		.m_axis_in_ft_map_data(m_axis_in_ft_map_data),
		.m_axis_in_ft_map_keep(m_axis_in_ft_map_keep),
		.m_axis_in_ft_map_last(m_axis_in_ft_map_last),
		.m_axis_in_ft_map_valid(m_axis_in_ft_map_valid),
		.m_axis_in_ft_map_ready(m_axis_in_ft_map_ready),
		
		.m_axi_araddr(m_axi_araddr),
		.m_axi_arburst(m_axi_arburst),
		.m_axi_arlen(m_axi_arlen),
		.m_axi_arsize(m_axi_arsize),
		.m_axis_arcache(m_axis_arcache),
		.m_axi_arvalid(m_axi_arvalid),
		.m_axi_arready(m_axi_arready),
		.m_axi_awaddr(m_axi_awaddr),
		.m_axi_awburst(m_axi_awburst),
		.m_axi_awlen(m_axi_awlen),
		.m_axi_awsize(m_axi_awsize),
		.m_axis_awcache(m_axis_awcache),
		.m_axi_awvalid(m_axi_awvalid),
		.m_axi_awready(m_axi_awready),
		.m_axi_bresp(m_axi_bresp),
		.m_axi_bvalid(m_axi_bvalid),
		.m_axi_bready(m_axi_bready),
		.m_axi_rdata(m_axi_rdata),
		.m_axi_rresp(m_axi_rresp),
		.m_axi_rlast(m_axi_rlast),
		.m_axi_rvalid(m_axi_rvalid),
		.m_axi_rready(m_axi_rready),
		.m_axi_wdata(m_axi_wdata),
		.m_axi_wstrb(m_axi_wstrb),
		.m_axi_wlast(m_axi_wlast),
		.m_axi_wvalid(m_axi_wvalid),
		.m_axi_wready(m_axi_wready)
	);
	
	/** �ϲ�������Ԫ **/
	// ����������ͼ����������
	wire[feature_n_per_clk*feature_data_width-1:0] s_axis_upsample_data;
	wire s_axis_upsample_valid;
	wire s_axis_upsample_ready;
	// ���������ͼ���������
	wire[feature_n_per_clk*feature_data_width*2-1:0] m_axis_upsample_data;
	wire m_axis_upsample_last; // ����ͼ���1��
	wire m_axis_upsample_valid;
	wire m_axis_upsample_ready;
	
	upsample #(
		.feature_n_per_clk(feature_n_per_clk),
		.feature_data_width(feature_data_width),
		.max_feature_w(max_feature_w),
		.max_feature_h(max_feature_h),
		.max_feature_chn_n(max_feature_chn_n),
		.simulation_delay(simulation_delay)
	)upsample_u(
		.clk(clk),
		.rst_n(resetn),
		
		.feature_w(feature_map_w),
		.feature_h(feature_map_h),
		.feature_chn_n(feature_map_chn_n),
		
		.s_axis_data(s_axis_upsample_data),
		.s_axis_valid(s_axis_upsample_valid),
		.s_axis_ready(s_axis_upsample_ready),
		
		.m_axis_data(m_axis_upsample_data),
		.m_axis_user(),
		.m_axis_last(m_axis_upsample_last),
		.m_axis_valid(m_axis_upsample_valid),
		.m_axis_ready(m_axis_upsample_ready)
	);
	
	/** λ��任(64 -> feature_n_per_clk*feature_data_width) **/
	// λ��任����
	wire[63:0] s_axis_dw_cvt_0_data;
	wire[7:0] s_axis_dw_cvt_0_keep;
	wire s_axis_dw_cvt_0_last;
	wire s_axis_dw_cvt_0_valid;
	wire s_axis_dw_cvt_0_ready;
	// λ��任���
	wire[feature_n_per_clk*feature_data_width-1:0] m_axis_dw_cvt_0_data;
	wire[feature_n_per_clk*feature_data_width/8-1:0] m_axis_dw_cvt_0_keep;
	wire m_axis_dw_cvt_0_last; // ָʾ����ͼ����
	wire m_axis_dw_cvt_0_valid;
	wire m_axis_dw_cvt_0_ready;
	
	assign s_axis_dw_cvt_0_data = m_axis_in_ft_map_data;
	assign s_axis_dw_cvt_0_keep = m_axis_in_ft_map_keep;
	assign s_axis_dw_cvt_0_last = m_axis_in_ft_map_last;
	assign s_axis_dw_cvt_0_valid = m_axis_in_ft_map_valid;
	assign m_axis_in_ft_map_ready = s_axis_dw_cvt_0_ready;
	
	assign s_axis_upsample_data = m_axis_dw_cvt_0_data;
	assign s_axis_upsample_valid = m_axis_dw_cvt_0_valid;
	assign m_axis_dw_cvt_0_ready = s_axis_upsample_ready;
	
	axis_dw_cvt #(
		.slave_data_width(64),
		.master_data_width(feature_n_per_clk*feature_data_width),
		.slave_user_width_foreach_byte(1),
		.en_keep("true"),
		.en_last("true"),
		.en_out_isolation("false"),
		.simulation_delay(simulation_delay)
	)axis_dw_cvt_u0(
		.clk(clk),
		.rst_n(resetn),
		
		.s_axis_data(s_axis_dw_cvt_0_data),
		.s_axis_keep(s_axis_dw_cvt_0_keep),
		.s_axis_last(s_axis_dw_cvt_0_last),
		.s_axis_valid(s_axis_dw_cvt_0_valid),
		.s_axis_ready(s_axis_dw_cvt_0_ready),
		
		.m_axis_data(m_axis_dw_cvt_0_data),
		.m_axis_keep(m_axis_dw_cvt_0_keep),
		.m_axis_last(m_axis_dw_cvt_0_last),
		.m_axis_valid(m_axis_dw_cvt_0_valid),
		.m_axis_ready(m_axis_dw_cvt_0_ready)
	);
	
	/** λ��任(feature_n_per_clk*feature_data_width*2 -> 64) **/
	// λ��任����
	wire[feature_n_per_clk*feature_data_width*2-1:0] s_axis_dw_cvt_1_data;
	wire s_axis_dw_cvt_1_last;
	wire s_axis_dw_cvt_1_valid;
	wire s_axis_dw_cvt_1_ready;
	// λ��任���
	wire[63:0] m_axis_dw_cvt_1_data;
	wire[7:0] m_axis_dw_cvt_1_keep;
	wire m_axis_dw_cvt_1_last; // ָʾ����ͼ����
	wire m_axis_dw_cvt_1_valid;
	wire m_axis_dw_cvt_1_ready;
	
	assign s_axis_dw_cvt_1_data = m_axis_upsample_data;
	assign s_axis_dw_cvt_1_last = m_axis_upsample_last;
	assign s_axis_dw_cvt_1_valid = m_axis_upsample_valid;
	assign m_axis_upsample_ready = s_axis_dw_cvt_1_ready;
	
	assign s_axis_out_ft_map_data = m_axis_dw_cvt_1_data;
	assign s_axis_out_ft_map_keep = m_axis_dw_cvt_1_keep;
	assign s_axis_out_ft_map_last = m_axis_dw_cvt_1_last;
	assign s_axis_out_ft_map_valid = m_axis_dw_cvt_1_valid;
	assign m_axis_dw_cvt_1_ready = s_axis_out_ft_map_ready;
	
	axis_dw_cvt #(
		.slave_data_width(feature_n_per_clk*feature_data_width*2),
		.master_data_width(64),
		.slave_user_width_foreach_byte(1),
		.en_keep("true"),
		.en_last("true"),
		.en_out_isolation("false"),
		.simulation_delay(simulation_delay)
	)axis_dw_cvt_u1(
		.clk(clk),
		.rst_n(resetn),
		
		.s_axis_data(s_axis_dw_cvt_1_data),
		.s_axis_keep({(feature_n_per_clk*feature_data_width*2/8){1'b1}}),
		.s_axis_last(s_axis_dw_cvt_1_last),
		.s_axis_valid(s_axis_dw_cvt_1_valid),
		.s_axis_ready(s_axis_dw_cvt_1_ready),
		
		.m_axis_data(m_axis_dw_cvt_1_data),
		.m_axis_keep(m_axis_dw_cvt_1_keep),
		.m_axis_last(m_axis_dw_cvt_1_last),
		.m_axis_valid(m_axis_dw_cvt_1_valid),
		.m_axis_ready(m_axis_dw_cvt_1_ready)
	);
    
endmodule
