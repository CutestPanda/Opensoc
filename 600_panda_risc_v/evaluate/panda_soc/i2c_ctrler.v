`timescale 1ns / 1ps
/********************************************************************
��ģ��: I2C������

����: 
ͨ��IC2������
֧��7λ/10λ��ַ

����fifo���ݰ���ʽ��
    д���� -> last0 xxxx_xxx0 ��ַ�׶�
             [last0 xxxx_xxxx ��ַ�׶�(��10λ��ַʱ��Ҫ)]
             last0 xxxx_xxxx ���ݽ׶�
             ...
             last1 xxxx_xxxx ���ݽ׶�
    ������ -> last0 xxxx_xxx1 ��ַ�׶�
             [last0 xxxx_xxxx ��ַ�׶�(��10λ��ַʱ��Ҫ)]
             last1 8λ����ȡ�ֽ���

ע�⣺
ÿ��I2C���ݰ����ܳ���15�ֽ�

Э��:
I2C MASTER

����: �¼�ҫ
����: 2024/06/14
********************************************************************/


module i2c_ctrler #(
    parameter integer addr_bits_n = 7, // ��ַλ��(7|10)
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire resetn,
    
    // I2Cʱ�ӷ�Ƶϵ��
    // ��Ƶ�� = (��Ƶϵ�� + 1) * 2
    // ����:��Ƶϵ��>=1!
    input wire[7:0] i2c_scl_div_rate,
    
    // ����fifo���˿�
    output wire tx_fifo_ren,
    input wire tx_fifo_empty,
    input wire[7:0] tx_fifo_dout,
    input wire tx_fifo_dout_last,
    // ����fifoд�˿�
    output wire rx_fifo_wen,
    input wire rx_fifo_full,
    output wire[7:0] rx_fifo_din,
    
    // I2C�������ָʾ
    output wire i2c_tx_done,
    output wire[3:0] i2c_tx_bytes_n,
    // I2C�������ָʾ
    output wire i2c_rx_done,
    output wire[3:0] i2c_rx_bytes_n,
    // I2C�ӻ���Ӧ����
    output wire i2c_slave_resp_err,
    // I2C�������
    output wire i2c_rx_overflow,
    
    // I2C�����ӿ�
    // scl
    output wire scl_t, // 1'b1Ϊ����, 1'b0Ϊ���
    input wire scl_i,
    output wire scl_o,
    // sda
    output wire sda_t, // 1'b1Ϊ����, 1'b0Ϊ���
    input wire sda_i,
    output wire sda_o
);
    
    /** ���� **/
    // ״̬����
    localparam I2C_CTRLER_STS_IDLE = 2'b00; // ״̬:����
    localparam I2C_CTRLER_STS_LOAD = 2'b01; // ״̬:��������
    localparam I2C_CTRLER_STS_RX_TX = 2'b10; // ״̬:�շ�
    localparam I2C_CTRLER_STS_DONE = 2'b11; // ״̬:���
    
    /** ���̿��� **/
    reg[1:0] i2c_ctrler_sts; // ������״̬
    reg[2:0] tx_fifo_ren_onehot; // ����fifo��ʹ��(������)
    reg[2:0] i2c_if_stage_onehot; // i2c���ӿڿ������׶�(������)
    wire i2c_if_ctrler_done; // i2c���ӿڿ��������(ָʾ)
    reg is_rd_trans; // �Ƿ������
    reg last_loaded; // �����last�ź�
    wire is_addr_stage; // �Ƿ��ڵ�ַ�׶�
    reg[3:0] bytes_n_to_rx; // �������ֽ���
    reg trans_first; // �շ���1���ֽ�(��־)
    reg[3:0] trans_bytes_n; // ���շ����ֽ���
    reg[3:0] trans_bytes_n_add1; // ���շ����ֽ��� + 1
    
    assign tx_fifo_ren = tx_fifo_ren_onehot[1];
    
    // ������״̬
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_ctrler_sts <= I2C_CTRLER_STS_IDLE;
        else
        begin
            # simulation_delay;
            
            case(i2c_ctrler_sts)
                I2C_CTRLER_STS_IDLE: // ״̬:����
                    if(~tx_fifo_empty)
                        i2c_ctrler_sts <= I2C_CTRLER_STS_LOAD; // -> ״̬:��������
                I2C_CTRLER_STS_LOAD: // ״̬:��������
                    if(tx_fifo_ren_onehot[2])
                        i2c_ctrler_sts <= I2C_CTRLER_STS_RX_TX; // -> ״̬:�շ�
                I2C_CTRLER_STS_RX_TX: // ״̬:�շ�
                    if(i2c_if_stage_onehot[2] & i2c_if_ctrler_done)
                        i2c_ctrler_sts <= I2C_CTRLER_STS_DONE; // -> ״̬:���
                I2C_CTRLER_STS_DONE:
                begin
                    if(is_rd_trans)
                    begin
                        if(last_loaded)
                            i2c_ctrler_sts <= (trans_bytes_n == bytes_n_to_rx) ? I2C_CTRLER_STS_IDLE: // -> ״̬:����
                                                                                 I2C_CTRLER_STS_RX_TX; // -> ״̬:�շ�
                        else
                            i2c_ctrler_sts <= I2C_CTRLER_STS_LOAD; // -> ״̬:��������
                    end
                    else
                        i2c_ctrler_sts <= last_loaded ? I2C_CTRLER_STS_IDLE: // -> ״̬:����
                                                        I2C_CTRLER_STS_LOAD; // -> ״̬:��������
                end
                default:
                    i2c_ctrler_sts <= I2C_CTRLER_STS_IDLE;
            endcase
        end
    end
    
    // ����fifo��ʹ��(������)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            tx_fifo_ren_onehot <= 3'b001;
        else if((tx_fifo_ren_onehot[0] & (i2c_ctrler_sts == I2C_CTRLER_STS_LOAD)) | (tx_fifo_ren_onehot[1] & (~tx_fifo_empty)) | tx_fifo_ren_onehot[2])
            # simulation_delay tx_fifo_ren_onehot <= {tx_fifo_ren_onehot[1:0], tx_fifo_ren_onehot[2]};
    end
    
    // i2c���ӿڿ������׶�(������)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_if_stage_onehot <= 3'b001;
        else if((i2c_if_stage_onehot[0] & (i2c_ctrler_sts == I2C_CTRLER_STS_RX_TX)) | i2c_if_stage_onehot[1] | (i2c_if_stage_onehot[2] & i2c_if_ctrler_done))
            # simulation_delay i2c_if_stage_onehot <= {i2c_if_stage_onehot[1:0], i2c_if_stage_onehot[2]};
    end
    
    // �շ���1���ֽ�(��־)
    always @(posedge clk)
    begin
        if(i2c_ctrler_sts == I2C_CTRLER_STS_IDLE)
            # simulation_delay trans_first <= 1'b1;
        else if(trans_first)
            # simulation_delay trans_first <= ~(i2c_if_stage_onehot[2] & i2c_if_ctrler_done);
    end
    
    // ���շ����ֽ���
    always @(posedge clk)
    begin
        if(i2c_ctrler_sts == I2C_CTRLER_STS_IDLE)
            # simulation_delay trans_bytes_n <= 4'd0;
        else if(i2c_if_stage_onehot[2] & i2c_if_ctrler_done & (~is_addr_stage))
            # simulation_delay trans_bytes_n <= trans_bytes_n + 4'd1;
    end
    // ���շ����ֽ��� + 1
    always @(posedge clk)
    begin
        if(i2c_ctrler_sts == I2C_CTRLER_STS_IDLE)
            # simulation_delay trans_bytes_n_add1 <= 4'd1;
        else if(i2c_if_stage_onehot[2] & i2c_if_ctrler_done & (~is_addr_stage))
            # simulation_delay trans_bytes_n_add1 <= trans_bytes_n_add1 + 4'd1;
    end
    
    /** �������� **/
    reg first_load; // ��I2C���ݰ���1����������(��־)
    reg[7:0] data_loaded; // ���������
    wire resp_dire; // ��Ӧ����(1'b0 -> ����������Ӧ, 1'b1 -> ����������Ӧ)
    
    assign resp_dire = is_addr_stage ? 1'b0:is_rd_trans;
    
    // ��I2C���ݰ���1����������(��־)
    always @(posedge clk)
    begin
        if(i2c_ctrler_sts == I2C_CTRLER_STS_IDLE)
            # simulation_delay first_load <= 1'b1;
        else if(first_load)
            # simulation_delay first_load <= ~tx_fifo_ren_onehot[2];
    end
    
    // ���������
    // �����last�ź�
    always @(posedge clk)
    begin
        if(tx_fifo_ren_onehot[2])
            # simulation_delay {last_loaded, data_loaded} <= {tx_fifo_dout_last, tx_fifo_dout};
    end
    
    // �Ƿ������
    always @(posedge clk)
    begin
        if(tx_fifo_ren_onehot[2] & first_load)
            # simulation_delay is_rd_trans <= tx_fifo_dout[0];
    end
    
    // �Ƿ��ڵ�ַ�׶�
    generate
        if(addr_bits_n == 7) // 7λ��ַ
        begin
            reg[1:0] is_addr_stage_onehot;
            
            assign is_addr_stage = is_addr_stage_onehot[0];
            
            always @(posedge clk)
            begin
                if(i2c_ctrler_sts == I2C_CTRLER_STS_IDLE)
                    # simulation_delay is_addr_stage_onehot <= 2'b01;
                else if((~is_addr_stage_onehot[1]) & (i2c_if_stage_onehot[2] & i2c_if_ctrler_done))
                    # simulation_delay is_addr_stage_onehot <= {is_addr_stage_onehot[0], is_addr_stage_onehot[1]};
            end
        end
        else // 10λ��ַ
        begin
            reg[2:0] is_addr_stage_onehot;
            
            assign is_addr_stage = ~is_addr_stage_onehot[2];
            
            always @(posedge clk)
            begin
                if(i2c_ctrler_sts == I2C_CTRLER_STS_IDLE)
                    # simulation_delay is_addr_stage_onehot <= 3'b001;
                else if((~is_addr_stage_onehot[2]) & (i2c_if_stage_onehot[2] & i2c_if_ctrler_done))
                    # simulation_delay is_addr_stage_onehot <= {is_addr_stage_onehot[1:0], is_addr_stage_onehot[2]};
            end
        end
    endgenerate
    
    // �������ֽ���
    always @(posedge clk)
    begin
        if(tx_fifo_ren_onehot[2] & tx_fifo_dout_last & is_rd_trans)
            # simulation_delay bytes_n_to_rx <= tx_fifo_dout[3:0];
    end
    
    /** I2C���ӿ� **/
    wire[7:0] byte_recv; // ���յ�����
    reg i2c_rx_overflow_reg; // I2C�������
    wire i2c_if_ctrler_start; // i2c���ӿڿ�������ʼ(ָʾ)
    reg[1:0] i2c_if_ctrler_mode; // i2c���ӿڿ���������ģʽ(2'b00 -> ����ʼλ, 2'b01 -> ������λ, 2'b10 -> ����, 2'b11 -> Ԥ��)
    wire i2c_if_ctrler_dire; // i2c���ӿڿ��������䷽��(1'b0 -> ����, 1'b1 -> ����)
    
    assign rx_fifo_wen = i2c_if_ctrler_done & resp_dire;
    assign rx_fifo_din = byte_recv;
    
    assign i2c_rx_overflow = i2c_rx_overflow_reg;
    
    assign i2c_if_ctrler_start = i2c_if_stage_onehot[1];
    assign i2c_if_ctrler_dire = resp_dire;
    
    // I2C�������
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_rx_overflow_reg <= 1'b0;
        else
            # simulation_delay i2c_rx_overflow_reg <= rx_fifo_wen & rx_fifo_full;
    end
    
    // i2c���ӿڿ���������ģʽ
    always @(posedge clk)
    begin
        if(trans_first)
            # simulation_delay i2c_if_ctrler_mode <= 2'b00;
        else if(is_rd_trans ? (last_loaded & (trans_bytes_n_add1 == bytes_n_to_rx)):last_loaded)
            # simulation_delay i2c_if_ctrler_mode <= 2'b01;
        else
            # simulation_delay i2c_if_ctrler_mode <= 2'b10;
    end
    
    // i2c���ӿڿ�����
    i2c_master_if #(
        .simulation_delay(simulation_delay)
    )i2c_master_if_u(
        .clk(clk),
        .resetn(resetn),
        
        .i2c_scl_div_rate(i2c_scl_div_rate),
        
        .ctrler_start(i2c_if_ctrler_start),
        .ctrler_idle(),
        .ctrler_done(i2c_if_ctrler_done),
        
        .mode(i2c_if_ctrler_mode),
        .direction(i2c_if_ctrler_dire),
        .byte_to_send(data_loaded),
        .byte_recv(byte_recv),
        
        .i2c_slave_resp_err(i2c_slave_resp_err),
        
        .scl_t(scl_t),
        .scl_i(scl_i),
        .scl_o(scl_o),
        .sda_t(sda_t),
        .sda_i(sda_i),
        .sda_o(sda_o)
    );
    
    /** I2C�շ����ָʾ **/
    reg i2c_tx_done_reg; // I2C�������ָʾ
    reg i2c_rx_done_reg; // I2C�������ָʾ
    
    assign i2c_tx_done = i2c_tx_done_reg;
    assign i2c_tx_bytes_n = trans_bytes_n;
    assign i2c_rx_done = i2c_rx_done_reg;
    assign i2c_rx_bytes_n = trans_bytes_n;
    
    // I2C�������ָʾ
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_tx_done_reg <= 1'b0;
        else
            # simulation_delay i2c_tx_done_reg <= (i2c_ctrler_sts == I2C_CTRLER_STS_DONE) & (~is_rd_trans) & last_loaded;
    end
    // I2C�������ָʾ
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_rx_done_reg <= 1'b0;
        else
            # simulation_delay i2c_rx_done_reg <= (i2c_ctrler_sts == I2C_CTRLER_STS_DONE) & is_rd_trans & last_loaded & (trans_bytes_n == bytes_n_to_rx);
    end
    
endmodule
