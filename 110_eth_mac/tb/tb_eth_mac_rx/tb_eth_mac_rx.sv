`timescale 1ns / 1ps

module tb_eth_mac_rx();
	
	/** 配置参数 **/
	// 测试模块配置
	localparam integer ETH_RX_TIMEOUT_N = 8; // 以太网接收超时周期数(必须在范围[4, 256]内)
	// 时钟和复位配置
	localparam real clk1_p = 10.0; // 时钟#1周期
	localparam real clk2_p = 8.0; // 时钟#2周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 时钟和复位 **/
	reg clk1;
	reg rst_n1;
	reg clk2;
	reg rst_n2;
	
	initial
	begin
		clk1 <= 1'b1;
		
		forever
		begin
			# (clk1_p / 2) clk1 <= ~clk1;
		end
	end
	
	initial
	begin
		clk2 <= 1'b1;
		
		forever
		begin
			# (clk2_p / 2) clk2 <= ~clk2;
		end
	end
	
	initial begin
		rst_n1 <= 1'b0;
		
		# (clk1_p * 10 + simulation_delay);
		
		rst_n1 <= 1'b1;
	end
	
	initial begin
		rst_n2 <= 1'b0;
		
		# (clk2_p * 10 + simulation_delay);
		
		rst_n2 <= 1'b1;
	end
	
	/** 测试激励 **/
	// 以太网帧字节流
	reg[7:0] eth_rx_data;
	reg eth_rx_valid;
	
	initial
	begin
		eth_rx_data <= 8'hxx;
		eth_rx_valid <= 1'b0;
		
		repeat(10)
			@(posedge clk2 iff rst_n2);
		
		// 帧#0
		repeat(7)
		begin
			@(posedge clk2 iff rst_n2);
			
			eth_rx_data <= # simulation_delay 8'h55;
			eth_rx_valid <= # simulation_delay 1'b1;
		end
		
		@(posedge clk2 iff rst_n2);
		
		eth_rx_data <= # simulation_delay 8'hd5;
		eth_rx_valid <= # simulation_delay 1'b1;
		
		for(int i = 0;i < 18;i++)
		begin
			@(posedge clk2 iff rst_n2);
		
			eth_rx_data <= # simulation_delay i;
			eth_rx_valid <= # simulation_delay 1'b1;
		end
		
		@(posedge clk2 iff rst_n2);
		
		eth_rx_data <= # simulation_delay 8'h85;
		eth_rx_valid <= # simulation_delay 1'b1;
		
		@(posedge clk2 iff rst_n2);
		
		eth_rx_data <= # simulation_delay 8'h7f;
		eth_rx_valid <= # simulation_delay 1'b1;
		
		@(posedge clk2 iff rst_n2);
		
		eth_rx_data <= # simulation_delay 8'hf5;
		eth_rx_valid <= # simulation_delay 1'b1;
		
		@(posedge clk2 iff rst_n2);
		
		eth_rx_data <= # simulation_delay 8'hdc;
		eth_rx_valid <= # simulation_delay 1'b1;
		
		repeat(96)
		begin
			@(posedge clk2 iff rst_n2);
			
			eth_rx_data <= # simulation_delay 8'hxx;
			eth_rx_valid <= # simulation_delay 1'b0;
		end
		
		// 帧#1
		repeat(7)
		begin
			@(posedge clk2 iff rst_n2);
			
			eth_rx_data <= # simulation_delay 8'h55;
			eth_rx_valid <= # simulation_delay 1'b1;
		end
		
		@(posedge clk2 iff rst_n2);
		
		eth_rx_data <= # simulation_delay 8'hd5;
		eth_rx_valid <= # simulation_delay 1'b1;
		
		for(int i = 0;i < 19;i++)
		begin
			@(posedge clk2 iff rst_n2);
		
			eth_rx_data <= # simulation_delay i;
			eth_rx_valid <= # simulation_delay 1'b1;
		end
		
		@(posedge clk2 iff rst_n2);
		
		eth_rx_data <= # simulation_delay 8'h15;
		eth_rx_valid <= # simulation_delay 1'b1;
		
		@(posedge clk2 iff rst_n2);
		
		eth_rx_data <= # simulation_delay 8'h1c;
		eth_rx_valid <= # simulation_delay 1'b1;
		
		@(posedge clk2 iff rst_n2);
		
		eth_rx_data <= # simulation_delay 8'hb5;
		eth_rx_valid <= # simulation_delay 1'b1;
		
		@(posedge clk2 iff rst_n2);
		
		eth_rx_data <= # simulation_delay 8'hbc;
		eth_rx_valid <= # simulation_delay 1'b1;
		
		repeat(96)
		begin
			@(posedge clk2 iff rst_n2);
			
			eth_rx_data <= # simulation_delay 8'hxx;
			eth_rx_valid <= # simulation_delay 1'b0;
		end
		
		// 帧#2
		repeat(7)
		begin
			@(posedge clk2 iff rst_n2);
			
			eth_rx_data <= # simulation_delay 8'h55;
			eth_rx_valid <= # simulation_delay 1'b1;
		end
		
		@(posedge clk2 iff rst_n2);
		
		eth_rx_data <= # simulation_delay 8'hd5;
		eth_rx_valid <= # simulation_delay 1'b1;
		
		for(int i = 0;i < 20;i++)
		begin
			@(posedge clk2 iff rst_n2);
		
			eth_rx_data <= # simulation_delay i;
			eth_rx_valid <= # simulation_delay 1'b1;
		end
		
		@(posedge clk2 iff rst_n2);
		
		eth_rx_data <= # simulation_delay 8'ha4;
		eth_rx_valid <= # simulation_delay 1'b1;
		
		@(posedge clk2 iff rst_n2);
		
		eth_rx_data <= # simulation_delay 8'hff;
		eth_rx_valid <= # simulation_delay 1'b1;
		
		@(posedge clk2 iff rst_n2);
		
		eth_rx_data <= # simulation_delay 8'hdd;
		eth_rx_valid <= # simulation_delay 1'b1;
		
		@(posedge clk2 iff rst_n2);
		
		eth_rx_data <= # simulation_delay 8'h3b;
		eth_rx_valid <= # simulation_delay 1'b1;
		
		repeat(96)
		begin
			@(posedge clk2 iff rst_n2);
			
			eth_rx_data <= # simulation_delay 8'hxx;
			eth_rx_valid <= # simulation_delay 1'b0;
		end
	end
	
	/** 待测模块 **/
	eth_mac_rx #(
		.ETH_RX_TIMEOUT_N(ETH_RX_TIMEOUT_N),
		.SIM_DELAY(simulation_delay)
	)dut(
		.m_axis_aclk(clk1),
		.m_axis_aresetn(rst_n1),
		.eth_rx_aclk(clk2),
		.eth_rx_aresetn(rst_n2),
		
		.broadcast_accept(1'b1),
		.unicast_filter_mac(48'h00_01_02_03_04_05),
		.multicast_filter_mac_0(48'hxx_xx_xx_xx_xx_xx),
		.multicast_filter_mac_1(48'hxx_xx_xx_xx_xx_xx),
		.multicast_filter_mac_2(48'hxx_xx_xx_xx_xx_xx),
		.multicast_filter_mac_3(48'hxx_xx_xx_xx_xx_xx),
		
		.eth_rx_data(eth_rx_data),
		.eth_rx_valid(eth_rx_valid),
		
		.m_axis_data(),
		.m_axis_keep(),
		.m_axis_last(),
		.m_axis_valid()
	);
	
endmodule
