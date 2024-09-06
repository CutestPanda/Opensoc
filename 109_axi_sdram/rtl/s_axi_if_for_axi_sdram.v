`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXI-SDRAM��AXI�ӽӿ�

����: 
32λ��ַ/��������
֧�ַǶ��봫��

ע�⣺
��֧��INCRͻ������
��֧��խ������

���·ǼĴ������ ->
    AXI�ӻ��Ķ�����ͨ��: s_axi_rlast, s_axi_rvalid
    AXI�ӻ���д����ͨ��: s_axi_wready
    AXI�ӻ���д��Ӧͨ��: s_axi_bvalid
    SDRAM�û�����AXIS: m_axis_usr_cmd_data, m_axis_usr_cmd_user, m_axis_usr_cmd_valid
    SDRAMд����AXIS: m_axis_wt_keep(������Ƕ��봫��ʱΪ�ǼĴ������), m_axi_wlast, m_axis_wt_valid

Э��:
AXI SLAVE
AXIS MASTER/SLAVE

����: �¼�ҫ
����: 2024/05/01
********************************************************************/


module s_axi_if_for_axi_sdram #(
    parameter arb_algorithm = "round-robin", // �ٲ��㷨("round-robin" | "fixed-r" | "fixed-w")
    parameter en_unaligned_transfer = "false" // �Ƿ�����Ƕ��봫��
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // AXI�ӻ�
    // AR
    input wire[31:0] s_axi_araddr,
    input wire[7:0] s_axi_arlen,
    input wire[2:0] s_axi_arsize,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    // R
    output wire[31:0] s_axi_rdata,
    output wire s_axi_rlast,
    output wire[1:0] s_axi_rresp, // const -> 2'b00
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    // AW
    input wire[31:0] s_axi_awaddr,
    input wire[7:0] s_axi_awlen,
    input wire[2:0] s_axi_awsize,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
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
    
    // SDRAM�û�����AXIS
    output wire[31:0] m_axis_usr_cmd_data, // {����(5bit), ba(2bit), �е�ַ(11bit), A10-0(11bit), �����(3bit)}
    output wire[8:0] m_axis_usr_cmd_user, // {�Ƿ��Զ����"ֹͣͻ��"����(1bit), ͻ������ - 1(8bit)}
    output wire m_axis_usr_cmd_valid,
    input wire m_axis_usr_cmd_ready,
    
    // SDRAMд����AXIS
    output wire[31:0] m_axis_wt_data,
    output wire[3:0] m_axis_wt_keep,
    output wire m_axis_wt_last,
    output wire m_axis_wt_valid,
    input wire m_axis_wt_ready,
    // SDRAM������AXIS
    input wire[31:0] s_axis_rd_data,
    input wire s_axis_rd_last,
    input wire s_axis_rd_valid,
    output wire s_axis_rd_ready
);
    
    /** 1KB�߽籣�� **/
    // ������1KB�߽籣�����AXI����
    // AR
    wire[31:0] m_axi_araddr;
    wire[7:0] m_axi_arlen;
    wire[2:0] m_axi_arsize;
    wire m_axi_arvalid;
    wire m_axi_arready;
    // R
    wire[31:0] m_axi_rdata;
    wire m_axi_rlast;
    wire[1:0] m_axi_rresp;
    wire m_axi_rvalid;
    wire m_axi_rready;
    // AW
    wire[31:0] m_axi_awaddr;
    wire[7:0] m_axi_awlen;
    wire[2:0] m_axi_awsize;
    wire m_axi_awvalid;
    wire m_axi_awready;
    // W
    wire[31:0] m_axi_wdata;
    wire[3:0] m_axi_wstrb;
    wire m_axi_wlast;
    wire m_axi_wvalid;
    wire m_axi_wready;
    // B
    wire[1:0] m_axi_bresp;
    wire m_axi_bvalid;
    wire m_axi_bready;
    
    axi_boundary_protect #(
        .en_narrow_transfer("false"),
        .boundary_size(1),
        .simulation_delay(0)
    )boundary_protect(
        .clk(clk),
        .rst_n(rst_n),
        
        .s_axis_ar_data({1'bx, s_axi_arsize, 3'bxxx, 1'bx, s_axi_arlen, 4'bxxxx, 2'b01, s_axi_araddr}),
        .s_axis_ar_valid(s_axi_arvalid),
        .s_axis_ar_ready(s_axi_arready),
        .s_axis_aw_data({1'bx, s_axi_awsize, 3'bxxx, 1'bx, s_axi_awlen, 4'bxxxx, 2'b01, s_axi_awaddr}),
        .s_axis_aw_valid(s_axi_awvalid),
        .s_axis_aw_ready(s_axi_awready),
        .s_axis_w_data(s_axi_wdata),
        .s_axis_w_keep(s_axi_wstrb),
        .s_axis_w_last(s_axi_wlast),
        .s_axis_w_valid(s_axi_wvalid),
        .s_axis_w_ready(s_axi_wready),
        .m_axis_r_data(s_axi_rdata),
        .m_axis_r_user(s_axi_rresp),
        .m_axis_r_last(s_axi_rlast),
        .m_axis_r_valid(s_axi_rvalid),
        .m_axis_r_ready(s_axi_rready),
        .m_axis_b_data(s_axi_bresp), // m_axis_b_data��8bit��, ��s_axi_bresp��2bit��
        .m_axis_b_valid(s_axi_bvalid),
        .m_axis_b_ready(s_axi_bready),
        
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arburst(),
        .m_axi_arcache(),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arlock(),
        .m_axi_arprot(),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awburst(),
        .m_axi_awcache(),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awlock(),
        .m_axi_awprot(),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready)
    );
    
    /** ��д�ٲ� **/
    // дͻ���Ƕ����ַ��Ϣfifoд�˿�
    wire wt_burst_unaligned_msg_fifo_wen;
    wire[1:0] wt_burst_unaligned_msg_fifo_din; // д��ַ(awaddr)��2λ
    wire wt_burst_unaligned_msg_fifo_full_n;
    
    axi_sdram_rw_arb #(
        .arb_algorithm(arb_algorithm)
    )axi_sdram_rw_arb_u(
        .clk(clk),
        .rst_n(rst_n),
        
        .s_axi_araddr(m_axi_araddr),
        .s_axi_arlen(m_axi_arlen),
        .s_axi_arsize(m_axi_arsize),
        .s_axi_arvalid(m_axi_arvalid),
        .s_axi_arready(m_axi_arready),
        .s_axi_awaddr(m_axi_awaddr),
        .s_axi_awlen(m_axi_awlen),
        .s_axi_awsize(m_axi_awsize),
        .s_axi_awvalid(m_axi_awvalid),
        .s_axi_awready(m_axi_awready),
        
        .m_axis_usr_cmd_data(m_axis_usr_cmd_data),
        .m_axis_usr_cmd_user(m_axis_usr_cmd_user),
        .m_axis_usr_cmd_valid(m_axis_usr_cmd_valid),
        .m_axis_usr_cmd_ready(m_axis_usr_cmd_ready),
        
        .wt_burst_unaligned_msg_fifo_wen(wt_burst_unaligned_msg_fifo_wen),
        .wt_burst_unaligned_msg_fifo_din(wt_burst_unaligned_msg_fifo_din),
        .wt_burst_unaligned_msg_fifo_full_n(wt_burst_unaligned_msg_fifo_full_n)
    );
    
    /** д���ݺ�д��Ӧ **/
    // дͻ���Ƕ����ַ��Ϣfifo���˿�
    wire wt_burst_unaligned_msg_fifo_ren;
    wire[1:0] wt_burst_unaligned_msg_fifo_dout; // д��ַ(awaddr)��2λ
    wire wt_burst_unaligned_msg_fifo_empty_n;
    
    axi_sdram_w_b_chn axi_sdram_w_b_chn_u(
        .clk(clk),
        .rst_n(rst_n),
        
        .s_axi_wdata(m_axi_wdata),
        .s_axi_wstrb(m_axi_wstrb),
        .s_axi_wlast(m_axi_wlast),
        .s_axi_wvalid(m_axi_wvalid),
        .s_axi_wready(m_axi_wready),
        .s_axi_bresp(m_axi_bresp),
        .s_axi_bvalid(m_axi_bvalid),
        .s_axi_bready(m_axi_bready),
        
        .m_axis_wt_data(m_axis_wt_data),
        .m_axis_wt_keep(m_axis_wt_keep),
        .m_axis_wt_last(m_axis_wt_last),
        .m_axis_wt_valid(m_axis_wt_valid),
        .m_axis_wt_ready(m_axis_wt_ready),
        
        .wt_burst_unaligned_msg_fifo_ren(wt_burst_unaligned_msg_fifo_ren),
        .wt_burst_unaligned_msg_fifo_dout(wt_burst_unaligned_msg_fifo_dout),
        .wt_burst_unaligned_msg_fifo_empty_n(wt_burst_unaligned_msg_fifo_empty_n)
    );
    
    /** дͻ���Ƕ����ַ��Ϣfifo **/
    generate
        if(en_unaligned_transfer == "true")
            fifo_based_on_regs #(
                .fwft_mode("true"),
                .fifo_depth(4),
                .fifo_data_width(2),
                .almost_full_th(),
                .almost_empty_th(),
                .simulation_delay(0)
            )wt_burst_unaligned_msg_fifo(
                .clk(clk),
                .rst_n(rst_n),
                
                .fifo_wen(wt_burst_unaligned_msg_fifo_wen),
                .fifo_din(wt_burst_unaligned_msg_fifo_din),
                .fifo_almost_full_n(wt_burst_unaligned_msg_fifo_full_n),
                
                .fifo_ren(wt_burst_unaligned_msg_fifo_ren),
                .fifo_dout(wt_burst_unaligned_msg_fifo_dout),
                .fifo_empty_n(wt_burst_unaligned_msg_fifo_empty_n)
            );
        else
        begin
            assign wt_burst_unaligned_msg_fifo_full_n = 1'b1;
            assign wt_burst_unaligned_msg_fifo_dout = 2'b00;
            assign wt_burst_unaligned_msg_fifo_empty_n = 1'b1;
        end
    endgenerate
    
    /** ������ **/
    // ��sdram������ֱ��pass��������1KB�߽籣����AXI�����Ķ�����(R)ͨ��
    assign m_axi_rdata = s_axis_rd_data;
    assign m_axi_rlast = s_axis_rd_last;
    assign m_axi_rresp = 2'b00;
    assign m_axi_rvalid = s_axis_rd_valid;
    assign s_axis_rd_ready = m_axi_rready;
    
endmodule
