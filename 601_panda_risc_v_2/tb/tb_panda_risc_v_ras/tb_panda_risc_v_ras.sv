`timescale 1ns / 1ps

module tb_panda_risc_v_ras();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer RAS_ENTRY_WIDTH = 32; // 返回地址堆栈的条目位宽
	localparam integer RAS_ENTRY_N = 4; // 返回地址堆栈的条目数(2 | 4 | 8 | 16)
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
	// RAS压栈
	reg ras_push_req;
	reg[RAS_ENTRY_WIDTH-1:0] ras_push_addr;
	// RAS出栈
	reg ras_pop_req;
	wire[RAS_ENTRY_WIDTH-1:0] ras_pop_addr;
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			ras_push_addr <= 0;
		else if(ras_push_req)
			ras_push_addr <= # simulation_delay ras_push_addr + 1;
	end
	
	initial
	begin
		ras_push_req <= 1'b0;
		ras_pop_req <= 1'b0;
		
		@(posedge clk iff rst_n);
		
		repeat(4)
		begin
			ras_push_req <= # simulation_delay 1'b1;
			ras_pop_req <= # simulation_delay 1'b0;
			
			@(posedge clk iff rst_n);
			
			ras_push_req <= # simulation_delay 1'b0;
			ras_pop_req <= # simulation_delay 1'b1;
			
			@(posedge clk iff rst_n);
		end
		
		ras_push_req <= # simulation_delay 1'b0;
		ras_pop_req <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		repeat(4)
		begin
			ras_push_req <= # simulation_delay 1'b0;
			ras_pop_req <= # simulation_delay 1'b1;
			
			@(posedge clk iff rst_n);
		end
		
		ras_push_req <= # simulation_delay 1'b0;
		ras_pop_req <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		repeat(8)
		begin
			ras_push_req <= # simulation_delay 1'b1;
			ras_pop_req <= # simulation_delay 1'b0;
			
			@(posedge clk iff rst_n);
		end
		
		ras_push_req <= # simulation_delay 1'b0;
		ras_pop_req <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		repeat(6)
		begin
			ras_push_req <= # simulation_delay 1'b0;
			ras_pop_req <= # simulation_delay 1'b1;
			
			@(posedge clk iff rst_n);
		end
		
		ras_push_req <= # simulation_delay 1'b0;
		ras_pop_req <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		repeat(5)
		begin
			ras_push_req <= # simulation_delay 1'b0;
			ras_pop_req <= # simulation_delay 1'b0;
			
			@(posedge clk iff rst_n);
			
			ras_push_req <= # simulation_delay 1'b1;
			ras_pop_req <= # simulation_delay 1'b0;
			
			@(posedge clk iff rst_n);
		end
		
		ras_push_req <= # simulation_delay 1'b0;
		ras_pop_req <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		repeat(4)
		begin
			ras_push_req <= # simulation_delay 1'b1;
			ras_pop_req <= # simulation_delay 1'b0;
			
			@(posedge clk iff rst_n);
			
			ras_push_req <= # simulation_delay 1'b0;
			ras_pop_req <= # simulation_delay 1'b1;
			
			@(posedge clk iff rst_n);
		end
		
		ras_push_req <= # simulation_delay 1'b0;
		ras_pop_req <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		repeat(6)
		begin
			ras_push_req <= # simulation_delay 1'b0;
			ras_pop_req <= # simulation_delay 1'b1;
			
			@(posedge clk iff rst_n);
		end
		
		ras_push_req <= # simulation_delay 1'b0;
		ras_pop_req <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		ras_push_req <= # simulation_delay 1'b1;
		ras_pop_req <= # simulation_delay 1'b1;
		
		@(posedge clk iff rst_n);
		
		ras_push_req <= # simulation_delay 1'b1;
		ras_pop_req <= # simulation_delay 1'b1;
		
		@(posedge clk iff rst_n);
		
		ras_push_req <= # simulation_delay 1'b1;
		ras_pop_req <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		ras_push_req <= # simulation_delay 1'b1;
		ras_pop_req <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		ras_push_req <= # simulation_delay 1'b1;
		ras_pop_req <= # simulation_delay 1'b1;
		
		@(posedge clk iff rst_n);
		
		ras_push_req <= # simulation_delay 1'b1;
		ras_pop_req <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		ras_push_req <= # simulation_delay 1'b1;
		ras_pop_req <= # simulation_delay 1'b1;
		
		@(posedge clk iff rst_n);
		
		ras_push_req <= # simulation_delay 1'b1;
		ras_pop_req <= # simulation_delay 1'b1;
		
		@(posedge clk iff rst_n);
		
		ras_push_req <= # simulation_delay 1'b0;
		ras_pop_req <= # simulation_delay 1'b0;
	end
	
	/** 待测模块 **/
	panda_risc_v_ras #(
		.RAS_ENTRY_WIDTH(RAS_ENTRY_WIDTH),
		.RAS_ENTRY_N(RAS_ENTRY_N),
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		
		.ras_push_req(ras_push_req),
		.ras_push_addr(ras_push_addr),
		
		.ras_pop_req(ras_pop_req),
		.ras_pop_addr(ras_pop_addr),
		
		.ras_query_req(1'b1),
		.ras_query_addr()
	);
	
endmodule
