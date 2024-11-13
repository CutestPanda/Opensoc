`timescale 1ns / 1ps
/********************************************************************
��ģ��: �ж��źŷ�����

����: 
��ԭʼ���ж�������չΪһ��������ж��ź�

ע�⣺
�ж�������� >= 2

Э��:
��

����: �¼�ҫ
����: 2023/11/08
********************************************************************/


module itr_generator #(
    parameter integer pulse_w = 100, // �ж�����(����>=1)
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    input wire itr_org, // ԭʼ�ж�����
    output wire itr // �ж����
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
    
    // �����ж��ź�
    reg itr_reg; // �ж��ź�
    reg[clogb2(pulse_w - 1):0] itr_cnt; // �жϼ�����
    
    assign itr = itr_reg;
    
    generate
        if(pulse_w == 1)
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    itr_reg <= 1'b0;
                else
                    itr_reg <= # simulation_delay itr_org;
            end
        end
        else
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    itr_reg <= 1'b0;
                else
                begin
                    if(~itr_reg) // �ȴ�ԭʼ�ж�����
                        itr_reg <= # simulation_delay itr_org;
                    else // �ȴ��������
                        itr_reg <= # simulation_delay itr_cnt != pulse_w - 1;
                end
            end
        end
    endgenerate
    
    always @(posedge clk)
		itr_cnt <= # simulation_delay (~itr_reg) ? 0:(itr_cnt + 1);

endmodule
