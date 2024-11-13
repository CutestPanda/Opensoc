`timescale 1ns / 1ps
/********************************************************************
本模块: 卷积单元的卷积核参数缓存区

描述:
用于缓存卷积核参数
可存储1个多通道卷积核

卷积核参数缓存MEM: max_feature_map_chn_n深度 * (9*kernal_param_data_width)位宽
读时延 = 1clk

注意：
无

协议:
MEM READ/WRITE

作者: 陈家耀
日期: 2024/10/22
********************************************************************/


module kernal_params_buffer #(
	parameter integer kernal_param_data_width = 16, // 卷积核参数位宽(8 | 16 | 32 | 64)
	parameter integer max_feature_map_chn_n = 512, // 最大的输入特征图通道数
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟
	input wire clk,
	
	// 卷积核参数缓存区写端口
	input wire buffer_wen,
	input wire[15:0] buffer_waddr, // 每个写地址对应1个单通道卷积核
	input wire[kernal_param_data_width*9-1:0] buffer_din,
	
	// 卷积核参数缓存区读端口
	input wire buffer_ren,
	input wire[15:0] buffer_raddr, // 每个读地址对应1个单通道卷积核
	output wire[kernal_param_data_width*9-1:0] buffer_dout // 卷积核参数缓存区读数据
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
	
	/** 内部配置 **/
	localparam sim_mode = "false"; // 是否处于仿真模式
	
	/** 卷积核参数缓存MEM **/
	wire[kernal_param_data_width*9-1:0] kernal_pars_buffer_mem_dout; // 卷积核参数缓存MEM读数据
	
	assign buffer_dout = kernal_pars_buffer_mem_dout;
	
	// 简单双口RAM
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(9*kernal_param_data_width),
		.mem_depth(max_feature_map_chn_n),
		.INIT_FILE((sim_mode == "true") ? "default":"no_init"),
		.byte_write_mode("false"),
		.simulation_delay(simulation_delay)
	)kernal_pars_buffer_mem(
		.clk(clk),
		
		.wen_a(buffer_wen),
		.addr_a(buffer_waddr[clogb2(max_feature_map_chn_n-1):0]),
		.din_a(buffer_din),
		
		.ren_b(buffer_ren),
		.addr_b(buffer_raddr[clogb2(max_feature_map_chn_n-1):0]),
		.dout_b(kernal_pars_buffer_mem_dout)
	);
	
endmodule
