`timescale 1ns / 1ps

module tb_icb_dcache();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer CACHE_WAY_N = 4; // 缓存路数(1 | 2 | 4 | 8)
	localparam integer CACHE_ENTRY_N = 16; // 缓存存储条目数
	localparam integer CACHE_LINE_WORD_N = 4; // 每个缓存行的字数(1 | 2 | 4 | 8 | 16)
	localparam integer CACHE_TAG_WIDTH = 4; // 缓存标签位数
	localparam integer WBUF_ITEM_N = 4; // 写缓存最多可存的缓存行个数(1~8)
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
	
	/** 接口 **/
	ICB #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32)) m_icb_inst(.clk(clk), .rst_n(rst_n));
	ICB #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32)) s_icb_inst(.clk(clk), .rst_n(rst_n));
	
	/** 任务 **/
	task drive_m_icb_cmd_trans(input bit[31:0] addr, input bit is_read, 
		input bit[31:0] wdata, input bit[3:0] wmask, input int unsigned wait_n);
		repeat(wait_n)
			@(posedge clk iff rst_n);
		
		m_icb_inst.master.cb_master.cmd_addr <= addr;
		m_icb_inst.master.cb_master.cmd_read <= is_read;
		m_icb_inst.master.cb_master.cmd_wdata <= wdata;
		m_icb_inst.master.cb_master.cmd_wmask <= wmask;
		m_icb_inst.master.cb_master.cmd_valid <= 1'b1;
		
		do
		begin
			@(posedge clk iff rst_n);
		end
		while(!(m_icb_inst.master.cmd_valid & m_icb_inst.master.cmd_ready));
		
		m_icb_inst.master.cb_master.cmd_addr <= 32'dx;
		m_icb_inst.master.cb_master.cmd_read <= 1'bx;
		m_icb_inst.master.cb_master.cmd_wdata <= 32'dx;
		m_icb_inst.master.cb_master.cmd_wmask <= 4'bxxxx;
		m_icb_inst.master.cb_master.cmd_valid <= 1'b0;
	endtask
	
	task drive_m_icb_rsp_trans(input int unsigned wait_n);
		repeat(wait_n)
			@(posedge clk iff rst_n);
		
		m_icb_inst.master.cb_master.rsp_ready <= 1'b1;
		
		do
		begin
			@(posedge clk iff rst_n);
		end
		while(!(m_icb_inst.master.rsp_valid & m_icb_inst.master.rsp_ready));
		
		m_icb_inst.master.cb_master.rsp_ready <= 1'b0;
	endtask
	
	/** 测试激励 **/
	initial
	begin
		m_icb_inst.master.cb_master.cmd_addr <= 32'dx;
		m_icb_inst.master.cb_master.cmd_read <= 1'bx;
		m_icb_inst.master.cb_master.cmd_wdata <= 32'dx;
		m_icb_inst.master.cb_master.cmd_wmask <= 4'bxxxx;
		m_icb_inst.master.cb_master.cmd_valid <= 1'b0;
		
		/*
		task drive_m_icb_cmd_trans(input bit[31:0] addr, input bit is_read, 
			input bit[31:0] wdata, input bit[3:0] wmask, input int unsigned wait_n);
		*/
		// 读未命中
		drive_m_icb_cmd_trans((CACHE_ENTRY_N*CACHE_LINE_WORD_N*4)*0 + (CACHE_LINE_WORD_N*4)*0 + 4*0, 1'b1, 32'dx, 4'bxxxx, 2);
		// 读命中
		drive_m_icb_cmd_trans((CACHE_ENTRY_N*CACHE_LINE_WORD_N*4)*0 + (CACHE_LINE_WORD_N*4)*0 + 4*1, 1'b1, 32'dx, 4'bxxxx, 0);
		// 读未命中
		drive_m_icb_cmd_trans((CACHE_ENTRY_N*CACHE_LINE_WORD_N*4)*0 + (CACHE_LINE_WORD_N*4)*1 + 4*0, 1'b1, 32'dx, 4'bxxxx, 0);
		// 读命中
		drive_m_icb_cmd_trans((CACHE_ENTRY_N*CACHE_LINE_WORD_N*4)*0 + (CACHE_LINE_WORD_N*4)*1 + 4*2, 1'b1, 32'dx, 4'bxxxx, 2);
		// 读命中
		drive_m_icb_cmd_trans((CACHE_ENTRY_N*CACHE_LINE_WORD_N*4)*0 + (CACHE_LINE_WORD_N*4)*1 + 4*0, 1'b1, 32'dx, 4'bxxxx, 0);
		// 读命中
		drive_m_icb_cmd_trans((CACHE_ENTRY_N*CACHE_LINE_WORD_N*4)*0 + (CACHE_LINE_WORD_N*4)*1 + 4*1, 1'b1, 32'dx, 4'bxxxx, 0);
		// 读命中
		drive_m_icb_cmd_trans((CACHE_ENTRY_N*CACHE_LINE_WORD_N*4)*0 + (CACHE_LINE_WORD_N*4)*1 + 4*2, 1'b1, 32'dx, 4'bxxxx, 0);
		// 读命中
		drive_m_icb_cmd_trans((CACHE_ENTRY_N*CACHE_LINE_WORD_N*4)*0 + (CACHE_LINE_WORD_N*4)*1 + 4*3, 1'b1, 32'dx, 4'bxxxx, 0);
		// 写未命中, 不需要写回
		drive_m_icb_cmd_trans((CACHE_ENTRY_N*CACHE_LINE_WORD_N*4)*1 + (CACHE_LINE_WORD_N*4)*0 + 4*0, 1'b0, 32'h58_aa_ba_10, 4'b1000, 0);
		// 写未命中, 不需要写回
		drive_m_icb_cmd_trans((CACHE_ENTRY_N*CACHE_LINE_WORD_N*4)*2 + (CACHE_LINE_WORD_N*4)*0 + 4*0, 1'b0, 32'h90_f3_11_fe, 4'b0100, 0);
		// 写未命中, 不需要写回
		drive_m_icb_cmd_trans((CACHE_ENTRY_N*CACHE_LINE_WORD_N*4)*3 + (CACHE_LINE_WORD_N*4)*0 + 4*0, 1'b0, 32'h90_f3_11_fe, 4'b0010, 0);
		// 写未命中, 不需要写回
		drive_m_icb_cmd_trans((CACHE_ENTRY_N*CACHE_LINE_WORD_N*4)*4 + (CACHE_LINE_WORD_N*4)*0 + 4*0, 1'b0, 32'h1e_32_fe_86, 4'b0001, 0);
		// 写命中
		drive_m_icb_cmd_trans((CACHE_ENTRY_N*CACHE_LINE_WORD_N*4)*1 + (CACHE_LINE_WORD_N*4)*0 + 4*0, 1'b0, 32'h12_15_19_1e, 4'b1111, 0);
		// 写未命中, 需要写回
		drive_m_icb_cmd_trans((CACHE_ENTRY_N*CACHE_LINE_WORD_N*4)*5 + (CACHE_LINE_WORD_N*4)*0 + 4*0, 1'b0, 32'h23_2e_34_5f, 4'b1111, 0);
		// 读命中
		drive_m_icb_cmd_trans((CACHE_ENTRY_N*CACHE_LINE_WORD_N*4)*1 + (CACHE_LINE_WORD_N*4)*0 + 4*2, 1'b1, 32'dx, 4'bxxxx, 4);
		// 读命中
		drive_m_icb_cmd_trans((CACHE_ENTRY_N*CACHE_LINE_WORD_N*4)*1 + (CACHE_LINE_WORD_N*4)*0 + 4*0, 1'b1, 32'dx, 4'bxxxx, 0);
	end
	
	initial
	begin
		m_icb_inst.master.cb_master.rsp_ready <= 1'b0;
		
		// task drive_m_icb_rsp_trans(input int unsigned wait_n);
		repeat(50)
		begin
			// automatic int unsigned wait_n = $urandom_range(0, 2);
			automatic int unsigned wait_n = 0;
			
			drive_m_icb_rsp_trans(wait_n);
		end
	end
	
	/** 仿真模型 **/
	// 数据存储器接口
	wire[CACHE_WAY_N-1:0] data_sram_clk_a;
	wire[CACHE_WAY_N*4*CACHE_LINE_WORD_N-1:0] data_sram_en_a;
	wire[CACHE_WAY_N*4*CACHE_LINE_WORD_N-1:0] data_sram_wen_a;
	wire[CACHE_WAY_N*4*CACHE_LINE_WORD_N*32-1:0] data_sram_addr_a;
	wire[CACHE_WAY_N*4*CACHE_LINE_WORD_N*8-1:0] data_sram_din_a;
	wire[CACHE_WAY_N*4*CACHE_LINE_WORD_N*8-1:0] data_sram_dout_a;
	// 标签存储器接口
	wire[CACHE_WAY_N-1:0] tag_sram_clk_a;
	wire[CACHE_WAY_N-1:0] tag_sram_en_a;
	wire[CACHE_WAY_N-1:0] tag_sram_wen_a;
	wire[CACHE_WAY_N*32-1:0] tag_sram_addr_a;
	wire[CACHE_WAY_N*(CACHE_TAG_WIDTH+2)-1:0] tag_sram_din_a; // {dirty(1位), valid(1位), tag(CACHE_TAG_WIDTH位)}
	wire[CACHE_WAY_N*(CACHE_TAG_WIDTH+2)-1:0] tag_sram_dout_a; // {dirty(1位), valid(1位), tag(CACHE_TAG_WIDTH位)}
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
	
	genvar data_sram_i;
	generate
		for(data_sram_i = 0;data_sram_i < CACHE_WAY_N*4*CACHE_LINE_WORD_N;data_sram_i = data_sram_i + 1)
		begin:data_sram_blk
			bram_single_port #(
				.style("LOW_LATENCY"),
				.rw_mode("read_first"),
				.mem_width(8),
				.mem_depth(CACHE_ENTRY_N),
				.INIT_FILE("no_init"),
				.byte_write_mode("false"),
				.simulation_delay(simulation_delay)
			)data_sram_u(
				.clk(data_sram_clk_a[data_sram_i/(4*CACHE_LINE_WORD_N)]),
				
				.en(data_sram_en_a[data_sram_i]),
				.wen(data_sram_wen_a[data_sram_i]),
				.addr(data_sram_addr_a[data_sram_i*32+31:data_sram_i*32]),
				.din(data_sram_din_a[data_sram_i*8+7:data_sram_i*8]),
				.dout(data_sram_dout_a[data_sram_i*8+7:data_sram_i*8])
			);
		end
	endgenerate
	
	genvar tag_sram_i;
	generate
		for(tag_sram_i = 0;tag_sram_i < CACHE_WAY_N;tag_sram_i = tag_sram_i + 1)
		begin:tag_sram_blk
			bram_single_port #(
				.style("LOW_LATENCY"),
				.rw_mode("read_first"),
				.mem_width(CACHE_TAG_WIDTH+2),
				.mem_depth(CACHE_ENTRY_N),
				.INIT_FILE(""),
				.byte_write_mode("false"),
				.simulation_delay(simulation_delay)
			)tag_sram_u(
				.clk(tag_sram_clk_a[tag_sram_i]),
				
				.en(tag_sram_en_a[tag_sram_i]),
				.wen(tag_sram_wen_a[tag_sram_i]),
				.addr(tag_sram_addr_a[tag_sram_i*32+31:tag_sram_i*32]),
				.din(tag_sram_din_a[(tag_sram_i+1)*(CACHE_TAG_WIDTH+2)-1:tag_sram_i*(CACHE_TAG_WIDTH+2)]),
				.dout(tag_sram_dout_a[(tag_sram_i+1)*(CACHE_TAG_WIDTH+2)-1:tag_sram_i*(CACHE_TAG_WIDTH+2)])
			);
		end
	endgenerate
	
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(24),
		.mem_depth(CACHE_ENTRY_N),
		.INIT_FILE(""),
		.simulation_delay(simulation_delay)
	)hot_sram_u(
		.clk(hot_sram_clk_a),
		
		.wen_a(hot_sram_wen_a),
		.addr_a(hot_sram_waddr_a),
		.din_a(hot_sram_din_a),
		
		.ren_b(hot_sram_ren_b),
		.addr_b(hot_sram_raddr_b),
		.dout_b(hot_sram_dout_b)
	);
	
	s_icb_memory_map_model #(
		.out_drive_t(simulation_delay),
		.addr_width(32),
		.data_width(32),
		.memory_map_depth(1024 * 64)
	)s_icb_memory_map_model_u(
		.s_icb_if(s_icb_inst.slave)
	);
	
	initial
	begin
		for(int i = 0;i < 1024 * 64;i++)
		begin
			s_icb_memory_map_model_u.mem[i] = i + 1;
		end
	end
	
	/** 待测模块 **/
	// 处理器核ICB从机
	// [命令通道]
	wire[31:0] s_icb_cmd_addr;
	wire s_icb_cmd_read;
	wire[31:0] s_icb_cmd_wdata;
	wire[3:0] s_icb_cmd_wmask;
	wire s_icb_cmd_valid;
	wire s_icb_cmd_ready;
	// [响应通道]
	wire[31:0] s_icb_rsp_rdata;
	wire s_icb_rsp_err; // const -> 1'b0
	wire s_icb_rsp_valid;
	wire s_icb_rsp_ready;
	// 访问下级存储器ICB主机
	// [命令通道]
	wire[31:0] m_icb_cmd_addr;
	wire m_icb_cmd_read;
	wire[31:0] m_icb_cmd_wdata;
	wire[3:0] m_icb_cmd_wmask;
	wire m_icb_cmd_valid;
	wire m_icb_cmd_ready;
	// [响应通道]
	wire[31:0] m_icb_rsp_rdata;
	wire m_icb_rsp_err; // ignored
	wire m_icb_rsp_valid;
	wire m_icb_rsp_ready;
	
	assign s_icb_cmd_addr = m_icb_inst.cmd_addr;
	assign s_icb_cmd_read = m_icb_inst.cmd_read;
	assign s_icb_cmd_wdata = m_icb_inst.cmd_wdata;
	assign s_icb_cmd_wmask = m_icb_inst.cmd_wmask;
	assign s_icb_cmd_valid = m_icb_inst.cmd_valid;
	assign m_icb_inst.cmd_ready = s_icb_cmd_ready;
	assign m_icb_inst.rsp_rdata = s_icb_rsp_rdata;
	assign m_icb_inst.rsp_err = s_icb_rsp_err;
	assign m_icb_inst.rsp_valid = s_icb_rsp_valid;
	assign s_icb_rsp_ready = m_icb_inst.rsp_ready;
	
	assign s_icb_inst.cmd_addr = m_icb_cmd_addr;
	assign s_icb_inst.cmd_read = m_icb_cmd_read;
	assign s_icb_inst.cmd_wdata = m_icb_cmd_wdata;
	assign s_icb_inst.cmd_wmask = m_icb_cmd_wmask;
	assign s_icb_inst.cmd_valid = m_icb_cmd_valid;
	assign m_icb_cmd_ready = s_icb_inst.cmd_ready;
	assign m_icb_rsp_rdata = s_icb_inst.rsp_rdata;
	assign m_icb_rsp_err = s_icb_inst.rsp_err;
	assign m_icb_rsp_valid = s_icb_inst.rsp_valid;
	assign s_icb_inst.rsp_ready = m_icb_rsp_ready;
	
	icb_dcache #(
		.CACHE_WAY_N(CACHE_WAY_N),
		.CACHE_ENTRY_N(CACHE_ENTRY_N),
		.CACHE_LINE_WORD_N(CACHE_LINE_WORD_N),
		.CACHE_TAG_WIDTH(CACHE_TAG_WIDTH),
		.WBUF_ITEM_N(WBUF_ITEM_N),
		.SIM_DELAY(simulation_delay)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		
		.s_icb_cmd_addr(s_icb_cmd_addr),
		.s_icb_cmd_read(s_icb_cmd_read),
		.s_icb_cmd_wdata(s_icb_cmd_wdata),
		.s_icb_cmd_wmask(s_icb_cmd_wmask),
		.s_icb_cmd_valid(s_icb_cmd_valid),
		.s_icb_cmd_ready(s_icb_cmd_ready),
		.s_icb_rsp_rdata(s_icb_rsp_rdata),
		.s_icb_rsp_err(s_icb_rsp_err),
		.s_icb_rsp_valid(s_icb_rsp_valid),
		.s_icb_rsp_ready(s_icb_rsp_ready),
		
		.m_icb_cmd_addr(m_icb_cmd_addr),
		.m_icb_cmd_read(m_icb_cmd_read),
		.m_icb_cmd_wdata(m_icb_cmd_wdata),
		.m_icb_cmd_wmask(m_icb_cmd_wmask),
		.m_icb_cmd_valid(m_icb_cmd_valid),
		.m_icb_cmd_ready(m_icb_cmd_ready),
		.m_icb_rsp_rdata(m_icb_rsp_rdata),
		.m_icb_rsp_err(m_icb_rsp_err),
		.m_icb_rsp_valid(m_icb_rsp_valid),
		.m_icb_rsp_ready(m_icb_rsp_ready),
		
		.data_sram_clk_a(data_sram_clk_a),
		.data_sram_en_a(data_sram_en_a),
		.data_sram_wen_a(data_sram_wen_a),
		.data_sram_addr_a(data_sram_addr_a),
		.data_sram_din_a(data_sram_din_a),
		.data_sram_dout_a(data_sram_dout_a),
		
		.tag_sram_clk_a(tag_sram_clk_a),
		.tag_sram_en_a(tag_sram_en_a),
		.tag_sram_wen_a(tag_sram_wen_a),
		.tag_sram_addr_a(tag_sram_addr_a),
		.tag_sram_din_a(tag_sram_din_a),
		.tag_sram_dout_a(tag_sram_dout_a),
		
		.hot_sram_clk_a(hot_sram_clk_a),
		.hot_sram_wen_a(hot_sram_wen_a),
		.hot_sram_waddr_a(hot_sram_waddr_a),
		.hot_sram_din_a(hot_sram_din_a),
		.hot_sram_clk_b(hot_sram_clk_b),
		.hot_sram_ren_b(hot_sram_ren_b),
		.hot_sram_raddr_b(hot_sram_raddr_b),
		.hot_sram_dout_b(hot_sram_dout_b)
	);
	
endmodule
