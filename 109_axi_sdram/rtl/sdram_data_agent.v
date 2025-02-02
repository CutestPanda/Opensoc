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
本模块: sdram数据代理

描述:
写数据广义fifo -> sdram写数据
sdram读数据 -> 读数据广义fifo

注意：
写数据广义fifo的MEM读延迟 = 1clk
写/读数据广义fifo总深度固定为512
当突发长度为全页时, 写/读数据广义fifo的数据片深度为256, 其他情况时为突发长度

协议:
EXT FIFO READ/WRITE

作者: 陈家耀
日期: 2024/04/14
********************************************************************/


module sdram_data_agent #(
    parameter integer rw_data_buffer_depth = 1024, // 读写数据buffer深度(512 | 1024 | 2048 | 4096)
    parameter integer burst_len = -1, // 突发长度(-1 -> 全页; 1 | 2 | 4 | 8)
    parameter integer cas_latency = 2, // sdram读潜伏期时延(2 | 3)
    parameter integer data_width = 32, // 数据位宽
    parameter en_expt_tip = "false", // 是否使能异常指示
    parameter real sdram_if_signal_delay = 2.5 // sdram接口信号延迟
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 突发信息
    input wire new_burst_start, // 突发开始指示
    input wire is_write_burst, // 是否写突发
    input wire[7:0] new_burst_len, // 突发长度 - 1
    
    // 写数据广义fifo读端口
    output wire wdata_ext_fifo_ren,
    input wire wdata_ext_fifo_empty_n,
    output wire wdata_ext_fifo_mem_ren, // const -> 1'b1
    output wire[clogb2(rw_data_buffer_depth-1):0] wdata_ext_fifo_mem_raddr,
    input wire[data_width+data_width/8-1:0] wdata_ext_fifo_mem_dout, // {keep(data_width/8 bit), data(data_width bit)}
    
    // 读数据广义fifo写端口
    output wire rdata_ext_fifo_wen,
    input wire rdata_ext_fifo_full_n,
    output wire rdata_ext_fifo_mem_wen,
    output wire[clogb2(rw_data_buffer_depth-1):0] rdata_ext_fifo_mem_waddr,
    output wire[data_width:0] rdata_ext_fifo_mem_din, // {last(1bit), data(data_width bit)}
    
    // sdram数据线
    output wire[data_width/8-1:0] sdram_dqm, // 1'b0 -> data write/output enable; 1'b1 -> data mask/output disable
    input wire[data_width-1:0] sdram_dq_i,
    output wire sdram_dq_t, // 三态门方向(1表示输入, 0表示输出)
    output wire[data_width-1:0] sdram_dq_o,
    
    // 异常指示
    output wire ld_when_wdata_ext_fifo_empty_err, // 在写数据广义fifo空时取数据(异常指示)
    output wire st_when_rdata_ext_fifo_full_err // 在读数据广义fifo满时存数据(异常指示)
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
    // 由于写数据广义fifo中读地址->读数据时延为2clk, 所以对sdram命令延迟2clk, 产生额外2clk的sdram突发读时延
    localparam integer sdram_burst_rd_latency = cas_latency + 2; // sdram突发读时延
    
    /** sdram数据线 **/
    reg wt_burst_start_d; // 延迟1clk的写突发开始(指示)
    wire wdata_ext_fifo_ren_d2; // 延迟2clk的写数据广义fifo读使能
    reg sdram_dq_t_reg; // sdram数据三态门方向
    reg[data_width-1:0] wdata_ext_fifo_mem_dout_data_d; // 延迟1clk的写数据广义fifo的MEM读数据中的data
    wire wdata_cmd_vld_p2; // 提前2clk的正在写数据(指示)
    wire rdata_cmd_vld_p2; // 提前2clk的正在读数据(指示)
    reg wdata_cmd_vld_p1; // 提前1clk的正在写数据(指示)
    reg rdata_cmd_vld_p1; // 提前1clk的正在读数据(指示)
    reg rdata_cmd_vld; // 正在读数据(指示)
    reg[data_width/8-1:0] sdram_dqm_regs; // sdram字节掩码
    
    assign sdram_dqm = sdram_dqm_regs;
    assign sdram_dq_t = sdram_dq_t_reg;
    assign sdram_dq_o = wdata_ext_fifo_mem_dout_data_d;
    
    // 提前1clk的正在写数据(指示)
    // 提前1clk的正在读数据(指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            {wdata_cmd_vld_p1, rdata_cmd_vld_p1} <= 2'b00;
        else
            {wdata_cmd_vld_p1, rdata_cmd_vld_p1} <= {wdata_cmd_vld_p2, rdata_cmd_vld_p2};
    end
    
    // 正在读数据(指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rdata_cmd_vld <= 1'b0;
        else
            rdata_cmd_vld <= rdata_cmd_vld_p1;
    end
    
    // sdram字节掩码
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            sdram_dqm_regs <= {(data_width/8){1'b1}};
        else
        begin
            // 断言:wdata_cmd_vld_p1和rdata_cmd_vld_p1不可能同时为1
            case({wdata_cmd_vld_p1, (cas_latency == 2) ? rdata_cmd_vld_p1:rdata_cmd_vld})
                2'b01: sdram_dqm_regs <= # sdram_if_signal_delay {(data_width/8){1'b0}}; // 读数据时DQM都有效, 也就是允许obuffer输出
                2'b10: sdram_dqm_regs <= # sdram_if_signal_delay (~wdata_ext_fifo_mem_dout[data_width+data_width/8-1:data_width]); // 写数据时取keep信号的按位反
                default: sdram_dqm_regs <= # sdram_if_signal_delay {(data_width/8){1'b1}}; // 非读写时DQM都无效
            endcase
        end
    end
    
    // 延迟1clk的写突发开始(指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_burst_start_d <= 1'b0;
        else
            wt_burst_start_d <= new_burst_start & is_write_burst;
    end
    
    // sdram数据三态门方向
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            sdram_dq_t_reg <= 1'b1;
        else if(wt_burst_start_d | wdata_ext_fifo_ren_d2)
            /*
            wt_burst_start_d wdata_ext_fifo_ren_d2 | sdram_dq_t_reg
                   0                  0                  hold
                   0                  1                 1, 输入
                   1                  0                 0, 输出
                   1                  1                 0, 输出
            */
            sdram_dq_t_reg <= # sdram_if_signal_delay (~wt_burst_start_d);
    end
    
    // 延迟1clk的写数据广义fifo的MEM读数据
    always @(posedge clk)
        wdata_ext_fifo_mem_dout_data_d <= # sdram_if_signal_delay wdata_ext_fifo_mem_dout[data_width-1:0];
    
    // 延迟2clk的写数据广义fifo读使能
    ram_based_shift_regs #(
        .data_width(1),
        .delay_n(2),
        .shift_type("ff"),
        .ram_type(),
        .INIT_FILE(),
        .en_output_register_init("true"),
        .output_register_init_v(1'b0),
        .simulation_delay(0)
    )delay_for_wdata_ext_fifo_ren(
        .clk(clk),
        .resetn(rst_n),
        .shift_in(wdata_ext_fifo_ren),
        .ce(1'b1),
        .shift_out(wdata_ext_fifo_ren_d2)
    );
    
    /** 写数据广义fifo **/
    reg[clogb2(rw_data_buffer_depth-1):0] wdata_ext_fifo_mem_raddr_regs; // 写数据广义fifo的MEM读地址
    wire wdata_ext_fifo_ld_data; // 从写数据广义fifo加载数据(指示)
    
    assign wdata_ext_fifo_mem_ren = 1'b1;
    assign wdata_ext_fifo_mem_raddr = wdata_ext_fifo_mem_raddr_regs;
    
    generate
        if(burst_len == 1)
        begin
            assign wdata_ext_fifo_ren = new_burst_start & is_write_burst;
            assign wdata_ext_fifo_ld_data = new_burst_start & is_write_burst;
            assign wdata_cmd_vld_p2 = new_burst_start & is_write_burst;
            
            // 写数据广义fifo的MEM读地址
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_raddr_regs <= 0;
                else if(new_burst_start & is_write_burst)
                    wdata_ext_fifo_mem_raddr_regs <= wdata_ext_fifo_mem_raddr_regs + 1;
            end
        end
        else if((burst_len == 2) | (burst_len == 4) | (burst_len == 8))
        begin
            reg[burst_len-1:0] wdata_ext_fifo_item_cnt; // 写数据广义fifo数据片读计数器
            
            assign wdata_ext_fifo_ren = wdata_ext_fifo_item_cnt[burst_len-1];
            assign wdata_ext_fifo_ld_data = (new_burst_start & is_write_burst) | (~wdata_ext_fifo_item_cnt[0]);
            assign wdata_cmd_vld_p2 = (new_burst_start & is_write_burst) | (~wdata_ext_fifo_item_cnt[0]);
            
            // 写数据广义fifo数据片读计数器
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_item_cnt <= {{(burst_len-1){1'b0}}, 1'b1};
                else if((new_burst_start & is_write_burst) | (~wdata_ext_fifo_item_cnt[0]))
                    wdata_ext_fifo_item_cnt <= {wdata_ext_fifo_item_cnt[burst_len-2:0], wdata_ext_fifo_item_cnt[burst_len-1]};
            end
            
            // 写数据广义fifo的MEM读地址
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_raddr_regs <= 0;
                else if((new_burst_start & is_write_burst) | (~wdata_ext_fifo_item_cnt[0]))
                    wdata_ext_fifo_mem_raddr_regs <= wdata_ext_fifo_mem_raddr_regs + 1;
            end
        end
        else // burst_len == -1, 全页突发
        begin
            reg[7:0] burst_len_latched; // 锁存的(突发长度 - 1)
            reg wt_burst_transmitting; // 正在进行写突发(标志)
            reg[7:0] wdata_ext_fifo_item_cnt; // 写数据广义fifo数据片读计数器
            
            assign wdata_ext_fifo_ren = wt_burst_transmitting ? 
                (wdata_ext_fifo_item_cnt == burst_len_latched):
                (new_burst_start & is_write_burst & (new_burst_len == 8'd0));
            assign wdata_ext_fifo_ld_data = (new_burst_start & is_write_burst) | wt_burst_transmitting;
            assign wdata_cmd_vld_p2 = (new_burst_start & is_write_burst) | wt_burst_transmitting;
            
            // 锁存的(突发长度 - 1)
            always @(posedge clk)
            begin
                if(new_burst_start & is_write_burst)
                    burst_len_latched <= new_burst_len;
            end
            
            // 正在进行写突发(标志)
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wt_burst_transmitting <= 1'b0;
                else
                    wt_burst_transmitting <= wt_burst_transmitting ? (wdata_ext_fifo_item_cnt != burst_len_latched):(new_burst_start & is_write_burst & (new_burst_len != 8'd0));
            end
            
            // 写数据广义fifo数据片读计数器
            always @(posedge clk)
            begin
                if(new_burst_start & is_write_burst)
                    wdata_ext_fifo_item_cnt <= 8'd1; // 写突发开始时就已取出1个数据, 因此数据片读计数器初始时应载入1
                else if(wt_burst_transmitting)
                    wdata_ext_fifo_item_cnt <= wdata_ext_fifo_item_cnt + 8'd1;
            end
            
            // 写数据广义fifo的MEM读地址
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_raddr_regs[clogb2(rw_data_buffer_depth-1):8] <= 0;
                else if(wdata_ext_fifo_ren)
                    wdata_ext_fifo_mem_raddr_regs[clogb2(rw_data_buffer_depth-1):8] <= wdata_ext_fifo_mem_raddr_regs[clogb2(rw_data_buffer_depth-1):8] + 1;
            end
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_raddr_regs[7:0] <= 8'd0;
                else if(wdata_ext_fifo_ren)
                    wdata_ext_fifo_mem_raddr_regs[7:0] <= 8'd0;
                else if(wt_burst_transmitting | (new_burst_start & is_write_burst))
                    wdata_ext_fifo_mem_raddr_regs[7:0] <= wdata_ext_fifo_mem_raddr_regs[7:0] + 8'd1;
            end
        end
    endgenerate
    
    /** 读数据广义fifo **/
    reg[clogb2(rw_data_buffer_depth-1):0] rdata_ext_fifo_mem_waddr_regs; // 读数据广义fifo的MEM写地址
    wire rdata_ext_fifo_st_data; // 向读数据广义fifo存入数据(指示)
    
    assign rdata_ext_fifo_mem_waddr = rdata_ext_fifo_mem_waddr_regs;
    assign rdata_ext_fifo_mem_din = {rdata_ext_fifo_wen, sdram_dq_i};
    
    generate
        if(burst_len == 1)
        begin
            assign rdata_ext_fifo_wen = rdata_ext_fifo_mem_wen;
            assign rdata_ext_fifo_st_data = rdata_ext_fifo_mem_wen;
            assign rdata_cmd_vld_p2 = new_burst_start & (~is_write_burst);
            
            // 读数据广义fifo的MEM写使能
            ram_based_shift_regs #(
                .data_width(1),
                .delay_n(sdram_burst_rd_latency),
                .shift_type("ff"),
                .ram_type(),
                .INIT_FILE(),
                .en_output_register_init("true"),
                .output_register_init_v(1'b0),
                .simulation_delay(0)
            )delay_for_rd_burst_start(
                .clk(clk),
                .resetn(rst_n),
                .shift_in(new_burst_start & (~is_write_burst)),
                .ce(1'b1),
                .shift_out(rdata_ext_fifo_mem_wen)
            );
            
            // 读数据广义fifo的MEM写地址
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_waddr_regs <= 0;
                else if(rdata_ext_fifo_mem_wen)
                    rdata_ext_fifo_mem_waddr_regs <= rdata_ext_fifo_mem_waddr_regs + 1;
            end
        end
        else if((burst_len == 2) | (burst_len == 4) | (burst_len == 8))
        begin
            reg[burst_len-1:0] rdata_ext_fifo_item_cnt; // 读数据广义fifo数据片写计数器
            
            assign rdata_ext_fifo_st_data = rdata_ext_fifo_mem_wen;
            assign rdata_cmd_vld_p2 = (new_burst_start & (~is_write_burst)) | (~rdata_ext_fifo_item_cnt[0]);
            
            // 读数据广义fifo数据片写计数器
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_item_cnt <= {{(burst_len-1){1'b0}}, 1'b1};
                else if((new_burst_start & (~is_write_burst)) | (~rdata_ext_fifo_item_cnt[0]))
                    rdata_ext_fifo_item_cnt <= {rdata_ext_fifo_item_cnt[burst_len-2:0], rdata_ext_fifo_item_cnt[burst_len-1]};
            end
            
            // 读数据广义fifo的MEM写地址
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_waddr_regs <= 0;
                else if(rdata_ext_fifo_mem_wen)
                    rdata_ext_fifo_mem_waddr_regs <= rdata_ext_fifo_mem_waddr_regs + 1;
            end
            
            // 读数据广义fifo写使能
            ram_based_shift_regs #(
                .data_width(1),
                .delay_n(sdram_burst_rd_latency),
                .shift_type("ff"),
                .ram_type(),
                .INIT_FILE(),
                .en_output_register_init("true"),
                .output_register_init_v(1'b0),
                .simulation_delay(0)
            )delay_for_last_trans_at_burst(
                .clk(clk),
                .resetn(rst_n),
                .shift_in(rdata_ext_fifo_item_cnt[burst_len-1]),
                .ce(1'b1),
                .shift_out(rdata_ext_fifo_wen)
            );
            // 读数据广义fifo的MEM写使能
            ram_based_shift_regs #(
                .data_width(1),
                .delay_n(sdram_burst_rd_latency),
                .shift_type("ff"),
                .ram_type(),
                .INIT_FILE(),
                .en_output_register_init("true"),
                .output_register_init_v(1'b0),
                .simulation_delay(0)
            )delay_for_rd_burst_transmitting(
                .clk(clk),
                .resetn(rst_n),
                .shift_in((new_burst_start & (~is_write_burst)) | (~rdata_ext_fifo_item_cnt[0])),
                .ce(1'b1),
                .shift_out(rdata_ext_fifo_mem_wen)
            );
        end
        else // burst_len == -1, 全页突发
        begin
            reg[7:0] burst_len_latched; // 锁存的(突发长度 - 1)
            reg rd_burst_transmitting; // 读突发进行中(标志)
            reg[7:0] rdata_ext_fifo_item_cnt; // 读数据广义fifo数据片写计数器
            
            assign rdata_ext_fifo_st_data = rdata_ext_fifo_wen | rdata_ext_fifo_mem_wen;
            assign rdata_cmd_vld_p2 = (new_burst_start & (~is_write_burst)) | rd_burst_transmitting;
            
            // 锁存的(突发长度 - 1)
            always @(posedge clk)
            begin
                if(new_burst_start & (~is_write_burst))
                    burst_len_latched <= new_burst_len;
            end
            
            // 读突发进行中(标志)
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rd_burst_transmitting <= 1'b0;
                else
                    rd_burst_transmitting <= rd_burst_transmitting ? (rdata_ext_fifo_item_cnt != burst_len_latched):(new_burst_start & (~is_write_burst) & (new_burst_len != 8'd0));
            end
            
            // 读数据广义fifo数据片写计数器
            always @(posedge clk)
            begin
                if(new_burst_start & (~is_write_burst))
                    rdata_ext_fifo_item_cnt <= 8'd1; // 读突发开始时就已预存1个数据, 因此数据片写计数器初始时应载入1
                else if(rd_burst_transmitting)
                    rdata_ext_fifo_item_cnt <= rdata_ext_fifo_item_cnt + 8'd1;
            end
            
            // 读数据广义fifo的MEM写地址
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_waddr_regs[clogb2(rw_data_buffer_depth-1):8] <= 0;
                else if(rdata_ext_fifo_wen)
                    rdata_ext_fifo_mem_waddr_regs[clogb2(rw_data_buffer_depth-1):8] <= rdata_ext_fifo_mem_waddr_regs[clogb2(rw_data_buffer_depth-1):8] + 1;
            end
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_waddr_regs[7:0] <= 8'd0;
                else if(rdata_ext_fifo_wen)
                    rdata_ext_fifo_mem_waddr_regs[7:0] <= 8'd0;
                else if(rdata_ext_fifo_mem_wen)
                    rdata_ext_fifo_mem_waddr_regs[7:0] <= rdata_ext_fifo_mem_waddr_regs[7:0] + 8'd1;
            end
            
            // 读数据广义fifo写使能
            ram_based_shift_regs #(
                .data_width(1),
                .delay_n(sdram_burst_rd_latency),
                .shift_type("ff"),
                .ram_type(),
                .INIT_FILE(),
                .en_output_register_init("true"),
                .output_register_init_v(1'b0),
                .simulation_delay(0)
            )delay_for_last_trans_at_burst(
                .clk(clk),
                .resetn(rst_n),
                .shift_in(rd_burst_transmitting ? 
                    (rdata_ext_fifo_item_cnt == burst_len_latched):
                    (new_burst_start & (~is_write_burst) & (new_burst_len == 8'd0))),
                .ce(1'b1),
                .shift_out(rdata_ext_fifo_wen)
            );
            // 读数据广义fifo的MEM写使能
            ram_based_shift_regs #(
                .data_width(1),
                .delay_n(sdram_burst_rd_latency),
                .shift_type("ff"),
                .ram_type(),
                .INIT_FILE(),
                .en_output_register_init("true"),
                .output_register_init_v(1'b0),
                .simulation_delay(0)
            )delay_for_rd_burst_transmitting(
                .clk(clk),
                .resetn(rst_n),
                .shift_in((new_burst_start & (~is_write_burst)) | rd_burst_transmitting),
                .ce(1'b1),
                .shift_out(rdata_ext_fifo_mem_wen)
            );
        end
    endgenerate
    
    // 异常指示
    reg ld_when_wdata_ext_fifo_empty_err_reg; // 在写数据广义fifo空时取数据(异常指示)
    reg st_when_rdata_ext_fifo_full_err_reg; // 在读数据广义fifo满时存数据(异常指示)
    
    assign ld_when_wdata_ext_fifo_empty_err = (en_expt_tip == "true") ? ld_when_wdata_ext_fifo_empty_err_reg:1'b0;
    assign st_when_rdata_ext_fifo_full_err = (en_expt_tip == "true") ? st_when_rdata_ext_fifo_full_err_reg:1'b0;
    
    // 在写数据广义fifo空时取数据(异常指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            ld_when_wdata_ext_fifo_empty_err_reg <= 1'b0;
        else
            ld_when_wdata_ext_fifo_empty_err_reg <= wdata_ext_fifo_ld_data & (~wdata_ext_fifo_empty_n);
    end
    // 在读数据广义fifo满时存数据(异常指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            st_when_rdata_ext_fifo_full_err_reg <= 1'b0;
        else
            st_when_rdata_ext_fifo_full_err_reg <= rdata_ext_fifo_st_data & (~rdata_ext_fifo_full_n);
    end
    
endmodule
