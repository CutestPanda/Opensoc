`timescale 1ns / 1ps
/********************************************************************
本模块: 译码/派遣器

描述:
仅用于综合后时序评估

注意：
无

协议:
REQ/GRANT

作者: 陈家耀
日期: 2025/02/01
********************************************************************/


module panda_risc_v_dcd_dsptc_eva(
	// 时钟
	input wire clk,
	// 外部复位输入
	input wire ext_resetn,
	
	// 软件复位请求
	input wire sw_reset,
	
	// 冲刷请求
	input wire flush_req,
	
	// 内存屏障处理
	input wire lsu_idle, // 访存单元空闲(标志)
	
	// 数据相关性
	output wire[4:0] raw_dpc_check_rs1_id, // 待检查RAW相关性的RS1索引
	input wire rs1_raw_dpc, // RS1有RAW相关性(标志)
	output wire[4:0] raw_dpc_check_rs2_id, // 待检查RAW相关性的RS2索引
	input wire rs2_raw_dpc, // RS2有RAW相关性(标志)
	// 仅检查待派遣指令的RD索引是否与未交付长指令的RD索引冲突!
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
	
	// 取指结果
	input wire[127:0] s_if_res_data, // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	input wire[3:0] s_if_res_msg, // 取指附加信息({是否预测跳转(1bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	input wire[3:0] s_if_res_id, // 指令编号
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
	output wire[3:0] m_alu_inst_id, // 指令编号
	output wire m_alu_valid,
	input wire m_alu_ready,
	
	// LSU执行请求
	output wire m_ls_sel, // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	output wire[2:0] m_ls_type, // 访存类型
	output wire[4:0] m_rd_id_for_ld, // 用于加载的目标寄存器的索引
	output wire[31:0] m_ls_din, // 写数据
	output wire[3:0] m_lsu_inst_id, // 指令编号
	output wire m_lsu_valid,
	input wire m_lsu_ready,
	
	// CSR原子读写单元执行请求
	output wire[11:0] m_csr_addr, // CSR地址
	output wire[1:0] m_csr_upd_type, // CSR更新类型
	output wire[31:0] m_csr_upd_mask_v, // CSR更新掩码或更新值
	output wire[4:0] m_csr_rw_rd_id, // RD索引
	output wire[3:0] m_csr_rw_inst_id, // 指令编号
	output wire m_csr_rw_valid,
	input wire m_csr_rw_ready,
	
	// 乘法器执行请求
	output wire[32:0] m_mul_op_a, // 操作数A
	output wire[32:0] m_mul_op_b, // 操作数B
	output wire m_mul_res_sel, // 乘法结果选择(1'b0 -> 低32位, 1'b1 -> 高32位)
	output wire[4:0] m_mul_rd_id, // RD索引
	output wire[3:0] m_mul_inst_id, // 指令编号
	output wire m_mul_valid,
	input wire m_mul_ready,
	
	// 除法器执行请求
	output wire[32:0] m_div_op_a, // 操作数A
	output wire[32:0] m_div_op_b, // 操作数B
	output wire m_div_rem_sel, // 除法/求余选择(1'b0 -> 除法, 1'b1 -> 求余)
	output wire[4:0] m_div_rd_id, // RD索引
	output wire[3:0] m_div_inst_id, // 指令编号
	output wire m_div_valid,
	input wire m_div_ready,
	
	// 数据相关性跟踪
	// 指令被译码
	output wire[3:0] dpc_trace_dcd_inst_id, // 指令编号
	output wire dpc_trace_dcd_valid,
	// 指令被派遣
	output wire[3:0] dpc_trace_dsptc_inst_id, // 指令编号
	output wire dpc_trace_dsptc_valid
);
	
	// 系统复位输入
	wire sys_resetn;
	// 系统复位请求
	wire sys_reset_req;
	
	panda_risc_v_reset #(
		.simulation_delay(1)
	)panda_risc_v_reset_u(
		.clk(clk),
		
		.ext_resetn(ext_resetn),
		.sw_reset(sw_reset),
		
		.sys_resetn(sys_resetn),
		.sys_reset_req(sys_reset_req)
	);
	
	panda_risc_v_dcd_dsptc #(
		.simulation_delay(1)
	)panda_risc_v_dcd_dsptc_u(
		.clk(clk),
		.sys_resetn(sys_resetn),
		
		.sys_reset_req(sys_reset_req),
		.flush_req(flush_req),
		
		.lsu_idle(lsu_idle),
		
		.raw_dpc_check_rs1_id(raw_dpc_check_rs1_id),
		.rs1_raw_dpc(rs1_raw_dpc),
		.raw_dpc_check_rs2_id(raw_dpc_check_rs2_id),
		.rs2_raw_dpc(rs2_raw_dpc),
		.waw_dpc_check_rd_id(waw_dpc_check_rd_id),
		.rd_waw_dpc(rd_waw_dpc),
		
		.dcd_reg_file_rd_p0_req(dcd_reg_file_rd_p0_req),
		.dcd_reg_file_rd_p0_addr(dcd_reg_file_rd_p0_addr),
		.dcd_reg_file_rd_p0_grant(dcd_reg_file_rd_p0_grant),
		.dcd_reg_file_rd_p0_dout(dcd_reg_file_rd_p0_dout),
		
		.dcd_reg_file_rd_p1_req(dcd_reg_file_rd_p1_req),
		.dcd_reg_file_rd_p1_addr(dcd_reg_file_rd_p1_addr),
		.dcd_reg_file_rd_p1_grant(dcd_reg_file_rd_p1_grant),
		.dcd_reg_file_rd_p1_dout(dcd_reg_file_rd_p1_dout),
		
		.s_if_res_data(s_if_res_data),
		.s_if_res_msg(s_if_res_msg),
		.s_if_res_id(s_if_res_id),
		.s_if_res_valid(s_if_res_valid),
		.s_if_res_ready(s_if_res_ready),
		
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
		.m_div_ready(m_div_ready),
		
		.dpc_trace_dcd_inst_id(dpc_trace_dcd_inst_id),
		.dpc_trace_dcd_valid(dpc_trace_dcd_valid),
		.dpc_trace_dsptc_inst_id(dpc_trace_dsptc_inst_id),
		.dpc_trace_dsptc_valid(dpc_trace_dsptc_valid)
	);
	
endmodule
