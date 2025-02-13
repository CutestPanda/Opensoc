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
本模块: APB时钟转换模块

描述:
将APB主机从1个时钟域转换到另外1个时钟域

跨时钟域握手过程: 
(1)当APB从机传输启动且从机端观察到应答(ack_at_slave)无效时, 从机端请求信号(req_at_slave)有效
(2)当主机端观察到请求(req_at_master)有效且应答(ack_at_master)无效时, APB主机的m_psel和m_penable相继有效
(3)当APB主机传输完成时, 主机端应答信号(ack_at_master)有效, 而APB主机的m_psel和m_penable无效
(4)当从机端观察到应答(ack_at_slave)有效时, 从机端请求信号(req_at_slave)无效
(5)当主机端观察到请求(req_at_master)无效时, 主机端应答信号(ack_at_master)无效

n级同步器: 
      从机端          主机端
  req_at_slave --> req_at_master
  ack_at_slave <-- ack_at_master

注意：
无

协议:
APB MASTER/SLAVE

作者: 陈家耀
日期: 2025/02/04
********************************************************************/


module apb_clock_convert #(
	parameter integer SYN_STAGE = 2, // 同步器级数(必须>=1)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// APB从机的时钟和复位
	input wire s_apb_aclk,
	input wire s_apb_aresetn,
	// APB主机的时钟和复位
	input wire m_apb_aclk,
	input wire m_apb_aresetn,
	
	// APB从机
    input wire[31:0] s_paddr,
    input wire s_psel,
    input wire s_penable,
    input wire s_pwrite,
    input wire[31:0] s_pwdata,
    output wire s_pready,
    output wire[31:0] s_prdata,
    output wire s_pslverr,
	
	// APB主机
    output wire[31:0] m_paddr,
    output wire m_psel,
    output wire m_penable,
    output wire m_pwrite,
    output wire[31:0] m_pwdata,
    input wire m_pready,
    input wire[31:0] m_prdata,
    input wire m_pslverr
);
	
	/** 内部配置 **/
	localparam LAUNCH_ONCE_PSEL_VLD = "true"; // 是否在s_psel有效时启动传输
	
	/** 跨时钟域握手 **/
	reg req_at_slave; // 从机端请求信号
	wire req_at_master; // 主机端请求信号
	wire ack_at_slave; // 从机端应答信号
	reg ack_at_master; // 主机端应答信号
	
	// 跨时钟域: req_at_slave -> req_syn_u.dffs[0]
	single_bit_syn #(
		.SYN_STAGE(SYN_STAGE),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)req_syn_u(
		.clk(m_apb_aclk),
		.rst_n(m_apb_aresetn),
		
		.single_bit_in(req_at_slave),
		.single_bit_out(req_at_master)
	);
	
	// 跨时钟域: ack_at_master -> ack_syn_u.dffs[0]
	single_bit_syn #(
		.SYN_STAGE(SYN_STAGE),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)ack_syn_u(
		.clk(s_apb_aclk),
		.rst_n(s_apb_aresetn),
		
		.single_bit_in(ack_at_master),
		.single_bit_out(ack_at_slave)
	);
	
	/** APB从机 **/
	reg[31:0] paddr_latched; // 锁存的传输地址
	reg pwrite_latched; // 锁存的读写类型
	reg[31:0] pwdata_latched; // 锁存的写数据
	
	assign s_pready = req_at_slave & ack_at_slave;
	
	// 从机端请求信号
	always @(posedge s_apb_aclk or negedge s_apb_aresetn)
	begin
		if(~s_apb_aresetn)
			req_at_slave <= 1'b0;
		else if(req_at_slave ? ack_at_slave:((~ack_at_slave) & s_psel & ((LAUNCH_ONCE_PSEL_VLD == "true") | s_penable)))
			req_at_slave <= # SIM_DELAY ~req_at_slave;
	end
	
	// 锁存的传输地址, 锁存的读写类型, 锁存的写数据
	always @(posedge s_apb_aclk)
	begin
		if(s_psel)
			{paddr_latched, pwrite_latched, pwdata_latched} <= # SIM_DELAY {s_paddr, s_pwrite, s_pwdata};
	end
	
	/** APB主机 **/
	reg[31:0] prdata_latched; // 锁存的读数据
	reg pslverr_latched; // 锁存的从机错误类型
	reg m_psel_r; // APB主机的psel
	reg m_penable_r; // APB主机的penable
	
	// 跨时钟域: prdata_latched[*] -> ...
	assign s_prdata = prdata_latched;
	// 跨时钟域: pslverr_latched -> ...
	assign s_pslverr = pslverr_latched;
	
	// 跨时钟域: paddr_latched[*] -> ...
	assign m_paddr = paddr_latched;
	assign m_psel = m_psel_r;
	assign m_penable = m_penable_r;
	// 跨时钟域: pwrite_latched -> ...
	assign m_pwrite = pwrite_latched;
	// 跨时钟域: pwdata_latched[*] -> ...
	assign m_pwdata = pwdata_latched;
	
	// 主机端应答信号
	always @(posedge m_apb_aclk or negedge m_apb_aresetn)
	begin
		if(~m_apb_aresetn)
			ack_at_master <= 1'b0;
		else if(ack_at_master ? (~req_at_master):(m_psel & m_penable & m_pready))
			ack_at_master <= # SIM_DELAY ~ack_at_master;
	end
	
	// 锁存的读数据, 锁存的从机错误类型
	always @(posedge m_apb_aclk)
	begin
		if(m_psel & m_penable & m_pready)
			{prdata_latched, pslverr_latched} <= # SIM_DELAY {m_prdata, m_pslverr};
	end
	
	// APB主机的psel
	always @(posedge m_apb_aclk or negedge m_apb_aresetn)
	begin
		if(~m_apb_aresetn)
			m_psel_r <= 1'b0;
		else if(m_psel_r ? (m_penable & m_pready):(req_at_master & (~ack_at_master)))
			m_psel_r <= # SIM_DELAY ~m_psel_r;
	end
	
	// APB主机的penable
	always @(posedge m_apb_aclk or negedge m_apb_aresetn)
	begin
		if(~m_apb_aresetn)
			m_penable_r <= 1'b0;
		else if(m_penable_r ? m_pready:m_psel)
			m_penable_r <= # SIM_DELAY ~m_penable_r;
	end
	
endmodule
