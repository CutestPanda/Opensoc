`timescale 1ns / 1ps
/********************************************************************
本模块: AXI通用DMA引擎MM2S通道

描述:
接收读请求命令, 驱动AXI读通道, 返回输出数据流
提供4KB边界保护
提供读数据fifo

注意：
不支持回环(WRAP)突发类型
未对非对齐传输时的输出数据流做重新对齐处理
AXI主机的地址位宽固定为32位
突发类型为固定时, 传输基地址必须是对齐的

协议:
AXIS MASTER/SLAVE
AXI MASTER(READ ONLY)

作者: 陈家耀
日期: 2025/01/26
********************************************************************/


module axi_dma_engine_mm2s #(
	parameter integer DATA_WIDTH = 32, // 传输数据位宽(32 | 64 | 128 | 256)
	parameter integer MAX_BURST_LEN = 32, // 最大的突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter S_AXIS_COMMON_CLOCK = "true", // 命令AXIS从机与AXI主机是否使用相同的时钟和复位
	parameter M_AXIS_COMMON_CLOCK = "true", // 输出数据流AXIS主机与AXI主机是否使用相同的时钟和复位
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 命令AXIS从机的时钟和复位
	input wire s_axis_aclk,
	input wire s_axis_aresetn,
	// 输出数据流AXIS主机的时钟和复位
	input wire m_axis_aclk,
	input wire m_axis_aresetn,
	// AXI主机的时钟和复位
	input wire m_axi_aclk,
	input wire m_axi_aresetn,
	
	// 命令AXIS从机
	input wire[55:0] s_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	input wire s_cmd_axis_user, // {固定(1'b1)/递增(1'b0)传输(1bit)}
	input wire s_cmd_axis_valid,
	output wire s_cmd_axis_ready,
	
	// 输出数据流AXIS主机
	output wire[DATA_WIDTH-1:0] m_mm2s_axis_data,
	output wire[DATA_WIDTH/8-1:0] m_mm2s_axis_keep,
	output wire[1:0] m_mm2s_axis_user, // 错误类型(2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR)
	output wire m_mm2s_axis_last,
	output wire m_mm2s_axis_valid,
	input wire m_mm2s_axis_ready,
	
	// AXI主机(读通道)
	// AR通道
	output wire[31:0] m_axi_araddr,
	// 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
	output wire[1:0] m_axi_arburst,
	output wire[3:0] m_axi_arcache, // const -> 4'b0011
	output wire[7:0] m_axi_arlen,
	output wire[2:0] m_axi_arprot, // const -> 3'b000
	output wire[2:0] m_axi_arsize, // const -> clogb2(DATA_WIDTH/8)
	output wire m_axi_arvalid,
	input wire m_axi_arready,
	// R通道
	input wire[DATA_WIDTH-1:0] m_axi_rdata,
	// 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
	input wire[1:0] m_axi_rresp,
	input wire m_axi_rlast,
	input wire m_axi_rvalid,
	output wire m_axi_rready
);
	
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
    end
    endfunction
	
	/** 常量 **/
	// 读地址通道流程控制状态常量
	localparam AR_CTRL_STS_IDLE = 2'b00; // 状态: 空闲
	localparam AR_CTRL_STS_GEN_BURST_MSG_0 = 2'b01; // 状态: 生成突发信息阶段#0
	localparam AR_CTRL_STS_GEN_BURST_MSG_1 = 2'b10; // 状态: 生成突发信息阶段#1
	localparam AR_CTRL_STS_LAUNCH_BURST = 2'b11; // 状态: 启动突发
	// AXI突发类型
	localparam AXI_BURST_FIXED = 2'b00;
	localparam AXI_BURST_INCR = 2'b01;
	localparam AXI_BURST_WRAP = 2'b10;
	// 可缓存的读突发次数
	localparam integer BUFFERABLE_RD_BURST_N = 512 / ((MAX_BURST_LEN >= 16) ? MAX_BURST_LEN:16);
	
	/** 命令fifo **/
	// fifo写端口
	wire[55:0] s_cmd_fifo_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire s_cmd_fifo_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire s_cmd_fifo_axis_valid;
	wire s_cmd_fifo_axis_ready;
	// fifo读端口
	wire[55:0] m_cmd_fifo_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m_cmd_fifo_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m_cmd_fifo_axis_valid;
	wire m_cmd_fifo_axis_ready;
	
	assign s_cmd_fifo_axis_data = s_cmd_axis_data;
	assign s_cmd_fifo_axis_user = s_cmd_axis_user;
	assign s_cmd_fifo_axis_valid = s_cmd_axis_valid;
	assign s_cmd_axis_ready = s_cmd_fifo_axis_ready;
	
	axis_data_fifo #(
		.is_async((S_AXIS_COMMON_CLOCK == "true") ? "false":"true"),
		.en_packet_mode("false"),
		.ram_type("bram"),
		.fifo_depth(512),
		.data_width(56),
		.user_width(1),
		.simulation_delay(SIM_DELAY)
	)cmd_fifo(
		.s_axis_aclk(s_axis_aclk),
		.s_axis_aresetn(s_axis_aresetn),
		.m_axis_aclk(m_axi_aclk),
		.m_axis_aresetn(m_axi_aresetn),
		
		.s_axis_data(s_cmd_fifo_axis_data),
		.s_axis_keep(7'bxxx_xxxx),
		.s_axis_strb(7'bxxx_xxxx),
		.s_axis_user(s_cmd_fifo_axis_user),
		.s_axis_last(1'bx),
		.s_axis_valid(s_cmd_fifo_axis_valid),
		.s_axis_ready(s_cmd_fifo_axis_ready),
		
		.m_axis_data(m_cmd_fifo_axis_data),
		.m_axis_keep(),
		.m_axis_strb(),
		.m_axis_user(m_cmd_fifo_axis_user),
		.m_axis_last(),
		.m_axis_valid(m_cmd_fifo_axis_valid),
		.m_axis_ready(m_cmd_fifo_axis_ready)
	);
	
	/** 命令流输入 **/
	wire[23:0] in_cmd_btt; // 待传输字节数
	wire[31:0] in_cmd_baseaddr; // 传输首地址
	// 注意: 传输末地址用于计算传输次数, 因此仅考虑传输首地址的非对齐部分!
	wire[24:0] in_cmd_trm_addr; // 传输末地址
	wire[23:0] in_cmd_trans_n; // 传输次数
	wire in_cmd_fixed; // 是否固定传输
	wire[DATA_WIDTH/8-1:0] in_cmd_first_keep; // 第1次传输的keep信号
	wire[DATA_WIDTH/8-1:0] in_cmd_last_keep; // 最后1次传输的keep信号
	wire in_cmd_valid;
	wire in_cmd_ready;
	
	assign {in_cmd_btt, in_cmd_baseaddr} = m_cmd_fifo_axis_data;
	assign in_cmd_trm_addr = in_cmd_btt + in_cmd_baseaddr[clogb2(DATA_WIDTH/8-1):0];
	assign in_cmd_trans_n = in_cmd_trm_addr[24:clogb2(DATA_WIDTH/8-1)+1] + (|in_cmd_trm_addr[clogb2(DATA_WIDTH/8-1):0]);
	assign in_cmd_fixed = m_cmd_fifo_axis_user;
	assign in_cmd_valid = m_cmd_fifo_axis_valid;
	assign m_cmd_fifo_axis_ready = in_cmd_ready;
	
	genvar in_cmd_keep_i;
	generate
		for(in_cmd_keep_i = 0;in_cmd_keep_i < DATA_WIDTH/8;in_cmd_keep_i = in_cmd_keep_i + 1)
		begin
			assign in_cmd_first_keep[in_cmd_keep_i] = in_cmd_baseaddr[clogb2(DATA_WIDTH/8-1):0] <= in_cmd_keep_i;
			assign in_cmd_last_keep[in_cmd_keep_i] = 
				(in_cmd_trm_addr[clogb2(DATA_WIDTH/8-1):0] > in_cmd_keep_i) | (~(|in_cmd_trm_addr[clogb2(DATA_WIDTH/8-1):0]));
		end
	endgenerate
	
	/** AXI主机AR通道 **/
	wire burst_msg_fifo_full_n; // 突发信息fifo满标志
	wire rdata_buf_full_n; // 读数据缓存区满标志
	reg last_burst_of_req; // 读请求最后1次突发(标志)
	reg[DATA_WIDTH/8-1:0] first_keep_of_req; // 读请求第1次传输的keep信号
	reg[DATA_WIDTH/8-1:0] last_keep_of_req; // 读请求最后1次传输的keep信号
	reg[1:0] ar_ctrl_sts; // 读地址通道流程控制状态
	reg[23:0] rmn_tn_sub1; // 剩余的传输次数 - 1
	reg[clogb2(4096/(DATA_WIDTH/8)-1):0] rmn_tn_sub1_at_4KB; // 当前4KB区间剩余的传输次数 - 1
	reg[31:0] araddr; // AR通道的突发基址
	reg[1:0] arburst; // AR通道的突发类型
	wire[7:0] arlen; // AR通道的突发长度
	reg arvalid; // AR通道的valid
	/*
	最小值比较
	
	阶段#0: 计算min(剩余的传输次数 - 1, 最大的突发长度 - 1)
	阶段#1: 计算min(阶段#0结果, 当前4KB区间剩余的传输次数 - 1)
	*/
	wire min_cmp_en; // 计算使能
	wire[23:0] min_cmp_op_a; // 操作数A
	wire[11:0] min_cmp_op_b; // 操作数B
	wire min_cmp_a_leq_b; // 比较情况(操作数A <= 操作数B)
	reg[7:0] min_cmp_res; // 计算结果
	reg min_cmp_a_leq_b_pre; // 上一次比较情况(操作数A <= 操作数B)
	
	assign m_axi_araddr = araddr;
	assign m_axi_arburst = arburst;
	assign m_axi_arcache = 4'b0011;
	assign m_axi_arlen = arlen;
	assign m_axi_arprot = 3'b000;
	assign m_axi_arsize = clogb2(DATA_WIDTH/8);
	assign m_axi_arvalid = arvalid;
	
	assign in_cmd_ready = ar_ctrl_sts == AR_CTRL_STS_IDLE;
	
	assign arlen = min_cmp_res;
	
	assign min_cmp_en = 
		((ar_ctrl_sts == AR_CTRL_STS_GEN_BURST_MSG_0) & burst_msg_fifo_full_n & rdata_buf_full_n) | 
		// 注意: 在最小值比较阶段#1, 若突发类型为"固定", 则不必更新"计算结果"和"上一次比较情况"!
		((ar_ctrl_sts == AR_CTRL_STS_GEN_BURST_MSG_1) & (arburst == AXI_BURST_INCR));
	assign min_cmp_op_a = 
		(ar_ctrl_sts == AR_CTRL_STS_GEN_BURST_MSG_0) ? 
			rmn_tn_sub1:{16'h0000, min_cmp_res};
	assign min_cmp_op_b = 
		(ar_ctrl_sts == AR_CTRL_STS_GEN_BURST_MSG_0) ? 
			(((arburst == AXI_BURST_INCR) ? MAX_BURST_LEN:((MAX_BURST_LEN >= 16) ? 12'd16:MAX_BURST_LEN)) - 12'd1):
			{{clogb2(DATA_WIDTH/8){1'b0}}, rmn_tn_sub1_at_4KB};
	assign min_cmp_a_leq_b = 
		(min_cmp_op_a <= {12'h000, min_cmp_op_b}) | 
		// 注意: 在最小值比较阶段#1, 若突发类型为"固定", 则比较情况必定是"操作数A <= 操作数B"!
		((ar_ctrl_sts == AR_CTRL_STS_GEN_BURST_MSG_1) & (arburst != AXI_BURST_INCR));
	
	// 读请求最后1次突发(标志)
	always @(posedge m_axi_aclk)
	begin
		if(ar_ctrl_sts == AR_CTRL_STS_GEN_BURST_MSG_1)
			last_burst_of_req <= # SIM_DELAY min_cmp_a_leq_b_pre & min_cmp_a_leq_b;
	end
	// 读请求第1次传输的keep信号
	always @(posedge m_axi_aclk)
	begin
		if((ar_ctrl_sts == AR_CTRL_STS_IDLE) & in_cmd_valid)
			first_keep_of_req <= # SIM_DELAY in_cmd_first_keep;
	end
	// 读请求最后1次传输的keep信号
	always @(posedge m_axi_aclk)
	begin
		if((ar_ctrl_sts == AR_CTRL_STS_IDLE) & in_cmd_valid)
			last_keep_of_req <= # SIM_DELAY in_cmd_last_keep;
	end
	
	// 读地址通道流程控制状态
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			ar_ctrl_sts <= AR_CTRL_STS_IDLE;
		else if(
			((ar_ctrl_sts == AR_CTRL_STS_IDLE) & in_cmd_valid) | 
			((ar_ctrl_sts == AR_CTRL_STS_GEN_BURST_MSG_0) & burst_msg_fifo_full_n & rdata_buf_full_n) | 
			(ar_ctrl_sts == AR_CTRL_STS_GEN_BURST_MSG_1) | 
			((ar_ctrl_sts == AR_CTRL_STS_LAUNCH_BURST) & m_axi_arready)
		)
			ar_ctrl_sts <= # SIM_DELAY 
				({2{ar_ctrl_sts == AR_CTRL_STS_IDLE}} & AR_CTRL_STS_GEN_BURST_MSG_0) | 
				({2{ar_ctrl_sts == AR_CTRL_STS_GEN_BURST_MSG_0}} & AR_CTRL_STS_GEN_BURST_MSG_1) | 
				({2{ar_ctrl_sts == AR_CTRL_STS_GEN_BURST_MSG_1}} & AR_CTRL_STS_LAUNCH_BURST) | 
				({2{ar_ctrl_sts == AR_CTRL_STS_LAUNCH_BURST}} & 
					(last_burst_of_req ? AR_CTRL_STS_IDLE:AR_CTRL_STS_GEN_BURST_MSG_0)
				);
	end
	
	// 剩余的传输次数 - 1
	always @(posedge m_axi_aclk)
	begin
		if(
			((ar_ctrl_sts == AR_CTRL_STS_IDLE) & in_cmd_valid) | 
			((ar_ctrl_sts == AR_CTRL_STS_LAUNCH_BURST) & m_axi_arready & (~last_burst_of_req))
		)
			rmn_tn_sub1 <= # SIM_DELAY 
				(ar_ctrl_sts == AR_CTRL_STS_IDLE) ? 
					// in_cmd_trans_n - 1'b1
					(in_cmd_trans_n + 24'hff_ffff):
					// rmn_tn_sub1 - ({16'h0000, arlen} + 1'b1)
					(rmn_tn_sub1 + {16'hffff, ~arlen});
	end
	// 当前4KB区间剩余的传输次数 - 1
	always @(posedge m_axi_aclk)
	begin
		if(
			((ar_ctrl_sts == AR_CTRL_STS_IDLE) & in_cmd_valid) | 
			((ar_ctrl_sts == AR_CTRL_STS_LAUNCH_BURST) & m_axi_arready & (~last_burst_of_req) & (arburst == AXI_BURST_INCR))
		)
			rmn_tn_sub1_at_4KB <= # SIM_DELAY 
				(ar_ctrl_sts == AR_CTRL_STS_IDLE) ? 
					(~in_cmd_baseaddr[11:clogb2(DATA_WIDTH/8)]):
					// 注意: 这里将加法位宽拓展到12位, 截取加法结果的低(clogb2(4096/(DATA_WIDTH/8)-1) + 1)位!
					// {{clogb2(DATA_WIDTH/8){1'b0}}, rmn_tn_sub1_at_4KB} - ({4'b0000, arlen} + 1'b1)
					({{clogb2(DATA_WIDTH/8){1'b0}}, rmn_tn_sub1_at_4KB} + {4'b1111, ~arlen});
	end
	
	// AR通道的突发基址
	always @(posedge m_axi_aclk)
	begin
		if(
			((ar_ctrl_sts == AR_CTRL_STS_IDLE) & in_cmd_valid) | 
			((ar_ctrl_sts == AR_CTRL_STS_LAUNCH_BURST) & m_axi_arready & (~last_burst_of_req) & (arburst == AXI_BURST_INCR))
		)
			araddr <= # SIM_DELAY 
				(ar_ctrl_sts == AR_CTRL_STS_IDLE) ? 
					in_cmd_baseaddr:
					({araddr[31:clogb2(DATA_WIDTH/8)], {clogb2(DATA_WIDTH/8){1'b0}}} + (({24'h00_0000, arlen} + 1'b1) * (DATA_WIDTH/8)));
	end
	// AR通道的突发类型
	always @(posedge m_axi_aclk)
	begin
		if((ar_ctrl_sts == AR_CTRL_STS_IDLE) & in_cmd_valid)
			arburst <= # SIM_DELAY in_cmd_fixed ? AXI_BURST_FIXED:AXI_BURST_INCR;
	end
	// AR通道的valid
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			arvalid <= 1'b0;
		else if(
			(ar_ctrl_sts == AR_CTRL_STS_GEN_BURST_MSG_1) | 
			((ar_ctrl_sts == AR_CTRL_STS_LAUNCH_BURST) & m_axi_arready)
		)
			arvalid <= # SIM_DELAY ar_ctrl_sts == AR_CTRL_STS_GEN_BURST_MSG_1;
	end
	
	// 最小值比较计算结果
	always @(posedge m_axi_aclk)
	begin
		if(min_cmp_en)
			min_cmp_res <= # SIM_DELAY min_cmp_a_leq_b ? min_cmp_op_a[7:0]:min_cmp_op_b[7:0];
	end
	// 上一次比较情况(操作数A <= 操作数B)
	always @(posedge m_axi_aclk)
	begin
		if(min_cmp_en)
			min_cmp_a_leq_b_pre <= # SIM_DELAY min_cmp_a_leq_b;
	end
	
	/** 突发信息fifo **/
	// fifo写端口
	wire burst_msg_fifo_wen;
	wire burst_msg_fifo_din_last_burst; // 读请求最后1次突发标志
	wire[DATA_WIDTH/8-1:0] burst_msg_fifo_din_last_keep; // 读请求最后1次传输的keep信号
	wire[DATA_WIDTH/8-1:0] burst_msg_fifo_din_first_keep; // 读请求第1次传输的keep信号
	// fifo读端口
	wire burst_msg_fifo_ren;
	wire burst_msg_fifo_dout_last_burst; // 读请求最后1次突发标志
	wire[DATA_WIDTH/8-1:0] burst_msg_fifo_dout_last_keep; // 读请求最后1次传输的keep信号
	wire[DATA_WIDTH/8-1:0] burst_msg_fifo_dout_first_keep; // 读请求第1次传输的keep信号
	wire burst_msg_fifo_empty_n;
	
	assign burst_msg_fifo_wen = m_axi_arvalid & m_axi_arready;
	assign burst_msg_fifo_din_last_burst = last_burst_of_req;
	assign burst_msg_fifo_din_last_keep = last_keep_of_req;
	assign burst_msg_fifo_din_first_keep = first_keep_of_req;
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(4),
		.fifo_data_width(DATA_WIDTH/4+1),
		.almost_full_th(2),
		.almost_empty_th(2),
		.simulation_delay(SIM_DELAY)
	)burst_msg_fifo(
		.clk(m_axi_aclk),
		.rst_n(m_axi_aresetn),
		
		.fifo_wen(burst_msg_fifo_wen),
		.fifo_din({burst_msg_fifo_din_first_keep, burst_msg_fifo_din_last_keep, burst_msg_fifo_din_last_burst}),
		.fifo_full(),
		.fifo_full_n(burst_msg_fifo_full_n),
		.fifo_almost_full(),
		.fifo_almost_full_n(),
		
		.fifo_ren(burst_msg_fifo_ren),
		.fifo_dout({burst_msg_fifo_dout_first_keep, burst_msg_fifo_dout_last_keep, burst_msg_fifo_dout_last_burst}),
		.fifo_empty(),
		.fifo_empty_n(burst_msg_fifo_empty_n),
		.fifo_almost_empty(),
		.fifo_almost_empty_n(),
		
		.data_cnt()
	);
	
	/** 读数据缓存区 **/
	// 读请求首末传输标志
	reg first_trans_at_rdata; // 读请求第1次传输(标志)
	wire last_trans_at_rdata; // 读请求最后1次传输(标志)
	// 读数据缓存控制
	reg[clogb2(BUFFERABLE_RD_BURST_N):0] pre_launched_rd_burst_n; // 预启动的读突发次数
	// fifo写端口
	wire[DATA_WIDTH-1:0] s_rdata_fifo_axis_data;
	wire[DATA_WIDTH/8-1:0] s_rdata_fifo_axis_keep;
	wire[1:0] s_rdata_fifo_axis_user; // 错误类型(2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR)
	wire s_rdata_fifo_axis_last;
	wire s_rdata_fifo_axis_valid;
	wire s_rdata_fifo_axis_ready;
	// fifo读端口
	wire[DATA_WIDTH-1:0] m_rdata_fifo_axis_data;
	wire[DATA_WIDTH/8-1:0] m_rdata_fifo_axis_keep;
	wire[1:0] m_rdata_fifo_axis_user; // 错误类型(2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR)
	wire m_rdata_fifo_axis_last;
	wire m_rdata_fifo_axis_valid;
	wire m_rdata_fifo_axis_ready;
	
	assign s_rdata_fifo_axis_data = m_axi_rdata;
	/*
	({first_trans_at_rdata, last_trans_at_rdata} == 2'b00) ? {(DATA_WIDTH/8){1'b1}}:
	({first_trans_at_rdata, last_trans_at_rdata} == 2'b01) ? burst_msg_fifo_dout_last_keep:
	({first_trans_at_rdata, last_trans_at_rdata} == 2'b10) ? burst_msg_fifo_dout_first_keep:
														 (burst_msg_fifo_dout_first_keep & burst_msg_fifo_dout_last_keep)
	*/
	assign s_rdata_fifo_axis_keep = 
		({(DATA_WIDTH/8){~first_trans_at_rdata}} | burst_msg_fifo_dout_first_keep) & 
		({(DATA_WIDTH/8){~last_trans_at_rdata}} | burst_msg_fifo_dout_last_keep);
	assign s_rdata_fifo_axis_user = m_axi_rresp;
	assign s_rdata_fifo_axis_last = last_trans_at_rdata;
	assign s_rdata_fifo_axis_valid = m_axi_rvalid & burst_msg_fifo_empty_n;
	assign m_axi_rready = s_rdata_fifo_axis_ready & burst_msg_fifo_empty_n;
	
	assign m_mm2s_axis_data = m_rdata_fifo_axis_data;
	assign m_mm2s_axis_keep = m_rdata_fifo_axis_keep;
	assign m_mm2s_axis_user = m_rdata_fifo_axis_user;
	assign m_mm2s_axis_last = m_rdata_fifo_axis_last;
	assign m_mm2s_axis_valid = m_rdata_fifo_axis_valid;
	assign m_rdata_fifo_axis_ready = m_mm2s_axis_ready;
	
	assign rdata_buf_full_n = pre_launched_rd_burst_n != BUFFERABLE_RD_BURST_N;
	
	assign burst_msg_fifo_ren = m_axi_rvalid & s_rdata_fifo_axis_ready & m_axi_rlast;
	
	assign last_trans_at_rdata = m_axi_rlast & burst_msg_fifo_dout_last_burst;
	
	// 读请求第1次传输(标志)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			first_trans_at_rdata <= 1'b1;
		else if(s_rdata_fifo_axis_valid & s_rdata_fifo_axis_ready)
			first_trans_at_rdata <= # SIM_DELAY last_trans_at_rdata;
	end
	
	// 预启动的读突发次数
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			pre_launched_rd_burst_n <= 0;
		else if(burst_msg_fifo_wen ^ (burst_msg_fifo_ren & burst_msg_fifo_empty_n))
			pre_launched_rd_burst_n <= # SIM_DELAY burst_msg_fifo_wen ? (pre_launched_rd_burst_n + 1):(pre_launched_rd_burst_n - 1);
	end
	
	axis_data_fifo #(
		.is_async((M_AXIS_COMMON_CLOCK == "true") ? "false":"true"),
		.en_packet_mode("false"),
		.ram_type("bram"),
		.fifo_depth(512),
		.data_width(DATA_WIDTH),
		.user_width(2),
		.simulation_delay(SIM_DELAY)
	)rdata_fifo(
		.s_axis_aclk(m_axi_aclk),
		.s_axis_aresetn(m_axi_aresetn),
		.m_axis_aclk(m_axis_aclk),
		.m_axis_aresetn(m_axis_aresetn),
		
		.s_axis_data(s_rdata_fifo_axis_data),
		.s_axis_keep(s_rdata_fifo_axis_keep),
		.s_axis_strb({(DATA_WIDTH/8){1'bx}}),
		.s_axis_user(s_rdata_fifo_axis_user),
		.s_axis_last(s_rdata_fifo_axis_last),
		.s_axis_valid(s_rdata_fifo_axis_valid),
		.s_axis_ready(s_rdata_fifo_axis_ready),
		
		.m_axis_data(m_rdata_fifo_axis_data),
		.m_axis_keep(m_rdata_fifo_axis_keep),
		.m_axis_strb(),
		.m_axis_user(m_rdata_fifo_axis_user),
		.m_axis_last(m_rdata_fifo_axis_last),
		.m_axis_valid(m_rdata_fifo_axis_valid),
		.m_axis_ready(m_rdata_fifo_axis_ready)
	);
	
endmodule
