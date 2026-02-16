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
本模块: 执行单元组

描述:
一组执行单元, 包括ALU、CSR原子读写(需要外接)、LSU、乘法器、除法器

注意：
无

协议:
AXI-Lite MASTER

作者: 陈家耀
日期: 2026/02/11
********************************************************************/


module panda_risc_v_func_units #(
	parameter EN_OUT_OF_ORDER_ISSUE = "true", // 是否启用乱序发射
	parameter integer IBUS_TID_WIDTH = 8, // 指令总线事务ID位宽(1~16)
	parameter integer AXI_MEM_DATA_WIDTH = 64, // 存储器AXI主机的数据位宽(32 | 64 | 128 | 256)
	parameter integer MEM_ACCESS_TIMEOUT_TH = 0, // 存储器访问超时周期数(0 -> 不设超时 | 正整数)
	parameter integer PERPH_ACCESS_TIMEOUT_TH = 32, // 外设访问超时周期数(0 -> 不设超时 | 正整数)
	parameter integer LSU_REQ_BUF_ENTRY_N = 8, // LSU请求缓存区条目数(2~16)
	parameter integer RD_MEM_BUF_ENTRY_N = 4, // 读存储器缓存区条目数(2~16)
	parameter integer WR_MEM_BUF_ENTRY_N = 4, // 写存储器缓存区条目数(2~16)
	parameter PERPH_ADDR_REGION_0_BASE = 32'h4000_0000, // 外设地址区域#0基地址
	parameter PERPH_ADDR_REGION_0_LEN = 32'h1000_0000, // 外设地址区域#0长度(以字节计)
	parameter PERPH_ADDR_REGION_1_BASE = 32'hF000_0000, // 外设地址区域#1基地址
	parameter PERPH_ADDR_REGION_1_LEN = 32'h0800_0000, // 外设地址区域#1长度(以字节计)
	parameter EN_SGN_PERIOD_MUL = "true", // 是否使用单周期乘法器
	parameter EN_LOW_LATENCY_PERPH_ACCESS = "false", // 是否启用低时延的外设访问模式
	parameter integer EN_LOW_LATENCY_RD_MEM_ACCESS_IN_LSU = 1, // LSU读存储器访问时延优化等级(0 | 1 | 2)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// ALU(用户端口)
	// [操作信息输入]
	input wire[3:0] s_alu_op_mode, // 操作类型
	input wire[31:0] s_alu_op1, // 操作数1
	input wire[31:0] s_alu_op2, // 操作数2
	input wire[IBUS_TID_WIDTH-1:0] s_alu_tid, // 指令ID
	input wire s_alu_use_res, // 是否使用ALU的计算结果
	input wire s_alu_valid,
	// [计算结果输出]
	output wire[31:0] m_alu_res, // 计算结果
	output wire[IBUS_TID_WIDTH-1:0] m_alu_tid, // 指令ID
	output wire m_alu_brc_cond_res, // 分支判定结果
	output wire m_alu_valid,
	
	// CSR原子读写(用户端口)
	// [访问输入]
	input wire[11:0] s_csr_addr, // CSR地址
	input wire[IBUS_TID_WIDTH-1:0] s_csr_tid, // 指令ID
	input wire s_csr_valid,
	// [访问输出]
	output wire[31:0] m_csr_dout, // CSR原值
	output wire[IBUS_TID_WIDTH-1:0] m_csr_tid, // 指令ID
	output wire m_csr_valid,
	
	// LSU(用户端口)
	// [访问输入]
	input wire s_lsu_ls_sel, // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	input wire[2:0] s_lsu_ls_type, // 访存类型
	input wire[4:0] s_lsu_rd_id_for_ld, // 用于加载的目标寄存器的索引
	input wire[31:0] s_lsu_ls_addr, // 访存地址
	input wire[31:0] s_lsu_ls_din, // 写数据
	input wire[IBUS_TID_WIDTH-1:0] s_lsu_inst_id, // 指令ID
	input wire s_lsu_valid,
	output wire s_lsu_ready,
	// [访问输出]
	output wire m_lsu_ls_sel, // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	output wire[4:0] m_lsu_rd_id_for_ld, // 用于加载的目标寄存器的索引
	// 说明: 访存正常完成时给出"读数据", 错误时给出"访存地址"
	output wire[31:0] m_lsu_dout_ls_addr, // 读数据或访存地址
	output wire[1:0] m_lsu_err, // 错误类型
	output wire[IBUS_TID_WIDTH-1:0] m_lsu_inst_id, // 指令ID
	output wire m_lsu_valid,
	
	// 乘法器(用户端口)
	// [计算输入]
	input wire[32:0] s_mul_op_a, // 操作数A
	input wire[32:0] s_mul_op_b, // 操作数B
	input wire s_mul_res_sel, // 乘法结果选择(1'b0 -> 低32位, 1'b1 -> 高32位)
	input wire[4:0] s_mul_rd_id, // RD索引
	input wire[IBUS_TID_WIDTH-1:0] s_mul_inst_id, // 指令ID
	input wire s_mul_valid,
	output wire s_mul_ready,
	// [计算输出]
	output wire[31:0] m_mul_data, // 计算结果
	output wire[4:0] m_mul_rd_id, // RD索引
	output wire[IBUS_TID_WIDTH-1:0] m_mul_inst_id, // 指令ID
	output wire m_mul_valid,
	
	// 除法器(用户端口)
	// [计算输入]
	input wire[32:0] s_div_op_a, // 操作数A(被除数)
	input wire[32:0] s_div_op_b, // 操作数B(除数)
	input wire s_div_rem_sel, // 除法/求余选择(1'b0 -> 除法, 1'b1 -> 求余)
	input wire[4:0] s_div_rd_id, // RD索引
	input wire[IBUS_TID_WIDTH-1:0] s_div_inst_id, // 指令ID
	input wire s_div_valid,
	output wire s_div_ready,
	// [计算输出]
	output wire[31:0] m_div_data, // 计算结果
	output wire[4:0] m_div_rd_id, // RD索引
	output wire[IBUS_TID_WIDTH-1:0] m_div_inst_id, // 指令ID
	output wire m_div_valid,
	
	// CSR原子读写(FU端口)
	output wire[11:0] csr_atom_raddr, // CSR读地址
	input wire[31:0] csr_atom_dout, // CSR原值
	
	// BRU名义结果
	input wire bru_nominal_res_vld, // 有效标志
	input wire[IBUS_TID_WIDTH-1:0] bru_nominal_res_tid, // 指令ID
	input wire[31:0] bru_nominal_res, // 执行结果
	
	// 执行单元结果返回
	output wire[6-1:0] fu_res_vld, // 有效标志
	output wire[6*IBUS_TID_WIDTH-1:0] fu_res_tid, // 指令ID
	output wire[6*32-1:0] fu_res_data, // 执行结果
	output wire[6*3-1:0] fu_res_err, // 错误码
	
	// 存储器AXI主机
	// [AR通道]
	output wire[31:0] m_axi_mem_araddr,
	output wire[1:0] m_axi_mem_arburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_mem_arlen, // const -> 8'd0
	output wire[2:0] m_axi_mem_arsize, // const -> clogb2(AXI_MEM_DATA_WIDTH/8)
	output wire m_axi_mem_arvalid,
	input wire m_axi_mem_arready,
	// [R通道]
	input wire[AXI_MEM_DATA_WIDTH-1:0] m_axi_mem_rdata,
	input wire[1:0] m_axi_mem_rresp,
	input wire m_axi_mem_rlast, // ignored
	input wire m_axi_mem_rvalid,
	output wire m_axi_mem_rready, // const -> 1'b1
	// [AW通道]
	output wire[31:0] m_axi_mem_awaddr,
	output wire[1:0] m_axi_mem_awburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_mem_awlen, // const -> 8'd0
	output wire[2:0] m_axi_mem_awsize, // const -> clogb2(AXI_MEM_DATA_WIDTH/8)
	output wire m_axi_mem_awvalid,
	input wire m_axi_mem_awready,
	// [B通道]
	input wire[1:0] m_axi_mem_bresp, // ignored
	input wire m_axi_mem_bvalid,
	output wire m_axi_mem_bready, // const -> 1'b1
	// [W通道]
	output wire[AXI_MEM_DATA_WIDTH-1:0] m_axi_mem_wdata,
	output wire[AXI_MEM_DATA_WIDTH/8-1:0] m_axi_mem_wstrb,
	output wire m_axi_mem_wlast, // const -> 1'b1
	output wire m_axi_mem_wvalid,
	input wire m_axi_mem_wready,
	
	// 外设AXI主机
	// [AR通道]
	output wire[31:0] m_axi_perph_araddr,
	output wire[1:0] m_axi_perph_arburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_perph_arlen, // const -> 8'd0
	output wire[2:0] m_axi_perph_arsize, // const -> 3'b010
	output wire m_axi_perph_arvalid,
	input wire m_axi_perph_arready,
	// [R通道]
	input wire[31:0] m_axi_perph_rdata,
	input wire[1:0] m_axi_perph_rresp,
	input wire m_axi_perph_rlast, // ignored
	input wire m_axi_perph_rvalid,
	output wire m_axi_perph_rready, // const -> 1'b1
	// [AW通道]
	output wire[31:0] m_axi_perph_awaddr,
	output wire[1:0] m_axi_perph_awburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_perph_awlen, // const -> 8'd0
	output wire[2:0] m_axi_perph_awsize, // const -> 3'b010
	output wire m_axi_perph_awvalid,
	input wire m_axi_perph_awready,
	// [B通道]
	input wire[1:0] m_axi_perph_bresp,
	input wire m_axi_perph_bvalid,
	output wire m_axi_perph_bready, // const -> 1'b1
	// [W通道]
	output wire[31:0] m_axi_perph_wdata,
	output wire[3:0] m_axi_perph_wstrb,
	output wire m_axi_perph_wlast, // const -> 1'b1
	output wire m_axi_perph_wvalid,
	input wire m_axi_perph_wready,
	
	// 写存储器缓存区控制
	// [写存储器许可]
	input wire wr_mem_permitted_flag, // 许可标志
	input wire[IBUS_TID_WIDTH-1:0] init_mem_bus_tr_store_inst_tid, // 待发起存储器总线事务的存储指令ID
	// [清空缓存区]
	input wire clr_wr_mem_buf, // 清空指示
	
	// 外设访问控制
	// [外设访问许可]
	input wire perph_access_permitted_flag, // 许可标志
	input wire[IBUS_TID_WIDTH-1:0] init_perph_bus_tr_ls_inst_tid, // 待发起外设总线事务的访存指令ID
	// [取消后续外设访问]
	input wire cancel_subseq_perph_access, // 取消指示
	
	// 读存储器结果快速旁路
	output wire on_get_instant_rd_mem_res_s0,
	output wire[IBUS_TID_WIDTH-1:0] inst_id_of_instant_rd_mem_res_gotten_s0,
	output wire[31:0] data_of_instant_rd_mem_res_gotten_s0,
	output wire on_get_instant_rd_mem_res_s1,
	output wire[IBUS_TID_WIDTH-1:0] inst_id_of_instant_rd_mem_res_gotten_s1,
	output wire[31:0] data_of_instant_rd_mem_res_gotten_s1,
	
	// LSU状态
	output wire has_buffered_wr_mem_req, // 存在已缓存的写存储器请求(标志)
	output wire has_processing_perph_access_req, // 存在处理中的外设访问请求(标志)
	output wire rd_mem_timeout, // 读存储器超时(标志)
	output wire wr_mem_timeout, // 写存储器超时(标志)
	output wire perph_access_timeout // 外设访问超时(标志)
);
	
	/** 常量 **/
	// CSR更新类型
	localparam CSR_UPD_TYPE_LOAD = 2'b00;
	localparam CSR_UPD_TYPE_SET = 2'b01;
	localparam CSR_UPD_TYPE_CLR = 2'b10;
	// 访存类型
	localparam LS_TYPE_BYTE = 3'b000;
	localparam LS_TYPE_HALF_WORD = 3'b001;
	localparam LS_TYPE_WORD = 3'b010;
	localparam LS_TYPE_BYTE_UNSIGNED = 3'b100;
	localparam LS_TYPE_HALF_WORD_UNSIGNED = 3'b101;
	// 访存应答错误类型
	localparam DBUS_ACCESS_NORMAL = 2'b00; // 正常
	localparam DBUS_ACCESS_LS_UNALIGNED = 2'b01; // 访存地址非对齐
	localparam DBUS_ACCESS_BUS_ERR = 2'b10; // 数据总线访问错误
	localparam DBUS_ACCESS_TIMEOUT = 2'b11; // 响应超时
	// LSU错误类型
	localparam LSU_ERR_CODE_NORMAL = 3'b000; // 正常
	localparam LSU_ERR_CODE_RD_ADDR_UNALIGNED = 3'b001; // 读访问地址非对齐
	localparam LSU_ERR_CODE_WT_ADDR_UNALIGNED = 3'b010; // 写访问地址非对齐
	localparam LSU_ERR_CODE_RD_FAILED = 3'b011; // 读访问失败
	localparam LSU_ERR_CODE_WT_FAILED = 3'b100; // 写访问失败
	
	/** ALU **/
	// ALU特定结果输出
	wire[31:0] ls_addr; // 访存地址
	
	assign m_alu_tid = s_alu_tid;
	assign m_alu_valid = s_alu_valid & s_alu_use_res;
	
	panda_risc_v_alu #(
		.en_shift_reuse("true"),
		.en_eq_cmp_reuse("false")
	)alu_u(
		.op_mode(s_alu_op_mode),
		.op1(s_alu_op1),
		.op2(s_alu_op2),
		
		.brc_cond_res(m_alu_brc_cond_res),
		.ls_addr(ls_addr),
		
		.res(m_alu_res)
	);
	
	/** CSR原子读写 **/
	assign csr_atom_raddr = s_csr_addr;
	
	assign m_csr_dout = csr_atom_dout;
	assign m_csr_tid = s_csr_tid;
	assign m_csr_valid = s_csr_valid;
	
	/** LSU **/
	wire[31:0] cur_ls_addr; // 当前的访存地址
	wire is_ls_addr_in_perph_region; // 访存地址处于外设区域(标志)
	
	assign cur_ls_addr = (EN_OUT_OF_ORDER_ISSUE == "true") ? s_lsu_ls_addr:ls_addr;
	assign is_ls_addr_in_perph_region = 
		((cur_ls_addr >= PERPH_ADDR_REGION_0_BASE) & (cur_ls_addr < (PERPH_ADDR_REGION_0_BASE + PERPH_ADDR_REGION_0_LEN))) | 
		((cur_ls_addr >= PERPH_ADDR_REGION_1_BASE) & (cur_ls_addr < (PERPH_ADDR_REGION_1_BASE + PERPH_ADDR_REGION_1_LEN)));
	
	panda_risc_v_lsu #(
		.INST_ID_WIDTH(IBUS_TID_WIDTH),
		.AXI_MEM_DATA_WIDTH(AXI_MEM_DATA_WIDTH),
		.MEM_ACCESS_TIMEOUT_TH(MEM_ACCESS_TIMEOUT_TH),
		.PERPH_ACCESS_TIMEOUT_TH(PERPH_ACCESS_TIMEOUT_TH),
		.LSU_REQ_BUF_ENTRY_N(LSU_REQ_BUF_ENTRY_N),
		.RD_MEM_BUF_ENTRY_N(RD_MEM_BUF_ENTRY_N),
		.WR_MEM_BUF_ENTRY_N(WR_MEM_BUF_ENTRY_N),
		.EN_LOW_LATENCY_PERPH_ACCESS(EN_LOW_LATENCY_PERPH_ACCESS),
		.EN_LOW_LATENCY_RD_MEM_ACCESS(EN_LOW_LATENCY_RD_MEM_ACCESS_IN_LSU),
		.EN_PERMISSION_CHECK_ON_SUBMIT_NEW_WR_MEM_REQ("false"),
		.SIM_DELAY(SIM_DELAY)
	)lsu_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.wr_mem_permitted_flag(wr_mem_permitted_flag),
		.init_mem_bus_tr_store_inst_tid(init_mem_bus_tr_store_inst_tid),
		.clr_wr_mem_buf(clr_wr_mem_buf),
		
		.perph_access_permitted_flag(perph_access_permitted_flag),
		.init_perph_bus_tr_ls_inst_tid(init_perph_bus_tr_ls_inst_tid),
		.cancel_subseq_perph_access(cancel_subseq_perph_access),
		
		.s_req_ls_sel(s_lsu_ls_sel),
		.s_req_ls_type(s_lsu_ls_type),
		.s_req_rd_id_for_ld(s_lsu_rd_id_for_ld),
		.s_req_ls_addr(cur_ls_addr),
		.s_req_ls_din(s_lsu_ls_din),
		.s_req_lsu_inst_id(s_lsu_inst_id),
		.s_req_ls_mem_access(~is_ls_addr_in_perph_region),
		.s_req_valid(s_lsu_valid),
		.s_req_ready(s_lsu_ready),
		
		.m_resp_ls_sel(m_lsu_ls_sel),
		.m_resp_rd_id_for_ld(m_lsu_rd_id_for_ld),
		.m_resp_dout_ls_addr(m_lsu_dout_ls_addr),
		.m_resp_err(m_lsu_err),
		.m_resp_lsu_inst_id(m_lsu_inst_id),
		.m_resp_valid(m_lsu_valid),
		.m_resp_ready(1'b1),
		
		.m_axi_mem_araddr(m_axi_mem_araddr),
		.m_axi_mem_arburst(m_axi_mem_arburst),
		.m_axi_mem_arlen(m_axi_mem_arlen),
		.m_axi_mem_arsize(m_axi_mem_arsize),
		.m_axi_mem_arvalid(m_axi_mem_arvalid),
		.m_axi_mem_arready(m_axi_mem_arready),
		.m_axi_mem_rdata(m_axi_mem_rdata),
		.m_axi_mem_rresp(m_axi_mem_rresp),
		.m_axi_mem_rlast(m_axi_mem_rlast),
		.m_axi_mem_rvalid(m_axi_mem_rvalid),
		.m_axi_mem_rready(m_axi_mem_rready),
		.m_axi_mem_awaddr(m_axi_mem_awaddr),
		.m_axi_mem_awburst(m_axi_mem_awburst),
		.m_axi_mem_awlen(m_axi_mem_awlen),
		.m_axi_mem_awsize(m_axi_mem_awsize),
		.m_axi_mem_awvalid(m_axi_mem_awvalid),
		.m_axi_mem_awready(m_axi_mem_awready),
		.m_axi_mem_bresp(m_axi_mem_bresp),
		.m_axi_mem_bvalid(m_axi_mem_bvalid),
		.m_axi_mem_bready(m_axi_mem_bready),
		.m_axi_mem_wdata(m_axi_mem_wdata),
		.m_axi_mem_wstrb(m_axi_mem_wstrb),
		.m_axi_mem_wlast(m_axi_mem_wlast),
		.m_axi_mem_wvalid(m_axi_mem_wvalid),
		.m_axi_mem_wready(m_axi_mem_wready),
		
		.m_axi_perph_araddr(m_axi_perph_araddr),
		.m_axi_perph_arburst(m_axi_perph_arburst),
		.m_axi_perph_arlen(m_axi_perph_arlen),
		.m_axi_perph_arsize(m_axi_perph_arsize),
		.m_axi_perph_arvalid(m_axi_perph_arvalid),
		.m_axi_perph_arready(m_axi_perph_arready),
		.m_axi_perph_rdata(m_axi_perph_rdata),
		.m_axi_perph_rresp(m_axi_perph_rresp),
		.m_axi_perph_rlast(m_axi_perph_rlast),
		.m_axi_perph_rvalid(m_axi_perph_rvalid),
		.m_axi_perph_rready(m_axi_perph_rready),
		.m_axi_perph_awaddr(m_axi_perph_awaddr),
		.m_axi_perph_awburst(m_axi_perph_awburst),
		.m_axi_perph_awlen(m_axi_perph_awlen),
		.m_axi_perph_awsize(m_axi_perph_awsize),
		.m_axi_perph_awvalid(m_axi_perph_awvalid),
		.m_axi_perph_awready(m_axi_perph_awready),
		.m_axi_perph_bresp(m_axi_perph_bresp),
		.m_axi_perph_bvalid(m_axi_perph_bvalid),
		.m_axi_perph_bready(m_axi_perph_bready),
		.m_axi_perph_wdata(m_axi_perph_wdata),
		.m_axi_perph_wstrb(m_axi_perph_wstrb),
		.m_axi_perph_wlast(m_axi_perph_wlast),
		.m_axi_perph_wvalid(m_axi_perph_wvalid),
		.m_axi_perph_wready(m_axi_perph_wready),
		
		.on_get_instant_rd_mem_res_s0(on_get_instant_rd_mem_res_s0),
		.inst_id_of_instant_rd_mem_res_gotten_s0(inst_id_of_instant_rd_mem_res_gotten_s0),
		.data_of_instant_rd_mem_res_gotten_s0(data_of_instant_rd_mem_res_gotten_s0),
		.on_get_instant_rd_mem_res_s1(on_get_instant_rd_mem_res_s1),
		.inst_id_of_instant_rd_mem_res_gotten_s1(inst_id_of_instant_rd_mem_res_gotten_s1),
		.data_of_instant_rd_mem_res_gotten_s1(data_of_instant_rd_mem_res_gotten_s1),
		
		.has_buffered_wr_mem_req(has_buffered_wr_mem_req),
		.has_processing_perph_access_req(has_processing_perph_access_req),
		
		.rd_mem_timeout(rd_mem_timeout),
		.wr_mem_timeout(wr_mem_timeout),
		.perph_access_timeout(perph_access_timeout)
	);
	
	/** 乘法器 **/
	panda_risc_v_multiplier #(
		.inst_id_width(IBUS_TID_WIDTH),
		.sgn_period_mul(EN_SGN_PERIOD_MUL),
		.simulation_delay(SIM_DELAY)
	)multiplier_u(
		.clk(aclk),
		.resetn(aresetn),
		
		.s_mul_req_op_a(s_mul_op_a),
		.s_mul_req_op_b(s_mul_op_b),
		.s_mul_req_res_sel(s_mul_res_sel),
		.s_mul_req_rd_id(s_mul_rd_id),
		.s_mul_req_inst_id(s_mul_inst_id),
		.s_mul_req_valid(s_mul_valid),
		.s_mul_req_ready(s_mul_ready),
		
		.m_mul_res_data(m_mul_data),
		.m_mul_res_rd_id(m_mul_rd_id),
		.m_mul_res_inst_id(m_mul_inst_id),
		.m_mul_res_valid(m_mul_valid),
		.m_mul_res_ready(1'b1)
	);
	
	/** 除法器 **/
	panda_risc_v_divider #(
		.inst_id_width(IBUS_TID_WIDTH),
		.simulation_delay(SIM_DELAY)
	)divider_u(
		.clk(aclk),
		.resetn(aresetn),
		
		.s_div_req_op_a(s_div_op_a),
		.s_div_req_op_b(s_div_op_b),
		.s_div_req_rem_sel(s_div_rem_sel),
		.s_div_req_rd_id(s_div_rd_id),
		.s_div_req_inst_id(s_div_inst_id),
		.s_div_req_valid(s_div_valid),
		.s_div_req_ready(s_div_ready),
		
		.m_div_res_data(m_div_data),
		.m_div_res_rd_id(m_div_rd_id),
		.m_div_res_inst_id(m_div_inst_id),
		.m_div_res_valid(m_div_valid),
		.m_div_res_ready(1'b1)
	);
	
	/** 执行单元结果返回 **/
	generate
		if(EN_OUT_OF_ORDER_ISSUE == "true")
		begin
			assign fu_res_vld = {bru_nominal_res_vld, m_div_valid, m_mul_valid, m_lsu_valid, m_csr_valid, m_alu_valid};
			assign fu_res_tid = {bru_nominal_res_tid, m_div_inst_id, m_mul_inst_id, m_lsu_inst_id, m_csr_tid, m_alu_tid};
			assign fu_res_data = {
				bru_nominal_res,
				m_div_data,
				m_mul_data,
				m_lsu_dout_ls_addr, // 发送LSU错误时给出访存地址而非读数据
				m_csr_dout,
				m_alu_res
			};
			assign fu_res_err = {
				3'b000,
				3'b000, 
				3'b000, 
				({3{m_lsu_err == DBUS_ACCESS_NORMAL}} & 
					LSU_ERR_CODE_NORMAL) | 
				({3{(m_lsu_err == DBUS_ACCESS_LS_UNALIGNED) & (~m_lsu_ls_sel)}} & 
					LSU_ERR_CODE_RD_ADDR_UNALIGNED) | 
				({3{(m_lsu_err == DBUS_ACCESS_LS_UNALIGNED) & m_lsu_ls_sel}} & 
					LSU_ERR_CODE_WT_ADDR_UNALIGNED) | 
				({3{((m_lsu_err == DBUS_ACCESS_BUS_ERR) | (m_lsu_err == DBUS_ACCESS_TIMEOUT)) & (~m_lsu_ls_sel)}} & 
					LSU_ERR_CODE_RD_FAILED) | 
				({3{((m_lsu_err == DBUS_ACCESS_BUS_ERR) | (m_lsu_err == DBUS_ACCESS_TIMEOUT)) & m_lsu_ls_sel}} & 
					LSU_ERR_CODE_WT_FAILED), 
				3'b000, 
				3'b000
			};
		end
		else
		begin
			assign fu_res_vld = {m_div_valid, m_mul_valid, m_lsu_valid, m_csr_valid, m_alu_valid};
			assign fu_res_tid = {m_div_inst_id, m_mul_inst_id, m_lsu_inst_id, m_csr_tid, m_alu_tid};
			assign fu_res_data = {
				m_div_data,
				m_mul_data,
				m_lsu_dout_ls_addr, // 发送LSU错误时给出访存地址而非读数据
				m_csr_dout,
				m_alu_res
			};
			assign fu_res_err = {
				3'b000, 
				3'b000, 
				({3{m_lsu_err == DBUS_ACCESS_NORMAL}} & 
					LSU_ERR_CODE_NORMAL) | 
				({3{(m_lsu_err == DBUS_ACCESS_LS_UNALIGNED) & (~m_lsu_ls_sel)}} & 
					LSU_ERR_CODE_RD_ADDR_UNALIGNED) | 
				({3{(m_lsu_err == DBUS_ACCESS_LS_UNALIGNED) & m_lsu_ls_sel}} & 
					LSU_ERR_CODE_WT_ADDR_UNALIGNED) | 
				({3{((m_lsu_err == DBUS_ACCESS_BUS_ERR) | (m_lsu_err == DBUS_ACCESS_TIMEOUT)) & (~m_lsu_ls_sel)}} & 
					LSU_ERR_CODE_RD_FAILED) | 
				({3{((m_lsu_err == DBUS_ACCESS_BUS_ERR) | (m_lsu_err == DBUS_ACCESS_TIMEOUT)) & m_lsu_ls_sel}} & 
					LSU_ERR_CODE_WT_FAILED), 
				3'b000, 
				3'b000
			};
		end
	endgenerate
	
endmodule
