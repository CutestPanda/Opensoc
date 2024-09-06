`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXIS�Ĵ���Ƭ

����: 
��AXIS���ӽӿڼ����Ӹ���
�и�����AXIS���ӽӿڵ�ʱ��·��

ע�⣺
��

Э��:
AXIS MASTER/SLAVE

����: �¼�ҫ
����: 2023/10/13
********************************************************************/


module axis_reg_slice #(
    parameter integer data_width = 32, // ����λ��(�����ܱ�8����)
    parameter integer user_width = 1, // �û��ź�λ��(����>=1, ����ʱ���ռ���)
    parameter forward_registered = "false", // �Ƿ�ʹ��ǰ��Ĵ���
    parameter back_registered = "false", // �Ƿ�ʹ�ܺ���Ĵ���
    parameter en_ready = "true", // �Ƿ�ʹ��ready�ź�
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // AXIS SLAVE(�ӻ�����)
    input wire[data_width-1:0] s_axis_data,
    input wire[data_width/8-1:0] s_axis_keep,
    input wire[user_width-1:0] s_axis_user,
    input wire s_axis_last,
    input wire s_axis_valid,
    output wire s_axis_ready,
    
    // AXIS MASTER(�������)
    output wire[data_width-1:0] m_axis_data,
    output wire[data_width/8-1:0] m_axis_keep,
    output wire[user_width-1:0] m_axis_user,
    output wire m_axis_last,
    output wire m_axis_valid,
    input wire m_axis_ready
);
    
    generate
        if(en_ready == "true")
        begin
            axis_reg_slice_core #(
                .forward_registered(forward_registered),
                .back_registered(back_registered),
                .payload_width(data_width + data_width/8 + user_width + 1),
                .simulation_delay(simulation_delay)
            )axis_reg_slice_core_u(
                .clk(clk),
                .rst_n(rst_n),
                .s_payload({s_axis_data, s_axis_keep, s_axis_user, s_axis_last}),
                .s_valid(s_axis_valid),
                .s_ready(s_axis_ready),
                .m_payload({m_axis_data, m_axis_keep, m_axis_user, m_axis_last}),
                .m_valid(m_axis_valid),
                .m_ready(m_axis_ready)
            );
        end
        else if(forward_registered == "true")
        begin
            reg[data_width-1:0] m_axis_data_regs;
            reg[data_width/8-1:0] m_axis_keep_regs;
            reg[user_width-1:0] m_axis_user_regs;
            reg m_axis_last_reg;
            reg m_axis_valid_reg;
            
            assign s_axis_ready = 1'b1;
            assign {m_axis_data, m_axis_keep, m_axis_user, m_axis_last} = {m_axis_data_regs, m_axis_keep_regs, m_axis_user_regs, m_axis_last_reg};
            assign m_axis_valid = m_axis_valid_reg;
            
            always @(posedge clk)
            begin
                if(s_axis_valid)
                begin
                    # simulation_delay;
                    
                    m_axis_data_regs <= s_axis_data;
                    m_axis_keep_regs <= s_axis_keep;
                    m_axis_user_regs <= s_axis_user;
                    m_axis_last_reg <= s_axis_last;
                end
            end
            
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    m_axis_valid_reg <= 1'b0;
                else
                    # simulation_delay m_axis_valid_reg <= s_axis_valid;
            end
        end
        else
        begin
            // pass
            assign s_axis_ready = 1'b1;
            assign m_axis_data = s_axis_data;
            assign m_axis_keep = s_axis_keep;
            assign m_axis_user = s_axis_user;
            assign m_axis_last = s_axis_last;
            assign m_axis_valid = s_axis_valid;
        end
    endgenerate

endmodule
