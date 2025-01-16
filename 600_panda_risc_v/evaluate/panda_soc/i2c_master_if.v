`timescale 1ns / 1ps
/********************************************************************
本模块: I2C主接口

描述: 
根据传输方向和待发送数据来驱动I2C主接口

注意：
无

协议:
I2C MASTER

作者: 陈家耀
日期: 2024/06/15
********************************************************************/


module i2c_master_if #(
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire resetn,
    
    // I2C时钟分频系数
    // 分频数 = (分频系数 + 1) * 2
    // 断言:分频系数>=1!
    input wire[7:0] i2c_scl_div_rate,
    
    // 流程控制
    input wire ctrler_start,
    output wire ctrler_idle,
    output wire ctrler_done,
    
    // 收发控制
    input wire[1:0] mode, // 传输模式(2'b00 -> 带起始位, 2'b01 -> 带结束位, 2'b10 -> 正常, 2'b11 -> 预留)
    input wire direction, // 传输方向(1'b0 -> 发送, 1'b1 -> 接收)
    input wire[7:0] byte_to_send, // 待发送数据
    output wire[7:0] byte_recv, // 接收到的数据
    
    // I2C从机响应错误
    output wire i2c_slave_resp_err,
    
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
    // 模式常量
    localparam MODE_WITH_START = 2'b00; // 模式:带起始位
    localparam MODE_WITH_STOP = 2'b01; // 模式:带结束位
    localparam MODE_NORMAL = 2'b10; // 模式:正常
    // 控制器状态常量
    localparam CTRLER_STS_IDLE = 3'b000; // 状态:空闲
    localparam CTRLER_STS_START = 3'b001; // 状态:起始位
    localparam CTRLER_STS_DATA = 3'b010; // 状态:数据位
    localparam CTRLER_STS_RESP = 3'b011; // 状态:响应
    localparam CTRLER_STS_STOP = 3'b100; // 状态:停止位
    localparam CTRLER_STS_DONE = 3'b101; // 状态:完成
    
    /** 载入的控制信息 **/
    reg[1:0] mode_latched; // 锁存的传输模式(2'b00 -> 带起始位, 2'b01 -> 带结束位, 2'b10 -> 正常, 2'b11 -> 预留)
    reg direction_latched; // 锁存的传输方向(1'b0 -> 发送, 1'b1 -> 接收)
    
    // 锁存的传输模式
    always @(posedge clk)
    begin
        if(ctrler_idle & ctrler_start)
            # simulation_delay mode_latched <= mode;
    end
    // 锁存的传输方向
    always @(posedge clk)
    begin
        if(ctrler_idle & ctrler_start)
            # simulation_delay direction_latched <= direction;
    end
    
    /** 流程控制 **/
    reg[2:0] i2c_if_ctrler_sts; // 控制器状态
    wire rx_tx_byte_done; // 字节收发完成(指示)
    wire resp_disposed; // 响应处理完成(指示)
    wire stop_disposed; // 停止位处理完成(指示)
    reg ctrler_idle_reg; // 控制器空闲(标志)
    reg ctrler_done_reg; // 控制器完成(指示)
    
    assign ctrler_idle = ctrler_idle_reg;
    assign ctrler_done = ctrler_done_reg;
    
    // 控制器状态
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_if_ctrler_sts <= CTRLER_STS_IDLE;
        else
        begin
            # simulation_delay;
            
            case(i2c_if_ctrler_sts)
                CTRLER_STS_IDLE: // 状态:空闲
                    if(ctrler_start)
                        i2c_if_ctrler_sts <= CTRLER_STS_START; // -> 状态:起始位
                CTRLER_STS_START: // 状态:起始位
                    i2c_if_ctrler_sts <= CTRLER_STS_DATA; // -> 状态:数据位
                CTRLER_STS_DATA: // 状态:数据位
                    if(rx_tx_byte_done)
                        i2c_if_ctrler_sts <= CTRLER_STS_RESP; // -> 状态:响应
                CTRLER_STS_RESP: // 状态:响应
                    if(resp_disposed)
                        i2c_if_ctrler_sts <= CTRLER_STS_STOP; // -> 状态:停止位
                CTRLER_STS_STOP: // 状态:停止位
                    if((mode_latched == MODE_WITH_STOP) ? stop_disposed:1'b1)
                        i2c_if_ctrler_sts <= CTRLER_STS_DONE; // -> 状态:完成
                CTRLER_STS_DONE: // 状态:完成
                    i2c_if_ctrler_sts <= CTRLER_STS_IDLE; // -> 状态:空闲
                default:
                    i2c_if_ctrler_sts <= CTRLER_STS_IDLE;
            endcase
        end
    end
    
    // 控制器空闲(标志)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            ctrler_idle_reg <= 1'b1;
        else
            # simulation_delay ctrler_idle_reg <= ctrler_idle_reg ? (~ctrler_start):ctrler_done_reg;
    end
    // 控制器完成(指示)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            ctrler_done_reg <= 1'b0;
        else
            # simulation_delay ctrler_done_reg <= (i2c_if_ctrler_sts == CTRLER_STS_STOP) & ((mode_latched == MODE_WITH_STOP) ? stop_disposed:1'b1);
    end
    
    /** 数据收发控制 **/
    reg shift_send_bit; // 待发送数据移位标志
    reg sample_recv_bit; // 待接收数据采样标志
    reg[7:0] send_byte_buffer; // 待发送数据缓冲区
    reg[7:0] recv_byte_buffer; // 待接收数据缓冲区
    reg[7:0] rx_tx_stage_onehot; // 收发进程独热码
    
    assign byte_recv = recv_byte_buffer;
    
    assign rx_tx_byte_done = rx_tx_stage_onehot[7] & sample_recv_bit;
    
    // 待发送数据缓冲区
    always @(posedge clk)
    begin
        if(ctrler_idle & ctrler_start)
            # simulation_delay send_byte_buffer <= byte_to_send;
        else if(shift_send_bit)
            # simulation_delay send_byte_buffer <= {send_byte_buffer[6:0], 1'bx};
    end
    // 待接收数据缓冲区
    always @(posedge clk)
    begin
        if(sample_recv_bit)
            # simulation_delay recv_byte_buffer <= {recv_byte_buffer[6:0], sda_i};
    end
    
    // 收发进程独热码
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            rx_tx_stage_onehot <= 8'b0000_0001;
        else if(sample_recv_bit)
            # simulation_delay rx_tx_stage_onehot <= {rx_tx_stage_onehot[6:0], rx_tx_stage_onehot[7]};
    end
    
    /** 响应控制 **/
	reg[7:0] resp_div_cnt; // 响应时scl分频计数器
    reg[5:0] resp_stage_onehot; // 响应进程独热码(6'b000001 -> SCL高, 6'b000010 -> SCL高, 6'b000100 -> SCL低, 6'b001000 -> SCL低且输出响应, 6'b010000 -> SCL高, 6'b100000 -> SCL高)
    reg i2c_slave_resp_err_reg; // I2C从机响应错误
    
    assign i2c_slave_resp_err = i2c_slave_resp_err_reg;
    
    assign resp_disposed = resp_stage_onehot[5];
	
	// 响应时scl分频计数器
	always @(posedge clk)
	begin
		if((i2c_if_ctrler_sts == CTRLER_STS_RESP) & (resp_stage_onehot[0] | resp_stage_onehot[2]))
            # simulation_delay resp_div_cnt <= resp_div_cnt + 8'd1;
		else
			# simulation_delay resp_div_cnt <= 8'd0;
	end
    
    // 响应进程独热码
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            resp_stage_onehot <= 6'b00_00_01;
        else if((i2c_if_ctrler_sts == CTRLER_STS_RESP) & 
			((resp_stage_onehot[0] | resp_stage_onehot[2]) ? (resp_div_cnt == i2c_scl_div_rate):1'b1))
            # simulation_delay resp_stage_onehot <= {resp_stage_onehot[4:0], resp_stage_onehot[5]};
    end
    
    // I2C从机响应错误
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_slave_resp_err_reg <= 1'b0;
        else
            # simulation_delay i2c_slave_resp_err_reg <= (i2c_if_ctrler_sts == CTRLER_STS_RESP) & resp_stage_onehot[4] & sda_i;
    end
    
    /** 停止位控制 **/
	reg[7:0] stop_div_cnt; // 停止位scl分频计数器
    reg[5:0] stop_stage_onehot; // 停止位进程独热码(6'b000001 -> SCL高, 6'b000010 -> SCL高, 6'b000100 -> SCL低, 6'b001000 -> SCL低且SDA低, 6'b010000 -> SCL高, 6'b100000 -> SCL高且SDA高)
    
    assign stop_disposed = stop_stage_onehot[5];
    
	// 停止位scl分频计数器
	always @(posedge clk)
	begin
		if((i2c_if_ctrler_sts == CTRLER_STS_STOP) & (mode_latched == MODE_WITH_STOP) & 
			(stop_stage_onehot[0] | stop_stage_onehot[2]))
            # simulation_delay stop_div_cnt <= stop_div_cnt + 8'd1;
		else
			# simulation_delay stop_div_cnt <= 8'd0;
	end
	
    // 停止位进程独热码
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            stop_stage_onehot <= 6'b00_00_01;
        else if((i2c_if_ctrler_sts == CTRLER_STS_STOP) & (mode_latched == MODE_WITH_STOP) & 
			((stop_stage_onehot[0] | stop_stage_onehot[2]) ? (stop_div_cnt == i2c_scl_div_rate):1'b1))
            # simulation_delay stop_stage_onehot <= {stop_stage_onehot[4:0], stop_stage_onehot[5]};
    end
    
    /** I2C时钟分频 **/
    reg[7:0] i2c_scl_div_cnt; // I2C时钟分频计数器
    wire i2c_scl_div_cnt_rst; // I2C时钟分频计数器回零指示
    
    assign i2c_scl_div_cnt_rst = i2c_scl_div_cnt == i2c_scl_div_rate;
    
    // 待发送数据移位标志
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            shift_send_bit <= 1'b0;
        else
            # simulation_delay shift_send_bit <= scl_o & (i2c_if_ctrler_sts == CTRLER_STS_DATA) & i2c_scl_div_cnt_rst;
    end
    // 待接收数据采样标志
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sample_recv_bit <= 1'b0;
        else
            # simulation_delay sample_recv_bit <= (~scl_o) & (i2c_if_ctrler_sts == CTRLER_STS_DATA) & i2c_scl_div_cnt_rst;
    end
    
    // I2C时钟分频计数器
    always @(posedge clk)
    begin
        if(i2c_if_ctrler_sts == CTRLER_STS_DATA)
            # simulation_delay i2c_scl_div_cnt <= (i2c_scl_div_cnt == i2c_scl_div_rate) ? 8'd0:(i2c_scl_div_cnt + 8'd1);
        else
            # simulation_delay i2c_scl_div_cnt <= 8'd0;
    end
    
    /** I2C主接口 **/
    reg scl_o_reg; // SCL输出
    reg sda_t_reg; // SDA方向
    reg sda_o_reg; // SDA输出
    
    assign scl_t = 1'b0;
    assign scl_o = scl_o_reg;
    assign sda_t = sda_t_reg;
    assign sda_o = sda_o_reg;
    
    // SCL输出
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            scl_o_reg <= 1'b1;
        else if(((i2c_if_ctrler_sts == CTRLER_STS_DATA) & i2c_scl_div_cnt_rst) |
            ((i2c_if_ctrler_sts == CTRLER_STS_RESP) & (resp_stage_onehot[1] | resp_stage_onehot[3])) |
            ((i2c_if_ctrler_sts == CTRLER_STS_STOP) & (mode_latched == MODE_WITH_STOP) & (stop_stage_onehot[1] | stop_stage_onehot[3])))
        begin
            # simulation_delay scl_o_reg <= ~scl_o_reg;
        end
    end
    
    // SDA方向(1'b1为输入, 1'b0为输出)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sda_t_reg <= 1'b1;
        else if(((i2c_if_ctrler_sts == CTRLER_STS_START) & (mode_latched == MODE_WITH_START)) | 
            ((i2c_if_ctrler_sts == CTRLER_STS_DATA) & shift_send_bit) |
            ((i2c_if_ctrler_sts == CTRLER_STS_RESP) & resp_stage_onehot[2]) |
            ((i2c_if_ctrler_sts == CTRLER_STS_STOP) & stop_stage_onehot[2]))
        begin
            # simulation_delay sda_t_reg <= 
                (i2c_if_ctrler_sts == CTRLER_STS_START) ? 1'b0:
                (i2c_if_ctrler_sts == CTRLER_STS_DATA) ? direction_latched:
                (i2c_if_ctrler_sts == CTRLER_STS_RESP) ? (~direction_latched):
                    1'b0;
        end
    end
    // SDA输出
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sda_o_reg <= 1'b1;
        else if(((i2c_if_ctrler_sts == CTRLER_STS_START) & (mode_latched == MODE_WITH_START)) | 
            ((i2c_if_ctrler_sts == CTRLER_STS_DATA) & (~direction_latched) & shift_send_bit) |
            ((i2c_if_ctrler_sts == CTRLER_STS_RESP) & resp_stage_onehot[2] & direction_latched) |
            ((i2c_if_ctrler_sts == CTRLER_STS_STOP) & (stop_stage_onehot[2] | stop_stage_onehot[4])))
        begin
            # simulation_delay sda_o_reg <= 
                (i2c_if_ctrler_sts == CTRLER_STS_START) ? 1'b0:
                (i2c_if_ctrler_sts == CTRLER_STS_DATA) ? send_byte_buffer[7]:
                (i2c_if_ctrler_sts == CTRLER_STS_RESP) ? (mode_latched == MODE_WITH_STOP):
                    stop_stage_onehot[4];
        end
    end
    
endmodule
