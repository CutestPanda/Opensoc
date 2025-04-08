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
本模块: sdram初始化命令生成器

描述:
等待一段时间 -> 对所有bank预充电 -> 设置模式寄存器 -> 刷新n次

协议:
AXIS MASTER

作者: 陈家耀
日期: 2025/03/01
********************************************************************/


module sdram_init_cmd_gen #(
    parameter real CLK_PERIOD = 7.0, // 时钟周期(以ns计)
	parameter real INIT_PAUSE = 250000.0, // 初始等待时间(以ns计)
    parameter integer BURST_LEN = -1, // 突发长度(-1 -> 全页; 1 | 2 | 4 | 8)
    parameter integer CAS_LATENCY = 2, // sdram读潜伏期时延(2 | 3)
	parameter integer AUTO_RFS_N = 2, // 执行自动刷新的次数
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 初始化命令接收完成(标志)
    output wire init_cmd_all_recv,

    // 命令AXIS
    output wire[23:0] m_axis_init_cmd_data, // {保留(3bit), BS(2bit), A15-0(16bit), 命令号(3bit)}
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
	// 复位后等待周期数
    localparam integer RST_WAIT_P = ceil(INIT_PAUSE / CLK_PERIOD);
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
        (CAS_LATENCY == 2) ? 3'b010:
                             3'b011,
        1'b0, // sequential
        // burst length
        (BURST_LEN == 1) ? 3'b000:
        (BURST_LEN == 2) ? 3'b001:
        (BURST_LEN == 4) ? 3'b010:
        (BURST_LEN == 8) ? 3'b011:
                           3'b111,
        CMD_LOGI_MR_SET};
    // 初始化命令条数
    localparam integer INIT_CMD_N = 6 + AUTO_RFS_N;
    
    /** 复位等待 **/
    reg[clogb2(RST_WAIT_P-1):0] rst_wait_cnt; // 复位等待计数器
    reg rst_stable; // 复位稳定(标志)
    
    // 复位等待计数器
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rst_wait_cnt <= 0;
        else if(~rst_stable)
            rst_wait_cnt <= # SIM_DELAY rst_wait_cnt + 1;
    end
    // 复位稳定(标志)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rst_stable <= 1'b0;
        else if(~rst_stable)
            rst_stable <= # SIM_DELAY rst_wait_cnt == (RST_WAIT_P-1);
    end
    
    /** 初始化命令序列 **/
    wire[15:0] next_init_cmd; // 下一初始化命令(组合逻辑)
    reg[clogb2(INIT_CMD_N):0] next_init_cmd_id; // 下一初始化命令编号
    reg[15:0] now_cmd; // 当前命令
    reg init_cmd_all_recv_reg; // 初始化命令接收完成(标志)
    reg cmd_valid; // 命令有效
    
    assign m_axis_init_cmd_data = {3'bxxx, now_cmd[15:14], 5'b00000, now_cmd[13:3], now_cmd[2:0]};
    assign m_axis_init_cmd_valid = cmd_valid;
    
    assign init_cmd_all_recv = init_cmd_all_recv_reg;
	
	assign next_init_cmd = 
		(next_init_cmd_id == 0) ? {2'bxx, 11'b1_xxxxx_xxxxx, CMD_LOGI_BANK_PRECHARGE}: // 预充电所有
		(next_init_cmd_id == 1) ? CMD_FOR_MR_SET: // 设置模式寄存器
		((next_init_cmd_id >= 6) & 
			(next_init_cmd_id < (6 + AUTO_RFS_N))) ? {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_AUTO_REFRESH}: // 自动刷新
			{2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_NOP}; // NOP
    
    // 下一初始化命令编号
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            next_init_cmd_id <= 1;
        else if(m_axis_init_cmd_valid & m_axis_init_cmd_ready)
            next_init_cmd_id <= # SIM_DELAY next_init_cmd_id + 1;
    end
    // 当前命令
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            now_cmd <= {2'bxx, 11'b1_xxxxx_xxxxx, CMD_LOGI_BANK_PRECHARGE}; // 预充电所有
        else if(m_axis_init_cmd_valid & m_axis_init_cmd_ready)
            now_cmd <= # SIM_DELAY next_init_cmd;
    end
    // 命令有效
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            cmd_valid <= 1'b0;
        else
            cmd_valid <= # SIM_DELAY 
				cmd_valid ? 
					(~((next_init_cmd_id == INIT_CMD_N) & m_axis_init_cmd_ready)):
					(rst_stable & (~init_cmd_all_recv_reg));
    end
    
    // 初始化命令接收完成(标志)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            init_cmd_all_recv_reg <= 1'b0;
        else if(~init_cmd_all_recv_reg)
            init_cmd_all_recv_reg <= # SIM_DELAY m_axis_init_cmd_valid & m_axis_init_cmd_ready & (next_init_cmd_id == INIT_CMD_N);
    end
    
endmodule
