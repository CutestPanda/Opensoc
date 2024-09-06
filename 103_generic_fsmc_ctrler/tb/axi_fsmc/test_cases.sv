`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class AXIFsmcCase0MAXISeq extends uvm_sequence #(AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2)));
	
	local AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2)) m_axi_trans; // AXI主机事务
	
	// 注册object
	`uvm_object_utils(AXIFsmcCase0MAXISeq)
	
	function new(string name = "AXIFsmcCase0MAXISeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		// 设置FSMC时序参数
		`uvm_create(this.m_axi_trans)
		this.m_axi_trans.is_rd_trans = 1'b0;
		this.m_axi_trans.data_n = 1;
		this.m_axi_trans.addr = 32'h0000_0000;
		this.m_axi_trans.len = 8'd0;
		this.m_axi_trans.size = 3'b001;
		this.m_axi_trans.addr_wait_period_n = 0;
		this.m_axi_trans.wdata.push_back({16'd0, 8'd1, 8'd1}); // 数据建立周期数 - 1, 地址建立周期数 - 1
		this.m_axi_trans.wlast.push_back(1'b1);
		this.m_axi_trans.wstrb.push_back(4'b1111);
		this.m_axi_trans.wdata_wait_period_n = new[1];
		this.m_axi_trans.wdata_wait_period_n[0] = 0;
		`uvm_send(this.m_axi_trans)
		
		`uvm_create(this.m_axi_trans)
		this.m_axi_trans.is_rd_trans = 1'b0;
		this.m_axi_trans.data_n = 1;
		this.m_axi_trans.addr = 32'h0000_0002;
		this.m_axi_trans.len = 8'd0;
		this.m_axi_trans.size = 3'b001;
		this.m_axi_trans.addr_wait_period_n = 0;
		this.m_axi_trans.wdata.push_back({8'd0, 8'd1, 16'd0}); // 数据保持周期数 - 1
		this.m_axi_trans.wlast.push_back(1'b1);
		this.m_axi_trans.wstrb.push_back(4'b1111);
		this.m_axi_trans.wdata_wait_period_n = new[1];
		this.m_axi_trans.wdata_wait_period_n[0] = 0;
		`uvm_send(this.m_axi_trans)
		
		// 继续运行1us
		# (10 ** 3);
		
		// 写FSMC地址0x10
		`uvm_create(this.m_axi_trans)
		this.m_axi_trans.is_rd_trans = 1'b0;
		this.m_axi_trans.data_n = 1;
		this.m_axi_trans.addr = 32'h0000_1010;
		this.m_axi_trans.len = 8'd0;
		this.m_axi_trans.size = 3'b001;
		this.m_axi_trans.addr_wait_period_n = 0;
		this.m_axi_trans.wdata.push_back({16'd0, 16'hFFAA}); // 写数据0xFFAA
		this.m_axi_trans.wlast.push_back(1'b1);
		this.m_axi_trans.wstrb.push_back(4'b0110);
		this.m_axi_trans.wdata_wait_period_n = new[1];
		this.m_axi_trans.wdata_wait_period_n[0] = 0;
		`uvm_send(this.m_axi_trans)
		
		// 读FSMC地址0x12
		`uvm_create(this.m_axi_trans)
		this.m_axi_trans.is_rd_trans = 1'b1;
		this.m_axi_trans.data_n = 1;
		this.m_axi_trans.addr = 32'h0000_1012;
		this.m_axi_trans.len = 8'd0;
		this.m_axi_trans.size = 3'b001;
		this.m_axi_trans.addr_wait_period_n = 0;
		`uvm_send(this.m_axi_trans)
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class AXIFsmcCase0Test extends uvm_test;
	
	local AXIFsmcEnv env; // AXI-Fsmc测试环境
	
	// 注册component
	`uvm_component_utils(AXIFsmcCase0Test)
	
	function new(string name = "AXIFsmcCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = AXIFsmcEnv::type_id::create("env", this); // 创建env
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt.sqr.main_phase", 
			"default_sequence", 
			AXIFsmcCase0MAXISeq::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("AXIFsmcCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
