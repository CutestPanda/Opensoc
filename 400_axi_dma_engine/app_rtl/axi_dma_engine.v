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
本模块: AXI通用DMA引擎

描述:
接收读请求命令, 驱动AXI读通道, 返回输出数据流
接收写请求命令, 接收输入数据流, 驱动AXI写通道

提供4KB边界保护
提供读/写数据fifo
支持写字节数实时统计

MM2S通道支持非对齐传输, 支持输出数据流重对齐
S2MM通道支持非对齐传输, 支持输入数据流重对齐

注意：
不支持回环(WRAP)突发类型
AXI主机的地址位宽固定为32位
突发类型为固定时, 传输基地址必须是对齐的

仅比对了写请求给出的传输次数和写数据实际的传输次数

当在MM2S通道允许非对齐传输时, 每帧所对应的读数据必须能被衔接, 即keep掩码满足:
	[4'b1100(首次传输可能是非对齐的) 4'b1111 ... 4'b1111(必须全1以衔接)]
	[4'b1111(必须全1以衔接) 4'b1111 ... 4'b1111(必须全1以衔接)]
	                             :
								 :
	[4'b1111(必须全1以衔接) 4'b1111 ... 4'b0011(最后1次传输时可以不全1)]

协议:
AXIS MASTER/SLAVE
AXI MASTER

作者: 陈家耀
日期: 2025/01/29
********************************************************************/


module axi_dma_engine #(
	parameter EN_RD_CHN = "true", // 是否启用读通道
	parameter EN_WT_CHN = "true", // 是否启用写通道
	parameter integer DATA_WIDTH = 32, // 传输数据位宽(32 | 64 | 128 | 256)
	parameter integer MAX_BURST_LEN = 32, // 最大的突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter S_CMD_AXIS_COMMON_CLOCK = "true", // 命令AXIS从机与AXI主机是否使用相同的时钟和复位
	parameter M_MM2S_AXIS_COMMON_CLOCK = "true", // 输出数据流AXIS主机与AXI主机是否使用相同的时钟和复位
	parameter S_S2MM_AXIS_COMMON_CLOCK = "true", // 输入数据流AXIS从机与AXI主机是否使用相同的时钟和复位
	parameter EN_WT_BYTES_N_STAT = "false", // 是否启用写字节数实时统计
	parameter EN_MM2S_UNALIGNED_TRANS = "false", // 是否在MM2S通道允许非对齐传输
	parameter EN_S2MM_UNALIGNED_TRANS = "false", // 是否在S2MM通道允许非对齐传输
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 命令AXIS从机的时钟和复位
	input wire s_cmd_axis_aclk,
	input wire s_cmd_axis_aresetn,
	// 输入数据流AXIS从机的时钟和复位
	input wire s_s2mm_axis_aclk,
	input wire s_s2mm_axis_aresetn,
	// 输出数据流AXIS主机的时钟和复位
	input wire m_mm2s_axis_aclk,
	input wire m_mm2s_axis_aresetn,
	// AXI主机的时钟和复位
	input wire m_axi_aclk,
	input wire m_axi_aresetn,
	
	// 命令完成指示
	// 注意: MM2S通道命令完成指示是脉冲信号, 当完成1个"标记为帧尾的命令"时产生!
	output wire mm2s_cmd_done,
	// 注意: S2MM通道命令完成指示是脉冲信号!
	output wire s2mm_cmd_done,
	
	// MM2S命令AXIS从机
	input wire[55:0] s_mm2s_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	input wire s_mm2s_cmd_axis_user, // {固定(1'b1)/递增(1'b0)传输(1bit)}
	input wire s_mm2s_cmd_axis_last, // 帧尾标志
	input wire s_mm2s_cmd_axis_valid,
	output wire s_mm2s_cmd_axis_ready,
	// S2MM命令AXIS从机
	input wire[55:0] s_s2mm_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	input wire s_s2mm_cmd_axis_user, // {固定(1'b1)/递增(1'b0)传输(1bit)}
	input wire s_s2mm_cmd_axis_valid,
	output wire s_s2mm_cmd_axis_ready,
	
	// 输入数据流AXIS从机
	input wire[DATA_WIDTH-1:0] s_s2mm_axis_data,
	input wire[DATA_WIDTH/8-1:0] s_s2mm_axis_keep,
	input wire s_s2mm_axis_last,
	input wire s_s2mm_axis_valid,
	output wire s_s2mm_axis_ready,
	// 输出数据流AXIS主机
	output wire[DATA_WIDTH-1:0] m_mm2s_axis_data,
	output wire[DATA_WIDTH/8-1:0] m_mm2s_axis_keep,
	// 注意: 仅当在MM2S通道不允许非对齐传输时可用!
	output wire[2:0] m_mm2s_axis_user, // {读请求最后1次传输标志(1bit), 
	                                   //     错误类型(2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR)}
	output wire m_mm2s_axis_last,
	output wire m_mm2s_axis_valid,
	input wire m_mm2s_axis_ready,
	
	// AXI主机
	// AR通道
	output wire[31:0] m_axi_araddr,
	// 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
	output wire[1:0] m_axi_arburst,
	output wire[3:0] m_axi_arcache, // const -> 4'b0011
	output wire[7:0] m_axi_arlen,
	output wire[2:0] m_axi_arprot, // const -> 3'b000
	output wire[2:0] m_axi_arsize, // const -> clogb2(DATA_WIDTH/8)
	output wire m_axi_arvalid,
	input wire m_axi_arready,
	// R通道
	input wire[DATA_WIDTH-1:0] m_axi_rdata,
	// 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
	input wire[1:0] m_axi_rresp,
	input wire m_axi_rlast,
	input wire m_axi_rvalid,
	output wire m_axi_rready,
	// AW通道
	output wire[31:0] m_axi_awaddr,
	// 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
	output wire[1:0] m_axi_awburst,
	output wire[3:0] m_axi_awcache, // const -> 4'b0011
	output wire[7:0] m_axi_awlen,
	output wire[2:0] m_axi_awprot, // const -> 3'b000
	output wire[2:0] m_axi_awsize, // const -> clogb2(DATA_WIDTH/8)
	output wire m_axi_awvalid,
	input wire m_axi_awready,
	// B通道
	// 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
	input wire[1:0] m_axi_bresp,
	input wire m_axi_bvalid,
	output wire m_axi_bready, // const -> 1'b1
	// W通道
	output wire[DATA_WIDTH-1:0] m_axi_wdata,
	output wire[DATA_WIDTH/8-1:0] m_axi_wstrb,
	output wire m_axi_wlast,
	output wire m_axi_wvalid,
	input wire m_axi_wready,
	
	// S2MM错误标志
	output wire[1:0] s2mm_err_flag // {写响应错误标志(1bit), 写传输次数不匹配错误标志(1bit)}
);
	
	// 读通道
	generate
		if(EN_RD_CHN == "true")
		begin
			axi_dma_engine_mm2s #(
				.DATA_WIDTH(DATA_WIDTH),
				.MAX_BURST_LEN(MAX_BURST_LEN),
				.S_AXIS_COMMON_CLOCK(S_CMD_AXIS_COMMON_CLOCK),
				.M_AXIS_COMMON_CLOCK(M_MM2S_AXIS_COMMON_CLOCK),
				.EN_UNALIGNED_TRANS(EN_MM2S_UNALIGNED_TRANS),
				.SIM_DELAY(SIM_DELAY)
			)dma_rchn_u(
				.s_axis_aclk(s_cmd_axis_aclk),
				.s_axis_aresetn(s_cmd_axis_aresetn),
				.m_axis_aclk(m_mm2s_axis_aclk),
				.m_axis_aresetn(m_mm2s_axis_aresetn),
				.m_axi_aclk(m_axi_aclk),
				.m_axi_aresetn(m_axi_aresetn),
				
				.cmd_done(mm2s_cmd_done),
				
				.s_cmd_axis_data(s_mm2s_cmd_axis_data),
				.s_cmd_axis_user(s_mm2s_cmd_axis_user),
				.s_cmd_axis_last(s_mm2s_cmd_axis_last),
				.s_cmd_axis_valid(s_mm2s_cmd_axis_valid),
				.s_cmd_axis_ready(s_mm2s_cmd_axis_ready),
				
				.m_mm2s_axis_data(m_mm2s_axis_data),
				.m_mm2s_axis_keep(m_mm2s_axis_keep),
				.m_mm2s_axis_user(m_mm2s_axis_user),
				.m_mm2s_axis_last(m_mm2s_axis_last),
				.m_mm2s_axis_valid(m_mm2s_axis_valid),
				.m_mm2s_axis_ready(m_mm2s_axis_ready),
				
				.m_axi_araddr(m_axi_araddr),
				.m_axi_arburst(m_axi_arburst),
				.m_axi_arcache(m_axi_arcache),
				.m_axi_arlen(m_axi_arlen),
				.m_axi_arprot(m_axi_arprot),
				.m_axi_arsize(m_axi_arsize),
				.m_axi_arvalid(m_axi_arvalid),
				.m_axi_arready(m_axi_arready),
				.m_axi_rdata(m_axi_rdata),
				.m_axi_rresp(m_axi_rresp),
				.m_axi_rlast(m_axi_rlast),
				.m_axi_rvalid(m_axi_rvalid),
				.m_axi_rready(m_axi_rready)
			);
		end
		else
		begin
			assign mm2s_cmd_done = 1'b0;
			
			assign s_mm2s_cmd_axis_ready = 1'b1;
			
			assign m_mm2s_axis_data = {DATA_WIDTH{1'bx}};
			assign m_mm2s_axis_keep = {(DATA_WIDTH/8){1'bx}};
			assign m_mm2s_axis_user = 2'bxx;
			assign m_mm2s_axis_last = 1'bx;
			assign m_mm2s_axis_valid = 1'b0;
			
			assign m_axi_araddr = 32'dx;
			assign m_axi_arburst = 2'bxx;
			assign m_axi_arcache = 4'bxxxx;
			assign m_axi_arlen = 8'dx;
			assign m_axi_arprot = 3'bxxx;
			assign m_axi_arsize = 3'bxxx;
			assign m_axi_arvalid = 1'b0;
			
			assign m_axi_rready = 1'b1;
		end
	endgenerate
	
	// 写通道
	generate
		if(EN_WT_CHN == "true")
		begin
			axi_dma_engine_s2mm #(
				.DATA_WIDTH(DATA_WIDTH),
				.MAX_BURST_LEN(MAX_BURST_LEN),
				.S_CMD_AXIS_COMMON_CLOCK(S_CMD_AXIS_COMMON_CLOCK),
				.S_S2MM_AXIS_COMMON_CLOCK(S_S2MM_AXIS_COMMON_CLOCK),
				.EN_WT_BYTES_N_STAT(EN_WT_BYTES_N_STAT),
				.EN_UNALIGNED_TRANS(EN_S2MM_UNALIGNED_TRANS),
				.SIM_DELAY(SIM_DELAY)
			)dma_wchn_u(
				.s_cmd_axis_aclk(s_cmd_axis_aclk),
				.s_cmd_axis_aresetn(s_cmd_axis_aresetn),
				.s_s2mm_axis_aclk(s_s2mm_axis_aclk),
				.s_s2mm_axis_aresetn(s_s2mm_axis_aresetn),
				.m_axi_aclk(m_axi_aclk),
				.m_axi_aresetn(m_axi_aresetn),
				
				.cmd_done(s2mm_cmd_done),
				
				.s_cmd_axis_data(s_s2mm_cmd_axis_data),
				.s_cmd_axis_user(s_s2mm_cmd_axis_user),
				.s_cmd_axis_valid(s_s2mm_cmd_axis_valid),
				.s_cmd_axis_ready(s_s2mm_cmd_axis_ready),
				
				.s_s2mm_axis_data(s_s2mm_axis_data),
				.s_s2mm_axis_keep(s_s2mm_axis_keep),
				.s_s2mm_axis_last(s_s2mm_axis_last),
				.s_s2mm_axis_valid(s_s2mm_axis_valid),
				.s_s2mm_axis_ready(s_s2mm_axis_ready),
				
				.m_axi_awaddr(m_axi_awaddr),
				.m_axi_awburst(m_axi_awburst),
				.m_axi_awcache(m_axi_awcache),
				.m_axi_awlen(m_axi_awlen),
				.m_axi_awprot(m_axi_awprot),
				.m_axi_awsize(m_axi_awsize),
				.m_axi_awvalid(m_axi_awvalid),
				.m_axi_awready(m_axi_awready),
				.m_axi_wdata(m_axi_wdata),
				.m_axi_wstrb(m_axi_wstrb),
				.m_axi_wlast(m_axi_wlast),
				.m_axi_wvalid(m_axi_wvalid),
				.m_axi_wready(m_axi_wready),
				.m_axi_bresp(m_axi_bresp),
				.m_axi_bvalid(m_axi_bvalid),
				.m_axi_bready(m_axi_bready),
				
				.err_flag(s2mm_err_flag)
			);
		end
		else
		begin
			assign s2mm_cmd_done = 1'b0;
			
			assign s_s2mm_cmd_axis_ready = 1'b1;
			
			assign s_s2mm_axis_ready = 1'b1;
			
			assign m_axi_awaddr = 32'dx;
			assign m_axi_awburst = 2'bxx;
			assign m_axi_awcache = 4'bxxxx;
			assign m_axi_awlen = 8'dx;
			assign m_axi_awprot = 3'bxxx;
			assign m_axi_awsize = 3'bxxx;
			assign m_axi_awvalid = 1'b0;
			
			assign m_axi_bready = 1'b1;
			
			assign m_axi_wdata = {DATA_WIDTH{1'bx}};
			assign m_axi_wstrb = {(DATA_WIDTH/8){1'bx}};
			assign m_axi_wlast = 1'bx;
			assign m_axi_wvalid = 1'b0;
		end
	endgenerate
	
endmodule
