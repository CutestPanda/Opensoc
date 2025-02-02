/*
MIT License

Copyright (c) 2024 Panda, 2257691535@qq.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

`timescale 1ns / 1ps

`ifndef __SEQUENCER_H

`define __SEQUENCER_H

`include "transactions.sv"

// 打开相应宏以启用sequencer
// `define BlkCtrlSeqr
`define AXISeqr
// `define APBSeqr
`define AXISSeqr
// `define AHBSeqr

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

`endif
