`timescale 1ns / 1ps
/********************************************************************
本模块: 指令存储器访问控制

描述:
将指令总线控制单元返回的取指结果存入深度为3的取指结果缓存区
发起指令存储器访问请求并更新PC

延长复位/冲刷请求, 生成正在复位/冲刷标志

复位/冲刷时清空取指结果缓存区, 取指结果输出无效

IMEM访问请求的生命周期:
	发起IMEM访问请求 -> 指令总线控制单元返回取指结果 -> 指令被后级取走

注意：
要求指令总线控制单元的响应时延>=1clk

协议:
REQ/ACK

作者: 陈家耀
日期: 2025/01/31
********************************************************************/


module panda_risc_v_imem_access_ctrler #(
	parameter integer inst_id_width = 4, // 指令编号的位宽
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// 复位请求
	input wire rst_req,
	// 冲刷请求
	input wire flush_req,
	input wire[31:0] flush_addr,
	// 复位应答
	output wire rst_ack,
	// 冲刷应答
	output wire flush_ack,
	
	// PC生成和分支预测
	output wire to_rst, // 当前正在复位
	output wire to_flush, // 当前正在冲刷
	output wire[31:0] flush_addr_hold, // 保持的冲刷地址
	output wire[31:0] now_pc, // 当前的PC
	input wire[31:0] new_pc, // 新的PC
	input wire to_jump, // 是否预测跳转
	output wire[31:0] rs1_v, // RS1读结果
	
	// 预译码输入
	output wire[31:0] now_inst, // 当前的指令
	// 预译码结果
	input wire is_jalr_inst, // 是否JALR指令
	input wire illegal_inst, // 非法指令(标志)
	input wire[63:0] pre_decoding_msg_packeted, // 打包的预译码信息
	
	// 读JALR指令基址
	output wire vld_inst_gotten, // 获取到有效的指令(指示)
	input wire jalr_baseaddr_vld, // JALR指令基址读完成(指示)
	input wire[31:0] jalr_baseaddr_v, // 基址读结果
	
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
	
	// 取指结果
	output wire[127:0] if_res_data, // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	output wire[3:0] if_res_msg, // 取指附加信息({是否预测跳转(1bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	output wire[inst_id_width-1:0] m_if_res_id, // 指令编号
	output wire if_res_valid,
	input wire if_res_ready,
	
	// 数据相关性跟踪
	// 是否有滞外的指令存储器访问请求
	output wire has_processing_imem_access_req,
	// 指令数据相关性跟踪表满标志
	input wire dpc_trace_tb_full,
	// 指令进入取指队列
	output wire[31:0] dpc_trace_enter_ifq_inst, // 取到的指令
	output wire[4:0] dpc_trace_enter_ifq_rd_id, // RD索引
	output wire dpc_trace_enter_ifq_rd_vld, // 是否需要写RD
	output wire dpc_trace_enter_ifq_is_long_inst, // 是否长指令
	output wire[inst_id_width-1:0] dpc_trace_enter_ifq_inst_id, // 指令编号
	output wire dpc_trace_enter_ifq_valid
);
	
	/** 常量 **/
	// 取指结果缓存区各项的起始索引
	localparam integer IF_RES_BUF_DATA_SID = 0; // 起始索引:取指数据
	localparam integer IF_RES_BUF_MSG_SID = 96; // 起始索引:取指附加信息
	localparam integer IF_RES_BUF_ID_SID = 100; // 起始索引:指令编号
	// 指令存储器访问应答错误类型
	localparam IMEM_ACCESS_NORMAL = 2'b00; // 正常
	localparam IMEM_ACCESS_PC_UNALIGNED = 2'b01; // 指令地址非对齐
	localparam IMEM_ACCESS_BUS_ERR = 2'b10; // 指令总线访问错误
	localparam IMEM_ACCESS_TIMEOUT = 2'b11; // 响应超时
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
	localparam integer PRE_DCD_MSG_IS_ECALL_INST_SID = 9;
	localparam integer PRE_DCD_MSG_IS_MRET_INST_SID = 10;
	localparam integer PRE_DCD_MSG_IS_FENCE_INST_SID = 11;
	localparam integer PRE_DCD_MSG_IS_FENCE_I_INST_SID = 12;
	localparam integer PRE_DCD_MSG_JUMP_OFS_IMM_SID = 13;
	localparam integer PRE_DCD_MSG_RD_VLD_SID = 34;
	localparam integer PRE_DCD_MSG_RS2_VLD_SID = 35;
	localparam integer PRE_DCD_MSG_RS1_VLD_SID = 36;
	localparam integer PRE_DCD_MSG_CSR_ADDR_SID = 37;
	
	/**
	取指结果缓存区
	
	从指令总线上取得的指令需要先缓存到深度为3的寄存器fifo, 
	这里未实现fifo空时的取指结果立即旁路, 因此会造成额外的时延, 但可以切分时序路径
	**/
	reg[3:0] if_res_buf_store_n; // 取指结果缓存区存储个数(4'b0001 -> 0, 4'b0010 -> 1, 4'b0100 -> 2, 4'b1000 -> 3)
	reg[1:0] if_res_buf_wptr; // 取指结果缓存区写指针
	reg[1:0] if_res_buf_rptr; // 取指结果缓存区读指针
	wire if_res_buf_wen; // 取指结果缓存区写使能
	wire if_res_buf_ren; // 取指结果缓存区读使能
	wire if_res_buf_clr; // 取指结果缓存区清零使能
	wire if_res_buf_full_n; // 取指结果缓存区满标志
	wire if_res_buf_empty_n; // 取指结果缓存区空标志
	reg[100+inst_id_width-1:0] if_res_buf_regs[0:2]; // 取指结果缓存寄存器组
	reg[inst_id_width-1:0] inst_id_cnt; // 指令编号计数器
	
	assign if_res_data[95:0] = if_res_buf_regs[if_res_buf_rptr][IF_RES_BUF_DATA_SID+95:IF_RES_BUF_DATA_SID];
	assign if_res_msg = if_res_buf_regs[if_res_buf_rptr][IF_RES_BUF_MSG_SID+3:IF_RES_BUF_MSG_SID];
	assign m_if_res_id = if_res_buf_regs[if_res_buf_rptr][IF_RES_BUF_ID_SID+inst_id_width-1:IF_RES_BUF_ID_SID];
	// 取指结果握手条件: (~if_res_buf_clr) & if_res_buf_empty_n & if_res_ready
	assign if_res_valid = (~if_res_buf_clr) & if_res_buf_empty_n;
	
	assign if_res_buf_wen = vld_inst_gotten; // 断言: 取指结果缓存区写使能有效时必定非满!
	assign if_res_buf_ren = if_res_ready;
	assign if_res_buf_clr = rst_req | flush_req;
	assign if_res_buf_full_n = ~if_res_buf_store_n[3];
	assign if_res_buf_empty_n = ~if_res_buf_store_n[0];
	
	// 取指结果缓存区存储个数
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			if_res_buf_store_n <= 4'b0001;
		else if(if_res_buf_clr | ((if_res_buf_ren & if_res_buf_empty_n) ^ if_res_buf_wen))
			if_res_buf_store_n <= # simulation_delay 
				if_res_buf_clr ? 4'b0001: // 清零取指结果缓存区
					(if_res_buf_wen ? {if_res_buf_store_n[2:0], if_res_buf_store_n[3]}: // 存储个数增加1
						{if_res_buf_store_n[0], if_res_buf_store_n[3:1]}); // 存储个数减少1
	end
	
	// 取指结果缓存区写指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			if_res_buf_wptr <= 2'b00;
		else if(if_res_buf_clr | if_res_buf_wen)
			// ((if_res_buf_wptr == 2'b10) | if_res_buf_clr) ? 2'b00:(if_res_buf_wptr + 2'b01)
			if_res_buf_wptr <= # simulation_delay {2{~(if_res_buf_wptr[1] | if_res_buf_clr)}} & (if_res_buf_wptr + 2'b01);
	end
	// 取指结果缓存区读指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			if_res_buf_rptr <= 2'b00;
		else if(if_res_buf_clr | (if_res_buf_ren & if_res_buf_empty_n))
			// (if_res_buf_rptr == 2'b10) ? 2'b00:(if_res_buf_rptr + 2'b01)
			if_res_buf_rptr <= # simulation_delay {2{~(if_res_buf_rptr[1] | if_res_buf_clr)}} & (if_res_buf_rptr + 2'b01);
	end
	
	// 写取指结果缓存寄存器组
	genvar if_res_buf_regs_i;
	generate
		for(if_res_buf_regs_i = 0;if_res_buf_regs_i < 3;if_res_buf_regs_i = if_res_buf_regs_i + 1)
		begin
			always @(posedge clk)
			begin
				if((~if_res_buf_clr) & if_res_buf_wen & (if_res_buf_wptr == if_res_buf_regs_i))
					if_res_buf_regs[if_res_buf_regs_i] <= # simulation_delay {
						// 指令编号(inst_id_width bit)
						inst_id_cnt,
						// 取指附加信息(4bit)
						to_jump, 
						illegal_inst, 
						imem_access_resp_err, 
						// 打包的预译码信息(64bit)
						pre_decoding_msg_packeted, 
						// 取到的指令(32bit)
						imem_access_resp_rdata
					};
			end
		end
	endgenerate
	
	// 指令编号计数器
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			inst_id_cnt <= 0;
		else if((~if_res_buf_clr) & if_res_buf_wen)
			inst_id_cnt <= # simulation_delay inst_id_cnt + 1;
	end
	
	/** 发起指令存储器访问请求 **/
	reg rst_imem_access_req_pending; // 待发起的复位IMEM访问请求标志
	reg flush_imem_access_req_pending; // 待发起的冲刷IMEM访问请求标志
	reg common_imem_access_req_pending; // 待发起的普通IMEM访问请求标志
	wire now_inst_vld; // 当前指令有效
	reg[31:0] inst_latched; // 锁存的指令
	reg[31:0] flush_addr_latched; // 锁存的冲刷地址
	reg[1:0] processing_imem_access_req_n; // 滞外的IMEM访问请求(已发起但后级未取走指令的访问请求)个数
	wire[1:0] processing_imem_access_req_n_with_rst_flush; // 考虑复位/冲刷后的滞外的IMEM访问请求个数
	reg[31:0] pc_regs; // PC寄存器
	reg[31:0] pc_buf_regs[0:2]; // 指令对应PC值缓存寄存器组
	reg[2:0] pc_buf_wptr; // 指令对应PC值缓存区写指针
	wire pc_buf_wen; // 指令对应PC值缓存区写使能
	reg inst_suppress_buf_regs[0:2]; // 取指结果镇压标志缓存寄存器组
	reg[2:0] inst_suppress_buf_wptr; // 取指结果镇压标志缓存区写指针
	wire inst_suppress_buf_wen; // 取指结果镇压标志缓存区写使能
	reg[1:0] inst_suppress_buf_rptr; // 取指结果镇压标志缓存区读指针
	wire[2:0] inst_suppress_buf_rptr_add1; // 取指结果镇压标志缓存区读指针 + 1
	wire inst_suppress_buf_ren; // 取指结果镇压标志缓存区读使能
	wire jalr_allow; // 允许无条件间接跳转(标志)
	wire on_now_inst_suppress; // 当前指令被镇压(指示)
	
	assign rst_ack = to_rst & (processing_imem_access_req_n != 2'b11) & (~dpc_trace_tb_full) & imem_access_req_ready;
	assign flush_ack = to_flush & (processing_imem_access_req_n != 2'b11) & (~dpc_trace_tb_full) & imem_access_req_ready;
	
	assign to_rst = rst_req | rst_imem_access_req_pending;
	assign to_flush = flush_req | flush_imem_access_req_pending;
	assign flush_addr_hold = flush_req ? flush_addr:flush_addr_latched;
	assign now_pc = pc_regs;
	
	assign now_inst = common_imem_access_req_pending ? inst_latched:imem_access_resp_rdata;
	
	assign vld_inst_gotten = imem_access_resp_valid & 
		(~(to_rst | to_flush | inst_suppress_buf_regs[inst_suppress_buf_rptr])); // 当前指令可能被镇压
	
	assign imem_access_req_addr = new_pc;
	assign imem_access_req_read = 1'b1;
	assign imem_access_req_wdata = 32'hxxxx_xxxx;
	assign imem_access_req_wmask = 4'b0000;
	// 指令存储器访问请求握手条件: (processing_imem_access_req_n != 2'b11) & (~dpc_trace_tb_full) & imem_access_req_ready & 
	//     (to_rst | to_flush | (now_inst_vld & ((~is_jalr_inst) | jalr_allow)))
	assign imem_access_req_valid = (processing_imem_access_req_n != 2'b11) & (~dpc_trace_tb_full) & 
		(to_rst | to_flush | (now_inst_vld & ((~is_jalr_inst) | jalr_allow)));
	
	// 指令对应的PC
	// 读端口位于取指结果处, 因此使用取指结果缓存区读指针
	assign if_res_data[127:96] = pc_buf_regs[if_res_buf_rptr];
	
	assign now_inst_vld = vld_inst_gotten | common_imem_access_req_pending;
	assign processing_imem_access_req_n_with_rst_flush = 
		if_res_buf_clr ? 
			// 复位/冲刷时提前减去取指结果缓存区的存储个数
			(processing_imem_access_req_n - 
				(({2{if_res_buf_store_n[0]}} & 2'b00) | 
				({2{if_res_buf_store_n[1]}} & 2'b01) | 
				({2{if_res_buf_store_n[2]}} & 2'b10) | 
				({2{if_res_buf_store_n[3]}} & 2'b11))):
			processing_imem_access_req_n;
	assign pc_buf_wen = imem_access_req_valid & imem_access_req_ready;
	
	assign inst_suppress_buf_rptr_add1 = {
		inst_suppress_buf_rptr == 2'b01,
		inst_suppress_buf_rptr == 2'b00,
		inst_suppress_buf_rptr == 2'b10
	};
	assign inst_suppress_buf_wen = imem_access_req_valid & imem_access_req_ready;
	assign inst_suppress_buf_ren = imem_access_resp_valid;
	
	assign on_now_inst_suppress = imem_access_resp_valid & (to_rst | to_flush | inst_suppress_buf_regs[inst_suppress_buf_rptr]);
	
	// 待发起的复位IMEM访问请求标志
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			rst_imem_access_req_pending <= 1'b0;
		else
			rst_imem_access_req_pending <= # simulation_delay 
			/*
				rst_imem_access_req_pending ? 
					(~((processing_imem_access_req_n != 2'b11) & 
						(~dpc_trace_tb_full) & imem_access_req_ready)): // 等待指令存储器访问请求成功发起
					(rst_req & (~((processing_imem_access_req_n != 2'b11) & (~dpc_trace_tb_full) & 
						imem_access_req_ready))) // 复位请求不能被立即处理, 置位等待标志
			*/
				(rst_imem_access_req_pending | rst_req) & 
				(~((processing_imem_access_req_n != 2'b11) & (~dpc_trace_tb_full) & imem_access_req_ready));
	end
	// 待发起的冲刷IMEM访问请求标志
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			flush_imem_access_req_pending <= 1'b0;
		else
			flush_imem_access_req_pending <= # simulation_delay 
			/*
				flush_imem_access_req_pending ? 
					(~(rst_req | // 该等待标志可能会被复位请求打断
						((processing_imem_access_req_n != 2'b11) & 
							(~dpc_trace_tb_full) & imem_access_req_ready))): // 等待指令存储器访问请求成功发起
					(flush_req & (~((processing_imem_access_req_n != 2'b11) & (~dpc_trace_tb_full) & 
						imem_access_req_ready))) // 冲刷请求不能被立即处理, 置位等待标志
			*/
				(flush_imem_access_req_pending ? (~rst_req):flush_req) & 
				(~((processing_imem_access_req_n != 2'b11) & (~dpc_trace_tb_full) & imem_access_req_ready));
	end
	// 待发起的普通IMEM访问请求标志
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			common_imem_access_req_pending <= 1'b0;
		else
			common_imem_access_req_pending <= # simulation_delay 
			/*
				common_imem_access_req_pending ? 
					(~(rst_req | flush_req | 
						((processing_imem_access_req_n != 2'b11) & imem_access_req_ready & (~dpc_trace_tb_full) & 
						((~is_jalr_inst) | jalr_allow)))): // 等待指令存储器访问请求成功发起, 
														   // 该等待标志可能会被复位/冲刷请求打断
					((~rst_req) & (~rst_imem_access_req_pending) & (~flush_req) & (~flush_imem_access_req_pending) & 
						vld_inst_gotten & (~((processing_imem_access_req_n != 2'b11) & imem_access_req_ready & (~dpc_trace_tb_full) & 
						((~is_jalr_inst) | jalr_allow)))) // 指令总线控制单元返回取指结果且当前不处于复位/冲刷状态, 
						                                  // 新的IMEM访问请求不能被立即处理, 置位等待标志
			*/
				(~rst_req) & (~flush_req) & 
				(common_imem_access_req_pending | 
					((~rst_imem_access_req_pending) & (~flush_imem_access_req_pending) & vld_inst_gotten)) & 
				(~((processing_imem_access_req_n != 2'b11) & imem_access_req_ready & (~dpc_trace_tb_full) & 
					((~is_jalr_inst) | jalr_allow)));
	end
	
	// 锁存的指令
	always @(posedge clk)
	begin
		if(imem_access_resp_valid)
			inst_latched <= # simulation_delay imem_access_resp_rdata;
	end
	// 锁存的冲刷地址
	always @(posedge clk)
	begin
		if(flush_req)
			flush_addr_latched <= # simulation_delay flush_addr;
	end
	
	// 滞外的IMEM访问请求个数
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			processing_imem_access_req_n <= 2'b00;
		else if(if_res_buf_clr | ((imem_access_req_valid & imem_access_req_ready) ^ ((if_res_valid & if_res_ready) | on_now_inst_suppress)))
			processing_imem_access_req_n <= # simulation_delay 
				/*
				(((imem_access_req_valid & imem_access_req_ready) ^ (if_res_valid & if_res_ready)) ? 
					((if_res_valid & if_res_ready) ? (processing_imem_access_req_n_with_rst_flush - 2'b01):
						(processing_imem_access_req_n_with_rst_flush + 2'b01)):
					processing_imem_access_req_n_with_rst_flush) + {2{on_now_inst_suppress}}
				*/
				processing_imem_access_req_n_with_rst_flush + 
					({2{(imem_access_req_valid & imem_access_req_ready) ^ (if_res_valid & if_res_ready)}} & 
					{if_res_valid & if_res_ready, 1'b1}) + 
					{2{on_now_inst_suppress}};
	end
	
	// PC寄存器
	always @(posedge clk)
	begin
		if(imem_access_req_valid & imem_access_req_ready)
			pc_regs <= # simulation_delay new_pc;
	end
	
	// 写指令对应PC值缓存寄存器组
	genvar pc_buf_regs_i;
	generate
		for(pc_buf_regs_i = 0;pc_buf_regs_i < 3;pc_buf_regs_i = pc_buf_regs_i + 1)
		begin
			always @(posedge clk)
			begin
				if(pc_buf_wen & ((to_rst | to_flush) ? 
					(pc_buf_regs_i == 0): // 复位/冲刷时固定写第1项
					pc_buf_wptr[pc_buf_regs_i]))
					pc_buf_regs[pc_buf_regs_i] <= # simulation_delay new_pc;
			end
		end
	endgenerate
	
	// 指令对应PC值缓存区写指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			pc_buf_wptr <= 3'b001;
		else if(pc_buf_wen)
			pc_buf_wptr <= # simulation_delay 
				(to_rst | to_flush) ? 3'b010: // 保留复位/冲刷时的PC记录
					{pc_buf_wptr[1:0], pc_buf_wptr[2]};
	end
	
	// 写取指结果镇压标志缓存寄存器组
	genvar inst_suppress_buf_regs_i;
	generate
		for(inst_suppress_buf_regs_i = 0;inst_suppress_buf_regs_i < 3;inst_suppress_buf_regs_i = inst_suppress_buf_regs_i + 1)
		begin
			always @(posedge clk)
			begin
				if(inst_suppress_buf_wen & ((to_rst | to_flush) | inst_suppress_buf_wptr[inst_suppress_buf_regs_i]))
					inst_suppress_buf_regs[inst_suppress_buf_regs_i] <= # simulation_delay 
						(~inst_suppress_buf_wptr[inst_suppress_buf_regs_i]) & // 保留复位/冲刷时发起的请求
						(to_rst | to_flush) & (
							({2{processing_imem_access_req_n_with_rst_flush == 2'b01}} & 
								(inst_suppress_buf_rptr == inst_suppress_buf_regs_i)) | // 镇压尚未返回响应的接下来1个指令存储器访问应答
							({2{processing_imem_access_req_n_with_rst_flush == 2'b10}} & 
								((inst_suppress_buf_rptr == inst_suppress_buf_regs_i) | 
								inst_suppress_buf_rptr_add1[inst_suppress_buf_regs_i])) // 镇压尚未返回响应的接下来2个指令存储器访问应答
						);
			end
		end
	endgenerate
	
	// 取指结果镇压标志缓存区写指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			inst_suppress_buf_wptr <= 3'b001;
		else if(inst_suppress_buf_wen)
			inst_suppress_buf_wptr <= # simulation_delay {inst_suppress_buf_wptr[1:0], inst_suppress_buf_wptr[2]};
	end
	
	// 取指结果镇压标志缓存区读指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			inst_suppress_buf_rptr <= 2'b00;
		else if(inst_suppress_buf_ren)
			// (inst_suppress_buf_rptr == 2'b10) ? 2'b00:(inst_suppress_buf_rptr + 2'b01)
			inst_suppress_buf_rptr <= # simulation_delay {2{~inst_suppress_buf_rptr[1]}} & (inst_suppress_buf_rptr + 2'b01);
	end
	
	/** JALR指令处理 **/
	reg jalr_baseaddr_latched_flag; // JALR指令基址已锁存(标志)
	reg[31:0] jalr_baseaddr_latched; // 锁存的JALR指令基址
	
	assign rs1_v = jalr_baseaddr_latched_flag ? jalr_baseaddr_latched:jalr_baseaddr_v;
	
	assign jalr_allow = jalr_baseaddr_vld | jalr_baseaddr_latched_flag;
	
	// JALR指令基址已锁存(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			jalr_baseaddr_latched_flag <= 1'b0;
		else if(jalr_baseaddr_vld | (imem_access_req_valid & imem_access_req_ready))
			jalr_baseaddr_latched_flag <= # simulation_delay 
				(~(imem_access_req_valid & imem_access_req_ready)) & jalr_baseaddr_vld;
	end
	
	// 锁存的JALR指令基址
	always @(posedge clk)
	begin
		if(jalr_baseaddr_vld)
			jalr_baseaddr_latched <= # simulation_delay jalr_baseaddr_v;
	end
	
	/** 数据相关性跟踪 **/
	assign has_processing_imem_access_req = 
		(if_res_buf_store_n[0] & (processing_imem_access_req_n != 2'b00)) | 
		(if_res_buf_store_n[1] & (processing_imem_access_req_n != 2'b01)) | 
		(if_res_buf_store_n[2] & (processing_imem_access_req_n != 2'b10));
	
	assign dpc_trace_enter_ifq_inst = imem_access_resp_rdata;
	assign dpc_trace_enter_ifq_rd_id = imem_access_resp_rdata[11:7];
	assign dpc_trace_enter_ifq_rd_vld = pre_decoding_msg_packeted[PRE_DCD_MSG_RD_VLD_SID];
	assign dpc_trace_enter_ifq_is_long_inst = 
		pre_decoding_msg_packeted[PRE_DCD_MSG_IS_LOAD_INST_SID] | 
		pre_decoding_msg_packeted[PRE_DCD_MSG_IS_STORE_INST_SID] | 
		pre_decoding_msg_packeted[PRE_DCD_MSG_IS_MUL_INST_SID] | 
		pre_decoding_msg_packeted[PRE_DCD_MSG_IS_DIV_INST_SID] | 
		pre_decoding_msg_packeted[PRE_DCD_MSG_IS_REM_INST_SID];
	assign dpc_trace_enter_ifq_inst_id = inst_id_cnt;
	assign dpc_trace_enter_ifq_valid = if_res_buf_wen;
	
endmodule
