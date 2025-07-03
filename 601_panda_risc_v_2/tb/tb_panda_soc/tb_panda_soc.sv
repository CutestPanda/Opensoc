`timescale 1ns / 1ps

module tb_panda_soc();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam imem_init_file = "E:/scientific_research/risc-v/coremark.txt"; // 指令存储器初始化文件路径
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
	
	/** 待测模块 **/
	tri0[21:0] gpio0_tri;
	tri0 i2c0_scl_tri;
	tri0 i2c0_sda_tri;
	
	assign gpio0_tri = 22'bzz_zzzz_zzzz_zzzz_zzzz_zzzz;
	assign i2c0_scl_tri = 1'bz;
	assign i2c0_sda_tri = 1'bz;
	
	panda_soc_top #(
		.imem_init_file(imem_init_file),
		.simulation_delay(simulation_delay)
	)panda_soc_top_u(
		.osc_clk(clk),
		.ext_resetn(rst_n),
		
		.tck(1'b1),
		.trst_n(1'b1),
		.tms(1'b1),
		.tdi(1'b1),
		.tdo(),
		
		.boot(1'b0),
		
		.gpio0(gpio0_tri),
		
		.i2c0_scl(i2c0_scl_tri),
		.i2c0_sda(i2c0_sda_tri),
		
		.uart0_tx(),
		.uart0_rx(1'b1),
		
		.pwm0_o()
	);
	
endmodule
