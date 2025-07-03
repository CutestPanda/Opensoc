`timescale 1ns / 1ps
/********************************************************************
本模块: 带指令/数据存储器的小胖达RISC-V处理器核

描述:
仅用于仿真

注意：
无

协议:
无

作者: 陈家耀
日期: 2025/07/02
********************************************************************/


module panda_risc_v_sim #(
	parameter integer IMEM_DEPTH = 4096, // 指令存储器深度
	parameter integer DMEM_DEPTH = 4096, // 数据存储器深度
	parameter IMEM_INIT_FILE = "no_init", // 指令存储器的初始化文件路径
	parameter DMEM_INIT_FILE = "no_init", // 数据存储器的初始化文件路径
	parameter integer IBUS_ACCESS_TIMEOUT_TH = 16, // 指令总线访问超时周期数(0 -> 不设超时 | 正整数)
	parameter integer IBUS_OUTSTANDING_N = 4, // 指令总线滞外深度(1 | 2 | 4 | 8)
	parameter integer DBUS_ACCESS_TIMEOUT_TH = 1024, // 数据总线访问超时周期数(必须>=1)
	parameter integer GHR_WIDTH = 8, // 全局分支历史寄存器的位宽(<=16)
	parameter integer BTB_WAY_N = 2, // BTB路数(1 | 2 | 4)
	parameter integer BTB_ENTRY_N = 512, // BTB项数(<=65536)
	parameter integer RAS_ENTRY_N = 4, // 返回地址堆栈的条目数(2 | 4 | 8 | 16)
	parameter EN_SGN_PERIOD_MUL = "true", // 是否使用单周期乘法器
	parameter integer ROB_ENTRY_N = 8, // 重排序队列项数(4 | 8 | 16 | 32)
	parameter integer CSR_RW_RCD_SLOTS_N = 2, // CSR读写指令信息记录槽位数(2 | 4 | 8 | 16 | 32)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟
	input wire clk,
	// 外部复位输入
	input wire ext_resetn,
	
	// 软件复位请求
	input wire sw_reset,
	
	// 指令总线访问超时标志
	output wire ibus_timeout,
	// 数据总线访问超时标志
	output wire dbus_timeout,
	
	// 中断请求
	// 注意: 中断请求保持有效直到中断清零!
	input wire sw_itr_req, // 软件中断请求
	input wire tmr_itr_req, // 计时器中断请求
	input wire ext_itr_req // 外部中断请求
);
    
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
	
    // 系统复位输入
	wire sys_resetn;
	// 系统复位请求
	wire sys_reset_req;
    // 指令ICB主机
	wire[31:0] m_icb_cmd_inst_addr;
	wire m_icb_cmd_inst_read;
	wire[31:0] m_icb_cmd_inst_wdata;
	wire[3:0] m_icb_cmd_inst_wmask;
	wire m_icb_cmd_inst_valid;
	wire m_icb_cmd_inst_ready;
	wire[31:0] m_icb_rsp_inst_rdata;
	wire m_icb_rsp_inst_err;
	wire m_icb_rsp_inst_valid;
	wire m_icb_rsp_inst_ready;
	// 数据ICB主机
	wire[31:0] m_icb_cmd_data_addr;
	wire m_icb_cmd_data_read;
	wire[31:0] m_icb_cmd_data_wdata;
	wire[3:0] m_icb_cmd_data_wmask;
	wire m_icb_cmd_data_valid;
	wire m_icb_cmd_data_ready;
	wire[31:0] m_icb_rsp_data_rdata;
	wire m_icb_rsp_data_err;
	wire m_icb_rsp_data_valid;
	wire m_icb_rsp_data_ready;
	// BTB存储器
	// [端口A]
	wire[BTB_WAY_N-1:0] btb_mem_clka;
	wire[BTB_WAY_N-1:0] btb_mem_ena;
	wire[BTB_WAY_N-1:0] btb_mem_wea;
	wire[BTB_WAY_N*16-1:0] btb_mem_addra;
	wire[BTB_WAY_N*64-1:0] btb_mem_dina;
	wire[BTB_WAY_N*64-1:0] btb_mem_douta;
	// [端口B]
	wire[BTB_WAY_N-1:0] btb_mem_clkb;
	wire[BTB_WAY_N-1:0] btb_mem_enb;
	wire[BTB_WAY_N-1:0] btb_mem_web;
	wire[BTB_WAY_N*16-1:0] btb_mem_addrb;
	wire[BTB_WAY_N*64-1:0] btb_mem_dinb;
	wire[BTB_WAY_N*64-1:0] btb_mem_doutb;
	// 指令存储器主接口
	wire inst_ram_clk;
    wire inst_ram_rst;
    wire inst_ram_en;
    wire[3:0] inst_ram_wen;
    wire[29:0] inst_ram_addr;
    wire[31:0] inst_ram_din;
    wire[31:0] inst_ram_dout;
	// 数据存储器主接口
	wire data_ram_clk;
    wire data_ram_rst;
    wire data_ram_en;
    wire[3:0] data_ram_wen;
    wire[29:0] data_ram_addr;
    wire[31:0] data_ram_din;
    wire[31:0] data_ram_dout;
    
    panda_risc_v_reset #(
		.simulation_delay(SIM_DELAY)
	)panda_risc_v_reset_u(
		.clk(clk),
		
		.ext_resetn(ext_resetn),
		
		.sw_reset(sw_reset),
		
		.sys_resetn(sys_resetn),
		.sys_reset_req(sys_reset_req),
		.sys_reset_fns()
	);
	
	panda_risc_v_core #(
		.EN_INST_CMD_FWD("false"),
		.EN_INST_RSP_BCK("false"),
		.EN_DATA_CMD_FWD("false"),
		.EN_DATA_RSP_BCK("false"),
		.IMEM_BASEADDR(32'h0000_0000),
		.IMEM_ADDR_RANGE(IMEM_DEPTH * 4),
		.DM_REGS_BASEADDR(32'hFFFF_F800),
		.DM_REGS_ADDR_RANGE(1024),
		.IBUS_ACCESS_TIMEOUT_TH(IBUS_ACCESS_TIMEOUT_TH),
		.IBUS_OUTSTANDING_N(IBUS_OUTSTANDING_N),
		.DBUS_ACCESS_TIMEOUT_TH(DBUS_ACCESS_TIMEOUT_TH),
		.GHR_WIDTH(GHR_WIDTH),
		.BTB_WAY_N(BTB_WAY_N),
		.BTB_ENTRY_N(BTB_ENTRY_N),
		.RAS_ENTRY_N(RAS_ENTRY_N),
		.DEBUG_SUPPORTED("false"),
		.DEBUG_ROM_ADDR(32'h0000_0600),
		.DSCRATCH_N(2),
		.EN_EXPT_VEC_VECTORED("false"),
		.EN_PERF_MONITOR("true"),
		.EN_SGN_PERIOD_MUL(EN_SGN_PERIOD_MUL),
		.ROB_ENTRY_N(ROB_ENTRY_N),
		.CSR_RW_RCD_SLOTS_N(CSR_RW_RCD_SLOTS_N),
		.SIM_DELAY(SIM_DELAY)
	)panda_risc_v_u(
		.aclk(clk),
		.aresetn(sys_resetn),
		
		.sys_reset_req(sys_reset_req),
		.rst_pc(32'h0000_0000),
		
		.m_icb_cmd_inst_addr(m_icb_cmd_inst_addr),
		.m_icb_cmd_inst_read(m_icb_cmd_inst_read),
		.m_icb_cmd_inst_wdata(m_icb_cmd_inst_wdata),
		.m_icb_cmd_inst_wmask(m_icb_cmd_inst_wmask),
		.m_icb_cmd_inst_valid(m_icb_cmd_inst_valid),
		.m_icb_cmd_inst_ready(m_icb_cmd_inst_ready),
		.m_icb_rsp_inst_rdata(m_icb_rsp_inst_rdata),
		.m_icb_rsp_inst_err(m_icb_rsp_inst_err),
		.m_icb_rsp_inst_valid(m_icb_rsp_inst_valid),
		.m_icb_rsp_inst_ready(m_icb_rsp_inst_ready),
		
		.m_icb_cmd_data_addr(m_icb_cmd_data_addr),
		.m_icb_cmd_data_read(m_icb_cmd_data_read),
		.m_icb_cmd_data_wdata(m_icb_cmd_data_wdata),
		.m_icb_cmd_data_wmask(m_icb_cmd_data_wmask),
		.m_icb_cmd_data_valid(m_icb_cmd_data_valid),
		.m_icb_cmd_data_ready(m_icb_cmd_data_ready),
		.m_icb_rsp_data_rdata(m_icb_rsp_data_rdata),
		.m_icb_rsp_data_err(m_icb_rsp_data_err),
		.m_icb_rsp_data_valid(m_icb_rsp_data_valid),
		.m_icb_rsp_data_ready(m_icb_rsp_data_ready),
		
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
		.btb_mem_doutb(btb_mem_doutb),
		
		.sw_itr_req(sw_itr_req),
		.tmr_itr_req(tmr_itr_req),
		.ext_itr_req(ext_itr_req),
		
		.dbg_halt_req(1'b0),
		.dbg_halt_on_reset_req(1'b0),
		
		.clr_inst_buf_while_suppressing(),
		.ibus_timeout(ibus_timeout),
		.dbus_timeout(dbus_timeout)
	);
	
	icb_sram_ctrler #(
		.en_unaligned_transfer("true"),
		.wt_trans_imdt_resp("false"),
		.simulation_delay(SIM_DELAY)
	)icb_inst_ram_ctrler_u(
		.s_icb_aclk(clk),
		.s_icb_aresetn(sys_resetn),
		
		.s_icb_cmd_addr(m_icb_cmd_inst_addr),
		.s_icb_cmd_read(m_icb_cmd_inst_read),
		.s_icb_cmd_wdata(m_icb_cmd_inst_wdata),
		.s_icb_cmd_wmask(m_icb_cmd_inst_wmask),
		.s_icb_cmd_valid(m_icb_cmd_inst_valid),
		.s_icb_cmd_ready(m_icb_cmd_inst_ready),
		.s_icb_rsp_rdata(m_icb_rsp_inst_rdata),
		.s_icb_rsp_err(m_icb_rsp_inst_err),
		.s_icb_rsp_valid(m_icb_rsp_inst_valid),
		.s_icb_rsp_ready(m_icb_rsp_inst_ready),
		
		.bram_clk(inst_ram_clk),
		.bram_rst(inst_ram_rst),
		.bram_en(inst_ram_en),
		.bram_wen(inst_ram_wen),
		.bram_addr(inst_ram_addr),
		.bram_din(inst_ram_din),
		.bram_dout(inst_ram_dout)
	);
	
	icb_sram_ctrler #(
		.en_unaligned_transfer("true"),
		.wt_trans_imdt_resp("false"),
		.simulation_delay(SIM_DELAY)
	)icb_data_ram_ctrler_u(
		.s_icb_aclk(clk),
		.s_icb_aresetn(sys_resetn),
		
		.s_icb_cmd_addr(m_icb_cmd_data_addr),
		.s_icb_cmd_read(m_icb_cmd_data_read),
		.s_icb_cmd_wdata(m_icb_cmd_data_wdata),
		.s_icb_cmd_wmask(m_icb_cmd_data_wmask),
		.s_icb_cmd_valid(m_icb_cmd_data_valid),
		.s_icb_cmd_ready(m_icb_cmd_data_ready),
		.s_icb_rsp_rdata(m_icb_rsp_data_rdata),
		.s_icb_rsp_err(m_icb_rsp_data_err),
		.s_icb_rsp_valid(m_icb_rsp_data_valid),
		.s_icb_rsp_ready(m_icb_rsp_data_ready),
		
		.bram_clk(data_ram_clk),
		.bram_rst(data_ram_rst),
		.bram_en(data_ram_en),
		.bram_wen(data_ram_wen),
		.bram_addr(data_ram_addr),
		.bram_din(data_ram_din),
		.bram_dout(data_ram_dout)
	);
	
	bram_single_port #(
		.style("LOW_LATENCY"),
		.rw_mode("read_first"),
		.mem_width(32),
		.mem_depth(IMEM_DEPTH),
		.INIT_FILE(IMEM_INIT_FILE),
		.byte_write_mode("true"),
		.simulation_delay(SIM_DELAY)
	)inst_ram_single_port_u(
		.clk(inst_ram_clk),
		
		.en(inst_ram_en),
		.wen(inst_ram_wen),
		.addr(inst_ram_addr[clogb2(IMEM_DEPTH-1):0]),
		.din(inst_ram_din),
		.dout(inst_ram_dout)
	);
	
	bram_single_port #(
		.style("LOW_LATENCY"),
		.rw_mode("read_first"),
		.mem_width(32),
		.mem_depth(DMEM_DEPTH),
		.INIT_FILE(DMEM_INIT_FILE),
		.byte_write_mode("true"),
		.simulation_delay(SIM_DELAY)
	)data_ram_single_port_u(
		.clk(data_ram_clk),
		
		.en(data_ram_en),
		.wen(data_ram_wen),
		.addr(data_ram_addr[clogb2(DMEM_DEPTH-1):0]),
		.din(data_ram_din),
		.dout(data_ram_dout)
	);
	
	genvar btb_mem_i;
	generate
		for(btb_mem_i = 0;btb_mem_i < BTB_WAY_N;btb_mem_i = btb_mem_i + 1)
		begin:btb_mem_blk
			bram_true_dual_port #(
				.mem_width(64),
				.mem_depth(BTB_ENTRY_N),
				.INIT_FILE("no_init"),
				.read_write_mode("read_first"),
				.use_output_register("false"),
				.simulation_delay(SIM_DELAY)
			)btb_mem_u(
				.clk(clk),
				
				.ena(btb_mem_ena[btb_mem_i]),
				.wea(btb_mem_wea[btb_mem_i]),
				.addra(btb_mem_addra[btb_mem_i*16+15:btb_mem_i*16]),
				.dina(btb_mem_dina[btb_mem_i*64+63:btb_mem_i*64]),
				.douta(btb_mem_douta[btb_mem_i*64+63:btb_mem_i*64]),
				
				.enb(btb_mem_enb[btb_mem_i]),
				.web(btb_mem_web[btb_mem_i]),
				.addrb(btb_mem_addrb[btb_mem_i*16+15:btb_mem_i*16]),
				.dinb(btb_mem_dinb[btb_mem_i*64+63:btb_mem_i*64]),
				.doutb(btb_mem_doutb[btb_mem_i*64+63:btb_mem_i*64])
			);
		end
	endgenerate

endmodule
