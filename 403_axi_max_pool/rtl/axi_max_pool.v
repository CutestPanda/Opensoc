/*
MIT License

Copyright (c) 2024 Panda, 2257691535@qq.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

`timescale 1ns / 1ps
/********************************************************************
本模块: AXI-最大池化加速器

描述:
实现神经网络中的最大池化处理(max pool)
多像素/clk
流控制模式固定为阻塞
池化窗口大小为2x2
支持步长为1或2
支持当步长为1时向上/下/左/右填充

处理速度 = 1特征组/clk

步长       输入     输出
  1      1 1 2 2  [1  1  2  2  2]
         3 4 3 1  [3] 4  4  3 [2]
         1 1 0 0  [3] 4  4  3 [1]
         7 8 0 1  [7] 8  8  1 [1]
		          [7  8  8  1  1]
  2      1 1 2 2
         3 4 3 1      4     3
         1 1 0 0
         7 8 0 1      8     1

注意：
输入特征图的宽度/高度/通道数必须<=最大的输入特征图宽度/高度/通道数

输入/输出特征图数据流 ->
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

协议:
AXI-Lite SLAVE
AXI MASTER

作者: 陈家耀
日期: 2024/11/26
********************************************************************/


module axi_max_pool #(
	// DMA配置
	parameter integer axi_max_burst_len = 32, // AXI主机最大突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer axi_addr_outstanding = 4, // AXI地址缓冲深度(1~16)
	parameter integer max_rd_btt = 4 * 512, // 最大的读请求传输字节数(256 | 512 | 1024 | ...)
	parameter integer axi_rdata_buffer_depth = 512, // AXI读数据buffer深度(0 -> 不启用 | 512 | 1024 | ...)
	parameter integer max_wt_btt = 4 * 512, // 最大的写请求传输字节数(256 | 512 | 1024 | ...)
	parameter integer axi_wdata_buffer_depth = 512, // AXI写数据buffer深度(512 | 1024 | ...)
	// 最大池化计算参数配置
    parameter integer feature_n_per_clk = 4, // 每个clk输入的特征点数量(2 | 4 | 8 | 16 | ...)
	parameter integer feature_data_width = 16, // 特征点位宽(必须能被8整除, 且>0)
	parameter integer max_feature_chn_n = 128, // 最大的特征图通道数
	parameter integer max_feature_w = 128, // 最大的输入特征图宽度
	parameter integer max_feature_h = 128, // 最大的输入特征图高度
	// 仿真参数配置
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire resetn,
	
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
	
	// AXI主机
	// AR
    output wire[31:0] m_axi_araddr,
    output wire[1:0] m_axi_arburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_arlen,
    output wire[2:0] m_axi_arsize, // const -> 3'b011
    output wire[3:0] m_axi_arcache, // const -> 4'b0011
    output wire m_axi_arvalid,
    input wire m_axi_arready,
	// AW
    output wire[31:0] m_axi_awaddr,
    output wire[1:0] m_axi_awburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_awlen,
    output wire[2:0] m_axi_awsize, // const -> 3'b011
    output wire[3:0] m_axi_awcache, // const -> 4'b0011
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
	
	// 中断信号
	output wire itr
);
    
	/** 寄存器配置接口 **/
	// DMA读通道控制
	wire dma_mm2s_start;
	wire dma_mm2s_idle;
	wire dma_mm2s_done;
	// DMA写通道控制
	wire dma_s2mm_start;
	wire dma_s2mm_idle;
	wire dma_s2mm_done;
	// 最大池化计算控制
	wire max_pool_cal_start;
	wire max_pool_cal_idle;
	wire max_pool_cal_done;
	// 运行时参数
	wire[31:0] in_ft_map_buf_baseaddr; // 输入特征图缓存区基地址
	wire[31:0] in_ft_map_buf_len; // 输入特征图缓存区长度 - 1(以字节计)
	wire[31:0] out_ft_map_buf_baseaddr; // 输出特征图缓存区基地址
	wire[31:0] out_ft_map_buf_len; // 输出特征图缓存区长度 - 1(以字节计)
	wire step_type; // 步长类型(1'b0 -> 步长为1, 1'b1 -> 步长为2)
	wire[3:0] padding_vec; // 外拓填充向量(仅当步长为1时可用, {上, 下, 左, 右})
	wire[15:0] feature_map_chn_n; // 特征图通道数 - 1
	wire[15:0] feature_map_w; // 特征图宽度 - 1
	wire[15:0] feature_map_h; // 特征图高度 - 1
	
	reg_if_for_max_pool #(
		.simulation_delay(simulation_delay)
	)reg_if_for_max_pool_u(
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
		
		.max_pool_cal_start(max_pool_cal_start),
		.max_pool_cal_idle(max_pool_cal_idle),
		.max_pool_cal_done(max_pool_cal_done),
		
		.in_ft_map_buf_baseaddr(in_ft_map_buf_baseaddr),
		.in_ft_map_buf_len(in_ft_map_buf_len),
		.out_ft_map_buf_baseaddr(out_ft_map_buf_baseaddr),
		.out_ft_map_buf_len(out_ft_map_buf_len),
		.step_type(step_type),
		.padding_vec(padding_vec),
		.feature_map_chn_n(feature_map_chn_n),
		.feature_map_w(feature_map_w),
		.feature_map_h(feature_map_h),
		
		.itr(itr)
	);
	
	/** 输入/输出特征图DMA **/
	// 输出结果特征图数据流
	wire[63:0] s_axis_out_ft_map_data;
	wire[7:0] s_axis_out_ft_map_keep;
	wire s_axis_out_ft_map_last;
	wire s_axis_out_ft_map_valid;
	wire s_axis_out_ft_map_ready;
	// 输入待处理特征图数据流
	wire[63:0] m_axis_in_ft_map_data;
	wire[7:0] m_axis_in_ft_map_keep;
	wire m_axis_in_ft_map_last;
	wire m_axis_in_ft_map_valid;
	wire m_axis_in_ft_map_ready;
	
	axi_dma_for_max_pool #(
		.axi_max_burst_len(axi_max_burst_len),
		.axi_addr_outstanding(axi_addr_outstanding),
		.max_rd_btt(max_rd_btt),
		.axi_rdata_buffer_depth(axi_rdata_buffer_depth),
		.max_wt_btt(max_wt_btt),
		.axi_wdata_buffer_depth(axi_wdata_buffer_depth),
		.simulation_delay(simulation_delay)
	)axi_dma_for_max_pool_u(
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
		.m_axi_arcache(m_axi_arcache),
		.m_axi_arvalid(m_axi_arvalid),
		.m_axi_arready(m_axi_arready),
		.m_axi_awaddr(m_axi_awaddr),
		.m_axi_awburst(m_axi_awburst),
		.m_axi_awlen(m_axi_awlen),
		.m_axi_awsize(m_axi_awsize),
		.m_axi_awcache(m_axi_awcache),
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
	
	/** 最大池化处理单元 **/
	// 待处理特征图像素流输入
	wire[feature_n_per_clk*feature_data_width-1:0] s_axis_max_pool_data;
	wire[feature_n_per_clk*feature_data_width/8-1:0] s_axis_max_pool_keep;
	wire s_axis_max_pool_last; // 指示特征图结束
	wire s_axis_max_pool_valid;
	wire s_axis_max_pool_ready;
	// 处理后特征图像素流输出
	wire[feature_n_per_clk*feature_data_width-1:0] m_axis_max_pool_data;
	wire[feature_n_per_clk*feature_data_width/8-1:0] m_axis_max_pool_keep;
	wire m_axis_max_pool_last; // 特征图最后1点
	wire m_axis_max_pool_valid;
	wire m_axis_max_pool_ready;
	
	max_pool_mul_pix #(
		.feature_n_per_clk(feature_n_per_clk),
		.feature_data_width(feature_data_width),
		.max_feature_chn_n(max_feature_chn_n),
		.max_feature_w(max_feature_w),
		.max_feature_h(max_feature_h),
		.en_out_reg_slice("true"),
		.simulation_delay(simulation_delay)
	)max_pool_mul_pix_u(
		.clk(clk),
		.rst_n(resetn),
		
		.blk_start(max_pool_cal_start),
		.blk_idle(max_pool_cal_idle),
		.blk_done(max_pool_cal_done),
		
		.step_type(step_type),
		.padding_vec(padding_vec),
		.feature_map_chn_n(feature_map_chn_n),
		.feature_map_w(feature_map_w),
		.feature_map_h(feature_map_h),
		
		.s_axis_data(s_axis_max_pool_data),
		.s_axis_keep(s_axis_max_pool_keep),
		.s_axis_last(s_axis_max_pool_last),
		.s_axis_valid(s_axis_max_pool_valid),
		.s_axis_ready(s_axis_max_pool_ready),
		
		.m_axis_data(m_axis_max_pool_data),
		.m_axis_keep(m_axis_max_pool_keep),
		.m_axis_last(m_axis_max_pool_last),
		.m_axis_valid(m_axis_max_pool_valid),
		.m_axis_ready(m_axis_max_pool_ready)
	);
	
	/** 位宽变换(64 -> feature_n_per_clk*feature_data_width) **/
	// 位宽变换输入
	wire[63:0] s_axis_dw_cvt_0_data;
	wire[7:0] s_axis_dw_cvt_0_keep;
	wire s_axis_dw_cvt_0_last;
	wire s_axis_dw_cvt_0_valid;
	wire s_axis_dw_cvt_0_ready;
	// 位宽变换输出
	wire[feature_n_per_clk*feature_data_width-1:0] m_axis_dw_cvt_0_data;
	wire[feature_n_per_clk*feature_data_width/8-1:0] m_axis_dw_cvt_0_keep;
	wire m_axis_dw_cvt_0_last; // 指示特征图结束
	wire m_axis_dw_cvt_0_valid;
	wire m_axis_dw_cvt_0_ready;
	
	assign s_axis_dw_cvt_0_data = m_axis_in_ft_map_data;
	assign s_axis_dw_cvt_0_keep = m_axis_in_ft_map_keep;
	assign s_axis_dw_cvt_0_last = m_axis_in_ft_map_last;
	assign s_axis_dw_cvt_0_valid = m_axis_in_ft_map_valid;
	assign m_axis_in_ft_map_ready = s_axis_dw_cvt_0_ready;
	
	assign s_axis_max_pool_data = m_axis_dw_cvt_0_data;
	assign s_axis_max_pool_keep = m_axis_dw_cvt_0_keep;
	assign s_axis_max_pool_last = m_axis_dw_cvt_0_last;
	assign s_axis_max_pool_valid = m_axis_dw_cvt_0_valid;
	assign m_axis_dw_cvt_0_ready = s_axis_max_pool_ready;
	
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
	
	/** 位宽变换(feature_n_per_clk*feature_data_width -> 64) **/
	// 位宽变换输入
	wire[feature_n_per_clk*feature_data_width-1:0] s_axis_dw_cvt_1_data;
	wire[feature_n_per_clk*feature_data_width/8-1:0] s_axis_dw_cvt_1_keep;
	wire s_axis_dw_cvt_1_last;
	wire s_axis_dw_cvt_1_valid;
	wire s_axis_dw_cvt_1_ready;
	// 位宽变换输出
	wire[63:0] m_axis_dw_cvt_1_data;
	wire[7:0] m_axis_dw_cvt_1_keep;
	wire m_axis_dw_cvt_1_last; // 指示特征图结束
	wire m_axis_dw_cvt_1_valid;
	wire m_axis_dw_cvt_1_ready;
	
	assign s_axis_dw_cvt_1_data = m_axis_max_pool_data;
	assign s_axis_dw_cvt_1_keep = m_axis_max_pool_keep;
	assign s_axis_dw_cvt_1_last = m_axis_max_pool_last;
	assign s_axis_dw_cvt_1_valid = m_axis_max_pool_valid;
	assign m_axis_max_pool_ready = s_axis_dw_cvt_1_ready;
	
	assign s_axis_out_ft_map_data = m_axis_dw_cvt_1_data;
	assign s_axis_out_ft_map_keep = m_axis_dw_cvt_1_keep;
	assign s_axis_out_ft_map_last = m_axis_dw_cvt_1_last;
	assign s_axis_out_ft_map_valid = m_axis_dw_cvt_1_valid;
	assign m_axis_dw_cvt_1_ready = s_axis_out_ft_map_ready;
	
	axis_dw_cvt #(
		.slave_data_width(feature_n_per_clk*feature_data_width),
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
		.s_axis_keep(s_axis_dw_cvt_1_keep),
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
