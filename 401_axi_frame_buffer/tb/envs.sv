`timescale 1ns / 1ps

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"

/** 环境:AXI帧缓存 **/
class AXIFrameBufferEnv #(
	real out_drive_t = 1, // 输出驱动延迟量
	integer s_axis_data_width = 8, // AXIS从机数据位宽
	integer m_axis_data_width = 8 // AXIS主机数据位宽
)extends uvm_env;
	
	// 组件
	local AXISMasterAgent #(.out_drive_t(out_drive_t), .data_width(s_axis_data_width), .user_width(0)) m_axis_agt; // AXIS主机代理
	local AXISSlaveAgent #(.out_drive_t(out_drive_t), .data_width(m_axis_data_width), .user_width(8)) s_axis_agt; // AXIS从机代理
	local AXISlaveAgent #(.out_drive_t(out_drive_t), .addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2)) s_axi_agt; // AXI从机代理
	
	// 通信端口
	local uvm_blocking_get_port #(AXISTrans #(.data_width(s_axis_data_width), .user_width(0))) m_axis_trans_port;
	local uvm_blocking_get_port #(AXISTrans #(.data_width(m_axis_data_width), .user_width(8))) s_axis_trans_port;
	local uvm_blocking_get_port #(AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2))) axi_rd_trans_port;
	local uvm_blocking_get_port #(AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2))) axi_wt_trans_port;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(s_axis_data_width), .user_width(0))) m_axis_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(m_axis_data_width), .user_width(8))) s_axis_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2))) s_axi_agt_rd_fifo;
	local uvm_tlm_analysis_fifo #(AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2))) s_axi_agt_wt_fifo;
	
	// 事务
	local AXISTrans #(.data_width(s_axis_data_width), .user_width(0)) m_axis_trans;
	local AXISTrans #(.data_width(m_axis_data_width), .user_width(8)) s_axis_trans;
	local AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2)) s_axi_rd_trans;
	local AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2)) s_axi_wt_trans;
	
	// 注册component
	`uvm_component_param_utils(AXIFrameBufferEnv #(.s_axis_data_width(s_axis_data_width), .m_axis_data_width(m_axis_data_width)))
	
	function new(string name = "AXIFrameBufferEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.m_axis_agt = AXISMasterAgent #(.data_width(s_axis_data_width), .user_width(0))::
			type_id::create("agt1", this);
		this.m_axis_agt.is_active = UVM_ACTIVE;
		this.s_axis_agt = AXISSlaveAgent #(.data_width(m_axis_data_width), .user_width(8))::
			type_id::create("agt2", this);
		this.s_axis_agt.is_active = UVM_ACTIVE;
		this.s_axi_agt = AXISlaveAgent #(.out_drive_t(out_drive_t), .addr_width(32), .data_width(32), 
			.bresp_width(2), .rresp_width(2))::type_id::create("agt3", this);
		this.s_axi_agt.is_active = UVM_PASSIVE;
		
		// 创建通信端口
		this.m_axis_trans_port = new("m_axis_trans_port", this);
		this.s_axis_trans_port = new("s_axis_trans_port", this);
		this.axi_rd_trans_port = new("axi_rd_trans_port", this);
		this.axi_wt_trans_port = new("axi_wt_trans_port", this);
		
		// 创建通信fifo
		this.m_axis_agt_fifo = new("m_axis_agt_fifo", this);
		this.s_axis_agt_fifo = new("s_axis_agt_fifo", this);
		this.s_axi_agt_rd_fifo = new("s_axi_agt_rd_fifo", this);
		this.s_axi_agt_wt_fifo = new("s_axi_agt_wt_fifo", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.m_axis_agt.axis_analysis_port.connect(this.m_axis_agt_fifo.analysis_export);
		this.m_axis_trans_port.connect(this.m_axis_agt_fifo.blocking_get_export);
		this.s_axis_agt.axis_analysis_port.connect(this.s_axis_agt_fifo.analysis_export);
		this.s_axis_trans_port.connect(this.s_axis_agt_fifo.blocking_get_export);
		this.s_axi_agt.rd_trans_analysis_port.connect(this.s_axi_agt_rd_fifo.analysis_export);
		this.axi_rd_trans_port.connect(this.s_axi_agt_rd_fifo.blocking_get_export);
		this.s_axi_agt.wt_trans_analysis_port.connect(this.s_axi_agt_wt_fifo.analysis_export);
		this.axi_wt_trans_port.connect(this.s_axi_agt_wt_fifo.blocking_get_export);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				this.m_axis_trans_port.get(this.m_axis_trans);
				this.m_axis_trans.print(); // 打印事务
			end
			forever
			begin
				this.s_axis_trans_port.get(this.s_axis_trans);
				this.s_axis_trans.print(); // 打印事务
			end
			forever
			begin
				this.axi_rd_trans_port.get(this.s_axi_rd_trans);
				this.s_axi_rd_trans.print(); // 打印事务
			end
			forever
			begin
				this.axi_wt_trans_port.get(this.s_axi_wt_trans);
				this.s_axi_wt_trans.print(); // 打印事务
			end
		join_none
	endtask
	
endclass
	
`endif
