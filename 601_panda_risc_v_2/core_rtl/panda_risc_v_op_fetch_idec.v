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
本模块: 取操作数和指令译码

描述:
接收前级的"取指结果", 根据ROB给出的数据相关性检查端口取2个操作数, 并作指令译码

取操作数的位置 -> 
	通用寄存器堆
	ROB暂存的执行结果
	旁路网络

复位/冲刷时不接收前级的"取指结果", 也不取操作数, 并复位"选择锁存的操作数标志"

注意：
"访存地址非对齐异常"可以在LSU中再生成

协议:
无

作者: 陈家耀
日期: 2026/01/25
********************************************************************/


module panda_risc_v_op_fetch_idec #(
	parameter integer IBUS_TID_WIDTH = 8, // 指令总线事务ID位宽(1~16)
	parameter integer LSN_FU_N = 5, // 要监听结果的执行单元的个数(正整数)
	parameter integer FU_ID_WIDTH = 8, // 执行单元ID位宽(1~16)
	parameter integer FU_RES_WIDTH = 32, // 执行单元结果位宽(正整数)
	parameter GEN_LS_ADDR_UNALIGNED_EXPT = "false", // 是否考虑访存地址非对齐异常
	parameter OP_PRE_FTC = "true", // 操作数已预取
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 复位/冲刷
	input wire sys_reset_req, // 系统复位请求
	input wire flush_req, // 冲刷请求
	
	// 取指结果
	input wire[127:0] s_if_res_data, // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	input wire[98:0] s_if_res_msg, // 取指附加信息({分支预测信息(96bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	input wire[IBUS_TID_WIDTH-1:0] s_if_res_id, // 指令ID
	input wire s_if_res_is_first_inst_after_rst, // 是否复位释放后的第1条指令
	// 说明: 仅当(OP_PRE_FTC == "true")时使用
	input wire[129:0] s_if_res_op, // 预取的操作数({操作数1已取得(1bit), 操作数2已取得(1bit), 
	                               //   操作数1(32bit), 操作数2(32bit), 用于取操作数1的执行单元ID(16bit), 用于取操作数2的执行单元ID(16bit), 
								   //   用于取操作数1的指令ID(16bit), 用于取操作数2的指令ID(16bit)})
	// 说明: 仅当(OP_PRE_FTC == "true")时使用
	input wire[FU_ID_WIDTH-1:0] s_if_res_fuid, // 执行单元ID
	input wire s_if_res_valid,
	output wire s_if_res_ready,
	
	// 取操作数和译码结果
	output wire[127:0] m_op_ftc_id_res_data, // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	output wire[162:0] m_op_ftc_id_res_msg, // 取指附加信息({分支预测信息(160bit), 错误码(3bit)})
	output wire[143:0] m_op_ftc_id_res_dcd_res, // 译码信息({打包的FU操作信息(128bit), 打包的指令类型标志(16bit)})
	output wire[IBUS_TID_WIDTH-1:0] m_op_ftc_id_res_id, // 指令ID
	output wire m_op_ftc_id_res_is_first_inst_after_rst, // 是否复位释放后的第1条指令
	output wire[31:0] m_op_ftc_id_res_op1, // 操作数1
	output wire[31:0] m_op_ftc_id_res_op2, // 操作数2
	output wire m_op_ftc_id_res_valid,
	input wire m_op_ftc_id_res_ready,
	
	// 发射阶段分支信息广播
	output wire brc_bdcst_luc_vld, // 广播有效
	output wire[IBUS_TID_WIDTH-1:0] brc_bdcst_luc_tid, // 事务ID
	output wire brc_bdcst_luc_is_b_inst, // 是否B指令
	output wire brc_bdcst_luc_is_jal_inst, // 是否JAL指令
	output wire brc_bdcst_luc_is_jalr_inst, // 是否JALR指令
	output wire[31:0] brc_bdcst_luc_bta, // 分支目标地址
	
	// 发射阶段ROB记录广播
	output wire rob_luc_bdcst_vld, // 广播有效
	output wire[IBUS_TID_WIDTH-1:0] rob_luc_bdcst_tid, // 指令ID
	output wire[FU_ID_WIDTH-1:0] rob_luc_bdcst_fuid, // 被发射到的执行单元ID
	output wire[4:0] rob_luc_bdcst_rd_id, // 目的寄存器编号
	output wire rob_luc_bdcst_is_ls_inst, // 是否加载/存储指令
	output wire rob_luc_bdcst_is_csr_rw_inst, // 是否CSR读写指令
	output wire[45:0] rob_luc_bdcst_csr_rw_inst_msg, // CSR读写指令信息({CSR写地址(12bit), CSR更新类型(2bit), CSR更新掩码或更新值(32bit)})
	output wire[2:0] rob_luc_bdcst_err, // 错误类型
	output wire[2:0] rob_luc_bdcst_spec_inst_type, // 特殊指令类型
	
	// 数据相关性检查
	// [操作数1]
	output wire[4:0] op1_ftc_rs1_id, // 1号源寄存器编号
	input wire op1_ftc_from_reg_file, // 从寄存器堆取到操作数(标志)
	input wire op1_ftc_from_rob, // 从ROB取到操作数(标志)
	input wire op1_ftc_from_byp, // 从旁路网络取到操作数(标志)
	input wire[FU_ID_WIDTH-1:0] op1_ftc_fuid, // 待旁路的执行单元编号
	input wire[IBUS_TID_WIDTH-1:0] op1_ftc_tid, // 待旁路的指令ID
	input wire[FU_RES_WIDTH-1:0] op1_ftc_rob_saved_data, // ROB暂存的执行结果
	// [操作数2]
	output wire[4:0] op2_ftc_rs2_id, // 2号源寄存器编号
	input wire op2_ftc_from_reg_file, // 从寄存器堆取到操作数(标志)
	input wire op2_ftc_from_rob, // 从ROB取到操作数(标志)
	input wire op2_ftc_from_byp, // 从旁路网络取到操作数(标志)
	input wire[FU_ID_WIDTH-1:0] op2_ftc_fuid, // 待旁路的执行单元编号
	input wire[IBUS_TID_WIDTH-1:0] op2_ftc_tid, // 待旁路的指令ID
	input wire[FU_RES_WIDTH-1:0] op2_ftc_rob_saved_data, // ROB暂存的执行结果
	
	// 执行单元结果旁路使能
	// 说明: 仅当(OP_PRE_FTC == "false")时使用
	input wire[LSN_FU_N-1:0] fu_res_bypass_en,
	
	// 执行单元结果返回
	input wire[LSN_FU_N-1:0] fu_res_vld, // 有效标志
	input wire[LSN_FU_N*IBUS_TID_WIDTH-1:0] fu_res_tid, // 指令ID
	input wire[LSN_FU_N*FU_RES_WIDTH-1:0] fu_res_data, // 执行结果
	
	// 通用寄存器堆读端口#0
	output wire[4:0] reg_file_raddr_p0,
	input wire[31:0] reg_file_dout_p0,
	// 通用寄存器堆读端口#1
	output wire[4:0] reg_file_raddr_p1,
	input wire[31:0] reg_file_dout_p1
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
	// 分支预测信息各字段的起始索引
	localparam integer PRDT_MSG_TARGET_ADDR_SID = 0; // 跳转地址
	localparam integer PRDT_MSG_BTYPE_SID = 32; // 分支指令类型
	localparam integer PRDT_MSG_IS_TAKEN_SID = 35; // 是否跳转
	localparam integer PRDT_MSG_BTB_HIT_SID = 36; // BTB命中
	localparam integer PRDT_MSG_BTB_WID_SID = 37; // BTB命中的缓存路编号
	localparam integer PRDT_MSG_BTB_WVLD_SID = 39; // BTB缓存路有效标志
	localparam integer PRDT_MSG_GLB_SAT_CNT_SID = 43; // 全局历史分支预测给出的2bit饱和计数器
	localparam integer PRDT_MSG_BTB_BTA_SID = 45; // BTB分支目标地址
	localparam integer PRDT_MSG_PUSH_RAS_SID = 77; // RAS压栈标志
	localparam integer PRDT_MSG_POP_RAS_SID = 78; // RAS出栈标志
	localparam integer PRDT_MSG_BHR_SID = 79; // BHR
	localparam integer PRDT_MSG_ACTUAL_BTA_SID = 95; // 实际的分支目标地址
	localparam integer PRDT_MSG_NXT_SEQ_PC_SID = 127; // 顺序取指时的下一PC
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
	// 预取的操作数各项的起始索引
	localparam integer PFTC_OP_OP2_TID = 0; // 用于取操作数2的指令ID
	localparam integer PFTC_OP_OP1_TID = 16; // 用于取操作数1的指令ID
	localparam integer PFTC_OP_OP2_FUID = 32; // 用于取操作数2的执行单元ID
	localparam integer PFTC_OP_OP1_FUID = 48; // 用于取操作数1的执行单元ID
	localparam integer PFTC_OP_OP2 = 64; // 操作数2
	localparam integer PFTC_OP_OP1 = 96; // 操作数1
	localparam integer PFTC_OP_OP2_VLD = 128; // 操作数2已取得
	localparam integer PFTC_OP_OP1_VLD = 129; // 操作数1已取得
	// 指令错误码
	localparam INST_ERR_CODE_NORMAL = 3'b000; // 正常
	localparam INST_ERR_CODE_ILLEGAL = 3'b001; // 非法指令
	localparam INST_ERR_CODE_PC_UNALIGNED = 3'b010; // 指令地址非对齐
	localparam INST_ERR_CODE_IMEM_ACCESS_FAILED = 3'b011; // 指令总线访问失败
	localparam INST_ERR_CODE_RD_DBUS_FAILED = 3'b100; // 读存储映射失败
	localparam INST_ERR_CODE_WT_DBUS_FAILED = 3'b101; // 写存储映射失败
	localparam INST_ERR_CODE_RD_DBUS_UNALIGNED = 3'b110; // 读存储映射地址非对齐
	localparam INST_ERR_CODE_WT_DBUS_UNALIGNED = 3'b111; // 写存储映射地址非对齐
	// 指令总线访问错误码
	localparam IBUS_ACCESS_NORMAL = 2'b00; // 正常
	localparam IBUS_ACCESS_PC_UNALIGNED = 2'b01; // 指令地址非对齐
	localparam IBUS_ACCESS_BUS_ERR = 2'b10; // 指令总线访问错误
	localparam IBUS_ACCESS_TIMEOUT = 2'b11; // 响应超时
	// 分支指令类型常量
	localparam BRANCH_TYPE_JAL = 3'b000; // JAL指令
	localparam BRANCH_TYPE_JALR = 3'b001; // JALR指令
	localparam BRANCH_TYPE_B = 3'b010; // B指令
	// 各个执行单元的ID
	localparam integer FU_ALU_ID = 0; // ALU
	localparam integer FU_CSR_ID = 1; // CSR
	localparam integer FU_LSU_ID = 2; // LSU
	localparam integer FU_MUL_ID = 3; // 乘法器
	localparam integer FU_DIV_ID = 4; // 除法器
	// 特殊指令类型
	localparam SPEC_INST_TYPE_NONE = 3'b000; // 非特殊指令
	localparam SPEC_INST_TYPE_ECALL = 3'b100; // ECALL指令
	localparam SPEC_INST_TYPE_EBREAK = 3'b101; // EBREAK指令
	localparam SPEC_INST_TYPE_MRET = 3'b110; // MRET指令
	localparam SPEC_INST_TYPE_DRET = 3'b111; // DRET指令
	
	/** 执行单元结果返回(数组) **/
	wire fu_res_vld_arr[0:LSN_FU_N-1]; // 有效标志
	wire[IBUS_TID_WIDTH-1:0] fu_res_tid_arr[0:LSN_FU_N-1]; // 指令ID
	wire[FU_RES_WIDTH-1:0] fu_res_data_arr[0:LSN_FU_N-1]; // 执行结果
	
	genvar fu_i;
	generate
		for(fu_i = 0;fu_i < LSN_FU_N;fu_i = fu_i + 1)
		begin:fu_res_lsn_blk
			assign fu_res_vld_arr[fu_i] = 
				((OP_PRE_FTC == "true") | fu_res_bypass_en[fu_i]) & 
				fu_res_vld[fu_i];
			assign fu_res_tid_arr[fu_i] = 
				fu_res_tid[(fu_i+1)*IBUS_TID_WIDTH-1:fu_i*IBUS_TID_WIDTH];
			assign fu_res_data_arr[fu_i] = 
				fu_res_data[(fu_i+1)*FU_RES_WIDTH-1:fu_i*FU_RES_WIDTH];
		end
	endgenerate
	
	/** 取操作数 **/
	wire on_rst_flush; // 正在复位/冲刷(指示)
	wire on_op1_fetch_from_bypass_network; // 操作数1从旁路网络得到执行结果(指示)
	wire on_op2_fetch_from_bypass_network; // 操作数2从旁路网络得到执行结果(指示)
	wire on_op1_fetch; // 取得操作数1(指示)
	wire on_op2_fetch; // 取得操作数2(指示)
	wire op1_no_need; // 无需操作数1(指示)
	wire op2_no_need; // 无需操作数2(指示)
	wire[31:0] op1_fetch_cur; // 当前取到得操作数1
	wire[31:0] op2_fetch_cur; // 当前取到得操作数2
	wire op1_ready; // 操作数1准备好(标志)
	wire op2_ready; // 操作数2准备好(标志)
	reg[31:0] op1_latched; // 锁存的操作数1
	reg[31:0] op2_latched; // 锁存的操作数2
	reg to_sel_op1_latched; // 选择锁存的操作数1(标志)
	reg to_sel_op2_latched; // 选择锁存的操作数2(标志)
	
	assign op1_ftc_rs1_id = 
		(OP_PRE_FTC == "true") ? 
			5'b00000:
			s_if_res_data[19:15];
	assign op2_ftc_rs2_id = 
		(OP_PRE_FTC == "true") ? 
			5'b00000:
			s_if_res_data[24:20];
	
	assign reg_file_raddr_p0 = 
		(OP_PRE_FTC == "true") ? 
			5'b00000:
			s_if_res_data[19:15];
	assign reg_file_raddr_p1 = 
		(OP_PRE_FTC == "true") ? 
			5'b00000:
			s_if_res_data[24:20];
	
	assign on_rst_flush = sys_reset_req | flush_req;
	
	assign on_op1_fetch_from_bypass_network = 
		(OP_PRE_FTC == "true") ? 
			(
				fu_res_vld_arr[s_if_res_op[FU_ID_WIDTH-1+PFTC_OP_OP1_FUID:PFTC_OP_OP1_FUID]] & 
				(
					fu_res_tid_arr[s_if_res_op[FU_ID_WIDTH-1+PFTC_OP_OP1_FUID:PFTC_OP_OP1_FUID]] == 
						s_if_res_op[IBUS_TID_WIDTH-1+PFTC_OP_OP1_TID:PFTC_OP_OP1_TID]
				)
			):
			(
				fu_res_vld_arr[op1_ftc_fuid] & 
				(fu_res_tid_arr[op1_ftc_fuid] == op1_ftc_tid)
			);
	assign on_op2_fetch_from_bypass_network = 
		(OP_PRE_FTC == "true") ? 
			(
				fu_res_vld_arr[s_if_res_op[FU_ID_WIDTH-1+PFTC_OP_OP2_FUID:PFTC_OP_OP2_FUID]] & 
				(
					fu_res_tid_arr[s_if_res_op[FU_ID_WIDTH-1+PFTC_OP_OP2_FUID:PFTC_OP_OP2_FUID]] == 
						s_if_res_op[IBUS_TID_WIDTH-1+PFTC_OP_OP2_TID:PFTC_OP_OP2_TID]
				)
			):
			(
				fu_res_vld_arr[op2_ftc_fuid] & 
				(fu_res_tid_arr[op2_ftc_fuid] == op2_ftc_tid)
			);
	
	assign on_op1_fetch = 
		(OP_PRE_FTC == "true") ? 
			(s_if_res_op[PFTC_OP_OP1_VLD] | on_op1_fetch_from_bypass_network):
			(
				op1_ftc_from_reg_file | 
				op1_ftc_from_rob | 
				(op1_ftc_from_byp & on_op1_fetch_from_bypass_network)
			);
	assign on_op2_fetch = 
		(OP_PRE_FTC == "true") ? 
			(s_if_res_op[PFTC_OP_OP2_VLD] | on_op2_fetch_from_bypass_network):
			(
				op2_ftc_from_reg_file | 
				op2_ftc_from_rob | 
				(op2_ftc_from_byp & on_op2_fetch_from_bypass_network)
			);
	
	assign op1_no_need = 
		s_if_res_data[32+PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID] | (~s_if_res_data[32+PRE_DCD_MSG_RS1_VLD_SID]);
	assign op2_no_need = 
		s_if_res_data[32+PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID] | (~s_if_res_data[32+PRE_DCD_MSG_RS2_VLD_SID]);
	
	assign op1_fetch_cur = 
		(OP_PRE_FTC == "true") ? 
			(
				s_if_res_op[PFTC_OP_OP1_VLD] ? 
					s_if_res_op[31+PFTC_OP_OP1:PFTC_OP_OP1]:
					fu_res_data_arr[s_if_res_op[FU_ID_WIDTH-1+PFTC_OP_OP1_FUID:PFTC_OP_OP1_FUID]][31:0]
			):
			(
				({32{op1_ftc_from_reg_file}} & reg_file_dout_p0) | 
				({32{op1_ftc_from_rob}} & op1_ftc_rob_saved_data[31:0]) | 
				({32{op1_ftc_from_byp}} & fu_res_data_arr[op1_ftc_fuid][31:0])
			);
	assign op2_fetch_cur = 
		(OP_PRE_FTC == "true") ? 
			(
				s_if_res_op[PFTC_OP_OP2_VLD] ? 
					s_if_res_op[31+PFTC_OP_OP2:PFTC_OP_OP2]:
					fu_res_data_arr[s_if_res_op[FU_ID_WIDTH-1+PFTC_OP_OP2_FUID:PFTC_OP_OP2_FUID]][31:0]
			):
			(
				({32{op2_ftc_from_reg_file}} & reg_file_dout_p1) | 
				({32{op2_ftc_from_rob}} & op2_ftc_rob_saved_data[31:0]) | 
				({32{op2_ftc_from_byp}} & fu_res_data_arr[op2_ftc_fuid][31:0])
			);
	
	assign op1_ready = op1_no_need | to_sel_op1_latched | on_op1_fetch;
	assign op2_ready = op2_no_need | to_sel_op2_latched | on_op2_fetch;
	
	// 锁存的操作数1
	always @(posedge aclk)
	begin
		if((~to_sel_op1_latched) & s_if_res_valid & (~op1_no_need) & on_op1_fetch)
			op1_latched <= # SIM_DELAY op1_fetch_cur;
	end
	// 锁存的操作数2
	always @(posedge aclk)
	begin
		if((~to_sel_op2_latched) & s_if_res_valid & (~op2_no_need) & on_op2_fetch)
			op2_latched <= # SIM_DELAY op2_fetch_cur;
	end
	
	// 选择锁存的操作数1(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			to_sel_op1_latched <= 1'b0;
		else
			to_sel_op1_latched <= # SIM_DELAY 
				(~on_rst_flush) & (
					/*
					to_sel_op1_latched ? 
						(~(m_op_ftc_id_res_ready & op2_ready)):
						((~(m_op_ftc_id_res_ready & op2_ready)) & s_if_res_valid & (~op1_no_need) & on_op1_fetch)
					*/
					(~(m_op_ftc_id_res_ready & op2_ready)) & 
					(to_sel_op1_latched | (s_if_res_valid & (~op1_no_need) & on_op1_fetch))
				);
	end
	// 选择锁存的操作数2(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			to_sel_op2_latched <= 1'b0;
		else
			to_sel_op2_latched <= # SIM_DELAY 
				(~on_rst_flush) & (
					/*
					to_sel_op2_latched ? 
						(~(m_op_ftc_id_res_ready & op1_ready)):
						((~(m_op_ftc_id_res_ready & op1_ready)) & s_if_res_valid & (~op2_no_need) & on_op2_fetch)
					*/
					(~(m_op_ftc_id_res_ready & op1_ready)) & 
					(to_sel_op2_latched | (s_if_res_valid & (~op2_no_need) & on_op2_fetch))
				);
	end
	
	/** 指令译码 **/
	wire is_csr_rw_inst; // 是否CSR读写指令
	wire is_load_inst; // 是否load指令
	wire is_store_inst; // 是否store指令
	wire is_mul_inst; // 是否乘法指令
	wire is_div_inst; // 是否除法指令
	wire is_rem_inst; // 是否求余指令
	wire is_ecall_inst; // 是否ECALL指令
	wire is_mret_inst; // 是否MRET指令
	wire is_ebreak_inst; // 是否EBREAK指令
	wire is_dret_inst; // 是否DRET指令
	wire is_illegal_inst; // 是否非法指令
	wire ls_addr_aligned; // 访存地址对齐(标志)
	wire[31:0] actual_bta; // 实际的分支目标地址
	wire[31:0] nxt_seq_pc; // 顺序取指时的下一PC
	wire[15:0] dcd_res_inst_type_packeted; // 打包的指令类型标志
	wire[69:0] dcd_res_alu_op_msg_packeted; // 打包的ALU操作信息
	wire[98:0] dcd_res_lsu_op_msg_packeted; // 打包的LSU操作信息
	wire[47:0] dcd_res_csr_rw_op_msg_packeted; // 打包的CSR原子读写操作信息
	wire[68:0] dcd_res_mul_div_op_msg_packeted; // 打包的乘除法操作信息
	wire[31:0] prdt_addr_corrected; // 修正的预测地址
	
	// 握手条件: (~on_rst_flush) & s_if_res_valid & m_op_ftc_id_res_ready & op1_ready & op2_ready
	assign s_if_res_ready = 
		(~on_rst_flush) & m_op_ftc_id_res_ready & op1_ready & op2_ready;
	
	assign m_op_ftc_id_res_data = {
		s_if_res_data[127:96], // 指令对应的PC
		s_if_res_data[95:32], // 打包的预译码信息
		s_if_res_data[31:0] // 取到的指令
	};
	
	assign m_op_ftc_id_res_msg[162:3] = 
		{
			nxt_seq_pc[31:0], // 顺序取指时的下一PC
			actual_bta[31:0], // 实际的分支目标地址
			s_if_res_msg[15+PRDT_MSG_BHR_SID+3:PRDT_MSG_BHR_SID+3], // BHR
			s_if_res_msg[PRDT_MSG_POP_RAS_SID+3:PRDT_MSG_POP_RAS_SID+3], // RAS出栈标志
			s_if_res_msg[PRDT_MSG_PUSH_RAS_SID+3:PRDT_MSG_PUSH_RAS_SID+3], // RAS压栈标志
			s_if_res_msg[31+PRDT_MSG_BTB_BTA_SID+3:PRDT_MSG_BTB_BTA_SID+3], // BTB分支目标地址
			s_if_res_msg[1+PRDT_MSG_GLB_SAT_CNT_SID+3:PRDT_MSG_GLB_SAT_CNT_SID+3], // 全局历史分支预测给出的2bit饱和计数器
			s_if_res_msg[3+PRDT_MSG_BTB_WVLD_SID+3:PRDT_MSG_BTB_WVLD_SID+3], // BTB缓存路有效标志
			s_if_res_msg[1+PRDT_MSG_BTB_WID_SID+3:PRDT_MSG_BTB_WID_SID+3], // BTB命中的缓存路编号
			s_if_res_msg[PRDT_MSG_BTB_HIT_SID+3:PRDT_MSG_BTB_HIT_SID+3], // BTB命中
			s_if_res_msg[PRDT_MSG_IS_TAKEN_SID+3:PRDT_MSG_IS_TAKEN_SID+3], // 是否跳转
			s_if_res_msg[2+PRDT_MSG_BTYPE_SID+3:PRDT_MSG_BTYPE_SID+3], // 分支指令类型
			prdt_addr_corrected // 跳转地址
		} | 160'd0; // 分支预测信息
	assign m_op_ftc_id_res_msg[2:0] = 
		// 正常
		({3{(~is_illegal_inst) & (s_if_res_msg[1:0] == IBUS_ACCESS_NORMAL) & 
			((GEN_LS_ADDR_UNALIGNED_EXPT == "false") | (~(is_load_inst | is_store_inst)) | ls_addr_aligned)}} & 
			INST_ERR_CODE_NORMAL) | 
		// 非法指令
		({3{is_illegal_inst}} & INST_ERR_CODE_ILLEGAL) | 
		// 指令地址非对齐
		({3{s_if_res_msg[1:0] == IBUS_ACCESS_PC_UNALIGNED}} & INST_ERR_CODE_PC_UNALIGNED) | 
		// 指令总线访问失败
		({3{(s_if_res_msg[1:0] == IBUS_ACCESS_BUS_ERR) | (s_if_res_msg[1:0] == IBUS_ACCESS_TIMEOUT)}} & 
			INST_ERR_CODE_IMEM_ACCESS_FAILED) | 
		// 读存储映射地址非对齐
		({3{(GEN_LS_ADDR_UNALIGNED_EXPT == "true") & (~is_illegal_inst) & is_load_inst & (~ls_addr_aligned)}} & 
			INST_ERR_CODE_RD_DBUS_UNALIGNED) | 
		// 写存储映射地址非对齐
		({3{(GEN_LS_ADDR_UNALIGNED_EXPT == "true") & (~is_illegal_inst) & is_store_inst & (~ls_addr_aligned)}} & 
			INST_ERR_CODE_WT_DBUS_UNALIGNED); // 错误码
	assign m_op_ftc_id_res_dcd_res[143:16] = 
		({128{is_illegal_inst | 
			(~(is_load_inst | is_store_inst | is_csr_rw_inst | is_mul_inst | is_div_inst | is_rem_inst))}} & 
			(dcd_res_alu_op_msg_packeted | 128'd0)) | 
		({128{(~is_illegal_inst) & (is_load_inst | is_store_inst)}} & 
			(dcd_res_lsu_op_msg_packeted | 128'd0)) | 
		({128{(~is_illegal_inst) & is_csr_rw_inst}} & 
			(dcd_res_csr_rw_op_msg_packeted | 128'd0)) | 
		({128{(~is_illegal_inst) & (is_mul_inst | is_div_inst | is_rem_inst)}} & 
			(dcd_res_mul_div_op_msg_packeted | 128'd0)); // 打包的FU操作信息
	assign m_op_ftc_id_res_dcd_res[15:0] = dcd_res_inst_type_packeted; // 打包的指令类型标志
	assign m_op_ftc_id_res_id = s_if_res_id;
	assign m_op_ftc_id_res_is_first_inst_after_rst = s_if_res_is_first_inst_after_rst;
	assign m_op_ftc_id_res_op1 = 
		to_sel_op1_latched ? 
			op1_latched:
			op1_fetch_cur;
	assign m_op_ftc_id_res_op2 = 
		to_sel_op2_latched ? 
			op2_latched:
			op2_fetch_cur;
	// 握手条件: (~on_rst_flush) & s_if_res_valid & m_op_ftc_id_res_ready & op1_ready & op2_ready
	assign m_op_ftc_id_res_valid = 
		(~on_rst_flush) & s_if_res_valid & op1_ready & op2_ready;
	
	assign brc_bdcst_luc_vld = m_op_ftc_id_res_valid & m_op_ftc_id_res_ready;
	assign brc_bdcst_luc_tid = m_op_ftc_id_res_id;
	assign brc_bdcst_luc_is_b_inst = 
		m_op_ftc_id_res_dcd_res[INST_TYPE_FLAG_IS_B_INST_SID] & 
		(~m_op_ftc_id_res_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]);
	assign brc_bdcst_luc_is_jal_inst = 
		m_op_ftc_id_res_dcd_res[INST_TYPE_FLAG_IS_JAL_INST_SID] & 
		(~m_op_ftc_id_res_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]);
	assign brc_bdcst_luc_is_jalr_inst = 
		m_op_ftc_id_res_dcd_res[INST_TYPE_FLAG_IS_JALR_INST_SID] & 
		(~m_op_ftc_id_res_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]);
	// 说明: 当实际分支指令类型是JALR时, 从"发射阶段分支信息广播"获得真实的BTA, 对B指令重新预测为跳
	assign brc_bdcst_luc_bta = actual_bta;
	
	assign rob_luc_bdcst_vld = m_op_ftc_id_res_valid & m_op_ftc_id_res_ready;
	assign rob_luc_bdcst_tid = m_op_ftc_id_res_id;
	assign rob_luc_bdcst_fuid = 
		(OP_PRE_FTC == "true") ? 
			s_if_res_fuid:
			(
				({FU_ID_WIDTH{
					is_illegal_inst | 
					(~(is_csr_rw_inst | is_load_inst | is_store_inst | is_mul_inst | is_div_inst | is_rem_inst))
				}} & FU_ALU_ID) | // 从ALU取到结果
				({FU_ID_WIDTH{(~is_illegal_inst) & is_csr_rw_inst}} & FU_CSR_ID) | // 从CSR取到结果
				({FU_ID_WIDTH{(~is_illegal_inst) & (is_load_inst | is_store_inst)}} & FU_LSU_ID) | // 从LSU取到结果
				({FU_ID_WIDTH{(~is_illegal_inst) & is_mul_inst}} & FU_MUL_ID) | // 从乘法器取到结果
				({FU_ID_WIDTH{(~is_illegal_inst) & (is_div_inst | is_rem_inst)}} & FU_DIV_ID) // 从除法器取到结果
			);
	assign rob_luc_bdcst_rd_id = 
		s_if_res_data[32+PRE_DCD_MSG_RD_VLD_SID] ? 
			s_if_res_data[11:7]:
			5'b00000;
	assign rob_luc_bdcst_is_ls_inst = 
		(~m_op_ftc_id_res_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & 
		(
			m_op_ftc_id_res_dcd_res[INST_TYPE_FLAG_IS_STORE_INST_SID] | 
			m_op_ftc_id_res_dcd_res[INST_TYPE_FLAG_IS_LOAD_INST_SID]
		);
	assign rob_luc_bdcst_is_csr_rw_inst = 
		(~m_op_ftc_id_res_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & 
		m_op_ftc_id_res_dcd_res[PRE_DCD_MSG_IS_CSR_RW_INST_SID];
	assign rob_luc_bdcst_csr_rw_inst_msg = {
		m_op_ftc_id_res_dcd_res[11+CSR_RW_OP_MSG_ADDR_SID+16:CSR_RW_OP_MSG_ADDR_SID+16], // CSR写地址
		m_op_ftc_id_res_dcd_res[1+CSR_RW_OP_MSG_UPD_TYPE_SID+16:CSR_RW_OP_MSG_UPD_TYPE_SID+16], // CSR更新类型
		m_op_ftc_id_res_dcd_res[31+CSR_RW_OP_MSG_MASK_V_SID+16:CSR_RW_OP_MSG_MASK_V_SID+16] // CSR更新掩码或更新值
	};
	assign rob_luc_bdcst_err = m_op_ftc_id_res_msg[2:0];
	assign rob_luc_bdcst_spec_inst_type = 
		({3{~(is_ecall_inst | is_mret_inst | is_ebreak_inst | is_dret_inst)}} & SPEC_INST_TYPE_NONE) | 
		({3{is_ecall_inst}} & SPEC_INST_TYPE_ECALL) | 
		({3{is_mret_inst}} & SPEC_INST_TYPE_MRET) | 
		({3{is_ebreak_inst}} & SPEC_INST_TYPE_EBREAK) | 
		({3{is_dret_inst}} & SPEC_INST_TYPE_DRET);
	
	assign nxt_seq_pc = s_if_res_data[127:96] + 3'd4; // PC + 指令长度
	assign prdt_addr_corrected = 
		(
			// 分支预测特例: BTB命中, BTB给出的分支指令类型为JALR, RAS出栈标志无效
			s_if_res_msg[PRDT_MSG_BTB_HIT_SID+3:PRDT_MSG_BTB_HIT_SID+3] & 
			(s_if_res_msg[2+PRDT_MSG_BTYPE_SID+3:PRDT_MSG_BTYPE_SID+3] == BRANCH_TYPE_JALR) & 
			(~s_if_res_msg[PRDT_MSG_POP_RAS_SID+3:PRDT_MSG_POP_RAS_SID+3])
		) ? 
			brc_bdcst_luc_bta:
			s_if_res_msg[31+PRDT_MSG_TARGET_ADDR_SID+3:PRDT_MSG_TARGET_ADDR_SID+3];
	
	panda_risc_v_decoder decoder_u(
		.inst(s_if_res_data[31:0]),
		.pre_decoding_msg_packeted(s_if_res_data[95:32]),
		.pc_of_inst(s_if_res_data[127:96]),
		.inst_len_type(1'b1),
		
		.rs1_v(m_op_ftc_id_res_op1),
		.rs2_v(m_op_ftc_id_res_op2),
		
		.is_b_inst(),
		.is_csr_rw_inst(is_csr_rw_inst),
		.is_load_inst(is_load_inst),
		.is_store_inst(is_store_inst),
		.is_mul_inst(is_mul_inst),
		.is_div_inst(is_div_inst),
		.is_rem_inst(is_rem_inst),
		.is_ecall_inst(is_ecall_inst),
		.is_mret_inst(is_mret_inst),
		.is_fence_inst(),
		.is_fence_i_inst(),
		.is_ebreak_inst(is_ebreak_inst),
		.is_dret_inst(is_dret_inst),
		.is_jal_inst(),
		.is_jalr_inst(),
		.is_illegal_inst(is_illegal_inst),
		
		.rs1_vld(),
		.rs2_vld(),
		.rd_vld(),
		
		.ls_type(),
		.ls_addr_aligned(ls_addr_aligned),
		
		.mul_div_op_a(),
		.mul_div_op_b(),
		.mul_res_sel(),
		
		.csr_addr(),
		.csr_upd_type(),
		.csr_upd_mask_v(),
		
		.alu_op_mode(),
		.alu_op1(),
		.alu_op2(),
		
		.actual_bta(actual_bta),
		.brc_jump_baseaddr_sel_rs1(),
		
		.dcd_res_inst_type_packeted(dcd_res_inst_type_packeted),
		.dcd_res_alu_op_msg_packeted(dcd_res_alu_op_msg_packeted),
		.dcd_res_lsu_op_msg_packeted(dcd_res_lsu_op_msg_packeted),
		.dcd_res_csr_rw_op_msg_packeted(dcd_res_csr_rw_op_msg_packeted),
		.dcd_res_mul_div_op_msg_packeted(dcd_res_mul_div_op_msg_packeted)
	);
	
endmodule
