`timescale 1ns / 1ps
/********************************************************************
本模块: 以太网MAC寄存器配置接口

描述:
寄存器->
    偏移量  |    含义                             |   读写特性    |        备注                         |    初值    |
	0x00    0:新建以太网发送描述符(请求)                 RW        取上升沿                                   0
	        1:释放以太网接收描述符(请求)                 RW        取上升沿                                   0
	0x04    8~0:AXI主机的数据位宽                        RO
	          9:是否在DMA的MM2S通道允许非对齐传输        RO
			 10:是否在DMA的S2MM通道允许非对齐传输        RO
			 11:是否启用MDIO控制器                       RO
			 12:是否启用中断                             RO
	0x08   31~0:以太网帧发送缓存区基址                   RW
	0x0C    7~0:以太网发送描述符缓存区长度 - 1           RW
	       15~8:以太网接收描述符缓存区长度 - 1           RW
	0x10   31~0:以太网帧接收缓存区基址                   RW
	0x14    9~0:MDIO时钟分频系数                         RW        分频数 = (分频系数 + 1) * 2
	0x18      0:是否接受广播帧                           RW                                                   0
	0x1C   31~0:单播过滤MAC[31:0]                        RW                                              32'hffff_ffff
	0x20   15~0:单播过滤MAC[47:32]                       RW                                                16'hffff
	0x24   31~0:组播过滤MAC#0[31:0]                      RW                                                   0
	0x28   15~0:组播过滤MAC#0[47:32]                     RW                                                   0
	0x2C   31~0:组播过滤MAC#1[31:0]                      RW                                                   0
	0x30   15~0:组播过滤MAC#1[47:32]                     RW                                                   0
	0x34   31~0:组播过滤MAC#2[31:0]                      RW                                                   0
	0x38   15~0:组播过滤MAC#2[47:32]                     RW                                                   0
	0x3C   31~0:组播过滤MAC#3[31:0]                      RW                                                   0
	0x40   15~0:组播过滤MAC#3[47:32]                     RW                                                   0
	0x44      0:是否MDIO读传输                           RW        写该寄存器时启动MDIO传输
	        5~1:MDIO传输PHY地址                          RW
		   10~6:MDIO传输寄存器地址                       RW
		  31~16:MDIO传输写数据                           RW
	0x48      0:MDIO控制器是否空闲                       RO
	      31~16:MDIO传输读数据                           RO
	0x4C      0:是否写存储器                             RW        以太网发送描述符缓存存储器端口#A
	        9~1:存储器访问地址                           RW        写该寄存器时访问存储器
		  31~16:存储器写数据                             RW
	0x50   15~0:读数据                                   RO
	0x54      0:是否写存储器                             RW        以太网接收描述符缓存存储器端口#A
	        9~1:存储器访问地址                           RW        写该寄存器时访问存储器
		  31~16:存储器写数据                             RW
	0x58   15~0:读数据                                   RO
	0x5C      0:全局中断使能                             RW                                                   0
	          8:DMA MM2S通道中断使能                     RW                                                   0
			  9:DMA S2MM通道中断使能                     RW                                                   0
	0x60      0:DMA MM2S通道中断等待                    RW1C                                                  0
	          1:DMA S2MM通道中断等待                    RW1C                                                  0

注意：
无

协议:
APB MASTER
BLK CTRL
MEM MASTER

作者: 陈家耀
日期: 2025/04/28
********************************************************************/


module eth_mac_regs_if #(
	parameter EN_ITR = "true", // 是否启用中断
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // APB从机时钟和复位
	input wire pclk,
	input wire presetn,
	
	// APB从机接口
	input wire[31:0] paddr,
    input wire psel,
    input wire penable,
    input wire pwrite,
    input wire[31:0] pwdata,
    output wire pready_out, // const -> 1'b1
    output wire[31:0] prdata_out,
    output wire pslverr_out, // const -> 1'b0
	
	// DMA命令完成请求
	// 注意: 取上升沿!
	input wire mm2s_cmd_done,
	input wire s2mm_cmd_done,
	
	// 以太网描述符变更请求
	output wire new_eth_tx_dsc_created, // 新建以太网发送描述符(请求)
	output wire eth_rx_dsc_free, // 释放以太网接收描述符(请求)
	
	// 常量状态信息
	input wire[8:0] dma_const_sts_m_axi_data_width, // AXI主机的数据位宽
	input wire dma_const_sts_en_mm2s_unaligned_trans, // 是否在DMA的MM2S通道允许非对齐传输
	input wire dma_const_sts_en_s2mm_unaligned_trans, // 是否在DMA的S2MM通道允许非对齐传输
	input wire mdio_ctrler_present, // MDIO控制器存在(标志)
	
	// 运行时参数
	output wire[31:0] eth_tx_buf_baseaddr, // 以太网帧发送缓存区基址
	output wire[7:0] eth_tx_dsc_buf_len, // 以太网发送描述符缓存区长度 - 1
	output wire[31:0] eth_rx_buf_baseaddr, // 以太网帧接收缓存区基址
	output wire[7:0] eth_rx_dsc_buf_len, // 以太网接收描述符缓存区长度 - 1
	output wire broadcast_accept, // 是否接受广播帧
	output wire[47:0] unicast_filter_mac, // 单播过滤MAC
	output wire[47:0] multicast_filter_mac_0, // 组播过滤MAC#0
	output wire[47:0] multicast_filter_mac_1, // 组播过滤MAC#1
	output wire[47:0] multicast_filter_mac_2, // 组播过滤MAC#2
	output wire[47:0] multicast_filter_mac_3, // 组播过滤MAC#3
	output wire[9:0] mdc_div_rate, // MDIO时钟分频系数(分频数 = (分频系数 + 1) * 2)
	
	// MDIO控制器块级控制
	output wire mdio_access_start,
	output wire mdio_access_is_rd, // 是否读寄存器
	output wire[9:0] mdio_access_addr, // 访问地址({寄存器地址(5位), PHY地址(5位)})
	output wire[15:0] mdio_access_wdata, // 写数据
	input wire mdio_access_idle,
	input wire[15:0] mdio_access_rdata, // 读数据
	input wire mdio_access_done,
	
	// 以太网发送描述符缓存存储器端口#A
	output wire eth_tx_dsc_mem_ena,
	output wire eth_tx_dsc_mem_wea,
	output wire[8:0] eth_tx_dsc_mem_addra,
	output wire[15:0] eth_tx_dsc_mem_dina,
	input wire[15:0] eth_tx_dsc_mem_douta,
	
	// 以太网接收描述符缓存存储器端口#A
	output wire eth_rx_dsc_mem_ena,
	output wire eth_rx_dsc_mem_wea,
	output wire[8:0] eth_rx_dsc_mem_addra,
	output wire[15:0] eth_rx_dsc_mem_dina,
	input wire[15:0] eth_rx_dsc_mem_douta,
	
	// 中断请求
	output wire dma_mm2s_cmd_done_itr,
	output wire dma_s2mm_cmd_done_itr
);
	
	// APB读寄存器输出
	reg[31:0] prdata_out_r;
	// 以太网描述符变更请求
	reg new_eth_tx_dsc_created_r; // 新建以太网发送描述符(请求)
	reg eth_rx_dsc_free_r; // 释放以太网接收描述符(请求)
	// 常量状态信息
	wire en_itr_mecns; // 是否启用中断
	// 运行时参数
	reg[31:0] eth_tx_buf_baseaddr_r; // 以太网帧发送缓存区基址
	reg[7:0] eth_tx_dsc_buf_len_r; // 以太网发送描述符缓存区长度 - 1
	reg[31:0] eth_rx_buf_baseaddr_r; // 以太网帧接收缓存区基址
	reg[7:0] eth_rx_dsc_buf_len_r; // 以太网接收描述符缓存区长度 - 1
	reg broadcast_accept_r; // 是否接受广播帧
	reg[47:0] unicast_filter_mac_r; // 单播过滤MAC
	reg[47:0] multicast_filter_mac_0_r; // 组播过滤MAC#0
	reg[47:0] multicast_filter_mac_1_r; // 组播过滤MAC#1
	reg[47:0] multicast_filter_mac_2_r; // 组播过滤MAC#2
	reg[47:0] multicast_filter_mac_3_r; // 组播过滤MAC#3
	reg[9:0] mdc_div_rate_r; // MDIO时钟分频系数
	// MDIO控制器块级控制
	reg mdio_access_start_r;
	reg mdio_access_is_rd_r; // 是否读寄存器
	reg[9:0] mdio_access_addr_r; // 访问地址({寄存器地址(5位), PHY地址(5位)})
	reg[15:0] mdio_access_wdata_r; // 写数据
	// 以太网发送描述符缓存存储器端口#A
	reg eth_tx_dsc_mem_ena_r;
	reg eth_tx_dsc_mem_wea_r;
	reg[8:0] eth_tx_dsc_mem_addra_r;
	reg[15:0] eth_tx_dsc_mem_dina_r;
	// 以太网接收描述符缓存存储器端口#A
	reg eth_rx_dsc_mem_ena_r;
	reg eth_rx_dsc_mem_wea_r;
	reg[8:0] eth_rx_dsc_mem_addra_r;
	reg[15:0] eth_rx_dsc_mem_dina_r;
	// 中断控制
	reg global_itr_en; // 全局中断使能
	reg dma_mm2s_cmd_done_itr_en; // DMA MM2S通道中断使能
	reg dma_s2mm_cmd_done_itr_en; // DMA S2MM通道中断使能
	reg dma_mm2s_cmd_done_itr_pending; // DMA MM2S通道中断等待
	reg dma_s2mm_cmd_done_itr_pending; // DMA S2MM通道中断等待
	reg mm2s_cmd_done_d1;
	reg s2mm_cmd_done_d1;
	wire on_mm2s_cmd_done;
	wire on_s2mm_cmd_done;
	reg dma_mm2s_cmd_done_itr_r; // DMA MM2S通道中断请求
	reg dma_s2mm_cmd_done_itr_r; // DMA S2MM通道中断请求
	
	assign pready_out = 1'b1;
	assign prdata_out = prdata_out_r;
	assign pslverr_out = 1'b0;
	
	assign dma_mm2s_cmd_done_itr = dma_mm2s_cmd_done_itr_r;
	assign dma_s2mm_cmd_done_itr = dma_s2mm_cmd_done_itr_r;
	
	assign new_eth_tx_dsc_created = new_eth_tx_dsc_created_r;
	assign eth_rx_dsc_free = eth_rx_dsc_free_r;
	
	assign eth_tx_buf_baseaddr = eth_tx_buf_baseaddr_r;
	assign eth_tx_dsc_buf_len = eth_tx_dsc_buf_len_r;
	assign eth_rx_buf_baseaddr = eth_rx_buf_baseaddr_r;
	assign eth_rx_dsc_buf_len = eth_rx_dsc_buf_len_r;
	assign broadcast_accept = broadcast_accept_r;
	assign unicast_filter_mac = unicast_filter_mac_r;
	assign multicast_filter_mac_0 = multicast_filter_mac_0_r;
	assign multicast_filter_mac_1 = multicast_filter_mac_1_r;
	assign multicast_filter_mac_2 = multicast_filter_mac_2_r;
	assign multicast_filter_mac_3 = multicast_filter_mac_3_r;
	assign mdc_div_rate = mdc_div_rate_r;
	
	assign mdio_access_start = mdio_access_start_r;
	assign mdio_access_is_rd = mdio_access_is_rd_r;
	assign mdio_access_addr = mdio_access_addr_r;
	assign mdio_access_wdata = mdio_access_wdata_r;
	
	assign eth_tx_dsc_mem_ena = eth_tx_dsc_mem_ena_r;
	assign eth_tx_dsc_mem_wea = eth_tx_dsc_mem_wea_r;
	assign eth_tx_dsc_mem_addra = eth_tx_dsc_mem_addra_r;
	assign eth_tx_dsc_mem_dina = eth_tx_dsc_mem_dina_r;
	
	assign eth_rx_dsc_mem_ena = eth_rx_dsc_mem_ena_r;
	assign eth_rx_dsc_mem_wea = eth_rx_dsc_mem_wea_r;
	assign eth_rx_dsc_mem_addra = eth_rx_dsc_mem_addra_r;
	assign eth_rx_dsc_mem_dina = eth_rx_dsc_mem_dina_r;
	
	assign on_mm2s_cmd_done = mm2s_cmd_done & (~mm2s_cmd_done_d1);
	assign on_s2mm_cmd_done = s2mm_cmd_done & (~s2mm_cmd_done_d1);
	
	assign en_itr_mecns = EN_ITR == "true";
	
	// APB读寄存器输出
	always @(posedge pclk)
	begin
		if(psel & (~pwrite))
		begin
			case(paddr[6:2])
				5'd0: prdata_out_r <= # SIM_DELAY {30'd0, eth_rx_dsc_free_r, new_eth_tx_dsc_created_r};
				5'd1: prdata_out_r <= # SIM_DELAY {
					19'd0, 
					en_itr_mecns, mdio_ctrler_present, 
					dma_const_sts_en_s2mm_unaligned_trans, dma_const_sts_en_mm2s_unaligned_trans, 
					dma_const_sts_m_axi_data_width
				};
				5'd2: prdata_out_r <= # SIM_DELAY eth_tx_buf_baseaddr_r;
				5'd3: prdata_out_r <= # SIM_DELAY {16'd0, eth_rx_dsc_buf_len_r, eth_tx_dsc_buf_len_r};
				5'd4: prdata_out_r <= # SIM_DELAY eth_rx_buf_baseaddr_r;
				5'd5: prdata_out_r <= # SIM_DELAY {22'd0, mdc_div_rate_r};
				5'd6: prdata_out_r <= # SIM_DELAY {31'd0, broadcast_accept_r};
				5'd7: prdata_out_r <= # SIM_DELAY unicast_filter_mac_r[31:0];
				5'd8: prdata_out_r <= # SIM_DELAY {16'd0, unicast_filter_mac_r[47:32]};
				5'd9: prdata_out_r <= # SIM_DELAY multicast_filter_mac_0_r[31:0];
				5'd10: prdata_out_r <= # SIM_DELAY {16'd0, multicast_filter_mac_0_r[47:32]};
				5'd11: prdata_out_r <= # SIM_DELAY multicast_filter_mac_1_r[31:0];
				5'd12: prdata_out_r <= # SIM_DELAY {16'd0, multicast_filter_mac_1_r[47:32]};
				5'd13: prdata_out_r <= # SIM_DELAY multicast_filter_mac_2_r[31:0];
				5'd14: prdata_out_r <= # SIM_DELAY {16'd0, multicast_filter_mac_2_r[47:32]};
				5'd15: prdata_out_r <= # SIM_DELAY multicast_filter_mac_3_r[31:0];
				5'd16: prdata_out_r <= # SIM_DELAY {16'd0, multicast_filter_mac_3_r[47:32]};
				5'd17: prdata_out_r <= # SIM_DELAY {mdio_access_wdata_r, 5'd0, mdio_access_addr_r, mdio_access_is_rd_r};
				5'd18: prdata_out_r <= # SIM_DELAY {mdio_access_rdata, 15'd0, mdio_access_idle};
				5'd19: prdata_out_r <= # SIM_DELAY {eth_tx_dsc_mem_dina_r, 6'd0, eth_tx_dsc_mem_addra_r, eth_tx_dsc_mem_wea_r};
				5'd20: prdata_out_r <= # SIM_DELAY {16'd0, eth_tx_dsc_mem_douta};
				5'd21: prdata_out_r <= # SIM_DELAY {eth_rx_dsc_mem_dina_r, 6'd0, eth_rx_dsc_mem_addra_r, eth_rx_dsc_mem_wea_r};
				5'd22: prdata_out_r <= # SIM_DELAY {16'd0, eth_rx_dsc_mem_douta};
				5'd23: prdata_out_r <= # SIM_DELAY {16'd0, 6'd0, dma_s2mm_cmd_done_itr_en, dma_mm2s_cmd_done_itr_en, 7'd0, global_itr_en};
				5'd24: prdata_out_r <= # SIM_DELAY {30'd0, dma_s2mm_cmd_done_itr_pending, dma_mm2s_cmd_done_itr_pending};
				
				default: prdata_out_r <= # SIM_DELAY 32'h0000_0000;
			endcase
		end
	end
	
	// 新建以太网发送描述符(请求), 释放以太网接收描述符(请求)
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			{eth_rx_dsc_free_r, new_eth_tx_dsc_created_r} <= 2'b00;
		else if(psel & penable & pwrite & (paddr[6:2] == 5'd0))
			{eth_rx_dsc_free_r, new_eth_tx_dsc_created_r} <= # SIM_DELAY pwdata[1:0];
	end
	
	// 以太网帧发送缓存区基址
	always @(posedge pclk)
	begin
		if(psel & penable & pwrite & (paddr[6:2] == 5'd2))
			eth_tx_buf_baseaddr_r <= # SIM_DELAY pwdata[31:0];
	end
	
	// 以太网发送描述符缓存区长度 - 1, 以太网接收描述符缓存区长度 - 1
	always @(posedge pclk)
	begin
		if(psel & penable & pwrite & (paddr[6:2] == 5'd3))
			{eth_rx_dsc_buf_len_r, eth_tx_dsc_buf_len_r} <= # SIM_DELAY pwdata[15:0];
	end
	
	// 以太网帧接收缓存区基址
	always @(posedge pclk)
	begin
		if(psel & penable & pwrite & (paddr[6:2] == 5'd4))
			eth_rx_buf_baseaddr_r <= # SIM_DELAY pwdata[31:0];
	end
	
	// MDIO时钟分频系数
	always @(posedge pclk)
	begin
		if(psel & penable & pwrite & (paddr[6:2] == 5'd5))
			mdc_div_rate_r <= # SIM_DELAY pwdata[9:0];
	end
	
	// 是否接受广播帧
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			broadcast_accept_r <= 1'b0;
		else if(psel & penable & pwrite & (paddr[6:2] == 5'd6))
			broadcast_accept_r <= # SIM_DELAY pwdata[0];
	end
	
	// 单播过滤MAC
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			unicast_filter_mac_r[31:0] <= 32'hffff_ffff;
		else if(psel & penable & pwrite & (paddr[6:2] == 5'd7))
			unicast_filter_mac_r[31:0] <= # SIM_DELAY pwdata[31:0];
	end
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			unicast_filter_mac_r[47:32] <= 16'hffff;
		else if(psel & penable & pwrite & (paddr[6:2] == 5'd8))
			unicast_filter_mac_r[47:32] <= # SIM_DELAY pwdata[15:0];
	end
	
	// 组播过滤MAC#0
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			multicast_filter_mac_0_r[31:0] <= 0;
		else if(psel & penable & pwrite & (paddr[6:2] == 5'd9))
			multicast_filter_mac_0_r[31:0] <= # SIM_DELAY pwdata[31:0];
	end
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			multicast_filter_mac_0_r[47:32] <= 0;
		else if(psel & penable & pwrite & (paddr[6:2] == 5'd10))
			multicast_filter_mac_0_r[47:32] <= # SIM_DELAY pwdata[15:0];
	end
	
	// 组播过滤MAC#1
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			multicast_filter_mac_1_r[31:0] <= 0;
		else if(psel & penable & pwrite & (paddr[6:2] == 5'd11))
			multicast_filter_mac_1_r[31:0] <= # SIM_DELAY pwdata[31:0];
	end
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			multicast_filter_mac_1_r[47:32] <= 0;
		else if(psel & penable & pwrite & (paddr[6:2] == 5'd12))
			multicast_filter_mac_1_r[47:32] <= # SIM_DELAY pwdata[15:0];
	end
	
	// 组播过滤MAC#2
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			multicast_filter_mac_2_r[31:0] <= 0;
		else if(psel & penable & pwrite & (paddr[6:2] == 5'd13))
			multicast_filter_mac_2_r[31:0] <= # SIM_DELAY pwdata[31:0];
	end
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			multicast_filter_mac_2_r[47:32] <= 0;
		else if(psel & penable & pwrite & (paddr[6:2] == 5'd14))
			multicast_filter_mac_2_r[47:32] <= # SIM_DELAY pwdata[15:0];
	end
	
	// 组播过滤MAC#2
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			multicast_filter_mac_3_r[31:0] <= 0;
		else if(psel & penable & pwrite & (paddr[6:2] == 5'd15))
			multicast_filter_mac_3_r[31:0] <= # SIM_DELAY pwdata[31:0];
	end
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			multicast_filter_mac_3_r[47:32] <= 0;
		else if(psel & penable & pwrite & (paddr[6:2] == 5'd16))
			multicast_filter_mac_3_r[47:32] <= # SIM_DELAY pwdata[15:0];
	end
	
	// MDIO传输(是否读寄存器, 访问地址, 写数据, 启动传输)
	always @(posedge pclk)
	begin
		if(psel & penable & pwrite & (paddr[6:2] == 5'd17))
			{mdio_access_wdata_r, mdio_access_addr_r, mdio_access_is_rd_r} <= # SIM_DELAY 
				{pwdata[31:16], pwdata[10:6], pwdata[5:1], pwdata[0]};
	end
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			mdio_access_start_r <= 1'b0;
		else
			mdio_access_start_r <= # SIM_DELAY psel & penable & pwrite & (paddr[6:2] == 5'd17);
	end
	
	// 以太网发送描述符缓存存储器端口#A
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			eth_tx_dsc_mem_ena_r <= 1'b0;
		else
			eth_tx_dsc_mem_ena_r <= # SIM_DELAY psel & penable & pwrite & (paddr[6:2] == 5'd19);
	end
	always @(posedge pclk)
	begin
		if(psel & penable & pwrite & (paddr[6:2] == 5'd19))
			{eth_tx_dsc_mem_dina_r, eth_tx_dsc_mem_addra_r, eth_tx_dsc_mem_wea_r} <= # SIM_DELAY 
				{pwdata[31:16], pwdata[9:1], pwdata[0]};
	end
	
	// 以太网接收描述符缓存存储器端口#A
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			eth_rx_dsc_mem_ena_r <= 1'b0;
		else
			eth_rx_dsc_mem_ena_r <= # SIM_DELAY psel & penable & pwrite & (paddr[6:2] == 5'd21);
	end
	always @(posedge pclk)
	begin
		if(psel & penable & pwrite & (paddr[6:2] == 5'd21))
			{eth_rx_dsc_mem_dina_r, eth_rx_dsc_mem_addra_r, eth_rx_dsc_mem_wea_r} <= # SIM_DELAY 
				{pwdata[31:16], pwdata[9:1], pwdata[0]};
	end
	
	// 全局中断使能, DMA MM2S通道中断使能, DMA S2MM通道中断使能
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			{dma_s2mm_cmd_done_itr_en, dma_mm2s_cmd_done_itr_en, global_itr_en} <= 3'b000;
		else if(psel & penable & pwrite & (paddr[6:2] == 5'd23))
			{dma_s2mm_cmd_done_itr_en, dma_mm2s_cmd_done_itr_en, global_itr_en} <= # SIM_DELAY 
				{pwdata[9], pwdata[8], pwdata[0]};
	end
	
	// DMA MM2S通道中断等待
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			dma_mm2s_cmd_done_itr_pending <= 1'b0;
		else if(on_mm2s_cmd_done | (psel & penable & pwrite & (paddr[6:2] == 5'd24) & pwdata[0]))
			dma_mm2s_cmd_done_itr_pending <= # SIM_DELAY 
				(~(psel & penable & pwrite & (paddr[6:2] == 5'd24) & pwdata[0])) & on_mm2s_cmd_done;
	end
	// DMA S2MM通道中断等待
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			dma_s2mm_cmd_done_itr_pending <= 1'b0;
		else if(on_s2mm_cmd_done | (psel & penable & pwrite & (paddr[6:2] == 5'd24) & pwdata[1]))
			dma_s2mm_cmd_done_itr_pending <= # SIM_DELAY 
				(~(psel & penable & pwrite & (paddr[6:2] == 5'd24) & pwdata[0])) & on_s2mm_cmd_done;
	end
	
	// 延迟1clk的DMA命令完成请求
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			{s2mm_cmd_done_d1, mm2s_cmd_done_d1} <= 2'b00;
		else
			{s2mm_cmd_done_d1, mm2s_cmd_done_d1} <= # SIM_DELAY {s2mm_cmd_done, mm2s_cmd_done};
	end
	
	// DMA MM2S通道中断请求, DMA S2MM通道中断请求
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			{dma_s2mm_cmd_done_itr_r, dma_mm2s_cmd_done_itr_r} <= 2'b00;
		else
			{dma_s2mm_cmd_done_itr_r, dma_mm2s_cmd_done_itr_r} <= # SIM_DELAY {
				global_itr_en & dma_s2mm_cmd_done_itr_en & (~dma_s2mm_cmd_done_itr_pending) & on_s2mm_cmd_done, 
				global_itr_en & dma_mm2s_cmd_done_itr_en & (~dma_mm2s_cmd_done_itr_pending) & on_mm2s_cmd_done
			};
	end
	
endmodule
