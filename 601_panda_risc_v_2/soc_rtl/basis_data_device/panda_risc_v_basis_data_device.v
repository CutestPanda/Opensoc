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
包括DTCM控制器、DTCM存储器

注意：
无

协议:
AXI-Lite SLAVE

作者: 陈家耀
日期: 2026/01/31
********************************************************************/


module panda_risc_v_basis_data_device #(
	parameter DMEM_BASEADDR = 32'h1000_0000, // 数据存储器基址
	parameter integer DMEM_ADDR_RANGE = 32 * 1024, // 数据存储器地址区间长度(以字节计)
	parameter DTCM_MEM_INIT_FILE = "no_init", // DTCM存储器初始化文件路径
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
	output wire s_axi_dmem_wready
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
	
endmodule
