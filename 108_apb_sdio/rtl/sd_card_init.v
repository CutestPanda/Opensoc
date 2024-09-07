`timescale 1ns / 1ps
/********************************************************************
本模块: SD卡初始化模块

描述:
初始化流程 ->
    (1)发送CMD0复位
    参数 = 32'h00000000
    该命令没有响应
    (2)发送CMD8鉴别SD1.X和SD2.0
    参数 = 32'h000001AA
    有响应 -> SD2.0以上
    无响应 -> 电压不匹配的2.0以上SD卡/1.0的SD卡/不是SD卡
    (3)发送ACMD41(CMD55 + CMD41)
    参数0 = 32'h00000000
    参数1 = 32'h40FF8000
    响应[30] -> 是否大容量卡
    响应[31] -> 是否上电
    (4)发送CMD2以获取CID
    参数 = 32'h00000000
    忽略该命令的响应
    (5)发送CMD3要求card指定一个RCA
    参数 = 32'h00000000
    响应[31:16] = RCA
    (6)发送CMD7选中卡
    参数[31:16] = RCA, 参数[15:0] = 16'h0000
    忽略该命令的响应
    (7)发送CMD16指定块大小为512Byte
    参数 = 32'h00000200
    响应[12:9] = 卡状态(4为tran状态)
    忽略该命令的响应
    (8)发送ACMD6(CMD55 + CMD6)设置总线位宽
    参数0[31:16] = RCA, 参数0[15:0] = 16'h0000
    参数1 = 启用四线模式 ? 32'h00000002:32'h00000000
    忽略该命令的响应
    (9)发送CMD6查询SD卡功能
    参数 = 32'h00FF_FF01
    忽略该命令的响应, 忽略该命令的读数据返回
    (10)发送CMD6切换到高速模式
    参数 = 32'h80FF_FF01
    忽略该命令的响应, 忽略该命令的读数据返回

注意：
无

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2024/02/29
********************************************************************/


module sd_card_init #(
    parameter integer init_acmd41_try_n = 20, // 初始化时发送ACMD41命令的尝试次数(必须<=32)
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire resetn,
    
    // 运行时参数
    input wire en_wide_sdio, // 启用四线模式
    
    // 初始化模块控制
    input wire init_start, // 开始初始化请求(指示)
    output wire init_idle, // 初始化模块空闲(标志)
    output wire init_done, // 初始化完成(指示)
    
    // 命令AXIS
    output wire[39:0] m_axis_cmd_data, // {保留(1bit), 是否忽略读数据(1bit), 命令号(6bit), 参数(32bit)}
    output wire m_axis_cmd_valid,
    input wire m_axis_cmd_ready,
    
    // 响应AXIS
    input wire[119:0] s_axis_resp_data, // 48bit响应 -> {命令号(6bit), 参数(32bit)}, 136bit响应 -> {参数(120bit)}
    input wire[2:0] s_axis_resp_user, // {接收超时(1bit), CRC错误(1bit), 是否长响应(1bit)}
    input wire s_axis_resp_valid,
    
    // 初始化结果AXIS
    output wire[23:0] m_axis_init_res_data, // {保留(5bit), RCA(16bit), 是否大容量卡(1bit), 是否支持SD2.0(1bit), 是否成功(1bit)}
    output wire m_axis_init_res_valid
);

    /** 常量 **/
    // 初始化状态
    localparam WAIT_INIT_START = 2'b00; // 状态:等待开始初始化
    localparam SEND_CMD = 2'b01; // 状态:发送命令
    localparam WAIT_RESP = 2'b10; // 状态:等待响应
    localparam INIT_FINISHED = 2'b11; // 状态:初始化完成
    
    /** 初始化状态机 **/
    wire sd_card_init_start; // 开始初始化(指示)
    reg is_first_cmd; // 第一条命令(标志)
    reg[1:0] sd_card_init_sts; // sd卡初始化状态
    reg s_axis_resp_valid_d; // 延迟1clk的响应AXIS的valid
    reg sd_card_init_failed; // sd卡初始化失败(标志)
    reg sd_card_init_cmd_last; // sd卡初始化最后1条命令(标志)
    
    assign sd_card_init_start = (sd_card_init_sts == WAIT_INIT_START) & init_start;
    
    // 第一条命令(标志)
    always @(posedge clk)
    begin
        if(sd_card_init_start)
            # simulation_delay is_first_cmd <= 1'b1;
        else if(is_first_cmd)
            # simulation_delay is_first_cmd <= sd_card_init_sts != WAIT_RESP;
    end
    
    // sd卡初始化状态
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sd_card_init_sts <= WAIT_INIT_START;
        else
        begin
            # simulation_delay;
            
            case(sd_card_init_sts)
                WAIT_INIT_START: // 状态:等待开始初始化
                    if(init_start)
                        sd_card_init_sts <= SEND_CMD; // -> 状态:发送命令
                SEND_CMD: // 状态:发送命令
                    if(m_axis_cmd_valid & m_axis_cmd_ready)
                        sd_card_init_sts <= WAIT_RESP; // -> 状态:等待响应
                WAIT_RESP: // 状态:等待响应
                    if(s_axis_resp_valid_d | is_first_cmd)
                        sd_card_init_sts <= (sd_card_init_cmd_last | sd_card_init_failed) ?
                            INIT_FINISHED: // -> 状态:初始化完成
                            SEND_CMD; // -> 状态:发送命令
                INIT_FINISHED: // 状态:初始化完成
                    sd_card_init_sts <= WAIT_INIT_START; // -> 状态:等待开始初始化
                default:
                    sd_card_init_sts <= WAIT_INIT_START;
            endcase
        end
    end
    
    // 延迟1clk的响应AXIS的valid
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            s_axis_resp_valid_d <= 1'b0;
        else
            # simulation_delay s_axis_resp_valid_d <= s_axis_resp_valid;
    end
    
    /** 初始化模块状态 **/
    reg init_idle_reg; // 初始化模块空闲(标志)
    reg init_done_reg; // 初始化完成(指示)
    
    assign init_idle = init_idle_reg;
    assign init_done = init_done_reg;
    
    // 初始化模块空闲(标志)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            init_idle_reg <= 1'b1;
        else
            # simulation_delay init_idle_reg <= init_idle ? (~init_start):init_done;
    end
    // 初始化完成(指示)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            init_done_reg <= 1'b0;
        else
            # simulation_delay init_done_reg <= (sd_card_init_sts == WAIT_RESP) &
                s_axis_resp_valid_d & (sd_card_init_cmd_last | sd_card_init_failed);
    end
    
    /** 发送命令控制 **/
    /*
    命令索引 子命令索引 命令号
       0        X      CMD0
       1        X      CMD8
       2        0      CMD55
                1      CMD41
       3        X      CMD2
       4        X      CMD3
       5        X      CMD7
       6        X      CMD16
       7        0      CMD55
                1      CMD6
       8        X      CMD6
       9        X      CMD6
    */
    reg[3:0] cmd_id; // 命令索引
    reg sub_cmd_id; // 命令子索引
    reg[5:0] m_axis_cmd_data_cmd_id; // 命令AXIS的命令号
    reg[15:0] rca; // RCA
    reg[31:0] m_axis_cmd_data_cmd_pars; // 命令AXIS的命令参数
    reg m_axis_cmd_valid_reg; // 命令AXIS的valid
    reg[4:0] acmd41_try_cnt; // ACMD41尝试次数(计数器)
    wire acmd41_succeeded; // ACMD41成功(指示)
    reg acmd41_try_last; // ACMD41最后1次尝试(标志)
    
    assign m_axis_cmd_data = {1'b0, 1'b1, m_axis_cmd_data_cmd_id, m_axis_cmd_data_cmd_pars};
    assign m_axis_cmd_valid = m_axis_cmd_valid_reg;
    
    // sd卡初始化最后1条命令(标志)
    always @(posedge clk)
    begin
        if(sd_card_init_start)
            # simulation_delay sd_card_init_cmd_last <= 1'b0;
        else if(m_axis_cmd_valid & m_axis_cmd_ready)
            # simulation_delay sd_card_init_cmd_last <= cmd_id == 4'd9;
    end
    
    // 命令索引
    always @(posedge clk)
    begin
        if(sd_card_init_start)
            # simulation_delay cmd_id <= 4'd0;
        else if((cmd_id == 4'd2) ? acmd41_succeeded:
                (cmd_id == 4'd7) ? (m_axis_cmd_valid & m_axis_cmd_ready & sub_cmd_id):
                                   (m_axis_cmd_valid & m_axis_cmd_ready))
            # simulation_delay cmd_id <= cmd_id + 4'd1;
    end
    // 命令子索引
    always @(posedge clk)
    begin
        if(sd_card_init_start)
            # simulation_delay sub_cmd_id <= 1'b0;
        else if(m_axis_cmd_valid & m_axis_cmd_ready & ((cmd_id == 4'd2) | (cmd_id == 4'd7)))
            # simulation_delay sub_cmd_id <= ~sub_cmd_id;
    end
    
    // 命令AXIS的命令号
    always @(posedge clk)
    begin
        if(sd_card_init_start)
            # simulation_delay m_axis_cmd_data_cmd_pars <= 32'h0000_0000;
        else
        begin
            # simulation_delay;
            
            case(cmd_id)
                4'd0: m_axis_cmd_data_cmd_pars <= 32'h0000_0000;
                4'd1: m_axis_cmd_data_cmd_pars <= 32'h0000_01AA;
                4'd2: m_axis_cmd_data_cmd_pars <= sub_cmd_id ? 32'h40FF_8000:32'h0000_0000;
                4'd3: m_axis_cmd_data_cmd_pars <= 32'h0000_0000;
                4'd4: m_axis_cmd_data_cmd_pars <= 32'h0000_0000;
                4'd5: m_axis_cmd_data_cmd_pars <= {rca, 16'h0000};
                4'd6: m_axis_cmd_data_cmd_pars <= 32'h0000_0200;
                4'd7: m_axis_cmd_data_cmd_pars <= sub_cmd_id ? (en_wide_sdio ? 32'h0000_0002:32'h0000_0000):{rca, 16'h0000};
                4'd8: m_axis_cmd_data_cmd_pars <= 32'h00FF_FF01;
                4'd9: m_axis_cmd_data_cmd_pars <= 32'h80FF_FF01;
                default: m_axis_cmd_data_cmd_pars <= 32'h0000_0000;
            endcase
        end
    end
    // 命令AXIS的命令参数
    always @(posedge clk)
    begin
        if(sd_card_init_start)
            # simulation_delay m_axis_cmd_data_cmd_id <= 6'd0;
        else
        begin
            # simulation_delay;
            
            case(cmd_id)
                4'd0: m_axis_cmd_data_cmd_id <= 6'd0;
                4'd1: m_axis_cmd_data_cmd_id <= 6'd8;
                4'd2: m_axis_cmd_data_cmd_id <= sub_cmd_id ? 6'd41:6'd55;
                4'd3: m_axis_cmd_data_cmd_id <= 6'd2;
                4'd4: m_axis_cmd_data_cmd_id <= 6'd3;
                4'd5: m_axis_cmd_data_cmd_id <= 6'd7;
                4'd6: m_axis_cmd_data_cmd_id <= 6'd16;
                4'd7: m_axis_cmd_data_cmd_id <= sub_cmd_id ? 6'd6:6'd55;
                4'd8, 4'd9: m_axis_cmd_data_cmd_id <= 6'd6;
                default: m_axis_cmd_data_cmd_id <= 6'd0;
            endcase
        end
    end
    // 命令AXIS的valid
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            m_axis_cmd_valid_reg <= 1'b0;
        else
            # simulation_delay m_axis_cmd_valid_reg <= m_axis_cmd_valid_reg ?
                (~m_axis_cmd_ready):
                (sd_card_init_start | ((sd_card_init_sts == WAIT_RESP) & (s_axis_resp_valid_d | is_first_cmd) & (~(sd_card_init_cmd_last | sd_card_init_failed))));
    end
    
    // ACMD41尝试次数(计数器)
    always @(posedge clk)
    begin
        if(sd_card_init_start)
            # simulation_delay acmd41_try_cnt <= 5'd0;
        else if(((cmd_id == 4'd2) & sub_cmd_id) & m_axis_cmd_valid & m_axis_cmd_ready)
            # simulation_delay acmd41_try_cnt <= acmd41_try_cnt + 5'd1;
    end
    // ACMD41最后1次尝试(标志)
    always @(posedge clk)
    begin
        if(sd_card_init_start)
            # simulation_delay acmd41_try_last <= 1'b0;
        else if(((cmd_id == 4'd2) & sub_cmd_id) & m_axis_cmd_valid & m_axis_cmd_ready)
            # simulation_delay acmd41_try_last <= acmd41_try_cnt == (init_acmd41_try_n - 1);
    end
    
    /** 响应处理 **/
    /*
    命令索引 子命令索引 命令号
       0        X      CMD0
       1        X      CMD8
       2        0      CMD55
                1      CMD41
       3        X      CMD2
       4        X      CMD3
       5        X      CMD7
       6        X      CMD16
       7        0      CMD55
                1      CMD6
       8        X      CMD6
       9        X      CMD6
    */
    reg[3:0] now_cmd_id; // 当前命令的索引
    reg now_sub_cmd_id; // 当前命令的子索引
    
    assign acmd41_succeeded = s_axis_resp_valid & ((now_cmd_id == 4'd2) & now_sub_cmd_id) &
        (~s_axis_resp_user[1]) & (~s_axis_resp_user[2]) & s_axis_resp_data[31];
    
    // sd卡初始化失败(标志)
    always @(posedge clk)
    begin
        if(sd_card_init_start)
            # simulation_delay sd_card_init_failed <= 1'b0;
        else if((~sd_card_init_failed) & s_axis_resp_valid)
            # simulation_delay sd_card_init_failed <= s_axis_resp_user[1] | // CRC错误
                ((now_cmd_id == 4'd1) ? 1'b0:s_axis_resp_user[2]) | // 接收超时(CMD8除外)
                (((now_cmd_id == 4'd2) & now_sub_cmd_id) & acmd41_try_last & (~s_axis_resp_data[31])) | // ACMD41失败
                ((now_cmd_id == 4'd6) & (s_axis_resp_data[12:9] != 4'd4)); // 选中卡后未进入tran状态
    end
    
    // RCA
    always @(posedge clk)
    begin
        if(s_axis_resp_valid & (now_cmd_id == 4'd4))
            # simulation_delay rca <= s_axis_resp_data[31:16];
    end
    
    // 当前命令的索引
    // 当前命令的子索引
    always @(posedge clk)
    begin
        if(m_axis_cmd_valid & m_axis_cmd_ready)
            # simulation_delay {now_cmd_id, now_sub_cmd_id} <= {cmd_id, sub_cmd_id};
    end
    
    // 初始化结果AXIS
    reg is_large_volume_card; // 是否大容量卡
    reg sd2_supported; // 是否支持SD2.0
    reg init_succeeded; // 初始化成功
    reg m_axis_init_res_valid_reg; // 初始化结果AXIS的valid
    
    assign m_axis_init_res_data = {5'd0, rca, is_large_volume_card, sd2_supported, init_succeeded};
    assign m_axis_init_res_valid = m_axis_init_res_valid_reg;
    
    // 是否大容量卡
    always @(posedge clk)
    begin
        if(s_axis_resp_valid & ((now_cmd_id == 4'd2) & now_sub_cmd_id))
            # simulation_delay is_large_volume_card <= s_axis_resp_data[30];
    end
    // 是否支持SD2.0
    always @(posedge clk)
    begin
        if(s_axis_resp_valid & (now_cmd_id == 4'd1))
            # simulation_delay sd2_supported <= ~s_axis_resp_user[2];
    end
    // 初始化成功
    always @(posedge clk)
    begin
        if(init_done)
            # simulation_delay init_succeeded <= ~sd_card_init_failed;
    end
    
    // 初始化结果AXIS的valid
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            m_axis_init_res_valid_reg <= 1'b0;
        else
            # simulation_delay m_axis_init_res_valid_reg <= init_done;
    end

endmodule
