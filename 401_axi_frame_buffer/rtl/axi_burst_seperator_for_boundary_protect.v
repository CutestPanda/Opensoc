`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXIͻ������(���ڱ߽籣��)

����: 
32λ��ַ/��������
֧�ַǶ��봫��/խ������
������߼�, ʱ�� = 0clk

ע�⣺
��֧��INCRͻ������

Э��:
��

����: �¼�ҫ
����: 2024/05/01
********************************************************************/


module axi_burst_seperator_for_boundary_protect #(
    parameter en_narrow_transfer = "false", // �Ƿ�����խ������
    parameter integer boundary_size = 1 // �߽��С(��KB��)(1 | 2 | 4)
)(
    // AXI�ӻ��ĵ�ַ��Ϣ
    input wire[31:0] s_axi_ax_addr,
    input wire[7:0] s_axi_ax_len,
    input wire[2:0] s_axi_ax_size,
    
    // ͻ�����ֽ��
    // ��32λ����������˵, ÿ��ͻ����ഫ��1KB, ��˽���1/2/4KB�߽籣��, ����ԭ����1��ͻ������Ϊ2��
    output wire across_boundary, // �Ƿ��Խ�߽�
    output wire[31:0] burst0_addr, // ͻ��0���׵�ַ
    output wire[7:0] burst0_len, // ͻ��0�ĳ��� - 1
    output wire[31:0] burst1_addr, // ͻ��1���׵�ַ
    output wire[7:0] burst1_len // ͻ��1�ĳ��� - 1
);
    
    wire[1:0] s_axi_ax_size_w;
    wire[7:0] now_regoin_trans_remaining; // ��ǰ1/2/4KB����ʣ�ഫ�����
    
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
