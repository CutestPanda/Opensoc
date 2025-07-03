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

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class IBusCtrlerCase0MAXISSeq #(
	integer IBUS_TID_WIDTH = 8 // 指令总线事务ID位宽(1~16)
)extends uvm_sequence #(AXISTrans #(.data_width(32), .user_width(IBUS_TID_WIDTH)));
	
	local AXISTrans #(.data_width(32), .user_width(IBUS_TID_WIDTH)) m_axis_trans; // AXIS主机事务
	
	// 注册object
	`uvm_object_param_utils(IBusCtrlerCase0MAXISSeq #(.IBUS_TID_WIDTH(IBUS_TID_WIDTH)))
	
	function new(string name = "IBusCtrlerCase0MAXISSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		// 地址 = 3, ID = 0, 等待周期数 = 0
		`uvm_do_with(this.m_axis_trans, {
			data_n == 1;
			
			data.size() == 1;
			user.size() == 1;
			last.size() == 1;
			wait_period_n.size() == 1;
			
			data[0] == 32'd3;
			user[0] == 8'd0;
			last[0] == 1'b1;
			wait_period_n[0] == 0;
		})
		
		// 地址 = 8, ID = 1, 等待周期数 = 0
		`uvm_do_with(this.m_axis_trans, {
			data_n == 1;
			
			data.size() == 1;
			user.size() == 1;
			last.size() == 1;
			wait_period_n.size() == 1;
			
			data[0] == 32'd8;
			user[0] == 8'd1;
			last[0] == 1'b1;
			wait_period_n[0] == 0;
		})
		
		// 地址 = 16, ID = 2, 等待周期数 = 1
		`uvm_do_with(this.m_axis_trans, {
			data_n == 1;
			
			data.size() == 1;
			user.size() == 1;
			last.size() == 1;
			wait_period_n.size() == 1;
			
			data[0] == 32'd16;
			user[0] == 8'd2;
			last[0] == 1'b1;
			wait_period_n[0] == 1;
		})
		
		// 地址 = 7, ID = 3, 等待周期数 = 0
		`uvm_do_with(this.m_axis_trans, {
			data_n == 1;
			
			data.size() == 1;
			user.size() == 1;
			last.size() == 1;
			wait_period_n.size() == 1;
			
			data[0] == 32'd7;
			user[0] == 8'd3;
			last[0] == 1'b1;
			wait_period_n[0] == 0;
		})
		
		// 地址 = 20, ID = 4, 等待周期数 = 0
		`uvm_do_with(this.m_axis_trans, {
			data_n == 1;
			
			data.size() == 1;
			user.size() == 1;
			last.size() == 1;
			wait_period_n.size() == 1;
			
			data[0] == 32'd20;
			user[0] == 8'd4;
			last[0] == 1'b1;
			wait_period_n[0] == 0;
		})
		
		// 地址 = 7, ID = 5, 等待周期数 = 0
		`uvm_do_with(this.m_axis_trans, {
			data_n == 1;
			
			data.size() == 1;
			user.size() == 1;
			last.size() == 1;
			wait_period_n.size() == 1;
			
			data[0] == 32'd7;
			user[0] == 8'd5;
			last[0] == 1'b1;
			wait_period_n[0] == 0;
		})
		
		// 地址 = 24, ID = 6, 等待周期数 = 0
		`uvm_do_with(this.m_axis_trans, {
			data_n == 1;
			
			data.size() == 1;
			user.size() == 1;
			last.size() == 1;
			wait_period_n.size() == 1;
			
			data[0] == 32'd24;
			user[0] == 8'd6;
			last[0] == 1'b1;
			wait_period_n[0] == 0;
		})
		
		// 地址 = 32, ID = 7, 等待周期数 = 2
		`uvm_do_with(this.m_axis_trans, {
			data_n == 1;
			
			data.size() == 1;
			user.size() == 1;
			last.size() == 1;
			wait_period_n.size() == 1;
			
			data[0] == 32'd32;
			user[0] == 8'd7;
			last[0] == 1'b1;
			wait_period_n[0] == 2;
		})
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class IBusCtrlerCase1MAXISSeq #(
	integer IBUS_TID_WIDTH = 8 // 指令总线事务ID位宽(1~16)
)extends uvm_sequence #(AXISTrans #(.data_width(32), .user_width(IBUS_TID_WIDTH)));
	
	localparam integer TEST_N = 50;
	
	local AXISTrans #(.data_width(32), .user_width(IBUS_TID_WIDTH)) m_axis_trans; // AXIS主机事务
	
	// 注册object
	`uvm_object_param_utils(IBusCtrlerCase1MAXISSeq #(.IBUS_TID_WIDTH(IBUS_TID_WIDTH)))
	
	function new(string name = "IBusCtrlerCase1MAXISSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		for(int i = 0;i < TEST_N;i++)
		begin
			`uvm_do_with(this.m_axis_trans, {
				data_n == 1;
				
				data.size() == 1;
				user.size() == 1;
				last.size() == 1;
				wait_period_n.size() == 1;
				
				data[0][31:2] == i;
				data[0][1:0] dist{0:/5, [1:3]:/1};
				
				user[0] == i & 8'hff;
				last[0] == 1'b1;
				wait_period_n[0] <= 2;
			})
		end
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class IBusCtrlerCase0SICBSeq extends uvm_sequence #(ICBTrans #(.addr_width(32), .data_width(32)));
	
	local ICBTrans #(.addr_width(32), .data_width(32)) s_icb_trans; // icb从机事务
	
	// 注册object
	`uvm_object_utils(IBusCtrlerCase0SICBSeq)
	
	function new(string name = "IBusCtrlerCase0SICBSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		// 命令通道等待周期数 = 1, 读数据 = 1, 错误 = 1'b0, 响应通道等待周期数 = 1
		`uvm_do_with(this.s_icb_trans, {
			cmd_wait_period_n == 1;
			
			rsp_rdata == 1;
			rsp_err == 1'b0;
			rsp_wait_period_n == 1;
		})
		
		// 命令通道等待周期数 = 2, 读数据 = 2, 错误 = 1'b1, 响应通道等待周期数 = 2
		`uvm_do_with(this.s_icb_trans, {
			cmd_wait_period_n == 2;
			
			rsp_rdata == 2;
			rsp_err == 1'b1;
			rsp_wait_period_n == 2;
		})
		
		// 命令通道等待周期数 = 5, 读数据 = 3, 错误 = 1'b0, 响应通道等待周期数 = 10
		`uvm_do_with(this.s_icb_trans, {
			cmd_wait_period_n == 5;
			
			rsp_rdata == 3;
			rsp_err == 1'b0;
			rsp_wait_period_n == 10;
		})
		
		// 命令通道等待周期数 = 5, 读数据 = 4, 错误 = 1'b0, 响应通道等待周期数 = 7
		`uvm_do_with(this.s_icb_trans, {
			cmd_wait_period_n == 5;
			
			rsp_rdata == 4;
			rsp_err == 1'b0;
			rsp_wait_period_n == 7;
		})
		
		// 命令通道等待周期数 = 3, 读数据 = 5, 错误 = 1'b0, 响应通道等待周期数 = 20
		`uvm_do_with(this.s_icb_trans, {
			cmd_wait_period_n == 3;
			
			rsp_rdata == 5;
			rsp_err == 1'b0;
			rsp_wait_period_n == 20;
		})
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class IBusCtrlerCase1SICBSeq extends uvm_sequence #(ICBTrans #(.addr_width(32), .data_width(32)));
	
	localparam integer TEST_N = 50;
	
	local ICBTrans #(.addr_width(32), .data_width(32)) s_icb_trans; // icb从机事务
	
	// 注册object
	`uvm_object_utils(IBusCtrlerCase1SICBSeq)
	
	function new(string name = "IBusCtrlerCase1SICBSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		for(int i = 0;i < TEST_N;i++)
		begin
			`uvm_do_with(this.s_icb_trans, {
				cmd_wait_period_n dist{[0:1]:/2, [2:6]:/1};
				
				rsp_rdata == i;
				rsp_err dist{0:=4, 1:=1};
				
				if(cmd_wait_period_n >= 1)
					rsp_wait_period_n >= cmd_wait_period_n - 1;
				rsp_wait_period_n <= cmd_wait_period_n + 6;
			})
		end
	endtask
	
endclass

class IBusCtrlerCase0ClrReqSeq extends uvm_sequence #(ReqAckTrans #(.req_payload_width(32), .resp_payload_width(32)));
	
	local ReqAckTrans #(.req_payload_width(32), .resp_payload_width(32)) clr_req_trans; // 清空指令缓存事务
	
	// 注册object
	`uvm_object_utils(IBusCtrlerCase0ClrReqSeq)
	
	function new(string name = "IBusCtrlerCase0ClrReqSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		`uvm_do_with(this.clr_req_trans, {
			req_wait_period_n == 67;
		})
		
		`uvm_do_with(this.clr_req_trans, {
			req_wait_period_n == 4;
		})
		
		`uvm_do_with(this.clr_req_trans, {
			req_wait_period_n == 17;
		})
		
		`uvm_do_with(this.clr_req_trans, {
			req_wait_period_n == 32;
		})
	endtask
	
endclass

class IBusCtrlerBaseTest #(
	integer IBUS_TID_WIDTH = 8, // 指令总线事务ID位宽(1~16)
	real SIM_DELAY = 1.0 // 仿真延时
)extends uvm_test;
	
	// 指令总线控制单元测试环境
	local IBusCtrlerEnv #(.IBUS_TID_WIDTH(IBUS_TID_WIDTH), .SIM_DELAY(SIM_DELAY)) env;
	
	// 注册component
	`uvm_component_param_utils(IBusCtrlerBaseTest #(.IBUS_TID_WIDTH(IBUS_TID_WIDTH), .SIM_DELAY(SIM_DELAY)))
	
	function new(string name = "IBusCtrlerBaseTest", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		phase.phase_done.set_drain_time(this, 10 ** 7);
	endtask
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建env
		this.env = IBusCtrlerEnv #(.IBUS_TID_WIDTH(IBUS_TID_WIDTH), .SIM_DELAY(SIM_DELAY))::type_id::create("env", this);
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("IBusCtrlerBaseTest", "test finished!", UVM_LOW)
	endfunction
	
endclass

class IBusCtrlerCase0Test extends IBusCtrlerBaseTest #(.IBUS_TID_WIDTH(8), .SIM_DELAY(1.0));
	
	localparam integer IBUS_TID_WIDTH = 8; // 指令总线事务ID位宽(1~16)
	
	// 注册component
	`uvm_component_utils(IBusCtrlerCase0Test)
	
	function new(string name = "IBusCtrlerCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			IBusCtrlerCase0MAXISSeq #(.IBUS_TID_WIDTH(IBUS_TID_WIDTH))::type_id::get());
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt2.sqr.main_phase", 
			"default_sequence", 
			IBusCtrlerCase0SICBSeq::type_id::get());
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt4.sqr.main_phase", 
			"default_sequence", 
			IBusCtrlerCase0ClrReqSeq::type_id::get());
	endfunction
	
endclass

class IBusCtrlerCase1Test extends IBusCtrlerBaseTest #(.IBUS_TID_WIDTH(8), .SIM_DELAY(1.0));
	
	localparam integer IBUS_TID_WIDTH = 8; // 指令总线事务ID位宽(1~16)
	
	// 注册component
	`uvm_component_utils(IBusCtrlerCase1Test)
	
	function new(string name = "IBusCtrlerCase1Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			IBusCtrlerCase1MAXISSeq #(.IBUS_TID_WIDTH(IBUS_TID_WIDTH))::type_id::get());
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt2.sqr.main_phase", 
			"default_sequence", 
			IBusCtrlerCase1SICBSeq::type_id::get());
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt4.sqr.main_phase", 
			"default_sequence", 
			IBusCtrlerCase0ClrReqSeq::type_id::get());
	endfunction
	
endclass

`endif
