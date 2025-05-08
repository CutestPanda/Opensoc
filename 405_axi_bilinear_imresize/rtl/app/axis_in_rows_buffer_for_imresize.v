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
本模块: AXIS源图片行缓存

描述:
接收源图片像素流, 使用乒乓RAM作行缓存
写入单位 = 1行, 读取单位 = 2行

注意：
源图片缓存MEM读时延 = 1clk

协议:
AXIS SLAVE
VFIFO SLAVE
MEM SLAVE

作者: 陈家耀
日期: 2025/02/21
********************************************************************/


module axis_in_rows_buffer_for_imresize #(
	parameter integer STREAM_WIDTH = 32, // 数据流位宽(8 | 16 | 32 | 64)
	parameter integer BUF_MEM_DEPTH = 1024, // 缓存MEM深度
	parameter USE_DUAL_PORT_RAM = "true", // 是否使用双口RAM
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// 源图片像素流(AXIS从机)
	input wire[STREAM_WIDTH-1:0] s_axis_data,
	input wire s_axis_last, // 行尾指示
	input wire s_axis_valid,
	output wire s_axis_ready,
	
	// 源图片缓存虚拟fifo读端口
	input wire src_img_vfifo_ren,
	output wire src_img_vfifo_empty_n,
	
	// 源图片缓存MEM读端口
	input wire src_img_mem_ren,
	input wire[15:0] src_img_mem_raddr, // 以字节计
	output wire[7:0] src_img_mem_dout_0,
	output wire[7:0] src_img_mem_dout_1
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
	
	/** 源图片缓存虚拟fifo **/
	reg[2:0] src_img_vfifo_store_n; // 存储行数
	wire src_img_vfifo_wen; // 写使能
	wire src_img_vfifo_full_n; // 满标志
	reg[3:0] src_img_vfifo_wptr; // 写指针
	reg src_img_vfifo_rptr; // 读指针
	reg src_img_vfifo_rptr_d; // 延迟1clk的读指针
	
	assign s_axis_ready = src_img_vfifo_full_n;
	
	assign src_img_vfifo_empty_n = src_img_vfifo_store_n[2] | src_img_vfifo_store_n[1]; // src_img_vfifo_store_n >= 3'b010
	assign src_img_vfifo_full_n = ~src_img_vfifo_store_n[2]; // src_img_vfifo_store_n < 3'b100
	
	assign src_img_vfifo_wen = s_axis_valid & s_axis_last;
	
	// 存储行数
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			src_img_vfifo_store_n <= 3'b000;
		else if((src_img_vfifo_wen & src_img_vfifo_full_n) | (src_img_vfifo_ren & src_img_vfifo_empty_n))
			src_img_vfifo_store_n <= # SIM_DELAY 
				src_img_vfifo_store_n + 
				{2'b00, src_img_vfifo_wen & src_img_vfifo_full_n} - 
				{1'b0, src_img_vfifo_ren & src_img_vfifo_empty_n, 1'b0};
	end
	
	// 写指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			src_img_vfifo_wptr <= 4'b0001;
		else if(src_img_vfifo_wen & src_img_vfifo_full_n)
			src_img_vfifo_wptr <= # SIM_DELAY {src_img_vfifo_wptr[2:0], src_img_vfifo_wptr[3]};
	end
	
	// 读指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			src_img_vfifo_rptr <= 1'b0;
		else if(src_img_vfifo_ren & src_img_vfifo_empty_n)
			src_img_vfifo_rptr <= # SIM_DELAY ~src_img_vfifo_rptr;
	end
	
	// 延迟1clk的读指针
	always @(posedge clk)
	begin
		if(src_img_mem_ren & src_img_vfifo_empty_n)
			src_img_vfifo_rptr_d <= # SIM_DELAY src_img_vfifo_rptr;
	end
	
	/** 源图片缓存MEM地址 **/
	reg[clogb2(BUF_MEM_DEPTH-1):0] src_img_mem_waddr;
	reg[clogb2(STREAM_WIDTH/8-1):0] src_img_mem_raddr_low_d;
	
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			src_img_mem_waddr <= 0;
		else if(s_axis_valid & s_axis_ready)
			// s_axis_last ? 0:(src_img_mem_waddr + 1)
			src_img_mem_waddr <= # SIM_DELAY {(clogb2(BUF_MEM_DEPTH-1)+1){~s_axis_last}} & (src_img_mem_waddr + 1);
	end
	
	always @(posedge clk)
	begin
		if(src_img_mem_ren & src_img_vfifo_empty_n)
			src_img_mem_raddr_low_d <= # SIM_DELAY (STREAM_WIDTH >= 16) ? src_img_mem_raddr[clogb2(STREAM_WIDTH/8-1):0]:1'b0;
	end
	
	/** 源图片缓存MEM **/
	wire[3:0] on_src_img_mem_wen;
	wire[3:0] on_src_img_mem_ren;
	wire[3:0] ping_pong_ram_en;
	wire[3:0] ping_pong_ram_wen;
	wire[clogb2(BUF_MEM_DEPTH-1):0] ping_pong_ram_addr[0:3];
	wire[STREAM_WIDTH-1:0] ping_pong_ram_din[0:3];
	wire[STREAM_WIDTH-1:0] ping_pong_ram_dout[0:3];
	
	assign src_img_mem_dout_0 = 
		(src_img_vfifo_rptr_d ? 
			ping_pong_ram_dout[2]:
			ping_pong_ram_dout[0]) >> {src_img_mem_raddr_low_d, 3'b000};
	assign src_img_mem_dout_1 = 
		(src_img_vfifo_rptr_d ? 
			ping_pong_ram_dout[3]:
			ping_pong_ram_dout[1]) >> {src_img_mem_raddr_low_d, 3'b000};
	
	assign on_src_img_mem_wen = {4{s_axis_valid & s_axis_ready}} & src_img_vfifo_wptr;
	assign on_src_img_mem_ren = {4{src_img_mem_ren & src_img_vfifo_empty_n}} & {{2{src_img_vfifo_rptr}}, {2{~src_img_vfifo_rptr}}};
	
	genvar ping_pong_ram_i;
	generate
		for(ping_pong_ram_i = 0;ping_pong_ram_i < 4;ping_pong_ram_i = ping_pong_ram_i + 1)
		begin
			assign ping_pong_ram_en[ping_pong_ram_i] = on_src_img_mem_wen[ping_pong_ram_i] | on_src_img_mem_ren[ping_pong_ram_i];
			assign ping_pong_ram_wen[ping_pong_ram_i] = on_src_img_mem_wen[ping_pong_ram_i];
			assign ping_pong_ram_addr[ping_pong_ram_i] = 
				on_src_img_mem_wen[ping_pong_ram_i] ? 
					src_img_mem_waddr:
					src_img_mem_raddr[clogb2(BUF_MEM_DEPTH-1)+clogb2(STREAM_WIDTH/8):clogb2(STREAM_WIDTH/8)];
			assign ping_pong_ram_din[ping_pong_ram_i] = s_axis_data;
			
			if(USE_DUAL_PORT_RAM == "true")
			begin
				bram_simple_dual_port #(
					.style("LOW_LATENCY"),
					.mem_width(STREAM_WIDTH),
					.mem_depth(BUF_MEM_DEPTH),
					.INIT_FILE("no_init"),
					.simulation_delay(SIM_DELAY)
				)ping_pong_ram_u(
					.clk(clk),
					
					.wen_a(on_src_img_mem_wen[ping_pong_ram_i]),
					.addr_a(src_img_mem_waddr),
					.din_a(ping_pong_ram_din[ping_pong_ram_i]),
					
					.ren_b(on_src_img_mem_ren[ping_pong_ram_i]),
					.addr_b(src_img_mem_raddr[clogb2(BUF_MEM_DEPTH-1)+clogb2(STREAM_WIDTH/8):clogb2(STREAM_WIDTH/8)]),
					.dout_b(ping_pong_ram_dout[ping_pong_ram_i])
				);
			end
			else
			begin
				bram_single_port #(
					.style("LOW_LATENCY"),
					.rw_mode("no_change"),
					.mem_width(STREAM_WIDTH),
					.mem_depth(BUF_MEM_DEPTH),
					.INIT_FILE("no_init"),
					.byte_write_mode("false"),
					.simulation_delay(SIM_DELAY)
				)ping_pong_ram_u(
					.clk(clk),
					
					.en(ping_pong_ram_en[ping_pong_ram_i]),
					.wen(ping_pong_ram_wen[ping_pong_ram_i]),
					.addr(ping_pong_ram_addr[ping_pong_ram_i]),
					.din(ping_pong_ram_din[ping_pong_ram_i]),
					.dout(ping_pong_ram_dout[ping_pong_ram_i])
				);
			end
		end
	endgenerate
	
endmodule
