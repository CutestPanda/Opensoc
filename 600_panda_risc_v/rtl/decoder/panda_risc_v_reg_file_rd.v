`timescale 1ns / 1ps
/********************************************************************
本模块: 译码阶段的通用寄存器读控制

描述:
接受通用寄存器堆读请求, 分别访问2个通用寄存器堆读端口, 
	给出源寄存器读结果

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/11/22
********************************************************************/


module panda_risc_v_reg_file_rd #(
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// 复位/冲刷请求
	input wire sys_reset_req, // 系统复位请求
	input wire flush_req, // 冲刷请求
	
	// 数据相关性
	output wire[4:0] raw_dpc_check_rs1_id, // 待检查RAW相关性的RS1索引
	input wire rs1_raw_dpc, // RS1有RAW相关性(标志)
	output wire[4:0] raw_dpc_check_rs2_id, // 待检查RAW相关性的RS2索引
	input wire rs2_raw_dpc, // RS2有RAW相关性(标志)
	
	// 读通用寄存器堆请求
	input wire[4:0] rs1_id, // RS1索引
	input wire[4:0] rs2_id, // RS2索引
	input wire rs1_vld, // 是否需要读RS1(标志)
	input wire rs2_vld, // 是否需要读RS2(标志)
	input wire reg_file_rd_req_valid,
	output wire reg_file_rd_req_ready,
	
	// 源寄存器读结果
	output wire[31:0] rs1_v, // RS1读结果
	output wire[31:0] rs2_v, // RS2读结果
	output wire reg_file_rd_res_valid,
	input wire reg_file_rd_res_ready,
	
	// 译码器给出的通用寄存器堆读端口#0
	output wire dcd_reg_file_rd_p0_req, // 读请求
	output wire[4:0] dcd_reg_file_rd_p0_addr, // 读地址
	input wire dcd_reg_file_rd_p0_grant, // 读许可
	input wire[31:0] dcd_reg_file_rd_p0_dout, // 读数据
	// 译码器给出的通用寄存器堆读端口#1
	output wire dcd_reg_file_rd_p1_req, // 读请求
	output wire[4:0] dcd_reg_file_rd_p1_addr, // 读地址
	input wire dcd_reg_file_rd_p1_grant, // 读许可
	input wire[31:0] dcd_reg_file_rd_p1_dout // 读数据
);
	
	reg[31:0] reg_file_rd_p0_dout_latched; // 锁存的RS1读结果
	reg[31:0] reg_file_rd_p1_dout_latched; // 锁存的RS2读结果
	reg to_sel_latched_rs1_v; // 选择锁存的RS1读结果(标志)
	reg to_sel_latched_rs2_v; // 选择锁存的RS2读结果(标志)
	wire on_flush_rst; // 当前冲刷或复位(指示)
	wire reg_file_rd_done; // 通用寄存器堆读完成(标志)
	
	assign raw_dpc_check_rs1_id = rs1_id;
	assign raw_dpc_check_rs2_id = rs2_id;
	
	// 握手条件: reg_file_rd_req_valid & reg_file_rd_res_ready & reg_file_rd_done
	assign reg_file_rd_req_ready = 
		reg_file_rd_res_ready & // 后级准备好取走源寄存器读结果
		reg_file_rd_done; // 通用寄存器堆读完成
	
	assign rs1_v = to_sel_latched_rs1_v ? reg_file_rd_p0_dout_latched:dcd_reg_file_rd_p0_dout;
	assign rs2_v = to_sel_latched_rs2_v ? reg_file_rd_p1_dout_latched:dcd_reg_file_rd_p1_dout;
	// 握手条件: reg_file_rd_req_valid & reg_file_rd_res_ready & reg_file_rd_done
	assign reg_file_rd_res_valid = 
		reg_file_rd_req_valid & // 请求有效
		reg_file_rd_done; // 通用寄存器堆读完成
	
	assign dcd_reg_file_rd_p0_req = 
		reg_file_rd_req_valid & rs1_vld & // 请求有效且需要读RS1
		(~on_flush_rst) & // 不处于冲刷或复位状态
		(~rs1_raw_dpc) & // RS1没有RAW相关性
		(~to_sel_latched_rs1_v); // RS1读结果未锁存
	assign dcd_reg_file_rd_p0_addr = rs1_id;
	
	assign dcd_reg_file_rd_p1_req = 
		reg_file_rd_req_valid & rs2_vld & // 请求有效且需要读RS2
		(~on_flush_rst) & // 不处于冲刷或复位状态
		(~rs2_raw_dpc) & // RS2没有RAW相关性
		(~to_sel_latched_rs2_v); // RS2读结果未锁存
	assign dcd_reg_file_rd_p1_addr = rs2_id;
	
	assign on_flush_rst = sys_reset_req | flush_req;
	assign reg_file_rd_done = 
		(~on_flush_rst) & // 不处于冲刷或复位状态(是否有必要???)
		((~rs1_vld) | (dcd_reg_file_rd_p0_grant | to_sel_latched_rs1_v)) & // 不需要读RS1或已经读回
		((~rs2_vld) | (dcd_reg_file_rd_p1_grant | to_sel_latched_rs2_v)); // 不需要读RS2或已经读回
	
	// 锁存的RS1读结果
	always @(posedge clk)
	begin
		if(dcd_reg_file_rd_p0_grant)
			reg_file_rd_p0_dout_latched <= # simulation_delay dcd_reg_file_rd_p0_dout;
	end
	// 锁存的RS2读结果
	always @(posedge clk)
	begin
		if(dcd_reg_file_rd_p1_grant)
			reg_file_rd_p1_dout_latched <= # simulation_delay dcd_reg_file_rd_p1_dout;
	end
	
	// 选择锁存的RS1读结果(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			to_sel_latched_rs1_v <= 1'b0;
		else
			/*
			(~on_flush_rst) & // 不处于冲刷或复位状态
			(to_sel_latched_rs1_v ? 
				(rs2_vld ? ((~(dcd_reg_file_rd_p1_grant | to_sel_latched_rs2_v)) | (~reg_file_rd_res_ready)):
					(~reg_file_rd_res_ready)):
				// RS1读许可
				(dcd_reg_file_rd_p0_grant &
				// 需要读RS2但尚未读回, 或者后级未取走源寄存器读结果
				(rs2_vld ? ((~(dcd_reg_file_rd_p1_grant | to_sel_latched_rs2_v)) | (~reg_file_rd_res_ready)):
					(~reg_file_rd_res_ready))))
			*/
			to_sel_latched_rs1_v <= # simulation_delay 
				(~on_flush_rst) & 
				(to_sel_latched_rs1_v | dcd_reg_file_rd_p0_grant) & 
				((rs2_vld & (~(dcd_reg_file_rd_p1_grant | to_sel_latched_rs2_v))) | (~reg_file_rd_res_ready));
	end
	// 选择锁存的RS2读结果(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			to_sel_latched_rs2_v <= 1'b0;
		else
			/*
			(~on_flush_rst) & // 不处于冲刷或复位状态
			(to_sel_latched_rs2_v ? 
				(rs1_vld ? ((~(dcd_reg_file_rd_p0_grant | to_sel_latched_rs1_v)) | (~reg_file_rd_res_ready)):
					(~reg_file_rd_res_ready)):
				// RS2读许可
				(dcd_reg_file_rd_p1_grant &
				// 需要读RS1但尚未读回, 或者后级未取走源寄存器读结果
				(rs1_vld ? ((~(dcd_reg_file_rd_p0_grant | to_sel_latched_rs1_v)) | (~reg_file_rd_res_ready)):
					(~reg_file_rd_res_ready))))
			*/
			to_sel_latched_rs2_v <= # simulation_delay 
				(~on_flush_rst) & 
				(to_sel_latched_rs2_v | dcd_reg_file_rd_p1_grant) & 
				((rs1_vld & (~(dcd_reg_file_rd_p0_grant | to_sel_latched_rs1_v))) | (~reg_file_rd_res_ready));
	end
	
endmodule
