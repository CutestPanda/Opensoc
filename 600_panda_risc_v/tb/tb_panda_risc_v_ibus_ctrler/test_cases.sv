`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class IBusCtrlerCase0MAXISSeq extends uvm_sequence #(AXISTrans #(.data_width(32), .user_width(33)));
	
	local AXISTrans #(.data_width(32), .user_width(33)) m_axis_trans; // AXIS主机事务
	
	// 注册object
	`uvm_object_utils(IBusCtrlerCase0MAXISSeq)
	
	function new(string name = "IBusCtrlerCase0MAXISSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		// 地址 = 3, 读, 写数据 = 1, 写掩码 = 4'b0001, 等待周期数 = 0
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		this.m_axis_trans.user.push_back({32'd3, 1'b1});
		this.m_axis_trans.data.push_back(32'd1);
		this.m_axis_trans.keep.push_back(4'b0001);
		this.m_axis_trans.last.push_back(1'b1);
		
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 0;
		`uvm_send(this.m_axis_trans)
		
		// 地址 = 8, 写, 写数据 = 2, 写掩码 = 4'b0011, 等待周期数 = 0
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		this.m_axis_trans.user.push_back({32'd8, 1'b0});
		this.m_axis_trans.data.push_back(32'd2);
		this.m_axis_trans.keep.push_back(4'b0011);
		this.m_axis_trans.last.push_back(1'b1);
		
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 0;
		`uvm_send(this.m_axis_trans)
		
		// 地址 = 16, 读, 写数据 = 3, 写掩码 = 4'b0111, 等待周期数 = 1
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		this.m_axis_trans.user.push_back({32'd16, 1'b1});
		this.m_axis_trans.data.push_back(32'd3);
		this.m_axis_trans.keep.push_back(4'b0111);
		this.m_axis_trans.last.push_back(1'b1);
		
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 1;
		`uvm_send(this.m_axis_trans)
		
		// 地址 = 7, 写, 写数据 = 4, 写掩码 = 4'b1111, 等待周期数 = 0
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		this.m_axis_trans.user.push_back({32'd7, 1'b0});
		this.m_axis_trans.data.push_back(32'd4);
		this.m_axis_trans.keep.push_back(4'b1111);
		this.m_axis_trans.last.push_back(1'b1);
		
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 0;
		`uvm_send(this.m_axis_trans)
		
		// 地址 = 20, 读, 写数据 = 5, 写掩码 = 4'b0001, 等待周期数 = 0
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		this.m_axis_trans.user.push_back({32'd20, 1'b1});
		this.m_axis_trans.data.push_back(32'd5);
		this.m_axis_trans.keep.push_back(4'b0001);
		this.m_axis_trans.last.push_back(1'b1);
		
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 0;
		`uvm_send(this.m_axis_trans)
		
		// 地址 = 7, 写, 写数据 = 100, 写掩码 = 4'b1111, 等待周期数 = 0
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		this.m_axis_trans.user.push_back({32'd7, 1'b0});
		this.m_axis_trans.data.push_back(32'd100);
		this.m_axis_trans.keep.push_back(4'b1111);
		this.m_axis_trans.last.push_back(1'b1);
		
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 0;
		`uvm_send(this.m_axis_trans)
		
		// 地址 = 24, 写, 写数据 = 6, 写掩码 = 4'b0011, 等待周期数 = 0
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		this.m_axis_trans.user.push_back({32'd24, 1'b0});
		this.m_axis_trans.data.push_back(32'd6);
		this.m_axis_trans.keep.push_back(4'b0011);
		this.m_axis_trans.last.push_back(1'b1);
		
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 0;
		`uvm_send(this.m_axis_trans)
		
		// 地址 = 32, 读, 写数据 = 7, 写掩码 = 4'b0111, 等待周期数 = 2
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		this.m_axis_trans.user.push_back({32'd32, 1'b1});
		this.m_axis_trans.data.push_back(32'd7);
		this.m_axis_trans.keep.push_back(4'b0111);
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

class IBusCtrlerCase0SICBSeq extends uvm_sequence #(ICBTrans #(.addr_width(32), .data_width(32)));
	
	local ICBTrans #(.addr_width(32), .data_width(32)) s_icb_trans; // icb从机事务
	
	// 注册object
	`uvm_object_utils(IBusCtrlerCase0SICBSeq)
	
	function new(string name = "IBusCtrlerCase0SICBSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		// 命令通道等待周期数 = 1, 读数据 = 1, 错误 = 1'b0, 响应通道等待周期数 = 1
		`uvm_create(this.s_icb_trans)
		this.s_icb_trans.cmd_wait_period_n = 1;
		this.s_icb_trans.rsp_rdata = 1;
		this.s_icb_trans.rsp_err = 1'b0;
		this.s_icb_trans.rsp_wait_period_n = 1;
		`uvm_send(this.s_icb_trans)
		
		// 命令通道等待周期数 = 2, 读数据 = 2, 错误 = 1'b1, 响应通道等待周期数 = 2
		`uvm_create(this.s_icb_trans)
		this.s_icb_trans.cmd_wait_period_n = 2;
		this.s_icb_trans.rsp_rdata = 2;
		this.s_icb_trans.rsp_err = 1'b1;
		this.s_icb_trans.rsp_wait_period_n = 2;
		`uvm_send(this.s_icb_trans)
		
		// 命令通道等待周期数 = 5, 读数据 = 3, 错误 = 1'b0, 响应通道等待周期数 = 10
		`uvm_create(this.s_icb_trans)
		this.s_icb_trans.cmd_wait_period_n = 5;
		this.s_icb_trans.rsp_rdata = 3;
		this.s_icb_trans.rsp_err = 1'b0;
		this.s_icb_trans.rsp_wait_period_n = 10;
		`uvm_send(this.s_icb_trans)
		
		// 命令通道等待周期数 = 5, 读数据 = 4, 错误 = 1'b0, 响应通道等待周期数 = 7
		`uvm_create(this.s_icb_trans)
		this.s_icb_trans.cmd_wait_period_n = 5;
		this.s_icb_trans.rsp_rdata = 4;
		this.s_icb_trans.rsp_err = 1'b0;
		this.s_icb_trans.rsp_wait_period_n = 7;
		`uvm_send(this.s_icb_trans)
		
		// 命令通道等待周期数 = 3, 读数据 = 5, 错误 = 1'b0, 响应通道等待周期数 = 20
		`uvm_create(this.s_icb_trans)
		this.s_icb_trans.cmd_wait_period_n = 3;
		this.s_icb_trans.rsp_rdata = 5;
		this.s_icb_trans.rsp_err = 1'b0;
		this.s_icb_trans.rsp_wait_period_n = 20;
		`uvm_send(this.s_icb_trans)
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class IBusCtrlerCase0Test extends uvm_test;
	
	// 指令总线控制单元测试环境
	local IBusCtrlerEnv env;
	
	// 注册component
	`uvm_component_utils(IBusCtrlerCase0Test)
	
	function new(string name = "IBusCtrlerCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = IBusCtrlerEnv::type_id::create("env", this); // 创建env
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			IBusCtrlerCase0MAXISSeq::type_id::get());
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt2.sqr.main_phase", 
			"default_sequence", 
			IBusCtrlerCase0SICBSeq::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("IBusCtrlerCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
