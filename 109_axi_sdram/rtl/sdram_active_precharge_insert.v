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
本模块: sdram激活/预充电命令插入模块

描述:
根据用户命令, 向读写数据命令前面插入合适的激活和预充电命令

当不是全页突发且允许自动预充电时, 本模块会使能读写数据命令的自动预充电

注意：
无

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/03/02
********************************************************************/


module sdram_active_precharge_insert #(
    parameter integer BURST_LEN = -1, // 突发长度(-1 -> 全页; 1 | 2 | 4 | 8)
    parameter ALLOW_AUTO_PRECHARGE = "true", // 是否允许自动预充电
    parameter EN_CMD_AXIS_REG_SLICE = "true", // 是否使能命令AXIS寄存器片
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 用户命令AXIS
    input wire[39:0] s_axis_usr_cmd_data, // {保留(3bit), ba(2bit), 行地址(16bit), A15-0(16bit), 命令号(3bit)}
    input wire[16:0] s_axis_usr_cmd_user, // {是否自动添加"停止突发"命令(1bit), 突发长度 - 1(16bit)}(仅对全页突发有效)
    input wire s_axis_usr_cmd_valid,
    output wire s_axis_usr_cmd_ready,
    
    // 插入激活/预充电命令后的命令AXIS
    output wire[23:0] m_axis_inserted_cmd_data, // {保留(3bit), BS(2bit), A15-0(16bit), 命令号(3bit)}
    output wire[16:0] m_axis_inserted_cmd_user, // {是否自动添加"停止突发"命令(1bit), 突发长度 - 1(16bit)}(仅对全页突发有效)
    output wire m_axis_inserted_cmd_valid,
    input wire m_axis_inserted_cmd_ready
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
    
    /** 常量 **/
    localparam RW_DATA_WITH_AUTO_PRECHARGE = (BURST_LEN == -1) ? "false":ALLOW_AUTO_PRECHARGE; // 使能读写数据命令的自动预充电
    // 命令的逻辑编码
    localparam CMD_LOGI_BANK_ACTIVE = 3'b000; // 命令:激活bank
    localparam CMD_LOGI_BANK_PRECHARGE = 3'b001; // 命令:预充电bank
    localparam CMD_LOGI_WT_DATA = 3'b010; // 命令:写数据
    localparam CMD_LOGI_RD_DATA = 3'b011; // 命令:读数据
    
    /** 可选的命令AXIS寄存器片 **/
    wire[39:0] m_axis_usr_cmd_data; // {保留(3bit), ba(2bit), 行地址(16bit), A15-0(16bit), 命令号(3bit)}
    wire[16:0] m_axis_usr_cmd_user; // {是否自动添加"停止突发"命令(1bit), 突发长度 - 1(16bit)}(仅对全页突发有效)
    wire m_axis_usr_cmd_valid;
    wire m_axis_usr_cmd_ready;
    
    axis_reg_slice #(
        .data_width(40),
        .user_width(17),
        .forward_registered(EN_CMD_AXIS_REG_SLICE),
        .back_registered(EN_CMD_AXIS_REG_SLICE),
        .en_ready("true"),
        .simulation_delay(SIM_DELAY)
    )usr_cmd_axis_reg_slice(
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_data(s_axis_usr_cmd_data),
        .s_axis_keep(),
        .s_axis_user(s_axis_usr_cmd_user),
        .s_axis_last(),
        .s_axis_valid(s_axis_usr_cmd_valid),
        .s_axis_ready(s_axis_usr_cmd_ready),
        .m_axis_data(m_axis_usr_cmd_data),
        .m_axis_keep(),
        .m_axis_user(m_axis_usr_cmd_user),
        .m_axis_last(),
        .m_axis_valid(m_axis_usr_cmd_valid),
        .m_axis_ready(m_axis_usr_cmd_ready)
    );
    
    /**
    bank空闲与激活状态判定
    
    这里对齐到插入激活/预充电命令后的命令AXIS, 并非真实的bank空闲与激活状态
    **/
    reg[3:0] spec_bank_active; // 各个bank是否激活
    reg[15:0] bank_active_row[3:0]; // 各个bank激活的行
    
    // 各个bank是否激活
    // bank被激活的行
    genvar spec_bank_active_i;
    genvar bank_active_row_i;
    generate
        // 各个bank是否激活
        for(spec_bank_active_i = 0;spec_bank_active_i < 4;spec_bank_active_i = spec_bank_active_i + 1)
        begin:spec_bank_active_blk
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    spec_bank_active[spec_bank_active_i] <= 1'b0;
                else if((m_axis_inserted_cmd_valid & m_axis_inserted_cmd_ready) & 
                    (((m_axis_inserted_cmd_data[2:0] == CMD_LOGI_BANK_ACTIVE) & (m_axis_inserted_cmd_data[20:19] == spec_bank_active_i)) | // 激活
                    ((m_axis_inserted_cmd_data[2:0] == CMD_LOGI_BANK_PRECHARGE) & (m_axis_inserted_cmd_data[20:19] == spec_bank_active_i)) | // 预充电
                    (((m_axis_inserted_cmd_data[2:0] == CMD_LOGI_WT_DATA) | (m_axis_inserted_cmd_data[2:0] == CMD_LOGI_RD_DATA)) & 
                        m_axis_inserted_cmd_data[13] & (m_axis_inserted_cmd_data[20:19] == spec_bank_active_i) & 
                        (RW_DATA_WITH_AUTO_PRECHARGE == "true")))) // 带自动预充电的读写
                    spec_bank_active[spec_bank_active_i] <= # SIM_DELAY m_axis_inserted_cmd_data[2:0] == CMD_LOGI_BANK_ACTIVE;
            end
        end
        
        // bank被激活的行
        for(bank_active_row_i = 0;bank_active_row_i < 4;bank_active_row_i = bank_active_row_i + 1)
        begin:bank_active_row_blk
            always @(posedge clk)
            begin
                if((m_axis_inserted_cmd_valid & m_axis_inserted_cmd_ready) & 
                    ((m_axis_inserted_cmd_data[2:0] == CMD_LOGI_BANK_ACTIVE) & (m_axis_inserted_cmd_data[20:19] == bank_active_row_i)))
                    bank_active_row[bank_active_row_i] <= # SIM_DELAY m_axis_inserted_cmd_data[18:3];
            end
        end
    endgenerate
    
    /**
    激活/预充电命令的插入
    
    不使能读写数据命令的自动预充电: [预充电] -> [激活] -> [读写数据]
    使能读写数据命令的自动预充电: [预充电] -> [激活] -> 读写数据([自动预充电])
    **/
    wire is_rw_cmd; // 是否读写数据命令
    reg precharge_need; // 需要预充电(标志)
    reg active_need; // 需要激活(标志)
    wire usr_cmd_suspend; // 用户命令AXIS等待
    reg[1:0] insert_stage_cnt; // 激活/预充电命令插入阶段计数器
    
    assign m_axis_inserted_cmd_user = m_axis_usr_cmd_user;
    assign m_axis_usr_cmd_ready = m_axis_inserted_cmd_ready & (~usr_cmd_suspend);
	
	assign m_axis_inserted_cmd_data[23:21] = 3'bxxx;
    assign m_axis_inserted_cmd_data[20:0] = 
        (insert_stage_cnt == 2'd0) ? {m_axis_usr_cmd_data[36:35], m_axis_usr_cmd_data[18:3], m_axis_usr_cmd_data[2:0]}: // pass
        (insert_stage_cnt == 2'd1) ? {m_axis_usr_cmd_data[36:35], 16'bx_xxxx0_xxxxx_xxxxx, CMD_LOGI_BANK_PRECHARGE}: // 预充电
        (insert_stage_cnt == 2'd2) ? {m_axis_usr_cmd_data[36:35], m_axis_usr_cmd_data[34:19], CMD_LOGI_BANK_ACTIVE}: // 激活
                                     {m_axis_usr_cmd_data[36:35], 
										m_axis_usr_cmd_data[18:14], 
										(RW_DATA_WITH_AUTO_PRECHARGE == "ture") ? m_axis_usr_cmd_data[13]:1'b0, 
                                        m_axis_usr_cmd_data[12:3], m_axis_usr_cmd_data[2:0]}; // 读写数据
    
    assign m_axis_inserted_cmd_valid = m_axis_usr_cmd_valid & 
        ((insert_stage_cnt == 2'd0) ? (~is_rw_cmd):
         (insert_stage_cnt == 2'd1) ? precharge_need:
         (insert_stage_cnt == 2'd2) ? active_need:
                                      1'b1);
    
    assign is_rw_cmd = (m_axis_usr_cmd_data[2:0] == CMD_LOGI_WT_DATA) | (m_axis_usr_cmd_data[2:0] == CMD_LOGI_RD_DATA);
    assign usr_cmd_suspend = 
        (insert_stage_cnt == 2'd0) ? is_rw_cmd:
        (insert_stage_cnt == 2'd3) ? 1'b0:
                                     1'b1;
    // 需要预充电(标志)
    always @(posedge clk)
    begin
        if((insert_stage_cnt == 2'd0) & is_rw_cmd)
            precharge_need <= # SIM_DELAY 
				spec_bank_active[m_axis_usr_cmd_data[36:35]] & 
				(bank_active_row[m_axis_usr_cmd_data[36:35]] != m_axis_usr_cmd_data[34:19]);
    end
    
    // 需要激活(标志)
    always @(posedge clk)
    begin
        if((insert_stage_cnt == 2'd0) & is_rw_cmd)
            active_need <= # SIM_DELAY ~(spec_bank_active[m_axis_usr_cmd_data[36:35]] & 
                (bank_active_row[m_axis_usr_cmd_data[36:35]] == m_axis_usr_cmd_data[34:19]));
    end
    
    // 激活/预充电命令插入阶段计数器
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            insert_stage_cnt <= 2'd0;
        else if(m_axis_inserted_cmd_ready & m_axis_usr_cmd_valid & ((insert_stage_cnt != 2'd0) | is_rw_cmd))
            insert_stage_cnt <= # SIM_DELAY (insert_stage_cnt == 2'd3) ? 2'd0:(insert_stage_cnt + 2'd1);
    end
    
endmodule
