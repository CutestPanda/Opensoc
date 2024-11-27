`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

// 测试模式配置
`define TEST_STEP_1 // 测试步长为1

class MaxPoolCase0SAXISSeq #(
	integer feature_n_per_clk = 2, // 每个clk输入的特征点数量(2 | 4 | 8 | 16 | ...)
	integer feature_data_width = 8 // 特征点位宽(必须能被8整除, 且>0)
)extends uvm_sequence #(AXISTrans #(.data_width(feature_n_per_clk*feature_data_width), .user_width(0)));
	
	local AXISTrans #(.data_width(feature_n_per_clk*feature_data_width), .user_width(0)) m_axis_trans; // AXIS主机事务
	
	// 注册object
	`uvm_object_param_utils(MaxPoolCase0SAXISSeq #(.feature_n_per_clk(feature_n_per_clk), .feature_data_width(feature_data_width)))
	
	function new(string name = "MaxPoolCase0SAXISSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
`ifdef TEST_STEP_1
		/**
		0 0  3 7 8 2 6 0 1  0  7  5  3
		1 2  5 4 3 7 0 0 0  3  8  9  2
		9 0  1 3 2 5 6 2 7  3  0  0  1
		7 10 5 6 1 0 8 5 3  2  12 13 5
		
		1 7  2 2 0 1 3 8 4  3  1  3  2
		9 2  0 5 1 2 0 3 3  2  2  1  1
		8 2  3 2 2 5 5 7 10 12 1  5  0
		6 6  1 1 0 1 2 3 0  3  2  3  2
		**/
		repeat(4)
		begin
			`uvm_create(this.m_axis_trans)
			
			this.m_axis_trans.data_n = 26;
			
			this.m_axis_trans.data.push_back({8'd7, 8'd3, 8'd0, 8'd0});
			this.m_axis_trans.data.push_back({8'd0, 8'd6, 8'd2, 8'd8});
			this.m_axis_trans.data.push_back({8'd5, 8'd7, 8'd0, 8'd1});
			this.m_axis_trans.data.push_back({8'd5, 8'd2, 8'd1, 8'd3});
			this.m_axis_trans.data.push_back({8'd0, 8'd7, 8'd3, 8'd4});
			this.m_axis_trans.data.push_back({8'd8, 8'd3, 8'd0, 8'd0});
			this.m_axis_trans.data.push_back({8'd0, 8'd9, 8'd2, 8'd9});
			this.m_axis_trans.data.push_back({8'd5, 8'd2, 8'd3, 8'd1});
			this.m_axis_trans.data.push_back({8'd3, 8'd7, 8'd2, 8'd6});
			this.m_axis_trans.data.push_back({8'd7, 8'd1, 8'd0, 8'd0});
			this.m_axis_trans.data.push_back({8'd1, 8'd6, 8'd5, 8'd10});
			this.m_axis_trans.data.push_back({8'd3, 8'd5, 8'd8, 8'd0});
			this.m_axis_trans.data.push_back({8'd5, 8'd13, 8'd12, 8'd2});
			
			this.m_axis_trans.data.push_back({8'd2, 8'd2, 8'd7, 8'd1});
			this.m_axis_trans.data.push_back({8'd8, 8'd3, 8'd1, 8'd0});
			this.m_axis_trans.data.push_back({8'd3, 8'd1, 8'd3, 8'd4});
			this.m_axis_trans.data.push_back({8'd0, 8'd2, 8'd9, 8'd2});
			this.m_axis_trans.data.push_back({8'd0, 8'd2, 8'd1, 8'd5});
			this.m_axis_trans.data.push_back({8'd2, 8'd2, 8'd3, 8'd3});
			this.m_axis_trans.data.push_back({8'd2, 8'd8, 8'd1, 8'd1});
			this.m_axis_trans.data.push_back({8'd5, 8'd2, 8'd2, 8'd3});
			this.m_axis_trans.data.push_back({8'd12, 8'd10, 8'd7, 8'd5});
			this.m_axis_trans.data.push_back({8'd6, 8'd0, 8'd5, 8'd1});
			this.m_axis_trans.data.push_back({8'd0, 8'd1, 8'd1, 8'd6});
			this.m_axis_trans.data.push_back({8'd0, 8'd3, 8'd2, 8'd1});
			this.m_axis_trans.data.push_back({8'd2, 8'd3, 8'd2, 8'd3});
			
			this.m_axis_trans.wait_period_n = new[26];
			
			for(int i = 0;i < 26;i++)
			begin
				this.m_axis_trans.wait_period_n[i] = $urandom_range(0, 5);
				// this.m_axis_trans.wait_period_n[i] = 0;
				this.m_axis_trans.keep.push_back(4'b1111);
				this.m_axis_trans.last.push_back(i == 25);
			end
			
			`uvm_send(this.m_axis_trans)
		end
`else
		/**
		0 0  3 7 8 2 6 0 1  0  7  5  3 1
		1 2  5 4 3 7 0 0 0  3  8  9  2 3
		9 0  1 3 2 5 6 2 7  3  0  0  1 10
		7 10 5 6 1 0 8 5 3  2  12 13 5 2
		
		1 7  2 2 0 1 3 8 4  3  1  3  2 5
		9 2  0 5 1 2 0 3 3  2  2  1  1 0
		8 2  3 2 2 5 5 7 10 12 1  5  0 1
		6 6  1 1 0 1 2 3 0  3  2  3  2 11
		**/
		repeat(4)
		begin
			`uvm_create(this.m_axis_trans)
			
			this.m_axis_trans.data_n = 28;
			
			this.m_axis_trans.data.push_back({8'd7, 8'd3, 8'd0, 8'd0});
			this.m_axis_trans.data.push_back({8'd0, 8'd6, 8'd2, 8'd8});
			this.m_axis_trans.data.push_back({8'd5, 8'd7, 8'd0, 8'd1});
			this.m_axis_trans.data.push_back({8'd2, 8'd1, 8'd1, 8'd3});
			this.m_axis_trans.data.push_back({8'd7, 8'd3, 8'd4, 8'd5});
			this.m_axis_trans.data.push_back({8'd3, 8'd0, 8'd0, 8'd0});
			this.m_axis_trans.data.push_back({8'd3, 8'd2, 8'd9, 8'd8});
			this.m_axis_trans.data.push_back({8'd3, 8'd1, 8'd0, 8'd9});
			this.m_axis_trans.data.push_back({8'd2, 8'd6, 8'd5, 8'd2});
			this.m_axis_trans.data.push_back({8'd0, 8'd0, 8'd3, 8'd7});
			this.m_axis_trans.data.push_back({8'd10, 8'd7, 8'd10, 8'd1});
			this.m_axis_trans.data.push_back({8'd0, 8'd1, 8'd6, 8'd5});
			this.m_axis_trans.data.push_back({8'd2, 8'd3, 8'd5, 8'd8});
			this.m_axis_trans.data.push_back({8'd2, 8'd5, 8'd13, 8'd12});
			
			this.m_axis_trans.data.push_back({8'd2, 8'd2, 8'd7, 8'd1});
			this.m_axis_trans.data.push_back({8'd8, 8'd3, 8'd1, 8'd0});
			this.m_axis_trans.data.push_back({8'd3, 8'd1, 8'd3, 8'd4});
			this.m_axis_trans.data.push_back({8'd2, 8'd9, 8'd5, 8'd2});
			this.m_axis_trans.data.push_back({8'd2, 8'd1, 8'd5, 8'd0});
			this.m_axis_trans.data.push_back({8'd2, 8'd3, 8'd3, 8'd0});
			this.m_axis_trans.data.push_back({8'd0, 8'd1, 8'd1, 8'd2});
			this.m_axis_trans.data.push_back({8'd2, 8'd3, 8'd2, 8'd8});
			this.m_axis_trans.data.push_back({8'd7, 8'd5, 8'd5, 8'd2});
			this.m_axis_trans.data.push_back({8'd5, 8'd1, 8'd12, 8'd10});
			this.m_axis_trans.data.push_back({8'd6, 8'd6, 8'd1, 8'd0});
			this.m_axis_trans.data.push_back({8'd1, 8'd0, 8'd1, 8'd1});
			this.m_axis_trans.data.push_back({8'd3, 8'd0, 8'd3, 8'd2});
			this.m_axis_trans.data.push_back({8'd11, 8'd2, 8'd3, 8'd2});
			
			this.m_axis_trans.wait_period_n = new[28];
			
			for(int i = 0;i < 28;i++)
			begin
				this.m_axis_trans.wait_period_n[i] = $urandom_range(0, 5);
				// this.m_axis_trans.wait_period_n[i] = 0;
				this.m_axis_trans.keep.push_back(4'b1111);
				this.m_axis_trans.last.push_back(i == 27);
			end
			
			`uvm_send(this.m_axis_trans)
		end
`endif
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class MaxPoolCase0Test extends uvm_test;
	
	localparam integer feature_n_per_clk = 4; // 每个clk输入的特征点数量(2 | 4 | 8 | 16 | ...)
	localparam integer feature_data_width = 8; // 特征点位宽(必须能被8整除, 且>0)
	
	// 最大池化测试环境
	local MaxPoolEnv #(.s_axis_data_width(feature_n_per_clk*feature_data_width), 
		.m_axis_data_width(feature_n_per_clk*feature_data_width)) env;
	
	// 注册component
	`uvm_component_utils(MaxPoolCase0Test)
	
	function new(string name = "MaxPoolCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = MaxPoolEnv #(.s_axis_data_width(feature_n_per_clk*feature_data_width), 
			.m_axis_data_width(feature_n_per_clk*feature_data_width))
				::type_id::create("env", this); // 创建env
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			MaxPoolCase0SAXISSeq #(.feature_n_per_clk(feature_n_per_clk), .feature_data_width(feature_data_width))
				::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("MaxPoolCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
