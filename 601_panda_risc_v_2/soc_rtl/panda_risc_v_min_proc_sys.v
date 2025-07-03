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
本模块: 小胖达RISC-V 最小处理器系统

描述:
将小胖达RISC-V的指令总线接到ICB-SRAM控制器, 并接入ITCM

将小胖达RISC-V的数据总线接到ICB一从五主分发器, 
ICB主机#0接ICB-SRAM控制器并接入DTCM, 
ICB主机#1接平台级中断控制器(PLIC), 
ICB主机#2接处理器局部中断控制器(CLINT),
ICB主机#3接ICB到AXI-Lite桥并引出AXI-Lite主机
ICB主机#4接ICB-DCache再通过ICB到AXI-Lite桥引出AXI-Lite主机

注意：
未使用的外部中断请求信号必须接1'b0

协议:
AXI MASTER
MEM MASTER

作者: 陈家耀
日期: 2025/02/13
********************************************************************/

module panda_risc_v_min_proc_sys #(
	// 数据Cache配置
	parameter EN_DCACHE = "false", // 是否使用DCACHE
	parameter EN_DTCM = "true", // 是否启用DTCM
	parameter integer DCACHE_WAY_N = 2, // 缓存路数(1 | 2 | 4 | 8)
	parameter integer DCACHE_ENTRY_N = 1024, // 缓存存储条目数
	parameter integer DCACHE_LINE_WORD_N = 2, // 每个缓存行的字数(1 | 2 | 4 | 8 | 16)
	parameter integer DCACHE_TAG_WIDTH = 10, // 缓存标签位数
	parameter integer DCACHE_WBUF_ITEM_N = 2, // 写缓存最多可存的缓存行个数(1~8)
    // 是否使用ITCM/DTCM的字节使能信号
    parameter EN_ITCM_DTCM_BYTE_WR = "false",
	// 指令总线控制单元配置
	parameter integer IBUS_ACCESS_TIMEOUT_TH = 16, // 指令总线访问超时周期数(0 -> 不设超时 | 正整数)
	// LSU配置
	parameter integer DBUS_ACCESS_TIMEOUT_TH = 1024, // 数据总线访问超时周期数(必须>=1)
	// CSR配置
	parameter EN_EXPT_VEC_VECTORED = "false", // 是否使能异常处理的向量链接模式
	parameter EN_PERF_MONITOR = "true", // 是否使能性能监测相关的CSR
	// 总线控制单元配置
	parameter imem_baseaddr = 32'h0000_0000, // 指令存储器基址
	parameter integer imem_addr_range = 16 * 1024, // 指令存储器地址区间长度
	parameter dm_regs_baseaddr = 32'hFFFF_F800, // DM寄存器区基址
	parameter integer dm_regs_addr_range = 1024, // DM寄存器区地址区间长度
	parameter dmem_baseaddr = 32'h1000_0000, // 数据存储器基地址
	parameter integer dmem_addr_range = 16 * 1024, // 数据存储器地址区间长度
	parameter plic_baseaddr = 32'hF000_0000, // PLIC基址
	parameter integer plic_addr_range = 4 * 1024 * 1024, // PLIC地址区间长度
	parameter clint_baseaddr = 32'hF400_0000, // CLINT基址
	parameter integer clint_addr_range = 64 * 1024 * 1024, // CLINT地址区间长度
	parameter ext_peripheral_baseaddr = 32'h4000_0000, // 拓展外设总线基地址
	parameter integer ext_peripheral_addr_range = 16 * 4096, // 拓展外设总线地址区间长度
	parameter ext_mem_baseaddr = 32'h6000_0000, // 拓展存储总线基地址
	parameter integer ext_mem_addr_range = 8 * 1024 * 1024, // 拓展存储总线地址区间长度
	// 指令/数据ICB主机AXIS寄存器片配置
	parameter EN_INST_CMD_FWD = "false", // 是否使能指令ICB主机命令通道前向寄存器
	parameter EN_INST_RSP_BCK = "false", // 是否使能指令ICB主机响应通道后向寄存器
	parameter EN_DATA_CMD_FWD = "false", // 是否使能数据ICB主机命令通道前向寄存器
	parameter EN_DATA_RSP_BCK = "false", // 是否使能数据ICB主机响应通道后向寄存器
	// 指令存储器配置
	parameter imem_init_file = "no_init", // 指令存储器初始化文件路径
	parameter imem_init_file_b0 = "no_init", // 指令存储器初始化文件路径(字节#0)
	parameter imem_init_file_b1 = "no_init", // 指令存储器初始化文件路径(字节#1)
	parameter imem_init_file_b2 = "no_init", // 指令存储器初始化文件路径(字节#2)
	parameter imem_init_file_b3 = "no_init", // 指令存储器初始化文件路径(字节#3)
	// 乘法器配置
	parameter EN_SGN_PERIOD_MUL = "true", // 是否使用单周期乘法器
	// RTC预分频系数
	parameter integer rtc_psc_r = 50 * 1000000,
	// 调试配置
	parameter DEBUG_SUPPORTED = "true", // 是否需要支持Debug
	parameter DEBUG_ROM_ADDR = 32'h0000_0600, // Debug ROM基地址
	parameter integer DSCRATCH_N = 2, // dscratch寄存器的个数(1 | 2)
	// 仿真配置
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟
	input wire clk,
	// 系统复位输入
	input wire sys_resetn,
	
	// 系统复位请求
	input wire sys_reset_req,
	
	// 复位时的PC
	input wire[31:0] rst_pc,
	
	// 实时时钟计数使能
	input wire rtc_en,
	
	// 扩展外设总线(AXI-Lite主机)
	// 读地址通道
    output wire[31:0] m_axi_dbus_araddr,
	output wire[1:0] m_axi_dbus_arburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_dbus_arlen, // const -> 8'd0
    output wire[2:0] m_axi_dbus_arsize, // const -> 3'b010
	output wire[3:0] m_axi_dbus_arcache, // const -> 4'b0011
    output wire m_axi_dbus_arvalid,
    input wire m_axi_dbus_arready,
    // 写地址通道
    output wire[31:0] m_axi_dbus_awaddr,
    output wire[1:0] m_axi_dbus_awburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_dbus_awlen, // const -> 8'd0
    output wire[2:0] m_axi_dbus_awsize, // const -> 3'b010
	output wire[3:0] m_axi_dbus_awcache, // const -> 4'b0011
    output wire m_axi_dbus_awvalid,
    input wire m_axi_dbus_awready,
    // 写响应通道
    // 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
    input wire[1:0] m_axi_dbus_bresp,
    input wire m_axi_dbus_bvalid,
    output wire m_axi_dbus_bready,
    // 读数据通道
    input wire[31:0] m_axi_dbus_rdata,
    // 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
    input wire[1:0] m_axi_dbus_rresp,
	input wire m_axi_dbus_rlast, // ignored
    input wire m_axi_dbus_rvalid,
    output wire m_axi_dbus_rready,
    // 写数据通道
    output wire[31:0] m_axi_dbus_wdata,
    output wire[3:0] m_axi_dbus_wstrb,
	output wire m_axi_dbus_wlast, // const -> 1'b1
    output wire m_axi_dbus_wvalid,
    input wire m_axi_dbus_wready,
	
	// 数据Cache总线(AXI主机)
	// 读地址通道
    output wire[31:0] m_axi_dcache_araddr,
	output wire[1:0] m_axi_dcache_arburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_dcache_arlen, // const -> DCACHE_LINE_WORD_N - 1
    output wire[2:0] m_axi_dcache_arsize, // const -> 3'b010
	output wire[3:0] m_axi_dcache_arcache, // const -> 4'b0011
    output wire m_axi_dcache_arvalid,
    input wire m_axi_dcache_arready,
    // 写地址通道
    output wire[31:0] m_axi_dcache_awaddr,
    output wire[1:0] m_axi_dcache_awburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_dcache_awlen, // const -> DCACHE_LINE_WORD_N - 1
    output wire[2:0] m_axi_dcache_awsize, // const -> 3'b010
	output wire[3:0] m_axi_dcache_awcache, // const -> 4'b0011
    output wire m_axi_dcache_awvalid,
    input wire m_axi_dcache_awready,
    // 写响应通道
    // 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
    input wire[1:0] m_axi_dcache_bresp,
    input wire m_axi_dcache_bvalid,
    output wire m_axi_dcache_bready,
    // 读数据通道
    input wire[31:0] m_axi_dcache_rdata,
    // 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
    input wire[1:0] m_axi_dcache_rresp,
	input wire m_axi_dcache_rlast, // ignored
    input wire m_axi_dcache_rvalid,
    output wire m_axi_dcache_rready,
    // 写数据通道
    output wire[31:0] m_axi_dcache_wdata,
    output wire[3:0] m_axi_dcache_wstrb,
	output wire m_axi_dcache_wlast,
    output wire m_axi_dcache_wvalid,
    input wire m_axi_dcache_wready,
	
	// 外部中断请求向量
	// 注意: 中断请求保持有效直到中断清零!
	input wire[62:0] ext_itr_req_vec,
	
	// HART对DM内容的访问(存储器主接口)
	output wire hart_access_en,
	output wire[3:0] hart_access_wen,
	output wire[29:0] hart_access_addr,
	output wire[31:0] hart_access_din,
	input wire[31:0] hart_access_dout,
	
	// 调试控制
	input wire dbg_halt_req, // 来自调试器的暂停请求
	input wire dbg_halt_on_reset_req, // 来自调试器的复位释放后暂停请求
	
	// 错误标志
	output wire clr_inst_buf_while_suppressing, // 在镇压ICB事务时清空指令缓存(错误标志)
	output wire ibus_timeout, // 指令总线访问超时(错误标志)
	output wire dbus_timeout // 数据总线访问超时(错误标志)
);
	
	/** 小胖达RISC-V CPU核 **/
	// 指令ICB主机
	wire[31:0] m_icb_cmd_inst_addr;
	wire m_icb_cmd_inst_read;
	wire[31:0] m_icb_cmd_inst_wdata;
	wire[3:0] m_icb_cmd_inst_wmask;
	wire m_icb_cmd_inst_valid;
	wire m_icb_cmd_inst_ready;
	wire[31:0] m_icb_rsp_inst_rdata;
	wire m_icb_rsp_inst_err;
	wire m_icb_rsp_inst_valid;
	wire m_icb_rsp_inst_ready;
	// 数据ICB主机
	wire[31:0] m_icb_cmd_data_addr;
	wire m_icb_cmd_data_read;
	wire[31:0] m_icb_cmd_data_wdata;
	wire[3:0] m_icb_cmd_data_wmask;
	wire m_icb_cmd_data_valid;
	wire m_icb_cmd_data_ready;
	wire[31:0] m_icb_rsp_data_rdata;
	wire m_icb_rsp_data_err;
	wire m_icb_rsp_data_valid;
	wire m_icb_rsp_data_ready;
	// BTB存储器
	// [端口A]
	wire[2-1:0] btb_mem_clka;
	wire[2-1:0] btb_mem_ena;
	wire[2-1:0] btb_mem_wea;
	wire[2*16-1:0] btb_mem_addra;
	wire[2*64-1:0] btb_mem_dina;
	wire[2*64-1:0] btb_mem_douta;
	// [端口B]
	wire[2-1:0] btb_mem_clkb;
	wire[2-1:0] btb_mem_enb;
	wire[2-1:0] btb_mem_web;
	wire[2*16-1:0] btb_mem_addrb;
	wire[2*64-1:0] btb_mem_dinb;
	wire[2*64-1:0] btb_mem_doutb;
	// 中断请求
	wire sw_itr_req; // 软件中断请求
	wire tmr_itr_req; // 计时器中断请求
	wire ext_itr_req; // 外部中断请求
	
	panda_risc_v_core #(
		.EN_INST_CMD_FWD(EN_INST_CMD_FWD),
		.EN_INST_RSP_BCK(EN_INST_RSP_BCK),
		.EN_DATA_CMD_FWD(EN_DATA_CMD_FWD),
		.EN_DATA_RSP_BCK(EN_DATA_RSP_BCK),
		.IMEM_BASEADDR(imem_baseaddr),
		.IMEM_ADDR_RANGE(imem_addr_range),
		.DM_REGS_BASEADDR(dm_regs_baseaddr),
		.DM_REGS_ADDR_RANGE(dm_regs_addr_range),
		.IBUS_ACCESS_TIMEOUT_TH(IBUS_ACCESS_TIMEOUT_TH),
		.IBUS_OUTSTANDING_N(4),
		.DBUS_ACCESS_TIMEOUT_TH(DBUS_ACCESS_TIMEOUT_TH),
		.GHR_WIDTH(8),
		.BTB_WAY_N(2),
		.BTB_ENTRY_N(512),
		.RAS_ENTRY_N(4),
		.DEBUG_SUPPORTED(DEBUG_SUPPORTED),
		.DEBUG_ROM_ADDR(DEBUG_ROM_ADDR),
		.DSCRATCH_N(DSCRATCH_N),
		.EN_EXPT_VEC_VECTORED(EN_EXPT_VEC_VECTORED),
		.EN_PERF_MONITOR(EN_PERF_MONITOR),
		.EN_SGN_PERIOD_MUL(EN_SGN_PERIOD_MUL),
		.ROB_ENTRY_N(8),
		.CSR_RW_RCD_SLOTS_N(2),
		.SIM_DELAY(simulation_delay)
	)panda_risc_v_core_u(
		.aclk(clk),
		.aresetn(sys_resetn),
		
		.sys_reset_req(sys_reset_req),
		.rst_pc(rst_pc),
		
		.m_icb_cmd_inst_addr(m_icb_cmd_inst_addr),
		.m_icb_cmd_inst_read(m_icb_cmd_inst_read),
		.m_icb_cmd_inst_wdata(m_icb_cmd_inst_wdata),
		.m_icb_cmd_inst_wmask(m_icb_cmd_inst_wmask),
		.m_icb_cmd_inst_valid(m_icb_cmd_inst_valid),
		.m_icb_cmd_inst_ready(m_icb_cmd_inst_ready),
		.m_icb_rsp_inst_rdata(m_icb_rsp_inst_rdata),
		.m_icb_rsp_inst_err(m_icb_rsp_inst_err),
		.m_icb_rsp_inst_valid(m_icb_rsp_inst_valid),
		.m_icb_rsp_inst_ready(m_icb_rsp_inst_ready),
		
		.m_icb_cmd_data_addr(m_icb_cmd_data_addr),
		.m_icb_cmd_data_read(m_icb_cmd_data_read),
		.m_icb_cmd_data_wdata(m_icb_cmd_data_wdata),
		.m_icb_cmd_data_wmask(m_icb_cmd_data_wmask),
		.m_icb_cmd_data_valid(m_icb_cmd_data_valid),
		.m_icb_cmd_data_ready(m_icb_cmd_data_ready),
		.m_icb_rsp_data_rdata(m_icb_rsp_data_rdata),
		.m_icb_rsp_data_err(m_icb_rsp_data_err),
		.m_icb_rsp_data_valid(m_icb_rsp_data_valid),
		.m_icb_rsp_data_ready(m_icb_rsp_data_ready),
		
		.btb_mem_clka(btb_mem_clka),
		.btb_mem_ena(btb_mem_ena),
		.btb_mem_wea(btb_mem_wea),
		.btb_mem_addra(btb_mem_addra),
		.btb_mem_dina(btb_mem_dina),
		.btb_mem_douta(btb_mem_douta),
		.btb_mem_clkb(btb_mem_clkb),
		.btb_mem_enb(btb_mem_enb),
		.btb_mem_web(btb_mem_web),
		.btb_mem_addrb(btb_mem_addrb),
		.btb_mem_dinb(btb_mem_dinb),
		.btb_mem_doutb(btb_mem_doutb),
		
		.sw_itr_req(sw_itr_req),
		.tmr_itr_req(tmr_itr_req),
		.ext_itr_req(ext_itr_req),
		
		.dbg_halt_req(dbg_halt_req),
		.dbg_halt_on_reset_req(dbg_halt_on_reset_req),
		
		.clr_inst_buf_while_suppressing(clr_inst_buf_while_suppressing),
		.ibus_timeout(ibus_timeout),
		.dbus_timeout(dbus_timeout)
	);
	
	/** BTB存储器 **/
	genvar btb_mem_i;
	generate
		for(btb_mem_i = 0;btb_mem_i < 2;btb_mem_i = btb_mem_i + 1)
		begin:btb_mem_blk
			bram_true_dual_port #(
				.mem_width(64),
				.mem_depth(512),
				.INIT_FILE("no_init"),
				.read_write_mode("read_first"),
				.use_output_register("false"),
				.simulation_delay(simulation_delay)
			)btb_mem_u(
				.clk(clk),
				
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
	
	/** ICB-SRAM控制器 **/
	// ICB从机
	// 命令通道
	wire[31:0] s_icb_imem_ctrler_cmd_addr;
	wire s_icb_imem_ctrler_cmd_read;
	wire[31:0] s_icb_imem_ctrler_cmd_wdata;
	wire[3:0] s_icb_imem_ctrler_cmd_wmask;
	wire s_icb_imem_ctrler_cmd_valid;
	wire s_icb_imem_ctrler_cmd_ready;
	// 响应通道
	wire[31:0] s_icb_imem_ctrler_rsp_rdata;
	wire s_icb_imem_ctrler_rsp_err;
	wire s_icb_imem_ctrler_rsp_valid;
	wire s_icb_imem_ctrler_rsp_ready;
	// ITCM与DM寄存器区选择
	wire itcm_sel;
	reg itcm_sel_d;
	// SRAM存储器主接口
	wire imem_clk;
    wire imem_rst;
    wire imem_en;
    wire[3:0] imem_wen;
    wire[29:0] imem_addr;
    wire[31:0] imem_din;
    wire[31:0] imem_dout;
	
	assign s_icb_imem_ctrler_cmd_addr = m_icb_cmd_inst_addr;
	assign s_icb_imem_ctrler_cmd_read = m_icb_cmd_inst_read;
	assign s_icb_imem_ctrler_cmd_wdata = m_icb_cmd_inst_wdata;
	assign s_icb_imem_ctrler_cmd_wmask = m_icb_cmd_inst_wmask;
	assign s_icb_imem_ctrler_cmd_valid = m_icb_cmd_inst_valid;
	assign m_icb_cmd_inst_ready = s_icb_imem_ctrler_cmd_ready;
	assign m_icb_rsp_inst_rdata = s_icb_imem_ctrler_rsp_rdata;
	assign m_icb_rsp_inst_err = s_icb_imem_ctrler_rsp_err;
	assign m_icb_rsp_inst_valid = s_icb_imem_ctrler_rsp_valid;
	assign s_icb_imem_ctrler_rsp_ready = m_icb_rsp_inst_ready;
	
	assign itcm_sel = 
		(DEBUG_SUPPORTED == "false") | 
		(({imem_addr, 2'b00} >= imem_baseaddr) & ({imem_addr, 2'b00} < (imem_baseaddr + imem_addr_range)));
	
	always @(posedge clk)
	begin
		itcm_sel_d <= # simulation_delay itcm_sel;
	end
	
	icb_sram_ctrler #(
		.en_unaligned_transfer("true"),
		.wt_trans_imdt_resp("false"),
		.simulation_delay(simulation_delay)
	)imem_ctrler_u(
		.s_icb_aclk(clk),
		.s_icb_aresetn(sys_resetn),
		
		.s_icb_cmd_addr(s_icb_imem_ctrler_cmd_addr),
		.s_icb_cmd_read(s_icb_imem_ctrler_cmd_read),
		.s_icb_cmd_wdata(s_icb_imem_ctrler_cmd_wdata),
		.s_icb_cmd_wmask(s_icb_imem_ctrler_cmd_wmask),
		.s_icb_cmd_valid(s_icb_imem_ctrler_cmd_valid),
		.s_icb_cmd_ready(s_icb_imem_ctrler_cmd_ready),
		.s_icb_rsp_rdata(s_icb_imem_ctrler_rsp_rdata),
		.s_icb_rsp_err(s_icb_imem_ctrler_rsp_err),
		.s_icb_rsp_valid(s_icb_imem_ctrler_rsp_valid),
		.s_icb_rsp_ready(s_icb_imem_ctrler_rsp_ready),
		
		.bram_clk(imem_clk),
		.bram_rst(imem_rst),
		.bram_en(imem_en),
		.bram_wen(imem_wen),
		.bram_addr(imem_addr),
		.bram_din(imem_din),
		.bram_dout(imem_dout)
	);
	
	/** 指令存储器 **/
	wire itcm_en;
    wire[3:0] itcm_wen;
    wire[29:0] itcm_addr;
    wire[31:0] itcm_din;
    wire[31:0] itcm_dout;
	
	assign hart_access_en = imem_en & (~itcm_sel);
	assign hart_access_wen = imem_wen;
	assign hart_access_addr = imem_addr;
	assign hart_access_din = imem_din;
	
	assign itcm_en = imem_en & itcm_sel;
	assign itcm_wen = imem_wen;
	assign itcm_addr = imem_addr;
	assign itcm_din = imem_din;
	
	assign imem_dout = ((DEBUG_SUPPORTED == "false") | itcm_sel_d) ? itcm_dout:hart_access_dout;
	
	generate
	    if(EN_ITCM_DTCM_BYTE_WR == "false")
	    begin
            bram_single_port #(
                .style("LOW_LATENCY"),
                .rw_mode("no_change"),
                .mem_width(8),
                .mem_depth(imem_addr_range / 4),
                .INIT_FILE(imem_init_file_b0),
				.byte_write_mode("false"),
                .simulation_delay(simulation_delay)
            )imem_u0(
                .clk(imem_clk),
                
                .en(itcm_en),
                .wen(itcm_wen[0]),
                .addr(itcm_addr),
                .din(itcm_din[7:0]),
                .dout(itcm_dout[7:0])
            );
            bram_single_port #(
                .style("LOW_LATENCY"),
                .rw_mode("no_change"),
                .mem_width(8),
                .mem_depth(imem_addr_range / 4),
                .INIT_FILE(imem_init_file_b1),
				.byte_write_mode("false"),
                .simulation_delay(simulation_delay)
            )imem_u1(
                .clk(imem_clk),
                
                .en(itcm_en),
                .wen(itcm_wen[1]),
                .addr(itcm_addr),
                .din(itcm_din[15:8]),
                .dout(itcm_dout[15:8])
            );
            bram_single_port #(
                .style("LOW_LATENCY"),
                .rw_mode("no_change"),
                .mem_width(8),
                .mem_depth(imem_addr_range / 4),
                .INIT_FILE(imem_init_file_b2),
				.byte_write_mode("false"),
                .simulation_delay(simulation_delay)
            )imem_u2(
                .clk(imem_clk),
                
                .en(itcm_en),
                .wen(itcm_wen[2]),
                .addr(itcm_addr),
                .din(itcm_din[23:16]),
                .dout(itcm_dout[23:16])
            );
            bram_single_port #(
                .style("LOW_LATENCY"),
                .rw_mode("no_change"),
                .mem_width(8),
                .mem_depth(imem_addr_range / 4),
                .INIT_FILE(imem_init_file_b3),
				.byte_write_mode("false"),
                .simulation_delay(simulation_delay)
            )imem_u3(
                .clk(imem_clk),
                
                .en(itcm_en),
                .wen(itcm_wen[3]),
                .addr(itcm_addr),
                .din(itcm_din[31:24]),
                .dout(itcm_dout[31:24])
            );
		end
		else
		begin
	        bram_single_port #(
                .style("LOW_LATENCY"),
                .rw_mode("read_first"),
                .mem_width(32),
                .mem_depth(imem_addr_range / 4),
                .INIT_FILE(imem_init_file),
				.byte_write_mode("true"),
                .simulation_delay(simulation_delay)
            )imem_u(
                .clk(imem_clk),
                
                .en(itcm_en),
                .wen(itcm_wen),
                .addr(itcm_addr),
                .din(itcm_din),
                .dout(itcm_dout)
            );
		end
	endgenerate
	
	/** ICB一从五主分发器 **/
	// ICB从机
	// 命令通道
	wire[31:0] s_icb_dstb_cmd_addr;
	wire s_icb_dstb_cmd_read;
	wire[31:0] s_icb_dstb_cmd_wdata;
	wire[3:0] s_icb_dstb_cmd_wmask;
	wire s_icb_dstb_cmd_valid;
	wire s_icb_dstb_cmd_ready;
	// 响应通道
	wire[31:0] s_icb_dstb_rsp_rdata;
	wire s_icb_dstb_rsp_err;
	wire s_icb_dstb_rsp_valid;
	wire s_icb_dstb_rsp_ready;
	// ICB主机#0
	// 命令通道
	wire[31:0] m0_icb_dstb_cmd_addr;
	wire m0_icb_dstb_cmd_read;
	wire[31:0] m0_icb_dstb_cmd_wdata;
	wire[3:0] m0_icb_dstb_cmd_wmask;
	wire m0_icb_dstb_cmd_valid;
	wire m0_icb_dstb_cmd_ready;
	// 响应通道
	wire[31:0] m0_icb_dstb_rsp_rdata;
	wire m0_icb_dstb_rsp_err;
	wire m0_icb_dstb_rsp_valid;
	wire m0_icb_dstb_rsp_ready;
	// ICB主机#1
	// 命令通道
	wire[31:0] m1_icb_dstb_cmd_addr;
	wire m1_icb_dstb_cmd_read;
	wire[31:0] m1_icb_dstb_cmd_wdata;
	wire[3:0] m1_icb_dstb_cmd_wmask;
	wire m1_icb_dstb_cmd_valid;
	wire m1_icb_dstb_cmd_ready;
	// 响应通道
	wire[31:0] m1_icb_dstb_rsp_rdata;
	wire m1_icb_dstb_rsp_err;
	wire m1_icb_dstb_rsp_valid;
	wire m1_icb_dstb_rsp_ready;
	// ICB主机#2
	// 命令通道
	wire[31:0] m2_icb_dstb_cmd_addr;
	wire m2_icb_dstb_cmd_read;
	wire[31:0] m2_icb_dstb_cmd_wdata;
	wire[3:0] m2_icb_dstb_cmd_wmask;
	wire m2_icb_dstb_cmd_valid;
	wire m2_icb_dstb_cmd_ready;
	// 响应通道
	wire[31:0] m2_icb_dstb_rsp_rdata;
	wire m2_icb_dstb_rsp_err;
	wire m2_icb_dstb_rsp_valid;
	wire m2_icb_dstb_rsp_ready;
	// ICB主机#3
	// 命令通道
	wire[31:0] m3_icb_dstb_cmd_addr;
	wire m3_icb_dstb_cmd_read;
	wire[31:0] m3_icb_dstb_cmd_wdata;
	wire[3:0] m3_icb_dstb_cmd_wmask;
	wire m3_icb_dstb_cmd_valid;
	wire m3_icb_dstb_cmd_ready;
	// 响应通道
	wire[31:0] m3_icb_dstb_rsp_rdata;
	wire m3_icb_dstb_rsp_err;
	wire m3_icb_dstb_rsp_valid;
	wire m3_icb_dstb_rsp_ready;
	// ICB主机#4
	// 命令通道
	wire[31:0] m4_icb_dstb_cmd_addr;
	wire m4_icb_dstb_cmd_read;
	wire[31:0] m4_icb_dstb_cmd_wdata;
	wire[3:0] m4_icb_dstb_cmd_wmask;
	wire m4_icb_dstb_cmd_valid;
	wire m4_icb_dstb_cmd_ready;
	// 响应通道
	wire[31:0] m4_icb_dstb_rsp_rdata;
	wire m4_icb_dstb_rsp_err;
	wire m4_icb_dstb_rsp_valid;
	wire m4_icb_dstb_rsp_ready;
	
	assign s_icb_dstb_cmd_addr = m_icb_cmd_data_addr;
	assign s_icb_dstb_cmd_read = m_icb_cmd_data_read;
	assign s_icb_dstb_cmd_wdata = m_icb_cmd_data_wdata;
	assign s_icb_dstb_cmd_wmask = m_icb_cmd_data_wmask;
	assign s_icb_dstb_cmd_valid = m_icb_cmd_data_valid;
	assign m_icb_cmd_data_ready = s_icb_dstb_cmd_ready;
	assign m_icb_rsp_data_rdata = s_icb_dstb_rsp_rdata;
	assign m_icb_rsp_data_err = s_icb_dstb_rsp_err;
	assign m_icb_rsp_data_valid = s_icb_dstb_rsp_valid;
	assign s_icb_dstb_rsp_ready = m_icb_rsp_data_ready;
	
	icb_1s_to_5m #(
		.m0_baseaddr(dmem_baseaddr),
		.m0_addr_range(dmem_addr_range),
		.m1_baseaddr(plic_baseaddr),
		.m1_addr_range(plic_addr_range),
		.m2_baseaddr(clint_baseaddr),
		.m2_addr_range(clint_addr_range),
		.m3_baseaddr(ext_peripheral_baseaddr),
		.m3_addr_range(ext_peripheral_addr_range),
		.m4_baseaddr(ext_mem_baseaddr),
		.m4_addr_range(ext_mem_addr_range),
		.simulation_delay(simulation_delay)
	)icb_1s_to_5m_u(
		.clk(clk),
		.resetn(sys_resetn),
		
		.s_icb_cmd_addr(s_icb_dstb_cmd_addr),
		.s_icb_cmd_read(s_icb_dstb_cmd_read),
		.s_icb_cmd_wdata(s_icb_dstb_cmd_wdata),
		.s_icb_cmd_wmask(s_icb_dstb_cmd_wmask),
		.s_icb_cmd_valid(s_icb_dstb_cmd_valid),
		.s_icb_cmd_ready(s_icb_dstb_cmd_ready),
		.s_icb_rsp_rdata(s_icb_dstb_rsp_rdata),
		.s_icb_rsp_err(s_icb_dstb_rsp_err),
		.s_icb_rsp_valid(s_icb_dstb_rsp_valid),
		.s_icb_rsp_ready(s_icb_dstb_rsp_ready),
		
		.m0_icb_cmd_addr(m0_icb_dstb_cmd_addr),
		.m0_icb_cmd_read(m0_icb_dstb_cmd_read),
		.m0_icb_cmd_wdata(m0_icb_dstb_cmd_wdata),
		.m0_icb_cmd_wmask(m0_icb_dstb_cmd_wmask),
		.m0_icb_cmd_valid(m0_icb_dstb_cmd_valid),
		.m0_icb_cmd_ready(m0_icb_dstb_cmd_ready),
		.m0_icb_rsp_rdata(m0_icb_dstb_rsp_rdata),
		.m0_icb_rsp_err(m0_icb_dstb_rsp_err),
		.m0_icb_rsp_valid(m0_icb_dstb_rsp_valid),
		.m0_icb_rsp_ready(m0_icb_dstb_rsp_ready),
		
		.m1_icb_cmd_addr(m1_icb_dstb_cmd_addr),
		.m1_icb_cmd_read(m1_icb_dstb_cmd_read),
		.m1_icb_cmd_wdata(m1_icb_dstb_cmd_wdata),
		.m1_icb_cmd_wmask(m1_icb_dstb_cmd_wmask),
		.m1_icb_cmd_valid(m1_icb_dstb_cmd_valid),
		.m1_icb_cmd_ready(m1_icb_dstb_cmd_ready),
		.m1_icb_rsp_rdata(m1_icb_dstb_rsp_rdata),
		.m1_icb_rsp_err(m1_icb_dstb_rsp_err),
		.m1_icb_rsp_valid(m1_icb_dstb_rsp_valid),
		.m1_icb_rsp_ready(m1_icb_dstb_rsp_ready),
		
		.m2_icb_cmd_addr(m2_icb_dstb_cmd_addr),
		.m2_icb_cmd_read(m2_icb_dstb_cmd_read),
		.m2_icb_cmd_wdata(m2_icb_dstb_cmd_wdata),
		.m2_icb_cmd_wmask(m2_icb_dstb_cmd_wmask),
		.m2_icb_cmd_valid(m2_icb_dstb_cmd_valid),
		.m2_icb_cmd_ready(m2_icb_dstb_cmd_ready),
		.m2_icb_rsp_rdata(m2_icb_dstb_rsp_rdata),
		.m2_icb_rsp_err(m2_icb_dstb_rsp_err),
		.m2_icb_rsp_valid(m2_icb_dstb_rsp_valid),
		.m2_icb_rsp_ready(m2_icb_dstb_rsp_ready),
		
		.m3_icb_cmd_addr(m3_icb_dstb_cmd_addr),
		.m3_icb_cmd_read(m3_icb_dstb_cmd_read),
		.m3_icb_cmd_wdata(m3_icb_dstb_cmd_wdata),
		.m3_icb_cmd_wmask(m3_icb_dstb_cmd_wmask),
		.m3_icb_cmd_valid(m3_icb_dstb_cmd_valid),
		.m3_icb_cmd_ready(m3_icb_dstb_cmd_ready),
		.m3_icb_rsp_rdata(m3_icb_dstb_rsp_rdata),
		.m3_icb_rsp_err(m3_icb_dstb_rsp_err),
		.m3_icb_rsp_valid(m3_icb_dstb_rsp_valid),
		.m3_icb_rsp_ready(m3_icb_dstb_rsp_ready),
		
		.m4_icb_cmd_addr(m4_icb_dstb_cmd_addr),
		.m4_icb_cmd_read(m4_icb_dstb_cmd_read),
		.m4_icb_cmd_wdata(m4_icb_dstb_cmd_wdata),
		.m4_icb_cmd_wmask(m4_icb_dstb_cmd_wmask),
		.m4_icb_cmd_valid(m4_icb_dstb_cmd_valid),
		.m4_icb_cmd_ready(m4_icb_dstb_cmd_ready),
		.m4_icb_rsp_rdata(m4_icb_dstb_rsp_rdata),
		.m4_icb_rsp_err(m4_icb_dstb_rsp_err),
		.m4_icb_rsp_valid(m4_icb_dstb_rsp_valid),
		.m4_icb_rsp_ready(m4_icb_dstb_rsp_ready)
	);
	
	/** ICB-SRAM控制器 **/
	// ICB从机
	// 命令通道
	wire[31:0] s_icb_dmem_ctrler_cmd_addr;
	wire s_icb_dmem_ctrler_cmd_read;
	wire[31:0] s_icb_dmem_ctrler_cmd_wdata;
	wire[3:0] s_icb_dmem_ctrler_cmd_wmask;
	wire s_icb_dmem_ctrler_cmd_valid;
	wire s_icb_dmem_ctrler_cmd_ready;
	// 响应通道
	wire[31:0] s_icb_dmem_ctrler_rsp_rdata;
	wire s_icb_dmem_ctrler_rsp_err;
	wire s_icb_dmem_ctrler_rsp_valid;
	wire s_icb_dmem_ctrler_rsp_ready;
	// SRAM存储器主接口
	wire dmem_clk;
    wire dmem_rst;
    wire dmem_en;
    wire[3:0] dmem_wen;
    wire[29:0] dmem_addr;
    wire[31:0] dmem_din;
    wire[31:0] dmem_dout;
	
	generate
		if(EN_DTCM == "true")
		begin
			assign s_icb_dmem_ctrler_cmd_addr = m0_icb_dstb_cmd_addr;
			assign s_icb_dmem_ctrler_cmd_read = m0_icb_dstb_cmd_read;
			assign s_icb_dmem_ctrler_cmd_wdata = m0_icb_dstb_cmd_wdata;
			assign s_icb_dmem_ctrler_cmd_wmask = m0_icb_dstb_cmd_wmask;
			assign s_icb_dmem_ctrler_cmd_valid = m0_icb_dstb_cmd_valid;
			assign m0_icb_dstb_cmd_ready = s_icb_dmem_ctrler_cmd_ready;
			assign m0_icb_dstb_rsp_rdata = s_icb_dmem_ctrler_rsp_rdata;
			assign m0_icb_dstb_rsp_err = s_icb_dmem_ctrler_rsp_err;
			assign m0_icb_dstb_rsp_valid = s_icb_dmem_ctrler_rsp_valid;
			assign s_icb_dmem_ctrler_rsp_ready = m0_icb_dstb_rsp_ready;
		end
		else
		begin
			assign m0_icb_dstb_cmd_ready = 1'b1;
			
			assign m0_icb_dstb_rsp_rdata = 32'dx;
			assign m0_icb_dstb_rsp_err = 1'b1;
			assign m0_icb_dstb_rsp_valid = 1'b1;
			
			assign s_icb_dmem_ctrler_cmd_addr = 32'dx;
			assign s_icb_dmem_ctrler_cmd_read = 1'bx;
			assign s_icb_dmem_ctrler_cmd_wdata = 32'dx;
			assign s_icb_dmem_ctrler_cmd_wmask = 4'bxxxx;
			assign s_icb_dmem_ctrler_cmd_valid = 1'b0;
			
			assign s_icb_dmem_ctrler_rsp_ready = 1'b1;
		end
	endgenerate
	
	icb_sram_ctrler #(
		.en_unaligned_transfer("true"),
		.wt_trans_imdt_resp("false"),
		.simulation_delay(simulation_delay)
	)dmem_ctrler_u(
		.s_icb_aclk(clk),
		.s_icb_aresetn(sys_resetn),
		
		.s_icb_cmd_addr(s_icb_dmem_ctrler_cmd_addr),
		.s_icb_cmd_read(s_icb_dmem_ctrler_cmd_read),
		.s_icb_cmd_wdata(s_icb_dmem_ctrler_cmd_wdata),
		.s_icb_cmd_wmask(s_icb_dmem_ctrler_cmd_wmask),
		.s_icb_cmd_valid(s_icb_dmem_ctrler_cmd_valid),
		.s_icb_cmd_ready(s_icb_dmem_ctrler_cmd_ready),
		.s_icb_rsp_rdata(s_icb_dmem_ctrler_rsp_rdata),
		.s_icb_rsp_err(s_icb_dmem_ctrler_rsp_err),
		.s_icb_rsp_valid(s_icb_dmem_ctrler_rsp_valid),
		.s_icb_rsp_ready(s_icb_dmem_ctrler_rsp_ready),
		
		.bram_clk(dmem_clk),
		.bram_rst(dmem_rst),
		.bram_en(dmem_en),
		.bram_wen(dmem_wen),
		.bram_addr(dmem_addr),
		.bram_din(dmem_din),
		.bram_dout(dmem_dout)
	);
	
	/** 数据存储器 **/
	generate
	    if(EN_ITCM_DTCM_BYTE_WR == "false")
	    begin
            bram_single_port #(
                .style("LOW_LATENCY"),
                .rw_mode("no_change"),
                .mem_width(8),
                .mem_depth(dmem_addr_range / 4),
                .INIT_FILE("no_init"),
				.byte_write_mode("false"),
                .simulation_delay(simulation_delay)
            )dmem_u0(
                .clk(dmem_clk),
                
                .en(dmem_en),
                .wen(dmem_wen[0]),
                .addr(dmem_addr),
                .din(dmem_din[7:0]),
                .dout(dmem_dout[7:0])
            );
            bram_single_port #(
                .style("LOW_LATENCY"),
                .rw_mode("no_change"),
                .mem_width(8),
                .mem_depth(dmem_addr_range / 4),
                .INIT_FILE("no_init"),
				.byte_write_mode("false"),
                .simulation_delay(simulation_delay)
            )dmem_u1(
                .clk(dmem_clk),
                
                .en(dmem_en),
                .wen(dmem_wen[1]),
                .addr(dmem_addr),
                .din(dmem_din[15:8]),
                .dout(dmem_dout[15:8])
            );
            bram_single_port #(
                .style("LOW_LATENCY"),
                .rw_mode("no_change"),
                .mem_width(8),
                .mem_depth(dmem_addr_range / 4),
                .INIT_FILE("no_init"),
				.byte_write_mode("false"),
                .simulation_delay(simulation_delay)
            )dmem_u2(
                .clk(dmem_clk),
                
                .en(dmem_en),
                .wen(dmem_wen[2]),
                .addr(dmem_addr),
                .din(dmem_din[23:16]),
                .dout(dmem_dout[23:16])
            );
            bram_single_port #(
                .style("LOW_LATENCY"),
                .rw_mode("no_change"),
                .mem_width(8),
                .mem_depth(dmem_addr_range / 4),
                .INIT_FILE("no_init"),
				.byte_write_mode("false"),
                .simulation_delay(simulation_delay)
            )dmem_u3(
                .clk(dmem_clk),
                
                .en(dmem_en),
                .wen(dmem_wen[3]),
                .addr(dmem_addr),
                .din(dmem_din[31:24]),
                .dout(dmem_dout[31:24])
            );
		end
		else
		begin
		    bram_single_port #(
                .style("LOW_LATENCY"),
                .rw_mode("read_first"),
                .mem_width(32),
                .mem_depth(dmem_addr_range / 4),
                .INIT_FILE("no_init"),
				.byte_write_mode("true"),
                .simulation_delay(simulation_delay)
            )dmem_u(
                .clk(dmem_clk),
                
                .en(dmem_en),
                .wen(dmem_wen),
                .addr(dmem_addr),
                .din(dmem_din),
                .dout(dmem_dout)
            );
		end
	endgenerate
	
	/** 数据Cache **/
	// 处理器核ICB从机
	// [命令通道]
	wire[31:0] s_dcache_icb_cmd_addr;
	wire s_dcache_icb_cmd_read;
	wire[31:0] s_dcache_icb_cmd_wdata;
	wire[3:0] s_dcache_icb_cmd_wmask;
	wire s_dcache_icb_cmd_valid;
	wire s_dcache_icb_cmd_ready;
	// [响应通道]
	wire[31:0] s_dcache_icb_rsp_rdata;
	wire s_dcache_icb_rsp_err; // const -> 1'b0
	wire s_dcache_icb_rsp_valid;
	wire s_dcache_icb_rsp_ready;
	// 访问下级存储器ICB主机
	// [命令通道]
	wire[31:0] m_dcache_icb_cmd_addr;
	wire m_dcache_icb_cmd_read;
	wire[31:0] m_dcache_icb_cmd_wdata;
	wire[3:0] m_dcache_icb_cmd_wmask;
	wire m_dcache_icb_cmd_valid;
	wire m_dcache_icb_cmd_ready;
	// [响应通道]
	wire[31:0] m_dcache_icb_rsp_rdata;
	wire m_dcache_icb_rsp_err; // ignored
	wire m_dcache_icb_rsp_valid;
	wire m_dcache_icb_rsp_ready;
	// 数据存储器接口
	wire[DCACHE_WAY_N-1:0] data_sram_clk_a;
	wire[DCACHE_WAY_N*4*DCACHE_LINE_WORD_N-1:0] data_sram_en_a;
	wire[DCACHE_WAY_N*4*DCACHE_LINE_WORD_N-1:0] data_sram_wen_a;
	wire[DCACHE_WAY_N*4*DCACHE_LINE_WORD_N*32-1:0] data_sram_addr_a;
	wire[DCACHE_WAY_N*4*DCACHE_LINE_WORD_N*8-1:0] data_sram_din_a;
	wire[DCACHE_WAY_N*4*DCACHE_LINE_WORD_N*8-1:0] data_sram_dout_a;
	// 标签存储器接口
	wire[DCACHE_WAY_N-1:0] tag_sram_clk_a;
	wire[DCACHE_WAY_N-1:0] tag_sram_en_a;
	wire[DCACHE_WAY_N-1:0] tag_sram_wen_a;
	wire[DCACHE_WAY_N*32-1:0] tag_sram_addr_a;
	wire[DCACHE_WAY_N*(DCACHE_TAG_WIDTH+2)-1:0] tag_sram_din_a; // {dirty(1位), valid(1位), tag(CACHE_TAG_WIDTH位)}
	wire[DCACHE_WAY_N*(DCACHE_TAG_WIDTH+2)-1:0] tag_sram_dout_a; // {dirty(1位), valid(1位), tag(CACHE_TAG_WIDTH位)}
	// 记录存储器接口
	// [存储器写端口]
	wire hot_sram_clk_a;
	wire hot_sram_wen_a;
	wire[31:0] hot_sram_waddr_a;
	wire[23:0] hot_sram_din_a;
	// [存储器读端口]
	wire hot_sram_clk_b;
	wire hot_sram_ren_b;
	wire[31:0] hot_sram_raddr_b;
	wire[23:0] hot_sram_dout_b;
	
	generate
		if(EN_DCACHE == "true")
		begin
			assign s_dcache_icb_cmd_addr = m4_icb_dstb_cmd_addr;
			assign s_dcache_icb_cmd_read = m4_icb_dstb_cmd_read;
			assign s_dcache_icb_cmd_wdata = m4_icb_dstb_cmd_wdata;
			assign s_dcache_icb_cmd_wmask = m4_icb_dstb_cmd_wmask;
			assign s_dcache_icb_cmd_valid = m4_icb_dstb_cmd_valid;
			assign m4_icb_dstb_cmd_ready = s_dcache_icb_cmd_ready;
			assign m4_icb_dstb_rsp_rdata = s_dcache_icb_rsp_rdata;
			assign m4_icb_dstb_rsp_err = s_dcache_icb_rsp_err;
			assign m4_icb_dstb_rsp_valid = s_dcache_icb_rsp_valid;
			assign s_dcache_icb_rsp_ready = m4_icb_dstb_rsp_ready;
		end
		else
		begin
			assign m4_icb_dstb_cmd_ready = 1'b1;
			
			assign m4_icb_dstb_rsp_rdata = 32'dx;
			assign m4_icb_dstb_rsp_err = 1'b1;
			assign m4_icb_dstb_rsp_valid = 1'b1;
			
			assign s_dcache_icb_cmd_addr = 32'dx;
			assign s_dcache_icb_cmd_read = 1'bx;
			assign s_dcache_icb_cmd_wdata = 32'dx;
			assign s_dcache_icb_cmd_wmask = 4'bxxxx;
			assign s_dcache_icb_cmd_valid = 1'b0;
			
			assign s_dcache_icb_rsp_ready = 1'b1;
			
			assign m_dcache_icb_cmd_ready = 1'b1;
			
			assign m_dcache_icb_rsp_rdata = 32'dx;
			assign m_dcache_icb_rsp_err = 1'b1;
			assign m_dcache_icb_rsp_valid = 1'b1;
		end
	endgenerate
	
	icb_dcache #(
		.CACHE_WAY_N(DCACHE_WAY_N),
		.CACHE_ENTRY_N(DCACHE_ENTRY_N),
		.CACHE_LINE_WORD_N(DCACHE_LINE_WORD_N),
		.CACHE_TAG_WIDTH(DCACHE_TAG_WIDTH),
		.WBUF_ITEM_N(DCACHE_WBUF_ITEM_N),
		.SIM_DELAY(simulation_delay)
	)dcache_u(
		.aclk(clk),
		.aresetn(sys_resetn),
		
		.s_icb_cmd_addr(s_dcache_icb_cmd_addr),
		.s_icb_cmd_read(s_dcache_icb_cmd_read),
		.s_icb_cmd_wdata(s_dcache_icb_cmd_wdata),
		.s_icb_cmd_wmask(s_dcache_icb_cmd_wmask),
		.s_icb_cmd_valid(s_dcache_icb_cmd_valid),
		.s_icb_cmd_ready(s_dcache_icb_cmd_ready),
		.s_icb_rsp_rdata(s_dcache_icb_rsp_rdata),
		.s_icb_rsp_err(s_dcache_icb_rsp_err),
		.s_icb_rsp_valid(s_dcache_icb_rsp_valid),
		.s_icb_rsp_ready(s_dcache_icb_rsp_ready),
		
		.m_icb_cmd_addr(m_dcache_icb_cmd_addr),
		.m_icb_cmd_read(m_dcache_icb_cmd_read),
		.m_icb_cmd_wdata(m_dcache_icb_cmd_wdata),
		.m_icb_cmd_wmask(m_dcache_icb_cmd_wmask),
		.m_icb_cmd_valid(m_dcache_icb_cmd_valid),
		.m_icb_cmd_ready(m_dcache_icb_cmd_ready),
		.m_icb_rsp_rdata(m_dcache_icb_rsp_rdata),
		.m_icb_rsp_err(m_dcache_icb_rsp_err),
		.m_icb_rsp_valid(m_dcache_icb_rsp_valid),
		.m_icb_rsp_ready(m_dcache_icb_rsp_ready),
		
		.data_sram_clk_a(data_sram_clk_a),
		.data_sram_en_a(data_sram_en_a),
		.data_sram_wen_a(data_sram_wen_a),
		.data_sram_addr_a(data_sram_addr_a),
		.data_sram_din_a(data_sram_din_a),
		.data_sram_dout_a(data_sram_dout_a),
		
		.tag_sram_clk_a(tag_sram_clk_a),
		.tag_sram_en_a(tag_sram_en_a),
		.tag_sram_wen_a(tag_sram_wen_a),
		.tag_sram_addr_a(tag_sram_addr_a),
		.tag_sram_din_a(tag_sram_din_a),
		.tag_sram_dout_a(tag_sram_dout_a),
		
		.hot_sram_clk_a(hot_sram_clk_a),
		.hot_sram_wen_a(hot_sram_wen_a),
		.hot_sram_waddr_a(hot_sram_waddr_a),
		.hot_sram_din_a(hot_sram_din_a),
		.hot_sram_clk_b(hot_sram_clk_b),
		.hot_sram_ren_b(hot_sram_ren_b),
		.hot_sram_raddr_b(hot_sram_raddr_b),
		.hot_sram_dout_b(hot_sram_dout_b)
	);
	
	genvar dcache_data_sram_i;
	generate
		for(dcache_data_sram_i = 0;dcache_data_sram_i < DCACHE_WAY_N*4*DCACHE_LINE_WORD_N;dcache_data_sram_i = dcache_data_sram_i + 1)
		begin:data_sram_blk
			bram_single_port #(
				.style("LOW_LATENCY"),
				.rw_mode("read_first"),
				.mem_width(8),
				.mem_depth(DCACHE_ENTRY_N),
				.INIT_FILE("no_init"),
				.byte_write_mode("false"),
				.simulation_delay(simulation_delay)
			)dcache_data_sram_u(
				.clk(data_sram_clk_a[dcache_data_sram_i/(4*DCACHE_LINE_WORD_N)]),
				
				.en(data_sram_en_a[dcache_data_sram_i]),
				.wen(data_sram_wen_a[dcache_data_sram_i]),
				.addr(data_sram_addr_a[dcache_data_sram_i*32+31:dcache_data_sram_i*32]),
				.din(data_sram_din_a[dcache_data_sram_i*8+7:dcache_data_sram_i*8]),
				.dout(data_sram_dout_a[dcache_data_sram_i*8+7:dcache_data_sram_i*8])
			);
		end
	endgenerate
	
	genvar dcache_tag_sram_i;
	generate
		for(dcache_tag_sram_i = 0;dcache_tag_sram_i < DCACHE_WAY_N;dcache_tag_sram_i = dcache_tag_sram_i + 1)
		begin:tag_sram_blk
			bram_single_port #(
				.style("LOW_LATENCY"),
				.rw_mode("read_first"),
				.mem_width(DCACHE_TAG_WIDTH+2),
				.mem_depth(DCACHE_ENTRY_N),
				.INIT_FILE(""),
				.byte_write_mode("false"),
				.simulation_delay(simulation_delay)
			)dcache_tag_sram_u(
				.clk(tag_sram_clk_a[dcache_tag_sram_i]),
				
				.en(tag_sram_en_a[dcache_tag_sram_i]),
				.wen(tag_sram_wen_a[dcache_tag_sram_i]),
				.addr(tag_sram_addr_a[dcache_tag_sram_i*32+31:dcache_tag_sram_i*32]),
				.din(tag_sram_din_a[(dcache_tag_sram_i+1)*(DCACHE_TAG_WIDTH+2)-1:dcache_tag_sram_i*(DCACHE_TAG_WIDTH+2)]),
				.dout(tag_sram_dout_a[(dcache_tag_sram_i+1)*(DCACHE_TAG_WIDTH+2)-1:dcache_tag_sram_i*(DCACHE_TAG_WIDTH+2)])
			);
		end
	endgenerate
	
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(24),
		.mem_depth(DCACHE_ENTRY_N),
		.INIT_FILE(""),
		.simulation_delay(simulation_delay)
	)dcache_hot_sram_u(
		.clk(hot_sram_clk_a),
		
		.wen_a(hot_sram_wen_a),
		.addr_a(hot_sram_waddr_a),
		.din_a(hot_sram_din_a),
		
		.ren_b(hot_sram_ren_b),
		.addr_b(hot_sram_raddr_b),
		.dout_b(hot_sram_dout_b)
	);
	
	/** PLIC **/
	// ICB从机
	// 命令通道
	wire[23:0] s_icb_plic_cmd_addr;
	wire s_icb_plic_cmd_read;
	wire[31:0] s_icb_plic_cmd_wdata;
	wire s_icb_plic_cmd_valid;
	wire s_icb_plic_cmd_ready;
	// 响应通道
	wire[31:0] s_icb_plic_rsp_rdata;
	wire s_icb_plic_rsp_valid;
	wire s_icb_plic_rsp_ready;
	
	assign s_icb_plic_cmd_addr = m1_icb_dstb_cmd_addr[23:0];
	assign s_icb_plic_cmd_read = m1_icb_dstb_cmd_read;
	assign s_icb_plic_cmd_wdata = m1_icb_dstb_cmd_wdata;
	assign s_icb_plic_cmd_valid = m1_icb_dstb_cmd_valid;
	assign m1_icb_dstb_cmd_ready = s_icb_plic_cmd_ready;
	assign m1_icb_dstb_rsp_rdata = s_icb_plic_rsp_rdata;
	assign m1_icb_dstb_rsp_err = 1'b0;
	assign m1_icb_dstb_rsp_valid = s_icb_plic_rsp_valid;
	assign s_icb_plic_rsp_ready = m1_icb_dstb_rsp_ready;
	
	sirv_plic_man #(
		.PLIC_PRIO_WIDTH(3),
		.PLIC_IRQ_NUM(64),
		.PLIC_IRQ_NUM_LOG2(6),
		.PLIC_ICB_RSP_FLOP(1),
		.PLIC_IRQ_I_FLOP(1),
		.PLIC_IRQ_O_FLOP(1) 
	)sirv_plic_man_u(
		.clk(clk),
		.rst_n(sys_resetn),
		
		.icb_cmd_addr(s_icb_plic_cmd_addr),
		.icb_cmd_read(s_icb_plic_cmd_read),
		.icb_cmd_wdata(s_icb_plic_cmd_wdata),
		.icb_cmd_valid(s_icb_plic_cmd_valid),
		.icb_cmd_ready(s_icb_plic_cmd_ready),
		.icb_rsp_rdata(s_icb_plic_rsp_rdata),
		.icb_rsp_valid(s_icb_plic_rsp_valid),
		.icb_rsp_ready(s_icb_plic_rsp_ready),
		
		.plic_irq_i({ext_itr_req_vec, 1'b0}),
		.plic_irq_o(ext_itr_req)
	);
	
	/** CLINT **/
	// ICB从机
	// 命令通道
	wire[31:0] s_icb_clint_cmd_addr;
	wire s_icb_clint_cmd_read;
	wire[31:0] s_icb_clint_cmd_wdata;
	wire[3:0] s_icb_clint_cmd_wmask;
	wire s_icb_clint_cmd_valid;
	wire s_icb_clint_cmd_ready;
	// 响应通道
	wire[31:0] s_icb_clint_rsp_rdata;
	wire s_icb_clint_rsp_err; // const -> 1'b0
	wire s_icb_clint_rsp_valid;
	wire s_icb_clint_rsp_ready;
	
	assign s_icb_clint_cmd_addr = m2_icb_dstb_cmd_addr;
	assign s_icb_clint_cmd_read = m2_icb_dstb_cmd_read;
	assign s_icb_clint_cmd_wdata = m2_icb_dstb_cmd_wdata;
	assign s_icb_clint_cmd_wmask = m2_icb_dstb_cmd_wmask;
	assign s_icb_clint_cmd_valid = m2_icb_dstb_cmd_valid;
	assign m2_icb_dstb_cmd_ready = s_icb_clint_cmd_ready;
	assign m2_icb_dstb_rsp_rdata = s_icb_clint_rsp_rdata;
	assign m2_icb_dstb_rsp_err = s_icb_clint_rsp_err;
	assign m2_icb_dstb_rsp_valid = s_icb_clint_rsp_valid;
	assign s_icb_clint_rsp_ready = m2_icb_dstb_rsp_ready;
	
	icb_clint #(
		.RTC_PSC_R(rtc_psc_r),
		.SIM_DELAY(simulation_delay)
	)icb_clint_u(
		.clk(clk),
		.rst_n(sys_resetn),
		
		.rtc_en(rtc_en),
		
		.sw_itr_req(sw_itr_req),
		.tmr_itr_req(tmr_itr_req),
		
		.s_icb_cmd_addr(s_icb_clint_cmd_addr),
		.s_icb_cmd_read(s_icb_clint_cmd_read),
		.s_icb_cmd_wdata(s_icb_clint_cmd_wdata),
		.s_icb_cmd_wmask(s_icb_clint_cmd_wmask),
		.s_icb_cmd_valid(s_icb_clint_cmd_valid),
		.s_icb_cmd_ready(s_icb_clint_cmd_ready),
		.s_icb_rsp_rdata(s_icb_clint_rsp_rdata),
		.s_icb_rsp_err(s_icb_clint_rsp_err),
		.s_icb_rsp_valid(s_icb_clint_rsp_valid),
		.s_icb_rsp_ready(s_icb_clint_rsp_ready)
	);
	
	/** ICB到AXI-Lite桥 **/
	// ICB从机#0
	// 命令通道
	wire[31:0] s0_icb_bridge_cmd_addr;
	wire s0_icb_bridge_cmd_read;
	wire[31:0] s0_icb_bridge_cmd_wdata;
	wire[3:0] s0_icb_bridge_cmd_wmask;
	wire s0_icb_bridge_cmd_valid;
	wire s0_icb_bridge_cmd_ready;
	// 响应通道
	wire[31:0] s0_icb_bridge_rsp_rdata;
	wire s0_icb_bridge_rsp_err;
	wire s0_icb_bridge_rsp_valid;
	wire s0_icb_bridge_rsp_ready;
	// ICB从机#1
	// 命令通道
	wire[31:0] s1_icb_bridge_cmd_addr;
	wire s1_icb_bridge_cmd_read;
	wire[31:0] s1_icb_bridge_cmd_wdata;
	wire[3:0] s1_icb_bridge_cmd_wmask;
	wire s1_icb_bridge_cmd_valid;
	wire s1_icb_bridge_cmd_ready;
	// 响应通道
	wire[31:0] s1_icb_bridge_rsp_rdata;
	wire s1_icb_bridge_rsp_err;
	wire s1_icb_bridge_rsp_valid;
	wire s1_icb_bridge_rsp_ready;
	
	assign m_axi_dbus_arburst = 2'b01;
	assign m_axi_dbus_arlen = 8'd0;
	assign m_axi_dbus_arsize = 3'b010;
	assign m_axi_dbus_arcache = 4'b0011;
	assign m_axi_dbus_awburst = 2'b01;
	assign m_axi_dbus_awlen = 8'd0;
	assign m_axi_dbus_awsize = 3'b010;
	assign m_axi_dbus_awcache = 4'b0011;
	assign m_axi_dbus_wlast = 1'b1;
	
	assign m_axi_dcache_arcache = 4'b0011;
	assign m_axi_dcache_awcache = 4'b0011;
	
	assign s0_icb_bridge_cmd_addr = m3_icb_dstb_cmd_addr;
	assign s0_icb_bridge_cmd_read = m3_icb_dstb_cmd_read;
	assign s0_icb_bridge_cmd_wdata = m3_icb_dstb_cmd_wdata;
	assign s0_icb_bridge_cmd_wmask = m3_icb_dstb_cmd_wmask;
	assign s0_icb_bridge_cmd_valid = m3_icb_dstb_cmd_valid;
	assign m3_icb_dstb_cmd_ready = s0_icb_bridge_cmd_ready;
	assign m3_icb_dstb_rsp_rdata = s0_icb_bridge_rsp_rdata;
	assign m3_icb_dstb_rsp_err = s0_icb_bridge_rsp_err;
	assign m3_icb_dstb_rsp_valid = s0_icb_bridge_rsp_valid;
	assign s0_icb_bridge_rsp_ready = m3_icb_dstb_rsp_ready;
	
	generate
		if(EN_DCACHE == "true")
		begin
			assign s1_icb_bridge_cmd_addr = m_dcache_icb_cmd_addr;
			assign s1_icb_bridge_cmd_read = m_dcache_icb_cmd_read;
			assign s1_icb_bridge_cmd_wdata = m_dcache_icb_cmd_wdata;
			assign s1_icb_bridge_cmd_wmask = m_dcache_icb_cmd_wmask;
			assign s1_icb_bridge_cmd_valid = m_dcache_icb_cmd_valid;
			assign m_dcache_icb_cmd_ready = s1_icb_bridge_cmd_ready;
			assign m_dcache_icb_rsp_rdata = s1_icb_bridge_rsp_rdata;
			assign m_dcache_icb_rsp_err = s1_icb_bridge_rsp_err;
			assign m_dcache_icb_rsp_valid = s1_icb_bridge_rsp_valid;
			assign s1_icb_bridge_rsp_ready = m_dcache_icb_rsp_ready;
		end
		else
		begin
			assign s1_icb_bridge_cmd_addr = 32'dx;
			assign s1_icb_bridge_cmd_read = 1'bx;
			assign s1_icb_bridge_cmd_wdata = 32'dx;
			assign s1_icb_bridge_cmd_wmask = 4'bxxxx;
			assign s1_icb_bridge_cmd_valid = 1'b0;
			
			assign s1_icb_bridge_rsp_ready = 1'b1;
		end
	endgenerate
	
	icb_axi_bridge #(
		.simulation_delay(simulation_delay)
	)icb_axi_bridge_u0(
		.clk(clk),
		.resetn(sys_resetn),
		
		.s_icb_cmd_addr(s0_icb_bridge_cmd_addr),
		.s_icb_cmd_read(s0_icb_bridge_cmd_read),
		.s_icb_cmd_wdata(s0_icb_bridge_cmd_wdata),
		.s_icb_cmd_wmask(s0_icb_bridge_cmd_wmask),
		.s_icb_cmd_valid(s0_icb_bridge_cmd_valid),
		.s_icb_cmd_ready(s0_icb_bridge_cmd_ready),
		.s_icb_rsp_rdata(s0_icb_bridge_rsp_rdata),
		.s_icb_rsp_err(s0_icb_bridge_rsp_err),
		.s_icb_rsp_valid(s0_icb_bridge_rsp_valid),
		.s_icb_rsp_ready(s0_icb_bridge_rsp_ready),
		
		.m_axi_araddr(m_axi_dbus_araddr),
		.m_axi_arprot(),
		.m_axi_arvalid(m_axi_dbus_arvalid),
		.m_axi_arready(m_axi_dbus_arready),
		.m_axi_awaddr(m_axi_dbus_awaddr),
		.m_axi_awprot(),
		.m_axi_awvalid(m_axi_dbus_awvalid),
		.m_axi_awready(m_axi_dbus_awready),
		.m_axi_bresp(m_axi_dbus_bresp),
		.m_axi_bvalid(m_axi_dbus_bvalid),
		.m_axi_bready(m_axi_dbus_bready),
		.m_axi_rdata(m_axi_dbus_rdata),
		.m_axi_rresp(m_axi_dbus_rresp),
		.m_axi_rvalid(m_axi_dbus_rvalid),
		.m_axi_rready(m_axi_dbus_rready),
		.m_axi_wdata(m_axi_dbus_wdata),
		.m_axi_wstrb(m_axi_dbus_wstrb),
		.m_axi_wvalid(m_axi_dbus_wvalid),
		.m_axi_wready(m_axi_dbus_wready)
	);
	
	generate
		if(EN_DCACHE == "true")
		begin
			dcache_nxt_lv_mem_icb_to_axi #(
				.CACHE_LINE_WORD_N(DCACHE_LINE_WORD_N),
				.SIM_DELAY(simulation_delay)
			)dcache_nxt_lv_mem_icb_to_axi_u(
				.aclk(clk),
				.aresetn(sys_resetn),
				
				.s_icb_cmd_addr(s1_icb_bridge_cmd_addr),
				.s_icb_cmd_read(s1_icb_bridge_cmd_read),
				.s_icb_cmd_wdata(s1_icb_bridge_cmd_wdata),
				.s_icb_cmd_wmask(s1_icb_bridge_cmd_wmask),
				.s_icb_cmd_valid(s1_icb_bridge_cmd_valid),
				.s_icb_cmd_ready(s1_icb_bridge_cmd_ready),
				.s_icb_rsp_rdata(s1_icb_bridge_rsp_rdata),
				.s_icb_rsp_err(s1_icb_bridge_rsp_err),
				.s_icb_rsp_valid(s1_icb_bridge_rsp_valid),
				.s_icb_rsp_ready(s1_icb_bridge_rsp_ready),
				
				.m_axi_araddr(m_axi_dcache_araddr),
				.m_axi_arburst(m_axi_dcache_arburst),
				.m_axi_arlen(m_axi_dcache_arlen),
				.m_axi_arsize(m_axi_dcache_arsize),
				.m_axi_arvalid(m_axi_dcache_arvalid),
				.m_axi_arready(m_axi_dcache_arready),
				.m_axi_awaddr(m_axi_dcache_awaddr),
				.m_axi_awburst(m_axi_dcache_awburst),
				.m_axi_awlen(m_axi_dcache_awlen),
				.m_axi_awsize(m_axi_dcache_awsize),
				.m_axi_awvalid(m_axi_dcache_awvalid),
				.m_axi_awready(m_axi_dcache_awready),
				.m_axi_bresp(m_axi_dcache_bresp),
				.m_axi_bvalid(m_axi_dcache_bvalid),
				.m_axi_bready(m_axi_dcache_bready),
				.m_axi_rdata(m_axi_dcache_rdata),
				.m_axi_rresp(m_axi_dcache_rresp),
				.m_axi_rlast(m_axi_dcache_rlast),
				.m_axi_rvalid(m_axi_dcache_rvalid),
				.m_axi_rready(m_axi_dcache_rready),
				.m_axi_wdata(m_axi_dcache_wdata),
				.m_axi_wstrb(m_axi_dcache_wstrb),
				.m_axi_wlast(m_axi_dcache_wlast),
				.m_axi_wvalid(m_axi_dcache_wvalid),
				.m_axi_wready(m_axi_dcache_wready)
			);
		end
		else
		begin
			assign m_axi_dcache_arvalid = 1'b0;
			
			assign m_axi_dcache_awvalid = 1'b0;
			
			assign m_axi_dcache_bready = 1'b1;
			
			assign m_axi_dcache_rready = 1'b1;
			
			assign m_axi_dcache_wvalid = 1'b0;
		end
	endgenerate
	
endmodule
