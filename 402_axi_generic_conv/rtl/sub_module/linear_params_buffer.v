`timescale 1ns / 1ps
/********************************************************************
本模块: 卷积单元的线性参数缓存区

描述:
用于缓存线性参数

线性参数缓存MEM: max_kernal_n深度 * (2*kernal_param_data_width)位宽
读时延 = 1clk

线性参数(A, B): AX + B

注意：
无

协议:
MEM READ/WRITE

作者: 陈家耀
日期: 2024/10/19
********************************************************************/


module linear_params_buffer #(
	parameter integer kernal_param_data_width = 16, // 卷积核参数位宽(8 | 16 | 32 | 64)
	parameter integer max_kernal_n = 512, // 最大的卷积核个数
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟
	input wire clk,
	
	// 线性参数缓存区写端口
	input wire buffer_wen_a, // 线性参数A缓存区写使能
	input wire buffer_wen_b, // 线性参数B缓存区写使能
	input wire[15:0] buffer_waddr, // 每个写地址对应1个线性参数
	input wire[kernal_param_data_width-1:0] buffer_din_a, // 线性参数A缓存区写数据
	input wire[kernal_param_data_width-1:0] buffer_din_b, // 线性参数B缓存区写数据
	
	// 线性参数缓存区读端口
	input wire buffer_ren,
	input wire[15:0] buffer_raddr, // 每个读地址对应1个线性参数
	output wire[kernal_param_data_width-1:0] buffer_dout_a, // 线性参数A缓存区读数据
	output wire[kernal_param_data_width-1:0] buffer_dout_b // 线性参数B缓存区读数据
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
	
	/** 线性参数缓存MEM **/
	wire[kernal_param_data_width*2-1:0] linear_pars_buffer_mem_dout; // 线性参数缓存MEM读数据
	
	assign {buffer_dout_b, buffer_dout_a} = linear_pars_buffer_mem_dout;
	
	// 简单双口RAM
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(2*kernal_param_data_width),
		.mem_depth(max_kernal_n),
		.INIT_FILE("no_init"),
		.byte_write_mode("true"),
		.simulation_delay(simulation_delay)
	)linear_pars_buffer_mem(
		.clk(clk),
		
		.wen_a({{(kernal_param_data_width/8){buffer_wen_b}}, 
			{(kernal_param_data_width/8){buffer_wen_a}}}),
		.addr_a(buffer_waddr[clogb2(max_kernal_n-1):0]),
		.din_a({buffer_din_b, buffer_din_a}),
		
		.ren_b(buffer_ren),
		.addr_b(buffer_raddr[clogb2(max_kernal_n-1):0]),
		.dout_b(linear_pars_buffer_mem_dout)
	);
	
endmodule
