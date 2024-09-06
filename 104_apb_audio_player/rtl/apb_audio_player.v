`timescale 1ns / 1ps
/********************************************************************
本模块: 符合APB协议的音频播放器

描述: 
根据用户提供的音频基地址和长度, 从SPI-Flash读取音频数据, 
以指定的音频采样率产生12位DAC输出

寄存器->
    偏移量  |    含义                     |   读写特性    |               备注
    0x00    23~0:音频在flash中的基地址           W
	0x04    23~0:音频字节数                      W
	0x08     2~0:音频采样率                      W
	0x0C       0:flash-dma空闲                   R
			   1:flash-dma启动                   W           写该寄存器且该位为1时产生DMA请求
			   2:flash-dma中止                   W           写该寄存器且该位为1时产生DMA中止
	0x10       0:SPI控制器发送fifo写溢出        RWC
			   1:SPI控制器接收fifo写溢出        RWC

支持的采样率 ->
	编号    值
	3'd0   8KHz
	3'd1 11.025KHz
	3'd2 22.05KHz
	3'd3   24KHz
	3'd4   32KHz
	3'd5  44.1KHz
	3'd6 47.25KHz
	3'd7   48KHz

注意：
不支持中断
SPI-Flash型号为W25QXX

协议:
APB SLAVE
SPI MASTER

作者: 陈家耀
日期: 2024/08/08
********************************************************************/


module apb_audio_player #(
	parameter real audio_clk_freq = 12 * 1000 * 1000, // 音频时钟频率(以Hz计)
	parameter init_audio_sample_rate = 3'd3, // 初始的音频采样率
	parameter integer audio_qtz_width = 8, // 音频量化位数(8 | 16)
	parameter audio_sample_rate_fixed = "false", // 固定的音频采样率
	parameter real simulation_delay = 0 // 仿真延时
)(
	// AMBA总线时钟和复位
	input wire amba_clk,
	input wire amba_resetn,
	// 音频时钟和复位
	input wire audio_clk,
	input wire audio_resetn,
	
	// APB从机接口
    input wire[31:0] paddr,
    input wire psel,
    input wire penable,
    input wire pwrite,
    input wire[31:0] pwdata,
    output wire pready_out, // const -> 1'b1
    output wire[31:0] prdata_out,
    output wire pslverr_out, // const -> 1'b0
	
	// SPI主机接口(flash)
    output wire audio_flash_spi_ss,
    output wire audio_flash_spi_sck,
    output wire audio_flash_spi_mosi,
    input wire audio_flash_spi_miso,
	
	// 12位DAC输出
	output wire[11:0] audio_dac_out
);
	
	/** 内部配置 **/
	localparam integer max_flash_rd_data_buffered_n = 500; // 允许的flash读数据缓存字节数
	
	/** APB写寄存器 **/
	/*
	跨时钟域:
		audio_sample_rate -> ...!
	*/
	reg[23:0] flash_rd_baseaddr; // 音频在flash中的基地址
	reg[23:0] flash_rd_bytes_n; // 音频字节数
	reg[2:0] audio_sample_rate; // 音频采样率
	reg dma_req; // flash-dma启动
	reg dma_abort; // flash-dma中止
	
	// 音频在flash中的基地址
	always @(posedge amba_clk)
	begin
		if(psel & pwrite & penable & (paddr[4:2] == 3'd0))
			# simulation_delay flash_rd_baseaddr <= pwdata[23:0];
	end
	
	// 音频字节数
	always @(posedge amba_clk)
	begin
		if(psel & pwrite & penable & (paddr[4:2] == 3'd1))
			# simulation_delay flash_rd_bytes_n <= pwdata[23:0];
	end
	
	// 音频采样率
	always @(posedge amba_clk or negedge amba_resetn)
	begin
		if(~amba_resetn)
			audio_sample_rate <= init_audio_sample_rate;
		else if(psel & pwrite & penable & (paddr[4:2] == 3'd2))
			# simulation_delay audio_sample_rate <= pwdata[2:0];
	end
	
	// flash-dma启动
	always @(posedge amba_clk or negedge amba_resetn)
	begin
		if(~amba_resetn)
			dma_req <= 1'b0;
		else
			# simulation_delay dma_req <= psel & pwrite & penable & (paddr[4:2] == 3'd3) & pwdata[1];
	end
	// flash-dma中止
	always @(posedge amba_clk or negedge amba_resetn)
	begin
		if(~amba_resetn)
			dma_abort <= 1'b0;
		else
			# simulation_delay dma_abort <= psel & pwrite & penable & (paddr[4:2] == 3'd3) & pwdata[2];
	end
	
	/** 错误标志 **/
	wire spi_tx_fifo_wt_ovf; // SPI控制器发送fifo写溢出(指示)
	wire spi_rx_fifo_wt_ovf; // SPI控制器接收fifo写溢出(指示)
	reg[1:0] err_flag_vec; // 错误标志向量
	
	// 错误标志向量
	always @(posedge amba_clk or negedge amba_resetn)
	begin
		if(~amba_resetn)
			err_flag_vec[0] <= 1'b0;
		else if(~err_flag_vec[0])
			# simulation_delay err_flag_vec[0] <= spi_tx_fifo_wt_ovf;
		else if(psel & pwrite & penable & (paddr[4:2] == 3'd4))
			# simulation_delay err_flag_vec[0] <= 1'b0;
	end
	always @(posedge amba_clk or negedge amba_resetn)
	begin
		if(~amba_resetn)
			err_flag_vec[1] <= 1'b0;
		else if(~err_flag_vec[1])
			# simulation_delay err_flag_vec[1] <= spi_rx_fifo_wt_ovf;
		else if(psel & pwrite & penable & (paddr[4:2] == 3'd4))
			# simulation_delay err_flag_vec[1] <= 1'b0;
	end
	
	/** APB读寄存器 **/
	wire dma_idle;
	reg[31:0] prdata_oregs; // APB读数据输出
	
	assign pready_out = 1'b1;
	assign prdata_out = prdata_oregs;
	assign pslverr_out = 1'b0;
	
	// APB读数据输出
	always @(posedge amba_clk)
	begin
		if(psel & (~pwrite))
		begin
			# simulation_delay;
			
			case(paddr[4:2])
				3'd3: prdata_oregs <= {31'dx, dma_idle};
				3'd4: prdata_oregs <= {30'dx, err_flag_vec};
				default: prdata_oregs <= 32'dx;
			endcase
		end
	end
	
	/** 音频播放器 **/
	audio_player #(
		.max_flash_rd_data_buffered_n(max_flash_rd_data_buffered_n),
		.audio_clk_freq(audio_clk_freq),
		.init_audio_sample_rate(init_audio_sample_rate),
		.audio_qtz_width(audio_qtz_width),
		.simulation_delay(simulation_delay)
	)audio_player_u(
		.amba_clk(amba_clk),
		.amba_resetn(amba_resetn),
		.audio_clk(audio_clk),
		.audio_resetn(audio_resetn),
		
		.audio_sample_rate((audio_sample_rate_fixed == "true") ? init_audio_sample_rate:audio_sample_rate),
		
		.dma_req(dma_req),
		.dma_abort(dma_abort),
		.flash_rd_baseaddr(flash_rd_baseaddr),
		.flash_rd_bytes_n(flash_rd_bytes_n),
		.dma_done(),
		.dma_idle(dma_idle),
		
		.flash_spi_ss(audio_flash_spi_ss),
		.flash_spi_sck(audio_flash_spi_sck),
		.flash_spi_mosi(audio_flash_spi_mosi),
		.flash_spi_miso(audio_flash_spi_miso),
		
		.dac_out(audio_dac_out),
		
		.spi_tx_fifo_wt_ovf(spi_tx_fifo_wt_ovf),
		.spi_rx_fifo_wt_ovf(spi_rx_fifo_wt_ovf)
	);
	
endmodule
