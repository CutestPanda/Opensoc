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
本模块: 小胖达RISC-V调试机制

描述: 
(JTAG从接口) -> DTM -> (DMI: APB接口) -> DM

注意：
无

协议:
JTAG SLAVE
MEM READ/WRITE

作者: 陈家耀
日期: 2026/01/31
********************************************************************/


module panda_risc_v_jtag_debug #(
	parameter integer PROGBUF_SIZE = 2, // Program Buffer的大小(以双字计, 必须在范围[0, 16]内)
	parameter DATA0_ADDR = 32'hFFFF_F800, // data0寄存器在存储映射中的地址
	parameter PROGBUF0_ADDR = 32'hFFFF_F900, // progbuf0寄存器在存储映射中的地址
	parameter HART_ACMD_CTRT_ADDR = 32'hFFFF_FA00, // HART抽象命令运行控制在存储映射中的地址
    parameter real SIM_DELAY = 1 // 仿真延时
)(
    // JTAG从机
	input wire jtag_slave_tck,
	input wire jtag_slave_trst_n,
	input wire jtag_slave_tms,
	input wire jtag_slave_tdi,
	output wire jtag_slave_tdo,
	
	// DM时钟和复位
	input wire dm_aclk,
	input wire dm_aresetn,
	
	// 复位控制
	input wire sys_reset_fns, // 系统复位完成
	output wire sw_reset, // 软件服务请求
	
	// HART暂停请求
	output wire dbg_halt_req, // 来自调试器的暂停请求
	output wire dbg_halt_on_reset_req, // 来自调试器的复位释放后暂停请求
	
	// HART写DM内容(存储器从接口)
	input wire[3:0] hart_access_wen,
	input wire[29:0] hart_access_waddr,
	input wire[31:0] hart_access_din,
	// HART读DM内容(存储器从接口)
	input wire hart_access_ren,
	input wire[29:0] hart_access_raddr,
	output wire[31:0] hart_access_dout
);
	
	/** DTM **/
	// DMI
    wire[8:0] dmi_paddr;
    wire dmi_psel;
    wire dmi_penable;
    wire dmi_pwrite;
    wire[31:0] dmi_pwdata;
    wire dmi_pready;
    wire[31:0] dmi_prdata;
    wire dmi_pslverr;
	
    jtag_dtm #(
		.JTAG_VERSION(4'h1),
		.DTMCS_IDLE_HINT(3'd5),
		.ABITS(7),
		.SYN_STAGE(2),
		.SIM_DELAY(SIM_DELAY)
	)jtag_dtm_u(
		.tck(jtag_slave_tck),
		.trst_n(jtag_slave_trst_n),
		.tms(jtag_slave_tms),
		.tdi(jtag_slave_tdi),
		.tdo(jtag_slave_tdo),
		.tdo_oen(),
		
		.m_apb_aclk(dm_aclk),
		.m_apb_aresetn(dm_aresetn),
		
		.dmihardreset_req(),
		
		.m_paddr(dmi_paddr),
		.m_psel(dmi_psel),
		.m_penable(dmi_penable),
		.m_pwrite(dmi_pwrite),
		.m_pwdata(dmi_pwdata),
		.m_pready(dmi_pready),
		.m_prdata(dmi_prdata),
		.m_pslverr(dmi_pslverr)
	);
	
	/** DM **/
	wire dbg_sys_reset_req;
	wire dbg_hart_reset_req;
	
	assign sw_reset = dbg_sys_reset_req | dbg_hart_reset_req;
	
	jtag_dm #(
		.ABITS(7),
		.HARTS_N(1),
		.SCRATCH_N(2),
		.SBUS_SUPPORTED("false"),
		.NEXT_DM_ADDR(32'h0000_0000),
		.PROGBUF_SIZE(PROGBUF_SIZE),
		.DATA0_ADDR(DATA0_ADDR),
		.PROGBUF0_ADDR(PROGBUF0_ADDR),
		.HART_ACMD_CTRT_ADDR(HART_ACMD_CTRT_ADDR),
		.SIM_DELAY(SIM_DELAY)
	)jtag_dm_u(
		.clk(dm_aclk),
		.rst_n(dm_aresetn),
		
		.s_dmi_paddr(dmi_paddr),
		.s_dmi_psel(dmi_psel),
		.s_dmi_penable(dmi_penable),
		.s_dmi_pwrite(dmi_pwrite),
		.s_dmi_pwdata(dmi_pwdata),
		.s_dmi_pready(dmi_pready),
		.s_dmi_prdata(dmi_prdata),
		.s_dmi_pslverr(dmi_pslverr),
		
		.sys_reset_req(dbg_sys_reset_req),
		.sys_reset_fns(sys_reset_fns),
		.hart_reset_req(dbg_hart_reset_req),
		.hart_reset_fns(sys_reset_fns),
		
		.hart_req_halt(dbg_halt_req),
		.hart_req_halt_on_reset(dbg_halt_on_reset_req),
		
		.hart_access_wen(hart_access_wen),
		.hart_access_waddr(hart_access_waddr),
		.hart_access_din(hart_access_din),
		.hart_access_ren(hart_access_ren),
		.hart_access_raddr(hart_access_raddr),
		.hart_access_dout(hart_access_dout),
		
		.m_icb_cmd_sbus_addr(),
		.m_icb_cmd_sbus_read(),
		.m_icb_cmd_sbus_wdata(),
		.m_icb_cmd_sbus_wmask(),
		.m_icb_cmd_sbus_valid(),
		.m_icb_cmd_sbus_ready(1'b1),
		
		.m_icb_rsp_sbus_rdata(32'dx),
		.m_icb_rsp_sbus_err(1'b1),
		.m_icb_rsp_sbus_valid(1'b1),
		.m_icb_rsp_sbus_ready()
	);
	
endmodule
