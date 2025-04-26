`timescale 1ns / 1ps

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"

/** 环境:以太网发送 **/
class EthMacTxEnv #(
	real simulation_delay = 1 // 仿真延时
)extends uvm_env;
	
	// 组件
	local AXISMasterAgent #(.out_drive_t(simulation_delay), .data_width(16), .user_width(0)) m_axis_agt; // AXIS主机代理
	
	// 通信端口
	local uvm_blocking_get_port #(AXISTrans #(.data_width(16), .user_width(0))) m_axis_trans_port;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(16), .user_width(0))) m_axis_fifo;
	
	// 事务
	local AXISTrans #(.data_width(16), .user_width(0)) m_axis_trans;
	
	// 注册component
	`uvm_component_param_utils(EthMacTxEnv #(.simulation_delay(simulation_delay)))
	
	function new(string name = "EthMacTxEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		// AXIS主机agent
		this.m_axis_agt = AXISMasterAgent #(.out_drive_t(simulation_delay), 
			.data_width(16), .user_width(0))::type_id::create("agt1", this);
		this.m_axis_agt.is_active = UVM_ACTIVE;
		
		// 创建通信端口
		this.m_axis_trans_port = new("m_axis_trans_port", this);
		
		// 创建通信fifo
		this.m_axis_fifo = new("m_axis_fifo", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.m_axis_agt.axis_analysis_port.connect(this.m_axis_fifo.analysis_export);
		this.m_axis_trans_port.connect(this.m_axis_fifo.blocking_get_export);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				this.m_axis_trans_port.get(this.m_axis_trans);
				// this.m_axis_trans.print();
			end
		join
	endtask
	
endclass
	
`endif
