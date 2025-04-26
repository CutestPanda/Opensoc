`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class EthMacTxMAxisCase0Sqc extends uvm_sequence;
	
	local AXISTrans #(.data_width(16), .user_width(0)) m_axis_trans; // AXIS主机事务
	
	// 注册object
	`uvm_object_utils(EthMacTxMAxisCase0Sqc)
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		// 42字节
		`uvm_do_with(this.m_axis_trans, {
			data_n == 21;
			
			data.size() == data_n;
			keep.size() == data_n;
			last.size() == data_n;
			wait_period_n.size() == data_n;
			
			data[0] == 16'hff_ff;
			data[1] == 16'hff_ff;
			data[2] == 16'hff_ff;
			data[3] == 16'h11_00;
			data[4] == 16'h33_22;
			data[5] == 16'h55_44;
			data[6] == 16'h06_08;
			data[7] == 16'h01_00;
			data[8] == 16'h00_08;
			data[9] == 16'h04_06;
			data[10] == 16'h01_00;
			data[11] == 16'h11_00;
			data[12] == 16'h33_22;
			data[13] == 16'h55_44;
			data[14] == 16'ha8_c0;
			data[15] == 16'h66_01;
			data[16] == 16'hff_ff;
			data[17] == 16'hff_ff;
			data[18] == 16'hff_ff;
			data[19] == 16'ha8_c0;
			data[20] == 16'h66_01;
			
			foreach(keep[i]){
				keep[i] == 2'b11;
			}
			
			foreach(last[i]){
				last[i] == (i == (data_n-1));
			}
			
			foreach(wait_period_n[i]){
				wait_period_n[i] == 0;
			}
		})
		
		// 42字节
		`uvm_do_with(this.m_axis_trans, {
			data_n == 21;
			
			data.size() == data_n;
			keep.size() == data_n;
			last.size() == data_n;
			wait_period_n.size() == data_n;
			
			data[0] == 16'h11_00;
			data[1] == 16'h33_22;
			data[2] == 16'h55_44;
			data[3] == 16'h11_00;
			data[4] == 16'h33_22;
			data[5] == 16'h55_44;
			data[6] == 16'h06_08;
			data[7] == 16'h01_00;
			data[8] == 16'h00_08;
			data[9] == 16'h04_06;
			data[10] == 16'h02_00;
			data[11] == 16'h11_00;
			data[12] == 16'h33_22;
			data[13] == 16'h55_44;
			data[14] == 16'ha8_c0;
			data[15] == 16'h66_01;
			data[16] == 16'h11_00;
			data[17] == 16'h33_22;
			data[18] == 16'h55_44;
			data[19] == 16'ha8_c0;
			data[20] == 16'h66_01;
			
			foreach(keep[i]){
				keep[i] == 2'b11;
			}
			
			foreach(last[i]){
				last[i] == (i == (data_n-1));
			}
			
			foreach(wait_period_n[i]){
				wait_period_n[i] == 0;
			}
		})
		
		// 15字节
		`uvm_do_with(this.m_axis_trans, {
			data_n == 8;
			
			data.size() == data_n;
			keep.size() == data_n;
			last.size() == data_n;
			wait_period_n.size() == data_n;
			
			foreach(data[i]){
				data[i][7:0] == i * 2;
				data[i][15:8] == i * 2 + 1;
			}
			
			foreach(keep[i]){
				if(i == (data_n-1))
					keep[i] == 2'b01;
				else
					keep[i] == 2'b11;
			}
			
			foreach(last[i]){
				last[i] == (i == (data_n-1));
			}
			
			foreach(wait_period_n[i]){
				wait_period_n[i] == 0;
			}
		})
		
		// 16字节
		`uvm_do_with(this.m_axis_trans, {
			data_n == 8;
			
			data.size() == data_n;
			keep.size() == data_n;
			last.size() == data_n;
			wait_period_n.size() == data_n;
			
			foreach(data[i]){
				data[i][7:0] == i * 2;
				data[i][15:8] == i * 2 + 1;
			}
			
			foreach(keep[i]){
				keep[i] == 2'b11;
			}
			
			foreach(last[i]){
				last[i] == (i == (data_n-1));
			}
			
			foreach(wait_period_n[i]){
				wait_period_n[i] <= 1;
			}
		})
		
		// 17字节
		`uvm_do_with(this.m_axis_trans, {
			data_n == 9;
			
			data.size() == data_n;
			keep.size() == data_n;
			last.size() == data_n;
			wait_period_n.size() == data_n;
			
			foreach(data[i]){
				data[i][7:0] == i * 2;
				data[i][15:8] == i * 2 + 1;
			}
			
			foreach(keep[i]){
				if(i == (data_n-1))
					keep[i] == 2'b01;
				else
					keep[i] == 2'b11;
			}
			
			foreach(last[i]){
				last[i] == (i == (data_n-1));
			}
			
			foreach(wait_period_n[i]){
				wait_period_n[i] <= 1;
			}
		})
		
		// 18字节
		`uvm_do_with(this.m_axis_trans, {
			data_n == 9;
			
			data.size() == data_n;
			keep.size() == data_n;
			last.size() == data_n;
			wait_period_n.size() == data_n;
			
			foreach(data[i]){
				data[i][7:0] == i * 2;
				data[i][15:8] == i * 2 + 1;
			}
			
			foreach(keep[i]){
				keep[i] == 2'b11;
			}
			
			foreach(last[i]){
				last[i] == (i == (data_n-1));
			}
			
			foreach(wait_period_n[i]){
				wait_period_n[i] <= 1;
			}
		})
		
		// 19字节
		`uvm_do_with(this.m_axis_trans, {
			data_n == 10;
			
			data.size() == data_n;
			keep.size() == data_n;
			last.size() == data_n;
			wait_period_n.size() == data_n;
			
			foreach(data[i]){
				data[i][7:0] == i * 2;
				data[i][15:8] == i * 2 + 1;
			}
			
			foreach(keep[i]){
				if(i == (data_n-1))
					keep[i] == 2'b01;
				else
					keep[i] == 2'b11;
			}
			
			foreach(last[i]){
				last[i] == (i == (data_n-1));
			}
			
			foreach(wait_period_n[i]){
				wait_period_n[i] <= 1;
			}
		})
		
		// 20字节
		`uvm_do_with(this.m_axis_trans, {
			data_n == 10;
			
			data.size() == data_n;
			keep.size() == data_n;
			last.size() == data_n;
			wait_period_n.size() == data_n;
			
			foreach(data[i]){
				data[i][7:0] == i * 2;
				data[i][15:8] == i * 2 + 1;
			}
			
			foreach(keep[i]){
				keep[i] == 2'b11;
			}
			
			foreach(last[i]){
				last[i] == (i == (data_n-1));
			}
			
			foreach(wait_period_n[i]){
				wait_period_n[i] <= 1;
			}
		})
		
		// 继续运行100us
		# (100 * (10 ** 3));
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class EthMacTxBaseTest #(
	real simulation_delay = 1 // 仿真延时
)extends uvm_test;
	
	// 以太网发送测试环境
	local EthMacTxEnv #(.simulation_delay(simulation_delay)) env;
	
	// 注册component
	`uvm_component_param_utils(EthMacTxBaseTest #(.simulation_delay(simulation_delay)))
	
	function new(string name = "EthMacTxBaseTest", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = EthMacTxEnv #(.simulation_delay(simulation_delay))::type_id::create("env", this); // 创建env
	endfunction
	
endclass

class EthMacTxCase0Test extends EthMacTxBaseTest #(.simulation_delay(1));
	
	// 注册component
	`uvm_component_utils(EthMacTxCase0Test)
	
	function new(string name = "EthMacTxCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			EthMacTxMAxisCase0Sqc::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("EthMacTxCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
