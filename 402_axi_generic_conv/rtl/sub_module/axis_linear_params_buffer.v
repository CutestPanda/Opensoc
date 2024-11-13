`timescale 1ns / 1ps
/********************************************************************
本模块: AXIS线性参数缓存区

描述:
由AXIS从机输入线性参数流, 写入缓存区
通过MEM读端口获取线性参数

读时延 = 2clk

线性参数(A, B): AX + B

注意：
无

协议:
AXIS SLAVE
MEM READ

作者: 陈家耀
日期: 2024/10/21
********************************************************************/


module axis_linear_params_buffer #(
	parameter integer kernal_param_data_width = 16, // 卷积核参数位宽(8 | 16 | 32 | 64)
	parameter integer max_kernal_n = 512, // 最大的卷积核个数
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 复位线性参数缓存区
	input wire rst_linear_pars_buf,
	// 线性参数缓存区加载完成标志
	output wire linear_pars_buf_load_completed,
	
	// 输入线性参数流(AXIS从机)
	input wire[63:0] s_axis_linear_pars_data,
	input wire[7:0] s_axis_linear_pars_keep,
	input wire s_axis_linear_pars_last, // 表示最后1组线性参数
	input wire[1:0] s_axis_linear_pars_user, // {线性参数是否有效, 线性参数类型(1'b0 -> A, 1'b1 -> B)}
	input wire s_axis_linear_pars_valid,
	output wire s_axis_linear_pars_ready,
	
	// 线性参数获取(MEM读)
	input wire linear_pars_buffer_ren_s0,
	input wire linear_pars_buffer_ren_s1,
	input wire[15:0] linear_pars_buffer_raddr,
	output wire[kernal_param_data_width-1:0] linear_pars_buffer_dout_a,
	output wire[kernal_param_data_width-1:0] linear_pars_buffer_dout_b
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
	
	/** 输入线性参数流 **/
	wire[kernal_param_data_width-1:0] linear_pars[0:64/kernal_param_data_width-1]; // 线性参数
	wire[64/kernal_param_data_width-1:0] linear_pars_vld; // 线性参数有效标志
	
	genvar linear_pars_i;
	generate
		for(linear_pars_i = 0;linear_pars_i < 64/kernal_param_data_width;linear_pars_i = linear_pars_i + 1)
		begin
			assign linear_pars[linear_pars_i] = s_axis_linear_pars_data[(linear_pars_i+1)*kernal_param_data_width-1:
				linear_pars_i*kernal_param_data_width];
			assign linear_pars_vld[linear_pars_i] = s_axis_linear_pars_keep[linear_pars_i*kernal_param_data_width/8];
		end
	endgenerate
	
	/** 缓存区写端口 **/
	wire buffer_wen_a; // 线性参数A缓存区写使能
	wire buffer_wen_b; // 线性参数B缓存区写使能
	reg[clogb2(max_kernal_n-1):0] buffer_waddr; // 每个写地址对应1个线性参数
	wire[kernal_param_data_width-1:0] buffer_din_a; // 线性参数A缓存区写数据
	wire[kernal_param_data_width-1:0] buffer_din_b; // 线性参数B缓存区写数据
	reg[64/kernal_param_data_width-1:0] linear_pars_sel_onehot; // 线性参数选择(独热码)
	reg[clogb2(64/kernal_param_data_width-1):0] linear_pars_sel_bin; // 线性参数选择(二进制码)
	wire[kernal_param_data_width-1:0] linear_pars_buffer_mem_dout_a; // 缓存MEM线性参数A读数据
	wire[kernal_param_data_width-1:0] linear_pars_buffer_mem_dout_b; // 缓存MEM线性参数B读数据
	
	// 握手条件: s_axis_linear_pars_valid & linear_pars_sel_onehot[64/kernal_param_data_width-1]
	assign s_axis_linear_pars_ready = linear_pars_sel_onehot[64/kernal_param_data_width-1];
	
	assign buffer_wen_a = s_axis_linear_pars_valid & (~s_axis_linear_pars_user[0]) & 
		(|(linear_pars_vld & linear_pars_sel_onehot));
	assign buffer_wen_b = s_axis_linear_pars_valid & s_axis_linear_pars_user[0] & 
		(|(linear_pars_vld & linear_pars_sel_onehot));
	assign buffer_din_a = linear_pars[linear_pars_sel_bin];
	assign buffer_din_b = linear_pars[linear_pars_sel_bin];
	
	// 线性参数缓存区写地址
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buffer_waddr <= 0;
		else if(s_axis_linear_pars_valid)
			// (s_axis_linear_pars_last & linear_pars_sel_onehot[64/kernal_param_data_width-1]) ? 0:(buffer_waddr + 1)
			buffer_waddr <= # simulation_delay 
				{(clogb2(max_kernal_n-1)+1){~(s_axis_linear_pars_last &
					linear_pars_sel_onehot[64/kernal_param_data_width-1])}} & (buffer_waddr + 1);
	end
	
	// 线性参数选择(独热码)
	generate
		if(kernal_param_data_width == 64)
		begin
			always @(*)
				linear_pars_sel_onehot = 1'b1;
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					linear_pars_sel_onehot <= {{(64/kernal_param_data_width-1){1'b0}}, 1'b1};
				else if(s_axis_linear_pars_valid)
					linear_pars_sel_onehot <= # simulation_delay {linear_pars_sel_onehot[64/kernal_param_data_width-2:0], 
						linear_pars_sel_onehot[64/kernal_param_data_width-1]};
			end
		end
	endgenerate
	// 线性参数选择(二进制码)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			linear_pars_sel_bin <= 0;
		else if(s_axis_linear_pars_valid)
			// linear_pars_sel_onehot[64/kernal_param_data_width-1] ? 0:(linear_pars_sel_bin + 1)
			linear_pars_sel_bin <= # simulation_delay 
				{(clogb2(64/kernal_param_data_width-1)+1){~linear_pars_sel_onehot[64/kernal_param_data_width-1]}} & 
				(linear_pars_sel_bin + 1);
	end
	
	// 线性参数缓存区MEM
	linear_params_buffer #(
		.kernal_param_data_width(kernal_param_data_width),
		.max_kernal_n(max_kernal_n),
		.simulation_delay(simulation_delay)
	)linear_params_buffer_u(
		.clk(clk),
		
		.buffer_wen_a(buffer_wen_a),
		.buffer_wen_b(buffer_wen_b),
		.buffer_waddr({{(15-clogb2(max_kernal_n-1)){1'b0}}, buffer_waddr}),
		.buffer_din_a(buffer_din_a),
		.buffer_din_b(buffer_din_b),
		
		.buffer_ren(linear_pars_buffer_ren_s0),
		.buffer_raddr(linear_pars_buffer_raddr),
		.buffer_dout_a(linear_pars_buffer_mem_dout_a),
		.buffer_dout_b(linear_pars_buffer_mem_dout_b)
	);
	
	/** 线性参数有效掩码 **/
	reg linear_pars_a_vld; // 线性参数A有效标志
	reg linear_pars_b_vld; // 线性参数B有效标志
	reg linear_pars_a_vld_d; // 对齐到缓存MEM线性参数A读数据的有效标志
	reg linear_pars_b_vld_d; // 对齐到缓存MEM线性参数B读数据的有效标志
	reg[kernal_param_data_width-1:0] linear_pars_buffer_dout_a_regs; // 线性参数A缓存区输出寄存器
	reg[kernal_param_data_width-1:0] linear_pars_buffer_dout_b_regs; // 线性参数B缓存区输出寄存器
	
	assign linear_pars_buffer_dout_a = linear_pars_buffer_dout_a_regs;
	assign linear_pars_buffer_dout_b = linear_pars_buffer_dout_b_regs;
	
	// 线性参数A有效标志
	always @(posedge clk)
	begin
		if(s_axis_linear_pars_valid & s_axis_linear_pars_ready & s_axis_linear_pars_last & (~s_axis_linear_pars_user[0]))
			linear_pars_a_vld <= #simulation_delay s_axis_linear_pars_user[1];
	end
	// 线性参数B有效标志
	always @(posedge clk)
	begin
		if(s_axis_linear_pars_valid & s_axis_linear_pars_ready & s_axis_linear_pars_last & s_axis_linear_pars_user[0])
			linear_pars_b_vld <= #simulation_delay s_axis_linear_pars_user[1];
	end
	
	// 对齐到缓存MEM线性参数A读数据的有效标志
	always @(posedge clk)
	begin
		if(linear_pars_buffer_ren_s0)
			linear_pars_a_vld_d <= # simulation_delay linear_pars_a_vld;
	end
	// 对齐到缓存MEM线性参数B读数据的有效标志
	always @(posedge clk)
	begin
		if(linear_pars_buffer_ren_s0)
			linear_pars_b_vld_d <= # simulation_delay linear_pars_b_vld;
	end
	
	// 线性参数A缓存区输出寄存器
	always @(posedge clk)
	begin
		if(linear_pars_buffer_ren_s1)
			// linear_pars_a_vld_d ? {kernal_param_data_width{1'b0}}:linear_pars_buffer_mem_dout_a
			linear_pars_buffer_dout_a_regs <= # simulation_delay {kernal_param_data_width{linear_pars_a_vld_d}} & 
				linear_pars_buffer_mem_dout_a;
	end
	// 线性参数B缓存区输出寄存器
	always @(posedge clk)
	begin
		if(linear_pars_buffer_ren_s1)
			// linear_pars_b_vld_d ? {kernal_param_data_width{1'b0}}:linear_pars_buffer_mem_dout_b
			linear_pars_buffer_dout_b_regs <= # simulation_delay {kernal_param_data_width{linear_pars_b_vld_d}} & 
				linear_pars_buffer_mem_dout_b;
	end
	
	/** 线性参数缓存区加载状态 **/
	reg linear_pars_a_loaded; // 线性参数A加载完成标志
	reg linear_pars_b_loaded; // 线性参数B加载完成标志
	
	assign linear_pars_buf_load_completed = linear_pars_a_loaded & linear_pars_b_loaded;
	
	// 线性参数A加载完成标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			linear_pars_a_loaded <= 1'b0;
		else if(rst_linear_pars_buf | 
			(s_axis_linear_pars_valid & s_axis_linear_pars_ready & s_axis_linear_pars_last & (~s_axis_linear_pars_user[0])))
			linear_pars_a_loaded <= ~rst_linear_pars_buf;
	end
	// 线性参数B加载完成标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			linear_pars_b_loaded <= 1'b0;
		else if(rst_linear_pars_buf | 
			(s_axis_linear_pars_valid & s_axis_linear_pars_ready & s_axis_linear_pars_last & s_axis_linear_pars_user[0]))
			linear_pars_b_loaded <= ~rst_linear_pars_buf;
	end
	
endmodule
