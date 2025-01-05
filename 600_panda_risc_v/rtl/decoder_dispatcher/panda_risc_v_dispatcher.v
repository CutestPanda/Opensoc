`timescale 1ns / 1ps
/********************************************************************
本模块: 派遣单元

描述:
将译码/读寄存器堆后的指令派遣给EXU(ALU/LSU/CSR原子读写单元/乘法器/除法器)

指令类型  |  派遣到ALU | 派遣到LSU | 派遣到CSR原子读写单元 | 派遣到乘法器 | 派遣到除法器
-----------------------------------------------------------------------------------------
 CSR读写  |    Yes     |           |          Yes          |              |             |
   LS     |    Yes     |    Yes    |                       |              |             |
  乘法    |    Yes     |           |                       |     Yes      |             |
除法/求余 |    Yes     |           |                       |              |     Yes     |
  其他    |    Yes     |           |                       |              |             |

注意：
对于访存地址非对齐的L/S指令, 将不会被派遣到LSU

协议:
无

作者: 陈家耀
日期: 2025/01/05
********************************************************************/


module panda_risc_v_dispatcher(
	// 数据相关性
	// 仅检查待派遣指令的RD索引是否与未交付长指令的RD索引冲突!
	output wire[4:0] raw_dpc_check_rd_id, // 待检查WAW相关性的RD索引
	input wire rd_waw_dpc, // RD有WAW相关性(标志)
	
	// 派遣请求
	/*
	指令类型           复用的派遣信息的内容
	--------------------------------------------
	    L/S         {打包的LSU操作信息[2:0], 
	                     打包的ALU操作信息[67:0]}
	  CSR读写       {打包的CSR原子读写操作信息[45:0]}
	   乘除         {打包的乘除法操作信息[66:0]}
	   非法指令     {取到的指令[31:0]}
	   其他         {是否预测跳转, 
	                     打包的ALU操作信息[67:0]}
	*/
	input wire[70:0] s_dispatch_req_msg_reused, // 复用的派遣信息
	input wire[8:0] s_dispatch_req_inst_type_packeted, // 打包的指令类型标志
	input wire[31:0] s_dispatch_req_pc_of_inst, // 指令对应的PC
	input wire[31:0] s_dispatch_req_brc_pc_upd_store_din, // 分支预测失败时修正的PC或用于写存储映射的数据
	input wire[4:0] s_dispatch_req_rd_id, // RD索引
	input wire s_dispatch_req_rd_vld, // 是否需要写RD
	input wire[2:0] s_dispatch_req_err_code, // 错误类型(3'b000 -> 正常, 3'b001 -> 非法指令, 
	                                         //     3'b010 -> 指令地址非对齐, 3'b011 -> 指令总线访问失败, 
									         //     3'b110 -> 读存储映射地址非对齐, 3'b111 -> 写存储映射地址非对齐)
	input wire s_dispatch_req_valid,
	output wire s_dispatch_req_ready,
	
	// ALU执行请求
	output wire[3:0] m_alu_op_mode, // 操作类型
	output wire[31:0] m_alu_op1, // 操作数1
	output wire[31:0] m_alu_op2, // 操作数2或取到的指令(若当前是非法指令)
	output wire m_alu_addr_gen_sel, // ALU是否用于访存地址生成
	output wire[2:0] m_alu_err_code, // 指令的错误类型(3'b000 -> 正常, 3'b001 -> 非法指令, 
	                                 //     3'b010 -> 指令地址非对齐, 3'b011 -> 指令总线访问失败, 
									 //     3'b110 -> 读存储映射地址非对齐, 3'b111 -> 写存储映射地址非对齐)
	output wire[31:0] m_alu_pc_of_inst, // 指令对应的PC
	output wire m_alu_is_b_inst, // 是否B指令
	output wire m_alu_is_ecall_inst, // 是否ECALL指令
	output wire m_alu_is_mret_inst, // 是否MRET指令
	output wire m_alu_is_csr_rw_inst, // 是否CSR读写指令
	output wire[31:0] m_alu_brc_pc_upd, // 分支预测失败时修正的PC
	output wire m_alu_prdt_jump, // 是否预测跳转
	output wire[4:0] m_alu_rd_id, // RD索引
	output wire m_alu_rd_vld, // 是否需要写RD
	output wire m_alu_is_long_inst, // 是否长指令(L/S, 乘除法)
	output wire m_alu_valid,
	input wire m_alu_ready,
	
	// LSU执行请求
	output wire m_ls_sel, // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	output wire[2:0] m_ls_type, // 访存类型
	output wire[4:0] m_rd_id_for_ld, // 用于加载的目标寄存器的索引
	output wire[31:0] m_ls_din, // 写数据
	output wire m_lsu_valid,
	input wire m_lsu_ready,
	
	// CSR原子读写单元执行请求
	output wire[11:0] m_csr_addr, // CSR地址
	output wire[1:0] m_csr_upd_type, // CSR更新类型
	output wire[31:0] m_csr_upd_mask_v, // CSR更新掩码或更新值
	output wire[4:0] m_csr_rw_rd_id, // RD索引
	output wire m_csr_rw_valid,
	input wire m_csr_rw_ready,
	
	// 乘法器执行请求
	output wire[32:0] m_mul_op_a, // 操作数A
	output wire[32:0] m_mul_op_b, // 操作数B
	output wire m_mul_res_sel, // 乘法结果选择(1'b0 -> 低32位, 1'b1 -> 高32位)
	output wire[4:0] m_mul_rd_id, // RD索引
	output wire m_mul_valid,
	input wire m_mul_ready,
	
	// 除法器执行请求
	output wire[32:0] m_div_op_a, // 操作数A
	output wire[32:0] m_div_op_b, // 操作数B
	output wire m_div_rem_sel, // 除法/求余选择(1'b0 -> 除法, 1'b1 -> 求余)
	output wire[4:0] m_div_rd_id, // RD索引
	output wire m_div_valid,
	input wire m_div_ready
);
	
	/** 常量 **/
	// 打包的指令类型标志各项的起始索引
	localparam integer INST_TYPE_FLAG_IS_MRET_INST_SID = 8;
	localparam integer INST_TYPE_FLAG_IS_ECALL_INST_SID = 7;
	localparam integer INST_TYPE_FLAG_IS_B_INST_SID = 6;
	localparam integer INST_TYPE_FLAG_IS_CSR_RW_INST_SID = 5;
	localparam integer INST_TYPE_FLAG_IS_LOAD_INST_SID = 4;
	localparam integer INST_TYPE_FLAG_IS_STORE_INST_SID = 3;
	localparam integer INST_TYPE_FLAG_IS_MUL_INST_SID = 2;
	localparam integer INST_TYPE_FLAG_IS_DIV_INST_SID = 1;
	localparam integer INST_TYPE_FLAG_IS_REM_INST_SID = 0;
	// 打包的ALU操作信息各项的起始索引
	localparam integer ALU_OP_MSG_ALU_OP_MODE = 64;
	localparam integer ALU_OP_MSG_ALU_OP1 = 32;
	localparam integer ALU_OP_MSG_ALU_OP2 = 0;
	// 打包的LSU操作信息各项的起始索引
	localparam integer LSU_OP_MSG_LS_TYPE = 0;
	// 打包的CSR原子读写操作信息各项的起始索引
	localparam integer CSR_RW_OP_MSG_CSR_ADDR = 34;
	localparam integer CSR_RW_OP_MSG_CSR_UPD_TYPE = 32;
	localparam integer CSR_RW_OP_MSG_CSR_UPD_MASK_V = 0;
	// 打包的乘除法操作信息各项的起始索引
	localparam integer MUL_DIV_OP_MSG_MUL_DIV_OP_A = 34;
	localparam integer MUL_DIV_OP_MSG_MUL_DIV_OP_B = 1;
	localparam integer MUL_DIV_OP_MSG_MUL_RES_SEL = 0;
	// 取指译码错误类型
	localparam INST_FETCH_DCD_NORMAL = 3'b000; // 正常
	localparam INST_FETCH_DCD_ILLEGAL_INST = 3'b001; // 非法指令
	localparam INST_FETCH_DCD_PC_UNALIGNE = 3'b010; // 指令地址非对齐
	localparam INST_FETCH_DCD_BUS_ACCESS_FAILED = 3'b011; // 指令总线访问失败
	localparam INST_FETCH_DCD_LD_ADDR_UNALIGNED = 3'b110; // 读存储映射地址非对齐
	localparam INST_FETCH_DCD_STR_ADDR_UNALIGNED = 3'b111; // 写存储映射地址非对齐
	
	/** 数据相关性 **/
	wire rd_waw_dpc_detected; // 检测到WAW相关性(标志)
	
	assign raw_dpc_check_rd_id = s_dispatch_req_rd_id;
	
	assign rd_waw_dpc_detected = s_dispatch_req_rd_vld & rd_waw_dpc;
	
	/** 复用的派遣信息 **/
	wire[67:0] dispatch_msg_alu_op_msg_packeted; // 打包的ALU操作信息
	wire[2:0] dispatch_msg_lsu_op_msg_packeted; // 打包的LSU操作信息
	wire[45:0] dispatch_msg_csr_rw_op_msg_packeted; // 打包的CSR原子读写操作信息
	wire[66:0] dispatch_msg_mul_div_op_msg_packeted; // 打包的乘除法操作信息
	wire dispatch_req_prdt_jump; // 是否预测跳转
	wire[31:0] dispatch_msg_inst; // 取到的指令
	
	assign dispatch_msg_alu_op_msg_packeted = s_dispatch_req_msg_reused[67:0];
	assign dispatch_msg_lsu_op_msg_packeted = s_dispatch_req_msg_reused[70:68];
	assign dispatch_msg_csr_rw_op_msg_packeted = s_dispatch_req_msg_reused[45:0];
	assign dispatch_msg_mul_div_op_msg_packeted = s_dispatch_req_msg_reused[66:0];
	assign dispatch_req_prdt_jump = s_dispatch_req_msg_reused[68];
	assign dispatch_msg_inst = s_dispatch_req_msg_reused[31:0];
	
	/** 指令类型标志 **/
	wire is_b_inst; // 是否B指令
	wire is_csr_rw_inst; // 是否CSR读写指令
	wire is_ls_inst; // 是否加载/存储指令
	wire is_mul_inst; // 是否乘法指令
	wire is_div_rem_inst; // 是否除法/求余指令
	
	assign is_b_inst = 
		s_dispatch_req_inst_type_packeted[INST_TYPE_FLAG_IS_B_INST_SID];
	assign is_csr_rw_inst = 
		s_dispatch_req_inst_type_packeted[INST_TYPE_FLAG_IS_CSR_RW_INST_SID];
	assign is_ls_inst = 
		s_dispatch_req_inst_type_packeted[INST_TYPE_FLAG_IS_LOAD_INST_SID] | 
		s_dispatch_req_inst_type_packeted[INST_TYPE_FLAG_IS_STORE_INST_SID];
	assign is_mul_inst = 
		s_dispatch_req_inst_type_packeted[INST_TYPE_FLAG_IS_MUL_INST_SID];
	assign is_div_rem_inst = 
		s_dispatch_req_inst_type_packeted[INST_TYPE_FLAG_IS_DIV_INST_SID] | 
		s_dispatch_req_inst_type_packeted[INST_TYPE_FLAG_IS_REM_INST_SID];
	
	/** 派遣控制 **/
	// 派遣请求
	assign s_dispatch_req_ready = 
		(~rd_waw_dpc_detected) & // RD存在WAW相关性时不派遣指令
		m_alu_ready & // 所有指令均经过ALU, 需要确保ALU就绪
		(
			((~is_ls_inst) | s_dispatch_req_err_code[2] | m_lsu_ready) & // 仅加载/存储指令需要用到LSU, 访存地址非对齐时不派遣到LSU
			((~is_csr_rw_inst) | m_csr_rw_ready) & // 仅CSR读写指令需要用到CSR原子读写单元
			((~is_mul_inst) | m_mul_ready) & // 仅乘法指令需要用到乘法器
			((~is_div_rem_inst) | m_div_ready) // 仅除法/求余指令需要用到除法器
		);
	
	// 派遣给ALU
	assign m_alu_op_mode = dispatch_msg_alu_op_msg_packeted[ALU_OP_MSG_ALU_OP_MODE+3:ALU_OP_MSG_ALU_OP_MODE];
	assign m_alu_op1 = dispatch_msg_alu_op_msg_packeted[ALU_OP_MSG_ALU_OP1+31:ALU_OP_MSG_ALU_OP1];
	assign m_alu_op2 = dispatch_msg_alu_op_msg_packeted[ALU_OP_MSG_ALU_OP2+31:ALU_OP_MSG_ALU_OP2];
	assign m_alu_addr_gen_sel = is_ls_inst;
	assign m_alu_err_code = s_dispatch_req_err_code;
	assign m_alu_pc_of_inst = s_dispatch_req_pc_of_inst;
	assign m_alu_is_b_inst = is_b_inst;
	assign m_alu_is_ecall_inst = s_dispatch_req_inst_type_packeted[INST_TYPE_FLAG_IS_ECALL_INST_SID];
	assign m_alu_is_mret_inst = s_dispatch_req_inst_type_packeted[INST_TYPE_FLAG_IS_MRET_INST_SID];
	assign m_alu_is_csr_rw_inst = is_csr_rw_inst;
	assign m_alu_brc_pc_upd = s_dispatch_req_brc_pc_upd_store_din; // 分支预测失败时修正的PC
	assign m_alu_prdt_jump = dispatch_req_prdt_jump;
	assign m_alu_rd_id = s_dispatch_req_rd_id;
	assign m_alu_rd_vld = s_dispatch_req_rd_vld;
	assign m_alu_is_long_inst = 
		s_dispatch_req_inst_type_packeted[INST_TYPE_FLAG_IS_LOAD_INST_SID] | 
		s_dispatch_req_inst_type_packeted[INST_TYPE_FLAG_IS_STORE_INST_SID] | 
		s_dispatch_req_inst_type_packeted[INST_TYPE_FLAG_IS_MUL_INST_SID] | 
		s_dispatch_req_inst_type_packeted[INST_TYPE_FLAG_IS_DIV_INST_SID] | 
		s_dispatch_req_inst_type_packeted[INST_TYPE_FLAG_IS_REM_INST_SID];
	assign m_alu_valid = 
		s_dispatch_req_valid & // 派遣请求有效
		(~rd_waw_dpc_detected) & // RD存在WAW相关性时不派遣指令
		(
			(is_ls_inst & (s_dispatch_req_err_code[2] | m_lsu_ready)) | // 若为加载/存储指令, 除非访存地址非对齐, 
			                                                            // 否则需要确保ALU执行请求和LSU执行请求同时握手
			(is_csr_rw_inst & m_csr_rw_ready) | // 若为CSR读写指令, 需要确保ALU执行请求和CSR原子读写单元执行请求同时握手
			(is_mul_inst & m_mul_ready) | // 若为乘法指令, 需要确保ALU执行请求和乘法器执行请求同时握手
			(is_div_rem_inst & m_div_ready) | // 若为除法/求余指令, 需要确保ALU执行请求和除法器执行请求同时握手
			(~(is_ls_inst | is_csr_rw_inst | is_mul_inst | is_div_rem_inst))
		);
	
	// 派遣给LSU
	assign m_ls_sel = s_dispatch_req_inst_type_packeted[INST_TYPE_FLAG_IS_STORE_INST_SID];
	assign m_ls_type = dispatch_msg_lsu_op_msg_packeted[LSU_OP_MSG_LS_TYPE+2:LSU_OP_MSG_LS_TYPE];
	assign m_rd_id_for_ld = s_dispatch_req_rd_id;
	assign m_ls_din = s_dispatch_req_brc_pc_upd_store_din; // 用于写存储映射的数据
	assign m_lsu_valid = 
		s_dispatch_req_valid & // 派遣请求有效
		(~rd_waw_dpc_detected) & // RD存在WAW相关性时不派遣指令
		is_ls_inst & // 当前派遣加载/存储指令
		(~s_dispatch_req_err_code[2]) & // 访存地址非对齐时不派遣到LSU
		m_alu_ready; // 所有指令均经过ALU, 需要确保ALU就绪
	
	// 派遣给CSR原子读写单元
	assign m_csr_addr = dispatch_msg_csr_rw_op_msg_packeted[CSR_RW_OP_MSG_CSR_ADDR+11:CSR_RW_OP_MSG_CSR_ADDR];
	assign m_csr_upd_type = dispatch_msg_csr_rw_op_msg_packeted[CSR_RW_OP_MSG_CSR_UPD_TYPE+1:CSR_RW_OP_MSG_CSR_UPD_TYPE];
	assign m_csr_upd_mask_v = dispatch_msg_csr_rw_op_msg_packeted[CSR_RW_OP_MSG_CSR_UPD_MASK_V+31:CSR_RW_OP_MSG_CSR_UPD_MASK_V];
	assign m_csr_rw_rd_id = s_dispatch_req_rd_id;
	assign m_csr_rw_valid = 
		s_dispatch_req_valid & // 派遣请求有效
		(~rd_waw_dpc_detected) & // RD存在WAW相关性时不派遣指令
		is_csr_rw_inst & // 当前派遣CSR读写指令
		m_alu_ready; // 所有指令均经过ALU, 需要确保ALU就绪
	
	// 派遣给乘法器
	assign m_mul_op_a = dispatch_msg_mul_div_op_msg_packeted[MUL_DIV_OP_MSG_MUL_DIV_OP_A+32:MUL_DIV_OP_MSG_MUL_DIV_OP_A];
	assign m_mul_op_b = dispatch_msg_mul_div_op_msg_packeted[MUL_DIV_OP_MSG_MUL_DIV_OP_B+32:MUL_DIV_OP_MSG_MUL_DIV_OP_B];
	assign m_mul_res_sel = dispatch_msg_mul_div_op_msg_packeted[MUL_DIV_OP_MSG_MUL_RES_SEL];
	assign m_mul_rd_id = s_dispatch_req_rd_id;
	assign m_mul_valid = 
		s_dispatch_req_valid & // 派遣请求有效
		(~rd_waw_dpc_detected) & // RD存在WAW相关性时不派遣指令
		is_mul_inst & // 当前派遣乘法指令
		m_alu_ready; // 所有指令均经过ALU, 需要确保ALU就绪
	
	// 派遣给除法器
	assign m_div_op_a = dispatch_msg_mul_div_op_msg_packeted[MUL_DIV_OP_MSG_MUL_DIV_OP_A+32:MUL_DIV_OP_MSG_MUL_DIV_OP_A];
	assign m_div_op_b = dispatch_msg_mul_div_op_msg_packeted[MUL_DIV_OP_MSG_MUL_DIV_OP_B+32:MUL_DIV_OP_MSG_MUL_DIV_OP_B];
	assign m_div_rem_sel = s_dispatch_req_inst_type_packeted[INST_TYPE_FLAG_IS_REM_INST_SID];
	assign m_div_rd_id = s_dispatch_req_rd_id;
	assign m_div_valid = 
		s_dispatch_req_valid & // 派遣请求有效
		(~rd_waw_dpc_detected) & // RD存在WAW相关性时不派遣指令
		is_div_rem_inst & // 当前派遣除法/求余指令
		m_alu_ready; // 所有指令均经过ALU, 需要确保ALU就绪
	
endmodule
