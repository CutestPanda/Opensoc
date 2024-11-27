`timescale 1ns / 1ps
/********************************************************************
本模块: AXIS位宽变换

描述: 
对AXIS接口进行位宽变换
支持位宽倍增/非整数倍增加/倍缩/非整数倍缩减/不变

注意：
无

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2023/11/02
********************************************************************/


module axis_dw_cvt #(
    parameter integer slave_data_width = 64, // 从机数据位宽(必须能被8整除)
    parameter integer master_data_width = 48, // 主机数据位宽(必须能被8整除)
    parameter integer slave_user_width_foreach_byte = 1, // 从机每个数据字节的user位宽(必须>=1, 不用时悬空即可)
    parameter en_keep = "true", // 是否使用keep信号
    parameter en_last = "true", // 是否使用last信号
    parameter en_out_isolation = "true", // 是否启用输出隔离
    parameter real simulation_delay = 1 // 仿真延时
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

    localparam en_keep_all0_filter = "false"; // 是否过滤keep全0的倍增输出

    generate
        if(slave_data_width > master_data_width)
        begin
            // 位宽缩减
            if(slave_data_width % master_data_width)
            begin
                // 非整数倍的位宽缩减
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
                // 位宽倍减
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
            // 位宽增加
            if(master_data_width % slave_data_width)
            begin
                // 非整数倍的位宽增加
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
                // 位宽倍增
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
            // 位宽不变
            assign m_axis_data = s_axis_data;
            assign m_axis_keep = s_axis_keep;
            assign m_axis_user = s_axis_user;
            assign m_axis_last = s_axis_last;
            assign m_axis_valid = s_axis_valid;
            assign s_axis_ready = m_axis_ready;
        end
    endgenerate

endmodule
