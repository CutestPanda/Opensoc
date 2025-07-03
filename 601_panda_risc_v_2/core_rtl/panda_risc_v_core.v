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
/********************************************************************
本模块: 小胖达RISC-V处理器核

描述:


注意：


协议:
MEM MASTER
ICB MASTER

作者: 陈家耀
日期: 2025/07/02
********************************************************************/


module panda_risc_v_core #(
	// 指令/数据ICB主机AXIS寄存器片配置
	parameter EN_INST_CMD_FWD = "false", // 是否使能指令ICB主机命令通道前向寄存器
	parameter EN_INST_RSP_BCK = "false", // 是否使能指令ICB主机响应通道后向寄存器
	parameter EN_DATA_CMD_FWD = "false", // 是否使能数据ICB主机命令通道前向寄存器
	parameter EN_DATA_RSP_BCK = "false", // 是否使能数据ICB主机响应通道后向寄存器
	// 总线控制单元配置
	parameter IMEM_BASEADDR = 32'h0000_0000, // 指令存储器基址
	parameter integer IMEM_ADDR_RANGE = 32 * 1024, // 指令存储器地址区间长度
	parameter DM_REGS_BASEADDR = 32'hFFFF_F800, // DM寄存器区基址
	parameter integer DM_REGS_ADDR_RANGE = 1024, // DM寄存器区地址区间长度
	parameter integer IBUS_ACCESS_TIMEOUT_TH = 16, // 指令总线访问超时周期数(0 -> 不设超时 | 正整数)
	parameter integer IBUS_OUTSTANDING_N = 4, // 指令总线滞外深度(1 | 2 | 4 | 8)
	parameter integer DBUS_ACCESS_TIMEOUT_TH = 1024, // 数据总线访问超时周期数(必须>=1)
	// 分支预测配置
	parameter integer GHR_WIDTH = 8, // 全局分支历史寄存器的位宽(<=16)
	parameter integer BTB_WAY_N = 2, // BTB路数(1 | 2 | 4)
	parameter integer BTB_ENTRY_N = 512, // BTB项数(<=65536)
	parameter integer RAS_ENTRY_N = 4, // 返回地址堆栈的条目数(2 | 4 | 8 | 16)
	// 调试配置
	parameter DEBUG_SUPPORTED = "false", // 是否需要支持Debug
	parameter DEBUG_ROM_ADDR = 32'h0000_0600, // Debug ROM基地址
	parameter integer DSCRATCH_N = 2, // dscratch寄存器的个数(1 | 2)
	// CSR配置
	parameter EN_EXPT_VEC_VECTORED = "false", // 是否使能异常处理的向量链接模式
	parameter EN_PERF_MONITOR = "true", // 是否使能性能监测相关的CSR
	// 执行单元配置
	parameter EN_SGN_PERIOD_MUL = "true", // 是否使用单周期乘法器
	// ROB配置
	parameter integer ROB_ENTRY_N = 8, // 重排序队列项数(4 | 8 | 16 | 32)
	parameter integer CSR_RW_RCD_SLOTS_N = 2, // CSR读写指令信息记录槽位数(2 | 4 | 8 | 16 | 32)
	// 仿真配置
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 复位请求
	input wire sys_reset_req, // 系统复位请求
	input wire[31:0] rst_pc, // 复位时的PC
	
	// 指令ICB主机
	// [命令通道]
	output wire[31:0] m_icb_cmd_inst_addr,
	output wire m_icb_cmd_inst_read,
	output wire[31:0] m_icb_cmd_inst_wdata,
	output wire[3:0] m_icb_cmd_inst_wmask,
	output wire m_icb_cmd_inst_valid,
	input wire m_icb_cmd_inst_ready,
	// [响应通道]
	input wire[31:0] m_icb_rsp_inst_rdata,
	input wire m_icb_rsp_inst_err,
	input wire m_icb_rsp_inst_valid,
	output wire m_icb_rsp_inst_ready,
	
	// 数据ICB主机
	// 命令通道
	output wire[31:0] m_icb_cmd_data_addr,
	output wire m_icb_cmd_data_read,
	output wire[31:0] m_icb_cmd_data_wdata,
	output wire[3:0] m_icb_cmd_data_wmask,
	output wire m_icb_cmd_data_valid,
	input wire m_icb_cmd_data_ready,
	// 响应通道
	input wire[31:0] m_icb_rsp_data_rdata,
	input wire m_icb_rsp_data_err,
	input wire m_icb_rsp_data_valid,
	output wire m_icb_rsp_data_ready,
	
	// BTB存储器
	// [端口A]
	output wire[BTB_WAY_N-1:0] btb_mem_clka,
	output wire[BTB_WAY_N-1:0] btb_mem_ena,
	output wire[BTB_WAY_N-1:0] btb_mem_wea,
	output wire[BTB_WAY_N*16-1:0] btb_mem_addra,
	output wire[BTB_WAY_N*64-1:0] btb_mem_dina,
	input wire[BTB_WAY_N*64-1:0] btb_mem_douta,
	// [端口B]
	output wire[BTB_WAY_N-1:0] btb_mem_clkb,
	output wire[BTB_WAY_N-1:0] btb_mem_enb,
	output wire[BTB_WAY_N-1:0] btb_mem_web,
	output wire[BTB_WAY_N*16-1:0] btb_mem_addrb,
	output wire[BTB_WAY_N*64-1:0] btb_mem_dinb,
	input wire[BTB_WAY_N*64-1:0] btb_mem_doutb,
	
	// 中断请求
	// 注意: 中断请求保持有效直到中断清零!
	input wire sw_itr_req, // 软件中断请求
	input wire tmr_itr_req, // 计时器中断请求
	input wire ext_itr_req, // 外部中断请求
	
	// 调试请求
	input wire dbg_halt_req, // 来自调试器的暂停请求
	input wire dbg_halt_on_reset_req, // 来自调试器的复位释放后暂停请求
	
	// 错误标志
	output wire clr_inst_buf_while_suppressing, // 在镇压ICB事务时清空指令缓存(错误标志)
	output wire ibus_timeout, // 指令总线访问超时(错误标志)
	output wire dbus_timeout // 数据总线访问超时(错误标志)
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
	
	/** 内部配置 **/
	// 取指单元配置
	localparam EN_IF_REGS = "false"; // 是否启用取指缓存
	localparam integer INST_ADDR_ALIGNMENT_WIDTH = 32; // 指令地址对齐位宽(16 | 32)
	localparam integer IBUS_TID_WIDTH = 6; // 指令总线事务ID位宽(1~16)
	localparam integer IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH = 1; // 指令总线访问请求附带信息的位宽(正整数)
	localparam integer PRDT_MSG_WIDTH = 96; // 分支预测信息的位宽(正整数)
	localparam EN_PC_FOR_PHT_ADDR = "true"; // 生成PHT地址时是否考虑PC
	localparam EN_GHR_FOR_PHT_ADDR = "false"; // 生成PHT地址时是否考虑GHR
	localparam integer PC_TAG_WIDTH = 32 - clogb2(BTB_ENTRY_N) - 2; // PC标签的位宽
	localparam integer BTB_MEM_WIDTH = PC_TAG_WIDTH + 32 + 3 + 1 + 1 + 2; // BTB存储器的数据位宽
	// 取操作数和指令译码配置
	localparam integer LSN_FU_N = 5; // 要监听结果的执行单元的个数(正整数)
	localparam integer FU_ID_WIDTH = 3; // 执行单元ID位宽(1~16)
	localparam integer FU_RES_WIDTH = 32; // 执行单元结果位宽(正整数)
	localparam GEN_LS_ADDR_UNALIGNED_EXPT = "false"; // 是否考虑访存地址非对齐异常
	// BRU配置
	localparam EN_BRU_IMDT_FLUSH = "true"; // 是否启用立即冲刷
	// CSR初值配置
	localparam init_mtvec_base = 30'd0; // mtvec状态寄存器BASE域复位值
	localparam init_mcause_interrupt = 1'b0; // mcause状态寄存器Interrupt域复位值
	localparam init_mcause_exception_code = 31'd16; // mcause状态寄存器Exception Code域复位值
	localparam init_misa_mxl = 2'b01; // misa状态寄存器MXL域复位值
	localparam init_misa_extensions = 26'b00_0000_0000_0001_0001_0000_0000; // misa状态寄存器Extensions域复位值
	localparam init_mvendorid_bank = 25'h0_00_00_00; // mvendorid状态寄存器Bank域复位值
	localparam init_mvendorid_offset = 7'h00; // mvendorid状态寄存器Offset域复位值
	localparam init_marchid = 32'h00_00_00_00; // marchid状态寄存器复位值
	localparam init_mimpid = 32'h31_2E_30_30; // mimpid状态寄存器复位值
	localparam init_mhartid = 32'h00_00_00_00; // mhartid状态寄存器复位值
	// ROB配置
	localparam integer FU_ERR_WIDTH = 3; // 执行单元错误码位宽(正整数)
	localparam EN_ARCT_REG_POS_TB = "true"; // 是否使用逻辑寄存器位置表
	localparam integer LSU_FU_ID = 2; // LSU的执行单元ID
	localparam AUTO_CANCEL_SYNC_ERR_ENTRY = "false"; // 是否在发射时自动取消带有同步异常的项
	
	/** 取指单元(IFU) **/
	// 全局冲刷请求
	wire global_flush_req; // 冲刷请求
	wire[31:0] global_flush_addr; // 冲刷地址
	wire global_flush_ack; // 冲刷应答
	// 发射阶段分支信息广播
	wire brc_bdcst_luc_vld; // 广播有效
	wire[IBUS_TID_WIDTH-1:0] brc_bdcst_luc_tid; // 事务ID
	wire brc_bdcst_luc_is_b_inst; // 是否B指令
	wire brc_bdcst_luc_is_jal_inst; // 是否JAL指令
	wire brc_bdcst_luc_is_jalr_inst; // 是否JALR指令
	wire[31:0] brc_bdcst_luc_bta; // 分支目标地址
	// 全局历史分支预测
	wire glb_brc_prdt_on_clr_retired_ghr; // 清零退休GHR
	wire glb_brc_prdt_on_upd_retired_ghr; // 退休GHR更新指示
	wire glb_brc_prdt_retired_ghr_shift_in; // 退休GHR移位输入
	wire glb_brc_prdt_rstr_speculative_ghr; // 恢复推测GHR指示
	wire glb_brc_prdt_upd_i_req; // 更新请求
	wire[31:0] glb_brc_prdt_upd_i_pc; // 待更新项的PC
	wire[GHR_WIDTH-1:0] glb_brc_prdt_upd_i_ghr; // 待更新项的GHR
	wire glb_brc_prdt_upd_i_brc_taken; // 待更新项的实际分支跳转方向
	wire[GHR_WIDTH-1:0] glb_brc_prdt_retired_ghr_o; // 当前的退休GHR
	// BTB存储器
	wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_dina_w;
	wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_douta_w;
	wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_dinb_w;
	wire[BTB_WAY_N*BTB_MEM_WIDTH-1:0] btb_mem_doutb_w;
	// 取指结果
	wire[127:0] m_if_res_data; // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	wire[98:0] m_if_res_msg; // 取指附加信息({分支预测信息(96bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	wire[IBUS_TID_WIDTH-1:0] m_if_res_id; // 指令编号
	wire m_if_res_is_first_inst_after_rst; // 是否复位释放后的第1条指令
	wire m_if_res_valid;
	wire m_if_res_ready;
	// CPU核内指令ICB主机
	wire[31:0] m_icb_imem_cmd_inst_addr;
	wire m_icb_imem_cmd_inst_read;
	wire[31:0] m_icb_imem_cmd_inst_wdata;
	wire[3:0] m_icb_imem_cmd_inst_wmask;
	wire m_icb_imem_cmd_inst_valid;
	wire m_icb_imem_cmd_inst_ready;
	wire[31:0] m_icb_imem_rsp_inst_rdata;
	wire m_icb_imem_rsp_inst_err;
	wire m_icb_imem_rsp_inst_valid;
	wire m_icb_imem_rsp_inst_ready;
	// 指令总线控制单元状态
	wire suppressing_ibus_access; // 当前有正在镇压的ICB事务(状态标志)
	
	genvar btb_mem_rvs_i;
	generate
		for(btb_mem_rvs_i = 0;btb_mem_rvs_i < BTB_WAY_N;btb_mem_rvs_i = btb_mem_rvs_i + 1)
		begin:btb_mem_rvs_blk
			assign btb_mem_dina[btb_mem_rvs_i*64+63:btb_mem_rvs_i*64] = 
				btb_mem_dina_w[(btb_mem_rvs_i+1)*BTB_MEM_WIDTH-1:btb_mem_rvs_i*BTB_MEM_WIDTH] | 64'd0;
			assign btb_mem_dinb[btb_mem_rvs_i*64+63:btb_mem_rvs_i*64] = 
				btb_mem_dinb_w[(btb_mem_rvs_i+1)*BTB_MEM_WIDTH-1:btb_mem_rvs_i*BTB_MEM_WIDTH] | 64'd0;
			
			assign btb_mem_douta_w[(btb_mem_rvs_i+1)*BTB_MEM_WIDTH-1:btb_mem_rvs_i*BTB_MEM_WIDTH] = 
				btb_mem_douta[btb_mem_rvs_i*64+BTB_MEM_WIDTH-1:btb_mem_rvs_i*64];
			assign btb_mem_doutb_w[(btb_mem_rvs_i+1)*BTB_MEM_WIDTH-1:btb_mem_rvs_i*BTB_MEM_WIDTH] = 
				btb_mem_doutb[btb_mem_rvs_i*64+BTB_MEM_WIDTH-1:btb_mem_rvs_i*64];
		end
	endgenerate
	
	panda_risc_v_ifu #(
		.EN_IF_REGS(EN_IF_REGS),
		.IBUS_ACCESS_TIMEOUT_TH(IBUS_ACCESS_TIMEOUT_TH),
		.INST_ADDR_ALIGNMENT_WIDTH(INST_ADDR_ALIGNMENT_WIDTH),
		.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
		.IBUS_OUTSTANDING_N(IBUS_OUTSTANDING_N),
		.IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH(IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH),
		.PRDT_MSG_WIDTH(PRDT_MSG_WIDTH),
		.EN_PC_FOR_PHT_ADDR(EN_PC_FOR_PHT_ADDR),
		.EN_GHR_FOR_PHT_ADDR(EN_GHR_FOR_PHT_ADDR),
		.GHR_WIDTH(GHR_WIDTH),
		.BTB_WAY_N(BTB_WAY_N),
		.BTB_ENTRY_N(BTB_ENTRY_N),
		.PC_TAG_WIDTH(PC_TAG_WIDTH),
		.BTB_MEM_WIDTH(BTB_MEM_WIDTH),
		.RAS_ENTRY_N(RAS_ENTRY_N),
		.SIM_DELAY(SIM_DELAY)
	)ifu_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.sys_reset_req(sys_reset_req),
		.rst_pc(rst_pc),
		.flush_req(global_flush_req),
		.flush_addr(global_flush_addr),
		.rst_ack(),
		.flush_ack(global_flush_ack),
		
		.brc_bdcst_luc_vld(brc_bdcst_luc_vld),
		.brc_bdcst_luc_tid(brc_bdcst_luc_tid),
		.brc_bdcst_luc_is_b_inst(brc_bdcst_luc_is_b_inst),
		.brc_bdcst_luc_is_jal_inst(brc_bdcst_luc_is_jal_inst),
		.brc_bdcst_luc_is_jalr_inst(brc_bdcst_luc_is_jalr_inst),
		.brc_bdcst_luc_bta(brc_bdcst_luc_bta),
		
		.glb_brc_prdt_on_clr_retired_ghr(glb_brc_prdt_on_clr_retired_ghr),
		.glb_brc_prdt_on_upd_retired_ghr(glb_brc_prdt_on_upd_retired_ghr),
		.glb_brc_prdt_retired_ghr_shift_in(glb_brc_prdt_retired_ghr_shift_in),
		.glb_brc_prdt_rstr_speculative_ghr(glb_brc_prdt_rstr_speculative_ghr),
		.glb_brc_prdt_upd_i_req(glb_brc_prdt_upd_i_req),
		.glb_brc_prdt_upd_i_pc(glb_brc_prdt_upd_i_pc),
		.glb_brc_prdt_upd_i_ghr(glb_brc_prdt_upd_i_ghr),
		.glb_brc_prdt_upd_i_brc_taken(glb_brc_prdt_upd_i_brc_taken),
		.glb_brc_prdt_retired_ghr_o(glb_brc_prdt_retired_ghr_o),
		
		.btb_mem_clka(btb_mem_clka),
		.btb_mem_ena(btb_mem_ena),
		.btb_mem_wea(btb_mem_wea),
		.btb_mem_addra(btb_mem_addra),
		.btb_mem_dina(btb_mem_dina_w),
		.btb_mem_douta(btb_mem_douta_w),
		.btb_mem_clkb(btb_mem_clkb),
		.btb_mem_enb(btb_mem_enb),
		.btb_mem_web(btb_mem_web),
		.btb_mem_addrb(btb_mem_addrb),
		.btb_mem_dinb(btb_mem_dinb_w),
		.btb_mem_doutb(btb_mem_doutb_w),
		
		.m_if_res_data(m_if_res_data),
		.m_if_res_msg(m_if_res_msg),
		.m_if_res_id(m_if_res_id),
		.m_if_res_is_first_inst_after_rst(m_if_res_is_first_inst_after_rst),
		.m_if_res_valid(m_if_res_valid),
		.m_if_res_ready(m_if_res_ready),
		
		.m_icb_cmd_inst_addr(m_icb_imem_cmd_inst_addr),
		.m_icb_cmd_inst_read(m_icb_imem_cmd_inst_read),
		.m_icb_cmd_inst_wdata(m_icb_imem_cmd_inst_wdata),
		.m_icb_cmd_inst_wmask(m_icb_imem_cmd_inst_wmask),
		.m_icb_cmd_inst_valid(m_icb_imem_cmd_inst_valid),
		.m_icb_cmd_inst_ready(m_icb_imem_cmd_inst_ready),
		.m_icb_rsp_inst_rdata(m_icb_imem_rsp_inst_rdata),
		.m_icb_rsp_inst_err(m_icb_imem_rsp_inst_err),
		.m_icb_rsp_inst_valid(m_icb_imem_rsp_inst_valid),
		.m_icb_rsp_inst_ready(m_icb_imem_rsp_inst_ready),
		
		.suppressing_ibus_access(suppressing_ibus_access),
		.clr_inst_buf_while_suppressing(clr_inst_buf_while_suppressing),
		.ibus_timeout(ibus_timeout)
	);
	
	/** 通用寄存器堆 **/
	// 通用寄存器堆写端口
	wire reg_file_wen;
	wire[4:0] reg_file_waddr;
	wire[31:0] reg_file_din;
	// 通用寄存器堆读端口#0
	wire[4:0] reg_file_raddr_p0;
	wire[31:0] reg_file_dout_p0;
	// 通用寄存器堆读端口#1
	wire[4:0] reg_file_raddr_p1;
	wire[31:0] reg_file_dout_p1;
	
	panda_risc_v_reg_file #(
		.SIM_DELAY(SIM_DELAY)
	)generic_reg_file_u(
		.clk(aclk),
		
		.reg_file_wen(reg_file_wen),
		.reg_file_waddr(reg_file_waddr),
		.reg_file_din(reg_file_din),
		
		.reg_file_raddr_p0(reg_file_raddr_p0),
		.reg_file_dout_p0(reg_file_dout_p0),
		.reg_file_raddr_p1(reg_file_raddr_p1),
		.reg_file_dout_p1(reg_file_dout_p1),
		
		.x1_v()
	);
	
	/** 预取操作数 **/
	// 读ARF/ROB输入
	wire[127:0] s_regs_rd_data; // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	wire[98:0] s_regs_rd_msg; // 取指附加信息({分支预测信息(96bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	wire[IBUS_TID_WIDTH-1:0] s_regs_rd_id; // 指令编号
	wire s_regs_rd_is_first_inst_after_rst; // 是否复位释放后的第1条指令
	wire s_regs_rd_valid;
	wire s_regs_rd_ready;
	// 读ARF/ROB输出
	wire[127:0] m_regs_rd_data; // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	wire[98:0] m_regs_rd_msg; // 取指附加信息({分支预测信息(96bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	wire[IBUS_TID_WIDTH-1:0] m_regs_rd_id; // 指令编号
	wire m_regs_rd_is_first_inst_after_rst; // 是否复位释放后的第1条指令
	wire[129:0] m_regs_rd_op; // 预取的操作数({操作数1已取得(1bit), 操作数2已取得(1bit), 
	                          //   操作数1(32bit), 操作数2(32bit), 用于取操作数1的执行单元ID(16bit), 用于取操作数2的执行单元ID(16bit), 
							  //   用于取操作数1的指令ID(16bit), 用于取操作数2的指令ID(16bit)})
	wire[FU_ID_WIDTH-1:0] m_regs_rd_fuid; // 执行单元ID
	wire m_regs_rd_valid;
	wire m_regs_rd_ready;
	// 数据相关性检查
	// [操作数1]
	wire[4:0] op1_ftc_rs1_id; // 1号源寄存器编号
	wire op1_ftc_from_reg_file; // 从寄存器堆取到操作数(标志)
	wire op1_ftc_from_rob; // 从ROB取到操作数(标志)
	wire op1_ftc_from_byp; // 从旁路网络取到操作数(标志)
	wire[FU_ID_WIDTH-1:0] op1_ftc_fuid; // 待旁路的执行单元编号
	wire[IBUS_TID_WIDTH-1:0] op1_ftc_tid; // 待旁路的指令ID
	wire[FU_RES_WIDTH-1:0] op1_ftc_rob_saved_data; // ROB暂存的执行结果
	// [操作数2]
	wire[4:0] op2_ftc_rs2_id; // 2号源寄存器编号
	wire op2_ftc_from_reg_file; // 从寄存器堆取到操作数(标志)
	wire op2_ftc_from_rob; // 从ROB取到操作数(标志)
	wire op2_ftc_from_byp; // 从旁路网络取到操作数(标志)
	wire[FU_ID_WIDTH-1:0] op2_ftc_fuid; // 待旁路的执行单元编号
	wire[IBUS_TID_WIDTH-1:0] op2_ftc_tid; // 待旁路的指令ID
	wire[FU_RES_WIDTH-1:0] op2_ftc_rob_saved_data; // ROB暂存的执行结果
	// 执行单元结果返回
	wire[LSN_FU_N-1:0] fu_res_vld; // 有效标志
	wire[LSN_FU_N*IBUS_TID_WIDTH-1:0] fu_res_tid; // 指令ID
	wire[LSN_FU_N*FU_RES_WIDTH-1:0] fu_res_data; // 执行结果
	wire[LSN_FU_N*FU_ERR_WIDTH-1:0] fu_res_err; // 错误码
	
	assign s_regs_rd_data = m_if_res_data;
	assign s_regs_rd_msg = m_if_res_msg;
	assign s_regs_rd_id = m_if_res_id;
	assign s_regs_rd_is_first_inst_after_rst = m_if_res_is_first_inst_after_rst;
	assign s_regs_rd_valid = m_if_res_valid;
	assign m_if_res_ready = s_regs_rd_ready;
	
	panda_risc_v_regs_rd #(
		.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
		.LSN_FU_N(LSN_FU_N),
		.FU_ID_WIDTH(FU_ID_WIDTH),
		.FU_RES_WIDTH(FU_RES_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)op_pre_fetch_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.sys_reset_req(sys_reset_req),
		.flush_req(global_flush_req),
		
		.s_regs_rd_data(s_regs_rd_data),
		.s_regs_rd_msg(s_regs_rd_msg),
		.s_regs_rd_id(s_regs_rd_id),
		.s_regs_rd_is_first_inst_after_rst(s_regs_rd_is_first_inst_after_rst),
		.s_regs_rd_valid(s_regs_rd_valid),
		.s_regs_rd_ready(s_regs_rd_ready),
		
		.m_regs_rd_data(m_regs_rd_data),
		.m_regs_rd_msg(m_regs_rd_msg),
		.m_regs_rd_id(m_regs_rd_id),
		.m_regs_rd_is_first_inst_after_rst(m_regs_rd_is_first_inst_after_rst),
		.m_regs_rd_op(m_regs_rd_op),
		.m_regs_rd_fuid(m_regs_rd_fuid),
		.m_regs_rd_valid(m_regs_rd_valid),
		.m_regs_rd_ready(m_regs_rd_ready),
		
		.op1_ftc_rs1_id(op1_ftc_rs1_id),
		.op1_ftc_from_reg_file(op1_ftc_from_reg_file),
		.op1_ftc_from_rob(op1_ftc_from_rob),
		.op1_ftc_from_byp(op1_ftc_from_byp),
		.op1_ftc_fuid(op1_ftc_fuid),
		.op1_ftc_tid(op1_ftc_tid),
		.op1_ftc_rob_saved_data(op1_ftc_rob_saved_data),
		.op2_ftc_rs2_id(op2_ftc_rs2_id),
		.op2_ftc_from_reg_file(op2_ftc_from_reg_file),
		.op2_ftc_from_rob(op2_ftc_from_rob),
		.op2_ftc_from_byp(op2_ftc_from_byp),
		.op2_ftc_fuid(op2_ftc_fuid),
		.op2_ftc_tid(op2_ftc_tid),
		.op2_ftc_rob_saved_data(op2_ftc_rob_saved_data),
		
		.fu_res_vld(fu_res_vld),
		.fu_res_tid(fu_res_tid),
		.fu_res_data(fu_res_data),
		
		.reg_file_raddr_p0(reg_file_raddr_p0),
		.reg_file_dout_p0(reg_file_dout_p0),
		.reg_file_raddr_p1(reg_file_raddr_p1),
		.reg_file_dout_p1(reg_file_dout_p1)
	);
	
	/** 取操作数和指令译码 **/
	// 取指结果
	wire[127:0] s_if_res_data; // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	wire[98:0] s_if_res_msg; // 取指附加信息({分支预测信息(96bit), 是否非法指令(1bit), 指令存储器访问错误码(2bit)})
	wire[IBUS_TID_WIDTH-1:0] s_if_res_id; // 指令编号
	wire s_if_res_is_first_inst_after_rst; // 是否复位释放后的第1条指令
	wire[129:0] s_if_res_op; // 预取的操作数({操作数1已取得(1bit), 操作数2已取得(1bit), 
	                         //   操作数1(32bit), 操作数2(32bit), 用于取操作数1的执行单元ID(16bit), 用于取操作数2的执行单元ID(16bit), 
						     //   用于取操作数1的指令ID(16bit), 用于取操作数2的指令ID(16bit)})
	wire[FU_ID_WIDTH-1:0] s_if_res_fuid; // 执行单元ID
	wire s_if_res_valid;
	wire s_if_res_ready;
	// 取操作数和译码结果
	wire[127:0] m_op_ftc_id_res_data; // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	wire[146:0] m_op_ftc_id_res_msg; // 取指附加信息({分支预测信息(144bit), 错误码(3bit)})
	wire[143:0] m_op_ftc_id_res_dcd_res; // 译码信息({打包的FU操作信息(128bit), 打包的指令类型标志(16bit)})
	wire[IBUS_TID_WIDTH-1:0] m_op_ftc_id_res_id; // 指令编号
	wire m_op_ftc_id_res_is_first_inst_after_rst; // 是否复位释放后的第1条指令
	wire[31:0] m_op_ftc_id_res_op1; // 操作数1
	wire[31:0] m_op_ftc_id_res_op2; // 操作数2
	wire m_op_ftc_id_res_with_ls_sdefc; // 是否存在访存副效应
	wire m_op_ftc_id_res_valid;
	wire m_op_ftc_id_res_ready;
	// 发射阶段ROB记录广播
	wire rob_luc_bdcst_vld; // 广播有效
	wire[IBUS_TID_WIDTH-1:0] rob_luc_bdcst_tid; // 指令ID
	wire[FU_ID_WIDTH-1:0] rob_luc_bdcst_fuid; // 被发射到的执行单元ID
	wire[4:0] rob_luc_bdcst_rd_id; // 目的寄存器编号
	wire rob_luc_bdcst_is_ls_inst; // 是否加载/存储指令
	wire rob_luc_bdcst_with_ls_sdefc; // 是否存在访存副效应
	wire rob_luc_bdcst_is_csr_rw_inst; // 是否CSR读写指令
	wire[45:0] rob_luc_bdcst_csr_rw_inst_msg; // CSR读写指令信息({CSR写地址(12bit), CSR更新类型(2bit), CSR更新掩码或更新值(32bit)})
	wire[2:0] rob_luc_bdcst_err; // 错误类型
	wire[2:0] rob_luc_bdcst_spec_inst_type; // 特殊指令类型
	
	assign s_if_res_data = m_regs_rd_data;
	assign s_if_res_msg = m_regs_rd_msg;
	assign s_if_res_id = m_regs_rd_id;
	assign s_if_res_is_first_inst_after_rst = m_regs_rd_is_first_inst_after_rst;
	assign s_if_res_op = m_regs_rd_op;
	assign s_if_res_fuid = m_regs_rd_fuid;
	assign s_if_res_valid = m_regs_rd_valid;
	assign m_regs_rd_ready = s_if_res_ready;
	
	panda_risc_v_op_fetch_idec #(
		.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
		.LSN_FU_N(LSN_FU_N),
		.FU_ID_WIDTH(FU_ID_WIDTH),
		.FU_RES_WIDTH(FU_RES_WIDTH),
		.GEN_LS_ADDR_UNALIGNED_EXPT(GEN_LS_ADDR_UNALIGNED_EXPT),
		.OP_PRE_FTC("true"),
		.SIM_DELAY(SIM_DELAY)
	)op_fetch_idec_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.sys_reset_req(sys_reset_req),
		.flush_req(global_flush_req),
		
		.s_if_res_data(s_if_res_data),
		.s_if_res_msg(s_if_res_msg),
		.s_if_res_id(s_if_res_id),
		.s_if_res_is_first_inst_after_rst(s_if_res_is_first_inst_after_rst),
		.s_if_res_op(s_if_res_op),
		.s_if_res_fuid(s_if_res_fuid),
		.s_if_res_valid(s_if_res_valid),
		.s_if_res_ready(s_if_res_ready),
		
		.m_op_ftc_id_res_data(m_op_ftc_id_res_data),
		.m_op_ftc_id_res_msg(m_op_ftc_id_res_msg),
		.m_op_ftc_id_res_dcd_res(m_op_ftc_id_res_dcd_res),
		.m_op_ftc_id_res_id(m_op_ftc_id_res_id),
		.m_op_ftc_id_res_is_first_inst_after_rst(m_op_ftc_id_res_is_first_inst_after_rst),
		.m_op_ftc_id_res_op1(m_op_ftc_id_res_op1),
		.m_op_ftc_id_res_op2(m_op_ftc_id_res_op2),
		.m_op_ftc_id_res_with_ls_sdefc(m_op_ftc_id_res_with_ls_sdefc),
		.m_op_ftc_id_res_valid(m_op_ftc_id_res_valid),
		.m_op_ftc_id_res_ready(m_op_ftc_id_res_ready),
		
		.brc_bdcst_luc_vld(brc_bdcst_luc_vld),
		.brc_bdcst_luc_tid(brc_bdcst_luc_tid),
		.brc_bdcst_luc_is_b_inst(brc_bdcst_luc_is_b_inst),
		.brc_bdcst_luc_is_jal_inst(brc_bdcst_luc_is_jal_inst),
		.brc_bdcst_luc_is_jalr_inst(brc_bdcst_luc_is_jalr_inst),
		.brc_bdcst_luc_bta(brc_bdcst_luc_bta),
		
		.rob_luc_bdcst_vld(rob_luc_bdcst_vld),
		.rob_luc_bdcst_tid(rob_luc_bdcst_tid),
		.rob_luc_bdcst_fuid(rob_luc_bdcst_fuid),
		.rob_luc_bdcst_rd_id(rob_luc_bdcst_rd_id),
		.rob_luc_bdcst_is_ls_inst(rob_luc_bdcst_is_ls_inst),
		.rob_luc_bdcst_with_ls_sdefc(rob_luc_bdcst_with_ls_sdefc),
		.rob_luc_bdcst_is_csr_rw_inst(rob_luc_bdcst_is_csr_rw_inst),
		.rob_luc_bdcst_csr_rw_inst_msg(rob_luc_bdcst_csr_rw_inst_msg),
		.rob_luc_bdcst_err(rob_luc_bdcst_err),
		.rob_luc_bdcst_spec_inst_type(rob_luc_bdcst_spec_inst_type),
		
		.op1_ftc_rs1_id(),
		.op1_ftc_from_reg_file(1'b0),
		.op1_ftc_from_rob(1'b0),
		.op1_ftc_from_byp(1'b0),
		.op1_ftc_fuid({FU_ID_WIDTH{1'b0}}),
		.op1_ftc_tid({IBUS_TID_WIDTH{1'b0}}),
		.op1_ftc_rob_saved_data({FU_RES_WIDTH{1'b0}}),
		.op2_ftc_rs2_id(),
		.op2_ftc_from_reg_file(1'b0),
		.op2_ftc_from_rob(1'b0),
		.op2_ftc_from_byp(1'b0),
		.op2_ftc_fuid({FU_ID_WIDTH{1'b0}}),
		.op2_ftc_tid({IBUS_TID_WIDTH{1'b0}}),
		.op2_ftc_rob_saved_data({FU_RES_WIDTH{1'b0}}),
		
		.fu_res_bypass_en({LSN_FU_N{1'b1}}),
		
		.fu_res_vld(fu_res_vld),
		.fu_res_tid(fu_res_tid),
		.fu_res_data(fu_res_data),
		
		.reg_file_raddr_p0(),
		.reg_file_dout_p0(32'h0000_0000),
		.reg_file_raddr_p1(),
		.reg_file_dout_p1(32'h0000_0000)
	);
	
	/** 发射单元 **/
	// ROB状态
	wire rob_full_n; // ROB满(标志)
	wire rob_empty_n; // ROB空(标志)
	wire rob_csr_rw_inst_allowed; // 允许发射CSR读写指令(标志)
	wire rob_has_ls_inst; // ROB中存在访存指令(标志)
	wire rob_has_ls_sdefc_inst; // ROB中存在带有副效应的访存指令(标志)
	// 取操作数和译码结果
	wire[127:0] s_op_ftc_id_res_data; // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	wire[146:0] s_op_ftc_id_res_msg; // 取指附加信息({分支预测信息(144bit), 错误码(3bit)})
	wire[143:0] s_op_ftc_id_res_dcd_res; // 译码信息({打包的FU操作信息(128bit), 打包的指令类型标志(16bit)})
	wire[IBUS_TID_WIDTH-1:0] s_op_ftc_id_res_id; // 指令编号
	wire s_op_ftc_id_res_is_first_inst_after_rst; // 是否复位释放后的第1条指令
	wire[31:0] s_op_ftc_id_res_op1; // 操作数1
	wire[31:0] s_op_ftc_id_res_op2; // 操作数2
	wire s_op_ftc_id_res_with_ls_sdefc; // 是否存在访存副效应
	wire s_op_ftc_id_res_valid;
	wire s_op_ftc_id_res_ready;
	// 发射单元输出
	wire[127:0] m_luc_data; // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	wire[146:0] m_luc_msg; // 取指附加信息({分支预测信息(144bit), 错误码(3bit)})
	wire[143:0] m_luc_dcd_res; // 译码信息({打包的FU操作信息(128bit), 打包的指令类型标志(16bit)})
	wire[IBUS_TID_WIDTH-1:0] m_luc_id; // 指令编号
	wire m_luc_is_first_inst_after_rst; // 是否复位释放后的第1条指令
	wire[31:0] m_luc_op1; // 操作数1
	wire[31:0] m_luc_op2; // 操作数2
	wire m_luc_valid;
	wire m_luc_ready;
	
	assign s_op_ftc_id_res_data = m_op_ftc_id_res_data;
	assign s_op_ftc_id_res_msg = m_op_ftc_id_res_msg;
	assign s_op_ftc_id_res_dcd_res = m_op_ftc_id_res_dcd_res;
	assign s_op_ftc_id_res_id = m_op_ftc_id_res_id;
	assign s_op_ftc_id_res_is_first_inst_after_rst = m_op_ftc_id_res_is_first_inst_after_rst;
	assign s_op_ftc_id_res_op1 = m_op_ftc_id_res_op1;
	assign s_op_ftc_id_res_op2 = m_op_ftc_id_res_op2;
	assign s_op_ftc_id_res_with_ls_sdefc = m_op_ftc_id_res_with_ls_sdefc;
	assign s_op_ftc_id_res_valid = m_op_ftc_id_res_valid;
	assign m_op_ftc_id_res_ready = s_op_ftc_id_res_ready;
	
	panda_risc_v_launch #(
		.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)launch_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.rob_full_n(rob_full_n),
		.rob_empty_n(rob_empty_n),
		.rob_csr_rw_inst_allowed(rob_csr_rw_inst_allowed),
		.rob_has_ls_inst(rob_has_ls_inst),
		.rob_has_ls_sdefc_inst(rob_has_ls_sdefc_inst),
		
		.sys_reset_req(sys_reset_req),
		.flush_req(global_flush_req),
		
		.s_op_ftc_id_res_data(s_op_ftc_id_res_data),
		.s_op_ftc_id_res_msg(s_op_ftc_id_res_msg),
		.s_op_ftc_id_res_dcd_res(s_op_ftc_id_res_dcd_res),
		.s_op_ftc_id_res_id(s_op_ftc_id_res_id),
		.s_op_ftc_id_res_is_first_inst_after_rst(s_op_ftc_id_res_is_first_inst_after_rst),
		.s_op_ftc_id_res_op1(s_op_ftc_id_res_op1),
		.s_op_ftc_id_res_op2(s_op_ftc_id_res_op2),
		.s_op_ftc_id_res_with_ls_sdefc(s_op_ftc_id_res_with_ls_sdefc),
		.s_op_ftc_id_res_valid(s_op_ftc_id_res_valid),
		.s_op_ftc_id_res_ready(s_op_ftc_id_res_ready),
		
		.m_luc_data(m_luc_data),
		.m_luc_msg(m_luc_msg),
		.m_luc_dcd_res(m_luc_dcd_res),
		.m_luc_id(m_luc_id),
		.m_luc_is_first_inst_after_rst(m_luc_is_first_inst_after_rst),
		.m_luc_op1(m_luc_op1),
		.m_luc_op2(m_luc_op2),
		.m_luc_valid(m_luc_valid),
		.m_luc_ready(m_luc_ready)
	);
	
	/** 分发单元 **/
	// 分发单元输入
	wire[127:0] s_dsptc_data; // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	wire[146:0] s_dsptc_msg; // 取指附加信息({分支预测信息(144bit), 错误码(3bit)})
	wire[143:0] s_dsptc_dcd_res; // 译码信息({打包的FU操作信息(128bit), 打包的指令类型标志(16bit)})
	wire[IBUS_TID_WIDTH-1:0] s_dsptc_id; // 指令编号
	wire s_dsptc_is_first_inst_after_rst; // 是否复位释放后的第1条指令
	wire s_dsptc_valid;
	wire s_dsptc_ready;
	// BRU
	wire[127:0] m_bru_i_data; // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	wire[146:0] m_bru_i_msg; // 取指附加信息({分支预测信息(144bit), 错误码(3bit)})
	wire[143:0] m_bru_i_dcd_res; // 译码信息({打包的FU操作信息(128bit), 打包的指令类型标志(16bit)})
	wire[IBUS_TID_WIDTH-1:0] m_bru_i_id; // 指令编号
	wire m_bru_i_valid;
	wire m_bru_i_ready;
	// 执行单元操作信息
	// [ALU]
	wire[3:0] m_alu_op_mode; // 操作类型
	wire[31:0] m_alu_op1; // 操作数1
	wire[31:0] m_alu_op2; // 操作数2
	wire[IBUS_TID_WIDTH-1:0] m_alu_tid; // 指令ID
	wire m_alu_use_res; // 是否使用ALU的计算结果
	wire m_alu_valid;
	// [CSR原子读写]
	wire[11:0] m_csr_addr; // CSR地址
	wire[IBUS_TID_WIDTH-1:0] m_csr_tid; // 指令ID
	wire m_csr_valid;
	// [LSU]
	wire m_lsu_ls_sel; // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	wire[2:0] m_lsu_ls_type; // 访存类型
	wire[4:0] m_lsu_rd_id_for_ld; // 用于加载的目标寄存器的索引
	wire[31:0] m_lsu_ls_din; // 写数据
	wire[IBUS_TID_WIDTH-1:0] m_lsu_inst_id; // 指令ID
	wire m_lsu_valid;
	wire m_lsu_ready;
	// [乘法器]
	wire[32:0] m_mul_op_a; // 操作数A
	wire[32:0] m_mul_op_b; // 操作数B
	wire m_mul_res_sel; // 乘法结果选择(1'b0 -> 低32位, 1'b1 -> 高32位)
	wire[4:0] m_mul_rd_id; // RD索引
	wire[IBUS_TID_WIDTH-1:0] m_mul_inst_id; // 指令ID
	wire m_mul_valid;
	wire m_mul_ready;
	// [除法器]
	wire[32:0] m_div_op_a; // 操作数A(被除数)
	wire[32:0] m_div_op_b; // 操作数B(除数)
	wire m_div_rem_sel; // 除法/求余选择(1'b0 -> 除法, 1'b1 -> 求余)
	wire[4:0] m_div_rd_id; // RD索引
	wire[IBUS_TID_WIDTH-1:0] m_div_inst_id; // 指令ID
	wire m_div_valid;
	wire m_div_ready;
	
	assign s_dsptc_data = m_luc_data;
	assign s_dsptc_msg = m_luc_msg;
	assign s_dsptc_dcd_res = m_luc_dcd_res;
	assign s_dsptc_id = m_luc_id;
	assign s_dsptc_is_first_inst_after_rst = m_luc_is_first_inst_after_rst;
	assign s_dsptc_valid = m_luc_valid;
	assign m_luc_ready = s_dsptc_ready;
	
	panda_risc_v_dispatch #(
		.IBUS_TID_WIDTH(IBUS_TID_WIDTH)
	)dispatch_u(
		.s_dsptc_data(s_dsptc_data),
		.s_dsptc_msg(s_dsptc_msg),
		.s_dsptc_dcd_res(s_dsptc_dcd_res),
		.s_dsptc_id(s_dsptc_id),
		.s_dsptc_is_first_inst_after_rst(s_dsptc_is_first_inst_after_rst),
		.s_dsptc_valid(s_dsptc_valid),
		.s_dsptc_ready(s_dsptc_ready),
		
		.m_bru_i_data(m_bru_i_data),
		.m_bru_i_msg(m_bru_i_msg),
		.m_bru_i_dcd_res(m_bru_i_dcd_res),
		.m_bru_i_id(m_bru_i_id),
		.m_bru_i_valid(m_bru_i_valid),
		.m_bru_i_ready(m_bru_i_ready),
		
		.m_alu_op_mode(m_alu_op_mode),
		.m_alu_op1(m_alu_op1),
		.m_alu_op2(m_alu_op2),
		.m_alu_tid(m_alu_tid),
		.m_alu_use_res(m_alu_use_res),
		.m_alu_valid(m_alu_valid),
		
		.m_csr_addr(m_csr_addr),
		.m_csr_tid(m_csr_tid),
		.m_csr_valid(m_csr_valid),
		
		.m_lsu_ls_sel(m_lsu_ls_sel),
		.m_lsu_ls_type(m_lsu_ls_type),
		.m_lsu_rd_id_for_ld(m_lsu_rd_id_for_ld),
		.m_lsu_ls_din(m_lsu_ls_din),
		.m_lsu_inst_id(m_lsu_inst_id),
		.m_lsu_valid(m_lsu_valid),
		.m_lsu_ready(m_lsu_ready),
		
		.m_mul_op_a(m_mul_op_a),
		.m_mul_op_b(m_mul_op_b),
		.m_mul_res_sel(m_mul_res_sel),
		.m_mul_rd_id(m_mul_rd_id),
		.m_mul_inst_id(m_mul_inst_id),
		.m_mul_valid(m_mul_valid),
		.m_mul_ready(m_mul_ready),
		
		.m_div_op_a(m_div_op_a),
		.m_div_op_b(m_div_op_b),
		.m_div_rem_sel(m_div_rem_sel),
		.m_div_rd_id(m_div_rd_id),
		.m_div_inst_id(m_div_inst_id),
		.m_div_valid(m_div_valid),
		.m_div_ready(m_div_ready)
	);
	
	/** 冲刷控制 **/
	// BRU给出的冲刷请求
	wire bru_flush_req; // 冲刷请求
	wire[31:0] bru_flush_addr; // 冲刷地址
	wire bru_flush_grant; // 冲刷许可
	// 交付单元给出的冲刷请求
	wire cmt_flush_req; // 冲刷请求
	wire[31:0] cmt_flush_addr; // 冲刷地址
	wire cmt_flush_grant; // 冲刷许可
	
	panda_risc_v_flush_ctrl #(
		.SIM_DELAY(SIM_DELAY)
	)flush_ctrl_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.sys_reset_req(sys_reset_req),
		
		.glb_brc_prdt_on_clr_retired_ghr(glb_brc_prdt_on_clr_retired_ghr),
		.glb_brc_prdt_rstr_speculative_ghr(glb_brc_prdt_rstr_speculative_ghr),
		
		.bru_flush_req(bru_flush_req),
		.bru_flush_addr(bru_flush_addr),
		.bru_flush_grant(bru_flush_grant),
		
		.cmt_flush_req(cmt_flush_req),
		.cmt_flush_addr(cmt_flush_addr),
		.cmt_flush_grant(cmt_flush_grant),
		
		.suppressing_ibus_access(suppressing_ibus_access),
		
		.global_flush_req(global_flush_req),
		.global_flush_addr(global_flush_addr),
		.global_flush_ack(global_flush_ack)
	);
	
	/** 状态寄存器(CSR) **/
	// CSR原子读写
	// [CSR写]
	wire[11:0] csr_atom_waddr; // CSR写地址
	wire[1:0] csr_atom_upd_type; // CSR更新类型
	wire[31:0] csr_atom_upd_mask_v; // CSR更新掩码或更新值
	wire csr_atom_wen; // CSR写使能
	// [CSR读]
	wire[11:0] csr_atom_raddr; // CSR读地址
	wire[31:0] csr_atom_dout; // CSR原值
	// 进入中断/异常处理
	wire itr_expt_enter; // 进入中断/异常(指示)
	wire itr_expt_is_intr; // 是否中断
	wire[7:0] itr_expt_cause; // 中断/异常原因
	wire[31:0] itr_expt_vec_baseaddr; // 中断/异常向量表基地址
	wire[31:0] itr_expt_ret_addr; // 中断/异常返回地址
	wire[31:0] itr_expt_val; // 中断/异常值(附加信息)
	// 退出中断/异常处理
	wire itr_expt_ret; // 退出中断/异常(指示)
	wire[31:0] mepc_ret_addr; // mepc状态寄存器定义的中断/异常返回地址
	// 进入调试模式
	wire dbg_mode_enter; // 进入调试模式(指示)
	wire[2:0] dbg_mode_cause; // 进入调试模式的原因
	wire[31:0] dbg_mode_ret_addr; // 调试模式返回地址
	// 退出调试模式
	wire dbg_mode_ret; // 退出调试模式(指示)
	wire[31:0] dpc_ret_addr; // dpc状态寄存器定义的调试模式返回地址
	// 调试状态
	wire dcsr_ebreakm_v; // dcsr状态寄存器EBREAKM域
	wire dcsr_step_v; // dcsr状态寄存器STEP域
	wire in_dbg_mode; // 当前处于调试模式(标志)
	// 性能监测
	wire inst_retire_cnt_en; // 退休指令计数器的计数使能
	// 中断使能
	wire mstatus_mie_v; // mstatus状态寄存器MIE域
	wire mie_msie_v; // mie状态寄存器MSIE域
	wire mie_mtie_v; // mie状态寄存器MTIE域
	wire mie_meie_v; // mie状态寄存器MEIE域
	
	panda_risc_v_csr_rw #(
		.en_expt_vec_vectored(EN_EXPT_VEC_VECTORED),
		.en_performance_monitor(EN_PERF_MONITOR),
		.init_mtvec_base(init_mtvec_base),
		.init_mcause_interrupt(init_mcause_interrupt),
		.init_mcause_exception_code(init_mcause_exception_code),
		.init_misa_mxl(init_misa_mxl),
		.init_misa_extensions(init_misa_extensions),
		.init_mvendorid_bank(init_mvendorid_bank),
		.init_mvendorid_offset(init_mvendorid_offset),
		.init_marchid(init_marchid),
		.init_mimpid(init_mimpid),
		.init_mhartid(init_mhartid),
		.debug_supported(DEBUG_SUPPORTED),
		.dscratch_n(DSCRATCH_N),
		.simulation_delay(SIM_DELAY)
	)csr_u(
		.clk(aclk),
		.resetn(aresetn),
		
		.csr_atom_waddr(csr_atom_waddr),
		.csr_atom_upd_type(csr_atom_upd_type),
		.csr_atom_upd_mask_v(csr_atom_upd_mask_v),
		.csr_atom_wen(csr_atom_wen),
		.csr_atom_raddr(csr_atom_raddr),
		.csr_atom_dout(csr_atom_dout),
		
		.itr_expt_enter(itr_expt_enter),
		.itr_expt_is_intr(itr_expt_is_intr),
		.itr_expt_cause(itr_expt_cause),
		.itr_expt_vec_baseaddr(itr_expt_vec_baseaddr),
		.itr_expt_ret_addr(itr_expt_ret_addr),
		.itr_expt_val(itr_expt_val),
		
		.itr_expt_ret(itr_expt_ret),
		.mepc_ret_addr(mepc_ret_addr),
		
		.dbg_mode_enter(dbg_mode_enter),
		.dbg_mode_cause(dbg_mode_cause),
		.dbg_mode_ret_addr(dbg_mode_ret_addr),
		
		.dbg_mode_ret(dbg_mode_ret),
		.dpc_ret_addr(dpc_ret_addr),
		
		.dcsr_ebreakm_v(dcsr_ebreakm_v),
		.dcsr_step_v(dcsr_step_v),
		.in_dbg_mode(in_dbg_mode),
		
		.inst_retire_cnt_en(inst_retire_cnt_en),
		
		.sw_itr_req(sw_itr_req),
		.tmr_itr_req(tmr_itr_req),
		.ext_itr_req(ext_itr_req),
		
		.mstatus_mie_v(mstatus_mie_v),
		.mie_msie_v(mie_msie_v),
		.mie_mtie_v(mie_mtie_v),
		.mie_meie_v(mie_meie_v)
	);
	
	/** 分支处理单元(BRU) **/
	// 控制/状态
	wire rst_bru; // 重置BRU
	wire[31:0] jal_inst_n_acpt; // 接受的JAL指令总数
	wire[31:0] jal_prdt_success_inst_n; // 预测正确的JAL指令数
	wire[31:0] jalr_inst_n_acpt; // 接受的JALR指令总数
	wire[31:0] jalr_prdt_success_inst_n; // 预测正确的JALR指令数
	wire[31:0] b_inst_n_acpt; // 接受的B指令总数
	wire[31:0] b_prdt_success_inst_n; // 预测正确的B指令数
	wire[31:0] common_inst_n_acpt; // 接受的非分支指令总数
	wire[31:0] common_prdt_success_inst_n; // 预测正确的非分支指令数
	// ALU给出的分支判定结果
	wire alu_brc_cond_res;
	// BRU输入
	wire[127:0] s_bru_i_data; // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	wire[146:0] s_bru_i_msg; // 取指附加信息({分支预测信息(144bit), 错误码(3bit)})
	wire[143:0] s_bru_i_dcd_res; // 译码信息({打包的FU操作信息(128bit), 打包的指令类型标志(16bit)})
	wire[IBUS_TID_WIDTH-1:0] s_bru_i_tid; // 指令ID
	wire s_bru_i_valid;
	wire s_bru_i_ready;
	// BRU输出
	wire[IBUS_TID_WIDTH-1:0] m_bru_o_tid; // 指令ID
	wire[31:0] m_bru_o_pc; // 当前PC地址
	wire[31:0] m_bru_o_nxt_pc; // 下一有效PC地址
	wire[1:0] m_bru_o_b_inst_res; // B指令执行结果
	wire m_bru_o_valid;
	
	assign rst_bru = cmt_flush_req;
	
	assign s_bru_i_data = m_bru_i_data;
	assign s_bru_i_msg = m_bru_i_msg;
	assign s_bru_i_dcd_res = m_bru_i_dcd_res;
	assign s_bru_i_tid = m_bru_i_id;
	assign s_bru_i_valid = m_bru_i_valid;
	assign m_bru_i_ready = s_bru_i_ready;
	
	panda_risc_v_bru #(
		.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
		.EN_IMDT_FLUSH(EN_BRU_IMDT_FLUSH),
		.DEBUG_ROM_ADDR(DEBUG_ROM_ADDR),
		.SIM_DELAY(SIM_DELAY)
	)bru_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.in_dbg_mode(in_dbg_mode),
		
		.rst_bru(rst_bru),
		.jal_inst_n_acpt(jal_inst_n_acpt),
		.jal_prdt_success_inst_n(jal_prdt_success_inst_n),
		.jalr_inst_n_acpt(jalr_inst_n_acpt),
		.jalr_prdt_success_inst_n(jalr_prdt_success_inst_n),
		.b_inst_n_acpt(b_inst_n_acpt),
		.b_prdt_success_inst_n(b_prdt_success_inst_n),
		.common_inst_n_acpt(common_inst_n_acpt),
		.common_prdt_success_inst_n(common_prdt_success_inst_n),
		
		.bru_flush_req(bru_flush_req),
		.bru_flush_addr(bru_flush_addr),
		.bru_flush_grant(bru_flush_grant),
		
		.alu_brc_cond_res(alu_brc_cond_res),
		
		.s_bru_i_data(s_bru_i_data),
		.s_bru_i_msg(s_bru_i_msg),
		.s_bru_i_dcd_res(s_bru_i_dcd_res),
		.s_bru_i_tid(s_bru_i_tid),
		.s_bru_i_valid(s_bru_i_valid),
		.s_bru_i_ready(s_bru_i_ready),
		
		.m_bru_o_tid(m_bru_o_tid),
		.m_bru_o_pc(m_bru_o_pc),
		.m_bru_o_nxt_pc(m_bru_o_nxt_pc),
		.m_bru_o_b_inst_res(m_bru_o_b_inst_res),
		.m_bru_o_valid(m_bru_o_valid)
	);
	
	/** 执行单元组 **/
	// ALU(操作信息输入)
	wire[3:0] s_alu_op_mode; // 操作类型
	wire[31:0] s_alu_op1; // 操作数1
	wire[31:0] s_alu_op2; // 操作数2
	wire[IBUS_TID_WIDTH-1:0] s_alu_tid; // 指令ID
	wire s_alu_use_res; // 是否使用ALU的计算结果
	wire s_alu_valid;
	// CSR原子读写(访问输入)
	wire[11:0] s_csr_addr; // CSR地址
	wire[IBUS_TID_WIDTH-1:0] s_csr_tid; // 指令ID
	wire s_csr_valid;
	// LSU(访问输入)
	wire s_lsu_ls_sel; // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	wire[2:0] s_lsu_ls_type; // 访存类型
	wire[4:0] s_lsu_rd_id_for_ld; // 用于加载的目标寄存器的索引
	wire[31:0] s_lsu_ls_din; // 写数据
	wire[IBUS_TID_WIDTH-1:0] s_lsu_inst_id; // 指令ID
	wire s_lsu_valid;
	wire s_lsu_ready;
	// 乘法器(计算输入)
	wire[32:0] s_mul_op_a; // 操作数A
	wire[32:0] s_mul_op_b; // 操作数B
	wire s_mul_res_sel; // 乘法结果选择(1'b0 -> 低32位, 1'b1 -> 高32位)
	wire[4:0] s_mul_rd_id; // RD索引
	wire[IBUS_TID_WIDTH-1:0] s_mul_inst_id; // 指令ID
	wire s_mul_valid;
	wire s_mul_ready;
	// 除法器(计算输入)
	wire[32:0] s_div_op_a; // 操作数A(被除数)
	wire[32:0] s_div_op_b; // 操作数B(除数)
	wire s_div_rem_sel; // 除法/求余选择(1'b0 -> 除法, 1'b1 -> 求余)
	wire[4:0] s_div_rd_id; // RD索引
	wire[IBUS_TID_WIDTH-1:0] s_div_inst_id; // 指令ID
	wire s_div_valid;
	wire s_div_ready;
	// CPU核内数据ICB主机
	wire[31:0] m_icb_lsu_cmd_data_addr;
	wire m_icb_lsu_cmd_data_read;
	wire[31:0] m_icb_lsu_cmd_data_wdata;
	wire[3:0] m_icb_lsu_cmd_data_wmask;
	wire m_icb_lsu_cmd_data_valid;
	wire m_icb_lsu_cmd_data_ready;
	wire[31:0] m_icb_lsu_rsp_data_rdata;
	wire m_icb_lsu_rsp_data_err;
	wire m_icb_lsu_rsp_data_valid;
	wire m_icb_lsu_rsp_data_ready;
	
	assign s_alu_op_mode = m_alu_op_mode;
	assign s_alu_op1 = m_alu_op1;
	assign s_alu_op2 = m_alu_op2;
	assign s_alu_tid = m_alu_tid;
	assign s_alu_use_res = m_alu_use_res;
	assign s_alu_valid = m_alu_valid;
	
	assign s_csr_addr = m_csr_addr;
	assign s_csr_tid = m_csr_tid;
	assign s_csr_valid = m_csr_valid;
	
	assign s_lsu_ls_sel = m_lsu_ls_sel;
	assign s_lsu_ls_type = m_lsu_ls_type;
	assign s_lsu_rd_id_for_ld = m_lsu_rd_id_for_ld;
	assign s_lsu_ls_din = m_lsu_ls_din;
	assign s_lsu_inst_id = m_lsu_inst_id;
	assign s_lsu_valid = m_lsu_valid;
	assign m_lsu_ready = s_lsu_ready;
	
	assign s_mul_op_a = m_mul_op_a;
	assign s_mul_op_b = m_mul_op_b;
	assign s_mul_res_sel = m_mul_res_sel;
	assign s_mul_rd_id = m_mul_rd_id;
	assign s_mul_inst_id = m_mul_inst_id;
	assign s_mul_valid = m_mul_valid;
	assign m_mul_ready = s_mul_ready;
	
	assign s_div_op_a = m_div_op_a;
	assign s_div_op_b = m_div_op_b;
	assign s_div_rem_sel = m_div_rem_sel;
	assign s_div_rd_id = m_div_rd_id;
	assign s_div_inst_id = m_div_inst_id;
	assign s_div_valid = m_div_valid;
	assign m_div_ready = s_div_ready;
	
	panda_risc_v_func_units #(
		.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
		.DBUS_ACCESS_TIMEOUT_TH(DBUS_ACCESS_TIMEOUT_TH),
		.EN_SGN_PERIOD_MUL(EN_SGN_PERIOD_MUL),
		.SIM_DELAY(SIM_DELAY)
	)func_units(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.s_alu_op_mode(s_alu_op_mode),
		.s_alu_op1(s_alu_op1),
		.s_alu_op2(s_alu_op2),
		.s_alu_tid(s_alu_tid),
		.s_alu_use_res(s_alu_use_res),
		.s_alu_valid(s_alu_valid),
		
		.m_alu_res(),
		.m_alu_tid(),
		.m_alu_brc_cond_res(alu_brc_cond_res),
		.m_alu_valid(),
		
		.s_csr_addr(s_csr_addr),
		.s_csr_tid(s_csr_tid),
		.s_csr_valid(s_csr_valid),
		
		.m_csr_dout(),
		.m_csr_tid(),
		.m_csr_valid(),
		
		.s_lsu_ls_sel(s_lsu_ls_sel),
		.s_lsu_ls_type(s_lsu_ls_type),
		.s_lsu_rd_id_for_ld(s_lsu_rd_id_for_ld),
		.s_lsu_ls_din(s_lsu_ls_din),
		.s_lsu_inst_id(s_lsu_inst_id),
		.s_lsu_valid(s_lsu_valid),
		.s_lsu_ready(s_lsu_ready),
		
		.m_lsu_ls_sel(),
		.m_lsu_rd_id_for_ld(),
		.m_lsu_dout(),
		.m_lsu_ls_addr(),
		.m_lsu_err(),
		.m_lsu_inst_id(),
		.m_lsu_valid(),
		
		.s_mul_op_a(s_mul_op_a),
		.s_mul_op_b(s_mul_op_b),
		.s_mul_res_sel(s_mul_res_sel),
		.s_mul_rd_id(s_mul_rd_id),
		.s_mul_inst_id(s_mul_inst_id),
		.s_mul_valid(s_mul_valid),
		.s_mul_ready(s_mul_ready),
		
		.m_mul_data(),
		.m_mul_rd_id(),
		.m_mul_inst_id(),
		.m_mul_valid(),
		
		.s_div_op_a(s_div_op_a),
		.s_div_op_b(s_div_op_b),
		.s_div_rem_sel(s_div_rem_sel),
		.s_div_rd_id(s_div_rd_id),
		.s_div_inst_id(s_div_inst_id),
		.s_div_valid(s_div_valid),
		.s_div_ready(s_div_ready),
		
		.m_div_data(),
		.m_div_rd_id(),
		.m_div_inst_id(),
		.m_div_valid(),
		
		.csr_atom_raddr(csr_atom_raddr),
		.csr_atom_dout(csr_atom_dout),
		
		.fu_res_vld(fu_res_vld),
		.fu_res_tid(fu_res_tid),
		.fu_res_data(fu_res_data),
		.fu_res_err(fu_res_err),
		
		.m_icb_cmd_data_addr(m_icb_lsu_cmd_data_addr),
		.m_icb_cmd_data_read(m_icb_lsu_cmd_data_read),
		.m_icb_cmd_data_wdata(m_icb_lsu_cmd_data_wdata),
		.m_icb_cmd_data_wmask(m_icb_lsu_cmd_data_wmask),
		.m_icb_cmd_data_valid(m_icb_lsu_cmd_data_valid),
		.m_icb_cmd_data_ready(m_icb_lsu_cmd_data_ready),
		.m_icb_rsp_data_rdata(m_icb_lsu_rsp_data_rdata),
		.m_icb_rsp_data_err(m_icb_lsu_rsp_data_err),
		.m_icb_rsp_data_valid(m_icb_lsu_rsp_data_valid),
		.m_icb_rsp_data_ready(m_icb_lsu_rsp_data_ready),
		
		.dbus_timeout(dbus_timeout),
		.lsu_idle()
	);
	
	/** 重排序队列(ROB) **/
	// ROB控制/状态
	wire rob_clr; // 清空ROB(指示)
	// 准备退休的ROB项
	wire rob_prep_rtr_entry_vld; // 有效标志
	wire rob_prep_rtr_entry_saved; // 结果已保存(标志)
	wire[2:0] rob_prep_rtr_entry_err; // 错误码
	wire[4:0] rob_prep_rtr_entry_rd_id; // 目的寄存器编号
	wire rob_prep_rtr_entry_is_csr_rw_inst; // 是否CSR读写指令
	wire[2:0] rob_prep_rtr_entry_spec_inst_type; // 特殊指令类型
	wire rob_prep_rtr_entry_is_ls_inst_with_sdefc; // 是否带副效应的访存指令
	wire rob_prep_rtr_entry_cancel; // 取消标志
	wire[FU_RES_WIDTH-1:0] rob_prep_rtr_entry_fu_res; // 保存的执行结果
	wire[31:0] rob_prep_rtr_entry_pc; // 指令对应的PC
	wire[31:0] rob_prep_rtr_entry_nxt_pc; // 指令对应的下一有效PC
	wire[1:0] rob_prep_rtr_entry_b_inst_res; // B指令执行结果
	wire[11:0] rob_prep_rtr_entry_csr_rw_waddr; // CSR写地址
	wire[1:0] rob_prep_rtr_entry_csr_rw_upd_type; // CSR更新类型
	wire[31:0] rob_prep_rtr_entry_csr_rw_upd_mask_v; // CSR更新掩码或更新值
	// BRU结果
	wire[IBUS_TID_WIDTH-1:0] s_bru_o_tid; // 指令ID
	wire[31:0] s_bru_o_pc; // 当前PC地址
	wire[31:0] s_bru_o_nxt_pc; // 下一有效PC地址
	wire[1:0] s_bru_o_b_inst_res; // B指令执行结果
	wire s_bru_o_valid;
	// 退休阶段ROB记录广播
	wire rob_rtr_bdcst_vld; // 广播有效
	wire rob_rtr_bdcst_excpt_proc_grant; // 异常处理许可
	
	assign s_bru_o_tid = m_bru_o_tid;
	assign s_bru_o_pc = m_bru_o_pc;
	assign s_bru_o_nxt_pc = m_bru_o_nxt_pc;
	assign s_bru_o_b_inst_res = m_bru_o_b_inst_res;
	assign s_bru_o_valid = m_bru_o_valid;
	
	panda_risc_v_rob #(
		.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
		.FU_ID_WIDTH(FU_ID_WIDTH),
		.ROB_ENTRY_N(ROB_ENTRY_N),
		.CSR_RW_RCD_SLOTS_N(CSR_RW_RCD_SLOTS_N),
		.LSN_FU_N(LSN_FU_N),
		.FU_RES_WIDTH(FU_RES_WIDTH),
		.FU_ERR_WIDTH(FU_ERR_WIDTH),
		.EN_ARCT_REG_POS_TB(EN_ARCT_REG_POS_TB),
		.LSU_FU_ID(LSU_FU_ID),
		.AUTO_CANCEL_SYNC_ERR_ENTRY(AUTO_CANCEL_SYNC_ERR_ENTRY),
		.SIM_DELAY(SIM_DELAY)
	)rob_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.rob_clr(rob_clr),
		.rstr_arct_reg_pos_tb(1'b0),
		.rob_full_n(rob_full_n),
		.rob_empty_n(rob_empty_n),
		.rob_csr_rw_inst_allowed(rob_csr_rw_inst_allowed),
		.rob_has_ls_inst(rob_has_ls_inst),
		.rob_has_ls_sdefc_inst(rob_has_ls_sdefc_inst),
		
		.rob_sng_cancel_vld(1'b0),
		.rob_sng_cancel_tid({IBUS_TID_WIDTH{1'b0}}),
		.rob_yngr_cancel_vld(1'b0),
		.rob_yngr_cancel_bchmk_wptr(6'b000000),
		.rob_yngr_th_ls_sdefc_cancel_vld(1'b0),
		
		.op1_ftc_rs1_id(op1_ftc_rs1_id),
		.op1_ftc_from_reg_file(op1_ftc_from_reg_file),
		.op1_ftc_from_rob(op1_ftc_from_rob),
		.op1_ftc_from_byp(op1_ftc_from_byp),
		.op1_ftc_fuid(op1_ftc_fuid),
		.op1_ftc_tid(op1_ftc_tid),
		.op1_ftc_rob_saved_data(op1_ftc_rob_saved_data),
		.op2_ftc_rs2_id(op2_ftc_rs2_id),
		.op2_ftc_from_reg_file(op2_ftc_from_reg_file),
		.op2_ftc_from_rob(op2_ftc_from_rob),
		.op2_ftc_from_byp(op2_ftc_from_byp),
		.op2_ftc_fuid(op2_ftc_fuid),
		.op2_ftc_tid(op2_ftc_tid),
		.op2_ftc_rob_saved_data(op2_ftc_rob_saved_data),
		
		.rob_prep_rtr_entry_vld(rob_prep_rtr_entry_vld),
		.rob_prep_rtr_entry_saved(rob_prep_rtr_entry_saved),
		.rob_prep_rtr_entry_err(rob_prep_rtr_entry_err),
		.rob_prep_rtr_entry_rd_id(rob_prep_rtr_entry_rd_id),
		.rob_prep_rtr_entry_is_csr_rw_inst(rob_prep_rtr_entry_is_csr_rw_inst),
		.rob_prep_rtr_entry_is_ls_inst_with_sdefc(rob_prep_rtr_entry_is_ls_inst_with_sdefc),
		.rob_prep_rtr_entry_spec_inst_type(rob_prep_rtr_entry_spec_inst_type),
		.rob_prep_rtr_entry_cancel(rob_prep_rtr_entry_cancel),
		.rob_prep_rtr_entry_fu_res(rob_prep_rtr_entry_fu_res),
		.rob_prep_rtr_entry_pc(rob_prep_rtr_entry_pc),
		.rob_prep_rtr_entry_nxt_pc(rob_prep_rtr_entry_nxt_pc),
		.rob_prep_rtr_entry_b_inst_res(rob_prep_rtr_entry_b_inst_res),
		.rob_prep_rtr_entry_csr_rw_waddr(rob_prep_rtr_entry_csr_rw_waddr),
		.rob_prep_rtr_entry_csr_rw_upd_type(rob_prep_rtr_entry_csr_rw_upd_type),
		.rob_prep_rtr_entry_csr_rw_upd_mask_v(rob_prep_rtr_entry_csr_rw_upd_mask_v),
		
		.fu_res_vld(fu_res_vld),
		.fu_res_tid(fu_res_tid),
		.fu_res_data(fu_res_data),
		.fu_res_err(fu_res_err),
		
		.s_bru_o_tid(s_bru_o_tid),
		.s_bru_o_pc(s_bru_o_pc),
		.s_bru_o_nxt_pc(s_bru_o_nxt_pc),
		.s_bru_o_b_inst_res(s_bru_o_b_inst_res),
		.s_bru_o_valid(s_bru_o_valid),
		
		.rob_luc_bdcst_vld(rob_luc_bdcst_vld),
		.rob_luc_bdcst_tid(rob_luc_bdcst_tid),
		.rob_luc_bdcst_fuid(rob_luc_bdcst_fuid),
		.rob_luc_bdcst_rd_id(rob_luc_bdcst_rd_id),
		.rob_luc_bdcst_is_ls_inst(rob_luc_bdcst_is_ls_inst),
		.rob_luc_bdcst_with_ls_sdefc(rob_luc_bdcst_with_ls_sdefc),
		.rob_luc_bdcst_is_csr_rw_inst(rob_luc_bdcst_is_csr_rw_inst),
		.rob_luc_bdcst_csr_rw_inst_msg(rob_luc_bdcst_csr_rw_inst_msg),
		.rob_luc_bdcst_err(rob_luc_bdcst_err),
		.rob_luc_bdcst_spec_inst_type(rob_luc_bdcst_spec_inst_type),
		
		.rob_rtr_bdcst_vld(rob_rtr_bdcst_vld)
	);
	
	/** 交付单元 **/
	panda_risc_v_commit #(
		.DEBUG_ROM_ADDR(DEBUG_ROM_ADDR),
		.DEBUG_SUPPORTED(DEBUG_SUPPORTED),
		.FU_RES_WIDTH(FU_RES_WIDTH),
		.GHR_WIDTH(GHR_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)commit_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.cmt_flush_req(cmt_flush_req),
		.cmt_flush_addr(cmt_flush_addr),
		.cmt_flush_grant(cmt_flush_grant),
		
		.rob_clr(rob_clr),
		
		.rob_prep_rtr_entry_vld(rob_prep_rtr_entry_vld),
		.rob_prep_rtr_entry_saved(rob_prep_rtr_entry_saved),
		.rob_prep_rtr_entry_err(rob_prep_rtr_entry_err),
		.rob_prep_rtr_entry_is_csr_rw_inst(rob_prep_rtr_entry_is_csr_rw_inst),
		.rob_prep_rtr_entry_spec_inst_type(rob_prep_rtr_entry_spec_inst_type),
		.rob_prep_rtr_entry_cancel(rob_prep_rtr_entry_cancel),
		.rob_prep_rtr_entry_fu_res(rob_prep_rtr_entry_fu_res),
		.rob_prep_rtr_entry_pc(rob_prep_rtr_entry_pc),
		.rob_prep_rtr_entry_nxt_pc(rob_prep_rtr_entry_nxt_pc),
		.rob_prep_rtr_entry_b_inst_res(rob_prep_rtr_entry_b_inst_res),
		
		.rob_rtr_bdcst_vld(rob_rtr_bdcst_vld),
		.rob_rtr_bdcst_excpt_proc_grant(rob_rtr_bdcst_excpt_proc_grant),
		
		.inst_retire_cnt_en(inst_retire_cnt_en),
		
		.mstatus_mie_v(mstatus_mie_v),
		.mie_msie_v(mie_msie_v),
		.mie_mtie_v(mie_mtie_v),
		.mie_meie_v(mie_meie_v),
		
		.sw_itr_req_i(sw_itr_req),
		.tmr_itr_req_i(tmr_itr_req),
		.ext_itr_req_i(ext_itr_req),
		
		.itr_expt_enter(itr_expt_enter),
		.itr_expt_is_intr(itr_expt_is_intr),
		.itr_expt_cause(itr_expt_cause),
		.itr_expt_vec_baseaddr(itr_expt_vec_baseaddr),
		.itr_expt_ret_addr(itr_expt_ret_addr),
		.itr_expt_val(itr_expt_val),
		
		.itr_expt_ret(itr_expt_ret),
		.mepc_ret_addr(mepc_ret_addr),
		
		.in_trap(),
		
		.dbg_mode_enter(dbg_mode_enter),
		.dbg_mode_cause(dbg_mode_cause),
		.dbg_mode_ret_addr(dbg_mode_ret_addr),
		
		.dbg_mode_ret(dbg_mode_ret),
		.dpc_ret_addr(dpc_ret_addr),
		
		.dbg_halt_req(dbg_halt_req),
		.dbg_halt_on_reset_req(dbg_halt_on_reset_req),
		.dcsr_ebreakm_v(dcsr_ebreakm_v),
		.dcsr_step_v(dcsr_step_v),
		.in_dbg_mode(in_dbg_mode),
		
		.glb_brc_prdt_on_upd_retired_ghr(glb_brc_prdt_on_upd_retired_ghr),
		.glb_brc_prdt_retired_ghr_shift_in(glb_brc_prdt_retired_ghr_shift_in),
		.glb_brc_prdt_upd_i_req(glb_brc_prdt_upd_i_req),
		.glb_brc_prdt_upd_i_pc(glb_brc_prdt_upd_i_pc),
		.glb_brc_prdt_upd_i_ghr(glb_brc_prdt_upd_i_ghr),
		.glb_brc_prdt_upd_i_brc_taken(glb_brc_prdt_upd_i_brc_taken),
		.glb_brc_prdt_retired_ghr_o(glb_brc_prdt_retired_ghr_o)
	);
	
	/** 写回单元 **/
	panda_risc_v_wbck #(
		.FU_RES_WIDTH(FU_RES_WIDTH)
	)wr_bck(
		.rob_prep_rtr_entry_rd_id(rob_prep_rtr_entry_rd_id),
		.rob_prep_rtr_entry_is_csr_rw_inst(rob_prep_rtr_entry_is_csr_rw_inst),
		.rob_prep_rtr_entry_cancel(rob_prep_rtr_entry_cancel),
		.rob_prep_rtr_entry_fu_res(rob_prep_rtr_entry_fu_res),
		.rob_prep_rtr_entry_csr_rw_waddr(rob_prep_rtr_entry_csr_rw_waddr),
		.rob_prep_rtr_entry_csr_rw_upd_type(rob_prep_rtr_entry_csr_rw_upd_type),
		.rob_prep_rtr_entry_csr_rw_upd_mask_v(rob_prep_rtr_entry_csr_rw_upd_mask_v),
		
		.rob_rtr_bdcst_vld(rob_rtr_bdcst_vld),
		.rob_rtr_bdcst_excpt_proc_grant(rob_rtr_bdcst_excpt_proc_grant),
		
		.reg_file_wen(reg_file_wen),
		.reg_file_waddr(reg_file_waddr),
		.reg_file_din(reg_file_din),
		
		.csr_atom_waddr(csr_atom_waddr),
		.csr_atom_upd_type(csr_atom_upd_type),
		.csr_atom_upd_mask_v(csr_atom_upd_mask_v),
		.csr_atom_wen(csr_atom_wen)
	);
	
	/** 指令ICB主机(命令通道输出寄存器片) **/
	// 输出寄存器片AXIS从机
	wire[63:0] s0_reg_slice_data;
	wire[4:0] s0_reg_slice_user;
	wire s0_reg_slice_valid;
	wire s0_reg_slice_ready;
	// 输出寄存器片AXIS主机
	wire[63:0] m0_reg_slice_data;
	wire[4:0] m0_reg_slice_user;
	wire m0_reg_slice_valid;
	wire m0_reg_slice_ready;
	
	assign {m_icb_cmd_inst_addr, m_icb_cmd_inst_wdata} = m0_reg_slice_data;
	assign {m_icb_cmd_inst_read, m_icb_cmd_inst_wmask} = m0_reg_slice_user;
	assign m_icb_cmd_inst_valid = m0_reg_slice_valid;
	assign m0_reg_slice_ready = m_icb_cmd_inst_ready;
	
	axis_reg_slice #(
		.data_width(64),
		.user_width(5),
		.forward_registered(EN_INST_CMD_FWD),
		.back_registered("false"),
		.en_ready("true"),
		.simulation_delay(SIM_DELAY)
	)axis_reg_slice_u0(
		.clk(aclk),
		.rst_n(aresetn),
		
		.s_axis_data(s0_reg_slice_data),
		.s_axis_user(s0_reg_slice_user),
		.s_axis_valid(s0_reg_slice_valid),
		.s_axis_ready(s0_reg_slice_ready),
		
		.m_axis_data(m0_reg_slice_data),
		.m_axis_user(m0_reg_slice_user),
		.m_axis_valid(m0_reg_slice_valid),
		.m_axis_ready(m0_reg_slice_ready)
	);
	
	/** 数据ICB主机(命令通道输出寄存器片) **/
	// 输出寄存器片AXIS从机
	wire[63:0] s1_reg_slice_data;
	wire[4:0] s1_reg_slice_user;
	wire s1_reg_slice_valid;
	wire s1_reg_slice_ready;
	// 输出寄存器片AXIS主机
	wire[63:0] m1_reg_slice_data;
	wire[4:0] m1_reg_slice_user;
	wire m1_reg_slice_valid;
	wire m1_reg_slice_ready;
	
	assign {m_icb_cmd_data_addr, m_icb_cmd_data_wdata} = m1_reg_slice_data;
	assign {m_icb_cmd_data_read, m_icb_cmd_data_wmask} = m1_reg_slice_user;
	assign m_icb_cmd_data_valid = m1_reg_slice_valid;
	assign m1_reg_slice_ready = m_icb_cmd_data_ready;
	
	axis_reg_slice #(
		.data_width(64),
		.user_width(5),
		.forward_registered(EN_DATA_CMD_FWD),
		.back_registered("false"),
		.en_ready("true"),
		.simulation_delay(SIM_DELAY)
	)axis_reg_slice_u1(
		.clk(aclk),
		.rst_n(aresetn),
		
		.s_axis_data(s1_reg_slice_data),
		.s_axis_user(s1_reg_slice_user),
		.s_axis_valid(s1_reg_slice_valid),
		.s_axis_ready(s1_reg_slice_ready),
		
		.m_axis_data(m1_reg_slice_data),
		.m_axis_user(m1_reg_slice_user),
		.m_axis_valid(m1_reg_slice_valid),
		.m_axis_ready(m1_reg_slice_ready)
	);
	
	/** 指令ICB主机(响应通道输入寄存器片) **/
	// 输入寄存器片AXIS从机
	wire[31:0] s2_reg_slice_data;
	wire s2_reg_slice_user;
	wire s2_reg_slice_valid;
	wire s2_reg_slice_ready;
	// 输入寄存器片AXIS主机
	wire[31:0] m2_reg_slice_data;
	wire m2_reg_slice_user;
	wire m2_reg_slice_valid;
	wire m2_reg_slice_ready;
	
	assign s2_reg_slice_data = m_icb_rsp_inst_rdata;
	assign s2_reg_slice_user = m_icb_rsp_inst_err;
	assign s2_reg_slice_valid = m_icb_rsp_inst_valid;
	assign m_icb_rsp_inst_ready = s2_reg_slice_ready;
	
	axis_reg_slice #(
		.data_width(32),
		.user_width(1),
		.forward_registered("false"),
		.back_registered(EN_INST_RSP_BCK),
		.en_ready("true"),
		.simulation_delay(SIM_DELAY)
	)axis_reg_slice_u2(
		.clk(aclk),
		.rst_n(aresetn),
		
		.s_axis_data(s2_reg_slice_data),
		.s_axis_user(s2_reg_slice_user),
		.s_axis_valid(s2_reg_slice_valid),
		.s_axis_ready(s2_reg_slice_ready),
		
		.m_axis_data(m2_reg_slice_data),
		.m_axis_user(m2_reg_slice_user),
		.m_axis_valid(m2_reg_slice_valid),
		.m_axis_ready(m2_reg_slice_ready)
	);
	
	/** 数据ICB主机(响应通道输入寄存器片) **/
	// 输入寄存器片AXIS从机
	wire[31:0] s3_reg_slice_data;
	wire s3_reg_slice_user;
	wire s3_reg_slice_valid;
	wire s3_reg_slice_ready;
	// 输入寄存器片AXIS主机
	wire[31:0] m3_reg_slice_data;
	wire m3_reg_slice_user;
	wire m3_reg_slice_valid;
	wire m3_reg_slice_ready;
	
	assign s3_reg_slice_data = m_icb_rsp_data_rdata;
	assign s3_reg_slice_user = m_icb_rsp_data_err;
	assign s3_reg_slice_valid = m_icb_rsp_data_valid;
	assign m_icb_rsp_data_ready = s3_reg_slice_ready;
	
	axis_reg_slice #(
		.data_width(32),
		.user_width(1),
		.forward_registered("false"),
		.back_registered(EN_DATA_RSP_BCK),
		.en_ready("true"),
		.simulation_delay(SIM_DELAY)
	)axis_reg_slice_u3(
		.clk(aclk),
		.rst_n(aresetn),
		
		.s_axis_data(s3_reg_slice_data),
		.s_axis_user(s3_reg_slice_user),
		.s_axis_valid(s3_reg_slice_valid),
		.s_axis_ready(s3_reg_slice_ready),
		
		.m_axis_data(m3_reg_slice_data),
		.m_axis_user(m3_reg_slice_user),
		.m_axis_valid(m3_reg_slice_valid),
		.m_axis_ready(m3_reg_slice_ready)
	);
	
	/** 总线控制单元 **/
	// CPU核内指令ICB从机
	wire[31:0] s_icb_biu_cmd_inst_addr;
	wire s_icb_biu_cmd_inst_read;
	wire[31:0] s_icb_biu_cmd_inst_wdata;
	wire[3:0] s_icb_biu_cmd_inst_wmask;
	wire s_icb_biu_cmd_inst_valid;
	wire s_icb_biu_cmd_inst_ready;
	wire[31:0] s_icb_biu_rsp_inst_rdata;
	wire s_icb_biu_rsp_inst_err;
	wire s_icb_biu_rsp_inst_valid;
	wire s_icb_biu_rsp_inst_ready;
	// CPU核内数据ICB从机
	wire[31:0] s_icb_biu_cmd_data_addr;
	wire s_icb_biu_cmd_data_read;
	wire[31:0] s_icb_biu_cmd_data_wdata;
	wire[3:0] s_icb_biu_cmd_data_wmask;
	wire s_icb_biu_cmd_data_valid;
	wire s_icb_biu_cmd_data_ready;
	wire[31:0] s_icb_biu_rsp_data_rdata;
	wire s_icb_biu_rsp_data_err;
	wire s_icb_biu_rsp_data_valid;
	wire s_icb_biu_rsp_data_ready;
	// 指令ICB主机
	wire[31:0] m_icb_biu_cmd_inst_addr;
	wire m_icb_biu_cmd_inst_read;
	wire[31:0] m_icb_biu_cmd_inst_wdata;
	wire[3:0] m_icb_biu_cmd_inst_wmask;
	wire m_icb_biu_cmd_inst_valid;
	wire m_icb_biu_cmd_inst_ready;
	wire[31:0] m_icb_biu_rsp_inst_rdata;
	wire m_icb_biu_rsp_inst_err;
	wire m_icb_biu_rsp_inst_valid;
	wire m_icb_biu_rsp_inst_ready;
	// 数据ICB主机
	wire[31:0] m_icb_biu_cmd_data_addr;
	wire m_icb_biu_cmd_data_read;
	wire[31:0] m_icb_biu_cmd_data_wdata;
	wire[3:0] m_icb_biu_cmd_data_wmask;
	wire m_icb_biu_cmd_data_valid;
	wire m_icb_biu_cmd_data_ready;
	wire[31:0] m_icb_biu_rsp_data_rdata;
	wire m_icb_biu_rsp_data_err;
	wire m_icb_biu_rsp_data_valid;
	wire m_icb_biu_rsp_data_ready;
	
	assign s0_reg_slice_data = {m_icb_biu_cmd_inst_addr, m_icb_biu_cmd_inst_wdata};
	assign s0_reg_slice_user = {m_icb_biu_cmd_inst_read, m_icb_biu_cmd_inst_wmask};
	assign s0_reg_slice_valid = m_icb_biu_cmd_inst_valid;
	assign m_icb_biu_cmd_inst_ready = s0_reg_slice_ready;
	
	assign s1_reg_slice_data = {m_icb_biu_cmd_data_addr, m_icb_biu_cmd_data_wdata};
	assign s1_reg_slice_user = {m_icb_biu_cmd_data_read, m_icb_biu_cmd_data_wmask};
	assign s1_reg_slice_valid = m_icb_biu_cmd_data_valid;
	assign m_icb_biu_cmd_data_ready = s1_reg_slice_ready;
	
	assign m_icb_biu_rsp_inst_rdata = m2_reg_slice_data;
	assign m_icb_biu_rsp_inst_err = m2_reg_slice_user;
	assign m_icb_biu_rsp_inst_valid = m2_reg_slice_valid;
	assign m2_reg_slice_ready = m_icb_biu_rsp_inst_ready;
	
	assign m_icb_biu_rsp_data_rdata = m3_reg_slice_data;
	assign m_icb_biu_rsp_data_err = m3_reg_slice_user;
	assign m_icb_biu_rsp_data_valid = m3_reg_slice_valid;
	assign m3_reg_slice_ready = m_icb_biu_rsp_data_ready;
	
	assign s_icb_biu_cmd_inst_addr = m_icb_imem_cmd_inst_addr;
	assign s_icb_biu_cmd_inst_read = m_icb_imem_cmd_inst_read;
	assign s_icb_biu_cmd_inst_wdata = m_icb_imem_cmd_inst_wdata;
	assign s_icb_biu_cmd_inst_wmask = m_icb_imem_cmd_inst_wmask;
	assign s_icb_biu_cmd_inst_valid = m_icb_imem_cmd_inst_valid;
	assign m_icb_imem_cmd_inst_ready = s_icb_biu_cmd_inst_ready;
	assign m_icb_imem_rsp_inst_rdata = s_icb_biu_rsp_inst_rdata;
	assign m_icb_imem_rsp_inst_err = s_icb_biu_rsp_inst_err;
	assign m_icb_imem_rsp_inst_valid = s_icb_biu_rsp_inst_valid;
	assign s_icb_biu_rsp_inst_ready = m_icb_imem_rsp_inst_ready;
	
	assign s_icb_biu_cmd_data_addr = m_icb_lsu_cmd_data_addr;
	assign s_icb_biu_cmd_data_read = m_icb_lsu_cmd_data_read;
	assign s_icb_biu_cmd_data_wdata = m_icb_lsu_cmd_data_wdata;
	assign s_icb_biu_cmd_data_wmask = m_icb_lsu_cmd_data_wmask;
	assign s_icb_biu_cmd_data_valid = m_icb_lsu_cmd_data_valid;
	assign m_icb_lsu_cmd_data_ready = s_icb_biu_cmd_data_ready;
	assign m_icb_lsu_rsp_data_rdata = s_icb_biu_rsp_data_rdata;
	assign m_icb_lsu_rsp_data_err = s_icb_biu_rsp_data_err;
	assign m_icb_lsu_rsp_data_valid = s_icb_biu_rsp_data_valid;
	assign s_icb_biu_rsp_data_ready = m_icb_lsu_rsp_data_ready;
	
	panda_risc_v_biu #(
		.imem_baseaddr(IMEM_BASEADDR),
		.imem_addr_range(IMEM_ADDR_RANGE),
		.dm_regs_baseaddr(DM_REGS_BASEADDR),
		.dm_regs_addr_range(DM_REGS_ADDR_RANGE),
		.debug_supported(DEBUG_SUPPORTED),
		.simulation_delay(SIM_DELAY)
	)panda_risc_v_biu_u(
		.clk(aclk),
		.resetn(aresetn),
		
		.s_icb_cmd_inst_addr(s_icb_biu_cmd_inst_addr),
		.s_icb_cmd_inst_read(s_icb_biu_cmd_inst_read),
		.s_icb_cmd_inst_wdata(s_icb_biu_cmd_inst_wdata),
		.s_icb_cmd_inst_wmask(s_icb_biu_cmd_inst_wmask),
		.s_icb_cmd_inst_valid(s_icb_biu_cmd_inst_valid),
		.s_icb_cmd_inst_ready(s_icb_biu_cmd_inst_ready),
		.s_icb_rsp_inst_rdata(s_icb_biu_rsp_inst_rdata),
		.s_icb_rsp_inst_err(s_icb_biu_rsp_inst_err),
		.s_icb_rsp_inst_valid(s_icb_biu_rsp_inst_valid),
		.s_icb_rsp_inst_ready(s_icb_biu_rsp_inst_ready),
		
		.s_icb_cmd_data_addr(s_icb_biu_cmd_data_addr),
		.s_icb_cmd_data_read(s_icb_biu_cmd_data_read),
		.s_icb_cmd_data_wdata(s_icb_biu_cmd_data_wdata),
		.s_icb_cmd_data_wmask(s_icb_biu_cmd_data_wmask),
		.s_icb_cmd_data_valid(s_icb_biu_cmd_data_valid),
		.s_icb_cmd_data_ready(s_icb_biu_cmd_data_ready),
		.s_icb_rsp_data_rdata(s_icb_biu_rsp_data_rdata),
		.s_icb_rsp_data_err(s_icb_biu_rsp_data_err),
		.s_icb_rsp_data_valid(s_icb_biu_rsp_data_valid),
		.s_icb_rsp_data_ready(s_icb_biu_rsp_data_ready),
		
		.m_icb_cmd_inst_addr(m_icb_biu_cmd_inst_addr),
		.m_icb_cmd_inst_read(m_icb_biu_cmd_inst_read),
		.m_icb_cmd_inst_wdata(m_icb_biu_cmd_inst_wdata),
		.m_icb_cmd_inst_wmask(m_icb_biu_cmd_inst_wmask),
		.m_icb_cmd_inst_valid(m_icb_biu_cmd_inst_valid),
		.m_icb_cmd_inst_ready(m_icb_biu_cmd_inst_ready),
		.m_icb_rsp_inst_rdata(m_icb_biu_rsp_inst_rdata),
		.m_icb_rsp_inst_err(m_icb_biu_rsp_inst_err),
		.m_icb_rsp_inst_valid(m_icb_biu_rsp_inst_valid),
		.m_icb_rsp_inst_ready(m_icb_biu_rsp_inst_ready),
		
		.m_icb_cmd_data_addr(m_icb_biu_cmd_data_addr),
		.m_icb_cmd_data_read(m_icb_biu_cmd_data_read),
		.m_icb_cmd_data_wdata(m_icb_biu_cmd_data_wdata),
		.m_icb_cmd_data_wmask(m_icb_biu_cmd_data_wmask),
		.m_icb_cmd_data_valid(m_icb_biu_cmd_data_valid),
		.m_icb_cmd_data_ready(m_icb_biu_cmd_data_ready),
		.m_icb_rsp_data_rdata(m_icb_biu_rsp_data_rdata),
		.m_icb_rsp_data_err(m_icb_biu_rsp_data_err),
		.m_icb_rsp_data_valid(m_icb_biu_rsp_data_valid),
		.m_icb_rsp_data_ready(m_icb_biu_rsp_data_ready)
	);
	
endmodule
