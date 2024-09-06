`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXI�ٲ���

����: 
��AXI�Ķ���ַ/д��ַͨ�������ٲ�

ע�⣺
��

Э��:
FIFO WRITE

����: �¼�ҫ
����: 2024/04/29
********************************************************************/


module axi_arbitrator #(
    parameter integer master_n = 4, // ��������(�����ڷ�Χ[2, 8]��)
    parameter integer arb_itv = 4, // �ٲü��������(�����ڷ�Χ[2, 16]��)
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // �ӻ�AR/AWͨ��
    input wire[52:0] s0_ar_aw_payload, // 0�Ŵӻ��ĸ���
    input wire[52:0] s1_ar_aw_payload, // 1�Ŵӻ��ĸ���
    input wire[52:0] s2_ar_aw_payload, // 2�Ŵӻ��ĸ���
    input wire[52:0] s3_ar_aw_payload, // 3�Ŵӻ��ĸ���
    input wire[52:0] s4_ar_aw_payload, // 4�Ŵӻ��ĸ���
    input wire[52:0] s5_ar_aw_payload, // 5�Ŵӻ��ĸ���
    input wire[52:0] s6_ar_aw_payload, // 6�Ŵӻ��ĸ���
    input wire[52:0] s7_ar_aw_payload, // 7�Ŵӻ��ĸ���
    input wire[7:0] s_ar_aw_valid, // ÿ���ӻ���valid
    output wire[7:0] s_ar_aw_ready, // ÿ���ӻ���ready
    
    // ����AR/AWͨ��
    output wire[52:0] m_ar_aw_payload, // ��������
    output wire[clogb2(master_n-1):0] m_ar_aw_id, // ����id
    output wire m_ar_aw_valid,
    input wire m_ar_aw_ready,
    
    // ��Ȩ�������fifoд�˿�
    output wire grant_mid_fifo_wen,
    input wire grant_mid_fifo_full_n,
    output wire[master_n-1:0] grant_mid_fifo_din_onehot, // ��������
    output wire[clogb2(master_n-1):0] grant_mid_fifo_din_bin // ����������
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
    // ״̬����
    localparam STS_ARB = 2'b00; // ״̬:�ٲ�
    localparam STS_M_TRANS = 2'b01; // ״̬:��AR/AW���񴫵ݸ�����
    localparam STS_ITV = 2'b10; // ״̬:��϶��
    
    /** �ٲ���״̬�� **/
    wire arb_valid; // �ٲý����Ч(ָʾ)
    reg[arb_itv-1:0] arb_itv_cnt; // �ٲü��������
    reg[1:0] arb_now_sts; // ��ǰ״̬
    
    // ��ǰ״̬
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            arb_now_sts <= STS_ARB;
        else
        begin
            # simulation_delay;
            
            case(arb_now_sts)
                STS_ARB: // ״̬:�ٲ�
                    if(arb_valid)
                        arb_now_sts <= STS_M_TRANS; // -> ״̬:��AR/AW���񴫵ݸ�����
                STS_M_TRANS: // ״̬:��AR/AW���񴫵ݸ�����
                    if(m_ar_aw_ready)
                        arb_now_sts <= STS_ITV; // -> ״̬:��϶��
                STS_ITV: // ״̬:��϶��
                    if(arb_itv_cnt[arb_itv-1])
                        arb_now_sts <= STS_ARB; // -> ״̬:�ٲ�
                default:
                    arb_now_sts <= STS_ARB;
            endcase
        end
    end
    
    /** Round-Robin�ٲ��� **/
    wire[master_n-1:0] arb_req; // ����
    wire[master_n-1:0] arb_grant; // ��Ȩ(������)
    wire[clogb2(master_n-1):0] arb_sel; // ѡ��(�൱����Ȩ�Ķ����Ʊ�ʾ)
    
    assign arb_req = ((arb_now_sts == STS_ARB) & grant_mid_fifo_full_n) ? s_ar_aw_valid[master_n-1:0]:{master_n{1'b0}};
    
    // Round-Robin�ٲ���
    round_robin_arbitrator #(
        .chn_n(master_n),
        .simulation_delay(simulation_delay)
    )arbitrator(
        .clk(clk),
        .rst_n(rst_n),
        .req(arb_req),
        .grant(arb_grant),
        .sel(arb_sel),
        .arb_valid(arb_valid)
    );
    
    /** �ӻ�AR/AWͨ�� **/
    wire[52:0] s_ar_aw_payload[7:0]; // �ӻ�����
    reg[master_n-1:0] s_ar_aw_ready_regs; // ÿ���ӻ���ready
    
    assign s_ar_aw_ready = {{(8-master_n){1'b1}}, s_ar_aw_ready_regs};
    
    assign s_ar_aw_payload[0] = s0_ar_aw_payload;
    assign s_ar_aw_payload[1] = s1_ar_aw_payload;
    assign s_ar_aw_payload[2] = s2_ar_aw_payload;
    assign s_ar_aw_payload[3] = s3_ar_aw_payload;
    assign s_ar_aw_payload[4] = s4_ar_aw_payload;
    assign s_ar_aw_payload[5] = s5_ar_aw_payload;
    assign s_ar_aw_payload[6] = s6_ar_aw_payload;
    assign s_ar_aw_payload[7] = s7_ar_aw_payload;
    
    // ÿ���ӻ���ready
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            s_ar_aw_ready_regs <= {master_n{1'b0}};
        else
            # simulation_delay s_ar_aw_ready_regs <= arb_grant;
    end
    
    /** ����AR/AWͨ�� **/
    reg[52:0] m_payload_latched; // �������������
    reg[clogb2(master_n-1):0] arb_sel_latched; // ������ٲ�ѡ��
    reg m_valid; // �������valid
    
    assign m_ar_aw_payload = m_payload_latched;
    assign m_ar_aw_id = arb_sel_latched;
    assign m_ar_aw_valid = m_valid;
    
    // �������������
    always @(posedge clk)
    begin
        if(arb_valid)
            # simulation_delay m_payload_latched <= s_ar_aw_payload[arb_sel];
    end
    // ������ٲ�ѡ��
    always @(posedge clk)
    begin
        if(arb_valid)
            # simulation_delay arb_sel_latched <= arb_sel;
    end
    // �������valid
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            m_valid <= 1'b0;
        else
            # simulation_delay m_valid <= m_valid ? (~m_ar_aw_ready):arb_valid;
    end
    
    /** ��Ȩ�������fifoд�˿� **/
    reg grant_mid_fifo_wen_reg;
    reg[master_n-1:0] grant_mid_fifo_din_onehot_regs;
    reg[clogb2(master_n-1):0] grant_mid_fifo_din_bin_regs;
    
    assign grant_mid_fifo_wen = grant_mid_fifo_wen_reg;
    assign grant_mid_fifo_din_onehot = grant_mid_fifo_din_onehot_regs;
    assign grant_mid_fifo_din_bin = grant_mid_fifo_din_bin_regs;
    
    // ��Ȩ�������fifoдʹ��
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            grant_mid_fifo_wen_reg <= 1'b0;
        else
            # simulation_delay grant_mid_fifo_wen_reg <= arb_valid;
    end
    // ��Ȩ�������fifoд����
    always @(posedge clk)
        # simulation_delay grant_mid_fifo_din_onehot_regs <= arb_grant;
    always @(posedge clk)
        # simulation_delay grant_mid_fifo_din_bin_regs <= arb_sel;
    
    /** �ٲü�������� **/
    // �ٲü��������
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            arb_itv_cnt <= {{(arb_itv-1){1'b0}}, 1'b1};
        else if(arb_now_sts == STS_ITV)
            # simulation_delay arb_itv_cnt <= {arb_itv_cnt[arb_itv-2:0], arb_itv_cnt[arb_itv-1]};
    end
    
endmodule
