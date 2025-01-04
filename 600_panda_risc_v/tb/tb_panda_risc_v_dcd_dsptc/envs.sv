`timescale 1ns / 1ps

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"
`include "vsqr.sv"

/** 环境:译码/派遣单元 **/
class DcdDsptcEnv #(
	real simulation_delay = 1 // 仿真延时
)extends uvm_env;
	
	// 虚拟Sequencer
	DcdDsptcVsqr vsqr;
	
	// 组件
	local AXISMasterAgent #(.out_drive_t(simulation_delay), .data_width(128), .user_width(4)) m_axis_if_res_agt; // 取指结果AXIS主机代理
	local AXISSlaveAgent #(.out_drive_t(simulation_delay), .data_width(160), .user_width(0)) s_axis_alu_agt; // ALU执行请求AXIS从机代理
	local AXISSlaveAgent #(.out_drive_t(simulation_delay), .data_width(160), .user_width(0)) s_axis_lsu_agt; // LSU执行请求AXIS从机代理
	local AXISSlaveAgent #(.out_drive_t(simulation_delay), .data_width(160), .user_width(0)) s_axis_csr_rw_agt; // CSR原子读写单元执行请求AXIS从机代理
	local AXISSlaveAgent #(.out_drive_t(simulation_delay), .data_width(160), .user_width(0)) s_axis_mul_agt; // 乘法器执行请求AXIS从机代理
	local AXISSlaveAgent #(.out_drive_t(simulation_delay), .data_width(160), .user_width(0)) s_axis_div_agt; // 除法器执行请求AXIS从机代理
	
	// 通信端口
	local uvm_blocking_get_port #(AXISTrans #(.data_width(128), .user_width(4))) m_axis_if_res_trans_port;
	local uvm_blocking_get_port #(AXISTrans #(.data_width(160), .user_width(0))) s_axis_alu_trans_port;
	local uvm_blocking_get_port #(AXISTrans #(.data_width(160), .user_width(0))) s_axis_lsu_trans_port;
	local uvm_blocking_get_port #(AXISTrans #(.data_width(160), .user_width(0))) s_axis_csr_rw_trans_port;
	local uvm_blocking_get_port #(AXISTrans #(.data_width(160), .user_width(0))) s_axis_mul_trans_port;
	local uvm_blocking_get_port #(AXISTrans #(.data_width(160), .user_width(0))) s_axis_div_trans_port;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(128), .user_width(4))) m_axis_if_res_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(160), .user_width(0))) s_axis_alu_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(160), .user_width(0))) s_axis_lsu_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(160), .user_width(0))) s_axis_csr_rw_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(160), .user_width(0))) s_axis_mul_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(160), .user_width(0))) s_axis_div_agt_fifo;
	
	// 事务
	local AXISTrans #(.data_width(128), .user_width(4)) m_axis_if_res_trans;
	local AXISTrans #(.data_width(160), .user_width(0)) s_axis_alu_trans;
	local AXISTrans #(.data_width(160), .user_width(0)) s_axis_lsu_trans;
	local AXISTrans #(.data_width(160), .user_width(0)) s_axis_csr_rw_trans;
	local AXISTrans #(.data_width(160), .user_width(0)) s_axis_mul_trans;
	local AXISTrans #(.data_width(160), .user_width(0)) s_axis_div_trans;
	
	// 注册component
	`uvm_component_param_utils(DcdDsptcEnv #(.simulation_delay(simulation_delay)))
	
	function new(string name = "DcdDsptcEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.m_axis_if_res_agt = AXISMasterAgent #(.out_drive_t(simulation_delay), .data_width(128), .user_width(4))::
			type_id::create("agt1", this);
		this.m_axis_if_res_agt.is_active = UVM_ACTIVE;
		this.s_axis_alu_agt = AXISSlaveAgent #(.out_drive_t(simulation_delay), .data_width(160), .user_width(0))::
			type_id::create("agt2", this);
		this.s_axis_alu_agt.is_active = UVM_ACTIVE;
		this.s_axis_alu_agt.use_sqr = 1'b1;
		this.s_axis_lsu_agt = AXISSlaveAgent #(.out_drive_t(simulation_delay), .data_width(160), .user_width(0))::
			type_id::create("agt3", this);
		this.s_axis_lsu_agt.is_active = UVM_ACTIVE;
		this.s_axis_lsu_agt.use_sqr = 1'b1;
		this.s_axis_csr_rw_agt = AXISSlaveAgent #(.out_drive_t(simulation_delay), .data_width(160), .user_width(0))::
			type_id::create("agt4", this);
		this.s_axis_csr_rw_agt.is_active = UVM_ACTIVE;
		this.s_axis_csr_rw_agt.use_sqr = 1'b1;
		this.s_axis_mul_agt = AXISSlaveAgent #(.out_drive_t(simulation_delay), .data_width(160), .user_width(0))::
			type_id::create("agt5", this);
		this.s_axis_mul_agt.is_active = UVM_ACTIVE;
		this.s_axis_mul_agt.use_sqr = 1'b1;
		this.s_axis_div_agt = AXISSlaveAgent #(.out_drive_t(simulation_delay), .data_width(160), .user_width(0))::
			type_id::create("agt6", this);
		this.s_axis_div_agt.is_active = UVM_ACTIVE;
		this.s_axis_div_agt.use_sqr = 1'b1;
		
		// 创建通信端口
		this.m_axis_if_res_trans_port = new("m_axis_if_res_trans_port", this);
		this.s_axis_alu_trans_port = new("s_axis_alu_trans_port", this);
		this.s_axis_lsu_trans_port = new("s_axis_lsu_trans_port", this);
		this.s_axis_csr_rw_trans_port = new("s_axis_csr_rw_trans_port", this);
		this.s_axis_mul_trans_port = new("s_axis_mul_trans_port", this);
		this.s_axis_div_trans_port = new("s_axis_div_trans_port", this);
		
		// 创建通信fifo
		this.m_axis_if_res_agt_fifo = new("m_axis_if_res_agt_fifo", this);
		this.s_axis_alu_agt_fifo = new("s_axis_alu_agt_fifo", this);
		this.s_axis_lsu_agt_fifo = new("s_axis_lsu_agt_fifo", this);
		this.s_axis_csr_rw_agt_fifo = new("s_axis_csr_rw_agt_fifo", this);
		this.s_axis_mul_agt_fifo = new("s_axis_mul_agt_fifo", this);
		this.s_axis_div_agt_fifo = new("s_axis_div_agt_fifo", this);
		
		// 创建虚拟Sequencer
		this.vsqr = DcdDsptcVsqr::type_id::create("v_sqr", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.m_axis_if_res_agt.axis_analysis_port.connect(this.m_axis_if_res_agt_fifo.analysis_export);
		this.m_axis_if_res_trans_port.connect(this.m_axis_if_res_agt_fifo.blocking_get_export);
		this.s_axis_alu_agt.axis_analysis_port.connect(this.s_axis_alu_agt_fifo.analysis_export);
		this.s_axis_alu_trans_port.connect(this.s_axis_alu_agt_fifo.blocking_get_export);
		this.s_axis_lsu_agt.axis_analysis_port.connect(this.s_axis_lsu_agt_fifo.analysis_export);
		this.s_axis_lsu_trans_port.connect(this.s_axis_lsu_agt_fifo.blocking_get_export);
		this.s_axis_csr_rw_agt.axis_analysis_port.connect(this.s_axis_csr_rw_agt_fifo.analysis_export);
		this.s_axis_csr_rw_trans_port.connect(this.s_axis_csr_rw_agt_fifo.blocking_get_export);
		this.s_axis_mul_agt.axis_analysis_port.connect(this.s_axis_mul_agt_fifo.analysis_export);
		this.s_axis_mul_trans_port.connect(this.s_axis_mul_agt_fifo.blocking_get_export);
		this.s_axis_div_agt.axis_analysis_port.connect(this.s_axis_div_agt_fifo.analysis_export);
		this.s_axis_div_trans_port.connect(this.s_axis_div_agt_fifo.blocking_get_export);
		
		this.vsqr.m_axis_if_res_sqr = this.m_axis_if_res_agt.sequencer;
		this.vsqr.s_axis_alu_sqr = this.s_axis_alu_agt.sequencer;
		this.vsqr.s_axis_lsu_sqr = this.s_axis_lsu_agt.sequencer;
		this.vsqr.s_axis_csr_rw_sqr = this.s_axis_csr_rw_agt.sequencer;
		this.vsqr.s_axis_mul_sqr = this.s_axis_mul_agt.sequencer;
		this.vsqr.s_axis_div_sqr = this.s_axis_div_agt.sequencer;
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				this.m_axis_if_res_trans_port.get(this.m_axis_if_res_trans);
				// this.m_axis_if_res_trans.print();
			end
			forever
			begin
				this.s_axis_alu_trans_port.get(this.s_axis_alu_trans);
				// this.s_axis_alu_trans.print();
			end
			forever
			begin
				this.s_axis_lsu_trans_port.get(this.s_axis_lsu_trans);
				// this.s_axis_lsu_trans.print();
			end
			forever
			begin
				this.s_axis_csr_rw_trans_port.get(this.s_axis_csr_rw_trans);
				// this.s_axis_csr_rw_trans.print();
			end
			forever
			begin
				this.s_axis_mul_trans_port.get(this.s_axis_mul_trans);
				// this.s_axis_mul_trans.print();
			end
			forever
			begin
				this.s_axis_div_trans_port.get(this.s_axis_div_trans);
				// this.s_axis_div_trans.print();
			end
		join
	endtask
	
endclass
	
`endif
