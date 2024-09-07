`timescale 1ns / 1ps
/********************************************************************
��ģ��: APB-SDIO�Ŀ���/״̬�Ĵ����ӿ�

����:
�Ĵ���->
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
��

Э��:
APB SLAVE
FIFO READ/WRITE
AXIS SLAVE

����: �¼�ҫ
����: 2024/01/23
********************************************************************/


module sdio_regs_interface #(
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
    
    // ����fifoд�˿�
    output wire cmd_fifo_wen,
    input wire cmd_fifo_full,
    output wire[45:0] cmd_fifo_din,
    // ������fifo���˿�
    output wire rdata_fifo_ren,
    input wire rdata_fifo_empty,
    input wire[31:0] rdata_fifo_dout,
    // д����fifoд�˿�
    output wire wdata_fifo_wen,
    input wire wdata_fifo_full,
    output wire[31:0] wdata_fifo_din,
    
    // ������״̬
    input wire sdio_ctrler_idle,
    // ����������ʱ����
    output wire en_sdio_clk, // ����sdioʱ��(��λʱ����Ϊ0)
    output wire[9:0] div_rate, // ��Ƶϵ��(��Ƶ�� = (��Ƶϵ�� + 1) * 2)
    output wire en_wide_sdio, // ��������ģʽ
    // ��ʼ��ģ�����
    output wire init_start, // ��ʼ��ʼ������(ָʾ)
    input wire init_idle, // ��ʼ��ģ�����(��־)
    
    // ��ӦAXIS
    input wire[119:0] s_axis_resp_data, // 48bit��Ӧ -> {�����(6bit), ����(32bit)}, 136bit��Ӧ -> {����(120bit)}
    input wire[2:0] s_axis_resp_user, // {���ճ�ʱ(1bit), CRC����(1bit), �Ƿ���Ӧ(1bit)}
    input wire s_axis_resp_valid,
    // ��ʼ�����AXIS
    input wire[23:0] s_axis_init_res_data, // {����(5bit), RCA(16bit), �Ƿ��������(1bit), �Ƿ�֧��SD2.0(1bit), �Ƿ�ɹ�(1bit)}
    input wire s_axis_init_res_valid,
    // �����ݷ��ؽ��AXIS
    input wire[7:0] s_axis_rd_sts_data, // {����(3bit), ����ʱ(1bit), У����(4bit)}
    input wire s_axis_rd_sts_valid,
    // д����״̬����AXIS
    input wire[7:0] s_axis_wt_sts_data, // {����(5bit), ״̬��Ϣ(3bit)}
    input wire s_axis_wt_sts_valid,
    
    // �жϿ���
    input wire rdata_itr_org_pulse, // ������ԭʼ�ж�����
    input wire wdata_itr_org_pulse, // д����ԭʼ�ж�����
    input wire common_itr_org_pulse, // �������������ж�����
    output wire rdata_itr_en, // �������ж�ʹ��
    output wire wdata_itr_en, // д�����ж�ʹ��
    output wire common_itr_en, // �������������ж�ʹ��
    output wire global_org_itr_pulse // ȫ��ԭʼ�ж�����
);

    /** APBд�Ĵ��� **/
    // ����fifoд�˿�
    reg cmd_fifo_wen_reg;
    reg[5:0] cmd_fifo_din_id; // �����
    reg[31:0] cmd_fifo_din_params; // �������
    reg[7:0] cmd_fifo_din_rw_patch_n; // ���ζ�д�Ŀ����-1
    // д����fifoд�˿�
    reg wdata_fifo_wen_reg;
    reg[31:0] wdata_fifo_din_regs;
    // �ж�ʹ��
    reg global_itr_en_reg; // ȫ���ж�ʹ��
    reg rdata_itr_en_reg; // �������ж�ʹ��
    reg wdata_itr_en_reg; // д�����ж�ʹ��
    reg common_itr_en_reg; // �������������ж�ʹ��
    // ȫ���жϱ�־
    reg global_itr_flag;
    // ����������ʱ����
    reg en_sdio_clk_reg; // ����sdioʱ��(��λʱ����Ϊ0)
    reg en_wide_sdio_reg; // �Ƿ���������ģʽ
    reg[9:0] div_rate_regs; // ��Ƶϵ��(��Ƶ�� = (��Ƶϵ�� + 1) * 2)
    // ��ʼ��ʼ��ָʾ
    reg init_start_reg;
    
    assign cmd_fifo_wen = cmd_fifo_wen_reg;
    assign cmd_fifo_din = {cmd_fifo_din_rw_patch_n, cmd_fifo_din_id, cmd_fifo_din_params};
    assign wdata_fifo_wen = wdata_fifo_wen_reg;
    assign wdata_fifo_din = wdata_fifo_din_regs;
    assign {en_wide_sdio, div_rate, en_sdio_clk} = {en_wide_sdio_reg, div_rate_regs, en_sdio_clk_reg};
    assign init_start = init_start_reg;
    assign {common_itr_en, wdata_itr_en, rdata_itr_en} = {common_itr_en_reg, wdata_itr_en_reg, rdata_itr_en_reg};
    
    assign global_org_itr_pulse = (rdata_itr_org_pulse | wdata_itr_org_pulse | common_itr_org_pulse) & global_itr_en_reg & (~global_itr_flag);
    
    // ����fifoдʹ��
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            cmd_fifo_wen_reg <= 1'b0;
        else
            # simulation_delay cmd_fifo_wen_reg <= psel & pwrite & penable & (paddr[5:2] == 4'd1);
    end
    // �����
    always @(posedge clk)
    begin
        if(psel & pwrite & penable & (paddr[5:2] == 4'd1))
            # simulation_delay cmd_fifo_din_id <= pwdata[5:0];
    end
    // �������
    always @(posedge clk)
    begin
        if(psel & pwrite & penable & (paddr[5:2] == 4'd2))
            # simulation_delay cmd_fifo_din_params <= pwdata;
    end
    // ���ζ�д�Ŀ����-1
    always @(posedge clk)
    begin
        if(psel & pwrite & penable & (paddr[5:2] == 4'd1))
            # simulation_delay cmd_fifo_din_rw_patch_n <= pwdata[15:8];
    end
    
    // д����fifoдʹ��
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            wdata_fifo_wen_reg <= 1'b0;
        else
            # simulation_delay wdata_fifo_wen_reg <= psel & pwrite & penable & (paddr[5:2] == 4'd4);
    end
    // д����fifoд����
    always @(posedge clk)
    begin
        if(psel & pwrite & penable & (paddr[5:2] == 4'd4))
            # simulation_delay wdata_fifo_din_regs <= pwdata;
    end
    
    // �ж�ʹ��
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            {common_itr_en_reg, wdata_itr_en_reg, rdata_itr_en_reg, global_itr_en_reg} <= 4'b0000;
        else if(psel & pwrite & penable & (paddr[5:2] == 4'd5))
            # simulation_delay {common_itr_en_reg, wdata_itr_en_reg, rdata_itr_en_reg, global_itr_en_reg} <= {pwdata[10:8], pwdata[0]};
    end
    
    // ȫ���жϱ�־
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            global_itr_flag <= 1'b0;
        else if(psel & pwrite & penable & (paddr[5:2] == 4'd6)) // ����жϱ�־
            # simulation_delay global_itr_flag <= 1'b0;
        else if(~global_itr_flag)
            # simulation_delay global_itr_flag <= global_org_itr_pulse;
    end
    
    // ����sdioʱ��(��λʱ����Ϊ0)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            en_sdio_clk_reg <= 1'b0;
        else if(psel & pwrite & penable & (paddr[5:2] == 4'd11))
            # simulation_delay en_sdio_clk_reg <= pwdata[16];
    end
    // �Ƿ���������ģʽ
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            en_wide_sdio_reg <= 1'b0;
        else if(psel & pwrite & penable & (paddr[5:2] == 4'd11))
            # simulation_delay en_wide_sdio_reg <= pwdata[17];
    end
    // ��Ƶϵ��(��Ƶ�� = (��Ƶϵ�� + 1) * 2)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            div_rate_regs <= 10'd99;
        else if(psel & pwrite & penable & (paddr[5:2] == 4'd11))
            # simulation_delay div_rate_regs <= pwdata[27:18];
    end
    
    // ��ʼ��ʼ��ָʾ
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            init_start_reg <= 1'b0;
        else
            # simulation_delay init_start_reg <= psel & pwrite & penable & (paddr[5:2] == 4'd12) & pwdata[0];
    end
    
    /** ���жϱ�־ **/
    reg rdata_itr_flag; // SDIO�������жϱ�־
    reg wdata_itr_flag; // SDIOд�����жϱ�־
    reg common_itr_flag; // SDIO�������������жϱ�־
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            {rdata_itr_flag, wdata_itr_flag, common_itr_flag} <= 3'b000;
        else if(global_org_itr_pulse)
            # simulation_delay {rdata_itr_flag, wdata_itr_flag, common_itr_flag} <= {rdata_itr_org_pulse, wdata_itr_org_pulse, common_itr_org_pulse};
    end
    
    /** ��Ӧ **/
    reg[119:0] resp_content;
    reg[2:0] resp_sts;
    
    always @(posedge clk)
    begin
        if(s_axis_resp_valid)
            # simulation_delay {resp_content, resp_sts} <= {s_axis_resp_data, s_axis_resp_user};
    end
    
    /** ��ʼ����� **/
    reg[15:0] rca;
    reg init_succeeded;
    reg sd2_supported;
    reg is_large_volume_card;
    
    always @(posedge clk)
    begin
        if(s_axis_init_res_valid)
            # simulation_delay {rca, is_large_volume_card, sd2_supported, init_succeeded} <= s_axis_init_res_data[18:0];
    end
    
    /** �����ݷ��ؽ�� **/
    reg[4:0] rd_res;
    
    always @(posedge clk)
    begin
        if(s_axis_rd_sts_valid)
            # simulation_delay rd_res <= s_axis_rd_sts_data[4:0];
    end
    
    /** д����״̬����AXIS **/
    reg[2:0] wt_sts;
    
    always @(posedge clk)
    begin
        if(s_axis_wt_sts_valid)
            # simulation_delay wt_sts <= s_axis_wt_sts_data[2:0];
    end
    
    /** APB���Ĵ��� **/
    reg[31:0] prdata_out_regs;
    reg rdata_visited;
    
    assign rdata_fifo_ren = rdata_visited & penable;
    
    assign pready_out = 1'b1;
    assign prdata_out = prdata_out_regs;
    assign pslverr_out = 1'b0;
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            rdata_visited <= 1'b0;
        else
            # simulation_delay rdata_visited <= psel & (~pwrite) & (paddr[5:2] == 4'd3);
    end
    
    always @(posedge clk)
    begin
        if(psel & (~pwrite))
        begin
            # simulation_delay;
            
            case(paddr[5:2])
                4'd0:
                    prdata_out_regs <= {29'dx, wdata_fifo_full, rdata_fifo_empty, cmd_fifo_full};
                4'd3:
                    prdata_out_regs <= rdata_fifo_dout;
                4'd6:
                    prdata_out_regs <= {21'dx, common_itr_flag, wdata_itr_flag, rdata_itr_flag, 7'dx, global_itr_flag};
                4'd7:
                    prdata_out_regs <= resp_content[119:88];
                4'd8:
                    prdata_out_regs <= resp_content[87:56];
                4'd9:
                    prdata_out_regs <= resp_content[55:24];
                4'd10:
                    prdata_out_regs <= {9'dx, resp_sts, resp_content[23:0]};
                4'd11:
                    prdata_out_regs <= {21'dx, wt_sts, 2'dx, rd_res, sdio_ctrler_idle};
                4'd12:
                    prdata_out_regs <= {5'dx, is_large_volume_card, sd2_supported, init_succeeded, rca, 6'dx, init_idle, 1'bx};
                default: // not care
                    prdata_out_regs <= 32'dx;
            endcase
        end
    end

endmodule
