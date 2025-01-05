`timescale 1ns / 1ps
/********************************************************************
本模块: 执行单元

描述:
仅用于综合后时序评估

注意：
无

协议:
REQ/GRANT
REQ/ACK
ICB MASTER

作者: 陈家耀
日期: 2025/01/05
********************************************************************/


module panda_risc_v_exu_eva(
	// 时钟
	input wire clk,
	// 外部复位输入
	input wire ext_resetn,
	
	// 软件复位请求
	input wire sw_reset,
	
	// 译码器给出的通用寄存器堆读端口#0
	input wire dcd_reg_file_rd_p0_req, // 读请求
	input wire[4:0] dcd_reg_file_rd_p0_addr, // 读地址
	output wire dcd_reg_file_rd_p0_grant, // 读许可
	output wire[31:0] dcd_reg_file_rd_p0_dout, // 读数据
	// 译码器给出的通用寄存器堆读端口#1
	input wire dcd_reg_file_rd_p1_req, // 读请求
	input wire[4:0] dcd_reg_file_rd_p1_addr, // 读地址
	output wire dcd_reg_file_rd_p1_grant, // 读许可
	output wire[31:0] dcd_reg_file_rd_p1_dout, // 读数据
	
	// 专用于JALR指令的通用寄存器堆读端口
	output wire[31:0] jalr_x1_v, // 通用寄存器#1读结果
	// JALR指令读基址给出的通用寄存器堆读端口#0
	input wire jalr_reg_file_rd_p0_req, // 读请求
	input wire[4:0] jalr_reg_file_rd_p0_addr, // 读地址
	output wire jalr_reg_file_rd_p0_grant, // 读许可
	output wire[31:0] jalr_reg_file_rd_p0_dout, // 读数据
	
	// ALU执行请求
	input wire[3:0] s_alu_op_mode, // 操作类型
	input wire[31:0] s_alu_op1, // 操作数1
	input wire[31:0] s_alu_op2, // 操作数2或取到的指令(若当前是非法指令)
	input wire s_alu_addr_gen_sel, // ALU是否用于访存地址生成
	input wire[2:0] s_alu_err_code, // 指令的错误类型(3'b000 -> 正常, 3'b001 -> 非法指令, 
	                                //     3'b010 -> 指令地址非对齐, 3'b011 -> 指令总线访问失败, 
									//     3'b110 -> 读存储映射地址非对齐, 3'b111 -> 写存储映射地址非对齐)
	input wire[31:0] s_alu_pc_of_inst, // 指令对应的PC
	input wire s_alu_is_b_inst, // 是否B指令
	input wire s_alu_is_ecall_inst, // 是否ECALL指令
	input wire s_alu_is_mret_inst, // 是否MRET指令
	input wire s_alu_is_csr_rw_inst, // 是否CSR读写指令
	input wire[31:0] s_alu_brc_pc_upd, // 分支预测失败时修正的PC
	input wire s_alu_prdt_jump, // 是否预测跳转
	input wire[4:0] s_alu_rd_id, // RD索引
	input wire s_alu_rd_vld, // 是否需要写RD
	input wire s_alu_is_long_inst, // 是否长指令(L/S, 乘除法)
	input wire s_alu_valid,
	output wire s_alu_ready,
	
	// LSU执行请求
	input wire s_ls_sel, // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	input wire[2:0] s_ls_type, // 访存类型
	input wire[4:0] s_rd_id_for_ld, // 用于加载的目标寄存器的索引
	input wire[31:0] s_ls_din, // 写数据
	input wire s_lsu_valid,
	output wire s_lsu_ready,
	
	// CSR原子读写单元执行请求
	input wire[11:0] s_csr_addr, // CSR地址
	input wire[1:0] s_csr_upd_type, // CSR更新类型
	input wire[31:0] s_csr_upd_mask_v, // CSR更新掩码或更新值
	input wire[4:0] s_csr_rw_rd_id, // RD索引
	input wire s_csr_rw_valid,
	output wire s_csr_rw_ready,
	
	// 乘法器执行请求
	input wire[32:0] s_mul_op_a, // 操作数A
	input wire[32:0] s_mul_op_b, // 操作数B
	input wire s_mul_res_sel, // 乘法结果选择(1'b0 -> 低32位, 1'b1 -> 高32位)
	input wire[4:0] s_mul_rd_id, // RD索引
	input wire s_mul_valid,
	output wire s_mul_ready,
	
	// 除法器执行请求
	input wire[32:0] s_div_op_a, // 操作数A
	input wire[32:0] s_div_op_b, // 操作数B
	input wire s_div_rem_sel, // 除法/求余选择(1'b0 -> 除法, 1'b1 -> 求余)
	input wire[4:0] s_div_rd_id, // RD索引
	input wire s_div_valid,
	output wire s_div_ready,
	
	// 数据ICB主机
	// 命令通道
	output wire[31:0] m_icb_cmd_addr,
	output wire m_icb_cmd_read,
	output wire[31:0] m_icb_cmd_wdata,
	output wire[3:0] m_icb_cmd_wmask,
	output wire m_icb_cmd_valid,
	input wire m_icb_cmd_ready,
	// 响应通道
	input wire[31:0] m_icb_rsp_rdata,
	input wire m_icb_rsp_err,
	input wire m_icb_rsp_valid,
	output wire m_icb_rsp_ready,
	
	// 数据总线访问超时标志
	output wire dbus_timeout,
	
	// 中断请求
	// 注意: 中断请求保持有效直到中断清零!
	input wire sw_itr_req, // 软件中断请求
	input wire tmr_itr_req, // 计时器中断请求
	input wire ext_itr_req, // 外部中断请求
	
	// 冲刷控制
	output wire flush_req, // 冲刷请求
	input wire flush_ack, // 冲刷应答
	output wire[31:0] flush_addr // 冲刷地址
);
	
	// 系统复位输入
	wire sys_resetn;
	
	panda_risc_v_reset #(
		.simulation_delay(1)
	)panda_risc_v_reset_u(
		.clk(clk),
		
		.ext_resetn(ext_resetn),
		.sw_reset(sw_reset),
		
		.sys_resetn(sys_resetn),
		.sys_reset_req()
	);
	
	panda_risc_v_exu #(
		// LSU配置
		.dbus_access_timeout_th(16), // 数据总线访问超时周期数(必须>=1)
		.icb_zero_latency_supported("false"), // 是否支持零响应时延的ICB主机
		// CSR配置
		.en_expt_vec_vectored("true"), // 是否使能异常处理的向量链接模式
		.en_performance_monitor("true"), // 是否使能性能监测相关的CSR
		.init_mtvec_base(30'd0), // mtvec状态寄存器BASE域复位值
		.init_mcause_interrupt(1'b0), // mcause状态寄存器Interrupt域复位值
		.init_mcause_exception_code(31'd16), // mcause状态寄存器Exception Code域复位值
		.init_misa_mxl(2'b01), // misa状态寄存器MXL域复位值
		.init_misa_extensions(26'b00_0000_0000_0001_0001_0000_0000), // misa状态寄存器Extensions域复位值
		.init_mvendorid_bank(25'h0_00_00_00), // mvendorid状态寄存器Bank域复位值
		.init_mvendorid_offset(7'h00), // mvendorid状态寄存器Offset域复位值
		.init_marchid(32'h00_00_00_00), // marchid状态寄存器复位值
		.init_mimpid(32'h31_2E_30_30), // mimpid状态寄存器复位值
		.init_mhartid(32'h00_00_00_00), // mhartid状态寄存器复位值
		// 仿真配置
		.simulation_delay(1) // 仿真延时
	)panda_risc_v_exu_u(
		// 时钟和复位
		.clk(clk),
		.resetn(sys_resetn),
		
		// 译码器给出的通用寄存器堆读端口#0
		.dcd_reg_file_rd_p0_req(dcd_reg_file_rd_p0_req), // 读请求
		.dcd_reg_file_rd_p0_addr(dcd_reg_file_rd_p0_addr), // 读地址
		.dcd_reg_file_rd_p0_grant(dcd_reg_file_rd_p0_grant), // 读许可
		.dcd_reg_file_rd_p0_dout(dcd_reg_file_rd_p0_dout), // 读数据
		// 译码器给出的通用寄存器堆读端口#1
		.dcd_reg_file_rd_p1_req(dcd_reg_file_rd_p1_req), // 读请求
		.dcd_reg_file_rd_p1_addr(dcd_reg_file_rd_p1_addr), // 读地址
		.dcd_reg_file_rd_p1_grant(dcd_reg_file_rd_p1_grant), // 读许可
		.dcd_reg_file_rd_p1_dout(dcd_reg_file_rd_p1_dout), // 读数据
		
		// 专用于JALR指令的通用寄存器堆读端口
		.jalr_x1_v(jalr_x1_v), // 通用寄存器#1读结果
		// JALR指令读基址给出的通用寄存器堆读端口#0
		.jalr_reg_file_rd_p0_req(jalr_reg_file_rd_p0_req), // 读请求
		.jalr_reg_file_rd_p0_addr(jalr_reg_file_rd_p0_addr), // 读地址
		.jalr_reg_file_rd_p0_grant(jalr_reg_file_rd_p0_grant), // 读许可
		.jalr_reg_file_rd_p0_dout(jalr_reg_file_rd_p0_dout), // 读数据
		
		// ALU执行请求
		.s_alu_op_mode(s_alu_op_mode), // 操作类型
		.s_alu_op1(s_alu_op1), // 操作数1
		.s_alu_op2(s_alu_op2), // 操作数2或取到的指令(若当前是非法指令)
		.s_alu_addr_gen_sel(s_alu_addr_gen_sel), // ALU是否用于访存地址生成
		.s_alu_err_code(s_alu_err_code), // 指令的错误类型(3'b000 -> 正常, 3'b001 -> 非法指令, 
										 //     3'b010 -> 指令地址非对齐, 3'b011 -> 指令总线访问失败, 
										 //     3'b110 -> 读存储映射地址非对齐, 3'b111 -> 写存储映射地址非对齐)
		.s_alu_pc_of_inst(s_alu_pc_of_inst), // 指令对应的PC
		.s_alu_is_b_inst(s_alu_is_b_inst), // 是否B指令
		.s_alu_is_ecall_inst(s_alu_is_ecall_inst), // 是否ECALL指令
		.s_alu_is_mret_inst(s_alu_is_mret_inst), // 是否MRET指令
		.s_alu_is_csr_rw_inst(s_alu_is_csr_rw_inst), // 是否CSR读写指令
		.s_alu_brc_pc_upd(s_alu_brc_pc_upd), // 分支预测失败时修正的PC
		.s_alu_prdt_jump(s_alu_prdt_jump), // 是否预测跳转
		.s_alu_rd_id(s_alu_rd_id), // RD索引
		.s_alu_rd_vld(s_alu_rd_vld), // 是否需要写RD
		.s_alu_is_long_inst(s_alu_is_long_inst), // 是否长指令(L/S, 乘除法)
		.s_alu_valid(s_alu_valid),
		.s_alu_ready(s_alu_ready),
		
		// LSU执行请求
		.s_ls_sel(s_ls_sel), // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
		.s_ls_type(s_ls_type), // 访存类型
		.s_rd_id_for_ld(s_rd_id_for_ld), // 用于加载的目标寄存器的索引
		.s_ls_din(s_ls_din), // 写数据
		.s_lsu_valid(s_lsu_valid),
		.s_lsu_ready(s_lsu_ready),
		
		// CSR原子读写单元执行请求
		.s_csr_addr(s_csr_addr), // CSR地址
		.s_csr_upd_type(s_csr_upd_type), // CSR更新类型
		.s_csr_upd_mask_v(s_csr_upd_mask_v), // CSR更新掩码或更新值
		.s_csr_rw_rd_id(s_csr_rw_rd_id), // RD索引
		.s_csr_rw_valid(s_csr_rw_valid),
		.s_csr_rw_ready(s_csr_rw_ready),
		
		// 乘法器执行请求
		.s_mul_op_a(s_mul_op_a), // 操作数A
		.s_mul_op_b(s_mul_op_b), // 操作数B
		.s_mul_res_sel(s_mul_res_sel), // 乘法结果选择(1'b0 -> 低32位, 1'b1 -> 高32位)
		.s_mul_rd_id(s_mul_rd_id), // RD索引
		.s_mul_valid(s_mul_valid),
		.s_mul_ready(s_mul_ready),
		
		// 除法器执行请求
		.s_div_op_a(s_div_op_a), // 操作数A
		.s_div_op_b(s_div_op_b), // 操作数B
		.s_div_rem_sel(s_div_rem_sel), // 除法/求余选择(1'b0 -> 除法, 1'b1 -> 求余)
		.s_div_rd_id(s_div_rd_id), // RD索引
		.s_div_valid(s_div_valid),
		.s_div_ready(s_div_ready),
		
		// 数据ICB主机
		// 命令通道
		.m_icb_cmd_addr(m_icb_cmd_addr),
		.m_icb_cmd_read(m_icb_cmd_read),
		.m_icb_cmd_wdata(m_icb_cmd_wdata),
		.m_icb_cmd_wmask(m_icb_cmd_wmask),
		.m_icb_cmd_valid(m_icb_cmd_valid),
		.m_icb_cmd_ready(m_icb_cmd_ready),
		// 响应通道
		.m_icb_rsp_rdata(m_icb_rsp_rdata),
		.m_icb_rsp_err(m_icb_rsp_err),
		.m_icb_rsp_valid(m_icb_rsp_valid),
		.m_icb_rsp_ready(m_icb_rsp_ready),
		
		// 数据总线访问超时标志
		.dbus_timeout(dbus_timeout),
		
		// 中断请求
		// 注意: 中断请求保持有效直到中断清零!
		.sw_itr_req(sw_itr_req), // 软件中断请求
		.tmr_itr_req(tmr_itr_req), // 计时器中断请求
		.ext_itr_req(ext_itr_req), // 外部中断请求
		
		// 冲刷控制
		.flush_req(flush_req), // 冲刷请求
		.flush_ack(flush_ack), // 冲刷应答
		.flush_addr(flush_addr) // 冲刷地址
	);
	
endmodule
