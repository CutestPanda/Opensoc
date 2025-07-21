`timescale 1ns / 1ps
/********************************************************************
本模块: AHB-片上执行SPI控制器

描述: 
符合AHB协议的片上执行SPI控制器(可实现Flash的等效片上读)
支持非对齐传输和窄带传输

注意：
AHB接口仅支持读传输

协议:
AHB SLAVE
SPI MASTER
FIFO READ/WRITE

作者: 陈家耀
日期: 2023/12/15
********************************************************************/


module ahb_spi_xip_ctrler #(
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
    
    // AHB从接口(只读)
    input wire s_ahb_hsel,
    input wire[31:0] s_ahb_haddr,
    // 2'b00 -> IDLE; 2'b01 -> BUSY; 2'b10 -> NONSEQ; 2'b11 -> SEQ
    input wire[1:0] s_ahb_htrans,
    // 3'b000 -> SINGLE; 3'b001 -> INCR; 3'b010 -> WRAP4; 3'b011 -> INCR4;
    // 3'b100 -> WRAP8; 3'b101 -> INCR8; 3'b110 -> WRAP16; 3'b111 -> INCR16
    input wire[2:0] s_ahb_hburst, // ignored
    input wire[2:0] s_ahb_hsize,
    input wire[3:0] s_ahb_hprot, // ignored
    input wire s_ahb_hwrite,
    input wire s_ahb_hready,
    input wire[31:0] s_ahb_hwdata, // ignored
    output wire s_ahb_hready_out,
    output wire[31:0] s_ahb_hrdata,
    output wire s_ahb_hresp, // 1'b0 -> OKAY; 1'b1 -> ERROR
    
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

    /** xip接收fifo **/
    // 写端口
    wire xip_rev_fifo_wen;
    wire xip_rev_fifo_full;
	wire xip_rev_fifo_afull;
	reg xip_rev_fifo_afull_d;
	reg xip_rev_fifo_afull_d2;
    wire[7:0] xip_rev_fifo_din_data;
    wire xip_rev_fifo_din_last;
    // 读端口
    wire xip_rev_fifo_ren;
    wire xip_rev_fifo_empty;
    wire[7:0] xip_rev_fifo_dout_data;
    wire xip_rev_fifo_dout_last;
	
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
    
    /** 片上执行SPI发送fifo写端口控制器 **/
    // 读命令AXIS从接口
    wire[23:0] s_axis_rd_cmd_data_addr; // 读flash首地址
    wire[11:0] s_axis_rd_cmd_user_len; // 读flash字节数-1
    wire s_axis_rd_cmd_valid;
    wire s_axis_rd_cmd_ready;
    
    spi_xip_ctrler #(
        .spi_type(spi_type),
        .simulation_delay(simulation_delay)
    )spi_xip_ctrler_u(
        .amba_clk(amba_clk),
        .amba_resetn(amba_resetn),
        .s_axis_data_addr(s_axis_rd_cmd_data_addr),
        .s_axis_user_len(s_axis_rd_cmd_user_len),
        .s_axis_valid(s_axis_rd_cmd_valid),
        .s_axis_ready(s_axis_rd_cmd_ready),
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
    
    /** 支持片上执行的SPI控制器 **/
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
    
    /** 产生读命令 **/
    wire haddr_trans_start; // AHB传输开始(指示)
    reg[23:0] haddr_latched; // 锁存的AHB传输地址
    reg[1:0] hsize_latched; // 锁存的AHB传输字节数
    reg hwrite_latched; // 锁存的AHB读写类型
    reg rd_cmd_valid; // 读命令有效
    
    assign haddr_trans_start = s_ahb_hsel & s_ahb_hready & s_ahb_htrans[1];
    assign s_axis_rd_cmd_data_addr = haddr_latched;
    assign s_axis_rd_cmd_user_len = {10'd0, hsize_latched};
    assign s_axis_rd_cmd_valid = rd_cmd_valid;
    
    // 锁存的AHB传输地址
    always @(posedge amba_clk)
    begin
        if(haddr_trans_start)
            # simulation_delay haddr_latched <= s_ahb_haddr[23:0];
    end
    // 锁存的AHB传输字节数
    // 断言:AHB突发大小只能为1/2/4字节!
    generate
        if(en_unaligned_transfer == "false")
        begin
            always @(posedge amba_clk)
            begin
                if(haddr_trans_start)
                    # simulation_delay hsize_latched <= 
                        (s_ahb_hsize[1:0] == 2'b00) ? 2'b00:
                        (s_ahb_hsize[1:0] == 2'b01) ? 2'b01:
                                                      2'b11;
            end
        end
        else if((en_unaligned_transfer == "true") && (en_narrow_transfer == "false"))
        begin
            always @(posedge amba_clk)
            begin
                if(haddr_trans_start)
                    # simulation_delay hsize_latched <= ~s_ahb_haddr[1:0];
            end
        end
        else // (en_unaligned_transfer == "true") && (en_narrow_transfer == "true")
        begin
            always @(posedge amba_clk)
            begin
                if(haddr_trans_start)
                    # simulation_delay hsize_latched <= 
                        (s_ahb_hsize[1:0] == 2'b00) ? 2'b00:
                        (s_ahb_hsize[1:0] == 2'b01) ? {1'b0, s_ahb_haddr[1:0] != 2'b11}:
                                                      (~s_ahb_haddr[1:0]);
            end
        end
    endgenerate
    // 锁存的AHB读写类型
    always @(posedge amba_clk)
    begin
        if(haddr_trans_start)
            # simulation_delay hwrite_latched <= s_ahb_hwrite;
    end
    
    // 读命令有效
    always @(posedge amba_clk or negedge amba_resetn)
    begin
        if(~amba_resetn)
            rd_cmd_valid <= 1'b0;
        else
            # simulation_delay rd_cmd_valid <= rd_cmd_valid ? (~s_axis_rd_cmd_ready):(haddr_trans_start & (~s_ahb_hwrite));
    end
    
    /** XIP读数据 **/
    reg[3:0] xip_rcnt; // XIP读计数器
    reg[31:0] xip_rdata; // XIP读数据
    reg xip_rdata_valid; // XIP读数据有效
    
    // XIP读计数器
    generate
        if(en_unaligned_transfer == "false")
        begin
            always @(posedge amba_clk)
            begin
                if(haddr_trans_start)
                    # simulation_delay xip_rcnt <= 4'b0001;
                else if(xip_rev_fifo_ren & (~xip_rev_fifo_empty))
                    # simulation_delay xip_rcnt <= {xip_rcnt[2:0], xip_rcnt[3]};
            end
        end
        else // en_unaligned_transfer == "true"
        begin
            always @(posedge amba_clk)
            begin
                if(haddr_trans_start)
                    # simulation_delay xip_rcnt <= 
                        (s_ahb_haddr[1:0] == 2'b00) ? 4'b0001:
                        (s_ahb_haddr[1:0] == 2'b01) ? 4'b0010:
                        (s_ahb_haddr[1:0] == 2'b10) ? 4'b0100:
                                                      4'b1000;
                else if(xip_rev_fifo_ren & (~xip_rev_fifo_empty))
                    # simulation_delay xip_rcnt <= {xip_rcnt[2:0], xip_rcnt[3]};
            end
        end
    endgenerate
    
    // XIP读数据
    always @(posedge amba_clk)
    begin
        if(xip_rev_fifo_ren & (~xip_rev_fifo_empty) & xip_rcnt[0])
            # simulation_delay xip_rdata[7:0] <= xip_rev_fifo_dout_data;
    end
    always @(posedge amba_clk)
    begin
        if(xip_rev_fifo_ren & (~xip_rev_fifo_empty) & xip_rcnt[1])
            # simulation_delay xip_rdata[15:8] <= xip_rev_fifo_dout_data;
    end
    always @(posedge amba_clk)
    begin
        if(xip_rev_fifo_ren & (~xip_rev_fifo_empty) & xip_rcnt[2])
            # simulation_delay xip_rdata[23:16] <= xip_rev_fifo_dout_data;
    end
    always @(posedge amba_clk)
    begin
        if(xip_rev_fifo_ren & (~xip_rev_fifo_empty) & xip_rcnt[3])
            # simulation_delay xip_rdata[31:24] <= xip_rev_fifo_dout_data;
    end
    
    // XIP读数据有效
    always @(posedge amba_clk or negedge amba_resetn)
    begin
        if(~amba_resetn)
            xip_rdata_valid <= 1'b0;
        else
            # simulation_delay xip_rdata_valid <= xip_rev_fifo_ren & (~xip_rev_fifo_empty) & xip_rev_fifo_dout_last;
    end
    
    /** AHB从机返回 **/
    reg ahb_transfering; // AHB传输进行中(标志)
    reg hready_out; // AHB上一次传输完成
    reg[31:0] hrdata; // AHB读数据
    reg hresp; // AHB从机响应
    
    assign s_ahb_hready_out = hready_out;
    assign s_ahb_hrdata = hrdata;
    assign s_ahb_hresp = hresp;
    
    assign xip_rev_fifo_ren = ahb_transfering;
    
    // AHB传输进行中(标志)
    always @(posedge amba_clk or negedge amba_resetn)
    begin
        if(~amba_resetn)
            ahb_transfering <= 1'b0;
        else
            # simulation_delay ahb_transfering <= ahb_transfering ? (~(hwrite_latched | xip_rdata_valid)):haddr_trans_start;
    end
    
    // AHB上一次传输完成
    always @(posedge amba_clk or negedge amba_resetn)
    begin
        if(~amba_resetn)
            hready_out <= 1'b1;
        else
        begin
            if(ahb_transfering)
                # simulation_delay hready_out <= hwrite_latched | xip_rdata_valid;
            else
                # simulation_delay hready_out <= ~haddr_trans_start;
        end
    end
    // AHB读数据
    always @(posedge amba_clk)
    begin
        if(ahb_transfering & (~hwrite_latched) & xip_rdata_valid) // 无需使能也可???
            # simulation_delay hrdata <= xip_rdata;
    end
    // AHB从机响应
    always @(posedge amba_clk or negedge amba_resetn)
    begin
        if(~amba_resetn)
            hresp <= 1'b0;
        else
            # simulation_delay hresp <= (haddr_trans_start & s_ahb_hwrite) | (ahb_transfering & hwrite_latched);
    end
    
    /** xip错误指示 **/
    assign xip_err[2] = 1'b0;
    
    generate
        if(en_unaligned_transfer == "false")
        begin
            reg unaligned_transfer_not_supported; // 不支持的非对齐
            
            assign xip_err[1] = unaligned_transfer_not_supported;
            
            // 不支持的非对齐
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    unaligned_transfer_not_supported <= 1'b0;
                else
                    # simulation_delay unaligned_transfer_not_supported <= haddr_trans_start & (~s_ahb_hwrite) & (s_ahb_haddr[1:0] != 2'b00);
            end
        end
        else
            assign xip_err[1] = 1'b0;
    endgenerate
    
    generate
        if(en_narrow_transfer == "false")
        begin
            reg narrow_transfer_not_supported; // 不支持的窄带传输
            
            assign xip_err[0] = narrow_transfer_not_supported;
            
            // 不支持的窄带传输
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    narrow_transfer_not_supported <= 1'b0;
                else
                    # simulation_delay narrow_transfer_not_supported <= haddr_trans_start & (~s_ahb_hwrite) & (s_ahb_hsize != 3'b010);
            end
        end
        else
            assign xip_err[0] = 1'b0;
    endgenerate
    
endmodule
