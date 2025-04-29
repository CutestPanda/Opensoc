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


module bram_true_dual_port_async #(
    parameter integer mem_width = 24, // 存储器位宽
    parameter integer mem_depth = 32, // 存储器深度
    parameter INIT_FILE = "no_init", // 初始化文件路径
    parameter read_write_mode = "no_change", // 读写模式(no_change|read_first|write_first)
    parameter use_output_register = "true", // 是否使用输出寄存器
    parameter real simulation_delay = 10 // 仿真时用的延时
)(
    input wire clk_a,
	input wire clk_b,
    
    // port A
    input wire ena,
    input wire wea,
    input wire[clogb2(mem_depth-1):0] addra,
    input wire[mem_width-1:0] dina,
    output wire[mem_width-1:0] douta,
    
    // port B
    input wire enb,
    input wire web,
    input wire[clogb2(mem_depth-1):0] addrb,
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
    generate
        if(read_write_mode == "read_first")
        begin
            // read first
            always @(posedge clk_a)
            begin
                if (ena)
                begin
                    if (wea)
                        mem[addra] <= # simulation_delay dina;
                    ram_data_a <= # simulation_delay mem[addra];
                end
            end
            
            always @(posedge clk_b)
            begin
                if (enb)
                begin
                    if (web)
                        mem[addrb] <= # simulation_delay dinb;
                    ram_data_b <= # simulation_delay mem[addrb];
                end
            end
        end
        else if(read_write_mode == "write_first")
        begin
            // write first
            always @(posedge clk_a)
            begin
                if (ena)
                    if (wea)
                    begin
                        mem[addra] <= # simulation_delay dina;
                        ram_data_a <= # simulation_delay dina;
                    end
                else
                    ram_data_a <= # simulation_delay mem[addra];
            end
            
            always @(posedge clk_b)
            begin
                if (enb)
                    if (web)
                    begin
                        mem[addrb] <= # simulation_delay dinb;
                        ram_data_b <= # simulation_delay dinb;
                    end
                else
                    ram_data_b <= # simulation_delay mem[addrb];
            end
        end
        else
        begin
            // no change
            always @(posedge clk_a)
            begin
                if (ena)
                begin
                    if (wea)
                        mem[addra] <= # simulation_delay dina;
                    else
                        ram_data_a <= # simulation_delay mem[addra];
                end
            end
        
            always @(posedge clk_b)
            begin
                if (enb)
                begin
                    if (web)
                        mem[addrb] <= # simulation_delay dinb;
                    else
                        ram_data_b <= # simulation_delay mem[addrb];
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
            
            always @(posedge clk_a)
				douta_reg <= # simulation_delay ram_data_a;
            
            always @(posedge clk_b)
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
