`timescale 1ns / 1ps
/********************************************************************
本模块: AXI-SDRAM

描述: 
32位地址/数据总线
支持非对齐传输

143MHz(时钟周期7ns)下带宽为483.13MB/s, 带宽利用率为84.55%

注意：
仅支持INCR突发类型
不支持窄带传输
sdram突发类型固定为全页

以下非寄存器输出 ->
    AXI从机的读数据通道: s_axi_rlast, s_axi_rvalid
    AXI从机的写数据通道: s_axi_wready
    AXI从机的写响应通道: s_axi_bvalid

协议:
AXI SLAVE
SDRAM MASTER

作者: 陈家耀
日期: 2024/05/01
********************************************************************/


module axi_sdram #(
    parameter arb_algorithm = "round-robin", // 读写仲裁算法("round-robin" | "fixed-r" | "fixed-w")
    parameter en_unaligned_transfer = "false", // 是否允许非对齐传输
    parameter real clk_period = 7.0, // 时钟周期
    parameter real refresh_itv = 64.0 * 1000.0 * 1000.0 / 4096.0 * 0.8, // 刷新间隔(以ns计)
    parameter real forced_refresh_itv = 64.0 * 1000.0 * 1000.0 / 4096.0 * 0.9, // 强制刷新间隔(以ns计)
    parameter real max_refresh_itv = 64.0 * 1000.0 * 1000.0 / 4096.0, // 最大刷新间隔(以ns计)
    parameter real tRC = 70.0, // (激活某个bank -> 激活同一bank)和(刷新完成时间)的最小时间要求
    parameter real tRRD = 14.0, // (激活某个bank -> 激活不同bank)的最小时间要求
    parameter real tRCD = 21.0, // (激活某个bank -> 读写这个bank)的最小时间要求
    parameter real tRP = 21.0, // (预充电某个bank -> 刷新/激活同一bank/设置模式寄存器)的最小时间要求
    parameter real tRAS_min = 49.0, // (激活某个bank -> 预充电同一bank)的最小时间要求
    parameter real tRAS_max = 100000.0, // (激活某个bank -> 预充电同一bank)的最大时间要求
    parameter real tWR = 2.0, // (写突发结束 -> 预充电)的最小时间要求
    parameter integer rw_data_buffer_depth = 512, // 读写数据buffer深度(512 | 1024 | 2048 | 4096)
    parameter integer cas_latency = 2, // sdram读潜伏期时延(2 | 3)
    parameter en_cmd_s2_axis_reg_slice = "true", // 是否使能第2级命令AXIS寄存器片
    parameter en_cmd_s3_axis_reg_slice = "true", // 是否使能第3级命令AXIS寄存器片
    parameter en_expt_tip = "false", // 是否使能异常指示
    parameter real sdram_if_signal_delay = 2.5 // sdram接口信号延迟(仅用于仿真)
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // AXI从机
    // AR
    input wire[31:0] s_axi_araddr,
    input wire[7:0] s_axi_arlen,
    input wire[2:0] s_axi_arsize,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    // R
    output wire[31:0] s_axi_rdata,
    output wire s_axi_rlast,
    output wire[1:0] s_axi_rresp, // const -> 2'b00
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    // AW
    input wire[31:0] s_axi_awaddr,
    input wire[7:0] s_axi_awlen,
    input wire[2:0] s_axi_awsize,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    // W
    input wire[31:0] s_axi_wdata,
    input wire[3:0] s_axi_wstrb,
    input wire s_axi_wlast,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    // B
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
    output wire[10:0] sdram_addr,
    // sdram数据线
    output wire[3:0] sdram_dqm, // 1'b0 -> data write/output enable; 1'b1 -> data mask/output disable
    input wire[31:0] sdram_dq_i,
	output wire[31:0] sdram_dq_o,
	output wire[31:0] sdram_dq_t, // 1为输入, 0为输出
    
    // 异常指示
    output wire pcg_spcf_idle_bank_err, // 预充电空闲的特定bank(异常指示)
    output wire pcg_spcf_bank_tot_err, // 预充电特定bank超时(异常指示)
    output wire rw_idle_bank_err, // 读写空闲的bank(异常指示)
    output wire rfs_with_act_banks_err, // 刷新时带有已激活的bank(异常指示)
    output wire illegal_logic_cmd_err, // 非法的逻辑命令编码(异常指示)
    output wire rw_cross_line_err, // 跨行的读写命令(异常指示)
    output wire ld_when_wdata_ext_fifo_empty_err, // 在写数据广义fifo空时取数据(异常指示)
    output wire st_when_rdata_ext_fifo_full_err, // 在读数据广义fifo满时存数据(异常指示)
    output wire rfs_timeout // 刷新超时
);
    
    /** AXI从接口 **/
    // SDRAM用户命令AXIS
    wire[31:0] m_axis_usr_cmd_data; // {保留(5bit), ba(2bit), 行地址(11bit), A10-0(11bit), 命令号(3bit)}
    wire[8:0] m_axis_usr_cmd_user; // {是否自动添加"停止突发"命令(1bit), 突发长度 - 1(8bit)}
    wire m_axis_usr_cmd_valid;
    wire m_axis_usr_cmd_ready;
    // SDRAM写数据AXIS
    wire[31:0] m_axis_wt_data;
    wire[3:0] m_axis_wt_keep;
    wire m_axis_wt_last;
    wire m_axis_wt_valid;
    wire m_axis_wt_ready;
    // SDRAM读数据AXIS
    wire[31:0] s_axis_rd_data;
    wire s_axis_rd_last;
    wire s_axis_rd_valid;
    wire s_axis_rd_ready;
    
    s_axi_if_for_axi_sdram #(
        .arb_algorithm(arb_algorithm),
        .en_unaligned_transfer(en_unaligned_transfer)
    )s_axi_if(
        .clk(clk),
        .rst_n(rst_n),
        
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
    
    /** SDRAM PHY **/
    // sdram突发类型固定为全页, 不使能实时统计写突发长度, 使能第1级命令AXIS寄存器片
    sdram_phy #(
        .clk_period(clk_period),
        .refresh_itv(refresh_itv),
        .forced_refresh_itv(forced_refresh_itv),
        .max_refresh_itv(max_refresh_itv),
        .tRC(tRC),
        .tRRD(tRRD),
        .tRCD(tRCD),
        .tRP(tRP),
        .tRAS_min(tRAS_min),
        .tRAS_max(tRAS_max),
        .tWR(tWR),
        .rw_data_buffer_depth(rw_data_buffer_depth),
        .burst_len(-1),
        .cas_latency(cas_latency),
        .data_width(32),
        .allow_auto_precharge("false"),
        .en_cmd_s1_axis_reg_slice("true"),
        .en_cmd_s2_axis_reg_slice(en_cmd_s2_axis_reg_slice),
        .en_cmd_s3_axis_reg_slice(en_cmd_s3_axis_reg_slice),
        .en_imdt_stat_wburst_len("false"),
        .en_expt_tip(en_expt_tip),
        .sdram_if_signal_delay(sdram_if_signal_delay)
    )sdram_phy_u(
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_wt_data(m_axis_wt_data),
        .s_axis_wt_keep(m_axis_wt_keep),
        .s_axis_wt_last(m_axis_wt_last),
        .s_axis_wt_valid(m_axis_wt_valid),
        .s_axis_wt_ready(m_axis_wt_ready),
        .m_axis_rd_data(s_axis_rd_data),
        .m_axis_rd_last(s_axis_rd_last),
        .m_axis_rd_valid(s_axis_rd_valid),
        .m_axis_rd_ready(s_axis_rd_ready),
        .s_axis_usr_cmd_data(m_axis_usr_cmd_data),
        .s_axis_usr_cmd_user(m_axis_usr_cmd_user),
        .s_axis_usr_cmd_valid(m_axis_usr_cmd_valid),
        .s_axis_usr_cmd_ready(m_axis_usr_cmd_ready),
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
        .pcg_spcf_idle_bank_err(pcg_spcf_idle_bank_err),
        .pcg_spcf_bank_tot_err(pcg_spcf_bank_tot_err),
        .rw_idle_bank_err(rw_idle_bank_err),
        .rfs_with_act_banks_err(rfs_with_act_banks_err),
        .illegal_logic_cmd_err(illegal_logic_cmd_err),
        .rw_cross_line_err(rw_cross_line_err),
        .ld_when_wdata_ext_fifo_empty_err(ld_when_wdata_ext_fifo_empty_err),
        .st_when_rdata_ext_fifo_full_err(st_when_rdata_ext_fifo_full_err),
        .rfs_timeout(rfs_timeout)
    );
    
endmodule
