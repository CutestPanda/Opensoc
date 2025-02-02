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
`include "scoreboards.sv"

/** 环境:axi-sdram **/
class AXISdramEnv extends uvm_env;

	// 组件
	local AXIMasterAgent #(.out_drive_t(0), .addr_width(32), 
		.data_width(32), .bresp_width(2), .rresp_width(2)) m_axi_agents[0:2];
	local AXISdramEnvScoreboard scoreboard;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2))) axi_rd_agt_scb_fifo[0:2];
	local uvm_tlm_analysis_fifo #(AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2))) axi_wt_agt_scb_fifo[0:2];
	
	// 注册component
	`uvm_component_utils(AXISdramEnv)
	
	function new(string name = "AXISdramEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.m_axi_agents[0] = AXIMasterAgent #(.out_drive_t(0), .addr_width(32), 
			.data_width(32), .bresp_width(2), .rresp_width(2))::type_id::create("agt", this);
		this.m_axi_agents[0].is_active = UVM_ACTIVE;
		this.m_axi_agents[1] = AXIMasterAgent #(.out_drive_t(0), .addr_width(32), 
			.data_width(32), .bresp_width(2), .rresp_width(2))::type_id::create("agt2", this);
		this.m_axi_agents[1].is_active = UVM_ACTIVE;
		this.m_axi_agents[2] = AXIMasterAgent #(.out_drive_t(0), .addr_width(32), 
			.data_width(32), .bresp_width(2), .rresp_width(2))::type_id::create("agt3", this);
		this.m_axi_agents[2].is_active = UVM_ACTIVE;
		
		// 创建scoreboard
		this.scoreboard = AXISdramEnvScoreboard::type_id::create("scb", this);
		
		// 创建通信fifo
		this.axi_rd_agt_scb_fifo[0] = new("axi_rd_agt_scb_fifo0", this);
		this.axi_rd_agt_scb_fifo[1] = new("axi_rd_agt_scb_fifo1", this);
		this.axi_rd_agt_scb_fifo[2] = new("axi_rd_agt_scb_fifo2", this);
		this.axi_wt_agt_scb_fifo[0] = new("axi_wt_agt_scb_fifo0", this);
		this.axi_wt_agt_scb_fifo[1] = new("axi_wt_agt_scb_fifo1", this);
		this.axi_wt_agt_scb_fifo[2] = new("axi_wt_agt_scb_fifo2", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		// 连接agent和scoreboard的通信端口
		for(int i = 0;i < 3;i++)
		begin
			this.m_axi_agents[i].rd_trans_analysis_port.connect(this.axi_rd_agt_scb_fifo[i].analysis_export);
			this.scoreboard.rd_trans_port[i].connect(this.axi_rd_agt_scb_fifo[i].blocking_get_export);
			
			this.m_axi_agents[i].wt_trans_analysis_port.connect(this.axi_wt_agt_scb_fifo[i].analysis_export);
			this.scoreboard.wt_trans_port[i].connect(this.axi_wt_agt_scb_fifo[i].blocking_get_export);
		end
	endfunction
	
endclass
	
`endif
