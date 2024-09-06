`timescale 1ns / 1ps
/********************************************************************
本模块: AXI-SDRAM的读写仲裁

描述: 
对AXI从机的AR/AW通道进行仲裁, 产生sdram读写命令

注意：
无

协议:
AXI SLAVE(ONLY AR/AW)
AXIS MASTER
FIFO WRITE

作者: 陈家耀
日期: 2024/05/01
********************************************************************/


module axi_sdram_rw_arb #(
    parameter arb_algorithm = "round-robin" // 仲裁算法("round-robin" | "fixed-r" | "fixed-w")
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // AXI从机
    // AR
    input wire[31:0] s_axi_araddr,
    input wire[7:0] s_axi_arlen,
    input wire[2:0] s_axi_arsize,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    // AW
    input wire[31:0] s_axi_awaddr,
    input wire[7:0] s_axi_awlen,
    input wire[2:0] s_axi_awsize,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    
    // SDRAM用户命令AXIS
    output wire[31:0] m_axis_usr_cmd_data, // {保留(5bit), ba(2bit), 行地址(11bit), A10-0(11bit), 命令号(3bit)}
    output wire[8:0] m_axis_usr_cmd_user, // {是否自动添加"停止突发"命令(1bit), 突发长度 - 1(8bit)}
    output wire m_axis_usr_cmd_valid,
    input wire m_axis_usr_cmd_ready,
    
    // 写突发非对齐地址信息fifo写端口
    output wire wt_burst_unaligned_msg_fifo_wen,
    output wire[1:0] wt_burst_unaligned_msg_fifo_din, // 写地址(awaddr)低2位
    input wire wt_burst_unaligned_msg_fifo_full_n
);

    /** 常量 **/
    // 命令的逻辑编码
    localparam CMD_LOGI_WT_DATA = 3'b010; // 命令:写数据
    localparam CMD_LOGI_RD_DATA = 3'b011; // 命令:读数据
    
    /** 读写仲裁 **/
    wire rd_req; // 读请求
    wire wt_req; // 写请求
    wire rd_grant; // 读授权
    wire wt_grant; // 写授权
    
    assign rd_req = s_axi_arvalid & m_axis_usr_cmd_ready;
    assign wt_req = s_axi_awvalid & m_axis_usr_cmd_ready & wt_burst_unaligned_msg_fifo_full_n;
    
    assign s_axi_arready = rd_grant;
    assign s_axi_awready = wt_grant;
    
    assign m_axis_usr_cmd_data = rd_grant ? {5'dx, s_axi_araddr[22:10], 3'd0, s_axi_araddr[9:2], CMD_LOGI_RD_DATA}:
        {5'dx, s_axi_awaddr[22:10], 3'd0, s_axi_awaddr[9:2], CMD_LOGI_WT_DATA};
    assign m_axis_usr_cmd_user = rd_grant ? {1'b1, s_axi_arlen}:{1'b1, s_axi_awlen};
    assign m_axis_usr_cmd_valid = s_axi_arvalid | (s_axi_awvalid & wt_burst_unaligned_msg_fifo_full_n);
    
    assign wt_burst_unaligned_msg_fifo_wen = s_axi_awvalid & s_axi_awready;
    assign wt_burst_unaligned_msg_fifo_din = s_axi_awaddr[1:0];
    
    // 仲裁器
    generate
        if(arb_algorithm == "round-robin")
            // Round-Robin仲裁器
            round_robin_arbitrator #(
                .chn_n(2),
                .simulation_delay(0)
            )round_robin_arbitrator_u(
                .clk(clk),
                .rst_n(rst_n),
                .req({wt_req, rd_req}),
                .grant({wt_grant, rd_grant}),
                .sel(),
                .arb_valid()
            );
        else
        begin
            // 固定优先级
            assign {wt_grant, rd_grant} = ({wt_req, rd_req} == 2'b00) ? 2'b00:
                ({wt_req, rd_req} == 2'b01) ? 2'b01:
                ({wt_req, rd_req} == 2'b10) ? 2'b10:
                    ((arb_algorithm == "fixed-r") ? 2'b01:2'b10);
        end
    endgenerate
    
endmodule
