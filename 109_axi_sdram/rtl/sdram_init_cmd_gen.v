`timescale 1ns / 1ps
/********************************************************************
本模块: sdram初始化命令生成器

描述:
等待250us -> 对所有bank预充电 -> 设置模式寄存器 -> 刷新2次

协议:
AXIS MASTER

作者: 陈家耀
日期: 2024/04/17
********************************************************************/


module sdram_init_cmd_gen #(
    parameter real clk_period = 7.0, // 时钟周期
    parameter integer burst_len = -1, // 突发长度(-1 -> 全页; 1 | 2 | 4 | 8)
    parameter integer cas_latency = 2 // sdram读潜伏期时延(2 | 3)
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 初始化命令接收完成(标志)
    output wire init_cmd_all_recv,

    // 命令AXIS
    output wire[15:0] m_axis_init_cmd_data, // {BS(2bit), A10-0(11bit), 命令号(3bit)}
    output wire m_axis_init_cmd_valid,
    input wire m_axis_init_cmd_ready
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
    localparam integer RST_WAIT_P = $ceil(250000.0 / clk_period); // 复位后等待周期数
    // 初始化状态
    localparam RST_WAITING = 3'b000; // 状态:复位等待
    localparam INIT_CMD_PRECHARGE = 3'b001; // 状态:发送"预充电"命令
    localparam INIT_CMD_MR_SET = 3'b010; // 状态:发送"设置模式寄存器"命令
    localparam INIT_CMD_NOP = 3'b011; // 状态:发送"NOP"命令
    localparam INIT_CMD_REFRESH_0 = 3'b100; // 状态:发送第1次"自动刷新"命令
    localparam INIT_CMD_REFRESH_1 = 3'b101; // 状态:发送第2次"自动刷新"命令
    localparam INIT_OKAY = 3'b110; // 状态:初始化完成
    // 命令的逻辑编码
    localparam CMD_LOGI_BANK_PRECHARGE = 3'b001; // 命令:预充电bank
    localparam CMD_LOGI_MR_SET = 3'b100; // 命令:设置模式寄存器
    localparam CMD_LOGI_AUTO_REFRESH = 3'b101; // 命令:自动刷新
    localparam CMD_LOGI_NOP = 3'b111; // 命令:空操作
    // 设置模式寄存器时的命令
    localparam CMD_FOR_MR_SET = {
        3'b000, // reserved
        1'b0, // burst
        2'b00, // normal
        // CAS# LA
        (cas_latency == 2) ? 3'b010:
                             3'b011,
        1'b0, // sequential
        // burst length
        (burst_len == 1) ? 3'b000:
        (burst_len == 2) ? 3'b001:
        (burst_len == 4) ? 3'b010:
        (burst_len == 8) ? 3'b011:
                           3'b111,
        CMD_LOGI_MR_SET};
    // 初始化命令的总数
    localparam integer init_cmd_n = 8;
    
    /** 复位等待 **/
    reg[clogb2(RST_WAIT_P-1):0] rst_wait_cnt; // 复位等待计数器
    reg rst_stable; // 复位稳定(标志)
    
    // 复位等待计数器
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rst_wait_cnt <= 0;
        else if(~rst_stable)
            rst_wait_cnt <= rst_wait_cnt + 1;
    end
    // 复位稳定(标志)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rst_stable <= 1'b0;
        else if(~rst_stable)
            rst_stable <= rst_wait_cnt == (RST_WAIT_P-1);
    end
    
    /** 初始化命令序列 **/
    reg[15:0] next_init_cmd; // 下一初始化命令(组合逻辑)
    reg[clogb2(init_cmd_n):0] next_init_cmd_id; // 下一初始化命令编号
    reg[15:0] now_cmd; // 当前命令
    reg init_cmd_all_recv_reg; // 初始化命令接收完成(标志)
    reg cmd_valid; // 命令有效
    
    assign m_axis_init_cmd_data = now_cmd;
    assign m_axis_init_cmd_valid = cmd_valid;
    
    assign init_cmd_all_recv = init_cmd_all_recv_reg;
    
    // 下一初始化命令(组合逻辑)
    always @(*)
    begin
        case(next_init_cmd_id)
            0: next_init_cmd = {2'bxx, 11'b1_xxxxx_xxxxx, CMD_LOGI_BANK_PRECHARGE}; // 预充电所有
            1: next_init_cmd = CMD_FOR_MR_SET; // 设置模式寄存器
            2: next_init_cmd = {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_NOP}; // NOP
            3: next_init_cmd = {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_NOP}; // NOP
            4: next_init_cmd = {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_NOP}; // NOP
            5: next_init_cmd = {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_NOP}; // NOP
            6: next_init_cmd = {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_AUTO_REFRESH}; // 自动刷新
            7: next_init_cmd = {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_AUTO_REFRESH}; // 自动刷新
            default: next_init_cmd = {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_NOP}; // NOP
        endcase
    end
    
    // 下一初始化命令编号
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            next_init_cmd_id <= 1;
        else if(m_axis_init_cmd_valid & m_axis_init_cmd_ready)
            next_init_cmd_id <= next_init_cmd_id + 1;
    end
    // 当前命令
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            now_cmd <= {2'bxx, 11'b1_xxxxx_xxxxx, CMD_LOGI_BANK_PRECHARGE};
        else if(m_axis_init_cmd_valid & m_axis_init_cmd_ready)
            now_cmd <= next_init_cmd;
    end
    // 命令有效
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            cmd_valid <= 1'b0;
        else
            cmd_valid <= cmd_valid ? (~((next_init_cmd_id == init_cmd_n) & m_axis_init_cmd_ready)):(rst_stable & (~init_cmd_all_recv_reg));
    end
    
    // 初始化命令接收完成(标志)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            init_cmd_all_recv_reg <= 1'b0;
        else if(~init_cmd_all_recv_reg)
            init_cmd_all_recv_reg <= m_axis_init_cmd_valid & m_axis_init_cmd_ready & (next_init_cmd_id == init_cmd_n);
    end
    
endmodule
