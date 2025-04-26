`timescale 1ns / 1ps

module tb_eth_mac_mdio();
	
	/** 配置参数 **/
	// 运行时参数
	localparam bit[9:0] mdc_div_rate = 10'd1; // MDIO时钟分频系数(分频数 = (分频系数 + 1) * 2)
	// 时钟和复位配置
	localparam real clk_p = 10.0; // 时钟周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 时钟和复位 **/
	reg clk;
	reg rst_n;
	
	initial
	begin
		clk <= 1'b1;
		
		forever
		begin
			# (clk_p / 2) clk <= ~clk;
		end
	end
	
	initial begin
		rst_n <= 1'b0;
		
		# (clk_p * 10 + simulation_delay);
		
		rst_n <= 1'b1;
	end
	
	/** 测试激励 **/
	// 块级控制
	reg mdio_access_start;
	reg mdio_access_is_rd; // 是否读寄存器
	reg[9:0] mdio_access_addr; // 访问地址({寄存器地址(5位), PHY地址(5位)})
	reg[15:0] mdio_access_wdata; // 写数据
	// MDIO接口
	tri1 mdio;
	wire mdio_i;
	wire mdio_o;
	wire mdio_t; // 1为输入, 0为输出
	
	initial
	begin
		repeat(10)
			@(posedge clk iff rst_n);
		
		mdio_access_start <= # simulation_delay 1'b1;
		mdio_access_is_rd <= # simulation_delay 1'b1;
		mdio_access_addr <= # simulation_delay {5'b10100, 5'b01101};
		mdio_access_wdata <= # simulation_delay 16'hxxxx;
		
		@(posedge clk iff rst_n);
		
		mdio_access_start <= # simulation_delay 1'b0;
		mdio_access_is_rd <= # simulation_delay 1'bx;
		mdio_access_addr <= # simulation_delay 10'dx;
		mdio_access_wdata <= # simulation_delay 16'hxxxx;
		
		repeat(600)
			@(posedge clk iff rst_n);
		
		mdio_access_start <= # simulation_delay 1'b1;
		mdio_access_is_rd <= # simulation_delay 1'b0;
		mdio_access_addr <= # simulation_delay {5'b01011, 5'b11100};
		mdio_access_wdata <= # simulation_delay 16'b11001100_00111011;
		
		@(posedge clk iff rst_n);
		
		mdio_access_start <= # simulation_delay 1'b0;
		mdio_access_is_rd <= # simulation_delay 1'bx;
		mdio_access_addr <= # simulation_delay 10'dx;
		mdio_access_wdata <= # simulation_delay 16'hxxxx;
	end
	
	/** 待测模块 **/
	assign mdio = mdio_t ? 1'bz:mdio_o;
	assign mdio_i = mdio;
	
	eth_mac_mdio #(
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		
		.mdc_div_rate(mdc_div_rate),
		
		.mdio_access_start(mdio_access_start),
		.mdio_access_is_rd(mdio_access_is_rd),
		.mdio_access_addr(mdio_access_addr),
		.mdio_access_wdata(mdio_access_wdata),
		.mdio_access_idle(),
		.mdio_access_rdata(),
		.mdio_access_done(),
		
		.mdc(),
		.mdio_i(mdio_i),
		.mdio_o(mdio_o),
		.mdio_t(mdio_t)
	);
	
endmodule
