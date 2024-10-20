`timescale 1ns / 1ps
/********************************************************************
本模块: 指令存储器访问控制

描述:
将取指结果传递到下级, 同时发起新的指令存储器访问请求, 并更新PC

注意：
无

协议:
AXIS MASTER

作者: 陈家耀
日期: 2024/10/19
********************************************************************/


module panda_risc_v_imem_access_ctrler #(
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// 当前的PC
	output wire[31:0] now_pc,
	// 新的PC
	input wire[31:0] new_pc,
	// 当前的指令
	output wire[31:0] now_inst,
	
	// 预译码信息
	input wire is_jalr_inst, // 是否JALR指令
	input wire illegal_inst, // 非法指令(标志)
	input wire[63:0] pre_decoding_msg_packeted, // 打包的预译码信息
	
	// JALR指令基址读完成
	input wire jalr_baseaddr_vld,
	
	// 是否预测跳转
	input wire to_jump,
	
	// 指令存储器访问请求
	output wire[31:0] imem_access_req_addr,
	output wire imem_access_req_read, // const -> 1'b1
	output wire[31:0] imem_access_req_wdata, // const -> 32'hxxxx_xxxx
	output wire[3:0] imem_access_req_wmask, // const -> 4'b0000
	output wire imem_access_req_valid,
	input wire imem_access_req_ready,
	
	// 指令存储器访问应答
	input wire[31:0] imem_access_resp_rdata,
	input wire[1:0] imem_access_resp_err, // 错误类型(2'b00 -> 正常, 2'b01 -> 指令地址非对齐, 
										  //          2'b10 -> 指令总线访问错误, 2'b11 -> 响应超时)
	input wire imem_access_resp_valid,
	
	// 取指结果(AXIS主机)
	output wire[127:0] m_axis_if_res_data, // {打包的预译码信息(64bit), 指令对应的PC(32bit), 取到的指令(32bit)}
	output wire[3:0] m_axis_if_res_user, // {是否预测跳转(1bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)}
	output wire m_axis_if_res_valid,
	input wire m_axis_if_res_ready
);
	
	/** 常量 **/
	localparam NOP_INST = 32'h0000_0013; // 空指令
	// 指令存储器访问应答错误类型
	localparam IMEM_ACCESS_NORMAL = 2'b00; // 正常
	localparam IMEM_ACCESS_PC_UNALIGNED = 2'b01; // 指令地址非对齐
	localparam IMEM_ACCESS_BUS_ERR = 2'b10; // 指令总线访问错误
	localparam IMEM_ACCESS_TIMEOUT = 2'b11; // 响应超时
	
	/** 取指结果缓存区 **/
	wire[1:0] now_imem_access_err_code; // 当前的指令存储器访问错误码
	reg[31:0] inst_fetched; // 取到的指令
	reg[1:0] imem_access_err_code; // 指令存储器访问错误码
	reg if_res_latched_flag; // 取指结果已锁存(标志)
	wire jalr_pass_allowed; // JALR指令传递许可(标志)
	
	// 握手条件: (imem_access_resp_valid | if_res_latched_flag) & 
	//     m_axis_if_res_ready & jalr_pass_allowed & imem_access_req_ready
	assign m_axis_if_res_valid = (imem_access_resp_valid | if_res_latched_flag) & jalr_pass_allowed & imem_access_req_ready;
	
	assign now_inst = if_res_latched_flag ? inst_fetched:imem_access_resp_rdata;
	assign now_imem_access_err_code = if_res_latched_flag ? imem_access_err_code:imem_access_resp_err;
	
	assign jalr_pass_allowed = (~is_jalr_inst) | jalr_baseaddr_vld;
	
	// 取到的指令
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			inst_fetched <= NOP_INST;
		else if(imem_access_resp_valid)
			inst_fetched <= # simulation_delay imem_access_resp_rdata;
	end
	// 指令存储器访问错误码
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			imem_access_err_code <= IMEM_ACCESS_NORMAL;
		else if(imem_access_resp_valid)
			imem_access_err_code <= # simulation_delay imem_access_resp_err;
	end
	
	// 取指结果已锁存(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			if_res_latched_flag <= 1'b1; // 复位时IFU上的取指结果是有效的
		else
			/*
			if_res_latched_flag ? 
				(~(m_axis_if_res_ready & jalr_pass_allowed & imem_access_req_ready)): // 等待后级取走指令及附加信息
				(imem_access_resp_valid & (~(m_axis_if_res_ready
					& jalr_pass_allowed & imem_access_req_ready))); // 指令及附加信息无法被立即传递时进行锁存
			*/
			if_res_latched_flag <= # simulation_delay (if_res_latched_flag | imem_access_resp_valid)
				& (~(m_axis_if_res_ready & jalr_pass_allowed & imem_access_req_ready));
	end
	
	/** 发起指令存储器访问请求 **/
	assign imem_access_req_addr = new_pc;
	assign imem_access_req_read = 1'b1;
	assign imem_access_req_wdata = 32'hxxxx_xxxx;
	assign imem_access_req_wmask = 4'b0000;
	// 握手条件: (imem_access_resp_valid | if_res_latched_flag) & 
	//     m_axis_if_res_ready & jalr_pass_allowed & imem_access_req_ready
	assign imem_access_req_valid = (imem_access_resp_valid | if_res_latched_flag) & jalr_pass_allowed & m_axis_if_res_ready;
	
	/** PC寄存器 **/
	wire to_upd_pc; // 更新PC(指示)
	reg[31:0] now_pc_regs; // 当前的PC
	
	assign now_pc = now_pc_regs;
	
	assign m_axis_if_res_data = {pre_decoding_msg_packeted, now_pc_regs, now_inst};
	assign m_axis_if_res_user = {to_jump, illegal_inst, now_imem_access_err_code};
	// {是否预测跳转(1bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)}
	
	assign to_upd_pc = (imem_access_resp_valid | if_res_latched_flag) & 
		m_axis_if_res_ready & jalr_pass_allowed & imem_access_req_ready;
	
	// 当前的PC
	// PC寄存器无需复位!
	always @(posedge clk)
	begin
		if(to_upd_pc)
			now_pc_regs <= # simulation_delay new_pc;
	end
	
endmodule
