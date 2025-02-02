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

`ifndef __MODEL_H

`define __MODEL_H

`include "transactions.sv"

/** 参考模型:n通道并行m核并行3x3卷积计算单元 **/
class AxisConvCalModel #(
	integer mul_add_width = 16, // 乘加位宽(8 | 16)
	integer quaz_acc = 10, // 量化精度(必须在范围[1, mul_add_width-1]内)
	integer add_3_input_ext_int_width = 4, // 三输入加法器额外考虑的整数位数(必须<=(mul_add_width-quaz_acc))
	integer add_3_input_ext_frac_width = 4, // 三输入加法器额外考虑的小数位数(必须<=quaz_acc)
	integer in_feature_map_buffer_rd_prl_n = 4, // 读输入特征图缓存的并行个数(1 | 2 | 4 | 8 | 16)
	integer kernal_prl_n = 4 // 多通道卷积核的并行个数(1 | 2 | 4 | 8 | 16)
)extends uvm_component;
	
	// 内部配置
	localparam integer max_feature_map_w = 256; // 最大的输入特征图宽度
	localparam integer max_feature_map_chn_n = 128; // 最大的输入特征图通道数
	localparam integer max_kernal_n = 128; // 最大的卷积核个数
	
	// 通信端口
	uvm_blocking_get_port #(AXISTrans #(.data_width(mul_add_width*3*in_feature_map_buffer_rd_prl_n), 
		.user_width(0))) m_axis_ft_col_trans_port;
	uvm_blocking_get_port #(AXISTrans #(.data_width(64), .user_width(1))) m_axis_kernal_trans_port;
	uvm_analysis_port #(AXISTrans #(.data_width(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width), .user_width(1))) out_analysis_port;
	
	// 特征图大小配置
	local int unsigned ift_map_chn; // 输入特征图通道数
	local int unsigned oft_map_h; // 输出特征图高度
	local int unsigned oft_map_chn; // 输出特征图通道数
	
	// 运行模式配置
	local bit en_left_padding; // 是否使能左填充
	local bit en_right_padding; // 是否使能右填充
	local bit is_3x3_kernal; // 卷积核类型是否为3x3
	
	// 参考模型
	local int unsigned ift_map_chn_i; // 输入特征图通道号
	local int unsigned oft_map_y; // 输出特征图行号
	local int unsigned oft_map_chn_i; // 输出特征图通道号
	local int unsigned now_vld_kernal_n; // 当前有效的多通道卷积核个数
	local int unsigned kernal_data_item_id; // 当前的卷积核数据项编号
	local int unsigned kernal_chn_id; // 当前的卷积核通道编号
	local bit[9*mul_add_width-1:0] kernal_pars_buf[0:max_kernal_n-1][0:max_feature_map_chn_n-1]; // 卷积核参数缓存区
	local bit[3*mul_add_width-1:0] ft_map_grp[0:max_feature_map_w-1][0:in_feature_map_buffer_rd_prl_n-1]; // 特征组
	local bit[add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width-1:0] now_conv_golden_res; // 当前的卷积结果(黄金参考)
	local bit[9*mul_add_width-1:0] kernal_selected[0:kernal_prl_n-1][0:in_feature_map_buffer_rd_prl_n-1]; // 选定的卷积核
	
	// 事务
	local AXISTrans #(.data_width(mul_add_width*3*in_feature_map_buffer_rd_prl_n), .user_width(0)) m_axis_ft_col_trans;
	local AXISTrans #(.data_width(64), .user_width(1)) m_axis_kernal_trans;
	local AXISTrans #(.data_width(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width), .user_width(1)) out_trans[0:kernal_prl_n-1];
	
	// 注册component
	`uvm_component_param_utils(AxisConvCalModel #(.mul_add_width(mul_add_width), .quaz_acc(quaz_acc), .add_3_input_ext_int_width(add_3_input_ext_int_width), .add_3_input_ext_frac_width(add_3_input_ext_frac_width), .in_feature_map_buffer_rd_prl_n(in_feature_map_buffer_rd_prl_n), .kernal_prl_n(kernal_prl_n)))
	
	function new(string name = "AxisConvCalModel", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	function void set_ft_map_size(input int unsigned ift_map_chn, input int unsigned oft_map_h, 
		input int unsigned oft_map_chn);
		this.ift_map_chn = ift_map_chn;
		this.oft_map_h = oft_map_h;
		this.oft_map_chn = oft_map_chn;
	endfunction
	
	function void set_padding(input bit en_left_padding, input bit en_right_padding);
		this.en_left_padding = en_left_padding;
		this.en_right_padding = en_right_padding;
	endfunction
	
	function void set_kernal_type(input bit is_3x3_kernal);
		this.is_3x3_kernal = is_3x3_kernal;
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.m_axis_ft_col_trans_port = new("m_axis_ft_col_trans_port", this);
		this.m_axis_kernal_trans_port = new("m_axis_kernal_trans_port", this);
		this.out_analysis_port = new("out_analysis_port", this);
		
		this.ift_map_chn_i = 0;
		this.oft_map_y = 0;
		this.oft_map_chn_i = 0;
		
		this.now_vld_kernal_n = 0;
		this.kernal_data_item_id = 0;
		this.kernal_chn_id = 0;
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			this.get_kernal();
			this.get_ft_map_and_gen_ref();
		join_none
	endtask
	
	local task get_kernal();
		forever
		begin
			// 从通信端口获取事务
			this.m_axis_kernal_trans_port.get(this.m_axis_kernal_trans);
			
			// 清零卷积核参数缓存区
			for(int i = 0;i < max_feature_map_chn_n;i++)
			begin
				this.kernal_pars_buf[this.now_vld_kernal_n][i] = 0;
			end
			
			// 保存卷积核参数
			if((this.m_axis_kernal_trans.data_n > 0) && this.m_axis_kernal_trans.user[0])
			begin
				for(int i = 0;i < this.m_axis_kernal_trans.data_n;i++)
				begin
					automatic bit[63:0] now_data = this.m_axis_kernal_trans.data[i];
					automatic bit[9*mul_add_width-1:0] now_kernal_item;
					
					for(int j = 0;j < (64/mul_add_width);j++)
					begin
						now_kernal_item = now_data[mul_add_width-1:0];
						
						if(this.is_3x3_kernal)
						begin
							this.kernal_pars_buf[this.now_vld_kernal_n][this.kernal_chn_id] |= 
								(now_kernal_item << (this.kernal_data_item_id * mul_add_width));
						end
						else
						begin
							this.kernal_pars_buf[this.now_vld_kernal_n][this.kernal_chn_id] |= 
								(now_kernal_item << (4 * mul_add_width));
						end
						
						now_data >>= mul_add_width;
						
						if(this.is_3x3_kernal)
						begin
							if(this.kernal_data_item_id == 8)
							begin
								this.kernal_data_item_id = 0;
								this.kernal_chn_id++;
							end
							else
								this.kernal_data_item_id++;
						end
						else
						begin
							this.kernal_chn_id++;
						end
					end
				end
			end
			
			`uvm_info("AxisConvCalModel", $sformatf("get kernal(id = %d)", this.now_vld_kernal_n), UVM_LOW)
			
			this.kernal_data_item_id = 0;
			this.kernal_chn_id = 0;
			this.now_vld_kernal_n++;
		end
	endtask
	
	local task get_ft_map_and_gen_ref();
		forever
		begin
			// 从通信端口获取事务
			this.m_axis_ft_col_trans_port.get(this.m_axis_ft_col_trans);
			
			// 保存特征组
			for(int i = 0;i < this.m_axis_ft_col_trans.data_n;i++)
			begin
				automatic bit[mul_add_width*3*in_feature_map_buffer_rd_prl_n-1:0] now_ft_col = this.m_axis_ft_col_trans.data[i];
				
				for(int j = 0;j < in_feature_map_buffer_rd_prl_n;j++)
				begin
					this.ft_map_grp[i][j] = now_ft_col[3*mul_add_width-1:0];
					
					now_ft_col >>= (mul_add_width*3);
				end
			end
			
			// 等待多通道卷积核可用
			wait(this.now_vld_kernal_n >= (this.oft_map_chn_i + kernal_prl_n));
			
			// 选定卷积核
			for(int i = 0;i < kernal_prl_n;i++)
			begin
				for(int j = 0;j < in_feature_map_buffer_rd_prl_n;j++)
				begin
					this.kernal_selected[i][j] = this.kernal_pars_buf[this.oft_map_chn_i + i][this.ift_map_chn_i + j];
				end
			end
			
			// 初始化输出事务
			if(this.ift_map_chn_i == 0)
			begin
				for(int i = 0;i < kernal_prl_n;i++)
				begin
					automatic int unsigned out_data_n = this.m_axis_ft_col_trans.data_n - 
						(this.en_left_padding ? 0:1) - (this.en_right_padding ? 0:1);
					
					this.out_trans[i] = new();
					
					this.out_trans[i].data_n = out_data_n;
					
					for(int j = 0;j < out_data_n;j++)
						this.out_trans[i].data.push_back(0);
				end
			end
			
			// 生成黄金参考
			for(int i = 0, p = 0;i < this.m_axis_ft_col_trans.data_n;i++)
			begin
				// {x3y3, x2y3, x1y3, x3y2, x2y2, x1y2, x3y1, x2y1, x1y1}
				automatic bit[9*mul_add_width-1:0] ft_map_roi[0:in_feature_map_buffer_rd_prl_n-1];
				
				// 左/右填充
				if((i == 0) && (!this.en_left_padding))
					continue;
				else if((i == (this.m_axis_ft_col_trans.data_n-1)) && (!this.en_right_padding))
					continue;
				
				// 生成ROI
				for(int j = 0;j < in_feature_map_buffer_rd_prl_n;j++)
				begin
					ft_map_roi[j][mul_add_width-1:0] = 
						(i == 0) ? 0:ft_map_grp[i-1][j][mul_add_width-1:0]; // x1y1
					ft_map_roi[j][mul_add_width*2-1:mul_add_width] = 
						ft_map_grp[i][j][mul_add_width-1:0]; // x2y1
					ft_map_roi[j][mul_add_width*3-1:mul_add_width*2] = 
						(i == (this.m_axis_ft_col_trans.data_n-1)) ? 0:ft_map_grp[i+1][j][mul_add_width-1:0]; // x3y1
					ft_map_roi[j][mul_add_width*4-1:mul_add_width*3] = 
						(i == 0) ? 0:ft_map_grp[i-1][j][mul_add_width*2-1:mul_add_width]; // x1y2
					ft_map_roi[j][mul_add_width*5-1:mul_add_width*4] = 
						ft_map_grp[i][j][mul_add_width*2-1:mul_add_width]; // x2y2
					ft_map_roi[j][mul_add_width*6-1:mul_add_width*5] = 
						(i == (this.m_axis_ft_col_trans.data_n-1)) ? 0:ft_map_grp[i+1][j][mul_add_width*2-1:mul_add_width]; // x3y2
					ft_map_roi[j][mul_add_width*7-1:mul_add_width*6] = 
						(i == 0) ? 0:ft_map_grp[i-1][j][mul_add_width*3-1:mul_add_width*2]; // x1y3
					ft_map_roi[j][mul_add_width*8-1:mul_add_width*7] = 
						ft_map_grp[i][j][mul_add_width*3-1:mul_add_width*2]; // x2y3
					ft_map_roi[j][mul_add_width*9-1:mul_add_width*8] = 
						(i == (this.m_axis_ft_col_trans.data_n-1)) ? 0:ft_map_grp[i+1][j][mul_add_width*3-1:mul_add_width*2]; // x3y3
				end
				
				// 计算卷积
				for(int j = 0;j < kernal_prl_n;j++)
				begin
					this.now_conv_golden_res = cal_conv(ft_map_roi, this.kernal_selected[j]);
					
					this.out_trans[j].data[p] += $signed(this.now_conv_golden_res);
				end
				
				p++;
			end
			
			// 传递黄金参考
			if((this.ift_map_chn_i + in_feature_map_buffer_rd_prl_n) >= this.ift_map_chn)
			begin
				automatic int unsigned oft_map_chn_n_to_add;
				
				if((this.oft_map_chn_i + kernal_prl_n) >= this.oft_map_chn)
					oft_map_chn_n_to_add = this.oft_map_chn - this.oft_map_chn_i;
				else
					oft_map_chn_n_to_add = kernal_prl_n;
				
				for(int k = 0;k < oft_map_chn_n_to_add;k++)
					this.out_analysis_port.write(this.out_trans[k]);
				
				`uvm_info("AxisConvCalModel", $sformatf("gnr ref(oft_map_chn_i%d, oft_map_y%d)", this.oft_map_chn_i, this.oft_map_y), UVM_LOW)
			end
			
			// 更新特征图位置索引
			if((this.ift_map_chn_i + in_feature_map_buffer_rd_prl_n) >= this.ift_map_chn)
			begin
				this.ift_map_chn_i = 0;
				
				if(this.oft_map_y >= (this.oft_map_h - 1))
				begin
					this.oft_map_y = 0;
					
					if((this.oft_map_chn_i + kernal_prl_n) >= this.oft_map_chn)
						this.oft_map_chn_i = 0;
					else
						this.oft_map_chn_i += kernal_prl_n;
				end
				else
					this.oft_map_y++;
			end
			else
				this.ift_map_chn_i += in_feature_map_buffer_rd_prl_n;
		end
	endtask
	
	static function bit[(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)-1:0] cal_conv(ref bit[9*mul_add_width-1:0] ft[0:in_feature_map_buffer_rd_prl_n-1], 
		ref bit[9*mul_add_width-1:0] kernal[0:in_feature_map_buffer_rd_prl_n-1]);
		automatic bit[add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width-1:0] res = 0;
		
		for(int i = 0;i < in_feature_map_buffer_rd_prl_n;i++)
		begin
			automatic bit[9*mul_add_width-1:0] op1 = ft[i];
			automatic bit[9*mul_add_width-1:0] op2 = kernal[i];
			automatic bit[2*mul_add_width-1:0] mul_add_res[0:2];
			automatic bit[add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width-1:0] sgc_conv_res;
			
			mul_add_res[0] = 0;
			mul_add_res[1] = 0;
			mul_add_res[2] = 0;
			
			for(int j = 0;j < 9;j++)
			begin
				automatic bit[2*mul_add_width-1:0] mul_res = 
					$signed(op1[mul_add_width-1:0]) * $signed(op2[mul_add_width-1:0]);
				
				mul_add_res[j / 3] += $signed(mul_res);
				
				op1 >>= mul_add_width;
				op2 >>= mul_add_width;
			end
			
			sgc_conv_res = 0;
			
			sgc_conv_res += $signed(mul_add_res[0][add_3_input_ext_int_width+quaz_acc+mul_add_width-1:quaz_acc-add_3_input_ext_frac_width]);
			sgc_conv_res += $signed(mul_add_res[1][add_3_input_ext_int_width+quaz_acc+mul_add_width-1:quaz_acc-add_3_input_ext_frac_width]);
			sgc_conv_res += $signed(mul_add_res[2][add_3_input_ext_int_width+quaz_acc+mul_add_width-1:quaz_acc-add_3_input_ext_frac_width]);
			
			res += $signed(sgc_conv_res);
		end
		
		return res;
	endfunction
	
endclass

`endif
