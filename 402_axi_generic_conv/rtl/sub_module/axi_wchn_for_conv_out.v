`timescale 1ns / 1ps
/********************************************************************
本模块: 用于输出卷积/BN/激活计算结果的AXI写通道

描述:
接受计算结果写请求, 将计算结果流存入输出特征图缓存区

32位地址64位数据的AXI写通道
支持非对齐传输
支持4KB边界保护

内部的AXI写数据buffer提高了AXI写突发的传输效率

可选的AXI写地址通道AXIS寄存器片

注意：
必须保证写请求基地址能被(feature_data_width/8)整除, 即写请求对齐到特征点位宽
必须保证写请求待写入的字节数能被(feature_data_width/8)整除, 即写入整数个特征点

协议:
AXIS SLAVE
AXI MASTER(WRITE ONLY)

作者: 陈家耀
日期: 2024/11/08
********************************************************************/


module axi_wchn_for_conv_out #(
	parameter integer feature_data_width = 16, // 特征点位宽(8 | 16 | 32 | 64)
	parameter integer max_wt_btt = 4 * 512, // 最大的写传输字节数(256 | 512 | 1024 | ...)
	parameter integer axi_wchn_max_burst_len = 32, // AXI写通道最大突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer axi_waddr_outstanding = 4, // AXI写地址缓冲深度(1 | 2 | 4)
	parameter integer axi_wdata_buffer_depth = 512, // AXI写数据buffer深度(512 | 1024 | ...)
	parameter en_4KB_boundary_protection = "true", // 是否使能4KB边界保护
	parameter en_axi_aw_reg_slice = "true", // 是否使能AXI写地址通道AXIS寄存器片
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 完成写请求(指示)
	output wire wt_req_fns,
	
	// 计算结果写请求
	input wire[63:0] s_axis_wt_req_data, // {待写入的字节数(32bit), 基地址(32bit)}
	input wire s_axis_wt_req_valid,
	output wire s_axis_wt_req_ready,
	
	// 计算结果流
	input wire[feature_data_width-1:0] s_axis_res_data,
	input wire s_axis_res_last, // 表示本次写请求最后1个数据
	input wire s_axis_res_valid,
	output wire s_axis_res_ready,
	
	// AXI主机(写通道)
	// AW
    output wire[31:0] m_axi_awaddr,
    output wire[1:0] m_axi_awburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_awlen,
    output wire[2:0] m_axi_awsize, // const -> 3'b011
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    // B
    input wire[1:0] m_axi_bresp, // ignored
    input wire m_axi_bvalid,
    output wire m_axi_bready, // const -> 1'b1
    // W
    output wire[63:0] m_axi_wdata,
    output wire[7:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready
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
	// 写地址信息更新状态独热码编号
	localparam integer STS_WAIT_ALLOW_AW_VLD = 0; // 状态: 等待允许写地址有效
	localparam integer STS_GEN_AW_LEN = 1; // 状态: 生成写突发长度
	localparam integer STS_UPD_AW_ADDR = 2; // 状态: 更新写地址并等待AW握手
	// 复用的最小值计算单元操作数1的位宽
	localparam integer MIN_CAL_OP1_WIDTH = (clogb2(max_wt_btt/8-1) > 8) ? (clogb2(max_wt_btt/8-1)+1):9;
	
	/** 处理写请求 **/
	wire wt_req_msg_fifo_allow_ready; // 写请求信息fifo允许接受写请求(标志)
	reg wt_req_ready; // 准备好接受写请求(标志)
	wire wt_req_done; // 写请求处理完成(指示)
	wire[clogb2(max_wt_btt):0] wt_btt; // 待写入的字节数
	wire[31:0] wt_baseaddr; // 写传输基地址
	wire[clogb2(max_wt_btt)+1:0] wt_req_termination_addr; // 写请求结束地址
	/*
	 起始地址[2:0]  编号        掩码
	     0         3'b000   8'b1111_1111
	     1         3'b001   8'b1111_1110
	     2         3'b010   8'b1111_1100
	     3         3'b011   8'b1111_1000
	     4         3'b100   8'b1111_0000
	     5         3'b101   8'b1110_0000
	     6         3'b110   8'b1100_0000
	     7         3'b111   8'b1000_0000
	*/
	wire[2:0] first_trans_keep_id; // 首次传输的字节有效掩码编号
	/*
	 结束地址[2:0]  编号        掩码
	     1         3'b000   8'b0000_0001
	     2         3'b001   8'b0000_0011
	     3         3'b010   8'b0000_0111
	     4         3'b011   8'b0000_1111
	     5         3'b100   8'b0001_1111
	     6         3'b101   8'b0011_1111
	     7         3'b110   8'b0111_1111
	     0         3'b111   8'b1111_1111
	*/
	wire[2:0] last_trans_keep_id; // 最后1次传输的字节有效掩码编号
	wire[clogb2(max_wt_btt/8-1):0] wt_trans_n; // 写传输个数 - 1
	
	// 握手条件: s_axis_wt_req_valid & wt_req_msg_fifo_allow_ready & wt_req_ready
	assign s_axis_wt_req_ready = wt_req_ready & wt_req_msg_fifo_allow_ready;
	
	assign {wt_btt, wt_baseaddr} = s_axis_wt_req_data[32+clogb2(max_wt_btt):0];
	assign wt_req_termination_addr = wt_btt + wt_baseaddr[2:0]; // 仅考虑基地址的非对齐部分, 对齐部分为0
	assign first_trans_keep_id = wt_baseaddr[2:0];
	assign last_trans_keep_id = wt_req_termination_addr[2:0] + 3'b111;
	// wt_req_termination_addr[clogb2(max_wt_btt)+1:3] + (wt_req_termination_addr[2:0] != 3'b000) - 1'b1
	assign wt_trans_n = wt_req_termination_addr[clogb2(max_wt_btt)+1:3] + 
		{(clogb2(max_wt_btt/8-1)+1){~(|wt_req_termination_addr[2:0])}};
	
	// 准备好接受写请求(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wt_req_ready <= 1'b1;
		else
			wt_req_ready <= # simulation_delay wt_req_ready ? 
				(~(s_axis_wt_req_valid & wt_req_msg_fifo_allow_ready)):wt_req_done;
	end
	
	/** 写地址通道AXIS寄存器片 **/
	// AXIS从机
	wire[31:0] s_axis_aw_data; // 写地址
	wire[7:0] s_axis_aw_user; // 写突发长度 - 1
	wire s_axis_aw_valid;
	wire s_axis_aw_ready;
	// AXIS主机
	wire[31:0] m_axis_aw_data; // 写地址
	wire[7:0] m_axis_aw_user; // 写突发长度 - 1
	wire m_axis_aw_valid;
	wire m_axis_aw_ready;
	
	assign m_axi_awaddr = m_axis_aw_data;
	assign m_axi_awburst = 2'b01;
	assign m_axi_awlen = m_axis_aw_user;
	assign m_axi_awsize = 3'b011;
	assign m_axi_awvalid = m_axis_aw_valid;
	assign m_axis_aw_ready = m_axi_awready;
	
	// 可选的AXI写地址通道AXIS寄存器片
	axis_reg_slice #(
		.data_width(32),
		.user_width(8),
		.forward_registered(en_axi_aw_reg_slice),
		.back_registered(en_axi_aw_reg_slice),
		.en_ready("true"),
		.simulation_delay(simulation_delay)
	)axi_aw_reg_slice(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axis_data(s_axis_aw_data),
		.s_axis_keep(4'bxxxx),
		.s_axis_user(s_axis_aw_user),
		.s_axis_last(1'bx),
		.s_axis_valid(s_axis_aw_valid),
		.s_axis_ready(s_axis_aw_ready),
		
		.m_axis_data(m_axis_aw_data),
		.m_axis_keep(),
		.m_axis_user(m_axis_aw_user),
		.m_axis_last(),
		.m_axis_valid(m_axis_aw_valid),
		.m_axis_ready(m_axis_aw_ready)
	);
	
	/** 写地址信息表 **/
	// 信息表寄存器区
	reg[39:0] aw_tb_content[0:axi_waddr_outstanding-1]; // 表内容({写突发长度 - 1(8bit), 写地址(32bit)})
	reg[1:0] aw_tb_flag[0:axi_waddr_outstanding-1]; // 表项生命周期标志({写突发的数据已准备好(1bit), 写突发已预启动(1bit)})
	// 信息表写端口(预启动写突发)
	reg[clogb2(axi_waddr_outstanding-1):0] pre_launch_wt_burst_wptr; // 写指针
	wire pre_launch_wt_burst_committing_wen; // 预启动新的写突发(表项更新使能)
	wire pre_launch_wt_burst_allowed_full_n; // 允许预启动写突发(标志)
	wire[39:0] wt_burst_msg_din; // 待存入的写突发信息({写突发长度 - 1(8bit), 写地址(32bit)})
	// 信息表读端口(准备好写突发的数据)
	reg[clogb2(axi_waddr_outstanding-1):0] prepare_wdata_rptr; // 读指针
	wire wdata_prepared_ren; // 准备好写突发的数据(表项更新使能)
	wire wt_burst_msg_available_empty_n; // 写突发信息可用(标志)
	wire[7:0] wt_burst_msg_dout; // 写突发信息({写突发长度 - 1(8bit)})
	// 信息表读端口(派发写地址)
	reg[clogb2(axi_waddr_outstanding-1):0] dispatch_waddr_rptr; // 读指针
	wire waddr_dispatched_ren; // 派发写地址(表项更新使能)
	wire dispatch_waddr_allowed_empty_n; // 允许派发写地址(标志)
	wire[39:0] waddr_dispatch_msg_dout; // 写地址派发信息({写突发长度 - 1(8bit), 写地址(32bit)})
	
	assign s_axis_aw_data = waddr_dispatch_msg_dout[31:0];
	assign s_axis_aw_user = waddr_dispatch_msg_dout[39:32];
	assign s_axis_aw_valid = dispatch_waddr_allowed_empty_n;
	assign waddr_dispatched_ren = s_axis_aw_ready;
	
	assign pre_launch_wt_burst_allowed_full_n = aw_tb_flag[pre_launch_wt_burst_wptr] == 2'b00;
	assign wt_burst_msg_available_empty_n = aw_tb_flag[prepare_wdata_rptr] == 2'b01;
	assign dispatch_waddr_allowed_empty_n = aw_tb_flag[dispatch_waddr_rptr] == 2'b11;
	
	assign wt_burst_msg_dout = aw_tb_content[prepare_wdata_rptr][39:32];
	assign waddr_dispatch_msg_dout = aw_tb_content[dispatch_waddr_rptr];
	
	// 表内容/表项生命周期标志寄存器区
	genvar aw_tb_i;
	generate
		for(aw_tb_i = 0;aw_tb_i < axi_waddr_outstanding;aw_tb_i = aw_tb_i + 1)
		begin
			// 表内容
			always @(posedge clk)
			begin
				if(pre_launch_wt_burst_committing_wen & pre_launch_wt_burst_allowed_full_n & 
					(pre_launch_wt_burst_wptr == aw_tb_i))
					aw_tb_content[aw_tb_i] <= # simulation_delay wt_burst_msg_din;
			end
			
			// 表项生命周期标志(写突发已预启动)
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					aw_tb_flag[aw_tb_i][0] <= 1'b0;
				else if((pre_launch_wt_burst_committing_wen & (aw_tb_flag[aw_tb_i] == 2'b00) & 
					(pre_launch_wt_burst_wptr == aw_tb_i)) | 
					(waddr_dispatched_ren & (aw_tb_flag[aw_tb_i] == 2'b11) & (dispatch_waddr_rptr == aw_tb_i)))
					aw_tb_flag[aw_tb_i][0] <= # simulation_delay aw_tb_flag[aw_tb_i] == 2'b00;
			end
			// 表项生命周期标志(写突发的数据已准备好)
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					aw_tb_flag[aw_tb_i][1] <= 1'b0;
				else if((wdata_prepared_ren & (aw_tb_flag[aw_tb_i] == 2'b01) & (prepare_wdata_rptr == aw_tb_i)) | 
					(waddr_dispatched_ren & (aw_tb_flag[aw_tb_i] == 2'b11) & (dispatch_waddr_rptr == aw_tb_i)))
					aw_tb_flag[aw_tb_i][1] <= # simulation_delay aw_tb_flag[aw_tb_i] == 2'b01;
			end
		end
	endgenerate
	
	// 信息表写指针(预启动写突发)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			pre_launch_wt_burst_wptr <= 0;
		else if(pre_launch_wt_burst_committing_wen & pre_launch_wt_burst_allowed_full_n)
			pre_launch_wt_burst_wptr <= # simulation_delay 
				// (pre_launch_wt_burst_wptr == (axi_waddr_outstanding-1)) ? 0:(pre_launch_wt_burst_wptr + 1)
				{(clogb2(axi_waddr_outstanding-1)+1){pre_launch_wt_burst_wptr != (axi_waddr_outstanding-1)}} & 
				(pre_launch_wt_burst_wptr + 1);
	end
	// 信息表读指针(准备好写突发的数据)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			prepare_wdata_rptr <= 0;
		else if(wdata_prepared_ren & wt_burst_msg_available_empty_n)
			prepare_wdata_rptr <= # simulation_delay 
				// (prepare_wdata_rptr == (axi_waddr_outstanding-1)) ? 0:(prepare_wdata_rptr + 1)
				{(clogb2(axi_waddr_outstanding-1)+1){prepare_wdata_rptr != (axi_waddr_outstanding-1)}} & 
				(prepare_wdata_rptr + 1);
	end
	// 信息表读指针(派发写地址)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			dispatch_waddr_rptr <= 0;
		else if(waddr_dispatched_ren & dispatch_waddr_allowed_empty_n)
			dispatch_waddr_rptr <= # simulation_delay 
				// (dispatch_waddr_rptr == (axi_waddr_outstanding-1)) ? 0:(dispatch_waddr_rptr + 1)
				{(clogb2(axi_waddr_outstanding-1)+1){dispatch_waddr_rptr != (axi_waddr_outstanding-1)}} & 
				(dispatch_waddr_rptr + 1);
	end
	
	/** 生成写地址 **/
	wire outstanding_stat_allow_aw_vld; // 滞外传输统计允许AXI写地址有效(标志)
	wire to_allow_aw_vld; // 允许AXI写地址有效(标志)
	reg[2:0] aw_msg_upd_sts; // 写地址信息更新状态(3'b001 -> 等待允许写地址有效, 
	                         //                    3'b010 -> 生成写突发长度, 3'b100 -> 更新写地址并等待AW握手)
	reg[31:0] aw_addr; // 当前的写地址
	wire[7:0] aw_len; // 写突发长度 - 1
	reg[8:0] trans_n_remaining_in_4kB; // 当前4KB区间剩余传输数 - 1
	reg[clogb2(max_wt_btt/8-1):0] trans_n_remaining; // 剩余传输数 - 1
	reg last_wt_burst; // 最后1个写突发(标志)
	/*
	复用的最小值计算单元 -> 
	
	使能4KB边界保护: 
					   cycle#0                 cycle#1
		op1    trans_n_remaining_in_4kB    trans_n_remaining
		
		op2   axi_wchn_max_burst_len - 1      前置最小值
	
	不使能4KB边界保护: 
					   cycle#0                       cycle#1
		op1       trans_n_remaining            trans_n_remaining
		
		op2   axi_wchn_max_burst_len - 1   axi_wchn_max_burst_len - 1
	*/
	wire[MIN_CAL_OP1_WIDTH-1:0] min_cal_op1;
	wire[7:0] min_cal_op2;
	wire min_cal_op1_leq_op2;
	reg[7:0] min_cal_res;
	
	assign wt_burst_msg_din[31:0] = aw_addr;
	assign wt_burst_msg_din[39:32] = aw_len;
	assign pre_launch_wt_burst_committing_wen = aw_msg_upd_sts[STS_UPD_AW_ADDR];
	
	assign wt_req_done = pre_launch_wt_burst_committing_wen & pre_launch_wt_burst_allowed_full_n & last_wt_burst;
	
	assign to_allow_aw_vld = outstanding_stat_allow_aw_vld & (~wt_req_ready);
	
	assign aw_len = min_cal_res;
	
	assign min_cal_op1 = 
		(aw_msg_upd_sts[STS_WAIT_ALLOW_AW_VLD] & (en_4KB_boundary_protection == "true")) ? 
			trans_n_remaining_in_4kB:trans_n_remaining;
	assign min_cal_op2 = 
		(aw_msg_upd_sts[STS_WAIT_ALLOW_AW_VLD] | (en_4KB_boundary_protection == "false")) ? 
			(axi_wchn_max_burst_len - 1):min_cal_res;
	assign min_cal_op1_leq_op2 = min_cal_op1 <= min_cal_op2;
	
	// 写地址信息更新状态
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			aw_msg_upd_sts <= 3'b001;
		else if((aw_msg_upd_sts[STS_WAIT_ALLOW_AW_VLD] & to_allow_aw_vld) | 
			aw_msg_upd_sts[STS_GEN_AW_LEN] | 
			(aw_msg_upd_sts[STS_UPD_AW_ADDR] & pre_launch_wt_burst_allowed_full_n))
			aw_msg_upd_sts <= # simulation_delay {aw_msg_upd_sts[1:0], aw_msg_upd_sts[2]};
	end
	
	// 当前的写地址
	always @(posedge clk)
	begin
		if((s_axis_wt_req_valid & s_axis_wt_req_ready) | 
			(pre_launch_wt_burst_committing_wen & pre_launch_wt_burst_allowed_full_n))
			aw_addr <= # simulation_delay 
				(s_axis_wt_req_valid & s_axis_wt_req_ready) ? {wt_baseaddr[31:3], 3'b000}: // 载入基地址
				                                              {aw_addr[31:3] + aw_len + 1'b1, 3'b000}; // 递增写地址
	end
	
	// 当前4KB区间剩余传输数 - 1
	always @(posedge clk)
	begin
		if((s_axis_wt_req_valid & s_axis_wt_req_ready) | 
			(pre_launch_wt_burst_committing_wen & pre_launch_wt_burst_allowed_full_n))
			// (s_axis_wt_req_valid & s_axis_wt_req_ready) ? 
			//     (9'd511 - wt_baseaddr[11:3]):(trans_n_remaining_in_4kB - aw_len - 1'b1)
			trans_n_remaining_in_4kB <= # simulation_delay (s_axis_wt_req_valid & s_axis_wt_req_ready) ? 
				(~wt_baseaddr[11:3]):(trans_n_remaining_in_4kB + {1'b1, ~aw_len});
	end
	
	// 剩余传输数 - 1
	always @(posedge clk)
	begin
		if((s_axis_wt_req_valid & s_axis_wt_req_ready) | 
			(pre_launch_wt_burst_committing_wen & pre_launch_wt_burst_allowed_full_n))
			// (s_axis_wt_req_valid & s_axis_wt_req_ready) ? 
			//     wt_trans_n:(trans_n_remaining - aw_len - 1'b1)
			trans_n_remaining <= # simulation_delay (s_axis_wt_req_valid & s_axis_wt_req_ready) ? 
				wt_trans_n:(trans_n_remaining + {24'hff_ff_ff, ~aw_len});
	end
	
	// 最后1个写突发(标志)
	always @(posedge clk)
	begin
		if(aw_msg_upd_sts[STS_GEN_AW_LEN])
			last_wt_burst <= # simulation_delay min_cal_op1_leq_op2;
	end
	
	// 复用的最小值计算单元(结果寄存器)
	always @(posedge clk)
	begin
		if(((en_4KB_boundary_protection == "true") & aw_msg_upd_sts[STS_WAIT_ALLOW_AW_VLD] & to_allow_aw_vld) | 
			aw_msg_upd_sts[STS_GEN_AW_LEN])
			min_cal_res <= # simulation_delay min_cal_op1_leq_op2 ? min_cal_op1[7:0]:min_cal_op2;
	end
	
	/** AXI滞外写传输统计 **/
	wire launch_new_wt_burst; // 预启动新的写突发(指示)
	wire wt_burst_finish; // 写突发完成(指示)
	reg[clogb2(axi_waddr_outstanding):0] outstanding_wt_burst_n; // 滞外的写突发个数
	reg outstanding_wt_burst_full_n; // 滞外的写突发统计已满
	reg outstanding_msg_fifo[0:axi_waddr_outstanding-1]; // 滞外写传输信息fifo寄存器组({是否本次写请求的最后1个突发})
	reg[clogb2(axi_waddr_outstanding-1):0] outstanding_msg_fifo_wptr; // 滞外写传输信息fifo写指针
	reg[clogb2(axi_waddr_outstanding-1):0] outstanding_msg_fifo_rptr; // 滞外写传输信息fifo读指针
	
	assign wt_req_fns = outstanding_msg_fifo[outstanding_msg_fifo_rptr] & wt_burst_finish;
	
	assign m_axi_bready = 1'b1;
	
	assign outstanding_stat_allow_aw_vld = outstanding_wt_burst_full_n;
	
	assign launch_new_wt_burst = pre_launch_wt_burst_committing_wen & pre_launch_wt_burst_allowed_full_n;
	assign wt_burst_finish = m_axi_bvalid;
	
	// 滞外的写突发个数
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			outstanding_wt_burst_n <= 0;
		else if(launch_new_wt_burst ^ wt_burst_finish)
			outstanding_wt_burst_n <= # simulation_delay wt_burst_finish ? 
				(outstanding_wt_burst_n - 1):(outstanding_wt_burst_n + 1);
	end
	
	// 滞外的写突发统计已满
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			outstanding_wt_burst_full_n <= 1'b1;
		else if(launch_new_wt_burst ^ wt_burst_finish)
			// wt_burst_finish ? 1'b1:(outstanding_wt_burst_n != (axi_waddr_outstanding - 1))
			outstanding_wt_burst_full_n <= # simulation_delay 
				wt_burst_finish | (outstanding_wt_burst_n != (axi_waddr_outstanding - 1));
	end
	
	// 滞外写传输信息fifo寄存器组
	genvar outstanding_msg_fifo_i;
	generate
		for(outstanding_msg_fifo_i = 0;outstanding_msg_fifo_i < axi_waddr_outstanding;
			outstanding_msg_fifo_i = outstanding_msg_fifo_i + 1)
		begin
			always @(posedge clk)
			begin
				if(launch_new_wt_burst & (outstanding_msg_fifo_wptr == outstanding_msg_fifo_i))
					outstanding_msg_fifo[outstanding_msg_fifo_i] <= # simulation_delay last_wt_burst;
			end
		end
	endgenerate
	
	// 滞外写传输信息fifo写指针
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			outstanding_msg_fifo_wptr <= 0;
		else if(launch_new_wt_burst)
			outstanding_msg_fifo_wptr <= # simulation_delay 
				// (outstanding_msg_fifo_wptr == (axi_waddr_outstanding-1)) ? 0:(outstanding_msg_fifo_wptr + 1)
				{(clogb2(axi_waddr_outstanding-1)+1){outstanding_msg_fifo_wptr != (axi_waddr_outstanding-1)}} & 
				(outstanding_msg_fifo_wptr + 1);
	end
	
	// 滞外写传输信息fifo读指针
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			outstanding_msg_fifo_rptr <= 0;
		else if(wt_burst_finish)
			outstanding_msg_fifo_rptr <= # simulation_delay 
				// (outstanding_msg_fifo_rptr == (axi_waddr_outstanding-1)) ? 0:(outstanding_msg_fifo_rptr + 1)
				{(clogb2(axi_waddr_outstanding-1)+1){outstanding_msg_fifo_rptr != (axi_waddr_outstanding-1)}} & 
				(outstanding_msg_fifo_rptr + 1);
	end
	
	/** 写请求信息fifo **/
	// fifo写端口
	wire wt_req_msg_fifo_wen;
	wire[5:0] wt_req_msg_fifo_din; // {首次传输的字节有效掩码编号(3bit), 最后1次传输的字节有效掩码编号(3bit)}
	wire wt_req_msg_fifo_full_n;
	// fifo读端口
	wire wt_req_msg_fifo_ren;
	wire[5:0] wt_req_msg_fifo_dout; // {首次传输的字节有效掩码编号(3bit), 最后1次传输的字节有效掩码编号(3bit)}
	wire wt_req_msg_fifo_empty_n;
	
	assign wt_req_msg_fifo_allow_ready = wt_req_msg_fifo_full_n;
	
	// 握手条件: s_axis_wt_req_valid & wt_req_ready & wt_req_msg_fifo_full_n
	assign wt_req_msg_fifo_wen = s_axis_wt_req_valid & wt_req_ready;
	assign wt_req_msg_fifo_din = {first_trans_keep_id, last_trans_keep_id};
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.fifo_depth(3),
		.fifo_data_width(6),
		.almost_full_th(),
		.almost_empty_th(),
		.simulation_delay(simulation_delay)
	)wt_req_msg_fifo(
		.clk(clk),
		.rst_n(rst_n),
		
		.fifo_wen(wt_req_msg_fifo_wen),
		.fifo_din(wt_req_msg_fifo_din),
		.fifo_full_n(wt_req_msg_fifo_full_n),
		
		.fifo_ren(wt_req_msg_fifo_ren),
		.fifo_dout(wt_req_msg_fifo_dout),
		.fifo_empty_n(wt_req_msg_fifo_empty_n)
	);
	
	/** AXI写数据buffer **/
	// 特征点收集
	reg first_feature; // 第1个特征点(标志)
	wire last_feature; // 最后1个特征点(标志)
	reg[feature_data_width-1:0] feature_set[0:64/feature_data_width-1]; // 特征点集合
	wire on_load_feature; // 特征点装载(指示)
	wire[64/feature_data_width-1:0] feature_upd_vec_first; // 写请求首个特征点更新使能向量
	wire[64/feature_data_width-1:0] trm_last_ft_id; // 最后1次传输的最后1个有效特征点编号(独热码)
	wire[64/feature_data_width-1:0] feature_upd_vec_cur; // 当前特征点更新使能向量
	wire[64/feature_data_width-1:0] feature_upd_vec_nxt; // 下一特征点更新使能向量
	reg[64/feature_data_width-1:0] feature_upd_vec_regs; // 特征点更新使能寄存器向量
	wire feature_upd_vec_match_trm_last_ft_id; // 当前特征点更新使能向量 <-> 最后1次传输的最后1个有效特征点编号(匹配标志)
	// 写数据生成
	reg first_trans; // 第1个传输(标志)
	wire loading_last_of_feature_set; // 加载特征点集合的最后1点(标志)
	reg[7:0] wt_burst_data_id; // 写突发传输编号(计数器)
	wire wt_burst_last_trans; // 本次写突发最后1次传输(标志)
	wire[7:0] wdata_gen_keep_s0; // 写数据生成第0级keep
	wire wdata_gen_last_s0; // 写数据生成第0级last
	wire wdata_gen_valid_s0; // 写数据生成第0级valid
	wire wdata_gen_ready_s0; // 写数据生成第0级ready
	reg[7:0] wdata_gen_keep_s1; // 写数据生成第1级keep
	reg wdata_gen_last_s1; // 写数据生成第1级last
	reg wdata_gen_valid_s1; // 写数据生成第1级valid
	wire wdata_gen_ready_s1; // 写数据生成第1级ready
	// keep信号生成
	wire[2:0] wdata_first_kid; // 写请求第1个数据的字节使能掩码编号
	wire[2:0] wdata_last_kid; // 写请求最后1个数据的字节使能掩码编号
	wire[7:0] wdata_first_keep; // 写请求第1个数据的keep信号
	wire[7:0] wdata_last_keep; // 写请求最后1个数据的keep信号
	// 写数据缓存fifo写端口
	wire wdata_buf_fifo_wen;
	wire[63:0] wdata_buf_fifo_din;
	wire[64/feature_data_width-1:0] wdata_buf_fifo_din_keep;
	wire wdata_buf_fifo_din_last;
	wire wdata_buf_fifo_full_n;
	// 写数据缓存fifo读端口
	wire wdata_buf_fifo_ren;
	wire[63:0] wdata_buf_fifo_dout;
	wire[64/feature_data_width-1:0] wdata_buf_fifo_dout_keep;
	wire wdata_buf_fifo_dout_last;
	wire wdata_buf_fifo_empty_n;
	
	// 握手条件: s_axis_res_valid & wt_req_msg_fifo_empty_n & wt_burst_msg_available_empty_n & 
	//     (loading_last_of_feature_set ? wdata_gen_ready_s0:1'b1)
	assign s_axis_res_ready = wt_req_msg_fifo_empty_n & wt_burst_msg_available_empty_n & 
		((~loading_last_of_feature_set) | wdata_gen_ready_s0);
	
	assign m_axi_wdata = wdata_buf_fifo_dout;
	assign m_axi_wstrb = 
		(feature_data_width == 8) ?  wdata_buf_fifo_dout_keep:
		(feature_data_width == 16) ? {{2{wdata_buf_fifo_dout_keep[3]}}, {2{wdata_buf_fifo_dout_keep[2]}}, 
									     {2{wdata_buf_fifo_dout_keep[1]}}, {2{wdata_buf_fifo_dout_keep[0]}}}:
		(feature_data_width == 32) ? {{4{wdata_buf_fifo_dout_keep[1]}}, {4{wdata_buf_fifo_dout_keep[0]}}}:
		                             8'hff;
	assign m_axi_wlast = wdata_buf_fifo_dout_last;
	assign m_axi_wvalid = wdata_buf_fifo_empty_n;
	assign wdata_buf_fifo_ren = m_axi_wready;
	
	// 握手条件: s_axis_res_valid & wt_req_msg_fifo_empty_n & wt_burst_msg_available_empty_n & 
	//     wdata_gen_ready_s0 & s_axis_res_last
	// 断言: 接收写请求最后1个数据时必定加载特征点集合的最后1点!
	assign wt_req_msg_fifo_ren = s_axis_res_valid & wt_burst_msg_available_empty_n & 
		wdata_gen_ready_s0 & s_axis_res_last;
	// 握手条件: s_axis_res_valid & wt_req_msg_fifo_empty_n & wt_burst_msg_available_empty_n & 
	//     loading_last_of_feature_set & wdata_gen_ready_s0 & wt_burst_last_trans
	assign wdata_prepared_ren = s_axis_res_valid & loading_last_of_feature_set & 
		wt_req_msg_fifo_empty_n & wdata_gen_ready_s0 & wt_burst_last_trans;
	
	assign last_feature = s_axis_res_last;
	assign on_load_feature = s_axis_res_valid & s_axis_res_ready;
	
	genvar feature_upd_vec_first_trm_i;
	generate
		for(feature_upd_vec_first_trm_i = 0;feature_upd_vec_first_trm_i < 64/feature_data_width;
			feature_upd_vec_first_trm_i = feature_upd_vec_first_trm_i + 1)
		begin
			assign feature_upd_vec_first[feature_upd_vec_first_trm_i] = 
				(feature_data_width == 64) | 
				(wt_req_msg_fifo_dout[5:5-clogb2(64/feature_data_width-1)] == feature_upd_vec_first_trm_i);
			assign trm_last_ft_id[feature_upd_vec_first_trm_i] = 
				(feature_data_width == 64) | 
				(wt_req_msg_fifo_dout[2:2-clogb2(64/feature_data_width-1)] == feature_upd_vec_first_trm_i);
		end
	endgenerate
	
	assign feature_upd_vec_cur = first_feature ? feature_upd_vec_first:feature_upd_vec_regs;
	
	generate
		if(feature_data_width < 64)
		begin
			assign feature_upd_vec_nxt = 
				{feature_upd_vec_cur[64/feature_data_width-2:0], feature_upd_vec_cur[64/feature_data_width-1]};
			assign feature_upd_vec_match_trm_last_ft_id = |(feature_upd_vec_cur & trm_last_ft_id);
		end
		else
		begin
			assign feature_upd_vec_nxt = 1'b1;
			assign feature_upd_vec_match_trm_last_ft_id = 1'b1;
		end
	endgenerate
	
	assign loading_last_of_feature_set = feature_upd_vec_cur[64/feature_data_width-1] | 
		(last_feature & feature_upd_vec_match_trm_last_ft_id);
	assign wt_burst_last_trans = wt_burst_data_id == wt_burst_msg_dout;
	/*
	({first_trans, last_feature} == 2'b00) ? 8'b1111_1111:
	({first_trans, last_feature} == 2'b01) ? wdata_last_keep:
	({first_trans, last_feature} == 2'b10) ? wdata_first_keep:
														 (wdata_first_keep & wdata_last_keep)
	*/
	assign wdata_gen_keep_s0 = 
		({8{~first_trans}} | wdata_first_keep) & 
		({8{~last_feature}} | wdata_last_keep);
	assign wdata_gen_last_s0 = wt_burst_last_trans;
	// 握手条件: s_axis_res_valid & wt_req_msg_fifo_empty_n & wt_burst_msg_available_empty_n & 
	//     loading_last_of_feature_set & wdata_gen_ready_s0
	assign wdata_gen_valid_s0 = s_axis_res_valid & loading_last_of_feature_set & 
		wt_req_msg_fifo_empty_n & wt_burst_msg_available_empty_n;
	assign wdata_gen_ready_s0 = (~wdata_gen_valid_s1) | wdata_gen_ready_s1;
	assign wdata_gen_ready_s1 = wdata_buf_fifo_full_n;
	
	assign wdata_first_kid = 
		(feature_data_width == 8)  ? wt_req_msg_fifo_dout[5:3]:
		(feature_data_width == 16) ? {wt_req_msg_fifo_dout[5:4], 1'b0}:
		(feature_data_width == 32) ? {wt_req_msg_fifo_dout[5], 2'b00}:
		                             3'b000;
	assign wdata_last_kid = 
		(feature_data_width == 8)  ? wt_req_msg_fifo_dout[2:0]:
		(feature_data_width == 16) ? {wt_req_msg_fifo_dout[2:1], 1'b1}:
		(feature_data_width == 32) ? {wt_req_msg_fifo_dout[2], 2'b11}:
		                             3'b111;
	assign wdata_first_keep = {
		1'b1, wdata_first_kid <= 3'd6,
		wdata_first_kid <= 3'd5, wdata_first_kid <= 3'd4,
		wdata_first_kid <= 3'd3, wdata_first_kid <= 3'd2,
		wdata_first_kid <= 3'd1, wdata_first_kid == 3'd0};
	assign wdata_last_keep = {
		wdata_last_kid == 3'd7, wdata_last_kid >= 3'd6,
		wdata_last_kid >= 3'd5, wdata_last_kid >= 3'd4,
		wdata_last_kid >= 3'd3, wdata_last_kid >= 3'd2,
		wdata_last_kid >= 3'd1, 1'b1};
	
	assign wdata_buf_fifo_wen = wdata_gen_valid_s1;
	assign wdata_buf_fifo_din = 
		(feature_data_width == 8) ?  {feature_set[7], feature_set[6], feature_set[5], feature_set[4], 
			                             feature_set[3], feature_set[2], feature_set[1], feature_set[0]}:
		(feature_data_width == 16) ? {feature_set[3], feature_set[2], feature_set[1], feature_set[0]}:
		(feature_data_width == 32) ? {feature_set[1], feature_set[0]}:
									 feature_set[0];
	
	
	assign wdata_buf_fifo_din_keep = 
		(feature_data_width == 8) ?  wdata_gen_keep_s1:
		(feature_data_width == 16) ? {wdata_gen_keep_s1[6], wdata_gen_keep_s1[4], wdata_gen_keep_s1[2], wdata_gen_keep_s1[0]}:
		(feature_data_width == 32) ? {wdata_gen_keep_s1[4], wdata_gen_keep_s1[0]}:
		                             1'b1;
	assign wdata_buf_fifo_din_last = wdata_gen_last_s1;
	
	// 第1个特征点(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			first_feature <= 1'b1;
		else if(on_load_feature)
			first_feature <= # simulation_delay last_feature;
	end
	
	// 特征点集合
	genvar feature_set_i;
	generate
		for(feature_set_i = 0;feature_set_i < 64/feature_data_width;feature_set_i = feature_set_i + 1)
		begin
			always @(posedge clk)
			begin
				if(on_load_feature & feature_upd_vec_cur[feature_set_i])
					feature_set[feature_set_i] <= # simulation_delay s_axis_res_data;
			end
		end
	endgenerate
	
	// 特征点更新使能寄存器向量
	always @(posedge clk)
	begin
		if(on_load_feature)
			feature_upd_vec_regs <= # simulation_delay feature_upd_vec_nxt;
	end
	
	// 第1个传输(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			first_trans <= 1'b1;
		else if(wdata_gen_valid_s0 & wdata_gen_ready_s0)
			first_trans <= # simulation_delay last_feature;
	end
	
	// 写突发传输编号(计数器)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wt_burst_data_id <= 8'd0;
		else if(wdata_gen_valid_s0 & wdata_gen_ready_s0)
			// wt_burst_last_trans ? 8'd0:(wt_burst_data_id + 8'd1)
			wt_burst_data_id <= # simulation_delay {8{~wt_burst_last_trans}} & (wt_burst_data_id + 8'd1);
	end
	
	// 写数据生成第1级keep
	always @(posedge clk)
	begin
		if(wdata_gen_valid_s0 & wdata_gen_ready_s0)
			wdata_gen_keep_s1 <= # simulation_delay wdata_gen_keep_s0;
	end
	
	// 写数据生成第1级last
	always @(posedge clk)
	begin
		if(wdata_gen_valid_s0 & wdata_gen_ready_s0)
			wdata_gen_last_s1 <= # simulation_delay wdata_gen_last_s0;
	end
	
	// 写数据生成第1级valid
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wdata_gen_valid_s1 <= 1'b0;
		else if(wdata_gen_ready_s0)
			wdata_gen_valid_s1 <= # simulation_delay wdata_gen_valid_s0;
	end
	
	// AXI写数据buffer
	ram_fifo_wrapper #(
		.fwft_mode("true"),
		.ram_type("bram"),
		.en_bram_reg("false"),
		.fifo_depth(axi_wdata_buffer_depth),
		.fifo_data_width(64 + 64 / feature_data_width + 1),
		.full_assert_polarity("low"),
		.empty_assert_polarity("low"),
		.almost_full_assert_polarity("no"),
		.almost_empty_assert_polarity("no"),
		.en_data_cnt("false"),
		.almost_full_th(),
		.almost_empty_th(),
		.simulation_delay(simulation_delay)
	)wdata_buf_fifo(
		.clk(clk),
		.rst_n(rst_n),
		
		.fifo_wen(wdata_buf_fifo_wen),
		.fifo_din({wdata_buf_fifo_din, wdata_buf_fifo_din_keep, wdata_buf_fifo_din_last}),
		.fifo_full_n(wdata_buf_fifo_full_n),
		
		.fifo_ren(wdata_buf_fifo_ren),
		.fifo_dout({wdata_buf_fifo_dout, wdata_buf_fifo_dout_keep, wdata_buf_fifo_dout_last}),
		.fifo_empty_n(wdata_buf_fifo_empty_n)
	);
	
endmodule
