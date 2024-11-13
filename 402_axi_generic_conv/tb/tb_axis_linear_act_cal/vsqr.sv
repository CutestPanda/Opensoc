`timescale 1ns / 1ps

`ifndef __VSQR_H

`define __VSQR_H

`include "transactions.sv"
`include "sequencers.sv"

class AXISLnActCalVsqr #(
	integer cal_width = 16 // 计算位宽(对于x/y/z和a/b/c来说, 可选8 | 16)
)extends uvm_sequencer;
	
	AXISSequencer #(.data_width(cal_width*2), .user_width(16)) m_axis_conv_res_sqr; // 多通道卷积计算结果AXIS主机
	AXISSequencer #(.data_width(64), .user_width(2)) m_axis_linear_pars_sqr; // 线性参数流AXIS主机
	
	`uvm_component_param_utils(AXISLnActCalVsqr #(.cal_width(cal_width)))
	
	function new(string name = "AXISLnActCalVsqr", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
endclass
	
`endif
