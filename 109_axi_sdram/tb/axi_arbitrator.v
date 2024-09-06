`timescale 1ns / 1ps
/********************************************************************
本模块: AXI仲裁器

描述: 
对AXI的读地址/写地址通道进行仲裁

注意：
无

协议:
FIFO WRITE

作者: 陈家耀
日期: 2024/04/29
********************************************************************/


module axi_arbitrator #(
    parameter integer master_n = 4, // 主机个数(必须在范围[2, 8]内)
    parameter integer arb_itv = 4, // 仲裁间隔周期数(必须在范围[2, 16]内)
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 从机AR/AW通道
    input wire[52:0] s0_ar_aw_payload, // 0号从机的负载
    input wire[52:0] s1_ar_aw_payload, // 1号从机的负载
    input wire[52:0] s2_ar_aw_payload, // 2号从机的负载
    input wire[52:0] s3_ar_aw_payload, // 3号从机的负载
    input wire[52:0] s4_ar_aw_payload, // 4号从机的负载
    input wire[52:0] s5_ar_aw_payload, // 5号从机的负载
    input wire[52:0] s6_ar_aw_payload, // 6号从机的负载
    input wire[52:0] s7_ar_aw_payload, // 7号从机的负载
    input wire[7:0] s_ar_aw_valid, // 每个从机的valid
    output wire[7:0] s_ar_aw_ready, // 每个从机的ready
    
    // 主机AR/AW通道
    output wire[52:0] m_ar_aw_payload, // 主机负载
    output wire[clogb2(master_n-1):0] m_ar_aw_id, // 事务id
    output wire m_ar_aw_valid,
    input wire m_ar_aw_ready,
    
    // 授权主机编号fifo写端口
    output wire grant_mid_fifo_wen,
    input wire grant_mid_fifo_full_n,
    output wire[master_n-1:0] grant_mid_fifo_din_onehot, // 独热码编号
    output wire[clogb2(master_n-1):0] grant_mid_fifo_din_bin // 二进制码编号
);

    // 计算log2(bit_depth)               
    function integer clogb2 (input integer bit_depth);
        integer temp;
    begin
        temp = bit_depth;
        for(clogb2 = -1;temp > 0;clogb2 = clogb2 + 1)
            temp = temp >> 1;
    end
    endfunction

    /** 常量 **/
    // 状态常量
    localparam STS_ARB = 2'b00; // 状态:仲裁
    localparam STS_M_TRANS = 2'b01; // 状态:将AR/AW事务传递给主机
    localparam STS_ITV = 2'b10; // 状态:间隙期
    
    /** 仲裁器状态机 **/
    wire arb_valid; // 仲裁结果有效(指示)
    reg[arb_itv-1:0] arb_itv_cnt; // 仲裁间隔计数器
    reg[1:0] arb_now_sts; // 当前状态
    
    // 当前状态
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            arb_now_sts <= STS_ARB;
        else
        begin
            # simulation_delay;
            
            case(arb_now_sts)
                STS_ARB: // 状态:仲裁
                    if(arb_valid)
                        arb_now_sts <= STS_M_TRANS; // -> 状态:将AR/AW事务传递给主机
                STS_M_TRANS: // 状态:将AR/AW事务传递给主机
                    if(m_ar_aw_ready)
                        arb_now_sts <= STS_ITV; // -> 状态:间隙期
                STS_ITV: // 状态:间隙期
                    if(arb_itv_cnt[arb_itv-1])
                        arb_now_sts <= STS_ARB; // -> 状态:仲裁
                default:
                    arb_now_sts <= STS_ARB;
            endcase
        end
    end
    
    /** Round-Robin仲裁器 **/
    wire[master_n-1:0] arb_req; // 请求
    wire[master_n-1:0] arb_grant; // 授权(独热码)
    wire[clogb2(master_n-1):0] arb_sel; // 选择(相当于授权的二进制表示)
    
    assign arb_req = ((arb_now_sts == STS_ARB) & grant_mid_fifo_full_n) ? s_ar_aw_valid[master_n-1:0]:{master_n{1'b0}};
    
    // Round-Robin仲裁器
    round_robin_arbitrator #(
        .chn_n(master_n),
        .simulation_delay(simulation_delay)
    )arbitrator(
        .clk(clk),
        .rst_n(rst_n),
        .req(arb_req),
        .grant(arb_grant),
        .sel(arb_sel),
        .arb_valid(arb_valid)
    );
    
    /** 从机AR/AW通道 **/
    wire[52:0] s_ar_aw_payload[7:0]; // 从机负载
    reg[master_n-1:0] s_ar_aw_ready_regs; // 每个从机的ready
    
    assign s_ar_aw_ready = {{(8-master_n){1'b1}}, s_ar_aw_ready_regs};
    
    assign s_ar_aw_payload[0] = s0_ar_aw_payload;
    assign s_ar_aw_payload[1] = s1_ar_aw_payload;
    assign s_ar_aw_payload[2] = s2_ar_aw_payload;
    assign s_ar_aw_payload[3] = s3_ar_aw_payload;
    assign s_ar_aw_payload[4] = s4_ar_aw_payload;
    assign s_ar_aw_payload[5] = s5_ar_aw_payload;
    assign s_ar_aw_payload[6] = s6_ar_aw_payload;
    assign s_ar_aw_payload[7] = s7_ar_aw_payload;
    
    // 每个从机的ready
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            s_ar_aw_ready_regs <= {master_n{1'b0}};
        else
            # simulation_delay s_ar_aw_ready_regs <= arb_grant;
    end
    
    /** 主机AR/AW通道 **/
    reg[52:0] m_payload_latched; // 锁存的主机负载
    reg[clogb2(master_n-1):0] arb_sel_latched; // 锁存的仲裁选择
    reg m_valid; // 主机输出valid
    
    assign m_ar_aw_payload = m_payload_latched;
    assign m_ar_aw_id = arb_sel_latched;
    assign m_ar_aw_valid = m_valid;
    
    // 锁存的主机负载
    always @(posedge clk)
    begin
        if(arb_valid)
            # simulation_delay m_payload_latched <= s_ar_aw_payload[arb_sel];
    end
    // 锁存的仲裁选择
    always @(posedge clk)
    begin
        if(arb_valid)
            # simulation_delay arb_sel_latched <= arb_sel;
    end
    // 主机输出valid
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            m_valid <= 1'b0;
        else
            # simulation_delay m_valid <= m_valid ? (~m_ar_aw_ready):arb_valid;
    end
    
    /** 授权主机编号fifo写端口 **/
    reg grant_mid_fifo_wen_reg;
    reg[master_n-1:0] grant_mid_fifo_din_onehot_regs;
    reg[clogb2(master_n-1):0] grant_mid_fifo_din_bin_regs;
    
    assign grant_mid_fifo_wen = grant_mid_fifo_wen_reg;
    assign grant_mid_fifo_din_onehot = grant_mid_fifo_din_onehot_regs;
    assign grant_mid_fifo_din_bin = grant_mid_fifo_din_bin_regs;
    
    // 授权主机编号fifo写使能
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            grant_mid_fifo_wen_reg <= 1'b0;
        else
            # simulation_delay grant_mid_fifo_wen_reg <= arb_valid;
    end
    // 授权主机编号fifo写数据
    always @(posedge clk)
        # simulation_delay grant_mid_fifo_din_onehot_regs <= arb_grant;
    always @(posedge clk)
        # simulation_delay grant_mid_fifo_din_bin_regs <= arb_sel;
    
    /** 仲裁间隔计数器 **/
    // 仲裁间隔计数器
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            arb_itv_cnt <= {{(arb_itv-1){1'b0}}, 1'b1};
        else if(arb_now_sts == STS_ITV)
            # simulation_delay arb_itv_cnt <= {arb_itv_cnt[arb_itv-2:0], arb_itv_cnt[arb_itv-1]};
    end
    
endmodule
