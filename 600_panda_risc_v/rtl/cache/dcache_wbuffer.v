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
将缓存的数据块通过32位地址/32位数据ICB主机写入下级存储器
空的存储项 -> 有效的存储项 -> 已被ICB主机命令通道接受的存储项 -> 已写入下级存储器的存储项

可使能的写缓存项立即覆盖, 以允许在得到写下级存储器的响应时立即存入新的缓存行
可使能的低时延的ICB命令通道, 以在没有任何存储项时将待写的缓存行直接旁路给ICB主机的命令通道, 从而减小传输时延

注意：
缓存行地址必须对齐到数据块大小, 即能够被CACHE_LINE_WORD_N*4整除

协议:
AXIS SLAVE
ICB MASTER

作者: 陈家耀
日期: 2025/04/12
********************************************************************/


module dcache_wbuffer #(
	parameter integer CACHE_LINE_WORD_N = 8, // 每个缓存行的字数(1 | 2 | 4 | 8 | 16)
	parameter integer WBUF_ITEM_N = 4, // 写缓存最多可存的缓存行个数(1~8)
	parameter EN_WBUF_ITEM_IMDT_OVR = "true", // 是否允许写缓存项的立即覆盖
	parameter EN_LOW_LA_ICB_CMD = "false", // 是否启用低时延的ICB命令通道
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 缓存行检索
	input wire[31:0] cache_line_sch_addr, // 检索地址
	output wire cache_line_in_wbuf_flag, // 缓存行在写缓存中(标志)
	output wire[CACHE_LINE_WORD_N*32-1:0] cache_line_sch_datblk, // 检索到的缓存行数据块
	
	// 待写的缓存行(AXIS从机)
	input wire[CACHE_LINE_WORD_N*32+32-1:0] s_cache_line_axis_data, // {缓存行地址(32位), 缓存行数据块(CACHE_LINE_WORD_N*32位)}
	input wire s_cache_line_axis_valid,
	output wire s_cache_line_axis_ready,
	
	// 写下级存储器(ICB主机)
	// [命令通道]
	output wire[31:0] m_icb_cmd_addr,
	output wire m_icb_cmd_read, // const -> 1'b0
	output wire[31:0] m_icb_cmd_wdata,
	output wire[3:0] m_icb_cmd_wmask, // const -> 4'b1111
	output wire m_icb_cmd_valid,
	input wire m_icb_cmd_ready,
	// [响应通道]
	input wire[31:0] m_icb_rsp_rdata, // ignored
	input wire m_icb_rsp_err, // ignored
	input wire m_icb_rsp_valid,
	output wire m_icb_rsp_ready // const -> 1'b1
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
	// 独热码 -> 二进制码
    function [clogb2(WBUF_ITEM_N-1):0] onehot_to_bin(input[WBUF_ITEM_N-1:0] onehot);
        integer i;
    begin
        onehot_to_bin = 0;
        
        for(i = 0;i < WBUF_ITEM_N;i = i + 1)
        begin
            if(onehot[i])
                onehot_to_bin = i;
        end
    end
    endfunction
	
	/**
	写缓存控制
	
	缓存行写指针和缓存行ICB主机命令发送指针采用独热码, 缓存行读指针采用二进制码
	**/
	wire cache_line_wen; // 缓存行写使能
	reg[WBUF_ITEM_N-1:0] cache_line_wptr; // 缓存行写指针
	wire cache_line_ren; // 缓存行读使能
	reg[clogb2(WBUF_ITEM_N-1):0] cache_line_rptr; // 缓存行读指针
	reg[WBUF_ITEM_N-1:0] cache_line_valid; // 缓存行有效(标志)
	wire[WBUF_ITEM_N-1:0] cache_line_valid_nxt; // 新的缓存行有效(标志)
	reg wbuf_full_n; // 写缓存满(标志)
	reg wbuf_empty_n; // 写缓存空(标志)
	wire cache_line_icb_cmd_acpt; // 缓存行被ICB主机的命令通道接受
	reg[WBUF_ITEM_N-1:0] cache_line_icb_cmd_ptr; // 缓存行ICB主机命令发送指针
	reg[WBUF_ITEM_N-1:0] cache_line_on_trans; // 缓存行已发送到ICB主机的命令通道(标志)
	
	assign cache_line_wen = s_cache_line_axis_valid & s_cache_line_axis_ready;
	
	// 缓存行写指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cache_line_wptr <= 8'b0000_0001;
		else if(cache_line_wen)
			cache_line_wptr <= # SIM_DELAY (cache_line_wptr << 1) | (cache_line_wptr >> (WBUF_ITEM_N-1)); // 循环左移1位
	end
	// 缓存行读指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cache_line_rptr <= 0;
		else if(cache_line_ren)
			cache_line_rptr <= # SIM_DELAY 
				(cache_line_rptr == (WBUF_ITEM_N-1)) ? 
					0:
					(cache_line_rptr + 1);
	end
	// 缓存行ICB主机命令发送指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cache_line_icb_cmd_ptr <= 8'b0000_0001;
		else if(cache_line_icb_cmd_acpt)
			cache_line_icb_cmd_ptr <= # SIM_DELAY 
				(cache_line_icb_cmd_ptr << 1) | (cache_line_icb_cmd_ptr >> (WBUF_ITEM_N-1)); // 循环左移1位
	end
	
	// 缓存行有效(标志)
	genvar cache_line_valid_i;
	generate
		for(cache_line_valid_i = 0;cache_line_valid_i < WBUF_ITEM_N;cache_line_valid_i = cache_line_valid_i + 1)
		begin:cache_line_valid_blk
			assign cache_line_valid_nxt[cache_line_valid_i] = 
				(
					(cache_line_wen & cache_line_wptr[cache_line_valid_i]) ^ 
					(cache_line_ren & (cache_line_rptr == cache_line_valid_i))
				) ? 
					(cache_line_wen & cache_line_wptr[cache_line_valid_i]):
					cache_line_valid[cache_line_valid_i];
			
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					cache_line_valid[cache_line_valid_i] <= 1'b0;
				else
					cache_line_valid[cache_line_valid_i] <= # SIM_DELAY cache_line_valid_nxt[cache_line_valid_i];
			end
		end
	endgenerate
	
	// 写缓存满(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wbuf_full_n <= 1'b1;
		else if(cache_line_wen | cache_line_ren)
			wbuf_full_n <= # SIM_DELAY ~(&cache_line_valid_nxt);
	end
	// 写缓存空(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			wbuf_empty_n <= 1'b0;
		else if(cache_line_wen | cache_line_ren)
			wbuf_empty_n <= # SIM_DELAY |cache_line_valid_nxt;
	end
	
	// 缓存行已发送到ICB主机的命令通道(标志)
	genvar cache_line_on_trans_i;
	generate
		for(cache_line_on_trans_i = 0;cache_line_on_trans_i < WBUF_ITEM_N;cache_line_on_trans_i = cache_line_on_trans_i + 1)
		begin:cache_line_on_trans_blk
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					cache_line_on_trans[cache_line_on_trans_i] <= 1'b0;
				else if(
					(cache_line_icb_cmd_acpt & cache_line_icb_cmd_ptr[cache_line_on_trans_i]) ^ 
					(cache_line_ren & (cache_line_rptr == cache_line_on_trans_i))
				)
					cache_line_on_trans[cache_line_on_trans_i] <= # SIM_DELAY 
						cache_line_icb_cmd_acpt & cache_line_icb_cmd_ptr[cache_line_on_trans_i];
			end
		end
	endgenerate
	
	/** 写缓存寄存器组 **/
	reg[CACHE_LINE_WORD_N*32-1:0] data_regs[0:WBUF_ITEM_N-1]; // 数据块寄存器组
	reg[31:0] addr_regs[0:WBUF_ITEM_N-1]; // 地址寄存器组
	
	// 数据块寄存器组
	genvar data_reg_i;
	generate
		for(data_reg_i = 0;data_reg_i < WBUF_ITEM_N;data_reg_i = data_reg_i + 1)
		begin:data_regs_blk
			always @(posedge aclk)
			begin
				if(cache_line_wen & cache_line_wptr[data_reg_i])
					data_regs[data_reg_i] <= # SIM_DELAY s_cache_line_axis_data[CACHE_LINE_WORD_N*32-1:0];
			end
		end
	endgenerate
	// 地址寄存器组
	genvar addr_reg_i;
	generate
		for(addr_reg_i = 0;addr_reg_i < WBUF_ITEM_N;addr_reg_i = addr_reg_i + 1)
		begin:addr_regs_blk
			always @(posedge aclk)
			begin
				if(cache_line_wen & cache_line_wptr[addr_reg_i])
					addr_regs[addr_reg_i] <= # SIM_DELAY s_cache_line_axis_data[CACHE_LINE_WORD_N*32+32-1:CACHE_LINE_WORD_N*32];
			end
		end
	endgenerate
	
	/** 写下级存储器控制 **/
	reg[clogb2(CACHE_LINE_WORD_N-1):0] cache_line_word_ofs; // 位于ICB命令端的缓存行字偏移量
	wire[31:0] cache_line_baseaddr; // 缓存行基地址
	wire[31:0] cache_line_data_block[0:CACHE_LINE_WORD_N-1]; // 缓存行数据块
	reg[clogb2(CACHE_LINE_WORD_N-1):0] icb_rsp_word_ofs; // 位于ICB响应端的缓存行字偏移量
	
	assign s_cache_line_axis_ready = 
		wbuf_full_n | 
		((EN_WBUF_ITEM_IMDT_OVR == "true") & cache_line_ren);
	
	assign m_icb_cmd_addr = 
		((EN_LOW_LA_ICB_CMD == "true") & (~wbuf_empty_n)) ? 
			(s_cache_line_axis_data[CACHE_LINE_WORD_N*32+32-1:CACHE_LINE_WORD_N*32] + (cache_line_word_ofs * 4)):
			(cache_line_baseaddr + (cache_line_word_ofs * 4));
	assign m_icb_cmd_read = 1'b0;
	assign m_icb_cmd_wdata = 
		((EN_LOW_LA_ICB_CMD == "true") & (~wbuf_empty_n)) ? 
			s_cache_line_axis_data[CACHE_LINE_WORD_N*32-1:0]:
			cache_line_data_block[cache_line_word_ofs];
	assign m_icb_cmd_wmask = 4'b1111;
	assign m_icb_cmd_valid = 
		(cache_line_valid[cache_line_icb_cmd_ptr] | ((EN_LOW_LA_ICB_CMD == "true") & (~wbuf_empty_n) & s_cache_line_axis_valid)) & 
		(~cache_line_on_trans[cache_line_icb_cmd_ptr]);
	
	assign m_icb_rsp_ready = 1'b1;
	
	assign cache_line_icb_cmd_acpt = m_icb_cmd_valid & m_icb_cmd_ready & (cache_line_word_ofs == (CACHE_LINE_WORD_N-1));
	assign cache_line_ren = m_icb_rsp_valid & m_icb_rsp_ready & (icb_rsp_word_ofs == (CACHE_LINE_WORD_N-1));
	
	// 说明: 缓存行地址是对齐到数据块大小的!
	assign cache_line_baseaddr = 
		addr_regs[cache_line_icb_cmd_ptr] & (32'hffff_ffff << clogb2(CACHE_LINE_WORD_N));
	
	genvar cache_line_datblk_i;
	generate
		for(cache_line_datblk_i = 0;cache_line_datblk_i < CACHE_LINE_WORD_N;cache_line_datblk_i = cache_line_datblk_i + 1)
		begin:cache_line_datblk_blk
			assign cache_line_data_block[cache_line_datblk_i] = 
				data_regs[cache_line_icb_cmd_ptr][cache_line_datblk_i*32+31:cache_line_datblk_i*32];
		end
	endgenerate
	
	// 位于ICB命令端的缓存行字偏移量
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			cache_line_word_ofs <= 0;
		else if(m_icb_cmd_valid & m_icb_cmd_ready)
			cache_line_word_ofs <= # SIM_DELAY 
				(cache_line_word_ofs == (CACHE_LINE_WORD_N-1)) ? 
					0:
					(cache_line_word_ofs + 1);
	end
	// 位于ICB响应端的缓存行字偏移量
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			icb_rsp_word_ofs <= 0;
		else if(m_icb_rsp_valid & m_icb_rsp_ready)
			icb_rsp_word_ofs <= # SIM_DELAY 
				(icb_rsp_word_ofs == (CACHE_LINE_WORD_N-1)) ? 
					0:
					(icb_rsp_word_ofs + 1);
	end
	
	/** 缓存行检索 **/
	wire[WBUF_ITEM_N-1:0] addr_cmp_res; // 地址比较结果
	wire[clogb2(WBUF_ITEM_N-1):0] sch_datblk_sel; // 检索结果的数据块选择
	
	assign cache_line_in_wbuf_flag = |addr_cmp_res;
	assign cache_line_sch_datblk = data_regs[sch_datblk_sel];
	
	genvar addr_cmp_i;
	generate
		for(addr_cmp_i = 0;addr_cmp_i < WBUF_ITEM_N;addr_cmp_i = addr_cmp_i + 1)
		begin:addr_cmp_blk
			// 说明: 缓存行地址是对齐到数据块大小的!
			assign addr_cmp_res[addr_cmp_i] = 
				cache_line_valid[addr_cmp_i] & 
				(cache_line_sch_addr[31:clogb2(CACHE_LINE_WORD_N)] == addr_regs[addr_cmp_i][31:clogb2(CACHE_LINE_WORD_N)]);
		end
	endgenerate
	
	assign sch_datblk_sel = onehot_to_bin(addr_cmp_res);
	
endmodule
