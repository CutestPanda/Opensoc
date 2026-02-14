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
本模块: 取指缓存

描述:
取指阶段的段寄存器
只能存储1条已取到的指令

注意：
无

协议:
无

作者: 陈家耀
日期: 2026/02/13
********************************************************************/


module panda_risc_v_if_regs #(
	parameter integer IBUS_TID_WIDTH = 8, // 指令总线事务ID位宽(1~16)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 复位/冲刷
	input wire sys_reset_req, // 系统复位请求
	input wire flush_req, // 冲刷请求
	
	// 取指缓存输入
	input wire[127:0] s_if_regs_data, // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	input wire[98:0] s_if_regs_msg, // 取指附加信息({分支预测信息(96bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	input wire[IBUS_TID_WIDTH-1:0] s_if_regs_id, // 指令编号
	input wire s_if_regs_is_first_inst_after_rst, // 是否复位释放后的第1条指令
	input wire s_if_regs_valid,
	output wire s_if_regs_ready,
	
	// 取指缓存输出
	output wire[127:0] m_if_regs_data, // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	output wire[98:0] m_if_regs_msg, // 取指附加信息({分支预测信息(96bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	output wire[IBUS_TID_WIDTH-1:0] m_if_regs_id, // 指令编号
	output wire m_if_regs_is_first_inst_after_rst, // 是否复位释放后的第1条指令
	output wire m_if_regs_valid,
	input wire m_if_regs_ready
);
	
	/** 常量 **/
	// 段寄存器负载数据的位宽
	localparam integer STAGE_REGS_PAYLOAD_WIDTH = 128 + 99 + IBUS_TID_WIDTH + 1;
	
	/** 段寄存器 **/
	wire on_flush_rst; // 正在进行流水线冲刷
	reg[STAGE_REGS_PAYLOAD_WIDTH-1:0] stage_regs_payload; // 暂存的负载数据
	reg stage_regs_latched; // 负载已暂存(标志)
	
	assign s_if_regs_ready = 
		(~on_flush_rst) & 
		(~stage_regs_latched);
	
	assign {m_if_regs_data, m_if_regs_msg, m_if_regs_id, m_if_regs_is_first_inst_after_rst} = 
		stage_regs_latched ? 
			stage_regs_payload:
			{s_if_regs_data, s_if_regs_msg, s_if_regs_id, s_if_regs_is_first_inst_after_rst}; // 将负载数据直接旁路出去
	assign m_if_regs_valid = 
		(~on_flush_rst) & 
		(stage_regs_latched | s_if_regs_valid);
	
	assign on_flush_rst = sys_reset_req | flush_req;
	
	// 暂存的负载数据
	always @(posedge aclk)
	begin
		if((~on_flush_rst) & (~stage_regs_latched) & s_if_regs_valid & (~m_if_regs_ready))
			stage_regs_payload <= # SIM_DELAY {
				s_if_regs_data,
				s_if_regs_msg,
				s_if_regs_id,
				s_if_regs_is_first_inst_after_rst
			};
	end
	
	// 负载已暂存(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			stage_regs_latched <= 1'b0;
		else if(
			on_flush_rst | 
			(
				stage_regs_latched ? 
					m_if_regs_ready:
					(s_if_regs_valid & (~m_if_regs_ready))
			)
		)
			stage_regs_latched <= # SIM_DELAY (~(sys_reset_req | flush_req)) & (~stage_regs_latched);
	end
	
endmodule
