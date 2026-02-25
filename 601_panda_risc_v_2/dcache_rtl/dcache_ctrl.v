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
缓存CPU侧AXI从机给出的写数据
对CPU侧AXI从机进行读写仲裁
cache缺失时读下级存储器, 将待替换的脏缓存行送入写缓存

cache读/写命中均可实现无阻塞访问(访问请求 -----1clk----> 访问响应)

----------------------------------------------------------
|    存储器端口   |               访问情形               |
----------------------------------------------------------
| 数据存储器端口A |  写命中, 缺失时读下级存储器          |
----------------------------------------------------------
| 数据存储器端口B |  cache访问, 取待替换的脏缓存行       |
----------------------------------------------------------
| 标签存储器端口A |  cache访问                           |
----------------------------------------------------------
| 标签存储器端口B |  写命中, 缺失时更新缓存行            |
----------------------------------------------------------
|    热度表       |  cache访问的下1clk                   |
----------------------------------------------------------

注意：
CPU侧AXI从机的读写地址必须对齐到缓存数据位宽对应的字节数, 即能够被(CACHE_DATA_WIDTH/8)所整除

对于读下级存储器(AXI主机), R通道至少应具有1clk时延(m_axi_arvalid & m_axi_arready -----至少1clk----> m_axi_rvalid)

协议:
AXI-Lite SLAVE
AXI MASTER(READ ONLY)
AXIS MASTER

作者: 陈家耀
日期: 2026/02/25
********************************************************************/


module dcache_ctrl #(
	parameter integer CACHE_WAY_N = 4, // 缓存路数(1 | 2 | 4 | 8)
	parameter integer CACHE_ENTRY_N = 512, // 缓存存储条目数
	parameter integer CACHE_DATA_WIDTH = 32, // 缓存数据位宽(32 | 64 | 128 | 256)
	parameter integer CACHE_LINE_DATA_N = 8, // 每个缓存行的数据个数(1 | 2 | 4 | 8 | 16)
	parameter integer CACHE_TAG_WIDTH = 12, // 缓存标签位数
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// CPU侧AXI从机
	// [AR通道]
	input wire[31:0] s_axi_araddr,
	input wire s_axi_arvalid,
	output wire s_axi_arready,
	// [R通道]
	output wire[CACHE_DATA_WIDTH-1:0] s_axi_rdata,
	output wire[1:0] s_axi_rresp, // const -> 2'b00(OKAY)
	output wire s_axi_rlast, // const -> 1'b1
	output wire s_axi_rvalid,
	input wire s_axi_rready,
	// [AW通道]
	input wire[31:0] s_axi_awaddr,
	input wire s_axi_awvalid,
	output wire s_axi_awready,
	// [B通道]
	output wire[1:0] s_axi_bresp, // const -> 2'b00(OKAY)
	output wire s_axi_bvalid,
	input wire s_axi_bready,
	// [W通道]
	input wire[CACHE_DATA_WIDTH-1:0] s_axi_wdata,
	input wire[CACHE_DATA_WIDTH/8-1:0] s_axi_wstrb,
	input wire s_axi_wlast, // aussumed to be 1'b1
	input wire s_axi_wvalid,
	output wire s_axi_wready,
	
	// 读下级存储器(AXI主机)
	// [AR通道]
	output wire[31:0] m_axi_araddr,
	output wire[1:0] m_axi_arburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_arlen, // const -> CACHE_LINE_DATA_N - 1
	output wire[2:0] m_axi_arsize, // const -> clogb2(CACHE_DATA_WIDTH/8)
	output wire m_axi_arvalid,
	input wire m_axi_arready,
	// [R通道]
	input wire[CACHE_DATA_WIDTH-1:0] m_axi_rdata,
	input wire[1:0] m_axi_rresp, // ignored
	input wire m_axi_rlast, // ignored
	input wire m_axi_rvalid,
	output wire m_axi_rready, // const -> 1'b1
	
	// 待写的缓存行(AXIS主机)
	output wire[32+CACHE_LINE_DATA_N*CACHE_DATA_WIDTH-1:0] m_wbuf_axis_data, // {缓存行地址(32位), 缓存行数据块(CACHE_LINE_DATA_N*CACHE_DATA_WIDTH位)}
	output wire m_wbuf_axis_valid,
	input wire m_wbuf_axis_ready,
	
	// 写缓存检索
	output wire[31:0] wbuf_sch_addr, // 检索地址
	input wire wbuf_cln_found_flag, // 在写缓存里找到缓存行(标志)
	input wire[CACHE_LINE_DATA_N*CACHE_DATA_WIDTH-1:0] wbuf_sch_datblk, // 检索到的数据块
	
	// 查询或更新热度表
	output wire hot_tb_en, // 热度表使能
	output wire hot_tb_upd_en, // 热度表更新使能
	output wire[31:0] hot_tb_cid, // 待查询或更新的缓存项的索引号
	output wire[2:0] hot_tb_acs_wid, // 本次访问的缓存路编号
	output wire hot_tb_init_item, // 初始化热度项(标志)
	output wire hot_tb_swp_lru_item, // 置换最近最少使用项(标志)
	input wire[2:0] hot_tb_lru_wid, // 最近最少使用项的缓存路编号
	
	// 逻辑Cache存储器接口
	// [数据存储器端口A]
	output wire[CACHE_WAY_N-1:0] cache_data_en_a, // 数据存储器使能
	output wire[CACHE_WAY_N*(CACHE_DATA_WIDTH/8)-1:0] cache_data_byte_wen_a, // 数据存储器字节写使能
	output wire[CACHE_WAY_N*32-1:0] cache_data_addr_index_a, // 数据存储器访问索引号
	output wire[CACHE_WAY_N*8-1:0] cache_data_addr_ofs_a, // 数据存储器访问数据偏移量
	output wire[CACHE_WAY_N*CACHE_DATA_WIDTH-1:0] cache_din_a, // 缓存行写数据
	input wire[CACHE_WAY_N*CACHE_DATA_WIDTH-1:0] cache_dout_a, // 缓存行读数据
	// [数据存储器端口B]
	output wire[CACHE_WAY_N-1:0] cache_data_en_b, // 数据存储器使能
	output wire[CACHE_WAY_N*(CACHE_DATA_WIDTH/8)-1:0] cache_data_byte_wen_b, // 数据存储器字节写使能
	output wire[CACHE_WAY_N*32-1:0] cache_data_addr_index_b, // 数据存储器访问索引号
	output wire[CACHE_WAY_N*8-1:0] cache_data_addr_ofs_b, // 数据存储器访问数据偏移量
	output wire[CACHE_WAY_N*CACHE_DATA_WIDTH-1:0] cache_din_b, // 缓存行写数据
	input wire[CACHE_WAY_N*CACHE_DATA_WIDTH-1:0] cache_dout_b, // 缓存行读数据
	// [标签存储器端口A]
	output wire[CACHE_WAY_N-1:0] cache_tag_en_a, // 标签存储器使能
	output wire[CACHE_WAY_N-1:0] cache_tag_wen_a, // 标签存储器写使能
	output wire[CACHE_WAY_N*32-1:0] cache_tag_addr_index_a, // 标签存储器访问索引号
	output wire[CACHE_WAY_N*8-1:0] cache_tag_addr_ofs_a, // 标签存储器访问数据偏移量
	output wire[CACHE_WAY_N*CACHE_TAG_WIDTH-1:0] cache_tag_addr_tag_a, // 标签存储器访问缓存行标签
	output wire[CACHE_WAY_N-1:0] cache_tag_din_valid_a, // 标签存储器待写的有效标志
	output wire[CACHE_WAY_N-1:0] cache_tag_din_dirty_a, // 标签存储器待写的脏标志
	input wire[CACHE_WAY_N*32-1:0] cache_tag_dout_real_addr_a, // 缓存行的实际基地址
	input wire[CACHE_WAY_N*CACHE_TAG_WIDTH-1:0] cache_tag_dout_org_tag_a, // 原来的缓存行地址标签
	input wire[CACHE_WAY_N-1:0] cache_tag_dout_hit_a, // 缓存行命中(标志)
	input wire[CACHE_WAY_N-1:0] cache_tag_dout_valid_a, // 缓存行有效(标志)
	input wire[CACHE_WAY_N-1:0] cache_tag_dout_dirty_a, // 缓存行脏(标志)
	// [标签存储器端口B]
	output wire[CACHE_WAY_N-1:0] cache_tag_en_b, // 标签存储器使能
	output wire[CACHE_WAY_N-1:0] cache_tag_wen_b, // 标签存储器写使能
	output wire[CACHE_WAY_N*32-1:0] cache_tag_addr_index_b, // 标签存储器访问索引号
	output wire[CACHE_WAY_N*CACHE_TAG_WIDTH-1:0] cache_tag_din_tag_b, // 标签存储器访问缓存行标签
	output wire[CACHE_WAY_N-1:0] cache_tag_din_valid_b, // 标签存储器待写的有效标志
	output wire[CACHE_WAY_N-1:0] cache_tag_din_dirty_b, // 标签存储器待写的脏标志
	input wire[CACHE_WAY_N-1:0] cache_tag_dout_valid_b, // 缓存行有效(标志)
	input wire[CACHE_WAY_N-1:0] cache_tag_dout_dirty_b, // 缓存行脏(标志)
	
	// Cache性能监测
	output wire[31:0] cache_access_total_n, // cache访问总次数(计数器)
	output wire[31:0] cache_hit_total_n, // cache命中总次数(计数器)
	output wire[31:0] cache_rd_hit_n, // cache读命中次数(计数器)
	output wire[31:0] cache_wr_hit_n, // cache写命中次数(计数器)
	output wire[31:0] cache_replace_dirty_line_n // cache替换脏的缓存行次数(计数器)
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
	
	/** CPU侧写数据缓存区 **/
	reg[CACHE_DATA_WIDTH-1:0] cpu_side_wdata_table_data[0:3]; // 写数据
	reg[CACHE_DATA_WIDTH/8-1:0] cpu_side_wdata_table_mask[0:3]; // 写字节掩码
	reg[3:0] cpu_side_wdata_table_vld_flag; // 有效标志
	reg[1:0] cpu_side_wdata_table_wptr; // 写指针
	reg[1:0] cpu_side_wdata_table_rptr; // 读指针
	reg cpu_side_wdata_table_full_n; // 不满标志
	wire on_query_cpu_side_wdata_table; // 查询缓存区(指示)
	wire[1:0] cpu_side_wdata_entry_id_to_query; // 待查询的缓存区条目ID
	reg pending_for_cpu_side_wdata_flag; // 等待写数据(标志)
	reg[1:0] cpu_side_wdata_entry_id_pending; // 正在等待存入的缓存区条目ID
	reg[CACHE_DATA_WIDTH-1:0] cpu_side_wdata_found; // 查到的写数据
	reg[CACHE_DATA_WIDTH/8-1:0] cpu_side_wmask_found; // 查到的写字节掩码
	
	assign s_axi_wready = cpu_side_wdata_table_full_n;
	
	/*
	CPU侧写数据缓存区的存储内容(写数据, 写字节掩码)
	CPU侧写数据缓存区的标志(有效标志)
	*/
	genvar cpu_side_wdata_table_entry_i;
	generate
		for(cpu_side_wdata_table_entry_i = 0;cpu_side_wdata_table_entry_i < 4;
			cpu_side_wdata_table_entry_i = cpu_side_wdata_table_entry_i + 1)
		begin:cpu_side_wdata_table_blk
			always @(posedge aclk)
			begin
				if(s_axi_wvalid & s_axi_wready & (cpu_side_wdata_table_wptr == cpu_side_wdata_table_entry_i))
				begin
					cpu_side_wdata_table_data[cpu_side_wdata_table_entry_i] <= # SIM_DELAY s_axi_wdata;
					cpu_side_wdata_table_mask[cpu_side_wdata_table_entry_i] <= # SIM_DELAY s_axi_wstrb;
				end
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					cpu_side_wdata_table_vld_flag[cpu_side_wdata_table_entry_i] <= 1'b0;
				else if(
					(s_axi_wvalid & s_axi_wready & (cpu_side_wdata_table_wptr == cpu_side_wdata_table_entry_i)) | 
					(s_axi_bvalid & s_axi_bready & (cpu_side_wdata_table_rptr == cpu_side_wdata_table_entry_i))
				)
					cpu_side_wdata_table_vld_flag[cpu_side_wdata_table_entry_i] <= # SIM_DELAY 
						s_axi_wvalid & s_axi_wready & (cpu_side_wdata_table_wptr == cpu_side_wdata_table_entry_i);
			end
		end
	endgenerate
	
	// CPU侧写数据缓存区写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cpu_side_wdata_table_wptr <= 2'd0;
		else if(s_axi_wvalid & s_axi_wready)
			cpu_side_wdata_table_wptr <= # SIM_DELAY cpu_side_wdata_table_wptr + 1'b1;
	end
	
	// CPU侧写数据缓存区读指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cpu_side_wdata_table_rptr <= 2'd0;
		else if(s_axi_bvalid & s_axi_bready)
			cpu_side_wdata_table_rptr <= # SIM_DELAY cpu_side_wdata_table_rptr + 1'b1;
	end
	
	// CPU侧写数据缓存区不满标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cpu_side_wdata_table_full_n <= 1'b1;
		else if((s_axi_wvalid & s_axi_wready) ^ (s_axi_bvalid & s_axi_bready))
			cpu_side_wdata_table_full_n <= # SIM_DELAY 
				(s_axi_bvalid & s_axi_bready) | 
				(~(&(cpu_side_wdata_table_vld_flag | (1 << cpu_side_wdata_table_wptr))));
	end
	
	// 等待CPU侧写数据(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			pending_for_cpu_side_wdata_flag <= 1'b0;
		else if(
			pending_for_cpu_side_wdata_flag ? 
				(s_axi_wvalid & s_axi_wready & (cpu_side_wdata_table_wptr == cpu_side_wdata_entry_id_pending)): // 从CPU侧AXI从机得到
				(
					on_query_cpu_side_wdata_table & 
					(~(
						cpu_side_wdata_table_vld_flag[cpu_side_wdata_entry_id_to_query] | // 从写数据缓存区得到
						(s_axi_wvalid & s_axi_wready & (cpu_side_wdata_table_wptr == cpu_side_wdata_entry_id_to_query)) // 从CPU侧AXI从机得到
					))
				)
		)
			pending_for_cpu_side_wdata_flag <= # SIM_DELAY 
				~pending_for_cpu_side_wdata_flag;
	end
	
	// 正在等待存入的缓存区条目ID
	always @(posedge aclk)
	begin
		if(
			(~pending_for_cpu_side_wdata_flag) & 
			on_query_cpu_side_wdata_table & 
			(~(
				cpu_side_wdata_table_vld_flag[cpu_side_wdata_entry_id_to_query] | // 从写数据缓存区得到
				(s_axi_wvalid & s_axi_wready & (cpu_side_wdata_table_wptr == cpu_side_wdata_entry_id_to_query)) // 从CPU侧AXI从机得到
			))
		)
			cpu_side_wdata_entry_id_pending <= # SIM_DELAY 
				cpu_side_wdata_entry_id_to_query;
	end
	
	// 查到的写数据, 查到的写字节掩码
	always @(posedge aclk)
	begin
		if(
			pending_for_cpu_side_wdata_flag ? 
				(s_axi_wvalid & s_axi_wready & (cpu_side_wdata_table_wptr == cpu_side_wdata_entry_id_pending)): // 从CPU侧AXI从机得到
				(
					on_query_cpu_side_wdata_table & 
					(
						cpu_side_wdata_table_vld_flag[cpu_side_wdata_entry_id_to_query] | // 从写数据缓存区得到
						(s_axi_wvalid & s_axi_wready & (cpu_side_wdata_table_wptr == cpu_side_wdata_entry_id_to_query)) // 从CPU侧AXI从机得到
					)
				)
		)
		begin
			cpu_side_wdata_found <= # SIM_DELAY 
				((~pending_for_cpu_side_wdata_flag) & cpu_side_wdata_table_vld_flag[cpu_side_wdata_entry_id_to_query]) ? 
					cpu_side_wdata_table_data[cpu_side_wdata_entry_id_to_query]:
					s_axi_wdata;
			
			cpu_side_wmask_found <= # SIM_DELAY 
				((~pending_for_cpu_side_wdata_flag) & cpu_side_wdata_table_vld_flag[cpu_side_wdata_entry_id_to_query]) ? 
					cpu_side_wdata_table_mask[cpu_side_wdata_entry_id_to_query]:
					s_axi_wstrb;
		end
	end
	
	/** CPU侧AXI从机读写仲裁 **/
	// CPU侧访问合并的命令通道
	wire[31:0] cpu_side_access_bus_cmd_addr; // 访问地址
	wire cpu_side_access_bus_cmd_is_read; // 是否读传输
	wire cpu_side_access_bus_cmd_valid;
	wire cpu_side_access_bus_cmd_ready;
	// CPU侧访问合并的响应通道
	wire[CACHE_DATA_WIDTH-1:0] cpu_side_access_bus_resp_rdata; // 读数据
	wire cpu_side_access_bus_resp_is_read; // 是否读传输
	wire cpu_side_access_bus_resp_valid;
	wire cpu_side_access_bus_resp_ready;
	// 仲裁信息缓存区
	reg[3:0] cpu_side_arb_msg_table_is_read; // 是否读传输
	reg[2:0] cpu_side_arb_msg_table_wptr; // 写指针
	wire[2:0] cpu_side_arb_msg_table_wptr_add1; // 写指针 + 1
	reg[2:0] cpu_side_arb_msg_table_rptr; // 读指针
	wire[2:0] cpu_side_arb_msg_table_rptr_add1; // 读指针 + 1
	reg cpu_side_arb_msg_table_full_n; // 不满标志
	reg cpu_side_arb_msg_table_empty_n; // 不空标志
	// 读写仲裁
	reg cpu_side_arb_grant_to_wr_chn_if_conflict; // 冲突时许可给写通道(标志)
	reg cpu_side_arb_locked_flag; // 仲裁锁定(标志)
	reg cpu_side_arb_locked_res_grant_to_wr_chn; // 锁定的仲裁结果是否为许可给写通道
	reg[5:0] cpu_side_wr_access_tid; // 写访问事务ID
	
	// [AR通道]
	assign s_axi_arready = 
		cpu_side_access_bus_cmd_ready & cpu_side_arb_msg_table_full_n & 
		(
			cpu_side_arb_locked_flag ? 
				(~cpu_side_arb_locked_res_grant_to_wr_chn): // 仲裁锁定许可给读通道
				((~s_axi_awvalid) | (~cpu_side_arb_grant_to_wr_chn_if_conflict))
		);
	// [R通道]
	assign s_axi_rdata = cpu_side_access_bus_resp_rdata;
	assign s_axi_rresp = 2'b00;
	assign s_axi_rlast = 1'b1;
	assign s_axi_rvalid = cpu_side_access_bus_resp_valid & cpu_side_access_bus_resp_is_read;
	// [AW通道]
	assign s_axi_awready = 
		cpu_side_access_bus_cmd_ready & cpu_side_arb_msg_table_full_n & 
		(
			cpu_side_arb_locked_flag ? 
				cpu_side_arb_locked_res_grant_to_wr_chn: // 仲裁锁定许可给写通道
				((~s_axi_arvalid) | cpu_side_arb_grant_to_wr_chn_if_conflict)
		);
	// [B通道]
	assign s_axi_bresp = 2'b00;
	assign s_axi_bvalid = cpu_side_access_bus_resp_valid & (~cpu_side_access_bus_resp_is_read);
	
	// [命令通道]
	assign cpu_side_access_bus_cmd_addr = 
		cpu_side_access_bus_cmd_is_read ? 
			s_axi_araddr:
			s_axi_awaddr;
	assign cpu_side_access_bus_cmd_is_read = 
		cpu_side_arb_locked_flag ? 
			(~cpu_side_arb_locked_res_grant_to_wr_chn): // 仲裁锁定许可给读通道
			(s_axi_arvalid & ((~s_axi_awvalid) | (~cpu_side_arb_grant_to_wr_chn_if_conflict)));
	assign cpu_side_access_bus_cmd_valid = 
		cpu_side_arb_msg_table_full_n & 
		(s_axi_arvalid | s_axi_awvalid);
	// [响应通道]
	assign cpu_side_access_bus_resp_is_read = 
		cpu_side_arb_msg_table_is_read[cpu_side_arb_msg_table_rptr[1:0]];
	assign cpu_side_access_bus_resp_ready = 
		// 说明: 能够保证仲裁信息缓存区非空
		cpu_side_access_bus_resp_is_read ? 
			s_axi_rready:
			s_axi_bready;
	
	assign on_query_cpu_side_wdata_table = 
		cpu_side_access_bus_cmd_valid & cpu_side_access_bus_cmd_ready & 
		(~cpu_side_access_bus_cmd_is_read);
	assign cpu_side_wdata_entry_id_to_query = 
		cpu_side_wr_access_tid[1:0];
	
	assign cpu_side_arb_msg_table_wptr_add1 = cpu_side_arb_msg_table_wptr + 1'b1;
	assign cpu_side_arb_msg_table_rptr_add1 = cpu_side_arb_msg_table_rptr + 1'b1;
	
	// 仲裁信息缓存区的存储内容(是否读传输)
	genvar cpu_side_arb_msg_table_entry_i;
	generate
		for(cpu_side_arb_msg_table_entry_i = 0;cpu_side_arb_msg_table_entry_i < 4;
			cpu_side_arb_msg_table_entry_i = cpu_side_arb_msg_table_entry_i + 1)
		begin:cpu_side_arb_msg_table_blk
			always @(posedge aclk)
			begin
				if(
					cpu_side_access_bus_cmd_valid & cpu_side_access_bus_cmd_ready & 
					(cpu_side_arb_msg_table_wptr[1:0] == cpu_side_arb_msg_table_entry_i)
				)
					cpu_side_arb_msg_table_is_read[cpu_side_arb_msg_table_entry_i] <= # SIM_DELAY 
						cpu_side_access_bus_cmd_is_read;
			end
		end
	endgenerate
	
	// 仲裁信息缓存区写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cpu_side_arb_msg_table_wptr <= 3'd0;
		else if(cpu_side_access_bus_cmd_valid & cpu_side_access_bus_cmd_ready)
			cpu_side_arb_msg_table_wptr <= # SIM_DELAY cpu_side_arb_msg_table_wptr_add1;
	end
	
	// 仲裁信息缓存区读指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cpu_side_arb_msg_table_rptr <= 3'd0;
		else if(cpu_side_access_bus_resp_valid & cpu_side_access_bus_resp_ready)
			cpu_side_arb_msg_table_rptr <= # SIM_DELAY cpu_side_arb_msg_table_rptr_add1;
	end
	
	// 仲裁信息缓存区不满标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cpu_side_arb_msg_table_full_n <= 1'b1;
		else if(
			(cpu_side_access_bus_cmd_valid & cpu_side_access_bus_cmd_ready) ^ 
			(cpu_side_access_bus_resp_valid & cpu_side_access_bus_resp_ready)
		)
			cpu_side_arb_msg_table_full_n <= # SIM_DELAY 
				(cpu_side_access_bus_resp_valid & cpu_side_access_bus_resp_ready) | 
				(~(
					(cpu_side_arb_msg_table_wptr_add1[2] ^ cpu_side_arb_msg_table_rptr[2]) & 
					(cpu_side_arb_msg_table_wptr_add1[1:0] == cpu_side_arb_msg_table_rptr[1:0])
				));
	end
	// 仲裁信息缓存区不空标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cpu_side_arb_msg_table_empty_n <= 1'b1;
		else if(
			(cpu_side_access_bus_cmd_valid & cpu_side_access_bus_cmd_ready) ^ 
			(cpu_side_access_bus_resp_valid & cpu_side_access_bus_resp_ready)
		)
			cpu_side_arb_msg_table_empty_n <= # SIM_DELAY 
				(cpu_side_access_bus_cmd_valid & cpu_side_access_bus_cmd_ready) | 
				(~(cpu_side_arb_msg_table_wptr[2:0] == cpu_side_arb_msg_table_rptr_add1[2:0]));
	end
	
	// CPU侧AXI从机读写冲突时许可给写通道(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cpu_side_arb_grant_to_wr_chn_if_conflict <= 1'b0;
		else if(
			(~cpu_side_arb_locked_flag) & 
			cpu_side_access_bus_cmd_valid & 
			s_axi_arvalid & s_axi_awvalid
		)
			cpu_side_arb_grant_to_wr_chn_if_conflict <= # SIM_DELAY 
				~cpu_side_arb_grant_to_wr_chn_if_conflict;
	end
	
	// CPU侧AXI从机读写仲裁锁定(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cpu_side_arb_locked_flag <= 1'b0;
		else if(
			cpu_side_arb_locked_flag ? 
				cpu_side_access_bus_cmd_ready:
				(cpu_side_access_bus_cmd_valid & (~cpu_side_access_bus_cmd_ready))
		)
			cpu_side_arb_locked_flag <= # SIM_DELAY 
				~cpu_side_arb_locked_flag;
	end
	
	// 锁定的CPU侧AXI从机读写仲裁结果是否为许可给写通道
	always @(posedge aclk)
	begin
		if(
			(~cpu_side_arb_locked_flag) & 
			cpu_side_access_bus_cmd_valid & (~cpu_side_access_bus_cmd_ready)
		)
			cpu_side_arb_locked_res_grant_to_wr_chn <= # SIM_DELAY 
				~(s_axi_arvalid & ((~s_axi_awvalid) | (~cpu_side_arb_grant_to_wr_chn_if_conflict)));
	end
	
	// CPU侧写访问事务ID
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cpu_side_wr_access_tid <= 6'd0;
		else if(
			cpu_side_access_bus_cmd_valid & cpu_side_access_bus_cmd_ready & 
			(~cpu_side_access_bus_cmd_is_read)
		)
			cpu_side_wr_access_tid <= # SIM_DELAY 
				cpu_side_wr_access_tid + 1'b1;
	end
	
	/**
	读下级存储器
	
	在发起读下级存储器事务时会检索写缓存, 若在写缓存能找到待读取的数据块, 则直接使用这个数据块, 而无需读下级存储器
	**/
	// 访问地址, 待合并的修改操作
	wire on_load_addr_for_rd_nxt_lv_mem; // 加载读下级存储器的访问地址(指示)
	wire[31:0] loading_addr_for_rd_nxt_lv_mem; // 待加载的读下级存储器的访问地址
	reg rd_nxt_lv_mem_initiated_by_write_access_flag; // 读下级存储器是因为写访问发起的(标志)
	reg[31:0] addr_for_rd_nxt_lv_mem; // 读下级存储器的访问地址
	wire[CACHE_DATA_WIDTH-1:0] wdata_to_merge_for_rd_nxt_lv_mem; // 读下级存储器待合并的写数据
	wire[CACHE_DATA_WIDTH/8-1:0] wmask_to_merge_for_rd_nxt_lv_mem; // 读下级存储器待合并的写字节掩码
	// 事务处理
	wire on_initiate_rd_nxt_lv_mem_tr; // 发起读下级存储器事务(指示)
	wire on_complete_rd_nxt_lv_mem_tr; // 完成读下级存储器事务(指示)
	reg pending_for_rd_nxt_lv_mem_tr_flag; // 等待读下级存储器事务完成(标志)
	reg rd_nxt_lv_mem_tr_addr_setup_flag; // 读下级存储器事务的地址已传输(标志)
	reg rd_data_blk_found_in_wbuf_flag; // 在写缓存里找到待读取的数据块(标志)
	reg[CACHE_LINE_DATA_N*CACHE_DATA_WIDTH-1:0] shifting_rd_data_blk_found_in_wbuf; // 在写缓存里找到的待读数据块
	reg[clogb2(CACHE_LINE_DATA_N-1):0] nxt_lv_mem_rdata_id_to_be_transmitted; // 读下级存储器待传输的数据ID
	// 写缓存行
	wire on_wr_cache_line; // 写缓存行(指示)
	wire[31:0] cache_line_index_to_be_written; // 待写缓存行的索引号
	wire[7:0] cache_line_data_ofs_to_be_written; // 待写缓存行的数据偏移量
	wire[CACHE_DATA_WIDTH-1:0] wr_cache_new_data; // 待写缓存行的新数据
	// 保存的访问数据
	reg[CACHE_DATA_WIDTH-1:0] cache_rd_access_data_saved;
	
	// [AR通道]
	assign m_axi_araddr = addr_for_rd_nxt_lv_mem & (~((CACHE_LINE_DATA_N * CACHE_DATA_WIDTH / 8) - 1));
	assign m_axi_arburst = 2'b01;
	assign m_axi_arlen = CACHE_LINE_DATA_N - 1;
	assign m_axi_arsize = clogb2(CACHE_DATA_WIDTH/8);
	assign m_axi_arvalid = 
		pending_for_rd_nxt_lv_mem_tr_flag ? 
			(~rd_nxt_lv_mem_tr_addr_setup_flag):
			(on_initiate_rd_nxt_lv_mem_tr & (~wbuf_cln_found_flag));
	// [R通道]
	assign m_axi_rready = 1'b1;
	
	assign wbuf_sch_addr = addr_for_rd_nxt_lv_mem & (~((CACHE_LINE_DATA_N * CACHE_DATA_WIDTH / 8) - 1));
	
	assign on_load_addr_for_rd_nxt_lv_mem = 
		cpu_side_access_bus_cmd_valid & cpu_side_access_bus_cmd_ready;
	assign loading_addr_for_rd_nxt_lv_mem = 
		cpu_side_access_bus_cmd_addr & (~((CACHE_DATA_WIDTH / 8) - 1));
	
	assign wdata_to_merge_for_rd_nxt_lv_mem = cpu_side_wdata_found;
	assign wmask_to_merge_for_rd_nxt_lv_mem = cpu_side_wmask_found;
	
	assign on_complete_rd_nxt_lv_mem_tr = 
		on_wr_cache_line & (nxt_lv_mem_rdata_id_to_be_transmitted == (CACHE_LINE_DATA_N - 1));
	
	assign on_wr_cache_line = 
		(pending_for_rd_nxt_lv_mem_tr_flag & rd_data_blk_found_in_wbuf_flag) | // 使用从写缓存里找到的数据块
		(m_axi_rvalid & m_axi_rready); // 使用读下级存储器(AXI主机)返回的数据
	assign cache_line_index_to_be_written = 
		(addr_for_rd_nxt_lv_mem[31:clogb2(CACHE_LINE_DATA_N*CACHE_DATA_WIDTH/8)] & (CACHE_ENTRY_N - 1)) | 
		32'h0000_0000;
	assign cache_line_data_ofs_to_be_written = 
		nxt_lv_mem_rdata_id_to_be_transmitted[clogb2(CACHE_LINE_DATA_N-1):0] | 
		8'h00;
	
	genvar wr_cache_new_data_byte_i;
	generate
		for(wr_cache_new_data_byte_i = 0;wr_cache_new_data_byte_i < CACHE_DATA_WIDTH/8;
			wr_cache_new_data_byte_i = wr_cache_new_data_byte_i + 1)
		begin:wr_cache_new_data_blk
			assign wr_cache_new_data[wr_cache_new_data_byte_i*8+7:wr_cache_new_data_byte_i*8] = 
				/*
				说明: 
					对于写cache引起的读下级存储器(即写缺失),
					从写缓存或读下级存储器(AXI主机)取到的数据要合并上写cache的修改(数据 + 写字节掩码)
				*/
				(
					(
						(nxt_lv_mem_rdata_id_to_be_transmitted | 8'd0) == 
							(addr_for_rd_nxt_lv_mem[clogb2(CACHE_DATA_WIDTH/8)+7:clogb2(CACHE_DATA_WIDTH/8)] & (CACHE_LINE_DATA_N - 1))
					) & // 块内数据ID匹配
					rd_nxt_lv_mem_initiated_by_write_access_flag & // 读下级存储器是因为cache写访问发起的
					wmask_to_merge_for_rd_nxt_lv_mem[wr_cache_new_data_byte_i] // 待写数据的字节掩码有效
				) ? 
					wdata_to_merge_for_rd_nxt_lv_mem[wr_cache_new_data_byte_i*8+7:wr_cache_new_data_byte_i*8]:
					(
						(pending_for_rd_nxt_lv_mem_tr_flag & rd_data_blk_found_in_wbuf_flag) ? 
							shifting_rd_data_blk_found_in_wbuf[wr_cache_new_data_byte_i*8+7:wr_cache_new_data_byte_i*8]: // 使用从写缓存里找到的数据块
							m_axi_rdata[wr_cache_new_data_byte_i*8+7:wr_cache_new_data_byte_i*8] // 使用读下级存储器(AXI主机)返回的数据
					);
		end
	endgenerate
	
	// 读下级存储器是因为写访问发起的(标志), 读下级存储器的访问地址
	always @(posedge aclk)
	begin
		if(on_load_addr_for_rd_nxt_lv_mem)
		begin
			rd_nxt_lv_mem_initiated_by_write_access_flag <= # SIM_DELAY ~cpu_side_access_bus_cmd_is_read;
			addr_for_rd_nxt_lv_mem <= # SIM_DELAY loading_addr_for_rd_nxt_lv_mem;
		end
	end
	
	// 等待读下级存储器事务完成(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			pending_for_rd_nxt_lv_mem_tr_flag <= 1'b0;
		else if(
			pending_for_rd_nxt_lv_mem_tr_flag ? 
				on_complete_rd_nxt_lv_mem_tr:
				(on_initiate_rd_nxt_lv_mem_tr & (~on_complete_rd_nxt_lv_mem_tr))
		)
			pending_for_rd_nxt_lv_mem_tr_flag <= # SIM_DELAY 
				~pending_for_rd_nxt_lv_mem_tr_flag;
	end
	
	// 读下级存储器事务的地址已传输(标志)
	always @(posedge aclk)
	begin
		if(
			pending_for_rd_nxt_lv_mem_tr_flag ? 
				((~rd_nxt_lv_mem_tr_addr_setup_flag) & m_axi_arready):
				on_initiate_rd_nxt_lv_mem_tr
		)
			rd_nxt_lv_mem_tr_addr_setup_flag <= # SIM_DELAY 
				pending_for_rd_nxt_lv_mem_tr_flag | 
				/*
				发起读下级存储器事务时,
				若能够从写缓存找到相应的数据块, 或者读下级存储器(AXI主机)的AR通道立即握手, 则标记读下级存储器事务的地址已传输
				*/
				(wbuf_cln_found_flag | m_axi_arready);
	end
	
	// 在写缓存里找到待读取的数据块(标志)
	always @(posedge aclk)
	begin
		if((~pending_for_rd_nxt_lv_mem_tr_flag) & on_initiate_rd_nxt_lv_mem_tr)
			rd_data_blk_found_in_wbuf_flag <= # SIM_DELAY 
				wbuf_cln_found_flag;
	end
	
	// 在写缓存里找到的待读数据块
	always @(posedge aclk)
	begin
		if(
			pending_for_rd_nxt_lv_mem_tr_flag ? 
				rd_data_blk_found_in_wbuf_flag:
				(on_initiate_rd_nxt_lv_mem_tr & wbuf_cln_found_flag)
		)
			shifting_rd_data_blk_found_in_wbuf <= # SIM_DELAY 
				pending_for_rd_nxt_lv_mem_tr_flag ? 
					(shifting_rd_data_blk_found_in_wbuf >> CACHE_DATA_WIDTH): // 右移1个数据
					wbuf_sch_datblk; // 载入从写缓存找到的数据块
	end
	
	// 读下级存储器待传输的数据ID
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			nxt_lv_mem_rdata_id_to_be_transmitted <= 0;
		else if(
			(CACHE_LINE_DATA_N > 1) & 
			on_wr_cache_line
		)
			nxt_lv_mem_rdata_id_to_be_transmitted <= # SIM_DELAY 
				nxt_lv_mem_rdata_id_to_be_transmitted + 1'b1;
	end
	
	// 保存的访问数据
	always @(posedge aclk)
	begin
		if(
			on_wr_cache_line & 
			(
				nxt_lv_mem_rdata_id_to_be_transmitted == 
					(addr_for_rd_nxt_lv_mem[clogb2(CACHE_DATA_WIDTH/8)+7:clogb2(CACHE_DATA_WIDTH/8)] & (CACHE_LINE_DATA_N - 1))
			) & // 块内数据ID匹配
			(~rd_nxt_lv_mem_initiated_by_write_access_flag) // 读下级存储器是因为Cache读访问发起的
		)
			cache_rd_access_data_saved <= # SIM_DELAY 
				wr_cache_new_data;
	end
	
	/** 将待替换的脏缓存行送入写缓存 **/
	reg[CACHE_DATA_WIDTH-1:0] cache_line_prepared_for_inserting_wbuf[0:CACHE_LINE_DATA_N-1]; // 准备置入写缓存的缓存行
	reg[CACHE_LINE_DATA_N-1:0] loading_cache_data_id_for_inserting_wbuf; // 待载入的缓存数据ID
	wire on_load_cache_data_for_inserting_wbuf; // 载入缓存数据(指示)
	wire[CACHE_DATA_WIDTH-1:0] loading_cache_data_for_inserting_wbuf; // 正在载入的缓存数据
	reg transmitting_cache_line_to_wbuf_flag; // 正在将缓存行送入写缓存(标志)
	
	assign m_wbuf_axis_valid = 
		transmitting_cache_line_to_wbuf_flag | 
		(loading_cache_data_id_for_inserting_wbuf[CACHE_LINE_DATA_N-1] & on_load_cache_data_for_inserting_wbuf);
	
	// 准备置入写缓存的缓存行
	genvar inserting_wbuf_data_id;
	generate
		for(inserting_wbuf_data_id = 0;inserting_wbuf_data_id < CACHE_LINE_DATA_N;
			inserting_wbuf_data_id = inserting_wbuf_data_id + 1)
		begin:inserting_wbuf_blk
			assign m_wbuf_axis_data[(inserting_wbuf_data_id+1)*CACHE_DATA_WIDTH-1:inserting_wbuf_data_id*CACHE_DATA_WIDTH] = 
				/*
				说明:
					数据块里的最后1个数据可能需要旁路出去, 这是因为接收数据块里的最后1个数据时,
					待写的缓存行(AXIS主机)已开始有效(m_wbuf_axis_valid有效)
				*/
				(
					(inserting_wbuf_data_id == (CACHE_LINE_DATA_N - 1)) & 
					(~transmitting_cache_line_to_wbuf_flag) & 
					loading_cache_data_id_for_inserting_wbuf[inserting_wbuf_data_id] & on_load_cache_data_for_inserting_wbuf
				) ? 
					loading_cache_data_for_inserting_wbuf:
					cache_line_prepared_for_inserting_wbuf[inserting_wbuf_data_id];
			
			always @(posedge aclk)
			begin
				if(
					(~transmitting_cache_line_to_wbuf_flag) & 
					loading_cache_data_id_for_inserting_wbuf[inserting_wbuf_data_id] & on_load_cache_data_for_inserting_wbuf
				)
					cache_line_prepared_for_inserting_wbuf[inserting_wbuf_data_id] <= # SIM_DELAY 
						loading_cache_data_for_inserting_wbuf;
			end
		end
	endgenerate
	
	// 待载入的缓存数据ID
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			loading_cache_data_id_for_inserting_wbuf <= 1;
		else if((~transmitting_cache_line_to_wbuf_flag) & on_load_cache_data_for_inserting_wbuf)
			loading_cache_data_id_for_inserting_wbuf <= # SIM_DELAY 
				(loading_cache_data_id_for_inserting_wbuf << 1) | 
				(loading_cache_data_id_for_inserting_wbuf >> (CACHE_LINE_DATA_N-1));
	end
	
	// 正在将缓存行送入写缓存(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			transmitting_cache_line_to_wbuf_flag <= 1'b0;
		else if(
			transmitting_cache_line_to_wbuf_flag ? 
				m_wbuf_axis_ready:
				(
					loading_cache_data_id_for_inserting_wbuf[CACHE_LINE_DATA_N-1] & on_load_cache_data_for_inserting_wbuf & 
					(~m_wbuf_axis_ready)
				)
		)
			transmitting_cache_line_to_wbuf_flag <= # SIM_DELAY 
				~transmitting_cache_line_to_wbuf_flag;
	end
	
	/** 读标签存储器, 读数据存储器 **/
	// 存储器接口
	// [标签存储器读端口]
	wire rd_tag_mem_en; // 读使能
	wire[31:0] rd_tag_mem_addr_index; // 读地址(索引号)
	wire[CACHE_TAG_WIDTH-1:0] rd_tag_mem_addr_tag; // 读地址(缓存行标签)
	wire[7:0] rd_tag_mem_addr_ofs; // 读地址(数据偏移量)
	wire[31:0] rd_tag_mem_dout_real_addr[0:CACHE_WAY_N-1]; // 读数据(缓存行的实际基地址)
	wire[CACHE_WAY_N-1:0] rd_tag_mem_dout_hit_flag; // 读数据(缓存行命中标志)
	wire[CACHE_WAY_N-1:0] rd_tag_mem_dout_valid_flag; // 读数据(缓存行有效标志)
	wire[CACHE_WAY_N-1:0] rd_tag_mem_dout_dirty_flag; // 读数据(缓存行脏标志)
	reg[CACHE_WAY_N-1:0] cache_line_prev_marked_as_dirty_flag; // 缓存行刚刚因为写命中被标记为脏
	// [数据存储器读端口(访问时)]
	wire rd_data_mem_en; // 读使能
	wire[31:0] rd_data_mem_addr_index; // 读地址(索引号)
	wire[7:0] rd_data_mem_addr_ofs; // 读地址(数据偏移量)
	wire[CACHE_DATA_WIDTH-1:0] rd_data_mem_dout[0:CACHE_WAY_N-1]; // 读数据
	// [数据存储器读端口(替换时)]
	wire[CACHE_WAY_N-1:0] fetch_data_mem_en; // 读使能
	wire[31:0] fetch_data_mem_addr_index; // 读地址(索引号)
	wire[7:0] fetch_data_mem_addr_ofs; // 读地址(数据偏移量)
	wire[CACHE_DATA_WIDTH-1:0] fetch_data_mem_dout[0:CACHE_WAY_N-1]; // 读数据
	reg fetching_replaced_cache_line_data_vld; // 正在取被替换缓存行的数据有效(指示)
	// 缓存命中判定
	wire is_cache_hit; // Cache是否命中
	wire has_invalid_cache_line; // 是否有无效缓存行
	reg has_invalid_cache_line_d1; // 延迟1clk的是否有无效缓存行
	wire[2:0] wid_of_hit_cache_line; // 所命中缓存行的缓存路编号
	reg to_bypass_wr_data_mem_in_hit_case_din_addr_collision_flag; // 旁路命中时的数据存储器写数据(地址冲突标志)
	reg[CACHE_DATA_WIDTH/8-1:0] to_bypass_wr_data_mem_in_hit_case_din_mask; // 旁路命中时的数据存储器写数据(字节掩码)
	reg[CACHE_DATA_WIDTH-1:0] wr_data_mem_in_hit_case_din_for_bypass; // 待旁路的命中时的数据存储器写数据
	wire[CACHE_DATA_WIDTH-1:0] data_of_hit_cache_line; // 所命中缓存行的数据
	reg is_tag_mem_rd_initiated_by_write_access; // 标签存储器读是否由cache写访问发起
	wire[31:0] tag_mem_rd_res_access_addr_index; // 所访问缓存行地址的索引部分
	wire[7:0] tag_mem_rd_res_access_addr_data_ofs; // 所访问缓存行地址的数据偏移量部分
	reg tag_mem_rd_res_vld; // 标签存储器读结果有效(指示)
	// 缓存行替换
	reg continue_to_fetch_replaced_cache_line; // 继续取被替换的缓存行(标志)
	reg[clogb2(CACHE_LINE_DATA_N-1):0] fetching_replaced_cache_line_data_ofs; // 正在取被替换缓存行的数据偏移量
	wire[2:0] invalid_cache_line_to_be_replaced; // 待替换的无效缓存行
	reg[2:0] invalid_cache_line_to_be_replaced_d1; // 延迟1clk的待替换的无效缓存行
	wire[2:0] cache_line_wid_to_be_replaced; // 待替换缓存行的路编号
	wire is_replaced_cache_line_valid; // 待替换缓存行是否有效
	wire is_replaced_cache_line_dirty; // 待替换缓存行是否脏
	
	assign m_wbuf_axis_data[32+CACHE_LINE_DATA_N*CACHE_DATA_WIDTH-1:CACHE_LINE_DATA_N*CACHE_DATA_WIDTH] = 
		rd_tag_mem_dout_real_addr[cache_line_wid_to_be_replaced & (CACHE_WAY_N - 1)] & 
		(~(CACHE_LINE_DATA_N * CACHE_DATA_WIDTH / 8 - 1));
	
	assign hot_tb_en = tag_mem_rd_res_vld;
	assign hot_tb_upd_en = 1'b1;
	assign hot_tb_cid = tag_mem_rd_res_access_addr_index;
	assign hot_tb_acs_wid = 
		is_cache_hit ? 
			wid_of_hit_cache_line:
			(
				has_invalid_cache_line ? 
					invalid_cache_line_to_be_replaced: // 说明: 如果当前缓存集里有无效缓存行, 则优先替换无效的缓存行
					3'bxxx
			);
	// 警告: 后续可能要无效化某些缓存行, 仅根据缓存路#0是否无效来判断是否要初始化这个缓存集的热度是不准确的!!!
	assign hot_tb_init_item = ~(is_cache_hit | rd_tag_mem_dout_valid_flag[0]);
	assign hot_tb_swp_lru_item = ~(is_cache_hit | has_invalid_cache_line);
	
	assign on_load_cache_data_for_inserting_wbuf = 
		fetching_replaced_cache_line_data_vld & 
		is_replaced_cache_line_valid & is_replaced_cache_line_dirty;
	assign loading_cache_data_for_inserting_wbuf = 
		fetch_data_mem_dout[cache_line_wid_to_be_replaced & (CACHE_WAY_N - 1)];
	
	assign rd_tag_mem_en = 
		cpu_side_access_bus_cmd_valid & cpu_side_access_bus_cmd_ready;
	assign rd_tag_mem_addr_index = 
		(cpu_side_access_bus_cmd_addr[31:clogb2(CACHE_LINE_DATA_N*CACHE_DATA_WIDTH/8)] & (CACHE_ENTRY_N - 1)) | 32'h0000_0000;
	assign rd_tag_mem_addr_tag = 
		cpu_side_access_bus_cmd_addr[(CACHE_TAG_WIDTH-1)+clogb2(CACHE_ENTRY_N*CACHE_LINE_DATA_N*CACHE_DATA_WIDTH/8):clogb2(CACHE_ENTRY_N*CACHE_LINE_DATA_N*CACHE_DATA_WIDTH/8)];
	assign rd_tag_mem_addr_ofs = 
		cpu_side_access_bus_cmd_addr[7+clogb2(CACHE_DATA_WIDTH/8):clogb2(CACHE_DATA_WIDTH/8)] & (CACHE_LINE_DATA_N - 1);
	
	genvar rd_tag_mem_way_i;
	generate
		for(rd_tag_mem_way_i = 0;rd_tag_mem_way_i < CACHE_WAY_N;rd_tag_mem_way_i = rd_tag_mem_way_i + 1)
		begin:rd_tag_mem_blk
			assign rd_tag_mem_dout_real_addr[rd_tag_mem_way_i] = 
				cache_tag_dout_real_addr_a[31+32*rd_tag_mem_way_i:32*rd_tag_mem_way_i];
		end
	endgenerate
	
	assign rd_tag_mem_dout_hit_flag = cache_tag_dout_hit_a;
	assign rd_tag_mem_dout_valid_flag = cache_tag_dout_valid_a;
	assign rd_tag_mem_dout_dirty_flag = cache_tag_dout_dirty_a | cache_line_prev_marked_as_dirty_flag;
	
	assign rd_data_mem_en = 
		cpu_side_access_bus_cmd_valid & cpu_side_access_bus_cmd_ready;
	assign rd_data_mem_addr_index = 
		(cpu_side_access_bus_cmd_addr[31:clogb2(CACHE_LINE_DATA_N*CACHE_DATA_WIDTH/8)] & (CACHE_ENTRY_N - 1)) | 32'h0000_0000;
	assign rd_data_mem_addr_ofs = 
		cpu_side_access_bus_cmd_addr[7+clogb2(CACHE_DATA_WIDTH/8):clogb2(CACHE_DATA_WIDTH/8)] & (CACHE_LINE_DATA_N - 1);
	
	genvar rd_data_mem_way_i;
	generate
		for(rd_data_mem_way_i = 0;rd_data_mem_way_i < CACHE_WAY_N;rd_data_mem_way_i = rd_data_mem_way_i + 1)
		begin:rd_data_mem_blk
			assign rd_data_mem_dout[rd_data_mem_way_i] = 
				cache_dout_b[(CACHE_DATA_WIDTH-1)+CACHE_DATA_WIDTH*rd_data_mem_way_i:CACHE_DATA_WIDTH*rd_data_mem_way_i];
		end
	endgenerate
	
	assign fetch_data_mem_en = 
		{CACHE_WAY_N{
			(
				continue_to_fetch_replaced_cache_line & 
				is_replaced_cache_line_valid & is_replaced_cache_line_dirty
			) | 
			// 说明: 访问cache的下1clk, 若缺失, 则读出这个缓存集的所有缓存行(尽管这时还不知道待替换缓存行的路编号)
			(tag_mem_rd_res_vld & (~is_cache_hit))
		}} & 
		(
			{CACHE_WAY_N{tag_mem_rd_res_vld}} | 
			(1 << cache_line_wid_to_be_replaced)
		);
	assign fetch_data_mem_addr_index = 
		tag_mem_rd_res_access_addr_index;
	assign fetch_data_mem_addr_ofs = 
		continue_to_fetch_replaced_cache_line ? 
			(fetching_replaced_cache_line_data_ofs | 8'd0):
			8'd0;
	
	genvar fetch_data_mem_way_i;
	generate
		for(fetch_data_mem_way_i = 0;fetch_data_mem_way_i < CACHE_WAY_N;fetch_data_mem_way_i = fetch_data_mem_way_i + 1)
		begin:fetch_data_mem_blk
			assign fetch_data_mem_dout[fetch_data_mem_way_i] = 
				cache_dout_b[CACHE_DATA_WIDTH*(fetch_data_mem_way_i+1)-1:CACHE_DATA_WIDTH*fetch_data_mem_way_i];
		end
	endgenerate
	
	assign is_cache_hit = |rd_tag_mem_dout_hit_flag;
	assign has_invalid_cache_line = ~(&rd_tag_mem_dout_valid_flag);
	
	assign wid_of_hit_cache_line = 
		({3{|((rd_tag_mem_dout_hit_flag | 8'd0) & (1 << 0))}} & 3'd0) | 
		({3{|((rd_tag_mem_dout_hit_flag | 8'd0) & (1 << 1))}} & 3'd1) | 
		({3{|((rd_tag_mem_dout_hit_flag | 8'd0) & (1 << 2))}} & 3'd2) | 
		({3{|((rd_tag_mem_dout_hit_flag | 8'd0) & (1 << 3))}} & 3'd3) | 
		({3{|((rd_tag_mem_dout_hit_flag | 8'd0) & (1 << 4))}} & 3'd4) | 
		({3{|((rd_tag_mem_dout_hit_flag | 8'd0) & (1 << 5))}} & 3'd5) | 
		({3{|((rd_tag_mem_dout_hit_flag | 8'd0) & (1 << 6))}} & 3'd6) | 
		({3{|((rd_tag_mem_dout_hit_flag | 8'd0) & (1 << 7))}} & 3'd7);
	
	genvar data_of_hit_cache_line_byte_i;
	generate
		for(data_of_hit_cache_line_byte_i = 0;data_of_hit_cache_line_byte_i < CACHE_DATA_WIDTH/8;
			data_of_hit_cache_line_byte_i = data_of_hit_cache_line_byte_i + 1)
		begin:data_of_hit_cache_line_blk
			assign data_of_hit_cache_line[data_of_hit_cache_line_byte_i*8+7:data_of_hit_cache_line_byte_i*8] = 
				(
					to_bypass_wr_data_mem_in_hit_case_din_addr_collision_flag & 
					to_bypass_wr_data_mem_in_hit_case_din_mask[data_of_hit_cache_line_byte_i]
				) ? 
					wr_data_mem_in_hit_case_din_for_bypass[data_of_hit_cache_line_byte_i*8+7:data_of_hit_cache_line_byte_i*8]:
					rd_data_mem_dout[wid_of_hit_cache_line & (CACHE_WAY_N - 1)][data_of_hit_cache_line_byte_i*8+7:data_of_hit_cache_line_byte_i*8];
		end
	endgenerate
	
	assign tag_mem_rd_res_access_addr_index = 
		(rd_tag_mem_dout_real_addr[0][31:clogb2(CACHE_LINE_DATA_N*CACHE_DATA_WIDTH/8)] | 32'h0000_0000) & 
		(CACHE_ENTRY_N - 1);
	assign tag_mem_rd_res_access_addr_data_ofs = 
		rd_tag_mem_dout_real_addr[0][7+clogb2(CACHE_DATA_WIDTH/8):clogb2(CACHE_DATA_WIDTH/8)] & 
		(CACHE_LINE_DATA_N - 1);
	
	assign invalid_cache_line_to_be_replaced = 
		(CACHE_WAY_N == 1) ? 3'b000:
		(CACHE_WAY_N == 2) ? (
			(~rd_tag_mem_dout_valid_flag[0]) ? 3'b000:
											   3'b001
		):
		(CACHE_WAY_N == 4) ? (
			({3{(~rd_tag_mem_dout_valid_flag[0])}} & 3'b000) | 
			({3{(&rd_tag_mem_dout_valid_flag[0:0]) & (~rd_tag_mem_dout_valid_flag[1])}} & 3'b001) | 
			({3{(&rd_tag_mem_dout_valid_flag[1:0]) & (~rd_tag_mem_dout_valid_flag[2])}} & 3'b010) | 
			({3{(&rd_tag_mem_dout_valid_flag[2:0]) & (~rd_tag_mem_dout_valid_flag[3])}} & 3'b011)
		):(
			({3{(~rd_tag_mem_dout_valid_flag[0])}} & 3'b000) | 
			({3{(&rd_tag_mem_dout_valid_flag[0:0]) & (~rd_tag_mem_dout_valid_flag[1])}} & 3'b001) | 
			({3{(&rd_tag_mem_dout_valid_flag[1:0]) & (~rd_tag_mem_dout_valid_flag[2])}} & 3'b010) | 
			({3{(&rd_tag_mem_dout_valid_flag[2:0]) & (~rd_tag_mem_dout_valid_flag[3])}} & 3'b011) | 
			({3{(&rd_tag_mem_dout_valid_flag[3:0]) & (~rd_tag_mem_dout_valid_flag[4])}} & 3'b100) | 
			({3{(&rd_tag_mem_dout_valid_flag[4:0]) & (~rd_tag_mem_dout_valid_flag[5])}} & 3'b101) | 
			({3{(&rd_tag_mem_dout_valid_flag[5:0]) & (~rd_tag_mem_dout_valid_flag[6])}} & 3'b110) | 
			({3{(&rd_tag_mem_dout_valid_flag[6:0]) & (~rd_tag_mem_dout_valid_flag[7])}} & 3'b111)
		);
	assign cache_line_wid_to_be_replaced = 
		has_invalid_cache_line_d1 ? 
			invalid_cache_line_to_be_replaced_d1:
			hot_tb_lru_wid;
	assign is_replaced_cache_line_valid = |(rd_tag_mem_dout_valid_flag & (1 << cache_line_wid_to_be_replaced));
	assign is_replaced_cache_line_dirty = |(rd_tag_mem_dout_dirty_flag & (1 << cache_line_wid_to_be_replaced));
	
	// 延迟1clk的是否有无效缓存行
	always @(posedge aclk)
	begin
		if(tag_mem_rd_res_vld)
			has_invalid_cache_line_d1 <= # SIM_DELAY has_invalid_cache_line;
	end
	
	// 延迟1clk的待替换的无效缓存行
	always @(posedge aclk)
	begin
		if(tag_mem_rd_res_vld & has_invalid_cache_line)
			invalid_cache_line_to_be_replaced_d1 <= # SIM_DELAY invalid_cache_line_to_be_replaced;
	end
	
	// 标签存储器读是否由cache写访问发起
	always @(posedge aclk)
	begin
		if(rd_tag_mem_en)
			is_tag_mem_rd_initiated_by_write_access <= # SIM_DELAY ~cpu_side_access_bus_cmd_is_read;
	end
	
	// 标签存储器读结果有效(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			tag_mem_rd_res_vld <= 1'b0;
		else
			tag_mem_rd_res_vld <= # SIM_DELAY rd_tag_mem_en;
	end
	
	// 继续取被替换的缓存行(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			continue_to_fetch_replaced_cache_line <= 1'b0;
		else if(
			(CACHE_LINE_DATA_N > 1) & 
			(
				continue_to_fetch_replaced_cache_line ? 
					(
						(fetching_replaced_cache_line_data_ofs == (CACHE_LINE_DATA_N - 1)) | 
						// 说明: 读热度表后, 若发现待替换缓存行不脏, 那么不需要继续取被替换缓存行
						(~(is_replaced_cache_line_valid & is_replaced_cache_line_dirty))
					):
					(tag_mem_rd_res_vld & (~is_cache_hit))
			)
		)
			continue_to_fetch_replaced_cache_line <= # SIM_DELAY 
				~continue_to_fetch_replaced_cache_line;
	end
	
	// 正在取被替换缓存行的数据偏移量
	always @(posedge aclk)
	begin
		if(
			(CACHE_LINE_DATA_N > 1) & 
			(
				continue_to_fetch_replaced_cache_line | 
				(tag_mem_rd_res_vld & (~is_cache_hit))
			)
		)
			fetching_replaced_cache_line_data_ofs <= # SIM_DELAY 
				continue_to_fetch_replaced_cache_line ? 
					(fetching_replaced_cache_line_data_ofs + 1'b1):
					1; // 将数据偏移量初始化为1
	end
	
	// 正在取被替换缓存行的数据有效(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			fetching_replaced_cache_line_data_vld <= 1'b0;
		else
			fetching_replaced_cache_line_data_vld <= # SIM_DELAY 
				(
					continue_to_fetch_replaced_cache_line & 
					is_replaced_cache_line_valid & is_replaced_cache_line_dirty
				) | 
				(tag_mem_rd_res_vld & (~is_cache_hit));
	end
	
	/**
	写数据存储器
	
	写命中时, 在接受cache写访问的下1clk写数据存储器
	**/
	// 存储器接口
	// [命中时的写端口]
	wire wr_data_mem_in_hit_case_global_en; // 全局使能
	wire[CACHE_WAY_N-1:0] wr_data_mem_in_hit_case_en; // 写使能
	wire[CACHE_DATA_WIDTH/8-1:0] wr_data_mem_in_hit_case_wmask; // 写字节掩码
	wire[31:0] wr_data_mem_in_hit_case_addr_index; // 写地址(索引号)
	wire[7:0] wr_data_mem_in_hit_case_addr_ofs; // 写地址(数据偏移量)
	wire[CACHE_DATA_WIDTH-1:0] wr_data_mem_in_hit_case_din; // 写数据
	// [缺失时的写端口]
	wire[CACHE_WAY_N-1:0] wr_data_mem_in_miss_case_en; // 写使能
	wire[31:0] wr_data_mem_in_miss_case_addr_index; // 写地址(索引号)
	wire[7:0] wr_data_mem_in_miss_case_addr_ofs; // 写地址(数据偏移量)
	wire[CACHE_DATA_WIDTH-1:0] wr_data_mem_in_miss_case_din; // 写数据
	
	assign wr_data_mem_in_hit_case_global_en = 
		(
			tag_mem_rd_res_vld ? 
				(
					(~pending_for_cpu_side_wdata_flag) | 
					(s_axi_wvalid & s_axi_wready & (cpu_side_wdata_table_wptr == cpu_side_wdata_entry_id_pending))
				):
				(
					pending_for_cpu_side_wdata_flag & 
					(s_axi_wvalid & s_axi_wready & (cpu_side_wdata_table_wptr == cpu_side_wdata_entry_id_pending))
				)
		) & // 等待写数据准备好
		is_tag_mem_rd_initiated_by_write_access; // 发起的是cache写访问
	assign wr_data_mem_in_hit_case_en = 
		{CACHE_WAY_N{wr_data_mem_in_hit_case_global_en}} & rd_tag_mem_dout_hit_flag;
	assign wr_data_mem_in_hit_case_wmask = 
		pending_for_cpu_side_wdata_flag ? 
			s_axi_wstrb:
			cpu_side_wmask_found;
	assign wr_data_mem_in_hit_case_addr_index = 
		tag_mem_rd_res_access_addr_index;
	assign wr_data_mem_in_hit_case_addr_ofs = 
		tag_mem_rd_res_access_addr_data_ofs;
	assign wr_data_mem_in_hit_case_din = 
		pending_for_cpu_side_wdata_flag ? 
			s_axi_wdata:
			cpu_side_wdata_found;
	
	assign wr_data_mem_in_miss_case_en = 
		{CACHE_WAY_N{on_wr_cache_line}} & 
		// 说明: "待替换缓存行的路编号"在标签存储器读结果有效的下1个clk可用, 这对于缺失时写缓存行是安全的
		(1 << cache_line_wid_to_be_replaced);
	assign wr_data_mem_in_miss_case_addr_index = cache_line_index_to_be_written;
	assign wr_data_mem_in_miss_case_addr_ofs = cache_line_data_ofs_to_be_written;
	assign wr_data_mem_in_miss_case_din = wr_cache_new_data;
	
	// 旁路命中时的数据存储器写数据(地址冲突标志), 旁路命中时的数据存储器写数据(字节掩码), 待旁路的命中时的数据存储器写数据
	always @(posedge aclk)
	begin
		if(rd_tag_mem_en)
		begin
			to_bypass_wr_data_mem_in_hit_case_din_addr_collision_flag <= # SIM_DELAY 
				// 访问地址(索引部分)匹配
				((rd_tag_mem_addr_index & (CACHE_ENTRY_N - 1)) == (wr_data_mem_in_hit_case_addr_index & (CACHE_ENTRY_N - 1))) & 
				// 访问地址(数据偏移量部分)匹配
				((rd_tag_mem_addr_ofs & (CACHE_LINE_DATA_N - 1)) == (wr_data_mem_in_hit_case_addr_ofs & (CACHE_LINE_DATA_N - 1))) & 
				// 访问地址(标签部分)匹配
				(rd_tag_mem_addr_tag[CACHE_TAG_WIDTH-1:0] == cache_tag_dout_org_tag_a[CACHE_TAG_WIDTH-1:0]);
			
			to_bypass_wr_data_mem_in_hit_case_din_mask <= # SIM_DELAY 
				{(CACHE_DATA_WIDTH/8){
					wr_data_mem_in_hit_case_global_en // 写数据存储器全局使能有效
				}} & 
				wr_data_mem_in_hit_case_wmask;
			
			wr_data_mem_in_hit_case_din_for_bypass <= # SIM_DELAY 
				wr_data_mem_in_hit_case_din;
		end
	end
	
	/** Cache访问控制 **/
	// 缓存行缺失处理
	reg rd_nxt_lv_mem_pending_for_wdata_flag; // 等待写数据准备好以开始读下级存储器(标志)
	reg rd_nxt_lv_mem_in_progress_flag; // 正在读下级存储器(标志)
	reg pending_for_dirty_cache_line_submission_flag; // 等待脏的缓存行提交完成(标志)
	reg cache_miss_solving_flag; // 正在解决缓存行缺失(标志)
	// CPU侧cache访问控制
	reg cache_access_in_progress_flag; // cache访问进行中(标志)
	
	assign cpu_side_access_bus_cmd_ready = 
		(~cache_access_in_progress_flag) | 
		(
			(
				is_cache_hit ? 
					(
						(~is_tag_mem_rd_initiated_by_write_access) | 
						// 说明: 对于写命中, 需要等待写数据准备好
						(~pending_for_cpu_side_wdata_flag) | 
						(s_axi_wvalid & s_axi_wready & (cpu_side_wdata_table_wptr == cpu_side_wdata_entry_id_pending))
					):
					(
						(~tag_mem_rd_res_vld) & // 排除掉发起cache访问的下1clk, 因为此时还不能确定要替换的缓存行
						(~cache_miss_solving_flag) // 等待缓存行缺失被解决
					)
			) & cpu_side_access_bus_resp_ready
		);
	
	assign cpu_side_access_bus_resp_rdata = 
		is_cache_hit ? 
			data_of_hit_cache_line:
			cache_rd_access_data_saved;
	assign cpu_side_access_bus_resp_valid = 
		cache_access_in_progress_flag & 
		(
			is_cache_hit ? 
				(
					(~is_tag_mem_rd_initiated_by_write_access) | 
					// 说明: 对于写命中, 需要等待写数据准备好
					(~pending_for_cpu_side_wdata_flag) | 
					(s_axi_wvalid & s_axi_wready & (cpu_side_wdata_table_wptr == cpu_side_wdata_entry_id_pending))
				):
				(
					(~tag_mem_rd_res_vld) & // 排除掉发起cache访问的下1clk, 因为此时还不能确定要替换的缓存行
					(~cache_miss_solving_flag) // 等待缓存行缺失被解决
				)
		);
	
	assign on_initiate_rd_nxt_lv_mem_tr = 
		(
			tag_mem_rd_res_vld & (~is_cache_hit) & // cache缺失
			(~(
				rd_nxt_lv_mem_initiated_by_write_access_flag & pending_for_cpu_side_wdata_flag
			)) // 不是写cache访问, 或者写数据已经准备好
		) | 
		(
			rd_nxt_lv_mem_pending_for_wdata_flag & // 等待写数据准备好以开始读下级存储器
			(s_axi_wvalid & s_axi_wready & (cpu_side_wdata_table_wptr == cpu_side_wdata_entry_id_pending))
		);
	
	// 等待写数据准备好以开始读下级存储器(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rd_nxt_lv_mem_pending_for_wdata_flag <= 1'b0;
		else if(
			rd_nxt_lv_mem_pending_for_wdata_flag ? 
				(s_axi_wvalid & s_axi_wready & (cpu_side_wdata_table_wptr == cpu_side_wdata_entry_id_pending)):
				(
					tag_mem_rd_res_vld & (~is_cache_hit) & // cache缺失
					// 是写cache访问, 并且写数据未准备好
					rd_nxt_lv_mem_initiated_by_write_access_flag & 
					pending_for_cpu_side_wdata_flag
				)
		)
			rd_nxt_lv_mem_pending_for_wdata_flag <= # SIM_DELAY 
				~rd_nxt_lv_mem_pending_for_wdata_flag;
	end
	
	// 正在读下级存储器(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			rd_nxt_lv_mem_in_progress_flag <= 1'b0;
		else if(
			rd_nxt_lv_mem_in_progress_flag ? 
				on_complete_rd_nxt_lv_mem_tr:
				(tag_mem_rd_res_vld & (~is_cache_hit))
		)
			rd_nxt_lv_mem_in_progress_flag <= # SIM_DELAY 
				~rd_nxt_lv_mem_in_progress_flag;
	end
	
	// 等待脏的缓存行提交完成(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			pending_for_dirty_cache_line_submission_flag <= 1'b0;
		else if(
			pending_for_dirty_cache_line_submission_flag ? 
				(
					(m_wbuf_axis_valid & m_wbuf_axis_ready) | 
					(~(is_replaced_cache_line_valid & is_replaced_cache_line_dirty))
				):
				(tag_mem_rd_res_vld & (~is_cache_hit))
		)
			pending_for_dirty_cache_line_submission_flag <= # SIM_DELAY 
				~pending_for_dirty_cache_line_submission_flag;
	end
	
	// 正在解决缓存行缺失(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cache_miss_solving_flag <= 1'b0;
		else if(
			cache_miss_solving_flag ? 
				(
					(
						(~rd_nxt_lv_mem_in_progress_flag) | 
						on_complete_rd_nxt_lv_mem_tr
					) & 
					(
						(~pending_for_dirty_cache_line_submission_flag) | 
						(m_wbuf_axis_valid & m_wbuf_axis_ready) | 
						(~(is_replaced_cache_line_valid & is_replaced_cache_line_dirty))
					)
				):
				(tag_mem_rd_res_vld & (~is_cache_hit))
		)
			cache_miss_solving_flag <= # SIM_DELAY 
				~cache_miss_solving_flag;
	end
	
	// cache访问进行中(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cache_access_in_progress_flag <= 1'b0;
		else if(
			cache_access_in_progress_flag ? 
				(
					(cpu_side_access_bus_resp_valid & cpu_side_access_bus_resp_ready) & 
					(~(cpu_side_access_bus_cmd_valid & cpu_side_access_bus_cmd_ready))
				):
				(cpu_side_access_bus_cmd_valid & cpu_side_access_bus_cmd_ready)
		)
			cache_access_in_progress_flag <= # SIM_DELAY 
				~cache_access_in_progress_flag;
	end
	
	/** 写标签存储器 **/
	wire[CACHE_WAY_N-1:0] wr_tag_mem_en; // 写使能
	wire[31:0] wr_tag_mem_addr_index; // 写地址(索引号)
	wire[CACHE_TAG_WIDTH-1:0] wr_tag_mem_din_tag; // 写数据(缓存行标签)
	wire wr_tag_mem_din_valid_flag; // 写数据(有效标志)
	wire wr_tag_mem_din_dirty_flag; // 写数据(脏标志)
	
	// 说明: 由写命中引起的写标签存储器, tag和valid字段保存不变
	assign wr_tag_mem_en = 
		(
			{CACHE_WAY_N{tag_mem_rd_res_vld & is_cache_hit & is_tag_mem_rd_initiated_by_write_access}} & 
			(1 << wid_of_hit_cache_line)
		) | 
		(
			{CACHE_WAY_N{
				cache_miss_solving_flag & 
				(
					(
						(~rd_nxt_lv_mem_in_progress_flag) | 
						on_complete_rd_nxt_lv_mem_tr
					) & 
					(
						(~pending_for_dirty_cache_line_submission_flag) | 
						(m_wbuf_axis_valid & m_wbuf_axis_ready) | 
						(~(is_replaced_cache_line_valid & is_replaced_cache_line_dirty))
					)
				)
			}} & 
			(1 << cache_line_wid_to_be_replaced)
		);
	assign wr_tag_mem_addr_index = tag_mem_rd_res_access_addr_index;
	assign wr_tag_mem_din_tag = cache_tag_dout_org_tag_a[CACHE_TAG_WIDTH-1:0];
	assign wr_tag_mem_din_valid_flag = 1'b1; // 警告: 后续可能要无效化某些缓存行!!!
	assign wr_tag_mem_din_dirty_flag = ~cache_miss_solving_flag;
	
	// 缓存行刚刚因为写命中被标记为脏
	always @(posedge aclk)
	begin
		if(rd_tag_mem_en)
			cache_line_prev_marked_as_dirty_flag <= # SIM_DELAY 
				(
					{CACHE_WAY_N{tag_mem_rd_res_vld & is_cache_hit & is_tag_mem_rd_initiated_by_write_access}} & 
					(1 << wid_of_hit_cache_line)
				) & // 写命中引起的写标签存储器
				{CACHE_WAY_N{
					rd_tag_mem_addr_index[clogb2(CACHE_ENTRY_N-1):0] == 
						tag_mem_rd_res_access_addr_index[clogb2(CACHE_ENTRY_N-1):0]
				}}; // 访问地址(索引部分)匹配
	end
	
	/** 逻辑Cache存储器接口 **/
	// [数据存储器端口A, 只写]
	assign cache_data_en_a = wr_data_mem_in_miss_case_en | wr_data_mem_in_hit_case_en;
	assign cache_data_byte_wen_a = {CACHE_WAY_N{{(CACHE_DATA_WIDTH/8){cache_miss_solving_flag}} | wr_data_mem_in_hit_case_wmask}};
	assign cache_data_addr_index_a = {CACHE_WAY_N{cache_miss_solving_flag ? wr_data_mem_in_miss_case_addr_index:wr_data_mem_in_hit_case_addr_index}};
	assign cache_data_addr_ofs_a = {CACHE_WAY_N{cache_miss_solving_flag ? wr_data_mem_in_miss_case_addr_ofs:wr_data_mem_in_hit_case_addr_ofs}};
	assign cache_din_a = {CACHE_WAY_N{cache_miss_solving_flag ? wr_data_mem_in_miss_case_din:wr_data_mem_in_hit_case_din}};
	
	// [数据存储器端口B, 只读]
	assign cache_data_en_b = fetch_data_mem_en | {CACHE_WAY_N{rd_data_mem_en}};
	assign cache_data_byte_wen_b = {CACHE_WAY_N{{(CACHE_DATA_WIDTH/8){1'b0}}}};
	assign cache_data_addr_index_b = 
		{CACHE_WAY_N{
			((tag_mem_rd_res_vld & (~is_cache_hit)) | continue_to_fetch_replaced_cache_line) ? 
				fetch_data_mem_addr_index:
				rd_data_mem_addr_index
		}};
	assign cache_data_addr_ofs_b = 
		{CACHE_WAY_N{
			((tag_mem_rd_res_vld & (~is_cache_hit)) | continue_to_fetch_replaced_cache_line) ? 
				fetch_data_mem_addr_ofs:
				rd_data_mem_addr_ofs
		}};
	assign cache_din_b = {CACHE_WAY_N{{CACHE_DATA_WIDTH{1'bx}}}};
	
	// [标签存储器端口A, 只读]
	assign cache_tag_en_a = {CACHE_WAY_N{rd_tag_mem_en}};
	assign cache_tag_wen_a = {CACHE_WAY_N{1'b0}};
	assign cache_tag_addr_index_a = {CACHE_WAY_N{rd_tag_mem_addr_index}};
	assign cache_tag_addr_ofs_a = {CACHE_WAY_N{rd_tag_mem_addr_ofs}};
	assign cache_tag_addr_tag_a = {CACHE_WAY_N{rd_tag_mem_addr_tag}};
	assign cache_tag_din_valid_a = {CACHE_WAY_N{1'bx}};
	assign cache_tag_din_dirty_a = {CACHE_WAY_N{1'bx}};
	
	// [标签存储器端口B, 只写]
	assign cache_tag_en_b = wr_tag_mem_en;
	assign cache_tag_wen_b = wr_tag_mem_en;
	assign cache_tag_addr_index_b = {CACHE_WAY_N{wr_tag_mem_addr_index}};
	assign cache_tag_din_tag_b = {CACHE_WAY_N{wr_tag_mem_din_tag}};
	assign cache_tag_din_valid_b = {CACHE_WAY_N{wr_tag_mem_din_valid_flag}};
	assign cache_tag_din_dirty_b = {CACHE_WAY_N{wr_tag_mem_din_dirty_flag}};
	
	/** Cache性能监测 **/
	reg[31:0] cache_access_total_n_r; // cache访问总次数(计数器)
	reg[31:0] cache_hit_total_n_r; // cache命中总次数(计数器)
	reg[31:0] cache_rd_hit_n_r; // cache读命中次数(计数器)
	reg[31:0] cache_wr_hit_n_r; // cache写命中次数(计数器)
	reg[31:0] cache_replace_dirty_line_n_r; // cache替换脏的缓存行次数(计数器)
	reg on_cache_miss_d1; // 延迟1clk的得知cache缺失(指示)
	reg to_clr_cache_perf_mon_cnt_d1; // 延迟1clk的清零Cache性能监测计数器组(指示)
	
	assign cache_access_total_n = cache_access_total_n_r;
	assign cache_hit_total_n = cache_hit_total_n_r;
	assign cache_rd_hit_n = cache_rd_hit_n_r;
	assign cache_wr_hit_n = cache_wr_hit_n_r;
	assign cache_replace_dirty_line_n = cache_replace_dirty_line_n_r;
	
	// cache访问总次数(计数器)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cache_access_total_n_r <= 32'd0;
		else if(tag_mem_rd_res_vld)
			cache_access_total_n_r <= # SIM_DELAY 
				cache_access_total_n_r + 1'b1;
	end
	
	// cache命中总次数(计数器)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cache_hit_total_n_r <= 32'd0;
		else if(tag_mem_rd_res_vld & ((&cache_access_total_n_r) | is_cache_hit))
			cache_hit_total_n_r <= # SIM_DELAY 
				(&cache_access_total_n_r) ? 
					32'd0:
					(cache_hit_total_n_r + 1'b1);
	end
	
	// cache读命中次数(计数器)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cache_rd_hit_n_r <= 32'd0;
		else if(tag_mem_rd_res_vld & ((&cache_access_total_n_r) | ((~is_tag_mem_rd_initiated_by_write_access) & is_cache_hit)))
			cache_rd_hit_n_r <= # SIM_DELAY 
				(&cache_access_total_n_r) ? 
					32'd0:
					(cache_rd_hit_n_r + 1'b1);
	end
	
	// cache写命中次数(计数器)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cache_wr_hit_n_r <= 32'd0;
		else if(tag_mem_rd_res_vld & ((&cache_access_total_n_r) | (is_tag_mem_rd_initiated_by_write_access & is_cache_hit)))
			cache_wr_hit_n_r <= # SIM_DELAY 
				(&cache_access_total_n_r) ? 
					32'd0:
					(cache_wr_hit_n_r + 1'b1);
	end
	
	// cache替换脏的缓存行次数(计数器)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cache_replace_dirty_line_n_r <= 32'd0;
		else if(
			to_clr_cache_perf_mon_cnt_d1 | 
			(on_cache_miss_d1 & (is_replaced_cache_line_valid & is_replaced_cache_line_dirty))
		)
			cache_replace_dirty_line_n_r <= # SIM_DELAY 
				to_clr_cache_perf_mon_cnt_d1 ? 
					32'd0:
					(cache_replace_dirty_line_n_r + 1'b1);
	end
	
	// 延迟1clk的得知cache缺失(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			on_cache_miss_d1 <= 1'b0;
		else
			on_cache_miss_d1 <= # SIM_DELAY 
				tag_mem_rd_res_vld & (~is_cache_hit);
	end
	
	// 延迟1clk的清零Cache性能监测计数器组(指示)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			to_clr_cache_perf_mon_cnt_d1 <= 1'b0;
		else
			to_clr_cache_perf_mon_cnt_d1 <= # SIM_DELAY 
				tag_mem_rd_res_vld & (&cache_access_total_n_r);
	end
	
endmodule
