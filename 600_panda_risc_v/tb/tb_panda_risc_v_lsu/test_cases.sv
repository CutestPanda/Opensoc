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
`include "vsqr.sv"

class LsuCase0VSqr extends uvm_sequence;

	local AXISTrans #(.data_width(64), .user_width(9)) m_req_axis_trans; // 访存请求AXIS主机事务
	local AXISTrans #(.data_width(64), .user_width(16)) s_resp_axis_trans; // 访存响应AXIS从机事务
	local ICBTrans #(.addr_width(32), .data_width(32)) s_icb_trans; // ICB从机事务
	
	local int unsigned test_n; // 测试访存次数
	local int unsigned fns_m_req_axis_trans_n; // 完成的访存请求AXIS主机事务的个数
	local int unsigned fns_s_resp_axis_trans_n; // 完成的访存响应AXIS从机事务的个数
	local int unsigned fns_s_icb_trans_trans_n; // 完成的ICB从机事务的个数
	local int unsigned s_icb_trans_n; // 可启动的ICB从机事务的个数
	
	// 注册object
	`uvm_object_utils(LsuCase0VSqr)
	
	// 声明p_sequencer
	`uvm_declare_p_sequencer(LsuVsqr)
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		this.test_n = 100;
		this.fns_m_req_axis_trans_n = 0;
		this.fns_s_resp_axis_trans_n = 0;
		this.fns_s_icb_trans_trans_n = 0;
		this.s_icb_trans_n = 0;
		
		fork
			repeat(this.test_n)
				this.drive_m_req_axis();
			
			repeat(this.test_n)
				this.drive_s_resp_axis();
			
			forever
			begin
				this.drive_s_icb();
				
				if(this.fns_s_resp_axis_trans_n >= this.test_n)
					break;
			end
		join
		
		`uvm_info("LsuCase0VSqr", $sformatf("fns_m_req_axis_trans_n = %d", this.fns_m_req_axis_trans_n), UVM_LOW)
		`uvm_info("LsuCase0VSqr", $sformatf("fns_s_resp_axis_trans_n = %d", this.fns_s_resp_axis_trans_n), UVM_LOW)
		`uvm_info("LsuCase0VSqr", $sformatf("fns_s_icb_trans_trans_n = %d", this.fns_s_icb_trans_trans_n), UVM_LOW)
		
		// 继续运行10us
		# (10 ** 4);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
	local task drive_m_req_axis();
		automatic bit unalign_trans = $urandom_range(0, 5) == 5;
		
		if(!unalign_trans)
			this.s_icb_trans_n++;
		
		`uvm_do_on_with(this.m_req_axis_trans, p_sequencer.m_axis_req_ls_sqr, {
			data_n == 1;
			
			data.size() == 1;
			user.size() == 1;
			last.size() == 1;
			wait_period_n.size() == 1;
			
			if(user[0][0]) // 存储
				(user[0][3:1] == 3'b000) || (user[0][3:1] == 3'b001) || (user[0][3:1] == 3'b010);
			else // 加载
				(user[0][3:1] == 3'b000) || (user[0][3:1] == 3'b001) || (user[0][3:1] == 3'b010) || 
				(user[0][3:1] == 3'b100) || (user[0][3:1] == 3'b101);
			
			data[0][63:32] < 10;
			data[0][31:2] < 1024;
			
			if(unalign_trans)
				!((user[0][3:1] == 3'b000) || (user[0][3:1] == 3'b100) || 
				(((user[0][3:1] == 3'b001) || (user[0][3:1] == 3'b101)) && (data[0][0] == 1'b0)) || 
				((user[0][3:1] == 3'b010) && (data[0][1:0] == 2'b00)));
			else
				(user[0][3:1] == 3'b000) || (user[0][3:1] == 3'b100) || 
				(((user[0][3:1] == 3'b001) || (user[0][3:1] == 3'b101)) && (data[0][0] == 1'b0)) || 
				((user[0][3:1] == 3'b010) && (data[0][1:0] == 2'b00));
			
			last[0] == 1'b1;
			wait_period_n[0] dist {0:/3, 1:/2, [2:4]:/1};
		})
		
		this.fns_m_req_axis_trans_n++;
	endtask
	
	local task drive_s_resp_axis();
		`uvm_do_on_with(this.s_resp_axis_trans, p_sequencer.s_axis_resp_ls_sqr, {
			wait_period_n.size() == 1;
			
			wait_period_n[0] dist {0:/1, 1:/3, [2:4]:/1};
		})
		
		this.fns_s_resp_axis_trans_n++;
	endtask
	
	local task drive_s_icb();
		wait((this.s_icb_trans_n > 0) || (this.fns_s_resp_axis_trans_n >= this.test_n));
		
		if(this.fns_s_resp_axis_trans_n < this.test_n)
		begin
			this.s_icb_trans_n--;
			
			`uvm_do_on_with(this.s_icb_trans, p_sequencer.s_data_icb_sqr, {
				cmd_wait_period_n <= 2;
				
				rsp_rdata[7:0] < 10;
				rsp_rdata[15:8] < 10;
				rsp_rdata[23:16] < 10;
				rsp_rdata[31:24] < 10;
				
				rsp_err dist {0:/3, 1:/1};
				rsp_wait_period_n <= 4;
			})
			
			this.fns_s_icb_trans_trans_n++;
		end
	endtask
	
endclass

class LsuBaseTest #(
	real simulation_delay = 1 // 仿真延时
)extends uvm_test;
	
	// LSU测试环境
	local LsuEnv #(.simulation_delay(simulation_delay)) env;
	
	// 虚拟Sequencer
	protected LsuVsqr vsqr;
	
	// 注册component
	`uvm_component_param_utils(LsuBaseTest #(.simulation_delay(simulation_delay)))
	
	function new(string name = "LsuBaseTest", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = LsuEnv #(.simulation_delay(simulation_delay))::type_id::create("env", this); // 创建env
		
		this.vsqr = LsuVsqr::type_id::create("v_sqr", this); // 创建虚拟Sequencer
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.vsqr.m_axis_req_ls_sqr = this.env.m_axis_req_ls_agt.sequencer;
		this.vsqr.s_axis_resp_ls_sqr = this.env.s_axis_resp_ls_agt.sequencer;
		this.vsqr.s_data_icb_sqr = this.env.s_data_icb_agt.sequencer;
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		env.close_file();
	endfunction
	
endclass

class LsuCase0Test extends LsuBaseTest #(.simulation_delay(1));
	
	// 注册component
	`uvm_component_utils(LsuCase0Test)
	
	function new(string name = "LsuCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"v_sqr.main_phase", 
			"default_sequence", 
			LsuCase0VSqr::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("LsuCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
