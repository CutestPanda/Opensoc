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

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"

/** 环境:AXI通用DMA引擎S2MM通道 **/
class AxiDmaEngineS2MMEnv extends uvm_env;
	
	// 组件
	local AXISMasterAgent #(.data_width(56), .user_width(1)) m0_axis_agt;
	local AXISMasterAgent #(.data_width(32), .user_width(0)) m1_axis_agt;
	
	// 通信端口
	local uvm_blocking_get_port #(AXISTrans #(.data_width(56), .user_width(1))) m0_axis_trans_port;
	local uvm_blocking_get_port #(AXISTrans #(.data_width(32), .user_width(0))) m1_axis_trans_port;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(56), .user_width(1))) m0_axis_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(32), .user_width(0))) m1_axis_agt_fifo;
	
	// 事务
	local AXISTrans #(.data_width(56), .user_width(1)) m0_axis_trans;
	local AXISTrans #(.data_width(32), .user_width(0)) m1_axis_trans;
	
	// 注册component
	`uvm_component_utils(AxiDmaEngineS2MMEnv)
	
	function new(string name = "AxiDmaEngineS2MMEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.m0_axis_agt = AXISMasterAgent #(.data_width(56), .user_width(1))::
			type_id::create("agt1", this);
		this.m0_axis_agt.is_active = UVM_ACTIVE;
		this.m1_axis_agt = AXISMasterAgent #(.data_width(32), .user_width(0))::
			type_id::create("agt2", this);
		this.m1_axis_agt.is_active = UVM_ACTIVE;
		
		// 创建通信端口
		this.m0_axis_trans_port = new("m0_axis_trans_port", this);
		this.m1_axis_trans_port = new("m1_axis_trans_port", this);
		
		// 创建通信fifo
		this.m0_axis_agt_fifo = new("m0_axis_agt_fifo", this);
		this.m1_axis_agt_fifo = new("m1_axis_agt_fifo", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.m0_axis_agt.axis_analysis_port.connect(this.m0_axis_agt_fifo.analysis_export);
		this.m0_axis_trans_port.connect(this.m0_axis_agt_fifo.blocking_get_export);
		this.m1_axis_agt.axis_analysis_port.connect(this.m1_axis_agt_fifo.analysis_export);
		this.m1_axis_trans_port.connect(this.m1_axis_agt_fifo.blocking_get_export);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				this.m0_axis_trans_port.get(this.m0_axis_trans);
				// this.m0_axis_trans.print(); // 打印事务
			end
			forever
			begin
				this.m1_axis_trans_port.get(this.m1_axis_trans);
				// this.m1_axis_trans.print(); // 打印事务
			end
		join_none
	endtask
	
endclass
	
`endif
