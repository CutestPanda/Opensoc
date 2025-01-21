`timescale 1ns / 1ps
/********************************************************************
��ģ��: ͨ�ö�ʱ�������벶��/����Ƚ�ͨ��

����: 
���벶��/����Ƚ�

ע�⣺
��

Э��:
��

����: �¼�ҫ
����: 2024/06/10
********************************************************************/


module timer_ic_oc #(
    parameter integer timer_width = 16, // ��ʱ��λ��(8~32)
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire resetn,
    
    // ����/�Ƚ�
    input wire cap_in, // ��������
    output wire cmp_out, // �Ƚ����
    
    // ��ʱ������ֵ
    input wire[timer_width-1:0] timer_cnt_now_v,
    // �Ƿ�������ʱ��
    input wire timer_started,
    
    // ��ʱ���������(ָʾ)
    input wire timer_expired,
    
    // ����/�Ƚ�ѡ��
    // 1'b0 -> ����, 1'b1 -> �Ƚ�
    input wire cap_cmp_sel,
    // ����/�Ƚ�ֵ
    input wire[timer_width-1:0] timer_cmp,
    output wire[timer_width-1:0] timer_cap_cmp_o,
    
    // �����˲���ֵ
    input wire[7:0] timer_cap_filter_th,
    // ���ؼ������
    // 2'b00 -> ������, 2'b01 -> �½���, 2'b10 -> ����/�½���, 2'b11 -> ����
    input wire[1:0] timer_cap_edge,
    
    // ���벶���ж�����
    output wire timer_cap_itr_req
);

    /** ���� **/
    // ���벶���������
    localparam IN_CAP_EDGE_POS = 2'b00; // ��������:������
    localparam IN_CAP_EDGE_NEG = 2'b01; // ��������:�½���
    localparam IN_CAP_EDGE_BOTH = 2'b10; // ��������:����/�½���
    // ���벶��״̬����
    localparam IN_CAP_STS_IDLE = 2'b00; // ״̬:����
    localparam IN_CAP_STS_DELAY = 2'b01; // ״̬:�ӳ�
    localparam IN_CAP_STS_COMFIRM = 2'b10; // ״̬:ȷ��
    localparam IN_CAP_STS_CAP = 2'b11; // ״̬:����
    
    /** ����/�ȽϼĴ��� **/
    wire to_in_cap; // ���벶��(ָʾ)
    reg to_in_cap_d; // �ӳ�1clk�����벶��(ָʾ)
    reg[timer_width-1:0] timer_cap_v_latched; // ����Ĳ���ֵ
    reg[timer_width-1:0] timer_cap_cmp; // ����/�ȽϼĴ���
    
    assign timer_cap_cmp_o = timer_cap_cmp;
    assign timer_cap_itr_req = to_in_cap_d;
    
    // ����/�ȽϼĴ���
    // �����ǰģʽ�ǱȽ�ģʽ, ��֤����/�ȽϼĴ������ڶ�ʱ��δ������ʱ���������ʱ��������ֵ!
    always @(posedge clk)
    begin
        if(cap_cmp_sel ? ((~timer_started) | timer_expired):to_in_cap)
            # simulation_delay timer_cap_cmp <= cap_cmp_sel ? timer_cmp:timer_cap_v_latched;
    end
    
    // �ӳ�1clk�����벶��(ָʾ)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            to_in_cap_d <= 1'b0;
        else
            # simulation_delay to_in_cap_d <= to_in_cap;
    end
    
    /** ���벶�� **/
    reg[2:0] cap_in_d1_to_d3; // �ӳ�1~3clk�Ĳ�������
    wire cap_in_posedge_detected; // ���������⵽������
    wire cap_in_negedge_detected; // ���������⵽�½���
    wire cap_vld_edge; // ��⵽��Ч����(ָʾ)
    reg cap_in_edge_type_latched; // ����Ĳ��������������(1'b0 -> �½���, 1'b1 -> ������)
    reg[7:0] cap_in_filter_th_latched; // ����������˲���ֵ
    reg[7:0] cap_in_filter_cnt; // �����˲�������
    wire cap_in_filter_done; // �����˲����(ָʾ)
    reg[1:0] in_cap_sts; // ���벶��״̬
    
    assign to_in_cap = in_cap_sts == IN_CAP_STS_CAP;
    
    assign cap_in_posedge_detected = cap_in_d1_to_d3[1] & (~cap_in_d1_to_d3[2]);
    assign cap_in_negedge_detected = (~cap_in_d1_to_d3[1]) & cap_in_d1_to_d3[2];
    assign cap_vld_edge = (((timer_cap_edge == IN_CAP_EDGE_POS) & cap_in_posedge_detected) |
        ((timer_cap_edge == IN_CAP_EDGE_NEG) & cap_in_negedge_detected) |
        ((timer_cap_edge == IN_CAP_EDGE_BOTH) & (cap_in_posedge_detected | cap_in_negedge_detected)))
            & timer_started & (~cap_cmp_sel);
    assign cap_in_filter_done = cap_in_filter_cnt == cap_in_filter_th_latched;
    
    // �ӳ�1~3clk�Ĳ�������
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            cap_in_d1_to_d3 <= 3'b000;
        else
            # simulation_delay cap_in_d1_to_d3 <= {cap_in_d1_to_d3[1:0], cap_in};
    end
    
    // ����Ĳ���ֵ
    always @(posedge clk)
    begin
        if((in_cap_sts == IN_CAP_STS_IDLE) & cap_vld_edge)
            # simulation_delay timer_cap_v_latched <= timer_cnt_now_v;
    end
    // ����Ĳ��������������
    always @(posedge clk)
    begin
        if((in_cap_sts == IN_CAP_STS_IDLE) & cap_vld_edge)
            # simulation_delay cap_in_edge_type_latched <= cap_in_posedge_detected;
    end
    // ����������˲���ֵ
    always @(posedge clk)
    begin
        if((in_cap_sts == IN_CAP_STS_IDLE) & cap_vld_edge)
            # simulation_delay cap_in_filter_th_latched <= timer_cap_filter_th;
    end
    
    // �����˲�������
    always @(posedge clk)
    begin
        if(in_cap_sts == IN_CAP_STS_IDLE)
            # simulation_delay cap_in_filter_cnt <= 8'd0;
        else if(in_cap_sts == IN_CAP_STS_DELAY)
            # simulation_delay cap_in_filter_cnt <= cap_in_filter_cnt + 8'd1;
    end
    
    // ���벶��״̬
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            in_cap_sts <= IN_CAP_STS_IDLE;
        else
        begin
            # simulation_delay;
            
            case(in_cap_sts)
                IN_CAP_STS_IDLE: // ״̬:����
                    if(cap_vld_edge)
                        in_cap_sts <= IN_CAP_STS_DELAY; // -> ״̬:�ӳ�
                IN_CAP_STS_DELAY: // ״̬:�ӳ�
                    if(cap_in_filter_done)
                        in_cap_sts <= IN_CAP_STS_COMFIRM; // -> ״̬:ȷ��
                IN_CAP_STS_COMFIRM: // ״̬:ȷ��
                    if(cap_in_d1_to_d3[1] == cap_in_edge_type_latched)
                        in_cap_sts <= IN_CAP_STS_CAP; // -> ״̬:����
                    else
                        in_cap_sts <= IN_CAP_STS_IDLE; // -> ״̬:����
                IN_CAP_STS_CAP: // ״̬:����
                    in_cap_sts <= IN_CAP_STS_IDLE; // -> ״̬:����
                default:
                    in_cap_sts <= IN_CAP_STS_IDLE;
            endcase
        end
    end
    
    /** ����Ƚ� **/
    wire cmp_o; // ����Ƚ�ֵ
    reg cmp_o_d; // �ӳ�1clk������Ƚ�ֵ
    
    assign cmp_out = cmp_o_d;
    
    assign cmp_o = timer_started & cap_cmp_sel & (timer_cnt_now_v >= timer_cap_cmp);
    
    // �ӳ�1clk������Ƚ�ֵ
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            cmp_o_d <= 1'b0;
        else
            # simulation_delay cmp_o_d <= cmp_o;
    end
    
endmodule
