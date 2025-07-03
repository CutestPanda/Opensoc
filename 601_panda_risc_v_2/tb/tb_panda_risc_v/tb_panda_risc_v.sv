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
	parameter IMEM_INIT_FILE = "E:/RTL/design/panda_risc_v/tb/tb_panda_risc_v/inst_test/rv32ui-p-add.txt"; // 指令存储器的初始化文件路径
	parameter DMEM_INIT_FILE = "E:/RTL/design/panda_risc_v/tb/tb_panda_risc_v/inst_test/rv32ui-p-add.txt"; // 数据存储器的初始化文件路径
	parameter integer IBUS_ACCESS_TIMEOUT_TH = 16; // 指令总线访问超时周期数(0 -> 不设超时 | 正整数)
	parameter integer IBUS_OUTSTANDING_N = 4; // 指令总线滞外深度(1 | 2 | 4 | 8)
	parameter integer DBUS_ACCESS_TIMEOUT_TH = 1024; // 数据总线访问超时周期数(必须>=1)
	parameter integer GHR_WIDTH = 8; // 全局分支历史寄存器的位宽(<=16)
	parameter integer BTB_WAY_N = 2; // BTB路数(1 | 2 | 4)
	parameter integer BTB_ENTRY_N = 512; // BTB项数(<=65536)
	parameter integer RAS_ENTRY_N = 4; // 返回地址堆栈的条目数(2 | 4 | 8 | 16)
	parameter EN_SGN_PERIOD_MUL = "true"; // 是否使用单周期乘法器
	parameter integer ROB_ENTRY_N = 8; // 重排序队列项数(4 | 8 | 16 | 32)
	parameter integer CSR_RW_RCD_SLOTS_N = 2; // CSR读写指令信息记录槽位数(2 | 4 | 8 | 16 | 32)
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
	
	assign x3 = panda_risc_v_sim_u.panda_risc_v_u.generic_reg_file_u.generic_reg_file[3];
	assign x26 = panda_risc_v_sim_u.panda_risc_v_u.generic_reg_file_u.generic_reg_file[26];
	assign x27 = panda_risc_v_sim_u.panda_risc_v_u.generic_reg_file_u.generic_reg_file[27];
	
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
					panda_risc_v_sim_u.panda_risc_v_u.generic_reg_file_u.generic_reg_file[i]);
			end
        end
	end
	
	/** 待测模块 **/
	panda_risc_v_sim #(
		.IMEM_DEPTH(IMEM_DEPTH),
		.DMEM_DEPTH(DMEM_DEPTH),
		.IMEM_INIT_FILE(IMEM_INIT_FILE),
		.DMEM_INIT_FILE(DMEM_INIT_FILE),
		.IBUS_ACCESS_TIMEOUT_TH(IBUS_ACCESS_TIMEOUT_TH),
		.IBUS_OUTSTANDING_N(IBUS_OUTSTANDING_N),
		.DBUS_ACCESS_TIMEOUT_TH(DBUS_ACCESS_TIMEOUT_TH),
		.GHR_WIDTH(GHR_WIDTH),
		.BTB_WAY_N(BTB_WAY_N),
		.BTB_ENTRY_N(BTB_ENTRY_N),
		.RAS_ENTRY_N(RAS_ENTRY_N),
		.EN_SGN_PERIOD_MUL(EN_SGN_PERIOD_MUL),
		.ROB_ENTRY_N(ROB_ENTRY_N),
		.CSR_RW_RCD_SLOTS_N(CSR_RW_RCD_SLOTS_N),
		.SIM_DELAY(simulation_delay)
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
