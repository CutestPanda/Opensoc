/*
MIT License

Copyright (c) 2024 Panda, 2257691535@qq.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

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
			
			payload_fifo.push_back($random() * 4);
			
			randcase
				3: ready_wait_period_n_fifo.push_back(0);
				2: ready_wait_period_n_fifo.push_back(1);
				2: ready_wait_period_n_fifo.push_back(2);
				1: ready_wait_period_n_fifo.push_back(3);
			endcase
		end
	end
	
endmodule
