`timescale 1ns / 1ps
/********************************************************************
��ģ��: sdram�Զ�ˢ�¿�����

����:
����Ҫ���ˢ�¼��, �����Զ�ˢ��������

�Զ�ˢ��Ԥ����Чʱ, �ȴ�����bank����ʱ��ˢ��
ǿ���Զ�ˢ��ʱ, ���ٵȴ�����bank����ʱ��ˢ��, ����ˢ�½���������¼���֮ǰ����

ע�⣺
ǿ��ˢ�¼������>ˢ�¼��

Э��:
AXIS MASTER

����: �¼�ҫ
����: 2024/04/17
********************************************************************/


module sdram_auto_refresh #(
    parameter real clk_period = 7.0, // ʱ������
    parameter real refresh_itv = 64.0 * 1000.0 * 1000.0 / 4096.0 * 0.8, // ˢ�¼��(��ns��)
    parameter real forced_refresh_itv = 64.0 * 1000.0 * 1000.0 / 4096.0 * 0.9, // ǿ��ˢ�¼��(��ns��)
    parameter integer burst_len = -1, // ͻ������(-1 -> ȫҳ; 1 | 2 | 4 | 8)
    parameter allow_auto_precharge = "true" // �Ƿ������Զ�Ԥ���
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // �Զ�ˢ�¶�ʱ��ʼ(ָʾ)
    input wire start_rfs_timing,
    // ˢ�¿�����������
    output wire rfs_ctrler_running,
    
    // sdram�������������
    input wire[15:0] s_axis_cmd_agent_monitor_data, // {BS(2bit), A10-0(11bit), �����(3bit)}
    input wire s_axis_cmd_agent_monitor_valid,
    input wire s_axis_cmd_agent_monitor_ready,
    
    // �Զ�ˢ��������AXIS
    output wire[15:0] m_axis_rfs_data, // {BS(2bit), A10-0(11bit), �����(3bit)}
    output wire m_axis_rfs_valid,
    input wire m_axis_rfs_ready
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
    localparam integer refresh_itv_p = $floor(refresh_itv / clk_period); // ˢ�¼��������
    localparam integer forced_refresh_itv_p = $floor(forced_refresh_itv / clk_period); // ǿ��ˢ�¼��������
    localparam rw_data_with_auto_precharge = (burst_len == -1) ? "false":allow_auto_precharge; // ʹ�ܶ�д����������Զ�Ԥ���
    // ������߼�����
    localparam CMD_LOGI_BANK_ACTIVE = 3'b000; // ����:����bank
    localparam CMD_LOGI_BANK_PRECHARGE = 3'b001; // ����:Ԥ���bank
    localparam CMD_LOGI_WT_DATA = 3'b010; // ����:д����
    localparam CMD_LOGI_RD_DATA = 3'b011; // ����:������
    localparam CMD_LOGI_AUTO_REFRESH = 3'b101; // ����:�Զ�ˢ��
    // �Զ�ˢ��״̬
    localparam RFS_NOT_START = 2'b00; // ״̬:ˢ��δ��ʼ
    localparam RFS_CMD_PRECHARGE_ALL = 2'b01; // ״̬:����"Ԥ���"����
    localparam RFS_CMD_REFRESH = 2'b10; // ״̬:����"ˢ��"����
    localparam RFS_CMD_ACTIVE = 2'b11; // ״̬:����"����"����
    // ʵ�ַ�ʽ(1 | 2)
    // ��ʽ1 -> Ч�ʸ�, ʱ���, ��Դ��; ��ʽ2 -> Ч�ʵ�, ʱ���, ��Դ��
    localparam integer impl_method = 2;
    
    /**
    bank�����뼤��״̬�ж�
    
    ������뵽sdram������������AXIS����, ������ʵ��bank�����뼤��״̬
    **/
    wire rfs_launched; // �����Զ�ˢ��
    reg[3:0] is_spec_bank_idle; // ����bank�Ƿ�idle
    wire next_all_bank_idle; // ��1clk��ÿ��bank��idle
    wire[3:0] ba_onehot; // �������bank��ַ
    reg[10:0] bank_active_row[3:0]; // bank���������
    reg rfs_launched_d; // �ӳ�1clk�������Զ�ˢ��
    reg all_bank_idle_lateched; // �����ÿ��bank��idle
    reg[3:0] is_spec_bank_active_lateched; // ����ĸ���bank�Ƿ�active
    reg[2:0] bank_active_n; // ����ļ���bank�ĸ���
    reg[10:0] bank_active_row_lateched[3:0]; // �����bank���������
    reg[1:0] bank_active_id_latched[3:0]; // ����ļ���bank���
    
    assign ba_onehot = (s_axis_cmd_agent_monitor_data[15:14] == 2'b00) ? 4'b0001:
        (s_axis_cmd_agent_monitor_data[15:14] == 2'b01) ? 4'b0010:
        (s_axis_cmd_agent_monitor_data[15:14] == 2'b10) ? 4'b0100:
                                                          4'b1000;
    assign next_all_bank_idle = (s_axis_cmd_agent_monitor_valid & s_axis_cmd_agent_monitor_ready) ?
        ((s_axis_cmd_agent_monitor_data[2:0] == CMD_LOGI_BANK_ACTIVE) ? 1'b0: // ����
            (s_axis_cmd_agent_monitor_data[2:0] == CMD_LOGI_BANK_PRECHARGE) ? (s_axis_cmd_agent_monitor_data[13] | (&(is_spec_bank_idle | ba_onehot))): // Ԥ���
            (((s_axis_cmd_agent_monitor_data[2:0] == CMD_LOGI_WT_DATA) | (s_axis_cmd_agent_monitor_data[2:0] == CMD_LOGI_RD_DATA)) & 
                s_axis_cmd_agent_monitor_data[13] & (rw_data_with_auto_precharge == "true")) ? (&(is_spec_bank_idle | ba_onehot)): // ���Զ�Ԥ���Ķ�д
            (&is_spec_bank_idle)):
        (&is_spec_bank_idle);
    
    // ����bank�Ƿ�idle
    // bank���������
    genvar is_spec_bank_idle_i;
    genvar bank_active_row_i;
    generate
        // ����bank�Ƿ�idle
        for(is_spec_bank_idle_i = 0;is_spec_bank_idle_i < 4;is_spec_bank_idle_i = is_spec_bank_idle_i + 1)
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    is_spec_bank_idle[is_spec_bank_idle_i] <= 1'b1;
                else if((s_axis_cmd_agent_monitor_valid & s_axis_cmd_agent_monitor_ready) & 
                    (((s_axis_cmd_agent_monitor_data[2:0] == CMD_LOGI_BANK_ACTIVE) & (s_axis_cmd_agent_monitor_data[15:14] == is_spec_bank_idle_i)) | // ����
                        ((s_axis_cmd_agent_monitor_data[2:0] == CMD_LOGI_BANK_PRECHARGE) & 
                        ((s_axis_cmd_agent_monitor_data[15:14] == is_spec_bank_idle_i) | s_axis_cmd_agent_monitor_data[13])) | // Ԥ���
                        (((s_axis_cmd_agent_monitor_data[2:0] == CMD_LOGI_WT_DATA) | (s_axis_cmd_agent_monitor_data[2:0] == CMD_LOGI_RD_DATA)) & 
                            s_axis_cmd_agent_monitor_data[13] & (s_axis_cmd_agent_monitor_data[15:14] == is_spec_bank_idle_i) & (rw_data_with_auto_precharge == "true")))) // ���Զ�Ԥ���Ķ�д
                    is_spec_bank_idle[is_spec_bank_idle_i] <= s_axis_cmd_agent_monitor_data[2:0] != CMD_LOGI_BANK_ACTIVE;
            end
        end
        
        // bank���������
        for(bank_active_row_i = 0;bank_active_row_i < 4;bank_active_row_i = bank_active_row_i + 1)
        begin
            always @(posedge clk)
            begin
                if((s_axis_cmd_agent_monitor_valid & s_axis_cmd_agent_monitor_ready) & 
                    ((s_axis_cmd_agent_monitor_data[2:0] == CMD_LOGI_BANK_ACTIVE) & (s_axis_cmd_agent_monitor_data[15:14] == bank_active_row_i)))
                    bank_active_row[bank_active_row_i] <= s_axis_cmd_agent_monitor_data[13:3];
            end
        end
    endgenerate
    
    // �����ÿ��bank��idle
    always @(posedge clk)
    begin
        if(rfs_launched)
            all_bank_idle_lateched <= next_all_bank_idle;
    end
    
    // �ӳ�1clk�������Զ�ˢ��
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rfs_launched_d <= 1'b0;
        else
            rfs_launched_d <= rfs_launched;
    end
    
    // ����ĸ���bank�Ƿ�active
    always @(posedge clk)
    begin
        if(rfs_launched_d)
            is_spec_bank_active_lateched <= ~is_spec_bank_idle;
    end
    
    // ����ļ���bank�ĸ���
    always @(posedge clk)
    begin
        if(rfs_launched_d)
        begin
            bank_active_n <= (~is_spec_bank_idle[0]) + (~is_spec_bank_idle[1]) + 
                (~is_spec_bank_idle[2]) + (~is_spec_bank_idle[3]);
        end
    end
    
    // �����bank���������
    generate
        if(impl_method == 1)
        begin
            always @(posedge clk)
            begin
                if(rfs_launched_d)
                begin
                    case(is_spec_bank_idle)
                        4'b0000: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[0], bank_active_row[1], bank_active_row[2], bank_active_row[3]};
                        4'b0001: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[1], bank_active_row[2], bank_active_row[3], 11'dx};
                        4'b0010: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[0], bank_active_row[2], bank_active_row[3], 11'dx};
                        4'b0011: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[2], bank_active_row[3], 11'dx, 11'dx};
                        4'b0100: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[0], bank_active_row[1], bank_active_row[3], 11'dx};
                        4'b0101: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[1], bank_active_row[3], 11'dx, 11'dx};
                        4'b0110: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[0], bank_active_row[3], 11'dx, 11'dx};
                        4'b0111: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[3], 11'dx, 11'dx, 11'dx};
                        4'b1000: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[0], bank_active_row[1], bank_active_row[2], 11'dx};
                        4'b1001: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[1], bank_active_row[2], 11'dx, 11'dx};
                        4'b1010: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[0], bank_active_row[2], 11'dx, 11'dx};
                        4'b1011: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[2], 11'dx, 11'dx, 11'dx};
                        4'b1100: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[0], bank_active_row[1], 11'dx, 11'dx};
                        4'b1101: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[1], 11'dx, 11'dx, 11'dx};
                        4'b1110: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {bank_active_row[0], 11'dx, 11'dx, 11'dx};
                        4'b1111: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {11'dx, 11'dx, 11'dx, 11'dx};
                        default: {bank_active_row_lateched[0], bank_active_row_lateched[1], bank_active_row_lateched[2], bank_active_row_lateched[3]} <= 
                            {11'dx, 11'dx, 11'dx, 11'dx};
                    endcase
                end
            end
        end
        else
        begin
            always @(posedge clk)
            begin
                if(rfs_launched_d)
                    {bank_active_row_lateched[3], bank_active_row_lateched[2], bank_active_row_lateched[1], bank_active_row_lateched[0]} <= 
                        {bank_active_row[3], bank_active_row[2], bank_active_row[1], bank_active_row[0]};
            end
        end
    endgenerate
    
    // ����ļ���bank���
    always @(posedge clk)
    begin
        if(rfs_launched_d)
        begin
            case(is_spec_bank_idle)
                4'b0000: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b00, 2'b01, 2'b10, 2'b11};
                4'b0001: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b01, 2'b10, 2'b11, 2'bxx};
                4'b0010: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b00, 2'b10, 2'b11, 2'bxx};
                4'b0011: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b10, 2'b11, 2'bxx, 2'bxx};
                4'b0100: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b00, 2'b01, 2'b11, 2'bxx};
                4'b0101: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b01, 2'b11, 2'bxx, 2'bxx};
                4'b0110: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b00, 2'b11, 2'bxx, 2'bxx};
                4'b0111: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b11, 2'bxx, 2'bxx, 2'bxx};
                4'b1000: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b00, 2'b01, 2'b10, 2'bxx};
                4'b1001: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b01, 2'b10, 2'bxx, 2'bxx};
                4'b1010: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b00, 2'b10, 2'bxx, 2'bxx};
                4'b1011: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b10, 2'bxx, 2'bxx, 2'bxx};
                4'b1100: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b00, 2'b01, 2'bxx, 2'bxx};
                4'b1101: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b01, 2'bxx, 2'bxx, 2'bxx};
                4'b1110: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'b00, 2'bxx, 2'bxx, 2'bxx};
                4'b1111: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'bxx, 2'bxx, 2'bxx, 2'bxx};
                default: {bank_active_id_latched[0], bank_active_id_latched[1], bank_active_id_latched[2], bank_active_id_latched[3]} <= 
                    {2'bxx, 2'bxx, 2'bxx, 2'bxx};
            endcase
        end
    end
    
    /** �Զ�ˢ�¼����� **/
    reg rfs_cnt_en; // �Զ�ˢ�¼�����ʹ��
    reg[clogb2(forced_refresh_itv_p-1):0] rfs_cnt; // �Զ�ˢ�¼�����
    reg rfs_alarm; // �Զ�ˢ��Ԥ��(��־)
    reg forced_rfs_start; // ��ʼǿ���Զ�ˢ��(ָʾ)
    
    assign rfs_launched = (rfs_alarm & next_all_bank_idle) | forced_rfs_start;
    
    // �Զ�ˢ�¼�����ʹ��
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rfs_cnt_en <= 1'b0;
        else if(~rfs_cnt_en)
            rfs_cnt_en <= start_rfs_timing;
    end
    // �Զ�ˢ�¼�����
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rfs_cnt <= 0;
        else if(rfs_launched_d) // ��1��������Ҳ����ν
            rfs_cnt <= 0;
        else if(rfs_cnt_en)
            rfs_cnt <= (rfs_cnt == (forced_refresh_itv_p - 1)) ? 0:(rfs_cnt + 1);
    end
    // �Զ�ˢ��Ԥ��(��־)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rfs_alarm <= 1'b0;
        else if(rfs_launched)
            rfs_alarm <= 1'b0;
        else if(~rfs_alarm)
            rfs_alarm <= rfs_cnt == (refresh_itv_p - 1);
    end
    // ��ʼǿ���Զ�ˢ��(ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            forced_rfs_start <= 1'b0;
        else
            forced_rfs_start <= rfs_cnt == (forced_refresh_itv_p - 1);
    end
    
    /** �Զ�ˢ�����̿��� **/
    reg[1:0] rfs_sts; // �Զ�ˢ�µĵ�ǰ״̬
    reg[2:0] active_cnt; // ����bank������
    reg[2:0] active_cnt_add1; // ����bank������ + 1
    reg rfs_ctrler_running_reg; // ˢ�¿�����������
    
    assign rfs_ctrler_running = rfs_ctrler_running_reg;
    
    // �Զ�ˢ�µĵ�ǰ״̬
    // ����bank������
    // ˢ�¿�����������
    generate
        if(impl_method == 1)
        begin
            // �Զ�ˢ�µĵ�ǰ״̬
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rfs_sts <= RFS_NOT_START;
                else
                begin
                    case(rfs_sts)
                        RFS_NOT_START: // ״̬:ˢ��δ��ʼ
                            if(rfs_launched)
                                rfs_sts <= next_all_bank_idle ? RFS_CMD_REFRESH: // -> ״̬:����"ˢ��"����
                                    RFS_CMD_PRECHARGE_ALL; // -> ״̬:����"Ԥ���"����
                        RFS_CMD_PRECHARGE_ALL: // ״̬:����"Ԥ���"����
                            if(m_axis_rfs_ready)
                                rfs_sts <= RFS_CMD_REFRESH; // -> ״̬:����"ˢ��"����
                        RFS_CMD_REFRESH: // ״̬:����"ˢ��"����
                            if(m_axis_rfs_ready)
                                rfs_sts <= all_bank_idle_lateched ? RFS_NOT_START: // -> ״̬:ˢ��δ��ʼ
                                    RFS_CMD_ACTIVE; // -> ״̬:����"����"����
                        RFS_CMD_ACTIVE: // ״̬:����"����"����
                            if(m_axis_rfs_ready & (active_cnt == bank_active_n))
                                rfs_sts <= RFS_NOT_START; // -> ״̬:ˢ��δ��ʼ
                        default:
                            rfs_sts <= RFS_NOT_START;
                    endcase
                end
            end
            
            // ����bank������
            always @(posedge clk)
            begin
                if((rfs_sts == RFS_CMD_REFRESH) & m_axis_rfs_ready & (~all_bank_idle_lateched))
                    active_cnt <= 3'd1;
                else if((rfs_sts == RFS_CMD_ACTIVE) & m_axis_rfs_ready)
                    active_cnt <= active_cnt + 3'd1;
            end
            
            // ˢ�¿�����������
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rfs_ctrler_running_reg <= 1'b0;
                else
                begin
                    case(rfs_sts)
                        RFS_NOT_START: // ״̬:ˢ��δ��ʼ
                            rfs_ctrler_running_reg <= rfs_launched;
                        RFS_CMD_REFRESH: // ״̬:����"ˢ��"����
                            rfs_ctrler_running_reg <= ~(m_axis_rfs_ready & all_bank_idle_lateched);
                        RFS_CMD_ACTIVE: // ״̬:����"����"����
                            rfs_ctrler_running_reg <= ~(m_axis_rfs_ready & (active_cnt == bank_active_n));
                        default:
                            rfs_ctrler_running_reg <= rfs_ctrler_running_reg;
                    endcase
                end
            end
        end
        else
        begin
            // �Զ�ˢ�µĵ�ǰ״̬
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rfs_sts <= RFS_NOT_START;
                else
                begin
                    case(rfs_sts)
                        RFS_NOT_START: // ״̬:ˢ��δ��ʼ
                            if(rfs_launched)
                                rfs_sts <= next_all_bank_idle ? RFS_CMD_REFRESH: // -> ״̬:����"ˢ��"����
                                    RFS_CMD_PRECHARGE_ALL; // -> ״̬:����"Ԥ���"����
                        RFS_CMD_PRECHARGE_ALL: // ״̬:����"Ԥ���"����
                            if(m_axis_rfs_ready)
                                rfs_sts <= RFS_CMD_REFRESH; // -> ״̬:����"ˢ��"����
                        RFS_CMD_REFRESH: // ״̬:����"ˢ��"����
                            if(m_axis_rfs_ready)
                                rfs_sts <= all_bank_idle_lateched ? RFS_NOT_START: // -> ״̬:ˢ��δ��ʼ
                                    RFS_CMD_ACTIVE; // -> ״̬:����"����"����
                        RFS_CMD_ACTIVE: // ״̬:����"����"����
                            if(active_cnt[2])
                                rfs_sts <= RFS_NOT_START; // -> ״̬:ˢ��δ��ʼ
                        default:
                            rfs_sts <= RFS_NOT_START;
                    endcase
                end
            end
            
            // ����bank������
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    active_cnt <= 3'd0;
                else if((rfs_sts == RFS_CMD_ACTIVE) & (((~is_spec_bank_active_lateched[active_cnt]) | m_axis_rfs_ready) | active_cnt[2]))
                    active_cnt <= active_cnt[2] ? 3'd0:(active_cnt + 3'd1);
            end
            // ����bank������ + 1
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    active_cnt_add1 <= 3'd1;
                else if((rfs_sts == RFS_CMD_ACTIVE) & (((~is_spec_bank_active_lateched[active_cnt]) | m_axis_rfs_ready) | active_cnt[2]))
                    active_cnt_add1 <= active_cnt[2] ? 3'd1:(active_cnt_add1 + 3'd1);
            end
            
            // ˢ�¿�����������
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rfs_ctrler_running_reg <= 1'b0;
                else
                begin
                    case(rfs_sts)
                        RFS_NOT_START: // ״̬:ˢ��δ��ʼ
                            rfs_ctrler_running_reg <= rfs_launched;
                        RFS_CMD_REFRESH: // ״̬:����"ˢ��"����
                            rfs_ctrler_running_reg <= ~(m_axis_rfs_ready & all_bank_idle_lateched);
                        RFS_CMD_ACTIVE: // ״̬:����"����"����
                            rfs_ctrler_running_reg <= ~active_cnt[2];
                        default:
                            rfs_ctrler_running_reg <= rfs_ctrler_running_reg;
                    endcase
                end
            end
        end
    endgenerate
    
    /** �Զ�ˢ��������AXIS **/
    reg[15:0] now_cmd; // ��ǰ����
    reg cmd_valid; // ������Ч
    
    assign m_axis_rfs_data = now_cmd;
    assign m_axis_rfs_valid = cmd_valid;
    
    // ��ǰ����
    // ������Ч
    generate
        if(impl_method == 1)
        begin
            // ��ǰ����
            always @(posedge clk)
            begin
                case(rfs_sts)
                    RFS_NOT_START: // ״̬:ˢ��δ��ʼ
                        now_cmd <= next_all_bank_idle ? {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_AUTO_REFRESH}:
                            {2'bxx, 11'b1_xxxxx_xxxxx, CMD_LOGI_BANK_PRECHARGE};
                    RFS_CMD_PRECHARGE_ALL: // ״̬:����"Ԥ���"����
                        if(m_axis_rfs_ready)
                            now_cmd <= {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_AUTO_REFRESH};
                    RFS_CMD_REFRESH: // ״̬:����"ˢ��"����
                        if(m_axis_rfs_ready)
                            now_cmd <= all_bank_idle_lateched ? 16'dx:
                                {2'b00, bank_active_row_lateched[0], CMD_LOGI_BANK_ACTIVE};
                    RFS_CMD_ACTIVE: // ״̬:����"����"����
                        if(m_axis_rfs_ready)
                            now_cmd <= {bank_active_id_latched[active_cnt[1:0]], bank_active_row_lateched[active_cnt[1:0]], CMD_LOGI_BANK_ACTIVE};
                    default:
                        now_cmd <= now_cmd;
                endcase
            end
            // ������Ч
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    cmd_valid <= 1'b0;
                else
                begin
                    case(rfs_sts)
                        RFS_NOT_START: // ״̬:ˢ��δ��ʼ
                            cmd_valid <= rfs_launched;
                        RFS_CMD_REFRESH: // ״̬:����"ˢ��"����
                            if(m_axis_rfs_ready)
                                cmd_valid <= ~all_bank_idle_lateched;
                        RFS_CMD_ACTIVE: // ״̬:����"����"����
                            if(m_axis_rfs_ready)
                                cmd_valid <= active_cnt != bank_active_n;
                        default:
                            cmd_valid <= cmd_valid;
                    endcase
                end
            end
        end
        else
        begin
            // ��ǰ����
            always @(posedge clk)
            begin
                case(rfs_sts)
                    RFS_NOT_START: // ״̬:ˢ��δ��ʼ
                        now_cmd <= next_all_bank_idle ? {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_AUTO_REFRESH}:
                            {2'bxx, 11'b1_xxxxx_xxxxx, CMD_LOGI_BANK_PRECHARGE};
                    RFS_CMD_PRECHARGE_ALL: // ״̬:����"Ԥ���"����
                        if(m_axis_rfs_ready)
                            now_cmd <= {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_AUTO_REFRESH};
                    RFS_CMD_REFRESH: // ״̬:����"ˢ��"����
                        if(m_axis_rfs_ready)
                            now_cmd <= all_bank_idle_lateched ? 16'dx:
                                {2'b00, bank_active_row_lateched[0], CMD_LOGI_BANK_ACTIVE};
                    RFS_CMD_ACTIVE: // ״̬:����"����"����
                        if(active_cnt[2])
                            now_cmd <= 16'dx;
                        else if((~is_spec_bank_active_lateched[active_cnt]) | m_axis_rfs_ready)
                            now_cmd <= {active_cnt_add1[1:0], bank_active_row_lateched[active_cnt_add1[1:0]], CMD_LOGI_BANK_ACTIVE};
                    default:
                        now_cmd <= now_cmd;
                endcase
            end
            // ������Ч
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    cmd_valid <= 1'b0;
                else
                begin
                    case(rfs_sts)
                        RFS_NOT_START: // ״̬:ˢ��δ��ʼ
                            cmd_valid <= rfs_launched;
                        RFS_CMD_REFRESH: // ״̬:����"ˢ��"����
                            if(m_axis_rfs_ready)
                                cmd_valid <= all_bank_idle_lateched ? 1'b0:is_spec_bank_active_lateched[0];
                        RFS_CMD_ACTIVE: // ״̬:����"����"����
                            if(active_cnt[2])
                                cmd_valid <= 1'b0;
                            else if((~is_spec_bank_active_lateched[active_cnt]) | m_axis_rfs_ready)
                                cmd_valid <= (active_cnt != 3'd3) & is_spec_bank_active_lateched[active_cnt_add1[1:0]];
                        default:
                            cmd_valid <= cmd_valid;
                    endcase
                end
            end
        end
    endgenerate
    
endmodule
