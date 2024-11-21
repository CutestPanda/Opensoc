`timescale 1ns / 1ps
/********************************************************************
本模块: 带指令存储器的取指单元

描述:
仅用于综合后时序评估

注意：
无

协议:
AXIS MASTER
REQ/GRANT

作者: 陈家耀
日期: 2024/11/17
********************************************************************/


module panda_risc_v_ifu_with_imem(
    // 时钟
	input wire clk,
	// 外部复位输入
	input wire ext_resetn,
	
	// 软件复位请求
	input wire sw_reset,
	
	// 冲刷请求
	input wire flush_req,
	input wire[31:0] flush_addr,
	
	// 数据相关性
	output wire[4:0] rs1_id, // rs1索引
	input wire rs1_raw_dpc, // RS1有RAW相关性(标志)
	
	// 专用于JALR指令的通用寄存器堆读端口
	input wire[31:0] jalr_x1_v, // 通用寄存器#1读结果
	// JALR指令读基址给出的通用寄存器读端口#0
	output wire jalr_reg_file_rd_p0_req, // 读请求
	output wire[4:0] jalr_rd_p0_addr, // 读地址
	input wire jalr_reg_file_rd_p0_grant, // 读许可
	input wire[31:0] jalr_reg_file_rd_p0_dout, // 读数据

	
	// 取指结果
	output wire[127:0] m_if_res_data, // {指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)}
	output wire[3:0] m_if_res_msg, // {是否预测跳转(1bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)}
	output wire m_if_res_valid,
	input wire m_if_res_ready,
	
	// 指令总线访问超时标志
	output wire ibus_timeout
);
    
    // 系统复位输入
	wire sys_resetn;
	// 系统复位请求
	wire sys_reset_req;
    // 指令ICB主机
	// 命令通道
	wire[31:0] m_icb_cmd_inst_addr;
	wire m_icb_cmd_inst_read; // const -> 1'b1
	wire[31:0] m_icb_cmd_inst_wdata; // const -> 32'hxxxx_xxxx
	wire[3:0] m_icb_cmd_inst_wmask; // const -> 4'b0000
	wire m_icb_cmd_inst_valid;
	wire m_icb_cmd_inst_ready;
	// 响应通道
	wire[31:0] m_icb_rsp_inst_rdata;
	wire m_icb_rsp_inst_err;
	wire m_icb_rsp_inst_valid;
	wire m_icb_rsp_inst_ready;
	// SRAM存储器主接口
	wire bram_clk;
    wire bram_rst;
    wire bram_en;
    wire[3:0] bram_wen;
    wire[29:0] bram_addr;
    wire[31:0] bram_din;
    wire[31:0] bram_dout;
    
    panda_risc_v_reset #(
		.simulation_delay(1)
	)panda_risc_v_reset_u(
		.clk(clk),
		
		.ext_resetn(ext_resetn),
		.sw_reset(sw_reset),
		
		.sys_resetn(sys_resetn),
		.sys_reset_req(sys_reset_req)
	);
	
	panda_risc_v_ifu #(
	    .imem_access_timeout_th(16),
	    .inst_addr_alignment_width(32),
	    .RST_PC(32'h0000_0000),
	    .simulation_delay(1)
	)panda_risc_v_ifu_u(
		.clk(clk),
		.sys_resetn(sys_resetn),
		
		.sys_reset_req(sys_reset_req),
		.flush_req(flush_req),
		.flush_addr(flush_addr),
		
		.rs1_id(rs1_id),
		.rs1_raw_dpc(rs1_raw_dpc),
		
		.jalr_x1_v(jalr_x1_v),
		.jalr_reg_file_rd_p0_req(jalr_reg_file_rd_p0_req),
		.jalr_rd_p0_addr(jalr_rd_p0_addr),
		.jalr_reg_file_rd_p0_grant(jalr_reg_file_rd_p0_grant),
		.jalr_reg_file_rd_p0_dout(jalr_reg_file_rd_p0_dout),
		
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
		
		.m_if_res_data(m_if_res_data),
		.m_if_res_msg(m_if_res_msg),
		.m_if_res_valid(m_if_res_valid),
		.m_if_res_ready(m_if_res_ready),
		
		.ibus_timeout(ibus_timeout)
	);
	
	icb_sram_ctrler #(
		.en_unaligned_transfer("false"),
		.wt_trans_imdt_resp("false"),
		.simulation_delay(1)
	)icb_sram_ctrler_u(
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
		
		.bram_clk(bram_clk),
		.bram_rst(bram_rst),
		.bram_en(bram_en),
		.bram_wen(bram_wen),
		.bram_addr(bram_addr),
		.bram_din(bram_din),
		.bram_dout(bram_dout)
	);
	
	bram_single_port #(
		.style("LOW_LATENCY"),
		.rw_mode("read_first"),
		.mem_width(32),
		.mem_depth(4096),
		.INIT_FILE("no_init"),
		.byte_write_mode("true"),
		.simulation_delay(1)
	)bram_single_port_u(
		.clk(bram_clk),
		
		.en(bram_en),
		.wen(bram_wen),
		.addr(bram_addr),
		.din(bram_din),
		.dout(bram_dout)
	);

endmodule
