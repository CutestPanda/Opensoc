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
本模块: 发射单元

描述:
发射阶段的段寄存器
只能存储1条已发射的指令
检查是否允许发射屏障指令、CSR读写指令

注意：
复位/冲刷时不接收前级的"取指结果", 也不取操作数, 并复位"选择锁存的操作数标志"

协议:
无

作者: 陈家耀
日期: 2026/01/24
********************************************************************/


module panda_risc_v_launch #(
	parameter integer IBUS_TID_WIDTH = 8, // 指令总线事务ID位宽(1~16)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// ROB状态
	input wire rob_full_n, // ROB满(标志)
	input wire rob_csr_rw_inst_allowed, // 允许发射CSR读写指令(标志)
	
	// LSU状态
	input wire has_buffered_wr_mem_req, // 存在已缓存的写存储器请求(标志)
	input wire has_processing_perph_access_req, // 存在处理中的外设访问请求(标志)
	
	// 复位/冲刷
	input wire sys_reset_req, // 系统复位请求
	input wire flush_req, // 冲刷请求
	
	// 取操作数和译码结果
	input wire[127:0] s_op_ftc_id_res_data, // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	input wire[162:0] s_op_ftc_id_res_msg, // 取指附加信息({分支预测信息(160bit), 错误码(3bit)})
	input wire[143:0] s_op_ftc_id_res_dcd_res, // 译码信息({打包的FU操作信息(128bit), 打包的指令类型标志(16bit)})
	input wire[IBUS_TID_WIDTH-1:0] s_op_ftc_id_res_id, // 指令编号
	input wire s_op_ftc_id_res_is_first_inst_after_rst, // 是否复位释放后的第1条指令
	input wire[31:0] s_op_ftc_id_res_op1, // 操作数1
	input wire[31:0] s_op_ftc_id_res_op2, // 操作数2
	input wire s_op_ftc_id_res_valid,
	output wire s_op_ftc_id_res_ready,
	
	// 发射单元输出
	output wire[127:0] m_luc_data, // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	output wire[162:0] m_luc_msg, // 取指附加信息({分支预测信息(160bit), 错误码(3bit)})
	output wire[143:0] m_luc_dcd_res, // 译码信息({打包的FU操作信息(128bit), 打包的指令类型标志(16bit)})
	output wire[IBUS_TID_WIDTH-1:0] m_luc_id, // 指令编号
	output wire m_luc_is_first_inst_after_rst, // 是否复位释放后的第1条指令
	output wire[31:0] m_luc_op1, // 操作数1
	output wire[31:0] m_luc_op2, // 操作数2
	output wire m_luc_valid,
	input wire m_luc_ready
);
	
	/** 常量 **/
	// 段寄存器负载数据的位宽
	localparam integer STAGE_REGS_PAYLOAD_WIDTH = 128 + 163 + 144 + IBUS_TID_WIDTH + 1 + 32 + 32;
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
	
	/** 段寄存器 **/
	reg[STAGE_REGS_PAYLOAD_WIDTH-1:0] luc_stage_data;
	reg luc_stage_valid;
	wire fence_csr_rw_allowed; // 允许通过屏障与CSR读写指令(标志)
	
	assign s_op_ftc_id_res_ready = 
		(~(sys_reset_req | flush_req)) & 
		((~luc_stage_valid) | m_luc_ready) & 
		rob_full_n & fence_csr_rw_allowed; // ROB非满, 且允许通过屏障指令、CSR读写指令
	
	assign {
		m_luc_data, 
		m_luc_msg, 
		m_luc_dcd_res, 
		m_luc_id, 
		m_luc_is_first_inst_after_rst, 
		m_luc_op1, 
		m_luc_op2
	} = luc_stage_data;
	assign m_luc_valid = luc_stage_valid;
	
	assign fence_csr_rw_allowed = 
		s_op_ftc_id_res_data[32+PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID] | 
		(
			(
				(~(
					s_op_ftc_id_res_data[32+PRE_DCD_MSG_IS_FENCE_I_INST_SID] | 
					s_op_ftc_id_res_data[32+PRE_DCD_MSG_IS_FENCE_INST_SID]
				)) | 
				((~has_buffered_wr_mem_req) & (~has_processing_perph_access_req))
			) & // FENCE.I或FENCE指令等到前序访存都已完成才能发射
			((~s_op_ftc_id_res_data[32+PRE_DCD_MSG_IS_CSR_RW_INST_SID]) | rob_csr_rw_inst_allowed) // 检查ROB是否允许发射CSR读写指令
		);
	
	always @(posedge aclk)
	begin
		if(s_op_ftc_id_res_valid & s_op_ftc_id_res_ready)
			luc_stage_data <= # SIM_DELAY {
				s_op_ftc_id_res_data, 
				s_op_ftc_id_res_msg, 
				s_op_ftc_id_res_dcd_res, 
				s_op_ftc_id_res_id, 
				s_op_ftc_id_res_is_first_inst_after_rst, 
				s_op_ftc_id_res_op1, 
				s_op_ftc_id_res_op2
			};
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			luc_stage_valid <= 1'b0;
		else if(
			(sys_reset_req | flush_req) | 
			((~luc_stage_valid) | m_luc_ready)
		)
			luc_stage_valid <= # SIM_DELAY 
				(~(sys_reset_req | flush_req)) & 
				s_op_ftc_id_res_valid & 
				rob_full_n & fence_csr_rw_allowed;
	end
	
endmodule
