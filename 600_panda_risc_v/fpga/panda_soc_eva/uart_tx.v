`timescale 1ns / 1ps
/********************************************************************
本模块: UART发送控制器

描述: 
UART发送控制器
可选AXIS接口或FIFO接口

注意：
无

协议:
AXIS SLAVE
FIFO READ
UART

作者: 陈家耀
日期: 2023/11/08
********************************************************************/


module uart_tx #(
    parameter integer clk_frequency = 200000000, // 时钟频率
    parameter integer baud_rate = 115200, // 波特率
    parameter interface = "axis", // 接口协议(axis|fifo)
    parameter real simulation_delay = 1 // 仿真延时
)(
    input wire clk,
    input wire rst_n,
    
    output wire tx,
    
    input wire[7:0] tx_byte_data,
    input wire tx_byte_valid,
    output wire tx_byte_ready,
    
    input wire[7:0] tx_fifo_dout,
    input wire tx_fifo_empty,
    output wire tx_fifo_ren,
    
    output wire tx_idle,
    output wire tx_done
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
    
    localparam integer div_n = clk_frequency / baud_rate;
    
    /** 发送fifo读端口 **/
    wire[7:0] tx_fifo_data_out;
    wire tx_fifo_empty_n;
    
    reg ready_reg;
    
    assign tx_byte_ready = ready_reg;
    assign tx_fifo_data_out = (interface == "axis") ? tx_byte_data:tx_fifo_dout;
    assign tx_fifo_empty_n = (interface == "axis") ? tx_byte_valid:(~tx_fifo_empty);
    
    assign tx_fifo_ren = ready_reg;
    
    /** 分频计数器 **/
    reg[clogb2(div_n-1):0] cnt;
    reg cnt_last_flag;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
        begin
            cnt <= 0;
            cnt_last_flag <= 1'b0;
        end
        else
        begin
            # simulation_delay;
            
            if(cnt_last_flag)
                cnt <= 0;
            else
                cnt <= cnt + 1;
            
            cnt_last_flag <= cnt == div_n - 2;
        end
    end
    
    /** 数据发送状态机 **/
    localparam status_idle = 2'b00; // 状态:空闲
    localparam status_start = 2'b01; // 状态:起始位
    localparam status_data = 2'b10; // 状态:数据位
    localparam status_stop = 2'b11; // 状态:停止位
    
    reg[1:0] now_status; // 当前状态
    reg[7:0] now_byte; // 待发送字节
    reg tx_reg; // UART的tx端
    reg[7:0] now_byte_i; // 当前发送字节的位编号(独一码)
    reg byte_loaded; // 已加载待发送字节(标志)
    reg tx_idle_reg; // UART控制器发送空闲(标志)
    reg tx_done_reg; // UART控制器发送完成(标志)
    
    assign tx = tx_reg;
    assign tx_idle = tx_idle_reg;
    assign tx_done = tx_done_reg;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
        begin
            now_status <= status_idle;
            tx_reg <= 1'b1;
            now_byte_i <= 8'd1;
            byte_loaded <= 1'b0;
            ready_reg <= 1'b0;
            tx_idle_reg <= 1'b1;
            tx_done_reg <= 1'b0;
        end
        else
        begin
            # simulation_delay;
        
            ready_reg <= 1'b0;
            tx_done_reg <= 1'b0;
            
            case(now_status)
                status_idle: // 状态:空闲
                begin
                    if(byte_loaded)
                        now_status <= status_start;
                    
                    byte_loaded <= tx_fifo_empty_n & ready_reg;
                    tx_reg <= 1'b1;
                    ready_reg <= (~byte_loaded) & (~(tx_fifo_empty_n & ready_reg));
                    tx_idle_reg <= ~(byte_loaded | tx_fifo_empty_n); // 直接判断~tx_fifo_empty_n也可以???
                end
                status_start: // 状态:起始位
                begin
                    if(cnt_last_flag)
                    begin
                        now_status <= status_data;
                        tx_reg <= 1'b0; // 产生下降沿 -> 起始位
                    end
                    
                    byte_loaded <= 1'b0;
                    tx_idle_reg <= 1'b0;
                end
                status_data: // 状态:数据位
                begin
                    if(cnt_last_flag)
                    begin
                        if(now_byte_i[7])
                            now_status <= status_stop;
                        
                        now_byte_i <= {now_byte_i[6:0], now_byte_i[7]}; // 对当前发送字节的位编号(独一码)做循环左移
                        tx_reg <= now_byte[0]; // 发送下一数据位
                    end
                    
                    byte_loaded <= 1'b0;
                    tx_idle_reg <= 1'b0;
                end
                status_stop: // 状态:停止位
                begin
                    if(cnt_last_flag)
                    begin
                        now_status <= status_idle;
                        tx_reg <= 1'b1; // 产生停止位
                        tx_done_reg <= 1'b1;
                    end
                    
                    byte_loaded <= 1'b0;
                    tx_idle_reg <= 1'b0;
                end
                default:
                begin
                    now_status <= status_idle;
                    tx_reg <= 1'b1;
                    now_byte_i <= 8'd1;
                    byte_loaded <= 1'b0;
                    tx_idle_reg <= 1'b1;
                end
            endcase
        end
    end
    
    // 待发送字节
    always @(posedge clk)
    begin
        # simulation_delay;
        
        if((now_status == status_idle) &
            ((interface == "axis") ? (tx_fifo_empty_n & ready_reg):byte_loaded)) // 载入
            now_byte <= tx_fifo_data_out;
        else if((now_status == status_data) & cnt_last_flag) // 右移
            now_byte <= {1'bx, now_byte[7:1]};
    end

endmodule
