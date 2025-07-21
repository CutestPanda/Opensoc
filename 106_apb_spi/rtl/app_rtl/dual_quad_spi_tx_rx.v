`timescale 1ns / 1ps
/********************************************************************
本模块: DUAL/QUAD SPI控制器

描述: 
使用发送/接收fifo的Dual/QUAD SPI控制器
MSB First
单端口传输相当于标准SPI模式, 多端口传输对应Dual/QUAD SPI模式
单端口传输时支持全双工, 多端口传输时仅支持半双工
SPI事务数据位宽->8bit

注意：
收发fifo均为标准fifo

协议:
FIFO READ/WRITE
SPI MASTER

作者: 陈家耀
日期: 2023/11/22
********************************************************************/


module dual_quad_spi_tx_rx #(
    parameter spi_type = "dual", // SPI接口类型(双口->dual 四口->quad)
    parameter integer spi_slave_n = 1, // SPI从机个数
    parameter integer spi_sck_div_n = 2, // SPI时钟分频系数(必须能被2整除, 且>=2)
    parameter integer spi_cpol = 0, // SPI空闲时的电平状态(0->低电平 1->高电平)
    parameter integer spi_cpha = 0, // SPI数据采样沿(0->奇数沿 1->偶数沿)
    parameter integer tx_user_data_width = 0, // 发送时用户数据位宽(0~16)
    parameter tx_user_default_v = 16'hff_ff, // 发送时用户数据默认值
    parameter real simulation_delay = 1 // 仿真延时
)(
    // SPI时钟和复位
    input wire spi_clk,
    input wire spi_resetn,
	// AMBA总线时钟和复位
	input wire amba_clk,
	input wire amba_resetn,
	
	// 运行时参数
	input wire[clogb2(spi_slave_n-1):0] rx_tx_sel, // 从机选择
    
    // 发送fifo读端口
    output wire tx_fifo_ren,
    input wire tx_fifo_empty,
    input wire[7:0] tx_fifo_dout,
    input wire tx_fifo_dout_ss,
    input wire[tx_user_data_width-1:0] tx_fifo_dout_user,
    input wire tx_fifo_dout_dire, // 当前byte的传输方向(1'b0->接收 1'b1->发送)
    input wire tx_fifo_dout_en_mul, // 当前byte是否在多端口上传输
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
    // io0
    output wire spi_io0_t,
    output wire spi_io0_o,
    input wire spi_io0_i,
    // io1
    output wire spi_io1_t,
    output wire spi_io1_o,
    input wire spi_io1_i,
    // io2
    output wire spi_io2_t,
    output wire spi_io2_o,
    input wire spi_io2_i,
    // io3
    output wire spi_io3_t,
    output wire spi_io3_o,
    input wire spi_io3_i,
    // user
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
    
    /** 参数和常量 **/
    localparam integer sck_cnt_range = spi_sck_div_n / 2 - 1; // SPI时钟分频计数器计数范围(0~sck_cnt_range)
    // 收发控制状态机的状态常量
    localparam STS_IDLE = 2'b00; // 空闲
    localparam STS_LOAD_DATA = 2'b01; // 载入数据
    localparam STS_SINGLE_PORT_TRANS = 2'b10; // 单端口传输中
    localparam STS_MUL_PORT_TRANS = 2'b11; // 多端口传输中
    
    /** 收发控制 **/
    // 发送/接收fifo
    wire tx_fifo_ren_w;
    reg rx_fifo_wen_reg;
    wire[7:0] rx_fifo_din_w;
    // 收发器状态
    reg rx_tx_start_reg; // 开始发送/接收(脉冲)
    reg rx_tx_done_reg; // 完成发送/接收(脉冲)
    reg rx_tx_idle_reg; // 收发器空闲(标志)
    reg rx_err_reg; // 接收溢出(脉冲)
    // SPI接口
    reg[spi_slave_n-1:0] spi_ss_reg;
    reg spi_sck_reg;
    reg spi_io0_t_reg;
    reg spi_io0_o_reg;
    reg spi_io1_t_reg;
    reg spi_io1_o_reg;
    reg spi_io2_t_reg;
    reg spi_io2_o_reg;
    reg spi_io3_t_reg;
    reg spi_io3_o_reg;
    // 用户信号
    reg[tx_user_data_width-1:0] spi_user_regs;
    // 锁存的当前byte传输结束后ss电平
    reg ss_latched;
    // 状态机
    reg[7:0] tx_bits; // 待发送数据
    reg[7:0] rx_bits; // 接收到的数据
    reg[1:0] tx_rx_status; // 当前状态
    reg[clogb2(sck_cnt_range):0] div_cnt; // 分频计数器
    wire div_cnt_clr; // 分频计数器(清零脉冲)
    wire tx_next; // 移出下1个待发送bit(脉冲)
    wire rx_next; // 移入下1个接收到bit(脉冲)
    reg[2:0] tx_bits_n_cnt; // 当前已处理bit数(计数器)
    reg tx_bits_last; // 当前是最后1bit(标志)
    
    assign {tx_fifo_ren, rx_fifo_wen, rx_fifo_din} = 
        {tx_fifo_ren_w, rx_fifo_wen_reg, rx_fifo_din_w};
    assign {spi_ss, spi_sck, spi_io0_t, spi_io0_o, spi_io1_t, spi_io1_o, spi_io2_t, spi_io2_o, spi_io3_t, spi_io3_o} = 
        {spi_ss_reg, spi_sck_reg, 
        spi_io0_t_reg, spi_io0_o_reg, 
        spi_io1_t_reg, spi_io1_o_reg, 
        (spi_type == "quad") ? spi_io2_t_reg:1'b1, (spi_type == "quad") ? spi_io2_o_reg:1'bx,
        (spi_type == "quad") ? spi_io3_t_reg:1'b1, (spi_type == "quad") ? spi_io3_o_reg:1'bx};
    assign spi_user = spi_user_regs;
    
    assign tx_fifo_ren_w = (tx_rx_status == STS_IDLE) | 
        (((tx_rx_status == STS_SINGLE_PORT_TRANS) | (tx_rx_status == STS_MUL_PORT_TRANS)) & tx_next & tx_bits_last);
    assign rx_fifo_din_w = rx_bits;
    
    // 状态机
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
        begin
            tx_rx_status <= STS_IDLE;
            rx_tx_idle_reg <= 1'b1;
            spi_sck_reg <= spi_cpol;
            {spi_io3_t_reg, spi_io2_t_reg, spi_io1_t_reg, spi_io0_t_reg} <= 4'b1111;
            spi_user_regs <= tx_user_default_v;
        end
        else
        begin
            case(tx_rx_status)
                STS_IDLE: // 空闲
                begin
                    tx_rx_status <= # simulation_delay (~tx_fifo_empty) ? STS_LOAD_DATA:STS_IDLE;
                    rx_tx_idle_reg <= # simulation_delay tx_fifo_empty;
                    {spi_io3_t_reg, spi_io2_t_reg, spi_io1_t_reg, spi_io0_t_reg} <= # simulation_delay 4'b1111;
                    spi_user_regs <= # simulation_delay tx_user_default_v;
                end
                STS_LOAD_DATA: // 载入数据
                begin
                    tx_rx_status <= # simulation_delay tx_fifo_dout_en_mul ? STS_MUL_PORT_TRANS:STS_SINGLE_PORT_TRANS;
                    rx_tx_idle_reg <= # simulation_delay 1'b0;
                    
                    if(spi_cpha)
                        spi_sck_reg <= # simulation_delay ~spi_sck_reg;
                    
                    {spi_io3_t_reg, spi_io2_t_reg, spi_io1_t_reg, spi_io0_t_reg} <= # simulation_delay 
						tx_fifo_dout_en_mul ? 
							{4{~tx_fifo_dout_dire}}:
							{3'b111, ~tx_fifo_dout_dire};
                    spi_user_regs <= # simulation_delay tx_fifo_dout_user;
                end
                STS_SINGLE_PORT_TRANS: // 单端口传输中
                begin
                    if(spi_cpha ? (div_cnt_clr & (~(tx_bits_last & (spi_sck_reg == spi_cpol)))):div_cnt_clr)
                        spi_sck_reg <= # simulation_delay ~spi_sck_reg;
                    
                    if(tx_next & tx_bits_last)
                    begin
                        tx_rx_status <= # simulation_delay (~tx_fifo_empty) ? STS_LOAD_DATA:STS_IDLE;
                        rx_tx_idle_reg <= # simulation_delay tx_fifo_empty;
                    end
                    else
                    begin
                        tx_rx_status <= # simulation_delay STS_SINGLE_PORT_TRANS;
                        rx_tx_idle_reg <= # simulation_delay 1'b0;
                    end
                end
                STS_MUL_PORT_TRANS: // 多端口传输中
                begin
                    if(spi_cpha ? (div_cnt_clr & (~(tx_bits_last & (spi_sck_reg == spi_cpol)))):div_cnt_clr)
                        spi_sck_reg <= # simulation_delay ~spi_sck_reg;
                    
                    if(tx_next & tx_bits_last)
                    begin
                        tx_rx_status <= # simulation_delay 
							(~tx_fifo_empty) ? 
								STS_LOAD_DATA:
								STS_IDLE;
                        rx_tx_idle_reg <= # simulation_delay tx_fifo_empty;
                    end
                    else
                    begin
                        tx_rx_status <= # simulation_delay STS_MUL_PORT_TRANS;
                        rx_tx_idle_reg <= # simulation_delay 1'b0;
                    end
                end
                default:
                begin
                    tx_rx_status <= # simulation_delay STS_IDLE;
                    rx_tx_idle_reg <= # simulation_delay 1'b1;
                    spi_sck_reg <= # simulation_delay spi_cpol;
                    {spi_io3_t_reg, spi_io2_t_reg, spi_io1_t_reg, spi_io0_t_reg} <= # simulation_delay 4'b1111;
                    spi_user_regs <= # simulation_delay tx_user_default_v;
                end
            endcase
        end
    end
	
	always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
		begin
			rx_fifo_wen_reg <= 1'b0;
			rx_tx_start_reg <= 1'b0;
			rx_tx_done_reg <= 1'b0;
		end
		else
		begin
			rx_fifo_wen_reg <= # simulation_delay 
				tx_next & tx_bits_last & (
					(tx_rx_status == STS_SINGLE_PORT_TRANS) | 
					(tx_rx_status == STS_MUL_PORT_TRANS)
				);
			rx_tx_start_reg <= # simulation_delay tx_rx_status == STS_LOAD_DATA;
			rx_tx_done_reg <= # simulation_delay 
				tx_next & tx_bits_last & (
					(tx_rx_status == STS_SINGLE_PORT_TRANS) | 
					(tx_rx_status == STS_MUL_PORT_TRANS)
				);
		end
	end
    
    // 锁存的当前byte传输结束后ss电平
    always @(posedge spi_clk)
    begin
        if(tx_rx_status == STS_LOAD_DATA)
            ss_latched <= # simulation_delay tx_fifo_dout_ss;
    end
    
    // SPI数据端
    always @(posedge spi_clk)
    begin
        case(tx_rx_status)
            STS_LOAD_DATA: // 载入数据
            begin
                if(tx_fifo_dout_dire)
                begin
                    if(spi_type == "quad")
                    begin
                        spi_io0_o_reg <= # simulation_delay tx_fifo_dout_en_mul ? tx_fifo_dout[4]:tx_fifo_dout[7];
                        spi_io1_o_reg <= # simulation_delay tx_fifo_dout_en_mul ? tx_fifo_dout[5]:1'bx;
                        spi_io2_o_reg <= # simulation_delay tx_fifo_dout_en_mul ? tx_fifo_dout[6]:1'bx;
                        spi_io3_o_reg <= # simulation_delay tx_fifo_dout_en_mul ? tx_fifo_dout[7]:1'bx;
                    end
                    else
                    begin
                        spi_io0_o_reg <= # simulation_delay tx_fifo_dout_en_mul ? tx_fifo_dout[6]:tx_fifo_dout[7];
                        spi_io1_o_reg <= # simulation_delay tx_fifo_dout_en_mul ? tx_fifo_dout[7]:1'bx;
                    end
                end
                else
                begin
                    spi_io0_o_reg <= # simulation_delay 1'bx;
                    spi_io1_o_reg <= # simulation_delay 1'bx;
                    
                    if(spi_type == "quad")
                    begin
                        spi_io2_o_reg <= # simulation_delay 1'bx;
                        spi_io3_o_reg <= # simulation_delay 1'bx;
                    end
                end
            end
            STS_SINGLE_PORT_TRANS: // 单端口传输中
            begin
                if(tx_next)
                    spi_io0_o_reg <= # simulation_delay tx_bits[6];
            end
            STS_MUL_PORT_TRANS: // 多端口传输中
            begin
                if(tx_next)
                begin
                    if(spi_type == "quad")
                    begin
                        spi_io0_o_reg <= # simulation_delay tx_bits[0];
                        spi_io1_o_reg <= # simulation_delay tx_bits[1];
                        spi_io2_o_reg <= # simulation_delay tx_bits[2];
                        spi_io3_o_reg <= # simulation_delay tx_bits[3];
                    end
                    else
                    begin
                        spi_io0_o_reg <= # simulation_delay tx_bits[4];
                        spi_io1_o_reg <= # simulation_delay tx_bits[5];
                    end
                end
            end
            default:
            begin
                spi_io0_o_reg <= # simulation_delay spi_io0_o_reg;
                spi_io1_o_reg <= # simulation_delay spi_io1_o_reg;
                spi_io2_o_reg <= # simulation_delay spi_io2_o_reg;
                spi_io3_o_reg <= # simulation_delay spi_io3_o_reg;
            end
        endcase
    end
    
    // 待发送数据
    always @(posedge spi_clk)
    begin
        case(tx_rx_status)
            STS_LOAD_DATA: // 载入数据
                tx_bits <= # simulation_delay tx_fifo_dout_dire ? tx_fifo_dout:8'dx;
            STS_SINGLE_PORT_TRANS: // 单端口传输中
                if(tx_next)
                    tx_bits <= # simulation_delay {tx_bits[6:0], 1'bx};
            STS_MUL_PORT_TRANS: // 多端口传输中
                if(tx_next && spi_type == "dual")
                    tx_bits <= # simulation_delay {tx_bits[5:0], 2'bxx};
            default:
                tx_bits <= # simulation_delay tx_bits;
        endcase
    end
    
    // 接收到的数据
    always @(posedge spi_clk)
    begin
        case(tx_rx_status)
            STS_SINGLE_PORT_TRANS: // 单端口传输中
                if(rx_next)
                    rx_bits <= # simulation_delay {rx_bits[6:0], spi_io1_i};
            STS_MUL_PORT_TRANS: // 多端口传输中
                if(rx_next)
                    rx_bits <= # simulation_delay (spi_type == "quad") ? {rx_bits[3:0], spi_io3_i, spi_io2_i, spi_io1_i, spi_io0_i}:{rx_bits[5:0], spi_io1_i, spi_io0_i};
            default:
                rx_bits <= # simulation_delay rx_bits;
        endcase
    end
    
    // 分频计数器
    assign div_cnt_clr = (sck_cnt_range == 0) ? 1'b1:(div_cnt == sck_cnt_range);
    assign tx_next = div_cnt_clr & ((spi_cpol ^ spi_cpha) ? (~spi_sck_reg):spi_sck_reg);
    assign rx_next = div_cnt_clr & ((spi_cpol ^ spi_cpha) ? spi_sck_reg:(~spi_sck_reg));
    
    generate
        if(sck_cnt_range > 0)
        begin
            always @(posedge spi_clk)
            begin
                if((tx_rx_status == STS_IDLE) | (tx_rx_status == STS_LOAD_DATA))
                    div_cnt <= # simulation_delay 0;
                else
                    div_cnt <= # simulation_delay (div_cnt == sck_cnt_range) ? 0:(div_cnt + 1);
            end
        end
    endgenerate
    
    // 当前已处理bit数(计数器)
    always @(posedge spi_clk)
    begin
        if((tx_rx_status == STS_IDLE) | (tx_rx_status == STS_LOAD_DATA))
        begin
            tx_bits_n_cnt <= # simulation_delay 3'd0;
            tx_bits_last <= # simulation_delay 1'b0;
        end
        else if(tx_next)
        begin
            tx_bits_n_cnt <= # simulation_delay tx_bits_n_cnt + 3'd1;
            
            if(spi_type == "quad")
                tx_bits_last <= # simulation_delay (tx_rx_status == STS_SINGLE_PORT_TRANS) ? (tx_bits_n_cnt == 3'd6):1'b1;
            else
                tx_bits_last <= # simulation_delay (tx_rx_status == STS_SINGLE_PORT_TRANS) ? (tx_bits_n_cnt == 3'd6):(tx_bits_n_cnt == 3'd2);
        end
    end
    
    // SPI片选
    genvar spi_ss_reg_i;
    generate
        if(spi_slave_n == 1)
        begin
            always @(posedge spi_clk or negedge spi_resetn)
            begin
                if(~spi_resetn)
                    spi_ss_reg <= 1'b1;
                else if((tx_rx_status == STS_LOAD_DATA) | ((tx_rx_status == STS_IDLE) & (~tx_fifo_empty)))
                    spi_ss_reg <= # simulation_delay 1'b0;
                else if(rx_tx_done_reg)
                    spi_ss_reg <= # simulation_delay ss_latched;
            end
        end
        else
        begin
            for(spi_ss_reg_i = 0;spi_ss_reg_i < spi_slave_n;spi_ss_reg_i = spi_ss_reg_i + 1)
            begin:spi_ss_reg_blk
                always @(posedge spi_clk or negedge spi_resetn)
                begin
                    if(~spi_resetn)
                        spi_ss_reg[spi_ss_reg_i] <= 1'b1;
                    else if((tx_rx_status == STS_LOAD_DATA) | ((tx_rx_status == STS_IDLE) & (~tx_fifo_empty)))
                        spi_ss_reg[spi_ss_reg_i] <= # simulation_delay rx_tx_sel != spi_ss_reg_i;
                    else if(rx_tx_done_reg)
                        spi_ss_reg <= # simulation_delay (rx_tx_sel != spi_ss_reg_i) | ss_latched;
                end
            end
        end
    endgenerate
    
    // 接收溢出(脉冲)
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
            rx_err_reg <= 1'b0;
        else
            rx_err_reg <= # simulation_delay rx_fifo_wen_reg & rx_fifo_full;
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
		
		.req1(rx_tx_start_reg),
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
