`timescale 1ns / 1ps
/********************************************************************
本模块: 标准SPI控制器

描述: 
使用发送/接收fifo的标准SPI控制器
MSB First
支持全双工/半双工/单工
SPI事务数据位宽->8bit

注意：
收发fifo均为标准fifo
若需要使用标准SPI的单工模式, 固定好SPI传输方向即可

协议:
FIFO READ/WRITE
SPI MASTER

作者: 陈家耀
日期: 2023/11/17
********************************************************************/


module std_spi_tx_rx #(
    parameter integer spi_slave_n = 1, // SPI从机个数
    parameter integer spi_sck_div_n = 2, // SPI时钟分频系数(必须能被2整除, 且>=2)
    parameter integer spi_cpol = 0, // SPI空闲时的电平状态(0->低电平 1->高电平)
    parameter integer spi_cpha = 0, // SPI数据采样沿(0->奇数沿 1->偶数沿)
    parameter integer tx_user_data_width = 0, // 发送时用户数据位宽(0~32)
    parameter tx_user_default_v = 16'hff_ff, // 发送时用户数据默认值
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire spi_clk,
    input wire spi_resetn,
	// AMBA总线时钟和复位
	input wire amba_clk,
	input wire amba_resetn,
	
	// 运行时参数
	input wire[clogb2(spi_slave_n-1):0] rx_tx_sel, // 从机选择
	input wire[1:0] rx_tx_dire, // 传输方向(2'b11->收发 2'b10->接收 2'b01->发送 2'b00->保留)
    
    // 发送fifo读端口
    output wire tx_fifo_ren,
    input wire tx_fifo_empty,
    input wire[7:0] tx_fifo_dout,
    input wire tx_fifo_dout_ss,
    input wire[tx_user_data_width-1:0] tx_fifo_dout_user,
    // 接收fifo写端口
    output wire rx_fifo_wen,
    input wire rx_fifo_full,
    output wire[7:0] rx_fifo_din,
    
    // 控制器收发指示
    output wire rx_tx_start,
    output wire rx_tx_done,
    output wire rx_tx_idle,
    output wire rx_err, // 接收溢出指示
    
    // SPI主机接口
    output wire[spi_slave_n-1:0] spi_ss,
    output wire spi_sck,
    output wire spi_mosi,
    input wire spi_miso,
    output wire[tx_user_data_width-1:0] spi_user
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

    /** 参数 **/
    localparam integer sck_cnt_range = spi_sck_div_n/2-1; // SPI时钟分频计数器计数范围(0~sck_cnt_range)
    
    /** SPI收发控制 **/
    // SPI传输状态控制
    reg rx_tx_done_reg; // 本次SPI传输完成(脉冲)
    reg rx_tx_idle_reg; // SPI传输空闲(标志)
    
    reg is_now_transmitting; // 当前是否正在传输(标志)
    reg now_transmission_start; // 当前传输开始(脉冲)
    wire now_transmission_end; // 当前传输结束(脉冲)
    
    assign tx_fifo_ren = (~is_now_transmitting) | (is_now_transmitting & now_transmission_end);
    
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
        begin
            rx_tx_done_reg <= 1'b0;
            rx_tx_idle_reg <= 1'b1;
            is_now_transmitting <= 1'b0;
            now_transmission_start <= 1'b0;
        end
        else
        begin
            rx_tx_done_reg <= # simulation_delay now_transmission_end;
            rx_tx_idle_reg <= # simulation_delay tx_fifo_empty & (rx_tx_idle_reg | ((~rx_tx_idle_reg) & now_transmission_end));
            is_now_transmitting <= # simulation_delay is_now_transmitting ? (~(now_transmission_end & tx_fifo_empty)):(~tx_fifo_empty);
            now_transmission_start <= # simulation_delay (~tx_fifo_empty) & ((~is_now_transmitting) | (is_now_transmitting & now_transmission_end));
        end
    end
    
    // SPI片选
    reg[spi_slave_n-1:0] spi_ss_regs; // SPI片选信号
    reg spi_ss_to_high; // SPI片选拉高(标志)
    reg ss_latched; // 锁存的当前byte结束后SS电平
    
    assign spi_ss = spi_ss_regs;
    
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
            spi_ss_to_high <= 1'b0;
        else
            spi_ss_to_high <= # simulation_delay is_now_transmitting & now_transmission_end & tx_fifo_empty;
    end
    
    genvar spi_slave_i;
    generate
        if(spi_slave_n == 1)
        begin
            always @(posedge spi_clk or negedge spi_resetn)
            begin
                if(~spi_resetn)
                    spi_ss_regs <= 1'b1;
                else if((~is_now_transmitting) & (~tx_fifo_empty))
                    spi_ss_regs <= # simulation_delay 1'b0;
                else if(spi_ss_to_high)
                    spi_ss_regs <= # simulation_delay ss_latched;
            end
        end
        else
        begin
            for(spi_slave_i = 0;spi_slave_i < spi_slave_n;spi_slave_i = spi_slave_i + 1)
            begin:spi_ss_regs_blk
                always @(posedge spi_clk or negedge spi_resetn)
                begin
                    if(~spi_resetn)
                        spi_ss_regs[spi_slave_i] <= 1'b1;
                    else if((~is_now_transmitting) & (~tx_fifo_empty))
                        spi_ss_regs[spi_slave_i] <= # simulation_delay (rx_tx_sel != spi_slave_i);
                    else if(spi_ss_to_high)
                        spi_ss_regs[spi_slave_i] <= # simulation_delay (rx_tx_sel != spi_slave_i) | ss_latched;
                end
            end
        end
    endgenerate
    
    // SPI用户数据
    reg tx_fifo_ren_d;
    reg[tx_user_data_width-1:0] spi_user_regs;
    
    assign spi_user = spi_user_regs;
	
	always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
            tx_fifo_ren_d <= 1'b0;
        else
            tx_fifo_ren_d <= # simulation_delay tx_fifo_ren & (~tx_fifo_empty);
	end
    
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
            spi_user_regs <= tx_user_default_v;
        else if(tx_fifo_ren_d)
            spi_user_regs <= # simulation_delay tx_fifo_dout_user;
        else if(spi_ss_to_high)
            spi_user_regs <= # simulation_delay tx_user_default_v;
    end
    
    // SPI发送数据
    reg[7:0] tx_byte; // 待发送字节(数据)
    wire tx_byte_load; // 待发送字节(加载标志)
    wire tx_byte_shift; // 待发送字节(移位标志)
    wire tx_bit_valid; // 发送位计数信息有效(标志)
    reg[2:0] tx_bit_cnt; // 当前发送位编号(计数器)
    reg tx_bit_last; // 当前发送的是最后1bit(标志)
    
    assign spi_mosi = tx_byte[7];
    
    assign now_transmission_end = tx_bit_last & tx_byte_shift;
    assign tx_byte_load = now_transmission_start;
    assign tx_bit_valid = is_now_transmitting & (~now_transmission_start);
    
    always @(posedge spi_clk)
    begin
        if(tx_byte_load) // 加载
            ss_latched <= # simulation_delay tx_fifo_dout_ss;
    end
    
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
            tx_bit_last <= 1'b0;
        else if(tx_byte_load) // 加载
            tx_bit_last <= # simulation_delay 1'b0;
        else if(tx_byte_shift) // 移位
            tx_bit_last <= # simulation_delay tx_bit_cnt == 3'd1;
    end
    
    always @(posedge spi_clk)
    begin
        if(tx_byte_load) // 加载
        begin
            tx_byte <= # simulation_delay rx_tx_dire[0] ? tx_fifo_dout:8'dx;
            tx_bit_cnt <= # simulation_delay 3'd7;
        end
        else if(tx_byte_shift) // 移位
        begin
            tx_byte <= # simulation_delay {tx_byte[6:0], 1'bx};
            tx_bit_cnt <= # simulation_delay tx_bit_cnt - 3'd1;
        end
    end
    
    // 生成SPI时钟
    reg sck_reg; // SPI时钟
    reg[clogb2(sck_cnt_range):0] sck_div_cnt; // SPI时钟分频计数器
    wire sck_toggle; // SPI时钟信号翻转标志
    
    assign spi_sck = sck_reg;
    
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
            sck_reg <= spi_cpol;
        else if(sck_toggle)
            sck_reg <= # simulation_delay ~sck_reg;
    end
    
    generate
        wire sck_div_cnt_rst; // SPI时钟分频计数器回零(标志)
        
        assign tx_byte_shift = (spi_sck != (spi_cpol ^ spi_cpha)) & is_now_transmitting & (sck_toggle | (spi_cpha & sck_div_cnt_rst & (spi_sck == spi_cpol)));
        
        if(spi_cpha) // 偶数沿采样
            assign sck_toggle = tx_byte_load | (sck_div_cnt_rst & (~((spi_sck == spi_cpol) & tx_bit_last)));
        else // 奇数沿采样
            assign sck_toggle = sck_div_cnt_rst;
        
        if(sck_cnt_range > 0)
        begin
            assign sck_div_cnt_rst = sck_div_cnt == sck_cnt_range;
        
            always @(posedge spi_clk or negedge spi_resetn)
            begin
                if(~spi_resetn)
                    sck_div_cnt <= 0;
                else if(~tx_bit_valid) // 计数信息无效 -> SPI时钟分频计数器清零
                    sck_div_cnt <= # simulation_delay 0;
                else
                    sck_div_cnt <= # simulation_delay sck_div_cnt_rst ? 0:(sck_div_cnt + 1);
            end
        end
        else
            assign sck_div_cnt_rst = tx_bit_valid;
    endgenerate
    
    // SPI接收数据
    reg rx_fifo_wen_reg; // 接收fifo写使能
    reg[7:0] rx_fifo_din_regs; // 接收fifo写数据
    
    wire rx_byte_shift; // 接收字节(移位标志)
    reg[7:0] rx_byte; // 接收字节(数据)
    reg[2:0] rx_bit_cnt; // 当前接收位编号(计数器)
    reg rx_bit_last; // 当前接收的是最后1bit(标志)
    
    assign rx_fifo_wen = rx_fifo_wen_reg;
    assign rx_fifo_din = rx_fifo_din_regs;
    
    assign rx_byte_shift = (spi_sck == (spi_cpol ^ spi_cpha)) & is_now_transmitting & sck_toggle & rx_tx_dire[1];
    
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
            rx_fifo_wen_reg <= 1'b0;
        else
            rx_fifo_wen_reg <= # simulation_delay rx_bit_last & rx_byte_shift;
    end
    
    always @(posedge spi_clk)
    begin
        rx_fifo_din_regs <= # simulation_delay {rx_byte[6:0], spi_miso};
    end
    
    always @(posedge spi_clk)
    begin
        if(rx_byte_shift)
            rx_byte <= # simulation_delay {rx_byte[6:0], spi_miso};
    end
    
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
        begin
            rx_bit_cnt <= 3'b000;
            rx_bit_last <= 1'b0;
        end
        else if(rx_byte_shift)
        begin
            rx_bit_cnt <= # simulation_delay rx_bit_cnt + 3'b001;
            rx_bit_last <= # simulation_delay rx_bit_cnt == 3'b110;
        end
    end
    
    // 生成接收溢出指示
    reg rx_err_reg; // 接收溢出指示
    
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
            rx_err_reg <= 1'b0;
        else
            rx_err_reg <= # simulation_delay rx_fifo_wen & rx_fifo_full;
    end
	
	/** 控制器收发指示 **/
	reg rx_tx_idle_d; // 延迟1clk的收发器空闲(标志)
	reg rx_tx_idle_d2; // 延迟2clk的收发器空闲(标志)
	
	assign rx_tx_idle = rx_tx_idle_d2;
	
	/*
	跨时钟域:
		async_handshake_u0/ack -> async_handshake_u0/ack_d!
		async_handshake_u0/req -> async_handshake_u0/req_d!
	*/
	async_handshake #(
		.simulation_delay(simulation_delay)
	)async_handshake_u0(
		.clk1(spi_clk),
		.rst_n1(spi_resetn),
		
		.clk2(amba_clk),
		.rst_n2(amba_resetn),
		
		.req1(now_transmission_start),
		.busy(),
		
		.req2(rx_tx_start)
	);
	/*
	跨时钟域:
		async_handshake_u1/ack -> async_handshake_u1/ack_d!
		async_handshake_u1/req -> async_handshake_u1/req_d!
	*/
	async_handshake #(
		.simulation_delay(simulation_delay)
	)async_handshake_u1(
		.clk1(spi_clk),
		.rst_n1(spi_resetn),
		
		.clk2(amba_clk),
		.rst_n2(amba_resetn),
		
		.req1(rx_tx_done_reg),
		.busy(),
		
		.req2(rx_tx_done)
	);
	/*
	跨时钟域:
		async_handshake_u2/ack -> async_handshake_u2/ack_d!
		async_handshake_u2/req -> async_handshake_u2/req_d!
	*/
	async_handshake #(
		.simulation_delay(simulation_delay)
	)async_handshake_u2(
		.clk1(spi_clk),
		.rst_n1(spi_resetn),
		
		.clk2(amba_clk),
		.rst_n2(amba_resetn),
		
		.req1(rx_err_reg),
		.busy(),
		
		.req2(rx_err)
	);
	
	// 将收发器空闲(标志)打2拍
	// 跨时钟域: rx_tx_idle_reg -> rx_tx_idle_d!
	always @(posedge amba_clk or negedge amba_resetn)
	begin
		if(~amba_resetn)
			{rx_tx_idle_d2, rx_tx_idle_d} <= 2'b11;
		else
			{rx_tx_idle_d2, rx_tx_idle_d} <= # simulation_delay {rx_tx_idle_d, rx_tx_idle_reg};
	end

endmodule
