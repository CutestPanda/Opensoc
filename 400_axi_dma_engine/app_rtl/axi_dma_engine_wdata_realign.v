`timescale 1ns / 1ps
/********************************************************************
本模块: AXI通用DMA引擎写数据重对齐

描述:
根据重对齐基准字节位置, 对输入数据流作字节级别的重新对齐处理

例如, 当重对齐基准字节位置为2时:
	data D3 D2 D1 D0  |  D7 D6 D5 D4    --->    D1 D0  X  X  |  D5 D4 D3 D2  |  X X D7 D6
	keep  1  1  1  1  |   0  1  1  1    --->     1  1  0  0  |  1  1  1  1   |  0 0 0  1

注意：
对于输入数据流来说, 仅当last信号有效时keep信号可以不全1, 其余情况下keep信号必须全1

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/01/29
********************************************************************/


module axi_dma_engine_wdata_realign #(
	parameter integer DATA_WIDTH = 32, // 传输数据位宽(32 | 64 | 128 | 256)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 输入数据流AXIS接口的时钟和复位
	input wire axis_aclk,
	input wire axis_aresetn,
	
	// 输入数据流AXIS从机
	input wire[DATA_WIDTH-1:0] s_s2mm_axis_data,
	input wire[DATA_WIDTH/8-1:0] s_s2mm_axis_keep,
	input wire[4:0] s_s2mm_axis_user, // 重对齐基准字节位置
	input wire s_s2mm_axis_last,
	input wire s_s2mm_axis_valid,
	output wire s_s2mm_axis_ready,
	
	// 输入数据流AXIS主机
	output wire[DATA_WIDTH-1:0] m_s2mm_axis_data,
	output wire[DATA_WIDTH/8-1:0] m_s2mm_axis_keep,
	output wire m_s2mm_axis_last,
	output wire m_s2mm_axis_valid,
	input wire m_s2mm_axis_ready
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
	
	/** 输出寄存器片 **/
	// 寄存器片AXIS从机
    wire[DATA_WIDTH-1:0] s_reg_slice_axis_data;
	wire[DATA_WIDTH/8-1:0] s_reg_slice_axis_keep;
	wire s_reg_slice_axis_last;
	wire s_reg_slice_axis_valid;
	wire s_reg_slice_axis_ready;
    // 寄存器片AXIS主机
    wire[DATA_WIDTH-1:0] m_reg_slice_axis_data;
	wire[DATA_WIDTH/8-1:0] m_reg_slice_axis_keep;
	wire m_reg_slice_axis_last;
	wire m_reg_slice_axis_valid;
	wire m_reg_slice_axis_ready;
	
	assign m_s2mm_axis_data = m_reg_slice_axis_data;
	assign m_s2mm_axis_keep = m_reg_slice_axis_keep;
	assign m_s2mm_axis_last = m_reg_slice_axis_last;
	assign m_s2mm_axis_valid = m_reg_slice_axis_valid;
	assign m_reg_slice_axis_ready = m_s2mm_axis_ready;
	
	axis_reg_slice #(
		.data_width(DATA_WIDTH),
		.user_width(1),
		.forward_registered("false"),
		.back_registered("true"),
		.en_ready("true"),
		.simulation_delay(SIM_DELAY)
	)out_reg_slice_u(
		.clk(axis_aclk),
		.rst_n(axis_aresetn),
		
		.s_axis_data(s_reg_slice_axis_data),
		.s_axis_keep(s_reg_slice_axis_keep),
		.s_axis_user(1'bx),
		.s_axis_last(s_reg_slice_axis_last),
		.s_axis_valid(s_reg_slice_axis_valid),
		.s_axis_ready(s_reg_slice_axis_ready),
		
		.m_axis_data(m_reg_slice_axis_data),
		.m_axis_keep(m_reg_slice_axis_keep),
		.m_axis_user(),
		.m_axis_last(m_reg_slice_axis_last),
		.m_axis_valid(m_reg_slice_axis_valid),
		.m_axis_ready(m_reg_slice_axis_ready)
	);
	
	/** 写数据重对齐 **/
	reg[DATA_WIDTH-8-1:0] reorg_data_buf; // 数据重对齐缓存
	reg[DATA_WIDTH/8-1-1:0] reorg_keep_buf; // keep掩码重对齐缓存
	reg is_first_trans; // 是否数据包内的首次传输
	wire is_last_trans; // 是否数据包内的最后1次传输
	wire need_buf_hdat; // 是否需要缓存高位数据
	reg to_flush_buf; // 冲刷缓存(标志)
	
	// 握手条件: (~to_flush_buf) & (s_s2mm_axis_valid & s_reg_slice_axis_ready)
	assign s_s2mm_axis_ready = (~to_flush_buf) & s_reg_slice_axis_ready;
	
	assign s_reg_slice_axis_data = 
		to_flush_buf ? 
			{8'dx, reorg_data_buf}:
			((s_s2mm_axis_data << (s_s2mm_axis_user[clogb2(DATA_WIDTH/8-1):0] * 8)) | {8'd0, reorg_data_buf});
	assign s_reg_slice_axis_keep = 
		to_flush_buf ? 
			{1'b0, reorg_keep_buf}:
			((s_s2mm_axis_keep << s_s2mm_axis_user[clogb2(DATA_WIDTH/8-1):0]) | {1'b0, reorg_keep_buf});
	assign s_reg_slice_axis_last = to_flush_buf | (s_s2mm_axis_last & (~need_buf_hdat));
	// 握手条件: to_flush_buf ? s_reg_slice_axis_ready:(s_s2mm_axis_valid & s_reg_slice_axis_ready)
	assign s_reg_slice_axis_valid = to_flush_buf | s_s2mm_axis_valid;
	
	assign is_last_trans = s_s2mm_axis_last;
	assign need_buf_hdat = |(s_s2mm_axis_keep[DATA_WIDTH/8-1:1] >> (DATA_WIDTH / 8 - 1 - s_s2mm_axis_user[clogb2(DATA_WIDTH/8-1):0]));
	
	// 数据重对齐缓存
	always @(posedge axis_aclk)
	begin
		if(~axis_aresetn)
			reorg_data_buf <= {(DATA_WIDTH-8){1'b0}};
		else if((s_s2mm_axis_valid & s_s2mm_axis_ready) | (to_flush_buf & s_reg_slice_axis_ready))
			reorg_data_buf <= # SIM_DELAY 
				{(DATA_WIDTH-8){~(to_flush_buf ? s_reg_slice_axis_ready:(s_s2mm_axis_last & (~need_buf_hdat)))}} & 
				(s_s2mm_axis_data[DATA_WIDTH-1:8] >> ((DATA_WIDTH / 8 - 1 - s_s2mm_axis_user[clogb2(DATA_WIDTH/8-1):0]) * 8));
	end
	// keep掩码重对齐缓存
	always @(posedge axis_aclk)
	begin
		if(~axis_aresetn)
			reorg_keep_buf <= {(DATA_WIDTH/8-1){1'b0}};
		else if((s_s2mm_axis_valid & s_s2mm_axis_ready) | (to_flush_buf & s_reg_slice_axis_ready))
			reorg_keep_buf <= # SIM_DELAY 
				{(DATA_WIDTH/8-1){~(to_flush_buf ? s_reg_slice_axis_ready:(s_s2mm_axis_last & (~need_buf_hdat)))}} & 
				(s_s2mm_axis_keep[DATA_WIDTH/8-1:1] >> (DATA_WIDTH / 8 - 1 - s_s2mm_axis_user[clogb2(DATA_WIDTH/8-1):0]));
	end
	
	// 是否数据包内的首次传输
	always @(posedge axis_aclk or negedge axis_aresetn)
	begin
		if(~axis_aresetn)
			is_first_trans <= 1'b1;
		else if(s_s2mm_axis_valid & s_s2mm_axis_ready)
			is_first_trans <= # SIM_DELAY is_last_trans;
	end
	
	// 冲刷缓存(标志)
	always @(posedge axis_aclk or negedge axis_aresetn)
	begin
		if(~axis_aresetn)
			to_flush_buf <= 1'b0;
		else if(to_flush_buf ? 
			s_reg_slice_axis_ready:
			(s_s2mm_axis_valid & s_s2mm_axis_ready & s_s2mm_axis_last & need_buf_hdat))
			to_flush_buf <= # SIM_DELAY ~to_flush_buf;
	end
	
endmodule
