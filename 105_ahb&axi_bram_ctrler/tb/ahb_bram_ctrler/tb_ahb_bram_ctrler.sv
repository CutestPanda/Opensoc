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

module tb_ahb_bram_ctrler();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer bram_read_la = 2; // Bram读延迟(1 | 2)
	// 时钟和复位配置
	localparam real clk_p = 10.0; // 时钟周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
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
		
		# (clk_p * 10 + simulation_delay);
		
		rst_n <= 1'b1;
	end
	
	/** 接口 **/
	AHB #(.out_drive_t(simulation_delay), .slave_n(1), .addr_width(32), .data_width(32), 
		.burst_width(3), .prot_width(4), .master_width(1)) ahb_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual AHB #(.out_drive_t(simulation_delay), 
			.slave_n(1), .addr_width(32), .data_width(32), 
			.burst_width(3), .prot_width(4), .master_width(1)).master)::set(null, 
			"uvm_test_top.env.agt.drv", "ahb_if", ahb_if.master);
		uvm_config_db #(virtual AHB #(.out_drive_t(simulation_delay), 
			.slave_n(1), .addr_width(32), .data_width(32), 
			.burst_width(3), .prot_width(4), .master_width(1)).monitor)::set(null, 
			"uvm_test_top.env.agt.mon", "ahb_if", ahb_if.monitor);
		
		// 启动testcase
		run_test("AHBBramCtrlerCase0Test");
	end
	
	/** 待测模块 **/
	// 存储器接口
    wire bram_en;
    wire[3:0] bram_wen;
    wire[29:0] bram_addr;
    wire[31:0] bram_din;
    wire[31:0] bram_dout;
	
	assign ahb_if.hsel = 1'b1;
	assign ahb_if.muxsel = 0;
	
	ahb_bram_ctrler #(
		.bram_read_la(bram_read_la),
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_ahb_haddr(ahb_if.haddr),
		.s_ahb_hburst(ahb_if.hburst),
		.s_ahb_hprot(ahb_if.hprot),
		.s_ahb_hrdata(ahb_if.hrdata_out[0]),
		.s_ahb_hready(ahb_if.hready),
		.s_ahb_hready_out(ahb_if.hready_out[0]),
		.s_ahb_hresp(ahb_if.hresp_out[0]),
		.s_ahb_hsize(ahb_if.hsize),
		.s_ahb_htrans(ahb_if.htrans),
		.s_ahb_hwdata(ahb_if.hwdata),
		.s_ahb_hwstrb(ahb_if.hwstrb),
		.s_ahb_hwrite(ahb_if.hwrite),
		.s_ahb_hsel(ahb_if.hsel),
		
		.bram_clk(),
		.bram_rst(),
		.bram_en(bram_en),
		.bram_wen(bram_wen),
		.bram_addr(bram_addr),
		.bram_din(bram_din),
		.bram_dout(bram_dout)
	);
	
	genvar mem_i;
	generate
		for(mem_i = 0;mem_i < 4;mem_i = mem_i + 1)
		begin
			bram_single_port #(
				.style((bram_read_la == 1) ? "LOW_LATENCY":"HIGH_PERFORMANCE"),
				.rw_mode("no_change"),
				.mem_width(8),
				.mem_depth(1024 * 16),
				.INIT_FILE("default"),
				.simulation_delay(simulation_delay)
			)bram_single_port_u(
				.clk(clk),
				
				.en(bram_en),
				.wen(bram_wen[mem_i]),
				.addr(bram_addr),
				.din(bram_din[mem_i*8+7:mem_i*8]),
				.dout(bram_dout[mem_i*8+7:mem_i*8])
			);
		end
	endgenerate
	
endmodule
