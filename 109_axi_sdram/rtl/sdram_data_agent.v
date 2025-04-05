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
当突发长度为全页时, 写/读数据广义fifo的数据片深度为sdram列数(SDRAM_COL_N), 其他情况时为突发长度

协议:
EXT FIFO READ/WRITE

作者: 陈家耀
日期: 2025/03/01
********************************************************************/


module sdram_data_agent #(
    parameter integer RW_DATA_BUF_DEPTH = 1024, // 读写数据buffer深度(512 | 1024 | 2048 | 4096 | 8192)
    parameter integer BURST_LEN = -1, // 突发长度(-1 -> 全页; 1 | 2 | 4 | 8)
    parameter integer CAS_LATENCY = 2, // sdram读潜伏期时延(2 | 3)
    parameter integer DATA_WIDTH = 32, // 数据位宽(8 | 16 | 32 | 64)
	parameter integer SDRAM_COL_N = 256, // sdram列数(64 | 128 | 256 | 512 | 1024)
    parameter EN_EXPT_TIP = "false", // 是否使能异常指示
    parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 突发信息
	/*
	断言:
		写突发开始时, 写数据广义fifo必定非空;
		读突发开始时, 读数据广义fifo必定非满
	*/
    input wire new_burst_start, // 突发开始指示
    input wire is_write_burst, // 是否写突发
    input wire[15:0] new_burst_len, // 突发长度 - 1
    
    // 写数据广义fifo读端口
    output wire wdata_ext_fifo_ren,
    input wire wdata_ext_fifo_empty_n,
    output wire wdata_ext_fifo_mem_ren,
    output wire[15:0] wdata_ext_fifo_mem_raddr,
    input wire[DATA_WIDTH+DATA_WIDTH/8-1:0] wdata_ext_fifo_mem_dout, // {keep(DATA_WIDTH/8 bit), data(DATA_WIDTH bit)}
    
    // 读数据广义fifo写端口
    output wire rdata_ext_fifo_wen,
    input wire rdata_ext_fifo_full_n,
    output wire rdata_ext_fifo_mem_wen,
    output wire[15:0] rdata_ext_fifo_mem_waddr,
    output wire[DATA_WIDTH:0] rdata_ext_fifo_mem_din, // {last(1bit), data(DATA_WIDTH bit)}
    
    // sdram数据线
    output wire[DATA_WIDTH/8-1:0] sdram_dqm, // 1'b0 -> data write/output enable; 1'b1 -> data mask/output disable
    input wire[DATA_WIDTH-1:0] sdram_dq_i,
    output wire sdram_dq_t, // 三态门方向(1表示输入, 0表示输出)
    output wire[DATA_WIDTH-1:0] sdram_dq_o,
    
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
	// 由于对读数据打了1拍, 因此还要再延迟1clk
    localparam integer SDRAM_BURST_RD_LATENCY = CAS_LATENCY + 2 + 1; // sdram突发读时延
    
    /** sdram数据线 **/
    reg wt_burst_start_d; // 延迟1clk的写突发开始(指示)
    wire wdata_ext_fifo_ren_d2; // 延迟2clk的写数据广义fifo读使能
    reg sdram_dq_t_reg; // sdram数据三态门方向
    reg[DATA_WIDTH-1:0] wdata_ext_fifo_mem_dout_data_d; // 延迟1clk的写数据广义fifo的MEM读数据中的data
    wire wdata_cmd_vld_p2; // 提前2clk的正在写数据(指示)
    wire rdata_cmd_vld_p2; // 提前2clk的正在读数据(指示)
    reg wdata_cmd_vld_p1; // 提前1clk的正在写数据(指示)
    reg rdata_cmd_vld_p1; // 提前1clk的正在读数据(指示)
    reg rdata_cmd_vld; // 正在读数据(指示)
    reg[DATA_WIDTH/8-1:0] sdram_dqm_regs; // sdram字节掩码
    
    assign sdram_dqm = sdram_dqm_regs;
    assign sdram_dq_t = sdram_dq_t_reg;
    assign sdram_dq_o = wdata_ext_fifo_mem_dout_data_d;
    
    // 提前1clk的正在写数据(指示), 提前1clk的正在读数据(指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            {wdata_cmd_vld_p1, rdata_cmd_vld_p1} <= 2'b00;
        else
            {wdata_cmd_vld_p1, rdata_cmd_vld_p1} <= # SIM_DELAY {wdata_cmd_vld_p2, rdata_cmd_vld_p2};
    end
    
    // 正在读数据(指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rdata_cmd_vld <= 1'b0;
        else
            rdata_cmd_vld <= # SIM_DELAY rdata_cmd_vld_p1;
    end
    
    // sdram字节掩码
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            sdram_dqm_regs <= {(DATA_WIDTH/8){1'b1}};
        else
        begin
            // 断言:wdata_cmd_vld_p1和rdata_cmd_vld_p1不可能同时为1
            case({wdata_cmd_vld_p1, (CAS_LATENCY == 2) ? rdata_cmd_vld_p1:rdata_cmd_vld})
                2'b01: sdram_dqm_regs <= # SIM_DELAY {(DATA_WIDTH/8){1'b0}}; // 读数据时DQM都有效, 也就是允许obuffer输出
                2'b10: sdram_dqm_regs <= # SIM_DELAY (~wdata_ext_fifo_mem_dout[DATA_WIDTH+DATA_WIDTH/8-1:DATA_WIDTH]); // 写数据时取keep信号的按位反
                default: sdram_dqm_regs <= # SIM_DELAY {(DATA_WIDTH/8){1'b1}}; // 非读写时DQM都无效
            endcase
        end
    end
    
    // 延迟1clk的写突发开始(指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_burst_start_d <= 1'b0;
        else
            wt_burst_start_d <= # SIM_DELAY new_burst_start & is_write_burst;
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
            sdram_dq_t_reg <= # SIM_DELAY (~wt_burst_start_d);
    end
    
    // 延迟1clk的写数据广义fifo的MEM读数据
    always @(posedge clk)
        wdata_ext_fifo_mem_dout_data_d <= # SIM_DELAY wdata_ext_fifo_mem_dout[DATA_WIDTH-1:0];
    
    // 延迟2clk的写数据广义fifo读使能
    ram_based_shift_regs #(
        .data_width(1),
        .delay_n(2),
        .shift_type("ff"),
        .ram_type(),
        .INIT_FILE(),
        .en_output_register_init("true"),
        .output_register_init_v(1'b0),
        .simulation_delay(SIM_DELAY)
    )delay_for_wdata_ext_fifo_ren(
        .clk(clk),
        .resetn(rst_n),
        .shift_in(wdata_ext_fifo_ren),
        .ce(1'b1),
        .shift_out(wdata_ext_fifo_ren_d2)
    );
    
    /** 写数据广义fifo **/
    reg[clogb2(RW_DATA_BUF_DEPTH-1):0] wdata_ext_fifo_mem_raddr_r; // 写数据广义fifo的MEM读地址
    wire wdata_ext_fifo_ld_data; // 从写数据广义fifo加载数据(指示)
    
    assign wdata_ext_fifo_mem_raddr = 16'h0000 | wdata_ext_fifo_mem_raddr_r;
    
    generate
        if(BURST_LEN == 1)
        begin
            assign wdata_ext_fifo_ren = new_burst_start & is_write_burst;
			assign wdata_ext_fifo_mem_ren = new_burst_start & is_write_burst;
            assign wdata_ext_fifo_ld_data = new_burst_start & is_write_burst;
            assign wdata_cmd_vld_p2 = new_burst_start & is_write_burst;
            
            // 写数据广义fifo的MEM读地址
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_raddr_r <= 0;
                else if(new_burst_start & is_write_burst)
                    wdata_ext_fifo_mem_raddr_r <= # SIM_DELAY wdata_ext_fifo_mem_raddr_r + 1;
            end
        end
        else if((BURST_LEN == 2) | (BURST_LEN == 4) | (BURST_LEN == 8))
        begin
            reg[BURST_LEN-1:0] wdata_ext_fifo_item_cnt; // 写数据广义fifo数据片读计数器
            
            assign wdata_ext_fifo_ren = wdata_ext_fifo_item_cnt[BURST_LEN-1];
			assign wdata_ext_fifo_mem_ren = (new_burst_start & is_write_burst) | (~wdata_ext_fifo_item_cnt[0]);
            assign wdata_ext_fifo_ld_data = (new_burst_start & is_write_burst) | (~wdata_ext_fifo_item_cnt[0]);
            assign wdata_cmd_vld_p2 = (new_burst_start & is_write_burst) | (~wdata_ext_fifo_item_cnt[0]);
            
            // 写数据广义fifo数据片读计数器
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_item_cnt <= {{(BURST_LEN-1){1'b0}}, 1'b1};
                else if((new_burst_start & is_write_burst) | (~wdata_ext_fifo_item_cnt[0]))
                    wdata_ext_fifo_item_cnt <= # SIM_DELAY {wdata_ext_fifo_item_cnt[BURST_LEN-2:0], wdata_ext_fifo_item_cnt[BURST_LEN-1]};
            end
            
            // 写数据广义fifo的MEM读地址
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_raddr_r <= 0;
                else if((new_burst_start & is_write_burst) | (~wdata_ext_fifo_item_cnt[0]))
                    wdata_ext_fifo_mem_raddr_r <= # SIM_DELAY wdata_ext_fifo_mem_raddr_r + 1;
            end
        end
        else // BURST_LEN == -1, 全页突发
        begin
            reg[15:0] burst_len_latched; // 锁存的(突发长度 - 1)
            reg wt_burst_transmitting; // 正在进行写突发(标志)
            reg[15:0] wdata_ext_fifo_item_cnt; // 写数据广义fifo数据片读计数器
            
            assign wdata_ext_fifo_ren = wt_burst_transmitting ? 
                (wdata_ext_fifo_item_cnt == burst_len_latched):
                (new_burst_start & is_write_burst & (new_burst_len == 16'd0));
			assign wdata_ext_fifo_mem_ren = wt_burst_transmitting | (new_burst_start & is_write_burst);
            assign wdata_ext_fifo_ld_data = (new_burst_start & is_write_burst) | wt_burst_transmitting;
            assign wdata_cmd_vld_p2 = (new_burst_start & is_write_burst) | wt_burst_transmitting;
            
            // 锁存的(突发长度 - 1)
            always @(posedge clk)
            begin
                if(new_burst_start & is_write_burst)
                    burst_len_latched <= # SIM_DELAY new_burst_len;
            end
            
            // 正在进行写突发(标志)
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wt_burst_transmitting <= 1'b0;
                else if(
					wt_burst_transmitting ? 
						(wdata_ext_fifo_item_cnt == burst_len_latched):
						(new_burst_start & is_write_burst & (new_burst_len != 16'd0))
				)
                    wt_burst_transmitting <= # SIM_DELAY ~wt_burst_transmitting;
            end
            
            // 写数据广义fifo数据片读计数器
            always @(posedge clk)
            begin
                if(new_burst_start & is_write_burst)
                    wdata_ext_fifo_item_cnt <= # SIM_DELAY 16'd1; // 注意: 写突发开始时就已取出1个数据, 因此数据片读计数器初始时应载入1!
                else if(wt_burst_transmitting)
                    wdata_ext_fifo_item_cnt <= # SIM_DELAY wdata_ext_fifo_item_cnt + 16'd1;
            end
            
            // 写数据广义fifo的MEM读地址
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_raddr_r[clogb2(RW_DATA_BUF_DEPTH-1):clogb2(SDRAM_COL_N-1)+1] <= 0;
                else if(wdata_ext_fifo_ren)
                    wdata_ext_fifo_mem_raddr_r[clogb2(RW_DATA_BUF_DEPTH-1):clogb2(SDRAM_COL_N-1)+1] <= # SIM_DELAY 
						wdata_ext_fifo_mem_raddr_r[clogb2(RW_DATA_BUF_DEPTH-1):clogb2(SDRAM_COL_N-1)+1] + 1;
            end
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_raddr_r[clogb2(SDRAM_COL_N-1):0] <= 0;
                else if(wdata_ext_fifo_ren)
                    wdata_ext_fifo_mem_raddr_r[clogb2(SDRAM_COL_N-1):0] <= # SIM_DELAY 0;
                else if(wt_burst_transmitting | (new_burst_start & is_write_burst))
                    wdata_ext_fifo_mem_raddr_r[clogb2(SDRAM_COL_N-1):0] <= # SIM_DELAY 
						wdata_ext_fifo_mem_raddr_r[clogb2(SDRAM_COL_N-1):0] + 1;
            end
        end
    endgenerate
    
    /** 读数据广义fifo **/
    reg[clogb2(RW_DATA_BUF_DEPTH-1):0] rdata_ext_fifo_mem_waddr_regs; // 读数据广义fifo的MEM写地址
    wire rdata_ext_fifo_st_data; // 向读数据广义fifo存入数据(指示)
	reg[DATA_WIDTH-1:0] sdram_dq_i_d; // 延迟1clk的sdram读数据
    
    assign rdata_ext_fifo_mem_waddr = 16'h0000 | rdata_ext_fifo_mem_waddr_regs;
    assign rdata_ext_fifo_mem_din = {rdata_ext_fifo_wen, sdram_dq_i_d};
	
	// 延迟1clk的sdram读数据
	always @(posedge clk)
	begin
		sdram_dq_i_d <= # SIM_DELAY sdram_dq_i;
	end
    
    generate
        if(BURST_LEN == 1)
        begin
            assign rdata_ext_fifo_wen = rdata_ext_fifo_mem_wen;
            assign rdata_ext_fifo_st_data = rdata_ext_fifo_mem_wen;
            assign rdata_cmd_vld_p2 = new_burst_start & (~is_write_burst);
            
            // 读数据广义fifo的MEM写使能
            ram_based_shift_regs #(
                .data_width(1),
                .delay_n(SDRAM_BURST_RD_LATENCY),
                .shift_type("ff"),
                .ram_type(),
                .INIT_FILE(),
                .en_output_register_init("true"),
                .output_register_init_v(1'b0),
                .simulation_delay(SIM_DELAY)
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
                    rdata_ext_fifo_mem_waddr_regs <= # SIM_DELAY rdata_ext_fifo_mem_waddr_regs + 1;
            end
        end
        else if((BURST_LEN == 2) | (BURST_LEN == 4) | (BURST_LEN == 8))
        begin
            reg[BURST_LEN-1:0] rdata_ext_fifo_item_cnt; // 读数据广义fifo数据片写计数器
            
            assign rdata_ext_fifo_st_data = rdata_ext_fifo_mem_wen;
            assign rdata_cmd_vld_p2 = (new_burst_start & (~is_write_burst)) | (~rdata_ext_fifo_item_cnt[0]);
            
            // 读数据广义fifo数据片写计数器
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_item_cnt <= {{(BURST_LEN-1){1'b0}}, 1'b1};
                else if((new_burst_start & (~is_write_burst)) | (~rdata_ext_fifo_item_cnt[0]))
                    rdata_ext_fifo_item_cnt <= # SIM_DELAY 
						{rdata_ext_fifo_item_cnt[BURST_LEN-2:0], rdata_ext_fifo_item_cnt[BURST_LEN-1]};
            end
            
            // 读数据广义fifo的MEM写地址
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_waddr_regs <= 0;
                else if(rdata_ext_fifo_mem_wen)
                    rdata_ext_fifo_mem_waddr_regs <= # SIM_DELAY rdata_ext_fifo_mem_waddr_regs + 1;
            end
            
            // 读数据广义fifo写使能
            ram_based_shift_regs #(
                .data_width(1),
                .delay_n(SDRAM_BURST_RD_LATENCY),
                .shift_type("ff"),
                .ram_type(),
                .INIT_FILE(),
                .en_output_register_init("true"),
                .output_register_init_v(1'b0),
                .simulation_delay(SIM_DELAY)
            )delay_for_last_trans_at_burst(
                .clk(clk),
                .resetn(rst_n),
                .shift_in(rdata_ext_fifo_item_cnt[BURST_LEN-1]),
                .ce(1'b1),
                .shift_out(rdata_ext_fifo_wen)
            );
            // 读数据广义fifo的MEM写使能
            ram_based_shift_regs #(
                .data_width(1),
                .delay_n(SDRAM_BURST_RD_LATENCY),
                .shift_type("ff"),
                .ram_type(),
                .INIT_FILE(),
                .en_output_register_init("true"),
                .output_register_init_v(1'b0),
                .simulation_delay(SIM_DELAY)
            )delay_for_rd_burst_transmitting(
                .clk(clk),
                .resetn(rst_n),
                .shift_in((new_burst_start & (~is_write_burst)) | (~rdata_ext_fifo_item_cnt[0])),
                .ce(1'b1),
                .shift_out(rdata_ext_fifo_mem_wen)
            );
        end
        else // BURST_LEN == -1, 全页突发
        begin
            reg[15:0] burst_len_latched; // 锁存的(突发长度 - 1)
            reg rd_burst_transmitting; // 读突发进行中(标志)
            reg[15:0] rdata_ext_fifo_item_cnt; // 读数据广义fifo数据片写计数器
            
            assign rdata_ext_fifo_st_data = rdata_ext_fifo_wen | rdata_ext_fifo_mem_wen;
            assign rdata_cmd_vld_p2 = (new_burst_start & (~is_write_burst)) | rd_burst_transmitting;
            
            // 锁存的(突发长度 - 1)
            always @(posedge clk)
            begin
                if(new_burst_start & (~is_write_burst))
                    burst_len_latched <= # SIM_DELAY new_burst_len;
            end
            
            // 读突发进行中(标志)
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rd_burst_transmitting <= 1'b0;
                else if(
					rd_burst_transmitting ? 
						(rdata_ext_fifo_item_cnt == burst_len_latched):
						(new_burst_start & (~is_write_burst) & (new_burst_len != 16'd0))
				)
                    rd_burst_transmitting <= # SIM_DELAY ~rd_burst_transmitting;
            end
            
            // 读数据广义fifo数据片写计数器
            always @(posedge clk)
            begin
                if(new_burst_start & (~is_write_burst))
                    rdata_ext_fifo_item_cnt <= # SIM_DELAY 16'd1; // 注意: 读突发开始时就已预存1个数据, 因此数据片写计数器初始时应载入1!
                else if(rd_burst_transmitting)
                    rdata_ext_fifo_item_cnt <= # SIM_DELAY rdata_ext_fifo_item_cnt + 16'd1;
            end
            
            // 读数据广义fifo的MEM写地址
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_waddr_regs[clogb2(RW_DATA_BUF_DEPTH-1):clogb2(SDRAM_COL_N-1)+1] <= 0;
                else if(rdata_ext_fifo_wen)
                    rdata_ext_fifo_mem_waddr_regs[clogb2(RW_DATA_BUF_DEPTH-1):clogb2(SDRAM_COL_N-1)+1] <= # SIM_DELAY 
						rdata_ext_fifo_mem_waddr_regs[clogb2(RW_DATA_BUF_DEPTH-1):clogb2(SDRAM_COL_N-1)+1] + 1;
            end
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_waddr_regs[clogb2(SDRAM_COL_N-1):0] <= 0;
                else if(rdata_ext_fifo_wen)
                    rdata_ext_fifo_mem_waddr_regs[clogb2(SDRAM_COL_N-1):0] <= # SIM_DELAY 0;
                else if(rdata_ext_fifo_mem_wen)
                    rdata_ext_fifo_mem_waddr_regs[clogb2(SDRAM_COL_N-1):0] <= # SIM_DELAY 
						rdata_ext_fifo_mem_waddr_regs[clogb2(SDRAM_COL_N-1):0] + 1;
            end
            
            // 读数据广义fifo写使能
            ram_based_shift_regs #(
                .data_width(1),
                .delay_n(SDRAM_BURST_RD_LATENCY),
                .shift_type("ff"),
                .ram_type(),
                .INIT_FILE(),
                .en_output_register_init("true"),
                .output_register_init_v(1'b0),
                .simulation_delay(SIM_DELAY)
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
                .delay_n(SDRAM_BURST_RD_LATENCY),
                .shift_type("ff"),
                .ram_type(),
                .INIT_FILE(),
                .en_output_register_init("true"),
                .output_register_init_v(1'b0),
                .simulation_delay(SIM_DELAY)
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
    reg ld_when_wdata_ext_fifo_empty_err_r; // 在写数据广义fifo空时取数据(异常指示)
    reg st_when_rdata_ext_fifo_full_err_r; // 在读数据广义fifo满时存数据(异常指示)
    
    assign ld_when_wdata_ext_fifo_empty_err = (EN_EXPT_TIP == "true") & ld_when_wdata_ext_fifo_empty_err_r;
    assign st_when_rdata_ext_fifo_full_err = (EN_EXPT_TIP == "true") & st_when_rdata_ext_fifo_full_err_r;
    
    // 在写数据广义fifo空时取数据(异常指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            ld_when_wdata_ext_fifo_empty_err_r <= 1'b0;
        else
            ld_when_wdata_ext_fifo_empty_err_r <= # SIM_DELAY wdata_ext_fifo_ld_data & (~wdata_ext_fifo_empty_n);
    end
    // 在读数据广义fifo满时存数据(异常指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            st_when_rdata_ext_fifo_full_err_r <= 1'b0;
        else
            st_when_rdata_ext_fifo_full_err_r <= # SIM_DELAY rdata_ext_fifo_st_data & (~rdata_ext_fifo_full_n);
    end
    
endmodule
