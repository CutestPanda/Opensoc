`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXIд����ͨ���ı߽籣��

����: 
��AXI�ӻ���Wͨ�����б߽籣��
32λ��ַ/��������

ע�⣺
��֧��INCRͻ������

���·ǼĴ������ ->
    AXI�ӻ�Wͨ��: s_axis_w_ready
    AXI����Wͨ��: m_axi_wlast, m_axi_wvalid

Э��:
AXI MASTER(ONLY W)
AXIS SLAVE
FIFO READ

����: �¼�ҫ
����: 2024/05/01
********************************************************************/


module axi_w_boundary_protect #(
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // AXI�ӻ���W
    input wire[31:0] s_axis_w_data,
    input wire[3:0] s_axis_w_keep,
    input wire s_axis_w_last,
    input wire s_axis_w_valid,
    output wire s_axis_w_ready,
    
    // AXI������W
    output wire[31:0] m_axi_wdata,
    output wire[3:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready,
    
    // ͻ������fifo���˿�
    output wire burst_len_fifo_ren,
    input wire[7:0] burst_len_fifo_dout, // ͻ������ - 1
    input wire burst_len_fifo_empty_n
);
    
    reg wt_burst_transmitting; // дͻ��������
    reg[7:0] wt_trans_cnt; // д���������
    
    assign m_axi_wdata = s_axis_w_data;
    assign m_axi_wstrb = s_axis_w_keep;
    assign m_axi_wlast = (burst_len_fifo_dout == 8'd0) | (burst_len_fifo_dout == wt_trans_cnt);
    // ��������: wt_burst_transmitting & s_axis_w_valid & m_axi_wready
    assign m_axi_wvalid = wt_burst_transmitting & s_axis_w_valid;
    assign s_axis_w_ready = wt_burst_transmitting & m_axi_wready;
    
    assign burst_len_fifo_ren = ~wt_burst_transmitting;
    
    // дͻ��������
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_burst_transmitting <= 1'b0;
        else
            # simulation_delay wt_burst_transmitting <= wt_burst_transmitting ? (~(m_axi_wvalid & m_axi_wready & m_axi_wlast)):burst_len_fifo_empty_n;
    end
    
    // д���������
    always @(posedge clk)
    begin
        if(burst_len_fifo_ren & burst_len_fifo_empty_n)
            # simulation_delay wt_trans_cnt <= 8'd0;
        else if(m_axi_wvalid & m_axi_wready)
            # simulation_delay wt_trans_cnt <= wt_trans_cnt + 8'd1;
    end
    
endmodule
