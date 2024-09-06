`timescale 1ns / 1ps
/********************************************************************
��ģ��: sdram�������

����:
����������, �Է���sdramʱ��Ҫ��ķ�ʽ����������

2λbank��ַ, 11λ��/�е�ַ

֧����������:
�����     ����                  ��ע
  0      ����bank        �û�һ������ָ��������
  1     Ԥ���bank       �û�һ������ָ��������
  2      д����
  3      ������
  4   ����ģʽ�Ĵ���     �û�һ������ָ��������
  5     �Զ�ˢ��         �û�һ������ָ��������
  6     ֹͣͻ��    ���ڲ�ʹ��, �û�����ָ���������
  7      �ղ���         �û�һ������ָ��������

ע�⣺
ʱ�����ں�ʱ��Ҫ����ns��
ͻ�����Ƚ���ʹ��ȫҳͻ�����ڶ�/д���������¿���
ͻ�����͹̶�Ϊ˳��ͻ��(sequential)

Э��:
AXIS SLAVE

����: �¼�ҫ
����: 2024/04/13
********************************************************************/


module axis_sdram_cmd_agent #(
    parameter integer cas_latency = 2, // sdram��Ǳ����ʱ��(2 | 3)
    parameter real clk_period = 5.0, // ʱ������
    parameter real tRC = 55.0, // (����ĳ��bank -> ����ͬһbank)��(ˢ�����ʱ��)����Сʱ��Ҫ��
    parameter real tRRD = 10.0, // (����ĳ��bank -> ���ͬbank)����Сʱ��Ҫ��
    parameter real tRCD = 18.0, // (����ĳ��bank -> ��д���bank)����Сʱ��Ҫ��
    parameter real tRP = 15.0, // (Ԥ���ĳ��bank -> ˢ��/����ͬһbank/����ģʽ�Ĵ���)����Сʱ��Ҫ��
    parameter real tRAS_min = 35.0, // (����ĳ��bank -> Ԥ���ͬһbank)����Сʱ��Ҫ��
    parameter real tRAS_max = 100000.0, // (����ĳ��bank -> Ԥ���ͬһbank)�����ʱ��Ҫ��
    parameter real tWR = 2.0, // (дͻ������ -> Ԥ���)����Сʱ��Ҫ��
    parameter integer burst_len = -1, // ͻ������(-1 -> ȫҳ; 1 | 2 | 4 | 8)
    parameter allow_auto_precharge = "true", // �Ƿ������Զ�Ԥ���
    parameter en_cmd_axis_reg_slice = "true", // �Ƿ�ʹ������AXIS�Ĵ���Ƭ
    parameter en_expt_tip = "false" // �Ƿ�ʹ���쳣ָʾ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // ����AXIS
    input wire[15:0] s_axis_cmd_data, // {BS(2bit), A10-0(11bit), �����(3bit)}
    input wire[8:0] s_axis_cmd_user, // {�Ƿ��Զ����"ֹͣͻ��"����(1bit), ͻ������ - 1(8bit)}(����ȫҳͻ����Ч)
    input wire s_axis_cmd_valid,
    output wire s_axis_cmd_ready,
    
    // sdram������
    output wire sdram_cs_n,
    output wire sdram_ras_n,
    output wire sdram_cas_n,
    output wire sdram_we_n,
    output wire[1:0] sdram_ba,
    output wire[10:0] sdram_addr,
    
    // ͻ����Ϣ
    output wire new_burst_start, // ͻ����ʼָʾ
    output wire is_write_burst, // �Ƿ�дͻ��
    output wire[7:0] new_burst_len, // ͻ������ - 1
    
    // �쳣ָʾ
    output wire pcg_spcf_idle_bank_err, // Ԥ�����е��ض�bank(�쳣ָʾ)
    output wire pcg_spcf_bank_tot_err, // Ԥ����ض�bank��ʱ(�쳣ָʾ)
    output wire rw_idle_bank_err, // ��д���е�bank(�쳣ָʾ)
    output wire rfs_with_act_banks_err, // ˢ��ʱ�����Ѽ����bank(�쳣ָʾ)
    output wire illegal_logic_cmd_err, // �Ƿ����߼��������(�쳣ָʾ)
    output wire rw_cross_line_err // ���еĶ�д����(�쳣ָʾ)
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
    
    /** ���� **/
    localparam rw_data_with_auto_precharge = (burst_len == -1) ? "false":allow_auto_precharge; // ʹ�ܶ�д����������Զ�Ԥ���
    // ʱ��Ҫ��(��ʱ�����ڼ�)
    localparam integer tRC_p = $ceil(tRC / clk_period); // (����ĳ��bank -> ����ͬһbank)��(ˢ�����ʱ��)����Сʱ��Ҫ��
    localparam integer tRRD_p = $ceil(tRRD / clk_period); // (����ĳ��bank -> ���ͬbank)����Сʱ��Ҫ��
    localparam integer tRCD_p = $ceil(tRCD / clk_period); // (����ĳ��bank -> ��д���bank)����Сʱ��Ҫ��
    localparam integer tRP_p = $ceil(tRP / clk_period); // (Ԥ���ĳ��bank -> ˢ��/����ͬһbank/����ģʽ�Ĵ���)����Сʱ��Ҫ��
    localparam integer tRAS_min_p = $ceil(tRAS_min / clk_period); // (����ĳ��bank -> Ԥ���ͬһbank)����Сʱ��Ҫ��
    localparam integer tRAS_max_p = $ceil(tRAS_max / clk_period); // (����ĳ��bank -> Ԥ���ͬһbank)�����ʱ��Ҫ��
    localparam integer tWR_p = $ceil(tWR / clk_period); // (дͻ������ -> Ԥ���)����Сʱ��Ҫ��
    // ���Զ�Ԥ���Ķ� -> tRP + burst_len; ���Զ�Ԥ����д -> tRP + burst_len - 1 + tWR
    localparam integer tATRFS_p = tRP_p + 1; // (�Զ�Ԥ������ʱ��)����Сʱ��Ҫ��
    // ������߼�����
    localparam CMD_LOGI_BANK_ACTIVE = 3'b000; // ����:����bank
    localparam CMD_LOGI_BANK_PRECHARGE = 3'b001; // ����:Ԥ���bank
    localparam CMD_LOGI_WT_DATA = 3'b010; // ����:д����
    localparam CMD_LOGI_RD_DATA = 3'b011; // ����:������
    localparam CMD_LOGI_MR_SET = 3'b100; // ����:����ģʽ�Ĵ���
    localparam CMD_LOGI_AUTO_REFRESH = 3'b101; // ����:�Զ�ˢ��
    localparam CMD_LOGI_BURST_STOP = 3'b110; // ����:ֹͣͻ��
    localparam CMD_LOGI_NOP = 3'b111; // ����:�ղ���
    // ������������(CS_N, RAS_N, CAS_N, WE_N)
    localparam CMD_PHY_BANK_ACTIVE = 4'b0011; // ����:����bank
    localparam CMD_PHY_BANK_PRECHARGE = 4'b0010; // ����:Ԥ���bank
    localparam CMD_PHY_WT_DATA = 4'b0100; // ����:д����
    localparam CMD_PHY_RD_DATA = 4'b0101; // ����:������
    localparam CMD_PHY_MR_SET = 4'b0000; // ����:����ģʽ�Ĵ���
    localparam CMD_PHY_BURST_STOP = 4'b0110; // ����:ֹͣͻ��
    localparam CMD_PHY_AUTO_REFRESH = 4'b0001; // ����:�Զ�ˢ��
    localparam CMD_PHY_NOP = 4'b0111; // ����:�ղ���
    // bank״̬
    localparam STS_BANK_IDLE = 2'b00; // ״̬:����
    localparam STS_BANK_ACTIVE = 2'b01; // ״̬:����
    localparam STS_BANK_BURST = 2'b10; // ״̬:ͻ��������
    // ͻ�����ȼ�������λ��
    localparam integer burst_len_cnt_width = (burst_len == -1) ? 8:
                                              (burst_len == 1) ? 1:
                                              (clogb2(burst_len - 1) + 1);
    
    /** ��ѡ������AXIS�Ĵ���Ƭ **/
    wire[15:0] m_axis_cmd_data; // {BS(2bit), A10-0(11bit), �����(3bit)}
    wire[8:0] m_axis_cmd_user; // {�Ƿ��Զ����"ֹͣͻ��"����(1bit), ͻ������ - 1(8bit)}
    wire m_axis_cmd_valid;
    wire m_axis_cmd_ready;
    
    axis_reg_slice #(
        .data_width(16),
        .user_width(9),
        .forward_registered(en_cmd_axis_reg_slice),
        .back_registered(en_cmd_axis_reg_slice),
        .en_ready("true"),
        .simulation_delay(0)
    )cmd_axis_reg_slice(
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_data(s_axis_cmd_data),
        .s_axis_keep(),
        .s_axis_user(s_axis_cmd_user),
        .s_axis_last(),
        .s_axis_valid(s_axis_cmd_valid),
        .s_axis_ready(s_axis_cmd_ready),
        .m_axis_data(m_axis_cmd_data),
        .m_axis_keep(),
        .m_axis_user(m_axis_cmd_user),
        .m_axis_last(),
        .m_axis_valid(m_axis_cmd_valid),
        .m_axis_ready(m_axis_cmd_ready)
    );
    
    /** ������Сʱ��Ҫ������ **/
    // ��ȴ�����������ź�
    wire refresh_start; // ��ʼ�Զ�ˢ��(ָʾ)
    wire auto_precharge_start; // ��ʼ�Զ�Ԥ���(ָʾ)
    wire[3:0] bank_active_same_cd_trigger; // ����ͬһbank����ȴ����
    wire[3:0] bank_active_diff_cd_trigger; // ���ͬbank����ȴ����
    wire[3:0] bank_active_to_rw_itv_trigger; // �����д�ĵȴ�����
    wire[3:0] bank_precharge_itv_trigger; // Ԥ��絽ˢ��/����ͬһbank/����ģʽ�Ĵ����ĵȴ�����
    wire[3:0] bank_precharge_same_cd_trigger; // Ԥ���ͬһbank����ȴ����
    // ��ȴ����������������ź�
    wire refresh_busy_n; // �Զ�ˢ��æµ(��־)
    wire auto_precharge_busy_n; // �Զ�Ԥ���æµ(���)
    wire auto_precharge_itv_done; // �Զ�Ԥ���ĵȴ����
    wire[3:0] bank_active_same_cd_ready; // ����ͬһbank����ȴ����
    wire[3:0] bank_active_diff_cd_ready; // ���ͬbank����ȴ����
    wire[3:0] bank_active_to_rw_itv_ready; // �����д�ĵȴ�����
    wire[3:0] bank_precharge_itv_done; // Ԥ��絽ˢ��/����ͬһbank/����ģʽ�Ĵ����ĵȴ����
    wire[3:0] bank_precharge_itv_ready; // Ԥ��絽ˢ��/����ͬһbank/����ģʽ�Ĵ����ĵȴ�����
    wire[3:0] bank_precharge_same_cd_ready; // Ԥ���ͬһbank����ȴ����
    
    // �Զ�ˢ��æµ������
    cool_down_cnt #(
        .max_cd(tRC_p + 1)
    )refresh_busy_cnt(
        .clk(clk),
        .rst_n(rst_n),
        .cd(tRC_p),
        .timer_trigger(refresh_start),
        .timer_done(),
        .timer_ready(refresh_busy_n),
        .timer_v()
    );
    // �Զ�Ԥ���æµ������
    cool_down_cnt #(
        .max_cd(tATRFS_p + 1)
    )auto_precharge_cnt(
        .clk(clk),
        .rst_n(rst_n),
        .cd(tATRFS_p),
        .timer_trigger(auto_precharge_start),
        .timer_done(auto_precharge_itv_done),
        .timer_ready(auto_precharge_busy_n),
        .timer_v()
    );
    // ����ͬһbank����ȴ������
    genvar bank_active_same_cd_cnt_i;
    generate
        for(bank_active_same_cd_cnt_i = 0;bank_active_same_cd_cnt_i < 4;bank_active_same_cd_cnt_i = bank_active_same_cd_cnt_i + 1)
        begin
            cool_down_cnt #(
                .max_cd(tRC_p + 1)
            )bank_active_same_cd_cnt(
                .clk(clk),
                .rst_n(rst_n),
                .cd(tRC_p),
                .timer_trigger(bank_active_same_cd_trigger[bank_active_same_cd_cnt_i]),
                .timer_done(),
                .timer_ready(bank_active_same_cd_ready[bank_active_same_cd_cnt_i]),
                .timer_v()
            );
        end
    endgenerate
    // ���ͬbank����ȴ������
    genvar bank_active_diff_cd_cnt_i;
    generate
        for(bank_active_diff_cd_cnt_i = 0;bank_active_diff_cd_cnt_i < 4;bank_active_diff_cd_cnt_i = bank_active_diff_cd_cnt_i + 1)
        begin
            cool_down_cnt #(
                .max_cd(tRRD_p + 1)
            )bank_active_diff_cd_cnt(
                .clk(clk),
                .rst_n(rst_n),
                .cd(tRRD_p),
                .timer_trigger(bank_active_diff_cd_trigger[bank_active_diff_cd_cnt_i]),
                .timer_done(),
                .timer_ready(bank_active_diff_cd_ready[bank_active_diff_cd_cnt_i]),
                .timer_v()
            );
        end
    endgenerate
    // �����д�ĵȴ�������
    genvar bank_active_to_rw_itv_cnt_i;
    generate
        for(bank_active_to_rw_itv_cnt_i = 0;bank_active_to_rw_itv_cnt_i < 4;bank_active_to_rw_itv_cnt_i = bank_active_to_rw_itv_cnt_i + 1)
        begin
            cool_down_cnt #(
                .max_cd(tRCD_p + 1)
            )bank_active_to_rw_itv_cnt(
                .clk(clk),
                .rst_n(rst_n),
                .cd(tRCD_p),
                .timer_trigger(bank_active_to_rw_itv_trigger[bank_active_to_rw_itv_cnt_i]),
                .timer_done(),
                .timer_ready(bank_active_to_rw_itv_ready[bank_active_to_rw_itv_cnt_i]),
                .timer_v()
            );
        end
    endgenerate
    
    // Ԥ��絽ˢ��/����ͬһbank/����ģʽ�Ĵ����ĵȴ�������
    genvar precharge_itv_cnt_i;
    generate
        for(precharge_itv_cnt_i = 0;precharge_itv_cnt_i < 4;precharge_itv_cnt_i = precharge_itv_cnt_i + 1)
        begin
            cool_down_cnt #(
                .max_cd(tRP_p + 1)
            )precharge_itv_cnt(
                .clk(clk),
                .rst_n(rst_n),
                .cd(tRP_p),
                .timer_trigger(bank_precharge_itv_trigger[precharge_itv_cnt_i]),
                .timer_done(bank_precharge_itv_done[precharge_itv_cnt_i]),
                .timer_ready(bank_precharge_itv_ready[precharge_itv_cnt_i]),
                .timer_v()
            );
        end
    endgenerate
    
    genvar bank_precharge_same_cd_cnt_i;
    generate
        for(bank_precharge_same_cd_cnt_i = 0;bank_precharge_same_cd_cnt_i < 4;bank_precharge_same_cd_cnt_i = bank_precharge_same_cd_cnt_i + 1)
        begin
            cool_down_cnt #(
                .max_cd(tRAS_min_p + 1)
            )bank_precharge_same_cd_cnt(
                .clk(clk),
                .rst_n(rst_n),
                .cd(tRAS_min_p),
                .timer_trigger(bank_precharge_same_cd_trigger[bank_precharge_same_cd_cnt_i]),
                .timer_done(),
                .timer_ready(bank_precharge_same_cd_ready[bank_precharge_same_cd_cnt_i]),
                .timer_v()
            );
        end
    endgenerate
    
    /** bank״̬ **/
    wire[3:0] bank_rw_start; // ��дbank��ʼ(ָʾ)
    reg[1:0] bank_in_burst; // ���ڽ��ж�дͻ����bank
    wire rw_burst_done; // ��дͻ�����(ָʾ)
    reg rw_burst_done_d; // �ӳ�1clk�Ķ�дͻ�����(ָʾ)
    reg[1:0] bank_sts[3:0]; // bank״̬
    
    // �ӳ�1clk�Ķ�дͻ�����(ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rw_burst_done_d <= 1'b0;
        else
            rw_burst_done_d <= rw_burst_done;
    end
    
    genvar bank_sts_i;
    generate
        for(bank_sts_i = 0;bank_sts_i < 4;bank_sts_i = bank_sts_i + 1)
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    bank_sts[bank_sts_i] <= STS_BANK_IDLE;
                else
                begin
                    case(bank_sts[bank_sts_i])
                        STS_BANK_IDLE: // ״̬:����
                            if(bank_active_same_cd_trigger[bank_sts_i])
                                bank_sts[bank_sts_i] <= STS_BANK_ACTIVE; // -> ״̬:����
                        STS_BANK_ACTIVE: // ״̬:����
                            if(bank_rw_start[bank_sts_i])
                                bank_sts[bank_sts_i] <= STS_BANK_BURST; // -> ״̬:ͻ��������
                            else if(bank_precharge_itv_done[bank_sts_i] | // Ԥ������
                                ((rw_data_with_auto_precharge == "true") & auto_precharge_itv_done & (bank_in_burst == bank_sts_i))) // �Զ�Ԥ������
                                bank_sts[bank_sts_i] <= STS_BANK_IDLE; // -> ״̬:����
                        STS_BANK_BURST: // ״̬:ͻ��������
                            // ��ͻ������Ϊ1ʱ, ֱ�ӷ���"����"״̬
                            // ȫҳͻ��ʱ, ��Ҫ�����1clk������"ֹͣͻ��"����
                            if((burst_len == -1) ? rw_burst_done_d:((burst_len == 1) | rw_burst_done))
                                bank_sts[bank_sts_i] <= STS_BANK_ACTIVE; // -> ״̬:����
                        default:
                            bank_sts[bank_sts_i] <= STS_BANK_IDLE;
                    endcase
                end
            end
        end
    endgenerate
    
    /** ��дͻ�������� **/
    wire burst_start; // ��ʼͻ��(ָʾ)
    reg burst_start_d; // �ӳ�1clk�Ŀ�ʼͻ��(ָʾ)
    reg wt_burst_start_d; // �ӳ�1clk�Ŀ�ʼдͻ��(ָʾ)
    reg[7:0] burst_len_d; // �ӳ�1clk��ͻ������
    reg burst_transmitting; // ͻ��������(��־)
    reg[burst_len_cnt_width-1:0] burst_len_cnt; // ͻ�����ȼ�����
    reg burst_last; // ͻ�������1�δ���(ָʾ)
    reg is_wt_burst_latched; // ������Ƿ�дͻ��
    wire is_wt_burst; // �Ƿ�дͻ��
    reg addr10_latched; // �������/�е�ַ��10λ
    wire auto_add_burst_stop; // �Զ����"ֹͣͻ��"����
    reg auto_add_burst_stop_latched; // ������Զ����"ֹͣͻ��"����
    reg[cas_latency:0] rd_burst_end_waiting; // ��ͻ����ɺ�ȴ�(������)
    reg to_add_burst_stop; // ���"ֹͣͻ��"����(ָʾ)
    
    assign new_burst_start = burst_start_d;
    assign is_write_burst = wt_burst_start_d;
    assign new_burst_len = burst_len_d;
    
    // ��ȫҳͻ����˵, ͻ�����ȿ���Ϊ1, ͻ����ʼ����1clkӦֱ�Ӷ�����AXIS�е�user���ж�
    assign rw_burst_done = burst_transmitting ? burst_last:(burst_start & ((burst_len == -1) & (m_axis_cmd_user[7:0] == 8'd0)));
    
    // ͻ����ʼ����1clkӦֱ�Ӷ�����AXIS�е�data/user���ж�
    assign is_wt_burst = burst_start ? (m_axis_cmd_data[2:0] == CMD_LOGI_WT_DATA):is_wt_burst_latched;
    assign auto_add_burst_stop = burst_start ? m_axis_cmd_user[8]:auto_add_burst_stop_latched;
    
    // ���ڽ��ж�дͻ����bank
    always @(posedge clk)
    begin
        if(burst_start)
            bank_in_burst <= m_axis_cmd_data[15:14];
    end
    
    // �ӳ�1clk�Ŀ�ʼͻ��(ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            burst_start_d <= 1'b0;
        else
            burst_start_d <= burst_start;
    end
    // �ӳ�1clk�Ŀ�ʼдͻ��(ָʾ)
    always @(posedge clk)
        wt_burst_start_d <= m_axis_cmd_data[2:0] == CMD_LOGI_WT_DATA;
    // �ӳ�1clk��ͻ������
    always @(posedge clk)
        burst_len_d <= (burst_len == -1) ? m_axis_cmd_user[7:0]:(burst_len - 1);
    
    // ͻ��������(��־)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            burst_transmitting <= 1'b0;
        else
            // ��ȫҳͻ����˵, �����ͻ����ʼ����1clk����ͻ������Ϊ1, "ͻ��������"��־������Ч, ������ΪĿǰ���ǵ�ǰͻ�������1�δ���
            burst_transmitting <= burst_transmitting ? (~burst_last):(burst_start & ((burst_len != -1) | (m_axis_cmd_user[7:0] != 8'd0)));
    end
    // ͻ�����ȼ�����
    always @(posedge clk)
    begin
        if(burst_start)
            burst_len_cnt <= (burst_len == -1) ? m_axis_cmd_user[7:0]:(burst_len - 1);
        else
            burst_len_cnt <= burst_len_cnt - 1;
    end
    // ͻ�������1�δ���(ָʾ)
    always @(posedge clk)
    begin
        if(burst_start)
            burst_last <= (burst_len == -1) ? (m_axis_cmd_user[7:0] == 8'd1):(burst_len == 2);
        else
            burst_last <= burst_len_cnt == 2;
    end
    
    // ������Ƿ�дͻ��
    always @(posedge clk)
    begin
        if(burst_start)
            is_wt_burst_latched <= m_axis_cmd_data[2:0] == CMD_LOGI_WT_DATA;
    end
    // �������/�е�ַ��10λ
    always @(posedge clk)
    begin
        if(burst_start)
            addr10_latched <= m_axis_cmd_data[13];
    end
    
    // ������Զ����"ֹͣͻ��"����
    always @(posedge clk)
    begin
        if(burst_start)
            auto_add_burst_stop_latched <= m_axis_cmd_user[8];
    end
    
    // ��дͻ����ɺ�ȴ�(��־)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_burst_end_waiting <= {{(cas_latency){1'b0}}, 1'b1};
        else if((rw_burst_done & (~is_wt_burst)) | (~rd_burst_end_waiting[0]))
            rd_burst_end_waiting <= {rd_burst_end_waiting[cas_latency-1:0], rd_burst_end_waiting[cas_latency]};
    end
    
    // ���"ֹͣͻ��"����(ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            to_add_burst_stop <= 1'b0;
        else
            to_add_burst_stop <= rw_burst_done & auto_add_burst_stop;
    end
    
    /** дͻ�������ȴ������� **/
    // ����:tWR_p����̫��, ����<=9!
    reg[tWR_p:0] wt_burst_end_itv_cnt;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_burst_end_itv_cnt <= {{tWR_p{1'b0}}, 1'b1};
        else if((is_wt_burst & rw_burst_done) | (~wt_burst_end_itv_cnt[0]))
            wt_burst_end_itv_cnt <= {wt_burst_end_itv_cnt[tWR_p-1:0], wt_burst_end_itv_cnt[tWR_p]};
    end
    
    /** дģʽ�Ĵ����ȴ� **/
    // дģʽ�Ĵ�����Ҫ1clk�����
    wire next_cmd_is_mr_set; // ��һ������"����ģʽ�Ĵ���"(ָʾ)
    reg to_wait_for_mr_set_n; // дģʽ�Ĵ����ȴ�
    
    // дģʽ�Ĵ����ȴ�
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            to_wait_for_mr_set_n <= 1'b1;
        else
            to_wait_for_mr_set_n <= ~next_cmd_is_mr_set;
    end
    
    /** ������� **/
    // ��һ����
    wire[2:0] next_cmd_id; // ��һ������߼�����
    wire[10:0] next_cmd_addr; // ��һ�������/�е�ַ
    wire[1:0] next_cmd_ba; // ��һ�����bank��ַ
    // ��ǰ����
    reg[3:0] now_cmd_ecd; // ��ǰ������������
    reg[10:0] now_cmd_addr; // ��ǰ�������/�е�ַ
    reg[1:0] now_cmd_ba; // ��ǰ�����bank��ַ
    
    assign m_axis_cmd_ready = refresh_busy_n & // �Զ�ˢ��ʱ�ĵȴ�
        to_wait_for_mr_set_n & // дģʽ�Ĵ����ȴ�
        ((allow_auto_precharge == "false") | (burst_len == -1) | auto_precharge_busy_n) & // �Զ�Ԥ���ʱ�ĵȴ�, ע�⵽ȫҳͻ��ʱ�����ܴ����Զ�Ԥ���
        ((burst_len == 1) | ((~burst_transmitting) & ((burst_len != -1) | (rd_burst_end_waiting[0] & (~rw_burst_done_d))))) & // ��д�����ڼ�Ӧ����NOP����, ��ȫҳͻ����˵�����������Ƿ����"ֹͣͻ��"�������������2/3������
        ((m_axis_cmd_data[2:0] == CMD_LOGI_BANK_ACTIVE) ? (bank_active_same_cd_ready[next_cmd_ba] & 
            bank_active_diff_cd_ready[next_cmd_ba] & bank_precharge_itv_ready[next_cmd_ba]): // BANK�������ȴ
        (m_axis_cmd_data[2:0] == CMD_LOGI_BANK_PRECHARGE) ? ((next_cmd_addr[10] ? (&bank_precharge_same_cd_ready):bank_precharge_same_cd_ready[next_cmd_ba]) & 
            ((burst_len == -1) | wt_burst_end_itv_cnt[0])): // Ԥ������ȴ
        ((m_axis_cmd_data[2:0] == CMD_LOGI_WT_DATA) | (m_axis_cmd_data[2:0] == CMD_LOGI_RD_DATA)) ? bank_active_to_rw_itv_ready[next_cmd_ba]: // ��д���ݵ���ȴ
        ((m_axis_cmd_data[2:0] == CMD_LOGI_MR_SET) | (m_axis_cmd_data[2:0] == CMD_LOGI_AUTO_REFRESH)) ? (&bank_precharge_itv_ready): // ����ģʽ�Ĵ������Զ�ˢ�µ���ȴ
        1'b1 // �ղ���
    );
    
    assign {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = now_cmd_ecd;
    assign sdram_ba = now_cmd_ba;
    assign sdram_addr = now_cmd_addr;
    
    assign next_cmd_is_mr_set = next_cmd_id == CMD_LOGI_MR_SET;
    assign refresh_start = next_cmd_id == CMD_LOGI_AUTO_REFRESH;
    // ͻ������Ϊ1ʱ, ��ͻ����ʼ����1clkֱ�Ӷ�����AXIS�е�data���ж�, ��Ϊ�������, ����ͻ������ʱ�ж�
    // ע�⵽ȫҳͻ��ʱ�����ܴ����Զ�Ԥ���
    assign auto_precharge_start = (burst_len == 1) ? (burst_start & m_axis_cmd_data[13]):(rw_burst_done & addr10_latched);
    
    genvar trigger_i;
    generate
        for(trigger_i = 0;trigger_i < 4;trigger_i = trigger_i + 1)
        begin
            assign bank_active_same_cd_trigger[trigger_i] = (next_cmd_id == CMD_LOGI_BANK_ACTIVE) & (next_cmd_ba == trigger_i);
            assign bank_active_diff_cd_trigger[trigger_i] = (next_cmd_id == CMD_LOGI_BANK_ACTIVE) & (next_cmd_ba != trigger_i);
            assign bank_active_to_rw_itv_trigger[trigger_i] = (next_cmd_id == CMD_LOGI_BANK_ACTIVE) & (next_cmd_ba == trigger_i);
            assign bank_precharge_itv_trigger[trigger_i] = (next_cmd_id == CMD_LOGI_BANK_PRECHARGE) & (next_cmd_addr[10] | (next_cmd_ba == trigger_i));
            assign bank_precharge_same_cd_trigger[trigger_i] = (next_cmd_id == CMD_LOGI_BANK_ACTIVE) & (next_cmd_addr[10] | (next_cmd_ba == trigger_i));
            
            assign bank_rw_start[trigger_i] = ((next_cmd_id == CMD_LOGI_WT_DATA) | (next_cmd_id == CMD_LOGI_RD_DATA)) & (next_cmd_ba == trigger_i);
        end
    endgenerate
    
    assign burst_start = (next_cmd_id == CMD_LOGI_WT_DATA) | (next_cmd_id == CMD_LOGI_RD_DATA);
    
    assign next_cmd_id = (m_axis_cmd_valid & m_axis_cmd_ready) ? m_axis_cmd_data[2:0]: // ������һ������
        ((burst_len == -1) & to_add_burst_stop) ? CMD_LOGI_BURST_STOP: // ��ȫҳͻ����˵���������Ҫ����"ֹͣͻ��"����
        CMD_LOGI_NOP;
    assign next_cmd_addr = m_axis_cmd_data[13:3];
    assign next_cmd_ba = m_axis_cmd_data[15:14];
    
    // ��ǰ������������
    // �߼����� -> �������
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            now_cmd_ecd <= CMD_PHY_NOP;
        else
        begin
            case(next_cmd_id)
                CMD_LOGI_BANK_ACTIVE: now_cmd_ecd <= CMD_PHY_BANK_ACTIVE;
                CMD_LOGI_BANK_PRECHARGE: now_cmd_ecd <= CMD_PHY_BANK_PRECHARGE;
                CMD_LOGI_WT_DATA: now_cmd_ecd <= CMD_PHY_WT_DATA;
                CMD_LOGI_RD_DATA: now_cmd_ecd <= CMD_PHY_RD_DATA;
                CMD_LOGI_MR_SET: now_cmd_ecd <= CMD_PHY_MR_SET;
                CMD_LOGI_AUTO_REFRESH: now_cmd_ecd <= CMD_PHY_AUTO_REFRESH;
                CMD_LOGI_BURST_STOP: now_cmd_ecd <= CMD_PHY_BURST_STOP;
                CMD_LOGI_NOP: now_cmd_ecd <= CMD_PHY_NOP;
                default: now_cmd_ecd <= CMD_PHY_NOP;
            endcase
        end
    end
    // ��ǰ�������/�е�ַ
    always @(posedge clk)
        now_cmd_addr <= next_cmd_addr;
    // ��ǰ�����bank��ַ
    always @(posedge clk)
        now_cmd_ba <= next_cmd_ba;
    
    /** �쳣ָʾ **/
    reg pcg_spcf_idle_bank_err_reg; // Ԥ�����е��ض�bank(�쳣ָʾ)
    reg pcg_spcf_bank_tot_err_reg; // Ԥ����ض�bank��ʱ(�쳣ָʾ)
    reg rw_idle_bank_err_reg; // ��д���е�bank(�쳣ָʾ)
    reg rfs_with_act_banks_err_reg; // ˢ��ʱ�����Ѽ����bank(�쳣ָʾ)
    reg illegal_logic_cmd_err_reg; // �Ƿ����߼��������(�쳣ָʾ)
    reg rw_cross_line_err_reg; // ���еĶ�д����(�쳣ָʾ)
    wire[8:0] col_addr_add_burst_len; // �е�ַ + ͻ������
    reg[clogb2(tRAS_max_p-1):0] pcg_tot_cnt[3:0]; // Ԥ����ض�bank��ʱ������
    
    assign pcg_spcf_idle_bank_err = (en_expt_tip == "true") ? pcg_spcf_idle_bank_err_reg:1'b0;
    assign pcg_spcf_bank_tot_err = (en_expt_tip == "true") ? pcg_spcf_bank_tot_err_reg:1'b0;
    assign rw_idle_bank_err = (en_expt_tip == "true") ? rw_idle_bank_err_reg:1'b0;
    assign rfs_with_act_banks_err = (en_expt_tip == "true") ? rfs_with_act_banks_err_reg:1'b0;
    assign illegal_logic_cmd_err = (en_expt_tip == "true") ? illegal_logic_cmd_err_reg:1'b0;
    assign rw_cross_line_err = (en_expt_tip == "true") ? rw_cross_line_err_reg:1'b0;
    
    assign col_addr_add_burst_len = m_axis_cmd_data[10:3] + ((burst_len == -1) ? m_axis_cmd_user[7:0]:(burst_len - 1));
    
    // Ԥ�����е��ض�bank(�쳣ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            pcg_spcf_idle_bank_err_reg <= 1'b0;
        else
            pcg_spcf_idle_bank_err_reg <= (next_cmd_id == CMD_LOGI_BANK_PRECHARGE) & (bank_sts[next_cmd_ba] == STS_BANK_IDLE) & (~next_cmd_addr[10]);
    end
    // Ԥ����ض�bank��ʱ(�쳣ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            pcg_spcf_bank_tot_err_reg <= 1'b0;
        else
            pcg_spcf_bank_tot_err_reg <= ((bank_sts[0] != STS_BANK_IDLE) & (pcg_tot_cnt[0] == 0)) | 
                ((bank_sts[1] != STS_BANK_IDLE) & (pcg_tot_cnt[1] == 0)) | 
                ((bank_sts[2] != STS_BANK_IDLE) & (pcg_tot_cnt[2] == 0)) | 
                ((bank_sts[3] != STS_BANK_IDLE) & (pcg_tot_cnt[3] == 0));
    end
    // ��д���е�bank(�쳣ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rw_idle_bank_err_reg <= 1'b0;
        else
            rw_idle_bank_err_reg <= ((next_cmd_id == CMD_LOGI_WT_DATA) | (next_cmd_id == CMD_LOGI_RD_DATA)) & (bank_sts[next_cmd_ba] == STS_BANK_IDLE);
    end
    // ˢ��ʱ�����Ѽ����bank(�쳣ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rfs_with_act_banks_err_reg <= 1'b0;
        else
            rfs_with_act_banks_err_reg <= (next_cmd_id == CMD_LOGI_AUTO_REFRESH) & 
                ((bank_sts[0] != STS_BANK_IDLE) | (bank_sts[1] != STS_BANK_IDLE) | (bank_sts[2] != STS_BANK_IDLE) | (bank_sts[3] != STS_BANK_IDLE));
    end
    // �Ƿ����߼��������(�쳣ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            illegal_logic_cmd_err_reg <= 1'b0;
        else
            illegal_logic_cmd_err_reg <= (m_axis_cmd_valid & m_axis_cmd_ready) & 
                (m_axis_cmd_data[2:0] == CMD_LOGI_BURST_STOP);
    end
    // ���еĶ�д����(�쳣ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rw_cross_line_err_reg <= 1'b0;
        else
            rw_cross_line_err_reg <= (m_axis_cmd_valid & m_axis_cmd_ready) & 
                ((m_axis_cmd_data[2:0] == CMD_LOGI_WT_DATA) | (m_axis_cmd_data[2:0] == CMD_LOGI_RD_DATA)) & 
                col_addr_add_burst_len[8];
    end
    
    // Ԥ����ض�bank��ʱ������
    genvar pcg_tot_i;
    generate
        for(pcg_tot_i = 0;pcg_tot_i < 4;pcg_tot_i = pcg_tot_i + 1)
        begin
            always @(posedge clk)
            begin
                if(bank_active_same_cd_trigger[pcg_tot_i] | bank_precharge_itv_trigger[pcg_tot_i])
                    pcg_tot_cnt[pcg_tot_i] <= tRAS_max_p - 1;
                else if(bank_sts[pcg_tot_i] != STS_BANK_IDLE)
                    pcg_tot_cnt[pcg_tot_i] <= pcg_tot_cnt[pcg_tot_i] - 1;
            end
        end
    endgenerate
    
endmodule
