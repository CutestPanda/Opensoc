`timescale 1ns / 1ps

`ifndef __VSQR_H

`define __VSQR_H

`include "transactions.sv"
`include "sequencers.sv"

class DcdDsptcVsqr extends uvm_sequencer;
	
	AXISSequencer #(.data_width(128), .user_width(4)) m_axis_if_res_sqr; // 取指结果AXIS主机
	AXISSequencer #(.data_width(144), .user_width(0)) s_axis_alu_sqr; // ALU执行请求AXIS从机
	AXISSequencer #(.data_width(144), .user_width(0)) s_axis_lsu_sqr; // LSU执行请求AXIS从机
	AXISSequencer #(.data_width(144), .user_width(0)) s_axis_csr_rw_sqr; // CSR原子读写单元执行请求AXIS从机
	AXISSequencer #(.data_width(144), .user_width(0)) s_axis_mul_sqr; // 乘法器执行请求AXIS从机
	AXISSequencer #(.data_width(144), .user_width(0)) s_axis_div_sqr; // 除法器执行请求AXIS从机
	
	`uvm_component_utils(DcdDsptcVsqr)
	
	function new(string name = "DcdDsptcVsqr", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
endclass
	
`endif
