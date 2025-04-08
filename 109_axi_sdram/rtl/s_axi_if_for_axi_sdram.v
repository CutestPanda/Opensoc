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
本模块: SDRAM控制器的AXI从接口

描述: 
地址位宽 = 32位, 数据位宽 = 8/16/32/64位
支持非对齐传输

注意：
仅支持INCR突发类型
不支持窄带传输

协议:
AXI SLAVE
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/04/06
********************************************************************/


module s_axi_if_for_axi_sdram #(
	parameter integer DATA_WIDTH = 32, // 数据位宽(8 | 16 | 32 | 64)
	parameter integer SDRAM_COL_N = 256, // sdram列数(128 | 256 | 512 | 1024)
	parameter integer SDRAM_ROW_N = 8192, // sdram行数(1024 | 2048 | 4096 | 8192 | 16384)
    parameter EN_UNALIGNED_TRANSFER = "false", // 是否允许非对齐传输
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // AXI从机
    // AR
    input wire[31:0] s_axi_araddr,
    input wire[7:0] s_axi_arlen,
    input wire[2:0] s_axi_arsize, // 必须是clogb2(DATA_WIDTH/8)
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    // R
    output wire[DATA_WIDTH-1:0] s_axi_rdata,
    output wire s_axi_rlast,
    output wire[1:0] s_axi_rresp, // const -> 2'b00
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    // AW
    input wire[31:0] s_axi_awaddr,
    input wire[7:0] s_axi_awlen,
    input wire[2:0] s_axi_awsize, // 必须是clogb2(DATA_WIDTH/8)
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    // W
    input wire[DATA_WIDTH-1:0] s_axi_wdata,
    input wire[DATA_WIDTH/8-1:0] s_axi_wstrb,
    input wire s_axi_wlast,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    // B
    output wire[1:0] s_axi_bresp, // const -> 2'b00
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    
    // SDRAM用户命令AXIS
    output wire[39:0] m_axis_usr_cmd_data, // {保留(3bit), ba(2bit), 行地址(16bit), A15-0(16bit), 命令号(3bit)}
    output wire[16:0] m_axis_usr_cmd_user, // {是否自动添加"停止突发"命令(1bit), 突发长度 - 1(16bit)}(仅对全页突发有效)
    output wire m_axis_usr_cmd_valid,
    input wire m_axis_usr_cmd_ready,
    // SDRAM写数据AXIS
    output wire[DATA_WIDTH-1:0] m_axis_wt_data,
    output wire[DATA_WIDTH/8-1:0] m_axis_wt_keep,
    output wire m_axis_wt_last,
    output wire m_axis_wt_valid,
    input wire m_axis_wt_ready,
    // SDRAM读数据AXIS
    input wire[DATA_WIDTH-1:0] s_axis_rd_data,
    input wire s_axis_rd_last,
    input wire s_axis_rd_valid,
    output wire s_axis_rd_ready
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
	
    /** 常量 **/
	// 突发边界(以字节计)
    localparam integer BURST_BD = 
		((SDRAM_COL_N*DATA_WIDTH/8) > 4096) ? 
			4096:
			(SDRAM_COL_N*DATA_WIDTH/8);
	// sdram命令的逻辑编码
    localparam CMD_LOGI_WT_DATA = 3'b010; // 命令:写数据
    localparam CMD_LOGI_RD_DATA = 3'b011; // 命令:读数据
	
	/** 仿真 **/
	/*
	generate
		if(SIM_DELAY != 0)
		begin
			always @(posedge clk)
			begin
				if(m_axis_usr_cmd_valid & m_axis_usr_cmd_ready)
				begin
					$display("**** m_axis_usr_cmd ****");
					$display("ba = %d", m_axis_usr_cmd_data[36:35]);
					$display("row_addr = %d", m_axis_usr_cmd_data[34:19]);
					$display("col_addr = %d", m_axis_usr_cmd_data[18:3]);
					if(m_axis_usr_cmd_data[2:0] == CMD_LOGI_WT_DATA)
						$display("wt_data");
					else
						$display("rd_data");
					$display("burst_len = %d", m_axis_usr_cmd_user[15:0] + 1);
					$display("************************");
				end
			end
		end
	endgenerate
	*/
	
	/** AXI从机的写响应通道 **/
	wire send_bresp; // 发送写响应(指示)
	wire accept_bresp; // 接受写响应(指示)
	reg[1:0] bresp_n_to_accept; // 等待接受的写响应数量
	
	assign s_axi_bresp = 2'b00;
	assign s_axi_bvalid = bresp_n_to_accept != 2'd0;
	
	assign accept_bresp = s_axi_bvalid & s_axi_bready;
	
	// 等待接受的写响应数量
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			bresp_n_to_accept <= 2'b00;
		else if(send_bresp ^ accept_bresp)
			// accept_bresp ? (bresp_n_to_accept - 2'b01):(bresp_n_to_accept + 2'b01)
			bresp_n_to_accept <= # SIM_DELAY bresp_n_to_accept + {accept_bresp, 1'b1};
	end
	
	/**
	写数据包划分
	
	根据sdram写突发信息fifo提供的写突发长度, 重新生成SDRAM写数据AXIS的last信号
	根据sdram写突发信息fifo提供的首地址的低3位, 处理非对齐的写突发, 重新生成SDRAM写数据AXIS的keep信号
	**/
	// fifo写端口
	wire sdram_wt_burst_msg_fifo_wen;
	wire[11:0] sdram_wt_burst_msg_fifo_din; // {是否划分的最后1次写突发(1bit), 突发长度 - 1(8bit), 首地址的低3位(3bit)}
	wire sdram_wt_burst_msg_fifo_full_n;
	// fifo读端口
	wire sdram_wt_burst_msg_fifo_ren;
	wire[11:0] sdram_wt_burst_msg_fifo_dout; // {是否划分的最后1次写突发(1bit), 突发长度 - 1(8bit), 首地址的低3位(3bit)}
	wire sdram_wt_burst_msg_fifo_empty_n;
	// 写数据包划分
	reg[7:0] sdram_wburst_cnt; // sdram写突发传输计数器
	wire sdram_last_wtrans; // sdram写突发最后1次传输(标志)
	wire[DATA_WIDTH/8-1:0] sdram_first_wtrans_bmsk; // sdram写突发第1次传输的字节掩码
	
	/*
	握手条件: 
		s_axi_wvalid & sdram_wt_burst_msg_fifo_empty_n & m_axis_wt_ready & 
		((~(sdram_last_wtrans & sdram_wt_burst_msg_fifo_dout[11])) | (bresp_n_to_accept < 2'd2))
	*/
	assign s_axi_wready = 
		sdram_wt_burst_msg_fifo_empty_n & m_axis_wt_ready & 
		((~(sdram_last_wtrans & sdram_wt_burst_msg_fifo_dout[11])) | (bresp_n_to_accept < 2'd2));
	
	assign m_axis_wt_data = s_axi_wdata;
	assign m_axis_wt_keep = 
		s_axi_wstrb & (
			((EN_UNALIGNED_TRANSFER == "true") & (sdram_wburst_cnt == 8'h00)) ? 
				sdram_first_wtrans_bmsk:
				{(DATA_WIDTH/8){1'b1}}
		);
	assign m_axis_wt_last = sdram_last_wtrans;
	/*
	握手条件: 
		s_axi_wvalid & sdram_wt_burst_msg_fifo_empty_n & m_axis_wt_ready & 
		((~(sdram_last_wtrans & sdram_wt_burst_msg_fifo_dout[11])) | (bresp_n_to_accept < 2'd2))
	*/
	assign m_axis_wt_valid = 
		s_axi_wvalid & sdram_wt_burst_msg_fifo_empty_n & 
		((~(sdram_last_wtrans & sdram_wt_burst_msg_fifo_dout[11])) | (bresp_n_to_accept < 2'd2));
	
	assign send_bresp = m_axis_wt_valid & m_axis_wt_ready & sdram_last_wtrans & sdram_wt_burst_msg_fifo_dout[11];
	
	/*
	握手条件: 
		s_axi_wvalid & sdram_wt_burst_msg_fifo_empty_n & m_axis_wt_ready & sdram_last_wtrans & 
		((~sdram_wt_burst_msg_fifo_dout[11]) | (bresp_n_to_accept < 2'd2))
	*/
	assign sdram_wt_burst_msg_fifo_ren = 
		s_axi_wvalid & m_axis_wt_ready & sdram_last_wtrans & 
		((~sdram_wt_burst_msg_fifo_dout[11]) | (bresp_n_to_accept < 2'd2));
	
	assign sdram_last_wtrans = sdram_wburst_cnt == sdram_wt_burst_msg_fifo_dout[10:3];
	assign sdram_first_wtrans_bmsk = 
		(DATA_WIDTH == 8)  ? 1'b1:
		(DATA_WIDTH == 16) ? (
			sdram_wt_burst_msg_fifo_dout[0] ? 2'b10:
			                                  2'b11
		):
		(DATA_WIDTH == 32) ? (
			(sdram_wt_burst_msg_fifo_dout[1:0] == 2'b00) ? 4'b1111:
			(sdram_wt_burst_msg_fifo_dout[1:0] == 2'b01) ? 4'b1110:
			(sdram_wt_burst_msg_fifo_dout[1:0] == 2'b10) ? 4'b1100:
			                                               4'b1000
		):
		(
			(sdram_wt_burst_msg_fifo_dout[2:0] == 3'b000) ? 8'b1111_1111:
			(sdram_wt_burst_msg_fifo_dout[2:0] == 3'b001) ? 8'b1111_1110:
			(sdram_wt_burst_msg_fifo_dout[2:0] == 3'b010) ? 8'b1111_1100:
			(sdram_wt_burst_msg_fifo_dout[2:0] == 3'b011) ? 8'b1111_1000:
			(sdram_wt_burst_msg_fifo_dout[2:0] == 3'b100) ? 8'b1111_0000:
			(sdram_wt_burst_msg_fifo_dout[2:0] == 3'b101) ? 8'b1110_0000:
			(sdram_wt_burst_msg_fifo_dout[2:0] == 3'b110) ? 8'b1100_0000:
			                                                8'b1000_0000
		);
	
	// sdram写突发传输计数器
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			sdram_wburst_cnt <= 8'h00;
		else if(m_axis_wt_valid & m_axis_wt_ready)
			sdram_wburst_cnt <= # SIM_DELAY 
				sdram_last_wtrans ? 
					8'h00:
					(sdram_wburst_cnt + 8'd1);
	end
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("true"),
		.fifo_depth(4),
		.fifo_data_width(12),
		.almost_full_th(2),
		.almost_empty_th(2),
		.simulation_delay(SIM_DELAY)
	)sdram_wt_burst_msg_fifo_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.fifo_wen(sdram_wt_burst_msg_fifo_wen),
		.fifo_din(sdram_wt_burst_msg_fifo_din),
		.fifo_full_n(sdram_wt_burst_msg_fifo_full_n),
		
		.fifo_ren(sdram_wt_burst_msg_fifo_ren),
		.fifo_dout(sdram_wt_burst_msg_fifo_dout),
		.fifo_empty_n(sdram_wt_burst_msg_fifo_empty_n)
	);
	
	/**
	AXI读数据通道
	
	根据AXI读事务的总突发长度, 重新生成AXI从机读数据通道的last信号
	**/
	// fifo写端口
	wire axi_rd_trans_msg_fifo_wen;
	wire[7:0] axi_rd_trans_msg_fifo_din; // {突发长度 - 1(8bit)}
	wire axi_rd_trans_msg_fifo_full_n;
	// fifo读端口
	wire axi_rd_trans_msg_fifo_ren;
	wire[7:0] axi_rd_trans_msg_fifo_dout; // {突发长度 - 1(8bit)}
	wire axi_rd_trans_msg_fifo_empty_n;
	// 读传输计数
	reg[7:0] axi_rburst_cnt; // AXI读事务传输计数器
	wire axi_last_rtrans; // AXI读事务最后1次传输(标志)
	
	assign s_axi_rdata = s_axis_rd_data;
	assign s_axi_rlast = axi_last_rtrans;
	assign s_axi_rresp = 2'b00;
	/*
	握手条件: 
		s_axis_rd_valid & s_axi_rready & axi_rd_trans_msg_fifo_empty_n
	*/
	assign s_axi_rvalid = s_axis_rd_valid & axi_rd_trans_msg_fifo_empty_n;
	
	/*
	握手条件: 
		s_axis_rd_valid & s_axi_rready & axi_rd_trans_msg_fifo_empty_n
	*/
	assign s_axis_rd_ready = s_axi_rready & axi_rd_trans_msg_fifo_empty_n;
	
	/*
	握手条件: 
		s_axis_rd_valid & s_axi_rready & axi_rd_trans_msg_fifo_empty_n & axi_last_rtrans
	*/
	assign axi_rd_trans_msg_fifo_ren = s_axis_rd_valid & s_axi_rready & axi_last_rtrans;
	assign axi_last_rtrans = axi_rburst_cnt == axi_rd_trans_msg_fifo_dout;
	
	// AXI读事务传输计数器
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			axi_rburst_cnt <= 8'h00;
		else if(s_axis_rd_valid & s_axis_rd_ready)
			axi_rburst_cnt <= # SIM_DELAY 
				axi_last_rtrans ? 
					8'h00:
					(axi_rburst_cnt + 8'd1);
	end
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(4),
		.fifo_data_width(8),
		.almost_full_th(2),
		.almost_empty_th(2),
		.simulation_delay(SIM_DELAY)
	)axi_rd_trans_msg_fifo_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.fifo_wen(axi_rd_trans_msg_fifo_wen),
		.fifo_din(axi_rd_trans_msg_fifo_din),
		.fifo_full_n(axi_rd_trans_msg_fifo_full_n),
		
		.fifo_ren(axi_rd_trans_msg_fifo_ren),
		.fifo_dout(axi_rd_trans_msg_fifo_dout),
		.fifo_empty_n(axi_rd_trans_msg_fifo_empty_n)
	);
	
	/**
	AXI侧事务信息fifo
	
	对AXI从机的AR/AW通道进行读写仲裁, 将事务信息存入fifo
	**/
	// fifo写端口
	wire axi_trans_msg_fifo_wen;
	wire[40:0] axi_trans_msg_fifo_din; // {是否读事务(1bit), 突发长度 - 1(8bit), 首地址(32bit)}
	wire axi_trans_msg_fifo_full_n;
	// fifo读端口
	wire axi_trans_msg_fifo_ren;
	wire[40:0] axi_trans_msg_fifo_dout; // {是否读事务(1bit), 突发长度 - 1(8bit), 首地址(32bit)}
	wire axi_trans_msg_fifo_empty_n;
	// 读写仲裁
	wire axi_rd_req;
	wire axi_wt_req;
	wire axi_rd_grant;
	wire axi_wt_grant;
	
	assign s_axi_arready = axi_rd_grant;
	assign s_axi_awready = axi_wt_grant;
	
	assign axi_rd_trans_msg_fifo_wen = s_axi_arvalid & s_axi_arready;
	assign axi_rd_trans_msg_fifo_din = s_axi_arlen;
	
	assign axi_trans_msg_fifo_wen = (s_axi_arvalid & axi_rd_trans_msg_fifo_full_n) | s_axi_awvalid;
	assign axi_trans_msg_fifo_din = 
		axi_rd_grant ? 
			{1'b1, s_axi_arlen, s_axi_araddr}:
			{1'b0, s_axi_awlen, s_axi_awaddr};
	
	assign axi_rd_req = s_axi_arvalid & axi_trans_msg_fifo_full_n & axi_rd_trans_msg_fifo_full_n;
	assign axi_wt_req = s_axi_awvalid & axi_trans_msg_fifo_full_n;
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(2),
		.fifo_data_width(41),
		.almost_full_th(1),
		.almost_empty_th(1),
		.simulation_delay(SIM_DELAY)
	)axi_trans_msg_fifo_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.fifo_wen(axi_trans_msg_fifo_wen),
		.fifo_din(axi_trans_msg_fifo_din),
		.fifo_full_n(axi_trans_msg_fifo_full_n),
		
		.fifo_ren(axi_trans_msg_fifo_ren),
		.fifo_dout(axi_trans_msg_fifo_dout),
		.fifo_empty_n(axi_trans_msg_fifo_empty_n)
	);
	
	round_robin_arbitrator #(
		.chn_n(2),
		.simulation_delay(SIM_DELAY)
	)axi_rw_arb_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.req({axi_rd_req, axi_wt_req}),
		.grant({axi_rd_grant, axi_wt_grant})
	);
	
	/**
	突发划分
	
	根据突发边界, 将AXI侧读/写事务划分成若干次sdram读/写突发, 
	将每个sdram写突发的长度和首地址的低3位存入sdram写突发信息fifo
	**/
	reg splitting_burst; // 正在进行突发划分(标志)
	reg[31:0] burst_baseaddr; // 突发首地址
	reg[7:0] burst_n_rmn; // 剩余的突发次数 - 1
	reg is_rd_burst; // 是否读突发(标志)
	wire[31:0] burst_baseaddr_cur; // 当前的突发首地址
	wire[7:0] burst_n_rmn_cur; // 当前的(剩余的突发次数 - 1)
	wire is_rd_burst_cur; // 当前的是否读突发(标志)
	wire[12:0] burst_endaddr_cur; // 当前的突发结束地址
	wire crossing_burst_bd; // 跨越突发边界(标志)
	wire last_burst; // 读/写事务内的最后一次突发(标志)
	wire[7:0] burst_n_now; // 本次突发的长度 - 1
	
	// 保留位
	assign m_axis_usr_cmd_data[39:37] = 3'bxxx;
	// ba
	assign m_axis_usr_cmd_data[36:35] = 
		burst_baseaddr_cur[clogb2(SDRAM_ROW_N*SDRAM_COL_N*DATA_WIDTH/8)+1:clogb2(SDRAM_ROW_N*SDRAM_COL_N*DATA_WIDTH/8)];
	// 行地址
	assign m_axis_usr_cmd_data[34:19] = 
		burst_baseaddr_cur[clogb2(SDRAM_ROW_N*SDRAM_COL_N*DATA_WIDTH/8-1):clogb2(SDRAM_COL_N*DATA_WIDTH/8)] | 16'h0000;
	// A15-0
	assign m_axis_usr_cmd_data[18:3] = 
		burst_baseaddr_cur[clogb2(SDRAM_COL_N*DATA_WIDTH/8-1):clogb2(DATA_WIDTH/8)] | 16'h0000;
	// 命令号
	assign m_axis_usr_cmd_data[2:0] = 
		is_rd_burst_cur ? 
			CMD_LOGI_RD_DATA:
			CMD_LOGI_WT_DATA;
	
	// 自动添加"停止突发"命令
	assign m_axis_usr_cmd_user[16] = 1'b1;
	// 突发长度 - 1
	assign m_axis_usr_cmd_user[15:0] = burst_n_now | 16'h0000;
	
	/*
	握手条件: 
		(splitting_burst | axi_trans_msg_fifo_empty_n) & 
		(is_rd_burst_cur | sdram_wt_burst_msg_fifo_full_n) & 
		m_axis_usr_cmd_ready
	*/
	assign m_axis_usr_cmd_valid = 	
		(splitting_burst | axi_trans_msg_fifo_empty_n) & 
		(is_rd_burst_cur | sdram_wt_burst_msg_fifo_full_n);
	
	/*
	握手条件: 
		((~splitting_burst) & axi_trans_msg_fifo_empty_n) & 
		(is_rd_burst_cur | sdram_wt_burst_msg_fifo_full_n) & 
		m_axis_usr_cmd_ready
	*/
	assign axi_trans_msg_fifo_ren = 
		(~splitting_burst) & m_axis_usr_cmd_ready & 
		(is_rd_burst_cur | sdram_wt_burst_msg_fifo_full_n);
	
	/*
	握手条件: 
		(splitting_burst | axi_trans_msg_fifo_empty_n) & 
		((~is_rd_burst_cur) & sdram_wt_burst_msg_fifo_full_n) & 
		m_axis_usr_cmd_ready
	*/
	assign sdram_wt_burst_msg_fifo_wen = 
		(splitting_burst | axi_trans_msg_fifo_empty_n) & 
		(~is_rd_burst_cur) & 
		m_axis_usr_cmd_ready;
	// 是否划分的最后1次写突发
	assign sdram_wt_burst_msg_fifo_din[11] = last_burst;
	// 突发长度 - 1
	assign sdram_wt_burst_msg_fifo_din[10:3] = burst_n_now;
	// 首地址的低3位
	assign sdram_wt_burst_msg_fifo_din[2:0] = burst_baseaddr_cur[2:0];
	
	assign burst_baseaddr_cur = 
		splitting_burst ? 
			burst_baseaddr:
			axi_trans_msg_fifo_dout[31:0];
	assign burst_n_rmn_cur = 
		splitting_burst ? 
			burst_n_rmn:
			axi_trans_msg_fifo_dout[39:32];
	assign is_rd_burst_cur = 
		splitting_burst ? 
			is_rd_burst:
			axi_trans_msg_fifo_dout[40];
	
	assign burst_endaddr_cur = 
		(
			(burst_baseaddr_cur[clogb2(BURST_BD-1):clogb2(DATA_WIDTH/8)] | 13'd0) + 
			(burst_n_rmn_cur | 13'd0) + 
			13'd1
		) * (DATA_WIDTH/8);
	assign crossing_burst_bd = burst_endaddr_cur > BURST_BD;
	assign last_burst = ~crossing_burst_bd;
	assign burst_n_now = 
		last_burst ? 
			burst_n_rmn_cur:
			((BURST_BD/(DATA_WIDTH/8)-1) - burst_baseaddr_cur[clogb2(BURST_BD-1):clogb2(DATA_WIDTH/8)]);
	
	// 正在进行突发划分(标志)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			splitting_burst <= 1'b0;
		else if(
			(is_rd_burst_cur | sdram_wt_burst_msg_fifo_full_n) & m_axis_usr_cmd_ready & 
			(
				splitting_burst ? 
					last_burst:
					((~last_burst) & axi_trans_msg_fifo_empty_n)
			)
		)
			splitting_burst <= # SIM_DELAY ~splitting_burst;
	end
	
	// 突发首地址
	always @(posedge clk)
	begin
		if(
			(~last_burst) & (is_rd_burst_cur | sdram_wt_burst_msg_fifo_full_n) & m_axis_usr_cmd_ready & 
			(splitting_burst | axi_trans_msg_fifo_empty_n)
		)
			burst_baseaddr <= # SIM_DELAY 
				// burst_baseaddr_cur[31:clogb2(DATA_WIDTH/8)] * (DATA_WIDTH / 8) + (burst_n_now + 1) * (DATA_WIDTH / 8)
				(burst_baseaddr_cur[31:clogb2(DATA_WIDTH/8)] * (DATA_WIDTH/8)) + 
				(((BURST_BD/(DATA_WIDTH/8)) - burst_baseaddr_cur[clogb2(BURST_BD-1):clogb2(DATA_WIDTH/8)]) * (DATA_WIDTH/8));
	end
	
	// 剩余的突发次数 - 1
	always @(posedge clk)
	begin
		if(
			(~last_burst) & (is_rd_burst_cur | sdram_wt_burst_msg_fifo_full_n) & m_axis_usr_cmd_ready & 
			(splitting_burst | axi_trans_msg_fifo_empty_n)
		)
			burst_n_rmn <= # SIM_DELAY 
				// burst_n_rmn_cur - (burst_n_now + 1)
				burst_n_rmn_cur - ((BURST_BD/(DATA_WIDTH/8)) - burst_baseaddr_cur[clogb2(BURST_BD-1):clogb2(DATA_WIDTH/8)]);
	end
	
	// 是否读突发(标志)
	always @(posedge clk)
	begin
		if(
			(~last_burst) & (is_rd_burst_cur | sdram_wt_burst_msg_fifo_full_n) & m_axis_usr_cmd_ready & 
			((~splitting_burst) & axi_trans_msg_fifo_empty_n)
		)
			is_rd_burst <= # SIM_DELAY axi_trans_msg_fifo_dout[40];
	end
	
endmodule
