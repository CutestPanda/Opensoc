`timescale 1ns / 1ps

`ifndef __VSQR_H

`define __VSQR_H

`include "transactions.sv"
`include "sequencers.sv"

class LsuVsqr extends uvm_sequencer;
	
	AXISSequencer #(.data_width(64), .user_width(9)) m_axis_req_ls_sqr; // 访存请求AXIS主机
	AXISSequencer #(.data_width(64), .user_width(8)) s_axis_resp_ls_sqr; // 访存结果AXIS从机
	ICBSequencer #(.addr_width(32), .data_width(32)) s_data_icb_sqr; // 数据ICB从机
	
	`uvm_component_utils(LsuVsqr)
	
	function new(string name = "LsuVsqr", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
endclass
	
`endif
