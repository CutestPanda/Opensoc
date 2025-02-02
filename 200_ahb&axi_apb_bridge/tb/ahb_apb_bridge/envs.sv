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

/** 环境:AHB-APB桥 **/
class AHBAPBBridgeEnv extends uvm_env;
	
	// 组件
	local APBSlaveAgent #(.out_drive_t(1), .addr_width(32), .data_width(32)) s_apb_agt[1:0]; // APB从机代理
	local AHBMasterAgent #(.out_drive_t(1), .slave_n(1), .addr_width(32), .data_width(32), 
		.burst_width(3), .prot_width(4), .master_width(1)) m_ahb_agt;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(APBTrans #(.addr_width(32), .data_width(32))) s_apb_agt_fifo[1:0];
	local uvm_tlm_analysis_fifo #(AHBTrans #(.addr_width(32), .data_width(32), 
		.burst_width(3), .prot_width(4), .master_width(1))) m_ahb_agt_fifo;
	
	// 通信端口
	local uvm_blocking_get_port #(APBTrans #(.addr_width(32), .data_width(32))) s_apb_trans_port[1:0];
	local uvm_blocking_get_port #(AHBTrans #(.addr_width(32), .data_width(32), 
		.burst_width(3), .prot_width(4), .master_width(1))) m_ahb_trans_port;
	
	// 事务
	local APBTrans #(.addr_width(32), .data_width(32)) s_apb_trans[1:0];
	local AHBTrans #(.addr_width(32), .data_width(32), 
		.burst_width(3), .prot_width(4), .master_width(1)) m_ahb_trans;
	
	// 注册component
	`uvm_component_utils(AHBAPBBridgeEnv)
	
	function new(string name = "AHBAPBBridgeEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.s_apb_agt[0] = APBSlaveAgent #(.out_drive_t(1), .addr_width(32), .data_width(32))::
			type_id::create("agt1", this);
		this.s_apb_agt[0].is_active = UVM_ACTIVE;
		this.s_apb_agt[1] = APBSlaveAgent #(.out_drive_t(1), .addr_width(32), .data_width(32))::
			type_id::create("agt2", this);
		this.s_apb_agt[1].is_active = UVM_ACTIVE;
		this.m_ahb_agt = AHBMasterAgent #(.out_drive_t(1), .slave_n(1), .addr_width(32), .data_width(32), 
			.burst_width(3), .prot_width(4), .master_width(1))::
			type_id::create("agt3", this);
		this.m_ahb_agt.is_active = UVM_ACTIVE;
		
		// 创建通信fifo
		this.s_apb_agt_fifo[0] = new("s_apb_agt_fifo_1", this);
		this.s_apb_agt_fifo[1] = new("s_apb_agt_fifo_2", this);
		this.m_ahb_agt_fifo = new("m_ahb_agt_fifo", this);
		
		// 创建通信端口
		this.s_apb_trans_port[0] = new("s_apb_trans_port_1", this);
		this.s_apb_trans_port[1] = new("s_apb_trans_port_2", this);
		this.m_ahb_trans_port = new("m_ahb_trans_port", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		// 连接agent的通信端口
		this.s_apb_agt[0].apb_analysis_port.connect(this.s_apb_agt_fifo[0].analysis_export);
		this.s_apb_agt[1].apb_analysis_port.connect(this.s_apb_agt_fifo[1].analysis_export);
		this.m_ahb_agt.ahb_analysis_port.connect(this.m_ahb_agt_fifo.analysis_export);
		
		this.s_apb_trans_port[0].connect(this.s_apb_agt_fifo[0].blocking_get_export);
		this.s_apb_trans_port[1].connect(this.s_apb_agt_fifo[1].blocking_get_export);
		this.m_ahb_trans_port.connect(this.m_ahb_agt_fifo.blocking_get_export);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				this.s_apb_trans_port[0].get(this.s_apb_trans[0]);
				this.s_apb_trans[0].print(); // 打印事务
			end
			forever
			begin
				this.s_apb_trans_port[1].get(this.s_apb_trans[1]);
				this.s_apb_trans[1].print(); // 打印事务
			end
			
			forever
			begin
				this.m_ahb_trans_port.get(this.m_ahb_trans);
				this.m_ahb_trans.print(); // 打印事务
			end
		join_none
	endtask
	
endclass
	
`endif
