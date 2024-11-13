`timescale 1ns / 1ps
/********************************************************************
本模块: 加法树

描述:

   加法输入数量   流水线级数
-------------------------------
        2             1
		4             2
		8             3
		16            4

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/10/30
********************************************************************/


module add_tree_2_4_8_16 #(
    parameter integer add_input_n = 4, // 加法输入数量
	parameter integer add_width = 16, // 加法位宽
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 加法输入
	input wire[add_input_n*add_width-1:0] add_in,
	input wire add_in_vld,
	input wire add_in_last,
	
	// 加法输出
	output wire[add_width-1:0] add_out,
	output wire add_out_vld,
	output wire add_out_last
);
    
    /** 第1级流水线 **/
	wire[add_width-1:0] add_s0_in[0:15];
	wire add_s0_in_vld;
	wire add_s0_in_last;
	reg[add_width-1:0] add_s0_out[0:7];
	reg add_s0_out_vld;
	reg add_s0_out_last;
	
	genvar add_s0_i;
	generate
		for(add_s0_i = 0;add_s0_i < 8;add_s0_i = add_s0_i + 1)
		begin
			always @(posedge clk)
			begin
				if(add_s0_in_vld)
					add_s0_out[add_s0_i] <= # simulation_delay add_s0_in[add_s0_i*2] + add_s0_in[add_s0_i*2+1];
			end
		end
	endgenerate
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			add_s0_out_vld <= 1'b0;
		else
			add_s0_out_vld <= # simulation_delay add_s0_in_vld;
	end
	
	always @(posedge clk)
	begin
		if(add_s0_in_vld)
			add_s0_out_last <= # simulation_delay add_s0_in_last;
	end
	
	/** 第2级流水线 **/
	wire[add_width-1:0] add_s1_in[0:7];
	wire add_s1_in_vld;
	wire add_s1_in_last;
	reg[add_width-1:0] add_s1_out[0:3];
	reg add_s1_out_vld;
	reg add_s1_out_last;
	
	genvar add_s1_i;
	generate
		for(add_s1_i = 0;add_s1_i < 4;add_s1_i = add_s1_i + 1)
		begin
			always @(posedge clk)
			begin
				if(add_s1_in_vld)
					add_s1_out[add_s1_i] <= # simulation_delay add_s1_in[add_s1_i*2] + add_s1_in[add_s1_i*2+1];
			end
		end
	endgenerate
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			add_s1_out_vld <= 1'b0;
		else
			add_s1_out_vld <= # simulation_delay add_s1_in_vld;
	end
	
	always @(posedge clk)
	begin
		if(add_s1_in_vld)
			add_s1_out_last <= # simulation_delay add_s1_in_last;
	end
	
	/** 第3级流水线 **/
	wire[add_width-1:0] add_s2_in[0:3];
	wire add_s2_in_vld;
	wire add_s2_in_last;
	reg[add_width-1:0] add_s2_out[0:1];
	reg add_s2_out_vld;
	reg add_s2_out_last;
	
	genvar add_s2_i;
	generate
		for(add_s2_i = 0;add_s2_i < 2;add_s2_i = add_s2_i + 1)
		begin
			always @(posedge clk)
			begin
				if(add_s2_in_vld)
					add_s2_out[add_s2_i] <= # simulation_delay add_s2_in[add_s2_i*2] + add_s2_in[add_s2_i*2+1];
			end
		end
	endgenerate
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			add_s2_out_vld <= 1'b0;
		else
			add_s2_out_vld <= # simulation_delay add_s2_in_vld;
	end
	
	always @(posedge clk)
	begin
		if(add_s2_in_vld)
			add_s2_out_last <= # simulation_delay add_s2_in_last;
	end
	
	/** 第4级流水线 **/
	wire[add_width-1:0] add_s3_in[0:1];
	wire add_s3_in_vld;
	wire add_s3_in_last;
	reg[add_width-1:0] add_s3_out;
	reg add_s3_out_vld;
	reg add_s3_out_last;
	
	assign add_out = add_s3_out;
	assign add_out_vld = add_s3_out_vld;
	assign add_out_last = add_s3_out_last;
	
	always @(posedge clk)
	begin
		if(add_s3_in_vld)
			add_s3_out <= # simulation_delay add_s3_in[0] + add_s3_in[1];
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			add_s3_out_vld <= 1'b0;
		else
			add_s3_out_vld <= # simulation_delay add_s3_in_vld;
	end
	
	always @(posedge clk)
	begin
		if(add_s3_in_vld)
			add_s3_out_last <= # simulation_delay add_s3_in_last;
	end
	
	/** 加法树输入 **/
	genvar add_s0_in_i;
	generate
		for(add_s0_in_i = 0;add_s0_in_i < 16;add_s0_in_i = add_s0_in_i + 1)
		begin
			if(add_input_n == 16)
				assign add_s0_in[add_s0_in_i] = add_in[(add_s0_in_i+1)*add_width-1:add_s0_in_i*add_width];
			else
				assign add_s0_in[add_s0_in_i] = {add_width{1'bx}};
		end
	endgenerate
	
	genvar add_s1_in_i;
	generate
		for(add_s1_in_i = 0;add_s1_in_i < 8;add_s1_in_i = add_s1_in_i + 1)
		begin
			if(add_input_n == 8)
				assign add_s1_in[add_s1_in_i] = add_in[(add_s1_in_i+1)*add_width-1:add_s1_in_i*add_width];
			else
				assign add_s1_in[add_s1_in_i] = add_s0_out[add_s1_in_i];
		end
	endgenerate
	
	genvar add_s2_in_i;
	generate
		for(add_s2_in_i = 0;add_s2_in_i < 4;add_s2_in_i = add_s2_in_i + 1)
		begin
			if(add_input_n == 4)
				assign add_s2_in[add_s2_in_i] = add_in[(add_s2_in_i+1)*add_width-1:add_s2_in_i*add_width];
			else
				assign add_s2_in[add_s2_in_i] = add_s1_out[add_s2_in_i];
		end
	endgenerate
	
	genvar add_s3_in_i;
	generate
		for(add_s3_in_i = 0;add_s3_in_i < 2;add_s3_in_i = add_s3_in_i + 1)
		begin
			if(add_input_n == 2)
				assign add_s3_in[add_s3_in_i] = add_in[(add_s3_in_i+1)*add_width-1:add_s3_in_i*add_width];
			else
				assign add_s3_in[add_s3_in_i] = add_s2_out[add_s3_in_i];
		end
	endgenerate
	
	assign add_s0_in_vld = (add_input_n == 16) ? add_in_vld:1'b0;
	assign add_s1_in_vld = (add_input_n == 8) ? add_in_vld:add_s0_out_vld;
	assign add_s2_in_vld = (add_input_n == 4) ? add_in_vld:add_s1_out_vld;
	assign add_s3_in_vld = (add_input_n == 2) ? add_in_vld:add_s2_out_vld;
	
	assign add_s0_in_last = (add_input_n == 16) ? add_in_last:1'bx;
	assign add_s1_in_last = (add_input_n == 8) ? add_in_last:add_s0_out_last;
	assign add_s2_in_last = (add_input_n == 4) ? add_in_last:add_s1_out_last;
	assign add_s3_in_last = (add_input_n == 2) ? add_in_last:add_s2_out_last;
	
endmodule
