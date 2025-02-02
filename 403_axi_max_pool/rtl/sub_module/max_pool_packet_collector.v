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
/********************************************************************
本模块: 最大池化输出特征数据收集单元

描述:
将有效特征项个数不固定的特征数据收集起来, 生成紧凑/无空字节的数据包

注意：
对于输入的特征数据, 其有效特征项个数为1~(feature_n_per_clk+1)

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2024/10/12
********************************************************************/


module max_pool_packet_collector #(
    parameter integer feature_n_per_clk = 4, // 每个clk输入的特征点数量(2 | 4 | 8 | 16 | ...)
	parameter integer feature_data_width = 8, // 特征点位宽(必须能被8整除, 且>0)
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 数据收集单元输入
	input wire[(feature_n_per_clk+1)*feature_data_width-1:0] s_axis_data,
	input wire[(feature_n_per_clk+1)*feature_data_width/8-1:0] s_axis_keep,
	input wire s_axis_last, // 指示最后1个特征组
	input wire s_axis_valid,
	output wire s_axis_ready,
	
	// 数据收集单元输出
	output wire[feature_n_per_clk*feature_data_width-1:0] m_axis_data,
	output wire[feature_n_per_clk*feature_data_width/8-1:0] m_axis_keep,
	output wire m_axis_last, // 指示输出特征图的最后1组数据
	output wire m_axis_valid,
	input wire m_axis_ready
);
    
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
        for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
			bit_depth = bit_depth >> 1;
    end
    endfunction
	
	// 计算数据中1的个数
    function integer count1_of_integer(input integer data, input integer data_width);
        integer i;
    begin
        count1_of_integer = 0;
        
        for(i = 0;i < data_width;i = i + 1)
			count1_of_integer = count1_of_integer + data[i];
    end
	endfunction
	
	/** 常量 **/
	localparam integer in_stream_data_width = (feature_n_per_clk+1)*feature_data_width; // 输入特征数据流位宽
	localparam integer out_stream_data_width = feature_n_per_clk*feature_data_width; // 输出特征数据流位宽
	
	/** 特征数据输入 **/
	wire[feature_n_per_clk:0] in_feature_item_mask; // 输入特征项有效掩码
	wire[clogb2(feature_n_per_clk+1):0] in_feature_vld_item_n; // 输入特征数据的有效项数
	
	genvar in_feature_item_mask_i;
	generate
		for(in_feature_item_mask_i = 0;in_feature_item_mask_i < feature_n_per_clk + 1;
			in_feature_item_mask_i = in_feature_item_mask_i + 1)
		begin
			assign in_feature_item_mask[in_feature_item_mask_i] = s_axis_keep[in_feature_item_mask_i*feature_data_width/8];
		end
	endgenerate
	
	assign in_feature_vld_item_n = count1_of_integer(in_feature_item_mask, feature_n_per_clk + 1);
	
	/**
	缓存寄存器区
	
	缓存2组特征图数据(域#1, 域#0)
	
	写位宽 = (feature_n_per_clk + 1)个特征项
	读位宽 = feature_n_per_clk个特征项
	**/
	// 寄存器缓存
	reg[feature_data_width-1:0] feature_data_buffer[0:feature_n_per_clk*2-1]; // 特征数据缓存
	reg[feature_n_per_clk*2-1:0] feature_keep_buffer; // 特征项使能缓存
	reg[feature_n_per_clk*2-1:0] feature_last_buffer; // 最后1组特征数据标志缓存
    // 缓存区写端口
	wire feature_buffer_wen; // 缓存区写使能
	wire feature_buffer_full_n; // 缓存区满标志
	reg[clogb2(feature_n_per_clk*2-1):0] feature_buffer_item_ptr_cur; // 当前缓存区写特征项指针
	wire[clogb2(feature_n_per_clk*2-1):0] feature_buffer_item_ptr_nxt; // 下一缓存区写特征项指针
	wire[feature_n_per_clk*2-1:0] feature_buffer_item_upd_en; // 缓存区特征项更新使能向量
	wire[feature_n_per_clk*2*feature_data_width-1:0] feature_buffer_new_data; // 缓存区待载入的特征数据
	wire[feature_n_per_clk*2-1:0] feature_buffer_new_keep; // 缓存区待载入的特征项使能
	wire[feature_n_per_clk*2-1:0] feature_buffer_new_last; // 缓存区待载入的最后1组特征数据标志
	wire feature_to_load_cross_region; // 即将载入的数据跨越缓存区域(标志)
	wire[feature_n_per_clk*2-1:0] cross_region_filling_mask; // 跨域填充掩码
	wire[feature_n_per_clk-1:0] reserve_mask; // 未跨域保留掩码
	wire[clogb2(feature_n_per_clk*2):0] feature_item_n_to_load; // 即将载入的特征项个数
	// 缓冲区读端口
	wire feature_buffer_ren; // 缓存区读使能
	wire feature_buffer_empty_n; // 缓存区空标志
	reg feature_buffer_rptr; // 缓存区读指针
	// 缓存区存储项计数
	reg[clogb2(feature_n_per_clk*2):0] feature_buffer_item_cnt_cur; // 当前存储项计数
	wire[clogb2(feature_n_per_clk*2):0] feature_buffer_item_cnt_nxt; // 下一存储项计数
	
	// 特征数据输入AXIS接口
	assign s_axis_ready = feature_buffer_full_n;
	
	// 缓存区写使能
	assign feature_buffer_wen = s_axis_valid;
	// 缓存区满标志
	assign feature_buffer_full_n = (feature_buffer_item_cnt_cur + feature_item_n_to_load) <= 
		((feature_buffer_ren & feature_buffer_empty_n) ? (feature_n_per_clk * 3):(feature_n_per_clk * 2));
	// 缓存区空标志
	assign feature_buffer_empty_n = feature_buffer_item_cnt_cur >= feature_n_per_clk;
	
	// 下一缓存区写特征项指针
	assign feature_buffer_item_ptr_nxt = s_axis_last ? 
		// feature_to_load_cross_region ? feature_buffer_item_ptr_cur[clogb2(feature_n_per_clk*2-1)]:
		//     (~feature_buffer_item_ptr_cur[clogb2(feature_n_per_clk*2-1)])
		{(~feature_to_load_cross_region) ^ feature_buffer_item_ptr_cur[clogb2(feature_n_per_clk*2-1)],
			{clogb2(feature_n_per_clk*2-1){1'b0}}}:
		(feature_buffer_item_ptr_cur + in_feature_vld_item_n);
	
	// 缓存区特征项更新使能向量
	assign feature_buffer_item_upd_en = 
		({{(feature_n_per_clk-1){1'b0}}, in_feature_item_mask} << feature_buffer_item_ptr_cur)
		| ({{(feature_n_per_clk-1){1'b0}}, in_feature_item_mask} 
			>> (feature_n_per_clk*2-feature_buffer_item_ptr_cur)) // 循环左移(共有feature_n_per_clk*2种情况)
		| ({(feature_n_per_clk*2){s_axis_last}} 
			// feature_to_load_cross_region ? cross_region_filling_mask:(~cross_region_filling_mask)
			& ({(feature_n_per_clk*2){~feature_to_load_cross_region}} ^ cross_region_filling_mask)
			& {2{~reserve_mask}}); // 填充最后1组数据
	
	// 缓存区待载入的负载
	assign feature_buffer_new_data = 
		({{((feature_n_per_clk-1)*feature_data_width){1'bx}}, s_axis_data} << (feature_buffer_item_ptr_cur*feature_data_width))
		| ({{((feature_n_per_clk-1)*feature_data_width){1'bx}}, s_axis_data} 
			>> ((feature_n_per_clk*2-feature_buffer_item_ptr_cur)*feature_data_width)); // 循环左移(共有feature_n_per_clk*2种情况)
	assign feature_buffer_new_keep = 
		({{(feature_n_per_clk-1){1'b0}}, in_feature_item_mask} << feature_buffer_item_ptr_cur)
		| ({{(feature_n_per_clk-1){1'b0}}, in_feature_item_mask} 
			>> (feature_n_per_clk*2-feature_buffer_item_ptr_cur)); // 循环左移(共有feature_n_per_clk*2种情况)
	assign feature_buffer_new_last = 
		{(feature_n_per_clk*2){s_axis_last}} 
			// feature_to_load_cross_region ? cross_region_filling_mask:(~cross_region_filling_mask)
			& ({(feature_n_per_clk*2){~feature_to_load_cross_region}} ^ cross_region_filling_mask);
	
	// 跨域填充
	assign feature_to_load_cross_region = feature_buffer_item_ptr_cur[clogb2(feature_n_per_clk*2-1)-1:0] + in_feature_vld_item_n
		> feature_n_per_clk;
	assign cross_region_filling_mask = {
		{feature_n_per_clk{~feature_buffer_item_ptr_cur[clogb2(feature_n_per_clk*2-1)]}}, // 从域#0跨越到域#1
		{feature_n_per_clk{feature_buffer_item_ptr_cur[clogb2(feature_n_per_clk*2-1)]}} // 从域#1跨越到域#0
	};
	// 未跨域保留掩码
	genvar reserve_mask_i;
	generate
		for(reserve_mask_i = 0;reserve_mask_i < feature_n_per_clk;reserve_mask_i = reserve_mask_i + 1)
		begin
			assign reserve_mask[reserve_mask_i] = 
				feature_buffer_item_ptr_cur[clogb2(feature_n_per_clk*2-1)-1:0] > reserve_mask_i;
		end
	endgenerate
	
	// 即将载入的特征项个数
	assign feature_item_n_to_load = s_axis_last ? 
		// (feature_to_load_cross_region ? feature_n_per_clk * 2:feature_n_per_clk)
		//     - feature_buffer_item_ptr_cur[clogb2(feature_n_per_clk*2-1)-1:0]
		((feature_n_per_clk << feature_to_load_cross_region) - feature_buffer_item_ptr_cur[clogb2(feature_n_per_clk*2-1)-1:0]):
		in_feature_vld_item_n;
	
	// 下一存储项计数
	assign feature_buffer_item_cnt_nxt = feature_buffer_item_cnt_cur + 
		((feature_buffer_wen & feature_buffer_full_n) ? feature_item_n_to_load:0) - 
		((feature_buffer_ren & feature_buffer_empty_n) ? feature_n_per_clk:0);
	
	// 当前缓存区写特征项指针
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			feature_buffer_item_ptr_cur <= 0;
		else if(feature_buffer_wen & feature_buffer_full_n)
			feature_buffer_item_ptr_cur <= # simulation_delay feature_buffer_item_ptr_nxt;
	end
	
	// 寄存器缓存
	genvar feature_buffer_i;
	generate
		for(feature_buffer_i = 0;feature_buffer_i < feature_n_per_clk*2;feature_buffer_i = feature_buffer_i + 1)
		begin
			always @(posedge clk)
			begin
				if(feature_buffer_wen & feature_buffer_full_n & feature_buffer_item_upd_en[feature_buffer_i])
					feature_data_buffer[feature_buffer_i] <= # simulation_delay 
						feature_buffer_new_data[(feature_buffer_i+1)*feature_data_width-1:feature_buffer_i*feature_data_width];
			end
			
			always @(posedge clk)
			begin
				if(feature_buffer_wen & feature_buffer_full_n & feature_buffer_item_upd_en[feature_buffer_i])
					feature_keep_buffer[feature_buffer_i] <= # simulation_delay feature_buffer_new_keep[feature_buffer_i];
			end
			
			always @(posedge clk)
			begin
				if(feature_buffer_wen & feature_buffer_full_n & feature_buffer_item_upd_en[feature_buffer_i])
					feature_last_buffer[feature_buffer_i] <= # simulation_delay feature_buffer_new_last[feature_buffer_i];
			end
		end
	endgenerate
	
	// 当前存储项计数
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			feature_buffer_item_cnt_cur <= 0;
		else if((feature_buffer_wen & feature_buffer_full_n) | (feature_buffer_ren & feature_buffer_empty_n))
			feature_buffer_item_cnt_cur <= # simulation_delay feature_buffer_item_cnt_nxt;
	end
	
	// 缓存区读指针
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			feature_buffer_rptr <= 1'b0;
		else if(feature_buffer_ren & feature_buffer_empty_n)
			feature_buffer_rptr <= # simulation_delay ~feature_buffer_rptr;
	end
	
	/** 特征数据输出 **/
	genvar m_axis_data_i;
	generate
		for(m_axis_data_i = 0;m_axis_data_i < feature_n_per_clk;m_axis_data_i = m_axis_data_i + 1)
		begin
			assign m_axis_data[(m_axis_data_i+1)*feature_data_width-1:m_axis_data_i*feature_data_width] = 
				feature_buffer_rptr ? feature_data_buffer[feature_n_per_clk+m_axis_data_i]:
					feature_data_buffer[m_axis_data_i];
		end
	endgenerate
	
	genvar m_axis_keep_i;
	generate
		for(m_axis_keep_i = 0;m_axis_keep_i < feature_n_per_clk;m_axis_keep_i = m_axis_keep_i + 1)
		begin
			assign m_axis_keep[(m_axis_keep_i+1)*feature_data_width/8-1:m_axis_keep_i*feature_data_width/8] = 
				{(feature_data_width/8){feature_buffer_rptr ? feature_keep_buffer[feature_n_per_clk+m_axis_keep_i]:
					feature_keep_buffer[m_axis_keep_i]}};
		end
	endgenerate
	
	assign m_axis_last = feature_buffer_rptr ? 
		feature_last_buffer[feature_n_per_clk*2-1]:feature_last_buffer[feature_n_per_clk-1];
	assign m_axis_valid = feature_buffer_empty_n;
	
	// 缓存区读使能
	assign feature_buffer_ren = m_axis_ready;
	
endmodule
