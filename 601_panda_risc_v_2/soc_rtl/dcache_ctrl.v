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
本模块: 数据Cache控制单元

描述:
写回、写分配、CACHE_WAY_N路、CACHE_ENTRY_N项、CACHE_LINE_WORD_N字的组相连数据Cache

读命中时最高访问速度为1word/cycle, 写命中时最高访问速度为0.5word/cycle
未命中处理采用状态机来控制

注意：
处理器核ICB从机给出的访问地址必须对齐到字(能被4整除)

协议:
ICB MASTER/SLAVE
AXIS MASTER

作者: 陈家耀
日期: 2025/04/14
********************************************************************/


module dcache_ctrl #(
	parameter integer CACHE_WAY_N = 4, // 缓存路数(1 | 2 | 4 | 8)
	parameter integer CACHE_ENTRY_N = 512, // 缓存存储条目数
	parameter integer CACHE_LINE_WORD_N = 8, // 每个缓存行的字数(1 | 2 | 4 | 8 | 16)
	parameter integer CACHE_TAG_WIDTH = 12, // 缓存标签位数
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 处理器核ICB从机
	// 命令通道
	input wire[31:0] s_icb_cmd_addr,
	input wire s_icb_cmd_read,
	input wire[31:0] s_icb_cmd_wdata,
	input wire[3:0] s_icb_cmd_wmask,
	input wire s_icb_cmd_valid,
	output wire s_icb_cmd_ready,
	// 响应通道
	output wire[31:0] s_icb_rsp_rdata,
	output wire s_icb_rsp_err, // const -> 1'b0
	output wire s_icb_rsp_valid,
	input wire s_icb_rsp_ready,
	
	// 读下级存储器ICB主机
	// [命令通道]
	output wire[31:0] m_icb_cmd_addr,
	output wire m_icb_cmd_read, // const -> 1'b1
	output wire[31:0] m_icb_cmd_wdata, // not care
	output wire[3:0] m_icb_cmd_wmask, // const -> 4'b0000
	output wire m_icb_cmd_valid,
	input wire m_icb_cmd_ready,
	// [响应通道]
	input wire[31:0] m_icb_rsp_rdata,
	input wire m_icb_rsp_err, // ignored
	input wire m_icb_rsp_valid,
	output wire m_icb_rsp_ready,
	
	// 待写的缓存行(AXIS主机)
	output wire[CACHE_LINE_WORD_N*32+32-1:0] m_wbuf_axis_data, // {缓存行地址(32位), 缓存行数据块(CACHE_LINE_WORD_N*32位)}
	output wire m_wbuf_axis_valid,
	input wire m_wbuf_axis_ready,
	
	// 写缓存检索
	output wire[31:0] wbuf_sch_addr, // 检索地址
	input wire wbuf_cln_found_flag, // 在写缓存里找到缓存行(标志)
	input wire[CACHE_LINE_WORD_N*32-1:0] wbuf_sch_datblk, // 检索到的数据块
	
	// 查询或更新热度表
	output wire hot_tb_en, // 热度表使能
	output wire hot_tb_upd_en, // 热度表更新使能
	output wire[31:0] hot_tb_cid, // 待查询或更新的缓存项的索引号
	output wire[2:0] hot_tb_acs_wid, // 本次访问的缓存路编号
	output wire hot_tb_init_item, // 初始化热度项(标志)
	output wire hot_tb_swp_lru_item, // 置换最近最少使用项(标志)
	input wire[2:0] hot_tb_lru_wid, // 最近最少使用项的缓存路编号
	
	// 逻辑Cache存储器接口
	// [数据存储器]
	output wire[CACHE_WAY_N-1:0] cache_data_en, // 数据存储器使能
	output wire[CACHE_WAY_N*CACHE_LINE_WORD_N*4-1:0] cache_data_byte_wen, // 数据存储器字节写使能
	output wire[CACHE_WAY_N*32-1:0] cache_data_index, // 数据存储器访问索引号
	output wire[CACHE_WAY_N*CACHE_LINE_WORD_N*4*8-1:0] cache_din, // 缓存行写数据
	input wire[CACHE_WAY_N*CACHE_LINE_WORD_N*4*8-1:0] cache_dout, // 缓存行读数据
	// [标签存储器]
	output wire[CACHE_WAY_N-1:0] cache_tag_en, // 标签存储器使能
	output wire[CACHE_WAY_N-1:0] cache_tag_wen, // 标签存储器写使能
	output wire[CACHE_WAY_N*32-1:0] cache_tag_index, // 标签存储器访问索引号
	output wire[CACHE_WAY_N*CACHE_TAG_WIDTH-1:0] cache_tag, // 缓存行标签
	output wire[CACHE_WAY_N-1:0] cache_valid_new, // 标签存储器待写的有效标志
	output wire[CACHE_WAY_N-1:0] cache_dirty_new, // 标签存储器待写的脏标志
	input wire[CACHE_WAY_N*32-1:0] cache_real_addr, // 缓存行的实际基地址
	input wire[CACHE_WAY_N-1:0] cache_hit, // 缓存行命中(标志)
	input wire[CACHE_WAY_N-1:0] cache_valid, // 缓存行有效(标志)
	input wire[CACHE_WAY_N-1:0] cache_dirty // 缓存行脏(标志)
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
	// 未命中处理状态常量
	localparam MISS_PROC_STS_NORMAL = 2'b00; // 状态: 正常
	localparam MISS_PROC_STS_SWP_CLN = 2'b01; // 状态: 置换缓存行
	localparam MISS_PROC_STS_UPD_CLN = 2'b10; // 状态: 更新缓存行
	localparam MISS_PROC_STS_RSP_TO_CPU = 2'b11; // 状态: 返回响应
	
	/** 逻辑Cache存储器接口 **/
	// [数据存储器]
	wire[CACHE_WAY_N-1:0] cache_data_en_arr; // 数据存储器使能(数组)
	wire[CACHE_LINE_WORD_N*4-1:0] cache_data_byte_wen_arr[0:CACHE_WAY_N-1]; // 数据存储器字节写使能(数组)
	wire[31:0] cache_data_index_arr[0:CACHE_WAY_N-1]; // 数据存储器访问索引号(数组)
	wire[CACHE_LINE_WORD_N*4*8-1:0] cache_din_arr[0:CACHE_WAY_N-1]; // 缓存行写数据(数组)
	wire[CACHE_LINE_WORD_N*4*8-1:0] cache_dout_arr[0:CACHE_WAY_N-1]; // 缓存行读数据(数组)
	// [标签存储器]
	wire[CACHE_WAY_N-1:0] cache_tag_en_arr; // 标签存储器使能(数组)
	wire[CACHE_WAY_N-1:0] cache_tag_wen_arr; // 标签存储器写使能(数组)
	wire[31:0] cache_tag_index_arr[0:CACHE_WAY_N-1]; // 标签存储器访问索引号(数组)
	wire[CACHE_TAG_WIDTH-1:0] cache_tag_arr[0:CACHE_WAY_N-1]; // 缓存行标签(数组)
	wire[CACHE_WAY_N-1:0] cache_valid_new_arr; // 标签存储器待写的有效标志(数组)
	wire[CACHE_WAY_N-1:0] cache_dirty_new_arr; // 标签存储器待写的脏标志(数组)
	wire[31:0] cache_real_addr_arr[0:CACHE_WAY_N-1]; // 缓存行的实际基地址(数组)
	wire[CACHE_WAY_N-1:0] cache_hit_arr; // 缓存行命中标志(数组)
	wire[CACHE_WAY_N-1:0] cache_valid_arr; // 缓存行有效标志(数组)
	wire[CACHE_WAY_N-1:0] cache_dirty_arr; // 缓存行脏标志(数组)
	
	genvar logic_cache_mem_i;
	generate
		for(logic_cache_mem_i = 0;logic_cache_mem_i < CACHE_WAY_N;logic_cache_mem_i = logic_cache_mem_i + 1)
		begin:logic_cache_mem_blk
			assign cache_data_en[logic_cache_mem_i] = cache_data_en_arr[logic_cache_mem_i];
			assign cache_data_byte_wen[CACHE_LINE_WORD_N*4*(logic_cache_mem_i+1)-1:CACHE_LINE_WORD_N*4*logic_cache_mem_i] = 
				cache_data_byte_wen_arr[logic_cache_mem_i];
			assign cache_data_index[32*(logic_cache_mem_i+1)-1:32*logic_cache_mem_i] = 
				cache_data_index_arr[logic_cache_mem_i];
			assign cache_din[CACHE_LINE_WORD_N*4*8*(logic_cache_mem_i+1)-1:CACHE_LINE_WORD_N*4*8*logic_cache_mem_i] = 
				cache_din_arr[logic_cache_mem_i];
			assign cache_dout_arr[logic_cache_mem_i] = 
				cache_dout[CACHE_LINE_WORD_N*4*8*(logic_cache_mem_i+1)-1:CACHE_LINE_WORD_N*4*8*logic_cache_mem_i];
			
			assign cache_tag_en[logic_cache_mem_i] = cache_tag_en_arr[logic_cache_mem_i];
			assign cache_tag_wen[logic_cache_mem_i] = cache_tag_wen_arr[logic_cache_mem_i];
			assign cache_tag_index[32*(logic_cache_mem_i+1)-1:32*logic_cache_mem_i] = 
				cache_tag_index_arr[logic_cache_mem_i];
			assign cache_tag[CACHE_TAG_WIDTH*(logic_cache_mem_i+1)-1:CACHE_TAG_WIDTH*logic_cache_mem_i] = 
				cache_tag_arr[logic_cache_mem_i];
			assign cache_valid_new[logic_cache_mem_i] = cache_valid_new_arr[logic_cache_mem_i];
			assign cache_dirty_new[logic_cache_mem_i] = cache_dirty_new_arr[logic_cache_mem_i];
			assign cache_real_addr_arr[logic_cache_mem_i] = 
				cache_real_addr[32*(logic_cache_mem_i+1)-1:32*logic_cache_mem_i];
			assign cache_hit_arr[logic_cache_mem_i] = cache_hit[logic_cache_mem_i];
			assign cache_valid_arr[logic_cache_mem_i] = cache_valid[logic_cache_mem_i];
			assign cache_dirty_arr[logic_cache_mem_i] = cache_dirty[logic_cache_mem_i];
		end
	endgenerate
	
	/** Cache访问 **/
	wire cache_miss_processing; // Cache未命中处理中(标志)
	wire on_cache_miss; // Cache未命中(指示)
	wire on_cache_miss_proc_done; // Cache未命中处理完成(指示)
	reg to_continue_cache_miss_proc; // 继续进行Cache未命中处理(标志)
	wire on_cache_wt_hit_upd; // Cache写命中后更新(指示)
	reg cache_wt_hit_upd_pending; // Cache写命中后更新等待(标志)
	reg cache_hit_pending; // Cache命中后等待CPU接收响应(标志)
	wire is_cache_hit; // 是否Cache命中
	wire has_invalid_cln; // 是否有无效的缓存行
	reg is_rd_cache; // 是否Cache读访问
	reg[31:0] cache_wdata; // Cache写数据
	reg[CACHE_LINE_WORD_N*4-1:0] cache_wt_byte_en; // Cache写字节掩码
	reg[clogb2(CACHE_LINE_WORD_N-1):0] cache_acs_addr_word_ofs; // Cache访问地址的字偏移量部分
	reg[clogb2(CACHE_ENTRY_N-1):0] cache_acs_addr_index; // Cache访问地址的index部分
	reg[CACHE_TAG_WIDTH-1:0] cache_acs_addr_tag; // Cache访问地址的tag部分
	reg cache_rdata_valid; // Cache读数据有效(标志)
	reg on_cache_rdata_valid; // Cache读数据有效(指示)
	wire[CACHE_LINE_WORD_N*4*8-1:0] cache_hit_datblk; // 命中的数据块
	wire[31:0] cache_hit_word; // 命中的字数据
	
	assign s_icb_cmd_ready = 
		(~(cache_miss_processing | on_cache_wt_hit_upd)) & 
		((~cache_rdata_valid) | s_icb_rsp_ready);
	
	assign cache_miss_processing = on_cache_miss | to_continue_cache_miss_proc;
	assign on_cache_miss = on_cache_rdata_valid & (~is_cache_hit);
	assign on_cache_wt_hit_upd = on_cache_rdata_valid & (~is_rd_cache) & is_cache_hit;
	assign is_cache_hit = |cache_hit_arr;
	assign has_invalid_cln = |(~cache_valid_arr);
	
	assign cache_hit_datblk = 
		(CACHE_WAY_N == 1) ? cache_dout_arr[0]:
		(CACHE_WAY_N == 2) ? cache_dout_arr[cache_hit_arr[1]]:
		(CACHE_WAY_N == 4) ? (
			({(CACHE_LINE_WORD_N*4*8){cache_hit_arr[0]}} & cache_dout_arr[0]) | 
			({(CACHE_LINE_WORD_N*4*8){cache_hit_arr[1]}} & cache_dout_arr[1]) | 
			({(CACHE_LINE_WORD_N*4*8){cache_hit_arr[2]}} & cache_dout_arr[2]) | 
			({(CACHE_LINE_WORD_N*4*8){cache_hit_arr[3]}} & cache_dout_arr[3])
		):(
			({(CACHE_LINE_WORD_N*4*8){cache_hit_arr[0]}} & cache_dout_arr[0]) | 
			({(CACHE_LINE_WORD_N*4*8){cache_hit_arr[1]}} & cache_dout_arr[1]) | 
			({(CACHE_LINE_WORD_N*4*8){cache_hit_arr[2]}} & cache_dout_arr[2]) | 
			({(CACHE_LINE_WORD_N*4*8){cache_hit_arr[3]}} & cache_dout_arr[3]) | 
			({(CACHE_LINE_WORD_N*4*8){cache_hit_arr[4]}} & cache_dout_arr[4]) | 
			({(CACHE_LINE_WORD_N*4*8){cache_hit_arr[5]}} & cache_dout_arr[5]) | 
			({(CACHE_LINE_WORD_N*4*8){cache_hit_arr[6]}} & cache_dout_arr[6]) | 
			({(CACHE_LINE_WORD_N*4*8){cache_hit_arr[7]}} & cache_dout_arr[7])
		);
	assign cache_hit_word = cache_hit_datblk >> (cache_acs_addr_word_ofs * 32);
	
	// 继续进行Cache未命中处理(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			to_continue_cache_miss_proc <= 1'b0;
		else
			to_continue_cache_miss_proc <= # SIM_DELAY 
				/*
				to_continue_cache_miss_proc ? 
					(~on_cache_miss_proc_done):
					(on_cache_miss & (~on_cache_miss_proc_done))
				*/
				(to_continue_cache_miss_proc | on_cache_miss) & (~on_cache_miss_proc_done);
	end
	
	// Cache写命中后更新等待(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cache_wt_hit_upd_pending <= 1'b0;
		else
			cache_wt_hit_upd_pending <= # SIM_DELAY 
				/*
				cache_wt_hit_upd_pending ? 
					(~s_icb_rsp_ready):
					(on_cache_wt_hit_upd & (~s_icb_rsp_ready))
				*/
				(cache_wt_hit_upd_pending | on_cache_wt_hit_upd) & (~s_icb_rsp_ready);
	end
	
	// Cache命中后等待CPU接收响应(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cache_hit_pending <= 1'b0;
		else
			cache_hit_pending <= # SIM_DELAY 
				/*
				cache_hit_pending ? 
					(~s_icb_rsp_ready):
					(on_cache_rdata_valid & is_cache_hit & (~s_icb_rsp_ready))
				*/
				(cache_hit_pending | (on_cache_rdata_valid & is_cache_hit)) & (~s_icb_rsp_ready);
	end
	
	// 是否Cache读访问
	always @(posedge aclk)
	begin
		if(s_icb_cmd_valid & s_icb_cmd_ready)
			is_rd_cache <= # SIM_DELAY s_icb_cmd_read;
	end
	// Cache写数据
	always @(posedge aclk)
	begin
		if(s_icb_cmd_valid & s_icb_cmd_ready & (~s_icb_cmd_read))
			cache_wdata <= # SIM_DELAY s_icb_cmd_wdata;
	end
	// Cache写字节掩码
	always @(posedge aclk)
	begin
		if(s_icb_cmd_valid & s_icb_cmd_ready)
			cache_wt_byte_en <= # SIM_DELAY 
				(({4{~s_icb_cmd_read}} & s_icb_cmd_wmask) | {(CACHE_LINE_WORD_N*4){1'b0}}) << 
				(((CACHE_LINE_WORD_N == 1) ? 0:s_icb_cmd_addr[2+clogb2(CACHE_LINE_WORD_N-1):2]) * 4);
	end
	// Cache访问地址的字偏移量部分, Cache访问地址的index部分, Cache访问地址的tag部分
	always @(posedge aclk)
	begin
		if(s_icb_cmd_valid & s_icb_cmd_ready)
		begin
			cache_acs_addr_word_ofs <= # SIM_DELAY 
				(CACHE_LINE_WORD_N == 1) ? 0:s_icb_cmd_addr[2+clogb2(CACHE_LINE_WORD_N-1):2];
			cache_acs_addr_index <= # SIM_DELAY 
				s_icb_cmd_addr[clogb2(4*CACHE_LINE_WORD_N)+clogb2(CACHE_ENTRY_N-1):clogb2(4*CACHE_LINE_WORD_N)];
			cache_acs_addr_tag <= # SIM_DELAY 
				s_icb_cmd_addr[clogb2(4*CACHE_LINE_WORD_N*CACHE_ENTRY_N)+CACHE_TAG_WIDTH-1:clogb2(4*CACHE_LINE_WORD_N*CACHE_ENTRY_N)];
		end
	end
	
	// Cache读数据有效(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cache_rdata_valid <= 1'b0;
		else if(
			(cache_rdata_valid & (
				((on_cache_wt_hit_upd | cache_wt_hit_upd_pending) & s_icb_rsp_ready) | 
				(cache_miss_processing & on_cache_miss_proc_done)
			)) | s_icb_cmd_ready
		)
			cache_rdata_valid <= # SIM_DELAY 
				(~(cache_rdata_valid & (
					(on_cache_wt_hit_upd & s_icb_rsp_ready) | 
					(cache_miss_processing & on_cache_miss_proc_done)
				))) & s_icb_cmd_valid;
	end
	
	// Cache读数据有效(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			on_cache_rdata_valid <= 1'b0;
		else
			on_cache_rdata_valid <= # SIM_DELAY s_icb_cmd_valid & s_icb_cmd_ready;
	end
	
	/** 写缓存检索 **/
	reg wbuf_cln_found_flag_r; // 在写缓存里找到缓存行(标志)
	reg[CACHE_LINE_WORD_N*32-1:0] wbuf_sch_datblk_r; // 检索到的数据块
	
	assign wbuf_sch_addr = {cache_acs_addr_tag, cache_acs_addr_index, {clogb2(CACHE_LINE_WORD_N*4){1'b0}}} | 32'h0000_0000;
	
	// 在写缓存里找到缓存行(标志), 检索到的数据块
	always @(posedge aclk)
	begin
		if(on_cache_miss)
		begin
			wbuf_cln_found_flag_r <= # SIM_DELAY wbuf_cln_found_flag;
			wbuf_sch_datblk_r <= # SIM_DELAY wbuf_sch_datblk;
		end
	end
	
	/** 读下级存储器 **/
	// [ICB主机命令端]
	reg[clogb2(CACHE_LINE_WORD_N-1):0] nxtlv_mem_acs_req_word_id; // 下级存储器访问请求的字索引
	reg nxtlv_mem_acs_valid; // 下级存储器访问有效(标志)
	// [ICB主机响应端]
	reg[CACHE_LINE_WORD_N*4*8-1:0] cln_fetched_from_ext; // 从外部取得的缓存行
	reg[CACHE_LINE_WORD_N-1:0] cln_fetched_word_id; // 从外部取缓存行的字索引(独热码)
	reg cln_ext_fetch_fns; // 从外部取缓存行完成(标志)
	wire cln_fetch_fns; // 取缓存行完成(标志)
	
	assign cln_fetch_fns = 
		wbuf_cln_found_flag_r | cln_ext_fetch_fns | 
		(m_icb_rsp_valid & m_icb_rsp_ready & cln_fetched_word_id[CACHE_LINE_WORD_N-1]);
	
	// 下级存储器访问请求的字索引
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			nxtlv_mem_acs_req_word_id <= 0;
		else if(m_icb_cmd_valid & m_icb_cmd_ready)
			nxtlv_mem_acs_req_word_id <= # SIM_DELAY 
				(nxtlv_mem_acs_req_word_id == (CACHE_LINE_WORD_N-1)) ? 
					0:(nxtlv_mem_acs_req_word_id + 1);
	end
	
	// 下级存储器访问有效(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			nxtlv_mem_acs_valid <= 1'b0;
		else
			nxtlv_mem_acs_valid <= # SIM_DELAY 
				nxtlv_mem_acs_valid ? 
					(~(
						m_icb_cmd_valid & m_icb_cmd_ready & (nxtlv_mem_acs_req_word_id == (CACHE_LINE_WORD_N-1))
					)):(on_cache_miss & (~wbuf_cln_found_flag));
	end
	
	// 从外部取得的缓存行
	generate
		if(CACHE_LINE_WORD_N == 1)
		begin
			always @(posedge aclk)
			begin
				if(m_icb_rsp_valid & m_icb_rsp_ready)
					cln_fetched_from_ext <= # SIM_DELAY m_icb_rsp_rdata;
			end
		end
		else
		begin
			always @(posedge aclk)
			begin
				if(m_icb_rsp_valid & m_icb_rsp_ready)
					// 从高位移入新的字
					cln_fetched_from_ext <= # SIM_DELAY {m_icb_rsp_rdata, cln_fetched_from_ext[CACHE_LINE_WORD_N*4*8-1:32]};
			end
		end
	endgenerate
	
	// 从外部取缓存行的字索引(独热码)
	generate
		if(CACHE_LINE_WORD_N == 1)
		begin
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					cln_fetched_word_id <= 1'b1;
				else if(m_icb_rsp_valid & m_icb_rsp_ready)
					cln_fetched_word_id <= # SIM_DELAY 1'b1;
			end
		end
		else
		begin
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					cln_fetched_word_id <= 1;
				else if(m_icb_rsp_valid & m_icb_rsp_ready)
					// 循环左移1位
					cln_fetched_word_id <= # SIM_DELAY 
						{cln_fetched_word_id[CACHE_LINE_WORD_N-2:0], cln_fetched_word_id[CACHE_LINE_WORD_N-1]};
			end
		end
	endgenerate
	
	/** 写缓存控制 **/
	wire[31:0] wbuf_addr; // 待存数据块的地址
	wire[CACHE_LINE_WORD_N*32-1:0] wbuf_data; // 待存数据块
	reg wbuf_valid; // 向写缓存存入数据块(有效标志)
	wire wbuf_access_fns; // 写缓存访问完成(标志)
	
	assign m_wbuf_axis_data = {wbuf_addr, wbuf_data};
	assign m_wbuf_axis_valid = wbuf_valid;
	
	/** 未命中处理 **/
	reg sel_swp_invld_cln; // 选择置换无效的缓存行(标志)
	reg[2:0] swp_invld_wip; // 待置换的无效缓存行的路编号
	wire[2:0] swp_cln_wip; // 待置换的缓存行的路编号
	wire[31:0] swp_cln_wbk_addr; // 待置换的缓存行的写回地址
	wire[CACHE_LINE_WORD_N*4*8-1:0] swp_cln_wbk_data; // 待置换的缓存行的写回数据
	wire swp_cln_dirty; // 待置换的缓存行是否脏
	reg[CACHE_WAY_N-1:0] swp_cache_way_sel; // 锁存的缓存路选择(独热码)
	reg[31:0] swp_cln_wbk_addr_latched; // 锁存的待置换的缓存行的写回地址
	reg[CACHE_LINE_WORD_N*4*8-1:0] swp_cln_wbk_data_latched; // 锁存的待置换的缓存行的写回数据
	reg swp_cln_dirty_latched; // 锁存的待置换的缓存行是否脏
	reg[1:0] miss_proc_sts; // 未命中处理的状态
	reg on_lacth_swp_cln_msg; // 锁存待置换缓存行信息(指示)
	reg on_lacth_swp_cln_msg_d1; // 延迟1clk的锁存待置换缓存行信息(指示)
	wire on_access_wbuf; // 访问写缓存(指示)
	wire[CACHE_LINE_WORD_N*32-1:0] datblk_fetched; // 取回的数据块
	reg[31:0] word_fetched; // 取回的字数据
	
	assign s_icb_rsp_rdata = 
		is_rd_cache ? (
			(miss_proc_sts == MISS_PROC_STS_RSP_TO_CPU) ? 
				word_fetched:
				cache_hit_word
		):32'hxxxx_xxxx;
	assign s_icb_rsp_err = 1'b0;
	assign s_icb_rsp_valid = 
		cache_rdata_valid & (
			((on_cache_rdata_valid & is_cache_hit) | cache_hit_pending) | 
			(miss_proc_sts == MISS_PROC_STS_RSP_TO_CPU)
		);
	
	assign m_icb_cmd_addr = 
		({cache_acs_addr_tag, cache_acs_addr_index, {clogb2(CACHE_LINE_WORD_N*4){1'b0}}} | 32'h0000_0000) + 
		(nxtlv_mem_acs_req_word_id * 4);
	assign m_icb_cmd_read = 1'b1;
	assign m_icb_cmd_wdata = 32'hxxxx_xxxx;
	assign m_icb_cmd_wmask = 4'b0000;
	assign m_icb_cmd_valid = nxtlv_mem_acs_valid;
	
	assign m_icb_rsp_ready = miss_proc_sts == MISS_PROC_STS_SWP_CLN;
	
	assign on_cache_miss_proc_done = (miss_proc_sts == MISS_PROC_STS_RSP_TO_CPU) & s_icb_rsp_ready;
	
	assign wbuf_addr = swp_cln_wbk_addr_latched;
	assign wbuf_data = swp_cln_wbk_data_latched;
	assign wbuf_access_fns = 
		(~on_lacth_swp_cln_msg) & (
			(~swp_cln_dirty_latched) | (
				(~on_lacth_swp_cln_msg_d1) & 
				((~wbuf_valid) | m_wbuf_axis_ready)
			)
		);
	
	assign swp_cln_wip = 
		sel_swp_invld_cln ? 
			swp_invld_wip:
			hot_tb_lru_wid;
	assign swp_cln_wbk_addr = cache_real_addr_arr[swp_cln_wip[((CACHE_WAY_N == 1) ? 0:clogb2(CACHE_WAY_N-1)):0]];
	assign swp_cln_wbk_data = cache_dout_arr[swp_cln_wip[((CACHE_WAY_N == 1) ? 0:clogb2(CACHE_WAY_N-1)):0]];
	assign swp_cln_dirty = cache_dirty_arr[swp_cln_wip[((CACHE_WAY_N == 1) ? 0:clogb2(CACHE_WAY_N-1)):0]];
	
	assign on_access_wbuf = on_lacth_swp_cln_msg_d1 & swp_cln_dirty_latched;
	
	assign datblk_fetched = 
		wbuf_cln_found_flag_r ? 
			wbuf_sch_datblk_r:
			cln_fetched_from_ext;
	
	// 从外部取缓存行完成(标志)
	always @(posedge aclk)
	begin
		if(miss_proc_sts != MISS_PROC_STS_SWP_CLN)
			cln_ext_fetch_fns <= # SIM_DELAY 1'b0;
		else if(~cln_ext_fetch_fns)
			cln_ext_fetch_fns <= # SIM_DELAY m_icb_rsp_valid & m_icb_rsp_ready & cln_fetched_word_id[CACHE_LINE_WORD_N-1];
	end
	
	// 向写缓存存入数据块(有效标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wbuf_valid <= 1'b0;
		else
			wbuf_valid <= # SIM_DELAY 
				wbuf_valid ? 
					(~m_wbuf_axis_ready):
					on_access_wbuf;
	end
	
	// 选择置换无效的缓存行(标志)
	always @(posedge aclk)
	begin
		if(on_cache_rdata_valid & (~is_cache_hit))
			sel_swp_invld_cln <= # SIM_DELAY has_invalid_cln;
	end
	
	// 待置换的无效缓存行的路编号
	always @(posedge aclk)
	begin
		if(on_cache_rdata_valid & (~is_cache_hit) & has_invalid_cln)
			swp_invld_wip <= # SIM_DELAY hot_tb_acs_wid;
	end
	
	// 锁存的缓存路选择(独热码), 锁存的待置换的缓存行的写回地址, 锁存的待置换的缓存行的写回数据, 锁存的待置换的缓存行是否脏
	always @(posedge aclk)
	begin
		if(on_lacth_swp_cln_msg)
		begin
			swp_cache_way_sel <= # SIM_DELAY 
				(CACHE_WAY_N == 1) ? 1'b1:
				(CACHE_WAY_N == 2) ? {
					swp_cln_wip[0] == 1'b1,
					swp_cln_wip[0] == 1'b0
				}:
				(CACHE_WAY_N == 4) ? {
					swp_cln_wip[1:0] == 2'b11,
					swp_cln_wip[1:0] == 2'b10,
					swp_cln_wip[1:0] == 2'b01,
					swp_cln_wip[1:0] == 2'b00
				}:
				{
					swp_cln_wip[2:0] == 3'b111,
					swp_cln_wip[2:0] == 3'b110,
					swp_cln_wip[2:0] == 3'b101,
					swp_cln_wip[2:0] == 3'b100,
					swp_cln_wip[2:0] == 3'b011,
					swp_cln_wip[2:0] == 3'b010,
					swp_cln_wip[2:0] == 3'b001,
					swp_cln_wip[2:0] == 3'b000
				};
			swp_cln_wbk_addr_latched <= # SIM_DELAY swp_cln_wbk_addr;
			swp_cln_wbk_data_latched <= # SIM_DELAY swp_cln_wbk_data;
			swp_cln_dirty_latched <= # SIM_DELAY swp_cln_dirty;
		end
	end
	
	// 未命中处理的状态
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			miss_proc_sts <= MISS_PROC_STS_NORMAL;
		else
		begin
			case(miss_proc_sts)
				MISS_PROC_STS_NORMAL: // 状态: 正常
				begin
					if(on_cache_miss)
						miss_proc_sts <= # SIM_DELAY MISS_PROC_STS_SWP_CLN;
				end
				MISS_PROC_STS_SWP_CLN: // 状态: 置换缓存行
				begin
					if(cln_fetch_fns & wbuf_access_fns)
						miss_proc_sts <= # SIM_DELAY MISS_PROC_STS_UPD_CLN;
				end
				MISS_PROC_STS_UPD_CLN: // 状态: 更新缓存行
				begin
					miss_proc_sts <= # SIM_DELAY MISS_PROC_STS_RSP_TO_CPU;
				end
				MISS_PROC_STS_RSP_TO_CPU: // 状态: 返回响应
				begin
					if(s_icb_rsp_ready)
						miss_proc_sts <= # SIM_DELAY MISS_PROC_STS_NORMAL;
				end
				default:
					miss_proc_sts <= # SIM_DELAY MISS_PROC_STS_NORMAL;
			endcase
		end
	end
	
	// 锁存待置换缓存行信息(指示), 延迟1clk的锁存待置换缓存行信息(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
		begin
			on_lacth_swp_cln_msg <= 1'b0;
			on_lacth_swp_cln_msg_d1 <= 1'b0;
		end
		else
		begin
			on_lacth_swp_cln_msg <= # SIM_DELAY (miss_proc_sts == MISS_PROC_STS_NORMAL) & on_cache_miss;
			on_lacth_swp_cln_msg_d1 <= # SIM_DELAY on_lacth_swp_cln_msg;
		end
	end
	
	// 取回的字数据
	always @(posedge aclk)
	begin
		if(miss_proc_sts == MISS_PROC_STS_UPD_CLN)
			word_fetched <= # SIM_DELAY datblk_fetched >> (cache_acs_addr_word_ofs * 32);
	end
	
	/** 访问标签存储器 **/
	wire sel_tag_getting_tag_mem_port; // 选择TAG获取给出的存储器端口
	wire sel_wt_hit_upd_tag_mem_port; // 选择写命中后更新标志给出的存储器端口
	wire sel_miss_proc_tag_mem_port; // 选择未命中处理给出的存储器端口
	// [TAG获取给出的存储器端口]
	wire tag_getting_tag_mem_ren; // 存储器读使能
	wire[31:0] tag_getting_tag_mem_addr_index; // 存储器访问地址(index)
	wire[CACHE_TAG_WIDTH-1:0] tag_getting_tag_for_cmp; // 待匹配的tag
	// [写命中后更新标志给出的存储器端口]
	wire[CACHE_WAY_N-1:0] wt_hit_upd_tag_mem_wen; // 存储器写使能
	wire[31:0] wt_hit_upd_tag_mem_addr_index; // 存储器访问地址(index)
	wire[CACHE_TAG_WIDTH-1:0] wt_hit_upd_tag_mem_din_tag; // 存储器写数据(tag)
	wire wt_hit_upd_tag_mem_din_valid; // 存储器写数据(valid)
	wire wt_hit_upd_tag_mem_din_dirty; // 存储器写数据(dirty)
	// [未命中处理给出的存储器端口]
	wire[CACHE_WAY_N-1:0] miss_proc_tag_mem_wen; // 存储器写使能
	wire[31:0] miss_proc_tag_mem_addr_index; // 存储器访问地址(index)
	wire[CACHE_TAG_WIDTH-1:0] miss_proc_tag_mem_din_tag; // 存储器写数据(tag)
	wire miss_proc_tag_mem_din_valid; // 存储器写数据(valid)
	wire miss_proc_tag_mem_din_dirty; // 存储器写数据(dirty)
	
	genvar acs_cache_tag_mem_i;
	generate
		for(acs_cache_tag_mem_i = 0;acs_cache_tag_mem_i < CACHE_WAY_N;acs_cache_tag_mem_i = acs_cache_tag_mem_i + 1)
		begin:acs_cache_tag_mem_blk
			assign cache_tag_en_arr[acs_cache_tag_mem_i] = 
				(sel_tag_getting_tag_mem_port & tag_getting_tag_mem_ren) | 
				(sel_wt_hit_upd_tag_mem_port & wt_hit_upd_tag_mem_wen[acs_cache_tag_mem_i]) | 
				(sel_miss_proc_tag_mem_port & miss_proc_tag_mem_wen[acs_cache_tag_mem_i]);
			assign cache_tag_wen_arr[acs_cache_tag_mem_i] = 
				(sel_tag_getting_tag_mem_port & 1'b0) | 
				(sel_wt_hit_upd_tag_mem_port & wt_hit_upd_tag_mem_wen[acs_cache_tag_mem_i]) | 
				(sel_miss_proc_tag_mem_port & miss_proc_tag_mem_wen[acs_cache_tag_mem_i]);
			assign cache_tag_index_arr[acs_cache_tag_mem_i] = 
				({32{sel_tag_getting_tag_mem_port}} & tag_getting_tag_mem_addr_index) | 
				({32{sel_wt_hit_upd_tag_mem_port}} & wt_hit_upd_tag_mem_addr_index) | 
				({32{sel_miss_proc_tag_mem_port}} & miss_proc_tag_mem_addr_index);
			assign cache_tag_arr[acs_cache_tag_mem_i] = 
				({CACHE_TAG_WIDTH{sel_tag_getting_tag_mem_port}} & tag_getting_tag_for_cmp) | 
				({CACHE_TAG_WIDTH{sel_wt_hit_upd_tag_mem_port}} & wt_hit_upd_tag_mem_din_tag) | 
				({CACHE_TAG_WIDTH{sel_miss_proc_tag_mem_port}} & miss_proc_tag_mem_din_tag);
			assign cache_valid_new_arr[acs_cache_tag_mem_i] = 
				(sel_tag_getting_tag_mem_port & 1'bx) | 
				(sel_wt_hit_upd_tag_mem_port & wt_hit_upd_tag_mem_din_valid) | 
				(sel_miss_proc_tag_mem_port & miss_proc_tag_mem_din_valid);
			assign cache_dirty_new_arr[acs_cache_tag_mem_i] = 
				(sel_tag_getting_tag_mem_port & 1'bx) | 
				(sel_wt_hit_upd_tag_mem_port & wt_hit_upd_tag_mem_din_dirty) | 
				(sel_miss_proc_tag_mem_port & miss_proc_tag_mem_din_dirty);
		end
	endgenerate
	
	assign sel_tag_getting_tag_mem_port = s_icb_cmd_valid & s_icb_cmd_ready;
	assign sel_wt_hit_upd_tag_mem_port = on_cache_wt_hit_upd;
	assign sel_miss_proc_tag_mem_port = on_lacth_swp_cln_msg;
	
	assign tag_getting_tag_mem_ren = s_icb_cmd_valid;
	assign tag_getting_tag_mem_addr_index = 
		s_icb_cmd_addr[clogb2(CACHE_ENTRY_N*CACHE_LINE_WORD_N*4-1):clogb2(CACHE_LINE_WORD_N*4)] | 32'h0000_0000;
	assign tag_getting_tag_for_cmp = 
		s_icb_cmd_addr[clogb2(CACHE_ENTRY_N*CACHE_LINE_WORD_N*4)+CACHE_TAG_WIDTH-1:clogb2(CACHE_ENTRY_N*CACHE_LINE_WORD_N*4)];
	
	assign wt_hit_upd_tag_mem_wen = cache_hit_arr;
	assign wt_hit_upd_tag_mem_addr_index = cache_acs_addr_index | 32'h0000_0000;
	assign wt_hit_upd_tag_mem_din_tag = cache_acs_addr_tag;
	assign wt_hit_upd_tag_mem_din_valid = 1'b1;
	assign wt_hit_upd_tag_mem_din_dirty = 1'b1;
	
	assign miss_proc_tag_mem_wen = 
		(CACHE_WAY_N == 1) ? 1'b1:
		(CACHE_WAY_N == 2) ? {
			swp_cln_wip[0] == 1'b1,
			swp_cln_wip[0] == 1'b0
		}:
		(CACHE_WAY_N == 4) ? {
			swp_cln_wip[1:0] == 2'b11,
			swp_cln_wip[1:0] == 2'b10,
			swp_cln_wip[1:0] == 2'b01,
			swp_cln_wip[1:0] == 2'b00
		}:
		{
			swp_cln_wip[2:0] == 3'b111,
			swp_cln_wip[2:0] == 3'b110,
			swp_cln_wip[2:0] == 3'b101,
			swp_cln_wip[2:0] == 3'b100,
			swp_cln_wip[2:0] == 3'b011,
			swp_cln_wip[2:0] == 3'b010,
			swp_cln_wip[2:0] == 3'b001,
			swp_cln_wip[2:0] == 3'b000
		};
	assign miss_proc_tag_mem_addr_index = cache_acs_addr_index | 32'h0000_0000;
	assign miss_proc_tag_mem_din_tag = cache_acs_addr_tag;
	assign miss_proc_tag_mem_din_valid = 1'b1;
	assign miss_proc_tag_mem_din_dirty = ~is_rd_cache;
	
	/** 访问数据存储器 **/
	wire sel_rd_cache_data_mem_port; // 选择读Cache给出的存储器端口
	wire sel_wt_cache_data_mem_port; // 选择写Cache给出的存储器端口
	// [读Cache给出的存储器端口]
	wire rd_cache_data_mem_ren; // 存储器读使能
	wire[31:0] rd_cache_data_mem_addr_index; // 存储器访问地址(index)
	// [写Cache给出的存储器端口]
	wire[CACHE_WAY_N-1:0] wt_cache_data_mem_en; // 存储器使能
	wire[CACHE_LINE_WORD_N*4-1:0] wt_cache_data_mem_wen; // 存储器字节写使能
	wire[31:0] wt_cache_data_mem_addr_index; // 存储器访问地址(index)
	wire[CACHE_LINE_WORD_N*4*8-1:0] wt_cache_data_mem_din; // 存储器写数据
	wire[CACHE_LINE_WORD_N*32-1:0] datblk_modified; // 修改后的数据块
	
	genvar acs_cache_data_mem_i;
	generate
		for(acs_cache_data_mem_i = 0;acs_cache_data_mem_i < CACHE_WAY_N;acs_cache_data_mem_i = acs_cache_data_mem_i + 1)
		begin:acs_cache_data_mem_blk
			assign cache_data_en_arr[acs_cache_data_mem_i] = 
				(sel_rd_cache_data_mem_port & rd_cache_data_mem_ren) | 
				(sel_wt_cache_data_mem_port & wt_cache_data_mem_en[acs_cache_data_mem_i]);
			assign cache_data_byte_wen_arr[acs_cache_data_mem_i] = 
				({(CACHE_LINE_WORD_N*4){sel_rd_cache_data_mem_port}} & {(CACHE_LINE_WORD_N*4){1'b0}}) | 
				({(CACHE_LINE_WORD_N*4){sel_wt_cache_data_mem_port}} & wt_cache_data_mem_wen);
			assign cache_data_index_arr[acs_cache_data_mem_i] = 
				({32{sel_rd_cache_data_mem_port}} & rd_cache_data_mem_addr_index) | 
				({32{sel_wt_cache_data_mem_port}} & wt_cache_data_mem_addr_index);
			assign cache_din_arr[acs_cache_data_mem_i] = 
				({(CACHE_LINE_WORD_N*4*8){sel_rd_cache_data_mem_port}} & {(CACHE_LINE_WORD_N*4*8){1'bx}}) | 
				({(CACHE_LINE_WORD_N*4*8){sel_wt_cache_data_mem_port}} & wt_cache_data_mem_din);
		end
	endgenerate
	
	assign sel_rd_cache_data_mem_port = s_icb_cmd_valid & s_icb_cmd_ready;
	assign sel_wt_cache_data_mem_port = on_cache_wt_hit_upd | (miss_proc_sts == MISS_PROC_STS_UPD_CLN);
	
	assign rd_cache_data_mem_ren = s_icb_cmd_valid;
	assign rd_cache_data_mem_addr_index = 
		s_icb_cmd_addr[clogb2(CACHE_ENTRY_N*CACHE_LINE_WORD_N*4-1):clogb2(CACHE_LINE_WORD_N*4)] | 32'h0000_0000;
	
	assign wt_cache_data_mem_en = 
		(miss_proc_sts == MISS_PROC_STS_UPD_CLN) ? 
			swp_cache_way_sel:
			cache_hit_arr;
	assign wt_cache_data_mem_wen = 
		(miss_proc_sts == MISS_PROC_STS_UPD_CLN) ? 
			{(CACHE_LINE_WORD_N*4){1'b1}}:
			cache_wt_byte_en;
	assign wt_cache_data_mem_addr_index = cache_acs_addr_index | 32'h0000_0000;
	assign wt_cache_data_mem_din = 
		(miss_proc_sts == MISS_PROC_STS_UPD_CLN) ? 
			datblk_modified:
			{CACHE_LINE_WORD_N{cache_wdata}};
	
	genvar datblk_modified_i;
	generate
		for(datblk_modified_i = 0;datblk_modified_i < CACHE_LINE_WORD_N*4;datblk_modified_i = datblk_modified_i + 1)
		begin:datblk_modified_blk
			assign datblk_modified[datblk_modified_i*8+7:datblk_modified_i*8] = 
				cache_wt_byte_en[datblk_modified_i] ? 
					cache_wdata[(datblk_modified_i%4)*8+7:(datblk_modified_i%4)*8]:
					datblk_fetched[datblk_modified_i*8+7:datblk_modified_i*8];
		end
	endgenerate
	
	/** 访问热度表 **/
	assign hot_tb_en = on_cache_rdata_valid;
	assign hot_tb_upd_en = on_cache_rdata_valid;
	assign hot_tb_cid = cache_acs_addr_index | 32'h0000_0000;
	assign hot_tb_acs_wid = 
		is_cache_hit ? (
			(CACHE_WAY_N == 1) ? 3'b000:
			(CACHE_WAY_N == 2) ? (
				cache_hit_arr[0] ? 3'b000:
				                   3'b001
			):
			(CACHE_WAY_N == 4) ? (
				({3{cache_hit_arr[0]}} & 3'b000) | 
				({3{cache_hit_arr[1]}} & 3'b001) | 
				({3{cache_hit_arr[2]}} & 3'b010) | 
				({3{cache_hit_arr[3]}} & 3'b011)
			):(
				({3{cache_hit_arr[0]}} & 3'b000) | 
				({3{cache_hit_arr[1]}} & 3'b001) | 
				({3{cache_hit_arr[2]}} & 3'b010) | 
				({3{cache_hit_arr[3]}} & 3'b011) | 
				({3{cache_hit_arr[4]}} & 3'b100) | 
				({3{cache_hit_arr[5]}} & 3'b101) | 
				({3{cache_hit_arr[6]}} & 3'b110) | 
				({3{cache_hit_arr[7]}} & 3'b111)
			)
		):(
			has_invalid_cln ? (
				(CACHE_WAY_N == 1) ? 3'b000:
				(CACHE_WAY_N == 2) ? (
					(~cache_valid_arr[0]) ? 3'b000:
					                        3'b001
				):
				(CACHE_WAY_N == 4) ? (
					({3{~cache_valid_arr[0]}} & 3'b000) | 
					({3{(&cache_valid_arr[0:0]) & (~cache_valid_arr[1])}} & 3'b001) | 
					({3{(&cache_valid_arr[1:0]) & (~cache_valid_arr[2])}} & 3'b010) | 
					({3{(&cache_valid_arr[2:0]) & (~cache_valid_arr[3])}} & 3'b011)
				):(
					({3{~cache_valid_arr[0]}} & 3'b000) | 
					({3{(&cache_valid_arr[0:0]) & (~cache_valid_arr[1])}} & 3'b001) | 
					({3{(&cache_valid_arr[1:0]) & (~cache_valid_arr[2])}} & 3'b010) | 
					({3{(&cache_valid_arr[2:0]) & (~cache_valid_arr[3])}} & 3'b011) | 
					({3{(&cache_valid_arr[3:0]) & (~cache_valid_arr[4])}} & 3'b100) | 
					({3{(&cache_valid_arr[4:0]) & (~cache_valid_arr[5])}} & 3'b101) | 
					({3{(&cache_valid_arr[5:0]) & (~cache_valid_arr[6])}} & 3'b110) | 
					({3{(&cache_valid_arr[6:0]) & (~cache_valid_arr[7])}} & 3'b111)
				)
			):3'b000
		);
	assign hot_tb_init_item = (~is_cache_hit) & (~cache_valid_arr[0]);
	assign hot_tb_swp_lru_item = (~is_cache_hit) & (~has_invalid_cln);
	
endmodule
