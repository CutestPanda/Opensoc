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
本模块: 符合AXI协议的Bram控制器

描述: 
AXI-Bram控制器
可选Bram读延迟为1clk或2clk
可选读缓冲fifo以提高读传输的效率

注意：
Bram位宽固定为32bit
必须先给出读/写地址(AR/AW), 再给出读/写数据(R/W), 不支持地址缓冲(outstanding)
不支持非对齐和窄带传输

协议:
AXI SLAVE
MEM READ/WRITE

作者: 陈家耀
日期: 2023/12/09
********************************************************************/


module axi_bram_ctrler #(
    parameter integer bram_depth = 2048, // Bram深度
    parameter integer bram_read_la = 1, // Bram读延迟(1 | 2)
    parameter en_read_buf_fifo = "true", // 是否使用读缓冲fifo
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // AXI SLAVE
    // 读地址通道
    input wire[31:0] s_axi_araddr, // assumed to be aligned
    // 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
    input wire[1:0] s_axi_arburst,
    input wire[3:0] s_axi_arcache, // ignored
    // 固定传输 -> len <= 16; 回环传输 -> len = 2 | 4 | 8 | 16
    input wire[7:0] s_axi_arlen,
    input wire s_axi_arlock, // ignored
    input wire[2:0] s_axi_arprot, // ignored
    input wire[2:0] s_axi_arsize, // assumed to be 3'b010(4 byte)
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    // 写地址通道
    input wire[31:0] s_axi_awaddr, // assumed to be aligned
    // 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
    input wire[1:0] s_axi_awburst,
    input wire[3:0] s_axi_awcache, // ignored
    // 固定传输 -> len <= 16; 回环传输 -> len = 2 | 4 | 8 | 16
    input wire[7:0] s_axi_awlen,
    input wire s_axi_awlock, // ignored
    input wire[2:0] s_axi_awprot, // ignored
    input wire[2:0] s_axi_awsize, // assumed to be 3'b010(4 byte)
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    // 写响应通道
    output wire[1:0] s_axi_bresp, // const -> 2'b00(OKAY)
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    // 读数据通道
    output wire[31:0] s_axi_rdata,
    output wire s_axi_rlast,
    output wire[1:0] s_axi_rresp, // const -> 2'b00(OKAY)
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    // 写数据通道
    input wire[31:0] s_axi_wdata,
    input wire s_axi_wlast,
    input wire[3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    
    // 存储器接口
    output wire bram_clk,
    output wire bram_rst,
    output wire bram_en,
    output wire[3:0] bram_wen,
    output wire[29:0] bram_addr,
    output wire[31:0] bram_din,
    input wire[31:0] bram_dout,
    
    // AXI-Bram控制器错误向量
    output wire[1:0] axi_bram_ctrler_err // {不支持的非对齐传输, 不支持的窄带传输}
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
    // bram控制器状态常量
    localparam bram_ctrler_status_wait_rw_req = 2'b00; // 等待读写请求
    localparam bram_ctrler_status_reading = 2'b01; // 正在读数据
    localparam bram_ctrler_status_writing = 2'b10; // 正在写数据
    localparam bram_ctrler_status_send_wresp = 2'b11; // 正在发送写响应
    // 回环突发地址区间长度
    localparam wrap_length_8byte = 2'b00; // 8byte区间回环突发
    localparam wrap_length_16byte = 2'b01; // 16byte区间回环突发
    localparam wrap_length_32byte = 2'b10; // 32byte区间回环突发
    localparam wrap_length_64byte = 2'b11; // 64byte区间回环突发
    // 突发类型
    localparam burst_fixed = 2'b00;
    localparam burst_incr = 2'b01;
    localparam burst_wrap = 2'b10;
    localparam burst_reserved = 2'b11;
    
    /** 读缓冲fifo(可选) **/
    wire read_buf_fifo_wen;
    wire[32:0] read_buf_fifo_din;
    wire read_buf_fifo_almost_full_n;
    wire read_buf_fifo_ren;
    wire[32:0] read_buf_fifo_dout;
    wire read_buf_fifo_empty_n;
    
    assign read_buf_fifo_ren = s_axi_rready;
    
    ram_fifo_wrapper #(
        .fwft_mode("true"),
        .ram_type("lutram"),
        .en_bram_reg(),
        .fifo_depth(32),
        .fifo_data_width(33),
        .full_assert_polarity("low"),
        .empty_assert_polarity("low"),
        .almost_full_assert_polarity("low"),
        .almost_empty_assert_polarity("no"),
        .en_data_cnt("false"),
        .almost_full_th(30 - bram_read_la),
        .almost_empty_th(),
        .simulation_delay(simulation_delay)
    )read_buf_fifo(
        .clk(clk),
        .rst_n(rst_n),
        .fifo_wen(read_buf_fifo_wen),
        .fifo_din(read_buf_fifo_din),
        .fifo_almost_full_n(read_buf_fifo_almost_full_n),
        .fifo_ren(read_buf_fifo_ren),
        .fifo_dout(read_buf_fifo_dout),
        .fifo_empty_n(read_buf_fifo_empty_n)
    );
	
	/** AXI读写仲裁 **/
	wire axi_rd_req; // AXI读请求
	wire axi_wt_req; // AXI写请求
	wire axi_rd_grant; // AXI读授权
	wire axi_wt_grant; // AXI写授权
	wire axi_rw_arb_valid; // AXI读写仲裁结果有效
	reg axi_rw_arb_valid_d; // 延迟1clk的AXI读写仲裁结果有效
	
	// 延迟1clk的AXI读写仲裁结果有效
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			axi_rw_arb_valid_d <= 1'b0;
		else
			# simulation_delay axi_rw_arb_valid_d <= axi_rw_arb_valid;
	end
	
	round_robin_arbitrator #(
		.chn_n(2),
		.simulation_delay(simulation_delay)
	)round_robin_arbitrator_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.req({axi_rd_req, axi_wt_req}),
		.grant({axi_rd_grant, axi_wt_grant}),
		.sel(),
		.arb_valid(axi_rw_arb_valid)
	);
    
    /** AXI从机接口 **/
    // 读写流程控制状态机
    reg[1:0] bram_ctrler_status; // bram控制器状态
    reg[1:0] s_axi_aw_ar_ready_reg;
    reg s_axi_bvalid_reg;
    reg s_axi_wready_reg;
    reg now_rw; // 当前正在读写数据(标志)
    
	assign {s_axi_awready, s_axi_arready} = s_axi_aw_ar_ready_reg;
	
	assign s_axi_bresp = 2'b00;
    assign s_axi_bvalid = s_axi_bvalid_reg;
	
    assign s_axi_rdata = (en_read_buf_fifo == "true") ? read_buf_fifo_dout[31:0]:bram_dout;
	assign s_axi_rresp = 2'b00;
	
	assign s_axi_wready = s_axi_wready_reg;
	
    assign read_buf_fifo_din[31:0] = bram_dout;
	
	assign axi_rd_req = s_axi_arvalid & (bram_ctrler_status == bram_ctrler_status_wait_rw_req) & (~axi_rw_arb_valid_d);
	assign axi_wt_req = s_axi_awvalid & (bram_ctrler_status == bram_ctrler_status_wait_rw_req) & (~axi_rw_arb_valid_d);
    
    // bram控制器状态
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
        begin
            bram_ctrler_status <= bram_ctrler_status_wait_rw_req;
            s_axi_aw_ar_ready_reg <= 2'b00;
            s_axi_bvalid_reg <= 1'b0;
            s_axi_wready_reg <= 1'b0;
            now_rw <= 1'b0;
        end
        else
        begin
            # simulation_delay;
            
            case(bram_ctrler_status)
                bram_ctrler_status_wait_rw_req: // 等待读写请求
                begin
					if((s_axi_arvalid & s_axi_arready) | (s_axi_awvalid & s_axi_awready))
						bram_ctrler_status <= (s_axi_arvalid & s_axi_arready) ? 
							bram_ctrler_status_reading:bram_ctrler_status_writing;
                    
                    s_axi_aw_ar_ready_reg <= ((s_axi_arvalid & s_axi_arready) | (s_axi_awvalid & s_axi_awready)) ? 
						2'b00:{axi_wt_grant, axi_rd_grant};
                    s_axi_bvalid_reg <= 1'b0;
                    s_axi_wready_reg <= s_axi_awvalid & s_axi_awready;
                    now_rw <= (s_axi_arvalid & s_axi_arready) | (s_axi_awvalid & s_axi_awready);
                end
                bram_ctrler_status_reading: // 正在读数据
                begin
                    bram_ctrler_status <= (s_axi_rvalid & s_axi_rready & s_axi_rlast) ? bram_ctrler_status_wait_rw_req:bram_ctrler_status_reading;
                    s_axi_aw_ar_ready_reg <= 2'b00;
                    s_axi_bvalid_reg <= 1'b0;
                    s_axi_wready_reg <= 1'b0;
                    now_rw <= ~(s_axi_rvalid & s_axi_rready & s_axi_rlast);
                end
                bram_ctrler_status_writing: // 正在写数据
                begin
                    bram_ctrler_status <= (s_axi_wvalid & s_axi_wlast) ? bram_ctrler_status_send_wresp:bram_ctrler_status_writing;
                    s_axi_aw_ar_ready_reg <= 2'b00;
                    s_axi_bvalid_reg <= s_axi_wvalid & s_axi_wlast;
                    s_axi_wready_reg <= ~(s_axi_wvalid & s_axi_wlast);
                    now_rw <= ~(s_axi_wvalid & s_axi_wlast);
                end
                bram_ctrler_status_send_wresp: // 正在发送写响应
                begin
                    bram_ctrler_status <= s_axi_bready ? bram_ctrler_status_wait_rw_req:bram_ctrler_status_send_wresp;
                    s_axi_aw_ar_ready_reg <= 2'b00;
                    s_axi_bvalid_reg <= ~s_axi_bready;
                    s_axi_wready_reg <= 1'b0;
                    now_rw <= 1'b0;
                end
                default:
                begin
                    bram_ctrler_status <= bram_ctrler_status_wait_rw_req;
                    s_axi_aw_ar_ready_reg <= 2'b00;
                    s_axi_bvalid_reg <= 1'b0;
                    s_axi_wready_reg <= 1'b0;
                    now_rw <= 1'b0;
                end
            endcase
        end
    end
    
    // 锁存读写请求信息
    reg[clogb2(bram_depth - 1):0] aw_ar_addr_latched; // 相对于Bram的起始地址
    reg[1:0] aw_ar_burst_latched; // 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
    reg[7:0] aw_ar_len_latched; // 固定传输 -> len <= 16; 回环传输 -> len = 2 | 4 | 8 | 16
    reg is_read_latched; // 是否读突发
    reg[1:0] wrap_addr_length; // 回环突发地址区间 = 2'b00 -> 8 | 2'b01 -> 16 | 2'b10 -> 32 | 2'b11 -> 64
    
    always @(posedge clk)
    begin
        # simulation_delay;
        
        if((bram_ctrler_status == bram_ctrler_status_wait_rw_req) & ((s_axi_arvalid & s_axi_arready) | (s_axi_awvalid & s_axi_awready))) // 捕获到读写请求
        begin
            if(s_axi_arvalid & s_axi_arready) // 启动读传输
            begin
                aw_ar_addr_latched <= s_axi_araddr[clogb2(bram_depth * 4 - 1):2];
                aw_ar_burst_latched <= s_axi_arburst;
                aw_ar_len_latched <= s_axi_arlen;
                is_read_latched <= 1'b1;
                wrap_addr_length <= {s_axi_arlen[2], s_axi_arlen[3] | ({s_axi_arlen[2], s_axi_arlen[1]} == 2'b01)};
            end
            else // 启动写传输
            begin
                aw_ar_addr_latched <= s_axi_awaddr[clogb2(bram_depth * 4 - 1):2];
                aw_ar_burst_latched <= s_axi_awburst;
                aw_ar_len_latched <= s_axi_awlen;
                is_read_latched <= 1'b0;
                wrap_addr_length <= {s_axi_awlen[2], s_axi_awlen[3] | ({s_axi_awlen[2], s_axi_awlen[1]} == 2'b01)};
            end
        end
    end
    
    // 传输开始脉冲
    reg rw_start_pulse;
    reg rw_start_pulse_d;
    
    always @(posedge clk)
    begin
        # simulation_delay;
        
        rw_start_pulse <= (bram_ctrler_status == bram_ctrler_status_wait_rw_req) & (s_axi_arvalid & s_axi_arready);
        rw_start_pulse_d <= rw_start_pulse;
    end
    
    // 读数据last信号
    // 对齐到MEM读数据
    reg s_axi_rlast_reg;
    reg[7:0] read_transfers_cnt; // 当前已完成读传输(计数器)
    // 对齐到MEM读地址
    reg s_axi_rlast_reg_pre;
    reg[7:0] read_transfers_cnt_pre; // 当前已完成读传输(预计数器)
    
    wire bram_raddr_vld_w; // Bram读地址有效
    reg bram_raddr_vld_d; // 延迟1clk的Bram读地址有效
    
    assign s_axi_rlast = (en_read_buf_fifo == "true") ? read_buf_fifo_dout[32]:s_axi_rlast_reg;
    assign read_buf_fifo_din[32] = s_axi_rlast_reg;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            bram_raddr_vld_d <= 1'b0;
        else
            # simulation_delay bram_raddr_vld_d <= bram_raddr_vld_w;
    end
    
    always @(posedge clk)
    begin
        # simulation_delay;
        
        if((bram_ctrler_status == bram_ctrler_status_wait_rw_req) & (s_axi_arvalid & s_axi_arready)) // 载入和清零
        begin
            s_axi_rlast_reg <= s_axi_arlen == 8'd0;
            read_transfers_cnt <= 8'd1;
        end
        else if((en_read_buf_fifo == "true") ? ((~s_axi_rlast_reg) & read_buf_fifo_wen):(s_axi_rvalid & s_axi_rready)) // 更新
        begin
            s_axi_rlast_reg <= read_transfers_cnt == aw_ar_len_latched;
            read_transfers_cnt <= read_transfers_cnt + 8'd1;
        end
        
        if((bram_ctrler_status == bram_ctrler_status_wait_rw_req) & (s_axi_arvalid & s_axi_arready)) // 载入和清零
        begin
            s_axi_rlast_reg_pre <= s_axi_arlen == 8'd0;
            read_transfers_cnt_pre <= 8'd1;
        end
        else if((~s_axi_rlast_reg_pre) & bram_raddr_vld_w) // 更新
        begin
            s_axi_rlast_reg_pre <= read_transfers_cnt_pre == aw_ar_len_latched;
            read_transfers_cnt_pre <= read_transfers_cnt_pre + 8'd1;
        end
    end
    
    // 读数据valid信号
    reg s_axi_rvalid_reg;
    
    assign s_axi_rvalid = (en_read_buf_fifo == "true") ? read_buf_fifo_empty_n:s_axi_rvalid_reg;
    assign read_buf_fifo_wen = s_axi_rvalid_reg;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            s_axi_rvalid_reg <= 1'b0;
        else
        begin
            # simulation_delay;
            
            if(en_read_buf_fifo == "true")
            begin
                s_axi_rvalid_reg <= now_rw & 
                    ((~s_axi_rlast_reg) | ((bram_read_la == 1) ? rw_start_pulse:rw_start_pulse_d)) &
                    ((bram_read_la == 1) ? bram_raddr_vld_w:bram_raddr_vld_d);
            end
            else
            begin
                if(~s_axi_rvalid_reg)
                    s_axi_rvalid_reg <= now_rw & 
                        ((bram_read_la == 1) ? bram_raddr_vld_w:bram_raddr_vld_d);
                else
                    s_axi_rvalid_reg <= ~s_axi_rready;
            end
        end
    end
    
    /** 存储器接口 **/
    // Bram时钟和复位
    assign bram_clk = clk;
    assign bram_rst = ~rst_n;
    
    // 生成Bram读写地址
    reg[clogb2(bram_depth - 1):0] bram_incr_addr; // INCR突发下的Bram读写地址
    reg[clogb2(bram_depth - 1):0] bram_wrap_addr; // WRAP突发下的Bram读写地址
    reg bram_raddr_vld; // Bram读地址有效
    
    assign bram_addr = ((aw_ar_burst_latched == burst_fixed) | (aw_ar_burst_latched == burst_reserved)) ? 
        aw_ar_addr_latched:((aw_ar_burst_latched == burst_incr) ? bram_incr_addr:bram_wrap_addr);
    assign bram_raddr_vld_w = bram_raddr_vld;
    
    always @(posedge clk)
    begin
        # simulation_delay;
        
        if((bram_ctrler_status == bram_ctrler_status_wait_rw_req) & ((s_axi_arvalid & s_axi_arready) | (s_axi_awvalid & s_axi_awready))) // 载入
        begin
            bram_incr_addr <= (s_axi_arvalid & s_axi_arready) ? s_axi_araddr[clogb2(bram_depth * 4 - 1):2]:s_axi_awaddr[clogb2(bram_depth * 4 - 1):2];
            bram_wrap_addr <= (s_axi_arvalid & s_axi_arready) ? s_axi_araddr[clogb2(bram_depth * 4 - 1):2]:s_axi_awaddr[clogb2(bram_depth * 4 - 1):2];
        end
        else if(now_rw &
            (is_read_latched ? & ((en_read_buf_fifo == "true") ? ((~s_axi_rlast_reg_pre) & read_buf_fifo_almost_full_n):((~s_axi_rlast_reg) & s_axi_rvalid & s_axi_rready))
                :s_axi_wvalid)) // 更新
        begin
            bram_incr_addr <= bram_incr_addr + 1;
            
            case(wrap_addr_length)
                wrap_length_8byte: // 回环突发地址区间8字节
                begin
                    if(bram_wrap_addr[0] == 1'b1)
                        bram_wrap_addr <= {bram_wrap_addr[clogb2(bram_depth - 1):1], 1'b0};
                    else
                        bram_wrap_addr <= bram_wrap_addr + 1;
                end
                wrap_length_16byte: // 回环突发地址区间16字节
                begin
                    if(bram_wrap_addr[1:0] == 2'b11)
                        bram_wrap_addr <= {bram_wrap_addr[clogb2(bram_depth - 1):2], 2'b00};
                    else
                        bram_wrap_addr <= bram_wrap_addr + 1;
                end
                wrap_length_32byte: // 回环突发地址区间32字节
                begin
                    if(bram_wrap_addr[2:0] == 3'b111)
                        bram_wrap_addr <= {bram_wrap_addr[clogb2(bram_depth - 1):3], 3'b000};
                    else
                        bram_wrap_addr <= bram_wrap_addr + 1;
                end
                wrap_length_64byte: // 回环突发地址区间64字节
                begin
                    if(bram_wrap_addr[3:0] == 4'b1111)
                        bram_wrap_addr <= {bram_wrap_addr[clogb2(bram_depth - 1):4], 4'b0000};
                    else
                        bram_wrap_addr <= bram_wrap_addr + 1;
                end
                default:
                    bram_wrap_addr <= {(clogb2(bram_depth - 1)+1){1'bx}};
            endcase
        end
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            bram_raddr_vld <= 1'b0;
        else
        begin
            # simulation_delay;
            
            if((bram_ctrler_status == bram_ctrler_status_wait_rw_req) & (s_axi_arvalid & s_axi_arready))
                bram_raddr_vld <= 1'b1;
            else
                bram_raddr_vld <= now_rw & is_read_latched &
                    ((en_read_buf_fifo == "true") ? ((~s_axi_rlast_reg_pre) & read_buf_fifo_almost_full_n):((~s_axi_rlast_reg) & s_axi_rvalid & s_axi_rready));
        end
    end
    
    // 生成Bram读写使能和写数据
    assign bram_en = bram_raddr_vld | (s_axi_wvalid & s_axi_wready);
    assign bram_wen = (s_axi_wvalid & s_axi_wready) ? s_axi_wstrb:4'b0000;
    assign bram_din = s_axi_wdata;
    
    /** 错误标志 **/
    reg[1:0] axi_bram_ctrler_err_regs; // {不支持的非对齐传输, 不支持的窄带传输}
    
    assign axi_bram_ctrler_err = axi_bram_ctrler_err_regs;
    
	// 不支持的非对齐传输
	always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            axi_bram_ctrler_err_regs[1] <= 1'b0;
        else if((s_axi_arvalid & s_axi_arready) | (s_axi_awvalid & s_axi_awready))
        begin
			# simulation_delay axi_bram_ctrler_err_regs[1] <= (s_axi_arvalid & s_axi_arready) ? 
				(s_axi_araddr[1:0] != 2'b00):(s_axi_awaddr[1:0] != 2'b00);
        end
    end
	// 不支持的窄带传输
	always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            axi_bram_ctrler_err_regs[0] <= 1'b0;
        else if((s_axi_arvalid & s_axi_arready) | (s_axi_awvalid & s_axi_awready))
        begin
			# simulation_delay axi_bram_ctrler_err_regs[0] <= (s_axi_arvalid & s_axi_arready) ? 
				(s_axi_arsize != 3'b010):(s_axi_awsize != 3'b010);
        end
    end

endmodule
