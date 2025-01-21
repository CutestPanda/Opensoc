`timescale 1ns / 1ps
/********************************************************************
本模块: I2C控制器

描述: 
通用IC2控制器
支持7位/10位地址

发送fifo数据包格式：
    写数据 -> last0 xxxx_xxx0 地址阶段
             [last0 xxxx_xxxx 地址阶段(仅10位地址时需要)]
             last0 xxxx_xxxx 数据阶段
             ...
             last1 xxxx_xxxx 数据阶段
    读数据 -> last0 xxxx_xxx1 地址阶段
             [last0 xxxx_xxxx 地址阶段(仅10位地址时需要)]
             last1 8位待读取字节数

注意：
每个I2C数据包不能超过15字节

协议:
I2C MASTER

作者: 陈家耀
日期: 2024/06/14
********************************************************************/


module i2c_ctrler #(
    parameter integer addr_bits_n = 7, // 地址位数(7|10)
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire resetn,
    
    // I2C时钟分频系数
    // 分频数 = (分频系数 + 1) * 2
    // 断言:分频系数>=1!
    input wire[7:0] i2c_scl_div_rate,
    
    // 发送fifo读端口
    output wire tx_fifo_ren,
    input wire tx_fifo_empty,
    input wire[7:0] tx_fifo_dout,
    input wire tx_fifo_dout_last,
    // 接收fifo写端口
    output wire rx_fifo_wen,
    input wire rx_fifo_full,
    output wire[7:0] rx_fifo_din,
    
    // I2C发送完成指示
    output wire i2c_tx_done,
    output wire[3:0] i2c_tx_bytes_n,
    // I2C接收完成指示
    output wire i2c_rx_done,
    output wire[3:0] i2c_rx_bytes_n,
    // I2C从机响应错误
    output wire i2c_slave_resp_err,
    // I2C接收溢出
    output wire i2c_rx_overflow,
    
    // I2C主机接口
    // scl
    output wire scl_t, // 1'b1为输入, 1'b0为输出
    input wire scl_i,
    output wire scl_o,
    // sda
    output wire sda_t, // 1'b1为输入, 1'b0为输出
    input wire sda_i,
    output wire sda_o
);
    
    /** 常量 **/
    // 状态常量
    localparam I2C_CTRLER_STS_IDLE = 2'b00; // 状态:空闲
    localparam I2C_CTRLER_STS_LOAD = 2'b01; // 状态:加载数据
    localparam I2C_CTRLER_STS_RX_TX = 2'b10; // 状态:收发
    localparam I2C_CTRLER_STS_DONE = 2'b11; // 状态:完成
    
    /** 流程控制 **/
    reg[1:0] i2c_ctrler_sts; // 控制器状态
    reg[2:0] tx_fifo_ren_onehot; // 发送fifo读使能(独热码)
    reg[2:0] i2c_if_stage_onehot; // i2c主接口控制器阶段(独热码)
    wire i2c_if_ctrler_done; // i2c主接口控制器完成(指示)
    reg is_rd_trans; // 是否读传输
    reg last_loaded; // 载入的last信号
    wire is_addr_stage; // 是否处于地址阶段
    reg[3:0] bytes_n_to_rx; // 待接收字节数
    reg trans_first; // 收发第1个字节(标志)
    reg[3:0] trans_bytes_n; // 已收发的字节数
    reg[3:0] trans_bytes_n_add1; // 已收发的字节数 + 1
    
    assign tx_fifo_ren = tx_fifo_ren_onehot[1];
    
    // 控制器状态
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_ctrler_sts <= I2C_CTRLER_STS_IDLE;
        else
        begin
            # simulation_delay;
            
            case(i2c_ctrler_sts)
                I2C_CTRLER_STS_IDLE: // 状态:空闲
                    if(~tx_fifo_empty)
                        i2c_ctrler_sts <= I2C_CTRLER_STS_LOAD; // -> 状态:加载数据
                I2C_CTRLER_STS_LOAD: // 状态:加载数据
                    if(tx_fifo_ren_onehot[2])
                        i2c_ctrler_sts <= I2C_CTRLER_STS_RX_TX; // -> 状态:收发
                I2C_CTRLER_STS_RX_TX: // 状态:收发
                    if(i2c_if_stage_onehot[2] & i2c_if_ctrler_done)
                        i2c_ctrler_sts <= I2C_CTRLER_STS_DONE; // -> 状态:完成
                I2C_CTRLER_STS_DONE:
                begin
                    if(is_rd_trans)
                    begin
                        if(last_loaded)
                            i2c_ctrler_sts <= (trans_bytes_n == bytes_n_to_rx) ? I2C_CTRLER_STS_IDLE: // -> 状态:空闲
                                                                                 I2C_CTRLER_STS_RX_TX; // -> 状态:收发
                        else
                            i2c_ctrler_sts <= I2C_CTRLER_STS_LOAD; // -> 状态:加载数据
                    end
                    else
                        i2c_ctrler_sts <= last_loaded ? I2C_CTRLER_STS_IDLE: // -> 状态:空闲
                                                        I2C_CTRLER_STS_LOAD; // -> 状态:加载数据
                end
                default:
                    i2c_ctrler_sts <= I2C_CTRLER_STS_IDLE;
            endcase
        end
    end
    
    // 发送fifo读使能(独热码)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            tx_fifo_ren_onehot <= 3'b001;
        else if((tx_fifo_ren_onehot[0] & (i2c_ctrler_sts == I2C_CTRLER_STS_LOAD)) | (tx_fifo_ren_onehot[1] & (~tx_fifo_empty)) | tx_fifo_ren_onehot[2])
            # simulation_delay tx_fifo_ren_onehot <= {tx_fifo_ren_onehot[1:0], tx_fifo_ren_onehot[2]};
    end
    
    // i2c主接口控制器阶段(独热码)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_if_stage_onehot <= 3'b001;
        else if((i2c_if_stage_onehot[0] & (i2c_ctrler_sts == I2C_CTRLER_STS_RX_TX)) | i2c_if_stage_onehot[1] | (i2c_if_stage_onehot[2] & i2c_if_ctrler_done))
            # simulation_delay i2c_if_stage_onehot <= {i2c_if_stage_onehot[1:0], i2c_if_stage_onehot[2]};
    end
    
    // 收发第1个字节(标志)
    always @(posedge clk)
    begin
        if(i2c_ctrler_sts == I2C_CTRLER_STS_IDLE)
            # simulation_delay trans_first <= 1'b1;
        else if(trans_first)
            # simulation_delay trans_first <= ~(i2c_if_stage_onehot[2] & i2c_if_ctrler_done);
    end
    
    // 已收发的字节数
    always @(posedge clk)
    begin
        if(i2c_ctrler_sts == I2C_CTRLER_STS_IDLE)
            # simulation_delay trans_bytes_n <= 4'd0;
        else if(i2c_if_stage_onehot[2] & i2c_if_ctrler_done & (~is_addr_stage))
            # simulation_delay trans_bytes_n <= trans_bytes_n + 4'd1;
    end
    // 已收发的字节数 + 1
    always @(posedge clk)
    begin
        if(i2c_ctrler_sts == I2C_CTRLER_STS_IDLE)
            # simulation_delay trans_bytes_n_add1 <= 4'd1;
        else if(i2c_if_stage_onehot[2] & i2c_if_ctrler_done & (~is_addr_stage))
            # simulation_delay trans_bytes_n_add1 <= trans_bytes_n_add1 + 4'd1;
    end
    
    /** 数据载入 **/
    reg first_load; // 本I2C数据包第1次载入数据(标志)
    reg[7:0] data_loaded; // 载入的数据
    wire resp_dire; // 响应方向(1'b0 -> 主机接收响应, 1'b1 -> 主机发送响应)
    
    assign resp_dire = is_addr_stage ? 1'b0:is_rd_trans;
    
    // 本I2C数据包第1次载入数据(标志)
    always @(posedge clk)
    begin
        if(i2c_ctrler_sts == I2C_CTRLER_STS_IDLE)
            # simulation_delay first_load <= 1'b1;
        else if(first_load)
            # simulation_delay first_load <= ~tx_fifo_ren_onehot[2];
    end
    
    // 载入的数据
    // 载入的last信号
    always @(posedge clk)
    begin
        if(tx_fifo_ren_onehot[2])
            # simulation_delay {last_loaded, data_loaded} <= {tx_fifo_dout_last, tx_fifo_dout};
    end
    
    // 是否读传输
    always @(posedge clk)
    begin
        if(tx_fifo_ren_onehot[2] & first_load)
            # simulation_delay is_rd_trans <= tx_fifo_dout[0];
    end
    
    // 是否处于地址阶段
    generate
        if(addr_bits_n == 7) // 7位地址
        begin
            reg[1:0] is_addr_stage_onehot;
            
            assign is_addr_stage = is_addr_stage_onehot[0];
            
            always @(posedge clk)
            begin
                if(i2c_ctrler_sts == I2C_CTRLER_STS_IDLE)
                    # simulation_delay is_addr_stage_onehot <= 2'b01;
                else if((~is_addr_stage_onehot[1]) & (i2c_if_stage_onehot[2] & i2c_if_ctrler_done))
                    # simulation_delay is_addr_stage_onehot <= {is_addr_stage_onehot[0], is_addr_stage_onehot[1]};
            end
        end
        else // 10位地址
        begin
            reg[2:0] is_addr_stage_onehot;
            
            assign is_addr_stage = ~is_addr_stage_onehot[2];
            
            always @(posedge clk)
            begin
                if(i2c_ctrler_sts == I2C_CTRLER_STS_IDLE)
                    # simulation_delay is_addr_stage_onehot <= 3'b001;
                else if((~is_addr_stage_onehot[2]) & (i2c_if_stage_onehot[2] & i2c_if_ctrler_done))
                    # simulation_delay is_addr_stage_onehot <= {is_addr_stage_onehot[1:0], is_addr_stage_onehot[2]};
            end
        end
    endgenerate
    
    // 待接收字节数
    always @(posedge clk)
    begin
        if(tx_fifo_ren_onehot[2] & tx_fifo_dout_last & is_rd_trans)
            # simulation_delay bytes_n_to_rx <= tx_fifo_dout[3:0];
    end
    
    /** I2C主接口 **/
    wire[7:0] byte_recv; // 接收到数据
    reg i2c_rx_overflow_reg; // I2C接收溢出
    wire i2c_if_ctrler_start; // i2c主接口控制器开始(指示)
    reg[1:0] i2c_if_ctrler_mode; // i2c主接口控制器传输模式(2'b00 -> 带起始位, 2'b01 -> 带结束位, 2'b10 -> 正常, 2'b11 -> 预留)
    wire i2c_if_ctrler_dire; // i2c主接口控制器传输方向(1'b0 -> 发送, 1'b1 -> 接收)
    
    assign rx_fifo_wen = i2c_if_ctrler_done & resp_dire;
    assign rx_fifo_din = byte_recv;
    
    assign i2c_rx_overflow = i2c_rx_overflow_reg;
    
    assign i2c_if_ctrler_start = i2c_if_stage_onehot[1];
    assign i2c_if_ctrler_dire = resp_dire;
    
    // I2C接收溢出
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_rx_overflow_reg <= 1'b0;
        else
            # simulation_delay i2c_rx_overflow_reg <= rx_fifo_wen & rx_fifo_full;
    end
    
    // i2c主接口控制器传输模式
    always @(posedge clk)
    begin
        if(trans_first)
            # simulation_delay i2c_if_ctrler_mode <= 2'b00;
        else if(is_rd_trans ? (last_loaded & (trans_bytes_n_add1 == bytes_n_to_rx)):last_loaded)
            # simulation_delay i2c_if_ctrler_mode <= 2'b01;
        else
            # simulation_delay i2c_if_ctrler_mode <= 2'b10;
    end
    
    // i2c主接口控制器
    i2c_master_if #(
        .simulation_delay(simulation_delay)
    )i2c_master_if_u(
        .clk(clk),
        .resetn(resetn),
        
        .i2c_scl_div_rate(i2c_scl_div_rate),
        
        .ctrler_start(i2c_if_ctrler_start),
        .ctrler_idle(),
        .ctrler_done(i2c_if_ctrler_done),
        
        .mode(i2c_if_ctrler_mode),
        .direction(i2c_if_ctrler_dire),
        .byte_to_send(data_loaded),
        .byte_recv(byte_recv),
        
        .i2c_slave_resp_err(i2c_slave_resp_err),
        
        .scl_t(scl_t),
        .scl_i(scl_i),
        .scl_o(scl_o),
        .sda_t(sda_t),
        .sda_i(sda_i),
        .sda_o(sda_o)
    );
    
    /** I2C收发完成指示 **/
    reg i2c_tx_done_reg; // I2C发送完成指示
    reg i2c_rx_done_reg; // I2C接收完成指示
    
    assign i2c_tx_done = i2c_tx_done_reg;
    assign i2c_tx_bytes_n = trans_bytes_n;
    assign i2c_rx_done = i2c_rx_done_reg;
    assign i2c_rx_bytes_n = trans_bytes_n;
    
    // I2C发送完成指示
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_tx_done_reg <= 1'b0;
        else
            # simulation_delay i2c_tx_done_reg <= (i2c_ctrler_sts == I2C_CTRLER_STS_DONE) & (~is_rd_trans) & last_loaded;
    end
    // I2C接收完成指示
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_rx_done_reg <= 1'b0;
        else
            # simulation_delay i2c_rx_done_reg <= (i2c_ctrler_sts == I2C_CTRLER_STS_DONE) & is_rd_trans & last_loaded & (trans_bytes_n == bytes_n_to_rx);
    end
    
endmodule
