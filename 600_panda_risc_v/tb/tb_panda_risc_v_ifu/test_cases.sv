`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class PandaRiscVIfuCase0Test extends uvm_test;
	
	// 小胖达risc-v取指单元测试环境
	local PandaRiscVIfuEnv env;
	
	// 注册component
	`uvm_component_utils(PandaRiscVIfuCase0Test)
	
	function new(string name = "PandaRiscVIfuCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = PandaRiscVIfuEnv::type_id::create("env", this); // 创建env
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		phase.raise_objection(this);
		
		# (200 * 1000); // 运行200us
		
		phase.drop_objection(this);
	endtask
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("PandaRiscVIfuCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
