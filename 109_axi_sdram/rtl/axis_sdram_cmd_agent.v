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
本模块: sdram命令代理

描述:
接受命令流, 以符合sdram时序要求的方式控制命令线

2位bank地址, 16位行/列地址

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

注意：
时钟周期和时间要求以ns计
突发长度仅当使用全页突发且在读/写数据命令下可用
突发类型固定为顺序突发(sequential)

本模块改进建议 -> 
	实际上, 在读/写突发进行时也可以执行激活/预充电命令, 这样可以实现交织读/写, 从而进一步了提高读写效率! 

协议:
AXIS SLAVE

作者: 陈家耀
日期: 2025/03/02
********************************************************************/


module axis_sdram_cmd_agent #(
    parameter integer CAS_LATENCY = 2, // sdram读潜伏期时延(2 | 3)
    parameter real CLK_PERIOD = 5.0, // 时钟周期
    parameter real tRC = 55.0, // (激活某个bank -> 激活同一bank)和(刷新完成时间)的最小时间要求
    parameter real tRRD = 2.0 * CLK_PERIOD, // (激活某个bank -> 激活不同bank)的最小时间要求
    parameter real tRCD = 18.0, // (激活某个bank -> 读写这个bank)的最小时间要求
    parameter real tRP = 15.0, // (预充电某个bank -> 刷新/激活同一bank/设置模式寄存器)的最小时间要求
    parameter real tRAS_min = 35.0, // (激活某个bank -> 预充电同一bank)的最小时间要求
    parameter real tRAS_max = 100000.0, // (激活某个bank -> 预充电同一bank)的最大时间要求
    parameter real tWR = 2.0 * CLK_PERIOD, // (写突发结束 -> 预充电)的最小时间要求
	parameter real tRSC = 2.0 * CLK_PERIOD, // 设置模式寄存器的等待时间
    parameter integer BURST_LEN = -1, // 突发长度(-1 -> 全页; 1 | 2 | 4 | 8)
    parameter ALLOW_AUTO_PRECHARGE = "true", // 是否允许自动预充电
    parameter EN_CMD_AXIS_REG_SLICE = "true", // 是否使能命令AXIS寄存器片
    parameter EN_EXPT_TIP = "false", // 是否使能异常指示
	parameter integer SDRAM_COL_N = 256, // sdram列数(64 | 128 | 256 | 512 | 1024)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 命令AXIS
    input wire[23:0] s_axis_cmd_data, // {保留(3bit), BS(2bit), A15-0(16bit), 命令号(3bit)}
    input wire[16:0] s_axis_cmd_user, // {是否自动添加"停止突发"命令(1bit), 突发长度 - 1(16bit)}(仅对全页突发有效)
    input wire s_axis_cmd_valid,
    output wire s_axis_cmd_ready,
    
    // sdram命令线
    output wire sdram_cs_n,
    output wire sdram_ras_n,
    output wire sdram_cas_n,
    output wire sdram_we_n,
    output wire[1:0] sdram_ba,
    output wire[15:0] sdram_addr,
    
    // 突发信息
    output wire new_burst_start, // 突发开始指示
    output wire is_write_burst, // 是否写突发
    output wire[15:0] new_burst_len, // 突发长度 - 1
    
    // 异常指示
    output wire pcg_spcf_idle_bank_err, // 预充电空闲的特定bank(异常指示)
    output wire pcg_spcf_bank_tot_err, // 预充电特定bank超时(异常指示)
    output wire rw_idle_bank_err, // 读写空闲的bank(异常指示)
    output wire rfs_with_act_banks_err, // 刷新时带有已激活的bank(异常指示)
    output wire illegal_logic_cmd_err, // 非法的逻辑命令编码(异常指示)
    output wire rw_cross_line_err // 跨行的读写命令(异常指示)
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
	// 向上取整
    function integer ceil(input real f);
		integer dec;
		real frac;
    begin
		if(f > 0.0)
			dec = f - 0.5;
		else if(f < 0.0)
			dec = f + 0.5;
		else
			dec = 0;
		
		frac = f - dec;
		
		ceil = ((frac == 0.0) || (f < 0)) ? dec:(dec + 1);
    end
    endfunction
    
    /** 常量 **/
    localparam rw_data_with_auto_precharge = (BURST_LEN == -1) ? "false":ALLOW_AUTO_PRECHARGE; // 使能读写数据命令的自动预充电
    // 时间要求(以时钟周期计)
    localparam integer tRC_p = ceil(tRC / CLK_PERIOD); // (激活某个bank -> 激活同一bank)和(刷新完成时间)的最小时间要求
    localparam integer tRRD_p = ceil(tRRD / CLK_PERIOD); // (激活某个bank -> 激活不同bank)的最小时间要求
    localparam integer tRCD_p = ceil(tRCD / CLK_PERIOD); // (激活某个bank -> 读写这个bank)的最小时间要求
    localparam integer tRP_p = ceil(tRP / CLK_PERIOD); // (预充电某个bank -> 刷新/激活同一bank/设置模式寄存器)的最小时间要求
    localparam integer tRAS_min_p = ceil(tRAS_min / CLK_PERIOD); // (激活某个bank -> 预充电同一bank)的最小时间要求
    localparam integer tRAS_max_p = ceil(tRAS_max / CLK_PERIOD); // (激活某个bank -> 预充电同一bank)的最大时间要求
    localparam integer tWR_p = ceil(tWR / CLK_PERIOD); // (写突发结束 -> 预充电)的最小时间要求
	localparam integer tRSC_p = ceil(tRSC / CLK_PERIOD); // 设置模式寄存器的等待时间
    // 带自动预充电的读 -> tRP + BURST_LEN; 带自动预充电的写 -> tRP + BURST_LEN - 1 + tWR
	// 注意: 简单起见, 这里考虑max(tRP + BURST_LEN, tRP + BURST_LEN - 1 + tWR)!
    localparam integer tATRFS_p = tRP_p + ((tWR_p > 1) ? tWR_p:1); // (自动预充电完成时间)的最小时间要求
    // 命令的逻辑编码
    localparam CMD_LOGI_BANK_ACTIVE = 3'b000; // 命令:激活bank
    localparam CMD_LOGI_BANK_PRECHARGE = 3'b001; // 命令:预充电bank
    localparam CMD_LOGI_WT_DATA = 3'b010; // 命令:写数据
    localparam CMD_LOGI_RD_DATA = 3'b011; // 命令:读数据
    localparam CMD_LOGI_MR_SET = 3'b100; // 命令:设置模式寄存器
    localparam CMD_LOGI_AUTO_REFRESH = 3'b101; // 命令:自动刷新
    localparam CMD_LOGI_BURST_STOP = 3'b110; // 命令:停止突发
    localparam CMD_LOGI_NOP = 3'b111; // 命令:空操作
    // 命令的物理编码(CS_N, RAS_N, CAS_N, WE_N)
    localparam CMD_PHY_BANK_ACTIVE = 4'b0011; // 命令:激活bank
    localparam CMD_PHY_BANK_PRECHARGE = 4'b0010; // 命令:预充电bank
    localparam CMD_PHY_WT_DATA = 4'b0100; // 命令:写数据
    localparam CMD_PHY_RD_DATA = 4'b0101; // 命令:读数据
    localparam CMD_PHY_MR_SET = 4'b0000; // 命令:设置模式寄存器
    localparam CMD_PHY_BURST_STOP = 4'b0110; // 命令:停止突发
    localparam CMD_PHY_AUTO_REFRESH = 4'b0001; // 命令:自动刷新
    localparam CMD_PHY_NOP = 4'b0111; // 命令:空操作
	localparam CMD_PHY_DEV_DSEL = 4'b1111; // 命令:片选无效
    // bank状态
    localparam STS_BANK_IDLE = 2'b00; // 状态:空闲
    localparam STS_BANK_ACTIVE = 2'b01; // 状态:激活
    localparam STS_BANK_BURST = 2'b10; // 状态:突发进行中
    // 突发长度计数器的位宽
    localparam integer BURST_LEN_CNT_WIDTH = (BURST_LEN == -1) ? 16:
                                              (BURST_LEN == 1) ? 1:
                                              (clogb2(BURST_LEN - 1) + 1);
	// sdram命令各字段的起始索引
	localparam integer SDRAM_CMD_CID = 0;
	localparam integer SDRAM_CMD_ADDR = 3;
	localparam integer SDRAM_CMD_BS = 19;
    
    /** 可选的命令AXIS寄存器片 **/
    wire[23:0] m_axis_cmd_data; // {保留(3bit), BS(2bit), A15-0(16bit), 命令号(3bit)}
    wire[16:0] m_axis_cmd_user; // {是否自动添加"停止突发"命令(1bit), 突发长度 - 1(16bit)}(仅对全页突发有效)
    wire m_axis_cmd_valid;
    wire m_axis_cmd_ready;
    
    axis_reg_slice #(
        .data_width(24),
        .user_width(17),
        .forward_registered(EN_CMD_AXIS_REG_SLICE),
        .back_registered(EN_CMD_AXIS_REG_SLICE),
        .en_ready("true"),
        .simulation_delay(SIM_DELAY)
    )cmd_axis_reg_slice(
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_data(s_axis_cmd_data),
        .s_axis_keep(),
        .s_axis_user(s_axis_cmd_user),
        .s_axis_last(),
        .s_axis_valid(s_axis_cmd_valid),
        .s_axis_ready(s_axis_cmd_ready),
        .m_axis_data(m_axis_cmd_data),
        .m_axis_keep(),
        .m_axis_user(m_axis_cmd_user),
        .m_axis_last(),
        .m_axis_valid(m_axis_cmd_valid),
        .m_axis_ready(m_axis_cmd_ready)
    );
    
    /** 命令最小时间要求限制 **/
    // 冷却计数器触发信号
    wire refresh_start; // 开始自动刷新(指示)
    wire auto_precharge_start; // 开始自动预充电(指示)
    wire[3:0] bank_active_same_cd_trigger; // 激活同一bank的冷却触发
    wire[3:0] bank_active_diff_cd_trigger; // 激活不同bank的冷却触发
    wire[3:0] bank_active_to_rw_itv_trigger; // 激活到读写的等待触发
    wire[3:0] bank_precharge_itv_trigger; // 预充电到刷新/激活同一bank/设置模式寄存器的等待触发
    wire[3:0] bank_precharge_same_cd_trigger; // 预充电同一bank的冷却触发
    // 冷却计数器就绪和完成信号
    wire refresh_busy_n; // 自动刷新忙碌(标志)
    wire auto_precharge_busy_n; // 自动预充电忙碌(标记)
    wire auto_precharge_itv_done; // 自动预充电的等待完成
    wire[3:0] bank_active_same_cd_ready; // 激活同一bank的冷却就绪
    wire[3:0] bank_active_diff_cd_ready; // 激活不同bank的冷却就绪
    wire[3:0] bank_active_to_rw_itv_ready; // 激活到读写的等待就绪
    wire[3:0] bank_precharge_itv_done; // 预充电到刷新/激活同一bank/设置模式寄存器的等待完成
    wire[3:0] bank_precharge_itv_ready; // 预充电到刷新/激活同一bank/设置模式寄存器的等待就绪
    wire[3:0] bank_precharge_same_cd_ready; // 预充电同一bank的冷却就绪
    
    // 自动刷新忙碌计数器
    cool_down_cnt #(
        .max_cd(tRC_p + 1),
		.EN_TRG_IN_CD("true"),
		.SIM_DELAY(SIM_DELAY)
    )refresh_busy_cnt(
        .clk(clk),
        .rst_n(rst_n),
        .cd(tRC_p),
        .timer_trigger(refresh_start),
        .timer_done(),
        .timer_ready(refresh_busy_n),
        .timer_v()
    );
    // 自动预充电忙碌计数器
    cool_down_cnt #(
        .max_cd(tATRFS_p + 1),
		.EN_TRG_IN_CD("true"),
		.SIM_DELAY(SIM_DELAY)
    )auto_precharge_cnt(
        .clk(clk),
        .rst_n(rst_n),
        .cd(tATRFS_p),
        .timer_trigger(auto_precharge_start),
        .timer_done(auto_precharge_itv_done),
        .timer_ready(auto_precharge_busy_n),
        .timer_v()
    );
    // 激活同一bank的冷却计数器
    genvar bank_active_same_cd_cnt_i;
    generate
        for(bank_active_same_cd_cnt_i = 0;bank_active_same_cd_cnt_i < 4;bank_active_same_cd_cnt_i = bank_active_same_cd_cnt_i + 1)
        begin:bank_active_same_cd_cnt_blk
            cool_down_cnt #(
                .max_cd(tRC_p + 1),
				.EN_TRG_IN_CD("true"),
				.SIM_DELAY(SIM_DELAY)
            )bank_active_same_cd_cnt(
                .clk(clk),
                .rst_n(rst_n),
                .cd(tRC_p),
                .timer_trigger(bank_active_same_cd_trigger[bank_active_same_cd_cnt_i]),
                .timer_done(),
                .timer_ready(bank_active_same_cd_ready[bank_active_same_cd_cnt_i]),
                .timer_v()
            );
        end
    endgenerate
    // 激活不同bank的冷却计数器
    genvar bank_active_diff_cd_cnt_i;
    generate
        for(bank_active_diff_cd_cnt_i = 0;bank_active_diff_cd_cnt_i < 4;bank_active_diff_cd_cnt_i = bank_active_diff_cd_cnt_i + 1)
        begin:bank_active_diff_cd_cnt_blk
            cool_down_cnt #(
                .max_cd(tRRD_p + 1),
				.EN_TRG_IN_CD("true"),
				.SIM_DELAY(SIM_DELAY)
            )bank_active_diff_cd_cnt(
                .clk(clk),
                .rst_n(rst_n),
                .cd(tRRD_p),
                .timer_trigger(bank_active_diff_cd_trigger[bank_active_diff_cd_cnt_i]),
                .timer_done(),
                .timer_ready(bank_active_diff_cd_ready[bank_active_diff_cd_cnt_i]),
                .timer_v()
            );
        end
    endgenerate
    // 激活到读写的等待计数器
    genvar bank_active_to_rw_itv_cnt_i;
    generate
        for(bank_active_to_rw_itv_cnt_i = 0;bank_active_to_rw_itv_cnt_i < 4;bank_active_to_rw_itv_cnt_i = bank_active_to_rw_itv_cnt_i + 1)
        begin:bank_active_to_rw_itv_cnt_blk
            cool_down_cnt #(
                .max_cd(tRCD_p + 1),
				.EN_TRG_IN_CD("true"),
				.SIM_DELAY(SIM_DELAY)
            )bank_active_to_rw_itv_cnt(
                .clk(clk),
                .rst_n(rst_n),
                .cd(tRCD_p),
                .timer_trigger(bank_active_to_rw_itv_trigger[bank_active_to_rw_itv_cnt_i]),
                .timer_done(),
                .timer_ready(bank_active_to_rw_itv_ready[bank_active_to_rw_itv_cnt_i]),
                .timer_v()
            );
        end
    endgenerate
    
    // 预充电到刷新/激活同一bank/设置模式寄存器的等待计数器
    genvar precharge_itv_cnt_i;
    generate
        for(precharge_itv_cnt_i = 0;precharge_itv_cnt_i < 4;precharge_itv_cnt_i = precharge_itv_cnt_i + 1)
        begin:precharge_itv_cnt_blk
            cool_down_cnt #(
                .max_cd(tRP_p + 1),
				.EN_TRG_IN_CD("true"),
				.SIM_DELAY(SIM_DELAY)
            )precharge_itv_cnt(
                .clk(clk),
                .rst_n(rst_n),
                .cd(tRP_p),
                .timer_trigger(bank_precharge_itv_trigger[precharge_itv_cnt_i]),
                .timer_done(bank_precharge_itv_done[precharge_itv_cnt_i]),
                .timer_ready(bank_precharge_itv_ready[precharge_itv_cnt_i]),
                .timer_v()
            );
        end
    endgenerate
    
    genvar bank_precharge_same_cd_cnt_i;
    generate
        for(bank_precharge_same_cd_cnt_i = 0;bank_precharge_same_cd_cnt_i < 4;bank_precharge_same_cd_cnt_i = bank_precharge_same_cd_cnt_i + 1)
        begin:bank_precharge_same_cd_cnt_blk
            cool_down_cnt #(
                .max_cd(tRAS_min_p + 1),
				.EN_TRG_IN_CD("true"),
				.SIM_DELAY(SIM_DELAY)
            )bank_precharge_same_cd_cnt(
                .clk(clk),
                .rst_n(rst_n),
                .cd(tRAS_min_p),
                .timer_trigger(bank_precharge_same_cd_trigger[bank_precharge_same_cd_cnt_i]),
                .timer_done(),
                .timer_ready(bank_precharge_same_cd_ready[bank_precharge_same_cd_cnt_i]),
                .timer_v()
            );
        end
    endgenerate
    
    /** bank状态 **/
    wire[3:0] bank_rw_start; // 读写bank开始(指示)
    reg[1:0] bank_in_burst; // 正在进行读写突发的bank
    wire rw_burst_done; // 读写突发完成(指示)
    reg rw_burst_done_d; // 延迟1clk的读写突发完成(指示)
    reg[1:0] bank_sts[3:0]; // bank状态
    
    // 延迟1clk的读写突发完成(指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rw_burst_done_d <= 1'b0;
        else
            rw_burst_done_d <= # SIM_DELAY rw_burst_done;
    end
    
    genvar bank_sts_i;
    generate
        for(bank_sts_i = 0;bank_sts_i < 4;bank_sts_i = bank_sts_i + 1)
        begin:bank_sts_blk
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    bank_sts[bank_sts_i] <= STS_BANK_IDLE;
                else
                begin
                    case(bank_sts[bank_sts_i])
                        STS_BANK_IDLE: // 状态:空闲
                            if(bank_active_same_cd_trigger[bank_sts_i])
                                bank_sts[bank_sts_i] <= # SIM_DELAY STS_BANK_ACTIVE; // -> 状态:激活
                        STS_BANK_ACTIVE: // 状态:激活
                            if(bank_rw_start[bank_sts_i])
                                bank_sts[bank_sts_i] <= # SIM_DELAY STS_BANK_BURST; // -> 状态:突发进行中
                            else if(bank_precharge_itv_done[bank_sts_i] | // 预充电完成
                                ((rw_data_with_auto_precharge == "true") & auto_precharge_itv_done & (bank_in_burst == bank_sts_i))) // 自动预充电完成
                                bank_sts[bank_sts_i] <= # SIM_DELAY STS_BANK_IDLE; // -> 状态:空闲
                        STS_BANK_BURST: // 状态:突发进行中
                            // 当突发长度为1时, 直接返回"激活"状态
                            // 全页突发时, 需要额外的1clk来发送"停止突发"命令
                            if((BURST_LEN == -1) ? rw_burst_done_d:((BURST_LEN == 1) | rw_burst_done))
                                bank_sts[bank_sts_i] <= # SIM_DELAY STS_BANK_ACTIVE; // -> 状态:激活
                        default:
                            bank_sts[bank_sts_i] <= # SIM_DELAY STS_BANK_IDLE;
                    endcase
                end
            end
        end
    endgenerate
    
    /** 读写突发计数器 **/
    wire burst_start; // 开始突发(指示)
    reg burst_start_d; // 延迟1clk的开始突发(指示)
    reg wt_burst_start_d; // 延迟1clk的开始写突发(指示)
    reg[15:0] burst_len_d; // 延迟1clk的突发长度
    reg burst_transmitting; // 突发进行中(标志)
    reg[BURST_LEN_CNT_WIDTH-1:0] burst_len_cnt; // 突发长度计数器
    reg burst_last; // 突发中最后1次传输(指示)
    reg is_wt_burst_latched; // 锁存的是否写突发
    wire is_wt_burst; // 是否写突发
    reg addr10_latched; // 锁存的行/列地址第10位
    wire auto_add_burst_stop; // 自动添加"停止突发"命令
    reg auto_add_burst_stop_latched; // 锁存的自动添加"停止突发"命令
    reg[CAS_LATENCY:0] rd_burst_end_waiting; // 读突发完成后等待(计数器)
    reg to_add_burst_stop; // 添加"停止突发"命令(指示)
    
    assign new_burst_start = burst_start_d;
    assign is_write_burst = wt_burst_start_d;
    assign new_burst_len = burst_len_d;
    
    // 对全页突发来说, 突发长度可能为1, 突发开始的那1clk应直接对命令AXIS中的user作判断
    assign rw_burst_done = burst_transmitting ? burst_last:(burst_start & ((BURST_LEN == -1) & (m_axis_cmd_user[15:0] == 16'd0)));
    
    // 突发开始的那1clk应直接对命令AXIS中的data/user作判断
    assign is_wt_burst = burst_start ? (m_axis_cmd_data[SDRAM_CMD_CID+2:SDRAM_CMD_CID] == CMD_LOGI_WT_DATA):is_wt_burst_latched;
    assign auto_add_burst_stop = burst_start ? m_axis_cmd_user[16]:auto_add_burst_stop_latched;
    
    // 正在进行读写突发的bank
    always @(posedge clk)
    begin
        if(burst_start)
            bank_in_burst <= # SIM_DELAY m_axis_cmd_data[SDRAM_CMD_BS+1:SDRAM_CMD_BS];
    end
    
    // 延迟1clk的开始突发(指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            burst_start_d <= 1'b0;
        else
            burst_start_d <= # SIM_DELAY burst_start;
    end
    // 延迟1clk的开始写突发(指示)
    always @(posedge clk)
        wt_burst_start_d <= # SIM_DELAY m_axis_cmd_data[SDRAM_CMD_CID+2:SDRAM_CMD_CID] == CMD_LOGI_WT_DATA;
    // 延迟1clk的突发长度
    always @(posedge clk)
        burst_len_d <= # SIM_DELAY (BURST_LEN == -1) ? m_axis_cmd_user[15:0]:(BURST_LEN - 1);
    
    // 突发进行中(标志)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            burst_transmitting <= 1'b0;
        else
            // 对全页突发来说, 如果在突发开始的那1clk发现突发长度为1, "突发进行中"标志不再有效, 这是因为目前就是当前突发的最后1次传输
            burst_transmitting <= # SIM_DELAY 
				burst_transmitting ? (~burst_last):(burst_start & ((BURST_LEN != -1) | (m_axis_cmd_user[15:0] != 16'd0)));
    end
    // 突发长度计数器
    always @(posedge clk)
    begin
        if(burst_start)
            burst_len_cnt <= # SIM_DELAY (BURST_LEN == -1) ? m_axis_cmd_user[15:0]:(BURST_LEN - 1);
        else
            burst_len_cnt <= # SIM_DELAY burst_len_cnt - 1;
    end
    // 突发中最后1次传输(指示)
    always @(posedge clk)
    begin
        if(burst_start)
            burst_last <= # SIM_DELAY (BURST_LEN == -1) ? (m_axis_cmd_user[15:0] == 16'd1):(BURST_LEN == 2);
        else
            burst_last <= # SIM_DELAY burst_len_cnt == 2;
    end
    
    // 锁存的是否写突发
    always @(posedge clk)
    begin
        if(burst_start)
            is_wt_burst_latched <= # SIM_DELAY m_axis_cmd_data[SDRAM_CMD_CID+2:SDRAM_CMD_CID] == CMD_LOGI_WT_DATA;
    end
    // 锁存的行/列地址第10位
    always @(posedge clk)
    begin
        if(burst_start)
            addr10_latched <= # SIM_DELAY m_axis_cmd_data[SDRAM_CMD_ADDR+10];
    end
    
    // 锁存的自动添加"停止突发"命令
    always @(posedge clk)
    begin
        if(burst_start)
            auto_add_burst_stop_latched <= # SIM_DELAY m_axis_cmd_user[16];
    end
    
    // 读突发完成后等待(计数器)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_burst_end_waiting <= {{(CAS_LATENCY){1'b0}}, 1'b1};
        else if((rw_burst_done & (~is_wt_burst)) | (~rd_burst_end_waiting[0]))
            rd_burst_end_waiting <= # SIM_DELAY {rd_burst_end_waiting[CAS_LATENCY-1:0], rd_burst_end_waiting[CAS_LATENCY]};
    end
    
    // 添加"停止突发"命令(指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            to_add_burst_stop <= 1'b0;
        else
            to_add_burst_stop <= # SIM_DELAY 
				(
					(rw_burst_done & is_wt_burst) | // 注意: 给出"停止突发"命令的当前clk, 这个写数据不会被写入!
					rd_burst_end_waiting[1] // 注意: 对于读突发来说, 延迟1clk再给出"停止突发"命令, 这是因为最后1个读数据的保持时间太短了!
				) & auto_add_burst_stop;
    end
    
    /** 写突发结束等待计数器 **/
    // 断言:tWR_p不会太大, 比如<=9!
    reg[tWR_p:0] wt_burst_end_itv_cnt;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_burst_end_itv_cnt <= {{tWR_p{1'b0}}, 1'b1};
        else if((is_wt_burst & rw_burst_done) | (~wt_burst_end_itv_cnt[0]))
            wt_burst_end_itv_cnt <= # SIM_DELAY {wt_burst_end_itv_cnt[tWR_p-1:0], wt_burst_end_itv_cnt[tWR_p]};
    end
    
    /** 写模式寄存器等待 **/
    wire next_cmd_is_mr_set; // 下一命令是"设置模式寄存器"(指示)
	// 断言:tWR_p不会太大, 比如<=9!
    reg[tRSC_p:0] mr_set_itv_cnt; // 写模式寄存器等待(计数器)
    wire to_wait_for_mr_set_n; // 写模式寄存器等待(标志)
	
	assign to_wait_for_mr_set_n = mr_set_itv_cnt[0];
    
	// 写模式寄存器等待(计数器)
	always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            mr_set_itv_cnt <= {{tRSC_p{1'b0}}, 1'b1};
        else if(next_cmd_is_mr_set | (~mr_set_itv_cnt[0]))
            mr_set_itv_cnt <= # SIM_DELAY {mr_set_itv_cnt[tRSC_p-1:0], mr_set_itv_cnt[tRSC_p]};
    end
    
    /** 命令产生 **/
    // 下一命令
    wire[2:0] next_cmd_id; // 下一命令的逻辑编码
    wire[15:0] next_cmd_addr; // 下一命令的行/列地址
    wire[1:0] next_cmd_ba; // 下一命令的bank地址
    // 当前命令
    reg[3:0] now_cmd_ecd; // 当前命令的物理编码
    reg[15:0] now_cmd_addr; // 当前命令的行/列地址
    reg[1:0] now_cmd_ba; // 当前命令的bank地址
    
    assign m_axis_cmd_ready = 
		refresh_busy_n & // 自动刷新时的等待
        to_wait_for_mr_set_n & // 写模式寄存器等待
        (
			(ALLOW_AUTO_PRECHARGE == "false") | (BURST_LEN == -1) | 
			auto_precharge_busy_n
		) & // 自动预充电时的等待, 注意到全页突发时不可能存在自动预充电
        (
			(BURST_LEN == 1) | 
			(
				(~burst_transmitting) & (
					(BURST_LEN != -1) | (rd_burst_end_waiting[0] & (~rw_burst_done_d))
				)
			)
		) & // 读写数据期间应产生NOP命令, 对全页读突发来说结束后无论是否产生"停止突发"命令都不接受下面2/3条命令
        (
			(m_axis_cmd_data[SDRAM_CMD_CID+2:SDRAM_CMD_CID] == CMD_LOGI_BANK_ACTIVE) ? 
				(
					bank_active_same_cd_ready[next_cmd_ba] & 
					bank_active_diff_cd_ready[next_cmd_ba] & 
					bank_precharge_itv_ready[next_cmd_ba]
				): // BANK激活的冷却
			(m_axis_cmd_data[SDRAM_CMD_CID+2:SDRAM_CMD_CID] == CMD_LOGI_BANK_PRECHARGE) ? 
				(
					(next_cmd_addr[10] ? 
						(&bank_precharge_same_cd_ready):
						bank_precharge_same_cd_ready[next_cmd_ba]) & 
					wt_burst_end_itv_cnt[0]
				): // 预充电的冷却
			((m_axis_cmd_data[SDRAM_CMD_CID+2:SDRAM_CMD_CID] == CMD_LOGI_WT_DATA) | 
				(m_axis_cmd_data[SDRAM_CMD_CID+2:SDRAM_CMD_CID] == CMD_LOGI_RD_DATA)) ? 
				bank_active_to_rw_itv_ready[next_cmd_ba]: // 读写数据的冷却
			((m_axis_cmd_data[SDRAM_CMD_CID+2:SDRAM_CMD_CID] == CMD_LOGI_MR_SET) | 
				(m_axis_cmd_data[SDRAM_CMD_CID+2:SDRAM_CMD_CID] == CMD_LOGI_AUTO_REFRESH)) ? 
				(&bank_precharge_itv_ready): // 设置模式寄存器和自动刷新的冷却
			1'b1 // 空操作
		);
    
    assign {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = now_cmd_ecd;
    assign sdram_ba = now_cmd_ba;
    assign sdram_addr = now_cmd_addr;
    
    assign next_cmd_is_mr_set = next_cmd_id == CMD_LOGI_MR_SET;
    assign refresh_start = next_cmd_id == CMD_LOGI_AUTO_REFRESH;
    // 突发长度为1时, 在突发开始的那1clk直接对命令AXIS中的data作判断, 若为其他情况, 就在突发结束时判断
    // 注意到全页突发时不可能存在自动预充电
    assign auto_precharge_start = (BURST_LEN == 1) ? (burst_start & m_axis_cmd_data[SDRAM_CMD_ADDR+10]):(rw_burst_done & addr10_latched);
    
    genvar trigger_i;
    generate
        for(trigger_i = 0;trigger_i < 4;trigger_i = trigger_i + 1)
        begin:trigger_blk
            assign bank_active_same_cd_trigger[trigger_i] = (next_cmd_id == CMD_LOGI_BANK_ACTIVE) & (next_cmd_ba == trigger_i);
            assign bank_active_diff_cd_trigger[trigger_i] = (next_cmd_id == CMD_LOGI_BANK_ACTIVE) & (next_cmd_ba != trigger_i);
            assign bank_active_to_rw_itv_trigger[trigger_i] = (next_cmd_id == CMD_LOGI_BANK_ACTIVE) & (next_cmd_ba == trigger_i);
            assign bank_precharge_itv_trigger[trigger_i] = (next_cmd_id == CMD_LOGI_BANK_PRECHARGE) & (next_cmd_addr[10] | (next_cmd_ba == trigger_i));
            assign bank_precharge_same_cd_trigger[trigger_i] = (next_cmd_id == CMD_LOGI_BANK_ACTIVE) & (next_cmd_ba == trigger_i);
            
            assign bank_rw_start[trigger_i] = ((next_cmd_id == CMD_LOGI_WT_DATA) | (next_cmd_id == CMD_LOGI_RD_DATA)) & (next_cmd_ba == trigger_i);
        end
    endgenerate
    
    assign burst_start = (next_cmd_id == CMD_LOGI_WT_DATA) | (next_cmd_id == CMD_LOGI_RD_DATA);
    
    assign next_cmd_id = 
		(m_axis_cmd_valid & m_axis_cmd_ready) ? m_axis_cmd_data[SDRAM_CMD_CID+2:SDRAM_CMD_CID]: // 接受下一条命令
        ((BURST_LEN == -1) & to_add_burst_stop) ? CMD_LOGI_BURST_STOP: // 对全页突发来说结束后可能要产生"停止突发"命令
        CMD_LOGI_NOP;
    assign next_cmd_addr = m_axis_cmd_data[SDRAM_CMD_ADDR+15:SDRAM_CMD_ADDR];
    assign next_cmd_ba = m_axis_cmd_data[SDRAM_CMD_BS+1:SDRAM_CMD_BS];
    
    // 当前命令的物理编码
    // 逻辑编码 -> 物理编码
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            now_cmd_ecd <= CMD_PHY_DEV_DSEL;
        else
        begin
            case(next_cmd_id)
                CMD_LOGI_BANK_ACTIVE: now_cmd_ecd <= # SIM_DELAY CMD_PHY_BANK_ACTIVE;
                CMD_LOGI_BANK_PRECHARGE: now_cmd_ecd <= # SIM_DELAY CMD_PHY_BANK_PRECHARGE;
                CMD_LOGI_WT_DATA: now_cmd_ecd <= # SIM_DELAY CMD_PHY_WT_DATA;
                CMD_LOGI_RD_DATA: now_cmd_ecd <= # SIM_DELAY CMD_PHY_RD_DATA;
                CMD_LOGI_MR_SET: now_cmd_ecd <= # SIM_DELAY CMD_PHY_MR_SET;
                CMD_LOGI_AUTO_REFRESH: now_cmd_ecd <= # SIM_DELAY CMD_PHY_AUTO_REFRESH;
                CMD_LOGI_BURST_STOP: now_cmd_ecd <= # SIM_DELAY CMD_PHY_BURST_STOP;
                CMD_LOGI_NOP: now_cmd_ecd <= # SIM_DELAY CMD_PHY_DEV_DSEL;
                default: now_cmd_ecd <= # SIM_DELAY CMD_PHY_DEV_DSEL;
            endcase
        end
    end
    // 当前命令的行/列地址
    always @(posedge clk)
        now_cmd_addr <= # SIM_DELAY next_cmd_addr;
    // 当前命令的bank地址
    always @(posedge clk)
        now_cmd_ba <= # SIM_DELAY next_cmd_ba;
    
    /** 异常指示 **/
    reg pcg_spcf_idle_bank_err_reg; // 预充电空闲的特定bank(异常指示)
    reg pcg_spcf_bank_tot_err_reg; // 预充电特定bank超时(异常指示)
    reg rw_idle_bank_err_reg; // 读写空闲的bank(异常指示)
    reg rfs_with_act_banks_err_reg; // 刷新时带有已激活的bank(异常指示)
    reg illegal_logic_cmd_err_reg; // 非法的逻辑命令编码(异常指示)
    reg rw_cross_line_err_reg; // 跨行的读写命令(异常指示)
    wire[16:0] col_addr_add_burst_len; // 列地址 + 突发长度
    reg[clogb2(tRAS_max_p-1):0] pcg_tot_cnt[3:0]; // 预充电特定bank超时计数器
    
    assign pcg_spcf_idle_bank_err = (EN_EXPT_TIP == "true") & pcg_spcf_idle_bank_err_reg;
    assign pcg_spcf_bank_tot_err = (EN_EXPT_TIP == "true") & pcg_spcf_bank_tot_err_reg;
    assign rw_idle_bank_err = (EN_EXPT_TIP == "true") & rw_idle_bank_err_reg;
    assign rfs_with_act_banks_err = (EN_EXPT_TIP == "true") & rfs_with_act_banks_err_reg;
    assign illegal_logic_cmd_err = (EN_EXPT_TIP == "true") & illegal_logic_cmd_err_reg;
    assign rw_cross_line_err = (EN_EXPT_TIP == "true") & rw_cross_line_err_reg;
    
    assign col_addr_add_burst_len = 
		m_axis_cmd_data[SDRAM_CMD_ADDR+15:SDRAM_CMD_ADDR] + 
		((BURST_LEN == -1) ? m_axis_cmd_user[15:0]:(BURST_LEN - 1));
    
    // 预充电空闲的特定bank(异常指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            pcg_spcf_idle_bank_err_reg <= 1'b0;
        else
            pcg_spcf_idle_bank_err_reg <= # SIM_DELAY 
				(next_cmd_id == CMD_LOGI_BANK_PRECHARGE) & (bank_sts[next_cmd_ba] == STS_BANK_IDLE) & (~next_cmd_addr[10]);
    end
    // 预充电特定bank超时(异常指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            pcg_spcf_bank_tot_err_reg <= 1'b0;
        else
            pcg_spcf_bank_tot_err_reg <= # SIM_DELAY 
				((bank_sts[0] != STS_BANK_IDLE) & (pcg_tot_cnt[0] == 0)) | 
                ((bank_sts[1] != STS_BANK_IDLE) & (pcg_tot_cnt[1] == 0)) | 
                ((bank_sts[2] != STS_BANK_IDLE) & (pcg_tot_cnt[2] == 0)) | 
                ((bank_sts[3] != STS_BANK_IDLE) & (pcg_tot_cnt[3] == 0));
    end
    // 读写空闲的bank(异常指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rw_idle_bank_err_reg <= 1'b0;
        else
            rw_idle_bank_err_reg <= # SIM_DELAY 
				((next_cmd_id == CMD_LOGI_WT_DATA) | (next_cmd_id == CMD_LOGI_RD_DATA)) & (bank_sts[next_cmd_ba] == STS_BANK_IDLE);
    end
    // 刷新时带有已激活的bank(异常指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rfs_with_act_banks_err_reg <= 1'b0;
        else
            rfs_with_act_banks_err_reg <= # SIM_DELAY 
				(next_cmd_id == CMD_LOGI_AUTO_REFRESH) & 
                (
					(bank_sts[0] != STS_BANK_IDLE) | 
					(bank_sts[1] != STS_BANK_IDLE) | 
					(bank_sts[2] != STS_BANK_IDLE) | 
					(bank_sts[3] != STS_BANK_IDLE)
				);
    end
    // 非法的逻辑命令编码(异常指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            illegal_logic_cmd_err_reg <= 1'b0;
        else
            illegal_logic_cmd_err_reg <= # SIM_DELAY 
				(m_axis_cmd_valid & m_axis_cmd_ready) & 
                (m_axis_cmd_data[SDRAM_CMD_CID+2:SDRAM_CMD_CID] == CMD_LOGI_BURST_STOP);
    end
    // 跨行的读写命令(异常指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rw_cross_line_err_reg <= 1'b0;
        else
            rw_cross_line_err_reg <= # SIM_DELAY 
				(m_axis_cmd_valid & m_axis_cmd_ready) & 
                ((m_axis_cmd_data[SDRAM_CMD_CID+2:SDRAM_CMD_CID] == CMD_LOGI_WT_DATA) | 
					(m_axis_cmd_data[SDRAM_CMD_CID+2:SDRAM_CMD_CID] == CMD_LOGI_RD_DATA)) & 
                col_addr_add_burst_len[clogb2(SDRAM_COL_N-1)+1];
    end
    
    // 预充电特定bank超时计数器
    genvar pcg_tot_i;
    generate
        for(pcg_tot_i = 0;pcg_tot_i < 4;pcg_tot_i = pcg_tot_i + 1)
        begin:pcg_tot_blk
            always @(posedge clk)
            begin
                if(bank_active_same_cd_trigger[pcg_tot_i] | bank_precharge_itv_trigger[pcg_tot_i])
                    pcg_tot_cnt[pcg_tot_i] <= # SIM_DELAY tRAS_max_p - 1;
                else if(bank_sts[pcg_tot_i] != STS_BANK_IDLE)
                    pcg_tot_cnt[pcg_tot_i] <= # SIM_DELAY pcg_tot_cnt[pcg_tot_i] - 1;
            end
        end
    endgenerate
    
endmodule
