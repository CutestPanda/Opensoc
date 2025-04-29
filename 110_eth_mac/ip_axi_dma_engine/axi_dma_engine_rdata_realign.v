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
本模块: AXI通用DMA引擎读数据重对齐

描述:
根据每个读数据包的首个数据的keep掩码, 对读数据作字节级别的重新对齐处理

data D3 D2 D1 D0  |  D7 D6 D5 D4    --->    D5 D4 D3 D2  |  X X D7 D6
keep  1  1  0  0  |   0  1  1  1    --->     1  1  1  1  |  0 0  0  1

注意：
无

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/01/28
********************************************************************/


module axi_dma_engine_rdata_realign #(
	parameter integer DATA_WIDTH = 32, // 传输数据位宽(32 | 64 | 128 | 256)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 输出数据流AXIS接口的时钟和复位
	input wire axis_aclk,
	input wire axis_aresetn,
	
	// 输出数据流AXIS从机
	input wire[DATA_WIDTH-1:0] s_mm2s_axis_data,
	input wire[DATA_WIDTH/8-1:0] s_mm2s_axis_keep,
	input wire s_mm2s_axis_last,
	input wire s_mm2s_axis_valid,
	output wire s_mm2s_axis_ready,
	
	// 输出数据流AXIS主机
	output wire[DATA_WIDTH-1:0] m_mm2s_axis_data,
	output wire[DATA_WIDTH/8-1:0] m_mm2s_axis_keep,
	output wire m_mm2s_axis_last,
	output wire m_mm2s_axis_valid,
	input wire m_mm2s_axis_ready
);
	
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
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
	
	/** 输出寄存器片 **/
	// 寄存器片AXIS从机
    wire[DATA_WIDTH-1:0] s_reg_slice_axis_data;
	wire[DATA_WIDTH/8-1:0] s_reg_slice_axis_keep;
	wire s_reg_slice_axis_last;
	wire s_reg_slice_axis_valid;
	wire s_reg_slice_axis_ready;
    // 寄存器片AXIS主机
    wire[DATA_WIDTH-1:0] m_reg_slice_axis_data;
	wire[DATA_WIDTH/8-1:0] m_reg_slice_axis_keep;
	wire m_reg_slice_axis_last;
	wire m_reg_slice_axis_valid;
	wire m_reg_slice_axis_ready;
	
	assign m_mm2s_axis_data = m_reg_slice_axis_data;
	assign m_mm2s_axis_keep = m_reg_slice_axis_keep;
	assign m_mm2s_axis_last = m_reg_slice_axis_last;
	assign m_mm2s_axis_valid = m_reg_slice_axis_valid;
	assign m_reg_slice_axis_ready = m_mm2s_axis_ready;
	
	axis_reg_slice #(
		.data_width(DATA_WIDTH),
		.user_width(1),
		.forward_registered("true"),
		.back_registered("false"),
		.en_ready("true"),
		.simulation_delay(SIM_DELAY)
	)out_reg_slice_u(
		.clk(axis_aclk),
		.rst_n(axis_aresetn),
		
		.s_axis_data(s_reg_slice_axis_data),
		.s_axis_keep(s_reg_slice_axis_keep),
		.s_axis_user(1'bx),
		.s_axis_last(s_reg_slice_axis_last),
		.s_axis_valid(s_reg_slice_axis_valid),
		.s_axis_ready(s_reg_slice_axis_ready),
		
		.m_axis_data(m_reg_slice_axis_data),
		.m_axis_keep(m_reg_slice_axis_keep),
		.m_axis_user(),
		.m_axis_last(m_reg_slice_axis_last),
		.m_axis_valid(m_reg_slice_axis_valid),
		.m_axis_ready(m_reg_slice_axis_ready)
	);
	
	/** 读数据重对齐 **/
	reg first_trans_to_reorg; // 第1个待整理传输(标志)
	wire last_trans_to_reorg; // 最后1个待整理传输(标志)
	reg to_flush_reorg_buffer; // 冲刷拼接缓存区(标志)
	reg[clogb2(DATA_WIDTH/8-1):0] reorg_method; // 拼接方式
	wire[clogb2(DATA_WIDTH/8-1):0] reorg_method_nxt; // 新的拼接方式
	reg[DATA_WIDTH/8-1:0] flush_keep_mask; // 冲刷时的keep掩码
	reg[DATA_WIDTH/8-1:0] reorg_first_keep; // 第1个字节有效掩码
	reg[DATA_WIDTH-1:0] data_reorg_buffer; // 拼接缓存区(数据)
	reg[DATA_WIDTH/8-1:0] keep_reorg_buffer; // 拼接缓存区(字节有效掩码)
	wire reorg_pkt_only_one_trans; // 待整理数据包仅包含1个传输(标志)
	wire[DATA_WIDTH/8-2:0] keep_pattern_vec; // keep掩码模式向量
	
	// 握手条件: (~to_flush_reorg_buffer) & s_mm2s_axis_valid & s_reg_slice_axis_ready
	assign s_mm2s_axis_ready = (~to_flush_reorg_buffer) & s_reg_slice_axis_ready;
	
	assign s_reg_slice_axis_data = reorg_pkt_only_one_trans ? 
		// 本次突发只有1个传输, 将有效字节对齐到最右边后输出, 共有(DATA_WIDTH/8)种情况
		((s_mm2s_axis_data >> (reorg_method_nxt * 8)) | ({DATA_WIDTH{1'bx}} << (DATA_WIDTH - reorg_method_nxt * 8))):
		// 根据拼接方式, 合并拼接缓存区和当前数据, 共有(DATA_WIDTH/8)种情况
		((data_reorg_buffer >> (reorg_method * 8)) | (s_mm2s_axis_data << (DATA_WIDTH - reorg_method * 8)));
	assign s_reg_slice_axis_keep = 
		// 冲刷拼接缓存区时需要根据第1个输入数据的keep取掩码
		(flush_keep_mask | {(DATA_WIDTH/8){~to_flush_reorg_buffer}}) &
		// 本次突发只有1个传输, 将keep信号对齐到LSB后输出, 共有(DATA_WIDTH/8)种情况
		(reorg_pkt_only_one_trans ? (s_mm2s_axis_keep >> reorg_method_nxt):
			// 根据拼接方式, 合并拼接缓存区和当前keep信号, 共有(DATA_WIDTH/8)种情况
			((keep_reorg_buffer >> reorg_method) | (s_mm2s_axis_keep << ({1'b1, {clogb2(DATA_WIDTH/8){1'b0}}} - {1'b0, reorg_method}))));
	assign s_reg_slice_axis_last = to_flush_reorg_buffer | 
		// 如果对最后1个输入数据取掩码后没有有效字节, 那么无需冲刷拼接缓存区, 当前就是最后1个输出数据
		((first_trans_to_reorg | (~(|(s_mm2s_axis_keep & reorg_first_keep)))) & last_trans_to_reorg);
	// 握手条件: (to_flush_reorg_buffer & s_reg_slice_axis_ready) | 
	//     (s_mm2s_axis_valid & s_reg_slice_axis_ready & (~(first_trans_to_reorg & (~last_trans_to_reorg))))
	assign s_reg_slice_axis_valid = to_flush_reorg_buffer | 
		(s_mm2s_axis_valid & (~(first_trans_to_reorg & (~last_trans_to_reorg))));
    
	assign last_trans_to_reorg = s_mm2s_axis_last;
	// 生成拼接方式
	assign reorg_method_nxt = count1_of_integer(~keep_pattern_vec, DATA_WIDTH/8-1);
	assign reorg_pkt_only_one_trans = first_trans_to_reorg & last_trans_to_reorg & (~to_flush_reorg_buffer);
	
	// keep掩码模式向量
	genvar keep_pattern_vec_i;
	generate
		for(keep_pattern_vec_i = 0;keep_pattern_vec_i < DATA_WIDTH/8-1;keep_pattern_vec_i = keep_pattern_vec_i + 1)
		begin
			assign keep_pattern_vec[keep_pattern_vec_i] = |s_mm2s_axis_keep[DATA_WIDTH/8-2-keep_pattern_vec_i:0];
		end
	endgenerate
	
	// 第1个待整理传输(标志)
	always @(posedge axis_aclk or negedge axis_aresetn)
	begin
		if(~axis_aresetn)
			first_trans_to_reorg <= 1'b1;
		else if(s_mm2s_axis_valid & s_mm2s_axis_ready)
			first_trans_to_reorg <= # SIM_DELAY last_trans_to_reorg;
	end
	
	// 冲刷拼接缓存区(标志)
	always @(posedge axis_aclk or negedge axis_aresetn)
	begin
		if(~axis_aresetn)
			to_flush_reorg_buffer <= 1'b0;
		else
			to_flush_reorg_buffer <= # SIM_DELAY 
				to_flush_reorg_buffer ? (~s_reg_slice_axis_ready):
					(s_mm2s_axis_valid & s_reg_slice_axis_ready & 
					// 如果对最后1个输入数据取掩码后没有有效字节, 那么无需冲刷拼接缓存区
					(~first_trans_to_reorg) & last_trans_to_reorg & (|(s_mm2s_axis_keep & reorg_first_keep)));
	end
	
	// 拼接方式
	always @(posedge axis_aclk)
	begin
		if(s_mm2s_axis_valid & s_mm2s_axis_ready & first_trans_to_reorg)
			reorg_method <= # SIM_DELAY reorg_method_nxt;
	end
	// 冲刷时的keep掩码
	genvar flush_keep_mask_i;
	generate
		for(flush_keep_mask_i = 0;flush_keep_mask_i < DATA_WIDTH/8;flush_keep_mask_i = flush_keep_mask_i + 1)
		begin
			always @(posedge axis_aclk)
			begin
				if(s_mm2s_axis_valid & s_mm2s_axis_ready & first_trans_to_reorg)
					flush_keep_mask[flush_keep_mask_i] <= # SIM_DELAY 
						(flush_keep_mask_i == 0) | 
						(|s_mm2s_axis_keep[DATA_WIDTH/8-1-flush_keep_mask_i:0]);
			end
		end
	endgenerate
	// 第1个字节有效掩码
	always @(posedge axis_aclk)
	begin
		if(s_mm2s_axis_valid & s_mm2s_axis_ready & first_trans_to_reorg)
			reorg_first_keep <= # SIM_DELAY s_mm2s_axis_keep;
	end
	
	// 拼接缓存区(数据)
	always @(posedge axis_aclk)
	begin
		if(s_mm2s_axis_valid & s_mm2s_axis_ready)
			data_reorg_buffer <= # SIM_DELAY s_mm2s_axis_data;
	end
	// 拼接缓存区(字节有效掩码)
	always @(posedge axis_aclk)
	begin
		if(s_mm2s_axis_valid & s_mm2s_axis_ready)
			keep_reorg_buffer <= # SIM_DELAY s_mm2s_axis_keep;
	end
	
endmodule
