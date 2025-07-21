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
本模块: 简单双端口Bram(异步)

描述: 
可选读延迟1clk或2clk

注意：
无

协议:
MEM READ/WRITE

作者: 陈家耀
日期: 2024/05/10
********************************************************************/


module bram_simple_dual_port_async #(
    parameter style = "HIGH_PERFORMANCE", // 存储器样式(HIGH_PERFORMANCE|LOW_LATENCY)
    parameter integer mem_width = 32, // 存储器位宽
    parameter integer mem_depth = 4096, // 存储器深度
    parameter INIT_FILE = "no_init", // 初始化文件路径
    parameter integer simulation_delay = 1 // 仿真延时
)
(
    // clk
    input wire clk_a,
    input wire clk_b,
    
    // mem write
    input wire wen_a,
    input wire[clogb2(mem_depth-1):0] addr_a,
    input wire[mem_width-1:0] din_a,
    
    // mem read
    input wire ren_b,
    input wire[clogb2(mem_depth-1):0] addr_b,
    output wire[mem_width-1:0] dout_b
);

    // 计算bit_depth的最高有效位编号(即位数-1)             
    function integer clogb2 (input integer bit_depth);              
    begin                                                           
        for(clogb2=-1; bit_depth>0; clogb2=clogb2+1)                   
          bit_depth = bit_depth >> 1;                                 
        end                                        
    endfunction
    
    (* ram_style="block" *) reg[mem_width-1:0] mem[mem_depth-1:0]; // 存储器
    reg[mem_width-1:0] ram_data_b;
    
    generate
        if (INIT_FILE != "")
        begin
            if(INIT_FILE == "default")
            begin
                integer ram_index;
                initial
                for (ram_index = 0; ram_index < mem_depth; ram_index = ram_index + 1)
                    mem[ram_index] = ram_index;
            end
            else if(INIT_FILE != "no_init")
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
    always @(posedge clk_a)
    begin
        if(wen_a)
            # simulation_delay mem[addr_a] <= din_a;
    end
    
    always @(posedge clk_b)
    begin
        if(ren_b)
            # simulation_delay ram_data_b <= mem[addr_b];
    end
    
    generate
        if(style == "HIGH_PERFORMANCE")
        begin
            // 使用输出寄存器
            reg[mem_width-1:0] data_b;
            
            assign dout_b = data_b;
            
            always @(posedge clk_b)
                #simulation_delay data_b <= ram_data_b;
        end
        else
        begin
            // 不使用输出寄存器
            assign dout_b = ram_data_b;
        end
    endgenerate
    
endmodule
