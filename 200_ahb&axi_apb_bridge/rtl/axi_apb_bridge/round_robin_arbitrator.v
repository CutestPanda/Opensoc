`timescale 1ns / 1ps
/********************************************************************
��ģ��: Round-Robin�ٲ���

����: 
����Round-Robin�㷨��0ʱ���ٲ���

ע�⣺
��

Э��:
ARB SLAVE

����: �¼�ҫ
����: 2024/04/28
********************************************************************/


module round_robin_arbitrator #(
    parameter integer chn_n = 4, // ͨ������(����>=2)
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // �ٲ���
    input wire[chn_n-1:0] req, // ����
    output wire[chn_n-1:0] grant, // ��Ȩ(������)
    output wire[clogb2(chn_n-1):0] sel, // ѡ��(�൱����Ȩ�Ķ����Ʊ�ʾ)
    output wire arb_valid // �ٲý����Ч
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
    // ������ -> ��������
    function [clogb2(chn_n-1):0] onehot_to_bin(input[chn_n-1:0] onehot);
        integer i;
    begin
        onehot_to_bin = 0;
        
        for(i = 0;i < chn_n;i = i + 1)
        begin
            if(onehot[i])
                onehot_to_bin = i;
        end
    end
    endfunction

    /** �ٲ����ȼ� **/
    reg[chn_n-1:0] priority_cnt; // ���ȼ������������
    
    // ���ȼ������������
    // 1��λ�ñ���������ȼ���ͨ��
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            priority_cnt <= {{(chn_n-1){1'b0}}, 1'b1};
        else if(|req) // ��ǰ������
            # simulation_delay priority_cnt <= {grant[chn_n-2:0], grant[chn_n-1]};
    end
    
    /** �ٲ���Ȩ��ѡ�� **/
    wire[chn_n*2-1:0] double_req;
    wire[chn_n*2-1:0] double_grant;
    
    assign double_req = {req, req};
    assign double_grant = double_req & (~(double_req - priority_cnt));
    
    assign grant = double_grant[chn_n-1:0] | double_grant[chn_n*2-1:chn_n];
    assign sel = onehot_to_bin(grant);
    assign arb_valid = |req;
    
endmodule
