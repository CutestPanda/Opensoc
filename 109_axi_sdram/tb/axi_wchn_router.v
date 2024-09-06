`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXIд����/д��Ӧͨ��·��

����: 
�������ӻ���д����(W)ͨ��ѡͨ������
��������д��Ӧͨ��(B)·�ɵ������Ĵӻ�

ע�⣺
��

Э��:
FIFO READ

����: �¼�ҫ
����: 2024/04/29
********************************************************************/


module axi_wchn_router #(
    parameter integer master_n = 4, // ��������(�����ڷ�Χ[2, 8]��)
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // AXI�ӻ�Wͨ��
    input wire[35:0] s0_w_payload, // 0�Ŵӻ�Wͨ���ĸ���
    input wire[35:0] s1_w_payload, // 1�Ŵӻ�Wͨ���ĸ���
    input wire[35:0] s2_w_payload, // 2�Ŵӻ�Wͨ���ĸ���
    input wire[35:0] s3_w_payload, // 3�Ŵӻ�Wͨ���ĸ���
    input wire[35:0] s4_w_payload, // 4�Ŵӻ�Wͨ���ĸ���
    input wire[35:0] s5_w_payload, // 5�Ŵӻ�Wͨ���ĸ���
    input wire[35:0] s6_w_payload, // 6�Ŵӻ�Wͨ���ĸ���
    input wire[35:0] s7_w_payload, // 7�Ŵӻ�Wͨ���ĸ���
    input wire[7:0] s_w_last, // ÿ���ӻ�Wͨ����last�ź�
    input wire[7:0] s_w_valid, // ÿ���ӻ�Wͨ����valid�ź�
    output wire[7:0] s_w_ready, // ÿ���ӻ�Wͨ����ready�ź�
    
    // AXI�ӻ�Bͨ��
    output wire[7:0] s_b_valid, // �ӻ�Bͨ����valid�ź�
    input wire[7:0] s_b_ready, // �ӻ�Bͨ����ready�ź�
    
    // AXI����Wͨ��
    output wire[35:0] m_w_payload, // ����Wͨ������
    output wire m_w_last,
    output wire m_w_valid,
    input wire m_w_ready,
    // AXI����Bͨ��
    input wire m_b_valid,
    output wire m_b_ready,
    
    // ��Ȩ�������fifo���˿�
    output wire grant_mid_fifo_ren,
    input wire grant_mid_fifo_empty_n,
    input wire[master_n-1:0] grant_mid_fifo_dout_onehot, // ��������
    input wire[clogb2(master_n-1):0] grant_mid_fifo_dout_bin // ����������
);

    // ����log2(bit_depth)               
    function integer clogb2 (input integer bit_depth);
        integer temp;
    begin
        temp = bit_depth;
        for(clogb2 = -1;temp > 0;clogb2 = clogb2 + 1)
            temp = temp >> 1;
    end
    endfunction

    /** AXI�ӻ�Wͨ���ĸ��� **/
    wire[35:0] s_w_payload[7:0];
    
    assign s_w_payload[0] = s0_w_payload;
    assign s_w_payload[1] = s1_w_payload;
    assign s_w_payload[2] = s2_w_payload;
    assign s_w_payload[3] = s3_w_payload;
    assign s_w_payload[4] = s4_w_payload;
    assign s_w_payload[5] = s5_w_payload;
    assign s_w_payload[6] = s6_w_payload;
    assign s_w_payload[7] = s7_w_payload;
    
    /** AXIд����ͨ��·�� **/
    // ��Wͨ��ͨ��ͻ����������Bͨ��δ����ʱ��ʹ��Wͨ��
    reg w_chn_en; // Wͨ��ʹ��
    
    // д����ʹ��
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            w_chn_en <= 1'b1;
        else
            # simulation_delay w_chn_en <= w_chn_en ? 
                (~((m_w_valid & m_w_ready & m_w_last) & (~(m_b_valid & m_b_ready)))):(m_b_valid & m_b_ready);
    end
    
    // ���ӻ�д����ͨ����payload��last·�ɸ�����
    assign m_w_payload = s_w_payload[grant_mid_fifo_dout_bin];
    assign m_w_last = s_w_last[grant_mid_fifo_dout_bin];
    // ����ÿ���ӻ���Wͨ��, ����������: w_chn_en & s_w_valid[i] & grant_mid_fifo_empty_n & m_w_ready & grant_mid_fifo_dout_onehot[i]
    assign m_w_valid = w_chn_en & grant_mid_fifo_empty_n & ((grant_mid_fifo_dout_onehot & s_w_valid[master_n-1:0]) != {master_n{1'b0}});
    assign s_w_ready = {{(8-master_n){1'b1}}, {master_n{w_chn_en & grant_mid_fifo_empty_n & m_w_ready}} & grant_mid_fifo_dout_onehot};
    
    /** AXIд��Ӧͨ��·�� **/
    // ����ÿ���ӻ���Bͨ��, ����������: m_b_valid & grant_mid_fifo_dout_onehot[i] & s_b_ready[i]
    assign s_b_valid = {{(8-master_n){1'b1}}, {master_n{m_b_valid}} & grant_mid_fifo_dout_onehot};
    assign m_b_ready = (grant_mid_fifo_dout_onehot & s_b_ready[master_n-1:0]) != {master_n{1'b0}};
    
    /** ��Ȩ�������fifo���˿� **/
    assign grant_mid_fifo_ren = m_b_valid & m_b_ready;
    
endmodule
