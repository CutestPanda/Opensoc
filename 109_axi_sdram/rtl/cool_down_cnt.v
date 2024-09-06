`timescale 1ns / 1ps
/********************************************************************
��ģ��: ��ȴ������

����:
���� -> ���� -> ��ȴ -> ���� -> ...

ע�⣺
��ȴ�����ڼ������������߻���ʱ����
��ȴ����ָ�Ӵ�������һ�ξ���������ʱ��������

Э��:
��

����: �¼�ҫ
����: 2024/04/13
********************************************************************/


module cool_down_cnt #(
    parameter integer max_cd = 20000 // ��ȴ�������ֵ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // ����ʱ����
    input wire[clogb2(max_cd-1):0] cd, // ��ȴ�� - 1
    
    // ����������/״̬
    input wire timer_trigger, // ����
    output wire timer_done, // ���
    output wire timer_ready, // ����
    output wire[clogb2(max_cd-1):0] timer_v // ��ǰ����ֵ
);
    
    // ����log2(bit_depth)
    function integer clogb2 (input integer bit_depth);
        integer temp;
    begin
        temp = bit_depth;
        for(clogb2 = -1;temp > 0;clogb2 = clogb2 + 1)
            temp = temp >> 1;
    end
    endfunction
    
    /** ��ȴ������ **/
    reg[clogb2(max_cd-1):0] cd_cnt; // ��ȴ����ֵ
    reg timer_ready_reg; // ����������
    
    assign timer_done = timer_ready ? (timer_trigger & cd == 0):(cd_cnt == 1);
    assign timer_ready = timer_ready_reg;
    assign timer_v = cd_cnt;
    
    // ��ȴ����ֵ
    always @(posedge clk)
    begin
        if(timer_ready | (cd_cnt == 0))
            cd_cnt <= cd;
        else if((~timer_ready) | timer_trigger)
            cd_cnt <= cd_cnt - 1;
    end
    
    // ����������
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            timer_ready_reg <= 1'b1;
        else
            timer_ready_reg <= timer_ready_reg ? (~(timer_trigger & (cd != 0))):(cd_cnt == 1);
    end

endmodule
