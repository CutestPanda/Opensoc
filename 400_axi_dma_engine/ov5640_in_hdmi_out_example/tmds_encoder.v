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
本模块: TMDS编码器

描述: 
将8位数据编码为最小传输, 直流均衡的10位数据
3级流水线

注意：
无

协议:
VIO

作者: 陈家耀
日期: 2024/03/01
********************************************************************/


module tmds_encoder #(
    parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst,
	
    // vio(video in)
	input wire hs, // 行同步
	input wire vs, // 场同步
	input wire de, // 数据有效
	input wire[7:0] pix, // 像素输入
	
	// 编码输出
	output wire[9:0] encode_out
);
	
    // 计算8位数据中1的个数
    function [3:0] count1_of_u8(input[7:0] data);
        integer i;
    begin
        count1_of_u8 = 4'd0;
        
        for(i = 0;i < 8;i = i + 1)
        begin
            if(data[i])
                count1_of_u8 = count1_of_u8 + 4'd1;
        end
    end
    endfunction
    // 计算8位数据中0的个数
    function [3:0] count0_of_u8(input[7:0] data);
        integer i;
    begin
        count0_of_u8 = 4'd0;
        
        for(i = 0;i < 8;i = i + 1)
        begin
            if(!data[i])
                count0_of_u8 = count0_of_u8 + 4'd1;
        end
    end
    endfunction
	
    /** 常量 **/
    localparam ENCODE_OUT_INIT_W = 10'b00000_00000; // 复位时的编码输出
    
    /**
    第1级 ->
        计算预编码的9位数据
        生成数据无效时的编码输出
    **/
    reg[8:0] q_m; // 预编码的9位数据
    reg[9:0] q_out_when_not_de; // 数据无效时的编码输出
    reg de_d; // 延迟1clk的数据有效信号
    
    // 预编码的9位数据
    always @(posedge clk)
    begin
        if((count1_of_u8(pix) > 4'd4) | ((count1_of_u8(pix) == 4'd4) & (~pix[0])))
        begin
            q_m[0] <= # SIM_DELAY pix[0];
            q_m[1] <= # SIM_DELAY pix[0] ^~ pix[1];
            q_m[2] <= # SIM_DELAY pix[0] ^~ pix[1] ^~ pix[2];
            q_m[3] <= # SIM_DELAY pix[0] ^~ pix[1] ^~ pix[2] ^~ pix[3];
            q_m[4] <= # SIM_DELAY pix[0] ^~ pix[1] ^~ pix[2] ^~ pix[3] ^~ pix[4];
            q_m[5] <= # SIM_DELAY pix[0] ^~ pix[1] ^~ pix[2] ^~ pix[3] ^~ pix[4] ^~ pix[5];
            q_m[6] <= # SIM_DELAY pix[0] ^~ pix[1] ^~ pix[2] ^~ pix[3] ^~ pix[4] ^~ pix[5] ^~ pix[6];
            q_m[7] <= # SIM_DELAY pix[0] ^~ pix[1] ^~ pix[2] ^~ pix[3] ^~ pix[4] ^~ pix[5] ^~ pix[6] ^~ pix[7];
            q_m[8] <= # SIM_DELAY 1'b0;
        end
        else
        begin
            q_m[0] <= # SIM_DELAY pix[0];
            q_m[1] <= # SIM_DELAY pix[0] ^ pix[1];
            q_m[2] <= # SIM_DELAY pix[0] ^ pix[1] ^ pix[2];
            q_m[3] <= # SIM_DELAY pix[0] ^ pix[1] ^ pix[2] ^ pix[3];
            q_m[4] <= # SIM_DELAY pix[0] ^ pix[1] ^ pix[2] ^ pix[3] ^ pix[4];
            q_m[5] <= # SIM_DELAY pix[0] ^ pix[1] ^ pix[2] ^ pix[3] ^ pix[4] ^ pix[5];
            q_m[6] <= # SIM_DELAY pix[0] ^ pix[1] ^ pix[2] ^ pix[3] ^ pix[4] ^ pix[5] ^ pix[6];
            q_m[7] <= # SIM_DELAY pix[0] ^ pix[1] ^ pix[2] ^ pix[3] ^ pix[4] ^ pix[5] ^ pix[6] ^ pix[7];
            q_m[8] <= # SIM_DELAY 1'b1;
        end
    end
    
    // 数据无效时的编码输出
    always @(posedge clk or posedge rst)
    begin
        if(rst)
            q_out_when_not_de <= ENCODE_OUT_INIT_W;
        else
        begin
            case({vs, hs})
                2'b00: q_out_when_not_de <= # SIM_DELAY 10'b1101010100;
                2'b01: q_out_when_not_de <= # SIM_DELAY 10'b0010101011;
                2'b10: q_out_when_not_de <= # SIM_DELAY 10'b0101010100;
                2'b11: q_out_when_not_de <= # SIM_DELAY 10'b1010101011;
                default: q_out_when_not_de <= # SIM_DELAY 10'b1101010100;
            endcase
        end
    end
    
    // 延迟1clk的数据有效信号
    always @(posedge clk or posedge rst)
    begin
        if(rst)
            de_d <= 1'b0;
        else
            de_d <= # SIM_DELAY de;
    end
    
    /**
    第2级 ->
        计算并比较预编码9位数据中低8位1和0的个数
        计算预编码9位数据中低8位1和0个数的差
    **/
    wire[3:0] count0_of_q_m; // 预编码9位数据中低8位0的个数
    wire[3:0] count1_of_q_m; // 预编码9位数据中低8位1的个数
    reg q_m_count1_gth_count0; // 预编码9位数据中低8位1的个数 > 预编码9位数据中低8位0的个数
    reg q_m_count0_gth_count1; // 预编码9位数据中低8位0的个数 > 预编码9位数据中低8位1的个数
    reg q_m_count0_eq_count1; // 预编码9位数据中低8位0的个数 == 预编码9位数据中低8位1的个数
    reg signed[4:0] q_m_count1_sub_count0; // 预编码9位数据中低8位1的个数 - 预编码9位数据中低8位0的个数
    reg signed[4:0] q_m_count0_sub_count1; // 预编码9位数据中低8位0的个数 - 预编码9位数据中低8位1的个数
    reg[8:0] q_m_d; // 延迟1clk的预编码的9位数据
    reg[9:0] q_out_when_not_de_d; // 延迟1clk的数据无效时的编码输出
    reg de_d2; // 延迟2clk的数据有效信号
    
    assign count0_of_q_m = count0_of_u8(q_m[7:0]);
    assign count1_of_q_m = count1_of_u8(q_m[7:0]);
    
    // 预编码9位数据中低8位1的个数 > 预编码9位数据中低8位0的个数
    always @(posedge clk)
        q_m_count1_gth_count0 <= # SIM_DELAY count1_of_q_m >= 4'd5;
    // 预编码9位数据中低8位0的个数 > 预编码9位数据中低8位1的个数
    always @(posedge clk)
        q_m_count0_gth_count1 <= # SIM_DELAY count1_of_q_m <= 4'd3;
    // 预编码9位数据中低8位0的个数 == 预编码9位数据中低8位1的个数
    always @(posedge clk)
        q_m_count0_eq_count1 <= # SIM_DELAY count1_of_q_m == 4'd4;
    
    // 预编码9位数据中低8位1的个数 - 预编码9位数据中低8位0的个数
    always @(posedge clk)
	    q_m_count1_sub_count0 <= # SIM_DELAY $signed(count1_of_q_m) - $signed(count0_of_q_m);
    // 预编码9位数据中低8位0的个数 - 预编码9位数据中低8位1的个数
    always @(posedge clk)
        q_m_count0_sub_count1 <= # SIM_DELAY $signed(count0_of_q_m) - $signed(count1_of_q_m);
    
    // 延迟1clk的预编码的9位数据
    always @(posedge clk)
        q_m_d <= # SIM_DELAY q_m;
    // 延迟1clk的数据无效时的编码输出
    always @(posedge clk or posedge rst)
    begin
        if(rst)
            q_out_when_not_de_d <= ENCODE_OUT_INIT_W;
        else
            q_out_when_not_de_d <= # SIM_DELAY q_out_when_not_de;
    end
    // 延迟2clk的数据有效信号
    always @(posedge clk or posedge rst)
    begin
        if(rst)
            de_d2 <= 1'b0;
        else
            de_d2 <= # SIM_DELAY de_d;
    end
    
    /**
    第3级
    生成编码后的10位数据
    更新"1"数量统计计数器
    **/
    reg signed[4:0] cnt; // "1"数量统计计数器
    reg[9:0] q_out; // 编码后的10位数据
    
    assign encode_out = q_out;
    
    // "1"数量统计计数器
    always @(posedge clk or posedge rst)
    begin
        if(rst)
            cnt <= 5'd0;
        else
        begin
            if(de_d2)
            begin
                if((cnt == 5'd0) | q_m_count0_eq_count1)
                    cnt <= # SIM_DELAY cnt + (q_m_d[8] ? q_m_count1_sub_count0:q_m_count0_sub_count1);
                else if(((cnt > 0) & q_m_count1_gth_count0) | ((cnt < 0) & q_m_count0_gth_count1))
                    cnt <= # SIM_DELAY cnt + $signed(q_m_d[8] ? 2:0) + q_m_count0_sub_count1;
                else
                    cnt <= # SIM_DELAY cnt - $signed(q_m_d[8] ? 0:2) + q_m_count1_sub_count0;
            end
            else
                cnt <= # SIM_DELAY 5'd0;
        end
    end
    
    // 编码后的10位数据
    always @(posedge clk or posedge rst)
    begin
        if(rst)
            q_out <= ENCODE_OUT_INIT_W;
        else
        begin
            if(de_d2)
            begin
                if((cnt == 5'd0) | q_m_count0_eq_count1)
                begin
                    q_out[9] <= # SIM_DELAY ~q_m_d[8];
                    q_out[8] <= # SIM_DELAY q_m_d[8];
                    q_out[7:0] <= # SIM_DELAY q_m_d[8] ? q_m_d[7:0]:(~q_m_d[7:0]);
                end
                else if(((cnt > 0) & q_m_count1_gth_count0) | ((cnt < 0) & q_m_count0_gth_count1))
                begin
                    q_out[9] <= # SIM_DELAY 1'b1;
                    q_out[8] <= # SIM_DELAY q_m_d[8];
                    q_out[7:0] <= # SIM_DELAY ~q_m_d[7:0];
                end
                else
                begin
                    q_out[9] <= # SIM_DELAY 1'b0;
                    q_out[8] <= # SIM_DELAY q_m_d[8];
                    q_out[7:0] <= # SIM_DELAY q_m_d[7:0];
                end
            end
            else
                q_out <= # SIM_DELAY q_out_when_not_de_d;
        end
    end
	
endmodule
