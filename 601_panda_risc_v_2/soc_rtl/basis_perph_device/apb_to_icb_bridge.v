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
本模块: APB转ICB协议桥

描述: 
将APB协议转换为ICB协议

注意：
无

协议:
APB SLAVE
ICB MASTER

作者: 陈家耀
日期: 2026/02/04
********************************************************************/


module apb_to_icb_bridge #(
	parameter integer ADDR_WIDTH = 32, // 地址位宽(4~32)
    parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
    input wire aclk,
    input wire aresetn,
	
	// APB从机
	input wire[ADDR_WIDTH-1:0] s_apb_paddr,
    input wire s_apb_penable,
    input wire s_apb_pwrite,
    input wire s_apb_psel,
    input wire[3:0] s_apb_pstrb,
    input wire[31:0] s_apb_pwdata,
    output wire s_apb_pready,
    output wire s_apb_pslverr,
    output wire[31:0] s_apb_prdata,
    
    // ICB从机
	// [命令通道]
	output wire[ADDR_WIDTH-1:0] m_icb_cmd_addr,
	output wire m_icb_cmd_read,
	output wire[31:0] m_icb_cmd_wdata,
	output wire[3:0] m_icb_cmd_wmask,
	output wire m_icb_cmd_valid,
	input wire m_icb_cmd_ready,
	// [响应通道]
	input wire[31:0] m_icb_rsp_rdata,
	input wire m_icb_rsp_err,
	input wire m_icb_rsp_valid,
	output wire m_icb_rsp_ready
);
	
	reg addr_setup;
	wire on_icb_cmd_complete;
	wire on_icb_rsp_complete;
	
	assign s_apb_pready = on_icb_rsp_complete;
	assign s_apb_pslverr = m_icb_rsp_err;
	assign s_apb_prdata = m_icb_rsp_rdata;
	
	assign m_icb_cmd_addr = s_apb_paddr;
	assign m_icb_cmd_read = ~s_apb_pwrite;
	assign m_icb_cmd_wdata = s_apb_pwdata;
	assign m_icb_cmd_wmask = s_apb_pstrb;
	assign m_icb_cmd_valid = s_apb_psel & (~addr_setup);
	
	assign m_icb_rsp_ready = s_apb_psel & s_apb_penable;
	
	assign on_icb_cmd_complete = m_icb_cmd_valid & m_icb_cmd_ready;
	assign on_icb_rsp_complete = m_icb_rsp_valid & m_icb_rsp_ready;
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			addr_setup <= 1'b0;
		else if(
			s_apb_psel & 
			(
				addr_setup ? 
					(s_apb_penable & s_apb_pready):
					on_icb_cmd_complete
			)
		)
			addr_setup <= # SIM_DELAY ~addr_setup;
	end
    
endmodule
