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

module tb_axi_dma_engine_s2mm();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer DATA_WIDTH = 32; // 传输数据位宽(32 | 64 | 128 | 256)
	localparam integer MAX_BURST_LEN = 4; // 最大的突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	localparam S_CMD_AXIS_COMMON_CLOCK = "true"; // 命令AXIS从机与AXI主机是否使用相同的时钟和复位
	localparam S_S2MM_AXIS_COMMON_CLOCK = "true"; // 输入数据流AXIS从机与AXI主机是否使用相同的时钟和复位
	localparam EN_WT_BYTES_N_STAT = "false"; // 是否启用写字节数实时统计
	localparam EN_UNALIGNED_TRANS = "true"; // 是否允许非对齐传输
	// 仿真模型配置
	localparam integer memory_map_depth = 1024 * 64; // 存储映射深度(以字节计)
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
	AXIS #(.out_drive_t(simulation_delay), .data_width(56), .user_width(1)) m0_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(32), .user_width(0)) m1_axis_if(.clk(clk), .rst_n(rst_n));
	AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), .bresp_width(2), .rresp_width(2))
		axi_if_inst(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(56), .user_width(1)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m0_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(56), .user_width(1)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m0_axis_if.monitor);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(32), .user_width(0)).master)::set(null, 
			"uvm_test_top.env.agt2.drv", "axis_if", m1_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(32), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axis_if", m1_axis_if.monitor);
		
		// 启动testcase
		run_test("AxiDmaEngineS2MMCase0Test");
	end
	
	/** AXI-Bram控制器(仿真模型) **/
	// AXI SLAVE
    // 读地址通道
    wire[31:0] s_axi_araddr;
    wire[1:0] s_axi_arburst;
    wire[3:0] s_axi_arcache;
    wire[7:0] s_axi_arlen;
    wire s_axi_arlock;
    wire[2:0] s_axi_arprot;
    wire[2:0] s_axi_arsize;
    wire s_axi_arvalid;
    wire s_axi_arready;
    // 写地址通道
    wire[31:0] s_axi_awaddr;
    wire[1:0] s_axi_awburst;
    wire[3:0] s_axi_awcache;
    wire[7:0] s_axi_awlen;
    wire s_axi_awlock;
    wire[2:0] s_axi_awprot;
    wire[2:0] s_axi_awsize;
    wire s_axi_awvalid;
    wire s_axi_awready;
    // 写响应通道
    wire[1:0] s_axi_bresp;
    wire s_axi_bvalid;
    wire s_axi_bready;
    // 读数据通道
    wire[31:0] s_axi_rdata;
    wire s_axi_rlast;
    wire[1:0] s_axi_rresp;
    wire s_axi_rvalid;
    wire s_axi_rready;
    // 写数据通道
    wire[31:0] s_axi_wdata;
    wire s_axi_wlast;
    wire[3:0] s_axi_wstrb;
    wire s_axi_wvalid;
    wire s_axi_wready;
	// 存储器接口
    wire bram_clk;
    wire bram_rst;
    wire bram_en;
    wire[3:0] bram_wen;
    wire[29:0] bram_addr;
    wire[31:0] bram_din;
    wire[31:0] bram_dout;
	
	assign s_axi_araddr = axi_if_inst.araddr;
	assign s_axi_arburst = axi_if_inst.arburst;
	assign s_axi_arcache = axi_if_inst.arcache;
	assign s_axi_arlen = axi_if_inst.arlen;
	assign s_axi_arlock = axi_if_inst.arlock;
	assign s_axi_arprot = axi_if_inst.arprot;
	assign s_axi_arsize = axi_if_inst.arsize;
	assign s_axi_arvalid = axi_if_inst.arvalid;
	assign axi_if_inst.arready = s_axi_arready;
	
	assign s_axi_awaddr = axi_if_inst.awaddr;
	assign s_axi_awburst = axi_if_inst.awburst;
	assign s_axi_awcache = axi_if_inst.awcache;
	assign s_axi_awlen = axi_if_inst.awlen;
	assign s_axi_awlock = axi_if_inst.awlock;
	assign s_axi_awprot = axi_if_inst.awprot;
	assign s_axi_awsize = axi_if_inst.awsize;
	assign s_axi_awvalid = axi_if_inst.awvalid;
	assign axi_if_inst.awready = s_axi_awready;
	
	assign axi_if_inst.bresp = s_axi_bresp;
	assign axi_if_inst.bvalid = s_axi_bvalid;
	assign s_axi_bready = axi_if_inst.bready;
	
	assign axi_if_inst.rdata = s_axi_rdata;
	assign axi_if_inst.rlast = s_axi_rlast;
	assign axi_if_inst.rresp = s_axi_rresp;
	assign axi_if_inst.rvalid = s_axi_rvalid;
	assign s_axi_rready = axi_if_inst.rready;
	
	assign s_axi_wdata = axi_if_inst.wdata;
	assign s_axi_wlast = axi_if_inst.wlast;
	assign s_axi_wstrb = axi_if_inst.wstrb;
	assign s_axi_wvalid = axi_if_inst.wvalid;
	assign axi_if_inst.wready = s_axi_wready;
	
	axi_bram_ctrler #(
		.bram_depth(memory_map_depth / 4),
		.bram_read_la(1),
		.en_read_buf_fifo("false"),
		.simulation_delay(simulation_delay)
	)axi_bram_ctrler_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axi_araddr(s_axi_araddr),
		.s_axi_arburst(s_axi_arburst),
		.s_axi_arcache(s_axi_arcache),
		.s_axi_arlen(s_axi_arlen),
		.s_axi_arlock(s_axi_arlock),
		.s_axi_arprot(s_axi_arprot),
		.s_axi_arsize(s_axi_arsize),
		.s_axi_arvalid(s_axi_arvalid),
		.s_axi_arready(s_axi_arready),
		.s_axi_awaddr(s_axi_awaddr),
		.s_axi_awburst(s_axi_awburst),
		.s_axi_awcache(s_axi_awcache),
		.s_axi_awlen(s_axi_awlen),
		.s_axi_awlock(s_axi_awlock),
		.s_axi_awprot(s_axi_awprot),
		.s_axi_awsize(s_axi_awsize),
		.s_axi_awvalid(s_axi_awvalid),
		.s_axi_awready(s_axi_awready),
		.s_axi_bresp(s_axi_bresp),
		.s_axi_bvalid(s_axi_bvalid),
		.s_axi_bready(s_axi_bready),
		.s_axi_rdata(s_axi_rdata),
		.s_axi_rlast(s_axi_rlast),
		.s_axi_rresp(s_axi_rresp),
		.s_axi_rvalid(s_axi_rvalid),
		.s_axi_rready(s_axi_rready),
		.s_axi_wdata(s_axi_wdata),
		.s_axi_wlast(s_axi_wlast),
		.s_axi_wstrb(s_axi_wstrb),
		.s_axi_wvalid(s_axi_wvalid),
		.s_axi_wready(s_axi_wready),
		
		.bram_clk(bram_clk),
		.bram_rst(bram_rst),
		.bram_en(bram_en),
		.bram_wen(bram_wen),
		.bram_addr(bram_addr),
		.bram_din(bram_din),
		.bram_dout(bram_dout),
		
		.axi_bram_ctrler_err()
	);
	
	bram_single_port #(
		.style("LOW_LATENCY"),
		.rw_mode("read_first"),
		.mem_width(32),
		.mem_depth(memory_map_depth / 4),
		.INIT_FILE("no_init"),
		.byte_write_mode("true"),
		.simulation_delay(simulation_delay)
	)bram_single_port_u(
		.clk(bram_clk),
		
		.en(bram_en),
		.wen(bram_wen),
		.addr(bram_addr),
		.din(bram_din),
		.dout(bram_dout)
	);
	
	initial
	begin
		for(int i = 0;i < (memory_map_depth / 4);i++)
		begin
			bram_single_port_u.mem[i] = (i << 2);
		end
	end
	
	/** 待测模块 **/
	// 命令AXIS从机
	wire[55:0] s_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire s_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire s_cmd_axis_valid;
	wire s_cmd_axis_ready;
	// 输入数据流AXIS从机
	wire[DATA_WIDTH-1:0] s_s2mm_axis_data;
	wire[DATA_WIDTH/8-1:0] s_s2mm_axis_keep;
	wire s_s2mm_axis_last;
	wire s_s2mm_axis_valid;
	wire s_s2mm_axis_ready;
	// AXI主机(写通道)
	// AW通道
	wire[31:0] m_axi_awaddr;
	wire[1:0] m_axi_awburst;
	wire[3:0] m_axi_awcache;
	wire[7:0] m_axi_awlen;
	wire[2:0] m_axi_awprot;
	wire[2:0] m_axi_awsize;
	wire m_axi_awvalid;
	wire m_axi_awready;
	// W通道
	wire[DATA_WIDTH-1:0] m_axi_wdata;
	wire[DATA_WIDTH/8-1:0] m_axi_wstrb;
	wire m_axi_wlast;
	wire m_axi_wvalid;
	wire m_axi_wready;
	// B通道
	wire[1:0] m_axi_bresp;
	wire m_axi_bvalid;
	wire m_axi_bready;
	
	assign s_cmd_axis_data = m0_axis_if.data;
	assign s_cmd_axis_user = m0_axis_if.user;
	assign s_cmd_axis_valid = m0_axis_if.valid;
	assign m0_axis_if.ready = s_cmd_axis_ready;
	
	assign s_s2mm_axis_data = m1_axis_if.data;
	assign s_s2mm_axis_keep = m1_axis_if.keep;
	assign s_s2mm_axis_last = m1_axis_if.last;
	assign s_s2mm_axis_valid = m1_axis_if.valid;
	assign m1_axis_if.ready = s_s2mm_axis_ready;
	
	assign axi_if_inst.awaddr = m_axi_awaddr;
	assign axi_if_inst.awburst = m_axi_awburst;
	assign axi_if_inst.awcache = m_axi_awcache;
	assign axi_if_inst.awlen = m_axi_awlen;
	assign axi_if_inst.awprot = m_axi_awprot;
	assign axi_if_inst.awsize = m_axi_awsize;
	assign axi_if_inst.awvalid = m_axi_awvalid;
	assign m_axi_awready = axi_if_inst.awready;
	assign m_axi_bresp = axi_if_inst.bresp;
	assign m_axi_bvalid = axi_if_inst.bvalid;
	assign axi_if_inst.bready = m_axi_bready;
	assign axi_if_inst.wdata = m_axi_wdata;
	assign axi_if_inst.wstrb = m_axi_wstrb;
	assign axi_if_inst.wlast = m_axi_wlast;
	assign axi_if_inst.wvalid = m_axi_wvalid;
	assign m_axi_wready = axi_if_inst.wready;
	assign axi_if_inst.arvalid = 1'b0;
	assign axi_if_inst.rready = 1'b1;
	
	axi_dma_engine_s2mm #(
		.DATA_WIDTH(DATA_WIDTH),
		.MAX_BURST_LEN(MAX_BURST_LEN),
		.S_CMD_AXIS_COMMON_CLOCK(S_CMD_AXIS_COMMON_CLOCK),
		.S_S2MM_AXIS_COMMON_CLOCK(S_S2MM_AXIS_COMMON_CLOCK),
		.EN_WT_BYTES_N_STAT(EN_WT_BYTES_N_STAT),
		.EN_UNALIGNED_TRANS(EN_UNALIGNED_TRANS),
		.SIM_DELAY(simulation_delay)
	)dut(
		.s_cmd_axis_aclk(clk),
		.s_cmd_axis_aresetn(rst_n),
		.s_s2mm_axis_aclk(clk),
		.s_s2mm_axis_aresetn(rst_n),
		.m_axi_aclk(clk),
		.m_axi_aresetn(rst_n),
		
		.s_cmd_axis_data(s_cmd_axis_data),
		.s_cmd_axis_user(s_cmd_axis_user),
		.s_cmd_axis_valid(s_cmd_axis_valid),
		.s_cmd_axis_ready(s_cmd_axis_ready),
		
		.s_s2mm_axis_data(s_s2mm_axis_data),
		.s_s2mm_axis_keep(s_s2mm_axis_keep),
		.s_s2mm_axis_last(s_s2mm_axis_last),
		.s_s2mm_axis_valid(s_s2mm_axis_valid),
		.s_s2mm_axis_ready(s_s2mm_axis_ready),
		
		.m_axi_awaddr(m_axi_awaddr),
		.m_axi_awburst(m_axi_awburst),
		.m_axi_awcache(m_axi_awcache),
		.m_axi_awlen(m_axi_awlen),
		.m_axi_awprot(m_axi_awprot),
		.m_axi_awsize(m_axi_awsize),
		.m_axi_awvalid(m_axi_awvalid),
		.m_axi_awready(m_axi_awready),
		.m_axi_wdata(m_axi_wdata),
		.m_axi_wstrb(m_axi_wstrb),
		.m_axi_wlast(m_axi_wlast),
		.m_axi_wvalid(m_axi_wvalid),
		.m_axi_wready(m_axi_wready),
		.m_axi_bresp(m_axi_bresp),
		.m_axi_bvalid(m_axi_bvalid),
		.m_axi_bready(m_axi_bready)
	);
	
endmodule
