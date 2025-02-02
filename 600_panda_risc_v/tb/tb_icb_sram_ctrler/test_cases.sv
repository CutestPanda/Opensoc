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

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class ICBSramCtrlerCase0MICBSeq extends uvm_sequence #(ICBTrans #(.addr_width(32), .data_width(32)));
	
	local ICBTrans #(.addr_width(32), .data_width(32)) m_icb_trans; // icb主机事务
	
	// 注册object
	`uvm_object_utils(ICBSramCtrlerCase0MICBSeq)
	
	function new(string name = "ICBSramCtrlerCase0MICBSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		repeat(10)
		begin
			`uvm_do_with(this.m_icb_trans, {
				cmd_addr[31:2] <= 512;
				cmd_addr[1:0] dist{0:/4, [1:3]:/1};
				cmd_read == 1'b0;
				cmd_wmask dist{4'b1111:/4, 4'b1110:/1, 4'b1100:/1, 4'b1000:/1};
				cmd_wait_period_n dist {0:/3, [1:2]:/1};
				rsp_wait_period_n dist {0:/3, [1:2]:/1};
			})
		end
		
		`uvm_do_with(this.m_icb_trans, {
			cmd_addr[31:2] <= 512;
			cmd_addr[1:0] dist{0:/4, [1:3]:/1};
			cmd_read == 1'b1;
			cmd_wmask dist{4'b1111:/4, 4'b1110:/1, 4'b1100:/1, 4'b1000:/1};
			cmd_wait_period_n == 0;
			rsp_wait_period_n == 0;
		})
		
		repeat(9)
		begin
			`uvm_do_with(this.m_icb_trans, {
				cmd_addr[31:2] <= 512;
				cmd_addr[1:0] dist{0:/4, [1:3]:/1};
				cmd_read == 1'b1;
				cmd_wmask dist{4'b1111:/4, 4'b1110:/1, 4'b1100:/1, 4'b1000:/1};
				cmd_wait_period_n dist {0:/3, [1:2]:/1};
				rsp_wait_period_n dist {0:/3, [1:2]:/1};
			})
		end
		
		`uvm_do_with(this.m_icb_trans, {
			cmd_addr[31:2] <= 512;
			cmd_addr[1:0] dist{0:/4, [1:3]:/1};
			cmd_read == 1'b0;
			cmd_wmask dist{4'b1111:/4, 4'b1110:/1, 4'b1100:/1, 4'b1000:/1};
			cmd_wait_period_n == 0;
			rsp_wait_period_n == 0;
		})
		
		repeat(9)
		begin
			`uvm_do_with(this.m_icb_trans, {
				cmd_addr[31:2] <= 512;
				cmd_addr[1:0] dist{0:/4, [1:3]:/1};
				cmd_wmask dist{4'b1111:/4, 4'b1110:/1, 4'b1100:/1, 4'b1000:/1};
				cmd_wait_period_n dist {0:/3, [1:2]:/1};
				rsp_wait_period_n dist {0:/3, [1:2]:/1};
			})
		end
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class ICBSramCtrlerCase0Test extends uvm_test;
	
	// ICB-SRAM控制器测试环境
	local ICBSramCtrlerEnv env;
	
	// 注册component
	`uvm_component_utils(ICBSramCtrlerCase0Test)
	
	function new(string name = "ICBSramCtrlerCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = ICBSramCtrlerEnv::type_id::create("env", this); // 创建env
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			ICBSramCtrlerCase0MICBSeq::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("ICBSramCtrlerCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
