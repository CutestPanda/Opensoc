`timescale 1ns / 1ps
/********************************************************************
本模块: 基于小胖达RISC-V的SOC

描述:
存储映射 ->
	指令存储器 0x0000_0000~?           imem_depth
	数据存储器 0x1000_0000~?           dmem_depth
	APB-GPIO   0x4000_0000~0x4000_0FFF 4KB
	APB-I2C    0x4000_1000~0x4000_1FFF 4KB
	APB-TIMER  0x4000_2000~0x4000_2FFF 4KB

注意：
无

协议:
GPIO
I2C MASTER

作者: 陈家耀
日期: 2025/01/20
********************************************************************/


module panda_soc_top #(
	parameter integer imem_depth = 8192, // 指令存储器深度
	parameter integer dmem_depth = 8192, // 数据存储器深度
	parameter imem_init_file = "E:/scientific_research/risc-v/tube_scan.txt", // 指令存储器初始化文件路径
	parameter sgn_period_mul = "true", // 是否使用单周期乘法器
	parameter real simulation_delay = 0 // 仿真延时
)(
	// 时钟和复位
	input wire osc_clk, // 外部晶振时钟输入
	input wire ext_resetn, // 外部复位输入
	
	// GPIO0
	inout wire[21:0] gpio0,
	
	// I2C0
	inout wire i2c0_scl,
	inout wire i2c0_sda,
	
	// UART0
    output wire uart0_tx,
    input wire uart0_rx
);
	
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
	wire sys_resetn; // 系统复位输出
	wire sys_reset_req; // 系统复位请求
	
	panda_risc_v_reset #(
		.simulation_delay(simulation_delay)
	)panda_risc_v_reset_u(
		.clk(pll_clk_out),
		
		.ext_resetn(pll_locked),
		
		.sw_reset(1'b0),
		
		.sys_resetn(sys_resetn),
		.sys_reset_req(sys_reset_req)
	);
	
	/** 小胖达RISC-V 最小处理器系统 **/
	// 数据总线(AXI-Lite主机)
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
	// 中断请求
	// 注意: 中断请求保持有效直到中断清零!
	wire sw_itr_req; // 软件中断请求
	wire tmr_itr_req; // 计时器中断请求
	wire ext_itr_req; // 外部中断请求
	
	assign sw_itr_req = 1'b0;
	assign ext_itr_req = 1'b0;
	
	panda_risc_v_min_proc_sys #(
		.RST_PC(32'h0000_0000),
		.imem_access_timeout_th(16),
		.inst_addr_alignment_width(32),
		.dbus_access_timeout_th(32),
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
		.dmem_baseaddr(32'h1000_0000),
		.dmem_addr_range(dmem_depth * 4),
		.ext_baseaddr(32'h4000_0000),
		.ext_addr_range(16 * 4096),
		.en_inst_cmd_fwd("false"),
		.en_inst_rsp_bck("false"),
		.en_data_cmd_fwd("false"),
		.en_data_rsp_bck("false"),
		.imem_init_file(imem_init_file),
		.sgn_period_mul(sgn_period_mul),
		.simulation_delay(simulation_delay)
	)panda_risc_v_min_proc_sys_u(
		.clk(pll_clk_out),
		.sys_resetn(sys_resetn),
		
		.sys_reset_req(sys_reset_req),
		
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
		
		.ibus_timeout(),
		.dbus_timeout(),
		
		.sw_itr_req(sw_itr_req),
		.tmr_itr_req(tmr_itr_req),
		.ext_itr_req(ext_itr_req)
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
		.en_itr("false"),
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
		
		.gpio_itr()
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
		.channel_n(0),
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
		.cmp_out(),
		
		.itr(tmr_itr_req)
	);
	
	/** APB-UART **/
	apb_uart #(
		.clk_frequency_MHz(65),
		.baud_rate(115200),
		.tx_rx_fifo_ram_type("bram"),
		.tx_fifo_depth(2048),
		.rx_fifo_depth(2048),
		.en_itr("false"),
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
		
		.uart_itr()
	);
	
endmodule
