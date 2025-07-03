/*
MIT License

Copyright (c) 2024 Panda, 2257691535@qq.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

`timescale 1ns / 1ps
/********************************************************************
本模块: AXI到APB桥

描述: 
AXI到APB桥(AXI-APB桥是APB总线上唯一的主设备)
可选APB从机个数为1~16

注意：
每个从机的地址区间长度必须 >= 4096(4KB)

协议:
AXI-Lite SLAVE
APB MASTER

作者: 陈家耀
日期: 2023/12/10
********************************************************************/


module axi_apb_bridge #(
    parameter integer apb_slave_n = 5, // APB从机个数(1~16)
    parameter integer apb_s0_baseaddr = 0, // 0号从机基地址
    parameter integer apb_s0_range = 4096, // 0号从机地址区间长度
    parameter integer apb_s1_baseaddr = 4096, // 1号从机基地址
    parameter integer apb_s1_range = 4096, // 1号从机地址区间长度
    parameter integer apb_s2_baseaddr = 8192, // 2号从机基地址
    parameter integer apb_s2_range = 4096, // 2号从机地址区间长度
    parameter integer apb_s3_baseaddr = 12288, // 3号从机基地址
    parameter integer apb_s3_range = 4096, // 3号从机地址区间长度
    parameter integer apb_s4_baseaddr = 16384, // 4号从机基地址
    parameter integer apb_s4_range = 4096, // 4号从机地址区间长度
    parameter integer apb_s5_baseaddr = 20480, // 5号从机基地址
    parameter integer apb_s5_range = 4096, // 5号从机地址区间长度
    parameter integer apb_s6_baseaddr = 24576, // 6号从机基地址
    parameter integer apb_s6_range = 4096, // 6号从机地址区间长度
    parameter integer apb_s7_baseaddr = 28672, // 7号从机基地址
    parameter integer apb_s7_range = 4096, // 7号从机地址区间长度
    parameter integer apb_s8_baseaddr = 32768, // 8号从机基地址
    parameter integer apb_s8_range = 4096, // 8号从机地址区间长度
    parameter integer apb_s9_baseaddr = 36864, // 9号从机基地址
    parameter integer apb_s9_range = 4096, // 9号从机地址区间长度
    parameter integer apb_s10_baseaddr = 40960, // 10号从机基地址
    parameter integer apb_s10_range = 4096, // 10号从机地址区间长度
    parameter integer apb_s11_baseaddr = 45056, // 11号从机基地址
    parameter integer apb_s11_range = 4096, // 11号从机地址区间长度
    parameter integer apb_s12_baseaddr = 49152, // 12号从机基地址
    parameter integer apb_s12_range = 4096, // 12号从机地址区间长度
    parameter integer apb_s13_baseaddr = 53248, // 13号从机基地址
    parameter integer apb_s13_range = 4096, // 13号从机地址区间长度
    parameter integer apb_s14_baseaddr = 57344, // 14号从机基地址
    parameter integer apb_s14_range = 4096, // 14号从机地址区间长度
    parameter integer apb_s15_baseaddr = 61440, // 15号从机基地址
    parameter integer apb_s15_range = 4096, // 15号从机地址区间长度
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // AXI-Lite SLAVE
    // 读地址通道
    input wire[31:0] s_axi_araddr,
    input wire[2:0] s_axi_arprot,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    // 写地址通道
    input wire[31:0] s_axi_awaddr,
    input wire[2:0] s_axi_awprot,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    // 写响应通道
    // 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
    output wire[1:0] s_axi_bresp,
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    // 读数据通道
    output wire[31:0] s_axi_rdata,
    // 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
    output wire[1:0] s_axi_rresp,
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    // 写数据通道
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
    
    // APB MUX选择信号
    output wire[3:0] apb_muxsel
);

    /** 常量 **/
    // 响应类型
    localparam RESP_OKAY = 2'b00;
    localparam RESP_EXOKAY = 2'b01;
    localparam RESP_SLVERR = 2'b10;
    localparam RESP_DECERR = 2'b11;
    // APB主接口状态常量
    localparam APB_STATUS_IDLE = 2'b00; // 空闲
    localparam APB_STATUS_READY = 2'b01; // 就绪
    localparam APB_STATUS_TRANS = 2'b10; // 等待APB从机完成传输
    localparam APB_STATUS_WAIT = 2'b11; // 等待AXI主机完成完成

    /** AXI-Lite从接口 **/
    // 读地址通道(AR)
    reg s_axi_arready_reg;
    reg[31:0] s_axi_araddr_latched; // 锁存的axi读地址
    reg[2:0] s_axi_arprot_latched; // 锁存的axi读保护类型
    reg s_axi_ar_decerr; // axi读地址译码错误(标志)
    reg[apb_slave_n-1:0] s_axi_ar_decsel; // axi读地址译码片选输出
    reg[3:0] s_axi_ar_decmuxsel; // axi读地址译码MUX选择信号输出
    
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
        
        if(s_axi_arvalid & s_axi_arready) // 锁存
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
    
    // 读数据通道(R)
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
    
    // 写地址通道(AW)
    reg s_axi_awready_reg;
    reg[31:0] s_axi_awaddr_latched; // 锁存的axi写地址
    reg[2:0] s_axi_awprot_latched; // 锁存的axi写保护类型
    reg s_axi_aw_decerr; // axi写地址译码错误(标志)
    reg[apb_slave_n-1:0] s_axi_aw_decsel; // axi写地址译码片选输出
    reg[3:0] s_axi_aw_decmuxsel; // axi写地址译码MUX选择信号输出
    
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
        
        if(s_axi_awvalid & s_axi_awready) // 锁存
        begin
            s_axi_awaddr_latched <= s_axi_awaddr;
            s_axi_awprot_latched <= s_axi_awprot;
        end
    end
    
    always @(posedge clk)
    begin
        # simulation_delay;
    
        if(s_axi_awvalid & s_axi_awready) // 写地址译码
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
    
    // 写数据通道(W)
    reg s_axi_wready_reg;
    reg[31:0] s_axi_wdata_latched; // 锁存的axi写数据
    reg[3:0] s_axi_wstrb_latched; // 锁存的axi写字节选通类型
    
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
        
        if(s_axi_wvalid & s_axi_wready) // 锁存
        begin
            s_axi_wdata_latched <= s_axi_wdata;
            s_axi_wstrb_latched <= s_axi_wstrb;
        end
    end
    
    // 写响应通道(B)
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
	
	/** APB读写仲裁 **/
	wire rd_req; // 读请求
	wire wt_req; // 写请求
    wire rd_grant; // 读授权
    wire wt_grant; // 写授权
    wire arb_valid; // 仲裁结果有效
	
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
    
    /** APB主接口 **/
    reg[31:0] m_apb_paddr_regs;
    reg m_apb_penable_reg;
    reg m_apb_pwrite_reg;
    reg[2:0] m_apb_pprot_regs;
    reg[apb_slave_n-1:0] m_apb_psel_regs;
    reg[3:0] m_apb_pstrb_regs;
    reg[31:0] m_apb_pwdata_regs;
    reg[3:0] apb_muxsel_regs;
    
    reg[1:0] m_apb_status; // APB主接口状态
    
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
                APB_STATUS_IDLE: // 空闲
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
                APB_STATUS_READY: // 就绪
                begin
                    m_apb_penable_reg <= 1'b1;
                    m_apb_psel_regs <= m_apb_psel_regs; // hold
                    m_apb_status <= APB_STATUS_TRANS;
                end
                APB_STATUS_TRANS: // 等待APB从机完成传输
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
                APB_STATUS_WAIT: // 等待AXI主机完成
                begin
                    m_apb_penable_reg <= 1'b0;
                    m_apb_psel_regs <= {apb_slave_n{1'b0}};
                    
                    if(~m_apb_pwrite_reg) // 读传输
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
