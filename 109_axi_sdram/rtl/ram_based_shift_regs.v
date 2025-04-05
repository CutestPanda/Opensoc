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
本模块: 基于ram的移位寄存器

描述: 
固定的延迟周期数
支持使用ram和ff来构造移位寄存器
利用错开的ram读写地址可实现深延迟(通常大于4拍)

注意：
ram的读延迟只能是1(请改进, 以支持ram读延迟为2!!!!!!!!)

协议:
无

作者: 陈家耀
日期: 2023/01/18
********************************************************************/


module ram_based_shift_regs #(
    parameter integer data_width = 8, // 数据位宽
    parameter integer delay_n = 16, // 延迟周期数
    parameter shift_type = "ram", // 移位寄存器类型(ram | ff)
    parameter ram_type = "lutram", // ram类型(lutram | bram)
    parameter INIT_FILE = "no_init", // RAM初始化文件路径
    parameter en_output_register_init = "true", // 输出寄存器是否需要复位
    parameter output_register_init_v = 0, // 输出寄存器复位值
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire resetn,
    
    // 移位寄存器
    input wire[data_width-1:0] shift_in,
    input wire ce,
    output wire[data_width-1:0] shift_out
);

    // 计算bit_depth的最高有效位编号(即位数-1)             
    function integer clogb2 (input integer bit_depth);
        integer temp;
    begin
        temp = bit_depth;
        for(clogb2 = -1;temp > 0;clogb2 = clogb2 + 1)
            temp = temp >> 1;
    end
    endfunction
    
    /** 基于FF的移位寄存器 **/
    reg[data_width-1:0] shift_ffs[delay_n-1:0];
    
    genvar shift_ffs_i;
    generate
        for(shift_ffs_i = 0;shift_ffs_i < delay_n;shift_ffs_i = shift_ffs_i + 1)
        begin:shift_ffs_blk
            if(en_output_register_init == "false")
            begin
                always @(posedge clk)
                begin
                    if(ce)
                        shift_ffs[shift_ffs_i] <= # simulation_delay (shift_ffs_i == 0) ?
                            shift_in:shift_ffs[shift_ffs_i-1];
                end
            end
            else
            begin
                always @(posedge clk or negedge resetn)
                begin
                    if(~resetn)
                        shift_ffs[shift_ffs_i] <= output_register_init_v;
                    else if(ce)
                        shift_ffs[shift_ffs_i] <= # simulation_delay (shift_ffs_i == 0) ?
                            shift_in:shift_ffs[shift_ffs_i-1];
                end
            end
        end
    endgenerate

    /** 基于ram的移位寄存器 **/
    // 写端口
    wire wen_a;
    reg[clogb2(delay_n-1):0] addr_a;
    wire[data_width-1:0] din_a;
    // 读端口
    wire ren_b;
    reg[clogb2(delay_n-1):0] addr_b;
    wire[data_width-1:0] dout_b;
    
    assign wen_a = ce;
    assign ren_b = ce;
    assign din_a = shift_in;
    
    generate
        if(ram_type == "lutram")
            dram_simple_dual_port #(
                .mem_width(data_width),
                .mem_depth(delay_n),
                .INIT_FILE(INIT_FILE),
                .use_output_register("true"),
                .output_register_init_v(output_register_init_v),
                .simulation_delay(simulation_delay)
            )ram_u(
                .clk(clk),
                .rst_n(resetn),
                .wen_a(wen_a),
                .addr_a(addr_a),
                .din_a(din_a),
                .ren_b(ren_b),
                .addr_b(addr_b),
                .dout_b(dout_b)
            );
        else
            bram_simple_dual_port #(
                .style("LOW_LATENCY"),
                .mem_width(data_width),
                .mem_depth(delay_n),
                .INIT_FILE(INIT_FILE),
                .simulation_delay(simulation_delay)
            )ram_u(
                .clk(clk),
                .wen_a(wen_a),
                .addr_a(addr_a),
                .din_a(din_a),
                .ren_b(ren_b),
                .addr_b(addr_b),
                .dout_b(dout_b)
            );
    endgenerate
    
    // 读写地址控制
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            addr_a <= delay_n - 1;
        else if(ce)
            addr_a <= # simulation_delay (addr_a == (delay_n - 1)) ? 0:(addr_a + 1);
    end
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            addr_b <= 0;
        else if(ce)
            addr_b <= # simulation_delay (addr_b == (delay_n - 1)) ? 0:(addr_b + 1);
    end
    
    /** 移位输出 **/
    assign shift_out = (shift_type == "ram") ? dout_b:shift_ffs[delay_n-1];

endmodule
