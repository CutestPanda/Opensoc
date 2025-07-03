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
本模块: 符合APB协议的I2C控制器

描述: 
APB-I2C控制器
支持I2C收发中断
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

寄存器->
    偏移量  |    含义                     |   读写特性    |                 备注
    0x00    0:发送fifo是否满                    R
            1:发送fifo写使能                    W         写该寄存器且该位为1'b1时产生发送fifo写使能
            10~2:发送fifo写数据                 W                 {last(1bit), data(8bit)}
            16:接收fifo是否空                   R
            17:接收fifo读使能                   W         写该寄存器且该位为1'b1时产生接收fifo读使能
            25~18:接收fifo读数据                R
    0x04    0:I2C全局中断使能                   W
            8:I2C发送指定字节数中断使能         W
            9:I2C从机响应错误中断使能           W
            10:I2C接收指定字节数中断使能        W
            11:I2C接收溢出中断使能              W
    0x08    7~0:I2C发送中断字节数阈值           W                  发送字节数 > 阈值时发生中断
            15~8:I2C接收中断字节数阈值          W                  接收字节数 > 阈值时发生中断
			23~16:I2C时钟分频系数               W                  分频数 = (分频系数 + 1) * 2
			                                                              分频系数应>=1
    0x0C    0:I2C全局中断标志                  RWC                 请在中断服务函数中清除中断标志
            1:I2C发送指定字节数中断标志         R
            2:I2C从机响应错误中断标志           R
            3:I2C接收指定字节数中断标志         R
            4:I2C接收溢出中断标志               R
            19~8:I2C发送字节数                RWC                  每当发送一个I2C数据包后更新
            31~20:I2C接收字节数               RWC                  每当接收一个I2C数据包后更新

注意：
I2C发送/接收指定字节数中断每当发送/接收一个I2C数据包后判断
每个I2C数据包不能超过15字节

协议:
APB SLAVE
I2C MASTER

作者: 陈家耀
日期: 2024/06/14
********************************************************************/


module apb_i2c #(
    parameter integer addr_bits_n = 7, // 地址位数(7|10)
	parameter en_i2c_rx = "true", // 是否使能i2c接收
    parameter tx_rx_fifo_ram_type = "bram", // 发送接收fifo的RAM类型(lutram|bram)
    parameter integer tx_fifo_depth = 1024, // 发送fifo深度(32|64|128|...)
    parameter integer rx_fifo_depth = 1024, // 接收fifo深度(32|64|128|...)
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
    
    // I2C主机接口
    // scl
    output wire scl_t, // 1'b1为输入, 1'b0为输出
    input wire scl_i,
    output wire scl_o,
    // sda
    output wire sda_t, // 1'b1为输入, 1'b0为输出
    input wire sda_i,
    output wire sda_o,
    
    // 中断信号
    output wire itr
);
	
    /** 收发fifo **/
    // 发送fifo写端口
    wire[8:0] tx_fifo_din;
    wire tx_fifo_wen;
    wire tx_fifo_full;
    // 发送fifo读端口
    wire tx_fifo_ren;
    wire tx_fifo_empty;
    wire[7:0] tx_fifo_dout;
    wire tx_fifo_dout_last;
    // 接收fifo写端口
    wire rx_fifo_wen;
    wire rx_fifo_full;
    wire[7:0] rx_fifo_din;
    // 接收fifo读端口
    wire rx_fifo_ren;
    wire rx_fifo_empty;
    wire[7:0] rx_fifo_dout;
    
    // 发送fifo
    ram_fifo_wrapper #(
        .fwft_mode("false"),
        .ram_type(tx_rx_fifo_ram_type),
        .en_bram_reg("false"),
        .fifo_depth(tx_fifo_depth),
        .fifo_data_width(9),
        .full_assert_polarity("high"),
        .empty_assert_polarity("high"),
        .almost_full_assert_polarity("no"),
        .almost_empty_assert_polarity("no"),
        .en_data_cnt("false"),
        .almost_full_th(),
        .almost_empty_th(),
        .simulation_delay(simulation_delay)
    )tx_fifo(
        .clk(clk),
        .rst_n(resetn),
        .fifo_wen(tx_fifo_wen),
        .fifo_din(tx_fifo_din),
        .fifo_full(tx_fifo_full),
        .fifo_ren(tx_fifo_ren),
        .fifo_dout({tx_fifo_dout_last, tx_fifo_dout}),
        .fifo_empty(tx_fifo_empty)
    );
    
    // 接收fifo
	generate
		if(en_i2c_rx == "true")
		begin
			ram_fifo_wrapper #(
				.fwft_mode("false"),
				.ram_type(tx_rx_fifo_ram_type),
				.en_bram_reg("false"),
				.fifo_depth(rx_fifo_depth),
				.fifo_data_width(8),
				.full_assert_polarity("high"),
				.empty_assert_polarity("high"),
				.almost_full_assert_polarity("no"),
				.almost_empty_assert_polarity("no"),
				.en_data_cnt("false"),
				.almost_full_th(),
				.almost_empty_th(),
				.simulation_delay(simulation_delay)
			)rx_fifo(
				.clk(clk),
				.rst_n(resetn),
				.fifo_wen(rx_fifo_wen),
				.fifo_din(rx_fifo_din),
				.fifo_full(rx_fifo_full),
				.fifo_ren(rx_fifo_ren),
				.fifo_dout(rx_fifo_dout),
				.fifo_empty(rx_fifo_empty)
			);
		end
		else
		begin
			assign rx_fifo_full = 1'b0;
			
			assign rx_fifo_dout = 8'dx;
			assign rx_fifo_empty = 1'b1;
		end
	endgenerate
    
    /** 寄存器接口和中断处理 **/
	// I2C时钟分频系数
    wire[7:0] i2c_scl_div_rate;
    // I2C发送完成指示
    wire i2c_tx_done;
    wire[3:0] i2c_tx_bytes_n;
    // I2C接收完成指示
    wire i2c_rx_done;
    wire[3:0] i2c_rx_bytes_n;
    // I2C从机响应错误
    wire i2c_slave_resp_err;
    // I2C接收溢出
    wire i2c_rx_overflow;
    
    // 寄存器接口和中断处理
    regs_if_for_i2c #(
        .simulation_delay(simulation_delay)
    )regs_if_for_i2c_u(
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
        
        .tx_fifo_wen(tx_fifo_wen),
        .tx_fifo_din(tx_fifo_din),
        .tx_fifo_full(tx_fifo_full),
        
        .rx_fifo_ren(rx_fifo_ren),
        .rx_fifo_dout(rx_fifo_dout),
        .rx_fifo_empty(rx_fifo_empty),
        
        .i2c_scl_div_rate(i2c_scl_div_rate),
        
        .i2c_tx_done(i2c_tx_done),
        .i2c_tx_bytes_n(i2c_tx_bytes_n),
        .i2c_rx_done(i2c_rx_done),
        .i2c_rx_bytes_n(i2c_rx_bytes_n),
        .i2c_slave_resp_err(i2c_slave_resp_err),
        .i2c_rx_overflow(i2c_rx_overflow),
        
        .itr(itr)
    );
    
    /** I2C控制器 **/
    i2c_ctrler #(
        .addr_bits_n(addr_bits_n),
        .simulation_delay(simulation_delay)
    )i2c_ctrler_u(
        .clk(clk),
        .resetn(resetn),
        
        .i2c_scl_div_rate(i2c_scl_div_rate),
        
        .tx_fifo_ren(tx_fifo_ren),
        .tx_fifo_empty(tx_fifo_empty),
        .tx_fifo_dout(tx_fifo_dout),
        .tx_fifo_dout_last(tx_fifo_dout_last),
        
        .rx_fifo_wen(rx_fifo_wen),
        .rx_fifo_full(rx_fifo_full),
        .rx_fifo_din(rx_fifo_din),
        
        .i2c_tx_done(i2c_tx_done),
        .i2c_tx_bytes_n(i2c_tx_bytes_n),
        .i2c_rx_done(i2c_rx_done),
        .i2c_rx_bytes_n(i2c_rx_bytes_n),
        .i2c_slave_resp_err(i2c_slave_resp_err),
        .i2c_rx_overflow(i2c_rx_overflow),
        
        .scl_t(scl_t),
        .scl_i(scl_i),
        .scl_o(scl_o),
        .sda_t(sda_t),
        .sda_i(sda_i),
        .sda_o(sda_o)
    );
    
endmodule
