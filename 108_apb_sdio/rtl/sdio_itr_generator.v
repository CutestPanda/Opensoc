`timescale 1ns / 1ps
/********************************************************************
��ģ��: APB-SDIO���жϷ�����

����:
�ж� -> �������ж�, д�����ж�, �������������ж�����

ע�⣺
��

Э��:
��

����: �¼�ҫ
����: 2024/01/24
********************************************************************/


module sdio_itr_generator  #(
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire resetn,
    
    // ������״̬
    input wire sdio_ctrler_done,
    input wire[1:0] sdio_ctrler_rw_type_done,
    
    // �жϿ���
    output wire rdata_itr_org_pulse, // ������ԭʼ�ж�����
    output wire wdata_itr_org_pulse, // д����ԭʼ�ж�����
    output wire common_itr_org_pulse, // �������������ж�����
    input wire rdata_itr_en, // �������ж�ʹ��
    input wire wdata_itr_en, // д�����ж�ʹ��
    input wire common_itr_en, // �������������ж�ʹ��
    input wire global_org_itr_pulse, // ȫ��ԭʼ�ж�����
    output wire itr // �ж��ź�
);

    /** ���� **/
    // ����Ķ�д����
    localparam RW_TYPE_NON = 2'b00; // �Ƕ�д
    localparam RW_TYPE_READ = 2'b01; // ��
    localparam RW_TYPE_WRITE = 2'b10; // д

    /** ԭʼ���ж����� **/
    reg rdata_itr_org_pulse_reg;
    reg wdata_itr_org_pulse_reg;
    reg common_itr_org_pulse_reg;
    
    assign {rdata_itr_org_pulse, wdata_itr_org_pulse, common_itr_org_pulse} = {rdata_itr_org_pulse_reg, wdata_itr_org_pulse_reg, common_itr_org_pulse_reg};
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            rdata_itr_org_pulse_reg <= 1'b0;
        else if(~rdata_itr_en) // ǿ������
            # simulation_delay rdata_itr_org_pulse_reg <= 1'b0;
        else // ��������
            # simulation_delay rdata_itr_org_pulse_reg <= sdio_ctrler_done & (sdio_ctrler_rw_type_done == RW_TYPE_READ);
    end
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            wdata_itr_org_pulse_reg <= 1'b0;
        else if(~wdata_itr_en) // ǿ������
            # simulation_delay wdata_itr_org_pulse_reg <= 1'b0;
        else // ��������
            # simulation_delay wdata_itr_org_pulse_reg <= sdio_ctrler_done & (sdio_ctrler_rw_type_done == RW_TYPE_WRITE);
    end
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            common_itr_org_pulse_reg <= 1'b0;
        else if(~common_itr_en) // ǿ������
            # simulation_delay common_itr_org_pulse_reg <= 1'b0;
        else // ��������
            # simulation_delay common_itr_org_pulse_reg <= sdio_ctrler_done & (sdio_ctrler_rw_type_done == RW_TYPE_NON);
    end
    
    /** �ж��ź� **/
    itr_generator #(
        .pulse_w(10),
        .simulation_delay(simulation_delay)
    )itr_generator_u(
        .clk(clk),
        .rst_n(resetn),
        .itr_org(global_org_itr_pulse),
        .itr(itr)
    );

endmodule
