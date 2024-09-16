`timescale 1ns / 1ps
/********************************************************************
本模块: AXI边界保护

描述: 
对AXI从机的AR/AW/W通道进行边界保护
32位地址/数据总线
支持非对齐传输/窄带传输

注意：
仅支持INCR突发类型

以下非寄存器输出 ->
    AXI从机的R通道: m_axis_r_last, m_axis_r_valid
    AXI主机的R通道: m_axi_rready
    AXI从机W通道: s_axis_w_ready
    AXI主机W通道: m_axi_wlast, m_axi_wvalid
    AXI从机B通道: m_axis_b_valid
    AXI主机B通道: m_axi_bready

协议:
AXI MASTER
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2024/05/01
********************************************************************/


module axi_boundary_protect #(
    parameter en_narrow_transfer = "false", // 是否允许窄带传输
    parameter integer boundary_size = 1, // 边界大小(以KB计)(1 | 2 | 4)
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // AXI从机
    // AR
    input wire[53:0] s_axis_ar_data, // {保留(1bit), arsize(3bit), arprot(3bit), arlock(1bit), arlen(8bit), arcache(4bit), arburst(2bit), araddr(32bit)}
    input wire s_axis_ar_valid,
    output wire s_axis_ar_ready,
    // AW
    input wire[53:0] s_axis_aw_data, // {保留(1bit), awsize(3bit), awprot(3bit), awlock(1bit), awlen(8bit), awcache(4bit), awburst(2bit), awaddr(32bit)}
    input wire s_axis_aw_valid,
    output wire s_axis_aw_ready,
    // W
    input wire[31:0] s_axis_w_data,
    input wire[3:0] s_axis_w_keep,
    input wire s_axis_w_last,
    input wire s_axis_w_valid,
    output wire s_axis_w_ready,
    // R
    output wire[31:0] m_axis_r_data,
    output wire[1:0] m_axis_r_user, // {rresp(2bit)}
    output wire m_axis_r_last,
    output wire m_axis_r_valid,
    input wire m_axis_r_ready,
    // B
    output wire[7:0] m_axis_b_data, // {保留(6bit), bresp(2bit)}
    output wire m_axis_b_valid,
    input wire m_axis_b_ready,
    
    // AXI主机
    // AR
    output wire[31:0] m_axi_araddr,
    output wire[1:0] m_axi_arburst,
    output wire[3:0] m_axi_arcache,
    output wire[7:0] m_axi_arlen,
    output wire m_axi_arlock,
    output wire[2:0] m_axi_arprot,
    output wire[2:0] m_axi_arsize,
    output wire m_axi_arvalid,
    input wire m_axi_arready,
    // R
    input wire[31:0] m_axi_rdata,
    input wire m_axi_rlast,
    input wire[1:0] m_axi_rresp,
    input wire m_axi_rvalid,
    output wire m_axi_rready,
    // AW
    output wire[31:0] m_axi_awaddr,
    output wire[1:0] m_axi_awburst,
    output wire[3:0] m_axi_awcache,
    output wire[7:0] m_axi_awlen,
    output wire m_axi_awlock,
    output wire[2:0] m_axi_awprot,
    output wire[2:0] m_axi_awsize,
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    // W
    output wire[31:0] m_axi_wdata,
    output wire[3:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready,
    // B
    input wire[1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready
);
    
    /** AR通道边界保护 **/
    // 读跨界标志fifo写端口
    wire rd_across_boundary_fifo_wen;
    wire rd_across_boundary_fifo_din;
    wire rd_across_boundary_fifo_full_n;
    
    axi_ar_aw_boundary_protect #(
        .en_narrow_transfer(en_narrow_transfer),
        .boundary_size(boundary_size),
        .simulation_delay(simulation_delay)
    )axi_ar_boundary_protect(
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_ax_data(s_axis_ar_data),
        .s_axis_ax_valid(s_axis_ar_valid),
        .s_axis_ax_ready(s_axis_ar_ready),
        .m_axi_axaddr(m_axi_araddr),
        .m_axi_axburst(m_axi_arburst),
        .m_axi_axcache(m_axi_arcache),
        .m_axi_axlen(m_axi_arlen),
        .m_axi_axlock(m_axi_arlock),
        .m_axi_axprot(m_axi_arprot),
        .m_axi_axsize(m_axi_arsize),
        .m_axi_axvalid(m_axi_arvalid),
        .m_axi_axready(m_axi_arready),
        .burst_len_fifo_wen(),
        .burst_len_fifo_din(),
        .burst_len_fifo_almost_full_n(1'b1),
        .across_boundary_fifo_wen(rd_across_boundary_fifo_wen),
        .across_boundary_fifo_din(rd_across_boundary_fifo_din),
        .across_boundary_fifo_full_n(rd_across_boundary_fifo_full_n)
    );
    
    /** R通道边界保护 **/
    // 读跨界标志fifo写端口
    wire rd_across_boundary_fifo_ren;
    wire rd_across_boundary_fifo_dout;
    wire rd_across_boundary_fifo_empty_n;
    
    axi_r_boundary_protect #(
        .simulation_delay(simulation_delay)
    )axi_r_boundary_protect_u(
        .clk(clk),
        .rst_n(rst_n),
        .m_axis_r_data(m_axis_r_data),
        .m_axis_r_user(m_axis_r_user),
        .m_axis_r_last(m_axis_r_last),
        .m_axis_r_valid(m_axis_r_valid),
        .m_axis_r_ready(m_axis_r_ready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .rd_across_boundary_fifo_ren(rd_across_boundary_fifo_ren),
        .rd_across_boundary_fifo_dout(rd_across_boundary_fifo_dout),
        .rd_across_boundary_fifo_empty_n(rd_across_boundary_fifo_empty_n)
    );
    
    /** 读跨界标志fifo **/
    fifo_based_on_regs #(
        .fwft_mode("false"),
        .fifo_depth(4),
        .fifo_data_width(1),
        .almost_full_th(),
        .almost_empty_th(),
        .simulation_delay(simulation_delay)
    )rd_across_boundary_fifo(
        .clk(clk),
        .rst_n(rst_n),
        .fifo_wen(rd_across_boundary_fifo_wen),
        .fifo_din(rd_across_boundary_fifo_din),
        .fifo_full_n(rd_across_boundary_fifo_full_n),
        .fifo_ren(rd_across_boundary_fifo_ren),
        .fifo_dout(rd_across_boundary_fifo_dout),
        .fifo_empty_n(rd_across_boundary_fifo_empty_n)
    );
    
    /** AW通道边界保护 **/
    // 写突发长度fifo写端口
    wire wt_burst_len_fifo_wen;
    wire[7:0] wt_burst_len_fifo_din; // 写突发长度 - 1
    wire wt_burst_len_fifo_almost_full_n;
    // 写跨界标志fifo写端口
    wire wt_across_boundary_fifo_wen;
    wire wt_across_boundary_fifo_din;
    wire wt_across_boundary_fifo_full_n;
    
    axi_ar_aw_boundary_protect #(
        .en_narrow_transfer(en_narrow_transfer),
        .boundary_size(boundary_size),
        .simulation_delay(simulation_delay)
    )axi_aw_boundary_protect(
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_ax_data(s_axis_aw_data),
        .s_axis_ax_valid(s_axis_aw_valid),
        .s_axis_ax_ready(s_axis_aw_ready),
        .m_axi_axaddr(m_axi_awaddr),
        .m_axi_axburst(m_axi_awburst),
        .m_axi_axcache(m_axi_awcache),
        .m_axi_axlen(m_axi_awlen),
        .m_axi_axlock(m_axi_awlock),
        .m_axi_axprot(m_axi_awprot),
        .m_axi_axsize(m_axi_awsize),
        .m_axi_axvalid(m_axi_awvalid),
        .m_axi_axready(m_axi_awready),
        .burst_len_fifo_wen(wt_burst_len_fifo_wen),
        .burst_len_fifo_din(wt_burst_len_fifo_din),
        .burst_len_fifo_almost_full_n(wt_burst_len_fifo_almost_full_n),
        .across_boundary_fifo_wen(wt_across_boundary_fifo_wen),
        .across_boundary_fifo_din(wt_across_boundary_fifo_din),
        .across_boundary_fifo_full_n(wt_across_boundary_fifo_full_n)
    );
    
    /** W通道边界保护 **/
    // 写突发长度fifo读端口
    wire wt_burst_len_fifo_ren;
    wire[7:0] wt_burst_len_fifo_dout; // 突发长度 - 1
    wire wt_burst_len_fifo_empty_n;
    
    axi_w_boundary_protect #(
        .simulation_delay(simulation_delay)
    )axi_w_boundary_protect_u(
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_w_data(s_axis_w_data),
        .s_axis_w_keep(s_axis_w_keep),
        .s_axis_w_last(s_axis_w_last),
        .s_axis_w_valid(s_axis_w_valid),
        .s_axis_w_ready(s_axis_w_ready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .burst_len_fifo_ren(wt_burst_len_fifo_ren),
        .burst_len_fifo_dout(wt_burst_len_fifo_dout),
        .burst_len_fifo_empty_n(wt_burst_len_fifo_empty_n)
    );
    
    /** 写突发长度fifo **/
    fifo_based_on_regs #(
        .fwft_mode("false"),
        .fifo_depth(4),
        .fifo_data_width(8),
        .almost_full_th(2),
        .almost_empty_th(),
        .simulation_delay(simulation_delay)
    )wt_burst_len_fifo(
        .clk(clk),
        .rst_n(rst_n),
        .fifo_wen(wt_burst_len_fifo_wen),
        .fifo_din(wt_burst_len_fifo_din),
        .fifo_almost_full_n(wt_burst_len_fifo_almost_full_n),
        .fifo_ren(wt_burst_len_fifo_ren),
        .fifo_dout(wt_burst_len_fifo_dout),
        .fifo_empty_n(wt_burst_len_fifo_empty_n)
    );
    
    /** B通道边界保护 **/
    // 写跨界标志fifo写端口
    wire wt_across_boundary_fifo_ren;
    wire wt_across_boundary_fifo_dout;
    wire wt_across_boundary_fifo_empty_n;
    
    axi_b_boundary_protect #(
        .simulation_delay(simulation_delay)
    )axi_b_boundary_protect_u(
        .clk(clk),
        .rst_n(rst_n),
        .m_axis_b_data(m_axis_b_data),
        .m_axis_b_valid(m_axis_b_valid),
        .m_axis_b_ready(m_axis_b_ready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .wt_across_boundary_fifo_ren(wt_across_boundary_fifo_ren),
        .wt_across_boundary_fifo_dout(wt_across_boundary_fifo_dout),
        .wt_across_boundary_fifo_empty_n(wt_across_boundary_fifo_empty_n)
    );
    
    /** 写跨界标志fifo **/
    fifo_based_on_regs #(
        .fwft_mode("true"),
        .fifo_depth(4),
        .fifo_data_width(1),
        .almost_full_th(),
        .almost_empty_th(),
        .simulation_delay(simulation_delay)
    )wt_across_boundary_fifo(
        .clk(clk),
        .rst_n(rst_n),
        .fifo_wen(wt_across_boundary_fifo_wen),
        .fifo_din(wt_across_boundary_fifo_din),
        .fifo_full_n(wt_across_boundary_fifo_full_n),
        .fifo_ren(wt_across_boundary_fifo_ren),
        .fifo_dout(wt_across_boundary_fifo_dout),
        .fifo_empty_n(wt_across_boundary_fifo_empty_n)
    );
    
endmodule
