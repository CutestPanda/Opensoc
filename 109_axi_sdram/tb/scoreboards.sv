`timescale 1ns / 1ps

`ifndef __SCOREBOARD_H

`define __SCOREBOARD_H

`include "transactions.sv"

/** 计分板:CLAHE算法 **/
class AXISdramEnvScoreboard extends uvm_scoreboard;
	
	// 通信端口
	uvm_blocking_get_port #(AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2))) rd_trans_port[0:2];
	uvm_blocking_get_port #(AXITrans #(.addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2))) wt_trans_port[0:2];
	
	// 事务
	local int unsigned rd_trans_id[0:2];
	local int unsigned wt_trans_id[0:2];
	
	// 注册component
	`uvm_component_utils(AXISdramEnvScoreboard)
	
	function new(string name = "AXISdramEnvScoreboard", uvm_component parent = null);
		super.new(name, parent);
		
		for(int i = 0;i < 3;i++)
		begin
			this.rd_trans_id[i] = 0;
			this.wt_trans_id[i] = 0;
		end
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.rd_trans_port[0] = new("scoreboard_rd_trans_port0", this);
		this.rd_trans_port[1] = new("scoreboard_rd_trans_port1", this);
		this.rd_trans_port[2] = new("scoreboard_rd_trans_port2", this);
		
		this.wt_trans_port[0] = new("scoreboard_wt_trans_port0", this);
		this.wt_trans_port[1] = new("scoreboard_wt_trans_port1", this);
		this.wt_trans_port[2] = new("scoreboard_wt_trans_port2", this);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				automatic AXITrans #(.addr_width(32), .data_width(32), 
					.bresp_width(2), .rresp_width(2)) axi_trans;
				
				this.rd_trans_port[0].get(axi_trans);
				
				`uvm_info("AXISdramEnvScoreboard", 
					$sformatf("AXISdramEnvScoreboard got axi0_rd_trans(id = %d)!", this.rd_trans_id[0]), UVM_LOW)
				
				this.rd_trans_id[0]++;
			end
			
			forever
			begin
				automatic AXITrans #(.addr_width(32), .data_width(32), 
					.bresp_width(2), .rresp_width(2)) axi_trans;
				
				this.rd_trans_port[1].get(axi_trans);
				
				`uvm_info("AXISdramEnvScoreboard", 
					$sformatf("AXISdramEnvScoreboard got axi1_rd_trans(id = %d)!", this.rd_trans_id[1]), UVM_LOW)
				
				this.rd_trans_id[1]++;
			end
			
			forever
			begin
				automatic AXITrans #(.addr_width(32), .data_width(32), 
					.bresp_width(2), .rresp_width(2)) axi_trans;
				
				this.rd_trans_port[2].get(axi_trans);
				
				`uvm_info("AXISdramEnvScoreboard", 
					$sformatf("AXISdramEnvScoreboard got axi2_rd_trans(id = %d)!", this.rd_trans_id[2]), UVM_LOW)
				
				this.rd_trans_id[2]++;
			end
			
			forever
			begin
				automatic AXITrans #(.addr_width(32), .data_width(32), 
					.bresp_width(2), .rresp_width(2)) axi_trans;
				
				this.wt_trans_port[0].get(axi_trans);
				
				`uvm_info("AXISdramEnvScoreboard", 
					$sformatf("AXISdramEnvScoreboard got axi0_wt_trans(id = %d)!", this.wt_trans_id[0]), UVM_LOW)
				
				this.wt_trans_id[0]++;
			end
			
			forever
			begin
				automatic AXITrans #(.addr_width(32), .data_width(32), 
					.bresp_width(2), .rresp_width(2)) axi_trans;
				
				this.wt_trans_port[1].get(axi_trans);
				
				`uvm_info("AXISdramEnvScoreboard", 
					$sformatf("AXISdramEnvScoreboard got axi1_wt_trans(id = %d)!", this.wt_trans_id[1]), UVM_LOW)
				
				this.wt_trans_id[1]++;
			end
			
			forever
			begin
				automatic AXITrans #(.addr_width(32), .data_width(32), 
					.bresp_width(2), .rresp_width(2)) axi_trans;
				
				this.wt_trans_port[2].get(axi_trans);
				
				`uvm_info("AXISdramEnvScoreboard", 
					$sformatf("AXISdramEnvScoreboard got axi2_wt_trans(id = %d)!", this.wt_trans_id[2]), UVM_LOW)
				
				this.wt_trans_id[2]++;
			end
		join_none
	endtask
	
endclass

`endif
