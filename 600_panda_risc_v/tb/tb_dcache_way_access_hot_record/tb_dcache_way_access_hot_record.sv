`timescale 1ns / 1ps

module tb_dcache_way_access_hot_record();
	
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
    end
    endfunction
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer CACHE_ENTRY_N = 512; // 缓存存储条目数
	localparam integer CACHE_WAY_N = 4; // 缓存路数(1 | 2 | 4 | 8)
	// 时钟和复位配置
	localparam real clk_p = 10.0; // 时钟周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 常量 **/
	localparam integer WID_WIDTH = 
		(CACHE_WAY_N == 1) ? 1:clogb2(CACHE_WAY_N); // 缓存路编号的位宽
	
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
	// 查询或更新热度
	reg hot_tb_en; // 热度表使能
	reg hot_tb_upd_en; // 热度表更新使能
	reg[31:0] cache_index; // 缓存项索引号
	reg[2:0] cache_access_wid; // 本次访问的缓存路编号
	reg to_init_hot_item; // 初始化热度项(标志)
	reg to_swp_lru_item; // 置换最近最少使用项(标志)
	wire[2:0] hot_tb_lru_wid; // 最近最少使用项的缓存路编号
	
	initial
	begin
		hot_tb_en <= # 1'b0;
		hot_tb_upd_en <= 1'b0;
		cache_index <= 32'dx;
		cache_access_wid <= 3'bxxx;
		to_init_hot_item <= # simulation_delay 1'bx;
		to_swp_lru_item <= # simulation_delay 1'bx;
		
		repeat(10)
		begin
			@(posedge clk iff rst_n);
		end
		
		hot_tb_en <= # simulation_delay 1'b1;
		hot_tb_upd_en <= # simulation_delay 1'b1;
		cache_index <= # simulation_delay 3;
		cache_access_wid <= # simulation_delay 0;
		to_init_hot_item <= # simulation_delay 1'b1;
		to_swp_lru_item <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		hot_tb_en <= # simulation_delay 1'b1;
		hot_tb_upd_en <= # simulation_delay 1'b0;
		cache_index <= # simulation_delay 3;
		cache_access_wid <= # simulation_delay 0;
		to_init_hot_item <= # simulation_delay 1'b0;
		to_swp_lru_item <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		hot_tb_en <= # simulation_delay 1'b1;
		hot_tb_upd_en <= # simulation_delay 1'b1;
		cache_index <= # simulation_delay 3;
		cache_access_wid <= # simulation_delay 0;
		to_init_hot_item <= # simulation_delay 1'b0;
		to_swp_lru_item <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		hot_tb_en <= # simulation_delay 1'b1;
		hot_tb_upd_en <= # simulation_delay 1'b0;
		cache_index <= # simulation_delay 3;
		cache_access_wid <= # simulation_delay 0;
		to_init_hot_item <= # simulation_delay 1'b0;
		to_swp_lru_item <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		hot_tb_en <= # simulation_delay 1'b1;
		hot_tb_upd_en <= # simulation_delay 1'b1;
		cache_index <= # simulation_delay 3;
		cache_access_wid <= # simulation_delay 2;
		to_init_hot_item <= # simulation_delay 1'b0;
		to_swp_lru_item <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		hot_tb_en <= # simulation_delay 1'b1;
		hot_tb_upd_en <= # simulation_delay 1'b0;
		cache_index <= # simulation_delay 3;
		cache_access_wid <= # simulation_delay 2;
		to_init_hot_item <= # simulation_delay 1'b0;
		to_swp_lru_item <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		hot_tb_en <= # simulation_delay 1'b1;
		hot_tb_upd_en <= # simulation_delay 1'b1;
		cache_index <= # simulation_delay 3;
		cache_access_wid <= # simulation_delay 0;
		to_init_hot_item <= # simulation_delay 1'b0;
		to_swp_lru_item <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		hot_tb_en <= # simulation_delay 1'b1;
		hot_tb_upd_en <= # simulation_delay 1'b0;
		cache_index <= # simulation_delay 3;
		cache_access_wid <= # simulation_delay 0;
		to_init_hot_item <= # simulation_delay 1'b0;
		to_swp_lru_item <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		hot_tb_en <= # simulation_delay 1'b1;
		hot_tb_upd_en <= # simulation_delay 1'b1;
		cache_index <= # simulation_delay 3;
		cache_access_wid <= # simulation_delay 0;
		to_init_hot_item <= # simulation_delay 1'b0;
		to_swp_lru_item <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		hot_tb_en <= # simulation_delay 1'b1;
		hot_tb_upd_en <= # simulation_delay 1'b0;
		cache_index <= # simulation_delay 3;
		cache_access_wid <= # simulation_delay 0;
		to_init_hot_item <= # simulation_delay 1'b0;
		to_swp_lru_item <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		hot_tb_en <= # simulation_delay 1'b1;
		hot_tb_upd_en <= # simulation_delay 1'b1;
		cache_index <= # simulation_delay 3;
		cache_access_wid <= # simulation_delay 3;
		to_init_hot_item <= # simulation_delay 1'b0;
		to_swp_lru_item <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		hot_tb_en <= # simulation_delay 1'b1;
		hot_tb_upd_en <= # simulation_delay 1'b1;
		cache_index <= # simulation_delay 3;
		cache_access_wid <= # simulation_delay 0;
		to_init_hot_item <= # simulation_delay 1'b0;
		to_swp_lru_item <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		hot_tb_en <= # simulation_delay 1'b1;
		hot_tb_upd_en <= # simulation_delay 1'b1;
		cache_index <= # simulation_delay 3;
		cache_access_wid <= # simulation_delay 1;
		to_init_hot_item <= # simulation_delay 1'b0;
		to_swp_lru_item <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		hot_tb_en <= # simulation_delay 1'b0;
		hot_tb_upd_en <= # simulation_delay 1'b0;
		cache_index <= # simulation_delay 3;
		cache_access_wid <= # simulation_delay 0;
		to_init_hot_item <= # simulation_delay 1'b0;
		to_swp_lru_item <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		hot_tb_en <= # simulation_delay 1'b1;
		hot_tb_upd_en <= # simulation_delay 1'b0;
		cache_index <= # simulation_delay 3;
		cache_access_wid <= # simulation_delay 0;
		to_init_hot_item <= # simulation_delay 1'b0;
		to_swp_lru_item <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		hot_tb_en <= # simulation_delay 1'b1;
		hot_tb_upd_en <= # simulation_delay 1'b1;
		cache_index <= # simulation_delay 3;
		cache_access_wid <= # simulation_delay 0;
		to_init_hot_item <= # simulation_delay 1'b0;
		to_swp_lru_item <= # simulation_delay 1'b1;
		
		@(posedge clk iff rst_n);
		
		hot_tb_en <= # simulation_delay 1'b1;
		hot_tb_upd_en <= # simulation_delay 1'b0;
		cache_index <= # simulation_delay 3;
		cache_access_wid <= # simulation_delay 0;
		to_init_hot_item <= # simulation_delay 1'b0;
		to_swp_lru_item <= # simulation_delay 1'b0;
		
		@(posedge clk iff rst_n);
		
		hot_tb_en <= # simulation_delay 1'b0;
		hot_tb_upd_en <= # simulation_delay 1'b0;
		cache_index <= # simulation_delay 3;
		cache_access_wid <= # simulation_delay 0;
		to_init_hot_item <= # simulation_delay 1'b0;
		to_swp_lru_item <= # simulation_delay 1'b0;
	end
	
	/** 待测模块 **/
	// 记录存储器接口
	// [存储器写端口]
	wire hot_sram_clk_a;
	wire hot_sram_wen_a;
	wire[31:0] hot_sram_waddr_a;
	wire[23:0] hot_sram_din_a;
	// [存储器读端口]
	wire hot_sram_clk_b;
	wire hot_sram_ren_b;
	wire[31:0] hot_sram_raddr_b;
	wire[23:0] hot_sram_dout_b;
	
	initial
	begin
		for(int i = 0;i < CACHE_ENTRY_N;i++)
		begin
			bram_u.mem[i] = 0;
			
			/*
			for(int j = 0;j < CACHE_WAY_N;j++)
			begin
				bram_u.mem[i] <<= WID_WIDTH;
				bram_u.mem[i][WID_WIDTH-1:0] = (CACHE_WAY_N-1-j);
			end
			*/
		end
	end
	
	dcache_way_access_hot_record #(
		.CACHE_ENTRY_N(CACHE_ENTRY_N),
		.CACHE_WAY_N(CACHE_WAY_N),
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		
		.hot_tb_en(hot_tb_en),
		.hot_tb_upd_en(hot_tb_upd_en),
		.cache_index(cache_index),
		.cache_access_wid(cache_access_wid),
		.to_init_hot_item(to_init_hot_item),
		.to_swp_lru_item(to_swp_lru_item),
		.hot_tb_lru_wid(hot_tb_lru_wid),
		
		.hot_sram_clk_a(hot_sram_clk_a),
		.hot_sram_wen_a(hot_sram_wen_a),
		.hot_sram_waddr_a(hot_sram_waddr_a),
		.hot_sram_din_a(hot_sram_din_a),
		.hot_sram_clk_b(hot_sram_clk_b),
		.hot_sram_ren_b(hot_sram_ren_b),
		.hot_sram_raddr_b(hot_sram_raddr_b),
		.hot_sram_dout_b(hot_sram_dout_b)
	);
	
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(24),
		.mem_depth(CACHE_ENTRY_N),
		.INIT_FILE("no_init"),
		.simulation_delay(simulation_delay)
	)bram_u(
		.clk(hot_sram_clk_a),
		
		.wen_a(hot_sram_wen_a),
		.addr_a(hot_sram_waddr_a),
		.din_a(hot_sram_din_a),
		
		.ren_b(hot_sram_ren_b),
		.addr_b(hot_sram_raddr_b),
		.dout_b(hot_sram_dout_b)
	);
	
endmodule
