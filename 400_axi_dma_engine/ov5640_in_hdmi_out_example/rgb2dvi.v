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
本模块: RGB转DVI

描述: 
RGB数据 + 行场同步信号 -> 最小传输/直流均衡处理 ->
    串行化+差分输出 -> TMDS信号

注意：
无

协议:
VIO
DVI

作者: 陈家耀
日期: 2024/03/02
********************************************************************/


module rgb2dvi(
    // 时钟和复位
    input wire clk,
    input wire clk_5x,
    input wire resetn,
	
    // vio(video in)
	input wire hs, // 行同步
	input wire vs, // 场同步
	input wire de, // 数据有效
	input wire[23:0] pix, // 像素输入(高位->低位 = RGB)
	
	// DVI(hdmi out)
	output wire tmds_clk_p,
	output wire tmds_clk_n,
	output wire[2:0] tmds_data_p,
	output wire[2:0] tmds_data_n,
	output wire hdmi_oen // const -> 1'b1
);
	
    /** 复位信号 **/
    wire rst;
    
    assign rst = ~resetn;
    
    /** RGB转DVI **/
    assign hdmi_oen = 1'b1;
    
    // TMDS时钟
    oserdes #(
        .PRL_BIT_WIDTH(10)
    )tmds_clk_oserdes(
        .clk(clk),
        .clk_5x(clk_5x),
        .rst(rst),
        .prl_in(10'b11111_00000),
        .ser_p(tmds_clk_p),
        .ser_n(tmds_clk_n)
    );
    // TMDS数据
    genvar tmds_data_i;
    generate
        for(tmds_data_i = 0;tmds_data_i < 3;tmds_data_i = tmds_data_i + 1)
        begin:rgb_chn
            wire[9:0] encode_out;
            
            tmds_encoder #(
                .SIM_DELAY(0)
            )tmds_encoder_u(
                .clk(clk),
                .rst(rst),
                .hs((tmds_data_i == 0) ? hs:1'b0), // 仅通道0需要行同步信号
                .vs((tmds_data_i == 0) ? vs:1'b0), // 仅通道0需要场同步信号
                .de(de),
                .pix(pix[tmds_data_i * 8 + 7:tmds_data_i * 8]),
                .encode_out(encode_out)
            );
            
            oserdes #(
                .PRL_BIT_WIDTH(10)
            )tmds_data_oserdes(
                .clk(clk),
                .clk_5x(clk_5x),
                .rst(rst),
                .prl_in(encode_out),
                .ser_p(tmds_data_p[tmds_data_i]),
                .ser_n(tmds_data_n[tmds_data_i])
            );
        end
    endgenerate
	
endmodule
