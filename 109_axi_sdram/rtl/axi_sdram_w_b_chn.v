`timescale 1ns / 1ps
/********************************************************************
本模块: AXI-SDRAM的写数据/写响应通道

描述: 
在写数据通道的每次突发的第1个传输上进行对齐处理
在每次写突发后发送写响应

注意：
无

协议:
AXI SLAVE(ONLY W/B)
AXIS MASTER
FIFO READ

作者: 陈家耀
日期: 2024/05/01
********************************************************************/


module axi_sdram_w_b_chn (
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // AXI从机
    // W
    input wire[31:0] s_axi_wdata,
    input wire[3:0] s_axi_wstrb,
    input wire s_axi_wlast,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    // B
    output wire[1:0] s_axi_bresp, // const -> 2'b00
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    
    // SDRAM写数据AXIS
    output wire[31:0] m_axis_wt_data,
    output wire[3:0] m_axis_wt_keep,
    output wire m_axis_wt_last,
    output wire m_axis_wt_valid,
    input wire m_axis_wt_ready,
    
    // 写突发非对齐地址信息fifo读端口
    output wire wt_burst_unaligned_msg_fifo_ren,
    input wire[1:0] wt_burst_unaligned_msg_fifo_dout, // 写地址(awaddr)低2位
    input wire wt_burst_unaligned_msg_fifo_empty_n
);
    
    wire[3:0] wburst_realign_keep_mask; // 写突发重对齐keep掩码
    reg bresp_transmitting; // 当前正在传输写响应
    reg first_trans_in_wt_burst; // 当前写突发的第1次传输
    
    assign wburst_realign_keep_mask = (wt_burst_unaligned_msg_fifo_dout == 2'b00) ? 4'b1111:
                                      (wt_burst_unaligned_msg_fifo_dout == 2'b01) ? 4'b1110:
                                      (wt_burst_unaligned_msg_fifo_dout == 2'b10) ? 4'b1100:
                                                                                    4'b1000;
    
    // 握手条件: s_axi_wvalid & (~bresp_transmitting) & m_axis_wt_ready & wt_burst_unaligned_msg_fifo_empty_n
    assign s_axi_wready = (~bresp_transmitting) & m_axis_wt_ready & wt_burst_unaligned_msg_fifo_empty_n;
    
    assign s_axi_bresp = 2'b00;
    assign s_axi_bvalid = bresp_transmitting;
    
    assign m_axis_wt_data = s_axi_wdata;
    assign m_axis_wt_keep = first_trans_in_wt_burst ? (s_axi_wstrb & wburst_realign_keep_mask):s_axi_wstrb;
    assign m_axis_wt_last = s_axi_wlast;
    assign m_axis_wt_valid = (~bresp_transmitting) & s_axi_wvalid & wt_burst_unaligned_msg_fifo_empty_n;
    
    assign wt_burst_unaligned_msg_fifo_ren = s_axi_bvalid & s_axi_bready;
    
    // 当前正在传输写响应
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            bresp_transmitting <= 1'b0;
        else
            bresp_transmitting <= bresp_transmitting ? (~s_axi_bready):(s_axi_wvalid & s_axi_wready & s_axi_wlast);
    end
    
    // 当前写突发的第1次传输
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            first_trans_in_wt_burst <= 1'b1;
        else
            first_trans_in_wt_burst <= first_trans_in_wt_burst ? (~(s_axi_wvalid & s_axi_wready)):(s_axi_bvalid & s_axi_bready);
    end
    
endmodule
