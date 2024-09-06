`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXI-SDRAM

����: 
32λ��ַ/��������
֧�ַǶ��봫��

143MHz(ʱ������7ns)�´���Ϊ483.13MB/s, ����������Ϊ84.55%

ע�⣺
��֧��INCRͻ������
��֧��խ������
sdramͻ�����͹̶�Ϊȫҳ

���·ǼĴ������ ->
    AXI�ӻ��Ķ�����ͨ��: s_axi_rlast, s_axi_rvalid
    AXI�ӻ���д����ͨ��: s_axi_wready
    AXI�ӻ���д��Ӧͨ��: s_axi_bvalid

Э��:
AXI SLAVE
SDRAM MASTER

����: �¼�ҫ
����: 2024/05/01
********************************************************************/


module axi_sdram #(
    parameter arb_algorithm = "round-robin", // ��д�ٲ��㷨("round-robin" | "fixed-r" | "fixed-w")
    parameter en_unaligned_transfer = "false", // �Ƿ�����Ƕ��봫��
    parameter real clk_period = 7.0, // ʱ������
    parameter real refresh_itv = 64.0 * 1000.0 * 1000.0 / 4096.0 * 0.8, // ˢ�¼��(��ns��)
    parameter real forced_refresh_itv = 64.0 * 1000.0 * 1000.0 / 4096.0 * 0.9, // ǿ��ˢ�¼��(��ns��)
    parameter real max_refresh_itv = 64.0 * 1000.0 * 1000.0 / 4096.0, // ���ˢ�¼��(��ns��)
    parameter real tRC = 70.0, // (����ĳ��bank -> ����ͬһbank)��(ˢ�����ʱ��)����Сʱ��Ҫ��
    parameter real tRRD = 14.0, // (����ĳ��bank -> ���ͬbank)����Сʱ��Ҫ��
    parameter real tRCD = 21.0, // (����ĳ��bank -> ��д���bank)����Сʱ��Ҫ��
    parameter real tRP = 21.0, // (Ԥ���ĳ��bank -> ˢ��/����ͬһbank/����ģʽ�Ĵ���)����Сʱ��Ҫ��
    parameter real tRAS_min = 49.0, // (����ĳ��bank -> Ԥ���ͬһbank)����Сʱ��Ҫ��
    parameter real tRAS_max = 100000.0, // (����ĳ��bank -> Ԥ���ͬһbank)�����ʱ��Ҫ��
    parameter real tWR = 2.0, // (дͻ������ -> Ԥ���)����Сʱ��Ҫ��
    parameter integer rw_data_buffer_depth = 512, // ��д����buffer���(512 | 1024 | 2048 | 4096)
    parameter integer cas_latency = 2, // sdram��Ǳ����ʱ��(2 | 3)
    parameter en_cmd_s2_axis_reg_slice = "true", // �Ƿ�ʹ�ܵ�2������AXIS�Ĵ���Ƭ
    parameter en_cmd_s3_axis_reg_slice = "true", // �Ƿ�ʹ�ܵ�3������AXIS�Ĵ���Ƭ
    parameter en_expt_tip = "false", // �Ƿ�ʹ���쳣ָʾ
    parameter real sdram_if_signal_delay = 2.5 // sdram�ӿ��ź��ӳ�(�����ڷ���)
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // AXI�ӻ�
    // AR
    input wire[31:0] s_axi_araddr,
    input wire[7:0] s_axi_arlen,
    input wire[2:0] s_axi_arsize,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    // R
    output wire[31:0] s_axi_rdata,
    output wire s_axi_rlast,
    output wire[1:0] s_axi_rresp, // const -> 2'b00
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    // AW
    input wire[31:0] s_axi_awaddr,
    input wire[7:0] s_axi_awlen,
    input wire[2:0] s_axi_awsize,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    // W
    input wire[31:0] s_axi_wdata,
    input wire[3:0] s_axi_wstrb,
    input wire s_axi_wlast,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    // B
    output wire[1:0] s_axi_bresp, // const -> 2'b00
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    
    // sdramʱ����
    output wire sdram_clk,
    output wire sdram_cke, // const -> 1'b1
    // sdram������
    output wire sdram_cs_n,
    output wire sdram_ras_n,
    output wire sdram_cas_n,
    output wire sdram_we_n,
    output wire[1:0] sdram_ba,
    output wire[10:0] sdram_addr,
    // sdram������
    output wire[3:0] sdram_dqm, // 1'b0 -> data write/output enable; 1'b1 -> data mask/output disable
    input wire[31:0] sdram_dq_i,
	output wire[31:0] sdram_dq_o,
	output wire[31:0] sdram_dq_t, // 1Ϊ����, 0Ϊ���
    
    // �쳣ָʾ
    output wire pcg_spcf_idle_bank_err, // Ԥ�����е��ض�bank(�쳣ָʾ)
    output wire pcg_spcf_bank_tot_err, // Ԥ����ض�bank��ʱ(�쳣ָʾ)
    output wire rw_idle_bank_err, // ��д���е�bank(�쳣ָʾ)
    output wire rfs_with_act_banks_err, // ˢ��ʱ�����Ѽ����bank(�쳣ָʾ)
    output wire illegal_logic_cmd_err, // �Ƿ����߼��������(�쳣ָʾ)
    output wire rw_cross_line_err, // ���еĶ�д����(�쳣ָʾ)
    output wire ld_when_wdata_ext_fifo_empty_err, // ��д���ݹ���fifo��ʱȡ����(�쳣ָʾ)
    output wire st_when_rdata_ext_fifo_full_err, // �ڶ����ݹ���fifo��ʱ������(�쳣ָʾ)
    output wire rfs_timeout // ˢ�³�ʱ
);
    
    /** AXI�ӽӿ� **/
    // SDRAM�û�����AXIS
    wire[31:0] m_axis_usr_cmd_data; // {����(5bit), ba(2bit), �е�ַ(11bit), A10-0(11bit), �����(3bit)}
    wire[8:0] m_axis_usr_cmd_user; // {�Ƿ��Զ����"ֹͣͻ��"����(1bit), ͻ������ - 1(8bit)}
    wire m_axis_usr_cmd_valid;
    wire m_axis_usr_cmd_ready;
    // SDRAMд����AXIS
    wire[31:0] m_axis_wt_data;
    wire[3:0] m_axis_wt_keep;
    wire m_axis_wt_last;
    wire m_axis_wt_valid;
    wire m_axis_wt_ready;
    // SDRAM������AXIS
    wire[31:0] s_axis_rd_data;
    wire s_axis_rd_last;
    wire s_axis_rd_valid;
    wire s_axis_rd_ready;
    
    s_axi_if_for_axi_sdram #(
        .arb_algorithm(arb_algorithm),
        .en_unaligned_transfer(en_unaligned_transfer)
    )s_axi_if(
        .clk(clk),
        .rst_n(rst_n),
        
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arlen(s_axi_arlen),
        .s_axi_arsize(s_axi_arsize),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rlast(s_axi_rlast),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awlen(s_axi_awlen),
        .s_axi_awsize(s_axi_awsize),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wlast(s_axi_wlast),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        
        .m_axis_usr_cmd_data(m_axis_usr_cmd_data),
        .m_axis_usr_cmd_user(m_axis_usr_cmd_user),
        .m_axis_usr_cmd_valid(m_axis_usr_cmd_valid),
        .m_axis_usr_cmd_ready(m_axis_usr_cmd_ready),
        .m_axis_wt_data(m_axis_wt_data),
        .m_axis_wt_keep(m_axis_wt_keep),
        .m_axis_wt_last(m_axis_wt_last),
        .m_axis_wt_valid(m_axis_wt_valid),
        .m_axis_wt_ready(m_axis_wt_ready),
        .s_axis_rd_data(s_axis_rd_data),
        .s_axis_rd_last(s_axis_rd_last),
        .s_axis_rd_valid(s_axis_rd_valid),
        .s_axis_rd_ready(s_axis_rd_ready)
    );
    
    /** SDRAM PHY **/
    // sdramͻ�����͹̶�Ϊȫҳ, ��ʹ��ʵʱͳ��дͻ������, ʹ�ܵ�1������AXIS�Ĵ���Ƭ
    sdram_phy #(
        .clk_period(clk_period),
        .refresh_itv(refresh_itv),
        .forced_refresh_itv(forced_refresh_itv),
        .max_refresh_itv(max_refresh_itv),
        .tRC(tRC),
        .tRRD(tRRD),
        .tRCD(tRCD),
        .tRP(tRP),
        .tRAS_min(tRAS_min),
        .tRAS_max(tRAS_max),
        .tWR(tWR),
        .rw_data_buffer_depth(rw_data_buffer_depth),
        .burst_len(-1),
        .cas_latency(cas_latency),
        .data_width(32),
        .allow_auto_precharge("false"),
        .en_cmd_s1_axis_reg_slice("true"),
        .en_cmd_s2_axis_reg_slice(en_cmd_s2_axis_reg_slice),
        .en_cmd_s3_axis_reg_slice(en_cmd_s3_axis_reg_slice),
        .en_imdt_stat_wburst_len("false"),
        .en_expt_tip(en_expt_tip),
        .sdram_if_signal_delay(sdram_if_signal_delay)
    )sdram_phy_u(
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_wt_data(m_axis_wt_data),
        .s_axis_wt_keep(m_axis_wt_keep),
        .s_axis_wt_last(m_axis_wt_last),
        .s_axis_wt_valid(m_axis_wt_valid),
        .s_axis_wt_ready(m_axis_wt_ready),
        .m_axis_rd_data(s_axis_rd_data),
        .m_axis_rd_last(s_axis_rd_last),
        .m_axis_rd_valid(s_axis_rd_valid),
        .m_axis_rd_ready(s_axis_rd_ready),
        .s_axis_usr_cmd_data(m_axis_usr_cmd_data),
        .s_axis_usr_cmd_user(m_axis_usr_cmd_user),
        .s_axis_usr_cmd_valid(m_axis_usr_cmd_valid),
        .s_axis_usr_cmd_ready(m_axis_usr_cmd_ready),
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n),
        .sdram_we_n(sdram_we_n),
        .sdram_ba(sdram_ba),
        .sdram_addr(sdram_addr),
        .sdram_dqm(sdram_dqm),
        .sdram_dq_i(sdram_dq_i),
		.sdram_dq_o(sdram_dq_o),
		.sdram_dq_t(sdram_dq_t),
        .pcg_spcf_idle_bank_err(pcg_spcf_idle_bank_err),
        .pcg_spcf_bank_tot_err(pcg_spcf_bank_tot_err),
        .rw_idle_bank_err(rw_idle_bank_err),
        .rfs_with_act_banks_err(rfs_with_act_banks_err),
        .illegal_logic_cmd_err(illegal_logic_cmd_err),
        .rw_cross_line_err(rw_cross_line_err),
        .ld_when_wdata_ext_fifo_empty_err(ld_when_wdata_ext_fifo_empty_err),
        .st_when_rdata_ext_fifo_full_err(st_when_rdata_ext_fifo_full_err),
        .rfs_timeout(rfs_timeout)
    );
    
endmodule
