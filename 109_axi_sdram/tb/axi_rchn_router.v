`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXI������ͨ��·��

����: 
�������Ķ�����ͨ��(R)·�ɵ������Ĵӻ�

ע�⣺
��

Э��:
FIFO READ

����: �¼�ҫ
����: 2024/04/29
********************************************************************/


module axi_rchn_router #(
    parameter integer master_n = 4, // ��������(�����ڷ�Χ[2, 8]��)
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // AXI�ӻ�Rͨ���Ŀ����ź���
    output wire[7:0] s_rvalid, // ÿ���ӻ���valid
    input wire[7:0] s_rready, // ÿ���ӻ���ready
    
    // AXI����Rͨ���Ŀ����ź���
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output wire m_axi_rready,
    
    // ��Ȩ�������fifo���˿�
    output wire grant_mid_fifo_ren,
    input wire grant_mid_fifo_empty_n,
    input wire[master_n-1:0] grant_mid_fifo_dout_onehot // ��������
);
    
    // ����ÿ���ӻ���Rͨ��, ����������: grant_mid_fifo_empty_n & m_axi_rvalid & grant_mid_fifo_dout_onehot[i] & s_rready[i]
    assign s_rvalid = {{(8-master_n){1'b1}}, {master_n{grant_mid_fifo_empty_n & m_axi_rvalid}} & grant_mid_fifo_dout_onehot};
    assign m_axi_rready = grant_mid_fifo_empty_n & ((s_rready[master_n-1:0] & grant_mid_fifo_dout_onehot) != {master_n{1'b0}});
    assign grant_mid_fifo_ren = m_axi_rvalid & ((s_rready[master_n-1:0] & grant_mid_fifo_dout_onehot) != {master_n{1'b0}}) & m_axi_rlast;
    
endmodule
