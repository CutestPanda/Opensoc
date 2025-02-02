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
本模块: 译码/派遣器

描述:
读通用寄存器堆, 进行指令译码, 将指令派遣给EXU(ALU/LSU/CSR原子读写单元/乘法器/除法器)

注意：
无

协议:
REQ/GRANT

作者: 陈家耀
日期: 2025/01/31
********************************************************************/


module panda_risc_v_dcd_dsptc #(
	parameter integer inst_id_width = 4, // 指令编号的位宽
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟
	input wire clk,
	// 系统复位输入
	input wire sys_resetn,
	
	// 复位/冲刷请求
	input wire sys_reset_req, // 系统复位请求
	input wire flush_req, // 冲刷请求
	
	// 内存屏障处理
	input wire lsu_idle, // 访存单元空闲(标志)
	
	// 数据相关性
	output wire[4:0] raw_dpc_check_rs1_id, // 待检查RAW相关性的RS1索引
	input wire rs1_raw_dpc, // RS1有RAW相关性(标志)
	output wire[4:0] raw_dpc_check_rs2_id, // 待检查RAW相关性的RS2索引
	input wire rs2_raw_dpc, // RS2有RAW相关性(标志)
	output wire[4:0] waw_dpc_check_rd_id, // 待检查WAW相关性的RD索引
	input wire rd_waw_dpc, // RD有WAW相关性(标志)
	
	// 译码器给出的通用寄存器堆读端口#0
	output wire dcd_reg_file_rd_p0_req, // 读请求
	output wire[4:0] dcd_reg_file_rd_p0_addr, // 读地址
	input wire dcd_reg_file_rd_p0_grant, // 读许可
	input wire[31:0] dcd_reg_file_rd_p0_dout, // 读数据
	// 译码器给出的通用寄存器堆读端口#1
	output wire dcd_reg_file_rd_p1_req, // 读请求
	output wire[4:0] dcd_reg_file_rd_p1_addr, // 读地址
	input wire dcd_reg_file_rd_p1_grant, // 读许可
	input wire[31:0] dcd_reg_file_rd_p1_dout, // 读数据
	
	// IFU取指结果
	input wire[127:0] s_if_res_data, // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	input wire[3:0] s_if_res_msg, // 取指附加信息({是否预测跳转(1bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	input wire[inst_id_width-1:0] s_if_res_id, // 指令编号
	input wire s_if_res_valid,
	output wire s_if_res_ready,
	
	// ALU执行请求
	output wire[3:0] m_alu_op_mode, // 操作类型
	output wire[31:0] m_alu_op1, // 操作数1
	output wire[31:0] m_alu_op2, // 操作数2或取到的指令(若当前是非法指令)
	output wire m_alu_addr_gen_sel, // ALU是否用于访存地址生成
	output wire[2:0] m_alu_err_code, // 指令的错误类型(3'b000 -> 正常, 3'b001 -> 非法指令, 
	                                 //     3'b010 -> 指令地址非对齐, 3'b011 -> 指令总线访问失败, 
									 //     3'b110 -> 读存储映射地址非对齐, 3'b111 -> 写存储映射地址非对齐)
	output wire[31:0] m_alu_pc_of_inst, // 指令对应的PC
	output wire m_alu_is_b_inst, // 是否B指令
	output wire m_alu_is_ecall_inst, // 是否ECALL指令
	output wire m_alu_is_mret_inst, // 是否MRET指令
	output wire m_alu_is_csr_rw_inst, // 是否CSR读写指令
	output wire m_alu_is_fence_i_inst, // 是否FENCE.I指令
	output wire[31:0] m_alu_brc_pc_upd, // 分支预测失败时修正的PC
	output wire m_alu_prdt_jump, // 是否预测跳转
	output wire[4:0] m_alu_rd_id, // RD索引
	output wire m_alu_rd_vld, // 是否需要写RD
	output wire m_alu_is_long_inst, // 是否长指令
	output wire[inst_id_width-1:0] m_alu_inst_id, // 指令编号
	output wire m_alu_valid,
	input wire m_alu_ready,
	
	// LSU执行请求
	output wire m_ls_sel, // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	output wire[2:0] m_ls_type, // 访存类型
	output wire[4:0] m_rd_id_for_ld, // 用于加载的目标寄存器的索引
	output wire[31:0] m_ls_din, // 写数据
	output wire[inst_id_width-1:0] m_lsu_inst_id, // 指令编号
	output wire m_lsu_valid,
	input wire m_lsu_ready,
	
	// CSR原子读写单元执行请求
	output wire[11:0] m_csr_addr, // CSR地址
	output wire[1:0] m_csr_upd_type, // CSR更新类型
	output wire[31:0] m_csr_upd_mask_v, // CSR更新掩码或更新值
	output wire[4:0] m_csr_rw_rd_id, // RD索引
	output wire[inst_id_width-1:0] m_csr_rw_inst_id, // 指令编号
	output wire m_csr_rw_valid,
	input wire m_csr_rw_ready,
	
	// 乘法器执行请求
	output wire[32:0] m_mul_op_a, // 操作数A
	output wire[32:0] m_mul_op_b, // 操作数B
	output wire m_mul_res_sel, // 乘法结果选择(1'b0 -> 低32位, 1'b1 -> 高32位)
	output wire[4:0] m_mul_rd_id, // RD索引
	output wire[inst_id_width-1:0] m_mul_inst_id, // 指令编号
	output wire m_mul_valid,
	input wire m_mul_ready,
	
	// 除法器执行请求
	output wire[32:0] m_div_op_a, // 操作数A
	output wire[32:0] m_div_op_b, // 操作数B
	output wire m_div_rem_sel, // 除法/求余选择(1'b0 -> 除法, 1'b1 -> 求余)
	output wire[4:0] m_div_rd_id, // RD索引
	output wire[inst_id_width-1:0] m_div_inst_id, // 指令编号
	output wire m_div_valid,
	input wire m_div_ready,
	
	// 数据相关性跟踪
	// 指令被译码
	output wire[inst_id_width-1:0] dpc_trace_dcd_inst_id, // 指令编号
	output wire dpc_trace_dcd_valid,
	// 指令被派遣
	output wire[inst_id_width-1:0] dpc_trace_dsptc_inst_id, // 指令编号
	output wire dpc_trace_dsptc_valid
);
	
	/** 通用寄存器读控制 **/
	// 读通用寄存器堆请求
	wire[4:0] s_reg_file_rd_req_rs1_id; // RS1索引
	wire[4:0] s_reg_file_rd_req_rs2_id; // RS2索引
	wire s_reg_file_rd_req_rs1_vld; // 是否需要读RS1(标志)
	wire s_reg_file_rd_req_rs2_vld; // 是否需要读RS2(标志)
	wire s_reg_file_rd_req_valid;
	wire s_reg_file_rd_req_ready;
	// 源寄存器读结果
	wire[31:0] m_reg_file_rd_res_rs1_v; // RS1读结果
	wire[31:0] m_reg_file_rd_res_rs2_v; // RS2读结果
	wire m_reg_file_rd_res_valid;
	wire m_reg_file_rd_res_ready;
	
	panda_risc_v_reg_file_rd #(
		.simulation_delay(simulation_delay)
	)panda_risc_v_reg_file_rd_u(
		.clk(clk),
		.resetn(sys_resetn),
		
		.sys_reset_req(sys_reset_req),
		.flush_req(flush_req),
		
		.raw_dpc_check_rs1_id(raw_dpc_check_rs1_id),
		.rs1_raw_dpc(rs1_raw_dpc),
		.raw_dpc_check_rs2_id(raw_dpc_check_rs2_id),
		.rs2_raw_dpc(rs2_raw_dpc),
		
		.s_reg_file_rd_req_rs1_id(s_reg_file_rd_req_rs1_id),
		.s_reg_file_rd_req_rs2_id(s_reg_file_rd_req_rs2_id),
		.s_reg_file_rd_req_rs1_vld(s_reg_file_rd_req_rs1_vld),
		.s_reg_file_rd_req_rs2_vld(s_reg_file_rd_req_rs2_vld),
		.s_reg_file_rd_req_valid(s_reg_file_rd_req_valid),
		.s_reg_file_rd_req_ready(s_reg_file_rd_req_ready),
		
		.m_reg_file_rd_res_rs1_v(m_reg_file_rd_res_rs1_v),
		.m_reg_file_rd_res_rs2_v(m_reg_file_rd_res_rs2_v),
		.m_reg_file_rd_res_valid(m_reg_file_rd_res_valid),
		.m_reg_file_rd_res_ready(m_reg_file_rd_res_ready),
		
		.dcd_reg_file_rd_p0_req(dcd_reg_file_rd_p0_req),
		.dcd_reg_file_rd_p0_addr(dcd_reg_file_rd_p0_addr),
		.dcd_reg_file_rd_p0_grant(dcd_reg_file_rd_p0_grant),
		.dcd_reg_file_rd_p0_dout(dcd_reg_file_rd_p0_dout),
		
		.dcd_reg_file_rd_p1_req(dcd_reg_file_rd_p1_req),
		.dcd_reg_file_rd_p1_addr(dcd_reg_file_rd_p1_addr),
		.dcd_reg_file_rd_p1_grant(dcd_reg_file_rd_p1_grant),
		.dcd_reg_file_rd_p1_dout(dcd_reg_file_rd_p1_dout)
	);
	
	/** 派遣信息生成 **/
	// 读通用寄存器堆请求
	wire[4:0] m_reg_file_rd_req_rs1_id; // RS1索引
	wire[4:0] m_reg_file_rd_req_rs2_id; // RS2索引
	wire m_reg_file_rd_req_rs1_vld; // 是否需要读RS1(标志)
	wire m_reg_file_rd_req_rs2_vld; // 是否需要读RS2(标志)
	wire m_reg_file_rd_req_valid;
	wire m_reg_file_rd_req_ready;
	// 源寄存器读结果
	wire[31:0] s_reg_file_rd_res_rs1_v; // RS1读结果
	wire[31:0] s_reg_file_rd_res_rs2_v; // RS2读结果
	wire s_reg_file_rd_res_valid;
	wire s_reg_file_rd_res_ready;
	// 派遣请求
	/*
	指令类型           复用的派遣信息的内容
	--------------------------------------------
	    L/S         {打包的LSU操作信息[2:0], 
	                     打包的ALU操作信息[67:0]}
	  CSR读写       {打包的CSR原子读写操作信息[45:0]}
	   乘除         {打包的乘除法操作信息[66:0]}
	   非法指令     {取到的指令[31:0]}
	   其他         {是否预测跳转, 
	                     打包的ALU操作信息[67:0]}
	*/
	wire[70:0] m_dispatch_req_msg_reused; // 复用的派遣信息
	wire[10:0] m_dispatch_req_inst_type_packeted; // 打包的指令类型标志
	wire[31:0] m_dispatch_req_pc_of_inst; // 指令对应的PC
	wire[31:0] m_dispatch_req_brc_pc_upd_store_din; // 分支预测失败时修正的PC或用于写存储映射的数据
	wire[4:0] m_dispatch_req_rd_id; // RD索引
	wire m_dispatch_req_rd_vld; // 是否需要写RD
	wire[2:0] m_dispatch_req_err_code; // 错误类型(3'b000 -> 正常, 3'b001 -> 非法指令, 
	                                   //     3'b010 -> 指令地址非对齐, 3'b011 -> 指令总线访问失败, 
									   //     3'b110 -> 读存储映射地址非对齐, 3'b111 -> 写存储映射地址非对齐)
	wire[inst_id_width-1:0] m_dispatch_req_inst_id; // 指令编号
	wire m_dispatch_req_valid;
	wire m_dispatch_req_ready;
	
	assign s_reg_file_rd_req_rs1_id = m_reg_file_rd_req_rs1_id;
	assign s_reg_file_rd_req_rs2_id = m_reg_file_rd_req_rs2_id;
	assign s_reg_file_rd_req_rs1_vld = m_reg_file_rd_req_rs1_vld;
	assign s_reg_file_rd_req_rs2_vld = m_reg_file_rd_req_rs2_vld;
	assign s_reg_file_rd_req_valid = m_reg_file_rd_req_valid;
	assign m_reg_file_rd_req_ready = s_reg_file_rd_req_ready;
	
	assign s_reg_file_rd_res_rs1_v = m_reg_file_rd_res_rs1_v;
	assign s_reg_file_rd_res_rs2_v = m_reg_file_rd_res_rs2_v;
	assign s_reg_file_rd_res_valid = m_reg_file_rd_res_valid;
	assign m_reg_file_rd_res_ready = s_reg_file_rd_res_ready;
	
	panda_risc_v_dispatch_msg_gen #(
		.inst_id_width(inst_id_width),
		.simulation_delay(simulation_delay)
	)panda_risc_v_dispatch_msg_gen_u(
		.clk(clk),
		.resetn(sys_resetn),
		
		.sys_reset_req(sys_reset_req),
		.flush_req(flush_req),
		
		.s_if_res_data(s_if_res_data),
		.s_if_res_msg(s_if_res_msg),
		.s_if_res_id(s_if_res_id),
		.s_if_res_valid(s_if_res_valid),
		.s_if_res_ready(s_if_res_ready),
		
		.m_reg_file_rd_req_rs1_id(m_reg_file_rd_req_rs1_id),
		.m_reg_file_rd_req_rs2_id(m_reg_file_rd_req_rs2_id),
		.m_reg_file_rd_req_rs1_vld(m_reg_file_rd_req_rs1_vld),
		.m_reg_file_rd_req_rs2_vld(m_reg_file_rd_req_rs2_vld),
		.m_reg_file_rd_req_valid(m_reg_file_rd_req_valid),
		.m_reg_file_rd_req_ready(m_reg_file_rd_req_ready),
		
		.s_reg_file_rd_res_rs1_v(s_reg_file_rd_res_rs1_v),
		.s_reg_file_rd_res_rs2_v(s_reg_file_rd_res_rs2_v),
		.s_reg_file_rd_res_valid(s_reg_file_rd_res_valid),
		.s_reg_file_rd_res_ready(s_reg_file_rd_res_ready),
		
		.m_dispatch_req_msg_reused(m_dispatch_req_msg_reused),
		.m_dispatch_req_inst_type_packeted(m_dispatch_req_inst_type_packeted),
		.m_dispatch_req_pc_of_inst(m_dispatch_req_pc_of_inst),
		.m_dispatch_req_brc_pc_upd_store_din(m_dispatch_req_brc_pc_upd_store_din),
		.m_dispatch_req_rd_id(m_dispatch_req_rd_id),
		.m_dispatch_req_rd_vld(m_dispatch_req_rd_vld),
		.m_dispatch_req_err_code(m_dispatch_req_err_code),
		.m_dispatch_req_inst_id(m_dispatch_req_inst_id),
		.m_dispatch_req_valid(m_dispatch_req_valid),
		.m_dispatch_req_ready(m_dispatch_req_ready),
		
		.dpc_trace_dcd_inst_id(dpc_trace_dcd_inst_id),
		.dpc_trace_dcd_valid(dpc_trace_dcd_valid),
		.dpc_trace_dsptc_inst_id(dpc_trace_dsptc_inst_id),
		.dpc_trace_dsptc_valid(dpc_trace_dsptc_valid)
	);
	
	/** 派遣单元 **/
	// 派遣请求
	/*
	指令类型           复用的派遣信息的内容
	--------------------------------------------
	    L/S         {打包的LSU操作信息[2:0], 
	                     打包的ALU操作信息[67:0]}
	  CSR读写       {打包的CSR原子读写操作信息[45:0]}
	   乘除         {打包的乘除法操作信息[66:0]}
	   非法指令     {取到的指令[31:0]}
	   其他         {是否预测跳转, 
	                     打包的ALU操作信息[67:0]}
	*/
	wire[70:0] s_dispatch_req_msg_reused; // 复用的派遣信息
	wire[10:0] s_dispatch_req_inst_type_packeted; // 打包的指令类型标志
	wire[31:0] s_dispatch_req_pc_of_inst; // 指令对应的PC
	wire[31:0] s_dispatch_req_brc_pc_upd_store_din; // 分支预测失败时修正的PC或用于写存储映射的数据
	wire[4:0] s_dispatch_req_rd_id; // RD索引
	wire s_dispatch_req_rd_vld; // 是否需要写RD
	wire[2:0] s_dispatch_req_err_code; // 错误类型(3'b000 -> 正常, 3'b001 -> 非法指令, 
	                                   //     3'b010 -> 指令地址非对齐, 3'b011 -> 指令总线访问失败, 
									   //     3'b110 -> 读存储映射地址非对齐, 3'b111 -> 写存储映射地址非对齐)
	wire[inst_id_width-1:0] s_dispatch_req_inst_id; // 指令编号
	wire s_dispatch_req_valid;
	wire s_dispatch_req_ready;
	
	assign s_dispatch_req_msg_reused = m_dispatch_req_msg_reused;
	assign s_dispatch_req_inst_type_packeted = m_dispatch_req_inst_type_packeted;
	assign s_dispatch_req_pc_of_inst = m_dispatch_req_pc_of_inst;
	assign s_dispatch_req_brc_pc_upd_store_din = m_dispatch_req_brc_pc_upd_store_din;
	assign s_dispatch_req_rd_id = m_dispatch_req_rd_id;
	assign s_dispatch_req_rd_vld = m_dispatch_req_rd_vld;
	assign s_dispatch_req_err_code = m_dispatch_req_err_code;
	assign s_dispatch_req_inst_id = m_dispatch_req_inst_id;
	assign s_dispatch_req_valid = m_dispatch_req_valid;
	assign m_dispatch_req_ready = s_dispatch_req_ready;
	
	panda_risc_v_dispatcher #(
		.inst_id_width(inst_id_width)
	)panda_risc_v_dispatcher_u(
		.waw_dpc_check_rd_id(waw_dpc_check_rd_id),
		.rd_waw_dpc(rd_waw_dpc),
		
		.lsu_idle(lsu_idle),
		
		.s_dispatch_req_msg_reused(s_dispatch_req_msg_reused),
		.s_dispatch_req_inst_type_packeted(s_dispatch_req_inst_type_packeted),
		.s_dispatch_req_pc_of_inst(s_dispatch_req_pc_of_inst),
		.s_dispatch_req_brc_pc_upd_store_din(s_dispatch_req_brc_pc_upd_store_din),
		.s_dispatch_req_rd_id(s_dispatch_req_rd_id),
		.s_dispatch_req_rd_vld(s_dispatch_req_rd_vld),
		.s_dispatch_req_err_code(s_dispatch_req_err_code),
		.s_dispatch_req_inst_id(s_dispatch_req_inst_id),
		.s_dispatch_req_valid(s_dispatch_req_valid),
		.s_dispatch_req_ready(s_dispatch_req_ready),
		
		.m_alu_op_mode(m_alu_op_mode),
		.m_alu_op1(m_alu_op1),
		.m_alu_op2(m_alu_op2),
		.m_alu_addr_gen_sel(m_alu_addr_gen_sel),
		.m_alu_err_code(m_alu_err_code),
		.m_alu_pc_of_inst(m_alu_pc_of_inst),
		.m_alu_is_b_inst(m_alu_is_b_inst),
		.m_alu_is_ecall_inst(m_alu_is_ecall_inst),
		.m_alu_is_mret_inst(m_alu_is_mret_inst),
		.m_alu_is_csr_rw_inst(m_alu_is_csr_rw_inst),
		.m_alu_is_fence_i_inst(m_alu_is_fence_i_inst),
		.m_alu_brc_pc_upd(m_alu_brc_pc_upd),
		.m_alu_prdt_jump(m_alu_prdt_jump),
		.m_alu_rd_id(m_alu_rd_id),
		.m_alu_rd_vld(m_alu_rd_vld),
		.m_alu_is_long_inst(m_alu_is_long_inst),
		.m_alu_inst_id(m_alu_inst_id),
		.m_alu_valid(m_alu_valid),
		.m_alu_ready(m_alu_ready),
		
		.m_ls_sel(m_ls_sel),
		.m_ls_type(m_ls_type),
		.m_rd_id_for_ld(m_rd_id_for_ld),
		.m_ls_din(m_ls_din),
		.m_lsu_inst_id(m_lsu_inst_id),
		.m_lsu_valid(m_lsu_valid),
		.m_lsu_ready(m_lsu_ready),
		
		.m_csr_addr(m_csr_addr),
		.m_csr_upd_type(m_csr_upd_type),
		.m_csr_upd_mask_v(m_csr_upd_mask_v),
		.m_csr_rw_rd_id(m_csr_rw_rd_id),
		.m_csr_rw_inst_id(m_csr_rw_inst_id),
		.m_csr_rw_valid(m_csr_rw_valid),
		.m_csr_rw_ready(m_csr_rw_ready),
		
		.m_mul_op_a(m_mul_op_a),
		.m_mul_op_b(m_mul_op_b),
		.m_mul_res_sel(m_mul_res_sel),
		.m_mul_rd_id(m_mul_rd_id),
		.m_mul_inst_id(m_mul_inst_id),
		.m_mul_valid(m_mul_valid),
		.m_mul_ready(m_mul_ready),
		
		.m_div_op_a(m_div_op_a),
		.m_div_op_b(m_div_op_b),
		.m_div_rem_sel(m_div_rem_sel),
		.m_div_rd_id(m_div_rd_id),
		.m_div_inst_id(m_div_inst_id),
		.m_div_valid(m_div_valid),
		.m_div_ready(m_div_ready)
	);
	
endmodule
