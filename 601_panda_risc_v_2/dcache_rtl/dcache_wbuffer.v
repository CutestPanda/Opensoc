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
本模块: 数据Cache写缓存

描述:
将数据块和缓存行地址存储到寄存器组中
将缓存的数据块通过AXI主机(32位地址, CACHE_DATA_WIDTH位数据)写入下级存储器

每次AXI写突发传输1个数据块, 因此突发长度 = CACHE_LINE_DATA_N

注意：
缓存行地址必须对齐到数据块, 即能够被CACHE_LINE_DATA_N*CACHE_DATA_WIDTH/8整除

协议:
AXIS SLAVE
AXI MASTER(WRITE ONLY)

作者: 陈家耀
日期: 2026/02/18
********************************************************************/


module dcache_wbuffer #(
	parameter integer CACHE_DATA_WIDTH = 32, // 缓存数据位宽(32 | 64 | 128 | 256)
	parameter integer CACHE_LINE_DATA_N = 8, // 每个缓存行的数据个数(1 | 2 | 4 | 8 | 16)
	parameter integer WBUF_ITEM_N = 4, // 写缓存最多可存的缓存行个数(1~8)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 缓存行检索
	input wire[31:0] cache_line_sch_addr, // 检索地址
	output wire cache_line_in_wbuf_flag, // 缓存行在写缓存中(标志)
	output wire[CACHE_LINE_DATA_N*CACHE_DATA_WIDTH-1:0] cache_line_sch_datblk, // 检索到的缓存行数据块
	
	// 待写的缓存行(AXIS从机)
	input wire[32+CACHE_LINE_DATA_N*CACHE_DATA_WIDTH-1:0] s_cache_line_axis_data, // {缓存行地址(32位), 缓存行数据块(CACHE_LINE_DATA_N*CACHE_DATA_WIDTH位)}
	input wire s_cache_line_axis_valid,
	output wire s_cache_line_axis_ready,
	
	// 写下级存储器(AXI主机)
	// [AW通道]
	output wire[31:0] m_axi_awaddr,
	output wire[1:0] m_axi_awburst, // const -> 2'b01(INCR)
	output wire[7:0] m_axi_awlen, // const -> CACHE_LINE_DATA_N - 1
	output wire[2:0] m_axi_awsize, // const -> clogb2(CACHE_DATA_WIDTH/8)
	output wire m_axi_awvalid,
	input wire m_axi_awready,
	// [B通道]
	input wire[1:0] m_axi_bresp, // ignored
	input wire m_axi_bvalid,
	output wire m_axi_bready, // const -> 1'b1
	// [W通道]
	output wire[CACHE_DATA_WIDTH-1:0] m_axi_wdata,
	output wire[CACHE_DATA_WIDTH/8-1:0] m_axi_wstrb, // const -> {(CACHE_DATA_WIDTH/8){1'b1}}
	output wire m_axi_wlast,
	output wire m_axi_wvalid,
	input wire m_axi_wready
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
	
	/** Cache Line写缓存 **/
	// [存储实体]
	reg[31:0] wbuf_table_addr[0:WBUF_ITEM_N-1]; // 缓存行地址
	reg[CACHE_LINE_DATA_N*CACHE_DATA_WIDTH-1:0] wbuf_table_data[0:WBUF_ITEM_N-1]; // 缓存行数据块
	reg[WBUF_ITEM_N-1:0] wbuf_table_vld_flag; // 有效标志
	reg[WBUF_ITEM_N-1:0] wbuf_table_addr_setup_flag; // 地址通道已传输标志
	reg[WBUF_ITEM_N-1:0] wbuf_table_data_sent_flag; // 数据通道已传输标志
	reg wbuf_full_n_flag; // 写缓存不满标志
	// [事务处理进程]
	reg[clogb2(WBUF_ITEM_N-1):0] wbuf_wptr; // 新请求写指针
	reg[clogb2(WBUF_ITEM_N-1):0] wbuf_addr_trans_ptr; // 正在进行地址通道传输的项指针
	reg[clogb2(WBUF_ITEM_N-1):0] wbuf_data_trans_ptr; // 正在进行数据通道传输的项指针
	reg[clogb2(CACHE_LINE_DATA_N-1):0] wbuf_sending_data_id_in_blk; // 正在传输的数据的块内编号
	reg[clogb2(WBUF_ITEM_N-1):0] wbuf_waiting_resp_trans_ptr; // 正在等待响应的项指针
	
	assign s_cache_line_axis_ready = wbuf_full_n_flag;
	
	assign m_axi_awaddr = wbuf_table_addr[wbuf_addr_trans_ptr] & (~(CACHE_LINE_DATA_N*CACHE_DATA_WIDTH/8 - 1));
	assign m_axi_awburst = 2'b01;
	assign m_axi_awlen = CACHE_LINE_DATA_N - 1;
	assign m_axi_awsize = clogb2(CACHE_DATA_WIDTH/8);
	assign m_axi_awvalid = wbuf_table_vld_flag[wbuf_addr_trans_ptr] & (~wbuf_table_addr_setup_flag[wbuf_addr_trans_ptr]);
	
	assign m_axi_bready = 1'b1;
	
	assign m_axi_wdata = wbuf_table_data[wbuf_data_trans_ptr] >> (wbuf_sending_data_id_in_blk * CACHE_DATA_WIDTH);
	assign m_axi_wstrb = {(CACHE_DATA_WIDTH/8){1'b1}};
	assign m_axi_wlast = wbuf_sending_data_id_in_blk == (CACHE_LINE_DATA_N - 1);
	assign m_axi_wvalid = wbuf_table_vld_flag[wbuf_data_trans_ptr] & (~wbuf_table_data_sent_flag[wbuf_data_trans_ptr]);
	
	// 写缓存不满标志
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wbuf_full_n_flag <= 1'b1;
		else if((s_cache_line_axis_valid & s_cache_line_axis_ready) ^ (m_axi_bvalid & m_axi_bready))
			wbuf_full_n_flag <= # SIM_DELAY 
				(m_axi_bvalid & m_axi_bready) | 
				(~(&(wbuf_table_vld_flag | (1 << wbuf_wptr))));
	end
	
	// 新请求写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wbuf_wptr <= 0;
		else if(s_cache_line_axis_valid & s_cache_line_axis_ready)
			wbuf_wptr <= # SIM_DELAY 
				(wbuf_wptr == (WBUF_ITEM_N - 1)) ? 
					0:
					(wbuf_wptr + 1'b1);
	end
	
	// 正在进行地址通道传输的项指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wbuf_addr_trans_ptr <= 0;
		else if(m_axi_awvalid & m_axi_awready)
			wbuf_addr_trans_ptr <= # SIM_DELAY 
				(wbuf_addr_trans_ptr == (WBUF_ITEM_N - 1)) ? 
					0:
					(wbuf_addr_trans_ptr + 1'b1);
	end
	
	// 正在进行数据通道传输的项指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wbuf_data_trans_ptr <= 0;
		else if(m_axi_wvalid & m_axi_wready & m_axi_wlast)
			wbuf_data_trans_ptr <= # SIM_DELAY 
				(wbuf_data_trans_ptr == (WBUF_ITEM_N - 1)) ? 
					0:
					(wbuf_data_trans_ptr + 1'b1);
	end
	
	// 正在传输的数据的块内编号
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wbuf_sending_data_id_in_blk <= 0;
		else if(m_axi_wvalid & m_axi_wready)
			wbuf_sending_data_id_in_blk <= # SIM_DELAY 
				m_axi_wlast ? 
					0:
					(wbuf_sending_data_id_in_blk + 1'b1);
	end
	
	// 正在等待响应的项指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wbuf_waiting_resp_trans_ptr <= 0;
		else if(m_axi_bvalid & m_axi_bready)
			wbuf_waiting_resp_trans_ptr <= # SIM_DELAY 
				(wbuf_waiting_resp_trans_ptr == (WBUF_ITEM_N - 1)) ? 
					0:
					(wbuf_waiting_resp_trans_ptr + 1'b1);
	end
	
	genvar wbuf_table_entry_i;
	generate
		for(wbuf_table_entry_i = 0;wbuf_table_entry_i < WBUF_ITEM_N;wbuf_table_entry_i = wbuf_table_entry_i + 1)
		begin:wbuf_table_blk
			always @(posedge aclk)
			begin
				if(s_cache_line_axis_valid & s_cache_line_axis_ready & (wbuf_wptr == wbuf_table_entry_i))
				begin
					wbuf_table_addr[wbuf_table_entry_i] <= # SIM_DELAY 
						s_cache_line_axis_data[32+CACHE_LINE_DATA_N*CACHE_DATA_WIDTH-1:CACHE_LINE_DATA_N*CACHE_DATA_WIDTH];
					wbuf_table_data[wbuf_table_entry_i] <= # SIM_DELAY 
						s_cache_line_axis_data[CACHE_LINE_DATA_N*CACHE_DATA_WIDTH-1:0];
				end
			end
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					wbuf_table_vld_flag[wbuf_table_entry_i] <= 1'b0;
				else if(
					(s_cache_line_axis_valid & s_cache_line_axis_ready & (wbuf_wptr == wbuf_table_entry_i)) | 
					(m_axi_bvalid & m_axi_bready & (wbuf_waiting_resp_trans_ptr == wbuf_table_entry_i))
				)
					wbuf_table_vld_flag[wbuf_table_entry_i] <= # SIM_DELAY 
						~(m_axi_bvalid & m_axi_bready & (wbuf_waiting_resp_trans_ptr == wbuf_table_entry_i));
			end
			
			always @(posedge aclk)
			begin
				if(
					(s_cache_line_axis_valid & s_cache_line_axis_ready & (wbuf_wptr == wbuf_table_entry_i)) | 
					(m_axi_awvalid & m_axi_awready & (wbuf_addr_trans_ptr == wbuf_table_entry_i))
				)
					wbuf_table_addr_setup_flag[wbuf_table_entry_i] <= # SIM_DELAY 
						m_axi_awvalid & m_axi_awready & (wbuf_addr_trans_ptr == wbuf_table_entry_i);
			end
			
			always @(posedge aclk)
			begin
				if(
					(s_cache_line_axis_valid & s_cache_line_axis_ready & (wbuf_wptr == wbuf_table_entry_i)) | 
					(m_axi_wvalid & m_axi_wready & m_axi_wlast & (wbuf_data_trans_ptr == wbuf_table_entry_i))
				)
					wbuf_table_data_sent_flag[wbuf_table_entry_i] <= # SIM_DELAY 
						m_axi_wvalid & m_axi_wready & m_axi_wlast & (wbuf_data_trans_ptr == wbuf_table_entry_i);
			end
		end
	endgenerate
	
	/** 缓存行检索 **/
	wire[WBUF_ITEM_N-1:0] addr_cmp_res; // 地址比较结果
	wire[clogb2(WBUF_ITEM_N-1):0] sch_datblk_sel; // 检索结果的数据块选择
	
	assign cache_line_in_wbuf_flag = |addr_cmp_res;
	assign cache_line_sch_datblk = wbuf_table_data[sch_datblk_sel];
	
	// 说明: 保证缓存行检索最多只有1项匹配
	assign sch_datblk_sel = 
		({3{|(addr_cmp_res & (1 << 0))}} & 0) | 
		({3{|(addr_cmp_res & (1 << 1))}} & 1) | 
		({3{|(addr_cmp_res & (1 << 2))}} & 2) | 
		({3{|(addr_cmp_res & (1 << 3))}} & 3) | 
		({3{|(addr_cmp_res & (1 << 4))}} & 4) | 
		({3{|(addr_cmp_res & (1 << 5))}} & 5) | 
		({3{|(addr_cmp_res & (1 << 6))}} & 6) | 
		({3{|(addr_cmp_res & (1 << 7))}} & 7);
	
	genvar addr_cmp_i;
	generate
		for(addr_cmp_i = 0;addr_cmp_i < WBUF_ITEM_N;addr_cmp_i = addr_cmp_i + 1)
		begin:addr_cmp_blk
			// 说明: 缓存行地址是对齐到数据块的
			assign addr_cmp_res[addr_cmp_i] = 
				wbuf_table_vld_flag[addr_cmp_i] & 
				(
					(cache_line_sch_addr & (~(CACHE_LINE_DATA_N*CACHE_DATA_WIDTH/8 - 1))) == 
					(wbuf_table_addr[addr_cmp_i] & (~(CACHE_LINE_DATA_N*CACHE_DATA_WIDTH/8 - 1)))
				);
		end
	endgenerate
	
endmodule
