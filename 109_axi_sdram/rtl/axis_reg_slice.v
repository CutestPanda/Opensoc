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
本模块: AXIS寄存器片

描述: 
在AXIS主从接口间增加隔离
切割两个AXIS主从接口的时序路径

注意：
无

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2023/10/13
********************************************************************/


module axis_reg_slice #(
    parameter integer data_width = 32, // 数据位宽(必须能被8整除)
    parameter integer user_width = 1, // 用户信号位宽(必须>=1, 不用时悬空即可)
    parameter forward_registered = "false", // 是否使能前向寄存器
    parameter back_registered = "false", // 是否使能后向寄存器
    parameter en_ready = "true", // 是否使用ready信号
	parameter en_clk_en = "false", // 是否使用全局时钟使能信号
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
	input wire clken,
    
    // AXIS SLAVE(从机输入)
    input wire[data_width-1:0] s_axis_data,
    input wire[data_width/8-1:0] s_axis_keep,
    input wire[user_width-1:0] s_axis_user,
    input wire s_axis_last,
    input wire s_axis_valid,
    output wire s_axis_ready,
    
    // AXIS MASTER(主机输出)
    output wire[data_width-1:0] m_axis_data,
    output wire[data_width/8-1:0] m_axis_keep,
    output wire[user_width-1:0] m_axis_user,
    output wire m_axis_last,
    output wire m_axis_valid,
    input wire m_axis_ready
);
    
    generate
        if(en_ready == "true")
        begin
            axis_reg_slice_core #(
                .forward_registered(forward_registered),
                .back_registered(back_registered),
                .payload_width(data_width + data_width/8 + user_width + 1),
                .simulation_delay(simulation_delay)
            )axis_reg_slice_core_u(
                .clk(clk),
                .rst_n(rst_n),
				.clken((en_clk_en == "false") | clken),
                .s_payload({s_axis_data, s_axis_keep, s_axis_user, s_axis_last}),
                .s_valid(s_axis_valid),
                .s_ready(s_axis_ready),
                .m_payload({m_axis_data, m_axis_keep, m_axis_user, m_axis_last}),
                .m_valid(m_axis_valid),
                .m_ready(m_axis_ready)
            );
        end
        else if(forward_registered == "true")
        begin
            reg[data_width-1:0] m_axis_data_regs;
            reg[data_width/8-1:0] m_axis_keep_regs;
            reg[user_width-1:0] m_axis_user_regs;
            reg m_axis_last_reg;
            reg m_axis_valid_reg;
            
            assign s_axis_ready = 1'b1;
            assign {m_axis_data, m_axis_keep, m_axis_user, m_axis_last} = {m_axis_data_regs, m_axis_keep_regs, m_axis_user_regs, m_axis_last_reg};
            assign m_axis_valid = m_axis_valid_reg;
            
            always @(posedge clk)
            begin
                if(s_axis_valid & ((en_clk_en == "false") | clken))
                begin
                    m_axis_data_regs <= # simulation_delay s_axis_data;
                    m_axis_keep_regs <= # simulation_delay s_axis_keep;
                    m_axis_user_regs <= # simulation_delay s_axis_user;
                    m_axis_last_reg <= # simulation_delay s_axis_last;
                end
            end
            
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    m_axis_valid_reg <= 1'b0;
                else if((en_clk_en == "false") | clken)
                    m_axis_valid_reg <= # simulation_delay s_axis_valid;
            end
        end
        else
        begin
            // pass
            assign s_axis_ready = 1'b1;
            assign m_axis_data = s_axis_data;
            assign m_axis_keep = s_axis_keep;
            assign m_axis_user = s_axis_user;
            assign m_axis_last = s_axis_last;
            assign m_axis_valid = s_axis_valid;
        end
    endgenerate

endmodule
