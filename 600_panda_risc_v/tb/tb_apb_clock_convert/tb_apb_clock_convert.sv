`timescale 1ns / 1ps

`include "uvm_macros.svh"

import uvm_pkg::*;

`include "test_cases.sv"
`include "envs.sv"
`include "agents.sv"
`include "sequencers.sv"
`include "drivers.sv"
`include "monitors.sv"
`include "transactions.sv"

module tb_apb_clock_convert();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer SYN_STAGE = 2; // 同步器级数(必须>=1)
	// 时钟和复位配置
	localparam real s_clk_p = 100.0; // APB从机时钟周期
	localparam real m_clk_p = 20.0; // APB主机时钟周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 时钟和复位 **/
	reg s_clk;
	reg s_rst_n;
	reg m_clk;
	reg m_rst_n;
	
	initial
	begin
		s_clk <= 1'b1;
		
		forever
		begin
			# (s_clk_p / 2) s_clk <= ~s_clk;
		end
	end
	
	initial
	begin
		m_clk <= 1'b1;
		
		forever
		begin
			# (m_clk_p / 2) m_clk <= ~m_clk;
		end
	end
	
	initial begin
		s_rst_n <= 1'b0;
		
		# (s_clk_p * 20 + simulation_delay);
		
		s_rst_n <= 1'b1;
	end
	
	initial begin
		m_rst_n <= 1'b0;
		
		# (m_clk_p * 10 + simulation_delay);
		
		m_rst_n <= 1'b1;
	end
	
	/** 接口 **/
	APB #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32)) m_apb_if(.clk(s_clk), .rst_n(s_rst_n));
	APB #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32)) s_apb_if(.clk(m_clk), .rst_n(m_rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual APB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "apb_if", m_apb_if.master);
		uvm_config_db #(virtual APB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "apb_if", m_apb_if.monitor);
		
		uvm_config_db #(virtual APB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).slave)::set(null, 
			"uvm_test_top.env.agt2.drv", "apb_if", s_apb_if.slave);
		uvm_config_db #(virtual APB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "apb_if", s_apb_if.monitor);
		
		// 启动testcase
		run_test("ApbClkCvtCase0Test");
	end
	
	/** 待测模块 **/
	// APB从机
    wire[31:0] s_paddr;
    wire s_psel;
    wire s_penable;
    wire s_pwrite;
    wire[31:0] s_pwdata;
    wire s_pready;
    wire[31:0] s_prdata;
    wire s_pslverr;
	// APB主机
    wire[31:0] m_paddr;
    wire m_psel;
    wire m_penable;
    wire m_pwrite;
    wire[31:0] m_pwdata;
    wire m_pready;
    wire[31:0] m_prdata;
    wire m_pslverr;
	
	assign s_paddr = m_apb_if.paddr;
	assign s_psel = m_apb_if.pselx;
	assign s_penable = m_apb_if.penable;
	assign s_pwrite = m_apb_if.pwrite;
	assign s_pwdata = m_apb_if.pwdata;
	assign m_apb_if.pready = s_pready;
	assign m_apb_if.prdata = s_prdata;
	assign m_apb_if.pslverr = s_pslverr;
	
	assign s_apb_if.paddr = m_paddr;
	assign s_apb_if.pselx = m_psel;
	assign s_apb_if.penable = m_penable;
	assign s_apb_if.pwrite = m_pwrite;
	assign s_apb_if.pwdata = m_pwdata;
	assign m_pready = s_apb_if.pready;
	assign m_prdata = s_apb_if.prdata;
	assign m_pslverr = s_apb_if.pslverr;
	
	apb_clock_convert #(
		.SYN_STAGE(SYN_STAGE),
		.SIM_DELAY(simulation_delay)
	)dut(
		.s_apb_aclk(s_clk),
		.s_apb_aresetn(s_rst_n),
		.m_apb_aclk(m_clk),
		.m_apb_aresetn(m_rst_n),
		
		.s_paddr(s_paddr),
		.s_psel(s_psel),
		.s_penable(s_penable),
		.s_pwrite(s_pwrite),
		.s_pwdata(s_pwdata),
		.s_pready(s_pready),
		.s_prdata(s_prdata),
		.s_pslverr(s_pslverr),
		
		.m_paddr(m_paddr),
		.m_psel(m_psel),
		.m_penable(m_penable),
		.m_pwrite(m_pwrite),
		.m_pwdata(m_pwdata),
		.m_pready(m_pready),
		.m_prdata(m_prdata),
		.m_pslverr(m_pslverr)
	);
	
endmodule
