`timescale 1ns / 1ps
/********************************************************************
��ģ��: I2C���ӿ�

����: 
���ݴ��䷽��ʹ���������������I2C���ӿ�

ע�⣺
��

Э��:
I2C MASTER

����: �¼�ҫ
����: 2024/06/15
********************************************************************/


module i2c_master_if #(
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire resetn,
    
    // I2Cʱ�ӷ�Ƶϵ��
    // ��Ƶ�� = (��Ƶϵ�� + 1) * 2
    // ����:��Ƶϵ��>=1!
    input wire[7:0] i2c_scl_div_rate,
    
    // ���̿���
    input wire ctrler_start,
    output wire ctrler_idle,
    output wire ctrler_done,
    
    // �շ�����
    input wire[1:0] mode, // ����ģʽ(2'b00 -> ����ʼλ, 2'b01 -> ������λ, 2'b10 -> ����, 2'b11 -> Ԥ��)
    input wire direction, // ���䷽��(1'b0 -> ����, 1'b1 -> ����)
    input wire[7:0] byte_to_send, // ����������
    output wire[7:0] byte_recv, // ���յ�������
    
    // I2C�ӻ���Ӧ����
    output wire i2c_slave_resp_err,
    
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
    // ģʽ����
    localparam MODE_WITH_START = 2'b00; // ģʽ:����ʼλ
    localparam MODE_WITH_STOP = 2'b01; // ģʽ:������λ
    localparam MODE_NORMAL = 2'b10; // ģʽ:����
    // ������״̬����
    localparam CTRLER_STS_IDLE = 3'b000; // ״̬:����
    localparam CTRLER_STS_START = 3'b001; // ״̬:��ʼλ
    localparam CTRLER_STS_DATA = 3'b010; // ״̬:����λ
    localparam CTRLER_STS_RESP = 3'b011; // ״̬:��Ӧ
    localparam CTRLER_STS_STOP = 3'b100; // ״̬:ֹͣλ
    localparam CTRLER_STS_DONE = 3'b101; // ״̬:���
    
    /** ����Ŀ�����Ϣ **/
    reg[1:0] mode_latched; // ����Ĵ���ģʽ(2'b00 -> ����ʼλ, 2'b01 -> ������λ, 2'b10 -> ����, 2'b11 -> Ԥ��)
    reg direction_latched; // ����Ĵ��䷽��(1'b0 -> ����, 1'b1 -> ����)
    
    // ����Ĵ���ģʽ
    always @(posedge clk)
    begin
        if(ctrler_idle & ctrler_start)
            # simulation_delay mode_latched <= mode;
    end
    // ����Ĵ��䷽��
    always @(posedge clk)
    begin
        if(ctrler_idle & ctrler_start)
            # simulation_delay direction_latched <= direction;
    end
    
    /** ���̿��� **/
    reg[2:0] i2c_if_ctrler_sts; // ������״̬
    wire rx_tx_byte_done; // �ֽ��շ����(ָʾ)
    wire resp_disposed; // ��Ӧ�������(ָʾ)
    wire stop_disposed; // ֹͣλ�������(ָʾ)
    reg ctrler_idle_reg; // ����������(��־)
    reg ctrler_done_reg; // ���������(ָʾ)
    
    assign ctrler_idle = ctrler_idle_reg;
    assign ctrler_done = ctrler_done_reg;
    
    // ������״̬
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_if_ctrler_sts <= CTRLER_STS_IDLE;
        else
        begin
            # simulation_delay;
            
            case(i2c_if_ctrler_sts)
                CTRLER_STS_IDLE: // ״̬:����
                    if(ctrler_start)
                        i2c_if_ctrler_sts <= CTRLER_STS_START; // -> ״̬:��ʼλ
                CTRLER_STS_START: // ״̬:��ʼλ
                    i2c_if_ctrler_sts <= CTRLER_STS_DATA; // -> ״̬:����λ
                CTRLER_STS_DATA: // ״̬:����λ
                    if(rx_tx_byte_done)
                        i2c_if_ctrler_sts <= CTRLER_STS_RESP; // -> ״̬:��Ӧ
                CTRLER_STS_RESP: // ״̬:��Ӧ
                    if(resp_disposed)
                        i2c_if_ctrler_sts <= CTRLER_STS_STOP; // -> ״̬:ֹͣλ
                CTRLER_STS_STOP: // ״̬:ֹͣλ
                    if((mode_latched == MODE_WITH_STOP) ? stop_disposed:1'b1)
                        i2c_if_ctrler_sts <= CTRLER_STS_DONE; // -> ״̬:���
                CTRLER_STS_DONE: // ״̬:���
                    i2c_if_ctrler_sts <= CTRLER_STS_IDLE; // -> ״̬:����
                default:
                    i2c_if_ctrler_sts <= CTRLER_STS_IDLE;
            endcase
        end
    end
    
    // ����������(��־)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            ctrler_idle_reg <= 1'b1;
        else
            # simulation_delay ctrler_idle_reg <= ctrler_idle_reg ? (~ctrler_start):ctrler_done_reg;
    end
    // ���������(ָʾ)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            ctrler_done_reg <= 1'b0;
        else
            # simulation_delay ctrler_done_reg <= (i2c_if_ctrler_sts == CTRLER_STS_STOP) & ((mode_latched == MODE_WITH_STOP) ? stop_disposed:1'b1);
    end
    
    /** �����շ����� **/
    reg shift_send_bit; // ������������λ��־
    reg sample_recv_bit; // ���������ݲ�����־
    reg[7:0] send_byte_buffer; // ���������ݻ�����
    reg[7:0] recv_byte_buffer; // ���������ݻ�����
    reg[7:0] rx_tx_stage_onehot; // �շ����̶�����
    
    assign byte_recv = recv_byte_buffer;
    
    assign rx_tx_byte_done = rx_tx_stage_onehot[7] & sample_recv_bit;
    
    // ���������ݻ�����
    always @(posedge clk)
    begin
        if(ctrler_idle & ctrler_start)
            # simulation_delay send_byte_buffer <= byte_to_send;
        else if(shift_send_bit)
            # simulation_delay send_byte_buffer <= {send_byte_buffer[6:0], 1'bx};
    end
    // ���������ݻ�����
    always @(posedge clk)
    begin
        if(sample_recv_bit)
            # simulation_delay recv_byte_buffer <= {recv_byte_buffer[6:0], sda_i};
    end
    
    // �շ����̶�����
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            rx_tx_stage_onehot <= 8'b0000_0001;
        else if(sample_recv_bit)
            # simulation_delay rx_tx_stage_onehot <= {rx_tx_stage_onehot[6:0], rx_tx_stage_onehot[7]};
    end
    
    /** ��Ӧ���� **/
	reg[7:0] resp_div_cnt; // ��Ӧʱscl��Ƶ������
    reg[5:0] resp_stage_onehot; // ��Ӧ���̶�����(6'b000001 -> SCL��, 6'b000010 -> SCL��, 6'b000100 -> SCL��, 6'b001000 -> SCL���������Ӧ, 6'b010000 -> SCL��, 6'b100000 -> SCL��)
    reg i2c_slave_resp_err_reg; // I2C�ӻ���Ӧ����
    
    assign i2c_slave_resp_err = i2c_slave_resp_err_reg;
    
    assign resp_disposed = resp_stage_onehot[5];
	
	// ��Ӧʱscl��Ƶ������
	always @(posedge clk)
	begin
		if((i2c_if_ctrler_sts == CTRLER_STS_RESP) & (resp_stage_onehot[0] | resp_stage_onehot[2]))
            # simulation_delay resp_div_cnt <= resp_div_cnt + 8'd1;
		else
			# simulation_delay resp_div_cnt <= 8'd0;
	end
    
    // ��Ӧ���̶�����
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            resp_stage_onehot <= 6'b00_00_01;
        else if((i2c_if_ctrler_sts == CTRLER_STS_RESP) & 
			((resp_stage_onehot[0] | resp_stage_onehot[2]) ? (resp_div_cnt == i2c_scl_div_rate):1'b1))
            # simulation_delay resp_stage_onehot <= {resp_stage_onehot[4:0], resp_stage_onehot[5]};
    end
    
    // I2C�ӻ���Ӧ����
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_slave_resp_err_reg <= 1'b0;
        else
            # simulation_delay i2c_slave_resp_err_reg <= (i2c_if_ctrler_sts == CTRLER_STS_RESP) & resp_stage_onehot[4] & sda_i;
    end
    
    /** ֹͣλ���� **/
	reg[7:0] stop_div_cnt; // ֹͣλscl��Ƶ������
    reg[5:0] stop_stage_onehot; // ֹͣλ���̶�����(6'b000001 -> SCL��, 6'b000010 -> SCL��, 6'b000100 -> SCL��, 6'b001000 -> SCL����SDA��, 6'b010000 -> SCL��, 6'b100000 -> SCL����SDA��)
    
    assign stop_disposed = stop_stage_onehot[5];
    
	// ֹͣλscl��Ƶ������
	always @(posedge clk)
	begin
		if((i2c_if_ctrler_sts == CTRLER_STS_STOP) & (mode_latched == MODE_WITH_STOP) & 
			(stop_stage_onehot[0] | stop_stage_onehot[2]))
            # simulation_delay stop_div_cnt <= stop_div_cnt + 8'd1;
		else
			# simulation_delay stop_div_cnt <= 8'd0;
	end
	
    // ֹͣλ���̶�����
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            stop_stage_onehot <= 6'b00_00_01;
        else if((i2c_if_ctrler_sts == CTRLER_STS_STOP) & (mode_latched == MODE_WITH_STOP) & 
			((stop_stage_onehot[0] | stop_stage_onehot[2]) ? (stop_div_cnt == i2c_scl_div_rate):1'b1))
            # simulation_delay stop_stage_onehot <= {stop_stage_onehot[4:0], stop_stage_onehot[5]};
    end
    
    /** I2Cʱ�ӷ�Ƶ **/
    reg[7:0] i2c_scl_div_cnt; // I2Cʱ�ӷ�Ƶ������
    wire i2c_scl_div_cnt_rst; // I2Cʱ�ӷ�Ƶ����������ָʾ
    
    assign i2c_scl_div_cnt_rst = i2c_scl_div_cnt == i2c_scl_div_rate;
    
    // ������������λ��־
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            shift_send_bit <= 1'b0;
        else
            # simulation_delay shift_send_bit <= scl_o & (i2c_if_ctrler_sts == CTRLER_STS_DATA) & i2c_scl_div_cnt_rst;
    end
    // ���������ݲ�����־
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sample_recv_bit <= 1'b0;
        else
            # simulation_delay sample_recv_bit <= (~scl_o) & (i2c_if_ctrler_sts == CTRLER_STS_DATA) & i2c_scl_div_cnt_rst;
    end
    
    // I2Cʱ�ӷ�Ƶ������
    always @(posedge clk)
    begin
        if(i2c_if_ctrler_sts == CTRLER_STS_DATA)
            # simulation_delay i2c_scl_div_cnt <= (i2c_scl_div_cnt == i2c_scl_div_rate) ? 8'd0:(i2c_scl_div_cnt + 8'd1);
        else
            # simulation_delay i2c_scl_div_cnt <= 8'd0;
    end
    
    /** I2C���ӿ� **/
    reg scl_o_reg; // SCL���
    reg sda_t_reg; // SDA����
    reg sda_o_reg; // SDA���
    
    assign scl_t = 1'b0;
    assign scl_o = scl_o_reg;
    assign sda_t = sda_t_reg;
    assign sda_o = sda_o_reg;
    
    // SCL���
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            scl_o_reg <= 1'b1;
        else if(((i2c_if_ctrler_sts == CTRLER_STS_DATA) & i2c_scl_div_cnt_rst) |
            ((i2c_if_ctrler_sts == CTRLER_STS_RESP) & (resp_stage_onehot[1] | resp_stage_onehot[3])) |
            ((i2c_if_ctrler_sts == CTRLER_STS_STOP) & (mode_latched == MODE_WITH_STOP) & (stop_stage_onehot[1] | stop_stage_onehot[3])))
        begin
            # simulation_delay scl_o_reg <= ~scl_o_reg;
        end
    end
    
    // SDA����(1'b1Ϊ����, 1'b0Ϊ���)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sda_t_reg <= 1'b1;
        else if(((i2c_if_ctrler_sts == CTRLER_STS_START) & (mode_latched == MODE_WITH_START)) | 
            ((i2c_if_ctrler_sts == CTRLER_STS_DATA) & shift_send_bit) |
            ((i2c_if_ctrler_sts == CTRLER_STS_RESP) & resp_stage_onehot[2]) |
            ((i2c_if_ctrler_sts == CTRLER_STS_STOP) & stop_stage_onehot[2]))
        begin
            # simulation_delay sda_t_reg <= 
                (i2c_if_ctrler_sts == CTRLER_STS_START) ? 1'b0:
                (i2c_if_ctrler_sts == CTRLER_STS_DATA) ? direction_latched:
                (i2c_if_ctrler_sts == CTRLER_STS_RESP) ? (~direction_latched):
                    1'b0;
        end
    end
    // SDA���
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sda_o_reg <= 1'b1;
        else if(((i2c_if_ctrler_sts == CTRLER_STS_START) & (mode_latched == MODE_WITH_START)) | 
            ((i2c_if_ctrler_sts == CTRLER_STS_DATA) & (~direction_latched) & shift_send_bit) |
            ((i2c_if_ctrler_sts == CTRLER_STS_RESP) & resp_stage_onehot[2] & direction_latched) |
            ((i2c_if_ctrler_sts == CTRLER_STS_STOP) & (stop_stage_onehot[2] | stop_stage_onehot[4])))
        begin
            # simulation_delay sda_o_reg <= 
                (i2c_if_ctrler_sts == CTRLER_STS_START) ? 1'b0:
                (i2c_if_ctrler_sts == CTRLER_STS_DATA) ? send_byte_buffer[7]:
                (i2c_if_ctrler_sts == CTRLER_STS_RESP) ? (mode_latched == MODE_WITH_STOP):
                    stop_stage_onehot[4];
        end
    end
    
endmodule
