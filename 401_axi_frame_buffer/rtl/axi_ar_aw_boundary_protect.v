`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXI��ַͨ���ı߽籣��

����: 
��AXI�ӻ���AR/AWͨ�����б߽籣��
32λ��ַ/��������
֧�ַǶ��봫��/խ������

ע�⣺
��֧��INCRͻ������

Э��:
AXI MASTER(ONLY AW/AR)
AXIS SLAVE
FIFO WRITE

����: �¼�ҫ
����: 2024/05/01
********************************************************************/


module axi_ar_aw_boundary_protect #(
    parameter en_narrow_transfer = "false", // �Ƿ�����խ������
    parameter integer boundary_size = 1, // �߽��С(��KB��)(1 | 2 | 4)
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // AXI�ӻ���AR��AW
    input wire[53:0] s_axis_ax_data, // {����(1bit), axsize(3bit), axprot(3bit), axlock(1bit), axlen(8bit), axcache(4bit), axburst(2bit), axaddr(32bit)}
    input wire s_axis_ax_valid,
    output wire s_axis_ax_ready,
    
    // AXI������AR��AW
    output wire[31:0] m_axi_axaddr,
    output wire[1:0] m_axi_axburst,
    output wire[3:0] m_axi_axcache,
    output wire[7:0] m_axi_axlen,
    output wire m_axi_axlock,
    output wire[2:0] m_axi_axprot,
    output wire[2:0] m_axi_axsize,
    output wire m_axi_axvalid,
    input wire m_axi_axready,
    
    // ͻ������fifoд�˿�
    output wire burst_len_fifo_wen,
    output wire[7:0] burst_len_fifo_din, // ͻ������ - 1
    input wire burst_len_fifo_almost_full_n, // full��Чʱfifo����ʣ��2����λ
    
    // ����־fifoд�˿�
    output wire across_boundary_fifo_wen,
    output wire across_boundary_fifo_din, // �Ƿ���
    input wire across_boundary_fifo_full_n
);

    /** ���� **/
    // ״̬����
    localparam STS_WAIT_S_AX_VLD = 2'b00; // ״̬:�ȴ��ӻ���Ч
    localparam STS_M_AX_0 = 2'b01; // ״̬:����������ͻ��0�ĵ�ַ��Ϣ
    localparam STS_M_AX_1 = 2'b10; // ״̬:����������ͻ��1�ĵ�ַ��Ϣ
    localparam STS_S_AX_RDY = 2'b11; // ״̬:�ӻ���ַͨ������

    /** AXI�ӻ���AR��AW **/
    wire[31:0] s_axi_ax_addr;
    wire[1:0] s_axi_ax_burst;
    wire[3:0] s_axi_ax_cache;
    wire[7:0] s_axi_ax_len;
    wire s_axi_ax_lock;
    wire[2:0] s_axi_ax_prot;
    wire[2:0] s_axi_ax_size;
    reg s_axis_ax_ready_reg;
    
    assign s_axis_ax_ready = s_axis_ax_ready_reg;
    
    assign {s_axi_ax_size, s_axi_ax_prot, s_axi_ax_lock, s_axi_ax_len,s_axi_ax_cache, s_axi_ax_burst, s_axi_ax_addr} = s_axis_ax_data[52:0];
    
    /** �߽籣��״̬�� **/
    reg across_boundary_latched; // ������Ƿ��Խ�߽�
    reg[31:0] burst_addr[1:0]; // ����ͻ�����׵�ַ
    reg[7:0] burst_len[1:0]; // ����ͻ���ĳ��� - 1
    reg[1:0] boundary_protect_sts; // ��ǰ״̬
    
    // ��ǰ״̬
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            boundary_protect_sts <= STS_WAIT_S_AX_VLD;
        else
        begin
            # simulation_delay;
            
            case(boundary_protect_sts)
                STS_WAIT_S_AX_VLD: // ״̬:�ȴ��ӻ���Ч
                    if(s_axis_ax_valid & burst_len_fifo_almost_full_n & across_boundary_fifo_full_n)
                        boundary_protect_sts <= STS_M_AX_0; // -> ״̬:����������ͻ��0�ĵ�ַ��Ϣ
                STS_M_AX_0: // ״̬:����������ͻ��0�ĵ�ַ��Ϣ
                    if(m_axi_axready)
                        boundary_protect_sts <= across_boundary_latched ? STS_M_AX_1: // -> ״̬:����������ͻ��1�ĵ�ַ��Ϣ
                            STS_S_AX_RDY; // -> ״̬:�ӻ���ַͨ������
                STS_M_AX_1: // ״̬:����������ͻ��1�ĵ�ַ��Ϣ
                    if(m_axi_axready)
                        boundary_protect_sts <= STS_S_AX_RDY; // -> ״̬:�ӻ���ַͨ������
                STS_S_AX_RDY: // ״̬:�ӻ���ַͨ������
                    boundary_protect_sts <= STS_WAIT_S_AX_VLD;
                default:
                    boundary_protect_sts <= STS_WAIT_S_AX_VLD;
            endcase
        end
    end
    
    // AXI�ӻ�AR��AW��ready�ź�
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            s_axis_ax_ready_reg <= 1'b0;
        else
            # simulation_delay s_axis_ax_ready_reg <= ((boundary_protect_sts == STS_M_AX_0) & (m_axi_axready & (~across_boundary_latched))) | 
                ((boundary_protect_sts == STS_M_AX_1) & m_axi_axready);
    end
    
    /** ����ͻ������ **/
    // ͻ�����ֽ��
    // ��32λ����������˵, ÿ��ͻ����ഫ��1KB, ��˽���1/2/4KB�߽籣��, ����ԭ����1��ͻ������Ϊ2��
    wire across_boundary; // �Ƿ��Խ�߽�
    wire[31:0] burst0_addr; // ͻ��0���׵�ַ
    wire[7:0] burst0_len; // ͻ��0�ĳ��� - 1
    wire[31:0] burst1_addr; // ͻ��1���׵�ַ
    wire[7:0] burst1_len; // ͻ��1�ĳ��� - 1
    
    axi_burst_seperator_for_boundary_protect #(
        .en_narrow_transfer(en_narrow_transfer),
        .boundary_size(boundary_size)
    )burst_seperator(
        .s_axi_ax_addr(s_axi_ax_addr),
        .s_axi_ax_len(s_axi_ax_len),
        .s_axi_ax_size(s_axi_ax_size),
        .across_boundary(across_boundary),
        .burst0_addr(burst0_addr),
        .burst0_len(burst0_len),
        .burst1_addr(burst1_addr),
        .burst1_len(burst1_len)
    );
    
    // ������Ƿ��Խ�߽�
    always @(posedge clk)
    begin
        if((boundary_protect_sts == STS_WAIT_S_AX_VLD) & (s_axis_ax_valid & burst_len_fifo_almost_full_n & across_boundary_fifo_full_n))
            # simulation_delay across_boundary_latched <= across_boundary;
    end
    // ����ͻ�����׵�ַ
    always @(posedge clk)
    begin
        if((boundary_protect_sts == STS_WAIT_S_AX_VLD) & (s_axis_ax_valid & burst_len_fifo_almost_full_n & across_boundary_fifo_full_n))
            # simulation_delay {burst_addr[1], burst_addr[0]} <= {burst1_addr, burst0_addr};
        else if((boundary_protect_sts == STS_M_AX_0) & m_axi_axready)
            # simulation_delay {burst_addr[1], burst_addr[0]} <= {burst_addr[0], burst_addr[1]};
    end
    // ����ͻ���ĳ��� - 1
    always @(posedge clk)
    begin
        if((boundary_protect_sts == STS_WAIT_S_AX_VLD) & (s_axis_ax_valid & burst_len_fifo_almost_full_n & across_boundary_fifo_full_n))
            # simulation_delay {burst_len[1], burst_len[0]} <= {burst1_len, burst0_len};
        else if((boundary_protect_sts == STS_M_AX_0) & m_axi_axready)
            # simulation_delay {burst_len[1], burst_len[0]} <= {burst_len[0], burst_len[1]};
    end
    
    /** AXI������AR��AW **/
    reg m_axi_axvalid_reg;
    
    assign m_axi_axaddr = burst_addr[0];
    assign m_axi_axburst = s_axi_ax_burst;
    assign m_axi_axcache = s_axi_ax_cache;
    assign m_axi_axlen = burst_len[0];
    assign m_axi_axlock = s_axi_ax_lock;
    assign m_axi_axprot = s_axi_ax_prot;
    assign m_axi_axsize = s_axi_ax_size;
    assign m_axi_axvalid = m_axi_axvalid_reg;
    
    // AXI����AR��AW��valid�ź�
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            m_axi_axvalid_reg <= 1'b0;
        else
        begin
            # simulation_delay;
            
            case(boundary_protect_sts)
                STS_WAIT_S_AX_VLD: // ״̬:�ȴ��ӻ���Ч
                    m_axi_axvalid_reg <= s_axis_ax_valid & burst_len_fifo_almost_full_n & across_boundary_fifo_full_n;
                STS_M_AX_0: // ״̬:����������ͻ��0�ĵ�ַ��Ϣ
                    m_axi_axvalid_reg <= m_axi_axready ? across_boundary_latched:1'b1;
                STS_M_AX_1: // ״̬:����������ͻ��1�ĵ�ַ��Ϣ
                    m_axi_axvalid_reg <= ~m_axi_axready;
                STS_S_AX_RDY: // ״̬:�ӻ���ַͨ������
                    m_axi_axvalid_reg <= 1'b0;
                default:
                    m_axi_axvalid_reg <= 1'b0;
            endcase
        end
    end
    
    /** ͻ������fifoд�˿� */
    assign burst_len_fifo_wen = m_axi_axvalid & m_axi_axready;
    assign burst_len_fifo_din = burst_len[0];
    
    /** ����־fifoд�˿� **/
    reg across_boundary_fifo_wen_reg;
    
    assign across_boundary_fifo_wen = across_boundary_fifo_wen_reg;
    assign across_boundary_fifo_din = across_boundary_latched;
    
    // ����־fifoдʹ��
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            across_boundary_fifo_wen_reg <= 1'b0;
        else
            # simulation_delay across_boundary_fifo_wen_reg <= (boundary_protect_sts == STS_WAIT_S_AX_VLD) & 
                (s_axis_ax_valid & burst_len_fifo_almost_full_n & across_boundary_fifo_full_n);
    end
    
endmodule
