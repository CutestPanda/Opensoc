`timescale 1ns / 1ps
/********************************************************************
本模块: 预译码单元

描述:
对指令进行预译码, 生成以下信息:
	指令类型(是否B指令, 是否JAL指令, 是否JALR指令, 是否CSR读写指令, 是否load指令, 
		是否store指令, 是否乘法指令, 是否除法指令, 是否求余指令)
	跳转偏移量立即数
	通用寄存器索引有效标志(是否需要读rs1, 是否需要读rs2, 是否需要写rd)
	CSR寄存器地址
	rs1索引
	异常标志(非法指令)

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/10/14
********************************************************************/


module panda_risc_v_pre_decoder(
	// 指令输入
	input wire[31:0] inst,
	
	// 预译码信息
	output wire is_b_inst, // 是否B指令
	output wire is_jal_inst, // 是否JAL指令
	output wire is_jalr_inst, // 是否JALR指令
	output wire is_csr_rw_inst, // 是否CSR读写指令
	output wire is_load_inst, // 是否load指令
	output wire is_store_inst, // 是否store指令
	output wire is_mul_inst, // 是否乘法指令
	output wire is_div_inst, // 是否除法指令
	output wire is_rem_inst, // 是否求余指令
	output wire[20:0] jump_ofs_imm, // 跳转偏移量立即数
	output wire rs1_vld, // 是否需要读rs1
	output wire rs2_vld, // 是否需要读rs2
	output wire rd_vld, // 是否需要写rd
	output wire[11:0] csr_addr, // CSR寄存器地址
	output wire[4:0] rs1_id, // RS1索引
	output wire illegal_inst, // 非法指令(标志)
	
	// 打包的预译码信息
	output wire[63:0] pre_decoding_msg_packeted
);
	
	/** 常量 **/
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
	
	/** 打包的预译码信息 **/
	assign pre_decoding_msg_packeted = {
		19'dx,
		// CSR寄存器地址(12bit)
		csr_addr,
		// 读写通用寄存器堆标志(3bit)
		rs1_vld, rs2_vld, rd_vld,
		// 跳转偏移量立即数(21bit)
		jump_ofs_imm,
		// 指令类型标志(9bit)
		is_b_inst, is_jal_inst, is_jalr_inst, is_csr_rw_inst, is_load_inst,
		is_store_inst, is_mul_inst, is_div_inst, is_rem_inst
	};
	
	/** 指令类型预译码 **/
	assign is_b_inst = inst[6:0] == OPCODE_B;
	assign is_jal_inst = inst[6:0] == OPCODE_JAL;
	assign is_jalr_inst = inst[6:0] == OPCODE_JALR;
	assign is_csr_rw_inst = (inst[6:0] == OPCODE_ENV_CSR) & (inst[14:12] != 3'b000);
	assign is_load_inst = inst[6:0] == OPCODE_LD;
	assign is_store_inst = inst[6:0] == OPCODE_STR;
	assign is_mul_inst = (inst[6:0] == OPCODE_ARTH_REG) & inst[25] & (~inst[14]);
	assign is_div_inst = (inst[6:0] == OPCODE_ARTH_REG) & inst[25] & (inst[14:13] == 2'b10);
	assign is_rem_inst = (inst[6:0] == OPCODE_ARTH_REG) & inst[25] & (inst[14:13] == 2'b11);
	
	/**
	跳转偏移量立即数
	
	21位有符号立即数:
		jal  -> inst[31], inst[19:12], inst[20], inst[30:25], inst[24:21], 1'b0
		jalr -> inst[31], {8{inst[31]}}, inst[31], inst[30:25], inst[24:21], inst[20]
		b    -> inst[31], {8{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0
	**/
	wire is_b_inst_fast; // 是否B指令(仅用于快速区分B/JAL/JALR)
	wire is_jal_inst_fast; // 是否JAL指令(仅用于快速区分B/JAL/JALR)
	wire is_jalr_inst_fast; // 是否JALR指令(仅用于快速区分B/JAL/JALR)
	
	assign jump_ofs_imm[20] = inst[31];
	assign jump_ofs_imm[19:12] = is_jal_inst_fast ? inst[19:12]:{8{inst[31]}};
	assign jump_ofs_imm[11] = (is_jal_inst_fast & inst[20]) | (is_jalr_inst_fast & inst[31]) | (is_b_inst_fast & inst[7]);
	assign jump_ofs_imm[10:5] = inst[30:25];
	assign jump_ofs_imm[4:1] = inst[2] ? inst[24:21]:inst[11:8];
	assign jump_ofs_imm[0] = is_jalr_inst_fast & inst[20];
	
	assign is_b_inst_fast = inst[3:2] == 2'b00;
	assign is_jal_inst_fast = inst[3:2] == 2'b11;
	assign is_jalr_inst_fast = inst[3:2] == 2'b01;
	
	/** 通用寄存器索引有效标志 **/
	assign rs1_vld = (inst[6:0] != OPCODE_LUI) & (inst[6:0] != OPCODE_AUIPC) & (inst[6:0] != OPCODE_JAL)
		& (inst[6:0] != OPCODE_FENCE) & (~((inst[6:0] == OPCODE_ENV_CSR) & ((inst[14:12] == 3'b000) | inst[14])));
	assign rs2_vld = (inst[6:0] == OPCODE_B) | (inst[6:0] == OPCODE_STR)
		| (inst[6:0] == OPCODE_ARTH_REG);
	assign rd_vld = (inst[6:0] != OPCODE_B) & (inst[6:0] != OPCODE_STR)
		& (inst[6:0] != OPCODE_FENCE) & (~((inst[6:0] == OPCODE_ENV_CSR) & (inst[14:12] == 3'b000)));
	
	/** CSR寄存器地址 **/
	assign csr_addr = inst[31:20];
	
	/** rs1索引 **/
	assign rs1_id = inst[19:15];
	
	/** 非法指令(标志) **/
	wire is_vld_lui_inst; // 有效的LUI指令(标志)
	wire is_vld_auipc_inst; // 有效的AUIPC指令(标志)
	wire is_vld_jal_inst; // 有效的JAL指令(标志)
	wire is_vld_jalr_inst; // 有效的JALR指令(标志)
	wire is_vld_b_inst; // 有效的B指令(标志)
	wire is_vld_load_inst; // 有效的load指令(标志)
	wire is_vld_store_inst; // 有效的store指令(标志)
	wire is_vld_arth_imm_inst; // 有效的立即数算术指令(标志)
	wire is_vld_arth_reg_inst; // 有效的寄存器算术指令(标志)
	wire is_vld_fench_inst; // 有效的屏障指令(标志)
	wire is_vld_env_csr_inst; // 有效的系统调用或CSR读写指令(标志)
	
	assign illegal_inst = ~(is_vld_lui_inst | is_vld_auipc_inst | is_vld_jal_inst | is_vld_jalr_inst | is_vld_b_inst
		| is_vld_load_inst | is_vld_store_inst | is_vld_arth_imm_inst | is_vld_arth_reg_inst | is_vld_fench_inst
		| is_vld_env_csr_inst);
	
	assign is_vld_lui_inst = inst[6:0] == OPCODE_LUI;
	assign is_vld_auipc_inst = inst[6:0] == OPCODE_AUIPC;
	assign is_vld_jal_inst = inst[6:0] == OPCODE_JAL;
	assign is_vld_jalr_inst = (inst[6:0] == OPCODE_JALR)
		& (inst[14:12] == 3'b000);
	assign is_vld_b_inst = (inst[6:0] == OPCODE_B)
		& (inst[14:12] != 3'b010) & (inst[14:12] != 3'b011);
	assign is_vld_load_inst = (inst[6:0] == OPCODE_LD)
		& (inst[14:12] != 3'b011) & (inst[14:12] != 3'b110) & (inst[14:12] != 3'b111);
	assign is_vld_store_inst = (inst[6:0] == OPCODE_STR)
		& (~inst[14]) & (inst[13:12] != 2'b11);
	assign is_vld_arth_imm_inst = (inst[6:0] == OPCODE_ARTH_IMM)
		& ((inst[14:12] == 3'b000)
			| ((inst[14:12] == 3'b001) & (inst[31:25] == 7'b0000000))
			| (inst[14:12] == 3'b010)
			| (inst[14:12] == 3'b011)
			| (inst[14:12] == 3'b100)
			| ((inst[14:12] == 3'b101) & ({inst[31], inst[29:25]} == 6'b000000))
			| (inst[14:12] == 3'b110)
			| (inst[14:12] == 3'b111)
		);
	assign is_vld_arth_reg_inst = (inst[6:0] == OPCODE_ARTH_REG)
		& (inst[25] ? 
			(inst[31:26] == 6'b000000) // 乘除法指令
			:(((inst[14:12] == 3'b000) & ({inst[31], inst[29:26]} == 5'b00000))
					| ((inst[14:12] == 3'b001) & (inst[31:26] == 6'b000000))
					| ((inst[14:12] == 3'b010) & (inst[31:26] == 6'b000000))
					| ((inst[14:12] == 3'b011) & (inst[31:26] == 6'b000000))
					| ((inst[14:12] == 3'b100) & (inst[31:26] == 6'b000000))
					| ((inst[14:12] == 3'b101) & ({inst[31], inst[29:26]} == 5'b00000))
					| ((inst[14:12] == 3'b110) & (inst[31:26] == 6'b000000))
					| ((inst[14:12] == 3'b111) & (inst[31:26] == 6'b000000))
			) // 普通算术指令
		);
	assign is_vld_fench_inst = (inst[6:0] == OPCODE_FENCE)
		& (((inst[14:12] == 3'b000) & ({inst[31:28], inst[19:15], inst[11:7]} == 14'd0))
			| ((inst[14:12] == 3'b001) & ({inst[31:20], inst[19:15], inst[11:7]} == 22'd0))
		);
	assign is_vld_env_csr_inst = (inst[6:0] == OPCODE_ENV_CSR)
		& (((inst[14:12] == 3'b000) & ({inst[31:21], inst[19:15], inst[11:7]} == 21'd0)) // 系统调用指令
			| (inst[14:12] == 3'b001) | (inst[14:12] == 3'b010) | (inst[14:12] == 3'b011)
				| (inst[14:12] == 3'b101) | (inst[14:12] == 3'b110) | (inst[14:12] == 3'b111) // CSR读写指令
		);
	
endmodule
