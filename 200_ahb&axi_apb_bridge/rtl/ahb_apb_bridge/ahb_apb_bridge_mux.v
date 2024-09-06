`timescale 1ns / 1ps
/********************************************************************
本模块: AHB到APB桥的数据MUX

描述: 
支持多达16个APB从机的数据MUX

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/04/20
********************************************************************/


module ahb_apb_bridge_mux #(
    parameter integer apb_slave_n = 4 // APB从机个数(1~16)
)(
    input wire[3:0] apb_muxsel,
    
    input wire s0_apb_pready,
    input wire s0_apb_pslverr,
    input wire[31:0] s0_apb_prdata,
    input wire s1_apb_pready,
    input wire s1_apb_pslverr,
    input wire[31:0] s1_apb_prdata,
    input wire s2_apb_pready,
    input wire s2_apb_pslverr,
    input wire[31:0] s2_apb_prdata,
    input wire s3_apb_pready,
    input wire s3_apb_pslverr,
    input wire[31:0] s3_apb_prdata,
    input wire s4_apb_pready,
    input wire s4_apb_pslverr,
    input wire[31:0] s4_apb_prdata,
    input wire s5_apb_pready,
    input wire s5_apb_pslverr,
    input wire[31:0] s5_apb_prdata,
    input wire s6_apb_pready,
    input wire s6_apb_pslverr,
    input wire[31:0] s6_apb_prdata,
    input wire s7_apb_pready,
    input wire s7_apb_pslverr,
    input wire[31:0] s7_apb_prdata,
    input wire s8_apb_pready,
    input wire s8_apb_pslverr,
    input wire[31:0] s8_apb_prdata,
    input wire s9_apb_pready,
    input wire s9_apb_pslverr,
    input wire[31:0] s9_apb_prdata,
    input wire s10_apb_pready,
    input wire s10_apb_pslverr,
    input wire[31:0] s10_apb_prdata,
    input wire s11_apb_pready,
    input wire s11_apb_pslverr,
    input wire[31:0] s11_apb_prdata,
    input wire s12_apb_pready,
    input wire s12_apb_pslverr,
    input wire[31:0] s12_apb_prdata,
    input wire s13_apb_pready,
    input wire s13_apb_pslverr,
    input wire[31:0] s13_apb_prdata,
    input wire s14_apb_pready,
    input wire s14_apb_pslverr,
    input wire[31:0] s14_apb_prdata,
    input wire s15_apb_pready,
    input wire s15_apb_pslverr,
    input wire[31:0] s15_apb_prdata,
    
    output wire s_apb_pready,
    output wire s_apb_pslverr,
    output wire[31:0] s_apb_prdata
);
    
    generate
        if(apb_slave_n == 1)
        begin
            assign s_apb_pready = s0_apb_pready;
            assign s_apb_pslverr = s0_apb_pslverr;
            assign s_apb_prdata = s0_apb_prdata;
        end
        else
        begin
            reg s_apb_pready_w;
            reg s_apb_pslverr_w;
            reg[31:0] s_apb_prdata_w;
            
            assign s_apb_pready = s_apb_pready_w;
            assign s_apb_pslverr = s_apb_pslverr_w;
            assign s_apb_prdata = s_apb_prdata_w;
            
            case(apb_slave_n)
                2:
                begin
                    always @(*)
                    begin
                        case(apb_muxsel)
                            4'd0:
                            begin
                                s_apb_pready_w = s0_apb_pready;
                                s_apb_pslverr_w = s0_apb_pslverr;
                                s_apb_prdata_w = s0_apb_prdata;
                            end
                            default:
                            begin
                                s_apb_pready_w = s1_apb_pready;
                                s_apb_pslverr_w = s1_apb_pslverr;
                                s_apb_prdata_w = s1_apb_prdata;
                            end
                        endcase
                    end
                end
                
                3:
                begin
                    always @(*)
                    begin
                        case(apb_muxsel)
                            4'd0:
                            begin
                                s_apb_pready_w = s0_apb_pready;
                                s_apb_pslverr_w = s0_apb_pslverr;
                                s_apb_prdata_w = s0_apb_prdata;
                            end
                            4'd1:
                            begin
                                s_apb_pready_w = s1_apb_pready;
                                s_apb_pslverr_w = s1_apb_pslverr;
                                s_apb_prdata_w = s1_apb_prdata;
                            end
                            default:
                            begin
                                s_apb_pready_w = s2_apb_pready;
                                s_apb_pslverr_w = s2_apb_pslverr;
                                s_apb_prdata_w = s2_apb_prdata;
                            end
                        endcase
                    end
                end
                
                4:
                begin
                    always @(*)
                    begin
                        case(apb_muxsel)
                            4'd0:
                            begin
                                s_apb_pready_w = s0_apb_pready;
                                s_apb_pslverr_w = s0_apb_pslverr;
                                s_apb_prdata_w = s0_apb_prdata;
                            end
                            4'd1:
                            begin
                                s_apb_pready_w = s1_apb_pready;
                                s_apb_pslverr_w = s1_apb_pslverr;
                                s_apb_prdata_w = s1_apb_prdata;
                            end
                            4'd2:
                            begin
                                s_apb_pready_w = s2_apb_pready;
                                s_apb_pslverr_w = s2_apb_pslverr;
                                s_apb_prdata_w = s2_apb_prdata;
                            end
                            default:
                            begin
                                s_apb_pready_w = s3_apb_pready;
                                s_apb_pslverr_w = s3_apb_pslverr;
                                s_apb_prdata_w = s3_apb_prdata;
                            end
                        endcase
                    end
                end
                
                5:
                begin
                    always @(*)
                    begin
                        case(apb_muxsel)
                            4'd0:
                            begin
                                s_apb_pready_w = s0_apb_pready;
                                s_apb_pslverr_w = s0_apb_pslverr;
                                s_apb_prdata_w = s0_apb_prdata;
                            end
                            4'd1:
                            begin
                                s_apb_pready_w = s1_apb_pready;
                                s_apb_pslverr_w = s1_apb_pslverr;
                                s_apb_prdata_w = s1_apb_prdata;
                            end
                            4'd2:
                            begin
                                s_apb_pready_w = s2_apb_pready;
                                s_apb_pslverr_w = s2_apb_pslverr;
                                s_apb_prdata_w = s2_apb_prdata;
                            end
                            4'd3:
                            begin
                                s_apb_pready_w = s3_apb_pready;
                                s_apb_pslverr_w = s3_apb_pslverr;
                                s_apb_prdata_w = s3_apb_prdata;
                            end
                            default:
                            begin
                                s_apb_pready_w = s4_apb_pready;
                                s_apb_pslverr_w = s4_apb_pslverr;
                                s_apb_prdata_w = s4_apb_prdata;
                            end
                        endcase
                    end
                end
                
                6:
                begin
                    always @(*)
                    begin
                        case(apb_muxsel)
                            4'd0:
                            begin
                                s_apb_pready_w = s0_apb_pready;
                                s_apb_pslverr_w = s0_apb_pslverr;
                                s_apb_prdata_w = s0_apb_prdata;
                            end
                            4'd1:
                            begin
                                s_apb_pready_w = s1_apb_pready;
                                s_apb_pslverr_w = s1_apb_pslverr;
                                s_apb_prdata_w = s1_apb_prdata;
                            end
                            4'd2:
                            begin
                                s_apb_pready_w = s2_apb_pready;
                                s_apb_pslverr_w = s2_apb_pslverr;
                                s_apb_prdata_w = s2_apb_prdata;
                            end
                            4'd3:
                            begin
                                s_apb_pready_w = s3_apb_pready;
                                s_apb_pslverr_w = s3_apb_pslverr;
                                s_apb_prdata_w = s3_apb_prdata;
                            end
                            4'd4:
                            begin
                                s_apb_pready_w = s4_apb_pready;
                                s_apb_pslverr_w = s4_apb_pslverr;
                                s_apb_prdata_w = s4_apb_prdata;
                            end
                            default:
                            begin
                                s_apb_pready_w = s5_apb_pready;
                                s_apb_pslverr_w = s5_apb_pslverr;
                                s_apb_prdata_w = s5_apb_prdata;
                            end
                        endcase
                    end
                end
                
                7:
                begin
                    always @(*)
                    begin
                        case(apb_muxsel)
                            4'd0:
                            begin
                                s_apb_pready_w = s0_apb_pready;
                                s_apb_pslverr_w = s0_apb_pslverr;
                                s_apb_prdata_w = s0_apb_prdata;
                            end
                            4'd1:
                            begin
                                s_apb_pready_w = s1_apb_pready;
                                s_apb_pslverr_w = s1_apb_pslverr;
                                s_apb_prdata_w = s1_apb_prdata;
                            end
                            4'd2:
                            begin
                                s_apb_pready_w = s2_apb_pready;
                                s_apb_pslverr_w = s2_apb_pslverr;
                                s_apb_prdata_w = s2_apb_prdata;
                            end
                            4'd3:
                            begin
                                s_apb_pready_w = s3_apb_pready;
                                s_apb_pslverr_w = s3_apb_pslverr;
                                s_apb_prdata_w = s3_apb_prdata;
                            end
                            4'd4:
                            begin
                                s_apb_pready_w = s4_apb_pready;
                                s_apb_pslverr_w = s4_apb_pslverr;
                                s_apb_prdata_w = s4_apb_prdata;
                            end
                            4'd5:
                            begin
                                s_apb_pready_w = s5_apb_pready;
                                s_apb_pslverr_w = s5_apb_pslverr;
                                s_apb_prdata_w = s5_apb_prdata;
                            end
                            default:
                            begin
                                s_apb_pready_w = s6_apb_pready;
                                s_apb_pslverr_w = s6_apb_pslverr;
                                s_apb_prdata_w = s6_apb_prdata;
                            end
                        endcase
                    end
                end
                
                8:
                begin
                    always @(*)
                    begin
                        case(apb_muxsel)
                            4'd0:
                            begin
                                s_apb_pready_w = s0_apb_pready;
                                s_apb_pslverr_w = s0_apb_pslverr;
                                s_apb_prdata_w = s0_apb_prdata;
                            end
                            4'd1:
                            begin
                                s_apb_pready_w = s1_apb_pready;
                                s_apb_pslverr_w = s1_apb_pslverr;
                                s_apb_prdata_w = s1_apb_prdata;
                            end
                            4'd2:
                            begin
                                s_apb_pready_w = s2_apb_pready;
                                s_apb_pslverr_w = s2_apb_pslverr;
                                s_apb_prdata_w = s2_apb_prdata;
                            end
                            4'd3:
                            begin
                                s_apb_pready_w = s3_apb_pready;
                                s_apb_pslverr_w = s3_apb_pslverr;
                                s_apb_prdata_w = s3_apb_prdata;
                            end
                            4'd4:
                            begin
                                s_apb_pready_w = s4_apb_pready;
                                s_apb_pslverr_w = s4_apb_pslverr;
                                s_apb_prdata_w = s4_apb_prdata;
                            end
                            4'd5:
                            begin
                                s_apb_pready_w = s5_apb_pready;
                                s_apb_pslverr_w = s5_apb_pslverr;
                                s_apb_prdata_w = s5_apb_prdata;
                            end
                            4'd6:
                            begin
                                s_apb_pready_w = s6_apb_pready;
                                s_apb_pslverr_w = s6_apb_pslverr;
                                s_apb_prdata_w = s6_apb_prdata;
                            end
                            default:
                            begin
                                s_apb_pready_w = s7_apb_pready;
                                s_apb_pslverr_w = s7_apb_pslverr;
                                s_apb_prdata_w = s7_apb_prdata;
                            end
                        endcase
                    end
                end
                
                9:
                begin
                    always @(*)
                    begin
                        case(apb_muxsel)
                            4'd0:
                            begin
                                s_apb_pready_w = s0_apb_pready;
                                s_apb_pslverr_w = s0_apb_pslverr;
                                s_apb_prdata_w = s0_apb_prdata;
                            end
                            4'd1:
                            begin
                                s_apb_pready_w = s1_apb_pready;
                                s_apb_pslverr_w = s1_apb_pslverr;
                                s_apb_prdata_w = s1_apb_prdata;
                            end
                            4'd2:
                            begin
                                s_apb_pready_w = s2_apb_pready;
                                s_apb_pslverr_w = s2_apb_pslverr;
                                s_apb_prdata_w = s2_apb_prdata;
                            end
                            4'd3:
                            begin
                                s_apb_pready_w = s3_apb_pready;
                                s_apb_pslverr_w = s3_apb_pslverr;
                                s_apb_prdata_w = s3_apb_prdata;
                            end
                            4'd4:
                            begin
                                s_apb_pready_w = s4_apb_pready;
                                s_apb_pslverr_w = s4_apb_pslverr;
                                s_apb_prdata_w = s4_apb_prdata;
                            end
                            4'd5:
                            begin
                                s_apb_pready_w = s5_apb_pready;
                                s_apb_pslverr_w = s5_apb_pslverr;
                                s_apb_prdata_w = s5_apb_prdata;
                            end
                            4'd6:
                            begin
                                s_apb_pready_w = s6_apb_pready;
                                s_apb_pslverr_w = s6_apb_pslverr;
                                s_apb_prdata_w = s6_apb_prdata;
                            end
                            4'd7:
                            begin
                                s_apb_pready_w = s7_apb_pready;
                                s_apb_pslverr_w = s7_apb_pslverr;
                                s_apb_prdata_w = s7_apb_prdata;
                            end
                            default:
                            begin
                                s_apb_pready_w = s8_apb_pready;
                                s_apb_pslverr_w = s8_apb_pslverr;
                                s_apb_prdata_w = s8_apb_prdata;
                            end
                        endcase
                    end
                end
                
                10:
                begin
                    always @(*)
                    begin
                        case(apb_muxsel)
                            4'd0:
                            begin
                                s_apb_pready_w = s0_apb_pready;
                                s_apb_pslverr_w = s0_apb_pslverr;
                                s_apb_prdata_w = s0_apb_prdata;
                            end
                            4'd1:
                            begin
                                s_apb_pready_w = s1_apb_pready;
                                s_apb_pslverr_w = s1_apb_pslverr;
                                s_apb_prdata_w = s1_apb_prdata;
                            end
                            4'd2:
                            begin
                                s_apb_pready_w = s2_apb_pready;
                                s_apb_pslverr_w = s2_apb_pslverr;
                                s_apb_prdata_w = s2_apb_prdata;
                            end
                            4'd3:
                            begin
                                s_apb_pready_w = s3_apb_pready;
                                s_apb_pslverr_w = s3_apb_pslverr;
                                s_apb_prdata_w = s3_apb_prdata;
                            end
                            4'd4:
                            begin
                                s_apb_pready_w = s4_apb_pready;
                                s_apb_pslverr_w = s4_apb_pslverr;
                                s_apb_prdata_w = s4_apb_prdata;
                            end
                            4'd5:
                            begin
                                s_apb_pready_w = s5_apb_pready;
                                s_apb_pslverr_w = s5_apb_pslverr;
                                s_apb_prdata_w = s5_apb_prdata;
                            end
                            4'd6:
                            begin
                                s_apb_pready_w = s6_apb_pready;
                                s_apb_pslverr_w = s6_apb_pslverr;
                                s_apb_prdata_w = s6_apb_prdata;
                            end
                            4'd7:
                            begin
                                s_apb_pready_w = s7_apb_pready;
                                s_apb_pslverr_w = s7_apb_pslverr;
                                s_apb_prdata_w = s7_apb_prdata;
                            end
                            4'd8:
                            begin
                                s_apb_pready_w = s8_apb_pready;
                                s_apb_pslverr_w = s8_apb_pslverr;
                                s_apb_prdata_w = s8_apb_prdata;
                            end
                            default:
                            begin
                                s_apb_pready_w = s9_apb_pready;
                                s_apb_pslverr_w = s9_apb_pslverr;
                                s_apb_prdata_w = s9_apb_prdata;
                            end
                        endcase
                    end
                end
                
                11:
                begin
                    always @(*)
                    begin
                        case(apb_muxsel)
                            4'd0:
                            begin
                                s_apb_pready_w = s0_apb_pready;
                                s_apb_pslverr_w = s0_apb_pslverr;
                                s_apb_prdata_w = s0_apb_prdata;
                            end
                            4'd1:
                            begin
                                s_apb_pready_w = s1_apb_pready;
                                s_apb_pslverr_w = s1_apb_pslverr;
                                s_apb_prdata_w = s1_apb_prdata;
                            end
                            4'd2:
                            begin
                                s_apb_pready_w = s2_apb_pready;
                                s_apb_pslverr_w = s2_apb_pslverr;
                                s_apb_prdata_w = s2_apb_prdata;
                            end
                            4'd3:
                            begin
                                s_apb_pready_w = s3_apb_pready;
                                s_apb_pslverr_w = s3_apb_pslverr;
                                s_apb_prdata_w = s3_apb_prdata;
                            end
                            4'd4:
                            begin
                                s_apb_pready_w = s4_apb_pready;
                                s_apb_pslverr_w = s4_apb_pslverr;
                                s_apb_prdata_w = s4_apb_prdata;
                            end
                            4'd5:
                            begin
                                s_apb_pready_w = s5_apb_pready;
                                s_apb_pslverr_w = s5_apb_pslverr;
                                s_apb_prdata_w = s5_apb_prdata;
                            end
                            4'd6:
                            begin
                                s_apb_pready_w = s6_apb_pready;
                                s_apb_pslverr_w = s6_apb_pslverr;
                                s_apb_prdata_w = s6_apb_prdata;
                            end
                            4'd7:
                            begin
                                s_apb_pready_w = s7_apb_pready;
                                s_apb_pslverr_w = s7_apb_pslverr;
                                s_apb_prdata_w = s7_apb_prdata;
                            end
                            4'd8:
                            begin
                                s_apb_pready_w = s8_apb_pready;
                                s_apb_pslverr_w = s8_apb_pslverr;
                                s_apb_prdata_w = s8_apb_prdata;
                            end
                            4'd9:
                            begin
                                s_apb_pready_w = s9_apb_pready;
                                s_apb_pslverr_w = s9_apb_pslverr;
                                s_apb_prdata_w = s9_apb_prdata;
                            end
                            default:
                            begin
                                s_apb_pready_w = s10_apb_pready;
                                s_apb_pslverr_w = s10_apb_pslverr;
                                s_apb_prdata_w = s10_apb_prdata;
                            end
                        endcase
                    end
                end
                
                12:
                begin
                    always @(*)
                    begin
                        case(apb_muxsel)
                            4'd0:
                            begin
                                s_apb_pready_w = s0_apb_pready;
                                s_apb_pslverr_w = s0_apb_pslverr;
                                s_apb_prdata_w = s0_apb_prdata;
                            end
                            4'd1:
                            begin
                                s_apb_pready_w = s1_apb_pready;
                                s_apb_pslverr_w = s1_apb_pslverr;
                                s_apb_prdata_w = s1_apb_prdata;
                            end
                            4'd2:
                            begin
                                s_apb_pready_w = s2_apb_pready;
                                s_apb_pslverr_w = s2_apb_pslverr;
                                s_apb_prdata_w = s2_apb_prdata;
                            end
                            4'd3:
                            begin
                                s_apb_pready_w = s3_apb_pready;
                                s_apb_pslverr_w = s3_apb_pslverr;
                                s_apb_prdata_w = s3_apb_prdata;
                            end
                            4'd4:
                            begin
                                s_apb_pready_w = s4_apb_pready;
                                s_apb_pslverr_w = s4_apb_pslverr;
                                s_apb_prdata_w = s4_apb_prdata;
                            end
                            4'd5:
                            begin
                                s_apb_pready_w = s5_apb_pready;
                                s_apb_pslverr_w = s5_apb_pslverr;
                                s_apb_prdata_w = s5_apb_prdata;
                            end
                            4'd6:
                            begin
                                s_apb_pready_w = s6_apb_pready;
                                s_apb_pslverr_w = s6_apb_pslverr;
                                s_apb_prdata_w = s6_apb_prdata;
                            end
                            4'd7:
                            begin
                                s_apb_pready_w = s7_apb_pready;
                                s_apb_pslverr_w = s7_apb_pslverr;
                                s_apb_prdata_w = s7_apb_prdata;
                            end
                            4'd8:
                            begin
                                s_apb_pready_w = s8_apb_pready;
                                s_apb_pslverr_w = s8_apb_pslverr;
                                s_apb_prdata_w = s8_apb_prdata;
                            end
                            4'd9:
                            begin
                                s_apb_pready_w = s9_apb_pready;
                                s_apb_pslverr_w = s9_apb_pslverr;
                                s_apb_prdata_w = s9_apb_prdata;
                            end
                            4'd10:
                            begin
                                s_apb_pready_w = s10_apb_pready;
                                s_apb_pslverr_w = s10_apb_pslverr;
                                s_apb_prdata_w = s10_apb_prdata;
                            end
                            default:
                            begin
                                s_apb_pready_w = s11_apb_pready;
                                s_apb_pslverr_w = s11_apb_pslverr;
                                s_apb_prdata_w = s11_apb_prdata;
                            end
                        endcase
                    end
                end
                
                13:
                begin
                    always @(*)
                    begin
                        case(apb_muxsel)
                            4'd0:
                            begin
                                s_apb_pready_w = s0_apb_pready;
                                s_apb_pslverr_w = s0_apb_pslverr;
                                s_apb_prdata_w = s0_apb_prdata;
                            end
                            4'd1:
                            begin
                                s_apb_pready_w = s1_apb_pready;
                                s_apb_pslverr_w = s1_apb_pslverr;
                                s_apb_prdata_w = s1_apb_prdata;
                            end
                            4'd2:
                            begin
                                s_apb_pready_w = s2_apb_pready;
                                s_apb_pslverr_w = s2_apb_pslverr;
                                s_apb_prdata_w = s2_apb_prdata;
                            end
                            4'd3:
                            begin
                                s_apb_pready_w = s3_apb_pready;
                                s_apb_pslverr_w = s3_apb_pslverr;
                                s_apb_prdata_w = s3_apb_prdata;
                            end
                            4'd4:
                            begin
                                s_apb_pready_w = s4_apb_pready;
                                s_apb_pslverr_w = s4_apb_pslverr;
                                s_apb_prdata_w = s4_apb_prdata;
                            end
                            4'd5:
                            begin
                                s_apb_pready_w = s5_apb_pready;
                                s_apb_pslverr_w = s5_apb_pslverr;
                                s_apb_prdata_w = s5_apb_prdata;
                            end
                            4'd6:
                            begin
                                s_apb_pready_w = s6_apb_pready;
                                s_apb_pslverr_w = s6_apb_pslverr;
                                s_apb_prdata_w = s6_apb_prdata;
                            end
                            4'd7:
                            begin
                                s_apb_pready_w = s7_apb_pready;
                                s_apb_pslverr_w = s7_apb_pslverr;
                                s_apb_prdata_w = s7_apb_prdata;
                            end
                            4'd8:
                            begin
                                s_apb_pready_w = s8_apb_pready;
                                s_apb_pslverr_w = s8_apb_pslverr;
                                s_apb_prdata_w = s8_apb_prdata;
                            end
                            4'd9:
                            begin
                                s_apb_pready_w = s9_apb_pready;
                                s_apb_pslverr_w = s9_apb_pslverr;
                                s_apb_prdata_w = s9_apb_prdata;
                            end
                            4'd10:
                            begin
                                s_apb_pready_w = s10_apb_pready;
                                s_apb_pslverr_w = s10_apb_pslverr;
                                s_apb_prdata_w = s10_apb_prdata;
                            end
                            4'd11:
                            begin
                                s_apb_pready_w = s11_apb_pready;
                                s_apb_pslverr_w = s11_apb_pslverr;
                                s_apb_prdata_w = s11_apb_prdata;
                            end
                            default:
                            begin
                                s_apb_pready_w = s12_apb_pready;
                                s_apb_pslverr_w = s12_apb_pslverr;
                                s_apb_prdata_w = s12_apb_prdata;
                            end
                        endcase
                    end
                end
                
                14:
                begin
                    always @(*)
                    begin
                        case(apb_muxsel)
                            4'd0:
                            begin
                                s_apb_pready_w = s0_apb_pready;
                                s_apb_pslverr_w = s0_apb_pslverr;
                                s_apb_prdata_w = s0_apb_prdata;
                            end
                            4'd1:
                            begin
                                s_apb_pready_w = s1_apb_pready;
                                s_apb_pslverr_w = s1_apb_pslverr;
                                s_apb_prdata_w = s1_apb_prdata;
                            end
                            4'd2:
                            begin
                                s_apb_pready_w = s2_apb_pready;
                                s_apb_pslverr_w = s2_apb_pslverr;
                                s_apb_prdata_w = s2_apb_prdata;
                            end
                            4'd3:
                            begin
                                s_apb_pready_w = s3_apb_pready;
                                s_apb_pslverr_w = s3_apb_pslverr;
                                s_apb_prdata_w = s3_apb_prdata;
                            end
                            4'd4:
                            begin
                                s_apb_pready_w = s4_apb_pready;
                                s_apb_pslverr_w = s4_apb_pslverr;
                                s_apb_prdata_w = s4_apb_prdata;
                            end
                            4'd5:
                            begin
                                s_apb_pready_w = s5_apb_pready;
                                s_apb_pslverr_w = s5_apb_pslverr;
                                s_apb_prdata_w = s5_apb_prdata;
                            end
                            4'd6:
                            begin
                                s_apb_pready_w = s6_apb_pready;
                                s_apb_pslverr_w = s6_apb_pslverr;
                                s_apb_prdata_w = s6_apb_prdata;
                            end
                            4'd7:
                            begin
                                s_apb_pready_w = s7_apb_pready;
                                s_apb_pslverr_w = s7_apb_pslverr;
                                s_apb_prdata_w = s7_apb_prdata;
                            end
                            4'd8:
                            begin
                                s_apb_pready_w = s8_apb_pready;
                                s_apb_pslverr_w = s8_apb_pslverr;
                                s_apb_prdata_w = s8_apb_prdata;
                            end
                            4'd9:
                            begin
                                s_apb_pready_w = s9_apb_pready;
                                s_apb_pslverr_w = s9_apb_pslverr;
                                s_apb_prdata_w = s9_apb_prdata;
                            end
                            4'd10:
                            begin
                                s_apb_pready_w = s10_apb_pready;
                                s_apb_pslverr_w = s10_apb_pslverr;
                                s_apb_prdata_w = s10_apb_prdata;
                            end
                            4'd11:
                            begin
                                s_apb_pready_w = s11_apb_pready;
                                s_apb_pslverr_w = s11_apb_pslverr;
                                s_apb_prdata_w = s11_apb_prdata;
                            end
                            4'd12:
                            begin
                                s_apb_pready_w = s12_apb_pready;
                                s_apb_pslverr_w = s12_apb_pslverr;
                                s_apb_prdata_w = s12_apb_prdata;
                            end
                            default:
                            begin
                                s_apb_pready_w = s13_apb_pready;
                                s_apb_pslverr_w = s13_apb_pslverr;
                                s_apb_prdata_w = s13_apb_prdata;
                            end
                        endcase
                    end
                end
                
                15:
                begin
                    always @(*)
                    begin
                        case(apb_muxsel)
                            4'd0:
                            begin
                                s_apb_pready_w = s0_apb_pready;
                                s_apb_pslverr_w = s0_apb_pslverr;
                                s_apb_prdata_w = s0_apb_prdata;
                            end
                            4'd1:
                            begin
                                s_apb_pready_w = s1_apb_pready;
                                s_apb_pslverr_w = s1_apb_pslverr;
                                s_apb_prdata_w = s1_apb_prdata;
                            end
                            4'd2:
                            begin
                                s_apb_pready_w = s2_apb_pready;
                                s_apb_pslverr_w = s2_apb_pslverr;
                                s_apb_prdata_w = s2_apb_prdata;
                            end
                            4'd3:
                            begin
                                s_apb_pready_w = s3_apb_pready;
                                s_apb_pslverr_w = s3_apb_pslverr;
                                s_apb_prdata_w = s3_apb_prdata;
                            end
                            4'd4:
                            begin
                                s_apb_pready_w = s4_apb_pready;
                                s_apb_pslverr_w = s4_apb_pslverr;
                                s_apb_prdata_w = s4_apb_prdata;
                            end
                            4'd5:
                            begin
                                s_apb_pready_w = s5_apb_pready;
                                s_apb_pslverr_w = s5_apb_pslverr;
                                s_apb_prdata_w = s5_apb_prdata;
                            end
                            4'd6:
                            begin
                                s_apb_pready_w = s6_apb_pready;
                                s_apb_pslverr_w = s6_apb_pslverr;
                                s_apb_prdata_w = s6_apb_prdata;
                            end
                            4'd7:
                            begin
                                s_apb_pready_w = s7_apb_pready;
                                s_apb_pslverr_w = s7_apb_pslverr;
                                s_apb_prdata_w = s7_apb_prdata;
                            end
                            4'd8:
                            begin
                                s_apb_pready_w = s8_apb_pready;
                                s_apb_pslverr_w = s8_apb_pslverr;
                                s_apb_prdata_w = s8_apb_prdata;
                            end
                            4'd9:
                            begin
                                s_apb_pready_w = s9_apb_pready;
                                s_apb_pslverr_w = s9_apb_pslverr;
                                s_apb_prdata_w = s9_apb_prdata;
                            end
                            4'd10:
                            begin
                                s_apb_pready_w = s10_apb_pready;
                                s_apb_pslverr_w = s10_apb_pslverr;
                                s_apb_prdata_w = s10_apb_prdata;
                            end
                            4'd11:
                            begin
                                s_apb_pready_w = s11_apb_pready;
                                s_apb_pslverr_w = s11_apb_pslverr;
                                s_apb_prdata_w = s11_apb_prdata;
                            end
                            4'd12:
                            begin
                                s_apb_pready_w = s12_apb_pready;
                                s_apb_pslverr_w = s12_apb_pslverr;
                                s_apb_prdata_w = s12_apb_prdata;
                            end
                            4'd13:
                            begin
                                s_apb_pready_w = s13_apb_pready;
                                s_apb_pslverr_w = s13_apb_pslverr;
                                s_apb_prdata_w = s13_apb_prdata;
                            end
                            default:
                            begin
                                s_apb_pready_w = s14_apb_pready;
                                s_apb_pslverr_w = s14_apb_pslverr;
                                s_apb_prdata_w = s14_apb_prdata;
                            end
                        endcase
                    end
                end
                
                16:
                begin
                    always @(*)
                    begin
                        case(apb_muxsel)
                            4'd0:
                            begin
                                s_apb_pready_w = s0_apb_pready;
                                s_apb_pslverr_w = s0_apb_pslverr;
                                s_apb_prdata_w = s0_apb_prdata;
                            end
                            4'd1:
                            begin
                                s_apb_pready_w = s1_apb_pready;
                                s_apb_pslverr_w = s1_apb_pslverr;
                                s_apb_prdata_w = s1_apb_prdata;
                            end
                            4'd2:
                            begin
                                s_apb_pready_w = s2_apb_pready;
                                s_apb_pslverr_w = s2_apb_pslverr;
                                s_apb_prdata_w = s2_apb_prdata;
                            end
                            4'd3:
                            begin
                                s_apb_pready_w = s3_apb_pready;
                                s_apb_pslverr_w = s3_apb_pslverr;
                                s_apb_prdata_w = s3_apb_prdata;
                            end
                            4'd4:
                            begin
                                s_apb_pready_w = s4_apb_pready;
                                s_apb_pslverr_w = s4_apb_pslverr;
                                s_apb_prdata_w = s4_apb_prdata;
                            end
                            4'd5:
                            begin
                                s_apb_pready_w = s5_apb_pready;
                                s_apb_pslverr_w = s5_apb_pslverr;
                                s_apb_prdata_w = s5_apb_prdata;
                            end
                            4'd6:
                            begin
                                s_apb_pready_w = s6_apb_pready;
                                s_apb_pslverr_w = s6_apb_pslverr;
                                s_apb_prdata_w = s6_apb_prdata;
                            end
                            4'd7:
                            begin
                                s_apb_pready_w = s7_apb_pready;
                                s_apb_pslverr_w = s7_apb_pslverr;
                                s_apb_prdata_w = s7_apb_prdata;
                            end
                            4'd8:
                            begin
                                s_apb_pready_w = s8_apb_pready;
                                s_apb_pslverr_w = s8_apb_pslverr;
                                s_apb_prdata_w = s8_apb_prdata;
                            end
                            4'd9:
                            begin
                                s_apb_pready_w = s9_apb_pready;
                                s_apb_pslverr_w = s9_apb_pslverr;
                                s_apb_prdata_w = s9_apb_prdata;
                            end
                            4'd10:
                            begin
                                s_apb_pready_w = s10_apb_pready;
                                s_apb_pslverr_w = s10_apb_pslverr;
                                s_apb_prdata_w = s10_apb_prdata;
                            end
                            4'd11:
                            begin
                                s_apb_pready_w = s11_apb_pready;
                                s_apb_pslverr_w = s11_apb_pslverr;
                                s_apb_prdata_w = s11_apb_prdata;
                            end
                            4'd12:
                            begin
                                s_apb_pready_w = s12_apb_pready;
                                s_apb_pslverr_w = s12_apb_pslverr;
                                s_apb_prdata_w = s12_apb_prdata;
                            end
                            4'd13:
                            begin
                                s_apb_pready_w = s13_apb_pready;
                                s_apb_pslverr_w = s13_apb_pslverr;
                                s_apb_prdata_w = s13_apb_prdata;
                            end
                            4'd14:
                            begin
                                s_apb_pready_w = s14_apb_pready;
                                s_apb_pslverr_w = s14_apb_pslverr;
                                s_apb_prdata_w = s14_apb_prdata;
                            end
                            default:
                            begin
                                s_apb_pready_w = s15_apb_pready;
                                s_apb_pslverr_w = s15_apb_pslverr;
                                s_apb_prdata_w = s15_apb_prdata;
                            end
                        endcase
                    end
                end
            endcase
        end
    endgenerate
    
endmodule
