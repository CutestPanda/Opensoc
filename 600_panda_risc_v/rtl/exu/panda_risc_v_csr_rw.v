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
本模块: CSR原子读写单元

描述:
实现CSR原子读写
部分CSR在进入或退出中断/异常处理时更新
可选Debug相关CSR

注意：
未考虑WIRI/WPRI/WLRL/WARL特性

协议:
无

作者: 陈家耀
日期: 2025/02/13
********************************************************************/


module panda_risc_v_csr_rw #(
	parameter en_expt_vec_vectored = "false", // 是否使能异常处理的向量链接模式
	parameter en_performance_monitor = "false", // 是否使能性能监测相关的CSR
	parameter init_mtvec_base = 30'd0, // mtvec状态寄存器BASE域复位值
	parameter init_mcause_interrupt = 1'b0, // mcause状态寄存器Interrupt域复位值
	parameter init_mcause_exception_code = 31'd16, // mcause状态寄存器Exception Code域复位值
	parameter init_misa_mxl = 2'b01, // misa状态寄存器MXL域复位值
	parameter init_misa_extensions = 26'b00_0000_0000_0001_0001_0000_0000, // misa状态寄存器Extensions域复位值
	parameter init_mvendorid_bank = 25'h0_00_00_00, // mvendorid状态寄存器Bank域复位值
	parameter init_mvendorid_offset = 7'h00, // mvendorid状态寄存器Offset域复位值
	parameter init_marchid = 32'h00_00_00_00, // marchid状态寄存器复位值
	parameter init_mimpid = 32'h31_2E_30_30, // mimpid状态寄存器复位值
	parameter init_mhartid = 32'h00_00_00_00, // mhartid状态寄存器复位值
	parameter debug_supported = "true", // 是否需要支持Debug
	parameter integer dscratch_n = 1, // dscratch寄存器的个数(1 | 2)
    parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// CSR原子读写
	input wire[11:0] csr_atom_rw_addr, // CSR地址
	input wire[1:0] csr_atom_rw_upd_type, // CSR更新类型
	input wire[31:0] csr_atom_rw_upd_mask_v, // CSR更新掩码或更新值
	input wire csr_atom_rw_valid, // 执行原子读写(指示)
	output wire[31:0] csr_atom_rw_dout, // CSR原值
	
	// 进入中断/异常处理
	input wire itr_expt_enter, // 进入中断/异常(指示)
	input wire itr_expt_is_intr, // 是否中断
	input wire[7:0] itr_expt_cause, // 中断/异常原因
	output wire[31:0] itr_expt_vec_baseaddr, // 中断/异常向量表基地址
	input wire[31:0] itr_expt_ret_addr, // 中断/异常返回地址
	input wire[31:0] itr_expt_val, // 中断/异常值(附加信息)
	
	// 退出中断/异常处理
	input wire itr_expt_ret, // 退出中断/异常(指示)
	output wire[31:0] mepc_ret_addr, // mepc状态寄存器定义的中断/异常返回地址
	
	// 进入调试模式
	input wire dbg_mode_enter, // 进入调试模式(指示)
	input wire[2:0] dbg_mode_cause, // 进入调试模式的原因
	input wire[31:0] dbg_mode_ret_addr, // 调试模式返回地址
	
	// 退出调试模式
	input wire dbg_mode_ret, // 退出调试模式(指示)
	output wire[31:0] dpc_ret_addr, // dpc状态寄存器定义的调试模式返回地址
	
	// 调试状态
	output wire dcsr_ebreakm_v, // dcsr状态寄存器EBREAKM域
	output wire dcsr_step_v, // dcsr状态寄存器STEP域
	input wire in_dbg_mode, // 当前处于调试模式(标志)
	
	// 性能监测
	input wire inst_retire_cnt_en, // 退休指令计数器的计数使能
	
	// 中断请求
	// 注意: 中断请求保持有效直到中断清零!
	input wire sw_itr_req, // 软件中断请求
	input wire tmr_itr_req, // 计时器中断请求
	input wire ext_itr_req, // 外部中断请求
	
	// 中断使能
	output wire mstatus_mie_v, // mstatus状态寄存器MIE域
	output wire mie_msie_v, // mie状态寄存器MSIE域
	output wire mie_mtie_v, // mie状态寄存器MTIE域
	output wire mie_meie_v // mie状态寄存器MEIE域
);
	
    /** 常量 **/
	// CSR更新类型
	localparam CSR_UPD_TYPE_LOAD = 2'b00;
	localparam CSR_UPD_TYPE_SET = 2'b01;
	localparam CSR_UPD_TYPE_CLR = 2'b10;
	// CSR地址
	localparam CSR_MSTATUS_ADDR = 12'h300;
	localparam CSR_MISA_ADDR = 12'h301;
	localparam CSR_MIE_ADDR = 12'h304;
	localparam CSR_MTVEC_ADDR = 12'h305;
	localparam CSR_MSCRATCH_ADDR = 12'h340;
	localparam CSR_MEPC_ADDR = 12'h341;
	localparam CSR_MCAUSE_ADDR = 12'h342;
	localparam CSR_MTVAL_ADDR = 12'h343;
	localparam CSR_MIP_ADDR = 12'h344;
	localparam CSR_DCSR_ADDR = 12'h7B0;
	localparam CSR_DPC_ADDR = 12'h7B1;
	localparam CSR_DSCRATCH0_ADDR = 12'h7B2;
	localparam CSR_DSCRATCH1_ADDR = 12'h7B3;
	localparam CSR_MCYCLE_ADDR = 12'hB00;
	localparam CSR_MINSTRET_ADDR = 12'hB02;
	localparam CSR_MCYCLEH_ADDR = 12'hB80;
	localparam CSR_MINSTRETH_ADDR = 12'hB82;
	localparam CSR_MVENDORID_ADDR = 12'hF11;
	localparam CSR_MARCHID_ADDR = 12'hF12;
	localparam CSR_MIMPID_ADDR = 12'hF13;
	localparam CSR_MHARTID_ADDR = 12'hF14;
	// 异常向量链接方式
	localparam EXPT_VEC_DIRECT = 2'b00;
	localparam EXPT_VEC_VECTORED = 2'b01;
	
	/** 读CSR **/
	wire[31:0] mstatus_dout;
	wire[31:0] mie_dout;
	wire[31:0] mtvec_dout;
	wire[31:0] misa_dout;
	wire[31:0] mepc_dout;
	wire[31:0] mcause_dout;
	wire[31:0] mtval_dout;
	wire[31:0] mip_dout;
	wire[31:0] mvendorid_dout;
	wire[31:0] marchid_dout;
	wire[31:0] mimpid_dout;
	wire[31:0] mhartid_dout;
	wire[31:0] mscratch_dout;
	wire[31:0] mcycle_dout;
	wire[31:0] mcycleh_dout;
	wire[31:0] minstret_dout;
	wire[31:0] minstreth_dout;
	wire[31:0] dcsr_dout;
	wire[31:0] dpc_dout;
	wire[31:0] dscratch0_dout;
	wire[31:0] dscratch1_dout;
	
	assign csr_atom_rw_dout = 
		({32{csr_atom_rw_addr == CSR_MSTATUS_ADDR}} & mstatus_dout) | 
		({32{csr_atom_rw_addr == CSR_MIE_ADDR}} & mie_dout) | 
		({32{csr_atom_rw_addr == CSR_MTVEC_ADDR}} & mtvec_dout) | 
		({32{csr_atom_rw_addr == CSR_MISA_ADDR}} & misa_dout) | 
		({32{csr_atom_rw_addr == CSR_MEPC_ADDR}} & mepc_dout) | 
		({32{csr_atom_rw_addr == CSR_MCAUSE_ADDR}} & mcause_dout) | 
		({32{csr_atom_rw_addr == CSR_MTVAL_ADDR}} & mtval_dout) | 
		({32{csr_atom_rw_addr == CSR_MIP_ADDR}} & mip_dout) | 
		({32{csr_atom_rw_addr == CSR_MVENDORID_ADDR}} & mvendorid_dout) | 
		({32{csr_atom_rw_addr == CSR_MARCHID_ADDR}} & marchid_dout) | 
		({32{csr_atom_rw_addr == CSR_MIMPID_ADDR}} & mimpid_dout) | 
		({32{csr_atom_rw_addr == CSR_MHARTID_ADDR}} & mhartid_dout) | 
		({32{csr_atom_rw_addr == CSR_MSCRATCH_ADDR}} & mscratch_dout) | 
		({32{csr_atom_rw_addr == CSR_MCYCLE_ADDR}} & mcycle_dout) | 
		({32{csr_atom_rw_addr == CSR_MCYCLEH_ADDR}} & mcycleh_dout) | 
		({32{csr_atom_rw_addr == CSR_MINSTRET_ADDR}} & minstret_dout) | 
		({32{csr_atom_rw_addr == CSR_MINSTRETH_ADDR}} & minstreth_dout) | 
		({32{csr_atom_rw_addr == CSR_DCSR_ADDR}} & ((debug_supported == "true") ? dcsr_dout:32'h0000_0000)) | 
		({32{csr_atom_rw_addr == CSR_DPC_ADDR}} & ((debug_supported == "true") ? dpc_dout:32'h0000_0000)) | 
		({32{csr_atom_rw_addr == CSR_DSCRATCH0_ADDR}} & 
			(((debug_supported == "true") & (dscratch_n >= 1)) ? dscratch0_dout:32'h0000_0000)) | 
		({32{csr_atom_rw_addr == CSR_DSCRATCH1_ADDR}} & 
			(((debug_supported == "true") & (dscratch_n >= 2)) ? dscratch1_dout:32'h0000_0000));
	
	/** 机器模式状态寄存器(mstatus) **/
	reg mstatus_mie; // MIE域
	reg mstatus_mpie; // MPIE域
	
	assign mstatus_mie_v = mstatus_mie;
	
	assign mstatus_dout = {
		1'b0, // SD
		8'd0, // [WPRI]
		1'b0, // TSR
		1'b0, // TW
		1'b0, // TVM
		1'b0, // MXR
		1'b0, // SUM
		1'b0, // MPRV
		2'b00, // XS
		2'b00, // FS
		2'b11, // MPP
		2'b00, // [WPRI]
		1'b0, // SPP
		mstatus_mpie, // MPIE
		1'b0, // [WPRI]
		1'b0, // SPIE
		1'b0, // UPIE
		mstatus_mie, // MIE
		1'b0, // [WPRI]
		1'b0, // SIE
		1'b0 // UIE
	};
	
	// MIE域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mstatus_mie <= 1'b0;
		else if(itr_expt_enter | itr_expt_ret | (csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MSTATUS_ADDR)))
			mstatus_mie <= # simulation_delay 
				// 进入中断时清零, 退出中断时从MPIE载入
				(itr_expt_enter | itr_expt_ret) ? ((~itr_expt_enter) & mstatus_mpie):
				// 从CSR原子读写载入
				(({csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD} & csr_atom_rw_upd_mask_v[3]) | 
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_SET} & (mstatus_mie | csr_atom_rw_upd_mask_v[3])) | 
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR} & (mstatus_mie & csr_atom_rw_upd_mask_v[3])));
	end
	
	// MPIE域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mstatus_mpie <= 1'b1;
		else if(itr_expt_enter | itr_expt_ret | (csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MSTATUS_ADDR)))
			mstatus_mpie <= # simulation_delay 
				// 进入中断时从MIE载入, 退出中断时置位
				(itr_expt_enter | itr_expt_ret) ? (itr_expt_ret | mstatus_mie):
				// 从CSR原子读写载入
				(({csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD} & csr_atom_rw_upd_mask_v[7]) | 
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_SET} & (mstatus_mpie | csr_atom_rw_upd_mask_v[7])) | 
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR} & (mstatus_mpie & csr_atom_rw_upd_mask_v[7])));
	end
	
	/** 机器模式指令集架构寄存器(misa) **/
	assign misa_dout = {
		init_misa_mxl, // MXL(WARL)
		4'd0, // [WIRI]
		init_misa_extensions // Extensions(WARL)
	};
	
	/** 机器模式中断使能寄存器(mie) **/
	reg mie_msie; // MSIE域
	reg mie_mtie; // MTIE域
	reg mie_meie; // MEIE域
	
	assign mie_msie_v = mie_msie;
	assign mie_mtie_v = mie_mtie;
	assign mie_meie_v = mie_meie;
	
	assign mie_dout = {
		20'd0, // [WPRI]
		mie_meie, // MEIE
		1'b0, // [WPRI]
		1'b0, // SEIE
		1'b0, // UEIE
		mie_mtie, // MTIE
		1'b0, // [WPRI]
		1'b0, // STIE
		1'b0, // UTIE
		mie_msie, // MSIE
		1'b0, // [WPRI]
		1'b0, // SSIE
		1'b0 // USIE
	};
	
	// MSIE域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mie_msie <= 1'b0;
		else if(csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MIE_ADDR))
			mie_msie <= # simulation_delay 
				// 从CSR原子读写载入
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD} & csr_atom_rw_upd_mask_v[3]) | 
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_SET} & (mie_msie | csr_atom_rw_upd_mask_v[3])) | 
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR} & (mie_msie & csr_atom_rw_upd_mask_v[3]));
	end
	
	// MTIE域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mie_mtie <= 1'b0;
		else if(csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MIE_ADDR))
			mie_mtie <= # simulation_delay 
				// 从CSR原子读写载入
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD} & csr_atom_rw_upd_mask_v[7]) | 
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_SET} & (mie_mtie | csr_atom_rw_upd_mask_v[7])) | 
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR} & (mie_mtie & csr_atom_rw_upd_mask_v[7]));
	end
	
	// MEIE域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mie_meie <= 1'b0;
		else if(csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MIE_ADDR))
			mie_meie <= # simulation_delay 
				// 从CSR原子读写载入
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD} & csr_atom_rw_upd_mask_v[11]) | 
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_SET} & (mie_meie | csr_atom_rw_upd_mask_v[11])) | 
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR} & (mie_meie & csr_atom_rw_upd_mask_v[11]));
	end
	
	/** 机器模式异常入口基地址寄存器(mtvec) **/
	reg[1:0] mtvec_mode; // MODE域
	reg[29:0] mtvec_base; // BASE域
	
	assign itr_expt_vec_baseaddr = 
		((en_expt_vec_vectored == "false") | (mtvec_mode == EXPT_VEC_DIRECT) | (~itr_expt_is_intr)) ? 
			{mtvec_base, 2'b00}: // 链接到BASE
			({mtvec_base, 2'b00} + {itr_expt_cause, 2'b00}); // 链接到BASE+4*cause
	
	assign mtvec_dout = {
		mtvec_base, // BASE(WARL)
		mtvec_mode // MODE(WARL)
	};
	
	// MODE域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mtvec_mode <= 2'b00;
		else if(csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MTVEC_ADDR))
			mtvec_mode <= # simulation_delay 
				// 从CSR原子读写载入
				({2{csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD}} & csr_atom_rw_upd_mask_v[1:0]) | 
				({2{csr_atom_rw_upd_type == CSR_UPD_TYPE_SET}} & (mtvec_mode | csr_atom_rw_upd_mask_v[1:0])) | 
				({2{csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR}} & (mtvec_mode & csr_atom_rw_upd_mask_v[1:0]));
	end
	
	// BASE域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mtvec_base <= init_mtvec_base;
		else if(csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MTVEC_ADDR))
			mtvec_base <= # simulation_delay 
				// 从CSR原子读写载入
				({30{csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD}} & csr_atom_rw_upd_mask_v[31:2]) | 
				({30{csr_atom_rw_upd_type == CSR_UPD_TYPE_SET}} & (mtvec_base | csr_atom_rw_upd_mask_v[31:2])) | 
				({30{csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR}} & (mtvec_base & csr_atom_rw_upd_mask_v[31:2]));
	end
	
	/** 机器模式异常PC寄存器(mepc) **/
	reg[31:0] mepc_mepc; // MEPC域
	
	assign mepc_ret_addr = mepc_mepc;
	
	assign mepc_dout = {
		mepc_mepc // mepc
	};
	
	// MEPC域
	always @(posedge clk)
	begin
		if(itr_expt_enter | (csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MEPC_ADDR)))
			mepc_mepc <= # simulation_delay 
				// 进入中断时锁存返回地址
				itr_expt_enter ? itr_expt_ret_addr:
				// 从CSR原子读写载入
				(({32{csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD}} & csr_atom_rw_upd_mask_v) | 
				({32{csr_atom_rw_upd_type == CSR_UPD_TYPE_SET}} & (mepc_mepc | csr_atom_rw_upd_mask_v)) | 
				({32{csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR}} & (mepc_mepc & csr_atom_rw_upd_mask_v)));
	end
	
	/** 机器模式异常原因寄存器(mcause) **/
	reg[30:0] mcause_exception_code; // Exception Code域
	reg mcause_interrupt; // Interrupt域
	
	assign mcause_dout = {
		mcause_interrupt, // Interrupt
		mcause_exception_code // Exception Code(WLRL)
	};
	
	// Exception Code域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mcause_exception_code <= init_mcause_exception_code;
		else if(itr_expt_enter | (csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MCAUSE_ADDR)))
			mcause_exception_code <= # simulation_delay 
				// 进入中断时锁存中断原因
				itr_expt_enter ? {23'd0, itr_expt_cause}:
				// 从CSR原子读写载入
				(({31{csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD}} & csr_atom_rw_upd_mask_v[30:0]) | 
				({31{csr_atom_rw_upd_type == CSR_UPD_TYPE_SET}} & (mcause_exception_code | csr_atom_rw_upd_mask_v[30:0])) | 
				({31{csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR}} & (mcause_exception_code & csr_atom_rw_upd_mask_v[30:0])));
	end
	
	// Interrupt域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mcause_interrupt <= init_mcause_interrupt;
		else if(itr_expt_enter | (csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MCAUSE_ADDR)))
			mcause_interrupt <= # simulation_delay 
				// 进入中断时锁存是否中断标志
				itr_expt_enter ? itr_expt_is_intr:
				// 从CSR原子读写载入
				(({csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD} & csr_atom_rw_upd_mask_v[31]) | 
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_SET} & (mcause_interrupt | csr_atom_rw_upd_mask_v[31])) | 
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR} & (mcause_interrupt & csr_atom_rw_upd_mask_v[31])));
	end
	
	/** 机器模式异常值寄存器(mtval) **/
	reg[31:0] mtval_mtval; // MTVAL域
	
	assign mtval_dout = {
		mtval_mtval // mtval
	};
	
	// MTVAL域
	always @(posedge clk)
	begin
		if(itr_expt_enter | (csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MTVAL_ADDR)))
			mtval_mtval <= # simulation_delay 
				// 进入中断时锁存附加信息
				itr_expt_enter ? itr_expt_val:
				// 从CSR原子读写载入
				(({32{csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD}} & csr_atom_rw_upd_mask_v) | 
				({32{csr_atom_rw_upd_type == CSR_UPD_TYPE_SET}} & (mtval_mtval | csr_atom_rw_upd_mask_v)) | 
				({32{csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR}} & (mtval_mtval & csr_atom_rw_upd_mask_v)));
	end
	
	/** 机器模式中断等待寄存器(mip) **/
	reg mip_msip; // MSIP域
	reg mip_mtip; // MTIP域
	reg mip_meip; // MEIP域
	
	assign mip_dout = {
		20'd0, // [WIRI]
		mip_meip, // MEIP
		1'b0, // [WIRI]
		1'b0, // SEIP
		1'b0, // UEIP
		mip_mtip, // MTIP
		1'b0, // [WIRI]
		1'b0, // STIP
		1'b0, // UTIP
		mip_msip, // MSIP
		1'b0, // [WIRI]
		1'b0, // SSIP
		1'b0 // USIP
	};
	
	// MSIP域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mip_msip <= 1'b0;
		else
			mip_msip <= # simulation_delay sw_itr_req;
	end
	// MTIP域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mip_mtip <= 1'b0;
		else
			mip_mtip <= # simulation_delay tmr_itr_req;
	end
	// MEIP域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mip_meip <= 1'b0;
		else
			mip_meip <= # simulation_delay ext_itr_req;
	end
	
	/** 机器模式供应商编号寄存器(mvendorid) **/
	assign mvendorid_dout = {
		init_mvendorid_bank, // Bank
		init_mvendorid_offset // Offset
	};
	
	/** 机器模式架构编号寄存器(marchid) **/
	assign marchid_dout = {
		init_marchid // Architecture ID
	};
	
	/** 机器模式硬件实现编号寄存器(mimpid) **/
	assign mimpid_dout = {
		init_mimpid // Implementation
	};
	
	/** Hart编号寄存器(mhartid) **/
	assign mhartid_dout = {
		init_mhartid // Hart ID
	};
	
	/** 机器模式擦写寄存器(mscratch) **/
	reg[31:0] mscratch_mscratch; // MSCRATCH域
	
	assign mscratch_dout = {
		mscratch_mscratch // mscratch
	};
	
	// MSCRATCH域
	always @(posedge clk)
	begin
		if(csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MSCRATCH_ADDR))
			mscratch_mscratch <= # simulation_delay 
				// 从CSR原子读写载入
				({32{csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD}} & csr_atom_rw_upd_mask_v) | 
				({32{csr_atom_rw_upd_type == CSR_UPD_TYPE_SET}} & (mscratch_mscratch | csr_atom_rw_upd_mask_v)) | 
				({32{csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR}} & (mscratch_mscratch & csr_atom_rw_upd_mask_v));
	end
	
	/** 周期计数器(mcycle, mcycleh) **/
	reg[31:0] mcycle_mcycle; // MCYCLE域
	reg[31:0] mcycleh_mcycleh; // MCYCLEH域
	
	assign mcycle_dout = 
		(en_performance_monitor == "true") ? {
			mcycle_mcycle
		}:32'd0;
	assign mcycleh_dout = 
		(en_performance_monitor == "true") ? {
			mcycleh_mcycleh
		}:32'd0;
	
	// MCYCLE域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mcycle_mcycle <= 32'd0;
		else if(((~in_dbg_mode) | (debug_supported == "false")) | 
			(csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MCYCLE_ADDR)))
			mcycle_mcycle <= # simulation_delay 
				(csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MCYCLE_ADDR)) ? 
					// 从CSR原子读写载入
					(({csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD} & csr_atom_rw_upd_mask_v) | 
					({csr_atom_rw_upd_type == CSR_UPD_TYPE_SET} & (mcycle_mcycle | csr_atom_rw_upd_mask_v)) | 
					({csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR} & (mcycle_mcycle & csr_atom_rw_upd_mask_v))):
					// 自增
					(mcycle_mcycle + 32'd1);
	end
	
	// MCYCLEH域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			mcycleh_mcycleh <= 32'd0;
		else if((((~in_dbg_mode) | (debug_supported == "false")) & (&mcycle_mcycle)) | 
			(csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MCYCLEH_ADDR)))
			mcycleh_mcycleh <= # simulation_delay 
				(csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MCYCLEH_ADDR)) ? 
					// 从CSR原子读写载入
					(({csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD} & csr_atom_rw_upd_mask_v) | 
					({csr_atom_rw_upd_type == CSR_UPD_TYPE_SET} & (mcycleh_mcycleh | csr_atom_rw_upd_mask_v)) | 
					({csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR} & (mcycleh_mcycleh & csr_atom_rw_upd_mask_v))):
					// 自增
					(mcycleh_mcycleh + 32'd1);
	end
	
	/** 退休指令计数器(minstret, minstreth) **/
	reg[31:0] minstret_minstret; // MINSTRET域
	reg[31:0] minstreth_minstreth; // MINSTRETH域
	
	assign minstret_dout = 
		(en_performance_monitor == "true") ? {
			minstret_minstret
		}:32'd0;
	assign minstreth_dout = 
		(en_performance_monitor == "true") ? {
			minstreth_minstreth
		}:32'd0;
	
	// MINSTRET域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			minstret_minstret <= 32'd0;
		else if((((~in_dbg_mode) | (debug_supported == "false")) & inst_retire_cnt_en) | 
			(csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MINSTRET_ADDR)))
			minstret_minstret <= # simulation_delay 
				(csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MINSTRET_ADDR)) ? 
					// 从CSR原子读写载入
					(({csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD} & csr_atom_rw_upd_mask_v) | 
					({csr_atom_rw_upd_type == CSR_UPD_TYPE_SET} & (minstret_minstret | csr_atom_rw_upd_mask_v)) | 
					({csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR} & (minstret_minstret & csr_atom_rw_upd_mask_v))):
					// 自增
					(minstret_minstret + 32'd1);
	end
	
	// MINSTRETH域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			minstreth_minstreth <= 32'd0;
		else if((((~in_dbg_mode) | (debug_supported == "false")) & inst_retire_cnt_en & (&minstret_minstret)) | 
			(csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MINSTRETH_ADDR)))
			minstreth_minstreth <= # simulation_delay 
				(csr_atom_rw_valid & (csr_atom_rw_addr == CSR_MINSTRETH_ADDR)) ? 
					// 从CSR原子读写载入
					(({csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD} & csr_atom_rw_upd_mask_v) | 
					({csr_atom_rw_upd_type == CSR_UPD_TYPE_SET} & (minstreth_minstreth | csr_atom_rw_upd_mask_v)) | 
					({csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR} & (minstreth_minstreth & csr_atom_rw_upd_mask_v))):
					// 自增
					(minstreth_minstreth + 32'd1);
	end
	
	/** 调试模式控制/状态寄存器(dcsr) **/
	reg dcsr_ebreakm; // EBREAKM域
	reg[2:0] dcsr_cause; // CAUSE域
	reg dcsr_step; // STEP域
	
	assign dcsr_ebreakm_v = dcsr_ebreakm;
	assign dcsr_step_v = dcsr_step;
	
	assign dcsr_dout = {
		4'd4, // debugver
		1'b0, // reserved
		3'b000, // extcause
		4'b0000, // reserved
		1'b0, // cetrig
		1'b0, // pelp
		1'b0, // ebreakvs
		1'b0, // ebreakvu
		dcsr_ebreakm, // ebreakm
		1'b0, // reserved
		1'b0, // ebreaks
		1'b0, // ebreaku
		1'b0, // stepie
		1'b1, // stopcount
		1'b0, // stoptime
		dcsr_cause, // cause
		1'b0, // v
		1'b0, // mprven
		1'b0, // nmip
		dcsr_step, // step
		2'b11 // prv
	};
	
	// EBREAKM域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			dcsr_ebreakm <= 1'b0;
		else if(csr_atom_rw_valid & (csr_atom_rw_addr == CSR_DCSR_ADDR))
			dcsr_ebreakm <= # simulation_delay 
				// 从CSR原子读写载入
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD} & csr_atom_rw_upd_mask_v[15]) | 
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_SET} & (dcsr_ebreakm | csr_atom_rw_upd_mask_v[15])) | 
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR} & (dcsr_ebreakm & csr_atom_rw_upd_mask_v[15]));
	end
	// CAUSE域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			dcsr_cause <= 3'b000;
		else if(dbg_mode_enter)
			dcsr_cause <= # simulation_delay dbg_mode_cause;
	end
	// STEP域
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			dcsr_step <= 1'b0;
		else if(csr_atom_rw_valid & (csr_atom_rw_addr == CSR_DCSR_ADDR))
			dcsr_step <= # simulation_delay 
				// 从CSR原子读写载入
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD} & csr_atom_rw_upd_mask_v[2]) | 
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_SET} & (dcsr_step | csr_atom_rw_upd_mask_v[2])) | 
				({csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR} & (dcsr_step & csr_atom_rw_upd_mask_v[2]));
	end
	
	/** 调试模式PC寄存器(dpc) **/
	reg[31:0] dpc_dpc; // DPC域
	
	assign dpc_ret_addr = dpc_dpc;
	
	assign dpc_dout = {
		dpc_dpc // dpc
	};
	
	// DPC域
	always @(posedge clk)
	begin
		if(dbg_mode_enter | (csr_atom_rw_valid & (csr_atom_rw_addr == CSR_DPC_ADDR)))
			dpc_dpc <= # simulation_delay 
				// 进入调试模式时锁存返回地址
				dbg_mode_enter ? dbg_mode_ret_addr:
				// 从CSR原子读写载入
				(({32{csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD}} & csr_atom_rw_upd_mask_v) | 
				({32{csr_atom_rw_upd_type == CSR_UPD_TYPE_SET}} & (dpc_dpc | csr_atom_rw_upd_mask_v)) | 
				({32{csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR}} & (dpc_dpc & csr_atom_rw_upd_mask_v)));
	end
	
	/** 调试模式擦写寄存器#0(dscratch0) **/
	reg[31:0] dscratch0_dscratch0; // DSCRATCH0域
	
	assign dscratch0_dout = {
		dscratch0_dscratch0 // dscratch0
	};
	
	// DSCRATCH0域
	always @(posedge clk)
	begin
		if(csr_atom_rw_valid & (csr_atom_rw_addr == CSR_DSCRATCH0_ADDR))
			dscratch0_dscratch0 <= # simulation_delay 
				// 从CSR原子读写载入
				({32{csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD}} & csr_atom_rw_upd_mask_v) | 
				({32{csr_atom_rw_upd_type == CSR_UPD_TYPE_SET}} & (dscratch0_dscratch0 | csr_atom_rw_upd_mask_v)) | 
				({32{csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR}} & (dscratch0_dscratch0 & csr_atom_rw_upd_mask_v));
	end
	
	/** 调试模式擦写寄存器#1(dscratch1) **/
	reg[31:0] dscratch1_dscratch1; // DSCRATCH1域
	
	assign dscratch1_dout = {
		dscratch1_dscratch1 // dscratch1
	};
	
	// DSCRATCH1域
	always @(posedge clk)
	begin
		if(csr_atom_rw_valid & (csr_atom_rw_addr == CSR_DSCRATCH1_ADDR))
			dscratch1_dscratch1 <= # simulation_delay 
				// 从CSR原子读写载入
				({32{csr_atom_rw_upd_type == CSR_UPD_TYPE_LOAD}} & csr_atom_rw_upd_mask_v) | 
				({32{csr_atom_rw_upd_type == CSR_UPD_TYPE_SET}} & (dscratch1_dscratch1 | csr_atom_rw_upd_mask_v)) | 
				({32{csr_atom_rw_upd_type == CSR_UPD_TYPE_CLR}} & (dscratch1_dscratch1 & csr_atom_rw_upd_mask_v));
	end
	
endmodule
