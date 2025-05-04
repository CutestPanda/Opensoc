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
本模块: 帧缓存的寄存器配置接口

描述:
寄存器->
    偏移量  |    含义                        |   读写特性    |        备注
     0x00    0:使能帧缓存                          W1RZ
	         1:当前帧已处理                        W1TRL
	 0x04    31~0:帧缓存区基地址                    RW
	 0x08    2~0:帧缓存区最大存储帧数 - 1           RW
	           8:是否允许帧的后处理                 RW
	 0x0C      0:全局中断使能                       RW
	           8:帧写入中断使能                     RW
			   9:帧读取中断使能                     RW
	 0x10      0:帧写入中断等待                    RW1C
	           1:帧读取中断等待                    RW1C

注意：
无

协议:
APB SLAVE

作者: 陈家耀
日期: 2025/02/20
********************************************************************/


module reg_if_for_frame_buffer #(
	parameter real SIM_DELAY = 1 // 仿真延时
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
	
	// 使能信号
	output wire en_frame_buffer,
	
	// 运行时参数
	output wire[31:0] frame_buffer_baseaddr, // 帧缓存区基地址
	output wire[2:0] frame_buffer_max_store_n_sub1, // 帧缓存区最大存储帧数 - 1
	output wire en_frame_pos_proc, // 是否允许帧的后处理
	
	// 帧处理控制
	output wire frame_processed, // 当前帧已处理标志(注意: 取上升沿!)
	input wire frame_filled, // 当前帧已填充标志(注意: 取上升沿!)
	input wire frame_fetched, // 当前帧已取走标志(注意: 取上升沿!)
	
	// 中断请求
	output wire frame_wt_itr_req, // 帧写入中断请求
	output wire frame_rd_itr_req // 帧读取中断请求
);
	
	/** 中断处理 **/
	reg frame_filled_d; // 延迟1clk的当前帧已填充标志
	reg frame_fetched_d; // 延迟1clk的当前帧已取走标志
	wire on_frame_filled; // 当前帧已填充指示
	wire on_frame_fetched; // 当前帧已取走指示
	reg global_itr_en_r; // 全局中断使能
	reg frame_wt_itr_en_r; // 帧写入中断使能
	reg frame_rd_itr_en_r; // 帧读取中断使能
	reg frame_wt_itr_pending; // 帧写入中断等待
	reg frame_rd_itr_pending; // 帧读取中断等待
	reg frame_wt_itr_req_r; // 帧写入中断请求
	reg frame_rd_itr_req_r; // 帧读取中断请求
	
	assign frame_wt_itr_req = frame_wt_itr_req_r;
	assign frame_rd_itr_req = frame_rd_itr_req_r;
	
	assign on_frame_filled = frame_filled & (~frame_filled_d);
	assign on_frame_fetched = frame_fetched & (~frame_fetched_d);
	
	// 延迟1clk的当前帧已填充标志, 延迟1clk的当前帧已取走标志
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			{frame_fetched_d, frame_filled_d} <= 2'b00;
		else
			{frame_fetched_d, frame_filled_d} <= # SIM_DELAY {frame_fetched, frame_filled};
	end
	
	// 帧写入中断等待
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			frame_wt_itr_pending <= 1'b0;
		else if((psel & penable & pwrite & (paddr[4:2] == 3'd4) & pwdata[0]) | on_frame_filled)
			frame_wt_itr_pending <= # SIM_DELAY on_frame_filled | (~(psel & penable & pwrite & (paddr[4:2] == 3'd4) & pwdata[0]));
	end
	// 帧读取中断等待
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			frame_rd_itr_pending <= 1'b0;
		else if((psel & penable & pwrite & (paddr[4:2] == 3'd4) & pwdata[1]) | on_frame_fetched)
			frame_rd_itr_pending <= # SIM_DELAY on_frame_fetched | (~(psel & penable & pwrite & (paddr[4:2] == 3'd4) & pwdata[1]));
	end
	
	// 帧写入中断请求
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			frame_wt_itr_req_r <= 1'b0;
		else
			frame_wt_itr_req_r <= # SIM_DELAY global_itr_en_r & frame_wt_itr_en_r & on_frame_filled;
	end
	// 帧读取中断请求
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			frame_rd_itr_req_r <= 1'b0;
		else
			frame_rd_itr_req_r <= # SIM_DELAY global_itr_en_r & frame_rd_itr_en_r & on_frame_fetched;
	end
	
	/** 配置寄存器区 **/
    reg[31:0] prdata_out_r; // APB从机读数据
	reg en_frame_buffer_r; // 使能帧缓存
	reg frame_processed_r; // 当前帧已处理标志
	reg[31:0] frame_buffer_baseaddr_r; // 帧缓存区基地址
	reg[2:0] frame_buffer_max_store_n_sub1_r; // 帧缓存区最大存储帧数 - 1
	reg en_frame_pos_proc_r; // 是否允许帧的后处理
	
	assign pready_out = 1'b1;
	assign prdata_out = prdata_out_r;
	assign pslverr_out = 1'b0;
	
	assign en_frame_buffer = en_frame_buffer_r;
	assign frame_buffer_baseaddr = frame_buffer_baseaddr_r;
	assign frame_buffer_max_store_n_sub1 = frame_buffer_max_store_n_sub1_r;
	assign en_frame_pos_proc = en_frame_pos_proc_r;
	
	assign frame_processed = frame_processed_r;
	
	// APB从机读数据
	always @(posedge clk)
	begin
		if(psel)
		begin
			case(paddr[4:2])
				3'd0: prdata_out_r <= # SIM_DELAY {30'd0, frame_processed_r, 1'b0};
				3'd1: prdata_out_r <= # SIM_DELAY frame_buffer_baseaddr_r;
				3'd2: prdata_out_r <= # SIM_DELAY {16'd0, 7'd0, en_frame_pos_proc_r, 5'd0, frame_buffer_max_store_n_sub1_r};
				3'd3: prdata_out_r <= # SIM_DELAY {16'd0, 6'd0, frame_rd_itr_en_r, frame_wt_itr_en_r, 7'd0, global_itr_en_r};
				3'd4: prdata_out_r <= # SIM_DELAY {30'd0, frame_rd_itr_pending, frame_wt_itr_pending};
				default: prdata_out_r <= # SIM_DELAY 32'd0;
			endcase
		end
	end
	
	// 使能帧缓存
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			en_frame_buffer_r <= 1'b0;
		else if(psel & penable & pwrite & (paddr[4:2] == 3'd0) & pwdata[0])
			en_frame_buffer_r <= # SIM_DELAY 1'b1;
	end
	
	// 当前帧已处理标志
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			frame_processed_r <= 1'b0;
		else if(psel & penable & pwrite & (paddr[4:2] == 3'd0) & pwdata[1])
			frame_processed_r <= # SIM_DELAY ~frame_processed_r;
	end
	
	// 帧缓存区基地址
	always @(posedge clk)
	begin
		if(psel & penable & pwrite & (paddr[4:2] == 3'd1))
			frame_buffer_baseaddr_r <= # SIM_DELAY pwdata;
	end
	
	// 帧缓存区最大存储帧数 - 1
	always @(posedge clk)
	begin
		if(psel & penable & pwrite & (paddr[4:2] == 3'd2))
			frame_buffer_max_store_n_sub1_r <= # SIM_DELAY pwdata[2:0];
	end
	
	// 是否允许帧的后处理
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			en_frame_pos_proc_r <= 1'b0;
		else if(psel & penable & pwrite & (paddr[4:2] == 3'd2))
			en_frame_pos_proc_r <= # SIM_DELAY pwdata[8];
	end
	
	// 全局中断使能, 帧写入中断使能, 帧读取中断使能
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			{frame_rd_itr_en_r, frame_wt_itr_en_r, global_itr_en_r} <= 3'b000;
		else if(psel & penable & pwrite & (paddr[4:2] == 3'd3))
			{frame_rd_itr_en_r, frame_wt_itr_en_r, global_itr_en_r} <= # SIM_DELAY {pwdata[9], pwdata[8], pwdata[0]};
	end
	
endmodule
