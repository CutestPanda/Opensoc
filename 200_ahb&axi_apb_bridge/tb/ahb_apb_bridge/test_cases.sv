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

class AHBAPBBridgeCase0SAPBSeq extends uvm_sequence #(APBTrans #(.addr_width(32), .data_width(32)));
	
	local APBTrans #(.addr_width(32), .data_width(32)) s_apb_trans; // APB从机事务
	
	// 注册object
	`uvm_object_utils(AHBAPBBridgeCase0SAPBSeq)
	
	function new(string name = "AHBAPBBridgeCase0SAPBSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		// 产生4个APB从机事务
		`uvm_create(this.s_apb_trans)
		this.s_apb_trans.rdata = 1;
		this.s_apb_trans.slverr = 1'b0;
		this.s_apb_trans.wait_period_n = 2;
		`uvm_send(this.s_apb_trans)
		`uvm_create(this.s_apb_trans)
		this.s_apb_trans.rdata = 2;
		this.s_apb_trans.slverr = 1'b0;
		this.s_apb_trans.wait_period_n = 1;
		`uvm_send(this.s_apb_trans)
		`uvm_create(this.s_apb_trans)
		this.s_apb_trans.rdata = 3;
		this.s_apb_trans.slverr = 1'b0;
		this.s_apb_trans.wait_period_n = 0;
		`uvm_send(this.s_apb_trans)
		`uvm_create(this.s_apb_trans)
		this.s_apb_trans.rdata = 4;
		this.s_apb_trans.slverr = 1'b0;
		this.s_apb_trans.wait_period_n = 0;
		`uvm_send(this.s_apb_trans)
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class AHBAPBBridgeCase0MAHBSeq extends uvm_sequence #(AHBTrans #(.addr_width(32), .data_width(32), 
	.burst_width(3), .prot_width(4), .master_width(1)));
	
	local AHBTrans #(.addr_width(32), .data_width(32), 
		.burst_width(3), .prot_width(4), .master_width(1)) m_ahb_trans; // AHB主机事务
	
	// 注册object
	`uvm_object_utils(AHBAPBBridgeCase0MAHBSeq)
	
	function new(string name = "AHBAPBBridgeCase0MAHBSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		// 产生8个AHB主机事务
		`uvm_create(this.m_ahb_trans)
		this.m_ahb_trans.haddr = 0;
		this.m_ahb_trans.hburst = 3'b000;
		this.m_ahb_trans.hsize = 3'b010;
		this.m_ahb_trans.hwrite = 1'b0;
		this.m_ahb_trans.wait_period_n = new[1];
		this.m_ahb_trans.wait_period_n[0] = 1;
		`uvm_send(this.m_ahb_trans)
		`uvm_create(this.m_ahb_trans)
		this.m_ahb_trans.haddr = 4096;
		this.m_ahb_trans.hburst = 3'b000;
		this.m_ahb_trans.hsize = 3'b010;
		this.m_ahb_trans.hwrite = 1'b1;
		this.m_ahb_trans.hwdata.push_back(1);
		this.m_ahb_trans.hwstrb.push_back(4'b1111);
		this.m_ahb_trans.wait_period_n = new[1];
		this.m_ahb_trans.wait_period_n[0] = 0;
		`uvm_send(this.m_ahb_trans)
		`uvm_create(this.m_ahb_trans)
		this.m_ahb_trans.haddr = 0 + 4;
		this.m_ahb_trans.hburst = 3'b000;
		this.m_ahb_trans.hsize = 3'b010;
		this.m_ahb_trans.hwrite = 1'b0;
		this.m_ahb_trans.wait_period_n = new[1];
		this.m_ahb_trans.wait_period_n[0] = 0;
		`uvm_send(this.m_ahb_trans)
		`uvm_create(this.m_ahb_trans)
		this.m_ahb_trans.haddr = 4096 + 4;
		this.m_ahb_trans.hburst = 3'b000;
		this.m_ahb_trans.hsize = 3'b010;
		this.m_ahb_trans.hwrite = 1'b1;
		this.m_ahb_trans.hwdata.push_back(2);
		this.m_ahb_trans.hwstrb.push_back(4'b1111);
		this.m_ahb_trans.wait_period_n = new[1];
		this.m_ahb_trans.wait_period_n[0] = 1;
		`uvm_send(this.m_ahb_trans)
		`uvm_create(this.m_ahb_trans)
		this.m_ahb_trans.haddr = 0 + 8;
		this.m_ahb_trans.hburst = 3'b000;
		this.m_ahb_trans.hsize = 3'b010;
		this.m_ahb_trans.hwrite = 1'b0;
		this.m_ahb_trans.wait_period_n = new[1];
		this.m_ahb_trans.wait_period_n[0] = 0;
		`uvm_send(this.m_ahb_trans)
		`uvm_create(this.m_ahb_trans)
		this.m_ahb_trans.haddr = 4096 + 8;
		this.m_ahb_trans.hburst = 3'b000;
		this.m_ahb_trans.hsize = 3'b010;
		this.m_ahb_trans.hwrite = 1'b1;
		this.m_ahb_trans.hwdata.push_back(3);
		this.m_ahb_trans.hwstrb.push_back(4'b1111);
		this.m_ahb_trans.wait_period_n = new[1];
		this.m_ahb_trans.wait_period_n[0] = 2;
		`uvm_send(this.m_ahb_trans)
		`uvm_create(this.m_ahb_trans)
		this.m_ahb_trans.haddr = 0 + 12;
		this.m_ahb_trans.hburst = 3'b000;
		this.m_ahb_trans.hsize = 3'b010;
		this.m_ahb_trans.hwrite = 1'b1;
		this.m_ahb_trans.hwdata.push_back(4);
		this.m_ahb_trans.hwstrb.push_back(4'b1111);
		this.m_ahb_trans.wait_period_n = new[1];
		this.m_ahb_trans.wait_period_n[0] = 3;
		`uvm_send(this.m_ahb_trans)
		`uvm_create(this.m_ahb_trans)
		this.m_ahb_trans.haddr = 4096 + 12;
		this.m_ahb_trans.hburst = 3'b000;
		this.m_ahb_trans.hsize = 3'b010;
		this.m_ahb_trans.hwrite = 1'b1;
		this.m_ahb_trans.hwdata.push_back(5);
		this.m_ahb_trans.hwstrb.push_back(4'b1111);
		this.m_ahb_trans.wait_period_n = new[1];
		this.m_ahb_trans.wait_period_n[0] = 0;
		`uvm_send(this.m_ahb_trans)
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class AHBAPBBridgeCase0Test extends uvm_test;
	
	local AHBAPBBridgeEnv env; // AHB-APB桥测试环境
	
	// 注册component
	`uvm_component_utils(AHBAPBBridgeCase0Test)
	
	function new(string name = "AHBAPBBridgeCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = AHBAPBBridgeEnv::type_id::create("env", this); // 创建env
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			AHBAPBBridgeCase0SAPBSeq::type_id::get());
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt2.sqr.main_phase", 
			"default_sequence", 
			AHBAPBBridgeCase0SAPBSeq::type_id::get());
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt3.sqr.main_phase", 
			"default_sequence", 
			AHBAPBBridgeCase0MAHBSeq::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("AHBAPBBridgeCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
