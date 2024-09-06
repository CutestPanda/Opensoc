`timescale 1ns / 1ps
/********************************************************************
本模块: spi-flash DMA

描述:
适用于W25QXX芯片
使用标准SPI
将flash读请求转换为spi控制器的命令

命令格式 ->
	8'h03
	基地址[23:16]
	基地址[15:8]
	基地址[7:0]
	读数据#0
	...
	读数据#N-1

注意：
无

协议:
AP CTRL
FIFO WRITE

作者: 陈家耀
日期: 2024/08/05
********************************************************************/

module flash_dma #(
	parameter integer max_flash_rd_data_buffered_n = 500, // 允许的flash读数据缓存字节数
	parameter real simulation_delay = 0 // 仿真延时
)(
	// AMBA总线时钟和复位
	input wire amba_clk,
	input wire amba_resetn,
	// 音频时钟和复位
	input wire audio_clk,
	input wire audio_resetn,
	
	// DMA请求
	input wire dma_req,
	input wire dma_abort,
	input wire[23:0] flash_rd_baseaddr, // 基地址
	input wire[23:0] flash_rd_bytes_n, // 待读取字节数(必须>=2)
	output wire dma_done,
	output wire dma_idle,
	
	// 取flash读数据(指示)
	input wire on_flash_data_ren,
	
	// SPI控制器发送fifo写端口
    output wire spi_tx_fifo_wen,
    input wire spi_tx_fifo_full,
    output wire[7:0] spi_tx_fifo_din,
    output wire spi_tx_fifo_ss,
	// SPI控制器发送fifo写溢出(指示)
	output wire spi_tx_fifo_wt_ovf
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
	
	/** flash读数据缓存控制 **/
	wire on_flash_data_wen; // 提交flash读命令(指示)
	wire on_flash_data_ren_sync; // 同步到AMBA总线时钟域的取flash读数据(指示)
	reg[clogb2(max_flash_rd_data_buffered_n):0] flash_rd_data_buffered_n; // 已缓存的flash读数据字节数
	reg flash_rd_data_buf_empty; // flash读数据缓存空(标志)
	reg flash_rd_data_buf_full; // flash读数据缓存满(标志)
	reg spi_tx_fifo_wt_ovf_reg; // SPI控制器发送fifo写溢出(指示)
	
	assign spi_tx_fifo_wt_ovf = spi_tx_fifo_wt_ovf_reg;
	
	// 已缓存的flash读数据字节数
	always @(posedge amba_clk or negedge amba_resetn)
	begin
		if(~amba_resetn)
			flash_rd_data_buffered_n <= 0;
		else if(dma_abort) // 清零
			# simulation_delay flash_rd_data_buffered_n <= 0;
		else if((on_flash_data_wen & (~flash_rd_data_buf_full)) ^ on_flash_data_ren_sync) // 更新
			# simulation_delay flash_rd_data_buffered_n <= 
				on_flash_data_ren_sync ? (flash_rd_data_buffered_n - 1):(flash_rd_data_buffered_n + 1);
	end
	// flash读数据缓存空(标志)
	always @(posedge amba_clk or negedge amba_resetn)
	begin
		if(~amba_resetn)
			flash_rd_data_buf_empty <= 1'b1;
		else if(dma_abort) // 复位
			# simulation_delay flash_rd_data_buf_empty <= 1'b1;
		else if((on_flash_data_wen & (~flash_rd_data_buf_full)) ^ on_flash_data_ren_sync) // 更新
			# simulation_delay flash_rd_data_buf_empty <= 
				on_flash_data_ren_sync ? (flash_rd_data_buffered_n == 1):1'b0;
	end
	// flash读数据缓存满(标志)
	always @(posedge amba_clk or negedge amba_resetn)
	begin
		if(~amba_resetn)
			flash_rd_data_buf_full <= 1'b0;
		else if(dma_abort) // 复位
			# simulation_delay flash_rd_data_buf_full <= 1'b0;
		else if((on_flash_data_wen & (~flash_rd_data_buf_full)) ^ on_flash_data_ren_sync) // 更新
			# simulation_delay flash_rd_data_buf_full <= 
				on_flash_data_ren_sync ? 1'b0:(flash_rd_data_buffered_n == (max_flash_rd_data_buffered_n - 1));
	end
	
	// SPI控制器发送fifo写溢出(指示)
	always @(posedge amba_clk or negedge amba_resetn)
	begin
		if(~amba_resetn)
			spi_tx_fifo_wt_ovf_reg <= 1'b0;
		else
			# simulation_delay spi_tx_fifo_wt_ovf_reg <= spi_tx_fifo_wen & spi_tx_fifo_full;
	end
	
	// 跨时钟域: 握手同步器!
	async_handshake #(
		.simulation_delay(simulation_delay)
	)async_handshake_u0(
		.clk1(audio_clk),
		.rst_n1(audio_resetn),
		
		.clk2(amba_clk),
		.rst_n2(amba_resetn),
		
		.req1(on_flash_data_ren),
		.busy(),
		
		.req2(on_flash_data_ren_sync)
	);
	
	/**
	DMA流程控制
	
	空闲 -> 发送读指令 -> 发送读地址 -> flash读数据 -> 等待flash读完成 -> 完成
	**/
	reg[5:0] dma_proc_onehot; // DMA流程独热码
	reg[1:0] flash_rd_baseaddr_sel; // 读地址字节选择(计数器)
	reg flash_rd_last_byte; // 读取最后一个字节(标志)
	
	assign dma_done = dma_proc_onehot[5];
	assign dma_idle = dma_proc_onehot[0];
	
	// DMA流程独热码
	always @(posedge amba_clk or negedge amba_resetn)
	begin
		if(~amba_resetn)
			dma_proc_onehot <= 6'b000001;
		else if(dma_proc_onehot[3] & dma_abort)
			# simulation_delay dma_proc_onehot <= 6'b000001;
		else if((dma_proc_onehot[0] & dma_req) | 
			dma_proc_onehot[1] | 
			(dma_proc_onehot[2] & flash_rd_baseaddr_sel[1]) | 
			(dma_proc_onehot[3] & flash_rd_last_byte & (~flash_rd_data_buf_full)) | 
			(dma_proc_onehot[4] & flash_rd_data_buf_empty) | 
			dma_proc_onehot[5])
			# simulation_delay dma_proc_onehot <= {dma_proc_onehot[4:0], dma_proc_onehot[5]};
	end
	
	// 读地址字节选择(计数器)
	always @(posedge amba_clk)
	begin
		# simulation_delay flash_rd_baseaddr_sel <= 
			dma_proc_onehot[2] ? (flash_rd_baseaddr_sel + 2'b01):2'b00;
	end
	
	/** 运行时参数 **/
	reg[23:0] flash_rd_baseaddr_latched; // 基地址
	reg[23:0] flash_rd_bytes_n_remaining; // 剩余的待读取字节数
	
	// 基地址
	always @(posedge amba_clk)
	begin
		if(dma_idle & dma_req)
			# simulation_delay flash_rd_baseaddr_latched <= flash_rd_baseaddr;
	end
	
	// 剩余的待读取字节数
	always @(posedge amba_clk)
	begin
		if(dma_idle & dma_req) // 载入
			# simulation_delay flash_rd_bytes_n_remaining <= flash_rd_bytes_n;
		else if(on_flash_data_wen & (~flash_rd_data_buf_full)) // 更新
			# simulation_delay flash_rd_bytes_n_remaining <= flash_rd_bytes_n_remaining - 24'd1;
	end
	// 读取最后一个字节(标志)
	always @(posedge amba_clk or negedge amba_resetn)
	begin
		if(~amba_resetn)
			flash_rd_last_byte <= 1'b0;
		else if(dma_proc_onehot[3] & dma_abort) // 复位
			# simulation_delay flash_rd_last_byte <= 1'b0;
		else if(on_flash_data_wen & (~flash_rd_data_buf_full)) // 更新
			# simulation_delay flash_rd_last_byte <= flash_rd_bytes_n_remaining == 2;
	end
	
	/** 写SPI控制器发送fifo **/
	reg spi_tx_fifo_wen_reg;
	reg[7:0] spi_tx_fifo_din_regs;
	reg spi_tx_fifo_ss_reg;
	
	assign spi_tx_fifo_wen = spi_tx_fifo_wen_reg;
	assign spi_tx_fifo_din = spi_tx_fifo_din_regs;
	assign spi_tx_fifo_ss = spi_tx_fifo_ss_reg;
	
	assign on_flash_data_wen = dma_proc_onehot[3];
	
	// 写使能
	always @(posedge amba_clk or negedge amba_resetn)
	begin
		if(~amba_resetn)
			spi_tx_fifo_wen_reg <= 1'b0;
		else
			# simulation_delay spi_tx_fifo_wen_reg <= dma_proc_onehot[1] | dma_proc_onehot[2] | 
				(dma_proc_onehot[3] & ((~flash_rd_data_buf_full) | dma_abort));
	end
	// 写数据#0
	always @(posedge amba_clk)
	begin
		if(dma_proc_onehot[2])
			# simulation_delay spi_tx_fifo_din_regs <= 
				(flash_rd_baseaddr_sel == 2'b00) ? flash_rd_baseaddr_latched[23:16]:
				(flash_rd_baseaddr_sel == 2'b01) ? flash_rd_baseaddr_latched[15:8]:
					flash_rd_baseaddr_latched[7:0];
		else
			# simulation_delay spi_tx_fifo_din_regs <= 8'h03;
	end
	// 写数据#1
	always @(posedge amba_clk)
	begin
		# simulation_delay spi_tx_fifo_ss_reg <= dma_proc_onehot[3] & (flash_rd_last_byte | dma_abort);
	end
	
endmodule
