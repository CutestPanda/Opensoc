`timescale 1ns / 1ps
/********************************************************************
��ģ��: AHB��APB��

����: 
AHB��APB��(AHB-APB����APB������Ψһ�����豸)
��ѡAPB�ӻ�����Ϊ1~16

ע�⣺
ÿ���ӻ��ĵ�ַ���䳤�ȱ��� >= 4096(4KB)

Э��:
AHB-Lite SLAVE
APB MASTER

����: �¼�ҫ
����: 2024/04/20
********************************************************************/


module ahb_apb_bridge #(
    parameter integer apb_slave_n = 5, // APB�ӻ�����(1~16)
    parameter integer apb_s0_baseaddr = 0, // 0�Ŵӻ�����ַ
    parameter integer apb_s0_range = 4096, // 0�Ŵӻ���ַ���䳤��
    parameter integer apb_s1_baseaddr = 4096, // 1�Ŵӻ�����ַ
    parameter integer apb_s1_range = 4096, // 1�Ŵӻ���ַ���䳤��
    parameter integer apb_s2_baseaddr = 8192, // 2�Ŵӻ�����ַ
    parameter integer apb_s2_range = 4096, // 2�Ŵӻ���ַ���䳤��
    parameter integer apb_s3_baseaddr = 12288, // 3�Ŵӻ�����ַ
    parameter integer apb_s3_range = 4096, // 3�Ŵӻ���ַ���䳤��
    parameter integer apb_s4_baseaddr = 16384, // 4�Ŵӻ�����ַ
    parameter integer apb_s4_range = 4096, // 4�Ŵӻ���ַ���䳤��
    parameter integer apb_s5_baseaddr = 20480, // 5�Ŵӻ�����ַ
    parameter integer apb_s5_range = 4096, // 5�Ŵӻ���ַ���䳤��
    parameter integer apb_s6_baseaddr = 24576, // 6�Ŵӻ�����ַ
    parameter integer apb_s6_range = 4096, // 6�Ŵӻ���ַ���䳤��
    parameter integer apb_s7_baseaddr = 28672, // 7�Ŵӻ�����ַ
    parameter integer apb_s7_range = 4096, // 7�Ŵӻ���ַ���䳤��
    parameter integer apb_s8_baseaddr = 32768, // 8�Ŵӻ�����ַ
    parameter integer apb_s8_range = 4096, // 8�Ŵӻ���ַ���䳤��
    parameter integer apb_s9_baseaddr = 36864, // 9�Ŵӻ�����ַ
    parameter integer apb_s9_range = 4096, // 9�Ŵӻ���ַ���䳤��
    parameter integer apb_s10_baseaddr = 40960, // 10�Ŵӻ�����ַ
    parameter integer apb_s10_range = 4096, // 10�Ŵӻ���ַ���䳤��
    parameter integer apb_s11_baseaddr = 45056, // 11�Ŵӻ�����ַ
    parameter integer apb_s11_range = 4096, // 11�Ŵӻ���ַ���䳤��
    parameter integer apb_s12_baseaddr = 49152, // 12�Ŵӻ�����ַ
    parameter integer apb_s12_range = 4096, // 12�Ŵӻ���ַ���䳤��
    parameter integer apb_s13_baseaddr = 53248, // 13�Ŵӻ�����ַ
    parameter integer apb_s13_range = 4096, // 13�Ŵӻ���ַ���䳤��
    parameter integer apb_s14_baseaddr = 57344, // 14�Ŵӻ�����ַ
    parameter integer apb_s14_range = 4096, // 14�Ŵӻ���ַ���䳤��
    parameter integer apb_s15_baseaddr = 61440, // 15�Ŵӻ�����ַ
    parameter integer apb_s15_range = 4096, // 15�Ŵӻ���ַ���䳤��
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // AHB-Lite SLAVE
    input wire[31:0] s_ahb_haddr,
    input wire[2:0] s_ahb_hburst, // ignored(assumed to be 3'b000, i.e. SINGLE)
    input wire[3:0] s_ahb_hprot,
    output wire[31:0] s_ahb_hrdata,
    input wire s_ahb_hready_in,
    output wire s_ahb_hready_out,
    output wire s_ahb_hresp, // 1'b0 -> OKAY; 1'b1 -> ERROR
    input wire[2:0] s_ahb_hsize, // ignored(assumed to be 3'b010, i.e. 32)
    input wire[1:0] s_ahb_htrans, // only 2'b00(IDLE) and 2'b10(NONSEQ) are supported
    input wire[31:0] s_ahb_hwdata,
    input wire[3:0] s_ahb_hwstrb,
    input wire s_ahb_hwrite,
    input wire s_ahb_hsel,
    
    // APB MASTER
    output wire[31:0] m_apb_paddr,
    output wire m_apb_penable,
    output wire m_apb_pwrite,
    output wire[2:0] m_apb_pprot,
    output wire[apb_slave_n-1:0] m_apb_psel,
    output wire[3:0] m_apb_pstrb,
    output wire[31:0] m_apb_pwdata,
    input wire m_apb_pready,
    input wire m_apb_pslverr, // 1'b0 -> OKAY; 1'b1 -> ERROR
    input wire[31:0] m_apb_prdata,
    
    // APB MUXѡ���ź�
    output wire[3:0] apb_muxsel
);

    /** ���� **/
    // AHB��������
    localparam AHB_TRANS_IDLE = 2'b00;
    localparam AHB_TRANS_BUSY = 2'b01;
    localparam AHB_TRANS_NONSEQ = 2'b10;
    localparam AHB_TRANS_SEQ = 2'b11;
    
    /** ��ַ������ **/
    wire[15:0] m_apb_psel_w;
    wire[3:0] apb_muxsel_w;
    
    ahb_apb_bridge_dec #(
        .apb_slave_n(apb_slave_n),
        .apb_s0_baseaddr(apb_s0_baseaddr),
        .apb_s0_range(apb_s0_range),
        .apb_s1_baseaddr(apb_s1_baseaddr),
        .apb_s1_range(apb_s1_range),
        .apb_s2_baseaddr(apb_s2_baseaddr),
        .apb_s2_range(apb_s2_range),
        .apb_s3_baseaddr(apb_s3_baseaddr),
        .apb_s3_range(apb_s3_range),
        .apb_s4_baseaddr(apb_s4_baseaddr),
        .apb_s4_range(apb_s4_range),
        .apb_s5_baseaddr(apb_s5_baseaddr),
        .apb_s5_range(apb_s5_range),
        .apb_s6_baseaddr(apb_s6_baseaddr),
        .apb_s6_range(apb_s6_range),
        .apb_s7_baseaddr(apb_s7_baseaddr),
        .apb_s7_range(apb_s7_range),
        .apb_s8_baseaddr(apb_s8_baseaddr),
        .apb_s8_range(apb_s8_range),
        .apb_s9_baseaddr(apb_s9_baseaddr),
        .apb_s9_range(apb_s9_range),
        .apb_s10_baseaddr(apb_s10_baseaddr),
        .apb_s10_range(apb_s10_range),
        .apb_s11_baseaddr(apb_s11_baseaddr),
        .apb_s11_range(apb_s11_range),
        .apb_s12_baseaddr(apb_s12_baseaddr),
        .apb_s12_range(apb_s12_range),
        .apb_s13_baseaddr(apb_s13_baseaddr),
        .apb_s13_range(apb_s13_range),
        .apb_s14_baseaddr(apb_s14_baseaddr),
        .apb_s14_range(apb_s14_range),
        .apb_s15_baseaddr(apb_s15_baseaddr),
        .apb_s15_range(apb_s15_range)
    )bridge_dec(
        .addr(s_ahb_haddr),
        .m_apb_psel(m_apb_psel_w),
        .apb_muxsel(apb_muxsel_w)
    );
    
    /** AHB�ӽӿ� **/
    reg[3:0] apb_slave_muxsel; // APB�ӻ���������ѡ��
    reg[31:0] ahb_haddr_latched; // �����AHB�����ַ
    reg ahb_hwrite_latched; // �����AHB��д����
    reg[2:0] ahb_hprot_latched; // �����AHB��������
    reg apb_transmitting; // APB���������(��־)
    reg ahb_hready; // APB�������
    reg[31:0] apb_rdata_d; // �ӳ�1clk��APB�����ݷ���
    reg ahb_hresp; // AHB������Ӧ
    
    assign s_ahb_hready_out = ahb_hready;
    assign s_ahb_hrdata = apb_rdata_d;
    assign s_ahb_hresp = ahb_hresp;
    
    assign apb_muxsel = apb_slave_muxsel;
    
    // AHB-APB�������, APB�ӻ���������ѡ��, �����AHB�����ַ, �����AHB��д����, �����AHB��������
    always @(posedge clk)
    begin
        if(s_ahb_hsel & s_ahb_hready_in & (s_ahb_htrans == AHB_TRANS_NONSEQ))
        begin
            apb_slave_muxsel <= # simulation_delay apb_muxsel_w;
            
            ahb_haddr_latched <= # simulation_delay s_ahb_haddr;
            ahb_hwrite_latched <= # simulation_delay s_ahb_hwrite;
            ahb_hprot_latched <= # simulation_delay {~s_ahb_hprot[0], 1'b1, s_ahb_hprot[1]};
        end
    end
    
    // APB�������
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            ahb_hready <= 1'b1;
        else
        begin
            if(ahb_hready)
                ahb_hready <= # simulation_delay ~(s_ahb_hsel & s_ahb_hready_in & (s_ahb_htrans == AHB_TRANS_NONSEQ));
            else
            begin
                ahb_hready <= # simulation_delay ahb_hresp | // ��������ӻ�����
                    (m_apb_penable & m_apb_pready & (~m_apb_pslverr)); // ��������
            end
        end
    end
    
    // �ӳ�1clk��APB�����ݷ���
    always @(posedge clk)
        apb_rdata_d <= # simulation_delay m_apb_prdata;
    
    // AHB������Ӧ
    always @(posedge clk)
    begin
        if(apb_transmitting)
        begin
            if(m_apb_penable & m_apb_pready)
                ahb_hresp <= # simulation_delay m_apb_pslverr;
        end
        else
        begin
            if(s_ahb_hsel & s_ahb_hready_in & (s_ahb_htrans == AHB_TRANS_NONSEQ))
                ahb_hresp <= # simulation_delay m_apb_psel_w[apb_slave_n-1:0] == {apb_slave_n{1'b0}};
        end
    end
    
    /** APB���ӿ� **/
    reg[apb_slave_n-1:0] apb_pselx; // APB�ӻ�ѡ��
    reg apb_valid_trans_start_d; // �ӳ�1clk����ЧAPB���俪ʼ(ָʾ)
    reg apb_penable; // APB����ʹ��
    
    assign m_apb_paddr = ahb_haddr_latched;
    assign m_apb_penable = apb_penable;
    assign m_apb_pwrite = ahb_hwrite_latched;
    assign m_apb_pprot = ahb_hprot_latched;
    assign m_apb_psel = apb_pselx;
    assign m_apb_pstrb = s_ahb_hwstrb;
    assign m_apb_pwdata = s_ahb_hwdata;
    
    // APB���������(��־)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            apb_transmitting <= 1'b0;
        else
            apb_transmitting <= # simulation_delay apb_transmitting ? (~(m_apb_penable & m_apb_pready)):(s_ahb_hsel & s_ahb_hready_in & (s_ahb_htrans == AHB_TRANS_NONSEQ));
    end
    
    // APB�ӻ�ѡ��
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            apb_pselx <= {apb_slave_n{1'b0}};
        else
        begin
            if(apb_transmitting)
            begin
                if(m_apb_penable & m_apb_pready)
                    apb_pselx <= # simulation_delay {apb_slave_n{1'b0}};
            end
            else
            begin
                if(s_ahb_hsel & s_ahb_hready_in & (s_ahb_htrans == AHB_TRANS_NONSEQ))
                    apb_pselx <= # simulation_delay m_apb_psel_w[apb_slave_n-1:0];
            end
        end
    end
    
    // �ӳ�1clk����ЧAPB���俪ʼ(ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            apb_valid_trans_start_d <= 1'b0;
        else
            apb_valid_trans_start_d <= # simulation_delay s_ahb_hsel & s_ahb_hready_in & (s_ahb_htrans == AHB_TRANS_NONSEQ) & 
                (m_apb_psel_w[apb_slave_n-1:0] != {apb_slave_n{1'b0}});
    end
    
    // APB����ʹ��
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            apb_penable <= 1'b0;
        else
            apb_penable <= # simulation_delay apb_penable ? (~m_apb_pready):apb_valid_trans_start_d;
    end
    
endmodule
