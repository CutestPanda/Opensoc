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
本模块: 加载/存储单元

描述:
接受访存请求, 根据请求类型进行不同的处理 -> 
	(1)对于写存储器请求, 先放入写存储器(请求)缓存区(Write Memory Buffer), 等待写存储器许可后, 将请求合并到总线事务缓存区,
		在存储器AXI主机发起总线事务
	(2)对于读存储器请求, 需要在接受请求时检查写存储器缓存, 得到检查结果后再在存储器AXI主机发起总线事务,
		访存读数据将合并上检查写存储器缓存时得到的修改数据和字节掩码
	(3)对于外设访问请求, 等待外设访问许可后, 在外设AXI主机发起总线事务

独立的存储器和外设总线

存储器访问支持滞外传输(Outstanding), 而外设访问不支持滞外传输

注意：
无

协议:
AXI-Lite MASTER

作者: 陈家耀
日期: 2026/02/12
********************************************************************/


module panda_risc_v_lsu #(
	parameter integer INST_ID_WIDTH = 4, // 指令编号的位宽
	parameter integer AXI_MEM_DATA_WIDTH = 64, // 存储器AXI主机的数据位宽(32 | 64 | 128 | 256)
	parameter integer MEM_ACCESS_TIMEOUT_TH = 0, // 存储器访问超时周期数(0 -> 不设超时 | 正整数)
	parameter integer PERPH_ACCESS_TIMEOUT_TH = 32, // 外设访问超时周期数(0 -> 不设超时 | 正整数)
	parameter integer LSU_REQ_BUF_ENTRY_N = 8, // LSU请求缓存区条目数(2~16)
	parameter integer RD_MEM_BUF_ENTRY_N = 4, // 读存储器缓存区条目数(2~16)
	parameter integer WR_MEM_BUF_ENTRY_N = 4, // 写存储器缓存区条目数(2~16)
	parameter EN_LOW_LATENCY_PERPH_ACCESS = "false", // 是否启用低时延的外设访问模式
	parameter integer EN_LOW_LATENCY_RD_MEM_ACCESS = 1, // 读存储器访问时延优化等级(0 | 1 | 2)
	parameter EN_PERMISSION_CHECK_ON_SUBMIT_NEW_WR_MEM_REQ = "false", // 是否在提交新的写存储器请求时进行(总线访问)许可检查
    parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 写存储器缓存区控制
	// [写存储器许可]
	input wire wr_mem_permitted_flag, // 许可标志
	input wire[INST_ID_WIDTH-1:0] init_mem_bus_tr_store_inst_tid, // 待发起存储器总线事务的存储指令ID
	// [清空缓存区]
	input wire clr_wr_mem_buf, // 清空指示
	
	// 外设访问控制
	// [外设访问许可]
	input wire perph_access_permitted_flag, // 许可标志
	input wire[INST_ID_WIDTH-1:0] init_perph_bus_tr_ls_inst_tid, // 待发起外设总线事务的访存指令ID
	// [取消后续外设访问]
	input wire cancel_subseq_perph_access, // 取消指示
	
	// 访存请求
	input wire s_req_ls_sel, // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	input wire[2:0] s_req_ls_type, // 访存类型
	input wire[4:0] s_req_rd_id_for_ld, // 用于加载的目标寄存器的索引
	input wire[31:0] s_req_ls_addr, // 访存地址
	input wire[31:0] s_req_ls_din, // 写数据
	input wire[INST_ID_WIDTH-1:0] s_req_lsu_inst_id, // 指令编号
	input wire s_req_ls_mem_access, // 访问存储器区域(标志)
	input wire s_req_valid,
	output wire s_req_ready,
	
	// 访存结果
	output wire m_resp_ls_sel, // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	output wire[4:0] m_resp_rd_id_for_ld, // 用于加载的目标寄存器的索引
	// 说明: 访存正常完成时给出"读数据", 错误时给出"访存地址"
	output wire[31:0] m_resp_dout_ls_addr, // 读数据或访存地址
	output wire[1:0] m_resp_err, // 错误类型
	output wire[INST_ID_WIDTH-1:0] m_resp_lsu_inst_id, // 指令编号
	output wire m_resp_valid,
	input wire m_resp_ready,
    
	// 存储器AXI主机
	// [AR通道]
	output wire[31:0] m_axi_mem_araddr,
	output wire[1:0] m_axi_mem_arburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_mem_arlen, // const -> 8'd0
	output wire[2:0] m_axi_mem_arsize, // const -> clogb2(AXI_MEM_DATA_WIDTH/8)
	output wire m_axi_mem_arvalid,
	input wire m_axi_mem_arready,
	// [R通道]
	input wire[AXI_MEM_DATA_WIDTH-1:0] m_axi_mem_rdata,
	input wire[1:0] m_axi_mem_rresp,
	input wire m_axi_mem_rlast, // ignored
	input wire m_axi_mem_rvalid,
	output wire m_axi_mem_rready, // const -> 1'b1
	// [AW通道]
	output wire[31:0] m_axi_mem_awaddr,
	output wire[1:0] m_axi_mem_awburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_mem_awlen, // const -> 8'd0
	output wire[2:0] m_axi_mem_awsize, // const -> clogb2(AXI_MEM_DATA_WIDTH/8)
	output wire m_axi_mem_awvalid,
	input wire m_axi_mem_awready,
	// [B通道]
	input wire[1:0] m_axi_mem_bresp, // ignored
	input wire m_axi_mem_bvalid,
	output wire m_axi_mem_bready, // const -> 1'b1
	// [W通道]
	output wire[AXI_MEM_DATA_WIDTH-1:0] m_axi_mem_wdata,
	output wire[AXI_MEM_DATA_WIDTH/8-1:0] m_axi_mem_wstrb,
	output wire m_axi_mem_wlast, // const -> 1'b1
	output wire m_axi_mem_wvalid,
	input wire m_axi_mem_wready,
	
	// 外设AXI主机
	// [AR通道]
	output wire[31:0] m_axi_perph_araddr,
	output wire[1:0] m_axi_perph_arburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_perph_arlen, // const -> 8'd0
	output wire[2:0] m_axi_perph_arsize, // const -> 3'b010
	output wire m_axi_perph_arvalid,
	input wire m_axi_perph_arready,
	// [R通道]
	input wire[31:0] m_axi_perph_rdata,
	input wire[1:0] m_axi_perph_rresp,
	input wire m_axi_perph_rlast, // ignored
	input wire m_axi_perph_rvalid,
	output wire m_axi_perph_rready, // const -> 1'b1
	// [AW通道]
	output wire[31:0] m_axi_perph_awaddr,
	output wire[1:0] m_axi_perph_awburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_perph_awlen, // const -> 8'd0
	output wire[2:0] m_axi_perph_awsize, // const -> 3'b010
	output wire m_axi_perph_awvalid,
	input wire m_axi_perph_awready,
	// [B通道]
	input wire[1:0] m_axi_perph_bresp,
	input wire m_axi_perph_bvalid,
	output wire m_axi_perph_bready, // const -> 1'b1
	// [W通道]
	output wire[31:0] m_axi_perph_wdata,
	output wire[3:0] m_axi_perph_wstrb,
	output wire m_axi_perph_wlast, // const -> 1'b1
	output wire m_axi_perph_wvalid,
	input wire m_axi_perph_wready,
	
	// 读存储器结果快速旁路
	output wire on_get_instant_rd_mem_res_s0,
	output wire[INST_ID_WIDTH-1:0] inst_id_of_instant_rd_mem_res_gotten_s0,
	output wire[31:0] data_of_instant_rd_mem_res_gotten_s0,
	output wire on_get_instant_rd_mem_res_s1,
	output wire[INST_ID_WIDTH-1:0] inst_id_of_instant_rd_mem_res_gotten_s1,
	output wire[31:0] data_of_instant_rd_mem_res_gotten_s1,
	
	// LSU状态
	output wire has_buffered_wr_mem_req, // 存在已缓存的写存储器请求(标志)
	output wire has_processing_perph_access_req, // 存在处理中的外设访问请求(标志)
	
	// 数据总线访问超时标志
	output wire rd_mem_timeout, // 读存储器超时(标志)
	output wire wr_mem_timeout, // 写存储器超时(标志)
	output wire perph_access_timeout // 外设访问超时(标志)
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
	// 访存类型
	localparam LS_TYPE_BYTE = 3'b000;
	localparam LS_TYPE_HALF_WORD = 3'b001;
	localparam LS_TYPE_WORD = 3'b010;
	localparam LS_TYPE_BYTE_UNSIGNED = 3'b100;
	localparam LS_TYPE_HALF_WORD_UNSIGNED = 3'b101;
	// 访存应答错误类型
	localparam DBUS_ACCESS_NORMAL = 2'b00; // 正常
	localparam DBUS_ACCESS_LS_UNALIGNED = 2'b01; // 访存地址非对齐
	localparam DBUS_ACCESS_BUS_ERR = 2'b10; // 数据总线访问错误
	localparam DBUS_ACCESS_TIMEOUT = 2'b11; // 响应超时
	// AXI响应类型
	localparam AXI_RESP_OKAY = 2'b00;
	localparam AXI_RESP_EXOKAY = 2'b01;
	localparam AXI_RESP_SLVERR = 2'b10;
	localparam AXI_RESP_DECERR = 2'b11;
	
	/** 写存储器缓存区 **/
	// [提交新的写存储器请求]
	wire on_submit_new_wr_mem_req; // 提交新请求(指示)
	wire is_allowed_to_submit_new_wr_mem_req; // 允许提交新请求(标志)
	reg[WR_MEM_BUF_ENTRY_N-1:0] wr_mem_req_table_entry_wptr; // 条目写指针
	reg wr_mem_req_table_age_wptr; // 年龄写指针
	wire[31:0] aligned_addr_of_new_wr_mem_req; // 新请求的对齐地址
	wire[31:0] wdata_of_new_wr_mem_req; // 新请求的写数据
	wire[3:0] wmask_of_new_wr_mem_req; // 新请求的写字节掩码
	wire[INST_ID_WIDTH-1:0] inst_id_of_new_wr_mem_req; // 新请求的指令ID
	reg is_vld_entry_in_wr_mem_req_table; // 写存储器请求信息表里存在有效条目(标志)
	// [写存储器请求的总线访问许可]
	wire[WR_MEM_BUF_ENTRY_N-1:0] on_wr_mem_req_permitted_to_bus; // 请求被许可发往总线(指示)
	wire on_new_wr_mem_req_permitted_directly; // 新的写存储器请求被直接许可(指示)
	reg[WR_MEM_BUF_ENTRY_N-1:0] permitting_wr_mem_req_entry_ptr; // 待获得许可的写存储器请求的条目指针
	reg permitting_wr_mem_req_age_ptr; // 待获得许可的写存储器请求的年龄指针
	// [创建新的写存储器总线事务记录]
	wire on_create_new_wr_mem_trans_record; // 创建新记录(指示)
	wire[WR_MEM_BUF_ENTRY_N-1:0] wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record; // 正在创建的记录在请求信息表所依据条目的编号(独热码)
	wire[3:0] wr_mem_req_table_sel_entry_bin_id_of_creating_new_wr_mem_trans_record; // 正在创建的记录在请求信息表所依据条目的编号(二进制码)
	wire[31:0] aligned_addr_of_creating_new_wr_mem_trans_record; // 正在创建的记录的对齐地址
	wire[31:0] wdata_of_creating_new_wr_mem_trans_record; // 正在创建的记录的写数据
	wire[3:0] wmask_of_creating_new_wr_mem_trans_record; // 正在创建的记录的写字节掩码
	wire[WR_MEM_BUF_ENTRY_N-1:0] new_wr_mem_trans_mergeable_onehot; // 可合并新的写存储器总线事务到记录表(项独热码)
	wire[WR_MEM_BUF_ENTRY_N-1:0] creating_new_wr_mem_trans_entry_sel; // 正在创建的记录的条目选择(独热码)
	reg[WR_MEM_BUF_ENTRY_N-1:0] wr_mem_trans_table_entry_wptr; // 条目写指针
	// [启动写存储器总线事务]
	reg[clogb2(WR_MEM_BUF_ENTRY_N):0] wr_mem_trans_to_be_initiated_cnt; // 待启动的写存储器总线事务数(计数器)
	reg has_wr_mem_trans_to_be_initiated; // 存在待启动的写存储器总线事务(标志)
	reg[3:0] wr_mem_trans_detained_cnt; // 写存储器总线事务滞留周期数(计数器)
	// [写存储器总线事务进程]
	reg on_initiate_wr_mem_trans; // 启动写存储器事务(指示)
	wire on_complete_wr_mem_trans; // 完成写存储器事务(指示)
	wire[31:0] aligned_addr_of_completed_wr_mem_trans; // 所完成事务的对齐地址
	wire[WR_MEM_BUF_ENTRY_N-1:0] record_onehot_id_of_completed_wr_mem_trans; // 所完成事务的记录编号(独热码)
	reg[clogb2(WR_MEM_BUF_ENTRY_N-1):0] wr_mem_trans_addr_setup_ptr; // 待进行地址传输的事务在写存储器总线事务记录表里的指针
	reg[clogb2(WR_MEM_BUF_ENTRY_N-1):0] wr_mem_trans_data_transfer_ptr; // 待进行数据传输的事务在写存储器总线事务记录表里的指针
	reg[WR_MEM_BUF_ENTRY_N-1:0] completed_wr_mem_trans_onehot_ptr; // 所完成事务在写存储器总线事务记录表里的指针(独热码)
	reg[clogb2(WR_MEM_BUF_ENTRY_N-1):0] completed_wr_mem_trans_bin_ptr; // 所完成事务在写存储器总线事务记录表里的指针(二进制码)
	// [写存储器超时限制]
	reg[clogb2(MEM_ACCESS_TIMEOUT_TH):0] wr_mem_timeout_cnt; // 超时计数器
	reg wr_mem_timeout_flag; // 超时标志
	// [写存储器请求信息表]
	reg[31:0] wr_mem_req_table_aligned_addr[0:WR_MEM_BUF_ENTRY_N-1]; // 对齐地址
	reg[31:0] wr_mem_req_table_wdata[0:WR_MEM_BUF_ENTRY_N-1]; // 写数据
	reg[3:0] wr_mem_req_table_wmask[0:WR_MEM_BUF_ENTRY_N-1]; // 写字节掩码
	reg[INST_ID_WIDTH-1:0] wr_mem_req_table_inst_id[0:WR_MEM_BUF_ENTRY_N-1]; // 指令ID
	reg[WR_MEM_BUF_ENTRY_N-1:0] wr_mem_req_table_age_tbit; // 年龄翻转位
	reg[WR_MEM_BUF_ENTRY_N-1:0] wr_mem_req_table_bonding_tr_record_onehot_id[0:WR_MEM_BUF_ENTRY_N-1]; // 绑定的总线事务记录编号(独热码)
	reg[WR_MEM_BUF_ENTRY_N-1:0] wr_mem_req_table_vld_flag; // 条目有效标志
	reg[WR_MEM_BUF_ENTRY_N-1:0] wr_mem_req_table_permitted_flag; // 条目许可标志
	reg[WR_MEM_BUF_ENTRY_N-1:0] wr_mem_req_table_trans_flag; // 条目传输中标志
	wire[WR_MEM_BUF_ENTRY_N-1:0] wr_mem_req_table_vld_flag_nxt; // (最新的)条目有效标志
	// [写存储器总线事务记录表]
	reg[31:0] wr_mem_trans_table_aligned_addr[0:WR_MEM_BUF_ENTRY_N-1]; // 对齐地址
	reg[AXI_MEM_DATA_WIDTH-1:0] wr_mem_trans_table_wdata[0:WR_MEM_BUF_ENTRY_N-1]; // 写数据
	reg[AXI_MEM_DATA_WIDTH/8-1:0] wr_mem_trans_table_wmask[0:WR_MEM_BUF_ENTRY_N-1]; // 写字节掩码
	reg[WR_MEM_BUF_ENTRY_N-1:0] wr_mem_trans_table_vld_flag; // 有效标志
	reg[WR_MEM_BUF_ENTRY_N-1:0] wr_mem_trans_table_trans_flag; // 传输中标志
	reg[WR_MEM_BUF_ENTRY_N-1:0] wr_mem_trans_table_addr_setup_flag; // 地址通道已传输标志
	reg[WR_MEM_BUF_ENTRY_N-1:0] wr_mem_trans_table_data_sent_flag; // 数据通道已传输标志
	
	// [AW通道]
	assign m_axi_mem_awaddr = 
		wr_mem_trans_table_aligned_addr[wr_mem_trans_addr_setup_ptr] & (~(AXI_MEM_DATA_WIDTH/8 - 1));
	assign m_axi_mem_awburst = 2'b01;
	assign m_axi_mem_awlen = 8'd0;
	assign m_axi_mem_awsize = clogb2(AXI_MEM_DATA_WIDTH/8);
	assign m_axi_mem_awvalid = 
		|((wr_mem_trans_table_trans_flag & (~wr_mem_trans_table_addr_setup_flag)) & (1 << wr_mem_trans_addr_setup_ptr));
	// [B通道]
	assign m_axi_mem_bready = 1'b1;
	// [W通道]
	assign m_axi_mem_wdata = wr_mem_trans_table_wdata[wr_mem_trans_data_transfer_ptr];
	assign m_axi_mem_wstrb = wr_mem_trans_table_wmask[wr_mem_trans_data_transfer_ptr];
	assign m_axi_mem_wlast = 1'b1;
	assign m_axi_mem_wvalid = 
		|((wr_mem_trans_table_trans_flag & (~wr_mem_trans_table_data_sent_flag)) & (1 << wr_mem_trans_data_transfer_ptr));
	
	assign has_buffered_wr_mem_req = is_vld_entry_in_wr_mem_req_table;
	
	assign wr_mem_timeout = wr_mem_timeout_flag;
	
	assign is_allowed_to_submit_new_wr_mem_req = 
		(~clr_wr_mem_buf) & (~(|(wr_mem_req_table_entry_wptr & wr_mem_req_table_vld_flag)));
	
	assign on_new_wr_mem_req_permitted_directly = 
		(EN_PERMISSION_CHECK_ON_SUBMIT_NEW_WR_MEM_REQ == "true") & 
		on_submit_new_wr_mem_req & is_allowed_to_submit_new_wr_mem_req & 
		wr_mem_permitted_flag & (init_mem_bus_tr_store_inst_tid == inst_id_of_new_wr_mem_req);
	
	assign on_create_new_wr_mem_trans_record = |on_wr_mem_req_permitted_to_bus;
	
	// 将独热码转为二进制码
	assign wr_mem_req_table_sel_entry_bin_id_of_creating_new_wr_mem_trans_record[0] = 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 1))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 3))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 5))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 7))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 9))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 11))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 13))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 15)));
	assign wr_mem_req_table_sel_entry_bin_id_of_creating_new_wr_mem_trans_record[1] = 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 2))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 3))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 6))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 7))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 10))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 11))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 14))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 15)));
	assign wr_mem_req_table_sel_entry_bin_id_of_creating_new_wr_mem_trans_record[2] = 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 4))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 5))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 6))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 7))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 12))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 13))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 14))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 15)));
	assign wr_mem_req_table_sel_entry_bin_id_of_creating_new_wr_mem_trans_record[3] = 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 8))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 9))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 10))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 11))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 12))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 13))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 14))) | 
		(|(wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record & (1 << 15)));
	
	assign aligned_addr_of_creating_new_wr_mem_trans_record = 
		on_new_wr_mem_req_permitted_directly ? 
			aligned_addr_of_new_wr_mem_req:
			wr_mem_req_table_aligned_addr[wr_mem_req_table_sel_entry_bin_id_of_creating_new_wr_mem_trans_record];
	assign wdata_of_creating_new_wr_mem_trans_record = 
		on_new_wr_mem_req_permitted_directly ? 
			wdata_of_new_wr_mem_req:
			wr_mem_req_table_wdata[wr_mem_req_table_sel_entry_bin_id_of_creating_new_wr_mem_trans_record];
	assign wmask_of_creating_new_wr_mem_trans_record = 
		on_new_wr_mem_req_permitted_directly ? 
			wmask_of_new_wr_mem_req:
			wr_mem_req_table_wmask[wr_mem_req_table_sel_entry_bin_id_of_creating_new_wr_mem_trans_record];
	
	assign on_complete_wr_mem_trans = m_axi_mem_bvalid & m_axi_mem_bready;
	assign aligned_addr_of_completed_wr_mem_trans = wr_mem_trans_table_aligned_addr[completed_wr_mem_trans_bin_ptr];
	assign record_onehot_id_of_completed_wr_mem_trans = completed_wr_mem_trans_onehot_ptr;
	
	// 写存储器请求信息表的条目写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wr_mem_req_table_entry_wptr <= 1;
		else if(clr_wr_mem_buf | (on_submit_new_wr_mem_req & is_allowed_to_submit_new_wr_mem_req))
			wr_mem_req_table_entry_wptr <= # SIM_DELAY 
				clr_wr_mem_buf ? 
					(
						(on_create_new_wr_mem_trans_record & (~on_new_wr_mem_req_permitted_directly)) ? 
							((permitting_wr_mem_req_entry_ptr << 1) | (permitting_wr_mem_req_entry_ptr >> (WR_MEM_BUF_ENTRY_N-1))):
							permitting_wr_mem_req_entry_ptr
					):
					((wr_mem_req_table_entry_wptr << 1) | (wr_mem_req_table_entry_wptr >> (WR_MEM_BUF_ENTRY_N-1)));
	end
	// 写存储器请求信息表的条目年龄写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wr_mem_req_table_age_wptr <= 1'b0;
		else if(
			clr_wr_mem_buf | 
			(on_submit_new_wr_mem_req & is_allowed_to_submit_new_wr_mem_req & wr_mem_req_table_entry_wptr[WR_MEM_BUF_ENTRY_N-1])
		)
			wr_mem_req_table_age_wptr <= # SIM_DELAY 
				clr_wr_mem_buf ? 
					(
						(
							on_create_new_wr_mem_trans_record & (~on_new_wr_mem_req_permitted_directly) & 
							permitting_wr_mem_req_entry_ptr[WR_MEM_BUF_ENTRY_N-1]
						) ^ permitting_wr_mem_req_age_ptr
					):
					(~wr_mem_req_table_age_wptr);
	end
	
	// 写存储器请求信息表里存在有效条目(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			is_vld_entry_in_wr_mem_req_table <= 1'b0;
		else if(
			(on_submit_new_wr_mem_req & is_allowed_to_submit_new_wr_mem_req) | 
			on_complete_wr_mem_trans | 
			clr_wr_mem_buf
		)
			is_vld_entry_in_wr_mem_req_table <= # SIM_DELAY 
				|wr_mem_req_table_vld_flag_nxt;
	end
	
	// 说明: 对写存储器请求的许可是逐条目进行的
	// 待获得许可的写存储器请求的条目指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			permitting_wr_mem_req_entry_ptr <= 1;
		else if(on_create_new_wr_mem_trans_record)
			permitting_wr_mem_req_entry_ptr <= # SIM_DELAY 
				(permitting_wr_mem_req_entry_ptr << 1) | (permitting_wr_mem_req_entry_ptr >> (WR_MEM_BUF_ENTRY_N-1));
	end
	// 待获得许可的写存储器请求的年龄指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			permitting_wr_mem_req_age_ptr <= 1'b0;
		else if(on_create_new_wr_mem_trans_record & permitting_wr_mem_req_entry_ptr[WR_MEM_BUF_ENTRY_N-1])
			permitting_wr_mem_req_age_ptr <= # SIM_DELAY ~permitting_wr_mem_req_age_ptr;
	end
	
	// 写存储器总线事务记录表的条目写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wr_mem_trans_table_entry_wptr <= 1;
		else if(
			on_create_new_wr_mem_trans_record & 
			(on_initiate_wr_mem_trans | (~(|new_wr_mem_trans_mergeable_onehot)))
		)
			wr_mem_trans_table_entry_wptr <= # SIM_DELAY 
				(wr_mem_trans_table_entry_wptr << 1) | (wr_mem_trans_table_entry_wptr >> (WR_MEM_BUF_ENTRY_N-1));
	end
	
	// 待启动的写存储器总线事务数(计数器), 存在待启动的写存储器总线事务(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
		begin
			wr_mem_trans_to_be_initiated_cnt <= 0;
			has_wr_mem_trans_to_be_initiated <= 1'b0;
		end
		else if(
			on_initiate_wr_mem_trans | 
			(on_create_new_wr_mem_trans_record & (~(|new_wr_mem_trans_mergeable_onehot)))
		)
		begin
			wr_mem_trans_to_be_initiated_cnt <= # SIM_DELAY 
				on_initiate_wr_mem_trans ? 
					(on_create_new_wr_mem_trans_record ? 1:0):
					(wr_mem_trans_to_be_initiated_cnt + 1);
			has_wr_mem_trans_to_be_initiated <= # SIM_DELAY 
				(~on_initiate_wr_mem_trans) | on_create_new_wr_mem_trans_record;
		end
	end
	// 写存储器总线事务滞留周期数(计数器)
	// 说明: 本计数器记录了从"存在待启动的写存储器总线事务"到"启动写存储器事务"的周期数, 其最大值限制为15
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wr_mem_trans_detained_cnt <= 4'd0;
		else if(
			on_initiate_wr_mem_trans | 
			(has_wr_mem_trans_to_be_initiated & (~(&wr_mem_trans_detained_cnt)))
		)
			wr_mem_trans_detained_cnt <= # SIM_DELAY 
				on_initiate_wr_mem_trans ? 
					4'd0:
					(wr_mem_trans_detained_cnt + 1'b1);
	end
	
	// 启动写存储器事务(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			on_initiate_wr_mem_trans <= 1'b0;
		else if(
			on_initiate_wr_mem_trans | 
			(
				(wr_mem_trans_to_be_initiated_cnt >= 2) | 
				(has_wr_mem_trans_to_be_initiated & (&wr_mem_trans_detained_cnt))
			)
		)
			on_initiate_wr_mem_trans <= # SIM_DELAY ~on_initiate_wr_mem_trans;
	end
	
	// 待进行地址传输的事务在写存储器总线事务记录表里的指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wr_mem_trans_addr_setup_ptr <= 0;
		else if(m_axi_mem_awvalid & m_axi_mem_awready)
			wr_mem_trans_addr_setup_ptr <= # SIM_DELAY 
				(wr_mem_trans_addr_setup_ptr == (WR_MEM_BUF_ENTRY_N-1)) ? 
					0:
					(wr_mem_trans_addr_setup_ptr + 1);
	end
	// 待进行数据传输的事务在写存储器总线事务记录表里的指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wr_mem_trans_data_transfer_ptr <= 0;
		else if(m_axi_mem_wvalid & m_axi_mem_wready)
			wr_mem_trans_data_transfer_ptr <= # SIM_DELAY 
				(wr_mem_trans_data_transfer_ptr == (WR_MEM_BUF_ENTRY_N-1)) ? 
					0:
					(wr_mem_trans_data_transfer_ptr + 1);
	end
	// 所完成事务在写存储器总线事务记录表里的指针(独热码)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			completed_wr_mem_trans_onehot_ptr <= 1;
		else if(on_complete_wr_mem_trans)
			completed_wr_mem_trans_onehot_ptr <= # SIM_DELAY 
				(completed_wr_mem_trans_onehot_ptr << 1) | (completed_wr_mem_trans_onehot_ptr >> (WR_MEM_BUF_ENTRY_N-1));
	end
	// 所完成事务在写存储器总线事务记录表里的指针(二进制码)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			completed_wr_mem_trans_bin_ptr <= 0;
		else if(on_complete_wr_mem_trans)
			completed_wr_mem_trans_bin_ptr <= # SIM_DELAY 
				(completed_wr_mem_trans_bin_ptr == (WR_MEM_BUF_ENTRY_N-1)) ? 
					0:
					(completed_wr_mem_trans_bin_ptr + 1);
	end
	
	// 写存储器超时计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wr_mem_timeout_cnt <= 0;
		else if(
			(MEM_ACCESS_TIMEOUT_TH > 0) & (~wr_mem_timeout_flag) & 
			((|wr_mem_trans_table_trans_flag) | on_complete_wr_mem_trans)
		)
			wr_mem_timeout_cnt <= # SIM_DELAY 
				on_complete_wr_mem_trans ? 
					0:
					(wr_mem_timeout_cnt + 1);
	end
	// 写存储器超时标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wr_mem_timeout_flag <= 1'b0;
		else if((MEM_ACCESS_TIMEOUT_TH > 0) & (~wr_mem_timeout_flag))
			wr_mem_timeout_flag <= # SIM_DELAY 
				(|wr_mem_trans_table_trans_flag) & (~on_complete_wr_mem_trans) & 
				(wr_mem_timeout_cnt == (MEM_ACCESS_TIMEOUT_TH - 1));
	end
	
	// 写存储器请求信息表的存储内容(对齐地址, 写数据, 写字节掩码, 指令ID, 年龄翻转位, 绑定的总线事务记录编号(独热码))
	// 写存储器请求信息表的标志(条目有效标志, 条目许可标志, 条目传输中标志)
	genvar wr_mem_req_table_entry_i;
	generate
		for(wr_mem_req_table_entry_i = 0;wr_mem_req_table_entry_i < WR_MEM_BUF_ENTRY_N;
			wr_mem_req_table_entry_i = wr_mem_req_table_entry_i + 1)
		begin:wr_mem_req_table_blk
			assign on_wr_mem_req_permitted_to_bus[wr_mem_req_table_entry_i] = 
				// 提交新的写存储器请求时, 刚好"新请求的指令ID"与"待发起总线事务的store指令ID"匹配
				(
					(EN_PERMISSION_CHECK_ON_SUBMIT_NEW_WR_MEM_REQ == "true") & 
					on_submit_new_wr_mem_req & is_allowed_to_submit_new_wr_mem_req & wr_mem_req_table_entry_wptr[wr_mem_req_table_entry_i] & 
					wr_mem_permitted_flag & (init_mem_bus_tr_store_inst_tid == inst_id_of_new_wr_mem_req)
				) | 
				// 条目有效但尚未被许可, "该条目的指令ID"与"待发起总线事务的store指令ID"匹配时得到许可
				(
					wr_mem_req_table_vld_flag[wr_mem_req_table_entry_i] & (~wr_mem_req_table_permitted_flag[wr_mem_req_table_entry_i]) & 
					wr_mem_permitted_flag & (init_mem_bus_tr_store_inst_tid == wr_mem_req_table_inst_id[wr_mem_req_table_entry_i])
				);
			assign wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record[wr_mem_req_table_entry_i] = 
				wr_mem_req_table_vld_flag[wr_mem_req_table_entry_i] & (~wr_mem_req_table_permitted_flag[wr_mem_req_table_entry_i]) & 
				wr_mem_permitted_flag & (init_mem_bus_tr_store_inst_tid == wr_mem_req_table_inst_id[wr_mem_req_table_entry_i]);
			
			assign wr_mem_req_table_vld_flag_nxt[wr_mem_req_table_entry_i] = 
				(
					(on_submit_new_wr_mem_req & is_allowed_to_submit_new_wr_mem_req & wr_mem_req_table_entry_wptr[wr_mem_req_table_entry_i]) | 
					(
						on_complete_wr_mem_trans & 
						wr_mem_req_table_trans_flag[wr_mem_req_table_entry_i] & 
						(|(record_onehot_id_of_completed_wr_mem_trans & wr_mem_req_table_bonding_tr_record_onehot_id[wr_mem_req_table_entry_i]))
					) | 
					(
						clr_wr_mem_buf & 
						(~wr_mem_req_table_permitted_flag[wr_mem_req_table_entry_i]) & 
						(~(
							wr_mem_req_table_vld_flag[wr_mem_req_table_entry_i] & 
							wr_mem_permitted_flag & (init_mem_bus_tr_store_inst_tid == wr_mem_req_table_inst_id[wr_mem_req_table_entry_i])
						))
					)
				) ? 
					(on_submit_new_wr_mem_req & is_allowed_to_submit_new_wr_mem_req & wr_mem_req_table_entry_wptr[wr_mem_req_table_entry_i]):
					wr_mem_req_table_vld_flag[wr_mem_req_table_entry_i];
			
			always @(posedge aclk)
			begin
				if(on_submit_new_wr_mem_req & is_allowed_to_submit_new_wr_mem_req & wr_mem_req_table_entry_wptr[wr_mem_req_table_entry_i])
				begin
					wr_mem_req_table_aligned_addr[wr_mem_req_table_entry_i] <= # SIM_DELAY aligned_addr_of_new_wr_mem_req;
					wr_mem_req_table_wdata[wr_mem_req_table_entry_i] <= # SIM_DELAY wdata_of_new_wr_mem_req;
					wr_mem_req_table_wmask[wr_mem_req_table_entry_i] <= # SIM_DELAY wmask_of_new_wr_mem_req;
					wr_mem_req_table_inst_id[wr_mem_req_table_entry_i] <= # SIM_DELAY inst_id_of_new_wr_mem_req;
					wr_mem_req_table_age_tbit[wr_mem_req_table_entry_i] <= # SIM_DELAY wr_mem_req_table_age_wptr;
				end
			end
			
			always @(posedge aclk)
			begin
				if(
					(
						(EN_PERMISSION_CHECK_ON_SUBMIT_NEW_WR_MEM_REQ == "true") & 
						on_submit_new_wr_mem_req & is_allowed_to_submit_new_wr_mem_req & wr_mem_req_table_entry_wptr[wr_mem_req_table_entry_i] & 
						wr_mem_permitted_flag & (init_mem_bus_tr_store_inst_tid == inst_id_of_new_wr_mem_req)
					) | 
					(
						wr_mem_req_table_vld_flag[wr_mem_req_table_entry_i] & (~wr_mem_req_table_permitted_flag[wr_mem_req_table_entry_i]) & 
						wr_mem_permitted_flag & (init_mem_bus_tr_store_inst_tid == wr_mem_req_table_inst_id[wr_mem_req_table_entry_i])
					)
				)
					wr_mem_req_table_bonding_tr_record_onehot_id[wr_mem_req_table_entry_i] <= # SIM_DELAY 
						creating_new_wr_mem_trans_entry_sel;
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					wr_mem_req_table_vld_flag[wr_mem_req_table_entry_i] <= 1'b0;
				else if(
					(on_submit_new_wr_mem_req & is_allowed_to_submit_new_wr_mem_req & wr_mem_req_table_entry_wptr[wr_mem_req_table_entry_i]) | 
					(
						on_complete_wr_mem_trans & 
						wr_mem_req_table_trans_flag[wr_mem_req_table_entry_i] & 
						(|(record_onehot_id_of_completed_wr_mem_trans & wr_mem_req_table_bonding_tr_record_onehot_id[wr_mem_req_table_entry_i]))
					) | 
					(
						clr_wr_mem_buf & 
						(~wr_mem_req_table_permitted_flag[wr_mem_req_table_entry_i]) & 
						(~(
							wr_mem_req_table_vld_flag[wr_mem_req_table_entry_i] & 
							wr_mem_permitted_flag & (init_mem_bus_tr_store_inst_tid == wr_mem_req_table_inst_id[wr_mem_req_table_entry_i])
						))
					)
				)
					wr_mem_req_table_vld_flag[wr_mem_req_table_entry_i] <= # SIM_DELAY 
						on_submit_new_wr_mem_req & is_allowed_to_submit_new_wr_mem_req & wr_mem_req_table_entry_wptr[wr_mem_req_table_entry_i];
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					wr_mem_req_table_permitted_flag[wr_mem_req_table_entry_i] <= 1'b0;
				else if(
					(
						(EN_PERMISSION_CHECK_ON_SUBMIT_NEW_WR_MEM_REQ == "true") & 
						on_submit_new_wr_mem_req & is_allowed_to_submit_new_wr_mem_req & wr_mem_req_table_entry_wptr[wr_mem_req_table_entry_i]
					) | 
					(
						wr_mem_req_table_vld_flag[wr_mem_req_table_entry_i] & (~wr_mem_req_table_permitted_flag[wr_mem_req_table_entry_i]) & 
						wr_mem_permitted_flag & (init_mem_bus_tr_store_inst_tid == wr_mem_req_table_inst_id[wr_mem_req_table_entry_i])
					) | 
					(
						on_complete_wr_mem_trans & 
						wr_mem_req_table_trans_flag[wr_mem_req_table_entry_i] & 
						(|(record_onehot_id_of_completed_wr_mem_trans & wr_mem_req_table_bonding_tr_record_onehot_id[wr_mem_req_table_entry_i]))
					)
				)
					wr_mem_req_table_permitted_flag[wr_mem_req_table_entry_i] <= # SIM_DELAY 
						(
							(EN_PERMISSION_CHECK_ON_SUBMIT_NEW_WR_MEM_REQ == "false") | 
							wr_mem_req_table_vld_flag[wr_mem_req_table_entry_i] 
						) ? 
							(~wr_mem_req_table_trans_flag[wr_mem_req_table_entry_i]):
							(wr_mem_permitted_flag & (init_mem_bus_tr_store_inst_tid == inst_id_of_new_wr_mem_req)); // 写入初始的条目许可标志
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					wr_mem_req_table_trans_flag[wr_mem_req_table_entry_i] <= 1'b0;
				else if(
					wr_mem_req_table_vld_flag[wr_mem_req_table_entry_i] & 
					(
						(on_initiate_wr_mem_trans & wr_mem_req_table_permitted_flag[wr_mem_req_table_entry_i]) | 
						(
							on_complete_wr_mem_trans & 
							wr_mem_req_table_trans_flag[wr_mem_req_table_entry_i] & 
							(|(record_onehot_id_of_completed_wr_mem_trans & wr_mem_req_table_bonding_tr_record_onehot_id[wr_mem_req_table_entry_i]))
						)
					)
				)
					wr_mem_req_table_trans_flag[wr_mem_req_table_entry_i] <= # SIM_DELAY 
						~(
							on_complete_wr_mem_trans & 
							wr_mem_req_table_trans_flag[wr_mem_req_table_entry_i] & 
							(|(record_onehot_id_of_completed_wr_mem_trans & wr_mem_req_table_bonding_tr_record_onehot_id[wr_mem_req_table_entry_i]))
						);
			end
		end
	endgenerate
	
	// 写存储器总线事务记录表的存储内容(对齐地址, 写数据, 写字节掩码)
	// 写存储器总线事务记录表的标志(有效标志, 传输中标志, 地址通道已传输标志, 数据通道已传输标志)
	genvar wr_mem_trans_table_entry_i;
	genvar wr_mem_trans_table_byte_j;
	generate
		for(wr_mem_trans_table_entry_i = 0;wr_mem_trans_table_entry_i < WR_MEM_BUF_ENTRY_N;
			wr_mem_trans_table_entry_i = wr_mem_trans_table_entry_i + 1)
		begin:wr_mem_trans_table_blk
			assign new_wr_mem_trans_mergeable_onehot[wr_mem_trans_table_entry_i] = 
				wr_mem_trans_table_vld_flag[wr_mem_trans_table_entry_i] & (~wr_mem_trans_table_trans_flag[wr_mem_trans_table_entry_i]) & 
				(
					wr_mem_trans_table_aligned_addr[wr_mem_trans_table_entry_i][31:clogb2(AXI_MEM_DATA_WIDTH/8)] == 
						aligned_addr_of_creating_new_wr_mem_trans_record[31:clogb2(AXI_MEM_DATA_WIDTH/8)]
				);
			assign creating_new_wr_mem_trans_entry_sel[wr_mem_trans_table_entry_i] = 
				(on_initiate_wr_mem_trans | (~(|new_wr_mem_trans_mergeable_onehot))) ? 
					wr_mem_trans_table_entry_wptr[wr_mem_trans_table_entry_i]:
					new_wr_mem_trans_mergeable_onehot[wr_mem_trans_table_entry_i];
			
			always @(posedge aclk)
			begin
				if(
					on_create_new_wr_mem_trans_record & 
					(on_initiate_wr_mem_trans | (~(|new_wr_mem_trans_mergeable_onehot))) & 
					wr_mem_trans_table_entry_wptr[wr_mem_trans_table_entry_i]
				)
					wr_mem_trans_table_aligned_addr[wr_mem_trans_table_entry_i] <= # SIM_DELAY 
						aligned_addr_of_creating_new_wr_mem_trans_record & (~(AXI_MEM_DATA_WIDTH/8 - 1));
			end
			
			always @(posedge aclk)
			begin
				if(on_create_new_wr_mem_trans_record & creating_new_wr_mem_trans_entry_sel[wr_mem_trans_table_entry_i])
					wr_mem_trans_table_wmask[wr_mem_trans_table_entry_i] <= # SIM_DELAY 
						(
							{(AXI_MEM_DATA_WIDTH/8){~(on_initiate_wr_mem_trans | (~(|new_wr_mem_trans_mergeable_onehot)))}} & 
							wr_mem_trans_table_wmask[wr_mem_trans_table_entry_i]
						) | 
						(
							(wmask_of_creating_new_wr_mem_trans_record | {(AXI_MEM_DATA_WIDTH/8){1'b0}}) << 
								((aligned_addr_of_creating_new_wr_mem_trans_record[31:2] & (AXI_MEM_DATA_WIDTH/32 - 1)) * 4)
						);
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					wr_mem_trans_table_vld_flag[wr_mem_trans_table_entry_i] <= 1'b0;
				else if(
					(
						on_create_new_wr_mem_trans_record & 
						(on_initiate_wr_mem_trans | (~(|new_wr_mem_trans_mergeable_onehot))) & 
						wr_mem_trans_table_entry_wptr[wr_mem_trans_table_entry_i]
					) | 
					(on_complete_wr_mem_trans & completed_wr_mem_trans_onehot_ptr[wr_mem_trans_table_entry_i])
				)
					wr_mem_trans_table_vld_flag[wr_mem_trans_table_entry_i] <= # SIM_DELAY 
						~(on_complete_wr_mem_trans & completed_wr_mem_trans_onehot_ptr[wr_mem_trans_table_entry_i]);
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					wr_mem_trans_table_trans_flag[wr_mem_trans_table_entry_i] <= 1'b0;
				else if(
					(
						on_initiate_wr_mem_trans & 
						wr_mem_trans_table_vld_flag[wr_mem_trans_table_entry_i] & 
						(~wr_mem_trans_table_trans_flag[wr_mem_trans_table_entry_i])
					) | 
					(on_complete_wr_mem_trans & completed_wr_mem_trans_onehot_ptr[wr_mem_trans_table_entry_i])
				)
					wr_mem_trans_table_trans_flag[wr_mem_trans_table_entry_i] <= # SIM_DELAY 
						~(on_complete_wr_mem_trans & completed_wr_mem_trans_onehot_ptr[wr_mem_trans_table_entry_i]);
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					wr_mem_trans_table_addr_setup_flag[wr_mem_trans_table_entry_i] <= 1'b0;
				else if(
					(m_axi_mem_awvalid & m_axi_mem_awready & (wr_mem_trans_addr_setup_ptr == wr_mem_trans_table_entry_i)) | 
					(on_complete_wr_mem_trans & completed_wr_mem_trans_onehot_ptr[wr_mem_trans_table_entry_i])
				)
					wr_mem_trans_table_addr_setup_flag[wr_mem_trans_table_entry_i] <= # SIM_DELAY 
						~(on_complete_wr_mem_trans & completed_wr_mem_trans_onehot_ptr[wr_mem_trans_table_entry_i]);
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					wr_mem_trans_table_data_sent_flag[wr_mem_trans_table_entry_i] <= 1'b0;
				else if(
					(m_axi_mem_wvalid & m_axi_mem_wready & (wr_mem_trans_data_transfer_ptr == wr_mem_trans_table_entry_i)) | 
					(on_complete_wr_mem_trans & completed_wr_mem_trans_onehot_ptr[wr_mem_trans_table_entry_i])
				)
					wr_mem_trans_table_data_sent_flag[wr_mem_trans_table_entry_i] <= # SIM_DELAY 
						~(on_complete_wr_mem_trans & completed_wr_mem_trans_onehot_ptr[wr_mem_trans_table_entry_i]);
			end
			
			for(wr_mem_trans_table_byte_j = 0;wr_mem_trans_table_byte_j < AXI_MEM_DATA_WIDTH/8;
				wr_mem_trans_table_byte_j = wr_mem_trans_table_byte_j + 1)
			begin:wr_mem_trans_table_entry_blk
				always @(posedge aclk)
				begin
					if(
						on_create_new_wr_mem_trans_record & creating_new_wr_mem_trans_entry_sel[wr_mem_trans_table_entry_i] & 
						(
							(aligned_addr_of_creating_new_wr_mem_trans_record[31:2] & (AXI_MEM_DATA_WIDTH/32 - 1)) == 
								(wr_mem_trans_table_byte_j/4)
						) & 
						wmask_of_creating_new_wr_mem_trans_record[wr_mem_trans_table_byte_j%4]
					)
						wr_mem_trans_table_wdata[wr_mem_trans_table_entry_i][(wr_mem_trans_table_byte_j+1)*8-1:wr_mem_trans_table_byte_j*8] <= # SIM_DELAY 
							wdata_of_creating_new_wr_mem_trans_record[((wr_mem_trans_table_byte_j%4)+1)*8-1:(wr_mem_trans_table_byte_j%4)*8];
				end
			end
		end
	endgenerate
	
	/** 读存储器 **/
	// [启动读存储器总线事务]
	wire on_initiate_rd_mem_trans; // 发起事务(标志)
	wire[31:0] new_rd_mem_trans_org_addr; // 新事务的原始地址
	wire[clogb2(LSU_REQ_BUF_ENTRY_N-1):0] new_rd_mem_trans_req_id; // 新事务的请求ID
	wire is_allowed_to_submit_new_rd_mem_req; // 允许提交新请求(标志)
	// [检查写存储器缓存]
	wire on_initiate_wr_mem_buf_check; // 发起写存储器缓存检查(指示)
	wire[31:0] org_addr_for_wr_mem_buf_check; // 写存储器缓存检查的原始地址
	wire[clogb2(LSU_REQ_BUF_ENTRY_N-1):0] req_id_for_wr_mem_buf_check; // 写存储器缓存检查的请求ID
	wire on_return_wr_mem_buf_check_res; // 返回写存储器缓存检查结果(指示)
	wire on_return_wr_mem_buf_check_res_p1; // 提前1clk的返回写存储器缓存检查结果(指示)
	wire[31:0] merging_data_of_wr_mem_buf_check_res; // 写存储器缓存检查结果的待合并数据
	wire[3:0] merging_mask_of_wr_mem_buf_check_res; // 写存储器缓存检查结果的数据合并字节掩码
	wire[clogb2(LSU_REQ_BUF_ENTRY_N-1):0] req_id_of_wr_mem_buf_check_res; // 写存储器缓存检查结果的请求ID
	reg[RD_MEM_BUF_ENTRY_N-1:0] rd_mem_trans_waiting_wr_mem_buf_check_res_ptr; // 等待写存储器缓存检查结果的项指针
	reg[RD_MEM_BUF_ENTRY_N-1:0] rd_mem_trans_waiting_wr_mem_buf_check_res_ptr_p1; // 提前1clk的等待写存储器缓存检查结果的项指针
	// [读存储器总线事务进程]
	reg[clogb2(RD_MEM_BUF_ENTRY_N-1):0] rd_mem_trans_wptr; // 记录表写指针
	reg[clogb2(RD_MEM_BUF_ENTRY_N-1):0] rd_mem_trans_addr_setup_ptr; // 正在进行地址传输的项指针
	reg[clogb2(RD_MEM_BUF_ENTRY_N-1):0] rd_mem_trans_waiting_resp_ptr; // 等待读响应的项指针
	reg[clogb2(RD_MEM_BUF_ENTRY_N):0] rd_mem_trans_vld_cnt; // 记录表中有效项数(计数器)
	reg rd_mem_trans_full_flag; // 记录表满(标志)
	// [读存储器超时限制]
	reg[clogb2(MEM_ACCESS_TIMEOUT_TH):0] rd_mem_timeout_cnt; // 超时计数器
	reg rd_mem_timeout_flag; // 超时标志
	reg on_rd_mem_timeout; // 超时指示
	// [读存储器访问结果]
	wire on_complete_rd_mem_trans; // 完成读存储器事务(指示)
	reg on_upd_req_entry_of_rd_mem_trans; // 更新读存储器事务对应的请求条目(指示)
	reg[clogb2(LSU_REQ_BUF_ENTRY_N-1):0] req_id_of_completed_rd_mem_trans; // 所完成读存储器事务的请求ID
	reg[31:0] rdata_of_completed_rd_mem_trans; // 所完成读存储器事务的读数据
	reg[1:0] err_code_of_completed_rd_mem_trans; // 所完成读存储器事务的错误码
	wire on_upd_req_entry_of_rd_mem_trans_w;
	wire[clogb2(LSU_REQ_BUF_ENTRY_N-1):0] req_id_of_completed_rd_mem_trans_w;
	wire[31:0] rdata_of_completed_rd_mem_trans_w;
	wire[1:0] err_code_of_completed_rd_mem_trans_w;
	// [读存储器总线事务记录表]
	reg[31:0] rd_mem_trans_table_org_addr[0:RD_MEM_BUF_ENTRY_N-1]; // 原始地址
	reg[clogb2(LSU_REQ_BUF_ENTRY_N-1):0] rd_mem_trans_table_req_id[0:RD_MEM_BUF_ENTRY_N-1]; // 请求ID
	reg[RD_MEM_BUF_ENTRY_N-1:0] rd_mem_trans_table_vld_flag; // 有效标志
	reg[RD_MEM_BUF_ENTRY_N-1:0] rd_mem_trans_table_check_done_flag; // 已检查写存储器缓存标志
	reg[RD_MEM_BUF_ENTRY_N-1:0] rd_mem_trans_table_addr_setup_flag; // 地址通道已传输标志
	
	// [AR通道]
	assign m_axi_mem_araddr = 
		(
			((EN_LOW_LATENCY_RD_MEM_ACCESS >= 2) & (~rd_mem_trans_table_vld_flag[rd_mem_trans_addr_setup_ptr])) ? 
				new_rd_mem_trans_org_addr:
				rd_mem_trans_table_org_addr[rd_mem_trans_addr_setup_ptr]
		) & (~(AXI_MEM_DATA_WIDTH/8 - 1));
	assign m_axi_mem_arburst = 2'b01;
	assign m_axi_mem_arlen = 8'd0;
	assign m_axi_mem_arsize = clogb2(AXI_MEM_DATA_WIDTH/8);
	assign m_axi_mem_arvalid = 
		|(
			(
				(
					rd_mem_trans_table_vld_flag | 
					(
						{RD_MEM_BUF_ENTRY_N{
							(EN_LOW_LATENCY_RD_MEM_ACCESS >= 2) & on_initiate_rd_mem_trans & is_allowed_to_submit_new_rd_mem_req
						}} & 
						(1 << rd_mem_trans_wptr)
					)
				) & 
				(~rd_mem_trans_table_addr_setup_flag) & 
				(
					rd_mem_trans_table_check_done_flag | 
					(
						(EN_LOW_LATENCY_RD_MEM_ACCESS >= 2) ? 
							({RD_MEM_BUF_ENTRY_N{on_return_wr_mem_buf_check_res_p1}} & rd_mem_trans_waiting_wr_mem_buf_check_res_ptr_p1):
							({RD_MEM_BUF_ENTRY_N{on_return_wr_mem_buf_check_res}} & rd_mem_trans_waiting_wr_mem_buf_check_res_ptr)
					)
				)
			) & 
			(1 << rd_mem_trans_addr_setup_ptr)
		);
	// [R通道]
	assign m_axi_mem_rready = 1'b1;
	
	assign rd_mem_timeout = rd_mem_timeout_flag;
	
	assign is_allowed_to_submit_new_rd_mem_req = ~rd_mem_trans_full_flag;
	
	assign on_initiate_wr_mem_buf_check = on_initiate_rd_mem_trans;
	assign org_addr_for_wr_mem_buf_check = new_rd_mem_trans_org_addr;
	assign req_id_for_wr_mem_buf_check = new_rd_mem_trans_req_id;
	
	assign on_complete_rd_mem_trans = m_axi_mem_rvalid & m_axi_mem_rready;
	
	assign on_upd_req_entry_of_rd_mem_trans_w = 
		(EN_LOW_LATENCY_RD_MEM_ACCESS >= 1) ? 
			(on_complete_rd_mem_trans | on_rd_mem_timeout):
			on_upd_req_entry_of_rd_mem_trans;
	assign req_id_of_completed_rd_mem_trans_w = 
		(EN_LOW_LATENCY_RD_MEM_ACCESS >= 1) ? 
			rd_mem_trans_table_req_id[rd_mem_trans_waiting_resp_ptr]:
			req_id_of_completed_rd_mem_trans;
	assign rdata_of_completed_rd_mem_trans_w = 
		(EN_LOW_LATENCY_RD_MEM_ACCESS >= 1) ? 
			(
				m_axi_mem_rdata >> 
					((rd_mem_trans_table_org_addr[rd_mem_trans_waiting_resp_ptr][31:2] & (AXI_MEM_DATA_WIDTH/32 - 1)) * 32)
			):
			rdata_of_completed_rd_mem_trans;
	assign err_code_of_completed_rd_mem_trans_w = 
		(EN_LOW_LATENCY_RD_MEM_ACCESS >= 1) ? 
			(
				on_rd_mem_timeout ? 
					DBUS_ACCESS_TIMEOUT:
					(
						(m_axi_mem_rresp != AXI_RESP_OKAY) ? 
							DBUS_ACCESS_BUS_ERR:
							DBUS_ACCESS_NORMAL
					)
			):
			err_code_of_completed_rd_mem_trans;
	
	// 等待写存储器缓存检查结果的项指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rd_mem_trans_waiting_wr_mem_buf_check_res_ptr <= 1;
		else if(on_return_wr_mem_buf_check_res)
			rd_mem_trans_waiting_wr_mem_buf_check_res_ptr <= # SIM_DELAY 
				(rd_mem_trans_waiting_wr_mem_buf_check_res_ptr << 1) | 
				(rd_mem_trans_waiting_wr_mem_buf_check_res_ptr >> (RD_MEM_BUF_ENTRY_N-1));
	end
	// 提前1clk的等待写存储器缓存检查结果的项指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rd_mem_trans_waiting_wr_mem_buf_check_res_ptr_p1 <= 1;
		else if(on_return_wr_mem_buf_check_res_p1)
			rd_mem_trans_waiting_wr_mem_buf_check_res_ptr_p1 <= # SIM_DELAY 
				(rd_mem_trans_waiting_wr_mem_buf_check_res_ptr_p1 << 1) | 
				(rd_mem_trans_waiting_wr_mem_buf_check_res_ptr_p1 >> (RD_MEM_BUF_ENTRY_N-1));
	end
	
	// 读存储器总线事务记录表写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rd_mem_trans_wptr <= 0;
		else if(on_initiate_rd_mem_trans & is_allowed_to_submit_new_rd_mem_req)
			rd_mem_trans_wptr <= # SIM_DELAY 
				(rd_mem_trans_wptr == (RD_MEM_BUF_ENTRY_N-1)) ? 
					0:
					(rd_mem_trans_wptr + 1);
	end
	// 正在进行地址传输的项指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rd_mem_trans_addr_setup_ptr <= 0;
		else if(m_axi_mem_arvalid & m_axi_mem_arready)
			rd_mem_trans_addr_setup_ptr <= # SIM_DELAY 
				(rd_mem_trans_addr_setup_ptr == (RD_MEM_BUF_ENTRY_N-1)) ? 
					0:
					(rd_mem_trans_addr_setup_ptr + 1);
	end
	// 等待读响应的项指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rd_mem_trans_waiting_resp_ptr <= 0;
		else if(on_complete_rd_mem_trans | on_rd_mem_timeout)
			rd_mem_trans_waiting_resp_ptr <= # SIM_DELAY 
				(rd_mem_trans_waiting_resp_ptr == (RD_MEM_BUF_ENTRY_N-1)) ? 
					0:
					(rd_mem_trans_waiting_resp_ptr + 1);
	end
	
	// 读存储器总线事务记录表中有效项数(计数器)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rd_mem_trans_vld_cnt <= 0;
		else if(
			(on_initiate_rd_mem_trans & is_allowed_to_submit_new_rd_mem_req) ^ 
			(on_complete_rd_mem_trans | on_rd_mem_timeout)
		)
			rd_mem_trans_vld_cnt <= # SIM_DELAY 
				(on_complete_rd_mem_trans | on_rd_mem_timeout) ? 
					(rd_mem_trans_vld_cnt - 1):
					(rd_mem_trans_vld_cnt + 1);
	end
	// 读存储器总线事务记录表满(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rd_mem_trans_full_flag <= 1'b0;
		else if(
			(on_initiate_rd_mem_trans & is_allowed_to_submit_new_rd_mem_req) ^ 
			(on_complete_rd_mem_trans | on_rd_mem_timeout)
		)
			rd_mem_trans_full_flag <= # SIM_DELAY 
				(~(on_complete_rd_mem_trans | on_rd_mem_timeout)) & 
				(rd_mem_trans_vld_cnt == (RD_MEM_BUF_ENTRY_N - 1));
	end
	
	// 读存储器超时计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rd_mem_timeout_cnt <= 0;
		else if(
			(MEM_ACCESS_TIMEOUT_TH > 0) & (~rd_mem_timeout_flag) & 
			(
				(m_axi_mem_rvalid & m_axi_mem_rready) | 
				(|(rd_mem_trans_table_vld_flag & rd_mem_trans_table_check_done_flag))
			)
		)
			rd_mem_timeout_cnt <= # SIM_DELAY 
				(m_axi_mem_rvalid & m_axi_mem_rready) ? 
					0:
					(rd_mem_timeout_cnt + 1);
	end
	// 读存储器超时标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rd_mem_timeout_flag <= 1'b0;
		else if((MEM_ACCESS_TIMEOUT_TH > 0) & (~rd_mem_timeout_flag))
			rd_mem_timeout_flag <= # SIM_DELAY 
				(|(rd_mem_trans_table_vld_flag & rd_mem_trans_table_check_done_flag)) & 
				(~(m_axi_mem_rvalid & m_axi_mem_rready)) & 
				(rd_mem_timeout_cnt == (MEM_ACCESS_TIMEOUT_TH - 1));
	end
	// 读存储器超时指示
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			on_rd_mem_timeout <= 1'b0;
		else if(
			on_rd_mem_timeout | 
			(
				(MEM_ACCESS_TIMEOUT_TH > 0) & 
				(|(rd_mem_trans_table_vld_flag & rd_mem_trans_table_check_done_flag)) & 
				(~(m_axi_mem_rvalid & m_axi_mem_rready)) & 
				(rd_mem_timeout_cnt == (MEM_ACCESS_TIMEOUT_TH - 1))
			)
		)
			on_rd_mem_timeout <= # SIM_DELAY ~on_rd_mem_timeout;
	end
	
	// 更新读存储器事务对应的请求条目(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			on_upd_req_entry_of_rd_mem_trans <= 1'b0;
		else
			on_upd_req_entry_of_rd_mem_trans <= # SIM_DELAY 
				on_complete_rd_mem_trans | on_rd_mem_timeout;
	end
	// 所完成读存储器事务的请求ID, 所完成读存储器事务的读数据, 所完成读存储器事务的错误码
	always @(posedge aclk)
	begin
		if(on_complete_rd_mem_trans | on_rd_mem_timeout)
		begin
			req_id_of_completed_rd_mem_trans <= # SIM_DELAY 
				rd_mem_trans_table_req_id[rd_mem_trans_waiting_resp_ptr];
			
			rdata_of_completed_rd_mem_trans <= # SIM_DELAY 
				m_axi_mem_rdata >> 
					((rd_mem_trans_table_org_addr[rd_mem_trans_waiting_resp_ptr][31:2] & (AXI_MEM_DATA_WIDTH/32 - 1)) * 32);
			
			err_code_of_completed_rd_mem_trans <= # SIM_DELAY 
				on_rd_mem_timeout ? 
					DBUS_ACCESS_TIMEOUT:
					(
						(m_axi_mem_rresp != AXI_RESP_OKAY) ? 
							DBUS_ACCESS_BUS_ERR:
							DBUS_ACCESS_NORMAL
					);
		end
	end
	
	// 读存储器总线事务记录表的存储内容(原始地址, 请求ID)
	// 读存储器总线事务记录表的标志(有效标志, 已检查写存储器缓存标志, 地址通道已传输标志)
	genvar rd_mem_trans_table_entry_i;
	generate
		for(rd_mem_trans_table_entry_i = 0;rd_mem_trans_table_entry_i < RD_MEM_BUF_ENTRY_N;
			rd_mem_trans_table_entry_i = rd_mem_trans_table_entry_i + 1)
		begin:rd_mem_trans_table_blk
			always @(posedge aclk)
			begin
				if(
					on_initiate_rd_mem_trans & is_allowed_to_submit_new_rd_mem_req & 
					(rd_mem_trans_wptr == rd_mem_trans_table_entry_i)
				)
				begin
					rd_mem_trans_table_org_addr[rd_mem_trans_table_entry_i] <= # SIM_DELAY new_rd_mem_trans_org_addr;
					rd_mem_trans_table_req_id[rd_mem_trans_table_entry_i] <= # SIM_DELAY new_rd_mem_trans_req_id;
				end
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					rd_mem_trans_table_vld_flag[rd_mem_trans_table_entry_i] <= 1'b0;
				else if(
					(on_initiate_rd_mem_trans & is_allowed_to_submit_new_rd_mem_req & (rd_mem_trans_wptr == rd_mem_trans_table_entry_i)) | 
					((on_complete_rd_mem_trans | on_rd_mem_timeout) & (rd_mem_trans_waiting_resp_ptr == rd_mem_trans_table_entry_i))
				)
					rd_mem_trans_table_vld_flag[rd_mem_trans_table_entry_i] <= # SIM_DELAY 
						~((on_complete_rd_mem_trans | on_rd_mem_timeout) & (rd_mem_trans_waiting_resp_ptr == rd_mem_trans_table_entry_i));
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					rd_mem_trans_table_check_done_flag[rd_mem_trans_table_entry_i] <= 1'b0;
				else if(
					(
						(EN_LOW_LATENCY_RD_MEM_ACCESS >= 2) ? 
							(on_return_wr_mem_buf_check_res_p1 & rd_mem_trans_waiting_wr_mem_buf_check_res_ptr_p1[rd_mem_trans_table_entry_i]):
							(on_return_wr_mem_buf_check_res & rd_mem_trans_waiting_wr_mem_buf_check_res_ptr[rd_mem_trans_table_entry_i])
					) | 
					((on_complete_rd_mem_trans | on_rd_mem_timeout) & (rd_mem_trans_waiting_resp_ptr == rd_mem_trans_table_entry_i))
				)
					rd_mem_trans_table_check_done_flag[rd_mem_trans_table_entry_i] <= # SIM_DELAY 
						~((on_complete_rd_mem_trans | on_rd_mem_timeout) & (rd_mem_trans_waiting_resp_ptr == rd_mem_trans_table_entry_i));
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					rd_mem_trans_table_addr_setup_flag[rd_mem_trans_table_entry_i] <= 1'b0;
				else if(
					(
						m_axi_mem_arvalid & m_axi_mem_arready & 
						(rd_mem_trans_addr_setup_ptr == rd_mem_trans_table_entry_i)
					) | 
					((on_complete_rd_mem_trans | on_rd_mem_timeout) & (rd_mem_trans_waiting_resp_ptr == rd_mem_trans_table_entry_i))
				)
					rd_mem_trans_table_addr_setup_flag[rd_mem_trans_table_entry_i] <= # SIM_DELAY 
						~((on_complete_rd_mem_trans | on_rd_mem_timeout) & (rd_mem_trans_waiting_resp_ptr == rd_mem_trans_table_entry_i));
			end
		end
	endgenerate
	
	/**
	写存储器缓存检查
	
	用指定的对齐地址检查写存储器缓存, 得到这一对齐地址最新的写数据和写字节掩码
	**/
	// [字节修改掩码]
	wire[WR_MEM_BUF_ENTRY_N-1:0] wr_mem_buf_entry_vld_flag_foreach_byte[0:3]; // 每个字节的缓存项有效标志
	reg[3:0] wr_mem_buf_check_modified_byte_mask; // 已修改的字节(掩码)
	// [查找每个字节的最新修改项]
	wire[15:0] wr_mem_buf_finding_newest_mdf_s0_vld_vec[0:3];
	wire[15:0] wr_mem_buf_finding_newest_mdf_s0_age_tbit[0:3];
	wire[16*4-1:0] wr_mem_buf_finding_newest_mdf_s0_id[0:3];
	wire[7:0] wr_mem_buf_finding_newest_mdf_s1_vld_vec[0:3];
	wire[7:0] wr_mem_buf_finding_newest_mdf_s1_age_tbit[0:3];
	wire[8*4-1:0] wr_mem_buf_finding_newest_mdf_s1_id[0:3];
	wire[3:0] wr_mem_buf_finding_newest_mdf_s2_vld_vec[0:3];
	wire[3:0] wr_mem_buf_finding_newest_mdf_s2_age_tbit[0:3];
	wire[4*4-1:0] wr_mem_buf_finding_newest_mdf_s2_id[0:3];
	wire[1:0] wr_mem_buf_finding_newest_mdf_s3_vld_vec[0:3];
	wire[1:0] wr_mem_buf_finding_newest_mdf_s3_age_tbit[0:3];
	wire[2*4-1:0] wr_mem_buf_finding_newest_mdf_s3_id[0:3];
	wire wr_mem_buf_finding_newest_mdf_s4_vld_vec[0:3];
	wire[1*4-1:0] wr_mem_buf_finding_newest_mdf_s4_id[0:3];
	reg[3:0] wr_mem_buf_check_newest_mdf_entry_id_foreach_byte[0:3]; // 每个字节的最新修改项编号
	reg[31:0] wr_mem_buf_check_newest_modified_byte; // 已修改的字节(数据)
	// [延迟1clk的写存储器缓存检查输入]
	reg[31:0] wr_mem_req_table_wdata_d1[0:WR_MEM_BUF_ENTRY_N-1]; // 延迟1clk的写存储器请求信息表写数据
	reg[clogb2(LSU_REQ_BUF_ENTRY_N-1):0] req_id_for_wr_mem_buf_check_d1; // 延迟1clk的写存储器缓存检查的请求ID
	reg on_initiate_wr_mem_buf_check_d1; // 延迟1clk的发起写存储器缓存检查(指示)
	
	assign on_return_wr_mem_buf_check_res = 
		on_initiate_wr_mem_buf_check_d1;
	assign on_return_wr_mem_buf_check_res_p1 = 
		on_initiate_wr_mem_buf_check;
	assign merging_data_of_wr_mem_buf_check_res = 
		(EN_LOW_LATENCY_RD_MEM_ACCESS >= 1) ? 
			wr_mem_buf_check_newest_modified_byte:
			{
				wr_mem_req_table_wdata_d1[wr_mem_buf_check_newest_mdf_entry_id_foreach_byte[3][clogb2(WR_MEM_BUF_ENTRY_N-1):0]][31:24],
				wr_mem_req_table_wdata_d1[wr_mem_buf_check_newest_mdf_entry_id_foreach_byte[2][clogb2(WR_MEM_BUF_ENTRY_N-1):0]][23:16],
				wr_mem_req_table_wdata_d1[wr_mem_buf_check_newest_mdf_entry_id_foreach_byte[1][clogb2(WR_MEM_BUF_ENTRY_N-1):0]][15:8],
				wr_mem_req_table_wdata_d1[wr_mem_buf_check_newest_mdf_entry_id_foreach_byte[0][clogb2(WR_MEM_BUF_ENTRY_N-1):0]][7:0]
			};
	assign merging_mask_of_wr_mem_buf_check_res = 
		wr_mem_buf_check_modified_byte_mask;
	assign req_id_of_wr_mem_buf_check_res = 
		req_id_for_wr_mem_buf_check_d1;
	
	// 延迟1clk的发起写存储器缓存检查(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			on_initiate_wr_mem_buf_check_d1 <= 1'b0;
		else
			on_initiate_wr_mem_buf_check_d1 <= # SIM_DELAY on_initiate_wr_mem_buf_check;
	end
	
	// 已修改的字节(掩码), 延迟1clk的写存储器缓存检查的请求ID
	always @(posedge aclk)
	begin
		if(on_initiate_wr_mem_buf_check)
		begin
			wr_mem_buf_check_modified_byte_mask <= # SIM_DELAY 
				{
					wr_mem_buf_finding_newest_mdf_s4_vld_vec[3],
					wr_mem_buf_finding_newest_mdf_s4_vld_vec[2],
					wr_mem_buf_finding_newest_mdf_s4_vld_vec[1],
					wr_mem_buf_finding_newest_mdf_s4_vld_vec[0]
				};
			
			req_id_for_wr_mem_buf_check_d1 <= # SIM_DELAY req_id_for_wr_mem_buf_check;
		end
	end
	
	 // 已修改的字节(数据)
	always @(posedge aclk)
	begin
		if(on_initiate_wr_mem_buf_check)
		begin
			wr_mem_buf_check_newest_modified_byte <= # SIM_DELAY 
				{
					wr_mem_req_table_wdata[wr_mem_buf_finding_newest_mdf_s4_id[3][clogb2(WR_MEM_BUF_ENTRY_N-1):0]][31:24],
					wr_mem_req_table_wdata[wr_mem_buf_finding_newest_mdf_s4_id[2][clogb2(WR_MEM_BUF_ENTRY_N-1):0]][23:16],
					wr_mem_req_table_wdata[wr_mem_buf_finding_newest_mdf_s4_id[1][clogb2(WR_MEM_BUF_ENTRY_N-1):0]][15:8],
					wr_mem_req_table_wdata[wr_mem_buf_finding_newest_mdf_s4_id[0][clogb2(WR_MEM_BUF_ENTRY_N-1):0]][7:0]
				};
		end
	end
	
	// 延迟1clk的写存储器请求信息表写数据
	genvar wr_mem_buf_check_entry_i;
	genvar wr_mem_buf_check_byte_j;
	generate
		for(wr_mem_buf_check_entry_i = 0;wr_mem_buf_check_entry_i < WR_MEM_BUF_ENTRY_N;
			wr_mem_buf_check_entry_i = wr_mem_buf_check_entry_i + 1)
		begin:wr_mem_buf_check_blk
			for(wr_mem_buf_check_byte_j = 0;wr_mem_buf_check_byte_j < 4;
				wr_mem_buf_check_byte_j = wr_mem_buf_check_byte_j + 1)
			begin:wr_mem_buf_check_entry_blk
				assign wr_mem_buf_entry_vld_flag_foreach_byte[wr_mem_buf_check_byte_j][wr_mem_buf_check_entry_i] = 
					wr_mem_req_table_vld_flag[wr_mem_buf_check_entry_i] & 
					(wr_mem_req_table_aligned_addr[wr_mem_buf_check_entry_i][31:2] == org_addr_for_wr_mem_buf_check[31:2]) & 
					wr_mem_req_table_wmask[wr_mem_buf_check_entry_i][wr_mem_buf_check_byte_j];
			end
			
			always @(posedge aclk)
			begin
				if(on_initiate_wr_mem_buf_check)
					wr_mem_req_table_wdata_d1[wr_mem_buf_check_entry_i] <= # SIM_DELAY 
						wr_mem_req_table_wdata[wr_mem_buf_check_entry_i];
			end
		end
	endgenerate
	
	// 每个字节的最新修改项编号
	genvar finding_newest_mdf_i;
	genvar finding_newest_mdf_s0_j;
	genvar finding_newest_mdf_s1_j;
	genvar finding_newest_mdf_s2_j;
	genvar finding_newest_mdf_s3_j;
	generate
		for(finding_newest_mdf_i = 0;finding_newest_mdf_i < 4;finding_newest_mdf_i = finding_newest_mdf_i + 1)
		begin:finding_newest_mdf_blk
			for(finding_newest_mdf_s0_j = 0;finding_newest_mdf_s0_j < 16;finding_newest_mdf_s0_j = finding_newest_mdf_s0_j + 1)
			begin:finding_newest_mdf_s0_blk
				assign wr_mem_buf_finding_newest_mdf_s0_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s0_j] = 
					(finding_newest_mdf_s0_j < WR_MEM_BUF_ENTRY_N) ? 
						wr_mem_buf_entry_vld_flag_foreach_byte[finding_newest_mdf_i][finding_newest_mdf_s0_j]:
						1'b0;
				assign wr_mem_buf_finding_newest_mdf_s0_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s0_j] = 
					(finding_newest_mdf_s0_j < WR_MEM_BUF_ENTRY_N) ? 
						wr_mem_req_table_age_tbit[finding_newest_mdf_s0_j]:
						1'bx;
				assign wr_mem_buf_finding_newest_mdf_s0_id[finding_newest_mdf_i][(finding_newest_mdf_s0_j+1)*4-1:finding_newest_mdf_s0_j*4] = 
					finding_newest_mdf_s0_j;
			end
			
			for(finding_newest_mdf_s1_j = 0;finding_newest_mdf_s1_j < 8;finding_newest_mdf_s1_j = finding_newest_mdf_s1_j + 1)
			begin:finding_newest_mdf_s1_blk
				assign wr_mem_buf_finding_newest_mdf_s1_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s1_j] = 
					wr_mem_buf_finding_newest_mdf_s0_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s1_j*2+0] | 
					wr_mem_buf_finding_newest_mdf_s0_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s1_j*2+1];
				/*
				选较新项的逻辑:
				
				vld | age                       vld | age
				---------                       ---------
				 0  |  X  ---选上项--->          0  |  X
				 0  |  X                         1  |  V  ---选下项--->
				
				vld | age                       vld | age
				---------                       ---------
				 1  |  V  ---选上项--->          1  |  V  ---若age不同则选上项--->
				 0  |  X                         1  |  V  ---若age相同则选下项--->
				*/
				assign wr_mem_buf_finding_newest_mdf_s1_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s1_j] = 
					(
						wr_mem_buf_finding_newest_mdf_s0_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s1_j*2+1] & 
						(
							(~wr_mem_buf_finding_newest_mdf_s0_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s1_j*2+0]) | 
							(~(
								wr_mem_buf_finding_newest_mdf_s0_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s1_j*2+0] ^ 
								wr_mem_buf_finding_newest_mdf_s0_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s1_j*2+1]
							))
						)
					) ? 
						wr_mem_buf_finding_newest_mdf_s0_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s1_j*2+1]:
						wr_mem_buf_finding_newest_mdf_s0_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s1_j*2+0];
				assign wr_mem_buf_finding_newest_mdf_s1_id[finding_newest_mdf_i][(finding_newest_mdf_s1_j+1)*4-1:finding_newest_mdf_s1_j*4] = 
					(
						wr_mem_buf_finding_newest_mdf_s0_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s1_j*2+1] & 
						(
							(~wr_mem_buf_finding_newest_mdf_s0_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s1_j*2+0]) | 
							(~(
								wr_mem_buf_finding_newest_mdf_s0_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s1_j*2+0] ^ 
								wr_mem_buf_finding_newest_mdf_s0_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s1_j*2+1]
							))
						)
					) ? 
						wr_mem_buf_finding_newest_mdf_s0_id[finding_newest_mdf_i][finding_newest_mdf_s1_j*4*2+7:finding_newest_mdf_s1_j*4*2+4]:
						wr_mem_buf_finding_newest_mdf_s0_id[finding_newest_mdf_i][finding_newest_mdf_s1_j*4*2+3:finding_newest_mdf_s1_j*4*2+0];
			end
			
			for(finding_newest_mdf_s2_j = 0;finding_newest_mdf_s2_j < 4;finding_newest_mdf_s2_j = finding_newest_mdf_s2_j + 1)
			begin:finding_newest_mdf_s2_blk
				assign wr_mem_buf_finding_newest_mdf_s2_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s2_j] = 
					wr_mem_buf_finding_newest_mdf_s1_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s2_j*2+0] | 
					wr_mem_buf_finding_newest_mdf_s1_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s2_j*2+1];
				assign wr_mem_buf_finding_newest_mdf_s2_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s2_j] = 
					(
						wr_mem_buf_finding_newest_mdf_s1_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s2_j*2+1] & 
						(
							(~wr_mem_buf_finding_newest_mdf_s1_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s2_j*2+0]) | 
							(~(
								wr_mem_buf_finding_newest_mdf_s1_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s2_j*2+0] ^ 
								wr_mem_buf_finding_newest_mdf_s1_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s2_j*2+1]
							))
						)
					) ? 
						wr_mem_buf_finding_newest_mdf_s1_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s2_j*2+1]:
						wr_mem_buf_finding_newest_mdf_s1_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s2_j*2+0];
				assign wr_mem_buf_finding_newest_mdf_s2_id[finding_newest_mdf_i][(finding_newest_mdf_s2_j+1)*4-1:finding_newest_mdf_s2_j*4] = 
					(
						wr_mem_buf_finding_newest_mdf_s1_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s2_j*2+1] & 
						(
							(~wr_mem_buf_finding_newest_mdf_s1_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s2_j*2+0]) | 
							(~(
								wr_mem_buf_finding_newest_mdf_s1_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s2_j*2+0] ^ 
								wr_mem_buf_finding_newest_mdf_s1_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s2_j*2+1]
							))
						)
					) ? 
						wr_mem_buf_finding_newest_mdf_s1_id[finding_newest_mdf_i][finding_newest_mdf_s2_j*4*2+7:finding_newest_mdf_s2_j*4*2+4]:
						wr_mem_buf_finding_newest_mdf_s1_id[finding_newest_mdf_i][finding_newest_mdf_s2_j*4*2+3:finding_newest_mdf_s2_j*4*2+0];
			end
			
			for(finding_newest_mdf_s3_j = 0;finding_newest_mdf_s3_j < 2;finding_newest_mdf_s3_j = finding_newest_mdf_s3_j + 1)
			begin:finding_newest_mdf_s3_blk
				assign wr_mem_buf_finding_newest_mdf_s3_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s3_j] = 
					wr_mem_buf_finding_newest_mdf_s2_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s3_j*2+0] | 
					wr_mem_buf_finding_newest_mdf_s2_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s3_j*2+1];
				assign wr_mem_buf_finding_newest_mdf_s3_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s3_j] = 
					(
						wr_mem_buf_finding_newest_mdf_s2_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s3_j*2+1] & 
						(
							(~wr_mem_buf_finding_newest_mdf_s2_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s3_j*2+0]) | 
							(~(
								wr_mem_buf_finding_newest_mdf_s2_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s3_j*2+0] ^ 
								wr_mem_buf_finding_newest_mdf_s2_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s3_j*2+1]
							))
						)
					) ? 
						wr_mem_buf_finding_newest_mdf_s2_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s3_j*2+1]:
						wr_mem_buf_finding_newest_mdf_s2_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s3_j*2+0];
				assign wr_mem_buf_finding_newest_mdf_s3_id[finding_newest_mdf_i][(finding_newest_mdf_s3_j+1)*4-1:finding_newest_mdf_s3_j*4] = 
					(
						wr_mem_buf_finding_newest_mdf_s2_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s3_j*2+1] & 
						(
							(~wr_mem_buf_finding_newest_mdf_s2_vld_vec[finding_newest_mdf_i][finding_newest_mdf_s3_j*2+0]) | 
							(~(
								wr_mem_buf_finding_newest_mdf_s2_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s3_j*2+0] ^ 
								wr_mem_buf_finding_newest_mdf_s2_age_tbit[finding_newest_mdf_i][finding_newest_mdf_s3_j*2+1]
							))
						)
					) ? 
						wr_mem_buf_finding_newest_mdf_s2_id[finding_newest_mdf_i][finding_newest_mdf_s3_j*4*2+7:finding_newest_mdf_s3_j*4*2+4]:
						wr_mem_buf_finding_newest_mdf_s2_id[finding_newest_mdf_i][finding_newest_mdf_s3_j*4*2+3:finding_newest_mdf_s3_j*4*2+0];
			end
			
			assign wr_mem_buf_finding_newest_mdf_s4_vld_vec[finding_newest_mdf_i] = 
				wr_mem_buf_finding_newest_mdf_s3_vld_vec[finding_newest_mdf_i][0] | 
				wr_mem_buf_finding_newest_mdf_s3_vld_vec[finding_newest_mdf_i][1];
			assign wr_mem_buf_finding_newest_mdf_s4_id[finding_newest_mdf_i] = 
				(
						wr_mem_buf_finding_newest_mdf_s3_vld_vec[finding_newest_mdf_i][1] & 
						(
							(~wr_mem_buf_finding_newest_mdf_s3_vld_vec[finding_newest_mdf_i][0]) | 
							(~(
								wr_mem_buf_finding_newest_mdf_s3_age_tbit[finding_newest_mdf_i][0] ^ 
								wr_mem_buf_finding_newest_mdf_s3_age_tbit[finding_newest_mdf_i][1]
							))
						)
					) ? 
						wr_mem_buf_finding_newest_mdf_s3_id[finding_newest_mdf_i][7:4]:
						wr_mem_buf_finding_newest_mdf_s3_id[finding_newest_mdf_i][3:0];
			
			always @(posedge aclk)
			begin
				if(on_initiate_wr_mem_buf_check)
					wr_mem_buf_check_newest_mdf_entry_id_foreach_byte[finding_newest_mdf_i] <= # SIM_DELAY 
						wr_mem_buf_finding_newest_mdf_s4_id[finding_newest_mdf_i];
			end
		end
	endgenerate
	
	/**
	外设访问总线控制
	
	外设访问是没有滞外传输(Outstanding)的,
		因为当1次外设访问未完成前, 无法确定它是否发生总线错误, 因此后续的外设访问不能够作推测执行, 比如:
		
		#0 ADD指令
		#1 B指令
		#2 LOAD指令(访问存储器)
		#3 ADD指令
		#4 STORE指令(访问存储器)
		#5 B指令
		#6 LOAD指令(访问外设)    ---> 前序指令(#0~5)无异常, 本指令(#6)没有除了总线错误之外的异常, 分支路径已确认, 外设访问事务可启动
		#7 ADD指令
		#8 STORE指令(访问外设)   ---> 指令(#6)未完成总线事务前, 指令(#8)不能启动外设访问事务, 因为无法确定指令(#6)是否发生总线错误
	**/
	// [启动外设访问事务]
	wire on_initiate_perph_trans; // 发起事务(标志)
	wire[clogb2(LSU_REQ_BUF_ENTRY_N-1):0] new_perph_trans_req_id; // 新事务的请求ID
	wire new_perph_trans_is_write_access; // 新事务是否为写访问
	// [进行中事务的信息]
	wire[31:0] perph_trans_aligned_addr; // 进行中事务的对齐地址
	wire perph_trans_is_write_access; // 进行中事务是否为写访问
	wire[31:0] perph_trans_wdata; // 进行中事务的写数据
	wire[3:0] perph_trans_wmask; // 进行中事务的写字节掩码
	wire[clogb2(LSU_REQ_BUF_ENTRY_N-1):0] perph_trans_req_id; // 进行中事务的请求ID
	// [外设访问进程]
	reg perph_trans_pending; // 事务等待(标志)
	wire on_complete_addr_setup_of_perph_trans; // 完成地址通道传输(指示)
	wire on_complete_wdata_sending_of_perph_trans; // 完成写数据通道传输(指示)
	wire on_complete_resp_recv_of_perph_trans; // 完成响应通道传输(指示)
	reg perph_trans_addr_setup; // 地址通道已传输(标志)
	reg perph_trans_wdata_sent; // 写数据通道已传输(标志)
	reg[clogb2(LSU_REQ_BUF_ENTRY_N-1):0] perph_trans_req_id_entended; // 延长的事务的请求ID
	// [外设访问超时限制]
	wire perph_trans_timeout_cnt_clr; // 超时计数器(清零使能)
	wire perph_trans_timeout_cnt_ce; // 超时计数器(计数使能)
	reg[clogb2(PERPH_ACCESS_TIMEOUT_TH):0] perph_trans_timeout_cnt; // 超时计数器
	reg perph_trans_timeout_flag; // 超时标志
	reg on_perph_trans_timeout; // 超时指示
	// [外设访问结果]
	wire on_get_perph_trans_res; // 得到外设访问结果(指示)
	wire[31:0] perph_trans_res_rdata; // 外设访问结果的读数据
	wire[1:0] perph_trans_res_err_code; // 外设访问结果的错误码
	
	// [AR通道]
	assign m_axi_perph_araddr = perph_trans_aligned_addr & (~32'd3);
	assign m_axi_perph_arburst = 2'b01;
	assign m_axi_perph_arlen = 8'd0;
	assign m_axi_perph_arsize = 3'b010;
	assign m_axi_perph_arvalid = 
		(~perph_trans_is_write_access) & 
		(
			(EN_LOW_LATENCY_PERPH_ACCESS == "false") ? 
				(perph_trans_pending & (~perph_trans_addr_setup)):
				(
					perph_trans_pending ? 
						(~perph_trans_addr_setup):
						on_initiate_perph_trans
				)
		);
	// [R通道]
	assign m_axi_perph_rready = 1'b1;
	// [AW通道]
	assign m_axi_perph_awaddr = perph_trans_aligned_addr & (~32'd3);
	assign m_axi_perph_awburst = 2'b01;
	assign m_axi_perph_awlen = 8'd0;
	assign m_axi_perph_awsize = 3'b010;
	assign m_axi_perph_awvalid = 
		perph_trans_is_write_access & 
		(
			(EN_LOW_LATENCY_PERPH_ACCESS == "false") ? 
				(perph_trans_pending & (~perph_trans_addr_setup)):
				(
					perph_trans_pending ? 
						(~perph_trans_addr_setup):
						on_initiate_perph_trans
				)
		);
	// [B通道]
	assign m_axi_perph_bready = 1'b1;
	// [W通道]
	assign m_axi_perph_wdata = perph_trans_wdata;
	assign m_axi_perph_wstrb = perph_trans_wmask;
	assign m_axi_perph_wlast = 1'b1;
	assign m_axi_perph_wvalid = 
		perph_trans_is_write_access & 
		(
			(EN_LOW_LATENCY_PERPH_ACCESS == "false") ? 
				(perph_trans_pending & (~perph_trans_wdata_sent)):
				(
					perph_trans_pending ? 
						(~perph_trans_wdata_sent):
						on_initiate_perph_trans
				)
		);
	
	assign perph_access_timeout = perph_trans_timeout_flag;
	
	assign perph_trans_req_id = 
		((EN_LOW_LATENCY_PERPH_ACCESS == "false") | perph_trans_pending) ? 
			perph_trans_req_id_entended:
			new_perph_trans_req_id;
	
	assign on_complete_addr_setup_of_perph_trans = 
		perph_trans_is_write_access ? 
			(m_axi_perph_awvalid & m_axi_perph_awready):
			(m_axi_perph_arvalid & m_axi_perph_arready);
	assign on_complete_wdata_sending_of_perph_trans = 
		perph_trans_is_write_access & 
		m_axi_perph_wvalid & m_axi_perph_wready;
	assign on_complete_resp_recv_of_perph_trans = 
		perph_trans_is_write_access ? 
			(m_axi_perph_bvalid & m_axi_perph_bready):
			(m_axi_perph_rvalid & m_axi_perph_rready);
	
	assign perph_trans_timeout_cnt_clr = 
		(PERPH_ACCESS_TIMEOUT_TH > 0) & 
		perph_trans_pending & on_complete_resp_recv_of_perph_trans;
	assign perph_trans_timeout_cnt_ce = 
		(PERPH_ACCESS_TIMEOUT_TH > 0) & 
		perph_trans_pending & (~on_complete_resp_recv_of_perph_trans);
	
	assign on_get_perph_trans_res = 
		((EN_LOW_LATENCY_PERPH_ACCESS == "false") | perph_trans_pending) ? 
			(on_perph_trans_timeout | on_complete_resp_recv_of_perph_trans):
			(on_initiate_perph_trans & on_complete_resp_recv_of_perph_trans);
	/*
	说明:
		对于写传输, m_axi_perph_bvalid必定在m_axi_perph_wvalid、m_axi_perph_wready、m_axi_perph_awvalid、m_axi_perph_awready
			有效之后才有效
		对于读传输, m_axi_perph_rvalid必定在m_axi_perph_arvalid、m_axi_perph_arready有效之后才有效
		
		因此, 直接使用m_axi_perph_rdata、m_axi_perph_bresp、m_axi_perph_rresp作为外设访问结果是安全的
	*/
	assign perph_trans_res_rdata = m_axi_perph_rdata;
	assign perph_trans_res_err_code = 
		on_perph_trans_timeout ? 
			DBUS_ACCESS_TIMEOUT:
			(
				(
					perph_trans_is_write_access ? 
						(m_axi_perph_bresp != AXI_RESP_OKAY):
						(m_axi_perph_rresp != AXI_RESP_OKAY)
				) ? 
					DBUS_ACCESS_BUS_ERR:
					DBUS_ACCESS_NORMAL
			);
	
	// 事务等待(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			perph_trans_pending <= 1'b0;
		else if(
			perph_trans_pending ? 
				(on_perph_trans_timeout | on_complete_resp_recv_of_perph_trans):
				(
					on_initiate_perph_trans & 
					((EN_LOW_LATENCY_PERPH_ACCESS == "false") | (~on_complete_resp_recv_of_perph_trans))
				)
		)
			perph_trans_pending <= # SIM_DELAY ~perph_trans_pending;
	end
	
	// 地址通道已传输(标志)
	always @(posedge aclk)
	begin
		if(
			perph_trans_pending ? 
				on_complete_addr_setup_of_perph_trans:
				(
					on_initiate_perph_trans & 
					((EN_LOW_LATENCY_PERPH_ACCESS == "false") | (~on_complete_resp_recv_of_perph_trans))
				)
		)
			perph_trans_addr_setup <= # SIM_DELAY 
				(~((EN_LOW_LATENCY_PERPH_ACCESS == "false") & (~perph_trans_pending))) & 
				on_complete_addr_setup_of_perph_trans;
	end
	// 写数据通道已传输(标志)
	always @(posedge aclk)
	begin
		if(
			perph_trans_pending ? 
				(perph_trans_is_write_access & on_complete_wdata_sending_of_perph_trans):
				(
					on_initiate_perph_trans & new_perph_trans_is_write_access & 
					((EN_LOW_LATENCY_PERPH_ACCESS == "false") | (~on_complete_resp_recv_of_perph_trans))
				)
		)
			perph_trans_wdata_sent <= # SIM_DELAY 
				(~((EN_LOW_LATENCY_PERPH_ACCESS == "false") & (~perph_trans_pending))) & 
				on_complete_wdata_sending_of_perph_trans;
	end
	
	// 延长的事务的请求ID
	always @(posedge aclk)
	begin
		if(
			(~perph_trans_pending) & 
			on_initiate_perph_trans & 
			((EN_LOW_LATENCY_PERPH_ACCESS == "false") | (~on_complete_resp_recv_of_perph_trans))
		)
			perph_trans_req_id_entended <= # SIM_DELAY new_perph_trans_req_id;
	end
	
	// 外设访问超时计数器
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			perph_trans_timeout_cnt <= 0;
		else if(
			(~perph_trans_timeout_flag) & 
			(perph_trans_timeout_cnt_clr | perph_trans_timeout_cnt_ce)
		)
			perph_trans_timeout_cnt <= # SIM_DELAY 
				perph_trans_timeout_cnt_clr ? 
					0:
					(perph_trans_timeout_cnt + 1);
	end
	// 外设访问超时标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			perph_trans_timeout_flag <= 1'b0;
		else if(~perph_trans_timeout_flag)
			perph_trans_timeout_flag <= # SIM_DELAY 
				perph_trans_timeout_cnt_ce & (perph_trans_timeout_cnt == (PERPH_ACCESS_TIMEOUT_TH - 1));
	end
	// 外设访问超时指示
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			on_perph_trans_timeout <= 1'b0;
		else if(
			on_perph_trans_timeout | 
			(perph_trans_timeout_cnt_ce & (perph_trans_timeout_cnt == (PERPH_ACCESS_TIMEOUT_TH - 1)))
		)
			on_perph_trans_timeout <= # SIM_DELAY ~on_perph_trans_timeout;
	end
	
	/** 外设访问请求缓存区 **/
	reg[clogb2(LSU_REQ_BUF_ENTRY_N):0] perph_access_req_table_req_id[0:1]; // 请求信息表存储内容(请求ID)
	reg[1:0] perph_access_req_table_wptr; // 写指针
	reg[1:0] perph_access_req_table_trans_ptr; // 总线事务指针
	wire[1:0] perph_access_req_table_wptr_nxt; // (最新的)写指针
	wire[1:0] perph_access_req_table_trans_ptr_nxt; // (最新的)总线事务指针
	reg perph_access_req_table_empty_flag; // 空标志
	reg perph_access_req_table_full_flag; // 满标志
	wire on_launch_or_ignore_perph_access; // 启动或忽略外设访问(指示)
	wire[clogb2(LSU_REQ_BUF_ENTRY_N):0] cur_launching_perph_access_req_id; // 当前待启动的外设访问事务的请求ID
	
	assign has_processing_perph_access_req = 
		(~perph_access_req_table_empty_flag) | perph_trans_pending;
	
	assign perph_access_req_table_wptr_nxt = 
		(s_req_valid & s_req_ready & (~s_req_ls_mem_access)) ? 
			(perph_access_req_table_wptr + 1'b1):
			perph_access_req_table_wptr;
	assign perph_access_req_table_trans_ptr_nxt = 
		on_launch_or_ignore_perph_access ? 
			(perph_access_req_table_trans_ptr + 1'b1):
			perph_access_req_table_trans_ptr;
	
	assign cur_launching_perph_access_req_id = perph_access_req_table_req_id[perph_access_req_table_trans_ptr[0]];
	
	// 外设访问请求信息表写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			perph_access_req_table_wptr <= 2'b00;
		else if(s_req_valid & s_req_ready & (~s_req_ls_mem_access))
			perph_access_req_table_wptr <= # SIM_DELAY 
				perph_access_req_table_wptr + 1'b1;
	end
	
	// 外设访问请求信息表总线事务指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			perph_access_req_table_trans_ptr <= 2'b00;
		else if(on_launch_or_ignore_perph_access)
			perph_access_req_table_trans_ptr <= # SIM_DELAY 
				perph_access_req_table_trans_ptr + 1'b1;
	end
	
	// 外设访问请求信息表空标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			perph_access_req_table_empty_flag <= 1'b1;
		else if(
			(s_req_valid & s_req_ready & (~s_req_ls_mem_access)) | 
			on_launch_or_ignore_perph_access
		)
			perph_access_req_table_empty_flag <= # SIM_DELAY 
				perph_access_req_table_wptr_nxt == perph_access_req_table_trans_ptr_nxt;
	end
	// 外设访问请求信息表满标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			perph_access_req_table_full_flag <= 1'b0;
		else if(
			(s_req_valid & s_req_ready & (~s_req_ls_mem_access)) | 
			on_launch_or_ignore_perph_access
		)
			perph_access_req_table_full_flag <= # SIM_DELAY 
				(perph_access_req_table_wptr_nxt[1] ^ perph_access_req_table_trans_ptr_nxt[1]) & 
				(~(perph_access_req_table_wptr_nxt[0] ^ perph_access_req_table_trans_ptr_nxt[0]));
	end
	
	/** 访存请求缓存区 **/
	// [访存地址非对齐判断]
	wire is_new_req_addr_unaligned; // 新请求的地址非对齐(标志)
	reg has_req_with_unaligned_addr; // 缓存里存在地址非对齐的条目(标志)
	// [写数据前处理]
	wire[31:0] store_din_pre_processed; // 经过前处理的写数据
	wire[3:0] store_wmask_pre_processed; // 经过前处理的字节有效掩码
	// [存储器读数据后处理]
	wire[2:0] rd_mem_ls_type_for_pos_prcs; // 待进行读数据后处理的访存类型
	wire[31:0] rd_mem_ls_addr_for_pos_prcs; // 待进行读数据后处理的访存地址
	wire[31:0] rd_mem_rdata_org_for_pos_prcs; // 原始的访存读数据
	wire[31:0] rd_mem_rdata_algn_for_pos_prcs; // 对齐后的访存读数据
	wire[31:0] rd_mem_rdata_final_for_pos_prcs; // 最终的访存读数据
	// [外设访问读数据后处理]
	wire[2:0] rd_perph_ls_type_for_pos_prcs; // 待进行读数据后处理的访存类型
	wire[31:0] rd_perph_ls_addr_for_pos_prcs; // 待进行读数据后处理的访存地址
	wire[31:0] rd_perph_rdata_org_for_pos_prcs; // 原始的访存读数据
	wire[31:0] rd_perph_rdata_algn_for_pos_prcs; // 对齐后的访存读数据
	wire[31:0] rd_perph_rdata_final_for_pos_prcs; // 最终的访存读数据
	// [缓存存储计数]
	reg[clogb2(LSU_REQ_BUF_ENTRY_N):0] vld_entry_n_in_req_buf; // 缓存有效条目数(计数器)
	reg req_buf_empty_flag; // 缓存空标志
	reg req_buf_full_flag; // 缓存满标志
	// [访存请求处理进程]
	reg[clogb2(LSU_REQ_BUF_ENTRY_N-1):0] ls_req_wptr; // 访存请求写指针
	reg[clogb2(LSU_REQ_BUF_ENTRY_N-1):0] ls_res_rptr; // 访存结果读指针
	wire on_retiring_ls_req; // 访存请求退休(指示)
	// [访存请求信息表]
	reg[LSU_REQ_BUF_ENTRY_N-1:0] ls_req_table_is_store; // 是否存储请求
	reg[LSU_REQ_BUF_ENTRY_N-1:0] ls_req_table_is_mem_access; // 是否访问存储器区域
	reg[2:0] ls_req_table_ls_type[0:LSU_REQ_BUF_ENTRY_N-1]; // 访存类型
	reg[4:0] ls_req_table_rd_id_for_ld[0:LSU_REQ_BUF_ENTRY_N-1]; // 用于加载的目标寄存器的索引
	reg[31:0] ls_req_table_ls_addr[0:LSU_REQ_BUF_ENTRY_N-1]; // 访存地址
	reg[31:0] ls_req_table_ls_data[0:LSU_REQ_BUF_ENTRY_N-1]; // 访存数据
	reg[31:0] ls_req_table_merging_data[0:LSU_REQ_BUF_ENTRY_N-1]; // 待合并数据
	reg[3:0] ls_req_table_byte_mask[0:LSU_REQ_BUF_ENTRY_N-1]; // 字节掩码
	reg[INST_ID_WIDTH-1:0] ls_req_table_inst_id[0:LSU_REQ_BUF_ENTRY_N-1]; // 指令ID
	reg[1:0] ls_req_table_err_code[0:LSU_REQ_BUF_ENTRY_N-1]; // 错误码
	reg[LSU_REQ_BUF_ENTRY_N-1:0] ls_req_table_vld_flag; // 有效标志
	reg[LSU_REQ_BUF_ENTRY_N-1:0] ls_req_table_permitted_flag; // 许可标志
	reg[LSU_REQ_BUF_ENTRY_N-1:0] ls_req_table_cancel_flag; // 取消标志
	reg[LSU_REQ_BUF_ENTRY_N-1:0] ls_req_table_completed_flag; // 完成标志
	
	assign s_req_ready = 
		(~req_buf_full_flag) & (~has_req_with_unaligned_addr) & 
		(
			s_req_ls_mem_access ? 
				(
					s_req_ls_sel ? 
						is_allowed_to_submit_new_wr_mem_req:
						is_allowed_to_submit_new_rd_mem_req
				):
				(~perph_access_req_table_full_flag)
		);
	
	assign m_resp_ls_sel = ls_req_table_is_store[ls_res_rptr];
	assign m_resp_rd_id_for_ld = ls_req_table_rd_id_for_ld[ls_res_rptr];
	assign m_resp_dout_ls_addr = 
		(ls_req_table_err_code[ls_res_rptr] == DBUS_ACCESS_NORMAL) ? 
			ls_req_table_ls_data[ls_res_rptr]:
			ls_req_table_ls_addr[ls_res_rptr];
	assign m_resp_err = ls_req_table_err_code[ls_res_rptr];
	assign m_resp_lsu_inst_id = ls_req_table_inst_id[ls_res_rptr];
	assign m_resp_valid = 
		ls_req_table_vld_flag[ls_res_rptr] & (~ls_req_table_cancel_flag[ls_res_rptr]) & ls_req_table_completed_flag[ls_res_rptr];
	
	assign on_launch_or_ignore_perph_access = 
		(~perph_access_req_table_empty_flag) & 
		ls_req_table_vld_flag[cur_launching_perph_access_req_id] & 
		(
			ls_req_table_cancel_flag[cur_launching_perph_access_req_id] | 
			(
				ls_req_table_permitted_flag[cur_launching_perph_access_req_id] & 
				(~perph_trans_pending)
			)
		);
	
	assign on_submit_new_wr_mem_req = s_req_valid & s_req_ready & s_req_ls_mem_access & s_req_ls_sel & (~is_new_req_addr_unaligned);
	assign aligned_addr_of_new_wr_mem_req = s_req_ls_addr & (~32'd3);
	assign wdata_of_new_wr_mem_req = store_din_pre_processed;
	assign wmask_of_new_wr_mem_req = store_wmask_pre_processed;
	assign inst_id_of_new_wr_mem_req = s_req_lsu_inst_id;
	
	assign on_initiate_rd_mem_trans = s_req_valid & s_req_ready & s_req_ls_mem_access & (~s_req_ls_sel) & (~is_new_req_addr_unaligned);
	assign new_rd_mem_trans_org_addr = s_req_ls_addr & (~32'd3);
	assign new_rd_mem_trans_req_id = ls_req_wptr;
	
	assign on_initiate_perph_trans = 
		(~perph_access_req_table_empty_flag) & 
		ls_req_table_vld_flag[cur_launching_perph_access_req_id] & 
		(~ls_req_table_cancel_flag[cur_launching_perph_access_req_id]) & 
		ls_req_table_permitted_flag[cur_launching_perph_access_req_id];
	assign new_perph_trans_req_id = cur_launching_perph_access_req_id;
	assign new_perph_trans_is_write_access = ls_req_table_is_store[cur_launching_perph_access_req_id];
	assign perph_trans_aligned_addr = ls_req_table_ls_addr[perph_trans_req_id] & (~32'd3);
	assign perph_trans_is_write_access = ls_req_table_is_store[perph_trans_req_id];
	assign perph_trans_wdata = ls_req_table_ls_data[perph_trans_req_id];
	assign perph_trans_wmask = ls_req_table_byte_mask[perph_trans_req_id];
	
	assign is_new_req_addr_unaligned = 
		~(
			(s_req_ls_type == LS_TYPE_BYTE) | (s_req_ls_type == LS_TYPE_BYTE_UNSIGNED) | 
			(((s_req_ls_type == LS_TYPE_HALF_WORD) | (s_req_ls_type == LS_TYPE_HALF_WORD_UNSIGNED)) & (~s_req_ls_addr[0])) | // 半字对齐
			((s_req_ls_type == LS_TYPE_WORD) & (s_req_ls_addr[1:0] == 2'b00)) // 字对齐
		);
	
	assign store_din_pre_processed = 
		({32{s_req_ls_type == LS_TYPE_BYTE}} & {4{s_req_ls_din[7:0]}}) | 
		({32{s_req_ls_type == LS_TYPE_HALF_WORD}} & {2{s_req_ls_din[15:0]}}) | 
		({32{s_req_ls_type == LS_TYPE_WORD}} & s_req_ls_din);
	assign store_wmask_pre_processed = 
		({4{s_req_ls_type == LS_TYPE_BYTE}} & (4'b0001 << s_req_ls_addr[1:0])) | 
		({4{s_req_ls_type == LS_TYPE_HALF_WORD}} & (4'b0011 << {s_req_ls_addr[1], 1'b0})) | 
		({4{s_req_ls_type == LS_TYPE_WORD}} & 4'b1111);
	
	assign rd_mem_ls_type_for_pos_prcs = ls_req_table_ls_type[req_id_of_completed_rd_mem_trans_w];
	assign rd_mem_ls_addr_for_pos_prcs = ls_req_table_ls_addr[req_id_of_completed_rd_mem_trans_w];
	assign rd_mem_rdata_org_for_pos_prcs[31:24] = 
		(
			(
				(EN_LOW_LATENCY_RD_MEM_ACCESS >= 2) & 
				on_return_wr_mem_buf_check_res & (req_id_of_wr_mem_buf_check_res == req_id_of_completed_rd_mem_trans_w)
			) ? 
				merging_mask_of_wr_mem_buf_check_res[3]:
				ls_req_table_byte_mask[req_id_of_completed_rd_mem_trans_w][3]
		) ? 
			(
				(
					(EN_LOW_LATENCY_RD_MEM_ACCESS >= 2) & 
					on_return_wr_mem_buf_check_res & (req_id_of_wr_mem_buf_check_res == req_id_of_completed_rd_mem_trans_w)
				) ? 
					merging_data_of_wr_mem_buf_check_res[31:24]:
					ls_req_table_merging_data[req_id_of_completed_rd_mem_trans_w][31:24]
			):
			rdata_of_completed_rd_mem_trans_w[31:24];
	assign rd_mem_rdata_org_for_pos_prcs[23:16] = 
		(
			(
				(EN_LOW_LATENCY_RD_MEM_ACCESS >= 2) & 
				on_return_wr_mem_buf_check_res & (req_id_of_wr_mem_buf_check_res == req_id_of_completed_rd_mem_trans_w)
			) ? 
				merging_mask_of_wr_mem_buf_check_res[2]:
				ls_req_table_byte_mask[req_id_of_completed_rd_mem_trans_w][2]
		) ? 
			(
				(
					(EN_LOW_LATENCY_RD_MEM_ACCESS >= 2) & 
					on_return_wr_mem_buf_check_res & (req_id_of_wr_mem_buf_check_res == req_id_of_completed_rd_mem_trans_w)
				) ? 
					merging_data_of_wr_mem_buf_check_res[23:16]:
					ls_req_table_merging_data[req_id_of_completed_rd_mem_trans_w][23:16]
			):
			rdata_of_completed_rd_mem_trans_w[23:16];
	assign rd_mem_rdata_org_for_pos_prcs[15:8] = 
		(
			(
				(EN_LOW_LATENCY_RD_MEM_ACCESS >= 2) & 
				on_return_wr_mem_buf_check_res & (req_id_of_wr_mem_buf_check_res == req_id_of_completed_rd_mem_trans_w)
			) ? 
				merging_mask_of_wr_mem_buf_check_res[1]:
				ls_req_table_byte_mask[req_id_of_completed_rd_mem_trans_w][1]
		) ? 
			(
				(
					(EN_LOW_LATENCY_RD_MEM_ACCESS >= 2) & 
					on_return_wr_mem_buf_check_res & (req_id_of_wr_mem_buf_check_res == req_id_of_completed_rd_mem_trans_w)
				) ? 
					merging_data_of_wr_mem_buf_check_res[15:8]:
					ls_req_table_merging_data[req_id_of_completed_rd_mem_trans_w][15:8]
			):
			rdata_of_completed_rd_mem_trans_w[15:8];
	assign rd_mem_rdata_org_for_pos_prcs[7:0] = 
		(
			(
				(EN_LOW_LATENCY_RD_MEM_ACCESS >= 2) & 
				on_return_wr_mem_buf_check_res & (req_id_of_wr_mem_buf_check_res == req_id_of_completed_rd_mem_trans_w)
			) ? 
				merging_mask_of_wr_mem_buf_check_res[0]:
				ls_req_table_byte_mask[req_id_of_completed_rd_mem_trans_w][0]
		) ? 
			(
				(
					(EN_LOW_LATENCY_RD_MEM_ACCESS >= 2) & 
					on_return_wr_mem_buf_check_res & (req_id_of_wr_mem_buf_check_res == req_id_of_completed_rd_mem_trans_w)
				) ? 
					merging_data_of_wr_mem_buf_check_res[7:0]:
					ls_req_table_merging_data[req_id_of_completed_rd_mem_trans_w][7:0]
			):
			rdata_of_completed_rd_mem_trans_w[7:0];
	assign rd_mem_rdata_algn_for_pos_prcs = 
		rd_mem_rdata_org_for_pos_prcs >> {rd_mem_ls_addr_for_pos_prcs[1:0], 3'b000};
	assign rd_mem_rdata_final_for_pos_prcs = 
		({32{rd_mem_ls_type_for_pos_prcs == LS_TYPE_BYTE}} & {{24{rd_mem_rdata_algn_for_pos_prcs[7]}}, rd_mem_rdata_algn_for_pos_prcs[7:0]}) | 
		({32{rd_mem_ls_type_for_pos_prcs == LS_TYPE_HALF_WORD}} & {{16{rd_mem_rdata_algn_for_pos_prcs[15]}}, rd_mem_rdata_algn_for_pos_prcs[15:0]}) | 
		({32{rd_mem_ls_type_for_pos_prcs == LS_TYPE_WORD}} & rd_mem_rdata_algn_for_pos_prcs[31:0]) | 
		({32{rd_mem_ls_type_for_pos_prcs == LS_TYPE_BYTE_UNSIGNED}} & {24'd0, rd_mem_rdata_algn_for_pos_prcs[7:0]}) | 
		({32{rd_mem_ls_type_for_pos_prcs == LS_TYPE_HALF_WORD_UNSIGNED}} & {16'd0, rd_mem_rdata_algn_for_pos_prcs[15:0]});
	
	assign rd_perph_ls_type_for_pos_prcs = ls_req_table_ls_type[perph_trans_req_id];
	assign rd_perph_ls_addr_for_pos_prcs = ls_req_table_ls_addr[perph_trans_req_id];
	assign rd_perph_rdata_org_for_pos_prcs = perph_trans_res_rdata;
	assign rd_perph_rdata_algn_for_pos_prcs = 
		rd_perph_rdata_org_for_pos_prcs >> {rd_perph_ls_addr_for_pos_prcs[1:0], 3'b000};
	assign rd_perph_rdata_final_for_pos_prcs = 
		({32{rd_perph_ls_type_for_pos_prcs == LS_TYPE_BYTE}} & {{24{rd_perph_rdata_algn_for_pos_prcs[7]}}, rd_perph_rdata_algn_for_pos_prcs[7:0]}) | 
		({32{rd_perph_ls_type_for_pos_prcs == LS_TYPE_HALF_WORD}} & {{16{rd_perph_rdata_algn_for_pos_prcs[15]}}, rd_perph_rdata_algn_for_pos_prcs[15:0]}) | 
		({32{rd_perph_ls_type_for_pos_prcs == LS_TYPE_WORD}} & rd_perph_rdata_algn_for_pos_prcs[31:0]) | 
		({32{rd_perph_ls_type_for_pos_prcs == LS_TYPE_BYTE_UNSIGNED}} & {24'd0, rd_perph_rdata_algn_for_pos_prcs[7:0]}) | 
		({32{rd_perph_ls_type_for_pos_prcs == LS_TYPE_HALF_WORD_UNSIGNED}} & {16'd0, rd_perph_rdata_algn_for_pos_prcs[15:0]});
	
	assign on_retiring_ls_req = 
		(m_resp_valid & m_resp_ready) | 
		(ls_req_table_vld_flag[ls_res_rptr] & ls_req_table_cancel_flag[ls_res_rptr]);
	
	// 外设访问请求信息表存储内容(请求ID)
	always @(posedge aclk)
	begin
		if(s_req_valid & s_req_ready & (~s_req_ls_mem_access) & (~perph_access_req_table_wptr[0]))
			perph_access_req_table_req_id[0] <= # SIM_DELAY ls_req_wptr;
	end
	always @(posedge aclk)
	begin
		if(s_req_valid & s_req_ready & (~s_req_ls_mem_access) & perph_access_req_table_wptr[0])
			perph_access_req_table_req_id[1] <= # SIM_DELAY ls_req_wptr;
	end
	
	// 访存请求缓存里存在地址非对齐的条目(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			has_req_with_unaligned_addr <= 1'b0;
		else if(
			has_req_with_unaligned_addr ? 
				(on_retiring_ls_req & (m_resp_err == DBUS_ACCESS_LS_UNALIGNED)):
				(s_req_valid & s_req_ready & is_new_req_addr_unaligned)
		)
			has_req_with_unaligned_addr <= # SIM_DELAY ~has_req_with_unaligned_addr;
	end
	
	// 访存请求缓存有效条目数(计数器)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			vld_entry_n_in_req_buf <= 0;
		else if((s_req_valid & s_req_ready) ^ on_retiring_ls_req)
			vld_entry_n_in_req_buf <= # SIM_DELAY 
				on_retiring_ls_req ? 
					(vld_entry_n_in_req_buf - 1):
					(vld_entry_n_in_req_buf + 1);
	end
	// 访存请求缓存空标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			req_buf_empty_flag <= 1'b1;
		else if((s_req_valid & s_req_ready) ^ on_retiring_ls_req)
			req_buf_empty_flag <= # SIM_DELAY 
				on_retiring_ls_req & (vld_entry_n_in_req_buf == 1);
	end
	// 访存请求缓存满标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			req_buf_full_flag <= 1'b0;
		else if((s_req_valid & s_req_ready) ^ on_retiring_ls_req)
			req_buf_full_flag <= # SIM_DELAY 
				(~on_retiring_ls_req) & (vld_entry_n_in_req_buf == (LSU_REQ_BUF_ENTRY_N - 1));
	end
	
	// 访存请求写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			ls_req_wptr <= 0;
		else if(s_req_valid & s_req_ready)
			ls_req_wptr <= # SIM_DELAY 
				(ls_req_wptr == (LSU_REQ_BUF_ENTRY_N-1)) ? 
					0:
					(ls_req_wptr + 1);
	end
	// 访存结果读指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			ls_res_rptr <= 0;
		else if(on_retiring_ls_req)
			ls_res_rptr <= # SIM_DELAY 
				(ls_res_rptr == (LSU_REQ_BUF_ENTRY_N-1)) ? 
					0:
					(ls_res_rptr + 1);
	end
	
	/*
	访存请求信息表的存储内容(
		是否存储请求, 是否访问存储器区域, 访存类型, 用于加载的目标寄存器的索引, 访存地址, 指令ID,
		字节掩码, 错误码, 访存数据, 待合并数据
	)
	访存请求信息表的标志(有效标志, 许可标志, 取消标志, 完成标志)
	*/
	genvar ls_req_table_entry_i;
	generate
		for(ls_req_table_entry_i = 0;ls_req_table_entry_i < LSU_REQ_BUF_ENTRY_N;ls_req_table_entry_i = ls_req_table_entry_i + 1)
		begin:ls_req_table_blk
			always @(posedge aclk)
			begin
				if(s_req_valid & s_req_ready & (ls_req_wptr == ls_req_table_entry_i))
				begin
					ls_req_table_is_store[ls_req_table_entry_i] <= # SIM_DELAY s_req_ls_sel;
					ls_req_table_is_mem_access[ls_req_table_entry_i] <= # SIM_DELAY s_req_ls_mem_access;
					ls_req_table_ls_type[ls_req_table_entry_i] <= # SIM_DELAY s_req_ls_type;
					ls_req_table_rd_id_for_ld[ls_req_table_entry_i] <= # SIM_DELAY s_req_rd_id_for_ld;
					ls_req_table_ls_addr[ls_req_table_entry_i] <= # SIM_DELAY s_req_ls_addr;
					ls_req_table_inst_id[ls_req_table_entry_i] <= # SIM_DELAY s_req_lsu_inst_id;
				end
			end
			
			always @(posedge aclk)
			begin
				if(
					// 接受存储请求
					(s_req_valid & s_req_ready & s_req_ls_sel & (ls_req_wptr == ls_req_table_entry_i)) | 
					// 返回写存储器缓存检查结果
					(on_return_wr_mem_buf_check_res & (req_id_of_wr_mem_buf_check_res == ls_req_table_entry_i))
				)
					ls_req_table_byte_mask[ls_req_table_entry_i] <= # SIM_DELAY 
						ls_req_table_vld_flag[ls_req_table_entry_i] ? 
							merging_mask_of_wr_mem_buf_check_res:
							store_wmask_pre_processed;
			end
			
			always @(posedge aclk)
			begin
				if(
					// 接受地址非对齐的请求或写存储器请求
					(
						s_req_valid & s_req_ready & 
						(is_new_req_addr_unaligned | (s_req_ls_mem_access & s_req_ls_sel)) & 
						(ls_req_wptr == ls_req_table_entry_i)
					) | 
					// 得到读存储器访问结果
					(on_upd_req_entry_of_rd_mem_trans_w & (req_id_of_completed_rd_mem_trans_w == ls_req_table_entry_i)) | 
					// 得到外设访问结果
					(on_get_perph_trans_res & (perph_trans_req_id == ls_req_table_entry_i))
				)
					ls_req_table_err_code[ls_req_table_entry_i] <= # SIM_DELAY 
						ls_req_table_vld_flag[ls_req_table_entry_i] ? 
							(
								ls_req_table_is_mem_access[ls_req_table_entry_i] ? 
									err_code_of_completed_rd_mem_trans_w:
									perph_trans_res_err_code
							):
							(
								is_new_req_addr_unaligned ? 
									DBUS_ACCESS_LS_UNALIGNED:
									DBUS_ACCESS_NORMAL
							);
			end
			
			always @(posedge aclk)
			begin
				if(
					// 接受存储请求
					(s_req_valid & s_req_ready & s_req_ls_sel & (ls_req_wptr == ls_req_table_entry_i)) | 
					// 得到外设读访问结果
					(
						on_get_perph_trans_res & (~ls_req_table_is_store[ls_req_table_entry_i]) & 
						(perph_trans_req_id == ls_req_table_entry_i)
					) | 
					// 得到读存储器访问结果
					(on_upd_req_entry_of_rd_mem_trans_w & (req_id_of_completed_rd_mem_trans_w == ls_req_table_entry_i))
				)
					ls_req_table_ls_data[ls_req_table_entry_i] <= # SIM_DELAY 
						ls_req_table_vld_flag[ls_req_table_entry_i] ? 
							(
								ls_req_table_is_mem_access[ls_req_table_entry_i] ? 
									rd_mem_rdata_final_for_pos_prcs:
									rd_perph_rdata_final_for_pos_prcs
							):
							store_din_pre_processed;
			end
			
			always @(posedge aclk)
			begin
				if(on_return_wr_mem_buf_check_res & (req_id_of_wr_mem_buf_check_res == ls_req_table_entry_i)) // 返回写存储器缓存检查结果
					ls_req_table_merging_data[ls_req_table_entry_i] <= # SIM_DELAY 
						merging_data_of_wr_mem_buf_check_res;
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					ls_req_table_vld_flag[ls_req_table_entry_i] <= 1'b0;
				else if(
					(s_req_valid & s_req_ready & (ls_req_wptr == ls_req_table_entry_i)) | 
					(on_retiring_ls_req & (ls_res_rptr == ls_req_table_entry_i))
				)
					ls_req_table_vld_flag[ls_req_table_entry_i] <= # SIM_DELAY 
						s_req_valid & s_req_ready & (ls_req_wptr == ls_req_table_entry_i);
			end
			
			// 说明: 仅记录外设访问请求的许可情况
			always @(posedge aclk)
			begin
				if(
					(s_req_valid & s_req_ready & (~s_req_ls_mem_access) & (ls_req_wptr == ls_req_table_entry_i)) | 
					(
						ls_req_table_vld_flag[ls_req_table_entry_i] & (~ls_req_table_is_mem_access[ls_req_table_entry_i]) & 
						(~ls_req_table_permitted_flag[ls_req_table_entry_i]) & 
						(perph_access_permitted_flag & (init_perph_bus_tr_ls_inst_tid == ls_req_table_inst_id[ls_req_table_entry_i]))
					)
				)
					ls_req_table_permitted_flag[ls_req_table_entry_i] <= # SIM_DELAY 
						~(s_req_valid & s_req_ready & (~s_req_ls_mem_access) & (ls_req_wptr == ls_req_table_entry_i));
			end
			
			// 说明: 仅取消未许可的外设访问请求
			always @(posedge aclk)
			begin
				if(
					(s_req_valid & s_req_ready & (ls_req_wptr == ls_req_table_entry_i)) | 
					(
						cancel_subseq_perph_access & 
						ls_req_table_vld_flag[ls_req_table_entry_i] & (~ls_req_table_is_mem_access[ls_req_table_entry_i]) & 
						(~ls_req_table_permitted_flag[ls_req_table_entry_i]) & 
						(~(perph_access_permitted_flag & (init_perph_bus_tr_ls_inst_tid == ls_req_table_inst_id[ls_req_table_entry_i])))
					)
				)
					ls_req_table_cancel_flag[ls_req_table_entry_i] <= # SIM_DELAY 
						~(
							s_req_valid & s_req_ready & (ls_req_wptr == ls_req_table_entry_i) & 
							((~cancel_subseq_perph_access) | s_req_ls_mem_access)
						);
			end
			
			always @(posedge aclk)
			begin
				if(
					// 接受访存请求
					(s_req_valid & s_req_ready & (ls_req_wptr == ls_req_table_entry_i)) | 
					// 得到读存储器访问结果
					(on_upd_req_entry_of_rd_mem_trans_w & (req_id_of_completed_rd_mem_trans_w == ls_req_table_entry_i)) | 
					// 得到外设访问结果
					(on_get_perph_trans_res & (perph_trans_req_id == ls_req_table_entry_i))
				)
					ls_req_table_completed_flag[ls_req_table_entry_i] <= # SIM_DELAY 
						ls_req_table_vld_flag[ls_req_table_entry_i] | 
						(is_new_req_addr_unaligned | (s_req_ls_mem_access & s_req_ls_sel));
			end
		end
	endgenerate
	
	/** 读存储器结果快速旁路 **/
	wire[3:0] instant_rd_mem_modified_byte_mask;
	wire[31:0] instant_rd_mem_modified_byte_data;
	wire[31:0] instant_rd_mem_res_algn;
	wire[31:0] instant_rd_mem_res_final;
	wire[31:0] instant_rd_mem_res_merged_org;
	wire[31:0] instant_rd_mem_res_merged_algn;
	wire[31:0] instant_rd_mem_res_merged_final;
	reg on_get_instant_rd_mem_res_s1_r;
	reg[INST_ID_WIDTH-1:0] inst_id_of_instant_rd_mem_res_gotten_s1_r;
	reg[31:0] data_of_instant_rd_mem_res_gotten_s1_r;
	
	assign on_get_instant_rd_mem_res_s0 = 
		on_complete_rd_mem_trans & 
		(~(|instant_rd_mem_modified_byte_mask)); // 说明: 为了降低组合逻辑延迟, 只将写存储器缓存检查无冲突的读存储器结果旁路出去
	assign inst_id_of_instant_rd_mem_res_gotten_s0 = 
		ls_req_table_inst_id[req_id_of_completed_rd_mem_trans_w];
	assign data_of_instant_rd_mem_res_gotten_s0 = 
		instant_rd_mem_res_final;
	
	assign on_get_instant_rd_mem_res_s1 = on_get_instant_rd_mem_res_s1_r;
	assign inst_id_of_instant_rd_mem_res_gotten_s1 = inst_id_of_instant_rd_mem_res_gotten_s1_r;
	assign data_of_instant_rd_mem_res_gotten_s1 = data_of_instant_rd_mem_res_gotten_s1_r;
	
	assign instant_rd_mem_modified_byte_mask = 
		(
			(EN_LOW_LATENCY_RD_MEM_ACCESS >= 2) & 
			on_return_wr_mem_buf_check_res & (req_id_of_wr_mem_buf_check_res == req_id_of_completed_rd_mem_trans_w)
		) ? 
			merging_mask_of_wr_mem_buf_check_res:
			ls_req_table_byte_mask[req_id_of_completed_rd_mem_trans_w];
	assign instant_rd_mem_modified_byte_data = 
		(
			(EN_LOW_LATENCY_RD_MEM_ACCESS >= 2) & 
			on_return_wr_mem_buf_check_res & (req_id_of_wr_mem_buf_check_res == req_id_of_completed_rd_mem_trans_w)
		) ? 
			merging_data_of_wr_mem_buf_check_res:
			ls_req_table_merging_data[req_id_of_completed_rd_mem_trans_w];
	
	assign instant_rd_mem_res_algn = 
		rdata_of_completed_rd_mem_trans_w >> {rd_mem_ls_addr_for_pos_prcs[1:0], 3'b000};
	assign instant_rd_mem_res_final = 
		({32{rd_mem_ls_type_for_pos_prcs == LS_TYPE_BYTE}} & {{24{instant_rd_mem_res_algn[7]}}, instant_rd_mem_res_algn[7:0]}) | 
		({32{rd_mem_ls_type_for_pos_prcs == LS_TYPE_HALF_WORD}} & {{16{instant_rd_mem_res_algn[15]}}, instant_rd_mem_res_algn[15:0]}) | 
		({32{rd_mem_ls_type_for_pos_prcs == LS_TYPE_WORD}} & instant_rd_mem_res_algn[31:0]) | 
		({32{rd_mem_ls_type_for_pos_prcs == LS_TYPE_BYTE_UNSIGNED}} & {24'd0, instant_rd_mem_res_algn[7:0]}) | 
		({32{rd_mem_ls_type_for_pos_prcs == LS_TYPE_HALF_WORD_UNSIGNED}} & {16'd0, instant_rd_mem_res_algn[15:0]});
	
	assign instant_rd_mem_res_merged_org[31:24] = 
		instant_rd_mem_modified_byte_mask[3] ? 
			instant_rd_mem_modified_byte_data[31:24]:
			rdata_of_completed_rd_mem_trans_w[31:24];
	assign instant_rd_mem_res_merged_org[23:16] = 
		instant_rd_mem_modified_byte_mask[2] ? 
			instant_rd_mem_modified_byte_data[23:16]:
			rdata_of_completed_rd_mem_trans_w[23:16];
	assign instant_rd_mem_res_merged_org[15:8] = 
		instant_rd_mem_modified_byte_mask[1] ? 
			instant_rd_mem_modified_byte_data[15:8]:
			rdata_of_completed_rd_mem_trans_w[15:8];
	assign instant_rd_mem_res_merged_org[7:0] = 
		instant_rd_mem_modified_byte_mask[0] ? 
			instant_rd_mem_modified_byte_data[7:0]:
			rdata_of_completed_rd_mem_trans_w[7:0];
	
	assign instant_rd_mem_res_merged_algn = 
		instant_rd_mem_res_merged_org >> {rd_mem_ls_addr_for_pos_prcs[1:0], 3'b000};
	assign instant_rd_mem_res_merged_final = 
		({32{rd_mem_ls_type_for_pos_prcs == LS_TYPE_BYTE}} & {{24{instant_rd_mem_res_merged_algn[7]}}, instant_rd_mem_res_merged_algn[7:0]}) | 
		({32{rd_mem_ls_type_for_pos_prcs == LS_TYPE_HALF_WORD}} & {{16{instant_rd_mem_res_merged_algn[15]}}, instant_rd_mem_res_merged_algn[15:0]}) | 
		({32{rd_mem_ls_type_for_pos_prcs == LS_TYPE_WORD}} & instant_rd_mem_res_merged_algn[31:0]) | 
		({32{rd_mem_ls_type_for_pos_prcs == LS_TYPE_BYTE_UNSIGNED}} & {24'd0, instant_rd_mem_res_merged_algn[7:0]}) | 
		({32{rd_mem_ls_type_for_pos_prcs == LS_TYPE_HALF_WORD_UNSIGNED}} & {16'd0, instant_rd_mem_res_merged_algn[15:0]});
	
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			on_get_instant_rd_mem_res_s1_r <= 1'b0;
		else
			on_get_instant_rd_mem_res_s1_r <= # SIM_DELAY 
				on_complete_rd_mem_trans;
	end
	
	always @(posedge aclk)
	begin
		if(on_complete_rd_mem_trans)
		begin
			inst_id_of_instant_rd_mem_res_gotten_s1_r <= # SIM_DELAY 
				ls_req_table_inst_id[req_id_of_completed_rd_mem_trans_w];
			
			data_of_instant_rd_mem_res_gotten_s1_r <= # SIM_DELAY 
				instant_rd_mem_res_merged_final;
		end
	end
	
endmodule
