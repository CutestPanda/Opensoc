`timescale 1ns / 1ps

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"

/** 环境:小胖达risc-v取指单元 **/
class PandaRiscVIfuEnv extends uvm_env;
	
	// 组件
	local AXISSlaveAgent #(.data_width(128), .user_width(4)) s_axis_agt; // AXIS从机代理
	
	// 通信端口
	local uvm_blocking_get_port #(AXISTrans #(.data_width(128), .user_width(4))) s_axis_trans_port;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(128), .user_width(4))) s_axis_agt_fifo;
	
	// 事务
	local AXISTrans #(.data_width(128), .user_width(4)) s_axis_trans;
	
	// 注册component
	`uvm_component_utils(PandaRiscVIfuEnv)
	
	function new(string name = "PandaRiscVIfuEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.s_axis_agt = AXISSlaveAgent #(.data_width(128), .user_width(4))::
			type_id::create("agt1", this);
		this.s_axis_agt.is_active = UVM_ACTIVE;
		
		// 创建通信端口
		this.s_axis_trans_port = new("s_axis_trans_port", this);
		
		// 创建通信fifo
		this.s_axis_agt_fifo = new("s_axis_agt_fifo", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.s_axis_agt.axis_analysis_port.connect(this.s_axis_agt_fifo.analysis_export);
		this.s_axis_trans_port.connect(this.s_axis_agt_fifo.blocking_get_export);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		forever
		begin
			this.s_axis_trans_port.get(this.s_axis_trans);
			print_ifu_res(this.s_axis_trans);
		end
	endtask
	
	static function void print_ifu_res(ref AXISTrans #(.data_width(128), .user_width(4)) trans);
		$display("-----------------RiscVIfuResTrans-----------------");
		
		$display("Inst: %7.7b %5.5b %5.5b %3.3b %5.5b %7.7b", 
			trans.data[0][31:25], trans.data[0][24:20], trans.data[0][19:15], 
			trans.data[0][14:12], trans.data[0][11:7], trans.data[0][6:0]);
		$display("PC: %d", trans.data[0][127:96]);
		$display("ToJump: %b", trans.user[0][3]);
		$display("IllegalInst: %b", trans.user[0][2]);
		$display("ImemAccessCode: %s", 
			(trans.user[0][1:0] == 2'b00) ? "NORMAL":
			(trans.user[0][1:0] == 2'b01) ? "PC_UNALIGNED":
			(trans.user[0][1:0] == 2'b10) ? "BUS_ERR":
			                                "TIMEOUT");
		$display("CsrAddr: %d", trans.data[0][76:65]);
		$display("Rs1Vld: %d", trans.data[0][64]);
		$display("Rs2Vld: %d", trans.data[0][63]);
		$display("RdVld: %d", trans.data[0][62]);
		$display("JumpOfsImm: %d", trans.data[0][61:41]);
		$display("IsBInst: %b", trans.data[0][40]);
		$display("IsJalInst: %b", trans.data[0][39]);
		$display("IsJalrInst: %b", trans.data[0][38]);
		$display("IsCsrRwInst: %b", trans.data[0][37]);
		$display("IsLoadInst: %b", trans.data[0][36]);
		$display("IsStoreInst: %b", trans.data[0][35]);
		$display("IsMulInst: %b", trans.data[0][34]);
		$display("IsDivInst: %b", trans.data[0][33]);
		$display("IsRemInst: %b", trans.data[0][32]);
		
		$display("--------------------------------------------------");
	endfunction
	
endclass
	
`endif
