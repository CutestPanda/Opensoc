`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class JtagDtmCase0SAPBSeq extends uvm_sequence #(APBTrans #(.addr_width(32), .data_width(32)));
	
	local APBTrans #(.addr_width(32), .data_width(32)) s_apb_trans; // APB从机事务
	
	// 注册object
	`uvm_object_utils(JtagDtmCase0SAPBSeq)
	
	function new(string name = "JtagDtmCase0SAPBSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		repeat(2)
		begin
			`uvm_do_with(this.s_apb_trans, {
				rdata <= 100;
				slverr == 1'b0;
				
				wait_period_n <= 2;
			})
		end
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class JtagDtmCase0Test extends uvm_test;
	
	// DTM测试环境
	local JtagDtmEnv #(.out_drive_t(1)) env;
	
	// 注册component
	`uvm_component_utils(JtagDtmCase0Test)
	
	function new(string name = "JtagDtmCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = JtagDtmEnv #(.out_drive_t(1))::type_id::create("env", this); // 创建env
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			JtagDtmCase0SAPBSeq::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("JtagDtmCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
