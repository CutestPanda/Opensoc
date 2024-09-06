`timescale 1ns / 1ps
/********************************************************************
本模块: AHB-FSMC

描述:
带AHB-Lite从接口的FSMC控制器

突发大小固定为16位

偏移量0x000_0000~0x000_0FFF:
	子偏移量0x00 -> 7~0:   地址建立周期数 - 1
					15~8:  数据建立周期数 - 1
	子偏移量0x02 -> 7~0:   数据保持周期数 - 1
偏移量0x000_1000~0x3FF_FFFF:
	子偏移量0x000_0000~0x3FF_EFFF -> FSMC

注意：
不支持非对齐传输

协议:
AHB SLAVE
FSMC MASTER

作者: 陈家耀
日期: 2024/07/18
********************************************************************/


module ahb_fsmc #(
	parameter real simulation_delay = 0 // 仿真延时
)(
	// 时钟和复位
    input wire hclk,
    input wire hresetn,
    
    // AHB-Lite SLAVE
    input wire[31:0] s_ahb_haddr,
    input wire[2:0] s_ahb_hburst, // ignored(assumed to be 3'b000, i.e. SINGLE)
    input wire[3:0] s_ahb_hprot, // ignored
    output wire[31:0] s_ahb_hrdata,
    input wire s_ahb_hready_in,
    output wire s_ahb_hready_out,
    output wire s_ahb_hresp, // const -> 1'b0
    input wire[2:0] s_ahb_hsize, // ignored(assumed to be 3'b001)
    input wire[1:0] s_ahb_htrans, // only 2'b00(IDLE) and 2'b10(NONSEQ) are supported
    input wire[31:0] s_ahb_hwdata,
    input wire[3:0] s_ahb_hwstrb,
    input wire s_ahb_hwrite,
    input wire s_ahb_hsel,
	
	// FSMC MASTER
	output wire[1:0] fsmc_nbl, // 数据掩码
	output wire[25:0] fsmc_addr, // 地址线
	output wire fsmc_nwe, // 写入使能
	output wire fsmc_noe, // 输出使能(读使能)
	output wire fsmc_ne, // 片选信号
	// 数据线(1'b1 -> 输入, 1'b0 -> 输出)
	input wire[15:0] fsmc_data_i,
	output wire[15:0] fsmc_data_o,
	output wire[15:0] fsmc_data_t
);

	/** FSMC控制器 **/
    // AHB传输开始指示
    wire ahb_trans_start;
	// 运行时参数
	reg to_upd_rt_pars_0; // 更新第0组运行时参数(指示)
	reg to_upd_rt_pars_1; // 更新第1组运行时参数(指示)
	reg[7:0] addr_set; // 地址建立周期数 - 1
	reg[7:0] data_set; // 数据建立周期数 - 1
	reg[7:0] data_hold; // 数据保持周期数 - 1
	// 流程控制
	reg fsmc_ctrler_start;
	wire fsmc_ctrler_done;
	// 传输参数
	wire[15:0] wdata; // 写数据
	wire[1:0] data_mask; // 字节使能掩码
	wire[25:0] trans_addr; // 传输地址
	wire is_rd; // 是否读传输
	// 读数据输出
	wire[15:0] m_axis_rd_data;
	wire m_axis_rd_valid;
    
    assign ahb_trans_start = s_ahb_hready_in & s_ahb_htrans[1] & s_ahb_hsel;
	
	// 更新第0组运行时参数(指示)
	always @(posedge hclk or negedge hresetn)
	begin
		if(~hresetn)
			to_upd_rt_pars_0 <= 1'b0;
		else
			# simulation_delay to_upd_rt_pars_0 <= ahb_trans_start & (s_ahb_haddr[25:12] == 14'd0) & (~s_ahb_haddr[1]);
	end
	// 更新第1组运行时参数(指示)
	always @(posedge hclk or negedge hresetn)
	begin
		if(~hresetn)
			to_upd_rt_pars_1 <= 1'b0;
		else
			# simulation_delay to_upd_rt_pars_1 <= ahb_trans_start & (s_ahb_haddr[25:12] == 14'd0) & s_ahb_haddr[1];
	end
	
	// 控制器运行时参数
	always @(posedge hclk)
	begin
		if(to_upd_rt_pars_0)
			# simulation_delay {data_set, addr_set} <= s_ahb_hwdata[15:0];
	end
	always @(posedge hclk)
	begin
		if(to_upd_rt_pars_1)
			# simulation_delay data_hold <= s_ahb_hwdata[23:16];
	end
	
	fsmc_ctrler #(
		.simulation_delay(simulation_delay)
	)fsmc_ctrler_u(
		.clk(hclk),
		.rst_n(hresetn),
		
		.ctrler_start(fsmc_ctrler_start),
		.ctrler_idle(),
		.ctrler_done(fsmc_ctrler_done),
		
		.addr_set(addr_set),
		.data_set(data_set),
		.data_hold(data_hold),
		
		.wdata(wdata),
		.data_mask(data_mask),
		.trans_addr(trans_addr),
		.is_rd(is_rd),
		
		.m_axis_rd_data(m_axis_rd_data),
		.m_axis_rd_valid(m_axis_rd_valid),
		
		.fsmc_nbl(fsmc_nbl),
		.fsmc_addr(fsmc_addr),
		.fsmc_nwe(fsmc_nwe),
		.fsmc_noe(fsmc_noe),
		.fsmc_ne(fsmc_ne),
		.fsmc_data_i(fsmc_data_i),
		.fsmc_data_o(fsmc_data_o),
		.fsmc_data_t(fsmc_data_t)
	);
	
	/** AHB从接口 **/
	reg[31:0] haddr_latched; // 锁存的AHB传输地址
	reg hwrite_latched; // 锁存的AHB传输读写类型
	reg[31:0] hrdata_regs; // AHB读数据
	reg hready_out_reg; // AHB上一次传输完成
	
	assign s_ahb_hrdata = hrdata_regs;
	assign s_ahb_hready_out = hready_out_reg;
	assign s_ahb_hresp = 1'b0;
	
	assign wdata = haddr_latched[1] ? s_ahb_hwdata[31:16]:s_ahb_hwdata[15:0];
	assign data_mask = hwrite_latched ? (haddr_latched[1] ? (~s_ahb_hwstrb[3:2]):(~s_ahb_hwstrb[1:0])):2'b00;
	assign trans_addr = haddr_latched[25:0];
	assign is_rd = ~hwrite_latched;
	
	// 锁存的AHB传输地址
	always @(posedge hclk)
	begin
		if(s_ahb_hready_in & s_ahb_htrans[1] & s_ahb_hsel)
			# simulation_delay haddr_latched <= s_ahb_haddr - 32'h0000_1000;
	end
	// 锁存的AHB传输读写类型
	always @(posedge hclk)
	begin
		if(s_ahb_hready_in & s_ahb_htrans[1] & s_ahb_hsel)
			# simulation_delay hwrite_latched <= s_ahb_hwrite;
	end
	
	// AHB读数据
	always @(posedge hclk)
	begin
		if(m_axis_rd_valid & haddr_latched[1])
			# simulation_delay hrdata_regs[31:16] <= m_axis_rd_data;
	end
	always @(posedge hclk)
	begin
		if(m_axis_rd_valid & (~haddr_latched[1]))
			# simulation_delay hrdata_regs[15:0] <= m_axis_rd_data;
	end
	// AHB上一次传输完成
	always @(posedge hclk or negedge hresetn)
	begin
		if(~hresetn)
			hready_out_reg <= 1'b1;
		else
			# simulation_delay hready_out_reg <= hready_out_reg ? 
				(~(ahb_trans_start & (s_ahb_haddr[25:12] != 14'd0))):fsmc_ctrler_done;
	end
	
	// FSMC控制器开始信号
	always @(posedge hclk or negedge hresetn)
	begin
		if(~hresetn)
			fsmc_ctrler_start <= 1'b0;
		else
			# simulation_delay fsmc_ctrler_start <= ahb_trans_start & (s_ahb_haddr[25:12] != 14'd0);
	end
	
endmodule
