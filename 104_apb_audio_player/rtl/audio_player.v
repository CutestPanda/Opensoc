`timescale 1ns / 1ps
/********************************************************************
本模块: 音频播放器

描述:
根据用户提供的音频基地址和长度, 从SPI-Flash读取音频数据, 
以指定的音频采样率产生12位DAC输出

注意：
无

协议:
AP CTRL
SPI MASTER

作者: 陈家耀
日期: 2024/08/06
********************************************************************/


module audio_player #(
	parameter integer max_flash_rd_data_buffered_n = 500, // 允许的flash读数据缓存字节数
	parameter real audio_clk_freq = 12 * 1000 * 1000, // 音频时钟频率(以Hz计)
	parameter init_audio_sample_rate = 3'd3, // 初始的音频采样率
	parameter integer audio_qtz_width = 8, // 音频量化位数(8 | 16)
	parameter real simulation_delay = 0 // 仿真延时
)(
	// AMBA总线时钟和复位
	input wire amba_clk,
	input wire amba_resetn,
	// 音频时钟和复位
	input wire audio_clk,
	input wire audio_resetn,
	
	// 运行时参数
	/*
	音频采样率:
		3'd0 8KHz
		3'd1 16KHz
		3'd2 22.05KHz
		3'd3 24KHz
		3'd4 32KHz
		3'd5 44.1KHz
		3'd6 47.25KHz
		3'd7 48KHz
	*/
	input wire[2:0] audio_sample_rate,
	
	// DMA请求
	input wire dma_req,
	input wire dma_abort,
	input wire[23:0] flash_rd_baseaddr, // 基地址
	input wire[23:0] flash_rd_bytes_n, // 待读取字节数(必须>=2)
	output wire dma_done,
	output wire dma_idle,
	
	// SPI主机接口(flash)
    output wire flash_spi_ss,
    output wire flash_spi_sck,
    output wire flash_spi_mosi,
    input wire flash_spi_miso,
	
	// 12位DAC输出
	output wire[11:0] dac_out,
	
	// SPI控制器发送fifo写溢出(指示)
	output wire spi_tx_fifo_wt_ovf,
	// SPI控制器接收fifo写溢出(指示)
	output wire spi_rx_fifo_wt_ovf
);
	
	/** spi-flash DMA **/
	// 取flash读数据(指示)
	wire on_flash_data_ren;
	// SPI控制器发送fifo写端口
    wire spi_tx_fifo_wen;
    wire spi_tx_fifo_full;
    wire[7:0] spi_tx_fifo_din;
    wire spi_tx_fifo_din_ss;
	
	flash_dma #(
		.max_flash_rd_data_buffered_n(max_flash_rd_data_buffered_n),
		.simulation_delay(simulation_delay)
	)flash_dma_u(
		.amba_clk(amba_clk),
		.amba_resetn(amba_resetn),
		.audio_clk(audio_clk),
		.audio_resetn(audio_resetn),
		
		.dma_req(dma_req),
		.dma_abort(dma_abort),
		.flash_rd_baseaddr(flash_rd_baseaddr),
		.flash_rd_bytes_n(flash_rd_bytes_n),
		.dma_done(dma_done),
		.dma_idle(dma_idle),
		
		.on_flash_data_ren(on_flash_data_ren),
		
		.spi_tx_fifo_wen(spi_tx_fifo_wen),
		.spi_tx_fifo_full(spi_tx_fifo_full),
		.spi_tx_fifo_din(spi_tx_fifo_din),
		.spi_tx_fifo_ss(spi_tx_fifo_din_ss),
		
		.spi_tx_fifo_wt_ovf(spi_tx_fifo_wt_ovf)
	);
	
	/** 音频DAC控制器 **/
	// 音频数据fifo读端口
    wire audio_fifo_ren;
    wire audio_fifo_empty;
    wire[audio_qtz_width-1:0] audio_fifo_dout;
	
	audio_dac_ctrler #(
		.audio_clk_freq(audio_clk_freq),
		.init_audio_sample_rate(init_audio_sample_rate),
		.audio_qtz_width(audio_qtz_width),
		.simulation_delay(simulation_delay)
	)audio_dac_ctrler_u(
		.amba_clk(amba_clk),
		.amba_resetn(amba_resetn),
		.audio_clk(audio_clk),
		.audio_resetn(audio_resetn),
		
		.audio_sample_rate(audio_sample_rate),
		
		.audio_fifo_ren(audio_fifo_ren),
		.audio_fifo_empty(audio_fifo_empty),
		.audio_fifo_dout(audio_fifo_dout),
		
		.on_flash_data_ren(on_flash_data_ren),
		
		.dac_out(dac_out)
	);
	
	/** 音频fifo写端口位宽变换 **/
	// 音频数据fifo写端口(上游)
	wire audio_fifo_wen_up;
	wire audio_fifo_wen_up_w;
	reg[4:0] audio_fifo_wen_suppress; // 音频数据fifo写使能(镇压标志)
	wire audio_fifo_full_up;
	wire[7:0] audio_fifo_din_up; // 小端格式
	// 音频数据fifo写端口(下游)
	wire audio_fifo_wen_down;
	wire audio_fifo_almost_full_down;
	wire[audio_qtz_width-1:0] audio_fifo_din_down;
	
	assign audio_fifo_wen_up_w = audio_fifo_wen_up & audio_fifo_wen_suppress[4];
	
	// 音频数据fifo写使能(镇压标志)
	always @(posedge amba_clk or negedge amba_resetn)
	begin
		if(~amba_resetn)
			audio_fifo_wen_suppress <= 5'b00001;
		else if(dma_abort)
			# simulation_delay audio_fifo_wen_suppress <= 5'b00001;
		else if(audio_fifo_wen_suppress[4] ? dma_done:audio_fifo_wen_up)
			# simulation_delay audio_fifo_wen_suppress <= 
				{audio_fifo_wen_suppress[3:0], audio_fifo_wen_suppress[4]};
	end
	
	generate
		if(audio_qtz_width == 16)
		begin
			audio_fifo_wt #(
				.simulation_delay(simulation_delay)
			)audio_fifo_wt_u(
				.amba_clk(amba_clk),
				.amba_resetn(amba_resetn),
				
				.on_dma_start(dma_req & dma_idle),
				
				.audio_fifo_wen_up(audio_fifo_wen_up_w),
				.audio_fifo_full_up(audio_fifo_full_up),
				.audio_fifo_din_up(audio_fifo_din_up),
				
				.audio_fifo_wen_down(audio_fifo_wen_down),
				.audio_fifo_almost_full_down(audio_fifo_almost_full_down),
				.audio_fifo_din_down(audio_fifo_din_down)
			);
		end
		else
		begin
			assign audio_fifo_wen_down = audio_fifo_wen_up_w;
			assign audio_fifo_full_up = audio_fifo_almost_full_down;
			assign audio_fifo_din_down = audio_fifo_din_up;
		end
	endgenerate
	
	/** 音频fifo **/
	async_fifo_with_ram #(
		.fwft_mode("false"),
		.ram_type("bram"),
		.depth((audio_qtz_width == 16) ? 512:1024),
		.data_width(audio_qtz_width),
		.simulation_delay(simulation_delay)
	)audio_fifo_u(
		.clk_wt(amba_clk),
		.rst_n_wt(amba_resetn),
		.clk_rd(audio_clk),
		.rst_n_rd(audio_resetn),
		
		.fifo_wen(audio_fifo_wen_down),
		// 异步fifo没有almost_full信号, 用full信号也可以, 因为音频fifo的full仅用于写溢出指示
		.fifo_full(audio_fifo_almost_full_down),
		.fifo_din(audio_fifo_din_down),
		
		.fifo_ren(audio_fifo_ren),
		.fifo_empty(audio_fifo_empty),
		.fifo_dout(audio_fifo_dout)
	);
	
	/** SPI控制器发送fifo **/
	// SPI控制器发送fifo读端口
    wire spi_tx_fifo_ren;
    wire spi_tx_fifo_empty;
    wire[7:0] spi_tx_fifo_dout;
    wire spi_tx_fifo_dout_ss;
	
	ram_fifo_wrapper #(
		.fwft_mode("false"),
		.ram_type("bram"),
		.en_bram_reg(),
		.fifo_depth(1024),
		.fifo_data_width(9),
		.full_assert_polarity("high"),
		.empty_assert_polarity("high"),
		.almost_full_assert_polarity("no"),
		.almost_empty_assert_polarity("no"),
		.en_data_cnt("false"),
		.almost_full_th(),
		.almost_empty_th(),
		.simulation_delay(simulation_delay)
	)spi_tx_fifo_u(
		.clk(amba_clk),
		.rst_n(amba_resetn),
		
		.fifo_wen(spi_tx_fifo_wen),
		.fifo_din({spi_tx_fifo_din, spi_tx_fifo_din_ss}),
		.fifo_full(spi_tx_fifo_full),
		
		.fifo_ren(spi_tx_fifo_ren),
		.fifo_dout({spi_tx_fifo_dout, spi_tx_fifo_dout_ss}),
		.fifo_empty(spi_tx_fifo_empty)
	);
	
	/** 标准SPI控制器 **/
	std_spi_tx_rx #(
		.spi_slave_n(1),
		.spi_sck_div_n(2),
		.spi_cpol(1),
		.spi_cpha(1),
		.tx_user_data_width(0),
		.tx_user_default_v(),
		.simulation_delay(simulation_delay)
	)std_spi_tx_rx_u(
		.spi_clk(amba_clk),
		.spi_resetn(amba_resetn),
		.amba_clk(amba_clk),
		.amba_resetn(amba_resetn),
		
		.rx_tx_sel(0),
		.rx_tx_dire(2'b11),
		
		.tx_fifo_ren(spi_tx_fifo_ren),
		.tx_fifo_empty(spi_tx_fifo_empty),
		.tx_fifo_dout(spi_tx_fifo_dout),
		.tx_fifo_dout_ss(spi_tx_fifo_dout_ss),
		.tx_fifo_dout_user(),
		
		.rx_fifo_wen(audio_fifo_wen_up),
		.rx_fifo_full(audio_fifo_full_up),
		.rx_fifo_din(audio_fifo_din_up),
		
		.rx_tx_start(),
		.rx_tx_done(),
		.rx_tx_idle(),
		.rx_err(spi_rx_fifo_wt_ovf),
		
		.spi_ss(flash_spi_ss),
		.spi_sck(flash_spi_sck),
		.spi_mosi(flash_spi_mosi),
		.spi_miso(flash_spi_miso),
		.spi_user()
	);
	
endmodule
