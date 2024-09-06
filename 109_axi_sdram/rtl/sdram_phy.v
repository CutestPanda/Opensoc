`timescale 1ns / 1ps
/********************************************************************
本模块: sdram控制器PHY层

描述:
接受命令流和写数据流, 以符合sdram时序要求的方式控制命令线
产生读数据流
已处理初始化和自动刷新
自动向读写数据命令插入合适的激活/预充电命令

2位bank地址, 11位行/列地址

支持如下命令:
命令号     含义                  备注
  0      激活bank        用户一般无需指定该命令
  1     预充电bank       用户一般无需指定该命令
  2      写数据
  3      读数据
  4   设置模式寄存器     用户一般无需指定该命令
  5     自动刷新         用户一般无需指定该命令
  6     停止突发    仅内部使用, 用户不可指定该命令号
  7      空操作         用户一般无需指定该命令

命令流输入到sdram命令输出存在3~6clk时延:
    [第1级AXIS寄存器片1clk] -> [第2级AXIS寄存器片1clk] -> [第3级寄存器片1clk] -> 命令代理判定1clk -> 由写数据引起的延迟补偿2clk

注意：
一般来说, 用户仅需指定写数据/读数据命令
建议使能第1级命令AXIS寄存器片, 以缓存用户命令

协议:
AXIS MASTER/SLAVE
SDRAM MASTER

作者: 陈家耀
日期: 2024/04/14
********************************************************************/


module sdram_phy #(
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
    parameter integer rw_data_buffer_depth = 1024, // 读写数据buffer深度(512 | 1024 | 2048 | 4096)
    parameter integer burst_len = -1, // 突发长度(-1 -> 全页; 1 | 2 | 4 | 8)
    parameter integer cas_latency = 2, // sdram读潜伏期时延(2 | 3)
    parameter integer data_width = 32, // 数据位宽
    parameter allow_auto_precharge = "true", // 是否允许自动预充电
    parameter en_cmd_s1_axis_reg_slice = "true", // 是否使能第1级命令AXIS寄存器片
    parameter en_cmd_s2_axis_reg_slice = "true", // 是否使能第2级命令AXIS寄存器片
    parameter en_cmd_s3_axis_reg_slice = "true", // 是否使能第3级命令AXIS寄存器片
    parameter en_imdt_stat_wburst_len = "true", // 是否使能实时统计写突发长度(仅对全页突发有效)
    parameter en_expt_tip = "false", // 是否使能异常指示
    parameter real sdram_if_signal_delay = 2.5 // sdram接口信号延迟(仅用于仿真)
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 写数据AXIS
    input wire[data_width-1:0] s_axis_wt_data,
    input wire[data_width/8-1:0] s_axis_wt_keep,
    input wire s_axis_wt_last,
    input wire s_axis_wt_valid,
    output wire s_axis_wt_ready,
    // 读数据AXIS
    output wire[data_width-1:0] m_axis_rd_data,
    output wire m_axis_rd_last,
    output wire m_axis_rd_valid,
    input wire m_axis_rd_ready,
    
    // 用户命令AXIS
    input wire[31:0] s_axis_usr_cmd_data, // {保留(5bit), ba(2bit), 行地址(11bit), A10-0(11bit), 命令号(3bit)}
    // 仅对全页突发有效, 若使能实时统计写突发长度, 则在写数据命令中无需指定突发长度
    input wire[8:0] s_axis_usr_cmd_user, // {是否自动添加"停止突发"命令(1bit), 突发长度 - 1(8bit)}
    input wire s_axis_usr_cmd_valid,
    output wire s_axis_usr_cmd_ready,
    
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
    output wire[data_width/8-1:0] sdram_dqm, // 1'b0 -> data write/output enable; 1'b1 -> data mask/output disable
	input wire[data_width-1:0] sdram_dq_i,
	output wire[data_width-1:0] sdram_dq_o,
	output wire[data_width-1:0] sdram_dq_t, // 1为输入, 0为输出
    
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

    // 计算log2(bit_depth)
    function integer clogb2 (input integer bit_depth);
        integer temp;
    begin
        temp = bit_depth;
        for(clogb2 = -1;temp > 0;clogb2 = clogb2 + 1)
            temp = temp >> 1;
    end
    endfunction
    
    /** 内部配置 **/
    localparam en_rw_cmd_outstanding = "false"; // 是否启用读写命令缓存(启用可能会提高读写效率)
	localparam sim_mode = "false"; // 是否处于仿真模式
    
    /** 常量 **/
    // 读写命令缓存深度
    localparam integer RW_CMD_OUTSTANDING = rw_data_buffer_depth / ((burst_len == -1) ? 256:burst_len);
    // 命令的逻辑编码
    localparam CMD_LOGI_WT_DATA = 3'b010; // 命令:写数据
    localparam CMD_LOGI_RD_DATA = 3'b011; // 命令:读数据
    
    /** sdram时钟线 **/
    assign sdram_cke = 1'b1;
    
    // ODDR
	generate
		if(sim_mode == "true")
		begin
			assign sdram_clk = clk;
		end
		else
		begin
			EG_LOGIC_ODDR #(
				.ASYNCRST("ENABLE")
			)oddr_u(
				.q(sdram_clk),
				
				.clk(clk),
				
				.d0(1'b0), // 上升沿数据输入
				.d1(1'b1), // 下降沿数据输入
				
				.rst(~rst_n)
			);
		end
	endgenerate
    
    /** sdram数据三态门 **/
    wire[data_width-1:0] sdram_dq_i_inner;
    wire sdram_dq_t_inner; // 三态门方向(1表示输入, 0表示输出)
    wire[data_width-1:0] sdram_dq_o_inner;
	
	assign sdram_dq_i_inner = sdram_dq_i;
	assign sdram_dq_o = sdram_dq_o_inner;
	assign sdram_dq_t = {data_width{sdram_dq_t_inner}};
    
    /** sdram数据缓冲区 **/
    // 写数据广义fifo读端口
    wire wdata_ext_fifo_ren;
    wire wdata_ext_fifo_empty_n;
    wire wdata_ext_fifo_mem_ren;
    wire[clogb2(rw_data_buffer_depth-1):0] wdata_ext_fifo_mem_raddr;
    wire[data_width+data_width/8-1:0] wdata_ext_fifo_mem_dout; // {keep(data_width/8 bit), data(data_width bit)}
    // 读数据广义fifo写端口
    wire rdata_ext_fifo_wen;
    wire rdata_ext_fifo_full_n;
    wire rdata_ext_fifo_mem_wen;
    wire[clogb2(rw_data_buffer_depth-1):0] rdata_ext_fifo_mem_waddr;
    wire[data_width:0] rdata_ext_fifo_mem_din; // {last(1bit), data(data_width bit)}
    // 实时统计写突发长度fifo读端口
    wire imdt_stat_wburst_len_fifo_ren;
    wire[7:0] imdt_stat_wburst_len_fifo_dout;
    
    sdram_data_buffer #(
        .rw_data_buffer_depth(rw_data_buffer_depth),
        .en_imdt_stat_wburst_len(en_imdt_stat_wburst_len),
        .burst_len(burst_len),
        .data_width(data_width)
    )sdram_data_buffer_u(
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_wt_data(s_axis_wt_data),
        .s_axis_wt_keep(s_axis_wt_keep),
        .s_axis_wt_last(s_axis_wt_last),
        .s_axis_wt_valid(s_axis_wt_valid),
        .s_axis_wt_ready(s_axis_wt_ready),
        .m_axis_rd_data(m_axis_rd_data),
        .m_axis_rd_last(m_axis_rd_last),
        .m_axis_rd_valid(m_axis_rd_valid),
        .m_axis_rd_ready(m_axis_rd_ready),
        .wdata_ext_fifo_ren(wdata_ext_fifo_ren),
        .wdata_ext_fifo_empty_n(wdata_ext_fifo_empty_n),
        .wdata_ext_fifo_mem_ren(wdata_ext_fifo_mem_ren),
        .wdata_ext_fifo_mem_raddr(wdata_ext_fifo_mem_raddr),
        .wdata_ext_fifo_mem_dout(wdata_ext_fifo_mem_dout),
        .rdata_ext_fifo_wen(rdata_ext_fifo_wen),
        .rdata_ext_fifo_full_n(rdata_ext_fifo_full_n),
        .rdata_ext_fifo_mem_wen(rdata_ext_fifo_mem_wen),
        .rdata_ext_fifo_mem_waddr(rdata_ext_fifo_mem_waddr),
        .rdata_ext_fifo_mem_din(rdata_ext_fifo_mem_din),
        .imdt_stat_wburst_len_fifo_ren(imdt_stat_wburst_len_fifo_ren),
        .imdt_stat_wburst_len_fifo_dout(imdt_stat_wburst_len_fifo_dout)
    );
    
    /** sdram激活/预充电命令插入模块 **/
    // 插入激活/预充电命令后的命令AXIS
    wire[15:0] m_axis_inserted_cmd_data; // {BS(2bit), A10-0(11bit), 命令号(3bit)}
    // 自动添加"停止突发"命令仅对全页突发有效
    wire[8:0] m_axis_inserted_cmd_user; // {是否自动添加"停止突发"命令(1bit), 突发长度 - 1(8bit)}
    wire m_axis_inserted_cmd_valid;
    wire m_axis_inserted_cmd_ready;
    
    sdram_active_precharge_insert #(
        .burst_len(burst_len),
        .allow_auto_precharge(allow_auto_precharge),
        .en_cmd_axis_reg_slice(en_cmd_s1_axis_reg_slice)
    )sdram_active_precharge_insert_u(
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_usr_cmd_data(s_axis_usr_cmd_data),
        .s_axis_usr_cmd_user(s_axis_usr_cmd_user),
        .s_axis_usr_cmd_valid(s_axis_usr_cmd_valid),
        .s_axis_usr_cmd_ready(s_axis_usr_cmd_ready),
        .m_axis_inserted_cmd_data(m_axis_inserted_cmd_data),
        .m_axis_inserted_cmd_user(m_axis_inserted_cmd_user),
        .m_axis_inserted_cmd_valid(m_axis_inserted_cmd_valid),
        .m_axis_inserted_cmd_ready(m_axis_inserted_cmd_ready)
    );
    
    /** 可选的命令AXIS寄存器片 **/
    // 用户命令AXIS
    wire[15:0] m_axis_usr_cmd_data; // {BS(2bit), A10-0(11bit), 命令号(3bit)}
    wire[8:0] m_axis_usr_cmd_user; // {是否自动添加"停止突发"命令(1bit), 突发长度 - 1(8bit)}
    wire m_axis_usr_cmd_valid;
    wire m_axis_usr_cmd_ready;
    
    axis_reg_slice #(
        .data_width(16),
        .user_width(9),
        .forward_registered(en_cmd_s2_axis_reg_slice),
        .back_registered(en_cmd_s2_axis_reg_slice),
        .en_ready("true"),
        .simulation_delay(0)
    )inserted_cmd_axis_reg_slice(
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_data(m_axis_inserted_cmd_data),
        .s_axis_keep(),
        .s_axis_user(m_axis_inserted_cmd_user),
        .s_axis_last(),
        .s_axis_valid(m_axis_inserted_cmd_valid),
        .s_axis_ready(m_axis_inserted_cmd_ready),
        .m_axis_data(m_axis_usr_cmd_data),
        .m_axis_keep(),
        .m_axis_user(m_axis_usr_cmd_user),
        .m_axis_last(),
        .m_axis_valid(m_axis_usr_cmd_valid),
        .m_axis_ready(m_axis_usr_cmd_ready)
    );
    
    /** sdram命令代理 **/
    // 命令代理的命令AXIS
    wire[15:0] s_axis_cmd_agent_data; // {BS(2bit), A10-0(11bit), 命令号(3bit)}
    // 自动添加"停止突发"命令仅对全页突发有效
    wire[8:0] s_axis_cmd_agent_user; // {是否自动添加"停止突发"命令(1bit), 突发长度 - 1(8bit)}
    wire s_axis_cmd_agent_valid;
    wire s_axis_cmd_agent_ready;
    // sdram命令线
    wire sdram_cs_n_p2;
    wire sdram_ras_n_p2;
    wire sdram_cas_n_p2;
    wire sdram_we_n_p2;
    wire[1:0] sdram_ba_p2;
    wire[10:0] sdram_addr_p2;
    reg sdram_cs_n_p1;
    reg sdram_ras_n_p1;
    reg sdram_cas_n_p1;
    reg sdram_we_n_p1;
    reg[1:0] sdram_ba_p1;
    reg[10:0] sdram_addr_p1;
    reg sdram_cs_n_now;
    reg sdram_ras_n_now;
    reg sdram_cas_n_now;
    reg sdram_we_n_now;
    reg[1:0] sdram_ba_now;
    reg[10:0] sdram_addr_now;
    // 突发信息
    wire new_burst_start; // 突发开始指示
    wire is_write_burst; // 是否写突发
    wire[7:0] new_burst_len; // 突发长度 - 1
    
    assign {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = {sdram_cs_n_now, sdram_ras_n_now, sdram_cas_n_now, sdram_we_n_now};
    assign {sdram_ba, sdram_addr} = {sdram_ba_now, sdram_addr_now};
    
    axis_sdram_cmd_agent #(
        .cas_latency(cas_latency),
        .clk_period(clk_period),
        .tRC(tRC),
        .tRRD(tRRD),
        .tRCD(tRCD),
        .tRP(tRP),
        .tRAS_min(tRAS_min),
        .tRAS_max(tRAS_max),
        .tWR(tWR),
        .burst_len(burst_len),
        .allow_auto_precharge(allow_auto_precharge),
        .en_cmd_axis_reg_slice(en_cmd_s3_axis_reg_slice),
        .en_expt_tip(en_expt_tip)
    )axis_sdram_cmd_agent_u(
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_cmd_data(s_axis_cmd_agent_data),
        .s_axis_cmd_user(s_axis_cmd_agent_user),
        .s_axis_cmd_valid(s_axis_cmd_agent_valid),
        .s_axis_cmd_ready(s_axis_cmd_agent_ready),
        .sdram_cs_n(sdram_cs_n_p2),
        .sdram_ras_n(sdram_ras_n_p2),
        .sdram_cas_n(sdram_cas_n_p2),
        .sdram_we_n(sdram_we_n_p2),
        .sdram_ba(sdram_ba_p2),
        .sdram_addr(sdram_addr_p2),
        .new_burst_start(new_burst_start),
        .is_write_burst(is_write_burst),
        .new_burst_len(new_burst_len),
        .pcg_spcf_idle_bank_err(pcg_spcf_idle_bank_err),
        .pcg_spcf_bank_tot_err(pcg_spcf_bank_tot_err),
        .rw_idle_bank_err(rw_idle_bank_err),
        .rfs_with_act_banks_err(rfs_with_act_banks_err),
        .illegal_logic_cmd_err(illegal_logic_cmd_err),
        .rw_cross_line_err(rw_cross_line_err)
    );
    
    // 将sdram命令代理输出的命令延迟2clk, 以补偿写数据
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            {sdram_cs_n_p1, sdram_ras_n_p1, sdram_cas_n_p1, sdram_we_n_p1} <= 4'b0111;
        else
            {sdram_cs_n_p1, sdram_ras_n_p1, sdram_cas_n_p1, sdram_we_n_p1} <= {sdram_cs_n_p2, sdram_ras_n_p2, sdram_cas_n_p2, sdram_we_n_p2};
    end
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            {sdram_cs_n_now, sdram_ras_n_now, sdram_cas_n_now, sdram_we_n_now} <= 4'b0111;
        else
            {sdram_cs_n_now, sdram_ras_n_now, sdram_cas_n_now, sdram_we_n_now} <= # sdram_if_signal_delay {sdram_cs_n_p1, sdram_ras_n_p1, sdram_cas_n_p1, sdram_we_n_p1};
    end
    
    always @(posedge clk)
        {sdram_ba_p1, sdram_addr_p1} <= {sdram_ba_p2, sdram_addr_p2};
    always @(posedge clk)
        {sdram_ba_now, sdram_addr_now} <= # sdram_if_signal_delay {sdram_ba_p1, sdram_addr_p1};
    
    /** sdram数据代理 **/
    sdram_data_agent #(
        .rw_data_buffer_depth(rw_data_buffer_depth),
        .burst_len(burst_len),
        .cas_latency(cas_latency),
        .data_width(data_width),
        .en_expt_tip(en_expt_tip),
        .sdram_if_signal_delay(sdram_if_signal_delay)
    )sdram_data_agent_u(
        .clk(clk),
        .rst_n(rst_n),
        .new_burst_start(new_burst_start),
        .is_write_burst(is_write_burst),
        .new_burst_len(new_burst_len),
        .wdata_ext_fifo_ren(wdata_ext_fifo_ren),
        .wdata_ext_fifo_empty_n(wdata_ext_fifo_empty_n),
        .wdata_ext_fifo_mem_ren(wdata_ext_fifo_mem_ren),
        .wdata_ext_fifo_mem_raddr(wdata_ext_fifo_mem_raddr),
        .wdata_ext_fifo_mem_dout(wdata_ext_fifo_mem_dout),
        .rdata_ext_fifo_wen(rdata_ext_fifo_wen),
        .rdata_ext_fifo_full_n(rdata_ext_fifo_full_n),
        .rdata_ext_fifo_mem_wen(rdata_ext_fifo_mem_wen),
        .rdata_ext_fifo_mem_waddr(rdata_ext_fifo_mem_waddr),
        .rdata_ext_fifo_mem_din(rdata_ext_fifo_mem_din),
        .sdram_dqm(sdram_dqm),
        .sdram_dq_i(sdram_dq_i_inner),
        .sdram_dq_t(sdram_dq_t_inner),
        .sdram_dq_o(sdram_dq_o_inner),
        .ld_when_wdata_ext_fifo_empty_err(ld_when_wdata_ext_fifo_empty_err),
        .st_when_rdata_ext_fifo_full_err(st_when_rdata_ext_fifo_full_err)
    );
    
    /** sdram初始化命令生成器 **/
    // 初始化命令AXIS
    wire[15:0] m_axis_init_cmd_data; // {BS(2bit), A10-0(11bit), 命令号(3bit)}
    wire m_axis_init_cmd_valid;
    wire m_axis_init_cmd_ready;
    // 初始化命令接收完成(标志)
    wire init_cmd_all_recv;
    
    sdram_init_cmd_gen #(
        .clk_period(clk_period),
        .burst_len(burst_len),
        .cas_latency(cas_latency)
    )sdram_init_cmd_gen_u(
        .clk(clk),
        .rst_n(rst_n),
        .init_cmd_all_recv(init_cmd_all_recv),
        .m_axis_init_cmd_data(m_axis_init_cmd_data),
        .m_axis_init_cmd_valid(m_axis_init_cmd_valid),
        .m_axis_init_cmd_ready(m_axis_init_cmd_ready)
    );
    
    /** sdram自动刷新控制器 **/
    // 自动刷新定时开始(指示)
    wire start_rfs_timing;
    // 自动刷新命令流AXIS
    wire[15:0] m_axis_rfs_data; // {BS(2bit), A10-0(11bit), 命令号(3bit)}
    wire m_axis_rfs_valid;
    wire m_axis_rfs_ready;
    // 刷新控制器运行中
    wire rfs_ctrler_running;
    
    sdram_auto_refresh #(
        .clk_period(clk_period),
        .refresh_itv(refresh_itv),
        .forced_refresh_itv(forced_refresh_itv),
        .allow_auto_precharge(allow_auto_precharge),
        .burst_len(burst_len)
    )sdram_auto_refresh_u(
        .clk(clk),
        .rst_n(rst_n),
        .start_rfs_timing(start_rfs_timing),
        .rfs_ctrler_running(rfs_ctrler_running),
        .s_axis_cmd_agent_monitor_data(s_axis_cmd_agent_data),
        .s_axis_cmd_agent_monitor_valid(s_axis_cmd_agent_valid),
        .s_axis_cmd_agent_monitor_ready(s_axis_cmd_agent_ready),
        .m_axis_rfs_data(m_axis_rfs_data),
        .m_axis_rfs_valid(m_axis_rfs_valid),
        .m_axis_rfs_ready(m_axis_rfs_ready)
    );
    
    /** 刷新监测器 **/
    sdram_rfs_monitor #(
        .clk_period(clk_period),
        .max_refresh_itv(max_refresh_itv),
        .en_expt_tip(en_expt_tip)
    )sdram_rfs_monitor_u(
        .clk(clk),
        .rst_n(rst_n),
        .start_rfs_timing(start_rfs_timing),
        .sdram_cs_n(sdram_cs_n_p2),
        .sdram_ras_n(sdram_ras_n_p2),
        .sdram_cas_n(sdram_cas_n_p2),
        .sdram_we_n(sdram_we_n_p2),
        .rfs_timeout(rfs_timeout)
    );
    
    /**
    初始化/自动刷新/用户命令AXIS选通
    
    自动刷新的优先级是最高的, 一旦刷新控制器运行中, 总线控制权立即交给自动刷新
    对读写数据命令的特殊处理: 保证产生写数据命令时写数据广义fifo非空, 保证产生读数据命令时读数据广义fifo非满
    **/
    wire rd_wt_cmd_ready; // 读写命令就绪(标志)
    reg[clogb2(RW_CMD_OUTSTANDING):0] wtrans_buffered; // 已缓存的写事务个数
    reg wtrans_ready; // 准备好接受写事务
    reg[clogb2(RW_CMD_OUTSTANDING):0] rtrans_launched; // 已启动的读事务个数
    reg rtrans_ready; // 准备好接受读事务
    
    assign s_axis_cmd_agent_data = rfs_ctrler_running ? m_axis_rfs_data:
        (init_cmd_all_recv ? m_axis_usr_cmd_data:m_axis_init_cmd_data);
    assign s_axis_cmd_agent_user = ((en_imdt_stat_wburst_len == "true") & (burst_len == -1)) ? 
        ((m_axis_usr_cmd_data[2:0] == CMD_LOGI_WT_DATA) ? {m_axis_usr_cmd_user[8], imdt_stat_wburst_len_fifo_dout}:m_axis_usr_cmd_user):
            m_axis_usr_cmd_user;
    assign s_axis_cmd_agent_valid = rfs_ctrler_running ? m_axis_rfs_valid:
        (init_cmd_all_recv ? (m_axis_usr_cmd_valid & rd_wt_cmd_ready):m_axis_init_cmd_valid);
    assign m_axis_usr_cmd_ready = (~rfs_ctrler_running) & init_cmd_all_recv & s_axis_cmd_agent_ready & rd_wt_cmd_ready;
    assign m_axis_init_cmd_ready = (~rfs_ctrler_running) & (~init_cmd_all_recv) & s_axis_cmd_agent_ready;
    assign m_axis_rfs_ready = s_axis_cmd_agent_ready;
    
    assign rd_wt_cmd_ready = (m_axis_usr_cmd_data[2:0] == CMD_LOGI_WT_DATA) ? (wtrans_ready & ((en_rw_cmd_outstanding == "true") | wdata_ext_fifo_empty_n)):
                             (m_axis_usr_cmd_data[2:0] == CMD_LOGI_RD_DATA) ? (rtrans_ready & ((en_rw_cmd_outstanding == "true") | rdata_ext_fifo_full_n)):
                                                                              1'b1;
    
    assign imdt_stat_wburst_len_fifo_ren = ((en_imdt_stat_wburst_len == "true") & (burst_len == -1)) ? 
        (m_axis_usr_cmd_valid & m_axis_usr_cmd_ready & (m_axis_usr_cmd_data[2:0] == CMD_LOGI_WT_DATA)):1'b0;
    
    // 已缓存的写事务个数
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wtrans_buffered <= 0;
        else if((s_axis_wt_valid & s_axis_wt_ready & s_axis_wt_last) ^ (m_axis_usr_cmd_valid & m_axis_usr_cmd_ready & (m_axis_usr_cmd_data[2:0] == CMD_LOGI_WT_DATA)))
            wtrans_buffered <= (s_axis_wt_valid & s_axis_wt_ready & s_axis_wt_last) ? (wtrans_buffered + 1):(wtrans_buffered - 1);
    end
    // 准备好接受写事务
    generate
        if(en_rw_cmd_outstanding == "true")
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wtrans_ready <= 1'b0;
                else if((s_axis_wt_valid & s_axis_wt_ready & s_axis_wt_last) ^ (m_axis_usr_cmd_valid & m_axis_usr_cmd_ready & (m_axis_usr_cmd_data[2:0] == CMD_LOGI_WT_DATA)))
                    wtrans_ready <= (s_axis_wt_valid & s_axis_wt_ready & s_axis_wt_last) ? 1'b1:(wtrans_buffered != 1);
            end
        end
        else
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wtrans_ready <= 1'b1;
                else
                    wtrans_ready <= wtrans_ready ? (~(m_axis_usr_cmd_valid & m_axis_usr_cmd_ready & (m_axis_usr_cmd_data[2:0] == CMD_LOGI_WT_DATA))):wdata_ext_fifo_ren;
            end
        end
    endgenerate
    
    // 已启动的读事务个数
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rtrans_launched <= 0;
        else if((m_axis_rd_valid & m_axis_rd_ready & m_axis_rd_last) ^ (m_axis_usr_cmd_valid & m_axis_usr_cmd_ready & (m_axis_usr_cmd_data[2:0] == CMD_LOGI_RD_DATA)))
            rtrans_launched <= (m_axis_rd_valid & m_axis_rd_ready & m_axis_rd_last) ? (rtrans_launched - 1):(rtrans_launched + 1);
    end
    // 准备好接受读事务
    generate
        if(en_rw_cmd_outstanding == "true")
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rtrans_ready <= 1'b1;
                else if((m_axis_rd_valid & m_axis_rd_ready & m_axis_rd_last) ^ (m_axis_usr_cmd_valid & m_axis_usr_cmd_ready & (m_axis_usr_cmd_data[2:0] == CMD_LOGI_RD_DATA)))
                    rtrans_ready <= (m_axis_rd_valid & m_axis_rd_ready & m_axis_rd_last) ? 1'b1:(rtrans_launched != (RW_CMD_OUTSTANDING - 1));
            end
        end
        else
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rtrans_ready <= 1'b1;
                else
                    rtrans_ready <= rtrans_ready ? (~(m_axis_usr_cmd_valid & m_axis_usr_cmd_ready & (m_axis_usr_cmd_data[2:0] == CMD_LOGI_RD_DATA))):rdata_ext_fifo_wen;
            end
        end
    endgenerate
    
endmodule
