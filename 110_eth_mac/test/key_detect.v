`timescale 1ns / 1ps
/********************************************************************
本模块: 按键检测

描述: 
带消抖的按键检测

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/02/28
********************************************************************/


module key_detect #(
    parameter integer elmt_buff_p = 1000000, // 消抖周期数(以时钟周期计)
    parameter detect_edge = "neg", // 按键检测边沿(pos | neg)
    parameter real simulation_delay = 1 // 仿真延迟
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 按键
    input wire key,
    
    // 按键按下(指示)
    output wire pressed
);

    /** 常量 **/
    // 按键检测状态
    localparam WAIT_EDGE = 2'b00; // 状态:等待边沿
    localparam DELAY = 2'b01; // 状态:延时
    localparam CONFIRM = 2'b10; // 状态:确认
    
    /** 按键同步器 **/
    reg key_d;
    reg key_syn;
    
    // 按键同步器
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            {key_syn, key_d} <= (detect_edge == "pos") ? 2'b00:2'b11;
        else
            # simulation_delay {key_syn, key_d} <= {key_d, key};
    end
    
    /** 按键边沿检测 **/
    wire key_detect_edge_valid; // 检测到有效边沿(指示)
    reg key_syn_d; // 延迟1clk的按键输入
    
    assign key_detect_edge_valid = (detect_edge == "pos") ? (key_syn & (~key_syn_d)):((~key_syn) & key_syn_d);
    
    // 延迟1clk的按键输入
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            key_syn_d <= (detect_edge == "pos") ? 1'b0:1'b1;
        else
            # simulation_delay key_syn_d <= key_syn;
    end
    
    /** 按键检测状态机 **/
    reg[1:0] key_detect_sts; // 按键检测状态
    reg elmt_buff_done; // 消抖完成(指示)
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            key_detect_sts <= WAIT_EDGE;
        else
        begin
            # simulation_delay;
        
            case(key_detect_sts)
                WAIT_EDGE: // 状态:等待边沿
                    if(key_detect_edge_valid)
                        key_detect_sts <= DELAY; // -> 状态:延时
                DELAY: // 状态:延时
                    if(elmt_buff_done)
                        key_detect_sts <= CONFIRM; // -> 状态:确认
                CONFIRM: // 状态:确认
                    key_detect_sts <= WAIT_EDGE; // -> 状态:等待边沿
                default:
                    key_detect_sts <= WAIT_EDGE;
            endcase
        end
    end
    
    /** 按键消抖 **/
    reg[31:0] elmt_buff_cnt; // 消抖计数器
    
    // 消抖计数器
    always @(posedge clk)
    begin
        if(key_detect_sts == WAIT_EDGE)
            # simulation_delay elmt_buff_cnt <= 32'd0;
        else if(key_detect_sts == DELAY)
            # simulation_delay elmt_buff_cnt <= elmt_buff_cnt + 32'd1;
    end
    
    // 消抖完成(指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            elmt_buff_done <= 1'b0;
        else
            # simulation_delay elmt_buff_done <= elmt_buff_cnt == elmt_buff_p - 2;
    end
    
    /** 按键按下指示 **/
    reg pressed_reg; // 按键按下(指示)
    
    assign pressed = pressed_reg;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            pressed_reg <= 1'b0;
        else
            # simulation_delay pressed_reg <= (key_detect_sts == CONFIRM) & ((detect_edge == "pos") ? key_syn:(~key_syn));
    end

endmodule
