`timescale 1ns / 1ps

`ifndef __SEQUENCER_H

`define __SEQUENCER_H

`include "transactions.sv"

// `define BlkCtrlSeqr
`define AXISeqr
// `define APBSeqr
// `define AXISSeqr

/** 序列发生器:块级控制 **/
`ifdef BlkCtrlSeqr
class BlkCtrlSeqr extends uvm_sequencer #(BlkCtrlTrans);
	
	// 注册component
	`uvm_component_utils(BlkCtrlSeqr)
	
	function new(string name = "BlkCtrlSeqr", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
endclass
`endif

/** 序列发生器:AXI **/
`ifdef AXISeqr
class AXISequencer #(
	integer addr_width = 32, // 地址位宽(1~64)
	integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
    integer bresp_width = 2, // 写响应信号位宽(0 | 2 | 3)
    integer rresp_width = 2 // 读响应信号位宽(0 | 2 | 3)
)extends uvm_sequencer #(AXITrans #(.addr_width(addr_width), .data_width(data_width), .bresp_width(bresp_width), .rresp_width(rresp_width)));
	
	// 注册component
	`uvm_component_param_utils(AXISequencer #(.addr_width(addr_width), .data_width(data_width), .bresp_width(bresp_width), .rresp_width(rresp_width)))
	
	function new(string name = "AXISequencer", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
endclass
`endif

/** 序列发生器:APB **/
`ifdef APBSeqr
class APBSequencer extends uvm_sequencer #(APBTrans);
	
	// 注册component
	`uvm_component_utils(APBSequencer)
	
	function new(string name = "APBSequencer", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
endclass
`endif

/** 序列发生器:AXIS **/
`ifdef AXISSeqr
class AXISSequencer #(
    integer data_width = 32, // 数据位宽(必须能被8整除)
    integer user_width = 0 // 用户数据位宽
)extends uvm_sequencer #(AXISTrans #(.data_width(data_width), .user_width(user_width)));
	
	// 注册component
	`uvm_component_param_utils(AXISSequencer #(.data_width(data_width), .user_width(user_width)))
	
	function new(string name = "AXISSequencer", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
endclass
`endif

`endif
