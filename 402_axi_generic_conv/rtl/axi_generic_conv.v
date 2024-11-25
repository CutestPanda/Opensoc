`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXIͨ�þ�����㵥Ԫ

����:
֧�ֶ�˶�ͨ��1x1/3x3���
֧�ֵ����������Ϊ3x3ʱ����/��/��/�����1����
32λ��ַ64λ���ݵ�AXI����

����ͼ�������洢˳�� ->
	{
		[x1y1, ͨ��1] [x2y1, ͨ��1] .... [xny1, ͨ��1]
							:
							:
		[x1yn, ͨ��1] [x2yn, ͨ��1] .... [xnyn, ͨ��1]
	}
	... ...
	{
		[x1y1, ͨ��n] [x2y1, ͨ��n] .... [xny1, ͨ��n]
							:
							:
		[x1yn, ͨ��n] [x2yn, ͨ��n] .... [xnyn, ͨ��n]
	}

����˻������洢˳�� ->
	[��1ͨ��1] [��1ͨ��2] .... [��1ͨ��n]
	                :
					:
	[��mͨ��1] [��mͨ��2] .... [��mͨ��n]

���Բ����������洢˳�� ->
	[����1, ����1] [����2, ����2] ... [����m, ����m]

ע�⣺
��������ͼͨ����Ӧ�����ھ����ͨ����
��������ͼ�������(in_feature_map_buffer_n)����>=ͨ��������(prl_chn_n)
����˲����������(kernal_pars_buffer_n)����>=����˲�����(prl_kernal_n)

Э��:
AXI-Lite SLAVE
AXI MASTER

����: �¼�ҫ
����: 2024/11/10
********************************************************************/


module axi_generic_conv #(
	// ������������DMA����
	parameter integer max_rd_req_n = 1024 * 1024, // ���Ķ��������
	parameter integer axi_rd_req_dsc_rchn_max_burst_len = 8, // AXI��ͨ�����ͻ������(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer rd_req_dsc_buffer_depth = 512, // ������������buffer���(256 | 512 | 1024 | ...)
	// д����������DMA����
	parameter integer max_wt_req_n = 1024 * 1024, // ����д�������
	parameter integer axi_wt_req_dsc_rchn_max_burst_len = 8, // AXI��ͨ�����ͻ������(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer wt_req_dsc_buffer_depth = 512, // д����������buffer���(256 | 512 | 1024 | ...)
	// ����ͼ���������/����ͼ���DMA�Ƿ�ʹ��4KB�߽籣��
	parameter axi_conv_rw_chn_en_4KB_boundary_protection = "true", 
	// ����ͼ���������DMA����
	parameter integer conv_max_rd_btt = 65536, // ���Ķ������ֽ���(256 | 512 | 1024 | ...)
	parameter integer axi_conv_rchn_max_burst_len = 32, // AXI��ͨ�����ͻ������(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer axi_conv_raddr_outstanding = 4, // AXI����ַ�������(1 | 2 | 4)
	parameter integer axi_conv_rdata_buffer_depth = 512, // AXI������buffer���(0 -> ������ | 512 | 1024 | ...)
	// ����ͼ���DMA����
	parameter integer conv_max_wt_btt = 65536, // ����д�����ֽ���(256 | 512 | 1024 | ...)
	parameter integer axi_conv_wchn_max_burst_len = 32, // AXIдͨ�����ͻ������(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer axi_conv_waddr_outstanding = 4, // AXIд��ַ�������(1 | 2 | 4)
	parameter integer axi_conv_wdata_buffer_depth = 512, // AXIд����buffer���(512 | 1024 | ...)
	// ����ͼ�Ͳ�������������
	parameter integer in_feature_map_buffer_n = 8, // ��������ͼ�������
	parameter integer kernal_pars_buffer_n = 8, // ����˲����������
	parameter integer out_buffer_n = 8, // ��ͨ���������������
	// �����������
	parameter integer in_ft_quaz_acc = 10, // ��������������(�����ڷ�Χ[1, feature_pars_data_width-1]��)
	parameter integer conv_res_ext_int_width = 4, // ���������⿼�ǵ�����λ��(����<=(feature_pars_data_width-in_ft_quaz_acc))
	parameter integer conv_res_ext_frac_width = 4, // ���������⿼�ǵ�С��λ��(����<=in_ft_quaz_acc)
	// ���Գ˼��뼤���������
	parameter integer ab_quaz_acc = 12, // a/bϵ����������(�����ڷ�Χ[1, feature_pars_data_width-1]��)
	parameter integer c_quaz_acc = 14, // cϵ����������(�����ڷ�Χ[1, feature_pars_data_width-1]��)
	// ��ͨ�������������
	parameter integer feature_pars_data_width = 16, // ������Ͳ���λ��(8 | 16 | 32 | 64)
	parameter integer max_feature_map_w = 512, // ������������ͼ���
	parameter integer max_feature_map_h = 512, // ������������ͼ�߶�
	parameter integer max_feature_map_chn_n = 512, // ������������ͼͨ����
	parameter integer max_kernal_n = 512, // ���ľ���˸���
	parameter integer prl_chn_n = 4, // ͨ��������(1 | 2 | 4 | 8 | 16)
	parameter integer prl_kernal_n = 4, // ����˲�����(1 | 2 | 4 | 8 | 16)
	// �����������
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
	input wire clk,
	input wire rst_n,
	
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
	
	// ����ͼ���������/����ͼ���(AXI����)
	// AR
    output wire[31:0] m_axi_conv_araddr,
    output wire[1:0] m_axi_conv_arburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_conv_arlen,
    output wire[2:0] m_axi_conv_arsize, // const -> 3'b011
    output wire m_axi_conv_arvalid,
    input wire m_axi_conv_arready,
    // R
    input wire[63:0] m_axi_conv_rdata,
    input wire[1:0] m_axi_conv_rresp, // ignored
    input wire m_axi_conv_rlast,
    input wire m_axi_conv_rvalid,
    output wire m_axi_conv_rready,
    // AW
    output wire[31:0] m_axi_conv_awaddr,
    output wire[1:0] m_axi_conv_awburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_conv_awlen,
    output wire[2:0] m_axi_conv_awsize, // const -> 3'b011
    output wire m_axi_conv_awvalid,
    input wire m_axi_conv_awready,
    // B
    input wire[1:0] m_axi_conv_bresp, // ignored
    input wire m_axi_conv_bvalid,
    output wire m_axi_conv_bready, // const -> 1'b1
    // W
    output wire[63:0] m_axi_conv_wdata,
    output wire[7:0] m_axi_conv_wstrb,
    output wire m_axi_conv_wlast,
    output wire m_axi_conv_wvalid,
    input wire m_axi_conv_wready,
	
	// ��/д��������������(AXI����, READ ONLY)
	// AR
    output wire[31:0] m_axi_rw_req_dsc_araddr,
    output wire[1:0] m_axi_rw_req_dsc_arburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_rw_req_dsc_arlen,
    output wire[2:0] m_axi_rw_req_dsc_arsize, // const -> 3'b011
    output wire m_axi_rw_req_dsc_arvalid,
    input wire m_axi_rw_req_dsc_arready,
    // R
    input wire[63:0] m_axi_rw_req_dsc_rdata,
    input wire[1:0] m_axi_rw_req_dsc_rresp, // ignored
    input wire m_axi_rw_req_dsc_rlast,
    input wire m_axi_rw_req_dsc_rvalid,
    output wire m_axi_rw_req_dsc_rready,
    // AW
    output wire[31:0] m_axi_rw_req_dsc_awaddr, // not care
    output wire[1:0] m_axi_rw_req_dsc_awburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_rw_req_dsc_awlen, // not care
    output wire[2:0] m_axi_rw_req_dsc_awsize, // const -> 3'b011
    output wire m_axi_rw_req_dsc_awvalid, // const -> 1'b0
    input wire m_axi_rw_req_dsc_awready, // ignored
    // B
    input wire[1:0] m_axi_rw_req_dsc_bresp, // ignored
    input wire m_axi_rw_req_dsc_bvalid, // ignored
    output wire m_axi_rw_req_dsc_bready, // const -> 1'b1
    // W
    output wire[63:0] m_axi_rw_req_dsc_wdata, // not care
    output wire[7:0] m_axi_rw_req_dsc_wstrb, // not care
    output wire m_axi_rw_req_dsc_wlast, // not care
    output wire m_axi_rw_req_dsc_wvalid, // const -> 1'b0
    input wire m_axi_rw_req_dsc_wready, // ignored
	
	// �ж��ź�
	output wire itr
);
    
	/** �Ĵ������ýӿ� **/
	// �鼶����
	// ������������DMA
	wire rd_req_dsc_dma_blk_start;
	wire rd_req_dsc_dma_blk_idle;
	// д����������DMA
	wire wt_req_dsc_dma_blk_start;
	wire wt_req_dsc_dma_blk_idle;
	// ʹ��
	wire en_conv_cal; // �Ƿ�ʹ�ܾ������
	// ��λ
	wire rst_linear_pars_buf; // ��λ���Բ���������
	wire rst_cal_path_kernal_buf; // ��λ����ͨ·�ϵľ���˲�������
	// �ж�
	wire[31:0] wt_req_itr_th; // д����������ж���ֵ
	wire[2:0] itr_req; // �ж�����({д����������ж�����, 
	                   //     д����������DMA����������ж�����, ������������DMA����������ж�����})
	wire en_wt_req_fns_itr; // �Ƿ�ʹ��д����������ж�
	// ����ɵ�д�������
	wire[3:0] to_set_wt_req_fns_n;
	wire[31:0] wt_req_fns_n_set_v;
	wire[31:0] wt_req_fns_n_cur_v;
	// ����ʱ����
	wire[feature_pars_data_width-1:0] act_rate_c; // Relu����ϵ��c
	wire[31:0] rd_req_buf_baseaddr; // �����󻺴����׵�ַ
	wire[31:0] rd_req_n; // ��������� - 1
	wire[31:0] wt_req_buf_baseaddr; // д���󻺴����׵�ַ
	wire[31:0] wt_req_n; // д������� - 1
	wire kernal_type; // ���������(1'b0 -> 1x1, 1'b1 -> 3x3)
	wire[15:0] feature_map_w; // ��������ͼ��� - 1
	wire[15:0] feature_map_h; // ��������ͼ�߶� - 1
	wire[15:0] feature_map_chn_n; // ��������ͼͨ���� - 1
	wire[15:0] kernal_n; // ����˸��� - 1
	wire[3:0] padding_en; // �������ʹ��(�������������Ϊ3x3ʱ����, {��, ��, ��, ��})
	
	reg_if_for_generic_conv #(
		.simulation_delay(simulation_delay)
	)reg_if_for_generic_conv_u(
		.clk(clk),
		.rst_n(rst_n),
		
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
		
		.rd_req_dsc_dma_blk_start(rd_req_dsc_dma_blk_start),
		.rd_req_dsc_dma_blk_idle(rd_req_dsc_dma_blk_idle),
		
		.wt_req_dsc_dma_blk_start(wt_req_dsc_dma_blk_start),
		.wt_req_dsc_dma_blk_idle(wt_req_dsc_dma_blk_idle),
		
		.en_conv_cal(en_conv_cal),
		
		.rst_linear_pars_buf(rst_linear_pars_buf),
		.rst_cal_path_kernal_buf(rst_cal_path_kernal_buf),
		
		.wt_req_itr_th(wt_req_itr_th),
		.itr_req(itr_req),
		.en_wt_req_fns_itr(en_wt_req_fns_itr),
		.itr(itr),
		
		.to_set_wt_req_fns_n(to_set_wt_req_fns_n),
		.wt_req_fns_n_set_v(wt_req_fns_n_set_v),
		.wt_req_fns_n_cur_v(wt_req_fns_n_cur_v),
		
		.act_rate_c(act_rate_c), // λ��64��λ��feature_pars_data_width����, ȡ��λ!
		.rd_req_buf_baseaddr(rd_req_buf_baseaddr),
		.rd_req_n(rd_req_n),
		.wt_req_buf_baseaddr(wt_req_buf_baseaddr),
		.wt_req_n(wt_req_n),
		.kernal_type(kernal_type),
		.feature_map_w(feature_map_w),
		.feature_map_h(feature_map_h),
		.feature_map_chn_n(feature_map_chn_n),
		.kernal_n(kernal_n),
		.padding_en(padding_en)
	);
	
	/** �жϿ��� **/
	// ������������DMA���������(ָʾ)
	wire rd_req_dsc_dma_blk_done;
	// д����������DMA���������(ָʾ)
	wire wt_req_dsc_dma_blk_done;
	// ���д����(ָʾ)
	wire wt_req_fns;
	
	itr_ctrl_for_generic_conv #(
		.simulation_delay(simulation_delay)
	)itr_ctrl_for_generic_conv_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.rd_req_dsc_dma_blk_done(rd_req_dsc_dma_blk_done),
		.wt_req_dsc_dma_blk_done(wt_req_dsc_dma_blk_done),
		.wt_req_fns(wt_req_fns),
		
		.to_set_wt_req_fns_n(to_set_wt_req_fns_n),
		.wt_req_fns_n_set_v(wt_req_fns_n_set_v),
		.wt_req_fns_n_cur_v(wt_req_fns_n_cur_v),
		
		.en_wt_req_fns_itr(en_wt_req_fns_itr),
		
		.wt_req_itr_th(wt_req_itr_th),
		
		.itr_req(itr_req)
	);
	
	/** ������������DMA **/
	// ������������(AXIS����)
	wire[63:0] m_axis_rd_req_dsc_data;
	wire m_axis_rd_req_dsc_valid;
	wire m_axis_rd_req_dsc_ready;
	// AXI����(��ͨ��)
	// AR
    wire[31:0] m_axi_rd_req_dsc_araddr;
    wire[1:0] m_axi_rd_req_dsc_arburst; // const -> 2'b01(INCR)
    wire[7:0] m_axi_rd_req_dsc_arlen;
    wire[2:0] m_axi_rd_req_dsc_arsize; // const -> 3'b011
    wire m_axi_rd_req_dsc_arvalid;
    wire m_axi_rd_req_dsc_arready;
    // R
    wire[63:0] m_axi_rd_req_dsc_rdata;
    wire[1:0] m_axi_rd_req_dsc_rresp; // ignored
    wire m_axi_rd_req_dsc_rlast;
    wire m_axi_rd_req_dsc_rvalid;
    wire m_axi_rd_req_dsc_rready;
	
	axi_rw_req_dsc_dma #(
		.max_req_n(max_rd_req_n),
		.axi_rchn_max_burst_len(axi_rd_req_dsc_rchn_max_burst_len),
		.rw_req_dsc_buffer_depth(rd_req_dsc_buffer_depth),
		.simulation_delay(simulation_delay)
	)axi_rd_req_dsc_dma_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.req_buf_baseaddr(rd_req_buf_baseaddr),
		.req_n(rd_req_n),
		
		.blk_start(rd_req_dsc_dma_blk_start),
		.blk_idle(rd_req_dsc_dma_blk_idle),
		.blk_done(rd_req_dsc_dma_blk_done),
		
		.m_axis_dsc_data(m_axis_rd_req_dsc_data),
		.m_axis_dsc_valid(m_axis_rd_req_dsc_valid),
		.m_axis_dsc_ready(m_axis_rd_req_dsc_ready),
		
		.m_axi_araddr(m_axi_rd_req_dsc_araddr),
		.m_axi_arburst(m_axi_rd_req_dsc_arburst),
		.m_axi_arlen(m_axi_rd_req_dsc_arlen),
		.m_axi_arsize(m_axi_rd_req_dsc_arsize),
		.m_axi_arvalid(m_axi_rd_req_dsc_arvalid),
		.m_axi_arready(m_axi_rd_req_dsc_arready),
		
		.m_axi_rdata(m_axi_rd_req_dsc_rdata),
		.m_axi_rresp(m_axi_rd_req_dsc_rresp),
		.m_axi_rlast(m_axi_rd_req_dsc_rlast),
		.m_axi_rvalid(m_axi_rd_req_dsc_rvalid),
		.m_axi_rready(m_axi_rd_req_dsc_rready)
	);
	
	/** д����������DMA **/
	// д����������(AXIS����)
	wire[63:0] m_axis_wt_req_dsc_data;
	wire m_axis_wt_req_dsc_valid;
	wire m_axis_wt_req_dsc_ready;
	// AXI����(��ͨ��)
	// AR
    wire[31:0] m_axi_wt_req_dsc_araddr;
    wire[1:0] m_axi_wt_req_dsc_arburst; // const -> 2'b01(INCR)
    wire[7:0] m_axi_wt_req_dsc_arlen;
    wire[2:0] m_axi_wt_req_dsc_arsize; // const -> 3'b011
    wire m_axi_wt_req_dsc_arvalid;
    wire m_axi_wt_req_dsc_arready;
    // R
    wire[63:0] m_axi_wt_req_dsc_rdata;
    wire[1:0] m_axi_wt_req_dsc_rresp; // ignored
    wire m_axi_wt_req_dsc_rlast;
    wire m_axi_wt_req_dsc_rvalid;
    wire m_axi_wt_req_dsc_rready;
	
	axi_rw_req_dsc_dma #(
		.max_req_n(max_wt_req_n),
		.axi_rchn_max_burst_len(axi_wt_req_dsc_rchn_max_burst_len),
		.rw_req_dsc_buffer_depth(wt_req_dsc_buffer_depth),
		.simulation_delay(simulation_delay)
	)axi_wt_req_dsc_dma_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.req_buf_baseaddr(wt_req_buf_baseaddr),
		.req_n(wt_req_n),
		
		.blk_start(wt_req_dsc_dma_blk_start),
		.blk_idle(wt_req_dsc_dma_blk_idle),
		.blk_done(wt_req_dsc_dma_blk_done),
		
		.m_axis_dsc_data(m_axis_wt_req_dsc_data),
		.m_axis_dsc_valid(m_axis_wt_req_dsc_valid),
		.m_axis_dsc_ready(m_axis_wt_req_dsc_ready),
		
		.m_axi_araddr(m_axi_wt_req_dsc_araddr),
		.m_axi_arburst(m_axi_wt_req_dsc_arburst),
		.m_axi_arlen(m_axi_wt_req_dsc_arlen),
		.m_axi_arsize(m_axi_wt_req_dsc_arsize),
		.m_axi_arvalid(m_axi_wt_req_dsc_arvalid),
		.m_axi_arready(m_axi_wt_req_dsc_arready),
		
		.m_axi_rdata(m_axi_wt_req_dsc_rdata),
		.m_axi_rresp(m_axi_wt_req_dsc_rresp),
		.m_axi_rlast(m_axi_wt_req_dsc_rlast),
		.m_axi_rvalid(m_axi_wt_req_dsc_rvalid),
		.m_axi_rready(m_axi_wt_req_dsc_rready)
	);
	
	/** AXIS�������ɷ���Ԫ **/
	// ������������(AXIS�ӻ�)
	wire[63:0] s_axis_rd_req_dsc_data;
	wire s_axis_rd_req_dsc_valid;
	wire s_axis_rd_req_dsc_ready;
	// ��������ͼ/�����/���Բ���������(AXIS����)
	wire[63:0] m_axis_rd_req_data; // {����ȡ���ֽ���(32bit), ����ַ(32bit)}
	wire m_axis_rd_req_valid;
	wire m_axis_rd_req_ready;
	// �ɷ���Ϣ��(AXIS����)
	wire[7:0] m_axis_dispatch_msg_data;
	wire m_axis_dispatch_msg_valid;
	wire m_axis_dispatch_msg_ready;
	
	assign s_axis_rd_req_dsc_data = m_axis_rd_req_dsc_data;
	assign s_axis_rd_req_dsc_valid = m_axis_rd_req_dsc_valid;
	assign m_axis_rd_req_dsc_ready = s_axis_rd_req_dsc_ready;
	
	axis_rd_req_distributor #(
		.max_rd_btt(conv_max_rd_btt),
		.simulation_delay(simulation_delay)
	)axis_rd_req_distributor_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axis_dsc_data(s_axis_rd_req_dsc_data),
		.s_axis_dsc_valid(s_axis_rd_req_dsc_valid),
		.s_axis_dsc_ready(s_axis_rd_req_dsc_ready),
		
		.m_axis_rd_req_data(m_axis_rd_req_data),
		.m_axis_rd_req_valid(m_axis_rd_req_valid),
		.m_axis_rd_req_ready(m_axis_rd_req_ready),
		
		.m_axis_dispatch_msg_data(m_axis_dispatch_msg_data),
		.m_axis_dispatch_msg_valid(m_axis_dispatch_msg_valid),
		.m_axis_dispatch_msg_ready(m_axis_dispatch_msg_ready)
	);
	
	/** ����ͼ���������DMA **/
	// ��������ͼ/�����/���Բ���������
	wire[63:0] s_axis_rd_req_data; // {����ȡ���ֽ���(32bit), ����ַ(32bit)}
	wire s_axis_rd_req_valid;
	wire s_axis_rd_req_ready;
	// ��������ͼ/�����/���Բ���������
	wire[63:0] m_axis_ft_par_data;
	wire[7:0] m_axis_ft_par_keep;
	wire m_axis_ft_par_last;
	wire m_axis_ft_par_valid;
	wire m_axis_ft_par_ready;
	
	assign s_axis_rd_req_data = m_axis_rd_req_data;
	assign s_axis_rd_req_valid = m_axis_rd_req_valid;
	assign m_axis_rd_req_ready = s_axis_rd_req_ready;
	
	axi_rchn_for_conv_in #(
		.max_rd_btt(conv_max_rd_btt),
		.axi_rchn_max_burst_len(axi_conv_rchn_max_burst_len),
		.axi_raddr_outstanding(axi_conv_raddr_outstanding),
		.axi_rdata_buffer_depth(axi_conv_rdata_buffer_depth),
		.en_4KB_boundary_protection(axi_conv_rw_chn_en_4KB_boundary_protection),
		.en_axi_ar_reg_slice("true"),
		.en_rdata_reg_slice("true"),
		.simulation_delay(simulation_delay)
	)axi_rchn_for_conv_in_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axis_rd_req_data(s_axis_rd_req_data),
		.s_axis_rd_req_valid(s_axis_rd_req_valid),
		.s_axis_rd_req_ready(s_axis_rd_req_ready),
		
		.m_axis_ft_par_data(m_axis_ft_par_data),
		.m_axis_ft_par_keep(m_axis_ft_par_keep),
		.m_axis_ft_par_last(m_axis_ft_par_last),
		.m_axis_ft_par_valid(m_axis_ft_par_valid),
		.m_axis_ft_par_ready(m_axis_ft_par_ready),
		
		.m_axi_araddr(m_axi_conv_araddr),
		.m_axi_arburst(m_axi_conv_arburst),
		.m_axi_arlen(m_axi_conv_arlen),
		.m_axi_arsize(m_axi_conv_arsize),
		.m_axi_arvalid(m_axi_conv_arvalid),
		.m_axi_arready(m_axi_conv_arready),
		
		.m_axi_rdata(m_axi_conv_rdata),
		.m_axi_rresp(m_axi_conv_rresp),
		.m_axi_rlast(m_axi_conv_rlast),
		.m_axi_rvalid(m_axi_conv_rvalid),
		.m_axi_rready(m_axi_conv_rready)
	);
	
	/** AXIS�����ɷ�·���� **/
	// DMA��������(AXIS�ӻ�)
	wire[63:0] s_axis_ft_par_dma_data;
	wire[7:0] s_axis_ft_par_dma_keep;
	wire s_axis_ft_par_dma_last;
	wire s_axis_ft_par_dma_valid;
	wire s_axis_ft_par_dma_ready;
	// �ɷ���Ϣ��(AXIS�ӻ�)
	wire[7:0] s_axis_dispatch_msg_data;
	wire s_axis_dispatch_msg_valid;
	wire s_axis_dispatch_msg_ready;
	// ��������ͼ����(AXIS����)
	wire[63:0] m_axis_ft_buf_data;
	wire m_axis_ft_buf_last; // ��ʾ����ͼ��β
	wire[1:0] m_axis_ft_buf_user; // {�����Ƿ���Ч, ��ǰ���������1�б�־}
	wire m_axis_ft_buf_valid;
	wire m_axis_ft_buf_ready;
	// ����˲�������(AXIS����)
	wire[63:0] m_axis_kernal_buf_data;
	wire[7:0] m_axis_kernal_buf_keep;
	wire m_axis_kernal_buf_last; // ��ʾ���1�����˲���
	wire m_axis_kernal_buf_user; // ��ǰ��ͨ��������Ƿ���Ч
	wire m_axis_kernal_buf_valid;
	wire m_axis_kernal_buf_ready;
	// ���Բ�������(AXIS����)
	wire[63:0] m_axis_linear_pars_data;
	wire[7:0] m_axis_linear_pars_keep;
	wire m_axis_linear_pars_last; // ��ʾ���1�����Բ���
	wire[1:0] m_axis_linear_pars_user; // {���Բ����Ƿ���Ч, ���Բ�������(1'b0 -> A, 1'b1 -> B)}
	wire m_axis_linear_pars_valid;
	wire m_axis_linear_pars_ready;
	
	assign s_axis_ft_par_dma_data = m_axis_ft_par_data;
	assign s_axis_ft_par_dma_keep = m_axis_ft_par_keep;
	assign s_axis_ft_par_dma_last = m_axis_ft_par_last;
	assign s_axis_ft_par_dma_valid = m_axis_ft_par_valid;
	assign m_axis_ft_par_ready = s_axis_ft_par_dma_ready;
	
	assign s_axis_dispatch_msg_data = m_axis_dispatch_msg_data;
	assign s_axis_dispatch_msg_valid = m_axis_dispatch_msg_valid;
	assign m_axis_dispatch_msg_ready = s_axis_dispatch_msg_ready;
	
	axis_gateway_for_conv_in axis_gateway_for_conv_in_u(
		.s_axis_dma_data(s_axis_ft_par_dma_data),
		.s_axis_dma_keep(s_axis_ft_par_dma_keep),
		.s_axis_dma_last(s_axis_ft_par_dma_last),
		.s_axis_dma_valid(s_axis_ft_par_dma_valid),
		.s_axis_dma_ready(s_axis_ft_par_dma_ready),
		
		.s_axis_dispatch_msg_data(s_axis_dispatch_msg_data),
		.s_axis_dispatch_msg_valid(s_axis_dispatch_msg_valid),
		.s_axis_dispatch_msg_ready(s_axis_dispatch_msg_ready),
		
		.m_axis_ft_buf_data(m_axis_ft_buf_data),
		.m_axis_ft_buf_last(m_axis_ft_buf_last),
		.m_axis_ft_buf_user(m_axis_ft_buf_user),
		.m_axis_ft_buf_valid(m_axis_ft_buf_valid),
		.m_axis_ft_buf_ready(m_axis_ft_buf_ready),
		
		.m_axis_kernal_buf_data(m_axis_kernal_buf_data),
		.m_axis_kernal_buf_keep(m_axis_kernal_buf_keep),
		.m_axis_kernal_buf_last(m_axis_kernal_buf_last),
		.m_axis_kernal_buf_user(m_axis_kernal_buf_user),
		.m_axis_kernal_buf_valid(m_axis_kernal_buf_valid),
		.m_axis_kernal_buf_ready(m_axis_kernal_buf_ready),
		
		.m_axis_linear_pars_data(m_axis_linear_pars_data),
		.m_axis_linear_pars_keep(m_axis_linear_pars_keep),
		.m_axis_linear_pars_last(m_axis_linear_pars_last),
		.m_axis_linear_pars_user(m_axis_linear_pars_user),
		.m_axis_linear_pars_valid(m_axis_linear_pars_valid),
		.m_axis_linear_pars_ready(m_axis_linear_pars_ready)
	);
	
	/** AXIS��������ͼ������ **/
	// ��������ͼ(AXIS�ӻ�)
	wire[63:0] s_axis_ft_buf_data;
	wire s_axis_ft_buf_last; // ��ʾ����ͼ��β
	wire[1:0] s_axis_ft_buf_user; // {�����Ƿ���Ч, ��ǰ���������1�б�־}
	wire s_axis_ft_buf_valid;
	wire s_axis_ft_buf_ready;
	// �������(AXIS����)
	// {����#(n-1)��#2, ����#(n-1)��#1, ����#(n-1)��#0, ..., ����#0��#2, ����#0��#1, ����#0��#0}
	wire[feature_pars_data_width*3*prl_chn_n-1:0] m_axis_feature_map_data;
	wire m_axis_feature_map_last; // ��ʾ����ͼ��β
	wire[prl_chn_n*3-1:0] m_axis_feature_map_user; // {�������Ƿ���Ч��־����}
	wire m_axis_feature_map_valid;
	wire m_axis_feature_map_ready;
	
	assign s_axis_ft_buf_data = m_axis_ft_buf_data;
	assign s_axis_ft_buf_last = m_axis_ft_buf_last;
	assign s_axis_ft_buf_user = m_axis_ft_buf_user;
	assign s_axis_ft_buf_valid = m_axis_ft_buf_valid;
	assign m_axis_ft_buf_ready = s_axis_ft_buf_ready;
	
	axis_in_feature_map_buffer_group #(
		.in_feature_map_buffer_n(in_feature_map_buffer_n),
		.in_feature_map_buffer_rd_prl_n(prl_chn_n),
		.feature_data_width(feature_pars_data_width),
		.max_feature_map_w(max_feature_map_w),
		.line_buffer_mem_type("bram"),
		.simulation_delay(simulation_delay)
	)axis_in_feature_map_buffer_group_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.feature_map_w(feature_map_w),
		
		.s_axis_ft_data(s_axis_ft_buf_data),
		.s_axis_ft_last(s_axis_ft_buf_last),
		.s_axis_ft_user(s_axis_ft_buf_user),
		.s_axis_ft_valid(s_axis_ft_buf_valid),
		.s_axis_ft_ready(s_axis_ft_buf_ready),
		
		.m_axis_buf_data(m_axis_feature_map_data),
		.m_axis_buf_last(m_axis_feature_map_last),
		.m_axis_buf_user(m_axis_feature_map_user),
		.m_axis_buf_valid(m_axis_feature_map_valid),
		.m_axis_buf_ready(m_axis_feature_map_ready)
	);
	
	/** AXIS����˲��������� **/
	// �������˲�����(AXIS�ӻ�)
	wire[63:0] s_axis_kernal_buf_data;
	wire[7:0] s_axis_kernal_buf_keep;
	wire s_axis_kernal_buf_last; // ��ʾ���1�����˲���
	wire s_axis_kernal_buf_user; // ��ǰ��ͨ��������Ƿ���Ч
	wire s_axis_kernal_buf_valid;
	wire s_axis_kernal_buf_ready;
	// ����˲����������(fifo���˿�)
	wire kernal_pars_buf_fifo_ren;
	wire kernal_pars_buf_fifo_empty_n;
	// ����˲�������MEM���˿�
	wire kernal_pars_buf_mem_buf_ren_s0;
	wire kernal_pars_buf_mem_buf_ren_s1;
	wire[15:0] kernal_pars_buf_mem_buf_raddr; // ÿ������ַ��Ӧ1����ͨ�������
	wire[prl_kernal_n*feature_pars_data_width*9-1:0] kernal_pars_buf_mem_buf_dout; // {��#(n-1), ..., ��#1, ��#0}
	
	assign s_axis_kernal_buf_data = m_axis_kernal_buf_data;
	assign s_axis_kernal_buf_keep = m_axis_kernal_buf_keep;
	assign s_axis_kernal_buf_last = m_axis_kernal_buf_last;
	assign s_axis_kernal_buf_user = m_axis_kernal_buf_user;
	assign s_axis_kernal_buf_valid = m_axis_kernal_buf_valid;
	assign m_axis_kernal_buf_ready = s_axis_kernal_buf_ready;
	
	axis_kernal_params_buffer #(
		.kernal_pars_buffer_n(kernal_pars_buffer_n),
		.kernal_prl_n(prl_kernal_n),
		.kernal_param_data_width(feature_pars_data_width),
		.max_feature_map_chn_n(max_feature_map_chn_n),
		.simulation_delay(simulation_delay)
	)axis_kernal_params_buffer_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.kernal_type(kernal_type),
		
		.s_axis_kernal_pars_data(s_axis_kernal_buf_data),
		.s_axis_kernal_pars_keep(s_axis_kernal_buf_keep),
		.s_axis_kernal_pars_last(s_axis_kernal_buf_last),
		.s_axis_kernal_pars_user(s_axis_kernal_buf_user),
		.s_axis_kernal_pars_valid(s_axis_kernal_buf_valid),
		.s_axis_kernal_pars_ready(s_axis_kernal_buf_ready),
		
		.kernal_pars_buf_fifo_ren(kernal_pars_buf_fifo_ren),
		.kernal_pars_buf_fifo_empty_n(kernal_pars_buf_fifo_empty_n),
		
		.kernal_pars_buf_mem_buf_ren_s0(kernal_pars_buf_mem_buf_ren_s0),
		.kernal_pars_buf_mem_buf_ren_s1(kernal_pars_buf_mem_buf_ren_s1),
		.kernal_pars_buf_mem_buf_raddr(kernal_pars_buf_mem_buf_raddr),
		.kernal_pars_buf_mem_buf_dout(kernal_pars_buf_mem_buf_dout)
	);
	
	/** AXIS���Բ��������� **/
	// ���Բ���������������ɱ�־
	wire linear_pars_buf_load_completed;
	// �������Բ�����(AXIS�ӻ�)
	wire[63:0] s_axis_linear_pars_data;
	wire[7:0] s_axis_linear_pars_keep;
	wire s_axis_linear_pars_last; // ��ʾ���1�����Բ���
	wire[1:0] s_axis_linear_pars_user; // {���Բ����Ƿ���Ч, ���Բ�������(1'b0 -> A, 1'b1 -> B)}
	wire s_axis_linear_pars_valid;
	wire s_axis_linear_pars_ready;
	// ���Բ�����ȡ(MEM��)
	wire linear_pars_buffer_ren_s0;
	wire linear_pars_buffer_ren_s1;
	wire[15:0] linear_pars_buffer_raddr;
	wire[feature_pars_data_width-1:0] linear_pars_buffer_dout_a;
	wire[feature_pars_data_width-1:0] linear_pars_buffer_dout_b;
	
	assign s_axis_linear_pars_data = m_axis_linear_pars_data;
	assign s_axis_linear_pars_keep = m_axis_linear_pars_keep;
	assign s_axis_linear_pars_last = m_axis_linear_pars_last;
	assign s_axis_linear_pars_user = m_axis_linear_pars_user;
	assign s_axis_linear_pars_valid = m_axis_linear_pars_valid;
	assign m_axis_linear_pars_ready = s_axis_linear_pars_ready;
	
	axis_linear_params_buffer #(
		.kernal_param_data_width(feature_pars_data_width),
		.max_kernal_n(max_kernal_n),
		.simulation_delay(simulation_delay)
	)axis_linear_params_buffer_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.rst_linear_pars_buf(rst_linear_pars_buf),
		.linear_pars_buf_load_completed(linear_pars_buf_load_completed),
		
		.s_axis_linear_pars_data(s_axis_linear_pars_data),
		.s_axis_linear_pars_keep(s_axis_linear_pars_keep),
		.s_axis_linear_pars_last(s_axis_linear_pars_last),
		.s_axis_linear_pars_user(s_axis_linear_pars_user),
		.s_axis_linear_pars_valid(s_axis_linear_pars_valid),
		.s_axis_linear_pars_ready(s_axis_linear_pars_ready),
		
		.linear_pars_buffer_ren_s0(linear_pars_buffer_ren_s0),
		.linear_pars_buffer_ren_s1(linear_pars_buffer_ren_s1),
		.linear_pars_buffer_raddr(linear_pars_buffer_raddr),
		.linear_pars_buffer_dout_a(linear_pars_buffer_dout_a),
		.linear_pars_buffer_dout_b(linear_pars_buffer_dout_b)
	);
	
	/** nͨ������m�˲���3x3������㵥Ԫ **/
	// �������
	wire[15:0] o_ft_map_h; // �������ͼ�߶� - 1
	// ����ͼ����(AXIS�ӻ�)
	// {����#(n-1)��#2, ����#(n-1)��#1, ����#(n-1)��#0, ..., ����#0��#2, ����#0��#1, ����#0��#0}
	wire[feature_pars_data_width*3*prl_chn_n-1:0] s_axis_feature_map_data;
	wire s_axis_feature_map_last; // ��ʾ����ͼ��β
	wire s_axis_feature_map_valid;
	wire s_axis_feature_map_ready;
	// �����ͨ���ۼ��м������(AXIS����)
	// {��#(m-1)���, ..., ��#1���, ��#0���}
	// ÿ���м�������(conv_res_ext_int_width+feature_pars_data_width+conv_res_ext_frac_width)λ��Ч
	wire[feature_pars_data_width*2*prl_kernal_n-1:0] m_axis_mid_res_data;
	wire m_axis_mid_res_last; // ��ʾ��β
	wire m_axis_mid_res_user; // ��ʾ��ǰ�����1����
	wire m_axis_mid_res_valid;
	wire m_axis_mid_res_ready;
	
	assign s_axis_feature_map_data = m_axis_feature_map_data;
	assign s_axis_feature_map_last = m_axis_feature_map_last;
	assign s_axis_feature_map_valid = m_axis_feature_map_valid;
	assign m_axis_feature_map_ready = s_axis_feature_map_ready;
	
	axis_conv_cal_3x3 #(
		.mul_add_width(feature_pars_data_width),
		.quaz_acc(in_ft_quaz_acc),
		.add_3_input_ext_int_width(conv_res_ext_int_width),
		.add_3_input_ext_frac_width(conv_res_ext_frac_width),
		.in_feature_map_buffer_rd_prl_n(prl_chn_n),
		.kernal_prl_n(prl_kernal_n),
		.max_feature_map_h(max_feature_map_h),
		.max_feature_map_chn_n(max_feature_map_chn_n),
		.max_kernal_n(max_kernal_n),
		.simulation_delay(simulation_delay)
	)axis_conv_cal_3x3_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.rst_kernal_buf(rst_cal_path_kernal_buf),
		
		.en_conv_cal(en_conv_cal),
		
		.kernal_type(kernal_type),
		.padding_en(padding_en),
		.feature_map_h(feature_map_h),
		.feature_map_chn_n(feature_map_chn_n),
		.kernal_n(kernal_n),
		
		.o_ft_map_h(o_ft_map_h),
		
		.s_axis_feature_map_data(s_axis_feature_map_data),
		.s_axis_feature_map_last(s_axis_feature_map_last),
		.s_axis_feature_map_valid(s_axis_feature_map_valid),
		.s_axis_feature_map_ready(s_axis_feature_map_ready),
		
		.kernal_pars_buf_fifo_ren(kernal_pars_buf_fifo_ren),
		.kernal_pars_buf_fifo_empty_n(kernal_pars_buf_fifo_empty_n),
		
		.kernal_pars_buf_mem_buf_ren_s0(kernal_pars_buf_mem_buf_ren_s0),
		.kernal_pars_buf_mem_buf_ren_s1(kernal_pars_buf_mem_buf_ren_s1),
		.kernal_pars_buf_mem_buf_raddr(kernal_pars_buf_mem_buf_raddr),
		.kernal_pars_buf_mem_buf_dout(kernal_pars_buf_mem_buf_dout),
		
		.m_axis_res_data(m_axis_mid_res_data),
		.m_axis_res_last(m_axis_mid_res_last),
		.m_axis_res_user(m_axis_mid_res_user),
		.m_axis_res_valid(m_axis_mid_res_valid),
		.m_axis_res_ready(m_axis_mid_res_ready)
	);
	
	/** AXIS��ͨ�������������� **/
	// �����ͨ���ۼ��м�������(AXIS�ӻ�)
	// {��#(m-1)���, ..., ��#1���, ��#0���}
	// ÿ���м�������(conv_res_ext_int_width+feature_pars_data_width+conv_res_ext_frac_width)λ��Ч
	wire[feature_pars_data_width*2*prl_kernal_n-1:0] s_axis_mid_res_data;
	wire s_axis_mid_res_last; // ��ʾ��β
	wire s_axis_mid_res_user; // ��ʾ��ǰ�����1����
	wire s_axis_mid_res_valid;
	wire s_axis_mid_res_ready;
	// �������ͼ���������(AXIS����)
	// ����ͼ���ݽ���(conv_res_ext_int_width+feature_pars_data_width+conv_res_ext_frac_width)λ��Ч
	wire[feature_pars_data_width*2-1:0] m_axis_conv_res_data;
	wire[15:0] m_axis_conv_res_user; // ��ǰ������������ڵ�ͨ����
	wire m_axis_conv_res_last; // ��ʾ��β
	wire m_axis_conv_res_valid;
	wire m_axis_conv_res_ready;
	
	assign s_axis_mid_res_data = m_axis_mid_res_data;
	assign s_axis_mid_res_last = m_axis_mid_res_last;
	assign s_axis_mid_res_user = m_axis_mid_res_user;
	assign s_axis_mid_res_valid = m_axis_mid_res_valid;
	assign m_axis_mid_res_ready = s_axis_mid_res_ready;
	
	axis_conv_out_buffer #(
		.ft_ext_width(feature_pars_data_width*2),
		.ft_vld_width(conv_res_ext_int_width+feature_pars_data_width+conv_res_ext_frac_width),
		.kernal_prl_n(prl_kernal_n),
		.out_buffer_n(out_buffer_n),
		.max_feature_map_w(max_feature_map_w),
		.max_feature_map_h(max_feature_map_h),
		.max_kernal_n(max_kernal_n),
		.simulation_delay(simulation_delay)
	)axis_conv_out_buffer_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.en_conv_cal(en_conv_cal),
		
		.kernal_type(kernal_type),
		.padding_en(padding_en[1:0]),
		.i_ft_map_w(feature_map_w),
		.o_ft_map_h(o_ft_map_h),
		.kernal_n(kernal_n),
		
		.s_axis_mid_res_data(s_axis_mid_res_data),
		.s_axis_mid_res_last(s_axis_mid_res_last),
		.s_axis_mid_res_user(s_axis_mid_res_user),
		.s_axis_mid_res_valid(s_axis_mid_res_valid),
		.s_axis_mid_res_ready(s_axis_mid_res_ready),
		
		.m_axis_ft_out_data(m_axis_conv_res_data),
		.m_axis_ft_out_user(m_axis_conv_res_user),
		.m_axis_ft_out_last(m_axis_conv_res_last),
		.m_axis_ft_out_valid(m_axis_conv_res_valid),
		.m_axis_ft_out_ready(m_axis_conv_res_ready)
	);
	
	/** AXIS���Գ˼��뼤����㵥Ԫ **/
	// ��ͨ���������������(AXIS�ӻ�)
	// ����(conv_res_ext_int_width+feature_pars_data_width+conv_res_ext_frac_width)λ��Ч
	wire[feature_pars_data_width*2-1:0] s_axis_conv_res_data;
	wire[15:0] s_axis_conv_res_user; // ��ǰ������������ڵ�ͨ����
	wire s_axis_conv_res_last; // ��ʾ��β
	wire s_axis_conv_res_valid;
	wire s_axis_conv_res_ready;
	// ���Գ˼��뼤����������(AXIS����)
	// ����(conv_res_ext_int_width+feature_pars_data_width+conv_res_ext_frac_width)λ��Ч
	wire[feature_pars_data_width*2-1:0] m_axis_linear_act_res_data;
	wire m_axis_linear_act_res_last; // ��ʾ��β
	wire m_axis_linear_act_res_valid;
	wire m_axis_linear_act_res_ready;
	
	assign s_axis_conv_res_data = m_axis_conv_res_data;
	assign s_axis_conv_res_user = m_axis_conv_res_user;
	assign s_axis_conv_res_last = m_axis_conv_res_last;
	assign s_axis_conv_res_valid = m_axis_conv_res_valid;
	assign m_axis_conv_res_ready = s_axis_conv_res_ready;
	
	axis_linear_act_cal #(
		.xyz_quaz_acc(in_ft_quaz_acc),
		.ab_quaz_acc(ab_quaz_acc),
		.c_quaz_acc(c_quaz_acc),
		.cal_width(feature_pars_data_width),
		.xyz_ext_int_width(conv_res_ext_int_width),
		.xyz_ext_frac_width(conv_res_ext_frac_width),
		.simulation_delay(simulation_delay)
	)axis_linear_act_cal_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.act_rate_c(act_rate_c),
		
		.s_axis_conv_res_data(s_axis_conv_res_data),
		.s_axis_conv_res_user(s_axis_conv_res_user),
		.s_axis_conv_res_last(s_axis_conv_res_last),
		.s_axis_conv_res_valid(s_axis_conv_res_valid),
		.s_axis_conv_res_ready(s_axis_conv_res_ready),
		
		.m_axis_linear_act_res_data(m_axis_linear_act_res_data),
		.m_axis_linear_act_res_last(m_axis_linear_act_res_last),
		.m_axis_linear_act_res_valid(m_axis_linear_act_res_valid),
		.m_axis_linear_act_res_ready(m_axis_linear_act_res_ready),
		
		.linear_pars_buf_load_completed(linear_pars_buf_load_completed),
		
		.linear_pars_buffer_ren_s0(linear_pars_buffer_ren_s0),
		.linear_pars_buffer_ren_s1(linear_pars_buffer_ren_s1),
		.linear_pars_buffer_raddr(linear_pars_buffer_raddr),
		.linear_pars_buffer_dout_a(linear_pars_buffer_dout_a),
		.linear_pars_buffer_dout_b(linear_pars_buffer_dout_b)
	);
	
	/** ����ͼ���DMA **/
	// ������д����
	wire[63:0] s_axis_wt_req_data; // {��д����ֽ���(32bit), ����ַ(32bit)}
	wire s_axis_wt_req_valid;
	wire s_axis_wt_req_ready;
	// ��������
	wire[feature_pars_data_width-1:0] s_axis_res_data;
	wire s_axis_res_last; // ��ʾ����д�������1������
	wire s_axis_res_valid;
	wire s_axis_res_ready;
	
	assign s_axis_wt_req_data = m_axis_wt_req_dsc_data;
	assign s_axis_wt_req_valid = m_axis_wt_req_dsc_valid;
	assign m_axis_wt_req_dsc_ready = s_axis_wt_req_ready;
	
	// �����Գ˼��뼤��õ��Ľ������conv_res_ext_frac_widthλ, �õ���������Ϊin_ft_quaz_acc�����������
	assign s_axis_res_data = 
		m_axis_linear_act_res_data[conv_res_ext_frac_width+feature_pars_data_width-1:conv_res_ext_frac_width];
	assign s_axis_res_last = m_axis_linear_act_res_last;
	assign s_axis_res_valid = m_axis_linear_act_res_valid;
	assign m_axis_linear_act_res_ready = s_axis_res_ready;
	
	axi_wchn_for_conv_out #(
		.feature_data_width(feature_pars_data_width),
		.max_wt_btt(conv_max_wt_btt),
		.axi_wchn_max_burst_len(axi_conv_wchn_max_burst_len),
		.axi_waddr_outstanding(axi_conv_waddr_outstanding),
		.axi_wdata_buffer_depth(axi_conv_wdata_buffer_depth),
		.en_4KB_boundary_protection(axi_conv_rw_chn_en_4KB_boundary_protection),
		.en_axi_aw_reg_slice("true"),
		.simulation_delay(simulation_delay)
	)axi_wchn_for_conv_out_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.wt_req_fns(wt_req_fns),
		
		.s_axis_wt_req_data(s_axis_wt_req_data),
		.s_axis_wt_req_valid(s_axis_wt_req_valid),
		.s_axis_wt_req_ready(s_axis_wt_req_ready),
		
		.s_axis_res_data(s_axis_res_data),
		.s_axis_res_last(s_axis_res_last),
		.s_axis_res_valid(s_axis_res_valid),
		.s_axis_res_ready(s_axis_res_ready),
		
		.m_axi_awaddr(m_axi_conv_awaddr),
		.m_axi_awburst(m_axi_conv_awburst),
		.m_axi_awlen(m_axi_conv_awlen),
		.m_axi_awsize(m_axi_conv_awsize),
		.m_axi_awvalid(m_axi_conv_awvalid),
		.m_axi_awready(m_axi_conv_awready),
		
		.m_axi_bresp(m_axi_conv_bresp),
		.m_axi_bvalid(m_axi_conv_bvalid),
		.m_axi_bready(m_axi_conv_bready),
		
		.m_axi_wdata(m_axi_conv_wdata),
		.m_axi_wstrb(m_axi_conv_wstrb),
		.m_axi_wlast(m_axi_conv_wlast),
		.m_axi_wvalid(m_axi_conv_wvalid),
		.m_axi_wready(m_axi_conv_wready)
	);
	
	/** ��/д����������AXI��ͨ���ٲ� **/
	assign m_axi_rw_req_dsc_awaddr = 32'dx;
	assign m_axi_rw_req_dsc_awburst = 2'b01;
	assign m_axi_rw_req_dsc_awlen = 8'dx;
	assign m_axi_rw_req_dsc_awsize = 3'b011;
	assign m_axi_rw_req_dsc_awvalid = 1'b0;
	
	assign m_axi_rw_req_dsc_bready = 1'b1;
	
	assign m_axi_rw_req_dsc_wdata = 64'dx;
	assign m_axi_rw_req_dsc_wstrb = 8'hxx;
	assign m_axi_rw_req_dsc_wlast = 1'bx;
	assign m_axi_rw_req_dsc_wvalid = 1'b0;
    
	axi_arb_for_rw_req_dsc #(
		.arb_msg_fifo_depth(6),
		.simulation_delay(simulation_delay)
	)axi_arb_for_rw_req_dsc_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axi_rd_req_dsc_araddr(m_axi_rd_req_dsc_araddr),
		.s_axi_rd_req_dsc_arburst(m_axi_rd_req_dsc_arburst),
		.s_axi_rd_req_dsc_arlen(m_axi_rd_req_dsc_arlen),
		.s_axi_rd_req_dsc_arsize(m_axi_rd_req_dsc_arsize),
		.s_axi_rd_req_dsc_arvalid(m_axi_rd_req_dsc_arvalid),
		.s_axi_rd_req_dsc_arready(m_axi_rd_req_dsc_arready),
		
		.s_axi_rd_req_dsc_rdata(m_axi_rd_req_dsc_rdata),
		.s_axi_rd_req_dsc_rresp(m_axi_rd_req_dsc_rresp),
		.s_axi_rd_req_dsc_rlast(m_axi_rd_req_dsc_rlast),
		.s_axi_rd_req_dsc_rvalid(m_axi_rd_req_dsc_rvalid),
		.s_axi_rd_req_dsc_rready(m_axi_rd_req_dsc_rready),
		
		.s_axi_wt_req_dsc_araddr(m_axi_wt_req_dsc_araddr),
		.s_axi_wt_req_dsc_arburst(m_axi_wt_req_dsc_arburst),
		.s_axi_wt_req_dsc_arlen(m_axi_wt_req_dsc_arlen),
		.s_axi_wt_req_dsc_arsize(m_axi_wt_req_dsc_arsize),
		.s_axi_wt_req_dsc_arvalid(m_axi_wt_req_dsc_arvalid),
		.s_axi_wt_req_dsc_arready(m_axi_wt_req_dsc_arready),
		
		.s_axi_wt_req_dsc_rdata(m_axi_wt_req_dsc_rdata),
		.s_axi_wt_req_dsc_rresp(m_axi_wt_req_dsc_rresp),
		.s_axi_wt_req_dsc_rlast(m_axi_wt_req_dsc_rlast),
		.s_axi_wt_req_dsc_rvalid(m_axi_wt_req_dsc_rvalid),
		.s_axi_wt_req_dsc_rready(m_axi_wt_req_dsc_rready),
		
		.m_axi_rw_req_dsc_araddr(m_axi_rw_req_dsc_araddr),
		.m_axi_rw_req_dsc_arburst(m_axi_rw_req_dsc_arburst),
		.m_axi_rw_req_dsc_arlen(m_axi_rw_req_dsc_arlen),
		.m_axi_rw_req_dsc_arsize(m_axi_rw_req_dsc_arsize),
		.m_axi_rw_req_dsc_arvalid(m_axi_rw_req_dsc_arvalid),
		.m_axi_rw_req_dsc_arready(m_axi_rw_req_dsc_arready),
		
		.m_axi_rw_req_dsc_rdata(m_axi_rw_req_dsc_rdata),
		.m_axi_rw_req_dsc_rresp(m_axi_rw_req_dsc_rresp),
		.m_axi_rw_req_dsc_rlast(m_axi_rw_req_dsc_rlast),
		.m_axi_rw_req_dsc_rvalid(m_axi_rw_req_dsc_rvalid),
		.m_axi_rw_req_dsc_rready(m_axi_rw_req_dsc_rready)
	);
	
endmodule
