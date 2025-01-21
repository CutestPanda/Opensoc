`timescale 1ns / 1ps
/********************************************************************
��ģ��: APB-TIMER�ļĴ����ӿ�

����: 
�Ĵ���->
    ƫ����  |    ����                     |   ��д����    |        ��ע
    0x00    timer_width-1~0:Ԥ��Ƶϵ��-1         W
    0x04    timer_width-1~0:�Զ�װ��ֵ-1         W
    0x08    timer_width-1~0:��ʱ������ֵ         RW
    0x0C    0:�Ƿ�������ʱ��                     W
            11~8:����/�Ƚ�ѡ��(4��ͨ��)          W
    0x10    0:ȫ���ж�ʹ��                       W
            8:��������ж�ʹ��                   W
            12~9:���벶���ж�ʹ��                W
    0x14    0:ȫ���жϱ�־                       RWC
            8:��������жϱ�־                   R
            12~9:���벶���жϱ�־                R
    0x18    timer_width-1~0:����/�Ƚ�ֵ(ͨ��1)   RW       ��ʹ�ܲ���/�Ƚ�ͨ��1ʱ����
    0x1C    7~0:�����˲���ֵ                     W        ��ʹ�ܲ���/�Ƚ�ͨ��1ʱ����
            9~8:���ؼ������                     W
    0x20    timer_width-1~0:����/�Ƚ�ֵ(ͨ��2)   RW       ��ʹ�ܲ���/�Ƚ�ͨ��2ʱ����
    0x24    7~0:�����˲���ֵ                     W        ��ʹ�ܲ���/�Ƚ�ͨ��2ʱ����
            9~8:���ؼ������                     W
    0x28    timer_width-1~0:����/�Ƚ�ֵ(ͨ��3)   RW       ��ʹ�ܲ���/�Ƚ�ͨ��3ʱ����
    0x2C    7~0:�����˲���ֵ                     W        ��ʹ�ܲ���/�Ƚ�ͨ��3ʱ����
            9~8:���ؼ������                     W
    0x30    timer_width-1~0:����/�Ƚ�ֵ(ͨ��4)   RW       ��ʹ�ܲ���/�Ƚ�ͨ��4ʱ����
    0x34    7~0:�����˲���ֵ                     W        ��ʹ�ܲ���/�Ƚ�ͨ��4ʱ����
            9~8:���ؼ������                     W

ע�⣺
��

Э��:
APB SLAVE

����: �¼�ҫ
����: 2024/06/09
********************************************************************/


module regs_if_for_timer #(
    parameter integer timer_width = 16, // ��ʱ��λ��(16 | 32)
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
    
    // Ԥ��Ƶϵ�� - 1
    output wire[timer_width-1:0] prescale,
    // �Զ�װ��ֵ - 1
    output wire[timer_width-1:0] autoload,
    
    // ��ʱ������ֵ
    output wire timer_cnt_to_set,
    output wire[timer_width-1:0] timer_cnt_set_v,
    input wire[timer_width-1:0] timer_cnt_now_v,
    
    // �Ƿ�������ʱ��
    output wire timer_started,
    // ����/�Ƚ�ѡ��(4��ͨ��)
    // 1'b0 -> ����, 1'b1 -> �Ƚ�
    output wire[3:0] cap_cmp_sel,
    
    // ����/�Ƚ�ֵ(ͨ��1)
    output wire[timer_width-1:0] timer_chn1_cmp,
    input wire[timer_width-1:0] timer_chn1_cap_cmp_i,
    // �����˲���ֵ(ͨ��1)
    output wire[7:0] timer_chn1_cap_filter_th,
    // ���ؼ������(ͨ��1)
    // 2'b00 -> ������, 2'b01 -> �½���, 2'b10 -> ����/�½���, 2'b11 -> ����
    output wire[1:0] timer_chn1_cap_edge,
    
    // ����/�Ƚ�ֵ(ͨ��2)
    output wire[timer_width-1:0] timer_chn2_cmp,
    input wire[timer_width-1:0] timer_chn2_cap_cmp_i,
    // �����˲���ֵ(ͨ��2)
    output wire[7:0] timer_chn2_cap_filter_th,
    // ���ؼ������(ͨ��2)
    // 2'b00 -> ������, 2'b01 -> �½���, 2'b1x -> ����/�½���
    output wire[1:0] timer_chn2_cap_edge,
    
    // ����/�Ƚ�ֵ(ͨ��3)
    output wire[timer_width-1:0] timer_chn3_cmp,
    input wire[timer_width-1:0] timer_chn3_cap_cmp_i,
    // �����˲���ֵ(ͨ��3)
    output wire[7:0] timer_chn3_cap_filter_th,
    // ���ؼ������(ͨ��3)
    // 2'b00 -> ������, 2'b01 -> �½���, 2'b1x -> ����/�½���
    output wire[1:0] timer_chn3_cap_edge,
    
    // ����/�Ƚ�ֵ(ͨ��4)
    output wire[timer_width-1:0] timer_chn4_cmp,
    input wire[timer_width-1:0] timer_chn4_cap_cmp_i,
    // �����˲���ֵ(ͨ��4)
    output wire[7:0] timer_chn4_cap_filter_th,
    // ���ؼ������(ͨ��4)
    // 2'b00 -> ������, 2'b01 -> �½���, 2'b1x -> ����/�½���
    output wire[1:0] timer_chn4_cap_edge,
    
    // �ж�����
    input wire timer_expired_itr_req, // ��������ж�����
    input wire[3:0] timer_cap_itr_req, // ���벶���ж�����
    
    // �ж��ź�
    output wire itr
);

    /** APBд�Ĵ��� **/
    // 0x00
    reg[31:0] prescale_regs; // Ԥ��Ƶϵ��-1
    // 0x04
    reg[31:0] autoload_regs; // �Զ�װ��ֵ - 1
    // 0x08
    reg timer_cnt_to_set_reg; // ��ʱ������ֵ����ָʾ
    reg[31:0] timer_cnt_set_v_regs; // ��ʱ������ֵ������
    // 0x0C
    reg timer_started_reg; // �Ƿ�������ʱ��
    reg[3:0] cap_cmp_sel_regs; // ����/�Ƚ�ѡ��
    // 0x10
    reg global_itr_en; // ȫ���ж�ʹ��
    reg timer_expired_itr_en; // ��������ж�ʹ��
    reg[3:0] timer_cap_itr_en; // ���벶���ж�ʹ��
    // 0x14
    wire[4:0] org_itr_req_vec; // ԭʼ�ж���������
    wire org_global_itr_req; // ԭʼ���ж�����
    reg global_itr_flag; // ȫ���жϱ�־
    reg timer_expired_itr_flag; // ��������жϱ�־
    reg[3:0] timer_cap_itr_flag; // ���벶���жϱ�־
    // 0x18
    reg[31:0] timer_chn1_cmp_regs; // ��ʱ���Ƚ�ֵ������(ͨ��1)
    // 0x1C
    reg[7:0] timer_chn1_cap_filter_th_regs; // �����˲���ֵ(ͨ��1)
    reg[1:0] timer_chn1_cap_edge_regs; // ���ؼ������(ͨ��1)
    // 0x20
    reg[31:0] timer_chn2_cmp_regs; // ��ʱ���Ƚ�ֵ������(ͨ��2)
    // 0x24
    reg[7:0] timer_chn2_cap_filter_th_regs; // �����˲���ֵ(ͨ��2)
    reg[1:0] timer_chn2_cap_edge_regs; // ���ؼ������(ͨ��2)
    // 0x28
    reg[31:0] timer_chn3_cmp_regs; // ��ʱ���Ƚ�ֵ������(ͨ��3)
    // 0x2C
    reg[7:0] timer_chn3_cap_filter_th_regs; // �����˲���ֵ(ͨ��3)
    reg[1:0] timer_chn3_cap_edge_regs; // ���ؼ������(ͨ��3)
    // 0x30
    reg[31:0] timer_chn4_cmp_regs; // ��ʱ���Ƚ�ֵ������(ͨ��4)
    // 0x34
    reg[7:0] timer_chn4_cap_filter_th_regs; // �����˲���ֵ(ͨ��4)
    reg[1:0] timer_chn4_cap_edge_regs; // ���ؼ������(ͨ��4)
    
    assign prescale = prescale_regs[timer_width-1:0];
    assign autoload = autoload_regs[timer_width-1:0];
    assign timer_cnt_to_set = timer_cnt_to_set_reg;
    assign timer_cnt_set_v = timer_cnt_set_v_regs[timer_width-1:0];
    assign timer_started = timer_started_reg;
    assign cap_cmp_sel = cap_cmp_sel_regs;
    assign timer_chn1_cmp = timer_chn1_cmp_regs[timer_width-1:0];
    assign {timer_chn1_cap_edge, timer_chn1_cap_filter_th} = {timer_chn1_cap_edge_regs, timer_chn1_cap_filter_th_regs};
    assign timer_chn2_cmp = timer_chn2_cmp_regs[timer_width-1:0];
    assign {timer_chn2_cap_edge, timer_chn2_cap_filter_th} = {timer_chn2_cap_edge_regs, timer_chn2_cap_filter_th_regs};
    assign timer_chn3_cmp = timer_chn3_cmp_regs[timer_width-1:0];
    assign {timer_chn3_cap_edge, timer_chn3_cap_filter_th} = {timer_chn3_cap_edge_regs, timer_chn3_cap_filter_th_regs};
    assign timer_chn4_cmp = timer_chn4_cmp_regs[timer_width-1:0];
    assign {timer_chn4_cap_edge, timer_chn4_cap_filter_th} = {timer_chn4_cap_edge_regs, timer_chn4_cap_filter_th_regs};
    
    // Ԥ��Ƶϵ��-1
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd0))
            # simulation_delay prescale_regs <= pwdata;
    end
    
    // �Զ�װ��ֵ - 1
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd1))
            # simulation_delay autoload_regs <= pwdata;
    end
    
    // ��ʱ������ֵ����ָʾ
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            timer_cnt_to_set_reg <= 1'b0;
        else
            # simulation_delay timer_cnt_to_set_reg <= psel & penable & pwrite & (paddr[5:2] == 4'd2);
    end
    // ��ʱ������ֵ������
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd2))
            # simulation_delay timer_cnt_set_v_regs <= pwdata;
    end
    
    // �Ƿ�������ʱ��
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            timer_started_reg <= 1'b0;
        else if(psel & penable & pwrite & (paddr[5:2] == 4'd3))
            # simulation_delay timer_started_reg <= pwdata[0];
    end
    // ����/�Ƚ�ѡ��
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd3))
            # simulation_delay cap_cmp_sel_regs <= pwdata[11:8];
    end
    
    // ȫ���ж�ʹ��
    // ��������ж�ʹ��
    // ���벶���ж�ʹ��
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            {timer_cap_itr_en, timer_expired_itr_en, global_itr_en} <= 6'd0;
        else if(psel & penable & pwrite & (paddr[5:2] == 4'd4))
            # simulation_delay {timer_cap_itr_en, timer_expired_itr_en, global_itr_en} <= {pwdata[12:8], pwdata[0]};
    end
    
    // ȫ���жϱ�־
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            global_itr_flag <= 1'b0;
        else if(psel & penable & pwrite & (paddr[5:2] == 4'd5))
            # simulation_delay global_itr_flag <= 1'b0;
        else if(~global_itr_flag)
            # simulation_delay global_itr_flag <= org_global_itr_req;
    end
    // ��������жϱ�־
    // ���벶���жϱ�־
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            {timer_cap_itr_flag, timer_expired_itr_flag} <= 5'd0;
        else if(org_global_itr_req)
            # simulation_delay {timer_cap_itr_flag, timer_expired_itr_flag} <= org_itr_req_vec;
    end
    
    // ��ʱ���Ƚ�ֵ������
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd6))
            # simulation_delay timer_chn1_cmp_regs <= pwdata;
    end
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd8))
            # simulation_delay timer_chn2_cmp_regs <= pwdata;
    end
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd10))
            # simulation_delay timer_chn3_cmp_regs <= pwdata;
    end
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd12))
            # simulation_delay timer_chn4_cmp_regs <= pwdata;
    end
    
    // �����˲���ֵ
    // ���ؼ������
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd7))
            # simulation_delay {timer_chn1_cap_edge_regs, timer_chn1_cap_filter_th_regs} <= pwdata[9:0];
    end
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd9))
            # simulation_delay {timer_chn2_cap_edge_regs, timer_chn2_cap_filter_th_regs} <= pwdata[9:0];
    end
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd11))
            # simulation_delay {timer_chn3_cap_edge_regs, timer_chn3_cap_filter_th_regs} <= pwdata[9:0];
    end
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[5:2] == 4'd13))
            # simulation_delay {timer_chn4_cap_edge_regs, timer_chn4_cap_filter_th_regs} <= pwdata[9:0];
    end
    
    /** �жϴ��� **/
    assign org_itr_req_vec = {timer_cap_itr_req, timer_expired_itr_req} & {timer_cap_itr_en, timer_expired_itr_en};
    assign org_global_itr_req = (|org_itr_req_vec) & global_itr_en & (~global_itr_flag);
    
    /** APB���Ĵ��� **/
    reg[31:0] prdata_out_regs;
    
    assign pready_out = 1'b1;
    assign prdata_out = prdata_out_regs;
    assign pslverr_out = 1'b0;
    
    // APB������
    always @(posedge clk)
    begin
        if(psel & (~pwrite))
        begin
            case(paddr[5:2])
                4'd2: prdata_out_regs <= {{(32-timer_width){1'b0}}, timer_cnt_now_v};
                4'd5: prdata_out_regs <= {16'dx, 3'dx, timer_cap_itr_flag, timer_expired_itr_flag, 7'dx, global_itr_flag};
                4'd6: prdata_out_regs <= {{(32-timer_width){1'b0}}, timer_chn1_cap_cmp_i};
                4'd8: prdata_out_regs <= {{(32-timer_width){1'b0}}, timer_chn2_cap_cmp_i};
                4'd10: prdata_out_regs <= {{(32-timer_width){1'b0}}, timer_chn3_cap_cmp_i};
                4'd12: prdata_out_regs <= {{(32-timer_width){1'b0}}, timer_chn4_cap_cmp_i};
                default: prdata_out_regs <= 32'dx;
            endcase
        end
    end
    
    // �жϷ�����
    itr_generator #(
        .pulse_w(10),
        .simulation_delay(simulation_delay)
    )itr_generator_u(
        .clk(clk),
        .rst_n(resetn),
        
        .itr_org(org_global_itr_req),
        
        .itr(itr)
    );

endmodule
