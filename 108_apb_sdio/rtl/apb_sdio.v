/*
MIT License

Copyright (c) 2024 Panda, 2257691535@qq.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

`timescale 1ns / 1ps
/********************************************************************
本模块: APB-SDIO

描述:
1.可选的硬件初始化模块
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
命令号  响应类型        含义
 CMD17    R1             单块读
 CMD18    R1             多块读
 CMD24    R1             单块写
 CMD25    R1             多块写
 CMD12    R1b         停止当前传输
4.寄存器->
    偏移量  |    含义                     |   读写特性    |                备注
    0x00    0:命令fifo是否满                    R
            1:读数据fifo是否空                  R
            2:写数据fifo是否满                  R
    0x04    5~0:命令号                         W             写该寄存器时会产生命令fifo写使能
            15~8:本次读写的块个数-1            W              写该寄存器时会产生命令fifo写使能
    0x08    31~0:命令参数                      W
    0x0C    31~0:读数据                        R             读该寄存器时会产生读数据fifo读使能
    0x10    31~0:写数据                        W             写该寄存器时会产生写数据fifo写使能
    0x14    0:SDIO全局中断使能                  W
            8:SDIO读数据中断使能                W
            9:SDIO写数据中断使能                W
            10:SDIO常规命令处理完成中断使能     W
    0x18    0:SDIO全局中断标志                 RWC              请在中断服务函数中清除中断标志
            8:SDIO读数据中断标志                R
            9:SDIO写数据中断标志                R
            10:SDIO常规命令处理完成中断标志     R
    0x1C    31~0:响应[119:88]                  R
    0x20    31~0:响应[87:56]                   R
    0x24    31~0:响应[55:24]                   R
    0x28    23~0:响应[23:0]                    R
            24:是否长响应                      R
            25:CRC错误                         R
            26:接收超时                        R
    0x2C    0:控制器是否空闲                   R
            5~1:读数据返回结果                 R
            10~8:写数据返回状态信息            R
            16:是否启用sdio时钟               W
            17:是否启用四线模式               W
            27~18:sdio时钟分频系数            W                  分频数 = (分频系数 + 1) * 2
   [0x30,   0:开始初始化标志                  W               写该寄存器并且该位为1时开始初始化
    仅使能   1:初始化模块是否空闲              R
    硬件     23~8:RCA                         R                    初始化结果[18:3]
    初始化   24:初始化是否成功                 R                    初始化结果[0]
    时可用]  25:是否支持SD2.0                  R                    初始化结果[1]
            26:是否大容量卡                   R                     初始化结果[2]

注意：
SD卡块大小为512字节
R2响应有136bit, 其他类型的响应有48bit
CMD6后也会产生读数据中断

协议:
APB SLAVE
SDIO MASTER

作者: 陈家耀
日期: 2024/01/24
********************************************************************/


module apb_sdio #(
    parameter en_hw_init = "false", // 使能硬件初始化
    parameter integer init_acmd41_try_n = 20, // 初始化时发送ACMD41命令的尝试次数(必须<=32, 仅使能硬件初始化时有效)
    parameter integer resp_timeout = 64, // 响应超时周期数
    parameter integer resp_with_busy_timeout = 64, // 响应后busy超时周期数
    parameter integer read_timeout = -1, // 读超时周期数
    parameter en_resp_rd_crc = "false", // 使能响应和读数据CRC
	parameter en_sdio_clken = "true", // 是否使用sdio时钟时钟使能
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire resetn,
    
    // APB从机接口
    input wire[31:0] paddr,
    input wire psel,
    input wire penable,
    input wire pwrite,
    input wire[31:0] pwdata,
    output wire pready_out, // const -> 1'b1
    output wire[31:0] prdata_out,
    output wire pslverr_out, // const -> 1'b0
    
    // sdio接口(三态总线方向选择 -> 0表示输出, 1表示输入)
    // clk
    output wire sdio_clk,
    // cmd
    output wire sdio_cmd_t,
    output wire sdio_cmd_o,
    input wire sdio_cmd_i,
    // data
    output wire[3:0] sdio_data_t,
    output wire[3:0] sdio_data_o,
    input wire[3:0] sdio_data_i,
    
    // 中断
    output wire itr
);
    
    /** 命令fifo(深度为1即可) **/
    // 写端口
    wire cmd_fifo_wen;
    reg cmd_fifo_full;
    wire[45:0] cmd_fifo_din;
    // 读端口
    wire cmd_fifo_ren;
    reg cmd_fifo_empty_n;
    reg[45:0] cmd_fifo_dout;
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            cmd_fifo_full <= 1'b0;
        else
            # simulation_delay cmd_fifo_full <= cmd_fifo_full ? (~cmd_fifo_ren):cmd_fifo_wen;
    end
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            cmd_fifo_empty_n <= 1'b0;
        else
            # simulation_delay cmd_fifo_empty_n <= cmd_fifo_empty_n ? (~cmd_fifo_ren):cmd_fifo_wen;
    end
    
    always @(posedge clk)
    begin
        if((~cmd_fifo_full) & cmd_fifo_wen)
            # simulation_delay cmd_fifo_dout <= cmd_fifo_din;
    end
    
    /** 读数据fifo **/
    // 写端口
    wire rdata_fifo_wen;
    wire rdata_fifo_full_n;
    wire[31:0] rdata_fifo_din;
    // 读端口
    wire rdata_fifo_ren;
    wire rdata_fifo_empty;
    wire[31:0] rdata_fifo_dout;
    
    ram_fifo_wrapper #(
        .fwft_mode("true"),
		.use_fifo9k("true"),
        .ram_type("bram_9k"),
        .en_bram_reg("false"),
        .fifo_depth(2048),
        .fifo_data_width(32),
        .full_assert_polarity("low"),
        .empty_assert_polarity("high"),
        .almost_full_assert_polarity("no"),
        .almost_empty_assert_polarity("no"),
        .en_data_cnt("false"),
        .almost_full_th(),
        .almost_empty_th(),
        .simulation_delay(simulation_delay)
    )rdata_fifo(
        .clk(clk),
        .rst_n(resetn),
        .fifo_wen(rdata_fifo_wen),
        .fifo_din(rdata_fifo_din),
        .fifo_full_n(rdata_fifo_full_n),
        .fifo_ren(rdata_fifo_ren),
        .fifo_dout(rdata_fifo_dout),
        .fifo_empty(rdata_fifo_empty)
    );
    
    /** 写数据fifo **/
    // 写端口
    wire wdata_fifo_wen;
    wire wdata_fifo_full;
    wire[31:0] wdata_fifo_din;
    // 读端口
    wire wdata_fifo_ren;
    wire wdata_fifo_empty_n;
    wire[31:0] wdata_fifo_dout;
    
    ram_fifo_wrapper #(
        .fwft_mode("true"),
        .use_fifo9k("true"),
        .ram_type("bram_9k"),
        .en_bram_reg("false"),
        .fifo_depth(2048),
        .fifo_data_width(32),
        .full_assert_polarity("high"),
        .empty_assert_polarity("low"),
        .almost_full_assert_polarity("no"),
        .almost_empty_assert_polarity("no"),
        .en_data_cnt("false"),
        .almost_full_th(),
        .almost_empty_th(),
        .simulation_delay(simulation_delay)
    )wdata_fifo(
        .clk(clk),
        .rst_n(resetn),
        .fifo_wen(wdata_fifo_wen),
        .fifo_din(wdata_fifo_din),
        .fifo_full(wdata_fifo_full),
        .fifo_ren(wdata_fifo_ren),
        .fifo_dout(wdata_fifo_dout),
        .fifo_empty_n(wdata_fifo_empty_n)
    );

    /** 控制/状态寄存器接口 **/
    // 控制器状态
    wire sdio_ctrler_idle;
    // 控制器运行时参数
    wire en_sdio_clk; // 启用sdio时钟(复位时必须为0)
    wire[9:0] div_rate; // 分频系数(分频数 = (分频系数 + 1) * 2)
    wire en_wide_sdio; // 启用四线模式
    // 初始化模块控制
    wire init_start; // 开始初始化请求(指示)
    wire init_idle; // 初始化模块空闲(标志)
    // 响应AXIS
    wire[119:0] s_axis_resp_data; // 48bit响应 -> {命令号(6bit), 参数(32bit)}, 136bit响应 -> {参数(120bit)}
    wire[2:0] s_axis_resp_user; // {接收超时(1bit), CRC错误(1bit), 是否长响应(1bit)}
    wire s_axis_resp_valid;
    // 初始化结果AXIS
    wire[23:0] m_axis_init_res_data; // {保留(5bit), RCA(16bit), 是否大容量卡(1bit), 是否支持SD2.0(1bit), 是否成功(1bit)}
    wire m_axis_init_res_valid;
    // 读数据返回结果AXIS
    wire[7:0] s_axis_rd_sts_data; // {保留(3bit), 读超时(1bit), 校验结果(4bit)}
    wire s_axis_rd_sts_valid;
    // 写数据状态返回AXIS
    wire[7:0] s_axis_wt_sts_data; // {保留(5bit), 状态信息(3bit)}
    wire s_axis_wt_sts_valid;
    // 中断控制
    wire rdata_itr_org_pulse; // 读数据原始中断脉冲
    wire wdata_itr_org_pulse; // 写数据原始中断脉冲
    wire common_itr_org_pulse; // 常规命令处理完成中断脉冲
    wire rdata_itr_en; // 读数据中断使能
    wire wdata_itr_en; // 写数据中断使能
    wire common_itr_en; // 常规命令处理完成中断使能
    wire global_org_itr_pulse; // 全局原始中断脉冲
    
    sdio_regs_interface #(
        .simulation_delay(simulation_delay)
    )sdio_regs_interface_u(
        .clk(clk),
        .resetn(resetn),
        .paddr(paddr),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .pready_out(pready_out),
        .prdata_out(prdata_out),
        .pslverr_out(pslverr_out),
        .cmd_fifo_wen(cmd_fifo_wen),
        .cmd_fifo_full(cmd_fifo_full),
        .cmd_fifo_din(cmd_fifo_din),
        .rdata_fifo_ren(rdata_fifo_ren),
        .rdata_fifo_empty(rdata_fifo_empty),
        .rdata_fifo_dout(rdata_fifo_dout),
        .wdata_fifo_wen(wdata_fifo_wen),
        .wdata_fifo_full(wdata_fifo_full),
        .wdata_fifo_din(wdata_fifo_din),
        .sdio_ctrler_idle(sdio_ctrler_idle),
        .en_sdio_clk(en_sdio_clk),
        .div_rate(div_rate),
        .en_wide_sdio(en_wide_sdio),
        .init_start(init_start),
        .init_idle(init_idle),
        .s_axis_resp_data(s_axis_resp_data),
        .s_axis_resp_user(s_axis_resp_user),
        .s_axis_resp_valid(s_axis_resp_valid),
        .s_axis_init_res_data(m_axis_init_res_data),
        .s_axis_init_res_valid(m_axis_init_res_valid),
        .s_axis_rd_sts_data(s_axis_rd_sts_data),
        .s_axis_rd_sts_valid(s_axis_rd_sts_valid),
        .s_axis_wt_sts_data(s_axis_wt_sts_data),
        .s_axis_wt_sts_valid(s_axis_wt_sts_valid),
        .rdata_itr_org_pulse(rdata_itr_org_pulse),
        .wdata_itr_org_pulse(wdata_itr_org_pulse),
        .common_itr_org_pulse(common_itr_org_pulse),
        .rdata_itr_en(rdata_itr_en),
        .wdata_itr_en(wdata_itr_en),
        .common_itr_en(common_itr_en),
        .global_org_itr_pulse(global_org_itr_pulse)
    );
    
    /** 中断发生器 **/
    // 控制器状态
    wire sdio_ctrler_done;
    wire[1:0] sdio_ctrler_rw_type_done;
    
    sdio_itr_generator #(
        .simulation_delay(simulation_delay)
    )sdio_itr_generator_u(
        .clk(clk),
        .resetn(resetn),
        .sdio_ctrler_done(sdio_ctrler_done),
        .sdio_ctrler_rw_type_done(sdio_ctrler_rw_type_done),
        .rdata_itr_org_pulse(rdata_itr_org_pulse),
        .wdata_itr_org_pulse(wdata_itr_org_pulse),
        .common_itr_org_pulse(common_itr_org_pulse),
        .rdata_itr_en(rdata_itr_en),
        .wdata_itr_en(wdata_itr_en),
        .common_itr_en(common_itr_en),
        .global_org_itr_pulse(global_org_itr_pulse),
        .itr(itr)
    );
    
    /** SDIO或SD卡控制器 **/
    wire sdio_d0_t;
    wire sdio_d0_o;
    wire sdio_d0_i;
    wire sdio_d1_t;
    wire sdio_d1_o;
    wire sdio_d1_i;
    wire sdio_d2_t;
    wire sdio_d2_o;
    wire sdio_d2_i;
    wire sdio_d3_t;
    wire sdio_d3_o;
    wire sdio_d3_i;
    
    assign sdio_data_t = {sdio_d3_t, sdio_d2_t, sdio_d1_t, sdio_d0_t};
    assign sdio_data_o = {sdio_d3_o, sdio_d2_o, sdio_d1_o, sdio_d0_o};
    assign {sdio_d3_i, sdio_d2_i, sdio_d1_i, sdio_d0_i} = sdio_data_i;
	
    generate
        if(en_hw_init == "true")
            sd_card_ctrler #(
                .init_acmd41_try_n(init_acmd41_try_n),
                .resp_timeout(resp_timeout),
                .resp_with_busy_timeout(resp_with_busy_timeout),
                .read_timeout(read_timeout),
                .en_resp_rd_crc(en_resp_rd_crc),
				.en_sdio_clken(en_sdio_clken),
				.en_resp("false"),
                .simulation_delay(simulation_delay)
            )sd_card_ctrler_u(
                .clk(clk),
                .resetn(resetn),
                .en_sdio_clk(en_sdio_clk),
                .div_rate(div_rate),
                .en_wide_sdio(en_wide_sdio),
                .init_start(init_start),
                .init_idle(init_idle),
                .init_done(), // not care
                .s_axis_cmd_data({2'b00, cmd_fifo_dout[37:0]}),
                .s_axis_cmd_user({8'd0, cmd_fifo_dout[45:38]}),
                .s_axis_cmd_valid(cmd_fifo_empty_n),
                .s_axis_cmd_ready(cmd_fifo_ren),
                .m_axis_resp_data(s_axis_resp_data),
                .m_axis_resp_user(s_axis_resp_user),
                .m_axis_resp_valid(s_axis_resp_valid),
                .m_axis_resp_ready(1'b1),
                .m_axis_init_res_data(m_axis_init_res_data),
                .m_axis_init_res_valid(m_axis_init_res_valid),
                .s_axis_wt_data(wdata_fifo_dout),
                .s_axis_wt_valid(wdata_fifo_empty_n),
                .s_axis_wt_ready(wdata_fifo_ren),
                .m_axis_rd_data(rdata_fifo_din),
                .m_axis_rd_last(), // not care
                .m_axis_rd_valid(rdata_fifo_wen),
                .m_axis_rd_ready(rdata_fifo_full_n),
                .m_axis_rd_sts_data(s_axis_rd_sts_data),
                .m_axis_rd_sts_valid(s_axis_rd_sts_valid),
                .m_axis_wt_sts_data(s_axis_wt_sts_data),
                .m_axis_wt_sts_valid(s_axis_wt_sts_valid),
                .sdio_ctrler_idle(sdio_ctrler_idle),
                .sdio_ctrler_start(), // not care
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
        else
            sdio_ctrler #(
                .resp_timeout(resp_timeout),
                .resp_with_busy_timeout(resp_with_busy_timeout),
                .read_timeout(read_timeout),
                .en_resp_rd_crc(en_resp_rd_crc),
                .simulation_delay(simulation_delay)
            )sdio_ctrler_u(
                .clk(clk),
                .resetn(resetn),
                .en_sdio_clk(en_sdio_clk),
                .div_rate(div_rate),
                .en_wide_sdio(en_wide_sdio),
                .s_axis_cmd_data({2'b00, cmd_fifo_dout[37:0]}),
                .s_axis_cmd_user({8'd0, cmd_fifo_dout[45:38]}),
                .s_axis_cmd_valid(cmd_fifo_empty_n),
                .s_axis_cmd_ready(cmd_fifo_ren),
                .m_axis_resp_data(s_axis_resp_data),
                .m_axis_resp_user(s_axis_resp_user),
                .m_axis_resp_valid(s_axis_resp_valid),
                .m_axis_resp_ready(1'b1),
                .s_axis_wt_data(wdata_fifo_dout),
                .s_axis_wt_valid(wdata_fifo_empty_n),
                .s_axis_wt_ready(wdata_fifo_ren),
                .m_axis_rd_data(rdata_fifo_din),
                .m_axis_rd_last(), // not care
                .m_axis_rd_valid(rdata_fifo_wen),
                .m_axis_rd_ready(rdata_fifo_full_n),
                .m_axis_rd_sts_data(s_axis_rd_sts_data),
                .m_axis_rd_sts_valid(s_axis_rd_sts_valid),
                .m_axis_wt_sts_data(s_axis_wt_sts_data),
                .m_axis_wt_sts_valid(s_axis_wt_sts_valid),
                .sdio_ctrler_idle(sdio_ctrler_idle),
                .sdio_ctrler_start(), // not care
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
    endgenerate
	
endmodule
