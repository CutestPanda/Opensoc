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

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"
`include "scoreboards.sv"
`include "ref_models.sv"

/** 环境:n通道并行m核并行3x3卷积计算单元 **/
class AxisConvCalEnv #(
	integer mul_add_width = 16, // 乘加位宽(8 | 16)
	integer in_feature_map_buffer_rd_prl_n = 4, // 读输入特征图缓存的并行个数(1 | 2 | 4 | 8 | 16)
	integer kernal_prl_n = 4, // 多通道卷积核的并行个数(1 | 2 | 4 | 8 | 16)
	real simulation_delay = 1 // 仿真延时
)extends uvm_env;
	
	// 内部配置
	localparam integer quaz_acc = 10; // 量化精度(必须在范围[1, mul_add_width-1]内)
	localparam integer add_3_input_ext_int_width = 4; // 三输入加法器额外考虑的整数位数(必须<=(mul_add_width-quaz_acc))
	localparam integer add_3_input_ext_frac_width = 4; // 三输入加法器额外考虑的小数位数(必须<=quaz_acc)
	localparam int unsigned ift_map_chn = 3; // 输入特征图通道数
	localparam int unsigned oft_map_w = 3; // 输出特征图宽度
	localparam int unsigned oft_map_h = 3; // 输出特征图高度
	localparam int unsigned oft_map_chn = 5; // 输出特征图通道数
	localparam bit en_left_padding = 1'b1; // 是否使能左填充
	localparam bit en_right_padding = 1'b1; // 是否使能右填充
	localparam bit is_3x3_kernal = 1'b1; // 卷积核类型是否为3x3
	
	// 组件
	local AXISMasterAgent #(.out_drive_t(simulation_delay), 
		.data_width(mul_add_width*3*in_feature_map_buffer_rd_prl_n), .user_width(0)) m_axis_ft_col_agt; // 特征列AXIS主机代理
	local AXISMasterAgent #(.out_drive_t(simulation_delay), 
		.data_width(64), .user_width(1)) m_axis_kernal_agt; // 卷积核AXIS主机代理
	local AXISSlaveAgent #(.out_drive_t(simulation_delay), 
		.data_width(mul_add_width*2), .user_width(16)) s_axis_res_agt; // 卷积结果AXIS从机代理
	local AxisConvCalScoreboard #(.mul_add_width(mul_add_width), .kernal_prl_n(kernal_prl_n), 
		.add_3_input_ext_int_width(add_3_input_ext_int_width), 
		.add_3_input_ext_frac_width(add_3_input_ext_frac_width)) scoreboard; // 计分板
	local AxisConvCalModel #(.mul_add_width(mul_add_width), .quaz_acc(quaz_acc), 
		.add_3_input_ext_int_width(add_3_input_ext_int_width), 
		.add_3_input_ext_frac_width(add_3_input_ext_frac_width), 
		.in_feature_map_buffer_rd_prl_n(in_feature_map_buffer_rd_prl_n), .kernal_prl_n(kernal_prl_n)) ref_model; // 参考模型
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(mul_add_width*3*in_feature_map_buffer_rd_prl_n), 
		.user_width(0))) m_axis_ft_col_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(64), 
		.user_width(1))) m_axis_kernal_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(mul_add_width*2), 
		.user_width(16))) s_axis_res_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width), 
		.user_width(1))) mdl_scb_fifo;
	
	// 注册component
	`uvm_component_param_utils(AxisConvCalEnv #(.mul_add_width(mul_add_width), .in_feature_map_buffer_rd_prl_n(in_feature_map_buffer_rd_prl_n), .kernal_prl_n(kernal_prl_n), .simulation_delay(simulation_delay)))
	
	function new(string name = "AxisConvCalEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.m_axis_ft_col_agt = AXISMasterAgent #(.out_drive_t(simulation_delay), 
			.data_width(mul_add_width*3*in_feature_map_buffer_rd_prl_n), .user_width(0))::type_id::create("agt1", this);
		this.m_axis_ft_col_agt.is_active = UVM_ACTIVE;
		this.m_axis_kernal_agt = AXISMasterAgent #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(1))::type_id::create("agt2", this);
		this.m_axis_kernal_agt.is_active = UVM_ACTIVE;
		this.s_axis_res_agt = AXISSlaveAgent #(.out_drive_t(simulation_delay), 
			.data_width(mul_add_width*2), .user_width(16))::type_id::create("agt3", this);
		this.s_axis_res_agt.is_active = UVM_ACTIVE;
		
		// 创建scoreboard
		this.scoreboard = AxisConvCalScoreboard #(.mul_add_width(mul_add_width), .kernal_prl_n(kernal_prl_n), 
			.add_3_input_ext_int_width(add_3_input_ext_int_width), 
			.add_3_input_ext_frac_width(add_3_input_ext_frac_width))::type_id::create("scb", this);
		this.scoreboard.set_ft_map_size(oft_map_w, oft_map_h, oft_map_chn);
		
		// 创建reference model
		this.ref_model = AxisConvCalModel #(.mul_add_width(mul_add_width), .quaz_acc(quaz_acc), 
			.add_3_input_ext_int_width(add_3_input_ext_int_width), 
			.add_3_input_ext_frac_width(add_3_input_ext_frac_width), .in_feature_map_buffer_rd_prl_n(in_feature_map_buffer_rd_prl_n), 
			.kernal_prl_n(kernal_prl_n))::type_id::create("ref_model", this);
		this.ref_model.set_ft_map_size(ift_map_chn, oft_map_h, oft_map_chn);
		this.ref_model.set_padding(en_left_padding, en_right_padding);
		this.ref_model.set_kernal_type(is_3x3_kernal);
		
		// 创建通信fifo
		this.m_axis_ft_col_agt_fifo = new("m_axis_ft_col_agt_fifo", this);
		this.m_axis_kernal_agt_fifo = new("m_axis_kernal_agt_fifo", this);
		this.s_axis_res_agt_fifo = new("s_axis_res_agt_fifo", this);
		this.mdl_scb_fifo = new("mdl_scb_fifo", this);
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.m_axis_ft_col_agt.axis_analysis_port.connect(this.m_axis_ft_col_agt_fifo.analysis_export);
		this.ref_model.m_axis_ft_col_trans_port.connect(this.m_axis_ft_col_agt_fifo.blocking_get_export);
		this.m_axis_kernal_agt.axis_analysis_port.connect(this.m_axis_kernal_agt_fifo.analysis_export);
		this.ref_model.m_axis_kernal_trans_port.connect(this.m_axis_kernal_agt_fifo.blocking_get_export);
		this.s_axis_res_agt.axis_analysis_port.connect(this.s_axis_res_agt_fifo.analysis_export);
		this.scoreboard.s_axis_res_trans_port.connect(this.s_axis_res_agt_fifo.blocking_get_export);
		this.ref_model.out_analysis_port.connect(this.mdl_scb_fifo.analysis_export);
		this.scoreboard.ref_trans_port.connect(this.mdl_scb_fifo.blocking_get_export);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
	endtask
	
endclass
	
`endif
