`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXI֡����

����: 
ʵ����֡д��AXIS��AXIдͨ��, ֡��ȡAXIS��AXI��ͨ��֮���ת��
AXI�����ĵ�ַ/����λ��̶�Ϊ32
��ѡ��4KB�߽籣��

ע�⣺
֡��С(img_n * pix_data_width / 8)�����ܱ�4����
AXI����ַ�������(axi_raddr_outstanding)��AXI��ͨ������buffer���(axi_rchn_data_buffer_depth)��ͬ����ARͨ��������

Э��:
AXIS MASTER/SLAVE
AXI MASTER

����: �¼�ҫ
����: 2024/05/08
********************************************************************/


module axi_frame_buffer #(
    parameter en_4KB_boundary_protect = "false", // �Ƿ�����4KB�߽籣��
    parameter en_reg_slice_at_m_axi_ar = "true", // �Ƿ���AXI������ARͨ������Ĵ���Ƭ
    parameter en_reg_slice_at_m_axi_aw = "true", // �Ƿ���AXI������AWͨ������Ĵ���Ƭ
    parameter en_reg_slice_at_m_axi_r = "true", // �Ƿ���AXI������Rͨ������Ĵ���Ƭ
    parameter en_reg_slice_at_m_axi_w = "true", // �Ƿ���AXI������Wͨ������Ĵ���Ƭ
    parameter en_reg_slice_at_m_axi_b = "true", // �Ƿ���AXI������Bͨ������Ĵ���Ƭ
    parameter integer frame_n = 4, // ������֡����(�����ڷ�Χ[3, 16]��)
    parameter integer frame_buffer_baseaddr = 0, // ֡�������׵�ַ(�����ܱ�4����)
    parameter integer img_n = 1920 * 1080, // ͼ���С(�����ظ�����)
    parameter integer pix_data_width = 24, // ����λ��(�����ܱ�8����)
    parameter integer pix_per_clk_for_wt = 1, // ÿclkд�����ظ���
	parameter integer pix_per_clk_for_rd = 1, // ÿclk�������ظ���
    parameter integer axi_raddr_outstanding = 2, // AXI����ַ�������(1 | 2 | 4 | 8 | 16)
    parameter integer axi_rchn_max_burst_len = 64, // AXI��ͨ�����ͻ������(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
    parameter integer axi_waddr_outstanding = 2, // AXIд��ַ�������(1 | 2 | 4 | 8 | 16)
    parameter integer axi_wchn_max_burst_len = 64, // AXIдͨ�����ͻ������(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
    parameter integer axi_wchn_data_buffer_depth = 512, // AXIдͨ������buffer���(0 | 16 | 32 | 64 | ..., ��Ϊ0ʱ��ʾ��ʹ��)
    parameter integer axi_rchn_data_buffer_depth = 512, // AXI��ͨ������buffer���(0 | 16 | 32 | 64 | ..., ��Ϊ0ʱ��ʾ��ʹ��)
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // ֡������ƺ�״̬
    input wire disp_suspend, // ��ͣȡ�µ�һ֡(��־)
    output wire rd_new_frame, // ��ȡ�µ�һ֡(ָʾ)
    
    // ֡д��AXIS
    input wire[pix_data_width*pix_per_clk_for_wt-1:0] s_axis_pix_data,
    input wire s_axis_pix_valid,
    output wire s_axis_pix_ready,
    
    // ֡��ȡAXIS
    output wire[pix_data_width*pix_per_clk_for_rd-1:0] m_axis_pix_data,
    output wire[7:0] m_axis_pix_user, // ��ǰ��֡��
    output wire m_axis_pix_last, // ָʾ��֡���1������
    output wire m_axis_pix_valid,
    input wire m_axis_pix_ready,
    
    // AXI����
    // AR
    output wire[31:0] m_axi_araddr,
    output wire[1:0] m_axi_arburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_arlen,
    output wire[2:0] m_axi_arsize, // const -> 3'b010
    output wire m_axi_arvalid,
    input wire m_axi_arready,
    // R
    input wire[31:0] m_axi_rdata,
    input wire[1:0] m_axi_rresp, // ignored
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output wire m_axi_rready,
    // AW
    output wire[31:0] m_axi_awaddr,
    output wire[1:0] m_axi_awburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_awlen,
    output wire[2:0] m_axi_awsize, // const -> 3'b010
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    // B
    input wire[1:0] m_axi_bresp, // ignored
    input wire m_axi_bvalid,
    output wire m_axi_bready, // const -> 1'b1
    // W
    output wire[31:0] m_axi_wdata,
    output wire[3:0] m_axi_wstrb, // const -> 4'b1111
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready
);

    /** AXI֡����(����) **/
    // AXI����
    // AR
    wire[31:0] m_axi_araddr_w;
    wire[1:0] m_axi_arburst_w;
    wire[7:0] m_axi_arlen_w;
    wire[2:0] m_axi_arsize_w;
    wire m_axi_arvalid_w;
    wire m_axi_arready_w;
    // R
    wire[31:0] m_axi_rdata_w;
    wire[1:0] m_axi_rresp_w;
    wire m_axi_rlast_w;
    wire m_axi_rvalid_w;
    wire m_axi_rready_w;
    // AW
    wire[31:0] m_axi_awaddr_w;
    wire[1:0] m_axi_awburst_w;
    wire[7:0] m_axi_awlen_w;
    wire[2:0] m_axi_awsize_w;
    wire m_axi_awvalid_w;
    wire m_axi_awready_w;
    // B
    wire[1:0] m_axi_bresp_w;
    wire m_axi_bvalid_w;
    wire m_axi_bready_w;
    // W
    wire[31:0] m_axi_wdata_w;
    wire[3:0] m_axi_wstrb_w;
    wire m_axi_wlast_w;
    wire m_axi_wvalid_w;
    wire m_axi_wready_w;
    
    axi_frame_buffer_core #(
        .frame_n(frame_n),
        .frame_buffer_baseaddr(frame_buffer_baseaddr),
        .img_n(img_n),
        .pix_data_width(pix_data_width),
        .pix_per_clk_for_wt(pix_per_clk_for_wt),
		.pix_per_clk_for_rd(pix_per_clk_for_rd),
        .axi_raddr_outstanding(axi_raddr_outstanding),
        .axi_rchn_max_burst_len(axi_rchn_max_burst_len),
        .axi_waddr_outstanding(axi_waddr_outstanding),
        .axi_wchn_max_burst_len(axi_wchn_max_burst_len),
        .axi_wchn_data_buffer_depth(axi_wchn_data_buffer_depth),
        .axi_rchn_data_buffer_depth(axi_rchn_data_buffer_depth),
        .simulation_delay(simulation_delay)
    )axi_frame_buffer_core_u(
        .clk(clk),
        .rst_n(rst_n),
        
        .disp_suspend(disp_suspend),
		.rd_new_frame(rd_new_frame),
        
        .s_axis_pix_data(s_axis_pix_data),
        .s_axis_pix_valid(s_axis_pix_valid),
        .s_axis_pix_ready(s_axis_pix_ready),
		
        .m_axis_pix_data(m_axis_pix_data),
        .m_axis_pix_user(m_axis_pix_user),
        .m_axis_pix_last(m_axis_pix_last),
        .m_axis_pix_valid(m_axis_pix_valid),
        .m_axis_pix_ready(m_axis_pix_ready),
        
        .m_axi_araddr(m_axi_araddr_w),
        .m_axi_arburst(m_axi_arburst_w),
        .m_axi_arlen(m_axi_arlen_w),
        .m_axi_arsize(m_axi_arsize_w),
        .m_axi_arvalid(m_axi_arvalid_w),
        .m_axi_arready(m_axi_arready_w),
        .m_axi_rdata(m_axi_rdata_w),
        .m_axi_rlast(m_axi_rlast_w),
        .m_axi_rresp(m_axi_rresp_w),
        .m_axi_rvalid(m_axi_rvalid_w),
        .m_axi_rready(m_axi_rready_w),
        .m_axi_awaddr(m_axi_awaddr_w),
        .m_axi_awburst(m_axi_awburst_w),
        .m_axi_awlen(m_axi_awlen_w),
        .m_axi_awsize(m_axi_awsize_w),
        .m_axi_awvalid(m_axi_awvalid_w),
        .m_axi_awready(m_axi_awready_w),
        .m_axi_wdata(m_axi_wdata_w),
        .m_axi_wstrb(m_axi_wstrb_w),
        .m_axi_wlast(m_axi_wlast_w),
        .m_axi_wvalid(m_axi_wvalid_w),
        .m_axi_wready(m_axi_wready_w),
        .m_axi_bresp(m_axi_bresp_w),
        .m_axi_bvalid(m_axi_bvalid_w),
        .m_axi_bready(m_axi_bready_w)
    );
    
    /** ��ѡ��4KB�߽籣�� **/
    // AXI����
    // AR
    wire[31:0] m_axi_araddr_w2;
    wire[1:0] m_axi_arburst_w2;
    wire[7:0] m_axi_arlen_w2;
    wire[2:0] m_axi_arsize_w2;
    wire m_axi_arvalid_w2;
    wire m_axi_arready_w2;
    // R
    wire[31:0] m_axi_rdata_w2;
    wire[1:0] m_axi_rresp_w2;
    wire m_axi_rlast_w2;
    wire m_axi_rvalid_w2;
    wire m_axi_rready_w2;
    // AW
    wire[31:0] m_axi_awaddr_w2;
    wire[1:0] m_axi_awburst_w2;
    wire[7:0] m_axi_awlen_w2;
    wire[2:0] m_axi_awsize_w2;
    wire m_axi_awvalid_w2;
    wire m_axi_awready_w2;
    // B
    wire[1:0] m_axi_bresp_w2;
    wire m_axi_bvalid_w2;
    wire m_axi_bready_w2;
    // W
    wire[31:0] m_axi_wdata_w2;
    wire[3:0] m_axi_wstrb_w2;
    wire m_axi_wlast_w2;
    wire m_axi_wvalid_w2;
    wire m_axi_wready_w2;
    
    generate
        if(en_4KB_boundary_protect == "true")
        begin
            axi_boundary_protect #(
                .en_narrow_transfer("false"),
                .boundary_size(4),
                .simulation_delay(simulation_delay)
            )axi_boundary_protect_u(
                .clk(clk),
                .rst_n(rst_n),
                
                .s_axis_ar_data({1'b0, m_axi_arsize_w, 3'd0, 1'b0, m_axi_arlen_w, 4'd0, m_axi_arburst_w, m_axi_araddr_w}),
                .s_axis_ar_valid(m_axi_arvalid_w),
                .s_axis_ar_ready(m_axi_arready_w),
                .s_axis_aw_data({1'b0, m_axi_awsize_w, 3'd0, 1'b0, m_axi_awlen_w, 4'd0, m_axi_awburst_w, m_axi_awaddr_w}),
                .s_axis_aw_valid(m_axi_awvalid_w),
                .s_axis_aw_ready(m_axi_awready_w),
                .s_axis_w_data(m_axi_wdata_w),
                .s_axis_w_keep(m_axi_wstrb_w),
                .s_axis_w_last(m_axi_wlast_w),
                .s_axis_w_valid(m_axi_wvalid_w),
                .s_axis_w_ready(m_axi_wready_w),
                .m_axis_r_data(m_axi_rdata_w),
                .m_axis_r_user(m_axi_rresp_w),
                .m_axis_r_last(m_axi_rlast_w),
                .m_axis_r_valid(m_axi_rvalid_w),
                .m_axis_r_ready(m_axi_rready_w),
                .m_axis_b_data(m_axi_bresp_w), // 8bit�����2bit����λ����
                .m_axis_b_valid(m_axi_bvalid_w),
                .m_axis_b_ready(m_axi_bready_w),
                
                .m_axi_araddr(m_axi_araddr_w2),
                .m_axi_arburst(m_axi_arburst_w2),
                .m_axi_arcache(),
                .m_axi_arlen(m_axi_arlen_w2),
                .m_axi_arlock(),
                .m_axi_arprot(),
                .m_axi_arsize(m_axi_arsize_w2),
                .m_axi_arvalid(m_axi_arvalid_w2),
                .m_axi_arready(m_axi_arready_w2),
                .m_axi_rdata(m_axi_rdata_w2),
                .m_axi_rlast(m_axi_rlast_w2),
                .m_axi_rresp(m_axi_rresp_w2),
                .m_axi_rvalid(m_axi_rvalid_w2),
                .m_axi_rready(m_axi_rready_w2),
                .m_axi_awaddr(m_axi_awaddr_w2),
                .m_axi_awburst(m_axi_awburst_w2),
                .m_axi_awcache(),
                .m_axi_awlen(m_axi_awlen_w2),
                .m_axi_awlock(),
                .m_axi_awprot(),
                .m_axi_awsize(m_axi_awsize_w2),
                .m_axi_awvalid(m_axi_awvalid_w2),
                .m_axi_awready(m_axi_awready_w2),
                .m_axi_wdata(m_axi_wdata_w2),
                .m_axi_wstrb(m_axi_wstrb_w2),
                .m_axi_wlast(m_axi_wlast_w2),
                .m_axi_wvalid(m_axi_wvalid_w2),
                .m_axi_wready(m_axi_wready_w2),
                .m_axi_bresp(m_axi_bresp_w2),
                .m_axi_bvalid(m_axi_bvalid_w2),
                .m_axi_bready(m_axi_bready_w2)
            );
        end
        else
        begin
            assign m_axi_araddr_w2 = m_axi_araddr_w;
            assign m_axi_arburst_w2 = m_axi_arburst_w;
            assign m_axi_arlen_w2 = m_axi_arlen_w;
            assign m_axi_arsize_w2 = m_axi_arsize_w;
            assign m_axi_arvalid_w2 = m_axi_arvalid_w;
            assign m_axi_arready_w = m_axi_arready_w2;
            
            assign m_axi_rdata_w = m_axi_rdata_w2;
            assign m_axi_rresp_w = m_axi_rresp_w2;
            assign m_axi_rlast_w = m_axi_rlast_w2;
            assign m_axi_rvalid_w = m_axi_rvalid_w2;
            assign m_axi_rready_w2 = m_axi_rready_w;
            
            assign m_axi_awaddr_w2 = m_axi_awaddr_w;
            assign m_axi_awburst_w2 = m_axi_awburst_w;
            assign m_axi_awlen_w2 = m_axi_awlen_w;
            assign m_axi_awsize_w2 = m_axi_awsize_w;
            assign m_axi_awvalid_w2 = m_axi_awvalid_w;
            assign m_axi_awready_w = m_axi_awready_w2;
            
            assign m_axi_bresp_w = m_axi_bresp_w2;
            assign m_axi_bvalid_w = m_axi_bvalid_w2;
            assign m_axi_bready_w2 = m_axi_bready_w;
            
            assign m_axi_wdata_w2 = m_axi_wdata_w;
            assign m_axi_wstrb_w2 = m_axi_wstrb_w;
            assign m_axi_wlast_w2 = m_axi_wlast_w;
            assign m_axi_wvalid_w2 = m_axi_wvalid_w;
            assign m_axi_wready_w = m_axi_wready_w2;
        end
    endgenerate
    
    /** ��ѡ��ARͨ���Ĵ���Ƭ **/
    axis_reg_slice #(
        .data_width(32),
        .user_width(2 + 8 + 3),
        .forward_registered(((en_4KB_boundary_protect == "false") && (en_reg_slice_at_m_axi_ar == "true")) ? "true":"false"),
        .back_registered(((en_4KB_boundary_protect == "false") && (en_reg_slice_at_m_axi_ar == "true")) ? "true":"false"),
        .en_ready("true"),
        .simulation_delay(simulation_delay)
    )axis_reg_slice_at_ar(
        .clk(clk),
        .rst_n(rst_n),
        
        .s_axis_data(m_axi_araddr_w2),
        .s_axis_keep(),
        .s_axis_user({m_axi_arburst_w2, m_axi_arlen_w2, m_axi_arsize_w2}),
        .s_axis_last(),
        .s_axis_valid(m_axi_arvalid_w2),
        .s_axis_ready(m_axi_arready_w2),
        
        .m_axis_data(m_axi_araddr),
        .m_axis_keep(),
        .m_axis_user({m_axi_arburst, m_axi_arlen, m_axi_arsize}),
        .m_axis_last(),
        .m_axis_valid(m_axi_arvalid),
        .m_axis_ready(m_axi_arready)
    );
    
    /** ��ѡ��AWͨ���Ĵ���Ƭ **/
    axis_reg_slice #(
        .data_width(32),
        .user_width(2 + 8 + 3),
        .forward_registered(((en_4KB_boundary_protect == "false") && (en_reg_slice_at_m_axi_aw == "true")) ? "true":"false"),
        .back_registered(((en_4KB_boundary_protect == "false") && (en_reg_slice_at_m_axi_aw == "true")) ? "true":"false"),
        .en_ready("true"),
        .simulation_delay(simulation_delay)
    )axis_reg_slice_at_aw(
        .clk(clk),
        .rst_n(rst_n),
        
        .s_axis_data(m_axi_awaddr_w2),
        .s_axis_keep(),
        .s_axis_user({m_axi_awburst_w2, m_axi_awlen_w2, m_axi_awsize_w2}),
        .s_axis_last(),
        .s_axis_valid(m_axi_awvalid_w2),
        .s_axis_ready(m_axi_awready_w2),
        
        .m_axis_data(m_axi_awaddr),
        .m_axis_keep(),
        .m_axis_user({m_axi_awburst, m_axi_awlen, m_axi_awsize}),
        .m_axis_last(),
        .m_axis_valid(m_axi_awvalid),
        .m_axis_ready(m_axi_awready)
    );
    
    /** ��ѡ��Rͨ���Ĵ���Ƭ **/
    axis_reg_slice #(
        .data_width(32),
        .user_width(2),
        .forward_registered(en_reg_slice_at_m_axi_r),
        .back_registered(en_reg_slice_at_m_axi_r),
        .en_ready("true"),
        .simulation_delay(simulation_delay)
    )axis_reg_slice_at_r(
        .clk(clk),
        .rst_n(rst_n),
        
        .s_axis_data(m_axi_rdata),
        .s_axis_keep(),
        .s_axis_user(m_axi_rresp),
        .s_axis_last(m_axi_rlast),
        .s_axis_valid(m_axi_rvalid),
        .s_axis_ready(m_axi_rready),
        
        .m_axis_data(m_axi_rdata_w2),
        .m_axis_keep(),
        .m_axis_user(m_axi_rresp_w2),
        .m_axis_last(m_axi_rlast_w2),
        .m_axis_valid(m_axi_rvalid_w2),
        .m_axis_ready(m_axi_rready_w2)
    );
    
    /** ��ѡ��Wͨ���Ĵ���Ƭ **/
    axis_reg_slice #(
        .data_width(32),
        .user_width(1),
        .forward_registered(((en_4KB_boundary_protect == "true") && (en_reg_slice_at_m_axi_w == "true")) ? "true":"false"),
        .back_registered(((en_4KB_boundary_protect == "true") && (en_reg_slice_at_m_axi_w == "true")) ? "true":"false"),
        .en_ready("true"),
        .simulation_delay(simulation_delay)
    )axis_reg_slice_at_w(
        .clk(clk),
        .rst_n(rst_n),
        
        .s_axis_data(m_axi_wdata_w2),
        .s_axis_keep(m_axi_wstrb_w2),
        .s_axis_user(),
        .s_axis_last(m_axi_wlast_w2),
        .s_axis_valid(m_axi_wvalid_w2),
        .s_axis_ready(m_axi_wready_w2),
        
        .m_axis_data(m_axi_wdata),
        .m_axis_keep(m_axi_wstrb),
        .m_axis_user(),
        .m_axis_last(m_axi_wlast),
        .m_axis_valid(m_axi_wvalid),
        .m_axis_ready(m_axi_wready)
    );
    
    /** ��ѡ��Bͨ���Ĵ���Ƭ **/
    axis_reg_slice #(
        .data_width(8),
        .user_width(1),
        .forward_registered(((en_4KB_boundary_protect == "true") && (en_reg_slice_at_m_axi_b == "true")) ? "true":"false"),
        .back_registered(((en_4KB_boundary_protect == "true") && (en_reg_slice_at_m_axi_b == "true")) ? "true":"false"),
        .en_ready("true"),
        .simulation_delay(simulation_delay)
    )axis_reg_slice_at_b(
        .clk(clk),
        .rst_n(rst_n),
        
        .s_axis_data({6'd0, m_axi_bresp}),
        .s_axis_keep(),
        .s_axis_user(),
        .s_axis_last(),
        .s_axis_valid(m_axi_bvalid),
        .s_axis_ready(m_axi_bready),
        
        .m_axis_data(m_axi_bresp_w2), // 8bit�����2bit����λ����
        .m_axis_keep(),
        .m_axis_user(),
        .m_axis_last(),
        .m_axis_valid(m_axi_bvalid_w2),
        .m_axis_ready(m_axi_bready_w2)
    );
    
endmodule
