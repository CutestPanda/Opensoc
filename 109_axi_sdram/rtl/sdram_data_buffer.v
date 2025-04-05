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
本模块: sdram数据缓冲区

描述:
写数据/读数据广义fifo

注意：
写数据/读数据广义fifo的MEM读延迟 = 1clk
当突发长度为全页时, 写/读数据广义fifo的数据片深度为sdram列数(SDRAM_COL_N), 其他情况时为突发长度
在写数据/读数据AXIS中, 用last信号来分隔每次突发
读写数据buffer深度(RW_DATA_BUF_DEPTH)应至少是sdram列数(SDRAM_COL_N)*2

协议:
AXIS MASTER/SLAVE
EXT FIFO READ/WRITE

作者: 陈家耀
日期: 2025/02/28
********************************************************************/


module sdram_data_buffer #(
    parameter integer RW_DATA_BUF_DEPTH = 1024, // 读写数据buffer深度(512 | 1024 | 2048 | 4096 | 8192)
    parameter EN_IMDT_STAT_WBURST_LEN = "false", // 是否使能实时统计写突发长度(仅对全页突发有效)
    parameter integer BURST_LEN = -1, // 突发长度(-1 -> 全页; 1 | 2 | 4 | 8)
    parameter integer DATA_WIDTH = 32, // 数据位宽(8 | 16 | 32 | 64)
	parameter integer SDRAM_COL_N = 256, // sdram列数(64 | 128 | 256 | 512 | 1024)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 写数据AXIS
    input wire[DATA_WIDTH-1:0] s_axis_wt_data,
    input wire[DATA_WIDTH/8-1:0] s_axis_wt_keep,
    input wire s_axis_wt_last,
    input wire s_axis_wt_valid,
    output wire s_axis_wt_ready,
    // 读数据AXIS
    output wire[DATA_WIDTH-1:0] m_axis_rd_data,
    output wire m_axis_rd_last,
    output wire m_axis_rd_valid,
    input wire m_axis_rd_ready,
    
    // 写数据广义fifo读端口
    input wire wdata_ext_fifo_ren,
    output wire wdata_ext_fifo_empty_n,
    input wire wdata_ext_fifo_mem_ren,
    input wire[15:0] wdata_ext_fifo_mem_raddr,
    output wire[DATA_WIDTH+DATA_WIDTH/8-1:0] wdata_ext_fifo_mem_dout, // {keep(DATA_WIDTH/8 bit), data(DATA_WIDTH bit)}
    
    // 读数据广义fifo写端口
    input wire rdata_ext_fifo_wen,
    output wire rdata_ext_fifo_full_n,
    input wire rdata_ext_fifo_mem_wen,
    input wire[15:0] rdata_ext_fifo_mem_waddr,
    input wire[DATA_WIDTH:0] rdata_ext_fifo_mem_din, // {last(1bit), data(DATA_WIDTH bit)}
    
    // 实时统计写突发长度fifo读端口
	// 断言: 写数据广义fifo非空时, 实时统计写突发长度fifo必定非空!
    input wire imdt_stat_wburst_len_fifo_ren,
    output wire[15:0] imdt_stat_wburst_len_fifo_dout
);
	
    // 计算log2(bit_depth)
    function integer clogb2 (input integer bit_depth);
        integer temp;
    begin
        temp = bit_depth;
        for(clogb2 = -1;temp > 0;clogb2 = clogb2 + 1)
            temp = temp >> 1;
    end
    endfunction
    
    /** 常量 **/
	// 写数据/读数据广义fifo的存储项数
    localparam integer EXT_FIFO_ITEM_N = 
		(BURST_LEN == -1) ? 
			(RW_DATA_BUF_DEPTH / SDRAM_COL_N):
			(RW_DATA_BUF_DEPTH / BURST_LEN);
    
    /** 写数据广义fifo **/
    reg[clogb2(EXT_FIFO_ITEM_N):0] wdata_ext_fifo_item_n; // 写数据广义fifo当前的存储项数
	wire imdt_stat_wburst_len_fifo_full_n; // 实时统计写突发长度fifo满标志
    // 写数据广义fifo读端口
    reg wdata_ext_fifo_empty_n_r;
    // 写数据广义fifo写端口
    wire wdata_ext_fifo_wen;
    reg wdata_ext_fifo_full_n;
    wire wdata_ext_fifo_mem_wen;
    reg[clogb2(RW_DATA_BUF_DEPTH-1):0] wdata_ext_fifo_mem_waddr;
    wire[DATA_WIDTH+DATA_WIDTH/8-1:0] wdata_ext_fifo_mem_din;
    
    assign s_axis_wt_ready = wdata_ext_fifo_full_n & imdt_stat_wburst_len_fifo_full_n;
    assign wdata_ext_fifo_empty_n = wdata_ext_fifo_empty_n_r;
    
    assign wdata_ext_fifo_wen = s_axis_wt_valid & s_axis_wt_ready & s_axis_wt_last;
    assign wdata_ext_fifo_mem_wen = s_axis_wt_valid & s_axis_wt_ready;
    assign wdata_ext_fifo_mem_din = {s_axis_wt_keep, s_axis_wt_data};
    
    // 写数据广义fifo当前的存储项数
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wdata_ext_fifo_item_n <= 0;
        else if((wdata_ext_fifo_wen & wdata_ext_fifo_full_n) ^ (wdata_ext_fifo_ren & wdata_ext_fifo_empty_n))
            wdata_ext_fifo_item_n <= # SIM_DELAY 
				(wdata_ext_fifo_wen & wdata_ext_fifo_full_n) ? 
					(wdata_ext_fifo_item_n + 1):
					(wdata_ext_fifo_item_n - 1);
    end
    // 写数据广义fifo空标志
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wdata_ext_fifo_empty_n_r <= 1'b0;
        else if((wdata_ext_fifo_wen & wdata_ext_fifo_full_n) ^ (wdata_ext_fifo_ren & wdata_ext_fifo_empty_n))
            wdata_ext_fifo_empty_n_r <= # SIM_DELAY 
				(wdata_ext_fifo_wen & wdata_ext_fifo_full_n) | 
				(wdata_ext_fifo_item_n != 1);
    end
    // 写数据广义fifo满标志
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wdata_ext_fifo_full_n <= 1'b1;
        else if((wdata_ext_fifo_wen & wdata_ext_fifo_full_n) ^ (wdata_ext_fifo_ren & wdata_ext_fifo_empty_n))
            wdata_ext_fifo_full_n <= # SIM_DELAY 
				(wdata_ext_fifo_ren & wdata_ext_fifo_empty_n) | 
				(wdata_ext_fifo_item_n != (EXT_FIFO_ITEM_N - 1));
    end
    
    // 写数据广义fifo的MEM写地址
    generate
        if(BURST_LEN == -1)
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_waddr[clogb2(RW_DATA_BUF_DEPTH-1):clogb2(SDRAM_COL_N-1)+1] <= 0;
                else if(s_axis_wt_valid & s_axis_wt_ready & s_axis_wt_last)
                    wdata_ext_fifo_mem_waddr[clogb2(RW_DATA_BUF_DEPTH-1):clogb2(SDRAM_COL_N-1)+1] <= # SIM_DELAY 
						wdata_ext_fifo_mem_waddr[clogb2(RW_DATA_BUF_DEPTH-1):clogb2(SDRAM_COL_N-1)+1] + 1;
            end
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_waddr[clogb2(SDRAM_COL_N-1):0] <= 0;
                else if(s_axis_wt_valid & s_axis_wt_ready)
                    wdata_ext_fifo_mem_waddr[clogb2(SDRAM_COL_N-1):0] <= # SIM_DELAY 
						s_axis_wt_last ? 0:(wdata_ext_fifo_mem_waddr[clogb2(SDRAM_COL_N-1):0] + 1);
            end
        end
        else
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_waddr <= 0;
                else if(s_axis_wt_valid & s_axis_wt_ready)
                    wdata_ext_fifo_mem_waddr <= # SIM_DELAY wdata_ext_fifo_mem_waddr + 1;
            end
        end
    endgenerate
    
    // 简单双口RAM
    bram_simple_dual_port #(
        .style("LOW_LATENCY"),
        .mem_width(DATA_WIDTH + DATA_WIDTH / 8),
        .mem_depth(RW_DATA_BUF_DEPTH),
        .INIT_FILE("no_init"),
        .simulation_delay(SIM_DELAY)
    )wdata_ext_fifo_mem(
        .clk(clk),
        .wen_a(wdata_ext_fifo_mem_wen),
        .addr_a(wdata_ext_fifo_mem_waddr),
        .din_a(wdata_ext_fifo_mem_din),
        .ren_b(wdata_ext_fifo_mem_ren),
        .addr_b(wdata_ext_fifo_mem_raddr[clogb2(RW_DATA_BUF_DEPTH-1):0]),
        .dout_b(wdata_ext_fifo_mem_dout)
    );
    
    /** 实时统计写突发长度 **/
    wire imdt_stat_wburst_len_fifo_wen;
	wire imdt_stat_wburst_len_fifo_full_n_w;
    wire[clogb2(SDRAM_COL_N-1):0] imdt_stat_wburst_len_fifo_din;
	wire[clogb2(SDRAM_COL_N-1):0] imdt_stat_wburst_len_fifo_dout_w;
    
	assign imdt_stat_wburst_len_fifo_dout = 
		((EN_IMDT_STAT_WBURST_LEN == "true") & (BURST_LEN == -1)) ? 
			(16'h0000 | imdt_stat_wburst_len_fifo_dout_w):
			16'h0000;
	
	assign imdt_stat_wburst_len_fifo_full_n = 
		(EN_IMDT_STAT_WBURST_LEN == "false") | (BURST_LEN != -1) | 
		imdt_stat_wburst_len_fifo_full_n_w;
	
    assign imdt_stat_wburst_len_fifo_wen = 
		(EN_IMDT_STAT_WBURST_LEN == "true") & (BURST_LEN == -1) & 
        s_axis_wt_valid & s_axis_wt_ready & s_axis_wt_last;
    assign imdt_stat_wburst_len_fifo_din = wdata_ext_fifo_mem_waddr[clogb2(SDRAM_COL_N-1):0];
    
    fifo_based_on_regs #(
        .fwft_mode("true"),
		.low_latency_mode("false"),
        .fifo_depth((EXT_FIFO_ITEM_N > 4) ? 4:EXT_FIFO_ITEM_N), // 注意: 实时统计写突发长度fifo的深度最大为4!
        .fifo_data_width(clogb2(SDRAM_COL_N-1)+1),
        .almost_full_th(),
        .almost_empty_th(),
        .simulation_delay(SIM_DELAY)
    )imdt_stat_wburst_len_fifo(
        .clk(clk),
        .rst_n(rst_n),
        .fifo_wen(imdt_stat_wburst_len_fifo_wen),
        .fifo_din(imdt_stat_wburst_len_fifo_din),
		.fifo_full_n(imdt_stat_wburst_len_fifo_full_n_w),
        .fifo_ren(imdt_stat_wburst_len_fifo_ren),
        .fifo_dout(imdt_stat_wburst_len_fifo_dout_w),
		.fifo_empty_n()
    );
    
    /** 读数据广义fifo **/
	// 读数据广义fifo当前的存储项数
    reg[clogb2(EXT_FIFO_ITEM_N):0] rdata_ext_fifo_item_n;
    // 读数据广义fifo读端口
    wire rdata_ext_fifo_ren;
    reg rdata_ext_fifo_empty_n;
    // 读数据广义fifo写端口
    reg rdata_ext_fifo_full_n_r;
	// 读数据缓存MEM读端口
	wire rdata_ext_fifo_mem_ren;
	reg[clogb2(RW_DATA_BUF_DEPTH-1):0] rdata_ext_fifo_mem_raddr;
	wire[DATA_WIDTH:0] rdata_ext_fifo_mem_dout; // {last(1bit), data(DATA_WIDTH bit)}
	// 读数据缓存流水线
	wire s0_rd_last;
	wire s0_rd_valid;
	wire s0_rd_ready;
	wire[DATA_WIDTH-1:0] s1_rd_data;
	wire s1_rd_last;
	reg s1_rd_valid;
	wire s1_rd_ready;
	reg[DATA_WIDTH-1:0] s2_rd_data;
	reg s2_rd_last;
	reg s2_rd_valid;
	wire s2_rd_ready;
	// 读突发数据个数记录表
	reg[clogb2(SDRAM_COL_N-1):0] rburst_len_tb[0:RW_DATA_BUF_DEPTH/SDRAM_COL_N-1];
	wire[clogb2(SDRAM_COL_N-1):0] rburst_len_tb_dout;
	
	assign m_axis_rd_data = s2_rd_data;
	assign m_axis_rd_last = s2_rd_last;
	assign m_axis_rd_valid = s2_rd_valid;
	
    assign rdata_ext_fifo_full_n = rdata_ext_fifo_full_n_r;
    
    assign rdata_ext_fifo_ren = s0_rd_valid & s0_rd_ready & s0_rd_last;
	
    assign rdata_ext_fifo_mem_ren = s0_rd_valid & s0_rd_ready;
	
	assign s0_rd_last = 
		(BURST_LEN == 1) ? 1'b1:
		(BURST_LEN == 2) ? rdata_ext_fifo_mem_raddr[0]:
		(BURST_LEN == 4) ? (&rdata_ext_fifo_mem_raddr[1:0]):
		(BURST_LEN == 8) ? (&rdata_ext_fifo_mem_raddr[2:0]):
			(rdata_ext_fifo_mem_raddr[clogb2(SDRAM_COL_N-1):0] == rburst_len_tb_dout);
	assign s0_rd_valid = rdata_ext_fifo_empty_n;
	assign s0_rd_ready = (~s1_rd_valid) | s1_rd_ready;
	
	assign s1_rd_data = rdata_ext_fifo_mem_dout[DATA_WIDTH-1:0];
	assign s1_rd_last = rdata_ext_fifo_mem_dout[DATA_WIDTH];
	assign s1_rd_ready = (~s2_rd_valid) | s2_rd_ready;
	
	assign s2_rd_ready = m_axis_rd_ready;
	
	assign rburst_len_tb_dout = 
		(BURST_LEN == -1) ? 
			rburst_len_tb[rdata_ext_fifo_mem_raddr[clogb2(RW_DATA_BUF_DEPTH-1):clogb2(SDRAM_COL_N-1)+1]]:
			(BURST_LEN - 1);
    
    // 读数据广义fifo当前的存储项数
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rdata_ext_fifo_item_n <= 0;
        else if((rdata_ext_fifo_wen & rdata_ext_fifo_full_n) ^ (rdata_ext_fifo_ren & rdata_ext_fifo_empty_n))
            rdata_ext_fifo_item_n <= # SIM_DELAY 
				(rdata_ext_fifo_wen & rdata_ext_fifo_full_n) ? 
					(rdata_ext_fifo_item_n + 1):
					(rdata_ext_fifo_item_n - 1);
    end
    // 读数据广义fifo空标志
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rdata_ext_fifo_empty_n <= 1'b0;
        else if((rdata_ext_fifo_wen & rdata_ext_fifo_full_n) ^ (rdata_ext_fifo_ren & rdata_ext_fifo_empty_n))
            rdata_ext_fifo_empty_n <= # SIM_DELAY 
				(rdata_ext_fifo_wen & rdata_ext_fifo_full_n) | 
				(rdata_ext_fifo_item_n != 1);
    end
    // 读数据广义fifo满标志
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rdata_ext_fifo_full_n_r <= 1'b1;
        else if((rdata_ext_fifo_wen & rdata_ext_fifo_full_n) ^ (rdata_ext_fifo_ren & rdata_ext_fifo_empty_n))
            rdata_ext_fifo_full_n_r <= # SIM_DELAY 
				(rdata_ext_fifo_ren & rdata_ext_fifo_empty_n) | 
				(rdata_ext_fifo_item_n != (EXT_FIFO_ITEM_N - 1));
    end
    
    // 读数据广义fifo的MEM读地址
    generate
        if(BURST_LEN == -1)
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_raddr[clogb2(RW_DATA_BUF_DEPTH-1):clogb2(SDRAM_COL_N-1)+1] <= 0;
                else if(rdata_ext_fifo_ren)
                    rdata_ext_fifo_mem_raddr[clogb2(RW_DATA_BUF_DEPTH-1):clogb2(SDRAM_COL_N-1)+1] <= # SIM_DELAY 
						rdata_ext_fifo_mem_raddr[clogb2(RW_DATA_BUF_DEPTH-1):clogb2(SDRAM_COL_N-1)+1] + 1;
            end
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_raddr[clogb2(SDRAM_COL_N-1):0] <= 0;
                else if(rdata_ext_fifo_mem_ren)
                    rdata_ext_fifo_mem_raddr[clogb2(SDRAM_COL_N-1):0] <= # SIM_DELAY 
						rdata_ext_fifo_ren ? 0:(rdata_ext_fifo_mem_raddr[clogb2(SDRAM_COL_N-1):0] + 1);
            end
        end
        else
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_raddr <= 0;
                else if(rdata_ext_fifo_mem_ren)
                    rdata_ext_fifo_mem_raddr <= # SIM_DELAY rdata_ext_fifo_mem_raddr + 1;
            end
        end
    endgenerate
	
	// 读突发数据个数记录表
	genvar rburst_len_tb_i;
	generate
		for(rburst_len_tb_i = 0;rburst_len_tb_i < RW_DATA_BUF_DEPTH/SDRAM_COL_N;rburst_len_tb_i = rburst_len_tb_i + 1)
		begin:rburst_len_tb_blk
			always @(posedge clk)
			begin
				if((BURST_LEN == -1) & 
					rdata_ext_fifo_mem_wen & 
					(rdata_ext_fifo_mem_waddr[clogb2(RW_DATA_BUF_DEPTH-1):clogb2(SDRAM_COL_N-1)+1] == rburst_len_tb_i) & 
					rdata_ext_fifo_mem_din[DATA_WIDTH]
				)
					rburst_len_tb[rburst_len_tb_i] <= # SIM_DELAY rdata_ext_fifo_mem_waddr[clogb2(SDRAM_COL_N-1):0];
			end
		end
	endgenerate
	
	// 读数据缓存流水线第1级的valid信号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			s1_rd_valid <= 1'b0;
		else if(s0_rd_ready)
			s1_rd_valid <= # SIM_DELAY s0_rd_valid;
	end
	// 读数据缓存流水线第2级的valid信号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			s2_rd_valid <= 1'b0;
		else if(s1_rd_ready)
			s2_rd_valid <= # SIM_DELAY s1_rd_valid;
	end
	
	// 读数据缓存流水线第2级的data和last
	always @(posedge clk)
	begin
		if(s1_rd_valid & s1_rd_ready)
			{s2_rd_last, s2_rd_data} <= # SIM_DELAY {s1_rd_last, s1_rd_data};
	end
    
    // 简单双口RAM
    bram_simple_dual_port #(
        .style("LOW_LATENCY"),
        .mem_width(DATA_WIDTH + 1),
        .mem_depth(RW_DATA_BUF_DEPTH),
        .INIT_FILE("no_init"),
        .simulation_delay(SIM_DELAY)
    )rdata_ext_fifo_mem(
        .clk(clk),
        .wen_a(rdata_ext_fifo_mem_wen),
        .addr_a(rdata_ext_fifo_mem_waddr[clogb2(RW_DATA_BUF_DEPTH-1):0]),
        .din_a(rdata_ext_fifo_mem_din),
        .ren_b(rdata_ext_fifo_mem_ren),
        .addr_b(rdata_ext_fifo_mem_raddr),
        .dout_b(rdata_ext_fifo_mem_dout)
    );
    
endmodule
