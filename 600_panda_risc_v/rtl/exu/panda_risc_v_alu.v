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
本模块: ALU

描述:
ALU实现了以下运算:
	按位逻辑运算(XOR, OR, AND)
	加减法运算(+, -)
	比较(>=, <, ==, !=)
	移位(SLL, SRL, SRA)

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/12/07
********************************************************************/


module panda_risc_v_alu #(
	parameter en_shift_reuse = "true", // 是否复用移位器
	parameter en_eq_cmp_reuse = "false" // 是否复用相等比较器
)(
	// ALU操作信息输入
	input wire[3:0] op_mode, // 操作类型
	input wire[31:0] op1, // 操作数1
	input wire[31:0] op2, // 操作数2
	
	// 特定结果输出
	output wire brc_cond_res, // 分支判定结果
	output wire[31:0] ls_addr, // 访存地址
	
	// ALU计算结果输出
	output wire[31:0] res // 计算结果
);
	
	/** 常量 **/
	// 操作类型
	localparam OP_MODE_ADD = 4'd0; // 加法
	localparam OP_MODE_SUB = 4'd1; // 减法
	localparam OP_MODE_EQU = 4'd2; // 比较是否相等
	localparam OP_MODE_NEQU = 4'd3; // 比较是否不等
	localparam OP_MODE_SGN_LT = 4'd4; // 有符号数比较是否小于
	localparam OP_MODE_SGN_GET = 4'd5; // 有符号数比较是否大于等于
	localparam OP_MODE_USGN_LT = 4'd6; // 无符号数比较是否小于
	localparam OP_MODE_USGN_GET = 4'd7; // 无符号数比较是否大于等于
	localparam OP_MODE_XOR = 4'd8; // 按位异或
	localparam OP_MODE_OR = 4'd9; // 按位或
	localparam OP_MODE_AND = 4'd10; // 按位与
	localparam OP_MODE_LG_LSH = 4'd11; // 逻辑左移
	localparam OP_MODE_LG_RSH = 4'd12; // 逻辑右移
	localparam OP_MODE_ATH_RSH = 4'd13; // 算术右移
	
	/** ALU详细操作标志 **/
	wire is_sub; // 减法操作(标志)
	wire is_cmp_geq; // 比较是否大于等于操作(标志)
	wire is_cmp_eq; // 比较是否相等操作(标志)
	wire is_cmp_neq; // 比较是否不等操作(标志)
	wire is_cmp_sign; // 有符号比较操作(标志)
	wire is_sll; // 逻辑左移操作(标志)
	wire is_sra; // 算术右移操作(标志)
	
	assign is_sub = op_mode == OP_MODE_SUB;
	assign is_cmp_geq = (op_mode == OP_MODE_SGN_GET) | (op_mode == OP_MODE_USGN_GET);
	assign is_cmp_eq = op_mode == OP_MODE_EQU;
	assign is_cmp_neq = op_mode == OP_MODE_NEQU;
	assign is_cmp_sign = (op_mode == OP_MODE_SGN_LT) | (op_mode == OP_MODE_SGN_GET);
	assign is_sll = op_mode == OP_MODE_LG_LSH;
	assign is_sra = op_mode == OP_MODE_ATH_RSH;
	
	/** 按位异或 **/
	wire[31:0] xor_res;
	
	assign xor_res = op1 ^ op2;
	
	/**  加法/减法 **/
	wire[31:0] add_sub_res;
	wire[31:0] adder_out;
	wire adder_to_sub;
	wire[31:0] adder_op1;
	wire[31:0] adder_op2;
	wire adder_cin;
	
	assign add_sub_res = adder_out;
	
	assign adder_out = adder_op1 + adder_op2 + adder_cin;
	
	assign adder_to_sub = is_sub | is_cmp_eq | is_cmp_neq;
	
	assign adder_op1 = op1;
	assign adder_op2 = op2 ^ {32{adder_to_sub}}; // adder_to_sub ? (~op2):op2
	assign adder_cin = adder_to_sub;
	
	/** 有符号/无符号比较是否大于等于/小于 **/
	wire geq_lt_cmp_res;
	wire lt_comparer_out;
	wire[32:0] op1_sign_ext;
	wire[32:0] op2_sign_ext;
	
	assign geq_lt_cmp_res = lt_comparer_out ^ is_cmp_geq; // is_cmp_geq ? (~lt_comparer_out):lt_comparer_out
	
	assign lt_comparer_out = $signed(op1_sign_ext) < $signed(op2_sign_ext);
	
	assign op1_sign_ext = {is_cmp_sign & op1[31], op1};
	assign op2_sign_ext = {is_cmp_sign & op2[31], op2};
	
	/** 比较是否相等/不等 **/
	wire eq_neq_cmp_res;
	wire eq_comparer_out;
	
	assign eq_neq_cmp_res = eq_comparer_out ^ is_cmp_neq; // is_cmp_neq ? (~eq_comparer_out):eq_comparer_out
	
	assign eq_comparer_out = (en_eq_cmp_reuse == "true") ? (adder_out == 32'd0):(op1 == op2);
	
	/** 按位或 **/
	wire[31:0] or_res;
	
	assign or_res = op1 | op2;
	
	/** 按位与 **/
	wire[31:0] and_res;
	
	assign and_res = op1 & op2;
	
	/** 逻辑左移/逻辑右移/算术右移 **/
	wire[31:0] shift_res;
	wire[31:0] sll_srl_res;
	wire[31:0] left_shifter_out;
	wire[31:0] left_shifter_op1;
	wire[4:0] left_shifter_op2;
	wire[31:0] shift_sign_mask;
	wire[31:0] sra_mask;
	
	assign shift_res = (en_shift_reuse == "true") ? 
		(sll_srl_res | sra_mask):
		(({32{op_mode == OP_MODE_LG_LSH}} & (left_shifter_op1 << left_shifter_op2)) | 
		({32{op_mode == OP_MODE_LG_RSH}} & (left_shifter_op1 >> left_shifter_op2)) | 
		({32{op_mode == OP_MODE_ATH_RSH}} & ($signed(left_shifter_op1) >>> left_shifter_op2)));
	
	assign sll_srl_res = is_sll ? left_shifter_out:{
		left_shifter_out[0], left_shifter_out[1], left_shifter_out[2], left_shifter_out[3], 
		left_shifter_out[4], left_shifter_out[5], left_shifter_out[6], left_shifter_out[7], 
		left_shifter_out[8], left_shifter_out[9], left_shifter_out[10], left_shifter_out[11], 
		left_shifter_out[12], left_shifter_out[13], left_shifter_out[14], left_shifter_out[15], 
		left_shifter_out[16], left_shifter_out[17], left_shifter_out[18], left_shifter_out[19], 
		left_shifter_out[20], left_shifter_out[21], left_shifter_out[22], left_shifter_out[23], 
		left_shifter_out[24], left_shifter_out[25], left_shifter_out[26], left_shifter_out[27], 
		left_shifter_out[28], left_shifter_out[29], left_shifter_out[30], left_shifter_out[31]
	};
	
	assign left_shifter_out = left_shifter_op1 << left_shifter_op2;
	
	assign left_shifter_op1 = is_sll ? op1:{
		op1[0], op1[1], op1[2], op1[3], op1[4], op1[5], op1[6], op1[7], 
		op1[8], op1[9], op1[10], op1[11], op1[12], op1[13], op1[14], op1[15], 
		op1[16], op1[17], op1[18], op1[19], op1[20], op1[21], op1[22], op1[23], 
		op1[24], op1[25], op1[26], op1[27], op1[28], op1[29], op1[30], op1[31]
	};
	assign left_shifter_op2 = op2[4:0];
	
	assign shift_sign_mask = ~(32'hffff_ffff >> left_shifter_op2);
	assign sra_mask = {32{is_sra & op1[31]}} & shift_sign_mask;
	
	/** ALU结果MUX **/
	wire is_logic_op;
	wire is_add_sub_op;
	wire is_geq_lt_cmp_op;
	wire is_eq_neq_cmp_op;
	wire is_shift_op;
	wire[31:0] logic_res;
	
	assign brc_cond_res = is_eq_neq_cmp_op ? eq_neq_cmp_res:geq_lt_cmp_res;
	assign ls_addr = add_sub_res;
	assign res = 
		({32{is_logic_op}} & logic_res) | 
		({32{is_add_sub_op}} & add_sub_res) | 
		({32{is_geq_lt_cmp_op}} & {31'd0, geq_lt_cmp_res}) | 
		({32{is_eq_neq_cmp_op}} & {31'd0, eq_neq_cmp_res}) | 
		({32{is_shift_op}} & shift_res);
	
	assign is_logic_op = (op_mode == OP_MODE_XOR) | (op_mode == OP_MODE_OR) | (op_mode == OP_MODE_AND);
	assign is_add_sub_op = (op_mode == OP_MODE_ADD) | (op_mode == OP_MODE_SUB);
	assign is_geq_lt_cmp_op = 
		(op_mode == OP_MODE_SGN_LT) | (op_mode == OP_MODE_SGN_GET) | 
		(op_mode == OP_MODE_USGN_LT) | (op_mode == OP_MODE_USGN_GET);
	assign is_eq_neq_cmp_op =(op_mode == OP_MODE_EQU) | (op_mode == OP_MODE_NEQU);
	assign is_shift_op = (op_mode == OP_MODE_LG_LSH) | (op_mode == OP_MODE_LG_RSH) | (op_mode == OP_MODE_ATH_RSH);
	
	assign logic_res = 
		({32{op_mode == OP_MODE_XOR}} & xor_res) | 
		({32{op_mode == OP_MODE_OR}} & or_res) | 
		({32{op_mode == OP_MODE_AND}} & and_res);
	
endmodule
