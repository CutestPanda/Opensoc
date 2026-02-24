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
本模块: 小胖达RISC-V基础数据系统设备

描述: 
包括DTCM控制器、DTCM存储器、DCache

注意：
无

协议:
AXI-Lite SLAVE
AXI MASTER

作者: 陈家耀
日期: 2026/02/24
********************************************************************/


module panda_risc_v_basis_data_device #(
	parameter DMEM_TYPE = "dtcm", // 数据存储器类型(dtcm | dcache)
	parameter DMEM_BASEADDR = 32'h1000_0000, // 数据存储器基址
	parameter integer DMEM_ADDR_RANGE = 32 * 1024, // 数据存储器地址区间长度(以字节计)
	parameter DTCM_MEM_INIT_FILE = "no_init", // DTCM存储器初始化文件路径
	parameter integer CACHE_WAY_N = 4, // 缓存路数(1 | 2 | 4 | 8)
	parameter integer CACHE_ENTRY_N = 512, // 缓存存储条目数
	parameter integer CACHE_LINE_DATA_N = 8, // 每个缓存行的数据个数(1 | 2 | 4 | 8 | 16)
	parameter integer CACHE_WBUF_ITEM_N = 4, // 写缓存最多可存的缓存行个数(1~8)
    parameter real SIM_DELAY = 1 // 仿真延时
)(
	// AXI从机时钟和复位
    input wire s_axi_aclk,
    input wire s_axi_aresetn,
	
	// (数据总线)存储器AXI主机
	// [AR通道]
	input wire[31:0] s_axi_dmem_araddr,
	input wire[1:0] s_axi_dmem_arburst,
	input wire[7:0] s_axi_dmem_arlen,
	input wire[2:0] s_axi_dmem_arsize,
	input wire s_axi_dmem_arvalid,
	output wire s_axi_dmem_arready,
	// [R通道]
	output wire[31:0] s_axi_dmem_rdata,
	output wire[1:0] s_axi_dmem_rresp,
	output wire s_axi_dmem_rlast,
	output wire s_axi_dmem_rvalid,
	input wire s_axi_dmem_rready,
	// [AW通道]
	input wire[31:0] s_axi_dmem_awaddr,
	input wire[1:0] s_axi_dmem_awburst,
	input wire[7:0] s_axi_dmem_awlen,
	input wire[2:0] s_axi_dmem_awsize,
	input wire s_axi_dmem_awvalid,
	output wire s_axi_dmem_awready,
	// [B通道]
	output wire[1:0] s_axi_dmem_bresp,
	output wire s_axi_dmem_bvalid,
	input wire s_axi_dmem_bready,
	// [W通道]
	input wire[31:0] s_axi_dmem_wdata,
	input wire[3:0] s_axi_dmem_wstrb,
	input wire s_axi_dmem_wlast,
	input wire s_axi_dmem_wvalid,
	output wire s_axi_dmem_wready,
	
	// 访问下级存储器(AXI主机)
	// 说明: 仅当启用DCache时可用
	// [AR通道]
	output wire[31:0] m_axi_nlv_araddr,
	output wire[1:0] m_axi_nlv_arburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_nlv_arlen, // const -> CACHE_LINE_DATA_N - 1
	output wire[2:0] m_axi_nlv_arsize, // const -> 3'b010
	output wire m_axi_nlv_arvalid,
	input wire m_axi_nlv_arready,
	// [R通道]
	input wire[31:0] m_axi_nlv_rdata,
	input wire[1:0] m_axi_nlv_rresp, // ignored
	input wire m_axi_nlv_rlast, // ignored
	input wire m_axi_nlv_rvalid,
	output wire m_axi_nlv_rready, // const -> 1'b1
	// [AW通道]
	output wire[31:0] m_axi_nlv_awaddr,
	output wire[1:0] m_axi_nlv_awburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_nlv_awlen, // const -> CACHE_LINE_DATA_N - 1
	output wire[2:0] m_axi_nlv_awsize, // const -> 3'b010
	output wire m_axi_nlv_awvalid,
	input wire m_axi_nlv_awready,
	// [B通道]
	input wire[1:0] m_axi_nlv_bresp, // ignored
	input wire m_axi_nlv_bvalid,
	output wire m_axi_nlv_bready, // const -> 1'b1
	// [W通道]
	output wire[31:0] m_axi_nlv_wdata,
	output wire[3:0] m_axi_nlv_wstrb, // const -> 4'b1111
	output wire m_axi_nlv_wlast,
	output wire m_axi_nlv_wvalid,
	input wire m_axi_nlv_wready
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
	
	/** 常量 **/
	// 缓存标签位数
	localparam integer CACHE_TAG_WIDTH = 
		(clogb2(DMEM_ADDR_RANGE/(CACHE_ENTRY_N*CACHE_LINE_DATA_N*(32/8))) < 1) ? 
			1:
			clogb2(DMEM_ADDR_RANGE/(CACHE_ENTRY_N*CACHE_LINE_DATA_N*(32/8)));
	
	/** AXI-TCM控制器 **/
	// 存储器接口
	// [端口A, 只读]
    wire tcm_clka;
    wire tcm_rsta;
    wire tcm_ena;
    wire[3:0] tcm_wena;
    wire[29:0] tcm_addra;
    wire[31:0] tcm_dina;
    wire[31:0] tcm_douta;
	// [端口B, 只写]
    wire tcm_clkb;
    wire tcm_rstb;
    wire tcm_enb;
    wire[3:0] tcm_wenb;
    wire[29:0] tcm_addrb;
    wire[31:0] tcm_dinb;
    wire[31:0] tcm_doutb;
	
	generate
		if(DMEM_TYPE == "dtcm")
		begin
			panda_risc_v_tcm_ctrler #(
				.TCM_DATA_WIDTH(32),
				.SIM_DELAY(SIM_DELAY)
			)tcm_ctrler_u(
				.aclk(s_axi_aclk),
				.aresetn(s_axi_aresetn),
				
				.s_axi_araddr(s_axi_dmem_araddr),
				.s_axi_arburst(s_axi_dmem_arburst),
				.s_axi_arlen(s_axi_dmem_arlen),
				.s_axi_arsize(s_axi_dmem_arsize),
				.s_axi_arvalid(s_axi_dmem_arvalid),
				.s_axi_arready(s_axi_dmem_arready),
				.s_axi_rdata(s_axi_dmem_rdata),
				.s_axi_rlast(s_axi_dmem_rlast),
				.s_axi_rresp(s_axi_dmem_rresp),
				.s_axi_rvalid(s_axi_dmem_rvalid),
				.s_axi_rready(s_axi_dmem_rready),
				.s_axi_awaddr(s_axi_dmem_awaddr),
				.s_axi_awburst(s_axi_dmem_awburst),
				.s_axi_awlen(s_axi_dmem_awlen),
				.s_axi_awsize(s_axi_dmem_awsize),
				.s_axi_awvalid(s_axi_dmem_awvalid),
				.s_axi_awready(s_axi_dmem_awready),
				.s_axi_bresp(s_axi_dmem_bresp),
				.s_axi_bvalid(s_axi_dmem_bvalid),
				.s_axi_bready(s_axi_dmem_bready),
				.s_axi_wdata(s_axi_dmem_wdata),
				.s_axi_wlast(s_axi_dmem_wlast),
				.s_axi_wstrb(s_axi_dmem_wstrb),
				.s_axi_wvalid(s_axi_dmem_wvalid),
				.s_axi_wready(s_axi_dmem_wready),
				
				.tcm_clka(tcm_clka),
				.tcm_rsta(tcm_rsta),
				.tcm_ena(tcm_ena),
				.tcm_wena(tcm_wena),
				.tcm_addra(tcm_addra),
				.tcm_dina(tcm_dina),
				.tcm_douta(tcm_douta),
				.tcm_clkb(tcm_clkb),
				.tcm_rstb(tcm_rstb),
				.tcm_enb(tcm_enb),
				.tcm_wenb(tcm_wenb),
				.tcm_addrb(tcm_addrb),
				.tcm_dinb(tcm_dinb),
				.tcm_doutb(tcm_doutb)
			);
		end
		else
		begin
			assign tcm_clka = 1'b0;
			assign tcm_rsta = 1'b1;
			assign tcm_ena = 1'b0;
			assign tcm_wena = 4'b0000;
			assign tcm_addra = 30'dx;
			assign tcm_dina = 32'dx;
			
			assign tcm_clkb = 1'b0;
			assign tcm_rstb = 1'b1;
			assign tcm_enb = 1'b0;
			assign tcm_wenb = 4'b0000;
			assign tcm_addrb = 30'dx;
			assign tcm_dinb = 32'dx;
		end
	endgenerate
	
	/** DCache **/
	generate
		if(DMEM_TYPE == "dcache")
		begin
			axi_dcache #(
				.CACHE_WAY_N(CACHE_WAY_N),
				.CACHE_ENTRY_N(CACHE_ENTRY_N),
				.CACHE_DATA_WIDTH(32),
				.CACHE_LINE_DATA_N(CACHE_LINE_DATA_N),
				.CACHE_TAG_WIDTH(CACHE_TAG_WIDTH),
				.WBUF_ITEM_N(CACHE_WBUF_ITEM_N),
				.SIM_DELAY(SIM_DELAY)
			)axi_dcache_u(
				.aclk(s_axi_aclk),
				.aresetn(s_axi_aresetn),
				
				.s_axi_araddr(s_axi_dmem_araddr),
				.s_axi_arvalid(s_axi_dmem_arvalid),
				.s_axi_arready(s_axi_dmem_arready),
				.s_axi_rdata(s_axi_dmem_rdata),
				.s_axi_rlast(s_axi_dmem_rlast),
				.s_axi_rresp(s_axi_dmem_rresp),
				.s_axi_rvalid(s_axi_dmem_rvalid),
				.s_axi_rready(s_axi_dmem_rready),
				.s_axi_awaddr(s_axi_dmem_awaddr),
				.s_axi_awvalid(s_axi_dmem_awvalid),
				.s_axi_awready(s_axi_dmem_awready),
				.s_axi_bresp(s_axi_dmem_bresp),
				.s_axi_bvalid(s_axi_dmem_bvalid),
				.s_axi_bready(s_axi_dmem_bready),
				.s_axi_wdata(s_axi_dmem_wdata),
				.s_axi_wlast(s_axi_dmem_wlast),
				.s_axi_wstrb(s_axi_dmem_wstrb),
				.s_axi_wvalid(s_axi_dmem_wvalid),
				.s_axi_wready(s_axi_dmem_wready),
				
				.m_axi_araddr(m_axi_nlv_araddr),
				.m_axi_arburst(m_axi_nlv_arburst),
				.m_axi_arlen(m_axi_nlv_arlen),
				.m_axi_arsize(m_axi_nlv_arsize),
				.m_axi_arvalid(m_axi_nlv_arvalid),
				.m_axi_arready(m_axi_nlv_arready),
				.m_axi_rdata(m_axi_nlv_rdata),
				.m_axi_rresp(m_axi_nlv_rresp),
				.m_axi_rlast(m_axi_nlv_rlast),
				.m_axi_rvalid(m_axi_nlv_rvalid),
				.m_axi_rready(m_axi_nlv_rready),
				.m_axi_awaddr(m_axi_nlv_awaddr),
				.m_axi_awburst(m_axi_nlv_awburst),
				.m_axi_awlen(m_axi_nlv_awlen),
				.m_axi_awsize(m_axi_nlv_awsize),
				.m_axi_awvalid(m_axi_nlv_awvalid),
				.m_axi_awready(m_axi_nlv_awready),
				.m_axi_bresp(m_axi_nlv_bresp),
				.m_axi_bvalid(m_axi_nlv_bvalid),
				.m_axi_bready(m_axi_nlv_bready),
				.m_axi_wdata(m_axi_nlv_wdata),
				.m_axi_wstrb(m_axi_nlv_wstrb),
				.m_axi_wlast(m_axi_nlv_wlast),
				.m_axi_wvalid(m_axi_nlv_wvalid),
				.m_axi_wready(m_axi_nlv_wready)
			);
		end
		else
		begin
			assign m_axi_nlv_araddr = 32'dx;
			assign m_axi_nlv_arburst = 2'bxx;
			assign m_axi_nlv_arlen = 8'dx;
			assign m_axi_nlv_arsize = 3'bxxx;
			assign m_axi_nlv_arvalid = 1'b0;
			
			assign m_axi_nlv_rready = 1'b1;
			
			assign m_axi_nlv_awaddr = 32'dx;
			assign m_axi_nlv_awburst = 2'bxx;
			assign m_axi_nlv_awlen = 8'dx;
			assign m_axi_nlv_awsize = 3'bxxx;
			assign m_axi_nlv_awvalid = 1'b0;
			
			assign m_axi_nlv_bready = 1'b1;
			
			assign m_axi_nlv_wdata = 32'dx;
			assign m_axi_nlv_wstrb = 4'bxxxx;
			assign m_axi_nlv_wlast = 1'bx;
			assign m_axi_nlv_wvalid = 1'b0;
		end
	endgenerate
	
	/** DTCM **/
	// 存储器接口
	// [端口A, 只读]
    wire dtcm_clka;
    wire dtcm_ena;
    wire[3:0] dtcm_wena;
    wire[29:0] dtcm_addra;
    wire[31:0] dtcm_dina;
    wire[31:0] dtcm_douta;
	// [端口B, 只写]
    wire dtcm_clkb;
    wire dtcm_enb;
    wire[3:0] dtcm_wenb;
    wire[29:0] dtcm_addrb;
    wire[31:0] dtcm_dinb;
    wire[31:0] dtcm_doutb;
	
	assign dtcm_clka = tcm_clka;
	assign dtcm_ena = tcm_ena;
	assign dtcm_wena = 4'b0000;
	assign dtcm_addra = tcm_addra;
	assign dtcm_dina = 32'dx;
	assign tcm_douta = dtcm_douta;
	
	assign dtcm_clkb = tcm_clkb;
	assign dtcm_enb = tcm_enb;
	assign dtcm_wenb = tcm_wenb;
	assign dtcm_addrb = tcm_addrb;
	assign dtcm_dinb = tcm_dinb;
	
	generate
		if(DMEM_TYPE == "dtcm")
		begin
			bram_true_dual_port #(
				.mem_width(32),
				.mem_depth(DMEM_ADDR_RANGE / 4),
				.INIT_FILE(DTCM_MEM_INIT_FILE),
				.read_write_mode("read_first"),
				.use_output_register("false"),
				.en_byte_write("true"),
				.simulation_delay(SIM_DELAY)
			)dtcm_mem_u(
				.clk(dtcm_clka),
				
				.ena(dtcm_ena),
				.wea(dtcm_wena),
				.addra(dtcm_addra[clogb2(DMEM_ADDR_RANGE / 4 - 1):0]),
				.dina(dtcm_dina),
				.douta(dtcm_douta),
				
				.enb(dtcm_enb),
				.web(dtcm_wenb),
				.addrb(dtcm_addrb[clogb2(DMEM_ADDR_RANGE / 4 - 1):0]),
				.dinb(dtcm_dinb),
				.doutb(dtcm_doutb)
			);
		end
		else
		begin
			assign dtcm_douta = 32'dx;
			assign dtcm_doutb = 32'dx;
		end
	endgenerate
	
endmodule
