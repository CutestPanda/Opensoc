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

module tb_axi_dma_engine_mm2s();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer DATA_WIDTH = 32; // 传输数据位宽(32 | 64 | 128 | 256)
	localparam integer MAX_BURST_LEN = 4; // 最大的突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	localparam S_AXIS_COMMON_CLOCK = "true"; // 命令AXIS从机与AXI主机是否使用相同的时钟和复位
	localparam M_AXIS_COMMON_CLOCK = "true"; // 输出数据流AXIS主机与AXI主机是否使用相同的时钟和复位
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
	AXIS #(.out_drive_t(simulation_delay), .data_width(56), .user_width(1)) m_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(32), .user_width(3)) s_axis_if(.clk(clk), .rst_n(rst_n));
	AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), .bresp_width(2), .rresp_width(2))
		axi_if_inst(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(56), .user_width(1)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(56), .user_width(1)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m_axis_if.monitor);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(32), .user_width(3)).slave)::set(null, 
			"uvm_test_top.env.agt2.drv", "axis_if", s_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(32), .user_width(3)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axis_if", s_axis_if.monitor);
		
		// 启动testcase
		run_test("AxiDmaEngineMM2SCase0Test");
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
			bram_single_port_u.mem[i][15:0] = (i << 2);
			bram_single_port_u.mem[i][31:16] = (i << 2) + 2;
		end
	end
	
	/** 待测模块 **/
	// 命令AXIS从机
	wire[55:0] s_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire s_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire s_cmd_axis_last; // 帧尾标志
	wire s_cmd_axis_valid;
	wire s_cmd_axis_ready;
	// 输出数据流AXIS主机
	wire[DATA_WIDTH-1:0] m_mm2s_axis_data;
	wire[DATA_WIDTH/8-1:0] m_mm2s_axis_keep;
	wire[2:0] m_mm2s_axis_user; // {读请求首次传输标志(1bit), 
	                            //     错误类型(2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR)}
	wire m_mm2s_axis_last;
	wire m_mm2s_axis_valid;
	wire m_mm2s_axis_ready;
	// AXI主机(读通道)
	// AR通道
	wire[31:0] m_axi_araddr;
	// 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
	wire[1:0] m_axi_arburst;
	wire[3:0] m_axi_arcache; // const -> 4'b0011
	wire[7:0] m_axi_arlen;
	wire[2:0] m_axi_arprot; // const -> 3'b000
	wire[2:0] m_axi_arsize; // const -> clogb2(DATA_WIDTH/8)
	wire m_axi_arvalid;
	wire m_axi_arready;
	// R通道
	wire[DATA_WIDTH-1:0] m_axi_rdata;
	// 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
	wire[1:0] m_axi_rresp;
	wire m_axi_rlast;
	wire m_axi_rvalid;
	wire m_axi_rready;
	
	assign s_cmd_axis_data = m_axis_if.data;
	assign s_cmd_axis_user = m_axis_if.user;
	assign s_cmd_axis_last = m_axis_if.last;
	assign s_cmd_axis_valid = m_axis_if.valid;
	assign m_axis_if.ready = s_cmd_axis_ready;
	
	assign s_axis_if.data = m_mm2s_axis_data;
	assign s_axis_if.keep = m_mm2s_axis_keep;
	assign s_axis_if.user = m_mm2s_axis_user;
	assign s_axis_if.last = m_mm2s_axis_last;
	assign s_axis_if.valid = m_mm2s_axis_valid;
	assign m_mm2s_axis_ready = s_axis_if.ready;
	
	assign axi_if_inst.araddr = m_axi_araddr;
	assign axi_if_inst.arburst = m_axi_arburst;
	assign axi_if_inst.arcache = m_axi_arcache;
	assign axi_if_inst.arlen = m_axi_arlen;
	assign axi_if_inst.arprot = m_axi_arprot;
	assign axi_if_inst.arsize = m_axi_arsize;
	assign axi_if_inst.arvalid = m_axi_arvalid;
	assign m_axi_arready = axi_if_inst.arready;
	assign m_axi_rdata = axi_if_inst.rdata;
	assign m_axi_rresp = axi_if_inst.rresp;
	assign m_axi_rlast = axi_if_inst.rlast;
	assign m_axi_rvalid = axi_if_inst.rvalid;
	assign axi_if_inst.rready = m_axi_rready;
	assign axi_if_inst.awvalid = 1'b0;
	assign axi_if_inst.wvalid = 1'b0;
	assign axi_if_inst.bready = 1'b1;
	
	axi_dma_engine_mm2s #(
		.DATA_WIDTH(DATA_WIDTH),
		.MAX_BURST_LEN(MAX_BURST_LEN),
		.S_AXIS_COMMON_CLOCK(S_AXIS_COMMON_CLOCK),
		.M_AXIS_COMMON_CLOCK(M_AXIS_COMMON_CLOCK),
		.EN_UNALIGNED_TRANS(EN_UNALIGNED_TRANS),
		.SIM_DELAY(simulation_delay)
	)dut(
		.s_axis_aclk(clk),
		.s_axis_aresetn(rst_n),
		.m_axis_aclk(clk),
		.m_axis_aresetn(rst_n),
		.m_axi_aclk(clk),
		.m_axi_aresetn(rst_n),
		
		.s_cmd_axis_data(s_cmd_axis_data),
		.s_cmd_axis_user(s_cmd_axis_user),
		.s_cmd_axis_last(s_cmd_axis_last),
		.s_cmd_axis_valid(s_cmd_axis_valid),
		.s_cmd_axis_ready(s_cmd_axis_ready),
		
		.m_mm2s_axis_data(m_mm2s_axis_data),
		.m_mm2s_axis_keep(m_mm2s_axis_keep),
		.m_mm2s_axis_user(m_mm2s_axis_user),
		.m_mm2s_axis_last(m_mm2s_axis_last),
		.m_mm2s_axis_valid(m_mm2s_axis_valid),
		.m_mm2s_axis_ready(m_mm2s_axis_ready),
		
		.m_axi_araddr(m_axi_araddr),
		.m_axi_arburst(m_axi_arburst),
		.m_axi_arcache(m_axi_arcache),
		.m_axi_arlen(m_axi_arlen),
		.m_axi_arprot(m_axi_arprot),
		.m_axi_arsize(m_axi_arsize),
		.m_axi_arvalid(m_axi_arvalid),
		.m_axi_arready(m_axi_arready),
		.m_axi_rdata(m_axi_rdata),
		.m_axi_rresp(m_axi_rresp),
		.m_axi_rlast(m_axi_rlast),
		.m_axi_rvalid(m_axi_rvalid),
		.m_axi_rready(m_axi_rready)
	);
	
endmodule
