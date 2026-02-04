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

module tb_isa_test();
	
	/** 配置参数 **/
	// ISA测试配置
	parameter integer TO_HOST_ADDR1 = 32'h3000;
	parameter integer IMEM_DEPTH = 8 * 1024; // 指令存储器深度
	parameter integer DMEM_DEPTH = 8 * 1024; // 数据存储器深度
<<<<<<< HEAD
	// parameter IMEM_INIT_FILE = "../coremark_sim.txt"; // 指令存储器的初始化文件路径
	// parameter DMEM_INIT_FILE = "no_init"; // 数据存储器的初始化文件路径
=======
>>>>>>> f159a4e146763038aa92fc830492fdebb5e4464f
	parameter IMEM_INIT_FILE = "test_compiled/rv32ui-p-ld_st.mem"; // 指令存储器的初始化文件路径
	parameter DMEM_INIT_FILE = "test_compiled/rv32ui-p-ld_st.mem"; // 数据存储器的初始化文件路径
	// 待测模块配置
	parameter integer IBUS_ACCESS_TIMEOUT_TH = 16; // 指令总线访问超时周期数(0 -> 不设超时 | 正整数)
	parameter integer IBUS_OUTSTANDING_N = 4; // 指令总线滞外深度(1 | 2 | 4 | 8)
	parameter integer MEM_ACCESS_TIMEOUT_TH = 0; // 存储器访问超时周期数(0 -> 不设超时 | 正整数)
	parameter integer PERPH_ACCESS_TIMEOUT_TH = 32; // 外设访问超时周期数(0 -> 不设超时 | 正整数)
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
	
	/** ISA测试 **/
<<<<<<< HEAD
	// 指令总线(AW通道)
	wire[31:0] m_axi_imem_awaddr;
	wire m_axi_imem_awvalid;
	wire m_axi_imem_awready;
=======
	// 指令总线
	wire[31:0] m_icb_cmd_inst_addr;
	wire m_icb_cmd_inst_valid;
	wire m_icb_cmd_inst_ready;
>>>>>>> f159a4e146763038aa92fc830492fdebb5e4464f
	// 寄存器堆
	wire[31:0] x3;
	// CSR
	wire[31:0] minstret;
	wire[31:0] mcycle;
	
<<<<<<< HEAD
	assign m_axi_imem_awaddr = panda_risc_v_sim_u.m_axi_imem_awaddr;
	assign m_axi_imem_awvalid = panda_risc_v_sim_u.m_axi_imem_awvalid;
	assign m_axi_imem_awready = panda_risc_v_sim_u.m_axi_imem_awready;
=======
	assign m_icb_cmd_inst_addr = panda_risc_v_sim_u.m_icb_cmd_inst_addr;
	assign m_icb_cmd_inst_valid = panda_risc_v_sim_u.m_icb_cmd_inst_valid;
	assign m_icb_cmd_inst_ready = panda_risc_v_sim_u.m_icb_cmd_inst_ready;
>>>>>>> f159a4e146763038aa92fc830492fdebb5e4464f
	
	assign x3 = panda_risc_v_sim_u.panda_risc_v_u.generic_reg_file_u.generic_reg_file[3];
	
	assign minstret = panda_risc_v_sim_u.panda_risc_v_u.csr_u.minstret_minstret;
	assign mcycle = panda_risc_v_sim_u.panda_risc_v_u.csr_u.mcycle_mcycle;
	
	initial
	begin
		$display("test running...");
		
<<<<<<< HEAD
		wait(((m_axi_imem_awvalid & m_axi_imem_awready) === 1'b1) && (m_axi_imem_awaddr === TO_HOST_ADDR1));
=======
		wait(((m_icb_cmd_inst_valid & m_icb_cmd_inst_ready) === 1'b1) && (m_icb_cmd_inst_addr === TO_HOST_ADDR1));
>>>>>>> f159a4e146763038aa92fc830492fdebb5e4464f
		
        # (clk_p * 10);
		
		$display("minstret=%0d", minstret);
		$display("mcycle=%0d", mcycle);
<<<<<<< HEAD
		$display("ipc=%0f", real'(minstret)/real'(mcycle));
=======
>>>>>>> f159a4e146763038aa92fc830492fdebb5e4464f
		
        if(x3 == 1)
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
		.MEM_ACCESS_TIMEOUT_TH(MEM_ACCESS_TIMEOUT_TH),
		.PERPH_ACCESS_TIMEOUT_TH(PERPH_ACCESS_TIMEOUT_TH),
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
		
		.clr_inst_buf_while_suppressing(),
		.ibus_timeout(),
		.rd_mem_timeout(),
		.wr_mem_timeout(),
		.perph_access_timeout(),
		
		.sw_itr_req(1'b0),
		.tmr_itr_req(1'b0),
		.ext_itr_req(1'b0)
	);
	
endmodule
