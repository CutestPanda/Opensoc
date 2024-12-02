`timescale 1ns / 1ps

module tb_float_mul_pipelined();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam en_round_in_frac_mul_res = "true"; // 是否对尾数相乘结果进行四舍五入
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
	
	/** 激励产生 **/
	// 浮点乘法器输入
	reg[31:0] float_in_a;
	reg[31:0] float_in_b;
	reg float_in_valid;
	
	initial
	begin
		float_in_a <= 32'dx;
		float_in_b <= 32'dx;
		float_in_valid <= 1'b0;
		
		repeat(100)
		begin
			automatic int unsigned wait_n = $urandom_range(0, 2);
			
			repeat(wait_n)
				@(posedge clk iff rst_n);
			
			float_in_a <= # simulation_delay $random();
			float_in_b <= # simulation_delay $random();
			float_in_valid <= # simulation_delay 1'b1;
			
			@(posedge clk iff rst_n);
			
			float_in_a <= # simulation_delay 32'dx;
			float_in_b <= # simulation_delay 32'dx;
			float_in_valid <= # simulation_delay 1'b0;
		end
	end
	
	/** 待测模块 **/
	float_mul_pipelined #(
		.en_round_in_frac_mul_res(en_round_in_frac_mul_res),
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.rst_n(rst_n),
		
		.float_in_a(float_in_a),
		.float_in_b(float_in_b),
		.float_in_valid(float_in_valid),
		
		.float_out(),
		.float_ovf(),
		.float_out_valid()
	);
	
endmodule
