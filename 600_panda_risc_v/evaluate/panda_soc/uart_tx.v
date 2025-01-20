`timescale 1ns / 1ps
/********************************************************************
��ģ��: UART���Ϳ�����

����: 
UART���Ϳ�����
��ѡAXIS�ӿڻ�FIFO�ӿ�

ע�⣺
��

Э��:
AXIS SLAVE
FIFO READ
UART

����: �¼�ҫ
����: 2023/11/08
********************************************************************/


module uart_tx #(
    parameter integer clk_frequency = 200000000, // ʱ��Ƶ��
    parameter integer baud_rate = 115200, // ������
    parameter interface = "axis", // �ӿ�Э��(axis|fifo)
    parameter real simulation_delay = 1 // ������ʱ
)(
    input wire clk,
    input wire rst_n,
    
    output wire tx,
    
    input wire[7:0] tx_byte_data,
    input wire tx_byte_valid,
    output wire tx_byte_ready,
    
    input wire[7:0] tx_fifo_dout,
    input wire tx_fifo_empty,
    output wire tx_fifo_ren,
    
    output wire tx_idle,
    output wire tx_done
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
    
    localparam integer div_n = clk_frequency / baud_rate;
    
    /** ����fifo���˿� **/
    wire[7:0] tx_fifo_data_out;
    wire tx_fifo_empty_n;
    
    reg ready_reg;
    
    assign tx_byte_ready = ready_reg;
    assign tx_fifo_data_out = (interface == "axis") ? tx_byte_data:tx_fifo_dout;
    assign tx_fifo_empty_n = (interface == "axis") ? tx_byte_valid:(~tx_fifo_empty);
    
    assign tx_fifo_ren = ready_reg;
    
    /** ��Ƶ������ **/
    reg[clogb2(div_n-1):0] cnt;
    reg cnt_last_flag;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
        begin
            cnt <= 0;
            cnt_last_flag <= 1'b0;
        end
        else
        begin
            # simulation_delay;
            
            if(cnt_last_flag)
                cnt <= 0;
            else
                cnt <= cnt + 1;
            
            cnt_last_flag <= cnt == div_n - 2;
        end
    end
    
    /** ���ݷ���״̬�� **/
    localparam status_idle = 2'b00; // ״̬:����
    localparam status_start = 2'b01; // ״̬:��ʼλ
    localparam status_data = 2'b10; // ״̬:����λ
    localparam status_stop = 2'b11; // ״̬:ֹͣλ
    
    reg[1:0] now_status; // ��ǰ״̬
    reg[7:0] now_byte; // �������ֽ�
    reg tx_reg; // UART��tx��
    reg[7:0] now_byte_i; // ��ǰ�����ֽڵ�λ���(��һ��)
    reg byte_loaded; // �Ѽ��ش������ֽ�(��־)
    reg tx_idle_reg; // UART���������Ϳ���(��־)
    reg tx_done_reg; // UART�������������(��־)
    
    assign tx = tx_reg;
    assign tx_idle = tx_idle_reg;
    assign tx_done = tx_done_reg;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
        begin
            now_status <= status_idle;
            tx_reg <= 1'b1;
            now_byte_i <= 8'd1;
            byte_loaded <= 1'b0;
            ready_reg <= 1'b0;
            tx_idle_reg <= 1'b1;
            tx_done_reg <= 1'b0;
        end
        else
        begin
            # simulation_delay;
        
            ready_reg <= 1'b0;
            tx_done_reg <= 1'b0;
            
            case(now_status)
                status_idle: // ״̬:����
                begin
                    if(byte_loaded)
                        now_status <= status_start;
                    
                    byte_loaded <= tx_fifo_empty_n & ready_reg;
                    tx_reg <= 1'b1;
                    ready_reg <= (~byte_loaded) & (~(tx_fifo_empty_n & ready_reg));
                    tx_idle_reg <= ~(byte_loaded | tx_fifo_empty_n); // ֱ���ж�~tx_fifo_empty_nҲ����???
                end
                status_start: // ״̬:��ʼλ
                begin
                    if(cnt_last_flag)
                    begin
                        now_status <= status_data;
                        tx_reg <= 1'b0; // �����½��� -> ��ʼλ
                    end
                    
                    byte_loaded <= 1'b0;
                    tx_idle_reg <= 1'b0;
                end
                status_data: // ״̬:����λ
                begin
                    if(cnt_last_flag)
                    begin
                        if(now_byte_i[7])
                            now_status <= status_stop;
                        
                        now_byte_i <= {now_byte_i[6:0], now_byte_i[7]}; // �Ե�ǰ�����ֽڵ�λ���(��һ��)��ѭ������
                        tx_reg <= now_byte[0]; // ������һ����λ
                    end
                    
                    byte_loaded <= 1'b0;
                    tx_idle_reg <= 1'b0;
                end
                status_stop: // ״̬:ֹͣλ
                begin
                    if(cnt_last_flag)
                    begin
                        now_status <= status_idle;
                        tx_reg <= 1'b1; // ����ֹͣλ
                        tx_done_reg <= 1'b1;
                    end
                    
                    byte_loaded <= 1'b0;
                    tx_idle_reg <= 1'b0;
                end
                default:
                begin
                    now_status <= status_idle;
                    tx_reg <= 1'b1;
                    now_byte_i <= 8'd1;
                    byte_loaded <= 1'b0;
                    tx_idle_reg <= 1'b1;
                end
            endcase
        end
    end
    
    // �������ֽ�
    always @(posedge clk)
    begin
        # simulation_delay;
        
        if((now_status == status_idle) &
            ((interface == "axis") ? (tx_fifo_empty_n & ready_reg):byte_loaded)) // ����
            now_byte <= tx_fifo_data_out;
        else if((now_status == status_data) & cnt_last_flag) // ����
            now_byte <= {1'bx, now_byte[7:1]};
    end

endmodule
