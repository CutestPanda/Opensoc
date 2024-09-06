`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXIд��Ӧͨ���ı߽籣��

����: 
��AXI�ӻ���Bͨ�����б߽籣��
32λ��ַ/��������

ע�⣺
��֧��INCRͻ������

���·ǼĴ������ ->
    AXI�ӻ�Bͨ��: m_axis_b_valid
    AXI����Bͨ��: m_axi_bready

Э��:
AXI MASTER(ONLY B)
AXIS MASTER
FIFO READ

����: �¼�ҫ
����: 2024/05/02
********************************************************************/


module axi_b_boundary_protect #(
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // AXI�ӻ���B
    output wire[7:0] m_axis_b_data, // {����(6bit), bresp(2bit)}
    output wire m_axis_b_valid,
    input wire m_axis_b_ready,
    
    // AXI������B
    input wire[1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready,
    
    // д����־fifoд�˿�
    output wire wt_across_boundary_fifo_ren,
    input wire wt_across_boundary_fifo_dout,
    input wire wt_across_boundary_fifo_empty_n
);

    reg bresp_merged; // д��Ӧ�ϲ�

    assign m_axis_b_data = {6'dx, m_axi_bresp};
    // ��������: wt_across_boundary_fifo_empty_n & m_axi_bvalid & ((~wt_across_boundary_fifo_dout) | bresp_merged) & m_axis_b_ready
    assign m_axis_b_valid = wt_across_boundary_fifo_empty_n & m_axi_bvalid & ((~wt_across_boundary_fifo_dout) | bresp_merged);
    // ��������: m_axi_bvalid & wt_across_boundary_fifo_empty_n & m_axis_b_ready
    assign m_axi_bready = wt_across_boundary_fifo_empty_n & m_axis_b_ready;
    
    assign wt_across_boundary_fifo_ren = m_axi_bvalid & ((~wt_across_boundary_fifo_dout) | bresp_merged) & m_axis_b_ready;
    
    // д��Ӧ�ϲ�
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            bresp_merged <= 1'b0;
        else if(m_axi_bvalid & m_axi_bready)
            # simulation_delay bresp_merged <= ~((~wt_across_boundary_fifo_dout) | bresp_merged);
    end
    
endmodule
