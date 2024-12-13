`timescale 1ns / 1ps
/********************************************************************
本模块: 多周期除法器

描述:
基于不恢复余数法的33位有符号除法器

包含深度为2的除法器输入缓存区

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/12/12
********************************************************************/


module panda_risc_v_divider #(
    parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// 除法器执行请求
	input wire[32:0] s_div_req_op_a, // 操作数A(被除数)
	input wire[32:0] s_div_req_op_b, // 操作数B(除数)
	input wire s_div_req_rem_sel, // 除法/求余选择(1'b0 -> 除法, 1'b1 -> 求余)
	input wire s_div_req_valid,
	output wire s_div_req_ready,
	
	// 除法器计算结果
	output wire[31:0] m_div_res_data, // 计算结果
	output wire m_div_res_valid,
	input wire m_div_res_ready
);
	
	/** 常量 **/
	// 除法器输入信息各项的起始索引
	localparam integer DIV_IN_MSG_REM_SEL = 0;
	localparam integer DIV_IN_MSG_OP_A = 1;
	localparam integer DIV_IN_MSG_OP_B = 34;
	
    /** 除法器输入缓存区 **/
	// 缓存区写端口
	wire div_in_buf_wen;
	wire[66:0] div_in_buf_din;
	wire div_in_buf_full_n;
	// 缓存区读端口
	wire div_in_buf_ren;
	wire[66:0] div_in_buf_dout;
	wire div_in_buf_empty_n;
	
	assign div_in_buf_wen = s_div_req_valid;
	assign div_in_buf_din[DIV_IN_MSG_REM_SEL] = s_div_req_rem_sel;
	assign div_in_buf_din[DIV_IN_MSG_OP_A+32:DIV_IN_MSG_OP_A] = s_div_req_op_a;
	assign div_in_buf_din[DIV_IN_MSG_OP_B+32:DIV_IN_MSG_OP_B] = s_div_req_op_b;
	assign s_div_req_ready = div_in_buf_full_n;
	
	// 寄存器fifo
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.fifo_depth(2),
		.fifo_data_width(67),
		.almost_full_th(1),
		.almost_empty_th(0),
		.simulation_delay(simulation_delay)
	)div_in_buf_fifo(
		.clk(clk),
		.rst_n(resetn),
		
		.fifo_wen(div_in_buf_wen),
		.fifo_din(div_in_buf_din),
		.fifo_full_n(div_in_buf_full_n),
		
		.fifo_ren(div_in_buf_ren),
		.fifo_dout(div_in_buf_dout),
		.fifo_empty_n(div_in_buf_empty_n)
	);
	
	/** 除法结果 **/
	wire[31:0] div_res_s0_data;
	wire div_res_s0_valid;
	wire div_res_s0_ready;
	reg[31:0] div_res_s1_data;
	reg div_res_s1_valid;
	wire div_res_s1_ready;
	
	assign m_div_res_data = div_res_s1_data;
	assign m_div_res_valid = div_res_s1_valid;
	assign div_res_s1_ready = m_div_res_ready;
	
	assign div_res_s0_ready = (~div_res_s1_valid) | div_res_s1_ready;
	
	// 除法结果
	always @(posedge clk)
	begin
		if(div_res_s0_valid & div_res_s0_ready)
			div_res_s1_data <= # simulation_delay div_res_s0_data;
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
	wire[32:0] remainder_add_op_a; // 余数加法器的操作数A
	wire[32:0] remainder_add_op_b; // 余数加法器的操作数B
	wire remainder_add_cin; // 余数加法器的进位输入
	wire qut_for_shift_in; // 上商值
	wire to_fix_remainder; // 需要修正余数(标志)
	wire to_fix_quotient; // 需要修正商(标志)
	wire to_fix_div_exct; // 需要进行整除修正(标志)
	wire div_zero; // 除0标志
	wire div_ovf; // 除法溢出标志
	reg[36:0] div_proc_onehot; // 除法计算流程独热码
	
	assign div_in_buf_ren = div_proc_onehot[36] & div_res_s0_ready;
	
	assign div_res_s0_data = div_in_buf_dout[DIV_IN_MSG_REM_SEL] ? remainder_div_exct_fix[31:0]:quotient_div_exct_fix[31:0];
	assign div_res_s0_valid = div_proc_onehot[36];
	
	assign dividend = div_in_buf_dout[DIV_IN_MSG_OP_A+32:DIV_IN_MSG_OP_A];
	assign divisor = div_in_buf_dout[DIV_IN_MSG_OP_B+32:DIV_IN_MSG_OP_B];
	
	// 进行整除修正, 余数置0
	assign remainder_div_exct_fix = {33{~to_fix_div_exct}} & remainder;
	// 进行整除修正, 被除数和除数异号时减去1, 被除数和除数同号时加上1
	assign quotient_div_exct_fix = 
		quotient + {{32{to_fix_div_exct & (dividend[32] ^ divisor[32])}}, to_fix_div_exct};
	
	assign remainder_add_op_a = 
		({33{div_proc_onehot[0]}} & {33{dividend[32]}}) | // 预置阶段 -> 将符号拓展后的被除数载入{R, Q}
		({33{div_proc_onehot[35]}} & remainder) | // 修正阶段 -> 修正余数
		({33{(~div_proc_onehot[0]) & (~div_proc_onehot[35])}} & {remainder[31:0], quotient[32]}); // 计算阶段 -> 左移{R, Q}
	assign remainder_add_op_b = {33{remainder_add_cin}} ^ divisor; // 除数
	assign remainder_add_cin = qut_for_shift_in;
	
	/*
	预置或修正阶段时判断被除数与除数是否异号, 计算阶段时判断余数与除数是否异号
	预置或计算阶段时异号相加, 同号相减; 修正阶段时同号相加, 异号相减
	*/
	assign qut_for_shift_in = (~div_proc_onehot[35]) ^ 
		(((div_proc_onehot[0] | div_proc_onehot[35]) ? dividend[32]:remainder[32]) ^ divisor[32]);
	
	assign to_fix_remainder = remainder[32] ^ dividend[32]; // 最后1次计算时, 若余数与除数异号则修正余数
	assign to_fix_quotient = dividend[32] ^ divisor[32]; // 最后1次计算时, 若被除数与除数异号则修正商
	 // 当余数等于负的除数或除数时, 进行整除修正
	assign to_fix_div_exct = (remainder == ((~divisor) + 1'b1)) | (remainder == divisor);
	
	assign div_zero = divisor[31:0] == 32'h0000_0000;
	assign div_ovf = 
		(dividend[31:0] == 32'h8000_0000) & // 被除数为-2^31
		(divisor[31:0] == 32'hFFFF_FFFF); // 除数为-1
	
	// 余数寄存器
	always @(posedge clk)
	begin
		if((div_proc_onehot[0] & div_in_buf_empty_n) | 
			((~div_proc_onehot[0]) & (~div_proc_onehot[34]) & (~div_proc_onehot[35]) & (~div_proc_onehot[36])) | 
			(div_proc_onehot[35] & to_fix_remainder))
			remainder <= # simulation_delay 
				{33{~div_ovf}} & ( // 溢出时余数为0
					div_zero ? dividend: // 除0时余数为被除数
						(remainder_add_op_a + remainder_add_op_b + remainder_add_cin)
				);
	end
	
	// 商寄存器
	always @(posedge clk)
	begin
		if((div_proc_onehot[0] & div_in_buf_empty_n) | 
			((~div_proc_onehot[0]) & (~div_proc_onehot[35]) & (~div_proc_onehot[36])) | 
			(div_proc_onehot[35] & to_fix_quotient))
			quotient <= # simulation_delay 
				// 预置阶段
				(({33{div_proc_onehot[0]}} & ({33{div_zero}} | dividend)) | // 除0时将商的所以位设为1, 溢出时商为-2^31
				// 修正阶段
				({33{div_proc_onehot[35]}} & quotient) | 
				// 计算阶段, 仅左移商阶段
				({33{(~div_proc_onehot[0]) & (~div_proc_onehot[35])}} & {quotient[31:0], qut_for_shift_in})) + div_proc_onehot[35];
	end
	
	// 除法计算流程独热码
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			div_proc_onehot <= 37'b0_0000_0000_0000_0000_0000_0000_0000_0000_0001;
		else if((div_proc_onehot[0] & div_in_buf_empty_n) | 
			((~div_proc_onehot[0]) & (~div_proc_onehot[36])) | 
			(div_proc_onehot[36] & div_res_s0_ready))
			div_proc_onehot <= # simulation_delay 
				({37{div_proc_onehot[0]}} & ((div_zero | div_ovf) ? 
					37'b1_0000_0000_0000_0000_0000_0000_0000_0000_0000: // 除0或溢出, 直接输出
					37'b0_0000_0000_0000_0000_0000_0000_0000_0000_0010)) | 
				({37{div_proc_onehot[34]}} & ((to_fix_remainder | to_fix_quotient) ? 
					37'b0_1000_0000_0000_0000_0000_0000_0000_0000_0000: // 需要修正余数或商
					37'b1_0000_0000_0000_0000_0000_0000_0000_0000_0000)) | // 不需要修正余数或商, 直接输出
				({37{(~div_proc_onehot[0]) & (~div_proc_onehot[34])}} & {div_proc_onehot[35:0], div_proc_onehot[36]});
	end
	
endmodule
