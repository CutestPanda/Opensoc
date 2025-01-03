`timescale 1ns / 1ps
/********************************************************************
本模块: 交付单元

描述:
进行分支确认并处理中断/异常, 产生冲刷请求, 完成指令的交付(确认/取消)

注意：
每当CPU进入中断/异常时, 全局中断使能自动关闭, 因此不支持中断嵌套
当CPU进入中断/异常后, 若产生新的同步异常, CPU无法正确处理(可能导致错误)

只有同步异常的返回地址为PC, 其余中断/异常的返回地址均为PC + 4

分支预测失败导致的重新跳转具有最高的优先级, 其次才是中断/异常
中断/异常优先级: 外部中断 > 软件中断 > 计时器中断 > 来自LSU的异常 > 同步异常

ECALL/同步异常可能会被中断请求/LSU异常请求覆盖而得不到处理, 且在返回时这条ECALL/带有同步异常的指令会被跳过

考虑增加1个异常指令缓存以避免ECALL/同步异常被覆盖???

协议:
无

作者: 陈家耀
日期: 2025/01/03
********************************************************************/


module panda_risc_v_commit #(
    parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// 中断使能
	input wire mstatus_mie_v, // mstatus状态寄存器MIE域
	input wire mie_msie_v, // mie状态寄存器MSIE域
	input wire mie_mtie_v, // mie状态寄存器MTIE域
	input wire mie_meie_v, // mie状态寄存器MEIE域
	
	// 待交付的指令
	input wire[31:0] s_pst_inst, // 取到的指令(仅对非法指令可用)
	input wire[2:0] s_pst_err_code, // 指令的错误类型(3'b000 -> 正常, 3'b001 -> 非法指令, 
	                                //     3'b010 -> 指令地址非对齐, 3'b011 -> 指令总线访问失败, 
									//     3'b110 -> 读存储映射地址非对齐, 3'b111 -> 写存储映射地址非对齐)
	input wire[31:0] s_pst_pc_of_inst, // 指令对应的PC
	input wire s_pst_is_b_inst, // 是否B指令
	input wire s_pst_is_ecall_inst, // 是否ECALL指令
	input wire s_pst_is_mret_inst, // 是否MRET指令
	input wire[31:0] s_pst_brc_pc_upd, // 分支预测失败时修正的PC(仅在B指令下有效)
	input wire s_pst_prdt_jump, // 是否预测跳转
	input wire s_pst_rd_vld, // 是否需要写RD
	input wire s_pst_is_long_inst, // 是否长指令(L/S, 乘除法)
	input wire s_pst_valid,
	output wire s_pst_ready,
	
	// 来自LSU的异常
	input wire[31:0] s_lsu_expt_ls_addr, // 访存地址
	input wire s_lsu_expt_err, // 错误类型(1'b0 -> 读存储映射总线错误, 1'b1 -> 写存储映射总线错误)
	input wire s_lsu_expt_valid,
	output wire s_lsu_expt_ready,
	
	// 交付结果
	output wire m_pst_inst_cmt, // 指令是否被确认
	output wire m_pst_wb_imdt, // 本指令是否需要立刻写回
	output wire m_pst_valid,
	input wire m_pst_ready,
	
	// 访存地址生成
	input wire[31:0] ls_addr, // 访存地址(仅对L/S指令可用)
	
	// 分支确认
	input wire cfr_jump, // 是否确认跳转(仅对B指令可用)
	
	// 中断请求
	// 注意: 中断请求保持有效直到中断清零!
	input wire sw_itr_req, // 软件中断请求
	input wire tmr_itr_req, // 计时器中断请求
	input wire ext_itr_req, // 外部中断请求
	
	// 进入中断/异常处理
	output wire itr_expt_enter, // 进入中断/异常(指示)
	output wire itr_expt_is_intr, // 是否中断
	output wire[7:0] itr_expt_cause, // 中断/异常原因
	input wire[31:0] itr_expt_vec_baseaddr, // 中断/异常向量表基地址
	output wire[31:0] itr_expt_ret_addr, // 中断/异常返回地址
	output wire[31:0] itr_expt_val, // 中断/异常值(附加信息)
	
	// 退出中断/异常处理
	output wire itr_expt_ret, // 退出中断/异常(指示)
	input wire[31:0] mepc_ret_addr, // mepc状态寄存器定义的中断/异常返回地址
	
	// 冲刷控制
	output wire flush_req, // 冲刷请求
	input wire flush_ack, // 冲刷应答
	output wire[31:0] flush_addr // 冲刷地址
);
	
	/** 常量 **/
	// 待交付指令错误类型
	localparam CMT_INST_ERR_CODE_NORMAL = 3'b000; // 正常
	localparam CMT_INST_ERR_CODE_ILLEGAL = 3'b001; // 非法指令
	localparam CMT_INST_ERR_CODE_PC_UNALIGNED = 3'b010; // 指令地址非对齐
	localparam CMT_INST_ERR_CODE_IMEM_ACCESS_FAILED = 3'b011; // 指令总线访问失败
	localparam CMT_INST_ERR_CODE_RD_DBUS_UNALIGNED = 3'b110; // 读存储映射地址非对齐
	localparam CMT_INST_ERR_CODE_WT_DBUS_UNALIGNED = 3'b111; // 写存储映射地址非对齐
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
	// LSU错误类型
	localparam LSU_LOAD_ACCESS_FAULT = 1'b0; // 读存储映射总线错误
	localparam LSU_STORE_ACCESS_FAULT = 1'b1; // 写存储映射总线错误
	
	/** 分支确认 **/
	wire brc_prdt_failed; // 分支预测失败(标志)
	
	assign brc_prdt_failed = 
		s_pst_valid & // 当前有待交付的指令
		(~(s_pst_err_code[0] | s_pst_err_code[1])) & // 待交付指令没有异常
		s_pst_is_b_inst & // 待交付指令是B指令
		(s_pst_prdt_jump ^ cfr_jump); // 预测结果与实际不符
	
	/** 中断/异常处理 **/
	// 有效的中断/异常请求
	wire sw_itr_req_vld; // 有效的软件中断请求
	wire tmr_itr_req_vld; // 有效的计时器中断请求
	wire ext_itr_req_vld; // 有效的外部中断请求
	wire lsu_expt_req_vld; // 有效的LSU异常请求
	wire sync_expt_req_vld; // 有效的同步异常请求
	// 许可的中断/异常请求
	wire sw_itr_req_granted; // 许可的软件中断请求
	wire tmr_itr_req_granted; // 许可的计时器中断请求
	wire ext_itr_req_granted; // 许可的外部中断请求
	wire lsu_expt_req_granted; // 许可的LSU异常请求
	wire sync_expt_req_granted; // 许可的同步异常请求
	// 正在处理的中断/异常(标志)
	reg trap_processing;
	
	// 问题: ECALL/同步异常可能会被中断请求/LSU异常请求覆盖而得不到处理!
	assign itr_expt_enter = 
		s_pst_valid & s_pst_ready & // 当前指令交付完成
		(~brc_prdt_failed) & // 当前指令不是分支预测失败的B指令
		(sw_itr_req_vld | tmr_itr_req_vld | ext_itr_req_vld | lsu_expt_req_vld | sync_expt_req_vld | // 当前有中断/异常
			((~(s_pst_err_code[0] | s_pst_err_code[1])) & s_pst_is_ecall_inst)); // 待交付指令没有异常且为ECALL指令
	assign itr_expt_is_intr = sw_itr_req_vld | tmr_itr_req_vld | ext_itr_req_vld;
	assign itr_expt_cause = 
		({8{ext_itr_req_vld}} & INTR_CODE_M_EXT) | // 机器模式外部中断
		({8{(~ext_itr_req_vld) & sw_itr_req_vld}} & INTR_CODE_M_SW) | // 机器模式软件中断
		({8{(~ext_itr_req_vld) & (~sw_itr_req_vld) & tmr_itr_req_vld}} & INTR_CODE_M_TMR) | // 机器模式计时器中断
		({8{(~ext_itr_req_vld) & (~sw_itr_req_vld) & (~tmr_itr_req_vld) & lsu_expt_req_vld & 
			(s_lsu_expt_err == LSU_LOAD_ACCESS_FAULT)}} & EXPT_CODE_LOAD_ACCESS_FAULT) | // 读存储映射总线错误
		({8{(~ext_itr_req_vld) & (~sw_itr_req_vld) & (~tmr_itr_req_vld) & lsu_expt_req_vld & 
			(s_lsu_expt_err == LSU_STORE_ACCESS_FAULT)}} & EXPT_CODE_STORE_ACCESS_FAULT) | // 写存储映射总线错误
		({8{(~ext_itr_req_vld) & (~sw_itr_req_vld) & (~tmr_itr_req_vld) & (~lsu_expt_req_vld) & sync_expt_req_vld & 
			(s_pst_err_code == CMT_INST_ERR_CODE_PC_UNALIGNED)}} & EXPT_CODE_INST_ADDR_MISALIGNED) | // 指令地址非对齐
		({8{(~ext_itr_req_vld) & (~sw_itr_req_vld) & (~tmr_itr_req_vld) & (~lsu_expt_req_vld) & sync_expt_req_vld & 
			(s_pst_err_code == CMT_INST_ERR_CODE_IMEM_ACCESS_FAILED)}} & EXPT_CODE_INST_ACCESS_FAULT) | // 指令总线访问错误
		({8{(~ext_itr_req_vld) & (~sw_itr_req_vld) & (~tmr_itr_req_vld) & (~lsu_expt_req_vld) & sync_expt_req_vld & 
			(s_pst_err_code == CMT_INST_ERR_CODE_ILLEGAL)}} & EXPT_CODE_ILLEGAL_INST) | // 非法指令
		({8{(~ext_itr_req_vld) & (~sw_itr_req_vld) & (~tmr_itr_req_vld) & (~lsu_expt_req_vld) & sync_expt_req_vld & 
			(s_pst_err_code == CMT_INST_ERR_CODE_RD_DBUS_UNALIGNED)}} & EXPT_CODE_LOAD_ADDR_MISALIGNED) | // 读存储映射地址非对齐
		({8{(~ext_itr_req_vld) & (~sw_itr_req_vld) & (~tmr_itr_req_vld) & (~lsu_expt_req_vld) & sync_expt_req_vld & 
			(s_pst_err_code == CMT_INST_ERR_CODE_WT_DBUS_UNALIGNED)}} & EXPT_CODE_STORE_ADDR_MISALIGNED) | // 写存储映射地址非对齐
		({8{(~ext_itr_req_vld) & (~sw_itr_req_vld) & (~tmr_itr_req_vld) & (~lsu_expt_req_vld) & 
			(~(s_pst_err_code[0] | s_pst_err_code[1])) & s_pst_is_ecall_inst}} & EXPT_CODE_ENV_CALL_FROM_M); // 机器模式环境调用
	// 注意: 只有同步异常的返回地址为PC, 其余中断/异常的返回地址均为PC + 4!
	// 问题: 1条ECALL/带有同步异常的指令可能会被中断请求/LSU异常请求覆盖, 且在返回时这条ECALL/带有同步异常的指令会被跳过!
	assign itr_expt_ret_addr = s_pst_pc_of_inst + 
		{sw_itr_req_vld | tmr_itr_req_vld | ext_itr_req_vld | lsu_expt_req_vld | (~sync_expt_req_vld), 2'b00};
	assign itr_expt_val = 
		({32{lsu_expt_req_granted}} & 
			s_lsu_expt_ls_addr) | // 发生LSU异常时, 保存LSU带来的访存地址
		({32{sync_expt_req_granted & (s_pst_err_code[1] & s_pst_err_code[2])}} & 
			ls_addr) | // 发生读/写存储映射地址非对齐导致的同步异常时, 保存ALU生成的访存地址
		({32{sync_expt_req_granted & s_pst_err_code[1] & (~s_pst_err_code[2])}} & 
			s_pst_pc_of_inst) | // 发生指令地址非对齐或指令总线访问失败导致的同步异常时, 保存指令对应的PC
		({32{sync_expt_req_granted & s_pst_err_code[0] & (~s_pst_err_code[1])}} & 
			s_pst_inst); // 发生非法指令导致的同步异常时, 保存取到的指令
	
	assign itr_expt_ret = 
		s_pst_valid & s_pst_ready & // 当前指令交付完成
		(~(s_pst_err_code[0] | s_pst_err_code[1])) & s_pst_is_mret_inst; // 待交付指令没有异常且为MRET指令
	
	// 注意: 每当CPU进入中断/异常时, 全局中断使能自动关闭, 因此不支持中断嵌套!
	assign sw_itr_req_vld = 
		mstatus_mie_v & mie_msie_v & // 软件中断已使能
		sw_itr_req; // 软件中断请求有效
	assign tmr_itr_req_vld = 
		mstatus_mie_v & mie_mtie_v & // 计时器中断已使能
		tmr_itr_req; // 计时器中断请求有效
	assign ext_itr_req_vld = 
		mstatus_mie_v & mie_meie_v & // 外部中断已使能
		ext_itr_req; // 外部中断请求有效
	assign lsu_expt_req_vld = 
		(~trap_processing) & // 在处理中断/异常时, 不再接受LSU异常
		s_lsu_expt_valid; // 当前有LSU异常
	// 问题: 当CPU进入中断/异常后, 若产生新的同步异常, CPU无法正确处理!
	assign sync_expt_req_vld = 
		(~trap_processing) & // 在处理中断/异常时, 不再接受同步异常
		s_pst_valid & // 当前有待交付的指令
		(s_pst_err_code[0] | s_pst_err_code[1]); // 待交付指令有异常
	
	/*
	分支预测失败导致的重新跳转具有最高的优先级, 其次才是中断/异常
	中断/异常优先级: 外部中断 > 软件中断 > 计时器中断 > 来自LSU的异常 > 同步异常
	*/
	assign sw_itr_req_granted = 
		(~brc_prdt_failed) & (~ext_itr_req_vld) & sw_itr_req_vld;
	assign tmr_itr_req_granted = 
		(~brc_prdt_failed) & (~ext_itr_req_vld) & (~sw_itr_req_vld) & tmr_itr_req_vld;
	assign ext_itr_req_granted = 
		(~brc_prdt_failed) & ext_itr_req_vld;
	assign lsu_expt_req_granted = 
		(~brc_prdt_failed) & (~ext_itr_req_vld) & (~sw_itr_req_vld) & (~tmr_itr_req_vld) & lsu_expt_req_vld;
	assign sync_expt_req_granted = 
		(~brc_prdt_failed) & (~ext_itr_req_vld) & (~sw_itr_req_vld) & (~tmr_itr_req_vld) & (~lsu_expt_req_vld) & sync_expt_req_vld;
	
	// 正在处理的中断/异常(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			trap_processing <= 1'b0;
		else if(itr_expt_enter | itr_expt_ret)
			trap_processing <= # simulation_delay itr_expt_enter;
	end
	
	/** 冲刷控制 **/
	reg flush_processing; // 正在处理的冲刷(标志)
	
	assign flush_req = 
		s_pst_valid & s_pst_ready & // 当前指令交付完成
		(brc_prdt_failed | // 分支预测失败
			((~(s_pst_err_code[0] | s_pst_err_code[1])) & 
				(s_pst_is_ecall_inst | s_pst_is_mret_inst)) | // 待交付指令没有异常且为ECALL或MRET指令
			sw_itr_req_vld | tmr_itr_req_vld | ext_itr_req_vld | lsu_expt_req_vld | sync_expt_req_vld); // 当前有中断/异常
	assign flush_addr = 
		({32{brc_prdt_failed}} & s_pst_brc_pc_upd) | // 分支预测失败时冲刷到修正的PC
		({32{s_pst_is_mret_inst}} & mepc_ret_addr) | // 中断/异常返回时冲刷到mepc状态寄存器定义的中断/异常返回地址
		({32{(~brc_prdt_failed) & (~s_pst_is_mret_inst)}} & itr_expt_vec_baseaddr); // 其余情况冲刷到中断/异常向量表基地址
	
	// 正在处理的冲刷(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			flush_processing <= 1'b0;
		else
			// flush_processing ? (~flush_ack):(flush_req & (~flush_ack))
			flush_processing <= # simulation_delay (flush_processing | flush_req) & (~flush_ack);
	end
	
	/** 指令交付 **/
	assign s_pst_ready = (~flush_processing) & m_pst_ready; // 当前没有处理中的冲刷, 且后级就绪
	
	assign s_lsu_expt_ready = 
		(~flush_processing) & m_pst_ready & // 当前没有处理中的冲刷, 且后级就绪
		s_pst_valid & // 保证"LSU异常输入"握手的同时, "待交付指令"也握手
		lsu_expt_req_granted; // LSU异常请求被许可
	
	assign m_pst_inst_cmt = ~sync_expt_req_granted; // 仅当待交付指令带有同步异常且该同步异常被许可时, 指令被取消
	assign m_pst_wb_imdt = s_pst_rd_vld & (~s_pst_is_long_inst); // 待交付指令需要写RD, 并且不是长指令(L/S, 乘除法)
	assign m_pst_valid = (~flush_processing) & s_pst_valid; // 当前没有处理中的冲刷, 且有待交付的指令
	
endmodule
