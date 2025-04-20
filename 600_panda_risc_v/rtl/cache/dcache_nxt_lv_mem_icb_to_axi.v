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
本模块: 数据Cache下级存储器访问ICB到AXI转换

描述:
将访问下级存储器ICB从机转换成突发长度为CACHE_LINE_WORD_N的AXI主机

注意：
无

协议:
ICB SLAVE
AXI MASTER

作者: 陈家耀
日期: 2025/04/16
********************************************************************/


module dcache_nxt_lv_mem_icb_to_axi #(
	parameter integer CACHE_LINE_WORD_N = 8, // 每个缓存行的字数(1 | 2 | 4 | 8 | 16)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 访问下级存储器ICB从机
	// 命令通道
	input wire[31:0] s_icb_cmd_addr,
	input wire s_icb_cmd_read,
	input wire[31:0] s_icb_cmd_wdata,
	input wire[3:0] s_icb_cmd_wmask,
	input wire s_icb_cmd_valid,
	output wire s_icb_cmd_ready,
	// 响应通道
	output wire[31:0] s_icb_rsp_rdata,
	output wire s_icb_rsp_err,
	output wire s_icb_rsp_valid,
	input wire s_icb_rsp_ready,
	
	// 访问下级存储器AXI主机
	// AR通道
	output wire[31:0] m_axi_araddr,
	output wire[1:0] m_axi_arburst, // const -> 2'b01
	output wire[7:0] m_axi_arlen, // const -> CACHE_LINE_WORD_N - 1
	output wire[2:0] m_axi_arsize, // const -> 3'b010
	output wire m_axi_arvalid,
	input wire m_axi_arready,
	// R通道
	input wire[31:0] m_axi_rdata,
	// 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
	input wire[1:0] m_axi_rresp,
	input wire m_axi_rlast, // ignored
	input wire m_axi_rvalid,
	output wire m_axi_rready,
	// AW通道
	output wire[31:0] m_axi_awaddr,
	output wire[1:0] m_axi_awburst, // const -> 2'b01
	output wire[7:0] m_axi_awlen, // const -> CACHE_LINE_WORD_N - 1
	output wire[2:0] m_axi_awsize, // const -> 3'b010
	output wire m_axi_awvalid,
	input wire m_axi_awready,
	// B通道
	// 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
	input wire[1:0] m_axi_bresp,
	input wire m_axi_bvalid,
	output wire m_axi_bready,
	// W通道
	output wire[31:0] m_axi_wdata,
	output wire[3:0] m_axi_wstrb,
	output wire m_axi_wlast,
	output wire m_axi_wvalid,
	input wire m_axi_wready
);
	
	reg[CACHE_LINE_WORD_N-1:0] icb_cmd_word_ofs; // ICB命令通道字偏移码
	reg[CACHE_LINE_WORD_N-1:0] icb_rsp_word_ofs; // ICB响应通道字偏移码
	reg[CACHE_LINE_WORD_N-1:0] axi_w_word_ofs; // AXI写数据通道字偏移码
	reg[1:0] bresp_lacthed; // 锁存的写响应错误码
	// [写数据fifo端口]
	wire wdata_fifo_wen;
	wire wdata_fifo_full_n;
	wire[35:0] wdata_fifo_din; // {写数据(32位), 写字节掩码(4位)}
	wire wdata_fifo_ren;
	wire wdata_fifo_empty_n;
	wire[35:0] wdata_fifo_dout; // {写数据(32位), 写字节掩码(4位)}
	// [突发信息fifo端口]
	wire burst_msg_fifo_wen;
	wire burst_msg_fifo_full_n;
	wire burst_msg_fifo_din; // {是否读突发(1位)}
	wire burst_msg_fifo_ren;
	wire burst_msg_fifo_empty_n;
	wire burst_msg_fifo_dout; // {是否读突发(1位)}
	// [写突发首地址缓存区]
	reg[31:0] wburst_baseaddr_buf_regs[0:3]; // 缓存寄存器组
	reg wburst_baseaddr_buf_wen_d1; // 延迟1clk的写使能
	reg[1:0] wburst_baseaddr_buf_wptr; // 写指针
	reg[1:0] wburst_baseaddr_buf_rptr; // 读指针
	reg[2:0] wburst_allowed_n; // 允许启动的写突发个数
	
	assign s_icb_cmd_ready = 
		s_icb_cmd_read ? (
			(~icb_cmd_word_ofs[0]) | (burst_msg_fifo_full_n & m_axi_arready)
		):(
			((~icb_cmd_word_ofs[0]) | burst_msg_fifo_full_n) & wdata_fifo_full_n
		);
	
	assign s_icb_rsp_rdata = 
		burst_msg_fifo_dout ? 
			m_axi_rdata:
			32'dx;
	assign s_icb_rsp_err = 
		burst_msg_fifo_dout ? 
			(m_axi_rresp != 2'b00):
			((icb_rsp_word_ofs[0] ? m_axi_bresp:bresp_lacthed) != 2'b00);
	assign s_icb_rsp_valid = 
		burst_msg_fifo_empty_n & (
			burst_msg_fifo_dout ? 
				m_axi_rvalid:
				((~icb_rsp_word_ofs[0]) | m_axi_bvalid)
		);
	
	assign m_axi_araddr = s_icb_cmd_addr;
	assign m_axi_arburst = 2'b01;
	assign m_axi_arlen = CACHE_LINE_WORD_N - 1;
	assign m_axi_arsize = 3'b010;
	assign m_axi_arvalid = 
		s_icb_cmd_valid & s_icb_cmd_read & 
		icb_cmd_word_ofs[0] & 
		burst_msg_fifo_full_n;
	
	assign m_axi_rready = burst_msg_fifo_empty_n & burst_msg_fifo_dout & s_icb_rsp_ready;
	
	assign m_axi_awaddr = wburst_baseaddr_buf_regs[wburst_baseaddr_buf_rptr];
	assign m_axi_awburst = 2'b01;
	assign m_axi_awlen = CACHE_LINE_WORD_N - 1;
	assign m_axi_awsize = 3'b010;
	assign m_axi_awvalid = wburst_allowed_n != 3'b000;
	
	assign m_axi_bready = burst_msg_fifo_empty_n & (~burst_msg_fifo_dout) & icb_rsp_word_ofs[0] & s_icb_rsp_ready;
	
	assign m_axi_wdata = wdata_fifo_dout[35:4];
	assign m_axi_wstrb = wdata_fifo_dout[3:0];
	assign m_axi_wlast = axi_w_word_ofs[CACHE_LINE_WORD_N-1];
	assign m_axi_wvalid = wdata_fifo_empty_n;
	
	assign wdata_fifo_wen = s_icb_cmd_valid & s_icb_cmd_ready & (~s_icb_cmd_read);
	assign wdata_fifo_din = {s_icb_cmd_wdata, s_icb_cmd_wmask};
	assign wdata_fifo_ren = m_axi_wready;
	
	assign burst_msg_fifo_wen = s_icb_cmd_valid & s_icb_cmd_ready & icb_cmd_word_ofs[0];
	assign burst_msg_fifo_din = s_icb_cmd_read;
	assign burst_msg_fifo_ren = 
		burst_msg_fifo_dout ? 
			(m_axi_rvalid & s_icb_rsp_ready & icb_rsp_word_ofs[CACHE_LINE_WORD_N-1]):
			(s_icb_rsp_ready & icb_rsp_word_ofs[CACHE_LINE_WORD_N-1] & ((CACHE_LINE_WORD_N > 1) | m_axi_bvalid));
	
	// ICB命令通道字偏移码
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			icb_cmd_word_ofs <= 1;
		else if(s_icb_cmd_valid & s_icb_cmd_ready)
			// 循环左移1位
			icb_cmd_word_ofs <= # SIM_DELAY (icb_cmd_word_ofs << 1) | (icb_cmd_word_ofs >> (CACHE_LINE_WORD_N-1));
	end
	// ICB响应通道字偏移码
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			icb_rsp_word_ofs <= 1;
		else if(s_icb_rsp_valid & s_icb_rsp_ready)
			// 循环左移1位
			icb_rsp_word_ofs <= # SIM_DELAY (icb_rsp_word_ofs << 1) | (icb_rsp_word_ofs >> (CACHE_LINE_WORD_N-1));
	end
	// AXI写数据通道字偏移码
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			axi_w_word_ofs <= 1;
		else if(m_axi_wvalid & m_axi_wready)
			// 循环左移1位
			axi_w_word_ofs <= # SIM_DELAY (axi_w_word_ofs << 1) | (axi_w_word_ofs >> (CACHE_LINE_WORD_N-1));
	end
	
	// 锁存的写响应错误码
	always @(posedge aclk)
	begin
		if(m_axi_bvalid & m_axi_bready)
			bresp_lacthed <= # SIM_DELAY m_axi_bresp;
	end
	
	// 写突发首地址缓存区寄存器组
	genvar wburst_baseaddr_buf_regs_i;
	generate
		for(wburst_baseaddr_buf_regs_i = 0;wburst_baseaddr_buf_regs_i < 4;wburst_baseaddr_buf_regs_i = wburst_baseaddr_buf_regs_i + 1)
		begin:wburst_baseaddr_buf_regs_blk
			always @(posedge aclk)
			begin
				if(s_icb_cmd_valid & s_icb_cmd_ready & (~s_icb_cmd_read) & icb_cmd_word_ofs[0] & 
					(wburst_baseaddr_buf_wptr == wburst_baseaddr_buf_regs_i))
					wburst_baseaddr_buf_regs[wburst_baseaddr_buf_regs_i] <= # SIM_DELAY s_icb_cmd_addr;
			end
		end
	endgenerate
	// 延迟1clk的写使能
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wburst_baseaddr_buf_wen_d1 <= 1'b0;
		else
			wburst_baseaddr_buf_wen_d1 <= # SIM_DELAY 
				s_icb_cmd_valid & s_icb_cmd_ready & (~s_icb_cmd_read) & icb_cmd_word_ofs[CACHE_LINE_WORD_N-1];
	end
	// 写突发首地址缓存区写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wburst_baseaddr_buf_wptr <= 2'b00;
		else if(wburst_baseaddr_buf_wen_d1)
			wburst_baseaddr_buf_wptr <= # SIM_DELAY wburst_baseaddr_buf_wptr + 2'b01;
	end
	// 写突发首地址缓存区读指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wburst_baseaddr_buf_rptr <= 2'b00;
		else if(m_axi_awvalid & m_axi_awready)
			wburst_baseaddr_buf_rptr <= # SIM_DELAY wburst_baseaddr_buf_rptr + 2'b01;
	end
	// 允许启动的写突发个数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wburst_allowed_n <= 3'b000;
		else if(
			wburst_baseaddr_buf_wen_d1 ^ 
			(m_axi_awvalid & m_axi_awready)
		)
			wburst_allowed_n <= # SIM_DELAY 
				wburst_allowed_n + {{2{~wburst_baseaddr_buf_wen_d1}}, 1'b1};
	end
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(4),
		.fifo_data_width(1),
		.almost_full_th(2),
		.almost_empty_th(2),
		.simulation_delay(SIM_DELAY)
	)burst_msg_fifo_u(
		.clk(aclk),
		.rst_n(aresetn),
		
		.fifo_wen(burst_msg_fifo_wen),
		.fifo_din(burst_msg_fifo_din),
		.fifo_full_n(burst_msg_fifo_full_n),
		
		.fifo_ren(burst_msg_fifo_ren),
		.fifo_dout(burst_msg_fifo_dout),
		.fifo_empty_n(burst_msg_fifo_empty_n)
	);
	
	ram_fifo_wrapper #(
		.fwft_mode("true"),
		.ram_type("bram"),
		.en_bram_reg("false"),
		.fifo_depth(512),
		.fifo_data_width(36),
		.full_assert_polarity("low"),
		.empty_assert_polarity("low"),
		.almost_full_assert_polarity("no"),
		.almost_empty_assert_polarity("no"),
		.en_data_cnt("false"),
		.almost_full_th(256),
		.almost_empty_th(256),
		.simulation_delay(SIM_DELAY)
	)wdata_fifo_u(
		.clk(aclk),
		.rst_n(aresetn),
		
		.fifo_wen(wdata_fifo_wen),
		.fifo_din(wdata_fifo_din),
		.fifo_full_n(wdata_fifo_full_n),
		
		.fifo_ren(wdata_fifo_ren),
		.fifo_dout(wdata_fifo_dout),
		.fifo_empty_n(wdata_fifo_empty_n)
	);
	
endmodule
