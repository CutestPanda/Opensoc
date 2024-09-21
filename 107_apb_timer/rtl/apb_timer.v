`timescale 1ns / 1ps
/********************************************************************
本模块: APB-TIMER

描述: 
带APB从接口的通用定时器
8~32位定时器
支持多达四通道输入捕获/输出比较
输入捕获支持输入滤波，可捕获上升沿/下降沿/双沿
可启用计数溢出中断和输入捕获中断

寄存器->
    偏移量  |    含义                     |   读写特性    |        备注
    0x00    timer_width-1~0:预分频系数-1         W
    0x04    timer_width-1~0:自动装载值-1         W
    0x08    timer_width-1~0:定时器计数值         RW
    0x0C    0:是否启动定时器                     W
            11~8:捕获/比较选择(4个通道)          W
    0x10    0:全局中断使能                       W
            8:计数溢出中断使能                   W
            12~9:输入捕获中断使能                W
    0x14    0:全局中断标志                       RWC
            8:计数溢出中断标志                   R
            12~9:输入捕获中断标志                R
    0x18    timer_width-1~0:捕获/比较值(通道1)   RW       仅使能捕获/比较通道1时可用
    0x1C    7~0:输入滤波阈值                     W        仅使能捕获/比较通道1时可用
            9~8:边沿检测类型                     W
    0x20    timer_width-1~0:捕获/比较值(通道2)   RW       仅使能捕获/比较通道2时可用
    0x24    7~0:输入滤波阈值                     W        仅使能捕获/比较通道2时可用
            9~8:边沿检测类型                     W
    0x28    timer_width-1~0:捕获/比较值(通道3)   RW       仅使能捕获/比较通道3时可用
    0x2C    7~0:输入滤波阈值                     W        仅使能捕获/比较通道3时可用
            9~8:边沿检测类型                     W
    0x30    timer_width-1~0:捕获/比较值(通道4)   RW       仅使能捕获/比较通道4时可用
    0x34    7~0:输入滤波阈值                     W        仅使能捕获/比较通道4时可用
            9~8:边沿检测类型                     W

注意：
无

协议:
APB SLAVE

作者: 陈家耀
日期: 2024/06/09
********************************************************************/


module apb_timer #(
    parameter integer timer_width = 16, // 定时器位宽(8~32)
    parameter integer channel_n = 1, // 捕获/比较通道数(0~4)
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
    
    // 捕获/比较
    input wire[channel_n-1:0] cap_in, // 捕获输入
    output wire[channel_n-1:0] cmp_out, // 比较输出
    
    // 中断信号
    output wire itr
);
    
    /** 寄存器接口 **/
    wire[timer_width-1:0] prescale; // 预分频系数 - 1
    wire[timer_width-1:0] autoload; // 自动装载值 - 1
    // 定时器计数值
    wire timer_cnt_to_set;
    wire[timer_width-1:0] timer_cnt_set_v;
    wire[timer_width-1:0] timer_cnt_now_v;
    // 是否启动定时器
    wire timer_started;
    // 捕获/比较选择(4个通道)
    // 1'b0 -> 捕获, 1'b1 -> 比较
    wire[3:0] cap_cmp_sel;
    // 捕获/比较值
    wire[timer_width-1:0] timer_cmp[3:0];
    wire[timer_width-1:0] timer_cap_cmp_i[3:0];
    // 输入滤波阈值
    wire[7:0] timer_cap_filter_th[3:0];
    // 边沿检测类型
    // 2'b00 -> 上升沿, 2'b01 -> 下降沿, 2'b10 -> 上升/下降沿, 2'b11 -> 保留
    wire[1:0] timer_cap_edge[3:0];
    // 中断请求
    wire timer_expired_itr_req; // 计数溢出中断请求
    wire[3:0] timer_cap_itr_req; // 输入捕获中断请求
    
    regs_if_for_timer #(
        .timer_width(timer_width),
        .simulation_delay(simulation_delay)
    )regs_if_for_timer_u(
        .clk(clk),
        .resetn(resetn),
        
        .paddr(paddr),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .pready_out(pready_out),
        .prdata_out(prdata_out),
        .pslverr_out(pslverr_out),
        
        .prescale(prescale),
        .autoload(autoload),
        
        .timer_cnt_to_set(timer_cnt_to_set),
        .timer_cnt_set_v(timer_cnt_set_v),
        .timer_cnt_now_v(timer_cnt_now_v),
        
        .timer_started(timer_started),
        .cap_cmp_sel(cap_cmp_sel),
        
        .timer_chn1_cmp(timer_cmp[0]),
        .timer_chn1_cap_cmp_i(timer_cap_cmp_i[0]),
        .timer_chn1_cap_filter_th(timer_cap_filter_th[0]),
        .timer_chn1_cap_edge(timer_cap_edge[0]),
        
        .timer_chn2_cmp(timer_cmp[1]),
        .timer_chn2_cap_cmp_i(timer_cap_cmp_i[1]),
        .timer_chn2_cap_filter_th(timer_cap_filter_th[1]),
        .timer_chn2_cap_edge(timer_cap_edge[1]),
        
        .timer_chn3_cmp(timer_cmp[2]),
        .timer_chn3_cap_cmp_i(timer_cap_cmp_i[2]),
        .timer_chn3_cap_filter_th(timer_cap_filter_th[2]),
        .timer_chn3_cap_edge(timer_cap_edge[2]),
        
        .timer_chn4_cmp(timer_cmp[3]),
        .timer_chn4_cap_cmp_i(timer_cap_cmp_i[3]),
        .timer_chn4_cap_filter_th(timer_cap_filter_th[3]),
        .timer_chn4_cap_edge(timer_cap_edge[3]),
        
        .timer_expired_itr_req(timer_expired_itr_req),
        .timer_cap_itr_req(timer_cap_itr_req),
        
        .itr(itr)
    );
    
    /** 基本定时器 **/
	// 定时器计数溢出(指示)
    wire timer_expired;
	
    basic_timer #(
        .timer_width(timer_width),
        .simulation_delay(simulation_delay)
    )basic_timer_u(
        .clk(clk),
        .resetn(resetn),
        
        .prescale(prescale),
        .autoload(autoload),
        
        .timer_cnt_to_set(timer_cnt_to_set),
        .timer_cnt_set_v(timer_cnt_set_v),
        .timer_cnt_now_v(timer_cnt_now_v),
        
        .timer_started(timer_started),
        
        .timer_expired(timer_expired),
        
        .timer_expired_itr_req(timer_expired_itr_req)
    );
    
    /** 输入捕获/输出比较通道 **/
    genvar cap_cmp_chn_i;
    generate
        for(cap_cmp_chn_i = 0;cap_cmp_chn_i < 4;cap_cmp_chn_i = cap_cmp_chn_i + 1)
        begin
            if(cap_cmp_chn_i < channel_n)
            begin
                timer_ic_oc #(
                    .timer_width(timer_width),
                    .simulation_delay(simulation_delay)
                )timer_ic_oc_u(
                    .clk(clk),
                    .resetn(resetn),
                    
                    .cap_in(cap_in[cap_cmp_chn_i]),
                    .cmp_out(cmp_out[cap_cmp_chn_i]),
                    
                    .timer_cnt_now_v(timer_cnt_now_v),
                    .timer_started(timer_started),
                    
                    .timer_expired(timer_expired),
                    
                    .cap_cmp_sel(cap_cmp_sel[cap_cmp_chn_i]),
                    .timer_cmp(timer_cmp[cap_cmp_chn_i]),
                    .timer_cap_cmp_o(timer_cap_cmp_i[cap_cmp_chn_i]),
                    
                    .timer_cap_filter_th(timer_cap_filter_th[cap_cmp_chn_i]),
                    .timer_cap_edge(timer_cap_edge[cap_cmp_chn_i]),
                    
                    .timer_cap_itr_req(timer_cap_itr_req[cap_cmp_chn_i])
                );
            end
            else
            begin
                assign timer_cap_cmp_i[cap_cmp_chn_i] = {timer_width{1'bx}};
                
                assign timer_cap_itr_req[cap_cmp_chn_i] = 1'b0;
            end
        end
    endgenerate
    
endmodule
