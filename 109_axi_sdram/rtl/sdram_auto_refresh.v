`timescale 1ns / 1ps
/********************************************************************
本模块: sdram自动刷新控制器

描述:
根据要求的刷新间隔, 产生自动刷新命令流

自动刷新预警有效时, 等待所有bank空闲时才刷新
强制自动刷新时, 不再等待所有bank空闲时才刷新, 但在刷新结束后会重新激活之前的行

注意：
强制刷新间隔必须>刷新间隔

协议:
AXIS MASTER

作者: 陈家耀
日期: 2024/04/17
********************************************************************/


module sdram_auto_refresh #(
    parameter real clk_period = 7.0, // 时钟周期
    parameter real refresh_itv = 64.0 * 1000.0 * 1000.0 / 4096.0 * 0.8, // 刷新间隔(以ns计)
    parameter real forced_refresh_itv = 64.0 * 1000.0 * 1000.0 / 4096.0 * 0.9, // 强制刷新间隔(以ns计)
    parameter integer burst_len = -1, // 突发长度(-1 -> 全页; 1 | 2 | 4 | 8)
    parameter allow_auto_precharge = "true" // 是否允许自动预充电
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 自动刷新定时开始(指示)
    input wire start_rfs_timing,
    // 刷新控制器运行中
    output wire rfs_ctrler_running,
    
    // sdram命令代理输入监测
    input wire[15:0] s_axis_cmd_agent_monitor_data, // {BS(2bit), A10-0(11bit), 命令号(3bit)}
    input wire s_axis_cmd_agent_monitor_valid,
    input wire s_axis_cmd_agent_monitor_ready,
    
    // 自动刷新命令流AXIS
    output wire[15:0] m_axis_rfs_data, // {BS(2bit), A10-0(11bit), 命令号(3bit)}
    output wire m_axis_rfs_valid,
    input wire m_axis_rfs_ready
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

    /** 常量 **/
    localparam integer refresh_itv_p = $floor(refresh_itv / clk_period); // 刷新间隔周期数
    localparam integer forced_refresh_itv_p = $floor(forced_refresh_itv / clk_period); // 强制刷新间隔周期数
    localparam rw_data_with_auto_precharge = (burst_len == -1) ? "false":allow_auto_precharge; // 使能读写数据命令的自动预充电
    // 命令的逻辑编码
    localparam CMD_LOGI_BANK_ACTIVE = 3'b000; // 命令:激活bank
    localparam CMD_LOGI_BANK_PRECHARGE = 3'b001; // 命令:预充电bank
    localparam CMD_LOGI_WT_DATA = 3'b010; // 命令:写数据
    localparam CMD_LOGI_RD_DATA = 3'b011; // 命令:读数据
    localparam CMD_LOGI_AUTO_REFRESH = 3'b101; // 命令:自动刷新
    // 自动刷新状态
    localparam RFS_NOT_START = 2'b00; // 状态:刷新未开始
    localparam RFS_CMD_PRECHARGE_ALL = 2'b01; // 状态:发送"预充电"命令
    localparam RFS_CMD_REFRESH = 2'b10; // 状态:发送"刷新"命令
    localparam RFS_CMD_ACTIVE = 2'b11; // 状态:发送"激活"命令
    // 实现方式(1 | 2)
    // 方式1 -> 效率高, 时序差, 资源多; 方式2 -> 效率低, 时序好, 资源少
    localparam integer impl_method = 2;
    
    /**
    bank空闲与激活状态判定
    
    这里对齐到sdram命令代理的命令AXIS输入, 并非真实的bank空闲与激活状态
    **/
    wire rfs_launched; // 启动自动刷新
    reg[3:0] is_spec_bank_idle; // 各个bank是否idle
    wire next_all_bank_idle; // 下1clk的每个bank均idle
    wire[3:0] ba_onehot; // 独热码的bank地址
    reg[10:0] bank_active_row[3:0]; // bank被激活的行
    reg rfs_launched_d; // 延迟1clk的启动自动刷新
    reg all_bank_idle_lateched; // 锁存的每个bank均idle
    reg[3:0] is_spec_bank_active_lateched; // 锁存的各个bank是否active
    reg[2:0] bank_active_n; // 锁存的激活bank的个数
    reg[10:0] bank_active_row_lateched[3:0]; // 锁存的bank被激活的行
    reg[1:0] bank_active_id_latched[3:0]; // 锁存的激活bank编号
    
    assign ba_onehot = (s_axis_cmd_agent_monitor_data[15:14] == 2'b00) ? 4'b0001:
        (s_axis_cmd_agent_monitor_data[15:14] == 2'b01) ? 4'b0010:
        (s_axis_cmd_agent_monitor_data[15:14] == 2'b10) ? 4'b0100:
                                                          4'b1000;
    assign next_all_bank_idle = (s_axis_cmd_agent_monitor_valid & s_axis_cmd_agent_monitor_ready) ?
        ((s_axis_cmd_agent_monitor_data[2:0] == CMD_LOGI_BANK_ACTIVE) ? 1'b0: // 激活
            (s_axis_cmd_agent_monitor_data[2:0] == CMD_LOGI_BANK_PRECHARGE) ? (s_axis_cmd_agent_monitor_data[13] | (&(is_spec_bank_idle | ba_onehot))): // 预充电
            (((s_axis_cmd_agent_monitor_data[2:0] == CMD_LOGI_WT_DATA) | (s_axis_cmd_agent_monitor_data[2:0] == CMD_LOGI_RD_DATA)) & 
                s_axis_cmd_agent_monitor_data[13] & (rw_data_with_auto_precharge == "true")) ? (&(is_spec_bank_idle | ba_onehot)): // 带自动预充电的读写
            (&is_spec_bank_idle)):
        (&is_spec_bank_idle);
    
    // 各个bank是否idle
    // bank被激活的行
    genvar is_spec_bank_idle_i;
    genvar bank_active_row_i;
    generate
        // 各个bank是否idle
        for(is_spec_bank_idle_i = 0;is_spec_bank_idle_i < 4;is_spec_bank_idle_i = is_spec_bank_idle_i + 1)
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    is_spec_bank_idle[is_spec_bank_idle_i] <= 1'b1;
                else if((s_axis_cmd_agent_monitor_valid & s_axis_cmd_agent_monitor_ready) & 
                    (((s_axis_cmd_agent_monitor_data[2:0] == CMD_LOGI_BANK_ACTIVE) & (s_axis_cmd_agent_monitor_data[15:14] == is_spec_bank_idle_i)) | // 激活
                        ((s_axis_cmd_agent_monitor_data[2:0] == CMD_LOGI_BANK_PRECHARGE) & 
                        ((s_axis_cmd_agent_monitor_data[15:14] == is_spec_bank_idle_i) | s_axis_cmd_agent_monitor_data[13])) | // 预充电
                        (((s_axis_cmd_agent_monitor_data[2:0] == CMD_LOGI_WT_DATA) | (s_axis_cmd_agent_monitor_data[2:0] == CMD_LOGI_RD_DATA)) & 
                            s_axis_cmd_agent_monitor_data[13] & (s_axis_cmd_agent_monitor_data[15:14] == is_spec_bank_idle_i) & (rw_data_with_auto_precharge == "true")))) // 带自动预充电的读写
                    is_spec_bank_idle[is_spec_bank_idle_i] <= s_axis_cmd_agent_monitor_data[2:0] != CMD_LOGI_BANK_ACTIVE;
            end
        end
        
        // bank被激活的行
        for(bank_active_row_i = 0;bank_active_row_i < 4;bank_active_row_i = bank_active_row_i + 1)
        begin
            always @(posedge clk)
            begin
                if((s_axis_cmd_agent_monitor_valid & s_axis_cmd_agent_monitor_ready) & 
                    ((s_axis_cmd_agent_monitor_data[2:0] == CMD_LOGI_BANK_ACTIVE) & (s_axis_cmd_agent_monitor_data[15:14] == bank_active_row_i)))
                    bank_active_row[bank_active_row_i] <= s_axis_cmd_agent_monitor_data[13:3];
            end
        end
    endgenerate
    
    // 锁存的每个bank均idle
    always @(posedge clk)
    begin
        if(rfs_launched)
            all_bank_idle_lateched <= next_all_bank_idle;
    end
    
    // 延迟1clk的启动自动刷新
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rfs_launched_d <= 1'b0;
        else
            rfs_launched_d <= rfs_launched;
    end
    
    // 锁存的各个bank是否active
    always @(posedge clk)
    begin
        if(rfs_launched_d)
            is_spec_bank_active_lateched <= ~is_spec_bank_idle;
    end
    
    // 锁存的激活bank的个数
    always @(posedge clk)
    begin
        if(rfs_launched_d)
        begin
            bank_active_n <= (~is_spec_bank_idle[0]) + (~is_spec_bank_idle[1]) + 
                (~is_spec_bank_idle[2]) + (~is_spec_bank_idle[3]);
        end
    end
    
    // 锁存的bank被激活的行
    generate
        if(impl_method == 1)
        begin
            always @(posedge clk)
            begin
                if(rfs_launched_d)
                begin
                    case(is_spec_bank_idle)
                        4'b0000: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[0], bank_active_row[1], bank_active_row[2], bank_active_row[3]};
                        4'b0001: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[1], bank_active_row[2], bank_active_row[3], 11'dx};
                        4'b0010: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[0], bank_active_row[2], bank_active_row[3], 11'dx};
                        4'b0011: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[2], bank_active_row[3], 11'dx, 11'dx};
                        4'b0100: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[0], bank_active_row[1], bank_active_row[3], 11'dx};
                        4'b0101: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[1], bank_active_row[3], 11'dx, 11'dx};
                        4'b0110: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[0], bank_active_row[3], 11'dx, 11'dx};
                        4'b0111: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[3], 11'dx, 11'dx, 11'dx};
                        4'b1000: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[0], bank_active_row[1], bank_active_row[2], 11'dx};
                        4'b1001: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[1], bank_active_row[2], 11'dx, 11'dx};
                        4'b1010: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[0], bank_active_row[2], 11'dx, 11'dx};
                        4'b1011: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[2], 11'dx, 11'dx, 11'dx};
                        4'b1100: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[0], bank_active_row[1], 11'dx, 11'dx};
                        4'b1101: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[1], 11'dx, 11'dx, 11'dx};
                        4'b1110: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[0], 11'dx, 11'dx, 11'dx};
                        4'b1111: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {11'dx, 11'dx, 11'dx, 11'dx};
                        default: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {11'dx, 11'dx, 11'dx, 11'dx};
                    endcase
                end
            end
        end
        else
        begin
            always @(posedge clk)
            begin
                if(rfs_launched_d)
                    {bank_active_row_lateched[3], bank_active_row_lateched[2], bank_active_row_lateched[1], bank_active_row_lateched[0]} <= 
                        {bank_active_row[3], bank_active_row[2], bank_active_row[1], bank_active_row[0]};
            end
        end
    endgenerate
    
    // 锁存的激活bank编号
    always @(posedge clk)
    begin
        if(rfs_launched_d)
        begin
            case(is_spec_bank_idle)
                4'b0000: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b00, 2'b01, 2'b10, 2'b11};
                4'b0001: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b01, 2'b10, 2'b11, 2'bxx};
                4'b0010: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b00, 2'b10, 2'b11, 2'bxx};
                4'b0011: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b10, 2'b11, 2'bxx, 2'bxx};
                4'b0100: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b00, 2'b01, 2'b11, 2'bxx};
                4'b0101: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b01, 2'b11, 2'bxx, 2'bxx};
                4'b0110: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b00, 2'b11, 2'bxx, 2'bxx};
                4'b0111: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b11, 2'bxx, 2'bxx, 2'bxx};
                4'b1000: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b00, 2'b01, 2'b10, 2'bxx};
                4'b1001: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b01, 2'b10, 2'bxx, 2'bxx};
                4'b1010: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b00, 2'b10, 2'bxx, 2'bxx};
                4'b1011: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b10, 2'bxx, 2'bxx, 2'bxx};
                4'b1100: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b00, 2'b01, 2'bxx, 2'bxx};
                4'b1101: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b01, 2'bxx, 2'bxx, 2'bxx};
                4'b1110: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b00, 2'bxx, 2'bxx, 2'bxx};
                4'b1111: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'bxx, 2'bxx, 2'bxx, 2'bxx};
                default: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'bxx, 2'bxx, 2'bxx, 2'bxx};
            endcase
        end
    end
    
    /** 自动刷新计数器 **/
    reg rfs_cnt_en; // 自动刷新计数器使能
    reg[clogb2(forced_refresh_itv_p-1):0] rfs_cnt; // 自动刷新计数器
    reg rfs_alarm; // 自动刷新预警(标志)
    reg forced_rfs_start; // 开始强制自动刷新(指示)
    
    assign rfs_launched = (rfs_alarm & next_all_bank_idle) | forced_rfs_start;
    
    // 自动刷新计数器使能
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rfs_cnt_en <= 1'b0;
        else if(~rfs_cnt_en)
            rfs_cnt_en <= start_rfs_timing;
    end
    // 自动刷新计数器
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rfs_cnt <= 0;
        else if(rfs_launched_d) // 打1拍再清零也无所谓
            rfs_cnt <= 0;
        else if(rfs_cnt_en)
            rfs_cnt <= (rfs_cnt == (forced_refresh_itv_p - 1)) ? 0:(rfs_cnt + 1);
    end
    // 自动刷新预警(标志)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rfs_alarm <= 1'b0;
        else if(rfs_launched)
            rfs_alarm <= 1'b0;
        else if(~rfs_alarm)
            rfs_alarm <= rfs_cnt == (refresh_itv_p - 1);
    end
    // 开始强制自动刷新(指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            forced_rfs_start <= 1'b0;
        else
            forced_rfs_start <= rfs_cnt == (forced_refresh_itv_p - 1);
    end
    
    /** 自动刷新流程控制 **/
    reg[1:0] rfs_sts; // 自动刷新的当前状态
    reg[2:0] active_cnt; // 激活bank计数器
    reg[2:0] active_cnt_add1; // 激活bank计数器 + 1
    reg rfs_ctrler_running_reg; // 刷新控制器运行中
    
    assign rfs_ctrler_running = rfs_ctrler_running_reg;
    
    // 自动刷新的当前状态
    // 激活bank计数器
    // 刷新控制器运行中
    generate
        if(impl_method == 1)
        begin
            // 自动刷新的当前状态
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rfs_sts <= RFS_NOT_START;
                else
                begin
                    case(rfs_sts)
                        RFS_NOT_START: // 状态:刷新未开始
                            if(rfs_launched)
                                rfs_sts <= next_all_bank_idle ? RFS_CMD_REFRESH: // -> 状态:发送"刷新"命令
                                    RFS_CMD_PRECHARGE_ALL; // -> 状态:发送"预充电"命令
                        RFS_CMD_PRECHARGE_ALL: // 状态:发送"预充电"命令
                            if(m_axis_rfs_ready)
                                rfs_sts <= RFS_CMD_REFRESH; // -> 状态:发送"刷新"命令
                        RFS_CMD_REFRESH: // 状态:发送"刷新"命令
                            if(m_axis_rfs_ready)
                                rfs_sts <= all_bank_idle_lateched ? RFS_NOT_START: // -> 状态:刷新未开始
                                    RFS_CMD_ACTIVE; // -> 状态:发送"激活"命令
                        RFS_CMD_ACTIVE: // 状态:发送"激活"命令
                            if(m_axis_rfs_ready & (active_cnt == bank_active_n))
                                rfs_sts <= RFS_NOT_START; // -> 状态:刷新未开始
                        default:
                            rfs_sts <= RFS_NOT_START;
                    endcase
                end
            end
            
            // 激活bank计数器
            always @(posedge clk)
            begin
                if((rfs_sts == RFS_CMD_REFRESH) & m_axis_rfs_ready & (~all_bank_idle_lateched))
                    active_cnt <= 3'd1;
                else if((rfs_sts == RFS_CMD_ACTIVE) & m_axis_rfs_ready)
                    active_cnt <= active_cnt + 3'd1;
            end
            
            // 刷新控制器运行中
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rfs_ctrler_running_reg <= 1'b0;
                else
                begin
                    case(rfs_sts)
                        RFS_NOT_START: // 状态:刷新未开始
                            rfs_ctrler_running_reg <= rfs_launched;
                        RFS_CMD_REFRESH: // 状态:发送"刷新"命令
                            rfs_ctrler_running_reg <= ~(m_axis_rfs_ready & all_bank_idle_lateched);
                        RFS_CMD_ACTIVE: // 状态:发送"激活"命令
                            rfs_ctrler_running_reg <= ~(m_axis_rfs_ready & (active_cnt == bank_active_n));
                        default:
                            rfs_ctrler_running_reg <= rfs_ctrler_running_reg;
                    endcase
                end
            end
        end
        else
        begin
            // 自动刷新的当前状态
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rfs_sts <= RFS_NOT_START;
                else
                begin
                    case(rfs_sts)
                        RFS_NOT_START: // 状态:刷新未开始
                            if(rfs_launched)
                                rfs_sts <= next_all_bank_idle ? RFS_CMD_REFRESH: // -> 状态:发送"刷新"命令
                                    RFS_CMD_PRECHARGE_ALL; // -> 状态:发送"预充电"命令
                        RFS_CMD_PRECHARGE_ALL: // 状态:发送"预充电"命令
                            if(m_axis_rfs_ready)
                                rfs_sts <= RFS_CMD_REFRESH; // -> 状态:发送"刷新"命令
                        RFS_CMD_REFRESH: // 状态:发送"刷新"命令
                            if(m_axis_rfs_ready)
                                rfs_sts <= all_bank_idle_lateched ? RFS_NOT_START: // -> 状态:刷新未开始
                                    RFS_CMD_ACTIVE; // -> 状态:发送"激活"命令
                        RFS_CMD_ACTIVE: // 状态:发送"激活"命令
                            if(active_cnt[2])
                                rfs_sts <= RFS_NOT_START; // -> 状态:刷新未开始
                        default:
                            rfs_sts <= RFS_NOT_START;
                    endcase
                end
            end
            
            // 激活bank计数器
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    active_cnt <= 3'd0;
                else if((rfs_sts == RFS_CMD_ACTIVE) & (((~is_spec_bank_active_lateched[active_cnt]) | m_axis_rfs_ready) | active_cnt[2]))
                    active_cnt <= active_cnt[2] ? 3'd0:(active_cnt + 3'd1);
            end
            // 激活bank计数器 + 1
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    active_cnt_add1 <= 3'd1;
                else if((rfs_sts == RFS_CMD_ACTIVE) & (((~is_spec_bank_active_lateched[active_cnt]) | m_axis_rfs_ready) | active_cnt[2]))
                    active_cnt_add1 <= active_cnt[2] ? 3'd1:(active_cnt_add1 + 3'd1);
            end
            
            // 刷新控制器运行中
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rfs_ctrler_running_reg <= 1'b0;
                else
                begin
                    case(rfs_sts)
                        RFS_NOT_START: // 状态:刷新未开始
                            rfs_ctrler_running_reg <= rfs_launched;
                        RFS_CMD_REFRESH: // 状态:发送"刷新"命令
                            rfs_ctrler_running_reg <= ~(m_axis_rfs_ready & all_bank_idle_lateched);
                        RFS_CMD_ACTIVE: // 状态:发送"激活"命令
                            rfs_ctrler_running_reg <= ~active_cnt[2];
                        default:
                            rfs_ctrler_running_reg <= rfs_ctrler_running_reg;
                    endcase
                end
            end
        end
    endgenerate
    
    /** 自动刷新命令流AXIS **/
    reg[15:0] now_cmd; // 当前命令
    reg cmd_valid; // 命令有效
    
    assign m_axis_rfs_data = now_cmd;
    assign m_axis_rfs_valid = cmd_valid;
    
    // 当前命令
    // 命令有效
    generate
        if(impl_method == 1)
        begin
            // 当前命令
            always @(posedge clk)
            begin
                case(rfs_sts)
                    RFS_NOT_START: // 状态:刷新未开始
                        now_cmd <= next_all_bank_idle ? {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_AUTO_REFRESH}:
                            {2'bxx, 11'b1_xxxxx_xxxxx, CMD_LOGI_BANK_PRECHARGE};
                    RFS_CMD_PRECHARGE_ALL: // 状态:发送"预充电"命令
                        if(m_axis_rfs_ready)
                            now_cmd <= {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_AUTO_REFRESH};
                    RFS_CMD_REFRESH: // 状态:发送"刷新"命令
                        if(m_axis_rfs_ready)
                            now_cmd <= all_bank_idle_lateched ? 16'dx:
                                {2'b00, bank_active_row_lateched[0], CMD_LOGI_BANK_ACTIVE};
                    RFS_CMD_ACTIVE: // 状态:发送"激活"命令
                        if(m_axis_rfs_ready)
                            now_cmd <= {bank_active_id_latched[active_cnt[1:0]], bank_active_row_lateched[active_cnt[1:0]], CMD_LOGI_BANK_ACTIVE};
                    default:
                        now_cmd <= now_cmd;
                endcase
            end
            // 命令有效
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    cmd_valid <= 1'b0;
                else
                begin
                    case(rfs_sts)
                        RFS_NOT_START: // 状态:刷新未开始
                            cmd_valid <= rfs_launched;
                        RFS_CMD_REFRESH: // 状态:发送"刷新"命令
                            if(m_axis_rfs_ready)
                                cmd_valid <= ~all_bank_idle_lateched;
                        RFS_CMD_ACTIVE: // 状态:发送"激活"命令
                            if(m_axis_rfs_ready)
                                cmd_valid <= active_cnt != bank_active_n;
                        default:
                            cmd_valid <= cmd_valid;
                    endcase
                end
            end
        end
        else
        begin
            // 当前命令
            always @(posedge clk)
            begin
                case(rfs_sts)
                    RFS_NOT_START: // 状态:刷新未开始
                        now_cmd <= next_all_bank_idle ? {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_AUTO_REFRESH}:
                            {2'bxx, 11'b1_xxxxx_xxxxx, CMD_LOGI_BANK_PRECHARGE};
                    RFS_CMD_PRECHARGE_ALL: // 状态:发送"预充电"命令
                        if(m_axis_rfs_ready)
                            now_cmd <= {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_AUTO_REFRESH};
                    RFS_CMD_REFRESH: // 状态:发送"刷新"命令
                        if(m_axis_rfs_ready)
                            now_cmd <= all_bank_idle_lateched ? 16'dx:
                                {2'b00, bank_active_row_lateched[0], CMD_LOGI_BANK_ACTIVE};
                    RFS_CMD_ACTIVE: // 状态:发送"激活"命令
                        if(active_cnt[2])
                            now_cmd <= 16'dx;
                        else if((~is_spec_bank_active_lateched[active_cnt]) | m_axis_rfs_ready)
                            now_cmd <= {active_cnt_add1[1:0], bank_active_row_lateched[active_cnt_add1[1:0]], CMD_LOGI_BANK_ACTIVE};
                    default:
                        now_cmd <= now_cmd;
                endcase
            end
            // 命令有效
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    cmd_valid <= 1'b0;
                else
                begin
                    case(rfs_sts)
                        RFS_NOT_START: // 状态:刷新未开始
                            cmd_valid <= rfs_launched;
                        RFS_CMD_REFRESH: // 状态:发送"刷新"命令
                            if(m_axis_rfs_ready)
                                cmd_valid <= all_bank_idle_lateched ? 1'b0:is_spec_bank_active_lateched[0];
                        RFS_CMD_ACTIVE: // 状态:发送"激活"命令
                            if(active_cnt[2])
                                cmd_valid <= 1'b0;
                            else if((~is_spec_bank_active_lateched[active_cnt]) | m_axis_rfs_ready)
                                cmd_valid <= (active_cnt != 3'd3) & is_spec_bank_active_lateched[active_cnt_add1[1:0]];
                        default:
                            cmd_valid <= cmd_valid;
                    endcase
                end
            end
        end
    endgenerate
    
endmodule
