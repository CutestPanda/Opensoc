`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"
`include "vsqr.sv"

class LsuCase0MAxisReqLsSeq extends uvm_sequence #(AXISTrans #(.data_width(64), .user_width(9)));
	
	local AXISTrans #(.data_width(64), .user_width(9)) m_axis_trans; // AXIS主机事务
	
	// 注册object
	`uvm_object_utils(LsuCase0MAxisReqLsSeq)
	
	function new(string name = "LsuCase0MAxisReqLsSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		`uvm_do_with(this.m_axis_trans, {
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
			data[0][1:0] dist {0:/3, [1:3]:/1};
			
			last[0] == 1'b1;
			wait_period_n[0] dist {0:/3, 1:/2, [2:4]:/1};
		})
	endtask
	
endclass

class LsuCase0SAxisRespLsSeq extends uvm_sequence #(AXISTrans #(.data_width(64), .user_width(8)));
	
	local AXISTrans #(.data_width(64), .user_width(8)) s_axis_trans; // AXIS从机事务
	
	// 注册object
	`uvm_object_utils(LsuCase0SAxisRespLsSeq)
	
	function new(string name = "LsuCase0SAxisRespLsSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		`uvm_do_with(this.s_axis_trans, {
			wait_period_n.size() == 1;
			
			wait_period_n[0] dist {0:/1, 1:/3, [2:4]:/1};
		})
	endtask
	
endclass

class LsuCase0SDataIcbSeq extends uvm_sequence #(ICBTrans #(.addr_width(32), .data_width(32)));
	
	local ICBTrans #(.addr_width(32), .data_width(32)) s_icb_trans; // ICB从机事务
	
	// 注册object
	`uvm_object_utils(LsuCase0SDataIcbSeq)
	
	function new(string name = "LsuCase0SDataIcbSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		`uvm_do_with(this.s_icb_trans, {
			cmd_wait_period_n <= 2;
			
			rsp_rdata[7:0] < 10;
			rsp_rdata[15:8] < 10;
			rsp_rdata[23:16] < 10;
			rsp_rdata[31:24] < 10;
			
			rsp_err dist {0:/3, 1:/1};
			rsp_wait_period_n <= 4;
		})
	endtask
	
endclass

class LsuCase0VSqr extends uvm_sequence;
	
	// 注册object
	`uvm_object_utils(LsuCase0VSqr)
	
	// 声明p_sequencer
	`uvm_declare_p_sequencer(LsuVsqr)
	
	virtual task body();
		LsuCase0MAxisReqLsSeq req_seq;
		LsuCase0SAxisRespLsSeq resp_seq;
		LsuCase0SDataIcbSeq icb_seq;
		
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		fork
			repeat(100)
				`uvm_do_on(req_seq, p_sequencer.m_axis_req_ls_sqr)
			
			repeat(100)
				`uvm_do_on(resp_seq, p_sequencer.s_axis_resp_ls_sqr)
			
			repeat(100)
				`uvm_do_on(icb_seq, p_sequencer.s_data_icb_sqr)
		join
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
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
