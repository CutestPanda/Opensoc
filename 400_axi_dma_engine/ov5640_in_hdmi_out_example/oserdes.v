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
本模块: 并串转换+差分输出

描述: 
并行数据 -> 串行数据 -> 差分输出
使用oddr实现并串转换

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/03/02
********************************************************************/


module oserdes #(
    parameter integer PRL_BIT_WIDTH = 10 // 并行数据的位宽(2~8, 10或14)
)(
    // 时钟和复位
    input wire clk,
    input wire clk_5x,
    input wire rst,
    
    // 并行数据输入
    input wire[PRL_BIT_WIDTH-1:0] prl_in,
    // 串行差分输出
    output wire ser_p,
    output wire ser_n
);
    
    wire s_dout; // 串行输出
    
    /** 并串转换 **/
	reg[(PRL_BIT_WIDTH/2-1):0] sample_cnt; // 并行数据采样计数器
	reg[(PRL_BIT_WIDTH-1):0] shift_regs; // 移位寄存器
	
	// 并行数据采样计数器
	if(PRL_BIT_WIDTH != 2)
	begin
		always @(posedge clk_5x or posedge rst)
		begin
			if(rst)
				sample_cnt <= {{(PRL_BIT_WIDTH/2-1){1'b0}}, 1'b1};
			else
				sample_cnt <= {sample_cnt[(PRL_BIT_WIDTH/2-2):0], sample_cnt[PRL_BIT_WIDTH/2-1]};
		end
	end
	
	// 移位寄存器
	always @(posedge clk_5x or posedge rst)
	begin
		if(rst)
			shift_regs <= {PRL_BIT_WIDTH{1'b0}};
		else if((PRL_BIT_WIDTH == 2) ? 1'b1:sample_cnt[(PRL_BIT_WIDTH/2-1)/2]) // 在clk_5x时钟域采样clk时钟域下相对稳定的prl_in
			shift_regs <= prl_in;
		else
			shift_regs <= (PRL_BIT_WIDTH == 2) ? prl_in:{2'bxx, shift_regs[(PRL_BIT_WIDTH-1):2]};
	end
	
	// ODDR
	// 注意: 根据所用器件重新例化"ODDR"!
	ODDR #(
		.DDR_CLK_EDGE("SAME_EDGE"),
		.INIT(1'b0),
		.SRTYPE("ASYNC")
	)oddr_u(
		.Q(s_dout),
		.C(clk_5x),
		.CE(1'b1),
		.D1(shift_regs[0]), // 上升沿数据输入
		.D2(shift_regs[1]), // 下降沿数据输入
		.R(rst),
		.S(1'b0)
	);
	
	/** 单端转差分 **/
	// 注意: 根据所用器件重新例化"单端转差分"!
	OBUFDS #(
        .IOSTANDARD("TMDS_33"),
        .SLEW("SLOW")
    )obufds_u(
        .O(ser_p),
        .OB(ser_n),
        .I(s_dout)
    );
	
endmodule
