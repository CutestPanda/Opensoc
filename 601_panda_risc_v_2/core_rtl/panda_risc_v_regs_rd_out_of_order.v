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
本模块: 读通用寄存器或ROB

描述:
进行指令译码
检查2个操作数所存在的数据相关性
从Reg-File、ROB、FU输出预取操作数

如果载入段寄存器时未成功预取到操作数, 则段寄存器会继续监听FU, 并给出即时的操作数及其就绪标志

如果某条指令不需要取某个操作数, 或者它是由立即数表示的, 则始终认为这个操作数预取成功

注意：
无

协议:
无

作者: 陈家耀
日期: 2026/02/12
********************************************************************/


module panda_risc_v_regs_rd_out_of_order #(
	parameter integer IBUS_TID_WIDTH = 8, // 指令总线事务ID位宽(1~16)
	parameter integer AGE_TAG_WIDTH = 4, // 年龄标识的位宽(必须>=2)
	parameter integer LSN_FU_N = 6, // 要监听结果的执行单元的个数(必须在范围[1, 16]内)
	parameter integer IQ0_OTHER_PAYLOAD_WIDTH = 128, // 发射队列#0其他负载数据的位宽
	parameter integer IQ1_OTHER_PAYLOAD_WIDTH = 384, // 发射队列#1其他负载数据的位宽
	parameter integer ROB_ENTRY_N = 8, // 重排序队列项数(4 | 8 | 16 | 32)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 复位/冲刷
	input wire sys_reset_req, // 系统复位请求
	input wire flush_req, // 冲刷请求
	
	// ROB控制/状态
	input wire rob_full_n, // ROB满(标志)
	input wire rob_csr_rw_inst_allowed, // 允许发射CSR读写指令(标志)
	input wire[7:0] rob_entry_id_to_be_written, // 待写项的条目编号
	input wire rob_entry_age_tbit_to_be_written, // 待写项的年龄翻转位
	
	// 执行单元结果返回
	input wire[LSN_FU_N*32-1:0] fu_res_data,
	input wire[LSN_FU_N*IBUS_TID_WIDTH-1:0] fu_res_tid,
	input wire[LSN_FU_N-1:0] fu_res_vld,
	
	// 读ARF/ROB输入
	input wire[127:0] s_regs_rd_data, // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	input wire[98:0] s_regs_rd_msg, // 取指附加信息({分支预测信息(96bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	input wire[IBUS_TID_WIDTH-1:0] s_regs_rd_id, // 指令ID
	input wire s_regs_rd_is_first_inst_after_rst, // 是否复位释放后的第1条指令
	input wire s_regs_rd_valid,
	output wire s_regs_rd_ready,
	
	// 写发射队列#0
	output wire[IBUS_TID_WIDTH-1:0] m_wr_iq0_inst_id, // 指令ID
	output wire[3:0] m_wr_iq0_fuid, // 执行单元ID
	output wire[7:0] m_wr_iq0_rob_entry_id, // ROB条目ID
	output wire[AGE_TAG_WIDTH-1:0] m_wr_iq0_age_tag, // 年龄标识
	output wire[3:0] m_wr_iq0_op1_lsn_fuid, // OP1所监听的执行单元ID
	output wire[3:0] m_wr_iq0_op2_lsn_fuid, // OP2所监听的执行单元ID
	output wire[IBUS_TID_WIDTH-1:0] m_wr_iq0_op1_lsn_inst_id, // OP1所监听的指令ID
	output wire[IBUS_TID_WIDTH-1:0] m_wr_iq0_op2_lsn_inst_id, // OP2所监听的指令ID
	output wire[IQ0_OTHER_PAYLOAD_WIDTH-1:0] m_wr_iq0_other_payload, // 其他负载数据
	output wire[31:0] m_wr_iq0_op1_pre_fetched, // 预取的OP1
	output wire[31:0] m_wr_iq0_op2_pre_fetched, // 预取的OP2
	output wire m_wr_iq0_op1_rdy, // OP1已就绪
	output wire m_wr_iq0_op2_rdy, // OP2已就绪
	output wire m_wr_iq0_valid,
	input wire m_wr_iq0_ready,
	
	// 写发射队列#1
	output wire[IBUS_TID_WIDTH-1:0] m_wr_iq1_inst_id, // 指令ID
	output wire[3:0] m_wr_iq1_fuid, // 执行单元ID
	output wire[7:0] m_wr_iq1_rob_entry_id, // ROB条目ID
	output wire[AGE_TAG_WIDTH-1:0] m_wr_iq1_age_tag, // 年龄标识
	output wire[3:0] m_wr_iq1_op1_lsn_fuid, // OP1所监听的执行单元ID
	output wire[3:0] m_wr_iq1_op2_lsn_fuid, // OP2所监听的执行单元ID
	output wire[IBUS_TID_WIDTH-1:0] m_wr_iq1_op1_lsn_inst_id, // OP1所监听的指令ID
	output wire[IBUS_TID_WIDTH-1:0] m_wr_iq1_op2_lsn_inst_id, // OP2所监听的指令ID
	output wire[IQ1_OTHER_PAYLOAD_WIDTH-1:0] m_wr_iq1_other_payload, // 其他负载数据
	output wire[31:0] m_wr_iq1_op1_pre_fetched, // 预取的OP1
	output wire[31:0] m_wr_iq1_op2_pre_fetched, // 预取的OP2
	output wire m_wr_iq1_op1_rdy, // OP1已就绪
	output wire m_wr_iq1_op2_rdy, // OP2已就绪
	output wire m_wr_iq1_valid,
	input wire m_wr_iq1_ready,
	
	// 数据相关性检查
	// [操作数1]
	output wire[4:0] op1_ftc_rs1_id, // 1号源寄存器编号
	input wire op1_ftc_from_reg_file, // 从寄存器堆取到操作数(标志)
	input wire op1_ftc_from_rob, // 从ROB取到操作数(标志)
	input wire op1_ftc_from_byp, // 从旁路网络取到操作数(标志)
	input wire[3:0] op1_ftc_fuid, // 待旁路的执行单元编号
	input wire[IBUS_TID_WIDTH-1:0] op1_ftc_tid, // 待旁路的指令ID
	input wire[31:0] op1_ftc_rob_saved_data, // ROB暂存的执行结果
	// [操作数2]
	output wire[4:0] op2_ftc_rs2_id, // 2号源寄存器编号
	input wire op2_ftc_from_reg_file, // 从寄存器堆取到操作数(标志)
	input wire op2_ftc_from_rob, // 从ROB取到操作数(标志)
	input wire op2_ftc_from_byp, // 从旁路网络取到操作数(标志)
	input wire[3:0] op2_ftc_fuid, // 待旁路的执行单元编号
	input wire[IBUS_TID_WIDTH-1:0] op2_ftc_tid, // 待旁路的指令ID
	input wire[31:0] op2_ftc_rob_saved_data, // ROB暂存的执行结果
	
	// 发射阶段ROB记录广播
	output wire rob_luc_bdcst_vld, // 广播有效
	output wire[IBUS_TID_WIDTH-1:0] rob_luc_bdcst_tid, // 指令ID
	output wire[3:0] rob_luc_bdcst_fuid, // 被发射到的执行单元ID
	output wire[4:0] rob_luc_bdcst_rd_id, // 目的寄存器编号
	output wire rob_luc_bdcst_is_ls_inst, // 是否加载/存储指令
	output wire rob_luc_bdcst_is_csr_rw_inst, // 是否CSR读写指令
	output wire[13:0] rob_luc_bdcst_csr_rw_inst_msg, // CSR读写指令信息({CSR写地址(12bit), CSR更新类型(2bit)})
	output wire[2:0] rob_luc_bdcst_err, // 错误类型
	output wire[2:0] rob_luc_bdcst_spec_inst_type, // 特殊指令类型
	output wire rob_luc_bdcst_is_b_inst, // 是否B指令
	output wire[31:0] rob_luc_bdcst_pc, // 指令对应的PC
	output wire[31:0] rob_luc_bdcst_nxt_pc, // 指令对应的下一有效PC
	output wire[1:0] rob_luc_bdcst_org_2bit_sat_cnt, // 原来的2bit饱和计数器
	output wire[15:0] rob_luc_bdcst_bhr, // BHR
	
	// 通用寄存器堆读端口#0
	output wire[4:0] reg_file_raddr_p0,
	input wire[31:0] reg_file_dout_p0,
	// 通用寄存器堆读端口#1
	output wire[4:0] reg_file_raddr_p1,
	input wire[31:0] reg_file_dout_p1
);
	
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
    end
    endfunction
	
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
	localparam integer PRDT_MSG_TARGET_ADDR_EXCEPT_FOR_SPEC_CASE_SID = 0; // 除外特例的预测地址
	localparam integer PRDT_MSG_BTYPE_SID = 32; // 分支指令类型
	localparam integer PRDT_MSG_IS_TAKEN_SID = 35; // 是否跳转
	localparam integer PRDT_MSG_BTB_HIT_SID = 36; // BTB命中
	localparam integer PRDT_MSG_BTB_WID_SID = 37; // BTB命中的缓存路编号
	localparam integer PRDT_MSG_BTB_WVLD_SID = 39; // BTB缓存路有效标志
	localparam integer PRDT_MSG_GLB_SAT_CNT_SID = 43; // 基于历史的分支预测给出的2bit饱和计数器
	localparam integer PRDT_MSG_BTB_BTA_SID = 45; // BTB分支目标地址
	localparam integer PRDT_MSG_PUSH_RAS_SID = 77; // RAS压栈标志
	localparam integer PRDT_MSG_POP_RAS_SID = 78; // RAS出栈标志
	localparam integer PRDT_MSG_BHR_SID = 79; // BHR
	// 发射队列#0其他负载数据各字段的起始索引
	// [复用的负载: 普通算术逻辑(ALU)指令]
	localparam integer IQ0_OTHER_PAYLOAD_FIELD_OP_MODE = 0; // ALU操作模式
	// [复用的负载: 乘除法指令]
	localparam integer IQ0_OTHER_PAYLOAD_FIELD_MUL_DIV_RES_SEL_SID = 0; // 乘除法结果选择(1'b0 -> 低32位乘积/商, 1'b1 -> 高32位乘积/余数)
	localparam integer IQ0_OTHER_PAYLOAD_FIELD_MUL_DIV_OP1_IS_UNSIGNED_SID = 1; // 乘除法运算操作数1是否无符号
	localparam integer IQ0_OTHER_PAYLOAD_FIELD_MUL_DIV_OP2_IS_UNSIGNED_SID = 2; // 乘除法运算操作数2是否无符号
	// [复用的负载: CSR读写指令]
	localparam integer IQ0_OTHER_PAYLOAD_FIELD_CSR_ADDR_SID = 0; // CSR读写地址
	// 发射队列#1其他负载数据各字段的起始索引
	localparam integer IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE = 0; // 打包的指令类型标志
	// [复用的负载: 加载/存储指令]
	localparam integer IQ1_OTHER_PAYLOAD_FIELD_LS_SEL_SID = 16; // 加载/存储选择
	localparam integer IQ1_OTHER_PAYLOAD_FIELD_LS_TYPE_SID = 17; // 访存类型
	localparam integer IQ1_OTHER_PAYLOAD_FIELD_LS_ADDR_OFS_SID = 20; // 地址偏移量
	// [复用的负载: 分支指令]
	localparam integer IQ1_OTHER_PAYLOAD_FIELD_INST_PC = 16; // 指令对应的PC
	localparam integer IQ1_OTHER_PAYLOAD_FIELD_INST_NXT_SEQ_PC = 48; // 顺序取指时的下一PC
	localparam integer IQ1_OTHER_PAYLOAD_FIELD_BRC_PRDT_MSG = 80; // 分支预测信息
	// [复用的负载: B指令或JAL指令]
	localparam integer IQ1_OTHER_PAYLOAD_FIELD_ACTUAL_BTA = 176; // 实际的分支目标地址
	localparam integer IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE = 208; // B指令类型
	// [复用的负载: JALR指令]
	localparam integer IQ1_OTHER_PAYLOAD_FIELD_BRC_JUMP_OFS = 176; // 分支跳转偏移量
	// 各个执行单元的ID
	localparam integer FU_ALU_ID = 0; // ALU
	localparam integer FU_CSR_ID = 1; // CSR
	localparam integer FU_LSU_ID = 2; // LSU
	localparam integer FU_MUL_ID = 3; // 乘法器
	localparam integer FU_DIV_ID = 4; // 除法器
	localparam integer FU_BRU_ID = 5; // BRU
	// 特殊指令类型
	localparam SPEC_INST_TYPE_NONE = 3'b000; // 非特殊指令
	localparam SPEC_INST_TYPE_ECALL = 3'b100; // ECALL指令
	localparam SPEC_INST_TYPE_EBREAK = 3'b101; // EBREAK指令
	localparam SPEC_INST_TYPE_MRET = 3'b110; // MRET指令
	localparam SPEC_INST_TYPE_DRET = 3'b111; // DRET指令
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
	// 段寄存器其他负载的位宽
	localparam integer STAGE_REGS_OTHER_PAYLOAD_WIDTH = 
		(IQ1_OTHER_PAYLOAD_WIDTH > IQ0_OTHER_PAYLOAD_WIDTH) ? 
			IQ1_OTHER_PAYLOAD_WIDTH:
			IQ0_OTHER_PAYLOAD_WIDTH;
	
	/** 执行单元结果返回 **/
	reg[31:0] fu_res_data_r[0:LSN_FU_N-1];
	reg[IBUS_TID_WIDTH-1:0] fu_res_tid_r[0:LSN_FU_N-1];
	reg[LSN_FU_N-1:0] fu_res_vld_r;
	wire[LSN_FU_N-1:0] fu_res_tid_match_op1_vec; // 指令ID匹配操作数1所绑定指令的ID(标志向量)
	wire[LSN_FU_N-1:0] fu_res_tid_match_op2_vec; // 指令ID匹配操作数2所绑定指令的ID(标志向量)
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			fu_res_vld_r <= {LSN_FU_N{1'b0}};
		else
			fu_res_vld_r <= # SIM_DELAY fu_res_vld;
	end
	
	genvar fu_i;
	generate
		for(fu_i = 0;fu_i < LSN_FU_N;fu_i = fu_i + 1)
		begin:fu_res_blk
			assign fu_res_tid_match_op1_vec[fu_i] = 
				(op1_ftc_fuid == fu_i) & fu_res_vld_r[fu_i] & (fu_res_tid_r[fu_i] == op1_ftc_tid);
			assign fu_res_tid_match_op2_vec[fu_i] = 
				(op2_ftc_fuid == fu_i) & fu_res_vld_r[fu_i] & (fu_res_tid_r[fu_i] == op2_ftc_tid);
			
			always @(posedge aclk)
			begin
				if(fu_res_vld[fu_i])
				begin
					fu_res_data_r[fu_i] <= # SIM_DELAY fu_res_data[32*fu_i+31:32*fu_i];
					fu_res_tid_r[fu_i] <= # SIM_DELAY fu_res_tid[IBUS_TID_WIDTH*fu_i+(IBUS_TID_WIDTH-1):IBUS_TID_WIDTH*fu_i];
				end
			end
		end
	endgenerate
	
	/** 指令译码 **/
	// 指令类型标志
	wire is_b_inst; // 是否B指令
	wire is_csr_rw_inst; // 是否CSR读写指令
	wire is_load_inst; // 是否load指令
	wire is_store_inst; // 是否store指令
	wire is_lui_inst; // 是否LUI指令
	wire is_auipc_inst; // 是否AUIPC指令
	wire is_csr_rw_imm_inst; // 是否以立即数为更新掩码或更新值的CSR读写指令
	wire is_arth_imm_inst; // 是否立即数算术逻辑指令
	wire is_ecall_inst; // 是否ECALL指令
	wire is_mret_inst; // 是否MRET指令
	wire is_ebreak_inst; // 是否EBREAK指令
	wire is_dret_inst; // 是否DRET指令
	wire is_illegal_inst; // 是否非法指令
	// 读写通用寄存器堆标志
	wire rs1_vld; // 是否需要读RS1
	wire rs2_vld; // 是否需要读RS2
	wire rd_vld; // 是否需要写RD
	// 访存信息
	wire[2:0] ls_type; // 访存类型
	wire[31:0] ls_ofs_imm; // load/store地址偏移量立即数
	// 乘除法操作数
	wire mul_res_sel; // 乘法结果选择(1'b0 -> 低32位, 1'b1 -> 高32位)
	wire mul_div_op_a_unsigned; // 乘除法操作数A无符号(标志)
	wire mul_div_op_b_unsigned; // 乘除法操作数B无符号(标志)
	wire mul_div_res_sel; // 乘除法结果选择(1'b0 -> 低32位乘积/商, 1'b1 -> 高32位乘积/余数)
	// CSR原子读写操作信息
	wire[11:0] csr_addr; // CSR地址
	wire[1:0] csr_upd_type; // CSR更新类型
	wire[31:0] csr_upd_imm; // CSR更新立即数
	// ALU操作信息
	wire[3:0] alu_op_mode; // 操作类型
	wire[31:0] alu_op1; // 操作数1
	wire[31:0] alu_op2; // 操作数2
	// 分支信息
	wire[31:0] nxt_seq_pc; // 顺序取指时的下一PC
	wire[31:0] brc_jump_ofs; // 分支跳转偏移量
	wire[31:0] actual_bta; // 实际的分支目标地址
	// 打包的译码结果
	wire[15:0] dcd_res_inst_type_packeted; // 打包的指令类型标志
	
	assign is_lui_inst = inst_decoder_u.is_lui_inst;
	assign is_auipc_inst = inst_decoder_u.is_auipc_inst;
	assign is_csr_rw_imm_inst = 
		inst_decoder_u.is_csrrwi_inst | inst_decoder_u.is_csrrsi_inst | inst_decoder_u.is_csrrci_inst;
	assign is_arth_imm_inst = inst_decoder_u.is_arth_imm_inst;
	
	assign ls_ofs_imm = inst_decoder_u.ls_ofs_imm;
	
	assign mul_div_op_a_unsigned = inst_decoder_u.mul_div_op_a_unsigned;
	assign mul_div_op_b_unsigned = inst_decoder_u.mul_div_op_b_unsigned;
	assign mul_div_res_sel = 
		s_regs_rd_data[PRE_DCD_MSG_IS_MUL_INST_SID+32] ? 
			mul_res_sel:
			s_regs_rd_data[PRE_DCD_MSG_IS_REM_INST_SID+32];
	
	assign csr_upd_imm = inst_decoder_u.csr_upd_imm;
	
	assign nxt_seq_pc = s_regs_rd_data[127:96] + 3'd4;
	assign brc_jump_ofs = inst_decoder_u.brc_jump_ofs;
	
	panda_risc_v_decoder inst_decoder_u(
		.inst(s_regs_rd_data[31:0]),
		.pre_decoding_msg_packeted(s_regs_rd_data[95:32]),
		.pc_of_inst(s_regs_rd_data[127:96]),
		.inst_len_type(1'b1),
		
		.rs1_v(32'dx),
		.rs2_v(32'dx),
		
		.is_b_inst(is_b_inst),
		.is_csr_rw_inst(is_csr_rw_inst),
		.is_load_inst(is_load_inst),
		.is_store_inst(is_store_inst),
		.is_mul_inst(),
		.is_div_inst(),
		.is_rem_inst(),
		.is_ecall_inst(is_ecall_inst),
		.is_mret_inst(is_mret_inst),
		.is_fence_inst(),
		.is_fence_i_inst(),
		.is_ebreak_inst(is_ebreak_inst),
		.is_dret_inst(is_dret_inst),
		.is_jal_inst(),
		.is_jalr_inst(),
		.is_illegal_inst(is_illegal_inst),
		
		.rs1_vld(rs1_vld),
		.rs2_vld(rs2_vld),
		.rd_vld(rd_vld),
		
		.ls_type(ls_type),
		.ls_addr_aligned(),
		
		.mul_div_op_a(),
		.mul_div_op_b(),
		.mul_res_sel(mul_res_sel),
		
		.csr_addr(csr_addr),
		.csr_upd_type(csr_upd_type),
		.csr_upd_mask_v(),
		
		.alu_op_mode(alu_op_mode),
		.alu_op1(alu_op1),
		.alu_op2(alu_op2),
		
		.actual_bta(actual_bta),
		.brc_jump_baseaddr_sel_rs1(),
		
		.dcd_res_inst_type_packeted(dcd_res_inst_type_packeted),
		.dcd_res_alu_op_msg_packeted(),
		.dcd_res_lsu_op_msg_packeted(),
		.dcd_res_csr_rw_op_msg_packeted(),
		.dcd_res_mul_div_op_msg_packeted()
	);
	
	/** 数据相关性检查 **/
	assign op1_ftc_rs1_id = s_regs_rd_data[19:15];
	assign op2_ftc_rs2_id = s_regs_rd_data[24:20];
	
	/** 读通用寄存器堆 **/
	assign reg_file_raddr_p0 = s_regs_rd_data[19:15];
	assign reg_file_raddr_p1 = s_regs_rd_data[24:20];
	
	/** 预取操作数 **/
	wire need_op1; // 需要取操作数1(标志)
	wire need_op2; // 需要取操作数2(标志)
	wire[31:0] op1_prefetched; // 预取的操作数1
	wire[31:0] op2_prefetched; // 预取的操作数2
	wire op1_pftc_success; // 操作数1预取成功(标志)
	wire op2_pftc_success; // 操作数2预取成功(标志)
	wire op1_stage_regs_raw_dpc; // 操作数1与段寄存器上的指令存在RAW相关性(标志)
	wire op2_stage_regs_raw_dpc; // 操作数2与段寄存器上的指令存在RAW相关性(标志)
	
	assign need_op1 = rs1_vld & (~is_illegal_inst);
	assign need_op2 = rs2_vld & (~is_illegal_inst);
	
	assign op1_prefetched = 
		({32{op1_ftc_from_reg_file}} & reg_file_dout_p0) | // 从寄存器堆取操作数
		({32{op1_ftc_from_rob}} & op1_ftc_rob_saved_data[31:0]) | // 从ROB取操作数
		({32{op1_ftc_from_byp}} & fu_res_data_r[op1_ftc_fuid[clogb2(LSN_FU_N-1):0]][31:0]); // 从FU取操作数
	assign op2_prefetched = 
		({32{op2_ftc_from_reg_file}} & reg_file_dout_p1) | // 从寄存器堆取操作数
		({32{op2_ftc_from_rob}} & op2_ftc_rob_saved_data[31:0]) | // 从ROB取操作数
		({32{op2_ftc_from_byp}} & fu_res_data_r[op2_ftc_fuid[clogb2(LSN_FU_N-1):0]][31:0]); // 从FU取操作数
	
	assign op1_pftc_success = 
		(~need_op1) | 
		(
			(~op1_stage_regs_raw_dpc) & // 与段寄存器上的指令不存在RAW相关性
			(
				op1_ftc_from_reg_file | 
				op1_ftc_from_rob | 
				(|fu_res_tid_match_op1_vec)
			)
		);
	assign op2_pftc_success = 
		(~need_op2) | 
		(
			(~op2_stage_regs_raw_dpc) & // 与段寄存器上的指令不存在RAW相关性
			(
				op2_ftc_from_reg_file | 
				op2_ftc_from_rob | 
				(|fu_res_tid_match_op2_vec)
			)
		);
	
	/** 段寄存器 **/
	reg[IBUS_TID_WIDTH-1:0] stage_regs_payload_inst_id; // 指令ID
	reg[3:0] stage_regs_payload_fuid; // 执行单元ID
	reg[4:0] stage_regs_payload_rd_id; // 目的寄存器编号
	reg[3:0] stage_regs_payload_op1_lsn_fuid; // OP1所监听的执行单元ID
	reg[3:0] stage_regs_payload_op2_lsn_fuid; // OP2所监听的执行单元ID
	reg[IBUS_TID_WIDTH-1:0] stage_regs_payload_op1_lsn_inst_id; // OP1所监听的指令ID
	reg[IBUS_TID_WIDTH-1:0] stage_regs_payload_op2_lsn_inst_id; // OP2所监听的指令ID
	reg[31:0] stage_regs_payload_op1_pre_fetched; // 预取的OP1
	reg[31:0] stage_regs_payload_op2_pre_fetched; // 预取的OP2
	reg stage_regs_payload_op1_rdy; // OP1已就绪
	reg stage_regs_payload_op2_rdy; // OP2已就绪
	reg[STAGE_REGS_OTHER_PAYLOAD_WIDTH-1:0] stage_regs_other_payload; // 其他负载
	reg stage_regs_payload_is_ls_inst; // 是否加载/存储指令
	reg stage_regs_payload_is_csr_rw_inst; // 是否CSR读写指令
	reg stage_regs_payload_is_b_inst; // 是否B指令
	reg[2:0] stage_regs_payload_spec_inst_type; // 特殊指令类型
	reg[1:0] stage_regs_payload_csr_upd_type; // CSR更新类型
	reg[31:0] stage_regs_payload_pc; // 指令对应的PC
	reg[31:0] stage_regs_payload_nxt_pc; // 指令对应的下一有效PC
	reg[2:0] stage_regs_payload_err_code; // 错误类型
	wire[31:0] instant_op1_pre_fetched; // 最新的预取的OP1
	wire[31:0] instant_op2_pre_fetched; // 最新的预取的OP2
	wire instant_op1_rdy; // 最新的OP1已就绪
	wire instant_op2_rdy; // 最新的OP2已就绪
	reg stage_regs_valid; // 段寄存器有效标志
	wire stage_regs_ready; // 段寄存器后级就绪标志
	
	assign s_regs_rd_ready = (~(sys_reset_req | flush_req)) & ((~stage_regs_valid) | stage_regs_ready);
	
	assign m_wr_iq0_inst_id = stage_regs_payload_inst_id;
	assign m_wr_iq0_fuid = stage_regs_payload_fuid;
	assign m_wr_iq0_rob_entry_id = rob_entry_id_to_be_written;
	assign m_wr_iq0_age_tag = {rob_entry_age_tbit_to_be_written, rob_entry_id_to_be_written[clogb2(ROB_ENTRY_N-1):0]};
	assign m_wr_iq0_op1_lsn_fuid = stage_regs_payload_op1_lsn_fuid;
	assign m_wr_iq0_op2_lsn_fuid = stage_regs_payload_op2_lsn_fuid;
	assign m_wr_iq0_op1_lsn_inst_id = stage_regs_payload_op1_lsn_inst_id;
	assign m_wr_iq0_op2_lsn_inst_id = stage_regs_payload_op2_lsn_inst_id;
	assign m_wr_iq0_other_payload = stage_regs_other_payload[IQ0_OTHER_PAYLOAD_WIDTH-1:0];
	assign m_wr_iq0_op1_pre_fetched = instant_op1_pre_fetched;
	assign m_wr_iq0_op2_pre_fetched = instant_op2_pre_fetched;
	assign m_wr_iq0_op1_rdy = instant_op1_rdy;
	assign m_wr_iq0_op2_rdy = instant_op2_rdy;
	assign m_wr_iq0_valid = 
		(~(sys_reset_req | flush_req)) & 
		stage_regs_valid & 
		rob_full_n & 
		// 说明: 如果1条指令是发往CSR原子读写单元的, 那么它必定是CSR读写指令
		((stage_regs_payload_fuid != FU_CSR_ID) | rob_csr_rw_inst_allowed) & // CSR读写指令需要等待许可
		(~((stage_regs_payload_fuid == FU_LSU_ID) | (stage_regs_payload_fuid == FU_BRU_ID)));
	
	assign m_wr_iq1_inst_id = stage_regs_payload_inst_id;
	assign m_wr_iq1_fuid = stage_regs_payload_fuid;
	assign m_wr_iq1_rob_entry_id = rob_entry_id_to_be_written;
	assign m_wr_iq1_age_tag = {rob_entry_age_tbit_to_be_written, rob_entry_id_to_be_written[clogb2(ROB_ENTRY_N-1):0]};
	assign m_wr_iq1_op1_lsn_fuid = stage_regs_payload_op1_lsn_fuid;
	assign m_wr_iq1_op2_lsn_fuid = stage_regs_payload_op2_lsn_fuid;
	assign m_wr_iq1_op1_lsn_inst_id = stage_regs_payload_op1_lsn_inst_id;
	assign m_wr_iq1_op2_lsn_inst_id = stage_regs_payload_op2_lsn_inst_id;
	assign m_wr_iq1_other_payload = stage_regs_other_payload[IQ1_OTHER_PAYLOAD_WIDTH-1:0];
	assign m_wr_iq1_op1_pre_fetched = instant_op1_pre_fetched;
	assign m_wr_iq1_op2_pre_fetched = instant_op2_pre_fetched;
	assign m_wr_iq1_op1_rdy = instant_op1_rdy;
	assign m_wr_iq1_op2_rdy = instant_op2_rdy;
	assign m_wr_iq1_valid = 
		(~(sys_reset_req | flush_req)) & 
		stage_regs_valid & 
		rob_full_n & 
		((stage_regs_payload_fuid == FU_LSU_ID) | (stage_regs_payload_fuid == FU_BRU_ID));
	
	assign rob_luc_bdcst_vld = (~(sys_reset_req | flush_req)) & stage_regs_valid & stage_regs_ready;
	assign rob_luc_bdcst_tid = stage_regs_payload_inst_id;
	assign rob_luc_bdcst_fuid = stage_regs_payload_fuid | 4'd0;
	assign rob_luc_bdcst_rd_id = stage_regs_payload_rd_id;
	assign rob_luc_bdcst_is_ls_inst = stage_regs_payload_is_ls_inst;
	assign rob_luc_bdcst_is_csr_rw_inst = stage_regs_payload_is_csr_rw_inst;
	assign rob_luc_bdcst_csr_rw_inst_msg = {
		stage_regs_other_payload[IQ0_OTHER_PAYLOAD_FIELD_CSR_ADDR_SID+11:IQ0_OTHER_PAYLOAD_FIELD_CSR_ADDR_SID], // CSR写地址(12bit)
		stage_regs_payload_csr_upd_type // CSR更新类型(2bit)
	};
	assign rob_luc_bdcst_err = stage_regs_payload_err_code;
	assign rob_luc_bdcst_spec_inst_type = stage_regs_payload_spec_inst_type;
	assign rob_luc_bdcst_is_b_inst = stage_regs_payload_is_b_inst;
	assign rob_luc_bdcst_pc = stage_regs_payload_pc;
	assign rob_luc_bdcst_nxt_pc = stage_regs_payload_nxt_pc;
	assign rob_luc_bdcst_org_2bit_sat_cnt = 
		stage_regs_other_payload[IQ1_OTHER_PAYLOAD_FIELD_BRC_PRDT_MSG+PRDT_MSG_GLB_SAT_CNT_SID+1:IQ1_OTHER_PAYLOAD_FIELD_BRC_PRDT_MSG+PRDT_MSG_GLB_SAT_CNT_SID];
	assign rob_luc_bdcst_bhr = 
		stage_regs_other_payload[IQ1_OTHER_PAYLOAD_FIELD_BRC_PRDT_MSG+PRDT_MSG_BHR_SID+15:IQ1_OTHER_PAYLOAD_FIELD_BRC_PRDT_MSG+PRDT_MSG_BHR_SID];
	
	assign op1_stage_regs_raw_dpc = 
		stage_regs_valid & (stage_regs_payload_rd_id != 5'b00000) & (s_regs_rd_data[19:15] == stage_regs_payload_rd_id);
	assign op2_stage_regs_raw_dpc = 
		stage_regs_valid & (stage_regs_payload_rd_id != 5'b00000) & (s_regs_rd_data[24:20] == stage_regs_payload_rd_id);
	
	assign instant_op1_pre_fetched = 
		stage_regs_payload_op1_rdy ? 
			stage_regs_payload_op1_pre_fetched:
			fu_res_data_r[stage_regs_payload_op1_lsn_fuid[clogb2(LSN_FU_N-1):0]];
	assign instant_op2_pre_fetched = 
		stage_regs_payload_op2_rdy ? 
			stage_regs_payload_op2_pre_fetched:
			fu_res_data_r[stage_regs_payload_op2_lsn_fuid[clogb2(LSN_FU_N-1):0]];
	assign instant_op1_rdy = 
		stage_regs_payload_op1_rdy | 
		(
			fu_res_vld_r[stage_regs_payload_op1_lsn_fuid[clogb2(LSN_FU_N-1):0]] & 
			(fu_res_tid_r[stage_regs_payload_op1_lsn_fuid[clogb2(LSN_FU_N-1):0]] == stage_regs_payload_op1_lsn_inst_id)
		);
	assign instant_op2_rdy = 
		stage_regs_payload_op2_rdy | 
		(
			fu_res_vld_r[stage_regs_payload_op2_lsn_fuid[clogb2(LSN_FU_N-1):0]] & 
			(fu_res_tid_r[stage_regs_payload_op2_lsn_fuid[clogb2(LSN_FU_N-1):0]] == stage_regs_payload_op2_lsn_inst_id)
		);
	
	assign stage_regs_ready = 
		rob_full_n & 
		// 说明: 如果1条指令是发往CSR原子读写单元的, 那么它必定是CSR读写指令
		((stage_regs_payload_fuid != FU_CSR_ID) | rob_csr_rw_inst_allowed) & // CSR读写指令需要等待许可
		(
			((stage_regs_payload_fuid == FU_LSU_ID) | (stage_regs_payload_fuid == FU_BRU_ID)) ? 
				m_wr_iq1_ready:
				m_wr_iq0_ready
		);
	
	// 指令ID
	always @(posedge aclk)
	begin
		if(s_regs_rd_valid & s_regs_rd_ready)
			stage_regs_payload_inst_id <= # SIM_DELAY s_regs_rd_id;
	end
	
	// 执行单元ID
	always @(posedge aclk)
	begin
		if(s_regs_rd_valid & s_regs_rd_ready)
			stage_regs_payload_fuid <= # SIM_DELAY 
				({4{
					s_regs_rd_data[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID+32] | 
					(~(
						s_regs_rd_data[PRE_DCD_MSG_IS_CSR_RW_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_LOAD_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_STORE_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_MUL_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_DIV_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_REM_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_JAL_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_JALR_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_B_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_EBREAK_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_FENCE_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_FENCE_I_INST_SID+32]
					))
				}} & FU_ALU_ID) | // 发往ALU
				({4{
					(~s_regs_rd_data[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID+32]) & 
					s_regs_rd_data[PRE_DCD_MSG_IS_CSR_RW_INST_SID+32]
				}} & FU_CSR_ID) | // 发往CSR原子读写单元
				({4{
					(~s_regs_rd_data[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID+32]) & 
					(
						s_regs_rd_data[PRE_DCD_MSG_IS_LOAD_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_STORE_INST_SID+32]
					)
				}} & FU_LSU_ID) | // 发往LSU
				({4{
					(~s_regs_rd_data[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID+32]) & 
					s_regs_rd_data[PRE_DCD_MSG_IS_MUL_INST_SID+32]
				}} & FU_MUL_ID) | // 发往乘法器
				({4{
					(~s_regs_rd_data[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID+32]) & 
					(
						s_regs_rd_data[PRE_DCD_MSG_IS_DIV_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_REM_INST_SID+32]
					)
				}} & FU_DIV_ID) | // 发往除法器
				({4{
					(~s_regs_rd_data[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID+32]) & 
					(
						s_regs_rd_data[PRE_DCD_MSG_IS_JAL_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_JALR_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_B_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_EBREAK_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_FENCE_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_FENCE_I_INST_SID+32]
					)
				}} & FU_BRU_ID); // 发往BRU
	end
	
	// 目的寄存器编号
	always @(posedge aclk)
	begin
		if(s_regs_rd_valid & s_regs_rd_ready)
			stage_regs_payload_rd_id <= # SIM_DELAY 
				s_regs_rd_data[PRE_DCD_MSG_RD_VLD_SID+32] ? 
					s_regs_rd_data[11:7]:
					5'd0;
	end
	
	// OP1所监听的执行单元ID, OP2所监听的执行单元ID, OP1所监听的指令ID, OP2所监听的指令ID
	always @(posedge aclk)
	begin
		if(s_regs_rd_valid & s_regs_rd_ready)
		begin
			stage_regs_payload_op1_lsn_fuid <= # SIM_DELAY 
				op1_stage_regs_raw_dpc ? 
					stage_regs_payload_fuid: // 与段寄存器上的指令存在RAW相关性, 那么操作数1就要从段寄存器上的指令的执行结果获取
					op1_ftc_fuid;
			
			stage_regs_payload_op2_lsn_fuid <= # SIM_DELAY 
				op2_stage_regs_raw_dpc ? 
					stage_regs_payload_fuid: // 与段寄存器上的指令存在RAW相关性, 那么操作数1就要从段寄存器上的指令的执行结果获取
					op2_ftc_fuid;
			
			stage_regs_payload_op1_lsn_inst_id <= # SIM_DELAY 
				op1_stage_regs_raw_dpc ? 
					stage_regs_payload_inst_id: // 与段寄存器上的指令存在RAW相关性, 那么操作数1就要从段寄存器上的指令的执行结果获取
					op1_ftc_tid;
			
			stage_regs_payload_op2_lsn_inst_id <= # SIM_DELAY 
				op2_stage_regs_raw_dpc ? 
					stage_regs_payload_inst_id:
					op2_ftc_tid;
		end
	end
	
	// 预取的OP1
	always @(posedge aclk)
	begin
		if(
			(s_regs_rd_valid & s_regs_rd_ready) | 
			(
				stage_regs_valid & 
				(~stage_regs_payload_op1_rdy) & 
				fu_res_vld_r[stage_regs_payload_op1_lsn_fuid[clogb2(LSN_FU_N-1):0]] & 
				(fu_res_tid_r[stage_regs_payload_op1_lsn_fuid[clogb2(LSN_FU_N-1):0]] == stage_regs_payload_op1_lsn_inst_id)
			)
		)
			stage_regs_payload_op1_pre_fetched <= # SIM_DELAY 
				(s_regs_rd_valid & s_regs_rd_ready) ? 
					(
						(is_illegal_inst | is_lui_inst | is_auipc_inst | is_csr_rw_imm_inst) ? 
							(
								is_csr_rw_imm_inst ? 
									csr_upd_imm[31:0]:
									alu_op1[31:0]
							):
							op1_prefetched[31:0]
					):
					fu_res_data_r[stage_regs_payload_op1_lsn_fuid[clogb2(LSN_FU_N-1):0]];
	end
	// 预取的OP2
	always @(posedge aclk)
	begin
		if(
			(s_regs_rd_valid & s_regs_rd_ready) | 
			(
				stage_regs_valid & 
				(~stage_regs_payload_op2_rdy) & 
				fu_res_vld_r[stage_regs_payload_op2_lsn_fuid[clogb2(LSN_FU_N-1):0]] & 
				(fu_res_tid_r[stage_regs_payload_op2_lsn_fuid[clogb2(LSN_FU_N-1):0]] == stage_regs_payload_op2_lsn_inst_id)
			)
		)
			stage_regs_payload_op2_pre_fetched <= # SIM_DELAY 
				(s_regs_rd_valid & s_regs_rd_ready) ? 
					(
						(is_illegal_inst | is_lui_inst | is_auipc_inst | is_arth_imm_inst) ? 
							alu_op2[31:0]:
							op2_prefetched[31:0]
					):
					fu_res_data_r[stage_regs_payload_op2_lsn_fuid[clogb2(LSN_FU_N-1):0]];
	end
	
	// OP1已就绪
	always @(posedge aclk)
	begin
		if(
			(s_regs_rd_valid & s_regs_rd_ready) | 
			(
				stage_regs_valid & 
				(~stage_regs_payload_op1_rdy) & 
				fu_res_vld_r[stage_regs_payload_op1_lsn_fuid[clogb2(LSN_FU_N-1):0]] & 
				(fu_res_tid_r[stage_regs_payload_op1_lsn_fuid[clogb2(LSN_FU_N-1):0]] == stage_regs_payload_op1_lsn_inst_id)
			)
		)
			stage_regs_payload_op1_rdy <= # SIM_DELAY 
				(~(s_regs_rd_valid & s_regs_rd_ready)) | op1_pftc_success;
	end
	// OP2已就绪
	always @(posedge aclk)
	begin
		if(
			(s_regs_rd_valid & s_regs_rd_ready) | 
			(
				stage_regs_valid & 
				(~stage_regs_payload_op2_rdy) & 
				fu_res_vld_r[stage_regs_payload_op2_lsn_fuid[clogb2(LSN_FU_N-1):0]] & 
				(fu_res_tid_r[stage_regs_payload_op2_lsn_fuid[clogb2(LSN_FU_N-1):0]] == stage_regs_payload_op2_lsn_inst_id)
			)
		)
			stage_regs_payload_op2_rdy <= # SIM_DELAY 
				(~(s_regs_rd_valid & s_regs_rd_ready)) | op2_pftc_success;
	end
	
	// 其他负载
	always @(posedge aclk)
	begin
		if(s_regs_rd_valid & s_regs_rd_ready)
		begin
			stage_regs_other_payload <= # SIM_DELAY 
				(
					(
						(~s_regs_rd_data[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID+32]) & 
						(
							s_regs_rd_data[PRE_DCD_MSG_IS_LOAD_INST_SID+32] | 
							s_regs_rd_data[PRE_DCD_MSG_IS_STORE_INST_SID+32] | 
							s_regs_rd_data[PRE_DCD_MSG_IS_JAL_INST_SID+32] | 
							s_regs_rd_data[PRE_DCD_MSG_IS_JALR_INST_SID+32] | 
							s_regs_rd_data[PRE_DCD_MSG_IS_B_INST_SID+32] | 
							s_regs_rd_data[PRE_DCD_MSG_IS_EBREAK_INST_SID+32] | 
							s_regs_rd_data[PRE_DCD_MSG_IS_FENCE_INST_SID+32] | 
							s_regs_rd_data[PRE_DCD_MSG_IS_FENCE_I_INST_SID+32]
						)
					) ? 
						// 生成发射队列#1的其他负载数据
						{
							{
								(
									s_regs_rd_data[PRE_DCD_MSG_IS_LOAD_INST_SID+32] | 
									s_regs_rd_data[PRE_DCD_MSG_IS_STORE_INST_SID+32]
								) ? 
									{
										ls_ofs_imm[31:0], // 地址偏移量
										ls_type[2:0], // 访存类型
										s_regs_rd_data[PRE_DCD_MSG_IS_STORE_INST_SID+32] // 加载/存储选择
									}:
									{
										{
											s_regs_rd_data[PRE_DCD_MSG_IS_JALR_INST_SID+32] ? 
												brc_jump_ofs[31:0]: // 分支跳转偏移量
												{
													s_regs_rd_data[14:12], // B指令类型
													actual_bta[31:0] // 实际的分支目标地址
												}
										},
										s_regs_rd_msg[98:3], // 分支预测信息
										nxt_seq_pc[31:0], // 顺序取指时的下一PC
										s_regs_rd_data[127:96] // 指令对应的PC
									}
							},
							dcd_res_inst_type_packeted[15:0] // 打包的指令类型标志
						}:
						// 生成发射队列#0的其他负载数据
						(
							(
								(~s_regs_rd_data[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID+32]) & 
								s_regs_rd_data[PRE_DCD_MSG_IS_CSR_RW_INST_SID+32]
							) ? 
								csr_addr[11:0]: // CSR读写地址
								(
									(
										(~s_regs_rd_data[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID+32]) & 
										(
											s_regs_rd_data[PRE_DCD_MSG_IS_MUL_INST_SID+32] | 
											s_regs_rd_data[PRE_DCD_MSG_IS_DIV_INST_SID+32] | 
											s_regs_rd_data[PRE_DCD_MSG_IS_REM_INST_SID+32]
										)
									) ? 
										{
											mul_div_op_b_unsigned, // 乘除法运算操作数2是否无符号
											mul_div_op_a_unsigned, // 乘除法运算操作数1是否无符号
											mul_div_res_sel // 乘除法结果选择(1'b0 -> 低32位乘积/商, 1'b1 -> 高32位乘积/余数)
										}:
										alu_op_mode[3:0] // ALU操作模式
								)
						)
				) | {STAGE_REGS_OTHER_PAYLOAD_WIDTH{1'b0}};
		end
	end
	
	// 是否加载/存储指令, 是否CSR读写指令, 是否B指令, 特殊指令类型
	always @(posedge aclk)
	begin
		if(s_regs_rd_valid & s_regs_rd_ready)
		begin
			stage_regs_payload_is_ls_inst <= # SIM_DELAY 
				(~is_illegal_inst) & (is_load_inst | is_store_inst);
			
			stage_regs_payload_is_csr_rw_inst <= # SIM_DELAY 
				(~is_illegal_inst) & is_csr_rw_inst;
			
			stage_regs_payload_is_b_inst <= # SIM_DELAY 
				(~is_illegal_inst) & is_b_inst;
			
			stage_regs_payload_spec_inst_type <= # SIM_DELAY 
				is_illegal_inst ? 
					SPEC_INST_TYPE_NONE:
					(
						({3{~(is_ecall_inst | is_mret_inst | is_ebreak_inst | is_dret_inst)}} & SPEC_INST_TYPE_NONE) | 
						({3{is_ecall_inst}} & SPEC_INST_TYPE_ECALL) | 
						({3{is_mret_inst}} & SPEC_INST_TYPE_MRET) | 
						({3{is_ebreak_inst}} & SPEC_INST_TYPE_EBREAK) | 
						({3{is_dret_inst}} & SPEC_INST_TYPE_DRET)
					);
		end
	end
	
	// CSR更新类型
	always @(posedge aclk)
	begin
		if(s_regs_rd_valid & s_regs_rd_ready & (~is_illegal_inst) & is_csr_rw_inst)
			stage_regs_payload_csr_upd_type <= # SIM_DELAY csr_upd_type;
	end
	
	// 指令对应的PC, 指令对应的下一有效PC
	always @(posedge aclk)
	begin
		if(s_regs_rd_valid & s_regs_rd_ready)
		begin
			stage_regs_payload_pc <= # SIM_DELAY 
				s_regs_rd_data[127:96];
			stage_regs_payload_nxt_pc <= # SIM_DELAY 
				(
					// 非法指令、JAL指令、普通指令(非分支指令)的分支预测失败在前端(IFU)处理, 这里需要对"下一有效PC"作修正
					s_regs_rd_data[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID+32] | 
					s_regs_rd_data[PRE_DCD_MSG_IS_JAL_INST_SID+32] | 
					(~(
						s_regs_rd_data[PRE_DCD_MSG_IS_B_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_JAL_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_JALR_INST_SID+32]
					))
				) ? 
					(
						(
							(~s_regs_rd_data[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID+32]) & 
							s_regs_rd_data[PRE_DCD_MSG_IS_JAL_INST_SID+32]
						) ? 
							actual_bta[31:0]:
							nxt_seq_pc[31:0]
					):
					s_regs_rd_msg[31+PRDT_MSG_TARGET_ADDR_EXCEPT_FOR_SPEC_CASE_SID+3:PRDT_MSG_TARGET_ADDR_EXCEPT_FOR_SPEC_CASE_SID+3];
		end
	end
	
	// 错误类型
	always @(posedge aclk)
	begin
		if(s_regs_rd_valid & s_regs_rd_ready)
			// 说明: "读存储映射地址非对齐"和"写存储映射地址非对齐"在执行阶段再判定
			stage_regs_payload_err_code <= # SIM_DELAY 
				// 正常
				({3{(~is_illegal_inst) & (s_regs_rd_msg[1:0] == IBUS_ACCESS_NORMAL)}} & 
					INST_ERR_CODE_NORMAL) | 
				// 非法指令
				({3{is_illegal_inst}} & INST_ERR_CODE_ILLEGAL) | 
				// 指令地址非对齐
				({3{s_regs_rd_msg[1:0] == IBUS_ACCESS_PC_UNALIGNED}} & INST_ERR_CODE_PC_UNALIGNED) | 
				// 指令总线访问失败
				({3{(s_regs_rd_msg[1:0] == IBUS_ACCESS_BUS_ERR) | (s_regs_rd_msg[1:0] == IBUS_ACCESS_TIMEOUT)}} & 
					INST_ERR_CODE_IMEM_ACCESS_FAILED);
	end
	
	// 段寄存器有效标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			stage_regs_valid <= 1'b0;
		else if(
			(sys_reset_req | flush_req) | 
			((~stage_regs_valid) | stage_regs_ready)
		)
			stage_regs_valid <= # SIM_DELAY 
				(~(sys_reset_req | flush_req)) & s_regs_rd_valid;
	end
	
endmodule
