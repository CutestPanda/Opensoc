`timescale 1ns / 1ps
/********************************************************************
本模块: AXIS数据包统计(异步)

描述: 
统计AXIS接口上的数据包个数, 以实现AXIS数据fifo的数据包模式
有数据包或者fifo满时主机可以输出

注意：
由于写指针从写端口传递到读端口需要3clk，因此位于读端口的"有数据包"从无效到有效是滞后的
由于满标志从写端口传递到读端口需要2clk，因此位于读端口的"fifo满"无论是从无效到有效还是从有效到无效都是滞后的

协议:
无

作者: 陈家耀
日期: 2024/09/17
********************************************************************/


module axis_packet_stat_async #(
	parameter fifo_depth = 32, // fifo深度(必须为16|32|64|128...)
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 从机时钟和复位
	input wire s_axis_aclk,
	input wire s_axis_aresetn,
	// 主机时钟和复位
	input wire m_axis_aclk,
	input wire m_axis_aresetn,
	
	// AXIS从机
	input wire s_axis_last,
	input wire s_axis_valid,
	input wire s_axis_ready,
	
	// AXIS主机
	input wire m_axis_last,
	input wire m_axis_valid,
	input wire m_axis_ready,
	
	// 主机输出使能
	output wire master_oen
);
	
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
        for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
			bit_depth = bit_depth >> 1;
    end
    endfunction
	
	/** 常量 **/
	localparam integer pkt_ptr_width = clogb2(fifo_depth-1) + 2; // 数据包指针位宽
	
	/** 写端口(AXIS从机) **/
	reg[pkt_ptr_width-1:0] wptr_bin_at_w; // 位于写端口的写指针(二进制码)
	wire[pkt_ptr_width-1:0] wptr_gray_at_w_cvt_cmb; // 位于写端口的写指针的格雷码转换组合逻辑
	reg[pkt_ptr_width-1:0] wptr_gray_at_w; // 位于写端口的写指针(格雷码)
	
	assign wptr_gray_at_w_cvt_cmb = {1'b0, wptr_bin_at_w[pkt_ptr_width-1:1]} ^ wptr_bin_at_w;
	
	// 位于写端口的写指针(二进制码)
    always @(posedge s_axis_aclk or negedge s_axis_aresetn)
    begin
        if(~s_axis_aresetn)
            wptr_bin_at_w <= 0;
        else if(s_axis_valid & s_axis_ready & s_axis_last)
            wptr_bin_at_w <= # simulation_delay wptr_bin_at_w + 1;
    end
	
	// 位于写端口的写指针(格雷码)
    always @(posedge s_axis_aclk or negedge s_axis_aresetn)
    begin
        if(~s_axis_aresetn)
            wptr_gray_at_w <= 0;
        else
            wptr_gray_at_w <= # simulation_delay wptr_gray_at_w_cvt_cmb;
    end
	
	/** 读端口(AXIS主机) **/
	wire[pkt_ptr_width-1:0] wptr_gray_at_r; // 位于读端口的写指针(格雷码)
	reg[pkt_ptr_width-1:0] rptr_bin_at_r; // 位于读端口的读指针(二进制码)
    reg[pkt_ptr_width-1:0] rptr_add1_bin_at_r; // 位于读端口的读指针+1(二进制码)
	wire[pkt_ptr_width-1:0] rptr_gray_at_r_cvt_cmb; // 位于读端口的读指针的格雷码转换组合逻辑
    wire[pkt_ptr_width-1:0] rptr_add1_gray_at_r_cvt_cmb; // 位于读端口的读指针+1的格雷码转换组合逻辑
	reg no_packet; // 没有数据包(标志)
	reg full_at_r; // 位于读端口的满标志
	
	assign master_oen = (~no_packet) | full_at_r; // 有数据包或者fifo满
	
	assign rptr_gray_at_r_cvt_cmb = {1'b0, rptr_bin_at_r[pkt_ptr_width-1:1]} ^ rptr_bin_at_r;
    assign rptr_add1_gray_at_r_cvt_cmb = {1'b0, rptr_add1_bin_at_r[pkt_ptr_width-1:1]} ^ rptr_add1_bin_at_r;
	
	// 位于读端口的读指针(二进制码)
    always @(posedge m_axis_aclk or negedge m_axis_aresetn)
    begin
        if(~m_axis_aresetn)
            rptr_bin_at_r <= 0;
        else if(m_axis_valid & m_axis_ready & m_axis_last)
            rptr_bin_at_r <= # simulation_delay rptr_bin_at_r + 1;
    end
    // 位于读端口的读指针+1(二进制码)
    always @(posedge m_axis_aclk or negedge m_axis_aresetn)
    begin
        if(~m_axis_aresetn)
            rptr_add1_bin_at_r <= 1;
        else if(m_axis_valid & m_axis_ready & m_axis_last)
            rptr_add1_bin_at_r <= # simulation_delay rptr_add1_bin_at_r + 1;
    end
	
	// 没有数据包(标志)
	always @(posedge m_axis_aclk or negedge m_axis_aresetn)
    begin
        if(~m_axis_aresetn)
            no_packet <= 1'b1;
        else
			// 读指针格雷码 == 写指针格雷码时空
            no_packet <= # simulation_delay ((m_axis_valid & m_axis_ready & m_axis_last) ? 
				rptr_add1_gray_at_r_cvt_cmb:rptr_gray_at_r_cvt_cmb) == wptr_gray_at_r;
    end
	
	/** 写指针同步 **/
	// 同步到读端口的写指针(格雷码)
	reg[pkt_ptr_width-1:0] wptr_gray_at_w_d;
	reg[pkt_ptr_width-1:0] wptr_gray_at_w_d2;
	
	assign wptr_gray_at_r = wptr_gray_at_w_d2;
	
	// 同步到读端口的写指针(格雷码)
	// 跨时钟域：wptr_gray_at_w -> wptr_gray_at_w_d!
	always @(posedge m_axis_aclk or negedge m_axis_aresetn)
	begin
		if(~m_axis_aresetn)
			{wptr_gray_at_w_d2, wptr_gray_at_w_d} <= {(2*pkt_ptr_width){1'b0}};
		else
			{wptr_gray_at_w_d2, wptr_gray_at_w_d} <= # simulation_delay {wptr_gray_at_w_d, wptr_gray_at_w};
	end
	
	/** 满标志同步 **/
	// 同步到读端口的满标志
	reg full_d;
	reg full_d2;
	
	// 同步到读端口的满标志
	// 跨时钟域：... -> full_d!
	always @(posedge m_axis_aclk or negedge m_axis_aresetn)
	begin
		if(~m_axis_aresetn)
			{full_d2, full_d} <= 2'b00;
		else
			{full_d2, full_d} <= # simulation_delay {full_d, ~s_axis_ready};
	end
	
	// 位于读端口的满标志
	always @(posedge m_axis_aclk or negedge m_axis_aresetn)
	begin
		if(~m_axis_aresetn)
			full_at_r <= 1'b0;
		else
			full_at_r <= # simulation_delay full_at_r ? ~(m_axis_valid & m_axis_ready & (~full_d2)):full_d2;
	end
	
endmodule
