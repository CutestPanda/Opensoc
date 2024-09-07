`timescale 1ns / 1ps
/********************************************************************
本模块: APB-SDIO的中断发生器

描述:
中断 -> 读数据中断, 写数据中断, 常规命令处理完成中断脉冲

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/01/24
********************************************************************/


module sdio_itr_generator  #(
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire resetn,
    
    // 控制器状态
    input wire sdio_ctrler_done,
    input wire[1:0] sdio_ctrler_rw_type_done,
    
    // 中断控制
    output wire rdata_itr_org_pulse, // 读数据原始中断脉冲
    output wire wdata_itr_org_pulse, // 写数据原始中断脉冲
    output wire common_itr_org_pulse, // 常规命令处理完成中断脉冲
    input wire rdata_itr_en, // 读数据中断使能
    input wire wdata_itr_en, // 写数据中断使能
    input wire common_itr_en, // 常规命令处理完成中断使能
    input wire global_org_itr_pulse, // 全局原始中断脉冲
    output wire itr // 中断信号
);

    /** 常量 **/
    // 命令的读写类型
    localparam RW_TYPE_NON = 2'b00; // 非读写
    localparam RW_TYPE_READ = 2'b01; // 读
    localparam RW_TYPE_WRITE = 2'b10; // 写

    /** 原始子中断脉冲 **/
    reg rdata_itr_org_pulse_reg;
    reg wdata_itr_org_pulse_reg;
    reg common_itr_org_pulse_reg;
    
    assign {rdata_itr_org_pulse, wdata_itr_org_pulse, common_itr_org_pulse} = {rdata_itr_org_pulse_reg, wdata_itr_org_pulse_reg, common_itr_org_pulse_reg};
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            rdata_itr_org_pulse_reg <= 1'b0;
        else if(~rdata_itr_en) // 强制清零
            # simulation_delay rdata_itr_org_pulse_reg <= 1'b0;
        else // 产生脉冲
            # simulation_delay rdata_itr_org_pulse_reg <= sdio_ctrler_done & (sdio_ctrler_rw_type_done == RW_TYPE_READ);
    end
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            wdata_itr_org_pulse_reg <= 1'b0;
        else if(~wdata_itr_en) // 强制清零
            # simulation_delay wdata_itr_org_pulse_reg <= 1'b0;
        else // 产生脉冲
            # simulation_delay wdata_itr_org_pulse_reg <= sdio_ctrler_done & (sdio_ctrler_rw_type_done == RW_TYPE_WRITE);
    end
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            common_itr_org_pulse_reg <= 1'b0;
        else if(~common_itr_en) // 强制清零
            # simulation_delay common_itr_org_pulse_reg <= 1'b0;
        else // 产生脉冲
            # simulation_delay common_itr_org_pulse_reg <= sdio_ctrler_done & (sdio_ctrler_rw_type_done == RW_TYPE_NON);
    end
    
    /** 中断信号 **/
    itr_generator #(
        .pulse_w(10),
        .simulation_delay(simulation_delay)
    )itr_generator_u(
        .clk(clk),
        .rst_n(resetn),
        .itr_org(global_org_itr_pulse),
        .itr(itr)
    );

endmodule
