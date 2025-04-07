`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class AxiSdramCase0Sqc #(
	integer data_width = 32 // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
)extends uvm_sequence;
	
	local AXITrans #(.addr_width(32), 
		.data_width(data_width), .bresp_width(2), .rresp_width(2)) m_axi_trans; // AXI主机事务
	
	// 注册object
	`uvm_object_param_utils(AxiSdramCase0Sqc #(.data_width(data_width)))
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		`uvm_do_with(this.m_axi_trans, {
			is_rd_trans == 1'b0;
			data_n == 32;
			
			addr == 1000;
			burst == 2'b01;
			len == (data_n - 1);
			size == 3'b001;
			addr_wait_period_n <= 8;
			
			wdata.size() == data_n;
			wlast.size() == data_n;
			wstrb.size() == data_n;
			wdata_wait_period_n.size() == data_n;
			
			foreach(wdata[i]){
				wdata[i] == (1000 + i * 2);
			}
			foreach(wlast[i]){
				wlast[i] == (i == (data_n - 1));
			}
			foreach(wstrb[i]){
				wstrb[i] == 2'b11;
			}
			foreach(wdata_wait_period_n[i]){
				wdata_wait_period_n[i] <= 2;
			}
		})
		
		`uvm_do_with(this.m_axi_trans, {
			is_rd_trans == 1'b1;
			data_n == 32;
			
			addr == 1002;
			burst == 2'b01;
			len == (data_n - 1);
			size == 3'b001;
			addr_wait_period_n <= 8;
		})
		
		`uvm_do_with(this.m_axi_trans, {
			is_rd_trans == 1'b0;
			data_n == 64;
			
			addr == 1;
			burst == 2'b01;
			len == (data_n - 1);
			size == 3'b001;
			addr_wait_period_n <= 8;
			
			wdata.size() == data_n;
			wlast.size() == data_n;
			wstrb.size() == data_n;
			wdata_wait_period_n.size() == data_n;
			
			foreach(wdata[i]){
				wdata[i] == (0 + i * 2);
			}
			foreach(wlast[i]){
				wlast[i] == (i == (data_n - 1));
			}
			foreach(wstrb[i]){
				wstrb[i] == 2'b11;
			}
			foreach(wdata_wait_period_n[i]){
				wdata_wait_period_n[i] <= 2;
			}
		})
		
		`uvm_do_with(this.m_axi_trans, {
			is_rd_trans == 1'b1;
			data_n == 64;
			
			addr == 0;
			burst == 2'b01;
			len == (data_n - 1);
			size == 3'b001;
			addr_wait_period_n <= 8;
		})
		
		`uvm_do_with(this.m_axi_trans, {
			is_rd_trans == 1'b0;
			data_n == 24;
			
			addr == 2000;
			burst == 2'b01;
			len == (data_n - 1);
			size == 3'b001;
			addr_wait_period_n <= 8;
			
			wdata.size() == data_n;
			wlast.size() == data_n;
			wstrb.size() == data_n;
			wdata_wait_period_n.size() == data_n;
			
			foreach(wdata[i]){
				wdata[i] == (2000 + i * 2);
			}
			foreach(wlast[i]){
				wlast[i] == (i == (data_n - 1));
			}
			foreach(wstrb[i]){
				wstrb[i] == 2'b11;
			}
			foreach(wdata_wait_period_n[i]){
				wdata_wait_period_n[i] <= 2;
			}
		})
		
		`uvm_do_with(this.m_axi_trans, {
			is_rd_trans == 1'b1;
			data_n == 24;
			
			addr == 2000;
			burst == 2'b01;
			len == (data_n - 1);
			size == 3'b001;
			addr_wait_period_n <= 8;
		})
		
		// 继续运行300us
		# (300 * (10 ** 3));
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class AxiSdramBaseTest #(
	integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	real simulation_delay = 1 // 仿真延时
)extends uvm_test;
	
	// axi-sdram测试环境
	local AxiSdramEnv #(.data_width(data_width), .simulation_delay(simulation_delay)) env;
	
	// 注册component
	`uvm_component_param_utils(AxiSdramBaseTest #(.data_width(data_width), .simulation_delay(simulation_delay)))
	
	function new(string name = "AxiSdramBaseTest", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = AxiSdramEnv #(.data_width(data_width), .simulation_delay(simulation_delay))::type_id::create("env", this); // 创建env
	endfunction
	
endclass

class AxiSdramCase0Test extends AxiSdramBaseTest #(.data_width(16), .simulation_delay(1));
	
	// 注册component
	`uvm_component_utils(AxiSdramCase0Test)
	
	function new(string name = "AxiSdramCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			AxiSdramCase0Sqc #(.data_width(16))::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("AxiSdramCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
