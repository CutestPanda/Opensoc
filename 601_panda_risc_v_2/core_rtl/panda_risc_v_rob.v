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
本模块: 重排序队列

描述:
基于FIFO的ROB
ROB项记录了指令的指令ID、被发射到的执行单元ID、目的寄存器编号、指令类型、错误类型
为每个ROB项保存了写指针以确定条目的新旧情况
每个ROB项都会自动监听其被发射到的执行单元的结果, 并在该条目内暂存数据
每个ROB项都会自动监听其BRU结果(指令对应的PC、指令对应的下一有效PC、B指令执行结果)
使用逻辑寄存器位置表来确定每个逻辑寄存器是否在ROB或旁路网络中, 或者已经被写回通用寄存器堆
支持清空ROB
独立的CSR读写指令信息记录表(其深度决定了能存在于ROB中的CSR读写指令的个数)
支持取消单个ROB项、(比基准写指针)更年轻的ROB项, 支持发射时自动取消带有同步异常的ROB项

注意：
不允许同时发射和退休相同指令
只能退休ROB中最旧的那条指令, 即按照FIFO方式让指令退出ROB
如果某条指令无需写RD, 那么在发射时将RD指定为x0即可
CSR读写指令信息记录槽位数(CSR_RW_RCD_SLOTS_N)不能大于ROB项数(ROB_ENTRY_N)

协议:
无

作者: 陈家耀
日期: 2026/02/05
********************************************************************/


module panda_risc_v_rob #(
	parameter integer IBUS_TID_WIDTH = 8, // 指令总线事务ID位宽(1~16)
	parameter integer FU_ID_WIDTH = 8, // 执行单元ID位宽(1~16)
	parameter integer ROB_ENTRY_N = 8, // 重排序队列项数(4 | 8 | 16 | 32)
	parameter integer CSR_RW_RCD_SLOTS_N = 4, // CSR读写指令信息记录槽位数(2 | 4 | 8 | 16 | 32)
	parameter integer LSN_FU_N = 5, // 要监听结果的执行单元的个数(正整数)
	parameter integer FU_RES_WIDTH = 32, // 执行单元结果位宽(正整数)
	parameter integer FU_ERR_WIDTH = 3, // 执行单元错误码位宽(正整数)
	parameter integer LSU_FU_ID = 2, // LSU的执行单元ID
	parameter AUTO_CANCEL_SYNC_ERR_ENTRY = "true", // 是否在发射时自动取消带有同步异常的项
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// ROB控制/状态
	input wire rob_clr, // 清空ROB(指示)
	output wire rob_full_n, // ROB满(标志)
	output wire rob_empty_n, // ROB空(标志)
	output wire rob_csr_rw_inst_allowed, // 允许发射CSR读写指令(标志)
	output wire rob_has_ls_inst, // ROB中存在访存指令(标志)
	
	// 取消指定的1项
	input wire rob_sng_cancel_vld, // 有效标志
	input wire[IBUS_TID_WIDTH-1:0] rob_sng_cancel_tid, // 被取消项的指令ID
	// 取消所有更年轻项
	input wire rob_yngr_cancel_vld, // 有效标志
	input wire[5:0] rob_yngr_cancel_bchmk_wptr, // 基准写指针
	
	// 读操作数(数据相关性检查)
	// [操作数1]
	input wire[4:0] op1_ftc_rs1_id, // 1号源寄存器编号
	output wire op1_ftc_from_reg_file, // 从寄存器堆取到操作数(标志)
	output wire op1_ftc_from_rob, // 从ROB取到操作数(标志)
	output wire op1_ftc_from_byp, // 从旁路网络取到操作数(标志)
	output wire[FU_ID_WIDTH-1:0] op1_ftc_fuid, // 待旁路的执行单元编号
	output wire[IBUS_TID_WIDTH-1:0] op1_ftc_tid, // 待旁路的指令ID
	output wire[FU_RES_WIDTH-1:0] op1_ftc_rob_saved_data, // ROB暂存的执行结果
	// [操作数2]
	input wire[4:0] op2_ftc_rs2_id, // 2号源寄存器编号
	output wire op2_ftc_from_reg_file, // 从寄存器堆取到操作数(标志)
	output wire op2_ftc_from_rob, // 从ROB取到操作数(标志)
	output wire op2_ftc_from_byp, // 从旁路网络取到操作数(标志)
	output wire[FU_ID_WIDTH-1:0] op2_ftc_fuid, // 待旁路的执行单元编号
	output wire[IBUS_TID_WIDTH-1:0] op2_ftc_tid, // 待旁路的指令ID
	output wire[FU_RES_WIDTH-1:0] op2_ftc_rob_saved_data, // ROB暂存的执行结果
	
	// 准备退休的ROB项
	output wire rob_prep_rtr_entry_vld, // 有效标志
	output wire rob_prep_rtr_entry_saved, // 结果已保存(标志)
	output wire[2:0] rob_prep_rtr_entry_err, // 错误码
	output wire[4:0] rob_prep_rtr_entry_rd_id, // 目的寄存器编号
	output wire rob_prep_rtr_entry_is_csr_rw_inst, // 是否CSR读写指令
	output wire[2:0] rob_prep_rtr_entry_spec_inst_type, // 特殊指令类型
	output wire rob_prep_rtr_entry_cancel, // 取消标志
	output wire[FU_RES_WIDTH-1:0] rob_prep_rtr_entry_fu_res, // 保存的执行结果
	output wire[31:0] rob_prep_rtr_entry_pc, // 指令对应的PC
	output wire[31:0] rob_prep_rtr_entry_nxt_pc, // 指令对应的下一有效PC
	output wire[1:0] rob_prep_rtr_entry_b_inst_res, // B指令执行结果
	output wire[1:0] rob_prep_rtr_entry_org_2bit_sat_cnt, // 原来的2bit饱和计数器
	output wire[15:0] rob_prep_rtr_entry_bhr, // BHR
	output wire[11:0] rob_prep_rtr_entry_csr_rw_waddr, // CSR写地址
	output wire[1:0] rob_prep_rtr_entry_csr_rw_upd_type, // CSR更新类型
	output wire[31:0] rob_prep_rtr_entry_csr_rw_upd_mask_v, // CSR更新掩码或更新值
	
	// 执行单元结果返回
	input wire[LSN_FU_N-1:0] fu_res_vld, // 有效标志
	input wire[LSN_FU_N*IBUS_TID_WIDTH-1:0] fu_res_tid, // 指令ID
	input wire[LSN_FU_N*FU_RES_WIDTH-1:0] fu_res_data, // 执行结果
	input wire[LSN_FU_N*FU_ERR_WIDTH-1:0] fu_res_err, // 错误码
	
	// BRU结果
	input wire[IBUS_TID_WIDTH-1:0] s_bru_o_tid, // 指令ID
	input wire[31:0] s_bru_o_pc, // 当前PC地址
	input wire[31:0] s_bru_o_nxt_pc, // 下一有效PC地址
	input wire[1:0] s_bru_o_b_inst_res, // B指令执行结果
	input wire[1:0] s_bru_o_org_2bit_sat_cnt, // 原来的2bit饱和计数器
	input wire[15:0] s_bru_o_bhr, // BHR
	input wire s_bru_o_valid,
	
	// 写存储器许可
	output wire wr_mem_permitted_flag, // 许可标志
	output wire[IBUS_TID_WIDTH-1:0] init_mem_bus_tr_store_inst_tid, // 待发起总线事务的store指令ID
	// 外设访问许可
	output wire perph_access_permitted_flag, // 许可标志
	output wire[IBUS_TID_WIDTH-1:0] init_perph_bus_tr_ls_inst_tid, // 待发起外设总线事务的访存指令ID
	
	// ROB记录广播
	// [发射阶段]
	input wire rob_luc_bdcst_vld, // 广播有效
	input wire[IBUS_TID_WIDTH-1:0] rob_luc_bdcst_tid, // 指令ID
	input wire[FU_ID_WIDTH-1:0] rob_luc_bdcst_fuid, // 被发射到的执行单元ID
	input wire[4:0] rob_luc_bdcst_rd_id, // 目的寄存器编号
	input wire rob_luc_bdcst_is_ls_inst, // 是否加载/存储指令
	input wire rob_luc_bdcst_is_csr_rw_inst, // 是否CSR读写指令
	input wire[45:0] rob_luc_bdcst_csr_rw_inst_msg, // CSR读写指令信息({CSR写地址(12bit), CSR更新类型(2bit), CSR更新掩码或更新值(32bit)})
	input wire[2:0] rob_luc_bdcst_err, // 错误类型
	input wire[2:0] rob_luc_bdcst_spec_inst_type, // 特殊指令类型
	// [退休阶段]
	input wire rob_rtr_bdcst_vld // 广播有效
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
	// LSU错误类型
	localparam LSU_ERR_CODE_NORMAL = 3'b000; // 正常
	localparam LSU_ERR_CODE_RD_ADDR_UNALIGNED = 3'b001; // 读访问地址非对齐
	localparam LSU_ERR_CODE_WT_ADDR_UNALIGNED = 3'b010; // 写访问地址非对齐
	localparam LSU_ERR_CODE_RD_FAILED = 3'b011; // 读访问失败
	localparam LSU_ERR_CODE_WT_FAILED = 3'b100; // 写访问失败
	// 待发射指令错误类型
	localparam LUC_INST_ERR_CODE_NORMAL = 3'b000; // 正常
	localparam LUC_INST_ERR_CODE_ILLEGAL = 3'b001; // 非法指令
	localparam LUC_INST_ERR_CODE_PC_UNALIGNED = 3'b010; // 指令地址非对齐
	localparam LUC_INST_ERR_CODE_IMEM_ACCESS_FAILED = 3'b011; // 指令总线访问失败
	localparam LUC_INST_ERR_CODE_RD_DBUS_FAILED = 3'b100; // 读存储映射失败
	localparam LUC_INST_ERR_CODE_WT_DBUS_FAILED = 3'b101; // 写存储映射失败
	localparam LUC_INST_ERR_CODE_RD_DBUS_UNALIGNED = 3'b110; // 读存储映射地址非对齐
	localparam LUC_INST_ERR_CODE_WT_DBUS_UNALIGNED = 3'b111; // 写存储映射地址非对齐
	
	/** ROB记录表读写控制 **/
	reg[clogb2(ROB_ENTRY_N):0] rob_vld_entry_n; // ROB记录表有效项数
	reg rob_rcd_tb_full_n; // ROB记录表满(标志)
	reg rob_rcd_tb_empty_n; // ROB记录表空(标志)
	reg[clogb2(ROB_ENTRY_N):0] rob_rcd_tb_wptr; // ROB记录表写指针
	reg[clogb2(ROB_ENTRY_N):0] rob_rcd_tb_rptr; // ROB记录表读指针
	
	assign rob_full_n = rob_rcd_tb_full_n;
	assign rob_empty_n = rob_rcd_tb_empty_n;
	
	// ROB记录表有效项数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rob_vld_entry_n <= 0;
		else if(rob_clr | ((rob_luc_bdcst_vld & rob_rcd_tb_full_n) ^ rob_rtr_bdcst_vld))
			rob_vld_entry_n <= # SIM_DELAY 
				rob_clr ? 
					0:(
						rob_rtr_bdcst_vld ? 
							(rob_vld_entry_n - 1):
							(rob_vld_entry_n + 1)
					);
	end
	// ROB记录表满(标志), ROB记录表空(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
		begin
			rob_rcd_tb_full_n <= 1'b1;
			rob_rcd_tb_empty_n <= 1'b0;
		end
		else if(rob_clr | ((rob_luc_bdcst_vld & rob_rcd_tb_full_n) ^ rob_rtr_bdcst_vld))
		begin
			rob_rcd_tb_full_n <= # SIM_DELAY 
				rob_clr | rob_rtr_bdcst_vld | (rob_vld_entry_n != (ROB_ENTRY_N - 1));
			rob_rcd_tb_empty_n <= # SIM_DELAY 
				(~rob_clr) & ((rob_luc_bdcst_vld & rob_rcd_tb_full_n) | (rob_vld_entry_n != 1));
		end
	end
	
	// ROB记录表写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rob_rcd_tb_wptr <= 0;
		else if(rob_clr | (rob_luc_bdcst_vld & rob_rcd_tb_full_n))
			rob_rcd_tb_wptr <= # SIM_DELAY 
				rob_clr ? 
					0:
					(rob_rcd_tb_wptr + 1);
	end
	// ROB记录表读指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rob_rcd_tb_rptr <= 0;
		else if(rob_clr | rob_rtr_bdcst_vld) // 说明: 1条指令要退休, 那么在ROB中肯定是记录了这条指令的信息, 此时ROB不可能是空的
			rob_rcd_tb_rptr <= # SIM_DELAY 
				rob_clr ? 
					0:
					(rob_rcd_tb_rptr + 1);
	end
	
	/** CSR读写指令信息记录表读写控制 **/
	reg[clogb2(CSR_RW_RCD_SLOTS_N):0] csr_rw_inst_stored_n; // 已存储的CSR读写指令个数
	reg csr_rw_rcd_full_n; // CSR读写指令信息记录表满标志
	reg[clogb2(CSR_RW_RCD_SLOTS_N-1):0] csr_rw_rcd_wptr; // CSR读写指令信息记录写指针
	reg[clogb2(CSR_RW_RCD_SLOTS_N-1):0] csr_rw_rcd_rptr; // CSR读写指令信息记录读指针
	
	// 已存储的CSR读写指令个数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			csr_rw_inst_stored_n <= 0;
		else if(
			rob_clr | 
			(
				(rob_luc_bdcst_vld & rob_rcd_tb_full_n & rob_luc_bdcst_is_csr_rw_inst) ^ 
				(rob_rtr_bdcst_vld & rob_prep_rtr_entry_is_csr_rw_inst)
			)
		)
			csr_rw_inst_stored_n <= # SIM_DELAY 
				rob_clr ? 
					0:(
						(rob_rtr_bdcst_vld & rob_prep_rtr_entry_is_csr_rw_inst) ? 
							(csr_rw_inst_stored_n - 1):
							(csr_rw_inst_stored_n + 1)
					);
	end
	// CSR读写指令信息记录表满标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			csr_rw_rcd_full_n <= 1'b1;
		else if(rob_clr | 
			(
				(rob_luc_bdcst_vld & rob_rcd_tb_full_n & rob_luc_bdcst_is_csr_rw_inst) ^ 
				(rob_rtr_bdcst_vld & rob_prep_rtr_entry_is_csr_rw_inst)
			)
		)
			csr_rw_rcd_full_n <= # SIM_DELAY 
				rob_clr | 
				(rob_rtr_bdcst_vld & rob_prep_rtr_entry_is_csr_rw_inst) | 
				(csr_rw_inst_stored_n != (CSR_RW_RCD_SLOTS_N - 1));
	end
	
	// CSR读写指令信息记录写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			csr_rw_rcd_wptr <= 0;
		else if(rob_clr | (rob_luc_bdcst_vld & rob_rcd_tb_full_n & rob_luc_bdcst_is_csr_rw_inst))
			csr_rw_rcd_wptr <= # SIM_DELAY 
				rob_clr ? 
					0:
					(csr_rw_rcd_wptr + 1);
	end
	// CSR读写指令信息记录读指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			csr_rw_rcd_rptr <= 0;
		else if(rob_clr | (rob_rtr_bdcst_vld & rob_prep_rtr_entry_is_csr_rw_inst))
			csr_rw_rcd_rptr <= # SIM_DELAY 
				rob_clr ? 
					0:
					(csr_rw_rcd_rptr + 1);
	end
	
	/** CSR读写指令信息记录表存储实体 **/
	reg[11:0] csr_rw_rcd_waddr[0:CSR_RW_RCD_SLOTS_N-1]; // CSR写地址
	reg[1:0] csr_rw_rcd_upd_type[0:CSR_RW_RCD_SLOTS_N-1]; // CSR更新类型
	reg[31:0] csr_rw_rcd_upd_mask_v[0:CSR_RW_RCD_SLOTS_N-1]; // CSR更新掩码或更新值
	reg[clogb2(ROB_ENTRY_N):0] csr_rw_rcd_wptr_saved[0:CSR_RW_RCD_SLOTS_N-1]; // 记录的写指针
	reg[CSR_RW_RCD_SLOTS_N-1:0] csr_rw_rcd_valid; // 有效标志
	wire[CSR_RW_RCD_SLOTS_N-1:0] csr_rw_inst_collision; // CSR读写指令冲突标志
	
	assign rob_prep_rtr_entry_csr_rw_waddr = csr_rw_rcd_waddr[csr_rw_rcd_rptr];
	assign rob_prep_rtr_entry_csr_rw_upd_type = csr_rw_rcd_upd_type[csr_rw_rcd_rptr];
	assign rob_prep_rtr_entry_csr_rw_upd_mask_v = csr_rw_rcd_upd_mask_v[csr_rw_rcd_rptr];
	
	assign rob_csr_rw_inst_allowed = 
		csr_rw_rcd_full_n & (~(|csr_rw_inst_collision));
	
	genvar csr_rw_rcd_i;
	generate
		for(csr_rw_rcd_i = 0;csr_rw_rcd_i < CSR_RW_RCD_SLOTS_N;csr_rw_rcd_i = csr_rw_rcd_i + 1)
		begin:csr_rw_rcd_blk
			assign csr_rw_inst_collision[csr_rw_rcd_i] = 
				// 待发射(CSR读写)指令的CSR地址与尚未退休的CSR读写指令产生冲突
				csr_rw_rcd_valid[csr_rw_rcd_i] & (csr_rw_rcd_waddr[csr_rw_rcd_i] == rob_luc_bdcst_csr_rw_inst_msg[45:34]);
			
			always @(posedge aclk)
			begin
				if(rob_luc_bdcst_vld & rob_rcd_tb_full_n & rob_luc_bdcst_is_csr_rw_inst & (csr_rw_rcd_wptr == csr_rw_rcd_i))
				begin
					{
						csr_rw_rcd_waddr[csr_rw_rcd_i], 
						csr_rw_rcd_upd_type[csr_rw_rcd_i], 
						csr_rw_rcd_upd_mask_v[csr_rw_rcd_i]
					} <= # SIM_DELAY rob_luc_bdcst_csr_rw_inst_msg;
					
					csr_rw_rcd_wptr_saved[csr_rw_rcd_i] <= # SIM_DELAY rob_rcd_tb_wptr;
				end
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					csr_rw_rcd_valid[csr_rw_rcd_i] <= 1'b0;
				else if(
					rob_clr | 
					(rob_luc_bdcst_vld & rob_rcd_tb_full_n & rob_luc_bdcst_is_csr_rw_inst & (csr_rw_rcd_wptr == csr_rw_rcd_i)) | 
					(rob_rtr_bdcst_vld & rob_prep_rtr_entry_is_csr_rw_inst & (csr_rw_rcd_rptr == csr_rw_rcd_i))
				)
					csr_rw_rcd_valid[csr_rw_rcd_i] <= # SIM_DELAY 
						// 断言: 不会出现写和退出同一ROB项的情况
						(~rob_clr) & 
						rob_luc_bdcst_vld & rob_rcd_tb_full_n & rob_luc_bdcst_is_csr_rw_inst & (csr_rw_rcd_wptr == csr_rw_rcd_i);
			end
		end
	endgenerate
	
	/** ROB内有效访存指令数 **/
	wire is_retiring_ls_inst; // 是否正在退休访存指令
	reg[clogb2(ROB_ENTRY_N):0] rob_vld_ls_inst_n; // ROB内有效的访存指令数
	reg rob_has_ls_inst_r; // ROB中存在访存指令(标志)
	
	assign rob_has_ls_inst = rob_has_ls_inst_r;
	
	// ROB内有效的访存指令数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rob_vld_ls_inst_n <= 0;
		else if(
			rob_clr | 
			(
				(rob_luc_bdcst_vld & rob_rcd_tb_full_n & rob_luc_bdcst_is_ls_inst) ^ 
				(rob_rtr_bdcst_vld & is_retiring_ls_inst)
			)
		)
			rob_vld_ls_inst_n <= # SIM_DELAY 
				rob_clr ? 
					0:
					(
						(rob_rtr_bdcst_vld & is_retiring_ls_inst) ? 
							(rob_vld_ls_inst_n - 1):
							(rob_vld_ls_inst_n + 1)
					);
	end
	// ROB中存在访存指令(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rob_has_ls_inst_r <= 1'b0;
		else if(
			rob_clr | 
			(
				(rob_luc_bdcst_vld & rob_rcd_tb_full_n & rob_luc_bdcst_is_ls_inst) ^ 
				(rob_rtr_bdcst_vld & is_retiring_ls_inst)
			)
		)
			rob_has_ls_inst_r <= # SIM_DELAY 
				(~rob_clr) & 
				(
					(~(rob_rtr_bdcst_vld & is_retiring_ls_inst)) | 
					(rob_vld_ls_inst_n != 1)
				);
	end
	
	/** ROB记录表存储实体 **/
	reg[IBUS_TID_WIDTH-1:0] rob_rcd_tb_tid[0:ROB_ENTRY_N-1]; // 指令ID
	reg[FU_ID_WIDTH-1:0] rob_rcd_tb_fuid[0:ROB_ENTRY_N-1]; // 被发射到的执行单元ID
	reg[4:0] rob_rcd_tb_rd_id[0:ROB_ENTRY_N-1]; // 目的寄存器编号
	reg rob_rcd_tb_is_ls_inst[0:ROB_ENTRY_N-1]; // 是否加载/存储指令
	reg rob_rcd_tb_is_csr_rw_inst[0:ROB_ENTRY_N-1]; // 是否CSR读写指令
	reg[2:0] rob_rcd_tb_spec_inst_type[0:ROB_ENTRY_N-1]; // 特殊指令类型
	reg rob_rcd_tb_cancel[0:ROB_ENTRY_N-1]; // 取消标志
	reg[2:0] rob_rcd_tb_err[0:ROB_ENTRY_N-1]; // 错误类型
	reg[clogb2(ROB_ENTRY_N):0] rob_rcd_tb_wptr_saved[0:ROB_ENTRY_N-1]; // 记录的写指针
	reg[FU_RES_WIDTH-1:0] rob_rcd_tb_fu_res[0:ROB_ENTRY_N-1]; // 保存的执行结果
	reg[31:0] rob_rcd_tb_pc[0:ROB_ENTRY_N-1]; // 指令对应的PC
	reg[31:0] rob_rcd_tb_nxt_pc[0:ROB_ENTRY_N-1]; // 指令对应的下一有效PC
	reg[1:0] rob_rcd_tb_b_inst_res[0:ROB_ENTRY_N-1]; // B指令执行结果
	reg[1:0] rob_rcd_tb_org_2bit_sat_cnt[0:ROB_ENTRY_N-1]; // 原来的2bit饱和计数器
	reg[15:0] rob_rcd_tb_bhr[0:ROB_ENTRY_N-1]; // BHR
	reg[ROB_ENTRY_N-1:0] rob_rcd_tb_saved; // 结果已保存(标志)
	reg[ROB_ENTRY_N-1:0] rob_rcd_tb_vld; // 有效标志
	wire[ROB_ENTRY_N-1:0] on_rob_sng_cancel_vld; // 取消单个ROB项(标志向量)
	wire[ROB_ENTRY_N-1:0] on_rob_yngr_cancel_vld; // 取消多个年轻ROB项(标志向量)
	wire[ROB_ENTRY_N-1:0] on_rob_sync_err_cancel_vld; // 取消带有同步异常的ROB项(标志向量)
	
	assign rob_prep_rtr_entry_vld = rob_rcd_tb_vld[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]];
	assign rob_prep_rtr_entry_saved = rob_rcd_tb_saved[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]];
	assign rob_prep_rtr_entry_err = rob_rcd_tb_err[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]];
	assign rob_prep_rtr_entry_rd_id = rob_rcd_tb_rd_id[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]];
	assign rob_prep_rtr_entry_is_csr_rw_inst = rob_rcd_tb_is_csr_rw_inst[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]];
	assign rob_prep_rtr_entry_spec_inst_type = rob_rcd_tb_spec_inst_type[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]];
	assign rob_prep_rtr_entry_cancel = rob_rcd_tb_cancel[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]];
	assign rob_prep_rtr_entry_fu_res = rob_rcd_tb_fu_res[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]];
	assign rob_prep_rtr_entry_pc = rob_rcd_tb_pc[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]];
	assign rob_prep_rtr_entry_nxt_pc = rob_rcd_tb_nxt_pc[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]];
	assign rob_prep_rtr_entry_b_inst_res = rob_rcd_tb_b_inst_res[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]];
	assign rob_prep_rtr_entry_org_2bit_sat_cnt = rob_rcd_tb_org_2bit_sat_cnt[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]];
	assign rob_prep_rtr_entry_bhr = rob_rcd_tb_bhr[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]];
	
	assign is_retiring_ls_inst = rob_rcd_tb_is_ls_inst[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]];
	
	genvar rob_rcd_tb_entry_i;
	generate
		for(rob_rcd_tb_entry_i = 0;rob_rcd_tb_entry_i < ROB_ENTRY_N;rob_rcd_tb_entry_i = rob_rcd_tb_entry_i + 1)
		begin:rob_rcd_tb_entry_blk
			assign on_rob_sng_cancel_vld[rob_rcd_tb_entry_i] = 
				rob_sng_cancel_vld & 
				rob_rcd_tb_vld[rob_rcd_tb_entry_i] & (rob_rcd_tb_tid[rob_rcd_tb_entry_i] == rob_sng_cancel_tid);
			assign on_rob_yngr_cancel_vld[rob_rcd_tb_entry_i] = 
				rob_yngr_cancel_vld & 
				rob_rcd_tb_vld[rob_rcd_tb_entry_i] & (
					(rob_yngr_cancel_bchmk_wptr[5] ^ rob_rcd_tb_wptr_saved[rob_rcd_tb_entry_i][clogb2(ROB_ENTRY_N)]) ^ 
					(rob_rcd_tb_wptr_saved[rob_rcd_tb_entry_i][clogb2(ROB_ENTRY_N-1):0] >= 
						rob_yngr_cancel_bchmk_wptr[clogb2(ROB_ENTRY_N-1):0])
				);
			assign on_rob_sync_err_cancel_vld[rob_rcd_tb_entry_i] = 
				(AUTO_CANCEL_SYNC_ERR_ENTRY == "true") & 
				(rob_luc_bdcst_vld & rob_rcd_tb_full_n & (rob_rcd_tb_wptr[clogb2(ROB_ENTRY_N-1):0] == rob_rcd_tb_entry_i)) & 
				(rob_luc_bdcst_err != LUC_INST_ERR_CODE_NORMAL);
			
			always @(posedge aclk)
			begin
				if(rob_luc_bdcst_vld & rob_rcd_tb_full_n & (rob_rcd_tb_wptr[clogb2(ROB_ENTRY_N-1):0] == rob_rcd_tb_entry_i))
				begin
					rob_rcd_tb_tid[rob_rcd_tb_entry_i] <= # SIM_DELAY rob_luc_bdcst_tid;
					rob_rcd_tb_fuid[rob_rcd_tb_entry_i] <= # SIM_DELAY 
						(rob_luc_bdcst_fuid >= LSN_FU_N) ? 
							0:
							rob_luc_bdcst_fuid;
					rob_rcd_tb_rd_id[rob_rcd_tb_entry_i] <= # SIM_DELAY rob_luc_bdcst_rd_id;
					rob_rcd_tb_is_ls_inst[rob_rcd_tb_entry_i] <= # SIM_DELAY rob_luc_bdcst_is_ls_inst;
					rob_rcd_tb_is_csr_rw_inst[rob_rcd_tb_entry_i] <= # SIM_DELAY rob_luc_bdcst_is_csr_rw_inst;
					rob_rcd_tb_spec_inst_type[rob_rcd_tb_entry_i] <= # SIM_DELAY rob_luc_bdcst_spec_inst_type;
					
					rob_rcd_tb_wptr_saved[rob_rcd_tb_entry_i][clogb2(ROB_ENTRY_N)] <= # SIM_DELAY 
						rob_rcd_tb_wptr[clogb2(ROB_ENTRY_N)];
					rob_rcd_tb_wptr_saved[rob_rcd_tb_entry_i][clogb2(ROB_ENTRY_N-1):0] <= # SIM_DELAY 
						rob_rcd_tb_entry_i;
				end
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					rob_rcd_tb_vld[rob_rcd_tb_entry_i] <= 1'b0;
				else if(
					rob_clr | 
					(rob_luc_bdcst_vld & rob_rcd_tb_full_n & (rob_rcd_tb_wptr[clogb2(ROB_ENTRY_N-1):0] == rob_rcd_tb_entry_i)) | 
					(rob_rtr_bdcst_vld & (rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0] == rob_rcd_tb_entry_i))
				)
					rob_rcd_tb_vld[rob_rcd_tb_entry_i] <= # SIM_DELAY 
						// 断言: 不会出现写和退出同一ROB项的情况
						(~rob_clr) & 
						rob_luc_bdcst_vld & rob_rcd_tb_full_n & (rob_rcd_tb_wptr[clogb2(ROB_ENTRY_N-1):0] == rob_rcd_tb_entry_i);
			end
			
			always @(posedge aclk)
			begin
				if(
					(rob_luc_bdcst_vld & rob_rcd_tb_full_n & (rob_rcd_tb_wptr[clogb2(ROB_ENTRY_N-1):0] == rob_rcd_tb_entry_i)) | 
					on_rob_sng_cancel_vld[rob_rcd_tb_entry_i] | 
					on_rob_yngr_cancel_vld[rob_rcd_tb_entry_i] | 
					on_rob_sync_err_cancel_vld[rob_rcd_tb_entry_i]
				)
					rob_rcd_tb_cancel[rob_rcd_tb_entry_i] <= # SIM_DELAY 
						on_rob_sng_cancel_vld[rob_rcd_tb_entry_i] | 
						on_rob_yngr_cancel_vld[rob_rcd_tb_entry_i] | 
						on_rob_sync_err_cancel_vld[rob_rcd_tb_entry_i];
			end
		end
	endgenerate
	
	/** 执行单元结果监听 **/
	// 执行单元结果返回(数组)
	wire fu_res_vld_arr[0:LSN_FU_N-1]; // 有效标志
	wire[IBUS_TID_WIDTH-1:0] fu_res_tid_arr[0:LSN_FU_N-1]; // 指令ID
	wire[FU_RES_WIDTH-1:0] fu_res_data_arr[0:LSN_FU_N-1]; // 执行结果
	wire[FU_ERR_WIDTH-1:0] fu_res_err_arr[0:LSN_FU_N-1]; // 错误码
	// 每个ROB条目对执行单元的结果监听
	wire rob_entry_res_on_lsn[0:ROB_ENTRY_N-1]; // 得到执行结果(指示)
	wire rob_entry_res_vld_arr[0:ROB_ENTRY_N-1]; // 有效标志
	wire[IBUS_TID_WIDTH-1:0] rob_entry_res_tid_arr[0:ROB_ENTRY_N-1]; // 指令ID
	wire[FU_RES_WIDTH-1:0] rob_entry_res_data_arr[0:ROB_ENTRY_N-1]; // 执行结果
	wire[FU_ERR_WIDTH-1:0] rob_entry_res_err_arr[0:ROB_ENTRY_N-1]; // 错误码
	
	genvar fu_i;
	generate
		for(fu_i = 0;fu_i < LSN_FU_N;fu_i = fu_i + 1)
		begin:fu_res_lsn_blk
			assign fu_res_vld_arr[fu_i] = fu_res_vld[fu_i];
			assign fu_res_tid_arr[fu_i] = fu_res_tid[(fu_i+1)*IBUS_TID_WIDTH-1:fu_i*IBUS_TID_WIDTH];
			assign fu_res_data_arr[fu_i] = fu_res_data[(fu_i+1)*FU_RES_WIDTH-1:fu_i*FU_RES_WIDTH];
			assign fu_res_err_arr[fu_i] = fu_res_err[(fu_i+1)*FU_ERR_WIDTH-1:fu_i*FU_ERR_WIDTH];
		end
	endgenerate
	
	genvar rob_res_i;
	generate
		for(rob_res_i = 0;rob_res_i < ROB_ENTRY_N;rob_res_i = rob_res_i + 1)
		begin:rob_entry_res_blk
			assign rob_entry_res_on_lsn[rob_res_i] = 
				rob_entry_res_vld_arr[rob_res_i] & // 所监听的FU结果有效
				(rob_entry_res_tid_arr[rob_res_i] == rob_rcd_tb_tid[rob_res_i]) & // 所监听的FU指令ID匹配
				rob_rcd_tb_vld[rob_res_i] & (~rob_rcd_tb_saved[rob_res_i]); // 当前ROB项有效且未保存结果
			
			assign rob_entry_res_vld_arr[rob_res_i] = 
				fu_res_vld_arr[rob_rcd_tb_fuid[rob_res_i]];
			assign rob_entry_res_tid_arr[rob_res_i] = 
				fu_res_tid_arr[rob_rcd_tb_fuid[rob_res_i]];
			assign rob_entry_res_data_arr[rob_res_i] = 
				fu_res_data_arr[rob_rcd_tb_fuid[rob_res_i]];
			assign rob_entry_res_err_arr[rob_res_i] = 
				fu_res_err_arr[rob_rcd_tb_fuid[rob_res_i]];
			
			always @(posedge aclk)
			begin
				if(rob_entry_res_on_lsn[rob_res_i])
					rob_rcd_tb_fu_res[rob_res_i] <= # SIM_DELAY rob_entry_res_data_arr[rob_res_i];
			end
			
			always @(posedge aclk)
			begin
				if(
					// 发射1条指令
					(rob_luc_bdcst_vld & rob_rcd_tb_full_n & (rob_rcd_tb_wptr[clogb2(ROB_ENTRY_N-1):0] == rob_res_i)) | 
					// 发生LSU错误
					(
						rob_entry_res_on_lsn[rob_res_i] & rob_rcd_tb_is_ls_inst[rob_res_i] & 
						(fu_res_err_arr[LSU_FU_ID] != LSU_ERR_CODE_NORMAL)
					)
				)
					rob_rcd_tb_err[rob_res_i] <= # SIM_DELAY 
						// 断言: 不会出现同时写ROB项和得到这一项的执行结果(或者得知LSU返回的错误)的情况
						(
							rob_luc_bdcst_vld & rob_rcd_tb_full_n & 
							(rob_rcd_tb_wptr[clogb2(ROB_ENTRY_N-1):0] == rob_res_i)
						) ? 
							rob_luc_bdcst_err:
							(
								({3{fu_res_err_arr[LSU_FU_ID] == LSU_ERR_CODE_RD_ADDR_UNALIGNED}} & 
									LUC_INST_ERR_CODE_RD_DBUS_UNALIGNED) | 
								({3{fu_res_err_arr[LSU_FU_ID] == LSU_ERR_CODE_WT_ADDR_UNALIGNED}} & 
									LUC_INST_ERR_CODE_WT_DBUS_UNALIGNED) | 
								({3{fu_res_err_arr[LSU_FU_ID] == LSU_ERR_CODE_RD_FAILED}} & 
									LUC_INST_ERR_CODE_RD_DBUS_FAILED) | 
								({3{fu_res_err_arr[LSU_FU_ID] == LSU_ERR_CODE_WT_FAILED}} & 
									LUC_INST_ERR_CODE_WT_DBUS_FAILED)
							);
			end
			
			always @(posedge aclk)
			begin
				if(
					rob_clr | 
					(rob_luc_bdcst_vld & rob_rcd_tb_full_n & (rob_rcd_tb_wptr[clogb2(ROB_ENTRY_N-1):0] == rob_res_i)) | 
					rob_entry_res_on_lsn[rob_res_i]
				)
					rob_rcd_tb_saved[rob_res_i] <= # SIM_DELAY 
						// 断言: 不会出现同时写ROB项和得到这一项的执行结果的情况
						(~(
							rob_clr | 
							(rob_luc_bdcst_vld & rob_rcd_tb_full_n & (rob_rcd_tb_wptr[clogb2(ROB_ENTRY_N-1):0] == rob_res_i))
						));
			end
			
			always @(posedge aclk)
			begin
				if(s_bru_o_valid & (s_bru_o_tid == rob_rcd_tb_tid[rob_res_i])) // 所有指令都会经过BRU, 且BRU结果必定在(FU)执行结果之前得到
				begin
					rob_rcd_tb_pc[rob_res_i] <= # SIM_DELAY s_bru_o_pc;
					rob_rcd_tb_nxt_pc[rob_res_i] <= # SIM_DELAY s_bru_o_nxt_pc;
					rob_rcd_tb_b_inst_res[rob_res_i] <= # SIM_DELAY s_bru_o_b_inst_res;
					rob_rcd_tb_org_2bit_sat_cnt[rob_res_i] <= # SIM_DELAY s_bru_o_org_2bit_sat_cnt;
					rob_rcd_tb_bhr[rob_res_i] <= # SIM_DELAY s_bru_o_bhr;
				end
			end
		end
	endgenerate
	
	/** 逻辑寄存器位置表 **/
	reg[31:0] is_arct_reg_at_rob; // 逻辑寄存器位于ROB或旁路网络(标志组)
	reg[clogb2(ROB_ENTRY_N-1):0] arct_reg_rob_entry_i[0:31]; // 逻辑寄存器在ROB中的项编号
	
	genvar arct_reg_i;
	generate
		for(arct_reg_i = 0;arct_reg_i < 32;arct_reg_i = arct_reg_i + 1)
		begin:arct_reg_pos_rcd_blk
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					is_arct_reg_at_rob[arct_reg_i] <= 1'b0;
				else if(
					(arct_reg_i != 0) & 
					(
						rob_clr | 
						// 一旦向ROB记录了1条(不带同步异常的)指令, 那么这条指令所对应的Rd就位于ROB或旁路网络上
						(
							rob_luc_bdcst_vld & rob_rcd_tb_full_n & (rob_luc_bdcst_rd_id == arct_reg_i) & 
							(rob_luc_bdcst_err == LUC_INST_ERR_CODE_NORMAL)
						) | 
						// 当这个逻辑寄存器所绑定的ROB项退休时, 那么这个逻辑寄存器就位于Reg-File上
						(
							is_arct_reg_at_rob[arct_reg_i] & 
							rob_rtr_bdcst_vld & (rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0] == arct_reg_rob_entry_i[arct_reg_i])
						)
					)
				)
					is_arct_reg_at_rob[arct_reg_i] <= # SIM_DELAY 
						(~rob_clr) & (
							rob_luc_bdcst_vld & rob_rcd_tb_full_n & (rob_luc_bdcst_rd_id == arct_reg_i) & 
							(rob_luc_bdcst_err == LUC_INST_ERR_CODE_NORMAL)
						);
			end
			
			always @(posedge aclk)
			begin
				if(
					(arct_reg_i != 0) & 
					// 一旦向ROB记录了1条(不带同步异常的)指令, 那么就更新这条指令对应Rd所绑定的ROB项编号
					rob_luc_bdcst_vld & rob_rcd_tb_full_n & (rob_luc_bdcst_rd_id == arct_reg_i) & 
					(rob_luc_bdcst_err == LUC_INST_ERR_CODE_NORMAL)
				)
					arct_reg_rob_entry_i[arct_reg_i] <= # SIM_DELAY 
						rob_rcd_tb_wptr[clogb2(ROB_ENTRY_N-1):0];
			end
		end
	endgenerate
	
	/** 取操作数与RAW数据相关性检查 **/
	wire[clogb2(ROB_ENTRY_N-1):0] op1_rs1_rob_entry_i; // OP1(RS1)在ROB中的项编号
	wire[clogb2(ROB_ENTRY_N-1):0] op2_rs2_rob_entry_i; // OP2(RS2)在ROB中的项编号
	
	// "逻辑寄存器位置表"记录了每个逻辑寄存器是否在ROB或旁路网络中, 并给出了最新的ROB项编号, 利用这个表可以很容易地完成操作数读取
	assign op1_ftc_from_reg_file = ~is_arct_reg_at_rob[op1_ftc_rs1_id];
	assign op1_ftc_from_rob = is_arct_reg_at_rob[op1_ftc_rs1_id] & rob_rcd_tb_saved[op1_rs1_rob_entry_i];
	assign op1_ftc_from_byp = is_arct_reg_at_rob[op1_ftc_rs1_id] & (~rob_rcd_tb_saved[op1_rs1_rob_entry_i]);
	assign op1_ftc_fuid = rob_rcd_tb_fuid[op1_rs1_rob_entry_i];
	assign op1_ftc_tid = rob_rcd_tb_tid[op1_rs1_rob_entry_i];
	assign op1_ftc_rob_saved_data = rob_rcd_tb_fu_res[op1_rs1_rob_entry_i];
	
	assign op2_ftc_from_reg_file = ~is_arct_reg_at_rob[op2_ftc_rs2_id];
	assign op2_ftc_from_rob = is_arct_reg_at_rob[op2_ftc_rs2_id] & rob_rcd_tb_saved[op2_rs2_rob_entry_i];
	assign op2_ftc_from_byp = is_arct_reg_at_rob[op2_ftc_rs2_id] & (~rob_rcd_tb_saved[op2_rs2_rob_entry_i]);
	assign op2_ftc_fuid = rob_rcd_tb_fuid[op2_rs2_rob_entry_i];
	assign op2_ftc_tid = rob_rcd_tb_tid[op2_rs2_rob_entry_i];
	assign op2_ftc_rob_saved_data = rob_rcd_tb_fu_res[op2_rs2_rob_entry_i];
	
	assign op1_rs1_rob_entry_i = arct_reg_rob_entry_i[op1_ftc_rs1_id];
	assign op2_rs2_rob_entry_i = arct_reg_rob_entry_i[op2_ftc_rs2_id];
	
	/** LSU许可 **/
	/*
	说明: 
		当1条Load/Store指令成为ROB里最旧的指令时, 给出写存储器许可
		实际上, 只有访问存储器区域的Store指令才需要等待这个许可
	*/
	assign wr_mem_permitted_flag = 
		rob_rcd_tb_vld[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]] & rob_rcd_tb_is_ls_inst[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]];
	assign init_mem_bus_tr_store_inst_tid = 
		rob_rcd_tb_tid[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]];
	
	assign perph_access_permitted_flag = 
		rob_rcd_tb_vld[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]] & rob_rcd_tb_is_ls_inst[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]];
	assign init_perph_bus_tr_ls_inst_tid = 
		rob_rcd_tb_tid[rob_rcd_tb_rptr[clogb2(ROB_ENTRY_N-1):0]];
	
endmodule
