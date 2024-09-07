`timescale 1ns / 1ps
/********************************************************************
��ģ��: APB-SDIO

����:
1.��ѡ��Ӳ����ʼ��ģ��
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
�����  ��Ӧ����        ����
 CMD17    R1             �����
 CMD18    R1             ����
 CMD24    R1             ����д
 CMD25    R1             ���д
 CMD12    R1b         ֹͣ��ǰ����
4.�Ĵ���->
    ƫ����  |    ����                     |   ��д����    |                ��ע
    0x00    0:����fifo�Ƿ���                    R
            1:������fifo�Ƿ��                  R
            2:д����fifo�Ƿ���                  R
    0x04    5~0:�����                         W             д�üĴ���ʱ���������fifoдʹ��
            15~8:���ζ�д�Ŀ����-1            W              д�üĴ���ʱ���������fifoдʹ��
    0x08    31~0:�������                      W
    0x0C    31~0:������                        R             ���üĴ���ʱ�����������fifo��ʹ��
    0x10    31~0:д����                        W             д�üĴ���ʱ�����д����fifoдʹ��
    0x14    0:SDIOȫ���ж�ʹ��                  W
            8:SDIO�������ж�ʹ��                W
            9:SDIOд�����ж�ʹ��                W
            10:SDIO�������������ж�ʹ��     W
    0x18    0:SDIOȫ���жϱ�־                 RWC              �����жϷ�����������жϱ�־
            8:SDIO�������жϱ�־                R
            9:SDIOд�����жϱ�־                R
            10:SDIO�������������жϱ�־     R
    0x1C    31~0:��Ӧ[119:88]                  R
    0x20    31~0:��Ӧ[87:56]                   R
    0x24    31~0:��Ӧ[55:24]                   R
    0x28    23~0:��Ӧ[23:0]                    R
            24:�Ƿ���Ӧ                      R
            25:CRC����                         R
            26:���ճ�ʱ                        R
    0x2C    0:�������Ƿ����                   R
            5~1:�����ݷ��ؽ��                 R
            10~8:д���ݷ���״̬��Ϣ            R
            16:�Ƿ�����sdioʱ��               W
            17:�Ƿ���������ģʽ               W
            27~18:sdioʱ�ӷ�Ƶϵ��            W                  ��Ƶ�� = (��Ƶϵ�� + 1) * 2
   [0x30,   0:��ʼ��ʼ����־                  W               д�üĴ������Ҹ�λΪ1ʱ��ʼ��ʼ��
    ��ʹ��   1:��ʼ��ģ���Ƿ����              R
    Ӳ��     23~8:RCA                         R                    ��ʼ�����[18:3]
    ��ʼ��   24:��ʼ���Ƿ�ɹ�                 R                    ��ʼ�����[0]
    ʱ����]  25:�Ƿ�֧��SD2.0                  R                    ��ʼ�����[1]
            26:�Ƿ��������                   R                     ��ʼ�����[2]

ע�⣺
SD�����СΪ512�ֽ�
R2��Ӧ��136bit, �������͵���Ӧ��48bit
CMD6��Ҳ������������ж�

Э��:
APB SLAVE
SDIO MASTER

����: �¼�ҫ
����: 2024/01/24
********************************************************************/


module apb_sdio #(
    parameter en_hw_init = "false", // ʹ��Ӳ����ʼ��
    parameter integer init_acmd41_try_n = 20, // ��ʼ��ʱ����ACMD41����ĳ��Դ���(����<=32, ��ʹ��Ӳ����ʼ��ʱ��Ч)
    parameter integer resp_timeout = 64, // ��Ӧ��ʱ������
    parameter integer resp_with_busy_timeout = 64, // ��Ӧ��busy��ʱ������
    parameter integer read_timeout = -1, // ����ʱ������
    parameter en_resp_rd_crc = "false", // ʹ����Ӧ�Ͷ�����CRC
	parameter en_sdio_clken = "true", // �Ƿ�ʹ��sdioʱ��ʱ��ʹ��
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire resetn,
    
    // APB�ӻ��ӿ�
    input wire[31:0] paddr,
    input wire psel,
    input wire penable,
    input wire pwrite,
    input wire[31:0] pwdata,
    output wire pready_out, // const -> 1'b1
    output wire[31:0] prdata_out,
    output wire pslverr_out, // const -> 1'b0
    
    // sdio�ӿ�(��̬���߷���ѡ�� -> 0��ʾ���, 1��ʾ����)
    // clk
    output wire sdio_clk,
    // cmd
    output wire sdio_cmd_t,
    output wire sdio_cmd_o,
    input wire sdio_cmd_i,
    // data
    output wire[3:0] sdio_data_t,
    output wire[3:0] sdio_data_o,
    input wire[3:0] sdio_data_i,
    
    // �ж�
    output wire itr
);
    
    /** ����fifo(���Ϊ1����) **/
    // д�˿�
    wire cmd_fifo_wen;
    reg cmd_fifo_full;
    wire[45:0] cmd_fifo_din;
    // ���˿�
    wire cmd_fifo_ren;
    reg cmd_fifo_empty_n;
    reg[45:0] cmd_fifo_dout;
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            cmd_fifo_full <= 1'b0;
        else
            # simulation_delay cmd_fifo_full <= cmd_fifo_full ? (~cmd_fifo_ren):cmd_fifo_wen;
    end
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            cmd_fifo_empty_n <= 1'b0;
        else
            # simulation_delay cmd_fifo_empty_n <= cmd_fifo_empty_n ? (~cmd_fifo_ren):cmd_fifo_wen;
    end
    
    always @(posedge clk)
    begin
        if((~cmd_fifo_full) & cmd_fifo_wen)
            # simulation_delay cmd_fifo_dout <= cmd_fifo_din;
    end
    
    /** ������fifo **/
    // д�˿�
    wire rdata_fifo_wen;
    wire rdata_fifo_full_n;
    wire[31:0] rdata_fifo_din;
    // ���˿�
    wire rdata_fifo_ren;
    wire rdata_fifo_empty;
    wire[31:0] rdata_fifo_dout;
    
    ram_fifo_wrapper #(
        .fwft_mode("true"),
		.use_fifo9k("true"),
        .ram_type("bram_9k"),
        .en_bram_reg("false"),
        .fifo_depth(2048),
        .fifo_data_width(32),
        .full_assert_polarity("low"),
        .empty_assert_polarity("high"),
        .almost_full_assert_polarity("no"),
        .almost_empty_assert_polarity("no"),
        .en_data_cnt("false"),
        .almost_full_th(),
        .almost_empty_th(),
        .simulation_delay(simulation_delay)
    )rdata_fifo(
        .clk(clk),
        .rst_n(resetn),
        .fifo_wen(rdata_fifo_wen),
        .fifo_din(rdata_fifo_din),
        .fifo_full_n(rdata_fifo_full_n),
        .fifo_ren(rdata_fifo_ren),
        .fifo_dout(rdata_fifo_dout),
        .fifo_empty(rdata_fifo_empty)
    );
    
    /** д����fifo **/
    // д�˿�
    wire wdata_fifo_wen;
    wire wdata_fifo_full;
    wire[31:0] wdata_fifo_din;
    // ���˿�
    wire wdata_fifo_ren;
    wire wdata_fifo_empty_n;
    wire[31:0] wdata_fifo_dout;
    
    ram_fifo_wrapper #(
        .fwft_mode("true"),
        .use_fifo9k("true"),
        .ram_type("bram_9k"),
        .en_bram_reg("false"),
        .fifo_depth(2048),
        .fifo_data_width(32),
        .full_assert_polarity("high"),
        .empty_assert_polarity("low"),
        .almost_full_assert_polarity("no"),
        .almost_empty_assert_polarity("no"),
        .en_data_cnt("false"),
        .almost_full_th(),
        .almost_empty_th(),
        .simulation_delay(simulation_delay)
    )wdata_fifo(
        .clk(clk),
        .rst_n(resetn),
        .fifo_wen(wdata_fifo_wen),
        .fifo_din(wdata_fifo_din),
        .fifo_full(wdata_fifo_full),
        .fifo_ren(wdata_fifo_ren),
        .fifo_dout(wdata_fifo_dout),
        .fifo_empty_n(wdata_fifo_empty_n)
    );

    /** ����/״̬�Ĵ����ӿ� **/
    // ������״̬
    wire sdio_ctrler_idle;
    // ����������ʱ����
    wire en_sdio_clk; // ����sdioʱ��(��λʱ����Ϊ0)
    wire[9:0] div_rate; // ��Ƶϵ��(��Ƶ�� = (��Ƶϵ�� + 1) * 2)
    wire en_wide_sdio; // ��������ģʽ
    // ��ʼ��ģ�����
    wire init_start; // ��ʼ��ʼ������(ָʾ)
    wire init_idle; // ��ʼ��ģ�����(��־)
    // ��ӦAXIS
    wire[119:0] s_axis_resp_data; // 48bit��Ӧ -> {�����(6bit), ����(32bit)}, 136bit��Ӧ -> {����(120bit)}
    wire[2:0] s_axis_resp_user; // {���ճ�ʱ(1bit), CRC����(1bit), �Ƿ���Ӧ(1bit)}
    wire s_axis_resp_valid;
    // ��ʼ�����AXIS
    wire[23:0] m_axis_init_res_data; // {����(5bit), RCA(16bit), �Ƿ��������(1bit), �Ƿ�֧��SD2.0(1bit), �Ƿ�ɹ�(1bit)}
    wire m_axis_init_res_valid;
    // �����ݷ��ؽ��AXIS
    wire[7:0] s_axis_rd_sts_data; // {����(3bit), ����ʱ(1bit), У����(4bit)}
    wire s_axis_rd_sts_valid;
    // д����״̬����AXIS
    wire[7:0] s_axis_wt_sts_data; // {����(5bit), ״̬��Ϣ(3bit)}
    wire s_axis_wt_sts_valid;
    // �жϿ���
    wire rdata_itr_org_pulse; // ������ԭʼ�ж�����
    wire wdata_itr_org_pulse; // д����ԭʼ�ж�����
    wire common_itr_org_pulse; // �������������ж�����
    wire rdata_itr_en; // �������ж�ʹ��
    wire wdata_itr_en; // д�����ж�ʹ��
    wire common_itr_en; // �������������ж�ʹ��
    wire global_org_itr_pulse; // ȫ��ԭʼ�ж�����
    
    sdio_regs_interface #(
        .simulation_delay(simulation_delay)
    )sdio_regs_interface_u(
        .clk(clk),
        .resetn(resetn),
        .paddr(paddr),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .pready_out(pready_out),
        .prdata_out(prdata_out),
        .pslverr_out(pslverr_out),
        .cmd_fifo_wen(cmd_fifo_wen),
        .cmd_fifo_full(cmd_fifo_full),
        .cmd_fifo_din(cmd_fifo_din),
        .rdata_fifo_ren(rdata_fifo_ren),
        .rdata_fifo_empty(rdata_fifo_empty),
        .rdata_fifo_dout(rdata_fifo_dout),
        .wdata_fifo_wen(wdata_fifo_wen),
        .wdata_fifo_full(wdata_fifo_full),
        .wdata_fifo_din(wdata_fifo_din),
        .sdio_ctrler_idle(sdio_ctrler_idle),
        .en_sdio_clk(en_sdio_clk),
        .div_rate(div_rate),
        .en_wide_sdio(en_wide_sdio),
        .init_start(init_start),
        .init_idle(init_idle),
        .s_axis_resp_data(s_axis_resp_data),
        .s_axis_resp_user(s_axis_resp_user),
        .s_axis_resp_valid(s_axis_resp_valid),
        .s_axis_init_res_data(m_axis_init_res_data),
        .s_axis_init_res_valid(m_axis_init_res_valid),
        .s_axis_rd_sts_data(s_axis_rd_sts_data),
        .s_axis_rd_sts_valid(s_axis_rd_sts_valid),
        .s_axis_wt_sts_data(s_axis_wt_sts_data),
        .s_axis_wt_sts_valid(s_axis_wt_sts_valid),
        .rdata_itr_org_pulse(rdata_itr_org_pulse),
        .wdata_itr_org_pulse(wdata_itr_org_pulse),
        .common_itr_org_pulse(common_itr_org_pulse),
        .rdata_itr_en(rdata_itr_en),
        .wdata_itr_en(wdata_itr_en),
        .common_itr_en(common_itr_en),
        .global_org_itr_pulse(global_org_itr_pulse)
    );
    
    /** �жϷ����� **/
    // ������״̬
    wire sdio_ctrler_done;
    wire[1:0] sdio_ctrler_rw_type_done;
    
    sdio_itr_generator #(
        .simulation_delay(simulation_delay)
    )sdio_itr_generator_u(
        .clk(clk),
        .resetn(resetn),
        .sdio_ctrler_done(sdio_ctrler_done),
        .sdio_ctrler_rw_type_done(sdio_ctrler_rw_type_done),
        .rdata_itr_org_pulse(rdata_itr_org_pulse),
        .wdata_itr_org_pulse(wdata_itr_org_pulse),
        .common_itr_org_pulse(common_itr_org_pulse),
        .rdata_itr_en(rdata_itr_en),
        .wdata_itr_en(wdata_itr_en),
        .common_itr_en(common_itr_en),
        .global_org_itr_pulse(global_org_itr_pulse),
        .itr(itr)
    );
    
    /** SDIO��SD�������� **/
    wire sdio_d0_t;
    wire sdio_d0_o;
    wire sdio_d0_i;
    wire sdio_d1_t;
    wire sdio_d1_o;
    wire sdio_d1_i;
    wire sdio_d2_t;
    wire sdio_d2_o;
    wire sdio_d2_i;
    wire sdio_d3_t;
    wire sdio_d3_o;
    wire sdio_d3_i;
    
    assign sdio_data_t = {sdio_d3_t, sdio_d2_t, sdio_d1_t, sdio_d0_t};
    assign sdio_data_o = {sdio_d3_o, sdio_d2_o, sdio_d1_o, sdio_d0_o};
    assign {sdio_d3_i, sdio_d2_i, sdio_d1_i, sdio_d0_i} = sdio_data_i;
	
    generate
        if(en_hw_init == "true")
            sd_card_ctrler #(
                .init_acmd41_try_n(init_acmd41_try_n),
                .resp_timeout(resp_timeout),
                .resp_with_busy_timeout(resp_with_busy_timeout),
                .read_timeout(read_timeout),
                .en_resp_rd_crc(en_resp_rd_crc),
				.en_sdio_clken(en_sdio_clken),
				.en_resp("false"),
                .simulation_delay(simulation_delay)
            )sd_card_ctrler_u(
                .clk(clk),
                .resetn(resetn),
                .en_sdio_clk(en_sdio_clk),
                .div_rate(div_rate),
                .en_wide_sdio(en_wide_sdio),
                .init_start(init_start),
                .init_idle(init_idle),
                .init_done(), // not care
                .s_axis_cmd_data({2'b00, cmd_fifo_dout[37:0]}),
                .s_axis_cmd_user({8'd0, cmd_fifo_dout[45:38]}),
                .s_axis_cmd_valid(cmd_fifo_empty_n),
                .s_axis_cmd_ready(cmd_fifo_ren),
                .m_axis_resp_data(s_axis_resp_data),
                .m_axis_resp_user(s_axis_resp_user),
                .m_axis_resp_valid(s_axis_resp_valid),
                .m_axis_resp_ready(1'b1),
                .m_axis_init_res_data(m_axis_init_res_data),
                .m_axis_init_res_valid(m_axis_init_res_valid),
                .s_axis_wt_data(wdata_fifo_dout),
                .s_axis_wt_valid(wdata_fifo_empty_n),
                .s_axis_wt_ready(wdata_fifo_ren),
                .m_axis_rd_data(rdata_fifo_din),
                .m_axis_rd_last(), // not care
                .m_axis_rd_valid(rdata_fifo_wen),
                .m_axis_rd_ready(rdata_fifo_full_n),
                .m_axis_rd_sts_data(s_axis_rd_sts_data),
                .m_axis_rd_sts_valid(s_axis_rd_sts_valid),
                .m_axis_wt_sts_data(s_axis_wt_sts_data),
                .m_axis_wt_sts_valid(s_axis_wt_sts_valid),
                .sdio_ctrler_idle(sdio_ctrler_idle),
                .sdio_ctrler_start(), // not care
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
        else
            sdio_ctrler #(
                .resp_timeout(resp_timeout),
                .resp_with_busy_timeout(resp_with_busy_timeout),
                .read_timeout(read_timeout),
                .en_resp_rd_crc(en_resp_rd_crc),
                .simulation_delay(simulation_delay)
            )sdio_ctrler_u(
                .clk(clk),
                .resetn(resetn),
                .en_sdio_clk(en_sdio_clk),
                .div_rate(div_rate),
                .en_wide_sdio(en_wide_sdio),
                .s_axis_cmd_data({2'b00, cmd_fifo_dout[37:0]}),
                .s_axis_cmd_user({8'd0, cmd_fifo_dout[45:38]}),
                .s_axis_cmd_valid(cmd_fifo_empty_n),
                .s_axis_cmd_ready(cmd_fifo_ren),
                .m_axis_resp_data(s_axis_resp_data),
                .m_axis_resp_user(s_axis_resp_user),
                .m_axis_resp_valid(s_axis_resp_valid),
                .m_axis_resp_ready(1'b1),
                .s_axis_wt_data(wdata_fifo_dout),
                .s_axis_wt_valid(wdata_fifo_empty_n),
                .s_axis_wt_ready(wdata_fifo_ren),
                .m_axis_rd_data(rdata_fifo_din),
                .m_axis_rd_last(), // not care
                .m_axis_rd_valid(rdata_fifo_wen),
                .m_axis_rd_ready(rdata_fifo_full_n),
                .m_axis_rd_sts_data(s_axis_rd_sts_data),
                .m_axis_rd_sts_valid(s_axis_rd_sts_valid),
                .m_axis_wt_sts_data(s_axis_wt_sts_data),
                .m_axis_wt_sts_valid(s_axis_wt_sts_valid),
                .sdio_ctrler_idle(sdio_ctrler_idle),
                .sdio_ctrler_start(), // not care
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
    endgenerate
	
endmodule
