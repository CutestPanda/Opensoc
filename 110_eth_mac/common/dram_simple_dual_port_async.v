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
//////////////////////////////////////////////////////////////////////////////////
// 项目: 简单双端口Dram
/* 
描述: 
可选的输出寄存器
*/
/*
注意：
无
*/
// 作者: 陈家耀
// 日期: 2022/1/13
//////////////////////////////////////////////////////////////////////////////////


module dram_simple_dual_port_async #(
    parameter integer mem_width = 24, // 存储器位宽
    parameter integer mem_depth = 32, // 存储器深度
    parameter INIT_FILE = "no_init", // 初始化文件路径
    parameter use_output_register = "true", // 是否使用输出寄存器
    parameter real simulation_delay = 10 // 仿真时用的延时
)(
    // 时钟
    input wire clk_a,
    input wire clk_b,
    
    // mem
    // write port
    input wire wen_a,
    input wire[clogb2(mem_depth-1):0] addr_a,
    input wire[mem_width-1:0] din_a,
    // read port
    input wire ren_b,
    input wire[clogb2(mem_depth-1):0] addr_b,
    output wire[mem_width-1:0] dout_b
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
    
    (* ram_style="distributed" *) reg[mem_width-1:0] mem[mem_depth-1:0]; // 存储器
    
    generate
    if (INIT_FILE != "")
    begin
        if(INIT_FILE != "no_init")
        begin
            initial
                $readmemh(INIT_FILE, mem, 0, mem_depth - 1);
        end
    end
    else
    begin
        integer ram_index;
        initial
        for (ram_index = 0; ram_index < mem_depth; ram_index = ram_index + 1)
            mem[ram_index] = {mem_width{1'b0}};
    end
    endgenerate
    
    // 读写控制逻辑
    generate
        if(use_output_register == "true")
        begin
			// 跨时钟域：... -> dout_b_regs!
            reg[mem_width-1:0] dout_b_regs;
            
            assign dout_b = dout_b_regs;
            
            always @(posedge clk_a)
            begin
                if(wen_a)
                    # simulation_delay mem[addr_a] <= din_a;
            end
            
            always @(posedge clk_b)
            begin
                if(ren_b)
                    # simulation_delay dout_b_regs <= mem[addr_b];
            end
        end
        else
        begin
            always @(posedge clk_a)
            begin
                # simulation_delay;
                if(wen_a)
                    mem[addr_a] <= din_a;
            end
            
            assign dout_b = mem[addr_b];
        end
    endgenerate

endmodule
