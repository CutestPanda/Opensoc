`timescale 1ns / 1ps
/********************************************************************
本模块: AXI-片上执行SPI控制器

描述: 
符合AXI协议的片上执行SPI控制器(可实现Flash的等效片上读)
支持非对齐传输和窄带传输

注意：
AXI接口仅支持读传输
AXI接口仅支持INCR传输

协议:
AXI SLAVE
SPI MASTER
FIFO READ/WRITE

作者: 陈家耀
日期: 2023/12/15
********************************************************************/


module axi_spi_xip_ctrler #(
    parameter spi_type = "std", // SPI接口类型(标准->std 双口->dual 四口->quad)
    parameter integer spi_sck_div_n = 2, // SPI时钟分频系数(必须能被2整除, 且>=2)
    parameter integer spi_cpol = 0, // SPI空闲时的电平状态(0->低电平 1->高电平)
    parameter integer spi_cpha = 0, // SPI数据采样沿(0->奇数沿 1->偶数沿)
    parameter en_unaligned_transfer = "false", // 是否启用非对齐传输
    parameter en_narrow_transfer = "false", // 是否启用窄带传输
    parameter real simulation_delay = 1 // 仿真延时
)(
	// SPI时钟和复位
    input wire spi_clk,
    input wire spi_resetn,
    // AMBA总线时钟和复位
    input wire amba_clk,
    input wire amba_resetn,
    
    // AXI从接口
    // 读地址通道
    input wire[31:0] s_axi_araddr,
    // 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
    input wire[1:0] s_axi_arburst,
    input wire[3:0] s_axi_arcache, // ignored
    input wire[7:0] s_axi_arlen,
    input wire[2:0] s_axi_arprot, // ignored
    // 3'b000 -> 8; 3'b001 -> 16; 3'b010 -> 32;
    input wire[2:0] s_axi_arsize,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    // 读数据通道
    output wire[31:0] s_axi_rdata,
    output wire s_axi_rlast,
    output wire[1:0] s_axi_rresp, // const -> 2'b00
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    
    // 控制器收发指示
    input wire[1:0] rx_tx_dire, // 传输方向(2'b11->收发 2'b10->接收 2'b01->发送 2'b00->保留)
    input wire en_xip, // 使能片内执行
    output wire rx_tx_start,
    output wire rx_tx_done,
    output wire rx_tx_idle,
    output wire rx_err, // 接收溢出指示
    
    // xip发送fifo写端口
    output wire xip_tx_fifo_wen,
    input wire xip_tx_fifo_full,
    output wire[7:0] xip_tx_fifo_din,
    output wire xip_tx_fifo_din_ss,
    output wire xip_tx_fifo_din_ignored,
    output wire xip_tx_fifo_din_last,
    output wire xip_tx_fifo_din_dire,
    output wire xip_tx_fifo_din_en_mul,
    // xip发送fifo读端口
    output wire xip_tx_fifo_ren,
    input wire xip_tx_fifo_empty,
    input wire[7:0] xip_tx_fifo_dout,
    input wire xip_tx_fifo_dout_ss,
    input wire xip_tx_fifo_dout_ignored,
    input wire xip_tx_fifo_dout_last,
    input wire xip_tx_fifo_dout_dire,
    input wire xip_tx_fifo_dout_en_mul,
    
    // 寄存器操作模式下的接收fifo写端口
    output wire rx_fifo_wen,
    input wire rx_fifo_full,
    output wire[7:0] rx_fifo_din,
    
    // SPI主机接口
    output wire spi_ss,
    output wire spi_sck,
    // io0
    output wire spi_io0_t,
    output wire spi_io0_o, // denotes mosi if spi_type == "std"
    input wire spi_io0_i,
    // io1
    output wire spi_io1_t,
    output wire spi_io1_o,
    input wire spi_io1_i, // denotes miso if spi_type == "std"
    // io2(only used when spi_type == "quad")
    output wire spi_io2_t,
    output wire spi_io2_o,
    input wire spi_io2_i,
    // io3(only used when spi_type == "quad")
    output wire spi_io3_t,
    output wire spi_io3_o,
    input wire spi_io3_i,
    
    // xip错误指示
    output wire[2:0] xip_err // {不支持的突发类型, 不支持的非对齐, 不支持的窄带传输}
);

    /** AXI从接口(读地址通道, AR) **/
    // axi的ar通道 -> 读命令AXIS主接口
    // 读命令AXIS从接口(axis reg slice)
    wire[23:0] s_reg_axis_data_addr; // 读flash首地址
    wire[11:0] s_reg_axis_user_len; // 读flash字节数-1
    wire[1:0] s_reg_axis_user_size; // 突发大小
    wire s_reg_axis_valid;
    wire s_reg_axis_ready;
    // 读命令AXIS主接口 -> 读地址信息fifo写端口
    // 读命令AXIS主接口(axis reg slice)
    wire[23:0] m_reg_axis_data_addr; // 读flash首地址
    wire[11:0] m_reg_axis_user_len; // 读flash字节数-1
    wire[1:0] m_reg_axis_user_size; // 突发大小
    wire m_reg_axis_valid;
    wire m_reg_axis_ready;
    // 读命令AXIS从接口(spi xip ctrler)
    wire[23:0] s_axis_data_addr; // 读flash首地址
    wire[11:0] s_axis_user_len; // 读flash字节数-1
    wire s_axis_valid;
    wire s_axis_ready;
    // 读地址信息fifo
    wire ar_fifo_wen;
    wire ar_fifo_full_n;
    wire[1:0] ar_fifo_din_addr; // 低2位地址
    wire[1:0] ar_fifo_din_size; // 突发大小
    wire ar_fifo_ren;
    wire ar_fifo_empty_n;
    wire[1:0] ar_fifo_dout_addr; // 低2位地址
    wire[1:0] ar_fifo_dout_size; // 突发大小
    
    assign s_reg_axis_data_addr = s_axi_araddr[23:0];
    /*
    非对齐传输 窄带传输       读flash字节数
       No        No      {2'b00, s_axi_arlen, 2'b11}
       No        Yes     (s_axi_arsize[1:0] == 2'b00) ? s_axi_arlen:
                         (s_axi_arsize[1:0] == 2'b01) ? {3'b000, s_axi_arlen, 1'b1}:
                                                        {2'b00, s_axi_arlen, 2'b11}
       Yes       No      {2'b00, s_axi_arlen, ~s_axi_araddr[1:0]}
       Yes       Yes     (s_axi_arsize[1:0] == 2'b00) ? s_axi_arlen:
                         (s_axi_arsize[1:0] == 2'b01) ? {3'b000, s_axi_arlen, ~(((s_axi_araddr[1:0] == 2'b01) & (s_axi_arlen != 8'd0)) | (s_axi_araddr[1:0] == 2'b11))}:
                                                        {2'b00, s_axi_arlen, ~s_axi_araddr[1:0]}
    */
    generate
        if((en_unaligned_transfer == "false") && (en_narrow_transfer == "false"))
            assign s_reg_axis_user_len = {2'b00, s_axi_arlen, 2'b11};
        else if((en_unaligned_transfer == "false") && (en_narrow_transfer == "true"))
            assign s_reg_axis_user_len = (s_axi_arsize[1:0] == 2'b00) ? s_axi_arlen:
                (s_axi_arsize[1:0] == 2'b01) ? {3'b000, s_axi_arlen, 1'b1}:
                    {2'b00, s_axi_arlen, 2'b11};
        else if((en_unaligned_transfer == "true") && (en_narrow_transfer == "false"))
            assign s_reg_axis_user_len = {2'b00, s_axi_arlen, ~s_axi_araddr[1:0]};
        else
            assign s_reg_axis_user_len = (s_axi_arsize[1:0] == 2'b00) ? s_axi_arlen:
                (s_axi_arsize[1:0] == 2'b01) ? {3'b000, s_axi_arlen, ~(((s_axi_araddr[1:0] == 2'b01) & (s_axi_arlen != 8'd0)) | (s_axi_araddr[1:0] == 2'b11))}:
                    {2'b00, s_axi_arlen, ~s_axi_araddr[1:0]};
    endgenerate
    assign s_reg_axis_user_size = s_axi_arsize[1:0];
    assign s_reg_axis_valid = s_axi_arvalid;
    assign s_axi_arready = s_reg_axis_ready;
    
    assign s_axis_data_addr = m_reg_axis_data_addr;
    assign s_axis_user_len = m_reg_axis_user_len;
    assign s_axis_valid = m_reg_axis_valid & ar_fifo_full_n;
    assign m_reg_axis_ready = s_axis_ready & ar_fifo_full_n;
    
    generate
        if((en_unaligned_transfer == "true") || (en_narrow_transfer == "true"))
        begin
            assign ar_fifo_wen = m_reg_axis_valid & s_axis_ready;
            assign ar_fifo_din_addr = m_reg_axis_data_addr[1:0];
            assign ar_fifo_din_size = m_reg_axis_user_size;
        end
    endgenerate
    
    // AXI读地址通道reg slice
    axis_reg_slice #(
        .data_width(24),
        .user_width(14),
        .en_ready("true"),
        .forward_registered("true"),
        .back_registered("true"),
        .simulation_delay(simulation_delay)
    )axi_ar_reg_slice(
        .clk(amba_clk),
        .rst_n(amba_resetn),
        .s_axis_data(s_reg_axis_data_addr),
        .s_axis_user({s_reg_axis_user_size, s_reg_axis_user_len}),
        .s_axis_valid(s_reg_axis_valid),
        .s_axis_ready(s_reg_axis_ready),
        .m_axis_data(m_reg_axis_data_addr),
        .m_axis_user({m_reg_axis_user_size, m_reg_axis_user_len}),
        .m_axis_valid(m_reg_axis_valid),
        .m_axis_ready(m_reg_axis_ready)
    );
    
    // 读地址信息fifo
    ram_fifo_wrapper #(
        .fwft_mode("false"),
        .ram_type("lutram"),
        .en_bram_reg(),
        .fifo_depth(32),
        .fifo_data_width(4),
        .full_assert_polarity("low"),
        .empty_assert_polarity("low"),
        .almost_full_assert_polarity("no"),
        .almost_empty_assert_polarity("no"),
        .en_data_cnt("false"),
        .almost_full_th(),
        .almost_empty_th(),
        .simulation_delay(simulation_delay)
    )ar_fifo(
        .clk(amba_clk),
        .rst_n(amba_resetn),
        .fifo_wen(ar_fifo_wen),
        .fifo_din({ar_fifo_din_size, ar_fifo_din_addr}),
        .fifo_full_n(ar_fifo_full_n),
        .fifo_ren(ar_fifo_ren),
        .fifo_dout({ar_fifo_dout_size, ar_fifo_dout_addr}),
        .fifo_empty_n(ar_fifo_empty_n)
    );
    
    /** AXI从接口(读数据通道, R) **/
    // xip接收fifo
    wire xip_rev_fifo_wen;
    wire xip_rev_fifo_full;
    wire[7:0] xip_rev_fifo_din_data;
    wire xip_rev_fifo_din_last;
    wire xip_rev_fifo_ren;
    wire xip_rev_fifo_empty;
    wire[7:0] xip_rev_fifo_dout_data;
    wire xip_rev_fifo_dout_last;
    // 等效的axi读数据通道axis
    wire[31:0] s_axi_rdata_w;
    wire s_axi_rlast_w;
    wire s_axi_rvalid_w;
    wire s_axi_rready_w;
    // 不支持的突发类型
    reg burst_type_not_support;
    
    assign s_axi_rresp = 2'b00;
    
    always @(posedge amba_clk or negedge amba_resetn)
    begin
        if(~amba_resetn)
            burst_type_not_support <= 1'b0;
        else
            # simulation_delay burst_type_not_support <= s_axi_arvalid & s_axi_arready & (s_axi_arburst != 2'b01);
    end
    
    generate
        if((en_unaligned_transfer == "false") && (en_narrow_transfer == "false"))
        begin
            reg[31:0] rdata; // 保存的读数据
            reg rlast; // 保存的last信号
            reg[3:0] rdata_onehot_cnt; // 读数据保存字节使能
            reg rdata_vld; // 读数据有效(标志)
            reg ar_fifo_ren_vld; // 读地址信息fifo有效读(脉冲)
            reg[1:0] xip_err_regs; // xip错误指示(不支持的非对齐, 不支持的窄带传输)
            
            assign ar_fifo_ren = 1'b1;
            
            assign xip_rev_fifo_ren = ~rdata_vld;
            
            assign s_axi_rdata_w = rdata;
            assign s_axi_rlast_w = rlast;
            assign s_axi_rvalid_w = rdata_vld;
            
            assign xip_err = {burst_type_not_support, xip_err_regs};
            
            always @(posedge amba_clk)
            begin
                # simulation_delay;
                
                if((~rdata_vld) & rdata_onehot_cnt[0])
                    rdata[7:0] <= xip_rev_fifo_dout_data;
                
                if(rdata_onehot_cnt[1])
                    rdata[15:8] <= xip_rev_fifo_dout_data;
                
                if(rdata_onehot_cnt[2])
                    rdata[23:16] <= xip_rev_fifo_dout_data;
                
                if(rdata_onehot_cnt[3])
                begin
                    rdata[31:24] <= xip_rev_fifo_dout_data;
                    rlast <= xip_rev_fifo_dout_last;
                end
            end
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                begin
                    rdata_onehot_cnt <= 4'b0001;
                    rdata_vld <= 1'b0;
                end
                else
                begin
                    # simulation_delay;
                    
                    if(rdata_vld)
                        rdata_vld <= ~(s_axi_rready_w);
                    else
                        rdata_vld <= rdata_onehot_cnt[3] & (~xip_rev_fifo_empty);
                    
                    if(xip_rev_fifo_ren & (~xip_rev_fifo_empty)) // 循环左移
                        rdata_onehot_cnt <= {rdata_onehot_cnt[2:0], rdata_onehot_cnt[3]};
                end
            end
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    ar_fifo_ren_vld <= 1'b0;
                else
                    # simulation_delay ar_fifo_ren_vld <= ar_fifo_ren & ar_fifo_empty_n;
            end
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    xip_err_regs <= 2'b00;
                else
                begin
                    # simulation_delay;
                    
                    xip_err_regs[1] <= ar_fifo_ren_vld & (ar_fifo_dout_addr != 2'b00);
                    xip_err_regs[0] <= ar_fifo_ren_vld & ar_fifo_dout_size != 2'b10;
                end
            end
        end
        else if((en_unaligned_transfer == "false") && (en_narrow_transfer == "true"))
        begin
            // 窄带传输
            reg read_transmitting; // 读传输进行中(标志)
            wire read_start; // 读传输开始(脉冲)
            reg[31:0] rdata; // 保存的读数据
            reg rlast; // 保存的last信号
            reg[1:0] rbyte_cnt; // 保存的读数据字节数-1(计数器)
            reg[3:0] rdata_onehot_cnt; // 读数据保存字节使能
            reg rdata_vld; // 读数据有效(标志)
            reg ar_fifo_ren_vld; // 读地址信息fifo有效读(脉冲)
            reg xip_err_reg; // xip错误指示(不支持的非对齐)
            
            assign read_start = ar_fifo_ren & ar_fifo_empty_n;
            
            assign ar_fifo_ren = read_transmitting ? (s_axi_rvalid_w & s_axi_rready_w & s_axi_rlast_w):1'b1;
            assign xip_rev_fifo_ren = read_transmitting & (~rdata_vld);
            assign s_axi_rdata_w = rdata;
            assign s_axi_rlast_w = rlast;
            assign s_axi_rvalid_w = read_transmitting & rdata_vld;
            
            assign xip_err = {burst_type_not_support, xip_err_reg, 1'b0};
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    read_transmitting <= 1'b0;
                else
                begin
                    # simulation_delay;
                    
                    if(read_transmitting)
                        read_transmitting <= (s_axi_rvalid_w & s_axi_rready_w & s_axi_rlast_w) ? ar_fifo_empty_n:1'b1;
                    else
                        read_transmitting <= ar_fifo_empty_n;
                end
            end
            
            always @(posedge amba_clk)
            begin
                # simulation_delay;
                
                if(~rdata_vld)
                begin
                    if(rdata_onehot_cnt[0])
                        rdata[7:0] <= xip_rev_fifo_dout_data;
                    
                    if(rdata_onehot_cnt[1])
                        rdata[15:8] <= xip_rev_fifo_dout_data;
                    
                    if(rdata_onehot_cnt[2])
                        rdata[23:16] <= xip_rev_fifo_dout_data;
                    
                    if(rdata_onehot_cnt[3])
                        rdata[31:24] <= xip_rev_fifo_dout_data;
                    
                    rlast <= xip_rev_fifo_dout_last;
                end
            end
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    rbyte_cnt <= 2'b00;
                else if(xip_rev_fifo_ren & (~xip_rev_fifo_empty))
                begin
                    # simulation_delay;
                    
                    case(ar_fifo_dout_size)
                        2'b00: // 突发长度1字节
                            rbyte_cnt <= 2'b00;
                        2'b01: // 突发长度2字节
                            rbyte_cnt <= {1'b0, ~rbyte_cnt[0]};
                        default: // 突发长度4字节
                            rbyte_cnt <= rbyte_cnt + 2'b01;
                    endcase
                end
            end
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    rdata_onehot_cnt <= 4'b0001;
                else if(read_start) // 复位
                    rdata_onehot_cnt <= 4'b0001;
                else if(xip_rev_fifo_ren & (~xip_rev_fifo_empty)) // 循环左移
                    # simulation_delay rdata_onehot_cnt <= {rdata_onehot_cnt[2:0], rdata_onehot_cnt[3]};
            end
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    rdata_vld <= 1'b0;
                else
                begin
                    # simulation_delay;
                    
                    if(rdata_vld)
                        rdata_vld <= ~s_axi_rready_w;
                    else if(xip_rev_fifo_ren & (~xip_rev_fifo_empty))
                    begin
                        case(ar_fifo_dout_size)
                            2'b00: // 突发长度1字节
                                rdata_vld <= 1'b1;
                            2'b01: // 突发长度2字节
                                rdata_vld <= rbyte_cnt[0];
                            default: // 突发长度4字节
                                rdata_vld <= rbyte_cnt == 2'b11;
                        endcase
                    end
                end
            end
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    ar_fifo_ren_vld <= 1'b0;
                else
                    # simulation_delay ar_fifo_ren_vld <= ar_fifo_ren & ar_fifo_empty_n;
            end
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    xip_err_reg <= 1'b0;
                else
                begin
                    # simulation_delay;
                    
                    xip_err_reg <= ar_fifo_ren_vld & (ar_fifo_dout_addr != 2'b00);
                end
            end
        end
        else if((en_unaligned_transfer == "true") && (en_narrow_transfer == "false"))
        begin
            // 非对齐传输
            reg read_transmitting; // 读传输进行中(标志)
            reg read_transfer_ready; // 读传输就绪(标志)
            reg read_start; // 读传输开始(脉冲)
            reg[31:0] rdata; // 保存的读数据
            reg rlast; // 保存的last信号
            reg[3:0] rdata_onehot_cnt; // 读数据保存字节使能
            reg rdata_vld; // 读数据有效(标志)
            reg ar_fifo_ren_vld; // 读地址信息fifo有效读(脉冲)
            reg xip_err_reg; // xip错误指示(不支持的窄带传输)
            
            assign ar_fifo_ren = read_transmitting ? (s_axi_rvalid_w & s_axi_rready_w & s_axi_rlast_w):1'b1;
            assign xip_rev_fifo_ren = read_transfer_ready & (~rdata_vld);
            assign s_axi_rdata_w = rdata;
            assign s_axi_rlast_w = rlast;
            assign s_axi_rvalid_w = read_transfer_ready & rdata_vld;
            
            assign xip_err = {burst_type_not_support, 1'b0, xip_err_reg};
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    read_transmitting <= 1'b0;
                else
                begin
                    # simulation_delay;
                    
                    if(read_transmitting)
                        read_transmitting <= (s_axi_rvalid_w & s_axi_rready_w & s_axi_rlast_w) ? ar_fifo_empty_n:1'b1;
                    else
                        read_transmitting <= ar_fifo_empty_n;
                end
            end
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    read_transfer_ready <= 1'b0;
                else
                begin
                    # simulation_delay;
                    
                    if(read_transfer_ready)
                        read_transfer_ready <= ~(s_axi_rvalid_w & s_axi_rready_w & s_axi_rlast_w);
                    else
                        read_transfer_ready <= read_start;
                end
            end
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    read_start <= 1'b0;
                else
                    # simulation_delay read_start <= ar_fifo_ren & ar_fifo_empty_n;
            end
            
            always @(posedge amba_clk)
            begin
                # simulation_delay;
                
                if(~rdata_vld)
                begin
                    if(rdata_onehot_cnt[0])
                        rdata[7:0] <= xip_rev_fifo_dout_data;
                    
                    if(rdata_onehot_cnt[1])
                        rdata[15:8] <= xip_rev_fifo_dout_data;
                    
                    if(rdata_onehot_cnt[2])
                        rdata[23:16] <= xip_rev_fifo_dout_data;
                    
                    if(rdata_onehot_cnt[3])
                        rdata[31:24] <= xip_rev_fifo_dout_data;
                    
                    rlast <= xip_rev_fifo_dout_last;
                end
            end
            
            always @(posedge amba_clk)
            begin
                # simulation_delay;
                
                if(read_start) // 载入
                begin
                    rdata_onehot_cnt[0] <= ar_fifo_dout_addr == 2'b00;
                    rdata_onehot_cnt[1] <= ar_fifo_dout_addr == 2'b01;
                    rdata_onehot_cnt[2] <= ar_fifo_dout_addr == 2'b10;
                    rdata_onehot_cnt[3] <= ar_fifo_dout_addr == 2'b11;
                end
                else if(xip_rev_fifo_ren & (~xip_rev_fifo_empty)) // 循环左移
                    # simulation_delay rdata_onehot_cnt <= {rdata_onehot_cnt[2:0], rdata_onehot_cnt[3]};
            end
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    rdata_vld <= 1'b0;
                else
                begin
                    # simulation_delay;
                    
                    if(rdata_vld)
                        rdata_vld <= ~(s_axi_rready_w);
                    else
                        rdata_vld <= rdata_onehot_cnt[3] & (~xip_rev_fifo_empty);
                end
            end
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    ar_fifo_ren_vld <= 1'b0;
                else
                    # simulation_delay ar_fifo_ren_vld <= ar_fifo_ren & ar_fifo_empty_n;
            end
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    xip_err_reg <= 1'b0;
                else
                begin
                    # simulation_delay;
                    
                    xip_err_reg <= ar_fifo_ren_vld & ar_fifo_dout_size != 2'b10;
                end
            end
        end
        else
        begin
            // 非对齐传输, 窄带传输
            reg read_transmitting; // 读传输进行中(标志)
            reg read_transfer_ready; // 读传输就绪(标志)
            reg read_start; // 读传输开始(脉冲)
            reg[31:0] rdata; // 保存的读数据
            reg rlast; // 保存的last信号
            reg[1:0] rbyte_cnt; // 保存的读数据字节数-1(计数器)
            reg[3:0] rdata_onehot_cnt; // 读数据保存字节使能
            reg rdata_vld; // 读数据有效(标志)
            
            assign ar_fifo_ren = read_transmitting ? (s_axi_rvalid_w & s_axi_rready_w & s_axi_rlast_w):1'b1;
            assign xip_rev_fifo_ren = read_transfer_ready & (~rdata_vld);
            assign s_axi_rdata_w = rdata;
            assign s_axi_rlast_w = rlast;
            assign s_axi_rvalid_w = read_transfer_ready & rdata_vld;
            
            assign xip_err = {burst_type_not_support, 2'b00};
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    read_transmitting <= 1'b0;
                else
                begin
                    # simulation_delay;
                    
                    if(read_transmitting)
                        read_transmitting <= (s_axi_rvalid_w & s_axi_rready_w & s_axi_rlast_w) ? ar_fifo_empty_n:1'b1;
                    else
                        read_transmitting <= ar_fifo_empty_n;
                end
            end
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    read_transfer_ready <= 1'b0;
                else
                begin
                    # simulation_delay;
                    
                    if(read_transfer_ready)
                        read_transfer_ready <= ~(s_axi_rvalid_w & s_axi_rready_w & s_axi_rlast_w);
                    else
                        read_transfer_ready <= read_start;
                end
            end
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    read_start <= 1'b0;
                else
                    # simulation_delay read_start <= ar_fifo_ren & ar_fifo_empty_n;
            end
            
            always @(posedge amba_clk)
            begin
                # simulation_delay;
                
                if(~rdata_vld)
                begin
                    if(rdata_onehot_cnt[0])
                        rdata[7:0] <= xip_rev_fifo_dout_data;
                    
                    if(rdata_onehot_cnt[1])
                        rdata[15:8] <= xip_rev_fifo_dout_data;
                    
                    if(rdata_onehot_cnt[2])
                        rdata[23:16] <= xip_rev_fifo_dout_data;
                    
                    if(rdata_onehot_cnt[3])
                        rdata[31:24] <= xip_rev_fifo_dout_data;
                    
                    rlast <= xip_rev_fifo_dout_last;
                end
            end
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    rbyte_cnt <= 2'b00;
                else if(xip_rev_fifo_ren & (~xip_rev_fifo_empty))
                begin
                    # simulation_delay;
                    
                    if(rdata_onehot_cnt[3])
                        rbyte_cnt <= 2'b00;
                    else
                    begin
                        case(ar_fifo_dout_size)
                            2'b00: // 突发长度1字节
                                rbyte_cnt <= 2'b00;
                            2'b01: // 突发长度2字节
                                rbyte_cnt <= {1'b0, ~rbyte_cnt[0]};
                            default: // 突发长度4字节
                                rbyte_cnt <= rbyte_cnt + 2'b01;
                        endcase
                    end
                end
            end
            
            always @(posedge amba_clk)
            begin
                if(read_start) // 载入
                begin
                    rdata_onehot_cnt[0] <= ar_fifo_dout_addr == 2'b00;
                    rdata_onehot_cnt[1] <= ar_fifo_dout_addr == 2'b01;
                    rdata_onehot_cnt[2] <= ar_fifo_dout_addr == 2'b10;
                    rdata_onehot_cnt[3] <= ar_fifo_dout_addr == 2'b11;
                end
                else if(xip_rev_fifo_ren & (~xip_rev_fifo_empty)) // 循环左移
                    # simulation_delay rdata_onehot_cnt <= {rdata_onehot_cnt[2:0], rdata_onehot_cnt[3]};
            end
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    rdata_vld <= 1'b0;
                else
                begin
                    # simulation_delay;
                    
                    if(rdata_vld)
                        rdata_vld <= ~s_axi_rready_w;
                    else if(xip_rev_fifo_ren & (~xip_rev_fifo_empty))
                    begin
                        if(rdata_onehot_cnt[3])
                            rdata_vld <= 1'b1;
                        else
                        begin
                            case(ar_fifo_dout_size)
                                2'b00: // 突发长度1字节
                                    rdata_vld <= 1'b1;
                                2'b01: // 突发长度2字节
                                    rdata_vld <= rbyte_cnt[0];
                                default: // 突发长度4字节
                                    rdata_vld <= rbyte_cnt == 2'b11;
                            endcase
                        end
                    end
                end
            end
        end
    endgenerate
    
    /** xip接收fifo **/
	wire xip_rev_fifo_afull;
	reg xip_rev_fifo_afull_d;
	reg xip_rev_fifo_afull_d2;
	
	assign xip_rev_fifo_full = xip_rev_fifo_afull_d2;
	
	// 将xip接收fifo将满信号打2拍
	// 跨时钟域: ... -> xip_rev_fifo_afull_d!
	always @(posedge amba_clk or negedge amba_resetn)
	begin
		if(~amba_resetn)
			{xip_rev_fifo_afull_d2, xip_rev_fifo_afull_d} <= 2'b00;
		else
			# simulation_delay {xip_rev_fifo_afull_d2, xip_rev_fifo_afull_d} <= 
				{xip_rev_fifo_afull_d, xip_rev_fifo_afull};
	end
	
	async_fifo_with_ram #(
		.fwft_mode("true"),
		.use_fifo9k("true"),
		.ram_type("bram_9k"),
		.depth(1024),
		.data_width(9),
		.almost_full_th(1024 - 16),
		.simulation_delay(simulation_delay)
	)xip_rev_fifo(
		.clk_wt(spi_clk),
		.rst_n_wt(spi_resetn),
		.clk_rd(amba_clk),
		.rst_n_rd(amba_resetn),
		
		.fifo_wen(xip_rev_fifo_wen),
		.fifo_full(xip_rev_fifo_afull), // 应使用将满信号!!!
		.fifo_din({xip_rev_fifo_din_last, xip_rev_fifo_din_data}),
		
		.fifo_ren(xip_rev_fifo_ren),
		.fifo_empty(xip_rev_fifo_empty),
		.fifo_dout({xip_rev_fifo_dout_last, xip_rev_fifo_dout_data})
	);
    
	/** 可选的AXI读数据通道reg-slice **/
    generate
        if((en_unaligned_transfer == "true") || (en_narrow_transfer == "true"))
        begin
            // AXI读数据通道reg-slice
            axis_reg_slice #(
                .data_width(32),
                .en_ready("true"),
                .forward_registered("true"),
                .back_registered("true"),
                .simulation_delay(simulation_delay)
            )axi_r_reg_slice(
                .clk(amba_clk),
                .rst_n(amba_resetn),
                .s_axis_data(s_axi_rdata_w),
                .s_axis_last(s_axi_rlast_w),
                .s_axis_valid(s_axi_rvalid_w),
                .s_axis_ready(s_axi_rready_w),
                .m_axis_data(s_axi_rdata),
                .m_axis_last(s_axi_rlast),
                .m_axis_valid(s_axi_rvalid),
                .m_axis_ready(s_axi_rready)
            );
        end
        else
        begin
            // pass
            assign s_axi_rdata = s_axi_rdata_w;
            assign s_axi_rlast = s_axi_rlast_w;
            assign s_axi_rvalid = s_axi_rvalid_w;
            assign s_axi_rready_w = s_axi_rready;
        end
    endgenerate
    
    /** 片上执行SPI发送fifo写端口控制器 **/
    spi_xip_ctrler #(
        .spi_type(spi_type),
        .simulation_delay(simulation_delay)
    )spi_xip_ctrler_u(
        .amba_clk(amba_clk),
        .amba_resetn(amba_resetn),
        .s_axis_data_addr(s_axis_data_addr),
        .s_axis_user_len(s_axis_user_len),
        .s_axis_valid(s_axis_valid),
        .s_axis_ready(s_axis_ready),
        .en_xip(en_xip),
        .xip_rev_fifo_full(xip_rev_fifo_full),
        .xip_tx_fifo_wen(xip_tx_fifo_wen),
        .xip_tx_fifo_full(xip_tx_fifo_full),
        .xip_tx_fifo_din(xip_tx_fifo_din),
        .xip_tx_fifo_din_ss(xip_tx_fifo_din_ss),
        .xip_tx_fifo_din_ignored(xip_tx_fifo_din_ignored),
        .xip_tx_fifo_din_last(xip_tx_fifo_din_last),
        .xip_tx_fifo_din_dire(xip_tx_fifo_din_dire),
        .xip_tx_fifo_din_en_mul(xip_tx_fifo_din_en_mul)
    );
    
    /** 支持片上执行的标准SPI控制器 **/
    spi_tx_rx_with_xip #(
        .spi_type(spi_type),
        .spi_sck_div_n(spi_sck_div_n),
        .spi_cpol(spi_cpol),
        .spi_cpha(spi_cpha),
        .simulation_delay(simulation_delay)
    )spi_tx_rx_with_xip_u(
        .spi_clk(spi_clk),
        .spi_resetn(spi_resetn),
		.amba_clk(amba_clk),
		.amba_resetn(amba_resetn),
        .tx_fifo_ren(xip_tx_fifo_ren),
        .tx_fifo_empty(xip_tx_fifo_empty),
        .tx_fifo_dout(xip_tx_fifo_dout),
        .tx_fifo_dout_ss(xip_tx_fifo_dout_ss),
        .tx_fifo_dout_ignored(xip_tx_fifo_dout_ignored),
        .tx_fifo_dout_last(xip_tx_fifo_dout_last),
        .tx_fifo_dout_dire(xip_tx_fifo_dout_dire),
        .tx_fifo_dout_en_mul(xip_tx_fifo_dout_en_mul),
        .rx_fifo_wen(rx_fifo_wen),
        .rx_fifo_full(rx_fifo_full),
        .rx_fifo_din(rx_fifo_din),
        .m_rev_axis_data(xip_rev_fifo_din_data),
        .m_rev_axis_valid(xip_rev_fifo_wen),
        .m_rev_axis_last(xip_rev_fifo_din_last),
        .rx_tx_dire(rx_tx_dire),
        .en_xip(en_xip),
        .rx_tx_start(rx_tx_start),
        .rx_tx_done(rx_tx_done),
        .rx_tx_idle(rx_tx_idle),
        .rx_err(rx_err),
        .spi_ss(spi_ss),
        .spi_sck(spi_sck),
        .spi_io0_t(spi_io0_t),
        .spi_io0_o(spi_io0_o),
        .spi_io0_i(spi_io0_i),
        .spi_io1_t(spi_io1_t),
        .spi_io1_o(spi_io1_o),
        .spi_io1_i(spi_io1_i),
        .spi_io2_t(spi_io2_t),
        .spi_io2_o(spi_io2_o),
        .spi_io2_i(spi_io2_i),
        .spi_io3_t(spi_io3_t),
        .spi_io3_o(spi_io3_o),
        .spi_io3_i(spi_io3_i)
    );
    
endmodule
