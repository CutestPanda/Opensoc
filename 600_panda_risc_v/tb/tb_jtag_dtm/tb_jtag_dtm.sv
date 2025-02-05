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

module tb_jtag_dtm();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam JTAG_VERSION  = 4'h1; // IDCODE寄存器下Version域的值
	localparam DTMCS_IDLE_HINT = 3'd5; // 停留在Run-Test/Idle状态的周期数
	localparam integer ABITS = 7; // DMI地址位宽(必须在范围[7, 32]内)
	localparam integer SYN_STAGE = 2; // 同步器级数(必须>=1)
	// 时钟和复位配置
	localparam real m_clk_p = 20.0; // APB主机时钟周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 时钟和复位 **/
	reg m_clk;
	reg m_rst_n;
	
	initial
	begin
		m_clk <= 1'b1;
		
		forever
		begin
			# (m_clk_p / 2) m_clk <= ~m_clk;
		end
	end
	
	initial begin
		m_rst_n <= 1'b0;
		
		# (m_clk_p * 10 + simulation_delay);
		
		m_rst_n <= 1'b1;
	end
	
	/** 接口 **/
	APB #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32)) s_apb_if(.clk(m_clk), .rst_n(m_rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual APB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).slave)::set(null, 
			"uvm_test_top.env.agt1.drv", "apb_if", s_apb_if.slave);
		uvm_config_db #(virtual APB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "apb_if", s_apb_if.monitor);
		
		// 启动testcase
		run_test("JtagDtmCase0Test");
	end
	
	/** 待测模块 **/
	// JTAG从机
	reg TCK;
	reg TRST_N;
    reg TMS;
    reg TDI;
    wire TDO;
	wire TDO_OEN;
	// APB主机
    wire[ABITS+1:0] m_paddr;
    wire m_psel;
    wire m_penable;
    wire m_pwrite;
    wire[31:0] m_pwdata;
    wire m_pready;
    wire[31:0] m_prdata;
    wire m_pslverr;
	
	assign s_apb_if.paddr = 32'h0000_0000 | m_paddr;
	assign s_apb_if.pselx = m_psel;
	assign s_apb_if.penable = m_penable;
	assign s_apb_if.pwrite = m_pwrite;
	assign s_apb_if.pwdata = m_pwdata;
	assign m_pready = s_apb_if.pready;
	assign m_prdata = s_apb_if.prdata;
	assign m_pslverr = s_apb_if.pslverr;
	
	jtag_dtm #(
		.JTAG_VERSION(JTAG_VERSION),
		.DTMCS_IDLE_HINT(DTMCS_IDLE_HINT),
		.ABITS(ABITS),
		.SYN_STAGE(SYN_STAGE),
		.SIM_DELAY(simulation_delay)
	)dut(
		.tck(TCK),
		.trst_n(TRST_N),
		.tms(TMS),
		.tdi(TDI),
		.tdo(TDO),
		.tdo_oen(TDO_OEN),
		
		.m_apb_aclk(m_clk),
		.m_apb_aresetn(m_rst_n),
		
		.dmihardreset_req(),
		
		.m_paddr(m_paddr),
		.m_psel(m_psel),
		.m_penable(m_penable),
		.m_pwrite(m_pwrite),
		.m_pwdata(m_pwdata),
		.m_pready(m_pready),
		.m_prdata(m_prdata),
		.m_pslverr(m_pslverr)
	);
	
	/** JTAG测试激励 **/
    reg[40:0] shift_reg;
    reg in;
	
	initial begin
        TCK = 1;
        TMS = 1;
        TDI = 1;
		TRST_N = 0;
		
		# 100;
		
		TRST_N = 1;
		
        // RESET
        for(int i = 0;i < 8;i++)
		begin
            TMS = 1;
            TCK = 0;
            #100
            TCK = 1;
            #100
            TCK = 0;
        end
		
        // IR
        shift_reg = 41'b10001;
		
        // IDLE
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // SELECT-DR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // SELECT-IR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // CAPTURE-IR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // SHIFT-IR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // SHIFT-IR & EXIT1-IR
        for(int i = 5;i > 0;i--)
		begin
            if(shift_reg[0] == 1'b1)
                TDI = 1'b1;
            else
                TDI = 1'b0;
			
            if(i == 1)
                TMS = 1;
			
            TCK = 0;
            #100
            in = TDO;
            TCK = 1;
            #100
            TCK = 0;
			
            shift_reg = {{(36){1'b0}}, in, shift_reg[4:1]};
        end
		
        // PAUSE-IR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;
		
        // EXIT2-IR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;
		
        // UPDATE-IR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;
		
        // IDLE
		repeat(DTMCS_IDLE_HINT - 1)
		begin
			TMS = 0;
			TCK = 0;
			#100
			TCK = 1;
			#100
			TCK = 0;
		end
		
        // dmi write
        shift_reg = {7'h10, 32'd100, 2'b10};
		
        // SELECT-DR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;
		
        // CAPTURE-DR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;
		
        // SHIFT-DR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;
		
        // SHIFT-DR & EXIT1-DR
        for(int i = 41;i > 0;i--)
		begin
            if(shift_reg[0] == 1'b1)
                TDI = 1'b1;
            else
                TDI = 1'b0;
			
            if(i == 1)
                TMS = 1;
			
            TCK = 0;
            #100
            in = TDO;
            TCK = 1;
            #100
            TCK = 0;
			
            shift_reg = {in, shift_reg[40:1]};
        end
		
        // PAUSE-DR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;
		
        // EXIT2-DR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;
		
        // UPDATE-DR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;
		
        // IDLE
        repeat(DTMCS_IDLE_HINT - 1)
		begin
			TMS = 0;
			TCK = 0;
			#100
			TCK = 1;
			#100
			TCK = 0;
		end
		
        // SELECT-DR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;
		
        // dmi read
        shift_reg = {7'h11, {(32){1'b0}}, 2'b01};
		
        // CAPTURE-DR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;
		
        // SHIFT-DR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;
		
        // SHIFT-DR & EXIT1-DR
        for(int i = 41;i > 0;i--)
		begin
            if(shift_reg[0] == 1'b1)
                TDI = 1'b1;
            else
                TDI = 1'b0;
			
            if(i == 1)
                TMS = 1;
			
            TCK = 0;
            #100
            in = TDO;
            TCK = 1;
            #100
            TCK = 0;
			
            shift_reg = {in, shift_reg[40:1]};
        end
		
        // PAUSE-DR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;
		
        // EXIT2-DR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;
		
        // UPDATE-DR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;
		
        // IDLE
        repeat(DTMCS_IDLE_HINT - 1)
		begin
			TMS = 0;
			TCK = 0;
			#100
			TCK = 1;
			#100
			TCK = 0;
		end
		
        // SELECT-DR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;
		
        // dmi read
        shift_reg = {7'h11, {(32){1'b0}}, 2'b00};
		
        // CAPTURE-DR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;
		
        // SHIFT-DR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;
		
        // SHIFT-DR & EXIT1-DR
        for(int i = 41;i > 0;i--)
		begin
            if (shift_reg[0] == 1'b1)
                TDI = 1'b1;
            else
                TDI = 1'b0;
			
            if (i == 1)
                TMS = 1;
			
            TCK = 0;
            #100
            in = TDO;
            TCK = 1;
            #100
            TCK = 0;
			
            shift_reg = {in, shift_reg[40:1]};
        end
		
		#100

        $display("shift_reg_data = 0x%x", shift_reg[33:2]);
		$display("shift_reg_addr = 0x%x", shift_reg[40:34]);
		$display("shift_reg_resp = %b", shift_reg[1:0]);
    end
	
endmodule
