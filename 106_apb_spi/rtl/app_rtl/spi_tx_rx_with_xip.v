`timescale 1ns / 1ps
/********************************************************************
本模块: 支持片上执行的SPI控制器

描述: 
使用发送/接收fifo的SPI控制器(标准SPI支持全双工/半双工/单工, Dual/Quad SPI仅支持半双工)
MSB First
SPI事务数据位宽->8bit

注意：
收发fifo均为标准fifo
若需要使用标准SPI的单工模式, 固定好SPI传输方向即可
请确保 ->
    spi_slave_n == 1
    tx_user_data_width == 0

协议:
FIFO READ/WRITE
SPI MASTER

作者: 陈家耀
日期: 2023/11/17
********************************************************************/


module spi_tx_rx_with_xip #(
    parameter spi_type = "std", // SPI接口类型(标准->std 双口->dual 四口->quad)
    parameter integer spi_sck_div_n = 2, // SPI时钟分频系数(必须能被2整除, 且>=2)
    parameter integer spi_cpol = 0, // SPI空闲时的电平状态(0->低电平 1->高电平)
    parameter integer spi_cpha = 0, // SPI数据采样沿(0->奇数沿 1->偶数沿)
    parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
    input wire spi_clk,
    input wire spi_resetn,
	// AMBA总线时钟和复位
	input wire amba_clk,
	input wire amba_resetn,
	
	// 运行时参数
	input wire[1:0] rx_tx_dire, // 传输方向(2'b11->收发 2'b10->接收 2'b01->发送 2'b00->保留)
    input wire en_xip, // 使能片内执行
    
    // 发送fifo读端口
    output wire tx_fifo_ren,
    input wire tx_fifo_empty,
    input wire[7:0] tx_fifo_dout,
    input wire tx_fifo_dout_ss,
    input wire tx_fifo_dout_ignored,
    input wire tx_fifo_dout_last,
    input wire tx_fifo_dout_dire,
    input wire tx_fifo_dout_en_mul,
    // 接收fifo写端口
    output wire rx_fifo_wen,
    input wire rx_fifo_full,
    output wire[7:0] rx_fifo_din,
    // xip接收数据AXIS主接口
    output wire[7:0] m_rev_axis_data,
    output wire m_rev_axis_valid,
    output wire m_rev_axis_last,
    
    // 控制器收发指示
    output wire rx_tx_start,
    output wire rx_tx_done,
    output wire rx_tx_idle,
    output wire rx_err, // 接收溢出指示
    
    // SPI主机接口
    output wire spi_ss,
    output wire spi_sck,
    // io0
    output wire spi_io0_t,
    output wire spi_io0_o, // denotes mosi if spi_type == "std"
    input wire spi_io0_i,
    // io1
    output wire spi_io1_t,
    output wire spi_io1_o,
    input wire spi_io1_i, // denotes miso if spi_type == "std"
    // io2(only used when spi_type == "quad")
    output wire spi_io2_t,
    output wire spi_io2_o,
    input wire spi_io2_i,
    // io3(only used when spi_type == "quad")
    output wire spi_io3_t,
    output wire spi_io3_o,
    input wire spi_io3_i
);
    
    /** SPI控制器 **/
    wire rx_fifo_wen_w; // 控制器生成的接收fifo写使能
    wire[1:0] rx_tx_dire_w; // 带xip的传输方向
    reg tx_fifo_dout_vld; // 发送fifo数据输出有效
    reg ignored_rx_latched; // 锁存的忽略本次传输的接收数据
    reg last_latched; // 锁存的last信号
    
    assign rx_fifo_wen = rx_fifo_wen_w & (~en_xip);
    
    assign m_rev_axis_data = rx_fifo_din;
    assign m_rev_axis_valid = rx_fifo_wen_w & en_xip & (~ignored_rx_latched);
    assign m_rev_axis_last = last_latched;
    
    assign rx_tx_dire_w = en_xip ? 2'b11:rx_tx_dire; // 使能xip时传输方向固定为收发
    
    // 发送fifo数据输出有效
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
            tx_fifo_dout_vld <= 1'b0;
        else
            # simulation_delay tx_fifo_dout_vld <= tx_fifo_ren & (~tx_fifo_empty);
    end
    
    // 锁存的忽略本次传输的接收数据
    // 锁存的last信号
    always @(posedge spi_clk)
    begin
        if(tx_fifo_dout_vld)
        begin
            # simulation_delay;
            
            ignored_rx_latched <= tx_fifo_dout_ignored;
            last_latched <= tx_fifo_dout_last;
        end
    end
    
    generate
        if(spi_type == "std")
        begin
            // 标准SPI
            assign spi_io0_t = 1'b0;
            assign spi_io1_t = 1'b1;
            assign spi_io1_o = 1'bx;
            
            assign spi_io2_t = 1'b1;
            assign spi_io2_o = 1'bx;
            assign spi_io3_t = 1'b1;
            assign spi_io3_o = 1'bx;
            
            std_spi_tx_rx #(
                .spi_slave_n(1),
                .spi_sck_div_n(spi_sck_div_n),
                .spi_cpol(spi_cpol),
                .spi_cpha(spi_cpha),
                .tx_user_data_width(0),
                .tx_user_default_v(),
                .simulation_delay(simulation_delay)
            )spi_tx_rx_ctrler(
                .spi_clk(spi_clk),
                .spi_resetn(spi_resetn),
				.amba_clk(amba_clk),
				.amba_resetn(amba_resetn),
                .tx_fifo_ren(tx_fifo_ren),
                .tx_fifo_empty(tx_fifo_empty),
                .tx_fifo_dout(tx_fifo_dout),
                .tx_fifo_dout_ss(tx_fifo_dout_ss),
                .tx_fifo_dout_user(),
                .rx_fifo_wen(rx_fifo_wen_w),
                .rx_fifo_full(rx_fifo_full),
                .rx_fifo_din(rx_fifo_din),
                .rx_tx_sel(0),
                .rx_tx_dire(rx_tx_dire_w),
                .rx_tx_start(rx_tx_start),
                .rx_tx_done(rx_tx_done),
                .rx_tx_idle(rx_tx_idle),
                .rx_err(rx_err),
                .spi_ss(spi_ss),
                .spi_sck(spi_sck),
                .spi_mosi(spi_io0_o),
                .spi_miso(spi_io1_i),
                .spi_user()
            );
        end
        else
        begin
            // Dual/Quad SPI
            dual_quad_spi_tx_rx #(
                .spi_type(spi_type),
                .spi_slave_n(1),
                .spi_sck_div_n(spi_sck_div_n),
                .spi_cpol(spi_cpol),
                .spi_cpha(spi_cpha),
                .tx_user_data_width(0),
                .tx_user_default_v(),
                .simulation_delay(simulation_delay)
            )spi_tx_rx_ctrler(
                .spi_clk(spi_clk),
                .spi_resetn(spi_resetn),
				.amba_clk(amba_clk),
				.amba_resetn(amba_resetn),
                .tx_fifo_ren(tx_fifo_ren),
                .tx_fifo_empty(tx_fifo_empty),
                .tx_fifo_dout(tx_fifo_dout),
                .tx_fifo_dout_ss(tx_fifo_dout_ss),
                .tx_fifo_dout_user(),
                .tx_fifo_dout_dire(tx_fifo_dout_dire),
                .tx_fifo_dout_en_mul(tx_fifo_dout_en_mul),
                .rx_fifo_wen(rx_fifo_wen_w),
                .rx_fifo_full(rx_fifo_full),
                .rx_fifo_din(rx_fifo_din),
                .rx_tx_sel(0),
                .rx_tx_start(rx_tx_start),
                .rx_tx_done(rx_tx_done),
                .rx_tx_idle(rx_tx_idle),
                .rx_err(rx_err),
                .spi_ss(spi_ss),
                .spi_sck(spi_sck),
                .spi_io0_t(spi_io0_t),
                .spi_io0_o(spi_io0_o),
                .spi_io0_i(spi_io0_i),
                .spi_io1_t(spi_io1_t),
                .spi_io1_o(spi_io1_o),
                .spi_io1_i(spi_io1_i),
                .spi_io2_t(spi_io2_t),
                .spi_io2_o(spi_io2_o),
                .spi_io2_i(spi_io2_i),
                .spi_io3_t(spi_io3_t),
                .spi_io3_o(spi_io3_o),
                .spi_io3_i(spi_io3_i),
                .spi_user()
            );
        end
    endgenerate

endmodule
