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
本模块: APB-TIMER的寄存器接口

描述: 
寄存器->
    偏移量  |    含义                     |   读写特性    |        备注
    0x00    timer_width-1~0:预分频系数-1         RW
    0x04    timer_width-1~0:自动装载值-1         RW
    0x08    timer_width-1~0:定时器计数值         RW
    0x0C    0:是否启动定时器                      RW
            11~8:捕获/比较选择(4个通道)            RW
			15~12:比较输出使能(4个通道)            RW
			23~16:版本号                        R
    0x10    0:全局中断使能                       RW
            8:计数溢出中断使能                    RW
            12~9:输入捕获中断使能                 RW
    0x14    0:全局中断标志                       RWC
            8:计数溢出中断标志                    R
            12~9:输入捕获中断标志                 R
    0x18    timer_width-1~0:捕获/比较值(通道1)   RW       仅当捕获/比较通道数(channel_n)>=1时可用
    0x1C    7~0:输入滤波阈值                     W        仅当捕获/比较通道数(channel_n)>=1时可用
            9~8:边沿检测类型                     W
			11~10:比较输出模式                   W
    0x20    timer_width-1~0:捕获/比较值(通道2)   RW       仅当捕获/比较通道数(channel_n)>=2时可用
    0x24    7~0:输入滤波阈值                     W        仅当捕获/比较通道数(channel_n)>=2时可用
            9~8:边沿检测类型                     W
			11~10:比较输出模式                   W
    0x28    timer_width-1~0:捕获/比较值(通道3)   RW       仅当捕获/比较通道数(channel_n)>=3时可用
    0x2C    7~0:输入滤波阈值                     W        仅当捕获/比较通道数(channel_n)>=3时可用
            9~8:边沿检测类型                     W
			11~10:比较输出模式                   W
    0x30    timer_width-1~0:捕获/比较值(通道4)   RW       仅当捕获/比较通道数(channel_n)>=4时可用
    0x34    7~0:输入滤波阈值                     W        仅当捕获/比较通道数(channel_n)>=4时可用
            9~8:边沿检测类型                     W
			11~10:比较输出模式                   W

注意：
无

协议:
APB SLAVE

作者: 陈家耀
日期: 2024/06/09
********************************************************************/


module regs_if_for_timer #(
    parameter integer timer_width = 16, // 定时器位宽(16 | 32)
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire resetn,
    
    // APB从机接口
    input wire[31:0] paddr,
    input wire psel,
    input wire penable,
    input wire pwrite,
    input wire[31:0] pwdata,
    output wire pready_out, // const -> 1'b1
    output wire[31:0] prdata_out,
    output wire pslverr_out, // const -> 1'b0
    
    // 预分频系数 - 1
    output wire[timer_width-1:0] prescale,
    // 自动装载值 - 1
    output wire[timer_width-1:0] autoload,
    
    // 定时器计数值
    output wire timer_cnt_to_set,
    output wire[timer_width-1:0] timer_cnt_set_v,
    input wire[timer_width-1:0] timer_cnt_now_v,
    
    // 是否启动定时器
    output wire timer_started,
    // 捕获/比较选择(4个通道)
    // 1'b0 -> 捕获, 1'b1 -> 比较
    output wire[3:0] cap_cmp_sel,
    
	// 比较输出使能(通道1)
	output wire timer_chn1_cmp_oen,
    // 捕获/比较值(通道1)
    output wire[timer_width-1:0] timer_chn1_cmp,
    input wire[timer_width-1:0] timer_chn1_cap_cmp_i,
    // 输入滤波阈值(通道1)
    output wire[7:0] timer_chn1_cap_filter_th,
    // 边沿检测类型(通道1)
    // 2'b00 -> 上升沿, 2'b01 -> 下降沿, 2'b10 -> 上升/下降沿, 2'b11 -> 保留
    output wire[1:0] timer_chn1_cap_edge,
	// 比较输出模式(通道1)
	output wire[1:0] timer_chn1_cmp_out_mode,
    
	// 比较输出使能(通道2)
	output wire timer_chn2_cmp_oen,
    // 捕获/比较值(通道2)
    output wire[timer_width-1:0] timer_chn2_cmp,
    input wire[timer_width-1:0] timer_chn2_cap_cmp_i,
    // 输入滤波阈值(通道2)
    output wire[7:0] timer_chn2_cap_filter_th,
    // 边沿检测类型(通道2)
    // 2'b00 -> 上升沿, 2'b01 -> 下降沿, 2'b1x -> 上升/下降沿
    output wire[1:0] timer_chn2_cap_edge,
	// 比较输出模式(通道2)
	output wire[1:0] timer_chn2_cmp_out_mode,
    
	// 比较输出使能(通道3)
	output wire timer_chn3_cmp_oen,
    // 捕获/比较值(通道3)
    output wire[timer_width-1:0] timer_chn3_cmp,
    input wire[timer_width-1:0] timer_chn3_cap_cmp_i,
    // 输入滤波阈值(通道3)
    output wire[7:0] timer_chn3_cap_filter_th,
    // 边沿检测类型(通道3)
    // 2'b00 -> 上升沿, 2'b01 -> 下降沿, 2'b1x -> 上升/下降沿
    output wire[1:0] timer_chn3_cap_edge,
	// 比较输出模式(通道3)
	output wire[1:0] timer_chn3_cmp_out_mode,
    
	// 比较输出使能(通道4)
	output wire timer_chn4_cmp_oen,
    // 捕获/比较值(通道4)
    output wire[timer_width-1:0] timer_chn4_cmp,
    input wire[timer_width-1:0] timer_chn4_cap_cmp_i,
    // 输入滤波阈值(通道4)
    output wire[7:0] timer_chn4_cap_filter_th,
    // 边沿检测类型(通道4)
    // 2'b00 -> 上升沿, 2'b01 -> 下降沿, 2'b1x -> 上升/下降沿
    output wire[1:0] timer_chn4_cap_edge,
	// 比较输出模式(通道4)
	output wire[1:0] timer_chn4_cmp_out_mode,
    
    // 中断请求
    input wire timer_expired_itr_req, // 计数溢出中断请求
    input wire[3:0] timer_cap_itr_req, // 输入捕获中断请求
    
    // 中断信号
    output wire itr
);

    /** APB写寄存器 **/
    // 0x00
    reg[31:0] prescale_regs; // 预分频系数-1
    // 0x04
    reg[31:0] autoload_regs; // 自动装载值 - 1
    // 0x08
    reg timer_cnt_to_set_reg; // 定时器计数值设置指示
    reg[31:0] timer_cnt_set_v_regs; // 定时器计数值设置量
    // 0x0C
    reg timer_started_reg; // 是否启动定时器
    reg[3:0] cap_cmp_sel_regs; // 捕获/比较选择
	reg[3:0] cmp_oen_regs; // 比较输出使能
    // 0x10
    reg global_itr_en; // 全局中断使能
    reg timer_expired_itr_en; // 计数溢出中断使能
    reg[3:0] timer_cap_itr_en; // 输入捕获中断使能
    // 0x14
    wire[4:0] org_itr_req_vec; // 原始中断请求向量
    wire org_global_itr_req; // 原始总中断请求
    reg global_itr_flag; // 全局中断标志
    reg timer_expired_itr_flag; // 计数溢出中断标志
    reg[3:0] timer_cap_itr_flag; // 输入捕获中断标志
    // 0x18
    reg[31:0] timer_chn1_cmp_regs; // 定时器比较值设置量(通道1)
    // 0x1C
    reg[7:0] timer_chn1_cap_filter_th_regs; // 输入滤波阈值(通道1)
    reg[1:0] timer_chn1_cap_edge_regs; // 边沿检测类型(通道1)
	reg[1:0] timer_chn1_cmp_out_mode_regs; // 比较输出模式(通道1)
    // 0x20
    reg[31:0] timer_chn2_cmp_regs; // 定时器比较值设置量(通道2)
    // 0x24
    reg[7:0] timer_chn2_cap_filter_th_regs; // 输入滤波阈值(通道2)
    reg[1:0] timer_chn2_cap_edge_regs; // 边沿检测类型(通道2)
	reg[1:0] timer_chn2_cmp_out_mode_regs; // 比较输出模式(通道2)
    // 0x28
    reg[31:0] timer_chn3_cmp_regs; // 定时器比较值设置量(通道3)
    // 0x2C
    reg[7:0] timer_chn3_cap_filter_th_regs; // 输入滤波阈值(通道3)
    reg[1:0] timer_chn3_cap_edge_regs; // 边沿检测类型(通道3)
	reg[1:0] timer_chn3_cmp_out_mode_regs; // 比较输出模式(通道3)
    // 0x30
    reg[31:0] timer_chn4_cmp_regs; // 定时器比较值设置量(通道4)
    // 0x34
    reg[7:0] timer_chn4_cap_filter_th_regs; // 输入滤波阈值(通道4)
    reg[1:0] timer_chn4_cap_edge_regs; // 边沿检测类型(通道4)
	reg[1:0] timer_chn4_cmp_out_mode_regs; // 比较输出模式(通道4)
    
    assign prescale = prescale_regs[timer_width-1:0];
    assign autoload = autoload_regs[timer_width-1:0];
    assign timer_cnt_to_set = timer_cnt_to_set_reg;
    assign timer_cnt_set_v = timer_cnt_set_v_regs[timer_width-1:0];
    assign timer_started = timer_started_reg;
    assign cap_cmp_sel = cap_cmp_sel_regs;
	assign timer_chn1_cmp_oen = cmp_oen_regs[0];
    assign timer_chn1_cmp = timer_chn1_cmp_regs[timer_width-1:0];
    assign {timer_chn1_cmp_out_mode, timer_chn1_cap_edge, timer_chn1_cap_filter_th} = 
		{timer_chn1_cmp_out_mode_regs, timer_chn1_cap_edge_regs, timer_chn1_cap_filter_th_regs};
	assign timer_chn2_cmp_oen = cmp_oen_regs[1];
    assign timer_chn2_cmp = timer_chn2_cmp_regs[timer_width-1:0];
    assign {timer_chn2_cmp_out_mode, timer_chn2_cap_edge, timer_chn2_cap_filter_th} = 
		{timer_chn2_cmp_out_mode_regs, timer_chn2_cap_edge_regs, timer_chn2_cap_filter_th_regs};
	assign timer_chn3_cmp_oen = cmp_oen_regs[2];
    assign timer_chn3_cmp = timer_chn3_cmp_regs[timer_width-1:0];
    assign {timer_chn3_cmp_out_mode, timer_chn3_cap_edge, timer_chn3_cap_filter_th} = 
		{timer_chn3_cmp_out_mode_regs, timer_chn3_cap_edge_regs, timer_chn3_cap_filter_th_regs};
	assign timer_chn4_cmp_oen = cmp_oen_regs[3];
    assign timer_chn4_cmp = timer_chn4_cmp_regs[timer_width-1:0];
    assign {timer_chn4_cmp_out_mode, timer_chn4_cap_edge, timer_chn4_cap_filter_th} = 
		{timer_chn4_cmp_out_mode_regs, timer_chn4_cap_edge_regs, timer_chn4_cap_filter_th_regs};
    
    // 预分频系数-1
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd0))
            prescale_regs <= # simulation_delay pwdata;
    end
    
    // 自动装载值 - 1
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd1))
            autoload_regs <= # simulation_delay pwdata;
    end
    
    // 定时器计数值设置指示
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            timer_cnt_to_set_reg <= 1'b0;
        else
            timer_cnt_to_set_reg <= # simulation_delay psel & penable & pwrite & (paddr[5:2] == 4'd2);
    end
    // 定时器计数值设置量
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd2))
            timer_cnt_set_v_regs <= # simulation_delay pwdata;
    end
    
    // 是否启动定时器
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            timer_started_reg <= 1'b0;
        else if(psel & penable & pwrite & (paddr[5:2] == 4'd3))
            timer_started_reg <= # simulation_delay pwdata[0];
    end
    // 捕获/比较选择
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd3))
            cap_cmp_sel_regs <= # simulation_delay pwdata[11:8];
    end
	// 比较输出使能
	always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
			cmp_oen_regs <= 4'b0000;
		else if(psel & penable & pwrite & (paddr[5:2] == 4'd3))
			cmp_oen_regs <= # simulation_delay pwdata[15:12];
	end
    
    // 全局中断使能
    // 计数溢出中断使能
    // 输入捕获中断使能
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            {timer_cap_itr_en, timer_expired_itr_en, global_itr_en} <= 6'd0;
        else if(psel & penable & pwrite & (paddr[5:2] == 4'd4))
            {timer_cap_itr_en, timer_expired_itr_en, global_itr_en} <= # simulation_delay {pwdata[12:8], pwdata[0]};
    end
    
    // 全局中断标志
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            global_itr_flag <= 1'b0;
        else if(psel & penable & pwrite & (paddr[5:2] == 4'd5))
            global_itr_flag <= # simulation_delay 1'b0;
        else if(~global_itr_flag)
            global_itr_flag <= # simulation_delay org_global_itr_req;
    end
    // 计数溢出中断标志
    // 输入捕获中断标志
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            {timer_cap_itr_flag, timer_expired_itr_flag} <= 5'd0;
        else if(org_global_itr_req)
            {timer_cap_itr_flag, timer_expired_itr_flag} <= # simulation_delay org_itr_req_vec;
    end
    
    // 定时器比较值设置量
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd6))
            timer_chn1_cmp_regs <= # simulation_delay pwdata;
    end
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd8))
            timer_chn2_cmp_regs <= # simulation_delay pwdata;
    end
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd10))
            timer_chn3_cmp_regs <= # simulation_delay pwdata;
    end
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd12))
            timer_chn4_cmp_regs <= # simulation_delay pwdata;
    end
    
    // 输入滤波阈值
    // 边沿检测类型
	// 比较输出模式
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd7))
            {timer_chn1_cmp_out_mode_regs, timer_chn1_cap_edge_regs, timer_chn1_cap_filter_th_regs} <= # simulation_delay 
				pwdata[11:0];
    end
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd9))
            {timer_chn2_cmp_out_mode_regs, timer_chn2_cap_edge_regs, timer_chn2_cap_filter_th_regs} <= # simulation_delay 
				pwdata[11:0];
    end
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd11))
            {timer_chn3_cmp_out_mode_regs, timer_chn3_cap_edge_regs, timer_chn3_cap_filter_th_regs} <= # simulation_delay 
				pwdata[11:0];
    end
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd13))
            {timer_chn4_cmp_out_mode_regs, timer_chn4_cap_edge_regs, timer_chn4_cap_filter_th_regs} <= # simulation_delay 
				pwdata[11:0];
    end
    
    /** 中断处理 **/
    assign org_itr_req_vec = {timer_cap_itr_req, timer_expired_itr_req} & {timer_cap_itr_en, timer_expired_itr_en};
    assign org_global_itr_req = (|org_itr_req_vec) & global_itr_en & (~global_itr_flag);
    
    /** APB读寄存器 **/
    reg[31:0] prdata_out_regs;
    
    assign pready_out = 1'b1;
    assign prdata_out = prdata_out_regs;
    assign pslverr_out = 1'b0;
    
    // APB读数据
    always @(posedge clk)
    begin
        if(psel & (~pwrite))
        begin
            case(paddr[5:2])
				4'd0: prdata_out_regs <= # simulation_delay 
					prescale_regs[timer_width-1:0] | 32'h0000_0000;
				4'd1: prdata_out_regs <= # simulation_delay 
					autoload_regs[timer_width-1:0] | 32'h0000_0000;
                4'd2: prdata_out_regs <= # simulation_delay 
					timer_cnt_now_v | 32'h0000_0000;
				4'd3: prdata_out_regs <= # simulation_delay 
					{8'd0, 8'd1, cmp_oen_regs, cap_cmp_sel_regs, 7'd0, timer_started_reg};
				4'd4: prdata_out_regs <= # simulation_delay 
					{16'd0, 3'd0, timer_cap_itr_en, timer_expired_itr_en, 7'd0, global_itr_en};
                4'd5: prdata_out_regs <= # simulation_delay 
					{16'd0, 3'd0, timer_cap_itr_flag, timer_expired_itr_flag, 7'd0, global_itr_flag};
                4'd6: prdata_out_regs <= # simulation_delay 
					timer_chn1_cap_cmp_i | 32'h0000_0000;
                4'd8: prdata_out_regs <= # simulation_delay 
					timer_chn2_cap_cmp_i | 32'h0000_0000;
                4'd10: prdata_out_regs <= # simulation_delay 
					timer_chn3_cap_cmp_i | 32'h0000_0000;
                4'd12: prdata_out_regs <= # simulation_delay 
					timer_chn4_cap_cmp_i | 32'h0000_0000;
                default: prdata_out_regs <= # simulation_delay 
					32'h0000_0000;
            endcase
        end
    end
    
    // 中断发生器
    itr_generator #(
        .pulse_w(10),
        .simulation_delay(simulation_delay)
    )itr_generator_u(
        .clk(clk),
        .rst_n(resetn),
        
        .itr_org(org_global_itr_req),
        
        .itr(itr)
    );

endmodule
