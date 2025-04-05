`timescale 1ns / 1ps

module tb_cool_down_cnt();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer max_cd = 20000; // 冷却量的最大值(必须<=65536)
	localparam EN_TRG_IN_CD = "true"; // 是否允许冷却时再触发
	// 运行时参数
	localparam bit[15:0] cd = 16'd8 - 1; // 冷却量 - 1
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
	reg timer_trigger; // 触发
	
	initial
	begin
		timer_trigger <= 1'b0;
		
		@(posedge clk iff rst_n);
		
		repeat(10)
			@(posedge clk iff rst_n);
		
		timer_trigger <= # simulation_delay 1'b1;
		
		@(posedge clk iff rst_n);
		
		timer_trigger <= # simulation_delay 1'b0;
		
		repeat(20)
			@(posedge clk iff rst_n);
		
		timer_trigger <= # simulation_delay 1'b1;
		
		@(posedge clk iff rst_n);
		
		timer_trigger <= # simulation_delay 1'b0;
		
		repeat(4)
			@(posedge clk iff rst_n);
		
		timer_trigger <= # simulation_delay 1'b1;
		
		@(posedge clk iff rst_n);
		
		timer_trigger <= # simulation_delay 1'b0;
	end
	
	/** 待测模块 **/
	cool_down_cnt #(
		.max_cd(max_cd),
		.EN_TRG_IN_CD(EN_TRG_IN_CD),
		.SIM_DELAY(simulation_delay)
	)dut(
		.clk(clk),
		.rst_n(rst_n),
		
		.cd(cd),
		
		.timer_trigger(timer_trigger),
		.timer_done(),
		.timer_ready(),
		.timer_v()
	);
	
endmodule
