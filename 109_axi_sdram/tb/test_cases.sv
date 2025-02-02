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

class AXISdramSeq0 extends uvm_sequence #(AXITrans #(.addr_width(32), .data_width(32), 
	.bresp_width(2), .rresp_width(2)));
	
	local AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2)) axi_trans; // AXI事务
	
	local bit[31:0] now_rd_addr;
	local bit[31:0] now_wt_addr;
	local bit now_gen_rd_trans;
	
	// 注册object
	`uvm_object_utils(AXISdramSeq0)
	
	function new(string name = "AXISdramSeq0");
		super.new(name);
		
		this.now_rd_addr = 32'd0;
		this.now_wt_addr = 32'd0;
		this.now_gen_rd_trans = 1'b1;
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		while((this.now_rd_addr != 1922 * 1082) || (this.now_wt_addr != 1922 * 1082))
		begin
			automatic int unsigned burst_len;
			automatic bit[31:0] now_addr = this.now_gen_rd_trans ? this.now_rd_addr:this.now_wt_addr;
			
			if(this.now_gen_rd_trans)
				burst_len = ((1922 * 1082 - this.now_rd_addr) >= 128) ? 32:((1922 * 1082 - this.now_rd_addr) / 4);
			else
				burst_len = ((1922 * 1082 - this.now_wt_addr) >= 128) ? 32:((1922 * 1082 - this.now_wt_addr) / 4);
			
			if(this.now_gen_rd_trans)
			begin
				`uvm_do_with(this.axi_trans, {
					is_rd_trans == 1'b1;
					data_n == burst_len;
					
					addr == now_addr;
					burst == 2'b00;
					cache == 4'b0000;
					len == burst_len - 1;
					lock == 1'b0;
					prot == 3'b000;
					size == 3'b010;
					addr_wait_period_n <= 20;
					
					wdata.size() == 0;
					wlast.size() == 0;
					wstrb.size() == 0;
					wdata_wait_period_n.size() == 0;
					
					bresp == 2'b00;
					
					rdata.size() == 0;
					rlast.size() == 0;
					rresp.size() == 0;
					rdata_wait_period_n.size() == 0;
				})
			end
			else
			begin
				`uvm_do_with(this.axi_trans, {
					is_rd_trans == 1'b0;
					data_n == burst_len;
					
					addr == now_addr;
					burst == 2'b00;
					cache == 4'b0000;
					len == burst_len - 1;
					lock == 1'b0;
					prot == 3'b000;
					size == 3'b010;
					addr_wait_period_n <= 20;
					
					wdata.size() == burst_len;
					wlast.size() == burst_len;
					wstrb.size() == burst_len;
					wdata_wait_period_n.size() == burst_len;
					
					foreach(wlast[i])
						wlast[i] == (i == (burst_len - 1));
					
					bresp == 2'b00;
					
					rdata.size() == 0;
					rlast.size() == 0;
					rresp.size() == 0;
					rdata_wait_period_n.size() == 0;
				})
			end
			
			if(this.now_gen_rd_trans)
				this.now_rd_addr += burst_len * 4;
			else
				this.now_wt_addr += burst_len * 4;
			
			this.now_gen_rd_trans = !this.now_gen_rd_trans;
		end
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class AXISdramSeq1 extends uvm_sequence #(AXITrans #(.addr_width(32), .data_width(32), 
	.bresp_width(2), .rresp_width(2)));
	
	local AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2)) axi_trans; // AXI事务
	
	local bit[31:0] now_rd_addr;
	
	// 注册object
	`uvm_object_utils(AXISdramSeq1)
	
	function new(string name = "AXISdramSeq1");
		super.new(name);
		
		this.now_rd_addr = 32'h7F_0000;
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		for(int i = 0;i < 288;i++)
		begin
			automatic bit[31:0] now_addr = this.now_rd_addr;
			
			`uvm_do_with(this.axi_trans, {
				is_rd_trans == 1'b1;
				data_n == 32;
				
				addr == now_addr;
				burst == 2'b00;
				cache == 4'b0000;
				len == 8'd31;
				lock == 1'b0;
				prot == 3'b000;
				size == 3'b010;
				addr_wait_period_n <= 20;
				
				wdata.size() == 0;
				wlast.size() == 0;
				wstrb.size() == 0;
				wdata_wait_period_n.size() == 0;
				
				bresp == 2'b00;
				
				rdata.size() == 0;
				rlast.size() == 0;
				rresp.size() == 0;
				rdata_wait_period_n.size() == 0;
			})
			
			this.now_rd_addr += 128;
		end
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class AXISdramCase0Test extends uvm_test;
	
	local AXISdramEnv env; // axi-sdram测试环境
	
	// 注册component
	`uvm_component_utils(AXISdramCase0Test)
	
	function new(string name = "AXISdramCase0Test", uvm_component parent = null);
		super.new(name,parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = AXISdramEnv::type_id::create("env", this); // 创建env
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt.sqr.main_phase", 
			"default_sequence", 
			AXISdramSeq0::type_id::get());
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt2.sqr.main_phase", 
			"default_sequence", 
			AXISdramSeq0::type_id::get());
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt3.sqr.main_phase", 
			"default_sequence", 
			AXISdramSeq1::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("AXISdramCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
