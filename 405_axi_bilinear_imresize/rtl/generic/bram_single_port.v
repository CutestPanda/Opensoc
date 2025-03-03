`timescale 1ns / 1ps
/********************************************************************
本模块: 单端口Bram

描述: 
可选读延迟1clk或2clk

注意：
无

协议:
MEM READ/WRITE

作者: 陈家耀
日期: 2023/10/25
********************************************************************/


module bram_single_port #(
    parameter style = "HIGH_PERFORMANCE", // 存储器样式(HIGH_PERFORMANCE|LOW_LATENCY)
    parameter rw_mode = "no_change", // 读写模式(no_change|read_first|write_first)
    parameter integer mem_width = 32, // 存储器位宽
    parameter integer mem_depth = 4096, // 存储器深度
    parameter INIT_FILE = "no_init", // 初始化文件路径
	parameter byte_write_mode = "false", // 是否使用字节使能模式(no_change模式下不可用)
    parameter integer simulation_delay = 1 // 仿真延时
)
(
    // clk
    input wire clk,
    
    // mem read/write
    input wire en,
    input wire[((byte_write_mode == "true") ? (mem_width / 8):1)-1:0] wen,
    input wire[clogb2(mem_depth-1):0] addr,
    input wire[mem_width-1:0] din,
    output wire[mem_width-1:0] dout
);

    // 计算bit_depth的最高有效位编号(即位数-1)             
    function integer clogb2 (input integer bit_depth);              
    begin                                                           
        for(clogb2=-1; bit_depth>0; clogb2=clogb2+1)                   
          bit_depth = bit_depth >> 1;                                 
        end                                        
    endfunction
    
    (* ram_style="block" *) reg[mem_width-1:0] mem[mem_depth-1:0]; // 存储器
    reg[mem_width-1:0] ram_data;
    
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
	genvar byte_lane_i;
    generate
        if(rw_mode == "no_change")
        begin
            // 保持模式
            always @(posedge clk)
            begin
                if(en)
                begin
                    if(wen)
                        #simulation_delay mem[addr] <= din;
                    else
                        #simulation_delay ram_data <= mem[addr];
                end
            end
        end
        else if(rw_mode == "read_first")
        begin
            // 读优先模式
			if(byte_write_mode == "true")
			begin
				for(byte_lane_i = 0;byte_lane_i < mem_width / 8;byte_lane_i = byte_lane_i + 1)
				begin
					always @(posedge clk)
					begin
						if(en)
						begin
							if(wen[byte_lane_i])
								#simulation_delay mem[addr][byte_lane_i*8+7:byte_lane_i*8] <= 
									din[byte_lane_i*8+7:byte_lane_i*8];
						end
					end
				end
			end
			else
			begin
				always @(posedge clk)
				begin
					if(en)
					begin
						if(wen)
							#simulation_delay mem[addr] <= din;
					end
				end
			end
            
            always @(posedge clk)
            begin
                if(en)
                    #simulation_delay ram_data <= mem[addr];
            end
        end
        else
        begin
            // 写优先模式
			if(byte_write_mode == "true")
			begin
				for(byte_lane_i = 0;byte_lane_i < mem_width / 8;byte_lane_i = byte_lane_i + 1)
				begin
					always @(posedge clk)
					begin
						if(en)
						begin
							if(wen[byte_lane_i])
								#simulation_delay mem[addr][byte_lane_i*8+7:byte_lane_i*8] <= 
									din[byte_lane_i*8+7:byte_lane_i*8];
						end
					end
				end
			end
			else
			begin
				always @(posedge clk)
				begin
					if(en)
					begin
						if(wen)
							#simulation_delay mem[addr] <= din;
					end
				end
			end
            
            always @(posedge clk)
            begin
                if(en)
                begin
                    if(wen)
                        #simulation_delay ram_data <= din;
                    else
                        #simulation_delay ram_data <= mem[addr];
                end
            end
        end
    endgenerate
    
    generate
        if(style == "HIGH_PERFORMANCE")
        begin
            // 使用输出寄存器
            reg[mem_width-1:0] data;
            
            assign dout = data;
            
            always @(posedge clk)
                #simulation_delay data <= ram_data;
        end
        else
        begin
            // 不使用输出寄存器
            assign dout = ram_data;
        end
    endgenerate
    
endmodule
