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

class AxiWchnForConvOutCase0S0AXISSeq extends uvm_sequence #(AXISTrans #(.data_width(64), .user_width(0)));
	
	local AXISTrans #(.data_width(64), .user_width(0)) m_axis_trans; // AXIS主机事务
	
	// 注册object
	`uvm_object_utils(AxiWchnForConvOutCase0S0AXISSeq)
	
	function new(string name = "AxiWchnForConvOutCase0S0AXISSeq");
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
		
		// 传输字节数 = 50, 基地址 = 8182, 等待周期数 = 0
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		
		this.m_axis_trans.data.push_back({32'd50, 32'd8182});
		this.m_axis_trans.wait_period_n = new[1];
		this.m_axis_trans.wait_period_n[0] = 0;
		`uvm_send(this.m_axis_trans)
		
		// 传输字节数 = 4, 基地址 = 2, 等待周期数 = 1
		`uvm_create(this.m_axis_trans)
		this.m_axis_trans.data_n = 1;
		
		this.m_axis_trans.data.push_back({32'd4, 32'd2});
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

class AxiWchnForConvOutCase0S1AXISSeq #(
	integer feature_data_width = 16 // 特征点位宽(8 | 16 | 32 | 64)
)extends uvm_sequence #(AXISTrans #(.data_width(feature_data_width), .user_width(0)));
	
	localparam int unsigned data_n_of_pkt[0:5] = '{52, 26, 52, 25, 2, 5};
	
	local AXISTrans #(.data_width(feature_data_width), .user_width(0)) m_axis_trans; // AXIS主机事务
	
	// 注册object
	`uvm_object_param_utils(AxiWchnForConvOutCase0S1AXISSeq #(.feature_data_width(feature_data_width)))
	
	function new(string name = "AxiWchnForConvOutCase0S1AXISSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		for(int i = 0;i < 6;i++)
		begin
			`uvm_do_with(this.m_axis_trans, {
				data_n == data_n_of_pkt[i];
				
				data.size() == data_n_of_pkt[i];
				last.size() == data_n_of_pkt[i];
				wait_period_n.size() == data_n_of_pkt[i];
				
				foreach(data[k])
					data[k] == k;
				
				foreach(last[k])
					last[k] == (k == (data_n_of_pkt[i] - 1));
				
				foreach(wait_period_n[k])
					wait_period_n[k] <= 2;
			})
		end
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class AxiWchnForConvOutCase0Test extends uvm_test;
	
	localparam integer feature_data_width = 16; // 特征点位宽(8 | 16 | 32 | 64)
	
	// 用于输出卷积/BN/激活计算结果的AXI写通道测试环境
	local AxiWchnForConvOutEnv #(.feature_data_width(feature_data_width)) env;
	
	// 注册component
	`uvm_component_utils(AxiWchnForConvOutCase0Test)
	
	function new(string name = "AxiWchnForConvOutCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = AxiWchnForConvOutEnv #(.feature_data_width(feature_data_width))
				::type_id::create("env", this); // 创建env
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			AxiWchnForConvOutCase0S0AXISSeq::type_id::get());
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt2.sqr.main_phase", 
			"default_sequence", 
			AxiWchnForConvOutCase0S1AXISSeq #(.feature_data_width(feature_data_width))::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("AxiWchnForConvOutCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
