`timescale 1ns / 1ps
/********************************************************************
本模块: 多周期乘法器

描述:
使用1个18位*18位有符号和1个48位累加器来实现33位*33位有符号乘法器

包含深度为2的乘法器输入缓存区

周期数 = 输入缓存区(1cycle) + 计算(6cycle) + 乘法结果输出寄存器(1cycle)

注意：
无

协议:
无

作者: 陈家耀
日期: 2025/01/09
********************************************************************/


module panda_risc_v_multiplier #(
	parameter integer inst_id_width = 4, // 指令编号的位宽
    parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// 乘法器执行请求
	input wire[32:0] s_mul_req_op_a, // 操作数A
	input wire[32:0] s_mul_req_op_b, // 操作数B
	input wire s_mul_req_res_sel, // 乘法结果选择(1'b0 -> 低32位, 1'b1 -> 高32位)
	input wire[4:0] s_mul_req_rd_id, // RD索引
	input wire[inst_id_width-1:0] s_mul_req_inst_id, // 指令编号
	input wire s_mul_req_valid,
	output wire s_mul_req_ready,
	
	// 乘法器计算结果
	output wire[31:0] m_mul_res_data, // 计算结果
	output wire[4:0] m_mul_res_rd_id, // RD索引
	output wire[inst_id_width-1:0] m_mul_res_inst_id, // 指令编号
	output wire m_mul_res_valid,
	input wire m_mul_res_ready
);
	
	/** 常量 **/
	// 乘法器输入信息各项的起始索引
	localparam integer MUL_IN_MSG_RES_SEL = 0;
	localparam integer MUL_IN_MSG_OP_A = 1;
	localparam integer MUL_IN_MSG_OP_B = 34;
	localparam integer MUL_IN_MSG_RD_ID = 67;
	localparam integer MUL_IN_MSG_INST_ID = 72;
	
    /** 乘法器输入缓存区 **/
	// 缓存区写端口
	wire mul_in_buf_wen;
	wire[72+inst_id_width-1:0] mul_in_buf_din;
	wire mul_in_buf_full_n;
	// 缓存区读端口
	wire mul_in_buf_ren;
	wire[72+inst_id_width-1:0] mul_in_buf_dout;
	wire mul_in_buf_empty_n;
	
	assign mul_in_buf_wen = s_mul_req_valid;
	assign mul_in_buf_din[MUL_IN_MSG_RES_SEL] = s_mul_req_res_sel;
	assign mul_in_buf_din[MUL_IN_MSG_OP_A+32:MUL_IN_MSG_OP_A] = s_mul_req_op_a;
	assign mul_in_buf_din[MUL_IN_MSG_OP_B+32:MUL_IN_MSG_OP_B] = s_mul_req_op_b;
	assign mul_in_buf_din[MUL_IN_MSG_RD_ID+4:MUL_IN_MSG_RD_ID] = s_mul_req_rd_id;
	assign mul_in_buf_din[MUL_IN_MSG_INST_ID+inst_id_width-1:MUL_IN_MSG_INST_ID] = s_mul_req_inst_id;
	assign s_mul_req_ready = mul_in_buf_full_n;
	
	// 寄存器fifo
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("true"),
		.fifo_depth(2),
		.fifo_data_width(72+inst_id_width),
		.almost_full_th(1),
		.almost_empty_th(0),
		.simulation_delay(simulation_delay)
	)mul_in_buf_fifo(
		.clk(clk),
		.rst_n(resetn),
		
		.fifo_wen(mul_in_buf_wen),
		.fifo_din(mul_in_buf_din),
		.fifo_full_n(mul_in_buf_full_n),
		
		.fifo_ren(mul_in_buf_ren),
		.fifo_dout(mul_in_buf_dout),
		.fifo_empty_n(mul_in_buf_empty_n)
	);
	
	/** 乘法结果 **/
	wire[31:0] mul_res_s0_data; // 计算结果
	wire[4:0] mul_res_s0_rd_id; // RD索引
	wire[inst_id_width-1:0] mul_res_s0_inst_id; // 指令编号
	wire mul_res_s0_valid;
	wire mul_res_s0_ready;
	reg[31:0] mul_res_s1_data; // 计算结果
	reg[4:0] mul_res_s1_rd_id; // RD索引
	reg[inst_id_width-1:0] mul_res_s1_inst_id; // 指令编号
	reg mul_res_s1_valid;
	wire mul_res_s1_ready;
	
	assign m_mul_res_data = mul_res_s1_data;
	assign m_mul_res_rd_id = mul_res_s1_rd_id;
	assign m_mul_res_inst_id = mul_res_s1_inst_id;
	assign m_mul_res_valid = mul_res_s1_valid;
	assign mul_res_s1_ready = m_mul_res_ready;
	
	assign mul_res_s0_ready = (~mul_res_s1_valid) | mul_res_s1_ready;
	
	// 计算结果
	always @(posedge clk)
	begin
		if(mul_res_s0_valid & mul_res_s0_ready)
			mul_res_s1_data <= # simulation_delay mul_res_s0_data;
	end
	// RD索引
	always @(posedge clk)
	begin
		if(mul_res_s0_valid & mul_res_s0_ready)
			mul_res_s1_rd_id <= # simulation_delay mul_res_s0_rd_id;
	end
	// 指令编号
	always @(posedge clk)
	begin
		if(mul_res_s0_valid & mul_res_s0_ready)
			mul_res_s1_inst_id <= # simulation_delay mul_res_s0_inst_id;
	end
	
	// 乘法结果有效指示
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mul_res_s1_valid <= 1'b0;
		else if(mul_res_s0_ready)
			mul_res_s1_valid <= # simulation_delay mul_res_s0_valid;
	end
	
	/**
	18位*18位有符号乘法器
	
	时延 = 2clk
	**/
	wire signed[17:0] mul_18_18_in_op_a;
	wire signed[17:0] mul_18_18_in_op_b;
	wire mul_18_18_in_vld;
	reg mul_18_18_in_vld_d;
	wire signed[35:0] mul_18_18_out_res;
	
	// 延迟1clk的乘法器输入有效指示
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mul_18_18_in_vld_d <= 1'b0;
		else
			mul_18_18_in_vld_d <= # simulation_delay mul_18_18_in_vld;
	end
	
	// 18位*18位有符号乘法器
	mul_add_dsp #(
		.en_op_a_in_regs("false"),
		.en_op_b_in_regs("false"),
		.en_op_d_in_regs("false"),
		.en_pre_adder("false"),
		.en_op_b_in_s1_regs("false"),
		.en_op_c_in_s1_regs("false"),
		.en_op_c_in_s2_regs("true"),
		.op_a_width(18),
		.op_b_width(18),
		.op_c_width(36),
		.op_d_width(18),
		.output_width(36),
		.pattern_detect_msb_id(0),
		.pattern_detect_lsb_id(0),
		.pattern_detect_cmp(1'b0),
		.simulation_delay(simulation_delay)
	)mul_18_18(
		.clk(clk),
		
		.ce_s0_op_a(1'b1),
		.ce_s0_op_b(1'b1),
		.ce_s0_op_d(1'b1),
		.ce_s1_pre_adder(1'b1),
		.ce_s1_op_b(1'b1),
		.ce_s1_op_c(1'b1),
		.ce_s2_mul(mul_18_18_in_vld),
		.ce_s2_op_c(mul_18_18_in_vld),
		.ce_s3_p(mul_18_18_in_vld_d),
		
		.op_a(mul_18_18_in_op_a),
		.op_b(mul_18_18_in_op_b),
		.op_c(36'd0),
		.op_d(18'd0),
		
		.res(mul_18_18_out_res),
		.pattern_detect_res()
	);
	
	/** 累加器 **/
	wire to_clr_accum; // 累加寄存器清零指示
	wire[3:0] accum_proc_onehot; // 累加进程独热码
	wire[47:0] accum_in; // 累加输入
	reg signed[47:0] accum_for_mul_64_17;
	reg[16:0] mul_low_17_latched;
	wire signed[64:0] mul_res;
	
	assign mul_res_s0_data = mul_in_buf_dout[MUL_IN_MSG_RES_SEL] ? 
		mul_res[63:32]:mul_res[31:0];
	assign mul_res_s0_rd_id = mul_in_buf_dout[MUL_IN_MSG_RD_ID+4:MUL_IN_MSG_RD_ID];
	assign mul_res_s0_inst_id = mul_in_buf_dout[MUL_IN_MSG_INST_ID+inst_id_width-1:MUL_IN_MSG_INST_ID];
	
	assign accum_in = 
	    ({48{accum_proc_onehot[0]}} & {29'd0, mul_18_18_out_res[35:17]}) | 
		({48{accum_proc_onehot[1] | accum_proc_onehot[2]}} & {{12{mul_18_18_out_res[35]}}, mul_18_18_out_res[35:0]}) | 
		({48{accum_proc_onehot[3]}} & {mul_18_18_out_res[30:0], 17'd0});
	
	assign mul_res = {accum_for_mul_64_17, mul_low_17_latched};
	
	always @(posedge clk)
	begin
		if(to_clr_accum)
			accum_for_mul_64_17 <= 48'd0;
		else if(|accum_proc_onehot)
			accum_for_mul_64_17 <= # simulation_delay accum_for_mul_64_17 + accum_in;
	end
	
	always @(posedge clk)
	begin
		if(accum_proc_onehot[0])
			mul_low_17_latched <= # simulation_delay mul_18_18_out_res[16:0];
	end
	
	/**
	乘法计算控制
	
	clk                       内容
	#0   开始计算{1'b0, op_a[16:0]} * {1'b0, op_b[16:0]}
	#1   开始计算{{2{op_a[32]}}, op_a[32:17]} * {1'b0, op_b[16:0]}
	#2   开始计算{1'b0, op_a[16:0]} * {{2{op_b[32]}}, op_b[32:17]}
	#3   开始计算{{2{op_a[32]}}, op_a[32:17]} * {{2{op_b[32]}}, op_b[32:17]}
	
	#0   ---
	#1   ---
	#2   得到{1'b0, op_a[16:0]} * {1'b0, op_b[16:0]}
	#3   得到{{2{op_a[32]}}, op_a[32:17]} * {1'b0, op_b[16:0]}
	#4   得到{1'b0, op_a[16:0]} * {{2{op_b[32]}}, op_b[32:17]}
	#5   得到{{2{op_a[32]}}, op_a[32:17]} * {{2{op_b[32]}}, op_b[32:17]}
	
	#0   ---
	#1   清零累加寄存器
	#2   累加{29'd0, mul_part_res_ll[35:17]}, 锁存mul_part_res_ll[16:0]
	#3   累加{{12{mul_part_res_hl[35]}}, mul_part_res_hl[35:0]}
	#4   累加{{12{mul_part_res_lh[35]}}, mul_part_res_lh[35:0]}
	#5   累加{mul_part_res_hh[30:0], 17'd0}
	#6   选择乘法结果的低32位/高32位, 等待后级握手
	**/
	reg[6:0] mul_ctrl_onehot; // 乘法计算流程独热码
	reg mul_18_18_in_op_a_sel; // 18位*18位有符号乘法器操作数a选择
	reg mul_18_18_in_op_b_sel; // 18位*18位有符号乘法器操作数b选择
	
	assign mul_in_buf_ren = mul_ctrl_onehot[6] & mul_res_s0_ready;
	
	assign mul_res_s0_valid = mul_ctrl_onehot[6];
	
	assign mul_18_18_in_op_a = 
		mul_18_18_in_op_a_sel ? 
			{1'b0, mul_in_buf_dout[MUL_IN_MSG_OP_A+16:MUL_IN_MSG_OP_A]}:
			{{2{mul_in_buf_dout[MUL_IN_MSG_OP_A+32]}}, mul_in_buf_dout[MUL_IN_MSG_OP_A+32:MUL_IN_MSG_OP_A+17]};
	assign mul_18_18_in_op_b = 
		mul_18_18_in_op_b_sel ? 
			{1'b0, mul_in_buf_dout[MUL_IN_MSG_OP_B+16:MUL_IN_MSG_OP_B]}:
			{{2{mul_in_buf_dout[MUL_IN_MSG_OP_B+32]}}, mul_in_buf_dout[MUL_IN_MSG_OP_B+32:MUL_IN_MSG_OP_B+17]};
	assign mul_18_18_in_vld = 
		(mul_ctrl_onehot[0] & mul_in_buf_empty_n) | 
		mul_ctrl_onehot[1] | 
		mul_ctrl_onehot[2] | 
		mul_ctrl_onehot[3];
	
	assign to_clr_accum = mul_ctrl_onehot[1];
	assign accum_proc_onehot = mul_ctrl_onehot[5:2];
	
	// 乘法计算流程独热码
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mul_ctrl_onehot <= 7'b0000001;
		else if((mul_ctrl_onehot[0] & mul_in_buf_empty_n) | 
			((~mul_ctrl_onehot[0]) & (~mul_ctrl_onehot[6])) | 
			(mul_ctrl_onehot[6] & mul_res_s0_ready))
			mul_ctrl_onehot <= # simulation_delay {mul_ctrl_onehot[5:0], mul_ctrl_onehot[6]};
	end
	
	// 18位*18位有符号乘法器操作数a选择
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mul_18_18_in_op_a_sel <= 1'b1;
		else if((mul_ctrl_onehot[0] & mul_in_buf_empty_n) | 
			((~mul_ctrl_onehot[0]) & (~mul_ctrl_onehot[6])) | 
			(mul_ctrl_onehot[6] & mul_res_s0_ready))
			mul_18_18_in_op_a_sel <= # simulation_delay mul_ctrl_onehot[1] | mul_ctrl_onehot[6];
	end
	// 18位*18位有符号乘法器操作数b选择
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mul_18_18_in_op_b_sel <= 1'b1;
		else if((mul_ctrl_onehot[0] & mul_in_buf_empty_n) | 
			((~mul_ctrl_onehot[0]) & (~mul_ctrl_onehot[6])) | 
			(mul_ctrl_onehot[6] & mul_res_s0_ready))
			mul_18_18_in_op_b_sel <= # simulation_delay mul_ctrl_onehot[0] | mul_ctrl_onehot[6];
	end
	
endmodule
