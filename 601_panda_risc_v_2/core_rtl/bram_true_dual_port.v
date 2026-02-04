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
// 项目: 真双端口Bram
/* 
描述: 
可选读写模式(no_change|read_first|write_first)
可选的输出寄存器
*/
/*
注意：
无
*/
// 作者: 陈家耀
// 日期: 2022/4/13
//////////////////////////////////////////////////////////////////////////////////


module bram_true_dual_port #(
    parameter integer mem_width = 24, // 存储器位宽
    parameter integer mem_depth = 32, // 存储器深度
    parameter INIT_FILE = "no_init", // 初始化文件路径
    parameter read_write_mode = "no_change", // 读写模式(no_change|read_first|write_first)
    parameter use_output_register = "true", // 是否使用输出寄存器
	parameter en_byte_write = "false", // 是否使能字节写掩码
    parameter real simulation_delay = 10 // 仿真时用的延时
)(
    input wire clk,
    
    // port A
    input wire ena,
    input wire[(((en_byte_write == "true") & (read_write_mode != "no_change")) ? mem_width/8:1)-1:0] wea,
    input wire[31:0] addra,
    input wire[mem_width-1:0] dina,
    output wire[mem_width-1:0] douta,
    
    // port B
    input wire enb,
    input wire[(((en_byte_write == "true") & (read_write_mode != "no_change")) ? mem_width/8:1)-1:0] web,
    input wire[31:0] addrb,
    input wire[mem_width-1:0] dinb,
    output wire[mem_width-1:0] doutb
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
	
    (* ram_style="block" *) reg[mem_width-1:0] mem[mem_depth-1:0];
    reg[mem_width-1:0] ram_data_a = {mem_width{1'b0}};
    reg[mem_width-1:0] ram_data_b = {mem_width{1'b0}};
    
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
    
    // 读写逻辑
	genvar byte_i;
    generate
        if(read_write_mode == "read_first")
        begin
            // read first
			always @(posedge clk)
            begin
                if(ena)
					ram_data_a <= # simulation_delay mem[addra[clogb2(mem_depth-1):0]];
            end
			always @(posedge clk)
            begin
                if(enb)
					ram_data_b <= # simulation_delay mem[addrb[clogb2(mem_depth-1):0]];
            end
			
			if(en_byte_write == "true")
			begin
				for(byte_i = 0;byte_i < mem_width/8;byte_i = byte_i + 1)
				begin:mem_wr_blk_a
					always @(posedge clk)
					begin
						if(ena)
						begin
							if(wea[byte_i])
								mem[addra[clogb2(mem_depth-1):0]][(byte_i+1)*8-1:byte_i*8] <= # simulation_delay 
									dina[(byte_i+1)*8-1:byte_i*8];
						end
					end
					
					always @(posedge clk)
					begin
						if(enb)
						begin
							if(web[byte_i])
								mem[addrb[clogb2(mem_depth-1):0]][(byte_i+1)*8-1:byte_i*8] <= # simulation_delay 
									dinb[(byte_i+1)*8-1:byte_i*8];
						end
					end
				end
			end
			else
			begin
				always @(posedge clk)
				begin
					if(ena)
					begin
						if(wea)
							mem[addra[clogb2(mem_depth-1):0]] <= # simulation_delay dina;
					end
				end
				
				always @(posedge clk)
				begin
					if(enb)
					begin
						if(web)
							mem[addrb[clogb2(mem_depth-1):0]] <= # simulation_delay dinb;
					end
				end
			end
        end
        else if(read_write_mode == "write_first")
        begin
            // write first
			always @(posedge clk)
            begin
                if(ena)
				begin
                    if(wea)
                        ram_data_a <= # simulation_delay dina;
					else
						ram_data_a <= # simulation_delay mem[addra[clogb2(mem_depth-1):0]];
				end
            end
			
			always @(posedge clk)
            begin
                if(enb)
				begin
                    if(web)
                        ram_data_b <= # simulation_delay dinb;
					else
						ram_data_b <= # simulation_delay mem[addrb[clogb2(mem_depth-1):0]];
				end
            end
			
			if(en_byte_write == "true")
			begin
				for(byte_i = 0;byte_i < mem_width/8;byte_i = byte_i + 1)
				begin:mem_wr_blk_b
					always @(posedge clk)
					begin
						if(ena)
						begin
							if(wea[byte_i])
								mem[addra[clogb2(mem_depth-1):0]][(byte_i+1)*8-1:byte_i*8] <= # simulation_delay 
									dina[(byte_i+1)*8-1:byte_i*8];
						end
					end
					
					always @(posedge clk)
					begin
						if(enb)
						begin
							if(web[byte_i])
								mem[addrb[clogb2(mem_depth-1):0]][(byte_i+1)*8-1:byte_i*8] <= # simulation_delay 
									dinb[(byte_i+1)*8-1:byte_i*8];
						end
					end
				end
			end
			else
			begin
				always @(posedge clk)
				begin
					if(ena)
					begin
						if(wea)
							mem[addra[clogb2(mem_depth-1):0]] <= # simulation_delay dina;
					end
				end
				
				always @(posedge clk)
				begin
					if(enb)
					begin
						if(web)
							mem[addrb[clogb2(mem_depth-1):0]] <= # simulation_delay dinb;
					end
				end
			end
        end
        else
        begin
            // no change
            always @(posedge clk)
            begin
                if(ena)
                begin
                    if(wea)
                        mem[addra[clogb2(mem_depth-1):0]] <= # simulation_delay dina;
                    else
                        ram_data_a <= # simulation_delay mem[addra[clogb2(mem_depth-1):0]];
                end
            end
        
            always @(posedge clk)
            begin
                if(enb)
                begin
                    if(web)
                        mem[addrb[clogb2(mem_depth-1):0]] <= # simulation_delay dinb;
                    else
                        ram_data_b <= # simulation_delay mem[addrb[clogb2(mem_depth-1):0]];
                end
            end
        end
    endgenerate
    
    // 输出逻辑
    generate
        if(use_output_register == "true")
        begin
            // 使用输出寄存器
            reg[mem_width-1:0] douta_reg = {mem_width{1'b0}};
            reg[mem_width-1:0] doutb_reg = {mem_width{1'b0}};
            
            assign douta = douta_reg;
            assign doutb = doutb_reg;
            
            always @(posedge clk)
                douta_reg <= # simulation_delay ram_data_a;
            
            always @(posedge clk)
                doutb_reg <= # simulation_delay ram_data_b;
        end
        else
        begin
            // 不使用输出寄存器
            assign douta = ram_data_a;
            assign doutb = ram_data_b;
        end
    endgenerate

endmodule
