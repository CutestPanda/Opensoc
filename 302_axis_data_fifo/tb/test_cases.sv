`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class AxisDataFifoCase0SAXISSeq #(
	integer data_width = 8, // 数据位宽(必须能被8整除, 且>0)
	integer user_width = 1 // user信号位宽(必须>0)
)extends uvm_sequence #(AXISTrans #(.data_width(data_width), .user_width(user_width)));
	
	localparam integer pkt_n = 10; // 测试的数据包个数
	
	local AXISTrans #(.data_width(data_width), .user_width(user_width)) m_axis_trans; // AXIS主机事务
	local byte unsigned byte_v; // AXIS数据当前字节的值
	
	// 注册object
	`uvm_object_param_utils(AxisDataFifoCase0SAXISSeq #(.data_width(data_width), .user_width(user_width)))
	
	function new(string name = "AxisDataFifoCase0SAXISSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		repeat(pkt_n)
		begin
			automatic int unsigned trans_n = $urandom_range(1, 10);
			// automatic int unsigned trans_n = $urandom_range(20, 30);
			
			`uvm_create(this.m_axis_trans)
			
			this.m_axis_trans.data_n = trans_n;
			
			this.m_axis_trans.wait_period_n = new[trans_n];
			
			this.byte_v = 0;
			
			for(int i = 0;i < trans_n;i++)
			begin
				automatic bit[data_width-1:0] data = 0;
				
				for(int j = 0;j < data_width / 8;j++)
				begin
					data >>= 8;
					data[data_width-1:data_width-8] = this.byte_v;
					
					this.byte_v++;
				end
				
				this.m_axis_trans.data.push_back(data);
				this.m_axis_trans.last.push_back(i == (trans_n - 1));
				// 选择以下其中1个来控制从机输入是否一直valid
				this.m_axis_trans.wait_period_n[i] = $urandom_range(0, 4);
				// this.m_axis_trans.wait_period_n[i] = 0;
			end
			
			`uvm_send(this.m_axis_trans)
		end
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class AxisDataFifoCase0Test extends uvm_test;
	
	localparam integer data_width = 8; // 数据位宽(必须能被8整除, 且>0)
	localparam integer user_width = 1; // user信号位宽(必须>0)
	
	// AXIS数据FIFO测试环境
	local AxisDataFifoEnv #(.data_width(data_width), .user_width(user_width)) env;
	
	// 注册component
	`uvm_component_utils(AxisDataFifoCase0Test)
	
	function new(string name = "AxisDataFifoCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = AxisDataFifoEnv #(.data_width(data_width), .user_width(user_width))
			::type_id::create("env", this); // 创建env
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			AxisDataFifoCase0SAXISSeq #(.data_width(data_width), .user_width(user_width))
				::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("AxisDataFifoCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
