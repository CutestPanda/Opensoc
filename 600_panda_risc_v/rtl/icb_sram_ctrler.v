`timescale 1ns / 1ps
/********************************************************************
本模块: ICB-SRAM控制器

描述:
带ICB从接口的SRAM控制器
32位ICB总线
支持非对齐传输

注意：
SRAM存储器主接口仅支持读时延为1clk

协议:
ICB SLAVE
MEM MASTER

作者: 陈家耀
日期: 2024/10/14
********************************************************************/


module icb_sram_ctrler #(
	parameter en_unaligned_transfer = "true", // 是否允许非对齐传输
	parameter wt_trans_imdt_resp = "false", // 是否允许写传输立即响应
    parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire s_icb_aclk,
	input wire s_icb_aresetn,
	
	// ICB从机
	// 命令通道
	input wire[31:0] s_icb_cmd_addr,
	input wire s_icb_cmd_read,
	input wire[31:0] s_icb_cmd_wdata,
	input wire[3:0] s_icb_cmd_wmask,
	input wire s_icb_cmd_valid,
	output wire s_icb_cmd_ready,
	// 响应通道
	output wire[31:0] s_icb_rsp_rdata,
	output wire s_icb_rsp_err, // const -> 1'b0
	output wire s_icb_rsp_valid,
	input wire s_icb_rsp_ready,
	
	// SRAM存储器主接口
	output wire bram_clk,
    output wire bram_rst,
    output wire bram_en,
    output wire[3:0] bram_wen,
    output wire[29:0] bram_addr,
    output wire[31:0] bram_din,
    input wire[31:0] bram_dout
);
	
	/** SRAM存储器主接口时钟和复位 **/
	assign bram_clk = s_icb_aclk;
	assign bram_rst = ~s_icb_aresetn;
	
	/** ICB从机命令通道 **/
	reg bram_rw_pending; // BRAM读写传输进行中(标志)
	wire on_start_bram_rw; // 启动BRAM读写传输(指示)
	wire on_finish_bram_rw; // BRAM读写传输完成(指示)
	
	assign s_icb_cmd_ready = (~bram_rw_pending) | on_finish_bram_rw;
	
	assign bram_en = on_start_bram_rw;
	assign bram_wen = {4{~s_icb_cmd_read}} & s_icb_cmd_wmask & 
		((en_unaligned_transfer == "false") | 
		({4{s_icb_cmd_addr[1:0] == 2'b00}} & 4'b1111) | 
		({4{s_icb_cmd_addr[1:0] == 2'b01}} & 4'b1110) | 
		({4{s_icb_cmd_addr[1:0] == 2'b10}} & 4'b1100) | 
		({4{s_icb_cmd_addr[1:0] == 2'b11}} & 4'b1000));
	assign bram_addr = s_icb_cmd_addr[31:2];
	assign bram_din = s_icb_cmd_wdata;
	
	assign on_start_bram_rw = s_icb_cmd_valid & s_icb_cmd_ready;
	
	// BRAM读写传输进行中(标志)
	always @(posedge s_icb_aclk or negedge s_icb_aresetn)
	begin
		if(~s_icb_aresetn)
			bram_rw_pending <= 1'b0;
		else if(on_start_bram_rw ^ on_finish_bram_rw)
			bram_rw_pending <= #simulation_delay on_start_bram_rw;
	end
	
	/** ICB从机响应通道 **/
	assign s_icb_rsp_rdata = bram_dout;
	assign s_icb_rsp_err = 1'b0;
	assign s_icb_rsp_valid = bram_rw_pending 
		| ((wt_trans_imdt_resp == "true") & s_icb_cmd_valid & (~s_icb_cmd_read)); // 写传输的响应在本clk立即给出
	
	assign on_finish_bram_rw = s_icb_rsp_valid & s_icb_rsp_ready;
	
endmodule
