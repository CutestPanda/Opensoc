`timescale 1ns / 1ps
/********************************************************************
本模块: 带指令/数据存储器的小胖达RISC-V处理器核

描述:
仅用于仿真

注意：
无

协议:
无

作者: 陈家耀
日期: 2025/07/02
********************************************************************/


module panda_risc_v_sim #(
	parameter integer IMEM_DEPTH = 8 * 1024, // 指令存储器深度
	parameter integer DMEM_DEPTH = 8 * 1024, // 数据存储器深度
	parameter IMEM_INIT_FILE = "no_init", // 指令存储器的初始化文件路径
	parameter DMEM_INIT_FILE = "no_init", // 数据存储器的初始化文件路径
	parameter integer IBUS_ACCESS_TIMEOUT_TH = 16, // 指令总线访问超时周期数(0 -> 不设超时 | 正整数)
	parameter integer IBUS_OUTSTANDING_N = 4, // 指令总线滞外深度(1 | 2 | 4 | 8)
	parameter integer MEM_ACCESS_TIMEOUT_TH = 0, // 存储器访问超时周期数(0 -> 不设超时 | 正整数)
	parameter integer PERPH_ACCESS_TIMEOUT_TH = 32, // 外设访问超时周期数(0 -> 不设超时 | 正整数)
	parameter integer BTB_WAY_N = 2, // BTB路数(1 | 2 | 4)
	parameter integer BTB_ENTRY_N = 1024, // BTB项数(<=65536)
	parameter integer RAS_ENTRY_N = 4, // 返回地址堆栈的条目数(2 | 4 | 8 | 16)
	parameter EN_SGN_PERIOD_MUL = "true", // 是否使用单周期乘法器
	parameter integer ROB_ENTRY_N = 8, // 重排序队列项数(4 | 8 | 16 | 32)
	parameter integer CSR_RW_RCD_SLOTS_N = 2, // CSR读写指令信息记录槽位数(2 | 4 | 8 | 16 | 32)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟
	input wire clk,
	// 外部复位输入
	input wire ext_resetn,
	
	// 软件复位请求
	input wire sw_reset,
	
	// 错误标志
	output wire clr_inst_buf_while_suppressing, // 在镇压ICB事务时清空指令缓存(错误标志)
	output wire ibus_timeout, // 指令总线访问超时(错误标志)
	output wire rd_mem_timeout, // 读存储器超时(错误标志)
	output wire wr_mem_timeout, // 写存储器超时(错误标志)
	output wire perph_access_timeout, // 外设访问超时(错误标志)
	
	// 中断请求
	// 注意: 中断请求保持有效直到中断清零!
	input wire sw_itr_req, // 软件中断请求
	input wire tmr_itr_req, // 计时器中断请求
	input wire ext_itr_req // 外部中断请求
);
	
    // 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
    end
    endfunction
	
	/** 系统复位 **/
	wire sys_resetn; // 系统复位输入
	wire sys_reset_req; // 系统复位请求
    
    panda_risc_v_reset #(
		.simulation_delay(SIM_DELAY)
	)panda_risc_v_reset_u(
		.clk(clk),
		
		.ext_resetn(ext_resetn),
		
		.sw_reset(sw_reset),
		
		.sys_resetn(sys_resetn),
		.sys_reset_req(sys_reset_req),
		.sys_reset_fns()
	);
	
	/** 处理器核 **/
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
	
	panda_risc_v_core #(
		.IBUS_ACCESS_TIMEOUT_TH(IBUS_ACCESS_TIMEOUT_TH),
		.IBUS_OUTSTANDING_N(IBUS_OUTSTANDING_N),
		.AXI_MEM_DATA_WIDTH(32),
		.MEM_ACCESS_TIMEOUT_TH(MEM_ACCESS_TIMEOUT_TH),
		.PERPH_ACCESS_TIMEOUT_TH(PERPH_ACCESS_TIMEOUT_TH),
		.PERPH_ADDR_REGION_0_BASE(32'h4000_0000),
		.PERPH_ADDR_REGION_0_LEN(32'h1000_0000),
		.PERPH_ADDR_REGION_1_BASE(32'hF000_0000),
		.PERPH_ADDR_REGION_1_LEN(32'h0800_0000),
		.IMEM_BASEADDR(32'h0000_0000),
		.IMEM_ADDR_RANGE(IMEM_DEPTH * 4),
		.DM_REGS_BASEADDR(32'hFFFF_F800),
		.DM_REGS_ADDR_RANGE(1 * 1024),
		.GHR_WIDTH(0),
		.PC_WIDTH_FOR_PHT_ADDR(8),
		.BHR_WIDTH(0),
		.BHT_DEPTH(512),
		.PHT_MEM_IMPL("sram"),
		.BTB_WAY_N(BTB_WAY_N),
		.BTB_ENTRY_N(BTB_ENTRY_N),
		.RAS_ENTRY_N(RAS_ENTRY_N),
		.DEBUG_SUPPORTED("false"),
		.DEBUG_ROM_ADDR(32'h0000_0600),
		.DSCRATCH_N(2),
		.EN_EXPT_VEC_VECTORED("false"),
		.EN_PERF_MONITOR("true"),
		.EN_SGN_PERIOD_MUL(EN_SGN_PERIOD_MUL),
		.ROB_ENTRY_N(ROB_ENTRY_N),
		.CSR_RW_RCD_SLOTS_N(CSR_RW_RCD_SLOTS_N),
		.SIM_DELAY(SIM_DELAY)
	)panda_risc_v_u(
		.aclk(clk),
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
		
		.m_axi_perph_araddr(),
		.m_axi_perph_arburst(),
		.m_axi_perph_arlen(),
		.m_axi_perph_arsize(),
		.m_axi_perph_arvalid(),
		.m_axi_perph_arready(1'b1),
		.m_axi_perph_rdata(32'dx),
		.m_axi_perph_rresp(2'bxx),
		.m_axi_perph_rlast(1'bx),
		.m_axi_perph_rvalid(1'b0),
		.m_axi_perph_rready(),
		.m_axi_perph_awaddr(),
		.m_axi_perph_awburst(),
		.m_axi_perph_awlen(),
		.m_axi_perph_awsize(),
		.m_axi_perph_awvalid(),
		.m_axi_perph_awready(1'b1),
		.m_axi_perph_bresp(2'bxx),
		.m_axi_perph_bvalid(1'b0),
		.m_axi_perph_bready(),
		.m_axi_perph_wdata(),
		.m_axi_perph_wstrb(),
		.m_axi_perph_wlast(),
		.m_axi_perph_wvalid(),
		.m_axi_perph_wready(1'b1),
		
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
		
		.dbg_halt_req(1'b0),
		.dbg_halt_on_reset_req(1'b0),
		
		.clr_inst_buf_while_suppressing(clr_inst_buf_while_suppressing),
		.ibus_timeout(ibus_timeout),
		.rd_mem_timeout(rd_mem_timeout),
		.wr_mem_timeout(wr_mem_timeout),
		.perph_access_timeout(perph_access_timeout)
	);
	
	/** 指令存储器 **/
	// [端口A]
    wire imem_clka;
    wire imem_rsta;
    wire imem_ena;
    wire[3:0] imem_wena;
    wire[29:0] imem_addra;
    wire[31:0] imem_dina;
    wire[31:0] imem_douta;
	// [端口B]
    wire imem_clkb;
    wire imem_rstb;
    wire imem_enb;
    wire[3:0] imem_wenb;
    wire[29:0] imem_addrb;
    wire[31:0] imem_dinb;
    wire[31:0] imem_doutb;
	
	panda_risc_v_tcm_ctrler #(
		.TCM_DATA_WIDTH(32),
		.SIM_DELAY(SIM_DELAY)
	)tcm_ctrler_u0(
		.aclk(clk),
		.aresetn(sys_resetn),
		
		.s_axi_araddr(m_axi_imem_araddr),
		.s_axi_arburst(m_axi_imem_arburst),
		.s_axi_arlen(m_axi_imem_arlen),
		.s_axi_arsize(m_axi_imem_arsize),
		.s_axi_arvalid(m_axi_imem_arvalid),
		.s_axi_arready(m_axi_imem_arready),
		.s_axi_rdata(m_axi_imem_rdata),
		.s_axi_rlast(m_axi_imem_rlast),
		.s_axi_rresp(m_axi_imem_rresp),
		.s_axi_rvalid(m_axi_imem_rvalid),
		.s_axi_rready(m_axi_imem_rready),
		.s_axi_awaddr(m_axi_imem_awaddr),
		.s_axi_awburst(m_axi_imem_awburst),
		.s_axi_awlen(m_axi_imem_awlen),
		.s_axi_awsize(m_axi_imem_awsize),
		.s_axi_awvalid(m_axi_imem_awvalid),
		.s_axi_awready(m_axi_imem_awready),
		.s_axi_bresp(m_axi_imem_bresp),
		.s_axi_bvalid(m_axi_imem_bvalid),
		.s_axi_bready(m_axi_imem_bready),
		.s_axi_wdata(m_axi_imem_wdata),
		.s_axi_wlast(m_axi_imem_wlast),
		.s_axi_wstrb(m_axi_imem_wstrb),
		.s_axi_wvalid(m_axi_imem_wvalid),
		.s_axi_wready(m_axi_imem_wready),
		
		.tcm_clka(imem_clka),
		.tcm_rsta(imem_rsta),
		.tcm_ena(imem_ena),
		.tcm_wena(imem_wena),
		.tcm_addra(imem_addra),
		.tcm_dina(imem_dina),
		.tcm_douta(imem_douta),
		
		.tcm_clkb(imem_clkb),
		.tcm_rstb(imem_rstb),
		.tcm_enb(imem_enb),
		.tcm_wenb(imem_wenb),
		.tcm_addrb(imem_addrb),
		.tcm_dinb(imem_dinb),
		.tcm_doutb(imem_doutb)
	);
	
	bram_true_dual_port #(
		.mem_width(32),
		.mem_depth(IMEM_DEPTH),
		.INIT_FILE(IMEM_INIT_FILE),
		.read_write_mode("read_first"),
		.use_output_register("false"),
		.en_byte_write("true"),
		.simulation_delay(SIM_DELAY)
	)imem_u(
		.clk(imem_clka),
		
		.ena(imem_ena),
		.wea(imem_wena),
		.addra(imem_addra[clogb2(IMEM_DEPTH-1):0]),
		.dina(imem_dina),
		.douta(imem_douta),
		
		.enb(imem_enb),
		.web(imem_wenb),
		.addrb(imem_addrb[clogb2(IMEM_DEPTH-1):0]),
		.dinb(imem_dinb),
		.doutb(imem_doutb)
	);
	
	/** 数据存储器 **/
    // [端口A]
    wire dmem_clka;
    wire dmem_rsta;
    wire dmem_ena;
    wire[3:0] dmem_wena;
    wire[29:0] dmem_addra;
    wire[31:0] dmem_dina;
    wire[31:0] dmem_douta;
	// [端口B]
    wire dmem_clkb;
    wire dmem_rstb;
    wire dmem_enb;
    wire[3:0] dmem_wenb;
    wire[29:0] dmem_addrb;
    wire[31:0] dmem_dinb;
    wire[31:0] dmem_doutb;
	
	panda_risc_v_tcm_ctrler #(
		.TCM_DATA_WIDTH(32),
		.SIM_DELAY(SIM_DELAY)
	)tcm_ctrler_u1(
		.aclk(clk),
		.aresetn(sys_resetn),
		
		.s_axi_araddr(m_axi_dmem_araddr),
		.s_axi_arburst(m_axi_dmem_arburst),
		.s_axi_arlen(m_axi_dmem_arlen),
		.s_axi_arsize(m_axi_dmem_arsize),
		.s_axi_arvalid(m_axi_dmem_arvalid),
		.s_axi_arready(m_axi_dmem_arready),
		.s_axi_rdata(m_axi_dmem_rdata),
		.s_axi_rlast(m_axi_dmem_rlast),
		.s_axi_rresp(m_axi_dmem_rresp),
		.s_axi_rvalid(m_axi_dmem_rvalid),
		.s_axi_rready(m_axi_dmem_rready),
		.s_axi_awaddr(m_axi_dmem_awaddr),
		.s_axi_awburst(m_axi_dmem_awburst),
		.s_axi_awlen(m_axi_dmem_awlen),
		.s_axi_awsize(m_axi_dmem_awsize),
		.s_axi_awvalid(m_axi_dmem_awvalid),
		.s_axi_awready(m_axi_dmem_awready),
		.s_axi_bresp(m_axi_dmem_bresp),
		.s_axi_bvalid(m_axi_dmem_bvalid),
		.s_axi_bready(m_axi_dmem_bready),
		.s_axi_wdata(m_axi_dmem_wdata),
		.s_axi_wlast(m_axi_dmem_wlast),
		.s_axi_wstrb(m_axi_dmem_wstrb),
		.s_axi_wvalid(m_axi_dmem_wvalid),
		.s_axi_wready(m_axi_dmem_wready),
		
		.tcm_clka(dmem_clka),
		.tcm_rsta(dmem_rsta),
		.tcm_ena(dmem_ena),
		.tcm_wena(dmem_wena),
		.tcm_addra(dmem_addra),
		.tcm_dina(dmem_dina),
		.tcm_douta(dmem_douta),
		
		.tcm_clkb(dmem_clkb),
		.tcm_rstb(dmem_rstb),
		.tcm_enb(dmem_enb),
		.tcm_wenb(dmem_wenb),
		.tcm_addrb(dmem_addrb),
		.tcm_dinb(dmem_dinb),
		.tcm_doutb(dmem_doutb)
	);
	
	bram_true_dual_port #(
		.mem_width(32),
		.mem_depth(DMEM_DEPTH),
		.INIT_FILE(DMEM_INIT_FILE),
		.read_write_mode("read_first"),
		.use_output_register("false"),
		.en_byte_write("true"),
		.simulation_delay(SIM_DELAY)
	)dmem_u(
		.clk(dmem_clka),
		
		.ena(dmem_ena),
		.wea(dmem_wena),
		.addra(dmem_addra[clogb2(DMEM_DEPTH-1):0]),
		.dina(dmem_dina),
		.douta(dmem_douta),
		
		.enb(dmem_enb),
		.web(dmem_wenb),
		.addrb(dmem_addrb[clogb2(DMEM_DEPTH-1):0]),
		.dinb(dmem_dinb),
		.doutb(dmem_doutb)
	);
	
	/** BTB存储器 **/
	genvar btb_mem_i;
	generate
		for(btb_mem_i = 0;btb_mem_i < BTB_WAY_N;btb_mem_i = btb_mem_i + 1)
		begin:btb_mem_blk
			bram_true_dual_port #(
				.mem_width(64),
				.mem_depth(BTB_ENTRY_N),
				.INIT_FILE(""),
				.read_write_mode("read_first"),
				.use_output_register("false"),
				.en_byte_write("false"),
				.simulation_delay(SIM_DELAY)
			)btb_mem_u(
				.clk(clk),
				
				.ena(btb_mem_ena[btb_mem_i]),
				.wea(btb_mem_wea[btb_mem_i]),
				.addra(btb_mem_addra[btb_mem_i*16+15:btb_mem_i*16]),
				.dina(btb_mem_dina[btb_mem_i*64+63:btb_mem_i*64]),
				.douta(btb_mem_douta[btb_mem_i*64+63:btb_mem_i*64]),
				
				.enb(btb_mem_enb[btb_mem_i]),
				.web(btb_mem_web[btb_mem_i]),
				.addrb(btb_mem_addrb[btb_mem_i*16+15:btb_mem_i*16]),
				.dinb(btb_mem_dinb[btb_mem_i*64+63:btb_mem_i*64]),
				.doutb(btb_mem_doutb[btb_mem_i*64+63:btb_mem_i*64])
			);
		end
	endgenerate
	
	/** PHT存储器 **/
	bram_true_dual_port #(
		.mem_width(2),
		.mem_depth(2**16),
		.INIT_FILE(""),
		.read_write_mode("read_first"),
		.use_output_register("false"),
		.en_byte_write("false"),
		.simulation_delay(SIM_DELAY)
	)pht_mem_u(
		.clk(pht_mem_clka),
		
		.ena(pht_mem_ena),
		.wea(pht_mem_wea),
		.addra(pht_mem_addra[16-1:0]),
		.dina(pht_mem_dina),
		.douta(pht_mem_douta),
		
		.enb(pht_mem_enb),
		.web(pht_mem_web),
		.addrb(pht_mem_addrb[16-1:0]),
		.dinb(pht_mem_dinb),
		.doutb(pht_mem_doutb)
	);
	
endmodule
