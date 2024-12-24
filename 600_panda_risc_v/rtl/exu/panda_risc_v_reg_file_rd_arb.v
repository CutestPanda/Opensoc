`timescale 1ns / 1ps
/********************************************************************
本模块: 通用寄存器堆读仲裁

描述:
通用寄存器堆读端口#0 --> 译码器给出的通用寄存器堆读端口#0

                       |--> 译码器给出的通用寄存器堆读端口#1
通用寄存器堆读端口#1 --
                       |--> JALR指令读基址给出的通用寄存器堆读端口#0

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/12/24
********************************************************************/


module panda_risc_v_reg_file_rd_arb(
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
	
	/** 译码器给出的通用寄存器堆读端口#0 **/
	assign dcd_reg_file_rd_p0_grant = dcd_reg_file_rd_p0_req;
	assign dcd_reg_file_rd_p0_dout = reg_file_dout_p0;
	
	/** 译码器给出的通用寄存器堆读端口#1 **/
	assign dcd_reg_file_rd_p1_grant = dcd_reg_file_rd_p1_req & (~jalr_reg_file_rd_p0_req);
	assign dcd_reg_file_rd_p1_dout = reg_file_dout_p1;
	
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
