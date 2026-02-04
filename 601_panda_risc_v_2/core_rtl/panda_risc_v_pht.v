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
本模块: 分支历史模式-2bit饱和计数器表

描述:
带有1个读端口, 1个更新写端口(输入更新地址和实际分支跳转方向, 对2bit饱和计数器作自动更新)
PHT存储器的读延迟为1clk
使用寄存器组来实现

-------------------------------------------
| 2bit饱和计数器的值 |        含义        |
-------------------------------------------
|       2'b00        | Strongly Not Taken |
-------------------------------------------
|       2'b01        |  Weakly Not Taken  |
-------------------------------------------
|       2'b10        |    Weakly Taken    |
-------------------------------------------
|       2'b11        |   Strongly Taken   |
-------------------------------------------

注意：
无

协议:
MEM SLAVE

作者: 陈家耀
日期: 2026/01/21
********************************************************************/


module panda_risc_v_pht #(
	parameter INIT_2BIT_SAT_CNT_V = 2'b01, // 2bit饱和计数器初始值
	parameter integer PHT_MEM_DEPTH = 256, // PHT存储器深度(16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// PHT存储器读端口
	input wire pht_mem_ren,
	input wire[15:0] pht_mem_raddr,
	output wire[1:0] pht_mem_dout,
	
	// PHT存储器更新端口
	input wire pht_mem_upd_en,
	input wire[15:0] pht_mem_upd_addr,
	input wire pht_mem_upd_brc_taken
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
	
	/** PHT存储器 **/
	reg[1:0] sat_cnt_reg_file[0:PHT_MEM_DEPTH-1]; // 2bit饱和计数器组
	reg[1:0] dout_r; // 读端口输出寄存器
	
	assign pht_mem_dout = dout_r;
	
	genvar sat_cnt_i;
	generate
		for(sat_cnt_i = 0;sat_cnt_i < PHT_MEM_DEPTH;sat_cnt_i = sat_cnt_i + 1)
		begin:sat_cnt_reg_file_blk
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					sat_cnt_reg_file[sat_cnt_i] <= INIT_2BIT_SAT_CNT_V;
				else if(
					pht_mem_upd_en & (pht_mem_upd_addr[clogb2(PHT_MEM_DEPTH-1):0] == sat_cnt_i)
				)
					sat_cnt_reg_file[sat_cnt_i] <= # SIM_DELAY 
						/*
						pht_mem_upd_brc_taken ? 
							(
								(sat_cnt_reg_file[sat_cnt_i] == 2'b11) ? 
									2'b11:
									(sat_cnt_reg_file[sat_cnt_i] + 1'b1)
							):
							(
								(sat_cnt_reg_file[sat_cnt_i] == 2'b00) ? 
									2'b00:
									(sat_cnt_reg_file[sat_cnt_i] - 1'b1)
							)
						*/
						(sat_cnt_reg_file[sat_cnt_i] == {2{pht_mem_upd_brc_taken}}) ? 
							{2{pht_mem_upd_brc_taken}}:
							(sat_cnt_reg_file[sat_cnt_i] + {~pht_mem_upd_brc_taken, 1'b1});
			end
		end
	endgenerate
	
	// 读端口输出寄存器
	always @(posedge aclk)
	begin
		if(pht_mem_ren)
			dout_r <= # SIM_DELAY sat_cnt_reg_file[pht_mem_raddr[clogb2(PHT_MEM_DEPTH-1):0]];
	end
	
endmodule
