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
本模块: AXI通用DMA引擎写数据实时统计

描述:
对输入数据流的传输字节数进行实时统计, 对仅包含传输首地址的命令做进一步处理, 
得到带传输首地址和待传输字节数的命令

注意：
无论命令AXIS接口与输入数据流AXIS接口是否使用相同的时钟和复位, 默认都做跨时钟域处理

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/01/27
********************************************************************/


module axi_dma_engine_wdata_stat #(
	parameter integer DATA_WIDTH = 32, // 传输数据位宽(32 | 64 | 128 | 256)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 命令AXIS接口的时钟和复位
	input wire cmd_axis_aclk,
	input wire cmd_axis_aresetn,
	// 输入数据流AXIS接口的时钟和复位
	input wire s2mm_axis_aclk,
	input wire s2mm_axis_aresetn,
	
	// 命令AXIS从机
	input wire[31:0] s_cmd_axis_data, // {传输首地址(32bit)}
	input wire s_cmd_axis_user, // {固定(1'b1)/递增(1'b0)传输(1bit)}
	input wire s_cmd_axis_valid,
	output wire s_cmd_axis_ready,
	// 命令AXIS主机
	output wire[55:0] m_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	output wire m_cmd_axis_user, // {固定(1'b1)/递增(1'b0)传输(1bit)}
	output wire m_cmd_axis_last, // 标志自动分割后命令包的最后1条
	output wire m_cmd_axis_valid,
	input wire m_cmd_axis_ready,
	
	// 输入数据流AXIS从机
	input wire[DATA_WIDTH-1:0] s_s2mm_axis_data,
	input wire[DATA_WIDTH/8-1:0] s_s2mm_axis_keep,
	input wire s_s2mm_axis_last,
	input wire s_s2mm_axis_valid,
	output wire s_s2mm_axis_ready,
	// 输入数据流AXIS主机
	output wire[DATA_WIDTH-1:0] m_s2mm_axis_data,
	output wire[DATA_WIDTH/8-1:0] m_s2mm_axis_keep,
	output wire m_s2mm_axis_last,
	output wire m_s2mm_axis_valid,
	input wire m_s2mm_axis_ready
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
	// 计算32位数据中1的个数
    function [5:0] count1_of_u32(input[31:0] data);
        integer i;
    begin
        count1_of_u32 = 6'd0;
        
        for(i = 0;i < 32;i = i + 1)
        begin
            if(data[i])
                count1_of_u32 = count1_of_u32 + 6'd1;
        end
    end
    endfunction
	
	/** 常量 **/
	// 命令生成控制状态常量
	localparam CMD_GEN_STS_IDLE = 2'b00; // 状态:空闲
	localparam CMD_GEN_STS_WAIT_PKT_MSG = 2'b01; // 状态:等待数据包信息就绪
	localparam CMD_GEN_STS_PST_ACPT = 2'b10; // 状态:等待后级握手
	localparam CMD_GEN_STS_BUF_ACK = 2'b11; // 状态:等待"输入数据字节数统计"应答
	
	/**
	输入数据流缓存区
	
	设置两组RAM来实现输入数据的乒乓缓存
	**/
	// 输入数据字节数统计
	wire[5:0] in_bytes_n_cur; // 当前输入数据的字节数
	reg[clogb2(512*DATA_WIDTH/8):0] s2mm_bytes_n[0:1]; // 每组输入数据缓存所存储的字节数
	reg s2mm_last_pkt[0:1]; // 每组输入数据缓存是否对应最后1个数据包
	reg s2mm_bytes_n_vld[0:1]; // 输入数据缓存字节数有效标志(输入数据端)
	wire s2mm_bytes_n_alrdy_read[0:1]; // 输入数据缓存字节数已读标志(输入数据端)
	// 缓存区最后1个有效地址
	reg[8:0] s2mm_buf_last_vld_addr[0:1];
	// 缓存区写端口
	reg[1:0] s2mm_buf_wptr; // 缓存写指针
	wire[1:0] s2mm_buf_mem_wen; // 缓存MEM写使能
	reg[8:0] s2mm_buf_mem_waddr; // 缓存MEM写地址
	wire[DATA_WIDTH+DATA_WIDTH/8-1:0] s2mm_buf_mem_din; // 缓存MEM写数据({data(DATA_WIDTH bit), keep(DATA_WIDTH/8 bit)})
	// 缓存区读端口
	reg[1:0] s2mm_buf_rptr; // 缓存读指针
	wire[1:0] s2mm_buf_mem_ren; // 缓存MEM读使能
	reg[8:0] s2mm_buf_mem_raddr; // 缓存MEM读地址
	wire[DATA_WIDTH+DATA_WIDTH/8-1:0] s2mm_buf_mem_dout[0:1]; // 缓存MEM读数据({data(DATA_WIDTH bit), keep(DATA_WIDTH/8 bit)})
	// 输入数据缓存MEM读阶段#0
	wire m_s2mm_s0_last;
	wire m_s2mm_s0_valid;
	wire m_s2mm_s0_ready;
	// 输入数据缓存MEM读阶段#1
	reg s2mm_buf_mem_rsel; // 缓存MEM读数据选择
	reg m_s2mm_s1_last;
	reg m_s2mm_s1_valid;
	wire m_s2mm_s1_ready;
	
	assign s_s2mm_axis_ready = 
		((s2mm_buf_wptr[1] ^~ s2mm_buf_rptr[1]) | (s2mm_buf_wptr[0] ^ s2mm_buf_rptr[0])) & 
		(~s2mm_bytes_n_vld[s2mm_buf_wptr[0]]);
	
	assign {m_s2mm_axis_data, m_s2mm_axis_keep} = s2mm_buf_mem_dout[s2mm_buf_mem_rsel];
	assign m_s2mm_axis_last = m_s2mm_s1_last;
	assign m_s2mm_axis_valid = m_s2mm_s1_valid;
	
	assign in_bytes_n_cur = count1_of_u32(32'h0000_0000 | s_s2mm_axis_keep);
	
	assign s2mm_buf_mem_wen = {2{s_s2mm_axis_valid & s_s2mm_axis_ready}} & {s2mm_buf_wptr[0], ~s2mm_buf_wptr[0]};
	assign s2mm_buf_mem_din = {s_s2mm_axis_data, s_s2mm_axis_keep};
	
	assign s2mm_buf_mem_ren = {2{m_s2mm_s0_valid & m_s2mm_s0_ready}} & {s2mm_buf_rptr[0], ~s2mm_buf_rptr[0]};
	assign m_s2mm_s0_last = s2mm_buf_mem_raddr == s2mm_buf_last_vld_addr[s2mm_buf_rptr[0]];
	assign m_s2mm_s0_valid = s2mm_buf_wptr != s2mm_buf_rptr;
	assign m_s2mm_s0_ready = (~m_s2mm_s1_valid) | m_s2mm_s1_ready;
	assign m_s2mm_s1_ready = m_s2mm_axis_ready;
	
	// 每组输入数据缓存所存储的字节数
	always @(posedge s2mm_axis_aclk or negedge s2mm_axis_aresetn)
	begin
		if(~s2mm_axis_aresetn)
			s2mm_bytes_n[0] <= 0;
		else if((s2mm_bytes_n_vld[0] & s2mm_bytes_n_alrdy_read[0]) | ((~s2mm_buf_wptr[0]) & s_s2mm_axis_valid & s_s2mm_axis_ready))
			s2mm_bytes_n[0] <= # SIM_DELAY 
				// (s2mm_bytes_n_vld[0] & s2mm_bytes_n_alrdy_read[0]) ? 0:(s2mm_bytes_n[0] + in_bytes_n_cur)
				{(clogb2(512*DATA_WIDTH/8)+1){~(s2mm_bytes_n_vld[0] & s2mm_bytes_n_alrdy_read[0])}} & 
				(s2mm_bytes_n[0] + in_bytes_n_cur);
	end
	always @(posedge s2mm_axis_aclk or negedge s2mm_axis_aresetn)
	begin
		if(~s2mm_axis_aresetn)
			s2mm_bytes_n[1] <= 0;
		else if((s2mm_bytes_n_vld[1] & s2mm_bytes_n_alrdy_read[1]) | (s2mm_buf_wptr[0] & s_s2mm_axis_valid & s_s2mm_axis_ready))
			s2mm_bytes_n[1] <= # SIM_DELAY 
				// (s2mm_bytes_n_vld[1] & s2mm_bytes_n_alrdy_read[1]) ? 0:(s2mm_bytes_n[1] + in_bytes_n_cur)
				{(clogb2(512*DATA_WIDTH/8)+1){~(s2mm_bytes_n_vld[1] & s2mm_bytes_n_alrdy_read[1])}} & 
				(s2mm_bytes_n[1] + in_bytes_n_cur);
	end
	
	// 每组输入数据缓存是否对应最后1个数据包
	always @(posedge s2mm_axis_aclk)
	begin
		if((~s2mm_buf_wptr[0]) & s_s2mm_axis_valid & s_s2mm_axis_ready & ((s2mm_buf_mem_waddr == 9'd511) | s_s2mm_axis_last))
			s2mm_last_pkt[0] <= # SIM_DELAY s_s2mm_axis_last;
	end
	always @(posedge s2mm_axis_aclk)
	begin
		if(s2mm_buf_wptr[0] & s_s2mm_axis_valid & s_s2mm_axis_ready & ((s2mm_buf_mem_waddr == 9'd511) | s_s2mm_axis_last))
			s2mm_last_pkt[1] <= # SIM_DELAY s_s2mm_axis_last;
	end
	
	// 输入数据缓存字节数有效标志
	always @(posedge s2mm_axis_aclk or negedge s2mm_axis_aresetn)
	begin
		if(~s2mm_axis_aresetn)
			s2mm_bytes_n_vld[0] <= 1'b0;
		else if(s2mm_bytes_n_vld[0] ? 
			s2mm_bytes_n_alrdy_read[0]:
			((~s2mm_buf_wptr[0]) & s_s2mm_axis_valid & s_s2mm_axis_ready & ((s2mm_buf_mem_waddr == 9'd511) | s_s2mm_axis_last)))
			s2mm_bytes_n_vld[0] <= # SIM_DELAY ~s2mm_bytes_n_vld[0];
	end
	always @(posedge s2mm_axis_aclk or negedge s2mm_axis_aresetn)
	begin
		if(~s2mm_axis_aresetn)
			s2mm_bytes_n_vld[1] <= 1'b0;
		else if(s2mm_bytes_n_vld[1] ? 
			s2mm_bytes_n_alrdy_read[1]:
			(s2mm_buf_wptr[0] & s_s2mm_axis_valid & s_s2mm_axis_ready & ((s2mm_buf_mem_waddr == 9'd511) | s_s2mm_axis_last)))
			s2mm_bytes_n_vld[1] <= # SIM_DELAY ~s2mm_bytes_n_vld[1];
	end
	
	// 缓存区最后1个有效地址
	always @(posedge s2mm_axis_aclk)
	begin
		if((~s2mm_buf_wptr[0]) & s_s2mm_axis_valid & s_s2mm_axis_ready & ((s2mm_buf_mem_waddr == 9'd511) | s_s2mm_axis_last))
			s2mm_buf_last_vld_addr[0] <= # SIM_DELAY s2mm_buf_mem_waddr;
	end
	always @(posedge s2mm_axis_aclk)
	begin
		if(s2mm_buf_wptr[0] & s_s2mm_axis_valid & s_s2mm_axis_ready & ((s2mm_buf_mem_waddr == 9'd511) | s_s2mm_axis_last))
			s2mm_buf_last_vld_addr[1] <= # SIM_DELAY s2mm_buf_mem_waddr;
	end
	
	// 缓存写指针
	always @(posedge s2mm_axis_aclk or negedge s2mm_axis_aresetn)
	begin
		if(~s2mm_axis_aresetn)
			s2mm_buf_wptr <= 2'b00;
		else if(s_s2mm_axis_valid & s_s2mm_axis_ready & ((s2mm_buf_mem_waddr == 9'd511) | s_s2mm_axis_last))
			s2mm_buf_wptr <= # SIM_DELAY s2mm_buf_wptr + 2'b01;
	end
	// 缓存MEM写地址
	always @(posedge s2mm_axis_aclk or negedge s2mm_axis_aresetn)
	begin
		if(~s2mm_axis_aresetn)
			s2mm_buf_mem_waddr <= 9'd0;
		else if(s_s2mm_axis_valid & s_s2mm_axis_ready)
			// ((s2mm_buf_mem_waddr == 9'd511) | s_s2mm_axis_last) ? 9'd0:(s2mm_buf_mem_waddr + 9'd1)
			s2mm_buf_mem_waddr <= # SIM_DELAY {9{~((s2mm_buf_mem_waddr == 9'd511) | s_s2mm_axis_last)}} & (s2mm_buf_mem_waddr + 9'd1);
	end
	
	// 缓存读指针
	always @(posedge s2mm_axis_aclk or negedge s2mm_axis_aresetn)
	begin
		if(~s2mm_axis_aresetn)
			s2mm_buf_rptr <= 2'b00;
		else if(m_s2mm_s0_valid & m_s2mm_s0_ready & m_s2mm_s0_last)
			s2mm_buf_rptr <= # SIM_DELAY s2mm_buf_rptr + 2'b01;
	end
	// 缓存MEM读地址
	always @(posedge s2mm_axis_aclk or negedge s2mm_axis_aresetn)
	begin
		if(~s2mm_axis_aresetn)
			s2mm_buf_mem_raddr <= 9'd0;
		else if(m_s2mm_s0_valid & m_s2mm_s0_ready)
			// m_s2mm_s0_last ? 9'd0:(s2mm_buf_mem_raddr + 9'd1)
			s2mm_buf_mem_raddr <= # SIM_DELAY {9{~m_s2mm_s0_last}} & (s2mm_buf_mem_raddr + 9'd1);
	end
	// 缓存MEM读数据选择
	always @(posedge s2mm_axis_aclk)
	begin
		if(m_s2mm_s0_valid & m_s2mm_s0_ready)
			s2mm_buf_mem_rsel <= # SIM_DELAY s2mm_buf_rptr[0];
	end
	// 输入数据流AXIS主机的last信号
	always @(posedge s2mm_axis_aclk)
	begin
		if(m_s2mm_s0_valid & m_s2mm_s0_ready)
			m_s2mm_s1_last <= # SIM_DELAY m_s2mm_s0_last;
	end
	// 输入数据流AXIS主机的valid信号
	always @(posedge s2mm_axis_aclk or negedge s2mm_axis_aresetn)
	begin
		if(~s2mm_axis_aresetn)
			m_s2mm_s1_valid <= 1'b0;
		else if(m_s2mm_s0_ready)
			m_s2mm_s1_valid <= # SIM_DELAY m_s2mm_s0_valid;
	end
	
	// 输入数据缓存MEM#0
	bram_single_port #(
		.style("LOW_LATENCY"),
		.rw_mode("no_change"),
		.mem_width(DATA_WIDTH+DATA_WIDTH/8),
		.mem_depth(512),
		.INIT_FILE("no_init"),
		.byte_write_mode("false"),
		.simulation_delay(SIM_DELAY)
	)s2mm_buf_mem_a(
		.clk(s2mm_axis_aclk),
		
		.en(s2mm_buf_mem_wen[0] | s2mm_buf_mem_ren[0]),
		.wen(s2mm_buf_mem_wen[0]),
		.addr(s2mm_buf_mem_wen[0] ? s2mm_buf_mem_waddr:s2mm_buf_mem_raddr),
		.din(s2mm_buf_mem_din),
		.dout(s2mm_buf_mem_dout[0])
	);
	// 输入数据缓存MEM#1
	bram_single_port #(
		.style("LOW_LATENCY"),
		.rw_mode("no_change"),
		.mem_width(DATA_WIDTH+DATA_WIDTH/8),
		.mem_depth(512),
		.INIT_FILE("no_init"),
		.byte_write_mode("false"),
		.simulation_delay(SIM_DELAY)
	)s2mm_buf_mem_b(
		.clk(s2mm_axis_aclk),
		
		.en(s2mm_buf_mem_wen[1] | s2mm_buf_mem_ren[1]),
		.wen(s2mm_buf_mem_wen[1]),
		.addr(s2mm_buf_mem_wen[1] ? s2mm_buf_mem_waddr:s2mm_buf_mem_raddr),
		.din(s2mm_buf_mem_din),
		.dout(s2mm_buf_mem_dout[1])
	);
	
	/**
	两级同步器
	
	跨时钟域:
		s2mm_bytes_n_vld[0] -> s2mm_bytes_n_vld_d[0]
		s2mm_bytes_n_vld[1] -> s2mm_bytes_n_vld_d[1]
		
		s2mm_bytes_n_read[0] -> s2mm_bytes_n_read_d[0]
		s2mm_bytes_n_read[1] -> s2mm_bytes_n_read_d[1]
	**/
	// 从输入数据时钟到命令时钟
	reg s2mm_bytes_n_vld_d[0:1]; // 延迟1clk的输入数据缓存字节数有效标志(命令端)
	reg s2mm_bytes_n_vld_d2[0:1]; // 延迟2clk的输入数据缓存字节数有效标志(命令端)
	// 从命令时钟到输入数据时钟
	reg s2mm_bytes_n_read[0:1]; // 输入数据缓存字节数已读标志(命令端)
	reg s2mm_bytes_n_read_d[0:1]; // 延迟1clk的输入数据缓存字节数已读标志(输入数据端)
	reg s2mm_bytes_n_read_d2[0:1]; // 延迟2clk的输入数据缓存字节数已读标志(输入数据端)
	
	assign s2mm_bytes_n_alrdy_read[0] = s2mm_bytes_n_read_d2[0];
	assign s2mm_bytes_n_alrdy_read[1] = s2mm_bytes_n_read_d2[1];
	
	// 延迟1clk的输入数据缓存字节数有效标志
	always @(posedge cmd_axis_aclk or negedge cmd_axis_aresetn)
	begin
		if(~cmd_axis_aresetn)
			{s2mm_bytes_n_vld_d[0], s2mm_bytes_n_vld_d[1]} <= 2'b00;
		else
			{s2mm_bytes_n_vld_d[0], s2mm_bytes_n_vld_d[1]} <= # SIM_DELAY {s2mm_bytes_n_vld[0], s2mm_bytes_n_vld[1]};
	end
	// 延迟2clk的输入数据缓存字节数有效标志
	always @(posedge cmd_axis_aclk or negedge cmd_axis_aresetn)
	begin
		if(~cmd_axis_aresetn)
			{s2mm_bytes_n_vld_d2[0], s2mm_bytes_n_vld_d2[1]} <= 2'b00;
		else
			{s2mm_bytes_n_vld_d2[0], s2mm_bytes_n_vld_d2[1]} <= # SIM_DELAY {s2mm_bytes_n_vld_d[0], s2mm_bytes_n_vld_d[1]};
	end
	
	// 延迟1clk的输入数据缓存字节数已读标志(输入数据端)
	always @(posedge s2mm_axis_aclk or negedge s2mm_axis_aresetn)
	begin
		if(~s2mm_axis_aresetn)
			{s2mm_bytes_n_read_d[0], s2mm_bytes_n_read_d[1]} <= 2'b00;
		else
			{s2mm_bytes_n_read_d[0], s2mm_bytes_n_read_d[1]} <= # SIM_DELAY {s2mm_bytes_n_read[0], s2mm_bytes_n_read[1]};
	end
	// 延迟2clk的输入数据缓存字节数已读标志(输入数据端)
	always @(posedge s2mm_axis_aclk or negedge s2mm_axis_aresetn)
	begin
		if(~s2mm_axis_aresetn)
			{s2mm_bytes_n_read_d2[0], s2mm_bytes_n_read_d2[1]} <= 2'b00;
		else
			{s2mm_bytes_n_read_d2[0], s2mm_bytes_n_read_d2[1]} <= # SIM_DELAY {s2mm_bytes_n_read_d[0], s2mm_bytes_n_read_d[1]};
	end
	
	/**
	命令生成
	
	跨时钟域:
		s2mm_bytes_n[0] -> cmd_btt
		s2mm_bytes_n[1] -> cmd_btt
		
		s2mm_last_pkt[0] -> cmd_is_last_pkt
		s2mm_last_pkt[1] -> cmd_is_last_pkt
	**/
	reg[1:0] cmd_gen_sts; // 命令生成控制当前状态
	reg[31:0] cmd_addr; // 传输首地址
	reg[23:0] cmd_btt; // 待传输字节数
	reg cmd_is_fixed; // 是否固定传输
	reg cmd_is_last_pkt; // 是否最后一个数据包
	reg pkt_msg_rptr; // 数据包信息读指针
	
	assign s_cmd_axis_ready = cmd_gen_sts == CMD_GEN_STS_IDLE;
	
	assign m_cmd_axis_data = {cmd_btt, cmd_addr};
	assign m_cmd_axis_user = cmd_is_fixed;
	assign m_cmd_axis_last = cmd_is_last_pkt;
	assign m_cmd_axis_valid = cmd_gen_sts == CMD_GEN_STS_PST_ACPT;
	
	// 输入数据缓存字节数已读标志(命令端)
	always @(posedge cmd_axis_aclk or negedge cmd_axis_aresetn)
	begin
		if(~cmd_axis_aresetn)
			s2mm_bytes_n_read[0] <= 1'b0;
		else if(
			(~pkt_msg_rptr) & 
			(
				((cmd_gen_sts == CMD_GEN_STS_PST_ACPT) & m_cmd_axis_ready) | 
				((cmd_gen_sts == CMD_GEN_STS_BUF_ACK) & (~s2mm_bytes_n_vld_d2[0]))
			)
		)
			s2mm_bytes_n_read[0] <= # SIM_DELAY cmd_gen_sts == CMD_GEN_STS_PST_ACPT;
	end
	always @(posedge cmd_axis_aclk or negedge cmd_axis_aresetn)
	begin
		if(~cmd_axis_aresetn)
			s2mm_bytes_n_read[1] <= 1'b0;
		else if(
			pkt_msg_rptr & 
			(
				((cmd_gen_sts == CMD_GEN_STS_PST_ACPT) & m_cmd_axis_ready) | 
				((cmd_gen_sts == CMD_GEN_STS_BUF_ACK) & (~s2mm_bytes_n_vld_d2[1]))
			)
		)
			s2mm_bytes_n_read[1] <= # SIM_DELAY cmd_gen_sts == CMD_GEN_STS_PST_ACPT;
	end
	
	// 命令生成控制当前状态
	always @(posedge cmd_axis_aclk or negedge cmd_axis_aresetn)
	begin
		if(~cmd_axis_aresetn)
			cmd_gen_sts <= CMD_GEN_STS_IDLE;
		else if(
			((cmd_gen_sts == CMD_GEN_STS_IDLE) & s_cmd_axis_valid) | 
			((cmd_gen_sts == CMD_GEN_STS_WAIT_PKT_MSG) & s2mm_bytes_n_vld_d2[pkt_msg_rptr]) | 
			((cmd_gen_sts == CMD_GEN_STS_PST_ACPT) & m_cmd_axis_ready) | 
			((cmd_gen_sts == CMD_GEN_STS_BUF_ACK) & (~s2mm_bytes_n_vld_d2[pkt_msg_rptr]))
		)
			cmd_gen_sts <= # SIM_DELAY 
				({2{cmd_gen_sts == CMD_GEN_STS_IDLE}} & CMD_GEN_STS_WAIT_PKT_MSG) | 
				({2{cmd_gen_sts == CMD_GEN_STS_WAIT_PKT_MSG}} & CMD_GEN_STS_PST_ACPT) | 
				({2{cmd_gen_sts == CMD_GEN_STS_PST_ACPT}} & CMD_GEN_STS_BUF_ACK) | 
				({2{cmd_gen_sts == CMD_GEN_STS_BUF_ACK}} & (cmd_is_last_pkt ? CMD_GEN_STS_IDLE:CMD_GEN_STS_WAIT_PKT_MSG));
	end
	
	// 传输首地址
	always @(posedge cmd_axis_aclk)
	begin
		if(
			((cmd_gen_sts == CMD_GEN_STS_IDLE) & s_cmd_axis_valid) | 
			((cmd_gen_sts == CMD_GEN_STS_BUF_ACK) & (~s2mm_bytes_n_vld_d2[pkt_msg_rptr]) & (~cmd_is_last_pkt))
		)
			cmd_addr <= # SIM_DELAY (cmd_gen_sts == CMD_GEN_STS_IDLE) ? s_cmd_axis_data:(cmd_addr + cmd_btt);
	end
	// 待传输字节数
	always @(posedge cmd_axis_aclk)
	begin
		if((cmd_gen_sts == CMD_GEN_STS_WAIT_PKT_MSG) & s2mm_bytes_n_vld_d2[pkt_msg_rptr])
			cmd_btt <= # SIM_DELAY s2mm_bytes_n[pkt_msg_rptr];
	end
	// 是否固定传输
	always @(posedge cmd_axis_aclk)
	begin
		if((cmd_gen_sts == CMD_GEN_STS_IDLE) & s_cmd_axis_valid)
			cmd_is_fixed <= # SIM_DELAY s_cmd_axis_user;
	end
	// 是否最后一个数据包
	always @(posedge cmd_axis_aclk)
	begin
		if((cmd_gen_sts == CMD_GEN_STS_WAIT_PKT_MSG) & s2mm_bytes_n_vld_d2[pkt_msg_rptr])
			cmd_is_last_pkt <= # SIM_DELAY s2mm_last_pkt[pkt_msg_rptr];
	end
	
	// 数据包信息读指针
	always @(posedge cmd_axis_aclk or negedge cmd_axis_aresetn)
	begin
		if(~cmd_axis_aresetn)
			pkt_msg_rptr <= 1'b0;
		else if((cmd_gen_sts == CMD_GEN_STS_BUF_ACK) & (~s2mm_bytes_n_vld_d2[pkt_msg_rptr]))
			pkt_msg_rptr <= # SIM_DELAY ~pkt_msg_rptr;
	end
	
endmodule
