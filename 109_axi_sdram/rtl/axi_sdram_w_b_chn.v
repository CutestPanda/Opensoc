`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXI-SDRAM��д����/д��Ӧͨ��

����: 
��д����ͨ����ÿ��ͻ���ĵ�1�������Ͻ��ж��봦��
��ÿ��дͻ������д��Ӧ

ע�⣺
��

Э��:
AXI SLAVE(ONLY W/B)
AXIS MASTER
FIFO READ

����: �¼�ҫ
����: 2024/05/01
********************************************************************/


module axi_sdram_w_b_chn (
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // AXI�ӻ�
    // W
    input wire[31:0] s_axi_wdata,
    input wire[3:0] s_axi_wstrb,
    input wire s_axi_wlast,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    // B
    output wire[1:0] s_axi_bresp, // const -> 2'b00
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    
    // SDRAMд����AXIS
    output wire[31:0] m_axis_wt_data,
    output wire[3:0] m_axis_wt_keep,
    output wire m_axis_wt_last,
    output wire m_axis_wt_valid,
    input wire m_axis_wt_ready,
    
    // дͻ���Ƕ����ַ��Ϣfifo���˿�
    output wire wt_burst_unaligned_msg_fifo_ren,
    input wire[1:0] wt_burst_unaligned_msg_fifo_dout, // д��ַ(awaddr)��2λ
    input wire wt_burst_unaligned_msg_fifo_empty_n
);
    
    wire[3:0] wburst_realign_keep_mask; // дͻ���ض���keep����
    reg bresp_transmitting; // ��ǰ���ڴ���д��Ӧ
    reg first_trans_in_wt_burst; // ��ǰдͻ���ĵ�1�δ���
    
    assign wburst_realign_keep_mask = (wt_burst_unaligned_msg_fifo_dout == 2'b00) ? 4'b1111:
                                      (wt_burst_unaligned_msg_fifo_dout == 2'b01) ? 4'b1110:
                                      (wt_burst_unaligned_msg_fifo_dout == 2'b10) ? 4'b1100:
                                                                                    4'b1000;
    
    // ��������: s_axi_wvalid & (~bresp_transmitting) & m_axis_wt_ready & wt_burst_unaligned_msg_fifo_empty_n
    assign s_axi_wready = (~bresp_transmitting) & m_axis_wt_ready & wt_burst_unaligned_msg_fifo_empty_n;
    
    assign s_axi_bresp = 2'b00;
    assign s_axi_bvalid = bresp_transmitting;
    
    assign m_axis_wt_data = s_axi_wdata;
    assign m_axis_wt_keep = first_trans_in_wt_burst ? (s_axi_wstrb & wburst_realign_keep_mask):s_axi_wstrb;
    assign m_axis_wt_last = s_axi_wlast;
    assign m_axis_wt_valid = (~bresp_transmitting) & s_axi_wvalid & wt_burst_unaligned_msg_fifo_empty_n;
    
    assign wt_burst_unaligned_msg_fifo_ren = s_axi_bvalid & s_axi_bready;
    
    // ��ǰ���ڴ���д��Ӧ
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            bresp_transmitting <= 1'b0;
        else
            bresp_transmitting <= bresp_transmitting ? (~s_axi_bready):(s_axi_wvalid & s_axi_wready & s_axi_wlast);
    end
    
    // ��ǰдͻ���ĵ�1�δ���
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            first_trans_in_wt_burst <= 1'b1;
        else
            first_trans_in_wt_burst <= first_trans_in_wt_burst ? (~(s_axi_wvalid & s_axi_wready)):(s_axi_bvalid & s_axi_bready);
    end
    
endmodule
