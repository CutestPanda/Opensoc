`timescale 1ns / 1ps
/********************************************************************
本模块: sdram自检

描述:
每次突发的数据总是从1开始递增
当突发长度为全页时, 实际突发长度总是sdram列数(SDRAM_COL_N)

注意：
列地址固定为0
数据位宽必须>=clogb2(SDRAM_COL_N)

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/03/03
********************************************************************/


module sdram_selftest #(
    parameter integer BURST_LEN = -1, // 突发长度(-1 -> 全页; 1 | 2 | 4 | 8)
    parameter integer DATA_WIDTH = 32, // 数据位宽
	parameter integer SDRAM_COL_N = 256, // sdram列数(64 | 128 | 256 | 512 | 1024)
	parameter integer SDRAM_ROW_N = 8192, // sdram行数(1024 | 2048 | 4096 | 8192 | 16384)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 流程控制
    input wire self_test_start,
    output wire self_test_idle,
    output wire self_test_done,
    
    // 自检结果
    // {是否成功(1bit), 错误bank号(2bit), 错误行号(16bit)}
    output wire[18:0] self_test_res,
    output wire self_test_res_valid,
    
    // 写数据AXIS
    output wire[DATA_WIDTH-1:0] m_axis_wt_data,
    output wire[DATA_WIDTH/8-1:0] m_axis_wt_keep, // const -> {(DATA_WIDTH/8){1'b1}}
    output wire m_axis_wt_last,
    output wire m_axis_wt_valid,
    input wire m_axis_wt_ready,
    // 读数据AXIS
    input wire[DATA_WIDTH-1:0] s_axis_rd_data,
    input wire s_axis_rd_last,
    input wire s_axis_rd_valid,
    output wire s_axis_rd_ready,
    
    // 用户命令AXIS
    output wire[39:0] m_axis_usr_cmd_data, // {保留(3bit), ba(2bit), 行地址(16bit), A15-0(16bit), 命令号(3bit)}
    output wire[16:0] m_axis_usr_cmd_user, // {是否自动添加"停止突发"命令(1bit), 突发长度 - 1(16bit)}(仅对全页突发有效)
    output wire m_axis_usr_cmd_valid,
    input wire m_axis_usr_cmd_ready
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
    // 命令的逻辑编码
    localparam CMD_LOGI_WT_DATA = 3'b010; // 命令:写数据
    localparam CMD_LOGI_RD_DATA = 3'b011; // 命令:读数据
    localparam CMD_LOGI_BANK_PRECHARGE = 3'b001; // 命令:预充电bank
    
    /** 用户命令AXIS **/
    reg[36:0] now_cmd; // 当前命令
    reg now_cmd_valid; // 当前命令有效
    
    assign m_axis_usr_cmd_data = {3'dx, now_cmd};
    assign m_axis_usr_cmd_user = {
        (BURST_LEN == -1) ? 1'b1:1'bx, // 是否自动添加"停止突发"命令(1bit)
        (BURST_LEN == -1) ? (SDRAM_COL_N[15:0] - 16'd1):16'dx // 突发长度 - 1(16bit)
    };
    assign m_axis_usr_cmd_valid = now_cmd_valid;
    
    // 当前命令
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            now_cmd <= {2'b00, 16'd0, 16'd0, CMD_LOGI_WT_DATA}; // 写bank0行0
        else if(m_axis_usr_cmd_valid & m_axis_usr_cmd_ready)
        begin
			{now_cmd[36:35], now_cmd[19+clogb2(SDRAM_ROW_N-1):19]} <= # SIM_DELAY 
				{now_cmd[36:35], now_cmd[19+clogb2(SDRAM_ROW_N-1):19]} + 1;
            
            now_cmd[18:3] <= # SIM_DELAY 16'd0; // always 16'd0
            
            now_cmd[2:1] <= # SIM_DELAY 2'b01; // always 2'b01
            now_cmd[0] <= # SIM_DELAY (&{now_cmd[36:35], now_cmd[19+clogb2(SDRAM_ROW_N-1):19]}) ? (~now_cmd[0]):now_cmd[0];
        end
    end
    // 当前命令有效
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            now_cmd_valid <= 1'b0;
        else
            now_cmd_valid <= # SIM_DELAY now_cmd_valid ? 
				(~(m_axis_usr_cmd_ready & (&{now_cmd[36:35], now_cmd[19+clogb2(SDRAM_ROW_N-1):19]}) & now_cmd[0])):
				(self_test_idle & self_test_start);
    end
    
    /** 写数据AXIS **/
    reg[clogb2(SDRAM_ROW_N-1)+2:0] wt_burst_cnt; // 写突发个数(计数器)
    reg[DATA_WIDTH-1:0] wt_data; // 写数据
    reg wt_data_valid; // 写数据有效
    
    assign m_axis_wt_data = wt_data;
    assign m_axis_wt_keep = {(DATA_WIDTH/8){1'b1}};
    assign m_axis_wt_last = (BURST_LEN == -1) ? (wt_data == SDRAM_COL_N):
                             (BURST_LEN == 1) ? 1'b1:
                                                (wt_data == BURST_LEN);
    assign m_axis_wt_valid = wt_data_valid;
    
    // 写突发个数(计数器)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_burst_cnt <= 0;
        else if(m_axis_wt_valid & m_axis_wt_ready & m_axis_wt_last)
            wt_burst_cnt <= # SIM_DELAY wt_burst_cnt + 1;
    end
    
    // 写数据
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_data <= 1;
        else if(m_axis_wt_valid & m_axis_wt_ready)
            wt_data <= # SIM_DELAY m_axis_wt_last ? 1:(wt_data + 1);
    end
    // 写数据有效
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_data_valid <= 1'b0;
        else
            wt_data_valid <= # SIM_DELAY wt_data_valid ? 
				(~(m_axis_wt_ready & m_axis_wt_last & (&wt_burst_cnt))):
				(self_test_idle & self_test_start);
    end
    
    /** 读数据AXIS **/
    reg[clogb2(SDRAM_ROW_N-1)+2:0] rd_burst_cnt; // 读突发个数(计数器)
    reg rd_ready; // 读就绪
    
    assign s_axis_rd_ready = rd_ready;
    
    // 读突发个数(计数器)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_burst_cnt <= 0;
        else if(s_axis_rd_valid & s_axis_rd_ready & s_axis_rd_last)
            rd_burst_cnt <= # SIM_DELAY rd_burst_cnt + 1;
    end
    
    // 读就绪
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_ready <= 1'b0;
        else
            rd_ready <= # SIM_DELAY 
				rd_ready ? 
					(~(s_axis_rd_valid & s_axis_rd_last & (&rd_burst_cnt))):
					(self_test_idle & self_test_start);
    end
    
    /** 读数据检查 **/
    reg[clogb2(SDRAM_COL_N):0] rd_data_cnt; // 读数据计数器
    reg now_rd_data_mismatch; // 当前读突发数据不匹配(标志)
    wire now_rd_burst_check_res; // 当前读突发检查结果
    reg[18:0] now_self_test_res; // 当前的自检结果({是否成功(1bit), 错误bank号(2bit), 错误行号(16bit)})
    
    assign self_test_res = now_self_test_res;
    assign self_test_res_valid = self_test_done;
    
    assign now_rd_burst_check_res = now_rd_data_mismatch | (s_axis_rd_data != rd_data_cnt) | 
        (rd_data_cnt != ((BURST_LEN == -1) ? SDRAM_COL_N:BURST_LEN));
    
    // 读数据计数器
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_data_cnt <= 1;
        else if(s_axis_rd_valid & s_axis_rd_ready)
            rd_data_cnt <= # SIM_DELAY s_axis_rd_last ? 1:(rd_data_cnt + 1);
    end
    
    // 当前读突发数据不匹配(标志)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            now_rd_data_mismatch <= 1'b0;
        else if(s_axis_rd_valid & s_axis_rd_ready)
            now_rd_data_mismatch <= # SIM_DELAY s_axis_rd_last ? 1'b0:(now_rd_data_mismatch | (s_axis_rd_data != rd_data_cnt));
    end
    
    // 当前的自检结果({是否成功(1bit), 错误bank号(2bit), 错误行号(16bit)})
    always @(posedge clk)
    begin
        if(self_test_idle & self_test_start)
            now_self_test_res <= # SIM_DELAY {1'b1, 2'bxx, 16'dx};
        else if(s_axis_rd_valid & s_axis_rd_ready & s_axis_rd_last & now_self_test_res[18])
            now_self_test_res <= # SIM_DELAY {
				now_self_test_res[18] & (~now_rd_burst_check_res), 
				rd_burst_cnt[clogb2(SDRAM_ROW_N-1)+2:clogb2(SDRAM_ROW_N-1)+1], 
				16'h0000 | rd_burst_cnt[clogb2(SDRAM_ROW_N-1):0]
			};
    end
    
    /** 流程控制 **/
    reg self_test_idle_reg;
    reg self_test_done_reg;
    
    assign self_test_idle = self_test_idle_reg;
    assign self_test_done = self_test_done_reg;
    
    // 自检单元空闲标志
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            self_test_idle_reg <= 1'b1;
        else
            self_test_idle_reg <= # SIM_DELAY self_test_idle_reg ? (~self_test_start):self_test_done;
    end
    // 自检单元完成指示
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            self_test_done_reg <= 1'b0;
        else
            self_test_done_reg <= # SIM_DELAY s_axis_rd_valid & s_axis_rd_ready & s_axis_rd_last & ((&rd_burst_cnt) | now_rd_burst_check_res);
    end

endmodule
