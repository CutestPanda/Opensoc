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

/** 环境:指令总线控制单元 **/
class IBusCtrlerEnv #(
	integer IBUS_TID_WIDTH = 8, // 指令总线事务ID位宽(1~16)
	real SIM_DELAY = 1.0 // 仿真延时
)extends uvm_env;
	
	// 组件
	local AXISMasterAgent #(.out_drive_t(SIM_DELAY), .data_width(32), .user_width(IBUS_TID_WIDTH)) m_axis_agt; // AXIS主机代理
	local ICBSlaveAgent #(.out_drive_t(SIM_DELAY), .addr_width(32), .data_width(32)) s_icb_agt; // ICB从机代理
	local AXISSlaveAgent #(.out_drive_t(SIM_DELAY), .data_width(64), .user_width(2+IBUS_TID_WIDTH)) s_axis_agt; // AXIS从机代理
	local ReqAckMasterAgent #(.out_drive_t(SIM_DELAY), .req_payload_width(32), .resp_payload_width(32)) req_agt; // 清空请求代理
	
	// 通信端口
	local uvm_blocking_get_port #(AXISTrans #(.data_width(32), .user_width(IBUS_TID_WIDTH))) m_axis_trans_port;
	local uvm_blocking_get_port #(ICBTrans #(.addr_width(32), .data_width(32))) s_icb_trans_port;
	local uvm_blocking_get_port #(AXISTrans #(.data_width(64), .user_width(2+IBUS_TID_WIDTH))) s_axis_trans_port;
	local uvm_blocking_get_port #(ReqAckTrans #(.req_payload_width(32), .resp_payload_width(32))) req_trans_port;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(32), .user_width(IBUS_TID_WIDTH))) m_axis_agt_fifo;
	local uvm_tlm_analysis_fifo #(ICBTrans #(.addr_width(32), .data_width(32))) s_icb_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(64), .user_width(2+IBUS_TID_WIDTH))) s_axis_agt_fifo;
	local uvm_tlm_analysis_fifo #(ReqAckTrans #(.req_payload_width(32), .resp_payload_width(32))) req_agt_fifo;
	
	// 事务
	local AXISTrans #(.data_width(32), .user_width(IBUS_TID_WIDTH)) m_axis_trans;
	local ICBTrans #(.addr_width(32), .data_width(32)) s_icb_trans;
	local AXISTrans #(.data_width(64), .user_width(2+IBUS_TID_WIDTH)) s_axis_trans;
	local ReqAckTrans #(.req_payload_width(32), .resp_payload_width(32)) req_trans;
	
	// 文件句柄
	local integer fid_req;
	local integer fid_icb;
	local integer fid_ack;
	
	// 注册component
	`uvm_component_param_utils(IBusCtrlerEnv #(.IBUS_TID_WIDTH(IBUS_TID_WIDTH), .SIM_DELAY(SIM_DELAY)))
	
	function new(string name = "IBusCtrlerEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.m_axis_agt = AXISMasterAgent #(.out_drive_t(SIM_DELAY), .data_width(32), .user_width(IBUS_TID_WIDTH))::
			type_id::create("agt1", this);
		this.m_axis_agt.is_active = UVM_ACTIVE;
		this.s_icb_agt = ICBSlaveAgent #(.out_drive_t(SIM_DELAY), .addr_width(32), .data_width(32))::
			type_id::create("agt2", this);
		this.s_icb_agt.is_active = UVM_ACTIVE;
		this.s_axis_agt = AXISSlaveAgent #(.out_drive_t(SIM_DELAY), .data_width(64), .user_width(2+IBUS_TID_WIDTH))::
			type_id::create("agt3", this);
		this.s_axis_agt.is_active = UVM_ACTIVE;
		this.req_agt = ReqAckMasterAgent #(.out_drive_t(SIM_DELAY), .req_payload_width(32), .resp_payload_width(32))::
			type_id::create("agt4", this);
		this.req_agt.is_active = UVM_ACTIVE;
		
		// 创建通信端口
		this.m_axis_trans_port = new("m_axis_trans_port", this);
		this.s_icb_trans_port = new("s_icb_trans_port", this);
		this.s_axis_trans_port = new("s_axis_trans_port", this);
		this.req_trans_port = new("req_trans_port", this);
		
		// 创建通信fifo
		this.m_axis_agt_fifo = new("m_axis_agt_fifo", this);
		this.s_icb_agt_fifo = new("s_icb_agt_fifo", this);
		this.s_axis_agt_fifo = new("s_axis_agt_fifo", this);
		this.req_agt_fifo = new("req_agt_fifo", this);
		
		// 打开文件
		this.fid_req = $fopen("req_axis.txt", "w");
		this.fid_icb = $fopen("icb.txt", "w");
		this.fid_ack = $fopen("ack.txt", "w");
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.m_axis_agt.axis_analysis_port.connect(this.m_axis_agt_fifo.analysis_export);
		this.m_axis_trans_port.connect(this.m_axis_agt_fifo.blocking_get_export);
		this.s_icb_agt.icb_analysis_port.connect(this.s_icb_agt_fifo.analysis_export);
		this.s_icb_trans_port.connect(this.s_icb_agt_fifo.blocking_get_export);
		this.s_axis_agt.axis_analysis_port.connect(this.s_axis_agt_fifo.analysis_export);
		this.s_axis_trans_port.connect(this.s_axis_agt_fifo.blocking_get_export);
		this.req_agt.req_ack_analysis_port.connect(this.req_agt_fifo.analysis_export);
		this.req_trans_port.connect(this.req_agt_fifo.blocking_get_export);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				this.m_axis_trans_port.get(this.m_axis_trans);
				// this.m_axis_trans.print(); // 打印事务
				this.print_req_trans_to_txt(this.m_axis_trans);
			end
			
			forever
			begin
				this.s_icb_trans_port.get(this.s_icb_trans);
				// this.s_icb_trans.print(); // 打印事务
				this.print_icb_trans_to_txt(this.s_icb_trans);
			end
			
			forever
			begin
				this.s_axis_trans_port.get(this.s_axis_trans);
				// this.s_axis_trans.print(); // 打印事务
				this.print_ack_trans_to_txt(this.s_axis_trans);
			end
			
			forever
			begin
				this.req_trans_port.get(this.req_trans);
				// this.req_trans.print(); // 打印事务
			end
		join_none
	endtask
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		$fclose(this.fid_req);
		$fclose(this.fid_icb);
		$fclose(this.fid_ack);
	endfunction
	
	local task print_req_trans_to_txt(ref AXISTrans #(.data_width(32), .user_width(IBUS_TID_WIDTH)) trans);
		$fdisplay(this.fid_req, "addr = %d", trans.data[0]);
		$fdisplay(this.fid_req, "tid = %d", trans.user[0]);
		
		if(trans.data[0] & 32'h0000_0003)
			$fdisplay(this.fid_req, "unaligned");
		
		$fdisplay(this.fid_req, "------------------------------");
	endtask
	
	local task print_icb_trans_to_txt(ref ICBTrans #(.addr_width(32), .data_width(32)) trans);
		$fdisplay(this.fid_icb, "addr = %d", trans.cmd_addr);
		$fdisplay(this.fid_icb, "rdata = %d", trans.rsp_rdata);
		$fdisplay(this.fid_icb, "err = %b", trans.rsp_err);
		$fdisplay(this.fid_icb, "------------------------------");
	endtask
	
	local task print_ack_trans_to_txt(ref AXISTrans #(.data_width(64), .user_width(2+IBUS_TID_WIDTH)) trans);
		$fdisplay(this.fid_ack, "addr = %d", trans.data[0][63:32]);
		$fdisplay(this.fid_ack, "rdata = %d", trans.data[0][31:0]);
		$fdisplay(this.fid_ack, "tid = %d", trans.user[0][IBUS_TID_WIDTH-1:0]);
		
		if(trans.user[0][IBUS_TID_WIDTH+1:IBUS_TID_WIDTH] == 2'b00)
			$fdisplay(this.fid_ack, "err = normal");
		else if(trans.user[0][IBUS_TID_WIDTH+1:IBUS_TID_WIDTH] == 2'b01)
			$fdisplay(this.fid_ack, "err = pc_unaligned");
		else if(trans.user[0][IBUS_TID_WIDTH+1:IBUS_TID_WIDTH] == 2'b10)
			$fdisplay(this.fid_ack, "err = bus_err");
		else
			$fdisplay(this.fid_ack, "err = bus_timeout");
		
		$fdisplay(this.fid_ack, "------------------------------");
	endtask
	
endclass
	
`endif
