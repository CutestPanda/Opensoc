`timescale 1ns / 1ps

`ifndef __ENV_H

`define __ENV_H

`include "../../transactions.sv"
`include "../../agents.sv"

/** 环境:Apb-Timer **/
class ApbTimerEnv extends uvm_env;
	
	// 组件
	APBMasterAgent #(.out_drive_t(1), .addr_width(32), .data_width(32)) reg_agt;
	
	// 注册component
	`uvm_component_utils(ApbTimerEnv)
	
	function new(string name = "ApbTimerEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.reg_agt = APBMasterAgent #(.out_drive_t(1), .addr_width(32), .data_width(32))::type_id::create("reg_agt", this);
		this.reg_agt.is_active = UVM_ACTIVE;
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
	endfunction
	
endclass
	
`endif
