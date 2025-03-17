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
本模块: 调试传输控制模块

描述:
实现JTAG接口到如下DTM寄存器的访问: 
	地址 | 名称
---------------------
    0x01 | IDCODE
	0x10 | DTMCS
	0x11 |  DMI
	其余 | BYPASS

DMI采用APB协议

参见《The RISC-V Debug Specification》(Version 1.0.0-rc4, Revised 2024-12-05: Frozen)

注意：
DMI强制复位请求(dmihardreset_req)位于JTAG时钟域
JTAG数据输出使能(tdo_oen)可以悬空不使用

协议:
JTAG SLAVE
APB MASTER

作者: 陈家耀
日期: 2025/02/05
********************************************************************/


module jtag_dtm #(
	parameter JTAG_VERSION  = 4'h1, // IDCODE寄存器下Version域的值
	parameter DTMCS_IDLE_HINT = 3'd5, // 停留在Run-Test/Idle状态的周期数
	parameter integer ABITS = 7, // DMI地址位宽(必须在范围[7, 32]内)
	parameter integer SYN_STAGE = 2, // 同步器级数(必须>=1)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// JTAG从机
	input wire tck,
	input wire trst_n,
	input wire tms,
	input wire tdi,
	output wire tdo,
	output wire tdo_oen,
	
	// APB主机的时钟和复位
	input wire m_apb_aclk,
	input wire m_apb_aresetn,
	
	// DMI强制复位请求
	output wire dmihardreset_req,
	
	// APB主机
    output wire[ABITS+1:0] m_paddr,
    output wire m_psel,
    output wire m_penable,
    output wire m_pwrite,
    output wire[31:0] m_pwdata,
    input wire m_pready,
    input wire[31:0] m_prdata,
    input wire m_pslverr
);
	
	/** APB时钟转换模块 **/
	// APB从机
    wire[31:0] s_clk_cvt_paddr;
    wire s_clk_cvt_psel;
    wire s_clk_cvt_penable;
    wire s_clk_cvt_pwrite;
    wire[31:0] s_clk_cvt_pwdata;
    wire s_clk_cvt_pready;
    wire[31:0] s_clk_cvt_prdata;
    wire s_clk_cvt_pslverr;
	// APB主机
    wire[31:0] m_clk_cvt_paddr;
    wire m_clk_cvt_psel;
    wire m_clk_cvt_penable;
    wire m_clk_cvt_pwrite;
    wire[31:0] m_clk_cvt_pwdata;
    wire m_clk_cvt_pready;
    wire[31:0] m_clk_cvt_prdata;
    wire m_clk_cvt_pslverr;
	
	assign m_paddr = m_clk_cvt_paddr[ABITS+1:0];
	assign m_psel = m_clk_cvt_psel;
	assign m_penable = m_clk_cvt_penable;
	assign m_pwrite = m_clk_cvt_pwrite;
	assign m_pwdata = m_clk_cvt_pwdata;
	assign m_clk_cvt_pready = m_pready;
	assign m_clk_cvt_prdata = m_prdata;
	assign m_clk_cvt_pslverr = m_pslverr;
	
	apb_clock_convert #(
		.SYN_STAGE(SYN_STAGE),
		.SIM_DELAY(SIM_DELAY)
	)apb_clock_convert_u(
		.s_apb_aclk(tck),
		.s_apb_aresetn(trst_n),
		
		.m_apb_aclk(m_apb_aclk),
		.m_apb_aresetn(m_apb_aresetn),
		
		.s_paddr(s_clk_cvt_paddr),
		.s_psel(s_clk_cvt_psel),
		.s_penable(s_clk_cvt_penable),
		.s_pwrite(s_clk_cvt_pwrite),
		.s_pwdata(s_clk_cvt_pwdata),
		.s_pready(s_clk_cvt_pready),
		.s_prdata(s_clk_cvt_prdata),
		.s_pslverr(s_clk_cvt_pslverr),
		
		.m_paddr(m_clk_cvt_paddr),
		.m_psel(m_clk_cvt_psel),
		.m_penable(m_clk_cvt_penable),
		.m_pwrite(m_clk_cvt_pwrite),
		.m_pwdata(m_clk_cvt_pwdata),
		.m_pready(m_clk_cvt_pready),
		.m_prdata(m_clk_cvt_prdata),
		.m_pslverr(m_clk_cvt_pslverr)
	);
	
	/** 调试传输控制模块(核心) **/
	// APB主机
    wire[ABITS+1:0] m_dmi_paddr;
    wire m_dmi_psel;
    wire m_dmi_penable;
    wire m_dmi_pwrite;
    wire[31:0] m_dmi_pwdata;
    wire m_dmi_pready;
    wire[31:0] m_dmi_prdata;
    wire m_dmi_pslverr;
	
	assign s_clk_cvt_paddr = 32'h0000_0000 | m_dmi_paddr;
	assign s_clk_cvt_psel = m_dmi_psel;
	assign s_clk_cvt_penable = m_dmi_penable;
	assign s_clk_cvt_pwrite = m_dmi_pwrite;
	assign s_clk_cvt_pwdata = m_dmi_pwdata;
	assign m_dmi_pready = s_clk_cvt_pready;
	assign m_dmi_prdata = s_clk_cvt_prdata;
	assign m_dmi_pslverr = s_clk_cvt_pslverr;
	
	jtag_dtm_core #(
		.JTAG_VERSION(JTAG_VERSION),
		.DTMCS_IDLE_HINT(DTMCS_IDLE_HINT),
		.ABITS(ABITS),
		.SIM_DELAY(SIM_DELAY)
	)jtag_dtm_core_u(
		.tck(tck),
		.trst_n(trst_n),
		.tms(tms),
		.tdi(tdi),
		.tdo(tdo),
		.tdo_oen(tdo_oen),
		
		.dmihardreset_req(dmihardreset_req),
		
		.m_paddr(m_dmi_paddr),
		.m_psel(m_dmi_psel),
		.m_penable(m_dmi_penable),
		.m_pwrite(m_dmi_pwrite),
		.m_pwdata(m_dmi_pwdata),
		.m_pready(m_dmi_pready),
		.m_prdata(m_dmi_prdata),
		.m_pslverr(m_dmi_pslverr)
	);
	
endmodule
