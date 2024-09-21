`timescale 1ns / 1ps
/********************************************************************
��ģ��: APB-TIMER

����: 
��APB�ӽӿڵ�ͨ�ö�ʱ��
8~32λ��ʱ��
֧�ֶ����ͨ�����벶��/����Ƚ�
���벶��֧�������˲����ɲ���������/�½���/˫��
�����ü�������жϺ����벶���ж�

�Ĵ���->
    ƫ����  |    ����                     |   ��д����    |        ��ע
    0x00    timer_width-1~0:Ԥ��Ƶϵ��-1         W
    0x04    timer_width-1~0:�Զ�װ��ֵ-1         W
    0x08    timer_width-1~0:��ʱ������ֵ         RW
    0x0C    0:�Ƿ�������ʱ��                     W
            11~8:����/�Ƚ�ѡ��(4��ͨ��)          W
    0x10    0:ȫ���ж�ʹ��                       W
            8:��������ж�ʹ��                   W
            12~9:���벶���ж�ʹ��                W
    0x14    0:ȫ���жϱ�־                       RWC
            8:��������жϱ�־                   R
            12~9:���벶���жϱ�־                R
    0x18    timer_width-1~0:����/�Ƚ�ֵ(ͨ��1)   RW       ��ʹ�ܲ���/�Ƚ�ͨ��1ʱ����
    0x1C    7~0:�����˲���ֵ                     W        ��ʹ�ܲ���/�Ƚ�ͨ��1ʱ����
            9~8:���ؼ������                     W
    0x20    timer_width-1~0:����/�Ƚ�ֵ(ͨ��2)   RW       ��ʹ�ܲ���/�Ƚ�ͨ��2ʱ����
    0x24    7~0:�����˲���ֵ                     W        ��ʹ�ܲ���/�Ƚ�ͨ��2ʱ����
            9~8:���ؼ������                     W
    0x28    timer_width-1~0:����/�Ƚ�ֵ(ͨ��3)   RW       ��ʹ�ܲ���/�Ƚ�ͨ��3ʱ����
    0x2C    7~0:�����˲���ֵ                     W        ��ʹ�ܲ���/�Ƚ�ͨ��3ʱ����
            9~8:���ؼ������                     W
    0x30    timer_width-1~0:����/�Ƚ�ֵ(ͨ��4)   RW       ��ʹ�ܲ���/�Ƚ�ͨ��4ʱ����
    0x34    7~0:�����˲���ֵ                     W        ��ʹ�ܲ���/�Ƚ�ͨ��4ʱ����
            9~8:���ؼ������                     W

ע�⣺
��

Э��:
APB SLAVE

����: �¼�ҫ
����: 2024/06/09
********************************************************************/


module apb_timer #(
    parameter integer timer_width = 16, // ��ʱ��λ��(8~32)
    parameter integer channel_n = 1, // ����/�Ƚ�ͨ����(0~4)
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire resetn,
    
    // APB�ӻ��ӿ�
    input wire[31:0] paddr,
    input wire psel,
    input wire penable,
    input wire pwrite,
    input wire[31:0] pwdata,
    output wire pready_out, // const -> 1'b1
    output wire[31:0] prdata_out,
    output wire pslverr_out, // const -> 1'b0
    
    // ����/�Ƚ�
    input wire[channel_n-1:0] cap_in, // ��������
    output wire[channel_n-1:0] cmp_out, // �Ƚ����
    
    // �ж��ź�
    output wire itr
);
    
    /** �Ĵ����ӿ� **/
    wire[timer_width-1:0] prescale; // Ԥ��Ƶϵ�� - 1
    wire[timer_width-1:0] autoload; // �Զ�װ��ֵ - 1
    // ��ʱ������ֵ
    wire timer_cnt_to_set;
    wire[timer_width-1:0] timer_cnt_set_v;
    wire[timer_width-1:0] timer_cnt_now_v;
    // �Ƿ�������ʱ��
    wire timer_started;
    // ����/�Ƚ�ѡ��(4��ͨ��)
    // 1'b0 -> ����, 1'b1 -> �Ƚ�
    wire[3:0] cap_cmp_sel;
    // ����/�Ƚ�ֵ
    wire[timer_width-1:0] timer_cmp[3:0];
    wire[timer_width-1:0] timer_cap_cmp_i[3:0];
    // �����˲���ֵ
    wire[7:0] timer_cap_filter_th[3:0];
    // ���ؼ������
    // 2'b00 -> ������, 2'b01 -> �½���, 2'b10 -> ����/�½���, 2'b11 -> ����
    wire[1:0] timer_cap_edge[3:0];
    // �ж�����
    wire timer_expired_itr_req; // ��������ж�����
    wire[3:0] timer_cap_itr_req; // ���벶���ж�����
    
    regs_if_for_timer #(
        .timer_width(timer_width),
        .simulation_delay(simulation_delay)
    )regs_if_for_timer_u(
        .clk(clk),
        .resetn(resetn),
        
        .paddr(paddr),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .pready_out(pready_out),
        .prdata_out(prdata_out),
        .pslverr_out(pslverr_out),
        
        .prescale(prescale),
        .autoload(autoload),
        
        .timer_cnt_to_set(timer_cnt_to_set),
        .timer_cnt_set_v(timer_cnt_set_v),
        .timer_cnt_now_v(timer_cnt_now_v),
        
        .timer_started(timer_started),
        .cap_cmp_sel(cap_cmp_sel),
        
        .timer_chn1_cmp(timer_cmp[0]),
        .timer_chn1_cap_cmp_i(timer_cap_cmp_i[0]),
        .timer_chn1_cap_filter_th(timer_cap_filter_th[0]),
        .timer_chn1_cap_edge(timer_cap_edge[0]),
        
        .timer_chn2_cmp(timer_cmp[1]),
        .timer_chn2_cap_cmp_i(timer_cap_cmp_i[1]),
        .timer_chn2_cap_filter_th(timer_cap_filter_th[1]),
        .timer_chn2_cap_edge(timer_cap_edge[1]),
        
        .timer_chn3_cmp(timer_cmp[2]),
        .timer_chn3_cap_cmp_i(timer_cap_cmp_i[2]),
        .timer_chn3_cap_filter_th(timer_cap_filter_th[2]),
        .timer_chn3_cap_edge(timer_cap_edge[2]),
        
        .timer_chn4_cmp(timer_cmp[3]),
        .timer_chn4_cap_cmp_i(timer_cap_cmp_i[3]),
        .timer_chn4_cap_filter_th(timer_cap_filter_th[3]),
        .timer_chn4_cap_edge(timer_cap_edge[3]),
        
        .timer_expired_itr_req(timer_expired_itr_req),
        .timer_cap_itr_req(timer_cap_itr_req),
        
        .itr(itr)
    );
    
    /** ������ʱ�� **/
	// ��ʱ���������(ָʾ)
    wire timer_expired;
	
    basic_timer #(
        .timer_width(timer_width),
        .simulation_delay(simulation_delay)
    )basic_timer_u(
        .clk(clk),
        .resetn(resetn),
        
        .prescale(prescale),
        .autoload(autoload),
        
        .timer_cnt_to_set(timer_cnt_to_set),
        .timer_cnt_set_v(timer_cnt_set_v),
        .timer_cnt_now_v(timer_cnt_now_v),
        
        .timer_started(timer_started),
        
        .timer_expired(timer_expired),
        
        .timer_expired_itr_req(timer_expired_itr_req)
    );
    
    /** ���벶��/����Ƚ�ͨ�� **/
    genvar cap_cmp_chn_i;
    generate
        for(cap_cmp_chn_i = 0;cap_cmp_chn_i < 4;cap_cmp_chn_i = cap_cmp_chn_i + 1)
        begin
            if(cap_cmp_chn_i < channel_n)
            begin
                timer_ic_oc #(
                    .timer_width(timer_width),
                    .simulation_delay(simulation_delay)
                )timer_ic_oc_u(
                    .clk(clk),
                    .resetn(resetn),
                    
                    .cap_in(cap_in[cap_cmp_chn_i]),
                    .cmp_out(cmp_out[cap_cmp_chn_i]),
                    
                    .timer_cnt_now_v(timer_cnt_now_v),
                    .timer_started(timer_started),
                    
                    .timer_expired(timer_expired),
                    
                    .cap_cmp_sel(cap_cmp_sel[cap_cmp_chn_i]),
                    .timer_cmp(timer_cmp[cap_cmp_chn_i]),
                    .timer_cap_cmp_o(timer_cap_cmp_i[cap_cmp_chn_i]),
                    
                    .timer_cap_filter_th(timer_cap_filter_th[cap_cmp_chn_i]),
                    .timer_cap_edge(timer_cap_edge[cap_cmp_chn_i]),
                    
                    .timer_cap_itr_req(timer_cap_itr_req[cap_cmp_chn_i])
                );
            end
            else
            begin
                assign timer_cap_cmp_i[cap_cmp_chn_i] = {timer_width{1'bx}};
                
                assign timer_cap_itr_req[cap_cmp_chn_i] = 1'b0;
            end
        end
    endgenerate
    
endmodule
