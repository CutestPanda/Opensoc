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

module tb_panda_risc_v_btb();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer BTB_WAY_N = 2; // BTB路数(1 | 2 | 4)
	localparam integer BTB_ENTRY_N = 512; // BTB项数(<=65536)
	localparam integer PC_TAG_WIDTH = 21; // PC标签的位宽(不要修改)
	localparam integer BTB_MEM_WIDTH = PC_TAG_WIDTH + 32 + 3 + 1 + 1; // BTB存储器的数据位宽(不要修改)
	// 时钟和复位配置
	localparam real CLK_P = 10.0; // 时钟周期
	localparam real SIM_DELAY = 1.0; // 仿真延时
	
	/** 时钟和复位 **/
	reg clk;
	reg rst_n;
	
	initial
	begin
		clk <= 1'b1;
		
		forever
		begin
			# (CLK_P / 2) clk <= ~clk;
		end
	end
	
	initial begin
		rst_n <= 1'b0;
		
		# (CLK_P * 10 + SIM_DELAY);
		
		rst_n <= 1'b1;
	end
	
	/** 仿真激励 **/
	// BTB查询
	reg btb_query_i_req; // 查询请求
	reg[31:0] btb_query_i_pc; // 待查询的PC
	// BTB置换
	reg btb_rplc_req; // 置换请求
	reg[31:0] btb_rplc_pc; // 分支指令对应的PC
	reg[2:0] btb_rplc_btype; // 分支指令类型
	reg[31:0] btb_rplc_bta; // 分支指令对应的目标地址
	reg btb_rplc_jpdir; // 分支跳转方向
	
	initial
	begin
		btb_query_i_req <= 1'b0;
		btb_query_i_pc <= 32'dx;
		
		btb_rplc_req <= 1'b0;
		btb_rplc_pc <= 32'dx;
		btb_rplc_btype <= 3'bxxx;
		btb_rplc_bta <= 32'dx;
		btb_rplc_jpdir <= 1'bx;
		
		repeat(10)
			@(posedge clk iff rst_n);
		
		btb_query_i_req <= # SIM_DELAY 1'b1;
		btb_rplc_req <= # SIM_DELAY 1'b0;
		
		@(posedge clk iff rst_n);
		
		btb_query_i_req <= # SIM_DELAY 1'b0;
		btb_rplc_req <= # SIM_DELAY 1'b1;
		
		@(posedge clk iff rst_n);
		
		btb_query_i_req <= # SIM_DELAY 1'b0;
		btb_rplc_req <= # SIM_DELAY 1'b0;
		
		repeat(600)
			@(posedge clk iff rst_n);
		
		btb_rplc_req <= # SIM_DELAY 1'b1;
		btb_rplc_pc <= # SIM_DELAY {21'd0, 9'd0, 2'b00};
		btb_rplc_btype <= # SIM_DELAY 3'b001;
		btb_rplc_bta <= # SIM_DELAY 32'd200;
		btb_rplc_jpdir <= # SIM_DELAY 1'b0;
		
		@(posedge clk iff rst_n);
		
		btb_rplc_req <= # SIM_DELAY 1'b1;
		btb_rplc_pc <= # SIM_DELAY {21'd0, 9'd511, 2'b00};
		btb_rplc_btype <= # SIM_DELAY 3'b010;
		btb_rplc_bta <= # SIM_DELAY 32'd204;
		btb_rplc_jpdir <= # SIM_DELAY 1'b1;
		
		@(posedge clk iff rst_n);
		
		btb_rplc_req <= # SIM_DELAY 1'b1;
		btb_rplc_pc <= # SIM_DELAY {21'd0, 9'd3, 2'b00};
		btb_rplc_btype <= # SIM_DELAY 3'b001;
		btb_rplc_bta <= # SIM_DELAY 32'd200;
		btb_rplc_jpdir <= # SIM_DELAY 1'b0;
		
		@(posedge clk iff rst_n);
		
		btb_rplc_req <= # SIM_DELAY 1'b1;
		btb_rplc_pc <= # SIM_DELAY {21'd0, 9'd6, 2'b00};
		btb_rplc_btype <= # SIM_DELAY 3'b001;
		btb_rplc_bta <= # SIM_DELAY 32'd200;
		btb_rplc_jpdir <= # SIM_DELAY 1'b0;
		
		@(posedge clk iff rst_n);
		
		btb_rplc_req <= # SIM_DELAY 1'b1;
		btb_rplc_pc <= # SIM_DELAY {21'd1, 9'd511, 2'b00};
		btb_rplc_btype <= # SIM_DELAY 3'b011;
		btb_rplc_bta <= # SIM_DELAY 32'd208;
		btb_rplc_jpdir <= # SIM_DELAY 1'b0;
		
		@(posedge clk iff rst_n);
		
		btb_rplc_req <= # SIM_DELAY 1'b0;
		
		@(posedge clk iff rst_n);
		
		btb_query_i_req <= # SIM_DELAY 1'b1;
		btb_query_i_pc <= # SIM_DELAY {21'd1, 9'd511, 2'b00};
		
		@(posedge clk iff rst_n);
		
		btb_query_i_req <= # SIM_DELAY 1'b1;
		btb_query_i_pc <= # SIM_DELAY {21'd0, 9'd511, 2'b00};
		
		@(posedge clk iff rst_n);
		
		btb_query_i_req <= # SIM_DELAY 1'b1;
		btb_query_i_pc <= # SIM_DELAY {21'd0, 9'd0, 2'b00};
		
		@(posedge clk iff rst_n);
		
		btb_query_i_req <= # SIM_DELAY 1'b1;
		btb_query_i_pc <= # SIM_DELAY {21'd1, 9'd0, 2'b00};
		
		@(posedge clk iff rst_n);
		
		btb_query_i_req <= # SIM_DELAY 1'b0;
	end
	
	/** 待测模块 **/
	// BTB存储器
	// [端口A]
	wire[BTB_WAY_N-1:0] btb_mem_clka;
	wire[BTB_WAY_N-1:0] btb_mem_ena;
	wire[BTB_WAY_N-1:0] btb_mem_wea;
	wire[BTB_WAY_N*16-1:0] btb_mem_addra;
	wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_dina;
	wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_douta;
	// [端口B]
	wire[BTB_WAY_N-1:0] btb_mem_clkb;
	wire[BTB_WAY_N-1:0] btb_mem_enb;
	wire[BTB_WAY_N-1:0] btb_mem_web;
	wire[BTB_WAY_N*16-1:0] btb_mem_addrb;
	wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_dinb;
	wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_doutb;
	
	panda_risc_v_btb #(
		.BTB_WAY_N(BTB_WAY_N),
		.BTB_ENTRY_N(BTB_ENTRY_N),
		.PC_TAG_WIDTH(PC_TAG_WIDTH),
		.BTB_MEM_WIDTH(BTB_MEM_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		
		.btb_initializing(),
		
		.btb_query_i_req(btb_query_i_req),
		.btb_query_i_pc(btb_query_i_pc),
		.btb_query_o_hit(),
		.btb_query_o_btype(),
		.btb_query_o_bta(),
		.btb_query_o_jpdir(),
		.btb_query_o_vld(),
		
		.btb_rplc_req(btb_rplc_req),
		.btb_rplc_pc(btb_rplc_pc),
		.btb_rplc_btype(btb_rplc_btype),
		.btb_rplc_bta(btb_rplc_bta),
		.btb_rplc_jpdir(btb_rplc_jpdir),
		
		.btb_mem_clka(btb_mem_clka),
		.btb_mem_ena(btb_mem_ena),
		.btb_mem_wea(btb_mem_wea),
		.btb_mem_addra(btb_mem_addra),
		.btb_mem_dina(btb_mem_dina),
		.btb_mem_douta(btb_mem_douta),
		
		.btb_mem_clkb(btb_mem_clkb),
		.btb_mem_enb(btb_mem_enb),
		.btb_mem_web(btb_mem_web),
		.btb_mem_addrb(btb_mem_addrb),
		.btb_mem_dinb(btb_mem_dinb),
		.btb_mem_doutb(btb_mem_doutb)
	);
	
	genvar btb_mem_i;
	generate
		for(btb_mem_i = 0;btb_mem_i < BTB_WAY_N;btb_mem_i = btb_mem_i + 1)
		begin:btb_mem_blk
			bram_true_dual_port #(
				.mem_width(BTB_MEM_WIDTH),
				.mem_depth(BTB_ENTRY_N),
				.INIT_FILE("no_init"),
				.read_write_mode("no_change"),
				.use_output_register("false"),
				.simulation_delay(SIM_DELAY)
			)btb_mem_u(
				.clk(clk),
				
				.ena(btb_mem_ena[btb_mem_i]),
				.wea(btb_mem_wea[btb_mem_i]),
				.addra(btb_mem_addra[btb_mem_i*16+15:btb_mem_i*16] | 32'h0000_0000),
				.dina(btb_mem_dina[btb_mem_i*BTB_MEM_WIDTH+BTB_MEM_WIDTH-1:btb_mem_i*BTB_MEM_WIDTH]),
				.douta(btb_mem_douta[btb_mem_i*BTB_MEM_WIDTH+BTB_MEM_WIDTH-1:btb_mem_i*BTB_MEM_WIDTH]),
				
				.enb(btb_mem_enb[btb_mem_i]),
				.web(btb_mem_web[btb_mem_i]),
				.addrb(btb_mem_addrb[btb_mem_i*16+15:btb_mem_i*16] | 32'h0000_0000),
				.dinb(btb_mem_dinb[btb_mem_i*BTB_MEM_WIDTH+BTB_MEM_WIDTH-1:btb_mem_i*BTB_MEM_WIDTH]),
				.doutb(btb_mem_doutb[btb_mem_i*BTB_MEM_WIDTH+BTB_MEM_WIDTH-1:btb_mem_i*BTB_MEM_WIDTH])
			);
		end
	endgenerate
	
endmodule
