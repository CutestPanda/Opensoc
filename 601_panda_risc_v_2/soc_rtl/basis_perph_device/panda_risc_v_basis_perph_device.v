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
本模块: 小胖达RISC-V基础外设系统设备

描述: 
包括AXI-APB桥、APB-UART

存储映射 -> 
-------------------------------------------------
|  外设名  |        地址区间         | 区间长度 |
-------------------------------------------------
|   GPIO0  | 0x4000_0000~0x4000_0FFF |    4KB   |
-------------------------------------------------
|  TIMER0  | 0x4000_2000~0x4000_2FFF |    4KB   |
-------------------------------------------------
|   UART0  | 0x4000_3000~0x4000_3FFF |    4KB   |
-------------------------------------------------
|   PLIC   | 0xF000_0000~0xF03F_FFFF |    4MB   |
-------------------------------------------------
|  CLINT   | 0xF400_0000~0xF7FF_FFFF |   64MB   |
-------------------------------------------------

注意：
无

协议:
AXI-Lite SLAVE
UART MASTER
GPIO MASTER

作者: 陈家耀
日期: 2026/02/03
********************************************************************/


module panda_risc_v_basis_perph_device #(
	parameter integer RTC_PSC_R = 75 * 100, // RTC预分频系数
	parameter integer CLK_FREQUENCY_MHZ = 50, // 时钟频率(以MHz计)
    parameter real SIM_DELAY = 1 // 仿真延时
)(
	// AXI从机时钟和复位
    input wire s_axi_aclk,
    input wire s_axi_aresetn,
	
	// (数据总线)外设AXI主机
	// [AR通道]
	input wire[31:0] s_axi_perph_araddr,
	input wire[1:0] s_axi_perph_arburst,
	input wire[7:0] s_axi_perph_arlen,
	input wire[2:0] s_axi_perph_arsize,
	input wire s_axi_perph_arvalid,
	output wire s_axi_perph_arready,
	// [R通道]
	output wire[31:0] s_axi_perph_rdata,
	output wire[1:0] s_axi_perph_rresp,
	output wire s_axi_perph_rlast,
	output wire s_axi_perph_rvalid,
	input wire s_axi_perph_rready,
	// [AW通道]
	input wire[31:0] s_axi_perph_awaddr,
	input wire[1:0] s_axi_perph_awburst,
	input wire[7:0] s_axi_perph_awlen,
	input wire[2:0] s_axi_perph_awsize,
	input wire s_axi_perph_awvalid,
	output wire s_axi_perph_awready,
	// [B通道]
	output wire[1:0] s_axi_perph_bresp,
	output wire s_axi_perph_bvalid,
	input wire s_axi_perph_bready,
	// [W通道]
	input wire[31:0] s_axi_perph_wdata,
	input wire[3:0] s_axi_perph_wstrb,
	input wire s_axi_perph_wlast,
	input wire s_axi_perph_wvalid,
	output wire s_axi_perph_wready,
	
	// 实时时钟计数使能
	input wire rtc_en,
	
	// 外部中断请求向量
	// 注意: 中断请求保持有效直到中断清零, 中断号从4开始
	input wire[59:0] ext_itr_req_vec,
	
	// 通给CPU的中断请求
	output wire sw_itr_req, // 软件中断请求
	output wire tmr_itr_req, // 计时器中断请求
	output wire ext_itr_req, // 外部中断请求
	
	// UART0
    output wire uart0_tx,
    input wire uart0_rx,
	
	// GPIO0
	output wire[2:0] gpio0_o,
    output wire[2:0] gpio0_t, // 0->输出, 1->输入
    input wire[2:0] gpio0_i,
	
	// PWM
	output wire pwm_o
);
	
	/** AXI-APB桥 **/
	// APB主机#0
    wire[31:0] m0_apb_paddr;
    wire m0_apb_penable;
    wire m0_apb_pwrite;
    wire[2:0] m0_apb_pprot;
    wire m0_apb_psel;
    wire[3:0] m0_apb_pstrb;
    wire[31:0] m0_apb_pwdata;
    wire m0_apb_pready;
    wire m0_apb_pslverr;
    wire[31:0] m0_apb_prdata;
	// APB主机#2
    wire[31:0] m2_apb_paddr;
    wire m2_apb_penable;
    wire m2_apb_pwrite;
    wire[2:0] m2_apb_pprot;
    wire m2_apb_psel;
    wire[3:0] m2_apb_pstrb;
    wire[31:0] m2_apb_pwdata;
    wire m2_apb_pready;
    wire m2_apb_pslverr;
    wire[31:0] m2_apb_prdata;
	// APB主机#3
    wire[31:0] m3_apb_paddr;
    wire m3_apb_penable;
    wire m3_apb_pwrite;
    wire[2:0] m3_apb_pprot;
    wire m3_apb_psel;
    wire[3:0] m3_apb_pstrb;
    wire[31:0] m3_apb_pwdata;
    wire m3_apb_pready;
    wire m3_apb_pslverr;
    wire[31:0] m3_apb_prdata;
	// APB主机#4
    wire[31:0] m4_apb_paddr;
    wire m4_apb_penable;
    wire m4_apb_pwrite;
    wire[2:0] m4_apb_pprot;
    wire m4_apb_psel;
    wire[3:0] m4_apb_pstrb;
    wire[31:0] m4_apb_pwdata;
    wire m4_apb_pready;
    wire m4_apb_pslverr;
    wire[31:0] m4_apb_prdata;
	// APB主机#5
    wire[31:0] m5_apb_paddr;
    wire m5_apb_penable;
    wire m5_apb_pwrite;
    wire[2:0] m5_apb_pprot;
    wire m5_apb_psel;
    wire[3:0] m5_apb_pstrb;
    wire[31:0] m5_apb_pwdata;
    wire m5_apb_pready;
    wire m5_apb_pslverr;
    wire[31:0] m5_apb_prdata;
	
	axi_apb_bridge_wrapper #(
		.apb_slave_n(6),
		
		.apb_s0_baseaddr(32'h4000_0000),
		.apb_s0_range(4 * 1024),
		.apb_s1_baseaddr(32'h4000_1000),
		.apb_s1_range(4 * 1024),
		.apb_s2_baseaddr(32'h4000_2000),
		.apb_s2_range(4 * 1024),
		.apb_s3_baseaddr(32'h4000_3000),
		.apb_s3_range(4 * 1024),
		.apb_s4_baseaddr(32'hF000_0000),
		.apb_s4_range(4 * 1024 * 1024),
		.apb_s5_baseaddr(32'hF400_0000),
		.apb_s5_range(64 * 1024 * 1024),
		
		.simulation_delay(SIM_DELAY)
	)axi_apb_bridge_wrapper_u(
		.clk(s_axi_aclk),
		.rst_n(s_axi_aresetn),
		
		.s_axi_araddr(s_axi_perph_araddr),
		.s_axi_arprot(3'bxxx),
		.s_axi_arvalid(s_axi_perph_arvalid),
		.s_axi_arready(s_axi_perph_arready),
		.s_axi_awaddr(s_axi_perph_awaddr),
		.s_axi_awprot(3'bxxx),
		.s_axi_awvalid(s_axi_perph_awvalid),
		.s_axi_awready(s_axi_perph_awready),
		.s_axi_bresp(s_axi_perph_bresp),
		.s_axi_bvalid(s_axi_perph_bvalid),
		.s_axi_bready(s_axi_perph_bready),
		.s_axi_rdata(s_axi_perph_rdata),
		.s_axi_rresp(s_axi_perph_rresp),
		.s_axi_rvalid(s_axi_perph_rvalid),
		.s_axi_rready(s_axi_perph_rready),
		.s_axi_wdata(s_axi_perph_wdata),
		.s_axi_wstrb(s_axi_perph_wstrb),
		.s_axi_wvalid(s_axi_perph_wvalid),
		.s_axi_wready(s_axi_perph_wready),
		
		.m0_apb_paddr(m0_apb_paddr),
		.m0_apb_penable(m0_apb_penable),
		.m0_apb_pwrite(m0_apb_pwrite),
		.m0_apb_pprot(m0_apb_pprot),
		.m0_apb_psel(m0_apb_psel),
		.m0_apb_pstrb(m0_apb_pstrb),
		.m0_apb_pwdata(m0_apb_pwdata),
		.m0_apb_pready(m0_apb_pready),
		.m0_apb_pslverr(m0_apb_pslverr),
		.m0_apb_prdata(m0_apb_prdata),
		
		.m1_apb_paddr(),
		.m1_apb_penable(),
		.m1_apb_pwrite(),
		.m1_apb_pprot(),
		.m1_apb_psel(),
		.m1_apb_pstrb(),
		.m1_apb_pwdata(),
		.m1_apb_pready(1'b1),
		.m1_apb_pslverr(1'b1),
		.m1_apb_prdata(32'dx),
		
		.m2_apb_paddr(m2_apb_paddr),
		.m2_apb_penable(m2_apb_penable),
		.m2_apb_pwrite(m2_apb_pwrite),
		.m2_apb_pprot(m2_apb_pprot),
		.m2_apb_psel(m2_apb_psel),
		.m2_apb_pstrb(m2_apb_pstrb),
		.m2_apb_pwdata(m2_apb_pwdata),
		.m2_apb_pready(m2_apb_pready),
		.m2_apb_pslverr(m2_apb_pslverr),
		.m2_apb_prdata(m2_apb_prdata),
		
		.m3_apb_paddr(m3_apb_paddr),
		.m3_apb_penable(m3_apb_penable),
		.m3_apb_pwrite(m3_apb_pwrite),
		.m3_apb_pprot(m3_apb_pprot),
		.m3_apb_psel(m3_apb_psel),
		.m3_apb_pstrb(m3_apb_pstrb),
		.m3_apb_pwdata(m3_apb_pwdata),
		.m3_apb_pready(m3_apb_pready),
		.m3_apb_pslverr(m3_apb_pslverr),
		.m3_apb_prdata(m3_apb_prdata),
		
		.m4_apb_paddr(m4_apb_paddr),
		.m4_apb_penable(m4_apb_penable),
		.m4_apb_pwrite(m4_apb_pwrite),
		.m4_apb_pprot(m4_apb_pprot),
		.m4_apb_psel(m4_apb_psel),
		.m4_apb_pstrb(m4_apb_pstrb),
		.m4_apb_pwdata(m4_apb_pwdata),
		.m4_apb_pready(m4_apb_pready),
		.m4_apb_pslverr(m4_apb_pslverr),
		.m4_apb_prdata(m4_apb_prdata),
		
		.m5_apb_paddr(m5_apb_paddr),
		.m5_apb_penable(m5_apb_penable),
		.m5_apb_pwrite(m5_apb_pwrite),
		.m5_apb_pprot(m5_apb_pprot),
		.m5_apb_psel(m5_apb_psel),
		.m5_apb_pstrb(m5_apb_pstrb),
		.m5_apb_pwdata(m5_apb_pwdata),
		.m5_apb_pready(m5_apb_pready),
		.m5_apb_pslverr(m5_apb_pslverr),
		.m5_apb_prdata(m5_apb_prdata)
	);
	
	/** GPIO0 **/
	wire gpio0_itr; // 中断请求
	
	apb_gpio #(
		.gpio_width(3),
		.gpio_dire("inout"),
		.default_output_value(32'hffff_ffff),
		.default_tri_value(32'hffff_ffff),
		.en_itr("true"),
		.itr_edge("neg"),
		.simulation_delay(SIM_DELAY)
	)apb_gpio_u0(
		.clk(s_axi_aclk),
		.resetn(s_axi_aresetn),
		
		.paddr(m0_apb_paddr),
		.psel(m0_apb_psel),
		.penable(m0_apb_penable),
		.pwrite(m0_apb_pwrite),
		.pwdata(m0_apb_pwdata),
		.pready_out(m0_apb_pready),
		.prdata_out(m0_apb_prdata),
		.pslverr_out(m0_apb_pslverr),
		
		.gpio_o(gpio0_o),
		.gpio_t(gpio0_t),
		.gpio_i(gpio0_i),
		
		.gpio_itr(gpio0_itr)
	);
	
	/** TIMER0 **/
	wire timer0_itr; // 中断请求
	
	apb_timer #(
		.timer_width(32),
		.channel_n(1),
		.simulation_delay(SIM_DELAY)
	)apb_timer_u0(
		.clk(s_axi_aclk),
		.resetn(s_axi_aresetn),
		
		.paddr(m2_apb_paddr),
		.psel(m2_apb_psel),
		.penable(m2_apb_penable),
		.pwrite(m2_apb_pwrite),
		.pwdata(m2_apb_pwdata),
		.pready_out(m2_apb_pready),
		.prdata_out(m2_apb_prdata),
		.pslverr_out(m2_apb_pslverr),
		
		.cap_in(1'b0),
		.cmp_out(pwm_o),
		
		.itr(timer0_itr)
	);
	
	/** UART0 **/
	wire uart0_itr; // 中断请求
	
	apb_uart #(
		.clk_frequency_MHz(CLK_FREQUENCY_MHZ),
		.baud_rate(115200),
		.tx_rx_fifo_ram_type("bram"),
		.tx_fifo_depth(2048),
		.rx_fifo_depth(4096),
		.en_itr("true"),
		.simulation_delay(SIM_DELAY)
	)apb_uart_u0(
		.clk(s_axi_aclk),
		.resetn(s_axi_aresetn),
		
		.paddr(m3_apb_paddr),
		.psel(m3_apb_psel),
		.penable(m3_apb_penable),
		.pwrite(m3_apb_pwrite),
		.pwdata(m3_apb_pwdata),
		.pready_out(m3_apb_pready),
		.prdata_out(m3_apb_prdata),
		.pslverr_out(m3_apb_pslverr),
		
		.uart_tx(uart0_tx),
		.uart_rx(uart0_rx),
		
		.uart_itr(uart0_itr)
	);
	
	/** PLIC **/
	// APB从机
    wire[23:0] s_apb_plic_paddr;
    wire s_apb_plic_penable;
    wire s_apb_plic_pwrite;
    wire[2:0] s_apb_plic_pprot;
    wire s_apb_plic_psel;
    wire[3:0] s_apb_plic_pstrb;
    wire[31:0] s_apb_plic_pwdata;
    wire s_apb_plic_pready;
    wire s_apb_plic_pslverr;
    wire[31:0] s_apb_plic_prdata;
	// ICB主机
	// [命令通道]
	wire[23:0] m_icb_plic_cmd_addr;
	wire m_icb_plic_cmd_read;
	wire[31:0] m_icb_plic_cmd_wdata;
	wire m_icb_plic_cmd_valid;
	wire m_icb_plic_cmd_ready;
	// [响应通道]
	wire[31:0] m_icb_plic_rsp_rdata;
	wire m_icb_plic_rsp_valid;
	wire m_icb_plic_rsp_ready;
	
	assign s_apb_plic_paddr = m4_apb_paddr[23:0];
	assign s_apb_plic_penable = m4_apb_penable;
	assign s_apb_plic_pwrite = m4_apb_pwrite;
	assign s_apb_plic_pprot = m4_apb_pprot;
	assign s_apb_plic_psel = m4_apb_psel;
	assign s_apb_plic_pstrb = m4_apb_pstrb;
	assign s_apb_plic_pwdata = m4_apb_pwdata;
	assign m4_apb_pready = s_apb_plic_pready;
	assign m4_apb_pslverr = s_apb_plic_pslverr;
	assign m4_apb_prdata = s_apb_plic_prdata;
	
	apb_to_icb_bridge #(
		.ADDR_WIDTH(24),
		.SIM_DELAY(SIM_DELAY)
	)apb_to_icb_bridge_u0(
		.aclk(s_axi_aclk),
		.aresetn(s_axi_aresetn),
		
		.s_apb_paddr(s_apb_plic_paddr),
		.s_apb_penable(s_apb_plic_penable),
		.s_apb_pwrite(s_apb_plic_pwrite),
		.s_apb_psel(s_apb_plic_psel),
		.s_apb_pstrb(s_apb_plic_pstrb),
		.s_apb_pwdata(s_apb_plic_pwdata),
		.s_apb_pready(s_apb_plic_pready),
		.s_apb_pslverr(s_apb_plic_pslverr),
		.s_apb_prdata(s_apb_plic_prdata),
		
		.m_icb_cmd_addr(m_icb_plic_cmd_addr),
		.m_icb_cmd_read(m_icb_plic_cmd_read),
		.m_icb_cmd_wdata(m_icb_plic_cmd_wdata),
		.m_icb_cmd_wmask(),
		.m_icb_cmd_valid(m_icb_plic_cmd_valid),
		.m_icb_cmd_ready(m_icb_plic_cmd_ready),
		.m_icb_rsp_rdata(m_icb_plic_rsp_rdata),
		.m_icb_rsp_err(1'b0),
		.m_icb_rsp_valid(m_icb_plic_rsp_valid),
		.m_icb_rsp_ready(m_icb_plic_rsp_ready)
	);
	
	sirv_plic_man #(
		.PLIC_PRIO_WIDTH(3),
		.PLIC_IRQ_NUM(64),
		.PLIC_IRQ_NUM_LOG2(6),
		.PLIC_ICB_RSP_FLOP(1),
		.PLIC_IRQ_I_FLOP(1),
		.PLIC_IRQ_O_FLOP(1) 
	)plic_u(
		.clk(s_axi_aclk),
		.rst_n(s_axi_aresetn),
		
		.icb_cmd_addr(m_icb_plic_cmd_addr),
		.icb_cmd_read(m_icb_plic_cmd_read),
		.icb_cmd_wdata(m_icb_plic_cmd_wdata),
		.icb_cmd_valid(m_icb_plic_cmd_valid),
		.icb_cmd_ready(m_icb_plic_cmd_ready),
		.icb_rsp_rdata(m_icb_plic_rsp_rdata),
		.icb_rsp_valid(m_icb_plic_rsp_valid),
		.icb_rsp_ready(m_icb_plic_rsp_ready),
		
		.plic_irq_i({
			ext_itr_req_vec[59:0],
			uart0_itr,
			timer0_itr,
			gpio0_itr,
			1'b0
		}),
		.plic_irq_o(ext_itr_req)
	);
	
	/** CLINT **/
	apb_clint #(
		.RTC_PSC_R(RTC_PSC_R),
		.SIM_DELAY(SIM_DELAY)
	)clint_u(
		.clk(s_axi_aclk),
		.rst_n(s_axi_aresetn),
		
		.rtc_en(rtc_en),
		
		.s_apb_paddr(m5_apb_paddr),
		.s_apb_penable(m5_apb_penable),
		.s_apb_pwrite(m5_apb_pwrite),
		.s_apb_psel(m5_apb_psel),
		.s_apb_pstrb(m5_apb_pstrb),
		.s_apb_pwdata(m5_apb_pwdata),
		.s_apb_pready(m5_apb_pready),
		.s_apb_pslverr(m5_apb_pslverr),
		.s_apb_prdata(m5_apb_prdata),
		
		.sw_itr_req(sw_itr_req),
		.tmr_itr_req(tmr_itr_req)
	);
	
endmodule
