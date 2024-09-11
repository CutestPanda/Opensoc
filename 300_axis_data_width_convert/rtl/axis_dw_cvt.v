`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXISλ��任

����: 
��AXIS�ӿڽ���λ��任
֧��λ����/������������/����/������������/����

ע�⣺
��

Э��:
AXIS MASTER/SLAVE

����: �¼�ҫ
����: 2023/11/02
********************************************************************/


module axis_dw_cvt #(
    parameter integer slave_data_width = 64, // �ӻ�����λ��(�����ܱ�8����)
    parameter integer master_data_width = 48, // ��������λ��(�����ܱ�8����)
    parameter integer slave_user_width_foreach_byte = 1, // �ӻ�ÿ�������ֽڵ�userλ��(����>=1, ����ʱ���ռ���)
    parameter en_keep = "true", // �Ƿ�ʹ��keep�ź�
    parameter en_last = "true", // �Ƿ�ʹ��last�ź�
    parameter en_out_isolation = "true", // �Ƿ������������
    parameter real simulation_delay = 1 // ������ʱ
)(
    input wire clk,
    input wire rst_n,
    
    // AXIS SLAVE
    input wire[slave_data_width-1:0] s_axis_data,
    input wire[slave_data_width/8-1:0] s_axis_keep,
    input wire[slave_data_width/8*slave_user_width_foreach_byte-1:0] s_axis_user,
    input wire s_axis_last,
    input wire s_axis_valid,
    output wire s_axis_ready,
    
    // AXIS MASTER
    output wire[master_data_width-1:0] m_axis_data,
    output wire[master_data_width/8-1:0] m_axis_keep,
    output wire[master_data_width/8*slave_user_width_foreach_byte-1:0] m_axis_user,
    output wire m_axis_last,
    output wire m_axis_valid,
    input wire m_axis_ready
);

    localparam en_keep_all0_filter = "false"; // �Ƿ����keepȫ0�ı������

    generate
        if(slave_data_width > master_data_width)
        begin
            // λ������
            if(slave_data_width % master_data_width)
            begin
                // ����������λ������
                axis_dw_cvt_not_tpc #(
                    .slave_data_width(slave_data_width),
                    .slave_user_width_foreach_byte(slave_user_width_foreach_byte),
                    .master_data_width(master_data_width),
                    .en_out_isolation(en_out_isolation),
                    .simulation_delay(simulation_delay)
                )downsizer(
                    .clk(clk),
                    .rst_n(rst_n),
                    .s_axis_data(s_axis_data),
                    .s_axis_keep((en_keep == "true") ? s_axis_keep:{(slave_data_width/8){1'b1}}),
                    .s_axis_user(s_axis_user),
                    .s_axis_valid(s_axis_valid),
                    .s_axis_ready(s_axis_ready),
                    .s_axis_last((en_last == "true") ? s_axis_last:1'b0),
                    .m_axis_data(m_axis_data),
                    .m_axis_keep(m_axis_keep),
                    .m_axis_user(m_axis_user),
                    .m_axis_valid(m_axis_valid),
                    .m_axis_ready(m_axis_ready),
                    .m_axis_last(m_axis_last)
                );
            end
            else
            begin
                // λ����
                axis_dw_cvt_downsizer #(
                    .slave_data_width(slave_data_width),
                    .slave_user_width_foreach_byte(slave_user_width_foreach_byte),
                    .master_data_width(master_data_width),
                    .en_keep(en_keep),
                    .en_out_isolation(en_out_isolation),
                    .simulation_delay(simulation_delay)
                )downsizer(
                    .clk(clk),
                    .rst_n(rst_n),
                    .s_axis_data(s_axis_data),
                    .s_axis_keep((en_keep == "true") ? s_axis_keep:{(slave_data_width/8){1'b1}}),
                    .s_axis_user(s_axis_user),
                    .s_axis_valid(s_axis_valid),
                    .s_axis_ready(s_axis_ready),
                    .s_axis_last((en_last == "true") ? s_axis_last:1'b0),
                    .m_axis_data(m_axis_data),
                    .m_axis_keep(m_axis_keep),
                    .m_axis_user(m_axis_user),
                    .m_axis_valid(m_axis_valid),
                    .m_axis_ready(m_axis_ready),
                    .m_axis_last(m_axis_last)
                );
            end
        end
        else if(slave_data_width < master_data_width)
        begin
            // λ������
            if(master_data_width % slave_data_width)
            begin
                // ����������λ������
                axis_dw_cvt_not_tpc #(
                    .slave_data_width(slave_data_width),
                    .slave_user_width_foreach_byte(slave_user_width_foreach_byte),
                    .master_data_width(master_data_width),
                    .en_out_isolation(en_out_isolation),
                    .simulation_delay(simulation_delay)
                )upsizer(
                    .clk(clk),
                    .rst_n(rst_n),
                    .s_axis_data(s_axis_data),
                    .s_axis_keep((en_keep == "true") ? s_axis_keep:{(slave_data_width/8){1'b1}}),
                    .s_axis_user(s_axis_user),
                    .s_axis_valid(s_axis_valid),
                    .s_axis_ready(s_axis_ready),
                    .s_axis_last((en_last == "true") ? s_axis_last:1'b0),
                    .m_axis_data(m_axis_data),
                    .m_axis_keep(m_axis_keep),
                    .m_axis_user(m_axis_user),
                    .m_axis_valid(m_axis_valid),
                    .m_axis_ready(m_axis_ready),
                    .m_axis_last(m_axis_last)
                );
            end
            else
            begin
                // λ����
                axis_dw_cvt_upsizer #(
                    .slave_data_width(slave_data_width),
                    .slave_user_width_foreach_byte(slave_user_width_foreach_byte),
                    .master_data_width(master_data_width),
                    .en_keep_all0_filter(((en_keep == "true") && (en_keep_all0_filter == "true")) ? "true":"false"),
                    .en_out_isolation(en_out_isolation),
                    .simulation_delay(simulation_delay)
                )upsizer(
                    .clk(clk),
                    .rst_n(rst_n),
                    .s_axis_data(s_axis_data),
                    .s_axis_keep((en_keep == "true") ? s_axis_keep:{(slave_data_width/8){1'b1}}),
                    .s_axis_user(s_axis_user),
                    .s_axis_valid(s_axis_valid),
                    .s_axis_ready(s_axis_ready),
                    .s_axis_last((en_last == "true") ? s_axis_last:1'b0),
                    .m_axis_data(m_axis_data),
                    .m_axis_keep(m_axis_keep),
                    .m_axis_user(m_axis_user),
                    .m_axis_valid(m_axis_valid),
                    .m_axis_ready(m_axis_ready),
                    .m_axis_last(m_axis_last)
                );
            end
        end
        else
        begin
            // λ����
            assign m_axis_data = s_axis_data;
            assign m_axis_keep = s_axis_keep;
            assign m_axis_user = s_axis_user;
            assign m_axis_last = s_axis_last;
            assign m_axis_valid = s_axis_valid;
            assign s_axis_ready = m_axis_ready;
        end
    endgenerate

endmodule
