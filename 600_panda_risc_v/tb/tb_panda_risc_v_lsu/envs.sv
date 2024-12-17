`timescale 1ns / 1ps

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"

/** 环境:LSU **/
class LsuEnv #(
	real simulation_delay = 1 // 仿真延时
)extends uvm_env;
	
	// 组件
	AXISMasterAgent #(.out_drive_t(simulation_delay), .data_width(64), .user_width(9)) m_axis_req_ls_agt; // 访存请求AXIS主机代理
	AXISSlaveAgent #(.out_drive_t(simulation_delay), .data_width(64), .user_width(8)) s_axis_resp_ls_agt; // 访存结果AXIS从机代理
	ICBSlaveAgent #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32)) s_data_icb_agt; // 数据ICB从机代理
	
	// 通信端口
	local uvm_blocking_get_port #(AXISTrans #(.data_width(64), .user_width(9))) m_axis_req_ls_trans_port;
	local uvm_blocking_get_port #(AXISTrans #(.data_width(64), .user_width(8))) s_axis_resp_ls_trans_port;
	local uvm_blocking_get_port #(ICBTrans #(.addr_width(32), .data_width(32))) s_data_icb_trans_port;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(64), .user_width(9))) m_axis_req_ls_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(64), .user_width(8))) s_axis_resp_ls_agt_fifo;
	local uvm_tlm_analysis_fifo #(ICBTrans #(.addr_width(32), .data_width(32))) s_data_icb_agt_fifo;
	
	// 事务
	local AXISTrans #(.data_width(64), .user_width(9)) m_axis_req_ls_trans;
	local AXISTrans #(.data_width(64), .user_width(8)) s_axis_resp_ls_trans;
	local ICBTrans #(.addr_width(32), .data_width(32)) s_data_icb_trans;
	
	// 注册component
	`uvm_component_param_utils(LsuEnv #(.simulation_delay(simulation_delay)))
	
	function new(string name = "LsuEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.m_axis_req_ls_agt = AXISMasterAgent #(.out_drive_t(simulation_delay), .data_width(64), .user_width(9))::
			type_id::create("agt1", this);
		this.m_axis_req_ls_agt.is_active = UVM_ACTIVE;
		this.s_axis_resp_ls_agt = AXISSlaveAgent #(.out_drive_t(simulation_delay), .data_width(64), .user_width(8))::
			type_id::create("agt2", this);
		this.s_axis_resp_ls_agt.is_active = UVM_ACTIVE;
		this.s_axis_resp_ls_agt.use_sqr = 1'b1;
		this.s_data_icb_agt = ICBSlaveAgent #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32))::
			type_id::create("agt3", this);
		this.s_data_icb_agt.is_active = UVM_ACTIVE;
		
		// 创建通信端口
		this.m_axis_req_ls_trans_port = new("m_axis_req_ls_trans_port", this);
		this.s_axis_resp_ls_trans_port = new("s_axis_resp_ls_trans_port", this);
		this.s_data_icb_trans_port = new("s_data_icb_trans_port", this);
		
		// 创建通信fifo
		this.m_axis_req_ls_agt_fifo = new("m_axis_req_ls_agt_fifo", this);
		this.s_axis_resp_ls_agt_fifo = new("s_axis_resp_ls_agt_fifo", this);
		this.s_data_icb_agt_fifo = new("s_data_icb_agt_fifo", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.m_axis_req_ls_agt.axis_analysis_port.connect(this.m_axis_req_ls_agt_fifo.analysis_export);
		this.m_axis_req_ls_trans_port.connect(this.m_axis_req_ls_agt_fifo.blocking_get_export);
		this.s_axis_resp_ls_agt.axis_analysis_port.connect(this.s_axis_resp_ls_agt_fifo.analysis_export);
		this.s_axis_resp_ls_trans_port.connect(this.s_axis_resp_ls_agt_fifo.blocking_get_export);
		this.s_data_icb_agt.icb_analysis_port.connect(this.s_data_icb_agt_fifo.analysis_export);
		this.s_data_icb_trans_port.connect(this.s_data_icb_agt_fifo.blocking_get_export);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				this.m_axis_req_ls_trans_port.get(this.m_axis_req_ls_trans);
				// this.m_axis_req_ls_trans.print(); // 打印事务
			end
			forever
			begin
				this.s_axis_resp_ls_trans_port.get(this.s_axis_resp_ls_trans);
				// this.s_axis_resp_ls_trans.print(); // 打印事务
			end
			forever
			begin
				this.s_data_icb_trans_port.get(this.s_data_icb_trans);
				// this.s_data_icb_trans.print(); // 打印事务
			end
		join
	endtask
	
endclass
	
`endif
