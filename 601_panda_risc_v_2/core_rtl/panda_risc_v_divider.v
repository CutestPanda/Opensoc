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
本模块: 多周期除法器

描述:
基于不恢复余数法的33位有符号除法器

包含深度为2的除法器输入缓存区

周期数 = 输入缓存区(1cycle) + 计算(20cycle) + 除法结果输出寄存器(1cycle)

注意：
无

协议:
无

作者: 陈家耀
日期: 2026/02/02
********************************************************************/


module panda_risc_v_divider #(
	parameter integer inst_id_width = 4, // 指令编号的位宽
    parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// 除法器执行请求
	input wire[32:0] s_div_req_op_a, // 操作数A(被除数)
	input wire[32:0] s_div_req_op_b, // 操作数B(除数)
	input wire s_div_req_rem_sel, // 除法/求余选择(1'b0 -> 除法, 1'b1 -> 求余)
	input wire[4:0] s_div_req_rd_id, // RD索引
	input wire[inst_id_width-1:0] s_div_req_inst_id, // 指令编号
	input wire s_div_req_valid,
	output wire s_div_req_ready,
	
	// 除法器计算结果
	output wire[31:0] m_div_res_data, // 计算结果
	output wire[4:0] m_div_res_rd_id, // RD索引
	output wire[inst_id_width-1:0] m_div_res_inst_id, // 指令编号
	output wire m_div_res_valid,
	input wire m_div_res_ready
);
	
	/** 常量 **/
	// 除法器输入信息各项的起始索引
	localparam integer DIV_IN_MSG_REM_SEL = 0;
	localparam integer DIV_IN_MSG_OP_A = 1;
	localparam integer DIV_IN_MSG_OP_B = 34;
	localparam integer DIV_IN_MSG_RD_ID = 67;
	localparam integer DIV_IN_MSG_INST_ID = 72;
	
    /** 除法器输入缓存区 **/
	// 缓存区写端口
	wire div_in_buf_wen;
	wire[72+inst_id_width-1:0] div_in_buf_din;
	wire div_in_buf_full_n;
	// 缓存区读端口
	wire div_in_buf_ren;
	wire[72+inst_id_width-1:0] div_in_buf_dout;
	wire div_in_buf_empty_n;
	
	assign div_in_buf_wen = s_div_req_valid;
	assign div_in_buf_din[DIV_IN_MSG_REM_SEL] = s_div_req_rem_sel;
	assign div_in_buf_din[DIV_IN_MSG_OP_A+32:DIV_IN_MSG_OP_A] = s_div_req_op_a;
	assign div_in_buf_din[DIV_IN_MSG_OP_B+32:DIV_IN_MSG_OP_B] = s_div_req_op_b;
	assign div_in_buf_din[DIV_IN_MSG_RD_ID+4:DIV_IN_MSG_RD_ID] = s_div_req_rd_id;
	assign div_in_buf_din[DIV_IN_MSG_INST_ID+inst_id_width-1:DIV_IN_MSG_INST_ID] = s_div_req_inst_id;
	assign s_div_req_ready = div_in_buf_full_n;
	
	// 寄存器fifo
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(2),
		.fifo_data_width(72+inst_id_width),
		.almost_full_th(1),
		.almost_empty_th(0),
		.simulation_delay(simulation_delay)
	)div_in_buf_fifo(
		.clk(clk),
		.rst_n(resetn),
		
		.fifo_wen(div_in_buf_wen),
		.fifo_din(div_in_buf_din),
		.fifo_full(),
		.fifo_full_n(div_in_buf_full_n),
		.fifo_almost_full(),
		.fifo_almost_full_n(),
		
		.fifo_ren(div_in_buf_ren),
		.fifo_dout(div_in_buf_dout),
		.fifo_empty(),
		.fifo_empty_n(div_in_buf_empty_n),
		.fifo_almost_empty(),
		.fifo_almost_empty_n(),
		
		.data_cnt()
	);
	
	/** 除法结果 **/
	wire[31:0] div_res_s0_data; // 除法结果
	wire[4:0] div_res_s0_rd_id; // RD索引
	wire[inst_id_width-1:0] div_res_s0_inst_id; // 指令编号
	wire div_res_s0_valid;
	wire div_res_s0_ready;
	reg[31:0] div_res_s1_data; // 除法结果
	reg[4:0] div_res_s1_rd_id; // RD索引
	reg[inst_id_width-1:0] div_res_s1_inst_id; // 指令编号
	reg div_res_s1_valid;
	wire div_res_s1_ready;
	
	assign m_div_res_data = div_res_s1_data;
	assign m_div_res_rd_id = div_res_s1_rd_id;
	assign m_div_res_inst_id = div_res_s1_inst_id;
	assign m_div_res_valid = div_res_s1_valid;
	assign div_res_s1_ready = m_div_res_ready;
	
	assign div_res_s0_ready = (~div_res_s1_valid) | div_res_s1_ready;
	
	// 除法结果
	always @(posedge clk)
	begin
		if(div_res_s0_valid & div_res_s0_ready)
			div_res_s1_data <= # simulation_delay div_res_s0_data;
	end
	// RD索引
	always @(posedge clk)
	begin
		if(div_res_s0_valid & div_res_s0_ready)
			div_res_s1_rd_id <= # simulation_delay div_res_s0_rd_id;
	end
	// 指令编号
	always @(posedge clk)
	begin
		if(div_res_s0_valid & div_res_s0_ready)
			div_res_s1_inst_id <= # simulation_delay div_res_s0_inst_id;
	end
	
	// 除法结果有效指示
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			div_res_s1_valid <= 1'b0;
		else if(div_res_s0_ready)
			div_res_s1_valid <= # simulation_delay div_res_s0_valid;
	end
	
	/** 不恢复余数除法器 **/
	wire[32:0] dividend; // 被除数
	wire[32:0] divisor; // 除数
	reg[32:0] remainder; // 余数寄存器
	reg[32:0] quotient; // 商寄存器
	wire[32:0] remainder_div_exct_fix; // 整除修正后的余数
	wire[32:0] quotient_div_exct_fix; // 整除修正后的商
	wire[32:0] remainder_add_op_a[0:1]; // 余数加法器的操作数A
	wire[32:0] remainder_add_op_b[0:1]; // 余数加法器的操作数B
	wire[1:0] remainder_add_cin; // 余数加法器的进位输入
	wire[32:0] remainder_add_res[0:1]; // 余数加法器的结果输出
	wire[1:0] qut_for_shift_in; // 上商值
	wire need_fix_remainder; // 需要修正余数(标志)
	wire need_fix_quotient; // 需要修正商(标志)
	reg to_fix_remainder; // 进行修正余数(标志)
	reg to_fix_quotient; // 进行修正商(标志)
	wire to_fix_div_exct; // 进行整除修正(标志)
	wire div_zero; // 除0标志
	wire div_ovf; // 除法溢出标志
	wire rem_eq_dvs; // 余数等于除数(标志)
	wire rem_eq_inv_dvs; // 余数等于负的除数(标志)
	reg[19:0] div_proc_onehot; // 除法计算流程独热码
	
	assign div_in_buf_ren = div_proc_onehot[19] & div_res_s0_ready;
	
	assign div_res_s0_data = div_in_buf_dout[DIV_IN_MSG_REM_SEL] ? remainder_div_exct_fix[31:0]:quotient_div_exct_fix[31:0];
	assign div_res_s0_rd_id = div_in_buf_dout[DIV_IN_MSG_RD_ID+4:DIV_IN_MSG_RD_ID];
	assign div_res_s0_inst_id = div_in_buf_dout[DIV_IN_MSG_INST_ID+inst_id_width-1:DIV_IN_MSG_INST_ID];
	assign div_res_s0_valid = div_proc_onehot[19];
	
	assign dividend = div_in_buf_dout[DIV_IN_MSG_OP_A+32:DIV_IN_MSG_OP_A];
	assign divisor = div_in_buf_dout[DIV_IN_MSG_OP_B+32:DIV_IN_MSG_OP_B];
	
	// 进行整除修正, 余数置0
	assign remainder_div_exct_fix = 
		{33{~to_fix_div_exct}} & remainder;
	// 进行整除修正, 被除数和除数异号时减去1, 被除数和除数同号时加上1
	assign quotient_div_exct_fix = 
		quotient + {{32{to_fix_div_exct & (dividend[32] ^ divisor[32])}}, to_fix_div_exct};
	
	assign remainder_add_op_a[0] = 
		({33{div_proc_onehot[0]}} & {33{dividend[32]}}) | // 预置阶段 -> 将符号拓展后的被除数载入{R, Q}
		({33{div_proc_onehot[18]}} & remainder) | // 修正阶段 -> 修正余数
		({33{~(div_proc_onehot[0] | div_proc_onehot[18])}} & {remainder[31:0], quotient[32]}); // 计算阶段 -> 左移{R, Q}
	assign remainder_add_op_b[0] = {33{remainder_add_cin[0]}} ^ divisor; // 除数
	assign remainder_add_cin[0] = qut_for_shift_in[0];
	
	assign remainder_add_op_a[1] = {remainder_add_res[0][31:0], quotient[31]};
	assign remainder_add_op_b[1] = {33{remainder_add_cin[1]}} ^ divisor; // 除数
	assign remainder_add_cin[1] = qut_for_shift_in[1];
	
	assign remainder_add_res[0] = remainder_add_op_a[0] + remainder_add_op_b[0] + remainder_add_cin[0];
	assign remainder_add_res[1] = remainder_add_op_a[1] + remainder_add_op_b[1] + remainder_add_cin[1];
	
	/*
	预置或修正阶段时判断被除数与除数是否异号, 计算阶段时判断余数与除数是否异号
	预置或计算阶段时异号相加, 同号相减; 修正阶段时同号相加, 异号相减
	*/
	assign qut_for_shift_in[0] = 
		(~div_proc_onehot[18]) ^ 
		(
			(
				(div_proc_onehot[0] | div_proc_onehot[18]) ? 
					dividend[32]:
					remainder[32]
			) ^ 
			divisor[32]
		);
	assign qut_for_shift_in[1] = 
		~(remainder_add_res[0][32] ^ divisor[32]);
	
	// 仅左移商阶段时, 若余数与被除数异号则需要修正余数
	assign need_fix_remainder = remainder_add_res[0][32] ^ dividend[32];
	// 仅左移商阶段时, 若被除数与除数异号则需要修正商
	assign need_fix_quotient = dividend[32] ^ divisor[32];
	
	// 如果余数等于除数或者负的除数, 并且不是除0也没有除法溢出, 则进行整除修正
	assign to_fix_div_exct = (rem_eq_dvs | rem_eq_inv_dvs) & (~div_zero) & (~div_ovf);
	
	assign div_zero = 
		divisor[31:0] == 32'h0000_0000;
	assign div_ovf = 
		(dividend == 33'h1_8000_0000) & // 被除数为-2^31
		(divisor == 33'h1_FFFF_FFFF); // 除数为-1
	
	assign rem_eq_dvs = remainder == divisor;
	assign rem_eq_inv_dvs = remainder == ((~divisor) + 1'b1);
	
	// 余数寄存器
	always @(posedge clk)
	begin
		if(
			(div_proc_onehot[0] & div_in_buf_empty_n) | 
			(~(div_proc_onehot[0] | div_proc_onehot[18] | div_proc_onehot[19])) | 
			(div_proc_onehot[18] & to_fix_remainder)
		)
			remainder <= # simulation_delay 
				{33{~div_ovf}} & // 溢出时余数为0
				(
					div_zero ? 
						dividend: // 除0时余数为被除数
						(
							(div_proc_onehot[0] | div_proc_onehot[17] | div_proc_onehot[18]) ? 
								remainder_add_res[0]:
								remainder_add_res[1]
						)
				);
	end
	
	// 商寄存器
	always @(posedge clk)
	begin
		if(
			(div_proc_onehot[0] & div_in_buf_empty_n) | 
			(~(div_proc_onehot[0] | div_proc_onehot[18] | div_proc_onehot[19])) | 
			(div_proc_onehot[18] & to_fix_quotient)
		)
			quotient <= # simulation_delay 
				(
					// 预置阶段
					({33{div_proc_onehot[0]}} & ({33{div_zero}} | dividend)) | // 除0时将商的所有位设为1, 溢出时商为-2^31
					// 修正阶段
					({33{div_proc_onehot[18]}} & quotient) | 
					// 计算阶段, 仅左移商阶段
					({33{~(div_proc_onehot[0] | div_proc_onehot[18])}} & {quotient[30:0], qut_for_shift_in[0], qut_for_shift_in[1]})
				) + div_proc_onehot[18];
	end
	
	// 进行修正余数(标志)
	always @(posedge clk)
	begin
		if(div_proc_onehot[17])
			to_fix_remainder <= # simulation_delay need_fix_remainder;
	end
	// 进行修正商(标志)
	always @(posedge clk)
	begin
		if(div_proc_onehot[17])
			to_fix_quotient <= # simulation_delay need_fix_quotient;
	end
	
	// 除法计算流程独热码
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			div_proc_onehot <= 1;
		else if(
			(div_proc_onehot[0] & div_in_buf_empty_n) | 
			(~(div_proc_onehot[0] | div_proc_onehot[19])) | 
			(div_proc_onehot[19] & div_res_s0_ready)
		)
			div_proc_onehot <= # simulation_delay 
				(
					{20{div_proc_onehot[0]}} & 
					(
						(div_zero | div_ovf) ? 
							(1 << 19): // 除0或溢出, 直接输出
							(1 << 1)
					)
				) | 
				(
					{20{div_proc_onehot[17]}} & 
					(
						(need_fix_remainder | need_fix_quotient) ? 
						(1 << 18): // 需要修正余数或商
						(1 << 19) // 不需要修正余数或商, 直接输出
					)
				) | 
				(
					{20{~(div_proc_onehot[0] | div_proc_onehot[17])}} & 
					((div_proc_onehot << 1) | (div_proc_onehot >> (20 - 1)))
				);
	end
	
endmodule
