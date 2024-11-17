`timescale 1ns / 1ps

module req_grant_model #(
	parameter integer payload_width = 32, // 负载数据位宽
	parameter real simulation_delay = 1.0 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 请求/授权
	input wire req,
	output wire grant,
	output wire[payload_width-1:0] payload
);
	
	logic ready_reg;
	logic[payload_width-1:0] payload_regs;
	
	int unsigned ready_wait_period_n_fifo[$];
	bit[payload_width-1:0] payload_fifo[$];
	
	assign grant = req & ready_reg;
	assign payload = payload_regs;
	
	initial
	begin
		ready_reg <= 1'b0;
		payload_regs <= {payload_width{1'bx}};
		
		forever
		begin
			automatic int unsigned wait_n;
			automatic bit[payload_width-1:0] data;
			
			wait(ready_wait_period_n_fifo.size() > 0);
			wait(payload_fifo.size() > 0);
			
			wait_n = ready_wait_period_n_fifo.pop_front();
			data = payload_fifo.pop_front();
			
			if(wait_n == 0)
			begin
				ready_reg <= # simulation_delay 1'b1;
				payload_regs <= # simulation_delay data;
			end
			
			do
			begin
				@(posedge clk iff rst_n);
			end
			while(!req);
			
			if(wait_n > 0)
			begin
				repeat(wait_n - 1)
				begin
					@(posedge clk iff rst_n);
				end
				
				ready_reg <= # simulation_delay 1'b1;
				payload_regs <= # simulation_delay data;
				
				@(posedge clk iff rst_n);
				
				ready_reg <= # simulation_delay 1'b0;
				payload_regs <= # simulation_delay {payload_width{1'bx}};
			end
		end
	end
	
	initial
	begin
		forever
		begin
			wait((ready_wait_period_n_fifo.size() < 3) && (payload_fifo.size() < 3));
			
			payload_fifo.push_back(1984 + $urandom_range(0, 32) * 4);
			
			randcase
				3: ready_wait_period_n_fifo.push_back(0);
				1: ready_wait_period_n_fifo.push_back(1);
				1: ready_wait_period_n_fifo.push_back(2);
				1: ready_wait_period_n_fifo.push_back(3);
			endcase
		end
	end
	
endmodule
