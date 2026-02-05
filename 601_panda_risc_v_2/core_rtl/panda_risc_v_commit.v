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
本模块: 交付单元

描述:
每clk最多从ROB退休1条指令

更新基于历史的分支预测器

处理调试/中断/异常请求:
	调试优先级 -> 来自调试器的复位释放后暂停请求 > 来自调试器的暂停请求 > 断点调试 > 单步调试
	中断/异常优先级 -> 异常 > ECALL指令 > 外部中断 > 软件中断 > 计时器中断

进入/退出调试、中断与异常时更新CSR

产生冲刷请求, 冲刷地址为以下中的1种: 
	(1)Debug ROM基地址
	(2)中断/异常向量表基地址
	(3)dpc状态寄存器定义的调试模式返回地址
	(4)mepc状态寄存器定义的中断/异常返回地址

注意：
调试模式下, 不能处理中断/异常
中断/异常模式下, 不能处理嵌套的异常

协议:
REQ/GRANT

作者: 陈家耀
日期: 2026/02/05
********************************************************************/


module panda_risc_v_commit #(
	parameter DEBUG_ROM_ADDR = 32'h0000_0600, // Debug ROM基地址
	parameter DEBUG_SUPPORTED = "true", // 是否需要支持Debug
	parameter integer FU_RES_WIDTH = 32, // 执行单元结果位宽(正整数)
	parameter integer GHR_WIDTH = 8, // 全局分支历史寄存器的位宽(<=16)
	parameter integer BHR_WIDTH = 9, // 局部分支历史寄存器(BHR)的位宽
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 交付单元给出的冲刷请求
	output wire cmt_flush_req, // 冲刷请求
	output wire[31:0] cmt_flush_addr, // 冲刷地址
	input wire cmt_flush_grant, // 冲刷许可
	
	// ROB与LSU清空控制
	output wire rob_clr, // 清空ROB(指示)
	output wire lsu_clr_wr_mem_buf, // 清空LSU写存储器缓存区
	output wire cancel_lsu_subseq_perph_access, // 取消LSU后续外设访问
	
	// 准备退休的ROB项
	input wire rob_prep_rtr_entry_vld, // 有效标志
	input wire rob_prep_rtr_entry_saved, // 结果已保存(标志)
	input wire[2:0] rob_prep_rtr_entry_err, // 错误码
	input wire rob_prep_rtr_entry_is_csr_rw_inst, // 是否CSR读写指令
	input wire[2:0] rob_prep_rtr_entry_spec_inst_type, // 特殊指令类型
	input wire rob_prep_rtr_entry_cancel, // 取消标志
	input wire[FU_RES_WIDTH-1:0] rob_prep_rtr_entry_fu_res, // 保存的执行结果
	input wire[31:0] rob_prep_rtr_entry_pc, // 指令对应的PC
	input wire[31:0] rob_prep_rtr_entry_nxt_pc, // 指令对应的下一有效PC
	input wire[1:0] rob_prep_rtr_entry_b_inst_res, // B指令执行结果
	input wire[1:0] rob_prep_rtr_entry_org_2bit_sat_cnt, // 原来的2bit饱和计数器
	input wire[15:0] rob_prep_rtr_entry_bhr, // BHR
	input wire rob_prep_rtr_is_b_inst, // 是否B指令
	
	// 退休阶段ROB记录广播
	output wire rob_rtr_bdcst_vld, // 广播有效
	output wire rob_rtr_bdcst_excpt_proc_grant, // 异常处理许可
	
	// 性能监测
	output wire inst_retire_cnt_en, // 退休指令计数器的计数使能
	
	// 中断/异常处理
	// [中断使能]
	input wire mstatus_mie_v, // mstatus状态寄存器MIE域
	input wire mie_msie_v, // mie状态寄存器MSIE域
	input wire mie_mtie_v, // mie状态寄存器MTIE域
	input wire mie_meie_v, // mie状态寄存器MEIE域
	// [中断请求]
	// 注意: 中断请求保持有效直到在中断服务函数中清零!
	input wire sw_itr_req_i, // 输入的软件中断请求
	input wire tmr_itr_req_i, // 输入的计时器中断请求
	input wire ext_itr_req_i, // 输入的外部中断请求
	// [进入中断/异常]
	output wire itr_expt_enter, // 进入中断/异常(指示)
	output wire itr_expt_is_intr, // 是否中断
	output wire[7:0] itr_expt_cause, // 中断/异常原因
	input wire[31:0] itr_expt_vec_baseaddr, // 中断/异常向量表基地址
	output wire[31:0] itr_expt_ret_addr, // 中断/异常返回地址
	output wire[31:0] itr_expt_val, // 中断/异常值(附加信息)
	// [退出中断/异常]
	output wire itr_expt_ret, // 退出中断/异常(指示)
	input wire[31:0] mepc_ret_addr, // mepc状态寄存器定义的中断/异常返回地址
	// [中断/异常状态]
	output wire in_trap, // 正在处理中断/异常(标志)
	
	// 调试处理
	// [进入调试]
	output wire dbg_mode_enter, // 进入调试模式(指示)
	output wire[2:0] dbg_mode_cause, // 进入调试模式的原因
	output wire[31:0] dbg_mode_ret_addr, // 调试模式返回地址
	// [退出调试]
	output wire dbg_mode_ret, // 退出调试模式(指示)
	input wire[31:0] dpc_ret_addr, // dpc状态寄存器定义的调试模式返回地址
	// [调试状态]
	input wire dbg_halt_req, // 来自调试器的暂停请求
	input wire dbg_halt_on_reset_req, // 来自调试器的复位释放后暂停请求
	input wire dcsr_ebreakm_v, // dcsr状态寄存器EBREAKM域
	input wire dcsr_step_v, // dcsr状态寄存器STEP域
	output wire in_dbg_mode, // 当前处于调试模式(标志)
	
	// 基于历史的分支预测
	// [更新退休GHR]
	output wire glb_brc_prdt_on_upd_retired_ghr, // 退休GHR更新指示
	output wire glb_brc_prdt_retired_ghr_shift_in, // 退休GHR移位输入
	// [更新PHT]
	output wire glb_brc_prdt_upd_i_req, // 更新请求
	output wire[31:0] glb_brc_prdt_upd_i_pc, // 待更新项的PC
	output wire[((GHR_WIDTH <= 2) ? 2:GHR_WIDTH)-1:0] glb_brc_prdt_upd_i_ghr, // 待更新项的GHR
	output wire[((BHR_WIDTH <= 2) ? 2:BHR_WIDTH)-1:0] glb_brc_prdt_upd_i_bhr, // 待更新项的BHR
	output wire[1:0] glb_brc_prdt_upd_i_2bit_sat_cnt, // 新的2bit饱和计数器
	output wire glb_brc_prdt_upd_i_brc_taken, // 待更新项的实际分支跳转方向
	// [GHR值]
	input wire[((GHR_WIDTH <= 2) ? 2:GHR_WIDTH)-1:0] glb_brc_prdt_retired_ghr_o // 当前的退休GHR
);
	
	/** 常量 **/
	// 指令错误码
	localparam INST_ERR_CODE_NORMAL = 3'b000; // 正常
	localparam INST_ERR_CODE_ILLEGAL = 3'b001; // 非法指令
	localparam INST_ERR_CODE_PC_UNALIGNED = 3'b010; // 指令地址非对齐
	localparam INST_ERR_CODE_IMEM_ACCESS_FAILED = 3'b011; // 指令总线访问失败
	localparam INST_ERR_CODE_RD_DBUS_FAILED = 3'b100; // 读存储映射失败
	localparam INST_ERR_CODE_WT_DBUS_FAILED = 3'b101; // 写存储映射失败
	localparam INST_ERR_CODE_RD_DBUS_UNALIGNED = 3'b110; // 读存储映射地址非对齐
	localparam INST_ERR_CODE_WT_DBUS_UNALIGNED = 3'b111; // 写存储映射地址非对齐
	// 进入调试模式的原因
	localparam DBG_CAUSE_CODE_EBREAK = 3'd1; // 执行了1条EBREAK指令
	localparam DBG_CAUSE_CODE_HALTREQ = 3'd3; // 调试器暂停请求
	localparam DBG_CAUSE_CODE_STEP = 3'd4; // 单步调试
	localparam DBG_CAUSE_CODE_RST_HALTREQ = 3'd5; // 复位释放后暂停请求
	// 中断/异常原因
	localparam INTR_CODE_M_SW = 8'd3; // 机器模式软件中断
	localparam INTR_CODE_M_TMR = 8'd7; // 机器模式计时器中断
	localparam INTR_CODE_M_EXT = 8'd11; // 机器模式外部中断
	localparam EXPT_CODE_INST_ADDR_MISALIGNED = 8'd0; // 指令地址非对齐
	localparam EXPT_CODE_INST_ACCESS_FAULT = 8'd1; // 指令总线访问错误
	localparam EXPT_CODE_ILLEGAL_INST = 8'd2; // 非法指令
	localparam EXPT_CODE_LOAD_ADDR_MISALIGNED = 8'd4; // 读存储映射地址非对齐
	localparam EXPT_CODE_LOAD_ACCESS_FAULT = 8'd5; // 读存储映射总线错误
	localparam EXPT_CODE_STORE_ADDR_MISALIGNED = 8'd6; // 写存储映射地址非对齐
	localparam EXPT_CODE_STORE_ACCESS_FAULT = 8'd7; // 写存储映射总线错误
	localparam EXPT_CODE_ENV_CALL_FROM_M = 8'd11; // 机器模式环境调用
	// 特殊指令类型
	localparam SPEC_INST_TYPE_NONE = 3'b000; // 非特殊指令
	localparam SPEC_INST_TYPE_ECALL = 3'b100; // ECALL指令
	localparam SPEC_INST_TYPE_EBREAK = 3'b101; // EBREAK指令
	localparam SPEC_INST_TYPE_MRET = 3'b110; // MRET指令
	localparam SPEC_INST_TYPE_DRET = 3'b111; // DRET指令
	// B指令执行结果
	localparam B_INST_RES_NONE = 2'b00; // 不是B指令
	localparam B_INST_RES_TAKEN = 2'b01; // B指令跳转
	localparam B_INST_RES_NOT_TAKEN = 2'b10; // B指令不跳
	
	/** 调试/中断/异常仲裁 **/
	wire dbg_req_global; // 当前有导致进入调试模式的事件(标志)
	wire trap_req_global; // 全局的中断/异常请求
	wire dbg_grant_global; // 许可进入调试模式
	wire trap_grant_global; // 许可处理中断/异常
	
	/** 中断/异常处理 **/
	reg trap_proc; // 当前正在处理中断/异常
	wire ecall_intr_req; // ECALL指令中断请求
	wire sw_intr_req; // 软件中断请求
	wire tmr_intr_req; // 计时器中断请求
	wire ext_intr_req; // 外部中断请求
	wire excpt_proc_req; // 异常处理请求
	wire trap_return_req; // 退出中断/异常请求
	wire ecall_intr_grant; // ECALL指令中断许可
	wire sw_intr_grant; // 软件中断许可
	wire tmr_intr_grant; // 计时器中断许可
	wire ext_intr_grant; // 外部中断许可
	wire excpt_proc_grant; // 异常处理许可
	
	assign itr_expt_enter = 
		trap_grant_global & // 许可处理中断/异常
		rob_rtr_bdcst_vld; // 退休1条指令
	assign itr_expt_is_intr = sw_intr_grant | tmr_intr_grant | ext_intr_grant;
	assign itr_expt_cause = 
		// 机器模式软件中断
		({8{sw_intr_grant}} & INTR_CODE_M_SW) | 
		// 机器模式计时器中断
		({8{tmr_intr_grant}} & INTR_CODE_M_TMR) | 
		// 机器模式外部中断
		({8{ext_intr_grant}} & INTR_CODE_M_EXT) | 
		// 指令地址非对齐
		({8{excpt_proc_grant & (rob_prep_rtr_entry_err == INST_ERR_CODE_PC_UNALIGNED)}} & EXPT_CODE_INST_ADDR_MISALIGNED) | 
		// 指令总线访问错误
		({8{excpt_proc_grant & (rob_prep_rtr_entry_err == INST_ERR_CODE_IMEM_ACCESS_FAILED)}} & EXPT_CODE_INST_ACCESS_FAULT) | 
		// 非法指令
		({8{excpt_proc_grant & (rob_prep_rtr_entry_err == INST_ERR_CODE_ILLEGAL)}} & EXPT_CODE_ILLEGAL_INST) | 
		// 读存储映射地址非对齐
		({8{excpt_proc_grant & (rob_prep_rtr_entry_err == INST_ERR_CODE_RD_DBUS_UNALIGNED)}} & 
			EXPT_CODE_LOAD_ADDR_MISALIGNED) | 
		// 读存储映射总线错误
		({8{excpt_proc_grant & (rob_prep_rtr_entry_err == INST_ERR_CODE_RD_DBUS_FAILED)}} & 
			EXPT_CODE_LOAD_ACCESS_FAULT) | 
		// 写存储映射地址非对齐
		({8{excpt_proc_grant & (rob_prep_rtr_entry_err == INST_ERR_CODE_WT_DBUS_UNALIGNED)}} & 
			EXPT_CODE_STORE_ADDR_MISALIGNED) | 
		// 写存储映射总线错误
		({8{excpt_proc_grant & (rob_prep_rtr_entry_err == INST_ERR_CODE_WT_DBUS_FAILED)}} & 
			EXPT_CODE_STORE_ACCESS_FAULT) | 
		// 机器模式环境调用
		({8{ecall_intr_grant}} & EXPT_CODE_ENV_CALL_FROM_M);
	assign itr_expt_ret_addr = 
		// 异常处理返回到进入异常时的指令地址, ECALL指令/中断处理返回到进入中断时的下一有效指令地址
		excpt_proc_grant ? 
			rob_prep_rtr_entry_pc:
			rob_prep_rtr_entry_nxt_pc;
	assign itr_expt_val = 
		// 发生LSU异常时, 保存访存地址; 发生非法指令导致的异常时, 保存取到的指令
		({32{
			(rob_prep_rtr_entry_err == INST_ERR_CODE_RD_DBUS_FAILED) | 
			(rob_prep_rtr_entry_err == INST_ERR_CODE_WT_DBUS_FAILED) | 
			(rob_prep_rtr_entry_err == INST_ERR_CODE_RD_DBUS_UNALIGNED) | 
			(rob_prep_rtr_entry_err == INST_ERR_CODE_WT_DBUS_UNALIGNED) | 
			(rob_prep_rtr_entry_err == INST_ERR_CODE_ILLEGAL)
		}} & rob_prep_rtr_entry_fu_res[31:0]) | 
		// 发生指令地址非对齐或指令总线访问失败导致的异常时, 保存指令对应的PC
		({32{
			(rob_prep_rtr_entry_err == INST_ERR_CODE_PC_UNALIGNED) | 
			(rob_prep_rtr_entry_err == INST_ERR_CODE_IMEM_ACCESS_FAILED)
		}} & rob_prep_rtr_entry_pc);
	
	assign itr_expt_ret = 
		trap_return_req & // 退出中断/异常请求有效
		rob_rtr_bdcst_vld; // 退休1条指令
	
	assign in_trap = trap_proc;
	
	assign excpt_proc_req = 
		// 待交付的指令未被取消、存在异常
		rob_prep_rtr_entry_vld & rob_prep_rtr_entry_saved & (~rob_prep_rtr_entry_cancel) & 
		(rob_prep_rtr_entry_err != INST_ERR_CODE_NORMAL) & 
		// 当前不处于调试模式, 也不处于中断/异常模式
		(~(in_dbg_mode | trap_proc));
	assign ecall_intr_req = 
		// 待交付的指令未被取消、没有异常
		rob_prep_rtr_entry_vld & rob_prep_rtr_entry_saved & (~rob_prep_rtr_entry_cancel) & 
		(rob_prep_rtr_entry_err == INST_ERR_CODE_NORMAL) & 
		// 待交付的指令是ECALL指令
		(rob_prep_rtr_entry_spec_inst_type == SPEC_INST_TYPE_ECALL) & 
		// 当前不处于调试模式, 也不处于中断/异常模式
		(~(in_dbg_mode | trap_proc));
	
	// 说明: 简单起见, 不会将软件/计时器/外部中断绑定在1条CSR读写指令上, 这是因为这条CSR读写指令可能会修改中断/异常相关的CSR
	assign sw_intr_req = 
		// 待交付的指令未被取消、没有异常
		rob_prep_rtr_entry_vld & rob_prep_rtr_entry_saved & (~rob_prep_rtr_entry_cancel) & 
		(rob_prep_rtr_entry_err == INST_ERR_CODE_NORMAL) & 
		// 待交付的指令不是CSR读写指令
		(~rob_prep_rtr_entry_is_csr_rw_inst) & 
		// 全局中断使能, 软件中断使能, 输入的软件中断请求有效
		mstatus_mie_v & mie_msie_v & sw_itr_req_i & 
		// 当前不处于调试模式, 也不处于中断/异常模式
		(~(in_dbg_mode | trap_proc));
	assign tmr_intr_req = 
		// 待交付的指令未被取消、没有异常
		rob_prep_rtr_entry_vld & rob_prep_rtr_entry_saved & (~rob_prep_rtr_entry_cancel) & 
		(rob_prep_rtr_entry_err == INST_ERR_CODE_NORMAL) & 
		// 待交付的指令不是CSR读写指令
		(~rob_prep_rtr_entry_is_csr_rw_inst) & 
		// 全局中断使能, 计时器中断使能, 输入的计时器中断请求有效
		mstatus_mie_v & mie_mtie_v & tmr_itr_req_i & 
		// 当前不处于调试模式, 也不处于中断/异常模式
		(~(in_dbg_mode | trap_proc));
	assign ext_intr_req = 
		// 待交付的指令未被取消、没有异常
		rob_prep_rtr_entry_vld & rob_prep_rtr_entry_saved & (~rob_prep_rtr_entry_cancel) & 
		(rob_prep_rtr_entry_err == INST_ERR_CODE_NORMAL) & 
		// 待交付的指令不是CSR读写指令
		(~rob_prep_rtr_entry_is_csr_rw_inst) & 
		// 全局中断使能, 外部中断使能, 输入的外部中断请求有效
		mstatus_mie_v & mie_meie_v & ext_itr_req_i & 
		// 当前不处于调试模式, 也不处于中断/异常模式
		(~(in_dbg_mode | trap_proc));
	
	assign trap_return_req = 
		// 待交付的指令未被取消、没有异常
		rob_prep_rtr_entry_vld & rob_prep_rtr_entry_saved & (~rob_prep_rtr_entry_cancel) & 
		(rob_prep_rtr_entry_err == INST_ERR_CODE_NORMAL) & 
		// 待交付的指令是MRET指令
		(rob_prep_rtr_entry_spec_inst_type == SPEC_INST_TYPE_MRET) & 
		// 当前不处于调试模式, 但处于中断/异常模式
		(~in_dbg_mode) & trap_proc;
	
	// 中断/异常优先级: 异常 > ECALL指令 > 外部中断 > 软件中断 > 计时器中断
	assign ecall_intr_grant = (~excpt_proc_req) & ecall_intr_req;
	assign sw_intr_grant = (~excpt_proc_req) & (~ecall_intr_req) & (~ext_intr_req) & sw_intr_req;
	assign tmr_intr_grant = (~excpt_proc_req) & (~ecall_intr_req) & (~ext_intr_req) & (~sw_intr_req) & tmr_intr_req;
	assign ext_intr_grant = (~excpt_proc_req) & (~ecall_intr_req) & ext_intr_req;
	assign excpt_proc_grant = excpt_proc_req;
	
	// 当前正在处理中断/异常
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			trap_proc <= 1'b0;
		else if(itr_expt_enter | itr_expt_ret)
			// 断言: 进入/退出中断与异常模式(指示)不可能同时有效
			trap_proc <= # SIM_DELAY itr_expt_enter;
	end
	
	/** 调试模式 **/
	reg in_dbg_mode_r; // 当前处于调试模式(标志)
	reg first_inst_after_dret; // 退出调试模式后的第1条指令(标志)
	reg first_inst_after_rst; // 复位释放后的第1条指令(标志)
	wire dbg_req_halt; // 有效的调试器暂停请求
	wire dbg_req_halt_on_reset; // 有效的调试器复位释放后暂停请求
	wire dbg_req_ebreakm; // 有效的机器模式EBREAK调试请求
	wire dbg_req_step; // 有效的单步调试请求
	wire dbg_req_return; // 退出调试模式请求
	wire dbg_grant_halt; // 许可的调试器暂停请求
	wire dbg_grant_halt_on_reset; // 许可的调试器复位释放后暂停请求
	wire dbg_grant_ebreakm; // 许可的机器模式EBREAK调试请求
	wire dbg_grant_step; // 许可的单步调试请求
	
	assign dbg_mode_enter = 
		(DEBUG_SUPPORTED == "true") & dbg_grant_global & // 需要支持Debug且许可进入调试模式
		rob_rtr_bdcst_vld; // 退休1条指令
	assign dbg_mode_cause = 
		({3{dbg_grant_halt}} & DBG_CAUSE_CODE_HALTREQ) | 
		({3{dbg_grant_halt_on_reset}} & DBG_CAUSE_CODE_RST_HALTREQ) | 
		({3{dbg_grant_ebreakm}} & DBG_CAUSE_CODE_EBREAK) | 
		({3{dbg_grant_step}} & DBG_CAUSE_CODE_STEP);
	/*
	说明:
		"EBREAK指令导致的调试请求"返回到进入调试模式时的指令地址
		其余情况返回到进入调试模式时的下一有效指令地址或"中断/异常向量表基地址"
	*/
	assign dbg_mode_ret_addr = 
		dbg_grant_ebreakm ? 
			rob_prep_rtr_entry_pc:
			(
				(excpt_proc_req | ecall_intr_req) ? 
					itr_expt_vec_baseaddr:
					rob_prep_rtr_entry_nxt_pc
			);
	
	assign dbg_mode_ret = 
		(DEBUG_SUPPORTED == "true") & dbg_req_return & // 需要支持Debug且退出调试模式请求有效
		rob_rtr_bdcst_vld; // 退休1条指令
	
	assign in_dbg_mode = (DEBUG_SUPPORTED == "true") & in_dbg_mode_r;
	
	assign dbg_req_global = 
		(DEBUG_SUPPORTED == "true") & 
		(dbg_req_halt | dbg_req_halt_on_reset | dbg_req_ebreakm | dbg_req_step);
	assign trap_req_global = 
		ecall_intr_req | sw_intr_req | tmr_intr_req | ext_intr_req | excpt_proc_req;
	assign dbg_grant_global = 
		dbg_req_global;
	assign trap_grant_global = 
		trap_req_global & // 全局中断/异常请求有效
		(
			(~dbg_req_global) | // 全局调试请求无效
			(
				/*
				对于除"EBREAK指令导致的调试请求"以外的其他调试请求, 若当前存在"异常处理请求"或"ECALL指令中断请求",
					则在进入调试模式的同时进入中断/异常模式
				*/
				(~dbg_grant_ebreakm) & (excpt_proc_req | ecall_intr_req)
			)
		);
	
	/*
	说明: 
		"来自调试器的暂停请求"、"来自调试器的复位释放后暂停请求"和"单步调试请求"没有限制待交付的指令无异常或是ECALL指令,
			因此可能会返回到"中断/异常向量表基地址"
		"EBREAK指令导致的调试请求"要求待交付的指令不能带有异常
	*/
	assign dbg_req_halt = 
		// 需要支持Debug
		(DEBUG_SUPPORTED == "true") & 
		// 待交付的指令未被取消
		rob_prep_rtr_entry_vld & rob_prep_rtr_entry_saved & (~rob_prep_rtr_entry_cancel) & 
		// 来自调试器的暂停请求有效
		dbg_halt_req & 
		// 当前不处于调试模式
		(~in_dbg_mode);
	assign dbg_req_halt_on_reset = 
		// 需要支持Debug
		(DEBUG_SUPPORTED == "true") & 
		// 待交付的指令未被取消
		rob_prep_rtr_entry_vld & rob_prep_rtr_entry_saved & (~rob_prep_rtr_entry_cancel) & 
		// 当前是复位释放后的第1条待交付指令, 来自调试器的复位释放后暂停请求有效
		first_inst_after_rst & dbg_halt_on_reset_req & 
		// 当前不处于调试模式
		(~in_dbg_mode);
	assign dbg_req_ebreakm = 
		// 需要支持Debug
		(DEBUG_SUPPORTED == "true") & 
		// 待交付的指令未被取消、没有异常
		rob_prep_rtr_entry_vld & rob_prep_rtr_entry_saved & (~rob_prep_rtr_entry_cancel) & 
		(rob_prep_rtr_entry_err == INST_ERR_CODE_NORMAL) & 
		// 待交付的指令是EBREAK指令
		(rob_prep_rtr_entry_spec_inst_type == SPEC_INST_TYPE_EBREAK) & 
		// dcsr状态寄存器EBREAKM域 = 1
		dcsr_ebreakm_v & 
		// 当前不处于调试模式
		(~in_dbg_mode);
	assign dbg_req_step = 
		// 需要支持Debug
		(DEBUG_SUPPORTED == "true") & 
		// 待交付的指令未被取消
		rob_prep_rtr_entry_vld & rob_prep_rtr_entry_saved & (~rob_prep_rtr_entry_cancel) & 
		// dcsr状态寄存器STEP域 = 1
		dcsr_step_v & 
		// 当前是退出调试模式后的第1条指令
		first_inst_after_dret;
	
	assign dbg_req_return = 
		// 需要支持Debug
		(DEBUG_SUPPORTED == "true") & 
		// 待交付的指令未被取消、没有异常
		rob_prep_rtr_entry_vld & rob_prep_rtr_entry_saved & (~rob_prep_rtr_entry_cancel) & 
		(rob_prep_rtr_entry_err == INST_ERR_CODE_NORMAL) & 
		// 待交付的指令是DRET指令
		(rob_prep_rtr_entry_spec_inst_type == SPEC_INST_TYPE_DRET) & 
		// 当前处于调试模式
		in_dbg_mode;
	
	// 各种导致进入调试模式的事件的优先级: resethaltreq > haltreq > ebreak > step
	assign dbg_grant_halt = (~dbg_req_halt_on_reset) & dbg_req_halt;
	assign dbg_grant_halt_on_reset = dbg_req_halt_on_reset;
	assign dbg_grant_ebreakm = (~dbg_req_halt_on_reset) & (~dbg_req_halt) & dbg_req_ebreakm;
	assign dbg_grant_step = (~dbg_req_halt_on_reset) & (~dbg_req_halt) & (~dbg_req_ebreakm) & dbg_req_step;
	
	// 当前处于调试模式(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			in_dbg_mode_r <= 1'b0;
		else if(dbg_mode_enter | dbg_mode_ret)
			// 断言: 进入/退出调试模式(指示)不可能同时有效
			in_dbg_mode_r <= # SIM_DELAY dbg_mode_enter;
	end
	
	// 退出调试模式后的第1条指令(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			first_inst_after_dret <= 1'b0;
		else if(rob_rtr_bdcst_vld)
			first_inst_after_dret <= # SIM_DELAY dbg_mode_ret;
	end
	
	// 复位释放后的第1条指令(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			first_inst_after_rst <= 1'b1;
		else if(first_inst_after_rst)
			first_inst_after_rst <= # SIM_DELAY ~rob_rtr_bdcst_vld;
	end
	
	/** 产生冲刷请求 **/
	wire need_flush; // 需要冲刷(标志)
	wire[31:0] flush_addr_cur; // 当前的冲刷地址
	reg flush_pending; // 冲刷等待(标志)
	reg[31:0] flush_addr_saved; // 保存的冲刷地址
	
	// 说明: 开始冲刷(指示)有效后的下1个clk才冲刷
	assign cmt_flush_req = flush_pending;
	assign cmt_flush_addr = flush_addr_saved;
	
	assign rob_clr = flush_pending;
	assign lsu_clr_wr_mem_buf = flush_pending;
	assign cancel_lsu_subseq_perph_access = flush_pending;
	
	assign rob_rtr_bdcst_vld = 
		rob_prep_rtr_entry_vld & (
			rob_prep_rtr_entry_cancel | // 待交付指令已被取消, 那么直接退休即可
			(rob_prep_rtr_entry_saved & (~flush_pending)) // 未取消的指令需要等到没有处理中的冲刷且结果已保存时再退休
		);
	assign rob_rtr_bdcst_excpt_proc_grant = excpt_proc_grant;
	
	assign inst_retire_cnt_en = 
		rob_rtr_bdcst_vld & (~rob_prep_rtr_entry_cancel); // 退休的是1条未取消的指令
	
	assign need_flush = dbg_req_global | trap_req_global | dbg_req_return | trap_return_req;
	assign flush_addr_cur = 
		dbg_grant_global ? 
			DEBUG_ROM_ADDR: // Debug ROM基地址
			(
				trap_grant_global ? 
					itr_expt_vec_baseaddr: // 中断/异常向量表基地址
					(
						dbg_req_return ? 
							dpc_ret_addr: // dpc状态寄存器定义的调试模式返回地址
							mepc_ret_addr // mepc状态寄存器定义的中断/异常返回地址
					)
			);
	
	// 冲刷等待(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			flush_pending <= 1'b0;
		else
			flush_pending <= # SIM_DELAY 
				flush_pending ? 
					(~cmt_flush_grant):
					need_flush;
	end
	
	// 保存的冲刷地址
	always @(posedge aclk)
	begin
		if((~flush_pending) & need_flush)
			flush_addr_saved <= # SIM_DELAY flush_addr_cur;
	end
	
	/** 更新基于历史的分支预测器 **/
	assign glb_brc_prdt_on_upd_retired_ghr = 
		// 退休1条未被取消、没有异常的指令
		rob_rtr_bdcst_vld & (~rob_prep_rtr_entry_cancel) & (rob_prep_rtr_entry_err == INST_ERR_CODE_NORMAL) & 
		// 这条指令是B指令
		rob_prep_rtr_is_b_inst;
	assign glb_brc_prdt_retired_ghr_shift_in = 
		rob_prep_rtr_entry_b_inst_res == B_INST_RES_TAKEN;
	
	assign glb_brc_prdt_upd_i_req = 
		// 退休1条未被取消、没有异常的指令
		rob_rtr_bdcst_vld & (~rob_prep_rtr_entry_cancel) & (rob_prep_rtr_entry_err == INST_ERR_CODE_NORMAL) & 
		// 这条指令是B指令
		rob_prep_rtr_is_b_inst;
	assign glb_brc_prdt_upd_i_pc = 
		rob_prep_rtr_entry_pc;
	assign glb_brc_prdt_upd_i_ghr = 
		glb_brc_prdt_retired_ghr_o;
	assign glb_brc_prdt_upd_i_bhr = 
		rob_prep_rtr_entry_bhr;
	assign glb_brc_prdt_upd_i_2bit_sat_cnt = 
		/*
		(rob_prep_rtr_entry_b_inst_res == B_INST_RES_TAKEN) ? 
			(
				(rob_prep_rtr_entry_org_2bit_sat_cnt == 2'b11) ? 
					2'b11:
					(rob_prep_rtr_entry_org_2bit_sat_cnt + 1'b1)
			):
			(
				(rob_prep_rtr_entry_org_2bit_sat_cnt == 2'b00) ? 
					2'b00:
					(rob_prep_rtr_entry_org_2bit_sat_cnt - 1'b1)
			)
		*/
		(rob_prep_rtr_entry_org_2bit_sat_cnt == {2{rob_prep_rtr_entry_b_inst_res == B_INST_RES_TAKEN}}) ? 
			{2{rob_prep_rtr_entry_b_inst_res == B_INST_RES_TAKEN}}:
			(rob_prep_rtr_entry_org_2bit_sat_cnt + {rob_prep_rtr_entry_b_inst_res != B_INST_RES_TAKEN, 1'b1});
	assign glb_brc_prdt_upd_i_brc_taken = 
		rob_prep_rtr_entry_b_inst_res == B_INST_RES_TAKEN;
	
endmodule
