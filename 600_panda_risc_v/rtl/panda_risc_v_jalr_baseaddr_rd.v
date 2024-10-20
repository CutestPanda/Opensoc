`timescale 1ns / 1ps
/********************************************************************
本模块: 读JALR指令基址

描述:
从专用于JALR指令的通用寄存器堆读端口获取基址

     RS1编号                 操作
        x0                 直接返回
	    x1             无RAW相关性时返回
	  x2~x31   无RAW相关性时请求通用寄存器堆读端口#0, 
			           等待读许可后返回

注意：
无

协议:
REQ/GRANT

作者: 陈家耀
日期: 2024/10/20
********************************************************************/


module panda_risc_v_jalr_baseaddr_rd #(
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// 数据相关性
	input wire rs1_raw_dpc, // RS1有RAW相关性(标志)
	
	// rs1索引
	input wire[4:0] rs1_id,
	
	// 专用于JALR指令的通用寄存器堆读端口
	input wire[31:0] jalr_x1_v, // 通用寄存器#1读结果
	// JALR指令读基址给出的通用寄存器读端口#0
	output wire jalr_reg_file_rd_p0_req, // 读请求
	output wire[4:0] jalr_rd_p0_addr, // 读地址
	input wire jalr_reg_file_rd_p0_grant, // 读许可
	input wire[31:0] jalr_reg_file_rd_p0_dout, // 读数据
	
	// 基址获取状态
	input wire imem_access_resp_valid, // 指令存储器访问应答有效
	input wire is_jalr_inst, // 是否JALR指令
	output wire jalr_baseaddr_vld, // JALR指令基址读完成
	output wire[31:0] jalr_baseaddr_v // 基址读结果
);
	
	/** 通用寄存器读端口#0 **/
	wire now_inst_need_baseaddr_from_p0; // 当前指令需要从通用寄存器读端口#0获取基址
	reg to_continue_req_for_reg_file_rd_p0; // 继续请求通用寄存器读端口#0
	
	assign jalr_reg_file_rd_p0_req = (imem_access_resp_valid | to_continue_req_for_reg_file_rd_p0)
		& now_inst_need_baseaddr_from_p0 & (~rs1_raw_dpc);
	assign jalr_rd_p0_addr = rs1_id;
	
	assign now_inst_need_baseaddr_from_p0 = is_jalr_inst & (rs1_id != 5'd0) & (rs1_id != 5'd1);
	
	// 继续请求通用寄存器读端口#0
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			to_continue_req_for_reg_file_rd_p0 <= 1'b0;
		else
			/*
			to_continue_req_for_reg_file_rd_p0 ? 
				(~jalr_reg_file_rd_p0_grant): // 等待读许可
				(imem_access_resp_valid & now_inst_need_baseaddr_from_p0
					& (~jalr_reg_file_rd_p0_grant)); // 需要从通用寄存器读端口#0获取基址但不被立即许可, 则延长请求信号
			*/
			to_continue_req_for_reg_file_rd_p0 <= # simulation_delay 
				(to_continue_req_for_reg_file_rd_p0 | (imem_access_resp_valid & now_inst_need_baseaddr_from_p0))
					& (~jalr_reg_file_rd_p0_grant);
	end
	
	/** 读通用寄存器#1 **/
	wire now_inst_need_baseaddr_from_x1; // 当前指令需要从通用寄存器#1获取基址
	reg to_continue_rd_x1; // 继续读通用寄存器#1
	
	assign now_inst_need_baseaddr_from_x1 = is_jalr_inst & (rs1_id == 5'd1);
	
	// 继续读通用寄存器#1
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			to_continue_rd_x1 <= 1'b0;
		else
			/*
			to_continue_rd_x1 ? 
				rs1_raw_dpc: // 等待RAW相关性解除
				(imem_access_resp_valid & now_inst_need_baseaddr_from_x1
					& rs1_raw_dpc); // 需要从通用寄存器#1获取基址但存在RAW相关性, 则继续读
			*/
			to_continue_rd_x1 <= # simulation_delay 
				(to_continue_rd_x1 | (imem_access_resp_valid & now_inst_need_baseaddr_from_x1))
					& rs1_raw_dpc;
	end
	
	/** JALR指令基址读结果 **/
	wire baseaddr_fetch_idct; // 获取到基址(指示)
	wire[31:0] baseaddr_fetched; // 目前获取到的基址
	reg baseaddr_fetch_flag_ext; // 延长的获取到基址(标志)
	reg[31:0] baseaddr; // 保存的基址
	
	// 如果当前取到新的指令, 应将最新的获取到基址指示信号作为JALR指令基址读完成
	assign jalr_baseaddr_vld = baseaddr_fetch_idct | ((~imem_access_resp_valid) & baseaddr_fetch_flag_ext);
	// 如果当前获取到有效的基址, 将目前获取到的基址旁路出去, 否则使用保存的基址
	assign jalr_baseaddr_v = baseaddr_fetch_idct ? baseaddr_fetched:baseaddr;
	
	assign baseaddr_fetch_idct = (imem_access_resp_valid | to_continue_req_for_reg_file_rd_p0 | to_continue_rd_x1)
		& is_jalr_inst
		& (
			(rs1_id == 5'd0) ? 1'b1:
			(rs1_id == 5'd1) ? (~rs1_raw_dpc):
							   jalr_reg_file_rd_p0_grant
		);
	assign baseaddr_fetched = {32{rs1_id != 5'd0}} & (
		(rs1_id == 5'd1) ? jalr_x1_v:
						   jalr_reg_file_rd_p0_dout
	);
	
	// 延长的获取到基址(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			baseaddr_fetch_flag_ext <= 1'b0;
		else
			/*
			baseaddr_fetch_flag_ext ? 
				(~(imem_access_resp_valid & (~baseaddr_fetch_idct))): // 当前取到新的指令, 但未获取到有效的基址, 则不再延长
				baseaddr_fetch_idct; // 延长获取到基址指示信号
			*/
			baseaddr_fetch_flag_ext <= # simulation_delay 
				(baseaddr_fetch_flag_ext & (~imem_access_resp_valid)) | baseaddr_fetch_idct;
	end
	
	// 保存的基址
	always @(posedge clk)
	begin
		if(baseaddr_fetch_idct)
			baseaddr <= # simulation_delay baseaddr_fetched;
	end
	
endmodule
