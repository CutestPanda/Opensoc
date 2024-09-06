`timescale 1ns / 1ps
/********************************************************************
本模块: AXI地址通道的边界保护

描述: 
对AXI从机的AR/AW通道进行边界保护
32位地址/数据总线
支持非对齐传输/窄带传输

注意：
仅支持INCR突发类型

协议:
AXI MASTER(ONLY AW/AR)
AXIS SLAVE
FIFO WRITE

作者: 陈家耀
日期: 2024/05/01
********************************************************************/


module axi_ar_aw_boundary_protect #(
    parameter en_narrow_transfer = "false", // 是否允许窄带传输
    parameter integer boundary_size = 1, // 边界大小(以KB计)(1 | 2 | 4)
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // AXI从机的AR或AW
    input wire[53:0] s_axis_ax_data, // {保留(1bit), axsize(3bit), axprot(3bit), axlock(1bit), axlen(8bit), axcache(4bit), axburst(2bit), axaddr(32bit)}
    input wire s_axis_ax_valid,
    output wire s_axis_ax_ready,
    
    // AXI主机的AR或AW
    output wire[31:0] m_axi_axaddr,
    output wire[1:0] m_axi_axburst,
    output wire[3:0] m_axi_axcache,
    output wire[7:0] m_axi_axlen,
    output wire m_axi_axlock,
    output wire[2:0] m_axi_axprot,
    output wire[2:0] m_axi_axsize,
    output wire m_axi_axvalid,
    input wire m_axi_axready,
    
    // 突发长度fifo写端口
    output wire burst_len_fifo_wen,
    output wire[7:0] burst_len_fifo_din, // 突发长度 - 1
    input wire burst_len_fifo_almost_full_n, // full无效时fifo至少剩余2个空位
    
    // 跨界标志fifo写端口
    output wire across_boundary_fifo_wen,
    output wire across_boundary_fifo_din, // 是否跨界
    input wire across_boundary_fifo_full_n
);

    /** 常量 **/
    // 状态常量
    localparam STS_WAIT_S_AX_VLD = 2'b00; // 状态:等待从机有效
    localparam STS_M_AX_0 = 2'b01; // 状态:向主机传递突发0的地址信息
    localparam STS_M_AX_1 = 2'b10; // 状态:向主机传递突发1的地址信息
    localparam STS_S_AX_RDY = 2'b11; // 状态:从机地址通道握手

    /** AXI从机的AR或AW **/
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
    
    /** 边界保护状态机 **/
    reg across_boundary_latched; // 锁存的是否跨越边界
    reg[31:0] burst_addr[1:0]; // 两次突发的首地址
    reg[7:0] burst_len[1:0]; // 两次突发的长度 - 1
    reg[1:0] boundary_protect_sts; // 当前状态
    
    // 当前状态
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            boundary_protect_sts <= STS_WAIT_S_AX_VLD;
        else
        begin
            # simulation_delay;
            
            case(boundary_protect_sts)
                STS_WAIT_S_AX_VLD: // 状态:等待从机有效
                    if(s_axis_ax_valid & burst_len_fifo_almost_full_n & across_boundary_fifo_full_n)
                        boundary_protect_sts <= STS_M_AX_0; // -> 状态:向主机传递突发0的地址信息
                STS_M_AX_0: // 状态:向主机传递突发0的地址信息
                    if(m_axi_axready)
                        boundary_protect_sts <= across_boundary_latched ? STS_M_AX_1: // -> 状态:向主机传递突发1的地址信息
                            STS_S_AX_RDY; // -> 状态:从机地址通道握手
                STS_M_AX_1: // 状态:向主机传递突发1的地址信息
                    if(m_axi_axready)
                        boundary_protect_sts <= STS_S_AX_RDY; // -> 状态:从机地址通道握手
                STS_S_AX_RDY: // 状态:从机地址通道握手
                    boundary_protect_sts <= STS_WAIT_S_AX_VLD;
                default:
                    boundary_protect_sts <= STS_WAIT_S_AX_VLD;
            endcase
        end
    end
    
    // AXI从机AR或AW的ready信号
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            s_axis_ax_ready_reg <= 1'b0;
        else
            # simulation_delay s_axis_ax_ready_reg <= ((boundary_protect_sts == STS_M_AX_0) & (m_axi_axready & (~across_boundary_latched))) | 
                ((boundary_protect_sts == STS_M_AX_1) & m_axi_axready);
    end
    
    /** 进行突发划分 **/
    // 突发划分结果
    // 对32位数据总线来说, 每次突发最多传输1KB, 因此进行1/2/4KB边界保护, 最多把原来的1次突发划分为2次
    wire across_boundary; // 是否跨越边界
    wire[31:0] burst0_addr; // 突发0的首地址
    wire[7:0] burst0_len; // 突发0的长度 - 1
    wire[31:0] burst1_addr; // 突发1的首地址
    wire[7:0] burst1_len; // 突发1的长度 - 1
    
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
    
    // 锁存的是否跨越边界
    always @(posedge clk)
    begin
        if((boundary_protect_sts == STS_WAIT_S_AX_VLD) & (s_axis_ax_valid & burst_len_fifo_almost_full_n & across_boundary_fifo_full_n))
            # simulation_delay across_boundary_latched <= across_boundary;
    end
    // 两次突发的首地址
    always @(posedge clk)
    begin
        if((boundary_protect_sts == STS_WAIT_S_AX_VLD) & (s_axis_ax_valid & burst_len_fifo_almost_full_n & across_boundary_fifo_full_n))
            # simulation_delay {burst_addr[1], burst_addr[0]} <= {burst1_addr, burst0_addr};
        else if((boundary_protect_sts == STS_M_AX_0) & m_axi_axready)
            # simulation_delay {burst_addr[1], burst_addr[0]} <= {burst_addr[0], burst_addr[1]};
    end
    // 两次突发的长度 - 1
    always @(posedge clk)
    begin
        if((boundary_protect_sts == STS_WAIT_S_AX_VLD) & (s_axis_ax_valid & burst_len_fifo_almost_full_n & across_boundary_fifo_full_n))
            # simulation_delay {burst_len[1], burst_len[0]} <= {burst1_len, burst0_len};
        else if((boundary_protect_sts == STS_M_AX_0) & m_axi_axready)
            # simulation_delay {burst_len[1], burst_len[0]} <= {burst_len[0], burst_len[1]};
    end
    
    /** AXI主机的AR或AW **/
    reg m_axi_axvalid_reg;
    
    assign m_axi_axaddr = burst_addr[0];
    assign m_axi_axburst = s_axi_ax_burst;
    assign m_axi_axcache = s_axi_ax_cache;
    assign m_axi_axlen = burst_len[0];
    assign m_axi_axlock = s_axi_ax_lock;
    assign m_axi_axprot = s_axi_ax_prot;
    assign m_axi_axsize = s_axi_ax_size;
    assign m_axi_axvalid = m_axi_axvalid_reg;
    
    // AXI主机AR或AW的valid信号
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            m_axi_axvalid_reg <= 1'b0;
        else
        begin
            # simulation_delay;
            
            case(boundary_protect_sts)
                STS_WAIT_S_AX_VLD: // 状态:等待从机有效
                    m_axi_axvalid_reg <= s_axis_ax_valid & burst_len_fifo_almost_full_n & across_boundary_fifo_full_n;
                STS_M_AX_0: // 状态:向主机传递突发0的地址信息
                    m_axi_axvalid_reg <= m_axi_axready ? across_boundary_latched:1'b1;
                STS_M_AX_1: // 状态:向主机传递突发1的地址信息
                    m_axi_axvalid_reg <= ~m_axi_axready;
                STS_S_AX_RDY: // 状态:从机地址通道握手
                    m_axi_axvalid_reg <= 1'b0;
                default:
                    m_axi_axvalid_reg <= 1'b0;
            endcase
        end
    end
    
    /** 突发长度fifo写端口 */
    assign burst_len_fifo_wen = m_axi_axvalid & m_axi_axready;
    assign burst_len_fifo_din = burst_len[0];
    
    /** 跨界标志fifo写端口 **/
    reg across_boundary_fifo_wen_reg;
    
    assign across_boundary_fifo_wen = across_boundary_fifo_wen_reg;
    assign across_boundary_fifo_din = across_boundary_latched;
    
    // 跨界标志fifo写使能
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            across_boundary_fifo_wen_reg <= 1'b0;
        else
            # simulation_delay across_boundary_fifo_wen_reg <= (boundary_protect_sts == STS_WAIT_S_AX_VLD) & 
                (s_axis_ax_valid & burst_len_fifo_almost_full_n & across_boundary_fifo_full_n);
    end
    
endmodule
