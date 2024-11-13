`timescale 1ns / 1ps
/********************************************************************
本模块: AXIS卷积核参数缓存区

描述:
将多通道卷积核存入n个缓存区, 读缓存区时同时输出m个多通道卷积核的同一通道
写多通道卷积核时每clk从输入卷积核参数流中取1个参数点

MEM读时延 = 2clk

		 [------多通道卷积核#0------]  --
         [------多通道卷积核#1------]   |----->
		 [------多通道卷积核#2------]   |----->
		 [------多通道卷积核#3------]  --
 ----->  [------多通道卷积核#4------]
		 [------多通道卷积核#5------]
		 [------多通道卷积核#6------]
		 [------多通道卷积核#7------]

3x3单通道卷积核存储方式:
	{x3y3, x2y3, x1y3, x3y2, x2y2, x1y2, x3y1, x2y1, x1y1}

注意：
卷积核参数缓存个数(kernal_pars_buffer_n)必须>=多通道卷积核的并行个数(kernal_prl_n)

协议:
AXIS SLAVE
FIFO READ
MEM READ

作者: 陈家耀
日期: 2024/10/22
********************************************************************/


module axis_kernal_params_buffer #(
	parameter integer kernal_pars_buffer_n = 8, // 卷积核参数缓存个数
	parameter integer kernal_prl_n = 4, // 多通道卷积核的并行个数
	parameter integer kernal_param_data_width = 16, // 卷积核参数位宽(8 | 16 | 32 | 64)
	parameter integer max_feature_map_chn_n = 512, // 最大的输入特征图通道数
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 运行时参数
	input wire kernal_type, // 卷积核类型(1'b0 -> 1x1, 1'b1 -> 3x3)
	
	// 输入卷积核参数流(AXIS从机)
	input wire[63:0] s_axis_kernal_pars_data,
	input wire[7:0] s_axis_kernal_pars_keep,
	input wire s_axis_kernal_pars_last, // 表示最后1组卷积核参数
	input wire s_axis_kernal_pars_user, // 当前多通道卷积核是否有效
	input wire s_axis_kernal_pars_valid,
	output wire s_axis_kernal_pars_ready, // 注意:非寄存器输出!
	
	// 卷积核参数缓存控制(fifo读端口)
	input wire kernal_pars_buf_fifo_ren,
	output wire kernal_pars_buf_fifo_empty_n,
	
	// 卷积核参数缓存MEM读端口
	input wire kernal_pars_buf_mem_buf_ren_s0,
	input wire kernal_pars_buf_mem_buf_ren_s1,
	input wire[15:0] kernal_pars_buf_mem_buf_raddr, // 每个读地址对应1个单通道卷积核
	output wire[kernal_prl_n*kernal_param_data_width*9-1:0] kernal_pars_buf_mem_buf_dout // {核#(n-1), ..., 核#1, 核#0}
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
	localparam integer kernal_pars_n_per_clk = 64/kernal_param_data_width; // 写缓存区时每clk输入的卷积核参数个数
	
	/** 输入卷积核参数流 **/
	wire[kernal_param_data_width-1:0] in_kernal_pars[0:kernal_pars_n_per_clk-1]; // 输入卷积核参数
	wire[kernal_pars_n_per_clk-1:0] in_kernal_pars_vld_mask; // 输入卷积核参数的有效掩码
	
	genvar in_kernal_pars_i;
	generate
		for(in_kernal_pars_i = 0;in_kernal_pars_i < kernal_pars_n_per_clk;in_kernal_pars_i = in_kernal_pars_i + 1)
		begin
			assign in_kernal_pars[in_kernal_pars_i] = 
				s_axis_kernal_pars_data[(in_kernal_pars_i+1)*kernal_param_data_width-1:
					in_kernal_pars_i*kernal_param_data_width];
			assign in_kernal_pars_vld_mask[in_kernal_pars_i] = 
				s_axis_kernal_pars_keep[in_kernal_pars_i*kernal_param_data_width/8];
		end
	endgenerate
	
	/** 缓存区写数据流 **/
	// 写缓存区AXIS主机
	wire[kernal_param_data_width*9-1:0] m_axis_buf_wt_data;
	wire m_axis_buf_wt_last; // 表示多通道卷积核的最后1个通道
	wire m_axis_buf_wt_user; // 当前多通道卷积核是否有效
	wire m_axis_buf_wt_valid;
	wire m_axis_buf_wt_ready;
	// 单通道卷积核参数缓存
	reg[kernal_param_data_width-1:0] single_chn_kernal_pars_buffer[0:7]; // 缓存区
	reg[8:0] single_chn_kernal_pars_saved_vec; // 缓存进度(独热码)
	reg[kernal_pars_n_per_clk-1:0] single_chn_kernal_pars_item_sel_cur; // 当前项选择(独热码)
	wire[kernal_pars_n_per_clk-1:0] single_chn_kernal_pars_item_sel_nxt; // 下一项选择(独热码)
	wire last_kernal_pars_item; // 最后1个卷积核参数(标志)
	wire[kernal_param_data_width-1:0] single_chn_kernal_pars_data_selected; // 选择的卷积核参数数据项
	
	// 握手条件: s_axis_kernal_pars_valid & m_axis_buf_wt_ready & (single_chn_kernal_pars_item_sel_cur[kernal_pars_n_per_clk-1]
	//     | (s_axis_kernal_pars_last & ((single_chn_kernal_pars_item_sel_nxt & in_kernal_pars_vld_mask)
	//         == {kernal_pars_n_per_clk{1'b0}})))
	assign s_axis_kernal_pars_ready = m_axis_buf_wt_ready & (single_chn_kernal_pars_item_sel_cur[kernal_pars_n_per_clk-1] | 
		// s_axis_kernal_pars_last & ((single_chn_kernal_pars_item_sel_nxt & in_kernal_pars_vld_mask)
		//     == {kernal_pars_n_per_clk{1'b0}})
		(s_axis_kernal_pars_last & (~(|(single_chn_kernal_pars_item_sel_nxt & in_kernal_pars_vld_mask)))));
	
	assign m_axis_buf_wt_data = {
		{(kernal_param_data_width*4){kernal_type}},
		{(kernal_param_data_width){1'b1}},
		{(kernal_param_data_width*4){kernal_type}}
	} & {
		single_chn_kernal_pars_data_selected,
		single_chn_kernal_pars_buffer[7],
		single_chn_kernal_pars_buffer[6],
		single_chn_kernal_pars_buffer[5],
		// 卷积核类型为1x1时仅保留x2y2处的参数
		kernal_type ? single_chn_kernal_pars_buffer[4]:single_chn_kernal_pars_data_selected,
		single_chn_kernal_pars_buffer[3],
		single_chn_kernal_pars_buffer[2],
		single_chn_kernal_pars_buffer[1],
		single_chn_kernal_pars_buffer[0]
	};
	assign m_axis_buf_wt_last = last_kernal_pars_item;
	assign m_axis_buf_wt_user = s_axis_kernal_pars_user;
	// 握手条件: s_axis_kernal_pars_valid & m_axis_buf_wt_ready & 
	//     (single_chn_kernal_pars_saved_vec[8] | (~kernal_type))
	assign m_axis_buf_wt_valid = s_axis_kernal_pars_valid & 
		(single_chn_kernal_pars_saved_vec[8] | last_kernal_pars_item | (~kernal_type));
	
	assign single_chn_kernal_pars_item_sel_nxt = {
		single_chn_kernal_pars_item_sel_cur[((kernal_pars_n_per_clk == 1) ? 0:(kernal_pars_n_per_clk-2)):0], 
		(kernal_pars_n_per_clk == 1) | single_chn_kernal_pars_item_sel_cur[kernal_pars_n_per_clk-1]
	};
	
	assign last_kernal_pars_item = s_axis_kernal_pars_last & 
		// single_chn_kernal_pars_item_sel_cur[kernal_pars_n_per_clk-1]
		//     | ((single_chn_kernal_pars_item_sel_nxt & in_kernal_pars_vld_mask) == {kernal_pars_n_per_clk{1'b0}})
		(single_chn_kernal_pars_item_sel_cur[kernal_pars_n_per_clk-1]
			| (~(|(single_chn_kernal_pars_item_sel_nxt & in_kernal_pars_vld_mask))));
	
	assign single_chn_kernal_pars_data_selected = 
		(in_kernal_pars[0] & 
			{kernal_param_data_width{single_chn_kernal_pars_item_sel_cur[0]}}) | 
		(in_kernal_pars[(kernal_param_data_width <= 32) ? 1:0] & 
			{kernal_param_data_width{single_chn_kernal_pars_item_sel_cur[(kernal_param_data_width <= 32) ? 1:0]}}) | 
		(in_kernal_pars[(kernal_param_data_width <= 16) ? 2:0] & 
			{kernal_param_data_width{single_chn_kernal_pars_item_sel_cur[(kernal_param_data_width <= 16) ? 2:0]}}) | 
		(in_kernal_pars[(kernal_param_data_width <= 16) ? 3:0] & 
			{kernal_param_data_width{single_chn_kernal_pars_item_sel_cur[(kernal_param_data_width <= 16) ? 3:0]}}) | 
		(in_kernal_pars[(kernal_param_data_width == 8) ? 4:0] & 
			{kernal_param_data_width{single_chn_kernal_pars_item_sel_cur[(kernal_param_data_width == 8) ? 4:0]}}) | 
		(in_kernal_pars[(kernal_param_data_width == 8) ? 5:0] & 
			{kernal_param_data_width{single_chn_kernal_pars_item_sel_cur[(kernal_param_data_width == 8) ? 5:0]}}) | 
		(in_kernal_pars[(kernal_param_data_width == 8) ? 6:0] & 
			{kernal_param_data_width{single_chn_kernal_pars_item_sel_cur[(kernal_param_data_width == 8) ? 6:0]}}) | 
		(in_kernal_pars[(kernal_param_data_width == 8) ? 7:0] & 
			{kernal_param_data_width{single_chn_kernal_pars_item_sel_cur[(kernal_param_data_width == 8) ? 7:0]}});
	
	// 单通道卷积核参数缓存区
	genvar single_chn_kernal_pars_buffer_i;
	generate
		for(single_chn_kernal_pars_buffer_i = 0;single_chn_kernal_pars_buffer_i < 8;
			single_chn_kernal_pars_buffer_i = single_chn_kernal_pars_buffer_i + 1)
		begin
			always @(posedge clk)
			begin
				if(s_axis_kernal_pars_valid & m_axis_buf_wt_ready & 
					kernal_type & single_chn_kernal_pars_saved_vec[single_chn_kernal_pars_buffer_i])
				begin
					single_chn_kernal_pars_buffer[single_chn_kernal_pars_buffer_i] <= 
						# simulation_delay single_chn_kernal_pars_data_selected;
				end
			end
		end
	endgenerate
	
	// 单通道卷积核参数缓存进度(独热码)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			single_chn_kernal_pars_saved_vec <= 9'b0_0000_0001;
		else if(s_axis_kernal_pars_valid & m_axis_buf_wt_ready)
			// (last_kernal_pars_item | (~kernal_type)) ? 9'b0_0000_0001:
			//     {single_chn_kernal_pars_saved_vec[7:0], single_chn_kernal_pars_saved_vec[8]}
			single_chn_kernal_pars_saved_vec <= # simulation_delay 
				{{8{~(last_kernal_pars_item | (~kernal_type))}} & single_chn_kernal_pars_saved_vec[7:0], 
					last_kernal_pars_item | (~kernal_type) | single_chn_kernal_pars_saved_vec[8]};
	end
	// 单通道卷积核参数当前项选择(独热码)
	generate
		if(kernal_pars_n_per_clk == 1)
		begin
			always @(*)
				single_chn_kernal_pars_item_sel_cur = 1'b1;
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					single_chn_kernal_pars_item_sel_cur <= {{(kernal_pars_n_per_clk-1){1'b0}}, 1'b1};
				else if(s_axis_kernal_pars_valid & m_axis_buf_wt_ready)
					// last_kernal_pars_item ? {{(kernal_pars_n_per_clk-1){1'b0}}, 1'b1}:
					//     {single_chn_kernal_pars_item_sel_cur[kernal_pars_n_per_clk-2:0], 
					//         single_chn_kernal_pars_item_sel_cur[kernal_pars_n_per_clk-1]}
					single_chn_kernal_pars_item_sel_cur <= # simulation_delay 
						{{(kernal_pars_n_per_clk-1){~last_kernal_pars_item}} & 
							single_chn_kernal_pars_item_sel_cur[kernal_pars_n_per_clk-2:0], 
							last_kernal_pars_item | single_chn_kernal_pars_item_sel_cur[kernal_pars_n_per_clk-1]};
			end
		end
	endgenerate
	
	/** 缓存区控制 **/
	// 写端口
	wire kernal_pars_buffer_wen; // 写使能
	reg kernal_pars_buffer_full_n; // 满标志
	reg[kernal_pars_buffer_n-1:0] kernal_pars_buffer_wptr; // 写指针
	// 读端口
	wire kernal_pars_buffer_ren; // 读使能
	reg kernal_pars_buffer_empty_n; // 空标志
	reg[kernal_pars_buffer_n-1:0] kernal_pars_buffer_rptr; // 读指针
	reg[clogb2(kernal_pars_buffer_n-1):0] kernal_pars_buffer_rd_sel; // 读片选
	wire[clogb2(kernal_pars_buffer_n-1):0] kernal_pars_buffer_rd_sel_incr; // 读片选增量
	reg[clogb2(kernal_pars_buffer_n-1):0] kernal_pars_buffer_rd_sel_d; // 延迟1clk的读片选
	// 存储计数
	reg[clogb2(kernal_pars_buffer_n):0] kernal_pars_buffer_str_n_cur; // 当前的多通道卷积核存储个数
	wire[clogb2(kernal_pars_buffer_n):0] kernal_pars_buffer_str_n_nxt; // 下一的多通道卷积核存储个数
	wire[clogb2(kernal_pars_buffer_n):0] kernal_pars_buffer_str_n_incr; // 多通道卷积核存储个数增量
	
	assign m_axis_buf_wt_ready = kernal_pars_buffer_full_n;
	
	assign kernal_pars_buffer_wen = m_axis_buf_wt_valid & m_axis_buf_wt_last;
	assign kernal_pars_buffer_ren = kernal_pars_buf_fifo_ren;
	assign kernal_pars_buf_fifo_empty_n = kernal_pars_buffer_empty_n;
	
	assign kernal_pars_buffer_rd_sel_incr = (kernal_pars_buffer_rd_sel >= (kernal_pars_buffer_n - kernal_prl_n)) ? 
		// kernal_prl_n - kernal_pars_buffer_n
		((~(kernal_pars_buffer_n - kernal_prl_n)) + 1):
		kernal_prl_n;
	
	assign kernal_pars_buffer_str_n_nxt = kernal_pars_buffer_str_n_cur + kernal_pars_buffer_str_n_incr;
	assign kernal_pars_buffer_str_n_incr = 
		// -kernal_prl_n
		({kernal_pars_buffer_wen & kernal_pars_buffer_full_n, kernal_pars_buffer_ren & kernal_pars_buffer_empty_n}
			== 2'b01) ? ((~kernal_prl_n) + 1):
		// -kernal_prl_n + 1
		({kernal_pars_buffer_wen & kernal_pars_buffer_full_n, kernal_pars_buffer_ren & kernal_pars_buffer_empty_n}
			== 2'b11) ? ((~kernal_prl_n) + 2):
						1;
	
	// 卷积核参数缓存区写指针
	generate
		if(kernal_pars_buffer_n == 1)
		begin
			always @(*)
				kernal_pars_buffer_wptr = 1'b1;
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					kernal_pars_buffer_wptr <= {{(kernal_pars_buffer_n-1){1'b0}}, 1'b1};
				else if(kernal_pars_buffer_wen & kernal_pars_buffer_full_n)
					kernal_pars_buffer_wptr <= # simulation_delay 
						{kernal_pars_buffer_wptr[kernal_pars_buffer_n-2:0], kernal_pars_buffer_wptr[kernal_pars_buffer_n-1]};
			end
		end
	endgenerate
	
	// 卷积核参数缓存区满标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			kernal_pars_buffer_full_n <= 1'b1;
		else if((kernal_pars_buffer_wen & kernal_pars_buffer_full_n) | (kernal_pars_buffer_ren & kernal_pars_buffer_empty_n))
			kernal_pars_buffer_full_n <= # simulation_delay kernal_pars_buffer_str_n_nxt != kernal_pars_buffer_n;
	end
	// 卷积核参数缓存区空标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			kernal_pars_buffer_empty_n <= 1'b0;
		else if((kernal_pars_buffer_wen & kernal_pars_buffer_full_n) | (kernal_pars_buffer_ren & kernal_pars_buffer_empty_n))
			kernal_pars_buffer_empty_n <= # simulation_delay kernal_pars_buffer_str_n_nxt >= kernal_prl_n;
	end
	
	// 当前的多通道卷积核存储个数
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			kernal_pars_buffer_str_n_cur <= 0;
		else if((kernal_pars_buffer_wen & kernal_pars_buffer_full_n) | (kernal_pars_buffer_ren & kernal_pars_buffer_empty_n))
			kernal_pars_buffer_str_n_cur <= # simulation_delay kernal_pars_buffer_str_n_nxt;
	end
	
	// 卷积核参数缓存区读指针
	generate
		if(kernal_pars_buffer_n == kernal_prl_n)
		begin
			always @(*)
				kernal_pars_buffer_rptr = {kernal_pars_buffer_n{1'b1}};
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					kernal_pars_buffer_rptr <= {{(kernal_pars_buffer_n-kernal_prl_n){1'b0}}, 
						{kernal_prl_n{1'b1}}};
				else if(kernal_pars_buffer_ren & kernal_pars_buffer_empty_n)
					// 循环左移kernal_prl_n位
					kernal_pars_buffer_rptr <= # simulation_delay 
						(kernal_pars_buffer_rptr << kernal_prl_n) | 
						(kernal_pars_buffer_rptr >> (kernal_pars_buffer_n-kernal_prl_n));
			end
		end
	endgenerate
	
	// 卷积核参数缓存区读片选
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			kernal_pars_buffer_rd_sel <= 0;
		else if(kernal_pars_buffer_ren & kernal_pars_buffer_empty_n)
			kernal_pars_buffer_rd_sel <= # simulation_delay kernal_pars_buffer_rd_sel + kernal_pars_buffer_rd_sel_incr;
	end
	// 延迟1clk的卷积核参数缓存区读片选
	always @(posedge clk)
	begin
		if(kernal_pars_buf_mem_buf_ren_s0)
			kernal_pars_buffer_rd_sel_d <= # simulation_delay kernal_pars_buffer_rd_sel;
	end
	
	/** 多通道卷积核信息fifo **/
	reg kernal_msg_fifo[kernal_pars_buffer_n-1:0]; // fifo存储实体
	wire[kernal_pars_buffer_n-1:0] kernal_vld_vec; // 多通道卷积核有效标志向量
	reg[kernal_pars_buffer_n-1:0] kernal_vld_vec_d; // 延迟1clk的多通道卷积核有效标志向量
	
	genvar kernal_msg_fifo_i;
	generate
		for(kernal_msg_fifo_i = 0;kernal_msg_fifo_i < kernal_pars_buffer_n;kernal_msg_fifo_i = kernal_msg_fifo_i + 1)
		begin
			assign kernal_vld_vec[kernal_msg_fifo_i] = kernal_msg_fifo[kernal_msg_fifo_i];
			
			// 多通道卷积核有效标志
			always @(posedge clk)
			begin
				if(kernal_pars_buffer_wen & kernal_pars_buffer_full_n & kernal_pars_buffer_wptr[kernal_msg_fifo_i])
					kernal_msg_fifo[kernal_msg_fifo_i] <= # simulation_delay m_axis_buf_wt_user;
			end
		end
	endgenerate
	
	// 延迟1clk的多通道卷积核有效标志向量
	always @(posedge clk)
	begin
		if(kernal_pars_buf_mem_buf_ren_s0)
			kernal_vld_vec_d <= # simulation_delay kernal_vld_vec;
	end
	
	/** 缓存区MEM **/
	// 卷积核参数缓存区MEM写端口
	wire[kernal_pars_buffer_n-1:0] kernal_pars_buffer_mem_wen;
	reg[clogb2(max_feature_map_chn_n-1):0] kernal_pars_buffer_mem_waddr; // 每个写地址对应1个单通道卷积核
	wire[kernal_param_data_width*9-1:0] kernal_pars_buffer_mem_din;
	// 卷积核参数缓存区MEM读端口
	wire[kernal_pars_buffer_n-1:0] kernal_pars_buffer_mem_ren;
	wire[clogb2(max_feature_map_chn_n-1):0] kernal_pars_buffer_mem_raddr; // 每个读地址对应1个单通道卷积核
	wire[kernal_param_data_width*9-1:0] kernal_pars_buffer_mem_dout[0:kernal_pars_buffer_n-1];
	wire[kernal_pars_buffer_n*kernal_param_data_width*9-1:0] kernal_pars_buffer_mem_dout_flattened;
	wire[kernal_prl_n*kernal_param_data_width*9-1:0] kernal_pars_buffer_mem_dout_reorg;
	reg[kernal_prl_n*kernal_param_data_width*9-1:0] kernal_pars_buffer_mem_dout_reorg_d;
	
	assign kernal_pars_buffer_mem_wen = {kernal_pars_buffer_n{m_axis_buf_wt_valid & m_axis_buf_wt_ready}} & 
		kernal_pars_buffer_wptr;
	assign kernal_pars_buffer_mem_din = m_axis_buf_wt_data;
	
	assign kernal_pars_buffer_mem_ren = {kernal_pars_buffer_n{kernal_pars_buf_mem_buf_ren_s0}} & kernal_pars_buffer_rptr;
	assign kernal_pars_buffer_mem_raddr = kernal_pars_buf_mem_buf_raddr[clogb2(max_feature_map_chn_n-1):0];
	assign kernal_pars_buf_mem_buf_dout = kernal_pars_buffer_mem_dout_reorg_d;
	
	// 循环右移(kernal_pars_buffer_rd_sel_d * kernal_param_data_width * 9)位, 仅保留kernal_pars_buffer_n种情况
	assign kernal_pars_buffer_mem_dout_reorg = (kernal_pars_buffer_rd_sel_d >= kernal_pars_buffer_n) ? 
		{(kernal_param_data_width*9*kernal_prl_n){1'bx}}: // not care!
		((kernal_pars_buffer_mem_dout_flattened >> (kernal_pars_buffer_rd_sel_d * kernal_param_data_width * 9)) | 
			(kernal_pars_buffer_mem_dout_flattened << 
				((kernal_pars_buffer_n - kernal_pars_buffer_rd_sel_d) * kernal_param_data_width * 9)));
	
	// 展平的读数据
	genvar kernal_pars_buffer_mem_dout_flattened_i;
	generate
		for(kernal_pars_buffer_mem_dout_flattened_i = 0;kernal_pars_buffer_mem_dout_flattened_i < kernal_pars_buffer_n;
			kernal_pars_buffer_mem_dout_flattened_i = kernal_pars_buffer_mem_dout_flattened_i + 1)
		begin
			assign kernal_pars_buffer_mem_dout_flattened[(kernal_pars_buffer_mem_dout_flattened_i+1)*kernal_param_data_width*9-1:
				kernal_pars_buffer_mem_dout_flattened_i*kernal_param_data_width*9] = 
				kernal_pars_buffer_mem_dout[kernal_pars_buffer_mem_dout_flattened_i] & 
				// 根据多通道卷积核有效标志对读数据进行掩码清零处理
				{(kernal_param_data_width*9){kernal_vld_vec_d[kernal_pars_buffer_mem_dout_flattened_i]}};
		end
	endgenerate
	
	// 卷积核参数缓存区MEM写地址
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			kernal_pars_buffer_mem_waddr <= 0;
		else if(m_axis_buf_wt_valid & m_axis_buf_wt_ready)
			// m_axis_buf_wt_last ? 0:(kernal_pars_buffer_mem_waddr + 1)
			kernal_pars_buffer_mem_waddr <= # simulation_delay 
				{(clogb2(max_feature_map_chn_n-1)+1){~m_axis_buf_wt_last}} & (kernal_pars_buffer_mem_waddr + 1);
	end
	
	// 延迟1clk的重整理的卷积核参数缓存区MEM读数据
	always @(posedge clk)
	begin
		if(kernal_pars_buf_mem_buf_ren_s1)
			kernal_pars_buffer_mem_dout_reorg_d <= # simulation_delay kernal_pars_buffer_mem_dout_reorg;
	end
	
	// 缓存MEM
	genvar kernal_pars_buf_mem_i;
	generate
		for(kernal_pars_buf_mem_i = 0;kernal_pars_buf_mem_i < kernal_pars_buffer_n;
			kernal_pars_buf_mem_i = kernal_pars_buf_mem_i + 1)
		begin
			kernal_params_buffer #(
				.kernal_param_data_width(kernal_param_data_width),
				.max_feature_map_chn_n(max_feature_map_chn_n),
				.simulation_delay(simulation_delay)
			)kernal_params_buffer_mem_u(
				.clk(clk),
				
				.buffer_wen(kernal_pars_buffer_mem_wen[kernal_pars_buf_mem_i]),
				.buffer_waddr({{(15-clogb2(max_feature_map_chn_n-1)){1'b0}}, kernal_pars_buffer_mem_waddr}),
				.buffer_din(kernal_pars_buffer_mem_din),
				
				.buffer_ren(kernal_pars_buffer_mem_ren[kernal_pars_buf_mem_i]),
				.buffer_raddr({{(15-clogb2(max_feature_map_chn_n-1)){1'b0}}, kernal_pars_buffer_mem_raddr}),
				.buffer_dout(kernal_pars_buffer_mem_dout[kernal_pars_buf_mem_i])
			);
		end
	endgenerate
	
endmodule
