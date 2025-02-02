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

`ifndef __VSQR_H

`define __VSQR_H

`include "transactions.sv"
`include "sequencers.sv"

class LsuVsqr extends uvm_sequencer;
	
	AXISSequencer #(.data_width(64), .user_width(9)) m_axis_req_ls_sqr; // 访存请求AXIS主机
	AXISSequencer #(.data_width(64), .user_width(16)) s_axis_resp_ls_sqr; // 访存结果AXIS从机
	ICBSequencer #(.addr_width(32), .data_width(32)) s_data_icb_sqr; // 数据ICB从机
	
	`uvm_component_utils(LsuVsqr)
	
	function new(string name = "LsuVsqr", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
endclass
	
`endif
