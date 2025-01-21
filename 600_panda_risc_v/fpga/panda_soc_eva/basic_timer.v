`timescale 1ns / 1ps
/********************************************************************
��ģ��: ������ʱ��

����: 
��Ԥ��Ƶ���Զ�װ�ع���
8~32λ������ʱ��

ע�⣺
��

Э��:
��

����: �¼�ҫ
����: 2024/06/10
********************************************************************/


module basic_timer #(
    parameter integer timer_width = 16, // ��ʱ��λ��(8~32)
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire resetn,
    
    // Ԥ��Ƶϵ�� - 1
    input wire[timer_width-1:0] prescale,
    // �Զ�װ��ֵ - 1
    input wire[timer_width-1:0] autoload,
    
    // ��ʱ������ֵ
    input wire timer_cnt_to_set,
    input wire[timer_width-1:0] timer_cnt_set_v,
    output wire[timer_width-1:0] timer_cnt_now_v,
    
    // �Ƿ�������ʱ��
    input wire timer_started,
    
    // ��ʱ���������(ָʾ)
    output wire timer_expired,
    
    // ��������ж�����
    output wire timer_expired_itr_req
);
    
    /** Ԥ��Ƶ������ **/
    reg[timer_width-1:0] prescale_shadow; // Ԥ��Ƶϵ�� - 1(Ӱ�ӼĴ���)
    wire prescale_cnt_rst; // Ԥ��Ƶ������(����ָʾ)
    reg[timer_width-1:0] prescale_cnt; // Ԥ��Ƶ������
    
    assign prescale_cnt_rst = prescale_cnt == prescale_shadow;
    
    // Ԥ��Ƶϵ�� - 1(Ӱ�ӼĴ���)
    always @(posedge clk)
    begin
        if((~timer_started) | prescale_cnt_rst)
            # simulation_delay prescale_shadow <= prescale;
    end
    
    // Ԥ��Ƶ������
    always @(posedge clk)
    begin
        if(~timer_started)
            # simulation_delay prescale_cnt <= 0;
        else
            # simulation_delay prescale_cnt <= prescale_cnt_rst ? 0:(prescale_cnt + 1);
    end
    
    /** ��ʱ������ **/
    reg[timer_width-1:0] timer_cnt; // ��ʱ������
    reg timer_expired_d; // �ӳ�1clk�Ķ�ʱ���������(ָʾ)
    
    assign timer_cnt_now_v = timer_cnt;
    assign timer_expired = timer_started & prescale_cnt_rst & (timer_cnt == 0);
    
    assign timer_expired_itr_req = timer_expired_d;
    
    // ��ʱ������
    always @(posedge clk)
    begin
        if(timer_cnt_to_set)
            # simulation_delay timer_cnt <= timer_cnt_set_v;
        else if(timer_started & prescale_cnt_rst)
            # simulation_delay timer_cnt <= (timer_cnt == 0) ? autoload:(timer_cnt - 1);
    end
    
    // �ӳ�1clk�Ķ�ʱ���������(ָʾ)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            timer_expired_d <= 1'b0;
        else
            # simulation_delay timer_expired_d <= timer_expired;
    end
    
endmodule
