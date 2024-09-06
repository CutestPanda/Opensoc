`timescale 1ns / 1ps
/********************************************************************
��ģ��: sdram������PHY��

����:
������������д������, �Է���sdramʱ��Ҫ��ķ�ʽ����������
������������
�Ѵ����ʼ�����Զ�ˢ��
�Զ����д�������������ʵļ���/Ԥ�������

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

���������뵽sdram�����������3~6clkʱ��:
    [��1��AXIS�Ĵ���Ƭ1clk] -> [��2��AXIS�Ĵ���Ƭ1clk] -> [��3���Ĵ���Ƭ1clk] -> ��������ж�1clk -> ��д����������ӳٲ���2clk

ע�⣺
һ����˵, �û�����ָ��д����/����������
����ʹ�ܵ�1������AXIS�Ĵ���Ƭ, �Ի����û�����

Э��:
AXIS MASTER/SLAVE
SDRAM MASTER

����: �¼�ҫ
����: 2024/04/14
********************************************************************/


module sdram_phy #(
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
    parameter integer rw_data_buffer_depth = 1024, // ��д����buffer���(512 | 1024 | 2048 | 4096)
    parameter integer burst_len = -1, // ͻ������(-1 -> ȫҳ; 1 | 2 | 4 | 8)
    parameter integer cas_latency = 2, // sdram��Ǳ����ʱ��(2 | 3)
    parameter integer data_width = 32, // ����λ��
    parameter allow_auto_precharge = "true", // �Ƿ������Զ�Ԥ���
    parameter en_cmd_s1_axis_reg_slice = "true", // �Ƿ�ʹ�ܵ�1������AXIS�Ĵ���Ƭ
    parameter en_cmd_s2_axis_reg_slice = "true", // �Ƿ�ʹ�ܵ�2������AXIS�Ĵ���Ƭ
    parameter en_cmd_s3_axis_reg_slice = "true", // �Ƿ�ʹ�ܵ�3������AXIS�Ĵ���Ƭ
    parameter en_imdt_stat_wburst_len = "true", // �Ƿ�ʹ��ʵʱͳ��дͻ������(����ȫҳͻ����Ч)
    parameter en_expt_tip = "false", // �Ƿ�ʹ���쳣ָʾ
    parameter real sdram_if_signal_delay = 2.5 // sdram�ӿ��ź��ӳ�(�����ڷ���)
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // д����AXIS
    input wire[data_width-1:0] s_axis_wt_data,
    input wire[data_width/8-1:0] s_axis_wt_keep,
    input wire s_axis_wt_last,
    input wire s_axis_wt_valid,
    output wire s_axis_wt_ready,
    // ������AXIS
    output wire[data_width-1:0] m_axis_rd_data,
    output wire m_axis_rd_last,
    output wire m_axis_rd_valid,
    input wire m_axis_rd_ready,
    
    // �û�����AXIS
    input wire[31:0] s_axis_usr_cmd_data, // {����(5bit), ba(2bit), �е�ַ(11bit), A10-0(11bit), �����(3bit)}
    // ����ȫҳͻ����Ч, ��ʹ��ʵʱͳ��дͻ������, ����д��������������ָ��ͻ������
    input wire[8:0] s_axis_usr_cmd_user, // {�Ƿ��Զ����"ֹͣͻ��"����(1bit), ͻ������ - 1(8bit)}
    input wire s_axis_usr_cmd_valid,
    output wire s_axis_usr_cmd_ready,
    
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
    output wire[data_width/8-1:0] sdram_dqm, // 1'b0 -> data write/output enable; 1'b1 -> data mask/output disable
	input wire[data_width-1:0] sdram_dq_i,
	output wire[data_width-1:0] sdram_dq_o,
	output wire[data_width-1:0] sdram_dq_t, // 1Ϊ����, 0Ϊ���
    
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

    // ����log2(bit_depth)
    function integer clogb2 (input integer bit_depth);
        integer temp;
    begin
        temp = bit_depth;
        for(clogb2 = -1;temp > 0;clogb2 = clogb2 + 1)
            temp = temp >> 1;
    end
    endfunction
    
    /** �ڲ����� **/
    localparam en_rw_cmd_outstanding = "false"; // �Ƿ����ö�д�����(���ÿ��ܻ���߶�дЧ��)
	localparam sim_mode = "false"; // �Ƿ��ڷ���ģʽ
    
    /** ���� **/
    // ��д��������
    localparam integer RW_CMD_OUTSTANDING = rw_data_buffer_depth / ((burst_len == -1) ? 256:burst_len);
    // ������߼�����
    localparam CMD_LOGI_WT_DATA = 3'b010; // ����:д����
    localparam CMD_LOGI_RD_DATA = 3'b011; // ����:������
    
    /** sdramʱ���� **/
    assign sdram_cke = 1'b1;
    
    // ODDR
	generate
		if(sim_mode == "true")
		begin
			assign sdram_clk = clk;
		end
		else
		begin
			EG_LOGIC_ODDR #(
				.ASYNCRST("ENABLE")
			)oddr_u(
				.q(sdram_clk),
				
				.clk(clk),
				
				.d0(1'b0), // ��������������
				.d1(1'b1), // �½�����������
				
				.rst(~rst_n)
			);
		end
	endgenerate
    
    /** sdram������̬�� **/
    wire[data_width-1:0] sdram_dq_i_inner;
    wire sdram_dq_t_inner; // ��̬�ŷ���(1��ʾ����, 0��ʾ���)
    wire[data_width-1:0] sdram_dq_o_inner;
	
	assign sdram_dq_i_inner = sdram_dq_i;
	assign sdram_dq_o = sdram_dq_o_inner;
	assign sdram_dq_t = {data_width{sdram_dq_t_inner}};
    
    /** sdram���ݻ����� **/
    // д���ݹ���fifo���˿�
    wire wdata_ext_fifo_ren;
    wire wdata_ext_fifo_empty_n;
    wire wdata_ext_fifo_mem_ren;
    wire[clogb2(rw_data_buffer_depth-1):0] wdata_ext_fifo_mem_raddr;
    wire[data_width+data_width/8-1:0] wdata_ext_fifo_mem_dout; // {keep(data_width/8 bit), data(data_width bit)}
    // �����ݹ���fifoд�˿�
    wire rdata_ext_fifo_wen;
    wire rdata_ext_fifo_full_n;
    wire rdata_ext_fifo_mem_wen;
    wire[clogb2(rw_data_buffer_depth-1):0] rdata_ext_fifo_mem_waddr;
    wire[data_width:0] rdata_ext_fifo_mem_din; // {last(1bit), data(data_width bit)}
    // ʵʱͳ��дͻ������fifo���˿�
    wire imdt_stat_wburst_len_fifo_ren;
    wire[7:0] imdt_stat_wburst_len_fifo_dout;
    
    sdram_data_buffer #(
        .rw_data_buffer_depth(rw_data_buffer_depth),
        .en_imdt_stat_wburst_len(en_imdt_stat_wburst_len),
        .burst_len(burst_len),
        .data_width(data_width)
    )sdram_data_buffer_u(
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_wt_data(s_axis_wt_data),
        .s_axis_wt_keep(s_axis_wt_keep),
        .s_axis_wt_last(s_axis_wt_last),
        .s_axis_wt_valid(s_axis_wt_valid),
        .s_axis_wt_ready(s_axis_wt_ready),
        .m_axis_rd_data(m_axis_rd_data),
        .m_axis_rd_last(m_axis_rd_last),
        .m_axis_rd_valid(m_axis_rd_valid),
        .m_axis_rd_ready(m_axis_rd_ready),
        .wdata_ext_fifo_ren(wdata_ext_fifo_ren),
        .wdata_ext_fifo_empty_n(wdata_ext_fifo_empty_n),
        .wdata_ext_fifo_mem_ren(wdata_ext_fifo_mem_ren),
        .wdata_ext_fifo_mem_raddr(wdata_ext_fifo_mem_raddr),
        .wdata_ext_fifo_mem_dout(wdata_ext_fifo_mem_dout),
        .rdata_ext_fifo_wen(rdata_ext_fifo_wen),
        .rdata_ext_fifo_full_n(rdata_ext_fifo_full_n),
        .rdata_ext_fifo_mem_wen(rdata_ext_fifo_mem_wen),
        .rdata_ext_fifo_mem_waddr(rdata_ext_fifo_mem_waddr),
        .rdata_ext_fifo_mem_din(rdata_ext_fifo_mem_din),
        .imdt_stat_wburst_len_fifo_ren(imdt_stat_wburst_len_fifo_ren),
        .imdt_stat_wburst_len_fifo_dout(imdt_stat_wburst_len_fifo_dout)
    );
    
    /** sdram����/Ԥ����������ģ�� **/
    // ���뼤��/Ԥ�������������AXIS
    wire[15:0] m_axis_inserted_cmd_data; // {BS(2bit), A10-0(11bit), �����(3bit)}
    // �Զ����"ֹͣͻ��"�������ȫҳͻ����Ч
    wire[8:0] m_axis_inserted_cmd_user; // {�Ƿ��Զ����"ֹͣͻ��"����(1bit), ͻ������ - 1(8bit)}
    wire m_axis_inserted_cmd_valid;
    wire m_axis_inserted_cmd_ready;
    
    sdram_active_precharge_insert #(
        .burst_len(burst_len),
        .allow_auto_precharge(allow_auto_precharge),
        .en_cmd_axis_reg_slice(en_cmd_s1_axis_reg_slice)
    )sdram_active_precharge_insert_u(
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_usr_cmd_data(s_axis_usr_cmd_data),
        .s_axis_usr_cmd_user(s_axis_usr_cmd_user),
        .s_axis_usr_cmd_valid(s_axis_usr_cmd_valid),
        .s_axis_usr_cmd_ready(s_axis_usr_cmd_ready),
        .m_axis_inserted_cmd_data(m_axis_inserted_cmd_data),
        .m_axis_inserted_cmd_user(m_axis_inserted_cmd_user),
        .m_axis_inserted_cmd_valid(m_axis_inserted_cmd_valid),
        .m_axis_inserted_cmd_ready(m_axis_inserted_cmd_ready)
    );
    
    /** ��ѡ������AXIS�Ĵ���Ƭ **/
    // �û�����AXIS
    wire[15:0] m_axis_usr_cmd_data; // {BS(2bit), A10-0(11bit), �����(3bit)}
    wire[8:0] m_axis_usr_cmd_user; // {�Ƿ��Զ����"ֹͣͻ��"����(1bit), ͻ������ - 1(8bit)}
    wire m_axis_usr_cmd_valid;
    wire m_axis_usr_cmd_ready;
    
    axis_reg_slice #(
        .data_width(16),
        .user_width(9),
        .forward_registered(en_cmd_s2_axis_reg_slice),
        .back_registered(en_cmd_s2_axis_reg_slice),
        .en_ready("true"),
        .simulation_delay(0)
    )inserted_cmd_axis_reg_slice(
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_data(m_axis_inserted_cmd_data),
        .s_axis_keep(),
        .s_axis_user(m_axis_inserted_cmd_user),
        .s_axis_last(),
        .s_axis_valid(m_axis_inserted_cmd_valid),
        .s_axis_ready(m_axis_inserted_cmd_ready),
        .m_axis_data(m_axis_usr_cmd_data),
        .m_axis_keep(),
        .m_axis_user(m_axis_usr_cmd_user),
        .m_axis_last(),
        .m_axis_valid(m_axis_usr_cmd_valid),
        .m_axis_ready(m_axis_usr_cmd_ready)
    );
    
    /** sdram������� **/
    // ������������AXIS
    wire[15:0] s_axis_cmd_agent_data; // {BS(2bit), A10-0(11bit), �����(3bit)}
    // �Զ����"ֹͣͻ��"�������ȫҳͻ����Ч
    wire[8:0] s_axis_cmd_agent_user; // {�Ƿ��Զ����"ֹͣͻ��"����(1bit), ͻ������ - 1(8bit)}
    wire s_axis_cmd_agent_valid;
    wire s_axis_cmd_agent_ready;
    // sdram������
    wire sdram_cs_n_p2;
    wire sdram_ras_n_p2;
    wire sdram_cas_n_p2;
    wire sdram_we_n_p2;
    wire[1:0] sdram_ba_p2;
    wire[10:0] sdram_addr_p2;
    reg sdram_cs_n_p1;
    reg sdram_ras_n_p1;
    reg sdram_cas_n_p1;
    reg sdram_we_n_p1;
    reg[1:0] sdram_ba_p1;
    reg[10:0] sdram_addr_p1;
    reg sdram_cs_n_now;
    reg sdram_ras_n_now;
    reg sdram_cas_n_now;
    reg sdram_we_n_now;
    reg[1:0] sdram_ba_now;
    reg[10:0] sdram_addr_now;
    // ͻ����Ϣ
    wire new_burst_start; // ͻ����ʼָʾ
    wire is_write_burst; // �Ƿ�дͻ��
    wire[7:0] new_burst_len; // ͻ������ - 1
    
    assign {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = {sdram_cs_n_now, sdram_ras_n_now, sdram_cas_n_now, sdram_we_n_now};
    assign {sdram_ba, sdram_addr} = {sdram_ba_now, sdram_addr_now};
    
    axis_sdram_cmd_agent #(
        .cas_latency(cas_latency),
        .clk_period(clk_period),
        .tRC(tRC),
        .tRRD(tRRD),
        .tRCD(tRCD),
        .tRP(tRP),
        .tRAS_min(tRAS_min),
        .tRAS_max(tRAS_max),
        .tWR(tWR),
        .burst_len(burst_len),
        .allow_auto_precharge(allow_auto_precharge),
        .en_cmd_axis_reg_slice(en_cmd_s3_axis_reg_slice),
        .en_expt_tip(en_expt_tip)
    )axis_sdram_cmd_agent_u(
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_cmd_data(s_axis_cmd_agent_data),
        .s_axis_cmd_user(s_axis_cmd_agent_user),
        .s_axis_cmd_valid(s_axis_cmd_agent_valid),
        .s_axis_cmd_ready(s_axis_cmd_agent_ready),
        .sdram_cs_n(sdram_cs_n_p2),
        .sdram_ras_n(sdram_ras_n_p2),
        .sdram_cas_n(sdram_cas_n_p2),
        .sdram_we_n(sdram_we_n_p2),
        .sdram_ba(sdram_ba_p2),
        .sdram_addr(sdram_addr_p2),
        .new_burst_start(new_burst_start),
        .is_write_burst(is_write_burst),
        .new_burst_len(new_burst_len),
        .pcg_spcf_idle_bank_err(pcg_spcf_idle_bank_err),
        .pcg_spcf_bank_tot_err(pcg_spcf_bank_tot_err),
        .rw_idle_bank_err(rw_idle_bank_err),
        .rfs_with_act_banks_err(rfs_with_act_banks_err),
        .illegal_logic_cmd_err(illegal_logic_cmd_err),
        .rw_cross_line_err(rw_cross_line_err)
    );
    
    // ��sdram�����������������ӳ�2clk, �Բ���д����
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            {sdram_cs_n_p1, sdram_ras_n_p1, sdram_cas_n_p1, sdram_we_n_p1} <= 4'b0111;
        else
            {sdram_cs_n_p1, sdram_ras_n_p1, sdram_cas_n_p1, sdram_we_n_p1} <= {sdram_cs_n_p2, sdram_ras_n_p2, sdram_cas_n_p2, sdram_we_n_p2};
    end
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            {sdram_cs_n_now, sdram_ras_n_now, sdram_cas_n_now, sdram_we_n_now} <= 4'b0111;
        else
            {sdram_cs_n_now, sdram_ras_n_now, sdram_cas_n_now, sdram_we_n_now} <= # sdram_if_signal_delay {sdram_cs_n_p1, sdram_ras_n_p1, sdram_cas_n_p1, sdram_we_n_p1};
    end
    
    always @(posedge clk)
        {sdram_ba_p1, sdram_addr_p1} <= {sdram_ba_p2, sdram_addr_p2};
    always @(posedge clk)
        {sdram_ba_now, sdram_addr_now} <= # sdram_if_signal_delay {sdram_ba_p1, sdram_addr_p1};
    
    /** sdram���ݴ��� **/
    sdram_data_agent #(
        .rw_data_buffer_depth(rw_data_buffer_depth),
        .burst_len(burst_len),
        .cas_latency(cas_latency),
        .data_width(data_width),
        .en_expt_tip(en_expt_tip),
        .sdram_if_signal_delay(sdram_if_signal_delay)
    )sdram_data_agent_u(
        .clk(clk),
        .rst_n(rst_n),
        .new_burst_start(new_burst_start),
        .is_write_burst(is_write_burst),
        .new_burst_len(new_burst_len),
        .wdata_ext_fifo_ren(wdata_ext_fifo_ren),
        .wdata_ext_fifo_empty_n(wdata_ext_fifo_empty_n),
        .wdata_ext_fifo_mem_ren(wdata_ext_fifo_mem_ren),
        .wdata_ext_fifo_mem_raddr(wdata_ext_fifo_mem_raddr),
        .wdata_ext_fifo_mem_dout(wdata_ext_fifo_mem_dout),
        .rdata_ext_fifo_wen(rdata_ext_fifo_wen),
        .rdata_ext_fifo_full_n(rdata_ext_fifo_full_n),
        .rdata_ext_fifo_mem_wen(rdata_ext_fifo_mem_wen),
        .rdata_ext_fifo_mem_waddr(rdata_ext_fifo_mem_waddr),
        .rdata_ext_fifo_mem_din(rdata_ext_fifo_mem_din),
        .sdram_dqm(sdram_dqm),
        .sdram_dq_i(sdram_dq_i_inner),
        .sdram_dq_t(sdram_dq_t_inner),
        .sdram_dq_o(sdram_dq_o_inner),
        .ld_when_wdata_ext_fifo_empty_err(ld_when_wdata_ext_fifo_empty_err),
        .st_when_rdata_ext_fifo_full_err(st_when_rdata_ext_fifo_full_err)
    );
    
    /** sdram��ʼ������������ **/
    // ��ʼ������AXIS
    wire[15:0] m_axis_init_cmd_data; // {BS(2bit), A10-0(11bit), �����(3bit)}
    wire m_axis_init_cmd_valid;
    wire m_axis_init_cmd_ready;
    // ��ʼ������������(��־)
    wire init_cmd_all_recv;
    
    sdram_init_cmd_gen #(
        .clk_period(clk_period),
        .burst_len(burst_len),
        .cas_latency(cas_latency)
    )sdram_init_cmd_gen_u(
        .clk(clk),
        .rst_n(rst_n),
        .init_cmd_all_recv(init_cmd_all_recv),
        .m_axis_init_cmd_data(m_axis_init_cmd_data),
        .m_axis_init_cmd_valid(m_axis_init_cmd_valid),
        .m_axis_init_cmd_ready(m_axis_init_cmd_ready)
    );
    
    /** sdram�Զ�ˢ�¿����� **/
    // �Զ�ˢ�¶�ʱ��ʼ(ָʾ)
    wire start_rfs_timing;
    // �Զ�ˢ��������AXIS
    wire[15:0] m_axis_rfs_data; // {BS(2bit), A10-0(11bit), �����(3bit)}
    wire m_axis_rfs_valid;
    wire m_axis_rfs_ready;
    // ˢ�¿�����������
    wire rfs_ctrler_running;
    
    sdram_auto_refresh #(
        .clk_period(clk_period),
        .refresh_itv(refresh_itv),
        .forced_refresh_itv(forced_refresh_itv),
        .allow_auto_precharge(allow_auto_precharge),
        .burst_len(burst_len)
    )sdram_auto_refresh_u(
        .clk(clk),
        .rst_n(rst_n),
        .start_rfs_timing(start_rfs_timing),
        .rfs_ctrler_running(rfs_ctrler_running),
        .s_axis_cmd_agent_monitor_data(s_axis_cmd_agent_data),
        .s_axis_cmd_agent_monitor_valid(s_axis_cmd_agent_valid),
        .s_axis_cmd_agent_monitor_ready(s_axis_cmd_agent_ready),
        .m_axis_rfs_data(m_axis_rfs_data),
        .m_axis_rfs_valid(m_axis_rfs_valid),
        .m_axis_rfs_ready(m_axis_rfs_ready)
    );
    
    /** ˢ�¼���� **/
    sdram_rfs_monitor #(
        .clk_period(clk_period),
        .max_refresh_itv(max_refresh_itv),
        .en_expt_tip(en_expt_tip)
    )sdram_rfs_monitor_u(
        .clk(clk),
        .rst_n(rst_n),
        .start_rfs_timing(start_rfs_timing),
        .sdram_cs_n(sdram_cs_n_p2),
        .sdram_ras_n(sdram_ras_n_p2),
        .sdram_cas_n(sdram_cas_n_p2),
        .sdram_we_n(sdram_we_n_p2),
        .rfs_timeout(rfs_timeout)
    );
    
    /**
    ��ʼ��/�Զ�ˢ��/�û�����AXISѡͨ
    
    �Զ�ˢ�µ����ȼ�����ߵ�, һ��ˢ�¿�����������, ���߿���Ȩ���������Զ�ˢ��
    �Զ�д������������⴦��: ��֤����д��������ʱд���ݹ���fifo�ǿ�, ��֤��������������ʱ�����ݹ���fifo����
    **/
    wire rd_wt_cmd_ready; // ��д�������(��־)
    reg[clogb2(RW_CMD_OUTSTANDING):0] wtrans_buffered; // �ѻ����д�������
    reg wtrans_ready; // ׼���ý���д����
    reg[clogb2(RW_CMD_OUTSTANDING):0] rtrans_launched; // �������Ķ��������
    reg rtrans_ready; // ׼���ý��ܶ�����
    
    assign s_axis_cmd_agent_data = rfs_ctrler_running ? m_axis_rfs_data:
        (init_cmd_all_recv ? m_axis_usr_cmd_data:m_axis_init_cmd_data);
    assign s_axis_cmd_agent_user = ((en_imdt_stat_wburst_len == "true") & (burst_len == -1)) ? 
        ((m_axis_usr_cmd_data[2:0] == CMD_LOGI_WT_DATA) ? {m_axis_usr_cmd_user[8], imdt_stat_wburst_len_fifo_dout}:m_axis_usr_cmd_user):
            m_axis_usr_cmd_user;
    assign s_axis_cmd_agent_valid = rfs_ctrler_running ? m_axis_rfs_valid:
        (init_cmd_all_recv ? (m_axis_usr_cmd_valid & rd_wt_cmd_ready):m_axis_init_cmd_valid);
    assign m_axis_usr_cmd_ready = (~rfs_ctrler_running) & init_cmd_all_recv & s_axis_cmd_agent_ready & rd_wt_cmd_ready;
    assign m_axis_init_cmd_ready = (~rfs_ctrler_running) & (~init_cmd_all_recv) & s_axis_cmd_agent_ready;
    assign m_axis_rfs_ready = s_axis_cmd_agent_ready;
    
    assign rd_wt_cmd_ready = (m_axis_usr_cmd_data[2:0] == CMD_LOGI_WT_DATA) ? (wtrans_ready & ((en_rw_cmd_outstanding == "true") | wdata_ext_fifo_empty_n)):
                             (m_axis_usr_cmd_data[2:0] == CMD_LOGI_RD_DATA) ? (rtrans_ready & ((en_rw_cmd_outstanding == "true") | rdata_ext_fifo_full_n)):
                                                                              1'b1;
    
    assign imdt_stat_wburst_len_fifo_ren = ((en_imdt_stat_wburst_len == "true") & (burst_len == -1)) ? 
        (m_axis_usr_cmd_valid & m_axis_usr_cmd_ready & (m_axis_usr_cmd_data[2:0] == CMD_LOGI_WT_DATA)):1'b0;
    
    // �ѻ����д�������
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wtrans_buffered <= 0;
        else if((s_axis_wt_valid & s_axis_wt_ready & s_axis_wt_last) ^ (m_axis_usr_cmd_valid & m_axis_usr_cmd_ready & (m_axis_usr_cmd_data[2:0] == CMD_LOGI_WT_DATA)))
            wtrans_buffered <= (s_axis_wt_valid & s_axis_wt_ready & s_axis_wt_last) ? (wtrans_buffered + 1):(wtrans_buffered - 1);
    end
    // ׼���ý���д����
    generate
        if(en_rw_cmd_outstanding == "true")
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wtrans_ready <= 1'b0;
                else if((s_axis_wt_valid & s_axis_wt_ready & s_axis_wt_last) ^ (m_axis_usr_cmd_valid & m_axis_usr_cmd_ready & (m_axis_usr_cmd_data[2:0] == CMD_LOGI_WT_DATA)))
                    wtrans_ready <= (s_axis_wt_valid & s_axis_wt_ready & s_axis_wt_last) ? 1'b1:(wtrans_buffered != 1);
            end
        end
        else
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wtrans_ready <= 1'b1;
                else
                    wtrans_ready <= wtrans_ready ? (~(m_axis_usr_cmd_valid & m_axis_usr_cmd_ready & (m_axis_usr_cmd_data[2:0] == CMD_LOGI_WT_DATA))):wdata_ext_fifo_ren;
            end
        end
    endgenerate
    
    // �������Ķ��������
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rtrans_launched <= 0;
        else if((m_axis_rd_valid & m_axis_rd_ready & m_axis_rd_last) ^ (m_axis_usr_cmd_valid & m_axis_usr_cmd_ready & (m_axis_usr_cmd_data[2:0] == CMD_LOGI_RD_DATA)))
            rtrans_launched <= (m_axis_rd_valid & m_axis_rd_ready & m_axis_rd_last) ? (rtrans_launched - 1):(rtrans_launched + 1);
    end
    // ׼���ý��ܶ�����
    generate
        if(en_rw_cmd_outstanding == "true")
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rtrans_ready <= 1'b1;
                else if((m_axis_rd_valid & m_axis_rd_ready & m_axis_rd_last) ^ (m_axis_usr_cmd_valid & m_axis_usr_cmd_ready & (m_axis_usr_cmd_data[2:0] == CMD_LOGI_RD_DATA)))
                    rtrans_ready <= (m_axis_rd_valid & m_axis_rd_ready & m_axis_rd_last) ? 1'b1:(rtrans_launched != (RW_CMD_OUTSTANDING - 1));
            end
        end
        else
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rtrans_ready <= 1'b1;
                else
                    rtrans_ready <= rtrans_ready ? (~(m_axis_usr_cmd_valid & m_axis_usr_cmd_ready & (m_axis_usr_cmd_data[2:0] == CMD_LOGI_RD_DATA))):rdata_ext_fifo_wen;
            end
        end
    endgenerate
    
endmodule
