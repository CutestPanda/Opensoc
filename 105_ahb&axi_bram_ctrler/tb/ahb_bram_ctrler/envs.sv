`timescale 1ns / 1ps

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"

/** 环境:AHB-BRAM控制器 **/
class AHBBramCtrlerEnv extends uvm_env;
	
	// 组件
	local AHBMasterAgent #(.out_drive_t(1), .slave_n(1), .addr_width(32), .data_width(32), 
		.burst_width(3), .prot_width(4), .master_width(1)) m_ahb_agt;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(AHBTrans #(.addr_width(32), .data_width(32), 
		.burst_width(3), .prot_width(4), .master_width(1))) m_ahb_agt_fifo;
	
	// 通信端口
	local uvm_blocking_get_port #(AHBTrans #(.addr_width(32), .data_width(32), 
		.burst_width(3), .prot_width(4), .master_width(1))) m_ahb_trans_port;
	
	// 事务
	local AHBTrans #(.addr_width(32), .data_width(32), 
		.burst_width(3), .prot_width(4), .master_width(1)) m_ahb_trans;
	
	// 注册component
	`uvm_component_utils(AHBBramCtrlerEnv)
	
	function new(string name = "AHBBramCtrlerEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.m_ahb_agt = AHBMasterAgent #(.out_drive_t(1), .slave_n(1), .addr_width(32), .data_width(32), 
			.burst_width(3), .prot_width(4), .master_width(1))::
			type_id::create("agt", this);
		this.m_ahb_agt.is_active = UVM_ACTIVE;
		
		// 创建通信fifo
		this.m_ahb_agt_fifo = new("m_ahb_agt_fifo", this);
		
		// 创建通信端口
		this.m_ahb_trans_port = new("m_ahb_trans_port", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		// 连接agent的通信端口
		this.m_ahb_agt.ahb_analysis_port.connect(this.m_ahb_agt_fifo.analysis_export);
		
		this.m_ahb_trans_port.connect(this.m_ahb_agt_fifo.blocking_get_export);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				this.m_ahb_trans_port.get(this.m_ahb_trans);
				this.m_ahb_trans.print(); // 打印事务
			end
		join_none
	endtask
	
endclass
	
`endif
