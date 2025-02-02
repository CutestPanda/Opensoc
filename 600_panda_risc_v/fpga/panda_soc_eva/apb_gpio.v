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
本模块: 符合APB协议的GPIO控制器

描述: 
APB-GPIO控制器
支持GPIO输入中断

寄存器->
    偏移量  |    含义                     |   读写特性   |    备注
    0x00    gpio_width-1~0:GPIO输出             W
    0x04    gpio_width-1~0:GPIO写电平掩码       W
    0x08    gpio_width-1~0:GPIO方向             W         0为输出, 1为输入
    0x0C    gpio_width-1~0:GPIO输入             R
    0x10    0:全局中断使能                      W
            1:全局中断标志                      RWC   请在中断服务函数中清除中断标志
    0x14    gpio_width-1~0:中断状态             R
    0x18    gpio_width-1~0:中断使能             W

注意：
无

协议:
APB SLAVE
GPIO

作者: 陈家耀
日期: 2023/11/06
********************************************************************/


module apb_gpio #(
    parameter integer gpio_width = 16, // GPIO位宽(1~32)
    parameter gpio_dire = "inout", // GPIO方向(inout|input|output)
    parameter default_output_value = 32'hffff_ffff, // GPIO默认输出电平
    parameter default_tri_value = 32'hffff_ffff, // GPIO默认方向(0->输出 1->输入)(仅在inout模式下可用)
    parameter en_itr = "true", // 是否使能GPIO中断
    parameter itr_edge = "neg", // 中断极性(pos|neg)
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire resetn,
    
    // APB从机接口
    input wire[31:0] paddr,
    input wire psel,
    input wire penable,
    input wire pwrite,
    input wire[31:0] pwdata,
    output wire pready_out, // const -> 1'b1
    output wire[31:0] prdata_out,
    output wire pslverr_out, // const -> 1'b0
    
    // GPIO
    output wire[gpio_width-1:0] gpio_o,
    output wire[gpio_width-1:0] gpio_t, // 0->输出, 1->输入
    input wire[gpio_width-1:0] gpio_i,
    
    // 中断
    output wire gpio_itr
);
    
    /** GPIO三态总线 **/
    wire[gpio_width-1:0] gpio_o_w;
    wire[gpio_width-1:0] gpio_t_w;
    wire[gpio_width-1:0] gpio_i_w;
    
    generate
        if(gpio_dire != "input")
            assign gpio_o = gpio_o_w;
        else
            assign gpio_o = default_output_value;
        
        if(gpio_dire == "inout")
            assign gpio_t = gpio_t_w;
        else if(gpio_dire == "input")
            assign gpio_t = 32'hffff_ffff;
        else
            assign gpio_t = 32'h0000_0000;
        
        if(gpio_dire != "output")
        begin
            reg[gpio_width-1:0] gpio_i_d;
            reg[gpio_width-1:0] gpio_i_d2;
            
            assign gpio_i_w = gpio_i_d2;
            
            always @(posedge clk)
            begin
                # simulation_delay;
                
                gpio_i_d <= gpio_i;
                gpio_i_d2 <= gpio_i_d;
            end
        end
        else
            assign gpio_i_w = gpio_o_w;
    endgenerate
    
    /** GPIO中断 **/
    wire[gpio_width-1:0] gpio_i_w_d; // 延迟1clk的gpio输入
    wire gpio_global_itr_en_w; // 全局中断使能
    wire[gpio_width-1:0] gpio_itr_en_w; // 中断使能
    wire gpio_itr_flag_w; // 中断标志
    wire[gpio_width-1:0] gpio_itr_mask_w; // 中断掩码
    wire[gpio_width-1:0] gpio_itr_mask_w_d; // 延迟1clk的中断掩码
    wire gpio_org_itr_pulse; // 原始中断脉冲
    wire gpio_itr_w; // 中断信号
    
    assign gpio_itr = gpio_itr_w;
    
    generate
        if((en_itr == "true") && (gpio_dire != "output"))
        begin
            reg[gpio_width-1:0] gpio_org_itr_mask_regs;
            reg[gpio_width-1:0] gpio_itr_mask_regs_d;
            reg gpio_org_itr_pulse_reg;
            
            assign gpio_itr_mask_w = gpio_org_itr_mask_regs;
            assign gpio_itr_mask_w_d = gpio_itr_mask_regs_d;
            assign gpio_org_itr_pulse = gpio_org_itr_pulse_reg;
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                begin
                    gpio_org_itr_pulse_reg <= 1'b0;
                    gpio_org_itr_mask_regs <= {gpio_width{1'b0}};
                    gpio_itr_mask_regs_d <= {gpio_width{1'b0}};
                end
                else
                begin
                    # simulation_delay;
                    
                    gpio_org_itr_pulse_reg <= (gpio_org_itr_mask_regs != {gpio_width{1'b0}}) & gpio_global_itr_en_w & (~gpio_itr_flag_w); // 原始中断脉冲
                    gpio_org_itr_mask_regs <= ((itr_edge == "pos") ? (gpio_i_w & (~gpio_i_w_d)):((~gpio_i_w) & gpio_i_w_d)) & // 捕获上升沿或下降沿
                        gpio_t_w & // 仅考虑输入模式gpio的中断
                        gpio_itr_en_w; // gpio输入中断使能
                    gpio_itr_mask_regs_d <= gpio_org_itr_mask_regs; // 对中断状态打1拍
                end
            end
            
            // 对原始中断脉冲进行延展
            itr_generator #(
                .pulse_w(10),
                .simulation_delay(simulation_delay)
            )itr_generator_u(
                .clk(clk),
                .rst_n(resetn),
                .itr_org(gpio_org_itr_pulse),
                .itr(gpio_itr_w)
            );
        end
        else
        begin
            assign gpio_itr_w = 1'b0;
            
            assign gpio_itr_mask_w = 32'd0;
            assign gpio_org_itr_pulse = 1'b0;
        end
    endgenerate
    
    /** APB写寄存器 **/
    reg[31:0] gpio_o_value_regs; // GPIO输出
    reg[31:0] gpio_o_mask_regs; // GPIO写电平掩码
    reg[31:0] gpio_direction_regs; // GPIO方向
    reg[31:0] gpio_i_value_regs; // GPIO输入
    reg[31:0] gpio_itr_status_regs; // 全局中断使能, 中断标志
    reg[31:0] gpio_itr_mask_regs; // 中断状态
    reg[31:0] gpio_itr_en_regs; // 中断使能
    
    assign gpio_o_w = gpio_o_value_regs[gpio_width-1:0];
    assign gpio_t_w = gpio_direction_regs[gpio_width-1:0];
    
    assign gpio_i_w_d = gpio_i_value_regs[gpio_width-1:0];
    assign gpio_global_itr_en_w = gpio_itr_status_regs[0];
    assign gpio_itr_en_w = gpio_itr_en_regs;
    assign gpio_itr_flag_w = gpio_itr_status_regs[1];
    
    genvar gpio_o_value_regs_i;
    generate
        for(gpio_o_value_regs_i = 0;gpio_o_value_regs_i < gpio_width;gpio_o_value_regs_i = gpio_o_value_regs_i + 1)
        begin
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                    gpio_o_value_regs[gpio_o_value_regs_i] <= default_output_value[gpio_o_value_regs_i];
                else if(psel & pwrite & penable & (paddr[4:2] == 3'd0) & gpio_o_mask_regs[gpio_o_value_regs_i]) // 写GPIO输出电平
                    # simulation_delay gpio_o_value_regs[gpio_o_value_regs_i] <= pwdata[gpio_o_value_regs_i];
            end
        end
    endgenerate
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
        begin
            gpio_o_mask_regs[gpio_width-1:0] <= {gpio_width{1'b1}};
            
            if(gpio_dire == "inout")
                gpio_direction_regs[gpio_width-1:0] <= default_tri_value;
            else if(gpio_dire == "input")
                gpio_direction_regs[gpio_width-1:0] <= {gpio_width{1'b1}};
            else
                gpio_direction_regs[gpio_width-1:0] <= {gpio_width{1'b0}};
            
            gpio_itr_status_regs[0] <= 1'b0;
            gpio_itr_en_regs[gpio_width-1:0] <= {gpio_width{1'b0}};
        end
        else if(psel & pwrite & penable)
        begin
            # simulation_delay;
            
            case(paddr[4:2])
                3'd1: // 写GPIO写电平掩码
                    gpio_o_mask_regs[gpio_width-1:0] <= pwdata[gpio_width-1:0];
                3'd2: // 写GPIO方向, 仅inout下修改有效
                    gpio_direction_regs[gpio_width-1:0] <= pwdata[gpio_width-1:0];
                3'd4: // 写全局中断使能
                    gpio_itr_status_regs[0] <= pwdata[0];
                3'd6: // 写中断使能
                    gpio_itr_en_regs[gpio_width-1:0] <= pwdata[gpio_width-1:0];
                default: // hold
                begin
                    gpio_o_mask_regs[gpio_width-1:0] <= gpio_o_mask_regs[gpio_width-1:0];
                    gpio_direction_regs[gpio_width-1:0] <= gpio_direction_regs[gpio_width-1:0];
                    gpio_itr_status_regs[0] <= gpio_itr_status_regs[0];
                    gpio_itr_en_regs[gpio_width-1:0] <= gpio_itr_en_regs[gpio_width-1:0];
                end
            endcase
        end
    end
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            gpio_itr_status_regs[1] <= 1'b0;
        else if(psel & pwrite & penable & (paddr[4:2] == 3'd4)) // 清除中断标志
            # simulation_delay gpio_itr_status_regs[1] <= 1'b0;
        else if(~gpio_itr_status_regs[1]) // 等待新的GPIO中断, 中断标志为高时屏蔽新的GPIO中断
            # simulation_delay gpio_itr_status_regs[1] <= gpio_org_itr_pulse;
    end
    
    // 生成状态信息
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
        begin
            gpio_i_value_regs[gpio_width-1:0] <= (itr_edge == "pos") ? {gpio_width{1'b0}}:{gpio_width{1'b1}};
            gpio_itr_mask_regs[gpio_width-1:0] <= {gpio_width{1'b0}};
        end
        else
        begin
            # simulation_delay;
            
            gpio_i_value_regs[gpio_width-1:0] <= gpio_i_w; // 载入GPIO输入电平
            
            if(gpio_org_itr_pulse) // 载入中断状态
                gpio_itr_mask_regs[gpio_width-1:0] <= gpio_itr_mask_w_d;
        end
    end
    
    /** APB读寄存器 **/
    reg[31:0] prdata_out_regs;
	
	assign pready_out = 1'b1;
    assign pslverr_out = 1'b0;
    assign prdata_out = prdata_out_regs;
    
	generate
		if(simulation_delay == 0)
		begin
			always @(posedge clk)
			begin
				if(psel & (~pwrite))
				begin
					# simulation_delay;
					
					case(paddr[4:2])
						3'd3: // 读GPIO输入
							prdata_out_regs <= {{(32-gpio_width){1'bx}}, gpio_i_value_regs[gpio_width-1:0]};
						3'd4: // 读中断标志
							prdata_out_regs <= {30'dx, gpio_itr_status_regs[1], 1'bx};
						3'd5: // 读中断状态
							prdata_out_regs <= {{(32-gpio_width){1'bx}}, gpio_itr_mask_regs[gpio_width-1:0]};
						default: // not care
							prdata_out_regs <= 32'dx;
					endcase
				end
			end
		end
		else
		begin
			always @(posedge clk)
			begin
				if(psel & (~pwrite))
				begin
					# simulation_delay;
					
					case(paddr[4:2])
						3'd3: // 读GPIO输入
							prdata_out_regs <= {{(32-gpio_width){1'b0}}, gpio_i_value_regs[gpio_width-1:0]};
						3'd4: // 读中断标志
							prdata_out_regs <= {30'd0, gpio_itr_status_regs[1], 1'b0};
						3'd5: // 读中断状态
							prdata_out_regs <= {{(32-gpio_width){1'b0}}, gpio_itr_mask_regs[gpio_width-1:0]};
						default: // not care
							prdata_out_regs <= 32'd0;
					endcase
				end
			end
		end
	endgenerate
	
    

endmodule
