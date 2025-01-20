`timescale 1ns / 1ps
/********************************************************************
��ģ��: ����APBЭ���UART������

����: 
APB-UART������
֧��UART����/�����ж�

�Ĵ���->
    ƫ����  |    ����                     |   ��д����    |        ��ע
    0x00    0:����fifo�Ƿ���                    R
            1:����fifoдʹ��                    W         ����fifoдʹ��ȡ������
            9~2:����fifoд����                  W
            10:����fifo�Ƿ��                   R
            11:����fifo��ʹ��                   W         ����fifo��ʹ��ȡ������
            19~12:����fifo������                R
    0x04    0:UARTȫ���ж�ʹ��                  W
            1:UART���ʹﵽ�涨�ֽ����ж�ʹ��     W
            2:UART����IDLE�ж�ʹ��              W
            3:UART���մﵽ�涨�ֽ����ж�ʹ��     W
            4:UART����IDLE�ж�ʹ��              W
            5:UART����FIFO����ж�ʹ��          W
            16:UART�жϱ�־                    RWC      �����жϷ�����������жϱ�־
            21~17:UART�ж�״̬                  R
    0x08    15~0:UART�����ж��ֽ�����ֵ         W               ע��Ҫ��1
            31~16:UART�����ж�IDLE��������ֵ    W               ע��Ҫ��2
    0x0C    15~0:UART�����ж��ֽ�����ֵ         W               ע��Ҫ��1
            31~16:UART�����ж�IDLE��������ֵ    W               ע��Ҫ��2

ע�⣺
��

Э��:
APB SLAVE
UART

����: �¼�ҫ
����: 2023/11/07
********************************************************************/


module apb_uart #(
    parameter integer clk_frequency_MHz = 50, // ʱ��Ƶ��
    parameter integer baud_rate = 115200, // ������
    parameter tx_rx_fifo_ram_type = "bram", // ���ͽ���fifo��RAM����(lutram|bram)
    parameter integer tx_fifo_depth = 1024, // ����fifo���(32|64|128|...|2048)
    parameter integer rx_fifo_depth = 1024, // ����fifo���(32|64|128|...|2048)
    parameter en_itr = "false", // �Ƿ�ʹ��UART�ж�
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
    
    // UART
    output wire uart_tx,
    input wire uart_rx,
    
    // �ж�
    output wire uart_itr
);

    /* UART���ͺͽ���fifo */
    // ����fifoд�˿�
    wire tx_fifo_wen;
    wire tx_fifo_full;
    wire[7:0] tx_fifo_din;
    // ����fifo���˿�
    wire tx_fifo_ren;
    wire tx_fifo_empty;
    wire[7:0] tx_fifo_dout;
    // ����fifoд�˿�
    wire rx_fifo_wen;
    wire rx_fifo_full;
    wire[7:0] rx_fifo_din;
    // ����fifo���˿�
    wire rx_fifo_ren;
    wire rx_fifo_empty;
    wire[7:0] rx_fifo_dout;
    
    // ����fifo
    ram_fifo_wrapper #(
        .fwft_mode("false"),
        .ram_type(tx_rx_fifo_ram_type),
        .en_bram_reg("false"),
        .fifo_depth(tx_fifo_depth),
        .fifo_data_width(8),
        .full_assert_polarity("high"),
        .empty_assert_polarity("high"),
        .almost_full_assert_polarity("no"),
        .almost_empty_assert_polarity("no"),
        .en_data_cnt("false"),
        .almost_full_th(),
        .almost_empty_th(),
        .simulation_delay(simulation_delay)
    )tx_fifo(
        .clk(clk),
        .rst_n(resetn),
        .fifo_wen(tx_fifo_wen),
        .fifo_din(tx_fifo_din),
        .fifo_full(tx_fifo_full),
        .fifo_ren(tx_fifo_ren),
        .fifo_dout(tx_fifo_dout),
        .fifo_empty(tx_fifo_empty)
    );
    
    // ����fifo
    ram_fifo_wrapper #(
        .fwft_mode("false"),
        .ram_type(tx_rx_fifo_ram_type),
        .en_bram_reg("false"),
        .fifo_depth(rx_fifo_depth),
        .fifo_data_width(8),
        .full_assert_polarity("high"),
        .empty_assert_polarity("high"),
        .almost_full_assert_polarity("no"),
        .almost_empty_assert_polarity("no"),
        .en_data_cnt("false"),
        .almost_full_th(),
        .almost_empty_th(),
        .simulation_delay(simulation_delay)
    )rx_fifo(
        .clk(clk),
        .rst_n(resetn),
        .fifo_wen(rx_fifo_wen),
        .fifo_din(rx_fifo_din),
        .fifo_full(rx_fifo_full),
        .fifo_ren(rx_fifo_ren),
        .fifo_dout(rx_fifo_dout),
        .fifo_empty(rx_fifo_empty)
    );
    
    /** UART�ж� **/
    wire uart_org_itr_pulse; // ԭʼ��UART�ж�����
    wire uart_org_itr_pulse_d; // �ӳ�1clk��ԭʼ��UART�ж�����
    wire uart_itr_flag; // UART���жϱ�־
    wire[4:0] uart_itr_mask; // UART���жϱ�־����(UART����FIFO����ж�ʹ��, UART����IDLE�ж�ʹ��, UART���մﵽ�涨�ֽ����ж�ʹ��, UART����IDLE�ж�ʹ��, UART���ʹﵽ�涨�ֽ����ж�ʹ��)
    wire[4:0] uart_itr_mask_d; // �ӳ�1clk��UART���жϱ�־����
    wire uart_global_itr_en; // UARTȫ���ж�ʹ��
    wire[4:0] uart_itr_en; // UART�ж�ʹ��(UART����FIFO����ж�ʹ��, UART����IDLE�ж�ʹ��, UART���մﵽ�涨�ֽ����ж�ʹ��, UART����IDLE�ж�ʹ��, UART���ʹﵽ�涨�ֽ����ж�ʹ��)
    
    wire[15:0] tx_bytes_n_th; // UART�����ж��ֽ�����ֵ
    wire[15:0] tx_bytes_n_th_sub1; // UART�����ж��ֽ�����ֵ-1
    wire tx_bytes_n_th_eq0; // UART�����ж��ֽ�����ֵ����0(��־)
    wire[15:0] tx_idle_n_th; // UART�����ж�IDLE��������ֵ
    wire[15:0] rx_bytes_n_th; // UART�����ж��ֽ�����ֵ
    wire[15:0] rx_bytes_n_th_sub1; // UART�����ж��ֽ�����ֵ-1
    wire rx_bytes_n_th_eq0; // UART�����ж��ֽ�����ֵ����0(��־)
    wire[15:0] rx_idle_n_th; // UART�����ж�IDLE��������ֵ
    
    wire rx_err; // �������(����)
    wire tx_idle; // ���Ϳ���(��־)
    wire rx_idle; // ���տ���(��־)
    wire tx_done; // �������(����)
    wire rx_done; // �������(����)
    wire rx_start; // ���տ�ʼ(����)
    
    generate
        if(en_itr == "true")
        begin
            reg[15:0] uart_tx_finished_bytes_n_cnt; // �ѷ����ֽ���(������)
            reg uart_tx_finished_bytes_n_cnt_eq_th_sub1; // �ѷ����ֽ��� == UART�����ж��ֽ�����ֵ-1(��־)
            reg uart_tx_finished_bytes_n_itr_pulse; // UART���ʹﵽ�涨�ֽ���(ԭʼ�ж�����)
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                begin
                    uart_tx_finished_bytes_n_cnt <= 16'd0;
                    uart_tx_finished_bytes_n_cnt_eq_th_sub1 <= 1'b0;
                end
                else if((~uart_itr_en[0]) | (~uart_global_itr_en))
                begin
                    # simulation_delay;
                    
                    uart_tx_finished_bytes_n_cnt <= 16'd0;
                    uart_tx_finished_bytes_n_cnt_eq_th_sub1 <= 1'b0;
                end
                else if(tx_done)
                begin
                    # simulation_delay;
                    
                    uart_tx_finished_bytes_n_cnt <= (uart_tx_finished_bytes_n_cnt_eq_th_sub1 | tx_bytes_n_th_eq0) ? 16'd0:(uart_tx_finished_bytes_n_cnt + 16'd1);
                    uart_tx_finished_bytes_n_cnt_eq_th_sub1 <= uart_tx_finished_bytes_n_cnt == tx_bytes_n_th_sub1;
                end
            end
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                    uart_tx_finished_bytes_n_itr_pulse <= 1'b0;
                else
                    # simulation_delay uart_tx_finished_bytes_n_itr_pulse <= (uart_itr_en[0] & uart_global_itr_en) &
                        (uart_tx_finished_bytes_n_cnt_eq_th_sub1 | tx_bytes_n_th_eq0) & tx_done;
            end
            
            reg is_waiting_for_uart_tx_done; // �Ƿ����ڵȴ�UART�����������
            reg[15:0] uart_tx_idle_cnt; // UART���Ϳ���������(������)
            reg uart_tx_idle_cnt_eq_th_sub1; // UART���Ϳ��������� == UART�����ж�IDLE��������ֵ
            reg uart_tx_idle_itr_pulse; // UART���Ϳ���(ԭʼ�ж�����)
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                    is_waiting_for_uart_tx_done <= 1'b1;
                else
                    # simulation_delay is_waiting_for_uart_tx_done <= is_waiting_for_uart_tx_done ? (~tx_done):(uart_tx_idle_cnt_eq_th_sub1 | (~tx_idle));
            end
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                begin
                    uart_tx_idle_cnt <= 16'd0;
                    uart_tx_idle_cnt_eq_th_sub1 <= 1'b0;
                end
                else if((~uart_itr_en[1]) | (~uart_global_itr_en))
                begin
                    # simulation_delay;
                    
                    uart_tx_idle_cnt <= 16'd0;
                    uart_tx_idle_cnt_eq_th_sub1 <= 1'b0;
                end
                else if(~is_waiting_for_uart_tx_done)
                begin
                    # simulation_delay;
                    
                    uart_tx_idle_cnt <= (uart_tx_idle_cnt_eq_th_sub1 | (~tx_idle)) ? 16'd0:(uart_tx_idle_cnt + 16'd1);
                    uart_tx_idle_cnt_eq_th_sub1 <= uart_tx_idle_cnt == tx_idle_n_th;
                end
            end
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                    uart_tx_idle_itr_pulse <= 1'b0;
                else
                    # simulation_delay uart_tx_idle_itr_pulse <= (~is_waiting_for_uart_tx_done) & uart_tx_idle_cnt_eq_th_sub1 & tx_idle;
            end
            
            reg[15:0] uart_rx_finished_bytes_n_cnt;
            reg uart_rx_finished_bytes_n_cnt_eq_th_sub1;
            reg uart_rx_finished_bytes_n_itr_pulse;
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                begin
                    uart_rx_finished_bytes_n_cnt <= 16'd0;
                    uart_rx_finished_bytes_n_cnt_eq_th_sub1 <= 1'b0;
                end
                else if((~uart_itr_en[2]) | (~uart_global_itr_en))
                begin
                    # simulation_delay;
                    
                    uart_rx_finished_bytes_n_cnt <= 16'd0;
                    uart_rx_finished_bytes_n_cnt_eq_th_sub1 <= 1'b0;
                end
                else if(rx_done)
                begin
                    # simulation_delay;
                    
                    uart_rx_finished_bytes_n_cnt <= (uart_rx_finished_bytes_n_cnt_eq_th_sub1 | rx_bytes_n_th_eq0) ? 16'd0:(uart_rx_finished_bytes_n_cnt + 16'd1);
                    uart_rx_finished_bytes_n_cnt_eq_th_sub1 <= uart_rx_finished_bytes_n_cnt == rx_bytes_n_th_sub1;
               end
            end
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                    uart_rx_finished_bytes_n_itr_pulse <= 1'b0;
                else
                    # simulation_delay uart_rx_finished_bytes_n_itr_pulse <= (uart_itr_en[2] & uart_global_itr_en) &
                        (uart_rx_finished_bytes_n_cnt_eq_th_sub1 | rx_bytes_n_th_eq0) & rx_done;
            end
            
            reg is_waiting_for_uart_rx_done;
            reg[15:0] uart_rx_idle_cnt;
            reg uart_rx_idle_cnt_eq_th_sub1;
            reg uart_rx_idle_itr_pulse;
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                    is_waiting_for_uart_rx_done <= 1'b1;
                else
                    # simulation_delay is_waiting_for_uart_rx_done <= is_waiting_for_uart_rx_done ? (~rx_done):(uart_rx_idle_cnt_eq_th_sub1 | rx_start);
            end
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                begin
                    uart_rx_idle_cnt <= 16'd0;
                    uart_rx_idle_cnt_eq_th_sub1 <= 1'b0;
                end
                else if((~uart_itr_en[3]) | (~uart_global_itr_en))
                begin
                    # simulation_delay;
                    
                    uart_rx_idle_cnt <= 16'd0;
                    uart_rx_idle_cnt_eq_th_sub1 <= 1'b0;
                end
                else if((~is_waiting_for_uart_rx_done) & (rx_start | rx_idle))
                begin
                    # simulation_delay;
                    
                    uart_rx_idle_cnt <= (uart_rx_idle_cnt_eq_th_sub1 | rx_start) ? 16'd0:(uart_rx_idle_cnt + 16'd1);
                    uart_rx_idle_cnt_eq_th_sub1 <= rx_start ? 1'b0:(uart_rx_idle_cnt == rx_idle_n_th);
                end
            end
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                    uart_rx_idle_itr_pulse <= 1'b0;
                else
                    # simulation_delay uart_rx_idle_itr_pulse <= (~is_waiting_for_uart_rx_done) & uart_rx_idle_cnt_eq_th_sub1 & rx_idle;
            end
            
            reg rx_err_d;
            reg uart_rx_err_itr_pulse;
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                    rx_err_d <= 1'b0;
                else
                    # simulation_delay rx_err_d <= rx_err;
            end
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                    uart_rx_err_itr_pulse <= 1'b0;
                else if((~uart_itr_en[4]) | (~uart_global_itr_en))
                    uart_rx_err_itr_pulse <= 1'b0;
                else
                    # simulation_delay uart_rx_err_itr_pulse <= rx_err & (~rx_err_d);
            end
            
            assign uart_org_itr_pulse = (uart_rx_err_itr_pulse | uart_rx_idle_itr_pulse |
                uart_rx_finished_bytes_n_itr_pulse | uart_tx_idle_itr_pulse | uart_tx_finished_bytes_n_itr_pulse)
                & (~uart_itr_flag);
            assign uart_itr_mask = {uart_rx_err_itr_pulse, uart_rx_idle_itr_pulse, uart_rx_finished_bytes_n_itr_pulse,
                uart_tx_idle_itr_pulse, uart_tx_finished_bytes_n_itr_pulse};
            
            reg uart_org_itr_pulse_delay;
            reg[4:0] uart_itr_mask_delay;
            
            assign {uart_org_itr_pulse_d, uart_itr_mask_d} = {uart_org_itr_pulse_delay, uart_itr_mask_delay};
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                begin
                    uart_org_itr_pulse_delay <= 1'b0;
                    uart_itr_mask_delay <= 5'd0;
                end
                else
                begin
                    # simulation_delay;
                    
                    uart_org_itr_pulse_delay <= uart_org_itr_pulse;
                    uart_itr_mask_delay <= uart_itr_mask;
                end
            end
            
            itr_generator #(
                .pulse_w(10),
                .simulation_delay(simulation_delay)
            )itr_generator_u(
                .clk(clk),
                .rst_n(resetn),
                .itr_org(uart_org_itr_pulse),
                .itr(uart_itr)
            );
        end
        else
        begin
            assign uart_itr = 1'b0;
            
            assign {uart_org_itr_pulse, uart_itr_mask} = 6'd0;
            assign {uart_org_itr_pulse_d, uart_itr_mask_d} = 6'd0;
        end
    endgenerate
    
    /** UART������ **/
    uart_rx_tx #(
        .clk_frequency_MHz(clk_frequency_MHz),
        .baud_rate(),
        .interface("fifo"),
        .simulation_delay(simulation_delay)
    )uart_ctrler(
        .clk(clk),
        .resetn(resetn),
        .rx(uart_rx),
        .tx(uart_tx),
        .m_axis_rx_byte_data(),
        .m_axis_rx_byte_valid(),
        .m_axis_rx_byte_ready(),
        .rx_buf_fifo_din(rx_fifo_din),
        .rx_buf_fifo_wen(rx_fifo_wen),
        .rx_buf_fifo_full(rx_fifo_full),
        .s_axis_tx_byte_data(),
        .s_axis_tx_byte_valid(),
        .s_axis_tx_byte_ready(),
        .tx_buf_fifo_dout(tx_fifo_dout),
        .tx_buf_fifo_empty(tx_fifo_empty),
        .tx_buf_fifo_almost_empty(),
        .tx_buf_fifo_ren(tx_fifo_ren),
        .rx_err(rx_err),
        .tx_idle(tx_idle),
        .rx_idle(rx_idle),
        .tx_done(tx_done),
        .rx_done(rx_done)
    );

    /*
    �Ĵ�����->
    ƫ����  |    ����                     |   ��д����    |        ��ע
    0x00    0:����fifo�Ƿ���                    R
            1:����fifoдʹ��                    W         ����fifoдʹ��ȡ������
            9~2:����fifoд����                  W
            10:����fifo�Ƿ��                   R
            11:����fifo��ʹ��                   W         ����fifo��ʹ��ȡ������
            19~12:����fifo������                R
    0x04    0:UARTȫ���ж�ʹ��                  W
            1:UART���ʹﵽ�涨�ֽ����ж�ʹ��     W
            2:UART����IDLE�ж�ʹ��              W
            3:UART���մﵽ�涨�ֽ����ж�ʹ��     W
            4:UART����IDLE�ж�ʹ��              W
            5:UART����FIFO����ж�ʹ��          W
            16:UART�жϱ�־                    RWC      �����жϷ�����������жϱ�־
            21~17:UART�ж�״̬                  R
    0x08    15~0:UART�����ж��ֽ�����ֵ         W               ע��Ҫ��1
            31~16:UART�����ж�IDLE��������ֵ    W               ע��Ҫ��2
    0x0A    15~0:UART�����ж��ֽ�����ֵ         W               ע��Ҫ��1
            31~16:UART�����ж�IDLE��������ֵ    W               ע��Ҫ��2
    */
    // ����/״̬�Ĵ���
    reg[31:0] uart_fifo_cs;
    reg[31:0] uart_itr_status_en;
    reg[31:0] uart_tx_itr_th;
    reg[31:0] uart_rx_itr_th;
    
    reg[15:0] tx_bytes_n_th_sub1_regs; // UART�����ж��ֽ�����ֵ-1
    reg[15:0] rx_bytes_n_th_sub1_regs; // UART�����ж��ֽ�����ֵ-1
    reg tx_bytes_n_th_eq0_reg; // UART�����ж��ֽ�����ֵ����0(��־)
    reg rx_bytes_n_th_eq0_reg; // UART�����ж��ֽ�����ֵ����0(��־)
    
    reg tx_fifo_wen_d;
    reg rx_fifo_ren_d;
    
    assign tx_fifo_wen = uart_fifo_cs[1] & (~tx_fifo_wen_d); // ����fifoдʹ��ȡ������
    assign tx_fifo_din = uart_fifo_cs[9:2];
    assign rx_fifo_ren = uart_fifo_cs[11] & (~rx_fifo_ren_d); // ����fifo��ʹ��ȡ������
    
    assign {uart_itr_en, uart_global_itr_en} = uart_itr_status_en[5:0];
    assign uart_itr_flag = uart_itr_status_en[16];
    assign {tx_idle_n_th, tx_bytes_n_th} = uart_tx_itr_th;
    assign {rx_idle_n_th, rx_bytes_n_th} = uart_rx_itr_th;
    
    assign {tx_bytes_n_th_sub1, rx_bytes_n_th_sub1} = {tx_bytes_n_th_sub1_regs, rx_bytes_n_th_sub1_regs};
    assign {tx_bytes_n_th_eq0, rx_bytes_n_th_eq0} = {tx_bytes_n_th_eq0_reg, rx_bytes_n_th_eq0_reg};
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            {tx_fifo_wen_d, rx_fifo_ren_d} <= 2'b00;
        else
            # simulation_delay {tx_fifo_wen_d, rx_fifo_ren_d} <= {uart_fifo_cs[1], uart_fifo_cs[11]};
    end
    
    // APBд�Ĵ���
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
        begin
            {uart_fifo_cs[11], uart_fifo_cs[9:1]} <= {1'b0, 9'd0};
            {uart_itr_status_en[16], uart_itr_status_en[5:0]} <= {1'b0, 6'd0};
            uart_tx_itr_th <= {16'd100, 16'd1};
            uart_rx_itr_th <= {16'd100, 16'd1};
        end
        else if(psel & pwrite & penable)
        begin
            # simulation_delay;
            
            case(paddr[3:2])
                2'd0: {uart_fifo_cs[11], uart_fifo_cs[9:1]} <= {pwdata[11], pwdata[9:1]}; // ����fifo��ʹ��, ����fifoд����, ����fifoдʹ��
                2'd1: {uart_itr_status_en[16], uart_itr_status_en[5:0]} <= {1'b0, pwdata[5:0]}; // UART���жϱ�־, UART�ж�ʹ��
                2'd2: uart_tx_itr_th <= pwdata; // UART�����ж�IDLE��������ֵ, UART�����ж��ֽ�����ֵ
                2'd3: uart_rx_itr_th <= pwdata; // UART�����ж�IDLE��������ֵ, UART�����ж��ֽ�����ֵ
            endcase
        end
        else
        begin
            # simulation_delay;
            
            if(~uart_itr_status_en[16])
                uart_itr_status_en[16] <= uart_org_itr_pulse; // UART���жϱ�־
        end
    end
    
    // UART�����ж��ֽ�����ֵ-1
    // UART�����ж��ֽ�����ֵ-1
    // UART�����ж��ֽ�����ֵ����0(��־)
    // UART�����ж��ֽ�����ֵ����0(��־)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
        begin
            tx_bytes_n_th_eq0_reg <= 1'b1;
            tx_bytes_n_th_sub1_regs <= 16'hffff;
            rx_bytes_n_th_eq0_reg <= 1'b1;
            rx_bytes_n_th_sub1_regs <= 16'hffff;
        end
        else if(psel & pwrite & penable)
        begin
            # simulation_delay;
            
            if(paddr[3:2] == 2)
            begin
                tx_bytes_n_th_eq0_reg <= pwdata[15:0] == 16'd0;
                tx_bytes_n_th_sub1_regs <= pwdata[15:0] - 16'd1;
            end
            
            if(paddr[3:2] == 3)
            begin
                rx_bytes_n_th_eq0_reg <= pwdata[15:0] == 16'd0;
                rx_bytes_n_th_sub1_regs <= pwdata[15:0] - 16'd1;
            end
        end
    end
    
    // ���жϱ�־����
    always @(posedge clk)
    begin
        if(uart_org_itr_pulse_d)
            # simulation_delay uart_itr_status_en[21:17] <= uart_itr_mask_d; // UART���жϱ�־
    end
    
    // APB���Ĵ���
    reg[31:0] prdata_out_regs;
    
	generate
		if(simulation_delay == 0)
		begin
			always @(posedge clk)
			begin
				if(psel & (~pwrite))
				begin
					# simulation_delay;
					
					case(paddr[3:2])
						2'd0:
						begin
							prdata_out_regs[0] <= tx_fifo_full; // ����fifo�Ƿ���
							prdata_out_regs[10] <= rx_fifo_empty; // ����fifo�Ƿ��
							prdata_out_regs[19:12] <= rx_fifo_dout; // ����fifo������
							{prdata_out_regs[31:20], prdata_out_regs[11], prdata_out_regs[9:1]} <= 22'dx;
						end
						2'd1:
						begin
							prdata_out_regs[21:16] <= uart_itr_status_en[21:16];
							{prdata_out_regs[31:22], prdata_out_regs[15:0]} <= 26'dx;
						end
						default: prdata_out_regs <= 32'dx;
					endcase
				end
			end
		end
		else
		begin
			always @(posedge clk)
			begin
				if(psel & (~pwrite))
				begin
					# simulation_delay;
					
					case(paddr[3:2])
						2'd0:
						begin
							prdata_out_regs[0] <= tx_fifo_full; // ����fifo�Ƿ���
							prdata_out_regs[10] <= rx_fifo_empty; // ����fifo�Ƿ��
							prdata_out_regs[19:12] <= rx_fifo_dout; // ����fifo������
							{prdata_out_regs[31:20], prdata_out_regs[11], prdata_out_regs[9:1]} <= 22'd0;
						end
						2'd1:
						begin
							prdata_out_regs[21:16] <= uart_itr_status_en[21:16];
							{prdata_out_regs[31:22], prdata_out_regs[15:0]} <= 26'd0;
						end
						default: prdata_out_regs <= 32'd0;
					endcase
				end
			end
		end
	endgenerate
    
    /** APB�ӻ��ӿ� **/
    assign pready_out = 1'b1;
    assign prdata_out = prdata_out_regs;
    assign pslverr_out = 1'b0;

endmodule
