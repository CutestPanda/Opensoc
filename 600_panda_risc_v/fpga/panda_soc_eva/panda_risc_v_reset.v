`timescale 1ns / 1ps
/********************************************************************
本模块: 复位处理

描述:
由外部复位输入和软件复位请求, 输出异步复位、同步释放、滤除毛刺的系统复位, 并在复位释放后的第1个clk产生系统复位请求
当检测到(稳定的)外部复位输入, 或者捕获到软件复位请求时, 产生系统复位

注意：
本模块的输入时钟应当是系统中最慢的时钟
仔细考虑本复位模块是否可靠, 它提供的系统复位输出和系统复位请求是否正确???

协议:
无

作者: 陈家耀
日期: 2024/12/07
********************************************************************/


module panda_risc_v_reset #(
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟
	input wire clk,
	
	// 外部复位输入
	input wire ext_resetn,
	
	// 软件复位请求
	input wire sw_reset,
	
	// 系统复位输出
	output wire sys_resetn,
	// 系统复位请求
	output wire sys_reset_req
);
	
	/** 内部配置 **/
	localparam EN_EXT_RSTN_FILTER = "true"; // 是否使能外部复位滤波
	localparam integer FILTER_PERIOD_N = 4; // 外部复位滤波周期数
	localparam integer RST_RELEASE_DELAY_PERIOD_N = 4; // 复位释放延迟周期数
	
	/** 复位处理 **/
	reg[FILTER_PERIOD_N-1:0] ext_resetn_d; // 外部复位延迟链
	reg ext_resetn_filtered; // 滤除毛刺后的外部复位
	wire ext_resetn_processed; // 经过处理后的外部复位
	reg[RST_RELEASE_DELAY_PERIOD_N-1:0] rst_n_d; // 系统复位延迟链
	reg reset_req; // 系统复位请求
	
	assign sys_resetn = rst_n_d[RST_RELEASE_DELAY_PERIOD_N-1];
	assign sys_reset_req = reset_req;
	
	assign ext_resetn_processed = (EN_EXT_RSTN_FILTER == "true") ? ext_resetn_filtered:(ext_resetn & (~sw_reset));
	
	// 外部复位延迟链
	always @(posedge clk)
	begin
		// 问题: 外部复位延迟链本身没有复位, 一开始它处于不定态!
		// 考虑最近FILTER_PERIOD_N个时钟周期的外部复位输入
		ext_resetn_d <= # simulation_delay {ext_resetn_d[FILTER_PERIOD_N-2:0], ext_resetn};
	end
	
	// 滤除毛刺后的外部复位
	always @(posedge clk)
	begin
		// 问题: 滤除毛刺后的外部复位本身没有复位, 一开始它处于不定态!
		// 当检测到稳定的外部复位输入, 或者捕获到软件复位请求时, 产生系统复位
		ext_resetn_filtered <= # simulation_delay (|ext_resetn_d) & (~sw_reset);
	end
	
	// 系统复位延迟链
	always @(posedge clk or negedge ext_resetn_processed)
	begin
		if(~ext_resetn_processed)
			rst_n_d <= {RST_RELEASE_DELAY_PERIOD_N{1'b0}};
		else
			rst_n_d <= # simulation_delay {rst_n_d[RST_RELEASE_DELAY_PERIOD_N-2:0], 1'b1};
	end
	
	// 系统复位请求
	always @(posedge clk or negedge ext_resetn_processed)
	begin
		if(~ext_resetn_processed)
			reset_req <= 1'b0;
		else
			// 复位释放后的第1个clk产生系统复位请求
			reset_req <= # simulation_delay (~rst_n_d[RST_RELEASE_DELAY_PERIOD_N-1]) & rst_n_d[RST_RELEASE_DELAY_PERIOD_N-2];
	end
	
endmodule
