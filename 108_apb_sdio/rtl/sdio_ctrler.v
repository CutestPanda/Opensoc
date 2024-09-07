`timescale 1ns / 1ps
/********************************************************************
��ģ��: SDIO������

����:
1.֧��һ��/����ģʽ
2.֧������->
(1)����/״̬����
�����  ��Ӧ����                      ����
 CMD0     ��                         ��λ
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
CMD6��Ҳ������������ж�

Э��:
AXIS MASTER/SLAVE
SDIO MASTER

����: �¼�ҫ
����: 2024/07/30
********************************************************************/


module sdio_ctrler #(
    parameter integer resp_timeout = 64, // ��Ӧ��ʱ������
    parameter integer resp_with_busy_timeout = 64, // ��Ӧ��busy��ʱ������
    parameter integer read_timeout = -1, // ����ʱ������(-1��ʾ���賬ʱ)
    parameter en_resp_rd_crc = "false", // ʹ����Ӧ�Ͷ�����CRC
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire resetn,
    
    // ����ʱ����
    input wire en_sdio_clk, // ����sdioʱ��(��λʱ����Ϊ0)
    input wire[9:0] div_rate, // ��Ƶ�� - 1
    input wire en_wide_sdio, // ��������ģʽ
    
    // ����AXIS
    input wire[39:0] s_axis_cmd_data, // {����(1bit), �Ƿ���Զ�����(1bit), �����(6bit), ����(32bit)}
    input wire[15:0] s_axis_cmd_user, // ���ζ�д�Ŀ����-1
    input wire s_axis_cmd_valid,
    output wire s_axis_cmd_ready,
    
    // ��ӦAXIS
    output wire[119:0] m_axis_resp_data, // 48bit��Ӧ -> {�����(6bit), ����(32bit)}, 136bit��Ӧ -> {����(120bit)}
    output wire[2:0] m_axis_resp_user, // {���ճ�ʱ(1bit), CRC����(1bit), �Ƿ���Ӧ(1bit)}
    output wire m_axis_resp_valid,
    input wire m_axis_resp_ready,
    
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
    // ����״̬��״̬����
    localparam IDLE = 3'b000; // ����
    localparam SEND_CMD = 3'b001; // ��������
    localparam REV_RESP_RD = 3'b010; // ������Ӧ�Ͷ�����
    localparam WT_DATA = 3'b011; // д����
    localparam TRANS_RESP = 3'b100; // ������Ӧ
    
    // �������Ӧ����
    localparam RESP_TYPE_NO_RESP = 2'b00; // ����Ӧ
    localparam RESP_TYPE_COMMON_RESP = 2'b01; // ��ͨ��Ӧ(�����48bit��Ӧ)
    localparam RESP_TYPE_LONG_RESP = 2'b10; // ����Ӧ(136bit��Ӧ, ��R2)
    localparam RESP_TYPE_RESP_WITH_BUSY = 2'b11; // ��busy����Ӧ(��R1b)
    // ����Ķ�д����
    localparam RW_TYPE_NON = 2'b00; // �Ƕ�д
    localparam RW_TYPE_READ = 2'b01; // ��
    localparam RW_TYPE_WRITE = 2'b10; // д
    
    // ����λ��
    localparam CMD_DATA_REGION = 1'b0; // ����λ�ִ���������
    localparam CMD_CRC_END_REGION = 1'b1; // ����λ�ִ���У���������
    
    // ��Ӧλ��
    localparam RESP_BIT_REGION_NOT_CARE = 2'b00; // ��Ӧλ�ִ��ڲ�������
    localparam RESP_BIT_REGION_DATA = 2'b01; // ��Ӧλ�ִ���������
    localparam RESP_BIT_REGION_CRC = 2'b10; // ��Ӧλ�ִ���CRC��
    localparam RESP_BIT_REGION_END = 2'b11; // ��Ӧλ�ִ��ڽ�����
    // ��Ӧ��busy���״̬����
    localparam RESP_BUSY_DETECT_IDLE = 2'b00; // ������ʼ
    localparam RESP_WAIT_BUSY = 2'b01; // ���busy�ź�
    localparam RESP_WAIT_IDLE = 2'b10; // �ȴ��ӻ�idle
    localparam RESP_BUSY_DETECT_FINISH = 2'b11; // ������
    
    // ������������
    localparam RD_REGION_DATA = 2'b00; // �������ִ���������
    localparam RD_REGION_CRC = 2'b01; // �������ִ���У����
    localparam RD_REGION_END = 2'b10; // �������ִ��ڽ�����
    localparam RD_REGION_FINISH = 2'b11; // ���������
    
    // д���ݽ׶�
    localparam WT_STAGE_WAIT = 3'b000; // д�ȴ�
    localparam WT_STAGE_PULL_UP = 3'b001; // ����ǿ�������ߵ�ƽ
    localparam WT_STAGE_START = 3'b010; // ��ʼλ
    localparam WT_STAGE_TRANS = 3'b011; // ����д
    localparam WT_STAGE_CRC_END = 3'b100; // У��ͽ���λ
    localparam WT_STAGE_STS = 3'b101; // ����״̬��Ϣ
    localparam WT_STAGE_WAIT_IDLE = 3'b110; // �ȴ��ӻ�idle
    localparam WT_STAGE_FINISHED = 3'b111; // ���
    // д���ݽ���״̬���صĽ׶�
    localparam WT_STS_WAIT_START = 3'b000; // �ȴ���ʼλ
    localparam WT_STS_B2 = 3'b001; // ���յ�2��״̬λ
    localparam WT_STS_B1 = 3'b010; // ���յ�1��״̬λ
    localparam WT_STS_B0 = 3'b011; // ���յ�0��״̬λ
    localparam WT_STS_END = 3'b100; // ���ս���λ
    
    /** �ڲ����� **/
    localparam integer cmd_pre_p_num = 1; // ÿ������ǰPλ(ǿ�������ߵ�ƽ)����
    localparam integer cmd_itv = 8; // ��������֮��������Сsdioʱ��������
    localparam integer data_wt_wait_p = 2; // д�ȴ���sdioʱ��������(����>=2)
    
    /** sdioʱ�ӷ����� **/
    wire div_cnt_en; // ��Ƶ������(ʹ��)
	wire sdio_in_sample; // SDIO�������ָʾ
	wire sdio_out_upd; // SDIO�������ָʾ
    
    sdio_sck_generator #(
        .div_cnt_width(10),
        .simulation_delay(simulation_delay)
    )sdio_sck_generator_u(
        .clk(clk),
        .resetn(resetn),
		
        .en_sdio_clk(en_sdio_clk),
        .div_rate(div_rate),
		
        .div_cnt_en(div_cnt_en),
		
		.sdio_in_sample(sdio_in_sample),
		.sdio_out_upd(sdio_out_upd),
		
        .sdio_clk(sdio_clk)
    );
    
    /** ����״̬�� **/
    // ������
    reg[2:0] ctrler_status; // ������״̬
    wire cmd_done; // �������(����)
    // ȡ����
    reg cmd_send_started; // ��ʼ������(��־)
    // �����
    reg[1:0] cmd_resp_type; // �������Ӧ����
    reg[1:0] cmd_rw_type; // ����Ķ�д����
    reg cmd_bit_finished; // ��������(��־)
    // ��Ӧ���պͶ�����
    reg resp_received; // ��Ӧ�������(��־)
    reg rd_finished; // �����(��־)
    reg resp_busy_detect_finished; // �����Ӧ��busy���(��־)
    reg resp_timeout_flag; // ��Ӧ��ʱ(��־)
    reg rd_timeout_flag; // ����ʱ(��־)
    // д����
    reg wt_finished; // д���(��־)
    reg wt_axis_not_valid_but_ready_d; // �ӳ�1clk��д����AXIS����ʧ��
    
    // �������(����)
    assign cmd_done = (m_axis_resp_valid & m_axis_resp_ready) | ((ctrler_status == SEND_CMD) & (cmd_resp_type == RESP_TYPE_NO_RESP) & cmd_bit_finished);
    
    // ���������ɵ�sdioʱ��ʹ��
    // sdioʱ��ֻ�ܴ��ڸߵ�ƽʱ�ر�
    assign div_cnt_en = ({m_axis_rd_valid, m_axis_rd_ready} != 2'b10) &  // ������AXIS�ȴ�
        (~wt_axis_not_valid_but_ready_d); // д����AXIS�ȴ�
    
    // ������״̬
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            ctrler_status <= IDLE;
        else
        begin
            # simulation_delay;
            
            case(ctrler_status)
                IDLE: // ״̬:����
                    if(cmd_send_started)
                        ctrler_status <= SEND_CMD;
                SEND_CMD: // ״̬:��������
                    if(cmd_bit_finished)
                        ctrler_status <= (cmd_resp_type == RESP_TYPE_NO_RESP) ? IDLE:REV_RESP_RD;
                REV_RESP_RD: // ״̬:������Ӧ�Ͷ�����
                begin
                    case(cmd_rw_type)
                        RW_TYPE_NON: // �����д����:�Ƕ�д
                            if((cmd_resp_type == RESP_TYPE_RESP_WITH_BUSY) ?
                                (resp_timeout_flag | resp_busy_detect_finished): // ��busy����Ӧ, ��R1b
                                (resp_timeout_flag | resp_received)) // ����busy����Ӧ
                                ctrler_status <= TRANS_RESP;
                        RW_TYPE_READ: // �����д����:��
                            if((read_timeout == -1) ? 
                                (resp_timeout_flag | (resp_received & rd_finished)):
                                (resp_timeout_flag | rd_timeout_flag | (resp_received & rd_finished)))
                                ctrler_status <= TRANS_RESP;
                        RW_TYPE_WRITE: // �����д����:д
                            if(resp_timeout_flag)
                                ctrler_status <= TRANS_RESP;
                            else if(resp_received)
                                ctrler_status <= WT_DATA;
                        default:
                            ctrler_status <= REV_RESP_RD; // hold
                    endcase
                end
                WT_DATA: // ״̬:д����
                    if(wt_finished)
                        ctrler_status <= TRANS_RESP;
                TRANS_RESP: // ״̬:������Ӧ
                    if(m_axis_resp_valid & m_axis_resp_ready)
                         ctrler_status <= IDLE;
                default:
                    ctrler_status <= IDLE;
            endcase
        end
    end
    
    // �ӳ�1clk���ӳ�1clk��д����AXIS����ʧ��
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            wt_axis_not_valid_but_ready_d <= 1'b0;
        else // �ӳ�
            # simulation_delay wt_axis_not_valid_but_ready_d <= {s_axis_wt_valid, s_axis_wt_ready} == 2'b01;
    end
    
    /** ������״̬ **/
    reg cmd_done_d; // �ӳ�1clk���������(����)
    reg[1:0] cmd_rw_type_done_regs; // ���������Ķ�д����
    reg sdio_ctrler_idle_reg; // �����������ź�
    reg sdio_ctrler_start_reg; // ��������ʼ�ź�
    
    assign sdio_ctrler_idle = sdio_ctrler_idle_reg;
    assign sdio_ctrler_start = sdio_ctrler_start_reg;
    assign sdio_ctrler_done = cmd_done_d;
    assign sdio_ctrler_rw_type_done = cmd_rw_type_done_regs;
    
    // �ӳ�1clk���������(����)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            cmd_done_d <= 1'b0;
        else // �ӳ�
            # simulation_delay cmd_done_d <= cmd_done;
    end
    
    // ���������Ķ�д����
    always @(posedge clk)
    begin
        if(cmd_done) // ����
            # simulation_delay cmd_rw_type_done_regs <= cmd_rw_type;
    end
    
    // �����������ź�
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sdio_ctrler_idle_reg <= 1'b1;
        else
            # simulation_delay sdio_ctrler_idle_reg <= sdio_ctrler_idle_reg ? (~sdio_ctrler_start_reg):cmd_done_d;
    end
    // ��������ʼ�ź�
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sdio_ctrler_start_reg <= 1'b0;
        else
            # simulation_delay sdio_ctrler_start_reg <= (ctrler_status == IDLE) & cmd_send_started;
    end
    
    /** ����������� **/
    /*
    ����λ 47+cmd_pre_p_num:48 47 46 45:40   39:8   7:1  0
    ����             P         S  T  �����   ����  CRC7 E
    
    P:ǿ�������ߵ�ƽ
    S:��ʼλ
    T:����λ
    E:����λ
    */
    // ����AXIS
    wire s_axis_cmd_data_ignore_rd; // ����AXIS��data���Ƿ���Զ�����
    wire[5:0] s_axis_cmd_data_cmd; // ����AXIS��data�������
    wire[31:0] s_axis_cmd_data_param; // ����AXIS��data�Ĳ���
    wire[15:0] s_axis_cmd_user_rw_patch_n; // ����AXIS��user�Ķ�д�����-1
    reg s_axis_cmd_ready_reg; // ����AXIS��ready�ź�
    // ������Ϣ
    reg ignore_rd; // �Ƿ���Զ�����(��־)
    reg is_previous_cmd_id55; // ��һ��������CMD55
    reg cmd_with_long_resp; // �����Ƿ������Ӧ(��־)
    reg cmd_with_r3_resp; // �����R3��Ӧ(��־)
    reg[15:0] rw_patch_n; // ��д�����-1
    // ȡ�������
    reg cmd_itv_satisfied; // ����ͼ������Ҫ��(��־)
    reg cmd_fetched; // ��ȡ����(��־)
    // �������̿���
    wire cmd_to_send_en_shift; // ��ǰ�����͵�����(��λʹ��)
    reg sdio_cmd_o_reg; // sdio���������
    reg[(39+cmd_pre_p_num):0] cmd_data; // ����������(��λ�Ĵ���)
    reg[7:0] cmd_crc7_end; // ����У���������(��λ�Ĵ���)
    wire cmd_bit_sending; // ��ǰ���͵�����λ
    reg[5:0] sending_cmd_bit_i; // ��ǰ���������λ���(������)
    reg cmd_actual_sending; // ������ʼ��ʽ��������(���޳���һ��ʼ��Pλ)(��־)
    reg cmd_bit_region; // ����λ��(��־)
    
    assign s_axis_cmd_ready = s_axis_cmd_ready_reg;
    assign sdio_cmd_o = sdio_cmd_o_reg;
    
    assign {s_axis_cmd_data_ignore_rd, s_axis_cmd_data_cmd, s_axis_cmd_data_param} = s_axis_cmd_data[38:0];
    assign s_axis_cmd_user_rw_patch_n = s_axis_cmd_user;
    assign cmd_to_send_en_shift = sdio_out_upd;
    assign cmd_bit_sending = (cmd_bit_region == CMD_DATA_REGION) ? cmd_data[39+cmd_pre_p_num]:cmd_crc7_end[7];
    
    // ����AXIS��ready�ź�
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            s_axis_cmd_ready_reg <= 1'b1;
        else
            # simulation_delay s_axis_cmd_ready_reg <= s_axis_cmd_ready_reg ? (~s_axis_cmd_valid):
                ((ctrler_status == IDLE) & cmd_itv_satisfied & (~cmd_fetched));
    end
    
    // �Ƿ���Զ�����(��־)
    always @(posedge clk)
    begin
        if(s_axis_cmd_valid & s_axis_cmd_ready) // ����
            # simulation_delay ignore_rd <= s_axis_cmd_data_ignore_rd;
    end
    // ��һ��������CMD55
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            is_previous_cmd_id55 <= 1'b0;
        else if(s_axis_cmd_valid & s_axis_cmd_ready) // �ж�������
            # simulation_delay is_previous_cmd_id55 <= s_axis_cmd_data_cmd == 6'd55;
    end
    
    // ��������
    // �����Ƿ������Ӧ(��־)
    always @(posedge clk)
    begin
        if(s_axis_cmd_valid & s_axis_cmd_ready) // ���㲢����
            # simulation_delay cmd_with_long_resp <= s_axis_cmd_data_cmd == 6'd2;
    end
    // �������Ӧ����
    always @(posedge clk)
    begin
        if(s_axis_cmd_valid & s_axis_cmd_ready) // ���㲢����
        begin
            # simulation_delay;
            
            case(s_axis_cmd_data_cmd)
                6'd0: cmd_resp_type <= RESP_TYPE_NO_RESP;
                6'd2: cmd_resp_type <= RESP_TYPE_LONG_RESP;
                6'd7, 6'd12: cmd_resp_type <= RESP_TYPE_RESP_WITH_BUSY;
                default: cmd_resp_type <= RESP_TYPE_COMMON_RESP;
            endcase
        end
    end
    // ����Ķ�д����
    always @(posedge clk)
    begin
        if(s_axis_cmd_valid & s_axis_cmd_ready) // ���㲢����
        begin
            if(is_previous_cmd_id55)
                # simulation_delay cmd_rw_type <= RW_TYPE_NON;
            else
            begin
                # simulation_delay;
                
                case(s_axis_cmd_data_cmd)
                    6'd6, 6'd17, 6'd18: cmd_rw_type <= RW_TYPE_READ;
                    6'd24, 6'd25: cmd_rw_type <= RW_TYPE_WRITE;
                    default: cmd_rw_type <= RW_TYPE_NON;
                endcase
            end
        end
    end
    // �����R3��Ӧ(��־)
    always @(posedge clk)
    begin
        if(s_axis_cmd_valid & s_axis_cmd_ready) // ���㲢����
            # simulation_delay cmd_with_r3_resp <= s_axis_cmd_data_cmd == 6'd41;
    end
    // ��д�����-1
    always @(posedge clk)
    begin
        if(s_axis_cmd_valid & s_axis_cmd_ready) // ���㲢����
            # simulation_delay rw_patch_n <= ((s_axis_cmd_data_cmd == 6'd18) | (s_axis_cmd_data_cmd == 6'd25)) ? s_axis_cmd_user_rw_patch_n:16'd0;
    end
    
    // sdio���������
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sdio_cmd_o_reg <= 1'b1;
        else if(cmd_to_send_en_shift) // ����
            # simulation_delay sdio_cmd_o_reg <= ((ctrler_status == SEND_CMD) & (sending_cmd_bit_i != (48 + cmd_pre_p_num))) ? cmd_bit_sending:1'b1;
    end
    
    // ��������(��־)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ����
            # simulation_delay cmd_bit_finished <= 1'b0;
        else if(cmd_to_send_en_shift) // ����
            # simulation_delay cmd_bit_finished <= (ctrler_status == SEND_CMD) & (sending_cmd_bit_i == (48 + cmd_pre_p_num));
    end
    
    // ����������
    always @(posedge clk)
    begin
        if(s_axis_cmd_valid & s_axis_cmd_ready) // ����
            # simulation_delay cmd_data <= {
                {cmd_pre_p_num{1'b1}}, // P:ǿ�������ߵ�ƽ
                1'b0, // S:��ʼλ
                1'b1, // T:����λ
                s_axis_cmd_data_cmd, // �����
                s_axis_cmd_data_param // ����
            };
        else if((ctrler_status == SEND_CMD) & cmd_to_send_en_shift) // ����
            # simulation_delay cmd_data <= {cmd_data[(39+cmd_pre_p_num-1):0], 1'bx};
    end
    
    // ����У���������
    /*
    ����: CRC7ÿ����һ��bitʱ�ĸ����߼�
    ����: crc: �ɵ�CRC7
          inbit: �����bit
    ����ֵ: ���º�� CRC7
    function automatic logic[6:0] CalcCrc7(input[6:0] crc, input inbit);
        logic xorb = crc[6] ^ inbit;
        return (crc << 1) ^ {3'd0, xorb, 2'd0, xorb};
    endfunction
    */
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ��λ
            # simulation_delay cmd_crc7_end <= 8'b0000_0001;
        else if(cmd_to_send_en_shift & cmd_actual_sending)
        begin
            if(cmd_bit_region == CMD_DATA_REGION) // ��ǰ���͵�����λ����������, ����CRC����
                # simulation_delay cmd_crc7_end <= {
                    {cmd_crc7_end[6:1], 1'b0} ^ {3'b000, cmd_crc7_end[7] ^ cmd_bit_sending, 2'b00, cmd_crc7_end[7] ^ cmd_bit_sending}, // CRC7
                    1'b1 // E:����λ
                };
            else // ��ǰ���͵�����λ����У���������, ��������
                # simulation_delay cmd_crc7_end <= {cmd_crc7_end[6:0], 1'bx};
        end
    end
    
    // ������ʼ��ʽ��������(���޳���һ��ʼ��Pλ)(��־)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ����
            # simulation_delay cmd_actual_sending <= 1'b0;
        else if((~cmd_actual_sending) & cmd_to_send_en_shift) // ճ����λ
            # simulation_delay cmd_actual_sending <= sending_cmd_bit_i == (cmd_pre_p_num - 1);
    end
    
    // ��ǰ���������λ���(������)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ����
            # simulation_delay sending_cmd_bit_i <= 6'd0;
        else if(cmd_to_send_en_shift) // ����
            # simulation_delay sending_cmd_bit_i <= sending_cmd_bit_i + 6'd1;
    end
    
    // ����λ��ѡ��
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ��λ
            # simulation_delay cmd_bit_region <= CMD_DATA_REGION;
        else if((cmd_bit_region != CMD_CRC_END_REGION) & cmd_to_send_en_shift) // ճ�͸���
            # simulation_delay cmd_bit_region <= (sending_cmd_bit_i == (39 + cmd_pre_p_num)) ? CMD_CRC_END_REGION:
                CMD_DATA_REGION; // hold
    end
    
    /**
	����ͼ������
	
	��֤��������֮���� >= cmd_itv
	**/
	wire sdio_clk_posedge_arrived; // SDIOʱ�������ص���(����)
    reg[clogb2(cmd_itv-1):0] cmd_itv_cnt; // ����ͼ������(������)
	
	assign sdio_clk_posedge_arrived = sdio_in_sample;
    
    // ����ͼ������Ҫ��(��־)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            cmd_itv_satisfied <= 1'b1;
        else if(cmd_done) // ����
            # simulation_delay cmd_itv_satisfied <= 1'b0;
        else if((~cmd_itv_satisfied) & sdio_clk_posedge_arrived) // ճ����λ, ����cmd_itv��sdioʱ��������
            # simulation_delay cmd_itv_satisfied <= cmd_itv_cnt == (cmd_itv - 1);
    end
    // ����ͼ������(������)
    always @(posedge clk)
    begin
        if(cmd_done) // ����
            # simulation_delay cmd_itv_cnt <= 0;
        else if(sdio_clk_posedge_arrived) // ����
            # simulation_delay cmd_itv_cnt <= cmd_itv_cnt + 1;
    end
    
    // ��ȡ����(��־)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            cmd_fetched <= 1'b0;
        else
        begin
            # simulation_delay;
            
            if(ctrler_status == IDLE)
            begin
                if(~cmd_fetched)
                    cmd_fetched <= s_axis_cmd_valid & s_axis_cmd_ready;
            end
            else // ǿ������
                cmd_fetched <= 1'b0;
        end
    end
    
    // ��ʼ������(��־)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            cmd_send_started <= 1'b0;
        else if(cmd_to_send_en_shift) // ����
            # simulation_delay cmd_send_started <= (ctrler_status == IDLE) ? cmd_fetched:1'b0;
    end
    
    /** ������Ӧ���� **/
    reg m_axis_resp_valid_reg; // ��ӦAXIS��valid�ź�
    wire resp_rd_sample; // ������Ӧ�Ͷ�����(����)
    reg start_rev_resp; // ��ʼ������Ӧ(��־)
    reg[7:0] receiving_resp_bit_i; // ��ǰ������Ӧ��λ���(������)
    reg[1:0] resp_bit_region; // ��ǰ������Ӧ������λ��(��־)
    reg[119:0] resp_receiving; // ���ڽ��յ���Ӧ����(��λ�Ĵ���)
    reg resp_en_cal_crc7; // ��ӦCRC7����ʹ��(��־)
    reg[6:0] crc7_receiving; // ���ڽ��յ���ӦCRC7(��λ�Ĵ���)
    reg[6:0] crc7_cal; // ��õ���ӦCRC7
    reg crc7_err; // CRC7У�����(��־)
    
    assign m_axis_resp_data = resp_receiving;
    assign m_axis_resp_user = {resp_timeout_flag, (en_resp_rd_crc == "true") ? crc7_err:1'b0, cmd_with_long_resp};
    assign m_axis_resp_valid = m_axis_resp_valid_reg;
    
    assign resp_rd_sample = sdio_in_sample;
    
    // ��ӦAXIS��valid�ź�
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            m_axis_resp_valid_reg <= 1'b0;
        else
            # simulation_delay m_axis_resp_valid_reg <= m_axis_resp_valid_reg ? (~m_axis_resp_ready):(ctrler_status == TRANS_RESP);
    end
    
    // ��ʼ������Ӧ(��־)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ����
            # simulation_delay start_rev_resp <= 1'b0;
        else if((ctrler_status == REV_RESP_RD) & resp_rd_sample & (~sdio_cmd_i)) // ��λ
            # simulation_delay start_rev_resp <= 1'b1;
    end
    
    // ��ǰ������Ӧ��λ���(������)
    // λ��Ŵӷ���λ��ʼ
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ����
            # simulation_delay receiving_resp_bit_i <= 8'd0;
        else if(start_rev_resp & resp_rd_sample) // ����
            # simulation_delay receiving_resp_bit_i <= receiving_resp_bit_i + 8'd1;
    end
    
    // ��ǰ������Ӧ������λ��(��־)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ��λ
            # simulation_delay resp_bit_region <= RESP_BIT_REGION_NOT_CARE;
        else if(start_rev_resp & resp_rd_sample) // ����
        begin
            # simulation_delay;
            
            case(resp_bit_region)
                RESP_BIT_REGION_NOT_CARE: // λ��:��������
                    if((cmd_resp_type == RESP_TYPE_LONG_RESP) ? (receiving_resp_bit_i == 8'd6):(receiving_resp_bit_i == 8'd0))
                        resp_bit_region <= RESP_BIT_REGION_DATA;
                RESP_BIT_REGION_DATA: // λ��:������
                    if((cmd_resp_type == RESP_TYPE_LONG_RESP) ? (receiving_resp_bit_i == 8'd126):(receiving_resp_bit_i == 8'd38))
                        resp_bit_region <= RESP_BIT_REGION_CRC;
                RESP_BIT_REGION_CRC: // λ��:CRC��
                    if((cmd_resp_type == RESP_TYPE_LONG_RESP) ? (receiving_resp_bit_i == 8'd133):(receiving_resp_bit_i == 8'd45))
                        resp_bit_region <= RESP_BIT_REGION_END;
                RESP_BIT_REGION_END: // λ��:������
                    resp_bit_region <= RESP_BIT_REGION_END; // hold
                default:
                    resp_bit_region <= RESP_BIT_REGION_NOT_CARE;
            endcase
        end
    end
    
    // ��ӦCRC7����ʹ��(��־)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ��λ
            # simulation_delay resp_en_cal_crc7 <= 1'b0;
        else if(resp_rd_sample) // ����
        begin
            if(~start_rev_resp) // ��ʼ��
                # simulation_delay resp_en_cal_crc7 <= (cmd_resp_type == RESP_TYPE_LONG_RESP) ? 1'b0:((ctrler_status == REV_RESP_RD) & (~sdio_cmd_i));
            else
            begin
                # simulation_delay;
                
                if(resp_en_cal_crc7)
                    resp_en_cal_crc7 <= ~((cmd_resp_type == RESP_TYPE_LONG_RESP) ? (receiving_resp_bit_i == 8'd126):(receiving_resp_bit_i == 8'd38));
                else
                    resp_en_cal_crc7 <= receiving_resp_bit_i == 8'd6;
            end
        end
    end
    
    // ������Ӧ���ݺ�CRC7
    // ���ڽ��յ���Ӧ����(��λ�Ĵ���)
    always @(posedge clk)
    begin
        if(start_rev_resp & resp_rd_sample & (resp_bit_region == RESP_BIT_REGION_DATA)) // ��������
            # simulation_delay resp_receiving <= {resp_receiving[118:0], sdio_cmd_i};
    end
    // ���ڽ��յ���ӦCRC7(��λ�Ĵ���)
    always @(posedge clk)
    begin
        if(start_rev_resp & resp_rd_sample & (resp_bit_region == RESP_BIT_REGION_CRC)) // ��������
            # simulation_delay crc7_receiving <= {crc7_receiving[5:0], sdio_cmd_i};
    end
    
    // ��õ���ӦCRC7
    /*
    ����: CRC7ÿ����һ��bitʱ�ĸ����߼�
    ����: crc: �ɵ�CRC7
          inbit: �����bit
    ����ֵ: ���º�� CRC7
    function automatic logic[6:0] CalcCrc7(input[6:0] crc, input inbit);
        logic xorb = crc[6] ^ inbit;
		
        return (crc << 1) ^ {3'd0, xorb, 2'd0, xorb};
    endfunction
    */
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ��ʼ��
            // ��ʼλ -> 7'd0 ^ {3'b000, 1'b0 ^ 1'b0, 2'b00, 1'b0 ^ 1'b0} = 7'd0
            # simulation_delay crc7_cal <= 7'd0;
        else if(start_rev_resp & resp_rd_sample & resp_en_cal_crc7) // ����CRC7
            # simulation_delay crc7_cal <= {crc7_cal[5:0], 1'b0} ^ {3'b000, crc7_cal[6] ^ sdio_cmd_i, 2'b00, crc7_cal[6] ^ sdio_cmd_i};
    end
    
    // CRC7У�����(��־)
    always @(posedge clk)
    begin
        if(start_rev_resp & resp_rd_sample & (resp_bit_region == RESP_BIT_REGION_CRC) & 
            ((cmd_resp_type == RESP_TYPE_LONG_RESP) ? (receiving_resp_bit_i == 8'd133):(receiving_resp_bit_i == 8'd45))) // ���㲢����
            # simulation_delay crc7_err <= {crc7_receiving[5:0], sdio_cmd_i} != (cmd_with_r3_resp ? 7'b111_1111:crc7_cal);
    end
    
    // ��Ӧ�������(��־)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ����
            # simulation_delay resp_received <= 1'b0;
        else if(start_rev_resp & resp_rd_sample) // ��λ
            # simulation_delay resp_received <= resp_bit_region == RESP_BIT_REGION_END;
    end
    
    /** ��Ӧ��ʱ���� **/
    // ����Ӧʱ�� >= resp_timeoutʱ������ʱ
    reg[clogb2(resp_timeout-1):0] resp_timeout_cnt; // ��Ӧ��ʱ(������)
    
    // ��Ӧ��ʱ(��־)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ����
            # simulation_delay resp_timeout_flag <= 1'b0;
        else if((~resp_timeout_flag) & (~start_rev_resp) & (ctrler_status == REV_RESP_RD) & resp_rd_sample & sdio_cmd_i) // ճ����λ
            # simulation_delay resp_timeout_flag <= resp_timeout_cnt == (resp_timeout - 1);
    end
    // ��Ӧ��ʱ(������)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ����
            # simulation_delay resp_timeout_cnt <= 0;
        else if((~start_rev_resp) & (ctrler_status == REV_RESP_RD) & resp_rd_sample & sdio_cmd_i) // ����
            # simulation_delay resp_timeout_cnt <= resp_timeout_cnt + 1;
    end
    
    /** ��Ӧ��busy��� **/
    // ������resp_with_busy_timeout�����ڵ�busy���
    reg[clogb2(resp_with_busy_timeout-1):0] resp_busy_timeout_cnt; // ��Ӧ��busy��ⳬʱ(������)
    reg resp_busy_timeout_last; // ��Ӧ��busy��⴦�����1������(��־)
    reg[1:0] resp_busy_detect_status; // ��Ӧ��busy���״̬
    
    // ��Ӧ��busy��ⳬʱ(������)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ��λ
            # simulation_delay resp_busy_timeout_cnt <= 0;
        else if((resp_busy_detect_status == RESP_WAIT_BUSY) & resp_rd_sample) // ����
            # simulation_delay resp_busy_timeout_cnt <= resp_busy_timeout_cnt + 1;
    end
    // ��Ӧ��busy��⴦�����1������(��־)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ��λ
            # simulation_delay resp_busy_timeout_last <= 1'b0;
        else if((resp_busy_detect_status == RESP_WAIT_BUSY) & resp_rd_sample) // ����
            # simulation_delay resp_busy_timeout_last <= resp_busy_timeout_cnt == (resp_with_busy_timeout - 2);
    end
    
    // ��Ӧ��busy���״̬
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ��λ
            # simulation_delay resp_busy_detect_status <= RESP_BUSY_DETECT_IDLE;
        else if(start_rev_resp & resp_rd_sample)
        begin
            # simulation_delay;
            
            case(resp_busy_detect_status)
                RESP_BUSY_DETECT_IDLE: // ״̬:������ʼ
                    if(resp_received & (cmd_resp_type == RESP_TYPE_RESP_WITH_BUSY))
                        resp_busy_detect_status <= RESP_WAIT_BUSY;
                RESP_WAIT_BUSY: // ״̬:���busy�ź�
                    if(~sdio_d0_i) // ��⵽busy
                        resp_busy_detect_status <= RESP_WAIT_IDLE;
                    else if(resp_busy_timeout_last) // busy��ⳬʱ
                        resp_busy_detect_status <= RESP_BUSY_DETECT_FINISH;
                RESP_WAIT_IDLE: // ״̬:�ȴ��ӻ�idle
                    if(sdio_d0_i)
                        resp_busy_detect_status <= RESP_BUSY_DETECT_FINISH;
                RESP_BUSY_DETECT_FINISH: // ״̬:������
                    resp_busy_detect_status <= RESP_BUSY_DETECT_FINISH; // hold
                default:
                    resp_busy_detect_status <= RESP_BUSY_DETECT_IDLE;
            endcase
        end
    end
    
    // �����Ӧ��busy���(��־)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ����
            # simulation_delay resp_busy_detect_finished <= 1'b0;
        else if((~resp_busy_detect_finished) & (start_rev_resp & resp_rd_sample) & sdio_d0_i) // ճ����λ
            # simulation_delay resp_busy_detect_finished <= ((resp_busy_detect_status == RESP_WAIT_BUSY) & resp_busy_timeout_last) |
                (resp_busy_detect_status == RESP_WAIT_IDLE);
    end
    
    /** �����ݿ��� **/
    /*
    ʵ���˵���/����
    ÿ��̶�Ϊ512Byte(128*4Byte)
    */
    reg[31:0] m_axis_rd_data_regs; // ������AXIS��data�ź�
    reg m_axis_rd_valid_reg; // ������AXIS��valid�ź�
    reg m_axis_rd_last_reg; // ������AXIS��last�ź�
    reg start_rd_data; // ��ʼ������(��־)
    reg[31:0] rd_data_packet; // ��ȡ��һ������ -> {byte1, byte2, byte3, byte4}
    reg[4:0] rd_data_cnt_in_packet; // ��ȡһ�����ݵĽ���(������)
    reg rd_data_last_in_packet; // ��ǰ��ȡ�������ݵ����1��(��־)
    reg[6:0] rd_data_packet_n; // �Ѷ�ȡ����������-1(������)
    reg rd_data_last; // ��ȡ���1��(��־)
    reg[1:0] rd_data_region; // ������������
    reg[15:0] rd_patch_cnt; // �Ѷ������(������)
    reg[15:0] rd_crc16_cal[3:0]; // �����CRC16
    reg[15:0] rd_crc16_rev[3:0]; // ���յ�CRC16
    reg[3:0] rd_crc16_rev_cnt; // ����CRC16����(������)
    reg rd_crc16_rev_last; // �������1��CRC16λ(��־)
    reg[4:0] m_axis_rd_sts_data_regs; // �����ݷ��ؽ��AXIS��data
    reg m_axis_rd_sts_valid_reg; // �����ݷ��ؽ��AXIS��valid
    
    assign m_axis_rd_data = {m_axis_rd_data_regs[7:0], m_axis_rd_data_regs[15:8], m_axis_rd_data_regs[23:16], m_axis_rd_data_regs[31:24]}; // ��С���ֽ�����������
    assign m_axis_rd_valid = m_axis_rd_valid_reg;
    assign m_axis_rd_last = m_axis_rd_last_reg;
    
    assign m_axis_rd_sts_data = {3'd0, (read_timeout != -1) ? m_axis_rd_sts_data_regs[4]:1'b0, (en_resp_rd_crc == "true") ? m_axis_rd_sts_data_regs[3:0]:4'b0000};
    assign m_axis_rd_sts_valid = m_axis_rd_sts_valid_reg;
    
    // ������AXIS��data�ź�
    always @(posedge clk)
    begin
        if(start_rd_data & resp_rd_sample & rd_data_last_in_packet) // ����
            # simulation_delay m_axis_rd_data_regs <= en_wide_sdio ? {rd_data_packet[27:0], sdio_d3_i, sdio_d2_i, sdio_d1_i, sdio_d0_i}:
                {rd_data_packet[30:0], sdio_d0_i};
    end
    // ������AXIS��valid�ź�
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            m_axis_rd_valid_reg <= 1'b0;
        else
            # simulation_delay m_axis_rd_valid_reg <= m_axis_rd_valid_reg ? (~m_axis_rd_ready):
                (start_rd_data & resp_rd_sample & rd_data_last_in_packet & (~ignore_rd));
    end
    // ������AXIS��last�ź�
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            m_axis_rd_last_reg <= 1'b0;
        else if(start_rd_data & resp_rd_sample)
            # simulation_delay m_axis_rd_last_reg <= (rd_data_packet_n == 7'd127) & rd_data_last_in_packet;
    end
    
    // ��ʼ������(��־)
    always @(posedge clk)
    begin
        if((ctrler_status != REV_RESP_RD) | (cmd_rw_type != RW_TYPE_READ)) // ����
            # simulation_delay start_rd_data <= 1'b0;
        else if(resp_rd_sample) // ����
            # simulation_delay start_rd_data <= start_rd_data ?
                (~((rd_data_region == RD_REGION_END) & (rd_patch_cnt != rw_patch_n))):
                (~sdio_d0_i);
    end
    
    // ��ȡ��һ������ -> {byte1, byte2, byte3, byte4}
    always @(posedge clk)
    begin
        if(start_rd_data & resp_rd_sample & (rd_data_region == RD_REGION_DATA)) // ��������
            # simulation_delay rd_data_packet <= en_wide_sdio ? {rd_data_packet[27:0], sdio_d3_i, sdio_d2_i, sdio_d1_i, sdio_d0_i}:
                {rd_data_packet[30:0], sdio_d0_i};
    end
    
    // ������(�������ͱ�־)
    // ��ȡһ�����ݵĽ���(������)
    always @(posedge clk)
    begin
        if((ctrler_status == IDLE) | (rd_data_region == RD_REGION_END)) // ��λ
            # simulation_delay rd_data_cnt_in_packet <= 5'd0;
        else if(start_rd_data & resp_rd_sample) // ����
            # simulation_delay rd_data_cnt_in_packet <= rd_data_last_in_packet ? 5'd0:(rd_data_cnt_in_packet + 5'd1);
    end
    // ��ǰ��ȡ�������ݵ����1��
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ����
            # simulation_delay rd_data_last_in_packet <= 1'b0;
        else if(start_rd_data & resp_rd_sample) // ����
            # simulation_delay rd_data_last_in_packet <= (rd_data_region == RD_REGION_DATA) &
                (en_wide_sdio ? (rd_data_cnt_in_packet == 5'd6):(rd_data_cnt_in_packet == 5'd30));
    end
    // �Ѷ�ȡ����������-1(������)
    always @(posedge clk)
    begin
        if((ctrler_status == IDLE) | (rd_data_region == RD_REGION_END)) // ��λ
            # simulation_delay rd_data_packet_n <= 7'd0;
        else if(start_rd_data & resp_rd_sample & rd_data_last_in_packet) // ����
            # simulation_delay rd_data_packet_n <= rd_data_packet_n + 7'd1;
    end
    // ��ȡ���1��(��־)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ����
            # simulation_delay rd_data_last <= 1'b0;
        else if(start_rd_data & resp_rd_sample) // ����
            # simulation_delay rd_data_last <= (rd_data_region == RD_REGION_DATA) &
                (en_wide_sdio ? (rd_data_cnt_in_packet == 5'd6):(rd_data_cnt_in_packet == 5'd30)) &
                (rd_data_packet_n == 7'd127);
    end
    
    // ������������
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ��λ
            # simulation_delay rd_data_region <= RD_REGION_DATA;
        else if(start_rd_data & resp_rd_sample)
        begin
            # simulation_delay;
            
            case(rd_data_region)
                RD_REGION_DATA: // λ��:�������ִ���������
                    if(rd_data_last)
                        rd_data_region <= RD_REGION_CRC;
                RD_REGION_CRC: // λ��:�������ִ���У����
                    if(rd_crc16_rev_last)
                        rd_data_region <= RD_REGION_END;
                RD_REGION_END: // λ��:�������ִ��ڽ�����
                    rd_data_region <= (rd_patch_cnt == rw_patch_n) ? RD_REGION_FINISH:RD_REGION_DATA;
                RD_REGION_FINISH: // λ��:���������
                    rd_data_region <= RD_REGION_FINISH; // hold
                default:
                    rd_data_region <= RD_REGION_DATA;
            endcase
        end
    end
    
    // �Ѷ������(������)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ��λ
            # simulation_delay rd_patch_cnt <= 16'd0;
        else if(start_rd_data & resp_rd_sample & (rd_data_region == RD_REGION_END)) // ����
            # simulation_delay rd_patch_cnt <= rd_patch_cnt + 16'd1;
    end
    
    // �����(��־)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ��λ
            # simulation_delay rd_finished <= 1'b0;
        else if(~rd_finished) // ճ����λ
            # simulation_delay rd_finished <= rd_data_region == RD_REGION_FINISH;
    end
    
    // �����CRC16
    /*
    ����: CRC16ÿ����һ��bitʱ�ĸ����߼�
    ����: crc: �ɵ�CRC16
         inbit: �����bit
    ����ֵ: ���º��CRC16
    function automatic logic[15:0] CalcCrc16(input[15:0] crc, input inbit);
        logic xorb = crc[15] ^ inbit;
        return (crc << 1) ^ {3'd0, xorb, 6'd0, xorb, 4'd0, xorb};
    endfunction
    */
    always @(posedge clk)
    begin
        if((ctrler_status == IDLE) | (rd_data_region == RD_REGION_END)) // ��λ
        begin
            # simulation_delay;
            
            rd_crc16_cal[0] <= 16'd0;
            rd_crc16_cal[1] <= 16'd0;
            rd_crc16_cal[2] <= 16'd0;
            rd_crc16_cal[3] <= 16'd0;
        end
        else if(start_rd_data & resp_rd_sample & (rd_data_region == RD_REGION_DATA)) // ����CRC16
        begin
            # simulation_delay;
            
            rd_crc16_cal[0] <= {rd_crc16_cal[0][14:0], 1'b0} ^ {3'd0, rd_crc16_cal[0][15] ^ sdio_d0_i, 6'd0, rd_crc16_cal[0][15] ^ sdio_d0_i,
                4'd0, rd_crc16_cal[0][15] ^ sdio_d0_i};
            rd_crc16_cal[1] <= {rd_crc16_cal[1][14:0], 1'b0} ^ {3'd0, rd_crc16_cal[1][15] ^ sdio_d1_i, 6'd0, rd_crc16_cal[1][15] ^ sdio_d1_i,
                4'd0, rd_crc16_cal[1][15] ^ sdio_d1_i};
            rd_crc16_cal[2] <= {rd_crc16_cal[2][14:0], 1'b0} ^ {3'd0, rd_crc16_cal[2][15] ^ sdio_d2_i, 6'd0, rd_crc16_cal[2][15] ^ sdio_d2_i,
                4'd0, rd_crc16_cal[2][15] ^ sdio_d2_i};
            rd_crc16_cal[3] <= {rd_crc16_cal[3][14:0], 1'b0} ^ {3'd0, rd_crc16_cal[3][15] ^ sdio_d3_i, 6'd0, rd_crc16_cal[3][15] ^ sdio_d3_i,
                4'd0, rd_crc16_cal[3][15] ^ sdio_d3_i};
        end
    end
    
    // ���յ�CRC16
    always @(posedge clk)
    begin
        if(start_rd_data & resp_rd_sample & (rd_data_region == RD_REGION_CRC)) // ��������
        begin
            # simulation_delay;
            
            rd_crc16_rev[0] <= {rd_crc16_rev[0][14:0], sdio_d0_i};
            rd_crc16_rev[1] <= {rd_crc16_rev[1][14:0], sdio_d1_i};
            rd_crc16_rev[2] <= {rd_crc16_rev[2][14:0], sdio_d2_i};
            rd_crc16_rev[3] <= {rd_crc16_rev[3][14:0], sdio_d3_i};
        end
    end
    
    // ����CRC16����(�������ͱ�־)
    // ����CRC16����(������)
    always @(posedge clk)
    begin
        if(rd_data_region == RD_REGION_DATA) // ��λ
            # simulation_delay rd_crc16_rev_cnt <= 4'd0;
        else if(start_rd_data & resp_rd_sample & (rd_data_region == RD_REGION_CRC)) // ����
            # simulation_delay rd_crc16_rev_cnt <= rd_crc16_rev_cnt + 4'd1;
    end
    // �������1��CRC16λ(��־)
    always @(posedge clk)
    begin
        if(rd_data_region == RD_REGION_DATA) // ��λ
            # simulation_delay rd_crc16_rev_last <= 1'b0;
        else if(start_rd_data & resp_rd_sample) // ����
            # simulation_delay rd_crc16_rev_last <= (rd_data_region == RD_REGION_CRC) & (rd_crc16_rev_cnt == 4'd14);
    end
    
    // �����ݷ��ؽ��AXIS
    // data
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ��λ
            # simulation_delay m_axis_rd_sts_data_regs <= 5'b0_0000;
        else if(((rd_data_region == RD_REGION_CRC) & (resp_rd_sample & rd_crc16_rev_last)) |
            ((read_timeout != -1) & rd_timeout_flag))
        begin
            # simulation_delay;
            
            // ����ʱ
            m_axis_rd_sts_data_regs[4] <= m_axis_rd_sts_data_regs[4] |
                ((read_timeout != -1) & rd_timeout_flag);
            // У����
            m_axis_rd_sts_data_regs[3:0] <= m_axis_rd_sts_data_regs[3:0] |
                (((read_timeout != -1) & rd_timeout_flag) ? 4'b0000:
                {
                    en_wide_sdio ? 1'b0:({rd_crc16_rev[3][14:0], sdio_d3_i} != rd_crc16_cal[3]),
                    en_wide_sdio ? 1'b0:({rd_crc16_rev[2][14:0], sdio_d2_i} != rd_crc16_cal[2]),
                    en_wide_sdio ? 1'b0:({rd_crc16_rev[1][14:0], sdio_d1_i} != rd_crc16_cal[1]),
                    {rd_crc16_rev[0][14:0], sdio_d0_i} != rd_crc16_cal[0]
                });
        end
    end
    // valid
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            m_axis_rd_sts_valid_reg <= 1'b0;
        else // ��������
            # simulation_delay m_axis_rd_sts_valid_reg <= ((rd_data_region == RD_REGION_CRC) & (resp_rd_sample & rd_crc16_rev_last)) |
                ((read_timeout != -1) & rd_timeout_flag);
    end
    
    /** �����ݳ�ʱ���� **/
    reg[clogb2(read_timeout-1):0] rd_timeout_cnt; // ����ʱ������
    
    // ����ʱ(��־)
    always @(posedge clk)
    begin
        if((ctrler_status == IDLE) | (rd_data_region == RD_REGION_END)) // ��λ
            # simulation_delay rd_timeout_flag <= 1'b0;
        else if((ctrler_status == REV_RESP_RD) & (~rd_timeout_flag)) // ճ����λ
            # simulation_delay rd_timeout_flag <= (cmd_rw_type == RW_TYPE_READ) & resp_rd_sample & (~start_rd_data) & sdio_d0_i & (rd_timeout_cnt == (read_timeout - 1));
    end
    // ����ʱ������
    always @(posedge clk)
    begin
        if((ctrler_status == IDLE) | (rd_data_region == RD_REGION_END)) // ��λ
            # simulation_delay rd_timeout_cnt <= 0;
        else if((ctrler_status == REV_RESP_RD) & (cmd_rw_type == RW_TYPE_READ) & resp_rd_sample & (~start_rd_data) & sdio_d0_i) // ����
            # simulation_delay rd_timeout_cnt <= rd_timeout_cnt + 1;
    end
    
    /** д���ݿ��� **/
    /*
    ʵ���˵���/���д
    ÿ��̶�Ϊ512Byte(128*4Byte)
    */
    // sdio������
    reg[3:0] sdio_d_o_regs; // sdio�������
    wire sdio_dout_upd; // sdio�����������ʹ��(����)
    wire sdio_sts_sample; // sdioд���ݷ���״̬����ʹ��(����)
    // д����AXIS
	wire to_get_wt_data; // ��ȡд����(��־)
    reg s_axis_wt_ready_reg; // д����AXIS��ready�ź�
    // д����״̬����AXIS
    reg m_axis_wt_sts_valid_reg; // д����״̬����AXIS��valid�ź�
    // д���ݽ׶�
    reg[2:0] wt_stage; // ��ǰ������д�׶�
    reg[7:0] wt_patch_cnt; // �Ѷ������(������)
    // д�ȴ�
    reg[clogb2(data_wt_wait_p-1):0] wt_wait_cnt; // д�ȴ�������
    reg wt_wait_finished; // д�ȴ����(��־)
    // ����ǿ�������ߵ�ƽ, ��ʼλ
    reg wt_data_buf_initialized; // д���ݻ�������ʼ����ɱ�־
    // ����д
    reg[31:0] wt_data_buf; // д���ݻ�����(��λ�Ĵ���)
    reg[4:0] wt_data_cnt_in_packet; // дһ�����ݵĽ���(������)
    reg wt_data_last_in_packet; // ��ǰд�������ݵ����1��(��־)
    reg[6:0] wt_data_packet_n; // ��д����������-1(������)
	reg wt_data_packet_last; // ���1��д����(��־)
    reg wt_data_last; // д���1������(��־)
    // У��ͽ���λ
    reg[16:0] wt_crc16_end[3:0]; // д���ݵ�crc16�ͽ���λ
    reg[4:0] wt_crc16_end_cnt; // дcrc16�ͽ���λ�Ľ���(������)
    reg wt_crc16_end_finished; // дcrc16�ͽ���λ���(��־)
    // ����״̬��Ϣ
    reg[2:0] wt_sts_stage; // д���ݽ���״̬���صĽ׶�
    reg[2:0] wt_sts; // д����״̬����
    reg wt_sts_received; // д����״̬���ؽ������(��־)
    // �ȴ��ӻ�idle
    reg wt_slave_idle; // �ӻ�����(��־)
    
    assign s_axis_wt_ready = s_axis_wt_ready_reg;
    assign m_axis_wt_sts_data = {5'd0, wt_sts};
    assign m_axis_wt_sts_valid = m_axis_wt_sts_valid_reg;
    assign {sdio_d3_o, sdio_d2_o, sdio_d1_o, sdio_d0_o} = sdio_d_o_regs;
	
	assign to_get_wt_data = (div_rate == 10'd0) ? 
		(en_wide_sdio ? (wt_data_cnt_in_packet == 5'd6):(wt_data_cnt_in_packet == 5'd30)):
		wt_data_last_in_packet;
    
    assign sdio_dout_upd = sdio_out_upd;
    assign sdio_sts_sample = sdio_in_sample;
    
    // sdio�������
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sdio_d_o_regs <= 4'b1111;
        else if(sdio_dout_upd) // ����
        begin
            # simulation_delay;
            
            case(wt_stage)
                WT_STAGE_WAIT, WT_STAGE_PULL_UP: // �׶�:д�ȴ�, ����ǿ�������ߵ�ƽ
					sdio_d_o_regs <= 4'b1111;
				WT_STAGE_START: // �׶�:��ʼλ
                    sdio_d_o_regs <= {en_wide_sdio ? 3'b000:3'b111, 1'b0};
				WT_STAGE_TRANS: // �׶�:����д
                    sdio_d_o_regs <= en_wide_sdio ? wt_data_buf[31:28]:{3'b111, wt_data_buf[31]};
				WT_STAGE_CRC_END: // �׶�:У��ͽ���λ
                    sdio_d_o_regs <= wt_crc16_end_finished ?
                        4'b1111:(en_wide_sdio ? {wt_crc16_end[3][16], wt_crc16_end[2][16], 
							wt_crc16_end[1][16], wt_crc16_end[0][16]}:
							{3'b111, wt_crc16_end[0][16]});
				WT_STAGE_STS, WT_STAGE_WAIT_IDLE, WT_STAGE_FINISHED: // �׶�:����״̬��Ϣ, �ȴ��ӻ�idle, ���
                    sdio_d_o_regs <= 4'b1111;
                default:
                    sdio_d_o_regs <= 4'b1111;
            endcase
        end
    end
    
    // д����AXIS��ready�ź�
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            s_axis_wt_ready_reg <= 1'b0;
        else
        begin
            # simulation_delay;
            
            case(wt_stage)
                WT_STAGE_WAIT: // �׶�:д�ȴ�
                    s_axis_wt_ready_reg <= sdio_dout_upd & wt_wait_finished;
                WT_STAGE_PULL_UP, WT_STAGE_START: // �׶�:����ǿ�������ߵ�ƽ, ��ʼλ
                    s_axis_wt_ready_reg <= (~wt_data_buf_initialized) & (~s_axis_wt_valid);
                WT_STAGE_TRANS: // �׶�:����д
                    s_axis_wt_ready_reg <= s_axis_wt_ready_reg ? (~s_axis_wt_valid):
						(sdio_dout_upd & to_get_wt_data & (~wt_data_packet_last));
                WT_STAGE_CRC_END, WT_STAGE_STS, WT_STAGE_WAIT_IDLE, WT_STAGE_FINISHED: // �׶�:У��ͽ���λ, ����״̬��Ϣ, �ȴ��ӻ�idle, ���
                    s_axis_wt_ready_reg <= 1'b0;
                default:
                    s_axis_wt_ready_reg <= 1'b0;
            endcase
        end
    end
    
    // д���ݽ׶�
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ��λ
            # simulation_delay wt_stage <= WT_STAGE_WAIT;
        else
        begin
            # simulation_delay;
            
            case(wt_stage)
                WT_STAGE_WAIT: // �׶�:д�ȴ�
                    if(sdio_dout_upd & wt_wait_finished)
                        wt_stage <= WT_STAGE_PULL_UP;
                WT_STAGE_PULL_UP: // �׶�:����ǿ�������ߵ�ƽ
                    if(sdio_dout_upd)
                        wt_stage <= WT_STAGE_START;
                WT_STAGE_START: // �׶�:��ʼλ
                    if(sdio_dout_upd & wt_data_buf_initialized)
                        wt_stage <= WT_STAGE_TRANS;
                WT_STAGE_TRANS: // �׶�:����д
                    if(sdio_dout_upd & wt_data_last)
                        wt_stage <= WT_STAGE_CRC_END;
                WT_STAGE_CRC_END: // �׶�:У��ͽ���λ
                    if(sdio_dout_upd & wt_crc16_end_finished)
                        wt_stage <= WT_STAGE_STS;
                WT_STAGE_STS: // �׶�:����״̬��Ϣ
                    if(wt_sts_received)
                        wt_stage <= WT_STAGE_WAIT_IDLE;
                WT_STAGE_WAIT_IDLE: // �׶�:�ȴ��ӻ�idle
                    if(wt_slave_idle)
                        wt_stage <= (wt_patch_cnt == rw_patch_n) ? WT_STAGE_FINISHED:WT_STAGE_WAIT;
                WT_STAGE_FINISHED: // �׶�:���
                    wt_stage <= WT_STAGE_FINISHED; // hold
                default:
                    wt_stage <= WT_STAGE_WAIT;
            endcase
        end
    end
    
    // �Ѷ������(������)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ��λ
            # simulation_delay wt_patch_cnt <= 8'd0;
        else if((wt_stage == WT_STAGE_WAIT_IDLE) & wt_slave_idle) // ����
            # simulation_delay wt_patch_cnt <= wt_patch_cnt + 8'd1;
    end
    
    // д���(��־)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // ����
            # simulation_delay wt_finished <= 1'b0;
        else if((wt_stage == WT_STAGE_WAIT_IDLE) & wt_slave_idle) // ����
            # simulation_delay wt_finished <= wt_patch_cnt == rw_patch_n;
    end
    
    // �׶�:д�ȴ�
    // д�ȴ�������
    always @(posedge clk)
    begin
        if((ctrler_status == IDLE) | (wt_stage == WT_STAGE_WAIT_IDLE)) // ��λ
            # simulation_delay wt_wait_cnt <= 0;
        else if((ctrler_status == WT_DATA) & (wt_stage == WT_STAGE_WAIT) & sdio_dout_upd) // ����
            # simulation_delay wt_wait_cnt <= wt_wait_cnt + 1;
    end
    // д�ȴ����(��־)
    always @(posedge clk)
    begin
        if((ctrler_status == IDLE) | (wt_stage == WT_STAGE_WAIT_IDLE)) // ����
            # simulation_delay wt_wait_finished <= 1'b0;
        else if((ctrler_status == WT_DATA) & (wt_stage == WT_STAGE_WAIT) & sdio_dout_upd) // ����
            # simulation_delay wt_wait_finished <= wt_wait_cnt == (data_wt_wait_p - 1);
    end
    
    // �׶�:����ǿ�������ߵ�ƽ, ��ʼλ
    // д���ݻ�������ʼ����ɱ�־
    always @(posedge clk)
    begin
        if((wt_stage != WT_STAGE_PULL_UP) & (wt_stage != WT_STAGE_START)) // ����
            # simulation_delay wt_data_buf_initialized <= 1'b0;
        else if(~wt_data_buf_initialized) // ճ�͸���
            # simulation_delay wt_data_buf_initialized <= s_axis_wt_valid & s_axis_wt_ready;
    end
    
    // �׶�:����д
    // д���ݻ�����(��λ�Ĵ���)
    always @(posedge clk)
    begin
        if(s_axis_wt_valid & s_axis_wt_ready) // ����
            # simulation_delay wt_data_buf <= {s_axis_wt_data[7:0], s_axis_wt_data[15:8], s_axis_wt_data[23:16], s_axis_wt_data[31:24]}; // �ֽ�������
        else if((wt_stage == WT_STAGE_TRANS) & sdio_dout_upd) // ����
            # simulation_delay wt_data_buf <= en_wide_sdio ? {wt_data_buf[27:0], 4'dx}:{wt_data_buf[30:0], 1'bx};
    end
    
    // д����(�������ͱ�־)
    // дһ�����ݵĽ���(������)
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // ��λ
            # simulation_delay wt_data_cnt_in_packet <= 5'd0;
        else if((wt_stage == WT_STAGE_TRANS) & sdio_dout_upd) // ����
            # simulation_delay wt_data_cnt_in_packet <= wt_data_last_in_packet ? 5'd0:(wt_data_cnt_in_packet + 5'd1);
    end
    // ��ǰд�������ݵ����1��(��־)
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // ����
            # simulation_delay wt_data_last_in_packet <= 1'b0;
        else if((wt_stage == WT_STAGE_TRANS) & sdio_dout_upd) // ����
            # simulation_delay wt_data_last_in_packet <= en_wide_sdio ? (wt_data_cnt_in_packet == 5'd6):(wt_data_cnt_in_packet == 5'd30);
    end
    // ��д����������-1(������)
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // ��λ
            # simulation_delay wt_data_packet_n <= 7'd0;
        else if((wt_stage == WT_STAGE_TRANS) & sdio_dout_upd & wt_data_last_in_packet) // ����
            # simulation_delay wt_data_packet_n <= wt_data_packet_n + 7'd1;
    end
	// ���1��д����(��־)
	always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // ��λ
            # simulation_delay wt_data_packet_last <= 7'd0;
        else if((wt_stage == WT_STAGE_TRANS) & sdio_dout_upd & wt_data_last_in_packet) // ����
            # simulation_delay wt_data_packet_last <= wt_data_packet_n == 7'd126;
    end
    // д���1������(��־)
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // ����
            # simulation_delay wt_data_last <= 1'b0;
        else if((wt_stage == WT_STAGE_TRANS) & sdio_dout_upd) // ����
            # simulation_delay wt_data_last <= (wt_data_packet_n == 7'd127) &
                (en_wide_sdio ? (wt_data_cnt_in_packet == 5'd6):(wt_data_cnt_in_packet == 5'd30));
    end
    
    // �׶�:У��ͽ���λ
    /*
    ����: CRC16ÿ����һ��bitʱ�ĸ����߼�
    ����: crc: �ɵ�CRC16
         inbit: �����bit
    ����ֵ: ���º��CRC16
    function automatic logic[15:0] CalcCrc16(input[15:0] crc, input inbit);
        logic xorb = crc[15] ^ inbit;
        return (crc << 1) ^ {3'd0, xorb, 6'd0, xorb, 4'd0, xorb};
    endfunction
    */
    // д���ݵ�crc16�ͽ���λ
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // ��λ
        begin
            # simulation_delay;
            
            wt_crc16_end[0] <= 17'b0000_0000_0000_0000_1;
            wt_crc16_end[1] <= 17'b0000_0000_0000_0000_1;
            wt_crc16_end[2] <= 17'b0000_0000_0000_0000_1;
            wt_crc16_end[3] <= 17'b0000_0000_0000_0000_1;
        end
        else if(sdio_dout_upd)
        begin
            # simulation_delay;
            
            if(wt_stage == WT_STAGE_TRANS) // ��������д�׶�, ����CRC16
            begin
                wt_crc16_end[0] <= {
                    {wt_crc16_end[0][15:1], 1'b0} ^ {3'd0, wt_crc16_end[0][16] ^ (en_wide_sdio ? wt_data_buf[28]:wt_data_buf[31]), 
                        6'd0, wt_crc16_end[0][16] ^ (en_wide_sdio ? wt_data_buf[28]:wt_data_buf[31]),
                        4'd0, wt_crc16_end[0][16] ^ (en_wide_sdio ? wt_data_buf[28]:wt_data_buf[31])}, // CRC16
                    1'b1 // E:����λ
                };
                wt_crc16_end[1] <= {
                    {wt_crc16_end[1][15:1], 1'b0} ^ {3'd0, wt_crc16_end[1][16] ^ wt_data_buf[29], 
                        6'd0, wt_crc16_end[1][16] ^ wt_data_buf[29], 4'd0, wt_crc16_end[1][16] ^ wt_data_buf[29]}, // CRC16
                    1'b1 // E:����λ
                };
                wt_crc16_end[2] <= {
                    {wt_crc16_end[2][15:1], 1'b0} ^ {3'd0, wt_crc16_end[2][16] ^ wt_data_buf[30], 
                        6'd0, wt_crc16_end[2][16] ^ wt_data_buf[30], 4'd0, wt_crc16_end[2][16] ^ wt_data_buf[30]}, // CRC16
                    1'b1 // E:����λ
                };
                wt_crc16_end[3] <= {
                    {wt_crc16_end[3][15:1], 1'b0} ^ {3'd0, wt_crc16_end[3][16] ^ wt_data_buf[31], 
                        6'd0, wt_crc16_end[3][16] ^ wt_data_buf[31], 4'd0, wt_crc16_end[3][16] ^ wt_data_buf[31]}, // CRC16
                    1'b1 // E:����λ
                };
            end
            else if(wt_stage == WT_STAGE_CRC_END) // ����У��ͽ���λ�׶�, ��������
            begin
                wt_crc16_end[0] <= {wt_crc16_end[0][15:0], 1'bx};
                wt_crc16_end[1] <= {wt_crc16_end[1][15:0], 1'bx};
                wt_crc16_end[2] <= {wt_crc16_end[2][15:0], 1'bx};
                wt_crc16_end[3] <= {wt_crc16_end[3][15:0], 1'bx};
            end
        end
    end
    
    // дcrc16�ͽ���λ�Ľ���(�������ͱ�־)
    // дcrc16�ͽ���λ�Ľ���(������)
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // ��λ
            # simulation_delay wt_crc16_end_cnt <= 5'd0;
        else if((wt_stage == WT_STAGE_CRC_END) & sdio_dout_upd) // ����
            # simulation_delay wt_crc16_end_cnt <= wt_crc16_end_cnt + 5'd1;
    end
    // дcrc16�ͽ���λ���(��־)
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // ����
            # simulation_delay wt_crc16_end_finished <= 1'b0;
        else if((wt_stage == WT_STAGE_CRC_END) & sdio_dout_upd) // ����
            # simulation_delay wt_crc16_end_finished <= wt_crc16_end_cnt == 5'd16;
    end
    
    // �׶�:����״̬��Ϣ
    // д���ݽ���״̬���صĽ׶�
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // ��λ
            # simulation_delay wt_sts_stage <= WT_STS_WAIT_START;
        else if((wt_stage == WT_STAGE_STS) & sdio_sts_sample)
        begin
            # simulation_delay;
            
            case(wt_sts_stage)
                WT_STS_WAIT_START: // �׶�:�ȴ���ʼλ
                    if(~sdio_d0_i)
                        wt_sts_stage <= WT_STS_B2;
                WT_STS_B2: // �׶�:���յ�2��״̬λ
                    wt_sts_stage <= WT_STS_B1;
                WT_STS_B1: // �׶�:���յ�1��״̬λ
                    wt_sts_stage <= WT_STS_B0;
                WT_STS_B0: // �׶�:���յ�0��״̬λ
                    wt_sts_stage <= WT_STS_END;
                WT_STS_END: // �׶�:���ս���λ
                    wt_sts_stage <= WT_STS_END; // hold
                default:
                    wt_sts_stage <= WT_STS_WAIT_START;
            endcase
        end
    end
    
    // д����״̬����
    always @(posedge clk)
    begin
        if(sdio_sts_sample & ((wt_sts_stage == WT_STS_B2) | (wt_sts_stage == WT_STS_B1) | (wt_sts_stage == WT_STS_B0))) // ��������
            # simulation_delay wt_sts <= {wt_sts[1:0], sdio_d0_i};
    end
    
    // д����״̬���ؽ������(��־)
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // ����
            # simulation_delay wt_sts_received <= 1'b0;
        else if((~wt_sts_received) & (wt_stage == WT_STAGE_STS)) // ճ����λ
            # simulation_delay wt_sts_received <= sdio_sts_sample & (wt_sts_stage == WT_STS_END);
    end
    
    // д����״̬����AXIS��valid�ź�
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            m_axis_wt_sts_valid_reg <= 1'b0;
        else // ��������
            # simulation_delay m_axis_wt_sts_valid_reg <= (wt_stage == WT_STAGE_STS) & sdio_sts_sample & (wt_sts_stage == WT_STS_B0);
    end
    
    // �׶�:�ȴ��ӻ�idle
    // �ӻ�����(��־)
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // ����
            # simulation_delay wt_slave_idle <= 1'b0;
        else if((~wt_slave_idle) & (wt_stage == WT_STAGE_WAIT_IDLE)) // ճ����λ
            # simulation_delay wt_slave_idle <= sdio_sts_sample & sdio_d0_i;
    end
    
    /** sdio������̬�ŷ������ **/
    // 0Ϊ���, 1Ϊ����
    reg sdio_cmd_t_reg; // �����߷���
    reg[3:0] sdio_d_t_regs; // �����߷���
    
    assign sdio_cmd_t = sdio_cmd_t_reg;
    assign {sdio_d3_t, sdio_d2_t, sdio_d1_t, sdio_d0_t} = sdio_d_t_regs;
    
    // �����߷���
    // 1Ϊ����, 0Ϊ���
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sdio_cmd_t_reg <= 1'b1;
        else if(cmd_to_send_en_shift) // ����
        begin
            # simulation_delay;
            
            case(ctrler_status)
                IDLE: // ״̬:����
                    sdio_cmd_t_reg <= ~cmd_fetched;
                SEND_CMD: // ״̬:��������
                    sdio_cmd_t_reg <= sending_cmd_bit_i == (48 + cmd_pre_p_num);
                default:
                    sdio_cmd_t_reg <= 1'b1;
            endcase
        end
    end
    
    // �����߷���
    // 1Ϊ����, 0Ϊ���
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sdio_d_t_regs <= 4'b1111;
        else if(sdio_dout_upd) // ����
        begin
            # simulation_delay;
            
            if(ctrler_status == WT_DATA)
            begin
                case(wt_stage)
                    WT_STAGE_WAIT: // �׶�:д�ȴ�
                        sdio_d_t_regs <= en_wide_sdio ? {4{~wt_wait_finished}}:{3'b111, ~wt_wait_finished};
                    WT_STAGE_PULL_UP, WT_STAGE_START, WT_STAGE_TRANS: // �׶�:����ǿ�������ߵ�ƽ, ��ʼλ, ����д
                        sdio_d_t_regs <= en_wide_sdio ? 4'b0000:4'b1110;
                    WT_STAGE_CRC_END: // �׶�:У��ͽ���λ
                        sdio_d_t_regs <= en_wide_sdio ? {4{wt_crc16_end_finished}}:{3'b111, wt_crc16_end_finished};
                    WT_STAGE_STS, WT_STAGE_WAIT_IDLE, WT_STAGE_FINISHED: // �׶�:����״̬��Ϣ, �ȴ��ӻ�idle, ���
                        sdio_d_t_regs <= 4'b1111;
                    default:
                        sdio_d_t_regs <= 4'b1111;
                endcase
            end
            else
                sdio_d_t_regs <= 4'b1111;
        end
    end

endmodule
