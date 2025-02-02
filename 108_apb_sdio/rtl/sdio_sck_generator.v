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
本模块: SDIO时钟发生器

描述:
可动态配置分频数
支持任意整数倍分频
使用ODDR输出

注意：
分频数和分频计数器使能只能在关闭SDIO时钟或者分频计数器溢出时改变

协议:
无

作者: 陈家耀
日期: 2024/07/30
********************************************************************/


module sdio_sck_generator #(
    parameter integer div_cnt_width = 10, // 分频计数器位宽
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire resetn,
    
    // 运行时参数
    input wire en_sdio_clk, // 启用SDIO时钟(复位时必须为0)
    input wire[div_cnt_width-1:0] div_rate, // 分频数 - 1
    
    // 分频计数器使能
    input wire div_cnt_en,
	
	// SDIO输入采样指示
	output wire sdio_in_sample,
	// SDIO输出更新指示
	output wire sdio_out_upd,
    
    // SDIO时钟
    output wire sdio_clk
);
	
	/** 内部配置 **/
	localparam en_oddr_in_reg = "false"; // 是否使用ODDR输入寄存器
	
    /** ODDR **/
	wire oddr_posedge_in_w; // ODDR上升沿数据输入
	wire oddr_negedge_in_w; // ODDR下降沿数据输入
	reg oddr_posedge_in; // ODDR上升沿数据输入寄存器
	reg oddr_negedge_in; // ODDR下降沿数据输入寄存器
	
	// ODDR上升沿数据输入寄存器
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			oddr_posedge_in <= 1'b0;
		else
			# simulation_delay oddr_posedge_in <= oddr_posedge_in_w;
	end
	// ODDR下降沿数据输入寄存器
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			oddr_negedge_in <= 1'b0;
		else
			# simulation_delay oddr_negedge_in <= oddr_negedge_in_w;
	end
	
	// ODDR
	EG_LOGIC_ODDR #(
		.ASYNCRST("ENABLE")
	)oddr_u(
		.q(sdio_clk),
		
		.clk(clk),
		
		.d0((en_oddr_in_reg == "true") ? oddr_posedge_in:oddr_posedge_in_w),
		.d1((en_oddr_in_reg == "true") ? oddr_negedge_in:oddr_negedge_in_w),
		
		.rst(~resetn)
	);
	
	/** SDIO时钟分频 **/
	reg div_cnt_en_shadow; // 分频计数器使能(影子寄存器)
	reg[div_cnt_width-1:0] div_rate_shadow; // 分频数(影子寄存器)
	wire to_turn_off_sdio_clk; // 关闭SDIO时钟(标志)
	wire on_div_cnt_rst; // 分频计数器回零(指示)
	wire div_cnt_eq_div_rate_shadow_rsh1; // 分频计数器 == (分频数(影子寄存器) >> 1)
	reg[div_cnt_width-1:0] div_cnt; // 分频计数器
	
	assign oddr_posedge_in_w = (div_cnt > div_rate_shadow[div_cnt_width-1:1]) & (~to_turn_off_sdio_clk);
	assign oddr_negedge_in_w = ((div_cnt > div_rate_shadow[div_cnt_width-1:1]) | 
		(div_cnt_eq_div_rate_shadow_rsh1 & (~div_rate_shadow[0]))) & (~to_turn_off_sdio_clk);
	
	assign to_turn_off_sdio_clk = (~en_sdio_clk) | (~div_cnt_en_shadow);
	assign on_div_cnt_rst = div_cnt == div_rate_shadow;
	assign div_cnt_eq_div_rate_shadow_rsh1 = div_cnt == div_rate_shadow[div_cnt_width-1:1];
	
	// 分频计数器使能(影子寄存器)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			div_cnt_en_shadow <= 1'b0;
		else if(to_turn_off_sdio_clk | on_div_cnt_rst) // 载入
			# simulation_delay div_cnt_en_shadow <= div_cnt_en;
	end
	// 分频数(影子寄存器)
	always @(posedge clk)
	begin
		if(to_turn_off_sdio_clk | on_div_cnt_rst) // 载入
			# simulation_delay div_rate_shadow <= div_rate;
	end
	
	// 分频计数器
	always @(posedge clk)
	begin
		if(to_turn_off_sdio_clk | on_div_cnt_rst) // 清零
			# simulation_delay div_cnt <= 0;
		else // 更新
			# simulation_delay div_cnt <= div_cnt + 1;
	end
	
	/** SDIO输入采样和输出更新指示 **/
	reg sdio_in_sample_reg; // SDIO输入采样指示
	reg sdio_in_sample_reg_d; // 延迟1clk的SDIO输入采样指示
	reg sdio_out_upd_reg; // SDIO输出更新指示
	reg sdio_out_upd_reg_d; // 延迟1clk的SDIO输出更新指示
	
	assign sdio_in_sample = (en_oddr_in_reg == "true") ? sdio_in_sample_reg_d:sdio_in_sample_reg;
	assign sdio_out_upd = (en_oddr_in_reg == "true") ? sdio_out_upd_reg_d:sdio_out_upd_reg;
	
	// SDIO输入采样指示
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			sdio_in_sample_reg <= 1'b0;
		else // 生成脉冲
			# simulation_delay sdio_in_sample_reg <= (~to_turn_off_sdio_clk) & 
				(div_cnt == (div_rate_shadow[div_cnt_width-1:1] + div_rate_shadow[0]));
	end
	// SDIO输出更新指示
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			sdio_out_upd_reg <= 1'b0;
		else // 生成脉冲
			# simulation_delay sdio_out_upd_reg <= (~to_turn_off_sdio_clk) & on_div_cnt_rst;
	end
	
	// 延迟1clk的SDIO输入采样指示
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			sdio_in_sample_reg_d <= 1'b0;
		else // 延迟
			# simulation_delay sdio_in_sample_reg_d <= sdio_in_sample_reg;
	end
	// 延迟1clk的SDIO输出更新指示
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			sdio_out_upd_reg_d <= 1'b0;
		else // 延迟
			# simulation_delay sdio_out_upd_reg_d <= sdio_out_upd_reg;
	end
	
endmodule
