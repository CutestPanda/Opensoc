`timescale 1ns / 1ps
/********************************************************************
本模块: 通用寄存器堆读仲裁

描述:
通用寄存器堆读端口#0 --> 译码器给出的通用寄存器堆读端口#0

                       |--> 译码器给出的通用寄存器堆读端口#1
通用寄存器堆读端口#1 --|
                       |--> JALR指令读基址给出的通用寄存器堆读端口#0

注意：
无

协议:
REQ/GRANT

作者: 陈家耀
日期: 2025/01/15
********************************************************************/


module panda_risc_v_reg_file_rd_arb #(
	parameter en_alu_csr_rw_bypass = "true" // 是否使能ALU/CSR原子读写单元的数据旁路
)(
	// ALU/CSR原子读写单元的数据旁路
	input wire dcd_reg_file_rd_p0_bypass, // 需要旁路到译码器给出的通用寄存器堆读端口#0
	input wire dcd_reg_file_rd_p1_bypass, // 需要旁路到译码器给出的通用寄存器堆读端口#1
	input wire is_csr_rw_inst, // 是否CSR读写指令
	input wire[31:0] alu_res, // ALU计算结果
	input wire[31:0] csr_atom_rw_dout, // CSR原值
	
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
	
	// 通用寄存器堆读端口#0
	output wire[4:0] reg_file_raddr_p0,
	input wire[31:0] reg_file_dout_p0,
	// 通用寄存器堆读端口#1
	output wire[4:0] reg_file_raddr_p1,
	input wire[31:0] reg_file_dout_p1,
	
	// 通用寄存器#1的值
	input wire[31:0] x1_v
);
	
	/** 数据旁路 **/
	wire[31:0] alu_csr_rw_res_bypass; // 旁路的ALU计算结果或CSR原值
	
	assign alu_csr_rw_res_bypass = is_csr_rw_inst ? csr_atom_rw_dout:alu_res;
	
	/** 译码器给出的通用寄存器堆读端口#0 **/
	assign dcd_reg_file_rd_p0_grant = dcd_reg_file_rd_p0_req;
	assign dcd_reg_file_rd_p0_dout = 
		((en_alu_csr_rw_bypass == "true") & dcd_reg_file_rd_p0_bypass) ? 
			alu_csr_rw_res_bypass:
			reg_file_dout_p0;
	
	/** 译码器给出的通用寄存器堆读端口#1 **/
	assign dcd_reg_file_rd_p1_grant = dcd_reg_file_rd_p1_req & (~jalr_reg_file_rd_p0_req);
	assign dcd_reg_file_rd_p1_dout = 
		((en_alu_csr_rw_bypass == "true") & dcd_reg_file_rd_p1_bypass) ? 
			alu_csr_rw_res_bypass:
			reg_file_dout_p1;
	
	/** 专用于JALR指令的通用寄存器堆读端口 **/
	assign jalr_x1_v = x1_v;
	
	/** JALR指令读基址给出的通用寄存器堆读端口#0 **/
	assign jalr_reg_file_rd_p0_grant = jalr_reg_file_rd_p0_req;
	assign jalr_reg_file_rd_p0_dout = reg_file_dout_p1;
	
	/** 通用寄存器堆读端口#0 **/
	assign reg_file_raddr_p0 = dcd_reg_file_rd_p0_addr;
	
	/** 通用寄存器堆读端口#1 **/
	// JALR指令读基址给出的通用寄存器堆读端口#0的优先级 > 译码器给出的通用寄存器堆读端口#1的优先级
	assign reg_file_raddr_p1 = jalr_reg_file_rd_p0_req ? jalr_reg_file_rd_p0_addr:dcd_reg_file_rd_p1_addr;
	
endmodule
