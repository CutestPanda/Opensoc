`timescale 1ns / 1ps
/********************************************************************
本模块: 执行单元

描述:
LSU执行请求 ---------------> LSU ---------------------------------------------------------------------------> 数据ICB主机
                              |
							  |-------------------------来自LSU的写回请求------------------------->|
                                                                                                   |
ALU执行请求 ---------------> 交付单元 <------------------------m_pst_ready-------------------------|
                   |            ^<-----来自LSU的异常----- LSU异常缓存寄存器组 <-------LSU异常------|
			       |                                                                               |
			       --------> ALU -------------------------->|                                      |
                                                            |--来自ALU或CSR原子读写单元的写回请求->|----> 写回单元
CSR原子读写单元执行请求 ---> CSR原子读写单元 -------------->|                                      |          |
                                                                                                   |          |
乘法器执行请求 ------------> 多周期乘法器-------------------来自乘法器的写回请求------------------>|          |
                                                                                                   |      1个写端口
除法器执行请求 ------------> 多周期除法器-------------------来自除法器的写回请求------------------>|          |
                                                                                                              |
																											  V
                                                        通用寄存器堆读仲裁 <------------2个读端口-------通用寄存器堆
                                                                 |
																 |            |---> 译码器给出的通用寄存器堆读端口#0
																 |----------->|---> 译码器给出的通用寄存器堆读端口#1
																              |---> 专用于JALR指令的通用寄存器堆读端口
* 上图未画出冲刷控制和中断控制

注意：
无

协议:
REQ/GRANT
REQ/ACK
ICB MASTER

作者: 陈家耀
日期: 2025/01/14
********************************************************************/


module panda_risc_v_exu #(
	// 指令编号的位宽
	parameter integer inst_id_width = 4,
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
	// 仿真配置
    parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
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
	input wire s_alu_is_long_inst, // 是否长指令
	input wire[inst_id_width-1:0] s_alu_inst_id, // 指令编号
	input wire s_alu_valid,
	output wire s_alu_ready,
	
	// LSU执行请求
	input wire s_ls_sel, // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	input wire[2:0] s_ls_type, // 访存类型
	input wire[4:0] s_rd_id_for_ld, // 用于加载的目标寄存器的索引
	input wire[31:0] s_ls_din, // 写数据
	input wire[inst_id_width-1:0] s_lsu_inst_id, // 指令编号
	input wire s_lsu_valid,
	output wire s_lsu_ready,
	
	// CSR原子读写单元执行请求
	input wire[11:0] s_csr_addr, // CSR地址
	input wire[1:0] s_csr_upd_type, // CSR更新类型
	input wire[31:0] s_csr_upd_mask_v, // CSR更新掩码或更新值
	input wire[4:0] s_csr_rw_rd_id, // RD索引
	input wire[inst_id_width-1:0] s_csr_rw_inst_id, // 指令编号
	input wire s_csr_rw_valid,
	output wire s_csr_rw_ready,
	
	// 乘法器执行请求
	input wire[32:0] s_mul_op_a, // 操作数A
	input wire[32:0] s_mul_op_b, // 操作数B
	input wire s_mul_res_sel, // 乘法结果选择(1'b0 -> 低32位, 1'b1 -> 高32位)
	input wire[4:0] s_mul_rd_id, // RD索引
	input wire[inst_id_width-1:0] s_mul_inst_id, // 指令编号
	input wire s_mul_valid,
	output wire s_mul_ready,
	
	// 除法器执行请求
	input wire[32:0] s_div_op_a, // 操作数A
	input wire[32:0] s_div_op_b, // 操作数B
	input wire s_div_rem_sel, // 除法/求余选择(1'b0 -> 除法, 1'b1 -> 求余)
	input wire[4:0] s_div_rd_id, // RD索引
	input wire[inst_id_width-1:0] s_div_inst_id, // 指令编号
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
	output wire[31:0] flush_addr, // 冲刷地址
	
	// 数据相关性跟踪
	// 指令退休
	output wire[inst_id_width-1:0] dpc_trace_retire_inst_id, // 指令编号
	output wire dpc_trace_retire_valid
);
	
	/** 交付单元 **/
	// 中断使能
	wire mstatus_mie_v; // mstatus状态寄存器MIE域
	wire mie_msie_v; // mie状态寄存器MSIE域
	wire mie_mtie_v; // mie状态寄存器MTIE域
	wire mie_meie_v; // mie状态寄存器MEIE域
	// 待交付的指令
	wire[31:0] s_pst_inst; // 取到的指令(仅对非法指令可用)
	wire[2:0] s_pst_err_code; // 指令的错误类型(3'b000 -> 正常, 3'b001 -> 非法指令, 
	                          //     3'b010 -> 指令地址非对齐, 3'b011 -> 指令总线访问失败, 
							  //     3'b110 -> 读存储映射地址非对齐, 3'b111 -> 写存储映射地址非对齐)
	wire[31:0] s_pst_pc_of_inst; // 指令对应的PC
	wire s_pst_is_b_inst; // 是否B指令
	wire s_pst_is_ecall_inst; // 是否ECALL指令
	wire s_pst_is_mret_inst; // 是否MRET指令
	wire[31:0] s_pst_brc_pc_upd; // 分支预测失败时修正的PC(仅在B指令下有效)
	wire s_pst_prdt_jump; // 是否预测跳转
	wire s_pst_is_long_inst; // 是否长指令
	wire s_pst_valid;
	wire s_pst_ready;
	// 来自LSU的异常
	wire[31:0] s_lsu_expt_ls_addr; // 访存地址
	wire s_lsu_expt_err; // 错误类型(1'b0 -> 读存储映射总线错误, 1'b1 -> 写存储映射总线错误)
	wire s_lsu_expt_valid;
	wire s_lsu_expt_ready;
	// 交付结果
	wire m_pst_inst_cmt; // 指令是否被确认
	wire m_pst_need_imdt_wbk; // 是否需要立即写回通用寄存器堆
	wire m_pst_valid;
	wire m_pst_ready;
	// 访存地址生成
	wire[31:0] ls_addr; // 访存地址(仅对L/S指令可用)
	// 分支确认
	wire cfr_jump; // 是否确认跳转(仅对B指令可用)
	// 进入中断/异常处理
	wire itr_expt_enter; // 进入中断/异常(指示)
	wire itr_expt_is_intr; // 是否中断
	wire[7:0] itr_expt_cause; // 中断/异常原因
	wire[31:0] itr_expt_vec_baseaddr; // 中断/异常向量表基地址
	wire[31:0] itr_expt_ret_addr; // 中断/异常返回地址
	wire[31:0] itr_expt_val; // 中断/异常值(附加信息)
	// 退出中断/异常处理
	wire itr_expt_ret; // 退出中断/异常(指示)
	wire[31:0] mepc_ret_addr; // mepc状态寄存器定义的中断/异常返回地址
	
	assign s_pst_inst = s_alu_op2;
	assign s_pst_err_code = s_alu_err_code;
	assign s_pst_pc_of_inst = s_alu_pc_of_inst;
	assign s_pst_is_b_inst = s_alu_is_b_inst;
	assign s_pst_is_ecall_inst = s_alu_is_ecall_inst;
	assign s_pst_is_mret_inst = s_alu_is_mret_inst;
	assign s_pst_brc_pc_upd = s_alu_brc_pc_upd;
	assign s_pst_prdt_jump = s_alu_prdt_jump;
	assign s_pst_is_long_inst = s_alu_is_long_inst;
	assign s_pst_valid = s_alu_valid;
	assign s_alu_ready = s_pst_ready;
	
	panda_risc_v_commit #(
		.simulation_delay(simulation_delay)
	)panda_risc_v_commit_u(
		.clk(clk),
		.resetn(resetn),
		
		.mstatus_mie_v(mstatus_mie_v),
		.mie_msie_v(mie_msie_v),
		.mie_mtie_v(mie_mtie_v),
		.mie_meie_v(mie_meie_v),
		
		.s_pst_inst(s_pst_inst),
		.s_pst_err_code(s_pst_err_code),
		.s_pst_pc_of_inst(s_pst_pc_of_inst),
		.s_pst_is_b_inst(s_pst_is_b_inst),
		.s_pst_is_ecall_inst(s_pst_is_ecall_inst),
		.s_pst_is_mret_inst(s_pst_is_mret_inst),
		.s_pst_brc_pc_upd(s_pst_brc_pc_upd),
		.s_pst_prdt_jump(s_pst_prdt_jump),
		.s_pst_is_long_inst(s_pst_is_long_inst),
		.s_pst_valid(s_pst_valid),
		.s_pst_ready(s_pst_ready),
		
		.s_lsu_expt_ls_addr(s_lsu_expt_ls_addr),
		.s_lsu_expt_err(s_lsu_expt_err),
		.s_lsu_expt_valid(s_lsu_expt_valid),
		.s_lsu_expt_ready(s_lsu_expt_ready),
		
		.m_pst_inst_cmt(m_pst_inst_cmt),
		.m_pst_need_imdt_wbk(m_pst_need_imdt_wbk),
		.m_pst_valid(m_pst_valid),
		.m_pst_ready(m_pst_ready),
		
		.ls_addr(ls_addr),
		
		.cfr_jump(cfr_jump),
		
		.sw_itr_req(sw_itr_req),
		.tmr_itr_req(tmr_itr_req),
		.ext_itr_req(ext_itr_req),
		
		.itr_expt_enter(itr_expt_enter),
		.itr_expt_is_intr(itr_expt_is_intr),
		.itr_expt_cause(itr_expt_cause),
		.itr_expt_vec_baseaddr(itr_expt_vec_baseaddr),
		.itr_expt_ret_addr(itr_expt_ret_addr),
		.itr_expt_val(itr_expt_val),
		
		.itr_expt_ret(itr_expt_ret),
		.mepc_ret_addr(mepc_ret_addr),
		
		.flush_req(flush_req),
		.flush_ack(flush_ack),
		.flush_addr(flush_addr)
	);
	
	/** ALU **/
	// ALU操作信息输入
	wire[3:0] alu_op_mode; // 操作类型
	wire[31:0] alu_op1; // 操作数1
	wire[31:0] alu_op2; // 操作数2
	// 特定结果输出
	wire alu_brc_cond_res; // 分支判定结果
	wire[31:0] alu_ls_addr; // 访存地址
	// ALU计算结果输出
	wire[31:0] alu_res; // 计算结果
	
	assign alu_op_mode = s_alu_op_mode;
	assign alu_op1 = s_alu_op1;
	assign alu_op2 = s_alu_op2;
	
	assign cfr_jump = alu_brc_cond_res;
	assign ls_addr = alu_ls_addr;
	
	panda_risc_v_alu #(
		.en_shift_reuse("true"),
		.en_eq_cmp_reuse("false")
	)panda_risc_v_alu_u(
		.op_mode(alu_op_mode),
		.op1(alu_op1),
		.op2(alu_op2),
		
		.brc_cond_res(alu_brc_cond_res),
		.ls_addr(alu_ls_addr),
		
		.res(alu_res)
	);
	
	/** CSR原子读写单元 **/
	// CSR原子读写
	wire[11:0] csr_atom_rw_addr; // CSR地址
	wire[1:0] csr_atom_rw_upd_type; // CSR更新类型
	wire[31:0] csr_atom_rw_upd_mask_v; // CSR更新掩码或更新值
	wire csr_atom_rw_valid; // 执行原子读写(指示)
	wire[31:0] csr_atom_rw_dout; // CSR原值
	// 性能监测
	wire inst_retire_cnt_en; // 退休指令计数器的计数使能
	
	assign csr_atom_rw_addr = s_csr_addr;
	assign csr_atom_rw_upd_type = s_csr_upd_type;
	assign csr_atom_rw_upd_mask_v = s_csr_upd_mask_v;
	// 警告: 经由交付单元取消的指令不应执行CSR原子读写!
	assign csr_atom_rw_valid = s_csr_rw_valid;
	assign s_csr_rw_ready = 1'b1;
	
	panda_risc_v_csr_rw #(
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
	)panda_risc_v_csr_rw_u(
		.clk(clk),
		.resetn(resetn),
		
		.csr_atom_rw_addr(csr_atom_rw_addr),
		.csr_atom_rw_upd_type(csr_atom_rw_upd_type),
		.csr_atom_rw_upd_mask_v(csr_atom_rw_upd_mask_v),
		.csr_atom_rw_valid(csr_atom_rw_valid),
		.csr_atom_rw_dout(csr_atom_rw_dout),
		
		.itr_expt_enter(itr_expt_enter),
		.itr_expt_is_intr(itr_expt_is_intr),
		.itr_expt_cause(itr_expt_cause),
		.itr_expt_vec_baseaddr(itr_expt_vec_baseaddr),
		.itr_expt_ret_addr(itr_expt_ret_addr),
		.itr_expt_val(itr_expt_val),
		
		.itr_expt_ret(itr_expt_ret),
		.mepc_ret_addr(mepc_ret_addr),
		
		.inst_retire_cnt_en(inst_retire_cnt_en),
		
		.sw_itr_req(sw_itr_req),
		.tmr_itr_req(tmr_itr_req),
		.ext_itr_req(ext_itr_req),
		
		.mstatus_mie_v(mstatus_mie_v),
		.mie_msie_v(mie_msie_v),
		.mie_mtie_v(mie_mtie_v),
		.mie_meie_v(mie_meie_v)
	);
	
	/** LSU **/
	// 访存请求
	wire s_req_ls_sel; // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	wire[2:0] s_req_ls_type; // 访存类型
	wire[4:0] s_req_rd_id_for_ld; // 用于加载的目标寄存器的索引
	wire[31:0] s_req_ls_addr; // 访存地址
	wire[31:0] s_req_ls_din; // 写数据
	wire[inst_id_width-1:0] s_req_lsu_inst_id; // 指令编号
	wire s_req_valid;
	wire s_req_ready;
	// 访存结果
	wire m_resp_ls_sel; // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	wire[4:0] m_resp_rd_id_for_ld; // 用于加载的目标寄存器的索引
	wire[31:0] m_resp_dout; // 读数据
	wire[31:0] m_resp_ls_addr; // 访存地址
	wire[1:0] m_resp_err; // 错误类型
	wire[inst_id_width-1:0] m_resp_lsu_inst_id; // 指令编号
	wire m_resp_valid;
	wire m_resp_ready;
	
	assign s_req_ls_sel = s_ls_sel;
	assign s_req_ls_type = s_ls_type;
	assign s_req_rd_id_for_ld = s_rd_id_for_ld;
	assign s_req_ls_addr = alu_ls_addr;
	assign s_req_ls_din = s_ls_din;
	assign s_req_lsu_inst_id = s_lsu_inst_id;
	// 警告: 经由交付单元取消的指令不应发起访存请求!
	assign s_req_valid = s_lsu_valid;
	assign s_lsu_ready = s_req_ready;
	
	panda_risc_v_lsu #(
		.inst_id_width(inst_id_width),
		.dbus_access_timeout_th(dbus_access_timeout_th),
		.icb_zero_latency_supported(icb_zero_latency_supported),
		.simulation_delay(simulation_delay)
	)panda_risc_v_lsu_u(
		.clk(clk),
		.resetn(resetn),
		
		.s_req_ls_sel(s_req_ls_sel),
		.s_req_ls_type(s_req_ls_type),
		.s_req_rd_id_for_ld(s_req_rd_id_for_ld),
		.s_req_ls_addr(s_req_ls_addr),
		.s_req_ls_din(s_req_ls_din),
		.s_req_lsu_inst_id(s_req_lsu_inst_id),
		.s_req_valid(s_req_valid),
		.s_req_ready(s_req_ready),
		
		.m_resp_ls_sel(m_resp_ls_sel),
		.m_resp_rd_id_for_ld(m_resp_rd_id_for_ld),
		.m_resp_dout(m_resp_dout),
		.m_resp_ls_addr(m_resp_ls_addr),
		.m_resp_err(m_resp_err),
		.m_resp_lsu_inst_id(m_resp_lsu_inst_id),
		.m_resp_valid(m_resp_valid),
		.m_resp_ready(m_resp_ready),
		
		.m_icb_cmd_addr(m_icb_cmd_addr),
		.m_icb_cmd_read(m_icb_cmd_read),
		.m_icb_cmd_wdata(m_icb_cmd_wdata),
		.m_icb_cmd_wmask(m_icb_cmd_wmask),
		.m_icb_cmd_valid(m_icb_cmd_valid),
		.m_icb_cmd_ready(m_icb_cmd_ready),
		.m_icb_rsp_rdata(m_icb_rsp_rdata),
		.m_icb_rsp_err(m_icb_rsp_err),
		.m_icb_rsp_valid(m_icb_rsp_valid),
		.m_icb_rsp_ready(m_icb_rsp_ready),
		
		.dbus_timeout(dbus_timeout)
	);
	
	/** 多周期乘法器 **/
	// 乘法器执行请求
	wire[32:0] s_mul_req_op_a; // 操作数A
	wire[32:0] s_mul_req_op_b; // 操作数B
	wire s_mul_req_res_sel; // 乘法结果选择(1'b0 -> 低32位, 1'b1 -> 高32位)
	wire[4:0] s_mul_req_rd_id; // RD索引
	wire[inst_id_width-1:0] s_mul_req_inst_id; // 指令编号
	wire s_mul_req_valid;
	wire s_mul_req_ready;
	// 乘法器计算结果
	wire[31:0] m_mul_res_data; // 计算结果
	wire[4:0] m_mul_res_rd_id; // RD索引
	wire[inst_id_width-1:0] m_mul_res_inst_id; // 指令编号
	wire m_mul_res_valid;
	wire m_mul_res_ready;
	
	assign s_mul_req_op_a = s_mul_op_a;
	assign s_mul_req_op_b = s_mul_op_b;
	assign s_mul_req_res_sel = s_mul_res_sel;
	assign s_mul_req_rd_id = s_mul_rd_id;
	assign s_mul_req_inst_id = s_mul_inst_id;
	// 警告: 经由交付单元取消的指令不应发起乘法器执行请求!
	assign s_mul_req_valid = s_mul_valid;
	assign s_mul_ready = s_mul_req_ready;
	
	panda_risc_v_multiplier #(
		.inst_id_width(inst_id_width),
		.simulation_delay(simulation_delay)
	)panda_risc_v_multiplier_u(
		.clk(clk),
		.resetn(resetn),
		
		.s_mul_req_op_a(s_mul_req_op_a),
		.s_mul_req_op_b(s_mul_req_op_b),
		.s_mul_req_res_sel(s_mul_req_res_sel),
		.s_mul_req_rd_id(s_mul_req_rd_id),
		.s_mul_req_inst_id(s_mul_req_inst_id),
		.s_mul_req_valid(s_mul_req_valid),
		.s_mul_req_ready(s_mul_req_ready),
		
		.m_mul_res_data(m_mul_res_data),
		.m_mul_res_rd_id(m_mul_res_rd_id),
		.m_mul_res_inst_id(m_mul_res_inst_id),
		.m_mul_res_valid(m_mul_res_valid),
		.m_mul_res_ready(m_mul_res_ready)
	);
	
	/** 多周期除法器 **/
	// 除法器执行请求
	wire[32:0] s_div_req_op_a; // 操作数A(被除数)
	wire[32:0] s_div_req_op_b; // 操作数B(除数)
	wire s_div_req_rem_sel; // 除法/求余选择(1'b0 -> 除法, 1'b1 -> 求余)
	wire[4:0] s_div_req_rd_id; // RD索引
	wire[inst_id_width-1:0] s_div_req_inst_id; // 指令编号
	wire s_div_req_valid;
	wire s_div_req_ready;
	// 除法器计算结果
	wire[31:0] m_div_res_data; // 计算结果
	wire[4:0] m_div_res_rd_id; // RD索引
	wire[inst_id_width-1:0] m_div_res_inst_id; // 指令编号
	wire m_div_res_valid;
	wire m_div_res_ready;
	
	assign s_div_req_op_a = s_div_op_a;
	assign s_div_req_op_b = s_div_op_b;
	assign s_div_req_rem_sel = s_div_rem_sel;
	assign s_div_req_rd_id = s_div_rd_id;
	assign s_div_req_inst_id = s_div_inst_id;
	// 警告: 经由交付单元取消的指令不应发起除法器执行请求!
	assign s_div_req_valid = s_div_valid;
	assign s_div_ready = s_div_req_ready;
	
	panda_risc_v_divider #(
		.inst_id_width(inst_id_width),
		.simulation_delay(simulation_delay)
	)panda_risc_v_divider_u(
		.clk(clk),
		.resetn(resetn),
		
		.s_div_req_op_a(s_div_req_op_a),
		.s_div_req_op_b(s_div_req_op_b),
		.s_div_req_rem_sel(s_div_req_rem_sel),
		.s_div_req_rd_id(s_div_req_rd_id),
		.s_div_req_inst_id(s_div_req_inst_id),
		.s_div_req_valid(s_div_req_valid),
		.s_div_req_ready(s_div_req_ready),
		
		.m_div_res_data(m_div_res_data),
		.m_div_res_rd_id(m_div_res_rd_id),
		.m_div_res_inst_id(m_div_res_inst_id),
		.m_div_res_valid(m_div_res_valid),
		.m_div_res_ready(m_div_res_ready)
	);
	
	/** LSU异常缓存寄存器组 **/
	// fifo写端口
	wire lsu_expt_fifo_wen;
    wire[32:0] lsu_expt_fifo_din;
    wire lsu_expt_fifo_full_n;
	// fifo读端口
	wire lsu_expt_fifo_ren;
    wire[32:0] lsu_expt_fifo_dout;
    wire lsu_expt_fifo_empty_n;
	
	assign {s_lsu_expt_err, s_lsu_expt_ls_addr} = lsu_expt_fifo_dout;
	assign s_lsu_expt_valid = lsu_expt_fifo_empty_n;
	assign lsu_expt_fifo_ren = s_lsu_expt_ready;
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(2),
		.fifo_data_width(33),
		.almost_full_th(1),
		.almost_empty_th(1),
		.simulation_delay(simulation_delay)
	)lsu_expt_fifo(
		.clk(clk),
		.rst_n(resetn),
		
		.fifo_wen(lsu_expt_fifo_wen),
		.fifo_din(lsu_expt_fifo_din),
		.fifo_full_n(lsu_expt_fifo_full_n),
		
		.fifo_ren(lsu_expt_fifo_ren),
		.fifo_dout(lsu_expt_fifo_dout),
		.fifo_empty_n(lsu_expt_fifo_empty_n)
	);
	
	/** 通用寄存器堆 **/
	// 通用寄存器堆写端口
	wire reg_file_wen;
	wire[4:0] reg_file_waddr;
	wire[31:0] reg_file_din;
	// 通用寄存器堆读端口#0
	wire[4:0] reg_file_raddr_p0;
	wire[31:0] reg_file_dout_p0;
	// 通用寄存器堆读端口#1
	wire[4:0] reg_file_raddr_p1;
	wire[31:0] reg_file_dout_p1;
	// 通用寄存器#1的值
	wire[31:0] x1_v;
	
	panda_risc_v_reg_file #(
		.simulation_delay(simulation_delay)
	)panda_risc_v_reg_file_u(
		.clk(clk),
		
		.reg_file_wen(reg_file_wen),
		.reg_file_waddr(reg_file_waddr),
		.reg_file_din(reg_file_din),
		
		.reg_file_raddr_p0(reg_file_raddr_p0),
		.reg_file_dout_p0(reg_file_dout_p0),
		
		.reg_file_raddr_p1(reg_file_raddr_p1),
		.reg_file_dout_p1(reg_file_dout_p1),
		
		.x1_v(x1_v)
	);
	
	/** 通用寄存器堆读仲裁 **/
	panda_risc_v_reg_file_rd_arb panda_risc_v_reg_file_rd_arb_u(
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
		
		.reg_file_raddr_p0(reg_file_raddr_p0),
		.reg_file_dout_p0(reg_file_dout_p0),
		
		.reg_file_raddr_p1(reg_file_raddr_p1),
		.reg_file_dout_p1(reg_file_dout_p1),
		
		.x1_v(x1_v)
	);
	
	/** 写回单元 **/
	// 交付结果
	wire s_pst_res_inst_cmt; // 指令是否被确认
	wire s_pst_res_need_imdt_wbk; // 是否需要立即写回通用寄存器堆
	wire s_pst_res_valid;
	wire s_pst_res_ready;
	// 来自ALU或CSR原子读写单元的写回请求
	wire s_alu_csr_wbk_is_csr_rw_inst; // 是否CSR读写指令
	wire[31:0] s_alu_csr_wbk_csr_v; // CSR原值
	wire[31:0] s_alu_csr_wbk_alu_res; // ALU计算结果
	wire[4:0] s_alu_csr_wbk_csr_rw_rd_id; // CSR原子读写单元给出的RD索引
	wire[4:0] s_alu_csr_wbk_alu_rd_id; // ALU给出的RD索引
	wire s_alu_csr_wbk_rd_vld; // 是否需要写RD
	wire[inst_id_width-1:0] s_alu_csr_wbk_csr_rw_inst_id; // CSR原子读写单元给出的指令编号
	wire[inst_id_width-1:0] s_alu_csr_wbk_alu_inst_id; // ALU给出的指令编号
	wire s_alu_csr_wbk_valid;
	wire s_alu_csr_wbk_ready;
	// 来自LSU的写回请求
	wire s_lsu_wbk_ls_sel; // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	wire[4:0] s_lsu_wbk_rd_id_for_ld; // 用于加载的目标寄存器的索引
	wire[31:0] s_lsu_wbk_dout; // 读数据
	wire[31:0] s_lsu_wbk_ls_addr; // 访存地址
	wire[1:0] s_lsu_wbk_err; // 错误类型
	wire[inst_id_width-1:0] s_lsu_wbk_inst_id; // 指令编号
	wire s_lsu_wbk_valid;
	wire s_lsu_wbk_ready;
	// 来自乘法器的写回请求
	wire[31:0] s_mul_wbk_data; // 计算结果
	wire[4:0] s_mul_wbk_rd_id; // RD索引
	wire[inst_id_width-1:0] s_mul_wbk_inst_id; // 指令编号
	wire s_mul_wbk_valid;
	wire s_mul_wbk_ready;
	// 来自除法器的写回请求
	wire[31:0] s_div_wbk_data; // 计算结果
	wire[4:0] s_div_wbk_rd_id; // RD索引
	wire[inst_id_width-1:0] s_div_wbk_inst_id; // 指令编号
	wire s_div_wbk_valid;
	wire s_div_wbk_ready;
	// LSU异常
	wire[31:0] m_lsu_expt_ls_addr; // 访存地址
	wire m_lsu_expt_err; // 错误类型(1'b0 -> 读存储映射总线错误, 1'b1 -> 写存储映射总线错误)
	wire m_lsu_expt_valid;
	wire m_lsu_expt_ready;
	// 指令退休
	wire inst_retire; // 指令退休(指示)
	wire[inst_id_width-1:0] inst_retire_id; // 退休指令的编号
	
	assign dpc_trace_retire_inst_id = inst_retire_id;
	assign dpc_trace_retire_valid = inst_retire;
	
	assign inst_retire_cnt_en = inst_retire;
	
	assign s_pst_res_inst_cmt = m_pst_inst_cmt;
	assign s_pst_res_need_imdt_wbk = m_pst_need_imdt_wbk;
	assign s_pst_res_valid = m_pst_valid;
	assign m_pst_ready = s_pst_res_ready;
	
	assign s_alu_csr_wbk_is_csr_rw_inst = s_alu_is_csr_rw_inst;
	assign s_alu_csr_wbk_csr_v = csr_atom_rw_dout;
	assign s_alu_csr_wbk_alu_res = alu_res;
	assign s_alu_csr_wbk_csr_rw_rd_id = s_csr_rw_rd_id;
	assign s_alu_csr_wbk_alu_rd_id = s_alu_rd_id;
	assign s_alu_csr_wbk_rd_vld = s_alu_rd_vld;
	assign s_alu_csr_wbk_csr_rw_inst_id = s_csr_rw_inst_id;
	assign s_alu_csr_wbk_alu_inst_id = s_alu_inst_id;
	assign s_alu_csr_wbk_valid = m_pst_valid;
	
	assign s_lsu_wbk_ls_sel = m_resp_ls_sel;
	assign s_lsu_wbk_rd_id_for_ld = m_resp_rd_id_for_ld;
	assign s_lsu_wbk_dout = m_resp_dout;
	assign s_lsu_wbk_ls_addr = m_resp_ls_addr;
	assign s_lsu_wbk_err = m_resp_err;
	assign s_lsu_wbk_inst_id = m_resp_lsu_inst_id;
	assign s_lsu_wbk_valid = m_resp_valid;
	assign m_resp_ready = s_lsu_wbk_ready;
	
	assign s_mul_wbk_data = m_mul_res_data;
	assign s_mul_wbk_rd_id = m_mul_res_rd_id;
	assign s_mul_wbk_inst_id = m_mul_res_inst_id;
	assign s_mul_wbk_valid = m_mul_res_valid;
	assign m_mul_res_ready = s_mul_wbk_ready;
	
	assign s_div_wbk_data = m_div_res_data;
	assign s_div_wbk_rd_id = m_div_res_rd_id;
	assign s_div_wbk_inst_id = m_div_res_inst_id;
	assign s_div_wbk_valid = m_div_res_valid;
	assign m_div_res_ready = s_div_wbk_ready;
	
	assign lsu_expt_fifo_wen = m_lsu_expt_valid;
	assign lsu_expt_fifo_din = {m_lsu_expt_err, m_lsu_expt_ls_addr};
	assign m_lsu_expt_ready = lsu_expt_fifo_full_n;
	
	panda_risc_v_wbk #(
		.inst_id_width(inst_id_width),
		.simulation_delay(simulation_delay)
	)panda_risc_v_wbk_u(
		.clk(clk),
		.resetn(resetn),
		
		.s_pst_res_inst_cmt(s_pst_res_inst_cmt),
		.s_pst_res_need_imdt_wbk(s_pst_res_need_imdt_wbk),
		.s_pst_res_valid(s_pst_res_valid), // 注意: 未使用的信号!
		.s_pst_res_ready(s_pst_res_ready),
		
		.s_alu_csr_wbk_is_csr_rw_inst(s_alu_csr_wbk_is_csr_rw_inst),
		.s_alu_csr_wbk_csr_v(s_alu_csr_wbk_csr_v),
		.s_alu_csr_wbk_alu_res(s_alu_csr_wbk_alu_res),
		.s_alu_csr_wbk_csr_rw_rd_id(s_alu_csr_wbk_csr_rw_rd_id),
		.s_alu_csr_wbk_alu_rd_id(s_alu_csr_wbk_alu_rd_id),
		.s_alu_csr_wbk_rd_vld(s_alu_csr_wbk_rd_vld),
		.s_alu_csr_wbk_csr_rw_inst_id(s_alu_csr_wbk_csr_rw_inst_id),
		.s_alu_csr_wbk_alu_inst_id(s_alu_csr_wbk_alu_inst_id),
		.s_alu_csr_wbk_valid(s_alu_csr_wbk_valid),
		.s_alu_csr_wbk_ready(s_alu_csr_wbk_ready), // 注意: 未使用的信号!
		
		.s_lsu_wbk_ls_sel(s_lsu_wbk_ls_sel),
		.s_lsu_wbk_rd_id_for_ld(s_lsu_wbk_rd_id_for_ld),
		.s_lsu_wbk_dout(s_lsu_wbk_dout),
		.s_lsu_wbk_ls_addr(s_lsu_wbk_ls_addr),
		.s_lsu_wbk_err(s_lsu_wbk_err),
		.s_lsu_wbk_inst_id(s_lsu_wbk_inst_id),
		.s_lsu_wbk_valid(s_lsu_wbk_valid),
		.s_lsu_wbk_ready(s_lsu_wbk_ready),
		
		.s_mul_wbk_data(s_mul_wbk_data),
		.s_mul_wbk_rd_id(s_mul_wbk_rd_id),
		.s_mul_wbk_inst_id(s_mul_wbk_inst_id),
		.s_mul_wbk_valid(s_mul_wbk_valid),
		.s_mul_wbk_ready(s_mul_wbk_ready),
		
		.s_div_wbk_data(s_div_wbk_data),
		.s_div_wbk_rd_id(s_div_wbk_rd_id),
		.s_div_wbk_inst_id(s_div_wbk_inst_id),
		.s_div_wbk_valid(s_div_wbk_valid),
		.s_div_wbk_ready(s_div_wbk_ready),
		
		.m_lsu_expt_ls_addr(m_lsu_expt_ls_addr),
		.m_lsu_expt_err(m_lsu_expt_err),
		.m_lsu_expt_valid(m_lsu_expt_valid),
		.m_lsu_expt_ready(m_lsu_expt_ready),
		
		.reg_file_wen(reg_file_wen),
		.reg_file_waddr(reg_file_waddr),
		.reg_file_din(reg_file_din),
		
		.inst_retire(inst_retire),
		.inst_retire_id(inst_retire_id)
	);
	
endmodule
