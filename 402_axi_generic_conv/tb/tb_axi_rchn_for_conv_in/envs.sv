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

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"

/** 环境:用于获取输入特征图/卷积核的AXI读通道 **/
class AxiRchnForConvInEnv #(
	integer s_axis_data_width = 8, // 从机数据位宽
	integer m_axis_data_width = 8 // 主机数据位宽
)extends uvm_env;
	
	// 组件
	local AXISMasterAgent #(.data_width(s_axis_data_width), .user_width(0)) m_axis_agt; // AXIS主机代理
	local AXISSlaveAgent #(.data_width(m_axis_data_width), .user_width(0)) s_axis_agt; // AXIS从机代理
	
	// 通信端口
	local uvm_blocking_get_port #(AXISTrans #(.data_width(s_axis_data_width), .user_width(0))) m_axis_trans_port;
	local uvm_blocking_get_port #(AXISTrans #(.data_width(m_axis_data_width), .user_width(0))) s_axis_trans_port;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(s_axis_data_width), .user_width(0))) m_axis_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(m_axis_data_width), .user_width(0))) s_axis_agt_fifo;
	
	// 事务
	local AXISTrans #(.data_width(s_axis_data_width), .user_width(0)) m_axis_trans;
	local AXISTrans #(.data_width(m_axis_data_width), .user_width(0)) s_axis_trans;
	
	// 注册component
	`uvm_component_param_utils(AxiRchnForConvInEnv #(.s_axis_data_width(s_axis_data_width), .m_axis_data_width(m_axis_data_width)))
	
	function new(string name = "AxiRchnForConvInEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.m_axis_agt = AXISMasterAgent #(.data_width(s_axis_data_width), .user_width(0))::
			type_id::create("agt1", this);
		this.m_axis_agt.is_active = UVM_ACTIVE;
		this.s_axis_agt = AXISSlaveAgent #(.data_width(m_axis_data_width), .user_width(0))::
			type_id::create("agt2", this);
		this.s_axis_agt.is_active = UVM_ACTIVE;
		
		// 创建通信端口
		this.m_axis_trans_port = new("m_axis_trans_port", this);
		this.s_axis_trans_port = new("s_axis_trans_port", this);
		
		// 创建通信fifo
		this.m_axis_agt_fifo = new("m_axis_agt_fifo", this);
		this.s_axis_agt_fifo = new("s_axis_agt_fifo", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.m_axis_agt.axis_analysis_port.connect(this.m_axis_agt_fifo.analysis_export);
		this.m_axis_trans_port.connect(this.m_axis_agt_fifo.blocking_get_export);
		this.s_axis_agt.axis_analysis_port.connect(this.s_axis_agt_fifo.analysis_export);
		this.s_axis_trans_port.connect(this.s_axis_agt_fifo.blocking_get_export);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				this.m_axis_trans_port.get(this.m_axis_trans);
				// this.m_axis_trans.print(); // 打印事务
			end
			forever
			begin
				this.s_axis_trans_port.get(this.s_axis_trans);
				// this.s_axis_trans.print(); // 打印事务
			end
		join_none
	endtask
	
endclass
	
`endif
