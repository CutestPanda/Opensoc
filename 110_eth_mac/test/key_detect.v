`timescale 1ns / 1ps
/********************************************************************
��ģ��: �������

����: 
�������İ������

ע�⣺
��

Э��:
��

����: �¼�ҫ
����: 2024/02/28
********************************************************************/


module key_detect #(
    parameter integer elmt_buff_p = 1000000, // ����������(��ʱ�����ڼ�)
    parameter detect_edge = "neg", // ����������(pos | neg)
    parameter real simulation_delay = 1 // �����ӳ�
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // ����
    input wire key,
    
    // ��������(ָʾ)
    output wire pressed
);

    /** ���� **/
    // �������״̬
    localparam WAIT_EDGE = 2'b00; // ״̬:�ȴ�����
    localparam DELAY = 2'b01; // ״̬:��ʱ
    localparam CONFIRM = 2'b10; // ״̬:ȷ��
    
    /** ����ͬ���� **/
    reg key_d;
    reg key_syn;
    
    // ����ͬ����
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            {key_syn, key_d} <= (detect_edge == "pos") ? 2'b00:2'b11;
        else
            # simulation_delay {key_syn, key_d} <= {key_d, key};
    end
    
    /** �������ؼ�� **/
    wire key_detect_edge_valid; // ��⵽��Ч����(ָʾ)
    reg key_syn_d; // �ӳ�1clk�İ�������
    
    assign key_detect_edge_valid = (detect_edge == "pos") ? (key_syn & (~key_syn_d)):((~key_syn) & key_syn_d);
    
    // �ӳ�1clk�İ�������
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            key_syn_d <= (detect_edge == "pos") ? 1'b0:1'b1;
        else
            # simulation_delay key_syn_d <= key_syn;
    end
    
    /** �������״̬�� **/
    reg[1:0] key_detect_sts; // �������״̬
    reg elmt_buff_done; // �������(ָʾ)
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            key_detect_sts <= WAIT_EDGE;
        else
        begin
            # simulation_delay;
        
            case(key_detect_sts)
                WAIT_EDGE: // ״̬:�ȴ�����
                    if(key_detect_edge_valid)
                        key_detect_sts <= DELAY; // -> ״̬:��ʱ
                DELAY: // ״̬:��ʱ
                    if(elmt_buff_done)
                        key_detect_sts <= CONFIRM; // -> ״̬:ȷ��
                CONFIRM: // ״̬:ȷ��
                    key_detect_sts <= WAIT_EDGE; // -> ״̬:�ȴ�����
                default:
                    key_detect_sts <= WAIT_EDGE;
            endcase
        end
    end
    
    /** �������� **/
    reg[31:0] elmt_buff_cnt; // ����������
    
    // ����������
    always @(posedge clk)
    begin
        if(key_detect_sts == WAIT_EDGE)
            # simulation_delay elmt_buff_cnt <= 32'd0;
        else if(key_detect_sts == DELAY)
            # simulation_delay elmt_buff_cnt <= elmt_buff_cnt + 32'd1;
    end
    
    // �������(ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            elmt_buff_done <= 1'b0;
        else
            # simulation_delay elmt_buff_done <= elmt_buff_cnt == elmt_buff_p - 2;
    end
    
    /** ��������ָʾ **/
    reg pressed_reg; // ��������(ָʾ)
    
    assign pressed = pressed_reg;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            pressed_reg <= 1'b0;
        else
            # simulation_delay pressed_reg <= (key_detect_sts == CONFIRM) & ((detect_edge == "pos") ? key_syn:(~key_syn));
    end

endmodule
