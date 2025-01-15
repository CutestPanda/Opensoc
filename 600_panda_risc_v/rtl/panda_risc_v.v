`timescale 1ns / 1ps
/********************************************************************
本模块: 小胖达RISC-V CPU核

描述:
小胖达RISC-V处理器核顶层模块

注意：
暂未实现ALU/CSR原子读写单元的数据旁路
由于从取指队列到指令队列的缓存深度较大, 指令数据相关性跟踪表满标志(dpc_trace_tb_full)可能不安全

协议:
ICB MASTER

作者: 陈家耀
日期: 2025/01/15
********************************************************************/


module panda_risc_v #(
	// 复位时的PC
	parameter RST_PC = 32'h0000_0000,
	// 指令总线控制单元配置
	parameter integer imem_access_timeout_th = 16, // 指令总线访问超时周期数(必须>=1)
	parameter integer inst_addr_alignment_width = 32, // 指令地址对齐位宽(16 | 32)
	// LSU配置
	parameter integer dbus_access_timeout_th = 16, // 数据总线访问超时周期数(必须>=1)
	parameter icb_zero_latency_supported = "false", // 是否支持零响应时延的ICB主机
	// CSR配置
	parameter en_expt_vec_vectored = "true", // 是否使能异常处理的向量链接模式
	parameter en_performance_monitor = "true", // 是否使能性能监测相关的CSR
	parameter init_mtvec_base = 30'd0, // mtvec状态寄存器BASE域复位值
	parameter init_mcause_interrupt = 1'b0, // mcause状态寄存器Interrupt域复位值
	parameter init_mcause_exception_code = 31'd16, // mcause状态寄存器Exception Code域复位值
	parameter init_misa_mxl = 2'b01, // misa状态寄存器MXL域复位值
	parameter init_misa_extensions = 26'b00_0000_0000_0001_0001_0000_0000, // misa状态寄存器Extensions域复位值
	parameter init_mvendorid_bank = 25'h0_00_00_00, // mvendorid状态寄存器Bank域复位值
	parameter init_mvendorid_offset = 7'h00, // mvendorid状态寄存器Offset域复位值
	parameter init_marchid = 32'h00_00_00_00, // marchid状态寄存器复位值
	parameter init_mimpid = 32'h31_2E_30_30, // mimpid状态寄存器复位值
	parameter init_mhartid = 32'h00_00_00_00, // mhartid状态寄存器复位值
	// 数据相关性监测器配置
	parameter integer dpc_trace_inst_n = 4, // 执行数据相关性跟踪的指令条数
	parameter integer inst_id_width = 4, // 指令编号的位宽
	parameter en_alu_csr_rw_bypass = "true", // 是否使能ALU/CSR原子读写单元的数据旁路
	// 仿真配置
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟
	input wire clk,
	// 系统复位输入
	input wire sys_resetn,
	
	// 系统复位请求
	input wire sys_reset_req,
	
	// 指令ICB主机
	// 命令通道
	output wire[31:0] m_icb_cmd_inst_addr,
	output wire m_icb_cmd_inst_read, // const -> 1'b1
	output wire[31:0] m_icb_cmd_inst_wdata, // const -> 32'hxxxx_xxxx
	output wire[3:0] m_icb_cmd_inst_wmask, // const -> 4'b0000
	output wire m_icb_cmd_inst_valid,
	input wire m_icb_cmd_inst_ready,
	// 响应通道
	input wire[31:0] m_icb_rsp_inst_rdata,
	input wire m_icb_rsp_inst_err,
	input wire m_icb_rsp_inst_valid,
	output wire m_icb_rsp_inst_ready,
	
	// 数据ICB主机
	// 命令通道
	output wire[31:0] m_icb_cmd_data_addr,
	output wire m_icb_cmd_data_read,
	output wire[31:0] m_icb_cmd_data_wdata,
	output wire[3:0] m_icb_cmd_data_wmask,
	output wire m_icb_cmd_data_valid,
	input wire m_icb_cmd_data_ready,
	// 响应通道
	input wire[31:0] m_icb_rsp_data_rdata,
	input wire m_icb_rsp_data_err,
	input wire m_icb_rsp_data_valid,
	output wire m_icb_rsp_data_ready,
	
	// 指令总线访问超时标志
	output wire ibus_timeout,
	// 数据总线访问超时标志
	output wire dbus_timeout,
	
	// 中断请求
	// 注意: 中断请求保持有效直到中断清零!
	input wire sw_itr_req, // 软件中断请求
	input wire tmr_itr_req, // 计时器中断请求
	input wire ext_itr_req // 外部中断请求
);
	
	/** 取指单元 **/
	// 冲刷/复位控制
	wire flush_req; // 冲刷请求
	wire[31:0] flush_addr; // 冲刷地址
	wire rst_ack; // 复位应答
	wire flush_ack; // 冲刷应答
	// 指令存储器访问请求发起阶段数据相关性检查
	wire[4:0] imem_access_rs1_id; // 待检查RAW相关性的RS1索引
	wire imem_access_rs1_raw_dpc; // RS1有RAW相关性(标志)
	// 专用于JALR指令的通用寄存器堆读端口
	wire[31:0] jalr_x1_v; // 通用寄存器#1读结果
	// JALR指令读基址给出的通用寄存器堆读端口#0
	wire jalr_reg_file_rd_p0_req; // 读请求
	wire[4:0] jalr_reg_file_rd_p0_addr; // 读地址
	wire jalr_reg_file_rd_p0_grant; // 读许可
	wire[31:0] jalr_reg_file_rd_p0_dout; // 读数据
	// 取指结果
	wire[127:0] m_if_res_data; // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	wire[3:0] m_if_res_msg; // 取指附加信息({是否预测跳转(1bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	wire[inst_id_width-1:0] m_if_res_id; // 指令编号
	wire m_if_res_valid;
	wire m_if_res_ready;
	// 数据相关性跟踪(指令进入取指队列)
	wire has_processing_imem_access_req; // 是否有滞外的指令存储器访问请求
	wire dpc_trace_tb_full; // 指令数据相关性跟踪表满标志
	wire[31:0] dpc_trace_enter_ifq_inst; // 取到的指令
	wire[4:0] dpc_trace_enter_ifq_rd_id; // RD索引
	wire dpc_trace_enter_ifq_rd_vld; // 是否需要写RD
	wire dpc_trace_enter_ifq_is_long_inst; // 是否长指令
	wire[inst_id_width-1:0] dpc_trace_enter_ifq_inst_id; // 指令编号
	wire dpc_trace_enter_ifq_valid;
	
	panda_risc_v_ifu #(
		.imem_access_timeout_th(imem_access_timeout_th),
		.inst_addr_alignment_width(inst_addr_alignment_width),
		.RST_PC(RST_PC),
		.inst_id_width(inst_id_width),
		.simulation_delay(simulation_delay)
	)panda_risc_v_ifu_u(
		.clk(clk),
		.sys_resetn(sys_resetn),
		
		.sys_reset_req(sys_reset_req),
		.flush_req(flush_req),
		.flush_addr(flush_addr),
		.rst_ack(rst_ack), // 注意: 未使用的信号!
		.flush_ack(flush_ack),
		
		.rs1_id(imem_access_rs1_id),
		.rs1_raw_dpc(imem_access_rs1_raw_dpc),
		
		.jalr_x1_v(jalr_x1_v),
		.jalr_reg_file_rd_p0_req(jalr_reg_file_rd_p0_req),
		.jalr_reg_file_rd_p0_addr(jalr_reg_file_rd_p0_addr),
		.jalr_reg_file_rd_p0_grant(jalr_reg_file_rd_p0_grant),
		.jalr_reg_file_rd_p0_dout(jalr_reg_file_rd_p0_dout),
		
		.m_icb_cmd_inst_addr(m_icb_cmd_inst_addr),
		.m_icb_cmd_inst_read(m_icb_cmd_inst_read),
		.m_icb_cmd_inst_wdata(m_icb_cmd_inst_wdata),
		.m_icb_cmd_inst_wmask(m_icb_cmd_inst_wmask),
		.m_icb_cmd_inst_valid(m_icb_cmd_inst_valid),
		.m_icb_cmd_inst_ready(m_icb_cmd_inst_ready),
		.m_icb_rsp_inst_rdata(m_icb_rsp_inst_rdata),
		.m_icb_rsp_inst_err(m_icb_rsp_inst_err),
		.m_icb_rsp_inst_valid(m_icb_rsp_inst_valid),
		.m_icb_rsp_inst_ready(m_icb_rsp_inst_ready),
		
		.m_if_res_data(m_if_res_data),
		.m_if_res_msg(m_if_res_msg),
		.m_if_res_id(m_if_res_id),
		.m_if_res_valid(m_if_res_valid),
		.m_if_res_ready(m_if_res_ready),
		
		.ibus_timeout(ibus_timeout),
		
		.has_processing_imem_access_req(has_processing_imem_access_req),
		.dpc_trace_tb_full(dpc_trace_tb_full),
		.dpc_trace_enter_ifq_inst(dpc_trace_enter_ifq_inst),
		.dpc_trace_enter_ifq_rd_id(dpc_trace_enter_ifq_rd_id),
		.dpc_trace_enter_ifq_rd_vld(dpc_trace_enter_ifq_rd_vld),
		.dpc_trace_enter_ifq_is_long_inst(dpc_trace_enter_ifq_is_long_inst),
		.dpc_trace_enter_ifq_inst_id(dpc_trace_enter_ifq_inst_id),
		.dpc_trace_enter_ifq_valid(dpc_trace_enter_ifq_valid)
	);
	
	/** 译码/派遣单元 **/
	// 译码阶段数据相关性检查
	wire[4:0] dcd_raw_dpc_check_rs1_id; // 待检查RAW相关性的RS1索引
	wire dcd_rs1_raw_dpc; // RS1有RAW相关性(标志)
	wire[4:0] dcd_raw_dpc_check_rs2_id; // 待检查RAW相关性的RS2索引
	wire dcd_rs2_raw_dpc; // RS2有RAW相关性(标志)
	// 派遣阶段数据相关性检查
	wire[4:0] dsptc_waw_dpc_check_rd_id; // 待检查WAW相关性的RD索引
	wire dsptc_rd_waw_dpc; // RD有WAW相关性(标志)
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
	// IFU取指结果
	wire[127:0] s_if_res_data; // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	wire[3:0] s_if_res_msg; // 取指附加信息({是否预测跳转(1bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	wire[inst_id_width-1:0] s_if_res_id; // 指令编号
	wire s_if_res_valid;
	wire s_if_res_ready;
	// ALU执行请求
	wire[3:0] m_alu_op_mode; // 操作类型
	wire[31:0] m_alu_op1; // 操作数1
	wire[31:0] m_alu_op2; // 操作数2或取到的指令(若当前是非法指令)
	wire m_alu_addr_gen_sel; // ALU是否用于访存地址生成
	wire[2:0] m_alu_err_code; // 指令的错误类型(3'b000 -> 正常, 3'b001 -> 非法指令, 
	                          //     3'b010 -> 指令地址非对齐, 3'b011 -> 指令总线访问失败, 
							  //     3'b110 -> 读存储映射地址非对齐, 3'b111 -> 写存储映射地址非对齐)
	wire[31:0] m_alu_pc_of_inst; // 指令对应的PC
	wire m_alu_is_b_inst; // 是否B指令
	wire m_alu_is_ecall_inst; // 是否ECALL指令
	wire m_alu_is_mret_inst; // 是否MRET指令
	wire m_alu_is_csr_rw_inst; // 是否CSR读写指令
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
	// 数据相关性跟踪(指令被译码)
	wire[inst_id_width-1:0] dpc_trace_dcd_inst_id; // 指令编号
	wire dpc_trace_dcd_valid;
	// 数据相关性跟踪(指令被派遣)
	wire[inst_id_width-1:0] dpc_trace_dsptc_inst_id; // 指令编号
	wire dpc_trace_dsptc_valid;
	
	assign s_if_res_data = m_if_res_data;
	assign s_if_res_msg = m_if_res_msg;
	assign s_if_res_id = m_if_res_id;
	assign s_if_res_valid = m_if_res_valid;
	assign m_if_res_ready = s_if_res_ready;
	
	panda_risc_v_dcd_dsptc #(
		.inst_id_width(inst_id_width),
		.simulation_delay(simulation_delay)
	)panda_risc_v_dcd_dsptc_u(
		.clk(clk),
		.sys_resetn(sys_resetn),
		
		.sys_reset_req(sys_reset_req),
		.flush_req(flush_req),
		
		.raw_dpc_check_rs1_id(dcd_raw_dpc_check_rs1_id),
		.rs1_raw_dpc(dcd_rs1_raw_dpc),
		.raw_dpc_check_rs2_id(dcd_raw_dpc_check_rs2_id),
		.rs2_raw_dpc(dcd_rs2_raw_dpc),
		.waw_dpc_check_rd_id(dsptc_waw_dpc_check_rd_id),
		.rd_waw_dpc(dsptc_rd_waw_dpc),
		
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
		.m_alu_addr_gen_sel(m_alu_addr_gen_sel), // 注意: 未使用的信号!
		.m_alu_err_code(m_alu_err_code),
		.m_alu_pc_of_inst(m_alu_pc_of_inst),
		.m_alu_is_b_inst(m_alu_is_b_inst),
		.m_alu_is_ecall_inst(m_alu_is_ecall_inst),
		.m_alu_is_mret_inst(m_alu_is_mret_inst),
		.m_alu_is_csr_rw_inst(m_alu_is_csr_rw_inst),
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
	
	/** 执行单元 **/
	// ALU执行请求
	wire[3:0] s_alu_op_mode; // 操作类型
	wire[31:0] s_alu_op1; // 操作数1
	wire[31:0] s_alu_op2; // 操作数2或取到的指令(若当前是非法指令)
	wire[2:0] s_alu_err_code; // 指令的错误类型(3'b000 -> 正常, 3'b001 -> 非法指令, 
	                          //     3'b010 -> 指令地址非对齐, 3'b011 -> 指令总线访问失败, 
							  //     3'b110 -> 读存储映射地址非对齐, 3'b111 -> 写存储映射地址非对齐)
	wire[31:0] s_alu_pc_of_inst; // 指令对应的PC
	wire s_alu_is_b_inst; // 是否B指令
	wire s_alu_is_ecall_inst; // 是否ECALL指令
	wire s_alu_is_mret_inst; // 是否MRET指令
	wire s_alu_is_csr_rw_inst; // 是否CSR读写指令
	wire[31:0] s_alu_brc_pc_upd; // 分支预测失败时修正的PC
	wire s_alu_prdt_jump; // 是否预测跳转
	wire[4:0] s_alu_rd_id; // RD索引
	wire s_alu_rd_vld; // 是否需要写RD
	wire s_alu_is_long_inst; // 是否长指令
	wire[inst_id_width-1:0] s_alu_inst_id; // 指令编号
	wire s_alu_valid;
	wire s_alu_ready;
	// LSU执行请求
	wire s_ls_sel; // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	wire[2:0] s_ls_type; // 访存类型
	wire[4:0] s_rd_id_for_ld; // 用于加载的目标寄存器的索引
	wire[31:0] s_ls_din; // 写数据
	wire[inst_id_width-1:0] s_lsu_inst_id; // 指令编号
	wire s_lsu_valid;
	wire s_lsu_ready;
	// CSR原子读写单元执行请求
	wire[11:0] s_csr_addr; // CSR地址
	wire[1:0] s_csr_upd_type; // CSR更新类型
	wire[31:0] s_csr_upd_mask_v; // CSR更新掩码或更新值
	wire[4:0] s_csr_rw_rd_id; // RD索引
	wire[inst_id_width-1:0] s_csr_rw_inst_id; // 指令编号
	wire s_csr_rw_valid;
	wire s_csr_rw_ready;
	// 乘法器执行请求
	wire[32:0] s_mul_op_a; // 操作数A
	wire[32:0] s_mul_op_b; // 操作数B
	wire s_mul_res_sel; // 乘法结果选择(1'b0 -> 低32位, 1'b1 -> 高32位)
	wire[4:0] s_mul_rd_id; // RD索引
	wire[inst_id_width-1:0] s_mul_inst_id; // 指令编号
	wire s_mul_valid;
	wire s_mul_ready;
	// 除法器执行请求
	wire[32:0] s_div_op_a; // 操作数A
	wire[32:0] s_div_op_b; // 操作数B
	wire s_div_rem_sel; // 除法/求余选择(1'b0 -> 除法, 1'b1 -> 求余)
	wire[4:0] s_div_rd_id; // RD索引
	wire[inst_id_width-1:0] s_div_inst_id; // 指令编号
	wire s_div_valid;
	wire s_div_ready;
	// 数据相关性跟踪(指令退休)
	wire[inst_id_width-1:0] dpc_trace_retire_inst_id; // 指令编号
	wire dpc_trace_retire_valid;
	// ALU/CSR原子读写单元的数据旁路
	wire dcd_reg_file_rd_p0_bypass; // 需要旁路到译码器给出的通用寄存器堆读端口#0
	wire dcd_reg_file_rd_p1_bypass; // 需要旁路到译码器给出的通用寄存器堆读端口#1
	
	assign s_alu_op_mode = m_alu_op_mode;
	assign s_alu_op1 = m_alu_op1;
	assign s_alu_op2 = m_alu_op2;
	assign s_alu_err_code = m_alu_err_code;
	assign s_alu_pc_of_inst = m_alu_pc_of_inst;
	assign s_alu_is_b_inst = m_alu_is_b_inst;
	assign s_alu_is_ecall_inst = m_alu_is_ecall_inst;
	assign s_alu_is_mret_inst = m_alu_is_mret_inst;
	assign s_alu_is_csr_rw_inst = m_alu_is_csr_rw_inst;
	assign s_alu_brc_pc_upd = m_alu_brc_pc_upd;
	assign s_alu_prdt_jump = m_alu_prdt_jump;
	assign s_alu_rd_id = m_alu_rd_id;
	assign s_alu_rd_vld = m_alu_rd_vld;
	assign s_alu_is_long_inst = m_alu_is_long_inst;
	assign s_alu_inst_id = m_alu_inst_id;
	assign s_alu_valid = m_alu_valid;
	assign m_alu_ready = s_alu_ready;
	
	assign s_ls_sel = m_ls_sel;
	assign s_ls_type = m_ls_type;
	assign s_rd_id_for_ld = m_rd_id_for_ld;
	assign s_ls_din = m_ls_din;
	assign s_lsu_inst_id = m_lsu_inst_id;
	assign s_lsu_valid = m_lsu_valid;
	assign m_lsu_ready = s_lsu_ready;
	
	assign s_csr_addr = m_csr_addr;
	assign s_csr_upd_type = m_csr_upd_type;
	assign s_csr_upd_mask_v = m_csr_upd_mask_v;
	assign s_csr_rw_rd_id = m_csr_rw_rd_id;
	assign s_csr_rw_inst_id = m_csr_rw_inst_id;
	assign s_csr_rw_valid = m_csr_rw_valid;
	assign m_csr_rw_ready = s_csr_rw_ready;
	
	assign s_mul_op_a = m_mul_op_a;
	assign s_mul_op_b = m_mul_op_b;
	assign s_mul_res_sel = m_mul_res_sel;
	assign s_mul_rd_id = m_mul_rd_id;
	assign s_mul_inst_id = m_mul_inst_id;
	assign s_mul_valid = m_mul_valid;
	assign m_mul_ready = s_mul_ready;
	
	assign s_div_op_a = m_div_op_a;
	assign s_div_op_b = m_div_op_b;
	assign s_div_rem_sel = m_div_rem_sel;
	assign s_div_rd_id = m_div_rd_id;
	assign s_div_inst_id = m_div_inst_id;
	assign s_div_valid = m_div_valid;
	assign m_div_ready = s_div_ready;
	
	panda_risc_v_exu #(
		.inst_id_width(inst_id_width),
		.en_alu_csr_rw_bypass(en_alu_csr_rw_bypass),
		.dbus_access_timeout_th(dbus_access_timeout_th),
		.icb_zero_latency_supported(icb_zero_latency_supported),
		.en_expt_vec_vectored(en_expt_vec_vectored),
		.en_performance_monitor(en_performance_monitor),
		.init_mtvec_base(init_mtvec_base),
		.init_mcause_interrupt(init_mcause_interrupt),
		.init_mcause_exception_code(init_mcause_exception_code),
		.init_misa_mxl(init_misa_mxl),
		.init_misa_extensions(init_misa_extensions),
		.init_mvendorid_bank(init_mvendorid_bank),
		.init_mvendorid_offset(init_mvendorid_offset),
		.init_marchid(init_marchid),
		.init_mimpid(init_mimpid),
		.init_mhartid(init_mhartid),
		.simulation_delay(simulation_delay)
	)panda_risc_v_exu_u(
		.clk(clk),
		.sys_resetn(sys_resetn),
		
		.dcd_reg_file_rd_p0_req(dcd_reg_file_rd_p0_req),
		.dcd_reg_file_rd_p0_addr(dcd_reg_file_rd_p0_addr),
		.dcd_reg_file_rd_p0_grant(dcd_reg_file_rd_p0_grant),
		.dcd_reg_file_rd_p0_dout(dcd_reg_file_rd_p0_dout),
		.dcd_reg_file_rd_p1_req(dcd_reg_file_rd_p1_req),
		.dcd_reg_file_rd_p1_addr(dcd_reg_file_rd_p1_addr),
		.dcd_reg_file_rd_p1_grant(dcd_reg_file_rd_p1_grant),
		.dcd_reg_file_rd_p1_dout(dcd_reg_file_rd_p1_dout),
		
		.jalr_x1_v(jalr_x1_v),
		.jalr_reg_file_rd_p0_req(jalr_reg_file_rd_p0_req),
		.jalr_reg_file_rd_p0_addr(jalr_reg_file_rd_p0_addr),
		.jalr_reg_file_rd_p0_grant(jalr_reg_file_rd_p0_grant),
		.jalr_reg_file_rd_p0_dout(jalr_reg_file_rd_p0_dout),
		
		.s_alu_op_mode(s_alu_op_mode),
		.s_alu_op1(s_alu_op1),
		.s_alu_op2(s_alu_op2),
		.s_alu_err_code(s_alu_err_code),
		.s_alu_pc_of_inst(s_alu_pc_of_inst),
		.s_alu_is_b_inst(s_alu_is_b_inst),
		.s_alu_is_ecall_inst(s_alu_is_ecall_inst),
		.s_alu_is_mret_inst(s_alu_is_mret_inst),
		.s_alu_is_csr_rw_inst(s_alu_is_csr_rw_inst),
		.s_alu_brc_pc_upd(s_alu_brc_pc_upd),
		.s_alu_prdt_jump(s_alu_prdt_jump),
		.s_alu_rd_id(s_alu_rd_id),
		.s_alu_rd_vld(s_alu_rd_vld),
		.s_alu_is_long_inst(s_alu_is_long_inst),
		.s_alu_inst_id(s_alu_inst_id),
		.s_alu_valid(s_alu_valid),
		.s_alu_ready(s_alu_ready),
		
		.s_ls_sel(s_ls_sel),
		.s_ls_type(s_ls_type),
		.s_rd_id_for_ld(s_rd_id_for_ld),
		.s_ls_din(s_ls_din),
		.s_lsu_inst_id(s_lsu_inst_id),
		.s_lsu_valid(s_lsu_valid),
		.s_lsu_ready(s_lsu_ready),
		
		.s_csr_addr(s_csr_addr),
		.s_csr_upd_type(s_csr_upd_type),
		.s_csr_upd_mask_v(s_csr_upd_mask_v),
		.s_csr_rw_rd_id(s_csr_rw_rd_id),
		.s_csr_rw_inst_id(s_csr_rw_inst_id),
		.s_csr_rw_valid(s_csr_rw_valid),
		.s_csr_rw_ready(s_csr_rw_ready),
		
		.s_mul_op_a(s_mul_op_a),
		.s_mul_op_b(s_mul_op_b),
		.s_mul_res_sel(s_mul_res_sel),
		.s_mul_rd_id(s_mul_rd_id),
		.s_mul_inst_id(s_mul_inst_id),
		.s_mul_valid(s_mul_valid),
		.s_mul_ready(s_mul_ready),
		
		.s_div_op_a(s_div_op_a),
		.s_div_op_b(s_div_op_b),
		.s_div_rem_sel(s_div_rem_sel),
		.s_div_rd_id(s_div_rd_id),
		.s_div_inst_id(s_div_inst_id),
		.s_div_valid(s_div_valid),
		.s_div_ready(s_div_ready),
		
		.m_icb_cmd_data_addr(m_icb_cmd_data_addr),
		.m_icb_cmd_data_read(m_icb_cmd_data_read),
		.m_icb_cmd_data_wdata(m_icb_cmd_data_wdata),
		.m_icb_cmd_data_wmask(m_icb_cmd_data_wmask),
		.m_icb_cmd_data_valid(m_icb_cmd_data_valid),
		.m_icb_cmd_data_ready(m_icb_cmd_data_ready),
		.m_icb_rsp_data_rdata(m_icb_rsp_data_rdata),
		.m_icb_rsp_data_err(m_icb_rsp_data_err),
		.m_icb_rsp_data_valid(m_icb_rsp_data_valid),
		.m_icb_rsp_data_ready(m_icb_rsp_data_ready),
		
		.dbus_timeout(dbus_timeout),
		
		.sw_itr_req(sw_itr_req),
		.tmr_itr_req(tmr_itr_req),
		.ext_itr_req(ext_itr_req),
		
		.flush_req(flush_req),
		.flush_ack(flush_ack),
		.flush_addr(flush_addr),
		
		.dpc_trace_retire_inst_id(dpc_trace_retire_inst_id),
		.dpc_trace_retire_valid(dpc_trace_retire_valid),
		
		.dcd_reg_file_rd_p0_bypass(dcd_reg_file_rd_p0_bypass),
		.dcd_reg_file_rd_p1_bypass(dcd_reg_file_rd_p1_bypass)
	);
	
	/** 数据相关性监测器 **/
	// 注意: 执行数据相关性跟踪的指令条数(dpc_trace_inst_n)根据从取指队列到指令队列的缓存深度来设置!
	panda_risc_v_data_dpc_monitor #(
		.dpc_trace_inst_n(dpc_trace_inst_n),
		.inst_id_width(inst_id_width),
		.en_alu_csr_rw_bypass(en_alu_csr_rw_bypass),
		.simulation_delay(simulation_delay)
	)panda_risc_v_data_dpc_monitor_u(
		.clk(clk),
		.resetn(sys_resetn),
		
		.sys_reset_req(sys_reset_req),
		.flush_req(flush_req),
		
		.has_processing_imem_access_req(has_processing_imem_access_req),
		.dpc_trace_tb_full(dpc_trace_tb_full),
		
		.imem_access_rs1_id(imem_access_rs1_id),
		.imem_access_rs1_raw_dpc(imem_access_rs1_raw_dpc),
		.dcd_raw_dpc_check_rs1_id(dcd_raw_dpc_check_rs1_id),
		.dcd_rs1_raw_dpc(dcd_rs1_raw_dpc),
		.dcd_raw_dpc_check_rs2_id(dcd_raw_dpc_check_rs2_id),
		.dcd_rs2_raw_dpc(dcd_rs2_raw_dpc),
		.dsptc_waw_dpc_check_rd_id(dsptc_waw_dpc_check_rd_id),
		.dsptc_rd_waw_dpc(dsptc_rd_waw_dpc),
		
		.dpc_trace_enter_ifq_inst(dpc_trace_enter_ifq_inst),
		.dpc_trace_enter_ifq_rd_id(dpc_trace_enter_ifq_rd_id),
		.dpc_trace_enter_ifq_rd_vld(dpc_trace_enter_ifq_rd_vld),
		.dpc_trace_enter_ifq_is_long_inst(dpc_trace_enter_ifq_is_long_inst),
		.dpc_trace_enter_ifq_inst_id(dpc_trace_enter_ifq_inst_id),
		.dpc_trace_enter_ifq_valid(dpc_trace_enter_ifq_valid),
		.dpc_trace_dcd_inst_id(dpc_trace_dcd_inst_id),
		.dpc_trace_dcd_valid(dpc_trace_dcd_valid),
		.dpc_trace_dsptc_inst_id(dpc_trace_dsptc_inst_id),
		.dpc_trace_dsptc_valid(dpc_trace_dsptc_valid),
		.dpc_trace_retire_inst_id(dpc_trace_retire_inst_id),
		.dpc_trace_retire_valid(dpc_trace_retire_valid),
		
		.dcd_reg_file_rd_p0_bypass(dcd_reg_file_rd_p0_bypass),
		.dcd_reg_file_rd_p1_bypass(dcd_reg_file_rd_p1_bypass)
	);
	
endmodule
