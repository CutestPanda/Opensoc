`timescale 1ns / 1ps
/********************************************************************
本模块: AXI-FSMC

描述:
带AXI-Lite从接口的FSMC控制器

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
AXI SLAVE
FSMC MASTER

作者: 陈家耀
日期: 2024/08/29
********************************************************************/


module axi_fsmc #(
	parameter real simulation_delay = 0 // 仿真延时
)(
	// 时钟和复位
    input wire s_axi_clk,
    input wire s_axi_resetn,
    
    // AXI-Lite SLAVE
    // 读地址通道
    input wire[31:0] s_axi_araddr,
    input wire[2:0] s_axi_arsize, // ignored(assumed to be 3'b001)
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    // 写地址通道
    input wire[31:0] s_axi_awaddr,
    input wire[2:0] s_axi_awsize, // ignored(assumed to be 3'b001)
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    // 写响应通道
    output wire[1:0] s_axi_bresp, // const -> 2'b00
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    // 读数据通道
    output wire[31:0] s_axi_rdata,
    output wire[1:0] s_axi_rresp, // const -> 2'b00
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    // 写数据通道
    input wire[31:0] s_axi_wdata,
    input wire[3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
	
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
	
	/** AXI传输流程控制 **/
	wire axi_trans_done; // AXI传输完成(指示)
	reg axi_addr_available; // AXI地址寄存器可用(标志)
	reg axi_wdata_available; // AXI写数据寄存器可用(标志)
	reg axi_rd_reg; // 是否AXI读传输
	
	// AXI地址寄存器可用(标志)
	always @(posedge s_axi_clk or negedge s_axi_resetn)
	begin
		if(~s_axi_resetn)
			axi_addr_available <= 1'b1;
		else
			# simulation_delay axi_addr_available <= axi_addr_available ? 
				(~((s_axi_arvalid & s_axi_arready) | (s_axi_awvalid & s_axi_awready))):axi_trans_done;
	end
	
	// AXI写数据寄存器可用(标志)
	always @(posedge s_axi_clk or negedge s_axi_resetn)
	begin
		if(~s_axi_resetn)
			axi_wdata_available <= 1'b1;
		else
			# simulation_delay axi_wdata_available <= axi_wdata_available ? 
				(~(s_axi_wvalid & s_axi_wready)):(axi_trans_done & (~axi_rd_reg));
	end
	
	/** AXI读/写地址通道 **/
	wire axi_ar_req; // AXI读传输请求
	wire axi_aw_req; // AXI写传输请求
	wire arb_valid; // 仲裁结果有效
	reg arb_valid_d; // 延迟1clk的仲裁结果有效
	wire[1:0] arb_grant; // 仲裁授权(独热码)
	reg[1:0] arb_grant_d; // 延迟1clk的仲裁授权(独热码)
	reg[31:0] axi_addr_regs; // AXI地址寄存器
	
	assign {s_axi_arready, s_axi_awready} = arb_grant_d;
	
	assign axi_ar_req = s_axi_arvalid & axi_addr_available & (~arb_valid_d);
	assign axi_aw_req = s_axi_awvalid & axi_addr_available & (~arb_valid_d);
	
	// 延迟1clk的仲裁结果有效
	always @(posedge s_axi_clk or negedge s_axi_resetn)
	begin
		if(~s_axi_resetn)
			arb_valid_d <= 1'b0;
		else
			# simulation_delay arb_valid_d <= arb_valid;
	end
	// 延迟1clk的仲裁授权(独热码)
	always @(posedge s_axi_clk or negedge s_axi_resetn)
	begin
		if(~s_axi_resetn)
			arb_grant_d <= 2'b00;
		else
			# simulation_delay arb_grant_d <= arb_grant;
	end
	
	// AXI地址寄存器
	always @(posedge s_axi_clk)
	begin
		if((s_axi_arvalid & s_axi_arready) | (s_axi_awvalid & s_axi_awready))
			// 断言: AR通道和AW通道不会同时握手!
			# simulation_delay axi_addr_regs <= (s_axi_arvalid & s_axi_arready) ? 
				s_axi_araddr:s_axi_awaddr;
	end
	// 是否AXI读传输
	always @(posedge s_axi_clk)
	begin
		if((s_axi_arvalid & s_axi_arready) | (s_axi_awvalid & s_axi_awready))
			// 断言: AR通道和AW通道不会同时握手!
			# simulation_delay axi_rd_reg <= s_axi_arvalid & s_axi_arready;
	end
	
	// Round-Robin仲裁器
	round_robin_arbitrator #(
		.chn_n(2),
		.simulation_delay(simulation_delay)
	)round_robin_arbitrator_u(
		.clk(s_axi_clk),
		.rst_n(s_axi_resetn),
		
		.req({axi_ar_req, axi_aw_req}),
		.grant(arb_grant),
		.sel(),
		.arb_valid(arb_valid)
	);
	
	/** AXI写响应通道 **/
	reg axi_bvalid; // AXI写响应有效
	
	assign s_axi_bresp = 2'b00;
	assign s_axi_bvalid = axi_bvalid;
	
	// AXI写响应有效
	always @(posedge s_axi_clk or negedge s_axi_resetn)
	begin
		if(~s_axi_resetn)
			axi_bvalid <= 1'b0;
		else
			# simulation_delay axi_bvalid <= axi_bvalid ? (~s_axi_bready):(axi_trans_done & (~axi_rd_reg));
	end
	
	/** AXI读数据通道 **/
	// 配置寄存器片读数据输出
	wire[15:0] cfg_reg_slice_rdata;
	wire cfg_reg_slice_rdata_vld;
	// FSMC控制器读数据输出
	wire[15:0] m_axis_rd_data;
	wire m_axis_rd_valid;
	// AXI读数据
	reg[31:0] axi_rdata_regs; // AXI读数据寄存器
	reg axi_rdata_valid; // AXI读数据有效
	
	assign s_axi_rdata = axi_rdata_regs;
	assign s_axi_rresp = 2'b00;
	assign s_axi_rvalid = axi_rdata_valid;
	
	// AXI读数据寄存器
	always @(posedge s_axi_clk)
	begin
		if((m_axis_rd_valid | cfg_reg_slice_rdata_vld) & axi_addr_regs[1])
			# simulation_delay axi_rdata_regs[31:16] <= m_axis_rd_valid ? m_axis_rd_data:cfg_reg_slice_rdata;
	end
	always @(posedge s_axi_clk)
	begin
		if((m_axis_rd_valid | cfg_reg_slice_rdata_vld) & (~axi_addr_regs[1]))
			# simulation_delay axi_rdata_regs[15:0] <= m_axis_rd_valid ? m_axis_rd_data:cfg_reg_slice_rdata;
	end
	// AXI读数据有效
	always @(posedge s_axi_clk or negedge s_axi_resetn)
	begin
		if(~s_axi_resetn)
			axi_rdata_valid <= 1'b0;
		else
			# simulation_delay axi_rdata_valid <= axi_rdata_valid ? (~s_axi_rready):(m_axis_rd_valid | cfg_reg_slice_rdata_vld);
	end
	
	/** AXI写数据通道 **/
	reg[31:0] axi_wdata_regs; // AXI写数据寄存器
	reg[3:0] axi_wstrb_regs; // AXI写字节使能寄存器
	
	assign s_axi_wready = axi_wdata_available;
	
	// AXI写数据寄存器
	always @(posedge s_axi_clk)
	begin
		if(s_axi_wvalid & s_axi_wready)
			# simulation_delay axi_wdata_regs <= s_axi_wdata;
	end
	// AXI写字节使能寄存器
	always @(posedge s_axi_clk)
	begin
		if(s_axi_wvalid & s_axi_wready)
			# simulation_delay axi_wstrb_regs <= s_axi_wstrb;
	end
	
	/**
	配置寄存器片
	
	偏移量0x000_0000~0x000_0FFF:
		子偏移量0x00 -> 7~0:   地址建立周期数 - 1
						15~8:  数据建立周期数 - 1
		子偏移量0x02 -> 7~0:   数据保持周期数 - 1
	**/
	reg[2:0] cfg_reg_slice_proc_ctrl; // 流程独热码
	// FSMC控制器运行时参数
	reg[7:0] addr_set; // 地址建立周期数 - 1
	reg[7:0] data_set; // 数据建立周期数 - 1
	reg[7:0] data_hold; // 数据保持周期数 - 1
	
	assign cfg_reg_slice_rdata = 16'dx;
	assign cfg_reg_slice_rdata_vld = cfg_reg_slice_proc_ctrl[2] & axi_rd_reg;
	
	// 流程独热码
	always @(posedge s_axi_clk or negedge s_axi_resetn)
	begin
		if(~s_axi_resetn)
			cfg_reg_slice_proc_ctrl <= 3'b001;
		else if((cfg_reg_slice_proc_ctrl[0] & (~axi_addr_available) & 
			(axi_addr_regs[25:12] == 14'd0) & (axi_rd_reg ? 1'b1:(~axi_wdata_available))) | 
			cfg_reg_slice_proc_ctrl[1] | 
			cfg_reg_slice_proc_ctrl[2])
			# simulation_delay cfg_reg_slice_proc_ctrl <= {cfg_reg_slice_proc_ctrl[1:0], cfg_reg_slice_proc_ctrl[2]};
	end
	
	// 地址建立周期数 - 1
	// 数据建立周期数 - 1
	always @(posedge s_axi_clk)
	begin
		if(cfg_reg_slice_proc_ctrl[1] & (~axi_addr_regs[1]) & (~axi_rd_reg))
			# simulation_delay {data_set, addr_set} <= axi_wdata_regs[15:0];
	end
	// 数据保持周期数 - 1
	always @(posedge s_axi_clk)
	begin
		if(cfg_reg_slice_proc_ctrl[1] & axi_addr_regs[1] & (~axi_rd_reg))
			# simulation_delay data_hold <= axi_wdata_regs[23:16];
	end
	
	/** 
	FSMC存储映射区
	
	偏移量0x000_1000~0x3FF_FFFF:
		子偏移量0x000_0000~0x3FF_EFFF -> FSMC
	**/
	reg[2:0] fsmc_proc_ctrl; // 流程独热码
	// FSMC控制器流程控制
	wire fsmc_ctrler_start;
	wire fsmc_ctrler_done;
	
	assign axi_trans_done = cfg_reg_slice_proc_ctrl[2] | fsmc_ctrler_done;
	
	assign fsmc_ctrler_start = fsmc_proc_ctrl[1];
	
	// 流程独热码
	always @(posedge s_axi_clk or negedge s_axi_resetn)
	begin
		if(~s_axi_resetn)
			fsmc_proc_ctrl <= 3'b001;
		else if((fsmc_proc_ctrl[0] & (~axi_addr_available) & 
			(axi_addr_regs[25:12] != 14'd0) & (axi_rd_reg ? 1'b1:(~axi_wdata_available))) | 
			fsmc_proc_ctrl[1] | 
			(fsmc_proc_ctrl[2] & fsmc_ctrler_done))
			# simulation_delay fsmc_proc_ctrl <= {fsmc_proc_ctrl[1:0], fsmc_proc_ctrl[2]};
	end
	
	/** FSMC控制器 **/
	// 传输参数
	wire[15:0] wdata; // 写数据
	wire[1:0] data_mask; // 字节使能掩码
	wire[25:0] trans_addr; // 传输地址
	wire is_rd; // 是否读传输
	
	assign wdata = axi_addr_regs[1] ? axi_wdata_regs[31:16]:axi_wdata_regs[15:0];
	assign data_mask = axi_rd_reg ? 2'b00:(axi_addr_regs[1] ? (~axi_wstrb_regs[3:2]):(~axi_wstrb_regs[1:0]));
	assign trans_addr = axi_addr_regs[25:0] - 32'h0000_1000;
	assign is_rd = axi_rd_reg;
	
	fsmc_ctrler #(
		.simulation_delay(simulation_delay)
	)fsmc_ctrler_u(
		.clk(s_axi_clk),
		.rst_n(s_axi_resetn),
		
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
	
endmodule
