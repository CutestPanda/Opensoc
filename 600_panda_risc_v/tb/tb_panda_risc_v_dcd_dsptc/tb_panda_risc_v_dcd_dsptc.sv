`timescale 1ns / 1ps

`include "uvm_macros.svh"

import uvm_pkg::*;

`include "test_cases.sv"
`include "envs.sv"
`include "agents.sv"
`include "sequencers.sv"
`include "drivers.sv"
`include "monitors.sv"
`include "transactions.sv"

module tb_panda_risc_v_dcd_dsptc();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer inst_id_width = 4; // 指令编号的位宽
	// 时钟和复位配置
	localparam real clk_p = 10.0; // 时钟周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 时钟和复位 **/
	reg clk;
	reg rst_n;
	
	initial
	begin
		clk <= 1'b1;
		
		forever
		begin
			# (clk_p / 2) clk <= ~clk;
		end
	end
	
	initial begin
		rst_n <= 1'b0;
		
		# (clk_p * 10 + simulation_delay);
		
		rst_n <= 1'b1;
	end
	
	/** 接口 **/
	AXIS #(.out_drive_t(simulation_delay), .data_width(128), .user_width(4)) m_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(160), .user_width(0)) s0_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(160), .user_width(0)) s1_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(160), .user_width(0)) s2_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(160), .user_width(0)) s3_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(160), .user_width(0)) s4_axis_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(128), .user_width(4)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(128), .user_width(4)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m_axis_if.monitor);
		
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(160), .user_width(0)).slave)::set(null, 
			"uvm_test_top.env.agt2.drv", "axis_if", s0_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(160), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axis_if", s0_axis_if.monitor);
		
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(160), .user_width(0)).slave)::set(null, 
			"uvm_test_top.env.agt3.drv", "axis_if", s1_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(160), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt3.mon", "axis_if", s1_axis_if.monitor);
		
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(160), .user_width(0)).slave)::set(null, 
			"uvm_test_top.env.agt4.drv", "axis_if", s2_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(160), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt4.mon", "axis_if", s2_axis_if.monitor);
		
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(160), .user_width(0)).slave)::set(null, 
			"uvm_test_top.env.agt5.drv", "axis_if", s3_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(160), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt5.mon", "axis_if", s3_axis_if.monitor);
		
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(160), .user_width(0)).slave)::set(null, 
			"uvm_test_top.env.agt6.drv", "axis_if", s4_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(160), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt6.mon", "axis_if", s4_axis_if.monitor);
		
		// 启动testcase
		run_test("DcdDsptcCase0Test");
	end
	
	/** 复位处理 **/
	// 软件复位请求
	reg sw_reset;
	// 系统复位输入
	wire sys_resetn;
	// 系统复位请求
	wire sys_reset_req;
	
	panda_risc_v_reset #(
		.simulation_delay(simulation_delay)
	)panda_risc_v_reset_u(
		.clk(clk),
		
		.ext_resetn(rst_n),
		.sw_reset(sw_reset),
		
		.sys_resetn(sys_resetn),
		.sys_reset_req(sys_reset_req)
	);
	
	/** 待测模块 **/
	// 冲刷请求
	reg flush_req;
	// 数据相关性
	wire[4:0] raw_dpc_check_rs1_id; // 待检查RAW相关性的RS1索引
	reg rs1_raw_dpc; // RS1有RAW相关性(标志)
	wire[4:0] raw_dpc_check_rs2_id; // 待检查RAW相关性的RS2索引
	reg rs2_raw_dpc; // RS2有RAW相关性(标志)
	// 仅检查待派遣指令的RD索引是否与未交付长指令的RD索引冲突!
	wire[4:0] waw_dpc_check_rd_id; // 待检查WAW相关性的RD索引
	reg rd_waw_dpc; // RD有WAW相关性(标志)
	// 译码器给出的通用寄存器堆读端口#0
	wire dcd_reg_file_rd_p0_req; // 读请求
	wire[4:0] dcd_reg_file_rd_p0_addr; // 读地址
	wire dcd_reg_file_rd_p0_grant; // 读许可
	wire[31:0] dcd_reg_file_rd_p0_dout; // 读数据
	// 译码器给出的通用寄存器堆读端口#1
	wire dcd_reg_file_rd_p1_req; // 读请求
	wire[4:0] dcd_reg_file_rd_p1_addr; // 读地址
	wire dcd_reg_file_rd_p1_grant; // 读许可
	wire[31:0] dcd_reg_file_rd_p1_dout; // 读数据
	// 取指结果
	wire[127:0] s_if_res_data; // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	wire[3:0] s_if_res_msg; // 取指附加信息({是否预测跳转(1bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	reg[inst_id_width-1:0] s_if_res_id; // 指令编号
	wire s_if_res_valid;
	wire s_if_res_ready;
	// ALU执行请求
	wire[3:0] m_alu_op_mode; // 操作类型
	wire[31:0] m_alu_op1; // 操作数1
	wire[31:0] m_alu_op2; // 操作数2
	wire m_alu_addr_gen_sel; // ALU是否用于访存地址生成
	wire[2:0] m_alu_err_code; // 指令的错误类型(3'b000 -> 正常, 3'b001 -> 非法指令, 
	                          //     3'b010 -> 指令地址非对齐, 3'b011 -> 指令总线访问失败, 
							  //     3'b110 -> 读存储映射地址非对齐, 3'b111 -> 写存储映射地址非对齐)
	wire[31:0] m_alu_pc_of_inst; // 指令对应的PC
	wire m_alu_is_b_inst; // 是否B指令
	wire m_alu_is_ecall_inst; // 是否ECALL指令
	wire m_alu_is_mret_inst; // 是否MRET指令
	wire m_alu_is_csr_rw_inst; // 是否CSR读写指令
	wire m_alu_is_fence_i_inst; // 是否FENCE.I指令
	wire[31:0] m_alu_brc_pc_upd; // 分支预测失败时修正的PC
	wire m_alu_prdt_jump; // 是否预测跳转
	wire[4:0] m_alu_rd_id; // RD索引
	wire m_alu_rd_vld; // 是否需要写RD
	wire m_alu_is_long_inst; // 是否长指令
	wire[inst_id_width-1:0] m_alu_inst_id; // 指令编号
	wire m_alu_valid;
	wire m_alu_ready;
	// LSU执行请求
	wire m_ls_sel; // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	wire[2:0] m_ls_type; // 访存类型
	wire[4:0] m_rd_id_for_ld; // 用于加载的目标寄存器的索引
	wire[31:0] m_ls_din; // 写数据
	wire[inst_id_width-1:0] m_lsu_inst_id; // 指令编号
	wire m_lsu_valid;
	wire m_lsu_ready;
	// CSR原子读写单元执行请求
	wire[11:0] m_csr_addr; // CSR地址
	wire[1:0] m_csr_upd_type; // CSR更新类型
	wire[31:0] m_csr_upd_mask_v; // CSR更新掩码或更新值
	wire[4:0] m_csr_rw_rd_id; // RD索引
	wire[inst_id_width-1:0] m_csr_rw_inst_id; // 指令编号
	wire m_csr_rw_valid;
	wire m_csr_rw_ready;
	// 乘法器执行请求
	wire[32:0] m_mul_op_a; // 操作数A
	wire[32:0] m_mul_op_b; // 操作数B
	wire m_mul_res_sel; // 乘法结果选择(1'b0 -> 低32位, 1'b1 -> 高32位)
	wire[4:0] m_mul_rd_id; // RD索引
	wire[inst_id_width-1:0] m_mul_inst_id; // 指令编号
	wire m_mul_valid;
	wire m_mul_ready;
	// 除法器执行请求
	wire[32:0] m_div_op_a; // 操作数A
	wire[32:0] m_div_op_b; // 操作数B
	wire m_div_rem_sel; // 除法/求余选择(1'b0 -> 除法, 1'b1 -> 求余)
	wire[4:0] m_div_rd_id; // RD索引
	wire[inst_id_width-1:0] m_div_inst_id; // 指令编号
	wire m_div_valid;
	wire m_div_ready;
	
	assign s_if_res_data[31:0] = m_axis_if.data[31:0];
	assign s_if_res_data[127:96] = m_axis_if.data[127:96];
	assign s_if_res_msg = m_axis_if.user;
	assign s_if_res_valid = m_axis_if.valid;
	assign m_axis_if.ready = s_if_res_ready;
	
	assign s0_axis_if.data = {3'dx, 4'd0, m_alu_inst_id, 
		m_alu_op_mode, m_alu_op1, m_alu_op2, m_alu_addr_gen_sel, m_alu_err_code, 
		m_alu_pc_of_inst, m_alu_is_b_inst, m_alu_is_ecall_inst, m_alu_is_mret_inst, m_alu_is_csr_rw_inst, m_alu_is_fence_i_inst, 
		m_alu_brc_pc_upd, m_alu_prdt_jump, 
		m_alu_rd_id, m_alu_rd_vld, m_alu_is_long_inst};
	assign s0_axis_if.valid = m_alu_valid;
	assign s0_axis_if.last = 1'b1;
	assign m_alu_ready = s0_axis_if.ready;
	
	assign s1_axis_if.data = {111'dx, 4'd0, m_lsu_inst_id, m_ls_sel, m_ls_type, m_rd_id_for_ld, m_ls_din};
	assign s1_axis_if.valid = m_lsu_valid;
	assign s1_axis_if.last = 1'b1;
	assign m_lsu_ready = s1_axis_if.ready;
	
	assign s2_axis_if.data = {101'dx, 4'd0, m_csr_rw_inst_id, m_csr_addr, m_csr_upd_type, m_csr_upd_mask_v, m_csr_rw_rd_id};
	assign s2_axis_if.valid = m_csr_rw_valid;
	assign s2_axis_if.last = 1'b1;
	assign m_csr_rw_ready = s2_axis_if.ready;
	
	assign s3_axis_if.data = {80'dx, 4'd0, m_mul_inst_id, m_mul_op_a, m_mul_op_b, m_mul_res_sel, m_mul_rd_id};
	assign s3_axis_if.valid = m_mul_valid;
	assign s3_axis_if.last = 1'b1;
	assign m_mul_ready = s3_axis_if.ready;
	
	assign s4_axis_if.data = {80'dx, 4'd0, m_div_inst_id, m_div_op_a, m_div_op_b, m_div_rem_sel, m_div_rd_id};
	assign s4_axis_if.valid = m_div_valid;
	assign s4_axis_if.last = 1'b1;
	assign m_div_ready = s4_axis_if.ready;
	
	panda_risc_v_dcd_dsptc #(
		.inst_id_width(inst_id_width),
		.simulation_delay(simulation_delay)
	)panda_risc_v_dcd_dsptc_u(
		.clk(clk),
		.sys_resetn(sys_resetn),
		
		.sys_reset_req(sys_reset_req),
		.flush_req(flush_req),
		
		.lsu_idle(1'b1),
		
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
		
		.dpc_trace_dcd_inst_id(),
		.dpc_trace_dcd_valid(),
		.dpc_trace_dsptc_inst_id(),
		.dpc_trace_dsptc_valid()
	);
	
	/** 指令编号 **/
	always @(posedge clk or negedge sys_resetn)
	begin
		if(~sys_resetn)
			s_if_res_id <= 0;
		else if(s_if_res_valid & s_if_res_ready)
			s_if_res_id <= # simulation_delay s_if_res_id + 1;
	end
	
	/** 软件复位请求/冲刷请求 **/
	initial
	begin
		sw_reset <= 1'b0;
		flush_req <= 1'b0;
	end
	
	/** 数据相关性 **/
	// RS1有RAW相关性(标志)
	initial
	begin
		rs1_raw_dpc <= 1'b0;
		
		forever
		begin
			@(posedge clk iff sys_resetn);
			
			randcase
				5: rs1_raw_dpc <= # simulation_delay 1'b0;
				3: rs1_raw_dpc <= # simulation_delay 1'b1;
			endcase
		end
	end
	
	// RS2有RAW相关性(标志)
	initial
	begin
		rs2_raw_dpc <= 1'b0;
		
		forever
		begin
			@(posedge clk iff sys_resetn);
			
			randcase
				5: rs2_raw_dpc <= # simulation_delay 1'b0;
				3: rs2_raw_dpc <= # simulation_delay 1'b1;
			endcase
		end
	end
	
	// RD有WAW相关性(标志)
	initial
	begin
		rd_waw_dpc <= 1'b0;
		
		forever
		begin
			@(posedge clk iff sys_resetn);
			
			randcase
				5: rd_waw_dpc <= # simulation_delay 1'b0;
				3: rd_waw_dpc <= # simulation_delay 1'b1;
			endcase
		end
	end
	
	/** 译码器给出的通用寄存器堆读端口#0 **/
	req_grant_model #(
		.payload_width(32),
		.simulation_delay(simulation_delay)
	)req_grant_model_u0(
		.clk(clk),
		.rst_n(sys_resetn),
		
		.req(dcd_reg_file_rd_p0_req),
		.grant(dcd_reg_file_rd_p0_grant),
		.payload(dcd_reg_file_rd_p0_dout)
	);
	
	/** 译码器给出的通用寄存器堆读端口#1 **/
	req_grant_model #(
		.payload_width(32),
		.simulation_delay(simulation_delay)
	)req_grant_model_u1(
		.clk(clk),
		.rst_n(sys_resetn),
		
		.req(dcd_reg_file_rd_p1_req),
		.grant(dcd_reg_file_rd_p1_grant),
		.payload(dcd_reg_file_rd_p1_dout)
	);
	
	/** 打包的预译码信息 **/
	panda_risc_v_pre_decoder panda_risc_v_pre_decoder_u(
		.inst(s_if_res_data[31:0]),
		
		.pre_decoding_msg_packeted(s_if_res_data[95:32])
	);
	
endmodule
