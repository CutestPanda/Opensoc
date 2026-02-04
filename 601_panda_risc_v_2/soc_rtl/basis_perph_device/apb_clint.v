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
本模块: APB-局部中断控制器

描述:
   偏移地址[7:0]    |    寄存器名称      |     功能描述
----------------------------------------------------
      0x0000      |    msip         |   生成软件中断
	  0x0010      |  mtimecmp       |  配置计时器的比较值
	  0x0018      |    mtime        |   反映计时器的值
	  0x0040      | gpio0_baseaddr  |  GPIO0外设基地址
	  0x0044      | gpio1_baseaddr  |  GPIO1外设基地址
	  0x0048      | i2c0_baseaddr   |  I2C0外设基地址
	  0x004C      | i2c1_baseaddr   |  I2C1外设基地址
	  0x0050      | spi0_baseaddr   |  SPI0外设基地址
	  0x0054      | spi1_baseaddr   |  SPI1外设基地址
	  0x0058      | uart0_baseaddr  |  UART0外设基地址
	  0x005C      | uart1_baseaddr  |  UART1外设基地址
	  0x0060      | timer0_baseaddr |  TIMER0外设基地址
	  0x0064      | timer1_baseaddr |  TIMER1外设基地址
	  0x0068      | timer2_baseaddr |  TIMER2外设基地址
	  0x006C      | timer3_baseaddr |  TIMER3外设基地址

注意：
无

协议:
APB SLAVE

作者: 陈家耀
日期: 2026/02/04
********************************************************************/


module apb_clint #(
	parameter integer RTC_PSC_R = 50 * 1000000, // RTC预分频系数
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 实时时钟计数使能
	input wire rtc_en,
	
	// APB从机
	input wire[31:0] s_apb_paddr,
    input wire s_apb_penable,
    input wire s_apb_pwrite,
    input wire s_apb_psel,
    input wire[3:0] s_apb_pstrb,
    input wire[31:0] s_apb_pwdata,
    output wire s_apb_pready, // const -> 1'b1
    output wire s_apb_pslverr, // const -> 1'b0
    output wire[31:0] s_apb_prdata,
	
	// 中断请求
	output wire sw_itr_req, // 软件中断请求
	output wire tmr_itr_req // 计时器中断请求
);
	
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
    end
    endfunction
	
	/** RTC计数指示 **/
	reg[clogb2(RTC_PSC_R-1):0] rtc_prescaler;
	reg rtc_tick;
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rtc_prescaler <= 0;
		else if(rtc_en)
			rtc_prescaler <= # SIM_DELAY 
				{(clogb2(RTC_PSC_R-1)+1){rtc_prescaler != (RTC_PSC_R-1)}} & (rtc_prescaler + 1);
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rtc_tick <= 1'b0;
		else
			rtc_tick <= # SIM_DELAY rtc_en & (rtc_prescaler == (RTC_PSC_R-1));
	end
	
	/** msip寄存器 **/
	reg msip;
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			msip <= 1'b0;
		else if(
			s_apb_psel & s_apb_penable & s_apb_pwrite & 
			s_apb_pstrb[0] & (s_apb_paddr[7:2] == (8'h00 >> 2))
		)
			msip <= # SIM_DELAY s_apb_pwdata[0];
	end
	
	/** mtimecmp寄存器 **/
	reg[63:0] mtimecmp;
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mtimecmp[7:0] <= 8'hFF;
		else if(
			s_apb_psel & s_apb_penable & s_apb_pwrite & 
			s_apb_pstrb[0] & (s_apb_paddr[7:2] == (8'h10 >> 2))
		)
			mtimecmp[7:0] <= # SIM_DELAY s_apb_pwdata[7:0];
	end
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mtimecmp[15:8] <= 8'hFF;
		else if(
			s_apb_psel & s_apb_penable & s_apb_pwrite & 
			s_apb_pstrb[1] & (s_apb_paddr[7:2] == (8'h10 >> 2))
		)
			mtimecmp[15:8] <= # SIM_DELAY s_apb_pwdata[15:8];
	end
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mtimecmp[23:16] <= 8'hFF;
		else if(
			s_apb_psel & s_apb_penable & s_apb_pwrite & 
			s_apb_pstrb[2] & (s_apb_paddr[7:2] == (8'h10 >> 2))
		)
			mtimecmp[23:16] <= # SIM_DELAY s_apb_pwdata[23:16];
	end
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mtimecmp[31:24] <= 8'hFF;
		else if(
			s_apb_psel & s_apb_penable & s_apb_pwrite & 
			s_apb_pstrb[3] & (s_apb_paddr[7:2] == (8'h10 >> 2))
		)
			mtimecmp[31:24] <= # SIM_DELAY s_apb_pwdata[31:24];
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mtimecmp[39:32] <= 8'hFF;
		else if(
			s_apb_psel & s_apb_penable & s_apb_pwrite & 
			s_apb_pstrb[0] & (s_apb_paddr[7:2] == (8'h14 >> 2))
		)
			mtimecmp[39:32] <= # SIM_DELAY s_apb_pwdata[7:0];
	end
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mtimecmp[47:40] <= 8'hFF;
		else if(
			s_apb_psel & s_apb_penable & s_apb_pwrite & 
			s_apb_pstrb[1] & (s_apb_paddr[7:2] == (8'h14 >> 2))
		)
			mtimecmp[47:40] <= # SIM_DELAY s_apb_pwdata[15:8];
	end
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mtimecmp[55:48] <= 8'hFF;
		else if(
			s_apb_psel & s_apb_penable & s_apb_pwrite & 
			s_apb_pstrb[2] & (s_apb_paddr[7:2] == (8'h14 >> 2))
		)
			mtimecmp[55:48] <= # SIM_DELAY s_apb_pwdata[23:16];
	end
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mtimecmp[63:56] <= 8'hFF;
		else if(
			s_apb_psel & s_apb_penable & s_apb_pwrite & 
			s_apb_pstrb[3] & (s_apb_paddr[7:2] == (8'h14 >> 2))
		)
			mtimecmp[63:56] <= # SIM_DELAY s_apb_pwdata[31:24];
	end
	
	/** mtime寄存器 **/
	reg[63:0] mtime;
	wire[63:0] mtime_add1;
	
	assign mtime_add1 = mtime + 64'd1;
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mtime[7:0] <= 8'h00;
		else if(
			s_apb_psel & s_apb_penable & s_apb_pwrite & 
			s_apb_pstrb[0] & (s_apb_paddr[7:2] == (8'h18 >> 2))
		)
			mtime[7:0] <= # SIM_DELAY s_apb_pwdata[7:0];
		else if(rtc_tick)
			mtime[7:0] <= # SIM_DELAY mtime_add1[7:0];
	end
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mtime[15:8] <= 8'h00;
		else if(
			s_apb_psel & s_apb_penable & s_apb_pwrite & 
			s_apb_pstrb[1] & (s_apb_paddr[7:2] == (8'h18 >> 2))
		)
			mtime[15:8] <= # SIM_DELAY s_apb_pwdata[15:8];
		else if(rtc_tick)
			mtime[15:8] <= # SIM_DELAY mtime_add1[15:8];
	end
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mtime[23:16] <= 8'h00;
		else if(
			s_apb_psel & s_apb_penable & s_apb_pwrite & 
			s_apb_pstrb[2] & (s_apb_paddr[7:2] == (8'h18 >> 2))
		)
			mtime[23:16] <= # SIM_DELAY s_apb_pwdata[23:16];
		else if(rtc_tick)
			mtime[23:16] <= # SIM_DELAY mtime_add1[23:16];
	end
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mtime[31:24] <= 8'h00;
		else if(
			s_apb_psel & s_apb_penable & s_apb_pwrite & 
			s_apb_pstrb[3] & (s_apb_paddr[7:2] == (8'h18 >> 2))
		)
			mtime[31:24] <= # SIM_DELAY s_apb_pwdata[31:24];
		else if(rtc_tick)
			mtime[31:24] <= # SIM_DELAY mtime_add1[31:24];
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mtime[39:32] <= 8'h00;
		else if(
			s_apb_psel & s_apb_penable & s_apb_pwrite & 
			s_apb_pstrb[0] & (s_apb_paddr[7:2] == (8'h1C >> 2))
		)
			mtime[39:32] <= # SIM_DELAY s_apb_pwdata[7:0];
		else if(rtc_tick)
			mtime[39:32] <= # SIM_DELAY mtime_add1[39:32];
	end
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mtime[47:40] <= 8'h00;
		else if(
			s_apb_psel & s_apb_penable & s_apb_pwrite & 
			s_apb_pstrb[1] & (s_apb_paddr[7:2] == (8'h1C >> 2))
		)
			mtime[47:40] <= # SIM_DELAY s_apb_pwdata[15:8];
		else if(rtc_tick)
			mtime[47:40] <= # SIM_DELAY mtime_add1[47:40];
	end
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mtime[55:48] <= 8'h00;
		else if(
			s_apb_psel & s_apb_penable & s_apb_pwrite & 
			s_apb_pstrb[2] & (s_apb_paddr[7:2] == (8'h1C >> 2))
		)
			mtime[55:48] <= # SIM_DELAY s_apb_pwdata[23:16];
		else if(rtc_tick)
			mtime[55:48] <= # SIM_DELAY mtime_add1[55:48];
	end
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mtime[63:56] <= 8'h00;
		else if(
			s_apb_psel & s_apb_penable & s_apb_pwrite & 
			s_apb_pstrb[3] & (s_apb_paddr[7:2] == (8'h1C >> 2))
		)
			mtime[63:56] <= # SIM_DELAY s_apb_pwdata[31:24];
		else if(rtc_tick)
			mtime[63:56] <= # SIM_DELAY mtime_add1[63:56];
	end
	
	/** 寄存器读结果 **/
	reg[31:0] regs_dout;
	
	assign s_apb_pready = 1'b1;
	assign s_apb_pslverr = 1'b0;
	assign s_apb_prdata = regs_dout;
	
	always @(posedge clk)
	begin
		if(s_apb_psel & (~s_apb_penable) & (~s_apb_pwrite))
		begin
			regs_dout <= # SIM_DELAY 
				({32{s_apb_paddr[7:2] == (8'h00 >> 2)}} & {31'd0, msip}) | 
				({32{s_apb_paddr[7:2] == (8'h10 >> 2)}} & mtimecmp[31:0]) | 
				({32{s_apb_paddr[7:2] == (8'h14 >> 2)}} & mtimecmp[63:32]) | 
				({32{s_apb_paddr[7:2] == (8'h18 >> 2)}} & mtime[31:0]) | 
				({32{s_apb_paddr[7:2] == (8'h1C >> 2)}} & mtime[63:32]) | 
				({32{s_apb_paddr[7:2] == (8'h40 >> 2)}} & 32'h4000_0000) | // GPIO0外设基地址
				({32{s_apb_paddr[7:2] == (8'h44 >> 2)}} & 32'h0000_0000) | // GPIO1外设基地址
				({32{s_apb_paddr[7:2] == (8'h48 >> 2)}} & 32'h0000_0000) | // I2C0外设基地址
				({32{s_apb_paddr[7:2] == (8'h4C >> 2)}} & 32'h0000_0000) | // I2C1外设基地址
				({32{s_apb_paddr[7:2] == (8'h50 >> 2)}} & 32'h0000_0000) | // SPI0外设基地址
				({32{s_apb_paddr[7:2] == (8'h54 >> 2)}} & 32'h0000_0000) | // SPI1外设基地址
				({32{s_apb_paddr[7:2] == (8'h58 >> 2)}} & 32'h4000_3000) | // UART0外设基地址
				({32{s_apb_paddr[7:2] == (8'h5C >> 2)}} & 32'h0000_0000) | // UART1外设基地址
				({32{s_apb_paddr[7:2] == (8'h60 >> 2)}} & 32'h4000_2000) | // TIMER0外设基地址
				({32{s_apb_paddr[7:2] == (8'h64 >> 2)}} & 32'h0000_0000) | // TIMER1外设基地址
				({32{s_apb_paddr[7:2] == (8'h68 >> 2)}} & 32'h0000_0000) | // TIMER2外设基地址
				({32{s_apb_paddr[7:2] == (8'h6C >> 2)}} & 32'h0000_0000) | // TIMER3外设基地址
				({32{s_apb_paddr[7:2] == (8'h70 >> 2)}} & 32'h0000_0000) | // TIMER4外设基地址
				({32{s_apb_paddr[7:2] == (8'h74 >> 2)}} & 32'h0000_0000) | // TIMER5外设基地址
				({32{s_apb_paddr[7:2] == (8'h78 >> 2)}} & 32'h0000_0000) | // TIMER6外设基地址
				({32{s_apb_paddr[7:2] == (8'h7C >> 2)}} & 32'h0000_0000);  // TIMER7外设基地址
		end
	end
	
	/** 中断请求 **/
	reg tmr_itr_req_r;
	
	assign sw_itr_req = msip;
	assign tmr_itr_req = tmr_itr_req_r;
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			tmr_itr_req_r <= 1'b0;
		else
			tmr_itr_req_r <= # SIM_DELAY mtime >= mtimecmp;
	end
	
endmodule
