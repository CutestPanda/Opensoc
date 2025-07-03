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
LSU的访存地址由ALU计算得到

协议:
无

作者: 陈家耀
日期: 2025/06/19
********************************************************************/


module panda_risc_v_func_units #(
	parameter integer IBUS_TID_WIDTH = 8, // 指令总线事务ID位宽(1~16)
	parameter integer DBUS_ACCESS_TIMEOUT_TH = 16, // 数据总线访问超时周期数(必须>=1)
	parameter EN_SGN_PERIOD_MUL = "true", // 是否使用单周期乘法器
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
	input wire[31:0] s_lsu_ls_din, // 写数据
	input wire[IBUS_TID_WIDTH-1:0] s_lsu_inst_id, // 指令ID
	input wire s_lsu_valid,
	output wire s_lsu_ready,
	// [访问输出]
	output wire m_lsu_ls_sel, // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	output wire[4:0] m_lsu_rd_id_for_ld, // 用于加载的目标寄存器的索引
	output wire[31:0] m_lsu_dout, // 读数据
	output wire[31:0] m_lsu_ls_addr, // 访存地址
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
	
	// 执行单元结果返回
	output wire[4:0] fu_res_vld, // 有效标志
	output wire[5*IBUS_TID_WIDTH-1:0] fu_res_tid, // 指令ID
	output wire[5*32-1:0] fu_res_data, // 执行结果
	output wire[5*3-1:0] fu_res_err, // 错误码
	
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
	
	// LSU状态
	output wire dbus_timeout, // 数据总线访问超时标志
	output wire lsu_idle // 访存单元空闲(标志)
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
	wire[31:0] alu_ls_addr; // 访存地址
	
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
		.ls_addr(alu_ls_addr),
		
		.res(m_alu_res)
	);
	
	/** CSR原子读写 **/
	assign csr_atom_raddr = s_csr_addr;
	
	assign m_csr_dout = csr_atom_dout;
	assign m_csr_tid = s_csr_tid;
	assign m_csr_valid = s_csr_valid;
	
	/** LSU **/
	panda_risc_v_lsu #(
		.inst_id_width(IBUS_TID_WIDTH),
		.dbus_access_timeout_th(DBUS_ACCESS_TIMEOUT_TH),
		.icb_zero_latency_supported("false"),
		.simulation_delay(SIM_DELAY)
	)lsu_u(
		.clk(aclk),
		.resetn(aresetn),
		
		.lsu_idle(lsu_idle),
		
		.s_req_ls_sel(s_lsu_ls_sel),
		.s_req_ls_type(s_lsu_ls_type),
		.s_req_rd_id_for_ld(s_lsu_rd_id_for_ld),
		.s_req_ls_addr(alu_ls_addr), // 访存地址由ALU计算得到
		.s_req_ls_din(s_lsu_ls_din),
		.s_req_lsu_inst_id(s_lsu_inst_id),
		.s_req_valid(s_lsu_valid),
		.s_req_ready(s_lsu_ready),
		
		.m_resp_ls_sel(m_lsu_ls_sel),
		.m_resp_rd_id_for_ld(m_lsu_rd_id_for_ld),
		.m_resp_dout(m_lsu_dout),
		.m_resp_ls_addr(m_lsu_ls_addr),
		.m_resp_err(m_lsu_err),
		.m_resp_lsu_inst_id(m_lsu_inst_id),
		.m_resp_valid(m_lsu_valid),
		.m_resp_ready(1'b1),
		
		.m_icb_cmd_addr(m_icb_cmd_data_addr),
		.m_icb_cmd_read(m_icb_cmd_data_read),
		.m_icb_cmd_wdata(m_icb_cmd_data_wdata),
		.m_icb_cmd_wmask(m_icb_cmd_data_wmask),
		.m_icb_cmd_valid(m_icb_cmd_data_valid),
		.m_icb_cmd_ready(m_icb_cmd_data_ready),
		.m_icb_rsp_rdata(m_icb_rsp_data_rdata),
		.m_icb_rsp_err(m_icb_rsp_data_err),
		.m_icb_rsp_valid(m_icb_rsp_data_valid),
		.m_icb_rsp_ready(m_icb_rsp_data_ready),
		
		.dbus_timeout(dbus_timeout)
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
	assign fu_res_vld = {m_div_valid, m_mul_valid, m_lsu_valid, m_csr_valid, m_alu_valid};
	assign fu_res_tid = {m_div_inst_id, m_mul_inst_id, m_lsu_inst_id, m_csr_tid, m_alu_tid};
	assign fu_res_data = {
		m_div_data, 
		m_mul_data, 
		// 发送LSU错误时给出访存地址而非读数据
		(m_lsu_err == DBUS_ACCESS_NORMAL) ? 
			m_lsu_dout:
			m_lsu_ls_addr, 
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
	
endmodule
