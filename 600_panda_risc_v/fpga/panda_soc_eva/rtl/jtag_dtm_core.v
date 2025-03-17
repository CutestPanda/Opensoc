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
本模块: 调试传输控制模块(核心)

描述:
实现JTAG接口到如下DTM寄存器的访问: 
	地址 | 名称
---------------------
    0x01 | IDCODE
	0x10 | DTMCS
	0x11 |  DMI
	其余 | BYPASS

DMI采用APB协议

注意：
无

协议:
JTAG SLAVE
APB MASTER

作者: 陈家耀
日期: 2025/02/05
********************************************************************/


module jtag_dtm_core #(
	parameter JTAG_VERSION  = 4'h1, // IDCODE寄存器下Version域的值
	parameter DTMCS_IDLE_HINT = 3'd5, // 停留在Run-Test/Idle状态的周期数
	parameter integer ABITS = 7, // DMI地址位宽(必须在范围[7, 32]内)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// JTAG从机
	input wire tck,
	input wire trst_n,
	input wire tms,
	input wire tdi,
	output wire tdo,
	output wire tdo_oen,
	
	// DMI强制复位请求
	output wire dmihardreset_req,
	
	// APB主机
    output wire[ABITS+1:0] m_paddr,
    output wire m_psel,
    output wire m_penable,
    output wire m_pwrite,
    output wire[31:0] m_pwdata,
    input wire m_pready,
    input wire[31:0] m_prdata,
    input wire m_pslverr
);
	
	/** 常量 **/
	// DTM版本
	localparam DEBUG_VERSION = 4'd1;
	// JTAG状态常量
	localparam S_RESET = 4'd0;
	localparam S_RUN_IDLE = 4'd1;
	localparam S_SELECT_DR = 4'd2;
	localparam S_CAPTURE_DR = 4'd3;
	localparam S_SHIFT_DR = 4'd4;
	localparam S_EXIT1_DR = 4'd5;
	localparam S_PAUSE_DR = 4'd6;
	localparam S_EXIT2_DR = 4'd7;
	localparam S_UPDATE_DR = 4'd8;
	localparam S_SELECT_IR = 4'd9;
	localparam S_CAPTURE_IR = 4'd10;
	localparam S_SHIFT_IR = 4'd11;
	localparam S_EXIT1_IR = 4'd12;
	localparam S_PAUSE_IR = 4'd13;
	localparam S_EXIT2_IR = 4'd14;
	localparam S_UPDATE_IR = 4'd15;
	// 指令/数据寄存器位宽
	localparam integer W_IR = 5;
	localparam integer W_DR_SHIFT = ABITS + 32 + 2;
	// DTM寄存器地址
	localparam IR_IDCODE = 5'h01;
	localparam IR_DTMCS = 5'h10;
	localparam IR_DMI = 5'h11;
	// DMI传输状态常量
	localparam integer DMI_STS_ONEHOT_IDEL = 0;
	localparam integer DMI_STS_ONEHOT_PSEL = 1;
	localparam integer DMI_STS_ONEHOT_PENABLE = 2;
	// DMI操作类型
	localparam DMI_OP_NOP = 2'b00;
	localparam DMI_OP_READ = 2'b01;
	localparam DMI_OP_WRITE = 2'b10;
	localparam DMI_OP_RSV = 2'b11;
	// DMI响应类型
	localparam DMI_RESP_SUCCESS = 2'b00;
	localparam DMI_RESP_RSV = 2'b01;
	localparam DMI_RESP_FAILED = 2'b10;
	localparam DMI_RESP_BUSY = 2'b11;
	
	/** JTAG状态机 **/
	reg[3:0] tap_state; // JTAG当前状态
	
	// JTAG当前状态
	always @(posedge tck or negedge trst_n)
	begin
		if(~trst_n)
			tap_state <= S_RESET;
		else
		begin
			case(tap_state)
				S_RESET: tap_state <= # SIM_DELAY tms ? S_RESET:S_RUN_IDLE;
				S_RUN_IDLE: tap_state <= # SIM_DELAY tms ? S_SELECT_DR:S_RUN_IDLE;
				
				S_SELECT_DR: tap_state <= # SIM_DELAY tms ? S_SELECT_IR:S_CAPTURE_DR;
				S_CAPTURE_DR: tap_state <= # SIM_DELAY tms ? S_EXIT1_DR:S_SHIFT_DR;
				S_SHIFT_DR: tap_state <= # SIM_DELAY tms ? S_EXIT1_DR:S_SHIFT_DR;
				S_EXIT1_DR: tap_state <= # SIM_DELAY tms ? S_UPDATE_DR:S_PAUSE_DR;
				S_PAUSE_DR: tap_state <= # SIM_DELAY tms ? S_EXIT2_DR:S_PAUSE_DR;
				S_EXIT2_DR: tap_state <= # SIM_DELAY tms ? S_UPDATE_DR:S_SHIFT_DR;
				S_UPDATE_DR: tap_state <= # SIM_DELAY tms ? S_SELECT_DR:S_RUN_IDLE;
				
				S_SELECT_IR: tap_state <= # SIM_DELAY tms ? S_RESET:S_CAPTURE_IR;
				S_CAPTURE_IR: tap_state <= # SIM_DELAY tms ? S_EXIT1_IR:S_SHIFT_IR;
				S_SHIFT_IR: tap_state <= # SIM_DELAY tms ? S_EXIT1_IR:S_SHIFT_IR;
				S_EXIT1_IR: tap_state <= # SIM_DELAY tms ? S_UPDATE_IR:S_PAUSE_IR;
				S_PAUSE_IR: tap_state <= # SIM_DELAY tms ? S_EXIT2_IR:S_PAUSE_IR;
				S_EXIT2_IR: tap_state <= # SIM_DELAY tms ? S_UPDATE_IR:S_SHIFT_IR;
				S_UPDATE_IR: tap_state <= # SIM_DELAY tms ? S_SELECT_DR:S_RUN_IDLE;
			endcase
		end
	end
	
	/** DTM寄存器 **/
	wire[31:0] idcode_r; // IDCODE寄存器
	wire[31:0] dtmcs_r; // DTMCS寄存器
	wire[W_DR_SHIFT-1:0] dmi_r; // DMI寄存器
	reg[1:0] dmi_cmderr; // DMI寄存器的op域
	
	assign idcode_r = {
		JTAG_VERSION[3:0], // Version
		16'he200, // PartNumber
		11'h536, // ManufId
		1'b1 // Always 1'b1
	};
	assign dtmcs_r = {
		11'h000, // Always 11'h000
		3'b000, // errinfo
		1'b0, // dtmhardreset
		1'b0, // dmireset
		1'b0, // Always 1'b0
		DTMCS_IDLE_HINT[2:0], // idle
		dmi_cmderr, // dmistat
		ABITS[5:0], // abits
		DEBUG_VERSION[3:0] // version
	};
	
	/** 指令/数据寄存器 **/
	reg[W_DR_SHIFT-1:0] shift_r; // JTAG移位寄存器
	reg[W_IR-1:0] ir; // JTAG指令寄存器(IR)
	
	// JTAG移位寄存器
	always @(posedge tck)
	begin
		case(tap_state)
			S_CAPTURE_IR:
				shift_r <= # SIM_DELAY {{(W_DR_SHIFT-W_IR){1'b0}}, ir};
			S_SHIFT_IR:
				shift_r <= # SIM_DELAY {{(W_DR_SHIFT-W_IR){1'b0}}, tdi, shift_r[W_IR-1:1]};
			S_CAPTURE_DR:
				case(ir)
					IR_IDCODE:
						shift_r <= # SIM_DELAY {{(W_DR_SHIFT-32){1'b0}}, idcode_r};
					IR_DTMCS:
						shift_r <= # SIM_DELAY {{(W_DR_SHIFT-32){1'b0}}, dtmcs_r};
					IR_DMI:
						shift_r <= # SIM_DELAY dmi_r;
					default: // BYPASS
						shift_r <= # SIM_DELAY {W_DR_SHIFT{1'b0}};
				endcase
			S_SHIFT_DR:
				case(ir)
					IR_IDCODE, IR_DTMCS:
						shift_r <= # SIM_DELAY {{(W_DR_SHIFT-32){1'b0}}, tdi, shift_r[31:1]};
					IR_DMI:
						shift_r <= # SIM_DELAY {tdi, shift_r[W_DR_SHIFT-1:1]};
					default: // BYPASS
						shift_r <= # SIM_DELAY {{(W_DR_SHIFT-1){1'b0}}, tdi};
				endcase
		endcase
	end
	
	// JTAG指令寄存器(IR)
	always @(posedge tck or negedge trst_n)
	begin
		if(~trst_n)
			ir <= IR_IDCODE;
		else if((tap_state == S_RESET) | (tap_state == S_UPDATE_IR))
			ir <= # SIM_DELAY (tap_state == S_RESET) ? IR_IDCODE:shift_r[W_IR-1:0];
	end
	
	/** DMI传输 **/
	// DMI传输控制/状态
	wire dmi_start_trans; // DMI启动传输(指示)
	reg[2:0] dmi_sts; // DMI传输状态
	wire dmi_busy; // DMI忙碌(标志)
	// 锁存的传输信息
	reg[ABITS+1:0] paddr_latched;
	reg pwrite_latched;
	reg[31:0] pwdata_latched;
	// 锁存的读数据
	reg[31:0] prdata_latched;
	
	assign m_paddr = {paddr_latched[ABITS+1:2], 2'b00};
	assign m_psel = ~dmi_sts[DMI_STS_ONEHOT_IDEL];
	assign m_penable = dmi_sts[DMI_STS_ONEHOT_PENABLE];
	assign m_pwrite = pwrite_latched;
	assign m_pwdata = pwdata_latched;
	
	assign dmi_r = {
		paddr_latched[ABITS+1:2], // address
		prdata_latched, // data
		(dmi_busy & (dmi_cmderr == DMI_RESP_SUCCESS)) ? DMI_RESP_BUSY:dmi_cmderr // op
	};
	
	assign dmi_start_trans = (tap_state == S_UPDATE_DR) & (ir == IR_DMI) & 
		((shift_r[1:0] == DMI_OP_READ) | (shift_r[1:0] == DMI_OP_WRITE)) & 
		(dmi_cmderr == DMI_RESP_SUCCESS);
	assign dmi_busy = ~dmi_sts[DMI_STS_ONEHOT_IDEL];
	
	// DMI寄存器的op域
	always @(posedge tck or negedge trst_n)
	begin
		if(~trst_n)
			dmi_cmderr <= DMI_RESP_SUCCESS;
		else if(
			((tap_state == S_UPDATE_DR) & (
				((ir == IR_DTMCS) & shift_r[16]) | // 向dtmcs寄存器的dmireset域写1, 复位op域
				((ir == IR_DMI) & dmi_busy & (shift_r[1:0] != DMI_OP_NOP) & (dmi_cmderr == DMI_RESP_SUCCESS)) // 写dmi寄存器时DMI忙碌
			)) | 
			// 读dmi寄存器时DMI忙碌
			((tap_state == S_CAPTURE_DR) & (ir == IR_DMI) & dmi_busy & (dmi_cmderr == DMI_RESP_SUCCESS)) | 
			// APB主机返回错误响应
			(dmi_sts[DMI_STS_ONEHOT_PENABLE] & m_pready & m_pslverr & (dmi_cmderr == DMI_RESP_SUCCESS))
		)
		begin
			if(tap_state == S_UPDATE_DR)
				dmi_cmderr <= # SIM_DELAY (ir == IR_DTMCS) ? DMI_RESP_SUCCESS:DMI_RESP_BUSY;
			else if(tap_state == S_CAPTURE_DR)
				dmi_cmderr <= # SIM_DELAY DMI_RESP_BUSY;
			else
				dmi_cmderr <= # SIM_DELAY DMI_RESP_FAILED;
		end
	end
	
	// DMI传输状态
	always @(posedge tck or negedge trst_n)
	begin
		if(~trst_n)
			dmi_sts <= (3'b001 << DMI_STS_ONEHOT_IDEL);
		else if(
			(dmi_sts[DMI_STS_ONEHOT_IDEL] & dmi_start_trans) | 
			dmi_sts[DMI_STS_ONEHOT_PSEL] | 
			(dmi_sts[DMI_STS_ONEHOT_PENABLE] & m_pready)
		)
			dmi_sts <= # SIM_DELAY 
				({3{dmi_sts[DMI_STS_ONEHOT_IDEL]}} & (3'b001 << DMI_STS_ONEHOT_PSEL)) | 
				({3{dmi_sts[DMI_STS_ONEHOT_PSEL]}} & (3'b001 << DMI_STS_ONEHOT_PENABLE)) | 
				({3{dmi_sts[DMI_STS_ONEHOT_PENABLE]}} & (3'b001 << DMI_STS_ONEHOT_IDEL));
	end
	
	// 锁存的传输信息
	always @(posedge tck)
	begin
		if(dmi_start_trans & (~dmi_busy))
			{paddr_latched, pwrite_latched, pwdata_latched} <= # SIM_DELAY {
				{shift_r[W_DR_SHIFT-1:34], 2'b00}, // paddr
				shift_r[1:0] == DMI_OP_WRITE, // pwrite
				shift_r[33:2] // pwdata
			};
	end
	
	// 锁存的读数据
	always @(posedge tck)
	begin
		if(dmi_sts[DMI_STS_ONEHOT_PENABLE] & m_pready)
			prdata_latched <= # SIM_DELAY m_prdata;
	end
	
	/** DMI强制复位请求 **/
	reg dmihardreset_req_r;
	
	assign dmihardreset_req = dmihardreset_req_r;
	
	// DMI强制复位请求
	always @(posedge tck or negedge trst_n)
	begin
		if(~trst_n)
			dmihardreset_req_r <= 1'b0;
		else
			dmihardreset_req_r <= # SIM_DELAY (tap_state == S_UPDATE_DR) & (ir == IR_DTMCS) & shift_r[17];
	end
	
	/** JTAG输出寄存器 **/
	reg tdo_r;
	reg tdo_oen_r;
	
	assign tdo = tdo_r;
	assign tdo_oen = tdo_oen_r;
	
	// JTAG数据输出
	// 注意: tdo在tck下降沿时变化!
	always @(negedge tck or negedge trst_n)
	begin
		if(~trst_n)
			tdo_r <= 1'b0;
		else
			// ((tap_state == S_SHIFT_IR) | (tap_state == S_SHIFT_DR)) ? shift_r[0]:1'b0
			tdo_r <= # SIM_DELAY ((tap_state == S_SHIFT_IR) | (tap_state == S_SHIFT_DR)) & shift_r[0];
	end
	
	// JTAG数据输出使能
	// 注意: tdo_oen在tck下降沿时变化!
	always @(negedge tck or negedge trst_n)
	begin
		if(~trst_n)
			tdo_oen_r <= 1'b0;
		else
			tdo_oen_r <= # SIM_DELAY (tap_state == S_SHIFT_IR) | (tap_state == S_SHIFT_DR);
	end
	
endmodule
