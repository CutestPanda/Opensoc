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

`ifndef __TRANSACTION_H

`define __TRANSACTION_H

`include "uvm_macros.svh"

import uvm_pkg::*;

/** 枚举类型: RISC-V指令类型 **/
typedef enum{
	// 保存PC
	LUI, AUIPC, 
	// 无条件跳转
	JAL, JALR, 
	// 有条件直接跳转
	BEQ, BNE, BLT, BGE, BLTU, BGEU, 
	// 加载/存储
	LB, LH, LW, LBU, LHU, 
	SB, SH, SW, 
	// 立即数算术
	ADDI, SLTI, SLTIU, XORI, ORI, 
	ANDI, SLLI, SRLI, SRAI, 
	// 寄存器算术
	ADD, SUB, SLL, SLT, SLTU, 
	XOR, SRL, SRA, OR, AND, 
	MUL, MULH, MULHSU, MULHU, 
	DIV, DIVU, REM, REMU, 
	// 存储器屏障
	FENCE, FENCE_I, 
	// 环境调用
	ECALL, EBREAK, 
	// CRS读写
	CSRRW, CSRRS, CSRRC, 
	CSRRWI, CSRRSI, CSRRCI,
	// 中断/异常返回
	MRET
}RiscVInstType;

/** 事务:块级控制 **/
class BlkCtrlTrans extends uvm_sequence_item;
	
	rand int unsigned start_wait_period_n; // 启动功能模块的等待周期数
	
	// 域自动化
	`uvm_object_utils_begin(BlkCtrlTrans)
		`uvm_field_int(start_wait_period_n, UVM_ALL_ON)
	`uvm_object_utils_end
	
	function new(string name = "BlkCtrlTrans");
		super.new();
	endfunction
	
endclass

/** 事务:AXI **/
class AXITrans #(
	integer addr_width = 32, // 地址位宽(1~64)
	integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
    integer bresp_width = 2, // 写响应信号位宽(0 | 2 | 3)
    integer rresp_width = 2 // 读响应信号位宽(0 | 2 | 3)
)extends uvm_sequence_item;
	
	// 是否读传输
	rand bit is_rd_trans;
	
	// 数据个数
	rand int unsigned data_n;
	
	// 地址通道
	rand bit[addr_width-1:0] addr;
	rand bit[1:0] burst;
	rand bit[3:0] cache;
	rand bit[7:0] len;
	rand bit lock;
	rand bit[2:0] prot;
    rand bit[2:0] size;
    rand byte unsigned addr_wait_period_n; // 地址通道的等待周期数
	
	// 写数据通道
	rand bit[data_width-1:0] wdata[$];
    rand bit wlast[$];
    rand bit[data_width/8-1:0] wstrb[$];
	rand byte unsigned wdata_wait_period_n[]; // 写数据通道的等待周期数
	
	// 写响应通道
	rand bit[bresp_width-1:0] bresp;
	
	// 读数据通道
	rand bit[data_width-1:0] rdata[$];
    rand bit rlast[$];
    rand bit[rresp_width-1:0] rresp[$];
	rand byte unsigned rdata_wait_period_n[]; // 读数据通道的等待周期数
	
	// 域自动化
	`uvm_object_param_utils_begin(AXITrans #(.addr_width(addr_width), .data_width(data_width), .bresp_width(bresp_width), .rresp_width(rresp_width)))
		`uvm_field_int(data_n, UVM_ALL_ON)
		
		`uvm_field_int(addr, UVM_ALL_ON)
		`uvm_field_int(burst, UVM_ALL_ON)
		`uvm_field_int(cache, UVM_ALL_ON)
		`uvm_field_int(len, UVM_ALL_ON)
		`uvm_field_int(lock, UVM_ALL_ON)
		`uvm_field_int(prot, UVM_ALL_ON)
		`uvm_field_int(size, UVM_ALL_ON)
		`uvm_field_int(addr_wait_period_n, UVM_ALL_ON)
		
		`uvm_field_queue_int(wdata, UVM_ALL_ON)
		`uvm_field_queue_int(wstrb, UVM_ALL_ON)
		`uvm_field_array_int(wdata_wait_period_n, UVM_ALL_ON)
		
		`uvm_field_int(bresp, UVM_ALL_ON)
		
		`uvm_field_queue_int(rdata, UVM_ALL_ON)
		`uvm_field_queue_int(rresp, UVM_ALL_ON)
		`uvm_field_array_int(rdata_wait_period_n, UVM_ALL_ON)
	`uvm_object_utils_end
	
	function new(string name = "AXITrans");
		super.new();
	endfunction
	
endclass

/** 事务:APB **/
class APBTrans #(
	integer addr_width = 32, // 地址位宽(1~32)
    integer data_width = 32 // 数据位宽(8 | 16 | 32)
)extends uvm_sequence_item;
    
	// 主机
    rand bit[addr_width-1:0] addr; // 地址
    rand bit[data_width-1:0] wdata; // 写数据
    rand bit[data_width/8-1:0] wstrb; // 写字节掩码
    rand bit write; // 是否写传输
	
	// 从机
	rand bit[data_width-1:0] rdata; // 读数据
	rand bit slverr; // 从机错误
	
	// 从机
    rand byte unsigned wait_period_n; // 传输的等待周期数
	
	// 域自动化
	`uvm_object_utils_begin(APBTrans)
		`uvm_field_int(addr, UVM_ALL_ON)
		`uvm_field_int(wdata, UVM_ALL_ON)
		`uvm_field_int(wstrb, UVM_ALL_ON)
		`uvm_field_int(write, UVM_ALL_ON)
		`uvm_field_int(rdata, UVM_ALL_ON)
		`uvm_field_int(slverr, UVM_ALL_ON)
		`uvm_field_int(wait_period_n, UVM_ALL_ON)
	`uvm_object_utils_end
	
	function new(string name = "APBTrans");
		super.new();
	endfunction
    
endclass

/** 事务:AXIS **/
class AXISTrans #(
    integer data_width = 32, // 数据位宽(必须能被8整除)
    integer user_width = 0 // 用户数据位宽
)extends uvm_sequence_item;
	
	// 数据个数
	rand int unsigned data_n;
	
	// 主机
	rand bit[data_width-1:0] data[$];
    rand bit[data_width/8-1:0] keep[$];
	rand bit[data_width/8-1:0] strb[$];
    rand bit[user_width-1:0] user[$];
	rand bit last[$];
	
	// 主机或从机
    rand byte unsigned wait_period_n[]; // 每个数据的等待周期数
	
	// 域自动化
	`uvm_object_param_utils_begin(AXISTrans #(.data_width(data_width), .user_width(user_width)))
		`uvm_field_int(data_n, UVM_ALL_ON)
		`uvm_field_queue_int(data, UVM_ALL_ON)
		`uvm_field_queue_int(keep, UVM_ALL_ON)
		`uvm_field_queue_int(strb, UVM_ALL_ON)
		`uvm_field_queue_int(user, UVM_ALL_ON)
		`uvm_field_array_int(wait_period_n, UVM_ALL_ON)
	`uvm_object_utils_end
	
	function new(string name = "AXISTrans");
		super.new();
	endfunction
	
endclass

/** 事务:AHB **/
class AHBTrans #(
    integer addr_width = 32, // 地址位宽(10~64)
    integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
    integer burst_width = 3, // 突发类型位宽(0~3)
    integer prot_width = 4, // 保护类型位宽(0 | 4 | 7)
    integer master_width = 1 // 主机标识位宽(0~8)
)extends uvm_sequence_item;
	
	// 地址和附加传输信息
    rand bit[addr_width-1:0] haddr;
	rand bit[burst_width-1:0] hburst;
	rand bit hmastllock;
	rand bit[prot_width-1:0] hprot;
	rand bit[2:0] hsize;
	rand bit hnonsec;
    rand bit hexcl;
    rand bit[master_width-1:0] hmaster;
    rand bit hwrite;
	
	// 写数据和写字节选通
    rand bit[data_width-1:0] hwdata[$];
    rand bit[data_width/8-1:0] hwstrb[$];
	// 读数据
	rand bit[data_width-1:0] hrdata[$];
	// 从机响应
    rand bit hresp[$];
    rand bit hexokay[$];
    
	// 传输的等待周期数
	/*
	将该数组的长度作为突发长度
	用于主机事务时, 指定每次传输后BUSY或IDLE的周期数
	*/
	rand byte unsigned wait_period_n[];
	
	// 域自动化
	`uvm_object_param_utils_begin(AHBTrans #(.addr_width(addr_width), .data_width(data_width), .burst_width(burst_width), .prot_width(prot_width), .master_width(master_width)))
		`uvm_field_int(haddr, UVM_ALL_ON)
		`uvm_field_int(hburst, UVM_ALL_ON)
		`uvm_field_int(hmastllock, UVM_ALL_ON)
		`uvm_field_int(hprot, UVM_ALL_ON)
		`uvm_field_int(hsize, UVM_ALL_ON)
		`uvm_field_int(hnonsec, UVM_ALL_ON)
		`uvm_field_int(hexcl, UVM_ALL_ON)
		`uvm_field_int(hmaster, UVM_ALL_ON)
		`uvm_field_int(hwrite, UVM_ALL_ON)
		`uvm_field_queue_int(hwdata, UVM_ALL_ON)
		`uvm_field_queue_int(hwstrb, UVM_ALL_ON)
		`uvm_field_queue_int(hrdata, UVM_ALL_ON)
		`uvm_field_queue_int(hresp, UVM_ALL_ON)
		`uvm_field_queue_int(hexokay, UVM_ALL_ON)
		`uvm_field_array_int(wait_period_n, UVM_ALL_ON)
	`uvm_object_utils_end
	
endclass

/** 事务:req-ack **/
class ReqAckTrans #(
	integer req_payload_width = 32, // 请求数据位宽
	integer resp_payload_width = 32 // 响应数据位宽
)extends uvm_sequence_item;
	
	// 请求
	rand bit[req_payload_width-1:0] req_payload; // 数据
	rand byte unsigned req_wait_period_n; // 等待周期数
	
	// 响应
	rand bit[resp_payload_width-1:0] resp_payload; // 数据
	rand byte unsigned resp_wait_period_n; // 等待周期数
	
	`uvm_object_param_utils_begin(ReqAckTrans #(.req_payload_width(req_payload_width), .resp_payload_width(resp_payload_width)))
		`uvm_field_int(req_payload, UVM_ALL_ON)
		`uvm_field_int(req_wait_period_n, UVM_ALL_ON)
		`uvm_field_int(resp_payload, UVM_ALL_ON)
		`uvm_field_int(resp_wait_period_n, UVM_ALL_ON)
	`uvm_object_utils_end
	
endclass

/** 事务:ICB **/
class ICBTrans #(
	integer addr_width = 32, // 地址位宽
	integer data_width = 32 // 数据位宽
)extends uvm_sequence_item;
	
	rand bit[addr_width-1:0] cmd_addr;
	rand bit cmd_read;
	rand bit[data_width-1:0] cmd_wdata;
	rand bit[data_width/8-1:0] cmd_wmask;
	rand byte unsigned cmd_wait_period_n; // 等待周期数
	
	rand bit[data_width-1:0] rsp_rdata;
	rand bit rsp_err;
	rand byte unsigned rsp_wait_period_n; // 等待周期数
	
	`uvm_object_param_utils_begin(ICBTrans #(.addr_width(addr_width), .data_width(data_width)))
		`uvm_field_int(cmd_addr, UVM_ALL_ON)
		`uvm_field_int(cmd_read, UVM_ALL_ON)
		`uvm_field_int(cmd_wdata, UVM_ALL_ON)
		`uvm_field_int(cmd_wmask, UVM_ALL_ON)
		`uvm_field_int(cmd_wait_period_n, UVM_ALL_ON)
		`uvm_field_int(rsp_rdata, UVM_ALL_ON)
		`uvm_field_int(rsp_err, UVM_ALL_ON)
		`uvm_field_int(rsp_wait_period_n, UVM_ALL_ON)
	`uvm_object_utils_end
	
endclass

/**
事务:RISC-V指令

仅适用于RV32IM
**/
class RiscVInstTrans extends uvm_sequence_item;
	
	rand bit[31:0] inst;
	
	rand RiscVInstType inst_type; // 指令类型
	rand int imm; // 操作立即数
	rand bit[4:0] rd; // 目标寄存器索引
	rand bit[4:0] rs1; // 源寄存器1索引
	rand bit[4:0] rs2; // 源寄存器2索引
	rand bit[4:0] zimm; // CSR更新用立即数
	rand bit[4:0] shamt; // 移位的位数
	rand bit[3:0] pred; // FENCE指令前继操作集
	rand bit[3:0] succ; // FENCE指令后继操作集
	rand bit[11:0] csr_addr; // CSR寄存器地址
	
	`uvm_object_utils_begin(RiscVInstTrans)
		`uvm_field_int(inst, UVM_ALL_ON)
		`uvm_field_enum(RiscVInstType, inst_type, UVM_ALL_ON)
		`uvm_field_int(imm, UVM_ALL_ON)
		`uvm_field_int(rd, UVM_ALL_ON)
		`uvm_field_int(rs1, UVM_ALL_ON)
		`uvm_field_int(rs2, UVM_ALL_ON)
		`uvm_field_int(zimm, UVM_ALL_ON)
		`uvm_field_int(shamt, UVM_ALL_ON)
		`uvm_field_int(pred, UVM_ALL_ON)
		`uvm_field_int(succ, UVM_ALL_ON)
		`uvm_field_int(csr_addr, UVM_ALL_ON)
	`uvm_object_utils_end
	
	constraint inst_cst{
		// 约束跳转偏移量
		if((inst_type == BEQ) || (inst_type == BNE) || 
			(inst_type == BLT) || (inst_type == BGE) || 
			(inst_type == BLTU) || (inst_type == BGEU) || 
			(inst_type == JAL))
			imm[0] == 1'b0;
		
		// 约束inst[6:0]
		if(inst_type == LUI)
			inst[6:0] == 7'b0110111;
		else if(inst_type == AUIPC)
			inst[6:0] == 7'b0010111;
		else if(inst_type == JAL)
			inst[6:0] == 7'b1101111;
		else if(inst_type == JALR)
			inst[6:0] == 7'b1100111;
		else if((inst_type == BEQ) || (inst_type == BNE) || 
			(inst_type == BLT) || (inst_type == BGE) || 
			(inst_type == BLTU) || (inst_type == BGEU))
			inst[6:0] == 7'b1100011;
		else if((inst_type == LB) || (inst_type == LH) || 
			(inst_type == LW) || (inst_type == LBU) || 
			(inst_type == LHU))
			inst[6:0] == 7'b0000011;
		else if((inst_type == SB) || (inst_type == SH) || 
			(inst_type == SW))
			inst[6:0] == 7'b0100011;
		else if((inst_type == ADDI) || (inst_type == SLTI) || 
			(inst_type == SLTIU) || (inst_type == XORI) || 
			(inst_type == ORI) || (inst_type == ANDI) || 
			(inst_type == SLLI) || (inst_type == SRLI) || 
			(inst_type == SRAI))
			inst[6:0] == 7'b0010011;
		else if((inst_type == ADD) || (inst_type == SUB) || 
			(inst_type == SLL) || (inst_type == SLT) || 
			(inst_type == SLTU) || (inst_type == XOR) || 
			(inst_type == SRL) || (inst_type == SRA) || 
			(inst_type == OR) || (inst_type == AND) || 
			(inst_type == MUL) || (inst_type == MULH) || 
			(inst_type == MULHSU) || (inst_type == MULHU) || 
			(inst_type == DIV) || (inst_type == DIVU) || 
			(inst_type == REM) || (inst_type == REMU))
			inst[6:0] == 7'b0110011;
		else if((inst_type == FENCE) || (inst_type == FENCE_I))
			inst[6:0] == 7'b0001111;
		else
			inst[6:0] == 7'b1110011;
		
		// 约束inst[11:7]
		if((inst_type == BEQ) || (inst_type == BNE) || 
			(inst_type == BLT) || (inst_type == BGE) || 
			(inst_type == BLTU) || (inst_type == BGEU))
			inst[11:7] == {imm[4:1], imm[11]};
		else if((inst_type == SB) || (inst_type == SH) || 
			(inst_type == SW))
			inst[11:7] == imm[4:0];
		else if((inst_type == FENCE) || (inst_type == FENCE_I) || 
			(inst_type == ECALL) || (inst_type == EBREAK) || (inst_type == MRET))
			inst[11:7] == 5'b00000;
		else
			inst[11:7] == rd;
		
		// 约束inst[14:12]
		if((inst_type == JALR) || (inst_type == BEQ) || 
			(inst_type == LB) || (inst_type == SB) || 
			(inst_type == ADDI) || (inst_type == ADD) || 
			(inst_type == SUB) || (inst_type == FENCE) || 
			(inst_type == ECALL) || (inst_type == EBREAK) || 
			(inst_type == MUL) || (inst_type == MRET))
			inst[14:12] == 3'b000;
		else if((inst_type == BNE) || (inst_type == LH) || 
			(inst_type == SH) || (inst_type == SLLI) || 
			(inst_type == SLL) || (inst_type == FENCE_I) || 
			(inst_type == CSRRW) || (inst_type == MULH))
			inst[14:12] == 3'b001;
		else if((inst_type == LW) || (inst_type == SW) || 
			(inst_type == SLTI) || (inst_type == SLT) || 
			(inst_type == CSRRS) || (inst_type == MULHSU))
			inst[14:12] == 3'b010;
		else if((inst_type == SLTIU) || (inst_type == SLTU) || 
			(inst_type == CSRRC) || (inst_type == MULHU))
			inst[14:12] == 3'b011;
		else if((inst_type == BLT) || (inst_type == LBU) || 
			(inst_type == XORI) || (inst_type == XOR) || 
			(inst_type == DIV))
			inst[14:12] == 3'b100;
		else if((inst_type == BGE) || (inst_type == LHU) || 
			(inst_type == SRLI) || (inst_type == SRAI) || 
			(inst_type == SRL) || (inst_type == SRA) || 
			(inst_type == CSRRWI) || (inst_type == DIVU))
			inst[14:12] == 3'b101;
		else if((inst_type == BLTU) || (inst_type == ORI) || 
			(inst_type == OR) || (inst_type == CSRRSI) || 
			(inst_type == REM))
			inst[14:12] == 3'b110;
		else if((inst_type == BGEU) || (inst_type == ANDI) || 
			(inst_type == AND) || (inst_type == CSRRCI) || 
			(inst_type == REMU))
			inst[14:12] == 3'b111;
		else
			inst[14:12] == imm[14:12];
		
		// 约束inst[19:15]
		if((inst_type == FENCE) || (inst_type == FENCE_I) || 
			(inst_type == ECALL) || (inst_type == EBREAK) || (inst_type == MRET))
			inst[19:15] == 5'b00000;
		else if((inst_type == CSRRWI) || (inst_type == CSRRSI) || 
			(inst_type == CSRRCI))
			inst[19:15] == zimm;
		else if((inst_type == LUI) || (inst_type == AUIPC) || 
			(inst_type == JAL))
			inst[19:15] == imm[19:15];
		else
			inst[19:15] == rs1;
		
		// 约束inst[24:20]
		if((inst_type == LUI) || (inst_type == AUIPC))
			inst[24:20] == imm[24:20];
		else if(inst_type == JAL)
			inst[24:20] == {imm[4:1], imm[11]};
		else if((inst_type == JALR) || (inst_type == LB) || 
			(inst_type == LH) || (inst_type == LW) || 
			(inst_type == LBU) || (inst_type == LHU) || 
			(inst_type == ADDI) || (inst_type == SLTI) || 
			(inst_type == SLTIU) || (inst_type == XORI) || 
			(inst_type == ORI) || (inst_type == ANDI))
			inst[24:20] == imm[4:0];
		else if((inst_type == SLLI) || (inst_type == SRLI) || 
			(inst_type == SRAI))
			inst[24:20] == shamt;
		else if(inst_type == FENCE)
			inst[24:20] == {pred[0], succ};
		else if((inst_type == FENCE_I) || (inst_type == ECALL))
			inst[24:20] == 5'b00000;
		else if(inst_type == EBREAK)
			inst[24:20] == 5'b00001;
		else if(inst_type == MRET)
			inst[24:20] == 5'b00010;
		else if((inst_type == CSRRW) || (inst_type == CSRRS) || 
			(inst_type == CSRRC) || (inst_type == CSRRWI) || 
			(inst_type == CSRRSI) || (inst_type == CSRRCI))
			inst[24:20] == csr_addr[4:0];
		else
			inst[24:20] == rs2;
		
		// 约束inst[31:25]
		if((inst_type == LUI) || (inst_type == AUIPC))
			inst[31:25] == imm[31:25];
		else if(inst_type == JAL)
			inst[31:25] == {imm[20], imm[10:5]};
		else if((inst_type == BEQ) || (inst_type == BNE) || 
			(inst_type == BLT) || (inst_type == BGE) || 
			(inst_type == BLTU) || (inst_type == BGEU))
			inst[31:25] == {imm[12], imm[10:5]};
		else if((inst_type == JALR) || (inst_type == LB) || 
			(inst_type == LH) || (inst_type == LW) || 
			(inst_type == LBU) || (inst_type == LHU) || 
			(inst_type == SB) || (inst_type == SH) || 
			(inst_type == SW) || (inst_type == ADDI) || 
			(inst_type == SLTI) || (inst_type == SLTIU) || 
			(inst_type == XORI) || (inst_type == ORI) || 
			(inst_type == ANDI))
			inst[31:25] == imm[11:5];
		else if((inst_type == SLLI) || (inst_type == SRLI) || 
			(inst_type == ADD) || (inst_type == SLL) || 
			(inst_type == SLT) || (inst_type == SLTU) || 
			(inst_type == XOR) || (inst_type == SRL) || 
			(inst_type == OR) || (inst_type == AND) || 
			(inst_type == FENCE_I) || (inst_type == ECALL) || 
			(inst_type == EBREAK))
			inst[31:25] == 7'b0000000;
		else if(inst_type == MRET)
			inst[31:25] == 7'b0011000;
		else if((inst_type == SRAI) || (inst_type == SUB) || 
			(inst_type == SRA))
			inst[31:25] == 7'b0100000;
		else if(inst_type == FENCE)
			inst[31:25] == {4'b0000, pred[3:1]};
		else if((inst_type == CSRRW) || (inst_type == CSRRS) || 
			(inst_type == CSRRC) || (inst_type == CSRRWI) || 
			(inst_type == CSRRSI) || (inst_type == CSRRCI))
			inst[31:25] == csr_addr[11:5];
		else
			inst[31:25] == 7'b0000001;
	}
	
	virtual function void print();
		$display("-----------------RiscVInstTrans-----------------");
		
		$display("inst: %7.7b %5.5b %5.5b %3.3b %5.5b %7.7b", 
			inst[31:25], inst[24:20], inst[19:15], inst[14:12], inst[11:7], inst[6:0]);
		$display("inst_type: %s", risc_v_inst_type_to_string(this.inst_type));
		
		if((inst_type == LUI) || (inst_type == AUIPC))
			$display("imm: %d", $signed(imm & 32'hFFFF_F000));
		else if(inst_type == JAL)
			$display("imm: %d", $signed({{11{imm[20]}}, imm[20:0]}));
		else if((inst_type == BEQ) || (inst_type == BNE) || 
			(inst_type == BLT) || (inst_type == BGE) || 
			(inst_type == BLTU) || (inst_type == BGEU))
			$display("imm: %d", $signed({{19{imm[12]}}, imm[12:0]}));
		else if((inst_type == JALR) || 
			(inst_type == LB) || (inst_type == LH) || 
			(inst_type == LW) || (inst_type == LBU) || 
			(inst_type == LHU) || (inst_type == SB) || 
			(inst_type == SH) || (inst_type == SW) || 
			(inst_type == ADDI) || (inst_type == SLTI) || 
			(inst_type == SLTIU) || (inst_type == XORI) || 
			(inst_type == ORI) || (inst_type == ANDI))
			$display("imm: %d", $signed({{20{imm[11]}}, imm[11:0]}));
		
		if((inst_type != BEQ) && (inst_type != BNE) && 
			(inst_type != BLT) && (inst_type != BGE) && 
			(inst_type != BLTU) && (inst_type != BGEU) && 
			(inst_type != SB) && (inst_type != SH) && 
			(inst_type != SW) && (inst_type != FENCE) && 
			(inst_type != FENCE_I) && (inst_type != ECALL) && 
			(inst_type != EBREAK) && (inst_type != MRET))
			$display("rd: %d", rd);
		
		if((inst_type != LUI) && (inst_type != AUIPC) && 
			(inst_type != JAL) && (inst_type != FENCE) && 
			(inst_type != FENCE_I) && (inst_type != ECALL) && 
			(inst_type != EBREAK) && (inst_type != CSRRWI) && 
			(inst_type != CSRRSI) && (inst_type != CSRRCI) && 
			(inst_type != MRET))
			$display("rs1: %d", rs1);
		
		if((inst_type == BEQ) || (inst_type == BNE) || 
			(inst_type == BLT) || (inst_type == BGE) || 
			(inst_type == BLTU) || (inst_type == BGEU) || 
			(inst_type == SB) || (inst_type == SH) || 
			(inst_type == SW) || (inst_type == ADD) || 
			(inst_type == SUB) || (inst_type == SLL) || 
			(inst_type == SLT) || (inst_type == SLTU) || 
			(inst_type == XOR) || (inst_type == SRL) || 
			(inst_type == SRA) || (inst_type == OR) || 
			(inst_type == AND) || (inst_type == MUL) || 
			(inst_type == MULH) || (inst_type == MULHSU) || 
			(inst_type == MULHU) || (inst_type == DIV) || 
			(inst_type == DIVU) || (inst_type == REM) || 
			(inst_type == REMU))
			$display("rs2: %d", rs2);
		
		if((inst_type == CSRRW) || (inst_type == CSRRS) || 
			(inst_type == CSRRC) || (inst_type == CSRRWI) || 
			(inst_type == CSRRSI) || (inst_type == CSRRCI))
			$display("csr: %d", csr_addr);
		
		if((inst_type == CSRRWI) || (inst_type == CSRRSI) || (inst_type == CSRRCI))
			$display("zimm: %5.5b", zimm);
		
		if((inst_type == SLLI) || (inst_type == SRLI) || (inst_type == SRAI))
			$display("shamt: %d", shamt);
		
		if(inst_type == FENCE)
		begin
			$display("pred: %4.4b", pred);
			$display("succ: %4.4b", succ);
		end
		
		$display("------------------------------------------------");
	endfunction
	
	function void file_print(input integer fid);
		$fdisplay(fid, "-----------------RiscVInstTrans-----------------");
		
		$fdisplay(fid, "inst: %7.7b %5.5b %5.5b %3.3b %5.5b %7.7b", 
			inst[31:25], inst[24:20], inst[19:15], inst[14:12], inst[11:7], inst[6:0]);
		$fdisplay(fid, "inst_type: %s", risc_v_inst_type_to_string(this.inst_type));
		
		if((inst_type == LUI) || (inst_type == AUIPC))
			$fdisplay(fid, "imm: %d", $signed(imm & 32'hFFFF_F000));
		else if(inst_type == JAL)
			$fdisplay(fid, "imm: %d", $signed({{11{imm[20]}}, imm[20:0]}));
		else if((inst_type == BEQ) || (inst_type == BNE) || 
			(inst_type == BLT) || (inst_type == BGE) || 
			(inst_type == BLTU) || (inst_type == BGEU))
			$fdisplay(fid, "imm: %d", $signed({{19{imm[12]}}, imm[12:0]}));
		else if((inst_type == JALR) || 
			(inst_type == LB) || (inst_type == LH) || 
			(inst_type == LW) || (inst_type == LBU) || 
			(inst_type == LHU) || (inst_type == SB) || 
			(inst_type == SH) || (inst_type == SW) || 
			(inst_type == ADDI) || (inst_type == SLTI) || 
			(inst_type == SLTIU) || (inst_type == XORI) || 
			(inst_type == ORI) || (inst_type == ANDI))
			$fdisplay(fid, "imm: %d", $signed({{20{imm[11]}}, imm[11:0]}));
		
		if((inst_type != BEQ) && (inst_type != BNE) && 
			(inst_type != BLT) && (inst_type != BGE) && 
			(inst_type != BLTU) && (inst_type != BGEU) && 
			(inst_type != SB) && (inst_type != SH) && 
			(inst_type != SW) && (inst_type != FENCE) && 
			(inst_type != FENCE_I) && (inst_type != ECALL) && 
			(inst_type != EBREAK) && (inst_type != MRET))
			$fdisplay(fid, "rd: %d", rd);
		
		if((inst_type != LUI) && (inst_type != AUIPC) && 
			(inst_type != JAL) && (inst_type != FENCE) && 
			(inst_type != FENCE_I) && (inst_type != ECALL) && 
			(inst_type != EBREAK) && (inst_type != CSRRWI) && 
			(inst_type != CSRRSI) && (inst_type != CSRRCI) && 
			(inst_type != MRET))
			$fdisplay(fid, "rs1: %d", rs1);
		
		if((inst_type == BEQ) || (inst_type == BNE) || 
			(inst_type == BLT) || (inst_type == BGE) || 
			(inst_type == BLTU) || (inst_type == BGEU) || 
			(inst_type == SB) || (inst_type == SH) || 
			(inst_type == SW) || (inst_type == ADD) || 
			(inst_type == SUB) || (inst_type == SLL) || 
			(inst_type == SLT) || (inst_type == SLTU) || 
			(inst_type == XOR) || (inst_type == SRL) || 
			(inst_type == SRA) || (inst_type == OR) || 
			(inst_type == AND) || (inst_type == MUL) || 
			(inst_type == MULH) || (inst_type == MULHSU) || 
			(inst_type == MULHU) || (inst_type == DIV) || 
			(inst_type == DIVU) || (inst_type == REM) || 
			(inst_type == REMU))
			$fdisplay(fid, "rs2: %d", rs2);
		
		if((inst_type == CSRRW) || (inst_type == CSRRS) || 
			(inst_type == CSRRC) || (inst_type == CSRRWI) || 
			(inst_type == CSRRSI) || (inst_type == CSRRCI))
			$fdisplay(fid, "csr: %d", csr_addr);
		
		if((inst_type == CSRRWI) || (inst_type == CSRRSI) || (inst_type == CSRRCI))
			$fdisplay(fid, "zimm: %5.5b", zimm);
		
		if((inst_type == SLLI) || (inst_type == SRLI) || (inst_type == SRAI))
			$fdisplay(fid, "shamt: %d", shamt);
		
		if(inst_type == FENCE)
		begin
			$fdisplay(fid, "pred: %4.4b", pred);
			$fdisplay(fid, "succ: %4.4b", succ);
		end
		
		$fdisplay(fid, "------------------------------------------------");
	endfunction
	
	function static string risc_v_inst_type_to_string(input RiscVInstType inst_type);
		case(inst_type)
			LUI: return "LUI";
			AUIPC: return "AUIPC";
			JAL: return "JAL";
			JALR: return "JALR";
			BEQ: return "BEQ";
			BNE: return "BNE";
			BLT: return "BLT";
			BGE: return "BGE";
			BLTU: return "BLTU";
			BGEU: return "BGEU";
			LB: return "LB";
			LH: return "LH";
			LW: return "LW";
			LBU: return "LBU";
			LHU: return "LHU";
			SB: return "SB";
			SH: return "SH";
			SW: return "SW";
			ADDI: return "ADDI";
			SLTI: return "SLTI";
			SLTIU: return "SLTIU";
			XORI: return "XORI";
			ORI: return "ORI";
			ANDI: return "ANDI";
			SLLI: return "SLLI";
			SRLI: return "SRLI";
			SRAI: return "SRAI";
			ADD: return "ADD";
			SUB: return "SUB";
			SLL: return "SLL";
			SLT: return "SLT";
			SLTU: return "SLTU";
			XOR: return "XOR";
			SRL: return "SRL";
			SRA: return "SRA";
			OR: return "OR";
			AND: return "AND";
			MUL: return "MUL";
			MULH: return "MULH";
			MULHSU: return "MULHSU";
			MULHU: return "MULHU";
			DIV: return "DIV";
			DIVU: return "DIVU";
			REM: return "REM";
			REMU: return "REMU";
			FENCE: return "FENCE";
			FENCE_I: return "FENCE_I";
			ECALL: return "ECALL";
			EBREAK: return "EBREAK";
			CSRRW: return "CSRRW";
			CSRRS: return "CSRRS";
			CSRRC: return "CSRRC";
			CSRRWI: return "CSRRWI";
			CSRRSI: return "CSRRSI";
			CSRRCI: return "CSRRCI";
			MRET: return "MRET";
			default: return "UNKNOWN";
		endcase
	endfunction
	
endclass

`endif
