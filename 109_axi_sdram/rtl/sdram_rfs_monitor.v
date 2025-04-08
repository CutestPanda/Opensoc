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
本模块: sdram刷新监测器

描述:
给出自动刷新定时开始指示信号
检查是否在规定的时间间隔内刷新sdram

注意：
无

协议:
无

作者: 陈家耀
日期: 2025/03/01
********************************************************************/


module sdram_rfs_monitor #(
    parameter real CLK_PERIOD = 7.0, // 时钟周期(以ns计)
    parameter real MAX_RFS_ITV = 64.0 * 1000.0 * 1000.0 / 4096.0, // 最大刷新间隔(以ns计)
    parameter EN_EXPT_TIP = "false", // 是否使能异常指示
	parameter integer INIT_AUTO_RFS_N = 2, // 初始化时执行自动刷新的次数
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 自动刷新定时开始(指示)
    output wire start_rfs_timing,
    
    // sdram命令线监测
    input wire sdram_cs_n,
    input wire sdram_ras_n,
    input wire sdram_cas_n,
    input wire sdram_we_n,
    
    // 异常指示
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
	
	// 向下取整
	function integer floor(input real f);
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
		
		floor = ((frac == 0.0) || (f >= 0)) ? dec:(dec - 1);
    end
    endfunction
    
    /** 常量 **/
    localparam integer MAX_RFS_ITV_P = floor(MAX_RFS_ITV / CLK_PERIOD); // 最大刷新间隔周期数
    // 命令的物理编码(CS_N, RAS_N, CAS_N, WE_N)
    localparam CMD_PHY_AUTO_REFRESH = 4'b0001; // 命令:自动刷新
    
    /** 自动刷新定时开始(指示) **/
    reg[INIT_AUTO_RFS_N:0] init_rfs_cnt; // 初始化时刷新计数器
    reg start_rfs_timing_r; // 自动刷新定时开始(指示)
    reg monitor_en; // 监测使能
    
    assign start_rfs_timing = start_rfs_timing_r;
    
    // 初始化时刷新计数器
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            init_rfs_cnt <= {{INIT_AUTO_RFS_N{1'b0}}, 1'b1};
        else if(({sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} == CMD_PHY_AUTO_REFRESH) & (~init_rfs_cnt[INIT_AUTO_RFS_N]))
            init_rfs_cnt <= # SIM_DELAY {init_rfs_cnt[INIT_AUTO_RFS_N-1:0], init_rfs_cnt[INIT_AUTO_RFS_N]};
    end
    // 自动刷新定时开始(指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            start_rfs_timing_r <= 1'b0;
        else
            start_rfs_timing_r <= # SIM_DELAY 
				({sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} == CMD_PHY_AUTO_REFRESH) & 
				init_rfs_cnt[INIT_AUTO_RFS_N-1];
    end
    
    // 监测使能
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            monitor_en <= 1'b0;
        else if(~monitor_en)
            monitor_en <= # SIM_DELAY start_rfs_timing;
    end
    
    /** 刷新超时监测 **/
    reg[clogb2(MAX_RFS_ITV_P-1):0] rfs_timeout_cnt; // 刷新超时计数器
    reg rfs_timeout_cnt_suspend; // 刷新超时计数器挂起
    reg rfs_timeout_r; // 刷新超时(指示)
    
    assign rfs_timeout = (EN_EXPT_TIP == "true") & rfs_timeout_r;
    
    // 刷新超时计数器
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rfs_timeout_cnt <= 0;
        else if({sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} == CMD_PHY_AUTO_REFRESH)
            rfs_timeout_cnt <= # SIM_DELAY 0;
        else if(monitor_en & (~rfs_timeout_cnt_suspend))
            rfs_timeout_cnt <= # SIM_DELAY rfs_timeout_cnt + 1;
    end
    // 刷新超时计数器挂起
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rfs_timeout_cnt_suspend <= 1'b0;
        else if({sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} == CMD_PHY_AUTO_REFRESH)
            rfs_timeout_cnt_suspend <= # SIM_DELAY 1'b0;
        else if(~rfs_timeout_cnt_suspend)
            rfs_timeout_cnt_suspend <= # SIM_DELAY rfs_timeout_cnt == MAX_RFS_ITV_P - 1;
    end
    // 刷新超时(指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rfs_timeout_r <= 1'b0;
        else
            rfs_timeout_r <= # SIM_DELAY rfs_timeout_cnt == MAX_RFS_ITV_P - 1;
    end
	
endmodule
