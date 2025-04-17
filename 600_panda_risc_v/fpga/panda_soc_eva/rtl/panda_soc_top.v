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
本模块: 基于小胖达RISC-V的SOC

描述:
存储映射 ->
	ITCM       0x0000_0000~?           imem_depth
	DTCM       0x1000_0000~?           dmem_depth
	APB-GPIO   0x4000_0000~0x4000_0FFF 4KB
	APB-I2C    0x4000_1000~0x4000_1FFF 4KB
	APB-TIMER  0x4000_2000~0x4000_2FFF 4KB
	APB-UART   0x4000_3000~0x4000_3FFF 4KB
	外部DRAM   0x6000_0000~0x6080_0000 8MB            经DCache缓存
	PLIC       0xF000_0000~0xF03F_FFFF 4MB
	CLINT      0xF400_0000~0xF7FF_FFFF 64MB
	调试模块   0xFFFF_F800~0xFFFF_FBFF 1KB

外部中断 -> 
	中断#1 GPIO0中断
	中断#2 TIMER0中断
	中断#3 UART0中断

可启用DTCM或DCache

注意：
指令存储器的前2KB为Boot程序

协议:
JTAG SLAVE
GPIO
I2C MASTER

作者: 陈家耀
日期: 2025/02/13
********************************************************************/


module panda_soc_top #(
	parameter EN_DCACHE = "false", // 是否使用DCACHE
	parameter EN_DTCM = "true", // 是否启用DTCM
	parameter integer DCACHE_WAY_N = 2, // 缓存路数(1 | 2 | 4 | 8)
	parameter integer DCACHE_ENTRY_N = 1024, // 缓存存储条目数
	parameter integer DCACHE_LINE_WORD_N = 2, // 每个缓存行的字数(1 | 2 | 4 | 8 | 16)
	parameter integer DCACHE_TAG_WIDTH = 10, // 缓存标签位数
	parameter integer DCACHE_WBUF_ITEM_N = 2, // 写缓存最多可存的缓存行个数(1~8)
	parameter integer imem_depth = 8192, // 指令存储器深度
	parameter integer dmem_depth = 8192, // 数据存储器深度
	parameter en_mem_byte_write = "false", // 是否使用RAM的字节使能信号
	parameter imem_init_file = "E:/scientific_research/risc-v/boot_rom.txt", // 指令存储器初始化文件路径
	parameter imem_init_file_b0 = "E:/scientific_research/risc-v/boot_rom_b0.txt", // 指令存储器初始化文件路径(字节#0)
	parameter imem_init_file_b1 = "E:/scientific_research/risc-v/boot_rom_b1.txt", // 指令存储器初始化文件路径(字节#1)
	parameter imem_init_file_b2 = "E:/scientific_research/risc-v/boot_rom_b2.txt", // 指令存储器初始化文件路径(字节#2)
	parameter imem_init_file_b3 = "E:/scientific_research/risc-v/boot_rom_b3.txt", // 指令存储器初始化文件路径(字节#3)
	parameter sgn_period_mul = "true", // 是否使用单周期乘法器
	parameter uart_prog_supported = "true", // 是否支持UART编程烧录
	parameter real simulation_delay = 0 // 仿真延时
)(
	// 时钟和复位
	input wire osc_clk, // 外部晶振时钟输入
	input wire ext_resetn, // 外部复位输入
	
	// JTAG从机
	input wire tck,
	input wire trst_n,
	input wire tms,
	input wire tdi,
	output wire tdo,
	
	// BOOT模式(1'b0 -> UART编程, 1'b1 -> 正常运行)
	input wire boot,
	
	// GPIO0
	inout wire[21:0] gpio0,
	
	// I2C0
	inout wire i2c0_scl,
	inout wire i2c0_sda,
	
	// UART0
    output wire uart0_tx,
    input wire uart0_rx,
    
    // PWM输出
    output wire pwm0_o
);
	
	/** 内部配置 **/
	localparam integer clk_frequency_MHz = 50; // 时钟频率(以MHz计)
	localparam integer PROC_SYS_RST_WAIT_N = 300 * 1000 / (1000 / clk_frequency_MHz); // 处理器系统复位释放等待周期数
	
	/** PLL **/
	wire pll_clk_in;
	wire pll_resetn;
	wire pll_clk_out;
	wire pll_locked;
	
	generate
		if(simulation_delay == 0)
		begin
			assign pll_clk_in = osc_clk;
			assign pll_resetn = ext_resetn;
			
			clk_wiz_0 pll_u(
			   .clk_in1(pll_clk_in),
			   .resetn(pll_resetn),
			   
			   .clk_out1(pll_clk_out),
			   .locked(pll_locked)
			);
		end
		else
		begin
			assign pll_clk_in = osc_clk;
			assign pll_resetn = ext_resetn;
			
			assign pll_clk_out = pll_clk_in;
			assign pll_locked = pll_resetn;
		end
	endgenerate
	
	/** 复位处理 **/
	wire sw_reset; // 软件服务请求
	wire sys_resetn; // 系统复位输出
	wire sys_reset_req; // 系统复位请求
	wire sys_reset_fns; // 系统复位完成
	reg[15:0] proc_sys_rst_wait_cnt; // 处理器系统复位释放等待计数器
	reg proc_sys_rst_n; // 处理器系统复位信号
	
	panda_risc_v_reset #(
		.simulation_delay(simulation_delay)
	)panda_risc_v_reset_u(
		.clk(pll_clk_out),
		
		.ext_resetn(proc_sys_rst_n),
		
		.sw_reset(sw_reset),
		
		.sys_resetn(sys_resetn),
		.sys_reset_req(sys_reset_req),
		.sys_reset_fns(sys_reset_fns)
	);
	
	// 处理器系统复位释放等待计数器
	always @(posedge pll_clk_out or negedge pll_locked)
	begin
		if(~pll_locked)
			proc_sys_rst_wait_cnt <= 16'd0;
		else if(~proc_sys_rst_n)
			proc_sys_rst_wait_cnt <= # simulation_delay proc_sys_rst_wait_cnt + 16'd1;
	end
	
	// 处理器系统复位信号
	always @(posedge pll_clk_out or negedge pll_locked)
	begin
		if(~pll_locked)
			proc_sys_rst_n <= 1'b0;
		else if(~proc_sys_rst_n)
			proc_sys_rst_n <= # simulation_delay proc_sys_rst_wait_cnt == (PROC_SYS_RST_WAIT_N - 1);
	end
	
	/** 调试机制 **/
	// DMI
    wire[8:0] dmi_paddr;
    wire dmi_psel;
    wire dmi_penable;
    wire dmi_pwrite;
    wire[31:0] dmi_pwdata;
    wire dmi_pready;
    wire[31:0] dmi_prdata;
    wire dmi_pslverr;
	// 复位控制
	wire dbg_sys_reset_req;
	wire dbg_hart_reset_req;
	// HART暂停请求
	wire dbg_halt_req; // 来自调试器的暂停请求
	wire dbg_halt_on_reset_req; // 来自调试器的复位释放后暂停请求
	// HART对DM内容的访问(存储器从接口)
	wire hart_access_en;
	wire[3:0] hart_access_wen;
	wire[29:0] hart_access_addr;
	wire[31:0] hart_access_din;
	wire[31:0] hart_access_dout;
	
	assign sw_reset = dbg_sys_reset_req | dbg_hart_reset_req;
	
	jtag_dtm #(
		.JTAG_VERSION(4'h1),
		.DTMCS_IDLE_HINT(3'd5),
		.ABITS(7),
		.SYN_STAGE(2),
		.SIM_DELAY(simulation_delay)
	)jtag_dtm_u(
		.tck(tck),
		.trst_n(trst_n),
		.tms(tms),
		.tdi(tdi),
		.tdo(tdo),
		.tdo_oen(),
		
		.m_apb_aclk(pll_clk_out),
		.m_apb_aresetn(proc_sys_rst_n),
		
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
	
	jtag_dm #(
		.ABITS(7),
		.HARTS_N(1),
		.SCRATCH_N(2),
		.SBUS_SUPPORTED("false"),
		.NEXT_DM_ADDR(32'h0000_0000),
		.PROGBUF_SIZE(2),
		.DATA0_ADDR(32'hFFFF_F800),
		.PROGBUF0_ADDR(32'hFFFF_F900),
		.HART_ACMD_CTRT_ADDR(32'hFFFF_FA00),
		.SIM_DELAY(simulation_delay)
	)jtag_dm_u(
		.clk(pll_clk_out),
		.rst_n(proc_sys_rst_n),
		
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
		
		.hart_access_en(hart_access_en),
		.hart_access_wen(hart_access_wen),
		.hart_access_addr(hart_access_addr),
		.hart_access_din(hart_access_din),
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
	
	/** 小胖达RISC-V 最小处理器系统 **/
	// 复位时的PC
	reg[31:0] rst_pc;
	// 扩展外设总线(AXI-Lite主机)
	// 读地址通道
    wire[31:0] m_axi_dbus_araddr;
	wire[1:0] m_axi_dbus_arburst; // const -> 2'b01(INCR)
	wire[7:0] m_axi_dbus_arlen; // const -> 8'd0
    wire[2:0] m_axi_dbus_arsize; // const -> 3'b010
	wire[3:0] m_axi_dbus_arcache; // const -> 4'b0011
    wire m_axi_dbus_arvalid;
    wire m_axi_dbus_arready;
    // 写地址通道
    wire[31:0] m_axi_dbus_awaddr;
    wire[1:0] m_axi_dbus_awburst; // const -> 2'b01(INCR)
	wire[7:0] m_axi_dbus_awlen; // const -> 8'd0
    wire[2:0] m_axi_dbus_awsize; // const -> 3'b010
	wire[3:0] m_axi_dbus_awcache; // const -> 4'b0011
    wire m_axi_dbus_awvalid;
    wire m_axi_dbus_awready;
    // 写响应通道
    wire[1:0] m_axi_dbus_bresp;
    wire m_axi_dbus_bvalid;
    wire m_axi_dbus_bready;
    // 读数据通道
    wire[31:0] m_axi_dbus_rdata;
    wire[1:0] m_axi_dbus_rresp;
	wire m_axi_dbus_rlast; // ignored
    wire m_axi_dbus_rvalid;
    wire m_axi_dbus_rready;
    // 写数据通道
    wire[31:0] m_axi_dbus_wdata;
    wire[3:0] m_axi_dbus_wstrb;
	wire m_axi_dbus_wlast; // const -> 1'b1
    wire m_axi_dbus_wvalid;
    wire m_axi_dbus_wready;
	// 数据Cache总线(AXI-Lite主机)
	// 读地址通道
    wire[31:0] m_axi_dcache_araddr;
	wire[1:0] m_axi_dcache_arburst; // const -> 2'b01(INCR)
	wire[7:0] m_axi_dcache_arlen; // const -> 8'd0
    wire[2:0] m_axi_dcache_arsize; // const -> 3'b010
	wire[3:0] m_axi_dcache_arcache; // const -> 4'b0011
    wire m_axi_dcache_arvalid;
    wire m_axi_dcache_arready;
    // 写地址通道
    wire[31:0] m_axi_dcache_awaddr;
    wire[1:0] m_axi_dcache_awburst; // const -> 2'b01(INCR)
	wire[7:0] m_axi_dcache_awlen; // const -> 8'd0
    wire[2:0] m_axi_dcache_awsize; // const -> 3'b010
	wire[3:0] m_axi_dcache_awcache; // const -> 4'b0011
    wire m_axi_dcache_awvalid;
    wire m_axi_dcache_awready;
    // 写响应通道
    wire[1:0] m_axi_dcache_bresp;
    wire m_axi_dcache_bvalid;
    wire m_axi_dcache_bready;
    // 读数据通道
    wire[31:0] m_axi_dcache_rdata;
    wire[1:0] m_axi_dcache_rresp;
	wire m_axi_dcache_rlast; // ignored
    wire m_axi_dcache_rvalid;
    wire m_axi_dcache_rready;
    // 写数据通道
    wire[31:0] m_axi_dcache_wdata;
    wire[3:0] m_axi_dcache_wstrb;
	wire m_axi_dcache_wlast; // const -> 1'b1
    wire m_axi_dcache_wvalid;
    wire m_axi_dcache_wready;
	// 中断请求
	// 注意: 中断请求保持有效直到中断清零!
	wire sw_itr_req; // 软件中断请求
	wire tmr_itr_req; // 计时器中断请求
	wire[62:0] ext_itr_req_vec; // 外部中断请求向量
	// 外部中断
	wire gpio0_itr_req; // GPIO0中断
	wire timer0_itr_req; // TIMER0中断
	wire uart0_itr_req; // UART0中断
	
	/*
	说明: 已经引出外部存储器AXI主机(m_axi_dcache_xxx), 该地址区域已经DCache缓存, 
	      如将参数EN_DCACHE设为"true", 则可将这个AXI主机连接到DRAM控制器
	*/
	
	assign sw_itr_req = 1'b0;
	assign tmr_itr_req = 1'b0;
	assign ext_itr_req_vec = {
		60'd0, 
		uart0_itr_req, 
		timer0_itr_req, 
		gpio0_itr_req
	};
	
	// 复位时的PC
	always @(posedge pll_clk_out)
	begin
		rst_pc <= # simulation_delay ((uart_prog_supported == "true") & boot) ? 32'h0000_0800:32'h0000_0000;
	end
	
	// 小胖达RISC-V最小处理器系统
	panda_risc_v_min_proc_sys #(
		.EN_DCACHE(EN_DCACHE),
		.EN_DTCM(EN_DTCM),
		.DCACHE_WAY_N(DCACHE_WAY_N),
		.DCACHE_ENTRY_N(DCACHE_ENTRY_N),
		.DCACHE_LINE_WORD_N(DCACHE_LINE_WORD_N),
		.DCACHE_TAG_WIDTH(DCACHE_TAG_WIDTH),
		.DCACHE_WBUF_ITEM_N(DCACHE_WBUF_ITEM_N),
		.imem_access_timeout_th(16),
		.inst_addr_alignment_width(32),
		.dbus_access_timeout_th(64),
		.icb_zero_latency_supported("false"),
		.en_expt_vec_vectored("false"),
		.en_performance_monitor("true"),
		.init_mtvec_base(30'd0),
		.init_mcause_interrupt(1'b0),
		.init_mcause_exception_code(31'd16),
		.init_misa_mxl(2'b01),
		.init_misa_extensions(26'b00_0000_0000_0001_0001_0000_0000),
		.init_mvendorid_bank(25'h0_00_00_00),
		.init_mvendorid_offset(7'h00),
		.init_marchid(32'h00_00_00_00),
		.init_mimpid(32'h31_2E_30_30),
		.init_mhartid(32'h00_00_00_00),
		.dpc_trace_inst_n(16),
		.inst_id_width(5),
		.en_alu_csr_rw_bypass("true"),
		.imem_baseaddr(32'h0000_0000),
		.imem_addr_range(imem_depth * 4),
		.dm_regs_baseaddr(32'hFFFF_F800),
		.dm_regs_addr_range(1024),
		.dmem_baseaddr(32'h1000_0000),
		.dmem_addr_range(dmem_depth * 4),
		.plic_baseaddr(32'hF000_0000),
		.plic_addr_range(4 * 1024 * 1024),
		.clint_baseaddr(32'hF400_0000),
		.clint_addr_range(64 * 1024 * 1024),
		.ext_peripheral_baseaddr(32'h4000_0000),
		.ext_peripheral_addr_range(16 * 4096),
		.ext_mem_baseaddr(32'h6000_0000),
		.ext_mem_addr_range(8 * 1024 * 1024),
		.en_inst_cmd_fwd("false"),
		.en_inst_rsp_bck("false"),
		.en_data_cmd_fwd("true"),
		.en_data_rsp_bck("true"),
		.en_mem_byte_write(en_mem_byte_write),
		.imem_init_file(imem_init_file),
		.imem_init_file_b0(imem_init_file_b0),
		.imem_init_file_b1(imem_init_file_b1),
		.imem_init_file_b2(imem_init_file_b2),
		.imem_init_file_b3(imem_init_file_b3),
		.sgn_period_mul(sgn_period_mul),
		.rtc_psc_r(50 * 1000),
		.debug_supported("true"),
		.DEBUG_ROM_ADDR(32'h0000_0600),
		.dscratch_n(2),
		.simulation_delay(simulation_delay)
	)panda_risc_v_min_proc_sys_u(
		.clk(pll_clk_out),
		.sys_resetn(sys_resetn),
		
		.sys_reset_req(sys_reset_req),
		
		.rst_pc(rst_pc),
		
		.rtc_en(1'b1),
		
		.m_axi_dbus_araddr(m_axi_dbus_araddr),
		.m_axi_dbus_arburst(m_axi_dbus_arburst),
		.m_axi_dbus_arlen(m_axi_dbus_arlen),
		.m_axi_dbus_arsize(m_axi_dbus_arsize),
		.m_axi_dbus_arcache(m_axi_dbus_arcache),
		.m_axi_dbus_arvalid(m_axi_dbus_arvalid),
		.m_axi_dbus_arready(m_axi_dbus_arready),
		.m_axi_dbus_awaddr(m_axi_dbus_awaddr),
		.m_axi_dbus_awburst(m_axi_dbus_awburst),
		.m_axi_dbus_awlen(m_axi_dbus_awlen),
		.m_axi_dbus_awsize(m_axi_dbus_awsize),
		.m_axi_dbus_awcache(m_axi_dbus_awcache),
		.m_axi_dbus_awvalid(m_axi_dbus_awvalid),
		.m_axi_dbus_awready(m_axi_dbus_awready),
		.m_axi_dbus_bresp(m_axi_dbus_bresp),
		.m_axi_dbus_bvalid(m_axi_dbus_bvalid),
		.m_axi_dbus_bready(m_axi_dbus_bready),
		.m_axi_dbus_rdata(m_axi_dbus_rdata),
		.m_axi_dbus_rresp(m_axi_dbus_rresp),
		.m_axi_dbus_rlast(m_axi_dbus_rlast),
		.m_axi_dbus_rvalid(m_axi_dbus_rvalid),
		.m_axi_dbus_rready(m_axi_dbus_rready),
		.m_axi_dbus_wdata(m_axi_dbus_wdata),
		.m_axi_dbus_wstrb(m_axi_dbus_wstrb),
		.m_axi_dbus_wlast(m_axi_dbus_wlast),
		.m_axi_dbus_wvalid(m_axi_dbus_wvalid),
		.m_axi_dbus_wready(m_axi_dbus_wready),
		
		.m_axi_dcache_araddr(m_axi_dcache_araddr),
		.m_axi_dcache_arburst(m_axi_dcache_arburst),
		.m_axi_dcache_arlen(m_axi_dcache_arlen),
		.m_axi_dcache_arsize(m_axi_dcache_arsize),
		.m_axi_dcache_arcache(m_axi_dcache_arcache),
		.m_axi_dcache_arvalid(m_axi_dcache_arvalid),
		.m_axi_dcache_arready(m_axi_dcache_arready),
		.m_axi_dcache_awaddr(m_axi_dcache_awaddr),
		.m_axi_dcache_awburst(m_axi_dcache_awburst),
		.m_axi_dcache_awlen(m_axi_dcache_awlen),
		.m_axi_dcache_awsize(m_axi_dcache_awsize),
		.m_axi_dcache_awcache(m_axi_dcache_awcache),
		.m_axi_dcache_awvalid(m_axi_dcache_awvalid),
		.m_axi_dcache_awready(m_axi_dcache_awready),
		.m_axi_dcache_bresp(m_axi_dcache_bresp),
		.m_axi_dcache_bvalid(m_axi_dcache_bvalid),
		.m_axi_dcache_bready(m_axi_dcache_bready),
		.m_axi_dcache_rdata(m_axi_dcache_rdata),
		.m_axi_dcache_rresp(m_axi_dcache_rresp),
		.m_axi_dcache_rlast(m_axi_dcache_rlast),
		.m_axi_dcache_rvalid(m_axi_dcache_rvalid),
		.m_axi_dcache_rready(m_axi_dcache_rready),
		.m_axi_dcache_wdata(m_axi_dcache_wdata),
		.m_axi_dcache_wstrb(m_axi_dcache_wstrb),
		.m_axi_dcache_wlast(m_axi_dcache_wlast),
		.m_axi_dcache_wvalid(m_axi_dcache_wvalid),
		.m_axi_dcache_wready(m_axi_dcache_wready),
		
		.ibus_timeout(),
		.dbus_timeout(),
		
		.ext_itr_req_vec(ext_itr_req_vec),
		
		.hart_access_en(hart_access_en),
		.hart_access_wen(hart_access_wen),
		.hart_access_addr(hart_access_addr),
		.hart_access_din(hart_access_din),
		.hart_access_dout(hart_access_dout),
		
		.dbg_halt_req(dbg_halt_req),
		.dbg_halt_on_reset_req(dbg_halt_on_reset_req)
	);
	
	/** AXI-APB桥 **/
	// AXI-Lite从机
    // 读地址通道
    wire[31:0] s_axi_bridge_araddr;
    wire[2:0] s_axi_bridge_arprot;
    wire s_axi_bridge_arvalid;
    wire s_axi_bridge_arready;
    // 写地址通道
    wire[31:0] s_axi_bridge_awaddr;
    wire[2:0] s_axi_bridge_awprot;
    wire s_axi_bridge_awvalid;
    wire s_axi_bridge_awready;
    // 写响应通道
    wire[1:0] s_axi_bridge_bresp;
    wire s_axi_bridge_bvalid;
    wire s_axi_bridge_bready;
    // 读数据通道
    wire[31:0] s_axi_bridge_rdata;
    wire[1:0] s_axi_bridge_rresp;
    wire s_axi_bridge_rvalid;
    wire s_axi_bridge_rready;
    // 写数据通道
    wire[31:0] s_axi_bridge_wdata;
    wire[3:0] s_axi_bridge_wstrb;
    wire s_axi_bridge_wvalid;
    wire s_axi_bridge_wready;
	// APB MASTER #0
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
    // APB MASTER #1
    wire[31:0] m1_apb_paddr;
    wire m1_apb_penable;
    wire m1_apb_pwrite;
    wire[2:0] m1_apb_pprot;
    wire m1_apb_psel;
    wire[3:0] m1_apb_pstrb;
    wire[31:0] m1_apb_pwdata;
    wire m1_apb_pready;
    wire m1_apb_pslverr;
    wire[31:0] m1_apb_prdata;
    // APB MASTER #2
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
	// APB MASTER #3
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
	
	assign s_axi_bridge_araddr = m_axi_dbus_araddr;
	assign s_axi_bridge_arprot = 3'b000;
	assign s_axi_bridge_arvalid = m_axi_dbus_arvalid;
	assign m_axi_dbus_arready = s_axi_bridge_arready;
	
	assign s_axi_bridge_awaddr = m_axi_dbus_awaddr;
	assign s_axi_bridge_awprot = 3'b000;
	assign s_axi_bridge_awvalid = m_axi_dbus_awvalid;
	assign m_axi_dbus_awready = s_axi_bridge_awready;
	
	assign m_axi_dbus_bresp = s_axi_bridge_bresp;
	assign m_axi_dbus_bvalid = s_axi_bridge_bvalid;
	assign s_axi_bridge_bready = m_axi_dbus_bready;
	
	assign m_axi_dbus_rdata = s_axi_bridge_rdata;
	assign m_axi_dbus_rresp = s_axi_bridge_rresp;
	assign m_axi_dbus_rlast = 1'b1;
	assign m_axi_dbus_rvalid = s_axi_bridge_rvalid;
	assign s_axi_bridge_rready = m_axi_dbus_rready;
	
	assign s_axi_bridge_wdata = m_axi_dbus_wdata;
	assign s_axi_bridge_wstrb = m_axi_dbus_wstrb;
	assign s_axi_bridge_wvalid = m_axi_dbus_wvalid;
	assign m_axi_dbus_wready = s_axi_bridge_wready;
	
	axi_apb_bridge_wrapper #(
		.apb_slave_n(4),
		
		.apb_s0_baseaddr(32'h4000_0000),
		.apb_s0_range(4096),
		.apb_s1_baseaddr(32'h4000_1000),
		.apb_s1_range(4096),
		.apb_s2_baseaddr(32'h4000_2000),
		.apb_s2_range(4096),
		.apb_s3_baseaddr(32'h4000_3000),
		.apb_s3_range(4096),
		
		.simulation_delay(simulation_delay)
	)axi_apb_bridge_wrapper_u(
		.clk(pll_clk_out),
		.rst_n(sys_resetn),
		
		.s_axi_araddr(s_axi_bridge_araddr),
		.s_axi_arprot(s_axi_bridge_arprot),
		.s_axi_arvalid(s_axi_bridge_arvalid),
		.s_axi_arready(s_axi_bridge_arready),
		.s_axi_awaddr(s_axi_bridge_awaddr),
		.s_axi_awprot(s_axi_bridge_awprot),
		.s_axi_awvalid(s_axi_bridge_awvalid),
		.s_axi_awready(s_axi_bridge_awready),
		.s_axi_bresp(s_axi_bridge_bresp),
		.s_axi_bvalid(s_axi_bridge_bvalid),
		.s_axi_bready(s_axi_bridge_bready),
		.s_axi_rdata(s_axi_bridge_rdata),
		.s_axi_rresp(s_axi_bridge_rresp),
		.s_axi_rvalid(s_axi_bridge_rvalid),
		.s_axi_rready(s_axi_bridge_rready),
		.s_axi_wdata(s_axi_bridge_wdata),
		.s_axi_wstrb(s_axi_bridge_wstrb),
		.s_axi_wvalid(s_axi_bridge_wvalid),
		.s_axi_wready(s_axi_bridge_wready),
		
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
		
		.m1_apb_paddr(m1_apb_paddr),
		.m1_apb_penable(m1_apb_penable),
		.m1_apb_pwrite(m1_apb_pwrite),
		.m1_apb_pprot(m1_apb_pprot),
		.m1_apb_psel(m1_apb_psel),
		.m1_apb_pstrb(m1_apb_pstrb),
		.m1_apb_pwdata(m1_apb_pwdata),
		.m1_apb_pready(m1_apb_pready),
		.m1_apb_pslverr(m1_apb_pslverr),
		.m1_apb_prdata(m1_apb_prdata),
		
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
		.m3_apb_prdata(m3_apb_prdata)
	);
	
	/** APB-GPIO **/
	// GPIO
    wire[21:0] gpio_o;
    wire[21:0] gpio_t; // 0->输出, 1->输入
    wire[21:0] gpio_i;
	
	genvar gpio0_i;
	generate
		for(gpio0_i = 0;gpio0_i < 22;gpio0_i = gpio0_i + 1)
		begin
			assign gpio0[gpio0_i] = gpio_t[gpio0_i] ? 1'bz:gpio_o[gpio0_i];
			assign gpio_i[gpio0_i] = gpio0[gpio0_i];
		end
	endgenerate
	
	apb_gpio #(
		.gpio_width(22),
		.gpio_dire("inout"),
		.default_output_value(32'h0000_0000),
		.default_tri_value(32'hffff_ffff),
		.en_itr("true"),
		.itr_edge("neg"),
		.simulation_delay(simulation_delay)
	)apb_gpio_u(
		.clk(pll_clk_out),
		.resetn(sys_resetn),
		
		.paddr(m0_apb_paddr),
		.psel(m0_apb_psel),
		.penable(m0_apb_penable),
		.pwrite(m0_apb_pwrite),
		.pwdata(m0_apb_pwdata),
		.pready_out(m0_apb_pready),
		.prdata_out(m0_apb_prdata),
		.pslverr_out(m0_apb_pslverr),
		
		.gpio_o(gpio_o),
		.gpio_t(gpio_t),
		.gpio_i(gpio_i),
		
		.gpio_itr(gpio0_itr_req)
	);
	
	/** APB-I2C **/
	// I2C主机接口
    // scl
    wire scl_t; // 1'b1为输入, 1'b0为输出
    wire scl_i;
    wire scl_o;
    // sda
    wire sda_t; // 1'b1为输入, 1'b0为输出
    wire sda_i;
    wire sda_o;
	
	assign i2c0_scl = scl_t ? 1'bz:scl_o;
	assign scl_i = i2c0_scl;
	
	assign i2c0_sda = sda_t ? 1'bz:sda_o;
	assign sda_i = i2c0_sda;
	
	apb_i2c #(
		.addr_bits_n(7),
		.en_i2c_rx("true"),
		.tx_rx_fifo_ram_type("bram"),
		.tx_fifo_depth(2048),
		.rx_fifo_depth(2048),
		.simulation_delay(simulation_delay)
	)apb_i2c_u(
		.clk(pll_clk_out),
		.resetn(sys_resetn),
		
		.paddr(m1_apb_paddr),
		.psel(m1_apb_psel),
		.penable(m1_apb_penable),
		.pwrite(m1_apb_pwrite),
		.pwdata(m1_apb_pwdata),
		.pready_out(m1_apb_pready),
		.prdata_out(m1_apb_prdata),
		.pslverr_out(m1_apb_pslverr),
		
		.scl_t(scl_t),
		.scl_i(scl_i),
		.scl_o(scl_o),
		
		.sda_t(sda_t),
		.sda_i(sda_i),
		.sda_o(sda_o),
		
		.itr()
	);
	
	/** APB-TIMER **/
	apb_timer #(
		.timer_width(16),
		.channel_n(1),
		.simulation_delay(simulation_delay)
	)apb_timer_u(
		.clk(pll_clk_out),
		.resetn(sys_resetn),
		
		.paddr(m2_apb_paddr),
		.psel(m2_apb_psel),
		.penable(m2_apb_penable),
		.pwrite(m2_apb_pwrite),
		.pwdata(m2_apb_pwdata),
		.pready_out(m2_apb_pready),
		.prdata_out(m2_apb_prdata),
		.pslverr_out(m2_apb_pslverr),
		
		.cap_in(4'b0000),
		.cmp_out(pwm0_o),
		
		.itr(timer0_itr_req)
	);
	
	/** APB-UART **/
	apb_uart #(
		.clk_frequency_MHz(clk_frequency_MHz),
		.baud_rate(115200),
		.tx_rx_fifo_ram_type("bram"),
		.tx_fifo_depth(2048),
		.rx_fifo_depth(4096),
		.en_itr("true"),
		.simulation_delay(simulation_delay)
	)apb_uart_u(
		.clk(pll_clk_out),
		.resetn(sys_resetn),
		
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
		
		.uart_itr(uart0_itr_req)
	);
	
endmodule
