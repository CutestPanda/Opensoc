`timescale 1ns / 1ps
/********************************************************************
本模块: 复位处理

描述:
由外部复位输入, 输出异步复位、同步释放的系统复位, 并在复位释放后的第1个clk
	产生复位请求

系统复位请求 = 上电复位请求 | 软件复位请求

注意：
本模块无法处理抖动的外部复位输入

协议:
无

作者: 陈家耀
日期: 2024/10/20
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
	
	reg[3:0] rst_n_d;
	reg reset_req;
	
	assign sys_resetn = rst_n_d[3];
	assign sys_reset_req = reset_req | sw_reset;
	
	always @(posedge clk or negedge ext_resetn)
	begin
		if(~ext_resetn)
			rst_n_d <= 4'b0000;
		else
			rst_n_d <= # simulation_delay {rst_n_d[2:0], 1'b1};
	end
	
	always @(posedge clk or negedge ext_resetn)
	begin
		if(~ext_resetn)
			reset_req <= 1'b0;
		else
			reset_req <= # simulation_delay (~rst_n_d[3]) & rst_n_d[2];
	end
	
endmodule
