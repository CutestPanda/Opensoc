`timescale 1ns / 1ps
/********************************************************************
��ģ��: sdramˢ�¼����

����:
����Ƿ��ڹ涨��ʱ������ˢ��sdram

ע�⣺
��

Э��:
��

����: �¼�ҫ
����: 2024/04/17
********************************************************************/


module sdram_rfs_monitor #(
    parameter real clk_period = 7.0, // ʱ������
    parameter real max_refresh_itv = 64.0 * 1000.0 * 1000.0 / 4096.0, // ���ˢ�¼��(��ns��)
    parameter en_expt_tip = "false" // �Ƿ�ʹ���쳣ָʾ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // �Զ�ˢ�¶�ʱ��ʼ(ָʾ)
    output wire start_rfs_timing,
    
    // sdram�����߼��
    input wire sdram_cs_n,
    input wire sdram_ras_n,
    input wire sdram_cas_n,
    input wire sdram_we_n,
    
    // �쳣ָʾ
    output wire rfs_timeout // ˢ�³�ʱ
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
    localparam integer max_refresh_itv_p = $floor(max_refresh_itv / clk_period); // ���ˢ�¼��������
    // ������������(CS_N, RAS_N, CAS_N, WE_N)
    localparam CMD_PHY_AUTO_REFRESH = 4'b0001; // ����:�Զ�ˢ��
    
    /** �Զ�ˢ�¶�ʱ��ʼ(ָʾ) **/
    reg[2:0] init_rfs_cnt; // ��ʼ��ʱˢ�¼�����
    reg start_rfs_timing_reg; // �Զ�ˢ�¶�ʱ��ʼ(ָʾ)
    reg monitor_en; // ���ʹ��
    
    assign start_rfs_timing = start_rfs_timing_reg;
    
    // ��ʼ��ʱˢ�¼�����
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            init_rfs_cnt <= 3'b001;
        else if(({sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} == CMD_PHY_AUTO_REFRESH) & (~init_rfs_cnt[2]))
            init_rfs_cnt <= {init_rfs_cnt[1:0], init_rfs_cnt[2]};
    end
    // �Զ�ˢ�¶�ʱ��ʼ(ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            start_rfs_timing_reg <= 1'b0;
        else
            start_rfs_timing_reg <= ({sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} == CMD_PHY_AUTO_REFRESH) & init_rfs_cnt[1];
    end
    
    // ���ʹ��
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            monitor_en <= 1'b0;
        else if(~monitor_en)
            monitor_en <= start_rfs_timing;
    end
    
    /** ˢ�³�ʱ��� **/
    reg[clogb2(max_refresh_itv_p-1):0] rfs_timeout_cnt; // ˢ�³�ʱ������
    reg rfs_timeout_cnt_suspend; // ˢ�³�ʱ����������
    reg rfs_timeout_reg; // ˢ�³�ʱ
    
    assign rfs_timeout = (en_expt_tip == "true") ? rfs_timeout_reg:1'b0;
    
    // ˢ�³�ʱ������
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rfs_timeout_cnt <= 0;
        else if({sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} == CMD_PHY_AUTO_REFRESH)
            rfs_timeout_cnt <= 0;
        else if(monitor_en & (~rfs_timeout_cnt_suspend))
            rfs_timeout_cnt <= rfs_timeout_cnt + 1;
    end
    // ˢ�³�ʱ����������
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rfs_timeout_cnt_suspend <= 1'b0;
        else if({sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} == CMD_PHY_AUTO_REFRESH)
            rfs_timeout_cnt_suspend <= 1'b0;
        else if(~rfs_timeout_cnt_suspend)
            rfs_timeout_cnt_suspend <= rfs_timeout_cnt == max_refresh_itv_p - 1;
    end
    // ˢ�³�ʱ
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rfs_timeout_reg <= 1'b0;
        else
            rfs_timeout_reg <= rfs_timeout_cnt == max_refresh_itv_p - 1;
    end

endmodule
