`timescale 1ns / 1ps
/********************************************************************
��ģ��: sdram��ʼ������������

����:
�ȴ�250us -> ������bankԤ��� -> ����ģʽ�Ĵ��� -> ˢ��2��

Э��:
AXIS MASTER

����: �¼�ҫ
����: 2024/04/17
********************************************************************/


module sdram_init_cmd_gen #(
    parameter real clk_period = 7.0, // ʱ������
    parameter integer burst_len = -1, // ͻ������(-1 -> ȫҳ; 1 | 2 | 4 | 8)
    parameter integer cas_latency = 2 // sdram��Ǳ����ʱ��(2 | 3)
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // ��ʼ������������(��־)
    output wire init_cmd_all_recv,

    // ����AXIS
    output wire[15:0] m_axis_init_cmd_data, // {BS(2bit), A10-0(11bit), �����(3bit)}
    output wire m_axis_init_cmd_valid,
    input wire m_axis_init_cmd_ready
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
    localparam integer RST_WAIT_P = $ceil(250000.0 / clk_period); // ��λ��ȴ�������
    // ��ʼ��״̬
    localparam RST_WAITING = 3'b000; // ״̬:��λ�ȴ�
    localparam INIT_CMD_PRECHARGE = 3'b001; // ״̬:����"Ԥ���"����
    localparam INIT_CMD_MR_SET = 3'b010; // ״̬:����"����ģʽ�Ĵ���"����
    localparam INIT_CMD_NOP = 3'b011; // ״̬:����"NOP"����
    localparam INIT_CMD_REFRESH_0 = 3'b100; // ״̬:���͵�1��"�Զ�ˢ��"����
    localparam INIT_CMD_REFRESH_1 = 3'b101; // ״̬:���͵�2��"�Զ�ˢ��"����
    localparam INIT_OKAY = 3'b110; // ״̬:��ʼ�����
    // ������߼�����
    localparam CMD_LOGI_BANK_PRECHARGE = 3'b001; // ����:Ԥ���bank
    localparam CMD_LOGI_MR_SET = 3'b100; // ����:����ģʽ�Ĵ���
    localparam CMD_LOGI_AUTO_REFRESH = 3'b101; // ����:�Զ�ˢ��
    localparam CMD_LOGI_NOP = 3'b111; // ����:�ղ���
    // ����ģʽ�Ĵ���ʱ������
    localparam CMD_FOR_MR_SET = {
        3'b000, // reserved
        1'b0, // burst
        2'b00, // normal
        // CAS# LA
        (cas_latency == 2) ? 3'b010:
                             3'b011,
        1'b0, // sequential
        // burst length
        (burst_len == 1) ? 3'b000:
        (burst_len == 2) ? 3'b001:
        (burst_len == 4) ? 3'b010:
        (burst_len == 8) ? 3'b011:
                           3'b111,
        CMD_LOGI_MR_SET};
    // ��ʼ�����������
    localparam integer init_cmd_n = 8;
    
    /** ��λ�ȴ� **/
    reg[clogb2(RST_WAIT_P-1):0] rst_wait_cnt; // ��λ�ȴ�������
    reg rst_stable; // ��λ�ȶ�(��־)
    
    // ��λ�ȴ�������
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rst_wait_cnt <= 0;
        else if(~rst_stable)
            rst_wait_cnt <= rst_wait_cnt + 1;
    end
    // ��λ�ȶ�(��־)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rst_stable <= 1'b0;
        else if(~rst_stable)
            rst_stable <= rst_wait_cnt == (RST_WAIT_P-1);
    end
    
    /** ��ʼ���������� **/
    reg[15:0] next_init_cmd; // ��һ��ʼ������(����߼�)
    reg[clogb2(init_cmd_n):0] next_init_cmd_id; // ��һ��ʼ��������
    reg[15:0] now_cmd; // ��ǰ����
    reg init_cmd_all_recv_reg; // ��ʼ������������(��־)
    reg cmd_valid; // ������Ч
    
    assign m_axis_init_cmd_data = now_cmd;
    assign m_axis_init_cmd_valid = cmd_valid;
    
    assign init_cmd_all_recv = init_cmd_all_recv_reg;
    
    // ��һ��ʼ������(����߼�)
    always @(*)
    begin
        case(next_init_cmd_id)
            0: next_init_cmd = {2'bxx, 11'b1_xxxxx_xxxxx, CMD_LOGI_BANK_PRECHARGE}; // Ԥ�������
            1: next_init_cmd = CMD_FOR_MR_SET; // ����ģʽ�Ĵ���
            2: next_init_cmd = {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_NOP}; // NOP
            3: next_init_cmd = {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_NOP}; // NOP
            4: next_init_cmd = {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_NOP}; // NOP
            5: next_init_cmd = {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_NOP}; // NOP
            6: next_init_cmd = {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_AUTO_REFRESH}; // �Զ�ˢ��
            7: next_init_cmd = {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_AUTO_REFRESH}; // �Զ�ˢ��
            default: next_init_cmd = {2'bxx, 11'bx_xxxxx_xxxxx, CMD_LOGI_NOP}; // NOP
        endcase
    end
    
    // ��һ��ʼ��������
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            next_init_cmd_id <= 1;
        else if(m_axis_init_cmd_valid & m_axis_init_cmd_ready)
            next_init_cmd_id <= next_init_cmd_id + 1;
    end
    // ��ǰ����
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            now_cmd <= {2'bxx, 11'b1_xxxxx_xxxxx, CMD_LOGI_BANK_PRECHARGE};
        else if(m_axis_init_cmd_valid & m_axis_init_cmd_ready)
            now_cmd <= next_init_cmd;
    end
    // ������Ч
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            cmd_valid <= 1'b0;
        else
            cmd_valid <= cmd_valid ? (~((next_init_cmd_id == init_cmd_n) & m_axis_init_cmd_ready)):(rst_stable & (~init_cmd_all_recv_reg));
    end
    
    // ��ʼ������������(��־)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            init_cmd_all_recv_reg <= 1'b0;
        else if(~init_cmd_all_recv_reg)
            init_cmd_all_recv_reg <= m_axis_init_cmd_valid & m_axis_init_cmd_ready & (next_init_cmd_id == init_cmd_n);
    end
    
endmodule
