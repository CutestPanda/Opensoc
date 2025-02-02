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

module tb_non_linear_act();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer act_cal_width = 16; // 激活计算位宽(8 | 16)
	localparam integer act_in_quaz_acc = 8; // 激活输入量化精度(必须在范围[1, act_cal_width-1]内)
	localparam integer act_in_ext_int_width = 4; // 激活输入额外考虑的整数位数(必须<=(act_cal_width-act_in_quaz_acc))
	localparam integer act_in_ext_frac_width = 4; // 激活输入额外考虑的小数位数(必须<=act_in_quaz_acc)
	// 运行时参数配置
	localparam bit non_ln_act_type = 1'b1; // 非线性激活类型(1'b0 -> Sigmoid, 1'b1 -> Tanh)
	// 仿真模型配置
	localparam string act_sigmoid_txt_path = "./sim_model/act_sigmoid.txt";
	localparam string act_tanh_txt_path = "./sim_model/act_tanh.txt";
	// 时钟和复位配置
	localparam real clk_p = 10.0; // 时钟周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 时钟和复位 **/
	reg clk;
	reg rst_n;
	
	initial
	begin
		clk <= 1'b1;
		
		forever
		begin
			# (clk_p / 2) clk <= ~clk;
		end
	end
	
	initial begin
		rst_n <= 1'b0;
		
		# (clk_p * 10);
		
		rst_n <= # simulation_delay 1'b1;
	end
	
	/** 激励产生 **/
	reg signed[act_cal_width*2-1:0] act_in; // 小数位数 = act_in_quaz_acc + act_in_ext_frac_width
	reg act_in_vld;
	
	class ActInStim;
		rand int act_data;
		
		constraint c{
			if(non_ln_act_type)
				(act_data >= (-5 * (2 ** (act_in_quaz_acc + act_in_ext_frac_width)))) && 
				(act_data <= (5 * (2 ** (act_in_quaz_acc + act_in_ext_frac_width))));
			else
				(act_data >= (-10 * (2 ** (act_in_quaz_acc + act_in_ext_frac_width)))) && 
				(act_data <= (10 * (2 ** (act_in_quaz_acc + act_in_ext_frac_width))));
		}
		
	endclass
	
	ActInStim act_in_stim;
	
	initial
	begin
		act_in_stim = new();
		
		act_in <= {(act_cal_width*2){1'bx}};
		act_in_vld <= 1'b0;
		
		forever
		begin
			@(posedge clk iff rst_n);
			
			if($urandom_range(0, 3) != 3)
			begin
				assert(act_in_stim.randomize()) else $fatal("ActInStim failed to randomize!");
				
				act_in <= # simulation_delay act_in_stim.act_data;
				act_in_vld <= # simulation_delay 1'b1;
			end
			else
			begin
				act_in <= # simulation_delay {(act_cal_width*2){1'bx}};
				act_in_vld <= # simulation_delay 1'b0;
			end
		end
	end
	
	/** 仿真模型 **/
	// Sigmoid/Tanh查找表(读端口)
	wire non_ln_act_lut_ren;
	wire[10:0] non_ln_act_lut_raddr;
	wire[15:0] non_ln_act_lut_dout; // Q15
	
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(16),
		.mem_depth(2048),
		.INIT_FILE(non_ln_act_type ? act_tanh_txt_path:act_sigmoid_txt_path),
		.byte_write_mode("false"),
		.simulation_delay(simulation_delay)
	)non_ln_act_lut(
		.clk(clk),
		
		.wen_a(1'b0),
		.addr_a(11'dx),
		.din_a(16'dx),
		
		.ren_b(non_ln_act_lut_ren),
		.addr_b(non_ln_act_lut_raddr),
		.dout_b(non_ln_act_lut_dout)
	);
	
	/** 待测模块 **/
	non_linear_act #(
		.act_cal_width(act_cal_width),
		.act_in_quaz_acc(act_in_quaz_acc),
		.act_in_ext_int_width(act_in_ext_int_width),
		.act_in_ext_frac_width(act_in_ext_frac_width),
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.rst_n(rst_n),
		
		.non_ln_act_type(non_ln_act_type),
		
		.non_ln_act_lut_ren(non_ln_act_lut_ren),
		.non_ln_act_lut_raddr(non_ln_act_lut_raddr),
		.non_ln_act_lut_dout(non_ln_act_lut_dout),
		
		.act_in(act_in),
		.act_in_vld(act_in_vld),
		
		.act_out(),
		.act_out_vld()
	);
	
endmodule
