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
请填写

注意：
请填写


协议:
APB SLAVE
ICB MASTER
MEM SLAVE

作者: 陈家耀
日期: 2025/02/06
********************************************************************/


module jtag_dm #(
	parameter integer ABITS = 7, // DMI地址位宽(必须在范围[7, 32]内)
	parameter integer HARTS_N = 1, // HART个数(必须在范围[1, 32]内)
	parameter SBUS_SUPPORTED = "true", // 是否支持系统总线访问
	parameter integer PROGBUF_SIZE = 4, // Program Buffer的大小(以双字计, 必须在范围[2, 16]内)
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
	reg[clogb2(HARTS_N-1):0] hartsel;
	wire[clogb2(HARTS_N-1):0] hartsel_nxt;
	
	// 注意: 仅支持hartsel的低10位(hartsello)!
	assign hartsel_nxt = 
		(HARTS_N > 1) ? 
			(dmcontrol_en ? dmi_wdata[16+clogb2(HARTS_N-1):16]:hartsel):
			1'b0;
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			hartsel <= 0;
		else if((~dmactive) | dmcontrol_en)
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
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
		begin
			dmcontrol_haltreq <= {HARTS_N{1'b0}};
			dmcontrol_hartreset <= {HARTS_N{1'b0}};
			dmcontrol_resethaltreq <= {HARTS_N{1'b0}};
			dmcontrol_ndmreset <= 1'b0;
		end
		else if((~dmactive) | dmcontrol_en)
		begin
			dmcontrol_haltreq <= # SIM_DELAY {HARTS_N{dmactive}} & (
				(dmcontrol_haltreq & (~dmcontrol_op_mask)) | 
				// haltreq
				({HARTS_N{dmi_wdata[31]}} & dmcontrol_op_mask)
			);
			dmcontrol_hartreset <= # SIM_DELAY {HARTS_N{dmactive}} & (
				(dmcontrol_hartreset & (~dmcontrol_op_mask)) | 
				// hartreset
				({HARTS_N{dmi_wdata[29]}} & dmcontrol_op_mask)
			);
			dmcontrol_resethaltreq <= # SIM_DELAY {HARTS_N{dmactive}} & (
				// clrresethaltreq
				(dmcontrol_resethaltreq & (~({HARTS_N{dmi_wdata[2]}} & dmcontrol_op_mask))) | 
				// setresethaltreq
				({HARTS_N{dmi_wdata[3]}} & dmcontrol_op_mask)
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
					(dmcontrol_en & dmi_wdata[28] & dmcontrol_op_mask[dmstatus_havereset_i])
				)
					dmstatus_havereset[dmstatus_havereset_i] <= # SIM_DELAY 
						dmactive & 
						(hart_reset_fns[dmstatus_havereset_i] & (~hart_reset_fns_d[dmstatus_havereset_i])) & 
						// ackhavereset
						(~(dmcontrol_en & dmi_wdata[28] & dmcontrol_op_mask[dmstatus_havereset_i]));
			end
		end
	endgenerate
	
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
					(dmcontrol_en & (~dmi_wdata[31]) & dmi_wdata[30] & dmcontrol_op_mask[dmstatus_resumeack_i])
				)
					dmstatus_resumeack[dmstatus_resumeack_i] <= # SIM_DELAY 
						dmactive & 
						(hart_req_resume[dmstatus_resumeack_i] & 
							hart_running[dmstatus_resumeack_i] & hart_available[dmstatus_resumeack_i]) & 
						(~(dmcontrol_en & (~dmi_wdata[31]) & dmi_wdata[30] & dmcontrol_op_mask[dmstatus_resumeack_i]));
			end
		end
	endgenerate
	
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
					(dmcontrol_en & (~dmi_wdata[31]) & dmi_wdata[30] & dmcontrol_op_mask[dmcontrol_resumereq_i])
				)
					dmcontrol_resumereq[dmcontrol_resumereq_i] <= # SIM_DELAY 
						dmactive & (
							(~(hart_running[dmcontrol_resumereq_i] & hart_available[dmcontrol_resumereq_i])) | 
							(dmcontrol_en & (~dmi_wdata[31]) & dmi_wdata[30] & dmcontrol_op_mask[dmcontrol_resumereq_i])
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
	reg sbus_vld_suppress; // 镇压系统总线命令通道
	wire sbaddress0_en;
	wire sbdata0_en;
	wire sbcs_en;
	wire sb_access_illegal_when_busy;
	wire sb_want_start_read;
	wire sb_want_start_write;
	wire[1:0] sb_next_align;
	wire sb_badsize;
	wire sb_badalign;
	
	assign m_icb_cmd_sbus_addr = sbaddress;
	assign m_icb_cmd_sbus_read = sbus_is_read_latched;
	assign m_icb_cmd_sbus_wdata = 
		({32{sbaccess[1:0] == 2'b00}} & {4{sbdata[7:0]}}) | 
		({32{sbaccess[1:0] == 2'b01}} & {2{sbdata[15:0]}}) | 
		({32{sbaccess[1:0] == 2'b10}} & sbdata);
	assign m_icb_cmd_sbus_wmask = 
		{{2{sbaccess[1:0] == 2'b10}}, (sbaccess[1:0] == 2'b10) | (sbaccess[1:0] == 2'b01), 1'b1} << sbaddress[1:0];
	assign m_icb_cmd_sbus_valid = sbbusy & (~sbus_vld_suppress);
	
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
	
	assign sb_next_align = 
		(sbreadonaddr & dmi_write & (dmi_regaddr == ADDR_SBADDRESS0)) ? 
			dmi_wdata[1:0]:
			sbaddress[1:0];
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
					{1'b0, 3'b010, 1'b0, 1'b0}
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
				((sb_want_start_read | sb_want_start_write) & (~sbbusyerror) & (sberror == SBERROR_NONE) & (~sb_badsize) & (~sb_badalign))
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
		if(dmactive & (sb_want_start_read | sb_want_start_write) & (~sbbusy) & (~sbbusyerror) & (sberror == SBERROR_NONE))
			sbus_is_read_latched <= # SIM_DELAY ~sb_want_start_write;
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			sbus_vld_suppress <= 1'b0;
		else if((~dmactive) | 
			(sbbusy & (sbus_vld_suppress ? 
				m_icb_rsp_sbus_valid:
				(m_icb_cmd_sbus_ready & (~m_icb_rsp_sbus_valid))
			))
		)
			sbus_vld_suppress <= # SIM_DELAY dmactive & (~sbus_vld_suppress);
	end
	
	/** 抽象命令 **/
	reg[31:0] abstract_data0;
	reg[31:0] progbuf[0:PROGBUF_SIZE-1];
	reg abstractauto_autoexecdata;
	reg[1:0] abstractauto_autoexecprogbuf;
	reg acmd_postexec;
	reg acmd_transfer;
	reg acmd_write;
	reg[15:0] acmd_regno;
	
	// 请实现!!!
	
endmodule
