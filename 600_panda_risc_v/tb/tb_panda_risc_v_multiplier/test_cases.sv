`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class MulCase0SAXISSeq extends uvm_sequence #(AXISTrans #(.data_width(72), .user_width(0)));
	
	local AXISTrans #(.data_width(72), .user_width(0)) m_axis_trans; // AXIS主机事务
	
	// 注册object
	`uvm_object_utils(MulCase0SAXISSeq)
	
	function new(string name = "MulCase0SAXISSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		repeat(100)
		begin
			`uvm_do_with(this.m_axis_trans, {
				data_n == 1;
				
				data.size() == 1;
				last.size() == 1;
				
				wait_period_n.size() == 1;
				
				($signed(data[0][32:0]) >= -100) && ($signed(data[0][32:0]) <= 100);
				($signed(data[0][65:33]) >= -100) && ($signed(data[0][65:33]) <= 100);
				
				last[0] == 1'b1;
				wait_period_n[0] <= 2;
			})
		end
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class MulCase0Test extends uvm_test;
	
	// 多周期乘法器测试环境
	local MulEnv #(.s_axis_data_width(72), .m_axis_data_width(48)) env;
	
	// 注册component
	`uvm_component_utils(MulCase0Test)
	
	function new(string name = "MulCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = MulEnv #(.s_axis_data_width(72), .m_axis_data_width(48))
			::type_id::create("env", this); // 创建env
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			MulCase0SAXISSeq::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("MulCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
