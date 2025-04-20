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
本模块: AXI-SDRAM控制器

描述: 
地址位宽 = 32位, 数据位宽 = 8/16/32/64位
支持非对齐传输

注意：
仅支持INCR突发类型
不支持窄带传输

协议:
AXI SLAVE
SDRAM MASTER

作者: 陈家耀
日期: 2025/04/07
********************************************************************/


module axi_sdram #(
	parameter integer AXI_ID_WIDTH = 4, // AXI接口ID位宽(1~8)
	parameter real CLK_PERIOD = 7.0, // 时钟周期(以ns计)
	parameter real INIT_PAUSE = 250000.0, // 初始等待时间(以ns计)
	parameter integer INIT_AUTO_RFS_N = 2, // 初始化时执行自动刷新的次数
    parameter real RFS_ITV = 64.0 * 1000.0 * 1000.0 / 4096.0 * 0.8, // 刷新间隔(以ns计)
    parameter real FORCED_RFS_ITV = 64.0 * 1000.0 * 1000.0 / 4096.0 * 0.9, // 强制刷新间隔(以ns计)
    parameter real MAX_RFS_ITV = 64.0 * 1000.0 * 1000.0 / 4096.0, // 最大刷新间隔(以ns计)
    parameter real tRC = 70.0, // (激活某个bank -> 激活同一bank)和(刷新完成时间)的最小时间要求
    parameter real tRRD = 2.0 * CLK_PERIOD, // (激活某个bank -> 激活不同bank)的最小时间要求
    parameter real tRCD = 21.0, // (激活某个bank -> 读写这个bank)的最小时间要求
    parameter real tRP = 21.0, // (预充电某个bank -> 刷新/激活同一bank/设置模式寄存器)的最小时间要求
    parameter real tRAS_min = 49.0, // (激活某个bank -> 预充电同一bank)的最小时间要求
    parameter real tRAS_max = 100000.0, // (激活某个bank -> 预充电同一bank)的最大时间要求
    parameter real tWR = 2.0 * CLK_PERIOD, // (写突发结束 -> 预充电)的最小时间要求
	parameter real tRSC = 2.0 * CLK_PERIOD, // 设置模式寄存器的等待时间
    parameter integer RW_DATA_BUF_DEPTH = 1024, // sdram-phy的读写数据buffer深度(512 | 1024 | 2048 | 4096 | 8192)
    parameter integer CAS_LATENCY = 2, // sdram读潜伏期时延(2 | 3)
    parameter integer DATA_WIDTH = 32, // 数据位宽(8 | 16 | 32 | 64)
	parameter integer SDRAM_COL_N = 256, // sdram列数(128 | 256 | 512 | 1024)
	parameter integer SDRAM_ROW_N = 8192, // sdram行数(1024 | 2048 | 4096 | 8192 | 16384)
    parameter EN_CMD_S1_AXIS_REG_SLICE = "true", // 是否使能sdram-phy的第1级命令AXIS寄存器片
    parameter EN_CMD_S2_AXIS_REG_SLICE = "true", // 是否使能sdram-phy的第2级命令AXIS寄存器片
    parameter EN_CMD_S3_AXIS_REG_SLICE = "true", // 是否使能sdram-phy的第3级命令AXIS寄存器片
	parameter EN_UNALIGNED_TRANSFER = "false", // 是否允许非对齐传输
    parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 控制器时钟和复位
    input wire ctrler_aclk,
    input wire ctrler_aresetn,
	// sdram时钟
	input wire sdram_aclk,
    
    // AXI从机
    // AR
	input wire[AXI_ID_WIDTH-1:0] s_axi_arid,
    input wire[31:0] s_axi_araddr,
    input wire[7:0] s_axi_arlen,
    input wire[2:0] s_axi_arsize, // 必须是clogb2(DATA_WIDTH/8)
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    // R
	output wire[AXI_ID_WIDTH-1:0] s_axi_rid,
    output wire[DATA_WIDTH-1:0] s_axi_rdata,
    output wire s_axi_rlast,
    output wire[1:0] s_axi_rresp, // const -> 2'b00
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    // AW
	input wire[AXI_ID_WIDTH-1:0] s_axi_awid,
    input wire[31:0] s_axi_awaddr,
    input wire[7:0] s_axi_awlen,
    input wire[2:0] s_axi_awsize, // 必须是clogb2(DATA_WIDTH/8)
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    // W
    input wire[DATA_WIDTH-1:0] s_axi_wdata,
    input wire[DATA_WIDTH/8-1:0] s_axi_wstrb,
    input wire s_axi_wlast,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    // B
	output wire[AXI_ID_WIDTH-1:0] s_axi_bid,
    output wire[1:0] s_axi_bresp, // const -> 2'b00
    output wire s_axi_bvalid,
    input wire s_axi_bready,
	
	// sdram时钟线
    output wire sdram_clk,
    output wire sdram_cke, // const -> 1'b1
    // sdram命令线
    output wire sdram_cs_n,
    output wire sdram_ras_n,
    output wire sdram_cas_n,
    output wire sdram_we_n,
    output wire[1:0] sdram_ba,
    output wire[15:0] sdram_addr,
    // sdram数据线
    output wire[DATA_WIDTH/8-1:0] sdram_dqm, // 1'b0 -> data write/output enable; 1'b1 -> data mask/output disable
	input wire[DATA_WIDTH-1:0] sdram_dq_i,
	output wire[DATA_WIDTH-1:0] sdram_dq_o,
	output wire[DATA_WIDTH-1:0] sdram_dq_t // 1为输入, 0为输出
);
	
	/** AXI从机接口 **/
	// SDRAM用户命令AXIS
    wire[39:0] m_axis_usr_cmd_data; // {保留(3bit), ba(2bit), 行地址(16bit), A15-0(16bit), 命令号(3bit)}
    wire[16:0] m_axis_usr_cmd_user; // {是否自动添加"停止突发"命令(1bit), 突发长度 - 1(16bit)}(仅对全页突发有效)
    wire m_axis_usr_cmd_valid;
    wire m_axis_usr_cmd_ready;
    // SDRAM写数据AXIS
    wire[DATA_WIDTH-1:0] m_axis_wt_data;
    wire[DATA_WIDTH/8-1:0] m_axis_wt_keep;
    wire m_axis_wt_last;
    wire m_axis_wt_valid;
    wire m_axis_wt_ready;
    // SDRAM读数据AXIS
    wire[DATA_WIDTH-1:0] s_axis_rd_data;
    wire s_axis_rd_last;
    wire s_axis_rd_valid;
    wire s_axis_rd_ready;
	
	s_axi_if_for_axi_sdram #(
		.AXI_ID_WIDTH(AXI_ID_WIDTH),
		.DATA_WIDTH(DATA_WIDTH),
		.SDRAM_COL_N(SDRAM_COL_N),
		.SDRAM_ROW_N(SDRAM_ROW_N),
		.EN_UNALIGNED_TRANSFER(EN_UNALIGNED_TRANSFER),
		.SIM_DELAY(SIM_DELAY)
	)s_axi_if_for_axi_sdram_u(
		.clk(ctrler_aclk),
		.rst_n(ctrler_aresetn),
		
		.s_axi_arid(s_axi_arid),
		.s_axi_araddr(s_axi_araddr),
		.s_axi_arlen(s_axi_arlen),
		.s_axi_arsize(s_axi_arsize),
		.s_axi_arvalid(s_axi_arvalid),
		.s_axi_arready(s_axi_arready),
		.s_axi_rid(s_axi_rid),
		.s_axi_rdata(s_axi_rdata),
		.s_axi_rlast(s_axi_rlast),
		.s_axi_rresp(s_axi_rresp),
		.s_axi_rvalid(s_axi_rvalid),
		.s_axi_rready(s_axi_rready),
		.s_axi_awid(s_axi_awid),
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
		.s_axi_bid(s_axi_bid),
		.s_axi_bresp(s_axi_bresp),
		.s_axi_bvalid(s_axi_bvalid),
		.s_axi_bready(s_axi_bready),
		
		.m_axis_usr_cmd_data(m_axis_usr_cmd_data),
		.m_axis_usr_cmd_user(m_axis_usr_cmd_user),
		.m_axis_usr_cmd_valid(m_axis_usr_cmd_valid),
		.m_axis_usr_cmd_ready(m_axis_usr_cmd_ready),
		
		.m_axis_wt_data(m_axis_wt_data),
		.m_axis_wt_keep(m_axis_wt_keep),
		.m_axis_wt_last(m_axis_wt_last),
		.m_axis_wt_valid(m_axis_wt_valid),
		.m_axis_wt_ready(m_axis_wt_ready),
		
		.s_axis_rd_data(s_axis_rd_data),
		.s_axis_rd_last(s_axis_rd_last),
		.s_axis_rd_valid(s_axis_rd_valid),
		.s_axis_rd_ready(s_axis_rd_ready)
	);
	
	/** sdram-phy **/
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
	
	assign s_axis_usr_cmd_data = m_axis_usr_cmd_data;
	assign s_axis_usr_cmd_user = m_axis_usr_cmd_user;
	assign s_axis_usr_cmd_valid = m_axis_usr_cmd_valid;
	assign m_axis_usr_cmd_ready = s_axis_usr_cmd_ready;
	
	assign s_axis_wt_data = m_axis_wt_data;
	assign s_axis_wt_keep = m_axis_wt_keep;
	assign s_axis_wt_last = m_axis_wt_last;
	assign s_axis_wt_valid = m_axis_wt_valid;
	assign m_axis_wt_ready = s_axis_wt_ready;
	
	assign s_axis_rd_data = m_axis_rd_data;
	assign s_axis_rd_last = m_axis_rd_last;
	assign s_axis_rd_valid = m_axis_rd_valid;
	assign m_axis_rd_ready = s_axis_rd_ready;
	
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
		.BURST_LEN(-1), // 全页突发
		.CAS_LATENCY(CAS_LATENCY),
		.DATA_WIDTH(DATA_WIDTH),
		.SDRAM_COL_N(SDRAM_COL_N),
		.ALLOW_AUTO_PRECHARGE("false"), // 不允许自动预充电
		.EN_CMD_S1_AXIS_REG_SLICE(EN_CMD_S1_AXIS_REG_SLICE),
		.EN_CMD_S2_AXIS_REG_SLICE(EN_CMD_S2_AXIS_REG_SLICE),
		.EN_CMD_S3_AXIS_REG_SLICE(EN_CMD_S3_AXIS_REG_SLICE),
		.EN_IMDT_STAT_WBURST_LEN("false"), // 不使能实时统计写突发长度
		.EN_EXPT_TIP("false"), // 不使能异常指示
		.SIM_DELAY(SIM_DELAY)
	)sdram_phy_u(
		.clk(ctrler_aclk),
		.rst_n(ctrler_aresetn),
		.clk_sdram(sdram_aclk),
		
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
		.sdram_dq_t(sdram_dq_t),
		
		.pcg_spcf_idle_bank_err(),
		.pcg_spcf_bank_tot_err(),
		.rw_idle_bank_err(),
		.rfs_with_act_banks_err(),
		.illegal_logic_cmd_err(),
		.rw_cross_line_err(),
		.ld_when_wdata_ext_fifo_empty_err(),
		.st_when_rdata_ext_fifo_full_err(),
		.rfs_timeout()
	);
	
endmodule
