`timescale 1ns / 1ps
/********************************************************************
��ģ��: �������ֵĿ�ʱ����ͬ����

����: 
              req -> req_d2
              |        |
ack    ->   ack_d2     |
 |---------------------

ע�⣺
��

Э��:
��

����: �¼�ҫ
����: 2024/03/07
********************************************************************/


module async_handshake #(
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ1
    input wire clk1,
    input wire rst_n1,
    // ʱ�Ӻ͸�λ2
    input wire clk2,
    input wire rst_n2,
    
    // ʱ����1
    input wire req1, // ���ݴ�������(ָʾ)
    output wire busy, // ���ڽ������ݴ���(��־)
    // ʱ����2
    output wire req2 // ���ݴ�������(ָʾ)
);
    
    /** ʱ����1 **/
    reg req; // ���ݴ�������
    reg busy_reg; // ���ڽ������ݴ���(��־)
    wire ack_w;
    reg ack_d;
    reg ack_d2;
    reg ack_d3;
    wire ack_neg_edge; // ack�źų����½���(ָʾ)
    
    assign busy = busy_reg;
    
    assign ack_neg_edge = ack_d3 & (~ack_d2);
    
    // ���ݴ�������
    always @(posedge clk1 or negedge rst_n1)
    begin
        if(~rst_n1)
            req <= 1'b0;
        else
            # simulation_delay req <= req ? (~ack_d2):(req1 & (~busy_reg));
    end
    // ���ڽ������ݴ���(��־)
    always @(posedge clk1 or negedge rst_n1)
    begin
        if(~rst_n1)
            busy_reg <= 1'b0;
        else
            # simulation_delay busy_reg <= busy_reg ? (~ack_neg_edge):req1;
    end
    
    // ������ʱ����2��ack�źŴ�2��
    always @(posedge clk1 or negedge rst_n1)
    begin
        if(~rst_n1)
            {ack_d2, ack_d} <= 2'b00;
        else
            # simulation_delay {ack_d2, ack_d} <= {ack_d, ack_w};
    end
    // ��ͬ����ʱ����1��ack�źŴ�1��
    always @(posedge clk1 or negedge rst_n1)
    begin
        if(~rst_n1)
            ack_d3 <= 1'b0;
        else
            # simulation_delay ack_d3 <= ack_d2;
    end
    
    /** ʱ����2 **/
    reg ack; // ���ݴ���Ӧ��
    reg req_d;
    reg req_d2;
    reg req_d3;
    
    assign req2 = (~req_d3) & req_d2;
    
    assign ack_w = ack;
    
    // ���ݴ���Ӧ��
    always @(posedge clk2 or negedge rst_n2)
    begin
        if(~rst_n2)
            ack <= 1'b0;
        else
            # simulation_delay ack <= req_d2;
    end
    
    // ������ʱ����1��req�źŴ�2��
    always @(posedge clk2 or negedge rst_n2)
    begin
        if(~rst_n2)
            {req_d2, req_d} <= 2'b00;
        else
            # simulation_delay {req_d2, req_d} <= {req_d, req};
    end
    // ��ͬ����ʱ����2��req�źŴ�1��
    always @(posedge clk2 or negedge rst_n2)
    begin
        if(~rst_n2)
            req_d3 <= 1'b0;
        else
            # simulation_delay req_d3 <= req_d2;
    end

endmodule
