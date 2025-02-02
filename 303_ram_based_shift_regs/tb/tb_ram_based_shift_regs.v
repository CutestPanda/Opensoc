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

module tb_ram_based_shift_regs();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer data_width = 8; // 数据位宽
    localparam integer delay_n = 10; // 延迟周期数
    localparam shift_type = "ram"; // 移位寄存器类型(ram | ff)
    localparam ram_type = "lutram"; // ram类型(lutram | bram)
    localparam INIT_FILE = "no_init"; // RAM初始化文件路径
    localparam en_output_register_init = "false"; // 输出寄存器是否需要复位
    localparam output_register_init_v = 0; // 输出寄存器复位值
	// 时钟和复位配置
	localparam real clk_p = 10.0; // 时钟周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 时钟和复位 **/
	reg clk;
	reg rst_n;
	
	initial
	begin
		clk <= 1'b1;
		
		forever
		begin
			# (clk_p / 2) clk <= ~clk;
		end
	end
	
	initial begin
		rst_n <= 1'b0;
		
		# (clk_p * 10 + simulation_delay);
		
		rst_n <= 1'b1;
	end
	
	/** 激励产生 **/
	reg[data_width-1:0] shift_in;
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			shift_in <= 0;
		else
			shift_in <= # simulation_delay shift_in + 1;
	end
	
	/** 待测模块 **/
	wire[data_width-1:0] shift_out;
	
	ram_based_shift_regs #(
		.data_width(data_width),
		.delay_n(delay_n),
		.shift_type(shift_type),
		.ram_type(ram_type),
		.INIT_FILE(INIT_FILE),
		.en_output_register_init(en_output_register_init),
		.output_register_init_v(output_register_init_v),
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.resetn(rst_n),
		
		.shift_in(shift_in),
		.ce(1'b1),
		.shift_out(shift_out)
	);
	
endmodule
