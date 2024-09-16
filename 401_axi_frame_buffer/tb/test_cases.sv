`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"

class AXIFrameBufferCase0SAXISSeq #(
	integer data_width = 8 // 数据位宽(必须能被8整除, 且>0)
)extends uvm_sequence #(AXISTrans #(.data_width(data_width), .user_width(0)));
	
	localparam integer frame_n = 10; // 测试帧数
	localparam integer img_n = 20; // 测试图片总像素个数
	
	local AXISTrans #(.data_width(data_width), .user_width(0)) m_axis_trans; // AXIS主机事务
	local byte unsigned byte_v; // AXIS数据当前字节的值
	
	// 注册object
	`uvm_object_param_utils(AXIFrameBufferCase0SAXISSeq #(.data_width(data_width)))
	
	function new(string name = "AXIFrameBufferCase0SAXISSeq");
		super.new(name);
	endfunction
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		repeat(frame_n)
		begin
			this.byte_v = 0;
			
			`uvm_create(this.m_axis_trans)
			
			this.m_axis_trans.data_n = img_n;
			
			this.m_axis_trans.wait_period_n = new[img_n];
			
			for(int i = 0;i < img_n;i++)
			begin
				automatic bit[data_width-1:0] data = 0;
				
				for(int j = 0;j < data_width / 8;j++)
				begin
					data >>= 8;
					data[data_width-1:data_width-8] = this.byte_v;
					
					this.byte_v++;
				end
				
				this.m_axis_trans.data.push_back(data);
				this.m_axis_trans.last.push_back(i == (img_n - 1));
				this.m_axis_trans.wait_period_n[i] = $urandom_range(0, 4);
			end
			
			`uvm_send(this.m_axis_trans)
		end
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class AXIFrameBufferCase0Test extends uvm_test;
	
	localparam integer pix_data_width = 24; // 像素位宽(必须能被8整除)
    localparam integer pix_per_clk_for_wt = 1; // 每clk写的像素个数
	localparam integer pix_per_clk_for_rd = 1; // 每clk读的像素个数
	localparam real simulation_delay = 1; // 仿真延时
	
	// AXI帧缓存测试环境
	local AXIFrameBufferEnv #(.out_drive_t(simulation_delay), 
		.s_axis_data_width(pix_data_width * pix_per_clk_for_wt), .m_axis_data_width(pix_data_width * pix_per_clk_for_rd)) env;
	
	// 注册component
	`uvm_component_utils(AXIFrameBufferCase0Test)
	
	function new(string name = "AXIFrameBufferCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = AXIFrameBufferEnv #(.out_drive_t(simulation_delay), 
			.s_axis_data_width(pix_data_width * pix_per_clk_for_wt), .m_axis_data_width(pix_data_width * pix_per_clk_for_rd))
				::type_id::create("env", this); // 创建env
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.agt1.sqr.main_phase", 
			"default_sequence", 
			AXIFrameBufferCase0SAXISSeq #(.data_width(pix_data_width * pix_per_clk_for_wt))
				::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("AXIFrameBufferCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
