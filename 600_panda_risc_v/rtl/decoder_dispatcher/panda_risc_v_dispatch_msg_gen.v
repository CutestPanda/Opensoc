`timescale 1ns / 1ps
/********************************************************************
本模块: 译码阶段的派遣信息生成

描述:
IFU取指结果 -> 向通用寄存器读控制提交请求 -> 译码单元 -> 保存派遣信息

派遣信息寄存器属于CPU Core在译码/派遣阶段的流水线寄存器

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/12/01
********************************************************************/


module panda_risc_v_dispatch_msg_gen #(
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// 复位/冲刷请求
	input wire sys_reset_req, // 系统复位请求
	input wire flush_req, // 冲刷请求
	
	// IFU取指结果
	input wire[127:0] s_if_res_data, // {指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)}
	input wire[3:0] s_if_res_msg, // {是否预测跳转(1bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)}
	input wire s_if_res_valid,
	output wire s_if_res_ready,
	
	// 读通用寄存器堆请求
	output wire[4:0] m_reg_file_rd_req_rs1_id, // RS1索引
	output wire[4:0] m_reg_file_rd_req_rs2_id, // RS2索引
	output wire m_reg_file_rd_req_rs1_vld, // 是否需要读RS1(标志)
	output wire m_reg_file_rd_req_rs2_vld, // 是否需要读RS2(标志)
	output wire m_reg_file_rd_req_valid,
	input wire m_reg_file_rd_req_ready,
	
	// 源寄存器读结果
	input wire[31:0] s_reg_file_rd_res_rs1_v, // RS1读结果
	input wire[31:0] s_reg_file_rd_res_rs2_v, // RS2读结果
	input wire s_reg_file_rd_res_valid,
	output wire s_reg_file_rd_res_ready,
	
	// 派遣请求
	/*
	指令类型           复用的派遣信息的内容
	--------------------------------------------
	    L/S         {打包的LSU操作信息[2:0], 
	                     打包的ALU操作信息[67:0]}
	  CSR读写       {打包的CSR原子读写操作信息[45:0]}
	   乘除         {打包的乘除法操作信息[66:0]}
	   其他         {是否预测跳转, 
	                     打包的ALU操作信息[67:0]}
	*/
	output wire[70:0] m_dispatch_req_msg_reused, // 复用的派遣信息
	output wire[6:0] m_dispatch_req_inst_type_packeted, // 打包的指令类型标志
	output wire[31:0] m_dispatch_req_pc_of_inst, // 指令对应的PC
	output wire[31:0] m_dispatch_req_pc_jump, // 跳转后的PC
	output wire[4:0] m_dispatch_req_rd_id, // RD索引
	output wire m_dispatch_req_rd_vld, // 是否需要写RD
	output wire m_dispatch_req_valid,
	input wire m_dispatch_req_ready
);
	
	/** 常量 **/
	// 打包的预译码信息各项的起始索引
	localparam integer PRE_DCD_MSG_IS_REM_INST_SID = 0;
	localparam integer PRE_DCD_MSG_IS_DIV_INST_SID = 1;
	localparam integer PRE_DCD_MSG_IS_MUL_INST_SID = 2;
	localparam integer PRE_DCD_MSG_IS_STORE_INST_SID = 3;
	localparam integer PRE_DCD_MSG_IS_LOAD_INST_SID = 4;
	localparam integer PRE_DCD_MSG_IS_CSR_RW_INST_SID = 5;
	localparam integer PRE_DCD_MSG_IS_JALR_INST_SID = 6;
	localparam integer PRE_DCD_MSG_IS_JAL_INST_SID = 7;
	localparam integer PRE_DCD_MSG_IS_B_INST_SID = 8;
	localparam integer PRE_DCD_MSG_JUMP_OFS_IMM_SID = 9;
	localparam integer PRE_DCD_MSG_RD_VLD_SID = 30;
	localparam integer PRE_DCD_MSG_RS2_VLD_SID = 31;
	localparam integer PRE_DCD_MSG_RS1_VLD_SID = 32;
	localparam integer PRE_DCD_MSG_CSR_ADDR_SID = 33;
	// 打包的指令类型标志各项的起始索引
	localparam integer INST_TYPE_FLAG_IS_B_INST_SID = 6;
	localparam integer INST_TYPE_FLAG_IS_CSR_RW_INST_SID = 5;
	localparam integer INST_TYPE_FLAG_IS_LOAD_INST_SID = 4;
	localparam integer INST_TYPE_FLAG_IS_STORE_INST_SID = 3;
	localparam integer INST_TYPE_FLAG_IS_MUL_INST_SID = 2;
	localparam integer INST_TYPE_FLAG_IS_DIV_INST_SID = 1;
	localparam integer INST_TYPE_FLAG_IS_REM_INST_SID = 0;
	
	/** 复位/冲刷请求 **/
	wire on_flush_rst; // 当前冲刷或复位(指示)
	
	assign on_flush_rst = sys_reset_req | flush_req;
	
	/**
	译码/派遣流程控制
	
	IFU取指结果有效 -> 读通用寄存器堆 -> 返回源寄存器读结果, 进行指令译码 -> 保存派遣信息
	**/
	wire dispatch_msg_regs_empty; // 派遣信息寄存器空标志
	reg to_suppress_reg_file_rd_req; // 镇压读通用寄存器堆请求(标志)
	
	// 握手条件: s_if_res_valid & (~to_suppress_reg_file_rd_req) & m_reg_file_rd_req_ready & (~on_flush_rst)
	assign m_reg_file_rd_req_valid = s_if_res_valid & (~to_suppress_reg_file_rd_req) & (~on_flush_rst);
	
	// 当取走源寄存器读结果时, 当前指令译码完成
	// 握手条件: s_reg_file_rd_res_valid & s_if_res_valid & (dispatch_msg_regs_empty | m_dispatch_req_ready) & (~on_flush_rst)
	assign s_if_res_ready = s_reg_file_rd_res_valid & (dispatch_msg_regs_empty | m_dispatch_req_ready) & (~on_flush_rst);
	assign s_reg_file_rd_res_ready = s_if_res_valid & (dispatch_msg_regs_empty | m_dispatch_req_ready) & (~on_flush_rst);
	
	// 镇压读通用寄存器堆请求(标志)
	// 断言: 该标志恒为1'b0!
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			to_suppress_reg_file_rd_req <= 1'b0;
		else
			/*
			(~on_flush_rst) & // 处于冲刷或复位状态时清零标志
			(to_suppress_reg_file_rd_req ? 
				// 等待源寄存器读结果被取走
				(~(s_reg_file_rd_res_valid & s_reg_file_rd_res_ready)):
				// 读通用寄存器堆请求握手但不能立即取走源寄存器读结果
				(s_if_res_valid & m_reg_file_rd_req_ready & 
					(~(s_reg_file_rd_res_valid & s_reg_file_rd_res_ready))))
			*/
			to_suppress_reg_file_rd_req <= # simulation_delay 
				(~on_flush_rst) & 
				(to_suppress_reg_file_rd_req | (s_if_res_valid & m_reg_file_rd_req_ready)) & 
				(~(s_reg_file_rd_res_valid & s_reg_file_rd_res_ready));
	end
	
	/** IFU取指结果 **/
	wire[31:0] if_res_pc_of_inst; // 指令对应的PC
	wire[63:0] if_res_pre_decoding_msg_packeted; // 打包的预译码信息
	wire[31:0] if_res_inst; // 取到的指令
	wire if_res_prdt_jump; // 是否预测跳转
	
	assign {if_res_pc_of_inst, if_res_pre_decoding_msg_packeted, if_res_inst} = s_if_res_data;
	assign if_res_prdt_jump = s_if_res_msg[3];
	
	/** 读通用寄存器 **/
	assign m_reg_file_rd_req_rs1_id = if_res_inst[19:15];
	assign m_reg_file_rd_req_rs2_id = if_res_inst[24:20];
	assign m_reg_file_rd_req_rs1_vld = if_res_pre_decoding_msg_packeted[PRE_DCD_MSG_RS1_VLD_SID];
	assign m_reg_file_rd_req_rs2_vld = if_res_pre_decoding_msg_packeted[PRE_DCD_MSG_RS2_VLD_SID];
	
	/** 译码单元 **/
	// 待译码的指令及其附加信息
	wire[31:0] inst_to_dcd; // 指令
	wire[63:0] pre_decoding_msg_packeted_to_dcd; // 打包的预译码信息
	wire[31:0] pc_of_inst_to_dcd; // 指令对应的PC
	// 源寄存器读结果
	wire[31:0] rs1_v;
	wire[31:0] rs2_v;
	// 跳转后的PC
	wire[31:0] pc_jump;
	// 读写通用寄存器堆标志
	wire rs1_vld; // 是否需要读RS1
	wire rs2_vld; // 是否需要读RS2
	wire rd_vld; // 是否需要写RD
	// 打包的译码结果
	wire[6:0] dcd_res_inst_type_packeted; // 打包的指令类型标志
	wire[67:0] dcd_res_alu_op_msg_packeted; // 打包的ALU操作信息
	wire[2:0] dcd_res_lsu_op_msg_packeted; // 打包的LSU操作信息
	wire[45:0] dcd_res_csr_rw_op_msg_packeted; // 打包的CSR原子读写操作信息
	wire[66:0] dcd_res_mul_div_op_msg_packeted; // 打包的乘除法操作信息
	
	assign inst_to_dcd = if_res_inst;
	assign pre_decoding_msg_packeted_to_dcd = if_res_pre_decoding_msg_packeted;
	assign pc_of_inst_to_dcd = if_res_pc_of_inst;
	
	assign rs1_v = s_reg_file_rd_res_rs1_v;
	assign rs2_v = s_reg_file_rd_res_rs2_v;
	
	panda_risc_v_decoder panda_risc_v_decoder_u(
		.inst(inst_to_dcd),
		.pre_decoding_msg_packeted(pre_decoding_msg_packeted_to_dcd),
		.pc_of_inst(pc_of_inst_to_dcd),
		
		.rs1_v(rs1_v),
		.rs2_v(rs2_v),
		
		.is_b_inst(),
		.is_csr_rw_inst(),
		.is_load_inst(),
		.is_store_inst(),
		.is_mul_inst(),
		.is_div_inst(),
		.is_rem_inst(),
		
		.pc_jump(pc_jump),
		
		.rs1_vld(rs1_vld),
		.rs2_vld(rs2_vld),
		.rd_vld(rd_vld),
		
		.ls_type(),
		
		.mul_div_op_a(),
		.mul_div_op_b(),
		.mul_res_sel(),
		
		.csr_addr(),
		.csr_upd_type(),
		.csr_upd_mask_v(),
		
		.alu_op_mode(),
		.alu_op1(),
		.alu_op2(),
		
		.dcd_res_inst_type_packeted(dcd_res_inst_type_packeted),
		.dcd_res_alu_op_msg_packeted(dcd_res_alu_op_msg_packeted),
		.dcd_res_lsu_op_msg_packeted(dcd_res_lsu_op_msg_packeted),
		.dcd_res_csr_rw_op_msg_packeted(dcd_res_csr_rw_op_msg_packeted),
		.dcd_res_mul_div_op_msg_packeted(dcd_res_mul_div_op_msg_packeted)
	);
	
	/** 派遣信息寄存器 **/
	/*
	指令类型           复用的派遣信息的内容
	--------------------------------------------
	    L/S         {打包的LSU操作信息[2:0], 
	                     打包的ALU操作信息[67:0]}
	  CSR读写       {打包的CSR原子读写操作信息[45:0]}
	   乘除         {打包的乘除法操作信息[66:0]}
	   其他         {是否预测跳转, 
	                     打包的ALU操作信息[67:0]}
	*/
	reg[70:0] dispatch_msg_reused; // 复用的派遣信息
	reg[6:0] dispatch_inst_type_packeted; // 打包的指令类型标志
	reg[31:0] dispatch_pc_of_inst; // 指令对应的PC
	reg[31:0] dispatch_pc_jump; // 跳转后的PC
	reg[4:0] dispatch_rd_id; // RD索引
	reg dispatch_rd_vld; // 是否需要写RD
	reg dispatch_msg_valid; // 派遣信息有效标志
	
	assign m_dispatch_req_msg_reused = dispatch_msg_reused;
	assign m_dispatch_req_inst_type_packeted = dispatch_inst_type_packeted;
	assign m_dispatch_req_pc_of_inst = dispatch_pc_of_inst;
	assign m_dispatch_req_pc_jump = dispatch_pc_jump;
	assign m_dispatch_req_rd_id = dispatch_rd_id;
	assign m_dispatch_req_rd_vld = dispatch_rd_vld;
	assign m_dispatch_req_valid = dispatch_msg_valid & (~on_flush_rst);
	
	assign dispatch_msg_regs_empty = ~dispatch_msg_valid;
	
	// 复用的派遣信息
	always @(posedge clk)
	begin
		if(s_reg_file_rd_res_valid & s_reg_file_rd_res_ready) // 取走源寄存器读结果时保存派遣信息
			dispatch_msg_reused <= # simulation_delay 
				({71{dcd_res_inst_type_packeted[INST_TYPE_FLAG_IS_LOAD_INST_SID] | 
					dcd_res_inst_type_packeted[INST_TYPE_FLAG_IS_STORE_INST_SID]}} & 
					{dcd_res_lsu_op_msg_packeted, dcd_res_alu_op_msg_packeted}) | 
				({71{dcd_res_inst_type_packeted[INST_TYPE_FLAG_IS_CSR_RW_INST_SID]}} & 
					{25'dx, dcd_res_csr_rw_op_msg_packeted}) | 
				({71{dcd_res_inst_type_packeted[INST_TYPE_FLAG_IS_MUL_INST_SID] | 
					dcd_res_inst_type_packeted[INST_TYPE_FLAG_IS_DIV_INST_SID] | 
					dcd_res_inst_type_packeted[INST_TYPE_FLAG_IS_REM_INST_SID]}} & 
					{4'dx, dcd_res_mul_div_op_msg_packeted}) | 
				({71{(~dcd_res_inst_type_packeted[INST_TYPE_FLAG_IS_LOAD_INST_SID]) & 
					(~dcd_res_inst_type_packeted[INST_TYPE_FLAG_IS_STORE_INST_SID]) & 
					(~dcd_res_inst_type_packeted[INST_TYPE_FLAG_IS_CSR_RW_INST_SID]) & 
					(~dcd_res_inst_type_packeted[INST_TYPE_FLAG_IS_MUL_INST_SID]) & 
					(~dcd_res_inst_type_packeted[INST_TYPE_FLAG_IS_DIV_INST_SID]) & 
					(~dcd_res_inst_type_packeted[INST_TYPE_FLAG_IS_REM_INST_SID])}} & 
					{2'dx, if_res_prdt_jump, dcd_res_alu_op_msg_packeted});
	end
	// 打包的指令类型标志
	always @(posedge clk)
	begin
		if(s_reg_file_rd_res_valid & s_reg_file_rd_res_ready) // 取走源寄存器读结果时保存派遣信息
			dispatch_inst_type_packeted <= # simulation_delay dcd_res_inst_type_packeted;
	end
	// 指令对应的PC
	always @(posedge clk)
	begin
		if(s_reg_file_rd_res_valid & s_reg_file_rd_res_ready) // 取走源寄存器读结果时保存派遣信息
			dispatch_pc_of_inst <= # simulation_delay if_res_pc_of_inst;
	end
	// 跳转后的PC
	always @(posedge clk)
	begin
		if(s_reg_file_rd_res_valid & s_reg_file_rd_res_ready) // 取走源寄存器读结果时保存派遣信息
			dispatch_pc_jump <= # simulation_delay pc_jump;
	end
	// RD索引
	always @(posedge clk)
	begin
		if(s_reg_file_rd_res_valid & s_reg_file_rd_res_ready) // 取走源寄存器读结果时保存派遣信息
			dispatch_rd_id <= # simulation_delay if_res_inst[11:7];
	end
	// 是否需要写RD
	always @(posedge clk)
	begin
		if(s_reg_file_rd_res_valid & s_reg_file_rd_res_ready) // 取走源寄存器读结果时保存派遣信息
			dispatch_rd_vld <= # simulation_delay if_res_pre_decoding_msg_packeted[PRE_DCD_MSG_RD_VLD_SID];
	end
	
	// 派遣信息有效标志
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			dispatch_msg_valid <= 1'b0;
		else if(s_reg_file_rd_res_ready | on_flush_rst) // 取走源寄存器读结果时保存派遣信息, 冲刷/复位时清零派遣信息
			dispatch_msg_valid <= # simulation_delay s_reg_file_rd_res_valid & (~on_flush_rst);
	end
	
endmodule
