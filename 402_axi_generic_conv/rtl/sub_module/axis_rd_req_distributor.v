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
本模块: AXIS读请求派发单元

描述:
解析读请求描述子, 产生输入特征图/卷积核/线性参数读请求和派发信息流

每个读请求描述子的长度是64bit -> 
	位编号            内容
	 31~0            基地址
	 33~32      派发目标类型编号
	         (2'b00 -> 线性参数缓存, 
			 2'b01 -> 卷积核参数缓存, 
			 2'b10 -> 输入特征图缓存)
	 35~34         数据包信息
              (见派发信息流的描述)
	 63~36       待读取的字节数

注意：
无

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2024/11/07
********************************************************************/


module axis_rd_req_distributor #(
	parameter integer max_rd_btt = 4 * 512, // 最大的读传输字节数(256 | 512 | 1024 | ...)
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 读请求描述子(AXIS从机)
	input wire[63:0] s_axis_dsc_data,
	input wire s_axis_dsc_valid,
	output wire s_axis_dsc_ready,
	
	// 输入特征图/卷积核/线性参数读请求(AXIS主机)
	output wire[63:0] m_axis_rd_req_data, // {待读取的字节数(32bit), 基地址(32bit)}
	output wire m_axis_rd_req_valid,
	input wire m_axis_rd_req_ready,
	
	// 派发信息流(AXIS主机)
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
	output wire[7:0] m_axis_dispatch_msg_data,
	output wire m_axis_dispatch_msg_valid,
	input wire m_axis_dispatch_msg_ready
);
    
	// 计算bit_depth的最高有效位编号(即位数-1)
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
	
    /** 常量 **/
	// 派发目标类型编号
	localparam DISPATCH_TARGET_LINEAR_PARS = 2'b00; // 派发目标类型: 线性参数缓存
	localparam DISPATCH_TARGET_KERNAL_PARS = 2'b01; // 派发目标类型: 卷积核参数缓存
	localparam DISPATCH_TARGET_FT_MAP = 2'b10; // 派发目标类型: 输入特征图缓存
	
	/** 读请求描述子 **/
	wire[31:0] rd_req_baseaddr; // 读请求基地址
	wire[clogb2(max_rd_btt):0] rd_req_btt; // 待读取的字节数
	wire[1:0] dispatch_target; // 派发目标类型编号
	wire[1:0] pkt_msg; // 数据包信息
	
	assign rd_req_baseaddr = s_axis_dsc_data[31:0];
	assign dispatch_target = s_axis_dsc_data[33:32];
	assign pkt_msg = s_axis_dsc_data[35:34];
	assign rd_req_btt = s_axis_dsc_data[63:36];
	
	/** 读请求描述子AXIS从机 **/
	wire ft_map_pars_fifo_full_n; // 输入特征图/卷积核/线性参数读请求fifo满标志
	wire dispatch_msg_fifo_full_n; // 派发信息fifo满标志
	
	// 握手条件: s_axis_dsc_valid & ft_map_pars_fifo_full_n & dispatch_msg_fifo_full_n
	assign s_axis_dsc_ready = ft_map_pars_fifo_full_n & dispatch_msg_fifo_full_n;
	
	/** 输入特征图/卷积核/线性参数读请求fifo **/
	// fifo写端口
	wire ft_map_pars_fifo_wen;
	wire[32+clogb2(max_rd_btt):0] ft_map_pars_fifo_din;
	// fifo读端口
	wire ft_map_pars_fifo_ren;
	wire[32+clogb2(max_rd_btt):0] ft_map_pars_fifo_dout;
	wire ft_map_pars_fifo_empty_n;
	
	// 握手条件: s_axis_dsc_valid & ft_map_pars_fifo_full_n & dispatch_msg_fifo_full_n & pkt_msg[1]
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
	
	/** 派发信息fifo **/
	// fifo写端口
	wire dispatch_msg_fifo_wen;
	wire[3:0] dispatch_msg_fifo_din;
	// fifo读端口
	wire dispatch_msg_fifo_ren;
	wire[3:0] dispatch_msg_fifo_dout;
	wire dispatch_msg_fifo_empty_n;
	
	// 握手条件: s_axis_dsc_valid & ft_map_pars_fifo_full_n & dispatch_msg_fifo_full_n
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
