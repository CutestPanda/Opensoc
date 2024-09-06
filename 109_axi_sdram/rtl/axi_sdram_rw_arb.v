`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXI-SDRAM�Ķ�д�ٲ�

����: 
��AXI�ӻ���AR/AWͨ�������ٲ�, ����sdram��д����

ע�⣺
��

Э��:
AXI SLAVE(ONLY AR/AW)
AXIS MASTER
FIFO WRITE

����: �¼�ҫ
����: 2024/05/01
********************************************************************/


module axi_sdram_rw_arb #(
    parameter arb_algorithm = "round-robin" // �ٲ��㷨("round-robin" | "fixed-r" | "fixed-w")
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // AXI�ӻ�
    // AR
    input wire[31:0] s_axi_araddr,
    input wire[7:0] s_axi_arlen,
    input wire[2:0] s_axi_arsize,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    // AW
    input wire[31:0] s_axi_awaddr,
    input wire[7:0] s_axi_awlen,
    input wire[2:0] s_axi_awsize,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    
    // SDRAM�û�����AXIS
    output wire[31:0] m_axis_usr_cmd_data, // {����(5bit), ba(2bit), �е�ַ(11bit), A10-0(11bit), �����(3bit)}
    output wire[8:0] m_axis_usr_cmd_user, // {�Ƿ��Զ����"ֹͣͻ��"����(1bit), ͻ������ - 1(8bit)}
    output wire m_axis_usr_cmd_valid,
    input wire m_axis_usr_cmd_ready,
    
    // дͻ���Ƕ����ַ��Ϣfifoд�˿�
    output wire wt_burst_unaligned_msg_fifo_wen,
    output wire[1:0] wt_burst_unaligned_msg_fifo_din, // д��ַ(awaddr)��2λ
    input wire wt_burst_unaligned_msg_fifo_full_n
);

    /** ���� **/
    // ������߼�����
    localparam CMD_LOGI_WT_DATA = 3'b010; // ����:д����
    localparam CMD_LOGI_RD_DATA = 3'b011; // ����:������
    
    /** ��д�ٲ� **/
    wire rd_req; // ������
    wire wt_req; // д����
    wire rd_grant; // ����Ȩ
    wire wt_grant; // д��Ȩ
    
    assign rd_req = s_axi_arvalid & m_axis_usr_cmd_ready;
    assign wt_req = s_axi_awvalid & m_axis_usr_cmd_ready & wt_burst_unaligned_msg_fifo_full_n;
    
    assign s_axi_arready = rd_grant;
    assign s_axi_awready = wt_grant;
    
    assign m_axis_usr_cmd_data = rd_grant ? {5'dx, s_axi_araddr[22:10], 3'd0, s_axi_araddr[9:2], CMD_LOGI_RD_DATA}:
        {5'dx, s_axi_awaddr[22:10], 3'd0, s_axi_awaddr[9:2], CMD_LOGI_WT_DATA};
    assign m_axis_usr_cmd_user = rd_grant ? {1'b1, s_axi_arlen}:{1'b1, s_axi_awlen};
    assign m_axis_usr_cmd_valid = s_axi_arvalid | (s_axi_awvalid & wt_burst_unaligned_msg_fifo_full_n);
    
    assign wt_burst_unaligned_msg_fifo_wen = s_axi_awvalid & s_axi_awready;
    assign wt_burst_unaligned_msg_fifo_din = s_axi_awaddr[1:0];
    
    // �ٲ���
    generate
        if(arb_algorithm == "round-robin")
            // Round-Robin�ٲ���
            round_robin_arbitrator #(
                .chn_n(2),
                .simulation_delay(0)
            )round_robin_arbitrator_u(
                .clk(clk),
                .rst_n(rst_n),
                .req({wt_req, rd_req}),
                .grant({wt_grant, rd_grant}),
                .sel(),
                .arb_valid()
            );
        else
        begin
            // �̶����ȼ�
            assign {wt_grant, rd_grant} = ({wt_req, rd_req} == 2'b00) ? 2'b00:
                ({wt_req, rd_req} == 2'b01) ? 2'b01:
                ({wt_req, rd_req} == 2'b10) ? 2'b10:
                    ((arb_algorithm == "fixed-r") ? 2'b01:2'b10);
        end
    endgenerate
    
endmodule
