`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class AxisConvCalCase0MAxisFtColSeq #(
	integer mul_add_width = 16, // 乘加位宽(8 | 16)
	integer in_feature_map_buffer_rd_prl_n = 4 // 读输入特征图缓存的并行个数(1 | 2 | 4 | 8 | 16)
)extends uvm_sequence #(AXISTrans #(.data_width(mul_add_width*3*in_feature_map_buffer_rd_prl_n), .user_width(0)));
	
	local AXISTrans #(.data_width(mul_add_width*3*in_feature_map_buffer_rd_prl_n), .user_width(0)) m_axis_trans; // AXIS主机事务
	
	// 注册object
	`uvm_object_param_utils(AxisConvCalCase0MAxisFtColSeq #(.mul_add_width(mul_add_width), .in_feature_map_buffer_rd_prl_n(in_feature_map_buffer_rd_prl_n)))
	
	function new(string name = "AxisConvCalCase0MAxisFtColSeq");
		super.new(name);
	endfunction
	
	/*
	高度 = 7
	宽度 = 5
	通道数 = 3
	通道并行数 = 2
	卷积核类型 = 3x3
	核数 = 5
	核并行数 = 2
	使能上/下填充
	*/
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		for(int m = 0;m < 3;m++)
		begin
			for(int i = 0;i < 7;i++)
			begin
				for(int j = 0;j < 2;j++)
				begin
					`uvm_do_with(this.m_axis_trans, {
						data_n == 5;
						
						data.size() == 5;
						last.size() == 5;
						wait_period_n.size() == 5;
						
						foreach(data[k]){
							if(j == 1) // 无效的通道
								data[k][mul_add_width*6-1:mul_add_width*3] == 0;
						}
						
						foreach(last[i]) last[i] == (i == 4);
						
						foreach(wait_period_n[i]) wait_period_n[i] <= 2;
					})
				end
			end
		end
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class AxisConvCalCase0MAxisKernalSeq extends uvm_sequence #(AXISTrans #(.data_width(64), .user_width(1)));
	
	local AXISTrans #(.data_width(64), .user_width(1)) m_axis_trans; // AXIS主机事务
	
	// 注册object
	`uvm_object_utils(AxisConvCalCase0MAxisKernalSeq)
	
	function new(string name = "AxisConvCalCase0MAxisKernalSeq");
		super.new(name);
	endfunction
	
	/*
	通道数 = 3
	核数 = 5
	核并行数 = 2
	卷积核类型 = 3x3
	*/
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		for(int i = 0;i < 5;i++)
		begin
			`uvm_do_with(this.m_axis_trans, {
				data_n == 7;
				
				data.size() == 7;
				keep.size() == 7;
				user.size() == 7;
				last.size() == 7;
				wait_period_n.size() == 7;
				
				foreach(keep[i]){
					if(i == 6)
						keep[i] == 8'b0011_1111;
					else
						keep[i] == 8'b1111_1111;
					
					// keep[i] == 8'b1111_1111;
				}
				
				foreach(user[i]) user[i] == 1'b1;
				
				foreach(last[i]) last[i] == (i == 6);
				
				foreach(wait_period_n[i]) wait_period_n[i] <= 4;
			})
		end
		
		`uvm_do_with(this.m_axis_trans, {
			data_n == 1;
			
			data.size() == 1;
			keep.size() == 1;
			user.size() == 1;
			last.size() == 1;
			wait_period_n.size() == 1;
			
			keep[0] == 8'b0000_0000;
			user[0] == 1'b0;
			last[0] == 1'b1;
			wait_period_n[0] <= 4;
		})
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class AxisConvCalBaseTest #(
	integer mul_add_width = 16, // 乘加位宽(8 | 16)
	integer in_feature_map_buffer_rd_prl_n = 4, // 读输入特征图缓存的并行个数(1 | 2 | 4 | 8 | 16)
	integer kernal_prl_n = 4, // 多通道卷积核的并行个数(1 | 2 | 4 | 8 | 16)
	real simulation_delay = 1 // 仿真延时
)extends uvm_test;
	
	// 通道并行m核并行3x3卷积计算单元测试环境
	local AxisConvCalEnv #(.mul_add_width(mul_add_width), .in_feature_map_buffer_rd_prl_n(in_feature_map_buffer_rd_prl_n), 
		.kernal_prl_n(kernal_prl_n), .simulation_delay(simulation_delay)) env;
	
	// 注册component
	`uvm_component_param_utils(AxisConvCalBaseTest #(.mul_add_width(mul_add_width), .in_feature_map_buffer_rd_prl_n(in_feature_map_buffer_rd_prl_n), .kernal_prl_n(kernal_prl_n), .simulation_delay(simulation_delay)))
	
	function new(string name = "AxisConvCalBaseTest", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = AxisConvCalEnv #(.mul_add_width(mul_add_width), .in_feature_map_buffer_rd_prl_n(in_feature_map_buffer_rd_prl_n), 
			.kernal_prl_n(kernal_prl_n), .simulation_delay(simulation_delay))::type_id::create("env", this); // 创建env
	endfunction
	
endclass

class AxisConvCalCase0Test extends AxisConvCalBaseTest #(.mul_add_width(16), .in_feature_map_buffer_rd_prl_n(2), 
	.kernal_prl_n(2), .simulation_delay(1));
	
	// 注册component
	`uvm_component_utils(AxisConvCalCase0Test)
	
	function new(string name = "AxisConvCalCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			AxisConvCalCase0MAxisFtColSeq #(.mul_add_width(mul_add_width), 
				.in_feature_map_buffer_rd_prl_n(in_feature_map_buffer_rd_prl_n))::type_id::get());
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt2.sqr.main_phase", 
			"default_sequence", 
			AxisConvCalCase0MAxisKernalSeq::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("AxisConvCalCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
