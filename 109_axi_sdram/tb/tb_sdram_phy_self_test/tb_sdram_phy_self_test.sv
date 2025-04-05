`timescale 1ns / 1ps

module tb_sdram_phy_self_test();
	
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
    localparam integer BURST_LEN = -1; // 突发长度(-1 -> 全页; 1 | 2 | 4 | 8)
    localparam integer CAS_LATENCY = 3; // sdram读潜伏期时延(2 | 3)
    localparam integer DATA_WIDTH = 32; // 数据位宽(8 | 16 | 32 | 64)
	localparam integer SDRAM_COL_N = 512; // sdram列数(64 | 128 | 256 | 512 | 1024)
	localparam integer SDRAM_ROW_N = 8192; // sdram行数(1024 | 2048 | 4096 | 8192 | 16384)
    localparam ALLOW_AUTO_PRECHARGE = "true"; // 是否允许自动预充电(8 | 16 | 32 | 64)
    localparam EN_CMD_S1_AXIS_REG_SLICE = "true"; // 是否使能第1级命令AXIS寄存器片
    localparam EN_CMD_S2_AXIS_REG_SLICE = "true"; // 是否使能第2级命令AXIS寄存器片
    localparam EN_CMD_S3_AXIS_REG_SLICE = "true"; // 是否使能第3级命令AXIS寄存器片
    localparam EN_IMDT_STAT_WBURST_LEN = "true"; // 是否使能实时统计写突发长度(仅对全页突发有效)
    localparam EN_EXPT_TIP = "true"; // 是否使能异常指示
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
		
		# (clk_p / 2 + clk_p / 9); // 相位偏移220度
		
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
	// 写数据AXIS
    wire[DATA_WIDTH-1:0] s_axis_wt_data;
    wire[DATA_WIDTH/8-1:0] s_axis_wt_keep;
    wire s_axis_wt_last;
    wire s_axis_wt_valid;
    wire s_axis_wt_ready;
    // 读数据AXIS
    wire[DATA_WIDTH-1:0] m_axis_rd_data;
    wire m_axis_rd_last;
    wire m_axis_rd_valid;
    wire m_axis_rd_ready;
    // 用户命令AXIS
    wire[39:0] s_axis_usr_cmd_data; // {保留(3bit), ba(2bit), 行地址(16bit), A15-0(16bit), 命令号(3bit)}
    // 仅对全页突发有效, 若使能实时统计写突发长度, 则在写数据命令中无需指定突发长度
    wire[16:0] s_axis_usr_cmd_user; // {是否自动添加"停止突发"命令(1bit), 突发长度 - 1(16bit)}(仅对全页突发有效)
    wire s_axis_usr_cmd_valid;
    wire s_axis_usr_cmd_ready;
	
	sdram_phy #(
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
		.BURST_LEN(BURST_LEN),
		.CAS_LATENCY(CAS_LATENCY),
		.DATA_WIDTH(DATA_WIDTH),
		.SDRAM_COL_N(SDRAM_COL_N),
		.ALLOW_AUTO_PRECHARGE(ALLOW_AUTO_PRECHARGE),
		.EN_CMD_S1_AXIS_REG_SLICE(EN_CMD_S1_AXIS_REG_SLICE),
		.EN_CMD_S2_AXIS_REG_SLICE(EN_CMD_S2_AXIS_REG_SLICE),
		.EN_CMD_S3_AXIS_REG_SLICE(EN_CMD_S3_AXIS_REG_SLICE),
		.EN_IMDT_STAT_WBURST_LEN(EN_IMDT_STAT_WBURST_LEN),
		.EN_EXPT_TIP(EN_EXPT_TIP),
		.SIM_DELAY(simulation_delay)
	)dut(
		.clk(clk),
		.rst_n(rst_n),
		.clk_sdram(clk_sdram),
		
		.s_axis_wt_data(s_axis_wt_data),
		.s_axis_wt_keep(s_axis_wt_keep),
		.s_axis_wt_last(s_axis_wt_last),
		.s_axis_wt_valid(s_axis_wt_valid),
		.s_axis_wt_ready(s_axis_wt_ready),
		
		.m_axis_rd_data(m_axis_rd_data),
		.m_axis_rd_last(m_axis_rd_last),
		.m_axis_rd_valid(m_axis_rd_valid),
		.m_axis_rd_ready(m_axis_rd_ready),
		
		.s_axis_usr_cmd_data(s_axis_usr_cmd_data),
		.s_axis_usr_cmd_user(s_axis_usr_cmd_user),
		.s_axis_usr_cmd_valid(s_axis_usr_cmd_valid),
		.s_axis_usr_cmd_ready(s_axis_usr_cmd_ready),
		
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
	
	/** sdram自检 **/
	reg self_test_start;
	
	initial begin
		self_test_start <= 1'b0;
		
		# (clk_p * 20 + simulation_delay);
		
		self_test_start <= 1'b1;
		
		# (clk_p);
		
		self_test_start <= 1'b0;
	end
	
	sdram_selftest #(
		.BURST_LEN(BURST_LEN),
		.DATA_WIDTH(DATA_WIDTH),
		.SDRAM_COL_N(SDRAM_COL_N),
		.SDRAM_ROW_N(SDRAM_ROW_N),
		.SIM_DELAY(simulation_delay)
	)sdram_selftest_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.self_test_start(self_test_start),
		
		.m_axis_wt_data(s_axis_wt_data),
		.m_axis_wt_keep(s_axis_wt_keep),
		.m_axis_wt_last(s_axis_wt_last),
		.m_axis_wt_valid(s_axis_wt_valid),
		.m_axis_wt_ready(s_axis_wt_ready),
		
		.s_axis_rd_data(m_axis_rd_data),
		.s_axis_rd_last(m_axis_rd_last),
		.s_axis_rd_valid(m_axis_rd_valid),
		.s_axis_rd_ready(m_axis_rd_ready),
		
		.m_axis_usr_cmd_data(s_axis_usr_cmd_data),
		.m_axis_usr_cmd_user(s_axis_usr_cmd_user),
		.m_axis_usr_cmd_valid(s_axis_usr_cmd_valid),
		.m_axis_usr_cmd_ready(s_axis_usr_cmd_ready)
	);
	
endmodule
