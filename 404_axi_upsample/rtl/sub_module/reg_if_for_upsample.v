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
本模块: 最大池化单元的寄存器配置接口

描述:
寄存器->
    偏移量  |    含义                        |   读写特性    |        备注
    0x00    0:启动DMA的读通道                      WO        写该寄存器且该位为1'b1时执行启动
	        1:启动DMA的写通道                      WO        写该寄存器且该位为1'b1时执行启动
			8:DMA读通道空闲标志                    RO
			9:DMA写通道空闲标志                    RO
	0x04    31~0:输入特征图缓存区基地址            RW
	0x08    31~0:输入特征图缓存区长度 - 1          RW        以字节计
	0x0C    31~0:输出特征图缓存区基地址            RW
	0x10    31~0:输出特征图缓存区长度 - 1          RW        以字节计
	0x14    0:全局中断使能                         RW
			8:DMA读完成中断使能                    RW
	        9:DMA写完成中断使能                    RW
	0x18    0:全局中断标志                         WC
			8:DMA读完成中断标志                    RO
	        9:DMA写完成中断标志                    RO
	0x1C    15~0:特征图通道数 - 1                  RW
			31~16:特征图宽度 - 1                   RW
	0x20    15~0:特征图高度 - 1                    RW

注意：
无

协议:
AXI-Lite SLAVE
BLK CTRL

作者: 陈家耀
日期: 2024/11/28
********************************************************************/


module reg_if_for_upsample #(
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
	
	// 寄存器配置接口(AXI-Lite从机)
    // 读地址通道
    input wire[31:0] s_axi_lite_araddr,
	input wire[2:0] s_axi_lite_arprot, // ignored
    input wire s_axi_lite_arvalid,
    output wire s_axi_lite_arready,
    // 写地址通道
    input wire[31:0] s_axi_lite_awaddr,
	input wire[2:0] s_axi_lite_awprot, // ignored
    input wire s_axi_lite_awvalid,
    output wire s_axi_lite_awready,
    // 写响应通道
    output wire[1:0] s_axi_lite_bresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_bvalid,
    input wire s_axi_lite_bready,
    // 读数据通道
    output wire[31:0] s_axi_lite_rdata,
    output wire[1:0] s_axi_lite_rresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_rvalid,
    input wire s_axi_lite_rready,
    // 写数据通道
    input wire[31:0] s_axi_lite_wdata,
	input wire[3:0] s_axi_lite_wstrb,
    input wire s_axi_lite_wvalid,
    output wire s_axi_lite_wready,
	
	// DMA读通道控制
	output wire dma_mm2s_start,
	input wire dma_mm2s_idle,
	input wire dma_mm2s_done,
	// DMA写通道控制
	output wire dma_s2mm_start,
	input wire dma_s2mm_idle,
	input wire dma_s2mm_done,
	
	// 运行时参数
	output wire[31:0] in_ft_map_buf_baseaddr, // 输入特征图缓存区基地址
	output wire[31:0] in_ft_map_buf_len, // 输入特征图缓存区长度 - 1(以字节计)
	output wire[31:0] out_ft_map_buf_baseaddr, // 输出特征图缓存区基地址
	output wire[31:0] out_ft_map_buf_len, // 输出特征图缓存区长度 - 1(以字节计)
	output wire[15:0] feature_map_chn_n, // 特征图通道数 - 1
	output wire[15:0] feature_map_w, // 特征图宽度 - 1
	output wire[15:0] feature_map_h, // 特征图高度 - 1
	
	// 中断信号
	output wire itr
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
	
	/** 内部配置 **/
	localparam integer REGS_N = 9; // 寄存器总数
	
	/** 常量 **/
	// 寄存器配置状态独热码编号
	localparam integer REG_CFG_STS_ADDR = 0; // 状态:地址阶段
	localparam integer REG_CFG_STS_RW_REG = 1; // 状态:读/写寄存器
	localparam integer REG_CFG_STS_RW_RESP = 2; // 状态:读/写响应
	
	/** 寄存器配置控制 **/
	reg[2:0] reg_cfg_sts; // 寄存器配置状态
	wire[1:0] rw_grant; // 读写许可({写许可, 读许可})
	reg[1:0] addr_ready; // 地址通道的ready信号({aw_ready, ar_ready})
	reg is_write; // 是否写寄存器
	reg[clogb2(REGS_N-1):0] ofs_addr; // 读写寄存器的偏移地址
	reg wready; // 写数据通道的ready信号
	reg bvalid; // 写响应通道的valid信号
	reg rvalid; // 读数据通道的valid信号
	wire regs_en; // 寄存器访问使能
	wire[3:0] regs_wen; // 寄存器写使能
	wire[clogb2(REGS_N-1):0] regs_addr; // 寄存器访问地址
	wire[31:0] regs_din; // 寄存器写数据
	wire[31:0] regs_dout; // 寄存器读数据
	
	assign {s_axi_lite_awready, s_axi_lite_arready} = addr_ready;
	assign s_axi_lite_bresp = 2'b00;
	assign s_axi_lite_bvalid = bvalid;
	assign s_axi_lite_rdata = regs_dout;
	assign s_axi_lite_rresp = 2'b00;
	assign s_axi_lite_rvalid = rvalid;
	assign s_axi_lite_wready = wready;
	
	assign rw_grant = {s_axi_lite_awvalid, (~s_axi_lite_awvalid) & s_axi_lite_arvalid}; // 写优先
	
	assign regs_en = reg_cfg_sts[REG_CFG_STS_RW_REG] & ((~is_write) | s_axi_lite_wvalid);
	assign regs_wen = {4{is_write}} & s_axi_lite_wstrb;
	assign regs_addr = ofs_addr;
	assign regs_din = s_axi_lite_wdata;
	
	// 寄存器配置状态
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			reg_cfg_sts <= 3'b001;
		else if((reg_cfg_sts[REG_CFG_STS_ADDR] & (s_axi_lite_awvalid | s_axi_lite_arvalid)) | 
			(reg_cfg_sts[REG_CFG_STS_RW_REG] & ((~is_write) | s_axi_lite_wvalid)) | 
			(reg_cfg_sts[REG_CFG_STS_RW_RESP] & (is_write ? s_axi_lite_bready:s_axi_lite_rready)))
			reg_cfg_sts <= # simulation_delay {reg_cfg_sts[1:0], reg_cfg_sts[2]};
	end
	
	// 地址通道的ready信号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			addr_ready <= 2'b00;
		else
			addr_ready <= # simulation_delay {2{reg_cfg_sts[REG_CFG_STS_ADDR]}} & rw_grant;
	end
	
	// 是否写寄存器
	always @(posedge clk)
	begin
		if(reg_cfg_sts[REG_CFG_STS_ADDR] & (s_axi_lite_awvalid | s_axi_lite_arvalid))
			is_write <= # simulation_delay s_axi_lite_awvalid;
	end
	
	// 读写寄存器的偏移地址
	always @(posedge clk)
	begin
		if(reg_cfg_sts[REG_CFG_STS_ADDR] & (s_axi_lite_awvalid | s_axi_lite_arvalid))
			ofs_addr <= # simulation_delay s_axi_lite_awvalid ? 
				s_axi_lite_awaddr[2+clogb2(REGS_N-1):2]:s_axi_lite_araddr[2+clogb2(REGS_N-1):2];
	end
	
	// 写数据通道的ready信号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wready <= 1'b0;
		else
			wready <= # simulation_delay wready ? 
				(~s_axi_lite_wvalid):(reg_cfg_sts[REG_CFG_STS_ADDR] & s_axi_lite_awvalid);
	end
	
	// 写响应通道的valid信号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			bvalid <= 1'b0;
		else
			bvalid <= # simulation_delay bvalid ? 
				(~s_axi_lite_bready):(s_axi_lite_wvalid & s_axi_lite_wready);
	end
	
	// 读数据通道的valid信号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rvalid <= 1'b0;
		else
			rvalid <= # simulation_delay rvalid ? 
				(~s_axi_lite_rready):(reg_cfg_sts[REG_CFG_STS_RW_REG] & (~is_write));
	end
	
	/** 中断控制 **/
	wire global_itr_req; // 全局中断请求
	wire global_itr_en; // 全局中断使能
	wire global_itr_flag; // 全局中断标志
	wire[1:0] itr_en_vec; // 中断使能向量({DMA写完成中断使能, DMA读完成中断使能})
	wire[1:0] itr_req_vec; // 中断请求向量({DMA写完成中断请求, DMA读完成中断请求})
	
	assign global_itr_req = (|(itr_req_vec & itr_en_vec)) & global_itr_en & (~global_itr_flag);
	assign itr_req_vec = {dma_s2mm_done, dma_mm2s_done};
	
	// 中断发生器
    itr_generator #(
        .pulse_w(10),
        .simulation_delay(simulation_delay)
    )itr_generator_u(
        .clk(clk),
        .rst_n(rst_n),
        
        .itr_org(global_itr_req),
        
        .itr(itr)
    );
	
	/** 寄存器区 **/
	// 寄存器区读数据
	wire[31:0] regs_region_rd_out_nxt;
	reg[31:0] regs_region_rd_out;
	// 0x00
	reg dma_mm2s_start_reg; // 启动DMA的读通道
	reg dma_s2mm_start_reg; // 启动DMA的写通道
	reg dma_mm2s_idle_reg; // DMA读通道空闲标志
	reg dma_s2mm_idle_reg; // DMA写通道空闲标志
	// 0x04
	reg[31:0] in_ft_map_buf_baseaddr_regs; // 输入特征图缓存区基地址
	// 0x08
	reg[31:0] in_ft_map_buf_len_regs; // 输入特征图缓存区长度 - 1(以字节计)
	// 0x0C
	reg[31:0] out_ft_map_buf_baseaddr_regs; // 输出特征图缓存区基地址
	// 0x10
	reg[31:0] out_ft_map_buf_len_regs; // 输出特征图缓存区长度 - 1(以字节计)
	// 0x14
	reg global_itr_en_reg; // 全局中断使能
	reg dma_mm2s_done_itr_en_reg; // DMA读完成中断使能
	reg dma_s2mm_done_itr_en_reg; // DMA写完成中断使能
	// 0x18
	reg global_itr_flag_reg; // 全局中断标志
	reg dma_mm2s_done_itr_flag_reg; // DMA读完成中断标志
	reg dma_s2mm_done_itr_flag_reg; // DMA写完成中断标志
	// 0x1C
	reg[15:0] feature_map_chn_n_regs; // 特征图通道数 - 1
	reg[15:0] feature_map_w_regs; // 特征图宽度 - 1
	// 0x20
	reg[15:0] feature_map_h_regs; // 特征图高度 - 1
	
	assign dma_mm2s_start = dma_mm2s_start_reg;
	assign dma_s2mm_start = dma_s2mm_start_reg;
	
	assign in_ft_map_buf_baseaddr = in_ft_map_buf_baseaddr_regs;
	assign in_ft_map_buf_len = in_ft_map_buf_len_regs;
	assign out_ft_map_buf_baseaddr = out_ft_map_buf_baseaddr_regs;
	assign out_ft_map_buf_len = out_ft_map_buf_len_regs;
	assign feature_map_chn_n = feature_map_chn_n_regs;
	assign feature_map_w = feature_map_w_regs;
	assign feature_map_h = feature_map_h_regs;
	
	assign regs_dout = regs_region_rd_out;
	
	assign global_itr_en = global_itr_en_reg;
	assign global_itr_flag = global_itr_flag_reg;
	assign itr_en_vec = {dma_s2mm_done_itr_en_reg, dma_mm2s_done_itr_en_reg};
	
	assign regs_region_rd_out_nxt = 
		({32{regs_addr == 0}} & {
			8'dx, 
			8'dx, 
			6'dx, dma_s2mm_idle_reg, dma_mm2s_idle_reg, 
			8'dx
		}) | 
		({32{regs_addr == 1}} & {
			in_ft_map_buf_baseaddr_regs
		}) | 
		({32{regs_addr == 2}} & {
			in_ft_map_buf_len_regs
		}) | 
		({32{regs_addr == 3}} & {
			out_ft_map_buf_baseaddr_regs
		}) | 
		({32{regs_addr == 4}} & {
			out_ft_map_buf_len_regs
		}) | 
		({32{regs_addr == 5}} & {
			8'dx, 
			8'dx, 
			6'dx, dma_s2mm_done_itr_en_reg, dma_mm2s_done_itr_en_reg, 
			7'dx, global_itr_en_reg
		}) | 
		({32{regs_addr == 6}} & {
			8'dx, 
			8'dx, 
			6'dx, dma_s2mm_done_itr_flag_reg, dma_mm2s_done_itr_flag_reg, 
			7'dx, global_itr_flag_reg
		}) | 
		({32{regs_addr == 7}} & {
			feature_map_w_regs, 
			feature_map_chn_n_regs
		}) | 
		({32{regs_addr == 8}} & {
			16'dx, 
			feature_map_h_regs
		});
	
	// 寄存器区读数据
	always @(posedge clk)
	begin
		if(regs_en & (~is_write))
			regs_region_rd_out <= # simulation_delay regs_region_rd_out_nxt;
	end
	
	// 启动DMA的读通道, 启动DMA的写通道
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			{dma_s2mm_start_reg, dma_mm2s_start_reg} <= 2'b00;
		else
			{dma_s2mm_start_reg, dma_mm2s_start_reg} <= # simulation_delay 
				{2{regs_en & regs_wen[0] & (regs_addr == 0)}} & regs_din[1:0];
	end
	// DMA读通道空闲标志, DMA写通道空闲标志
	always @(posedge clk)
	begin
		{dma_s2mm_idle_reg, dma_mm2s_idle_reg} <= # simulation_delay 
			{dma_s2mm_idle, dma_mm2s_idle};
	end
	
	// 输入特征图缓存区基地址
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 1))
			in_ft_map_buf_baseaddr_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 1))
			in_ft_map_buf_baseaddr_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 1))
			in_ft_map_buf_baseaddr_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 1))
			in_ft_map_buf_baseaddr_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// 输入特征图缓存区长度 - 1(以字节计)
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 2))
			in_ft_map_buf_len_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 2))
			in_ft_map_buf_len_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 2))
			in_ft_map_buf_len_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 2))
			in_ft_map_buf_len_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// 输出特征图缓存区基地址
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 3))
			out_ft_map_buf_baseaddr_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 3))
			out_ft_map_buf_baseaddr_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 3))
			out_ft_map_buf_baseaddr_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 3))
			out_ft_map_buf_baseaddr_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// 输出特征图缓存区长度 - 1(以字节计)
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 4))
			out_ft_map_buf_len_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 4))
			out_ft_map_buf_len_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 4))
			out_ft_map_buf_len_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 4))
			out_ft_map_buf_len_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// 全局中断使能
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			global_itr_en_reg <= 1'b0;
		else if(regs_en & regs_wen[0] & (regs_addr == 5))
			global_itr_en_reg <= # simulation_delay regs_din[0];
	end
	// DMA读完成中断使能, DMA写完成中断使能
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			{dma_s2mm_done_itr_en_reg, dma_mm2s_done_itr_en_reg} <= 2'b00;
		else if(regs_en & regs_wen[1] & (regs_addr == 5))
			{dma_s2mm_done_itr_en_reg, dma_mm2s_done_itr_en_reg} <= # simulation_delay 
				regs_din[9:8];
	end
	
	// 全局中断标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			global_itr_flag_reg <= 1'b0;
		else if((regs_en & regs_wen[0] & (regs_addr == 6)) | (~global_itr_flag_reg))
			global_itr_flag_reg <= # simulation_delay 
				(~(regs_en & regs_wen[0] & (regs_addr == 6))) & // 清零全局中断标志
				((|(itr_req_vec & itr_en_vec)) & global_itr_en);
	end
	// DMA读完成中断标志, DMA写完成中断标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			{dma_s2mm_done_itr_flag_reg, dma_mm2s_done_itr_flag_reg} <= 2'b00;
		else if(global_itr_req)
			{dma_s2mm_done_itr_flag_reg, dma_mm2s_done_itr_flag_reg} <= # simulation_delay 
				itr_req_vec & itr_en_vec;
	end
	
	// 特征图通道数 - 1
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 7))
			feature_map_chn_n_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 7))
			feature_map_chn_n_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	// 特征图宽度 - 1
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 7))
			feature_map_w_regs[7:0] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 7))
			feature_map_w_regs[15:8] <= # simulation_delay regs_din[31:24];
	end
	
	// 特征图高度 - 1
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 8))
			feature_map_h_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 8))
			feature_map_h_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	
endmodule
