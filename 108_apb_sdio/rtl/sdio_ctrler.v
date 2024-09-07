`timescale 1ns / 1ps
/********************************************************************
本模块: SDIO控制器

描述:
1.支持一线/四线模式
2.支持命令->
(1)控制/状态命令
命令号  响应类型                      含义
 CMD0     无                         复位
 CMD5     R4                     IO接口电压设置
 CMD6     R1                     查询/切换功能
 CMD8     R7             发送SD卡接口环境(提供电压等)
 CMD11    R1                        电压切换
 CMD55    R1             指示下一条命令是特定的应用命令
 ACMD41   R3     发送主机电容供给信息(HCS)并获取操作环境寄存器(OCR)
 CMD2     R2                  获取卡标识号(CID)
 CMD3     R6                 获取卡相对地址(RCA)
 CMD7     R1b                  选中或取消选中卡
 CMD16    R1                       设置块大小
 ACMD6    R1                      设置总线位宽
(2)读写命令
命令号  响应类型           含义
 CMD17    R1             单块读
 CMD18    R1             多块读
 CMD24    R1             单块写
 CMD25    R1             多块写
 CMD12    R1b         停止当前传输

注意：
SD卡块大小为512字节
R2响应有136bit, 其他类型的响应有48bit
CMD6后也会产生读数据中断

协议:
AXIS MASTER/SLAVE
SDIO MASTER

作者: 陈家耀
日期: 2024/07/30
********************************************************************/


module sdio_ctrler #(
    parameter integer resp_timeout = 64, // 响应超时周期数
    parameter integer resp_with_busy_timeout = 64, // 响应后busy超时周期数
    parameter integer read_timeout = -1, // 读超时周期数(-1表示不设超时)
    parameter en_resp_rd_crc = "false", // 使能响应和读数据CRC
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire resetn,
    
    // 运行时参数
    input wire en_sdio_clk, // 启用sdio时钟(复位时必须为0)
    input wire[9:0] div_rate, // 分频数 - 1
    input wire en_wide_sdio, // 启用四线模式
    
    // 命令AXIS
    input wire[39:0] s_axis_cmd_data, // {保留(1bit), 是否忽略读数据(1bit), 命令号(6bit), 参数(32bit)}
    input wire[15:0] s_axis_cmd_user, // 本次读写的块个数-1
    input wire s_axis_cmd_valid,
    output wire s_axis_cmd_ready,
    
    // 响应AXIS
    output wire[119:0] m_axis_resp_data, // 48bit响应 -> {命令号(6bit), 参数(32bit)}, 136bit响应 -> {参数(120bit)}
    output wire[2:0] m_axis_resp_user, // {接收超时(1bit), CRC错误(1bit), 是否长响应(1bit)}
    output wire m_axis_resp_valid,
    input wire m_axis_resp_ready,
    
    // 写数据AXIS
    input wire[31:0] s_axis_wt_data,
    input wire s_axis_wt_valid,
    output wire s_axis_wt_ready,
    
    // 读数据AXIS
    output wire[31:0] m_axis_rd_data,
    output wire m_axis_rd_last, // 当前块的最后1组数据
    output wire m_axis_rd_valid,
    input wire m_axis_rd_ready,
    
    // 读数据返回结果AXIS
    output wire[7:0] m_axis_rd_sts_data, // {保留(3bit), 读超时(1bit), 校验结果(4bit)}
    output wire m_axis_rd_sts_valid,
    
    // 写数据状态返回AXIS
    output wire[7:0] m_axis_wt_sts_data, // {保留(5bit), 状态信息(3bit)}
    output wire m_axis_wt_sts_valid,
    
    // 控制器状态
    output wire sdio_ctrler_idle,
    output wire sdio_ctrler_start,
    output wire sdio_ctrler_done,
    output wire[1:0] sdio_ctrler_rw_type_done, // 2'b00->非读写 2'b01->读 2'b10->写
    
    // sdio接口(三态总线方向选择 -> 0表示输出, 1表示输入)
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

    // 计算log2(bit_depth)
    function integer clogb2 (input integer bit_depth);
        integer temp;
    begin
        temp = bit_depth;
        for(clogb2 = -1;temp > 0;clogb2 = clogb2 + 1)
            temp = temp >> 1;
    end
    endfunction
    
    /** 常量 **/
    // 主控状态机状态常量
    localparam IDLE = 3'b000; // 空闲
    localparam SEND_CMD = 3'b001; // 发送命令
    localparam REV_RESP_RD = 3'b010; // 接收响应和读数据
    localparam WT_DATA = 3'b011; // 写数据
    localparam TRANS_RESP = 3'b100; // 传输响应
    
    // 命令的响应类型
    localparam RESP_TYPE_NO_RESP = 2'b00; // 无响应
    localparam RESP_TYPE_COMMON_RESP = 2'b01; // 普通响应(常规的48bit响应)
    localparam RESP_TYPE_LONG_RESP = 2'b10; // 长响应(136bit响应, 如R2)
    localparam RESP_TYPE_RESP_WITH_BUSY = 2'b11; // 带busy的响应(如R1b)
    // 命令的读写类型
    localparam RW_TYPE_NON = 2'b00; // 非读写
    localparam RW_TYPE_READ = 2'b01; // 读
    localparam RW_TYPE_WRITE = 2'b10; // 写
    
    // 命令位域
    localparam CMD_DATA_REGION = 1'b0; // 命令位现处于数据域
    localparam CMD_CRC_END_REGION = 1'b1; // 命令位现处于校验与结束域
    
    // 响应位域
    localparam RESP_BIT_REGION_NOT_CARE = 2'b00; // 响应位现处于不关心域
    localparam RESP_BIT_REGION_DATA = 2'b01; // 响应位现处于数据域
    localparam RESP_BIT_REGION_CRC = 2'b10; // 响应位现处于CRC域
    localparam RESP_BIT_REGION_END = 2'b11; // 响应位现处于结束域
    // 响应后busy监测状态常量
    localparam RESP_BUSY_DETECT_IDLE = 2'b00; // 监测待开始
    localparam RESP_WAIT_BUSY = 2'b01; // 监测busy信号
    localparam RESP_WAIT_IDLE = 2'b10; // 等待从机idle
    localparam RESP_BUSY_DETECT_FINISH = 2'b11; // 监测完成
    
    // 读数据所处域
    localparam RD_REGION_DATA = 2'b00; // 读数据现处于数据域
    localparam RD_REGION_CRC = 2'b01; // 读数据现处于校验域
    localparam RD_REGION_END = 2'b10; // 读数据现处于结束域
    localparam RD_REGION_FINISH = 2'b11; // 读数据完成
    
    // 写数据阶段
    localparam WT_STAGE_WAIT = 3'b000; // 写等待
    localparam WT_STAGE_PULL_UP = 3'b001; // 主机强驱动到高电平
    localparam WT_STAGE_START = 3'b010; // 起始位
    localparam WT_STAGE_TRANS = 3'b011; // 正在写
    localparam WT_STAGE_CRC_END = 3'b100; // 校验和结束位
    localparam WT_STAGE_STS = 3'b101; // 接收状态信息
    localparam WT_STAGE_WAIT_IDLE = 3'b110; // 等待从机idle
    localparam WT_STAGE_FINISHED = 3'b111; // 完成
    // 写数据接收状态返回的阶段
    localparam WT_STS_WAIT_START = 3'b000; // 等待起始位
    localparam WT_STS_B2 = 3'b001; // 接收第2个状态位
    localparam WT_STS_B1 = 3'b010; // 接收第1个状态位
    localparam WT_STS_B0 = 3'b011; // 接收第0个状态位
    localparam WT_STS_END = 3'b100; // 接收结束位
    
    /** 内部配置 **/
    localparam integer cmd_pre_p_num = 1; // 每个命令前P位(强驱动到高电平)个数
    localparam integer cmd_itv = 8; // 两条命令之间间隔的最小sdio时钟周期数
    localparam integer data_wt_wait_p = 2; // 写等待的sdio时钟周期数(必须>=2)
    
    /** sdio时钟发生器 **/
    wire div_cnt_en; // 分频计数器(使能)
	wire sdio_in_sample; // SDIO输入采样指示
	wire sdio_out_upd; // SDIO输出更新指示
    
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
    
    /** 主控状态机 **/
    // 控制器
    reg[2:0] ctrler_status; // 控制器状态
    wire cmd_done; // 命令完成(脉冲)
    // 取命令
    reg cmd_send_started; // 开始发命令(标志)
    // 命令发送
    reg[1:0] cmd_resp_type; // 命令的响应类型
    reg[1:0] cmd_rw_type; // 命令的读写类型
    reg cmd_bit_finished; // 命令发送完成(标志)
    // 响应接收和读数据
    reg resp_received; // 响应接收完成(标志)
    reg rd_finished; // 读完成(标志)
    reg resp_busy_detect_finished; // 完成响应后busy监测(标志)
    reg resp_timeout_flag; // 响应超时(标志)
    reg rd_timeout_flag; // 读超时(标志)
    // 写数据
    reg wt_finished; // 写完成(标志)
    reg wt_axis_not_valid_but_ready_d; // 延迟1clk的写数据AXIS握手失败
    
    // 命令完成(脉冲)
    assign cmd_done = (m_axis_resp_valid & m_axis_resp_ready) | ((ctrler_status == SEND_CMD) & (cmd_resp_type == RESP_TYPE_NO_RESP) & cmd_bit_finished);
    
    // 控制器生成的sdio时钟使能
    // sdio时钟只能处于高电平时关闭
    assign div_cnt_en = ({m_axis_rd_valid, m_axis_rd_ready} != 2'b10) &  // 读数据AXIS等待
        (~wt_axis_not_valid_but_ready_d); // 写数据AXIS等待
    
    // 控制器状态
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            ctrler_status <= IDLE;
        else
        begin
            # simulation_delay;
            
            case(ctrler_status)
                IDLE: // 状态:空闲
                    if(cmd_send_started)
                        ctrler_status <= SEND_CMD;
                SEND_CMD: // 状态:发送命令
                    if(cmd_bit_finished)
                        ctrler_status <= (cmd_resp_type == RESP_TYPE_NO_RESP) ? IDLE:REV_RESP_RD;
                REV_RESP_RD: // 状态:接收响应和读数据
                begin
                    case(cmd_rw_type)
                        RW_TYPE_NON: // 命令读写类型:非读写
                            if((cmd_resp_type == RESP_TYPE_RESP_WITH_BUSY) ?
                                (resp_timeout_flag | resp_busy_detect_finished): // 带busy的响应, 如R1b
                                (resp_timeout_flag | resp_received)) // 不带busy的响应
                                ctrler_status <= TRANS_RESP;
                        RW_TYPE_READ: // 命令读写类型:读
                            if((read_timeout == -1) ? 
                                (resp_timeout_flag | (resp_received & rd_finished)):
                                (resp_timeout_flag | rd_timeout_flag | (resp_received & rd_finished)))
                                ctrler_status <= TRANS_RESP;
                        RW_TYPE_WRITE: // 命令读写类型:写
                            if(resp_timeout_flag)
                                ctrler_status <= TRANS_RESP;
                            else if(resp_received)
                                ctrler_status <= WT_DATA;
                        default:
                            ctrler_status <= REV_RESP_RD; // hold
                    endcase
                end
                WT_DATA: // 状态:写数据
                    if(wt_finished)
                        ctrler_status <= TRANS_RESP;
                TRANS_RESP: // 状态:传输响应
                    if(m_axis_resp_valid & m_axis_resp_ready)
                         ctrler_status <= IDLE;
                default:
                    ctrler_status <= IDLE;
            endcase
        end
    end
    
    // 延迟1clk的延迟1clk的写数据AXIS握手失败
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            wt_axis_not_valid_but_ready_d <= 1'b0;
        else // 延迟
            # simulation_delay wt_axis_not_valid_but_ready_d <= {s_axis_wt_valid, s_axis_wt_ready} == 2'b01;
    end
    
    /** 控制器状态 **/
    reg cmd_done_d; // 延迟1clk的命令完成(脉冲)
    reg[1:0] cmd_rw_type_done_regs; // 所完成命令的读写类型
    reg sdio_ctrler_idle_reg; // 控制器空闲信号
    reg sdio_ctrler_start_reg; // 控制器开始信号
    
    assign sdio_ctrler_idle = sdio_ctrler_idle_reg;
    assign sdio_ctrler_start = sdio_ctrler_start_reg;
    assign sdio_ctrler_done = cmd_done_d;
    assign sdio_ctrler_rw_type_done = cmd_rw_type_done_regs;
    
    // 延迟1clk的命令完成(脉冲)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            cmd_done_d <= 1'b0;
        else // 延迟
            # simulation_delay cmd_done_d <= cmd_done;
    end
    
    // 所完成命令的读写类型
    always @(posedge clk)
    begin
        if(cmd_done) // 锁存
            # simulation_delay cmd_rw_type_done_regs <= cmd_rw_type;
    end
    
    // 控制器空闲信号
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sdio_ctrler_idle_reg <= 1'b1;
        else
            # simulation_delay sdio_ctrler_idle_reg <= sdio_ctrler_idle_reg ? (~sdio_ctrler_start_reg):cmd_done_d;
    end
    // 控制器开始信号
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sdio_ctrler_start_reg <= 1'b0;
        else
            # simulation_delay sdio_ctrler_start_reg <= (ctrler_status == IDLE) & cmd_send_started;
    end
    
    /** 发送命令控制 **/
    /*
    命令位 47+cmd_pre_p_num:48 47 46 45:40   39:8   7:1  0
    内容             P         S  T  命令号   参数  CRC7 E
    
    P:强驱动到高电平
    S:起始位
    T:方向位
    E:结束位
    */
    // 命令AXIS
    wire s_axis_cmd_data_ignore_rd; // 命令AXIS中data的是否忽略读数据
    wire[5:0] s_axis_cmd_data_cmd; // 命令AXIS中data的命令号
    wire[31:0] s_axis_cmd_data_param; // 命令AXIS中data的参数
    wire[15:0] s_axis_cmd_user_rw_patch_n; // 命令AXIS中user的读写块个数-1
    reg s_axis_cmd_ready_reg; // 命令AXIS的ready信号
    // 命令信息
    reg ignore_rd; // 是否忽略读数据(标志)
    reg is_previous_cmd_id55; // 上一个命令是CMD55
    reg cmd_with_long_resp; // 命令是否带长响应(标志)
    reg cmd_with_r3_resp; // 命令带R3响应(标志)
    reg[15:0] rw_patch_n; // 读写块个数-1
    // 取命令控制
    reg cmd_itv_satisfied; // 命令发送间隔满足要求(标志)
    reg cmd_fetched; // 已取命令(标志)
    // 命令流程控制
    wire cmd_to_send_en_shift; // 当前待发送的命令(移位使能)
    reg sdio_cmd_o_reg; // sdio命令线输出
    reg[(39+cmd_pre_p_num):0] cmd_data; // 命令数据域(移位寄存器)
    reg[7:0] cmd_crc7_end; // 命令校验与结束域(移位寄存器)
    wire cmd_bit_sending; // 当前发送的命令位
    reg[5:0] sending_cmd_bit_i; // 当前发送命令的位编号(计数器)
    reg cmd_actual_sending; // 主机开始正式发送命令(即剔除了一开始的P位)(标志)
    reg cmd_bit_region; // 命令位域(标志)
    
    assign s_axis_cmd_ready = s_axis_cmd_ready_reg;
    assign sdio_cmd_o = sdio_cmd_o_reg;
    
    assign {s_axis_cmd_data_ignore_rd, s_axis_cmd_data_cmd, s_axis_cmd_data_param} = s_axis_cmd_data[38:0];
    assign s_axis_cmd_user_rw_patch_n = s_axis_cmd_user;
    assign cmd_to_send_en_shift = sdio_out_upd;
    assign cmd_bit_sending = (cmd_bit_region == CMD_DATA_REGION) ? cmd_data[39+cmd_pre_p_num]:cmd_crc7_end[7];
    
    // 命令AXIS的ready信号
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            s_axis_cmd_ready_reg <= 1'b1;
        else
            # simulation_delay s_axis_cmd_ready_reg <= s_axis_cmd_ready_reg ? (~s_axis_cmd_valid):
                ((ctrler_status == IDLE) & cmd_itv_satisfied & (~cmd_fetched));
    end
    
    // 是否忽略读数据(标志)
    always @(posedge clk)
    begin
        if(s_axis_cmd_valid & s_axis_cmd_ready) // 锁存
            # simulation_delay ignore_rd <= s_axis_cmd_data_ignore_rd;
    end
    // 上一个命令是CMD55
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            is_previous_cmd_id55 <= 1'b0;
        else if(s_axis_cmd_valid & s_axis_cmd_ready) // 判定并锁存
            # simulation_delay is_previous_cmd_id55 <= s_axis_cmd_data_cmd == 6'd55;
    end
    
    // 命令译码
    // 命令是否带长响应(标志)
    always @(posedge clk)
    begin
        if(s_axis_cmd_valid & s_axis_cmd_ready) // 运算并锁存
            # simulation_delay cmd_with_long_resp <= s_axis_cmd_data_cmd == 6'd2;
    end
    // 命令的响应类型
    always @(posedge clk)
    begin
        if(s_axis_cmd_valid & s_axis_cmd_ready) // 运算并锁存
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
    // 命令的读写类型
    always @(posedge clk)
    begin
        if(s_axis_cmd_valid & s_axis_cmd_ready) // 运算并锁存
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
    // 命令带R3响应(标志)
    always @(posedge clk)
    begin
        if(s_axis_cmd_valid & s_axis_cmd_ready) // 运算并锁存
            # simulation_delay cmd_with_r3_resp <= s_axis_cmd_data_cmd == 6'd41;
    end
    // 读写块个数-1
    always @(posedge clk)
    begin
        if(s_axis_cmd_valid & s_axis_cmd_ready) // 运算并锁存
            # simulation_delay rw_patch_n <= ((s_axis_cmd_data_cmd == 6'd18) | (s_axis_cmd_data_cmd == 6'd25)) ? s_axis_cmd_user_rw_patch_n:16'd0;
    end
    
    // sdio命令线输出
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sdio_cmd_o_reg <= 1'b1;
        else if(cmd_to_send_en_shift) // 更新
            # simulation_delay sdio_cmd_o_reg <= ((ctrler_status == SEND_CMD) & (sending_cmd_bit_i != (48 + cmd_pre_p_num))) ? cmd_bit_sending:1'b1;
    end
    
    // 命令发送完成(标志)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 清零
            # simulation_delay cmd_bit_finished <= 1'b0;
        else if(cmd_to_send_en_shift) // 更新
            # simulation_delay cmd_bit_finished <= (ctrler_status == SEND_CMD) & (sending_cmd_bit_i == (48 + cmd_pre_p_num));
    end
    
    // 命令数据域
    always @(posedge clk)
    begin
        if(s_axis_cmd_valid & s_axis_cmd_ready) // 载入
            # simulation_delay cmd_data <= {
                {cmd_pre_p_num{1'b1}}, // P:强驱动到高电平
                1'b0, // S:起始位
                1'b1, // T:方向位
                s_axis_cmd_data_cmd, // 命令号
                s_axis_cmd_data_param // 参数
            };
        else if((ctrler_status == SEND_CMD) & cmd_to_send_en_shift) // 左移
            # simulation_delay cmd_data <= {cmd_data[(39+cmd_pre_p_num-1):0], 1'bx};
    end
    
    // 命令校验与结束域
    /*
    函数: CRC7每输入一个bit时的更新逻辑
    参数: crc: 旧的CRC7
          inbit: 输入的bit
    返回值: 更新后的 CRC7
    function automatic logic[6:0] CalcCrc7(input[6:0] crc, input inbit);
        logic xorb = crc[6] ^ inbit;
        return (crc << 1) ^ {3'd0, xorb, 2'd0, xorb};
    endfunction
    */
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 复位
            # simulation_delay cmd_crc7_end <= 8'b0000_0001;
        else if(cmd_to_send_en_shift & cmd_actual_sending)
        begin
            if(cmd_bit_region == CMD_DATA_REGION) // 当前发送的命令位处于数据域, 进行CRC计算
                # simulation_delay cmd_crc7_end <= {
                    {cmd_crc7_end[6:1], 1'b0} ^ {3'b000, cmd_crc7_end[7] ^ cmd_bit_sending, 2'b00, cmd_crc7_end[7] ^ cmd_bit_sending}, // CRC7
                    1'b1 // E:结束位
                };
            else // 当前发送的命令位处于校验与结束域, 进行左移
                # simulation_delay cmd_crc7_end <= {cmd_crc7_end[6:0], 1'bx};
        end
    end
    
    // 主机开始正式发送命令(即剔除了一开始的P位)(标志)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 清零
            # simulation_delay cmd_actual_sending <= 1'b0;
        else if((~cmd_actual_sending) & cmd_to_send_en_shift) // 粘滞置位
            # simulation_delay cmd_actual_sending <= sending_cmd_bit_i == (cmd_pre_p_num - 1);
    end
    
    // 当前发送命令的位编号(计数器)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 清零
            # simulation_delay sending_cmd_bit_i <= 6'd0;
        else if(cmd_to_send_en_shift) // 自增
            # simulation_delay sending_cmd_bit_i <= sending_cmd_bit_i + 6'd1;
    end
    
    // 命令位域选择
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 复位
            # simulation_delay cmd_bit_region <= CMD_DATA_REGION;
        else if((cmd_bit_region != CMD_CRC_END_REGION) & cmd_to_send_en_shift) // 粘滞更新
            # simulation_delay cmd_bit_region <= (sending_cmd_bit_i == (39 + cmd_pre_p_num)) ? CMD_CRC_END_REGION:
                CMD_DATA_REGION; // hold
    end
    
    /**
	命令发送间隔控制
	
	保证两条命令之间间隔 >= cmd_itv
	**/
	wire sdio_clk_posedge_arrived; // SDIO时钟上升沿到达(脉冲)
    reg[clogb2(cmd_itv-1):0] cmd_itv_cnt; // 命令发送间隔控制(计数器)
	
	assign sdio_clk_posedge_arrived = sdio_in_sample;
    
    // 命令发送间隔满足要求(标志)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            cmd_itv_satisfied <= 1'b1;
        else if(cmd_done) // 清零
            # simulation_delay cmd_itv_satisfied <= 1'b0;
        else if((~cmd_itv_satisfied) & sdio_clk_posedge_arrived) // 粘滞置位, 捕获cmd_itv个sdio时钟上升沿
            # simulation_delay cmd_itv_satisfied <= cmd_itv_cnt == (cmd_itv - 1);
    end
    // 命令发送间隔控制(计数器)
    always @(posedge clk)
    begin
        if(cmd_done) // 清零
            # simulation_delay cmd_itv_cnt <= 0;
        else if(sdio_clk_posedge_arrived) // 自增
            # simulation_delay cmd_itv_cnt <= cmd_itv_cnt + 1;
    end
    
    // 已取命令(标志)
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
            else // 强制清零
                cmd_fetched <= 1'b0;
        end
    end
    
    // 开始发命令(标志)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            cmd_send_started <= 1'b0;
        else if(cmd_to_send_en_shift) // 更新
            # simulation_delay cmd_send_started <= (ctrler_status == IDLE) ? cmd_fetched:1'b0;
    end
    
    /** 接收响应控制 **/
    reg m_axis_resp_valid_reg; // 响应AXIS的valid信号
    wire resp_rd_sample; // 采样响应和读数据(脉冲)
    reg start_rev_resp; // 开始接收响应(标志)
    reg[7:0] receiving_resp_bit_i; // 当前接收响应的位编号(计数器)
    reg[1:0] resp_bit_region; // 当前接收响应所处的位域(标志)
    reg[119:0] resp_receiving; // 正在接收的响应数据(移位寄存器)
    reg resp_en_cal_crc7; // 响应CRC7计算使能(标志)
    reg[6:0] crc7_receiving; // 正在接收的响应CRC7(移位寄存器)
    reg[6:0] crc7_cal; // 算得的响应CRC7
    reg crc7_err; // CRC7校验错误(标志)
    
    assign m_axis_resp_data = resp_receiving;
    assign m_axis_resp_user = {resp_timeout_flag, (en_resp_rd_crc == "true") ? crc7_err:1'b0, cmd_with_long_resp};
    assign m_axis_resp_valid = m_axis_resp_valid_reg;
    
    assign resp_rd_sample = sdio_in_sample;
    
    // 响应AXIS的valid信号
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            m_axis_resp_valid_reg <= 1'b0;
        else
            # simulation_delay m_axis_resp_valid_reg <= m_axis_resp_valid_reg ? (~m_axis_resp_ready):(ctrler_status == TRANS_RESP);
    end
    
    // 开始接收响应(标志)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 清零
            # simulation_delay start_rev_resp <= 1'b0;
        else if((ctrler_status == REV_RESP_RD) & resp_rd_sample & (~sdio_cmd_i)) // 置位
            # simulation_delay start_rev_resp <= 1'b1;
    end
    
    // 当前接收响应的位编号(计数器)
    // 位编号从方向位开始
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 清零
            # simulation_delay receiving_resp_bit_i <= 8'd0;
        else if(start_rev_resp & resp_rd_sample) // 自增
            # simulation_delay receiving_resp_bit_i <= receiving_resp_bit_i + 8'd1;
    end
    
    // 当前接收响应所处的位域(标志)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 复位
            # simulation_delay resp_bit_region <= RESP_BIT_REGION_NOT_CARE;
        else if(start_rev_resp & resp_rd_sample) // 更新
        begin
            # simulation_delay;
            
            case(resp_bit_region)
                RESP_BIT_REGION_NOT_CARE: // 位域:不关心域
                    if((cmd_resp_type == RESP_TYPE_LONG_RESP) ? (receiving_resp_bit_i == 8'd6):(receiving_resp_bit_i == 8'd0))
                        resp_bit_region <= RESP_BIT_REGION_DATA;
                RESP_BIT_REGION_DATA: // 位域:数据域
                    if((cmd_resp_type == RESP_TYPE_LONG_RESP) ? (receiving_resp_bit_i == 8'd126):(receiving_resp_bit_i == 8'd38))
                        resp_bit_region <= RESP_BIT_REGION_CRC;
                RESP_BIT_REGION_CRC: // 位域:CRC域
                    if((cmd_resp_type == RESP_TYPE_LONG_RESP) ? (receiving_resp_bit_i == 8'd133):(receiving_resp_bit_i == 8'd45))
                        resp_bit_region <= RESP_BIT_REGION_END;
                RESP_BIT_REGION_END: // 位域:结束域
                    resp_bit_region <= RESP_BIT_REGION_END; // hold
                default:
                    resp_bit_region <= RESP_BIT_REGION_NOT_CARE;
            endcase
        end
    end
    
    // 响应CRC7计算使能(标志)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 复位
            # simulation_delay resp_en_cal_crc7 <= 1'b0;
        else if(resp_rd_sample) // 更新
        begin
            if(~start_rev_resp) // 初始化
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
    
    // 移入响应数据和CRC7
    // 正在接收的响应数据(移位寄存器)
    always @(posedge clk)
    begin
        if(start_rev_resp & resp_rd_sample & (resp_bit_region == RESP_BIT_REGION_DATA)) // 向左移入
            # simulation_delay resp_receiving <= {resp_receiving[118:0], sdio_cmd_i};
    end
    // 正在接收的响应CRC7(移位寄存器)
    always @(posedge clk)
    begin
        if(start_rev_resp & resp_rd_sample & (resp_bit_region == RESP_BIT_REGION_CRC)) // 向左移入
            # simulation_delay crc7_receiving <= {crc7_receiving[5:0], sdio_cmd_i};
    end
    
    // 算得的响应CRC7
    /*
    函数: CRC7每输入一个bit时的更新逻辑
    参数: crc: 旧的CRC7
          inbit: 输入的bit
    返回值: 更新后的 CRC7
    function automatic logic[6:0] CalcCrc7(input[6:0] crc, input inbit);
        logic xorb = crc[6] ^ inbit;
		
        return (crc << 1) ^ {3'd0, xorb, 2'd0, xorb};
    endfunction
    */
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 初始化
            // 起始位 -> 7'd0 ^ {3'b000, 1'b0 ^ 1'b0, 2'b00, 1'b0 ^ 1'b0} = 7'd0
            # simulation_delay crc7_cal <= 7'd0;
        else if(start_rev_resp & resp_rd_sample & resp_en_cal_crc7) // 更新CRC7
            # simulation_delay crc7_cal <= {crc7_cal[5:0], 1'b0} ^ {3'b000, crc7_cal[6] ^ sdio_cmd_i, 2'b00, crc7_cal[6] ^ sdio_cmd_i};
    end
    
    // CRC7校验错误(标志)
    always @(posedge clk)
    begin
        if(start_rev_resp & resp_rd_sample & (resp_bit_region == RESP_BIT_REGION_CRC) & 
            ((cmd_resp_type == RESP_TYPE_LONG_RESP) ? (receiving_resp_bit_i == 8'd133):(receiving_resp_bit_i == 8'd45))) // 计算并锁存
            # simulation_delay crc7_err <= {crc7_receiving[5:0], sdio_cmd_i} != (cmd_with_r3_resp ? 7'b111_1111:crc7_cal);
    end
    
    // 响应接收完成(标志)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 清零
            # simulation_delay resp_received <= 1'b0;
        else if(start_rev_resp & resp_rd_sample) // 置位
            # simulation_delay resp_received <= resp_bit_region == RESP_BIT_REGION_END;
    end
    
    /** 响应超时控制 **/
    // 当响应时间 >= resp_timeout时发生超时
    reg[clogb2(resp_timeout-1):0] resp_timeout_cnt; // 响应超时(计数器)
    
    // 响应超时(标志)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 清零
            # simulation_delay resp_timeout_flag <= 1'b0;
        else if((~resp_timeout_flag) & (~start_rev_resp) & (ctrler_status == REV_RESP_RD) & resp_rd_sample & sdio_cmd_i) // 粘滞置位
            # simulation_delay resp_timeout_flag <= resp_timeout_cnt == (resp_timeout - 1);
    end
    // 响应超时(计数器)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 清零
            # simulation_delay resp_timeout_cnt <= 0;
        else if((~start_rev_resp) & (ctrler_status == REV_RESP_RD) & resp_rd_sample & sdio_cmd_i) // 自增
            # simulation_delay resp_timeout_cnt <= resp_timeout_cnt + 1;
    end
    
    /** 响应后busy监测 **/
    // 最多进行resp_with_busy_timeout个周期的busy监测
    reg[clogb2(resp_with_busy_timeout-1):0] resp_busy_timeout_cnt; // 响应后busy监测超时(计数器)
    reg resp_busy_timeout_last; // 响应后busy监测处于最后1个周期(标志)
    reg[1:0] resp_busy_detect_status; // 响应后busy监测状态
    
    // 响应后busy监测超时(计数器)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 复位
            # simulation_delay resp_busy_timeout_cnt <= 0;
        else if((resp_busy_detect_status == RESP_WAIT_BUSY) & resp_rd_sample) // 自增
            # simulation_delay resp_busy_timeout_cnt <= resp_busy_timeout_cnt + 1;
    end
    // 响应后busy监测处于最后1个周期(标志)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 复位
            # simulation_delay resp_busy_timeout_last <= 1'b0;
        else if((resp_busy_detect_status == RESP_WAIT_BUSY) & resp_rd_sample) // 更新
            # simulation_delay resp_busy_timeout_last <= resp_busy_timeout_cnt == (resp_with_busy_timeout - 2);
    end
    
    // 响应后busy监测状态
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 复位
            # simulation_delay resp_busy_detect_status <= RESP_BUSY_DETECT_IDLE;
        else if(start_rev_resp & resp_rd_sample)
        begin
            # simulation_delay;
            
            case(resp_busy_detect_status)
                RESP_BUSY_DETECT_IDLE: // 状态:监测待开始
                    if(resp_received & (cmd_resp_type == RESP_TYPE_RESP_WITH_BUSY))
                        resp_busy_detect_status <= RESP_WAIT_BUSY;
                RESP_WAIT_BUSY: // 状态:监测busy信号
                    if(~sdio_d0_i) // 检测到busy
                        resp_busy_detect_status <= RESP_WAIT_IDLE;
                    else if(resp_busy_timeout_last) // busy监测超时
                        resp_busy_detect_status <= RESP_BUSY_DETECT_FINISH;
                RESP_WAIT_IDLE: // 状态:等待从机idle
                    if(sdio_d0_i)
                        resp_busy_detect_status <= RESP_BUSY_DETECT_FINISH;
                RESP_BUSY_DETECT_FINISH: // 状态:监测完成
                    resp_busy_detect_status <= RESP_BUSY_DETECT_FINISH; // hold
                default:
                    resp_busy_detect_status <= RESP_BUSY_DETECT_IDLE;
            endcase
        end
    end
    
    // 完成响应后busy监测(标志)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 清零
            # simulation_delay resp_busy_detect_finished <= 1'b0;
        else if((~resp_busy_detect_finished) & (start_rev_resp & resp_rd_sample) & sdio_d0_i) // 粘滞置位
            # simulation_delay resp_busy_detect_finished <= ((resp_busy_detect_status == RESP_WAIT_BUSY) & resp_busy_timeout_last) |
                (resp_busy_detect_status == RESP_WAIT_IDLE);
    end
    
    /** 读数据控制 **/
    /*
    实现了单块/多块读
    每块固定为512Byte(128*4Byte)
    */
    reg[31:0] m_axis_rd_data_regs; // 读数据AXIS的data信号
    reg m_axis_rd_valid_reg; // 读数据AXIS的valid信号
    reg m_axis_rd_last_reg; // 读数据AXIS的last信号
    reg start_rd_data; // 开始读数据(标志)
    reg[31:0] rd_data_packet; // 读取的一组数据 -> {byte1, byte2, byte3, byte4}
    reg[4:0] rd_data_cnt_in_packet; // 读取一组数据的进度(计数器)
    reg rd_data_last_in_packet; // 当前读取本组数据的最后1次(标志)
    reg[6:0] rd_data_packet_n; // 已读取的数据组数-1(计数器)
    reg rd_data_last; // 读取最后1次(标志)
    reg[1:0] rd_data_region; // 读数据所处域
    reg[15:0] rd_patch_cnt; // 已读块个数(计数器)
    reg[15:0] rd_crc16_cal[3:0]; // 计算的CRC16
    reg[15:0] rd_crc16_rev[3:0]; // 接收的CRC16
    reg[3:0] rd_crc16_rev_cnt; // 接收CRC16进度(计数器)
    reg rd_crc16_rev_last; // 接收最后1个CRC16位(标志)
    reg[4:0] m_axis_rd_sts_data_regs; // 读数据返回结果AXIS的data
    reg m_axis_rd_sts_valid_reg; // 读数据返回结果AXIS的valid
    
    assign m_axis_rd_data = {m_axis_rd_data_regs[7:0], m_axis_rd_data_regs[15:8], m_axis_rd_data_regs[23:16], m_axis_rd_data_regs[31:24]}; // 按小端字节序重新排列
    assign m_axis_rd_valid = m_axis_rd_valid_reg;
    assign m_axis_rd_last = m_axis_rd_last_reg;
    
    assign m_axis_rd_sts_data = {3'd0, (read_timeout != -1) ? m_axis_rd_sts_data_regs[4]:1'b0, (en_resp_rd_crc == "true") ? m_axis_rd_sts_data_regs[3:0]:4'b0000};
    assign m_axis_rd_sts_valid = m_axis_rd_sts_valid_reg;
    
    // 读数据AXIS的data信号
    always @(posedge clk)
    begin
        if(start_rd_data & resp_rd_sample & rd_data_last_in_packet) // 锁存
            # simulation_delay m_axis_rd_data_regs <= en_wide_sdio ? {rd_data_packet[27:0], sdio_d3_i, sdio_d2_i, sdio_d1_i, sdio_d0_i}:
                {rd_data_packet[30:0], sdio_d0_i};
    end
    // 读数据AXIS的valid信号
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            m_axis_rd_valid_reg <= 1'b0;
        else
            # simulation_delay m_axis_rd_valid_reg <= m_axis_rd_valid_reg ? (~m_axis_rd_ready):
                (start_rd_data & resp_rd_sample & rd_data_last_in_packet & (~ignore_rd));
    end
    // 读数据AXIS的last信号
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            m_axis_rd_last_reg <= 1'b0;
        else if(start_rd_data & resp_rd_sample)
            # simulation_delay m_axis_rd_last_reg <= (rd_data_packet_n == 7'd127) & rd_data_last_in_packet;
    end
    
    // 开始读数据(标志)
    always @(posedge clk)
    begin
        if((ctrler_status != REV_RESP_RD) | (cmd_rw_type != RW_TYPE_READ)) // 清零
            # simulation_delay start_rd_data <= 1'b0;
        else if(resp_rd_sample) // 更新
            # simulation_delay start_rd_data <= start_rd_data ?
                (~((rd_data_region == RD_REGION_END) & (rd_patch_cnt != rw_patch_n))):
                (~sdio_d0_i);
    end
    
    // 读取的一组数据 -> {byte1, byte2, byte3, byte4}
    always @(posedge clk)
    begin
        if(start_rd_data & resp_rd_sample & (rd_data_region == RD_REGION_DATA)) // 向左移入
            # simulation_delay rd_data_packet <= en_wide_sdio ? {rd_data_packet[27:0], sdio_d3_i, sdio_d2_i, sdio_d1_i, sdio_d0_i}:
                {rd_data_packet[30:0], sdio_d0_i};
    end
    
    // 读进度(计数器和标志)
    // 读取一组数据的进度(计数器)
    always @(posedge clk)
    begin
        if((ctrler_status == IDLE) | (rd_data_region == RD_REGION_END)) // 复位
            # simulation_delay rd_data_cnt_in_packet <= 5'd0;
        else if(start_rd_data & resp_rd_sample) // 自增
            # simulation_delay rd_data_cnt_in_packet <= rd_data_last_in_packet ? 5'd0:(rd_data_cnt_in_packet + 5'd1);
    end
    // 当前读取本组数据的最后1次
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 清零
            # simulation_delay rd_data_last_in_packet <= 1'b0;
        else if(start_rd_data & resp_rd_sample) // 更新
            # simulation_delay rd_data_last_in_packet <= (rd_data_region == RD_REGION_DATA) &
                (en_wide_sdio ? (rd_data_cnt_in_packet == 5'd6):(rd_data_cnt_in_packet == 5'd30));
    end
    // 已读取的数据组数-1(计数器)
    always @(posedge clk)
    begin
        if((ctrler_status == IDLE) | (rd_data_region == RD_REGION_END)) // 复位
            # simulation_delay rd_data_packet_n <= 7'd0;
        else if(start_rd_data & resp_rd_sample & rd_data_last_in_packet) // 自增
            # simulation_delay rd_data_packet_n <= rd_data_packet_n + 7'd1;
    end
    // 读取最后1次(标志)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 清零
            # simulation_delay rd_data_last <= 1'b0;
        else if(start_rd_data & resp_rd_sample) // 更新
            # simulation_delay rd_data_last <= (rd_data_region == RD_REGION_DATA) &
                (en_wide_sdio ? (rd_data_cnt_in_packet == 5'd6):(rd_data_cnt_in_packet == 5'd30)) &
                (rd_data_packet_n == 7'd127);
    end
    
    // 读数据所处域
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 复位
            # simulation_delay rd_data_region <= RD_REGION_DATA;
        else if(start_rd_data & resp_rd_sample)
        begin
            # simulation_delay;
            
            case(rd_data_region)
                RD_REGION_DATA: // 位域:读数据现处于数据域
                    if(rd_data_last)
                        rd_data_region <= RD_REGION_CRC;
                RD_REGION_CRC: // 位域:读数据现处于校验域
                    if(rd_crc16_rev_last)
                        rd_data_region <= RD_REGION_END;
                RD_REGION_END: // 位域:读数据现处于结束域
                    rd_data_region <= (rd_patch_cnt == rw_patch_n) ? RD_REGION_FINISH:RD_REGION_DATA;
                RD_REGION_FINISH: // 位域:读数据完成
                    rd_data_region <= RD_REGION_FINISH; // hold
                default:
                    rd_data_region <= RD_REGION_DATA;
            endcase
        end
    end
    
    // 已读块个数(计数器)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 复位
            # simulation_delay rd_patch_cnt <= 16'd0;
        else if(start_rd_data & resp_rd_sample & (rd_data_region == RD_REGION_END)) // 自增
            # simulation_delay rd_patch_cnt <= rd_patch_cnt + 16'd1;
    end
    
    // 读完成(标志)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 复位
            # simulation_delay rd_finished <= 1'b0;
        else if(~rd_finished) // 粘滞置位
            # simulation_delay rd_finished <= rd_data_region == RD_REGION_FINISH;
    end
    
    // 计算的CRC16
    /*
    函数: CRC16每输入一个bit时的更新逻辑
    参数: crc: 旧的CRC16
         inbit: 输入的bit
    返回值: 更新后的CRC16
    function automatic logic[15:0] CalcCrc16(input[15:0] crc, input inbit);
        logic xorb = crc[15] ^ inbit;
        return (crc << 1) ^ {3'd0, xorb, 6'd0, xorb, 4'd0, xorb};
    endfunction
    */
    always @(posedge clk)
    begin
        if((ctrler_status == IDLE) | (rd_data_region == RD_REGION_END)) // 复位
        begin
            # simulation_delay;
            
            rd_crc16_cal[0] <= 16'd0;
            rd_crc16_cal[1] <= 16'd0;
            rd_crc16_cal[2] <= 16'd0;
            rd_crc16_cal[3] <= 16'd0;
        end
        else if(start_rd_data & resp_rd_sample & (rd_data_region == RD_REGION_DATA)) // 更新CRC16
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
    
    // 接收的CRC16
    always @(posedge clk)
    begin
        if(start_rd_data & resp_rd_sample & (rd_data_region == RD_REGION_CRC)) // 向左移入
        begin
            # simulation_delay;
            
            rd_crc16_rev[0] <= {rd_crc16_rev[0][14:0], sdio_d0_i};
            rd_crc16_rev[1] <= {rd_crc16_rev[1][14:0], sdio_d1_i};
            rd_crc16_rev[2] <= {rd_crc16_rev[2][14:0], sdio_d2_i};
            rd_crc16_rev[3] <= {rd_crc16_rev[3][14:0], sdio_d3_i};
        end
    end
    
    // 接收CRC16进度(计数器和标志)
    // 接收CRC16进度(计数器)
    always @(posedge clk)
    begin
        if(rd_data_region == RD_REGION_DATA) // 复位
            # simulation_delay rd_crc16_rev_cnt <= 4'd0;
        else if(start_rd_data & resp_rd_sample & (rd_data_region == RD_REGION_CRC)) // 自增
            # simulation_delay rd_crc16_rev_cnt <= rd_crc16_rev_cnt + 4'd1;
    end
    // 接收最后1个CRC16位(标志)
    always @(posedge clk)
    begin
        if(rd_data_region == RD_REGION_DATA) // 复位
            # simulation_delay rd_crc16_rev_last <= 1'b0;
        else if(start_rd_data & resp_rd_sample) // 更新
            # simulation_delay rd_crc16_rev_last <= (rd_data_region == RD_REGION_CRC) & (rd_crc16_rev_cnt == 4'd14);
    end
    
    // 读数据返回结果AXIS
    // data
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 复位
            # simulation_delay m_axis_rd_sts_data_regs <= 5'b0_0000;
        else if(((rd_data_region == RD_REGION_CRC) & (resp_rd_sample & rd_crc16_rev_last)) |
            ((read_timeout != -1) & rd_timeout_flag))
        begin
            # simulation_delay;
            
            // 读超时
            m_axis_rd_sts_data_regs[4] <= m_axis_rd_sts_data_regs[4] |
                ((read_timeout != -1) & rd_timeout_flag);
            // 校验结果
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
        else // 产生脉冲
            # simulation_delay m_axis_rd_sts_valid_reg <= ((rd_data_region == RD_REGION_CRC) & (resp_rd_sample & rd_crc16_rev_last)) |
                ((read_timeout != -1) & rd_timeout_flag);
    end
    
    /** 读数据超时控制 **/
    reg[clogb2(read_timeout-1):0] rd_timeout_cnt; // 读超时计数器
    
    // 读超时(标志)
    always @(posedge clk)
    begin
        if((ctrler_status == IDLE) | (rd_data_region == RD_REGION_END)) // 复位
            # simulation_delay rd_timeout_flag <= 1'b0;
        else if((ctrler_status == REV_RESP_RD) & (~rd_timeout_flag)) // 粘滞置位
            # simulation_delay rd_timeout_flag <= (cmd_rw_type == RW_TYPE_READ) & resp_rd_sample & (~start_rd_data) & sdio_d0_i & (rd_timeout_cnt == (read_timeout - 1));
    end
    // 读超时计数器
    always @(posedge clk)
    begin
        if((ctrler_status == IDLE) | (rd_data_region == RD_REGION_END)) // 复位
            # simulation_delay rd_timeout_cnt <= 0;
        else if((ctrler_status == REV_RESP_RD) & (cmd_rw_type == RW_TYPE_READ) & resp_rd_sample & (~start_rd_data) & sdio_d0_i) // 自增
            # simulation_delay rd_timeout_cnt <= rd_timeout_cnt + 1;
    end
    
    /** 写数据控制 **/
    /*
    实现了单块/多块写
    每块固定为512Byte(128*4Byte)
    */
    // sdio数据线
    reg[3:0] sdio_d_o_regs; // sdio数据输出
    wire sdio_dout_upd; // sdio数据输出更新使能(脉冲)
    wire sdio_sts_sample; // sdio写数据返回状态采样使能(脉冲)
    // 写数据AXIS
	wire to_get_wt_data; // 获取写数据(标志)
    reg s_axis_wt_ready_reg; // 写数据AXIS的ready信号
    // 写数据状态返回AXIS
    reg m_axis_wt_sts_valid_reg; // 写数据状态返回AXIS的valid信号
    // 写数据阶段
    reg[2:0] wt_stage; // 当前所处的写阶段
    reg[7:0] wt_patch_cnt; // 已读块个数(计数器)
    // 写等待
    reg[clogb2(data_wt_wait_p-1):0] wt_wait_cnt; // 写等待计数器
    reg wt_wait_finished; // 写等待完成(标志)
    // 主机强驱动到高电平, 起始位
    reg wt_data_buf_initialized; // 写数据缓冲区初始化完成标志
    // 正在写
    reg[31:0] wt_data_buf; // 写数据缓冲区(移位寄存器)
    reg[4:0] wt_data_cnt_in_packet; // 写一组数据的进度(计数器)
    reg wt_data_last_in_packet; // 当前写本组数据的最后1次(标志)
    reg[6:0] wt_data_packet_n; // 已写的数据组数-1(计数器)
	reg wt_data_packet_last; // 最后1组写数据(标志)
    reg wt_data_last; // 写最后1次数据(标志)
    // 校验和结束位
    reg[16:0] wt_crc16_end[3:0]; // 写数据的crc16和结束位
    reg[4:0] wt_crc16_end_cnt; // 写crc16和结束位的进度(计数器)
    reg wt_crc16_end_finished; // 写crc16和结束位完成(标志)
    // 接收状态信息
    reg[2:0] wt_sts_stage; // 写数据接收状态返回的阶段
    reg[2:0] wt_sts; // 写数据状态返回
    reg wt_sts_received; // 写数据状态返回接收完成(标志)
    // 等待从机idle
    reg wt_slave_idle; // 从机空闲(标志)
    
    assign s_axis_wt_ready = s_axis_wt_ready_reg;
    assign m_axis_wt_sts_data = {5'd0, wt_sts};
    assign m_axis_wt_sts_valid = m_axis_wt_sts_valid_reg;
    assign {sdio_d3_o, sdio_d2_o, sdio_d1_o, sdio_d0_o} = sdio_d_o_regs;
	
	assign to_get_wt_data = (div_rate == 10'd0) ? 
		(en_wide_sdio ? (wt_data_cnt_in_packet == 5'd6):(wt_data_cnt_in_packet == 5'd30)):
		wt_data_last_in_packet;
    
    assign sdio_dout_upd = sdio_out_upd;
    assign sdio_sts_sample = sdio_in_sample;
    
    // sdio数据输出
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sdio_d_o_regs <= 4'b1111;
        else if(sdio_dout_upd) // 更新
        begin
            # simulation_delay;
            
            case(wt_stage)
                WT_STAGE_WAIT, WT_STAGE_PULL_UP: // 阶段:写等待, 主机强驱动到高电平
					sdio_d_o_regs <= 4'b1111;
				WT_STAGE_START: // 阶段:起始位
                    sdio_d_o_regs <= {en_wide_sdio ? 3'b000:3'b111, 1'b0};
				WT_STAGE_TRANS: // 阶段:正在写
                    sdio_d_o_regs <= en_wide_sdio ? wt_data_buf[31:28]:{3'b111, wt_data_buf[31]};
				WT_STAGE_CRC_END: // 阶段:校验和结束位
                    sdio_d_o_regs <= wt_crc16_end_finished ?
                        4'b1111:(en_wide_sdio ? {wt_crc16_end[3][16], wt_crc16_end[2][16], 
							wt_crc16_end[1][16], wt_crc16_end[0][16]}:
							{3'b111, wt_crc16_end[0][16]});
				WT_STAGE_STS, WT_STAGE_WAIT_IDLE, WT_STAGE_FINISHED: // 阶段:接收状态信息, 等待从机idle, 完成
                    sdio_d_o_regs <= 4'b1111;
                default:
                    sdio_d_o_regs <= 4'b1111;
            endcase
        end
    end
    
    // 写数据AXIS的ready信号
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            s_axis_wt_ready_reg <= 1'b0;
        else
        begin
            # simulation_delay;
            
            case(wt_stage)
                WT_STAGE_WAIT: // 阶段:写等待
                    s_axis_wt_ready_reg <= sdio_dout_upd & wt_wait_finished;
                WT_STAGE_PULL_UP, WT_STAGE_START: // 阶段:主机强驱动到高电平, 起始位
                    s_axis_wt_ready_reg <= (~wt_data_buf_initialized) & (~s_axis_wt_valid);
                WT_STAGE_TRANS: // 阶段:正在写
                    s_axis_wt_ready_reg <= s_axis_wt_ready_reg ? (~s_axis_wt_valid):
						(sdio_dout_upd & to_get_wt_data & (~wt_data_packet_last));
                WT_STAGE_CRC_END, WT_STAGE_STS, WT_STAGE_WAIT_IDLE, WT_STAGE_FINISHED: // 阶段:校验和结束位, 接收状态信息, 等待从机idle, 完成
                    s_axis_wt_ready_reg <= 1'b0;
                default:
                    s_axis_wt_ready_reg <= 1'b0;
            endcase
        end
    end
    
    // 写数据阶段
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 复位
            # simulation_delay wt_stage <= WT_STAGE_WAIT;
        else
        begin
            # simulation_delay;
            
            case(wt_stage)
                WT_STAGE_WAIT: // 阶段:写等待
                    if(sdio_dout_upd & wt_wait_finished)
                        wt_stage <= WT_STAGE_PULL_UP;
                WT_STAGE_PULL_UP: // 阶段:主机强驱动到高电平
                    if(sdio_dout_upd)
                        wt_stage <= WT_STAGE_START;
                WT_STAGE_START: // 阶段:起始位
                    if(sdio_dout_upd & wt_data_buf_initialized)
                        wt_stage <= WT_STAGE_TRANS;
                WT_STAGE_TRANS: // 阶段:正在写
                    if(sdio_dout_upd & wt_data_last)
                        wt_stage <= WT_STAGE_CRC_END;
                WT_STAGE_CRC_END: // 阶段:校验和结束位
                    if(sdio_dout_upd & wt_crc16_end_finished)
                        wt_stage <= WT_STAGE_STS;
                WT_STAGE_STS: // 阶段:接收状态信息
                    if(wt_sts_received)
                        wt_stage <= WT_STAGE_WAIT_IDLE;
                WT_STAGE_WAIT_IDLE: // 阶段:等待从机idle
                    if(wt_slave_idle)
                        wt_stage <= (wt_patch_cnt == rw_patch_n) ? WT_STAGE_FINISHED:WT_STAGE_WAIT;
                WT_STAGE_FINISHED: // 阶段:完成
                    wt_stage <= WT_STAGE_FINISHED; // hold
                default:
                    wt_stage <= WT_STAGE_WAIT;
            endcase
        end
    end
    
    // 已读块个数(计数器)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 复位
            # simulation_delay wt_patch_cnt <= 8'd0;
        else if((wt_stage == WT_STAGE_WAIT_IDLE) & wt_slave_idle) // 自增
            # simulation_delay wt_patch_cnt <= wt_patch_cnt + 8'd1;
    end
    
    // 写完成(标志)
    always @(posedge clk)
    begin
        if(ctrler_status == IDLE) // 清零
            # simulation_delay wt_finished <= 1'b0;
        else if((wt_stage == WT_STAGE_WAIT_IDLE) & wt_slave_idle) // 更新
            # simulation_delay wt_finished <= wt_patch_cnt == rw_patch_n;
    end
    
    // 阶段:写等待
    // 写等待计数器
    always @(posedge clk)
    begin
        if((ctrler_status == IDLE) | (wt_stage == WT_STAGE_WAIT_IDLE)) // 复位
            # simulation_delay wt_wait_cnt <= 0;
        else if((ctrler_status == WT_DATA) & (wt_stage == WT_STAGE_WAIT) & sdio_dout_upd) // 自增
            # simulation_delay wt_wait_cnt <= wt_wait_cnt + 1;
    end
    // 写等待完成(标志)
    always @(posedge clk)
    begin
        if((ctrler_status == IDLE) | (wt_stage == WT_STAGE_WAIT_IDLE)) // 清零
            # simulation_delay wt_wait_finished <= 1'b0;
        else if((ctrler_status == WT_DATA) & (wt_stage == WT_STAGE_WAIT) & sdio_dout_upd) // 更新
            # simulation_delay wt_wait_finished <= wt_wait_cnt == (data_wt_wait_p - 1);
    end
    
    // 阶段:主机强驱动到高电平, 起始位
    // 写数据缓冲区初始化完成标志
    always @(posedge clk)
    begin
        if((wt_stage != WT_STAGE_PULL_UP) & (wt_stage != WT_STAGE_START)) // 清零
            # simulation_delay wt_data_buf_initialized <= 1'b0;
        else if(~wt_data_buf_initialized) // 粘滞更新
            # simulation_delay wt_data_buf_initialized <= s_axis_wt_valid & s_axis_wt_ready;
    end
    
    // 阶段:正在写
    // 写数据缓冲区(移位寄存器)
    always @(posedge clk)
    begin
        if(s_axis_wt_valid & s_axis_wt_ready) // 载入
            # simulation_delay wt_data_buf <= {s_axis_wt_data[7:0], s_axis_wt_data[15:8], s_axis_wt_data[23:16], s_axis_wt_data[31:24]}; // 字节重排序
        else if((wt_stage == WT_STAGE_TRANS) & sdio_dout_upd) // 左移
            # simulation_delay wt_data_buf <= en_wide_sdio ? {wt_data_buf[27:0], 4'dx}:{wt_data_buf[30:0], 1'bx};
    end
    
    // 写进度(计数器和标志)
    // 写一组数据的进度(计数器)
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // 复位
            # simulation_delay wt_data_cnt_in_packet <= 5'd0;
        else if((wt_stage == WT_STAGE_TRANS) & sdio_dout_upd) // 自增
            # simulation_delay wt_data_cnt_in_packet <= wt_data_last_in_packet ? 5'd0:(wt_data_cnt_in_packet + 5'd1);
    end
    // 当前写本组数据的最后1次(标志)
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // 清零
            # simulation_delay wt_data_last_in_packet <= 1'b0;
        else if((wt_stage == WT_STAGE_TRANS) & sdio_dout_upd) // 更新
            # simulation_delay wt_data_last_in_packet <= en_wide_sdio ? (wt_data_cnt_in_packet == 5'd6):(wt_data_cnt_in_packet == 5'd30);
    end
    // 已写的数据组数-1(计数器)
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // 复位
            # simulation_delay wt_data_packet_n <= 7'd0;
        else if((wt_stage == WT_STAGE_TRANS) & sdio_dout_upd & wt_data_last_in_packet) // 自增
            # simulation_delay wt_data_packet_n <= wt_data_packet_n + 7'd1;
    end
	// 最后1组写数据(标志)
	always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // 复位
            # simulation_delay wt_data_packet_last <= 7'd0;
        else if((wt_stage == WT_STAGE_TRANS) & sdio_dout_upd & wt_data_last_in_packet) // 自增
            # simulation_delay wt_data_packet_last <= wt_data_packet_n == 7'd126;
    end
    // 写最后1次数据(标志)
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // 清零
            # simulation_delay wt_data_last <= 1'b0;
        else if((wt_stage == WT_STAGE_TRANS) & sdio_dout_upd) // 更新
            # simulation_delay wt_data_last <= (wt_data_packet_n == 7'd127) &
                (en_wide_sdio ? (wt_data_cnt_in_packet == 5'd6):(wt_data_cnt_in_packet == 5'd30));
    end
    
    // 阶段:校验和结束位
    /*
    函数: CRC16每输入一个bit时的更新逻辑
    参数: crc: 旧的CRC16
         inbit: 输入的bit
    返回值: 更新后的CRC16
    function automatic logic[15:0] CalcCrc16(input[15:0] crc, input inbit);
        logic xorb = crc[15] ^ inbit;
        return (crc << 1) ^ {3'd0, xorb, 6'd0, xorb, 4'd0, xorb};
    endfunction
    */
    // 写数据的crc16和结束位
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // 复位
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
            
            if(wt_stage == WT_STAGE_TRANS) // 处于正在写阶段, 更新CRC16
            begin
                wt_crc16_end[0] <= {
                    {wt_crc16_end[0][15:1], 1'b0} ^ {3'd0, wt_crc16_end[0][16] ^ (en_wide_sdio ? wt_data_buf[28]:wt_data_buf[31]), 
                        6'd0, wt_crc16_end[0][16] ^ (en_wide_sdio ? wt_data_buf[28]:wt_data_buf[31]),
                        4'd0, wt_crc16_end[0][16] ^ (en_wide_sdio ? wt_data_buf[28]:wt_data_buf[31])}, // CRC16
                    1'b1 // E:结束位
                };
                wt_crc16_end[1] <= {
                    {wt_crc16_end[1][15:1], 1'b0} ^ {3'd0, wt_crc16_end[1][16] ^ wt_data_buf[29], 
                        6'd0, wt_crc16_end[1][16] ^ wt_data_buf[29], 4'd0, wt_crc16_end[1][16] ^ wt_data_buf[29]}, // CRC16
                    1'b1 // E:结束位
                };
                wt_crc16_end[2] <= {
                    {wt_crc16_end[2][15:1], 1'b0} ^ {3'd0, wt_crc16_end[2][16] ^ wt_data_buf[30], 
                        6'd0, wt_crc16_end[2][16] ^ wt_data_buf[30], 4'd0, wt_crc16_end[2][16] ^ wt_data_buf[30]}, // CRC16
                    1'b1 // E:结束位
                };
                wt_crc16_end[3] <= {
                    {wt_crc16_end[3][15:1], 1'b0} ^ {3'd0, wt_crc16_end[3][16] ^ wt_data_buf[31], 
                        6'd0, wt_crc16_end[3][16] ^ wt_data_buf[31], 4'd0, wt_crc16_end[3][16] ^ wt_data_buf[31]}, // CRC16
                    1'b1 // E:结束位
                };
            end
            else if(wt_stage == WT_STAGE_CRC_END) // 处于校验和结束位阶段, 进行左移
            begin
                wt_crc16_end[0] <= {wt_crc16_end[0][15:0], 1'bx};
                wt_crc16_end[1] <= {wt_crc16_end[1][15:0], 1'bx};
                wt_crc16_end[2] <= {wt_crc16_end[2][15:0], 1'bx};
                wt_crc16_end[3] <= {wt_crc16_end[3][15:0], 1'bx};
            end
        end
    end
    
    // 写crc16和结束位的进度(计数器和标志)
    // 写crc16和结束位的进度(计数器)
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // 复位
            # simulation_delay wt_crc16_end_cnt <= 5'd0;
        else if((wt_stage == WT_STAGE_CRC_END) & sdio_dout_upd) // 自增
            # simulation_delay wt_crc16_end_cnt <= wt_crc16_end_cnt + 5'd1;
    end
    // 写crc16和结束位完成(标志)
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // 清零
            # simulation_delay wt_crc16_end_finished <= 1'b0;
        else if((wt_stage == WT_STAGE_CRC_END) & sdio_dout_upd) // 更新
            # simulation_delay wt_crc16_end_finished <= wt_crc16_end_cnt == 5'd16;
    end
    
    // 阶段:接收状态信息
    // 写数据接收状态返回的阶段
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // 复位
            # simulation_delay wt_sts_stage <= WT_STS_WAIT_START;
        else if((wt_stage == WT_STAGE_STS) & sdio_sts_sample)
        begin
            # simulation_delay;
            
            case(wt_sts_stage)
                WT_STS_WAIT_START: // 阶段:等待起始位
                    if(~sdio_d0_i)
                        wt_sts_stage <= WT_STS_B2;
                WT_STS_B2: // 阶段:接收第2个状态位
                    wt_sts_stage <= WT_STS_B1;
                WT_STS_B1: // 阶段:接收第1个状态位
                    wt_sts_stage <= WT_STS_B0;
                WT_STS_B0: // 阶段:接收第0个状态位
                    wt_sts_stage <= WT_STS_END;
                WT_STS_END: // 阶段:接收结束位
                    wt_sts_stage <= WT_STS_END; // hold
                default:
                    wt_sts_stage <= WT_STS_WAIT_START;
            endcase
        end
    end
    
    // 写数据状态返回
    always @(posedge clk)
    begin
        if(sdio_sts_sample & ((wt_sts_stage == WT_STS_B2) | (wt_sts_stage == WT_STS_B1) | (wt_sts_stage == WT_STS_B0))) // 向左移入
            # simulation_delay wt_sts <= {wt_sts[1:0], sdio_d0_i};
    end
    
    // 写数据状态返回接收完成(标志)
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // 清零
            # simulation_delay wt_sts_received <= 1'b0;
        else if((~wt_sts_received) & (wt_stage == WT_STAGE_STS)) // 粘滞置位
            # simulation_delay wt_sts_received <= sdio_sts_sample & (wt_sts_stage == WT_STS_END);
    end
    
    // 写数据状态返回AXIS的valid信号
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            m_axis_wt_sts_valid_reg <= 1'b0;
        else // 产生脉冲
            # simulation_delay m_axis_wt_sts_valid_reg <= (wt_stage == WT_STAGE_STS) & sdio_sts_sample & (wt_sts_stage == WT_STS_B0);
    end
    
    // 阶段:等待从机idle
    // 从机空闲(标志)
    always @(posedge clk)
    begin
        if(wt_stage == WT_STAGE_WAIT) // 清零
            # simulation_delay wt_slave_idle <= 1'b0;
        else if((~wt_slave_idle) & (wt_stage == WT_STAGE_WAIT_IDLE)) // 粘滞置位
            # simulation_delay wt_slave_idle <= sdio_sts_sample & sdio_d0_i;
    end
    
    /** sdio总线三态门方向控制 **/
    // 0为输出, 1为输入
    reg sdio_cmd_t_reg; // 命令线方向
    reg[3:0] sdio_d_t_regs; // 数据线方向
    
    assign sdio_cmd_t = sdio_cmd_t_reg;
    assign {sdio_d3_t, sdio_d2_t, sdio_d1_t, sdio_d0_t} = sdio_d_t_regs;
    
    // 命令线方向
    // 1为输入, 0为输出
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sdio_cmd_t_reg <= 1'b1;
        else if(cmd_to_send_en_shift) // 更新
        begin
            # simulation_delay;
            
            case(ctrler_status)
                IDLE: // 状态:空闲
                    sdio_cmd_t_reg <= ~cmd_fetched;
                SEND_CMD: // 状态:发送命令
                    sdio_cmd_t_reg <= sending_cmd_bit_i == (48 + cmd_pre_p_num);
                default:
                    sdio_cmd_t_reg <= 1'b1;
            endcase
        end
    end
    
    // 数据线方向
    // 1为输入, 0为输出
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sdio_d_t_regs <= 4'b1111;
        else if(sdio_dout_upd) // 更新
        begin
            # simulation_delay;
            
            if(ctrler_status == WT_DATA)
            begin
                case(wt_stage)
                    WT_STAGE_WAIT: // 阶段:写等待
                        sdio_d_t_regs <= en_wide_sdio ? {4{~wt_wait_finished}}:{3'b111, ~wt_wait_finished};
                    WT_STAGE_PULL_UP, WT_STAGE_START, WT_STAGE_TRANS: // 阶段:主机强驱动到高电平, 起始位, 正在写
                        sdio_d_t_regs <= en_wide_sdio ? 4'b0000:4'b1110;
                    WT_STAGE_CRC_END: // 阶段:校验和结束位
                        sdio_d_t_regs <= en_wide_sdio ? {4{wt_crc16_end_finished}}:{3'b111, wt_crc16_end_finished};
                    WT_STAGE_STS, WT_STAGE_WAIT_IDLE, WT_STAGE_FINISHED: // 阶段:接收状态信息, 等待从机idle, 完成
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
