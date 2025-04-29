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
本模块: 以太网MDIO控制器

描述:
接收MDIO读/写请求, 驱动MDIO接口

注意：
无

协议:
BLK CTRL
MDIO

作者: 陈家耀
日期: 2025/04/22
********************************************************************/


module eth_mac_mdio #(
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 运行时参数
	input wire[9:0] mdc_div_rate, // MDIO时钟分频系数(分频数 = (分频系数 + 1) * 2)
	
	// 块级控制
	input wire mdio_access_start,
	input wire mdio_access_is_rd, // 是否读寄存器
	input wire[9:0] mdio_access_addr, // 访问地址({寄存器地址(5位), PHY地址(5位)})
	input wire[15:0] mdio_access_wdata, // 写数据
	output wire mdio_access_idle,
	output wire[15:0] mdio_access_rdata, // 读数据
	output wire mdio_access_done,
	
	// MDIO接口
	output wire mdc,
	input wire mdio_i,
	output wire mdio_o,
	output wire mdio_t // 1为输入, 0为输出
);
	
	/** MDIO接口 **/
	wire mdc_en;
	reg[9:0] mdc_div_cnt;
	wire mdc_to_rise;
	wire mdc_to_fall;
	reg mdc_r;
	reg[6:0] mdio_cnt;
	reg mdio_is_rd_trans;
	reg[31:0] mdio_trans_data;
	reg mdio_to_sample;
	reg[15:0] mdio_rdata;
	reg mdio_o_r;
	reg mdio_t_r;
	reg mdio_access_idle_r;
	
	assign mdio_access_idle = mdio_access_idle_r;
	assign mdio_access_rdata = mdio_rdata;
	assign mdio_access_done = (mdio_cnt == 7'd0) & mdc_to_rise;
	
	assign mdc = mdc_r;
	assign mdio_o = mdio_o_r;
	assign mdio_t = mdio_t_r;
	
	assign mdc_en = ~mdio_access_idle_r;
	assign mdc_to_rise = mdc_en & (~mdc_r) & (mdc_div_cnt == mdc_div_rate);
	assign mdc_to_fall = mdc_en & mdc_r & (mdc_div_cnt == mdc_div_rate);
	
	always @(posedge aclk)
	begin
		if(~mdc_en)
			mdc_div_cnt <= 10'd0;
		else
			mdc_div_cnt <= # SIM_DELAY 
				(mdc_div_cnt == mdc_div_rate) ? 
					10'd0:
					(mdc_div_cnt + 10'd1);
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mdc_r <= 1'b1;
		else if(mdc_to_rise | mdc_to_fall)
			mdc_r <= # SIM_DELAY ~mdc_r;
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mdio_cnt <= 7'd0;
		else if(mdc_to_fall)
			mdio_cnt <= # SIM_DELAY 
				(mdio_cnt >= 7'd64) ? 
					7'd0:
					(mdio_cnt + 7'd1);
	end
	
	always @(posedge aclk)
	begin
		if(mdio_access_idle_r & mdio_access_start)
			mdio_is_rd_trans <= # SIM_DELAY mdio_access_is_rd;
	end
	
	always @(posedge aclk)
	begin
		if(mdio_access_idle_r & mdio_access_start)
			mdio_trans_data <= # SIM_DELAY {
				2'b01, // ST
				mdio_access_is_rd ? 2'b10:2'b01, // OP
				mdio_access_addr[4:0], // PHYAD
				mdio_access_addr[9:5], // REGAD
				mdio_access_is_rd ? 2'b11:2'b10, // TA
				mdio_access_is_rd ? 16'hffff:mdio_access_wdata // DATA
			};
		else if(mdc_to_fall & (
			(mdio_cnt > 7'd31) & (mdio_cnt <= 7'd63)
		))
			mdio_trans_data <= # SIM_DELAY {mdio_trans_data[30:0], 1'bx};
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mdio_to_sample <= 1'b0;
		else
			mdio_to_sample <= # SIM_DELAY mdc_to_rise & (mdio_cnt >= 7'd49);
	end
	
	always @(posedge aclk)
	begin
		if(mdio_to_sample)
			mdio_rdata <= # SIM_DELAY {mdio_rdata[14:0], mdio_i};
	end
	
	always @(posedge aclk)
	begin
		if(mdc_to_fall)
			mdio_o_r <= # SIM_DELAY 
				((mdio_cnt <= 7'd31) | (mdio_cnt == 7'd64)) ? 
					1'b1:
					mdio_trans_data[31];
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mdio_t_r <= 1'b1;
		else if(mdc_to_fall & (
			(mdio_cnt == 7'd32) | 
			((mdio_cnt == 7'd46) & mdio_is_rd_trans) | 
			(mdio_cnt == 7'd64)
		))
			/*
			写寄存器:
				0~31  输入
				32~45 输出
				46~63 输出
				64    输入
			
			读寄存器:
				0~31  输入
				32~45 输出
				46~63 输入
				64    输入
			*/
			mdio_t_r <= # SIM_DELAY ~(mdio_cnt == 7'd32);
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mdio_access_idle_r <= 1'b1;
		else if(
			mdio_access_idle_r ? 
				mdio_access_start:
				mdio_access_done
		)
			mdio_access_idle_r <= # SIM_DELAY ~mdio_access_idle_r;
	end
	
endmodule
