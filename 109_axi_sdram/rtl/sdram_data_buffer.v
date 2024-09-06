`timescale 1ns / 1ps
/********************************************************************
本模块: sdram数据缓冲区

描述:
写数据/读数据广义fifo

注意：
写数据/读数据广义fifo的MEM读延迟 = 1clk
当突发长度为全页时, 写/读数据广义fifo的数据片深度为256, 其他情况时为突发长度
在写数据/读数据AXIS中, 用last信号来分隔每次突发

协议:
AXIS MASTER/SLAVE
EXT FIFO READ/WRITE

作者: 陈家耀
日期: 2024/04/14
********************************************************************/


module sdram_data_buffer #(
    parameter integer rw_data_buffer_depth = 1024, // 读写数据buffer深度(512 | 1024 | 2048 | 4096)
    parameter en_imdt_stat_wburst_len = "true", // 是否使能实时统计写突发长度(仅对全页突发有效)
    parameter integer burst_len = -1, // 突发长度(-1 -> 全页; 1 | 2 | 4 | 8)
    parameter integer data_width = 32 // 数据位宽
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 写数据AXIS
    input wire[data_width-1:0] s_axis_wt_data,
    input wire[data_width/8-1:0] s_axis_wt_keep,
    input wire s_axis_wt_last,
    input wire s_axis_wt_valid,
    output wire s_axis_wt_ready,
    // 读数据AXIS
    output wire[data_width-1:0] m_axis_rd_data,
    output wire m_axis_rd_last,
    output wire m_axis_rd_valid,
    input wire m_axis_rd_ready,
    
    // 写数据广义fifo读端口
    input wire wdata_ext_fifo_ren,
    output wire wdata_ext_fifo_empty_n,
    input wire wdata_ext_fifo_mem_ren,
    input wire[clogb2(rw_data_buffer_depth-1):0] wdata_ext_fifo_mem_raddr,
    output wire[data_width+data_width/8-1:0] wdata_ext_fifo_mem_dout, // {keep(data_width/8 bit), data(data_width bit)}
    
    // 读数据广义fifo写端口
    input wire rdata_ext_fifo_wen,
    output wire rdata_ext_fifo_full_n,
    input wire rdata_ext_fifo_mem_wen,
    input wire[clogb2(rw_data_buffer_depth-1):0] rdata_ext_fifo_mem_waddr,
    input wire[data_width:0] rdata_ext_fifo_mem_din, // {last(1bit), data(data_width bit)}
    
    // 实时统计写突发长度fifo读端口
    input wire imdt_stat_wburst_len_fifo_ren,
    output wire[7:0] imdt_stat_wburst_len_fifo_dout
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
    localparam integer ext_fifo_item_n = (burst_len == -1) ? (rw_data_buffer_depth / 256):(rw_data_buffer_depth / burst_len); // 写数据/读数据广义fifo的存储项数
    
    /** 写数据广义fifo **/
    reg[clogb2(ext_fifo_item_n):0] wdata_ext_fifo_item_n; // 写数据广义fifo当前的存储项数
    // 写数据广义fifo读端口
    reg wdata_ext_fifo_empty_n_reg;
    // 写数据广义fifo写端口
    wire wdata_ext_fifo_wen;
    reg wdata_ext_fifo_full_n;
    wire wdata_ext_fifo_mem_wen;
    reg[clogb2(rw_data_buffer_depth-1):0] wdata_ext_fifo_mem_waddr;
    wire[data_width+data_width/8-1:0] wdata_ext_fifo_mem_din;
    
    assign s_axis_wt_ready = wdata_ext_fifo_full_n;
    assign wdata_ext_fifo_empty_n = wdata_ext_fifo_empty_n_reg;
    
    assign wdata_ext_fifo_wen = s_axis_wt_valid & s_axis_wt_ready & s_axis_wt_last;
    assign wdata_ext_fifo_mem_wen = s_axis_wt_valid & s_axis_wt_ready;
    assign wdata_ext_fifo_mem_din = {s_axis_wt_keep, s_axis_wt_data};
    
    // 写数据广义fifo当前的存储项数
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wdata_ext_fifo_item_n <= 0;
        else if((wdata_ext_fifo_wen & wdata_ext_fifo_full_n) ^ (wdata_ext_fifo_ren & wdata_ext_fifo_empty_n))
            wdata_ext_fifo_item_n <= (wdata_ext_fifo_wen & wdata_ext_fifo_full_n) ? (wdata_ext_fifo_item_n + 1):(wdata_ext_fifo_item_n - 1);
    end
    // 写数据广义fifo空标志
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wdata_ext_fifo_empty_n_reg <= 1'b0;
        else if((wdata_ext_fifo_wen & wdata_ext_fifo_full_n) ^ (wdata_ext_fifo_ren & wdata_ext_fifo_empty_n))
            wdata_ext_fifo_empty_n_reg <= (wdata_ext_fifo_wen & wdata_ext_fifo_full_n) | (wdata_ext_fifo_item_n != 1);
    end
    // 写数据广义fifo满标志
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wdata_ext_fifo_full_n <= 1'b1;
        else if((wdata_ext_fifo_wen & wdata_ext_fifo_full_n) ^ (wdata_ext_fifo_ren & wdata_ext_fifo_empty_n))
            wdata_ext_fifo_full_n <= (wdata_ext_fifo_ren & wdata_ext_fifo_empty_n) | (wdata_ext_fifo_item_n != (ext_fifo_item_n - 1));
    end
    
    // 写数据广义fifo的MEM写地址
    generate
        if(burst_len == -1)
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_waddr[clogb2(rw_data_buffer_depth-1):8] <= 0;
                else if(s_axis_wt_valid & s_axis_wt_ready & s_axis_wt_last)
                    wdata_ext_fifo_mem_waddr[clogb2(rw_data_buffer_depth-1):8] <= wdata_ext_fifo_mem_waddr[clogb2(rw_data_buffer_depth-1):8] + 1;
            end
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_waddr[7:0] <= 8'd0;
                else if(s_axis_wt_valid & s_axis_wt_ready)
                    wdata_ext_fifo_mem_waddr[7:0] <= s_axis_wt_last ? 8'd0:(wdata_ext_fifo_mem_waddr[7:0] + 8'd1);
            end
        end
        else
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_waddr <= 0;
                else if(s_axis_wt_valid & s_axis_wt_ready)
                    wdata_ext_fifo_mem_waddr <= wdata_ext_fifo_mem_waddr + 1;
            end
        end
    endgenerate
    
    // MEM
    bram_simple_dual_port #(
        .style("LOW_LATENCY"),
        .mem_width(data_width + data_width / 8),
        .mem_depth(rw_data_buffer_depth),
        .INIT_FILE("no_init"),
        .simulation_delay(0)
    )wdata_ext_fifo_mem(
        .clk(clk),
        .wen_a(wdata_ext_fifo_mem_wen),
        .addr_a(wdata_ext_fifo_mem_waddr),
        .din_a(wdata_ext_fifo_mem_din),
        .ren_b(wdata_ext_fifo_mem_ren),
        .addr_b(wdata_ext_fifo_mem_raddr),
        .dout_b(wdata_ext_fifo_mem_dout)
    );
    
    /** 实时统计写突发长度 **/
    wire imdt_stat_wburst_len_fifo_wen;
    wire[7:0] imdt_stat_wburst_len_fifo_din;
    
    assign imdt_stat_wburst_len_fifo_wen = ((en_imdt_stat_wburst_len == "true") & (burst_len == -1)) & 
        s_axis_wt_valid & s_axis_wt_ready & s_axis_wt_last;
    assign imdt_stat_wburst_len_fifo_din = wdata_ext_fifo_mem_waddr[7:0];
    
    fifo_based_on_regs #(
        .fwft_mode("true"),
        .fifo_depth(2),
        .fifo_data_width(8),
        .almost_full_th(),
        .almost_empty_th(),
        .simulation_delay(0)
    )imdt_stat_wburst_len_fifo(
        .clk(clk),
        .rst_n(rst_n),
        .fifo_wen(imdt_stat_wburst_len_fifo_wen),
        .fifo_din(imdt_stat_wburst_len_fifo_din),
        .fifo_ren(imdt_stat_wburst_len_fifo_ren),
        .fifo_dout(imdt_stat_wburst_len_fifo_dout)
    );
    
    /** 读数据广义fifo **/
    reg[clogb2(ext_fifo_item_n):0] rdata_ext_fifo_item_n; // 读数据广义fifo当前的存储项数
    // 读数据广义fifo读端口
    reg[burst_len-1:0] rdata_rcnt;
    wire rdata_ext_fifo_ren;
    reg rdata_ext_fifo_empty_n;
    wire rdata_ext_fifo_mem_ren;
    reg rdata_ext_fifo_mem_ren_d;
    reg[clogb2(rw_data_buffer_depth-1):0] rdata_ext_fifo_mem_raddr;
    wire[data_width:0] rdata_ext_fifo_mem_dout;
    // 读数据广义fifo写端口
    reg rdata_ext_fifo_full_n_reg;
    // 用于缓冲的寄存器fifo
    wire rdata_show_ahead_buffer_almost_full_n;
    
    assign rdata_ext_fifo_full_n = rdata_ext_fifo_full_n_reg; // 对全页突发来说, 广义fifo满标志从有效到无效存在1clk时延, 但这只是更加保守了, 不影响功能
    
    assign rdata_ext_fifo_ren = (burst_len == 1) ? rdata_ext_fifo_mem_ren:
                                ((burst_len == 2) | (burst_len == 4) | (burst_len == 8)) ? (rdata_ext_fifo_mem_ren & rdata_rcnt[burst_len-1]):
                                                                                           rdata_ext_fifo_mem_ren_d & rdata_ext_fifo_mem_dout[data_width]; // 全页突发
    assign rdata_ext_fifo_mem_ren = rdata_show_ahead_buffer_almost_full_n & rdata_ext_fifo_empty_n & 
        ((burst_len != -1) | (~rdata_ext_fifo_ren)); // 对全页突发来说, 广义fifo空标志从无效到有效存在1clk时延, 因此需要屏蔽广义fifo读使能那1clk的MEM读, 用额外1clk来更新MEM读地址
    
    // 读数据数据片计数器
    generate
        if(burst_len != -1)
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_rcnt <= {{(burst_len-1){1'b0}}, 1'b1};
                else if(rdata_ext_fifo_mem_ren)
                    rdata_rcnt <= {rdata_rcnt[burst_len-2:0], rdata_rcnt[burst_len-1]};
            end
        end
    endgenerate
    
    // 读数据广义fifo当前的存储项数
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rdata_ext_fifo_item_n <= 0;
        else if((rdata_ext_fifo_wen & rdata_ext_fifo_full_n) ^ (rdata_ext_fifo_ren & rdata_ext_fifo_empty_n))
            rdata_ext_fifo_item_n <= (rdata_ext_fifo_wen & rdata_ext_fifo_full_n) ? (rdata_ext_fifo_item_n + 1):(rdata_ext_fifo_item_n - 1);
    end
    // 读数据广义fifo空标志
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rdata_ext_fifo_empty_n <= 1'b0;
        else if((rdata_ext_fifo_wen & rdata_ext_fifo_full_n) ^ (rdata_ext_fifo_ren & rdata_ext_fifo_empty_n))
            rdata_ext_fifo_empty_n <= (rdata_ext_fifo_wen & rdata_ext_fifo_full_n) | (rdata_ext_fifo_item_n != 1);
    end
    // 读数据广义fifo满标志
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rdata_ext_fifo_full_n_reg <= 1'b1;
        else if((rdata_ext_fifo_wen & rdata_ext_fifo_full_n) ^ (rdata_ext_fifo_ren & rdata_ext_fifo_empty_n))
            rdata_ext_fifo_full_n_reg <= (rdata_ext_fifo_ren & rdata_ext_fifo_empty_n) | (rdata_ext_fifo_item_n != (ext_fifo_item_n - 1));
    end
    
    // 延迟1clk的读数据广义fifo的MEM读使能
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rdata_ext_fifo_mem_ren_d <= 1'b0;
        else
            rdata_ext_fifo_mem_ren_d <= rdata_ext_fifo_mem_ren;
    end
    
    // 读数据广义fifo的MEM读地址
    generate
        if(burst_len == -1)
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_raddr[clogb2(rw_data_buffer_depth-1):8] <= 0;
                else if(rdata_ext_fifo_ren)
                    rdata_ext_fifo_mem_raddr[clogb2(rw_data_buffer_depth-1):8] <= rdata_ext_fifo_mem_raddr[clogb2(rw_data_buffer_depth-1):8] + 1;
            end
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_raddr[7:0] <= 8'd0;
                else if(rdata_ext_fifo_ren | rdata_ext_fifo_mem_ren)
                    rdata_ext_fifo_mem_raddr[7:0] <= rdata_ext_fifo_ren ? 8'd0:(rdata_ext_fifo_mem_raddr[7:0] + 8'd1);
            end
        end
        else
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_raddr <= 0;
                else if(rdata_ext_fifo_mem_ren)
                    rdata_ext_fifo_mem_raddr <= rdata_ext_fifo_mem_raddr + 1;
            end
        end
    endgenerate
    
    // MEM
    bram_simple_dual_port #(
        .style("LOW_LATENCY"),
        .mem_width(data_width + 1),
        .mem_depth(rw_data_buffer_depth),
        .INIT_FILE("no_init"),
        .simulation_delay(0)
    )rdata_ext_fifo_mem(
        .clk(clk),
        .wen_a(rdata_ext_fifo_mem_wen),
        .addr_a(rdata_ext_fifo_mem_waddr),
        .din_a(rdata_ext_fifo_mem_din),
        .ren_b(rdata_ext_fifo_mem_ren),
        .addr_b(rdata_ext_fifo_mem_raddr),
        .dout_b(rdata_ext_fifo_mem_dout)
    );
    
    // 用于缓冲的寄存器fifo
    fifo_based_on_regs #(
        .fwft_mode("true"),
        .fifo_depth(4),
        .fifo_data_width(data_width + 1),
        .almost_full_th(3),
        .almost_empty_th(),
        .simulation_delay(0)
    )rdata_show_ahead_buffer(
        .clk(clk),
        .rst_n(rst_n),
        .fifo_wen(rdata_ext_fifo_mem_ren_d),
        .fifo_din(rdata_ext_fifo_mem_dout),
        .fifo_almost_full_n(rdata_show_ahead_buffer_almost_full_n),
        .fifo_ren(m_axis_rd_ready),
        .fifo_dout({m_axis_rd_last, m_axis_rd_data}),
        .fifo_empty_n(m_axis_rd_valid)
    );
    
endmodule
