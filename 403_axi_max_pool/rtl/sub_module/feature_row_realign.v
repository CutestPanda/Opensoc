`timescale 1ns / 1ps
/********************************************************************
本模块: 特征组提取器

描述: 
根据特征图的宽度, 从特征图像素流中提取特征组
输出速度 = 1特征组/clk

注意：
无

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2024/10/10
********************************************************************/


module feature_row_realign #(
	parameter integer feature_n_per_clk = 4, // 每个clk输入的特征点数量(2 | 4 | 8 | 16 | ...)
	parameter integer feature_data_width = 16, // 特征点位宽(必须能被8整除, 且>0)
	parameter integer max_feature_map_chn_n = 128, // 最大的特征图通道数
	parameter integer max_feature_map_w = 128, // 最大的特征图宽度
	parameter integer max_feature_map_h = 128, // 最大的特征图高度
	parameter en_out_reg_slice = "true", // 是否使能输出寄存器片
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
    input wire clk,
    input wire rst_n,
	
	// 使能信号
	input wire in_stream_en, // 允许输入数据流(标志)
	
	// 运行时参数
	input wire[15:0] feature_map_chn_n, // 特征图通道数 - 1
	input wire[15:0] feature_map_w, // 特征图宽度 - 1
	input wire[15:0] feature_map_h, // 特征图高度 - 1
	
	// 特征图像素流输入
	input wire[feature_n_per_clk*feature_data_width-1:0] s_axis_data,
	input wire[feature_n_per_clk*feature_data_width/8-1:0] s_axis_keep,
	input wire s_axis_last, // 指示特征图结束
	input wire s_axis_valid,
	output wire s_axis_ready,
	
	// 特征组输出
	output wire[feature_n_per_clk*feature_data_width-1:0] m_axis_data,
	output wire[2:0] m_axis_user, // {当前处于最后1个通道, 当前处于最后1行, 当前处于最后1列}
	output wire[feature_n_per_clk*feature_data_width/8-1:0] m_axis_keep,
	output wire m_axis_last, // 指示最后1个特征组
	output wire m_axis_valid,
	input wire m_axis_ready
);
	
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
        for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
			bit_depth = bit_depth >> 1;
    end
    endfunction
	
	// 计算数据中1的个数
    function integer count1_of_integer(input integer data, input integer data_width);
        integer i;
    begin
        count1_of_integer = 0;
        
        for(i = 0;i < data_width;i = i + 1)
			count1_of_integer = count1_of_integer + data[i];
    end
	endfunction
	
	/** 常量 **/
	localparam integer feature_pix_stream_data_width = feature_n_per_clk*feature_data_width; // 特征图像素流数据位宽
	
	/** 特征图像素流缓存 **/
	// 特征项有效标志
	wire[feature_n_per_clk-1:0] feature_item_keep;
	// 寄存器组
	reg[feature_pix_stream_data_width-1:0] feature_pix_stream_data_buffer[0:2]; // 特征图像素流缓存寄存器组(特征点)
	reg[clogb2(feature_n_per_clk-1):0] feature_pix_stream_msb_id_buffer[0:2]; // 特征图像素流缓存寄存器组(最后1个有效特征点的编号 + 1)
	reg feature_pix_stream_last_buffer[0:2]; // 特征图像素流缓存寄存器组(是否最后1个特征图数据)
	// 写端口
	wire feature_pix_stream_buffer_wen; // 特征图像素流缓存写使能
	reg[2:0] feature_pix_stream_buffer_wptr; // 特征图像素流缓存写指针(独热码)
	reg feature_pix_stream_buffer_full_n; // 特征图像素流缓存满标志
	// 读端口
	wire feature_pix_stream_buffer_ren; // 特征图像素流缓存读使能
	reg[2:0] feature_pix_stream_buffer_rptr; // 特征图像素流缓存读指针(独热码)
	reg feature_pix_stream_buffer_empty_n; // 特征图像素流缓存空标志
	reg[1:0] feature_pix_stream_buffer_data_cnt; // 特征图像素流缓存存储计数
	
	// 握手条件：s_axis_valid & feature_pix_stream_buffer_full_n & in_stream_en
	assign s_axis_ready = feature_pix_stream_buffer_full_n & in_stream_en;
	
	assign feature_pix_stream_buffer_wen = s_axis_valid & in_stream_en;
	
	// 特征项有效标志
	genvar feature_item_keep_i;
	generate
		for(feature_item_keep_i = 0;feature_item_keep_i < feature_n_per_clk;feature_item_keep_i = feature_item_keep_i + 1)
		begin
			assign feature_item_keep[feature_item_keep_i] = s_axis_keep[feature_item_keep_i*feature_data_width/8];
		end
	endgenerate
	
	// 特征图像素流缓存寄存器组
	genvar feature_pix_stream_buffer_i;
	generate
		for(feature_pix_stream_buffer_i = 0;feature_pix_stream_buffer_i < 3;feature_pix_stream_buffer_i = feature_pix_stream_buffer_i + 1)
		begin
			// 特征点
			always @(posedge clk)
			begin
				if(feature_pix_stream_buffer_wptr[feature_pix_stream_buffer_i] & feature_pix_stream_buffer_wen
					& feature_pix_stream_buffer_full_n)
					feature_pix_stream_data_buffer[feature_pix_stream_buffer_i] <= # simulation_delay s_axis_data;
			end
			// 最后1个有效字节的编号
			always @(posedge clk)
			begin
				if(feature_pix_stream_buffer_wptr[feature_pix_stream_buffer_i] & feature_pix_stream_buffer_wen
					& feature_pix_stream_buffer_full_n)
					feature_pix_stream_msb_id_buffer[feature_pix_stream_buffer_i] <=
						# simulation_delay count1_of_integer(feature_item_keep, feature_n_per_clk);
			end
			// 是否最后1个特征图数据
			always @(posedge clk)
			begin
				if(feature_pix_stream_buffer_wptr[feature_pix_stream_buffer_i] & feature_pix_stream_buffer_wen
					& feature_pix_stream_buffer_full_n)
					feature_pix_stream_last_buffer[feature_pix_stream_buffer_i] <= # simulation_delay s_axis_last;
			end
		end
	endgenerate
	
	// 特征图像素流缓存存储计数
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			feature_pix_stream_buffer_data_cnt <= 2'b00;
		else if((feature_pix_stream_buffer_wen & feature_pix_stream_buffer_full_n) ^ 
			(feature_pix_stream_buffer_ren & feature_pix_stream_buffer_empty_n))
			// (feature_pix_stream_buffer_wen & feature_pix_stream_buffer_full_n) ? (feature_pix_stream_buffer_data_cnt + 2'b01):
			//     (feature_pix_stream_buffer_data_cnt - 2'b01)
			feature_pix_stream_buffer_data_cnt <= # simulation_delay feature_pix_stream_buffer_data_cnt + 
				{~(feature_pix_stream_buffer_wen & feature_pix_stream_buffer_full_n), 1'b1};
	end
	
	// 特征图像素流缓存写指针(独热码)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			feature_pix_stream_buffer_wptr <= 3'b001;
		else if(feature_pix_stream_buffer_wen & feature_pix_stream_buffer_full_n)
			feature_pix_stream_buffer_wptr <= # simulation_delay {feature_pix_stream_buffer_wptr[1:0], feature_pix_stream_buffer_wptr[2]};
	end
	// 特征图像素流缓存满标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			feature_pix_stream_buffer_full_n <= 1'b1;
		else if((feature_pix_stream_buffer_wen & feature_pix_stream_buffer_full_n) ^ 
			(feature_pix_stream_buffer_ren & feature_pix_stream_buffer_empty_n))
			feature_pix_stream_buffer_full_n <= 
				/*
				(feature_pix_stream_buffer_wen & feature_pix_stream_buffer_full_n) ? 
					(feature_pix_stream_buffer_data_cnt != 2'd2):1'b1;
				*/
				# simulation_delay (~(feature_pix_stream_buffer_wen & feature_pix_stream_buffer_full_n))
					| (~feature_pix_stream_buffer_data_cnt[1]);
	end
	
	// 特征图像素流缓存读指针(独热码)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			feature_pix_stream_buffer_rptr <= 3'b001;
		else if(feature_pix_stream_buffer_ren & feature_pix_stream_buffer_empty_n)
			feature_pix_stream_buffer_rptr <= # simulation_delay {feature_pix_stream_buffer_rptr[1:0], feature_pix_stream_buffer_rptr[2]};
	end
	// 特征图像素流缓存空标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			feature_pix_stream_buffer_empty_n <= 1'b0;
		else if((feature_pix_stream_buffer_wen & feature_pix_stream_buffer_full_n) ^ 
			(feature_pix_stream_buffer_ren & feature_pix_stream_buffer_empty_n))
			feature_pix_stream_buffer_empty_n <= 
				/*
				(feature_pix_stream_buffer_wen & feature_pix_stream_buffer_full_n) ? 
					1'b1:(feature_pix_stream_buffer_data_cnt != 2'b01);
				*/
				# simulation_delay (feature_pix_stream_buffer_wen & feature_pix_stream_buffer_full_n)
					| feature_pix_stream_buffer_data_cnt[1];
	end
	
	/** 输出寄存器片 **/
	wire[feature_pix_stream_data_width-1:0] s_axis_reg_slice_data;
	wire[2:0] s_axis_reg_slice_user; // {当前处于最后1个通道, 当前处于最后1行, 当前处于最后1列}
	wire[feature_pix_stream_data_width/8-1:0] s_axis_reg_slice_keep;
	wire s_axis_reg_slice_last; // 指示最后1个特征组
	wire s_axis_reg_slice_valid;
	wire s_axis_reg_slice_ready;
	
	axis_reg_slice #(
		.data_width(feature_pix_stream_data_width),
		.user_width(3),
		.forward_registered(en_out_reg_slice),
		.back_registered(en_out_reg_slice),
		.en_ready("true"),
		.simulation_delay(simulation_delay)
	)out_reg_slice(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axis_data(s_axis_reg_slice_data),
		.s_axis_keep(s_axis_reg_slice_keep),
		.s_axis_user(s_axis_reg_slice_user),
		.s_axis_last(s_axis_reg_slice_last),
		.s_axis_valid(s_axis_reg_slice_valid),
		.s_axis_ready(s_axis_reg_slice_ready),
		
		.m_axis_data(m_axis_data),
		.m_axis_keep(m_axis_keep),
		.m_axis_user(m_axis_user),
		.m_axis_last(m_axis_last),
		.m_axis_valid(m_axis_valid),
		.m_axis_ready(m_axis_ready)
	);
	
	/** 特征点位置计数器 **/
	reg[clogb2(max_feature_map_w/feature_n_per_clk-1):0] feature_pos_x; // 特征点x坐标
	reg[clogb2(max_feature_map_h-1):0] feature_pos_y; // 特征点y坐标
	reg[clogb2(max_feature_map_chn_n-1):0] feature_pos_c; // 特征点c坐标
	wire feature_pos_x_at_last; // 当前特征点在最后1列(标志)
	wire feature_pos_y_at_last; // 当前特征点在最后1行(标志)
	wire feature_pos_c_at_last; // 当前特征点在最后1通道(标志)
	
	assign feature_pos_x_at_last = feature_pos_x == feature_map_w[15:clogb2(feature_n_per_clk)];
	assign feature_pos_y_at_last = feature_pos_y == feature_map_h;
	assign feature_pos_c_at_last = feature_pos_c == feature_map_chn_n;
	
	// 特征点x坐标
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			feature_pos_x <= 0;
		else if(s_axis_reg_slice_valid & s_axis_reg_slice_ready)
			feature_pos_x <= # simulation_delay feature_pos_x_at_last ? 0:(feature_pos_x + 1);
	end
	// 特征点y坐标
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			feature_pos_y <= 0;
		else if(s_axis_reg_slice_valid & s_axis_reg_slice_ready & feature_pos_x_at_last)
			feature_pos_y <= # simulation_delay feature_pos_y_at_last ? 0:(feature_pos_y + 1);
	end
	// 特征点c坐标
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			feature_pos_c <= 0;
		else if(s_axis_reg_slice_valid & s_axis_reg_slice_ready & feature_pos_x_at_last & feature_pos_y_at_last)
			feature_pos_c <= # simulation_delay feature_pos_c_at_last ? 0:(feature_pos_c + 1);
	end
	
	/** 特征组提取 **/
	wire[feature_pix_stream_data_width-1:0] feature_pix_stream_data_read_cur; // 当前读指针指向的特征图数据(特征点)
	wire[clogb2(feature_n_per_clk-1):0] feature_pix_stream_msb_id_read_cur; // 当前读指针指向的特征图数据(最后1个有效特征点的编号 + 1)
	wire feature_pix_stream_last_read_cur; // 当前读指针指向的特征图数据(是否最后1个特征图数据)
	wire[feature_pix_stream_data_width-1:0] feature_pix_stream_data_read_nxt; // 下一读指针指向的特征图数据(特征点)
	wire[clogb2(feature_n_per_clk-1):0] feature_pix_stream_msb_id_read_nxt; // 下一读指针指向的特征图数据(最后1个有效特征点的编号 + 1)
	wire feature_pix_stream_last_read_nxt; // 下一读指针指向的特征图数据(是否最后1个特征图数据)
	reg[clogb2(feature_n_per_clk-1):0] feature_pix_stream_item_ptr_cur; // 当前的特征图数据项指针
	wire[clogb2(feature_n_per_clk-1)+1:0] feature_pix_stream_item_ptr_nxt; // 下一特征图数据项指针
	wire[feature_pix_stream_data_width-1:0] feature_group; // 特征组
	wire[feature_pix_stream_data_width/8-1:0] feature_group_keep; // 特征组字节有效标志
	wire[clogb2(feature_n_per_clk-1):0] feature_item_n; // 有效特征项个数 - 1
	wire feature_data_last_at_cur; // 当前特征数据对应最后1组(标志)
	wire feature_data_last_at_nxt; // 下一特征数据对应最后1组(标志)
	wire feature_data_last; // 最后1个特征组(标志)
	reg to_rd_last_feature_data; // 取最后1个特征数据(指示)
	
	assign s_axis_reg_slice_data = feature_group;
	assign s_axis_reg_slice_user = {feature_pos_c_at_last, feature_pos_y_at_last, feature_pos_x_at_last};
	assign s_axis_reg_slice_keep = feature_group_keep;
	assign s_axis_reg_slice_last = feature_data_last;
	assign s_axis_reg_slice_valid = feature_pix_stream_buffer_empty_n & (~to_rd_last_feature_data) & 
		((feature_pix_stream_item_ptr_nxt[clogb2(feature_n_per_clk-1)+1]
			& (|feature_pix_stream_item_ptr_nxt[clogb2(feature_n_per_clk-1):0])) ? 
			feature_pix_stream_buffer_data_cnt[1]:1'b1);
	
	assign feature_pix_stream_buffer_ren = to_rd_last_feature_data | (s_axis_reg_slice_ready & 
		((feature_pix_stream_item_ptr_nxt[clogb2(feature_n_per_clk-1)+1]
			& ((~(|feature_pix_stream_item_ptr_nxt[clogb2(feature_n_per_clk-1):0])) | feature_pix_stream_buffer_data_cnt[1])) | 
			feature_data_last_at_cur));
	
	// 当前读指针指向的特征图数据
	assign feature_pix_stream_data_read_cur = 
		({feature_pix_stream_data_width{feature_pix_stream_buffer_rptr[0]}} & feature_pix_stream_data_buffer[0]) | 
		({feature_pix_stream_data_width{feature_pix_stream_buffer_rptr[1]}} & feature_pix_stream_data_buffer[1]) | 
		({feature_pix_stream_data_width{feature_pix_stream_buffer_rptr[2]}} & feature_pix_stream_data_buffer[2]);
	assign feature_pix_stream_msb_id_read_cur = 
		({(clogb2(feature_n_per_clk-1)+1){feature_pix_stream_buffer_rptr[0]}} & feature_pix_stream_msb_id_buffer[0]) | 
		({(clogb2(feature_n_per_clk-1)+1){feature_pix_stream_buffer_rptr[1]}} & feature_pix_stream_msb_id_buffer[1]) | 
		({(clogb2(feature_n_per_clk-1)+1){feature_pix_stream_buffer_rptr[2]}} & feature_pix_stream_msb_id_buffer[2]);
	assign feature_pix_stream_last_read_cur = 
		(feature_pix_stream_buffer_rptr[0] & feature_pix_stream_last_buffer[0]) | 
		(feature_pix_stream_buffer_rptr[1] & feature_pix_stream_last_buffer[1]) | 
		(feature_pix_stream_buffer_rptr[2] & feature_pix_stream_last_buffer[2]);
	// 下一读指针指向的特征图数据
	assign feature_pix_stream_data_read_nxt = 
		({feature_pix_stream_data_width{feature_pix_stream_buffer_rptr[0]}} & feature_pix_stream_data_buffer[1]) | 
		({feature_pix_stream_data_width{feature_pix_stream_buffer_rptr[1]}} & feature_pix_stream_data_buffer[2]) | 
		({feature_pix_stream_data_width{feature_pix_stream_buffer_rptr[2]}} & feature_pix_stream_data_buffer[0]);
	assign feature_pix_stream_msb_id_read_nxt = 
		({(clogb2(feature_n_per_clk-1)+1){feature_pix_stream_buffer_rptr[0]}} & feature_pix_stream_msb_id_buffer[1]) | 
		({(clogb2(feature_n_per_clk-1)+1){feature_pix_stream_buffer_rptr[1]}} & feature_pix_stream_msb_id_buffer[2]) | 
		({(clogb2(feature_n_per_clk-1)+1){feature_pix_stream_buffer_rptr[2]}} & feature_pix_stream_msb_id_buffer[0]);
	assign feature_pix_stream_last_read_nxt = 
		(feature_pix_stream_buffer_rptr[0] & feature_pix_stream_last_buffer[1]) | 
		(feature_pix_stream_buffer_rptr[1] & feature_pix_stream_last_buffer[2]) | 
		(feature_pix_stream_buffer_rptr[2] & feature_pix_stream_last_buffer[0]);
	
	// 下一特征图数据项指针
	assign feature_pix_stream_item_ptr_nxt = feature_pix_stream_item_ptr_cur + feature_item_n + 1'b1;
	
	// 特征组
	assign feature_group = 
		{feature_pix_stream_data_read_nxt, feature_pix_stream_data_read_cur} 
			>> (feature_pix_stream_item_ptr_cur * feature_data_width); // 右移并取低位(共feature_n_per_clk种情况)
	
	// 特征组字节有效标志
	genvar feature_group_keep_i;
	generate
		for(feature_group_keep_i = 0;feature_group_keep_i < feature_n_per_clk;feature_group_keep_i = feature_group_keep_i + 1)
		begin
			assign feature_group_keep[(feature_group_keep_i+1)*feature_data_width/8-1:feature_group_keep_i*feature_data_width/8] = 
				{(feature_data_width/8){feature_pos_x_at_last ? 
					(feature_group_keep_i <= feature_map_w[clogb2(feature_n_per_clk-1):0]):1'b1}};
		end
	endgenerate
	
	// 有效特征项个数 - 1
	assign feature_item_n = feature_pos_x_at_last ? feature_map_w[clogb2(feature_n_per_clk-1):0]:(feature_n_per_clk-1);
	
	// 最后1个特征组(标志)
	assign feature_data_last_at_cur = feature_pix_stream_last_read_cur
		& (feature_pix_stream_item_ptr_nxt[clogb2(feature_n_per_clk-1):0] == feature_pix_stream_msb_id_read_cur);
	assign feature_data_last_at_nxt = feature_pix_stream_last_read_nxt
		& feature_pix_stream_item_ptr_nxt[clogb2(feature_n_per_clk-1)+1]
		& (|feature_pix_stream_item_ptr_nxt[clogb2(feature_n_per_clk-1):0])
		& (feature_pix_stream_item_ptr_nxt[clogb2(feature_n_per_clk-1):0] == feature_pix_stream_msb_id_read_nxt);
	assign feature_data_last = feature_data_last_at_cur | feature_data_last_at_nxt;
	
	// 当前的特征图数据项指针
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			feature_pix_stream_item_ptr_cur <= 0;
		else if(s_axis_reg_slice_valid & s_axis_reg_slice_ready)
			feature_pix_stream_item_ptr_cur <= # simulation_delay feature_data_last ? 
				0:feature_pix_stream_item_ptr_nxt[clogb2(feature_n_per_clk-1):0];
	end
	
	// 取最后1个特征数据(指示)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			to_rd_last_feature_data <= 1'b0;
		else
			to_rd_last_feature_data <= # simulation_delay s_axis_reg_slice_valid & s_axis_reg_slice_ready
				& feature_data_last_at_nxt;
	end
	
endmodule
