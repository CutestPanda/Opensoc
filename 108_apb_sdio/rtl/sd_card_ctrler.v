`timescale 1ns / 1ps
/********************************************************************
本模块: SD卡控制器

描述:
1.带初始化模块
2.支持一线/四线模式
3.支持命令->
(1)控制/状态命令
命令号  响应类型                      含义
 CMD0     ---                        复位
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
控制器在初始化完成后才能接受用户命令

协议:
AXIS MASTER/SLAVE
SDIO MASTER

作者: 陈家耀
日期: 2024/03/01
********************************************************************/


module sd_card_ctrler #(
    parameter integer init_acmd41_try_n = 20, // 初始化时发送ACMD41命令的尝试次数(必须<=32)
    parameter integer resp_timeout = 64, // 响应超时周期数
    parameter integer resp_with_busy_timeout = 64, // 响应后busy超时周期数
    parameter integer read_timeout = -1, // 读超时周期数(-1表示不设超时)
    parameter en_resp_rd_crc = "false", // 是否使能响应和读数据CRC
    parameter en_sdio_clken = "false", // 是否使用sdio时钟时钟使能
    parameter en_resp = "false", // 是否使能响应AXIS
    parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
    
    // 运行时参数
    input wire en_sdio_clk, // 启用sdio时钟(复位时必须为0), 仅使用sdio时钟时钟使能可用
    input wire[9:0] div_rate, // 分频数 - 1
    input wire en_wide_sdio, // 启用四线模式
    
    // 初始化模块控制
    input wire init_start, // 开始初始化请求(指示)
    output wire init_idle, // 初始化模块空闲(标志)
    output wire init_done, // 初始化完成(指示)
    
    // 命令AXIS
    input wire[39:0] s_axis_cmd_data, // {保留(2bit), 命令号(6bit), 参数(32bit)}
    input wire[15:0] s_axis_cmd_user, // 本次读写的块个数-1
    input wire s_axis_cmd_valid,
    output wire s_axis_cmd_ready,
    
    // 响应AXIS
    // 仅使能响应AXIS时可用
    output wire[119:0] m_axis_resp_data, // 48bit响应 -> {命令号(6bit), 参数(32bit)}, 136bit响应 -> {参数(120bit)}
    output wire[2:0] m_axis_resp_user, // {响应超时(1bit), CRC错误(1bit), 是否长响应(1bit)}
    output wire m_axis_resp_valid,
    input wire m_axis_resp_ready,
    
    // 初始化结果AXIS
    output wire[23:0] m_axis_init_res_data, // {保留(5bit), RCA(16bit), 是否大容量卡(1bit), 是否支持SD2.0(1bit), 是否成功(1bit)}
    output wire m_axis_init_res_valid,
    
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

    /** SD卡初始化模块 **/
    // 初始化模块产生的命令AXIS
    wire[39:0] m_axis_init_cmd_data; // {保留(1bit), 是否忽略读数据(1bit), 命令号(6bit), 参数(32bit)}
    wire m_axis_init_cmd_valid;
    wire m_axis_init_cmd_ready;
    
	sd_card_init #(
		.init_acmd41_try_n(init_acmd41_try_n),
		.simulation_delay(simulation_delay)
	)sd_card_init_u(
		.clk(clk),
		.resetn(resetn),
		
		.en_wide_sdio(en_wide_sdio),
		
		.init_start(init_start),
		.init_idle(init_idle),
		.init_done(init_done),
		
		.m_axis_cmd_data(m_axis_init_cmd_data),
		.m_axis_cmd_valid(m_axis_init_cmd_valid),
		.m_axis_cmd_ready(m_axis_init_cmd_ready),
		
		.s_axis_resp_data(m_axis_resp_data),
		.s_axis_resp_user(m_axis_resp_user),
		.s_axis_resp_valid(m_axis_resp_valid),
		
		.m_axis_init_res_data(m_axis_init_res_data),
		.m_axis_init_res_valid(m_axis_init_res_valid)
	);
    
    /** SDIO控制器 **/
    // 命令AXIS
    wire[39:0] m_axis_cmd_data; // {保留(1bit), 是否忽略读数据(1bit), 命令号(6bit), 参数(32bit)}
    wire[15:0] m_axis_cmd_user; // 本次读写的块个数-1
    wire m_axis_cmd_valid;
    wire m_axis_cmd_ready;
    // sdio时钟使能
    reg[3:0] sdio_rst_onehot;
    wire sdio_clken;
	// 初始化完成标志
	reg init_finished;
    
    assign sdio_clken = sdio_rst_onehot[3];
    
    // sdio时钟使能
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            sdio_rst_onehot <= 4'b0000;
        else if(~sdio_rst_onehot[3]) // 向左移入1'b1
            # simulation_delay sdio_rst_onehot <= {sdio_rst_onehot[2:0], 1'b1};
    end
	
	// 初始化完成标志
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            init_finished <= 1'b0;
        else if(~init_finished)
            # simulation_delay init_finished <= m_axis_init_res_valid;
    end
    
    sdio_ctrler #(
        .resp_timeout(resp_timeout),
        .resp_with_busy_timeout(resp_with_busy_timeout),
        .read_timeout(read_timeout),
        .en_resp_rd_crc(en_resp_rd_crc),
        .simulation_delay(simulation_delay)
    )sdio_ctrler_u(
        .clk(clk),
        .resetn(resetn),
		
        .en_sdio_clk((en_sdio_clken == "true") ? en_sdio_clk:sdio_clken),
        .div_rate(div_rate),
        .en_wide_sdio(en_wide_sdio),
		
        .s_axis_cmd_data(m_axis_cmd_data),
        .s_axis_cmd_user(m_axis_cmd_user),
        .s_axis_cmd_valid(m_axis_cmd_valid),
        .s_axis_cmd_ready(m_axis_cmd_ready),
		
        .m_axis_resp_data(m_axis_resp_data),
        .m_axis_resp_user(m_axis_resp_user),
        .m_axis_resp_valid(m_axis_resp_valid),
        .m_axis_resp_ready((en_resp == "true") ? (init_finished ? m_axis_resp_ready:1'b1):1'b1),
		
        .s_axis_wt_data(s_axis_wt_data),
        .s_axis_wt_valid(s_axis_wt_valid),
        .s_axis_wt_ready(s_axis_wt_ready),
		
        .m_axis_rd_data(m_axis_rd_data),
        .m_axis_rd_last(m_axis_rd_last),
        .m_axis_rd_valid(m_axis_rd_valid),
        .m_axis_rd_ready(m_axis_rd_ready),
		
        .m_axis_rd_sts_data(m_axis_rd_sts_data),
        .m_axis_rd_sts_valid(m_axis_rd_sts_valid),
		
        .m_axis_wt_sts_data(m_axis_wt_sts_data),
        .m_axis_wt_sts_valid(m_axis_wt_sts_valid),
		
        .sdio_ctrler_idle(sdio_ctrler_idle),
        .sdio_ctrler_start(sdio_ctrler_start),
        .sdio_ctrler_done(sdio_ctrler_done),
        .sdio_ctrler_rw_type_done(sdio_ctrler_rw_type_done),
		
        .sdio_clk(sdio_clk),
        .sdio_cmd_t(sdio_cmd_t),
        .sdio_cmd_o(sdio_cmd_o),
        .sdio_cmd_i(sdio_cmd_i),
        .sdio_d0_t(sdio_d0_t),
        .sdio_d0_o(sdio_d0_o),
        .sdio_d0_i(sdio_d0_i),
        .sdio_d1_t(sdio_d1_t),
        .sdio_d1_o(sdio_d1_o),
        .sdio_d1_i(sdio_d1_i),
        .sdio_d2_t(sdio_d2_t),
        .sdio_d2_o(sdio_d2_o),
        .sdio_d2_i(sdio_d2_i),
        .sdio_d3_t(sdio_d3_t),
        .sdio_d3_o(sdio_d3_o),
        .sdio_d3_i(sdio_d3_i)
    );
    
    /** 
	命令AXIS选通
	
	初始化完成 -> 选通给初始化模块, 初始化未完成 -> 选通给用户
	**/
    assign m_axis_init_cmd_ready = (~init_finished) & m_axis_cmd_ready;
    assign s_axis_cmd_ready = init_finished & m_axis_cmd_ready;
    assign m_axis_cmd_data = init_finished ? {2'b00, s_axis_cmd_data[37:0]}:m_axis_init_cmd_data;
    assign m_axis_cmd_user = s_axis_cmd_user;
    assign m_axis_cmd_valid = init_finished ? s_axis_cmd_valid:m_axis_init_cmd_valid;
    
endmodule
