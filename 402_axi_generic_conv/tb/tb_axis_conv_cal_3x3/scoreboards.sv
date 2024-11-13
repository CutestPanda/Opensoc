`timescale 1ns / 1ps

`ifndef __SCOREBOARD_H

`define __SCOREBOARD_H

`include "transactions.sv"

/** 计分板:n通道并行m核并行3x3卷积计算单元 **/
class AxisConvCalScoreboard #(
	integer mul_add_width = 16, // 乘加位宽(8 | 16)
	integer kernal_prl_n = 4, // 多通道卷积核的并行个数(1 | 2 | 4 | 8 | 16)
	integer add_3_input_ext_int_width = 4, // 三输入加法器额外考虑的整数位数(必须<=(mul_add_width-quaz_acc))
	integer add_3_input_ext_frac_width = 4 // 三输入加法器额外考虑的小数位数(必须<=quaz_acc)
)extends uvm_scoreboard;
	
	// 通信端口
	uvm_blocking_get_port #(AXISTrans #(.data_width(mul_add_width*2), 
		.user_width(16))) s_axis_res_trans_port;
	uvm_blocking_get_port #(AXISTrans #(.data_width(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width), 
		.user_width(1))) ref_trans_port;
	
	// 特征图大小配置
	local int unsigned oft_map_w; // 输出特征图宽度
	local int unsigned oft_map_h; // 输出特征图高度
	local int unsigned oft_map_chn; // 输出特征图通道数
	
	// 事务
	local AXISTrans #(.data_width(mul_add_width*2), .user_width(16)) res_trans;
	local AXISTrans #(.data_width(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width), .user_width(1)) ref_trans;
	
	// 比较
	local int unsigned oft_map_y; // 输出特征图行号
	local int unsigned oft_map_chn_i; // 输出特征图通道号
	local int unsigned oft_map_chn_ofs; // 输出特征图通道号偏移
	local bit cmp_success;
	
	// 注册component
	`uvm_component_param_utils(AxisConvCalScoreboard #(.mul_add_width(mul_add_width), .kernal_prl_n(kernal_prl_n), .add_3_input_ext_int_width(add_3_input_ext_int_width), .add_3_input_ext_frac_width(add_3_input_ext_frac_width)))
	
	function new(string name = "AxisConvCalScoreboard", uvm_component parent = null);
		super.new(name, parent);
		
		this.oft_map_y = 0;
		this.oft_map_chn_i = 0;
		this.oft_map_chn_ofs = 0;
	endfunction
	
	function void set_ft_map_size(input int unsigned oft_map_w, 
		input int unsigned oft_map_h, input int unsigned oft_map_chn);
		this.oft_map_w = oft_map_w;
		this.oft_map_h = oft_map_h;
		this.oft_map_chn = oft_map_chn;
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.s_axis_res_trans_port = new("s_axis_res_trans_port", this);
		this.ref_trans_port = new("ref_trans_port", this);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		forever
		begin
			this.ref_trans_port.get(this.ref_trans);
			this.s_axis_res_trans_port.get(this.res_trans);
			
			this.cmp_success = 1'b1;
			
			// 比较数据量
			if(this.res_trans.data_n != this.oft_map_w)
			begin
				`uvm_info("AxisConvCalScoreboard", $sformatf("data_n(%d) != %d", this.res_trans.data_n, this.oft_map_w), UVM_LOW)
				
				this.cmp_success = 1'b0;
			end
			
			// 比较输出通道号
			if(this.cmp_success)
			begin
				for(int i = 0;i < this.oft_map_w;i++)
				begin
					if(this.res_trans.user[i] != (this.oft_map_chn_i + this.oft_map_chn_ofs))
					begin
						`uvm_info("AxisConvCalScoreboard", $sformatf("oft_map_chn_i(%d) != %d", this.res_trans.user[i], this.oft_map_chn_i + this.oft_map_chn_ofs), UVM_LOW)
						
						this.cmp_success = 1'b0;
						
						break;
					end
				end
			end
			
			// 比较数据
			if(this.cmp_success)
			begin
				for(int i = 0;i < this.oft_map_w;i++)
				begin
					automatic bit[mul_add_width*2-1:0] res_data = this.res_trans.data[i];
					automatic bit[add_3_input_ext_frac_width+mul_add_width+add_3_input_ext_frac_width-1:0] ref_data = this.ref_trans.data[i];
					
					if(res_data[add_3_input_ext_frac_width+mul_add_width+add_3_input_ext_frac_width-1:0] != ref_data)
					begin
						`uvm_info("AxisConvCalScoreboard", "data mismatched", UVM_LOW)
						
						this.cmp_success = 1'b0;
						
						break;
					end
				end
			end
			
			// 打印比较结果
			if(this.cmp_success)
				`uvm_info("AxisConvCalScoreboard", $sformatf("(oft_map_chn_i%d, oft_map_y%d)check passed!", this.oft_map_chn_i + this.oft_map_chn_ofs, this.oft_map_y), UVM_LOW)
			else
			begin
				`uvm_error("AxisConvCalScoreboard", $sformatf("(oft_map_chn_i%d, oft_map_y%d)check failed!", this.oft_map_chn_i + this.oft_map_chn_ofs, this.oft_map_y))
				
				/*
				`uvm_info("AxisConvCalScoreboard", "ref_trans -> ", UVM_LOW)
				this.ref_trans.print();
				`uvm_info("AxisConvCalScoreboard", "res_trans -> ", UVM_LOW)
				this.res_trans.print();
				*/
			end
			
			// 更新特征图位置索引
			if((this.oft_map_chn_ofs >= (kernal_prl_n - 1)) || 
				((this.oft_map_chn_i + this.oft_map_chn_ofs) >= (this.oft_map_chn - 1)))
			begin
				if(this.oft_map_y >= (this.oft_map_h - 1))
				begin
					this.oft_map_chn_i += (this.oft_map_chn_ofs + 1);
					
					this.oft_map_y = 0;
				end
				else
					this.oft_map_y++;
				
				this.oft_map_chn_ofs = 0;
			end
			else
				this.oft_map_chn_ofs++;
		end
	endtask
	
endclass

`endif
