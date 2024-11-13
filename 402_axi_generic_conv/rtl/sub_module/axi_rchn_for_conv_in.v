`timescale 1ns / 1ps
/********************************************************************
本模块: 用于获取输入特征图/卷积核/线性参数的AXI读通道

描述:
接受输入特征图/卷积核/线性参数读请求, 通过AXI读通道访问特征图/卷积核/线性参数缓存区,
	给出输入特征图/卷积核/线性参数数据流

32位地址64位数据的AXI读通道
支持非对齐传输
支持4KB边界保护

可选的AXI读数据buffer

可选的AXI读地址通道AXIS寄存器片
可选的读数据AXIS寄存器片

注意：
AXI读地址缓冲深度(axi_raddr_outstanding)和AXI读数据buffer深度(axi_rdata_buffer_depth)共同决定AR通道的握手

协议:
AXIS MASTER/SLAVE
AXI MASTER(READ ONLY)

作者: 陈家耀
日期: 2024/10/15
********************************************************************/


module axi_rchn_for_conv_in #(
	parameter integer max_rd_btt = 4 * 512, // 最大的读传输字节数(256 | 512 | 1024 | ...)
	parameter integer axi_rchn_max_burst_len = 32, // AXI读通道最大突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer axi_raddr_outstanding = 4, // AXI读地址缓冲深度(1 | 2 | 4)
	parameter integer axi_rdata_buffer_depth = 512, // AXI读数据buffer深度(0 -> 不启用 | 512 | 1024 | ...)
	parameter en_axi_ar_reg_slice = "true", // 是否使能AXI读地址通道AXIS寄存器片
	parameter en_rdata_reg_slice = "true", // 是否使能读数据AXIS寄存器片
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 输入特征图/卷积核/线性参数读请求
	input wire[63:0] s_axis_rd_req_data, // {待读取的字节数(32bit), 基地址(32bit)}
	input wire s_axis_rd_req_valid,
	output wire s_axis_rd_req_ready,
	
	// 输入特征图/卷积核/线性参数数据流
	output wire[63:0] m_axis_ft_par_data,
	output wire[7:0] m_axis_ft_par_keep,
	output wire m_axis_ft_par_last,
	output wire m_axis_ft_par_valid,
	input wire m_axis_ft_par_ready,
	
	// AXI主机(读通道)
	// AR
    output wire[31:0] m_axi_araddr,
    output wire[1:0] m_axi_arburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_arlen,
    output wire[2:0] m_axi_arsize, // const -> 3'b011
    output wire m_axi_arvalid,
    input wire m_axi_arready,
    // R
    input wire[63:0] m_axi_rdata,
    input wire[1:0] m_axi_rresp, // ignored
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output wire m_axi_rready
);
    
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
        for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
			bit_depth = bit_depth >> 1;
    end
    endfunction
	
	// 计算数据中1的个数
    function integer count1_of_integer(input integer data, input integer data_width);
        integer i;
    begin
        count1_of_integer = 0;
        
        for(i = 0;i < data_width;i = i + 1)
			count1_of_integer = count1_of_integer + data[i];
    end
	endfunction
	
	/** 常量 **/
	localparam integer max_rdata_buffer_store_burst_n = (axi_rdata_buffer_depth == 0) ? 
		(1024 / axi_rchn_max_burst_len):(axi_rdata_buffer_depth / axi_rchn_max_burst_len); // 读数据buffer预存的最大突发个数
	
	/** 处理读请求 **/
	reg rd_req_ready; // 准备好接受读请求(标志)
	wire rd_req_done; // 读请求处理完成(指示)
	wire[clogb2(max_rd_btt):0] rd_btt; // 待读取的字节数
	wire[31:0] rd_baseaddr; // 读传输基地址
	wire[clogb2(max_rd_btt)+1:0] rd_req_termination_addr; // 读请求结束地址
	reg[2:0] first_trans_keep_id; // 首次传输的字节有效掩码(编号)
	reg[2:0] last_trans_keep_id; // 最后1次传输的字节有效掩码(编号)
	
	assign s_axis_rd_req_ready = rd_req_ready;
	
	assign {rd_btt, rd_baseaddr} = s_axis_rd_req_data[32 + clogb2(max_rd_btt):0];
	
	assign rd_req_termination_addr = rd_btt + rd_baseaddr[2:0]; // 仅考虑基地址的非对齐部分, 对齐部分为0
	
	// 准备好接受读请求(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rd_req_ready <= 1'b1;
		else
			rd_req_ready <= # simulation_delay rd_req_ready ? (~s_axis_rd_req_valid):rd_req_done;
	end
	
	// 首次传输的字节有效掩码(编号)
	always @(posedge clk)
	begin
		if(s_axis_rd_req_valid & s_axis_rd_req_ready)
			first_trans_keep_id <= # simulation_delay rd_baseaddr[2:0];
	end
	// 最后1次传输的字节有效掩码(编号)
	always @(posedge clk)
	begin
		if(s_axis_rd_req_valid & s_axis_rd_req_ready)
			last_trans_keep_id <= # simulation_delay rd_req_termination_addr[2:0] - 3'b001;
	end
	
	/** AXI读地址通道 **/
	wire raddr_outstanding_allow_arvalid; // 读地址outstanding允许读地址有效(标志)
	wire rdata_buffer_allow_arvalid; // 读数据buffer允许读地址有效(标志)
	reg first_burst; // 第1次突发(标志)
	wire last_burst; // 最后1次突发(标志)
	reg[31:0] now_ar; // 当前读地址
	reg[clogb2(max_rd_btt/8):0] trans_n_remaining; // 剩余传输数
	reg[8:0] trans_n_remaining_in_4kB_sub1; // 当前4KB区间剩余传输数 - 1
	wire[9:0] trans_n_remaining_in_4kB; // 当前4KB区间剩余传输数
	wire[8:0] min_trans_n_remaining_max_burst_len; // min(剩余传输数, AXI读通道最大突发长度)
	wire[8:0] min_trans_n_remaining_in_4kB_max_burst_len; // min(当前4KB区间剩余传输数, AXI读通道最大突发长度)
	wire[8:0] now_burst_trans_n; // 本次突发的传输数
	// 读地址通道AXIS寄存器片
	// AXIS寄存器片从机
	wire[31:0] s_axis_ar_reg_slice_data;
    wire[7:0] s_axis_ar_reg_slice_user;
    wire s_axis_ar_reg_slice_valid;
    wire s_axis_ar_reg_slice_ready;
	// AXIS寄存器片主机
	wire[31:0] m_axis_ar_reg_slice_data;
    wire[7:0] m_axis_ar_reg_slice_user;
    wire m_axis_ar_reg_slice_valid;
    wire m_axis_ar_reg_slice_ready;
	
	assign m_axi_araddr = m_axis_ar_reg_slice_data;
	assign m_axi_arburst = 2'b01;
	assign m_axi_arlen = m_axis_ar_reg_slice_user;
	assign m_axi_arsize = 3'b011;
	assign m_axi_arvalid = m_axis_ar_reg_slice_valid;
	assign m_axis_ar_reg_slice_ready = m_axi_arready;
	
	assign s_axis_ar_reg_slice_data = now_ar;
	assign s_axis_ar_reg_slice_user = now_burst_trans_n - 1'b1; // 突发长度 - 1
	assign s_axis_ar_reg_slice_valid = raddr_outstanding_allow_arvalid & rdata_buffer_allow_arvalid & (~rd_req_ready);
	
	assign rd_req_done = s_axis_ar_reg_slice_valid & s_axis_ar_reg_slice_ready & last_burst;
	
	assign trans_n_remaining_in_4kB = trans_n_remaining_in_4kB_sub1 + 1'b1;
	
	assign min_trans_n_remaining_max_burst_len = (trans_n_remaining <= axi_rchn_max_burst_len) ? 
		trans_n_remaining:axi_rchn_max_burst_len;
	assign min_trans_n_remaining_in_4kB_max_burst_len = (trans_n_remaining_in_4kB_sub1 <= (axi_rchn_max_burst_len - 1)) ? 
		trans_n_remaining_in_4kB:axi_rchn_max_burst_len;
	// 本次突发的传输数 = min(剩余传输数, 当前4KB区间剩余传输数, AXI读通道最大突发长度)
	assign now_burst_trans_n = (min_trans_n_remaining_max_burst_len <= min_trans_n_remaining_in_4kB_max_burst_len) ? 
		min_trans_n_remaining_max_burst_len:min_trans_n_remaining_in_4kB_max_burst_len;
	
	assign last_burst = (trans_n_remaining <= axi_rchn_max_burst_len) & (trans_n_remaining <= trans_n_remaining_in_4kB);
	
	// 第1次突发(标志)
	always @(posedge clk)
	begin
		if((s_axis_rd_req_valid & s_axis_rd_req_ready) | (s_axis_ar_reg_slice_valid & s_axis_ar_reg_slice_ready))
			first_burst <= # simulation_delay s_axis_rd_req_valid & s_axis_rd_req_ready;
	end
	// 当前读地址
	always @(posedge clk)
	begin
		if((s_axis_rd_req_valid & s_axis_rd_req_ready) | (s_axis_ar_reg_slice_valid & s_axis_ar_reg_slice_ready))
			now_ar <= # simulation_delay (s_axis_rd_req_valid & s_axis_rd_req_ready) ? 
				{rd_baseaddr[31:3], 3'b000}:{now_ar[31:3] + now_burst_trans_n, 3'b000};
	end
	// 剩余传输数
	always @(posedge clk)
	begin
		if((s_axis_rd_req_valid & s_axis_rd_req_ready) | (s_axis_ar_reg_slice_valid & s_axis_ar_reg_slice_ready))
			trans_n_remaining <= # simulation_delay (s_axis_rd_req_valid & s_axis_rd_req_ready) ? 
				(rd_req_termination_addr[clogb2(max_rd_btt)+1:3] + (rd_req_termination_addr[2:0] != 3'b000)):
				(trans_n_remaining - now_burst_trans_n);
	end
	// 当前4KB区间剩余传输数 - 1
	always @(posedge clk)
	begin
		if((s_axis_rd_req_valid & s_axis_rd_req_ready) | (s_axis_ar_reg_slice_valid & s_axis_ar_reg_slice_ready))
			trans_n_remaining_in_4kB_sub1 <= # simulation_delay (s_axis_rd_req_valid & s_axis_rd_req_ready) ? 
				(~rd_baseaddr[11:3]):(trans_n_remaining_in_4kB_sub1 - now_burst_trans_n);
	end
	
	// 可选的AXI读地址通道AXIS寄存器片
	axis_reg_slice #(
		.data_width(32),
		.user_width(8),
		.forward_registered(en_axi_ar_reg_slice),
		.back_registered(en_axi_ar_reg_slice),
		.en_ready("true"),
		.simulation_delay(simulation_delay)
	)axi_ar_reg_slice(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axis_data(s_axis_ar_reg_slice_data),
		.s_axis_keep(4'bxxxx),
		.s_axis_user(s_axis_ar_reg_slice_user),
		.s_axis_last(1'bx),
		.s_axis_valid(s_axis_ar_reg_slice_valid),
		.s_axis_ready(s_axis_ar_reg_slice_ready),
		
		.m_axis_data(m_axis_ar_reg_slice_data),
		.m_axis_keep(),
		.m_axis_user(m_axis_ar_reg_slice_user),
		.m_axis_last(),
		.m_axis_valid(m_axis_ar_reg_slice_valid),
		.m_axis_ready(m_axis_ar_reg_slice_ready)
	);
	
	/** AXI读地址outstanding统计 **/
	wire on_start_outstanding_ar; // 启动滞外AXI读传输(指示)
	wire on_finish_outstanding_ar; // 完成滞外AXI读传输(指示)
	reg[clogb2(axi_raddr_outstanding):0] outstanding_ar_n; // 滞外AXI读传输个数
	reg outstanding_ar_full_n; // 滞外AXI读传输满标志
	// 读地址信息fifo
	reg[axi_raddr_outstanding-1:0] ar_msg_fifo_wptr; // 写指针
	reg[axi_raddr_outstanding-1:0] ar_msg_fifo_rptr; // 读指针
	reg ar_msg_fifo_last_burst_flag[0:axi_raddr_outstanding-1]; // 寄存器fifo(最后1次突发标志)
	reg[2:0] ar_msg_fifo_first_trans_keep_id[0:axi_raddr_outstanding-1]; // 寄存器fifo(首次传输的字节有效掩码)
	reg[2:0] ar_msg_fifo_last_trans_keep_id[0:axi_raddr_outstanding-1]; // 寄存器fifo(最后1次传输的字节有效掩码)
	wire ar_msg_fifo_last_burst_flag_dout; // 读数据(最后1次突发标志)
	wire[2:0] ar_msg_fifo_first_trans_keep_id_dout; // 读数据(首次传输的字节有效掩码)
	wire[2:0] ar_msg_fifo_last_trans_keep_id_dout; // 读数据(最后1次传输的字节有效掩码)
	
	assign raddr_outstanding_allow_arvalid = outstanding_ar_full_n;
	
	assign on_start_outstanding_ar = s_axis_ar_reg_slice_valid & s_axis_ar_reg_slice_ready;
	assign on_finish_outstanding_ar = m_axi_rvalid & m_axi_rready & m_axi_rlast;
	
	// 读地址信息fifo读数据
	generate
		if(axi_raddr_outstanding == 1)
		begin
			assign ar_msg_fifo_last_burst_flag_dout = ar_msg_fifo_last_burst_flag[0];
			assign ar_msg_fifo_first_trans_keep_id_dout = ar_msg_fifo_first_trans_keep_id[0];
			assign ar_msg_fifo_last_trans_keep_id_dout = ar_msg_fifo_last_trans_keep_id[0];
		end
		else if(axi_raddr_outstanding == 2)
		begin
			assign ar_msg_fifo_last_burst_flag_dout = 
				(ar_msg_fifo_rptr[0] & ar_msg_fifo_last_burst_flag[0])
				| (ar_msg_fifo_rptr[1] & ar_msg_fifo_last_burst_flag[1]);
			assign ar_msg_fifo_first_trans_keep_id_dout = 
				({8{ar_msg_fifo_rptr[0]}} & ar_msg_fifo_first_trans_keep_id[0])
				| ({8{ar_msg_fifo_rptr[1]}} & ar_msg_fifo_first_trans_keep_id[1]);
			assign ar_msg_fifo_last_trans_keep_id_dout = 
				({8{ar_msg_fifo_rptr[0]}} & ar_msg_fifo_last_trans_keep_id[0])
				| ({8{ar_msg_fifo_rptr[1]}} & ar_msg_fifo_last_trans_keep_id[1]);
		end
		else
		begin
			assign ar_msg_fifo_last_burst_flag_dout = 
				(ar_msg_fifo_rptr[0] & ar_msg_fifo_last_burst_flag[0])
				| (ar_msg_fifo_rptr[1] & ar_msg_fifo_last_burst_flag[1])
				| (ar_msg_fifo_rptr[2] & ar_msg_fifo_last_burst_flag[2])
				| (ar_msg_fifo_rptr[3] & ar_msg_fifo_last_burst_flag[3]);
			assign ar_msg_fifo_first_trans_keep_id_dout = 
				({8{ar_msg_fifo_rptr[0]}} & ar_msg_fifo_first_trans_keep_id[0])
				| ({8{ar_msg_fifo_rptr[1]}} & ar_msg_fifo_first_trans_keep_id[1])
				| ({8{ar_msg_fifo_rptr[2]}} & ar_msg_fifo_first_trans_keep_id[2])
				| ({8{ar_msg_fifo_rptr[3]}} & ar_msg_fifo_first_trans_keep_id[3]);
			assign ar_msg_fifo_last_trans_keep_id_dout = 
				({8{ar_msg_fifo_rptr[0]}} & ar_msg_fifo_last_trans_keep_id[0])
				| ({8{ar_msg_fifo_rptr[1]}} & ar_msg_fifo_last_trans_keep_id[1])
				| ({8{ar_msg_fifo_rptr[2]}} & ar_msg_fifo_last_trans_keep_id[2])
				| ({8{ar_msg_fifo_rptr[3]}} & ar_msg_fifo_last_trans_keep_id[3]);
		end
	endgenerate
	
	// 滞外AXI读传输个数
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			outstanding_ar_n <= 0;
		else if(on_start_outstanding_ar ^ on_finish_outstanding_ar)
			outstanding_ar_n <= # simulation_delay on_start_outstanding_ar ? (outstanding_ar_n + 1):(outstanding_ar_n - 1);
	end
	// 滞外AXI读传输满标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			outstanding_ar_full_n <= 1'b1;
		else if(on_start_outstanding_ar ^ on_finish_outstanding_ar)
			// on_start_outstanding_ar ? (outstanding_ar_n != (axi_raddr_outstanding - 1)):1'b1;
			outstanding_ar_full_n <= # simulation_delay (~on_start_outstanding_ar) 
				| (outstanding_ar_n != (axi_raddr_outstanding - 1));
	end
	
	// 读地址信息fifo写指针
	generate
		if(axi_raddr_outstanding == 1)
		begin
			always @(*)
				ar_msg_fifo_wptr = 1'b1;
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					ar_msg_fifo_wptr <= {{(axi_raddr_outstanding-1){1'b0}}, 1'b1};
				else if(on_start_outstanding_ar)
					ar_msg_fifo_wptr <= # simulation_delay 
						{ar_msg_fifo_wptr[axi_raddr_outstanding-2:0], ar_msg_fifo_wptr[axi_raddr_outstanding-1]};
			end
		end
	endgenerate
	// 读地址信息fifo读指针
	generate
		if(axi_raddr_outstanding == 1)
		begin
			always @(*)
				ar_msg_fifo_rptr = 1'b1;
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					ar_msg_fifo_rptr <= {{(axi_raddr_outstanding-1){1'b0}}, 1'b1};
				else if(on_finish_outstanding_ar)
					ar_msg_fifo_rptr <= # simulation_delay 
						{ar_msg_fifo_rptr[axi_raddr_outstanding-2:0], ar_msg_fifo_rptr[axi_raddr_outstanding-1]};
			end
		end
	endgenerate
	// 读地址信息fifo存储内容
	genvar ar_msg_fifo_item_i;
	generate
		for(ar_msg_fifo_item_i = 0;ar_msg_fifo_item_i < axi_raddr_outstanding;ar_msg_fifo_item_i = ar_msg_fifo_item_i + 1)
		begin
			// 最后1次突发标志
			always @(posedge clk)
			begin
				if(on_start_outstanding_ar & ar_msg_fifo_wptr[ar_msg_fifo_item_i])
					ar_msg_fifo_last_burst_flag[ar_msg_fifo_item_i] <= # simulation_delay last_burst;
			end
			// 首次传输的字节有效掩码
			always @(posedge clk)
			begin
				if(on_start_outstanding_ar & ar_msg_fifo_wptr[ar_msg_fifo_item_i])
					ar_msg_fifo_first_trans_keep_id[ar_msg_fifo_item_i] <= # simulation_delay first_trans_keep_id;
			end
			// 最后1次传输的字节有效掩码
			always @(posedge clk)
			begin
				if(on_start_outstanding_ar & ar_msg_fifo_wptr[ar_msg_fifo_item_i])
					ar_msg_fifo_last_trans_keep_id[ar_msg_fifo_item_i] <= # simulation_delay last_trans_keep_id;
			end
		end
	endgenerate
	
	/** AXI读数据处理 **/
	// 生成last信号
	wire rd_req_last_trans; // 读请求最后1个数据
	// 处理last信号并添加user信号后的AXI读数据流
	wire[63:0] s_axis_axi_data;
	wire[6:0] s_axis_axi_user; // {首次传输的字节有效掩码编号, 最后1次传输的字节有效掩码编号, AXI读突发最后1个数据(标志)}
    wire s_axis_axi_last;
    wire s_axis_axi_valid;
    wire s_axis_axi_ready;
	
	assign s_axis_axi_data = m_axi_rdata;
	assign s_axis_axi_user = {ar_msg_fifo_first_trans_keep_id_dout, ar_msg_fifo_last_trans_keep_id_dout, m_axi_rlast};
	assign s_axis_axi_last = rd_req_last_trans;
	assign s_axis_axi_valid = m_axi_rvalid;
	assign m_axi_rready = s_axis_axi_ready;
	
	assign rd_req_last_trans = m_axi_rlast & ar_msg_fifo_last_burst_flag_dout;
	
	/** 读数据buffer **/
	wire on_rdata_buffer_store; // 读数据buffer预存1个突发(指示)
	wire on_rdata_buffer_fetch; // 读数据buffer取出1个突发(指示)
	reg[clogb2(max_rdata_buffer_store_burst_n):0] rdata_buffer_store_burst_n; // 读数据buffer预存的突发个数
	reg rdata_buffer_full_n; // 读数据buffer满标志
	// 生成keep信号
	reg rdata_first; // 本数据包第1个读数据(标志)
	wire[7:0] rdata_first_keep; // 第1个读数据的keep信号
	wire[7:0] rdata_last_keep; // 最后1个读数据的keep信号
	// 读数据buffer输出流
	wire[63:0] m_axis_rdata_buffer_data;
	wire[7:0] m_axis_rdata_buffer_keep;
	wire[6:0] m_axis_rdata_buffer_user; // {首次传输的字节有效掩码编号, 最后1次传输的字节有效掩码编号, AXI读突发最后1个数据(标志)}
    wire m_axis_rdata_buffer_last;
    wire m_axis_rdata_buffer_valid;
    wire m_axis_rdata_buffer_ready;
	
	assign rdata_buffer_allow_arvalid = (axi_rdata_buffer_depth == 0) | rdata_buffer_full_n;
	
	assign on_rdata_buffer_store = s_axis_ar_reg_slice_valid & s_axis_ar_reg_slice_ready;
	assign on_rdata_buffer_fetch = m_axis_rdata_buffer_valid & m_axis_rdata_buffer_ready & m_axis_rdata_buffer_user[0];
	
	// 从字节有效掩码编号生成keep信号
	assign rdata_first_keep = {
		1'b1, m_axis_rdata_buffer_user[6:4] <= 3'd6,
		m_axis_rdata_buffer_user[6:4] <= 3'd5, m_axis_rdata_buffer_user[6:4] <= 3'd4,
		m_axis_rdata_buffer_user[6:4] <= 3'd3, m_axis_rdata_buffer_user[6:4] <= 3'd2,
		m_axis_rdata_buffer_user[6:4] <= 3'd1, m_axis_rdata_buffer_user[6:4] == 3'd0};
	assign rdata_last_keep = {
		m_axis_rdata_buffer_user[3:1] == 3'd7, m_axis_rdata_buffer_user[3:1] >= 3'd6,
		m_axis_rdata_buffer_user[3:1] >= 3'd5, m_axis_rdata_buffer_user[3:1] >= 3'd4,
		m_axis_rdata_buffer_user[3:1] >= 3'd3, m_axis_rdata_buffer_user[3:1] >= 3'd2,
		m_axis_rdata_buffer_user[3:1] >= 3'd1, 1'b1};
	/*
	({rdata_first, m_axis_rdata_buffer_last} == 2'b00) ? 8'b1111_1111:
	({rdata_first, m_axis_rdata_buffer_last} == 2'b01) ? rdata_last_keep:
	({rdata_first, m_axis_rdata_buffer_last} == 2'b10) ? rdata_first_keep:
														 (rdata_first_keep & rdata_last_keep)
	*/
	assign m_axis_rdata_buffer_keep = 
		({8{~rdata_first}} | rdata_first_keep) & 
		({8{~m_axis_rdata_buffer_last}} | rdata_last_keep);
	
	// 读数据buffer预存的突发个数
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rdata_buffer_store_burst_n <= 0;
		else if(on_rdata_buffer_store ^ on_rdata_buffer_fetch)
			rdata_buffer_store_burst_n <= # simulation_delay on_rdata_buffer_store ? (rdata_buffer_store_burst_n + 1):
				(rdata_buffer_store_burst_n - 1);
	end
	// 读数据buffer满标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rdata_buffer_full_n <= 1'b1;
		else if(on_rdata_buffer_store ^ on_rdata_buffer_fetch)
			// on_rdata_buffer_store ? (rdata_buffer_store_burst_n != (max_rdata_buffer_store_burst_n - 1)):1'b1;
			rdata_buffer_full_n <= # simulation_delay (~on_rdata_buffer_store) 
				| (rdata_buffer_store_burst_n != (max_rdata_buffer_store_burst_n - 1));
	end
	
	// 本数据包第1个读数据(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rdata_first <= 1'b1;
		else if(m_axis_rdata_buffer_valid & m_axis_rdata_buffer_ready)
			rdata_first <= # simulation_delay m_axis_rdata_buffer_last;
	end
	
	// 可选的AXI读数据缓存fifo
	generate
		if(axi_rdata_buffer_depth != 0)
		begin
			axis_data_fifo #(
				.is_async("false"),
				.en_packet_mode("false"),
				.ram_type("bram"),
				.fifo_depth(axi_rdata_buffer_depth),
				.data_width(64),
				.user_width(7),
				.simulation_delay(simulation_delay)
			)axi_rdata_buffer(
				.s_axis_aclk(clk),
				.s_axis_aresetn(rst_n),
				.m_axis_aclk(clk),
				.m_axis_aresetn(rst_n),
				
				.s_axis_data(s_axis_axi_data),
				.s_axis_keep(8'bxxxx_xxxx),
				.s_axis_strb(8'bxxxx_xxxx),
				.s_axis_user(s_axis_axi_user),
				.s_axis_last(s_axis_axi_last),
				.s_axis_valid(s_axis_axi_valid),
				.s_axis_ready(s_axis_axi_ready),
				
				.m_axis_data(m_axis_rdata_buffer_data),
				.m_axis_keep(),
				.m_axis_strb(),
				.m_axis_user(m_axis_rdata_buffer_user),
				.m_axis_last(m_axis_rdata_buffer_last),
				.m_axis_valid(m_axis_rdata_buffer_valid),
				.m_axis_ready(m_axis_rdata_buffer_ready)
			);
		end
		else
		begin
			// pass
			assign m_axis_rdata_buffer_data = s_axis_axi_data;
			assign m_axis_rdata_buffer_user = s_axis_axi_user;
			assign m_axis_rdata_buffer_last = s_axis_axi_last;
			assign m_axis_rdata_buffer_valid = s_axis_axi_valid;
			assign s_axis_axi_ready = m_axis_rdata_buffer_ready;
		end
	endgenerate
	
	/** 读数据AXIS寄存器片 **/
	// AXIS寄存器片从机
	wire[63:0] s_axis_rdata_reg_slice_data;
    wire[7:0] s_axis_rdata_reg_slice_keep;
	wire s_axis_rdata_reg_slice_last;
    wire s_axis_rdata_reg_slice_valid;
    wire s_axis_rdata_reg_slice_ready;
	// AXIS寄存器片主机
	wire[63:0] m_axis_rdata_reg_slice_data;
    wire[7:0] m_axis_rdata_reg_slice_keep;
	wire m_axis_rdata_reg_slice_last;
    wire m_axis_rdata_reg_slice_valid;
    wire m_axis_rdata_reg_slice_ready;
	
	assign m_axis_ft_par_data = m_axis_rdata_reg_slice_data;
	assign m_axis_ft_par_keep = m_axis_rdata_reg_slice_keep;
	assign m_axis_ft_par_last = m_axis_rdata_reg_slice_last;
	assign m_axis_ft_par_valid = m_axis_rdata_reg_slice_valid;
	assign m_axis_rdata_reg_slice_ready = m_axis_ft_par_ready;
	
	// 可选的读数据AXIS寄存器片
	axis_reg_slice #(
		.data_width(64),
		.user_width(1),
		.forward_registered(en_rdata_reg_slice),
		.back_registered(((axi_rdata_buffer_depth == 0) && (en_rdata_reg_slice == "true")) ? "true":"false"),
		.en_ready("true"),
		.simulation_delay(simulation_delay)
	)rdata_reg_slice(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axis_data(s_axis_rdata_reg_slice_data),
		.s_axis_keep(s_axis_rdata_reg_slice_keep),
		.s_axis_user(1'bx),
		.s_axis_last(s_axis_rdata_reg_slice_last),
		.s_axis_valid(s_axis_rdata_reg_slice_valid),
		.s_axis_ready(s_axis_rdata_reg_slice_ready),
		
		.m_axis_data(m_axis_rdata_reg_slice_data),
		.m_axis_keep(m_axis_rdata_reg_slice_keep),
		.m_axis_user(),
		.m_axis_last(m_axis_rdata_reg_slice_last),
		.m_axis_valid(m_axis_rdata_reg_slice_valid),
		.m_axis_ready(m_axis_rdata_reg_slice_ready)
	);
	
	/** 整理读数据流 **/
	reg first_trans_to_reorg; // 第1个待整理传输(标志)
	wire last_trans_to_reorg; // 最后1个待整理传输(标志)
	reg to_flush_reorg_buffer; // 冲刷拼接缓存区(标志)
	reg[2:0] reorg_method; // 拼接方式
	wire[2:0] reorg_method_nxt; // 新的拼接方式
	reg[7:0] flush_keep_mask; // 冲刷时的keep掩码
	reg[7:0] reorg_first_keep; // 第1个字节有效掩码
	reg[63:0] data_reorg_buffer; // 拼接缓存区(数据)
	reg[7:0] keep_reorg_buffer; // 拼接缓存区(字节有效掩码)
	wire reorg_pkt_only_one_trans; // 待整理数据包仅包含1个传输(标志)
	
	// 握手条件: (~to_flush_reorg_buffer) & m_axis_rdata_buffer_valid & s_axis_rdata_reg_slice_ready
	assign m_axis_rdata_buffer_ready = (~to_flush_reorg_buffer) & s_axis_rdata_reg_slice_ready;
	
	assign s_axis_rdata_reg_slice_data = reorg_pkt_only_one_trans ? 
		// 本次突发只有1个传输, 将有效字节对齐到最右边后输出, 共有8种情况
		((m_axis_rdata_buffer_data >> (reorg_method_nxt * 8)) | (64'dx << (64 - reorg_method_nxt * 8))):
		// 根据拼接方式, 合并拼接缓存区和当前数据, 共有8种情况
		((data_reorg_buffer >> (reorg_method * 8)) | (m_axis_rdata_buffer_data << (64 - reorg_method * 8)));
	assign s_axis_rdata_reg_slice_keep = 
		// 冲刷拼接缓存区时需要根据第1个输入数据的keep取掩码
		(flush_keep_mask | {8{~to_flush_reorg_buffer}}) &
		// 本次突发只有1个传输, 将keep信号对齐到LSB后输出, 共有8种情况
		(reorg_pkt_only_one_trans ? (m_axis_rdata_buffer_keep >> reorg_method_nxt):
			// 根据拼接方式, 合并拼接缓存区和当前keep信号, 共有8种情况
			((keep_reorg_buffer >> reorg_method) | (m_axis_rdata_buffer_keep << (4'd8 - {1'b0, reorg_method}))));
	assign s_axis_rdata_reg_slice_last = to_flush_reorg_buffer | 
		// 如果对最后1个输入数据取掩码后没有有效字节, 那么无需冲刷拼接缓存区, 当前就是最后1个输出数据
		((first_trans_to_reorg | (~(|(m_axis_rdata_buffer_keep & reorg_first_keep)))) & last_trans_to_reorg);
	// 握手条件: (to_flush_reorg_buffer & s_axis_rdata_reg_slice_ready) | 
	//     (m_axis_rdata_buffer_valid & s_axis_rdata_reg_slice_ready & (~(first_trans_to_reorg & (~last_trans_to_reorg))))
	assign s_axis_rdata_reg_slice_valid = to_flush_reorg_buffer | 
		(m_axis_rdata_buffer_valid & (~(first_trans_to_reorg & (~last_trans_to_reorg))));
    
	assign last_trans_to_reorg = m_axis_rdata_buffer_last;
	// 生成拼接方式
	assign reorg_method_nxt = count1_of_integer(~{
		m_axis_rdata_buffer_keep[0],
		|m_axis_rdata_buffer_keep[1:0],
		|m_axis_rdata_buffer_keep[2:0],
		|m_axis_rdata_buffer_keep[3:0],
		|m_axis_rdata_buffer_keep[4:0],
		|m_axis_rdata_buffer_keep[5:0],
		|m_axis_rdata_buffer_keep[6:0]}, 7);
	assign reorg_pkt_only_one_trans = first_trans_to_reorg & last_trans_to_reorg & (~to_flush_reorg_buffer);
	
	// 第1个待整理传输(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			first_trans_to_reorg <= 1'b1;
		else if(m_axis_rdata_buffer_valid & m_axis_rdata_buffer_ready)
			first_trans_to_reorg <= # simulation_delay last_trans_to_reorg;
	end
	
	// 冲刷拼接缓存区(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			to_flush_reorg_buffer <= 1'b0;
		else
			to_flush_reorg_buffer <= # simulation_delay 
				to_flush_reorg_buffer ? (~s_axis_rdata_reg_slice_ready):
					(m_axis_rdata_buffer_valid & s_axis_rdata_reg_slice_ready & 
					// 如果对最后1个输入数据取掩码后没有有效字节, 那么无需冲刷拼接缓存区
					(~first_trans_to_reorg) & last_trans_to_reorg & (|(m_axis_rdata_buffer_keep & reorg_first_keep)));
	end
	
	// 拼接方式
	always @(posedge clk)
	begin
		if(m_axis_rdata_buffer_valid & m_axis_rdata_buffer_ready & first_trans_to_reorg)
			reorg_method <= # simulation_delay reorg_method_nxt;
	end
	// 冲刷时的keep掩码
	always @(posedge clk)
	begin
		if(m_axis_rdata_buffer_valid & m_axis_rdata_buffer_ready & first_trans_to_reorg)
			flush_keep_mask <= # simulation_delay {
				m_axis_rdata_buffer_keep[0],
				|m_axis_rdata_buffer_keep[1:0],
				|m_axis_rdata_buffer_keep[2:0],
				|m_axis_rdata_buffer_keep[3:0],
				|m_axis_rdata_buffer_keep[4:0],
				|m_axis_rdata_buffer_keep[5:0],
				|m_axis_rdata_buffer_keep[6:0],
				1'b1
			};
	end
	// 第1个字节有效掩码
	always @(posedge clk)
	begin
		if(m_axis_rdata_buffer_valid & m_axis_rdata_buffer_ready & first_trans_to_reorg)
			reorg_first_keep <= # simulation_delay m_axis_rdata_buffer_keep;
	end
	
	// 拼接缓存区(数据)
	always @(posedge clk)
	begin
		if(m_axis_rdata_buffer_valid & m_axis_rdata_buffer_ready)
			data_reorg_buffer <= # simulation_delay m_axis_rdata_buffer_data;
	end
	// 拼接缓存区(字节有效掩码)
	always @(posedge clk)
	begin
		if(m_axis_rdata_buffer_valid & m_axis_rdata_buffer_ready)
			keep_reorg_buffer <= # simulation_delay m_axis_rdata_buffer_keep;
	end
	
endmodule
