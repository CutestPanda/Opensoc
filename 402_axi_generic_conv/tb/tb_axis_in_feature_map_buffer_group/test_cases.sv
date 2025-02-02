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

class AxisInFtMapBufGrpCase0SAXISSeq #(
	integer feature_data_width = 16 // 特征点位宽(8 | 16 | 32 | 64)
)extends uvm_sequence #(AXISTrans #(.data_width(64), .user_width(2)));
	
	local AXISTrans #(.data_width(64), .user_width(2)) m_axis_trans; // AXIS主机事务
	
	// 注册object
	`uvm_object_param_utils(AxisInFtMapBufGrpCase0SAXISSeq #(.feature_data_width(feature_data_width)))
	
	function new(string name = "AxisInFtMapBufGrpCase0SAXISSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		// 行#0有效, 行#1有效, 行#2有效
		for(int k = 0;k < 3;k++)
		begin
			`uvm_do_with(this.m_axis_trans, {
				data_n == 2;
				
				data.size() == data_n;
				last.size() == data_n;
				user.size() == data_n;
				wait_period_n.size() == data_n;
				
				foreach(data[i]){
					(data[i][15:0] == (i * 4)) && 
					(data[i][31:16] == (i * 4 + 1)) && 
					(data[i][47:32] == (i * 4 + 2)) && 
					(data[i][63:48] == (i * 4 + 3));
				}
				
				foreach(last[i]){
					last[i] == (i == (data_n - 1));
				}
				
				foreach(user[i]){
					user[i] == {1'b1, k == 2};
				}
				
				foreach(wait_period_n[i]){
					wait_period_n[i] <= 2;
				}
			})
		end
		
		// 行#0无效, 行#1有效, 行#2有效
		`uvm_do_with(this.m_axis_trans, {
			data_n == 1;
			
			data.size() == 1;
			last.size() == 1;
			user.size() == 1;
			wait_period_n.size() == 1;
			
			last[0] == 1'b1;
			user[0] == 2'b00;
			wait_period_n[0] <= 2;
		})
		
		for(int k = 0;k < 2;k++)
		begin
			`uvm_do_with(this.m_axis_trans, {
				data_n == 2;
				
				data.size() == data_n;
				last.size() == data_n;
				user.size() == data_n;
				wait_period_n.size() == data_n;
				
				foreach(data[i]){
					(data[i][15:0] == (i * 4)) && 
					(data[i][31:16] == (i * 4 + 1)) && 
					(data[i][47:32] == (i * 4 + 2)) && 
					(data[i][63:48] == (i * 4 + 3));
				}
				
				foreach(last[i]){
					last[i] == (i == (data_n - 1));
				}
				
				foreach(user[i]){
					user[i] == {1'b1, k == 1};
				}
				
				foreach(wait_period_n[i]){
					wait_period_n[i] <= 2;
				}
			})
		end
		
		// 行#0无效, 行#1有效, 行#2无效
		`uvm_do_with(this.m_axis_trans, {
			data_n == 1;
			
			data.size() == 1;
			last.size() == 1;
			user.size() == 1;
			wait_period_n.size() == 1;
			
			last[0] == 1'b1;
			user[0] == 2'b00;
			wait_period_n[0] <= 2;
		})
		
		`uvm_do_with(this.m_axis_trans, {
			data_n == 2;
			
			data.size() == data_n;
			last.size() == data_n;
			user.size() == data_n;
			wait_period_n.size() == data_n;
			
			foreach(data[i]){
				(data[i][15:0] == (i * 4)) && 
				(data[i][31:16] == (i * 4 + 1)) && 
				(data[i][47:32] == (i * 4 + 2)) && 
				(data[i][63:48] == (i * 4 + 3));
			}
			
			foreach(last[i]){
				last[i] == (i == (data_n - 1));
			}
			
			foreach(user[i]){
				user[i] == 2'b11;
			}
			
			foreach(wait_period_n[i]){
				wait_period_n[i] <= 2;
			}
		})
		
		// 行#0有效, 行#1有效, 行#2无效
		for(int k = 0;k < 2;k++)
		begin
			`uvm_do_with(this.m_axis_trans, {
				data_n == 2;
				
				data.size() == data_n;
				last.size() == data_n;
				user.size() == data_n;
				wait_period_n.size() == data_n;
				
				foreach(data[i]){
					(data[i][15:0] == (i * 4)) && 
					(data[i][31:16] == (i * 4 + 1)) && 
					(data[i][47:32] == (i * 4 + 2)) && 
					(data[i][63:48] == (i * 4 + 3));
				}
				
				foreach(last[i]){
					last[i] == (i == (data_n - 1));
				}
				
				foreach(user[i]){
					user[i] == {1'b1, k == 1};
				}
				
				foreach(wait_period_n[i]){
					wait_period_n[i] <= 2;
				}
			})
		end
		
		// 行#0有效, 行#1有效, 行#2有效
		for(int k = 0;k < 3;k++)
		begin
			`uvm_do_with(this.m_axis_trans, {
				data_n == 2;
				
				data.size() == data_n;
				last.size() == data_n;
				user.size() == data_n;
				wait_period_n.size() == data_n;
				
				foreach(data[i]){
					(data[i][15:0] == (i * 4)) && 
					(data[i][31:16] == (i * 4 + 1)) && 
					(data[i][47:32] == (i * 4 + 2)) && 
					(data[i][63:48] == (i * 4 + 3));
				}
				
				foreach(last[i]){
					last[i] == (i == (data_n - 1));
				}
				
				foreach(user[i]){
					user[i] == {1'b1, k == 2};
				}
				
				foreach(wait_period_n[i]){
					wait_period_n[i] <= 2;
				}
			})
		end
		
		// 行#0无效, 行#1无效, 行#2无效
		`uvm_do_with(this.m_axis_trans, {
			data_n == 1;
			
			data.size() == 1;
			last.size() == 1;
			user.size() == 1;
			wait_period_n.size() == 1;
			
			last[0] == 1'b1;
			user[0] == 2'b01;
			wait_period_n[0] <= 2;
		})
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class AxisInFtMapBufGrpCase0Test extends uvm_test;
	
	localparam integer in_feature_map_buffer_rd_prl_n = 2; // 读输入特征图缓存的并行个数
	localparam integer feature_data_width = 16; // 特征点位宽(8 | 16 | 32 | 64)
	
	// AXIS输入特征图缓存组测试环境
	local AxisInFtMapBufGrpEnv #(.in_feature_map_buffer_rd_prl_n(in_feature_map_buffer_rd_prl_n), 
		.feature_data_width(feature_data_width)) env;
	
	// 注册component
	`uvm_component_utils(AxisInFtMapBufGrpCase0Test)
	
	function new(string name = "AxisInFtMapBufGrpCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = AxisInFtMapBufGrpEnv #(.in_feature_map_buffer_rd_prl_n(in_feature_map_buffer_rd_prl_n), 
			.feature_data_width(feature_data_width))
				::type_id::create("env", this); // 创建env
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			AxisInFtMapBufGrpCase0SAXISSeq #(.feature_data_width(feature_data_width))
				::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("AxisInFtMapBufGrpCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
