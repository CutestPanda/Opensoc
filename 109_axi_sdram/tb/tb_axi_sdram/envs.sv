`timescale 1ns / 1ps

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"

/** 环境:axi-sdram **/
class AxiSdramEnv #(
	integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	real simulation_delay = 1 // 仿真延时
)extends uvm_env;
	
	// 组件
	local AXIMasterAgent #(.out_drive_t(simulation_delay), 
		.addr_width(32), .data_width(data_width), .bresp_width(2), .rresp_width(2)) m_axi_agt; // AXI主机代理
	
	// 通信端口
	local uvm_blocking_get_port #(AXITrans #(.addr_width(32), 
		.data_width(data_width), .bresp_width(2), .rresp_width(2))) m_axi_rd_trans_port;
	local uvm_blocking_get_port #(AXITrans #(.addr_width(32), 
		.data_width(data_width), .bresp_width(2), .rresp_width(2))) m_axi_wt_trans_port;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(AXITrans #(.addr_width(32), 
		.data_width(data_width), .bresp_width(2), .rresp_width(2))) m_axi_agt_rd_fifo;
	local uvm_tlm_analysis_fifo #(AXITrans #(.addr_width(32), 
		.data_width(data_width), .bresp_width(2), .rresp_width(2))) m_axi_agt_wt_fifo;
	
	// 事务
	local AXITrans #(.addr_width(32), 
		.data_width(data_width), .bresp_width(2), .rresp_width(2)) m_axi_rd_trans;
	local AXITrans #(.addr_width(32), 
		.data_width(data_width), .bresp_width(2), .rresp_width(2)) m_axi_wt_trans;
	
	// 注册component
	`uvm_component_param_utils(AxiSdramEnv #(.data_width(data_width), .simulation_delay(simulation_delay)))
	
	function new(string name = "AxiSdramEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		// AXI主机agent
		this.m_axi_agt = AXIMasterAgent #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(data_width), .bresp_width(2), .rresp_width(2))::type_id::create("agt1", this);
		this.m_axi_agt.is_active = UVM_ACTIVE;
		
		// 创建通信端口
		this.m_axi_rd_trans_port = new("m_axi_rd_trans_port", this);
		this.m_axi_wt_trans_port = new("m_axi_wt_trans_port", this);
		
		// 创建通信fifo
		this.m_axi_agt_rd_fifo = new("m_axi_agt_rd_fifo", this);
		this.m_axi_agt_wt_fifo = new("m_axi_agt_wt_fifo", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.m_axi_agt.rd_trans_analysis_port.connect(this.m_axi_agt_rd_fifo.analysis_export);
		this.m_axi_rd_trans_port.connect(this.m_axi_agt_rd_fifo.blocking_get_export);
		this.m_axi_agt.wt_trans_analysis_port.connect(this.m_axi_agt_wt_fifo.analysis_export);
		this.m_axi_wt_trans_port.connect(this.m_axi_agt_wt_fifo.blocking_get_export);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				this.m_axi_rd_trans_port.get(this.m_axi_rd_trans);
				// this.m_axi_rd_trans.print();
			end
			forever
			begin
				this.m_axi_wt_trans_port.get(this.m_axi_wt_trans);
				// this.m_axi_wt_trans.print();
			end
		join
	endtask
	
endclass
	
`endif
