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
