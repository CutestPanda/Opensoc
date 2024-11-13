`timescale 1ns / 1ps

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"

/** 环境:AXIS数据FIFO **/
class AxisDataFifoEnv #(
	integer data_width = 8, // 数据位宽(必须能被8整除, 且>0)
	integer user_width = 1 // user信号位宽(必须>0)
)extends uvm_env;
	
	// 组件
	local AXISMasterAgent #(.data_width(data_width), .user_width(user_width)) m_axis_agt; // AXIS主机代理
	local AXISSlaveAgent #(.data_width(data_width), .user_width(user_width)) s_axis_agt; // AXIS从机代理
	
	// 通信端口
	local uvm_blocking_get_port #(AXISTrans #(.data_width(data_width), .user_width(user_width))) m_axis_trans_port;
	local uvm_blocking_get_port #(AXISTrans #(.data_width(data_width), .user_width(user_width))) s_axis_trans_port;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(data_width), .user_width(user_width))) m_axis_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(data_width), .user_width(user_width))) s_axis_agt_fifo;
	
	// 事务
	local AXISTrans #(.data_width(data_width), .user_width(user_width)) m_axis_trans;
	local AXISTrans #(.data_width(data_width), .user_width(user_width)) s_axis_trans;
	
	// 注册component
	`uvm_component_param_utils(AxisDataFifoEnv #(.data_width(data_width), .user_width(user_width)))
	
	function new(string name = "AxisDataFifoEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.m_axis_agt = AXISMasterAgent #(.data_width(data_width), .user_width(user_width))::
			type_id::create("agt1", this);
		this.m_axis_agt.is_active = UVM_ACTIVE;
		this.s_axis_agt = AXISSlaveAgent #(.data_width(data_width), .user_width(user_width))::
			type_id::create("agt2", this);
		this.s_axis_agt.is_active = UVM_ACTIVE;
		
		// 创建通信端口
		this.m_axis_trans_port = new("m_axis_trans_port", this);
		this.s_axis_trans_port = new("s_axis_trans_port", this);
		
		// 创建通信fifo
		this.m_axis_agt_fifo = new("m_axis_agt_fifo", this);
		this.s_axis_agt_fifo = new("s_axis_agt_fifo", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.m_axis_agt.axis_analysis_port.connect(this.m_axis_agt_fifo.analysis_export);
		this.m_axis_trans_port.connect(this.m_axis_agt_fifo.blocking_get_export);
		this.s_axis_agt.axis_analysis_port.connect(this.s_axis_agt_fifo.analysis_export);
		this.s_axis_trans_port.connect(this.s_axis_agt_fifo.blocking_get_export);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				this.m_axis_trans_port.get(this.m_axis_trans);
				`uvm_info("AxisDataFifoEnv", "m_axis_trans -> ", UVM_LOW)
				this.m_axis_trans.print(); // 打印事务
			end
			forever
			begin
				this.s_axis_trans_port.get(this.s_axis_trans);
				`uvm_info("AxisDataFifoEnv", "s_axis_trans -> ", UVM_LOW)
				this.s_axis_trans.print(); // 打印事务
			end
		join_none
	endtask
	
endclass
	
`endif