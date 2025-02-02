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

class DcdDsptcVsqr extends uvm_sequencer;
	
	AXISSequencer #(.data_width(128), .user_width(4)) m_axis_if_res_sqr; // 取指结果AXIS主机
	AXISSequencer #(.data_width(160), .user_width(0)) s_axis_alu_sqr; // ALU执行请求AXIS从机
	AXISSequencer #(.data_width(160), .user_width(0)) s_axis_lsu_sqr; // LSU执行请求AXIS从机
	AXISSequencer #(.data_width(160), .user_width(0)) s_axis_csr_rw_sqr; // CSR原子读写单元执行请求AXIS从机
	AXISSequencer #(.data_width(160), .user_width(0)) s_axis_mul_sqr; // 乘法器执行请求AXIS从机
	AXISSequencer #(.data_width(160), .user_width(0)) s_axis_div_sqr; // 除法器执行请求AXIS从机
	
	`uvm_component_utils(DcdDsptcVsqr)
	
	function new(string name = "DcdDsptcVsqr", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
endclass
	
`endif
