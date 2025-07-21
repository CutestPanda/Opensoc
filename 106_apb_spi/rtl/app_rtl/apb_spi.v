`timescale 1ns / 1ps
/********************************************************************
本模块: 符合APB协议的SPI控制器

描述: 
APB-SPI控制器
支持标准/Dual/Quad SPI(标准SPI支持全双工/半双工/单工, Dual/Quad SPI支持全双工/半双工)
SPI事务数据位宽为8bit
支持XIP功能(支持非对齐和窄带传输)
支持SPI收发中断

寄存器->
    偏移量  |    含义                     |   读写特性    |        备注
    0x00    0:发送fifo是否满                    R
            1:发送fifo写使能                    W         发送fifo写使能取写偏移地址0x00时该位为高
            15~8:发送fifo写数据                 W
            16:接收fifo是否空                   R
            17:接收fifo读使能                   W         接收fifo读使能取写偏移地址0x00时该位为高
            31~24:接收fifo读数据                R
    0x04    0:SPI全局中断使能                   W
            8:SPI收发指定字节数中断使能          W
            9:SPI接收FIFO溢出中断使能           W
            16:SPI中断标志                     RWC           请在中断服务函数中清除中断标志
            25~24:SPI中断状态                   R
    0x08    11~0:SPI收发中断字节数阈值          W                       注意要减1
    0x0C    1~0:SPI传输方向                    W      2'b11->收发 2'b10->接收 2'b01->发送 2'b00->保留
                                                                    仅对标准SPI有效
            15~8:SPI从机选择                   W            范围为0~spi_slave_n-1
    0x10    tx_user_data_width-1~0:用户数据    W
            16:当前byte的传输方向              W             1'b0->接收 1'b1->发送
            17:当前byte是否在多端口上传输       W
            24:当前byte结束后SS电平            W
    0x14    0:是否使能XIP                     RW           默认使能, 仅当启用片内执行功能时可用

注意：
1. 标准SPI的传输方向
若需要使用标准SPI的单工模式, 固定好SPI传输方向即可
2. XIP功能
支持AXI或AHB接口
XIP功能的AXI或AHB接口仅支持读传输
XIP功能的AXI接口仅支持INCR传输
3. 用户信号
user信号的时序与ss(片选)信号一致, 每一SPI事务的user信号由发送fifo写数据中的用户数据来指定

协议:
AXI SLAVE
APB SLAVE
SPI MASTER

作者: 陈家耀
日期: 2023/11/17
********************************************************************/


module apb_spi #(
    parameter spi_type = "quad", // SPI接口类型(标准->std 双口->dual 四口->quad)
    parameter xip = "false", // 是否启用片内执行功能
    parameter xip_interface = "ahb", // XIP接口(ahb | axi)
    parameter en_unaligned_transfer = "true", // XIP功能是否启用非对齐传输
    parameter en_narrow_transfer = "true", // XIP功能是否启用窄带传输
    parameter integer spi_slave_n = 1, // SPI从机个数(1~32)
    parameter integer spi_sck_div_n = 2, // SPI时钟分频系数(必须能被2整除, 且>=2)
    parameter integer spi_cpol = 1, // SPI空闲时的电平状态(0->低电平 1->高电平)
    parameter integer spi_cpha = 1, // SPI数据采样沿(0->奇数沿 1->偶数沿)
    parameter integer tx_fifo_depth = 512, // 发送fifo深度(32|64|128|...)
    parameter integer rx_fifo_depth = 1024, // 接收fifo深度(32|64|128|...)
    parameter en_itr = "false", // 是否启用SPI中断
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
    
    // AXI从接口(仅启用XIP功能时下可用, 只读)
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
    output wire[1:0] s_axi_rresp,
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    
    // AHB从接口(仅启用XIP功能时下可用, 只读)
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
    
    // APB从机接口
    input wire[31:0] paddr,
    input wire psel,
    input wire penable,
    input wire pwrite,
    input wire[31:0] pwdata,
    output wire pready_out, // const -> 1'b1
    output wire[31:0] prdata_out,
    output wire pslverr_out, // const -> 1'b0
    
    // SPI主机接口
    // ss
    output wire spi_ss_t, // const -> 1'b0
    output wire[spi_slave_n-1:0] spi_ss_o, // ss
    input wire[spi_slave_n-1:0] spi_ss_i, // ignored
    // sck
    output wire spi_sck_t, // const -> 1'b0
    output wire spi_sck_o, // sck
    input wire spi_sck_i, // ignored
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
    // user(only used when tx_user_data_width > 0)
    output wire[tx_user_data_width-1:0] spi_user,
    
    // 中断信号
    output wire spi_itr,
    
    // XIP错误指示
    output wire[2:0] xip_err // {不支持的突发类型, 不支持的非对齐, 不支持的窄带传输}
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
    
    /* SPI发送和接收fifo */
    wire en_xip; // 使能片内执行
    // xip专用写端口
    wire xip_tx_fifo_wen;
    wire xip_tx_fifo_full;
    wire[7:0] xip_tx_fifo_din;
    wire xip_tx_fifo_din_ss;
    wire xip_tx_fifo_din_ignored;
    wire xip_tx_fifo_din_last;
    wire xip_tx_fifo_din_dire;
    wire xip_tx_fifo_din_en_mul;
    // 发送fifo写端口
    wire tx_fifo_wen;
    wire tx_fifo_full;
    wire[(7 + ((xip == "true") ? ((spi_type != "std") ? 5:3):(tx_user_data_width + ((spi_type != "std") ? 3:1)))):0] tx_fifo_din;
    // 发送fifo读端口
    wire tx_fifo_ren;
    wire tx_fifo_empty;
    wire[7:0] tx_fifo_dout;
    wire tx_fifo_dout_ss;
    wire[tx_user_data_width-1:0] tx_fifo_dout_user;
    wire tx_fifo_dout_dire;
    wire tx_fifo_dout_en_mul;
    wire tx_fifo_dout_ignored_xip;
    wire tx_fifo_dout_last_xip;
    // 接收fifo写端口
    wire rx_fifo_wen;
    wire rx_fifo_full;
    wire[7:0] rx_fifo_din;
    // 接收fifo读端口
    wire rx_fifo_ren;
    wire rx_fifo_empty;
    wire[7:0] rx_fifo_dout;
    
    // 发送fifo
	/*
	跨时钟域:
		tx_fifo/async_fifo_u/rptr_gray_at_r[*] -> tx_fifo/async_fifo_u/rptr_gray_at_w_p2[*]!
		tx_fifo/async_fifo_u/wptr_gray_at_w[*] -> tx_fifo/async_fifo_u/wptr_gray_at_r_p2[*]!
	*/
    generate
        if(xip == "true")
        begin
            wire tx_fifo_wen_w;
            wire tx_fifo_full_w;
            
            assign tx_fifo_wen_w = en_xip ? xip_tx_fifo_wen:tx_fifo_wen;
            assign tx_fifo_full = tx_fifo_full_w;
            assign xip_tx_fifo_full = tx_fifo_full_w;
            
            if(spi_type != "std")
            begin
				async_fifo_with_ram #(
					.fwft_mode("false"),
					.ram_type("bram"),
					.depth(tx_fifo_depth),
					.data_width(13),
					.almost_full_th(),
					.almost_empty_th(),
					.simulation_delay(simulation_delay)
				)tx_fifo(
					.clk_wt(amba_clk),
					.rst_n_wt(amba_resetn),
					.clk_rd(spi_clk),
					.rst_n_rd(spi_resetn),
					
					.fifo_wen(tx_fifo_wen_w),
					.fifo_full(tx_fifo_full_w),
					.fifo_din(tx_fifo_din),
					
					.fifo_ren(tx_fifo_ren),
					.fifo_empty(tx_fifo_empty),
					.fifo_dout({tx_fifo_dout_en_mul, tx_fifo_dout_dire, tx_fifo_dout_ignored_xip, tx_fifo_dout_last_xip, tx_fifo_dout_ss, tx_fifo_dout})
				);
            end
            else
            begin
				async_fifo_with_ram #(
					.fwft_mode("false"),
					.ram_type("bram"),
					.depth(tx_fifo_depth),
					.data_width(11),
					.almost_full_th(),
					.almost_empty_th(),
					.simulation_delay(simulation_delay)
				)tx_fifo(
					.clk_wt(amba_clk),
					.rst_n_wt(amba_resetn),
					.clk_rd(spi_clk),
					.rst_n_rd(spi_resetn),
					
					.fifo_wen(tx_fifo_wen_w),
					.fifo_full(tx_fifo_full_w),
					.fifo_din(tx_fifo_din),
					
					.fifo_ren(tx_fifo_ren),
					.fifo_empty(tx_fifo_empty),
					.fifo_dout({tx_fifo_dout_ignored_xip, tx_fifo_dout_last_xip, tx_fifo_dout_ss, tx_fifo_dout})
				);
            end
        end
        else
        begin
            if(tx_user_data_width == 0)
            begin
                if(spi_type != "std")
                begin
					async_fifo_with_ram #(
						.fwft_mode("false"),
						.ram_type("bram"),
						.depth(tx_fifo_depth),
						.data_width(11),
						.almost_full_th(),
						.almost_empty_th(),
						.simulation_delay(simulation_delay)
					)tx_fifo(
						.clk_wt(amba_clk),
						.rst_n_wt(amba_resetn),
						.clk_rd(spi_clk),
						.rst_n_rd(spi_resetn),
						
						.fifo_wen(tx_fifo_wen),
						.fifo_full(tx_fifo_full),
						.fifo_din(tx_fifo_din),
						
						.fifo_ren(tx_fifo_ren),
						.fifo_empty(tx_fifo_empty),
						.fifo_dout({tx_fifo_dout_en_mul, tx_fifo_dout_dire, tx_fifo_dout_ss, tx_fifo_dout})
					);
                end
                else
                begin
					async_fifo_with_ram #(
						.fwft_mode("false"),
						.ram_type("bram"),
						.depth(tx_fifo_depth),
						.data_width(9),
						.almost_full_th(),
						.almost_empty_th(),
						.simulation_delay(simulation_delay)
					)tx_fifo(
						.clk_wt(amba_clk),
						.rst_n_wt(amba_resetn),
						.clk_rd(spi_clk),
						.rst_n_rd(spi_resetn),
						
						.fifo_wen(tx_fifo_wen),
						.fifo_full(tx_fifo_full),
						.fifo_din(tx_fifo_din),
						
						.fifo_ren(tx_fifo_ren),
						.fifo_empty(tx_fifo_empty),
						.fifo_dout({tx_fifo_dout_ss, tx_fifo_dout})
					);
                end
            end
            else
            begin
                if(spi_type != "std")
                begin
					async_fifo_with_ram #(
						.fwft_mode("false"),
						.ram_type("bram"),
						.depth(tx_fifo_depth),
						.data_width(11 + tx_user_data_width),
						.almost_full_th(),
						.almost_empty_th(),
						.simulation_delay(simulation_delay)
					)tx_fifo(
						.clk_wt(amba_clk),
						.rst_n_wt(amba_resetn),
						.clk_rd(spi_clk),
						.rst_n_rd(spi_resetn),
						
						.fifo_wen(tx_fifo_wen),
						.fifo_full(tx_fifo_full),
						.fifo_din(tx_fifo_din),
						
						.fifo_ren(tx_fifo_ren),
						.fifo_empty(tx_fifo_empty),
						.fifo_dout({tx_fifo_dout_en_mul, tx_fifo_dout_dire, tx_fifo_dout_user, tx_fifo_dout_ss, tx_fifo_dout})
					);
                end
                else
                begin
					async_fifo_with_ram #(
						.fwft_mode("false"),
						.ram_type("bram"),
						.depth(tx_fifo_depth),
						.data_width(9 + tx_user_data_width),
						.almost_full_th(),
						.almost_empty_th(),
						.simulation_delay(simulation_delay)
					)tx_fifo(
						.clk_wt(amba_clk),
						.rst_n_wt(amba_resetn),
						.clk_rd(spi_clk),
						.rst_n_rd(spi_resetn),
						
						.fifo_wen(tx_fifo_wen),
						.fifo_full(tx_fifo_full),
						.fifo_din(tx_fifo_din),
						
						.fifo_ren(tx_fifo_ren),
						.fifo_empty(tx_fifo_empty),
						.fifo_dout({tx_fifo_dout_user, tx_fifo_dout_ss, tx_fifo_dout})
					);
                end
            end
        end
    endgenerate
    
    // 接收fifo
	/*
	跨时钟域:
		rx_fifo/async_fifo_u/rptr_gray_at_r[*] -> rx_fifo/async_fifo_u/rptr_gray_at_w_p2[*]!
		rx_fifo/async_fifo_u/wptr_gray_at_w[*] -> rx_fifo/async_fifo_u/wptr_gray_at_r_p2[*]!
	*/
	async_fifo_with_ram #(
		.fwft_mode("false"),
		.ram_type("bram"),
		.depth(rx_fifo_depth),
		.data_width(8),
		.almost_full_th(),
		.almost_empty_th(),
		.simulation_delay(simulation_delay)
	)rx_fifo(
		.clk_wt(spi_clk),
		.rst_n_wt(spi_resetn),
		.clk_rd(amba_clk),
		.rst_n_rd(amba_resetn),
		
		.fifo_wen(rx_fifo_wen),
		.fifo_full(rx_fifo_full),
		.fifo_din(rx_fifo_din),
		
		.fifo_ren(rx_fifo_ren),
		.fifo_empty(rx_fifo_empty),
		.fifo_dout(rx_fifo_dout)
	);
	
    /** SPI控制器 **/
    // 控制器收发指示
    wire[clogb2(spi_slave_n-1):0] rx_tx_sel; // 从机选择
    wire[1:0] rx_tx_dire; // 传输方向(2'b11->收发 2'b10->接收 2'b01->发送 2'b00->保留)
    wire rx_tx_done;
    wire rx_err; // 接收溢出指示
    // SPI主机接口
    wire[spi_slave_n-1:0] spi_ss;
    wire spi_sck;
    
    // ss(仅输出)
    assign spi_ss_t = 1'b0;
    assign spi_ss_o = spi_ss;
    // sck(仅输出)
    assign spi_sck_t = 1'b0;
    assign spi_sck_o = spi_sck;
    
    generate
        if(xip == "true")
        begin
            // 片上执行SPI控制器
            if(xip_interface == "axi")
            begin
                assign s_ahb_hready_out = 1'b1;
                assign s_ahb_hrdata = 32'dx;
                assign s_ahb_hresp = 1'b1;
                
                axi_spi_xip_ctrler #(
                    .spi_type(spi_type),
                    .spi_sck_div_n(spi_sck_div_n),
                    .spi_cpol(spi_cpol),
                    .spi_cpha(spi_cpha),
                    .en_unaligned_transfer(en_unaligned_transfer),
                    .en_narrow_transfer(en_narrow_transfer),
                    .simulation_delay(simulation_delay)
                )axi_spi_xip_ctrler_u(
                    .spi_clk(spi_clk),
                    .spi_resetn(spi_resetn),
					.amba_clk(amba_clk),
					.amba_resetn(amba_resetn),
                    .s_axi_araddr(s_axi_araddr),
                    .s_axi_arburst(s_axi_arburst),
                    .s_axi_arcache(s_axi_arcache),
                    .s_axi_arlen(s_axi_arlen),
                    .s_axi_arprot(s_axi_arprot),
                    .s_axi_arsize(s_axi_arsize),
                    .s_axi_arvalid(s_axi_arvalid),
                    .s_axi_arready(s_axi_arready),
                    .s_axi_rdata(s_axi_rdata),
                    .s_axi_rlast(s_axi_rlast),
                    .s_axi_rresp(s_axi_rresp),
                    .s_axi_rvalid(s_axi_rvalid),
                    .s_axi_rready(s_axi_rready),
                    .rx_tx_dire(rx_tx_dire),
                    .en_xip(en_xip),
                    .rx_tx_start(),
                    .rx_tx_done(rx_tx_done),
                    .rx_tx_idle(),
                    .rx_err(rx_err),
                    .xip_tx_fifo_wen(xip_tx_fifo_wen),
                    .xip_tx_fifo_full(xip_tx_fifo_full),
                    .xip_tx_fifo_din(xip_tx_fifo_din),
                    .xip_tx_fifo_din_ss(xip_tx_fifo_din_ss),
                    .xip_tx_fifo_din_ignored(xip_tx_fifo_din_ignored),
                    .xip_tx_fifo_din_last(xip_tx_fifo_din_last),
                    .xip_tx_fifo_din_dire(xip_tx_fifo_din_dire),
                    .xip_tx_fifo_din_en_mul(xip_tx_fifo_din_en_mul),
                    .xip_tx_fifo_ren(tx_fifo_ren),
                    .xip_tx_fifo_empty(tx_fifo_empty),
                    .xip_tx_fifo_dout(tx_fifo_dout),
                    .xip_tx_fifo_dout_ss(tx_fifo_dout_ss),
                    .xip_tx_fifo_dout_ignored(tx_fifo_dout_ignored_xip),
                    .xip_tx_fifo_dout_last(tx_fifo_dout_last_xip),
                    .xip_tx_fifo_dout_dire(tx_fifo_dout_dire),
                    .xip_tx_fifo_dout_en_mul(tx_fifo_dout_en_mul),
                    .rx_fifo_wen(rx_fifo_wen),
                    .rx_fifo_full(rx_fifo_full),
                    .rx_fifo_din(rx_fifo_din),
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
                    .spi_io3_i(spi_io3_i),
                    .xip_err(xip_err)
                );
            end
            else
            begin
                assign s_axi_arready = 1'b1;
                assign s_axi_rdata = 32'dx;
                assign s_axi_rlast = 1'b1;
                assign s_axi_rresp = 2'b10;
                assign s_axi_rvalid = 1'b1;
                
                ahb_spi_xip_ctrler #(
                    .spi_type(spi_type),
                    .spi_sck_div_n(spi_sck_div_n),
                    .spi_cpol(spi_cpol),
                    .spi_cpha(spi_cpha),
                    .en_unaligned_transfer(en_unaligned_transfer),
                    .en_narrow_transfer(en_narrow_transfer),
                    .simulation_delay(simulation_delay)
                )ahb_spi_xip_ctrler_u(
                    .spi_clk(spi_clk),
                    .spi_resetn(spi_resetn),
					.amba_clk(amba_clk),
					.amba_resetn(amba_resetn),
                    .s_ahb_hsel(s_ahb_hsel),
                    .s_ahb_haddr(s_ahb_haddr),
                    .s_ahb_htrans(s_ahb_htrans),
                    .s_ahb_hburst(s_ahb_hburst),
                    .s_ahb_hsize(s_ahb_hsize),
                    .s_ahb_hprot(s_ahb_hprot),
                    .s_ahb_hwrite(s_ahb_hwrite),
                    .s_ahb_hready(s_ahb_hready),
                    .s_ahb_hwdata(s_ahb_hwdata),
                    .s_ahb_hready_out(s_ahb_hready_out),
                    .s_ahb_hrdata(s_ahb_hrdata),
                    .s_ahb_hresp(s_ahb_hresp),
                    .rx_tx_dire(rx_tx_dire),
                    .en_xip(en_xip),
                    .rx_tx_start(),
                    .rx_tx_done(rx_tx_done),
                    .rx_tx_idle(),
                    .rx_err(rx_err),
                    .xip_tx_fifo_wen(xip_tx_fifo_wen),
                    .xip_tx_fifo_full(xip_tx_fifo_full),
                    .xip_tx_fifo_din(xip_tx_fifo_din),
                    .xip_tx_fifo_din_ss(xip_tx_fifo_din_ss),
                    .xip_tx_fifo_din_ignored(xip_tx_fifo_din_ignored),
                    .xip_tx_fifo_din_last(xip_tx_fifo_din_last),
                    .xip_tx_fifo_din_dire(xip_tx_fifo_din_dire),
                    .xip_tx_fifo_din_en_mul(xip_tx_fifo_din_en_mul),
                    .xip_tx_fifo_ren(tx_fifo_ren),
                    .xip_tx_fifo_empty(tx_fifo_empty),
                    .xip_tx_fifo_dout(tx_fifo_dout),
                    .xip_tx_fifo_dout_ss(tx_fifo_dout_ss),
                    .xip_tx_fifo_dout_ignored(tx_fifo_dout_ignored_xip),
                    .xip_tx_fifo_dout_last(tx_fifo_dout_last_xip),
                    .xip_tx_fifo_dout_dire(tx_fifo_dout_dire),
                    .xip_tx_fifo_dout_en_mul(tx_fifo_dout_en_mul),
                    .rx_fifo_wen(rx_fifo_wen),
                    .rx_fifo_full(rx_fifo_full),
                    .rx_fifo_din(rx_fifo_din),
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
                    .spi_io3_i(spi_io3_i),
                    .xip_err(xip_err)
                );
            end
        end
        else
        begin
            if(spi_type == "std")
            begin
                assign spi_io0_t = 1'b0;
                assign spi_io1_t = 1'b1;
                assign spi_io1_o = 1'bx;
                
                assign spi_io2_t = 1'b1;
                assign spi_io2_o = 1'bx;
                assign spi_io3_t = 1'b1;
                assign spi_io3_o = 1'bx;
                
                // 标准SPI控制器
                std_spi_tx_rx #(
                    .spi_slave_n(spi_slave_n),
                    .spi_sck_div_n(spi_sck_div_n),
                    .spi_cpol(spi_cpol),
                    .spi_cpha(spi_cpha),
                    .tx_user_data_width(tx_user_data_width),
                    .tx_user_default_v(tx_user_default_v),
                    .simulation_delay(simulation_delay)
                )spi_tx_rx_ctrler(
                    .spi_clk(spi_clk),
                    .spi_resetn(spi_resetn),
					.amba_clk(amba_clk),
					.amba_resetn(amba_resetn),
                    .tx_fifo_ren(tx_fifo_ren),
                    .tx_fifo_empty(tx_fifo_empty),
                    .tx_fifo_dout(tx_fifo_dout),
                    .tx_fifo_dout_ss(tx_fifo_dout_ss),
                    .tx_fifo_dout_user(tx_fifo_dout_user),
                    .rx_fifo_wen(rx_fifo_wen),
                    .rx_fifo_full(rx_fifo_full),
                    .rx_fifo_din(rx_fifo_din),
                    .rx_tx_sel(rx_tx_sel),
                    .rx_tx_dire(rx_tx_dire),
                    .rx_tx_start(),
                    .rx_tx_done(rx_tx_done),
                    .rx_tx_idle(),
                    .rx_err(rx_err),
                    .spi_ss(spi_ss),
                    .spi_sck(spi_sck),
                    .spi_mosi(spi_io0_o),
                    .spi_miso(spi_io1_i),
                    .spi_user(spi_user)
                );
            end
            else
            begin
                // 双口/四口SPI控制器
                dual_quad_spi_tx_rx #(
                    .spi_type(spi_type),
                    .spi_slave_n(spi_slave_n),
                    .spi_sck_div_n(spi_sck_div_n),
                    .spi_cpol(spi_cpol),
                    .spi_cpha(spi_cpha),
                    .tx_user_data_width(tx_user_data_width),
                    .tx_user_default_v(tx_user_default_v),
                    .simulation_delay(simulation_delay)
                )spi_tx_rx_ctrler(
                    .spi_clk(spi_clk),
                    .spi_resetn(spi_resetn),
					.amba_clk(amba_clk),
					.amba_resetn(amba_resetn),
                    .tx_fifo_ren(tx_fifo_ren),
                    .tx_fifo_empty(tx_fifo_empty),
                    .tx_fifo_dout(tx_fifo_dout),
                    .tx_fifo_dout_user(tx_fifo_dout_user),
                    .tx_fifo_dout_dire(tx_fifo_dout_dire),
                    .tx_fifo_dout_en_mul(tx_fifo_dout_en_mul),
                    .rx_fifo_wen(rx_fifo_wen),
                    .rx_fifo_full(rx_fifo_full),
                    .rx_fifo_din(rx_fifo_din),
                    .rx_tx_sel(rx_tx_sel),
                    .rx_tx_start(),
                    .rx_tx_done(rx_tx_done),
                    .rx_tx_idle(),
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
                    .spi_io3_i(spi_io3_i),
                    .spi_user(spi_user)
                );
            end
        end
    endgenerate
    
    /** SPI中断 **/
    wire spi_org_itr_pulse; // 原始的SPI中断(脉冲)
    reg spi_rx_bytes_n_itr_pulse; // 原始的SPI收发指定字节数中断(脉冲)
    reg spi_rx_err_itr_pulse; // 原始的SPI接收FIFO溢出中断(脉冲)
    wire[1:0] spi_itr_status; // SPI中断状态(SPI接收FIFO溢出中断, SPI收发指定字节数中断)
    wire spi_global_itr_en; // SPI全局中断(使能)
    wire[1:0] spi_itr_en; // SPI中断(使能)(SPI接收FIFO溢出中断, SPI收发指定字节数中断)
    wire spi_itr_flag; // SPI中断(标志)
    wire[11:0] spi_rx_bytes_n_itr_th; // SPI收发中断字节数(阈值)
    
    generate
        if(en_itr == "true")
        begin // 启用中断
            assign spi_org_itr_pulse = (spi_rx_err_itr_pulse | spi_rx_bytes_n_itr_pulse) & (~spi_itr_flag);
            assign spi_itr_status = {spi_rx_err_itr_pulse, spi_rx_bytes_n_itr_pulse};
            
            // SPI收发指定字节数中断
            reg[11:0] now_tx_rx_bytes_finished_cnt; // 当前已收发字节数(计数器)
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    now_tx_rx_bytes_finished_cnt <= 12'd0;
                else if((~spi_itr_en[0]) | (~spi_global_itr_en))
                    now_tx_rx_bytes_finished_cnt <= # simulation_delay 12'd0;
                else if(rx_tx_done)
                    now_tx_rx_bytes_finished_cnt <= # simulation_delay 
						(now_tx_rx_bytes_finished_cnt == spi_rx_bytes_n_itr_th) ? 
							12'd0:
							(now_tx_rx_bytes_finished_cnt + 12'd1);
            end
            
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    spi_rx_bytes_n_itr_pulse <= 1'b0;
                else if((~spi_itr_en[0]) | (~spi_global_itr_en))
                    spi_rx_bytes_n_itr_pulse <= # simulation_delay 1'b0;
                else
                    spi_rx_bytes_n_itr_pulse <= # simulation_delay 
						rx_tx_done & (now_tx_rx_bytes_finished_cnt == spi_rx_bytes_n_itr_th);
            end
            
            // SPI接收FIFO溢出中断
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    spi_rx_err_itr_pulse <= 1'b0;
                else if((~spi_itr_en[1]) | (~spi_global_itr_en))
                    spi_rx_err_itr_pulse <= # simulation_delay 1'b0;
                else
                    spi_rx_err_itr_pulse <= # simulation_delay rx_err;
            end
            
            // 中断发生器
            itr_generator #(
                .pulse_w(10),
                .simulation_delay(simulation_delay)
            )itr_generator_u(
                .clk(amba_clk),
                .rst_n(amba_resetn),
                .itr_org(spi_org_itr_pulse),
                .itr(spi_itr)
            );
        end
        else // 不启用中断
        begin
            assign spi_itr = 1'b0;
            
            assign spi_org_itr_pulse = 1'b0;
            assign spi_itr_status = 2'b00;
        end
    endgenerate
    
    /*
    寄存器区->
    偏移量  |    含义                     |   读写特性    |        备注
    0x00    0:发送fifo是否满                    R
            1:发送fifo写使能                    W         发送fifo写使能取写偏移地址0x00时该位为高
            15~8:发送fifo写数据                 W
            16:接收fifo是否空                   R
            17:接收fifo读使能                   W         接收fifo读使能取写偏移地址0x00时该位为高
            31~24:接收fifo读数据                R
    0x04    0:SPI全局中断使能                   W
            8:SPI收发指定字节数中断使能          W
            9:SPI接收FIFO溢出中断使能           W
            16:SPI中断标志                     RWC           请在中断服务函数中清除中断标志
            25~24:SPI中断状态                   R
    0x08    11~0:SPI收发中断字节数阈值          W                       注意要减1
    0x0A    1~0:SPI传输方向                    W      2'b11->收发 2'b10->接收 2'b01->发送 2'b00->保留
            15~8:SPI从机选择                   W            范围为0~spi_slave_n-1
    0x10    tx_user_data_width-1~0:用户数据    W
            16:当前byte的传输方向              W             1'b0->接收 1'b1->发送
            17:当前byte是否在多端口上传输       W
            24:当前byte结束后SS电平            W
    0x14    0:是否使能XIP                     RW              仅当启用片内执行功能时可用
    */
	/*
	跨时钟域: spi_trans_params[15:8] -> ...!
		      spi_trans_params[1:0] -> ...!
			  spi_xip[0] -> ...!
	*/
    reg[31:0] spi_fifo_cs;
    reg[31:0] spi_itr_status_en;
    reg[31:0] spi_tx_rx_itr_th;
    reg[31:0] spi_trans_params;
    reg[31:0] spi_user_r;
    reg[31:0] spi_xip;
    
    assign spi_global_itr_en = spi_itr_status_en[0];
    assign spi_itr_en = spi_itr_status_en[9:8];
    assign spi_itr_flag = spi_itr_status_en[16];
    assign spi_rx_bytes_n_itr_th = spi_tx_rx_itr_th[11:0];
    assign rx_tx_dire = spi_trans_params[1:0];
    assign en_xip = spi_xip[0];
    assign rx_tx_sel = spi_trans_params[15:8];
    
    // APB写寄存器
    always @(posedge amba_clk or negedge amba_resetn)
    begin
        if(~amba_resetn)
        begin
            {spi_fifo_cs[17], spi_fifo_cs[15:8], spi_fifo_cs[1]} <= 10'd0;
            {spi_itr_status_en[16], spi_itr_status_en[9:8], spi_itr_status_en[0]} <= 4'd0;
            spi_tx_rx_itr_th[11:0] <= 12'd0;
            {spi_trans_params[15:8], spi_trans_params[1:0]} <= {8'd0, 2'b11};
            
            if((xip == "false") && (tx_user_data_width > 0))
                spi_user_r[tx_user_data_width-1:0] <= tx_user_default_v;
            if(spi_type != "std")
                spi_user_r[17:16] <= 2'b00;
            
            spi_user_r[24] <= 1'b0;
            
            spi_xip[0] <= 1'b1;
        end
        else if(psel & pwrite & penable) // 写寄存器区
        begin
            case(paddr[4:2])
                3'd0: {spi_fifo_cs[17], spi_fifo_cs[15:8], spi_fifo_cs[1]} <= # simulation_delay 
					{pwdata[17], pwdata[15:8], pwdata[1]};
                3'd1: {spi_itr_status_en[16], spi_itr_status_en[9:8], spi_itr_status_en[0]} <= # simulation_delay 
					{1'b0, pwdata[9:8], pwdata[0]};
                3'd2: spi_tx_rx_itr_th[11:0] <= # simulation_delay pwdata[11:0];
                3'd3: {spi_trans_params[15:8], spi_trans_params[1:0]} <= # simulation_delay {pwdata[15:8], pwdata[1:0]};
                3'd4:
                begin
                    if((xip == "false") && (tx_user_data_width > 0))
                        spi_user_r[tx_user_data_width-1:0] <= # simulation_delay pwdata[tx_user_data_width-1:0];
                    if(spi_type != "std")
                        spi_user_r[17:16] <= # simulation_delay pwdata[17:16];
                    
                    spi_user_r[24] <= # simulation_delay pwdata[24];
                end
                3'd5: spi_xip[0] <= # simulation_delay pwdata[0];
            endcase
        end
        else
        begin
            // 中断标志
            if(~spi_itr_status_en[16])
                spi_itr_status_en[16] <= # simulation_delay spi_org_itr_pulse;
        end
    end
    
    // 中断状态
    always @(posedge amba_clk)
    begin
        if(spi_org_itr_pulse)
            spi_itr_status_en[25:24] <= # simulation_delay spi_itr_status;
    end
    
    // APB读寄存器
    reg[31:0] prdata_out_regs;
    
    always @(posedge amba_clk)
    begin
        if(psel & (~pwrite))
        begin
            case(paddr[4:2])
                3'd0:
                begin
                    {prdata_out_regs[7:1], prdata_out_regs[0]} <= # simulation_delay {7'd0, tx_fifo_full}; // 发送fifo是否满
                    prdata_out_regs[15:8] <= # simulation_delay 8'd0;
                    {prdata_out_regs[23:17], prdata_out_regs[16]} <= # simulation_delay {7'd0, rx_fifo_empty}; // 接收fifo是否空
                    prdata_out_regs[31:24] <= # simulation_delay rx_fifo_dout; // 接收fifo读数据
                end
                3'd1:
                begin
                    prdata_out_regs[7:0] <= # simulation_delay 8'd0;
                    prdata_out_regs[15:8] <= # simulation_delay 8'd0;
                    prdata_out_regs[23:16] <= # simulation_delay {7'd0, spi_itr_status_en[16]}; // 中断标志
                    prdata_out_regs[31:24] <= # simulation_delay {6'd0, spi_itr_status_en[25:24]}; // 中断掩码
                end
				3'd5:
				begin
					{prdata_out_regs[7:1], prdata_out_regs[0]} <= # simulation_delay 
						{7'd0, (xip == "true") & spi_xip[0]}; // 是否使能XIP
					prdata_out_regs[15:8] <= # simulation_delay 8'd0;
					prdata_out_regs[23:16] <= # simulation_delay 8'd0;
					prdata_out_regs[31:24] <= # simulation_delay 8'd0;
				end
                default: prdata_out_regs <= # simulation_delay 32'd0;
            endcase
        end
    end
    
    /** APB从机接口 **/
    assign pready_out = 1'b1;
    assign prdata_out = prdata_out_regs;
    assign pslverr_out = 1'b0;
    
    /** 写发送fifo或读接收fifo **/
	reg tx_fifo_wen_reg;
    reg apb_rx_fifo_ren; // 延迟1clk的APB总线读接收fifo事务(标志)
    
    assign rx_fifo_ren = penable & apb_rx_fifo_ren;
    assign tx_fifo_wen = tx_fifo_wen_reg;
	
    generate
        if(xip == "true")
        begin
            if(spi_type == "std")
                // ignored, last, ss, din
                assign tx_fifo_din = {xip_tx_fifo_din_ignored, xip_tx_fifo_din_last, en_xip ? xip_tx_fifo_din_ss:spi_user_r[24], en_xip ? xip_tx_fifo_din:spi_fifo_cs[15:8]};
            else
                // en_mul, dire, ignored, last, ss, din
                assign tx_fifo_din = {en_xip ? {xip_tx_fifo_din_en_mul, xip_tx_fifo_din_dire}:spi_user_r[17:16], xip_tx_fifo_din_ignored, 
                    xip_tx_fifo_din_last, en_xip ? xip_tx_fifo_din_ss:spi_user_r[24], en_xip ? xip_tx_fifo_din:spi_fifo_cs[15:8]};
        end
        else
        begin
            if(tx_user_data_width == 0)
            begin
                if(spi_type == "std")
                    assign tx_fifo_din = {spi_user_r[24], spi_fifo_cs[15:8]}; // ss, din
                else
                    assign tx_fifo_din = {spi_user_r[17:16], spi_user_r[24], spi_fifo_cs[15:8]}; // en_mul, dire, ss, din
            end
            else
                if(spi_type == "std")
                    assign tx_fifo_din = {spi_user_r[tx_user_data_width-1:0], spi_user_r[24], spi_fifo_cs[15:8]}; // user, ss, din
                else
                    assign tx_fifo_din = {spi_user_r[17:16], spi_user_r[tx_user_data_width-1:0], spi_user_r[24], spi_fifo_cs[15:8]}; // en_mul, dire, user, ss, din
        end
    endgenerate
    
    // 发送fifo写使能, 延迟1clk的APB总线读接收fifo事务(标志)
    always @(posedge amba_clk or negedge amba_resetn)
    begin
        if(~amba_resetn)
        begin
            tx_fifo_wen_reg <= 1'b0;
            apb_rx_fifo_ren <= 1'b0;
        end
        else
        begin
            tx_fifo_wen_reg <= # simulation_delay psel & pwrite & penable & (paddr[4:2] == 3'd0) & pwdata[1];
            apb_rx_fifo_ren <= # simulation_delay psel & pwrite & (paddr[4:2] == 3'd0) & pwdata[17];
        end
    end
	
endmodule
