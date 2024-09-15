`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXI������ͨ���ı߽籣��

����: 
��AXI�ӻ���Rͨ�����б߽籣��
32λ��ַ/��������

ע�⣺
��֧��INCRͻ������

���·ǼĴ������ ->
    AXI�ӻ���Rͨ��: m_axis_r_last, m_axis_r_valid
    AXI������Rͨ��: m_axi_rready

Э��:
AXI MASTER(ONLY R)
AXIS MASTER
FIFO READ

����: �¼�ҫ
����: 2024/05/02
********************************************************************/


module axi_r_boundary_protect #(
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // AXI�ӻ���R
    output wire[31:0] m_axis_r_data,
    output wire[1:0] m_axis_r_user, // {rresp(2bit)}
    output wire m_axis_r_last,
    output wire m_axis_r_valid,
    input wire m_axis_r_ready,
    
    // AXI������R
    input wire[31:0] m_axi_rdata,
    input wire m_axi_rlast,
    input wire[1:0] m_axi_rresp,
    input wire m_axi_rvalid,
    output wire m_axi_rready,
    
    // ������־fifoд�˿�
    output wire rd_across_boundary_fifo_ren,
    input wire rd_across_boundary_fifo_dout,
    input wire rd_across_boundary_fifo_empty_n
);
    
    reg rd_burst_transmitting; // ��ͻ��������
    reg burst_merged; // ��ͻ���Ѻϲ�
    
    assign m_axis_r_data = m_axi_rdata;
    assign m_axis_r_user = m_axi_rresp;
    assign m_axis_r_last = m_axi_rlast & ((~rd_across_boundary_fifo_dout) | burst_merged);
    // ��������: rd_burst_transmitting & m_axi_rvalid & m_axis_r_ready
    assign m_axis_r_valid = rd_burst_transmitting & m_axi_rvalid;
    assign m_axi_rready = rd_burst_transmitting & m_axis_r_ready;
    
    assign rd_across_boundary_fifo_ren = ~rd_burst_transmitting;
    
    // ��ͻ��������
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_burst_transmitting <= 1'b0;
        else
            # simulation_delay rd_burst_transmitting <= rd_burst_transmitting ? (~(m_axi_rvalid & m_axis_r_ready & m_axis_r_last)):rd_across_boundary_fifo_empty_n;
    end
    
    // ��ͻ���Ѻϲ�
    always @(posedge clk)
    begin
        if((~rd_burst_transmitting) & rd_across_boundary_fifo_empty_n)
            # simulation_delay burst_merged <= 1'b0;
        else if(m_axi_rvalid & m_axi_rready & m_axi_rlast)
            # simulation_delay burst_merged <= ~burst_merged;
    end
    
endmodule
