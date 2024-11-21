`timescale 1ns / 1ps
/********************************************************************
本模块: 指令总线控制单元

描述:
接收指令存储器访问请求, 返回读数据和错误类型
对于ICB主机, 仅允许2个滞外传输(outstanding)

注意：
PC地址非对齐时不发起ICB传输, 且允许在没有处理中的传输时立即返回应答
若发生指令总线响应超时, 则不再接受新的指令存储器访问请求, 指令ICB主机停止传输

协议:
ICB MASTER

作者: 陈家耀
日期: 2024/10/14
********************************************************************/


module panda_risc_v_ibus_ctrler #(
	parameter integer imem_access_timeout_th = 16, // 指令总线访问超时周期数(必须>=1)
	parameter integer inst_addr_alignment_width = 32, // 指令地址对齐位宽(16 | 32)
	parameter pc_unaligned_imdt_resp = "false", // 是否允许PC地址非对齐时立即响应
    parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// 指令存储器访问请求
	input wire[31:0] imem_access_req_addr,
	input wire imem_access_req_read,
	input wire[31:0] imem_access_req_wdata,
	input wire[3:0] imem_access_req_wmask,
	input wire imem_access_req_valid,
	output wire imem_access_req_ready,
	// 指令存储器访问应答
	output wire[31:0] imem_access_resp_rdata,
	output wire[1:0] imem_access_resp_err, // 错误类型(2'b00 -> 正常, 2'b01 -> 指令地址非对齐, 
										   //          2'b10 -> 指令总线访问错误, 2'b11 -> 响应超时)
	output wire imem_access_resp_valid,
    
    // 指令ICB主机
	// 命令通道
	output wire[31:0] m_icb_cmd_addr,
	output wire m_icb_cmd_read,
	output wire[31:0] m_icb_cmd_wdata,
	output wire[3:0] m_icb_cmd_wmask,
	output wire m_icb_cmd_valid,
	input wire m_icb_cmd_ready,
	// 响应通道
	input wire[31:0] m_icb_rsp_rdata,
	input wire m_icb_rsp_err,
	input wire m_icb_rsp_valid,
	output wire m_icb_rsp_ready,
	
	// 指令总线访问超时标志
	output wire ibus_timeout
);
	
    // 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
        for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
			bit_depth = bit_depth >> 1;
    end
    endfunction
	
	/** 常量 **/
	// 指令存储器访问应答错误类型
	localparam IMEM_ACCESS_NORMAL = 2'b00; // 正常
	localparam IMEM_ACCESS_PC_UNALIGNED = 2'b01; // 指令地址非对齐
	localparam IMEM_ACCESS_BUS_ERR = 2'b10; // 指令总线访问错误
	localparam IMEM_ACCESS_TIMEOUT = 2'b11; // 响应超时
	// 空指令
	localparam NOP_INST = 32'h0000_0013;
	
	/** 传输缓存区 **/
	// 传输缓存控制
	wire clr_all_trans; // 清除所有传输(指示)
	wire on_trans_start; // 启动传输(指示)
	wire on_trans_finish; // 传输完成(指示)
	reg[1:0] trans_n_processing; // 正在处理的传输个数(计数器)
	reg no_trans_processing; // 没有正在处理的传输(标志)
	// 指令地址对齐(标志)
	wire pc_aligned;
	// 传输信息fifo
	reg trans_msg_fifo_pc_unaligned_flag[0:1]; // 寄存器缓存(指令地址非对齐标志)
	wire trans_msg_fifo_wen; // 写使能
	reg[1:0] trans_msg_fifo_wptr; // 写指针(独热码)
	wire trans_msg_fifo_ren; // 读使能
	reg[1:0] trans_msg_fifo_rptr; // 读指针(独热码)
	wire trans_msg_fifo_pc_unaligned_flag_dout; // 数据输出(指令地址非对齐标志)
	
	assign on_trans_start = imem_access_req_valid & imem_access_req_ready;
	assign on_trans_finish = imem_access_resp_valid;
	
	// imem_access_req_addr[(inst_addr_alignment_width == 32):0] == 0
	assign pc_aligned = ~(|imem_access_req_addr[(inst_addr_alignment_width == 32):0]);
	
	assign trans_msg_fifo_wen = on_trans_start & ((pc_unaligned_imdt_resp == "false")
		// (trans_n_processing == 2'b00) & (~pc_aligned)
		| (~((~trans_n_processing[1]) & (~trans_n_processing[0]) & (~pc_aligned))));
	assign trans_msg_fifo_ren = on_trans_finish & ((pc_unaligned_imdt_resp == "false")
		// (trans_n_processing == 2'b00) & (~pc_aligned)
		| (~((~trans_n_processing[1]) & (~trans_n_processing[0]) & (~pc_aligned))));
	assign trans_msg_fifo_pc_unaligned_flag_dout = 
		(trans_msg_fifo_rptr[0] & trans_msg_fifo_pc_unaligned_flag[0])
		| (trans_msg_fifo_rptr[1] & trans_msg_fifo_pc_unaligned_flag[1]);
	
	// 正在处理的传输个数(计数器)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			trans_n_processing <= 2'b00;
		else if(clr_all_trans | (on_trans_start ^ on_trans_finish))
			trans_n_processing <= # simulation_delay 
				// on_trans_start ? (trans_n_processing + 2'b01):(trans_n_processing - 2'b01)
				{2{~clr_all_trans}} & (trans_n_processing + {~on_trans_start, 1'b1});
	end
	// 没有正在处理的传输(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			no_trans_processing <= 1'b1;
		else if(clr_all_trans | (on_trans_start ^ on_trans_finish))
			// clr_all_trans ? 1'b1:(on_trans_start ? 1'b0:(trans_n_processing == 2'b01))
			no_trans_processing <= # simulation_delay clr_all_trans | ((~on_trans_start) & (~trans_n_processing[1]));
	end
	
	// 传输信息fifo写指针(独热码)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			trans_msg_fifo_wptr <= 2'b01;
		else if(trans_msg_fifo_wen)
			trans_msg_fifo_wptr <= # simulation_delay {trans_msg_fifo_wptr[0], trans_msg_fifo_wptr[1]};
	end
	// 传输信息fifo读指针(独热码)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			trans_msg_fifo_rptr <= 2'b01;
		else if(trans_msg_fifo_ren)
			trans_msg_fifo_rptr <= # simulation_delay {trans_msg_fifo_rptr[0], trans_msg_fifo_rptr[1]};
	end
	
	// 传输信息fifo寄存器缓存
	genvar trans_msg_fifo_item_i;
	generate
		for(trans_msg_fifo_item_i = 0;trans_msg_fifo_item_i < 2;trans_msg_fifo_item_i = trans_msg_fifo_item_i + 1)
		begin
			always @(posedge clk)
			begin
				if(trans_msg_fifo_wen & trans_msg_fifo_wptr[trans_msg_fifo_item_i])
					trans_msg_fifo_pc_unaligned_flag[trans_msg_fifo_item_i] <= # simulation_delay ~pc_aligned;
			end
		end
	endgenerate
	
	/** 指令ICB主机命令通道 **/
	reg[clogb2(imem_access_timeout_th-1):0] m_icb_timeout_cnt; // 指令ICB主机访问超时计数器
	reg m_icb_timeout_flag; // 指令ICB主机访问超时标志
	reg m_icb_timeout_idct; // 指令ICB主机访问超时指示
	
	// 指令存储器访问请求AXIS握手条件: imem_access_req_valid & (~m_icb_timeout_flag)
	//     & (~trans_n_processing[1]) & ((~pc_aligned) | m_icb_cmd_ready)
	assign imem_access_req_ready = 
		(~m_icb_timeout_flag) & // ICB主机访问超时后不再允许新的访问请求
		(~trans_n_processing[1]) & // 必须保证正在处理的传输个数 <= 2
		((~pc_aligned) | m_icb_cmd_ready); // 若当前请求的地址是对齐的, 必须等待命令通道就绪
	
	assign m_icb_cmd_addr = imem_access_req_addr;
	assign m_icb_cmd_read = imem_access_req_read;
	assign m_icb_cmd_wdata = imem_access_req_wdata;
	assign m_icb_cmd_wmask = imem_access_req_wmask;
	// ICB主机命令通道握手条件: imem_access_req_valid & m_icb_cmd_ready & (~m_icb_timeout_flag) & 
	//     (~trans_n_processing[1]) & pc_aligned
	assign m_icb_cmd_valid = 
		imem_access_req_valid & // 等待有效的访问请求
		(~m_icb_timeout_flag) & // ICB主机访问超时后不再允许新的访问请求
		(~trans_n_processing[1]) & // 必须保证正在处理的传输个数 <= 2
		pc_aligned; // 若当前请求的地址是非对齐的, 不向命令通道发起传输
	
	assign ibus_timeout = m_icb_timeout_flag;
	
	assign clr_all_trans = m_icb_timeout_idct;
	
	// 指令ICB主机访问超时计数器
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			m_icb_timeout_cnt <= 0;
		else if((~m_icb_timeout_flag) & ((~no_trans_processing) | on_trans_finish))
			// on_trans_finish ? 0:(m_icb_timeout_cnt + 1)
			m_icb_timeout_cnt <= # simulation_delay {(clogb2(imem_access_timeout_th-1)+1){~on_trans_finish}}
				& (m_icb_timeout_cnt + 1);
	end
	// 指令ICB主机访问超时标志
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			m_icb_timeout_flag <= 1'b0;
		else if(~m_icb_timeout_flag)
			m_icb_timeout_flag <= # simulation_delay (~no_trans_processing)
				& (m_icb_timeout_cnt == (imem_access_timeout_th - 1));
	end
	// 指令ICB主机访问超时指示
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			m_icb_timeout_idct <= 1'b0;
		else
			m_icb_timeout_idct <= # simulation_delay (~m_icb_timeout_flag)
				& (~no_trans_processing) & (m_icb_timeout_cnt == (imem_access_timeout_th - 1));
	end
	
	/** 指令ICB主机响应通道 **/
	wire resp_with_normal; // 返回响应(正常)
	wire resp_with_pc_unaligned; // 返回响应(指令地址非对齐)
	wire resp_with_bus_err; // 返回响应(总线错误)
	wire resp_with_timeout; // 返回响应(访问超时)
	
	assign imem_access_resp_rdata = 
		resp_with_normal ? m_icb_rsp_rdata:NOP_INST;
	assign imem_access_resp_err = 
		({2{resp_with_normal}} & IMEM_ACCESS_NORMAL)
		| ({2{resp_with_pc_unaligned}} & IMEM_ACCESS_PC_UNALIGNED)
		| ({2{resp_with_bus_err}} & IMEM_ACCESS_BUS_ERR)
		| ({2{resp_with_timeout}} & IMEM_ACCESS_TIMEOUT); // 将"响应超时"编码为2'b11, 使得"响应超时"的优先级最高
	assign imem_access_resp_valid = 
		(m_icb_rsp_valid & m_icb_rsp_ready) | // ICB主机响应通道上完成传输
		resp_with_pc_unaligned | // 给出当前的地址非对齐请求的响应
		resp_with_timeout; // ICB主机访问超时
	
	assign resp_with_normal = m_icb_rsp_valid & m_icb_rsp_ready & (~m_icb_rsp_err);
	assign resp_with_pc_unaligned = 
		((~no_trans_processing) & trans_msg_fifo_pc_unaligned_flag_dout)
		// 允许PC地址非对齐时立即响应
		| ((pc_unaligned_imdt_resp == "true") & (~m_icb_timeout_flag)
			& no_trans_processing & (~pc_aligned) & imem_access_req_valid);
	assign resp_with_bus_err = m_icb_rsp_valid & m_icb_rsp_ready & m_icb_rsp_err;
	assign resp_with_timeout = m_icb_timeout_idct;
	
	// ICB主机响应握手条件: m_icb_rsp_valid & (~m_icb_timeout_flag)
	//     & (~((~no_trans_processing) & trans_msg_fifo_pc_unaligned_flag_dout))
	assign m_icb_rsp_ready = 
		(~m_icb_timeout_flag) & // ICB主机访问超时后不再允许新的访问请求
		// 当给出当前的地址非对齐请求的响应时, 镇压ICB主机的响应通道
		(~((~no_trans_processing) & trans_msg_fifo_pc_unaligned_flag_dout));
    
endmodule
