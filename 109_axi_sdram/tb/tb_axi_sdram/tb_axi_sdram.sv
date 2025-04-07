`timescale 1ns / 1ps

`include "uvm_macros.svh"

import uvm_pkg::*;

`include "test_cases.sv"
`include "envs.sv"
`include "agents.sv"
`include "sequencers.sv"
`include "drivers.sv"
`include "monitors.sv"
`include "transactions.sv"

module tb_axi_sdram();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam real CLK_PERIOD = 7.0; // 时钟周期(以ns计)
	localparam real INIT_PAUSE = 250000.0; // 初始等待时间(以ns计)
	localparam integer INIT_AUTO_RFS_N = 8; // 初始化时执行自动刷新的次数
    localparam real RFS_ITV = 64.0 * 1000.0 * 1000.0 / 8192.0 * 0.8; // 刷新间隔(以ns计)
    localparam real FORCED_RFS_ITV = 64.0 * 1000.0 * 1000.0 / 8192.0 * 0.9; // 强制刷新间隔(以ns计)
    localparam real MAX_RFS_ITV = 64.0 * 1000.0 * 1000.0 / 8192.0; // 最大刷新间隔(以ns计)
    localparam real tRC = 60.0; // (激活某个bank -> 激活同一bank)和(刷新完成时间)的最小时间要求
    localparam real tRRD = 2.0 * CLK_PERIOD; // (激活某个bank -> 激活不同bank)的最小时间要求
    localparam real tRCD = 15.0; // (激活某个bank -> 读写这个bank)的最小时间要求
    localparam real tRP = 15.0; // (预充电某个bank -> 刷新/激活同一bank/设置模式寄存器)的最小时间要求
    localparam real tRAS_min = 42.0; // (激活某个bank -> 预充电同一bank)的最小时间要求
    localparam real tRAS_max = 100000.0; // (激活某个bank -> 预充电同一bank)的最大时间要求
    localparam real tWR = 2.0 * CLK_PERIOD; // (写突发结束 -> 预充电)的最小时间要求
	localparam real tRSC = 2.0 * CLK_PERIOD; // 设置模式寄存器的等待时间
    localparam integer RW_DATA_BUF_DEPTH = 1024; // 读写数据buffer深度(512 | 1024 | 2048 | 4096 | 8192)
    localparam integer CAS_LATENCY = 3; // sdram读潜伏期时延(2 | 3)
    localparam integer DATA_WIDTH = 16; // 数据位宽(8 | 16 | 32 | 64)
	localparam integer SDRAM_COL_N = 512; // sdram列数(64 | 128 | 256 | 512 | 1024)
	localparam integer SDRAM_ROW_N = 8192; // sdram行数(1024 | 2048 | 4096 | 8192 | 16384)
    localparam EN_CMD_S1_AXIS_REG_SLICE = "true"; // 是否使能第1级命令AXIS寄存器片
    localparam EN_CMD_S2_AXIS_REG_SLICE = "true"; // 是否使能第2级命令AXIS寄存器片
    localparam EN_CMD_S3_AXIS_REG_SLICE = "true"; // 是否使能第3级命令AXIS寄存器片
    localparam EN_UNALIGNED_TRANSFER = "true"; // 是否允许非对齐传输
	// 时钟和复位配置
	localparam real clk_p = CLK_PERIOD; // 时钟周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 时钟和复位 **/
	reg clk;
	reg clk_sdram;
	reg rst_n;
	
	initial
	begin
		clk <= 1'b1;
		
		forever
		begin
			# (clk_p / 2) clk <= ~clk;
		end
	end
	
	initial
	begin
		clk_sdram <= 1'b1;
		
		# (clk_p / 2); // 相位偏移180度
		
		forever
		begin
			# (clk_p / 2) clk_sdram <= ~clk_sdram;
		end
	end
	
	initial begin
		rst_n <= 1'b0;
		
		# (clk_p * 10 + simulation_delay);
		
		rst_n <= 1'b1;
	end
	
	/** 接口 **/
	AXI #(.out_drive_t(simulation_delay), 
		.addr_width(32), .data_width(DATA_WIDTH), .bresp_width(2), .rresp_width(2)) m_axi_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		uvm_config_db #(virtual AXI #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(DATA_WIDTH), .bresp_width(2), .rresp_width(2)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axi_if", m_axi_if.master);
		uvm_config_db #(virtual AXI #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(DATA_WIDTH), .bresp_width(2), .rresp_width(2)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axi_if", m_axi_if.monitor);
		
		// 启动testcase
		run_test("AxiSdramCase0Test");
	end
	
	/** sdram仿真模型 **/
	// sdram时钟线
    wire sdram_clk;
    wire sdram_cke; // const -> 1'b1
    // sdram命令线
    wire sdram_cs_n;
    wire sdram_ras_n;
    wire sdram_cas_n;
    wire sdram_we_n;
    wire[1:0] sdram_ba;
    wire[15:0] sdram_addr;
    // sdram数据线
    wire[DATA_WIDTH/8-1:0] sdram_dqm; // 1'b0 -> data write/output enable; 1'b1 -> data mask/output disable
	tri1[DATA_WIDTH-1:0] sdram_dq;
	wire[DATA_WIDTH-1:0] sdram_dq_i;
	wire[DATA_WIDTH-1:0] sdram_dq_o;
	wire[DATA_WIDTH-1:0] sdram_dq_t; // 1为输入, 0为输出
	
	genvar sdram_data_i;
	generate
		for(sdram_data_i = 0;sdram_data_i < DATA_WIDTH;sdram_data_i = sdram_data_i + 1)
		begin
			assign sdram_dq[sdram_data_i] = sdram_dq_t[sdram_data_i] ? 1'bz:sdram_dq_o[sdram_data_i];
			assign sdram_dq_i[sdram_data_i] = sdram_dq[sdram_data_i];
		end
	endgenerate
	
	IS42s32200 sdram_model_u(
		.Dq(sdram_dq),
		.Addr(sdram_addr[12:0]),
		.Ba(sdram_ba),
		.Clk(sdram_clk),
		.Cke(sdram_cke),
		.Cs_n(sdram_cs_n),
		.Ras_n(sdram_ras_n),
		.Cas_n(sdram_cas_n),
		.We_n(sdram_we_n),
		.Dqm(sdram_dqm)
	);
	
	/** 待测模块 **/
	// AXI从机
    // AR
    wire[31:0] s_axi_araddr;
    wire[7:0] s_axi_arlen;
    wire[2:0] s_axi_arsize; // 必须是clogb2(DATA_WIDTH/8)
    wire s_axi_arvalid;
    wire s_axi_arready;
    // R
    wire[DATA_WIDTH-1:0] s_axi_rdata;
    wire s_axi_rlast;
    wire[1:0] s_axi_rresp; // const -> 2'b00
    wire s_axi_rvalid;
    wire s_axi_rready;
    // AW
    wire[31:0] s_axi_awaddr;
    wire[7:0] s_axi_awlen;
    wire[2:0] s_axi_awsize; // 必须是clogb2(DATA_WIDTH/8)
    wire s_axi_awvalid;
    wire s_axi_awready;
    // W
    wire[DATA_WIDTH-1:0] s_axi_wdata;
    wire[DATA_WIDTH/8-1:0] s_axi_wstrb;
    wire s_axi_wlast;
    wire s_axi_wvalid;
    wire s_axi_wready;
    // B
    wire[1:0] s_axi_bresp; // const -> 2'b00
    wire s_axi_bvalid;
    wire s_axi_bready;
	
	assign s_axi_araddr = m_axi_if.araddr;
	assign s_axi_arlen = m_axi_if.arlen;
	assign s_axi_arsize = m_axi_if.arsize;
	assign s_axi_arvalid = m_axi_if.arvalid;
	assign m_axi_if.arready = s_axi_arready;
	
	assign m_axi_if.rdata = s_axi_rdata;
	assign m_axi_if.rlast = s_axi_rlast;
	assign m_axi_if.rresp = s_axi_rresp;
	assign m_axi_if.rvalid = s_axi_rvalid;
	assign s_axi_rready = m_axi_if.rready;
	
	assign s_axi_awaddr = m_axi_if.awaddr;
	assign s_axi_awlen = m_axi_if.awlen;
	assign s_axi_awsize = m_axi_if.awsize;
	assign s_axi_awvalid = m_axi_if.awvalid;
	assign m_axi_if.awready = s_axi_awready;
	
	assign s_axi_wdata = m_axi_if.wdata;
	assign s_axi_wstrb = m_axi_if.wstrb;
	assign s_axi_wlast = m_axi_if.wlast;
	assign s_axi_wvalid = m_axi_if.wvalid;
	assign m_axi_if.wready = s_axi_wready;
	
	assign m_axi_if.bresp = s_axi_bresp;
	assign m_axi_if.bvalid = s_axi_bvalid;
	assign s_axi_bready = m_axi_if.bready;
	
	axi_sdram #(
		.CLK_PERIOD(CLK_PERIOD),
		.INIT_PAUSE(INIT_PAUSE),
		.INIT_AUTO_RFS_N(INIT_AUTO_RFS_N),
		.RFS_ITV(RFS_ITV),
		.FORCED_RFS_ITV(FORCED_RFS_ITV),
		.MAX_RFS_ITV(MAX_RFS_ITV),
		.tRC(tRC),
		.tRRD(tRRD),
		.tRCD(tRCD),
		.tRP(tRP),
		.tRAS_min(tRAS_min),
		.tRAS_max(tRAS_max),
		.tWR(tWR),
		.tRSC(tRSC),
		.RW_DATA_BUF_DEPTH(RW_DATA_BUF_DEPTH),
		.CAS_LATENCY(CAS_LATENCY),
		.DATA_WIDTH(DATA_WIDTH),
		.SDRAM_COL_N(SDRAM_COL_N),
		.SDRAM_ROW_N(SDRAM_ROW_N),
		.EN_CMD_S1_AXIS_REG_SLICE(EN_CMD_S1_AXIS_REG_SLICE),
		.EN_CMD_S2_AXIS_REG_SLICE(EN_CMD_S2_AXIS_REG_SLICE),
		.EN_CMD_S3_AXIS_REG_SLICE(EN_CMD_S3_AXIS_REG_SLICE),
		.EN_UNALIGNED_TRANSFER(EN_UNALIGNED_TRANSFER),
		.SIM_DELAY(simulation_delay)
	)dut(
		.ctrler_aclk(clk),
		.ctrler_aresetn(rst_n),
		.sdram_aclk(clk_sdram),
		
		.s_axi_araddr(s_axi_araddr),
		.s_axi_arlen(s_axi_arlen),
		.s_axi_arsize(s_axi_arsize),
		.s_axi_arvalid(s_axi_arvalid),
		.s_axi_arready(s_axi_arready),
		.s_axi_rdata(s_axi_rdata),
		.s_axi_rlast(s_axi_rlast),
		.s_axi_rresp(s_axi_rresp),
		.s_axi_rvalid(s_axi_rvalid),
		.s_axi_rready(s_axi_rready),
		.s_axi_awaddr(s_axi_awaddr),
		.s_axi_awlen(s_axi_awlen),
		.s_axi_awsize(s_axi_awsize),
		.s_axi_awvalid(s_axi_awvalid),
		.s_axi_awready(s_axi_awready),
		.s_axi_wdata(s_axi_wdata),
		.s_axi_wstrb(s_axi_wstrb),
		.s_axi_wlast(s_axi_wlast),
		.s_axi_wvalid(s_axi_wvalid),
		.s_axi_wready(s_axi_wready),
		.s_axi_bresp(s_axi_bresp),
		.s_axi_bvalid(s_axi_bvalid),
		.s_axi_bready(s_axi_bready),
		
		.sdram_clk(sdram_clk),
		.sdram_cke(sdram_cke),
		.sdram_cs_n(sdram_cs_n),
		.sdram_ras_n(sdram_ras_n),
		.sdram_cas_n(sdram_cas_n),
		.sdram_we_n(sdram_we_n),
		.sdram_ba(sdram_ba),
		.sdram_addr(sdram_addr),
		.sdram_dqm(sdram_dqm),
		.sdram_dq_i(sdram_dq_i),
		.sdram_dq_o(sdram_dq_o),
		.sdram_dq_t(sdram_dq_t)
	);
	
endmodule
