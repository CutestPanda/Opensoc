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
本模块: 多通道卷积结果行缓存区

描述:
存储输出特征图某个通道的某1行

写行缓存区时先读出原数据再加上新的中间结果后写回

MEM位宽 = ft_vld_width
MEM深度 = max_feature_map_w
MEM写延迟 = 2clk
MEM读延迟 = 1clk

注意：
无

协议:
MEM READ/WRITE

作者: 陈家耀
日期: 2024/11/02
********************************************************************/


module conv_out_line_buffer #(
	parameter integer ft_vld_width = 20, // 特征点有效位宽(必须<=ft_ext_width)
	parameter integer max_feature_map_w = 512, // 最大的输入特征图宽度
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 行缓存区读/写端口
	input wire buffer_en,
	input wire buffer_wen,
	input wire[15:0] buffer_addr,
	input wire buffer_w_first_grp, // 写第1组中间结果(标志)
	input wire[ft_vld_width-1:0] buffer_din,
	output wire[ft_vld_width-1:0] buffer_dout,
	
	// 行缓存区状态
	output wire conv_mid_res_updating // 正在更新卷积中间结果
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
	
	/** 行缓存区MEM **/
	// MEM写端口
	wire mem_wen_a;
	wire[clogb2(max_feature_map_w-1):0] mem_addr_a;
    wire[ft_vld_width-1:0] mem_din_a;
	// MEM读端口
	wire mem_ren_b;
    wire[clogb2(max_feature_map_w-1):0] mem_addr_b;
    wire[ft_vld_width-1:0] mem_dout_b;
	// 写回新的中间结果
	reg on_mem_wen_d; // 延迟1clk的有效的MEM写使能
	reg on_mem_wen_d2; // 延迟2clk的有效的MEM写使能
	reg buffer_w_first_grp_d; // 延迟1clk的写第1组中间结果标志
	reg[ft_vld_width-1:0] buffer_din_d; // 延迟1clk的写数据
	reg[clogb2(max_feature_map_w-1):0] buffer_waddr_d; // 延迟1clk的写地址
	reg[clogb2(max_feature_map_w-1):0] buffer_waddr_d2; // 延迟2clk的写地址
	reg[ft_vld_width-1:0] new_conv_mid_res; // 新的卷积中间结果
	// 行缓存区状态
	reg buffer_updating; // 正在更新卷积中间结果(标志)
	
	assign mem_wen_a = on_mem_wen_d2;
	assign mem_addr_a = buffer_waddr_d2;
	assign mem_din_a = new_conv_mid_res;
	
	assign mem_ren_b = buffer_en & ((~buffer_wen) | (~buffer_w_first_grp));
	assign mem_addr_b = buffer_addr;
	assign buffer_dout = mem_dout_b;
	
	assign conv_mid_res_updating = buffer_updating;
	
	// 延迟1clk的有效的MEM写使能
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			on_mem_wen_d <= 1'b0;
		else
			on_mem_wen_d <= # simulation_delay buffer_en & buffer_wen;
	end
	// 延迟2clk的有效的MEM写使能
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			on_mem_wen_d2 <= 1'b0;
		else
			on_mem_wen_d2 <= # simulation_delay on_mem_wen_d;
	end
	
	// 延迟1clk的写第1组中间结果标志
	always @(posedge clk)
	begin
		if(buffer_en & buffer_wen)
			buffer_w_first_grp_d <= # simulation_delay buffer_w_first_grp;
	end
	
	// 延迟1clk的写数据
	always @(posedge clk)
	begin
		if(buffer_en & buffer_wen)
			buffer_din_d <= # simulation_delay buffer_din;
	end
	
	// 延迟1clk的写地址
	always @(posedge clk)
	begin
		if(buffer_en & buffer_wen)
			buffer_waddr_d <= # simulation_delay buffer_addr[clogb2(max_feature_map_w-1):0];
	end
	// 延迟2clk的写地址
	always @(posedge clk)
	begin
		if(on_mem_wen_d)
			buffer_waddr_d2 <= # simulation_delay buffer_waddr_d;
	end
	
	// 新的卷积中间结果
	always @(posedge clk)
	begin
		if(on_mem_wen_d)
			// buffer_w_first_grp_d ? buffer_din_d:(buffer_din_d + mem_dout_b)
			new_conv_mid_res <= # simulation_delay buffer_din_d + 
				({ft_vld_width{~buffer_w_first_grp_d}} & mem_dout_b);
	end
	
	// 正在更新卷积中间结果(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_updating <= 1'b0;
		else
			buffer_updating <= # simulation_delay (buffer_en & buffer_wen) | on_mem_wen_d;
	end
	
	// 行缓存区MEM
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(ft_vld_width),
		.mem_depth(max_feature_map_w),
		.INIT_FILE("no_init"),
		.byte_write_mode("false"),
		.simulation_delay(simulation_delay)
	)line_buffer_mem(
		.clk(clk),
		
		.wen_a(mem_wen_a),
		.addr_a(mem_addr_a),
		.din_a(mem_din_a),
		
		.ren_b(mem_ren_b),
		.addr_b(mem_addr_b),
		.dout_b(mem_dout_b)
	);
	
endmodule
