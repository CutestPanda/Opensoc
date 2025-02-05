`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class ApbClkCvtCase0MAPBSeq extends uvm_sequence #(APBTrans #(.addr_width(32), .data_width(32)));
	
	local APBTrans #(.addr_width(32), .data_width(32)) m_apb_trans; // APB主机事务
	
	// 注册object
	`uvm_object_utils(ApbClkCvtCase0MAPBSeq)
	
	localparam real CLK_P = 100.0;
	
	function new(string name = "ApbClkCvtCase0MAPBSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		# (CLK_P * 2);
		
		`uvm_do_with(this.m_apb_trans, {
			addr <= 1023;
			wdata <= 100;
		})
		
		`uvm_do_with(this.m_apb_trans, {
			addr <= 1023;
			wdata <= 100;
		})
		
		# (CLK_P * 40);
		
		`uvm_do_with(this.m_apb_trans, {
			addr <= 1023;
			wdata <= 100;
		})
		
		`uvm_do_with(this.m_apb_trans, {
			addr <= 1023;
			wdata <= 100;
		})
		
		`uvm_do_with(this.m_apb_trans, {
			addr <= 1023;
			wdata <= 100;
		})
		
		# (CLK_P * 30);
		
		`uvm_do_with(this.m_apb_trans, {
			addr <= 1023;
			wdata <= 100;
		})
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class ApbClkCvtCase0SAPBSeq extends uvm_sequence #(APBTrans #(.addr_width(32), .data_width(32)));
	
	local APBTrans #(.addr_width(32), .data_width(32)) s_apb_trans; // APB从机事务
	
	// 注册object
	`uvm_object_utils(ApbClkCvtCase0SAPBSeq)
	
	function new(string name = "ApbClkCvtCase0SAPBSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		repeat(6)
		begin
			`uvm_do_with(this.s_apb_trans, {
				rdata <= 100;
				
				wait_period_n <= 2;
			})
		end
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class ApbClkCvtCase0Test extends uvm_test;
	
	// APB时钟转换模块测试环境
	local ApbClkCvtEnv #(.out_drive_t(1)) env;
	
	// 注册component
	`uvm_component_utils(ApbClkCvtCase0Test)
	
	function new(string name = "ApbClkCvtCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = ApbClkCvtEnv #(.out_drive_t(1))::type_id::create("env", this); // 创建env
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			ApbClkCvtCase0MAPBSeq::type_id::get());
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt2.sqr.main_phase", 
			"default_sequence", 
			ApbClkCvtCase0SAPBSeq::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("ApbClkCvtCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
