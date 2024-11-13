`timescale 1ns / 1ps
/********************************************************************
本模块: 用于转发输入特征图/卷积核/线性参数数据流的AXIS路由器

描述:
                          |--------> AXIS输入特征图缓存组
                          |
来自DMA的读数据流 ------- |--------> AXIS卷积核参数缓存区
                     ^    |
				     |    |--------> AXIS线性参数缓存区
                     |
					 |
					 |
                 派发信息

本模块仅涉及纯组合逻辑

派发信息来自读请求缓存区

注意：
无

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2024/10/25
********************************************************************/


module axis_gateway_for_conv_in(
	// DMA读数据流(AXIS从机)
	input wire[63:0] s_axis_dma_data,
	input wire[7:0] s_axis_dma_keep,
	input wire s_axis_dma_last,
	input wire s_axis_dma_valid,
	output wire s_axis_dma_ready,
	
	// 派发信息流(AXIS从机)
	/*
	位编号
     7~5    保留
	 4~3    派发给输入特征图缓存 -> {本行是否有效, 当前缓存区最后1行标志}
	        派发给卷积核参数缓存 -> {当前多通道卷积核是否有效, 1'bx}
	        派发给线性参数缓存   -> {线性参数是否有效, 线性参数类型(1'b0 -> A, 1'b1 -> B)}
	  2     派发给输入特征图缓存
	  1     派发给卷积核参数缓存
	  0     派发给线性参数缓存
	*/
	input wire[7:0] s_axis_dispatch_msg_data,
	input wire s_axis_dispatch_msg_valid,
	output wire s_axis_dispatch_msg_ready,
	
	// 输入特征图缓存(AXIS主机)
	output wire[63:0] m_axis_ft_buf_data,
	output wire m_axis_ft_buf_last, // 表示特征图行尾
	output wire[1:0] m_axis_ft_buf_user, // {本行是否有效, 当前缓存区最后1行标志}
	output wire m_axis_ft_buf_valid,
	input wire m_axis_ft_buf_ready,
	// 卷积核参数缓存(AXIS主机)
	output wire[63:0] m_axis_kernal_buf_data,
	output wire[7:0] m_axis_kernal_buf_keep,
	output wire m_axis_kernal_buf_last, // 表示最后1组卷积核参数
	output wire m_axis_kernal_buf_user, // 当前多通道卷积核是否有效
	output wire m_axis_kernal_buf_valid,
	input wire m_axis_kernal_buf_ready,
	// 线性参数缓存(AXIS主机)
	output wire[63:0] m_axis_linear_pars_data,
	output wire[7:0] m_axis_linear_pars_keep,
	output wire m_axis_linear_pars_last, // 表示最后1组线性参数
	output wire[1:0] m_axis_linear_pars_user, // {线性参数是否有效, 线性参数类型(1'b0 -> A, 1'b1 -> B)}
	output wire m_axis_linear_pars_valid,
	input wire m_axis_linear_pars_ready
);
	
	/** 数据派发 **/
	wire[2:0] dispatch_vec; // 派发选择向量({派发给输入特征图缓存(1bit), 派发给卷积核参数缓存(1bit), 派发给线性参数缓存(1bit)})
	/*
	派发给输入特征图缓存 -> {本行是否有效, 当前缓存区最后1行标志}
	派发给卷积核参数缓存 -> {当前多通道卷积核是否有效, 1'bx}
	派发给线性参数缓存   -> {线性参数是否有效, 线性参数类型(1'b0 -> A, 1'b1 -> B)}
	*/
	wire[1:0] data_pkt_msg; // 数据包信息
	
	// DMA读数据流(AXIS从机)
	// 握手条件: s_axis_dma_valid & s_axis_dispatch_msg_valid & 
	//     ((dispatch_vec & {m_axis_ft_buf_ready, m_axis_kernal_buf_ready, m_axis_linear_pars_ready}) != 3'b000) & 
	//     data_pkt_msg[1]
	assign s_axis_dma_ready = s_axis_dispatch_msg_valid & 
		(|(dispatch_vec & {m_axis_ft_buf_ready, m_axis_kernal_buf_ready, m_axis_linear_pars_ready})) & 
		data_pkt_msg[1];
	
	// 派发信息流(AXIS从机)
	// 握手条件: s_axis_dispatch_msg_valid & 
	//     ((dispatch_vec & {m_axis_ft_buf_ready, m_axis_kernal_buf_ready, m_axis_linear_pars_ready}) != 3'b000) & 
	//     (data_pkt_msg[1] ? (s_axis_dma_valid & s_axis_dma_last):1'b1)
	assign s_axis_dispatch_msg_ready = 
		(|(dispatch_vec & {m_axis_ft_buf_ready, m_axis_kernal_buf_ready, m_axis_linear_pars_ready})) & 
		((~data_pkt_msg[1]) | (s_axis_dma_valid & s_axis_dma_last));
	
	// 输入特征图缓存(AXIS主机)
	assign m_axis_ft_buf_data = s_axis_dma_data;
	assign m_axis_ft_buf_last = (~data_pkt_msg[1]) | s_axis_dma_last;
	assign m_axis_ft_buf_user = data_pkt_msg;
	// 握手条件: s_axis_dispatch_msg_valid & dispatch_vec[2] & (data_pkt_msg[1] ? s_axis_dma_valid:1'b1) & 
	//     m_axis_ft_buf_ready
	assign m_axis_ft_buf_valid = s_axis_dispatch_msg_valid & dispatch_vec[2] & 
		((~data_pkt_msg[1]) | s_axis_dma_valid);
	
	// 卷积核参数缓存(AXIS主机)
	assign m_axis_kernal_buf_data = s_axis_dma_data;
	assign m_axis_kernal_buf_keep = {8{data_pkt_msg[1]}} & s_axis_dma_keep;
	assign m_axis_kernal_buf_last = (~data_pkt_msg[1]) | s_axis_dma_last;
	assign m_axis_kernal_buf_user = data_pkt_msg[1];
	// 握手条件: s_axis_dispatch_msg_valid & dispatch_vec[1] & (data_pkt_msg[1] ? s_axis_dma_valid:1'b1) & 
	//     m_axis_ft_buf_ready
	assign m_axis_kernal_buf_valid = s_axis_dispatch_msg_valid & dispatch_vec[1] & 
		((~data_pkt_msg[1]) | s_axis_dma_valid);
	
	// 线性参数缓存(AXIS主机)
	assign m_axis_linear_pars_data = s_axis_dma_data;
	assign m_axis_linear_pars_keep = s_axis_dma_keep;
	assign m_axis_linear_pars_last = (~data_pkt_msg[1]) | s_axis_dma_last;
	assign m_axis_linear_pars_user = data_pkt_msg;
	// 握手条件: s_axis_dispatch_msg_valid & dispatch_vec[0] & (data_pkt_msg[1] ? s_axis_dma_valid:1'b1) & 
	//     m_axis_ft_buf_ready
	assign m_axis_linear_pars_valid = s_axis_dispatch_msg_valid & dispatch_vec[0] & 
		((~data_pkt_msg[1]) | s_axis_dma_valid);
	
	// 派发选择向量
	assign dispatch_vec = s_axis_dispatch_msg_data[2:0];
	// 数据包信息
	assign data_pkt_msg = s_axis_dispatch_msg_data[4:3];
	
endmodule
