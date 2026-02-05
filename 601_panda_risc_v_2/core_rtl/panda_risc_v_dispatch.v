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
本模块: 分发单元

描述:
将已发射的指令输出给交付单元, 同时分发给多个执行单元

纯组合逻辑模块

注意：
无

协议:
无

作者: 陈家耀
日期: 2026/02/05
********************************************************************/


module panda_risc_v_dispatch #(
	parameter integer IBUS_TID_WIDTH = 8 // 指令总线事务ID位宽(1~16)
)(
	// 分发单元输入
	input wire[127:0] s_dsptc_data, // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	input wire[162:0] s_dsptc_msg, // 取指附加信息({分支预测信息(160bit), 错误码(3bit)})
	input wire[143:0] s_dsptc_dcd_res, // 译码信息({打包的FU操作信息(128bit), 打包的指令类型标志(16bit)})
	input wire[IBUS_TID_WIDTH-1:0] s_dsptc_id, // 指令编号
	input wire s_dsptc_is_first_inst_after_rst, // 是否复位释放后的第1条指令
	input wire s_dsptc_valid,
	output wire s_dsptc_ready,
	
	// BRU
	output wire[127:0] m_bru_i_data, // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	output wire[162:0] m_bru_i_msg, // 取指附加信息({分支预测信息(160bit), 错误码(3bit)})
	output wire[143:0] m_bru_i_dcd_res, // 译码信息({打包的FU操作信息(128bit), 打包的指令类型标志(16bit)})
	output wire[IBUS_TID_WIDTH-1:0] m_bru_i_id, // 指令编号
	output wire m_bru_i_valid,
	input wire m_bru_i_ready,
	
	// 执行单元操作信息
	// [ALU]
	output wire[3:0] m_alu_op_mode, // 操作类型
	output wire[31:0] m_alu_op1, // 操作数1
	output wire[31:0] m_alu_op2, // 操作数2
	output wire[IBUS_TID_WIDTH-1:0] m_alu_tid, // 指令ID
	output wire m_alu_use_res, // 是否使用ALU的计算结果
	output wire m_alu_valid,
	// [CSR原子读写]
	output wire[11:0] m_csr_addr, // CSR地址
	output wire[IBUS_TID_WIDTH-1:0] m_csr_tid, // 指令ID
	output wire m_csr_valid,
	// [LSU]
	output wire m_lsu_ls_sel, // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	output wire[2:0] m_lsu_ls_type, // 访存类型
	output wire[4:0] m_lsu_rd_id_for_ld, // 用于加载的目标寄存器的索引
	output wire[31:0] m_lsu_ls_din, // 写数据
	output wire[IBUS_TID_WIDTH-1:0] m_lsu_inst_id, // 指令ID
	output wire m_lsu_valid,
	input wire m_lsu_ready,
	// [乘法器]
	output wire[32:0] m_mul_op_a, // 操作数A
	output wire[32:0] m_mul_op_b, // 操作数B
	output wire m_mul_res_sel, // 乘法结果选择(1'b0 -> 低32位, 1'b1 -> 高32位)
	output wire[4:0] m_mul_rd_id, // RD索引
	output wire[IBUS_TID_WIDTH-1:0] m_mul_inst_id, // 指令ID
	output wire m_mul_valid,
	input wire m_mul_ready,
	// [除法器]
	output wire[32:0] m_div_op_a, // 操作数A(被除数)
	output wire[32:0] m_div_op_b, // 操作数B(除数)
	output wire m_div_rem_sel, // 除法/求余选择(1'b0 -> 除法, 1'b1 -> 求余)
	output wire[4:0] m_div_rd_id, // RD索引
	output wire[IBUS_TID_WIDTH-1:0] m_div_inst_id, // 指令ID
	output wire m_div_valid,
	input wire m_div_ready
);
	
	/** 常量 **/
	// 指令错误码
	localparam INST_ERR_CODE_NORMAL = 3'b000; // 正常
	localparam INST_ERR_CODE_ILLEGAL = 3'b001; // 非法指令
	localparam INST_ERR_CODE_PC_UNALIGNED = 3'b010; // 指令地址非对齐
	localparam INST_ERR_CODE_IMEM_ACCESS_FAILED = 3'b011; // 指令总线访问失败
	localparam INST_ERR_CODE_RD_DBUS_FAILED = 3'b100; // 读存储映射失败
	localparam INST_ERR_CODE_WT_DBUS_FAILED = 3'b101; // 写存储映射失败
	localparam INST_ERR_CODE_RD_DBUS_UNALIGNED = 3'b110; // 读存储映射地址非对齐
	localparam INST_ERR_CODE_WT_DBUS_UNALIGNED = 3'b111; // 写存储映射地址非对齐
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
	// ALU操作类型
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
	
	/** 分发单元输入 **/
	wire fu_ready; // 执行单元就绪(标志)
	
	assign s_dsptc_ready = fu_ready;
	
	assign fu_ready = 
		s_dsptc_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID] | // 非法指令显然不会经过BRU、LSU、乘法器、除法器
		(
			(
				(~(
					s_dsptc_dcd_res[INST_TYPE_FLAG_IS_B_INST_SID] | s_dsptc_dcd_res[INST_TYPE_FLAG_IS_JALR_INST_SID] | 
					s_dsptc_dcd_res[INST_TYPE_FLAG_IS_EBREAK_INST_SID] | s_dsptc_dcd_res[INST_TYPE_FLAG_IS_FENCE_I_INST_SID]
				)) | 
				m_bru_i_ready
			) & // B指令、JALR指令、EBREAK指令或FENCE.I指令需要经过BRU
			(
				(~(s_dsptc_dcd_res[INST_TYPE_FLAG_IS_STORE_INST_SID] | s_dsptc_dcd_res[INST_TYPE_FLAG_IS_LOAD_INST_SID])) | 
				m_lsu_ready
			) & // 访存指令需要经过LSU
			(
				(~s_dsptc_dcd_res[INST_TYPE_FLAG_IS_MUL_INST_SID]) | 
				m_mul_ready
			) & // 乘法指令需要经过乘法器
			(
				(~(s_dsptc_dcd_res[INST_TYPE_FLAG_IS_REM_INST_SID] | s_dsptc_dcd_res[INST_TYPE_FLAG_IS_DIV_INST_SID])) | 
				m_div_ready
			) // 除法/求余指令需要经过除法器
		);
	
	/** 分发给BRU **/
	assign m_bru_i_data = s_dsptc_data;
	assign m_bru_i_msg = s_dsptc_msg;
	assign m_bru_i_dcd_res = s_dsptc_dcd_res;
	assign m_bru_i_id = s_dsptc_id;
	assign m_bru_i_valid = 
		s_dsptc_valid & 
		// 属于B指令、JALR指令、EBREAK指令或FENCE.I指令
		(~s_dsptc_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & 
		(
			s_dsptc_dcd_res[INST_TYPE_FLAG_IS_B_INST_SID] | s_dsptc_dcd_res[INST_TYPE_FLAG_IS_JALR_INST_SID] | 
			s_dsptc_dcd_res[INST_TYPE_FLAG_IS_EBREAK_INST_SID] | s_dsptc_dcd_res[INST_TYPE_FLAG_IS_FENCE_I_INST_SID]
		);
	
	/** 分发给ALU **/
	assign m_alu_op_mode = 
		(
			(~s_dsptc_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & 
			(s_dsptc_dcd_res[INST_TYPE_FLAG_IS_STORE_INST_SID] | s_dsptc_dcd_res[INST_TYPE_FLAG_IS_LOAD_INST_SID])
		) ? 
			OP_MODE_ADD:
			s_dsptc_dcd_res[3+ALU_OP_MSG_OP_MODE_SID+16:ALU_OP_MSG_OP_MODE_SID+16];
	assign m_alu_op1 = 
		(
			(~s_dsptc_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & 
			(s_dsptc_dcd_res[INST_TYPE_FLAG_IS_STORE_INST_SID] | s_dsptc_dcd_res[INST_TYPE_FLAG_IS_LOAD_INST_SID])
		) ? 
			// 实际上选择的FU操作信息的索引是一样的
			s_dsptc_dcd_res[31+LSU_OP_MSG_LS_BASEADDR_SID+16:LSU_OP_MSG_LS_BASEADDR_SID+16]:
			s_dsptc_dcd_res[31+ALU_OP_MSG_OP1_SID+16:ALU_OP_MSG_OP1_SID+16];
	assign m_alu_op2 = 
		(
			(~s_dsptc_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & 
			(s_dsptc_dcd_res[INST_TYPE_FLAG_IS_STORE_INST_SID] | s_dsptc_dcd_res[INST_TYPE_FLAG_IS_LOAD_INST_SID])
		) ? 
			// 实际上选择的FU操作信息的索引是一样的
			s_dsptc_dcd_res[31+LSU_OP_MSG_LS_OFSADDR_SID+16:LSU_OP_MSG_LS_OFSADDR_SID+16]:
			s_dsptc_dcd_res[31+ALU_OP_MSG_OP2_SID+16:ALU_OP_MSG_OP2_SID+16];
	assign m_alu_tid = s_dsptc_id;
	assign m_alu_use_res = 
		// 访存指令会使用ALU来计算访存地址, 但访存地址显然不是访存指令的执行结果
		(~(s_dsptc_dcd_res[INST_TYPE_FLAG_IS_STORE_INST_SID] | s_dsptc_dcd_res[INST_TYPE_FLAG_IS_LOAD_INST_SID]));
	assign m_alu_valid = 
		s_dsptc_valid & 
		// CSR读写指令不用经过ALU
		(~(
			(~s_dsptc_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & s_dsptc_dcd_res[INST_TYPE_FLAG_IS_CSR_RW_INST_SID]
		));
	
	/** 分发给CSR原子读写 **/
	assign m_csr_addr = s_dsptc_dcd_res[11+CSR_RW_OP_MSG_ADDR_SID+16:CSR_RW_OP_MSG_ADDR_SID+16];
	assign m_csr_tid = s_dsptc_id;
	assign m_csr_valid = 
		s_dsptc_valid & 
		// 属于CSR读写指令
		(~s_dsptc_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & s_dsptc_dcd_res[INST_TYPE_FLAG_IS_CSR_RW_INST_SID];
	
	/** 分发给LSU **/
	assign m_lsu_ls_sel = s_dsptc_dcd_res[INST_TYPE_FLAG_IS_STORE_INST_SID];
	assign m_lsu_ls_type = s_dsptc_dcd_res[2+LSU_OP_MSG_LS_TYPE_SID+16:LSU_OP_MSG_LS_TYPE_SID+16];
	assign m_lsu_rd_id_for_ld = 5'bxxxxx; // 目标寄存器编号在ROB中已经保存, 无需在执行单元里传递
	assign m_lsu_ls_din = s_dsptc_dcd_res[31+LSU_OP_MSG_LS_DIN_SID+16:LSU_OP_MSG_LS_DIN_SID+16];
	assign m_lsu_inst_id = s_dsptc_id;
	assign m_lsu_valid = 
		s_dsptc_valid & 
		// 属于访存指令
		(~s_dsptc_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & 
		(s_dsptc_dcd_res[INST_TYPE_FLAG_IS_STORE_INST_SID] | s_dsptc_dcd_res[INST_TYPE_FLAG_IS_LOAD_INST_SID]);
	
	/** 分发给乘法器 **/
	assign m_mul_op_a = s_dsptc_dcd_res[32+MUL_DIV_OP_MSG_OP_A_SID+16:MUL_DIV_OP_MSG_OP_A_SID+16];
	assign m_mul_op_b = s_dsptc_dcd_res[32+MUL_DIV_OP_MSG_OP_B_SID+16:MUL_DIV_OP_MSG_OP_B_SID+16];
	assign m_mul_res_sel = s_dsptc_dcd_res[MUL_DIV_OP_MSG_MUL_RES_SEL_SID+16];
	assign m_mul_rd_id = 5'bxxxxx; // 目标寄存器编号在ROB中已经保存, 无需在执行单元里传递
	assign m_mul_inst_id = s_dsptc_id;
	assign m_mul_valid = 
		s_dsptc_valid & 
		// 属于乘法指令
		(~s_dsptc_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & s_dsptc_dcd_res[INST_TYPE_FLAG_IS_MUL_INST_SID];
	
	/** 分发给除法器 **/
	assign m_div_op_a = s_dsptc_dcd_res[32+MUL_DIV_OP_MSG_OP_A_SID+16:MUL_DIV_OP_MSG_OP_A_SID+16];
	assign m_div_op_b = s_dsptc_dcd_res[32+MUL_DIV_OP_MSG_OP_B_SID+16:MUL_DIV_OP_MSG_OP_B_SID+16];
	assign m_div_rem_sel = s_dsptc_dcd_res[INST_TYPE_FLAG_IS_REM_INST_SID];
	assign m_div_rd_id = 5'bxxxxx; // 目标寄存器编号在ROB中已经保存, 无需在执行单元里传递
	assign m_div_inst_id = s_dsptc_id;
	assign m_div_valid = 
		s_dsptc_valid & 
		// 属于除法/求余指令
		(~s_dsptc_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & 
		(s_dsptc_dcd_res[INST_TYPE_FLAG_IS_REM_INST_SID] | s_dsptc_dcd_res[INST_TYPE_FLAG_IS_DIV_INST_SID]);
	
endmodule
