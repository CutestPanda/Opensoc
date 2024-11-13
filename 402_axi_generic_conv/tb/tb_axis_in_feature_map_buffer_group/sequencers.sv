`timescale 1ns / 1ps

`ifndef __SEQUENCER_H

`define __SEQUENCER_H

`include "transactions.sv"

// 打开以下宏以启用sequencer
// `define BlkCtrlSeqr
// `define AXISeqr
// `define APBSeqr
`define AXISSeqr
// `define AHBSeqr
// `define ReqAckSeqr
// `define ICBSeqr

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
class APBSequencer  #(
    integer addr_width = 32, // 地址位宽(1~32)
    integer data_width = 32 // 数据位宽(8 | 16 | 32)
)extends uvm_sequencer #(APBTrans #(.addr_width(addr_width), .data_width(data_width)));
	
	// 注册component
	`uvm_component_utils(APBSequencer #(.addr_width(addr_width), .data_width(data_width)))
	
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

/** 序列发生器:AHB **/
`ifdef AHBSeqr
class AHBSequencer #(
    integer addr_width = 32, // 地址位宽(10~64)
    integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
    integer burst_width = 3, // 突发类型位宽(0~3)
    integer prot_width = 4, // 保护类型位宽(0 | 4 | 7)
    integer master_width = 1 // 主机标识位宽(0~8)
)extends uvm_sequencer #(AHBTrans #(.addr_width(addr_width), .data_width(data_width), .burst_width(burst_width), 
	.prot_width(prot_width), .master_width(master_width)));
	
	// 注册component
	`uvm_component_param_utils(AHBSequencer #(.addr_width(addr_width), .data_width(data_width), .burst_width(burst_width), .prot_width(prot_width), .master_width(master_width)))
	
	function new(string name = "AHBSequencer", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
endclass
`endif

/** 序列发生器:req-ack **/
`ifdef ReqAckSeqr
class ReqAckSequencer #(
    integer req_payload_width = 32, // 请求数据位宽
	integer resp_payload_width = 32 // 响应数据位宽
)extends uvm_sequencer #(ReqAckTrans #(.req_payload_width(req_payload_width), .resp_payload_width(resp_payload_width)));
	
	// 注册component
	`uvm_component_param_utils(ReqAckSequencer #(.req_payload_width(req_payload_width), .resp_payload_width(resp_payload_width)))
	
	function new(string name = "ReqAckSequencer", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
endclass
`endif

/** 序列发生器:ICB **/
`ifdef ICBSeqr
class ICBSequencer #(
	integer addr_width = 32, // 地址位宽
	integer data_width = 32 // 数据位宽
)extends uvm_sequencer #(ICBTrans #(.addr_width(addr_width), .data_width(data_width)));
	
	// 注册component
	`uvm_component_param_utils(ICBSequencer #(.addr_width(addr_width), .data_width(data_width)))
	
	function new(string name = "ICBSequencer", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
endclass
`endif

`endif
