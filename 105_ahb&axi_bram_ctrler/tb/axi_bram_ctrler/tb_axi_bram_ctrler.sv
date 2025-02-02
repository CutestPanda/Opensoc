/*
MIT License

Copyright (c) 2024 Panda, 2257691535@qq.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

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

module tb_axi_bram_ctrler();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer bram_depth = 2048; // Bram深度
    localparam integer bram_read_la = 2; // Bram读延迟(1 | 2)
    localparam en_read_buf_fifo = "true"; // 是否使用读缓冲fifo
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
	AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2)) axi_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), 
			.bresp_width(2), .rresp_width(2)).master)::set(null, 
			"uvm_test_top.env.agt.drv", "axi_if", axi_if.master);
		uvm_config_db #(virtual AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), 
			.bresp_width(2), .rresp_width(2)).monitor)::set(null, 
			"uvm_test_top.env.agt.mon", "axi_if", axi_if.monitor);
		
		// 启动testcase
		run_test("AXIBramCtrlerCase0Test");
	end
	
	/** 待测模块 **/
	// 存储器接口
    wire bram_en;
    wire[3:0] bram_wen;
    wire[29:0] bram_addr;
    wire[31:0] bram_din;
    wire[31:0] bram_dout;
	
	axi_bram_ctrler #(
		.bram_depth(bram_depth),
		.bram_read_la(bram_read_la),
		.en_read_buf_fifo(en_read_buf_fifo),
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axi_araddr(axi_if.araddr),
        .s_axi_arburst(axi_if.arburst),
        .s_axi_arcache(axi_if.arcache),
        .s_axi_arlen(axi_if.arlen),
        .s_axi_arlock(axi_if.arlock),
        .s_axi_arprot(axi_if.arprot),
        .s_axi_arsize(axi_if.arsize),
        .s_axi_arvalid(axi_if.arvalid),
        .s_axi_arready(axi_if.arready),
        .s_axi_awaddr(axi_if.awaddr),
        .s_axi_awburst(axi_if.awburst),
        .s_axi_awcache(axi_if.awcache),
        .s_axi_awlen(axi_if.awlen),
        .s_axi_awlock(axi_if.awlock),
        .s_axi_awprot(axi_if.awprot),
        .s_axi_awsize(axi_if.awsize),
        .s_axi_awvalid(axi_if.awvalid),
        .s_axi_awready(axi_if.awready),
        .s_axi_bresp(axi_if.bresp),
        .s_axi_bvalid(axi_if.bvalid),
        .s_axi_bready(axi_if.bready),
        .s_axi_rdata(axi_if.rdata),
        .s_axi_rlast(axi_if.rlast),
        .s_axi_rresp(axi_if.rresp),
        .s_axi_rvalid(axi_if.rvalid),
        .s_axi_rready(axi_if.rready),
        .s_axi_wdata(axi_if.wdata),
        .s_axi_wlast(axi_if.wlast),
        .s_axi_wstrb(axi_if.wstrb),
        .s_axi_wvalid(axi_if.wvalid),
        .s_axi_wready(axi_if.wready),
		
		.bram_clk(),
		.bram_rst(),
		.bram_en(bram_en),
		.bram_wen(bram_wen),
		.bram_addr(bram_addr),
		.bram_din(bram_din),
		.bram_dout(bram_dout),
		
		.axi_bram_ctrler_err()
	);
	
	genvar mem_i;
	generate
		for(mem_i = 0;mem_i < 4;mem_i = mem_i + 1)
		begin
			bram_single_port #(
				.style((bram_read_la == 1) ? "LOW_LATENCY":"HIGH_PERFORMANCE"),
				.rw_mode("no_change"),
				.mem_width(8),
				.mem_depth(bram_depth),
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
