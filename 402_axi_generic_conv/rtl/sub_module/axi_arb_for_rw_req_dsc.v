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
本模块: 读/写请求描述子输入AXI主机读通道仲裁

描述:
对读/写请求描述子DMA的AXI主机读通道进行仲裁, 合并成1个AXI主机读通道

注意：
无

协议:
AXI MASTER/SLAVE(READ ONLY)

作者: 陈家耀
日期: 2024/11/10
********************************************************************/


module axi_arb_for_rw_req_dsc #(
	parameter integer arb_msg_fifo_depth = 4, // 仲裁信息fifo深度
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 仲裁输入#0
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
	
	// 仲裁输入#1
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
	
	// 仲裁输出
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
    
	/** 仲裁信息fifo **/
	// fifo写端口
	wire arb_msg_fifo_wen;
	wire[1:0] arb_msg_fifo_din; // {选择通道#1, 选择通道#0}
	wire arb_msg_fifo_full_n;
	// fifo读端口
	wire arb_msg_fifo_ren;
	wire[1:0] arb_msg_fifo_dout; // {选择通道#1, 选择通道#0}
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
	
	/** 读地址通道仲裁 **/
	wire[1:0] rd_access_req; // 读请求({通道#1, 通道#0})
	wire[1:0] rd_access_grant; // 读许可({通道#1, 通道#0})
	reg ar_valid; // 读地址通道的valid信号
	reg[1:0] ar_ready; // 读地址通道的ready信号({通道#1, 通道#0})
	reg[31:0] araddr_latched; // 锁存的读地址
	reg[7:0] arlen_latched; // 锁存的(读突发长度 - 1)
	
	assign {s_axi_wt_req_dsc_arready, s_axi_rd_req_dsc_arready} = ar_ready;
	
	assign m_axi_rw_req_dsc_araddr = araddr_latched;
	assign m_axi_rw_req_dsc_arburst = 2'b01;
	assign m_axi_rw_req_dsc_arlen = arlen_latched;
	assign m_axi_rw_req_dsc_arsize = 3'b011;
	assign m_axi_rw_req_dsc_arvalid = ar_valid;
	
	assign arb_msg_fifo_wen = (~ar_valid) & (s_axi_wt_req_dsc_arvalid | s_axi_rd_req_dsc_arvalid);
	assign arb_msg_fifo_din = rd_access_grant;
	
	assign rd_access_req = {2{(~ar_valid) & arb_msg_fifo_full_n}} & {s_axi_wt_req_dsc_arvalid, s_axi_rd_req_dsc_arvalid};
	
	// 读地址通道的valid信号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			ar_valid <= 1'b0;
		else
			ar_valid <= # simulation_delay ar_valid ? 
				(~m_axi_rw_req_dsc_arready):(arb_msg_fifo_full_n & (s_axi_wt_req_dsc_arvalid | s_axi_rd_req_dsc_arvalid));
	end
	
	// 读地址通道的ready信号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			ar_ready <= 2'b00;
		else
			ar_ready <= # simulation_delay rd_access_grant;
	end
	
	// 锁存的读地址
	always @(posedge clk)
	begin
		if((~ar_valid) & arb_msg_fifo_full_n & (s_axi_wt_req_dsc_arvalid | s_axi_rd_req_dsc_arvalid))
			araddr_latched <= # simulation_delay rd_access_grant[0] ? s_axi_rd_req_dsc_araddr:s_axi_wt_req_dsc_araddr;
	end
	
	// 锁存的(读突发长度 - 1)
	always @(posedge clk)
	begin
		if((~ar_valid) & arb_msg_fifo_full_n & (s_axi_wt_req_dsc_arvalid | s_axi_rd_req_dsc_arvalid))
			arlen_latched <= # simulation_delay rd_access_grant[0] ? s_axi_rd_req_dsc_arlen:s_axi_wt_req_dsc_arlen;
	end
	
	// Round-Robin仲裁器
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
	
	/** 读数据选择 **/
	assign s_axi_rd_req_dsc_rdata = m_axi_rw_req_dsc_rdata;
	assign s_axi_rd_req_dsc_rresp = m_axi_rw_req_dsc_rresp;
	assign s_axi_rd_req_dsc_rlast = m_axi_rw_req_dsc_rlast;
	// 握手条件: arb_msg_fifo_empty_n & arb_msg_fifo_dout[0] & s_axi_rd_req_dsc_rready & m_axi_rw_req_dsc_rvalid
	assign s_axi_rd_req_dsc_rvalid = arb_msg_fifo_empty_n & arb_msg_fifo_dout[0] & m_axi_rw_req_dsc_rvalid;
	
	assign s_axi_wt_req_dsc_rdata = m_axi_rw_req_dsc_rdata;
	assign s_axi_wt_req_dsc_rresp = m_axi_rw_req_dsc_rresp;
	assign s_axi_wt_req_dsc_rlast = m_axi_rw_req_dsc_rlast;
	// 握手条件: arb_msg_fifo_empty_n & (~arb_msg_fifo_dout[0]) & s_axi_wt_req_dsc_rready & m_axi_rw_req_dsc_rvalid
	assign s_axi_wt_req_dsc_rvalid = arb_msg_fifo_empty_n & (~arb_msg_fifo_dout[0]) & m_axi_rw_req_dsc_rvalid;
	
	// 握手条件: arb_msg_fifo_empty_n & (arb_msg_fifo_dout[0] ? s_axi_rd_req_dsc_rready:s_axi_wt_req_dsc_rready) & 
	//     m_axi_rw_req_dsc_rvalid
	assign m_axi_rw_req_dsc_rready = arb_msg_fifo_empty_n & 
		(arb_msg_fifo_dout[0] ? s_axi_rd_req_dsc_rready:s_axi_wt_req_dsc_rready);
	
	// 握手条件: arb_msg_fifo_empty_n & (arb_msg_fifo_dout[0] ? s_axi_rd_req_dsc_rready:s_axi_wt_req_dsc_rready) & 
	//     m_axi_rw_req_dsc_rvalid & m_axi_rw_req_dsc_rlast
	assign arb_msg_fifo_ren = (arb_msg_fifo_dout[0] ? s_axi_rd_req_dsc_rready:s_axi_wt_req_dsc_rready) & 
		m_axi_rw_req_dsc_rvalid & m_axi_rw_req_dsc_rlast;
	
endmodule
