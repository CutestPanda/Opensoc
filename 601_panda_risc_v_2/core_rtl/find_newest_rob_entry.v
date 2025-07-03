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
本模块: 查找最新的ROB条目

描述:
对重排序队列某些条目记录的写指针进行比较(是否比较通过掩码来控制), 使用比较树得到最新项的编号和数据

 写指针翻转位是否相同 |   比较方法
------------------------------
       Y        | 编号位越大则越新
	   N        | 编号位越小则越新

注意：
对于比较掩码中的每1位, 为0时表示无需比较

协议:
无

作者: 陈家耀
日期: 2025/06/18
********************************************************************/


module find_newest_rob_entry #(
	parameter integer ROB_PAYLOAD_WIDTH = 32, // 重排序队列数据位宽(正整数)
	parameter integer ROB_ENTRY_N = 8 // 重排序队列项数(4 | 8 | 16 | 32)
)(
	input wire[ROB_ENTRY_N*6-1:0] wptr_recorded, // 记录的写指针
	input wire[ROB_ENTRY_N*ROB_PAYLOAD_WIDTH-1:0] rob_payload, // 负载数据
	input wire[ROB_ENTRY_N-1:0] cmp_mask, // 比较掩码
	
	output wire[4:0] newest_entry_i, // 最新项的编号
	output wire[ROB_PAYLOAD_WIDTH-1:0] newest_entry_payload // 最新项的数据
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
	
	/** 第1级比较(32 -> 16) **/
	wire[5:0] cmp_stage1_i_wptr[0:31];
	wire cmp_stage1_i_mask[0:31];
	wire[ROB_PAYLOAD_WIDTH-1:0] cmp_stage1_i_data[0:31];
	wire[5:0] cmp_stage1_o_wptr[0:15];
	wire cmp_stage1_o_mask[0:15];
	wire[ROB_PAYLOAD_WIDTH-1:0] cmp_stage1_o_data[0:15];
	
	genvar stage1_i;
	generate
		for(stage1_i = 0;stage1_i < 32;stage1_i = stage1_i + 1)
		begin:cmp_stage1_blk
			if(ROB_ENTRY_N == 32)
			begin
				assign cmp_stage1_i_wptr[stage1_i] = wptr_recorded[(stage1_i+1)*6-1:stage1_i*6];
				assign cmp_stage1_i_mask[stage1_i] = cmp_mask[stage1_i];
				assign cmp_stage1_i_data[stage1_i] = rob_payload[(stage1_i+1)*ROB_PAYLOAD_WIDTH-1:stage1_i*ROB_PAYLOAD_WIDTH];
			end
			else
			begin
				assign cmp_stage1_i_wptr[stage1_i] = 6'dx;
				assign cmp_stage1_i_mask[stage1_i] = 1'bx;
				assign cmp_stage1_i_data[stage1_i] = {ROB_PAYLOAD_WIDTH{1'bx}};
			end
			
			if(stage1_i < 16)
			begin
				assign cmp_stage1_o_wptr[stage1_i] = 
					((~cmp_stage1_i_mask[stage1_i*2]) | (~cmp_stage1_i_mask[stage1_i*2+1])) ? 
						(
							cmp_stage1_i_mask[stage1_i*2] ? 
								cmp_stage1_i_wptr[stage1_i*2]:
								cmp_stage1_i_wptr[stage1_i*2+1]
						):(
							(
								(cmp_stage1_i_wptr[stage1_i*2][5] ^ cmp_stage1_i_wptr[stage1_i*2+1][5]) ^ 
								(cmp_stage1_i_wptr[stage1_i*2][4:0] > cmp_stage1_i_wptr[stage1_i*2+1][4:0])
							) ? 
								cmp_stage1_i_wptr[stage1_i*2]:
								cmp_stage1_i_wptr[stage1_i*2+1]
						);
				assign cmp_stage1_o_mask[stage1_i] = 
					cmp_stage1_i_mask[stage1_i*2] | cmp_stage1_i_mask[stage1_i*2+1];
				assign cmp_stage1_o_data[stage1_i] = 
					((~cmp_stage1_i_mask[stage1_i*2]) | (~cmp_stage1_i_mask[stage1_i*2+1])) ? 
						(
							cmp_stage1_i_mask[stage1_i*2] ? 
								cmp_stage1_i_data[stage1_i*2]:
								cmp_stage1_i_data[stage1_i*2+1]
						):(
							(
								(cmp_stage1_i_wptr[stage1_i*2][5] ^ cmp_stage1_i_wptr[stage1_i*2+1][5]) ^ 
								(cmp_stage1_i_wptr[stage1_i*2][4:0] > cmp_stage1_i_wptr[stage1_i*2+1][4:0])
							) ? 
								cmp_stage1_i_data[stage1_i*2]:
								cmp_stage1_i_data[stage1_i*2+1]
						);
			end
		end
	endgenerate
	
	/** 第2级比较(16 -> 8) **/
	wire[5:0] cmp_stage2_i_wptr[0:15];
	wire cmp_stage2_i_mask[0:15];
	wire[ROB_PAYLOAD_WIDTH-1:0] cmp_stage2_i_data[0:15];
	wire[5:0] cmp_stage2_o_wptr[0:7];
	wire cmp_stage2_o_mask[0:7];
	wire[ROB_PAYLOAD_WIDTH-1:0] cmp_stage2_o_data[0:7];
	
	genvar stage2_i;
	generate
		for(stage2_i = 0;stage2_i < 16;stage2_i = stage2_i + 1)
		begin:cmp_stage2_blk
			if(ROB_ENTRY_N == 16)
			begin
				assign cmp_stage2_i_wptr[stage2_i] = wptr_recorded[(stage2_i+1)*6-1:stage2_i*6];
				assign cmp_stage2_i_mask[stage2_i] = cmp_mask[stage2_i];
				assign cmp_stage2_i_data[stage2_i] = rob_payload[(stage2_i+1)*ROB_PAYLOAD_WIDTH-1:stage2_i*ROB_PAYLOAD_WIDTH];
			end
			else
			begin
				assign cmp_stage2_i_wptr[stage2_i] = cmp_stage1_o_wptr[stage2_i];
				assign cmp_stage2_i_mask[stage2_i] = cmp_stage1_o_mask[stage2_i];
				assign cmp_stage2_i_data[stage2_i] = cmp_stage1_o_data[stage2_i];
			end
			
			if(stage2_i < 8)
			begin
				assign cmp_stage2_o_wptr[stage2_i] = 
					((~cmp_stage2_i_mask[stage2_i*2]) | (~cmp_stage2_i_mask[stage2_i*2+1])) ? 
						(
							cmp_stage2_i_mask[stage2_i*2] ? 
								cmp_stage2_i_wptr[stage2_i*2]:
								cmp_stage2_i_wptr[stage2_i*2+1]
						):(
							(
								(cmp_stage2_i_wptr[stage2_i*2][5] ^ cmp_stage2_i_wptr[stage2_i*2+1][5]) ^ 
								(cmp_stage2_i_wptr[stage2_i*2][4:0] > cmp_stage2_i_wptr[stage2_i*2+1][4:0])
							) ? 
								cmp_stage2_i_wptr[stage2_i*2]:
								cmp_stage2_i_wptr[stage2_i*2+1]
						);
				assign cmp_stage2_o_mask[stage2_i] = 
					cmp_stage2_i_mask[stage2_i*2] | cmp_stage2_i_mask[stage2_i*2+1];
				assign cmp_stage2_o_data[stage2_i] = 
					((~cmp_stage2_i_mask[stage2_i*2]) | (~cmp_stage2_i_mask[stage2_i*2+1])) ? 
						(
							cmp_stage2_i_mask[stage2_i*2] ? 
								cmp_stage2_i_data[stage2_i*2]:
								cmp_stage2_i_data[stage2_i*2+1]
						):(
							(
								(cmp_stage2_i_wptr[stage2_i*2][5] ^ cmp_stage2_i_wptr[stage2_i*2+1][5]) ^ 
								(cmp_stage2_i_wptr[stage2_i*2][4:0] > cmp_stage2_i_wptr[stage2_i*2+1][4:0])
							) ? 
								cmp_stage2_i_data[stage2_i*2]:
								cmp_stage2_i_data[stage2_i*2+1]
						);
			end
		end
	endgenerate
	
	/** 第3级比较(8 -> 4) **/
	wire[5:0] cmp_stage3_i_wptr[0:7];
	wire cmp_stage3_i_mask[0:7];
	wire[ROB_PAYLOAD_WIDTH-1:0] cmp_stage3_i_data[0:7];
	wire[5:0] cmp_stage3_o_wptr[0:3];
	wire cmp_stage3_o_mask[0:3];
	wire[ROB_PAYLOAD_WIDTH-1:0] cmp_stage3_o_data[0:3];
	
	genvar stage3_i;
	generate
		for(stage3_i = 0;stage3_i < 8;stage3_i = stage3_i + 1)
		begin:cmp_stage3_blk
			if(ROB_ENTRY_N == 8)
			begin
				assign cmp_stage3_i_wptr[stage3_i] = wptr_recorded[(stage3_i+1)*6-1:stage3_i*6];
				assign cmp_stage3_i_mask[stage3_i] = cmp_mask[stage3_i];
				assign cmp_stage3_i_data[stage3_i] = rob_payload[(stage3_i+1)*ROB_PAYLOAD_WIDTH-1:stage3_i*ROB_PAYLOAD_WIDTH];
			end
			else
			begin
				assign cmp_stage3_i_wptr[stage3_i] = cmp_stage2_o_wptr[stage3_i];
				assign cmp_stage3_i_mask[stage3_i] = cmp_stage2_o_mask[stage3_i];
				assign cmp_stage3_i_data[stage3_i] = cmp_stage2_o_data[stage3_i];
			end
			
			if(stage3_i < 4)
			begin
				assign cmp_stage3_o_wptr[stage3_i] = 
					((~cmp_stage3_i_mask[stage3_i*2]) | (~cmp_stage3_i_mask[stage3_i*2+1])) ? 
						(
							cmp_stage3_i_mask[stage3_i*2] ? 
								cmp_stage3_i_wptr[stage3_i*2]:
								cmp_stage3_i_wptr[stage3_i*2+1]
						):(
							(
								(cmp_stage3_i_wptr[stage3_i*2][5] ^ cmp_stage3_i_wptr[stage3_i*2+1][5]) ^ 
								(cmp_stage3_i_wptr[stage3_i*2][4:0] > cmp_stage3_i_wptr[stage3_i*2+1][4:0])
							) ? 
								cmp_stage3_i_wptr[stage3_i*2]:
								cmp_stage3_i_wptr[stage3_i*2+1]
						);
				assign cmp_stage3_o_mask[stage3_i] = 
					cmp_stage3_i_mask[stage3_i*2] | cmp_stage3_i_mask[stage3_i*2+1];
				assign cmp_stage3_o_data[stage3_i] = 
					((~cmp_stage3_i_mask[stage3_i*2]) | (~cmp_stage3_i_mask[stage3_i*2+1])) ? 
						(
							cmp_stage3_i_mask[stage3_i*2] ? 
								cmp_stage3_i_data[stage3_i*2]:
								cmp_stage3_i_data[stage3_i*2+1]
						):(
							(
								(cmp_stage3_i_wptr[stage3_i*2][5] ^ cmp_stage3_i_wptr[stage3_i*2+1][5]) ^ 
								(cmp_stage3_i_wptr[stage3_i*2][4:0] > cmp_stage3_i_wptr[stage3_i*2+1][4:0])
							) ? 
								cmp_stage3_i_data[stage3_i*2]:
								cmp_stage3_i_data[stage3_i*2+1]
						);
			end
		end
	endgenerate
	
	/** 第4级比较(4 -> 2) **/
	wire[5:0] cmp_stage4_i_wptr[0:3];
	wire cmp_stage4_i_mask[0:3];
	wire[ROB_PAYLOAD_WIDTH-1:0] cmp_stage4_i_data[0:3];
	wire[5:0] cmp_stage4_o_wptr[0:1];
	wire cmp_stage4_o_mask[0:1];
	wire[ROB_PAYLOAD_WIDTH-1:0] cmp_stage4_o_data[0:1];
	
	genvar stage4_i;
	generate
		for(stage4_i = 0;stage4_i < 4;stage4_i = stage4_i + 1)
		begin:cmp_stage4_blk
			if(ROB_ENTRY_N == 4)
			begin
				assign cmp_stage4_i_wptr[stage4_i] = wptr_recorded[(stage4_i+1)*6-1:stage4_i*6];
				assign cmp_stage4_i_mask[stage4_i] = cmp_mask[stage4_i];
				assign cmp_stage4_i_data[stage4_i] = rob_payload[(stage4_i+1)*ROB_PAYLOAD_WIDTH-1:stage4_i*ROB_PAYLOAD_WIDTH];
			end
			else
			begin
				assign cmp_stage4_i_wptr[stage4_i] = cmp_stage3_o_wptr[stage4_i];
				assign cmp_stage4_i_mask[stage4_i] = cmp_stage3_o_mask[stage4_i];
				assign cmp_stage4_i_data[stage4_i] = cmp_stage3_o_data[stage4_i];
			end
			
			if(stage4_i < 2)
			begin
				assign cmp_stage4_o_wptr[stage4_i] = 
					((~cmp_stage4_i_mask[stage4_i*2]) | (~cmp_stage4_i_mask[stage4_i*2+1])) ? 
						(
							cmp_stage4_i_mask[stage4_i*2] ? 
								cmp_stage4_i_wptr[stage4_i*2]:
								cmp_stage4_i_wptr[stage4_i*2+1]
						):(
							(
								(cmp_stage4_i_wptr[stage4_i*2][5] ^ cmp_stage4_i_wptr[stage4_i*2+1][5]) ^ 
								(cmp_stage4_i_wptr[stage4_i*2][4:0] > cmp_stage4_i_wptr[stage4_i*2+1][4:0])
							) ? 
								cmp_stage4_i_wptr[stage4_i*2]:
								cmp_stage4_i_wptr[stage4_i*2+1]
						);
				assign cmp_stage4_o_mask[stage4_i] = 
					cmp_stage4_i_mask[stage4_i*2] | cmp_stage4_i_mask[stage4_i*2+1];
				assign cmp_stage4_o_data[stage4_i] = 
					((~cmp_stage4_i_mask[stage4_i*2]) | (~cmp_stage4_i_mask[stage4_i*2+1])) ? 
						(
							cmp_stage4_i_mask[stage4_i*2] ? 
								cmp_stage4_i_data[stage4_i*2]:
								cmp_stage4_i_data[stage4_i*2+1]
						):(
							(
								(cmp_stage4_i_wptr[stage4_i*2][5] ^ cmp_stage4_i_wptr[stage4_i*2+1][5]) ^ 
								(cmp_stage4_i_wptr[stage4_i*2][4:0] > cmp_stage4_i_wptr[stage4_i*2+1][4:0])
							) ? 
								cmp_stage4_i_data[stage4_i*2]:
								cmp_stage4_i_data[stage4_i*2+1]
						);
			end
		end
	endgenerate
	
	/** 第5级比较(2 -> 1) **/
	wire[5:0] cmp_stage5_i_wptr[0:1];
	wire cmp_stage5_i_mask[0:1];
	wire[ROB_PAYLOAD_WIDTH-1:0] cmp_stage5_i_data[0:1];
	wire[5:0] cmp_stage5_o_wptr;
	wire cmp_stage5_o_mask;
	wire[ROB_PAYLOAD_WIDTH-1:0] cmp_stage5_o_data;
	
	assign cmp_stage5_i_wptr[0] = cmp_stage4_o_wptr[0];
	assign cmp_stage5_i_wptr[1] = cmp_stage4_o_wptr[1];
	
	assign cmp_stage5_i_mask[0] = cmp_stage4_o_mask[0];
	assign cmp_stage5_i_mask[1] = cmp_stage4_o_mask[1];
	
	assign cmp_stage5_i_data[0] = cmp_stage4_o_data[0];
	assign cmp_stage5_i_data[1] = cmp_stage4_o_data[1];
	
	assign cmp_stage5_o_wptr = 
		((~cmp_stage5_i_mask[0]) | (~cmp_stage5_i_mask[1])) ? 
			(
				cmp_stage5_i_mask[0] ? 
					cmp_stage5_i_wptr[0]:
					cmp_stage5_i_wptr[1]
			):(
				(
					(cmp_stage5_i_wptr[0][5] ^ cmp_stage5_i_wptr[1][5]) ^ 
					(cmp_stage5_i_wptr[0][4:0] > cmp_stage5_i_wptr[1][4:0])
				) ? 
					cmp_stage5_i_wptr[0]:
					cmp_stage5_i_wptr[1]
			);
	assign cmp_stage5_o_mask = 
		cmp_stage5_i_mask[0] | cmp_stage5_i_mask[1];
	assign cmp_stage5_o_data = 
		((~cmp_stage5_i_mask[0]) | (~cmp_stage5_i_mask[1])) ? 
			(
				cmp_stage5_i_mask[0] ? 
					cmp_stage5_i_data[0]:
					cmp_stage5_i_data[1]
			):(
				(
					(cmp_stage5_i_wptr[0][5] ^ cmp_stage5_i_wptr[1][5]) ^ 
					(cmp_stage5_i_wptr[0][4:0] > cmp_stage5_i_wptr[1][4:0])
				) ? 
					cmp_stage5_i_data[0]:
					cmp_stage5_i_data[1]
			);
	
	/** 最终的比较结果 **/
	assign newest_entry_i = cmp_stage5_o_wptr[4:0];
	assign newest_entry_payload = cmp_stage5_o_data;
	
endmodule
