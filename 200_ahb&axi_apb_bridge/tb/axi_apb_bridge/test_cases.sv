`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class AXIAPBBridgeCase0SAPBSeq extends uvm_sequence #(APBTrans #(.addr_width(32), .data_width(32)));
	
	local APBTrans #(.addr_width(32), .data_width(32)) s_apb_trans; // APB从机事务
	
	// 注册object
	`uvm_object_utils(AXIAPBBridgeCase0SAPBSeq)
	
	function new(string name = "AXIAPBBridgeCase0SAPBSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		// 产生4个APB从机事务
		`uvm_create(this.s_apb_trans)
		this.s_apb_trans.rdata = 1;
		this.s_apb_trans.slverr = 1'b0;
		this.s_apb_trans.wait_period_n = 0;
		`uvm_send(this.s_apb_trans)
		`uvm_create(this.s_apb_trans)
		this.s_apb_trans.rdata = 2;
		this.s_apb_trans.slverr = 1'b0;
		this.s_apb_trans.wait_period_n = 0;
		`uvm_send(this.s_apb_trans)
		`uvm_create(this.s_apb_trans)
		this.s_apb_trans.rdata = 3;
		this.s_apb_trans.slverr = 1'b0;
		this.s_apb_trans.wait_period_n = 1;
		`uvm_send(this.s_apb_trans)
		`uvm_create(this.s_apb_trans)
		this.s_apb_trans.rdata = 4;
		this.s_apb_trans.slverr = 1'b0;
		this.s_apb_trans.wait_period_n = 2;
		`uvm_send(this.s_apb_trans)
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class AXIAPBBridgeCase0MAHBSeq extends uvm_sequence #(AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2)));
	
	local AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2)) m_axi_trans; // AXI主机事务
	
	// 注册object
	`uvm_object_utils(AXIAPBBridgeCase0MAHBSeq)
	
	function new(string name = "AXIAPBBridgeCase0MAHBSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		// #0
		`uvm_create(this.m_axi_trans)
		this.m_axi_trans.is_rd_trans = 1'b0;
		this.m_axi_trans.data_n = 1;
		this.m_axi_trans.addr = 32'h0000_0000;
		this.m_axi_trans.len = 8'd0;
		this.m_axi_trans.size = 3'b010;
		this.m_axi_trans.addr_wait_period_n = 0;
		this.m_axi_trans.wdata.push_back(32'h01_02_03_04);
		this.m_axi_trans.wlast.push_back(1'b1);
		this.m_axi_trans.wstrb.push_back(4'b1111);
		this.m_axi_trans.wdata_wait_period_n = new[1];
		this.m_axi_trans.wdata_wait_period_n[0] = 0;
		`uvm_send(this.m_axi_trans)
		
		# (10 ** 3);
		
		// #1
		`uvm_create(this.m_axi_trans)
		this.m_axi_trans.is_rd_trans = 1'b0;
		this.m_axi_trans.data_n = 1;
		this.m_axi_trans.addr = 32'h0000_1000;
		this.m_axi_trans.len = 8'd0;
		this.m_axi_trans.size = 3'b010;
		this.m_axi_trans.addr_wait_period_n = 0;
		this.m_axi_trans.wdata.push_back(32'h05_06_07_08);
		this.m_axi_trans.wlast.push_back(1'b1);
		this.m_axi_trans.wstrb.push_back(4'b1111);
		this.m_axi_trans.wdata_wait_period_n = new[1];
		this.m_axi_trans.wdata_wait_period_n[0] = 0;
		`uvm_send(this.m_axi_trans)
		
		# (10 ** 3);
		
		// #2
		`uvm_create(this.m_axi_trans)
		this.m_axi_trans.is_rd_trans = 1'b1;
		this.m_axi_trans.data_n = 1;
		this.m_axi_trans.addr = 32'h0000_0000;
		this.m_axi_trans.len = 8'd0;
		this.m_axi_trans.size = 3'b010;
		this.m_axi_trans.addr_wait_period_n = 0;
		`uvm_send(this.m_axi_trans)
		
		# (10 ** 3);
		
		// #3
		`uvm_create(this.m_axi_trans)
		this.m_axi_trans.is_rd_trans = 1'b1;
		this.m_axi_trans.data_n = 1;
		this.m_axi_trans.addr = 32'h0000_1000;
		this.m_axi_trans.len = 8'd0;
		this.m_axi_trans.size = 3'b010;
		this.m_axi_trans.addr_wait_period_n = 0;
		`uvm_send(this.m_axi_trans)
		
		# (10 ** 3);
		
		// #4
		`uvm_create(this.m_axi_trans)
		this.m_axi_trans.is_rd_trans = 1'b0;
		this.m_axi_trans.data_n = 1;
		this.m_axi_trans.addr = 32'h0000_0010;
		this.m_axi_trans.len = 8'd0;
		this.m_axi_trans.size = 3'b010;
		this.m_axi_trans.addr_wait_period_n = 3;
		this.m_axi_trans.wdata.push_back(32'h01_02_03_04);
		this.m_axi_trans.wlast.push_back(1'b1);
		this.m_axi_trans.wstrb.push_back(4'b1111);
		this.m_axi_trans.wdata_wait_period_n = new[1];
		this.m_axi_trans.wdata_wait_period_n[0] = 5;
		`uvm_send(this.m_axi_trans)
		
		# (10 ** 3);
		
		// #5
		`uvm_create(this.m_axi_trans)
		this.m_axi_trans.is_rd_trans = 1'b0;
		this.m_axi_trans.data_n = 1;
		this.m_axi_trans.addr = 32'h0000_1010;
		this.m_axi_trans.len = 8'd0;
		this.m_axi_trans.size = 3'b010;
		this.m_axi_trans.addr_wait_period_n = 2;
		this.m_axi_trans.wdata.push_back(32'h05_06_07_08);
		this.m_axi_trans.wlast.push_back(1'b1);
		this.m_axi_trans.wstrb.push_back(4'b1111);
		this.m_axi_trans.wdata_wait_period_n = new[1];
		this.m_axi_trans.wdata_wait_period_n[0] = 3;
		`uvm_send(this.m_axi_trans)
		
		# (10 ** 3);
		
		// #6
		`uvm_create(this.m_axi_trans)
		this.m_axi_trans.is_rd_trans = 1'b1;
		this.m_axi_trans.data_n = 1;
		this.m_axi_trans.addr = 32'h0000_0020;
		this.m_axi_trans.len = 8'd0;
		this.m_axi_trans.size = 3'b010;
		this.m_axi_trans.addr_wait_period_n = 5;
		`uvm_send(this.m_axi_trans)
		
		# (10 ** 3);
		
		// #7
		`uvm_create(this.m_axi_trans)
		this.m_axi_trans.is_rd_trans = 1'b1;
		this.m_axi_trans.data_n = 1;
		this.m_axi_trans.addr = 32'h0000_1020;
		this.m_axi_trans.len = 8'd0;
		this.m_axi_trans.size = 3'b010;
		this.m_axi_trans.addr_wait_period_n = 6;
		`uvm_send(this.m_axi_trans)
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class AXIAPBBridgeCase0Test extends uvm_test;
	
	local AXIAPBBridgeEnv env; // AHB-APB桥测试环境
	
	// 注册component
	`uvm_component_utils(AXIAPBBridgeCase0Test)
	
	function new(string name = "AXIAPBBridgeCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = AXIAPBBridgeEnv::type_id::create("env", this); // 创建env
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			AXIAPBBridgeCase0SAPBSeq::type_id::get());
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt2.sqr.main_phase", 
			"default_sequence", 
			AXIAPBBridgeCase0SAPBSeq::type_id::get());
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt3.sqr.main_phase", 
			"default_sequence", 
			AXIAPBBridgeCase0MAHBSeq::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("AXIAPBBridgeCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
