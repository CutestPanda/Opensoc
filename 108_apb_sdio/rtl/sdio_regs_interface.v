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
本模块: APB-SDIO的控制/状态寄存器接口

描述:
寄存器->
    偏移量  |    含义                     |   读写特性    |                备注
    0x00    0:命令fifo是否满                    R
            1:读数据fifo是否空                  R
            2:写数据fifo是否满                  R
    0x04    5~0:命令号                         W             写该寄存器时会产生命令fifo写使能
            15~8:本次读写的块个数-1            W              写该寄存器时会产生命令fifo写使能
    0x08    31~0:命令参数                      W
    0x0C    31~0:读数据                        R             读该寄存器时会产生读数据fifo读使能
    0x10    31~0:写数据                        W             写该寄存器时会产生写数据fifo写使能
    0x14    0:SDIO全局中断使能                  W
            8:SDIO读数据中断使能                W
            9:SDIO写数据中断使能                W
            10:SDIO常规命令处理完成中断使能     W
    0x18    0:SDIO全局中断标志                 RWC              请在中断服务函数中清除中断标志
            8:SDIO读数据中断标志                R
            9:SDIO写数据中断标志                R
            10:SDIO常规命令处理完成中断标志     R
    0x1C    31~0:响应[119:88]                  R
    0x20    31~0:响应[87:56]                   R
    0x24    31~0:响应[55:24]                   R
    0x28    23~0:响应[23:0]                    R
            24:是否长响应                      R
            25:CRC错误                         R
            26:接收超时                        R
    0x2C    0:控制器是否空闲                   R
            5~1:读数据返回结果                 R
            10~8:写数据返回状态信息            R
            16:是否启用sdio时钟               W
            17:是否启用四线模式               W
            27~18:sdio时钟分频系数            W                  分频数 = (分频系数 + 1) * 2
   [0x30,   0:开始初始化标志                  W               写该寄存器并且该位为1时开始初始化
    仅使能   1:初始化模块是否空闲              R
    硬件     23~8:RCA                         R                    初始化结果[18:3]
    初始化   24:初始化是否成功                 R                    初始化结果[0]
    时可用]  25:是否支持SD2.0                  R                    初始化结果[1]
            26:是否大容量卡                   R                     初始化结果[2]

注意：
无

协议:
APB SLAVE
FIFO READ/WRITE
AXIS SLAVE

作者: 陈家耀
日期: 2024/01/23
********************************************************************/


module sdio_regs_interface #(
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
    
    // 命令fifo写端口
    output wire cmd_fifo_wen,
    input wire cmd_fifo_full,
    output wire[45:0] cmd_fifo_din,
    // 读数据fifo读端口
    output wire rdata_fifo_ren,
    input wire rdata_fifo_empty,
    input wire[31:0] rdata_fifo_dout,
    // 写数据fifo写端口
    output wire wdata_fifo_wen,
    input wire wdata_fifo_full,
    output wire[31:0] wdata_fifo_din,
    
    // 控制器状态
    input wire sdio_ctrler_idle,
    // 控制器运行时参数
    output wire en_sdio_clk, // 启用sdio时钟(复位时必须为0)
    output wire[9:0] div_rate, // 分频系数(分频数 = (分频系数 + 1) * 2)
    output wire en_wide_sdio, // 启用四线模式
    // 初始化模块控制
    output wire init_start, // 开始初始化请求(指示)
    input wire init_idle, // 初始化模块空闲(标志)
    
    // 响应AXIS
    input wire[119:0] s_axis_resp_data, // 48bit响应 -> {命令号(6bit), 参数(32bit)}, 136bit响应 -> {参数(120bit)}
    input wire[2:0] s_axis_resp_user, // {接收超时(1bit), CRC错误(1bit), 是否长响应(1bit)}
    input wire s_axis_resp_valid,
    // 初始化结果AXIS
    input wire[23:0] s_axis_init_res_data, // {保留(5bit), RCA(16bit), 是否大容量卡(1bit), 是否支持SD2.0(1bit), 是否成功(1bit)}
    input wire s_axis_init_res_valid,
    // 读数据返回结果AXIS
    input wire[7:0] s_axis_rd_sts_data, // {保留(3bit), 读超时(1bit), 校验结果(4bit)}
    input wire s_axis_rd_sts_valid,
    // 写数据状态返回AXIS
    input wire[7:0] s_axis_wt_sts_data, // {保留(5bit), 状态信息(3bit)}
    input wire s_axis_wt_sts_valid,
    
    // 中断控制
    input wire rdata_itr_org_pulse, // 读数据原始中断脉冲
    input wire wdata_itr_org_pulse, // 写数据原始中断脉冲
    input wire common_itr_org_pulse, // 常规命令处理完成中断脉冲
    output wire rdata_itr_en, // 读数据中断使能
    output wire wdata_itr_en, // 写数据中断使能
    output wire common_itr_en, // 常规命令处理完成中断使能
    output wire global_org_itr_pulse // 全局原始中断脉冲
);

    /** APB写寄存器 **/
    // 命令fifo写端口
    reg cmd_fifo_wen_reg;
    reg[5:0] cmd_fifo_din_id; // 命令号
    reg[31:0] cmd_fifo_din_params; // 命令参数
    reg[7:0] cmd_fifo_din_rw_patch_n; // 本次读写的块个数-1
    // 写数据fifo写端口
    reg wdata_fifo_wen_reg;
    reg[31:0] wdata_fifo_din_regs;
    // 中断使能
    reg global_itr_en_reg; // 全局中断使能
    reg rdata_itr_en_reg; // 读数据中断使能
    reg wdata_itr_en_reg; // 写数据中断使能
    reg common_itr_en_reg; // 常规命令处理完成中断使能
    // 全局中断标志
    reg global_itr_flag;
    // 控制器运行时参数
    reg en_sdio_clk_reg; // 启用sdio时钟(复位时必须为0)
    reg en_wide_sdio_reg; // 是否启用四线模式
    reg[9:0] div_rate_regs; // 分频系数(分频数 = (分频系数 + 1) * 2)
    // 开始初始化指示
    reg init_start_reg;
    
    assign cmd_fifo_wen = cmd_fifo_wen_reg;
    assign cmd_fifo_din = {cmd_fifo_din_rw_patch_n, cmd_fifo_din_id, cmd_fifo_din_params};
    assign wdata_fifo_wen = wdata_fifo_wen_reg;
    assign wdata_fifo_din = wdata_fifo_din_regs;
    assign {en_wide_sdio, div_rate, en_sdio_clk} = {en_wide_sdio_reg, div_rate_regs, en_sdio_clk_reg};
    assign init_start = init_start_reg;
    assign {common_itr_en, wdata_itr_en, rdata_itr_en} = {common_itr_en_reg, wdata_itr_en_reg, rdata_itr_en_reg};
    
    assign global_org_itr_pulse = (rdata_itr_org_pulse | wdata_itr_org_pulse | common_itr_org_pulse) & global_itr_en_reg & (~global_itr_flag);
    
    // 命令fifo写使能
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            cmd_fifo_wen_reg <= 1'b0;
        else
            # simulation_delay cmd_fifo_wen_reg <= psel & pwrite & penable & (paddr[5:2] == 4'd1);
    end
    // 命令号
    always @(posedge clk)
    begin
        if(psel & pwrite & penable & (paddr[5:2] == 4'd1))
            # simulation_delay cmd_fifo_din_id <= pwdata[5:0];
    end
    // 命令参数
    always @(posedge clk)
    begin
        if(psel & pwrite & penable & (paddr[5:2] == 4'd2))
            # simulation_delay cmd_fifo_din_params <= pwdata;
    end
    // 本次读写的块个数-1
    always @(posedge clk)
    begin
        if(psel & pwrite & penable & (paddr[5:2] == 4'd1))
            # simulation_delay cmd_fifo_din_rw_patch_n <= pwdata[15:8];
    end
    
    // 写数据fifo写使能
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            wdata_fifo_wen_reg <= 1'b0;
        else
            # simulation_delay wdata_fifo_wen_reg <= psel & pwrite & penable & (paddr[5:2] == 4'd4);
    end
    // 写数据fifo写数据
    always @(posedge clk)
    begin
        if(psel & pwrite & penable & (paddr[5:2] == 4'd4))
            # simulation_delay wdata_fifo_din_regs <= pwdata;
    end
    
    // 中断使能
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            {common_itr_en_reg, wdata_itr_en_reg, rdata_itr_en_reg, global_itr_en_reg} <= 4'b0000;
        else if(psel & pwrite & penable & (paddr[5:2] == 4'd5))
            # simulation_delay {common_itr_en_reg, wdata_itr_en_reg, rdata_itr_en_reg, global_itr_en_reg} <= {pwdata[10:8], pwdata[0]};
    end
    
    // 全局中断标志
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            global_itr_flag <= 1'b0;
        else if(psel & pwrite & penable & (paddr[5:2] == 4'd6)) // 清除中断标志
            # simulation_delay global_itr_flag <= 1'b0;
        else if(~global_itr_flag)
            # simulation_delay global_itr_flag <= global_org_itr_pulse;
    end
    
    // 启用sdio时钟(复位时必须为0)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            en_sdio_clk_reg <= 1'b0;
        else if(psel & pwrite & penable & (paddr[5:2] == 4'd11))
            # simulation_delay en_sdio_clk_reg <= pwdata[16];
    end
    // 是否启用四线模式
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            en_wide_sdio_reg <= 1'b0;
        else if(psel & pwrite & penable & (paddr[5:2] == 4'd11))
            # simulation_delay en_wide_sdio_reg <= pwdata[17];
    end
    // 分频系数(分频数 = (分频系数 + 1) * 2)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            div_rate_regs <= 10'd99;
        else if(psel & pwrite & penable & (paddr[5:2] == 4'd11))
            # simulation_delay div_rate_regs <= pwdata[27:18];
    end
    
    // 开始初始化指示
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            init_start_reg <= 1'b0;
        else
            # simulation_delay init_start_reg <= psel & pwrite & penable & (paddr[5:2] == 4'd12) & pwdata[0];
    end
    
    /** 子中断标志 **/
    reg rdata_itr_flag; // SDIO读数据中断标志
    reg wdata_itr_flag; // SDIO写数据中断标志
    reg common_itr_flag; // SDIO常规命令处理完成中断标志
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            {rdata_itr_flag, wdata_itr_flag, common_itr_flag} <= 3'b000;
        else if(global_org_itr_pulse)
            # simulation_delay {rdata_itr_flag, wdata_itr_flag, common_itr_flag} <= {rdata_itr_org_pulse, wdata_itr_org_pulse, common_itr_org_pulse};
    end
    
    /** 响应 **/
    reg[119:0] resp_content;
    reg[2:0] resp_sts;
    
    always @(posedge clk)
    begin
        if(s_axis_resp_valid)
            # simulation_delay {resp_content, resp_sts} <= {s_axis_resp_data, s_axis_resp_user};
    end
    
    /** 初始化结果 **/
    reg[15:0] rca;
    reg init_succeeded;
    reg sd2_supported;
    reg is_large_volume_card;
    
    always @(posedge clk)
    begin
        if(s_axis_init_res_valid)
            # simulation_delay {rca, is_large_volume_card, sd2_supported, init_succeeded} <= s_axis_init_res_data[18:0];
    end
    
    /** 读数据返回结果 **/
    reg[4:0] rd_res;
    
    always @(posedge clk)
    begin
        if(s_axis_rd_sts_valid)
            # simulation_delay rd_res <= s_axis_rd_sts_data[4:0];
    end
    
    /** 写数据状态返回AXIS **/
    reg[2:0] wt_sts;
    
    always @(posedge clk)
    begin
        if(s_axis_wt_sts_valid)
            # simulation_delay wt_sts <= s_axis_wt_sts_data[2:0];
    end
    
    /** APB读寄存器 **/
    reg[31:0] prdata_out_regs;
    reg rdata_visited;
    
    assign rdata_fifo_ren = rdata_visited & penable;
    
    assign pready_out = 1'b1;
    assign prdata_out = prdata_out_regs;
    assign pslverr_out = 1'b0;
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            rdata_visited <= 1'b0;
        else
            # simulation_delay rdata_visited <= psel & (~pwrite) & (paddr[5:2] == 4'd3);
    end
    
    always @(posedge clk)
    begin
        if(psel & (~pwrite))
        begin
            # simulation_delay;
            
            case(paddr[5:2])
                4'd0:
                    prdata_out_regs <= {29'dx, wdata_fifo_full, rdata_fifo_empty, cmd_fifo_full};
                4'd3:
                    prdata_out_regs <= rdata_fifo_dout;
                4'd6:
                    prdata_out_regs <= {21'dx, common_itr_flag, wdata_itr_flag, rdata_itr_flag, 7'dx, global_itr_flag};
                4'd7:
                    prdata_out_regs <= resp_content[119:88];
                4'd8:
                    prdata_out_regs <= resp_content[87:56];
                4'd9:
                    prdata_out_regs <= resp_content[55:24];
                4'd10:
                    prdata_out_regs <= {9'dx, resp_sts, resp_content[23:0]};
                4'd11:
                    prdata_out_regs <= {21'dx, wt_sts, 2'dx, rd_res, sdio_ctrler_idle};
                4'd12:
                    prdata_out_regs <= {5'dx, is_large_volume_card, sd2_supported, init_succeeded, rca, 6'dx, init_idle, 1'bx};
                default: // not care
                    prdata_out_regs <= 32'dx;
            endcase
        end
    end

endmodule
