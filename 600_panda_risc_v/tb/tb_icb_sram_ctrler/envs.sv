`timescale 1ns / 1ps

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"

/** 环境:ICB-SRAM控制器 **/
class ICBSramCtrlerEnv extends uvm_env;
	
	// 组件
	local ICBMasterAgent #(.out_drive_t(1), .addr_width(32), .data_width(32)) m_icb_agt; // ICB主机代理
	
	// 通信端口
	local uvm_blocking_get_port #(ICBTrans #(.addr_width(32), .data_width(32))) m_icb_trans_port;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(ICBTrans #(.addr_width(32), .data_width(32))) m_icb_agt_fifo;
	
	// 事务
	local ICBTrans #(.addr_width(32), .data_width(32)) m_icb_trans;
	
	// 注册component
	`uvm_component_utils(ICBSramCtrlerEnv)
	
	function new(string name = "ICBSramCtrlerEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.m_icb_agt = ICBMasterAgent #(.out_drive_t(1), .addr_width(32), .data_width(32))::
			type_id::create("agt1", this);
		this.m_icb_agt.is_active = UVM_ACTIVE;
		
		// 创建通信端口
		this.m_icb_trans_port = new("m_icb_trans_port", this);
		
		// 创建通信fifo
		this.m_icb_agt_fifo = new("m_icb_agt_fifo", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.m_icb_agt.icb_analysis_port.connect(this.m_icb_agt_fifo.analysis_export);
		this.m_icb_trans_port.connect(this.m_icb_agt_fifo.blocking_get_export);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				this.m_icb_trans_port.get(this.m_icb_trans);
				this.m_icb_trans.print(); // 打印事务
			end
		join_none
	endtask
	
endclass
	
`endif