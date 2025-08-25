`timescale 1ns / 1ps

`include "uvm_macros.svh"

import uvm_pkg::*;

`include "test_cases.sv"

module tb_apb_timer();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer timer_width = 32; // 定时器位宽(8~32)
	// 时钟配置
	localparam real clk_p = 10.0; // 时钟周期
	
	/** 时钟和复位 **/
	reg clk;
	reg rst_n;
	
	initial
	begin
		clk <= 1'b1;
		
		forever
		begin
			# (clk_p / 2) clk <= ~clk;
		end
	end
	
	initial begin
		rst_n <= 1'b0;
		
		# (clk_p * 10 + 1);
		
		rst_n <= 1'b1;
	end
	
	/** 接口 **/
	APB #(.out_drive_t(1), .addr_width(32), .data_width(32)) reg_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		uvm_config_db #(virtual APB #(.out_drive_t(1), 
			.addr_width(32), .data_width(32)).master)::set(null, 
			"uvm_test_top.env.reg_agt.drv", "apb_if", reg_if.master);
		uvm_config_db #(virtual APB #(.out_drive_t(1), 
			.addr_width(32), .data_width(32)).monitor)::set(null, 
			"uvm_test_top.env.reg_agt.mon", "apb_if", reg_if.monitor);
		
		// 启动testcase
		run_test("ApbTimerBaseTest");
	end
	
	/** 待测模块 **/
	// APB从机接口
    wire[31:0] paddr;
    wire psel;
    wire penable;
    wire pwrite;
    wire[31:0] pwdata;
    wire pready_out;
    wire[31:0] prdata_out;
    wire pslverr_out;
	
	assign paddr = reg_if.paddr;
	assign psel = reg_if.pselx;
	assign penable = reg_if.penable;
	assign pwrite = reg_if.pwrite;
	assign pwdata = reg_if.pwdata;
	assign reg_if.pready = pready_out;
	assign reg_if.prdata = prdata_out;
	assign reg_if.pslverr = pslverr_out;
	
	apb_timer #(
		.timer_width(timer_width),
		.channel_n(4),
		.simulation_delay(1)
	)dut(
		.clk(clk),
		.resetn(rst_n),
		
		.paddr(paddr),
		.psel(psel),
		.penable(penable),
		.pwrite(pwrite),
		.pwdata(pwdata),
		.pready_out(pready_out),
		.prdata_out(prdata_out),
		.pslverr_out(pslverr_out),
		
		.cap_cmp_i(4'b1111),
		.cap_cmp_o(),
		.cap_cmp_t(),
		
		.itr()
	);
	
endmodule
