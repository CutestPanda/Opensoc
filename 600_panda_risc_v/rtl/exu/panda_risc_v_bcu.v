`timescale 1ns / 1ps
/********************************************************************
本模块: 分支确认单元

描述:
将实际的分支判定结果与预测的分支跳转进行比较, 在分支预测失败时产生冲刷请求

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/12/09
********************************************************************/


module panda_risc_v_bcu(
	// 分支确认输入
	input wire[31:0] s_bcu_brc_pc_upd, // 分支预测失败时修正的PC
	input wire s_bcu_prdt_jump, // 是否预测跳转
	input wire s_bcu_cfr_jump, // 是否确认跳转
	input wire s_bcu_valid, // 分支确认输入有效(指示)
	
	// 冲刷请求输出
	output wire flush_req_from_bcu, 
	output wire[31:0] flush_addr_from_bcu
);
	
	assign flush_req_from_bcu = 
		s_bcu_valid & 
		(s_bcu_prdt_jump ^ s_bcu_cfr_jump); // 分支预测失败时冲刷
	assign flush_addr_from_bcu = s_bcu_brc_pc_upd;
	
endmodule
