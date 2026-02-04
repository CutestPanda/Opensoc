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
本模块: 总线互联单元

描述:
CPU核内指令ICB从机 ------------------------- 外部(指令总线)存储器AXI主机
                                                           |
											               |
           |------------------------------------------------
		   |
CPU核内数据存储器AXI从机 ------------------- 外部(数据总线)存储器AXI主机

CPU核内指令ICB总线只能访问外部的(指令总线)存储器AXI总线
CPU核内数据存储器AXI总线可以根据地址区间访问外部的(指令/数据)存储器AXI总线

注意：
CPU核内指令ICB从机必须是只读(Read Only)的

协议:
ICB SLAVE
AXI-Lite MASTER/SLAVE

作者: 陈家耀
日期: 2026/01/29
********************************************************************/


module panda_risc_v_biu #(
	parameter integer AXI_MEM_DATA_WIDTH = 64, // 存储器AXI主机的数据位宽(32 | 64 | 128 | 256)
	parameter IMEM_BASEADDR = 32'h0000_0000, // 指令存储器基址
	parameter integer IMEM_ADDR_RANGE = 32 * 1024, // 指令存储器地址区间长度(以字节计)
	parameter DM_REGS_BASEADDR = 32'hFFFF_F800, // DM寄存器区基址
	parameter integer DM_REGS_ADDR_RANGE = 1 * 1024, // DM寄存器区地址区间长度(以字节计)
	parameter DEBUG_SUPPORTED = "true", // 是否需要支持Debug
	parameter EN_LOW_LATENCY_DMEM_RD = "false", // 是否使能低时延的数据存储器读模式
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// CPU核内指令ICB从机
	// [命令通道]
	input wire[31:0] s_icb_cmd_inst_addr,
	input wire s_icb_cmd_inst_read,
	input wire[31:0] s_icb_cmd_inst_wdata,
	input wire[3:0] s_icb_cmd_inst_wmask,
	input wire s_icb_cmd_inst_valid,
	output wire s_icb_cmd_inst_ready,
	// [响应通道]
	output wire[31:0] s_icb_rsp_inst_rdata,
	output wire s_icb_rsp_inst_err,
	output wire s_icb_rsp_inst_valid,
	input wire s_icb_rsp_inst_ready,
	
	// CPU核内数据存储器AXI从机
	// [AR通道]
	input wire[31:0] s_axi_dmem_araddr,
	input wire[1:0] s_axi_dmem_arburst,
	input wire[7:0] s_axi_dmem_arlen,
	input wire[2:0] s_axi_dmem_arsize,
	input wire s_axi_dmem_arvalid,
	output wire s_axi_dmem_arready,
	// [R通道]
	output wire[AXI_MEM_DATA_WIDTH-1:0] s_axi_dmem_rdata,
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
	input wire[AXI_MEM_DATA_WIDTH-1:0] s_axi_dmem_wdata,
	input wire[AXI_MEM_DATA_WIDTH/8-1:0] s_axi_dmem_wstrb,
	input wire s_axi_dmem_wlast,
	input wire s_axi_dmem_wvalid,
	output wire s_axi_dmem_wready,
	
	// 外部(指令总线)存储器AXI主机
	// [AR通道]
	output wire[31:0] m_axi_imem_araddr,
	output wire[1:0] m_axi_imem_arburst,
	output wire[7:0] m_axi_imem_arlen,
	output wire[2:0] m_axi_imem_arsize,
	output wire m_axi_imem_arvalid,
	input wire m_axi_imem_arready,
	// [R通道]
	input wire[AXI_MEM_DATA_WIDTH-1:0] m_axi_imem_rdata,
	input wire[1:0] m_axi_imem_rresp,
	input wire m_axi_imem_rlast,
	input wire m_axi_imem_rvalid,
	output wire m_axi_imem_rready,
	// [AW通道]
	output wire[31:0] m_axi_imem_awaddr,
	output wire[1:0] m_axi_imem_awburst,
	output wire[7:0] m_axi_imem_awlen,
	output wire[2:0] m_axi_imem_awsize,
	output wire m_axi_imem_awvalid,
	input wire m_axi_imem_awready,
	// [B通道]
	input wire[1:0] m_axi_imem_bresp,
	input wire m_axi_imem_bvalid,
	output wire m_axi_imem_bready,
	// [W通道]
	output wire[AXI_MEM_DATA_WIDTH-1:0] m_axi_imem_wdata,
	output wire[AXI_MEM_DATA_WIDTH/8-1:0] m_axi_imem_wstrb,
	output wire m_axi_imem_wlast,
	output wire m_axi_imem_wvalid,
	input wire m_axi_imem_wready,
	
	// 外部(数据总线)存储器AXI主机
	// [AR通道]
	output wire[31:0] m_axi_dmem_araddr,
	output wire[1:0] m_axi_dmem_arburst,
	output wire[7:0] m_axi_dmem_arlen,
	output wire[2:0] m_axi_dmem_arsize,
	output wire m_axi_dmem_arvalid,
	input wire m_axi_dmem_arready,
	// [R通道]
	input wire[AXI_MEM_DATA_WIDTH-1:0] m_axi_dmem_rdata,
	input wire[1:0] m_axi_dmem_rresp,
	input wire m_axi_dmem_rlast,
	input wire m_axi_dmem_rvalid,
	output wire m_axi_dmem_rready,
	// [AW通道]
	output wire[31:0] m_axi_dmem_awaddr,
	output wire[1:0] m_axi_dmem_awburst,
	output wire[7:0] m_axi_dmem_awlen,
	output wire[2:0] m_axi_dmem_awsize,
	output wire m_axi_dmem_awvalid,
	input wire m_axi_dmem_awready,
	// [B通道]
	input wire[1:0] m_axi_dmem_bresp,
	input wire m_axi_dmem_bvalid,
	output wire m_axi_dmem_bready,
	// [W通道]
	output wire[AXI_MEM_DATA_WIDTH-1:0] m_axi_dmem_wdata,
	output wire[AXI_MEM_DATA_WIDTH/8-1:0] m_axi_dmem_wstrb,
	output wire m_axi_dmem_wlast,
	output wire m_axi_dmem_wvalid,
	input wire m_axi_dmem_wready
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
	// AXI响应类型
	localparam AXI_RESP_OKAY = 2'b00;
	localparam AXI_RESP_EXOKAY = 2'b01;
	localparam AXI_RESP_SLVERR = 2'b10;
	localparam AXI_RESP_DECERR = 2'b11;
	
	/** 读通道互联 **/
	// [外部指令总线访问信息fifo]
	wire imem_rd_access_msg_fifo_wen;
	wire imem_rd_access_msg_fifo_din_initiated_by_ibus; // 由CPU核内指令总线发起访问(标志)
	wire[1:0] imem_rd_access_msg_fifo_din_rdata_buf_id; // 分配的读数据缓存条目ID
	wire[2:0] imem_rd_access_msg_fifo_din_word_sel; // 字选择
	wire imem_rd_access_msg_fifo_full_n;
	wire imem_rd_access_msg_fifo_ren;
	wire imem_rd_access_msg_fifo_dout_initiated_by_ibus; // 由CPU核内指令总线发起访问(标志)
	wire[1:0] imem_rd_access_msg_fifo_dout_rdata_buf_id; // 分配的读数据缓存条目ID
	wire[2:0] imem_rd_access_msg_fifo_dout_word_sel; // 字选择
	wire imem_rd_access_msg_fifo_empty_n;
	// [外部数据总线访问信息fifo]
	wire dmem_rd_access_msg_fifo_wen;
	wire[1:0] dmem_rd_access_msg_fifo_din_rdata_buf_id; // 分配的读数据缓存条目ID
	wire dmem_rd_access_msg_fifo_full_n;
	wire dmem_rd_access_msg_fifo_ren;
	wire[1:0] dmem_rd_access_msg_fifo_dout_rdata_buf_id; // 分配的读数据缓存条目ID
	wire dmem_rd_access_msg_fifo_empty_n;
	// [内部数据总线读数据缓存]
	reg[AXI_MEM_DATA_WIDTH-1:0] dbus_rd_chn_buf_rdata[0:3]; // 读数据
	reg[1:0] dbus_rd_chn_buf_rresp[0:3]; // 读响应
	reg[3:0] dbus_rd_chn_buf_filled_flag; // 条目已填充标志
	reg[1:0] dbus_rd_chn_buf_wptr; // 缓存写指针
	reg[1:0] dbus_rd_chn_buf_rptr; // 缓存读指针
	reg[2:0] dbus_rd_chn_buf_vld_entry_n; // 有效条目数
	reg dbus_rd_chn_buf_full_flag; // 缓存满标志
	// [地址译码]
	wire dbus_rd_chn_fall_into_inst_region; // 地址落在指令区
	// [外部指令总线访问仲裁]
	wire imem_rd_access_req_from_ibus; // 来自内部指令总线的请求
	wire imem_rd_access_req_from_dbus; // 来自内部数据总线的请求
	wire imem_rd_access_instant_arb_res; // 即时仲裁结果(是否许可给内部指令总线)
	wire imem_rd_access_grant_to_ibus; // 许可给内部指令总线
	reg imem_rd_access_arb_locked_flag; // 仲裁锁定(标志)
	reg imem_rd_access_locked_arb_res; // 锁定的仲裁结果(是否许可给内部指令总线)
	reg imem_rd_access_grant_to_ibus_if_conflict; // 冲突时许可给内部指令总线
	
	// CPU核内指令ICB从机(只读)
	// [命令通道]
	assign s_icb_cmd_inst_ready = 
		imem_rd_access_msg_fifo_full_n & imem_rd_access_grant_to_ibus & m_axi_imem_arready;
	// [响应通道]
	assign s_icb_rsp_inst_rdata = m_axi_imem_rdata >> (imem_rd_access_msg_fifo_dout_word_sel * 32);
	assign s_icb_rsp_inst_err = m_axi_imem_rresp != AXI_RESP_OKAY;
	assign s_icb_rsp_inst_valid = 
		imem_rd_access_msg_fifo_empty_n & imem_rd_access_msg_fifo_dout_initiated_by_ibus & 
		m_axi_imem_rvalid;
	
	// CPU核内数据存储器AXI从机读通道
	// [AR通道]
	assign s_axi_dmem_arready = 
		(~dbus_rd_chn_buf_full_flag) & 
		(
			dbus_rd_chn_fall_into_inst_region ? 
				(imem_rd_access_msg_fifo_full_n & (~imem_rd_access_grant_to_ibus) & m_axi_imem_arready):
				(dmem_rd_access_msg_fifo_full_n & m_axi_dmem_arready)
		);
	// [R通道]
	assign s_axi_dmem_rdata = 
		(
			(EN_LOW_LATENCY_DMEM_RD == "true") & 
			dmem_rd_access_msg_fifo_empty_n & 
			(dmem_rd_access_msg_fifo_dout_rdata_buf_id == dbus_rd_chn_buf_rptr) & 
			dmem_rd_access_msg_fifo_ren
		) ? 
			m_axi_dmem_rdata:
			dbus_rd_chn_buf_rdata[dbus_rd_chn_buf_rptr];
	assign s_axi_dmem_rresp = 
		(
			(EN_LOW_LATENCY_DMEM_RD == "true") & 
			dmem_rd_access_msg_fifo_empty_n & 
			(dmem_rd_access_msg_fifo_dout_rdata_buf_id == dbus_rd_chn_buf_rptr) & 
			dmem_rd_access_msg_fifo_ren
		) ? 
			m_axi_dmem_rresp:
			dbus_rd_chn_buf_rresp[dbus_rd_chn_buf_rptr];
	assign s_axi_dmem_rlast = 1'b1;
	assign s_axi_dmem_rvalid = 
		dbus_rd_chn_buf_filled_flag[dbus_rd_chn_buf_rptr] | 
		(
			(EN_LOW_LATENCY_DMEM_RD == "true") & 
			dmem_rd_access_msg_fifo_empty_n & 
			(dmem_rd_access_msg_fifo_dout_rdata_buf_id == dbus_rd_chn_buf_rptr) & 
			dmem_rd_access_msg_fifo_ren
		);
	
	// 外部(指令总线)存储器AXI主机读通道
	// [AR通道]
	assign m_axi_imem_araddr = 
		imem_rd_access_grant_to_ibus ? 
			(s_icb_cmd_inst_addr & (~(AXI_MEM_DATA_WIDTH/8 - 1))):
			s_axi_dmem_araddr;
	assign m_axi_imem_arburst = 
		imem_rd_access_grant_to_ibus ? 
			2'b01:
			s_axi_dmem_arburst;
	assign m_axi_imem_arlen = 
		imem_rd_access_grant_to_ibus ? 
			8'd0:
			s_axi_dmem_arlen;
	assign m_axi_imem_arsize = 
		imem_rd_access_grant_to_ibus ? 
			clogb2(AXI_MEM_DATA_WIDTH/8):
			s_axi_dmem_arsize;
	assign m_axi_imem_arvalid = 
		imem_rd_access_msg_fifo_full_n & 
		(
			imem_rd_access_grant_to_ibus ? 
				s_icb_cmd_inst_valid:
				(s_axi_dmem_arvalid & dbus_rd_chn_fall_into_inst_region & (~dbus_rd_chn_buf_full_flag))
		);
	// [R通道]
	assign m_axi_imem_rready = 
		imem_rd_access_msg_fifo_empty_n & 
		((~imem_rd_access_msg_fifo_dout_initiated_by_ibus) | s_icb_rsp_inst_ready);
	
	// 外部(数据总线)存储器AXI主机读通道
	// [AR通道]
	assign m_axi_dmem_araddr = s_axi_dmem_araddr;
	assign m_axi_dmem_arburst = s_axi_dmem_arburst;
	assign m_axi_dmem_arlen = s_axi_dmem_arlen;
	assign m_axi_dmem_arsize = s_axi_dmem_arsize;
	assign m_axi_dmem_arvalid = 
		(~dbus_rd_chn_buf_full_flag) & s_axi_dmem_arvalid & dmem_rd_access_msg_fifo_full_n & (~dbus_rd_chn_fall_into_inst_region);
	// [R通道]
	assign m_axi_dmem_rready = 
		dmem_rd_access_msg_fifo_empty_n;
	
	assign imem_rd_access_msg_fifo_wen = 
		m_axi_imem_arready & 
		(
			imem_rd_access_grant_to_ibus ? 
				s_icb_cmd_inst_valid:
				(s_axi_dmem_arvalid & dbus_rd_chn_fall_into_inst_region & (~dbus_rd_chn_buf_full_flag))
		);
	assign imem_rd_access_msg_fifo_din_initiated_by_ibus = imem_rd_access_grant_to_ibus;
	assign imem_rd_access_msg_fifo_din_rdata_buf_id = dbus_rd_chn_buf_wptr;
	assign imem_rd_access_msg_fifo_din_word_sel = s_icb_cmd_inst_addr[31:2] & (AXI_MEM_DATA_WIDTH/32 - 1);
	assign imem_rd_access_msg_fifo_ren = 
		m_axi_imem_rvalid & ((~imem_rd_access_msg_fifo_dout_initiated_by_ibus) | s_icb_rsp_inst_ready);
	
	assign dmem_rd_access_msg_fifo_wen = 
		(~dbus_rd_chn_buf_full_flag) & s_axi_dmem_arvalid & m_axi_dmem_arready & (~dbus_rd_chn_fall_into_inst_region);
	assign dmem_rd_access_msg_fifo_din_rdata_buf_id = 
		dbus_rd_chn_buf_wptr;
	assign dmem_rd_access_msg_fifo_ren = 
		m_axi_dmem_rvalid;
	
	assign dbus_rd_chn_fall_into_inst_region = 
		((s_axi_dmem_araddr >= IMEM_BASEADDR) & (s_axi_dmem_araddr < (IMEM_BASEADDR + IMEM_ADDR_RANGE))) | 
		((DEBUG_SUPPORTED == "true") & (s_axi_dmem_araddr >= DM_REGS_BASEADDR) & (s_axi_dmem_araddr < (DM_REGS_BASEADDR + DM_REGS_ADDR_RANGE)));
	
	assign imem_rd_access_req_from_ibus = s_icb_cmd_inst_valid;
	assign imem_rd_access_req_from_dbus = (~dbus_rd_chn_buf_full_flag) & s_axi_dmem_arvalid & dbus_rd_chn_fall_into_inst_region;
	assign imem_rd_access_instant_arb_res = 
		(imem_rd_access_req_from_ibus & imem_rd_access_req_from_dbus) ? 
			imem_rd_access_grant_to_ibus_if_conflict:
			imem_rd_access_req_from_ibus;
	assign imem_rd_access_grant_to_ibus = 
		imem_rd_access_arb_locked_flag ? 
			imem_rd_access_locked_arb_res:
			imem_rd_access_instant_arb_res;
	
	// 内部数据总线读数据缓存写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dbus_rd_chn_buf_wptr <= 2'b00;
		else if(s_axi_dmem_arvalid & s_axi_dmem_arready)
			dbus_rd_chn_buf_wptr <= # SIM_DELAY dbus_rd_chn_buf_wptr + 1'b1;
	end
	// 内部数据总线读数据缓存读指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dbus_rd_chn_buf_rptr <= 2'b00;
		else if(s_axi_dmem_rvalid & s_axi_dmem_rready)
			dbus_rd_chn_buf_rptr <= # SIM_DELAY dbus_rd_chn_buf_rptr + 1'b1;
	end
	// 内部数据总线读数据缓存有效条目数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dbus_rd_chn_buf_vld_entry_n <= 3'd0;
		else if(
			(s_axi_dmem_arvalid & s_axi_dmem_arready) ^ 
			(s_axi_dmem_rvalid & s_axi_dmem_rready)
		)
			dbus_rd_chn_buf_vld_entry_n <= # SIM_DELAY 
				(s_axi_dmem_rvalid & s_axi_dmem_rready) ? 
					(dbus_rd_chn_buf_vld_entry_n - 1):
					(dbus_rd_chn_buf_vld_entry_n + 1);
	end
	// 内部数据总线读数据缓存满标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dbus_rd_chn_buf_full_flag <= 1'b0;
		else if(
			(s_axi_dmem_arvalid & s_axi_dmem_arready) ^ 
			(s_axi_dmem_rvalid & s_axi_dmem_rready)
		)
			dbus_rd_chn_buf_full_flag <= # SIM_DELAY 
				(~(s_axi_dmem_rvalid & s_axi_dmem_rready)) & (dbus_rd_chn_buf_vld_entry_n == 3);
	end
	
	// 外部指令总线访问仲裁锁定(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			imem_rd_access_arb_locked_flag <= 1'b0;
		else
			imem_rd_access_arb_locked_flag <= # SIM_DELAY 
				imem_rd_access_arb_locked_flag ? 
					(~(
						imem_rd_access_locked_arb_res ? 
							(s_icb_cmd_inst_valid & s_icb_cmd_inst_ready):
							(s_axi_dmem_arvalid & s_axi_dmem_arready)
					)):
					(
						(imem_rd_access_req_from_ibus | imem_rd_access_req_from_dbus) & 
						(~(
							imem_rd_access_instant_arb_res ? 
								(s_icb_cmd_inst_valid & s_icb_cmd_inst_ready):
								(s_axi_dmem_arvalid & s_axi_dmem_arready)
						))
					);
	end
	// 锁定的外部指令总线访问仲裁结果(是否许可给内部指令总线)
	always @(posedge aclk)
	begin
		if(
			(~imem_rd_access_arb_locked_flag) & 
			(imem_rd_access_req_from_ibus | imem_rd_access_req_from_dbus)
		)
			imem_rd_access_locked_arb_res <= # SIM_DELAY 
				imem_rd_access_instant_arb_res;
	end
	// 冲突时许可给内部指令总线
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			imem_rd_access_grant_to_ibus_if_conflict <= 1'b1;
		else if(
			(~imem_rd_access_arb_locked_flag) & 
			(imem_rd_access_req_from_ibus & imem_rd_access_req_from_dbus)
		)
			imem_rd_access_grant_to_ibus_if_conflict <= # SIM_DELAY 
				~imem_rd_access_grant_to_ibus_if_conflict;
	end
	
	// 内部数据总线读数据缓存内容(读数据, 读响应, 条目已填充标志)
	genvar dbus_rd_chn_buf_entry_i;
	generate
		for(dbus_rd_chn_buf_entry_i = 0;dbus_rd_chn_buf_entry_i < 4;dbus_rd_chn_buf_entry_i = dbus_rd_chn_buf_entry_i + 1)
		begin:dbus_rd_chn_buf_blk
			always @(posedge aclk)
			begin
				if(
					dmem_rd_access_msg_fifo_empty_n & 
					(dmem_rd_access_msg_fifo_dout_rdata_buf_id == dbus_rd_chn_buf_entry_i) & 
					dmem_rd_access_msg_fifo_ren
				)
				begin
					dbus_rd_chn_buf_rdata[dbus_rd_chn_buf_entry_i] <= # SIM_DELAY m_axi_dmem_rdata;
					dbus_rd_chn_buf_rresp[dbus_rd_chn_buf_entry_i] <= # SIM_DELAY m_axi_dmem_rresp;
				end
				else if(
					imem_rd_access_msg_fifo_empty_n & (~imem_rd_access_msg_fifo_dout_initiated_by_ibus) & 
					(imem_rd_access_msg_fifo_dout_rdata_buf_id == dbus_rd_chn_buf_entry_i) & 
					imem_rd_access_msg_fifo_ren
				)
				begin
					dbus_rd_chn_buf_rdata[dbus_rd_chn_buf_entry_i] <= # SIM_DELAY m_axi_imem_rdata;
					dbus_rd_chn_buf_rresp[dbus_rd_chn_buf_entry_i] <= # SIM_DELAY m_axi_imem_rresp;
				end
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					dbus_rd_chn_buf_filled_flag[dbus_rd_chn_buf_entry_i] <= 1'b0;
				else if(
					(
						imem_rd_access_msg_fifo_empty_n & (~imem_rd_access_msg_fifo_dout_initiated_by_ibus) & 
						(imem_rd_access_msg_fifo_dout_rdata_buf_id == dbus_rd_chn_buf_entry_i) & 
						imem_rd_access_msg_fifo_ren
					) | 
					(
						dmem_rd_access_msg_fifo_empty_n & 
						(dmem_rd_access_msg_fifo_dout_rdata_buf_id == dbus_rd_chn_buf_entry_i) & 
						dmem_rd_access_msg_fifo_ren
					) | 
					(
						dbus_rd_chn_buf_filled_flag[dbus_rd_chn_buf_entry_i] & 
						(dbus_rd_chn_buf_rptr == dbus_rd_chn_buf_entry_i) & 
						s_axi_dmem_rready
					)
				)
					dbus_rd_chn_buf_filled_flag[dbus_rd_chn_buf_entry_i] <= # SIM_DELAY 
						(~dbus_rd_chn_buf_filled_flag[dbus_rd_chn_buf_entry_i]) & 
						(~(
							(EN_LOW_LATENCY_DMEM_RD == "true") & 
							dmem_rd_access_msg_fifo_empty_n & 
							(dmem_rd_access_msg_fifo_dout_rdata_buf_id == dbus_rd_chn_buf_rptr) & 
							dmem_rd_access_msg_fifo_ren & 
							s_axi_dmem_rready
						));
			end
		end
	endgenerate
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(4),
		.fifo_data_width(6),
		.almost_full_th(1),
		.almost_empty_th(1),
		.simulation_delay(SIM_DELAY)
	)imem_rd_access_msg_fifo_u(
		.clk(aclk),
		.rst_n(aresetn),
		
		.fifo_wen(imem_rd_access_msg_fifo_wen),
		.fifo_din({
			imem_rd_access_msg_fifo_din_initiated_by_ibus,
			imem_rd_access_msg_fifo_din_rdata_buf_id,
			imem_rd_access_msg_fifo_din_word_sel
		}),
		.fifo_full(),
		.fifo_full_n(imem_rd_access_msg_fifo_full_n),
		.fifo_almost_full(),
		.fifo_almost_full_n(),
		
		.fifo_ren(imem_rd_access_msg_fifo_ren),
		.fifo_dout({
			imem_rd_access_msg_fifo_dout_initiated_by_ibus,
			imem_rd_access_msg_fifo_dout_rdata_buf_id,
			imem_rd_access_msg_fifo_dout_word_sel
		}),
		.fifo_empty(),
		.fifo_empty_n(imem_rd_access_msg_fifo_empty_n),
		.fifo_almost_empty(),
		.fifo_almost_empty_n(),
		
		.data_cnt()
	);
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(4),
		.fifo_data_width(2),
		.almost_full_th(1),
		.almost_empty_th(1),
		.simulation_delay(SIM_DELAY)
	)dmem_rd_access_msg_fifo_u(
		.clk(aclk),
		.rst_n(aresetn),
		
		.fifo_wen(dmem_rd_access_msg_fifo_wen),
		.fifo_din({
			dmem_rd_access_msg_fifo_din_rdata_buf_id
		}),
		.fifo_full(),
		.fifo_full_n(dmem_rd_access_msg_fifo_full_n),
		.fifo_almost_full(),
		.fifo_almost_full_n(),
		
		.fifo_ren(dmem_rd_access_msg_fifo_ren),
		.fifo_dout({
			dmem_rd_access_msg_fifo_dout_rdata_buf_id
		}),
		.fifo_empty(),
		.fifo_empty_n(dmem_rd_access_msg_fifo_empty_n),
		.fifo_almost_empty(),
		.fifo_almost_empty_n(),
		
		.data_cnt()
	);
	
	/** 写通道互联 **/
	// [数据总线写事务信息表]
	reg[3:0] dbus_wr_trans_table_to_access_inst_region; // 访问指令区
	reg[3:0] dbus_wr_trans_table_vld_flag; // 有效标志
	reg[3:0] dbus_wr_trans_table_wdata_sent_flag; // 写数据已传输标志
	reg[2:0] dbus_wr_trans_table_vld_entry_n; // 有效条目数
	reg dbus_wr_trans_table_full_flag; // 满标志
	reg dbus_wr_trans_table_empty_flag; // 空标志
	// [数据总线写事务进程]
	reg[1:0] dbus_wr_trans_addr_setup_ptr; // 正在进行地址传输的项指针
	reg[1:0] dbus_wr_trans_sending_wdata_ptr; // 正在进行数据传输的项指针
	reg[1:0] dbus_wr_trans_waiting_resp_ptr; // 等待响应的项指针
	// [地址译码]
	wire dbus_wr_chn_fall_into_inst_region; // 地址落在指令区
	
	// CPU核内数据存储器AXI从机写通道
	// [AW通道]
	assign s_axi_dmem_awready = 
		(~dbus_wr_trans_table_full_flag) & 
		(
			dbus_wr_chn_fall_into_inst_region ? 
				m_axi_imem_awready:
				m_axi_dmem_awready
		);
	// [B通道]
	assign s_axi_dmem_bresp = 
		dbus_wr_trans_table_to_access_inst_region[dbus_wr_trans_waiting_resp_ptr] ? 
			m_axi_imem_bresp:
			m_axi_dmem_bresp;
	assign s_axi_dmem_bvalid = 
		(~dbus_wr_trans_table_empty_flag) & 
		(
			dbus_wr_trans_table_to_access_inst_region[dbus_wr_trans_waiting_resp_ptr] ? 
				m_axi_imem_bvalid:
				m_axi_dmem_bvalid
		);
	// [W通道]
	assign s_axi_dmem_wready = 
		dbus_wr_trans_table_vld_flag[dbus_wr_trans_sending_wdata_ptr] ? 
			(
				(~dbus_wr_trans_table_wdata_sent_flag[dbus_wr_trans_sending_wdata_ptr]) & 
				(
					dbus_wr_trans_table_to_access_inst_region[dbus_wr_trans_sending_wdata_ptr] ? 
						m_axi_imem_wready:
						m_axi_dmem_wready
				)
			):
			(
				s_axi_dmem_awvalid & (dbus_wr_trans_sending_wdata_ptr == dbus_wr_trans_addr_setup_ptr) & 
				(
					dbus_wr_chn_fall_into_inst_region ? 
						m_axi_imem_wready:
						m_axi_dmem_wready
				)
			);
	
	// 外部(指令总线)存储器AXI主机写通道
	// [AW通道]
	assign m_axi_imem_awaddr = s_axi_dmem_awaddr;
	assign m_axi_imem_awburst = s_axi_dmem_awburst;
	assign m_axi_imem_awlen = s_axi_dmem_awlen;
	assign m_axi_imem_awsize = s_axi_dmem_awsize;
	assign m_axi_imem_awvalid = 
		(~dbus_wr_trans_table_full_flag) & s_axi_dmem_awvalid & dbus_wr_chn_fall_into_inst_region;
	// [B通道]
	assign m_axi_imem_bready = 
		(~dbus_wr_trans_table_empty_flag) & 
		dbus_wr_trans_table_to_access_inst_region[dbus_wr_trans_waiting_resp_ptr] & 
		s_axi_dmem_bready;
	// [W通道]
	assign m_axi_imem_wdata = s_axi_dmem_wdata;
	assign m_axi_imem_wstrb = s_axi_dmem_wstrb;
	assign m_axi_imem_wlast = s_axi_dmem_wlast;
	assign m_axi_imem_wvalid = 
		s_axi_dmem_wvalid & 
		(
			dbus_wr_trans_table_vld_flag[dbus_wr_trans_sending_wdata_ptr] ? 
				(
					(~dbus_wr_trans_table_wdata_sent_flag[dbus_wr_trans_sending_wdata_ptr]) & 
					dbus_wr_trans_table_to_access_inst_region[dbus_wr_trans_sending_wdata_ptr]
				):
				(
					s_axi_dmem_awvalid & (dbus_wr_trans_sending_wdata_ptr == dbus_wr_trans_addr_setup_ptr) & 
					dbus_wr_chn_fall_into_inst_region
				)
		);
	
	// 外部(数据总线)存储器AXI主机写通道
	// [AW通道]
	assign m_axi_dmem_awaddr = s_axi_dmem_awaddr;
	assign m_axi_dmem_awburst = s_axi_dmem_awburst;
	assign m_axi_dmem_awlen = s_axi_dmem_awlen;
	assign m_axi_dmem_awsize = s_axi_dmem_awsize;
	assign m_axi_dmem_awvalid = 
		(~dbus_wr_trans_table_full_flag) & s_axi_dmem_awvalid & (~dbus_wr_chn_fall_into_inst_region);
	// [B通道]
	assign m_axi_dmem_bready = 
		(~dbus_wr_trans_table_empty_flag) & 
		(~dbus_wr_trans_table_to_access_inst_region[dbus_wr_trans_waiting_resp_ptr]) & 
		s_axi_dmem_bready;
	// [W通道]
	assign m_axi_dmem_wdata = s_axi_dmem_wdata;
	assign m_axi_dmem_wstrb = s_axi_dmem_wstrb;
	assign m_axi_dmem_wlast = s_axi_dmem_wlast;
	assign m_axi_dmem_wvalid = 
		s_axi_dmem_wvalid & 
		(
			dbus_wr_trans_table_vld_flag[dbus_wr_trans_sending_wdata_ptr] ? 
				(
					(~dbus_wr_trans_table_wdata_sent_flag[dbus_wr_trans_sending_wdata_ptr]) & 
					(~dbus_wr_trans_table_to_access_inst_region[dbus_wr_trans_sending_wdata_ptr])
				):
				(
					s_axi_dmem_awvalid & (dbus_wr_trans_sending_wdata_ptr == dbus_wr_trans_addr_setup_ptr) & 
					(~dbus_wr_chn_fall_into_inst_region)
				)
		);
	
	assign dbus_wr_chn_fall_into_inst_region = 
		((s_axi_dmem_awaddr >= IMEM_BASEADDR) & (s_axi_dmem_awaddr < (IMEM_BASEADDR + IMEM_ADDR_RANGE))) | 
		((DEBUG_SUPPORTED == "true") & (s_axi_dmem_awaddr >= DM_REGS_BASEADDR) & (s_axi_dmem_awaddr < (DM_REGS_BASEADDR + DM_REGS_ADDR_RANGE)));
	
	// 数据总线写事务信息表有效条目数
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dbus_wr_trans_table_vld_entry_n <= 0;
		else if(
			(s_axi_dmem_awvalid & s_axi_dmem_awready) ^ 
			(s_axi_dmem_bvalid & s_axi_dmem_bready)
		)
			dbus_wr_trans_table_vld_entry_n <= # SIM_DELAY 
				(s_axi_dmem_bvalid & s_axi_dmem_bready) ? 
					(dbus_wr_trans_table_vld_entry_n - 1):
					(dbus_wr_trans_table_vld_entry_n + 1);
	end
	// 数据总线写事务信息表满标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dbus_wr_trans_table_full_flag <= 1'b0;
		else if(
			(s_axi_dmem_awvalid & s_axi_dmem_awready) ^ 
			(s_axi_dmem_bvalid & s_axi_dmem_bready)
		)
			dbus_wr_trans_table_full_flag <= # SIM_DELAY 
				(~(s_axi_dmem_bvalid & s_axi_dmem_bready)) & (dbus_wr_trans_table_vld_entry_n == 3);
	end
	// 数据总线写事务信息表空标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dbus_wr_trans_table_empty_flag <= 1'b1;
		else if(
			(s_axi_dmem_awvalid & s_axi_dmem_awready) ^ 
			(s_axi_dmem_bvalid & s_axi_dmem_bready)
		)
			dbus_wr_trans_table_empty_flag <= # SIM_DELAY 
				(s_axi_dmem_bvalid & s_axi_dmem_bready) & (dbus_wr_trans_table_vld_entry_n == 1);
	end
	
	// 正在进行地址传输的项指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dbus_wr_trans_addr_setup_ptr <= 2'b00;
		else if(s_axi_dmem_awvalid & s_axi_dmem_awready)
			dbus_wr_trans_addr_setup_ptr <= # SIM_DELAY 
				dbus_wr_trans_addr_setup_ptr + 1'b1;
	end
	// 正在进行数据传输的项指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dbus_wr_trans_sending_wdata_ptr <= 2'b00;
		else if(s_axi_dmem_wvalid & s_axi_dmem_wready)
			dbus_wr_trans_sending_wdata_ptr <= # SIM_DELAY 
				dbus_wr_trans_sending_wdata_ptr + 1'b1;
	end
	// 等待响应的项指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			dbus_wr_trans_waiting_resp_ptr <= 2'b00;
		else if(s_axi_dmem_bvalid & s_axi_dmem_bready)
			dbus_wr_trans_waiting_resp_ptr <= # SIM_DELAY 
				dbus_wr_trans_waiting_resp_ptr + 1'b1;
	end
	
	// 数据总线写事务信息表的存储内容(访问指令区)
	// 数据总线写事务信息表的标志(有效标志, 写数据已传输标志)
	genvar dbus_wr_trans_table_entry_i;
	generate
		for(dbus_wr_trans_table_entry_i = 0;dbus_wr_trans_table_entry_i < 4;
			dbus_wr_trans_table_entry_i = dbus_wr_trans_table_entry_i + 1)
		begin:dbus_wr_trans_table_blk
			always @(posedge aclk)
			begin
				if(
					s_axi_dmem_awvalid & s_axi_dmem_awready & 
					(dbus_wr_trans_addr_setup_ptr == dbus_wr_trans_table_entry_i)
				)
					dbus_wr_trans_table_to_access_inst_region[dbus_wr_trans_table_entry_i] <= # SIM_DELAY 
						dbus_wr_chn_fall_into_inst_region;
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					dbus_wr_trans_table_vld_flag[dbus_wr_trans_table_entry_i] <= 1'b0;
				else if(
					(
						s_axi_dmem_awvalid & s_axi_dmem_awready & 
						(dbus_wr_trans_addr_setup_ptr == dbus_wr_trans_table_entry_i)
					) | 
					(
						s_axi_dmem_bvalid & s_axi_dmem_bready & 
						(dbus_wr_trans_waiting_resp_ptr == dbus_wr_trans_table_entry_i)
					)
				)
					dbus_wr_trans_table_vld_flag[dbus_wr_trans_table_entry_i] <= # SIM_DELAY 
						~(
							s_axi_dmem_bvalid & s_axi_dmem_bready & 
							(dbus_wr_trans_waiting_resp_ptr == dbus_wr_trans_table_entry_i)
						);
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					dbus_wr_trans_table_wdata_sent_flag[dbus_wr_trans_table_entry_i] <= 1'b0;
				else if(
					(
						s_axi_dmem_wvalid & s_axi_dmem_wready & 
						(dbus_wr_trans_sending_wdata_ptr == dbus_wr_trans_table_entry_i)
					) | 
					(
						s_axi_dmem_bvalid & s_axi_dmem_bready & 
						(dbus_wr_trans_waiting_resp_ptr == dbus_wr_trans_table_entry_i)
					)
				)
					dbus_wr_trans_table_wdata_sent_flag[dbus_wr_trans_table_entry_i] <= # SIM_DELAY 
						~(
							s_axi_dmem_bvalid & s_axi_dmem_bready & 
							(dbus_wr_trans_waiting_resp_ptr == dbus_wr_trans_table_entry_i)
						);
			end
		end
	endgenerate
	
endmodule
