`timescale 1ns / 1ps
/********************************************************************
本模块: 数据相关性监测器

描述:
跟踪指令的处理过程(指令进入取指队列 -> 指令被译码 -> 指令被派遣 -> 指令退休), 进行数据相关性检查

注意：
无

协议:
无

作者: 陈家耀
日期: 2025/01/15
********************************************************************/


module panda_risc_v_data_dpc_monitor #(
	parameter integer dpc_trace_inst_n = 4, // 执行数据相关性跟踪的指令条数
	parameter integer inst_id_width = 4, // 指令编号的位宽
	parameter en_alu_csr_rw_bypass = "true", // 是否使能ALU/CSR原子读写单元的数据旁路
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// 复位/冲刷请求
	input wire sys_reset_req, // 系统复位请求
	input wire flush_req, // 冲刷请求
	
	// 是否有滞外的指令存储器访问请求
	input wire has_processing_imem_access_req,
	// 指令数据相关性跟踪表满标志
	output wire dpc_trace_tb_full,
	
	// 数据相关性检查
	// 指令存储器访问请求发起阶段
	input wire[4:0] imem_access_rs1_id, // 待检查RAW相关性的RS1索引
	output wire imem_access_rs1_raw_dpc, // RS1有RAW相关性(标志)
	// 译码阶段
	input wire[4:0] dcd_raw_dpc_check_rs1_id, // 待检查RAW相关性的RS1索引
	output wire dcd_rs1_raw_dpc, // RS1有RAW相关性(标志)
	input wire[4:0] dcd_raw_dpc_check_rs2_id, // 待检查RAW相关性的RS2索引
	output wire dcd_rs2_raw_dpc, // RS2有RAW相关性(标志)
	// 派遣阶段
	input wire[4:0] dsptc_waw_dpc_check_rd_id, // 待检查WAW相关性的RD索引
	output wire dsptc_rd_waw_dpc, // RD有WAW相关性(标志)
	
	// 数据相关性跟踪
	// 指令进入取指队列
	input wire[31:0] dpc_trace_enter_ifq_inst, // 取到的指令
	input wire[4:0] dpc_trace_enter_ifq_rd_id, // RD索引
	input wire dpc_trace_enter_ifq_rd_vld, // 是否需要写RD
	input wire dpc_trace_enter_ifq_is_long_inst, // 是否长指令
	input wire[inst_id_width-1:0] dpc_trace_enter_ifq_inst_id, // 指令编号
	input wire dpc_trace_enter_ifq_valid,
	// 指令被译码
	input wire[inst_id_width-1:0] dpc_trace_dcd_inst_id, // 指令编号
	input wire dpc_trace_dcd_valid,
	// 指令被派遣
	input wire[inst_id_width-1:0] dpc_trace_dsptc_inst_id, // 指令编号
	input wire dpc_trace_dsptc_valid,
	// 指令退休
	input wire[inst_id_width-1:0] dpc_trace_retire_inst_id, // 指令编号
	input wire dpc_trace_retire_valid,
	
	// ALU/CSR原子读写单元的数据旁路
	output wire dcd_reg_file_rd_p0_bypass, // 需要旁路到译码器给出的通用寄存器堆读端口#0
	output wire dcd_reg_file_rd_p1_bypass // 需要旁路到译码器给出的通用寄存器堆读端口#1
);
	
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
        for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
			bit_depth = bit_depth >> 1;
    end
    endfunction
	
	/** 常量 **/
	// 指令生命周期标志位索引
	localparam integer INST_NOT_VALID_STAGE_FID = 0; // 阶段: 指令尚未被取出
	localparam integer INST_IFQ_STAGE_FID = 1; // 阶段: 指令在取指队列里
	localparam integer INST_DSPTC_MSG_STAGE_FID = 2; // 阶段: 指令在派遣信息里
	localparam integer INST_EXU_STAGE_FID = 3; // 阶段: 指令执行中
	// 指令数据相关性跟踪信息各项的起始索引
	localparam integer INST_DPC_TRACE_MSG_INST = 0; // 起始索引:取到的指令
	localparam integer INST_DPC_TRACE_MSG_RD_ID = 32; // 起始索引:RD索引
	localparam integer INST_DPC_TRACE_MSG_IS_LONG_INST = 37; // 起始索引:是否长指令
	localparam integer INST_DPC_TRACE_MSG_INST_ID = 38; // 起始索引:指令编号
	
	/** 复位/冲刷请求 **/
	wire on_flush_rst; // 当前冲刷或复位(指示)
	
	assign on_flush_rst = sys_reset_req | flush_req;
	
	/** 数据相关性跟踪 **/
	wire[dpc_trace_inst_n-1:0] inst_dpc_trace_item_empty_vec; // 指令数据相关性跟踪表存储项空标志向量
	wire[dpc_trace_inst_n-1:0] inst_dpc_trace_item_alloc_grant_vec; // 指令数据相关性跟踪表分配存储项许可标志向量
	reg[3:0] inst_life_cycle_vec[0:dpc_trace_inst_n-1]; // 指令生命周期向量(寄存器组)
	reg[38+inst_id_width-1:0] inst_dpc_trace_msg[0:dpc_trace_inst_n-1]; // 指令数据相关性跟踪信息(寄存器组)
	
	assign dpc_trace_tb_full = ~(|inst_dpc_trace_item_empty_vec); // 所有存储项都非空
	
	/*
	指令数据相关性跟踪表
	
	"指令进入取指队列"和"指令被译码"都必须至少经过1个cycle, 而"指令被派遣"和"指令退休"可能在同1个clk发生
	复位/冲刷时复位所有不处于"指令执行中"阶段的指令跟踪, 除非该指令处于"指令在派遣信息里"阶段且被派遣
	*/
	genvar inst_dpc_trace_item_i;
	generate
		for(inst_dpc_trace_item_i = 0;inst_dpc_trace_item_i < dpc_trace_inst_n;inst_dpc_trace_item_i = inst_dpc_trace_item_i + 1)
		begin
			assign inst_dpc_trace_item_empty_vec[inst_dpc_trace_item_i] = 
				inst_life_cycle_vec[inst_dpc_trace_item_i][INST_NOT_VALID_STAGE_FID];
			
			// 优先分配编号较小的存储项
			if(inst_dpc_trace_item_i >= 1)
				assign inst_dpc_trace_item_alloc_grant_vec[inst_dpc_trace_item_i] = 
					inst_dpc_trace_item_empty_vec[inst_dpc_trace_item_i] & // 当前存储项空
					(~(|inst_dpc_trace_item_empty_vec[inst_dpc_trace_item_i-1:0])); // 编号更小的存储项都非空
			else
				assign inst_dpc_trace_item_alloc_grant_vec[inst_dpc_trace_item_i] = 
					inst_dpc_trace_item_empty_vec[inst_dpc_trace_item_i];
			
			always @(posedge clk or negedge resetn)
			begin
				if(~resetn)
					inst_life_cycle_vec[inst_dpc_trace_item_i] <= (1 << INST_NOT_VALID_STAGE_FID);
				else if(
				// 当前冲刷或复位
				(on_flush_rst & (~inst_life_cycle_vec[inst_dpc_trace_item_i][INST_EXU_STAGE_FID])) | 
				// 阶段: 指令尚未被取出
				(inst_life_cycle_vec[inst_dpc_trace_item_i][INST_NOT_VALID_STAGE_FID] & dpc_trace_enter_ifq_valid & 
					inst_dpc_trace_item_alloc_grant_vec[inst_dpc_trace_item_i]) | 
				// 阶段: 指令在取指队列里
				(inst_life_cycle_vec[inst_dpc_trace_item_i][INST_IFQ_STAGE_FID] & dpc_trace_dcd_valid & 
					(inst_dpc_trace_msg[inst_dpc_trace_item_i][INST_DPC_TRACE_MSG_INST_ID+inst_id_width-1:INST_DPC_TRACE_MSG_INST_ID] == 
						dpc_trace_dcd_inst_id)) | 
				// 阶段: 指令在派遣信息里
				(inst_life_cycle_vec[inst_dpc_trace_item_i][INST_DSPTC_MSG_STAGE_FID] & dpc_trace_dsptc_valid & 
					(inst_dpc_trace_msg[inst_dpc_trace_item_i][INST_DPC_TRACE_MSG_INST_ID+inst_id_width-1:INST_DPC_TRACE_MSG_INST_ID] == 
						dpc_trace_dsptc_inst_id)) | 
				// 阶段: 指令执行中
				(inst_life_cycle_vec[inst_dpc_trace_item_i][INST_EXU_STAGE_FID] & dpc_trace_retire_valid & 
					(inst_dpc_trace_msg[inst_dpc_trace_item_i][INST_DPC_TRACE_MSG_INST_ID+inst_id_width-1:INST_DPC_TRACE_MSG_INST_ID] == 
						dpc_trace_retire_inst_id))
				)
					inst_life_cycle_vec[inst_dpc_trace_item_i] <= # simulation_delay 
						((on_flush_rst & (~inst_life_cycle_vec[inst_dpc_trace_item_i][INST_EXU_STAGE_FID])) & (
						~(
							inst_life_cycle_vec[inst_dpc_trace_item_i][INST_DSPTC_MSG_STAGE_FID] & dpc_trace_dsptc_valid & 
							(inst_dpc_trace_msg[inst_dpc_trace_item_i]
								[INST_DPC_TRACE_MSG_INST_ID+inst_id_width-1:INST_DPC_TRACE_MSG_INST_ID] == dpc_trace_dsptc_inst_id))
						)) ? (1 << INST_NOT_VALID_STAGE_FID):(
							// 阶段: 指令尚未被取出
							({4{inst_life_cycle_vec[inst_dpc_trace_item_i][INST_NOT_VALID_STAGE_FID]}} & (1 << INST_IFQ_STAGE_FID)) | 
							// 阶段: 指令在取指队列里
							({4{inst_life_cycle_vec[inst_dpc_trace_item_i][INST_IFQ_STAGE_FID]}} & (1 << INST_DSPTC_MSG_STAGE_FID)) | 
							// 阶段: 指令在派遣信息里
							// "指令被派遣"发生, 而"指令退休"未发生, 跳到"指令执行中"阶段
							({4{inst_life_cycle_vec[inst_dpc_trace_item_i][INST_DSPTC_MSG_STAGE_FID] & (
									dpc_trace_dsptc_valid & 
									(inst_dpc_trace_msg[inst_dpc_trace_item_i]
										[INST_DPC_TRACE_MSG_INST_ID+inst_id_width-1:INST_DPC_TRACE_MSG_INST_ID] == 
											dpc_trace_dsptc_inst_id)
								) & (~(
									dpc_trace_retire_valid & 
									(inst_dpc_trace_msg[inst_dpc_trace_item_i]
										[INST_DPC_TRACE_MSG_INST_ID+inst_id_width-1:INST_DPC_TRACE_MSG_INST_ID] == 
											dpc_trace_retire_inst_id)
								))}} & (1 << INST_EXU_STAGE_FID)) | 
							// "指令被派遣"和"指令退休"同时发生, 跳到"指令尚未被取出"阶段
							({4{inst_life_cycle_vec[inst_dpc_trace_item_i][INST_DSPTC_MSG_STAGE_FID] & (
									dpc_trace_dsptc_valid & 
									(inst_dpc_trace_msg[inst_dpc_trace_item_i]
										[INST_DPC_TRACE_MSG_INST_ID+inst_id_width-1:INST_DPC_TRACE_MSG_INST_ID] == 
											dpc_trace_dsptc_inst_id)
								) & (
									dpc_trace_retire_valid & 
									(inst_dpc_trace_msg[inst_dpc_trace_item_i]
										[INST_DPC_TRACE_MSG_INST_ID+inst_id_width-1:INST_DPC_TRACE_MSG_INST_ID] == 
											dpc_trace_retire_inst_id)
								)}} & (1 << INST_NOT_VALID_STAGE_FID)) | 
							// 阶段: 指令执行中
							({4{inst_life_cycle_vec[inst_dpc_trace_item_i][INST_EXU_STAGE_FID]}} & (1 << INST_NOT_VALID_STAGE_FID))
						);
			end
			
			always @(posedge clk)
			begin
				if(inst_life_cycle_vec[inst_dpc_trace_item_i][INST_NOT_VALID_STAGE_FID] & dpc_trace_enter_ifq_valid & 
					inst_dpc_trace_item_alloc_grant_vec[inst_dpc_trace_item_i])
					inst_dpc_trace_msg[inst_dpc_trace_item_i] <= # simulation_delay {
						dpc_trace_enter_ifq_inst_id, // 指令编号(inst_id_width bit)
						dpc_trace_enter_ifq_is_long_inst, // 是否长指令(1bit)
						// dpc_trace_enter_ifq_rd_vld ? dpc_trace_enter_ifq_rd_id:5'd0
						{5{dpc_trace_enter_ifq_rd_vld}} & dpc_trace_enter_ifq_rd_id, // RD索引(5bit)
						dpc_trace_enter_ifq_inst // 取到的指令(32bit)
					};
			end
		end
	endgenerate
	
	/** 数据相关性检查 **/
	wire[dpc_trace_inst_n-1:0] imem_access_rs1_raw_dpc_check_res_vec; // 指令存储器访问请求发起阶段RS1的RAW相关性检查结果向量
	wire[dpc_trace_inst_n-1:0] dcd_rs1_raw_dpc_check_res_vec; // 译码阶段RS1的RAW相关性检查结果向量
	wire[dpc_trace_inst_n-1:0] dcd_rs2_raw_dpc_check_res_vec; // 译码阶段RS2的RAW相关性检查结果向量
	wire[dpc_trace_inst_n-1:0] dsptc_waw_dpc_check_res_vec; // 派遣阶段WAW相关性检查结果向量
	
	assign imem_access_rs1_raw_dpc = (|imem_access_rs1_raw_dpc_check_res_vec) | has_processing_imem_access_req;
	assign dcd_rs1_raw_dpc = |dcd_rs1_raw_dpc_check_res_vec;
	assign dcd_rs2_raw_dpc = |dcd_rs2_raw_dpc_check_res_vec;
	assign dsptc_rd_waw_dpc = |dsptc_waw_dpc_check_res_vec;
	
	genvar dpc_check_i;
	generate
		for(dpc_check_i = 0;dpc_check_i < dpc_trace_inst_n;dpc_check_i = dpc_check_i + 1)
		begin
			assign imem_access_rs1_raw_dpc_check_res_vec[dpc_check_i] = 
				(inst_dpc_trace_msg[dpc_check_i][INST_DPC_TRACE_MSG_RD_ID+4:INST_DPC_TRACE_MSG_RD_ID] != 5'd0) & 
				(inst_dpc_trace_msg[dpc_check_i][INST_DPC_TRACE_MSG_RD_ID+4:INST_DPC_TRACE_MSG_RD_ID] == imem_access_rs1_id) & 
				// JALR指令读基址给出的通用寄存器堆读端口#0不支持数据旁路
				(~inst_life_cycle_vec[dpc_check_i][INST_NOT_VALID_STAGE_FID]);
			
			assign dcd_rs1_raw_dpc_check_res_vec[dpc_check_i] = 
				(inst_dpc_trace_msg[dpc_check_i][INST_DPC_TRACE_MSG_RD_ID+4:INST_DPC_TRACE_MSG_RD_ID] != 5'd0) & 
				(inst_dpc_trace_msg[dpc_check_i][INST_DPC_TRACE_MSG_RD_ID+4:INST_DPC_TRACE_MSG_RD_ID] == dcd_raw_dpc_check_rs1_id) & 
				(inst_life_cycle_vec[dpc_check_i][INST_DSPTC_MSG_STAGE_FID] | inst_life_cycle_vec[dpc_check_i][INST_EXU_STAGE_FID]) & 
				// 如果支持数据旁路, 那么单周期指令的结果可以被旁路到译码器给出的通用寄存器读端口#0
				((en_alu_csr_rw_bypass == "false") | inst_dpc_trace_msg[dpc_check_i][INST_DPC_TRACE_MSG_IS_LONG_INST]);
			
			assign dcd_rs2_raw_dpc_check_res_vec[dpc_check_i] = 
				(inst_dpc_trace_msg[dpc_check_i][INST_DPC_TRACE_MSG_RD_ID+4:INST_DPC_TRACE_MSG_RD_ID] != 5'd0) & 
				(inst_dpc_trace_msg[dpc_check_i][INST_DPC_TRACE_MSG_RD_ID+4:INST_DPC_TRACE_MSG_RD_ID] == dcd_raw_dpc_check_rs2_id) & 
				(inst_life_cycle_vec[dpc_check_i][INST_DSPTC_MSG_STAGE_FID] | inst_life_cycle_vec[dpc_check_i][INST_EXU_STAGE_FID]) & 
				// 如果支持数据旁路, 那么单周期指令的结果可以被旁路到译码器给出的通用寄存器读端口#1
				((en_alu_csr_rw_bypass == "false") | inst_dpc_trace_msg[dpc_check_i][INST_DPC_TRACE_MSG_IS_LONG_INST]);
			
			assign dsptc_waw_dpc_check_res_vec[dpc_check_i] = 
				(inst_dpc_trace_msg[dpc_check_i][INST_DPC_TRACE_MSG_RD_ID+4:INST_DPC_TRACE_MSG_RD_ID] != 5'd0) & 
				(inst_dpc_trace_msg[dpc_check_i][INST_DPC_TRACE_MSG_RD_ID+4:INST_DPC_TRACE_MSG_RD_ID] == dsptc_waw_dpc_check_rd_id) & 
				// 仅检查与执行中长指令的WAW相关性
				inst_life_cycle_vec[dpc_check_i][INST_EXU_STAGE_FID] & 
				inst_dpc_trace_msg[dpc_check_i][INST_DPC_TRACE_MSG_IS_LONG_INST];
		end
	endgenerate
	
	/** 数据旁路 **/
	wire[dpc_trace_inst_n-1:0] dcd_reg_file_rd_p0_bypass_vec; // 译码器给出的通用寄存器堆读端口#0的数据旁路标志向量
	wire[dpc_trace_inst_n-1:0] dcd_reg_file_rd_p1_bypass_vec; // 译码器给出的通用寄存器堆读端口#1的数据旁路标志向量
	
	assign dcd_reg_file_rd_p0_bypass = |dcd_reg_file_rd_p0_bypass_vec;
	assign dcd_reg_file_rd_p1_bypass = |dcd_reg_file_rd_p1_bypass_vec;
	
	genvar alu_csr_rw_bypass_i;
	generate
		for(alu_csr_rw_bypass_i = 0;alu_csr_rw_bypass_i < dpc_trace_inst_n;alu_csr_rw_bypass_i = alu_csr_rw_bypass_i + 1)
		begin
			assign dcd_reg_file_rd_p0_bypass_vec[alu_csr_rw_bypass_i] = 
				(inst_dpc_trace_msg[alu_csr_rw_bypass_i][INST_DPC_TRACE_MSG_RD_ID+4:INST_DPC_TRACE_MSG_RD_ID] != 5'd0) & 
				(inst_dpc_trace_msg[alu_csr_rw_bypass_i][INST_DPC_TRACE_MSG_RD_ID+4:INST_DPC_TRACE_MSG_RD_ID] == 
					dcd_raw_dpc_check_rs1_id) & 
				(inst_life_cycle_vec[alu_csr_rw_bypass_i][INST_DSPTC_MSG_STAGE_FID] | 
					inst_life_cycle_vec[alu_csr_rw_bypass_i][INST_EXU_STAGE_FID]) & 
				// 仅旁路单周期指令的结果
				(~inst_dpc_trace_msg[alu_csr_rw_bypass_i][INST_DPC_TRACE_MSG_IS_LONG_INST]);
			
			assign dcd_reg_file_rd_p1_bypass_vec[alu_csr_rw_bypass_i] = 
				(inst_dpc_trace_msg[alu_csr_rw_bypass_i][INST_DPC_TRACE_MSG_RD_ID+4:INST_DPC_TRACE_MSG_RD_ID] != 5'd0) & 
				(inst_dpc_trace_msg[alu_csr_rw_bypass_i][INST_DPC_TRACE_MSG_RD_ID+4:INST_DPC_TRACE_MSG_RD_ID] == 
					dcd_raw_dpc_check_rs2_id) & 
				(inst_life_cycle_vec[alu_csr_rw_bypass_i][INST_DSPTC_MSG_STAGE_FID] | 
					inst_life_cycle_vec[alu_csr_rw_bypass_i][INST_EXU_STAGE_FID]) & 
				// 仅旁路单周期指令的结果
				(~inst_dpc_trace_msg[alu_csr_rw_bypass_i][INST_DPC_TRACE_MSG_IS_LONG_INST]);
		end
	endgenerate
	
	/** 仿真信号 **/
	reg[31:0] inst_not_valid_n; // 处于"指令尚未被取出"阶段的条目数
	reg[31:0] inst_at_ifq_n; // 处于"指令在取指队列里"阶段的条目数
	reg[31:0] inst_at_dsptc_msg_n; // 处于"指令在派遣信息里"阶段的条目数
	reg[31:0] inst_at_exu_n; // 处于"指令执行中"阶段的条目数
	
	integer i1;
	always @(*)
	begin
		inst_not_valid_n = 0;
		
		for(i1 = 0;i1 < dpc_trace_inst_n;i1 = i1 + 1)
			inst_not_valid_n = inst_not_valid_n + inst_life_cycle_vec[i1][INST_NOT_VALID_STAGE_FID];
	end
	
	integer i2;
	always @(*)
	begin
		inst_at_ifq_n = 0;
		
		for(i2 = 0;i2 < dpc_trace_inst_n;i2 = i2 + 1)
			inst_at_ifq_n = inst_at_ifq_n + inst_life_cycle_vec[i2][INST_IFQ_STAGE_FID];
	end
	
	integer i3;
	always @(*)
	begin
		inst_at_dsptc_msg_n = 0;
		
		for(i3 = 0;i3 < dpc_trace_inst_n;i3 = i3 + 1)
			inst_at_dsptc_msg_n = inst_at_dsptc_msg_n + inst_life_cycle_vec[i3][INST_DSPTC_MSG_STAGE_FID];
	end
	
	integer i4;
	always @(*)
	begin
		inst_at_exu_n = 0;
		
		for(i4 = 0;i4 < dpc_trace_inst_n;i4 = i4 + 1)
			inst_at_exu_n = inst_at_exu_n + inst_life_cycle_vec[i4][INST_EXU_STAGE_FID];
	end
	
endmodule
