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
本模块: 发射队列

描述:
2个发射队列 -> 
	发射队列#0处理普通算术逻辑(ALU)指令、CSR读写指令、乘除法指令、非法指令、特殊指令(ECALL/MRET/DRET)
	发射队列#1处理分支指令(JAL指令、JALR指令、B指令)、内存屏障指令(FENCE指令、FENCE.I指令)、加载/存储指令、EBREAK指令

发射队列#0是乱序发射的, 发射仲裁方式为Oldest-First
发射队列#1是顺序发射的

只有当分支路径已确认且没有处理中的EBREAK或FENCE.I指令, 才允许写发射队列

发射队列#1可对LSU结果进行低时延监听, 以尽快解除load指令带来的数据相关性

注意：
"BRU处理结果"和"BRU名义结果"是不同的,
	"BRU处理结果"包含了实际的分支信息(下一有效PC地址, B指令执行结果), 而"BRU名义结果"则是名义的FU执行结果(对JAL和JALR指令来说就是PC + 4)

如果确认了1条分支指令, 则发送发射阶段的分支信息广播

如果发射了1条发往CSR原子读写单元的指令(此时CSR更新掩码或更新值肯定是准备好的), 则更新ROB的"CSR更新掩码或更新值"字段
如果确认了1条分支指令且这条分支指令初步确认为预测失败或者这是1个分支预测特例#0, 则更新ROB的"指令对应的下一有效PC"字段

协议:
无

作者: 陈家耀
日期: 2026/02/14
********************************************************************/


module panda_risc_v_issue_queue #(
	parameter integer IBUS_TID_WIDTH = 8, // 指令总线事务ID位宽(1~16)
	parameter integer IQ0_ENTRY_N = 4, // 发射队列#0条目数(2 | 4 | 8 | 16)
	parameter integer IQ1_ENTRY_N = 4, // 发射队列#1条目数(2 | 4 | 8 | 16)
	parameter integer AGE_TAG_WIDTH = 4, // 年龄标识的位宽(必须>=2)
	parameter integer LSN_FU_N = 6, // 要监听结果的执行单元的个数(必须在范围[1, 16]内)
	parameter integer LSU_FU_ID = 2, // LSU的执行单元ID
	parameter integer IQ1_LOW_LA_LSU_LSN_OPT_LEVEL = 1, // 发射队列#1对LSU结果的低时延监听(优化等级)(0 | 1 | 2)
	parameter EN_LOW_LA_BRC_PRDT_FAILURE_PROC = "true", // 是否启用低时延的分支预测失败处理
	parameter integer IQ0_OTHER_PAYLOAD_WIDTH = 128, // 发射队列#0其他负载数据的位宽
	parameter integer IQ1_OTHER_PAYLOAD_WIDTH = 384, // 发射队列#1其他负载数据的位宽
	parameter integer BRU_NOMINAL_RES_LATENCY = 0, // BRU名义结果输出时延(0 | 1)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 发射队列控制/状态
	input wire clr_iq0, // 清空发射队列#0(指示)
	input wire clr_iq1, // 清空发射队列#1(指示)
	
	// 读存储器结果快速旁路
	input wire on_get_instant_rd_mem_res,
	input wire[IBUS_TID_WIDTH-1:0] inst_id_of_instant_rd_mem_res_gotten,
	input wire[31:0] data_of_instant_rd_mem_res_gotten,
	
	// LSU状态
	input wire has_buffered_wr_mem_req, // 存在已缓存的写存储器请求(标志)
	input wire has_processing_perph_access_req, // 存在处理中的外设访问请求(标志)
	
	// 执行单元结果返回
	input wire[LSN_FU_N*32-1:0] fu_res_data,
	input wire[LSN_FU_N*IBUS_TID_WIDTH-1:0] fu_res_tid,
	input wire[LSN_FU_N-1:0] fu_res_vld,
	
	// BRU处理结果返回
	input wire[IBUS_TID_WIDTH-1:0] s_bru_o_tid, // 指令ID
	input wire s_bru_o_valid,
	
	// BRU名义结果
	output wire bru_nominal_res_vld, // 有效标志
	output wire[IBUS_TID_WIDTH-1:0] bru_nominal_res_tid, // 指令ID
	output wire[31:0] bru_nominal_res, // 执行结果
	
	// 写发射队列#0
	input wire[IBUS_TID_WIDTH-1:0] s_wr_iq0_inst_id, // 指令ID
	input wire[3:0] s_wr_iq0_fuid, // 执行单元ID
	input wire[7:0] s_wr_iq0_rob_entry_id, // ROB条目ID
	input wire[AGE_TAG_WIDTH-1:0] s_wr_iq0_age_tag, // 年龄标识
	input wire[3:0] s_wr_iq0_op1_lsn_fuid, // OP1所监听的执行单元ID
	input wire[3:0] s_wr_iq0_op2_lsn_fuid, // OP2所监听的执行单元ID
	input wire[IBUS_TID_WIDTH-1:0] s_wr_iq0_op1_lsn_inst_id, // OP1所监听的指令ID
	input wire[IBUS_TID_WIDTH-1:0] s_wr_iq0_op2_lsn_inst_id, // OP2所监听的指令ID
	input wire[IQ0_OTHER_PAYLOAD_WIDTH-1:0] s_wr_iq0_other_payload, // 其他负载数据
	input wire[31:0] s_wr_iq0_op1_pre_fetched, // 预取的OP1
	input wire[31:0] s_wr_iq0_op2_pre_fetched, // 预取的OP2
	input wire s_wr_iq0_op1_rdy, // OP1已就绪
	input wire s_wr_iq0_op2_rdy, // OP2已就绪
	input wire s_wr_iq0_valid,
	output wire s_wr_iq0_ready,
	
	// 写发射队列#1
	input wire[IBUS_TID_WIDTH-1:0] s_wr_iq1_inst_id, // 指令ID
	input wire[3:0] s_wr_iq1_fuid, // 执行单元ID
	input wire[7:0] s_wr_iq1_rob_entry_id, // ROB条目ID
	input wire[AGE_TAG_WIDTH-1:0] s_wr_iq1_age_tag, // 年龄标识
	input wire[3:0] s_wr_iq1_op1_lsn_fuid, // OP1所监听的执行单元ID
	input wire[3:0] s_wr_iq1_op2_lsn_fuid, // OP2所监听的执行单元ID
	input wire[IBUS_TID_WIDTH-1:0] s_wr_iq1_op1_lsn_inst_id, // OP1所监听的指令ID
	input wire[IBUS_TID_WIDTH-1:0] s_wr_iq1_op2_lsn_inst_id, // OP2所监听的指令ID
	input wire[IQ1_OTHER_PAYLOAD_WIDTH-1:0] s_wr_iq1_other_payload, // 其他负载数据
	input wire[31:0] s_wr_iq1_op1_pre_fetched, // 预取的OP1
	input wire[31:0] s_wr_iq1_op2_pre_fetched, // 预取的OP2
	input wire s_wr_iq1_op1_rdy, // OP1已就绪
	input wire s_wr_iq1_op2_rdy, // OP2已就绪
	input wire s_wr_iq1_valid,
	output wire s_wr_iq1_ready,
	
	// 发射阶段分支信息广播
	output wire brc_bdcst_luc_vld, // 广播有效
	output wire[IBUS_TID_WIDTH-1:0] brc_bdcst_luc_tid, // 指令ID
	output wire brc_bdcst_luc_is_b_inst, // 是否B指令
	output wire brc_bdcst_luc_is_jal_inst, // 是否JAL指令
	output wire brc_bdcst_luc_is_jalr_inst, // 是否JALR指令
	output wire[31:0] brc_bdcst_luc_bta, // 分支目标地址
	
	// 更新ROB的"CSR更新掩码或更新值"字段
	output wire[31:0] saving_csr_rw_msg_upd_mask_v, // 更新掩码或更新值
	output wire[7:0] saving_csr_rw_msg_rob_entry_id, // ROB条目编号
	output wire saving_csr_rw_msg_vld,
	
	// 更新ROB的"指令对应的下一有效PC"字段
	output wire on_upd_rob_field_nxt_pc,
	output wire[IBUS_TID_WIDTH-1:0] inst_id_of_upd_rob_field_nxt_pc,
	output wire[31:0] rob_field_nxt_pc,
	
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
	input wire m_div_ready,
	// [LSU]
	output wire m_lsu_ls_sel, // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	output wire[2:0] m_lsu_ls_type, // 访存类型
	output wire[4:0] m_lsu_rd_id_for_ld, // 用于加载的目标寄存器的索引
	output wire[31:0] m_lsu_ls_addr, // 访存地址
	output wire[31:0] m_lsu_ls_din, // 写数据
	output wire[IBUS_TID_WIDTH-1:0] m_lsu_inst_id, // 指令ID
	output wire m_lsu_valid,
	input wire m_lsu_ready,
	// [BRU]
	output wire[159:0] m_bru_prdt_msg, // 分支预测信息
	output wire[15:0] m_bru_inst_type, // 打包的指令类型标志
	output wire[IBUS_TID_WIDTH-1:0] m_bru_tid, // 指令ID
	output wire m_bru_prdt_suc, // 是否预判分支预测成功
	output wire m_bru_brc_cond_res, // 分支判定结果
	output wire m_bru_valid,
	input wire m_bru_ready
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
	// 各个执行单元的ID
	localparam integer FU_ALU_ID = 0; // ALU
	localparam integer FU_CSR_ID = 1; // CSR
	localparam integer FU_LSU_ID = 2; // LSU
	localparam integer FU_MUL_ID = 3; // 乘法器
	localparam integer FU_DIV_ID = 4; // 除法器
	localparam integer FU_BRU_ID = 5; // BRU
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
	// 分支预测时的分支指令类型常量
	localparam BRANCH_TYPE_JAL = 3'b000; // JAL指令
	localparam BRANCH_TYPE_JALR = 3'b001; // JALR指令
	localparam BRANCH_TYPE_B = 3'b010; // B指令
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
	// B指令类型的编码
	localparam B_TYPE_BEQ = 3'b000; // BEQ
	localparam B_TYPE_BNE = 3'b001; // BNE
	localparam B_TYPE_BLT = 3'b100; // BLT
	localparam B_TYPE_BGE = 3'b101; // BGE
	localparam B_TYPE_BLTU = 3'b110; // BLTU
	localparam B_TYPE_BGEU = 3'b111; // BGEU
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
	
	/** 执行单元结果返回 **/
	reg[31:0] fu_res_data_r[0:LSN_FU_N-1];
	reg[IBUS_TID_WIDTH-1:0] fu_res_tid_r[0:LSN_FU_N-1];
	reg[LSN_FU_N-1:0] fu_res_vld_r;
	
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
	
	/**
	发射队列#0
	
	处理普通算术逻辑(ALU)指令、CSR读写指令、乘除法指令、非法指令、特殊指令(ECALL/MRET/DRET)
	**/
	// 发射队列表
	reg[IBUS_TID_WIDTH-1:0] iq0_table_inst_id[0:IQ0_ENTRY_N-1]; // 指令ID
	reg[clogb2(LSN_FU_N-1):0] iq0_table_fuid[0:IQ0_ENTRY_N-1]; // 执行单元ID
	reg[7:0] iq0_table_rob_entry_id[0:IQ0_ENTRY_N-1]; // ROB条目ID
	reg[AGE_TAG_WIDTH-1:0] iq0_table_age_tag[0:IQ0_ENTRY_N-1]; // 年龄标识
	reg[clogb2(LSN_FU_N-1):0] iq0_table_op1_lsn_fuid[0:IQ0_ENTRY_N-1]; // OP1所监听的执行单元ID
	reg[clogb2(LSN_FU_N-1):0] iq0_table_op2_lsn_fuid[0:IQ0_ENTRY_N-1]; // OP2所监听的执行单元ID
	reg[IBUS_TID_WIDTH-1:0] iq0_table_op1_lsn_inst_id[0:IQ0_ENTRY_N-1]; // OP1所监听的指令ID
	reg[IBUS_TID_WIDTH-1:0] iq0_table_op2_lsn_inst_id[0:IQ0_ENTRY_N-1]; // OP2所监听的指令ID
	reg[IQ0_OTHER_PAYLOAD_WIDTH-1:0] iq0_table_other_payload[0:IQ0_ENTRY_N-1]; // 其他负载数据
	reg[31:0] iq0_table_op1_saved[0:IQ0_ENTRY_N-1]; // 暂存的OP1
	reg[31:0] iq0_table_op2_saved[0:IQ0_ENTRY_N-1]; // 暂存的OP2
	reg[IQ0_ENTRY_N-1:0] iq0_table_op1_rdy_flag; // OP1就绪标志
	reg[IQ0_ENTRY_N-1:0] iq0_table_op2_rdy_flag; // OP2就绪标志
	reg[IQ0_ENTRY_N-1:0] iq0_table_vld_flag; // 有效标志
	// 写发射队列
	wire is_iq0_full_n; // 发射队列不满标志
	wire[IQ0_ENTRY_N-1:0] iq0_entry_to_wr_onehot; // 待写条目独热码
	// 出发射队列(指令发射)
	wire is_iq0_empty_n; // 发射队列不空标志
	wire[IQ0_ENTRY_N-1:0] iq0_fu_ready_flag; // 执行单元就绪标志
	wire[IQ0_ENTRY_N-1:0] iq0_issue_allowed_flag; // 可发射标志
	// 最新的操作数及其就绪状态
	wire[IQ0_ENTRY_N-1:0] iq0_op1_instant_rdy_flag; // OP1当前就绪
	wire[IQ0_ENTRY_N-1:0] iq0_op2_instant_rdy_flag; // OP2当前就绪
	wire[31:0] iq0_instant_op1[0:IQ0_ENTRY_N-1]; // 当前的OP1
	wire[31:0] iq0_instant_op2[0:IQ0_ENTRY_N-1]; // 当前的OP2
	// 发射仲裁(Oldest-First)
	// [第0级]
	wire[3:0] iq0_issue_arb_s0_id[0:15]; // 项编号
	wire[AGE_TAG_WIDTH-1:0] iq0_issue_arb_s0_age_tag[0:15]; // 年龄标识
	wire[15:0] iq0_issue_arb_s0_vld_flag; // 有效标志
	// [第1级]
	wire[3:0] iq0_issue_arb_s1_id[0:7]; // 项编号
	wire[AGE_TAG_WIDTH-1:0] iq0_issue_arb_s1_age_tag[0:7]; // 年龄标识
	wire[7:0] iq0_issue_arb_s1_vld_flag; // 有效标志
	// [第2级]
	wire[3:0] iq0_issue_arb_s2_id[0:3]; // 项编号
	wire[AGE_TAG_WIDTH-1:0] iq0_issue_arb_s2_age_tag[0:3]; // 年龄标识
	wire[3:0] iq0_issue_arb_s2_vld_flag; // 有效标志
	// [第3级]
	wire[3:0] iq0_issue_arb_s3_id[0:1]; // 项编号
	wire[AGE_TAG_WIDTH-1:0] iq0_issue_arb_s3_age_tag[0:1]; // 年龄标识
	wire[1:0] iq0_issue_arb_s3_vld_flag; // 有效标志
	// [第4级]
	wire[3:0] iq0_issue_arb_fnl_id; // 项编号
	wire[AGE_TAG_WIDTH-1:0] iq0_issue_arb_fnl_age_tag; // 年龄标识
	wire iq0_issue_arb_fnl_vld_flag; // 有效标志
	
	assign m_alu_op_mode = 
		iq0_table_other_payload[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]][IQ0_OTHER_PAYLOAD_FIELD_OP_MODE+3:IQ0_OTHER_PAYLOAD_FIELD_OP_MODE];
	assign m_alu_op1 = iq0_instant_op1[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]][31:0];
	assign m_alu_op2 = iq0_instant_op2[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]][31:0];
	assign m_alu_tid = 
		iq0_table_inst_id[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]];
	assign m_alu_use_res = 1'b1;
	assign m_alu_valid = 
		(|iq0_issue_allowed_flag) & 
		(iq0_table_fuid[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]] == FU_ALU_ID);
	
	assign m_csr_addr = 
		iq0_table_other_payload[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]][IQ0_OTHER_PAYLOAD_FIELD_CSR_ADDR_SID+11:IQ0_OTHER_PAYLOAD_FIELD_CSR_ADDR_SID];
	assign m_csr_tid = 
		iq0_table_inst_id[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]];
	assign m_csr_valid = 
		(|iq0_issue_allowed_flag) & 
		(iq0_table_fuid[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]] == FU_CSR_ID);
	
	assign m_mul_op_a = 
		{
			(~iq0_table_other_payload[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]][IQ0_OTHER_PAYLOAD_FIELD_MUL_DIV_OP1_IS_UNSIGNED_SID]) & 
			iq0_instant_op1[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]][31],
			iq0_instant_op1[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]][31:0]
		};
	assign m_mul_op_b = 
		{
			(~iq0_table_other_payload[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]][IQ0_OTHER_PAYLOAD_FIELD_MUL_DIV_OP2_IS_UNSIGNED_SID]) & 
			iq0_instant_op2[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]][31],
			iq0_instant_op2[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]][31:0]
		};
	assign m_mul_res_sel = 
		iq0_table_other_payload[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]][IQ0_OTHER_PAYLOAD_FIELD_MUL_DIV_RES_SEL_SID];
	assign m_mul_rd_id = 5'bxxxxx; // 目标寄存器编号在ROB中已经保存, 无需在执行单元里传递
	assign m_mul_inst_id = iq0_table_inst_id[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]];
	assign m_mul_valid = 
		// 说明: m_mul_valid依赖于m_mul_ready, 但乘法器输入处有fifo, 因此这是安全的
		(|iq0_issue_allowed_flag) & 
		(iq0_table_fuid[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]] == FU_MUL_ID);
	
	assign m_div_op_a = 
		{
			(~iq0_table_other_payload[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]][IQ0_OTHER_PAYLOAD_FIELD_MUL_DIV_OP1_IS_UNSIGNED_SID]) & 
			iq0_instant_op1[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]][31],
			iq0_instant_op1[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]][31:0]
		};
	assign m_div_op_b = 
		{
			(~iq0_table_other_payload[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]][IQ0_OTHER_PAYLOAD_FIELD_MUL_DIV_OP2_IS_UNSIGNED_SID]) & 
			iq0_instant_op2[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]][31],
			iq0_instant_op2[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]][31:0]
		};
	assign m_div_rem_sel = 
		iq0_table_other_payload[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]][IQ0_OTHER_PAYLOAD_FIELD_MUL_DIV_RES_SEL_SID];
	assign m_div_rd_id = 5'bxxxxx; // 目标寄存器编号在ROB中已经保存, 无需在执行单元里传递
	assign m_div_inst_id = iq0_table_inst_id[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]];
	assign m_div_valid = 
		// 说明: m_div_valid依赖于m_div_ready, 但除法器输入处有fifo, 因此这是安全的
		(|iq0_issue_allowed_flag) & 
		(iq0_table_fuid[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]] == FU_DIV_ID);
	
	assign is_iq0_full_n = ~(&iq0_table_vld_flag);
	/*
	((~A) + 1) & A就是第1个"1"的位置独热码, 比如:
		---------------------------------
		|   A   | A的补码 | A & A的补码 |
		---------------------------------
		| 1000  |  1000   |    1000     |
		---------------------------------
		| 0000  |  0000   |    0000     |
		---------------------------------
		| 0110  |  1010   |    0010     |
		---------------------------------
		| 0111  |  1001   |    0001     |
		---------------------------------
		| 0101  |  1011   |    0001     |
		---------------------------------
	
	那么, (A + 1) & (~A)就是第1个"0"的位置独热码
	*/
	assign iq0_entry_to_wr_onehot = (iq0_table_vld_flag + 1'b1) & (~iq0_table_vld_flag);
	
	assign is_iq0_empty_n = |iq0_table_vld_flag;
	
	/*
	发射队列表存储负载(指令ID, 执行单元ID, ROB条目ID, 年龄标识, OP1所监听的执行单元ID, OP2所监听的执行单元ID,
		OP1所监听的指令ID, OP2所监听的指令ID, 其他负载数据)
	发射队列表保存的操作数(暂存的OP1, 暂存的OP2)
	发射队列表的标志(OP1就绪标志, OP2就绪标志, 有效标志)
	*/
	genvar iq0_entry_i;
	generate
		for(iq0_entry_i = 0;iq0_entry_i < IQ0_ENTRY_N;iq0_entry_i = iq0_entry_i + 1)
		begin:iq0_blk
			assign iq0_fu_ready_flag[iq0_entry_i] = 
				(iq0_table_fuid[iq0_entry_i] == FU_ALU_ID) | 
				(iq0_table_fuid[iq0_entry_i] == FU_CSR_ID) | 
				((iq0_table_fuid[iq0_entry_i] == FU_MUL_ID) & m_mul_ready) | 
				((iq0_table_fuid[iq0_entry_i] == FU_DIV_ID) & m_div_ready);
			assign iq0_issue_allowed_flag[iq0_entry_i] = 
				(~clr_iq0) & // 当前不正在清空发射队列#0
				iq0_table_vld_flag[iq0_entry_i] & // 条目有效
				iq0_op1_instant_rdy_flag[iq0_entry_i] & iq0_op2_instant_rdy_flag[iq0_entry_i] & // 操作数准备好
				iq0_fu_ready_flag[iq0_entry_i]; // 执行单元就绪
			
			assign iq0_op1_instant_rdy_flag[iq0_entry_i] = 
				iq0_table_op1_rdy_flag[iq0_entry_i] | 
				(
					fu_res_vld_r[iq0_table_op1_lsn_fuid[iq0_entry_i]] & 
					(fu_res_tid_r[iq0_table_op1_lsn_fuid[iq0_entry_i]] == iq0_table_op1_lsn_inst_id[iq0_entry_i])
				);
			assign iq0_op2_instant_rdy_flag[iq0_entry_i] = 
				iq0_table_op2_rdy_flag[iq0_entry_i] | 
				(
					fu_res_vld_r[iq0_table_op2_lsn_fuid[iq0_entry_i]] & 
					(fu_res_tid_r[iq0_table_op2_lsn_fuid[iq0_entry_i]] == iq0_table_op2_lsn_inst_id[iq0_entry_i])
				);
			assign iq0_instant_op1[iq0_entry_i] = 
				iq0_table_op1_rdy_flag[iq0_entry_i] ? 
					iq0_table_op1_saved[iq0_entry_i]:
					fu_res_data_r[iq0_table_op1_lsn_fuid[iq0_entry_i]];
			assign iq0_instant_op2[iq0_entry_i] = 
				iq0_table_op2_rdy_flag[iq0_entry_i] ? 
					iq0_table_op2_saved[iq0_entry_i]:
					fu_res_data_r[iq0_table_op2_lsn_fuid[iq0_entry_i]];
			
			always @(posedge aclk)
			begin
				if(s_wr_iq0_valid & s_wr_iq0_ready & iq0_entry_to_wr_onehot[iq0_entry_i])
				begin
					iq0_table_inst_id[iq0_entry_i] <= # SIM_DELAY s_wr_iq0_inst_id;
					iq0_table_fuid[iq0_entry_i] <= # SIM_DELAY s_wr_iq0_fuid[clogb2(LSN_FU_N-1):0];
					iq0_table_rob_entry_id[iq0_entry_i] <= # SIM_DELAY s_wr_iq0_rob_entry_id;
					iq0_table_age_tag[iq0_entry_i] <= # SIM_DELAY s_wr_iq0_age_tag;
					iq0_table_op1_lsn_fuid[iq0_entry_i] <= # SIM_DELAY s_wr_iq0_op1_lsn_fuid[clogb2(LSN_FU_N-1):0];
					iq0_table_op2_lsn_fuid[iq0_entry_i] <= # SIM_DELAY s_wr_iq0_op2_lsn_fuid[clogb2(LSN_FU_N-1):0];
					iq0_table_op1_lsn_inst_id[iq0_entry_i] <= # SIM_DELAY s_wr_iq0_op1_lsn_inst_id;
					iq0_table_op2_lsn_inst_id[iq0_entry_i] <= # SIM_DELAY s_wr_iq0_op2_lsn_inst_id;
					iq0_table_other_payload[iq0_entry_i] <= # SIM_DELAY s_wr_iq0_other_payload;
				end
			end
			
			always @(posedge aclk)
			begin
				if(
					(s_wr_iq0_valid & s_wr_iq0_ready & s_wr_iq0_op1_rdy & iq0_entry_to_wr_onehot[iq0_entry_i]) | 
					(
						iq0_table_vld_flag[iq0_entry_i] & 
						(~iq0_table_op1_rdy_flag[iq0_entry_i]) & 
						fu_res_vld_r[iq0_table_op1_lsn_fuid[iq0_entry_i]] & 
						(fu_res_tid_r[iq0_table_op1_lsn_fuid[iq0_entry_i]] == iq0_table_op1_lsn_inst_id[iq0_entry_i])
					)
				)
					iq0_table_op1_saved[iq0_entry_i] <= # SIM_DELAY 
						iq0_table_vld_flag[iq0_entry_i] ? 
							fu_res_data_r[iq0_table_op1_lsn_fuid[iq0_entry_i]]:
							s_wr_iq0_op1_pre_fetched;
			end
			
			always @(posedge aclk)
			begin
				if(
					(s_wr_iq0_valid & s_wr_iq0_ready & s_wr_iq0_op2_rdy & iq0_entry_to_wr_onehot[iq0_entry_i]) | 
					(
						iq0_table_vld_flag[iq0_entry_i] & 
						(~iq0_table_op2_rdy_flag[iq0_entry_i]) & 
						fu_res_vld_r[iq0_table_op2_lsn_fuid[iq0_entry_i]] & 
						(fu_res_tid_r[iq0_table_op2_lsn_fuid[iq0_entry_i]] == iq0_table_op2_lsn_inst_id[iq0_entry_i])
					)
				)
					iq0_table_op2_saved[iq0_entry_i] <= # SIM_DELAY 
						iq0_table_vld_flag[iq0_entry_i] ? 
							fu_res_data_r[iq0_table_op2_lsn_fuid[iq0_entry_i]]:
							s_wr_iq0_op2_pre_fetched;
			end
			
			always @(posedge aclk)
			begin
				if(
					(s_wr_iq0_valid & s_wr_iq0_ready & iq0_entry_to_wr_onehot[iq0_entry_i]) | 
					(
						iq0_table_vld_flag[iq0_entry_i] & 
						(~iq0_table_op1_rdy_flag[iq0_entry_i]) & 
						fu_res_vld_r[iq0_table_op1_lsn_fuid[iq0_entry_i]] & 
						(fu_res_tid_r[iq0_table_op1_lsn_fuid[iq0_entry_i]] == iq0_table_op1_lsn_inst_id[iq0_entry_i])
					)
				)
					iq0_table_op1_rdy_flag[iq0_entry_i] <= # SIM_DELAY 
						iq0_table_vld_flag[iq0_entry_i] | 
						s_wr_iq0_op1_rdy; // 写入条目时初始化OP1就绪标志
			end
			
			always @(posedge aclk)
			begin
				if(
					(s_wr_iq0_valid & s_wr_iq0_ready & iq0_entry_to_wr_onehot[iq0_entry_i]) | 
					(
						iq0_table_vld_flag[iq0_entry_i] & 
						(~iq0_table_op2_rdy_flag[iq0_entry_i]) & 
						fu_res_vld_r[iq0_table_op2_lsn_fuid[iq0_entry_i]] & 
						(fu_res_tid_r[iq0_table_op2_lsn_fuid[iq0_entry_i]] == iq0_table_op2_lsn_inst_id[iq0_entry_i])
					)
				)
					iq0_table_op2_rdy_flag[iq0_entry_i] <= # SIM_DELAY 
						iq0_table_vld_flag[iq0_entry_i] | 
						s_wr_iq0_op2_rdy; // 写入条目时初始化OP2就绪标志
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					iq0_table_vld_flag[iq0_entry_i] <= 1'b0;
				else if(
					clr_iq0 | 
					(s_wr_iq0_valid & s_wr_iq0_ready & iq0_entry_to_wr_onehot[iq0_entry_i]) | 
					((|iq0_issue_allowed_flag) & (iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0] == iq0_entry_i))
				)
					iq0_table_vld_flag[iq0_entry_i] <= # SIM_DELAY 
						(~clr_iq0) & 
						s_wr_iq0_valid & s_wr_iq0_ready & iq0_entry_to_wr_onehot[iq0_entry_i];
			end
		end
	endgenerate
	
	genvar iq0_issue_arb_s0_i;
	genvar iq0_issue_arb_s1_i;
	genvar iq0_issue_arb_s2_i;
	genvar iq0_issue_arb_s3_i;
	generate
		for(iq0_issue_arb_s0_i = 0;iq0_issue_arb_s0_i < 16;iq0_issue_arb_s0_i = iq0_issue_arb_s0_i + 1)
		begin:iq0_issue_arb_s0_blk
			assign iq0_issue_arb_s0_id[iq0_issue_arb_s0_i] = 
				iq0_issue_arb_s0_i;
			assign iq0_issue_arb_s0_age_tag[iq0_issue_arb_s0_i] = 
				(iq0_issue_arb_s0_i < IQ0_ENTRY_N) ? 
					iq0_table_age_tag[iq0_issue_arb_s0_i]:
					{AGE_TAG_WIDTH{1'bx}};
			assign iq0_issue_arb_s0_vld_flag[iq0_issue_arb_s0_i] = 
				(iq0_issue_arb_s0_i < IQ0_ENTRY_N) ? 
					iq0_issue_allowed_flag[iq0_issue_arb_s0_i]:
					1'b0;
		end
		
		for(iq0_issue_arb_s1_i = 0;iq0_issue_arb_s1_i < 8;iq0_issue_arb_s1_i = iq0_issue_arb_s1_i + 1)
		begin:iq0_issue_arb_s1_blk
			assign iq0_issue_arb_s1_id[iq0_issue_arb_s1_i] = 
				(
					iq0_issue_arb_s0_vld_flag[iq0_issue_arb_s1_i*2] & 
					(
						(~iq0_issue_arb_s0_vld_flag[iq0_issue_arb_s1_i*2+1]) | 
						(
							iq0_issue_arb_s0_age_tag[iq0_issue_arb_s1_i*2+1][AGE_TAG_WIDTH-1] ^ 
							iq0_issue_arb_s0_age_tag[iq0_issue_arb_s1_i*2][AGE_TAG_WIDTH-1] ^ 
							(
								iq0_issue_arb_s0_age_tag[iq0_issue_arb_s1_i*2+1][AGE_TAG_WIDTH-2:0] > 
								iq0_issue_arb_s0_age_tag[iq0_issue_arb_s1_i*2][AGE_TAG_WIDTH-2:0]
							)
						)
					)
				) ? 
					iq0_issue_arb_s0_id[iq0_issue_arb_s1_i*2]:
					iq0_issue_arb_s0_id[iq0_issue_arb_s1_i*2+1];
			
			assign iq0_issue_arb_s1_age_tag[iq0_issue_arb_s1_i] = 
				(
					iq0_issue_arb_s0_vld_flag[iq0_issue_arb_s1_i*2] & 
					(
						(~iq0_issue_arb_s0_vld_flag[iq0_issue_arb_s1_i*2+1]) | 
						(
							iq0_issue_arb_s0_age_tag[iq0_issue_arb_s1_i*2+1][AGE_TAG_WIDTH-1] ^ 
							iq0_issue_arb_s0_age_tag[iq0_issue_arb_s1_i*2][AGE_TAG_WIDTH-1] ^ 
							(
								iq0_issue_arb_s0_age_tag[iq0_issue_arb_s1_i*2+1][AGE_TAG_WIDTH-2:0] > 
								iq0_issue_arb_s0_age_tag[iq0_issue_arb_s1_i*2][AGE_TAG_WIDTH-2:0]
							)
						)
					)
				) ? 
					iq0_issue_arb_s0_age_tag[iq0_issue_arb_s1_i*2]:
					iq0_issue_arb_s0_age_tag[iq0_issue_arb_s1_i*2+1];
			
			assign iq0_issue_arb_s1_vld_flag[iq0_issue_arb_s1_i] = 
				iq0_issue_arb_s0_vld_flag[iq0_issue_arb_s1_i*2] | 
				iq0_issue_arb_s0_vld_flag[iq0_issue_arb_s1_i*2+1];
		end
		
		for(iq0_issue_arb_s2_i = 0;iq0_issue_arb_s2_i < 4;iq0_issue_arb_s2_i = iq0_issue_arb_s2_i + 1)
		begin:iq0_issue_arb_s2_blk
			assign iq0_issue_arb_s2_id[iq0_issue_arb_s2_i] = 
				(
					iq0_issue_arb_s1_vld_flag[iq0_issue_arb_s2_i*2] & 
					(
						(~iq0_issue_arb_s1_vld_flag[iq0_issue_arb_s2_i*2+1]) | 
						(
							iq0_issue_arb_s1_age_tag[iq0_issue_arb_s2_i*2+1][AGE_TAG_WIDTH-1] ^ 
							iq0_issue_arb_s1_age_tag[iq0_issue_arb_s2_i*2][AGE_TAG_WIDTH-1] ^ 
							(
								iq0_issue_arb_s1_age_tag[iq0_issue_arb_s2_i*2+1][AGE_TAG_WIDTH-2:0] > 
								iq0_issue_arb_s1_age_tag[iq0_issue_arb_s2_i*2][AGE_TAG_WIDTH-2:0]
							)
						)
					)
				) ? 
					iq0_issue_arb_s1_id[iq0_issue_arb_s2_i*2]:
					iq0_issue_arb_s1_id[iq0_issue_arb_s2_i*2+1];
			
			assign iq0_issue_arb_s2_age_tag[iq0_issue_arb_s2_i] = 
				(
					iq0_issue_arb_s1_vld_flag[iq0_issue_arb_s2_i*2] & 
					(
						(~iq0_issue_arb_s1_vld_flag[iq0_issue_arb_s2_i*2+1]) | 
						(
							iq0_issue_arb_s1_age_tag[iq0_issue_arb_s2_i*2+1][AGE_TAG_WIDTH-1] ^ 
							iq0_issue_arb_s1_age_tag[iq0_issue_arb_s2_i*2][AGE_TAG_WIDTH-1] ^ 
							(
								iq0_issue_arb_s1_age_tag[iq0_issue_arb_s2_i*2+1][AGE_TAG_WIDTH-2:0] > 
								iq0_issue_arb_s1_age_tag[iq0_issue_arb_s2_i*2][AGE_TAG_WIDTH-2:0]
							)
						)
					)
				) ? 
					iq0_issue_arb_s1_age_tag[iq0_issue_arb_s2_i*2]:
					iq0_issue_arb_s1_age_tag[iq0_issue_arb_s2_i*2+1];
			
			assign iq0_issue_arb_s2_vld_flag[iq0_issue_arb_s2_i] = 
				iq0_issue_arb_s1_vld_flag[iq0_issue_arb_s2_i*2] | 
				iq0_issue_arb_s1_vld_flag[iq0_issue_arb_s2_i*2+1];
		end
		
		for(iq0_issue_arb_s3_i = 0;iq0_issue_arb_s3_i < 2;iq0_issue_arb_s3_i = iq0_issue_arb_s3_i + 1)
		begin:iq0_issue_arb_s3_blk
			assign iq0_issue_arb_s3_id[iq0_issue_arb_s3_i] = 
				(
					iq0_issue_arb_s2_vld_flag[iq0_issue_arb_s3_i*2] & 
					(
						(~iq0_issue_arb_s2_vld_flag[iq0_issue_arb_s3_i*2+1]) | 
						(
							iq0_issue_arb_s2_age_tag[iq0_issue_arb_s3_i*2+1][AGE_TAG_WIDTH-1] ^ 
							iq0_issue_arb_s2_age_tag[iq0_issue_arb_s3_i*2][AGE_TAG_WIDTH-1] ^ 
							(
								iq0_issue_arb_s2_age_tag[iq0_issue_arb_s3_i*2+1][AGE_TAG_WIDTH-2:0] > 
								iq0_issue_arb_s2_age_tag[iq0_issue_arb_s3_i*2][AGE_TAG_WIDTH-2:0]
							)
						)
					)
				) ? 
					iq0_issue_arb_s2_id[iq0_issue_arb_s3_i*2]:
					iq0_issue_arb_s2_id[iq0_issue_arb_s3_i*2+1];
			
			assign iq0_issue_arb_s3_age_tag[iq0_issue_arb_s3_i] = 
				(
					iq0_issue_arb_s2_vld_flag[iq0_issue_arb_s3_i*2] & 
					(
						(~iq0_issue_arb_s2_vld_flag[iq0_issue_arb_s3_i*2+1]) | 
						(
							iq0_issue_arb_s2_age_tag[iq0_issue_arb_s3_i*2+1][AGE_TAG_WIDTH-1] ^ 
							iq0_issue_arb_s2_age_tag[iq0_issue_arb_s3_i*2][AGE_TAG_WIDTH-1] ^ 
							(
								iq0_issue_arb_s2_age_tag[iq0_issue_arb_s3_i*2+1][AGE_TAG_WIDTH-2:0] > 
								iq0_issue_arb_s2_age_tag[iq0_issue_arb_s3_i*2][AGE_TAG_WIDTH-2:0]
							)
						)
					)
				) ? 
					iq0_issue_arb_s2_age_tag[iq0_issue_arb_s3_i*2]:
					iq0_issue_arb_s2_age_tag[iq0_issue_arb_s3_i*2+1];
			
			assign iq0_issue_arb_s3_vld_flag[iq0_issue_arb_s3_i] = 
				iq0_issue_arb_s2_vld_flag[iq0_issue_arb_s3_i*2] | 
				iq0_issue_arb_s2_vld_flag[iq0_issue_arb_s3_i*2+1];
		end
		
		assign iq0_issue_arb_fnl_id = 
			(
				iq0_issue_arb_s3_vld_flag[0] & 
				(
					(~iq0_issue_arb_s3_vld_flag[1]) | 
					(
						iq0_issue_arb_s3_age_tag[1][AGE_TAG_WIDTH-1] ^ 
						iq0_issue_arb_s3_age_tag[0][AGE_TAG_WIDTH-1] ^ 
						(
							iq0_issue_arb_s3_age_tag[1][AGE_TAG_WIDTH-2:0] > 
							iq0_issue_arb_s3_age_tag[0][AGE_TAG_WIDTH-2:0]
						)
					)
				)
			) ? 
				iq0_issue_arb_s3_id[0]:
				iq0_issue_arb_s3_id[1];
		
		assign iq0_issue_arb_fnl_age_tag = 
			(
				iq0_issue_arb_s3_vld_flag[0] & 
				(
					(~iq0_issue_arb_s3_vld_flag[1]) | 
					(
						iq0_issue_arb_s3_age_tag[1][AGE_TAG_WIDTH-1] ^ 
						iq0_issue_arb_s3_age_tag[0][AGE_TAG_WIDTH-1] ^ 
						(
							iq0_issue_arb_s3_age_tag[1][AGE_TAG_WIDTH-2:0] > 
							iq0_issue_arb_s3_age_tag[0][AGE_TAG_WIDTH-2:0]
						)
					)
				)
			) ? 
				iq0_issue_arb_s3_age_tag[0]:
				iq0_issue_arb_s3_age_tag[1];
		
		assign iq0_issue_arb_fnl_vld_flag = 
			iq0_issue_arb_s3_vld_flag[0] | 
			iq0_issue_arb_s3_vld_flag[1];
	endgenerate
	
	/**
	发射队列#1
	
	处理分支指令(JAL指令、JALR指令、B指令)、内存屏障指令(FENCE指令、FENCE.I指令)、加载/存储指令、EBREAK指令
	**/
	// 发射队列表
	reg[IBUS_TID_WIDTH-1:0] iq1_table_inst_id[0:IQ1_ENTRY_N-1]; // 指令ID
	reg[clogb2(LSN_FU_N-1):0] iq1_table_fuid[0:IQ1_ENTRY_N-1]; // 执行单元ID
	reg[7:0] iq1_table_rob_entry_id[0:IQ1_ENTRY_N-1]; // ROB条目ID
	reg[AGE_TAG_WIDTH-1:0] iq1_table_age_tag[0:IQ1_ENTRY_N-1]; // 年龄标识
	reg[clogb2(LSN_FU_N-1):0] iq1_table_op1_lsn_fuid[0:IQ1_ENTRY_N-1]; // OP1所监听的执行单元ID
	reg[clogb2(LSN_FU_N-1):0] iq1_table_op2_lsn_fuid[0:IQ1_ENTRY_N-1]; // OP2所监听的执行单元ID
	reg[IBUS_TID_WIDTH-1:0] iq1_table_op1_lsn_inst_id[0:IQ1_ENTRY_N-1]; // OP1所监听的指令ID
	reg[IBUS_TID_WIDTH-1:0] iq1_table_op2_lsn_inst_id[0:IQ1_ENTRY_N-1]; // OP2所监听的指令ID
	reg[IQ1_OTHER_PAYLOAD_WIDTH-1:0] iq1_table_other_payload[0:IQ1_ENTRY_N-1]; // 其他负载数据
	reg[31:0] iq1_table_op1_saved[0:IQ1_ENTRY_N-1]; // 暂存的OP1
	reg[31:0] iq1_table_op2_saved[0:IQ1_ENTRY_N-1]; // 暂存的OP2
	reg[IQ1_ENTRY_N-1:0] iq1_table_actual_brc_direction_saved; // 保存的实际的分支跳转方向
	reg[IQ1_ENTRY_N-1:0] iq1_table_op1_rdy_flag; // OP1就绪标志
	reg[IQ1_ENTRY_N-1:0] iq1_table_op2_rdy_flag; // OP2就绪标志
	reg[IQ1_ENTRY_N-1:0] iq1_table_vld_flag; // 有效标志
	// 写发射队列
	wire is_iq1_full_n; // 发射队列不满标志
	reg[clogb2(IQ1_ENTRY_N-1):0] iq1_wptr; // 发射队列写指针
	// 出发射队列(指令发射)
	wire is_iq1_empty_n; // 发射队列不空标志
	wire iq1_fu_ready_flag; // 执行单元就绪标志
	reg[clogb2(IQ1_ENTRY_N-1):0] iq1_rptr; // 发射队列读指针
	reg[IBUS_TID_WIDTH-1:0] iq1_pending_ebreak_fence_i_inst_id; // 正在等待的EBREAK或FENCE.I指令的指令ID
	reg iq1_pending_for_ebreak_fence_i_inst; // 等待EBREAK或FENCE.I指令处理完成(标志)
	wire iq1_fence_inst_allowed; // 允许发射内存屏障(FENCE或FENCE.I)指令(标志)
	wire iq1_inst_launched; // 发射1条指令(指示)
	// 最新的操作数及其就绪状态
	wire[IQ1_ENTRY_N-1:0] iq1_op1_instant_rdy_flag; // OP1当前就绪
	wire[IQ1_ENTRY_N-1:0] iq1_op2_instant_rdy_flag; // OP2当前就绪
	wire[31:0] iq1_instant_op1[0:IQ1_ENTRY_N-1]; // 当前的OP1
	wire[31:0] iq1_instant_op2[0:IQ1_ENTRY_N-1]; // 当前的OP2
	// 待确认的分支指令
	/*
	提示: 实际上, 只有B指令或JALR指令是需要确认的, 因为JAL指令已经在前端(IFU)处确认
	说明: 发射队列里至多有1条分支指令是在确认中的
	*/
	reg[clogb2(IQ1_ENTRY_N-1):0] iq1_confirming_brc_inst_entry_id; // 正在确认的分支指令在发射队列中的编号
	reg[IBUS_TID_WIDTH-1:0] iq1_confirming_brc_inst_inst_id; // 正在确认的分支指令的指令ID
	reg has_confirming_brc_inst_in_iq1; // 存在正在确认的分支指令(标志)
	reg iq1_pending_for_brc_prdt_failure; // 等待初步确认为预测失败的分支指令处理完成(标志)
	wire iq1_is_confirming_brc_inst_classified_as_spec_case_0; // 正在确认的分支指令是分支预测特例#0(标志)
	wire iq1_actual_bta_of_confirming_brc_inst_rdy; // 正在确认的分支指令准备好实际的分支目标地址(标志)
	wire[31:0] iq1_actual_bta_of_confirming_brc_inst; // 正在确认的分支指令的实际的分支目标地址
	wire iq1_actual_brc_direction_of_confirming_brc_inst_rdy; // 正在确认的分支指令准备好实际的分支跳转方向(标志)
	wire iq1_actual_brc_direction_of_confirming_brc_inst; // 正在确认的分支指令的实际的分支跳转方向
	wire iq1_is_confirming_brc_inst_prdt_success; // 待确认的分支指令预测成功
	wire[31:0] iq1_corrected_prdt_addr_of_confirming_brc_inst; // 正在确认的分支指令的修正的预测地址
	reg[31:0] iq1_actual_bta_of_failed_brc_prdt_inst; // 初步确认为预测失败的分支指令的实际的分支目标地址
	reg[31:0] iq1_corrected_prdt_addr_of_failed_brc_prdt_inst; // 初步确认为预测失败的分支指令的修正的预测地址
	
	assign brc_bdcst_luc_vld = 
		// 确认了1条分支指令
		has_confirming_brc_inst_in_iq1 & 
		iq1_actual_bta_of_confirming_brc_inst_rdy & iq1_actual_brc_direction_of_confirming_brc_inst_rdy;
	assign brc_bdcst_luc_tid = 
		iq1_table_inst_id[iq1_confirming_brc_inst_entry_id];
	assign brc_bdcst_luc_is_b_inst = 
		iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_B_INST_SID];
	assign brc_bdcst_luc_is_jal_inst = 
		iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JAL_INST_SID];
	assign brc_bdcst_luc_is_jalr_inst = 
		iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JALR_INST_SID];
	assign brc_bdcst_luc_bta = 
		iq1_actual_bta_of_confirming_brc_inst;
	
	assign m_lsu_ls_sel = 
		iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_LS_SEL_SID];
	assign m_lsu_ls_type = 
		iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_LS_TYPE_SID+2:IQ1_OTHER_PAYLOAD_FIELD_LS_TYPE_SID];
	assign m_lsu_rd_id_for_ld = 5'bxxxxx; // 目标寄存器编号在ROB中已经保存, 无需在执行单元里传递
	assign m_lsu_ls_addr = 
		iq1_instant_op1[iq1_rptr][31:0] + 
		iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_LS_ADDR_OFS_SID+31:IQ1_OTHER_PAYLOAD_FIELD_LS_ADDR_OFS_SID];
	assign m_lsu_ls_din = iq1_instant_op2[iq1_rptr][31:0];
	assign m_lsu_inst_id = 
		iq1_table_inst_id[iq1_rptr];
	assign m_lsu_valid = 
		(~clr_iq1) & // 当前不正在清空发射队列#1
		iq1_table_vld_flag[iq1_rptr] & // 条目有效
		iq1_op1_instant_rdy_flag[iq1_rptr] & iq1_op2_instant_rdy_flag[iq1_rptr] & // 操作数准备好
		(iq1_table_fuid[iq1_rptr] == FU_LSU_ID); // 条目使用LSU
	
	assign m_bru_prdt_msg = 
		{
			/*
			说明:
				"实际的分支目标地址"和"修正的预测地址"只在初步确认为分支预测失败后才可用, 不过这是安全的, 因为:
					(1)如果当前待发往BRU的指令是EBREAK指令, 那么"实际的分支目标地址"和"修正的预测地址"根本不会用到
					(2)如果当前待发往BRU的指令是FENCE.I指令, 那么只会用到"顺序取指时的下一PC",
						而不会用"实际的分支目标地址"和"修正的预测地址"
					(3)如果当前待发往BRU的指令是分支指令且初步确认为分支预测成功, 那么肯定不会进行流水线冲刷,
						并且已经将"预测地址"写入了ROB里的"指令对应的下一有效PC"字段
			*/
			// 顺序取指时的下一PC
			iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_NXT_SEQ_PC+31:IQ1_OTHER_PAYLOAD_FIELD_INST_NXT_SEQ_PC],
			// 实际的分支目标地址
			(EN_LOW_LA_BRC_PRDT_FAILURE_PROC == "true") ? 
				iq1_actual_bta_of_confirming_brc_inst[31:0]:
				iq1_actual_bta_of_failed_brc_prdt_inst[31:0],
			// 前级传递的分支预测信息
			iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_BRC_PRDT_MSG+94:IQ1_OTHER_PAYLOAD_FIELD_BRC_PRDT_MSG+32],
			// 修正的预测地址
			(EN_LOW_LA_BRC_PRDT_FAILURE_PROC == "true") ? 
				iq1_corrected_prdt_addr_of_confirming_brc_inst[31:0]:
				iq1_corrected_prdt_addr_of_failed_brc_prdt_inst[31:0]
		} | 160'd0;
	assign m_bru_inst_type = 
		iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+15:IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE];
	assign m_bru_tid = 
		iq1_table_inst_id[iq1_rptr];
	assign m_bru_prdt_suc = 
		// 非分支指令始终被判定为分支预测成功
		(~(
			iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JAL_INST_SID] | 
			iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JALR_INST_SID] | 
			iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_B_INST_SID]
		)) | 
		(
			(EN_LOW_LA_BRC_PRDT_FAILURE_PROC == "true") ? 
				(
					(~((has_confirming_brc_inst_in_iq1 | iq1_pending_for_brc_prdt_failure) & (iq1_confirming_brc_inst_entry_id == iq1_rptr))) | 
					((~iq1_pending_for_brc_prdt_failure) & (has_confirming_brc_inst_in_iq1 & iq1_is_confirming_brc_inst_prdt_success))
				):
				(
					/*
					说明:
						如果当前待发往BRU的指令正在进行分支确认, 则能够通过BRU的指令肯定是分支预测成功的,
							这是因为初步确认为预测失败的分支指令需要等待1clk才能发送给BRU执行
						如果当前待发往BRU的指令已经初步判定为预测失败, 则直接向BRU给出预判分支预测失败的信号
					*/
					(~((has_confirming_brc_inst_in_iq1 | iq1_pending_for_brc_prdt_failure) & (iq1_confirming_brc_inst_entry_id == iq1_rptr))) | 
					(~iq1_pending_for_brc_prdt_failure)
				)
		);
	assign m_bru_brc_cond_res = 
		(has_confirming_brc_inst_in_iq1 & (iq1_confirming_brc_inst_entry_id == iq1_rptr)) ? 
			iq1_actual_brc_direction_of_confirming_brc_inst:
			iq1_table_actual_brc_direction_saved[iq1_rptr];
	assign m_bru_valid = 
		(~clr_iq1) & // 当前不正在清空发射队列#1
		iq1_table_vld_flag[iq1_rptr] & // 条目有效
		// 说明: 对于分支指令来说, 如果2个操作数都准备好了, 那么它实际的分支目标地址和分支跳转方向都是确定的
		iq1_op1_instant_rdy_flag[iq1_rptr] & iq1_op2_instant_rdy_flag[iq1_rptr] & // 操作数准备好
		(iq1_table_fuid[iq1_rptr] == FU_BRU_ID) & // 条目使用BRU
		(
			(~(
				iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_FENCE_I_INST_SID] | 
				iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_FENCE_INST_SID]
			)) | 
			iq1_fence_inst_allowed
		) & // FENCE或FENCE.I指令需要等待许可
		(
			(EN_LOW_LA_BRC_PRDT_FAILURE_PROC == "true") | 
			(~(
				iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JAL_INST_SID] | 
				iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JALR_INST_SID] | 
				iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_B_INST_SID]
			)) | 
			// 说明: 未在确认中的分支指令一定是已经初步确认为预测成功的, 而初步确认为预测失败的分支指令需要等待1clk才能发送给BRU执行
			(~(
				has_confirming_brc_inst_in_iq1 & (iq1_confirming_brc_inst_entry_id == iq1_rptr) & 
				(~iq1_is_confirming_brc_inst_prdt_success)
			))
		);
	
	assign is_iq1_full_n = ~(&iq1_table_vld_flag);
	
	assign is_iq1_empty_n = |iq1_table_vld_flag;
	assign iq1_fu_ready_flag = 
		((iq1_table_fuid[iq1_rptr] == FU_LSU_ID) & m_lsu_ready) | 
		((iq1_table_fuid[iq1_rptr] == FU_BRU_ID) & m_bru_ready);
	assign iq1_fence_inst_allowed = ~(has_buffered_wr_mem_req | has_processing_perph_access_req);
	assign iq1_inst_launched = 
		iq1_table_vld_flag[iq1_rptr] & // 条目有效
		iq1_op1_instant_rdy_flag[iq1_rptr] & iq1_op2_instant_rdy_flag[iq1_rptr] & // 操作数准备好
		iq1_fu_ready_flag & // 所用的执行单元准备好
		(
			(~(
				iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_FENCE_I_INST_SID] | 
				iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_FENCE_INST_SID]
			)) | 
			iq1_fence_inst_allowed
		) & // FENCE或FENCE.I指令需要等待许可
		(
			(EN_LOW_LA_BRC_PRDT_FAILURE_PROC == "true") | 
			(~(
				iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JAL_INST_SID] | 
				iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JALR_INST_SID] | 
				iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_B_INST_SID]
			)) | 
			// 说明: 未在确认中的分支指令一定是已经初步确认为预测成功的, 而初步确认为预测失败的分支指令需要等待1clk才能发送给BRU执行
			(~(
				has_confirming_brc_inst_in_iq1 & (iq1_confirming_brc_inst_entry_id == iq1_rptr) & 
				(~iq1_is_confirming_brc_inst_prdt_success)
			))
		);
	
	assign iq1_is_confirming_brc_inst_classified_as_spec_case_0 = 
		// 分支预测特例#0: BTB命中, 分支指令类型为JALR, RAS出栈标志无效
		iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_BRC_PRDT_MSG+PRDT_MSG_BTB_HIT_SID] & 
		(iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_BRC_PRDT_MSG+PRDT_MSG_BTYPE_SID+2:IQ1_OTHER_PAYLOAD_FIELD_BRC_PRDT_MSG+PRDT_MSG_BTYPE_SID] == BRANCH_TYPE_JALR) & 
		(~iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_BRC_PRDT_MSG+PRDT_MSG_POP_RAS_SID]);
	assign iq1_actual_bta_of_confirming_brc_inst_rdy = 
		// JAL指令或B指令的分支目标地址 = PC + 偏移量, 因此在进入发射队列时其分支目标地址就已准备好
		iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JAL_INST_SID] | 
		iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_B_INST_SID] | 
		// JALR的分支目标地址 = RS1 + 偏移量, 因此其分支目标地址需要等待OP1就绪才能准备好
		iq1_op1_instant_rdy_flag[iq1_confirming_brc_inst_entry_id];
	assign iq1_actual_bta_of_confirming_brc_inst = 
		(
			iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JAL_INST_SID] | 
			iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_B_INST_SID]
		) ? 
			// JAL指令或B指令的分支目标地址 = PC + 偏移量
			iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_ACTUAL_BTA+31:IQ1_OTHER_PAYLOAD_FIELD_ACTUAL_BTA]:
			// JALR的分支目标地址 = RS1 + 偏移量
			(
				iq1_instant_op1[iq1_confirming_brc_inst_entry_id] + 
				iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_BRC_JUMP_OFS+31:IQ1_OTHER_PAYLOAD_FIELD_BRC_JUMP_OFS]
			);
	assign iq1_actual_brc_direction_of_confirming_brc_inst_rdy = 
		// JAL指令或JALR指令必定是跳转的
		iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JAL_INST_SID] | 
		iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JALR_INST_SID] | 
		// B指令需要等待OP1与OP2就绪才能确定跳转方向
		(iq1_op1_instant_rdy_flag[iq1_confirming_brc_inst_entry_id] & iq1_op2_instant_rdy_flag[iq1_confirming_brc_inst_entry_id]);
	assign iq1_actual_brc_direction_of_confirming_brc_inst = 
		// JAL指令或JALR指令必定是跳转的
		iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JAL_INST_SID] | 
		iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JALR_INST_SID] | 
		// B指令比较操作: !=, ==
		(
			(
				(iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE+2:IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE] == B_TYPE_BEQ) | 
				(iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE+2:IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE] == B_TYPE_BNE)
			) & 
			(
				(iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE+2:IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE] == B_TYPE_BNE) ^ 
				(iq1_instant_op1[iq1_confirming_brc_inst_entry_id] == iq1_instant_op2[iq1_confirming_brc_inst_entry_id])
			)
		) | 
		// B指令比较操作: 有符号>=, 无符号>=, 有符号<, 无符号<
		(
			(
				(iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE+2:IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE] == B_TYPE_BLT) | 
				(iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE+2:IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE] == B_TYPE_BGE) | 
				(iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE+2:IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE] == B_TYPE_BLTU) | 
				(iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE+2:IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE] == B_TYPE_BGEU)
			) & 
			(
				(
					(iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE+2:IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE] == B_TYPE_BGE) | 
					(iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE+2:IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE] == B_TYPE_BGEU)
				) ^ 
				(
					$signed({
						(
							(iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE+2:IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE] == B_TYPE_BLT) | 
							(iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE+2:IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE] == B_TYPE_BGE)
						) & iq1_instant_op1[iq1_confirming_brc_inst_entry_id][31],
						iq1_instant_op1[iq1_confirming_brc_inst_entry_id][31:0]
					}) < 
					$signed({
						(
							(iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE+2:IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE] == B_TYPE_BLT) | 
							(iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE+2:IQ1_OTHER_PAYLOAD_FIELD_B_INST_TYPE] == B_TYPE_BGE)
						) & iq1_instant_op2[iq1_confirming_brc_inst_entry_id][31],
						iq1_instant_op2[iq1_confirming_brc_inst_entry_id][31:0]
					})
				)
			)
		);
	assign iq1_is_confirming_brc_inst_prdt_success = 
		// JAL指令默认是预测成功的, 因为JAL指令的预测失败已经在前端(IFU)处理
		iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JAL_INST_SID] | 
		(
			iq1_actual_brc_direction_of_confirming_brc_inst ? 
				/*
				实际上跳, 并且预测也是跳, 以及, 要么预测的跳转地址正确, 要么这是1次分支预测特例#0, 才算预测成功
				实际上跳, 并且预测不跳, 有可能预测成功, 比如在实际的分支目标地址正好是PC + 指令长度时,
					不过这种情况是罕见的, 可以保守地认为是预测失败
				*/
				(
					iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_BRC_PRDT_MSG+PRDT_MSG_IS_TAKEN_SID] & 
					(
						(
							iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_BRC_PRDT_MSG+PRDT_MSG_TARGET_ADDR_EXCEPT_FOR_SPEC_CASE_SID+31:IQ1_OTHER_PAYLOAD_FIELD_BRC_PRDT_MSG+PRDT_MSG_TARGET_ADDR_EXCEPT_FOR_SPEC_CASE_SID] == 
								iq1_actual_bta_of_confirming_brc_inst
						) | 
						iq1_is_confirming_brc_inst_classified_as_spec_case_0
					)
				):
				/*
				实际上不跳, 并且预测不跳, 那么必定预测成功
				实际上不跳, 并且预测跳, 有可能预测成功, 比如在预测的跳转地址正好是PC + 指令长度时,
					不过这种情况是罕见的, 可以保守地认为是预测失败
				*/
				(~iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_BRC_PRDT_MSG+PRDT_MSG_IS_TAKEN_SID])
		);
	assign iq1_corrected_prdt_addr_of_confirming_brc_inst = 
		iq1_is_confirming_brc_inst_classified_as_spec_case_0 ? 
			iq1_actual_bta_of_confirming_brc_inst: // 修正到实际的分支目标地址
			iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_BRC_PRDT_MSG+PRDT_MSG_TARGET_ADDR_EXCEPT_FOR_SPEC_CASE_SID+31:IQ1_OTHER_PAYLOAD_FIELD_BRC_PRDT_MSG+PRDT_MSG_TARGET_ADDR_EXCEPT_FOR_SPEC_CASE_SID];
	
	// 发射队列写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			iq1_wptr <= 0;
		else if(clr_iq1 | (s_wr_iq1_valid & s_wr_iq1_ready))
			iq1_wptr <= # SIM_DELAY 
				clr_iq1 ? 
					0:
					(iq1_wptr + 1'b1);
	end
	
	// 发射队列读指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			iq1_rptr <= 0;
		else if(clr_iq1 | iq1_inst_launched)
			iq1_rptr <= # SIM_DELAY 
				clr_iq1 ? 
					0:
					(iq1_rptr + 1'b1);
	end
	
	// 正在等待的EBREAK或FENCE.I指令的指令ID
	always @(posedge aclk)
	begin
		if(
			// 向发射队列#1写入了1条EBREAK或FENCE.I指令
			s_wr_iq1_valid & s_wr_iq1_ready & 
			(
				s_wr_iq1_other_payload[IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_EBREAK_INST_SID] | 
				s_wr_iq1_other_payload[IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_FENCE_I_INST_SID]
			)
		)
			iq1_pending_ebreak_fence_i_inst_id <= # SIM_DELAY s_wr_iq1_inst_id;
	end
	
	// 等待EBREAK或FENCE.I指令处理完成(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			iq1_pending_for_ebreak_fence_i_inst <= 1'b0;
		else if(
			clr_iq1 | 
			(
				iq1_pending_for_ebreak_fence_i_inst ? 
					(
						// BRU处理完这1条EBREAK或FENCE.I指令
						s_bru_o_valid & (s_bru_o_tid == iq1_pending_ebreak_fence_i_inst_id)
					):
					(
						// 向发射队列#1写入了1条EBREAK或FENCE.I指令
						s_wr_iq1_valid & s_wr_iq1_ready & 
						(
							s_wr_iq1_other_payload[IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_EBREAK_INST_SID] | 
							s_wr_iq1_other_payload[IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_FENCE_I_INST_SID]
						)
					)
			)
		)
			iq1_pending_for_ebreak_fence_i_inst <= # SIM_DELAY 
				~(clr_iq1 | iq1_pending_for_ebreak_fence_i_inst);
	end
	
	// 正在确认的分支指令在发射队列中的编号, 正在确认的分支指令的指令ID
	always @(posedge aclk)
	begin
		if(
			// 写入了1条分支指令
			s_wr_iq1_valid & s_wr_iq1_ready & 
			(
				s_wr_iq1_other_payload[IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JAL_INST_SID] | 
				s_wr_iq1_other_payload[IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JALR_INST_SID] | 
				s_wr_iq1_other_payload[IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_B_INST_SID]
			)
		)
		begin
			iq1_confirming_brc_inst_entry_id <= # SIM_DELAY iq1_wptr;
			iq1_confirming_brc_inst_inst_id <= # SIM_DELAY s_wr_iq1_inst_id;
		end
	end
	
	// 存在正在确认的分支指令(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			has_confirming_brc_inst_in_iq1 <= 1'b0;
		else if(
			clr_iq1 | 
			(
				// 写入了1条分支指令
				s_wr_iq1_valid & s_wr_iq1_ready & 
				(
					s_wr_iq1_other_payload[IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JAL_INST_SID] | 
					s_wr_iq1_other_payload[IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JALR_INST_SID] | 
					s_wr_iq1_other_payload[IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_B_INST_SID]
				)
			) | 
			(
				// 确认了1条分支指令
				has_confirming_brc_inst_in_iq1 & 
				iq1_actual_bta_of_confirming_brc_inst_rdy & iq1_actual_brc_direction_of_confirming_brc_inst_rdy
			)
		)
			has_confirming_brc_inst_in_iq1 <= # SIM_DELAY 
				(~clr_iq1) & 
				(
					(~has_confirming_brc_inst_in_iq1) | 
					(
						// 写入了1条分支指令
						s_wr_iq1_valid & s_wr_iq1_ready & 
						(
							s_wr_iq1_other_payload[IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JAL_INST_SID] | 
							s_wr_iq1_other_payload[IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JALR_INST_SID] | 
							s_wr_iq1_other_payload[IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_B_INST_SID]
						)
					)
				);
	end
	
	// 等待初步确认为预测失败的分支指令处理完成(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			iq1_pending_for_brc_prdt_failure <= 1'b0;
		else if(
			clr_iq1 | 
			(
				iq1_pending_for_brc_prdt_failure ? 
					(
						// BRU处理完这1条分支指令
						/*
						说明:
							如果正在等待初步确认为预测失败的分支指令处理完成, 那么发射队列#1不会接受新的分支指令,
							因此"正在确认的分支指令的指令ID"是可用的
						*/
						s_bru_o_valid & (s_bru_o_tid == iq1_confirming_brc_inst_inst_id)
					):
					(
						// 确认了1条分支指令, 并且这条分支指令初步确认为预测失败
						has_confirming_brc_inst_in_iq1 & 
						iq1_actual_bta_of_confirming_brc_inst_rdy & iq1_actual_brc_direction_of_confirming_brc_inst_rdy & 
						(~iq1_is_confirming_brc_inst_prdt_success) & 
						(
							(EN_LOW_LA_BRC_PRDT_FAILURE_PROC == "false") | 
							(~(s_bru_o_valid & (s_bru_o_tid == iq1_confirming_brc_inst_inst_id)))
						)
					)
			)
		)
			iq1_pending_for_brc_prdt_failure <= # SIM_DELAY 
				~(clr_iq1 | iq1_pending_for_brc_prdt_failure);
	end
	
	// 初步确认为预测失败的分支指令的实际的分支目标地址, 初步确认为预测失败的分支指令的修正的预测地址
	always @(posedge aclk)
	begin
		if(
			(~iq1_pending_for_brc_prdt_failure) & 
			// 确认了1条分支指令, 并且这条分支指令初步确认为预测失败
			has_confirming_brc_inst_in_iq1 & 
			iq1_actual_bta_of_confirming_brc_inst_rdy & iq1_actual_brc_direction_of_confirming_brc_inst_rdy & 
			(~iq1_is_confirming_brc_inst_prdt_success)
		)
		begin
			iq1_actual_bta_of_failed_brc_prdt_inst <= # SIM_DELAY iq1_actual_bta_of_confirming_brc_inst;
			iq1_corrected_prdt_addr_of_failed_brc_prdt_inst <= # SIM_DELAY iq1_corrected_prdt_addr_of_confirming_brc_inst;
		end
	end
	
	/*
	发射队列表存储负载(指令ID, 执行单元ID, ROB条目ID, 年龄标识, OP1所监听的执行单元ID, OP2所监听的执行单元ID,
		OP1所监听的指令ID, OP2所监听的指令ID, 其他负载数据)
	发射队列表保存的结果(暂存的OP1, 暂存的OP2, 保存的实际的分支跳转方向)
	发射队列表的标志(OP1就绪标志, OP2就绪标志, 有效标志)
	*/
	genvar iq1_entry_i;
	generate
		for(iq1_entry_i = 0;iq1_entry_i < IQ1_ENTRY_N;iq1_entry_i = iq1_entry_i + 1)
		begin:iq1_blk
			assign iq1_op1_instant_rdy_flag[iq1_entry_i] = 
				iq1_table_op1_rdy_flag[iq1_entry_i] | 
				(
					fu_res_vld_r[iq1_table_op1_lsn_fuid[iq1_entry_i]] & 
					(fu_res_tid_r[iq1_table_op1_lsn_fuid[iq1_entry_i]] == iq1_table_op1_lsn_inst_id[iq1_entry_i])
				) | 
				(
					(IQ1_LOW_LA_LSU_LSN_OPT_LEVEL >= 1) & 
					fu_res_vld[LSU_FU_ID] & 
					(
						fu_res_tid[IBUS_TID_WIDTH*LSU_FU_ID+(IBUS_TID_WIDTH-1):IBUS_TID_WIDTH*LSU_FU_ID] == 
							iq1_table_op1_lsn_inst_id[iq1_entry_i]
					)
				) | 
				(
					(IQ1_LOW_LA_LSU_LSN_OPT_LEVEL >= 2) & 
					on_get_instant_rd_mem_res & 
					(inst_id_of_instant_rd_mem_res_gotten == iq1_table_op1_lsn_inst_id[iq1_entry_i])
				);
			assign iq1_op2_instant_rdy_flag[iq1_entry_i] = 
				iq1_table_op2_rdy_flag[iq1_entry_i] | 
				(
					fu_res_vld_r[iq1_table_op2_lsn_fuid[iq1_entry_i]] & 
					(fu_res_tid_r[iq1_table_op2_lsn_fuid[iq1_entry_i]] == iq1_table_op2_lsn_inst_id[iq1_entry_i])
				) | 
				(
					(IQ1_LOW_LA_LSU_LSN_OPT_LEVEL >= 1) & 
					fu_res_vld[LSU_FU_ID] & 
					(
						fu_res_tid[IBUS_TID_WIDTH*LSU_FU_ID+(IBUS_TID_WIDTH-1):IBUS_TID_WIDTH*LSU_FU_ID] == 
							iq1_table_op2_lsn_inst_id[iq1_entry_i]
					)
				) | 
				(
					(IQ1_LOW_LA_LSU_LSN_OPT_LEVEL >= 2) & 
					on_get_instant_rd_mem_res & 
					(inst_id_of_instant_rd_mem_res_gotten == iq1_table_op2_lsn_inst_id[iq1_entry_i])
				);
			assign iq1_instant_op1[iq1_entry_i] = 
				iq1_table_op1_rdy_flag[iq1_entry_i] ? 
					iq1_table_op1_saved[iq1_entry_i]:
					(
						(
							(
								(IQ1_LOW_LA_LSU_LSN_OPT_LEVEL >= 1) & 
								fu_res_vld[LSU_FU_ID] & 
								(
									fu_res_tid[IBUS_TID_WIDTH*LSU_FU_ID+(IBUS_TID_WIDTH-1):IBUS_TID_WIDTH*LSU_FU_ID] == 
										iq1_table_op1_lsn_inst_id[iq1_entry_i]
								)
							) | 
							(
								(IQ1_LOW_LA_LSU_LSN_OPT_LEVEL >= 2) & 
								on_get_instant_rd_mem_res & 
								(inst_id_of_instant_rd_mem_res_gotten == iq1_table_op1_lsn_inst_id[iq1_entry_i])
							)
						) ? 
							(
								(
									(IQ1_LOW_LA_LSU_LSN_OPT_LEVEL <= 1) | 
									(
										fu_res_vld[LSU_FU_ID] & 
										(
											fu_res_tid[IBUS_TID_WIDTH*LSU_FU_ID+(IBUS_TID_WIDTH-1):IBUS_TID_WIDTH*LSU_FU_ID] == 
												iq1_table_op1_lsn_inst_id[iq1_entry_i]
										)
									)
								) ? 
									fu_res_data[32*LSU_FU_ID+31:32*LSU_FU_ID]:
									data_of_instant_rd_mem_res_gotten[31:0]
							):
							fu_res_data_r[iq1_table_op1_lsn_fuid[iq1_entry_i]]
					);
			assign iq1_instant_op2[iq1_entry_i] = 
				iq1_table_op2_rdy_flag[iq1_entry_i] ? 
					iq1_table_op2_saved[iq1_entry_i]:
					(
						(
							(
								(IQ1_LOW_LA_LSU_LSN_OPT_LEVEL >= 1) & 
								fu_res_vld[LSU_FU_ID] & 
								(
									fu_res_tid[IBUS_TID_WIDTH*LSU_FU_ID+(IBUS_TID_WIDTH-1):IBUS_TID_WIDTH*LSU_FU_ID] == 
										iq1_table_op2_lsn_inst_id[iq1_entry_i]
								)
							) | 
							(
								(IQ1_LOW_LA_LSU_LSN_OPT_LEVEL >= 2) & 
								on_get_instant_rd_mem_res & 
								(inst_id_of_instant_rd_mem_res_gotten == iq1_table_op2_lsn_inst_id[iq1_entry_i])
							)
						) ? 
							(
								(
									(IQ1_LOW_LA_LSU_LSN_OPT_LEVEL <= 1) | 
									(
										fu_res_vld[LSU_FU_ID] & 
										(
											fu_res_tid[IBUS_TID_WIDTH*LSU_FU_ID+(IBUS_TID_WIDTH-1):IBUS_TID_WIDTH*LSU_FU_ID] == 
												iq1_table_op2_lsn_inst_id[iq1_entry_i]
										)
									)
								) ? 
									fu_res_data[32*LSU_FU_ID+31:32*LSU_FU_ID]:
									data_of_instant_rd_mem_res_gotten[31:0]
							):
							fu_res_data_r[iq1_table_op2_lsn_fuid[iq1_entry_i]]
					);
			
			always @(posedge aclk)
			begin
				if(s_wr_iq1_valid & s_wr_iq1_ready & (iq1_wptr == iq1_entry_i))
				begin
					iq1_table_inst_id[iq1_entry_i] <= # SIM_DELAY s_wr_iq1_inst_id;
					iq1_table_fuid[iq1_entry_i] <= # SIM_DELAY s_wr_iq1_fuid[clogb2(LSN_FU_N-1):0];
					iq1_table_rob_entry_id[iq1_entry_i] <= # SIM_DELAY s_wr_iq1_rob_entry_id;
					iq1_table_age_tag[iq1_entry_i] <= # SIM_DELAY s_wr_iq1_age_tag;
					iq1_table_op1_lsn_fuid[iq1_entry_i] <= # SIM_DELAY s_wr_iq1_op1_lsn_fuid[clogb2(LSN_FU_N-1):0];
					iq1_table_op2_lsn_fuid[iq1_entry_i] <= # SIM_DELAY s_wr_iq1_op2_lsn_fuid[clogb2(LSN_FU_N-1):0];
					iq1_table_op1_lsn_inst_id[iq1_entry_i] <= # SIM_DELAY s_wr_iq1_op1_lsn_inst_id;
					iq1_table_op2_lsn_inst_id[iq1_entry_i] <= # SIM_DELAY s_wr_iq1_op2_lsn_inst_id;
					iq1_table_other_payload[iq1_entry_i] <= # SIM_DELAY s_wr_iq1_other_payload;
				end
			end
			
			always @(posedge aclk)
			begin
				if(
					(s_wr_iq1_valid & s_wr_iq1_ready & s_wr_iq1_op1_rdy & (iq1_wptr == iq1_entry_i)) | 
					(
						iq1_table_vld_flag[iq1_entry_i] & 
						(~iq1_table_op1_rdy_flag[iq1_entry_i]) & 
						/*
						说明:
							对LSU的低时延监听, 其结果是没有必要锁存的, 即使因为各种原因无法在本clk发射这条指令,
							下1clk也能重新得到同样的LSU执行结果
						*/
						(
							fu_res_vld_r[iq1_table_op1_lsn_fuid[iq1_entry_i]] & 
							(fu_res_tid_r[iq1_table_op1_lsn_fuid[iq1_entry_i]] == iq1_table_op1_lsn_inst_id[iq1_entry_i])
						)
					)
				)
					iq1_table_op1_saved[iq1_entry_i] <= # SIM_DELAY 
						iq1_table_vld_flag[iq1_entry_i] ? 
							fu_res_data_r[iq1_table_op1_lsn_fuid[iq1_entry_i]]:
							s_wr_iq1_op1_pre_fetched;
			end
			
			always @(posedge aclk)
			begin
				if(
					(s_wr_iq1_valid & s_wr_iq1_ready & s_wr_iq1_op2_rdy & (iq1_wptr == iq1_entry_i)) | 
					(
						iq1_table_vld_flag[iq1_entry_i] & 
						(~iq1_table_op2_rdy_flag[iq1_entry_i]) & 
						/*
						说明:
							对LSU的低时延监听, 其结果是没有必要锁存的, 即使因为各种原因无法在本clk发射这条指令,
							下1clk也能重新得到同样的LSU执行结果
						*/
						(
							fu_res_vld_r[iq1_table_op2_lsn_fuid[iq1_entry_i]] & 
							(fu_res_tid_r[iq1_table_op2_lsn_fuid[iq1_entry_i]] == iq1_table_op2_lsn_inst_id[iq1_entry_i])
						)
					)
				)
					iq1_table_op2_saved[iq1_entry_i] <= # SIM_DELAY 
						iq1_table_vld_flag[iq1_entry_i] ? 
							fu_res_data_r[iq1_table_op2_lsn_fuid[iq1_entry_i]]:
							s_wr_iq1_op2_pre_fetched;
			end
			
			always @(posedge aclk)
			begin
				if(
					// 确认了当前这条分支指令的实际跳转方向
					has_confirming_brc_inst_in_iq1 & iq1_actual_brc_direction_of_confirming_brc_inst_rdy & 
					(iq1_confirming_brc_inst_entry_id == iq1_entry_i)
				)
					iq1_table_actual_brc_direction_saved[iq1_entry_i] <= # SIM_DELAY 
						iq1_actual_brc_direction_of_confirming_brc_inst;
			end
			
			always @(posedge aclk)
			begin
				if(
					(s_wr_iq1_valid & s_wr_iq1_ready & (iq1_wptr == iq1_entry_i)) | 
					(
						iq1_table_vld_flag[iq1_entry_i] & 
						(~iq1_table_op1_rdy_flag[iq1_entry_i]) & 
						/*
						说明:
							对LSU的低时延监听, 其结果是没有必要锁存的, 即使因为各种原因无法在本clk发射这条指令,
							下1clk也能重新得到同样的LSU执行结果
						*/
						(
							fu_res_vld_r[iq1_table_op1_lsn_fuid[iq1_entry_i]] & 
							(fu_res_tid_r[iq1_table_op1_lsn_fuid[iq1_entry_i]] == iq1_table_op1_lsn_inst_id[iq1_entry_i])
						)
					)
				)
					iq1_table_op1_rdy_flag[iq1_entry_i] <= # SIM_DELAY 
						iq1_table_vld_flag[iq1_entry_i] | 
						s_wr_iq1_op1_rdy; // 写入条目时初始化OP1就绪标志
			end
			
			always @(posedge aclk)
			begin
				if(
					(s_wr_iq1_valid & s_wr_iq1_ready & (iq1_wptr == iq1_entry_i)) | 
					(
						iq1_table_vld_flag[iq1_entry_i] & 
						(~iq1_table_op2_rdy_flag[iq1_entry_i]) & 
						/*
						说明:
							对LSU的低时延监听, 其结果是没有必要锁存的, 即使因为各种原因无法在本clk发射这条指令,
							下1clk也能重新得到同样的LSU执行结果
						*/
						(
							fu_res_vld_r[iq1_table_op2_lsn_fuid[iq1_entry_i]] & 
							(fu_res_tid_r[iq1_table_op2_lsn_fuid[iq1_entry_i]] == iq1_table_op2_lsn_inst_id[iq1_entry_i])
						)
					)
				)
					iq1_table_op2_rdy_flag[iq1_entry_i] <= # SIM_DELAY 
						iq1_table_vld_flag[iq1_entry_i] | 
						s_wr_iq1_op2_rdy; // 写入条目时初始化OP2就绪标志
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					iq1_table_vld_flag[iq1_entry_i] <= 1'b0;
				else if(
					clr_iq1 | 
					(s_wr_iq1_valid & s_wr_iq1_ready & (iq1_wptr == iq1_entry_i)) | 
					(iq1_inst_launched & (iq1_rptr == iq1_entry_i))
				)
					iq1_table_vld_flag[iq1_entry_i] <= # SIM_DELAY 
						(~clr_iq1) & 
						s_wr_iq1_valid & s_wr_iq1_ready & (iq1_wptr == iq1_entry_i);
			end
		end
	endgenerate
	
	/** 写发射队列控制 **/
	wire brc_path_confirmed; // 分支路径已确认(标志)
	
	assign s_wr_iq0_ready = 
		(~clr_iq0) & 
		brc_path_confirmed & (~iq1_pending_for_ebreak_fence_i_inst) & 
		is_iq0_full_n;
	
	assign s_wr_iq1_ready = 
		(~clr_iq1) & 
		brc_path_confirmed & (~iq1_pending_for_ebreak_fence_i_inst) & 
		is_iq1_full_n;
	
	assign brc_path_confirmed = 
		(~(has_confirming_brc_inst_in_iq1 | iq1_pending_for_brc_prdt_failure)) | 
		(
			// 确认了1条分支指令, 并且判定是预测成功的
			has_confirming_brc_inst_in_iq1 & 
			iq1_actual_bta_of_confirming_brc_inst_rdy & iq1_actual_brc_direction_of_confirming_brc_inst_rdy & 
			iq1_is_confirming_brc_inst_prdt_success
		);
	
	/** BRU名义结果 **/
	wire bru_nominal_res_vld_w; // 有效标志
	wire[IBUS_TID_WIDTH-1:0] bru_nominal_res_tid_w; // 指令ID
	wire[31:0] bru_nominal_res_w; // 执行结果
	reg bru_nominal_res_vld_r; // 有效标志
	reg[IBUS_TID_WIDTH-1:0] bru_nominal_res_tid_r; // 指令ID
	reg[31:0] bru_nominal_res_r; // 执行结果
	
	assign bru_nominal_res_vld = (BRU_NOMINAL_RES_LATENCY == 0) ? bru_nominal_res_vld_w:bru_nominal_res_vld_r;
	assign bru_nominal_res_tid = (BRU_NOMINAL_RES_LATENCY == 0) ? bru_nominal_res_tid_w:bru_nominal_res_tid_r;
	assign bru_nominal_res = (BRU_NOMINAL_RES_LATENCY == 0) ? bru_nominal_res_w:bru_nominal_res_r;
	
	assign bru_nominal_res_vld_w = 
		// 当前不正在清空发射队列#1
		(~clr_iq1) & 
		// 发射了1条分支指令或EBREAK指令或FENCE指令或FENCE.I指令
		iq1_inst_launched & 
		(
			iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JAL_INST_SID] | 
			iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_JALR_INST_SID] | 
			iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_B_INST_SID] | 
			iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_EBREAK_INST_SID] | 
			iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_FENCE_INST_SID] | 
			iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_FENCE_I_INST_SID]
		);
	assign bru_nominal_res_tid_w = 
		iq1_table_inst_id[iq1_rptr];
	assign bru_nominal_res_w = 
		// 说明: 虽然B指令、EBREAK指令、FENCE指令、FENCE.I指令本身是没有目的寄存器(Rd)的, 不过还是要给出虚拟结果来通知ROB这条指令已完成
		iq1_table_other_payload[iq1_rptr][IQ1_OTHER_PAYLOAD_FIELD_INST_NXT_SEQ_PC+31:IQ1_OTHER_PAYLOAD_FIELD_INST_NXT_SEQ_PC];
	
	// 警告: 这些寄存器没有使能信号, 可能增加功耗
	always @(posedge aclk)
	begin
		{bru_nominal_res_tid_r, bru_nominal_res_r} <= # SIM_DELAY {bru_nominal_res_tid_w, bru_nominal_res_w};
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			bru_nominal_res_vld_r <= 1'b0;
		else
			bru_nominal_res_vld_r <= # SIM_DELAY bru_nominal_res_vld_w;
	end
	
	/** 更新ROB的"CSR更新掩码或更新值"字段 **/
	reg saving_csr_rw_msg_vld_r; // 更新指示
	reg[31:0] saving_csr_rw_msg_upd_mask_v_r; // 更新掩码或更新值
	reg[7:0] saving_csr_rw_msg_rob_entry_id_r; // ROB条目编号
	
	assign saving_csr_rw_msg_upd_mask_v = saving_csr_rw_msg_upd_mask_v_r;
	assign saving_csr_rw_msg_rob_entry_id = saving_csr_rw_msg_rob_entry_id_r;
	assign saving_csr_rw_msg_vld = saving_csr_rw_msg_vld_r;
	
	// 更新指示
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			saving_csr_rw_msg_vld_r <= 1'b0;
		else
			saving_csr_rw_msg_vld_r <= # SIM_DELAY 
				// 发射了1条发往CSR原子读写单元的指令
				(|iq0_issue_allowed_flag) & 
				(iq0_table_fuid[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]] == FU_CSR_ID);
	end
	
	// 更新掩码或更新值, ROB条目编号
	always @(posedge aclk)
	begin
		if(
			// 发射了1条发往CSR原子读写单元的指令
			(|iq0_issue_allowed_flag) & 
			(iq0_table_fuid[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]] == FU_CSR_ID)
		)
		begin
			saving_csr_rw_msg_upd_mask_v_r <= # SIM_DELAY 
				iq0_instant_op1[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]];
			
			saving_csr_rw_msg_rob_entry_id_r <= # SIM_DELAY 
				iq0_table_rob_entry_id[iq0_issue_arb_fnl_id[clogb2(IQ0_ENTRY_N-1):0]];
		end
	end
	
	/** 更新ROB的"指令对应的下一有效PC"字段 **/
	reg on_upd_rob_field_nxt_pc_r; // 更新指示
	reg[IBUS_TID_WIDTH-1:0] inst_id_of_upd_rob_field_nxt_pc_r; // 指令ID
	reg[31:0] rob_field_nxt_pc_r; // 指令对应的下一有效PC
	
	assign on_upd_rob_field_nxt_pc = on_upd_rob_field_nxt_pc_r;
	assign inst_id_of_upd_rob_field_nxt_pc = inst_id_of_upd_rob_field_nxt_pc_r;
	assign rob_field_nxt_pc = rob_field_nxt_pc_r;
	
	// 更新指示
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			on_upd_rob_field_nxt_pc_r <= 1'b0;
		else
			on_upd_rob_field_nxt_pc_r <= # SIM_DELAY 
				// 当前不正在清空发射队列#1
				(~clr_iq1) & 
				// 确认了1条分支指令, 并且这条分支指令初步确认为预测失败或者这是1个分支预测特例#0
				has_confirming_brc_inst_in_iq1 & 
				iq1_actual_bta_of_confirming_brc_inst_rdy & iq1_actual_brc_direction_of_confirming_brc_inst_rdy & 
				((~iq1_is_confirming_brc_inst_prdt_success) | iq1_is_confirming_brc_inst_classified_as_spec_case_0);
	end
	
	// 指令ID, 指令对应的下一有效PC
	always @(posedge aclk)
	begin
		if(
			// 当前不正在清空发射队列#1
			(~clr_iq1) & 
			// 确认了1条分支指令, 并且这条分支指令初步确认为预测失败或者这是1个分支预测特例#0
			has_confirming_brc_inst_in_iq1 & 
			iq1_actual_bta_of_confirming_brc_inst_rdy & iq1_actual_brc_direction_of_confirming_brc_inst_rdy & 
			((~iq1_is_confirming_brc_inst_prdt_success) | iq1_is_confirming_brc_inst_classified_as_spec_case_0)
		)
		begin
			inst_id_of_upd_rob_field_nxt_pc_r <= # SIM_DELAY iq1_table_inst_id[iq1_confirming_brc_inst_entry_id];
			
			rob_field_nxt_pc_r <= # SIM_DELAY 
				(
					iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_INST_TYPE+INST_TYPE_FLAG_IS_B_INST_SID] & 
					(~iq1_actual_brc_direction_of_confirming_brc_inst)
				) ? 
					iq1_table_other_payload[iq1_confirming_brc_inst_entry_id][IQ1_OTHER_PAYLOAD_FIELD_INST_NXT_SEQ_PC+31:IQ1_OTHER_PAYLOAD_FIELD_INST_NXT_SEQ_PC]:
					iq1_actual_bta_of_confirming_brc_inst;
		end
	end
	
endmodule
