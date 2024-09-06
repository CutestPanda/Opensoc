`timescale 1ns / 1ps

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"

/** 环境:AXI-BRAM控制器 **/
class AXIBramCtrlerEnv extends uvm_env;
	
	// 组件
	local AXIMasterAgent #(.out_drive_t(1), .addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2)) m_axi_agt;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2))) m_axi_agt_fifo[1:0];
	
	// 通信端口
	local uvm_blocking_get_port #(AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2))) m_axi_trans_port[1:0];
	
	// 事务
	local AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2)) m_axi_trans[1:0];
	
	// 注册component
	`uvm_component_utils(AXIBramCtrlerEnv)
	
	function new(string name = "AXIBramCtrlerEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.m_axi_agt = AXIMasterAgent #(.out_drive_t(1), .addr_width(32), .data_width(32), 
			.bresp_width(2), .rresp_width(2))::type_id::create("agt", this);
		this.m_axi_agt.is_active = UVM_ACTIVE;
		
		// 创建通信fifo
		this.m_axi_agt_fifo[1] = new("m_axi_agt_fifo_rd", this);
		this.m_axi_agt_fifo[0] = new("m_axi_agt_fifo_wt", this);
		
		// 创建通信端口
		this.m_axi_trans_port[1] = new("m_axi_trans_port_rd", this);
		this.m_axi_trans_port[0] = new("m_axi_trans_port_wt", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		// 连接agent的通信端口
		this.m_axi_agt.rd_trans_analysis_port.connect(this.m_axi_agt_fifo[1].analysis_export);
		this.m_axi_agt.wt_trans_analysis_port.connect(this.m_axi_agt_fifo[0].analysis_export);
		
		this.m_axi_trans_port[1].connect(this.m_axi_agt_fifo[1].blocking_get_export);
		this.m_axi_trans_port[0].connect(this.m_axi_agt_fifo[0].blocking_get_export);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				this.m_axi_trans_port[1].get(this.m_axi_trans[1]);
				this.m_axi_trans[1].print(); // 打印事务
			end
			
			forever
			begin
				this.m_axi_trans_port[0].get(this.m_axi_trans[0]);
				this.m_axi_trans[0].print(); // 打印事务
			end
		join_none
	endtask
	
endclass
	
`endif
