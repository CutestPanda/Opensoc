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
本模块: 取指单元

描述:
分支预测/预取指令 -> 指令总线控制单元 -> 取指应答/取指结果
监听发射阶段的分支信息广播, 用于处理BTB命中的RAS出栈标志无效的JALR指令, 得到其真实BTA
在得到取指应答的第1clk更新/置换BTB

注意：
复位请求比冲刷请求的优先级更高, 如果有正在处理的冲刷请求, 并且这时出现了1个复位请求, 
    那么冲刷请求不会再被处理, 冲刷应答也不会给出
取指结果总线是直接接的指令总线控制单元里的事务存储实体, 并没有实际的段寄存器

协议:
MEM MASTER
ICB MASTER
REQ/GRANT
REQ/ACK

作者: 陈家耀
日期: 2026/02/05
********************************************************************/


module panda_risc_v_ifu #(
	// 取指缓存配置
	parameter EN_IF_REGS = "true", // 是否启用取指缓存
	// 指令总线控制单元配置
	parameter integer IBUS_ACCESS_TIMEOUT_TH = 16, // 指令总线访问超时周期数(0 -> 不设超时 | 正整数)
	parameter integer INST_ADDR_ALIGNMENT_WIDTH = 32, // 指令地址对齐位宽(16 | 32)
	parameter integer IBUS_TID_WIDTH = 8, // 指令总线事务ID位宽(1~16)
	parameter integer IBUS_OUTSTANDING_N = 4, // 指令总线滞外深度(1 | 2 | 4 | 8)
	parameter integer IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH = 1, // 指令总线访问请求附带信息的位宽(正整数)
	parameter integer PRDT_MSG_WIDTH = 96, // 分支预测信息的位宽(正整数)
	// 基于历史的分支预测配置
	parameter integer GHR_WIDTH = 8, // 全局分支历史寄存器的位宽(<=16)
	parameter integer PC_WIDTH = 4, // 截取的低位PC的位宽(必须在范围[1, 16]内)
	parameter integer BHR_WIDTH = 9, // 局部分支历史寄存器(BHR)的位宽
	parameter integer BHT_DEPTH = 256, // 局部分支历史表(BHT)的深度(必须>=2且为2^n)
	parameter PHT_MEM_IMPL = "reg", // PHT存储器的实现方式(reg | sram)
	parameter NO_INIT_PHT = "false", // 是否无需初始化PHT存储器
	// BTB配置
	parameter integer BTB_WAY_N = 2, // BTB路数(1 | 2 | 4)
	parameter integer BTB_ENTRY_N = 512, // BTB项数(<=65536)
	parameter integer PC_TAG_WIDTH = 21, // PC标签的位宽(不要修改)
	parameter integer BTB_MEM_WIDTH = PC_TAG_WIDTH + 32 + 3 + 1 + 1 + 2, // BTB存储器的数据位宽(不要修改)
	parameter NO_INIT_BTB = "false", // 是否无需初始化BTB存储器
	// RAS配置
	parameter integer RAS_ENTRY_N = 4, // 返回地址堆栈的条目数(2 | 4 | 8 | 16)
	// 仿真配置
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 复位/冲刷
	input wire sys_reset_req, // 系统复位请求
	input wire[31:0] rst_pc, // 复位时的PC
	input wire flush_req, // 冲刷请求
	input wire ifu_exclusive_flush_req, // IFU专用冲刷请求
	input wire[31:0] flush_addr, // 冲刷地址
	output wire rst_ack, // 复位应答
	output wire flush_ack, // 冲刷应答
	
	// IFU给出的冲刷请求
	output wire ifu_flush_req, // 冲刷请求
	output wire[31:0] ifu_flush_addr, // 冲刷地址
	input wire ifu_flush_grant, // 冲刷许可
	
	// 发射阶段分支信息广播
	input wire brc_bdcst_luc_vld, // 广播有效
	input wire[IBUS_TID_WIDTH-1:0] brc_bdcst_luc_tid, // 事务ID
	input wire brc_bdcst_luc_is_b_inst, // 是否B指令
	input wire brc_bdcst_luc_is_jal_inst, // 是否JAL指令
	input wire brc_bdcst_luc_is_jalr_inst, // 是否JALR指令
	input wire[31:0] brc_bdcst_luc_bta, // 分支目标地址
	
	// 基于历史的分支预测
	// [更新退休GHR]
	input wire glb_brc_prdt_on_clr_retired_ghr, // 清零退休GHR
	input wire glb_brc_prdt_on_upd_retired_ghr, // 退休GHR更新指示
	input wire glb_brc_prdt_retired_ghr_shift_in, // 退休GHR移位输入
	// [更新推测GHR]
	input wire glb_brc_prdt_rstr_speculative_ghr, // 恢复推测GHR指示
	// [更新PHT]
	input wire glb_brc_prdt_upd_i_req, // 更新请求
	input wire[31:0] glb_brc_prdt_upd_i_pc, // 待更新项的PC
	input wire[((GHR_WIDTH <= 2) ? 2:GHR_WIDTH)-1:0] glb_brc_prdt_upd_i_ghr, // 待更新项的GHR
	input wire[15:0] glb_brc_prdt_upd_i_bhr, // 待更新项的BHR
	// 说明: PHT_MEM_IMPL == "sram"时可用
	input wire[1:0] glb_brc_prdt_upd_i_2bit_sat_cnt, // 新的2bit饱和计数器
	input wire glb_brc_prdt_upd_i_brc_taken, // 待更新项的实际分支跳转方向
	// [GHR值]
	output wire[((GHR_WIDTH <= 2) ? 2:GHR_WIDTH)-1:0] glb_brc_prdt_retired_ghr_o, // 当前的退休GHR
	// [PHT存储器]
	// 说明: PHT_MEM_IMPL == "sram"时可用
	// [端口A]
	output wire pht_mem_clka,
	output wire pht_mem_ena,
	output wire pht_mem_wea,
	output wire[15:0] pht_mem_addra,
	output wire[1:0] pht_mem_dina,
	input wire[1:0] pht_mem_douta,
	// [端口B]
	output wire pht_mem_clkb,
	output wire pht_mem_enb,
	output wire pht_mem_web,
	output wire[15:0] pht_mem_addrb,
	output wire[1:0] pht_mem_dinb,
	input wire[1:0] pht_mem_doutb,
	
	// BTB存储器
	// [端口A]
	output wire[BTB_WAY_N-1:0] btb_mem_clka,
	output wire[BTB_WAY_N-1:0] btb_mem_ena,
	output wire[BTB_WAY_N-1:0] btb_mem_wea,
	output wire[BTB_WAY_N*16-1:0] btb_mem_addra,
	output wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_dina,
	input wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_douta,
	// [端口B]
	output wire[BTB_WAY_N-1:0] btb_mem_clkb,
	output wire[BTB_WAY_N-1:0] btb_mem_enb,
	output wire[BTB_WAY_N-1:0] btb_mem_web,
	output wire[BTB_WAY_N*16-1:0] btb_mem_addrb,
	output wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_dinb,
	input wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_doutb,
	
	// 取指结果
	output wire[127:0] m_if_res_data, // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	output wire[98:0] m_if_res_msg, // 取指附加信息({分支预测信息(96bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	output wire[IBUS_TID_WIDTH-1:0] m_if_res_id, // 指令编号
	output wire m_if_res_is_first_inst_after_rst, // 是否复位释放后的第1条指令
	output wire m_if_res_valid,
	input wire m_if_res_ready,
	
	// 指令ICB主机
	// [命令通道]
	output wire[31:0] m_icb_cmd_inst_addr,
	output wire m_icb_cmd_inst_read, // const -> 1'b1
	output wire[31:0] m_icb_cmd_inst_wdata, // const -> 32'h0000_0000
	output wire[3:0] m_icb_cmd_inst_wmask, // const -> 4'b0000
	output wire m_icb_cmd_inst_valid,
	input wire m_icb_cmd_inst_ready,
	// [响应通道]
	input wire[31:0] m_icb_rsp_inst_rdata,
	input wire m_icb_rsp_inst_err,
	input wire m_icb_rsp_inst_valid,
	output wire m_icb_rsp_inst_ready,
	
	// 指令总线控制单元状态
	output wire suppressing_ibus_access, // 当前有正在镇压的ICB事务(状态标志)
	output wire clr_inst_buf_while_suppressing, // 在镇压ICB事务时清空指令缓存(错误标志)
	output wire ibus_timeout // 指令总线访问超时(错误标志)
);
	
	/** 常量 **/
	// 分支指令类型常量
	localparam BRANCH_TYPE_JAL = 3'b000; // JAL指令
	localparam BRANCH_TYPE_JALR = 3'b001; // JALR指令
	localparam BRANCH_TYPE_B = 3'b010; // B指令
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
	// 指令总线访问请求附带信息各字段的起始索引
	localparam integer IBUS_ACCESS_REQ_EXTRA_MSG_IS_FIRST_INST_SID = 0; // 是否复位释放后的第1条指令
	// 指令存储器访问应答错误类型
	localparam IBUS_ACCESS_NORMAL = 2'b00; // 正常
	localparam IBUS_ACCESS_PC_UNALIGNED = 2'b01; // 指令地址非对齐
	localparam IBUS_ACCESS_BUS_ERR = 2'b10; // 指令总线访问错误
	localparam IBUS_ACCESS_TIMEOUT = 2'b11; // 响应超时
	
	/** 取指缓存 **/
	// 取指缓存输入
	wire[127:0] s_if_regs_data; // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	wire[98:0] s_if_regs_msg; // 取指附加信息({分支预测信息(96bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	wire[IBUS_TID_WIDTH-1:0] s_if_regs_id; // 指令编号
	wire s_if_regs_is_first_inst_after_rst; // 是否复位释放后的第1条指令
	wire s_if_regs_valid;
	wire s_if_regs_ready;
	// 取指缓存输出
	wire[127:0] m_if_regs_data; // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	wire[98:0] m_if_regs_msg; // 取指附加信息({分支预测信息(96bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	wire[IBUS_TID_WIDTH-1:0] m_if_regs_id; // 指令编号
	wire m_if_regs_is_first_inst_after_rst; // 是否复位释放后的第1条指令
	wire m_if_regs_valid;
	wire m_if_regs_ready;
	
	assign m_if_res_data = m_if_regs_data;
	assign m_if_res_msg = m_if_regs_msg;
	assign m_if_res_id = m_if_regs_id;
	assign m_if_res_is_first_inst_after_rst = m_if_regs_is_first_inst_after_rst;
	assign m_if_res_valid = m_if_regs_valid;
	assign m_if_regs_ready = m_if_res_ready;
	
	generate
		if(EN_IF_REGS == "true")
		begin
			panda_risc_v_if_regs #(
				.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
				.SIM_DELAY(SIM_DELAY)
			)if_regs_u(
				.aclk(aclk),
				.aresetn(aresetn),
				
				.sys_reset_req(sys_reset_req),
				.flush_req(flush_req | ifu_exclusive_flush_req),
				
				.s_if_regs_data(s_if_regs_data),
				.s_if_regs_msg(s_if_regs_msg),
				.s_if_regs_id(s_if_regs_id),
				.s_if_regs_is_first_inst_after_rst(s_if_regs_is_first_inst_after_rst),
				.s_if_regs_valid(s_if_regs_valid),
				.s_if_regs_ready(s_if_regs_ready),
				
				.m_if_regs_data(m_if_regs_data),
				.m_if_regs_msg(m_if_regs_msg),
				.m_if_regs_id(m_if_regs_id),
				.m_if_regs_is_first_inst_after_rst(m_if_regs_is_first_inst_after_rst),
				.m_if_regs_valid(m_if_regs_valid),
				.m_if_regs_ready(m_if_regs_ready)
			);
		end
		else
		begin
			assign m_if_regs_data = s_if_regs_data;
			assign m_if_regs_msg = s_if_regs_msg;
			assign m_if_regs_id = s_if_regs_id;
			assign m_if_regs_is_first_inst_after_rst = s_if_regs_is_first_inst_after_rst;
			assign m_if_regs_valid = s_if_regs_valid;
			assign s_if_regs_ready = m_if_regs_ready;
		end
	endgenerate
	
	/** 指令总线控制单元 **/
	// 清空指令缓存(指示)
	wire clr_inst_buf;
	// 分支预测信息广播
	wire prdt_bdcst_vld; // 广播有效
	wire[IBUS_TID_WIDTH-1:0] prdt_bdcst_tid; // 事务ID
	wire[PRDT_MSG_WIDTH-1:0] prdt_bdcst_msg; // 分支预测信息
	// 指令总线访问请求
	wire[31:0] ibus_access_req_addr; // 访问地址(PC)
	wire[IBUS_TID_WIDTH-1:0] ibus_access_req_tid; // 事务ID
	wire[IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH-1:0] ibus_access_req_extra_msg; // 附带信息
	wire ibus_access_req_valid;
	wire ibus_access_req_ready;
	// 指令总线访问应答
	wire[31:0] ibus_access_resp_rdata; // 读数据(指令)
	wire[1:0] ibus_access_resp_err; // 错误类型
	wire[31:0] ibus_access_resp_addr; // 访问地址(PC)
	wire[IBUS_TID_WIDTH-1:0] ibus_access_resp_tid; // 事务ID
	wire[IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH-1:0] ibus_access_resp_extra_msg; // 附带信息
	wire[63:0] ibus_access_resp_pre_decoding_msg; // 预译码信息
	wire[PRDT_MSG_WIDTH-1:0] ibus_access_resp_prdt; // 分支预测信息
	wire ibus_access_resp_valid;
	wire ibus_access_resp_ready;
	// 取指阶段分支信息广播
	wire brc_bdcst_iftc_vld; // 广播有效
	wire[IBUS_TID_WIDTH-1:0] brc_bdcst_iftc_tid; // 事务ID
	wire brc_bdcst_iftc_is_b_inst; // 是否B指令
	wire brc_bdcst_iftc_is_jal_inst; // 是否JAL指令
	wire brc_bdcst_iftc_is_jalr_inst; // 是否JALR指令
	wire[31:0] brc_bdcst_iftc_bta; // 分支目标地址
	
	assign s_if_regs_data = {
		ibus_access_resp_addr, // 指令对应的PC(32bit)
		ibus_access_resp_pre_decoding_msg, // 打包的预译码信息(64bit)
		ibus_access_resp_rdata // 取到的指令(32bit)
	};
	assign s_if_regs_msg[1:0] = ibus_access_resp_err; // 指令存储器访问错误码
	assign s_if_regs_msg[2] = ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID]; // 是否非法指令
	// 分支预测信息
	assign s_if_regs_msg[98:3] = {
		ibus_access_resp_prdt[PRDT_MSG_BHR_SID+15:PRDT_MSG_BHR_SID], // BHR
		ibus_access_resp_prdt[PRDT_MSG_POP_RAS_SID], // RAS出栈标志
		ibus_access_resp_prdt[PRDT_MSG_PUSH_RAS_SID], // RAS压栈标志
		ibus_access_resp_prdt[PRDT_MSG_BTB_BTA_SID+31:PRDT_MSG_BTB_BTA_SID], // BTB分支目标地址
		ibus_access_resp_prdt[PRDT_MSG_GLB_SAT_CNT_SID+1:PRDT_MSG_GLB_SAT_CNT_SID], // 基于历史的分支预测给出的2bit饱和计数器
		ibus_access_resp_prdt[PRDT_MSG_BTB_WVLD_SID+3:PRDT_MSG_BTB_WVLD_SID], // BTB缓存路有效标志
		ibus_access_resp_prdt[PRDT_MSG_BTB_WID_SID+1:PRDT_MSG_BTB_WID_SID], // BTB命中的缓存路编号
		ibus_access_resp_prdt[PRDT_MSG_BTB_HIT_SID], // BTB命中
		ibus_access_resp_prdt[PRDT_MSG_IS_TAKEN_SID], // 是否跳转
		ibus_access_resp_prdt[PRDT_MSG_BTYPE_SID+2:PRDT_MSG_BTYPE_SID], // 分支指令类型
		ibus_access_resp_prdt[PRDT_MSG_TARGET_ADDR_SID+31:PRDT_MSG_TARGET_ADDR_SID] // 跳转地址
	} | 96'd0;
	
	assign s_if_regs_id = ibus_access_resp_tid;
	assign s_if_regs_is_first_inst_after_rst = ibus_access_resp_extra_msg[IBUS_ACCESS_REQ_EXTRA_MSG_IS_FIRST_INST_SID];
	assign s_if_regs_valid = (~(sys_reset_req | flush_req | ifu_exclusive_flush_req)) & ibus_access_resp_valid;
	
	assign ibus_access_resp_ready = (~(sys_reset_req | flush_req | ifu_exclusive_flush_req)) & s_if_regs_ready;
	
	assign brc_bdcst_iftc_vld = ibus_access_resp_valid & ibus_access_resp_ready;
	assign brc_bdcst_iftc_tid = ibus_access_resp_tid;
	assign brc_bdcst_iftc_is_b_inst = 
		ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_IS_B_INST_SID] & 
		(~ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID]);
	assign brc_bdcst_iftc_is_jal_inst = 
		ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_IS_JAL_INST_SID] & 
		(~ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID]);
	assign brc_bdcst_iftc_is_jalr_inst = 
		ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_IS_JALR_INST_SID] & 
		(~ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID]);
	// 说明: 当实际分支指令类型不是JALR时, 从"取指阶段分支信息广播"获得真实的BTA, 对B指令重新预测为跳
	assign brc_bdcst_iftc_bta = 
		ibus_access_resp_addr + (
			(brc_bdcst_iftc_is_b_inst | brc_bdcst_iftc_is_jal_inst) ? 
				{
					{11{ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_JUMP_OFS_IMM_SID+20]}}, 
					ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_JUMP_OFS_IMM_SID+20:PRE_DCD_MSG_JUMP_OFS_IMM_SID]
				}:
				3'd4
		);
	
	panda_risc_v_ibus_ctrler #(
		.IBUS_ACCESS_TIMEOUT_TH(IBUS_ACCESS_TIMEOUT_TH),
		.INST_ADDR_ALIGNMENT_WIDTH(INST_ADDR_ALIGNMENT_WIDTH),
		.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
		.IBUS_OUTSTANDING_N(IBUS_OUTSTANDING_N),
		.IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH(IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH),
		.PRDT_MSG_WIDTH(PRDT_MSG_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)ibus_ctrler_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.clr_inst_buf(clr_inst_buf),
		.suppressing_ibus_access(suppressing_ibus_access),
		.clr_inst_buf_while_suppressing(clr_inst_buf_while_suppressing),
		.ibus_timeout(ibus_timeout),
		
		.prdt_bdcst_vld(prdt_bdcst_vld),
		.prdt_bdcst_tid(prdt_bdcst_tid),
		.prdt_bdcst_msg(prdt_bdcst_msg),
		
		.ibus_access_req_addr(ibus_access_req_addr),
		.ibus_access_req_tid(ibus_access_req_tid),
		.ibus_access_req_extra_msg(ibus_access_req_extra_msg),
		.ibus_access_req_valid(ibus_access_req_valid),
		.ibus_access_req_ready(ibus_access_req_ready),
		
		.ibus_access_resp_rdata(ibus_access_resp_rdata),
		.ibus_access_resp_err(ibus_access_resp_err),
		.ibus_access_resp_addr(ibus_access_resp_addr),
		.ibus_access_resp_tid(ibus_access_resp_tid),
		.ibus_access_resp_extra_msg(ibus_access_resp_extra_msg),
		.ibus_access_resp_pre_decoding_msg(ibus_access_resp_pre_decoding_msg),
		.ibus_access_resp_prdt(ibus_access_resp_prdt),
		.ibus_access_resp_valid(ibus_access_resp_valid),
		.ibus_access_resp_ready(ibus_access_resp_ready),
		
		.m_icb_cmd_addr(m_icb_cmd_inst_addr),
		.m_icb_cmd_read(m_icb_cmd_inst_read),
		.m_icb_cmd_wdata(m_icb_cmd_inst_wdata),
		.m_icb_cmd_wmask(m_icb_cmd_inst_wmask),
		.m_icb_cmd_valid(m_icb_cmd_inst_valid),
		.m_icb_cmd_ready(m_icb_cmd_inst_ready),
		.m_icb_rsp_rdata(m_icb_rsp_inst_rdata),
		.m_icb_rsp_err(m_icb_rsp_inst_err),
		.m_icb_rsp_valid(m_icb_rsp_inst_valid),
		.m_icb_rsp_ready(m_icb_rsp_inst_ready)
	);
	
	/** 检查JAL和普通指令的分支预测 **/
	wire on_need_flush; // 需要冲刷(指示)
	wire[31:0] correct_npc; // 正确的下一PC值
	reg on_start_flush; // 开始冲刷(指示)
	reg flush_pending; // 冲刷等待(标志)
	reg[31:0] flush_addr_r; // 冲刷地址
	
	assign ifu_flush_req = on_start_flush | flush_pending;
	assign ifu_flush_addr = flush_addr_r;
	
	assign on_need_flush = 
		(~(sys_reset_req | flush_req | ifu_exclusive_flush_req)) & 
		ibus_access_resp_valid & ibus_access_resp_ready & 
		(~(
			// 分支预测特例: BTB命中, BTB给出的分支指令类型为JALR, RAS出栈标志无效
			ibus_access_resp_prdt[PRDT_MSG_BTB_HIT_SID] & 
			(ibus_access_resp_prdt[2+PRDT_MSG_BTYPE_SID:PRDT_MSG_BTYPE_SID] == BRANCH_TYPE_JALR) & 
			(~ibus_access_resp_prdt[PRDT_MSG_POP_RAS_SID])
		)) & 
		(
			// 是JAL指令或非法指令或普通指令(非分支指令)
			(
				(~ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID]) & 
				ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_IS_JAL_INST_SID]
			) | 
			(
				ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID] | 
				(~(
					ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_IS_B_INST_SID] | 
					ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_IS_JAL_INST_SID] | 
					ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_IS_JALR_INST_SID]
				))
			)
		) & 
		(ibus_access_resp_prdt[31+PRDT_MSG_TARGET_ADDR_SID:PRDT_MSG_TARGET_ADDR_SID] != correct_npc);
	assign correct_npc = brc_bdcst_iftc_bta;
	
	// 冲刷地址
	always @(posedge aclk)
	begin
		if(on_need_flush)
			flush_addr_r <= # SIM_DELAY correct_npc;
	end
	
	// 开始冲刷(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			on_start_flush <= 1'b0;
		else
			on_start_flush <= # SIM_DELAY on_need_flush;
	end
	
	// 冲刷等待(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			flush_pending <= 1'b0;
		else if(
			flush_req | 
			(
				flush_pending ? 
					ifu_flush_grant:
					(on_start_flush & (~ifu_flush_grant))
			)
		)
			flush_pending <= # SIM_DELAY ~(flush_req | flush_pending);
	end
	
	/** 置换BTB条目 **/
	wire btb_rplc_req; // 置换请求
	wire btb_rplc_strgy; // 置换策略(1'b0 -> 随机, 1'b1 -> 定向)
	wire[1:0] btb_rplc_sel_wid; // 置换选定的缓存路编号
	wire[31:0] btb_rplc_pc; // 分支指令对应的PC
	wire[2:0] btb_rplc_btype; // 分支指令类型
	wire[31:0] btb_rplc_bta; // 分支指令对应的目标地址
	wire btb_rplc_jpdir; // BTFN跳转方向(1'b1 -> 向后, 1'b0 -> 向前)
	wire btb_rplc_push_ras; // RAS压栈标志
	wire btb_rplc_pop_ras; // RAS出栈标志
	wire btb_rplc_vld_flag; // 有效标志
	wire is_rd_eq_link; // RD为link寄存器(标志)
	wire is_rs1_eq_link; // RS1为link寄存器(标志)
	wire is_rd_eq_rs1; // RD与RS1相同(标志)
	wire[1:0] invld_btb_sel_wid; // 选取的无效的BTB缓存路编号
	wire is_brc_inst; // 是否分支指令
	reg btb_rplc_suppress; // BTB置换(镇压标志)
	
	// 说明: 由于希望尽早更新BTB, 这里是在得到取指应答的首个clk就发起置换请求, 而无论后级是否拿走取指结果
	assign btb_rplc_req = 
		ibus_access_resp_valid & (~btb_rplc_suppress) & 
		(is_brc_inst | ibus_access_resp_prdt[PRDT_MSG_BTB_HIT_SID]);
	/*
	说明: 对于取到的指令, 只要它是分支指令就考虑置换BTB项
	      如果在BTB中可以找到这条分支指令的信息(预测时BTB命中), 则覆盖找到的这1项, 这在分支信息本身就正确时可能会浪费功耗, 
			  但这在指令自修改时是有必要的
	      如果预测时BTB缺失, 那么就先考虑替换1个无效项, 否则就随机找1项来替换
	*/
	assign btb_rplc_strgy = 
		ibus_access_resp_prdt[PRDT_MSG_BTB_HIT_SID] | 
		(~(&ibus_access_resp_prdt[PRDT_MSG_BTB_WVLD_SID+BTB_WAY_N-1:PRDT_MSG_BTB_WVLD_SID]));
	assign btb_rplc_sel_wid = 
		ibus_access_resp_prdt[PRDT_MSG_BTB_HIT_SID] ? 
			ibus_access_resp_prdt[PRDT_MSG_BTB_WID_SID+1:PRDT_MSG_BTB_WID_SID]:
			invld_btb_sel_wid;
	assign btb_rplc_pc = ibus_access_resp_addr;
	assign btb_rplc_btype = 
		({3{ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_IS_JAL_INST_SID]}} & BRANCH_TYPE_JAL) | 
		({3{ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_IS_JALR_INST_SID]}} & BRANCH_TYPE_JALR) | 
		({3{ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_IS_B_INST_SID]}} & BRANCH_TYPE_B);
	assign btb_rplc_bta = brc_bdcst_iftc_bta;
	assign btb_rplc_jpdir = ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_JUMP_OFS_IMM_SID+20];
	/*
	link为x1或x5
	
	对于JAL指令, rd = link时push
	对于JALR指令:
		  rd  |  rs1  | rs1 = rd |   RAS操作
	  -------------------------------------------
		!link | !link |    ---   |    none
		!link | link  |    ---   |    pop
		link  | !link |    ---   |    push
		link  | link  |     0    |  push and pop
		link  | link  |     1    |    push
	*/
	assign btb_rplc_push_ras = 
		(~ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID]) & is_rd_eq_link & (
			ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_IS_JAL_INST_SID] | 
			ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_IS_JALR_INST_SID]
		);
	assign btb_rplc_pop_ras = 
		(~ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID]) & 
		ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_IS_JALR_INST_SID] & 
		(is_rs1_eq_link & (~(is_rd_eq_link & is_rd_eq_rs1)));
	assign btb_rplc_vld_flag = 
		// 说明: 对于取到的指令, 如果它不是分支指令但在预测时BTB命中, 此时BTB条目是过时的, 需要无效化该项
		~((~is_brc_inst) & ibus_access_resp_prdt[PRDT_MSG_BTB_HIT_SID]);
	
	assign is_rd_eq_link = (ibus_access_resp_rdata[11:7] == 5'd1) | (ibus_access_resp_rdata[11:7] == 5'd5);
	assign is_rs1_eq_link = (ibus_access_resp_rdata[19:15] == 5'd1) | (ibus_access_resp_rdata[19:15] == 5'd5);
	assign is_rd_eq_rs1 = ibus_access_resp_rdata[11:7] == ibus_access_resp_rdata[19:15];
	
	assign invld_btb_sel_wid = 
		(BTB_WAY_N == 1) ? 2'b00:
		(BTB_WAY_N == 2) ? (
			(~ibus_access_resp_prdt[PRDT_MSG_BTB_WVLD_SID]) ? 
				2'b00:
				2'b01
		):(
			(~ibus_access_resp_prdt[PRDT_MSG_BTB_WVLD_SID])   ? 2'b00:
			(~ibus_access_resp_prdt[PRDT_MSG_BTB_WVLD_SID+1]) ? 2'b01:
			(~ibus_access_resp_prdt[PRDT_MSG_BTB_WVLD_SID+2]) ? 2'b10:
			                                                    2'b11
		);
	assign is_brc_inst = 
		(~ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_ILLEGAL_INST_FLAG_SID]) & (
			ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_IS_JAL_INST_SID] | 
			ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_IS_JALR_INST_SID] | 
			ibus_access_resp_pre_decoding_msg[PRE_DCD_MSG_IS_B_INST_SID]
		);
	
	// BTB置换(镇压标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			btb_rplc_suppress <= 1'b0;
		else if(
			(sys_reset_req | flush_req | ifu_exclusive_flush_req) | (
				/*
				btb_rplc_suppress ? 
					ibus_access_resp_ready:
					(ibus_access_resp_valid & (is_brc_inst | ibus_access_resp_prdt[PRDT_MSG_BTB_HIT_SID]) & (~ibus_access_resp_ready))
				*/
				(btb_rplc_suppress | (ibus_access_resp_valid & (is_brc_inst | ibus_access_resp_prdt[PRDT_MSG_BTB_HIT_SID]))) & 
				((~btb_rplc_suppress) ^ ibus_access_resp_ready)
			)
		)
			btb_rplc_suppress <= # SIM_DELAY 
				(~(sys_reset_req | flush_req | ifu_exclusive_flush_req)) & (~btb_rplc_suppress);
	end
	
	/** 预取指单元(含分支预测) **/
	panda_risc_v_pre_if #(
		.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
		.IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH(IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH),
		.PRDT_MSG_WIDTH(PRDT_MSG_WIDTH),
		.GHR_WIDTH(GHR_WIDTH),
		.PC_WIDTH(PC_WIDTH),
		.BHR_WIDTH(BHR_WIDTH),
		.BHT_DEPTH(BHT_DEPTH),
		.PHT_MEM_IMPL(PHT_MEM_IMPL),
		.NO_INIT_PHT(NO_INIT_PHT),
		.BTB_WAY_N(BTB_WAY_N),
		.BTB_ENTRY_N(BTB_ENTRY_N),
		.PC_TAG_WIDTH(PC_TAG_WIDTH),
		.BTB_MEM_WIDTH(BTB_MEM_WIDTH),
		.NO_INIT_BTB(NO_INIT_BTB),
		.RAS_ENTRY_N(RAS_ENTRY_N),
		.SIM_DELAY(SIM_DELAY)
	)pre_inst_fetch_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.sys_reset_req(sys_reset_req),
		.rst_pc(rst_pc),
		.flush_req(flush_req | ifu_exclusive_flush_req),
		.flush_addr(flush_addr),
		.rst_ack(rst_ack),
		.flush_ack(flush_ack),
		
		.clr_inst_buf(clr_inst_buf),
		
		.ibus_access_req_addr(ibus_access_req_addr),
		.ibus_access_req_tid(ibus_access_req_tid),
		.ibus_access_req_extra_msg(ibus_access_req_extra_msg),
		.ibus_access_req_valid(ibus_access_req_valid),
		.ibus_access_req_ready(ibus_access_req_ready),
		
		.prdt_bdcst_vld(prdt_bdcst_vld),
		.prdt_bdcst_tid(prdt_bdcst_tid),
		.prdt_bdcst_msg(prdt_bdcst_msg),
		
		.brc_bdcst_iftc_vld(brc_bdcst_iftc_vld),
		.brc_bdcst_iftc_tid(brc_bdcst_iftc_tid),
		.brc_bdcst_iftc_is_b_inst(brc_bdcst_iftc_is_b_inst),
		.brc_bdcst_iftc_is_jal_inst(brc_bdcst_iftc_is_jal_inst),
		.brc_bdcst_iftc_is_jalr_inst(brc_bdcst_iftc_is_jalr_inst),
		.brc_bdcst_iftc_bta(brc_bdcst_iftc_bta),
		
		.brc_bdcst_luc_vld(brc_bdcst_luc_vld),
		.brc_bdcst_luc_tid(brc_bdcst_luc_tid),
		.brc_bdcst_luc_is_b_inst(brc_bdcst_luc_is_b_inst),
		.brc_bdcst_luc_is_jal_inst(brc_bdcst_luc_is_jal_inst),
		.brc_bdcst_luc_is_jalr_inst(brc_bdcst_luc_is_jalr_inst),
		.brc_bdcst_luc_bta(brc_bdcst_luc_bta),
		
		.glb_brc_prdt_on_clr_retired_ghr(glb_brc_prdt_on_clr_retired_ghr),
		.glb_brc_prdt_on_upd_retired_ghr(glb_brc_prdt_on_upd_retired_ghr),
		.glb_brc_prdt_retired_ghr_shift_in(glb_brc_prdt_retired_ghr_shift_in),
		
		.glb_brc_prdt_rstr_speculative_ghr(glb_brc_prdt_rstr_speculative_ghr),
		
		.glb_brc_prdt_upd_i_req(glb_brc_prdt_upd_i_req),
		.glb_brc_prdt_upd_i_pc(glb_brc_prdt_upd_i_pc),
		.glb_brc_prdt_upd_i_ghr(glb_brc_prdt_upd_i_ghr),
		.glb_brc_prdt_upd_i_bhr(glb_brc_prdt_upd_i_bhr),
		.glb_brc_prdt_upd_i_2bit_sat_cnt(glb_brc_prdt_upd_i_2bit_sat_cnt),
		.glb_brc_prdt_upd_i_brc_taken(glb_brc_prdt_upd_i_brc_taken),
		.glb_brc_prdt_retired_ghr_o(glb_brc_prdt_retired_ghr_o),
		
		.pht_mem_clka(pht_mem_clka),
		.pht_mem_ena(pht_mem_ena),
		.pht_mem_wea(pht_mem_wea),
		.pht_mem_addra(pht_mem_addra),
		.pht_mem_dina(pht_mem_dina),
		.pht_mem_douta(pht_mem_douta),
		
		.pht_mem_clkb(pht_mem_clkb),
		.pht_mem_enb(pht_mem_enb),
		.pht_mem_web(pht_mem_web),
		.pht_mem_addrb(pht_mem_addrb),
		.pht_mem_dinb(pht_mem_dinb),
		.pht_mem_doutb(pht_mem_doutb),
		
		.btb_rplc_req(btb_rplc_req),
		.btb_rplc_strgy(btb_rplc_strgy),
		.btb_rplc_sel_wid(btb_rplc_sel_wid),
		.btb_rplc_pc(btb_rplc_pc),
		.btb_rplc_btype(btb_rplc_btype),
		.btb_rplc_bta(btb_rplc_bta),
		.btb_rplc_jpdir(btb_rplc_jpdir),
		.btb_rplc_push_ras(btb_rplc_push_ras),
		.btb_rplc_pop_ras(btb_rplc_pop_ras),
		.btb_rplc_vld_flag(btb_rplc_vld_flag),
		
		.btb_mem_clka(btb_mem_clka),
		.btb_mem_ena(btb_mem_ena),
		.btb_mem_wea(btb_mem_wea),
		.btb_mem_addra(btb_mem_addra),
		.btb_mem_dina(btb_mem_dina),
		.btb_mem_douta(btb_mem_douta),
		
		.btb_mem_clkb(btb_mem_clkb),
		.btb_mem_enb(btb_mem_enb),
		.btb_mem_web(btb_mem_web),
		.btb_mem_addrb(btb_mem_addrb),
		.btb_mem_dinb(btb_mem_dinb),
		.btb_mem_doutb(btb_mem_doutb)
	);
	
endmodule
