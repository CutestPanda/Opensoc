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
日期: 2024/12/01
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
	
	// 数据相关性
	output wire[4:0] raw_dpc_check_rs1_id, // 待检查RAW相关性的RS1索引
	input wire rs1_raw_dpc, // RS1有RAW相关性(标志)
	output wire[4:0] raw_dpc_check_rs2_id, // 待检查RAW相关性的RS2索引
	input wire rs2_raw_dpc, // RS2有RAW相关性(标志)
	// 仅检查待派遣指令的RD索引是否与未交付长指令的RD索引冲突!
	output wire[4:0] raw_dpc_check_rd_id, // 待检查WAW相关性的RD索引
	input wire rd_raw_dpc, // RD有WAW相关性(标志)
	
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
	input wire[127:0] s_if_res_data, // {指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)}
	input wire[3:0] s_if_res_msg, // {是否预测跳转(1bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)}
	input wire s_if_res_valid,
	output wire s_if_res_ready,
	
	// ALU执行请求
	output wire[3:0] m_alu_op_mode, // 操作类型
	output wire[31:0] m_alu_op1, // 操作数1
	output wire[31:0] m_alu_op2, // 操作数2
	output wire m_alu_addr_gen_sel, // ALU是否用于访存地址生成
	output wire m_alu_valid,
	input wire m_alu_ready,
	
	// 分支确认单元执行请求
	output wire[31:0] m_bcu_pc_of_inst, // 指令对应的PC
	output wire[31:0] m_bcu_pc_jump, // 跳转后的PC
	output wire m_bcu_prdt_jump, // 是否预测跳转
	output wire m_bcu_valid,
	input wire m_bcu_ready,
	
	// LSU执行请求
	output wire m_ls_sel, // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	output wire[2:0] m_ls_type, // 访存类型
	output wire[4:0] m_rd_id_for_ld, // 用于加载的目标寄存器的索引
	output wire m_lsu_valid,
	input wire m_lsu_ready,
	
	// CSR原子读写单元执行请求
	output wire[11:0] m_csr_addr, // CSR地址
	output wire[1:0] m_csr_upd_type, // CSR更新类型
	output wire[31:0] m_csr_upd_mask_v, // CSR更新掩码或更新值
	output wire m_csr_rw_valid,
	input wire m_csr_rw_ready,
	
	// 乘法器执行请求
	output wire[32:0] m_mul_op_a, // 操作数A
	output wire[32:0] m_mul_op_b, // 操作数B
	output wire m_mul_res_sel, // 乘法结果选择(1'b0 -> 低32位, 1'b1 -> 高32位)
	output wire m_mul_valid,
	input wire m_mul_ready,
	
	// 除法器执行请求
	output wire[32:0] m_div_op_a, // 操作数A
	output wire[32:0] m_div_op_b, // 操作数B
	output wire m_div_rem_sel, // 除法/求余选择(1'b0 -> 除法, 1'b1 -> 求余)
	output wire m_div_valid,
	input wire m_div_ready
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
		
		.raw_dpc_check_rs1_id(raw_dpc_check_rs1_id),
		.rs1_raw_dpc(rs1_raw_dpc),
		.raw_dpc_check_rs2_id(raw_dpc_check_rs2_id),
		.rs2_raw_dpc(rs2_raw_dpc),
		.raw_dpc_check_rd_id(raw_dpc_check_rd_id),
		.rd_raw_dpc(rd_raw_dpc),
		
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
		.s_if_res_valid(s_if_res_valid),
		.s_if_res_ready(s_if_res_ready),
		
		.m_alu_op_mode(m_alu_op_mode),
		.m_alu_op1(m_alu_op1),
		.m_alu_op2(m_alu_op2),
		.m_alu_addr_gen_sel(m_alu_addr_gen_sel),
		.m_alu_valid(m_alu_valid),
		.m_alu_ready(m_alu_ready),
		
		.m_bcu_pc_of_inst(m_bcu_pc_of_inst),
		.m_bcu_pc_jump(m_bcu_pc_jump),
		.m_bcu_prdt_jump(m_bcu_prdt_jump),
		.m_bcu_valid(m_bcu_valid),
		.m_bcu_ready(m_bcu_ready),
		
		.m_ls_sel(m_ls_sel),
		.m_ls_type(m_ls_type),
		.m_rd_id_for_ld(m_rd_id_for_ld),
		.m_lsu_valid(m_lsu_valid),
		.m_lsu_ready(m_lsu_ready),
		
		.m_csr_addr(m_csr_addr),
		.m_csr_upd_type(m_csr_upd_type),
		.m_csr_upd_mask_v(m_csr_upd_mask_v),
		.m_csr_rw_valid(m_csr_rw_valid),
		.m_csr_rw_ready(m_csr_rw_ready),
		
		.m_mul_op_a(m_mul_op_a),
		.m_mul_op_b(m_mul_op_b),
		.m_mul_res_sel(m_mul_res_sel),
		.m_mul_valid(m_mul_valid),
		.m_mul_ready(m_mul_ready),
		
		.m_div_op_a(m_div_op_a),
		.m_div_op_b(m_div_op_b),
		.m_div_rem_sel(m_div_rem_sel),
		.m_div_valid(m_div_valid),
		.m_div_ready(m_div_ready)
	);
	
endmodule
