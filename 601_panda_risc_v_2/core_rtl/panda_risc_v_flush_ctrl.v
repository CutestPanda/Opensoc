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
本模块: 冲刷控制

描述:
对来自IFU/BRU/交付单元的冲刷请求进行仲裁

冲刷请求的优先级从高到低分别是 -> 
	交付单元给出的冲刷请求
	BRU给出的冲刷请求
	IFU给出的冲刷请求

注意：
无

协议:
REQ/GRANT

作者: 陈家耀
日期: 2026/02/05
********************************************************************/


module panda_risc_v_flush_ctrl #(
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 系统复位请求
	input wire sys_reset_req,
	
	// 全局历史分支预测
	output wire glb_brc_prdt_on_clr_retired_ghr, // 清零退休GHR(指示)
	output wire glb_brc_prdt_rstr_speculative_ghr, // 恢复推测GHR(指示)
	
	// IFU给出的冲刷请求
	input wire ifu_flush_req, // 冲刷请求
	input wire[31:0] ifu_flush_addr, // 冲刷地址
	output wire ifu_flush_grant, // 冲刷许可
	
	// BRU给出的冲刷请求
	input wire bru_flush_req, // 冲刷请求
	input wire[31:0] bru_flush_addr, // 冲刷地址
	output wire bru_flush_grant, // 冲刷许可
	
	// 交付单元给出的冲刷请求
	input wire cmt_flush_req, // 冲刷请求
	input wire[31:0] cmt_flush_addr, // 冲刷地址
	output wire cmt_flush_grant, // 冲刷许可
	
	// 指令总线控制单元状态
	input wire suppressing_ibus_access, // 当前有正在镇压的ICB事务(状态标志)
	
	// IFU专用冲刷请求
	output wire ifu_exclusive_flush_req,
	
	// 全局冲刷请求
	output wire global_flush_req, // 冲刷请求
	output wire[31:0] global_flush_addr, // 冲刷地址
	input wire global_flush_ack // 冲刷应答
);
	
	reg global_flush_pending; // 全局冲刷等待(标志)
	reg sel_ifu_flush; // 选择IFU给出的冲刷请求(标志)
	reg sel_bru_flush; // 选择BRU给出的冲刷请求(标志)
	reg sel_cmt_flush; // 选择交付单元给出的冲刷请求(标志)
	
	assign glb_brc_prdt_on_clr_retired_ghr = 
		sys_reset_req | 
		(cmt_flush_req & (~suppressing_ibus_access) & (~global_flush_pending));
	assign glb_brc_prdt_rstr_speculative_ghr = 
		sys_reset_req | 
		((bru_flush_req | cmt_flush_req) & (~suppressing_ibus_access) & (~global_flush_pending));
	
	assign ifu_flush_grant = 
		ifu_flush_req & global_flush_ack & 
		(
			global_flush_pending ? 
				sel_ifu_flush:
				((~bru_flush_req) & (~cmt_flush_req))
		);
	assign bru_flush_grant = 
		bru_flush_req & global_flush_ack & 
		(
			global_flush_pending ? 
				sel_bru_flush:
				(~cmt_flush_req)
		);
	assign cmt_flush_grant = 
		cmt_flush_req & global_flush_ack & 
		(
			global_flush_pending ? 
				sel_cmt_flush:
				1'b1
		);
	
	assign ifu_exclusive_flush_req = 
		ifu_flush_req & (~suppressing_ibus_access) & (~global_flush_pending);
	assign global_flush_req = 
		(bru_flush_req | cmt_flush_req) & (~suppressing_ibus_access) & (~global_flush_pending);
	assign global_flush_addr = 
		cmt_flush_req ? 
			cmt_flush_addr:
			(
				bru_flush_req ? 
					bru_flush_addr:
					ifu_flush_addr
			);
	
	// 全局冲刷等待(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			global_flush_pending <= 1'b0;
		else
			global_flush_pending <= # SIM_DELAY 
				/*
				global_flush_pending ? 
					(~global_flush_ack):
					((ifu_flush_req | bru_flush_req | cmt_flush_req) & (~suppressing_ibus_access) & (~global_flush_ack))
				*/
				(
					global_flush_pending | 
					((ifu_flush_req | bru_flush_req | cmt_flush_req) & (~suppressing_ibus_access))
				) & 
				(~global_flush_ack);
	end
	
	// 选择IFU给出的冲刷请求(标志), 选择BRU给出的冲刷请求(标志), 选择交付单元给出的冲刷请求(标志)
	always @(posedge aclk)
	begin
		if(ifu_exclusive_flush_req | global_flush_req)
		begin
			sel_ifu_flush <= # SIM_DELAY ifu_flush_req & (~bru_flush_req) & (~cmt_flush_req);
			sel_bru_flush <= # SIM_DELAY bru_flush_req & (~cmt_flush_req);
			sel_cmt_flush <= # SIM_DELAY cmt_flush_req;
		end
	end
	
endmodule
