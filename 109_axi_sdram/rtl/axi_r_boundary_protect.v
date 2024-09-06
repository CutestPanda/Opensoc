`timescale 1ns / 1ps
/********************************************************************
本模块: AXI读数据通道的边界保护

描述: 
对AXI从机的R通道进行边界保护
32位地址/数据总线

注意：
仅支持INCR突发类型

以下非寄存器输出 ->
    AXI从机的R通道: m_axis_r_last, m_axis_r_valid
    AXI主机的R通道: m_axi_rready

协议:
AXI MASTER(ONLY R)
AXIS MASTER
FIFO READ

作者: 陈家耀
日期: 2024/05/02
********************************************************************/


module axi_r_boundary_protect #(
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // AXI从机的R
    output wire[31:0] m_axis_r_data,
    output wire[1:0] m_axis_r_user, // {rresp(2bit)}
    output wire m_axis_r_last,
    output wire m_axis_r_valid,
    input wire m_axis_r_ready,
    
    // AXI主机的R
    input wire[31:0] m_axi_rdata,
    input wire m_axi_rlast,
    input wire[1:0] m_axi_rresp,
    input wire m_axi_rvalid,
    output wire m_axi_rready,
    
    // 读跨界标志fifo写端口
    output wire rd_across_boundary_fifo_ren,
    input wire rd_across_boundary_fifo_dout,
    input wire rd_across_boundary_fifo_empty_n
);
    
    reg rd_burst_transmitting; // 读突发传输中
    reg burst_merged; // 读突发已合并
    
    assign m_axis_r_data = m_axi_rdata;
    assign m_axis_r_user = m_axi_rresp;
    assign m_axis_r_last = m_axi_rlast & ((~rd_across_boundary_fifo_dout) | burst_merged);
    // 握手条件: rd_burst_transmitting & m_axi_rvalid & m_axis_r_ready
    assign m_axis_r_valid = rd_burst_transmitting & m_axi_rvalid;
    assign m_axi_rready = rd_burst_transmitting & m_axis_r_ready;
    
    assign rd_across_boundary_fifo_ren = ~rd_burst_transmitting;
    
    // 读突发传输中
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_burst_transmitting <= 1'b0;
        else
            # simulation_delay rd_burst_transmitting <= rd_burst_transmitting ? (~(m_axi_rvalid & m_axis_r_ready & m_axis_r_last)):rd_across_boundary_fifo_empty_n;
    end
    
    // 读突发已合并
    always @(posedge clk)
    begin
        if((~rd_burst_transmitting) & rd_across_boundary_fifo_empty_n)
            # simulation_delay burst_merged <= 1'b0;
        else if(m_axi_rvalid & m_axi_rready & m_axi_rlast)
            # simulation_delay burst_merged <= ~burst_merged;
    end
    
endmodule
