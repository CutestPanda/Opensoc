`timescale 1ns / 1ps
/********************************************************************
��ģ��: SD��������

����:
1.����ʼ��ģ��
2.֧��һ��/����ģʽ
3.֧������->
(1)����/״̬����
�����  ��Ӧ����                      ����
 CMD0     ---                        ��λ
 CMD5     R4                     IO�ӿڵ�ѹ����
 CMD6     R1                     ��ѯ/�л�����
 CMD8     R7             ����SD���ӿڻ���(�ṩ��ѹ��)
 CMD11    R1                        ��ѹ�л�
 CMD55    R1             ָʾ��һ���������ض���Ӧ������
 ACMD41   R3     �����������ݹ�����Ϣ(HCS)����ȡ���������Ĵ���(OCR)
 CMD2     R2                  ��ȡ����ʶ��(CID)
 CMD3     R6                 ��ȡ����Ե�ַ(RCA)
 CMD7     R1b                  ѡ�л�ȡ��ѡ�п�
 CMD16    R1                       ���ÿ��С
 ACMD6    R1                      ��������λ��
(2)��д����
�����  ��Ӧ����           ����
 CMD17    R1             �����
 CMD18    R1             ����
 CMD24    R1             ����д
 CMD25    R1             ���д
 CMD12    R1b         ֹͣ��ǰ����

ע�⣺
SD�����СΪ512�ֽ�
R2��Ӧ��136bit, �������͵���Ӧ��48bit
�������ڳ�ʼ����ɺ���ܽ����û�����

Э��:
AXIS MASTER/SLAVE
SDIO MASTER

����: �¼�ҫ
����: 2024/03/01
********************************************************************/


module sd_card_ctrler #(
    parameter integer init_acmd41_try_n = 20, // ��ʼ��ʱ����ACMD41����ĳ��Դ���(����<=32)
    parameter integer resp_timeout = 64, // ��Ӧ��ʱ������
    parameter integer resp_with_busy_timeout = 64, // ��Ӧ��busy��ʱ������
    parameter integer read_timeout = -1, // ����ʱ������(-1��ʾ���賬ʱ)
    parameter en_resp_rd_crc = "false", // �Ƿ�ʹ����Ӧ�Ͷ�����CRC
    parameter en_sdio_clken = "false", // �Ƿ�ʹ��sdioʱ��ʱ��ʹ��
    parameter en_resp = "false", // �Ƿ�ʹ����ӦAXIS
    parameter real simulation_delay = 1 // ������ʱ
)(
	// ʱ�Ӻ͸�λ
	input wire clk,
	input wire resetn,
    
    // ����ʱ����
    input wire en_sdio_clk, // ����sdioʱ��(��λʱ����Ϊ0), ��ʹ��sdioʱ��ʱ��ʹ�ܿ���
    input wire[9:0] div_rate, // ��Ƶ�� - 1
    input wire en_wide_sdio, // ��������ģʽ
    
    // ��ʼ��ģ�����
    input wire init_start, // ��ʼ��ʼ������(ָʾ)
    output wire init_idle, // ��ʼ��ģ�����(��־)
    output wire init_done, // ��ʼ�����(ָʾ)
    
    // ����AXIS
    input wire[39:0] s_axis_cmd_data, // {����(2bit), �����(6bit), ����(32bit)}
    input wire[15:0] s_axis_cmd_user, // ���ζ�д�Ŀ����-1
    input wire s_axis_cmd_valid,
    output wire s_axis_cmd_ready,
    
    // ��ӦAXIS
    // ��ʹ����ӦAXISʱ����
    output wire[119:0] m_axis_resp_data, // 48bit��Ӧ -> {�����(6bit), ����(32bit)}, 136bit��Ӧ -> {����(120bit)}
    output wire[2:0] m_axis_resp_user, // {��Ӧ��ʱ(1bit), CRC����(1bit), �Ƿ���Ӧ(1bit)}
    output wire m_axis_resp_valid,
    input wire m_axis_resp_ready,
    
    // ��ʼ�����AXIS
    output wire[23:0] m_axis_init_res_data, // {����(5bit), RCA(16bit), �Ƿ��������(1bit), �Ƿ�֧��SD2.0(1bit), �Ƿ�ɹ�(1bit)}
    output wire m_axis_init_res_valid,
    
    // д����AXIS
    input wire[31:0] s_axis_wt_data,
    input wire s_axis_wt_valid,
    output wire s_axis_wt_ready,
    
    // ������AXIS
    output wire[31:0] m_axis_rd_data,
    output wire m_axis_rd_last, // ��ǰ������1������
    output wire m_axis_rd_valid,
    input wire m_axis_rd_ready,
    
    // �����ݷ��ؽ��AXIS
    output wire[7:0] m_axis_rd_sts_data, // {����(3bit), ����ʱ(1bit), У����(4bit)}
    output wire m_axis_rd_sts_valid,
    
    // д����״̬����AXIS
    output wire[7:0] m_axis_wt_sts_data, // {����(5bit), ״̬��Ϣ(3bit)}
    output wire m_axis_wt_sts_valid,
    
    // ������״̬
    output wire sdio_ctrler_idle,
    output wire sdio_ctrler_start,
    output wire sdio_ctrler_done,
    output wire[1:0] sdio_ctrler_rw_type_done, // 2'b00->�Ƕ�д 2'b01->�� 2'b10->д
    
    // sdio�ӿ�(��̬���߷���ѡ�� -> 0��ʾ���, 1��ʾ����)
    // clk
    output wire sdio_clk,
    // cmd
    output wire sdio_cmd_t,
    output wire sdio_cmd_o,
    input wire sdio_cmd_i,
    // data0
    output wire sdio_d0_t,
    output wire sdio_d0_o,
    input wire sdio_d0_i,
    // data1
    output wire sdio_d1_t,
    output wire sdio_d1_o,
    input wire sdio_d1_i,
    // data2
    output wire sdio_d2_t,
    output wire sdio_d2_o,
    input wire sdio_d2_i,
    // data3
    output wire sdio_d3_t,
    output wire sdio_d3_o,
    input wire sdio_d3_i
);

    /** SD����ʼ��ģ�� **/
    // ��ʼ��ģ�����������AXIS
    wire[39:0] m_axis_init_cmd_data; // {����(1bit), �Ƿ���Զ�����(1bit), �����(6bit), ����(32bit)}
    wire m_axis_init_cmd_valid;
    wire m_axis_init_cmd_ready;
    
	sd_card_init #(
		.init_acmd41_try_n(init_acmd41_try_n),
		.simulation_delay(simulation_delay)
	)sd_card_init_u(
		.clk(clk),
		.resetn(resetn),
		
		.en_wide_sdio(en_wide_sdio),
		
		.init_start(init_start),
		.init_idle(init_idle),
		.init_done(init_done),
		
		.m_axis_cmd_data(m_axis_init_cmd_data),
		.m_axis_cmd_valid(m_axis_init_cmd_valid),
		.m_axis_cmd_ready(m_axis_init_cmd_ready),
		
		.s_axis_resp_data(m_axis_resp_data),
		.s_axis_resp_user(m_axis_resp_user),
		.s_axis_resp_valid(m_axis_resp_valid),
		
		.m_axis_init_res_data(m_axis_init_res_data),
		.m_axis_init_res_valid(m_axis_init_res_valid)
	);
    
    /** SDIO������ **/
    // ����AXIS
    wire[39:0] m_axis_cmd_data; // {����(1bit), �Ƿ���Զ�����(1bit), �����(6bit), ����(32bit)}
    wire[15:0] m_axis_cmd_user; // ���ζ�д�Ŀ����-1
    wire m_axis_cmd_valid;
    wire m_axis_cmd_ready;
    // sdioʱ��ʹ��
    reg[3:0] sdio_rst_onehot;
    wire sdio_clken;
	// ��ʼ����ɱ�־
	reg init_finished;
    
    assign sdio_clken = sdio_rst_onehot[3];
    
    // sdioʱ��ʹ��
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sdio_rst_onehot <= 4'b0000;
        else if(~sdio_rst_onehot[3]) // ��������1'b1
            # simulation_delay sdio_rst_onehot <= {sdio_rst_onehot[2:0], 1'b1};
    end
	
	// ��ʼ����ɱ�־
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            init_finished <= 1'b0;
        else if(~init_finished)
            # simulation_delay init_finished <= m_axis_init_res_valid;
    end
    
    sdio_ctrler #(
        .resp_timeout(resp_timeout),
        .resp_with_busy_timeout(resp_with_busy_timeout),
        .read_timeout(read_timeout),
        .en_resp_rd_crc(en_resp_rd_crc),
        .simulation_delay(simulation_delay)
    )sdio_ctrler_u(
        .clk(clk),
        .resetn(resetn),
		
        .en_sdio_clk((en_sdio_clken == "true") ? en_sdio_clk:sdio_clken),
        .div_rate(div_rate),
        .en_wide_sdio(en_wide_sdio),
		
        .s_axis_cmd_data(m_axis_cmd_data),
        .s_axis_cmd_user(m_axis_cmd_user),
        .s_axis_cmd_valid(m_axis_cmd_valid),
        .s_axis_cmd_ready(m_axis_cmd_ready),
		
        .m_axis_resp_data(m_axis_resp_data),
        .m_axis_resp_user(m_axis_resp_user),
        .m_axis_resp_valid(m_axis_resp_valid),
        .m_axis_resp_ready((en_resp == "true") ? (init_finished ? m_axis_resp_ready:1'b1):1'b1),
		
        .s_axis_wt_data(s_axis_wt_data),
        .s_axis_wt_valid(s_axis_wt_valid),
        .s_axis_wt_ready(s_axis_wt_ready),
		
        .m_axis_rd_data(m_axis_rd_data),
        .m_axis_rd_last(m_axis_rd_last),
        .m_axis_rd_valid(m_axis_rd_valid),
        .m_axis_rd_ready(m_axis_rd_ready),
		
        .m_axis_rd_sts_data(m_axis_rd_sts_data),
        .m_axis_rd_sts_valid(m_axis_rd_sts_valid),
		
        .m_axis_wt_sts_data(m_axis_wt_sts_data),
        .m_axis_wt_sts_valid(m_axis_wt_sts_valid),
		
        .sdio_ctrler_idle(sdio_ctrler_idle),
        .sdio_ctrler_start(sdio_ctrler_start),
        .sdio_ctrler_done(sdio_ctrler_done),
        .sdio_ctrler_rw_type_done(sdio_ctrler_rw_type_done),
		
        .sdio_clk(sdio_clk),
        .sdio_cmd_t(sdio_cmd_t),
        .sdio_cmd_o(sdio_cmd_o),
        .sdio_cmd_i(sdio_cmd_i),
        .sdio_d0_t(sdio_d0_t),
        .sdio_d0_o(sdio_d0_o),
        .sdio_d0_i(sdio_d0_i),
        .sdio_d1_t(sdio_d1_t),
        .sdio_d1_o(sdio_d1_o),
        .sdio_d1_i(sdio_d1_i),
        .sdio_d2_t(sdio_d2_t),
        .sdio_d2_o(sdio_d2_o),
        .sdio_d2_i(sdio_d2_i),
        .sdio_d3_t(sdio_d3_t),
        .sdio_d3_o(sdio_d3_o),
        .sdio_d3_i(sdio_d3_i)
    );
    
    /** 
	����AXISѡͨ
	
	��ʼ����� -> ѡͨ����ʼ��ģ��, ��ʼ��δ��� -> ѡͨ���û�
	**/
    assign m_axis_init_cmd_ready = (~init_finished) & m_axis_cmd_ready;
    assign s_axis_cmd_ready = init_finished & m_axis_cmd_ready;
    assign m_axis_cmd_data = init_finished ? {2'b00, s_axis_cmd_data[37:0]}:m_axis_init_cmd_data;
    assign m_axis_cmd_user = s_axis_cmd_user;
    assign m_axis_cmd_valid = init_finished ? s_axis_cmd_valid:m_axis_init_cmd_valid;
    
endmodule
