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
本模块: 小胖达SOC顶层

描述: 
基于小胖达RISC-V的SOC

存储映射 -> 
-----------------------------------------------------------------------
|   总线类别   |  设备名  |        地址区间         |     区间长度    |
-----------------------------------------------------------------------
|              |   ITCM   | 0x0000_0000~?           | IMEM_ADDR_RANGE |
|  指令总线    |------------------------------------------------------|
|              | 调试模块 | 0xFFFF_F800~0xFFFF_FBFF |       1KB       |
-----------------------------------------------------------------------
|  数据总线    |   DTCM   | 0x1000_0000~?           | DMEM_ADDR_RANGE |
-----------------------------------------------------------------------
|              |   GPIO0  | 0x4000_0000~0x4000_0FFF |       4KB       |
|              |------------------------------------------------------|
|              |  TIMER0  | 0x4000_2000~0x4000_2FFF |       4KB       |
|              |------------------------------------------------------|
|  外设总线    |   UART0  | 0x4000_3000~0x4000_3FFF |       4KB       |
|              |------------------------------------------------------|
|              |   PLIC   | 0xF000_0000~0xF03F_FFFF |       4MB       |
|              |------------------------------------------------------|
|              |  CLINT   | 0xF400_0000~0xF7FF_FFFF |      64MB       |
-----------------------------------------------------------------------

外部中断 -> 
-------------------------
| 中断号 |    中断源    |
-------------------------
|   1    |    GPIO0     |
-------------------------
|   2    |    TIMER0    |
-------------------------
|   3    |    UART0     |
-------------------------

注意：
无

协议:
JTAG SLAVE
UART MASTER
GPIO MASTER

作者: 陈家耀
日期: 2026/02/03
********************************************************************/


module panda_soc_top #(
	parameter DEBUG_SUPPORTED = "true", // 是否需要支持Debug
	parameter integer IMEM_ADDR_RANGE = 32 * 1024, // 指令存储器地址区间长度(以字节计)
	parameter ITCM_MEM_INIT_FILE = "E:/scientific_research/risc-v/boot_rom.txt", // ITCM存储器初始化文件路径
	parameter integer DMEM_ADDR_RANGE = 32 * 1024, // 数据存储器地址区间长度(以字节计)
	parameter DTCM_MEM_INIT_FILE = "no_init", // DTCM存储器初始化文件路径
	parameter integer CPU_CLK_FREQUENCY_MHZ = 75, // CPU时钟频率(以MHz计)
	parameter integer RTC_PSC_R = 75 * 100 // RTC预分频系数
)(
	// JTAG从机
	input wire jtag_slave_tck,
	input wire jtag_slave_trst_n,
	input wire jtag_slave_tms,
	input wire jtag_slave_tdi,
	output wire jtag_slave_tdo,
	
    // 时钟和复位
    input wire osc_clk, // 外部晶振时钟输入
	input wire ext_resetn, // 外部复位输入
	
	// UART0
    output wire uart0_tx,
    input wire uart0_rx,
	
	// GPIO0
	inout wire[2:0] gpio0_io,
	
	// PWM
	output wire pwm_o
);
	
	/** 内部配置 **/
	// [总线配置]
	localparam integer IBUS_ACCESS_TIMEOUT_TH = 16; // 指令总线访问超时周期数(0 -> 不设超时 | 正整数)
	localparam integer IBUS_OUTSTANDING_N = 4; // 指令总线滞外深度(1 | 2 | 4 | 8)
	localparam integer AXI_MEM_DATA_WIDTH = 32; // 存储器AXI主机的数据位宽(32 | 64 | 128 | 256)
	localparam integer MEM_ACCESS_TIMEOUT_TH = 16; // 存储器访问超时周期数(0 -> 不设超时 | 正整数)
	localparam integer PERPH_ACCESS_TIMEOUT_TH = 0; // 外设访问超时周期数(0 -> 不设超时 | 正整数)
	localparam PERPH_ADDR_REGION_0_BASE = 32'h4000_0000; // 外设地址区域#0基地址
	localparam PERPH_ADDR_REGION_0_LEN = 32'h1000_0000; // 外设地址区域#0长度(以字节计)
	localparam PERPH_ADDR_REGION_1_BASE = 32'hF000_0000; // 外设地址区域#1基地址
	localparam PERPH_ADDR_REGION_1_LEN = 32'h0800_0000; // 外设地址区域#1长度(以字节计)
	localparam IMEM_BASEADDR = 32'h0000_0000; // 指令存储器基址
	localparam DMEM_BASEADDR = 32'h1000_0000; // 数据存储器基址
	localparam DM_REGS_BASEADDR = 32'hFFFF_F800; // DM寄存器区基址
	localparam integer DM_REGS_ADDR_RANGE = 1 * 1024; // DM寄存器区地址区间长度(以字节计)
	// [分支预测配置]
	localparam integer GHR_WIDTH = 8; // 全局分支历史寄存器的位宽(<=16)
	localparam integer BTB_WAY_N = 2; // BTB路数(1 | 2 | 4)
	localparam integer BTB_ENTRY_N = 1024; // BTB项数(<=65536)
	localparam integer RAS_ENTRY_N = 4; // 返回地址堆栈的条目数(2 | 4 | 8 | 16)
	// [调试配置]
	localparam DEBUG_ROM_ADDR = 32'h0000_0600; // Debug ROM基地址
	localparam integer DSCRATCH_N = 2; // dscratch寄存器的个数(1 | 2)
	localparam integer PROGBUF_SIZE = 4; // Program Buffer的大小(以双字计, 必须在范围[0, 16]内)
	localparam DATA0_ADDR = 32'hFFFF_F800; // data0寄存器在存储映射中的地址
	localparam PROGBUF0_ADDR = 32'hFFFF_F900; // progbuf0寄存器在存储映射中的地址
	localparam HART_ACMD_CTRT_ADDR = 32'hFFFF_FA00; // HART抽象命令运行控制在存储映射中的地址
	// [CSR配置]
	localparam EN_EXPT_VEC_VECTORED = "false"; // 是否使能异常处理的向量链接模式
	localparam EN_PERF_MONITOR = "true"; // 是否使能性能监测相关的CSR
	// [执行单元配置]
	localparam EN_SGN_PERIOD_MUL = "true"; // 是否使用单周期乘法器
	// [ROB配置]
	localparam integer ROB_ENTRY_N = 8; // 重排序队列项数(4 | 8 | 16 | 32)
	localparam integer CSR_RW_RCD_SLOTS_N = 2; // CSR读写指令信息记录槽位数(2 | 4 | 8 | 16 | 32)
	
	/** PLL **/
	wire pll_clk_in;
	wire pll_resetn;
	wire pll_clk_out;
	wire pll_locked;
	
	assign pll_clk_in = osc_clk;
	assign pll_resetn = ext_resetn;
	
	clk_wiz_0 pll_u(
	   .clk_in1(pll_clk_in),
	   .resetn(pll_resetn),
	   
	   .clk_out1(pll_clk_out),
	   .locked(pll_locked)
	);
	
	/** 复位处理 **/
	wire sw_reset; // 软件服务请求
	wire sys_resetn; // 系统复位输出
	wire sys_reset_req; // 系统复位请求
	wire sys_reset_fns; // 系统复位完成
	
	panda_risc_v_reset #(
		.simulation_delay(0)
	)panda_risc_v_reset_u(
		.clk(pll_clk_out),
		
		.ext_resetn(pll_locked),
		
		.sw_reset(sw_reset),
		
		.sys_resetn(sys_resetn),
		.sys_reset_req(sys_reset_req),
		.sys_reset_fns(sys_reset_fns)
	);
	
	/** 小胖达RISC-V处理器核 **/
	// (指令总线)存储器AXI主机
	// [AR通道]
	wire[31:0] m_axi_imem_araddr;
	wire[1:0] m_axi_imem_arburst;
	wire[7:0] m_axi_imem_arlen;
	wire[2:0] m_axi_imem_arsize;
	wire m_axi_imem_arvalid;
	wire m_axi_imem_arready;
	// [R通道]
	wire[31:0] m_axi_imem_rdata;
	wire[1:0] m_axi_imem_rresp;
	wire m_axi_imem_rlast;
	wire m_axi_imem_rvalid;
	wire m_axi_imem_rready;
	// [AW通道]
	wire[31:0] m_axi_imem_awaddr;
	wire[1:0] m_axi_imem_awburst;
	wire[7:0] m_axi_imem_awlen;
	wire[2:0] m_axi_imem_awsize;
	wire m_axi_imem_awvalid;
	wire m_axi_imem_awready;
	// [B通道]
	wire[1:0] m_axi_imem_bresp;
	wire m_axi_imem_bvalid;
	wire m_axi_imem_bready;
	// [W通道]
	wire[31:0] m_axi_imem_wdata;
	wire[3:0] m_axi_imem_wstrb;
	wire m_axi_imem_wlast;
	wire m_axi_imem_wvalid;
	wire m_axi_imem_wready;
	// (数据总线)存储器AXI主机
	// [AR通道]
	wire[31:0] m_axi_dmem_araddr;
	wire[1:0] m_axi_dmem_arburst;
	wire[7:0] m_axi_dmem_arlen;
	wire[2:0] m_axi_dmem_arsize;
	wire m_axi_dmem_arvalid;
	wire m_axi_dmem_arready;
	// [R通道]
	wire[31:0] m_axi_dmem_rdata;
	wire[1:0] m_axi_dmem_rresp;
	wire m_axi_dmem_rlast;
	wire m_axi_dmem_rvalid;
	wire m_axi_dmem_rready;
	// [AW通道]
	wire[31:0] m_axi_dmem_awaddr;
	wire[1:0] m_axi_dmem_awburst;
	wire[7:0] m_axi_dmem_awlen;
	wire[2:0] m_axi_dmem_awsize;
	wire m_axi_dmem_awvalid;
	wire m_axi_dmem_awready;
	// [B通道]
	wire[1:0] m_axi_dmem_bresp;
	wire m_axi_dmem_bvalid;
	wire m_axi_dmem_bready;
	// [W通道]
	wire[31:0] m_axi_dmem_wdata;
	wire[3:0] m_axi_dmem_wstrb;
	wire m_axi_dmem_wlast;
	wire m_axi_dmem_wvalid;
	wire m_axi_dmem_wready;
	// (数据总线)外设AXI主机
	// [AR通道]
	wire[31:0] m_axi_perph_araddr;
	wire[1:0] m_axi_perph_arburst;
	wire[7:0] m_axi_perph_arlen;
	wire[2:0] m_axi_perph_arsize;
	wire m_axi_perph_arvalid;
	wire m_axi_perph_arready;
	// [R通道]
	wire[31:0] m_axi_perph_rdata;
	wire[1:0] m_axi_perph_rresp;
	wire m_axi_perph_rlast;
	wire m_axi_perph_rvalid;
	wire m_axi_perph_rready;
	// [AW通道]
	wire[31:0] m_axi_perph_awaddr;
	wire[1:0] m_axi_perph_awburst;
	wire[7:0] m_axi_perph_awlen;
	wire[2:0] m_axi_perph_awsize;
	wire m_axi_perph_awvalid;
	wire m_axi_perph_awready;
	// [B通道]
	wire[1:0] m_axi_perph_bresp;
	wire m_axi_perph_bvalid;
	wire m_axi_perph_bready;
	// [W通道]
	wire[31:0] m_axi_perph_wdata;
	wire[3:0] m_axi_perph_wstrb;
	wire m_axi_perph_wlast;
	wire m_axi_perph_wvalid;
	wire m_axi_perph_wready;
	// BTB存储器
	// [端口A]
	wire[BTB_WAY_N-1:0] btb_mem_clka;
	wire[BTB_WAY_N-1:0] btb_mem_ena;
	wire[BTB_WAY_N-1:0] btb_mem_wea;
	wire[BTB_WAY_N*16-1:0] btb_mem_addra;
	wire[BTB_WAY_N*64-1:0] btb_mem_dina;
	wire[BTB_WAY_N*64-1:0] btb_mem_douta;
	// [端口B]
	wire[BTB_WAY_N-1:0] btb_mem_clkb;
	wire[BTB_WAY_N-1:0] btb_mem_enb;
	wire[BTB_WAY_N-1:0] btb_mem_web;
	wire[BTB_WAY_N*16-1:0] btb_mem_addrb;
	wire[BTB_WAY_N*64-1:0] btb_mem_dinb;
	wire[BTB_WAY_N*64-1:0] btb_mem_doutb;
	// 中断请求
	wire sw_itr_req; // 软件中断请求
	wire tmr_itr_req; // 计时器中断请求
	wire ext_itr_req; // 外部中断请求
	// 调试请求
	wire dbg_halt_req; // 来自调试器的暂停请求
	wire dbg_halt_on_reset_req; // 来自调试器的复位释放后暂停请求
	
	panda_risc_v_core #(
		.IBUS_ACCESS_TIMEOUT_TH(IBUS_ACCESS_TIMEOUT_TH),
		.IBUS_OUTSTANDING_N(IBUS_OUTSTANDING_N),
		.AXI_MEM_DATA_WIDTH(AXI_MEM_DATA_WIDTH),
		.MEM_ACCESS_TIMEOUT_TH(MEM_ACCESS_TIMEOUT_TH),
		.PERPH_ACCESS_TIMEOUT_TH(PERPH_ACCESS_TIMEOUT_TH),
		.PERPH_ADDR_REGION_0_BASE(PERPH_ADDR_REGION_0_BASE),
		.PERPH_ADDR_REGION_0_LEN(PERPH_ADDR_REGION_0_LEN),
		.PERPH_ADDR_REGION_1_BASE(PERPH_ADDR_REGION_1_BASE),
		.PERPH_ADDR_REGION_1_LEN(PERPH_ADDR_REGION_1_LEN),
		.IMEM_BASEADDR(IMEM_BASEADDR),
		.IMEM_ADDR_RANGE(IMEM_ADDR_RANGE),
		.DM_REGS_BASEADDR(DM_REGS_BASEADDR),
		.DM_REGS_ADDR_RANGE(DM_REGS_ADDR_RANGE),
		.GHR_WIDTH(GHR_WIDTH),
		.BTB_WAY_N(BTB_WAY_N),
		.BTB_ENTRY_N(BTB_ENTRY_N),
		.RAS_ENTRY_N(RAS_ENTRY_N),
		.DEBUG_SUPPORTED(DEBUG_SUPPORTED),
		.DEBUG_ROM_ADDR(DEBUG_ROM_ADDR),
		.DSCRATCH_N(DSCRATCH_N),
		.EN_EXPT_VEC_VECTORED(EN_EXPT_VEC_VECTORED),
		.EN_PERF_MONITOR(EN_PERF_MONITOR),
		.EN_SGN_PERIOD_MUL(EN_SGN_PERIOD_MUL),
		.ROB_ENTRY_N(ROB_ENTRY_N),
		.CSR_RW_RCD_SLOTS_N(CSR_RW_RCD_SLOTS_N),
		.SIM_DELAY(0)
	)panda_risc_v_core_u(
		.aclk(pll_clk_out),
		.aresetn(sys_resetn),
		
		.sys_reset_req(sys_reset_req),
		.rst_pc(32'h0000_0000),
		
		.m_axi_imem_araddr(m_axi_imem_araddr),
		.m_axi_imem_arburst(m_axi_imem_arburst),
		.m_axi_imem_arlen(m_axi_imem_arlen),
		.m_axi_imem_arsize(m_axi_imem_arsize),
		.m_axi_imem_arvalid(m_axi_imem_arvalid),
		.m_axi_imem_arready(m_axi_imem_arready),
		.m_axi_imem_rdata(m_axi_imem_rdata),
		.m_axi_imem_rresp(m_axi_imem_rresp),
		.m_axi_imem_rlast(m_axi_imem_rlast),
		.m_axi_imem_rvalid(m_axi_imem_rvalid),
		.m_axi_imem_rready(m_axi_imem_rready),
		.m_axi_imem_awaddr(m_axi_imem_awaddr),
		.m_axi_imem_awburst(m_axi_imem_awburst),
		.m_axi_imem_awlen(m_axi_imem_awlen),
		.m_axi_imem_awsize(m_axi_imem_awsize),
		.m_axi_imem_awvalid(m_axi_imem_awvalid),
		.m_axi_imem_awready(m_axi_imem_awready),
		.m_axi_imem_bresp(m_axi_imem_bresp),
		.m_axi_imem_bvalid(m_axi_imem_bvalid),
		.m_axi_imem_bready(m_axi_imem_bready),
		.m_axi_imem_wdata(m_axi_imem_wdata),
		.m_axi_imem_wstrb(m_axi_imem_wstrb),
		.m_axi_imem_wlast(m_axi_imem_wlast),
		.m_axi_imem_wvalid(m_axi_imem_wvalid),
		.m_axi_imem_wready(m_axi_imem_wready),
		
		.m_axi_dmem_araddr(m_axi_dmem_araddr),
		.m_axi_dmem_arburst(m_axi_dmem_arburst),
		.m_axi_dmem_arlen(m_axi_dmem_arlen),
		.m_axi_dmem_arsize(m_axi_dmem_arsize),
		.m_axi_dmem_arvalid(m_axi_dmem_arvalid),
		.m_axi_dmem_arready(m_axi_dmem_arready),
		.m_axi_dmem_rdata(m_axi_dmem_rdata),
		.m_axi_dmem_rresp(m_axi_dmem_rresp),
		.m_axi_dmem_rlast(m_axi_dmem_rlast),
		.m_axi_dmem_rvalid(m_axi_dmem_rvalid),
		.m_axi_dmem_rready(m_axi_dmem_rready),
		.m_axi_dmem_awaddr(m_axi_dmem_awaddr),
		.m_axi_dmem_awburst(m_axi_dmem_awburst),
		.m_axi_dmem_awlen(m_axi_dmem_awlen),
		.m_axi_dmem_awsize(m_axi_dmem_awsize),
		.m_axi_dmem_awvalid(m_axi_dmem_awvalid),
		.m_axi_dmem_awready(m_axi_dmem_awready),
		.m_axi_dmem_bresp(m_axi_dmem_bresp),
		.m_axi_dmem_bvalid(m_axi_dmem_bvalid),
		.m_axi_dmem_bready(m_axi_dmem_bready),
		.m_axi_dmem_wdata(m_axi_dmem_wdata),
		.m_axi_dmem_wstrb(m_axi_dmem_wstrb),
		.m_axi_dmem_wlast(m_axi_dmem_wlast),
		.m_axi_dmem_wvalid(m_axi_dmem_wvalid),
		.m_axi_dmem_wready(m_axi_dmem_wready),
		
		.m_axi_perph_araddr(m_axi_perph_araddr),
		.m_axi_perph_arburst(m_axi_perph_arburst),
		.m_axi_perph_arlen(m_axi_perph_arlen),
		.m_axi_perph_arsize(m_axi_perph_arsize),
		.m_axi_perph_arvalid(m_axi_perph_arvalid),
		.m_axi_perph_arready(m_axi_perph_arready),
		.m_axi_perph_rdata(m_axi_perph_rdata),
		.m_axi_perph_rresp(m_axi_perph_rresp),
		.m_axi_perph_rlast(m_axi_perph_rlast),
		.m_axi_perph_rvalid(m_axi_perph_rvalid),
		.m_axi_perph_rready(m_axi_perph_rready),
		.m_axi_perph_awaddr(m_axi_perph_awaddr),
		.m_axi_perph_awburst(m_axi_perph_awburst),
		.m_axi_perph_awlen(m_axi_perph_awlen),
		.m_axi_perph_awsize(m_axi_perph_awsize),
		.m_axi_perph_awvalid(m_axi_perph_awvalid),
		.m_axi_perph_awready(m_axi_perph_awready),
		.m_axi_perph_bresp(m_axi_perph_bresp),
		.m_axi_perph_bvalid(m_axi_perph_bvalid),
		.m_axi_perph_bready(m_axi_perph_bready),
		.m_axi_perph_wdata(m_axi_perph_wdata),
		.m_axi_perph_wstrb(m_axi_perph_wstrb),
		.m_axi_perph_wlast(m_axi_perph_wlast),
		.m_axi_perph_wvalid(m_axi_perph_wvalid),
		.m_axi_perph_wready(m_axi_perph_wready),
		
		.btb_mem_clka(btb_mem_clka),
		.btb_mem_ena(btb_mem_ena),
		.btb_mem_wea(btb_mem_wea),
		.btb_mem_addra(btb_mem_addra),
		.btb_mem_dina(btb_mem_dina),
		.btb_mem_douta(btb_mem_douta),
		.btb_mem_clkb(btb_mem_clkb),
		.btb_mem_enb(btb_mem_enb),
		.btb_mem_web(btb_mem_web),
		.btb_mem_addrb(btb_mem_addrb),
		.btb_mem_dinb(btb_mem_dinb),
		.btb_mem_doutb(btb_mem_doutb),
		
		.sw_itr_req(sw_itr_req),
		.tmr_itr_req(tmr_itr_req),
		.ext_itr_req(ext_itr_req),
		
		.dbg_halt_req(dbg_halt_req),
		.dbg_halt_on_reset_req(dbg_halt_on_reset_req),
		
		.clr_inst_buf_while_suppressing(),
		.ibus_timeout(),
		.rd_mem_timeout(),
		.wr_mem_timeout(),
		.perph_access_timeout()
	);
	
	/** 小胖达RISC-V基础指令系统设备 **/
	panda_risc_v_basis_inst_device #(
		.DEBUG_SUPPORTED(DEBUG_SUPPORTED),
		.PROGBUF_SIZE(PROGBUF_SIZE),
		.DATA0_ADDR(DATA0_ADDR),
		.PROGBUF0_ADDR(PROGBUF0_ADDR),
		.HART_ACMD_CTRT_ADDR(HART_ACMD_CTRT_ADDR),
		.IMEM_BASEADDR(IMEM_BASEADDR),
		.IMEM_ADDR_RANGE(IMEM_ADDR_RANGE),
		.DM_REGS_BASEADDR(DM_REGS_BASEADDR),
		.DM_REGS_ADDR_RANGE(DM_REGS_ADDR_RANGE),
		.ITCM_MEM_INIT_FILE(ITCM_MEM_INIT_FILE),
		.BTB_WAY_N(BTB_WAY_N),
		.BTB_ENTRY_N(BTB_ENTRY_N),
		.SIM_DELAY(0)
	)panda_risc_v_basis_inst_device_u(
		.jtag_slave_tck(jtag_slave_tck),
		.jtag_slave_trst_n(jtag_slave_trst_n),
		.jtag_slave_tms(jtag_slave_tms),
		.jtag_slave_tdi(jtag_slave_tdi),
		.jtag_slave_tdo(jtag_slave_tdo),
		
		.s_axi_aclk(pll_clk_out),
		.s_axi_aresetn(sys_resetn),
		
		.dbg_aresetn(pll_locked),
		
		.sys_reset_fns(sys_reset_fns),
		.sw_reset(sw_reset),
		
		.dbg_halt_req(dbg_halt_req),
		.dbg_halt_on_reset_req(dbg_halt_on_reset_req),
		
		.s_axi_imem_araddr(m_axi_imem_araddr),
		.s_axi_imem_arburst(m_axi_imem_arburst),
		.s_axi_imem_arlen(m_axi_imem_arlen),
		.s_axi_imem_arsize(m_axi_imem_arsize),
		.s_axi_imem_arvalid(m_axi_imem_arvalid),
		.s_axi_imem_arready(m_axi_imem_arready),
		.s_axi_imem_rdata(m_axi_imem_rdata),
		.s_axi_imem_rresp(m_axi_imem_rresp),
		.s_axi_imem_rlast(m_axi_imem_rlast),
		.s_axi_imem_rvalid(m_axi_imem_rvalid),
		.s_axi_imem_rready(m_axi_imem_rready),
		.s_axi_imem_awaddr(m_axi_imem_awaddr),
		.s_axi_imem_awburst(m_axi_imem_awburst),
		.s_axi_imem_awlen(m_axi_imem_awlen),
		.s_axi_imem_awsize(m_axi_imem_awsize),
		.s_axi_imem_awvalid(m_axi_imem_awvalid),
		.s_axi_imem_awready(m_axi_imem_awready),
		.s_axi_imem_bresp(m_axi_imem_bresp),
		.s_axi_imem_bvalid(m_axi_imem_bvalid),
		.s_axi_imem_bready(m_axi_imem_bready),
		.s_axi_imem_wdata(m_axi_imem_wdata),
		.s_axi_imem_wstrb(m_axi_imem_wstrb),
		.s_axi_imem_wlast(m_axi_imem_wlast),
		.s_axi_imem_wvalid(m_axi_imem_wvalid),
		.s_axi_imem_wready(m_axi_imem_wready),
		
		.btb_mem_clka(btb_mem_clka),
		.btb_mem_ena(btb_mem_ena),
		.btb_mem_wea(btb_mem_wea),
		.btb_mem_addra(btb_mem_addra),
		.btb_mem_dina(btb_mem_dina),
		.btb_mem_douta(btb_mem_douta),
		.btb_mem_clkb(btb_mem_clkb),
		.btb_mem_enb(btb_mem_enb),
		.btb_mem_web(btb_mem_web),
		.btb_mem_addrb(btb_mem_addrb),
		.btb_mem_dinb(btb_mem_dinb),
		.btb_mem_doutb(btb_mem_doutb)
	);
	
	/** 小胖达RISC-V基础数据系统设备 **/
	panda_risc_v_basis_data_device #(
		.DMEM_BASEADDR(DMEM_BASEADDR),
		.DMEM_ADDR_RANGE(DMEM_ADDR_RANGE),
		.DTCM_MEM_INIT_FILE(DTCM_MEM_INIT_FILE),
		.SIM_DELAY(0)
	)panda_risc_v_basis_data_device_u(
		.s_axi_aclk(pll_clk_out),
		.s_axi_aresetn(sys_resetn),
		
		.s_axi_dmem_araddr(m_axi_dmem_araddr),
		.s_axi_dmem_arburst(m_axi_dmem_arburst),
		.s_axi_dmem_arlen(m_axi_dmem_arlen),
		.s_axi_dmem_arsize(m_axi_dmem_arsize),
		.s_axi_dmem_arvalid(m_axi_dmem_arvalid),
		.s_axi_dmem_arready(m_axi_dmem_arready),
		.s_axi_dmem_rdata(m_axi_dmem_rdata),
		.s_axi_dmem_rresp(m_axi_dmem_rresp),
		.s_axi_dmem_rlast(m_axi_dmem_rlast),
		.s_axi_dmem_rvalid(m_axi_dmem_rvalid),
		.s_axi_dmem_rready(m_axi_dmem_rready),
		.s_axi_dmem_awaddr(m_axi_dmem_awaddr),
		.s_axi_dmem_awburst(m_axi_dmem_awburst),
		.s_axi_dmem_awlen(m_axi_dmem_awlen),
		.s_axi_dmem_awsize(m_axi_dmem_awsize),
		.s_axi_dmem_awvalid(m_axi_dmem_awvalid),
		.s_axi_dmem_awready(m_axi_dmem_awready),
		.s_axi_dmem_bresp(m_axi_dmem_bresp),
		.s_axi_dmem_bvalid(m_axi_dmem_bvalid),
		.s_axi_dmem_bready(m_axi_dmem_bready),
		.s_axi_dmem_wdata(m_axi_dmem_wdata),
		.s_axi_dmem_wstrb(m_axi_dmem_wstrb),
		.s_axi_dmem_wlast(m_axi_dmem_wlast),
		.s_axi_dmem_wvalid(m_axi_dmem_wvalid),
		.s_axi_dmem_wready(m_axi_dmem_wready)
	);
	
	/** 小胖达RISC-V基础外设系统设备 **/
	// GPIO0
	wire[2:0] gpio0_o;
    wire[2:0] gpio0_t; // 0->输出, 1->输入
    wire[2:0] gpio0_i;
	
	genvar gpio0_port_i;
	generate
		for(gpio0_port_i = 0;gpio0_port_i < 3;gpio0_port_i = gpio0_port_i + 1)
		begin:gpio0_port_blk
			assign gpio0_io[gpio0_port_i] = gpio0_t[gpio0_port_i] ? 1'bz:gpio0_o[gpio0_port_i];
			assign gpio0_i[gpio0_port_i] = gpio0_io[gpio0_port_i];
		end
	endgenerate
	
	panda_risc_v_basis_perph_device #(
		.RTC_PSC_R(RTC_PSC_R),
		.CLK_FREQUENCY_MHZ(CPU_CLK_FREQUENCY_MHZ),
		.SIM_DELAY(0)
	)panda_risc_v_basis_perph_device_u(
		.s_axi_aclk(pll_clk_out),
		.s_axi_aresetn(sys_resetn),
		
		.s_axi_perph_araddr(m_axi_perph_araddr),
		.s_axi_perph_arburst(m_axi_perph_arburst),
		.s_axi_perph_arlen(m_axi_perph_arlen),
		.s_axi_perph_arsize(m_axi_perph_arsize),
		.s_axi_perph_arvalid(m_axi_perph_arvalid),
		.s_axi_perph_arready(m_axi_perph_arready),
		.s_axi_perph_rdata(m_axi_perph_rdata),
		.s_axi_perph_rresp(m_axi_perph_rresp),
		.s_axi_perph_rlast(m_axi_perph_rlast),
		.s_axi_perph_rvalid(m_axi_perph_rvalid),
		.s_axi_perph_rready(m_axi_perph_rready),
		.s_axi_perph_awaddr(m_axi_perph_awaddr),
		.s_axi_perph_awburst(m_axi_perph_awburst),
		.s_axi_perph_awlen(m_axi_perph_awlen),
		.s_axi_perph_awsize(m_axi_perph_awsize),
		.s_axi_perph_awvalid(m_axi_perph_awvalid),
		.s_axi_perph_awready(m_axi_perph_awready),
		.s_axi_perph_bresp(m_axi_perph_bresp),
		.s_axi_perph_bvalid(m_axi_perph_bvalid),
		.s_axi_perph_bready(m_axi_perph_bready),
		.s_axi_perph_wdata(m_axi_perph_wdata),
		.s_axi_perph_wstrb(m_axi_perph_wstrb),
		.s_axi_perph_wlast(m_axi_perph_wlast),
		.s_axi_perph_wvalid(m_axi_perph_wvalid),
		.s_axi_perph_wready(m_axi_perph_wready),
		
		.rtc_en(1'b1),
		
		.ext_itr_req_vec(60'd0),
		
		.sw_itr_req(sw_itr_req),
		.tmr_itr_req(tmr_itr_req),
		.ext_itr_req(ext_itr_req),
		
		.uart0_tx(uart0_tx),
		.uart0_rx(uart0_rx),
		
		.gpio0_o(gpio0_o),
		.gpio0_t(gpio0_t),
		.gpio0_i(gpio0_i),
		
		.pwm_o(pwm_o)
	);
	
endmodule
