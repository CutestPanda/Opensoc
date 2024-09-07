`timescale 1ns / 1ps
/********************************************************************
��ģ��: SD����ʼ��ģ��

����:
��ʼ������ ->
    (1)����CMD0��λ
    ���� = 32'h00000000
    ������û����Ӧ
    (2)����CMD8����SD1.X��SD2.0
    ���� = 32'h000001AA
    ����Ӧ -> SD2.0����
    ����Ӧ -> ��ѹ��ƥ���2.0����SD��/1.0��SD��/����SD��
    (3)����ACMD41(CMD55 + CMD41)
    ����0 = 32'h00000000
    ����1 = 32'h40FF8000
    ��Ӧ[30] -> �Ƿ��������
    ��Ӧ[31] -> �Ƿ��ϵ�
    (4)����CMD2�Ի�ȡCID
    ���� = 32'h00000000
    ���Ը��������Ӧ
    (5)����CMD3Ҫ��cardָ��һ��RCA
    ���� = 32'h00000000
    ��Ӧ[31:16] = RCA
    (6)����CMD7ѡ�п�
    ����[31:16] = RCA, ����[15:0] = 16'h0000
    ���Ը��������Ӧ
    (7)����CMD16ָ�����СΪ512Byte
    ���� = 32'h00000200
    ��Ӧ[12:9] = ��״̬(4Ϊtran״̬)
    ���Ը��������Ӧ
    (8)����ACMD6(CMD55 + CMD6)��������λ��
    ����0[31:16] = RCA, ����0[15:0] = 16'h0000
    ����1 = ��������ģʽ ? 32'h00000002:32'h00000000
    ���Ը��������Ӧ
    (9)����CMD6��ѯSD������
    ���� = 32'h00FF_FF01
    ���Ը��������Ӧ, ���Ը�����Ķ����ݷ���
    (10)����CMD6�л�������ģʽ
    ���� = 32'h80FF_FF01
    ���Ը��������Ӧ, ���Ը�����Ķ����ݷ���

ע�⣺
��

Э��:
AXIS MASTER/SLAVE

����: �¼�ҫ
����: 2024/02/29
********************************************************************/


module sd_card_init #(
    parameter integer init_acmd41_try_n = 20, // ��ʼ��ʱ����ACMD41����ĳ��Դ���(����<=32)
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire resetn,
    
    // ����ʱ����
    input wire en_wide_sdio, // ��������ģʽ
    
    // ��ʼ��ģ�����
    input wire init_start, // ��ʼ��ʼ������(ָʾ)
    output wire init_idle, // ��ʼ��ģ�����(��־)
    output wire init_done, // ��ʼ�����(ָʾ)
    
    // ����AXIS
    output wire[39:0] m_axis_cmd_data, // {����(1bit), �Ƿ���Զ�����(1bit), �����(6bit), ����(32bit)}
    output wire m_axis_cmd_valid,
    input wire m_axis_cmd_ready,
    
    // ��ӦAXIS
    input wire[119:0] s_axis_resp_data, // 48bit��Ӧ -> {�����(6bit), ����(32bit)}, 136bit��Ӧ -> {����(120bit)}
    input wire[2:0] s_axis_resp_user, // {���ճ�ʱ(1bit), CRC����(1bit), �Ƿ���Ӧ(1bit)}
    input wire s_axis_resp_valid,
    
    // ��ʼ�����AXIS
    output wire[23:0] m_axis_init_res_data, // {����(5bit), RCA(16bit), �Ƿ��������(1bit), �Ƿ�֧��SD2.0(1bit), �Ƿ�ɹ�(1bit)}
    output wire m_axis_init_res_valid
);

    /** ���� **/
    // ��ʼ��״̬
    localparam WAIT_INIT_START = 2'b00; // ״̬:�ȴ���ʼ��ʼ��
    localparam SEND_CMD = 2'b01; // ״̬:��������
    localparam WAIT_RESP = 2'b10; // ״̬:�ȴ���Ӧ
    localparam INIT_FINISHED = 2'b11; // ״̬:��ʼ�����
    
    /** ��ʼ��״̬�� **/
    wire sd_card_init_start; // ��ʼ��ʼ��(ָʾ)
    reg is_first_cmd; // ��һ������(��־)
    reg[1:0] sd_card_init_sts; // sd����ʼ��״̬
    reg s_axis_resp_valid_d; // �ӳ�1clk����ӦAXIS��valid
    reg sd_card_init_failed; // sd����ʼ��ʧ��(��־)
    reg sd_card_init_cmd_last; // sd����ʼ�����1������(��־)
    
    assign sd_card_init_start = (sd_card_init_sts == WAIT_INIT_START) & init_start;
    
    // ��һ������(��־)
    always @(posedge clk)
    begin
        if(sd_card_init_start)
            # simulation_delay is_first_cmd <= 1'b1;
        else if(is_first_cmd)
            # simulation_delay is_first_cmd <= sd_card_init_sts != WAIT_RESP;
    end
    
    // sd����ʼ��״̬
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sd_card_init_sts <= WAIT_INIT_START;
        else
        begin
            # simulation_delay;
            
            case(sd_card_init_sts)
                WAIT_INIT_START: // ״̬:�ȴ���ʼ��ʼ��
                    if(init_start)
                        sd_card_init_sts <= SEND_CMD; // -> ״̬:��������
                SEND_CMD: // ״̬:��������
                    if(m_axis_cmd_valid & m_axis_cmd_ready)
                        sd_card_init_sts <= WAIT_RESP; // -> ״̬:�ȴ���Ӧ
                WAIT_RESP: // ״̬:�ȴ���Ӧ
                    if(s_axis_resp_valid_d | is_first_cmd)
                        sd_card_init_sts <= (sd_card_init_cmd_last | sd_card_init_failed) ?
                            INIT_FINISHED: // -> ״̬:��ʼ�����
                            SEND_CMD; // -> ״̬:��������
                INIT_FINISHED: // ״̬:��ʼ�����
                    sd_card_init_sts <= WAIT_INIT_START; // -> ״̬:�ȴ���ʼ��ʼ��
                default:
                    sd_card_init_sts <= WAIT_INIT_START;
            endcase
        end
    end
    
    // �ӳ�1clk����ӦAXIS��valid
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            s_axis_resp_valid_d <= 1'b0;
        else
            # simulation_delay s_axis_resp_valid_d <= s_axis_resp_valid;
    end
    
    /** ��ʼ��ģ��״̬ **/
    reg init_idle_reg; // ��ʼ��ģ�����(��־)
    reg init_done_reg; // ��ʼ�����(ָʾ)
    
    assign init_idle = init_idle_reg;
    assign init_done = init_done_reg;
    
    // ��ʼ��ģ�����(��־)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            init_idle_reg <= 1'b1;
        else
            # simulation_delay init_idle_reg <= init_idle ? (~init_start):init_done;
    end
    // ��ʼ�����(ָʾ)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            init_done_reg <= 1'b0;
        else
            # simulation_delay init_done_reg <= (sd_card_init_sts == WAIT_RESP) &
                s_axis_resp_valid_d & (sd_card_init_cmd_last | sd_card_init_failed);
    end
    
    /** ����������� **/
    /*
    �������� ���������� �����
       0        X      CMD0
       1        X      CMD8
       2        0      CMD55
                1      CMD41
       3        X      CMD2
       4        X      CMD3
       5        X      CMD7
       6        X      CMD16
       7        0      CMD55
                1      CMD6
       8        X      CMD6
       9        X      CMD6
    */
    reg[3:0] cmd_id; // ��������
    reg sub_cmd_id; // ����������
    reg[5:0] m_axis_cmd_data_cmd_id; // ����AXIS�������
    reg[15:0] rca; // RCA
    reg[31:0] m_axis_cmd_data_cmd_pars; // ����AXIS���������
    reg m_axis_cmd_valid_reg; // ����AXIS��valid
    reg[4:0] acmd41_try_cnt; // ACMD41���Դ���(������)
    wire acmd41_succeeded; // ACMD41�ɹ�(ָʾ)
    reg acmd41_try_last; // ACMD41���1�γ���(��־)
    
    assign m_axis_cmd_data = {1'b0, 1'b1, m_axis_cmd_data_cmd_id, m_axis_cmd_data_cmd_pars};
    assign m_axis_cmd_valid = m_axis_cmd_valid_reg;
    
    // sd����ʼ�����1������(��־)
    always @(posedge clk)
    begin
        if(sd_card_init_start)
            # simulation_delay sd_card_init_cmd_last <= 1'b0;
        else if(m_axis_cmd_valid & m_axis_cmd_ready)
            # simulation_delay sd_card_init_cmd_last <= cmd_id == 4'd9;
    end
    
    // ��������
    always @(posedge clk)
    begin
        if(sd_card_init_start)
            # simulation_delay cmd_id <= 4'd0;
        else if((cmd_id == 4'd2) ? acmd41_succeeded:
                (cmd_id == 4'd7) ? (m_axis_cmd_valid & m_axis_cmd_ready & sub_cmd_id):
                                   (m_axis_cmd_valid & m_axis_cmd_ready))
            # simulation_delay cmd_id <= cmd_id + 4'd1;
    end
    // ����������
    always @(posedge clk)
    begin
        if(sd_card_init_start)
            # simulation_delay sub_cmd_id <= 1'b0;
        else if(m_axis_cmd_valid & m_axis_cmd_ready & ((cmd_id == 4'd2) | (cmd_id == 4'd7)))
            # simulation_delay sub_cmd_id <= ~sub_cmd_id;
    end
    
    // ����AXIS�������
    always @(posedge clk)
    begin
        if(sd_card_init_start)
            # simulation_delay m_axis_cmd_data_cmd_pars <= 32'h0000_0000;
        else
        begin
            # simulation_delay;
            
            case(cmd_id)
                4'd0: m_axis_cmd_data_cmd_pars <= 32'h0000_0000;
                4'd1: m_axis_cmd_data_cmd_pars <= 32'h0000_01AA;
                4'd2: m_axis_cmd_data_cmd_pars <= sub_cmd_id ? 32'h40FF_8000:32'h0000_0000;
                4'd3: m_axis_cmd_data_cmd_pars <= 32'h0000_0000;
                4'd4: m_axis_cmd_data_cmd_pars <= 32'h0000_0000;
                4'd5: m_axis_cmd_data_cmd_pars <= {rca, 16'h0000};
                4'd6: m_axis_cmd_data_cmd_pars <= 32'h0000_0200;
                4'd7: m_axis_cmd_data_cmd_pars <= sub_cmd_id ? (en_wide_sdio ? 32'h0000_0002:32'h0000_0000):{rca, 16'h0000};
                4'd8: m_axis_cmd_data_cmd_pars <= 32'h00FF_FF01;
                4'd9: m_axis_cmd_data_cmd_pars <= 32'h80FF_FF01;
                default: m_axis_cmd_data_cmd_pars <= 32'h0000_0000;
            endcase
        end
    end
    // ����AXIS���������
    always @(posedge clk)
    begin
        if(sd_card_init_start)
            # simulation_delay m_axis_cmd_data_cmd_id <= 6'd0;
        else
        begin
            # simulation_delay;
            
            case(cmd_id)
                4'd0: m_axis_cmd_data_cmd_id <= 6'd0;
                4'd1: m_axis_cmd_data_cmd_id <= 6'd8;
                4'd2: m_axis_cmd_data_cmd_id <= sub_cmd_id ? 6'd41:6'd55;
                4'd3: m_axis_cmd_data_cmd_id <= 6'd2;
                4'd4: m_axis_cmd_data_cmd_id <= 6'd3;
                4'd5: m_axis_cmd_data_cmd_id <= 6'd7;
                4'd6: m_axis_cmd_data_cmd_id <= 6'd16;
                4'd7: m_axis_cmd_data_cmd_id <= sub_cmd_id ? 6'd6:6'd55;
                4'd8, 4'd9: m_axis_cmd_data_cmd_id <= 6'd6;
                default: m_axis_cmd_data_cmd_id <= 6'd0;
            endcase
        end
    end
    // ����AXIS��valid
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            m_axis_cmd_valid_reg <= 1'b0;
        else
            # simulation_delay m_axis_cmd_valid_reg <= m_axis_cmd_valid_reg ?
                (~m_axis_cmd_ready):
                (sd_card_init_start | ((sd_card_init_sts == WAIT_RESP) & (s_axis_resp_valid_d | is_first_cmd) & (~(sd_card_init_cmd_last | sd_card_init_failed))));
    end
    
    // ACMD41���Դ���(������)
    always @(posedge clk)
    begin
        if(sd_card_init_start)
            # simulation_delay acmd41_try_cnt <= 5'd0;
        else if(((cmd_id == 4'd2) & sub_cmd_id) & m_axis_cmd_valid & m_axis_cmd_ready)
            # simulation_delay acmd41_try_cnt <= acmd41_try_cnt + 5'd1;
    end
    // ACMD41���1�γ���(��־)
    always @(posedge clk)
    begin
        if(sd_card_init_start)
            # simulation_delay acmd41_try_last <= 1'b0;
        else if(((cmd_id == 4'd2) & sub_cmd_id) & m_axis_cmd_valid & m_axis_cmd_ready)
            # simulation_delay acmd41_try_last <= acmd41_try_cnt == (init_acmd41_try_n - 1);
    end
    
    /** ��Ӧ���� **/
    /*
    �������� ���������� �����
       0        X      CMD0
       1        X      CMD8
       2        0      CMD55
                1      CMD41
       3        X      CMD2
       4        X      CMD3
       5        X      CMD7
       6        X      CMD16
       7        0      CMD55
                1      CMD6
       8        X      CMD6
       9        X      CMD6
    */
    reg[3:0] now_cmd_id; // ��ǰ���������
    reg now_sub_cmd_id; // ��ǰ�����������
    
    assign acmd41_succeeded = s_axis_resp_valid & ((now_cmd_id == 4'd2) & now_sub_cmd_id) &
        (~s_axis_resp_user[1]) & (~s_axis_resp_user[2]) & s_axis_resp_data[31];
    
    // sd����ʼ��ʧ��(��־)
    always @(posedge clk)
    begin
        if(sd_card_init_start)
            # simulation_delay sd_card_init_failed <= 1'b0;
        else if((~sd_card_init_failed) & s_axis_resp_valid)
            # simulation_delay sd_card_init_failed <= s_axis_resp_user[1] | // CRC����
                ((now_cmd_id == 4'd1) ? 1'b0:s_axis_resp_user[2]) | // ���ճ�ʱ(CMD8����)
                (((now_cmd_id == 4'd2) & now_sub_cmd_id) & acmd41_try_last & (~s_axis_resp_data[31])) | // ACMD41ʧ��
                ((now_cmd_id == 4'd6) & (s_axis_resp_data[12:9] != 4'd4)); // ѡ�п���δ����tran״̬
    end
    
    // RCA
    always @(posedge clk)
    begin
        if(s_axis_resp_valid & (now_cmd_id == 4'd4))
            # simulation_delay rca <= s_axis_resp_data[31:16];
    end
    
    // ��ǰ���������
    // ��ǰ�����������
    always @(posedge clk)
    begin
        if(m_axis_cmd_valid & m_axis_cmd_ready)
            # simulation_delay {now_cmd_id, now_sub_cmd_id} <= {cmd_id, sub_cmd_id};
    end
    
    // ��ʼ�����AXIS
    reg is_large_volume_card; // �Ƿ��������
    reg sd2_supported; // �Ƿ�֧��SD2.0
    reg init_succeeded; // ��ʼ���ɹ�
    reg m_axis_init_res_valid_reg; // ��ʼ�����AXIS��valid
    
    assign m_axis_init_res_data = {5'd0, rca, is_large_volume_card, sd2_supported, init_succeeded};
    assign m_axis_init_res_valid = m_axis_init_res_valid_reg;
    
    // �Ƿ��������
    always @(posedge clk)
    begin
        if(s_axis_resp_valid & ((now_cmd_id == 4'd2) & now_sub_cmd_id))
            # simulation_delay is_large_volume_card <= s_axis_resp_data[30];
    end
    // �Ƿ�֧��SD2.0
    always @(posedge clk)
    begin
        if(s_axis_resp_valid & (now_cmd_id == 4'd1))
            # simulation_delay sd2_supported <= ~s_axis_resp_user[2];
    end
    // ��ʼ���ɹ�
    always @(posedge clk)
    begin
        if(init_done)
            # simulation_delay init_succeeded <= ~sd_card_init_failed;
    end
    
    // ��ʼ�����AXIS��valid
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            m_axis_init_res_valid_reg <= 1'b0;
        else
            # simulation_delay m_axis_init_res_valid_reg <= init_done;
    end

endmodule
