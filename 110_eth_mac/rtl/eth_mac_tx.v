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
本模块: 以太网发送

描述:
接收以太网帧数据包, 添加前导码、帧起始界定符、帧检验序列并在必要时填充帧数据, 输出字节流
对于每个以太网帧, 字节流是连续输出的

注意：
无

协议:
AXIS SLAVE

作者: 陈家耀
日期: 2025/04/22
********************************************************************/


module eth_mac_tx #(
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // AXIS从机时钟和复位
	input wire s_axis_aclk,
	input wire s_axis_aresetn,
	// 以太网发送时钟和复位
	input wire eth_tx_aclk,
	input wire eth_tx_aresetn,
	
	// 待发送的以太网帧数据(AXIS从机)
	input wire[15:0] s_axis_data,
	input wire[1:0] s_axis_keep,
	input wire s_axis_last,
	input wire s_axis_valid,
	output wire s_axis_ready,
	
	// 以太网帧字节流
	output wire[7:0] eth_tx_data,
	output wire eth_tx_valid
);
	
	/** 内部配置 **/
	localparam integer MIN_ETH_FRAME_LEN = 14 + 46; // 最小的以太网帧长度(含帧头, 以字节计, 必须是偶数)
	localparam PADDING_BYTE = 8'h00; // 填充字节
	localparam PRE_CODE = 8'h55; // 前导码
	localparam SFD_CODE = 8'hd5; // 帧起始界定符
	
	/** 常量 **/
	// 以太网发送状态独热码索引
	localparam integer ETH_TX_STS_ID_PRE = 0;
	localparam integer ETH_TX_STS_ID_DATA = 1;
	localparam integer ETH_TX_STS_ID_FCS = 2;
	// 以太网帧字节流字段类型
	localparam ETH_BYTE_STRM_PRE = 2'b00;
	localparam ETH_BYTE_STRM_SFD = 2'b01;
	localparam ETH_BYTE_STRM_DATA = 2'b10;
	localparam ETH_BYTE_STRM_FCS = 2'b11;
	
	/** 以太网帧数据乒乓缓存 **/
	// 写端口
	wire eth_frame_wen; // 以太网帧缓存写使能
	wire eth_frame_full_n; // 以太网帧缓存满标志
	reg[1:0] eth_frame_wptr_at_w; // 位于写端口的以太网帧缓存写指针
	wire[1:0] eth_frame_rptr_at_w; // 位于写端口的以太网帧缓存读指针
	wire[1:0] ping_pong_ram_wen_a;
	wire[9:0] ping_pong_ram_addr_a[0:1];
	wire[17:0] ping_pong_ram_din_a[0:1]; // {last(1位), 是否两个字节都有效(1位), data(16位)}
	// 读端口
	wire eth_frame_ren; // 以太网帧缓存读使能
	wire eth_frame_empty_n; // 以太网帧缓存空标志
	wire[1:0] eth_frame_wptr_at_r; // 位于读端口的以太网帧缓存写指针
	reg[1:0] eth_frame_rptr_at_r; // 位于读端口的以太网帧缓存读指针
	wire[1:0] ping_pong_ram_ren_b;
	wire[9:0] ping_pong_ram_addr_b[0:1];
	wire[17:0] ping_pong_ram_dout_b[0:1]; // {last(1位), 是否两个字节都有效(1位), data(16位)}
	
	assign eth_frame_full_n = 
		(eth_frame_wptr_at_w[0] == eth_frame_rptr_at_w[0]) | 
		(eth_frame_wptr_at_w[1] == eth_frame_rptr_at_w[1]);
	assign eth_frame_empty_n = 
		eth_frame_wptr_at_r != eth_frame_rptr_at_r;
	
	// 位于写端口的以太网帧缓存写指针
	always @(posedge s_axis_aclk or negedge s_axis_aresetn)
	begin
		if(~s_axis_aresetn)
			eth_frame_wptr_at_w <= 2'b00;
		else if(eth_frame_wen & eth_frame_full_n)
		begin
			case(eth_frame_wptr_at_w)
				2'b00: eth_frame_wptr_at_w <= # SIM_DELAY 2'b01;
				2'b01: eth_frame_wptr_at_w <= # SIM_DELAY 2'b11;
				2'b11: eth_frame_wptr_at_w <= # SIM_DELAY 2'b10;
				2'b10: eth_frame_wptr_at_w <= # SIM_DELAY 2'b00;
				default: eth_frame_wptr_at_w <= # SIM_DELAY 2'b00;
			endcase
		end
	end
	
	// 位于读端口的以太网帧缓存读指针
	always @(posedge eth_tx_aclk or negedge eth_tx_aresetn)
	begin
		if(~eth_tx_aresetn)
			eth_frame_rptr_at_r <= 2'b00;
		else if(eth_frame_ren & eth_frame_empty_n)
		begin
			case(eth_frame_rptr_at_r)
				2'b00: eth_frame_rptr_at_r <= # SIM_DELAY 2'b01;
				2'b01: eth_frame_rptr_at_r <= # SIM_DELAY 2'b11;
				2'b11: eth_frame_rptr_at_r <= # SIM_DELAY 2'b10;
				2'b10: eth_frame_rptr_at_r <= # SIM_DELAY 2'b00;
				default: eth_frame_rptr_at_r <= # SIM_DELAY 2'b00;
			endcase
		end
	end
	
	bram_simple_dual_port_async #(
		.style("LOW_LATENCY"),
		.mem_width(18),
		.mem_depth(1024),
		.INIT_FILE("no_init"),
		.simulation_delay(SIM_DELAY)
	)ping_pong_ram_u0(
		.clk_a(s_axis_aclk),
		.clk_b(eth_tx_aclk),
		
		.wen_a(ping_pong_ram_wen_a[0]),
		.addr_a(ping_pong_ram_addr_a[0]),
		.din_a(ping_pong_ram_din_a[0]),
		
		.ren_b(ping_pong_ram_ren_b[0]),
		.addr_b(ping_pong_ram_addr_b[0]),
		.dout_b(ping_pong_ram_dout_b[0])
	);
	
	bram_simple_dual_port_async #(
		.style("LOW_LATENCY"),
		.mem_width(18),
		.mem_depth(1024),
		.INIT_FILE("no_init"),
		.simulation_delay(SIM_DELAY)
	)ping_pong_ram_u1(
		.clk_a(s_axis_aclk),
		.clk_b(eth_tx_aclk),
		
		.wen_a(ping_pong_ram_wen_a[1]),
		.addr_a(ping_pong_ram_addr_a[1]),
		.din_a(ping_pong_ram_din_a[1]),
		
		.ren_b(ping_pong_ram_ren_b[1]),
		.addr_b(ping_pong_ram_addr_b[1]),
		.dout_b(ping_pong_ram_dout_b[1])
	);
	
	/*
	跨时钟域: 
		eth_frame_wptr_at_w[0] -> sync_for_eth_frame_wptr_u0/dffs[0]
		eth_frame_wptr_at_w[1] -> sync_for_eth_frame_wptr_u1/dffs[0]
		eth_frame_rptr_at_r[0] -> sync_for_eth_frame_rptr_u0/dffs[0]
		eth_frame_rptr_at_r[1] -> sync_for_eth_frame_rptr_u1/dffs[0]
	*/
	single_bit_syn #(
		.SYN_STAGE(3),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)sync_for_eth_frame_wptr_u0(
		.clk(eth_tx_aclk),
		.rst_n(eth_tx_aresetn),
		
		.single_bit_in(eth_frame_wptr_at_w[0]),
		
		.single_bit_out(eth_frame_wptr_at_r[0])
	);
	single_bit_syn #(
		.SYN_STAGE(3),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)sync_for_eth_frame_wptr_u1(
		.clk(eth_tx_aclk),
		.rst_n(eth_tx_aresetn),
		
		.single_bit_in(eth_frame_wptr_at_w[1]),
		
		.single_bit_out(eth_frame_wptr_at_r[1])
	);
	
	single_bit_syn #(
		.SYN_STAGE(3),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)sync_for_eth_frame_rptr_u0(
		.clk(s_axis_aclk),
		.rst_n(s_axis_aresetn),
		
		.single_bit_in(eth_frame_rptr_at_r[0]),
		
		.single_bit_out(eth_frame_rptr_at_w[0])
	);
	
	single_bit_syn #(
		.SYN_STAGE(3),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)sync_for_eth_frame_rptr_u1(
		.clk(s_axis_aclk),
		.rst_n(s_axis_aresetn),
		
		.single_bit_in(eth_frame_rptr_at_r[1]),
		
		.single_bit_out(eth_frame_rptr_at_w[1])
	);
	
	/** 待发送的以太网帧数据 **/
	reg[9:0] eth_frame_buf_waddr; // 以太网帧缓存写地址
	
	assign s_axis_ready = eth_frame_full_n;
	
	assign eth_frame_wen = s_axis_valid & s_axis_last;
	
	assign ping_pong_ram_wen_a[0] = s_axis_valid & s_axis_ready & ((eth_frame_wptr_at_w == 2'b00) | (eth_frame_wptr_at_w == 2'b11));
	assign ping_pong_ram_wen_a[1] = s_axis_valid & s_axis_ready & ((eth_frame_wptr_at_w == 2'b01) | (eth_frame_wptr_at_w == 2'b10));
	assign ping_pong_ram_addr_a[0] = eth_frame_buf_waddr;
	assign ping_pong_ram_addr_a[1] = eth_frame_buf_waddr;
	assign ping_pong_ram_din_a[0] = {s_axis_last, s_axis_keep[1], s_axis_data};
	assign ping_pong_ram_din_a[1] = {s_axis_last, s_axis_keep[1], s_axis_data};
	
	// 以太网帧缓存写地址
	always @(posedge s_axis_aclk or negedge s_axis_aresetn)
	begin
		if(~s_axis_aresetn)
			eth_frame_buf_waddr <= 10'd0;
		else if(s_axis_valid & s_axis_ready)
			eth_frame_buf_waddr <= # SIM_DELAY 
				s_axis_last ? 
					10'd0:
					(eth_frame_buf_waddr + 10'd1);
	end
	
	/** 以太网发送帧间隙冷却计数器 **/
	wire ifg_cd_trigger;
	wire ifg_cd_ready;
	
	cool_down_cnt #(
		.max_cd(128),
		.EN_TRG_IN_CD("false"),
		.SIM_DELAY(SIM_DELAY)
	)ifg_cd_cnt_u(
		.clk(eth_tx_aclk),
		.rst_n(eth_tx_aresetn),
		
		.cd(100 - 1), // 至少间隔96个周期
		
		.timer_trigger(ifg_cd_trigger),
		.timer_done(),
		.timer_ready(ifg_cd_ready),
		.timer_v()
	);
	
	/** 以太网帧字节流 **/
	reg[3:0] eth_tx_sts; // 以太网发送状态
	reg to_padding_eth_frame; // 填充以太网帧数据(标志)
	reg to_padding_eth_frame_d1; // 延迟1clk的填充以太网帧数据(标志)
	reg at_padding_boundary; // 位于填充边界(指示)
	reg exceed_padding_boundary; // 超越填充边界(指示)
	reg[2:0] eth_tx_field_cnt; // 以太网发送字段计数器
	wire ping_pong_ram_dout_sel; // 以太网帧缓存读数据选择
	reg[9:0] eth_frame_buf_raddr; // 以太网帧缓存读地址
	wire[17:0] eth_fbuf_rdata; // 以太网帧缓存读数据({last(1位), 是否两个字节都有效(1位), data(16位)})
	reg[1:0] eth_byte_strm_field; // 以太网帧字节流字段
	reg eth_byte_sel; // 以太网帧字节流选择高位字节(标志)
	reg eth_byte_strm_oen; // 以太网帧字节流输出使能
	wire[7:0] eth_tx_byte_cur; // 当前的以太网帧字节
	wire eth_tx_last_dw_flag; // 以太网帧最后1个半字(标志)
	wire eth_tx_dw_both_vld_flag; // 以太网帧两个字节都有效(标志)
	wire[31:0] eth_crc32; // 以太网帧CRC32校验码
	reg[1:0] eth_crc32_byte_sel; // 以太网帧CRC32校验码字节选择
	wire[1:0] eth_byte_strm_field_cur; // 当前的以太网帧字节流字段
	wire eth_byte_strm_valid; // 以太网帧字节流有效(标志)
	reg[5:0] early_crc32_flag; // 提前的CRC32字段(独热码标志)
	reg[7:0] eth_tx_data_r; // 输出的以太网帧字节流数据
	reg eth_tx_valid_r; // 输出的以太网帧字节流有效(标志)
	
	assign eth_tx_data = eth_tx_data_r;
	assign eth_tx_valid = eth_tx_valid_r;
	
	assign eth_frame_ren = eth_tx_sts[ETH_TX_STS_ID_FCS] & (eth_tx_field_cnt[1:0] == 2'b11);
	
	assign ifg_cd_trigger = eth_tx_sts[ETH_TX_STS_ID_FCS] & (eth_tx_field_cnt[1:0] == 2'b11);
	
	assign ping_pong_ram_ren_b[0] = eth_tx_sts[ETH_TX_STS_ID_DATA] & (~eth_tx_field_cnt[0]) & (~ping_pong_ram_dout_sel);
	assign ping_pong_ram_ren_b[1] = eth_tx_sts[ETH_TX_STS_ID_DATA] & (~eth_tx_field_cnt[0]) & ping_pong_ram_dout_sel;
	assign ping_pong_ram_addr_b[0] = eth_frame_buf_raddr;
	assign ping_pong_ram_addr_b[1] = eth_frame_buf_raddr;
	
	assign ping_pong_ram_dout_sel = eth_frame_rptr_at_r[0] ^ eth_frame_rptr_at_r[1];
	assign eth_fbuf_rdata = ping_pong_ram_dout_b[ping_pong_ram_dout_sel];
	
	assign eth_tx_byte_cur = 
		to_padding_eth_frame_d1 ? 
			PADDING_BYTE:(
				eth_byte_sel ? 
					(eth_fbuf_rdata[16] ? eth_fbuf_rdata[15:8]:PADDING_BYTE):
					eth_fbuf_rdata[7:0]
			);
	assign eth_tx_last_dw_flag = 
		to_padding_eth_frame_d1 ? 
			at_padding_boundary:
			((at_padding_boundary | exceed_padding_boundary) & eth_fbuf_rdata[17]);
	assign eth_tx_dw_both_vld_flag = 
		(~exceed_padding_boundary) | eth_fbuf_rdata[16];
	
	assign eth_byte_strm_field_cur = 
		early_crc32_flag[0] ? 
			eth_byte_strm_field:
			ETH_BYTE_STRM_FCS;
	assign eth_byte_strm_valid = eth_byte_strm_oen & (~early_crc32_flag[5]);
	
	// 以太网发送状态
	always @(posedge eth_tx_aclk or negedge eth_tx_aresetn)
	begin
		if(~eth_tx_aresetn)
			eth_tx_sts <= 3'b001 << ETH_TX_STS_ID_PRE;
		else if(
			(eth_tx_sts[ETH_TX_STS_ID_PRE] & (eth_tx_field_cnt[2:0] == 3'b111)) | 
			(
				eth_tx_sts[ETH_TX_STS_ID_DATA] & eth_tx_field_cnt[0] & 
				(to_padding_eth_frame | eth_fbuf_rdata[17]) & (eth_frame_buf_raddr >= (MIN_ETH_FRAME_LEN/2))
			) | 
			(eth_tx_sts[ETH_TX_STS_ID_FCS] & (eth_tx_field_cnt[1:0] == 2'b11))
		)
			eth_tx_sts <= # SIM_DELAY 
				({3{eth_tx_sts[ETH_TX_STS_ID_PRE]}} & (3'b001 << ETH_TX_STS_ID_DATA)) | 
				({3{eth_tx_sts[ETH_TX_STS_ID_DATA]}} & (3'b001 << ETH_TX_STS_ID_FCS)) | 
				({3{eth_tx_sts[ETH_TX_STS_ID_FCS]}} & (3'b001 << ETH_TX_STS_ID_PRE));
	end
	
	// 填充以太网帧数据(标志)
	always @(posedge eth_tx_aclk)
	begin
		if(
			(eth_tx_sts[ETH_TX_STS_ID_PRE] & (eth_tx_field_cnt[2:0] == 3'b111)) | 
			(eth_tx_sts[ETH_TX_STS_ID_DATA] & (~to_padding_eth_frame))
		)
			to_padding_eth_frame <= # SIM_DELAY 
				eth_tx_sts[ETH_TX_STS_ID_PRE] ? 
					1'b0:
					(eth_tx_field_cnt[0] & eth_fbuf_rdata[17] & (eth_frame_buf_raddr < (MIN_ETH_FRAME_LEN/2)));
	end
	// 延迟1clk的填充以太网帧数据(标志)
	always @(posedge eth_tx_aclk)
	begin
		if(
			(~eth_tx_sts[ETH_TX_STS_ID_PRE]) | (eth_tx_field_cnt[2:0] != 3'b000) | (eth_frame_empty_n & ifg_cd_ready)
		)
			to_padding_eth_frame_d1 <= # SIM_DELAY to_padding_eth_frame;
	end
	// 位于填充边界(指示), 超越填充边界(指示)
	always @(posedge eth_tx_aclk)
	begin
		if(
			eth_tx_sts[ETH_TX_STS_ID_DATA] & (~eth_tx_field_cnt[0])
		)
		begin
			at_padding_boundary <= # SIM_DELAY eth_frame_buf_raddr == (MIN_ETH_FRAME_LEN/2-1);
			
			exceed_padding_boundary <= # SIM_DELAY eth_frame_buf_raddr > (MIN_ETH_FRAME_LEN/2-1);
		end
	end
	
	// 以太网发送字段计数器
	always @(posedge eth_tx_aclk or negedge eth_tx_aresetn)
	begin
		if(~eth_tx_aresetn)
			eth_tx_field_cnt <= 3'b000;
		else if(
			(~eth_tx_sts[ETH_TX_STS_ID_PRE]) | (eth_tx_field_cnt[2:0] != 3'b000) | (eth_frame_empty_n & ifg_cd_ready)
		)
			eth_tx_field_cnt <= # SIM_DELAY 
				({3{eth_tx_sts[ETH_TX_STS_ID_PRE]}} & (eth_tx_field_cnt[2:0] + 3'b001)) | 
				({3{eth_tx_sts[ETH_TX_STS_ID_DATA]}} & {2'b00, ~eth_tx_field_cnt[0]}) | 
				({3{eth_tx_sts[ETH_TX_STS_ID_FCS]}} & ((eth_tx_field_cnt[1:0] + 2'b01) & 3'b011));
	end
	
	// 以太网帧缓存读地址
	always @(posedge eth_tx_aclk)
	begin
		if(
			(eth_tx_sts[ETH_TX_STS_ID_PRE] & (eth_tx_field_cnt[2:0] == 3'b111)) | 
			(eth_tx_sts[ETH_TX_STS_ID_DATA] & (~eth_tx_field_cnt[0]))
		)
			eth_frame_buf_raddr <= # SIM_DELAY 
				eth_tx_sts[ETH_TX_STS_ID_PRE] ? 
					10'd0:
					(eth_frame_buf_raddr + 10'd1);
	end
	
	// 以太网帧字节流字段, 以太网帧字节流选择高位字节(标志)
	always @(posedge eth_tx_aclk)
	begin
		if(
			(~eth_tx_sts[ETH_TX_STS_ID_PRE]) | (eth_tx_field_cnt[2:0] != 3'b000) | (eth_frame_empty_n & ifg_cd_ready)
		)
		begin
			eth_byte_strm_field <= # SIM_DELAY 
				({2{eth_tx_sts[ETH_TX_STS_ID_PRE]}} & (
						(eth_tx_field_cnt[2:0] == 3'b111) ? 
							ETH_BYTE_STRM_SFD:
							ETH_BYTE_STRM_PRE
					)
				) | 
				({2{eth_tx_sts[ETH_TX_STS_ID_DATA]}} & ETH_BYTE_STRM_DATA) | 
				({2{eth_tx_sts[ETH_TX_STS_ID_FCS]}} & ETH_BYTE_STRM_FCS);
			
			eth_byte_sel <= # SIM_DELAY eth_tx_field_cnt[0];
		end
	end
	
	// 以太网帧字节流输出使能
	always @(posedge eth_tx_aclk or negedge eth_tx_aresetn)
	begin
		if(~eth_tx_aresetn)
			eth_byte_strm_oen <= 1'b0;
		else
			eth_byte_strm_oen <= # SIM_DELAY 
				(~eth_tx_sts[ETH_TX_STS_ID_PRE]) | (eth_tx_field_cnt[2:0] != 3'b000) | (eth_frame_empty_n & ifg_cd_ready);
	end
	
	// 以太网帧CRC32校验码字节选择
	always @(posedge eth_tx_aclk or negedge eth_tx_aresetn)
	begin
		if(~eth_tx_aresetn)
			eth_crc32_byte_sel <= 2'b00;
		else if(eth_byte_strm_valid & (eth_byte_strm_field_cur == ETH_BYTE_STRM_FCS))
			eth_crc32_byte_sel <= # SIM_DELAY eth_crc32_byte_sel + 2'b01;
	end
	
	// 提前的CRC32字段(独热码标志)
	always @(posedge eth_tx_aclk or negedge eth_tx_aresetn)
	begin
		if(~eth_tx_aresetn)
			early_crc32_flag <= 6'b000001;
		else if(
			(~early_crc32_flag[0]) | (
				eth_byte_strm_oen & (~eth_byte_sel) & 
				(eth_byte_strm_field == ETH_BYTE_STRM_DATA) & 
				eth_tx_last_dw_flag & (~eth_tx_dw_both_vld_flag)
			)
		)
			early_crc32_flag <= # SIM_DELAY {early_crc32_flag[4:0], early_crc32_flag[5]};
	end
	
	// 输出的以太网帧字节流数据
	always @(posedge eth_tx_aclk)
	begin
		if(eth_byte_strm_valid)
		begin
			case(eth_byte_strm_field_cur)
				ETH_BYTE_STRM_PRE:
					eth_tx_data_r <= # SIM_DELAY PRE_CODE;
				ETH_BYTE_STRM_SFD:
					eth_tx_data_r <= # SIM_DELAY SFD_CODE;
				ETH_BYTE_STRM_DATA:
					eth_tx_data_r <= # SIM_DELAY eth_tx_byte_cur;
				ETH_BYTE_STRM_FCS:
					eth_tx_data_r <= # SIM_DELAY 
						(eth_crc32_byte_sel == 2'b00) ? 
							(~{
								eth_crc32[24], eth_crc32[25], eth_crc32[26], eth_crc32[27], 
								eth_crc32[28], eth_crc32[29], eth_crc32[30], eth_crc32[31]
							}):
						(eth_crc32_byte_sel == 2'b01) ? 
							(~{
								eth_crc32[16], eth_crc32[17], eth_crc32[18], eth_crc32[19], 
								eth_crc32[20], eth_crc32[21], eth_crc32[22], eth_crc32[23]
							}):
						(eth_crc32_byte_sel == 2'b10) ? 
							(~{
								eth_crc32[8], eth_crc32[9], eth_crc32[10], eth_crc32[11], 
								eth_crc32[12], eth_crc32[13], eth_crc32[14], eth_crc32[15]
							}):
							(~{
								eth_crc32[0], eth_crc32[1], eth_crc32[2], eth_crc32[3], 
								eth_crc32[4], eth_crc32[5], eth_crc32[6], eth_crc32[7]
							});
				default:
					eth_tx_data_r <= # SIM_DELAY PRE_CODE;
			endcase
		end
	end
	
	// 输出的以太网帧字节流有效(标志)
	always @(posedge eth_tx_aclk or negedge eth_tx_aresetn)
	begin
		if(~eth_tx_aresetn)
			eth_tx_valid_r <= 1'b0;
		else
			eth_tx_valid_r <= # SIM_DELAY eth_byte_strm_valid;
	end
	
	crc32_d8 #(
		.SIM_DELAY(SIM_DELAY)
	)crc32_d8_u(
		.clk(eth_tx_aclk),
		.rst_n(eth_tx_aresetn),
		
		.data(eth_tx_byte_cur),
		.crc_en(eth_byte_strm_valid & (eth_byte_strm_field_cur == ETH_BYTE_STRM_DATA)),
		.crc_clr(eth_byte_strm_valid & (eth_byte_strm_field_cur == ETH_BYTE_STRM_SFD)),
		.crc_data(eth_crc32),
		.crc_next()
	);
	
endmodule
