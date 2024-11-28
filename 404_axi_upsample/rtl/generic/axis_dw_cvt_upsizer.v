`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXISλ������

����: 
��axis�ӻ�������λ����������
��ѡ���������

ע�⣺
��

Э��:
AXIS MASTER/SLAVE

����: �¼�ҫ
����: 2023/11/02
********************************************************************/


module axis_dw_cvt_upsizer #(
    parameter integer slave_data_width = 16, // �ӻ�����λ��(�����ܱ�8����)
    parameter integer slave_user_width_foreach_byte = 1, // �ӻ�ÿ�������ֽڵ�userλ��(����>=1, ����ʱ���ռ���)
    parameter integer master_data_width = 32, // ��������λ��(�����ܱ�8����, ��Ϊ�ӻ�����λ��������)
    parameter en_keep_all0_filter = "false", // �Ƿ����keepȫ0�ı������
    parameter en_out_isolation = "false", // �Ƿ������������
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // AXIS SLAVE
    input wire[slave_data_width-1:0] s_axis_data,
    input wire[slave_data_width/8-1:0] s_axis_keep,
    input wire[slave_user_width_foreach_byte*slave_data_width/8-1:0] s_axis_user,
    input wire s_axis_last,
    input wire s_axis_valid,
    output wire s_axis_ready,
    
    // AXIS MASTER
    output wire[master_data_width-1:0] m_axis_data,
    output wire[master_data_width/8-1:0] m_axis_keep,
    output wire[slave_user_width_foreach_byte*master_data_width/8-1:0] m_axis_user,
    output wire m_axis_last,
    output wire m_axis_valid,
    input wire m_axis_ready
);
    
    /** ���� **/
    localparam integer upsize_scale = master_data_width/slave_data_width; // λ����ϵ��
    
    /** ������� **/
    wire[master_data_width-1:0] out_axis_data;
    wire[master_data_width/8-1:0] out_axis_keep;
    wire[slave_user_width_foreach_byte*master_data_width/8-1:0] out_axis_user;
    wire out_axis_last;
    wire out_axis_valid;
    wire out_axis_ready;
    
    generate
        if(en_out_isolation == "true")
        begin
            axis_reg_slice #(
                .data_width(master_data_width),
                .user_width(slave_user_width_foreach_byte*master_data_width/8),
                .en_ready("true"),
                .forward_registered("true"),
                .back_registered("true"),
                .simulation_delay(simulation_delay)
            )out_reg_slice(
                .clk(clk),
                .rst_n(rst_n),
                .s_axis_data(out_axis_data),
                .s_axis_keep(out_axis_keep),
                .s_axis_user(out_axis_user),
                .s_axis_last(out_axis_last),
                .s_axis_valid(out_axis_valid),
                .s_axis_ready(out_axis_ready),
                .m_axis_data(m_axis_data),
                .m_axis_keep(m_axis_keep),
                .m_axis_user(m_axis_user),
                .m_axis_last(m_axis_last),
                .m_axis_valid(m_axis_valid),
                .m_axis_ready(m_axis_ready)
            );
        end
        else
        begin
            assign m_axis_data = out_axis_data;
            assign m_axis_keep = out_axis_keep;
            assign m_axis_user = out_axis_user;
            assign m_axis_last = out_axis_last;
            assign m_axis_valid = out_axis_valid;
            assign out_axis_ready = m_axis_ready;
        end
    endgenerate
    
    /** λ���� **/
    reg[slave_data_width-1:0] data_latched[upsize_scale-2:0]; // data����
    reg[slave_data_width/8-1:0] keep_latched[upsize_scale-2:0]; // keep����
    reg[slave_user_width_foreach_byte*slave_data_width/8-1:0] user_latched[upsize_scale-2:0]; // user����
    reg[upsize_scale-1:0] upsize_onehot; // ������һ�������
    reg upsize_keep_all0_n; // ��ǰ�����ִ�keepȫ0(��־)
    wire upsize_o_valid; // ���������Ч
    
    assign upsize_o_valid = s_axis_valid & (upsize_onehot[upsize_scale-1] | s_axis_last);
    
    genvar data_user_latched_i;
    generate
        for(data_user_latched_i = 0;data_user_latched_i < upsize_scale-1;data_user_latched_i = data_user_latched_i + 1)
        begin
            always @(posedge clk)
            begin
                if(upsize_onehot[data_user_latched_i])
                begin
                    # simulation_delay;
                    
                    data_latched[data_user_latched_i] <= s_axis_data;
                    user_latched[data_user_latched_i] <= s_axis_user;
                end
            end
            
            always @(posedge clk)
            begin
                if(upsize_o_valid & out_axis_ready)
                    # simulation_delay keep_latched[data_user_latched_i] <= 0;
                else if(upsize_onehot[data_user_latched_i])
                    # simulation_delay keep_latched[data_user_latched_i] <= s_axis_keep;
            end
        end
    endgenerate
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            upsize_onehot <= 1;
        else if(s_axis_valid & s_axis_ready)
            # simulation_delay upsize_onehot <= s_axis_last ? 1:{upsize_onehot[upsize_scale-2:0], upsize_onehot[upsize_scale-1]};
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            upsize_keep_all0_n <= 1'b0;
        else if(upsize_o_valid & out_axis_ready)
            # simulation_delay upsize_keep_all0_n <= 1'b0;
        else if(s_axis_valid & s_axis_ready)
            # simulation_delay upsize_keep_all0_n <= upsize_keep_all0_n | (|s_axis_keep);
    end
    
    /** λ��任��� **/
    assign s_axis_ready = (~(upsize_onehot[upsize_scale-1] | s_axis_last)) | out_axis_ready;
    
    assign out_axis_data[master_data_width-1:master_data_width-slave_data_width] = s_axis_data;
    assign out_axis_keep[master_data_width/8-1:master_data_width/8-slave_data_width/8] = upsize_onehot[0] ? 0:s_axis_keep;
    assign out_axis_user[slave_user_width_foreach_byte*master_data_width/8-1:
        slave_user_width_foreach_byte*master_data_width/8-(slave_user_width_foreach_byte*slave_data_width/8)] = s_axis_user;
    assign out_axis_last = s_axis_last;
    
    genvar upsize_scale_i;
    generate
        if(en_keep_all0_filter == "true")
            assign out_axis_valid = upsize_o_valid & (upsize_keep_all0_n | (|s_axis_keep));
        else
            assign out_axis_valid = upsize_o_valid;
        
        for(upsize_scale_i = 0;upsize_scale_i < upsize_scale-1;upsize_scale_i = upsize_scale_i + 1)
        begin
            assign out_axis_data[upsize_scale_i*slave_data_width+(slave_data_width-1):upsize_scale_i*slave_data_width] = 
                (upsize_scale_i == 0) ? (upsize_onehot[0] ? s_axis_data:data_latched[0]):data_latched[upsize_scale_i];
            assign out_axis_keep[upsize_scale_i*(slave_data_width/8)+(slave_data_width/8-1):upsize_scale_i*(slave_data_width/8)] = 
                (upsize_scale_i == 0) ? (upsize_onehot[0] ? s_axis_keep:keep_latched[0]):keep_latched[upsize_scale_i];
            assign out_axis_user[upsize_scale_i*(slave_user_width_foreach_byte*slave_data_width/8)+(slave_user_width_foreach_byte*slave_data_width/8-1):
                upsize_scale_i*(slave_user_width_foreach_byte*slave_data_width/8)] = 
                (upsize_scale_i == 0) ? (upsize_onehot[0] ? s_axis_user:user_latched[0]):user_latched[upsize_scale_i];
        end
    endgenerate

endmodule
