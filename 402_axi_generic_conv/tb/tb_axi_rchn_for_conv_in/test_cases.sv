`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class AxiRchnForConvInCase0SAXISSeq extends uvm_sequence #(AXISTrans #(.data_width(64), .user_width(0)));
	
	local AXISTrans #(.data_width(64), .user_width(0)) m_axis_trans; // AXIS主机事务
	
	// 注册object
	`uvm_object_utils(AxiRchnForConvInCase0SAXISSeq)
	
	function new(string name = "AxiRchnForConvInCase0SAXISSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		// 传输字节数 = 104, 基地址 = 4000, 等待周期数 = 0
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		
		this.m_axis_trans.data.push_back({32'd104, 32'd4000});
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 0;
		`uvm_send(this.m_axis_trans)
		
		// 传输字节数 = 52, 基地址 = 4104, 等待周期数 = 0
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		
		this.m_axis_trans.data.push_back({32'd52, 32'd4104});
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 0;
		`uvm_send(this.m_axis_trans)
		
		// 传输字节数 = 104, 基地址 = 4156, 等待周期数 = 2
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		
		this.m_axis_trans.data.push_back({32'd104, 32'd4156});
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 2;
		`uvm_send(this.m_axis_trans)
		
		// 传输字节数 = 50, 基地址 = 8180, 等待周期数 = 0
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		
		this.m_axis_trans.data.push_back({32'd50, 32'd8180});
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 0;
		`uvm_send(this.m_axis_trans)
		
		// 传输字节数 = 5, 基地址 = 2, 等待周期数 = 1
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		
		this.m_axis_trans.data.push_back({32'd5, 32'd2});
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 1;
		`uvm_send(this.m_axis_trans)
		
		// 传输字节数 = 10, 基地址 = 44, 等待周期数 = 1
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		
		this.m_axis_trans.data.push_back({32'd10, 32'd44});
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 1;
		`uvm_send(this.m_axis_trans)
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class AxiRchnForConvInCase0Test extends uvm_test;
	
	// 用于获取输入特征图/卷积核的AXI读通道测试环境
	local AxiRchnForConvInEnv #(.s_axis_data_width(64), .m_axis_data_width(64)) env;
	
	// 注册component
	`uvm_component_utils(AxiRchnForConvInCase0Test)
	
	function new(string name = "AxiRchnForConvInCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = AxiRchnForConvInEnv #(.s_axis_data_width(64), .m_axis_data_width(64))
				::type_id::create("env", this); // 创建env
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			AxiRchnForConvInCase0SAXISSeq::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("AxiRchnForConvInCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
