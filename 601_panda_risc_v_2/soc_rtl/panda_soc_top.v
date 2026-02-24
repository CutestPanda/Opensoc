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
日期: 2026/02/24
********************************************************************/


module panda_soc_top #(
	parameter DMEM_TYPE = "dcache", // 数据存储器类型(dtcm | dcache)
	parameter DEBUG_SUPPORTED = "true", // 是否需要支持Debug
	parameter integer IMEM_ADDR_RANGE = 32 * 1024, // 指令存储器地址区间长度(以字节计)
	parameter ITCM_MEM_INIT_FILE = "E:/scientific_research/risc-v/boot_rom.txt", // ITCM存储器初始化文件路径
	parameter integer DMEM_ADDR_RANGE = 32 * 1024 * 1024, // 数据存储器地址区间长度(以字节计)
	parameter DTCM_MEM_INIT_FILE = "no_init", // DTCM存储器初始化文件路径
	parameter integer CPU_CLK_FREQUENCY_MHZ = 100, // CPU时钟频率(以MHz计)
	parameter integer RTC_PSC_R = 100 * 100 // RTC预分频系数
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
	output wire pwm_o,
	
	// DDR3
	inout wire[31:0] ddr3_dq,
	inout wire[3:0] ddr3_dqs_n,
	inout wire[3:0] ddr3_dqs_p,
	output wire[14:0] ddr3_addr,
	output wire[2:0] ddr3_ba,
	output wire ddr3_ras_n,
	output wire ddr3_cas_n,
	output wire ddr3_we_n,
	output wire ddr3_reset_n,
	output wire[0:0] ddr3_ck_p,
	output wire[0:0] ddr3_ck_n,
	output wire[0:0] ddr3_cke,
	output wire[0:0] ddr3_cs_n,
	output wire[3:0] ddr3_dm,
	output wire[0:0] ddr3_odt
);
	
	/** 内部配置 **/
	// [Dcache配置]
	localparam integer CACHE_WAY_N = 4; // 缓存路数(1 | 2 | 4 | 8)
	localparam integer CACHE_ENTRY_N = 256; // 缓存存储条目数
	localparam integer CACHE_LINE_DATA_N = 8; // 每个缓存行的数据个数(1 | 2 | 4 | 8 | 16)
	localparam integer CACHE_WBUF_ITEM_N = 4; // 写缓存最多可存的缓存行个数(1~8)
	// [总线配置]
	localparam integer IBUS_ACCESS_TIMEOUT_TH = 16; // 指令总线访问超时周期数(0 -> 不设超时 | 正整数)
	localparam integer IBUS_OUTSTANDING_N = 4; // 指令总线滞外深度(1 | 2 | 4 | 8)
	localparam integer AXI_MEM_DATA_WIDTH = 32; // 存储器AXI主机的数据位宽(32 | 64 | 128 | 256)
	localparam integer MEM_ACCESS_TIMEOUT_TH = 0; // 存储器访问超时周期数(0 -> 不设超时 | 正整数)
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
	localparam integer GHR_WIDTH = 0; // 全局分支历史寄存器的位宽(<=16)
	localparam integer PC_WIDTH_FOR_PHT_ADDR = 3; // PHT地址截取的低位PC的位宽(必须在范围[1, 16]内)
	localparam integer BHR_WIDTH = 13; // 局部分支历史寄存器(BHR)的位宽
	localparam integer BHT_DEPTH = 512; // 局部分支历史表(BHT)的深度(必须>=2且为2^n)
	localparam PHT_MEM_IMPL = "sram"; // PHT存储器的实现方式(reg | sram)
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
	
	/** 时钟 **/
	// PLL
	wire pll_clk_in;
	wire pll_resetn;
	wire pll_clk_out;
	wire pll_locked;
	// DDR控制器生成的时钟
	wire ddr3_ui_clk;
    wire ddr3_ui_rst;
	// CPU时钟
	wire cpu_clk;
	
	assign pll_clk_in = osc_clk;
	assign pll_resetn = ext_resetn;
	
	assign cpu_clk = 
		(DMEM_TYPE == "dtcm") ? 
			pll_clk_out:
			ddr3_ui_clk;
	
	clk_wiz_0 pll_u(
	   .clk_in1(pll_clk_in),
	   .resetn(pll_resetn),
	   
	   .clk_out1(pll_clk_out),
	   .locked(pll_locked)
	);
	
	/** 复位处理 **/
	wire org_resetn; // 原始复位信号
	wire sw_reset; // 软件服务请求
	wire sys_resetn; // 系统复位输出
	wire sys_reset_req; // 系统复位请求
	wire sys_reset_fns; // 系统复位完成
	
	assign org_resetn = 
		(DMEM_TYPE == "dtcm") ? 
			pll_locked:
			(~ddr3_ui_rst);
	
	panda_risc_v_reset #(
		.simulation_delay(0)
	)panda_risc_v_reset_u(
		.clk(cpu_clk),
		
		.ext_resetn(org_resetn),
		
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
	// PHT存储器
	// 说明: PHT_MEM_IMPL == "sram"时可用
	// [端口A]
	wire pht_mem_clka;
	wire pht_mem_ena;
	wire pht_mem_wea;
	wire[15:0] pht_mem_addra;
	wire[1:0] pht_mem_dina;
	wire[1:0] pht_mem_douta;
	// [端口B]
	wire pht_mem_clkb;
	wire pht_mem_enb;
	wire pht_mem_web;
	wire[15:0] pht_mem_addrb;
	wire[1:0] pht_mem_dinb;
	wire[1:0] pht_mem_doutb;
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
		.PC_WIDTH_FOR_PHT_ADDR(PC_WIDTH_FOR_PHT_ADDR),
		.BHR_WIDTH(BHR_WIDTH),
		.BHT_DEPTH(BHT_DEPTH),
		.PHT_MEM_IMPL(PHT_MEM_IMPL),
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
		.aclk(cpu_clk),
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
		
		.pht_mem_clka(pht_mem_clka),
		.pht_mem_ena(pht_mem_ena),
		.pht_mem_wea(pht_mem_wea),
		.pht_mem_addra(pht_mem_addra),
		.pht_mem_dina(pht_mem_dina),
		.pht_mem_douta(pht_mem_douta),
		
		.pht_mem_clkb(pht_mem_clkb),
		.pht_mem_enb(pht_mem_enb),
		.pht_mem_web(pht_mem_web),
		.pht_mem_addrb(pht_mem_addrb),
		.pht_mem_dinb(pht_mem_dinb),
		.pht_mem_doutb(pht_mem_doutb),
		
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
		.PHT_ADDR_WIDTH(PC_WIDTH_FOR_PHT_ADDR + BHR_WIDTH),
		.SIM_DELAY(0)
	)panda_risc_v_basis_inst_device_u(
		.jtag_slave_tck(jtag_slave_tck),
		.jtag_slave_trst_n(jtag_slave_trst_n),
		.jtag_slave_tms(jtag_slave_tms),
		.jtag_slave_tdi(jtag_slave_tdi),
		.jtag_slave_tdo(jtag_slave_tdo),
		
		.s_axi_aclk(cpu_clk),
		.s_axi_aresetn(sys_resetn),
		
		.dbg_aresetn(org_resetn),
		
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
		.btb_mem_doutb(btb_mem_doutb),
		
		.pht_mem_clka(pht_mem_clka),
		.pht_mem_ena(pht_mem_ena),
		.pht_mem_wea(pht_mem_wea),
		.pht_mem_addra(pht_mem_addra),
		.pht_mem_dina(pht_mem_dina),
		.pht_mem_douta(pht_mem_douta),
		
		.pht_mem_clkb(pht_mem_clkb),
		.pht_mem_enb(pht_mem_enb),
		.pht_mem_web(pht_mem_web),
		.pht_mem_addrb(pht_mem_addrb),
		.pht_mem_dinb(pht_mem_dinb),
		.pht_mem_doutb(pht_mem_doutb)
	);
	
	/** 小胖达RISC-V基础数据系统设备 **/
	// 访问下级存储器(AXI主机)
	// 说明: 仅当启用DCache时可用
	// [AR通道]
	wire[31:0] m_axi_nlv_araddr;
	wire[1:0] m_axi_nlv_arburst; // const -> 2'b01(INCR)
	wire[7:0] m_axi_nlv_arlen; // const -> CACHE_LINE_DATA_N - 1
	wire[2:0] m_axi_nlv_arsize; // const -> 3'b010
	wire m_axi_nlv_arvalid;
	wire m_axi_nlv_arready;
	// [R通道]
	wire[31:0] m_axi_nlv_rdata;
	wire[1:0] m_axi_nlv_rresp; // ignored
	wire m_axi_nlv_rlast; // ignored
	wire m_axi_nlv_rvalid;
	wire m_axi_nlv_rready; // const -> 1'b1
	// [AW通道]
	wire[31:0] m_axi_nlv_awaddr;
	wire[1:0] m_axi_nlv_awburst; // const -> 2'b01(INCR)
	wire[7:0] m_axi_nlv_awlen; // const -> CACHE_LINE_DATA_N - 1
	wire[2:0] m_axi_nlv_awsize; // const -> 3'b010
	wire m_axi_nlv_awvalid;
	wire m_axi_nlv_awready;
	// [B通道]
	wire[1:0] m_axi_nlv_bresp; // ignored
	wire m_axi_nlv_bvalid;
	wire m_axi_nlv_bready; // const -> 1'b1
	// [W通道]
	wire[31:0] m_axi_nlv_wdata;
	wire[3:0] m_axi_nlv_wstrb; // const -> 4'b1111
	wire m_axi_nlv_wlast;
	wire m_axi_nlv_wvalid;
	wire m_axi_nlv_wready;
	
	panda_risc_v_basis_data_device #(
		.DMEM_TYPE(DMEM_TYPE),
		.DMEM_BASEADDR(DMEM_BASEADDR),
		.DMEM_ADDR_RANGE(DMEM_ADDR_RANGE),
		.DTCM_MEM_INIT_FILE(DTCM_MEM_INIT_FILE),
		.CACHE_WAY_N(CACHE_WAY_N),
		.CACHE_ENTRY_N(CACHE_ENTRY_N),
		.CACHE_LINE_DATA_N(CACHE_LINE_DATA_N),
		.CACHE_WBUF_ITEM_N(CACHE_WBUF_ITEM_N),
		.SIM_DELAY(0)
	)panda_risc_v_basis_data_device_u(
		.s_axi_aclk(cpu_clk),
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
		.s_axi_dmem_wready(m_axi_dmem_wready),
		
		.m_axi_nlv_araddr(m_axi_nlv_araddr),
		.m_axi_nlv_arburst(m_axi_nlv_arburst),
		.m_axi_nlv_arlen(m_axi_nlv_arlen),
		.m_axi_nlv_arsize(m_axi_nlv_arsize),
		.m_axi_nlv_arvalid(m_axi_nlv_arvalid),
		.m_axi_nlv_arready(m_axi_nlv_arready),
		.m_axi_nlv_rdata(m_axi_nlv_rdata),
		.m_axi_nlv_rresp(m_axi_nlv_rresp),
		.m_axi_nlv_rlast(m_axi_nlv_rlast),
		.m_axi_nlv_rvalid(m_axi_nlv_rvalid),
		.m_axi_nlv_rready(m_axi_nlv_rready),
		.m_axi_nlv_awaddr(m_axi_nlv_awaddr),
		.m_axi_nlv_awburst(m_axi_nlv_awburst),
		.m_axi_nlv_awlen(m_axi_nlv_awlen),
		.m_axi_nlv_awsize(m_axi_nlv_awsize),
		.m_axi_nlv_awvalid(m_axi_nlv_awvalid),
		.m_axi_nlv_awready(m_axi_nlv_awready),
		.m_axi_nlv_bresp(m_axi_nlv_bresp),
		.m_axi_nlv_bvalid(m_axi_nlv_bvalid),
		.m_axi_nlv_bready(m_axi_nlv_bready),
		.m_axi_nlv_wdata(m_axi_nlv_wdata),
		.m_axi_nlv_wstrb(m_axi_nlv_wstrb),
		.m_axi_nlv_wlast(m_axi_nlv_wlast),
		.m_axi_nlv_wvalid(m_axi_nlv_wvalid),
		.m_axi_nlv_wready(m_axi_nlv_wready)
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
		.s_axi_aclk(cpu_clk),
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
	
	/** DDR控制器 **/
	// 控制器主时钟
	wire ddr3_clk;
	// DDR3访问(AXI从机)
	// [AR通道]
	wire[3:0] s_axi_ddr_arid;
	wire s_axi_ddr_arlock;
	wire[3:0] s_axi_ddr_arcache;
	wire[2:0] s_axi_ddr_arprot;
	wire[3:0] s_axi_ddr_arqos;
	wire[31:0] s_axi_ddr_araddr;
	wire[1:0] s_axi_ddr_arburst;
	wire[7:0] s_axi_ddr_arlen;
	wire[2:0] s_axi_ddr_arsize;
	wire s_axi_ddr_arvalid;
	wire s_axi_ddr_arready;
	// [R通道]
	wire[3:0] s_axi_ddr_rid;
	wire[31:0] s_axi_ddr_rdata;
	wire[1:0] s_axi_ddr_rresp;
	wire s_axi_ddr_rlast;
	wire s_axi_ddr_rvalid;
	wire s_axi_ddr_rready;
	// [AW通道]
	wire[3:0] s_axi_ddr_awid;
	wire s_axi_ddr_awlock;
	wire[3:0] s_axi_ddr_awcache;
	wire[2:0] s_axi_ddr_awprot;
	wire[3:0] s_axi_ddr_awqos;
	wire[31:0] s_axi_ddr_awaddr;
	wire[1:0] s_axi_ddr_awburst;
	wire[7:0] s_axi_ddr_awlen;
	wire[2:0] s_axi_ddr_awsize;
	wire s_axi_ddr_awvalid;
	wire s_axi_ddr_awready;
	// [B通道]
	wire[3:0] s_axi_ddr_bid;
	wire[1:0] s_axi_ddr_bresp;
	wire s_axi_ddr_bvalid;
	wire s_axi_ddr_bready;
	// [W通道]
	wire[31:0] s_axi_ddr_wdata;
	wire[3:0] s_axi_ddr_wstrb;
	wire s_axi_ddr_wlast;
	wire s_axi_ddr_wvalid;
	wire s_axi_ddr_wready;
	
	assign ddr3_clk = (DMEM_TYPE == "dcache") & pll_clk_out;
	
	assign s_axi_ddr_arid = 4'd0;
	assign s_axi_ddr_arlock = 1'b0;
	assign s_axi_ddr_arcache = 4'b0010;
	assign s_axi_ddr_arprot = 3'b000;
	assign s_axi_ddr_arqos = 4'b0000;
	assign s_axi_ddr_araddr = m_axi_nlv_araddr & (DMEM_ADDR_RANGE - 1);
	assign s_axi_ddr_arburst = m_axi_nlv_arburst;
	assign s_axi_ddr_arlen = m_axi_nlv_arlen;
	assign s_axi_ddr_arsize = m_axi_nlv_arsize;
	assign s_axi_ddr_arvalid = m_axi_nlv_arvalid;
	assign m_axi_nlv_arready = s_axi_ddr_arready;
	
	assign m_axi_nlv_rdata = s_axi_ddr_rdata;
	assign m_axi_nlv_rresp = s_axi_ddr_rresp;
	assign m_axi_nlv_rlast = s_axi_ddr_rlast;
	assign m_axi_nlv_rvalid = s_axi_ddr_rvalid;
	assign s_axi_ddr_rready = m_axi_nlv_rready;
	
	assign s_axi_ddr_awid = 4'd0;
	assign s_axi_ddr_awlock = 1'b0;
	assign s_axi_ddr_awcache = 4'b0010;
	assign s_axi_ddr_awprot = 3'b000;
	assign s_axi_ddr_awqos = 4'b0000;
	assign s_axi_ddr_awaddr = m_axi_nlv_awaddr & (DMEM_ADDR_RANGE - 1);
	assign s_axi_ddr_awburst = m_axi_nlv_awburst;
	assign s_axi_ddr_awlen = m_axi_nlv_awlen;
	assign s_axi_ddr_awsize = m_axi_nlv_awsize;
	assign s_axi_ddr_awvalid = m_axi_nlv_awvalid;
	assign m_axi_nlv_awready = s_axi_ddr_awready;
	
	assign m_axi_nlv_bresp = s_axi_ddr_bresp;
	assign m_axi_nlv_bvalid = s_axi_ddr_bvalid;
	assign s_axi_ddr_bready = m_axi_nlv_bready;
	
	assign s_axi_ddr_wdata = m_axi_nlv_wdata;
	assign s_axi_ddr_wstrb = m_axi_nlv_wstrb;
	assign s_axi_ddr_wlast = m_axi_nlv_wlast;
	assign s_axi_ddr_wvalid = m_axi_nlv_wvalid;
	assign m_axi_nlv_wready = s_axi_ddr_wready;
	
	mig_7series_0 mig_u(
		.ddr3_dq(ddr3_dq),
		.ddr3_dqs_n(ddr3_dqs_n),
		.ddr3_dqs_p(ddr3_dqs_p),
		.ddr3_addr(ddr3_addr),
		.ddr3_ba(ddr3_ba),
		.ddr3_ras_n(ddr3_ras_n),
		.ddr3_cas_n(ddr3_cas_n),
		.ddr3_we_n(ddr3_we_n),
		.ddr3_reset_n(ddr3_reset_n),
		.ddr3_ck_p(ddr3_ck_p),
		.ddr3_ck_n(ddr3_ck_n),
		.ddr3_cke(ddr3_cke),
		.ddr3_cs_n(ddr3_cs_n),
		.ddr3_dm(ddr3_dm),
		.ddr3_odt(ddr3_odt),
		
		.sys_clk_i(ddr3_clk),
		.clk_ref_i(ddr3_clk),
		.ui_clk(ddr3_ui_clk),
		.ui_clk_sync_rst(ddr3_ui_rst),
		.mmcm_locked(),
		.aresetn(ext_resetn),
		
		.app_sr_req(1'b0),
		.app_ref_req(1'b0),
		.app_zq_req(1'b0),
		.app_sr_active(),
		.app_ref_ack(),
		.app_zq_ack(),
		
		.s_axi_awid(s_axi_ddr_awid),
		.s_axi_awaddr(s_axi_ddr_awaddr),
		.s_axi_awlen(s_axi_ddr_awlen),
		.s_axi_awsize(s_axi_ddr_awsize),
		.s_axi_awburst(s_axi_ddr_awburst),
		.s_axi_awlock(s_axi_ddr_awlock),
		.s_axi_awcache(s_axi_ddr_awcache),
		.s_axi_awprot(s_axi_ddr_awprot),
		.s_axi_awqos(s_axi_ddr_awqos),
		.s_axi_awvalid(s_axi_ddr_awvalid),
		.s_axi_awready(s_axi_ddr_awready),
		
		.s_axi_wdata(s_axi_ddr_wdata),
		.s_axi_wstrb(s_axi_ddr_wstrb),
		.s_axi_wlast(s_axi_ddr_wlast),
		.s_axi_wvalid(s_axi_ddr_wvalid),
		.s_axi_wready(s_axi_ddr_wready),
		.s_axi_bready(s_axi_ddr_bready),
		.s_axi_bid(s_axi_ddr_bid),
		.s_axi_bresp(s_axi_ddr_bresp),
		.s_axi_bvalid(s_axi_ddr_bvalid),
		
		.s_axi_arid(s_axi_ddr_arid),
		.s_axi_araddr(s_axi_ddr_araddr),
		.s_axi_arlen(s_axi_ddr_arlen),
		.s_axi_arsize(s_axi_ddr_arsize),
		.s_axi_arburst(s_axi_ddr_arburst),
		.s_axi_arlock(s_axi_ddr_arlock),
		.s_axi_arcache(s_axi_ddr_arcache),
		.s_axi_arprot(s_axi_ddr_arprot),
		.s_axi_arqos(s_axi_ddr_arqos),
		.s_axi_arvalid(s_axi_ddr_arvalid),
		.s_axi_arready(s_axi_ddr_arready),
	
		.s_axi_rready(s_axi_ddr_rready),
		.s_axi_rid(s_axi_ddr_rid),
		.s_axi_rdata(s_axi_ddr_rdata),
		.s_axi_rresp(s_axi_ddr_rresp),
		.s_axi_rlast(s_axi_ddr_rlast),
		.s_axi_rvalid(s_axi_ddr_rvalid),
		
		.init_calib_complete(),
		.device_temp(),
		.sys_rst(ext_resetn)
	);
	
endmodule
