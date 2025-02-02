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
本模块: AHB到APB桥

描述: 
AHB到APB桥(AHB-APB桥是APB总线上唯一的主设备)
可选APB从机个数为1~16

注意：
每个从机的地址区间长度必须 >= 4096(4KB)

协议:
AHB-Lite SLAVE
APB MASTER

作者: 陈家耀
日期: 2024/04/20
********************************************************************/


module ahb_apb_bridge #(
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
    
    // APB MUX选择信号
    output wire[3:0] apb_muxsel
);

    /** 常量 **/
    // AHB传输类型
    localparam AHB_TRANS_IDLE = 2'b00;
    localparam AHB_TRANS_BUSY = 2'b01;
    localparam AHB_TRANS_NONSEQ = 2'b10;
    localparam AHB_TRANS_SEQ = 2'b11;
    
    /** 地址译码器 **/
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
    
    /** AHB从接口 **/
    reg[3:0] apb_slave_muxsel; // APB从机返回数据选择
    reg[31:0] ahb_haddr_latched; // 锁存的AHB传输地址
    reg ahb_hwrite_latched; // 锁存的AHB读写类型
    reg[2:0] ahb_hprot_latched; // 锁存的AHB保护类型
    reg apb_transmitting; // APB传输进行中(标志)
    reg ahb_hready; // APB传输完成
    reg[31:0] apb_rdata_d; // 延迟1clk的APB读数据返回
    reg ahb_hresp; // AHB传输响应
    
    assign s_ahb_hready_out = ahb_hready;
    assign s_ahb_hrdata = apb_rdata_d;
    assign s_ahb_hresp = ahb_hresp;
    
    assign apb_muxsel = apb_slave_muxsel;
    
    // AHB-APB译码错误, APB从机返回数据选择, 锁存的AHB传输地址, 锁存的AHB读写类型, 锁存的AHB保护类型
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
    
    // APB传输完成
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
                ahb_hready <= # simulation_delay ahb_hresp | // 译码错误或从机错误
                    (m_apb_penable & m_apb_pready & (~m_apb_pslverr)); // 正常传输
            end
        end
    end
    
    // 延迟1clk的APB读数据返回
    always @(posedge clk)
        apb_rdata_d <= # simulation_delay m_apb_prdata;
    
    // AHB传输响应
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
    
    /** APB主接口 **/
    reg[apb_slave_n-1:0] apb_pselx; // APB从机选择
    reg apb_valid_trans_start_d; // 延迟1clk的有效APB传输开始(指示)
    reg apb_penable; // APB传输使能
    
    assign m_apb_paddr = ahb_haddr_latched;
    assign m_apb_penable = apb_penable;
    assign m_apb_pwrite = ahb_hwrite_latched;
    assign m_apb_pprot = ahb_hprot_latched;
    assign m_apb_psel = apb_pselx;
    assign m_apb_pstrb = s_ahb_hwstrb;
    assign m_apb_pwdata = s_ahb_hwdata;
    
    // APB传输进行中(标志)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            apb_transmitting <= 1'b0;
        else
            apb_transmitting <= # simulation_delay apb_transmitting ? (~(m_apb_penable & m_apb_pready)):(s_ahb_hsel & s_ahb_hready_in & (s_ahb_htrans == AHB_TRANS_NONSEQ));
    end
    
    // APB从机选择
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
    
    // 延迟1clk的有效APB传输开始(指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            apb_valid_trans_start_d <= 1'b0;
        else
            apb_valid_trans_start_d <= # simulation_delay s_ahb_hsel & s_ahb_hready_in & (s_ahb_htrans == AHB_TRANS_NONSEQ) & 
                (m_apb_psel_w[apb_slave_n-1:0] != {apb_slave_n{1'b0}});
    end
    
    // APB传输使能
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            apb_penable <= 1'b0;
        else
            apb_penable <= # simulation_delay apb_penable ? (~m_apb_pready):apb_valid_trans_start_d;
    end
    
endmodule
