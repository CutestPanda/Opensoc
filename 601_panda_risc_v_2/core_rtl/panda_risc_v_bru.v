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
本模块: 分支处理单元

描述:
提供"重置"信号, 用于后级(交付)镇压BRU给出的冲刷请求

如果是以下情形中的一种: 
	(1)发生分支预测失败
	(2)输入的是FENCE.I指令
	(3)当前处于调试模式, 且输入的是EBREAK指令
则在本clk(若启用立即冲刷)/下1个clk开始冲刷

注意：
无

协议:
REQ/GRANT

作者: 陈家耀
日期: 2026/01/22
********************************************************************/


module panda_risc_v_bru #(
	parameter integer IBUS_TID_WIDTH = 8, // 指令总线事务ID位宽(1~16)
	parameter EN_IMDT_FLUSH = "false", // 是否启用立即冲刷
	parameter DEBUG_ROM_ADDR = 32'h0000_0600, // Debug ROM基地址
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 当前处于调试模式(标志)
	input wire in_dbg_mode,
	
	// 控制/状态
	input wire rst_bru, // 重置BRU
	output wire[31:0] jal_inst_n_acpt, // 接受的JAL指令总数
	output wire[31:0] jal_prdt_success_inst_n, // 预测正确的JAL指令数
	output wire[31:0] jalr_inst_n_acpt, // 接受的JALR指令总数
	output wire[31:0] jalr_prdt_success_inst_n, // 预测正确的JALR指令数
	output wire[31:0] b_inst_n_acpt, // 接受的B指令总数
	output wire[31:0] b_prdt_success_inst_n, // 预测正确的B指令数
	output wire[31:0] common_inst_n_acpt, // 接受的非分支指令总数
	output wire[31:0] common_prdt_success_inst_n, // 预测正确的非分支指令数
	output wire[31:0] brc_inst_n_acpt, // 接受的分支指令总数
	output wire[31:0] brc_inst_with_btb_hit_n, // BTB命中的分支指令总数
	
	// BRU给出的冲刷请求
	output wire bru_flush_req, // 冲刷请求
	output wire[31:0] bru_flush_addr, // 冲刷地址
	input wire bru_flush_grant, // 冲刷许可
	
	// ALU给出的分支判定结果
	// 说明: BRU输入有效(s_bru_i_valid有效)且指令类型为B指令时, 分支判定结果必定有效
	input wire alu_brc_cond_res,
	
	// BRU输入
	input wire[127:0] s_bru_i_data, // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	input wire[146:0] s_bru_i_msg, // 取指附加信息({分支预测信息(144bit), 错误码(3bit)})
	input wire[143:0] s_bru_i_dcd_res, // 译码信息({打包的FU操作信息(128bit), 打包的指令类型标志(16bit)})
	input wire[IBUS_TID_WIDTH-1:0] s_bru_i_tid, // 指令ID
	input wire s_bru_i_valid,
	output wire s_bru_i_ready,
	
	// BRU输出
	output wire[IBUS_TID_WIDTH-1:0] m_bru_o_tid, // 指令ID
	output wire[31:0] m_bru_o_pc, // 当前PC地址
	output wire[31:0] m_bru_o_nxt_pc, // 下一有效PC地址
	output wire[1:0] m_bru_o_b_inst_res, // B指令执行结果
	output wire m_bru_o_valid
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
	localparam integer PRDT_MSG_ACTUAL_BTA_SID = 79; // 实际的分支目标地址
	localparam integer PRDT_MSG_NXT_SEQ_PC_SID = 111; // 顺序取指时的下一PC
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
	// 指令错误码
	localparam INST_ERR_CODE_NORMAL = 3'b000; // 正常
	localparam INST_ERR_CODE_ILLEGAL = 3'b001; // 非法指令
	localparam INST_ERR_CODE_PC_UNALIGNED = 3'b010; // 指令地址非对齐
	localparam INST_ERR_CODE_IMEM_ACCESS_FAILED = 3'b011; // 指令总线访问失败
	localparam INST_ERR_CODE_RD_DBUS_FAILED = 3'b100; // 读存储映射失败
	localparam INST_ERR_CODE_WT_DBUS_FAILED = 3'b101; // 写存储映射失败
	localparam INST_ERR_CODE_RD_DBUS_UNALIGNED = 3'b110; // 读存储映射地址非对齐
	localparam INST_ERR_CODE_WT_DBUS_UNALIGNED = 3'b111; // 写存储映射地址非对齐
	// B指令执行结果
	localparam B_INST_RES_NONE = 2'b00; // 不是B指令
	localparam B_INST_RES_TAKEN = 2'b01; // B指令跳转
	localparam B_INST_RES_NOT_TAKEN = 2'b10; // B指令不跳
	
	/** 分支预测确认 **/
	wire is_brc_inst; // 是否分支指令(标志)
	wire prdt_success; // 分支预测成功(标志)
	wire[31:0] actual_bta; // 实际的分支目标地址
	wire[31:0] nxt_seq_pc; // 顺序取指时的下一PC
	wire[31:0] prdt_jmp_addr; // 预测的跳转地址
	wire[31:0] actual_jmp_addr; // 实际的跳转地址
	
	assign is_brc_inst = 
		(~s_bru_i_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & (
			s_bru_i_dcd_res[INST_TYPE_FLAG_IS_B_INST_SID] | 
			s_bru_i_dcd_res[INST_TYPE_FLAG_IS_JAL_INST_SID] | 
			s_bru_i_dcd_res[INST_TYPE_FLAG_IS_JALR_INST_SID]
		);
	
	// 说明: 即使不是分支指令, 也可能预测跳转, 这只在"指令自修改"时可能发生, 因为此时BTB中的分支信息是过时的
	assign prdt_success = prdt_jmp_addr == actual_jmp_addr;
	
	assign actual_bta = s_bru_i_msg[31+PRDT_MSG_ACTUAL_BTA_SID+3:PRDT_MSG_ACTUAL_BTA_SID+3];
	assign nxt_seq_pc = s_bru_i_msg[31+PRDT_MSG_NXT_SEQ_PC_SID+3:PRDT_MSG_NXT_SEQ_PC_SID+3];
	assign prdt_jmp_addr = s_bru_i_msg[31+PRDT_MSG_TARGET_ADDR_SID+3:PRDT_MSG_TARGET_ADDR_SID+3];
	
	assign actual_jmp_addr = 
		((~is_brc_inst) | (s_bru_i_dcd_res[INST_TYPE_FLAG_IS_B_INST_SID] & (~alu_brc_cond_res))) ? 
			nxt_seq_pc:
			actual_bta;
	
	/** 处理FENCE.I指令 **/
	wire is_fence_i_inst; // 是否FENCE.I指令(标志)
	
	assign is_fence_i_inst = 
		(~s_bru_i_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & 
		s_bru_i_dcd_res[INST_TYPE_FLAG_IS_FENCE_I_INST_SID];
	
	/** 处理调试模式下的EBREAK指令 **/
	wire is_ebreak_inst; // 是否EBREAK指令(标志)
	
	assign is_ebreak_inst = 
		(~s_bru_i_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & 
		s_bru_i_dcd_res[INST_TYPE_FLAG_IS_EBREAK_INST_SID];
	
	/** 产生冲刷请求 **/
	wire need_flush; // 需要冲刷(标志)
	wire[31:0] flush_addr_cur; // 当前的冲刷地址
	reg bru_flush_pending; // 等待BRU冲刷完成(标志)
	reg[31:0] bru_flush_addr_gen; // 生成的冲刷地址
	
	assign bru_flush_req = 
		(~rst_bru) & 
		(
			bru_flush_pending | 
			(
				(EN_IMDT_FLUSH == "true") & s_bru_i_valid & need_flush
			)
		);
	assign bru_flush_addr = 
		((EN_IMDT_FLUSH == "false") | bru_flush_pending) ? 
			bru_flush_addr_gen:
			flush_addr_cur;
	
	/*
	说明: 
		如果当前有正在等待的冲刷请求, 则不会接受需要冲刷的输入(分支预测失败、FENCE.I指令、调试模式下的EBREAK指令)
		后级(交付)镇压时, 接受或不接受输入都是无所谓的, 因为后级此时通常是发生了异常/中断/调试, 这个时候肯定也是要冲刷CPU前端
	*/
	assign s_bru_i_ready = rst_bru | (~bru_flush_pending) | (~need_flush);
	
	assign m_bru_o_tid = s_bru_i_tid;
	assign m_bru_o_pc = s_bru_i_data[127:96];
	// 说明: 下一有效PC地址未考虑到中断/异常, 只考虑了实际的分支跳转地址
	assign m_bru_o_nxt_pc = actual_jmp_addr;
	assign m_bru_o_b_inst_res = 
		(
			(~s_bru_i_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & 
			s_bru_i_dcd_res[INST_TYPE_FLAG_IS_B_INST_SID]
		) ? 
			(
				alu_brc_cond_res ? 
					B_INST_RES_TAKEN:
					B_INST_RES_NOT_TAKEN
			):
			B_INST_RES_NONE;
	assign m_bru_o_valid = s_bru_i_valid & s_bru_i_ready;
	
	assign need_flush = (~prdt_success) | is_fence_i_inst | (in_dbg_mode & is_ebreak_inst);
	assign flush_addr_cur = 
		(in_dbg_mode & is_ebreak_inst) ? 
			DEBUG_ROM_ADDR:
			actual_jmp_addr;
	
	// 等待BRU冲刷完成(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			bru_flush_pending <= 1'b0;
		else if(
			rst_bru | 
			(
				bru_flush_pending ? 
					bru_flush_grant:
					(s_bru_i_valid & need_flush & ((EN_IMDT_FLUSH == "false") | (~bru_flush_grant)))
			)
		)
			bru_flush_pending <= # SIM_DELAY ~(rst_bru | bru_flush_pending);
	end
	
	// 生成的冲刷地址
	always @(posedge aclk)
	begin
		if((~bru_flush_pending) & s_bru_i_valid & need_flush & ((EN_IMDT_FLUSH == "false") | (~bru_flush_grant)))
			bru_flush_addr_gen <= # SIM_DELAY flush_addr_cur;
	end
	
	/** 分支预测统计信息 **/
	reg[31:0] jal_inst_n_acpt_r; // 接受的JAL指令总数
	reg[31:0] jal_prdt_success_inst_n_r; // 预测正确的JAL指令数
	reg[31:0] jalr_inst_n_acpt_r; // 接受的JALR指令总数
	reg[31:0] jalr_prdt_success_inst_n_r; // 预测正确的JALR指令数
	reg[31:0] b_inst_n_acpt_r; // 接受的B指令总数
	reg[31:0] b_prdt_success_inst_n_r; // 预测正确的B指令数
	reg[31:0] common_inst_n_acpt_r; // 接受的非分支指令总数
	reg[31:0] common_prdt_success_inst_n_r; // 预测正确的非分支指令数
	reg[31:0] brc_inst_n_acpt_r; // 接受的分支指令总数
	reg[31:0] brc_inst_with_btb_hit_n_r; // BTB命中的分支指令总数
	
	assign jal_inst_n_acpt = jal_inst_n_acpt_r;
	assign jal_prdt_success_inst_n = jal_prdt_success_inst_n_r;
	assign jalr_inst_n_acpt = jalr_inst_n_acpt_r;
	assign jalr_prdt_success_inst_n = jalr_prdt_success_inst_n_r;
	assign b_inst_n_acpt = b_inst_n_acpt_r;
	assign b_prdt_success_inst_n = b_prdt_success_inst_n_r;
	assign common_inst_n_acpt = common_inst_n_acpt_r;
	assign common_prdt_success_inst_n = common_prdt_success_inst_n_r;
	assign brc_inst_n_acpt = brc_inst_n_acpt_r;
	assign brc_inst_with_btb_hit_n = brc_inst_with_btb_hit_n_r;
	
	// 接受的JAL指令总数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			jal_inst_n_acpt_r <= 32'd0;
		else if(
			s_bru_i_valid & s_bru_i_ready & 
			(~s_bru_i_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & s_bru_i_dcd_res[INST_TYPE_FLAG_IS_JAL_INST_SID]
		)
			jal_inst_n_acpt_r <= # SIM_DELAY jal_inst_n_acpt_r + 1'b1;
	end
	// 预测正确的JAL指令数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			jal_prdt_success_inst_n_r <= 32'd0;
		else if(
			s_bru_i_valid & s_bru_i_ready & 
			(~s_bru_i_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & s_bru_i_dcd_res[INST_TYPE_FLAG_IS_JAL_INST_SID] & 
			prdt_success
		)
			jal_prdt_success_inst_n_r <= # SIM_DELAY jal_prdt_success_inst_n_r + 1'b1;
	end
	
	// 接受的JALR指令总数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			jalr_inst_n_acpt_r <= 32'd0;
		else if(
			s_bru_i_valid & s_bru_i_ready & 
			(~s_bru_i_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & s_bru_i_dcd_res[INST_TYPE_FLAG_IS_JALR_INST_SID]
		)
			jalr_inst_n_acpt_r <= # SIM_DELAY jalr_inst_n_acpt_r + 1'b1;
	end
	// 预测正确的JALR指令数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			jalr_prdt_success_inst_n_r <= 32'd0;
		else if(
			s_bru_i_valid & s_bru_i_ready & 
			(~s_bru_i_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & s_bru_i_dcd_res[INST_TYPE_FLAG_IS_JALR_INST_SID] & 
			prdt_success
		)
			jalr_prdt_success_inst_n_r <= # SIM_DELAY jalr_prdt_success_inst_n_r + 1'b1;
	end
	
	// 接受的B指令总数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			b_inst_n_acpt_r <= 32'd0;
		else if(
			s_bru_i_valid & s_bru_i_ready & 
			(~s_bru_i_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & s_bru_i_dcd_res[INST_TYPE_FLAG_IS_B_INST_SID]
		)
			b_inst_n_acpt_r <= # SIM_DELAY b_inst_n_acpt_r + 1'b1;
	end
	// 预测正确的B指令数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			b_prdt_success_inst_n_r <= 32'd0;
		else if(
			s_bru_i_valid & s_bru_i_ready & 
			(~s_bru_i_dcd_res[INST_TYPE_FLAG_IS_ILLEGAL_INST_SID]) & s_bru_i_dcd_res[INST_TYPE_FLAG_IS_B_INST_SID] & 
			prdt_success
		)
			b_prdt_success_inst_n_r <= # SIM_DELAY b_prdt_success_inst_n_r + 1'b1;
	end
	
	// 接受的非分支指令总数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			common_inst_n_acpt_r <= 32'd0;
		else if(
			s_bru_i_valid & s_bru_i_ready & 
			(~is_brc_inst)
		)
			common_inst_n_acpt_r <= # SIM_DELAY common_inst_n_acpt_r + 1'b1;
	end
	// 预测正确的非分支指令数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			common_prdt_success_inst_n_r <= 32'd0;
		else if(
			s_bru_i_valid & s_bru_i_ready & 
			(~is_brc_inst) & 
			prdt_success
		)
			common_prdt_success_inst_n_r <= # SIM_DELAY common_prdt_success_inst_n_r + 1'b1;
	end
	
	// 接受的分支指令总数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			brc_inst_n_acpt_r <= 32'd0;
		else if(
			s_bru_i_valid & s_bru_i_ready & 
			is_brc_inst
		)
			brc_inst_n_acpt_r <= # SIM_DELAY brc_inst_n_acpt_r + 1'b1;
	end
	// BTB命中的分支指令总数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			brc_inst_with_btb_hit_n_r <= 32'd0;
		else if(
			s_bru_i_valid & s_bru_i_ready & 
			is_brc_inst & 
			s_bru_i_msg[PRDT_MSG_BTB_HIT_SID+3]
		)
			brc_inst_with_btb_hit_n_r <= # SIM_DELAY brc_inst_with_btb_hit_n_r + 1'b1;
	end
	
endmodule
