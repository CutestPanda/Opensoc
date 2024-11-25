`timescale 1ns / 1ps
/********************************************************************
本模块: AXI通用卷积计算单元

描述:
支持多核多通道1x1/3x3卷积
支持当卷积核类型为3x3时向上/下/左/右填充1像素
32位地址64位数据的AXI主机

特征图缓存区存储顺序 ->
	{
		[x1y1, 通道1] [x2y1, 通道1] .... [xny1, 通道1]
							:
							:
		[x1yn, 通道1] [x2yn, 通道1] .... [xnyn, 通道1]
	}
	... ...
	{
		[x1y1, 通道n] [x2y1, 通道n] .... [xny1, 通道n]
							:
							:
		[x1yn, 通道n] [x2yn, 通道n] .... [xnyn, 通道n]
	}

卷积核缓存区存储顺序 ->
	[核1通道1] [核1通道2] .... [核1通道n]
	                :
					:
	[核m通道1] [核m通道2] .... [核m通道n]

线性参数缓存区存储顺序 ->
	[乘数1, 加数1] [乘数2, 加数2] ... [乘数m, 加数m]

注意：
输入特征图通道数应当等于卷积核通道数
输入特征图缓存个数(in_feature_map_buffer_n)必须>=通道并行数(prl_chn_n)
卷积核参数缓存个数(kernal_pars_buffer_n)必须>=卷积核并行数(prl_kernal_n)

协议:
AXI-Lite SLAVE
AXI MASTER

作者: 陈家耀
日期: 2024/11/10
********************************************************************/


module axi_generic_conv #(
	// 读请求描述子DMA配置
	parameter integer max_rd_req_n = 1024 * 1024, // 最大的读请求个数
	parameter integer axi_rd_req_dsc_rchn_max_burst_len = 8, // AXI读通道最大突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer rd_req_dsc_buffer_depth = 512, // 读请求描述子buffer深度(256 | 512 | 1024 | ...)
	// 写请求描述子DMA配置
	parameter integer max_wt_req_n = 1024 * 1024, // 最大的写请求个数
	parameter integer axi_wt_req_dsc_rchn_max_burst_len = 8, // AXI读通道最大突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer wt_req_dsc_buffer_depth = 512, // 写请求描述子buffer深度(256 | 512 | 1024 | ...)
	// 特征图与参数输入/特征图输出DMA是否使能4KB边界保护
	parameter axi_conv_rw_chn_en_4KB_boundary_protection = "true", 
	// 特征图与参数输入DMA配置
	parameter integer conv_max_rd_btt = 65536, // 最大的读传输字节数(256 | 512 | 1024 | ...)
	parameter integer axi_conv_rchn_max_burst_len = 32, // AXI读通道最大突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer axi_conv_raddr_outstanding = 4, // AXI读地址缓冲深度(1 | 2 | 4)
	parameter integer axi_conv_rdata_buffer_depth = 512, // AXI读数据buffer深度(0 -> 不启用 | 512 | 1024 | ...)
	// 特征图输出DMA配置
	parameter integer conv_max_wt_btt = 65536, // 最大的写传输字节数(256 | 512 | 1024 | ...)
	parameter integer axi_conv_wchn_max_burst_len = 32, // AXI写通道最大突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer axi_conv_waddr_outstanding = 4, // AXI写地址缓冲深度(1 | 2 | 4)
	parameter integer axi_conv_wdata_buffer_depth = 512, // AXI写数据buffer深度(512 | 1024 | ...)
	// 特征图和参数缓存区配置
	parameter integer in_feature_map_buffer_n = 8, // 输入特征图缓存个数
	parameter integer kernal_pars_buffer_n = 8, // 卷积核参数缓存个数
	parameter integer out_buffer_n = 8, // 多通道卷积结果缓存个数
	// 卷积计算配置
	parameter integer in_ft_quaz_acc = 10, // 特征点量化精度(必须在范围[1, feature_pars_data_width-1]内)
	parameter integer conv_res_ext_int_width = 4, // 卷积结果额外考虑的整数位数(必须<=(feature_pars_data_width-in_ft_quaz_acc))
	parameter integer conv_res_ext_frac_width = 4, // 卷积结果额外考虑的小数位数(必须<=in_ft_quaz_acc)
	// 线性乘加与激活计算配置
	parameter integer ab_quaz_acc = 12, // a/b系数量化精度(必须在范围[1, feature_pars_data_width-1]内)
	parameter integer c_quaz_acc = 14, // c系数量化精度(必须在范围[1, feature_pars_data_width-1]内)
	// 多通道卷积参数配置
	parameter integer feature_pars_data_width = 16, // 特征点和参数位宽(8 | 16 | 32 | 64)
	parameter integer max_feature_map_w = 512, // 最大的输入特征图宽度
	parameter integer max_feature_map_h = 512, // 最大的输入特征图高度
	parameter integer max_feature_map_chn_n = 512, // 最大的输入特征图通道数
	parameter integer max_kernal_n = 512, // 最大的卷积核个数
	parameter integer prl_chn_n = 4, // 通道并行数(1 | 2 | 4 | 8 | 16)
	parameter integer prl_kernal_n = 4, // 卷积核并行数(1 | 2 | 4 | 8 | 16)
	// 仿真参数配置
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 寄存器配置接口(AXI-Lite从机)
    // 读地址通道
    input wire[31:0] s_axi_lite_araddr,
	input wire[2:0] s_axi_lite_arprot, // ignored
    input wire s_axi_lite_arvalid,
    output wire s_axi_lite_arready,
    // 写地址通道
    input wire[31:0] s_axi_lite_awaddr,
	input wire[2:0] s_axi_lite_awprot, // ignored
    input wire s_axi_lite_awvalid,
    output wire s_axi_lite_awready,
    // 写响应通道
    output wire[1:0] s_axi_lite_bresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_bvalid,
    input wire s_axi_lite_bready,
    // 读数据通道
    output wire[31:0] s_axi_lite_rdata,
    output wire[1:0] s_axi_lite_rresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_rvalid,
    input wire s_axi_lite_rready,
    // 写数据通道
    input wire[31:0] s_axi_lite_wdata,
	input wire[3:0] s_axi_lite_wstrb,
    input wire s_axi_lite_wvalid,
    output wire s_axi_lite_wready,
	
	// 特征图与参数输入/特征图输出(AXI主机)
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
	
	// 读/写请求描述子输入(AXI主机, READ ONLY)
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
	
	// 中断信号
	output wire itr
);
    
	/** 寄存器配置接口 **/
	// 块级控制
	// 读请求描述子DMA
	wire rd_req_dsc_dma_blk_start;
	wire rd_req_dsc_dma_blk_idle;
	// 写请求描述子DMA
	wire wt_req_dsc_dma_blk_start;
	wire wt_req_dsc_dma_blk_idle;
	// 使能
	wire en_conv_cal; // 是否使能卷积计算
	// 复位
	wire rst_linear_pars_buf; // 复位线性参数缓存区
	wire rst_cal_path_kernal_buf; // 复位数据通路上的卷积核参数缓存
	// 中断
	wire[31:0] wt_req_itr_th; // 写请求处理完成中断阈值
	wire[2:0] itr_req; // 中断请求({写请求处理完成中断请求, 
	                   //     写请求描述子DMA请求处理完成中断请求, 读请求描述子DMA请求处理完成中断请求})
	wire en_wt_req_fns_itr; // 是否使能写请求处理完成中断
	// 已完成的写请求个数
	wire[3:0] to_set_wt_req_fns_n;
	wire[31:0] wt_req_fns_n_set_v;
	wire[31:0] wt_req_fns_n_cur_v;
	// 运行时参数
	wire[feature_pars_data_width-1:0] act_rate_c; // Relu激活系数c
	wire[31:0] rd_req_buf_baseaddr; // 读请求缓存区首地址
	wire[31:0] rd_req_n; // 读请求个数 - 1
	wire[31:0] wt_req_buf_baseaddr; // 写请求缓存区首地址
	wire[31:0] wt_req_n; // 写请求个数 - 1
	wire kernal_type; // 卷积核类型(1'b0 -> 1x1, 1'b1 -> 3x3)
	wire[15:0] feature_map_w; // 输入特征图宽度 - 1
	wire[15:0] feature_map_h; // 输入特征图高度 - 1
	wire[15:0] feature_map_chn_n; // 输入特征图通道数 - 1
	wire[15:0] kernal_n; // 卷积核个数 - 1
	wire[3:0] padding_en; // 外拓填充使能(仅当卷积核类型为3x3时可用, {上, 下, 左, 右})
	
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
		
		.act_rate_c(act_rate_c), // 位宽64与位宽feature_pars_data_width不符, 取低位!
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
	
	/** 中断控制 **/
	// 读请求描述子DMA请求处理完成(指示)
	wire rd_req_dsc_dma_blk_done;
	// 写请求描述子DMA请求处理完成(指示)
	wire wt_req_dsc_dma_blk_done;
	// 完成写请求(指示)
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
	
	/** 读请求描述子DMA **/
	// 读请求描述子(AXIS主机)
	wire[63:0] m_axis_rd_req_dsc_data;
	wire m_axis_rd_req_dsc_valid;
	wire m_axis_rd_req_dsc_ready;
	// AXI主机(读通道)
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
	
	/** 写请求描述子DMA **/
	// 写请求描述子(AXIS主机)
	wire[63:0] m_axis_wt_req_dsc_data;
	wire m_axis_wt_req_dsc_valid;
	wire m_axis_wt_req_dsc_ready;
	// AXI主机(读通道)
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
	
	/** AXIS读请求派发单元 **/
	// 读请求描述子(AXIS从机)
	wire[63:0] s_axis_rd_req_dsc_data;
	wire s_axis_rd_req_dsc_valid;
	wire s_axis_rd_req_dsc_ready;
	// 输入特征图/卷积核/线性参数读请求(AXIS主机)
	wire[63:0] m_axis_rd_req_data; // {待读取的字节数(32bit), 基地址(32bit)}
	wire m_axis_rd_req_valid;
	wire m_axis_rd_req_ready;
	// 派发信息流(AXIS主机)
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
	
	/** 特征图与参数输入DMA **/
	// 输入特征图/卷积核/线性参数读请求
	wire[63:0] s_axis_rd_req_data; // {待读取的字节数(32bit), 基地址(32bit)}
	wire s_axis_rd_req_valid;
	wire s_axis_rd_req_ready;
	// 输入特征图/卷积核/线性参数数据流
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
	
	/** AXIS数据派发路由器 **/
	// DMA读数据流(AXIS从机)
	wire[63:0] s_axis_ft_par_dma_data;
	wire[7:0] s_axis_ft_par_dma_keep;
	wire s_axis_ft_par_dma_last;
	wire s_axis_ft_par_dma_valid;
	wire s_axis_ft_par_dma_ready;
	// 派发信息流(AXIS从机)
	wire[7:0] s_axis_dispatch_msg_data;
	wire s_axis_dispatch_msg_valid;
	wire s_axis_dispatch_msg_ready;
	// 输入特征图缓存(AXIS主机)
	wire[63:0] m_axis_ft_buf_data;
	wire m_axis_ft_buf_last; // 表示特征图行尾
	wire[1:0] m_axis_ft_buf_user; // {本行是否有效, 当前缓存区最后1行标志}
	wire m_axis_ft_buf_valid;
	wire m_axis_ft_buf_ready;
	// 卷积核参数缓存(AXIS主机)
	wire[63:0] m_axis_kernal_buf_data;
	wire[7:0] m_axis_kernal_buf_keep;
	wire m_axis_kernal_buf_last; // 表示最后1组卷积核参数
	wire m_axis_kernal_buf_user; // 当前多通道卷积核是否有效
	wire m_axis_kernal_buf_valid;
	wire m_axis_kernal_buf_ready;
	// 线性参数缓存(AXIS主机)
	wire[63:0] m_axis_linear_pars_data;
	wire[7:0] m_axis_linear_pars_keep;
	wire m_axis_linear_pars_last; // 表示最后1组线性参数
	wire[1:0] m_axis_linear_pars_user; // {线性参数是否有效, 线性参数类型(1'b0 -> A, 1'b1 -> B)}
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
	
	/** AXIS输入特征图缓存组 **/
	// 输入特征图(AXIS从机)
	wire[63:0] s_axis_ft_buf_data;
	wire s_axis_ft_buf_last; // 表示特征图行尾
	wire[1:0] s_axis_ft_buf_user; // {本行是否有效, 当前缓存区最后1行标志}
	wire s_axis_ft_buf_valid;
	wire s_axis_ft_buf_ready;
	// 缓存输出(AXIS主机)
	// {缓存#(n-1)行#2, 缓存#(n-1)行#1, 缓存#(n-1)行#0, ..., 缓存#0行#2, 缓存#0行#1, 缓存#0行#0}
	wire[feature_pars_data_width*3*prl_chn_n-1:0] m_axis_feature_map_data;
	wire m_axis_feature_map_last; // 表示特征图行尾
	wire[prl_chn_n*3-1:0] m_axis_feature_map_user; // {缓存行是否有效标志向量}
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
	
	/** AXIS卷积核参数缓存区 **/
	// 输入卷积核参数流(AXIS从机)
	wire[63:0] s_axis_kernal_buf_data;
	wire[7:0] s_axis_kernal_buf_keep;
	wire s_axis_kernal_buf_last; // 表示最后1组卷积核参数
	wire s_axis_kernal_buf_user; // 当前多通道卷积核是否有效
	wire s_axis_kernal_buf_valid;
	wire s_axis_kernal_buf_ready;
	// 卷积核参数缓存控制(fifo读端口)
	wire kernal_pars_buf_fifo_ren;
	wire kernal_pars_buf_fifo_empty_n;
	// 卷积核参数缓存MEM读端口
	wire kernal_pars_buf_mem_buf_ren_s0;
	wire kernal_pars_buf_mem_buf_ren_s1;
	wire[15:0] kernal_pars_buf_mem_buf_raddr; // 每个读地址对应1个单通道卷积核
	wire[prl_kernal_n*feature_pars_data_width*9-1:0] kernal_pars_buf_mem_buf_dout; // {核#(n-1), ..., 核#1, 核#0}
	
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
	
	/** AXIS线性参数缓存区 **/
	// 线性参数缓存区加载完成标志
	wire linear_pars_buf_load_completed;
	// 输入线性参数流(AXIS从机)
	wire[63:0] s_axis_linear_pars_data;
	wire[7:0] s_axis_linear_pars_keep;
	wire s_axis_linear_pars_last; // 表示最后1组线性参数
	wire[1:0] s_axis_linear_pars_user; // {线性参数是否有效, 线性参数类型(1'b0 -> A, 1'b1 -> B)}
	wire s_axis_linear_pars_valid;
	wire s_axis_linear_pars_ready;
	// 线性参数获取(MEM读)
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
	
	/** n通道并行m核并行3x3卷积计算单元 **/
	// 计算参数
	wire[15:0] o_ft_map_h; // 输出特征图高度 - 1
	// 特征图输入(AXIS从机)
	// {缓存#(n-1)行#2, 缓存#(n-1)行#1, 缓存#(n-1)行#0, ..., 缓存#0行#2, 缓存#0行#1, 缓存#0行#0}
	wire[feature_pars_data_width*3*prl_chn_n-1:0] s_axis_feature_map_data;
	wire s_axis_feature_map_last; // 表示特征图行尾
	wire s_axis_feature_map_valid;
	wire s_axis_feature_map_ready;
	// 卷积核通道累加中间结果输出(AXIS主机)
	// {核#(m-1)结果, ..., 核#1结果, 核#0结果}
	// 每个中间结果仅低(conv_res_ext_int_width+feature_pars_data_width+conv_res_ext_frac_width)位有效
	wire[feature_pars_data_width*2*prl_kernal_n-1:0] m_axis_mid_res_data;
	wire m_axis_mid_res_last; // 表示行尾
	wire m_axis_mid_res_user; // 表示当前行最后1组结果
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
	
	/** AXIS多通道卷积结果缓存区 **/
	// 卷积核通道累加中间结果输入(AXIS从机)
	// {核#(m-1)结果, ..., 核#1结果, 核#0结果}
	// 每个中间结果仅低(conv_res_ext_int_width+feature_pars_data_width+conv_res_ext_frac_width)位有效
	wire[feature_pars_data_width*2*prl_kernal_n-1:0] s_axis_mid_res_data;
	wire s_axis_mid_res_last; // 表示行尾
	wire s_axis_mid_res_user; // 表示当前行最后1组结果
	wire s_axis_mid_res_valid;
	wire s_axis_mid_res_ready;
	// 输出特征图数据流输出(AXIS主机)
	// 特征图数据仅低(conv_res_ext_int_width+feature_pars_data_width+conv_res_ext_frac_width)位有效
	wire[feature_pars_data_width*2-1:0] m_axis_conv_res_data;
	wire[15:0] m_axis_conv_res_user; // 当前输出特征行所在的通道号
	wire m_axis_conv_res_last; // 表示行尾
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
	
	/** AXIS线性乘加与激活计算单元 **/
	// 多通道卷积计算结果输入(AXIS从机)
	// 仅低(conv_res_ext_int_width+feature_pars_data_width+conv_res_ext_frac_width)位有效
	wire[feature_pars_data_width*2-1:0] s_axis_conv_res_data;
	wire[15:0] s_axis_conv_res_user; // 当前输出特征行所在的通道号
	wire s_axis_conv_res_last; // 表示行尾
	wire s_axis_conv_res_valid;
	wire s_axis_conv_res_ready;
	// 线性乘加与激活计算结果输出(AXIS主机)
	// 仅低(conv_res_ext_int_width+feature_pars_data_width+conv_res_ext_frac_width)位有效
	wire[feature_pars_data_width*2-1:0] m_axis_linear_act_res_data;
	wire m_axis_linear_act_res_last; // 表示行尾
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
	
	/** 特征图输出DMA **/
	// 计算结果写请求
	wire[63:0] s_axis_wt_req_data; // {待写入的字节数(32bit), 基地址(32bit)}
	wire s_axis_wt_req_valid;
	wire s_axis_wt_req_ready;
	// 计算结果流
	wire[feature_pars_data_width-1:0] s_axis_res_data;
	wire s_axis_res_last; // 表示本次写请求最后1个数据
	wire s_axis_res_valid;
	wire s_axis_res_ready;
	
	assign s_axis_wt_req_data = m_axis_wt_req_dsc_data;
	assign s_axis_wt_req_valid = m_axis_wt_req_dsc_valid;
	assign m_axis_wt_req_dsc_ready = s_axis_wt_req_ready;
	
	// 将线性乘加与激活得到的结果右移conv_res_ext_frac_width位, 得到量化精度为in_ft_quaz_acc的输出特征点
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
	
	/** 读/写请求描述子AXI读通道仲裁 **/
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
