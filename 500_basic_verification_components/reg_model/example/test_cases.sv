`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "../../transactions.sv"
`include "envs.sv"
`include "reg_blks.sv"
`include "../reg_adapters.sv"

class ApbTimerBaseTest extends uvm_test;
	
	// Apb-Timer测试环境
	local ApbTimerEnv env;
	
	// 寄存器模型与适配器
	local TimerRegBlk rm;
	local RegApbAdapter #(.addr_width(32), .data_width(32)) apb_adapter;
	
	// 注册component
	`uvm_component_utils(ApbTimerBaseTest)
	
	function new(string name = "ApbTimerBaseTest", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建env
		this.env = ApbTimerEnv::type_id::create("env", this);
		
		// 创建和初始化寄存器模型
		this.rm = TimerRegBlk::type_id::create("rm", this);
		this.rm.configure(null, "");
		this.rm.build();
		this.rm.lock_model();
		this.rm.reset();
		this.rm.set_hdl_path_root("tb_apb_timer.dut.regs_if_for_timer_u");
		
		// 创建寄存器模型的适配器
		this.apb_adapter = new("RegApbAdapter");
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		// 为寄存器模型绑定sequencer和适配器
		this.rm.default_map.set_sequencer(this.env.reg_agt.sequencer, this.apb_adapter);
		// 启用寄存器模型的自动预测功能
		this.rm.default_map.set_auto_predict(1);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		automatic uvm_status_e sts;
		automatic uvm_reg_data_t val;
		
		super.main_phase(phase);
		
		phase.phase_done.set_drain_time(this, 10 * (10 ** 6));
		
		// 读写寄存器测试
		phase.raise_objection(this);
		
		# (100 * 10);
		
		this.rm.reg_ctrl.read(sts, val, UVM_FRONTDOOR);
		
		`uvm_info("RegTest", $sformatf("version = %0d", (val >> 16) & 32'h0000_00ff), UVM_LOW)
		`uvm_info("RegTest", $sformatf("chn_n = %0d", (val >> 24) & 32'h0000_0007), UVM_LOW)
		
		# (10 * 10);
		
		this.rm.reg_psc.write(sts, 10 - 1, UVM_FRONTDOOR);
		
		# (10 * 10);
		
		this.rm.reg_atl.write(sts, 200 - 1, UVM_FRONTDOOR);
		
		# (10 * 10);
		
		this.rm.reg_chn0_v.write(sts, 100 - 1, UVM_BACKDOOR);
		this.rm.reg_atl.read(sts, val, UVM_BACKDOOR);
		
		`uvm_info("RegTest", $sformatf("auto_load_v = %0d", val), UVM_LOW)
		
		phase.drop_objection(this);
	endtask
	
endclass

`endif
