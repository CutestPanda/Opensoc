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
小胖达RISC-V处理器核顶层模块

注意：
无

协议:
MEM MASTER
AXI-Lite MASTER

作者: 陈家耀
日期: 2026/02/12
********************************************************************/


module panda_risc_v_core #(
	// IFU配置
	parameter NO_INIT_BTB = "false", // 是否无需初始化BTB存储器
	parameter NO_INIT_PHT = "false", // 是否无需初始化PHT存储器
	// 总线配置
	parameter integer IBUS_ACCESS_TIMEOUT_TH = 16, // 指令总线访问超时周期数(0 -> 不设超时 | 正整数)
	parameter integer IBUS_OUTSTANDING_N = 4, // 指令总线滞外深度(1 | 2 | 4 | 8)
	parameter integer AXI_MEM_DATA_WIDTH = 64, // 存储器AXI主机的数据位宽(32 | 64 | 128 | 256)
	parameter integer MEM_ACCESS_TIMEOUT_TH = 0, // 存储器访问超时周期数(0 -> 不设超时 | 正整数)
	parameter integer PERPH_ACCESS_TIMEOUT_TH = 32, // 外设访问超时周期数(0 -> 不设超时 | 正整数)
	parameter PERPH_ADDR_REGION_0_BASE = 32'h4000_0000, // 外设地址区域#0基地址
	parameter PERPH_ADDR_REGION_0_LEN = 32'h1000_0000, // 外设地址区域#0长度(以字节计)
	parameter PERPH_ADDR_REGION_1_BASE = 32'hF000_0000, // 外设地址区域#1基地址
	parameter PERPH_ADDR_REGION_1_LEN = 32'h0800_0000, // 外设地址区域#1长度(以字节计)
	parameter IMEM_BASEADDR = 32'h0000_0000, // 指令存储器基址
	parameter integer IMEM_ADDR_RANGE = 32 * 1024, // 指令存储器地址区间长度(以字节计)
	parameter DM_REGS_BASEADDR = 32'hFFFF_F800, // DM寄存器区基址
	parameter integer DM_REGS_ADDR_RANGE = 1 * 1024, // DM寄存器区地址区间长度(以字节计)
	// 分支预测配置
	parameter integer GHR_WIDTH = 8, // 全局分支历史寄存器的位宽(<=16)
	parameter integer PC_WIDTH_FOR_PHT_ADDR = 4, // PHT地址截取的低位PC的位宽(必须在范围[1, 16]内)
	parameter integer BHR_WIDTH = 9, // 局部分支历史寄存器(BHR)的位宽
	parameter integer BHT_DEPTH = 256, // 局部分支历史表(BHT)的深度(必须>=2且为2^n)
	parameter PHT_MEM_IMPL = "reg", // PHT存储器的实现方式(reg | sram)
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
	
	// (指令总线)存储器AXI主机
	// [AR通道]
	output wire[31:0] m_axi_imem_araddr,
	output wire[1:0] m_axi_imem_arburst,
	output wire[7:0] m_axi_imem_arlen,
	output wire[2:0] m_axi_imem_arsize,
	output wire m_axi_imem_arvalid,
	input wire m_axi_imem_arready,
	// [R通道]
	input wire[AXI_MEM_DATA_WIDTH-1:0] m_axi_imem_rdata,
	input wire[1:0] m_axi_imem_rresp,
	input wire m_axi_imem_rlast,
	input wire m_axi_imem_rvalid,
	output wire m_axi_imem_rready,
	// [AW通道]
	output wire[31:0] m_axi_imem_awaddr,
	output wire[1:0] m_axi_imem_awburst,
	output wire[7:0] m_axi_imem_awlen,
	output wire[2:0] m_axi_imem_awsize,
	output wire m_axi_imem_awvalid,
	input wire m_axi_imem_awready,
	// [B通道]
	input wire[1:0] m_axi_imem_bresp,
	input wire m_axi_imem_bvalid,
	output wire m_axi_imem_bready,
	// [W通道]
	output wire[AXI_MEM_DATA_WIDTH-1:0] m_axi_imem_wdata,
	output wire[AXI_MEM_DATA_WIDTH/8-1:0] m_axi_imem_wstrb,
	output wire m_axi_imem_wlast,
	output wire m_axi_imem_wvalid,
	input wire m_axi_imem_wready,
	
	// (数据总线)存储器AXI主机
	// [AR通道]
	output wire[31:0] m_axi_dmem_araddr,
	output wire[1:0] m_axi_dmem_arburst,
	output wire[7:0] m_axi_dmem_arlen,
	output wire[2:0] m_axi_dmem_arsize,
	output wire m_axi_dmem_arvalid,
	input wire m_axi_dmem_arready,
	// [R通道]
	input wire[AXI_MEM_DATA_WIDTH-1:0] m_axi_dmem_rdata,
	input wire[1:0] m_axi_dmem_rresp,
	input wire m_axi_dmem_rlast,
	input wire m_axi_dmem_rvalid,
	output wire m_axi_dmem_rready,
	// [AW通道]
	output wire[31:0] m_axi_dmem_awaddr,
	output wire[1:0] m_axi_dmem_awburst,
	output wire[7:0] m_axi_dmem_awlen,
	output wire[2:0] m_axi_dmem_awsize,
	output wire m_axi_dmem_awvalid,
	input wire m_axi_dmem_awready,
	// [B通道]
	input wire[1:0] m_axi_dmem_bresp,
	input wire m_axi_dmem_bvalid,
	output wire m_axi_dmem_bready,
	// [W通道]
	output wire[AXI_MEM_DATA_WIDTH-1:0] m_axi_dmem_wdata,
	output wire[AXI_MEM_DATA_WIDTH/8-1:0] m_axi_dmem_wstrb,
	output wire m_axi_dmem_wlast,
	output wire m_axi_dmem_wvalid,
	input wire m_axi_dmem_wready,
	
	// (数据总线)外设AXI主机
	// [AR通道]
	output wire[31:0] m_axi_perph_araddr,
	output wire[1:0] m_axi_perph_arburst,
	output wire[7:0] m_axi_perph_arlen,
	output wire[2:0] m_axi_perph_arsize,
	output wire m_axi_perph_arvalid,
	input wire m_axi_perph_arready,
	// [R通道]
	input wire[31:0] m_axi_perph_rdata,
	input wire[1:0] m_axi_perph_rresp,
	input wire m_axi_perph_rlast,
	input wire m_axi_perph_rvalid,
	output wire m_axi_perph_rready,
	// [AW通道]
	output wire[31:0] m_axi_perph_awaddr,
	output wire[1:0] m_axi_perph_awburst,
	output wire[7:0] m_axi_perph_awlen,
	output wire[2:0] m_axi_perph_awsize,
	output wire m_axi_perph_awvalid,
	input wire m_axi_perph_awready,
	// [B通道]
	input wire[1:0] m_axi_perph_bresp,
	input wire m_axi_perph_bvalid,
	output wire m_axi_perph_bready,
	// [W通道]
	output wire[31:0] m_axi_perph_wdata,
	output wire[3:0] m_axi_perph_wstrb,
	output wire m_axi_perph_wlast,
	output wire m_axi_perph_wvalid,
	input wire m_axi_perph_wready,
	
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
	
	// PHT存储器
	// 说明: PHT_MEM_IMPL == "sram"时可用
	// [端口A]
	output wire pht_mem_clka,
	output wire pht_mem_ena,
	output wire pht_mem_wea,
	output wire[15:0] pht_mem_addra,
	output wire[1:0] pht_mem_dina,
	input wire[1:0] pht_mem_douta,
	// [端口B]
	output wire pht_mem_clkb,
	output wire pht_mem_enb,
	output wire pht_mem_web,
	output wire[15:0] pht_mem_addrb,
	output wire[1:0] pht_mem_dinb,
	input wire[1:0] pht_mem_doutb,
	
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
	output wire rd_mem_timeout, // 读存储器超时(错误标志)
	output wire wr_mem_timeout, // 写存储器超时(错误标志)
	output wire perph_access_timeout // 外设访问超时(错误标志)
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
	// IFU配置
	localparam EN_IF_REGS = "true"; // 是否启用取指缓存
	localparam integer INST_ADDR_ALIGNMENT_WIDTH = 32; // 指令地址对齐位宽(16 | 32)
	localparam integer IBUS_TID_WIDTH = 6; // 指令总线事务ID位宽(1~16)
	localparam integer PC_TAG_WIDTH = 32 - clogb2(BTB_ENTRY_N) - 2; // PC标签的位宽
	localparam integer BTB_MEM_WIDTH = PC_TAG_WIDTH + 32 + 3 + 1 + 1 + 2; // BTB存储器的数据位宽
	localparam BHT_IMPL = "sram"; // BHT的实现方式(reg | sram)
	localparam EN_REG_SLICE_IN_ICB_INNER_IMEM_CMD_INST = "true"; // 是否在CPU核内指令ICB主机的命令通道插入寄存器片
	// IQ配置
	localparam EN_OUT_OF_ORDER_ISSUE = "true"; // 是否启用乱序发射
	localparam integer IQ0_ENTRY_N = 4; // 发射队列#0条目数(2 | 4 | 8 | 16)
	localparam integer IQ1_ENTRY_N = 4; // 发射队列#1条目数(2 | 4 | 8 | 16)
	localparam integer IQ1_LOW_LA_LSU_LSN_OPT_LEVEL = 1; // 发射队列#1对LSU结果的低时延监听(优化等级)(0 | 1 | 2)
	localparam EN_LOW_LA_BRC_PRDT_FAILURE_PROC = "true"; // 是否启用低时延的分支预测失败处理
	localparam integer BRU_NOMINAL_RES_LATENCY = 1; // BRU名义结果输出时延(0 | 1)
	// CSR初值配置
	localparam INIT_MTVEC_BASE = 30'd0; // mtvec状态寄存器BASE域复位值
	localparam INIT_MCAUSE_INTERRUPT = 1'b0; // mcause状态寄存器Interrupt域复位值
	localparam INIT_MCAUSE_EXCEPTION_CODE = 31'd16; // mcause状态寄存器Exception Code域复位值
	localparam INIT_MISA_MXL = 2'b01; // misa状态寄存器MXL域复位值
	localparam INIT_MISA_EXTENSIONS = 26'b00_0000_0000_0001_0001_0000_0000; // misa状态寄存器Extensions域复位值
	localparam INIT_MVENDORID_BANK = 25'h0_00_00_00; // mvendorid状态寄存器Bank域复位值
	localparam INIT_MVENDORID_OFFSET = 7'h00; // mvendorid状态寄存器Offset域复位值
	localparam INIT_MARCHID = 32'h00_00_00_00; // marchid状态寄存器复位值
	localparam INIT_MIMPID = 32'h31_2E_30_30; // mimpid状态寄存器复位值
	localparam INIT_MHARTID = 32'h00_00_00_00; // mhartid状态寄存器复位值
	// LSU配置
	localparam integer LSU_REQ_BUF_ENTRY_N = 8; // LSU请求缓存区条目数(2~16)
	localparam integer RD_MEM_BUF_ENTRY_N = 4; // 读存储器缓存区条目数(2~16)
	localparam integer WR_MEM_BUF_ENTRY_N = 4; // 写存储器缓存区条目数(2~16)
	localparam EN_LOW_LATENCY_PERPH_ACCESS = "true"; // 是否启用低时延的外设访问模式
	localparam integer EN_LOW_LATENCY_RD_MEM_ACCESS_IN_LSU = 2; // LSU读存储器访问时延优化等级(0 | 1 | 2)
	// BRU配置
	localparam integer BRU_RES_LATENCY = 0; // BRU输出时延(0 | 1)
	// ROB配置
	localparam integer LSU_FU_ID = 2; // LSU的执行单元ID
	localparam AUTO_CANCEL_SYNC_ERR_ENTRY = "false"; // 是否在发射时自动取消带有同步异常的项
	// BIU配置
	localparam EN_BIU_LOW_LATENCY_DMEM_RD = "true"; // 是否使能低时延的数据存储器读模式
	localparam EN_M_AXI_IMEM_AR_REG_SLICE = "true"; // 是否在(指令总线)存储器AXI主机AR通道插入寄存器片
	
	/** 取指单元(IFU) **/
	// 全局冲刷请求
	wire global_flush_req; // 冲刷请求
	wire[31:0] global_flush_addr; // 冲刷地址
	wire global_flush_ack; // 冲刷应答
	// IFU专用冲刷请求
	wire ifu_exclusive_flush_req;
	// IFU给出的冲刷请求
	wire ifu_flush_req; // 冲刷请求
	wire[31:0] ifu_flush_addr; // 冲刷地址
	wire ifu_flush_grant; // 冲刷许可
	// 发射阶段分支信息广播
	wire brc_bdcst_luc_vld; // 广播有效
	wire[IBUS_TID_WIDTH-1:0] brc_bdcst_luc_tid; // 事务ID
	wire brc_bdcst_luc_is_b_inst; // 是否B指令
	wire brc_bdcst_luc_is_jal_inst; // 是否JAL指令
	wire brc_bdcst_luc_is_jalr_inst; // 是否JALR指令
	wire[31:0] brc_bdcst_luc_bta; // 分支目标地址
	// 基于历史的分支预测
	wire glb_brc_prdt_on_clr_retired_ghr; // 清零退休GHR
	wire glb_brc_prdt_on_upd_retired_ghr; // 退休GHR更新指示
	wire glb_brc_prdt_retired_ghr_shift_in; // 退休GHR移位输入
	wire glb_brc_prdt_rstr_speculative_ghr; // 恢复推测GHR指示
	wire glb_brc_prdt_upd_i_req; // 更新请求
	wire[31:0] glb_brc_prdt_upd_i_pc; // 待更新项的PC
	wire[((GHR_WIDTH <= 2) ? 2:GHR_WIDTH)-1:0] glb_brc_prdt_upd_i_ghr; // 待更新项的GHR
	wire[15:0] glb_brc_prdt_upd_i_bhr; // 待更新项的BHR
	// 说明: PHT_MEM_IMPL == "sram"时可用
	wire[1:0] glb_brc_prdt_upd_i_2bit_sat_cnt; // 新的2bit饱和计数器
	wire glb_brc_prdt_upd_i_brc_taken; // 待更新项的实际分支跳转方向
	wire[((GHR_WIDTH <= 2) ? 2:GHR_WIDTH)-1:0] glb_brc_prdt_retired_ghr_o; // 当前的退休GHR
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
	wire[31:0] s_icb_reg_inner_imem_cmd_inst_addr;
	wire s_icb_reg_inner_imem_cmd_inst_read;
	wire[31:0] s_icb_reg_inner_imem_cmd_inst_wdata;
	wire[3:0] s_icb_reg_inner_imem_cmd_inst_wmask;
	wire s_icb_reg_inner_imem_cmd_inst_valid;
	wire s_icb_reg_inner_imem_cmd_inst_ready;
	wire[31:0] m_icb_reg_inner_imem_cmd_inst_addr;
	wire m_icb_reg_inner_imem_cmd_inst_read;
	wire[31:0] m_icb_reg_inner_imem_cmd_inst_wdata;
	wire[3:0] m_icb_reg_inner_imem_cmd_inst_wmask;
	wire m_icb_reg_inner_imem_cmd_inst_valid;
	wire m_icb_reg_inner_imem_cmd_inst_ready;
	wire[31:0] m_icb_inner_imem_cmd_inst_addr;
	wire m_icb_inner_imem_cmd_inst_read;
	wire[31:0] m_icb_inner_imem_cmd_inst_wdata;
	wire[3:0] m_icb_inner_imem_cmd_inst_wmask;
	wire m_icb_inner_imem_cmd_inst_valid;
	wire m_icb_inner_imem_cmd_inst_ready;
	wire[31:0] m_icb_inner_imem_rsp_inst_rdata;
	wire m_icb_inner_imem_rsp_inst_err;
	wire m_icb_inner_imem_rsp_inst_valid;
	wire m_icb_inner_imem_rsp_inst_ready;
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
	
	assign m_icb_inner_imem_cmd_inst_addr = m_icb_reg_inner_imem_cmd_inst_addr;
	assign m_icb_inner_imem_cmd_inst_read = m_icb_reg_inner_imem_cmd_inst_read;
	assign m_icb_inner_imem_cmd_inst_wdata = m_icb_reg_inner_imem_cmd_inst_wdata;
	assign m_icb_inner_imem_cmd_inst_wmask = m_icb_reg_inner_imem_cmd_inst_wmask;
	assign m_icb_inner_imem_cmd_inst_valid = m_icb_reg_inner_imem_cmd_inst_valid;
	assign m_icb_reg_inner_imem_cmd_inst_ready = m_icb_inner_imem_cmd_inst_ready;
	
	panda_risc_v_ifu #(
		.EN_IF_REGS(EN_IF_REGS),
		.IBUS_ACCESS_TIMEOUT_TH(IBUS_ACCESS_TIMEOUT_TH),
		.INST_ADDR_ALIGNMENT_WIDTH(INST_ADDR_ALIGNMENT_WIDTH),
		.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
		.IBUS_OUTSTANDING_N(IBUS_OUTSTANDING_N),
		.IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH(1),
		.PRDT_MSG_WIDTH(96),
		.GHR_WIDTH(GHR_WIDTH),
		.PC_WIDTH(PC_WIDTH_FOR_PHT_ADDR),
		.BHR_WIDTH(BHR_WIDTH),
		.BHT_DEPTH(BHT_DEPTH),
		.PHT_MEM_IMPL(PHT_MEM_IMPL),
		.BHT_IMPL(BHT_IMPL),
		.NO_INIT_PHT(NO_INIT_PHT),
		.BTB_WAY_N(BTB_WAY_N),
		.BTB_ENTRY_N(BTB_ENTRY_N),
		.PC_TAG_WIDTH(PC_TAG_WIDTH),
		.BTB_MEM_WIDTH(BTB_MEM_WIDTH),
		.NO_INIT_BTB(NO_INIT_BTB),
		.RAS_ENTRY_N(RAS_ENTRY_N),
		.SIM_DELAY(SIM_DELAY)
	)ifu_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.sys_reset_req(sys_reset_req),
		.rst_pc(rst_pc),
		.flush_req(global_flush_req),
		.ifu_exclusive_flush_req(ifu_exclusive_flush_req),
		.flush_addr(global_flush_addr),
		.rst_ack(),
		.flush_ack(global_flush_ack),
		
		.ifu_flush_req(ifu_flush_req),
		.ifu_flush_addr(ifu_flush_addr),
		.ifu_flush_grant(ifu_flush_grant),
		
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
		.glb_brc_prdt_upd_i_bhr(glb_brc_prdt_upd_i_bhr),
		.glb_brc_prdt_upd_i_2bit_sat_cnt(glb_brc_prdt_upd_i_2bit_sat_cnt),
		.glb_brc_prdt_upd_i_brc_taken(glb_brc_prdt_upd_i_brc_taken),
		.glb_brc_prdt_retired_ghr_o(glb_brc_prdt_retired_ghr_o),
		
		.pht_mem_clka(pht_mem_clka),
		.pht_mem_ena(pht_mem_ena),
		.pht_mem_wea(pht_mem_wea),
		.pht_mem_addra(pht_mem_addra),
		.pht_mem_dina(pht_mem_dina),
		.pht_mem_douta(pht_mem_douta),
		
		.pht_mem_clkb(pht_mem_clkb),
		.pht_mem_enb(pht_mem_enb),
		.pht_mem_web(pht_mem_web),
		.pht_mem_addrb(pht_mem_addrb),
		.pht_mem_dinb(pht_mem_dinb),
		.pht_mem_doutb(pht_mem_doutb),
		
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
		
		.m_icb_cmd_inst_addr(s_icb_reg_inner_imem_cmd_inst_addr),
		.m_icb_cmd_inst_read(s_icb_reg_inner_imem_cmd_inst_read),
		.m_icb_cmd_inst_wdata(s_icb_reg_inner_imem_cmd_inst_wdata),
		.m_icb_cmd_inst_wmask(s_icb_reg_inner_imem_cmd_inst_wmask),
		.m_icb_cmd_inst_valid(s_icb_reg_inner_imem_cmd_inst_valid),
		.m_icb_cmd_inst_ready(s_icb_reg_inner_imem_cmd_inst_ready),
		.m_icb_rsp_inst_rdata(m_icb_inner_imem_rsp_inst_rdata),
		.m_icb_rsp_inst_err(m_icb_inner_imem_rsp_inst_err),
		.m_icb_rsp_inst_valid(m_icb_inner_imem_rsp_inst_valid),
		.m_icb_rsp_inst_ready(m_icb_inner_imem_rsp_inst_ready),
		
		.suppressing_ibus_access(suppressing_ibus_access),
		.clr_inst_buf_while_suppressing(clr_inst_buf_while_suppressing),
		.ibus_timeout(ibus_timeout)
	);
	
	axis_reg_slice #(
		.data_width(64),
		.user_width(5),
		.forward_registered("false"),
		.back_registered(EN_REG_SLICE_IN_ICB_INNER_IMEM_CMD_INST),
		.en_ready("true"),
		.en_clk_en("false"),
		.simulation_delay(SIM_DELAY)
	)icb_inner_imem_cmd_inst_reg_slice_u(
		.clk(aclk),
		.rst_n(aresetn),
		.clken(1'b1),
		
		.s_axis_data({s_icb_reg_inner_imem_cmd_inst_addr, s_icb_reg_inner_imem_cmd_inst_wdata}),
		.s_axis_keep(),
		.s_axis_user({s_icb_reg_inner_imem_cmd_inst_read, s_icb_reg_inner_imem_cmd_inst_wmask}),
		.s_axis_last(),
		.s_axis_valid(s_icb_reg_inner_imem_cmd_inst_valid),
		.s_axis_ready(s_icb_reg_inner_imem_cmd_inst_ready),
		
		.m_axis_data({m_icb_reg_inner_imem_cmd_inst_addr, m_icb_reg_inner_imem_cmd_inst_wdata}),
		.m_axis_keep(),
		.m_axis_user({m_icb_reg_inner_imem_cmd_inst_read, m_icb_reg_inner_imem_cmd_inst_wmask}),
		.m_axis_last(),
		.m_axis_valid(m_icb_reg_inner_imem_cmd_inst_valid),
		.m_axis_ready(m_icb_reg_inner_imem_cmd_inst_ready)
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
	// ROB控制/状态
	wire rob_full_n; // ROB满(标志)
	wire rob_csr_rw_inst_allowed; // 允许发射CSR读写指令(标志)
	wire[7:0] rob_entry_id_to_be_written; // 待写项的条目编号
	wire rob_entry_age_tbit_to_be_written; // 待写项的年龄翻转位
	// 执行单元结果返回
	wire[((EN_OUT_OF_ORDER_ISSUE == "true") ? 6:5)-1:0] fu_res_vld; // 有效标志
	wire[((EN_OUT_OF_ORDER_ISSUE == "true") ? 6:5)*IBUS_TID_WIDTH-1:0] fu_res_tid; // 指令ID
	wire[((EN_OUT_OF_ORDER_ISSUE == "true") ? 6:5)*32-1:0] fu_res_data; // 执行结果
	wire[((EN_OUT_OF_ORDER_ISSUE == "true") ? 6:5)*3-1:0] fu_res_err; // 错误码
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
	wire[2:0] m_regs_rd_fuid; // 执行单元ID
	wire m_regs_rd_valid;
	wire m_regs_rd_ready;
	// 写发射队列#0
	wire[IBUS_TID_WIDTH-1:0] m_wr_iq0_inst_id; // 指令ID
	wire[3:0] m_wr_iq0_fuid; // 执行单元ID
	wire[7:0] m_wr_iq0_rob_entry_id; // ROB条目ID
	wire[clogb2(ROB_ENTRY_N-1)+1:0] m_wr_iq0_age_tag; // 年龄标识
	wire[3:0] m_wr_iq0_op1_lsn_fuid; // OP1所监听的执行单元ID
	wire[3:0] m_wr_iq0_op2_lsn_fuid; // OP2所监听的执行单元ID
	wire[IBUS_TID_WIDTH-1:0] m_wr_iq0_op1_lsn_inst_id; // OP1所监听的指令ID
	wire[IBUS_TID_WIDTH-1:0] m_wr_iq0_op2_lsn_inst_id; // OP2所监听的指令ID
	wire[63:0] m_wr_iq0_other_payload; // 其他负载数据
	wire[31:0] m_wr_iq0_op1_pre_fetched; // 预取的OP1
	wire[31:0] m_wr_iq0_op2_pre_fetched; // 预取的OP2
	wire m_wr_iq0_op1_rdy; // OP1已就绪
	wire m_wr_iq0_op2_rdy; // OP2已就绪
	wire m_wr_iq0_valid;
	wire m_wr_iq0_ready;
	// 写发射队列#1
	wire[IBUS_TID_WIDTH-1:0] m_wr_iq1_inst_id; // 指令ID
	wire[3:0] m_wr_iq1_fuid; // 执行单元ID
	wire[7:0] m_wr_iq1_rob_entry_id; // ROB条目ID
	wire[clogb2(ROB_ENTRY_N-1)+1:0] m_wr_iq1_age_tag; // 年龄标识
	wire[3:0] m_wr_iq1_op1_lsn_fuid; // OP1所监听的执行单元ID
	wire[3:0] m_wr_iq1_op2_lsn_fuid; // OP2所监听的执行单元ID
	wire[IBUS_TID_WIDTH-1:0] m_wr_iq1_op1_lsn_inst_id; // OP1所监听的指令ID
	wire[IBUS_TID_WIDTH-1:0] m_wr_iq1_op2_lsn_inst_id; // OP2所监听的指令ID
	wire[255:0] m_wr_iq1_other_payload; // 其他负载数据
	wire[31:0] m_wr_iq1_op1_pre_fetched; // 预取的OP1
	wire[31:0] m_wr_iq1_op2_pre_fetched; // 预取的OP2
	wire m_wr_iq1_op1_rdy; // OP1已就绪
	wire m_wr_iq1_op2_rdy; // OP2已就绪
	wire m_wr_iq1_valid;
	wire m_wr_iq1_ready;
	// 数据相关性检查
	// [操作数1]
	wire[4:0] op1_ftc_rs1_id; // 1号源寄存器编号
	wire op1_ftc_from_reg_file; // 从寄存器堆取到操作数(标志)
	wire op1_ftc_from_rob; // 从ROB取到操作数(标志)
	wire op1_ftc_from_byp; // 从旁路网络取到操作数(标志)
	wire[2:0] op1_ftc_fuid; // 待旁路的执行单元编号
	wire[IBUS_TID_WIDTH-1:0] op1_ftc_tid; // 待旁路的指令ID
	wire[31:0] op1_ftc_rob_saved_data; // ROB暂存的执行结果
	// [操作数2]
	wire[4:0] op2_ftc_rs2_id; // 2号源寄存器编号
	wire op2_ftc_from_reg_file; // 从寄存器堆取到操作数(标志)
	wire op2_ftc_from_rob; // 从ROB取到操作数(标志)
	wire op2_ftc_from_byp; // 从旁路网络取到操作数(标志)
	wire[2:0] op2_ftc_fuid; // 待旁路的执行单元编号
	wire[IBUS_TID_WIDTH-1:0] op2_ftc_tid; // 待旁路的指令ID
	wire[31:0] op2_ftc_rob_saved_data; // ROB暂存的执行结果
	// 发射阶段ROB记录广播
	wire rob_luc_bdcst_vld; // 广播有效
	wire[IBUS_TID_WIDTH-1:0] rob_luc_bdcst_tid; // 指令ID
	wire[3:0] rob_luc_bdcst_fuid; // 被发射到的执行单元ID
	wire[4:0] rob_luc_bdcst_rd_id; // 目的寄存器编号
	wire rob_luc_bdcst_is_ls_inst; // 是否加载/存储指令
	wire rob_luc_bdcst_is_csr_rw_inst; // 是否CSR读写指令
	wire[13:0] rob_luc_bdcst_csr_rw_inst_msg; // CSR读写指令信息({CSR写地址(12bit), CSR更新类型(2bit)})
	wire[2:0] rob_luc_bdcst_err; // 错误类型
	wire[2:0] rob_luc_bdcst_spec_inst_type; // 特殊指令类型
	wire rob_luc_bdcst_is_b_inst; // 是否B指令
	wire[31:0] rob_luc_bdcst_pc; // 指令对应的PC
	wire[31:0] rob_luc_bdcst_nxt_pc; // 指令对应的下一有效PC
	wire[1:0] rob_luc_bdcst_org_2bit_sat_cnt; // 原来的2bit饱和计数器
	wire[15:0] rob_luc_bdcst_bhr; // BHR
	
	assign s_regs_rd_data = m_if_res_data;
	assign s_regs_rd_msg = m_if_res_msg;
	assign s_regs_rd_id = m_if_res_id;
	assign s_regs_rd_is_first_inst_after_rst = m_if_res_is_first_inst_after_rst;
	assign s_regs_rd_valid = m_if_res_valid;
	assign m_if_res_ready = s_regs_rd_ready;
	
	generate
		if(EN_OUT_OF_ORDER_ISSUE == "true")
		begin
			panda_risc_v_regs_rd_out_of_order #(
				.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
				.AGE_TAG_WIDTH(clogb2(ROB_ENTRY_N-1)+1+1),
				.LSN_FU_N((EN_OUT_OF_ORDER_ISSUE == "true") ? 6:5),
				.IQ0_OTHER_PAYLOAD_WIDTH(64),
				.IQ1_OTHER_PAYLOAD_WIDTH(256),
				.ROB_ENTRY_N(ROB_ENTRY_N),
				.SIM_DELAY(SIM_DELAY)
			)op_pre_fetch_u(
				.aclk(aclk),
				.aresetn(aresetn),
				
				.sys_reset_req(sys_reset_req),
				.flush_req(global_flush_req),
				
				.rob_full_n(rob_full_n),
				.rob_csr_rw_inst_allowed(rob_csr_rw_inst_allowed),
				.rob_entry_id_to_be_written(rob_entry_id_to_be_written),
				.rob_entry_age_tbit_to_be_written(rob_entry_age_tbit_to_be_written),
				
				.fu_res_data(fu_res_data),
				.fu_res_tid(fu_res_tid),
				.fu_res_vld(fu_res_vld),
				
				.s_regs_rd_data(s_regs_rd_data),
				.s_regs_rd_msg(s_regs_rd_msg),
				.s_regs_rd_id(s_regs_rd_id),
				.s_regs_rd_is_first_inst_after_rst(s_regs_rd_is_first_inst_after_rst),
				.s_regs_rd_valid(s_regs_rd_valid),
				.s_regs_rd_ready(s_regs_rd_ready),
				
				.m_wr_iq0_inst_id(m_wr_iq0_inst_id),
				.m_wr_iq0_fuid(m_wr_iq0_fuid),
				.m_wr_iq0_rob_entry_id(m_wr_iq0_rob_entry_id),
				.m_wr_iq0_age_tag(m_wr_iq0_age_tag),
				.m_wr_iq0_op1_lsn_fuid(m_wr_iq0_op1_lsn_fuid),
				.m_wr_iq0_op2_lsn_fuid(m_wr_iq0_op2_lsn_fuid),
				.m_wr_iq0_op1_lsn_inst_id(m_wr_iq0_op1_lsn_inst_id),
				.m_wr_iq0_op2_lsn_inst_id(m_wr_iq0_op2_lsn_inst_id),
				.m_wr_iq0_other_payload(m_wr_iq0_other_payload),
				.m_wr_iq0_op1_pre_fetched(m_wr_iq0_op1_pre_fetched),
				.m_wr_iq0_op2_pre_fetched(m_wr_iq0_op2_pre_fetched),
				.m_wr_iq0_op1_rdy(m_wr_iq0_op1_rdy),
				.m_wr_iq0_op2_rdy(m_wr_iq0_op2_rdy),
				.m_wr_iq0_valid(m_wr_iq0_valid),
				.m_wr_iq0_ready(m_wr_iq0_ready),
				
				.m_wr_iq1_inst_id(m_wr_iq1_inst_id),
				.m_wr_iq1_fuid(m_wr_iq1_fuid),
				.m_wr_iq1_rob_entry_id(m_wr_iq1_rob_entry_id),
				.m_wr_iq1_age_tag(m_wr_iq1_age_tag),
				.m_wr_iq1_op1_lsn_fuid(m_wr_iq1_op1_lsn_fuid),
				.m_wr_iq1_op2_lsn_fuid(m_wr_iq1_op2_lsn_fuid),
				.m_wr_iq1_op1_lsn_inst_id(m_wr_iq1_op1_lsn_inst_id),
				.m_wr_iq1_op2_lsn_inst_id(m_wr_iq1_op2_lsn_inst_id),
				.m_wr_iq1_other_payload(m_wr_iq1_other_payload),
				.m_wr_iq1_op1_pre_fetched(m_wr_iq1_op1_pre_fetched),
				.m_wr_iq1_op2_pre_fetched(m_wr_iq1_op2_pre_fetched),
				.m_wr_iq1_op1_rdy(m_wr_iq1_op1_rdy),
				.m_wr_iq1_op2_rdy(m_wr_iq1_op2_rdy),
				.m_wr_iq1_valid(m_wr_iq1_valid),
				.m_wr_iq1_ready(m_wr_iq1_ready),
				
				.op1_ftc_rs1_id(op1_ftc_rs1_id),
				.op1_ftc_from_reg_file(op1_ftc_from_reg_file),
				.op1_ftc_from_rob(op1_ftc_from_rob),
				.op1_ftc_from_byp(op1_ftc_from_byp),
				.op1_ftc_fuid(op1_ftc_fuid | 4'd0),
				.op1_ftc_tid(op1_ftc_tid),
				.op1_ftc_rob_saved_data(op1_ftc_rob_saved_data),
				.op2_ftc_rs2_id(op2_ftc_rs2_id),
				.op2_ftc_from_reg_file(op2_ftc_from_reg_file),
				.op2_ftc_from_rob(op2_ftc_from_rob),
				.op2_ftc_from_byp(op2_ftc_from_byp),
				.op2_ftc_fuid(op2_ftc_fuid | 4'd0),
				.op2_ftc_tid(op2_ftc_tid),
				.op2_ftc_rob_saved_data(op2_ftc_rob_saved_data),
				
				.rob_luc_bdcst_vld(rob_luc_bdcst_vld),
				.rob_luc_bdcst_tid(rob_luc_bdcst_tid),
				.rob_luc_bdcst_fuid(rob_luc_bdcst_fuid),
				.rob_luc_bdcst_rd_id(rob_luc_bdcst_rd_id),
				.rob_luc_bdcst_is_ls_inst(rob_luc_bdcst_is_ls_inst),
				.rob_luc_bdcst_is_csr_rw_inst(rob_luc_bdcst_is_csr_rw_inst),
				.rob_luc_bdcst_csr_rw_inst_msg(rob_luc_bdcst_csr_rw_inst_msg),
				.rob_luc_bdcst_err(rob_luc_bdcst_err),
				.rob_luc_bdcst_spec_inst_type(rob_luc_bdcst_spec_inst_type),
				.rob_luc_bdcst_is_b_inst(rob_luc_bdcst_is_b_inst),
				.rob_luc_bdcst_pc(rob_luc_bdcst_pc),
				.rob_luc_bdcst_nxt_pc(rob_luc_bdcst_nxt_pc),
				.rob_luc_bdcst_org_2bit_sat_cnt(rob_luc_bdcst_org_2bit_sat_cnt),
				.rob_luc_bdcst_bhr(rob_luc_bdcst_bhr),
				
				.reg_file_raddr_p0(reg_file_raddr_p0),
				.reg_file_dout_p0(reg_file_dout_p0),
				.reg_file_raddr_p1(reg_file_raddr_p1),
				.reg_file_dout_p1(reg_file_dout_p1)
			);
		end
		else
		begin
			panda_risc_v_regs_rd_in_order #(
				.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
				.LSN_FU_N((EN_OUT_OF_ORDER_ISSUE == "true") ? 6:5),
				.FU_ID_WIDTH(3),
				.FU_RES_WIDTH(32),
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
				
				.fu_res_data(fu_res_data),
				.fu_res_tid(fu_res_tid),
				.fu_res_vld(fu_res_vld),
				
				.reg_file_raddr_p0(reg_file_raddr_p0),
				.reg_file_dout_p0(reg_file_dout_p0),
				.reg_file_raddr_p1(reg_file_raddr_p1),
				.reg_file_dout_p1(reg_file_dout_p1)
			);
		end
	endgenerate
	
	/** 发射队列 **/
	// 发射队列控制/状态
	wire clr_iq0; // 清空发射队列#0(指示)
	wire clr_iq1; // 清空发射队列#1(指示)
	// 读存储器结果快速旁路
	wire on_get_instant_rd_mem_res;
	wire[IBUS_TID_WIDTH-1:0] inst_id_of_instant_rd_mem_res_gotten;
	wire[31:0] data_of_instant_rd_mem_res_gotten;
	// LSU状态
	wire has_buffered_wr_mem_req; // 存在已缓存的写存储器请求(标志)
	wire has_processing_perph_access_req; // 存在处理中的外设访问请求(标志)
	// BRU处理结果返回
	wire[IBUS_TID_WIDTH-1:0] s_bru_o_to_iq_tid; // 指令ID
	wire s_bru_o_to_iq_valid;
	// BRU名义结果
	wire bru_nominal_res_vld; // 有效标志
	wire[IBUS_TID_WIDTH-1:0] bru_nominal_res_tid; // 指令ID
	wire[31:0] bru_nominal_res; // 执行结果
	// 写发射队列#0
	wire[IBUS_TID_WIDTH-1:0] s_wr_iq0_inst_id; // 指令ID
	wire[3:0] s_wr_iq0_fuid; // 执行单元ID
	wire[7:0] s_wr_iq0_rob_entry_id; // ROB条目ID
	wire[clogb2(ROB_ENTRY_N-1)+1:0] s_wr_iq0_age_tag; // 年龄标识
	wire[3:0] s_wr_iq0_op1_lsn_fuid; // OP1所监听的执行单元ID
	wire[3:0] s_wr_iq0_op2_lsn_fuid; // OP2所监听的执行单元ID
	wire[IBUS_TID_WIDTH-1:0] s_wr_iq0_op1_lsn_inst_id; // OP1所监听的指令ID
	wire[IBUS_TID_WIDTH-1:0] s_wr_iq0_op2_lsn_inst_id; // OP2所监听的指令ID
	wire[63:0] s_wr_iq0_other_payload; // 其他负载数据
	wire[31:0] s_wr_iq0_op1_pre_fetched; // 预取的OP1
	wire[31:0] s_wr_iq0_op2_pre_fetched; // 预取的OP2
	wire s_wr_iq0_op1_rdy; // OP1已就绪
	wire s_wr_iq0_op2_rdy; // OP2已就绪
	wire s_wr_iq0_valid;
	wire s_wr_iq0_ready;
	// 写发射队列#1
	wire[IBUS_TID_WIDTH-1:0] s_wr_iq1_inst_id; // 指令ID
	wire[3:0] s_wr_iq1_fuid; // 执行单元ID
	wire[7:0] s_wr_iq1_rob_entry_id; // ROB条目ID
	wire[clogb2(ROB_ENTRY_N-1)+1:0] s_wr_iq1_age_tag; // 年龄标识
	wire[3:0] s_wr_iq1_op1_lsn_fuid; // OP1所监听的执行单元ID
	wire[3:0] s_wr_iq1_op2_lsn_fuid; // OP2所监听的执行单元ID
	wire[IBUS_TID_WIDTH-1:0] s_wr_iq1_op1_lsn_inst_id; // OP1所监听的指令ID
	wire[IBUS_TID_WIDTH-1:0] s_wr_iq1_op2_lsn_inst_id; // OP2所监听的指令ID
	wire[255:0] s_wr_iq1_other_payload; // 其他负载数据
	wire[31:0] s_wr_iq1_op1_pre_fetched; // 预取的OP1
	wire[31:0] s_wr_iq1_op2_pre_fetched; // 预取的OP2
	wire s_wr_iq1_op1_rdy; // OP1已就绪
	wire s_wr_iq1_op2_rdy; // OP2已就绪
	wire s_wr_iq1_valid;
	wire s_wr_iq1_ready;
	// 取操作数和译码结果
	wire[127:0] m_op_ftc_id_res_data; // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	wire[162:0] m_op_ftc_id_res_msg; // 取指附加信息({分支预测信息(160bit), 错误码(3bit)})
	wire[143:0] m_op_ftc_id_res_dcd_res; // 译码信息({打包的FU操作信息(128bit), 打包的指令类型标志(16bit)})
	wire[IBUS_TID_WIDTH-1:0] m_op_ftc_id_res_id; // 指令ID
	wire m_op_ftc_id_res_is_first_inst_after_rst; // 是否复位释放后的第1条指令
	wire[31:0] m_op_ftc_id_res_op1; // 操作数1
	wire[31:0] m_op_ftc_id_res_op2; // 操作数2
	wire m_op_ftc_id_res_valid;
	wire m_op_ftc_id_res_ready;
	// 发射单元输出
	wire[127:0] m_luc_data; // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	wire[162:0] m_luc_msg; // 取指附加信息({分支预测信息(160bit), 错误码(3bit)})
	wire[143:0] m_luc_dcd_res; // 译码信息({打包的FU操作信息(128bit), 打包的指令类型标志(16bit)})
	wire[IBUS_TID_WIDTH-1:0] m_luc_id; // 指令编号
	wire m_luc_is_first_inst_after_rst; // 是否复位释放后的第1条指令
	wire[31:0] m_luc_op1; // 操作数1
	wire[31:0] m_luc_op2; // 操作数2
	wire m_luc_valid;
	wire m_luc_ready;
	// 更新ROB的"CSR更新掩码或更新值"字段
	wire[31:0] saving_csr_rw_msg_upd_mask_v; // 更新掩码或更新值
	wire[7:0] saving_csr_rw_msg_rob_entry_id; // ROB条目编号
	wire saving_csr_rw_msg_vld;
	// 更新ROB的"指令对应的下一有效PC"字段
	wire on_upd_rob_field_nxt_pc;
	wire[IBUS_TID_WIDTH-1:0] inst_id_of_upd_rob_field_nxt_pc;
	wire[31:0] rob_field_nxt_pc;
	// 分发单元给出的BRU输入
	wire[127:0] m_bru_i_data; // 取指数据({指令对应的PC(32bit), 打包的预译码信息(64bit), 取到的指令(32bit)})
	wire[162:0] m_bru_i_msg; // 取指附加信息({分支预测信息(160bit), 错误码(3bit)})
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
	// [LSU]
	wire m_lsu_ls_sel; // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	wire[2:0] m_lsu_ls_type; // 访存类型
	wire[4:0] m_lsu_rd_id_for_ld; // 用于加载的目标寄存器的索引
	wire[31:0] m_lsu_ls_addr; // 访存地址
	wire[31:0] m_lsu_ls_din; // 写数据
	wire[IBUS_TID_WIDTH-1:0] m_lsu_inst_id; // 指令ID
	wire m_lsu_valid;
	wire m_lsu_ready;
	// [BRU]
	wire[159:0] m_bru_prdt_msg; // 分支预测信息
	wire[15:0] m_bru_inst_type; // 打包的指令类型标志
	wire[IBUS_TID_WIDTH-1:0] m_bru_tid; // 指令ID
	wire m_bru_prdt_suc; // 是否预判分支预测成功
	wire m_bru_brc_cond_res; // 分支判定结果
	wire m_bru_valid;
	wire m_bru_ready;
	
	assign s_wr_iq0_inst_id = m_wr_iq0_inst_id;
	assign s_wr_iq0_fuid = m_wr_iq0_fuid;
	assign s_wr_iq0_rob_entry_id = m_wr_iq0_rob_entry_id;
	assign s_wr_iq0_age_tag = m_wr_iq0_age_tag;
	assign s_wr_iq0_op1_lsn_fuid = m_wr_iq0_op1_lsn_fuid;
	assign s_wr_iq0_op2_lsn_fuid = m_wr_iq0_op2_lsn_fuid;
	assign s_wr_iq0_op1_lsn_inst_id = m_wr_iq0_op1_lsn_inst_id;
	assign s_wr_iq0_op2_lsn_inst_id = m_wr_iq0_op2_lsn_inst_id;
	assign s_wr_iq0_other_payload = m_wr_iq0_other_payload;
	assign s_wr_iq0_op1_pre_fetched = m_wr_iq0_op1_pre_fetched;
	assign s_wr_iq0_op2_pre_fetched = m_wr_iq0_op2_pre_fetched;
	assign s_wr_iq0_op1_rdy = m_wr_iq0_op1_rdy;
	assign s_wr_iq0_op2_rdy = m_wr_iq0_op2_rdy;
	assign s_wr_iq0_valid = m_wr_iq0_valid;
	assign m_wr_iq0_ready = s_wr_iq0_ready;
	
	assign s_wr_iq1_inst_id = m_wr_iq1_inst_id;
	assign s_wr_iq1_fuid = m_wr_iq1_fuid;
	assign s_wr_iq1_rob_entry_id = m_wr_iq1_rob_entry_id;
	assign s_wr_iq1_age_tag = m_wr_iq1_age_tag;
	assign s_wr_iq1_op1_lsn_fuid = m_wr_iq1_op1_lsn_fuid;
	assign s_wr_iq1_op2_lsn_fuid = m_wr_iq1_op2_lsn_fuid;
	assign s_wr_iq1_op1_lsn_inst_id = m_wr_iq1_op1_lsn_inst_id;
	assign s_wr_iq1_op2_lsn_inst_id = m_wr_iq1_op2_lsn_inst_id;
	assign s_wr_iq1_other_payload = m_wr_iq1_other_payload;
	assign s_wr_iq1_op1_pre_fetched = m_wr_iq1_op1_pre_fetched;
	assign s_wr_iq1_op2_pre_fetched = m_wr_iq1_op2_pre_fetched;
	assign s_wr_iq1_op1_rdy = m_wr_iq1_op1_rdy;
	assign s_wr_iq1_op2_rdy = m_wr_iq1_op2_rdy;
	assign s_wr_iq1_valid = m_wr_iq1_valid;
	assign m_wr_iq1_ready = s_wr_iq1_ready;
	
	generate
		if(EN_OUT_OF_ORDER_ISSUE == "true")
		begin
			panda_risc_v_issue_queue #(
				.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
				.IQ0_ENTRY_N(IQ0_ENTRY_N),
				.IQ1_ENTRY_N(IQ1_ENTRY_N),
				.AGE_TAG_WIDTH(clogb2(ROB_ENTRY_N-1)+1+1),
				.LSN_FU_N((EN_OUT_OF_ORDER_ISSUE == "true") ? 6:5),
				.LSU_FU_ID(LSU_FU_ID),
				.IQ1_LOW_LA_LSU_LSN_OPT_LEVEL(IQ1_LOW_LA_LSU_LSN_OPT_LEVEL),
				.EN_LOW_LA_BRC_PRDT_FAILURE_PROC(EN_LOW_LA_BRC_PRDT_FAILURE_PROC),
				.IQ0_OTHER_PAYLOAD_WIDTH(64),
				.IQ1_OTHER_PAYLOAD_WIDTH(256),
				.BRU_NOMINAL_RES_LATENCY(BRU_NOMINAL_RES_LATENCY),
				.SIM_DELAY(SIM_DELAY)
			)issue_queue_u(
				.aclk(aclk),
				.aresetn(aresetn),
				
				.clr_iq0(clr_iq0),
				.clr_iq1(clr_iq1),
				
				.on_get_instant_rd_mem_res(on_get_instant_rd_mem_res),
				.inst_id_of_instant_rd_mem_res_gotten(inst_id_of_instant_rd_mem_res_gotten),
				.data_of_instant_rd_mem_res_gotten(data_of_instant_rd_mem_res_gotten),
				
				.has_buffered_wr_mem_req(has_buffered_wr_mem_req),
				.has_processing_perph_access_req(has_processing_perph_access_req),
				
				.fu_res_data(fu_res_data),
				.fu_res_tid(fu_res_tid),
				.fu_res_vld(fu_res_vld),
				
				.s_bru_o_tid(s_bru_o_to_iq_tid),
				.s_bru_o_valid(s_bru_o_to_iq_valid),
				
				.bru_nominal_res_vld(bru_nominal_res_vld),
				.bru_nominal_res_tid(bru_nominal_res_tid),
				.bru_nominal_res(bru_nominal_res),
				
				.s_wr_iq0_inst_id(s_wr_iq0_inst_id),
				.s_wr_iq0_fuid(s_wr_iq0_fuid),
				.s_wr_iq0_rob_entry_id(s_wr_iq0_rob_entry_id),
				.s_wr_iq0_age_tag(s_wr_iq0_age_tag),
				.s_wr_iq0_op1_lsn_fuid(s_wr_iq0_op1_lsn_fuid),
				.s_wr_iq0_op2_lsn_fuid(s_wr_iq0_op2_lsn_fuid),
				.s_wr_iq0_op1_lsn_inst_id(s_wr_iq0_op1_lsn_inst_id),
				.s_wr_iq0_op2_lsn_inst_id(s_wr_iq0_op2_lsn_inst_id),
				.s_wr_iq0_other_payload(s_wr_iq0_other_payload),
				.s_wr_iq0_op1_pre_fetched(s_wr_iq0_op1_pre_fetched),
				.s_wr_iq0_op2_pre_fetched(s_wr_iq0_op2_pre_fetched),
				.s_wr_iq0_op1_rdy(s_wr_iq0_op1_rdy),
				.s_wr_iq0_op2_rdy(s_wr_iq0_op2_rdy),
				.s_wr_iq0_valid(s_wr_iq0_valid),
				.s_wr_iq0_ready(s_wr_iq0_ready),
				
				.s_wr_iq1_inst_id(s_wr_iq1_inst_id),
				.s_wr_iq1_fuid(s_wr_iq1_fuid),
				.s_wr_iq1_rob_entry_id(s_wr_iq1_rob_entry_id),
				.s_wr_iq1_age_tag(s_wr_iq1_age_tag),
				.s_wr_iq1_op1_lsn_fuid(s_wr_iq1_op1_lsn_fuid),
				.s_wr_iq1_op2_lsn_fuid(s_wr_iq1_op2_lsn_fuid),
				.s_wr_iq1_op1_lsn_inst_id(s_wr_iq1_op1_lsn_inst_id),
				.s_wr_iq1_op2_lsn_inst_id(s_wr_iq1_op2_lsn_inst_id),
				.s_wr_iq1_other_payload(s_wr_iq1_other_payload),
				.s_wr_iq1_op1_pre_fetched(s_wr_iq1_op1_pre_fetched),
				.s_wr_iq1_op2_pre_fetched(s_wr_iq1_op2_pre_fetched),
				.s_wr_iq1_op1_rdy(s_wr_iq1_op1_rdy),
				.s_wr_iq1_op2_rdy(s_wr_iq1_op2_rdy),
				.s_wr_iq1_valid(s_wr_iq1_valid),
				.s_wr_iq1_ready(s_wr_iq1_ready),
				
				.brc_bdcst_luc_vld(brc_bdcst_luc_vld),
				.brc_bdcst_luc_tid(brc_bdcst_luc_tid),
				.brc_bdcst_luc_is_b_inst(brc_bdcst_luc_is_b_inst),
				.brc_bdcst_luc_is_jal_inst(brc_bdcst_luc_is_jal_inst),
				.brc_bdcst_luc_is_jalr_inst(brc_bdcst_luc_is_jalr_inst),
				.brc_bdcst_luc_bta(brc_bdcst_luc_bta),
				
				.saving_csr_rw_msg_upd_mask_v(saving_csr_rw_msg_upd_mask_v),
				.saving_csr_rw_msg_rob_entry_id(saving_csr_rw_msg_rob_entry_id),
				.saving_csr_rw_msg_vld(saving_csr_rw_msg_vld),
				
				.on_upd_rob_field_nxt_pc(on_upd_rob_field_nxt_pc),
				.inst_id_of_upd_rob_field_nxt_pc(inst_id_of_upd_rob_field_nxt_pc),
				.rob_field_nxt_pc(rob_field_nxt_pc),
				
				.m_alu_op_mode(m_alu_op_mode),
				.m_alu_op1(m_alu_op1),
				.m_alu_op2(m_alu_op2),
				.m_alu_tid(m_alu_tid),
				.m_alu_use_res(m_alu_use_res),
				.m_alu_valid(m_alu_valid),
				
				.m_csr_addr(m_csr_addr),
				.m_csr_tid(m_csr_tid),
				.m_csr_valid(m_csr_valid),
				
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
				.m_div_ready(m_div_ready),
				
				.m_lsu_ls_sel(m_lsu_ls_sel),
				.m_lsu_ls_type(m_lsu_ls_type),
				.m_lsu_rd_id_for_ld(m_lsu_rd_id_for_ld),
				.m_lsu_ls_addr(m_lsu_ls_addr),
				.m_lsu_ls_din(m_lsu_ls_din),
				.m_lsu_inst_id(m_lsu_inst_id),
				.m_lsu_valid(m_lsu_valid),
				.m_lsu_ready(m_lsu_ready),
				
				.m_bru_prdt_msg(m_bru_prdt_msg),
				.m_bru_inst_type(m_bru_inst_type),
				.m_bru_tid(m_bru_tid),
				.m_bru_prdt_suc(m_bru_prdt_suc),
				.m_bru_brc_cond_res(m_bru_brc_cond_res),
				.m_bru_valid(m_bru_valid),
				.m_bru_ready(m_bru_ready)
			);
		end
		else
		begin
			assign m_lsu_ls_addr = 32'dx;
			
			assign bru_nominal_res_vld = 1'b0;
			assign bru_nominal_res_tid = {IBUS_TID_WIDTH{1'bx}};
			assign bru_nominal_res = 32'dx;
			
			panda_risc_v_op_fetch_idec #(
				.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
				.LSN_FU_N((EN_OUT_OF_ORDER_ISSUE == "true") ? 6:5),
				.FU_ID_WIDTH(3),
				.FU_RES_WIDTH(32),
				.GEN_LS_ADDR_UNALIGNED_EXPT("false"),
				.OP_PRE_FTC("true"),
				.SIM_DELAY(SIM_DELAY)
			)op_fetch_idec_u(
				.aclk(aclk),
				.aresetn(aresetn),
				
				.sys_reset_req(sys_reset_req),
				.flush_req(global_flush_req),
				
				.s_if_res_data(m_regs_rd_data),
				.s_if_res_msg(m_regs_rd_msg),
				.s_if_res_id(m_regs_rd_id),
				.s_if_res_is_first_inst_after_rst(m_regs_rd_is_first_inst_after_rst),
				.s_if_res_op(m_regs_rd_op),
				.s_if_res_fuid(m_regs_rd_fuid),
				.s_if_res_valid(m_regs_rd_valid),
				.s_if_res_ready(m_regs_rd_ready),
				
				.m_op_ftc_id_res_data(m_op_ftc_id_res_data),
				.m_op_ftc_id_res_msg(m_op_ftc_id_res_msg),
				.m_op_ftc_id_res_dcd_res(m_op_ftc_id_res_dcd_res),
				.m_op_ftc_id_res_id(m_op_ftc_id_res_id),
				.m_op_ftc_id_res_is_first_inst_after_rst(m_op_ftc_id_res_is_first_inst_after_rst),
				.m_op_ftc_id_res_op1(m_op_ftc_id_res_op1),
				.m_op_ftc_id_res_op2(m_op_ftc_id_res_op2),
				.m_op_ftc_id_res_valid(m_op_ftc_id_res_valid),
				.m_op_ftc_id_res_ready(m_op_ftc_id_res_ready),
				
				.brc_bdcst_luc_vld(brc_bdcst_luc_vld),
				.brc_bdcst_luc_tid(brc_bdcst_luc_tid),
				.brc_bdcst_luc_is_b_inst(brc_bdcst_luc_is_b_inst),
				.brc_bdcst_luc_is_jal_inst(brc_bdcst_luc_is_jal_inst),
				.brc_bdcst_luc_is_jalr_inst(brc_bdcst_luc_is_jalr_inst),
				.brc_bdcst_luc_bta(brc_bdcst_luc_bta),
				
				.rob_entry_id_to_be_written(rob_entry_id_to_be_written),
				
				.rob_luc_bdcst_vld(rob_luc_bdcst_vld),
				.rob_luc_bdcst_tid(rob_luc_bdcst_tid),
				.rob_luc_bdcst_fuid(rob_luc_bdcst_fuid),
				.rob_luc_bdcst_rd_id(rob_luc_bdcst_rd_id),
				.rob_luc_bdcst_is_ls_inst(rob_luc_bdcst_is_ls_inst),
				.rob_luc_bdcst_is_csr_rw_inst(rob_luc_bdcst_is_csr_rw_inst),
				.rob_luc_bdcst_csr_rw_inst_msg(rob_luc_bdcst_csr_rw_inst_msg),
				.rob_luc_bdcst_err(rob_luc_bdcst_err),
				.rob_luc_bdcst_spec_inst_type(rob_luc_bdcst_spec_inst_type),
				.rob_luc_bdcst_is_b_inst(rob_luc_bdcst_is_b_inst),
				.rob_luc_bdcst_pc(rob_luc_bdcst_pc),
				.rob_luc_bdcst_nxt_pc(rob_luc_bdcst_nxt_pc),
				.rob_luc_bdcst_org_2bit_sat_cnt(rob_luc_bdcst_org_2bit_sat_cnt),
				.rob_luc_bdcst_bhr(rob_luc_bdcst_bhr),
				
				.saving_csr_rw_msg_upd_mask_v(saving_csr_rw_msg_upd_mask_v),
				.saving_csr_rw_msg_rob_entry_id(saving_csr_rw_msg_rob_entry_id),
				.saving_csr_rw_msg_vld(saving_csr_rw_msg_vld),
				
				.op1_ftc_rs1_id(),
				.op1_ftc_from_reg_file(1'b0),
				.op1_ftc_from_rob(1'b0),
				.op1_ftc_from_byp(1'b0),
				.op1_ftc_fuid(3'd0),
				.op1_ftc_tid({IBUS_TID_WIDTH{1'b0}}),
				.op1_ftc_rob_saved_data(32'd0),
				.op2_ftc_rs2_id(),
				.op2_ftc_from_reg_file(1'b0),
				.op2_ftc_from_rob(1'b0),
				.op2_ftc_from_byp(1'b0),
				.op2_ftc_fuid(3'd0),
				.op2_ftc_tid({IBUS_TID_WIDTH{1'b0}}),
				.op2_ftc_rob_saved_data(32'd0),
				
				.fu_res_bypass_en({((EN_OUT_OF_ORDER_ISSUE == "true") ? 6:5){1'b1}}),
				
				.fu_res_vld(fu_res_vld),
				.fu_res_tid(fu_res_tid),
				.fu_res_data(fu_res_data),
				
				.reg_file_raddr_p0(),
				.reg_file_dout_p0(32'h0000_0000),
				.reg_file_raddr_p1(),
				.reg_file_dout_p1(32'h0000_0000)
			);
			
			panda_risc_v_launch #(
				.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
				.SIM_DELAY(SIM_DELAY)
			)launch_u(
				.aclk(aclk),
				.aresetn(aresetn),
				
				.rob_full_n(rob_full_n),
				.rob_csr_rw_inst_allowed(rob_csr_rw_inst_allowed),
				
				.has_buffered_wr_mem_req(has_buffered_wr_mem_req),
				.has_processing_perph_access_req(has_processing_perph_access_req),
				
				.sys_reset_req(sys_reset_req),
				.flush_req(global_flush_req),
				
				.s_op_ftc_id_res_data(m_op_ftc_id_res_data),
				.s_op_ftc_id_res_msg(m_op_ftc_id_res_msg),
				.s_op_ftc_id_res_dcd_res(m_op_ftc_id_res_dcd_res),
				.s_op_ftc_id_res_id(m_op_ftc_id_res_id),
				.s_op_ftc_id_res_is_first_inst_after_rst(m_op_ftc_id_res_is_first_inst_after_rst),
				.s_op_ftc_id_res_op1(m_op_ftc_id_res_op1),
				.s_op_ftc_id_res_op2(m_op_ftc_id_res_op2),
				.s_op_ftc_id_res_valid(m_op_ftc_id_res_valid),
				.s_op_ftc_id_res_ready(m_op_ftc_id_res_ready),
				
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
			
			panda_risc_v_dispatch #(
				.IBUS_TID_WIDTH(IBUS_TID_WIDTH)
			)dispatch_u(
				.s_dsptc_data(m_luc_data),
				.s_dsptc_msg(m_luc_msg),
				.s_dsptc_dcd_res(m_luc_dcd_res),
				.s_dsptc_id(m_luc_id),
				.s_dsptc_is_first_inst_after_rst(m_luc_is_first_inst_after_rst),
				.s_dsptc_valid(m_luc_valid),
				.s_dsptc_ready(m_luc_ready),
				
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
		end
	endgenerate
	
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
		
		.ifu_flush_req(ifu_flush_req),
		.ifu_flush_addr(ifu_flush_addr),
		.ifu_flush_grant(ifu_flush_grant),
		
		.bru_flush_req(bru_flush_req),
		.bru_flush_addr(bru_flush_addr),
		.bru_flush_grant(bru_flush_grant),
		
		.cmt_flush_req(cmt_flush_req),
		.cmt_flush_addr(cmt_flush_addr),
		.cmt_flush_grant(cmt_flush_grant),
		
		.suppressing_ibus_access(suppressing_ibus_access),
		
		.ifu_exclusive_flush_req(ifu_exclusive_flush_req),
		
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
		.init_mtvec_base(INIT_MTVEC_BASE),
		.init_mcause_interrupt(INIT_MCAUSE_INTERRUPT),
		.init_mcause_exception_code(INIT_MCAUSE_EXCEPTION_CODE),
		.init_misa_mxl(INIT_MISA_MXL),
		.init_misa_extensions(INIT_MISA_EXTENSIONS),
		.init_mvendorid_bank(INIT_MVENDORID_BANK),
		.init_mvendorid_offset(INIT_MVENDORID_OFFSET),
		.init_marchid(INIT_MARCHID),
		.init_mimpid(INIT_MIMPID),
		.init_mhartid(INIT_MHARTID),
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
	// ALU给出的分支判定结果
	wire alu_brc_cond_res;
	// BRU输入
	wire[159:0] s_bru_i_prdt_msg; // 分支预测信息
	wire[15:0] s_bru_i_inst_type; // 打包的指令类型标志
	wire[IBUS_TID_WIDTH-1:0] s_bru_i_tid; // 指令ID
	wire s_bru_i_prdt_suc; // 是否预判分支预测成功
	wire s_bru_i_brc_cond_res; // 分支判定结果
	wire s_bru_i_valid;
	wire s_bru_i_ready;
	// BRU输出
	wire[IBUS_TID_WIDTH-1:0] m_bru_o_tid; // 指令ID
	wire[31:0] m_bru_o_nxt_pc; // 下一有效PC地址
	wire[1:0] m_bru_o_b_inst_res; // B指令执行结果
	wire m_bru_o_valid;
	
	assign s_bru_o_to_iq_tid = m_bru_o_tid;
	assign s_bru_o_to_iq_valid = m_bru_o_valid;
	
	assign rst_bru = cmt_flush_req;
	
	assign s_bru_i_prdt_msg = (EN_OUT_OF_ORDER_ISSUE == "true") ? m_bru_prdt_msg:m_bru_i_msg[162:3];
	assign s_bru_i_inst_type = (EN_OUT_OF_ORDER_ISSUE == "true") ? m_bru_inst_type:m_bru_i_dcd_res[15:0];
	assign s_bru_i_tid = (EN_OUT_OF_ORDER_ISSUE == "true") ? m_bru_tid:m_bru_i_id;
	assign s_bru_i_prdt_suc = (EN_OUT_OF_ORDER_ISSUE == "true") ? m_bru_prdt_suc:1'b0;
	assign s_bru_i_brc_cond_res = (EN_OUT_OF_ORDER_ISSUE == "true") ? m_bru_brc_cond_res:alu_brc_cond_res;
	assign s_bru_i_valid = (EN_OUT_OF_ORDER_ISSUE == "true") ? m_bru_valid:m_bru_i_valid;
	assign m_bru_ready = s_bru_i_ready;
	
	assign m_bru_i_ready = s_bru_i_ready;
	
	generate
		if(EN_OUT_OF_ORDER_ISSUE == "false")
		begin
			assign on_upd_rob_field_nxt_pc = m_bru_o_valid;
			assign inst_id_of_upd_rob_field_nxt_pc = m_bru_o_tid;
			assign rob_field_nxt_pc = m_bru_o_nxt_pc;
		end
	endgenerate
	
	panda_risc_v_bru #(
		.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
		.EN_IMDT_FLUSH((EN_OUT_OF_ORDER_ISSUE == "true") ? "false":"true"),
		.DEBUG_ROM_ADDR(DEBUG_ROM_ADDR),
		.BRU_RES_LATENCY(BRU_RES_LATENCY),
		.SIM_DELAY(SIM_DELAY)
	)bru_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.in_dbg_mode(in_dbg_mode),
		
		.rst_bru(rst_bru),
		.jal_inst_n_acpt(),
		.jal_prdt_success_inst_n(),
		.jalr_inst_n_acpt(),
		.jalr_prdt_success_inst_n(),
		.b_inst_n_acpt(),
		.b_prdt_success_inst_n(),
		.b_prdt_not_taken_but_actually_taken(),
		.b_prdt_taken_but_actually_not_taken(),
		.b_actually_taken(),
		.b_actually_not_taken(),
		.common_inst_n_acpt(),
		.common_prdt_success_inst_n(),
		.brc_inst_n_acpt(),
		.brc_inst_with_btb_hit_n(),
		
		.bru_flush_req(bru_flush_req),
		.bru_flush_addr(bru_flush_addr),
		.bru_flush_grant(bru_flush_grant),
		
		.s_bru_i_prdt_msg(s_bru_i_prdt_msg),
		.s_bru_i_inst_type(s_bru_i_inst_type),
		.s_bru_i_tid(s_bru_i_tid),
		.s_bru_i_prdt_suc(s_bru_i_prdt_suc),
		.s_bru_i_brc_cond_res(s_bru_i_brc_cond_res),
		.s_bru_i_valid(s_bru_i_valid),
		.s_bru_i_ready(s_bru_i_ready),
		
		.m_bru_o_tid(m_bru_o_tid),
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
	wire[31:0] s_lsu_ls_addr; // 访存地址
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
	// CPU核内存储器AXI主机
	// [AR通道]
	wire[31:0] m_axi_inner_mem_araddr;
	wire[1:0] m_axi_inner_mem_arburst;
	wire[7:0] m_axi_inner_mem_arlen;
	wire[2:0] m_axi_inner_mem_arsize;
	wire m_axi_inner_mem_arvalid;
	wire m_axi_inner_mem_arready;
	// [R通道]
	wire[AXI_MEM_DATA_WIDTH-1:0] m_axi_inner_mem_rdata;
	wire[1:0] m_axi_inner_mem_rresp;
	wire m_axi_inner_mem_rlast;
	wire m_axi_inner_mem_rvalid;
	wire m_axi_inner_mem_rready;
	// [AW通道]
	wire[31:0] m_axi_inner_mem_awaddr;
	wire[1:0] m_axi_inner_mem_awburst;
	wire[7:0] m_axi_inner_mem_awlen;
	wire[2:0] m_axi_inner_mem_awsize;
	wire m_axi_inner_mem_awvalid;
	wire m_axi_inner_mem_awready;
	// [B通道]
	wire[1:0] m_axi_inner_mem_bresp;
	wire m_axi_inner_mem_bvalid;
	wire m_axi_inner_mem_bready;
	// [W通道]
	wire[AXI_MEM_DATA_WIDTH-1:0] m_axi_inner_mem_wdata;
	wire[AXI_MEM_DATA_WIDTH/8-1:0] m_axi_inner_mem_wstrb;
	wire m_axi_inner_mem_wlast;
	wire m_axi_inner_mem_wvalid;
	wire m_axi_inner_mem_wready;
	// 写存储器缓存区控制
	wire wr_mem_permitted_flag; // 写存储器许可标志
	wire[IBUS_TID_WIDTH-1:0] init_mem_bus_tr_store_inst_tid; // 待发起存储器总线事务的存储指令ID
	wire clr_wr_mem_buf; // 清空缓存区指示
	// 外设访问控制
	wire perph_access_permitted_flag; // 外设访问许可标志
	wire[IBUS_TID_WIDTH-1:0] init_perph_bus_tr_ls_inst_tid; // 待发起外设总线事务的访存指令ID
	wire cancel_subseq_perph_access; // 取消后续外设访问指示
	
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
	assign s_lsu_ls_addr = m_lsu_ls_addr;
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
		.EN_OUT_OF_ORDER_ISSUE(EN_OUT_OF_ORDER_ISSUE),
		.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
		.AXI_MEM_DATA_WIDTH(AXI_MEM_DATA_WIDTH),
		.MEM_ACCESS_TIMEOUT_TH(MEM_ACCESS_TIMEOUT_TH),
		.PERPH_ACCESS_TIMEOUT_TH(PERPH_ACCESS_TIMEOUT_TH),
		.LSU_REQ_BUF_ENTRY_N(LSU_REQ_BUF_ENTRY_N),
		.RD_MEM_BUF_ENTRY_N(RD_MEM_BUF_ENTRY_N),
		.WR_MEM_BUF_ENTRY_N(WR_MEM_BUF_ENTRY_N),
		.PERPH_ADDR_REGION_0_BASE(PERPH_ADDR_REGION_0_BASE),
		.PERPH_ADDR_REGION_0_LEN(PERPH_ADDR_REGION_0_LEN),
		.PERPH_ADDR_REGION_1_BASE(PERPH_ADDR_REGION_1_BASE),
		.PERPH_ADDR_REGION_1_LEN(PERPH_ADDR_REGION_1_LEN),
		.EN_SGN_PERIOD_MUL(EN_SGN_PERIOD_MUL),
		.EN_LOW_LATENCY_PERPH_ACCESS(EN_LOW_LATENCY_PERPH_ACCESS),
		.EN_LOW_LATENCY_RD_MEM_ACCESS_IN_LSU(EN_LOW_LATENCY_RD_MEM_ACCESS_IN_LSU),
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
		.s_lsu_ls_addr(s_lsu_ls_addr),
		.s_lsu_ls_din(s_lsu_ls_din),
		.s_lsu_inst_id(s_lsu_inst_id),
		.s_lsu_valid(s_lsu_valid),
		.s_lsu_ready(s_lsu_ready),
		
		.m_lsu_ls_sel(),
		.m_lsu_rd_id_for_ld(),
		.m_lsu_dout_ls_addr(),
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
		
		.bru_nominal_res_vld(bru_nominal_res_vld),
		.bru_nominal_res_tid(bru_nominal_res_tid),
		.bru_nominal_res(bru_nominal_res),
		
		.fu_res_vld(fu_res_vld),
		.fu_res_tid(fu_res_tid),
		.fu_res_data(fu_res_data),
		.fu_res_err(fu_res_err),
		
		.m_axi_mem_araddr(m_axi_inner_mem_araddr),
		.m_axi_mem_arburst(m_axi_inner_mem_arburst),
		.m_axi_mem_arlen(m_axi_inner_mem_arlen),
		.m_axi_mem_arsize(m_axi_inner_mem_arsize),
		.m_axi_mem_arvalid(m_axi_inner_mem_arvalid),
		.m_axi_mem_arready(m_axi_inner_mem_arready),
		.m_axi_mem_rdata(m_axi_inner_mem_rdata),
		.m_axi_mem_rresp(m_axi_inner_mem_rresp),
		.m_axi_mem_rlast(m_axi_inner_mem_rlast),
		.m_axi_mem_rvalid(m_axi_inner_mem_rvalid),
		.m_axi_mem_rready(m_axi_inner_mem_rready),
		.m_axi_mem_awaddr(m_axi_inner_mem_awaddr),
		.m_axi_mem_awburst(m_axi_inner_mem_awburst),
		.m_axi_mem_awlen(m_axi_inner_mem_awlen),
		.m_axi_mem_awsize(m_axi_inner_mem_awsize),
		.m_axi_mem_awvalid(m_axi_inner_mem_awvalid),
		.m_axi_mem_awready(m_axi_inner_mem_awready),
		.m_axi_mem_bresp(m_axi_inner_mem_bresp),
		.m_axi_mem_bvalid(m_axi_inner_mem_bvalid),
		.m_axi_mem_bready(m_axi_inner_mem_bready),
		.m_axi_mem_wdata(m_axi_inner_mem_wdata),
		.m_axi_mem_wstrb(m_axi_inner_mem_wstrb),
		.m_axi_mem_wlast(m_axi_inner_mem_wlast),
		.m_axi_mem_wvalid(m_axi_inner_mem_wvalid),
		.m_axi_mem_wready(m_axi_inner_mem_wready),
		
		.m_axi_perph_araddr(m_axi_perph_araddr),
		.m_axi_perph_arburst(m_axi_perph_arburst),
		.m_axi_perph_arlen(m_axi_perph_arlen),
		.m_axi_perph_arsize(m_axi_perph_arsize),
		.m_axi_perph_arvalid(m_axi_perph_arvalid),
		.m_axi_perph_arready(m_axi_perph_arready),
		.m_axi_perph_rdata(m_axi_perph_rdata),
		.m_axi_perph_rresp(m_axi_perph_rresp),
		.m_axi_perph_rlast(m_axi_perph_rlast),
		.m_axi_perph_rvalid(m_axi_perph_rvalid),
		.m_axi_perph_rready(m_axi_perph_rready),
		.m_axi_perph_awaddr(m_axi_perph_awaddr),
		.m_axi_perph_awburst(m_axi_perph_awburst),
		.m_axi_perph_awlen(m_axi_perph_awlen),
		.m_axi_perph_awsize(m_axi_perph_awsize),
		.m_axi_perph_awvalid(m_axi_perph_awvalid),
		.m_axi_perph_awready(m_axi_perph_awready),
		.m_axi_perph_bresp(m_axi_perph_bresp),
		.m_axi_perph_bvalid(m_axi_perph_bvalid),
		.m_axi_perph_bready(m_axi_perph_bready),
		.m_axi_perph_wdata(m_axi_perph_wdata),
		.m_axi_perph_wstrb(m_axi_perph_wstrb),
		.m_axi_perph_wlast(m_axi_perph_wlast),
		.m_axi_perph_wvalid(m_axi_perph_wvalid),
		.m_axi_perph_wready(m_axi_perph_wready),
		
		.wr_mem_permitted_flag(wr_mem_permitted_flag),
		.init_mem_bus_tr_store_inst_tid(init_mem_bus_tr_store_inst_tid),
		.clr_wr_mem_buf(clr_wr_mem_buf),
		
		.perph_access_permitted_flag(perph_access_permitted_flag),
		.init_perph_bus_tr_ls_inst_tid(init_perph_bus_tr_ls_inst_tid),
		.cancel_subseq_perph_access(cancel_subseq_perph_access),
		
		.on_get_instant_rd_mem_res(on_get_instant_rd_mem_res),
		.inst_id_of_instant_rd_mem_res_gotten(inst_id_of_instant_rd_mem_res_gotten),
		.data_of_instant_rd_mem_res_gotten(data_of_instant_rd_mem_res_gotten),
		
		.has_buffered_wr_mem_req(has_buffered_wr_mem_req),
		.has_processing_perph_access_req(has_processing_perph_access_req),
		.rd_mem_timeout(rd_mem_timeout),
		.wr_mem_timeout(wr_mem_timeout),
		.perph_access_timeout(perph_access_timeout)
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
	wire rob_prep_rtr_entry_cancel; // 取消标志
	wire[31:0] rob_prep_rtr_entry_fu_res; // 保存的执行结果
	wire[31:0] rob_prep_rtr_entry_pc; // 指令对应的PC
	wire[31:0] rob_prep_rtr_entry_nxt_pc; // 指令对应的下一有效PC
	wire[1:0] rob_prep_rtr_entry_b_inst_res; // B指令执行结果
	wire[1:0] rob_prep_rtr_entry_org_2bit_sat_cnt; // 原来的2bit饱和计数器
	wire[15:0] rob_prep_rtr_entry_bhr; // BHR
	wire rob_prep_rtr_is_b_inst; // 是否B指令
	wire[11:0] rob_prep_rtr_entry_csr_rw_waddr; // CSR写地址
	wire[1:0] rob_prep_rtr_entry_csr_rw_upd_type; // CSR更新类型
	wire[31:0] rob_prep_rtr_entry_csr_rw_upd_mask_v; // CSR更新掩码或更新值
	// BRU结果
	wire[IBUS_TID_WIDTH-1:0] s_bru_o_to_rob_tid; // 指令ID
	wire[1:0] s_bru_o_to_rob_b_inst_res; // B指令执行结果
	wire s_bru_o_to_rob_valid;
	// 退休阶段ROB记录广播
	wire rob_rtr_bdcst_vld; // 广播有效
	wire rob_rtr_bdcst_excpt_proc_grant; // 异常处理许可
	
	assign s_bru_o_to_rob_tid = m_bru_o_tid;
	assign s_bru_o_to_rob_b_inst_res = m_bru_o_b_inst_res;
	assign s_bru_o_to_rob_valid = m_bru_o_valid;
	
	panda_risc_v_rob #(
		.EN_OUT_OF_ORDER_ISSUE(EN_OUT_OF_ORDER_ISSUE),
		.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
		.FU_ID_WIDTH(3),
		.ROB_ENTRY_N(ROB_ENTRY_N),
		.CSR_RW_RCD_SLOTS_N(CSR_RW_RCD_SLOTS_N),
		.FU_LSN_LATENCY((EN_OUT_OF_ORDER_ISSUE == "true") ? 1:0),
		.LSN_FU_N((EN_OUT_OF_ORDER_ISSUE == "true") ? 6:5),
		.FU_RES_WIDTH(32),
		.FU_ERR_WIDTH(3),
		.LSU_FU_ID(LSU_FU_ID),
		.AUTO_CANCEL_SYNC_ERR_ENTRY(AUTO_CANCEL_SYNC_ERR_ENTRY),
		.SIM_DELAY(SIM_DELAY)
	)rob_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.rob_clr(rob_clr),
		.rob_full_n(rob_full_n),
		.rob_empty_n(),
		.rob_csr_rw_inst_allowed(rob_csr_rw_inst_allowed),
		.rob_has_ls_inst(),
		.rob_entry_id_to_be_written(rob_entry_id_to_be_written),
		.rob_entry_age_tbit_to_be_written(rob_entry_age_tbit_to_be_written),
		
		.rob_sng_cancel_vld(1'b0),
		.rob_sng_cancel_tid({IBUS_TID_WIDTH{1'b0}}),
		.rob_yngr_cancel_vld(1'b0),
		.rob_yngr_cancel_bchmk_wptr(6'b000000),
		
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
		.rob_prep_rtr_entry_spec_inst_type(rob_prep_rtr_entry_spec_inst_type),
		.rob_prep_rtr_entry_cancel(rob_prep_rtr_entry_cancel),
		.rob_prep_rtr_entry_fu_res(rob_prep_rtr_entry_fu_res),
		.rob_prep_rtr_entry_pc(rob_prep_rtr_entry_pc),
		.rob_prep_rtr_entry_nxt_pc(rob_prep_rtr_entry_nxt_pc),
		.rob_prep_rtr_entry_b_inst_res(rob_prep_rtr_entry_b_inst_res),
		.rob_prep_rtr_entry_org_2bit_sat_cnt(rob_prep_rtr_entry_org_2bit_sat_cnt),
		.rob_prep_rtr_entry_bhr(rob_prep_rtr_entry_bhr),
		.rob_prep_rtr_is_b_inst(rob_prep_rtr_is_b_inst),
		.rob_prep_rtr_entry_csr_rw_waddr(rob_prep_rtr_entry_csr_rw_waddr),
		.rob_prep_rtr_entry_csr_rw_upd_type(rob_prep_rtr_entry_csr_rw_upd_type),
		.rob_prep_rtr_entry_csr_rw_upd_mask_v(rob_prep_rtr_entry_csr_rw_upd_mask_v),
		
		.fu_res_vld(fu_res_vld),
		.fu_res_tid(fu_res_tid),
		.fu_res_data(fu_res_data),
		.fu_res_err(fu_res_err),
		
		.s_bru_o_tid(s_bru_o_to_rob_tid),
		.s_bru_o_b_inst_res(s_bru_o_to_rob_b_inst_res),
		.s_bru_o_valid(s_bru_o_to_rob_valid),
		
		.saving_csr_rw_msg_upd_mask_v(saving_csr_rw_msg_upd_mask_v),
		.saving_csr_rw_msg_rob_entry_id(saving_csr_rw_msg_rob_entry_id),
		.saving_csr_rw_msg_vld(saving_csr_rw_msg_vld),
		
		.on_upd_rob_field_nxt_pc(on_upd_rob_field_nxt_pc),
		.inst_id_of_upd_rob_field_nxt_pc(inst_id_of_upd_rob_field_nxt_pc),
		.rob_field_nxt_pc(rob_field_nxt_pc),
		
		.wr_mem_permitted_flag(wr_mem_permitted_flag),
		.init_mem_bus_tr_store_inst_tid(init_mem_bus_tr_store_inst_tid),
		.perph_access_permitted_flag(perph_access_permitted_flag),
		.init_perph_bus_tr_ls_inst_tid(init_perph_bus_tr_ls_inst_tid),
		
		.rob_luc_bdcst_vld(rob_luc_bdcst_vld),
		.rob_luc_bdcst_tid(rob_luc_bdcst_tid),
		.rob_luc_bdcst_fuid(rob_luc_bdcst_fuid),
		.rob_luc_bdcst_rd_id(rob_luc_bdcst_rd_id),
		.rob_luc_bdcst_is_ls_inst(rob_luc_bdcst_is_ls_inst),
		.rob_luc_bdcst_is_csr_rw_inst(rob_luc_bdcst_is_csr_rw_inst),
		.rob_luc_bdcst_csr_rw_inst_msg(rob_luc_bdcst_csr_rw_inst_msg),
		.rob_luc_bdcst_err(rob_luc_bdcst_err),
		.rob_luc_bdcst_spec_inst_type(rob_luc_bdcst_spec_inst_type),
		.rob_luc_bdcst_is_b_inst(rob_luc_bdcst_is_b_inst),
		.rob_luc_bdcst_pc(rob_luc_bdcst_pc),
		.rob_luc_bdcst_nxt_pc(rob_luc_bdcst_nxt_pc),
		.rob_luc_bdcst_org_2bit_sat_cnt(rob_luc_bdcst_org_2bit_sat_cnt),
		.rob_luc_bdcst_bhr(rob_luc_bdcst_bhr),
		
		.rob_rtr_bdcst_vld(rob_rtr_bdcst_vld)
	);
	
	/** 交付单元 **/
	panda_risc_v_commit #(
		.DEBUG_ROM_ADDR(DEBUG_ROM_ADDR),
		.DEBUG_SUPPORTED(DEBUG_SUPPORTED),
		.FU_RES_WIDTH(32),
		.GHR_WIDTH(GHR_WIDTH),
		.BHR_WIDTH(BHR_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)commit_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.cmt_flush_req(cmt_flush_req),
		.cmt_flush_addr(cmt_flush_addr),
		.cmt_flush_grant(cmt_flush_grant),
		
		.rob_clr(rob_clr),
		.lsu_clr_wr_mem_buf(clr_wr_mem_buf),
		.cancel_lsu_subseq_perph_access(cancel_subseq_perph_access),
		
		.clr_iq0(clr_iq0),
		.clr_iq1(clr_iq1),
		
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
		.rob_prep_rtr_entry_org_2bit_sat_cnt(rob_prep_rtr_entry_org_2bit_sat_cnt),
		.rob_prep_rtr_entry_bhr(rob_prep_rtr_entry_bhr),
		.rob_prep_rtr_is_b_inst(rob_prep_rtr_is_b_inst),
		
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
		.glb_brc_prdt_upd_i_bhr(glb_brc_prdt_upd_i_bhr),
		.glb_brc_prdt_upd_i_2bit_sat_cnt(glb_brc_prdt_upd_i_2bit_sat_cnt),
		.glb_brc_prdt_upd_i_brc_taken(glb_brc_prdt_upd_i_brc_taken),
		.glb_brc_prdt_retired_ghr_o(glb_brc_prdt_retired_ghr_o)
	);
	
	/** 写回单元 **/
	panda_risc_v_wbck #(
		.FU_RES_WIDTH(32)
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
	
	/** 总线互联单元 **/
	// (指令总线)存储器AXI主机AR通道寄存器片
	// [寄存器片AXIS从机]
	wire[31:0] m_axi_imem_reg_i_araddr;
	wire[1:0] m_axi_imem_reg_i_arburst;
	wire[7:0] m_axi_imem_reg_i_arlen;
	wire[2:0] m_axi_imem_reg_i_arsize;
	wire m_axi_imem_reg_i_arvalid;
	wire m_axi_imem_reg_i_arready;
	// [寄存器片AXIS主机]
	wire[31:0] m_axi_imem_reg_o_araddr;
	wire[1:0] m_axi_imem_reg_o_arburst;
	wire[7:0] m_axi_imem_reg_o_arlen;
	wire[2:0] m_axi_imem_reg_o_arsize;
	wire m_axi_imem_reg_o_arvalid;
	wire m_axi_imem_reg_o_arready;
	
	assign m_axi_imem_araddr = m_axi_imem_reg_o_araddr;
	assign m_axi_imem_arburst = m_axi_imem_reg_o_arburst;
	assign m_axi_imem_arlen = m_axi_imem_reg_o_arlen;
	assign m_axi_imem_arsize = m_axi_imem_reg_o_arsize;
	assign m_axi_imem_arvalid = m_axi_imem_reg_o_arvalid;
	assign m_axi_imem_reg_o_arready = m_axi_imem_arready;
	
	panda_risc_v_biu #(
		.AXI_MEM_DATA_WIDTH(AXI_MEM_DATA_WIDTH),
		.IMEM_BASEADDR(IMEM_BASEADDR),
		.IMEM_ADDR_RANGE(IMEM_ADDR_RANGE),
		.DM_REGS_BASEADDR(DM_REGS_BASEADDR),
		.DM_REGS_ADDR_RANGE(DM_REGS_ADDR_RANGE),
		.DEBUG_SUPPORTED(DEBUG_SUPPORTED),
		.EN_LOW_LATENCY_DMEM_RD(EN_BIU_LOW_LATENCY_DMEM_RD),
		.SIM_DELAY(SIM_DELAY)
	)biu_u(
		.aclk(aclk),
		.aresetn(aresetn),
		
		.s_icb_cmd_inst_addr(m_icb_inner_imem_cmd_inst_addr),
		.s_icb_cmd_inst_read(m_icb_inner_imem_cmd_inst_read),
		.s_icb_cmd_inst_wdata(m_icb_inner_imem_cmd_inst_wdata),
		.s_icb_cmd_inst_wmask(m_icb_inner_imem_cmd_inst_wmask),
		.s_icb_cmd_inst_valid(m_icb_inner_imem_cmd_inst_valid),
		.s_icb_cmd_inst_ready(m_icb_inner_imem_cmd_inst_ready),
		.s_icb_rsp_inst_rdata(m_icb_inner_imem_rsp_inst_rdata),
		.s_icb_rsp_inst_err(m_icb_inner_imem_rsp_inst_err),
		.s_icb_rsp_inst_valid(m_icb_inner_imem_rsp_inst_valid),
		.s_icb_rsp_inst_ready(m_icb_inner_imem_rsp_inst_ready),
		
		.s_axi_dmem_araddr(m_axi_inner_mem_araddr),
		.s_axi_dmem_arburst(m_axi_inner_mem_arburst),
		.s_axi_dmem_arlen(m_axi_inner_mem_arlen),
		.s_axi_dmem_arsize(m_axi_inner_mem_arsize),
		.s_axi_dmem_arvalid(m_axi_inner_mem_arvalid),
		.s_axi_dmem_arready(m_axi_inner_mem_arready),
		.s_axi_dmem_rdata(m_axi_inner_mem_rdata),
		.s_axi_dmem_rresp(m_axi_inner_mem_rresp),
		.s_axi_dmem_rlast(m_axi_inner_mem_rlast),
		.s_axi_dmem_rvalid(m_axi_inner_mem_rvalid),
		.s_axi_dmem_rready(m_axi_inner_mem_rready),
		.s_axi_dmem_awaddr(m_axi_inner_mem_awaddr),
		.s_axi_dmem_awburst(m_axi_inner_mem_awburst),
		.s_axi_dmem_awlen(m_axi_inner_mem_awlen),
		.s_axi_dmem_awsize(m_axi_inner_mem_awsize),
		.s_axi_dmem_awvalid(m_axi_inner_mem_awvalid),
		.s_axi_dmem_awready(m_axi_inner_mem_awready),
		.s_axi_dmem_bresp(m_axi_inner_mem_bresp),
		.s_axi_dmem_bvalid(m_axi_inner_mem_bvalid),
		.s_axi_dmem_bready(m_axi_inner_mem_bready),
		.s_axi_dmem_wdata(m_axi_inner_mem_wdata),
		.s_axi_dmem_wstrb(m_axi_inner_mem_wstrb),
		.s_axi_dmem_wlast(m_axi_inner_mem_wlast),
		.s_axi_dmem_wvalid(m_axi_inner_mem_wvalid),
		.s_axi_dmem_wready(m_axi_inner_mem_wready),
		
		.m_axi_imem_araddr(m_axi_imem_reg_i_araddr),
		.m_axi_imem_arburst(m_axi_imem_reg_i_arburst),
		.m_axi_imem_arlen(m_axi_imem_reg_i_arlen),
		.m_axi_imem_arsize(m_axi_imem_reg_i_arsize),
		.m_axi_imem_arvalid(m_axi_imem_reg_i_arvalid),
		.m_axi_imem_arready(m_axi_imem_reg_i_arready),
		.m_axi_imem_rdata(m_axi_imem_rdata),
		.m_axi_imem_rresp(m_axi_imem_rresp),
		.m_axi_imem_rlast(m_axi_imem_rlast),
		.m_axi_imem_rvalid(m_axi_imem_rvalid),
		.m_axi_imem_rready(m_axi_imem_rready),
		.m_axi_imem_awaddr(m_axi_imem_awaddr),
		.m_axi_imem_awburst(m_axi_imem_awburst),
		.m_axi_imem_awlen(m_axi_imem_awlen),
		.m_axi_imem_awsize(m_axi_imem_awsize),
		.m_axi_imem_awvalid(m_axi_imem_awvalid),
		.m_axi_imem_awready(m_axi_imem_awready),
		.m_axi_imem_bresp(m_axi_imem_bresp),
		.m_axi_imem_bvalid(m_axi_imem_bvalid),
		.m_axi_imem_bready(m_axi_imem_bready),
		.m_axi_imem_wdata(m_axi_imem_wdata),
		.m_axi_imem_wstrb(m_axi_imem_wstrb),
		.m_axi_imem_wlast(m_axi_imem_wlast),
		.m_axi_imem_wvalid(m_axi_imem_wvalid),
		.m_axi_imem_wready(m_axi_imem_wready),
		
		.m_axi_dmem_araddr(m_axi_dmem_araddr),
		.m_axi_dmem_arburst(m_axi_dmem_arburst),
		.m_axi_dmem_arlen(m_axi_dmem_arlen),
		.m_axi_dmem_arsize(m_axi_dmem_arsize),
		.m_axi_dmem_arvalid(m_axi_dmem_arvalid),
		.m_axi_dmem_arready(m_axi_dmem_arready),
		.m_axi_dmem_rdata(m_axi_dmem_rdata),
		.m_axi_dmem_rresp(m_axi_dmem_rresp),
		.m_axi_dmem_rlast(m_axi_dmem_rlast),
		.m_axi_dmem_rvalid(m_axi_dmem_rvalid),
		.m_axi_dmem_rready(m_axi_dmem_rready),
		.m_axi_dmem_awaddr(m_axi_dmem_awaddr),
		.m_axi_dmem_awburst(m_axi_dmem_awburst),
		.m_axi_dmem_awlen(m_axi_dmem_awlen),
		.m_axi_dmem_awsize(m_axi_dmem_awsize),
		.m_axi_dmem_awvalid(m_axi_dmem_awvalid),
		.m_axi_dmem_awready(m_axi_dmem_awready),
		.m_axi_dmem_bresp(m_axi_dmem_bresp),
		.m_axi_dmem_bvalid(m_axi_dmem_bvalid),
		.m_axi_dmem_bready(m_axi_dmem_bready),
		.m_axi_dmem_wdata(m_axi_dmem_wdata),
		.m_axi_dmem_wstrb(m_axi_dmem_wstrb),
		.m_axi_dmem_wlast(m_axi_dmem_wlast),
		.m_axi_dmem_wvalid(m_axi_dmem_wvalid),
		.m_axi_dmem_wready(m_axi_dmem_wready)
	);
	
	axis_reg_slice #(
		.data_width(40),
		.user_width(5),
		.forward_registered(EN_M_AXI_IMEM_AR_REG_SLICE),
		.back_registered("false"),
		.en_ready("true"),
		.en_clk_en("false"),
		.simulation_delay(SIM_DELAY)
	)m_axi_imem_ar_reg_slice_u(
		.clk(aclk),
		.rst_n(aresetn),
		.clken(1'b1),
		
		.s_axis_data({m_axi_imem_reg_i_arlen, m_axi_imem_reg_i_araddr}),
		.s_axis_keep(5'bxxxxx),
		.s_axis_user({m_axi_imem_reg_i_arsize, m_axi_imem_reg_i_arburst}),
		.s_axis_last(1'bx),
		.s_axis_valid(m_axi_imem_reg_i_arvalid),
		.s_axis_ready(m_axi_imem_reg_i_arready),
		
		.m_axis_data({m_axi_imem_reg_o_arlen, m_axi_imem_reg_o_araddr}),
		.m_axis_keep(),
		.m_axis_user({m_axi_imem_reg_o_arsize, m_axi_imem_reg_o_arburst}),
		.m_axis_last(),
		.m_axis_valid(m_axi_imem_reg_o_arvalid),
		.m_axis_ready(m_axi_imem_reg_o_arready)
	);
	
endmodule
