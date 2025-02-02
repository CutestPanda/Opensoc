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
本模块: APB-I2C的寄存器接口

描述: 
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

作者: 陈家耀
日期: 2024/06/14
********************************************************************/


module regs_if_for_i2c #(
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
    
    // 发送fifo写端口
    output wire tx_fifo_wen,
    output wire[8:0] tx_fifo_din,
    input wire tx_fifo_full,
    // 接收fifo读端口
    output wire rx_fifo_ren,
    input wire[7:0] rx_fifo_dout,
    input wire rx_fifo_empty,
    
    // I2C时钟分频系数
    output wire[7:0] i2c_scl_div_rate,
    
    // I2C发送完成指示
    input wire i2c_tx_done,
    input wire[3:0] i2c_tx_bytes_n,
    // I2C接收完成指示
    input wire i2c_rx_done,
    input wire[3:0] i2c_rx_bytes_n,
    // I2C从机响应错误
    input wire i2c_slave_resp_err,
    // I2C接收溢出
    input wire i2c_rx_overflow,
    
    // 中断信号
    output wire itr
);
    
    /** APB写寄存器和中断处理 **/
    // 0x00
    reg tx_fifo_wen_reg; // 发送fifo写使能
    reg[8:0] tx_fifo_din_regs; // 发送fifo写数据
    reg rx_fifo_ren_reg; // 接收fifo读使能
    // 0x04
    reg global_itr_en; // 全局中断使能
    reg i2c_tx_reach_bytes_n_itr_en; // I2C发送指定字节数中断使能
    reg i2c_slave_resp_err_itr_en; // I2C从机响应错误中断使能
    reg i2c_rx_reach_bytes_n_itr_en; // I2C接收指定字节数中断使能
    reg i2c_rx_overflow_itr_en; // I2C接收溢出中断使能
    // 0x08
    reg[7:0] i2c_tx_bytes_n_th; // I2C发送中断字节数阈值
    reg[7:0] i2c_rx_bytes_n_th; // I2C接收中断字节数阈值
    reg[7:0] i2c_scl_div_rate_regs; // I2C时钟分频系数
    // 0x0C
    reg global_itr_flag; // 全局中断标志
    reg[3:0] sub_itr_flag; // 子中断标志
    reg[11:0] i2c_bytes_n_sent; // I2C发送字节数
    reg[11:0] i2c_bytes_n_rev; // I2C接收字节数
    // 中断处理
    reg i2c_tx_done_d; // 延迟1clk的I2C发送完成指示
    reg i2c_rx_done_d; // 延迟1clk的I2C发送完成指示
    reg i2c_tx_reach_bytes_n_itr_req; // I2C发送指定字节数中断请求
    wire i2c_slave_resp_err_itr_req; // I2C从机响应错误中断请求
    reg i2c_rx_reach_bytes_n_itr_req; // I2C接收指定字节数中断请求
    wire i2c_rx_overflow_itr_req; // I2C接收溢出中断请求
    wire[3:0] org_itr_req_vec; // 原始中断请求向量
    wire global_itr_req; // 总中断请求
    
    assign tx_fifo_wen = tx_fifo_wen_reg;
    assign tx_fifo_din = tx_fifo_din_regs;
    assign rx_fifo_ren = rx_fifo_ren_reg;
    
    assign i2c_scl_div_rate = i2c_scl_div_rate_regs;
    
    assign i2c_slave_resp_err_itr_req = i2c_slave_resp_err;
    assign i2c_rx_overflow_itr_req = i2c_rx_overflow;
    
    assign org_itr_req_vec = {i2c_rx_overflow_itr_req, i2c_rx_reach_bytes_n_itr_req, i2c_slave_resp_err_itr_req, i2c_tx_reach_bytes_n_itr_req} & 
        {i2c_rx_overflow_itr_en, i2c_rx_reach_bytes_n_itr_en, i2c_slave_resp_err_itr_en, i2c_tx_reach_bytes_n_itr_en};
    assign global_itr_req = (|org_itr_req_vec) & global_itr_en & (~global_itr_flag);
    
    // 发送fifo写使能
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            tx_fifo_wen_reg <= 1'b0;
        else
            # simulation_delay tx_fifo_wen_reg <= psel & penable & pwrite & (paddr[3:2] == 2'd0) & pwdata[1];
    end
    // 发送fifo写数据
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[3:2] == 2'd0))
            # simulation_delay tx_fifo_din_regs <= pwdata[10:2];
    end
    // 接收fifo读使能
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            rx_fifo_ren_reg <= 1'b0;
        else
            # simulation_delay rx_fifo_ren_reg <= psel & penable & pwrite & (paddr[3:2] == 2'd0) & pwdata[17];
    end
    
    // 全局中断使能
    // I2C发送指定字节数中断使能
    // I2C从机响应错误中断使能
    // I2C接收指定字节数中断使能
    // I2C接收溢出中断使能
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            {i2c_rx_overflow_itr_en, i2c_rx_reach_bytes_n_itr_en, i2c_slave_resp_err_itr_en, i2c_tx_reach_bytes_n_itr_en, global_itr_en} <= 5'd0;
        else if(psel & penable & pwrite & (paddr[3:2] == 2'd1))
            # simulation_delay {i2c_rx_overflow_itr_en, i2c_rx_reach_bytes_n_itr_en, i2c_slave_resp_err_itr_en, i2c_tx_reach_bytes_n_itr_en, global_itr_en} <= 
                {pwdata[11:8], pwdata[0]};
    end
    
    // I2C发送中断字节数阈值
    // I2C接收中断字节数阈值
    // I2C时钟分频系数
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[3:2] == 2'd2))
            # simulation_delay {i2c_scl_div_rate_regs, i2c_rx_bytes_n_th, i2c_tx_bytes_n_th} <= pwdata[23:0];
    end
    
    // 全局中断标志
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            global_itr_flag <= 1'b0;
        else if(psel & penable & pwrite & (paddr[3:2] == 2'd3))
            # simulation_delay global_itr_flag <= 1'b0;
        else if(~global_itr_flag)
            # simulation_delay global_itr_flag <= global_itr_req;
    end
    // 子中断标志
    always @(posedge clk)
    begin
        if(global_itr_req)
            # simulation_delay sub_itr_flag <= org_itr_req_vec;
    end
    // I2C发送字节数
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_bytes_n_sent <= 12'd0;
        else if(psel & penable & pwrite & (paddr[3:2] == 2'd3))
            # simulation_delay i2c_bytes_n_sent <= 12'd0;
        else if(i2c_tx_done)
            # simulation_delay i2c_bytes_n_sent <= i2c_bytes_n_sent + i2c_tx_bytes_n;
    end
    // I2C接收字节数
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_bytes_n_rev <= 12'd0;
        else if(psel & penable & pwrite & (paddr[3:2] == 2'd3))
            # simulation_delay i2c_bytes_n_rev <= 12'd0;
        else if(i2c_rx_done)
            # simulation_delay i2c_bytes_n_rev <= i2c_bytes_n_rev + i2c_rx_bytes_n;
    end
    
    // 延迟1clk的I2C发送完成指示
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_tx_done_d <= 1'b0;
        else
            # simulation_delay i2c_tx_done_d <= i2c_tx_done;
    end
    // 延迟1clk的I2C发送完成指示
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_rx_done_d <= 1'b0;
        else
            # simulation_delay i2c_rx_done_d <= i2c_rx_done;
    end
    // I2C发送指定字节数中断请求
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_tx_reach_bytes_n_itr_req <= 1'b0;
        else
            # simulation_delay i2c_tx_reach_bytes_n_itr_req <= i2c_tx_done_d & (i2c_bytes_n_sent > i2c_tx_bytes_n_th);
    end
    // I2C接收指定字节数中断请求
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_rx_reach_bytes_n_itr_req <= 1'b0;
        else
            # simulation_delay i2c_rx_reach_bytes_n_itr_req <= i2c_rx_done_d & (i2c_bytes_n_rev > i2c_rx_bytes_n_th);
    end
    
    // 中断发生器
    itr_generator #(
        .pulse_w(10),
        .simulation_delay(simulation_delay)
    )itr_generator_u(
        .clk(clk),
        .rst_n(resetn),
        
        .itr_org(global_itr_req),
        
        .itr(itr)
    );
    
    /** APB读寄存器 **/
    reg[31:0] prdata_out_regs; // APB读数据输出
    
    assign pready_out = 1'b1;
    assign prdata_out = prdata_out_regs;
    assign pslverr_out = 1'b0;
    
    // APB读数据输出
	generate
		if(simulation_delay == 0)
		begin
			always @(posedge clk)
			begin
				if(psel & (~pwrite))
				begin
					# simulation_delay;
					
					case(paddr[3:2])
						2'd0: prdata_out_regs <= {6'dx, rx_fifo_dout, 1'bx, rx_fifo_empty, 15'dx, tx_fifo_full};
						2'd1: prdata_out_regs <= 32'dx;
						2'd2: prdata_out_regs <= 32'dx;
						2'd3: prdata_out_regs <= {i2c_bytes_n_rev, i2c_bytes_n_sent, 3'dx, sub_itr_flag, global_itr_flag};
						default: prdata_out_regs <= 32'dx;
					endcase
				end
			end
		end
		else
		begin
			always @(posedge clk)
			begin
				if(psel & (~pwrite))
				begin
					# simulation_delay;
					
					case(paddr[3:2])
						2'd0: prdata_out_regs <= {6'd0, rx_fifo_dout, 1'b0, rx_fifo_empty, 15'd0, tx_fifo_full};
						2'd1: prdata_out_regs <= 32'd0;
						2'd2: prdata_out_regs <= 32'd0;
						2'd3: prdata_out_regs <= {i2c_bytes_n_rev, i2c_bytes_n_sent, 3'd0, sub_itr_flag, global_itr_flag};
						default: prdata_out_regs <= 32'd0;
					endcase
				end
			end
		end
	endgenerate
    
endmodule
