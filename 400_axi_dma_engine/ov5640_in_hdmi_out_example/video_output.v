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
本模块: 视频输出

描述: 
参数可配置的视频输出
支持1clk或2clk的读像素延迟

注意：
当获取下一个像素(标志)有效时，请在下1clk(不启用额外的像素输入延迟)或2clk
(启用额外的像素输入延迟)给出有效的像素数据

协议:
VIO

作者: 陈家耀
日期: 2023/09/17
********************************************************************/


module video_output #(
    parameter integer h_active = 1280, // 水平有效长度
    parameter integer h_fp = 110, // 水平前肩长度
    parameter integer h_sync = 40, // 水平同步长度
    parameter integer h_bp = 220, // 水平后肩
    parameter integer v_active = 720, // 垂直有效长度
    parameter integer v_fp = 5, // 垂直前肩长度
    parameter integer v_sync = 5, // 垂直同步长度
    parameter integer v_bp = 20, // 垂直后肩
    parameter hs_posedge = "true", // 上升沿触发的水平同步信号
    parameter vs_posedge = "true", // 上升沿触发的垂直同步信号
    parameter integer pix_data_width = 24, // 像素位宽
    parameter en_ext_pix_read_la = "false", // 额外的像素输入延迟(不启用->像素输入延迟为1clk 启用->像素输入延迟为2clk)
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
	input wire rst_n,
	
	// 像素输入
	output wire next_pix, // 获取下一个像素(标志)
	output wire pix_line_end, // 获取当前行最后一个像素(标志)
	output wire pix_last, // 获取当前帧最后一个像素(标志)
	input wire[pix_data_width-1:0] in_pix, // 像素输入
	
	// vio(video out)
	output wire hs, // 行同步
	output wire vs, // 场同步
	output wire de, // 数据有效
	output wire[pix_data_width-1:0] pix // 像素输出
);
	
    // 计算log2(bit_depth)
    function integer clogb2 (input integer bit_depth);
        integer temp;
    begin
        temp = bit_depth;
        for(clogb2 = -1;temp > 0;clogb2 = clogb2 + 1)
            temp = temp >> 1;
    end
    endfunction
    
    /** 视频时序信号 **/
    wire hs_w;
    wire vs_w;
    wire de_w;
    
    generate
        if(en_ext_pix_read_la == "true")
        begin
            reg hs_reg_d2;
            reg vs_reg_d2;
            reg de_reg_d;
            
            assign {hs, vs, de} = {hs_reg_d2, vs_reg_d2, de_reg_d};
            
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    hs_reg_d2 <= (hs_posedge == "true") ? 1'b0:1'b1;
                else
                    hs_reg_d2 <= # simulation_delay hs_w;
            end
            
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    vs_reg_d2 <= (vs_posedge == "true") ? 1'b0:1'b1;
                else
                    vs_reg_d2 <= # simulation_delay vs_w;
            end
            
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    de_reg_d <= 1'b0;
                else
                    de_reg_d <= # simulation_delay de_w;
            end
        end
        else
        begin
            assign {hs, vs, de} = {hs_w, vs_w, de_w};
        end
    endgenerate
    
    /** 水平和垂直总长度 **/
    localparam integer h_total = h_active + h_fp + h_sync + h_bp; // 水平总长度
    localparam integer v_total = v_active + v_fp + v_sync + v_bp; // 垂直总长度

    /** 行列计数器 **/
    reg[clogb2(h_total-1):0] h_cnt;
    reg[clogb2(v_total-1):0] v_cnt;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            h_cnt <= 0;
        else
            h_cnt <= # simulation_delay (h_cnt == h_total - 1) ? 0:(h_cnt + 1);
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            v_cnt <= 0;
        else if(h_cnt == h_fp - 1)
            v_cnt <= # simulation_delay (v_cnt == v_total - 1) ? 0:(v_cnt + 1);
    end
    
    /** 生成行列同步信号 **/
    reg hs_reg;
    reg hs_reg_d;
    reg vs_reg;
    reg vs_reg_d;
    
    assign {vs_w, hs_w} = {vs_reg_d, hs_reg_d};
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            hs_reg <= (hs_posedge == "true") ? 1'b0:1'b1;
        else if((h_cnt == h_fp - 1) | (h_cnt == h_fp + h_sync - 1))
            hs_reg <= # simulation_delay ~hs_reg;
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            hs_reg_d <= (hs_posedge == "true") ? 1'b0:1'b1;
        else
            hs_reg_d <= # simulation_delay hs_reg;
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            vs_reg <= (vs_posedge == "true") ? 1'b0:1'b1;
        else if(((v_cnt == v_fp - 1) | (v_cnt == v_fp + v_sync - 1)) & (h_cnt == h_fp - 1))
            vs_reg <= # simulation_delay ~vs_reg;
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            vs_reg_d <= (vs_posedge == "true") ? 1'b0:1'b1;
        else
            vs_reg_d <= # simulation_delay vs_reg;
    end
    
    /** 生成数据有效信号 **/
    reg h_active_reg; // 行有效
    reg v_active_reg; // 列有效
    wire pix_acitive; // 当前数据有效(标志)
    reg de_reg;
    
    assign pix_acitive = h_active_reg & v_active_reg;
    
    assign de_w = de_reg;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            h_active_reg <= 1'b0;
        else if((h_cnt == h_fp + h_sync + h_bp - 1) | (h_cnt == h_total - 1))
            h_active_reg <= # simulation_delay ~h_active_reg;
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            v_active_reg <= 1'd0;
        else if(((v_cnt == v_fp + v_sync + v_bp - 1) | (v_cnt == v_total - 1)) & (h_cnt == h_fp - 1))
            v_active_reg <= # simulation_delay ~v_active_reg;
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            de_reg <= 1'b0;
        else
            de_reg <= # simulation_delay pix_acitive;
    end
    
    /** 生成RGB数据 **/
    reg next_pix_reg; // 获取下一个像素(标志)
    reg pix_line_end_reg; // 获取当前行最后一个像素(标志)
	reg pix_last_reg; // 获取当前帧最后一个像素(标志)
    
    assign next_pix = next_pix_reg;
    assign pix_line_end = pix_line_end_reg;
	assign pix_last = pix_last_reg;
    assign pix = in_pix;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            next_pix_reg <= 1'b0;
        else if((h_cnt == h_fp + h_sync + h_bp - 1) | (h_cnt == h_total - 1))
            next_pix_reg <= # simulation_delay (h_cnt == h_total - 1) ? 1'b0:v_active_reg;
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            pix_line_end_reg <= 1'b0;
        else
            pix_line_end_reg <= # simulation_delay v_active_reg & (h_cnt == h_total - 2);
    end
	
	always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
			pix_last_reg <= 1'b0;
		else
			pix_last_reg <= # simulation_delay (h_cnt == h_total - 2) & (v_cnt == v_total - 1);
	end
    
endmodule
