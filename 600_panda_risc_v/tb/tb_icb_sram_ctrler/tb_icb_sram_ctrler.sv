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

module tb_icb_sram_ctrler();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam en_unaligned_transfer = "true"; // 是否允许非对齐传输
	localparam wt_trans_imdt_resp = "false"; // 是否允许写传输立即响应
	// 仿真模型配置
	localparam integer bram_depth = 2048; // Bram深度
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
	ICB #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32)) m_icb_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual ICB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "icb_if", m_icb_if.master);
		uvm_config_db #(virtual ICB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "icb_if", m_icb_if.monitor);
		
		// 启动testcase
		run_test("ICBSramCtrlerCase0Test");
	end
	
	/** 待测模块 **/
	// 存储器接口
    wire bram_en;
    wire[3:0] bram_wen;
    wire[29:0] bram_addr;
    wire[31:0] bram_din;
    wire[31:0] bram_dout;
	
	icb_sram_ctrler #(
		.en_unaligned_transfer(en_unaligned_transfer),
		.wt_trans_imdt_resp(wt_trans_imdt_resp),
		.simulation_delay(simulation_delay)
	)dut(
		.s_icb_aclk(clk),
		.s_icb_aresetn(rst_n),
		
		.s_icb_cmd_addr(m_icb_if.cmd_addr),
		.s_icb_cmd_read(m_icb_if.cmd_read),
		.s_icb_cmd_wdata(m_icb_if.cmd_wdata),
		.s_icb_cmd_wmask(m_icb_if.cmd_wmask),
		.s_icb_cmd_valid(m_icb_if.cmd_valid),
		.s_icb_cmd_ready(m_icb_if.cmd_ready),
		
		.s_icb_rsp_rdata(m_icb_if.rsp_rdata),
		.s_icb_rsp_err(m_icb_if.rsp_err),
		.s_icb_rsp_valid(m_icb_if.rsp_valid),
		.s_icb_rsp_ready(m_icb_if.rsp_ready),
		
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
				.style("LOW_LATENCY"),
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
