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
本模块: 小胖达RISC-V基础指令系统设备

描述: 
包括调试机制(DTM和DM)、ITCM控制器、ITCM存储器、BTB存储器

注意：
无

协议:
JTAG SLAVE
AXI-Lite SLAVE
MEM SLAVE

作者: 陈家耀
日期: 2026/01/31
********************************************************************/


module panda_risc_v_basis_inst_device #(
	parameter DEBUG_SUPPORTED = "false", // 是否需要支持Debug
	parameter integer PROGBUF_SIZE = 2, // Program Buffer的大小(以双字计, 必须在范围[0, 16]内)
	parameter DATA0_ADDR = 32'hFFFF_F800, // data0寄存器在存储映射中的地址
	parameter PROGBUF0_ADDR = 32'hFFFF_F900, // progbuf0寄存器在存储映射中的地址
	parameter HART_ACMD_CTRT_ADDR = 32'hFFFF_FA00, // HART抽象命令运行控制在存储映射中的地址
	parameter IMEM_BASEADDR = 32'h0000_0000, // 指令存储器基址
	parameter integer IMEM_ADDR_RANGE = 32 * 1024, // 指令存储器地址区间长度(以字节计)
	parameter DM_REGS_BASEADDR = 32'hFFFF_F800, // DM寄存器区基址
	parameter integer DM_REGS_ADDR_RANGE = 1 * 1024, // DM寄存器区地址区间长度(以字节计)
	parameter ITCM_MEM_INIT_FILE = "no_init", // ITCM存储器初始化文件路径
	parameter integer BTB_WAY_N = 2, // BTB路数(1 | 2 | 4)
	parameter integer BTB_ENTRY_N = 1024, // BTB项数(<=65536)
    parameter real SIM_DELAY = 1 // 仿真延时
)(
	// JTAG从机
	input wire jtag_slave_tck,
	input wire jtag_slave_trst_n,
	input wire jtag_slave_tms,
	input wire jtag_slave_tdi,
	output wire jtag_slave_tdo,
	
    // AXI从机时钟和复位
    input wire s_axi_aclk,
    input wire s_axi_aresetn,
	
	// 调试模块复位
	input wire dbg_aresetn,
	
	// 复位控制
	input wire sys_reset_fns, // 系统复位完成
	output wire sw_reset, // 软件服务请求
	
	// HART暂停请求
	output wire dbg_halt_req, // 来自调试器的暂停请求
	output wire dbg_halt_on_reset_req, // 来自调试器的复位释放后暂停请求
	
	// (指令总线)存储器AXI从机
	// [AR通道]
	input wire[31:0] s_axi_imem_araddr,
	input wire[1:0] s_axi_imem_arburst,
	input wire[7:0] s_axi_imem_arlen,
	input wire[2:0] s_axi_imem_arsize,
	input wire s_axi_imem_arvalid,
	output wire s_axi_imem_arready,
	// [R通道]
	output wire[31:0] s_axi_imem_rdata,
	output wire[1:0] s_axi_imem_rresp,
	output wire s_axi_imem_rlast,
	output wire s_axi_imem_rvalid,
	input wire s_axi_imem_rready,
	// [AW通道]
	input wire[31:0] s_axi_imem_awaddr,
	input wire[1:0] s_axi_imem_awburst,
	input wire[7:0] s_axi_imem_awlen,
	input wire[2:0] s_axi_imem_awsize,
	input wire s_axi_imem_awvalid,
	output wire s_axi_imem_awready,
	// [B通道]
	output wire[1:0] s_axi_imem_bresp,
	output wire s_axi_imem_bvalid,
	input wire s_axi_imem_bready,
	// [W通道]
	input wire[31:0] s_axi_imem_wdata,
	input wire[3:0] s_axi_imem_wstrb,
	input wire s_axi_imem_wlast,
	input wire s_axi_imem_wvalid,
	output wire s_axi_imem_wready,
	
	// BTB存储器
	// [端口A]
	input wire[BTB_WAY_N-1:0] btb_mem_clka,
	input wire[BTB_WAY_N-1:0] btb_mem_ena,
	input wire[BTB_WAY_N-1:0] btb_mem_wea,
	input wire[BTB_WAY_N*16-1:0] btb_mem_addra,
	input wire[BTB_WAY_N*64-1:0] btb_mem_dina,
	output wire[BTB_WAY_N*64-1:0] btb_mem_douta,
	// [端口B]
	input wire[BTB_WAY_N-1:0] btb_mem_clkb,
	input wire[BTB_WAY_N-1:0] btb_mem_enb,
	input wire[BTB_WAY_N-1:0] btb_mem_web,
	input wire[BTB_WAY_N*16-1:0] btb_mem_addrb,
	input wire[BTB_WAY_N*64-1:0] btb_mem_dinb,
	output wire[BTB_WAY_N*64-1:0] btb_mem_doutb
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
	wire port_a_itcm_sel;
	reg port_a_itcm_sel_d;
	// [端口B, 只写]
    wire tcm_clkb;
    wire tcm_rstb;
    wire tcm_enb;
    wire[3:0] tcm_wenb;
    wire[29:0] tcm_addrb;
    wire[31:0] tcm_dinb;
    wire[31:0] tcm_doutb;
	wire port_b_itcm_sel;
	
	assign port_a_itcm_sel = 
		(DEBUG_SUPPORTED == "false") | 
		(({tcm_addra, 2'b00} >= IMEM_BASEADDR) & ({tcm_addra, 2'b00} < (IMEM_BASEADDR + IMEM_ADDR_RANGE)));
	assign port_b_itcm_sel = 
		(DEBUG_SUPPORTED == "false") | 
		(({tcm_addrb, 2'b00} >= IMEM_BASEADDR) & ({tcm_addrb, 2'b00} < (IMEM_BASEADDR + IMEM_ADDR_RANGE)));
	
	always @(posedge s_axi_aclk)
	begin
		if(tcm_ena)
			port_a_itcm_sel_d <= # SIM_DELAY port_a_itcm_sel;
	end
	
	panda_risc_v_tcm_ctrler #(
		.TCM_DATA_WIDTH(32),
		.SIM_DELAY(SIM_DELAY)
	)tcm_ctrler_u(
		.aclk(s_axi_aclk),
		.aresetn(s_axi_aresetn),
		
		.s_axi_araddr(s_axi_imem_araddr),
		.s_axi_arburst(s_axi_imem_arburst),
		.s_axi_arlen(s_axi_imem_arlen),
		.s_axi_arsize(s_axi_imem_arsize),
		.s_axi_arvalid(s_axi_imem_arvalid),
		.s_axi_arready(s_axi_imem_arready),
		.s_axi_rdata(s_axi_imem_rdata),
		.s_axi_rlast(s_axi_imem_rlast),
		.s_axi_rresp(s_axi_imem_rresp),
		.s_axi_rvalid(s_axi_imem_rvalid),
		.s_axi_rready(s_axi_imem_rready),
		.s_axi_awaddr(s_axi_imem_awaddr),
		.s_axi_awburst(s_axi_imem_awburst),
		.s_axi_awlen(s_axi_imem_awlen),
		.s_axi_awsize(s_axi_imem_awsize),
		.s_axi_awvalid(s_axi_imem_awvalid),
		.s_axi_awready(s_axi_imem_awready),
		.s_axi_bresp(s_axi_imem_bresp),
		.s_axi_bvalid(s_axi_imem_bvalid),
		.s_axi_bready(s_axi_imem_bready),
		.s_axi_wdata(s_axi_imem_wdata),
		.s_axi_wlast(s_axi_imem_wlast),
		.s_axi_wstrb(s_axi_imem_wstrb),
		.s_axi_wvalid(s_axi_imem_wvalid),
		.s_axi_wready(s_axi_imem_wready),
		
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
	
	/** ITCM **/
	// 存储器接口
	// [端口A, 只读]
    wire itcm_clka;
    wire itcm_ena;
    wire[3:0] itcm_wena;
    wire[29:0] itcm_addra;
    wire[31:0] itcm_dina;
    wire[31:0] itcm_douta;
	// [端口B, 只写]
    wire itcm_clkb;
    wire itcm_enb;
    wire[3:0] itcm_wenb;
    wire[29:0] itcm_addrb;
    wire[31:0] itcm_dinb;
    wire[31:0] itcm_doutb;
	
	assign itcm_clka = tcm_clka;
	assign itcm_ena = tcm_ena & port_a_itcm_sel;
	assign itcm_wena = 4'b0000;
	assign itcm_addra = tcm_addra;
	assign itcm_dina = 32'dx;
	
	assign itcm_clkb = tcm_clkb;
	assign itcm_enb = tcm_enb & port_b_itcm_sel;
	assign itcm_wenb = tcm_wenb;
	assign itcm_addrb = tcm_addrb;
	assign itcm_dinb = tcm_dinb;
	
	bram_true_dual_port #(
		.mem_width(32),
		.mem_depth(IMEM_ADDR_RANGE / 4),
		.INIT_FILE(ITCM_MEM_INIT_FILE),
		.read_write_mode("read_first"),
		.use_output_register("false"),
		.en_byte_write("true"),
		.simulation_delay(SIM_DELAY)
	)itcm_mem_u(
		.clk(itcm_clka),
		
		.ena(itcm_ena),
		.wea(itcm_wena),
		.addra(itcm_addra[clogb2(IMEM_ADDR_RANGE / 4 - 1):0]),
		.dina(itcm_dina),
		.douta(itcm_douta),
		
		.enb(itcm_enb),
		.web(itcm_wenb),
		.addrb(itcm_addrb[clogb2(IMEM_ADDR_RANGE / 4 - 1):0]),
		.dinb(itcm_dinb),
		.doutb(itcm_doutb)
	);
	
	/** 调试机制 **/
	// HART写DM内容(存储器从接口)
	wire[3:0] hart_access_wen;
	wire[29:0] hart_access_waddr;
	wire[31:0] hart_access_din;
	// HART读DM内容(存储器从接口)
	wire hart_access_ren;
	wire[29:0] hart_access_raddr;
	wire[31:0] hart_access_dout;
	
	assign tcm_douta = 
		port_a_itcm_sel_d ? 
			itcm_douta:
			hart_access_dout;
	assign tcm_doutb = 32'dx;
	
	assign hart_access_ren = tcm_ena & (~port_a_itcm_sel);
	assign hart_access_raddr = tcm_addra;
	
	assign hart_access_wen = {4{tcm_enb & (~port_b_itcm_sel)}} & tcm_wenb;
	assign hart_access_waddr = tcm_addrb;
	assign hart_access_din = tcm_dinb;
	
	generate
		if(DEBUG_SUPPORTED == "true")
		begin
			panda_risc_v_jtag_debug #(
				.PROGBUF_SIZE(PROGBUF_SIZE),
				.DATA0_ADDR(DATA0_ADDR),
				.PROGBUF0_ADDR(PROGBUF0_ADDR),
				.HART_ACMD_CTRT_ADDR(HART_ACMD_CTRT_ADDR),
				.SIM_DELAY(SIM_DELAY)
			)jtag_debug_u(
				.jtag_slave_tck(jtag_slave_tck),
				.jtag_slave_trst_n(jtag_slave_trst_n),
				.jtag_slave_tms(jtag_slave_tms),
				.jtag_slave_tdi(jtag_slave_tdi),
				.jtag_slave_tdo(jtag_slave_tdo),
				
				.dm_aclk(s_axi_aclk),
				.dm_aresetn(dbg_aresetn),
				
				.sys_reset_fns(sys_reset_fns),
				.sw_reset(sw_reset),
				
				.dbg_halt_req(dbg_halt_req),
				.dbg_halt_on_reset_req(dbg_halt_on_reset_req),
				
				.hart_access_wen(hart_access_wen),
				.hart_access_waddr(hart_access_waddr),
				.hart_access_din(hart_access_din),
				
				.hart_access_ren(hart_access_ren),
				.hart_access_raddr(hart_access_raddr),
				.hart_access_dout(hart_access_dout)
			);
		end
		else
		begin
			assign jtag_slave_tdo = 1'b1;
			
			assign sw_reset = 1'b0;
			
			assign dbg_halt_req = 1'b0;
			assign dbg_halt_on_reset_req = 1'b0;
			
			assign hart_access_dout = 32'dx;
		end
	endgenerate
	
	/** BTB存储器 **/
	genvar btb_mem_i;
	generate
		for(btb_mem_i = 0;btb_mem_i < BTB_WAY_N;btb_mem_i = btb_mem_i + 1)
		begin:btb_mem_blk
			bram_true_dual_port #(
				.mem_width(64),
				.mem_depth(BTB_ENTRY_N),
				.INIT_FILE(""),
				.read_write_mode("read_first"),
				.use_output_register("false"),
				.en_byte_write("false"),
				.simulation_delay(SIM_DELAY)
			)btb_mem_u(
				.clk(btb_mem_clka[btb_mem_i]),
				
				.ena(btb_mem_ena[btb_mem_i]),
				.wea(btb_mem_wea[btb_mem_i]),
				.addra(btb_mem_addra[btb_mem_i*16+15:btb_mem_i*16]),
				.dina(btb_mem_dina[btb_mem_i*64+63:btb_mem_i*64]),
				.douta(btb_mem_douta[btb_mem_i*64+63:btb_mem_i*64]),
				
				.enb(btb_mem_enb[btb_mem_i]),
				.web(btb_mem_web[btb_mem_i]),
				.addrb(btb_mem_addrb[btb_mem_i*16+15:btb_mem_i*16]),
				.dinb(btb_mem_dinb[btb_mem_i*64+63:btb_mem_i*64]),
				.doutb(btb_mem_doutb[btb_mem_i*64+63:btb_mem_i*64])
			);
		end
	endgenerate
	
endmodule
