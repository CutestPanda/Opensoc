`timescale 1ns / 1ps
/********************************************************************
��ģ��: UART���տ�����

����: 
����AXISЭ���UART���տ�����

ע�⣺
UART���տ������

Э��:
AXIS MASTER
UART

����: �¼�ҫ
����: 2023/11/08
********************************************************************/


module uart_rx #(
    parameter integer clk_frequency = 200000000, // ʱ��Ƶ��
    parameter integer baud_rate = 115200, // ������
    parameter real simulation_delay = 1 // ������ʱ
)(
    input wire clk,
    input wire rst_n,
    
    input wire rx,
    
    output wire[7:0] rx_byte_data,
    output wire rx_byte_valid,
    input wire rx_byte_ready,
    
    output wire rx_idle,
    output wire rx_done,
    output wire rx_start
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

    localparam integer clk_n_per_bit = clk_frequency / baud_rate; // ����ÿһλ���õ�ʱ�����ڸ���
    
    /** ��������������̬ **/
    reg rx_d;
    reg rx_d2;
    wire rx_stable;
    
    assign rx_stable = rx_d2;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            {rx_d2, rx_d} <= 2'b11;
        else
            # simulation_delay {rx_d2, rx_d} <= {rx_d, rx};
    end
    
    /** ����½��� **/
    reg rx_stable_d;
    reg rx_neg_edge_detected; // ��⵽�½���(����)
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rx_stable_d <= 1'b1;
        else
            # simulation_delay rx_stable_d <= rx_stable;
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rx_neg_edge_detected <= 1'b0;
        else
            # simulation_delay rx_neg_edge_detected <= (~rx_stable) & rx_stable_d;
    end
    
    /** ���ݽ���״̬�� **/
    localparam status_idle = 2'b00; // ״̬:����
    localparam status_start = 2'b01; // ״̬:��ʼλ
    localparam status_data = 2'b10; // ״̬:����λ
    localparam status_stop = 2'b11; // ״̬:ֹͣλ
    
    reg[1:0] now_status;
    
    reg[clogb2(clk_n_per_bit-1):0] cnt; // �����ʼ�����
    reg[2:0] now_bit_i; // ��ǰ�����ֽ�λ���
    reg[7:0] byte; // ��ǰ���յ��ֽ�
    reg byte_vld; // �����ֽ����(����)
    reg rx_idle_reg; // UART���������տ���(��־)
    
    reg cnt_eq_clk_n_per_bit_div2_sub1; // �����ʼ����� == UARTλʱ������ / 2 - 1(����)
    reg cnt_eq_clk_n_per_bit_sub1; // �����ʼ����� == UARTλʱ������ - 1(����)
    
    assign rx_byte_data = byte;
    assign rx_byte_valid = byte_vld;
    assign rx_idle = rx_idle_reg;
    assign rx_done = byte_vld;
    assign rx_start = rx_neg_edge_detected;
    
    // �����ʼ������ȽϽ��ָʾ
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
        begin
            cnt_eq_clk_n_per_bit_div2_sub1 <= 1'b0;
            cnt_eq_clk_n_per_bit_sub1 <= 1'b0;
        end
        else
        begin
            # simulation_delay;
            
            cnt_eq_clk_n_per_bit_div2_sub1 <= (cnt == clk_n_per_bit / 2 - 2);
            cnt_eq_clk_n_per_bit_sub1 <= (cnt == clk_n_per_bit - 2);
        end
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
        begin
            now_status <= status_idle;
            cnt <= 0;
            now_bit_i <= 3'b000;
            byte_vld <= 1'b0;
            rx_idle_reg <= 1'b1;
        end
        else
        begin
            # simulation_delay;
            
            byte_vld <= 1'b0;
            case(now_status)
                status_idle: // ״̬:����
                begin
                    rx_idle_reg <= rx_idle_reg | cnt_eq_clk_n_per_bit_div2_sub1; // Ϊ��������һ�δ����ֹͣλ, idle�ź�ֻ���ڲ����ʼ����� == UARTλʱ������ / 2 - 1ʱ��Ϊ��Ч
                    
                    if(rx_neg_edge_detected) // ��⵽��ʼλ
                    begin
                        now_status <= status_start;
                        cnt <= 0;
                    end
                    else
                    begin
                        now_status <= status_idle;
                        cnt <= cnt + 1;
                    end
                end
                status_start: // ״̬:��ʼλ
                begin
                    rx_idle_reg <= 1'b0;
                    
                    if(cnt_eq_clk_n_per_bit_div2_sub1) // ���뵽��ʼλ�����ټ�������
                    begin
                        now_status <= status_data;
                        cnt <= 0;
                    end
                    else
                    begin
                        now_status <= status_start;
                        cnt <= cnt + 1;
                    end
                end
                status_data: // ״̬:����λ
                begin
                    rx_idle_reg <= 1'b0;
                    
                    if(cnt_eq_clk_n_per_bit_sub1) // ����UART����λ
                    begin
                        cnt <= 0;
                        now_bit_i <= now_bit_i + 3'b001;
                        
                        if(now_bit_i == 3'b111)
                            now_status <= status_stop;
                        else
                            now_status <= status_data;
                    end
                    else
                    begin
                        now_status <= status_data;
                        cnt <= cnt + 1;
                    end
                end
                status_stop: // ״̬:ֹͣλ
                begin
                    rx_idle_reg <= 1'b0;
                    
                    if(cnt_eq_clk_n_per_bit_sub1) // ��ʱ���뵽ֹͣλ������
                    begin
                        now_status <= status_idle;
                        cnt <= 0;
                        byte_vld <= 1'b1;
                    end
                    else
                    begin
                        now_status <= status_stop;
                        cnt <= cnt + 1;
                    end
                end
                default:
                begin
                    now_status <= status_idle;
                    cnt <= 0;
                    now_bit_i <= 3'b000;
                    rx_idle_reg <= 1'b1;
                end
            endcase
        end
    end
    
    // ��ǰ���յ��ֽ�
    always @(posedge clk)
    begin
        # simulation_delay;
        
        if(now_status == status_data)
        begin
            case(now_bit_i)
                3'b000: byte[0] <= rx_stable;
                3'b001: byte[1] <= rx_stable;
                3'b010: byte[2] <= rx_stable;
                3'b011: byte[3] <= rx_stable;
                3'b100: byte[4] <= rx_stable;
                3'b101: byte[5] <= rx_stable;
                3'b110: byte[6] <= rx_stable;
                3'b111: byte[7] <= rx_stable;
            endcase
        end
    end

endmodule
