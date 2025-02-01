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
日期: 2025/02/01
********************************************************************/


module panda_risc_v_sim #(
	parameter integer IMEM_DEPTH = 4096, // 指令存储器深度
	parameter integer DMEM_DEPTH = 4096, // 数据存储器深度
	parameter IMEM_INIT_FILE = "no_init", // 指令存储器的初始化文件路径
	parameter DMEM_INIT_FILE = "no_init", // 数据存储器的初始化文件路径
	parameter en_alu_csr_rw_bypass = "true", // 是否使能ALU/CSR原子读写单元的数据旁路
	parameter imem_baseaddr = 32'h0000_0000, // 指令存储器基址
	parameter integer imem_addr_range = 16 * 1024, // 指令存储器地址区间长度
	parameter en_inst_cmd_fwd = "false", // 使能指令ICB主机命令通道前向寄存器
	parameter en_inst_rsp_bck = "false", // 使能指令ICB主机响应通道后向寄存器
	parameter en_data_cmd_fwd = "true", // 使能数据ICB主机命令通道前向寄存器
	parameter en_data_rsp_bck = "true", // 使能数据ICB主机响应通道后向寄存器
	parameter sgn_period_mul = "true", // 是否使用单周期乘法器
	parameter real simulation_delay = 1 // 仿真延时
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
	wire m_icb_cmd_inst_read; // const -> 1'b1
	wire[31:0] m_icb_cmd_inst_wdata; // const -> 32'hxxxx_xxxx
	wire[3:0] m_icb_cmd_inst_wmask; // const -> 4'b0000
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
		.simulation_delay(simulation_delay)
	)panda_risc_v_reset_u(
		.clk(clk),
		
		.ext_resetn(ext_resetn),
		.sw_reset(sw_reset),
		
		.sys_resetn(sys_resetn),
		.sys_reset_req(sys_reset_req)
	);
	
	panda_risc_v #(
		.imem_access_timeout_th(16),
		.inst_addr_alignment_width(32),
		.dbus_access_timeout_th(16),
		.icb_zero_latency_supported("false"),
		.en_expt_vec_vectored("true"),
		.en_performance_monitor("true"),
		.init_mtvec_base(30'd0),
		.init_mcause_interrupt(1'b0),
		.init_mcause_exception_code(31'd16),
		.init_misa_mxl(2'b01),
		.init_misa_extensions(26'b00_0000_0000_0001_0001_0000_0000),
		.init_mvendorid_bank(25'h0_00_00_00),
		.init_mvendorid_offset(7'h00),
		.init_marchid(32'h00_00_00_00),
		.init_mimpid(32'h31_2E_30_30),
		.init_mhartid(32'h00_00_00_00),
		.dpc_trace_inst_n(16),
		.inst_id_width(5),
		.en_alu_csr_rw_bypass(en_alu_csr_rw_bypass),
		.imem_baseaddr(imem_baseaddr),
		.imem_addr_range(imem_addr_range),
		.en_inst_cmd_fwd(en_inst_cmd_fwd),
		.en_inst_rsp_bck(en_inst_rsp_bck),
		.en_data_cmd_fwd(en_data_cmd_fwd),
		.en_data_rsp_bck(en_data_rsp_bck),
		.sgn_period_mul(sgn_period_mul),
		.simulation_delay(simulation_delay)
	)panda_risc_v_u(
		.clk(clk),
		.sys_resetn(sys_resetn),
		
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
		
		.ibus_timeout(ibus_timeout),
		.dbus_timeout(dbus_timeout),
		
		.sw_itr_req(sw_itr_req),
		.tmr_itr_req(tmr_itr_req),
		.ext_itr_req(ext_itr_req)
	);
	
	icb_sram_ctrler #(
		.en_unaligned_transfer("true"),
		.wt_trans_imdt_resp("false"),
		.simulation_delay(simulation_delay)
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
		.simulation_delay(simulation_delay)
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
		.simulation_delay(simulation_delay)
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
		.simulation_delay(simulation_delay)
	)data_ram_single_port_u(
		.clk(data_ram_clk),
		
		.en(data_ram_en),
		.wen(data_ram_wen),
		.addr(data_ram_addr[clogb2(DMEM_DEPTH-1):0]),
		.din(data_ram_din),
		.dout(data_ram_dout)
	);

endmodule
