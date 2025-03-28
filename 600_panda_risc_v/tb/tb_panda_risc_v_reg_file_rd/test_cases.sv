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

class PandaRiscVRegFileRdCase0MAXISSeq extends uvm_sequence #(AXISTrans #(.data_width(16), .user_width(0)));
	
	local AXISTrans #(.data_width(16), .user_width(0)) m_axis_trans; // AXIS主机事务
	
	// 注册object
	`uvm_object_utils(PandaRiscVRegFileRdCase0MAXISSeq)
	
	function new(string name = "PandaRiscVRegFileRdCase0MAXISSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		repeat(50)
		begin
			`uvm_do_with(this.m_axis_trans, {
				data_n == 1;
				
				data.size() == 1;
				keep.size() == 1;
				strb.size() == 1;
				user.size() == 1;
				last.size() == 1;
				wait_period_n.size() == 1;
				
				last[0] == 1'b1;
				
				wait_period_n[0] dist {0:/3, 1:/1, 2:/1};
			})
		end
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class PandaRiscVRegFileRdCase0Test extends uvm_test;
	
	// 小胖达risc-v译码阶段的通用寄存器读控制测试环境
	local PandaRiscVRegFileRdEnv env;
	
	// 注册component
	`uvm_component_utils(PandaRiscVRegFileRdCase0Test)
	
	function new(string name = "PandaRiscVRegFileRdCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = PandaRiscVRegFileRdEnv::type_id::create("env", this); // 创建env
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			PandaRiscVRegFileRdCase0MAXISSeq::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("PandaRiscVRegFileRdCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
