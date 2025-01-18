`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXI��APB��

����: 
AXI��APB��(AXI-APB����APB������Ψһ�����豸)
��ѡAPB�ӻ�����Ϊ1~16

ע�⣺
ÿ���ӻ��ĵ�ַ���䳤�ȱ��� >= 4096(4KB)

Э��:
AXI-Lite SLAVE
APB MASTER

����: �¼�ҫ
����: 2023/12/10
********************************************************************/


module axi_apb_bridge #(
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
    
    // AXI-Lite SLAVE
    // ����ַͨ��
    input wire[31:0] s_axi_araddr,
    input wire[2:0] s_axi_arprot,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    // д��ַͨ��
    input wire[31:0] s_axi_awaddr,
    input wire[2:0] s_axi_awprot,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    // д��Ӧͨ��
    // 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
    output wire[1:0] s_axi_bresp,
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    // ������ͨ��
    output wire[31:0] s_axi_rdata,
    // 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
    output wire[1:0] s_axi_rresp,
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    // д����ͨ��
    input wire[31:0] s_axi_wdata,
    input wire[3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    
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
    // ��Ӧ����
    localparam RESP_OKAY = 2'b00;
    localparam RESP_EXOKAY = 2'b01;
    localparam RESP_SLVERR = 2'b10;
    localparam RESP_DECERR = 2'b11;
    // APB���ӿ�״̬����
    localparam APB_STATUS_IDLE = 2'b00; // ����
    localparam APB_STATUS_READY = 2'b01; // ����
    localparam APB_STATUS_TRANS = 2'b10; // �ȴ�APB�ӻ���ɴ���
    localparam APB_STATUS_WAIT = 2'b11; // �ȴ�AXI����������

    /** AXI-Lite�ӽӿ� **/
    // ����ַͨ��(AR)
    reg s_axi_arready_reg;
    reg[31:0] s_axi_araddr_latched; // �����axi����ַ
    reg[2:0] s_axi_arprot_latched; // �����axi����������
    reg s_axi_ar_decerr; // axi����ַ�������(��־)
    reg[apb_slave_n-1:0] s_axi_ar_decsel; // axi����ַ����Ƭѡ���
    reg[3:0] s_axi_ar_decmuxsel; // axi����ַ����MUXѡ���ź����
    
    wire[15:0] s_axi_ar_decsel_w;
    wire[3:0] s_axi_ar_decmuxsel_w;
    
    assign s_axi_arready = s_axi_arready_reg;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            s_axi_arready_reg <= 1'b1;
        else
            # simulation_delay s_axi_arready_reg <= s_axi_arready_reg ? (~s_axi_arvalid):(s_axi_rvalid & s_axi_rready);
    end
    
    always @(posedge clk)
    begin
        # simulation_delay;
        
        if(s_axi_arvalid & s_axi_arready) // ����
        begin
            s_axi_araddr_latched <= s_axi_araddr;
            s_axi_arprot_latched <= s_axi_arprot;
        end
    end
    
    always @(posedge clk)
    begin
        # simulation_delay;
        
        if(s_axi_arvalid & s_axi_arready)
        begin
            s_axi_ar_decerr <= s_axi_ar_decsel_w[apb_slave_n-1:0] == {apb_slave_n{1'b0}};
            s_axi_ar_decsel <= s_axi_ar_decsel_w;
            s_axi_ar_decmuxsel <= s_axi_ar_decmuxsel_w;
        end
    end
    
    axi_apb_bridge_dec #(
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
    )axi_ar_dec(
        .addr(s_axi_araddr),
        .m_apb_psel(s_axi_ar_decsel_w),
        .apb_muxsel(s_axi_ar_decmuxsel_w)
    );
    
    // ������ͨ��(R)
    reg[31:0] s_axi_rdata_regs;
    reg[1:0] s_axi_rresp_regs;
    reg s_axi_rvalid_reg;
    
    assign s_axi_rdata = s_axi_rdata_regs;
    assign s_axi_rresp = s_axi_rresp_regs;
    assign s_axi_rvalid = s_axi_rvalid_reg;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            s_axi_rvalid_reg <= 1'b0;
        else
            # simulation_delay s_axi_rvalid_reg <= s_axi_rvalid_reg ? (~s_axi_rready):((m_apb_penable & (~m_apb_pwrite) & m_apb_pready) | ((~s_axi_arready) & s_axi_ar_decerr));
    end
    
    always @(posedge clk)
    begin
        # simulation_delay;
    
        if((m_apb_penable & (~m_apb_pwrite) & m_apb_pready) | ((~s_axi_arready) & s_axi_ar_decerr))
        begin
            s_axi_rdata_regs <= m_apb_prdata;
            
            /*
            if(s_axi_ar_decerr)
                s_axi_rresp_regs <= RESP_DECERR;
            else if(m_apb_pslverr)
                s_axi_rresp_regs <= RESP_SLVERR;
            else
                s_axi_rresp_regs <= RESP_OKAY;
            */
            
            s_axi_rresp_regs <= {s_axi_ar_decerr | m_apb_pslverr, s_axi_ar_decerr};
        end
    end
    
    // д��ַͨ��(AW)
    reg s_axi_awready_reg;
    reg[31:0] s_axi_awaddr_latched; // �����axiд��ַ
    reg[2:0] s_axi_awprot_latched; // �����axiд��������
    reg s_axi_aw_decerr; // axiд��ַ�������(��־)
    reg[apb_slave_n-1:0] s_axi_aw_decsel; // axiд��ַ����Ƭѡ���
    reg[3:0] s_axi_aw_decmuxsel; // axiд��ַ����MUXѡ���ź����
    
    wire[15:0] s_axi_aw_decsel_w;
    wire[3:0] s_axi_aw_decmuxsel_w;
    
    assign s_axi_awready = s_axi_awready_reg;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            s_axi_awready_reg <= 1'b1;
        else
            # simulation_delay s_axi_awready_reg <= s_axi_awready_reg ? (~s_axi_awvalid):(s_axi_bvalid & s_axi_bready);
    end
    
    always @(posedge clk)
    begin
        # simulation_delay;
        
        if(s_axi_awvalid & s_axi_awready) // ����
        begin
            s_axi_awaddr_latched <= s_axi_awaddr;
            s_axi_awprot_latched <= s_axi_awprot;
        end
    end
    
    always @(posedge clk)
    begin
        # simulation_delay;
    
        if(s_axi_awvalid & s_axi_awready) // д��ַ����
        begin
            s_axi_aw_decerr <= s_axi_aw_decsel_w[apb_slave_n-1:0] == {apb_slave_n{1'b0}};
            s_axi_aw_decsel <= s_axi_aw_decsel_w;
            s_axi_aw_decmuxsel <= s_axi_aw_decmuxsel_w;
        end
    end
    
    axi_apb_bridge_dec #(
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
    )axi_aw_dec(
        .addr(s_axi_awaddr),
        .m_apb_psel(s_axi_aw_decsel_w),
        .apb_muxsel(s_axi_aw_decmuxsel_w)
    );
    
    // д����ͨ��(W)
    reg s_axi_wready_reg;
    reg[31:0] s_axi_wdata_latched; // �����axiд����
    reg[3:0] s_axi_wstrb_latched; // �����axiд�ֽ�ѡͨ����
    
    assign s_axi_wready = s_axi_wready_reg;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            s_axi_wready_reg <= 1'b1;
        else
            # simulation_delay s_axi_wready_reg <= s_axi_wready_reg ? (~s_axi_wvalid):(s_axi_bvalid & s_axi_bready);
    end
    
    always @(posedge clk)
    begin
        # simulation_delay;
        
        if(s_axi_wvalid & s_axi_wready) // ����
        begin
            s_axi_wdata_latched <= s_axi_wdata;
            s_axi_wstrb_latched <= s_axi_wstrb;
        end
    end
    
    // д��Ӧͨ��(B)
    reg[1:0] s_axi_bresp_regs;
    reg s_axi_bvalid_reg;
    
    assign s_axi_bresp = s_axi_bresp_regs;
    assign s_axi_bvalid = s_axi_bvalid_reg;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            s_axi_bvalid_reg <= 1'b0;
        else
            # simulation_delay s_axi_bvalid_reg <= s_axi_bvalid_reg ? (~s_axi_bready):
                ((m_apb_penable & m_apb_pwrite & m_apb_pready) | ((~s_axi_awready) & (~s_axi_wready) & s_axi_aw_decerr));
    end
    
    always @(posedge clk)
    begin
        # simulation_delay;
        
        if((m_apb_penable & m_apb_pwrite & m_apb_pready) | ((~s_axi_awready) & (~s_axi_wready) & s_axi_aw_decerr))
        begin
            /*
            if(s_axi_aw_decerr)
                s_axi_bresp_regs <= RESP_DECERR;
            else if(m_apb_pslverr)
                s_axi_bresp_regs <= RESP_SLVERR;
            else
                s_axi_bresp_regs <= RESP_OKAY;
            */
            
            s_axi_bresp_regs <= {s_axi_aw_decerr | m_apb_pslverr, s_axi_aw_decerr};
        end
    end
	
	/** APB��д�ٲ� **/
	wire rd_req; // ������
	wire wt_req; // д����
    wire rd_grant; // ����Ȩ
    wire wt_grant; // д��Ȩ
    wire arb_valid; // �ٲý����Ч
	
	round_robin_arbitrator #(
		.chn_n(2),
		.simulation_delay(simulation_delay)
	)round_robin_arbitrator_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.req({rd_req, wt_req}),
		.grant({rd_grant, wt_grant}),
		.sel(),
		.arb_valid(arb_valid)
	);
    
    /** APB���ӿ� **/
    reg[31:0] m_apb_paddr_regs;
    reg m_apb_penable_reg;
    reg m_apb_pwrite_reg;
    reg[2:0] m_apb_pprot_regs;
    reg[apb_slave_n-1:0] m_apb_psel_regs;
    reg[3:0] m_apb_pstrb_regs;
    reg[31:0] m_apb_pwdata_regs;
    reg[3:0] apb_muxsel_regs;
    
    reg[1:0] m_apb_status; // APB���ӿ�״̬
    
    assign m_apb_paddr = m_apb_paddr_regs;
    assign m_apb_penable = m_apb_penable_reg;
    assign m_apb_pwrite = m_apb_pwrite_reg;
    assign m_apb_pprot = m_apb_pprot_regs;
    assign m_apb_psel = m_apb_psel_regs;
    assign m_apb_pstrb = m_apb_pstrb_regs;
    assign m_apb_pwdata = m_apb_pwdata_regs;
    assign apb_muxsel = apb_muxsel_regs;
	
	assign rd_req = (~s_axi_arready) & (~s_axi_ar_decerr) & (m_apb_status == APB_STATUS_IDLE);
	assign wt_req = (~s_axi_awready) & (~s_axi_wready) & (~s_axi_aw_decerr) & (m_apb_status == APB_STATUS_IDLE);
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
        begin
            m_apb_penable_reg <= 1'b0;
            m_apb_psel_regs <= {apb_slave_n{1'b0}};
            m_apb_status <= APB_STATUS_IDLE;
        end
        else
        begin
            # simulation_delay;
            
            case(m_apb_status)
                APB_STATUS_IDLE: // ����
                begin
                    m_apb_penable_reg <= 1'b0;
                    
                    if(arb_valid)
                    begin
                        m_apb_psel_regs <= rd_grant ? s_axi_ar_decsel:s_axi_aw_decsel;
                        m_apb_status <= APB_STATUS_READY;
                    end
                    else
                    begin
                        m_apb_psel_regs <= {apb_slave_n{1'b0}};
                        m_apb_status <= APB_STATUS_IDLE; // hold
                    end
                end
                APB_STATUS_READY: // ����
                begin
                    m_apb_penable_reg <= 1'b1;
                    m_apb_psel_regs <= m_apb_psel_regs; // hold
                    m_apb_status <= APB_STATUS_TRANS;
                end
                APB_STATUS_TRANS: // �ȴ�APB�ӻ���ɴ���
                begin
                    if(m_apb_pready)
                    begin
                        m_apb_penable_reg <= 1'b0;
                        m_apb_psel_regs <= {apb_slave_n{1'b0}};
                        m_apb_status <= APB_STATUS_WAIT;
                    end
                    else
                    begin
                        m_apb_penable_reg <= 1'b1;
                        m_apb_psel_regs <= m_apb_psel_regs; // hold
                        m_apb_status <= APB_STATUS_TRANS; // hold
                    end
                end
                APB_STATUS_WAIT: // �ȴ�AXI�������
                begin
                    m_apb_penable_reg <= 1'b0;
                    m_apb_psel_regs <= {apb_slave_n{1'b0}};
                    
                    if(~m_apb_pwrite_reg) // ������
                    begin
                        if(s_axi_rvalid & s_axi_rready)
                            m_apb_status <= APB_STATUS_IDLE;
                        else
                            m_apb_status <= APB_STATUS_WAIT; // hold
                    end
                    else
                    begin
                        if(s_axi_bvalid & s_axi_bready)
                            m_apb_status <= APB_STATUS_IDLE;
                        else
                            m_apb_status <= APB_STATUS_WAIT; // hold
                    end
                end
                default:
                begin
                    m_apb_penable_reg <= 1'b0;
                    m_apb_psel_regs <= {apb_slave_n{1'b0}};
                    m_apb_status <= APB_STATUS_IDLE;
                end
            endcase
        end
    end
    
    always @(posedge clk)
    begin
        # simulation_delay;
        
        if(m_apb_status == APB_STATUS_IDLE)
        begin
            if(rd_grant)
            begin
                m_apb_paddr_regs <= s_axi_araddr_latched;
                m_apb_pwrite_reg <= 1'b0;
                m_apb_pprot_regs <= s_axi_arprot_latched;
                apb_muxsel_regs <= s_axi_ar_decmuxsel;
            end
            else if(wt_grant)
            begin
                m_apb_paddr_regs <= s_axi_awaddr_latched;
                m_apb_pwrite_reg <= 1'b1;
                m_apb_pprot_regs <= s_axi_awprot_latched;
                m_apb_pstrb_regs <= s_axi_wstrb_latched;
                m_apb_pwdata_regs <= s_axi_wdata_latched;
                apb_muxsel_regs <= s_axi_aw_decmuxsel;
            end
        end
    end

endmodule
