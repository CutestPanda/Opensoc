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
从通用寄存器堆、ROB、旁路网络预取操作数
传递"用于取操作数的执行单元ID"和"用于取操作数的指令ID"给后级
生成本指令的执行单元ID

注意：
当待预取操作数与段寄存器上的指令存在RAW相关性时, 必然预取失败, 需要后级继续从旁路网络取操作数

协议:
无

作者: 陈家耀
日期: 2026/01/24
********************************************************************/


module panda_risc_v_regs_rd #(
	parameter integer IBUS_TID_WIDTH = 8, // 指令总线事务ID位宽(1~16)
	parameter integer LSN_FU_N = 5, // 要监听结果的执行单元的个数(正整数)
	parameter integer FU_ID_WIDTH = 8, // 执行单元ID位宽(1~16)
	parameter integer FU_RES_WIDTH = 32, // 执行单元结果位宽(正整数)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 复位/冲刷
	input wire sys_reset_req, // 系统复位请求
	input wire flush_req, // 冲刷请求
	
	// 读ARF/ROB输入
	input wire[127:0] s_regs_rd_data, // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	input wire[98:0] s_regs_rd_msg, // 取指附加信息({分支预测信息(96bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	input wire[IBUS_TID_WIDTH-1:0] s_regs_rd_id, // 指令编号
	input wire s_regs_rd_is_first_inst_after_rst, // 是否复位释放后的第1条指令
	input wire s_regs_rd_valid,
	output wire s_regs_rd_ready,
	
	// 读ARF/ROB输出
	output wire[127:0] m_regs_rd_data, // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	output wire[98:0] m_regs_rd_msg, // 取指附加信息({分支预测信息(96bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	output wire[IBUS_TID_WIDTH-1:0] m_regs_rd_id, // 指令编号
	output wire m_regs_rd_is_first_inst_after_rst, // 是否复位释放后的第1条指令
	output wire[129:0] m_regs_rd_op, // 预取的操作数({操作数1已取得(1bit), 操作数2已取得(1bit), 
	                                 //   操作数1(32bit), 操作数2(32bit), 用于取操作数1的执行单元ID(16bit), 用于取操作数2的执行单元ID(16bit), 
									 //   用于取操作数1的指令ID(16bit), 用于取操作数2的指令ID(16bit)})
	output wire[FU_ID_WIDTH-1:0] m_regs_rd_fuid, // 执行单元ID
	output wire m_regs_rd_valid,
	input wire m_regs_rd_ready,
	
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
	// 负载数据的位宽
	localparam integer PAYLOAD_WIDTH = 128 + 99 + IBUS_TID_WIDTH + 1 + 130;
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
	// 各个执行单元的ID
	localparam integer FU_ALU_ID = 0; // ALU
	localparam integer FU_CSR_ID = 1; // CSR
	localparam integer FU_LSU_ID = 2; // LSU
	localparam integer FU_MUL_ID = 3; // 乘法器
	localparam integer FU_DIV_ID = 4; // 除法器
	
	/** 执行单元结果返回(数组) **/
	wire fu_res_vld_arr[0:LSN_FU_N-1]; // 有效标志
	wire[IBUS_TID_WIDTH-1:0] fu_res_tid_arr[0:LSN_FU_N-1]; // 指令ID
	wire[FU_RES_WIDTH-1:0] fu_res_data_arr[0:LSN_FU_N-1]; // 执行结果
	wire[LSN_FU_N-1:0] fu_res_tid_match_op1_vec; // 指令ID匹配操作数1所绑定指令的ID(标志向量)
	wire[LSN_FU_N-1:0] fu_res_tid_match_op2_vec; // 指令ID匹配操作数2所绑定指令的ID(标志向量)
	
	genvar fu_i;
	generate
		for(fu_i = 0;fu_i < LSN_FU_N;fu_i = fu_i + 1)
		begin:fu_res_lsn_blk
			assign fu_res_vld_arr[fu_i] = 
				fu_res_vld[fu_i];
			assign fu_res_tid_arr[fu_i] = 
				fu_res_tid[(fu_i+1)*IBUS_TID_WIDTH-1:fu_i*IBUS_TID_WIDTH];
			assign fu_res_data_arr[fu_i] = 
				fu_res_data[(fu_i+1)*FU_RES_WIDTH-1:fu_i*FU_RES_WIDTH];
			
			assign fu_res_tid_match_op1_vec[fu_i] = 
				(op1_ftc_fuid == fu_i) & fu_res_vld_arr[fu_i] & (fu_res_tid_arr[fu_i] == op1_ftc_tid);
			assign fu_res_tid_match_op2_vec[fu_i] = 
				(op2_ftc_fuid == fu_i) & fu_res_vld_arr[fu_i] & (fu_res_tid_arr[fu_i] == op2_ftc_tid);
		end
	endgenerate
	
	/** 数据相关性检查 **/
	assign op1_ftc_rs1_id = s_regs_rd_data[19:15];
	assign op2_ftc_rs2_id = s_regs_rd_data[24:20];
	
	/** 读通用寄存器堆 **/
	assign reg_file_raddr_p0 = s_regs_rd_data[19:15];
	assign reg_file_raddr_p1 = s_regs_rd_data[24:20];
	
	/** 预取操作数 **/
	wire[31:0] op1_prefetched; // 预取的操作数1
	wire[31:0] op2_prefetched; // 预取的操作数2
	wire op1_pftc_success; // 操作数1预取成功(标志)
	wire op2_pftc_success; // 操作数2预取成功(标志)
	wire op1_stage_regs_raw_dpc; // 操作数1与段寄存器上的指令存在RAW相关性(标志)
	wire op2_stage_regs_raw_dpc; // 操作数2与段寄存器上的指令存在RAW相关性(标志)
	
	assign op1_prefetched = 
		({32{op1_ftc_from_reg_file}} & reg_file_dout_p0) | // 从寄存器堆取操作数
		({32{op1_ftc_from_rob}} & op1_ftc_rob_saved_data[31:0]) | // 从ROB取操作数
		({32{op1_ftc_from_byp}} & fu_res_data_arr[op1_ftc_fuid][31:0]); // 从FU取操作数
	assign op2_prefetched = 
		({32{op2_ftc_from_reg_file}} & reg_file_dout_p1) | // 从寄存器堆取操作数
		({32{op2_ftc_from_rob}} & op2_ftc_rob_saved_data[31:0]) | // 从ROB取操作数
		({32{op2_ftc_from_byp}} & fu_res_data_arr[op2_ftc_fuid][31:0]); // 从FU取操作数
	
	assign op1_pftc_success = 
		(~op1_stage_regs_raw_dpc) & // 与段寄存器上的指令不存在RAW相关性
		(
			op1_ftc_from_reg_file | 
			op1_ftc_from_rob | 
			(|fu_res_tid_match_op1_vec)
		);
	assign op2_pftc_success = 
		(~op2_stage_regs_raw_dpc) & // 与段寄存器上的指令不存在RAW相关性
		(
			op2_ftc_from_reg_file | 
			op2_ftc_from_rob | 
			(|fu_res_tid_match_op2_vec)
		);
	
	/** 段寄存器 **/
	reg[PAYLOAD_WIDTH-1:0] stage_regs_payload; // 段寄存器负载数据
	reg[4:0] stage_regs_rd_id; // 段寄存器上指令的rd编号
	reg[FU_ID_WIDTH-1:0] stage_regs_fuid; // 段寄存器上指令的执行单元ID
	wire[15:0] op1_fuid; // 用于取操作数1的执行单元ID
	wire[15:0] op2_fuid; // 用于取操作数2的执行单元ID
	wire[15:0] op1_tid; // 用于取操作数1的指令ID
	wire[15:0] op2_tid; // 用于取操作数2的指令ID
	reg stage_regs_valid; // 段寄存器有效标志
	
	assign s_regs_rd_ready = (~(sys_reset_req | flush_req)) & ((~stage_regs_valid) | m_regs_rd_ready);
	
	assign {
		m_regs_rd_data, 
		m_regs_rd_msg, 
		m_regs_rd_id, 
		m_regs_rd_is_first_inst_after_rst, 
		m_regs_rd_op
	} = stage_regs_payload;
	assign m_regs_rd_fuid = stage_regs_fuid;
	assign m_regs_rd_valid = stage_regs_valid;
	
	assign op1_stage_regs_raw_dpc = 
		stage_regs_valid & (stage_regs_rd_id != 5'b00000) & (s_regs_rd_data[19:15] == stage_regs_rd_id);
	assign op2_stage_regs_raw_dpc = 
		stage_regs_valid & (stage_regs_rd_id != 5'b00000) & (s_regs_rd_data[24:20] == stage_regs_rd_id);
	
	assign op1_fuid = 
		(
			op1_stage_regs_raw_dpc ? 
				stage_regs_fuid: // 与段寄存器上的指令存在RAW相关性, 那么操作数1就要从段寄存器上的指令的执行结果获取
				op1_ftc_fuid
		) | 16'h0000;
	assign op2_fuid = 
		(
			op2_stage_regs_raw_dpc ? 
				stage_regs_fuid: // 与段寄存器上的指令存在RAW相关性, 那么操作数2就要从段寄存器上的指令的执行结果获取
				op2_ftc_fuid
		) | 16'h0000;
	
	assign op1_tid = 
		(
			op1_stage_regs_raw_dpc ? 
				m_regs_rd_id: // 与段寄存器上的指令存在RAW相关性, 那么操作数1就要从段寄存器上的指令的执行结果获取
				op1_ftc_tid
		) | 16'h0000;
	assign op2_tid = 
		(
			op2_stage_regs_raw_dpc ? 
				m_regs_rd_id: // 与段寄存器上的指令存在RAW相关性, 那么操作数2就要从段寄存器上的指令的执行结果获取
				op2_ftc_tid
		) | 16'h0000;
	
	// 段寄存器负载数据
	always @(posedge aclk)
	begin
		if(s_regs_rd_valid & s_regs_rd_ready)
			stage_regs_payload <= # SIM_DELAY {
				s_regs_rd_data, 
				s_regs_rd_msg, 
				s_regs_rd_id, 
				s_regs_rd_is_first_inst_after_rst, 
				{
					op1_pftc_success, op2_pftc_success, 
					op1_prefetched, op2_prefetched, op1_fuid, op2_fuid, 
					op1_tid, op2_tid
				}
			};
	end
	
	// 段寄存器上指令的rd编号
	always @(posedge aclk)
	begin
		if(s_regs_rd_valid & s_regs_rd_ready)
			stage_regs_rd_id <= # SIM_DELAY 
				s_regs_rd_data[PRE_DCD_MSG_RD_VLD_SID+32] ? 
					s_regs_rd_data[11:7]:
					5'b00000;
	end
	
	// 段寄存器上指令的执行单元ID
	always @(posedge aclk)
	begin
		if(s_regs_rd_valid & s_regs_rd_ready)
			stage_regs_fuid <= # SIM_DELAY 
				({FU_ID_WIDTH{
					s_regs_rd_data[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID+32] | 
					(~(
						s_regs_rd_data[PRE_DCD_MSG_IS_CSR_RW_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_LOAD_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_STORE_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_MUL_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_DIV_INST_SID+32] | 
						s_regs_rd_data[PRE_DCD_MSG_IS_REM_INST_SID+32]
					))
				}} & FU_ALU_ID) | // 从ALU取到结果
				({FU_ID_WIDTH{
					(~s_regs_rd_data[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID+32]) & 
					s_regs_rd_data[PRE_DCD_MSG_IS_CSR_RW_INST_SID+32]
				}} & FU_CSR_ID) | // 从CSR取到结果
				({FU_ID_WIDTH{
					(~s_regs_rd_data[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID+32]) & 
					(s_regs_rd_data[PRE_DCD_MSG_IS_LOAD_INST_SID+32] | s_regs_rd_data[PRE_DCD_MSG_IS_STORE_INST_SID+32])
				}} & FU_LSU_ID) | // 从LSU取到结果
				({FU_ID_WIDTH{
					(~s_regs_rd_data[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID+32]) & 
					s_regs_rd_data[PRE_DCD_MSG_IS_MUL_INST_SID+32]
				}} & FU_MUL_ID) | // 从乘法器取到结果
				({FU_ID_WIDTH{
					(~s_regs_rd_data[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID+32]) & 
					(s_regs_rd_data[PRE_DCD_MSG_IS_DIV_INST_SID+32] | s_regs_rd_data[PRE_DCD_MSG_IS_REM_INST_SID+32])
				}} & FU_DIV_ID); // 从除法器取到结果
	end
	
	// 段寄存器有效标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			stage_regs_valid <= 1'b0;
		else if((sys_reset_req | flush_req) | ((~stage_regs_valid) | m_regs_rd_ready))
			stage_regs_valid <= # SIM_DELAY (~(sys_reset_req | flush_req)) & s_regs_rd_valid;
	end
	
endmodule
