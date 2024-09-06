`timescale 1ns / 1ps
/********************************************************************
��ģ��: sdram����/Ԥ����������ģ��

����:
�����û�����, ���д��������ǰ�������ʵļ����Ԥ�������

������ȫҳͻ���������Զ�Ԥ���ʱ, ��ģ���ʹ�ܶ�д����������Զ�Ԥ���

ע�⣺
��

Э��:
AXIS MASTER/SLAVE

����: �¼�ҫ
����: 2024/04/18
********************************************************************/


module sdram_active_precharge_insert #(
    parameter integer burst_len = -1, // ͻ������(-1 -> ȫҳ; 1 | 2 | 4 | 8)
    parameter allow_auto_precharge = "true", // �Ƿ������Զ�Ԥ���
    parameter en_cmd_axis_reg_slice = "true" // �Ƿ�ʹ������AXIS�Ĵ���Ƭ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // �û�����AXIS
    input wire[31:0] s_axis_usr_cmd_data, // {����(5bit), ba(2bit), �е�ַ(11bit), A10-0(11bit), �����(3bit)}
    // �Զ����"ֹͣͻ��"�������ȫҳͻ����Ч
    input wire[8:0] s_axis_usr_cmd_user, // {�Ƿ��Զ����"ֹͣͻ��"����(1bit), ͻ������ - 1(8bit)}
    input wire s_axis_usr_cmd_valid,
    output wire s_axis_usr_cmd_ready,
    
    // ���뼤��/Ԥ�������������AXIS
    output wire[15:0] m_axis_inserted_cmd_data, // {BS(2bit), A10-0(11bit), �����(3bit)}
    output wire[8:0] m_axis_inserted_cmd_user, // {�Ƿ��Զ����"ֹͣͻ��"����(1bit), ͻ������ - 1(8bit)}(����ȫҳͻ����Ч)
    output wire m_axis_inserted_cmd_valid,
    input wire m_axis_inserted_cmd_ready
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
    // ������߼�����
    localparam CMD_LOGI_BANK_ACTIVE = 3'b000; // ����:����bank
    localparam CMD_LOGI_BANK_PRECHARGE = 3'b001; // ����:Ԥ���bank
    localparam CMD_LOGI_WT_DATA = 3'b010; // ����:д����
    localparam CMD_LOGI_RD_DATA = 3'b011; // ����:������
    
    /** ��ѡ������AXIS�Ĵ���Ƭ **/
    wire[31:0] m_axis_usr_cmd_data; // {����(5bit), ba(2bit), �е�ַ(11bit), A10-0(11bit), �����(3bit)}
    wire[8:0] m_axis_usr_cmd_user; // {�Ƿ��Զ����"ֹͣͻ��"����(1bit), ͻ������ - 1(8bit)}
    wire m_axis_usr_cmd_valid;
    wire m_axis_usr_cmd_ready;
    
    axis_reg_slice #(
        .data_width(32),
        .user_width(9),
        .forward_registered(en_cmd_axis_reg_slice),
        .back_registered(en_cmd_axis_reg_slice),
        .en_ready("true"),
        .simulation_delay(0)
    )usr_cmd_axis_reg_slice(
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_data(s_axis_usr_cmd_data),
        .s_axis_keep(),
        .s_axis_user(s_axis_usr_cmd_user),
        .s_axis_last(),
        .s_axis_valid(s_axis_usr_cmd_valid),
        .s_axis_ready(s_axis_usr_cmd_ready),
        .m_axis_data(m_axis_usr_cmd_data),
        .m_axis_keep(),
        .m_axis_user(m_axis_usr_cmd_user),
        .m_axis_last(),
        .m_axis_valid(m_axis_usr_cmd_valid),
        .m_axis_ready(m_axis_usr_cmd_ready)
    );
    
    /**
    bank�����뼤��״̬�ж�
    
    ������뵽���뼤��/Ԥ�������������AXIS, ������ʵ��bank�����뼤��״̬
    **/
    reg[3:0] spec_bank_active; // ����bank�Ƿ񼤻�
    reg[10:0] bank_active_row[3:0]; // ����bank�������
    
    // ����bank�Ƿ񼤻�
    // bank���������
    genvar spec_bank_active_i;
    genvar bank_active_row_i;
    generate
        // ����bank�Ƿ񼤻�
        for(spec_bank_active_i = 0;spec_bank_active_i < 4;spec_bank_active_i = spec_bank_active_i + 1)
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    spec_bank_active[spec_bank_active_i] <= 1'b0;
                else if((m_axis_inserted_cmd_valid & m_axis_inserted_cmd_ready) & 
                    (((m_axis_inserted_cmd_data[2:0] == CMD_LOGI_BANK_ACTIVE) & (m_axis_inserted_cmd_data[15:14] == spec_bank_active_i)) | // ����
                    ((m_axis_inserted_cmd_data[2:0] == CMD_LOGI_BANK_PRECHARGE) & (m_axis_inserted_cmd_data[15:14] == spec_bank_active_i)) | // Ԥ���
                    (((m_axis_inserted_cmd_data[2:0] == CMD_LOGI_WT_DATA) | (m_axis_inserted_cmd_data[2:0] == CMD_LOGI_RD_DATA)) & 
                        m_axis_inserted_cmd_data[13] & (m_axis_inserted_cmd_data[15:14] == spec_bank_active_i) & 
                        (rw_data_with_auto_precharge == "true")))) // ���Զ�Ԥ���Ķ�д
                    spec_bank_active[spec_bank_active_i] <= m_axis_inserted_cmd_data[2:0] == CMD_LOGI_BANK_ACTIVE;
            end
        end
        
        // bank���������
        for(bank_active_row_i = 0;bank_active_row_i < 4;bank_active_row_i = bank_active_row_i + 1)
        begin
            always @(posedge clk)
            begin
                if((m_axis_inserted_cmd_valid & m_axis_inserted_cmd_ready) & 
                    ((m_axis_inserted_cmd_data[2:0] == CMD_LOGI_BANK_ACTIVE) & (m_axis_inserted_cmd_data[15:14] == bank_active_row_i)))
                    bank_active_row[bank_active_row_i] <= m_axis_inserted_cmd_data[13:3];
            end
        end
    endgenerate
    
    /**
    ����/Ԥ�������Ĳ���
    
    ��ʹ�ܶ�д����������Զ�Ԥ���: [Ԥ���] -> [����] -> [��д����]
    ʹ�ܶ�д����������Զ�Ԥ���: [Ԥ���] -> [����] -> ��д����([�Զ�Ԥ���])
    **/
    wire is_rw_cmd; // �Ƿ��д��������
    reg precharge_need; // ��ҪԤ���(��־)
    reg active_need; // ��Ҫ����(��־)
    wire usr_cmd_suspend; // �û�����AXIS�ȴ�
    reg[1:0] insert_stage_cnt; // ����/Ԥ����������׶μ�����
    
    assign m_axis_inserted_cmd_user = m_axis_usr_cmd_user;
    assign m_axis_usr_cmd_ready = m_axis_inserted_cmd_ready & (~usr_cmd_suspend);
    
    assign m_axis_inserted_cmd_data = 
        (insert_stage_cnt == 2'd0) ? {m_axis_usr_cmd_data[26:25], m_axis_usr_cmd_data[13:3], m_axis_usr_cmd_data[2:0]}: // pass
        (insert_stage_cnt == 2'd1) ? {m_axis_usr_cmd_data[26:25], 11'b0_xxxxx_xxxxx, CMD_LOGI_BANK_PRECHARGE}: // Ԥ���
        (insert_stage_cnt == 2'd2) ? {m_axis_usr_cmd_data[26:25], m_axis_usr_cmd_data[24:14], CMD_LOGI_BANK_ACTIVE}: // ����
                                     {m_axis_usr_cmd_data[26:25], (rw_data_with_auto_precharge == "ture") ? m_axis_usr_cmd_data[13]:1'b0, 
                                        m_axis_usr_cmd_data[12:3], m_axis_usr_cmd_data[2:0]}; // ��д����
    
    assign m_axis_inserted_cmd_valid = m_axis_usr_cmd_valid & 
        ((insert_stage_cnt == 2'd0) ? (~is_rw_cmd):
         (insert_stage_cnt == 2'd1) ? precharge_need:
         (insert_stage_cnt == 2'd2) ? active_need:
                                      1'b1);
    
    assign is_rw_cmd = (m_axis_usr_cmd_data[2:0] == CMD_LOGI_WT_DATA) | (m_axis_usr_cmd_data[2:0] == CMD_LOGI_RD_DATA);
    assign usr_cmd_suspend = 
        (insert_stage_cnt == 2'd0) ? is_rw_cmd:
        (insert_stage_cnt == 2'd3) ? 1'b0:
                                     1'b1;
    // ��ҪԤ���(��־)
    always @(posedge clk)
    begin
        if((insert_stage_cnt == 2'd0) & is_rw_cmd)
            precharge_need <= spec_bank_active[m_axis_usr_cmd_data[26:25]] & (bank_active_row[m_axis_usr_cmd_data[26:25]] != m_axis_usr_cmd_data[24:14]);
    end
    
    // ��Ҫ����(��־)
    always @(posedge clk)
    begin
        if((insert_stage_cnt == 2'd0) & is_rw_cmd)
            active_need <= ~(spec_bank_active[m_axis_usr_cmd_data[26:25]] & 
                (bank_active_row[m_axis_usr_cmd_data[26:25]] == m_axis_usr_cmd_data[24:14]));
    end
    
    // ����/Ԥ����������׶μ�����
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            insert_stage_cnt <= 2'd0;
        else if(m_axis_inserted_cmd_ready & m_axis_usr_cmd_valid & ((insert_stage_cnt != 2'd0) | is_rw_cmd))
            insert_stage_cnt <= (insert_stage_cnt == 2'd3) ? 2'd0:(insert_stage_cnt + 2'd1);
    end
    
endmodule
