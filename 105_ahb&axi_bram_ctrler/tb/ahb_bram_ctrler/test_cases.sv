`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class AHBBramCtrlerCase0MAHBSeq extends uvm_sequence #(AHBTrans #(.addr_width(32), .data_width(32), 
	.burst_width(3), .prot_width(4), .master_width(1)));
	
	local AHBTrans #(.addr_width(32), .data_width(32), 
		.burst_width(3), .prot_width(4), .master_width(1)) m_ahb_trans; // AHB主机事务
	
	// 注册object
	`uvm_object_utils(AHBBramCtrlerCase0MAHBSeq)
	
	function new(string name = "AHBBramCtrlerCase0MAHBSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		`uvm_create(this.m_ahb_trans)
		this.m_ahb_trans.haddr = 0;
		this.m_ahb_trans.hburst = 3'b001;
		this.m_ahb_trans.hsize = 3'b010;
		this.m_ahb_trans.hwrite = 1'b1;
		this.m_ahb_trans.hwdata.push_back(1);
		this.m_ahb_trans.hwstrb.push_back(4'b1111);
		this.m_ahb_trans.hwdata.push_back(2);
		this.m_ahb_trans.hwstrb.push_back(4'b1110);
		this.m_ahb_trans.hwdata.push_back(3);
		this.m_ahb_trans.hwstrb.push_back(4'b1101);
		this.m_ahb_trans.hwdata.push_back(4);
		this.m_ahb_trans.hwstrb.push_back(4'b1011);
		this.m_ahb_trans.hwdata.push_back(5);
		this.m_ahb_trans.hwstrb.push_back(4'b0111);
		this.m_ahb_trans.wait_period_n = new[5];
		this.m_ahb_trans.wait_period_n[0] = 1;
		this.m_ahb_trans.wait_period_n[1] = 0;
		this.m_ahb_trans.wait_period_n[2] = 1;
		this.m_ahb_trans.wait_period_n[3] = 2;
		this.m_ahb_trans.wait_period_n[4] = 0;
		`uvm_send(this.m_ahb_trans)
		
		`uvm_create(this.m_ahb_trans)
		this.m_ahb_trans.haddr = 100;
		this.m_ahb_trans.hburst = 3'b001;
		this.m_ahb_trans.hsize = 3'b010;
		this.m_ahb_trans.hwrite = 1'b0;
		this.m_ahb_trans.wait_period_n = new[4];
		this.m_ahb_trans.wait_period_n[0] = 0;
		this.m_ahb_trans.wait_period_n[1] = 1;
		this.m_ahb_trans.wait_period_n[2] = 2;
		this.m_ahb_trans.wait_period_n[3] = 0;
		`uvm_send(this.m_ahb_trans)
		
		`uvm_create(this.m_ahb_trans)
		this.m_ahb_trans.haddr = 200;
		this.m_ahb_trans.hburst = 3'b001;
		this.m_ahb_trans.hsize = 3'b010;
		this.m_ahb_trans.hwrite = 1'b1;
		this.m_ahb_trans.hwdata.push_back(6);
		this.m_ahb_trans.hwstrb.push_back(4'b1111);
		this.m_ahb_trans.hwdata.push_back(7);
		this.m_ahb_trans.hwstrb.push_back(4'b1110);
		this.m_ahb_trans.hwdata.push_back(8);
		this.m_ahb_trans.hwstrb.push_back(4'b1101);
		this.m_ahb_trans.wait_period_n = new[3];
		this.m_ahb_trans.wait_period_n[0] = 0;
		this.m_ahb_trans.wait_period_n[1] = 1;
		this.m_ahb_trans.wait_period_n[2] = 2;
		`uvm_send(this.m_ahb_trans)
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class AHBBramCtrlerCase0Test extends uvm_test;
	
	local AHBBramCtrlerEnv env; // AHB-APB桥测试环境
	
	// 注册component
	`uvm_component_utils(AHBBramCtrlerCase0Test)
	
	function new(string name = "AHBBramCtrlerCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = AHBBramCtrlerEnv::type_id::create("env", this); // 创建env
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt.sqr.main_phase", 
			"default_sequence", 
			AHBBramCtrlerCase0MAHBSeq::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("AHBBramCtrlerCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
