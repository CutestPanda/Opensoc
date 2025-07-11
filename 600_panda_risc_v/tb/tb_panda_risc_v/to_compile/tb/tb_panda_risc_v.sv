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

module tb_panda_risc_v();
	
	/** 配置参数 **/
	// 待测模块配置
	parameter integer IMEM_DEPTH = 8 * 1024; // 指令存储器深度
	parameter integer DMEM_DEPTH = 8 * 1024; // 数据存储器深度
	parameter IMEM_INIT_FILE = "E:/modelsim/tb_panda_risc_v/inst_test/rv32ui-p-sw.txt"; // 指令存储器的初始化文件路径
	parameter DMEM_INIT_FILE = "no_init"; // 数据存储器的初始化文件路径
	parameter en_alu_csr_rw_bypass = "true"; // 是否使能ALU/CSR原子读写单元的数据旁路
	parameter imem_baseaddr = 32'h0000_0000; // 指令存储器基址
	parameter integer imem_addr_range = 16 * 1024; // 指令存储器地址区间长度
	parameter sgn_period_mul = "true"; // 是否使用单周期乘法器
	// 时钟和复位配置
	parameter real clk_p = 10.0; // 时钟周期
	parameter real simulation_delay = 1.0; // 仿真延时
	
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
	
	/** 汇编程序测试 **/
	wire[31:0] x3;
	wire[31:0] x26;
	wire[31:0] x27;
	
	assign x3 = panda_risc_v_sim_u.panda_risc_v_u.panda_risc_v_exu_u.panda_risc_v_reg_file_u.generic_reg_file[3];
	assign x26 = panda_risc_v_sim_u.panda_risc_v_u.panda_risc_v_exu_u.panda_risc_v_reg_file_u.generic_reg_file[26];
	assign x27 = panda_risc_v_sim_u.panda_risc_v_u.panda_risc_v_exu_u.panda_risc_v_reg_file_u.generic_reg_file[27];
	
	initial
	begin
		$display("test running...");
		
		wait(x26 == 32'b1);
		
        # (clk_p * 10);
		
        if(x27 == 32'b1)
		begin
            $display("~~~~~~~~~~~~~~~~~~~ TEST_PASS ~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~ #####     ##     ####    #### ~~~~~~~~~");
            $display("~~~~~~~~~ #    #   #  #   #       #     ~~~~~~~~~");
            $display("~~~~~~~~~ #    #  #    #   ####    #### ~~~~~~~~~");
            $display("~~~~~~~~~ #####   ######       #       #~~~~~~~~~");
            $display("~~~~~~~~~ #       #    #  #    #  #    #~~~~~~~~~");
            $display("~~~~~~~~~ #       #    #   ####    #### ~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        end
		else
		begin
		    $display("~~~~~~~~~~~~~~~~~~~ TEST_FAIL ~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~######    ##       #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#        #  #      #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#####   #    #     #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#       ######     #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#       #    #     #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#       #    #     #    ######~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
			
            $display("fail testnum = %2d", x3);
			
            for(int i = 0;i < 32;i++)
			begin
				$display("x%2d = 0x%x", i, 
					panda_risc_v_sim_u.panda_risc_v_u.panda_risc_v_exu_u.panda_risc_v_reg_file_u.generic_reg_file[i]);
			end
        end
	end
	
	/** 待测模块 **/
	panda_risc_v_sim #(
		.IMEM_DEPTH(IMEM_DEPTH),
		.DMEM_DEPTH(DMEM_DEPTH),
		.IMEM_INIT_FILE(IMEM_INIT_FILE),
		.DMEM_INIT_FILE(DMEM_INIT_FILE),
		.en_alu_csr_rw_bypass(en_alu_csr_rw_bypass),
		.imem_baseaddr(imem_baseaddr),
		.imem_addr_range(imem_addr_range),
		.sgn_period_mul(sgn_period_mul),
		.simulation_delay(simulation_delay)
	)panda_risc_v_sim_u(
		.clk(clk),
		.ext_resetn(rst_n),
		
		.sw_reset(1'b0),
		
		.ibus_timeout(),
		.dbus_timeout(),
		
		.sw_itr_req(1'b0),
		.tmr_itr_req(1'b0),
		.ext_itr_req(1'b0)
	);
	
endmodule
