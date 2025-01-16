`timescale 1ns / 1ps
/********************************************************************
本模块: 小胖达RISC-V 最小处理器系统

描述:
将小胖达RISC-V的指令总线接到ICB-SRAM控制器, 并接入指令存储器
将小胖达RISC-V的数据总线接到ICB到AXI-Lite桥, 引出AXI-Lite主机

注意：
无

协议:
AXI-Lite MASTER

作者: 陈家耀
日期: 2025/01/16
********************************************************************/


module panda_risc_v_min_proc_sys #(
	// 复位时的PC
	parameter RST_PC = 32'h0000_0000,
	// 指令总线控制单元配置
	parameter integer imem_access_timeout_th = 16, // 指令总线访问超时周期数(必须>=1)
	parameter integer inst_addr_alignment_width = 32, // 指令地址对齐位宽(16 | 32)
	// LSU配置
	parameter integer dbus_access_timeout_th = 16, // 数据总线访问超时周期数(必须>=1)
	parameter icb_zero_latency_supported = "false", // 是否支持零响应时延的ICB主机
	// CSR配置
	parameter en_expt_vec_vectored = "true", // 是否使能异常处理的向量链接模式
	parameter en_performance_monitor = "true", // 是否使能性能监测相关的CSR
	parameter init_mtvec_base = 30'd0, // mtvec状态寄存器BASE域复位值
	parameter init_mcause_interrupt = 1'b0, // mcause状态寄存器Interrupt域复位值
	parameter init_mcause_exception_code = 31'd16, // mcause状态寄存器Exception Code域复位值
	parameter init_misa_mxl = 2'b01, // misa状态寄存器MXL域复位值
	parameter init_misa_extensions = 26'b00_0000_0000_0001_0001_0000_0000, // misa状态寄存器Extensions域复位值
	parameter init_mvendorid_bank = 25'h0_00_00_00, // mvendorid状态寄存器Bank域复位值
	parameter init_mvendorid_offset = 7'h00, // mvendorid状态寄存器Offset域复位值
	parameter init_marchid = 32'h00_00_00_00, // marchid状态寄存器复位值
	parameter init_mimpid = 32'h31_2E_30_30, // mimpid状态寄存器复位值
	parameter init_mhartid = 32'h00_00_00_00, // mhartid状态寄存器复位值
	// 数据相关性监测器配置
	parameter integer dpc_trace_inst_n = 4, // 执行数据相关性跟踪的指令条数
	parameter integer inst_id_width = 4, // 指令编号的位宽
	parameter en_alu_csr_rw_bypass = "true", // 是否使能ALU/CSR原子读写单元的数据旁路
	// 总线控制单元配置
	parameter imem_baseaddr = 32'h0000_0000, // 指令存储器基址
	parameter integer imem_addr_range = 16 * 1024, // 指令存储器地址区间长度
	// 指令/数据ICB主机AXIS寄存器片配置
	parameter en_inst_cmd_fwd = "true", // 使能指令ICB主机命令通道前向寄存器
	parameter en_inst_rsp_bck = "true", // 使能指令ICB主机响应通道后向寄存器
	parameter en_data_cmd_fwd = "true", // 使能数据ICB主机命令通道前向寄存器
	parameter en_data_rsp_bck = "true", // 使能数据ICB主机响应通道后向寄存器
	// 指令存储器配置
	parameter integer imem_depth = 4096, // 指令存储器深度
	parameter imem_init_file = "no_init", // 指令存储器初始化文件路径
	// 仿真配置
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟
	input wire clk,
	// 系统复位输入
	input wire sys_resetn,
	
	// 系统复位请求
	input wire sys_reset_req,
	
	// 数据总线(AXI-Lite主机)
	// 读地址通道
    output wire[31:0] m_axi_dbus_araddr,
	output wire[1:0] m_axi_dbus_arburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_dbus_arlen, // const -> 8'd0
    output wire[2:0] m_axi_dbus_arsize, // const -> 3'b010
	output wire[3:0] m_axi_dbus_arcache, // const -> 4'b0011
    output wire m_axi_dbus_arvalid,
    input wire m_axi_dbus_arready,
    // 写地址通道
    output wire[31:0] m_axi_dbus_awaddr,
    output wire[1:0] m_axi_dbus_awburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_dbus_awlen, // const -> 8'd0
    output wire[2:0] m_axi_dbus_awsize, // const -> 3'b010
	output wire[3:0] m_axi_dbus_awcache, // const -> 4'b0011
    output wire m_axi_dbus_awvalid,
    input wire m_axi_dbus_awready,
    // 写响应通道
    // 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
    input wire[1:0] m_axi_dbus_bresp,
    input wire m_axi_dbus_bvalid,
    output wire m_axi_dbus_bready,
    // 读数据通道
    input wire[31:0] m_axi_dbus_rdata,
    // 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
    input wire[1:0] m_axi_dbus_rresp,
	input wire m_axi_dbus_rlast, // ignored
    input wire m_axi_dbus_rvalid,
    output wire m_axi_dbus_rready,
    // 写数据通道
    output wire[31:0] m_axi_dbus_wdata,
    output wire[3:0] m_axi_dbus_wstrb,
	output wire m_axi_dbus_wlast, // const -> 1'b1
    output wire m_axi_dbus_wvalid,
    input wire m_axi_dbus_wready,
	
	// 指令总线访问超时标志
	output wire ibus_timeout,
	// 数据总线访问超时标志
	output wire dbus_timeout,
	
	// 中断请求
	// 注意: 中断请求保持有效直到中断清零!
	input wire sw_itr_req, // 软件中断请求
	input wire tmr_itr_req, // 计时器中断请求
	input wire ext_itr_req // 外部中断请求
);
	
	/** 小胖达RISC-V CPU核 **/
	// 指令ICB主机
	wire[31:0] m_icb_cmd_inst_addr;
	wire m_icb_cmd_inst_read;
	wire[31:0] m_icb_cmd_inst_wdata;
	wire[3:0] m_icb_cmd_inst_wmask;
	wire m_icb_cmd_inst_valid;
	wire m_icb_cmd_inst_ready;
	wire[31:0] m_icb_rsp_inst_rdata;
	wire m_icb_rsp_inst_err;
	wire m_icb_rsp_inst_valid;
	wire m_icb_rsp_inst_ready;
	// 数据ICB主机
	wire[31:0] m_icb_cmd_data_addr;
	wire m_icb_cmd_data_read;
	wire[31:0] m_icb_cmd_data_wdata;
	wire[3:0] m_icb_cmd_data_wmask;
	wire m_icb_cmd_data_valid;
	wire m_icb_cmd_data_ready;
	wire[31:0] m_icb_rsp_data_rdata;
	wire m_icb_rsp_data_err;
	wire m_icb_rsp_data_valid;
	wire m_icb_rsp_data_ready;
	
	panda_risc_v #(
		.RST_PC(RST_PC),
		.imem_access_timeout_th(imem_access_timeout_th),
		.inst_addr_alignment_width(inst_addr_alignment_width),
		.dbus_access_timeout_th(dbus_access_timeout_th),
		.icb_zero_latency_supported(icb_zero_latency_supported),
		.en_expt_vec_vectored(en_expt_vec_vectored),
		.en_performance_monitor(en_performance_monitor),
		.init_mtvec_base(init_mtvec_base),
		.init_mcause_interrupt(init_mcause_interrupt),
		.init_mcause_exception_code(init_mcause_exception_code),
		.init_misa_mxl(init_misa_mxl),
		.init_misa_extensions(init_misa_extensions),
		.init_mvendorid_bank(init_mvendorid_bank),
		.init_mvendorid_offset(init_mvendorid_offset),
		.init_marchid(init_marchid),
		.init_mimpid(init_mimpid),
		.init_mhartid(init_mhartid),
		.dpc_trace_inst_n(dpc_trace_inst_n),
		.inst_id_width(inst_id_width),
		.en_alu_csr_rw_bypass(en_alu_csr_rw_bypass),
		.imem_baseaddr(imem_baseaddr),
		.imem_addr_range(imem_addr_range),
		.en_inst_cmd_fwd(en_inst_cmd_fwd),
		.en_inst_rsp_bck(en_inst_rsp_bck),
		.en_data_cmd_fwd(en_data_cmd_fwd),
		.en_data_rsp_bck(en_data_rsp_bck),
		.simulation_delay(simulation_delay)
	)panda_risc_v_u(
		.clk(clk),
		.sys_resetn(sys_resetn),
		
		.sys_reset_req(sys_reset_req),
		
		.m_icb_cmd_inst_addr(m_icb_cmd_inst_addr),
		.m_icb_cmd_inst_read(m_icb_cmd_inst_read),
		.m_icb_cmd_inst_wdata(m_icb_cmd_inst_wdata),
		.m_icb_cmd_inst_wmask(m_icb_cmd_inst_wmask),
		.m_icb_cmd_inst_valid(m_icb_cmd_inst_valid),
		.m_icb_cmd_inst_ready(m_icb_cmd_inst_ready),
		.m_icb_rsp_inst_rdata(m_icb_rsp_inst_rdata),
		.m_icb_rsp_inst_err(m_icb_rsp_inst_err),
		.m_icb_rsp_inst_valid(m_icb_rsp_inst_valid),
		.m_icb_rsp_inst_ready(m_icb_rsp_inst_ready),
		
		.m_icb_cmd_data_addr(m_icb_cmd_data_addr),
		.m_icb_cmd_data_read(m_icb_cmd_data_read),
		.m_icb_cmd_data_wdata(m_icb_cmd_data_wdata),
		.m_icb_cmd_data_wmask(m_icb_cmd_data_wmask),
		.m_icb_cmd_data_valid(m_icb_cmd_data_valid),
		.m_icb_cmd_data_ready(m_icb_cmd_data_ready),
		.m_icb_rsp_data_rdata(m_icb_rsp_data_rdata),
		.m_icb_rsp_data_err(m_icb_rsp_data_err),
		.m_icb_rsp_data_valid(m_icb_rsp_data_valid),
		.m_icb_rsp_data_ready(m_icb_rsp_data_ready),
		
		.ibus_timeout(ibus_timeout),
		.dbus_timeout(dbus_timeout),
		
		.sw_itr_req(sw_itr_req),
		.tmr_itr_req(tmr_itr_req),
		.ext_itr_req(ext_itr_req)
	);
	
	/** ICB-SRAM控制器 **/
	// ICB从机
	// 命令通道
	wire[31:0] s_icb_imem_ctrler_cmd_addr;
	wire s_icb_imem_ctrler_cmd_read;
	wire[31:0] s_icb_imem_ctrler_cmd_wdata;
	wire[3:0] s_icb_imem_ctrler_cmd_wmask;
	wire s_icb_imem_ctrler_cmd_valid;
	wire s_icb_imem_ctrler_cmd_ready;
	// 响应通道
	wire[31:0] s_icb_imem_ctrler_rsp_rdata;
	wire s_icb_imem_ctrler_rsp_err;
	wire s_icb_imem_ctrler_rsp_valid;
	wire s_icb_imem_ctrler_rsp_ready;
	// SRAM存储器主接口
	wire imem_clk;
    wire imem_rst;
    wire imem_en;
    wire[3:0] imem_wen;
    wire[29:0] imem_addr;
    wire[31:0] imem_din;
    wire[31:0] imem_dout;
	
	assign s_icb_imem_ctrler_cmd_addr = m_icb_cmd_inst_addr;
	assign s_icb_imem_ctrler_cmd_read = m_icb_cmd_inst_read;
	assign s_icb_imem_ctrler_cmd_wdata = m_icb_cmd_inst_wdata;
	assign s_icb_imem_ctrler_cmd_wmask = m_icb_cmd_inst_wmask;
	assign s_icb_imem_ctrler_cmd_valid = m_icb_cmd_inst_valid;
	assign m_icb_cmd_inst_ready = s_icb_imem_ctrler_cmd_ready;
	assign m_icb_rsp_inst_rdata = s_icb_imem_ctrler_rsp_rdata;
	assign m_icb_rsp_inst_err = s_icb_imem_ctrler_rsp_err;
	assign m_icb_rsp_inst_valid = s_icb_imem_ctrler_rsp_valid;
	assign s_icb_imem_ctrler_rsp_ready = m_icb_rsp_inst_ready;
	
	icb_sram_ctrler #(
		.en_unaligned_transfer("true"),
		.wt_trans_imdt_resp("false"),
		.simulation_delay(simulation_delay)
	)imem_ctrler_u(
		.s_icb_aclk(clk),
		.s_icb_aresetn(sys_resetn),
		
		.s_icb_cmd_addr(s_icb_imem_ctrler_cmd_addr),
		.s_icb_cmd_read(s_icb_imem_ctrler_cmd_read),
		.s_icb_cmd_wdata(s_icb_imem_ctrler_cmd_wdata),
		.s_icb_cmd_wmask(s_icb_imem_ctrler_cmd_wmask),
		.s_icb_cmd_valid(s_icb_imem_ctrler_cmd_valid),
		.s_icb_cmd_ready(s_icb_imem_ctrler_cmd_ready),
		.s_icb_rsp_rdata(s_icb_imem_ctrler_rsp_rdata),
		.s_icb_rsp_err(s_icb_imem_ctrler_rsp_err),
		.s_icb_rsp_valid(s_icb_imem_ctrler_rsp_valid),
		.s_icb_rsp_ready(s_icb_imem_ctrler_rsp_ready),
		
		.bram_clk(imem_clk),
		.bram_rst(imem_rst),
		.bram_en(imem_en),
		.bram_wen(imem_wen),
		.bram_addr(imem_addr),
		.bram_din(imem_din),
		.bram_dout(imem_dout)
	);
	
	/** 指令存储器 **/
	bram_single_port #(
		.style("LOW_LATENCY"),
		.rw_mode("no_change"),
		.mem_width(32),
		.mem_depth(imem_depth),
		.INIT_FILE(imem_init_file),
		.byte_write_mode("true"),
		.simulation_delay(simulation_delay)
	)imem_u(
		.clk(imem_clk),
		
		.en(imem_en),
		.wen(imem_wen),
		.addr(imem_addr),
		.din(imem_din),
		.dout(imem_dout)
	);
	
	/** ICB到AXI-Lite桥 **/
	// ICB从机
	// 命令通道
	wire[31:0] s_icb_bridge_cmd_addr;
	wire s_icb_bridge_cmd_read;
	wire[31:0] s_icb_bridge_cmd_wdata;
	wire[3:0] s_icb_bridge_cmd_wmask;
	wire s_icb_bridge_cmd_valid;
	wire s_icb_bridge_cmd_ready;
	// 响应通道
	wire[31:0] s_icb_bridge_rsp_rdata;
	wire s_icb_bridge_rsp_err;
	wire s_icb_bridge_rsp_valid;
	wire s_icb_bridge_rsp_ready;
	
	assign m_axi_dbus_arburst = 2'b01;
	assign m_axi_dbus_arlen = 8'd0;
	assign m_axi_dbus_arsize = 3'b010;
	assign m_axi_dbus_arcache = 4'b0011;
	assign m_axi_dbus_awburst = 2'b01;
	assign m_axi_dbus_awlen = 8'd0;
	assign m_axi_dbus_awsize = 3'b010;
	assign m_axi_dbus_awcache = 4'b0011;
	assign m_axi_dbus_wlast = 1'b1;
	
	assign s_icb_bridge_cmd_addr = m_icb_cmd_data_addr;
	assign s_icb_bridge_cmd_read = m_icb_cmd_data_read;
	assign s_icb_bridge_cmd_wdata = m_icb_cmd_data_wdata;
	assign s_icb_bridge_cmd_wmask = m_icb_cmd_data_wmask;
	assign s_icb_bridge_cmd_valid = m_icb_cmd_data_valid;
	assign m_icb_cmd_data_ready = s_icb_bridge_cmd_ready;
	assign m_icb_rsp_data_rdata = s_icb_bridge_rsp_rdata;
	assign m_icb_rsp_data_err = s_icb_bridge_rsp_err;
	assign m_icb_rsp_data_valid = s_icb_bridge_rsp_valid;
	assign s_icb_bridge_rsp_ready = m_icb_rsp_data_ready;
	
	icb_axi_bridge #(
		.simulation_delay(simulation_delay)
	)icb_axi_bridge_u(
		.clk(clk),
		.resetn(sys_resetn),
		
		.s_icb_cmd_addr(s_icb_bridge_cmd_addr),
		.s_icb_cmd_read(s_icb_bridge_cmd_read),
		.s_icb_cmd_wdata(s_icb_bridge_cmd_wdata),
		.s_icb_cmd_wmask(s_icb_bridge_cmd_wmask),
		.s_icb_cmd_valid(s_icb_bridge_cmd_valid),
		.s_icb_cmd_ready(s_icb_bridge_cmd_ready),
		.s_icb_rsp_rdata(s_icb_bridge_rsp_rdata),
		.s_icb_rsp_err(s_icb_bridge_rsp_err),
		.s_icb_rsp_valid(s_icb_bridge_rsp_valid),
		.s_icb_rsp_ready(s_icb_bridge_rsp_ready),
		
		.m_axi_araddr(m_axi_dbus_araddr),
		.m_axi_arprot(),
		.m_axi_arvalid(m_axi_dbus_arvalid),
		.m_axi_arready(m_axi_dbus_arready),
		.m_axi_awaddr(m_axi_dbus_awaddr),
		.m_axi_awprot(),
		.m_axi_awvalid(m_axi_dbus_awvalid),
		.m_axi_awready(m_axi_dbus_awready),
		.m_axi_bresp(m_axi_dbus_bresp),
		.m_axi_bvalid(m_axi_dbus_bvalid),
		.m_axi_bready(m_axi_dbus_bready),
		.m_axi_rdata(m_axi_dbus_rdata),
		.m_axi_rresp(m_axi_dbus_rresp),
		.m_axi_rvalid(m_axi_dbus_rvalid),
		.m_axi_rready(m_axi_dbus_rready),
		.m_axi_wdata(m_axi_dbus_wdata),
		.m_axi_wstrb(m_axi_dbus_wstrb),
		.m_axi_wvalid(m_axi_dbus_wvalid),
		.m_axi_wready(m_axi_dbus_wready)
	);
	
endmodule
