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
本模块: 指令总线控制单元

描述:
指令总线访问请求到应答的最小时延为2clk
支持访问请求直接旁路到ICB主机的命令通道
支持清空指令缓存, 清空时可继续接受请求, 未完成命令阶段的请求不再向ICB主机发送命令, 正在等待ICB主机响应的请求所对应的响应将被丢弃
清空指令缓存信号是只需要持续1clk的脉冲信号
访问地址非对齐的请求不会发起ICB传输就直接给出应答
支持指令预译码

注意：
仅实现了指令总线读操作
指令ICB主机的响应时延应至少为1clk
若当前有正在镇压的ICB事务, 则不能清空指令缓存
必须保证指令缓存中不会出现事务ID相同的条目
当指令总线访问请求被接受后, 应在下1clk广播该请求的分支预测信息
对于异常的取指结果(错误码不是IBUS_ACCESS_NORMAL), 其应答的指令为NOP及其相应的预译码信息

协议:
ICB MASTER

作者: 陈家耀
日期: 2026/02/05
********************************************************************/


module panda_risc_v_ibus_ctrler #(
	parameter integer IBUS_ACCESS_TIMEOUT_TH = 16, // 指令总线访问超时周期数(0 -> 不设超时 | 正整数)
	parameter integer INST_ADDR_ALIGNMENT_WIDTH = 32, // 指令地址对齐位宽(16 | 32)
	parameter integer IBUS_TID_WIDTH = 8, // 指令总线事务ID位宽(1~16)
	parameter integer IBUS_OUTSTANDING_N = 4, // 指令总线滞外深度(1 | 2 | 4 | 8)
	parameter integer IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH = 2, // 指令总线访问请求附带信息的位宽(正整数)
	parameter integer PRDT_MSG_WIDTH = 96, // 分支预测信息的位宽(正整数)
    parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 指令缓存控制与状态
	input wire clr_inst_buf, // 清空指令缓存(指示)
	output wire suppressing_ibus_access, // 当前有正在镇压的ICB事务(状态标志)
	output wire clr_inst_buf_while_suppressing, // 在镇压ICB事务时清空指令缓存(错误标志)
	output wire ibus_timeout, // 指令总线访问超时(错误标志)
	
	// 分支预测信息广播
	input wire prdt_bdcst_vld, // 广播有效
	input wire[IBUS_TID_WIDTH-1:0] prdt_bdcst_tid, // 事务ID
	input wire[PRDT_MSG_WIDTH-1:0] prdt_bdcst_msg, // 分支预测信息
	
	// 指令总线访问请求
	input wire[31:0] ibus_access_req_addr, // 访问地址(PC)
	input wire[IBUS_TID_WIDTH-1:0] ibus_access_req_tid, // 事务ID
	input wire[IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH-1:0] ibus_access_req_extra_msg, // 附带信息
	input wire ibus_access_req_valid,
	output wire ibus_access_req_ready,
	// 指令总线访问应答
	output wire[31:0] ibus_access_resp_rdata, // 读数据(指令)
	output wire[1:0] ibus_access_resp_err, // 错误类型(2'b00 -> 正常, 2'b01 -> 指令地址非对齐, 
										   //          2'b10 -> 指令总线访问错误, 2'b11 -> 响应超时)
	output wire[31:0] ibus_access_resp_addr, // 访问地址(PC)
	output wire[IBUS_TID_WIDTH-1:0] ibus_access_resp_tid, // 事务ID
	output wire[IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH-1:0] ibus_access_resp_extra_msg, // 附带信息
	output wire[63:0] ibus_access_resp_pre_decoding_msg, // 预译码信息
	output wire[PRDT_MSG_WIDTH-1:0] ibus_access_resp_prdt, // 分支预测信息
	output wire ibus_access_resp_valid,
	input wire ibus_access_resp_ready,
    
    // 指令ICB主机
	// [命令通道]
	output wire[31:0] m_icb_cmd_addr,
	output wire m_icb_cmd_read, // const -> 1'b1
	output wire[31:0] m_icb_cmd_wdata, // const -> 32'h0000_0000
	output wire[3:0] m_icb_cmd_wmask, // const -> 4'b0000
	output wire m_icb_cmd_valid,
	input wire m_icb_cmd_ready,
	// [响应通道]
	input wire[31:0] m_icb_rsp_rdata,
	input wire m_icb_rsp_err,
	input wire m_icb_rsp_valid,
	output wire m_icb_rsp_ready
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
	// 指令存储器访问应答错误类型
	localparam IBUS_ACCESS_NORMAL = 2'b00; // 正常
	localparam IBUS_ACCESS_PC_UNALIGNED = 2'b01; // 指令地址非对齐
	localparam IBUS_ACCESS_BUS_ERR = 2'b10; // 指令总线访问错误
	localparam IBUS_ACCESS_TIMEOUT = 2'b11; // 响应超时
	// 指令总线访问状态常量
	localparam IBUS_ACCESS_STS_EMPTY = 2'b00; // 阶段: 空
	localparam IBUS_ACCESS_STS_ICB_CMD = 2'b01; // 阶段: 向ICB总线发送命令
	localparam IBUS_ACCESS_STS_ICB_RESP = 2'b10; // 阶段: 等待ICB总线的响应
	localparam IBUS_ACCESS_STS_ACK = 2'b11; // 阶段: 应答
	// 分支预测信息各字段的起始索引
	localparam integer PRDT_MSG_TARGET_ADDR_SID = 0; // 跳转地址
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
	// 空指令
	localparam NOP_INST = 32'h0000_0013;
	
	/** 指令总线访问地址非对齐与超时限制 **/
	wire ibus_access_addr_unaligned_flag; // 访问地址非对齐(标志)
	wire waiting_icb_resp; // 正在等待ICB主机响应(标志)
	reg[clogb2(IBUS_ACCESS_TIMEOUT_TH):0] ibus_timeout_cnt; // 超时计数器
	reg ibus_timeout_flag; // 超时标志
	
	assign ibus_timeout = ibus_timeout_flag;
	
	assign ibus_access_addr_unaligned_flag = 
		(INST_ADDR_ALIGNMENT_WIDTH == 32) ? (ibus_access_req_addr[1:0] != 2'b00):
		                                    ibus_access_req_addr[0];
	
	// 超时计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			ibus_timeout_cnt <= 0;
		else if((~ibus_timeout_flag) & (waiting_icb_resp | (m_icb_rsp_valid & m_icb_rsp_ready)))
			ibus_timeout_cnt <= # SIM_DELAY 
				(m_icb_rsp_valid & m_icb_rsp_ready) ? 0:
				                                      (ibus_timeout_cnt + 1);
	end
	
	// 超时标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			ibus_timeout_flag <= 1'b0;
		else if((~ibus_timeout_flag) & waiting_icb_resp & (~(m_icb_rsp_valid & m_icb_rsp_ready)))
			ibus_timeout_flag <= # SIM_DELAY (IBUS_ACCESS_TIMEOUT_TH != 0) & (ibus_timeout_cnt == (IBUS_ACCESS_TIMEOUT_TH-1));
	end
	
	/** 指令预译码 **/
	wire[63:0] pre_decoding_msg_packeted; // 打包的预译码信息
	wire[63:0] NOP_PRE_DCD_MSG_PKT; // 空指令的打包的预译码信息
	
	panda_risc_v_pre_decoder pre_decoder_u0(
		.inst(m_icb_rsp_rdata),
		
		.is_b_inst(),
		.is_jal_inst(),
		.is_jalr_inst(),
		.is_csr_rw_inst(),
		.is_load_inst(),
		.is_store_inst(),
		.is_mul_inst(),
		.is_div_inst(),
		.is_rem_inst(),
		.is_ecall_inst(),
		.is_mret_inst(),
		.is_fence_inst(),
		.is_fence_i_inst(),
		.is_ebreak_inst(),
		.is_dret_inst(),
		.jump_ofs_imm(),
		.rs1_vld(),
		.rs2_vld(),
		.rd_vld(),
		.csr_addr(),
		.rs1_id(),
		.illegal_inst(),
		
		.pre_decoding_msg_packeted(pre_decoding_msg_packeted)
	);
	
	panda_risc_v_pre_decoder pre_decoder_u1(
		.inst(NOP_INST),
		
		.is_b_inst(),
		.is_jal_inst(),
		.is_jalr_inst(),
		.is_csr_rw_inst(),
		.is_load_inst(),
		.is_store_inst(),
		.is_mul_inst(),
		.is_div_inst(),
		.is_rem_inst(),
		.is_ecall_inst(),
		.is_mret_inst(),
		.is_fence_inst(),
		.is_fence_i_inst(),
		.is_ebreak_inst(),
		.is_dret_inst(),
		.jump_ofs_imm(),
		.rs1_vld(),
		.rs2_vld(),
		.rd_vld(),
		.csr_addr(),
		.rs1_id(),
		.illegal_inst(),
		
		.pre_decoding_msg_packeted(NOP_PRE_DCD_MSG_PKT)
	);
    
	/** 指令总线访问缓存区 **/
	// [存储实体]
	reg[1:0] ibus_access_sts[0:IBUS_OUTSTANDING_N-1]; // 访问状态
	reg ibus_access_suppress_flag[0:IBUS_OUTSTANDING_N-1]; // 事务镇压标志
	reg[31:0] ibus_access_addr[0:IBUS_OUTSTANDING_N-1]; // 访问地址
	reg[IBUS_TID_WIDTH-1:0] ibus_access_tid[0:IBUS_OUTSTANDING_N-1]; // 事务ID
	reg[IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH-1:0] ibus_access_extra_msg[0:IBUS_OUTSTANDING_N-1]; // 附带信息
	reg[31:0] ibus_access_data[0:IBUS_OUTSTANDING_N-1]; // 读数据
	reg[63:0] ibus_access_pre_decoding_msg[0:IBUS_OUTSTANDING_N-1]; // 指令预译码信息
	reg[PRDT_MSG_WIDTH-1:0] ibus_access_prdt_msg[0:IBUS_OUTSTANDING_N-1]; // 分支预测信息
	reg[1:0] ibus_access_err[0:IBUS_OUTSTANDING_N-1]; // 错误码
	// [状态指针]
	reg[clogb2(IBUS_OUTSTANDING_N-1):0] ibus_access_req_wptr; // 访问请求写指针
	reg[clogb2(IBUS_OUTSTANDING_N-1):0] ibus_access_cmd_rptr; // 命令阶段读指针
	reg[clogb2(IBUS_OUTSTANDING_N-1):0] ibus_access_resp_wptr; // 响应阶段写指针
	reg[clogb2(IBUS_OUTSTANDING_N-1):0] ibus_access_ack_rptr; // 访问应答读指针
	// [标志向量]
	reg[IBUS_OUTSTANDING_N-1:0] ibus_access_buf_empty_vec; // 缓存条目空标志向量
	wire[IBUS_OUTSTANDING_N-1:0] ibus_access_buf_wait_resp_vec; // 缓存条目等待ICB响应标志向量
	// [清空指令缓存时镇压的ICB事务]
	reg[clogb2(IBUS_OUTSTANDING_N-1):0] ibus_access_req_wptr_backup; // 备份的访问请求写指针
	wire[IBUS_OUTSTANDING_N-1:0] ibus_access_resp_vec; // ICB响应向量
	wire[IBUS_OUTSTANDING_N-1:0] ibus_access_suppress_vec; // ICB事务镇压向量
	
	assign suppressing_ibus_access = |ibus_access_suppress_vec;
	assign clr_inst_buf_while_suppressing = clr_inst_buf & (|ibus_access_suppress_vec);
	
	assign ibus_access_req_ready = 
		(~ibus_timeout_flag) & 
		(|(ibus_access_buf_empty_vec & (1 << ibus_access_req_wptr))) & 
		// 地址非对齐的访问请求必须等到访问缓存区全空时才能被接受
		((~ibus_access_addr_unaligned_flag) | (&ibus_access_buf_empty_vec));
	
	assign waiting_icb_resp = ibus_access_sts[ibus_access_resp_wptr] == IBUS_ACCESS_STS_ICB_RESP;
	
	// 访问状态, 缓存条目空标志向量, 事务镇压标志, 访问地址, 事务ID, 附带信息, 读数据, 指令预译码信息, 分支预测信息, 错误码
	genvar ibus_access_entry_i;
	generate
		for(ibus_access_entry_i = 0;ibus_access_entry_i < IBUS_OUTSTANDING_N;ibus_access_entry_i = ibus_access_entry_i + 1)
		begin:ibus_access_entry_blk
			assign ibus_access_buf_wait_resp_vec[ibus_access_entry_i] = 
				(ibus_access_sts[ibus_access_entry_i] == IBUS_ACCESS_STS_ICB_RESP) & 
				(~ibus_access_resp_vec[ibus_access_entry_i]);
			assign ibus_access_resp_vec[ibus_access_entry_i] = 
				// 当前指令在ICB总线上得到响应, 或访问超时
				((m_icb_rsp_valid & m_icb_rsp_ready) | ibus_timeout_flag) & 
				(ibus_access_resp_wptr == ibus_access_entry_i);
			assign ibus_access_suppress_vec[ibus_access_entry_i] = ibus_access_suppress_flag[ibus_access_entry_i];
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
				begin
					ibus_access_sts[ibus_access_entry_i] <= IBUS_ACCESS_STS_EMPTY;
					ibus_access_buf_empty_vec[ibus_access_entry_i] <= 1'b1;
				end
				else if(
					(
						(ibus_access_sts[ibus_access_entry_i] == IBUS_ACCESS_STS_EMPTY) & 
						ibus_access_req_valid & ibus_access_req_ready & 
						(ibus_access_req_wptr == ibus_access_entry_i)
					) | (
						(ibus_access_sts[ibus_access_entry_i] == IBUS_ACCESS_STS_ICB_CMD) & (
							// 断言: "清空指令缓存"和"命令阶段导致的ICB命令通道握手"不可能同时进行!
							clr_inst_buf | (
								m_icb_cmd_valid & m_icb_cmd_ready & 
								(ibus_access_cmd_rptr == ibus_access_entry_i)
							)
						)
					) | (
						(ibus_access_sts[ibus_access_entry_i] == IBUS_ACCESS_STS_ICB_RESP) & 
						ibus_access_resp_vec[ibus_access_entry_i]
					) | (
						(ibus_access_sts[ibus_access_entry_i] == IBUS_ACCESS_STS_ACK) & (
							// 断言: "清空指令缓存"和"指令总线访问应答握手"不可能同时进行!
							clr_inst_buf | (
								ibus_access_resp_valid & ibus_access_resp_ready & 
								(ibus_access_ack_rptr == ibus_access_entry_i)
							)
						)
					)
				)
				begin
					case(ibus_access_sts[ibus_access_entry_i])
						IBUS_ACCESS_STS_EMPTY:
						begin
							/*
							对于地址非对齐的事务, 直接跳到应答阶段
							对于命令阶段立即完成的事务, 直接跳到等待响应阶段
							*/
							ibus_access_sts[ibus_access_entry_i] <= # SIM_DELAY 
								ibus_access_addr_unaligned_flag ? 
									IBUS_ACCESS_STS_ACK:(
										((ibus_access_cmd_rptr == ibus_access_entry_i) & m_icb_cmd_ready) ? 
											IBUS_ACCESS_STS_ICB_RESP:
											IBUS_ACCESS_STS_ICB_CMD
									);
							
							ibus_access_buf_empty_vec[ibus_access_entry_i] <= # SIM_DELAY 1'b0;
						end
						IBUS_ACCESS_STS_ICB_CMD:
						begin
							ibus_access_sts[ibus_access_entry_i] <= # SIM_DELAY 
								// 清空指令缓存时, 若当前事务的命令阶段尚未完成, 则不再发送命令
								clr_inst_buf ? 
									IBUS_ACCESS_STS_EMPTY:
									IBUS_ACCESS_STS_ICB_RESP;
							
							ibus_access_buf_empty_vec[ibus_access_entry_i] <= # SIM_DELAY clr_inst_buf;
						end
						IBUS_ACCESS_STS_ICB_RESP:
						begin
							ibus_access_sts[ibus_access_entry_i] <= # SIM_DELAY 
								// 被镇压的事务不再进入应答阶段
								(clr_inst_buf | ibus_access_suppress_flag[ibus_access_entry_i]) ? 
									IBUS_ACCESS_STS_EMPTY:
									IBUS_ACCESS_STS_ACK;
							
							ibus_access_buf_empty_vec[ibus_access_entry_i] <= # SIM_DELAY 
								clr_inst_buf | ibus_access_suppress_flag[ibus_access_entry_i];
						end
						IBUS_ACCESS_STS_ACK:
						begin
							ibus_access_sts[ibus_access_entry_i] <= # SIM_DELAY IBUS_ACCESS_STS_EMPTY;
							ibus_access_buf_empty_vec[ibus_access_entry_i] <= # SIM_DELAY 1'b1;
						end
						default:
						begin
							ibus_access_sts[ibus_access_entry_i] <= # SIM_DELAY IBUS_ACCESS_STS_EMPTY;
							ibus_access_buf_empty_vec[ibus_access_entry_i] <= # SIM_DELAY 1'b1;
						end
					endcase
				end
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					ibus_access_suppress_flag[ibus_access_entry_i] <= 1'b0;
				else if(
					(ibus_access_sts[ibus_access_entry_i] == IBUS_ACCESS_STS_ICB_RESP) & 
					(clr_inst_buf | ibus_access_resp_vec[ibus_access_entry_i])
				)
					/*
					清空指令缓存 | 当前指令在ICB总线上得到响应 | 下一镇压标志
					----------------------------------------------------------
					     0       |             0               |     hold
						 0       |             1               |       0
						 1       |             0               |       1
						 1       |             1               |       0
					*/
					ibus_access_suppress_flag[ibus_access_entry_i] <= # SIM_DELAY 
						clr_inst_buf & (~ibus_access_resp_vec[ibus_access_entry_i]);
			end
			
			always @(posedge aclk)
			begin
				if(
					// 在指令总线访问请求被接受时锁存"访问地址"、"事务ID"和"附带信息"
					(ibus_access_sts[ibus_access_entry_i] == IBUS_ACCESS_STS_EMPTY) & 
					ibus_access_req_valid & ibus_access_req_ready & 
					(ibus_access_req_wptr == ibus_access_entry_i)
				)
				begin
					ibus_access_addr[ibus_access_entry_i] <= # SIM_DELAY ibus_access_req_addr;
					ibus_access_tid[ibus_access_entry_i] <= # SIM_DELAY ibus_access_req_tid;
					ibus_access_extra_msg[ibus_access_entry_i] <= # SIM_DELAY ibus_access_req_extra_msg;
				end
			end
			
			always @(posedge aclk)
			begin
				if(
					// 地址非对齐, 锁存"空指令"
					(
						(ibus_access_sts[ibus_access_entry_i] == IBUS_ACCESS_STS_EMPTY) & 
						ibus_access_req_valid & ibus_access_req_ready & 
						(ibus_access_req_wptr == ibus_access_entry_i) & 
						ibus_access_addr_unaligned_flag
					) | 
					// 总线错误或总线超时, 锁存"空指令"; 总线正常, 锁存"取到的指令"
					(
						(ibus_access_sts[ibus_access_entry_i] == IBUS_ACCESS_STS_ICB_RESP) & 
						ibus_access_resp_vec[ibus_access_entry_i]
					)
				)
				begin
					if(
						(ibus_access_sts[ibus_access_entry_i] != IBUS_ACCESS_STS_ICB_RESP) | 
						(ibus_timeout_flag | m_icb_rsp_err)
					)
					begin
						ibus_access_data[ibus_access_entry_i] <= # SIM_DELAY NOP_INST;
						ibus_access_pre_decoding_msg[ibus_access_entry_i] <= # SIM_DELAY NOP_PRE_DCD_MSG_PKT;
					end
					else
					begin
						ibus_access_data[ibus_access_entry_i] <= # SIM_DELAY m_icb_rsp_rdata;
						ibus_access_pre_decoding_msg[ibus_access_entry_i] <= # SIM_DELAY pre_decoding_msg_packeted;
					end
				end
			end
			
			always @(posedge aclk)
			begin
				if(
					// 监听分支预测信息广播
					prdt_bdcst_vld & (
						(ibus_access_sts[ibus_access_entry_i] == IBUS_ACCESS_STS_ICB_CMD) | 
						(ibus_access_sts[ibus_access_entry_i] == IBUS_ACCESS_STS_ICB_RESP)
					) & 
					(prdt_bdcst_tid == ibus_access_tid[ibus_access_entry_i])
				)
					ibus_access_prdt_msg[ibus_access_entry_i] <= # SIM_DELAY prdt_bdcst_msg;
			end
			
			always @(posedge aclk)
			begin
				if(
					// 事务错误码: 地址非对齐
					(
						(ibus_access_sts[ibus_access_entry_i] == IBUS_ACCESS_STS_EMPTY) & 
						ibus_access_req_valid & ibus_access_req_ready & 
						(ibus_access_req_wptr == ibus_access_entry_i) & 
						ibus_access_addr_unaligned_flag
					) | 
					// 事务错误码: 总线错误 | 总线超时 | 正常
					(
						(ibus_access_sts[ibus_access_entry_i] == IBUS_ACCESS_STS_ICB_RESP) & 
						ibus_access_resp_vec[ibus_access_entry_i]
					)
				)
					ibus_access_err[ibus_access_entry_i] <= # SIM_DELAY 
						(ibus_access_sts[ibus_access_entry_i] == IBUS_ACCESS_STS_EMPTY) ? 
							IBUS_ACCESS_PC_UNALIGNED:(
								ibus_timeout_flag ? 
									IBUS_ACCESS_TIMEOUT:(
										m_icb_rsp_err ? 
											IBUS_ACCESS_BUS_ERR:
											IBUS_ACCESS_NORMAL
									)
							);
			end
		end
	endgenerate
	
	// 访问请求写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			ibus_access_req_wptr <= 0;
		else if(ibus_access_req_valid & ibus_access_req_ready)
			ibus_access_req_wptr <= # SIM_DELAY ibus_access_req_wptr + 1;
	end
	
	// 命令阶段读指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			ibus_access_cmd_rptr <= 0;
		else if(
			clr_inst_buf | 
			(m_icb_cmd_valid & m_icb_cmd_ready) | 
			(ibus_access_req_valid & ibus_access_req_ready & ibus_access_addr_unaligned_flag)
		)
			ibus_access_cmd_rptr <= # SIM_DELAY 
				// 清空指令缓存时, 跳到访问请求写指针
				(clr_inst_buf ? ibus_access_req_wptr:ibus_access_cmd_rptr) + 
				/*
				不清空指令缓存时, 固定+1
				清空指令缓存时, 若当前指令总线访问请求被接受并且其命令阶段立即完成, 才需要+1
				*/
				(
					(
						(~clr_inst_buf) | 
						(m_icb_cmd_valid & m_icb_cmd_ready) | 
						(ibus_access_req_valid & ibus_access_req_ready & ibus_access_addr_unaligned_flag)
					) ? 1:0
				);
	end
	
	// 响应阶段写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			ibus_access_resp_wptr <= 0;
		else if(
			(clr_inst_buf & (~(|ibus_access_buf_wait_resp_vec))) | 
			((m_icb_rsp_valid & m_icb_rsp_ready) | ibus_timeout_flag) | 
			(ibus_access_req_valid & ibus_access_req_ready & ibus_access_addr_unaligned_flag)
		)
			ibus_access_resp_wptr <= # SIM_DELAY 
				(clr_inst_buf & (~(|ibus_access_buf_wait_resp_vec))) ? 
					// 清空指令缓存且没有等待响应的事务时, 直接跳到访问请求写指针
					(
						ibus_access_req_wptr + 
						// 若当前指令总线访问请求被接受并且其命令阶段立即完成, 需要+1
						((ibus_access_req_valid & ibus_access_req_ready & ibus_access_addr_unaligned_flag) ? 1:0)
					):(
						// ICB总线响应通道握手(或总线超时), 且当前镇压最后1个事务, 则跳到备份的访问请求写指针
						(
							((m_icb_rsp_valid & m_icb_rsp_ready) | ibus_timeout_flag) & 
							(ibus_access_suppress_vec == ibus_access_resp_vec)
						) ? 
							ibus_access_req_wptr_backup:
							(ibus_access_resp_wptr + 1)
					);
	end
	
	// 访问应答读指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			ibus_access_ack_rptr <= 0;
		else if(
			clr_inst_buf | 
			(ibus_access_resp_valid & ibus_access_resp_ready)
		)
			ibus_access_ack_rptr <= # SIM_DELAY 
				clr_inst_buf ? 
					// 清空指令缓存时, 跳到访问请求写指针
					ibus_access_req_wptr:
					(ibus_access_ack_rptr + 1);
	end
	
	// 备份的访问请求写指针
	always @(posedge aclk)
	begin
		if(clr_inst_buf)
			ibus_access_req_wptr_backup <= # SIM_DELAY ibus_access_req_wptr;
	end
	
	/** 指令总线访问应答 **/
	assign ibus_access_resp_rdata = ibus_access_data[ibus_access_ack_rptr];
	assign ibus_access_resp_err = ibus_access_err[ibus_access_ack_rptr];
	assign ibus_access_resp_addr = ibus_access_addr[ibus_access_ack_rptr];
	assign ibus_access_resp_tid = ibus_access_tid[ibus_access_ack_rptr];
	assign ibus_access_resp_extra_msg = ibus_access_extra_msg[ibus_access_ack_rptr];
	assign ibus_access_resp_pre_decoding_msg = ibus_access_pre_decoding_msg[ibus_access_ack_rptr];
	assign ibus_access_resp_prdt = ibus_access_prdt_msg[ibus_access_ack_rptr];
	assign ibus_access_resp_valid = (ibus_access_sts[ibus_access_ack_rptr] == IBUS_ACCESS_STS_ACK) & (~clr_inst_buf);
	
	/** 指令ICB主机命令通道 **/
	assign m_icb_cmd_addr = 
		(ibus_access_sts[ibus_access_cmd_rptr] == IBUS_ACCESS_STS_EMPTY) ? 
			ibus_access_req_addr:
			ibus_access_addr[ibus_access_cmd_rptr];
	assign m_icb_cmd_read = 1'b1;
	assign m_icb_cmd_wdata = 32'h0000_0000;
	assign m_icb_cmd_wmask = 4'b0000;
	assign m_icb_cmd_valid = 
		// 当前选中的事务是空的, 则将指令总线访问请求直接旁路出去
		(
			(ibus_access_sts[ibus_access_cmd_rptr] == IBUS_ACCESS_STS_EMPTY) & 
			ibus_access_req_valid & 
			(~ibus_access_addr_unaligned_flag) & (~ibus_timeout_flag)
		) | 
		// 当前选中的事务处于命令阶段
		(
			(ibus_access_sts[ibus_access_cmd_rptr] == IBUS_ACCESS_STS_ICB_CMD) & 
			(~clr_inst_buf)
		);
	
	/** 指令ICB主机响应通道 **/
	assign m_icb_rsp_ready = ibus_access_sts[ibus_access_resp_wptr] == IBUS_ACCESS_STS_ICB_RESP;
	
endmodule
