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
接受访存请求, 驱动数据ICB主机, 得到访存结果
若访存请求允许提前执行, 则在它与前序访存请求不产生地址冲突时自动许可;若访存请求不允许提前执行, 则需要等待外部给出(匹配当前请求的指令编号的)访存许可
当接受访存请求时, 向ROB发出广播

最低的访存时延为5clk: 接受访存请求 -> 许可 -> 数据ICB主机命令通道握手 -> 数据ICB主机响应通道握手 -> 得到访存结果

注意：
至少要在接受访存请求项后的1clk, 外部才能给出对应请求项的访存许可, 否则该许可没有作用

协议:
ICB MASTER

作者: 陈家耀
日期: 2025/09/18
********************************************************************/


module panda_risc_v_lsu #(
	parameter integer INST_ID_WIDTH = 4, // 指令编号的位宽
	parameter integer DBUS_ACCESS_TIMEOUT_TH = 16, // 数据总线访问超时周期数(0 -> 不设超时 | 正整数)
	parameter integer LS_BUF_ENTRY_N = 8, // 访存缓存区条目数(4 | 8 | 16)
	parameter integer DBUS_OUTSTANDING_N = 4, // 数据总线可滞外传输个数(必须<=LS_BUF_ENTRY_N)
    parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// 访存许可
	input wire ls_allow_vld,
	input wire[INST_ID_WIDTH-1:0] ls_allow_inst_id, // 指令编号
	
	// 接受访存请求阶段ROB记录广播
	output wire rob_ls_start_bdcst_vld, // 广播有效
	output wire[INST_ID_WIDTH-1:0] rob_ls_start_bdcst_tid, // 指令ID
	
	// 访存请求
	input wire s_req_ls_sel, // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	input wire[2:0] s_req_ls_type, // 访存类型
	input wire[4:0] s_req_rd_id_for_ld, // 用于加载的目标寄存器的索引
	input wire[31:0] s_req_ls_addr, // 访存地址
	input wire[31:0] s_req_ls_din, // 写数据
	input wire[INST_ID_WIDTH-1:0] s_req_lsu_inst_id, // 指令编号
	input wire s_req_pre_exec_prmt, // 是否允许提前执行
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
    
    // 数据ICB主机
	// [命令通道]
	output wire[31:0] m_icb_cmd_addr,
	output wire m_icb_cmd_read,
	output wire[31:0] m_icb_cmd_wdata,
	output wire[3:0] m_icb_cmd_wmask,
	output wire m_icb_cmd_valid,
	input wire m_icb_cmd_ready,
	// [响应通道]
	input wire[31:0] m_icb_rsp_rdata,
	input wire m_icb_rsp_err,
	input wire m_icb_rsp_valid,
	output wire m_icb_rsp_ready,
	
	// 数据总线访问超时标志
	output wire dbus_timeout
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
	
	/** 接受访存请求阶段ROB记录广播 **/
	assign rob_ls_start_bdcst_vld = s_req_valid & s_req_ready;
	assign rob_ls_start_bdcst_tid = s_req_lsu_inst_id;
	
	/** 访存请求前处理 **/
	wire[2:0] ls_type_for_pre_prcs; // 访存类型
	wire[31:0] ls_addr_for_pre_prcs; // 访存地址
	wire[31:0] ls_din_for_pre_prcs; // 写数据
	wire ls_addr_aligned_in_pre_prcs; // 访存地址对齐(标志)
	wire[31:0] store_din_in_pre_prcs; // 用于写存储映射的数据
	wire[3:0] store_wmask_in_pre_prcs; // 用于写存储映射的字节有效掩码
	
	assign ls_type_for_pre_prcs = s_req_ls_type;
	assign ls_addr_for_pre_prcs = s_req_ls_addr;
	assign ls_din_for_pre_prcs = s_req_ls_din;
	
	assign ls_addr_aligned_in_pre_prcs = 
		(ls_type_for_pre_prcs == LS_TYPE_BYTE) | 
		(ls_type_for_pre_prcs == LS_TYPE_BYTE_UNSIGNED) | 
		(
			// 半字对齐
			((ls_type_for_pre_prcs == LS_TYPE_HALF_WORD) | (ls_type_for_pre_prcs == LS_TYPE_HALF_WORD_UNSIGNED)) & 
			(~ls_addr_for_pre_prcs[0])
		) | 
		(
			// 字对齐
			(ls_type_for_pre_prcs == LS_TYPE_WORD) & (ls_addr_for_pre_prcs[1:0] == 2'b00)
		);
	assign store_din_in_pre_prcs = 
		({32{ls_type_for_pre_prcs == LS_TYPE_BYTE}} & {4{ls_din_for_pre_prcs[7:0]}}) | 
		({32{ls_type_for_pre_prcs == LS_TYPE_HALF_WORD}} & {2{ls_din_for_pre_prcs[15:0]}}) | 
		({32{ls_type_for_pre_prcs == LS_TYPE_WORD}} & ls_din_for_pre_prcs);
	assign store_wmask_in_pre_prcs = 
		({4{ls_type_for_pre_prcs == LS_TYPE_BYTE}} & (4'b0001 << ls_addr_for_pre_prcs[1:0])) | 
		({4{ls_type_for_pre_prcs == LS_TYPE_HALF_WORD}} & (4'b0011 << {ls_addr_for_pre_prcs[1], 1'b0})) | 
		({4{ls_type_for_pre_prcs == LS_TYPE_WORD}} & 4'b1111);
	
	/**
	数据总线事务随路信息缓存区
	
	数据总线命令通道握手时写入, 取走访存结果时读出
	**/
	// [存储实体]
	reg[clogb2(LS_BUF_ENTRY_N-1):0] dbus_info_buf_trans_eid[0:DBUS_OUTSTANDING_N-1]; // 事务对应的访存缓存区条目编号
	// [事务启动侧写端口]
	wire dbus_info_buf_luc_wen;
	wire[clogb2(LS_BUF_ENTRY_N-1):0] dbus_info_buf_luc_din_trans_eid; // 事务对应的访存缓存区条目编号
	wire dbus_info_buf_luc_full_n;
	// [事务响应侧读端口]
	wire dbus_info_buf_rsp_ren;
	wire[clogb2(LS_BUF_ENTRY_N-1):0] dbus_info_buf_rsp_dout_trans_eid; // 事务对应的访存缓存区条目编号
	wire dbus_info_buf_rsp_empty_n;
	// [访存结果侧读端口]
	wire dbus_info_buf_res_ren;
	wire[clogb2(LS_BUF_ENTRY_N-1):0] dbus_info_buf_res_dout_trans_eid; // 事务对应的访存缓存区条目编号
	wire dbus_info_buf_res_empty_n;
	// [指针]
	reg[clogb2(DBUS_OUTSTANDING_N):0] dbus_info_buf_luc_wptr; // 事务启动侧写指针
	reg[clogb2(DBUS_OUTSTANDING_N):0] dbus_info_buf_rsp_rptr; // 事务响应侧读指针
	reg[clogb2(DBUS_OUTSTANDING_N):0] dbus_info_buf_res_rptr; // 访存结果侧读指针
	
	assign dbus_info_buf_luc_full_n = 
		~(
			(dbus_info_buf_luc_wptr[clogb2(DBUS_OUTSTANDING_N)] ^ dbus_info_buf_res_rptr[clogb2(DBUS_OUTSTANDING_N)]) & 
			(dbus_info_buf_luc_wptr[clogb2(DBUS_OUTSTANDING_N-1):0] == dbus_info_buf_res_rptr[clogb2(DBUS_OUTSTANDING_N-1):0])
		);
	
	assign dbus_info_buf_rsp_dout_trans_eid = dbus_info_buf_trans_eid[dbus_info_buf_rsp_rptr[clogb2(DBUS_OUTSTANDING_N-1):0]];
	assign dbus_info_buf_rsp_empty_n = 
		~(dbus_info_buf_luc_wptr == dbus_info_buf_rsp_rptr);
	
	assign dbus_info_buf_res_dout_trans_eid = dbus_info_buf_trans_eid[dbus_info_buf_res_rptr[clogb2(DBUS_OUTSTANDING_N-1):0]];
	assign dbus_info_buf_res_empty_n = 
		~(dbus_info_buf_rsp_rptr == dbus_info_buf_res_rptr);
	
	genvar dbus_info_buf_i;
	generate
		for(dbus_info_buf_i = 0;dbus_info_buf_i < DBUS_OUTSTANDING_N;dbus_info_buf_i = dbus_info_buf_i + 1)
		begin:dbus_info_buf_blk
			always @(posedge clk)
			begin
				if(
					dbus_info_buf_luc_wen & dbus_info_buf_luc_full_n & 
					(dbus_info_buf_luc_wptr[clogb2(DBUS_OUTSTANDING_N-1):0] == dbus_info_buf_i)
				)
					dbus_info_buf_trans_eid[dbus_info_buf_i] <= # SIM_DELAY dbus_info_buf_luc_din_trans_eid;
			end
		end
	endgenerate
	
	// 事务启动侧写指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			dbus_info_buf_luc_wptr <= 0;
		else if(dbus_info_buf_luc_wen & dbus_info_buf_luc_full_n)
			dbus_info_buf_luc_wptr <= # SIM_DELAY dbus_info_buf_luc_wptr + 1'b1;
	end
	// 事务响应侧读指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			dbus_info_buf_rsp_rptr <= 0;
		else if(dbus_info_buf_rsp_ren & dbus_info_buf_rsp_empty_n)
			dbus_info_buf_rsp_rptr <= # SIM_DELAY dbus_info_buf_rsp_rptr + 1'b1;
	end
	// 访存结果侧读指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			dbus_info_buf_res_rptr <= 0;
		else if(dbus_info_buf_res_ren & dbus_info_buf_res_empty_n)
			dbus_info_buf_res_rptr <= # SIM_DELAY dbus_info_buf_res_rptr + 1'b1;
	end
	
	/** 访存响应后处理 **/
	wire[2:0] ls_type_for_pos_prcs; // 访存类型
	wire[31:0] ls_addr_for_pos_prcs; // 访存地址
	wire[31:0] rdata_org_for_pos_prcs; // 原始的访存读数据
	wire[31:0] rdata_algn_in_pos_prcs; // 对齐后的访存读数据
	wire[31:0] rdata_final_in_pos_prcs; // 最终的访存读数据
	
	assign rdata_algn_in_pos_prcs = rdata_org_for_pos_prcs >> {ls_addr_for_pos_prcs[1:0], 3'b000};
	assign rdata_final_in_pos_prcs = 
		({32{ls_type_for_pos_prcs == LS_TYPE_BYTE}} & {{24{rdata_algn_in_pos_prcs[7]}}, rdata_algn_in_pos_prcs[7:0]}) | 
		({32{ls_type_for_pos_prcs == LS_TYPE_HALF_WORD}} & {{16{rdata_algn_in_pos_prcs[15]}}, rdata_algn_in_pos_prcs[15:0]}) | 
		({32{ls_type_for_pos_prcs == LS_TYPE_WORD}} & rdata_algn_in_pos_prcs) | 
		({32{ls_type_for_pos_prcs == LS_TYPE_BYTE_UNSIGNED}} & {24'd0, rdata_algn_in_pos_prcs[7:0]}) | 
		({32{ls_type_for_pos_prcs == LS_TYPE_HALF_WORD_UNSIGNED}} & {16'd0, rdata_algn_in_pos_prcs[15:0]});
	
	/** 数据总线超时控制 **/
	// [计数器]
	reg[clogb2(DBUS_ACCESS_TIMEOUT_TH):0] dbus_timeout_cnt; // 超时计数器
	// [标志]
	reg dbus_timeout_flag; // 超时标志
	wire dbus_timeout_idct; // 超时指示
	
	assign dbus_timeout = dbus_timeout_flag;
	assign dbus_timeout_idct = 
		(~dbus_timeout_flag) & (DBUS_ACCESS_TIMEOUT_TH != 0) & 
		(~(m_icb_rsp_valid & m_icb_rsp_ready)) & 
		dbus_info_buf_rsp_empty_n & 
		(dbus_timeout_cnt == (DBUS_ACCESS_TIMEOUT_TH - 1));
	
	// 超时计数器
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			dbus_timeout_cnt <= 0;
		else if(
			(~dbus_timeout_flag) & (DBUS_ACCESS_TIMEOUT_TH != 0) & 
			(
				(m_icb_rsp_valid & m_icb_rsp_ready) | 
				dbus_info_buf_rsp_empty_n
			)
		)
			dbus_timeout_cnt <= # SIM_DELAY 
				(m_icb_rsp_valid & m_icb_rsp_ready) ? 
					0:
					(dbus_timeout_cnt + 1'b1);
	end
	
	// 超时标志
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			dbus_timeout_flag <= 1'b0;
		else if((~dbus_timeout_flag) & (DBUS_ACCESS_TIMEOUT_TH != 0))
			dbus_timeout_flag <= # SIM_DELAY dbus_timeout_idct;
	end
	
	/** 访存缓存区 **/
	// [存储实体]
	reg ls_buf_is_store[0:LS_BUF_ENTRY_N-1]; // 是否写传输
	reg[2:0] ls_buf_access_type[0:LS_BUF_ENTRY_N-1]; // 访存类型
	reg[4:0] ls_buf_rd_id_for_ld[0:LS_BUF_ENTRY_N-1]; // 用于加载的目标寄存器的索引
	reg[31:0] ls_buf_addr[0:LS_BUF_ENTRY_N-1]; // 访存地址
	reg[31:0] ls_buf_data[0:LS_BUF_ENTRY_N-1]; // 写数据/读数据
	reg[3:0] ls_buf_wmask[0:LS_BUF_ENTRY_N-1]; // 写字节掩码
	reg[INST_ID_WIDTH-1:0] ls_buf_inst_id[0:LS_BUF_ENTRY_N-1]; // 指令ID
	reg[1:0] ls_buf_err_code[0:LS_BUF_ENTRY_N-1]; // 错误码
	reg[clogb2(LS_BUF_ENTRY_N):0] ls_buf_wptr_rcd[0:LS_BUF_ENTRY_N-1]; // 记录的写指针
	// [标志]
	reg[LS_BUF_ENTRY_N-1:0] ls_buf_vld_flag; // 有效标志
	reg[LS_BUF_ENTRY_N-1:0] ls_buf_allow_flag; // 许可标志
	reg ls_buf_exist_addr_unalgn_req; // 存在地址非对齐的请求项(标志)
	reg ls_buf_exist_pre_exec_to_prmt; // 存在待许可提前执行项(标志)
	wire[LS_BUF_ENTRY_N-1:0] ls_buf_pre_exec_cflct; // 提前执行项地址冲突(标志)
	reg[LS_BUF_ENTRY_N-1:0] ls_buf_trans_launched_flag; // 总线事务已启动(标志)
	wire now_sel_addr_unalgn_req; // 当前选择地址非对齐的访存结果(标志)
	// [指针]
	reg[clogb2(LS_BUF_ENTRY_N):0] ls_buf_wptr; // 缓存区写指针
	reg[clogb2(LS_BUF_ENTRY_N-1):0] ls_buf_addr_unalgn_ptr; // 地址非对齐请求项指针
	reg[clogb2(LS_BUF_ENTRY_N-1):0] ls_buf_pre_exec_to_prmt_ptr; // 待许可提前执行项指针
	wire[clogb2(LS_BUF_ENTRY_N-1):0] ls_buf_rptr; // 缓存区读指针
	
	assign s_req_ready = 
		(~ls_buf_exist_addr_unalgn_req) & // 保证缓存区仅存在1条地址非对齐的请求
		((~ls_buf_exist_pre_exec_to_prmt) | (~s_req_pre_exec_prmt)) & // 保证缓存区仅存在1个待许可提前执行项
		(~ls_buf_vld_flag[ls_buf_wptr[clogb2(LS_BUF_ENTRY_N-1):0]]); // 当前待写项无效
	
	assign m_icb_rsp_ready = dbus_info_buf_rsp_empty_n;
	
	assign dbus_info_buf_rsp_ren = 
		(m_icb_rsp_valid & m_icb_rsp_ready) | 
		dbus_timeout_idct;
	
	assign ls_type_for_pos_prcs = ls_buf_access_type[dbus_info_buf_rsp_dout_trans_eid];
	assign ls_addr_for_pos_prcs = ls_buf_addr[dbus_info_buf_rsp_dout_trans_eid];
	assign rdata_org_for_pos_prcs = m_icb_rsp_rdata;
	
	genvar ls_buf_i;
	generate
		for(ls_buf_i = 0;ls_buf_i < LS_BUF_ENTRY_N;ls_buf_i = ls_buf_i + 1)
		begin:ls_buf_blk
			assign ls_buf_pre_exec_cflct[ls_buf_i] = 
				ls_buf_vld_flag[ls_buf_i] & // 条目有效
				// 条目比"待许可提前执行项"更旧
				(
					ls_buf_wptr_rcd[ls_buf_i][clogb2(LS_BUF_ENTRY_N)] ^ 
					ls_buf_wptr_rcd[ls_buf_pre_exec_to_prmt_ptr][clogb2(LS_BUF_ENTRY_N)] ^ 
					(ls_buf_i < ls_buf_pre_exec_to_prmt_ptr)
				) & 
				(ls_buf_addr[ls_buf_i][31:2] == ls_buf_addr[ls_buf_pre_exec_to_prmt_ptr][31:2]); // 地址冲突
			
			// 是否写传输, 访存类型, 用于加载的目标寄存器的索引, 访存地址, 指令ID, 记录的写指针
			always @(posedge clk)
			begin
				if(s_req_valid & s_req_ready & (ls_buf_wptr[clogb2(LS_BUF_ENTRY_N-1):0] == ls_buf_i))
				begin
					ls_buf_is_store[ls_buf_i] <= # SIM_DELAY s_req_ls_sel;
					ls_buf_access_type[ls_buf_i] <= # SIM_DELAY s_req_ls_type;
					ls_buf_rd_id_for_ld[ls_buf_i] <= # SIM_DELAY s_req_rd_id_for_ld;
					ls_buf_addr[ls_buf_i] <= # SIM_DELAY s_req_ls_addr;
					ls_buf_inst_id[ls_buf_i] <= # SIM_DELAY s_req_lsu_inst_id;
					ls_buf_wptr_rcd[ls_buf_i] <= # SIM_DELAY ls_buf_wptr;
				end
			end
			
			// 写数据/读数据
			always @(posedge clk)
			begin
				if(
					// 接受了地址对齐的存储请求
					(
						s_req_valid & s_req_ready & (ls_buf_wptr[clogb2(LS_BUF_ENTRY_N-1):0] == ls_buf_i) & 
						s_req_ls_sel & ls_addr_aligned_in_pre_prcs
					) | 
					// 加载请求返回响应
					(
						m_icb_rsp_valid & m_icb_rsp_ready & (dbus_info_buf_rsp_dout_trans_eid == ls_buf_i) & 
						(~ls_buf_is_store[ls_buf_i])
					)
				)
					ls_buf_data[ls_buf_i] <= # SIM_DELAY 
						(m_icb_rsp_valid & m_icb_rsp_ready & (dbus_info_buf_rsp_dout_trans_eid == ls_buf_i)) ? 
							rdata_final_in_pos_prcs:
							store_din_in_pre_prcs;
			end
			
			// 写字节掩码
			always @(posedge clk)
			begin
				if(
					// 接受了地址对齐的加载/存储请求
					s_req_valid & s_req_ready & (ls_buf_wptr[clogb2(LS_BUF_ENTRY_N-1):0] == ls_buf_i) & 
					ls_addr_aligned_in_pre_prcs
				)
					ls_buf_wmask[ls_buf_i] <= # SIM_DELAY 
						s_req_ls_sel ? 
							store_wmask_in_pre_prcs:
							4'b0000;
			end
			
			// 错误码
			always @(posedge clk)
			begin
				if(
					// 接受了地址非对齐的加载/存储请求
					(
						s_req_valid & s_req_ready & (ls_buf_wptr[clogb2(LS_BUF_ENTRY_N-1):0] == ls_buf_i) & 
						(~ls_addr_aligned_in_pre_prcs)
					) | 
					// 加载/存储请求返回响应或超时
					(
						dbus_info_buf_rsp_empty_n & (dbus_info_buf_rsp_dout_trans_eid == ls_buf_i) & 
						(
							(m_icb_rsp_valid & m_icb_rsp_ready) | 
							dbus_timeout_idct
						)
					)
				)
					ls_buf_err_code[ls_buf_i] <= # SIM_DELAY 
						(
							s_req_valid & s_req_ready & (ls_buf_wptr[clogb2(LS_BUF_ENTRY_N-1):0] == ls_buf_i) & 
							(~ls_addr_aligned_in_pre_prcs)
						) ? 
							DBUS_ACCESS_LS_UNALIGNED: // 错误码: 访存地址非对齐
							(
								(m_icb_rsp_valid & m_icb_rsp_ready) ? 
									(
										m_icb_rsp_err ? 
											DBUS_ACCESS_BUS_ERR: // 错误码: 数据总线访问错误
											DBUS_ACCESS_NORMAL // 错误码: 正常
									):
									DBUS_ACCESS_TIMEOUT // 错误码: 响应超时
							);
			end
			
			// 有效标志
			always @(posedge clk or negedge resetn)
			begin
				if(~resetn)
					ls_buf_vld_flag[ls_buf_i] <= 1'b0;
				else if(
					// 接受了加载/存储请求
					(s_req_valid & s_req_ready & (ls_buf_wptr[clogb2(LS_BUF_ENTRY_N-1):0] == ls_buf_i)) | 
					// 取走访存结果
					(m_resp_valid & m_resp_ready & (ls_buf_rptr == ls_buf_i))
				)
					ls_buf_vld_flag[ls_buf_i] <= # SIM_DELAY 
						s_req_valid & s_req_ready & (ls_buf_wptr[clogb2(LS_BUF_ENTRY_N-1):0] == ls_buf_i);
			end
			
			// 许可标志
			always @(posedge clk)
			begin
				if(
					ls_buf_vld_flag[ls_buf_i] ? 
						(
							(~ls_buf_allow_flag[ls_buf_i]) & 
							(
								// 若为待许可的提前执行项, 则在地址不产生冲突时自动许可
								(
									ls_buf_exist_pre_exec_to_prmt & (ls_buf_pre_exec_to_prmt_ptr == ls_buf_i) & 
									(ls_buf_pre_exec_cflct == {LS_BUF_ENTRY_N{1'b0}})
								) | 
								// 外部许可
								(ls_allow_vld & (ls_allow_inst_id == ls_buf_inst_id[ls_buf_i]))
							)
						):
						(s_req_valid & s_req_ready & (ls_buf_wptr[clogb2(LS_BUF_ENTRY_N-1):0] == ls_buf_i))
				)
					ls_buf_allow_flag[ls_buf_i] <= # SIM_DELAY 
						ls_buf_vld_flag[ls_buf_i] ? 
							1'b1:
							(~ls_addr_aligned_in_pre_prcs); // 接受请求时, 如果地址非对齐, 则直接许可该条目
			end
		end
	endgenerate
	
	// 存在地址非对齐的请求项(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			ls_buf_exist_addr_unalgn_req <= 1'b0;
		else if(
			// 接受了地址非对齐的加载/存储请求
			(s_req_valid & s_req_ready & (~ls_addr_aligned_in_pre_prcs)) | 
			// 取走了地址非对齐的访存结果
			(m_resp_valid & m_resp_ready & now_sel_addr_unalgn_req)
		)
			ls_buf_exist_addr_unalgn_req <= # SIM_DELAY ~ls_buf_exist_addr_unalgn_req;
	end
	
	// 存在待许可提前执行项(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			ls_buf_exist_pre_exec_to_prmt <= 1'b0;
		else if(
			// 接受了可提前执行、地址对齐的加载/存储请求
			(s_req_valid & s_req_ready & s_req_pre_exec_prmt & ls_addr_aligned_in_pre_prcs) | 
			// 对于现存的待许可提前执行项, 地址冲突已解决
			(ls_buf_exist_pre_exec_to_prmt & (ls_buf_pre_exec_cflct == {LS_BUF_ENTRY_N{1'b0}}))
		)
			ls_buf_exist_pre_exec_to_prmt <= # SIM_DELAY ~ls_buf_exist_pre_exec_to_prmt;
	end
	
	// 缓存区写指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			ls_buf_wptr <= 0;
		else if(s_req_valid & s_req_ready)
			ls_buf_wptr <= # SIM_DELAY ls_buf_wptr + 1'b1;
	end
	
	// 地址非对齐请求项指针
	always @(posedge clk)
	begin
		if(s_req_valid & s_req_ready & (~ls_addr_aligned_in_pre_prcs))
			ls_buf_addr_unalgn_ptr <= # SIM_DELAY ls_buf_wptr[clogb2(LS_BUF_ENTRY_N-1):0];
	end
	
	// 待许可提前执行项指针
	always @(posedge clk)
	begin
		if(s_req_valid & s_req_ready & s_req_pre_exec_prmt & ls_addr_aligned_in_pre_prcs)
			ls_buf_pre_exec_to_prmt_ptr <= # SIM_DELAY ls_buf_wptr[clogb2(LS_BUF_ENTRY_N-1):0];
	end
	
	/**
	数据总线仲裁
	
	从访存缓存区中有效、已许可、总线事务未启动的条目里, 选出1个最旧的条目来发起数据总线事务
	**/
	// [仲裁状态]
	reg ls_arb_locked; // 仲裁锁定(标志)
	// [仲裁输入]
	wire[LS_BUF_ENTRY_N*6-1:0] ls_buf_wptr_rcd_flt; // 展平的记录的写指针
	wire[LS_BUF_ENTRY_N*(32+1+32+4)-1:0] ls_buf_arb_payload_flt; // 展平的负载数据
	wire[LS_BUF_ENTRY_N-1:0] ls_buf_entry_for_trans_mask_cur; // 当前的待启动传输的访存缓存区条目(掩码)
	reg[LS_BUF_ENTRY_N-1:0] ls_buf_entry_for_trans_mask_latched; // 锁存的待启动传输的访存缓存区条目(掩码)
	wire[LS_BUF_ENTRY_N-1:0] ls_buf_entry_for_trans_mask_actual; // 实际的待启动传输的访存缓存区条目(掩码)
	// [仲裁输出]
	wire[4:0] arb_sel_entry_id; // 仲裁所选中条目的编号
	wire[31:0] arb_sel_entry_addr; // 仲裁所选中条目的地址
	wire arb_sel_entry_is_store; // 仲裁所选中条目的读写类型
	wire[31:0] arb_sel_entry_wdata; // 仲裁所选中条目的写数据
	wire[3:0] arb_sel_entry_wmask; // 仲裁所选中条目的写字节掩码
	
	assign m_icb_cmd_addr = arb_sel_entry_addr;
	assign m_icb_cmd_read = ~arb_sel_entry_is_store;
	assign m_icb_cmd_wdata = arb_sel_entry_wdata;
	assign m_icb_cmd_wmask = arb_sel_entry_wmask;
	assign m_icb_cmd_valid = (|ls_buf_entry_for_trans_mask_actual) & dbus_info_buf_luc_full_n;
	
	assign dbus_info_buf_luc_wen = m_icb_cmd_valid & m_icb_cmd_ready;
	assign dbus_info_buf_luc_din_trans_eid = arb_sel_entry_id[clogb2(LS_BUF_ENTRY_N-1):0];
	
	genvar ls_arb_i;
	generate
		for(ls_arb_i = 0;ls_arb_i < LS_BUF_ENTRY_N;ls_arb_i = ls_arb_i + 1)
		begin:ls_arb_blk
			assign ls_buf_wptr_rcd_flt[ls_arb_i*6+5] = 
				ls_buf_wptr_rcd[ls_arb_i][clogb2(LS_BUF_ENTRY_N)];
			assign ls_buf_wptr_rcd_flt[ls_arb_i*6+4:ls_arb_i*6] = 
				ls_buf_wptr_rcd[ls_arb_i][clogb2(LS_BUF_ENTRY_N-1):0] | 5'b00000;
			assign ls_buf_arb_payload_flt[(ls_arb_i+1)*(32+1+32+4)-1:ls_arb_i*(32+1+32+4)] = 
				{ls_buf_addr[ls_arb_i], ls_buf_is_store[ls_arb_i], ls_buf_data[ls_arb_i], ls_buf_wmask[ls_arb_i]};
			assign ls_buf_entry_for_trans_mask_cur[ls_arb_i] = 
				ls_buf_vld_flag[ls_arb_i] & ls_buf_allow_flag[ls_arb_i] & (~ls_buf_trans_launched_flag[ls_arb_i]);
			
			assign ls_buf_entry_for_trans_mask_actual[ls_arb_i] = 
				ls_arb_locked ? 
					ls_buf_entry_for_trans_mask_latched[ls_arb_i]:
					ls_buf_entry_for_trans_mask_cur[ls_arb_i];
			
			// 总线事务已启动(标志)
			always @(posedge clk)
			begin
				if(
					(s_req_valid & s_req_ready & (ls_buf_wptr[clogb2(LS_BUF_ENTRY_N-1):0] == ls_arb_i)) | 
					// 当前项被仲裁电路选中, 并在数据总线上发起事务
					(m_icb_cmd_valid & m_icb_cmd_ready & (arb_sel_entry_id[clogb2(LS_BUF_ENTRY_N-1):0] == ls_arb_i))
				)
					ls_buf_trans_launched_flag[ls_arb_i] <= # SIM_DELAY 
						(s_req_valid & s_req_ready & (ls_buf_wptr[clogb2(LS_BUF_ENTRY_N-1):0] == ls_arb_i)) ? 
							(~ls_addr_aligned_in_pre_prcs): // 接受请求时, 如果地址非对齐, 则直接标记为总线事务已启动
							1'b1;
			end
		end
	endgenerate
	
	// 仲裁锁定(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			ls_arb_locked <= 1'b0;
		else if(
			ls_arb_locked ? 
				m_icb_cmd_ready:
				(m_icb_cmd_valid & (~m_icb_cmd_ready))
		)
			ls_arb_locked <= # SIM_DELAY ~ls_arb_locked;
	end
	
	// 锁存的待启动传输的访存缓存区条目(掩码)
	always @(posedge clk)
	begin
		if((~ls_arb_locked) & m_icb_cmd_valid & (~m_icb_cmd_ready))
			ls_buf_entry_for_trans_mask_latched <= # SIM_DELAY ls_buf_entry_for_trans_mask_cur;
	end
	
	find_oldest_entry #(
		.PAYLOAD_WIDTH(32+1+32+4),
		.ENTRY_N(LS_BUF_ENTRY_N)
	)find_oldest_entry_u(
		.wptr_recorded(ls_buf_wptr_rcd_flt),
		.payload(ls_buf_arb_payload_flt),
		.cmp_mask(ls_buf_entry_for_trans_mask_actual),
		
		.newest_entry_i(arb_sel_entry_id),
		.newest_entry_payload({arb_sel_entry_addr, arb_sel_entry_is_store, arb_sel_entry_wdata, arb_sel_entry_wmask})
	);
	
	/**
	访存结果
	
	优先选择地址非对齐的访存结果, 其次再根据得到数据总线响应的顺序来选择
	**/
	reg ls_res_locked; // 锁定访存结果(标志)
	reg to_sel_addr_unalgn_req_latched; // 锁存的选择地址非对齐的访存结果(标志)
	
	assign m_resp_ls_sel = ls_buf_is_store[ls_buf_rptr];
	assign m_resp_rd_id_for_ld = ls_buf_rd_id_for_ld[ls_buf_rptr];
	assign m_resp_dout_ls_addr = 
		(ls_buf_err_code[ls_buf_rptr] == DBUS_ACCESS_NORMAL) ? 
			ls_buf_data[ls_buf_rptr]:
			ls_buf_addr[ls_buf_rptr];
	assign m_resp_err = ls_buf_err_code[ls_buf_rptr];
	assign m_resp_lsu_inst_id = ls_buf_inst_id[ls_buf_rptr];
	assign m_resp_valid = ls_buf_exist_addr_unalgn_req | dbus_info_buf_res_empty_n;
	
	assign dbus_info_buf_res_ren = m_resp_valid & m_resp_ready & (~now_sel_addr_unalgn_req);
	
	assign ls_buf_rptr = 
		now_sel_addr_unalgn_req ? 
			ls_buf_addr_unalgn_ptr:
			dbus_info_buf_res_dout_trans_eid;
	
	assign now_sel_addr_unalgn_req = 
		ls_res_locked ? 
			to_sel_addr_unalgn_req_latched:
			ls_buf_exist_addr_unalgn_req;
	
	// 锁定访存结果(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			ls_res_locked <= 1'b0;
		else if(
			ls_res_locked ? 
				m_resp_ready:
				(m_resp_valid & (~m_resp_ready))
		)
			ls_res_locked <= # SIM_DELAY ~ls_res_locked;
	end
	
	// 锁存的选择地址非对齐的访存结果(标志)
	always @(posedge clk)
	begin
		if((~ls_res_locked) & m_resp_valid & (~m_resp_ready))
			to_sel_addr_unalgn_req_latched <= # SIM_DELAY ls_buf_exist_addr_unalgn_req;
	end
	
endmodule
