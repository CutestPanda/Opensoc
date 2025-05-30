`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class AxiDmaEngineMM2SCase0SAXISSeq extends uvm_sequence #(AXISTrans #(.data_width(56), .user_width(1)));
	
	local AXISTrans #(.data_width(56), .user_width(1)) m_axis_trans; // AXIS主机事务
	
	// 注册object
	`uvm_object_utils(AxiDmaEngineMM2SCase0SAXISSeq)
	
	function new(string name = "AxiDmaEngineMM2SCase0SAXISSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		// 传输字节数 = 104, 基地址 = 4000, 递增突发, 等待周期数 = 0
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		
		this.m_axis_trans.data.push_back({24'd104, 32'd4000});
		this.m_axis_trans.user.push_back(1'b0);
		this.m_axis_trans.last.push_back(1'b1);
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 0;
		`uvm_send(this.m_axis_trans)
		
		// 传输字节数 = 50, 基地址 = 4104, 递增突发, 等待周期数 = 0
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		
		this.m_axis_trans.data.push_back({24'd50, 32'd4104});
		this.m_axis_trans.user.push_back(1'b0);
		this.m_axis_trans.last.push_back(1'b1);
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 0;
		`uvm_send(this.m_axis_trans)
		
		// 传输字节数 = 104, 基地址 = 4154, 递增突发, 等待周期数 = 2
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		
		this.m_axis_trans.data.push_back({24'd104, 32'd4154});
		this.m_axis_trans.user.push_back(1'b0);
		this.m_axis_trans.last.push_back(1'b1);
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 2;
		`uvm_send(this.m_axis_trans)
		
		// 传输字节数 = 50, 基地址 = 8182, 递增突发, 等待周期数 = 0
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		
		this.m_axis_trans.data.push_back({24'd50, 32'd8182});
		this.m_axis_trans.user.push_back(1'b0);
		this.m_axis_trans.last.push_back(1'b1);
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 0;
		`uvm_send(this.m_axis_trans)
		
		// 传输字节数 = 2, 基地址 = 1, 递增突发, 等待周期数 = 1
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		
		this.m_axis_trans.data.push_back({24'd2, 32'd1});
		this.m_axis_trans.user.push_back(1'b0);
		this.m_axis_trans.last.push_back(1'b1);
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 1;
		`uvm_send(this.m_axis_trans)
		
		// 传输字节数 = 4, 基地址 = 42, 递增突发, 等待周期数 = 1
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		
		this.m_axis_trans.data.push_back({24'd4, 32'd42});
		this.m_axis_trans.user.push_back(1'b0);
		this.m_axis_trans.last.push_back(1'b1);
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 1;
		`uvm_send(this.m_axis_trans)
		
		// 传输字节数 = 124, 基地址 = 4000, 固定突发, 等待周期数 = 3
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		
		this.m_axis_trans.data.push_back({24'd124, 32'd4000});
		this.m_axis_trans.user.push_back(1'b1);
		this.m_axis_trans.last.push_back(1'b1);
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 3;
		`uvm_send(this.m_axis_trans)
		
		// 传输字节数 = 6, 基地址 = 4124, 固定突发, 等待周期数 = 2
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		
		this.m_axis_trans.data.push_back({24'd6, 32'd4124});
		this.m_axis_trans.user.push_back(1'b1);
		this.m_axis_trans.last.push_back(1'b1);
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 2;
		`uvm_send(this.m_axis_trans)
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class AxiDmaEngineMM2SCase0Test extends uvm_test;
	
	// AXI通用DMA引擎MM2S通道测试环境
	local AxiDmaEngineMM2SEnv #(.s_axis_data_width(56), .m_axis_data_width(32)) env;
	
	// 注册component
	`uvm_component_utils(AxiDmaEngineMM2SCase0Test)
	
	function new(string name = "AxiDmaEngineMM2SCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = AxiDmaEngineMM2SEnv #(.s_axis_data_width(56), .m_axis_data_width(32))
				::type_id::create("env", this); // 创建env
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			AxiDmaEngineMM2SCase0SAXISSeq::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("AxiDmaEngineMM2SCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
