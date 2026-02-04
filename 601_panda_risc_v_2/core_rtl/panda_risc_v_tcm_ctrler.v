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
本模块: 符合AXI协议的ITCM/DTCM控制器

描述: 
用于小胖达RISC-V的低时延ITCM/DTCM控制器

ITCM/DTCM读时延 = 1clk

注意：
无

协议:
AXI-Lite SLAVE
MEM READ/WRITE

作者: 陈家耀
日期: 2026/01/30
********************************************************************/


module panda_risc_v_tcm_ctrler #(
	parameter integer TCM_DATA_WIDTH = 32, // TCM数据位宽(32 | 64 | 128 | 256)
    parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
    input wire aclk,
    input wire aresetn,
    
    // AXI从机
    // [AR通道]
    input wire[31:0] s_axi_araddr,
    input wire[1:0] s_axi_arburst, // ignored
    input wire[7:0] s_axi_arlen, // ignored
    input wire[2:0] s_axi_arsize, // ignored
    input wire s_axi_arvalid,
    output wire s_axi_arready,
	// [R通道]
    output wire[TCM_DATA_WIDTH-1:0] s_axi_rdata,
    output wire s_axi_rlast, // const -> 1'b1
    output wire[1:0] s_axi_rresp, // const -> 2'b00(OKAY)
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    // [AW通道]
    input wire[31:0] s_axi_awaddr,
    input wire[1:0] s_axi_awburst, // ignored
    input wire[7:0] s_axi_awlen, // ignored
    input wire[2:0] s_axi_awsize, // ignored
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    // [B通道]
    output wire[1:0] s_axi_bresp, // const -> 2'b00(OKAY)
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    // [W通道]
    input wire[TCM_DATA_WIDTH-1:0] s_axi_wdata,
    input wire s_axi_wlast, // ignored
    input wire[TCM_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    
    // 存储器接口
	// [端口A]
    output wire tcm_clka,
    output wire tcm_rsta,
    output wire tcm_ena,
    output wire[TCM_DATA_WIDTH/8-1:0] tcm_wena, // const -> {(TCM_DATA_WIDTH/8){1'b0}}
    output wire[29:0] tcm_addra,
    output wire[TCM_DATA_WIDTH-1:0] tcm_dina, // not cared
    input wire[TCM_DATA_WIDTH-1:0] tcm_douta,
	// [端口B]
    output wire tcm_clkb,
    output wire tcm_rstb,
    output wire tcm_enb,
    output wire[TCM_DATA_WIDTH/8-1:0] tcm_wenb,
    output wire[29:0] tcm_addrb,
    output wire[TCM_DATA_WIDTH-1:0] tcm_dinb,
    input wire[TCM_DATA_WIDTH-1:0] tcm_doutb // ignored
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
    
    /** 读控制 **/
	reg rvalid_r;
	
	assign s_axi_arready = (~rvalid_r) | s_axi_rready;
	
	assign s_axi_rdata = tcm_douta;
	assign s_axi_rlast = 1'b1;
	assign s_axi_rresp = 2'b00;
	assign s_axi_rvalid = rvalid_r;
	
	assign tcm_clka = aclk;
	assign tcm_rsta = ~aresetn;
	assign tcm_ena = s_axi_arvalid & s_axi_arready;
	assign tcm_wena = {(TCM_DATA_WIDTH/8){1'b0}};
	assign tcm_addra = s_axi_araddr[31:clogb2(TCM_DATA_WIDTH/8)] | 30'd0;
	assign tcm_dina = {TCM_DATA_WIDTH{1'bx}};
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rvalid_r <= 1'b0;
		else if(s_axi_arready)
			rvalid_r <= # SIM_DELAY s_axi_arvalid;
	end
	
	/** 写控制 **/
	reg[31:0] awaddr_latched;
	reg is_aw_content_latched;
	reg[TCM_DATA_WIDTH-1:0] wdata_latched;
	reg[TCM_DATA_WIDTH/8-1:0] wmask_latched;
	reg is_w_content_latched;
	wire mem_wr_s0_valid;
	wire mem_wr_s0_ready;
	reg mem_wr_s1_valid;
	wire mem_wr_s1_ready;
	
	assign s_axi_awready = ~is_aw_content_latched;
	
	assign s_axi_bresp = 2'b00;
	assign s_axi_bvalid = mem_wr_s1_valid;
	
	assign s_axi_wready = ~is_w_content_latched;
	
	assign tcm_clkb = aclk;
	assign tcm_rstb = ~aresetn;
	assign tcm_enb = mem_wr_s0_valid & mem_wr_s0_ready;
	assign tcm_wenb = 
		is_w_content_latched ? 
			wmask_latched:
			s_axi_wstrb;
	assign tcm_addrb = 
		is_aw_content_latched ? 
			awaddr_latched[31:clogb2(TCM_DATA_WIDTH/8)]:
			s_axi_awaddr[31:clogb2(TCM_DATA_WIDTH/8)];
	assign tcm_dinb = 
		is_w_content_latched ? 
			wdata_latched:
			s_axi_wdata;
	
	assign mem_wr_s0_valid = 
		(is_aw_content_latched | s_axi_awvalid) & 
		(is_w_content_latched | s_axi_wvalid);
	assign mem_wr_s0_ready = (~mem_wr_s1_valid) | mem_wr_s1_ready;
	assign mem_wr_s1_ready = s_axi_bready;
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			is_aw_content_latched <= 1'b0;
		else
			is_aw_content_latched <= # SIM_DELAY 
				is_aw_content_latched ? 
					((~(mem_wr_s0_valid & mem_wr_s0_ready))):
					(
						s_axi_awvalid & 
						(~(mem_wr_s0_valid & mem_wr_s0_ready))
					);
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			is_w_content_latched <= 1'b0;
		else
			is_w_content_latched <= # SIM_DELAY 
				is_w_content_latched ? 
					((~(mem_wr_s0_valid & mem_wr_s0_ready))):
					(
						s_axi_wvalid & 
						(~(mem_wr_s0_valid & mem_wr_s0_ready))
					);
	end
	
	always @(posedge aclk)
	begin
		if((~is_aw_content_latched) & s_axi_awvalid)
			awaddr_latched <= # SIM_DELAY s_axi_awaddr;
			
	end
	
	always @(posedge aclk)
	begin
		if((~is_w_content_latched) & s_axi_wvalid)
		begin
			wdata_latched <= # SIM_DELAY s_axi_wdata;
			wmask_latched <= # SIM_DELAY s_axi_wstrb;
		end
	end
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			mem_wr_s1_valid <= 1'b0;
		else if(mem_wr_s0_ready)
			mem_wr_s1_valid <= # SIM_DELAY mem_wr_s0_valid;
	end
	
endmodule
