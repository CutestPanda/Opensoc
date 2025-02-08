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
本模块: 调试模块

描述:
实现DM寄存器, 支持以下调试特性:
	(1)系统总线访问(System Bus Access, 可选)
	(2)抽象命令(Abstract Command)下的GPRs读写和程序缓存区(Program Buffer)执行
	(3)复位释放后暂停(resethaltreq)

尚不支持以下特性:
	(1)多HART选择
	(2)抽象命令(Abstract Command)下的非GPRs寄存器读写、存储器访问(Access Memory)、快速访问(Quick Access)
	(3)HART运行时通过抽象命令读写寄存器

参见《The RISC-V Debug Specification》(Version 1.0.0-rc4, Revised 2024-12-05: Frozen)

注意：
无

协议:
APB SLAVE
ICB MASTER
MEM SLAVE

作者: 陈家耀
日期: 2025/02/08
********************************************************************/


module jtag_dm #(
	parameter integer ABITS = 7, // DMI地址位宽(必须在范围[7, 32]内)
	parameter integer HARTS_N = 1, // HART个数(必须在范围[1, 32]内)
	parameter integer SCRATCH_N = 1, // HART支持的dscratch个数(必须在范围[0, 2]内)
	parameter SBUS_SUPPORTED = "true", // 是否支持系统总线访问
	/*
	Spec:
		If there is more than one DM accessible on this DMI, this register contains the base address of the next
			one in the chain, or 0 if this is the last one in the chain.
	*/
	parameter NEXT_DM_ADDR = 32'h0000_0000, // 下一DM地址
	parameter integer PROGBUF_SIZE = 2, // Program Buffer的大小(以双字计, 必须在范围[2, 16]内)
	parameter DATA0_ADDR = 32'hFFFF_F800, // data0寄存器在存储映射中的地址(必须在范围[0xFFFFF800, 0xFFFFFFFF] U [0x00000000, 0x000007FF]内)
	parameter PROGBUF0_ADDR = 32'hFFFF_F900, // progbuf0寄存器在存储映射中的地址(必须在范围[0xFFFFF800, 0xFFFFFFFF] U [0x00000000, 0x000007FF]内)
	parameter ACMD_FLAGS_ADDR = 32'hFFFF_FA00, // 抽象命令执行标志在存储映射中的地址(必须在范围[0xFFFFF800, 0xFFFFFFFF] U [0x00000000, 0x000007FF]内)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// DMI(APB从机)
    input wire[ABITS+1:0] s_dmi_paddr,
    input wire s_dmi_psel,
    input wire s_dmi_penable,
    input wire s_dmi_pwrite,
    input wire[31:0] s_dmi_pwdata,
    output wire s_dmi_pready, // const -> 1'b1
    output wire[31:0] s_dmi_prdata,
    output wire s_dmi_pslverr, // const -> 1'b0
	
	// 复位控制
	output wire sys_reset_req,
	input wire sys_reset_fns,
	output wire[HARTS_N-1:0] hart_reset_req,
	input wire[HARTS_N-1:0] hart_reset_fns,
	
	// 运行/暂停控制
	output wire[HARTS_N-1:0] hart_req_halt,
	output wire[HARTS_N-1:0] hart_req_halt_on_reset,
	output wire[HARTS_N-1:0] hart_req_resume,
	input wire[HARTS_N-1:0] hart_halted,
	input wire[HARTS_N-1:0] hart_running,
	
	// HART对DM内容的访问(存储器从接口)
	input wire hart_access_en,
	input wire[3:0] hart_access_wen,
	input wire[29:0] hart_access_addr,
	input wire[31:0] hart_access_din,
	output wire[31:0] hart_access_dout,
	
	// 系统总线访问(ICB主机)
	// 命令通道
	output wire[31:0] m_icb_cmd_sbus_addr,
	output wire m_icb_cmd_sbus_read,
	output wire[31:0] m_icb_cmd_sbus_wdata,
	output wire[3:0] m_icb_cmd_sbus_wmask,
	output wire m_icb_cmd_sbus_valid,
	input wire m_icb_cmd_sbus_ready,
	// 响应通道
	input wire[31:0] m_icb_rsp_sbus_rdata,
	input wire m_icb_rsp_sbus_err,
	input wire m_icb_rsp_sbus_valid,
	output wire m_icb_rsp_sbus_ready
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
	// DM版本
	localparam DM_VERSION = 4'd2; // RISC-V debug spec 0.13.2
	// DM寄存器地址
	localparam ADDR_DATA0 = {ABITS{1'b0}} | 7'h04;
	localparam ADDR_DMCONTROL = {ABITS{1'b0}} | 7'h10;
	localparam ADDR_DMSTATUS = {ABITS{1'b0}} | 7'h11;
	localparam ADDR_HARTINFO = {ABITS{1'b0}} | 7'h12;
	localparam ADDR_HALTSUM1 = {ABITS{1'b0}} | 7'h13;
	localparam ADDR_HALTSUM0 = {ABITS{1'b0}} | 7'h40;
	localparam ADDR_HAWINDOWSEL = {ABITS{1'b0}} | 7'h14;
	localparam ADDR_HAWINDOW = {ABITS{1'b0}} | 7'h15;
	localparam ADDR_ABSTRACTCS = {ABITS{1'b0}} | 7'h16;
	localparam ADDR_COMMAND = {ABITS{1'b0}} | 7'h17;
	localparam ADDR_ABSTRACTAUTO = {ABITS{1'b0}} | 7'h18;
	localparam ADDR_CONFSTRPTR0 = {ABITS{1'b0}} | 7'h19;
	localparam ADDR_CONFSTRPTR1 = {ABITS{1'b0}} | 7'h1a;
	localparam ADDR_CONFSTRPTR2 = {ABITS{1'b0}} | 7'h1b;
	localparam ADDR_CONFSTRPTR3 = {ABITS{1'b0}} | 7'h1c;
	localparam ADDR_NEXTDM = {ABITS{1'b0}} | 7'h1d;
	localparam ADDR_PROGBUF_BASE = {ABITS{1'b0}} | 7'h20;
	localparam ADDR_SBCS = {ABITS{1'b0}} | 7'h38;
	localparam ADDR_SBADDRESS0 = {ABITS{1'b0}} | 7'h39;
	localparam ADDR_SBDATA0 = {ABITS{1'b0}} | 7'h3c;
	// 系统总线错误编码
	localparam SBERROR_NONE = 3'd0;
	localparam SBERROR_TIMEOUT = 3'd1;
	localparam SBERROR_ADDRESS = 3'd2;
	localparam SBERROR_ALIGNMENT = 3'd3;
	localparam SBERROR_SIZE = 3'd4;
	localparam SBERROR_OTHER = 3'd7;
	// 抽象命令错误编码
	localparam CMDERR_NONE = 3'd0;
	localparam CMDERR_BUSY = 3'd1;
	localparam CMDERR_NOT_SUPPORTED = 3'd2;
	localparam CMDERR_EXCEPTION = 3'd3;
	localparam CMDERR_HALT_RESUME = 3'd4;
	localparam CMDERR_BUS = 3'd5;
	localparam CMDERR_OTHER = 3'd7;
	// 抽象命令执行状态常量
	localparam ACMD_EXEC_STS_IDLE = 2'b00;
	localparam ACMD_EXEC_STS_REGS_RW = 2'b01;
	localparam ACMD_EXEC_STS_PROGBUF = 2'b10;
	
	/** DMI访问 **/
	wire dmi_write;
	wire dmi_read;
	wire[ABITS-1:0] dmi_regaddr;
	wire[31:0] dmi_wdata;
	
	assign s_dmi_pready = 1'b1;
	assign s_dmi_pslverr = 1'b0;
	
	assign dmi_write = s_dmi_psel & s_dmi_penable & s_dmi_pready & s_dmi_pwrite;
	assign dmi_read = s_dmi_psel & s_dmi_penable & s_dmi_pready & (~s_dmi_pwrite);
	assign dmi_regaddr = s_dmi_paddr[ABITS+1:2];
	assign dmi_wdata = s_dmi_pwdata;
	
	/** DM复位 **/
	reg dmactive; // DM激活标志
	wire dmcontrol_en;
	
	assign dmcontrol_en = dmi_write & (dmi_regaddr == ADDR_DMCONTROL);
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			dmactive <= 1'b0;
		else if(dmcontrol_en)
			dmactive <= # SIM_DELAY dmi_wdata[0];
	end
	
	/** HART选择 **/
	wire abstractcs_busy; // 抽象命令执行中
	reg[clogb2(HARTS_N-1):0] hartsel;
	wire[clogb2(HARTS_N-1):0] hartsel_nxt;
	
	// 注意: 仅支持hartsel的低10位(hartsello)!
	assign hartsel_nxt = 
		(HARTS_N > 1) ? 
			((dmcontrol_en & (~abstractcs_busy)) ? dmi_wdata[16+clogb2(HARTS_N-1):16]:hartsel):
			1'b0;
	
	/*
	Spec:
		While an abstract command is executing (busy in abstractcs is high), a debugger must not change
			hartsel, and must not write 1 to haltreq, resumereq, ackhavereset, setresethaltreq, or clrresethaltreq.
		
		The hardware should not rely on this debugger behavior, but should enforce it by ignoring writes to
			these bits while busy is high.
	*/
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			hartsel <= 0;
		else if((~dmactive) | (dmcontrol_en & (~abstractcs_busy)))
			hartsel <= # SIM_DELAY {(clogb2(HARTS_N-1)+1){dmactive}} & hartsel_nxt;
	end
	
	/** 运行/暂停/复位控制 **/
	wire[HARTS_N-1:0] dmcontrol_op_mask; // HART选择掩码
	reg[HARTS_N-1:0] dmcontrol_haltreq; // HART暂停请求
	reg[HARTS_N-1:0] dmcontrol_hartreset; // HART复位请求
	reg[HARTS_N-1:0] dmcontrol_resethaltreq; // HART复位释放后暂停请求
	reg dmcontrol_ndmreset; // 非DM组件复位请求
	reg[HARTS_N-1:0] hart_reset_fns_d; // 延迟1clk的HART复位完成标志
	reg[HARTS_N-1:0] dmstatus_havereset; // HART已复位标志
	wire[HARTS_N-1:0] hart_available; // HART可用标志
	reg[HARTS_N-1:0] dmstatus_resumeack; // HART复位应答标志
	reg[HARTS_N-1:0] dmcontrol_resumereq; // HART复位请求
	
	assign sys_reset_req = dmcontrol_ndmreset;
	assign hart_reset_req = dmcontrol_hartreset;
	
	assign hart_req_halt = dmcontrol_haltreq;
	assign hart_req_halt_on_reset = dmcontrol_resethaltreq;
	assign hart_req_resume = dmcontrol_resumereq;
	
	// 注意: 不支持多HART同时选择!
	generate
		if(HARTS_N > 1)
			assign dmcontrol_op_mask = 
				(hartsel_nxt >= HARTS_N) ? 
					{HARTS_N{1'b0}}:
					({{(HARTS_N-1){1'b0}}, 1'b1} << hartsel_nxt);
		else
			assign dmcontrol_op_mask = 1'b1;
	endgenerate
	assign hart_available = hart_reset_fns & {HARTS_N{sys_reset_fns}};
	
	/*
	Spec:
		While an abstract command is executing (busy in abstractcs is high), a debugger must not change
			hartsel, and must not write 1 to haltreq, resumereq, ackhavereset, setresethaltreq, or clrresethaltreq.
		
		The hardware should not rely on this debugger behavior, but should enforce it by ignoring writes to
			these bits while busy is high.
	*/
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
		begin
			dmcontrol_haltreq <= {HARTS_N{1'b0}};
			dmcontrol_resethaltreq <= {HARTS_N{1'b0}};
		end
		else if((~dmactive) | (dmcontrol_en & (~abstractcs_busy)))
		begin
			dmcontrol_haltreq <= # SIM_DELAY {HARTS_N{dmactive}} & (
				(dmcontrol_haltreq & (~dmcontrol_op_mask)) | 
				// haltreq
				({HARTS_N{dmi_wdata[31]}} & dmcontrol_op_mask)
			);
			dmcontrol_resethaltreq <= # SIM_DELAY {HARTS_N{dmactive}} & (
				// clrresethaltreq
				(dmcontrol_resethaltreq & (~({HARTS_N{dmi_wdata[2]}} & dmcontrol_op_mask))) | 
				// setresethaltreq
				({HARTS_N{dmi_wdata[3]}} & dmcontrol_op_mask)
			);
		end
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
		begin
			dmcontrol_hartreset <= {HARTS_N{1'b0}};
			dmcontrol_ndmreset <= 1'b0;
		end
		else if((~dmactive) | dmcontrol_en)
		begin
			dmcontrol_hartreset <= # SIM_DELAY {HARTS_N{dmactive}} & (
				(dmcontrol_hartreset & (~dmcontrol_op_mask)) | 
				// hartreset
				({HARTS_N{dmi_wdata[29]}} & dmcontrol_op_mask)
			);
			dmcontrol_ndmreset <= # SIM_DELAY dmactive & dmi_wdata[1];
		end
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			hart_reset_fns_d <= {HARTS_N{1'b0}};
		else
			hart_reset_fns_d <= # SIM_DELAY hart_reset_fns;
	end
	
	/*
	Spec:
		While an abstract command is executing (busy in abstractcs is high), a debugger must not change
			hartsel, and must not write 1 to haltreq, resumereq, ackhavereset, setresethaltreq, or clrresethaltreq.
		
		The hardware should not rely on this debugger behavior, but should enforce it by ignoring writes to
			these bits while busy is high.
	*/
	genvar dmstatus_havereset_i;
	generate
		for(dmstatus_havereset_i = 0;dmstatus_havereset_i < HARTS_N;dmstatus_havereset_i = dmstatus_havereset_i + 1)
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					dmstatus_havereset[dmstatus_havereset_i] <= 1'b0;
				else if((~dmactive) | 
					// 在"HART复位完成标志"检测到上升沿
					(hart_reset_fns[dmstatus_havereset_i] & (~hart_reset_fns_d[dmstatus_havereset_i])) | 
					(dmcontrol_en & dmi_wdata[28] & (~abstractcs_busy) & dmcontrol_op_mask[dmstatus_havereset_i])
				)
					dmstatus_havereset[dmstatus_havereset_i] <= # SIM_DELAY 
						dmactive & 
						(hart_reset_fns[dmstatus_havereset_i] & (~hart_reset_fns_d[dmstatus_havereset_i])) & 
						// ackhavereset
						(~(dmcontrol_en & dmi_wdata[28] & (~abstractcs_busy) & dmcontrol_op_mask[dmstatus_havereset_i]));
			end
		end
	endgenerate
	
	/*
	Spec:
		While an abstract command is executing (busy in abstractcs is high), a debugger must not change
			hartsel, and must not write 1 to haltreq, resumereq, ackhavereset, setresethaltreq, or clrresethaltreq.
		
		The hardware should not rely on this debugger behavior, but should enforce it by ignoring writes to
			these bits while busy is high.
	*/
	genvar dmstatus_resumeack_i;
	generate
		for(dmstatus_resumeack_i = 0;dmstatus_resumeack_i < HARTS_N;dmstatus_resumeack_i = dmstatus_resumeack_i + 1)
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					dmstatus_resumeack[dmstatus_resumeack_i] <= 1'b0;
				else if((~dmactive) | 
					// HART恢复请求有效, 且HART正在运行、可用
					(hart_req_resume[dmstatus_resumeack_i] & hart_running[dmstatus_resumeack_i] & hart_available[dmstatus_resumeack_i]) | 
					// haltreq = 0, resumereq = 1
					(dmcontrol_en & (~dmi_wdata[31]) & dmi_wdata[30] & (~abstractcs_busy) & dmcontrol_op_mask[dmstatus_resumeack_i])
				)
					dmstatus_resumeack[dmstatus_resumeack_i] <= # SIM_DELAY 
						dmactive & 
						(hart_req_resume[dmstatus_resumeack_i] & 
							hart_running[dmstatus_resumeack_i] & hart_available[dmstatus_resumeack_i]) & 
						(~(dmcontrol_en & (~dmi_wdata[31]) & dmi_wdata[30] & (~abstractcs_busy) & dmcontrol_op_mask[dmstatus_resumeack_i]));
			end
		end
	endgenerate
	
	/*
	Spec:
		While an abstract command is executing (busy in abstractcs is high), a debugger must not change
			hartsel, and must not write 1 to haltreq, resumereq, ackhavereset, setresethaltreq, or clrresethaltreq.
		
		The hardware should not rely on this debugger behavior, but should enforce it by ignoring writes to
			these bits while busy is high.
	*/
	genvar dmcontrol_resumereq_i;
	generate
		for(dmcontrol_resumereq_i = 0;dmcontrol_resumereq_i < HARTS_N;
			dmcontrol_resumereq_i = dmcontrol_resumereq_i + 1)
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					dmcontrol_resumereq[dmcontrol_resumereq_i] <= 1'b0;
				else if((~dmactive) | 
					// HART正在运行、可用
					(hart_running[dmcontrol_resumereq_i] & hart_available[dmcontrol_resumereq_i]) | 
					// haltreq = 0, resumereq = 1
					(dmcontrol_en & (~dmi_wdata[31]) & dmi_wdata[30] & (~abstractcs_busy) & dmcontrol_op_mask[dmcontrol_resumereq_i])
				)
					dmcontrol_resumereq[dmcontrol_resumereq_i] <= # SIM_DELAY 
						dmactive & (
							(~(hart_running[dmcontrol_resumereq_i] & hart_available[dmcontrol_resumereq_i])) | 
							(dmcontrol_en & (~dmi_wdata[31]) & dmi_wdata[30] & (~abstractcs_busy) & dmcontrol_op_mask[dmcontrol_resumereq_i])
						);
			end
		end
	endgenerate
	
	/** 系统总线访问 **/
	reg[31:0] sbaddress; // 系统总线地址
	reg[31:0] sbdata; // 系统总线数据
	reg sbbusy; // 系统总线忙碌标志
	reg sbautoincrement; // 系统总线地址自动递增标志
	reg[2:0] sbaccess; // 系统总线访问位宽
	reg sbbusyerror; // 系统总线忙碌错误
	reg sbreadonaddr; // 写系统总线地址时自动读
	reg sbreadondata; // 取系统总线数据时自动读
	reg[2:0] sberror; // 系统总线错误码
	reg sbus_is_read_latched; // 锁存的系统总线读写类型
	reg[31:0] sbus_wdata_latched; // 锁存的系统总线写数据
	reg[3:0] sbus_wmask_latched; // 锁存的系统总线写字节掩码
	reg sbus_cmd_vld; // 系统总线命令通道的valid信号
	wire sbaddress0_en;
	wire sbdata0_en;
	wire sbcs_en;
	wire sb_access_illegal_when_busy; // 系统总线忙碌时进行非法操作
	wire sb_want_start_read; // 启动系统总线读操作
	wire sb_want_start_write; // 启动系统总线写操作
	wire sb_start; // 启动系统总线
	wire[1:0] sb_next_align; // 最新的低位系统总线地址
	wire[31:0] sb_next_data; // 最新的系统总线数据
	wire sb_badsize; // 不支持的系统总线访问位宽
	wire sb_badalign; // 系统总线访问非对齐
	
	assign m_icb_cmd_sbus_addr = sbaddress;
	assign m_icb_cmd_sbus_read = sbus_is_read_latched;
	assign m_icb_cmd_sbus_wdata = sbus_wdata_latched;
	assign m_icb_cmd_sbus_wmask = sbus_wmask_latched;
	assign m_icb_cmd_sbus_valid = sbus_cmd_vld;
	
	assign m_icb_rsp_sbus_ready = sbbusy;
	
	assign sbaddress0_en = dmi_write & (dmi_regaddr == ADDR_SBADDRESS0);
	assign sbdata0_en = dmi_write & (dmi_regaddr == ADDR_SBDATA0);
	assign sbcs_en = dmi_write & (dmi_regaddr == ADDR_SBCS);
	
	assign sb_access_illegal_when_busy =
		((dmi_read | dmi_write) & (dmi_regaddr == ADDR_SBDATA0)) | 
		(dmi_write & (dmi_regaddr == ADDR_SBADDRESS0));
	assign sb_want_start_read =
		(sbreadonaddr & dmi_write & (dmi_regaddr == ADDR_SBADDRESS0)) | 
		(sbreadondata & dmi_read & (dmi_regaddr == ADDR_SBDATA0));
	assign sb_want_start_write = dmi_write & (dmi_regaddr == ADDR_SBDATA0);
	assign sb_start = (sb_want_start_read | sb_want_start_write) & 
		(~sbbusy) & (~sbbusyerror) & (sberror == SBERROR_NONE) & (~sb_badsize) & (~sb_badalign);
	
	assign sb_next_align = 
		(sbreadonaddr & dmi_write & (dmi_regaddr == ADDR_SBADDRESS0)) ? 
			dmi_wdata[1:0]:
			sbaddress[1:0];
	assign sb_next_data = 
		(dmi_write & (dmi_regaddr == ADDR_SBDATA0)) ? 
			dmi_wdata:
			sbdata;
	assign sb_badsize = sbaccess > 3'b010;
	assign sb_badalign = 
		((sbaccess[1:0] == 2'b01) & sb_next_align[0]) | 
		((sbaccess[1:0] == 2'b10) & (|sb_next_align[1:0]));
	
	/*
	SPEC: 
		When the system bus manager is busy, writes to this register will set sbbusyerror and don’t do anything else.
		If the read/write succeeded and sbautoincrement is set, increment sbaddress.
	*/
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			sbaddress <= 32'h0000_0000;
		else if((~dmactive) | (
			sbbusy ? 
				(m_icb_rsp_sbus_valid & m_icb_rsp_sbus_ready & (~m_icb_rsp_sbus_err) & sbautoincrement):
				sbaddress0_en
		))
			sbaddress <= # SIM_DELAY {32{dmactive}} & (
				sbbusy ? 
					(sbaddress + (
						({32{sbaccess[1:0] == 2'b00}} & 32'd1) | 
						({32{sbaccess[1:0] == 2'b01}} & 32'd2) | 
						({32{sbaccess[1:0] == 2'b10}} & 32'd4)
					)):
					dmi_wdata
			);
	end
	
	/*
	SPEC:
		If either sberror or sbbusyerror isn’t 0 then accesses do nothing.
		If the bus manager is busy then accesses set sbbusyerror, and don’t do anything else.
		
		If the width of the read access is less than the width of sbdata, 
			the contents of the remaining high bits may take on any value.
		
		Any successful system bus read updates sbdata.
	*/
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			sbdata <= 32'h0000_0000;
		else if((~dmactive) | (
			sbbusy ? 
				(m_icb_rsp_sbus_valid & m_icb_rsp_sbus_ready & (~m_icb_rsp_sbus_err) & sbus_is_read_latched):
				(sbdata0_en & (~sbbusyerror) & (sberror == SBERROR_NONE))
		))
			sbdata <= # SIM_DELAY {32{dmactive}} & (
				sbbusy ? 
					(m_icb_rsp_sbus_rdata >> {sbaddress[1:0], 3'b000}):
					dmi_wdata
			);
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			{sbreadonaddr, sbaccess, sbautoincrement, sbreadondata} <= {1'b0, 3'b010, 1'b0, 1'b0};
		else if((~dmactive) | sbcs_en)
			{sbreadonaddr, sbaccess, sbautoincrement, sbreadondata} <= # SIM_DELAY 
				dmactive ? 
					{dmi_wdata[20], dmi_wdata[19:17], dmi_wdata[16], dmi_wdata[15]}:
					{1'b0, 3'b010, 1'b0, 1'b0};
	end
	
	/*
	SPEC:
		This bit goes high immediately when a read or write is requested for any reason, 
		and does not go low until the access is fully completed.
	*/
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			sbbusy <= 1'b0;
		else if((~dmactive) | 
			(sbbusy ? 
				(m_icb_rsp_sbus_valid & m_icb_rsp_sbus_ready):
				sb_start
			)
		)
			sbbusy <= # SIM_DELAY dmactive & (~sbbusy);
	end
	
	/*
	SPEC:
		Set when the debugger attempts to read data while a read is in progress, 
		or when the debugger initiates a new access while one is already in progress (while sbbusy is set).
	*/
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			sbbusyerror <= 1'b0;
		else if((~dmactive) | 
			(sbcs_en & dmi_wdata[22]) | 
			(sbbusy & sb_access_illegal_when_busy)
		)
			sbbusyerror <= # SIM_DELAY dmactive & ((~(sbcs_en & dmi_wdata[22])) | (sbbusy & sb_access_illegal_when_busy));
	end
	
	/*
	SPEC:
		When the Debug Module’s system bus manager encounters an error, this field gets set.
	*/
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			sberror <= SBERROR_NONE;
		else if((~dmactive) | 
			sbcs_en | 
			(sbbusy ? 
				(m_icb_rsp_sbus_valid & m_icb_rsp_sbus_ready & m_icb_rsp_sbus_err):
				((sb_want_start_read | sb_want_start_write) & (~sbbusyerror) & (sberror == SBERROR_NONE) & (sb_badsize | sb_badalign))
			)
		)
		begin
			if(~dmactive)
				sberror <= # SIM_DELAY SBERROR_NONE;
			else if(sbbusy ? 
				(m_icb_rsp_sbus_valid & m_icb_rsp_sbus_ready & m_icb_rsp_sbus_err):
				((sb_want_start_read | sb_want_start_write) & (~sbbusyerror) & (sberror == SBERROR_NONE) & (sb_badsize | sb_badalign))
			)
				sberror <= # SIM_DELAY sbbusy ? 
					SBERROR_ADDRESS:
					(sb_badsize ? 
						SBERROR_SIZE:
						SBERROR_ALIGNMENT
					);
			else
				sberror <= # SIM_DELAY sberror & (~dmi_wdata[14:12]);
		end
	end
	
	always @(posedge clk)
	begin
		if(dmactive & sb_start)
		begin
			sbus_is_read_latched <= # SIM_DELAY ~sb_want_start_write;
			sbus_wdata_latched <= # SIM_DELAY 
				({32{sbaccess[1:0] == 2'b00}} & {4{sb_next_data[7:0]}}) | 
				({32{sbaccess[1:0] == 2'b01}} & {2{sb_next_data[15:0]}}) | 
				({32{sbaccess[1:0] == 2'b10}} & sb_next_data);
			sbus_wmask_latched <= # SIM_DELAY 
				{{2{sbaccess[1:0] == 2'b10}}, (sbaccess[1:0] == 2'b10) | (sbaccess[1:0] == 2'b01), 1'b1} << sb_next_align;
		end
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			sbus_cmd_vld <= 1'b0;
		else if(sbus_cmd_vld ? 
			m_icb_cmd_sbus_ready:(dmactive & sb_start))
			sbus_cmd_vld <= # SIM_DELAY ~sbus_cmd_vld;
	end
	
	/** 抽象命令 **/
	// 注意: 该寄存器(RW)位于存储映射(地址 = DATA0_ADDR)上!
	reg[31:0] abstract_data0; // 抽象命令data0
	wire[31:0] progbuf[0:PROGBUF_SIZE]; // 程序缓存区
	reg abstractauto_autoexecdata; // 访问data时自动执行抽象命令
	reg[15:0] abstractauto_autoexecprogbuf; // 访问progbuf时自动执行抽象命令
	reg acmd_postexec; // 抽象命令后执行程序缓存区
	reg acmd_transfer; // 抽象命令允许传输
	reg acmd_write; // 抽象命令读写类型
	reg[15:0] acmd_regno; // 抽象命令寄存器号
	wire[7:0] acmd_cmdtype_nxt; // 最新的抽象命令类型
	wire[2:0] acmd_aarsize_nxt; // 最新的抽象命令寄存器读写位宽
	wire acmd_aarpostincrement_nxt; // 最新的抽象命令寄存器号自动递增标志
	wire acmd_postexec_nxt; // 最新的抽象命令后执行程序缓存区
	wire acmd_transfer_nxt; // 最新的抽象命令允许传输
	wire acmd_write_nxt; // 最新的抽象命令读写类型
	wire[15:0] acmd_regno_nxt; // 最新的抽象命令寄存器号
	reg[2:0] abstractcs_cmderr; // 抽象命令错误类型
	wire abstract_data0_en;
	wire[PROGBUF_SIZE:0] progbuf_en;
	wire abstractauto_en;
	wire acmd_en;
	wire abstractcs_en;
	wire dmi_want_launch_acmd; // DMI请求执行抽象命令
	wire start_acmd; // 启动抽象命令
	wire acmd_supported; // 抽象命令被支持
	wire acmd_hart_halted; // 待执行抽象命令的HART已暂停
	reg[31:0] regs_rw_inst_0; // 寄存器读写指令区#0
	wire[31:0] regs_rw_inst_1; // 寄存器读写指令区#1
	wire[31:0] regs_rw_inst_2; // 寄存器读写指令区#2
	// 注意: 该寄存器(RW)位于存储映射(地址 = ACMD_FLAGS_ADDR)上!
	reg exec_progbuf; // 执行程序缓存区标志
	reg[1:0] acmd_exec_sts; // 抽象命令执行状态
	wire illegal_access_while_abstractcs_busy; // 在抽象命令执行时进行非法访问
	
	assign abstractcs_busy = acmd_exec_sts != ACMD_EXEC_STS_IDLE;
	
	assign {acmd_cmdtype_nxt, acmd_aarsize_nxt, acmd_aarpostincrement_nxt, 
		acmd_postexec_nxt, acmd_transfer_nxt, acmd_write_nxt, acmd_regno_nxt} = 
		acmd_en ? 
			{dmi_wdata[31:24], dmi_wdata[22:0]}:
			{8'd0, 3'b010, 1'b0, acmd_postexec, acmd_transfer, acmd_write, acmd_regno};
	
	assign abstract_data0_en = dmi_write & (dmi_regaddr == ADDR_DATA0);
	assign abstractauto_en = dmi_write & (dmi_regaddr == ADDR_ABSTRACTAUTO);
	assign acmd_en = dmi_write & (dmi_regaddr == ADDR_COMMAND);
	assign abstractcs_en = dmi_write & (dmi_regaddr == ADDR_ABSTRACTCS);
	
	assign dmi_want_launch_acmd = 
		(dmi_write & (dmi_regaddr == ADDR_COMMAND)) | 
		((dmi_write | dmi_read) & (dmi_regaddr == ADDR_DATA0) & abstractauto_autoexecdata) | 
		((dmi_write | dmi_read) & (dmi_regaddr == (ADDR_PROGBUF_BASE + 0)) & abstractauto_autoexecprogbuf[0] & (PROGBUF_SIZE >= 1)) | 
		((dmi_write | dmi_read) & (dmi_regaddr == (ADDR_PROGBUF_BASE + 1)) & abstractauto_autoexecprogbuf[1] & (PROGBUF_SIZE >= 2)) | 
		((dmi_write | dmi_read) & (dmi_regaddr == (ADDR_PROGBUF_BASE + 2)) & abstractauto_autoexecprogbuf[2] & (PROGBUF_SIZE >= 3)) | 
		((dmi_write | dmi_read) & (dmi_regaddr == (ADDR_PROGBUF_BASE + 3)) & abstractauto_autoexecprogbuf[3] & (PROGBUF_SIZE >= 4)) | 
		((dmi_write | dmi_read) & (dmi_regaddr == (ADDR_PROGBUF_BASE + 4)) & abstractauto_autoexecprogbuf[4] & (PROGBUF_SIZE >= 5)) | 
		((dmi_write | dmi_read) & (dmi_regaddr == (ADDR_PROGBUF_BASE + 5)) & abstractauto_autoexecprogbuf[5] & (PROGBUF_SIZE >= 6)) | 
		((dmi_write | dmi_read) & (dmi_regaddr == (ADDR_PROGBUF_BASE + 6)) & abstractauto_autoexecprogbuf[6] & (PROGBUF_SIZE >= 7)) | 
		((dmi_write | dmi_read) & (dmi_regaddr == (ADDR_PROGBUF_BASE + 7)) & abstractauto_autoexecprogbuf[7] & (PROGBUF_SIZE >= 8)) | 
		((dmi_write | dmi_read) & (dmi_regaddr == (ADDR_PROGBUF_BASE + 8)) & abstractauto_autoexecprogbuf[8] & (PROGBUF_SIZE >= 9)) | 
		((dmi_write | dmi_read) & (dmi_regaddr == (ADDR_PROGBUF_BASE + 9)) & abstractauto_autoexecprogbuf[9] & (PROGBUF_SIZE >= 10)) | 
		((dmi_write | dmi_read) & (dmi_regaddr == (ADDR_PROGBUF_BASE + 10)) & abstractauto_autoexecprogbuf[10] & (PROGBUF_SIZE >= 11)) | 
		((dmi_write | dmi_read) & (dmi_regaddr == (ADDR_PROGBUF_BASE + 11)) & abstractauto_autoexecprogbuf[11] & (PROGBUF_SIZE >= 12)) | 
		((dmi_write | dmi_read) & (dmi_regaddr == (ADDR_PROGBUF_BASE + 12)) & abstractauto_autoexecprogbuf[12] & (PROGBUF_SIZE >= 13)) | 
		((dmi_write | dmi_read) & (dmi_regaddr == (ADDR_PROGBUF_BASE + 13)) & abstractauto_autoexecprogbuf[13] & (PROGBUF_SIZE >= 14)) | 
		((dmi_write | dmi_read) & (dmi_regaddr == (ADDR_PROGBUF_BASE + 14)) & abstractauto_autoexecprogbuf[14] & (PROGBUF_SIZE >= 15)) | 
		((dmi_write | dmi_read) & (dmi_regaddr == (ADDR_PROGBUF_BASE + 15)) & abstractauto_autoexecprogbuf[15] & (PROGBUF_SIZE >= 16));
	assign start_acmd = 
		(abstractcs_cmderr == CMDERR_NONE) & (~abstractcs_busy) & 
		acmd_supported & acmd_hart_halted & 
		(acmd_transfer_nxt | acmd_postexec_nxt) & 
		dmi_want_launch_acmd;
	assign acmd_supported = 
		(acmd_cmdtype_nxt == 8'd0) & // 仅支持寄存器读写
		((acmd_aarsize_nxt == 3'b010) | (~acmd_transfer_nxt)) & // 仅支持32位寄存器读写位宽
		(~acmd_aarpostincrement_nxt) & // 不支持寄存器号自动递增
		((acmd_regno_nxt[15:5] == 11'b0001_0000000) | (~acmd_transfer_nxt)); // 仅支持读写GPRs
	assign acmd_hart_halted = hart_halted[hartsel] & hart_available[hartsel];
	assign illegal_access_while_abstractcs_busy = 
		(
			(dmi_write | dmi_read) & (
				(dmi_regaddr == ADDR_DATA0) | 
				((dmi_regaddr == (ADDR_PROGBUF_BASE + 0)) & (PROGBUF_SIZE >= 1)) | 
				((dmi_regaddr == (ADDR_PROGBUF_BASE + 1)) & (PROGBUF_SIZE >= 2)) | 
				((dmi_regaddr == (ADDR_PROGBUF_BASE + 2)) & (PROGBUF_SIZE >= 3)) | 
				((dmi_regaddr == (ADDR_PROGBUF_BASE + 3)) & (PROGBUF_SIZE >= 4)) | 
				((dmi_regaddr == (ADDR_PROGBUF_BASE + 4)) & (PROGBUF_SIZE >= 5)) | 
				((dmi_regaddr == (ADDR_PROGBUF_BASE + 5)) & (PROGBUF_SIZE >= 6)) | 
				((dmi_regaddr == (ADDR_PROGBUF_BASE + 6)) & (PROGBUF_SIZE >= 7)) | 
				((dmi_regaddr == (ADDR_PROGBUF_BASE + 7)) & (PROGBUF_SIZE >= 8)) | 
				((dmi_regaddr == (ADDR_PROGBUF_BASE + 8)) & (PROGBUF_SIZE >= 9)) | 
				((dmi_regaddr == (ADDR_PROGBUF_BASE + 9)) & (PROGBUF_SIZE >= 10)) | 
				((dmi_regaddr == (ADDR_PROGBUF_BASE + 10)) & (PROGBUF_SIZE >= 11)) | 
				((dmi_regaddr == (ADDR_PROGBUF_BASE + 11)) & (PROGBUF_SIZE >= 12)) | 
				((dmi_regaddr == (ADDR_PROGBUF_BASE + 12)) & (PROGBUF_SIZE >= 13)) | 
				((dmi_regaddr == (ADDR_PROGBUF_BASE + 13)) & (PROGBUF_SIZE >= 14)) | 
				((dmi_regaddr == (ADDR_PROGBUF_BASE + 14)) & (PROGBUF_SIZE >= 15)) | 
				((dmi_regaddr == (ADDR_PROGBUF_BASE + 15)) & (PROGBUF_SIZE >= 16))
			)
		) | abstractauto_en | acmd_en;
	
	assign progbuf_impebreak = 32'h00100073; // ebreak
	assign regs_rw_inst_1 = 32'h0ff0000f; // fence iorw, iorw
	assign regs_rw_inst_2 = 32'h00100073; // ebreak
	
	/*
	SPEC:
		Accessing these registers while an abstract command is executing causes cmderr to be set to 1 (busy) if it is 0.
		Attempts to write them while busy is set does not change their value.
	*/
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			abstract_data0 <= 32'h0000_0000;
		else if((~dmactive) | 
			// 注意: DM只能在abstractcs_busy无效时写该寄存器, 而HART可在任何时候写该寄存器, DM的写具有更高优先级
			(abstract_data0_en & (~abstractcs_busy)) | 
			(hart_access_en & (|hart_access_wen) & ({hart_access_addr, 2'b00} == DATA0_ADDR))
		)
			abstract_data0 <= # SIM_DELAY 
				{32{dmactive}} & 
				((abstract_data0_en & (~abstractcs_busy)) ? 
					dmi_wdata:
					(
						({{8{hart_access_wen[3]}}, {8{hart_access_wen[2]}}, {8{hart_access_wen[1]}}, {8{hart_access_wen[0]}}} & 
							hart_access_din) | 
						({{8{~hart_access_wen[3]}}, {8{~hart_access_wen[2]}}, {8{~hart_access_wen[1]}}, {8{~hart_access_wen[0]}}} & 
							abstract_data0)
					)
				);
	end
	
	/*
	SPEC:
		Accessing these registers while an abstract command is executing causes cmderr to be set to 1 (busy) if it is 0.
		Attempts to write them while busy is set does not change their value.
	*/
	genvar progbuf_i;
	generate
		for(progbuf_i = 0;progbuf_i < PROGBUF_SIZE + 1;progbuf_i = progbuf_i + 1)
		begin
			reg[31:0] progbuf_r;
			
			assign progbuf[progbuf_i] = 
				(progbuf_i < PROGBUF_SIZE) ? 
					progbuf_r:
					32'h00100073; // 隐含的EBREAK指令
			assign progbuf_en[progbuf_i] = dmi_write & (dmi_regaddr == (ADDR_PROGBUF_BASE + progbuf_i));
			
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					progbuf_r <= 32'h0000_0000;
				else if((~dmactive) | 
					(progbuf_en[progbuf_i] & (~abstractcs_busy))
				)
					progbuf_r <= # SIM_DELAY {32{dmactive}} & dmi_wdata;
			end
		end
	endgenerate
	
	/*
	Spec:
		If this register is written while an abstract command is executing then the write is ignored and cmderr
			becomes 1 (busy) once the command completes (busy becomes 0).
	*/
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			{abstractauto_autoexecprogbuf, abstractauto_autoexecdata} <= {16'd0, 1'b0};
		else if((~dmactive) | 
			// 注意: DM只能在abstractcs_busy无效时写该寄存器
			(abstractauto_en & (~abstractcs_busy))
		)
			{abstractauto_autoexecprogbuf, abstractauto_autoexecdata} <= # SIM_DELAY 
				dmactive ? 
					{dmi_wdata[31:16], dmi_wdata[0]}:
					{16'd0, 1'b0};
	end
	
	/*
	Spec:
		Writes to this register cause the corresponding abstract command to be executed.
		Writing this register while an abstract command is executing causes cmderr to become 1 (busy) once
			the command completes (busy becomes 0).
		If cmderr is non-zero, writes to this register are ignored.
	*/
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			{acmd_postexec, acmd_transfer, acmd_write, acmd_regno} <= {1'b0, 1'b0, 1'b0, 16'd0};
		else if((~dmactive) | 
			(acmd_en & (abstractcs_cmderr == CMDERR_NONE) & (~abstractcs_busy))
		)
			{acmd_postexec, acmd_transfer, acmd_write, acmd_regno} <= # SIM_DELAY 
				{19{dmactive}} & {acmd_postexec_nxt, acmd_transfer_nxt, acmd_write_nxt, acmd_regno_nxt};
	end
	
	// 注意: 未处理处理器在执行Program Buffer时的异常(即给出错误码CMDERR_EXCEPTION)!
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			abstractcs_cmderr <= CMDERR_NONE;
		else if(
			((acmd_exec_sts == ACMD_EXEC_STS_IDLE) & 
				((~acmd_supported) | (~acmd_hart_halted)) & (acmd_transfer_nxt | acmd_postexec_nxt) & dmi_want_launch_acmd) | 
			(abstractcs_busy & illegal_access_while_abstractcs_busy) | 
			abstractcs_en
		)
			abstractcs_cmderr <= # SIM_DELAY 
				abstractcs_en ? 
					(abstractcs_cmderr & (~dmi_wdata[10:8])):(
						abstractcs_busy ? 
							CMDERR_BUSY:(
								(~acmd_hart_halted) ? 
									CMDERR_HALT_RESUME:
									CMDERR_NOT_SUPPORTED
							)
					);
	end
	
	// 注意: 仅支持对GPRs的读写!
	always @(posedge clk)
	begin
		if(start_acmd & acmd_transfer_nxt)
			regs_rw_inst_0 <= # SIM_DELAY 
				acmd_write_nxt ? 
					// data0 -> GPRs, 使用指令: lw acmd_regno_nxt[4:0], DATA0_ADDR[11:0](x0)
					{DATA0_ADDR[11:0], 5'b00000, 3'b010, acmd_regno_nxt[4:0], 7'b0000011}:
					// GPRs -> data0, 使用指令: sw acmd_regno_nxt[4:0], DATA0_ADDR[11:0](x0)
					{DATA0_ADDR[11:5], acmd_regno_nxt[4:0], 5'b00000, 3'b010, DATA0_ADDR[4:0], 7'b0100011};
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			exec_progbuf <= 1'b0;
		else if(
			((acmd_exec_sts == ACMD_EXEC_STS_IDLE) & start_acmd) | 
			((acmd_exec_sts == ACMD_EXEC_STS_REGS_RW) & (~exec_progbuf) & acmd_postexec) | 
			(hart_access_en & hart_access_wen[0] & ({hart_access_addr, 2'b00} == ACMD_FLAGS_ADDR))
		)
			exec_progbuf <= # SIM_DELAY 
				(~(hart_access_en & hart_access_wen[0] & ({hart_access_addr, 2'b00} == ACMD_FLAGS_ADDR))) | hart_access_din[0];
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			acmd_exec_sts <= ACMD_EXEC_STS_IDLE;
		else if(
			((acmd_exec_sts == ACMD_EXEC_STS_IDLE) & start_acmd) | 
			((acmd_exec_sts == ACMD_EXEC_STS_REGS_RW) & (~exec_progbuf)) | 
			((acmd_exec_sts == ACMD_EXEC_STS_PROGBUF) & (~exec_progbuf))
		)
		begin
			case(acmd_exec_sts)
				ACMD_EXEC_STS_IDLE:
					acmd_exec_sts <= # SIM_DELAY 
						acmd_transfer_nxt ? ACMD_EXEC_STS_REGS_RW:ACMD_EXEC_STS_PROGBUF;
				ACMD_EXEC_STS_REGS_RW:
					acmd_exec_sts <= # SIM_DELAY 
						acmd_postexec ? ACMD_EXEC_STS_PROGBUF:ACMD_EXEC_STS_IDLE;
				ACMD_EXEC_STS_PROGBUF:
					acmd_exec_sts <= # SIM_DELAY ACMD_EXEC_STS_IDLE;
				default:
					acmd_exec_sts <= # SIM_DELAY ACMD_EXEC_STS_IDLE;
			endcase
		end
	end
	
	/** 存储映射读 **/
	// 注意: 这些寄存器(RO)位于存储映射(地址 = PROGBUF0_ADDR~(PROGBUF0_ADDR + 4 * PROGBUF_SIZE))上!
	wire[31:0] progbuf_mem_rd[0:PROGBUF_SIZE];
	reg[31:0] hart_access_dout_r;
	
	assign hart_access_dout = hart_access_dout_r;
	
	genvar progbuf_mem_rd_i;
	generate
		for(progbuf_mem_rd_i = 0;progbuf_mem_rd_i < PROGBUF_SIZE + 1;progbuf_mem_rd_i = progbuf_mem_rd_i + 1)
		begin
			assign progbuf_mem_rd[progbuf_mem_rd_i] = 
				(acmd_exec_sts == ACMD_EXEC_STS_PROGBUF) ? 
					progbuf[progbuf_mem_rd_i]:(
						(progbuf_mem_rd_i == 0) ? regs_rw_inst_0:
						(progbuf_mem_rd_i == 1) ? regs_rw_inst_1:
							regs_rw_inst_2
					);
		end
	endgenerate
	
	// 预设一些Debug Mode下的服务程序???
	always @(posedge clk)
	begin
		if(hart_access_en)
		begin
			case({hart_access_addr, 2'b00})
				DATA0_ADDR: hart_access_dout_r <= # SIM_DELAY abstract_data0;
				
				PROGBUF0_ADDR + 0: hart_access_dout_r <= # SIM_DELAY progbuf_mem_rd[(PROGBUF_SIZE >= 0) ? 0:PROGBUF_SIZE];
				PROGBUF0_ADDR + 4: hart_access_dout_r <= # SIM_DELAY progbuf_mem_rd[(PROGBUF_SIZE >= 1) ? 1:PROGBUF_SIZE];
				PROGBUF0_ADDR + 8: hart_access_dout_r <= # SIM_DELAY progbuf_mem_rd[(PROGBUF_SIZE >= 2) ? 2:PROGBUF_SIZE];
				PROGBUF0_ADDR + 12: hart_access_dout_r <= # SIM_DELAY progbuf_mem_rd[(PROGBUF_SIZE >= 3) ? 3:PROGBUF_SIZE];
				PROGBUF0_ADDR + 16: hart_access_dout_r <= # SIM_DELAY progbuf_mem_rd[(PROGBUF_SIZE >= 4) ? 4:PROGBUF_SIZE];
				PROGBUF0_ADDR + 20: hart_access_dout_r <= # SIM_DELAY progbuf_mem_rd[(PROGBUF_SIZE >= 5) ? 5:PROGBUF_SIZE];
				PROGBUF0_ADDR + 24: hart_access_dout_r <= # SIM_DELAY progbuf_mem_rd[(PROGBUF_SIZE >= 6) ? 6:PROGBUF_SIZE];
				PROGBUF0_ADDR + 28: hart_access_dout_r <= # SIM_DELAY progbuf_mem_rd[(PROGBUF_SIZE >= 7) ? 7:PROGBUF_SIZE];
				PROGBUF0_ADDR + 32: hart_access_dout_r <= # SIM_DELAY progbuf_mem_rd[(PROGBUF_SIZE >= 8) ? 8:PROGBUF_SIZE];
				PROGBUF0_ADDR + 36: hart_access_dout_r <= # SIM_DELAY progbuf_mem_rd[(PROGBUF_SIZE >= 9) ? 9:PROGBUF_SIZE];
				PROGBUF0_ADDR + 40: hart_access_dout_r <= # SIM_DELAY progbuf_mem_rd[(PROGBUF_SIZE >= 10) ? 10:PROGBUF_SIZE];
				PROGBUF0_ADDR + 44: hart_access_dout_r <= # SIM_DELAY progbuf_mem_rd[(PROGBUF_SIZE >= 11) ? 11:PROGBUF_SIZE];
				PROGBUF0_ADDR + 48: hart_access_dout_r <= # SIM_DELAY progbuf_mem_rd[(PROGBUF_SIZE >= 12) ? 12:PROGBUF_SIZE];
				PROGBUF0_ADDR + 52: hart_access_dout_r <= # SIM_DELAY progbuf_mem_rd[(PROGBUF_SIZE >= 13) ? 13:PROGBUF_SIZE];
				PROGBUF0_ADDR + 56: hart_access_dout_r <= # SIM_DELAY progbuf_mem_rd[(PROGBUF_SIZE >= 14) ? 14:PROGBUF_SIZE];
				PROGBUF0_ADDR + 60: hart_access_dout_r <= # SIM_DELAY progbuf_mem_rd[(PROGBUF_SIZE >= 15) ? 15:PROGBUF_SIZE];
				PROGBUF0_ADDR + 64: hart_access_dout_r <= # SIM_DELAY progbuf_mem_rd[(PROGBUF_SIZE >= 16) ? 16:PROGBUF_SIZE];
				
				ACMD_FLAGS_ADDR: hart_access_dout_r <= # SIM_DELAY {31'd0, exec_progbuf};
				
				default: hart_access_dout_r <= # SIM_DELAY 32'h0000_0000;
			endcase
		end
	end
	
	/** DM寄存器读结果 **/
	reg[31:0] s_dmi_prdata_r;
	
	assign s_dmi_prdata = s_dmi_prdata_r;
	
	always @(posedge clk)
	begin
		if(s_dmi_psel & (~s_dmi_pwrite))
		begin
			case(dmi_regaddr)
				ADDR_DATA0: s_dmi_prdata_r <= # SIM_DELAY abstract_data0;
				ADDR_DMCONTROL: s_dmi_prdata_r <= # SIM_DELAY {
					1'b0, // haltreq
					1'b0, // resumereq
					dmcontrol_hartreset[hartsel], // hartreset
					1'b0, // ackhavereset
					1'b0, // reserved(0.13.2), ackunavail(1.0)
					1'b0, // hasel
					{{(10-(clogb2(HARTS_N-1)+1)){1'b0}}, hartsel}, // hartsello
					10'd0, // hartselhi
					1'b0, // reserved(0.13.2), setkeepalive(1.0)
					1'b0, // reserved(0.13.2), clrkeepalive(1.0)
					1'b0, // setresethaltreq
					1'b0, // clrresethaltreq
					dmcontrol_ndmreset, // ndmreset
					dmactive // dmactive
				};
				ADDR_DMSTATUS: s_dmi_prdata_r <= # SIM_DELAY {
					7'd0, // reserved
					1'b0, // reserved(0.13.2), ndmresetpending(1.0)
					1'b0, // reserved(0.13.2), stickyunavail(1.0)
					1'b1, // impebreak
					1'b0, // reserved
					dmstatus_havereset[hartsel], // allhavereset
					dmstatus_havereset[hartsel], // anyhavereset
					dmstatus_resumeack[hartsel], // allresumeack
					dmstatus_resumeack[hartsel], // anyresumeack
					hartsel >= HARTS_N, // allnonexistent
					hartsel >= HARTS_N, // anynonexistent
					~hart_available[hartsel], // allunavail
					~hart_available[hartsel], // anyunavail
					hart_running[hartsel] & hart_available[hartsel], // allrunning
					hart_running[hartsel] & hart_available[hartsel], // anyrunning
					hart_halted[hartsel] & hart_available[hartsel], // allhalted
					hart_halted[hartsel] & hart_available[hartsel], // anyhalted
					1'b1, // authenticated
					1'b0, // authbusy
					1'b1, // hasresethaltreq
					1'b0, // confstrptrvalid
					DM_VERSION[3:0] // version
				};
				ADDR_HARTINFO: s_dmi_prdata_r <= # SIM_DELAY {
					8'd0, // reserved
					SCRATCH_N[3:0], // nscratch
					3'd0, // reserved
					1'b1, // dataaccess: memory
					4'd1, // datasize
					DATA0_ADDR[11:0] // dataaddr
				};
				ADDR_HALTSUM0: s_dmi_prdata_r <= # SIM_DELAY {
					{(32 - HARTS_N){1'b0}}, 
					hart_halted & hart_available
				};
				ADDR_HALTSUM1: s_dmi_prdata_r <= # SIM_DELAY {
					31'd0, 
					|(hart_halted & hart_available)
				};
				ADDR_HAWINDOWSEL: s_dmi_prdata_r <= # SIM_DELAY 32'h0000_0000;
				ADDR_HAWINDOW: s_dmi_prdata_r <= # SIM_DELAY 32'h0000_0000;
				ADDR_ABSTRACTCS: s_dmi_prdata_r <= # SIM_DELAY {
					3'b000, // reserved
					PROGBUF_SIZE[4:0], // progbufsize
					11'd0, // reserved
					abstractcs_busy, // busy
					1'b0, // relaxedpriv
					abstractcs_cmderr, // cmderr
					4'd0, // reserved
					4'd1 // datacount
				};
				ADDR_ABSTRACTAUTO: s_dmi_prdata_r <= # SIM_DELAY {
					abstractauto_autoexecprogbuf, // autoexecprogbuf
					4'd0, // reserved
					{11'd0, abstractauto_autoexecdata} // autoexecdata
				};
				ADDR_SBCS: s_dmi_prdata_r <= # SIM_DELAY {
					3'd1, // sbversion
					6'd0, // reserved
					sbbusyerror, // sbbusyerror
					sbbusy, // sbbusy
					sbreadonaddr, // sbreadonaddr
					sbaccess, // sbaccess
					sbautoincrement, // sbautoincrement
					sbreadondata, // sbreadondata
					sberror, // sberror
					7'd32, // sbasize
					5'b00111 // sbaccess128, sbaccess64, sbaccess32, sbaccess16, sbaccess8
				} & ((SBUS_SUPPORTED == "true") ? 32'hffff_ffff:32'h0000_0000);
				ADDR_SBDATA0: s_dmi_prdata_r <= # SIM_DELAY sbdata & ((SBUS_SUPPORTED == "true") ? 32'hffff_ffff:32'h0000_0000);
				ADDR_SBADDRESS0: s_dmi_prdata_r <= # SIM_DELAY sbaddress & ((SBUS_SUPPORTED == "true") ? 32'hffff_ffff:32'h0000_0000);
				ADDR_CONFSTRPTR0: s_dmi_prdata_r <= # SIM_DELAY 32'h4c296328;
				ADDR_CONFSTRPTR1: s_dmi_prdata_r <= # SIM_DELAY 32'h20656b75;
				ADDR_CONFSTRPTR2: s_dmi_prdata_r <= # SIM_DELAY 32'h6e657257;
				ADDR_CONFSTRPTR3: s_dmi_prdata_r <= # SIM_DELAY 32'h31322720;
				ADDR_NEXTDM: s_dmi_prdata_r <= # SIM_DELAY NEXT_DM_ADDR;
				ADDR_PROGBUF_BASE + 0: s_dmi_prdata_r <= # SIM_DELAY 
					progbuf[0];
				ADDR_PROGBUF_BASE + 1: s_dmi_prdata_r <= # SIM_DELAY 
					(PROGBUF_SIZE >= 2) ? progbuf[(PROGBUF_SIZE >= 2) ? 1:0]:32'h0000_0000;
				ADDR_PROGBUF_BASE + 2: s_dmi_prdata_r <= # SIM_DELAY 
					(PROGBUF_SIZE >= 3) ? progbuf[(PROGBUF_SIZE >= 3) ? 2:0]:32'h0000_0000;
				ADDR_PROGBUF_BASE + 3: s_dmi_prdata_r <= # SIM_DELAY 
					(PROGBUF_SIZE >= 4) ? progbuf[(PROGBUF_SIZE >= 4) ? 3:0]:32'h0000_0000;
				ADDR_PROGBUF_BASE + 4: s_dmi_prdata_r <= # SIM_DELAY 
					(PROGBUF_SIZE >= 5) ? progbuf[(PROGBUF_SIZE >= 5) ? 4:0]:32'h0000_0000;
				ADDR_PROGBUF_BASE + 5: s_dmi_prdata_r <= # SIM_DELAY 
					(PROGBUF_SIZE >= 6) ? progbuf[(PROGBUF_SIZE >= 6) ? 5:0]:32'h0000_0000;
				ADDR_PROGBUF_BASE + 6: s_dmi_prdata_r <= # SIM_DELAY 
					(PROGBUF_SIZE >= 7) ? progbuf[(PROGBUF_SIZE >= 7) ? 6:0]:32'h0000_0000;
				ADDR_PROGBUF_BASE + 7: s_dmi_prdata_r <= # SIM_DELAY 
					(PROGBUF_SIZE >= 8) ? progbuf[(PROGBUF_SIZE >= 8) ? 7:0]:32'h0000_0000;
				ADDR_PROGBUF_BASE + 8: s_dmi_prdata_r <= # SIM_DELAY 
					(PROGBUF_SIZE >= 9) ? progbuf[(PROGBUF_SIZE >= 9) ? 8:0]:32'h0000_0000;
				ADDR_PROGBUF_BASE + 9: s_dmi_prdata_r <= # SIM_DELAY 
					(PROGBUF_SIZE >= 10) ? progbuf[(PROGBUF_SIZE >= 10) ? 9:0]:32'h0000_0000;
				ADDR_PROGBUF_BASE + 10: s_dmi_prdata_r <= # SIM_DELAY 
					(PROGBUF_SIZE >= 11) ? progbuf[(PROGBUF_SIZE >= 11) ? 10:0]:32'h0000_0000;
				ADDR_PROGBUF_BASE + 11: s_dmi_prdata_r <= # SIM_DELAY 
					(PROGBUF_SIZE >= 12) ? progbuf[(PROGBUF_SIZE >= 12) ? 11:0]:32'h0000_0000;
				ADDR_PROGBUF_BASE + 12: s_dmi_prdata_r <= # SIM_DELAY 
					(PROGBUF_SIZE >= 13) ? progbuf[(PROGBUF_SIZE >= 13) ? 12:0]:32'h0000_0000;
				ADDR_PROGBUF_BASE + 13: s_dmi_prdata_r <= # SIM_DELAY 
					(PROGBUF_SIZE >= 14) ? progbuf[(PROGBUF_SIZE >= 14) ? 13:0]:32'h0000_0000;
				ADDR_PROGBUF_BASE + 14: s_dmi_prdata_r <= # SIM_DELAY 
					(PROGBUF_SIZE >= 15) ? progbuf[(PROGBUF_SIZE >= 15) ? 14:0]:32'h0000_0000;
				ADDR_PROGBUF_BASE + 15: s_dmi_prdata_r <= # SIM_DELAY 
					(PROGBUF_SIZE >= 16) ? progbuf[(PROGBUF_SIZE >= 16) ? 15:0]:32'h0000_0000;
				default: s_dmi_prdata_r <= # SIM_DELAY 32'h0000_0000;
			endcase
		end
	end
	
endmodule
