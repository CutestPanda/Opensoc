`timescale 1ns / 1ps
/********************************************************************
本模块: AHB到APB桥(顶层)

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


module ahb_apb_bridge_wrapper #(
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
    
    // APB MASTER #0
    output wire[31:0] m0_apb_paddr,
    output wire m0_apb_penable,
    output wire m0_apb_pwrite,
    output wire[2:0] m0_apb_pprot,
    output wire m0_apb_psel,
    output wire[3:0] m0_apb_pstrb,
    output wire[31:0] m0_apb_pwdata,
    input wire m0_apb_pready,
    input wire m0_apb_pslverr,
    input wire[31:0] m0_apb_prdata,
    // APB MASTER #1
    output wire[31:0] m1_apb_paddr,
    output wire m1_apb_penable,
    output wire m1_apb_pwrite,
    output wire[2:0] m1_apb_pprot,
    output wire m1_apb_psel,
    output wire[3:0] m1_apb_pstrb,
    output wire[31:0] m1_apb_pwdata,
    input wire m1_apb_pready,
    input wire m1_apb_pslverr,
    input wire[31:0] m1_apb_prdata,
    // APB MASTER #2
    output wire[31:0] m2_apb_paddr,
    output wire m2_apb_penable,
    output wire m2_apb_pwrite,
    output wire[2:0] m2_apb_pprot,
    output wire m2_apb_psel,
    output wire[3:0] m2_apb_pstrb,
    output wire[31:0] m2_apb_pwdata,
    input wire m2_apb_pready,
    input wire m2_apb_pslverr,
    input wire[31:0] m2_apb_prdata,
    // APB MASTER #3
    output wire[31:0] m3_apb_paddr,
    output wire m3_apb_penable,
    output wire m3_apb_pwrite,
    output wire[2:0] m3_apb_pprot,
    output wire m3_apb_psel,
    output wire[3:0] m3_apb_pstrb,
    output wire[31:0] m3_apb_pwdata,
    input wire m3_apb_pready,
    input wire m3_apb_pslverr,
    input wire[31:0] m3_apb_prdata,
    // APB MASTER #4
    output wire[31:0] m4_apb_paddr,
    output wire m4_apb_penable,
    output wire m4_apb_pwrite,
    output wire[2:0] m4_apb_pprot,
    output wire m4_apb_psel,
    output wire[3:0] m4_apb_pstrb,
    output wire[31:0] m4_apb_pwdata,
    input wire m4_apb_pready,
    input wire m4_apb_pslverr,
    input wire[31:0] m4_apb_prdata,
    // APB MASTER #5
    output wire[31:0] m5_apb_paddr,
    output wire m5_apb_penable,
    output wire m5_apb_pwrite,
    output wire[2:0] m5_apb_pprot,
    output wire m5_apb_psel,
    output wire[3:0] m5_apb_pstrb,
    output wire[31:0] m5_apb_pwdata,
    input wire m5_apb_pready,
    input wire m5_apb_pslverr,
    input wire[31:0] m5_apb_prdata,
    // APB MASTER #6
    output wire[31:0] m6_apb_paddr,
    output wire m6_apb_penable,
    output wire m6_apb_pwrite,
    output wire[2:0] m6_apb_pprot,
    output wire m6_apb_psel,
    output wire[3:0] m6_apb_pstrb,
    output wire[31:0] m6_apb_pwdata,
    input wire m6_apb_pready,
    input wire m6_apb_pslverr,
    input wire[31:0] m6_apb_prdata,
    // APB MASTER #7
    output wire[31:0] m7_apb_paddr,
    output wire m7_apb_penable,
    output wire m7_apb_pwrite,
    output wire[2:0] m7_apb_pprot,
    output wire m7_apb_psel,
    output wire[3:0] m7_apb_pstrb,
    output wire[31:0] m7_apb_pwdata,
    input wire m7_apb_pready,
    input wire m7_apb_pslverr,
    input wire[31:0] m7_apb_prdata,
    // APB MASTER #8
    output wire[31:0] m8_apb_paddr,
    output wire m8_apb_penable,
    output wire m8_apb_pwrite,
    output wire[2:0] m8_apb_pprot,
    output wire m8_apb_psel,
    output wire[3:0] m8_apb_pstrb,
    output wire[31:0] m8_apb_pwdata,
    input wire m8_apb_pready,
    input wire m8_apb_pslverr,
    input wire[31:0] m8_apb_prdata,
    // APB MASTER #9
    output wire[31:0] m9_apb_paddr,
    output wire m9_apb_penable,
    output wire m9_apb_pwrite,
    output wire[2:0] m9_apb_pprot,
    output wire m9_apb_psel,
    output wire[3:0] m9_apb_pstrb,
    output wire[31:0] m9_apb_pwdata,
    input wire m9_apb_pready,
    input wire m9_apb_pslverr,
    input wire[31:0] m9_apb_prdata,
    // APB MASTER #10
    output wire[31:0] m10_apb_paddr,
    output wire m10_apb_penable,
    output wire m10_apb_pwrite,
    output wire[2:0] m10_apb_pprot,
    output wire m10_apb_psel,
    output wire[3:0] m10_apb_pstrb,
    output wire[31:0] m10_apb_pwdata,
    input wire m10_apb_pready,
    input wire m10_apb_pslverr,
    input wire[31:0] m10_apb_prdata,
    // APB MASTER #11
    output wire[31:0] m11_apb_paddr,
    output wire m11_apb_penable,
    output wire m11_apb_pwrite,
    output wire[2:0] m11_apb_pprot,
    output wire m11_apb_psel,
    output wire[3:0] m11_apb_pstrb,
    output wire[31:0] m11_apb_pwdata,
    input wire m11_apb_pready,
    input wire m11_apb_pslverr,
    input wire[31:0] m11_apb_prdata,
    // APB MASTER #12
    output wire[31:0] m12_apb_paddr,
    output wire m12_apb_penable,
    output wire m12_apb_pwrite,
    output wire[2:0] m12_apb_pprot,
    output wire m12_apb_psel,
    output wire[3:0] m12_apb_pstrb,
    output wire[31:0] m12_apb_pwdata,
    input wire m12_apb_pready,
    input wire m12_apb_pslverr,
    input wire[31:0] m12_apb_prdata,
    // APB MASTER #13
    output wire[31:0] m13_apb_paddr,
    output wire m13_apb_penable,
    output wire m13_apb_pwrite,
    output wire[2:0] m13_apb_pprot,
    output wire m13_apb_psel,
    output wire[3:0] m13_apb_pstrb,
    output wire[31:0] m13_apb_pwdata,
    input wire m13_apb_pready,
    input wire m13_apb_pslverr,
    input wire[31:0] m13_apb_prdata,
    // APB MASTER #14
    output wire[31:0] m14_apb_paddr,
    output wire m14_apb_penable,
    output wire m14_apb_pwrite,
    output wire[2:0] m14_apb_pprot,
    output wire m14_apb_psel,
    output wire[3:0] m14_apb_pstrb,
    output wire[31:0] m14_apb_pwdata,
    input wire m14_apb_pready,
    input wire m14_apb_pslverr,
    input wire[31:0] m14_apb_prdata,
    // APB MASTER #15
    output wire[31:0] m15_apb_paddr,
    output wire m15_apb_penable,
    output wire m15_apb_pwrite,
    output wire[2:0] m15_apb_pprot,
    output wire m15_apb_psel,
    output wire[3:0] m15_apb_pstrb,
    output wire[31:0] m15_apb_pwdata,
    input wire m15_apb_pready,
    input wire m15_apb_pslverr,
    input wire[31:0] m15_apb_prdata
);

    /** 桥主体 **/
    wire[3:0] apb_muxsel; // APB MUX选择信号
    
    wire[31:0] m_apb_paddr;
    wire m_apb_penable;
    wire m_apb_pwrite;
    wire[2:0] m_apb_pprot;
    wire[15:0] m_apb_psel;
    wire[3:0] m_apb_pstrb;
    wire[31:0] m_apb_pwdata;
    wire m_apb_pready;
    wire m_apb_pslverr;
    wire[31:0] m_apb_prdata;
    
    assign m0_apb_paddr = m_apb_paddr;
    assign m0_apb_penable = m_apb_penable;
    assign m0_apb_pwrite = m_apb_pwrite;
    assign m0_apb_pprot = m_apb_pprot;
    assign m0_apb_psel = m_apb_psel[0];
    assign m0_apb_pstrb = m_apb_pstrb;
    assign m0_apb_pwdata = m_apb_pwdata;
    
    assign m1_apb_paddr = m_apb_paddr;
    assign m1_apb_penable = m_apb_penable;
    assign m1_apb_pwrite = m_apb_pwrite;
    assign m1_apb_pprot = m_apb_pprot;
    assign m1_apb_psel = (apb_slave_n >= 2) & m_apb_psel[1];
    assign m1_apb_pstrb = m_apb_pstrb;
    assign m1_apb_pwdata = m_apb_pwdata;
    
    assign m2_apb_paddr = m_apb_paddr;
    assign m2_apb_penable = m_apb_penable;
    assign m2_apb_pwrite = m_apb_pwrite;
    assign m2_apb_pprot = m_apb_pprot;
    assign m2_apb_psel = (apb_slave_n >= 3) & m_apb_psel[2];
    assign m2_apb_pstrb = m_apb_pstrb;
    assign m2_apb_pwdata = m_apb_pwdata;
    
    assign m3_apb_paddr = m_apb_paddr;
    assign m3_apb_penable = m_apb_penable;
    assign m3_apb_pwrite = m_apb_pwrite;
    assign m3_apb_pprot = m_apb_pprot;
    assign m3_apb_psel = (apb_slave_n >= 4) & m_apb_psel[3];
    assign m3_apb_pstrb = m_apb_pstrb;
    assign m3_apb_pwdata = m_apb_pwdata;
    
    assign m4_apb_paddr = m_apb_paddr;
    assign m4_apb_penable = m_apb_penable;
    assign m4_apb_pwrite = m_apb_pwrite;
    assign m4_apb_pprot = m_apb_pprot;
    assign m4_apb_psel = (apb_slave_n >= 5) & m_apb_psel[4];
    assign m4_apb_pstrb = m_apb_pstrb;
    assign m4_apb_pwdata = m_apb_pwdata;
    
    assign m5_apb_paddr = m_apb_paddr;
    assign m5_apb_penable = m_apb_penable;
    assign m5_apb_pwrite = m_apb_pwrite;
    assign m5_apb_pprot = m_apb_pprot;
    assign m5_apb_psel = (apb_slave_n >= 6) & m_apb_psel[5];
    assign m5_apb_pstrb = m_apb_pstrb;
    assign m5_apb_pwdata = m_apb_pwdata;
    
    assign m6_apb_paddr = m_apb_paddr;
    assign m6_apb_penable = m_apb_penable;
    assign m6_apb_pwrite = m_apb_pwrite;
    assign m6_apb_pprot = m_apb_pprot;
    assign m6_apb_psel = (apb_slave_n >= 7) & m_apb_psel[6];
    assign m6_apb_pstrb = m_apb_pstrb;
    assign m6_apb_pwdata = m_apb_pwdata;
    
    assign m7_apb_paddr = m_apb_paddr;
    assign m7_apb_penable = m_apb_penable;
    assign m7_apb_pwrite = m_apb_pwrite;
    assign m7_apb_pprot = m_apb_pprot;
    assign m7_apb_psel = (apb_slave_n >= 8) & m_apb_psel[7];
    assign m7_apb_pstrb = m_apb_pstrb;
    assign m7_apb_pwdata = m_apb_pwdata;
    
    assign m8_apb_paddr = m_apb_paddr;
    assign m8_apb_penable = m_apb_penable;
    assign m8_apb_pwrite = m_apb_pwrite;
    assign m8_apb_pprot = m_apb_pprot;
    assign m8_apb_psel = (apb_slave_n >= 9) & m_apb_psel[8];
    assign m8_apb_pstrb = m_apb_pstrb;
    assign m8_apb_pwdata = m_apb_pwdata;
    
    assign m9_apb_paddr = m_apb_paddr;
    assign m9_apb_penable = m_apb_penable;
    assign m9_apb_pwrite = m_apb_pwrite;
    assign m9_apb_pprot = m_apb_pprot;
    assign m9_apb_psel = (apb_slave_n >= 10) & m_apb_psel[9];
    assign m9_apb_pstrb = m_apb_pstrb;
    assign m9_apb_pwdata = m_apb_pwdata;
    
    assign m10_apb_paddr = m_apb_paddr;
    assign m10_apb_penable = m_apb_penable;
    assign m10_apb_pwrite = m_apb_pwrite;
    assign m10_apb_pprot = m_apb_pprot;
    assign m10_apb_psel = (apb_slave_n >= 11) & m_apb_psel[10];
    assign m10_apb_pstrb = m_apb_pstrb;
    assign m10_apb_pwdata = m_apb_pwdata;
    
    assign m11_apb_paddr = m_apb_paddr;
    assign m11_apb_penable = m_apb_penable;
    assign m11_apb_pwrite = m_apb_pwrite;
    assign m11_apb_pprot = m_apb_pprot;
    assign m11_apb_psel = (apb_slave_n >= 12) & m_apb_psel[11];
    assign m11_apb_pstrb = m_apb_pstrb;
    assign m11_apb_pwdata = m_apb_pwdata;
    
    assign m12_apb_paddr = m_apb_paddr;
    assign m12_apb_penable = m_apb_penable;
    assign m12_apb_pwrite = m_apb_pwrite;
    assign m12_apb_pprot = m_apb_pprot;
    assign m12_apb_psel = (apb_slave_n >= 13) & m_apb_psel[12];
    assign m12_apb_pstrb = m_apb_pstrb;
    assign m12_apb_pwdata = m_apb_pwdata;
    
    assign m13_apb_paddr = m_apb_paddr;
    assign m13_apb_penable = m_apb_penable;
    assign m13_apb_pwrite = m_apb_pwrite;
    assign m13_apb_pprot = m_apb_pprot;
    assign m13_apb_psel = (apb_slave_n >= 14) & m_apb_psel[13];
    assign m13_apb_pstrb = m_apb_pstrb;
    assign m13_apb_pwdata = m_apb_pwdata;
    
    assign m14_apb_paddr = m_apb_paddr;
    assign m14_apb_penable = m_apb_penable;
    assign m14_apb_pwrite = m_apb_pwrite;
    assign m14_apb_pprot = m_apb_pprot;
    assign m14_apb_psel = (apb_slave_n >= 15) & m_apb_psel[14];
    assign m14_apb_pstrb = m_apb_pstrb;
    assign m14_apb_pwdata = m_apb_pwdata;
    
    assign m15_apb_paddr = m_apb_paddr;
    assign m15_apb_penable = m_apb_penable;
    assign m15_apb_pwrite = m_apb_pwrite;
    assign m15_apb_pprot = m_apb_pprot;
    assign m15_apb_psel = (apb_slave_n >= 16) & m_apb_psel[15];
    assign m15_apb_pstrb = m_apb_pstrb;
    assign m15_apb_pwdata = m_apb_pwdata;
    
    ahb_apb_bridge #(
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
        .apb_s15_range(apb_s15_range),
        .simulation_delay(simulation_delay)
    )bridge(
        .clk(clk),
        .rst_n(rst_n),
        .s_ahb_haddr(s_ahb_haddr),
        .s_ahb_hburst(s_ahb_hburst),
        .s_ahb_hprot(s_ahb_hprot),
        .s_ahb_hrdata(s_ahb_hrdata),
        .s_ahb_hready_in(s_ahb_hready_in),
        .s_ahb_hready_out(s_ahb_hready_out),
        .s_ahb_hresp(s_ahb_hresp),
        .s_ahb_hsize(s_ahb_hsize),
        .s_ahb_htrans(s_ahb_htrans),
        .s_ahb_hwdata(s_ahb_hwdata),
        .s_ahb_hwstrb(s_ahb_hwstrb),
        .s_ahb_hwrite(s_ahb_hwrite),
        .s_ahb_hsel(s_ahb_hsel),
        .m_apb_paddr(m_apb_paddr),
        .m_apb_penable(m_apb_penable),
        .m_apb_pwrite(m_apb_pwrite),
        .m_apb_pprot(m_apb_pprot),
        .m_apb_psel(m_apb_psel[apb_slave_n-1:0]),
        .m_apb_pstrb(m_apb_pstrb),
        .m_apb_pwdata(m_apb_pwdata),
        .m_apb_pready(m_apb_pready),
        .m_apb_pslverr(m_apb_pslverr),
        .m_apb_prdata(m_apb_prdata),
        .apb_muxsel(apb_muxsel)
    );
    
    /** 数据MUX **/
    ahb_apb_bridge_mux #(
        .apb_slave_n(apb_slave_n)
    )data_mux(
        .apb_muxsel(apb_muxsel),
        .s0_apb_pready(m0_apb_pready),
        .s0_apb_pslverr(m0_apb_pslverr),
        .s0_apb_prdata(m0_apb_prdata),
        .s1_apb_pready(m1_apb_pready),
        .s1_apb_pslverr(m1_apb_pslverr),
        .s1_apb_prdata(m1_apb_prdata),
        .s2_apb_pready(m2_apb_pready),
        .s2_apb_pslverr(m2_apb_pslverr),
        .s2_apb_prdata(m2_apb_prdata),
        .s3_apb_pready(m3_apb_pready),
        .s3_apb_pslverr(m3_apb_pslverr),
        .s3_apb_prdata(m3_apb_prdata),
        .s4_apb_pready(m4_apb_pready),
        .s4_apb_pslverr(m4_apb_pslverr),
        .s4_apb_prdata(m4_apb_prdata),
        .s5_apb_pready(m5_apb_pready),
        .s5_apb_pslverr(m5_apb_pslverr),
        .s5_apb_prdata(m5_apb_prdata),
        .s6_apb_pready(m6_apb_pready),
        .s6_apb_pslverr(m6_apb_pslverr),
        .s6_apb_prdata(m6_apb_prdata),
        .s7_apb_pready(m7_apb_pready),
        .s7_apb_pslverr(m7_apb_pslverr),
        .s7_apb_prdata(m7_apb_prdata),
        .s8_apb_pready(m8_apb_pready),
        .s8_apb_pslverr(m8_apb_pslverr),
        .s8_apb_prdata(m8_apb_prdata),
        .s9_apb_pready(m9_apb_pready),
        .s9_apb_pslverr(m9_apb_pslverr),
        .s9_apb_prdata(m9_apb_prdata),
        .s10_apb_pready(m10_apb_pready),
        .s10_apb_pslverr(m10_apb_pslverr),
        .s10_apb_prdata(m10_apb_prdata),
        .s11_apb_pready(m11_apb_pready),
        .s11_apb_pslverr(m11_apb_pslverr),
        .s11_apb_prdata(m11_apb_prdata),
        .s12_apb_pready(m12_apb_pready),
        .s12_apb_pslverr(m12_apb_pslverr),
        .s12_apb_prdata(m12_apb_prdata),
        .s13_apb_pready(m13_apb_pready),
        .s13_apb_pslverr(m13_apb_pslverr),
        .s13_apb_prdata(m13_apb_prdata),
        .s14_apb_pready(m14_apb_pready),
        .s14_apb_pslverr(m14_apb_pslverr),
        .s14_apb_prdata(m14_apb_prdata),
        .s15_apb_pready(m15_apb_pready),
        .s15_apb_pslverr(m15_apb_pslverr),
        .s15_apb_prdata(m15_apb_prdata),
        .s_apb_pready(m_apb_pready),
        .s_apb_pslverr(m_apb_pslverr),
        .s_apb_prdata(m_apb_prdata)
    );

endmodule
