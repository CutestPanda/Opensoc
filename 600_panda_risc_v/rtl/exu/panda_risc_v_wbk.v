`timescale 1ns / 1ps
/********************************************************************
本模块: 写回单元

描述:
对来自ALU或CSR原子读写单元、LSU、乘法器、除法器的写回请求进行仲裁, 驱动通用寄存器堆写端口
若LSU传回数据总线访问错误或响应超时的响应, 则产生LSU异常

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/12/24
********************************************************************/


module panda_risc_v_wbk #(
    parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// 来自ALU或CSR原子读写单元的写回请求
	input wire[31:0] s_alu_csr_wbk_data, // 计算结果或CSR原值
	input wire[4:0] s_alu_csr_wbk_rd_id, // RD索引
	input wire s_alu_csr_wbk_rd_vld, // 是否需要写RD
	input wire s_alu_csr_wbk_valid,
	output wire s_alu_csr_wbk_ready,
	
	// 来自LSU的写回请求
	input wire s_lsu_wbk_ls_sel, // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	input wire[4:0] s_lsu_wbk_rd_id_for_ld, // 用于加载的目标寄存器的索引
	input wire[31:0] s_lsu_wbk_dout, // 读数据
	input wire[31:0] s_lsu_wbk_ls_addr, // 访存地址
	input wire[1:0] s_lsu_wbk_err, // 错误类型
	input wire s_lsu_wbk_valid,
	output wire s_lsu_wbk_ready,
	
	// 来自乘法器的写回请求
	input wire[31:0] s_mul_wbk_data, // 计算结果
	input wire[4:0] s_mul_wbk_rd_id, // RD索引
	input wire s_mul_wbk_valid,
	output wire s_mul_wbk_ready,
	
	// 来自除法器的写回请求
	input wire[31:0] s_div_wbk_data, // 计算结果
	input wire[4:0] s_div_wbk_rd_id, // RD索引
	input wire s_div_wbk_valid,
	output wire s_div_wbk_ready,
	
	// LSU异常
	output wire[31:0] m_lsu_expt_ls_addr, // 访存地址
	output wire m_lsu_expt_err, // 错误类型(1'b0 -> 读存储映射总线错误, 1'b1 -> 写存储映射总线错误)
	output wire m_lsu_expt_valid,
	input wire m_lsu_expt_ready,
	
	// 通用寄存器堆写端口
	output wire reg_file_wen,
	output wire[4:0] reg_file_waddr,
	output wire[31:0] reg_file_din
);
	
	/** 常量 **/
	// 访存应答错误类型
	localparam DBUS_ACCESS_NORMAL = 2'b00; // 正常
	localparam DBUS_ACCESS_LS_UNALIGNED = 2'b01; // 访存地址非对齐
	localparam DBUS_ACCESS_BUS_ERR = 2'b10; // 数据总线访问错误
	localparam DBUS_ACCESS_TIMEOUT = 2'b11; // 响应超时
	// LSU错误类型
	localparam LSU_LOAD_ACCESS_FAULT = 1'b0; // 读存储映射总线错误
	localparam LSU_STORE_ACCESS_FAULT = 1'b1; // 写存储映射总线错误
	
	/** 写回请求仲裁 **/
	// 写回请求
	wire alu_csr_wbk_req; // ALU或CSR原子读写单元写回请求
	wire lsu_wbk_req; // LSU写回请求
	wire mul_wbk_req; // 乘法器写回请求
	wire div_wbk_req; // 除法器写回请求
	// 写回许可
	wire alu_csr_wbk_granted; // ALU或CSR原子读写单元写回许可
	wire lsu_wbk_granted; // LSU写回许可
	wire mul_wbk_granted; // 乘法器写回许可
	wire div_wbk_granted; // 除法器写回许可
	
	// 来自ALU或CSR原子读写单元的写回请求
	assign s_alu_csr_wbk_ready = alu_csr_wbk_granted | (~s_alu_csr_wbk_rd_vld);
	
	// 来自LSU的写回请求
	assign s_lsu_wbk_ready = 
		lsu_wbk_granted | 
		((s_lsu_wbk_err == DBUS_ACCESS_NORMAL) & s_lsu_wbk_ls_sel) | // 对于正常的LSU存储响应, 直接忽略
		(s_lsu_wbk_err == DBUS_ACCESS_LS_UNALIGNED) | // 对于访存地址非对齐的LSU响应, 直接忽略
		(((s_lsu_wbk_err == DBUS_ACCESS_BUS_ERR) | (s_lsu_wbk_err == DBUS_ACCESS_TIMEOUT)) & 
			m_lsu_expt_ready); // 对于数据总线访问错误或响应超时的LSU响应, 需要产生LSU异常
	
	// 来自乘法器的写回请求
	assign s_mul_wbk_ready = mul_wbk_granted;
	
	// 来自除法器的写回请求
	assign s_div_wbk_ready = div_wbk_granted;
	
	assign alu_csr_wbk_req = s_alu_csr_wbk_valid & s_alu_csr_wbk_rd_vld;
	assign lsu_wbk_req = s_lsu_wbk_valid & (s_lsu_wbk_err == DBUS_ACCESS_NORMAL) & (~s_lsu_wbk_ls_sel);
	assign mul_wbk_req = s_mul_wbk_valid;
	assign div_wbk_req = s_div_wbk_valid;
	
	// 注意: 单周期指令写回请求的优先级 < 长指令写回请求的优先级!
	assign alu_csr_wbk_granted = alu_csr_wbk_req & (~(lsu_wbk_req | mul_wbk_req | div_wbk_req));
	
	// Round-Robin仲裁器
	round_robin_arbitrator #(
		.chn_n(3),
		.simulation_delay(simulation_delay)
	)round_robin_arbitrator_u(
		.clk(clk),
		.rst_n(resetn),
		
		.req({lsu_wbk_req, mul_wbk_req, div_wbk_req}),
		
		.grant({lsu_wbk_granted, mul_wbk_granted, div_wbk_granted})
	);
	
	/** LSU异常 **/
	assign m_lsu_expt_ls_addr = s_lsu_wbk_ls_addr;
	assign m_lsu_expt_err = s_lsu_wbk_ls_sel;
	assign m_lsu_expt_valid = s_lsu_wbk_valid & ((s_lsu_wbk_err == DBUS_ACCESS_BUS_ERR) | (s_lsu_wbk_err == DBUS_ACCESS_TIMEOUT));
	
	/** 通用寄存器堆写端口 **/
	assign reg_file_wen = alu_csr_wbk_req | lsu_wbk_req | mul_wbk_req | div_wbk_req;
	assign reg_file_waddr = 
		({5{lsu_wbk_granted}} & s_lsu_wbk_rd_id_for_ld) | 
		({5{mul_wbk_granted}} & s_mul_wbk_rd_id) | 
		({5{div_wbk_granted}} & s_div_wbk_rd_id) | 
		({5{alu_csr_wbk_granted}} & s_alu_csr_wbk_rd_id);
	assign reg_file_din = 
		({32{lsu_wbk_granted}} & s_lsu_wbk_dout) | 
		({32{mul_wbk_granted}} & s_mul_wbk_data) | 
		({32{div_wbk_granted}} & s_div_wbk_data) | 
		({32{alu_csr_wbk_granted}} & s_alu_csr_wbk_data);
	
endmodule
