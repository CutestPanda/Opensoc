`timescale 1ns / 1ps
/********************************************************************
本模块: 卷积单元的输入特征图缓存区

描述:
行缓存MEM: 3组 * (max_feature_map_w * feature_data_width / 64)深度 * (64 + 64 / feature_data_width)位宽
读时延 = 2clk

写缓存区时以64位数据为单位, 可选择写某些行; 读缓存区时以特征点为单位, 只能将3行同时读出

注意：
无

协议:
MEM READ/WRITE

作者: 陈家耀
日期: 2024/10/18
********************************************************************/


module conv_in_feature_map_buffer #(
	parameter integer feature_data_width = 16, // 特征点位宽(8 | 16 | 32 | 64)
	parameter integer max_feature_map_w = 512, // 最大的输入特征图宽度
	parameter line_buffer_mem_type = "bram", // 行缓存MEM类型("bram" | "lutram" | "auto")
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟
	input wire clk,
	
	// 缓存区写端口
	input wire[2:0] buffer_wen,
	input wire[15:0] buffer_waddr, // 每个写地址对应64位数据
	input wire[63:0] buffer_din, // 64位数据
	input wire[64/feature_data_width-1:0] buffer_din_last, // 行尾标志
	
	// 缓存区读端口
	input wire buffer_ren_s0,
	input wire buffer_ren_s1,
	input wire[15:0] buffer_raddr, // 每个读地址对应1个特征点
	output wire[feature_data_width-1:0] buffer_dout_r0, // 行#0特征点
	output wire[feature_data_width-1:0] buffer_dout_r1, // 行#1特征点
	output wire[feature_data_width-1:0] buffer_dout_r2, // 行#2特征点
	output wire buffer_dout_last_r0, // 行#0行尾标志
	output wire buffer_dout_last_r1, // 行#1行尾标志
	output wire buffer_dout_last_r2 // 行#2行尾标志
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
	localparam integer line_buffer_mem_data_width = 64 + 64 / feature_data_width; // 行缓存MEM位宽
	localparam integer line_buffer_mem_depth = max_feature_map_w * feature_data_width / 64; // 行缓存MEM深度
	localparam line_buffer_mem_type_confirmed = (line_buffer_mem_type == "auto") ? 
		((line_buffer_mem_depth <= 64) ? "lutram":"bram"):line_buffer_mem_type; // 确定使用的行缓存MEM类型
	
	/** 行缓存MEM **/
	// MEM写端口
    wire[2:0] line_buffer_mem_wen_a;
    wire[clogb2(line_buffer_mem_depth-1):0] line_buffer_mem_addr_a[2:0];
    wire[line_buffer_mem_data_width-1:0] line_buffer_mem_din_a[2:0]; // {行尾标志, 64位数据}
    // MEM读端口
	wire[clogb2(line_buffer_mem_depth-1):0] line_buffer_mem_raddr;
    wire[2:0] line_buffer_mem_ren_b;
    wire[clogb2(line_buffer_mem_depth-1):0] line_buffer_mem_addr_b[2:0];
    wire[line_buffer_mem_data_width-1:0] line_buffer_mem_dout_b[2:0]; // {行尾标志, 64位数据}
	
	assign line_buffer_mem_wen_a = buffer_wen;
	assign line_buffer_mem_addr_a[2] = buffer_waddr[clogb2(line_buffer_mem_depth-1):0];
	assign line_buffer_mem_addr_a[1] = buffer_waddr[clogb2(line_buffer_mem_depth-1):0];
	assign line_buffer_mem_addr_a[0] = buffer_waddr[clogb2(line_buffer_mem_depth-1):0];
	assign line_buffer_mem_din_a[2] = {buffer_din_last, buffer_din};
	assign line_buffer_mem_din_a[1] = {buffer_din_last, buffer_din};
	assign line_buffer_mem_din_a[0] = {buffer_din_last, buffer_din};
	
	assign line_buffer_mem_ren_b = {3{buffer_ren_s0}};
	assign line_buffer_mem_addr_b[2] = line_buffer_mem_raddr;
	assign line_buffer_mem_addr_b[1] = line_buffer_mem_raddr;
	assign line_buffer_mem_addr_b[0] = line_buffer_mem_raddr;
	
	assign line_buffer_mem_raddr = buffer_raddr[clogb2(max_feature_map_w-1):
		((feature_data_width == 64) ? 0:(clogb2(64/feature_data_width-1)+1))];
	
	// 简单双口RAM
	genvar line_buffer_mem_i;
	
	generate
		for(line_buffer_mem_i = 0;line_buffer_mem_i < 3;line_buffer_mem_i = line_buffer_mem_i + 1)
		begin
			if(line_buffer_mem_type_confirmed == "bram")
			begin
				bram_simple_dual_port #(
					.style("LOW_LATENCY"),
					.mem_width(line_buffer_mem_data_width),
					.mem_depth(line_buffer_mem_depth),
					.INIT_FILE("no_init"),
					.byte_write_mode("false"),
					.simulation_delay(simulation_delay)
				)line_buffer_mem(
					.clk(clk),
					
					.wen_a(line_buffer_mem_wen_a[line_buffer_mem_i]),
					.addr_a(line_buffer_mem_addr_a[line_buffer_mem_i]),
					.din_a(line_buffer_mem_din_a[line_buffer_mem_i]),
					
					.ren_b(line_buffer_mem_ren_b[line_buffer_mem_i]),
					.addr_b(line_buffer_mem_addr_b[line_buffer_mem_i]),
					.dout_b(line_buffer_mem_dout_b[line_buffer_mem_i])
				);
			end
			else
			begin
				dram_simple_dual_port #(
					.mem_width(line_buffer_mem_data_width),
					.mem_depth(line_buffer_mem_depth),
					.INIT_FILE("no_init"),
					.use_output_register("true"),
					.output_register_init_v(0),
					.simulation_delay(simulation_delay)
				)line_buffer_mem(
					.clk(clk),
					.rst_n(1'b1), // 不必复位输出寄存器
					
					.wen_a(line_buffer_mem_wen_a[line_buffer_mem_i]),
					.addr_a(line_buffer_mem_addr_a[line_buffer_mem_i]),
					.din_a(line_buffer_mem_din_a[line_buffer_mem_i]),
					
					.ren_b(line_buffer_mem_ren_b[line_buffer_mem_i]),
					.addr_b(line_buffer_mem_addr_b[line_buffer_mem_i]),
					.dout_b(line_buffer_mem_dout_b[line_buffer_mem_i])
				);

			end
		end
	endgenerate
	
	/** 处理读数据 **/
	reg[clogb2(max_feature_map_w-1):0] buffer_raddr_d; // 延迟1clk的行缓存区读地址
	reg[feature_data_width:0] buffer_dout_regs[2:0]; // 行缓存区读数据寄存器({行尾标志, 特征点})
	
	assign {buffer_dout_last_r2, buffer_dout_r2} = buffer_dout_regs[2];
	assign {buffer_dout_last_r1, buffer_dout_r1} = buffer_dout_regs[1];
	assign {buffer_dout_last_r0, buffer_dout_r0} = buffer_dout_regs[0];
	
	// 延迟1clk的行缓存区读地址
	always @(posedge clk)
	begin
		if(buffer_ren_s0)
			buffer_raddr_d <= # simulation_delay buffer_raddr[clogb2(max_feature_map_w-1):0];
	end
	
	// 行缓存区读数据寄存器
	genvar buffer_dout_i;
	generate
		for(buffer_dout_i = 0;buffer_dout_i < 3;buffer_dout_i = buffer_dout_i + 1)
		begin
			// 特征点
			always @(posedge clk)
			begin
				if(buffer_ren_s1)
					buffer_dout_regs[buffer_dout_i][feature_data_width-1:0] <= # simulation_delay 
						line_buffer_mem_dout_b[buffer_dout_i][63:0] >> 
							(buffer_raddr_d[clogb2(64/feature_data_width-1):0] * feature_data_width * (feature_data_width != 64));
			end
			// 行尾标志
			always @(posedge clk)
			begin
				if(buffer_ren_s1)
					buffer_dout_regs[buffer_dout_i][feature_data_width] <= # simulation_delay 
						line_buffer_mem_dout_b[buffer_dout_i][line_buffer_mem_data_width-1:64] >> 
							(buffer_raddr_d[clogb2(64/feature_data_width-1):0] * (feature_data_width != 64));
			end
		end
	endgenerate
	
endmodule
