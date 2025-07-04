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
本模块: 译码器

描述:
根据取指结果和源寄存器读结果进行译码, 生成指令类型标志、读写通用寄存器堆标志、
	访存类型、乘除法操作数、CSR原子读写操作信息、ALU操作信息

乘除法操作数均为33位有符号数

CSR原子读写操作 -> 
	加载, 置位, 清零位

ALU操作 -> 
	+, -, ==, !=, 
	有符号<, 有符号>=, 无符号<, 无符号>=, 
	^, |, &, 
	<<, >>, >>>

生成实际的BTA(RS1值或PC + 偏移量)

可以先不输入源寄存器读结果, 而是根据源寄存器选择标志在后级取出操作数时再作选择

注意：
无

协议:
无

作者: 陈家耀
日期: 2025/07/01
********************************************************************/


module panda_risc_v_decoder(
	// 取指结果
	input wire[31:0] inst, // 取到的指令
	input wire[63:0] pre_decoding_msg_packeted, // 打包的预译码信息
	input wire[31:0] pc_of_inst, // 指令对应的PC
	input wire inst_len_type, // 指令长度类型(1'b0 -> 16位, 1'b1 -> 32位)
	
	// 源寄存器读结果
	input wire[31:0] rs1_v,
	input wire[31:0] rs2_v,
	
	// 指令类型标志
	output wire is_b_inst, // 是否B指令
	output wire is_csr_rw_inst, // 是否CSR读写指令
	output wire is_load_inst, // 是否load指令
	output wire is_store_inst, // 是否store指令
	output wire is_mul_inst, // 是否乘法指令
	output wire is_div_inst, // 是否除法指令
	output wire is_rem_inst, // 是否求余指令
	output wire is_ecall_inst, // 是否ECALL指令
	output wire is_mret_inst, // 是否MRET指令
	output wire is_fence_inst, // 是否FENCE指令
	output wire is_fence_i_inst, // 是否FENCE.I指令
	output wire is_ebreak_inst, // 是否EBREAK指令
	output wire is_dret_inst, // 是否DRET指令
	output wire is_jal_inst, // 是否JAL指令
	output wire is_jalr_inst, // 是否JALR指令
	output wire is_illegal_inst, // 是否非法指令
	
	// 读写通用寄存器堆标志
	output wire rs1_vld, // 是否需要读RS1
	output wire rs2_vld, // 是否需要读RS2
	output wire rd_vld, // 是否需要写RD
	
	// 访存信息
	output wire[2:0] ls_type, // 访存类型
	output wire ls_addr_aligned, // 访存地址对齐(标志)
	
	// 乘除法操作数
	output wire[32:0] mul_div_op_a, // 操作数A
	output wire[32:0] mul_div_op_b, // 操作数B
	output wire mul_res_sel, // 乘法结果选择(1'b0 -> 低32位, 1'b1 -> 高32位)
	
	// CSR原子读写操作信息
	output wire[11:0] csr_addr, // CSR地址
	output wire[1:0] csr_upd_type, // CSR更新类型
	output wire[31:0] csr_upd_mask_v, // CSR更新掩码或更新值
	
	// ALU操作信息
	output wire[3:0] alu_op_mode, // 操作类型
	output wire[31:0] alu_op1, // 操作数1
	output wire[31:0] alu_op2, // 操作数2
	
	// 实际的分支目标地址
	output wire[31:0] actual_bta,
	output wire brc_jump_baseaddr_sel_rs1,
	
	// 打包的译码结果
	output wire[15:0] dcd_res_inst_type_packeted, // 打包的指令类型标志
	output wire[69:0] dcd_res_alu_op_msg_packeted, // 打包的ALU操作信息
	output wire[98:0] dcd_res_lsu_op_msg_packeted, // 打包的LSU操作信息
	output wire[47:0] dcd_res_csr_rw_op_msg_packeted, // 打包的CSR原子读写操作信息
	output wire[68:0] dcd_res_mul_div_op_msg_packeted // 打包的乘除法操作信息
);
	
	/** 常量 **/
	// 打包的预译码信息各项的起始索引
	localparam integer PRE_DCD_MSG_IS_REM_INST_SID = 0;
	localparam integer PRE_DCD_MSG_IS_DIV_INST_SID = 1;
	localparam integer PRE_DCD_MSG_IS_MUL_INST_SID = 2;
	localparam integer PRE_DCD_MSG_IS_STORE_INST_SID = 3;
	localparam integer PRE_DCD_MSG_IS_LOAD_INST_SID = 4;
	localparam integer PRE_DCD_MSG_IS_CSR_RW_INST_SID = 5;
	localparam integer PRE_DCD_MSG_IS_JALR_INST_SID = 6;
	localparam integer PRE_DCD_MSG_IS_JAL_INST_SID = 7;
	localparam integer PRE_DCD_MSG_IS_B_INST_SID = 8;
	localparam integer PRE_DCD_MSG_IS_ECALL_INST_SID = 9;
	localparam integer PRE_DCD_MSG_IS_MRET_INST_SID = 10;
	localparam integer PRE_DCD_MSG_IS_FENCE_INST_SID = 11;
	localparam integer PRE_DCD_MSG_IS_FENCE_I_INST_SID = 12;
	localparam integer PRE_DCD_MSG_IS_EBREAK_INST_SID = 13;
	localparam integer PRE_DCD_MSG_IS_DRET_INST_SID = 14;
	localparam integer PRE_DCD_MSG_JUMP_OFS_IMM_SID = 15;
	localparam integer PRE_DCD_MSG_RD_VLD_SID = 36;
	localparam integer PRE_DCD_MSG_RS2_VLD_SID = 37;
	localparam integer PRE_DCD_MSG_RS1_VLD_SID = 38;
	localparam integer PRE_DCD_MSG_CSR_ADDR_SID = 39;
	localparam integer PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID = 51;
	// 打包的指令类型标志各项的起始索引
	localparam integer INST_TYPE_FLAG_IS_REM_INST_SID = 0;
	localparam integer INST_TYPE_FLAG_IS_DIV_INST_SID = 1;
	localparam integer INST_TYPE_FLAG_IS_MUL_INST_SID = 2;
	localparam integer INST_TYPE_FLAG_IS_STORE_INST_SID = 3;
	localparam integer INST_TYPE_FLAG_IS_LOAD_INST_SID = 4;
	localparam integer INST_TYPE_FLAG_IS_CSR_RW_INST_SID = 5;
	localparam integer INST_TYPE_FLAG_IS_B_INST_SID = 6;
	localparam integer INST_TYPE_FLAG_IS_ECALL_INST_SID = 7;
	localparam integer INST_TYPE_FLAG_IS_MRET_INST_SID = 8;
	localparam integer INST_TYPE_FLAG_IS_FENCE_INST_SID = 9;
	localparam integer INST_TYPE_FLAG_IS_FENCE_I_INST_SID = 10;
	localparam integer INST_TYPE_FLAG_IS_EBREAK_INST_SID = 11;
	localparam integer INST_TYPE_FLAG_IS_DRET_INST_SID = 12;
	localparam integer INST_TYPE_FLAG_IS_JAL_INST_SID = 13;
	localparam integer INST_TYPE_FLAG_IS_JALR_INST_SID = 14;
	localparam integer INST_TYPE_FLAG_IS_ILLEGAL_INST_SID = 15;
	// 打包的ALU操作信息各项的起始索引
	localparam integer ALU_OP_MSG_OP2_SID = 0;
	localparam integer ALU_OP_MSG_OP1_SID = 32;
	localparam integer ALU_OP_MSG_OP_MODE_SID = 64;
	localparam integer ALU_OP_MSG_OP1_SEL_RS1_SID = 68;
	localparam integer ALU_OP_MSG_OP2_SEL_RS2_SID = 69;
	// 打包的LSU操作信息各项的起始索引
	localparam integer LSU_OP_MSG_LS_OFSADDR_SID = 0;
	localparam integer LSU_OP_MSG_LS_BASEADDR_SID = 32;
	localparam integer LSU_OP_MSG_LS_TYPE_SID = 64;
	localparam integer LSU_OP_MSG_LS_DIN_SID = 67;
	// 打包的CSR原子读写操作信息各项的起始索引
	localparam integer CSR_RW_OP_MSG_MASK_V_SID = 0;
	localparam integer CSR_RW_OP_MSG_UPD_TYPE_SID = 32;
	localparam integer CSR_RW_OP_MSG_ADDR_SID = 34;
	localparam integer CSR_RW_OP_MSG_MASK_V_SEL_RS1_SID = 46;
	localparam integer CSR_RW_OP_MSG_MASK_V_SEL_RS1_INV_SID = 47;
	// 打包的乘除法操作信息各项的起始索引
	localparam integer MUL_DIV_OP_MSG_MUL_RES_SEL_SID = 0;
	localparam integer MUL_DIV_OP_MSG_OP_B_SID = 1;
	localparam integer MUL_DIV_OP_MSG_OP_A_SID = 34;
	localparam integer MUL_DIV_OP_MSG_OP_A_UNSGN_SID = 67;
	localparam integer MUL_DIV_OP_MSG_OP_B_UNSGN_SID = 68;
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
	// 指令操作码
	localparam OPCODE_LUI = 7'b0110111;
	localparam OPCODE_AUIPC = 7'b0010111;
	localparam OPCODE_JAL = 7'b1101111;
	localparam OPCODE_JALR = 7'b1100111;
	localparam OPCODE_B = 7'b1100011;
	localparam OPCODE_LD = 7'b0000011;
	localparam OPCODE_STR = 7'b0100011;
	localparam OPCODE_ARTH_IMM = 7'b0010011;
	localparam OPCODE_ARTH_REG = 7'b0110011;
	localparam OPCODE_FENCE = 7'b0001111;
	localparam OPCODE_ENV_CSR = 7'b1110011;
	// 访存类型
	localparam LS_TYPE_BYTE = 3'b000;
	localparam LS_TYPE_HALF_WORD = 3'b001;
	localparam LS_TYPE_WORD = 3'b010;
	localparam LS_TYPE_BYTE_UNSIGNED = 3'b100;
	localparam LS_TYPE_HALF_WORD_UNSIGNED = 3'b101;
	// CSR更新类型
	localparam CSR_UPD_TYPE_LOAD = 2'b00;
	localparam CSR_UPD_TYPE_SET = 2'b01;
	localparam CSR_UPD_TYPE_CLR = 2'b10;
	
	/** 指令类型译码 **/
	wire is_arth_imm_inst; // 是否立即数算术逻辑指令
	wire is_arth_regs_inst; // 是否寄存器算术逻辑指令
	// 基本I指令
	wire is_lui_inst; // 是否LUI指令
	wire is_auipc_inst; // 是否AUIPC指令
	wire is_beq_inst; // 是否BEQ指令
	wire is_bne_inst; // 是否BNE指令
	wire is_blt_inst; // 是否BLT指令
	wire is_bge_inst; // 是否BGE指令
	wire is_bltu_inst; // 是否BLTU指令
	wire is_bgeu_inst; // 是否BGEU指令
	wire is_addi_inst; // 是否ADDI指令
	wire is_slti_inst; // 是否SLTI指令
	wire is_sltiu_inst; // 是否SLTIU指令
	wire is_xori_inst; // 是否XORI指令
	wire is_ori_inst; // 是否ORI指令
	wire is_andi_inst; // 是否ANDI指令
	wire is_slli_inst; // 是否SLLI指令
	wire is_srli_inst; // 是否SRLI指令
	wire is_srai_inst; // 是否SRAI指令
	wire is_add_inst; // 是否ADD指令
	wire is_sub_inst; // 是否SUB指令
	wire is_sll_inst; // 是否SLL指令
	wire is_slt_inst; // 是否SLT指令
	wire is_sltu_inst; // 是否SLTU指令
	wire is_xor_inst; // 是否XOR指令
	wire is_srl_inst; // 是否SRL指令
	wire is_sra_inst; // 是否SRA指令
	wire is_or_inst; // 是否OR指令
	wire is_and_inst; // 是否AND指令
	wire is_fence_inst_acc; // 是否FENCE指令(精确的)
	wire is_fence_i_inst_acc; // 是否FENCE.I指令(精确的)
	wire is_csrrw_inst; // 是否CSRRW指令
	wire is_csrrs_inst; // 是否CSRRS指令
	wire is_csrrc_inst; // 是否CSRRC指令
	wire is_csrrwi_inst; // 是否CSRRWI指令
	wire is_csrrsi_inst; // 是否CSRRSI指令
	wire is_csrrci_inst; // 是否CSRRCI指令
	// 拓展M指令
	wire is_mul_inst_acc; // 是否MUL指令(精确的)
	wire is_mulh_inst_acc; // 是否MULH指令(精确的)
	wire is_mulhsu_inst_acc; // 是否MULHSU指令(精确的)
	wire is_mulhu_inst_acc; // 是否MULHU指令(精确的)
	wire is_div_inst_acc; // 是否DIV指令(精确的)
	wire is_divu_inst_acc; // 是否DIVU指令(精确的)
	wire is_rem_inst_acc; // 是否REM指令(精确的)
	wire is_remu_inst_acc; // 是否REMU指令(精确的)
	
	assign is_b_inst = pre_decoding_msg_packeted[PRE_DCD_MSG_IS_B_INST_SID];
	assign is_csr_rw_inst = pre_decoding_msg_packeted[PRE_DCD_MSG_IS_CSR_RW_INST_SID];
	assign is_load_inst = pre_decoding_msg_packeted[PRE_DCD_MSG_IS_LOAD_INST_SID];
	assign is_store_inst = pre_decoding_msg_packeted[PRE_DCD_MSG_IS_STORE_INST_SID];
	assign is_mul_inst = pre_decoding_msg_packeted[PRE_DCD_MSG_IS_MUL_INST_SID];
	assign is_div_inst = pre_decoding_msg_packeted[PRE_DCD_MSG_IS_DIV_INST_SID];
	assign is_rem_inst = pre_decoding_msg_packeted[PRE_DCD_MSG_IS_REM_INST_SID];
	assign is_ecall_inst = pre_decoding_msg_packeted[PRE_DCD_MSG_IS_ECALL_INST_SID];
	assign is_mret_inst = pre_decoding_msg_packeted[PRE_DCD_MSG_IS_MRET_INST_SID];
	assign is_fence_inst = pre_decoding_msg_packeted[PRE_DCD_MSG_IS_FENCE_INST_SID];
	assign is_fence_i_inst = pre_decoding_msg_packeted[PRE_DCD_MSG_IS_FENCE_I_INST_SID];
	assign is_ebreak_inst = pre_decoding_msg_packeted[PRE_DCD_MSG_IS_EBREAK_INST_SID];
	assign is_dret_inst = pre_decoding_msg_packeted[PRE_DCD_MSG_IS_DRET_INST_SID];
	assign is_jal_inst = pre_decoding_msg_packeted[PRE_DCD_MSG_IS_JAL_INST_SID];
	assign is_jalr_inst = pre_decoding_msg_packeted[PRE_DCD_MSG_IS_JALR_INST_SID];
	assign is_illegal_inst = pre_decoding_msg_packeted[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID];
	
	assign is_arth_imm_inst = inst[6:0] == OPCODE_ARTH_IMM;
	assign is_arth_regs_inst = (inst[6:0] == OPCODE_ARTH_REG) & (~inst[25]);
	
	assign is_lui_inst = inst[6:0] == OPCODE_LUI;
	assign is_auipc_inst = inst[6:0] == OPCODE_AUIPC;
	assign is_beq_inst = is_b_inst & (inst[14:12] == 3'b000);
	assign is_bne_inst = is_b_inst & (inst[14:12] == 3'b001);
	assign is_blt_inst = is_b_inst & (inst[14:12] == 3'b100);
	assign is_bge_inst = is_b_inst & (inst[14:12] == 3'b101);
	assign is_bltu_inst = is_b_inst & (inst[14:12] == 3'b110);
	assign is_bgeu_inst = is_b_inst & (inst[14:12] == 3'b111);
	assign is_addi_inst = (inst[6:0] == OPCODE_ARTH_IMM) & (inst[14:12] == 3'b000);
	assign is_slti_inst = (inst[6:0] == OPCODE_ARTH_IMM) & (inst[14:12] == 3'b010);
	assign is_sltiu_inst = (inst[6:0] == OPCODE_ARTH_IMM) & (inst[14:12] == 3'b011);
	assign is_xori_inst = (inst[6:0] == OPCODE_ARTH_IMM) & (inst[14:12] == 3'b100);
	assign is_ori_inst = (inst[6:0] == OPCODE_ARTH_IMM) & (inst[14:12] == 3'b110);
	assign is_andi_inst = (inst[6:0] == OPCODE_ARTH_IMM) & (inst[14:12] == 3'b111);
	assign is_slli_inst = (inst[6:0] == OPCODE_ARTH_IMM) & (inst[14:12] == 3'b001);
	assign is_srli_inst = (inst[6:0] == OPCODE_ARTH_IMM) & (inst[14:12] == 3'b101) & (~inst[30]);
	assign is_srai_inst = (inst[6:0] == OPCODE_ARTH_IMM) & (inst[14:12] == 3'b101) & inst[30];
	assign is_add_inst = (inst[6:0] == OPCODE_ARTH_REG) & (inst[14:12] == 3'b000) & (~inst[30]) & (~inst[25]);
	assign is_sub_inst = (inst[6:0] == OPCODE_ARTH_REG) & (inst[14:12] == 3'b000) & inst[30] & (~inst[25]);
	assign is_sll_inst = (inst[6:0] == OPCODE_ARTH_REG) & (inst[14:12] == 3'b001) & (~inst[25]);
	assign is_slt_inst = (inst[6:0] == OPCODE_ARTH_REG) & (inst[14:12] == 3'b010) & (~inst[25]);
	assign is_sltu_inst = (inst[6:0] == OPCODE_ARTH_REG) & (inst[14:12] == 3'b011) & (~inst[25]);
	assign is_xor_inst = (inst[6:0] == OPCODE_ARTH_REG) & (inst[14:12] == 3'b100) & (~inst[25]);
	assign is_srl_inst = (inst[6:0] == OPCODE_ARTH_REG) & (inst[14:12] == 3'b101) & (~inst[30]) & (~inst[25]);
	assign is_sra_inst = (inst[6:0] == OPCODE_ARTH_REG) & (inst[14:12] == 3'b101) & inst[30] & (~inst[25]);
	assign is_or_inst = (inst[6:0] == OPCODE_ARTH_REG) & (inst[14:12] == 3'b110) & (~inst[25]);
	assign is_and_inst = (inst[6:0] == OPCODE_ARTH_REG) & (inst[14:12] == 3'b111) & (~inst[25]);
	assign is_fence_inst_acc = (inst[6:0] == OPCODE_FENCE) & (~inst[12]);
	assign is_fence_i_inst_acc = (inst[6:0] == OPCODE_FENCE) & inst[12];
	assign is_csrrw_inst = (inst[6:0] == OPCODE_ENV_CSR) & (inst[14:12] == 3'b001);
	assign is_csrrs_inst = (inst[6:0] == OPCODE_ENV_CSR) & (inst[14:12] == 3'b010);
	assign is_csrrc_inst = (inst[6:0] == OPCODE_ENV_CSR) & (inst[14:12] == 3'b011);
	assign is_csrrwi_inst = (inst[6:0] == OPCODE_ENV_CSR) & (inst[14:12] == 3'b101);
	assign is_csrrsi_inst = (inst[6:0] == OPCODE_ENV_CSR) & (inst[14:12] == 3'b110);
	assign is_csrrci_inst = (inst[6:0] == OPCODE_ENV_CSR) & (inst[14:12] == 3'b111);
	
	assign is_mul_inst_acc = (inst[6:0] == OPCODE_ARTH_REG) & (inst[14:12] == 3'b000) & inst[25];
	assign is_mulh_inst_acc = (inst[6:0] == OPCODE_ARTH_REG) & (inst[14:12] == 3'b001) & inst[25];
	assign is_mulhsu_inst_acc = (inst[6:0] == OPCODE_ARTH_REG) & (inst[14:12] == 3'b010) & inst[25];
	assign is_mulhu_inst_acc = (inst[6:0] == OPCODE_ARTH_REG) & (inst[14:12] == 3'b011) & inst[25];
	assign is_div_inst_acc = (inst[6:0] == OPCODE_ARTH_REG) & (inst[14:12] == 3'b100) & inst[25];
	assign is_divu_inst_acc = (inst[6:0] == OPCODE_ARTH_REG) & (inst[14:12] == 3'b101) & inst[25];
	assign is_rem_inst_acc = (inst[6:0] == OPCODE_ARTH_REG) & (inst[14:12] == 3'b110) & inst[25];
	assign is_remu_inst_acc = (inst[6:0] == OPCODE_ARTH_REG) & (inst[14:12] == 3'b111) & inst[25];
	
	/** 读写通用寄存器堆标志 **/
	assign rs1_vld = pre_decoding_msg_packeted[PRE_DCD_MSG_RS1_VLD_SID];
	assign rs2_vld = pre_decoding_msg_packeted[PRE_DCD_MSG_RS2_VLD_SID];
	assign rd_vld = pre_decoding_msg_packeted[PRE_DCD_MSG_RD_VLD_SID];
	
	/** 立即数译码 **/
	wire[31:0] csr_upd_imm; // CSR更新立即数
	wire[31:0] load_reg_imm; // 加载寄存器立即数
	wire[31:0] ls_ofs_imm; // load/store地址偏移量立即数
	wire[31:0] arth_imm; // 算术逻辑运算立即数
	wire is_srli_srai_inst_fast; // 是否SRLI/SRAI指令(在立即数算术逻辑指令内快速区分)
	
	assign csr_upd_imm = {27'd0, inst[19:15]};
	assign load_reg_imm = {inst[31:12], 12'd0};
	assign ls_ofs_imm = {{20{inst[31]}}, inst[31:25], is_store_inst ? inst[11:7]:inst[24:20]};
	assign arth_imm = {{20{inst[31]}}, inst[31:20] & {1'b1, ~is_srli_srai_inst_fast, 10'h3FF}};
	
	assign is_srli_srai_inst_fast = inst[14:12] == 3'b101;
	
	/** ALU操作译码 **/
	wire alu_op1_sel_rs1; // ALU操作数1选择RS1(标志)
	wire alu_op2_sel_rs2; // ALU操作数2选择RS2(标志)
	
	assign alu_op_mode = 
		is_illegal_inst ? 
			OP_MODE_OR: // 按位或
			(
				({4{is_lui_inst | is_auipc_inst | 
					is_jal_inst | is_jalr_inst | 
					is_load_inst | is_store_inst | 
					is_addi_inst | is_add_inst}} & OP_MODE_ADD) | // 加法
				({4{is_sub_inst}} & OP_MODE_SUB) | // 减法
				({4{is_beq_inst}} & OP_MODE_EQU) | // 比较是否相等
				({4{is_bne_inst}} & OP_MODE_NEQU) | // 比较是否不等
				({4{is_blt_inst | is_slti_inst | is_slt_inst}} & OP_MODE_SGN_LT) | // 有符号数比较是否小于
				({4{is_bge_inst}} & OP_MODE_SGN_GET) | // 有符号数比较是否大于等于
				({4{is_bltu_inst | is_sltiu_inst | is_sltu_inst}} & OP_MODE_USGN_LT) | // 无符号数比较是否小于
				({4{is_bgeu_inst}} & OP_MODE_USGN_GET) | // 无符号数比较是否大于等于
				({4{is_xori_inst | is_xor_inst}} & OP_MODE_XOR) | // 按位异或
				({4{is_ori_inst | is_or_inst}} & OP_MODE_OR) | // 按位或
				({4{is_andi_inst | is_and_inst}} & OP_MODE_AND) | // 按位与
				({4{is_slli_inst | is_sll_inst}} & OP_MODE_LG_LSH) | // 逻辑左移
				({4{is_srli_inst | is_srl_inst}} & OP_MODE_LG_RSH) | // 逻辑右移
				({4{is_srai_inst | is_sra_inst}} & OP_MODE_ATH_RSH) // 算术右移
			);
	assign alu_op1 = 
		is_illegal_inst ? 
			inst:
			(
				({32{is_lui_inst}} & 32'd0) | 
				({32{is_auipc_inst | is_jal_inst | is_jalr_inst}} & pc_of_inst) | 
				({32{alu_op1_sel_rs1}} & rs1_v)
			);
	assign alu_op2 = 
		is_illegal_inst ? 
			32'h0000_0000:
			(
				({32{is_jal_inst | is_jalr_inst}} & 32'd4) | 
				({32{is_lui_inst | is_auipc_inst}} & load_reg_imm) | 
				({32{is_load_inst | is_store_inst}} & ls_ofs_imm) | 
				({32{is_arth_imm_inst}} & arth_imm) | 
				({32{alu_op2_sel_rs2}} & rs2_v)
			);
	
	assign alu_op1_sel_rs1 = 
		(~is_illegal_inst) & 
		(is_b_inst | is_arth_regs_inst | is_load_inst | is_store_inst | is_arth_imm_inst);
	assign alu_op2_sel_rs2 = 
		(~is_illegal_inst) & 
		(is_b_inst | is_arth_regs_inst);
	
	/** 实际的分支目标地址 **/
	wire[31:0] brc_jump_ofs; // 分支跳转偏移量
	
	assign actual_bta = 
		(
			brc_jump_baseaddr_sel_rs1 ? 
				rs1_v:
				pc_of_inst
		) + brc_jump_ofs;
	assign brc_jump_baseaddr_sel_rs1 = is_jalr_inst;
	
	assign brc_jump_ofs = {
		{11{pre_decoding_msg_packeted[PRE_DCD_MSG_JUMP_OFS_IMM_SID+20]}}, 
		pre_decoding_msg_packeted[PRE_DCD_MSG_JUMP_OFS_IMM_SID+20:PRE_DCD_MSG_JUMP_OFS_IMM_SID]
	};
	
	/** 访存信息生成 **/
	wire[1:0] ls_addr_pre_cal; // 预计算的访存地址低2位
	
	assign ls_type = inst[14:12];
	assign ls_addr_aligned = 
		(ls_type == LS_TYPE_BYTE) | 
		(ls_type == LS_TYPE_BYTE_UNSIGNED) | 
		(((ls_type == LS_TYPE_HALF_WORD) | (ls_type == LS_TYPE_HALF_WORD_UNSIGNED)) & (~ls_addr_pre_cal[0])) | 
		((ls_type == LS_TYPE_WORD) & (ls_addr_pre_cal == 2'b00));
	
	assign ls_addr_pre_cal = rs1_v[1:0] + ls_ofs_imm[1:0];
	
	/** 乘除法操作数生成 **/
	wire is_mul_inst_fast; // 是否MUL指令(在乘除法指令内快速区分)
	wire is_mulhsu_inst_fast; // 是否MULHSU指令(在乘除法指令内快速区分)
	wire is_mulhu_inst_fast; // 是否MULHU指令(在乘除法指令内快速区分)
	wire is_divu_inst_fast; // 是否DIVU指令(在乘除法指令内快速区分)
	wire is_remu_inst_fast; // 是否REMU指令(在乘除法指令内快速区分)
	wire mul_div_op_a_unsigned; // 乘除法操作数A无符号(标志)
	wire mul_div_op_b_unsigned; // 乘除法操作数B无符号(标志)
	
	assign mul_div_op_a = 
		{(~mul_div_op_a_unsigned) & rs1_v[31], rs1_v};
	assign mul_div_op_b = 
		{(~mul_div_op_b_unsigned) & rs2_v[31], rs2_v};
	assign mul_res_sel = 
		~is_mul_inst_fast;
	
	assign is_mul_inst_fast = inst[14:12] == 3'b000;
	assign is_mulhsu_inst_fast = inst[14:12] == 3'b010;
	assign is_mulhu_inst_fast = inst[14:12] == 3'b011;
	assign is_divu_inst_fast = inst[14:12] == 3'b101;
	assign is_remu_inst_fast = inst[14:12] == 3'b111;
	
	assign mul_div_op_a_unsigned = is_divu_inst_fast | is_remu_inst_fast | is_mulhu_inst_fast;
	assign mul_div_op_b_unsigned = is_divu_inst_fast | is_remu_inst_fast | is_mulhu_inst_fast | is_mulhsu_inst_fast;
	
	/** CSR读写 **/
	wire is_csrrw_inst_fast; // 是否CSRRW指令(在CSR读写指令内快速区分)
	wire is_csrrs_inst_fast; // 是否CSRRS指令(在CSR读写指令内快速区分)
	wire is_csrrc_inst_fast; // 是否CSRRC指令(在CSR读写指令内快速区分)
	wire is_csrrwi_inst_fast; // 是否CSRRWI指令(在CSR读写指令内快速区分)
	wire is_csrrsi_inst_fast; // 是否CSRRSI指令(在CSR读写指令内快速区分)
	wire is_csrrci_inst_fast; // 是否CSRRCI指令(在CSR读写指令内快速区分)
	wire csr_upd_mask_v_sel_rs1; // CSR更新掩码或更新值选择RS1(标志)
	wire csr_upd_mask_v_sel_rs1_inv; // CSR更新掩码或更新值选择RS1的按位取反(标志)
	
	assign csr_addr = inst[31:20];
	assign csr_upd_type = 
		({2{is_csrrw_inst_fast | is_csrrwi_inst_fast}} & CSR_UPD_TYPE_LOAD) | 
		({2{is_csrrs_inst_fast | is_csrrsi_inst_fast}} & CSR_UPD_TYPE_SET) | 
		({2{is_csrrc_inst_fast | is_csrrci_inst_fast}} & CSR_UPD_TYPE_CLR);
	assign csr_upd_mask_v = 
		({32{csr_upd_mask_v_sel_rs1}} & rs1_v) | 
		({32{is_csrrsi_inst_fast | is_csrrwi_inst_fast}} & csr_upd_imm) | 
		({32{csr_upd_mask_v_sel_rs1_inv}} & (~rs1_v)) | 
		({32{is_csrrci_inst_fast}} & (~csr_upd_imm));
	
	assign is_csrrw_inst_fast = inst[14:12] == 3'b001;
	assign is_csrrs_inst_fast = inst[14:12] == 3'b010;
	assign is_csrrc_inst_fast = inst[14:12] == 3'b011;
	assign is_csrrwi_inst_fast = inst[14:12] == 3'b101;
	assign is_csrrsi_inst_fast = inst[14:12] == 3'b110;
	assign is_csrrci_inst_fast = inst[14:12] == 3'b111;
	
	assign csr_upd_mask_v_sel_rs1 = is_csrrs_inst_fast | is_csrrw_inst_fast;
	assign csr_upd_mask_v_sel_rs1_inv = is_csrrc_inst_fast;
	
	/** 打包的译码结果 **/
	assign dcd_res_inst_type_packeted = {
		is_illegal_inst, 
		is_jalr_inst, is_jal_inst, 
		is_dret_inst, is_ebreak_inst, 
		is_fence_i_inst, is_fence_inst, 
		is_mret_inst, is_ecall_inst, 
		is_b_inst, is_csr_rw_inst, is_load_inst, is_store_inst, 
		is_mul_inst, is_div_inst, is_rem_inst
	};
	assign dcd_res_alu_op_msg_packeted = {
		alu_op2_sel_rs2, alu_op1_sel_rs1, 
		alu_op_mode, alu_op1, alu_op2
	};
	assign dcd_res_lsu_op_msg_packeted = {
		rs2_v, 
		ls_type, 
		rs1_v, 
		ls_ofs_imm
	};
	assign dcd_res_csr_rw_op_msg_packeted = {
		csr_upd_mask_v_sel_rs1_inv, csr_upd_mask_v_sel_rs1, 
		csr_addr, csr_upd_type, csr_upd_mask_v
	};
	assign dcd_res_mul_div_op_msg_packeted = {
		mul_div_op_b_unsigned, mul_div_op_a_unsigned, 
		mul_div_op_a, mul_div_op_b, mul_res_sel
	};
	
endmodule
