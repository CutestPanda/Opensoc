`timescale 1ns / 1ps
/********************************************************************
本模块: AXI突发划分(用于边界保护)

描述: 
32位地址/数据总线
支持非对齐传输/窄带传输
纯组合逻辑, 时延 = 0clk

注意：
仅支持INCR突发类型

协议:
无

作者: 陈家耀
日期: 2024/05/01
********************************************************************/


module axi_burst_seperator_for_boundary_protect #(
    parameter en_narrow_transfer = "false", // 是否允许窄带传输
    parameter integer boundary_size = 1 // 边界大小(以KB计)(1 | 2 | 4)
)(
    // AXI从机的地址信息
    input wire[31:0] s_axi_ax_addr,
    input wire[7:0] s_axi_ax_len,
    input wire[2:0] s_axi_ax_size,
    
    // 突发划分结果
    // 对32位数据总线来说, 每次突发最多传输1KB, 因此进行1/2/4KB边界保护, 最多把原来的1次突发划分为2次
    output wire across_boundary, // 是否跨越边界
    output wire[31:0] burst0_addr, // 突发0的首地址
    output wire[7:0] burst0_len, // 突发0的长度 - 1
    output wire[31:0] burst1_addr, // 突发1的首地址
    output wire[7:0] burst1_len // 突发1的长度 - 1
);
    
    wire[1:0] s_axi_ax_size_w;
    wire[7:0] now_regoin_trans_remaining; // 当前1/2/4KB区间剩余传输次数
    
    assign s_axi_ax_size_w = (en_narrow_transfer == "true") ? s_axi_ax_size[1:0]:2'b10;
    
    generate
        if(boundary_size == 1)
            assign now_regoin_trans_remaining = (s_axi_ax_size_w[1:0] == 2'b00) ? (32'd1024 - s_axi_ax_addr[9:0]):
                                                (s_axi_ax_size_w[1:0] == 2'b01) ? (32'd512 - s_axi_ax_addr[9:1]):
                                                                                (32'd256 - s_axi_ax_addr[9:2]);
        else if(boundary_size == 2)
            assign now_regoin_trans_remaining = (s_axi_ax_size_w[1:0] == 2'b00) ? (32'd2048 - s_axi_ax_addr[10:0]):
                                                (s_axi_ax_size_w[1:0] == 2'b01) ? (32'd1024 - s_axi_ax_addr[10:1]):
                                                                                (32'd512 - s_axi_ax_addr[10:2]);
        else
            assign now_regoin_trans_remaining = (s_axi_ax_size_w[1:0] == 2'b00) ? (32'd4096 - s_axi_ax_addr[11:0]):
                                                (s_axi_ax_size_w[1:0] == 2'b01) ? (32'd2048 - s_axi_ax_addr[11:1]):
                                                                                (32'd1024 - s_axi_ax_addr[11:2]);
    endgenerate
    
    generate
        if(boundary_size == 1)
            assign across_boundary = (s_axi_ax_size_w[1:0] == 2'b00) ? ((s_axi_ax_addr[9:0] + s_axi_ax_len) >= 11'd1024):
                                     (s_axi_ax_size_w[1:0] == 2'b01) ? ((s_axi_ax_addr[9:1] + s_axi_ax_len) >= 10'd512):
                                                                     ((s_axi_ax_addr[9:2] + s_axi_ax_len) >= 9'd256);
        else if(boundary_size == 2)
            assign across_boundary = (s_axi_ax_size_w[1:0] == 2'b00) ? ((s_axi_ax_addr[10:0] + s_axi_ax_len) >= 12'd2048):
                                     (s_axi_ax_size_w[1:0] == 2'b01) ? ((s_axi_ax_addr[10:1] + s_axi_ax_len) >= 11'd1024):
                                                                     ((s_axi_ax_addr[10:2] + s_axi_ax_len) >= 10'd512);
        else
            assign across_boundary = (s_axi_ax_size_w[1:0] == 2'b00) ? ((s_axi_ax_addr[11:0] + s_axi_ax_len) >= 13'd4096):
                                     (s_axi_ax_size_w[1:0] == 2'b01) ? ((s_axi_ax_addr[11:1] + s_axi_ax_len) >= 12'd2048):
                                                                     ((s_axi_ax_addr[11:2] + s_axi_ax_len) >= 11'd1024);
    endgenerate
    
    assign burst0_addr = s_axi_ax_addr;
    assign burst1_addr = (boundary_size == 1) ? ({s_axi_ax_addr[31:10], 10'd0} + 32'd1024):
                         (boundary_size == 2) ? ({s_axi_ax_addr[31:11], 11'd0} + 32'd2048):
                                                ({s_axi_ax_addr[31:12], 12'd0} + 32'd4096);
    
    assign burst0_len = across_boundary ? (now_regoin_trans_remaining - 8'd1):s_axi_ax_len;
    assign burst1_len = s_axi_ax_len - now_regoin_trans_remaining;
    
endmodule
