`timescale 1ns / 1ps
/********************************************************************
本模块: 上采样单元的输入/输出特征图DMA

描述:
32位地址64位数据的AXI主机

可选的AXI读数据buffer以提高AXI读突发的传输效率
内部的AXI写数据buffer提高了AXI写突发的传输效率

注意：
不支持非对齐传输
不支持4KB边界保护, 必须保证输入/输出特征图缓存区首地址能被(axi_max_burst_len*8)整除, 从而确保每次突发传输不会跨越4KB边界
对于输出结果特征图数据流来说, 必须保证每个数据包的字节数与写请求字节数一致

协议:
BLK CTRL
AXIS MASTER/SLAVE
AXI MASTER

作者: 陈家耀
日期: 2024/11/25
********************************************************************/


module axi_dma_for_upsample #(
	parameter integer axi_max_burst_len = 32, // AXI主机最大突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer axi_addr_outstanding = 4, // AXI地址缓冲深度(1~16)
	parameter integer max_rd_btt = 4 * 512, // 最大的读请求传输字节数(256 | 512 | 1024 | ...)
	parameter integer axi_rdata_buffer_depth = 512, // AXI读数据buffer深度(0 -> 不启用 | 512 | 1024 | ...)
	parameter integer max_wt_btt = 4 * 512, // 最大的写请求传输字节数(256 | 512 | 1024 | ...)
	parameter integer axi_wdata_buffer_depth = 512, // AXI写数据buffer深度(512 | 1024 | ...)
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 运行时参数
	input wire[31:0] in_ft_map_buf_baseaddr, // 输入特征图缓存区基地址
	input wire[31:0] in_ft_map_buf_len, // 输入特征图缓存区长度 - 1(以字节计)
	input wire[31:0] out_ft_map_buf_baseaddr, // 输出特征图缓存区基地址
	input wire[31:0] out_ft_map_buf_len, // 输出特征图缓存区长度 - 1(以字节计)
	
	// MM2S控制
	input wire mm2s_start,
	output wire mm2s_idle,
	output wire mm2s_done,
	// S2MM控制
	input wire s2mm_start,
	output wire s2mm_idle,
	output wire s2mm_done,
	
	// 输出结果特征图数据流
	input wire[63:0] s_axis_out_ft_map_data,
	input wire[7:0] s_axis_out_ft_map_keep,
	input wire s_axis_out_ft_map_last,
	input wire s_axis_out_ft_map_valid,
	output wire s_axis_out_ft_map_ready,
	
	// 输入待处理特征图数据流
	output wire[63:0] m_axis_in_ft_map_data,
	output wire[7:0] m_axis_in_ft_map_keep,
	output wire m_axis_in_ft_map_last,
	output wire m_axis_in_ft_map_valid,
	input wire m_axis_in_ft_map_ready,
	
	// AXI主机
	// AR
    output wire[31:0] m_axi_araddr,
    output wire[1:0] m_axi_arburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_arlen,
    output wire[2:0] m_axi_arsize, // const -> 3'b011
    output wire[3:0] m_axis_arcache, // const -> 4'b0011
    output wire m_axi_arvalid,
    input wire m_axi_arready,
	// AW
    output wire[31:0] m_axi_awaddr,
    output wire[1:0] m_axi_awburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_awlen,
    output wire[2:0] m_axi_awsize, // const -> 3'b011
    output wire[3:0] m_axis_awcache, // const -> 4'b0011
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    // B
    input wire[1:0] m_axi_bresp, // ignored
    input wire m_axi_bvalid,
    output wire m_axi_bready, // const -> 1'b1
    // R
    input wire[63:0] m_axi_rdata,
    input wire[1:0] m_axi_rresp, // ignored
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output wire m_axi_rready,
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
	// 读数据buffer存储的最大读突发次数
	localparam integer MAX_RDATA_BUFFER_STORE_N = (axi_rdata_buffer_depth == 0) ? 4:(axi_rdata_buffer_depth / axi_max_burst_len);
	// 写数据buffer存储的最大写突发次数
	localparam integer MAX_WDATA_BUFFER_STORE_N = axi_wdata_buffer_depth / axi_max_burst_len;
	
	/** 流程控制 **/
	reg mm2s_idle_reg; // MM2S通道空闲标志
	reg s2mm_idle_reg; // S2MM通道空闲标志
	
	assign mm2s_idle = mm2s_idle_reg;
	assign s2mm_idle = s2mm_idle_reg;
	
	// MM2S通道空闲标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mm2s_idle_reg <= 1'b1;
		else
			mm2s_idle_reg <= # simulation_delay mm2s_idle ? (~mm2s_start):mm2s_done;
	end
	// S2MM通道空闲标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			s2mm_idle_reg <= 1'b1;
		else
			s2mm_idle_reg <= # simulation_delay s2mm_idle ? (~s2mm_start):s2mm_done;
	end
	
	/** AXI读地址通道 **/
	reg[31:0] ar_addr; // 读地址
	reg[clogb2(max_rd_btt/8-1):0] remaining_rd_trans_n; // 剩余的(读传输次数 - 1)
	reg to_suppress_ar_addr; // 镇压读地址通道(标志)
	reg[clogb2(max_rd_btt/8-1):0] rd_trans_n_latched; // 锁存的(读传输次数 - 1)
	reg[7:0] last_rd_trans_keep_latched; // 锁存的最后1次读传输的keep信号
	wire last_rd_burst; // 最后1次读突发(标志)
	wire rdata_buffer_allow_arvalid; // 读数据buffer允许读地址通道有效(标志)
	wire raddr_outstanding_ctrl_allow_arvalid; // 读地址outstanding控制允许读地址通道有效(标志)
	// 读地址缓存
	reg[clogb2(axi_addr_outstanding):0] ar_outstanding_n; // 滞外的读传输个数
	reg ar_outstanding_full_n; // 读地址缓存满标志
	wire on_pre_launch_rd_burst; // 预启动新的读突发(指示)
	wire on_rdata_return; // 读突发数据已返回(指示)
	
	assign m_axi_araddr = ar_addr;
	assign m_axi_arburst = 2'b01;
	assign m_axi_arlen = last_rd_burst ? remaining_rd_trans_n:(axi_max_burst_len - 1);
	assign m_axi_arsize = 3'b011;
	assign m_axis_arcache = 4'b0011;
	assign m_axi_arvalid = (~mm2s_idle) & (~to_suppress_ar_addr) & rdata_buffer_allow_arvalid & raddr_outstanding_ctrl_allow_arvalid;
	
	assign last_rd_burst = remaining_rd_trans_n <= (axi_max_burst_len - 1);
	assign raddr_outstanding_ctrl_allow_arvalid = ar_outstanding_full_n;
	assign on_pre_launch_rd_burst = m_axi_arvalid & m_axi_arready;
	assign on_rdata_return = m_axi_rvalid & m_axi_rready & m_axi_rlast;
	
	// 读地址
	always @(posedge clk)
	begin
		if((mm2s_idle & mm2s_start) | on_pre_launch_rd_burst)
			ar_addr <= # simulation_delay mm2s_idle ? in_ft_map_buf_baseaddr:(ar_addr + (axi_max_burst_len * 8));
	end
	
	// 剩余的(读传输次数 - 1)
	always @(posedge clk)
	begin
		if((mm2s_idle & mm2s_start) | on_pre_launch_rd_burst)
			remaining_rd_trans_n <= # simulation_delay mm2s_idle ? 
				in_ft_map_buf_len[3+clogb2(max_rd_btt/8-1):3]:(remaining_rd_trans_n - axi_max_burst_len);
	end
	
	// 镇压读地址通道(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			to_suppress_ar_addr <= 1'b0;
		else
			to_suppress_ar_addr <= # simulation_delay to_suppress_ar_addr ? 
				(~mm2s_done):(on_pre_launch_rd_burst & last_rd_burst);
	end
	
	// 锁存的(读传输次数 - 1)
	always @(posedge clk)
	begin
		if(mm2s_idle & mm2s_start)
			rd_trans_n_latched <= # simulation_delay in_ft_map_buf_len[3+clogb2(max_rd_btt/8-1):3];
	end
	
	// 锁存的最后1次读传输的keep信号
	always @(posedge clk)
	begin
		if(mm2s_idle & mm2s_start)
			/*
			case(in_ft_map_buf_len[2:0])
				3'd0: last_rd_trans_keep_latched <= # simulation_delay 8'b0000_0001;
				3'd1: last_rd_trans_keep_latched <= # simulation_delay 8'b0000_0011;
				3'd2: last_rd_trans_keep_latched <= # simulation_delay 8'b0000_0111;
				3'd3: last_rd_trans_keep_latched <= # simulation_delay 8'b0000_1111;
				3'd4: last_rd_trans_keep_latched <= # simulation_delay 8'b0001_1111;
				3'd5: last_rd_trans_keep_latched <= # simulation_delay 8'b0011_1111;
				3'd6: last_rd_trans_keep_latched <= # simulation_delay 8'b0111_1111;
				3'd7: last_rd_trans_keep_latched <= # simulation_delay 8'b1111_1111;
				default: last_rd_trans_keep_latched <= # simulation_delay 8'bxxxx_xxxx;
			endcase
			*/
			last_rd_trans_keep_latched <= # simulation_delay {
				in_ft_map_buf_len[2] & in_ft_map_buf_len[1] & in_ft_map_buf_len[0],
				in_ft_map_buf_len[2] & in_ft_map_buf_len[1],
				in_ft_map_buf_len[2] & (in_ft_map_buf_len[1] | in_ft_map_buf_len[0]),
				in_ft_map_buf_len[2],
				in_ft_map_buf_len[2] | (in_ft_map_buf_len[1] & in_ft_map_buf_len[0]),
				in_ft_map_buf_len[2] | in_ft_map_buf_len[1],
				in_ft_map_buf_len[2] | in_ft_map_buf_len[1] | in_ft_map_buf_len[0],
				1'b1
			};
	end
	
	// 滞外的读传输个数
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			ar_outstanding_n <= 0;
		else if(on_pre_launch_rd_burst ^ on_rdata_return)
			ar_outstanding_n <= # simulation_delay 
				on_pre_launch_rd_burst ? (ar_outstanding_n + 1):(ar_outstanding_n - 1);
	end
	// 读地址缓存满标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			ar_outstanding_full_n <= 1'b1;
		else if(on_pre_launch_rd_burst ^ on_rdata_return)
			ar_outstanding_full_n <= # simulation_delay 
				// on_pre_launch_rd_burst ? (ar_outstanding_n != (axi_addr_outstanding - 1)):1'b1
				(~on_pre_launch_rd_burst) | (ar_outstanding_n != (axi_addr_outstanding - 1));
	end
	
	/** AXI读数据通道 **/
	reg[clogb2(MAX_RDATA_BUFFER_STORE_N):0] pre_launched_rd_burst_n; // 预启动的读突发次数
	reg rdata_buffer_pre_full_n; // 读数据buffer预满(标志)
	wire on_rd_burst_complete; // 读突发完成(指示)
	reg[clogb2(max_rd_btt/8-1):0] rd_trans_out_cnt; // 已输出的读传输数据量(计数器)
	// 读数据buffer写端口
	wire rdata_buffer_wen;
	wire rdata_buffer_full_n;
	wire[63:0] rdata_buffer_din;
	wire rdata_buffer_din_burst_last; // 指示读突发最后1组数据
	// 读数据buffer读端口
	wire rdata_buffer_ren;
	wire rdata_buffer_empty_n;
	wire[63:0] rdata_buffer_dout;
	wire[7:0] rdata_buffer_dout_keep;
	wire rdata_buffer_dout_ft_last; // 指示特征图最后1组数据
	wire rdata_buffer_dout_burst_last; // 指示读突发最后1组数据
	
	assign mm2s_done = m_axis_in_ft_map_valid & m_axis_in_ft_map_ready & m_axis_in_ft_map_last;
	
	assign m_axis_in_ft_map_data = rdata_buffer_dout;
	assign m_axis_in_ft_map_keep = rdata_buffer_dout_keep;
	assign m_axis_in_ft_map_last = rdata_buffer_dout_ft_last;
	assign m_axis_in_ft_map_valid = rdata_buffer_empty_n;
	assign rdata_buffer_ren = m_axis_in_ft_map_ready;
	
	assign rdata_buffer_allow_arvalid = (axi_rdata_buffer_depth == 0) | rdata_buffer_pre_full_n;
	
	assign on_rd_burst_complete = rdata_buffer_ren & rdata_buffer_empty_n & rdata_buffer_dout_burst_last;
	
	assign rdata_buffer_wen = m_axi_rvalid;
	assign m_axi_rready = rdata_buffer_full_n;
	assign rdata_buffer_din = m_axi_rdata;
	assign rdata_buffer_din_burst_last = m_axi_rlast;
	
	// rdata_buffer_dout_ft_last ? last_rd_trans_keep_latched:8'hff
	assign rdata_buffer_dout_keep = {8{~rdata_buffer_dout_ft_last}} | last_rd_trans_keep_latched;
	assign rdata_buffer_dout_ft_last = rd_trans_out_cnt == rd_trans_n_latched;
	
	// 预启动的读突发次数
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			pre_launched_rd_burst_n <= 0;
		else if(on_pre_launch_rd_burst ^ on_rd_burst_complete)
			pre_launched_rd_burst_n <= # simulation_delay 
				on_pre_launch_rd_burst ? (pre_launched_rd_burst_n + 1):(pre_launched_rd_burst_n - 1);
	end
	// 读数据buffer预满(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rdata_buffer_pre_full_n <= 1'b1;
		else if(on_pre_launch_rd_burst ^ on_rd_burst_complete)
			rdata_buffer_pre_full_n <= # simulation_delay 
				// on_pre_launch_rd_burst ? (pre_launched_rd_burst_n != (MAX_RDATA_BUFFER_STORE_N - 1)):1'b1
				(~on_pre_launch_rd_burst) | (pre_launched_rd_burst_n != (MAX_RDATA_BUFFER_STORE_N - 1));
	end
	
	// 已输出的读传输数据量(计数器)
	always @(posedge clk)
	begin
		if((mm2s_idle & mm2s_start) | (m_axis_in_ft_map_valid & m_axis_in_ft_map_ready))
			// mm2s_idle ? 0:(rd_trans_out_cnt + 1)
			rd_trans_out_cnt <= # simulation_delay {(clogb2(max_rd_btt/8-1)+1){~mm2s_idle}} & (rd_trans_out_cnt + 1);
	end
	
	// 读数据buffer
	generate
		if(axi_rdata_buffer_depth > 0)
		begin
			ram_fifo_wrapper #(
				.fwft_mode("true"),
				.ram_type("bram"),
				.en_bram_reg("false"),
				.fifo_depth(axi_rdata_buffer_depth),
				.fifo_data_width(64 + 1),
				.full_assert_polarity("low"),
				.empty_assert_polarity("low"),
				.almost_full_assert_polarity("no"),
				.almost_empty_assert_polarity("no"),
				.en_data_cnt("false"),
				.almost_full_th(),
				.almost_empty_th(),
				.simulation_delay(simulation_delay)
			)rdata_buffer_fifo(
				.clk(clk),
				.rst_n(rst_n),
				
				.fifo_wen(rdata_buffer_wen),
				.fifo_din({rdata_buffer_din_burst_last, rdata_buffer_din}),
				.fifo_full_n(rdata_buffer_full_n),
				
				.fifo_ren(rdata_buffer_ren),
				.fifo_dout({rdata_buffer_dout_burst_last, rdata_buffer_dout}),
				.fifo_empty_n(rdata_buffer_empty_n)
			);
		end
		else
		begin
			assign {rdata_buffer_dout_burst_last, rdata_buffer_dout} = {rdata_buffer_din_burst_last, rdata_buffer_din};
			assign rdata_buffer_empty_n = rdata_buffer_wen;
			assign rdata_buffer_full_n = rdata_buffer_ren;
		end
	endgenerate
	
	/** AXI写地址通道 **/
	reg[31:0] aw_addr; // 写地址
	reg[clogb2(max_wt_btt/8-1):0] remaining_wt_trans_n; // 剩余的(写传输次数 - 1)
	reg to_suppress_aw_addr; // 镇压写地址通道(标志)
	wire last_wt_burst; // 最后1次写突发(标志)
	wire wdata_buffer_allow_awvalid; // 写数据buffer允许写地址通道有效(标志)
	wire waddr_outstanding_ctrl_allow_awvalid; // 写地址outstanding控制允许写地址通道有效(标志)
	// 写地址缓存
	reg[clogb2(axi_addr_outstanding):0] aw_outstanding_n; // 滞外的写传输个数
	reg aw_outstanding_full_n; // 写地址缓存满标志
	wire on_pre_launch_wt_burst; // 预启动新的写突发(指示)
	wire on_bresp_gotten; // 得到写响应(指示)
	
	assign m_axi_awaddr = aw_addr;
	assign m_axi_awburst = 2'b01;
	assign m_axi_awlen = last_wt_burst ? remaining_wt_trans_n:(axi_max_burst_len - 1);
	assign m_axi_awsize = 3'b011;
	assign m_axis_awcache = 4'b0011;
	assign m_axi_awvalid = (~s2mm_idle) & (~to_suppress_aw_addr) & wdata_buffer_allow_awvalid & waddr_outstanding_ctrl_allow_awvalid;
	
	assign last_wt_burst = remaining_wt_trans_n <= (axi_max_burst_len - 1);
	assign waddr_outstanding_ctrl_allow_awvalid = aw_outstanding_full_n;
	assign on_pre_launch_wt_burst = m_axi_awvalid & m_axi_awready;
	assign on_bresp_gotten = m_axi_bvalid;
	
	// 写地址
	always @(posedge clk)
	begin
		if((s2mm_idle & s2mm_start) | on_pre_launch_wt_burst)
			aw_addr <= # simulation_delay s2mm_idle ? out_ft_map_buf_baseaddr:(aw_addr + (axi_max_burst_len * 8));
	end
	
	// 剩余的(写传输次数 - 1)
	always @(posedge clk)
	begin
		if((s2mm_idle & s2mm_start) | on_pre_launch_wt_burst)
			remaining_wt_trans_n <= # simulation_delay s2mm_idle ? 
				out_ft_map_buf_len[3+clogb2(max_wt_btt/8-1):3]:(remaining_wt_trans_n - axi_max_burst_len);
	end
	
	// 镇压写地址通道(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			to_suppress_aw_addr <= 1'b0;
		else
			to_suppress_aw_addr <= # simulation_delay to_suppress_aw_addr ? 
				(~s2mm_done):(on_pre_launch_wt_burst & last_wt_burst);
	end
	
	// 滞外的写传输个数
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			aw_outstanding_n <= 0;
		else if(on_pre_launch_wt_burst ^ on_bresp_gotten)
			aw_outstanding_n <= # simulation_delay 
				on_pre_launch_wt_burst ? (aw_outstanding_n + 1):(aw_outstanding_n - 1);
	end
	// 写地址缓存满标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			aw_outstanding_full_n <= 1'b1;
		else if(on_pre_launch_wt_burst ^ on_bresp_gotten)
			aw_outstanding_full_n <= # simulation_delay 
				// on_pre_launch_wt_burst ? (aw_outstanding_n != (axi_addr_outstanding - 1)):1'b1
				(~on_pre_launch_wt_burst) | (aw_outstanding_n != (axi_addr_outstanding - 1));
	end
	
	/** AXI写响应通道 **/
	// 写突发信息fifo写端口
	wire wburst_msg_fifo_wen;
	wire wburst_msg_fifo_din; // 指示本次写请求最后1次写突发
	// 写突发信息fifo读端口
	wire wburst_msg_fifo_ren;
	wire wburst_msg_fifo_dout; // 指示本次写请求最后1次写突发
	
	assign s2mm_done = m_axi_bvalid & wburst_msg_fifo_dout;
	assign m_axi_bready = 1'b1;
	
	assign wburst_msg_fifo_wen = on_pre_launch_wt_burst;
	assign wburst_msg_fifo_din = last_wt_burst;
	assign wburst_msg_fifo_ren = m_axi_bvalid;
	
	// 写突发信息fifo
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.fifo_depth(axi_addr_outstanding), // 深度设为1也不会出错
		.fifo_data_width(1),
		.almost_full_th(),
		.almost_empty_th(),
		.simulation_delay(simulation_delay)
	)wburst_msg_fifo(
		.clk(clk),
		.rst_n(rst_n),
		
		.fifo_wen(wburst_msg_fifo_wen),
		.fifo_din(wburst_msg_fifo_din),
		.fifo_full_n(),
		
		.fifo_ren(wburst_msg_fifo_ren),
		.fifo_dout(wburst_msg_fifo_dout),
		.fifo_empty_n()
	);
	
	/** AXI写数据通道 **/
	wire on_wdata_buffered; // 缓存1次写突发对应的数据(指示)
	reg[clogb2(MAX_WDATA_BUFFER_STORE_N):0] wdata_buffer_store_n; // 写数据buffer已缓存的写突发个数
	reg wdata_buffer_has_stored_burst; // 写数据buffer缓存非空标志
	reg[clogb2(axi_max_burst_len-1):0] wdata_tid_in_burst; // 写数据在写突发中的编号(计数器)
	// 写数据buffer写端口
	wire wdata_buffer_wen;
	wire wdata_buffer_full_n;
	wire[63:0] wdata_buffer_din;
	wire[2:0] wdata_buffer_din_kid; // 字节使能掩码编号
	wire wdata_buffer_din_last; // 指示写突发最后1组数据
	// 写数据buffer读端口
	wire wdata_buffer_ren;
	wire wdata_buffer_empty_n;
	wire[63:0] wdata_buffer_dout;
	wire[2:0] wdata_buffer_dout_kid; // 字节使能掩码编号
	wire wdata_buffer_dout_last; // 指示写突发最后1组数据
	
	assign m_axi_wdata = wdata_buffer_dout;
	/*
	(wdata_buffer_dout_kid == 3'd0) ? 8'b0000_0001:
	(wdata_buffer_dout_kid == 3'd1) ? 8'b0000_0011:
	(wdata_buffer_dout_kid == 3'd2) ? 8'b0000_0111:
	(wdata_buffer_dout_kid == 3'd3) ? 8'b0000_1111:
	(wdata_buffer_dout_kid == 3'd4) ? 8'b0001_1111:
	(wdata_buffer_dout_kid == 3'd5) ? 8'b0011_1111:
	(wdata_buffer_dout_kid == 3'd6) ? 8'b0111_1111:
	                                  8'b1111_1111;
	*/
	assign m_axi_wstrb = {
		wdata_buffer_dout_kid[2] & wdata_buffer_dout_kid[1] & wdata_buffer_dout_kid[0],
		wdata_buffer_dout_kid[2] & wdata_buffer_dout_kid[1],
		wdata_buffer_dout_kid[2] & (wdata_buffer_dout_kid[1] | wdata_buffer_dout_kid[0]),
		wdata_buffer_dout_kid[2],
		wdata_buffer_dout_kid[2] | (wdata_buffer_dout_kid[1] & wdata_buffer_dout_kid[0]),
		wdata_buffer_dout_kid[2] | wdata_buffer_dout_kid[1],
		wdata_buffer_dout_kid[2] | wdata_buffer_dout_kid[1] | wdata_buffer_dout_kid[0],
		1'b1
	};
	assign m_axi_wlast = wdata_buffer_dout_last;
	assign m_axi_wvalid = wdata_buffer_empty_n;
	assign wdata_buffer_ren = m_axi_wready;
	
	assign wdata_buffer_allow_awvalid = wdata_buffer_has_stored_burst;
	
	assign on_wdata_buffered = wdata_buffer_wen & wdata_buffer_full_n & wdata_buffer_din_last;
	
	assign wdata_buffer_wen = s_axis_out_ft_map_valid;
	assign s_axis_out_ft_map_ready = wdata_buffer_full_n;
	assign wdata_buffer_din = s_axis_out_ft_map_data;
	/*
	s_axis_out_ft_map_keep[7] ? 3'd7:
	s_axis_out_ft_map_keep[6] ? 3'd6:
	s_axis_out_ft_map_keep[5] ? 3'd5:
	s_axis_out_ft_map_keep[4] ? 3'd4:
	s_axis_out_ft_map_keep[3] ? 3'd3:
	s_axis_out_ft_map_keep[2] ? 3'd2:
	s_axis_out_ft_map_keep[1] ? 3'd1:
	                           3'd0;
	*/
	assign wdata_buffer_din_kid = {
		s_axis_out_ft_map_keep[4], 
		s_axis_out_ft_map_keep[6] | ((~s_axis_out_ft_map_keep[4]) & s_axis_out_ft_map_keep[2]),
		((~s_axis_out_ft_map_keep[2]) & s_axis_out_ft_map_keep[1]) | 
			((~s_axis_out_ft_map_keep[4]) & s_axis_out_ft_map_keep[3]) | 
			((~s_axis_out_ft_map_keep[6]) & s_axis_out_ft_map_keep[5]) | 
			s_axis_out_ft_map_keep[7]
	};
	assign wdata_buffer_din_last = (wdata_tid_in_burst == (axi_max_burst_len - 1)) | s_axis_out_ft_map_last;
	
	// 写数据buffer已缓存的写突发个数
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wdata_buffer_store_n <= 0;
		else if(on_wdata_buffered ^ on_pre_launch_wt_burst)
			wdata_buffer_store_n <= # simulation_delay on_pre_launch_wt_burst ? (wdata_buffer_store_n - 1):(wdata_buffer_store_n + 1);
	end
	// 写数据buffer缓存非空标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wdata_buffer_has_stored_burst <= 1'b0;
		else if(on_wdata_buffered ^ on_pre_launch_wt_burst)
			// on_pre_launch_wt_burst ? (wdata_buffer_store_n != 1):1'b1
			wdata_buffer_has_stored_burst <= # simulation_delay (~on_pre_launch_wt_burst) | (wdata_buffer_store_n != 1);
	end
	
	// 写数据在写突发中的编号(计数器)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wdata_tid_in_burst <= 0;
		else if(wdata_buffer_wen & wdata_buffer_full_n)
			// s_axis_out_ft_map_last ? 0:(wdata_tid_in_burst + 1)
			wdata_tid_in_burst <= # simulation_delay {(clogb2(axi_max_burst_len-1)+1){~s_axis_out_ft_map_last}} & (wdata_tid_in_burst + 1);
	end
	
	// 写数据buffer
	ram_fifo_wrapper #(
		.fwft_mode("true"),
		.ram_type("bram"),
		.en_bram_reg("false"),
		.fifo_depth(axi_wdata_buffer_depth),
		.fifo_data_width(64 + 3 + 1),
		.full_assert_polarity("low"),
		.empty_assert_polarity("low"),
		.almost_full_assert_polarity("no"),
		.almost_empty_assert_polarity("no"),
		.en_data_cnt("false"),
		.almost_full_th(),
		.almost_empty_th(),
		.simulation_delay(simulation_delay)
	)wdata_buffer_fifo(
		.clk(clk),
		.rst_n(rst_n),
		
		.fifo_wen(wdata_buffer_wen),
		.fifo_din({wdata_buffer_din_last, wdata_buffer_din_kid, wdata_buffer_din}),
		.fifo_full_n(wdata_buffer_full_n),
		
		.fifo_ren(wdata_buffer_ren),
		.fifo_dout({wdata_buffer_dout_last, wdata_buffer_dout_kid, wdata_buffer_dout}),
		.fifo_empty_n(wdata_buffer_empty_n)
	);
    
endmodule
