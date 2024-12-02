`timescale 1ns / 1ps

module tb_float_mul_pipelined();
	
	/** 配置参数 **/
	// 时钟和复位配置
	localparam real clk_p = 10.0; // 时钟周期
	localparam real simulation_delay = 1.0; // 仿真延时
	// 测试案例配置
	localparam integer test_n = 6; // 测试数量
	
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
	// 浮点数加法测试输入
	bit[31:0] float_a_table[0:test_n-1];
	bit[31:0] float_b_table[0:test_n-1];
	// 浮点加法器输入
	reg[31:0] float_in_a;
	reg[31:0] float_in_b;
	reg float_in_valid;
	
	initial
	begin
		float_a_table[0] = 32'h3EEB851F;
		float_a_table[1] = 32'h4077AE14;
		float_a_table[2] = 32'h3FE3D70A;
		float_a_table[3] = 32'h42078F5C;
		float_a_table[4] = 32'h3D0B4396;
		float_a_table[5] = 32'h40FC7AE1;
		
		float_b_table[0] = 32'h3FAB851F;
		float_b_table[1] = 32'h4268F5C3;
		float_b_table[2] = 32'hBFE28F5C;
		float_b_table[3] = 32'hC2F1F5C3;
		float_b_table[4] = 32'hC0DC0000;
		float_b_table[5] = 32'hC0FC7AE1;
		
		float_in_a <= 32'dx;
		float_in_b <= 32'dx;
		float_in_valid <= 1'b0;
		
		for(int i = 0;i < test_n;i++)
		begin
			automatic int unsigned wait_n = $urandom_range(0, 2);
			
			repeat(wait_n)
				@(posedge clk iff rst_n);
			
			float_in_a <= # simulation_delay float_a_table[i];
			float_in_b <= # simulation_delay float_b_table[i];
			float_in_valid <= # simulation_delay 1'b1;
			
			@(posedge clk iff rst_n);
			
			float_in_a <= # simulation_delay 32'dx;
			float_in_b <= # simulation_delay 32'dx;
			float_in_valid <= # simulation_delay 1'b0;
		end
	end
	
	/** 待测模块 **/
	float_add_pipelined #(
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
