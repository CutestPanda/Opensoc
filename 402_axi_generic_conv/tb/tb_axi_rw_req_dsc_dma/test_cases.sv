`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class AxiRdReqDscDmaCase0Test extends uvm_test;
	
	// 用于获取读请求描述子的AXI读通道测试环境
	local AxiRdReqDscDmaEnv env;
	
	// 注册component
	`uvm_component_utils(AxiRdReqDscDmaCase0Test)
	
	function new(string name = "AxiRdReqDscDmaCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = AxiRdReqDscDmaEnv::type_id::create("env", this); // 创建env
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		phase.raise_objection(this);
		
		# (1000 * 1000); // 运行1ms
		
		phase.drop_objection(this);
	endtask
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("AxiRdReqDscDmaCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
