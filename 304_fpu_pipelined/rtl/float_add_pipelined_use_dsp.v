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
本模块: 全流水的单精度浮点加法器(使用DSP)

描述:
4级流水线完成对阶、尾数相加、标准化

标准化进行右规时有效尾数的末位恒置1

注意：
如何优化时序和面积???

协议:
无

作者: 陈家耀
日期: 2024/12/02
********************************************************************/


module float_add_pipelined_use_dsp #(
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 浮点加法器输入
	input wire[31:0] float_in_a,
	input wire[31:0] float_in_b,
	input wire float_in_valid,
	
	// 浮点加法器输出
	output wire[31:0] float_out,
	output wire[1:0] float_ovf, // {上溢标志, 下溢标志}
	output wire float_out_valid
);
    
	/** 浮点数输入 **/
	wire in_float_sgn[0:1]; // 符号位
	wire[7:0] in_float_exp[0:1]; // 阶码
	wire[22:0] in_float_frac[0:1]; // 尾数
	
	assign {in_float_sgn[0], in_float_exp[0], in_float_frac[0]} = float_in_a;
	assign {in_float_sgn[1], in_float_exp[1], in_float_frac[1]} = float_in_b;
	
	/**
	第1级流水线
	
	将定点尾数从原码转为补码
	对阶: 小阶向大阶看齐
	**/
	wire signed[27:0] float_a_frac_fixed; // 浮点数A定点化后的尾数({双符号位, 24位定点尾数, 双保护位})
	wire signed[27:0] float_b_frac_fixed; // 浮点数B定点化后的尾数(有符号, 双符号位)
	wire float_a_exp_geqth_b; // 浮点数A的阶码 >= 浮点数B的阶码(标志)
	wire[7:0] max_exp; // 最大的阶码
	wire[7:0] float_a_exp_sub_b; // 浮点数A的阶码 - 浮点数B的阶码
	wire[7:0] float_b_exp_sub_a; // 浮点数B的阶码 - 浮点数A的阶码
	wire[4:0] float_a_ath_rsh_n; // 浮点数A做算术右移的位数
	wire[4:0] float_b_ath_rsh_n; // 浮点数B做算术右移的位数
	reg[7:0] exp_aligned; // 对齐后的阶码
	reg signed[27:0] float_a_frac_fixed_rsh; // 做算术右移后的浮点数A定点尾数({双符号位, 24位定点尾数, 双保护位})
	reg signed[27:0] float_b_frac_fixed_rsh; // 做算术右移后的浮点数B定点尾数({双符号位, 24位定点尾数, 双保护位})
	reg float_in_valid_d; // 延迟1clk的浮点乘法器输入有效指示
	
	// 定点尾数 = 1.XXX或-1.XXX, 需要将原码转换为补码
	assign float_a_frac_fixed[27:25] = {{2{in_float_sgn[0]}}, ~in_float_sgn[0]};
	assign float_a_frac_fixed[24:2] = ({23{in_float_sgn[0]}} ^ in_float_frac[0]) + in_float_sgn[0];
	assign float_a_frac_fixed[1:0] = 2'b00;
	
	assign float_b_frac_fixed[27:25] = {{2{in_float_sgn[1]}}, ~in_float_sgn[1]};
	assign float_b_frac_fixed[24:2] = ({23{in_float_sgn[1]}} ^ in_float_frac[1]) + in_float_sgn[1];
	assign float_b_frac_fixed[1:0] = 2'b00;
	
	assign float_a_exp_geqth_b = in_float_exp[0] >= in_float_exp[1];
	assign max_exp = float_a_exp_geqth_b ? in_float_exp[0]:in_float_exp[1];
	
	assign float_a_exp_sub_b = in_float_exp[0] - in_float_exp[1];
	assign float_b_exp_sub_a = in_float_exp[1] - in_float_exp[0];
	// 浮点数A的阶码 < 浮点数B的阶码时, 对浮点数A定点尾数做算术右移, 最大右移位数限制到31位
	assign float_a_ath_rsh_n = {5{~float_a_exp_geqth_b}} & (float_b_exp_sub_a[4:0] | {5{|float_b_exp_sub_a[7:5]}});
	// 浮点数A的阶码 >= 浮点数B的阶码时, 对浮点数B定点尾数做算术右移, 最大右移位数限制到31位
	assign float_b_ath_rsh_n = {5{float_a_exp_geqth_b}} & (float_a_exp_sub_b[4:0] | {5{|float_a_exp_sub_b[7:5]}});
	
	// 对齐后的阶码
	always @(posedge clk)
	begin
		if(float_in_valid)
			exp_aligned <= # simulation_delay max_exp;
	end
	
	// 做算术右移后的浮点数A定点尾数
	always @(posedge clk)
	begin
		if(float_in_valid)
			float_a_frac_fixed_rsh <= # simulation_delay float_a_frac_fixed >>> float_a_ath_rsh_n;
	end
	// 做算术右移后的浮点数B定点尾数
	always @(posedge clk)
	begin
		if(float_in_valid)
			float_b_frac_fixed_rsh <= # simulation_delay float_b_frac_fixed >>> float_b_ath_rsh_n;
	end
	
	// 延迟1clk的浮点乘法器输入有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			float_in_valid_d <= 1'b0;
		else
			float_in_valid_d <= # simulation_delay float_in_valid;
	end
	
	/**
	第2级流水线
	
	定点尾数相加
	**/
	reg[7:0] exp_aligned_d; // 延迟1clk的对齐后阶码
	wire signed[27:0] float_frac_fixed_add_comb; // 定点尾数相加(加法器输出)
	reg signed[27:0] float_frac_fixed_add_res; // 定点尾数相加结果({26位定点尾数(Q23, 范围为(-4, 4)), 双保护位})
	reg[22:0] float_lsh_n_onehot; // 浮点左规情形独热码(左规1~23位)
	reg float_frac_fixed_too_small; // 定点尾数过小(标志)
	reg float_frac_fixed_add_res_ovf; // 定点尾数相加结果溢出(标志)
	reg float_frac_fixed_zero; // 定点尾数等于0(标志)
	reg float_in_valid_d2; // 延迟2clk的浮点乘法器输入有效指示
	
	assign float_frac_fixed_add_comb = float_a_frac_fixed_rsh + float_b_frac_fixed_rsh;
	
	// 延迟1clk的对齐后阶码
	always @(posedge clk)
	begin
		if(float_in_valid_d)
			exp_aligned_d <= # simulation_delay exp_aligned;
	end
	
	// 定点尾数相加结果
	always @(posedge clk)
	begin
		if(float_in_valid_d)
			float_frac_fixed_add_res <= # simulation_delay float_frac_fixed_add_comb;
	end
	
	// 浮点左规情形独热码
	always @(posedge clk)
	begin
		if(float_in_valid_d)
			float_lsh_n_onehot <= # simulation_delay {
				float_frac_fixed_add_comb[2] & (~(|float_frac_fixed_add_comb[24:3])), // 左规23位
				float_frac_fixed_add_comb[3] & (~(|float_frac_fixed_add_comb[24:4])), // 左规22位
				float_frac_fixed_add_comb[4] & (~(|float_frac_fixed_add_comb[24:5])), // 左规21位
				float_frac_fixed_add_comb[5] & (~(|float_frac_fixed_add_comb[24:6])), // 左规20位
				float_frac_fixed_add_comb[6] & (~(|float_frac_fixed_add_comb[24:7])), // 左规19位
				float_frac_fixed_add_comb[7] & (~(|float_frac_fixed_add_comb[24:8])), // 左规18位
				float_frac_fixed_add_comb[8] & (~(|float_frac_fixed_add_comb[24:9])), // 左规17位
				float_frac_fixed_add_comb[9] & (~(|float_frac_fixed_add_comb[24:10])), // 左规16位
				float_frac_fixed_add_comb[10] & (~(|float_frac_fixed_add_comb[24:11])), // 左规15位
				float_frac_fixed_add_comb[11] & (~(|float_frac_fixed_add_comb[24:12])), // 左规14位
				float_frac_fixed_add_comb[12] & (~(|float_frac_fixed_add_comb[24:13])), // 左规13位
				float_frac_fixed_add_comb[13] & (~(|float_frac_fixed_add_comb[24:14])), // 左规12位
				float_frac_fixed_add_comb[14] & (~(|float_frac_fixed_add_comb[24:15])), // 左规11位
				float_frac_fixed_add_comb[15] & (~(|float_frac_fixed_add_comb[24:16])), // 左规10位
				float_frac_fixed_add_comb[16] & (~(|float_frac_fixed_add_comb[24:17])), // 左规9位
				float_frac_fixed_add_comb[17] & (~(|float_frac_fixed_add_comb[24:18])), // 左规8位
				float_frac_fixed_add_comb[18] & (~(|float_frac_fixed_add_comb[24:19])), // 左规7位
				float_frac_fixed_add_comb[19] & (~(|float_frac_fixed_add_comb[24:20])), // 左规6位
				float_frac_fixed_add_comb[20] & (~(|float_frac_fixed_add_comb[24:21])), // 左规5位
				float_frac_fixed_add_comb[21] & (~(|float_frac_fixed_add_comb[24:22])), // 左规4位
				float_frac_fixed_add_comb[22] & (~(|float_frac_fixed_add_comb[24:23])), // 左规3位
				float_frac_fixed_add_comb[23] & (~(|float_frac_fixed_add_comb[24])), // 左规2位
				float_frac_fixed_add_comb[24] // 左规1位
			};
	end
	
	// 定点尾数过小(标志)
	always @(posedge clk)
	begin
		if(float_in_valid_d)
			float_frac_fixed_too_small <= # simulation_delay 
				// 当定点尾数相加结果落在范围(-1, 1)时过小
				// (float_frac_fixed_add_comb[27:25] == 3'b111) | (float_frac_fixed_add_comb[27:25] == 3'b000)
				(&float_frac_fixed_add_comb[27:25]) | (~(|float_frac_fixed_add_comb[27:25]));
	end
	
	// 定点尾数相加结果溢出(标志)
	always @(posedge clk)
	begin
		if(float_in_valid_d)
			// 当定点尾数相加结果落在范围[2, 4)或(-4, -2]时发生溢出
			float_frac_fixed_add_res_ovf <= # simulation_delay float_frac_fixed_add_comb[27] ^ float_frac_fixed_add_comb[26];
	end
	
	// 定点尾数等于0(标志)
	always @(posedge clk)
	begin
		if(float_in_valid_d)
			// 零判定时不包含保护位
			float_frac_fixed_zero <= # simulation_delay ~(|float_frac_fixed_add_comb[27:2]);
	end
	
	// 延迟2clk的浮点乘法器输入有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			float_in_valid_d2 <= 1'b0;
		else
			float_in_valid_d2 <= # simulation_delay float_in_valid_d;
	end
	
	/**
	第3级流水线
	
	标准化: 预左规(左归1~6位或7~23位), 预右规
	**/
	wire signed[9:0] exp_nml_incr; // 标准化阶码增量
	wire signed[9:0] float_exp_nml; // 标准化后的阶码
	wire float_up_ovf_flag; // 上溢标志
	wire float_down_ovf_flag; // 下溢标志
	reg[7:0] out_float_exp; // 输出浮点数的阶码
	reg[1:0] out_float_ovf; // 输出浮点数的溢出标志({上溢标志, 下溢标志})
	wire[42:0] lmnl_mul_res; // 左归乘法器输出
	wire signed[27:0] float_frac_lnml_7_to_23; // 左归7~23位的定点尾数
	reg signed[27:0] float_frac_lnml_1_to_6; // 左归1~6位的定点尾数
	reg signed[27:0] float_frac_rnml_1; // 右归1位的定点尾数
	reg signed[27:0] float_frac_org; // 原始的定点尾数
	reg float_frac_fixed_too_small_d; // 延迟1clk的定点尾数过小(标志)
	reg float_frac_fixed_add_res_ovf_d; // 延迟1clk的定点尾数相加结果溢出(标志)
	reg lnml_n_gth_6; // 左归位数 > 6(标志)
	reg float_in_valid_d3; // 延迟3clk的浮点乘法器输入有效指示
	
	assign exp_nml_incr = 
		// 溢出时右规1位
		({10{float_frac_fixed_add_res_ovf}} & 10'sd1) | 
		// 过小且非0时左规1~23位
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[0]}} & (-10'sd1)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[1]}} & (-10'sd2)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[2]}} & (-10'sd3)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[3]}} & (-10'sd4)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[4]}} & (-10'sd5)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[5]}} & (-10'sd6)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[6]}} & (-10'sd7)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[7]}} & (-10'sd8)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[8]}} & (-10'sd9)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[9]}} & (-10'sd10)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[10]}} & (-10'sd11)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[11]}} & (-10'sd12)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[12]}} & (-10'sd13)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[13]}} & (-10'sd14)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[14]}} & (-10'sd15)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[15]}} & (-10'sd16)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[16]}} & (-10'sd17)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[17]}} & (-10'sd18)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[18]}} & (-10'sd19)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[19]}} & (-10'sd20)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[20]}} & (-10'sd21)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[21]}} & (-10'sd22)) | 
		({10{float_frac_fixed_too_small & float_lsh_n_onehot[22]}} & (-10'sd23));
	assign float_exp_nml = {2'b00, exp_aligned_d} + exp_nml_incr;
	
	assign float_up_ovf_flag = float_exp_nml[9:8] == 2'b01;
	assign float_down_ovf_flag = float_exp_nml[9] | float_frac_fixed_zero;
	
	assign float_frac_lnml_7_to_23 = {lmnl_mul_res[20:0], 7'd0};
	
	// 输出浮点数的阶码
	always @(posedge clk)
	begin
		if(float_in_valid_d2)
			out_float_exp <= # simulation_delay {8{~float_down_ovf_flag}} & ({8{float_up_ovf_flag}} | float_exp_nml[7:0]);
	end
	
	// 输出浮点数的溢出标志
	always @(posedge clk)
	begin
		if(float_in_valid_d2)
			out_float_ovf <= # simulation_delay {float_up_ovf_flag, float_down_ovf_flag};
	end
	
	// 左归1~6位的定点尾数
	always @(posedge clk)
	begin
		if(float_in_valid_d2)
			float_frac_lnml_1_to_6 <= # simulation_delay 
				({28{float_lsh_n_onehot[0]}} & (float_frac_fixed_add_res << 1)) | 
				({28{float_lsh_n_onehot[1]}} & (float_frac_fixed_add_res << 2)) | 
				({28{float_lsh_n_onehot[2]}} & (float_frac_fixed_add_res << 3)) | 
				({28{float_lsh_n_onehot[3]}} & (float_frac_fixed_add_res << 4)) | 
				({28{float_lsh_n_onehot[4]}} & (float_frac_fixed_add_res << 5)) | 
				({28{float_lsh_n_onehot[5]}} & (float_frac_fixed_add_res << 6));
	end
	
	// 右归1位的定点尾数
	always @(posedge clk)
	begin
		if(float_in_valid_d2)
			// 右规时有效尾数的末位恒置1
			float_frac_rnml_1 <= # simulation_delay (float_frac_fixed_add_res >>> 1) | {26'h000_0001, 2'b00};
	end
	
	// 原始的定点尾数
	always @(posedge clk)
	begin
		if(float_in_valid_d2)
			float_frac_org <= # simulation_delay float_frac_fixed_add_res;
	end
	
	// 延迟1clk的定点尾数过小(标志)
	always @(posedge clk)
	begin
		if(float_in_valid_d2)
			float_frac_fixed_too_small_d <= # simulation_delay float_frac_fixed_too_small;
	end
	
	// 延迟1clk的定点尾数相加结果溢出(标志)
	always @(posedge clk)
	begin
		if(float_in_valid_d2)
			float_frac_fixed_add_res_ovf_d <= # simulation_delay float_frac_fixed_add_res_ovf;
	end
	
	// 左归位数 > 6(标志)
	always @(posedge clk)
	begin
		if(float_in_valid_d2)
			lnml_n_gth_6 <= # simulation_delay ~(|float_lsh_n_onehot[5:0]);
	end
	
	// 延迟3clk的浮点乘法器输入有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			float_in_valid_d3 <= 1'b0;
		else
			float_in_valid_d3 <= # simulation_delay float_in_valid_d2;
	end
	
	// 左归乘法器
	mul #(
		.op_a_width(25),
		.op_b_width(18),
		.output_width(43),
		.simulation_delay(simulation_delay)
	)lmnl_mul(
		.clk(clk),
		
		.ce_s0_mul(float_in_valid_d2),
		
		// 左规7~23位
		.op_a({4'd0, float_frac_fixed_add_res[20:0]}),
		.op_b({1'b0, float_lsh_n_onehot[22:6]}),
		
		.res(lmnl_mul_res)
	);
	
	/**
	第4级流水线
	
	标准化: 左规/右规
	**/
	reg[7:0] out_float_exp_d; // 延迟1clk的输出浮点数的阶码
	reg[1:0] out_float_ovf_d; // 延迟1clk的输出浮点数的溢出标志({上溢标志, 下溢标志})
	wire signed[27:0] float_frac_nml; // 标准化后的尾数({26位定点尾数(Q23, 范围为(-2, -1] U [1, 2)), 双保护位})
	wire[27:0] float_frac_nml_abs; // 取绝对值后的标准化尾数
	reg out_float_sgn; // 输出浮点数的符号位
	reg[22:0] out_float_frac; // 输出浮点数的尾数
	reg float_in_valid_d4; // 延迟4clk的浮点乘法器输入有效指示
	
	assign float_out = {out_float_sgn, out_float_exp_d, out_float_frac};
	assign float_ovf = out_float_ovf_d;
	assign float_out_valid = float_in_valid_d4;
	
	assign float_frac_nml = 
		({28{float_frac_fixed_add_res_ovf_d}} & float_frac_rnml_1) | // 右规
		({28{float_frac_fixed_too_small_d & lnml_n_gth_6}} & float_frac_lnml_7_to_23) | // 左归7~23位
		({28{float_frac_fixed_too_small_d & (~lnml_n_gth_6)}} & float_frac_lnml_1_to_6) | // 左归1~6位
		({28{(~float_frac_fixed_add_res_ovf_d) & (~float_frac_fixed_too_small_d)}} & float_frac_org); // 不变
	assign float_frac_nml_abs = ({28{float_frac_nml[27]}} ^ float_frac_nml) + float_frac_nml[27]; // 取绝对值, 将补码转换为原码
	
	// 输出浮点数的符号位
	always @(posedge clk)
	begin
		if(float_in_valid_d3)
			out_float_sgn <= # simulation_delay float_frac_nml[27];
	end
	
	// 延迟1clk的输出浮点数的阶码
	always @(posedge clk)
	begin
		if(float_in_valid_d3)
			out_float_exp_d <= # simulation_delay out_float_exp;
	end
	
	// 输出浮点数的尾数
	always @(posedge clk)
	begin
		if(float_in_valid_d3)
			out_float_frac <= # simulation_delay {23{~out_float_ovf[0]}} & ({23{out_float_ovf[1]}} | float_frac_nml_abs[24:2]);
	end
	
	// 延迟1clk的输出浮点数的溢出标志
	always @(posedge clk)
	begin
		if(float_in_valid_d3)
			out_float_ovf_d <= # simulation_delay out_float_ovf;
	end
	
	// 延迟4clk的浮点乘法器输入有效指示
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			float_in_valid_d4 <= 1'b0;
		else
			float_in_valid_d4 <= # simulation_delay float_in_valid_d3;
	end
	
endmodule
