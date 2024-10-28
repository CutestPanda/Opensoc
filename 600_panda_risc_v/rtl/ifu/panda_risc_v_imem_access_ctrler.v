`timescale 1ns / 1ps
/********************************************************************
本模块: 指令存储器访问控制

描述:
将指令总线控制单元返回的取指结果存入深度为2的取指结果缓存区
发起指令存储器访问请求并更新PC

延长复位/冲刷请求, 生成正在复位/冲刷标志

复位/冲刷时会将取指结果缓存区中的每1项清零为NOP, 并将当前的取指结果选择为NOP

IMEM访问请求的生命周期:
	发起IMEM访问请求 -> 指令总线控制单元返回取指结果 -> 指令被后级取走

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/10/28
********************************************************************/


module panda_risc_v_imem_access_ctrler #(
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
	output wire[127:0] if_res_data, // {指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)}
	output wire[3:0] if_res_msg, // {是否预测跳转(1bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)}
	output wire if_res_valid,
	input wire if_res_ready
);
	
	/** 常量 **/
	// 指令存储器访问应答错误类型
	localparam IMEM_ACCESS_NORMAL = 2'b00; // 正常
	localparam IMEM_ACCESS_PC_UNALIGNED = 2'b01; // 指令地址非对齐
	localparam IMEM_ACCESS_BUS_ERR = 2'b10; // 指令总线访问错误
	localparam IMEM_ACCESS_TIMEOUT = 2'b11; // 响应超时
	// 空指令
	localparam NOP_INST = 32'h0000_0013;
	// 复位或冲刷时的取指结果
	localparam IF_RES_AT_RST_FLUSH = {
		19'dx,
		// CSR寄存器地址(12bit)
		12'd0,
		// 读写通用寄存器堆标志(3bit)
		1'b1, 1'b0, 1'b1,
		// 跳转偏移量立即数(21bit)
		21'd0,
		// 指令类型标志(9bit)
		1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
		1'b0, 1'b0, 1'b0, 1'b0,
		
		// 取到的指令
		NOP_INST
	};
	
	/** 取指结果缓存区 **/
	reg[2:0] if_res_buf_store_n; // 取指结果缓存区存储个数(3'b001 -> 0, 3'b010 -> 1, 3'b100 -> 2)
	reg if_res_buf_wptr; // 取指结果缓存区写指针
	reg if_res_buf_rptr; // 取指结果缓存区读指针
	wire if_res_buf_wen; // 取指结果缓存区写使能
	wire if_res_buf_ren; // 取指结果缓存区读使能
	wire if_res_buf_clr; // 取指结果缓存区清零使能
	wire if_res_buf_full_n; // 取指结果缓存区满标志
	wire if_res_buf_empty_n; // 取指结果缓存区空标志
	// 取指结果缓存寄存器组({是否预测跳转(1bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit), 
	//     打包的预译码信息(64bit), 取到的指令(32bit)})
	reg[99:0] if_res_buf_regs[0:1];
	
	assign if_res_data[95:0] = (rst_req | flush_req) ? 
		IF_RES_AT_RST_FLUSH:if_res_buf_regs[if_res_buf_rptr][95:0]; // 取指结果
	assign if_res_msg = (rst_req | flush_req) ? 
		{1'b0, 1'b0, IMEM_ACCESS_NORMAL}:if_res_buf_regs[if_res_buf_rptr][99:96]; // 取指附加信息
	// 取指结果握手条件: if_res_buf_empty_n & if_res_ready
	assign if_res_valid = if_res_buf_empty_n;
	
	assign if_res_buf_wen = vld_inst_gotten; // 断言: 取指结果缓存区写使能有效时必定非满!
	assign if_res_buf_ren = if_res_ready;
	assign if_res_buf_clr = rst_req | flush_req; // 复位/冲刷时将取指结果缓存区中的每1项清零为NOP
	assign if_res_buf_full_n = ~if_res_buf_store_n[2];
	assign if_res_buf_empty_n = ~if_res_buf_store_n[0];
	
	// 取指结果缓存区存储个数
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			if_res_buf_store_n <= 3'b001;
		else if((if_res_buf_ren & if_res_buf_empty_n) ^ if_res_buf_wen)
			if_res_buf_store_n <= # simulation_delay if_res_buf_wen ? 
				{if_res_buf_store_n[1:0], if_res_buf_store_n[2]}: // 存储个数增加1
				{if_res_buf_store_n[0], if_res_buf_store_n[2:1]}; // 存储个数减少1
	end
	
	// 取指结果缓存区写指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			if_res_buf_wptr <= 1'b0;
		else if(if_res_buf_wen)
			if_res_buf_wptr <= # simulation_delay ~if_res_buf_wptr;
	end
	// 取指结果缓存区读指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			if_res_buf_rptr <= 1'b0;
		else if(if_res_buf_ren & if_res_buf_empty_n)
			if_res_buf_rptr <= # simulation_delay ~if_res_buf_rptr;
	end
	
	// 取指结果缓存寄存器组
	// 存储项#0
	always @(posedge clk)
	begin
		if(if_res_buf_clr | (if_res_buf_wen & (~if_res_buf_wptr)))
			if_res_buf_regs[0] <= # simulation_delay if_res_buf_clr ? 
			{
				1'b0,
				1'b0,
				IMEM_ACCESS_NORMAL,
				IF_RES_AT_RST_FLUSH
			}:{
				to_jump, 
				illegal_inst, 
				imem_access_resp_err, 
				pre_decoding_msg_packeted, 
				imem_access_resp_rdata
			};
	end
	// 存储项#1
	always @(posedge clk)
	begin
		if(if_res_buf_clr | (if_res_buf_wen & if_res_buf_wptr))
			if_res_buf_regs[1] <= # simulation_delay if_res_buf_clr ? 
			{
				1'b0,
				1'b0,
				IMEM_ACCESS_NORMAL,
				IF_RES_AT_RST_FLUSH
			}:{
				to_jump, 
				illegal_inst, 
				imem_access_resp_err, 
				pre_decoding_msg_packeted, 
				imem_access_resp_rdata
			};
	end
	
	/** 发起指令存储器访问请求 **/
	reg rst_imem_access_req_pending; // 待发起的复位IMEM访问请求标志
	reg flush_imem_access_req_pending; // 待发起的冲刷IMEM访问请求标志
	reg common_imem_access_req_pending; // 待发起的普通IMEM访问请求标志
	wire now_inst_vld; // 当前指令有效
	reg[31:0] inst_latched; // 锁存的指令
	reg[31:0] flush_addr_latched; // 锁存的冲刷地址
	reg[1:0] processing_imem_access_req_n; // 滞外的IMEM访问请求(已发起但后级未取走指令的访问请求)个数
	reg[31:0] pc_regs; // PC寄存器
	reg[31:0] pc_buf_regs[0:1]; // 指令对应PC值缓存寄存器组
	reg pc_buf_wptr; // 指令对应PC值缓存区写指针
	wire pc_buf_wen; // 指令对应PC值缓存区写使能
	reg inst_suppress_buf_regs[0:1]; // 取指结果镇压标志缓存寄存器组
	reg inst_suppress_buf_wptr; // 取指结果镇压标志缓存区写指针
	wire inst_suppress_buf_wen; // 取指结果镇压标志缓存区写使能
	reg inst_suppress_buf_rptr; // 取指结果镇压标志缓存区读指针
	wire inst_suppress_buf_ren; // 取指结果镇压标志缓存区读使能
	wire inst_suppress_buf_clr; // 取指结果镇压标志缓存区清零使能
	wire jalr_allow; // 允许无条件间接跳转(标志)
	
	assign to_rst = rst_req | rst_imem_access_req_pending;
	assign to_flush = flush_req | flush_imem_access_req_pending;
	assign flush_addr_hold = flush_imem_access_req_pending ? flush_addr_latched:flush_addr;
	assign now_pc = pc_regs;
	
	assign now_inst = common_imem_access_req_pending ? inst_latched:imem_access_resp_rdata;
	
	assign vld_inst_gotten = imem_access_resp_valid & 
		(~(inst_suppress_buf_regs[inst_suppress_buf_rptr] | inst_suppress_buf_clr));
	
	assign imem_access_req_addr = new_pc;
	assign imem_access_req_read = 1'b1;
	assign imem_access_req_wdata = 32'hxxxx_xxxx;
	assign imem_access_req_wmask = 4'b0000;
	// 指令存储器访问请求握手条件: (~processing_imem_access_req_n[1]) & imem_access_req_ready & 
	//     (to_rst | to_flush | (now_inst_vld & ((~is_jalr_inst) | jalr_allow)))
	assign imem_access_req_valid = (~processing_imem_access_req_n[1]) & // 必须保证滞外请求个数 <= 2
		(to_rst | to_flush | (now_inst_vld & ((~is_jalr_inst) | jalr_allow)));
	
	// 指令对应的PC
	// 读端口位于取指结果处, 因此使用取指结果缓存区读指针
	assign if_res_data[127:96] = pc_buf_regs[if_res_buf_rptr];
	
	assign now_inst_vld = vld_inst_gotten | common_imem_access_req_pending;
	assign pc_buf_wen = imem_access_req_valid & imem_access_req_ready;
	
	assign inst_suppress_buf_wen = imem_access_req_valid & imem_access_req_ready;
	assign inst_suppress_buf_ren = imem_access_resp_valid;
	assign inst_suppress_buf_clr = rst_req | flush_req; // 复位/冲刷时镇压已发起但未返回取指结果的访问请求
	
	// 待发起的复位IMEM访问请求标志
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			rst_imem_access_req_pending <= 1'b0;
		else
			rst_imem_access_req_pending <= # simulation_delay 
			/*
				rst_imem_access_req_pending ? 
					(~((~processing_imem_access_req_n[1]) & imem_access_req_ready)): // 等待指令存储器访问请求成功发起
					(rst_req & (~((~processing_imem_access_req_n[1]) & 
						imem_access_req_ready))) // 复位请求不能被立即处理, 置位等待标志
			*/
				(rst_imem_access_req_pending | rst_req) & 
				(~((~processing_imem_access_req_n[1]) & imem_access_req_ready));
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
					(~((~processing_imem_access_req_n[1]) & imem_access_req_ready)): // 等待指令存储器访问请求成功发起
					(flush_req & (~((~processing_imem_access_req_n[1]) & 
						imem_access_req_ready))) // 冲刷请求不能被立即处理, 置位等待标志
			*/
				(flush_imem_access_req_pending | flush_req) & 
				(~((~processing_imem_access_req_n[1]) & imem_access_req_ready));
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
						((~processing_imem_access_req_n[1]) & imem_access_req_ready & 
						((~is_jalr_inst) | jalr_allow)))): // 等待指令存储器访问请求成功发起, 
																  // 该等待标志可能会被复位/冲刷请求打断
					((~rst_req) & (~rst_imem_access_req_pending) & (~flush_req) & (~flush_imem_access_req_pending) & 
						vld_inst_gotten & (~((~processing_imem_access_req_n[1]) & imem_access_req_ready & 
						((~is_jalr_inst) | jalr_allow)))) // 指令总线控制单元返回取指结果且当前不处于复位/冲刷状态, 
						                                         // 新的IMEM访问请求不能被立即处理, 置位等待标志
			*/
				(~rst_req) & (~flush_req) & 
				(common_imem_access_req_pending | 
					((~rst_imem_access_req_pending) & (~flush_imem_access_req_pending) & vld_inst_gotten)) & 
				(~((~processing_imem_access_req_n[1]) & imem_access_req_ready & ((~is_jalr_inst) | jalr_allow)));
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
		else if((imem_access_req_valid & imem_access_req_ready) ^ (if_res_valid & if_res_ready))
			processing_imem_access_req_n <= # simulation_delay 
				// (if_res_valid & if_res_ready) ? (processing_imem_access_req_n - 2'b01):
				//     (processing_imem_access_req_n + 2'b01)
				processing_imem_access_req_n + {if_res_valid & if_res_ready, 1'b1};
	end
	
	// PC寄存器
	always @(posedge clk)
	begin
		if(imem_access_req_valid & imem_access_req_ready)
			pc_regs <= # simulation_delay new_pc;
	end
	
	// 指令对应PC值缓存寄存器组
	// 存储项#0
	always @(posedge clk)
	begin
		if(pc_buf_wen & (~pc_buf_wptr))
			pc_buf_regs[0] <= # simulation_delay new_pc;
	end
	// 存储项#1
	always @(posedge clk)
	begin
		if(pc_buf_wen & pc_buf_wptr)
			pc_buf_regs[1] <= # simulation_delay new_pc;
	end
	
	// 指令对应PC值缓存区写指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			pc_buf_wptr <= 1'b0;
		else if(pc_buf_wen)
			pc_buf_wptr <= # simulation_delay ~pc_buf_wptr;
	end
	
	// 取指结果镇压标志缓存寄存器组
	// 存储项#0
	always @(posedge clk)
	begin
		if(inst_suppress_buf_clr | (inst_suppress_buf_wen & (~inst_suppress_buf_wptr)))
			inst_suppress_buf_regs[0] <= # simulation_delay inst_suppress_buf_clr;
	end
	// 存储项#1
	always @(posedge clk)
	begin
		if(inst_suppress_buf_clr | (inst_suppress_buf_wen & inst_suppress_buf_wptr))
			inst_suppress_buf_regs[1] <= # simulation_delay inst_suppress_buf_clr;
	end
	
	// 取指结果镇压标志缓存区写指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			inst_suppress_buf_wptr <= 1'b0;
		else if(inst_suppress_buf_wen)
			inst_suppress_buf_wptr <= # simulation_delay ~inst_suppress_buf_wptr;
	end
	
	// 取指结果镇压标志缓存区读指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			inst_suppress_buf_rptr <= 1'b0;
		else if(inst_suppress_buf_ren)
			inst_suppress_buf_rptr <= # simulation_delay ~inst_suppress_buf_rptr;
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
	
endmodule
