`timescale 1ns / 1ps
/********************************************************************
本模块: 符合APB协议的UART控制器

描述: 
APB-UART控制器
支持UART发送/接收中断

寄存器->
    偏移量  |    含义                     |   读写特性    |        备注
    0x00    0:发送fifo是否满                    R
            1:发送fifo写使能                    W         发送fifo写使能取上升沿
            9~2:发送fifo写数据                  W
            10:接收fifo是否空                   R
            11:接收fifo读使能                   W         接收fifo读使能取上升沿
            19~12:接收fifo读数据                R
    0x04    0:UART全局中断使能                  W
            1:UART发送达到规定字节数中断使能     W
            2:UART发送IDLE中断使能              W
            3:UART接收达到规定字节数中断使能     W
            4:UART接收IDLE中断使能              W
            5:UART接收FIFO溢出中断使能          W
            16:UART中断标志                    RWC      请在中断服务函数中清除中断标志
            21~17:UART中断状态                  R
    0x08    15~0:UART发送中断字节数阈值         W               注意要减1
            31~16:UART发送中断IDLE周期数阈值    W               注意要减2
    0x0C    15~0:UART接收中断字节数阈值         W               注意要减1
            31~16:UART接收中断IDLE周期数阈值    W               注意要减2

注意：
无

协议:
APB SLAVE
UART

作者: 陈家耀
日期: 2023/11/07
********************************************************************/


module apb_uart #(
    parameter integer clk_frequency_MHz = 50, // 时钟频率
    parameter integer baud_rate = 115200, // 波特率
    parameter tx_rx_fifo_ram_type = "bram", // 发送接收fifo的RAM类型(lutram|bram)
    parameter integer tx_fifo_depth = 1024, // 发送fifo深度(32|64|128|...|2048)
    parameter integer rx_fifo_depth = 1024, // 接收fifo深度(32|64|128|...|2048)
    parameter en_itr = "false", // 是否使能UART中断
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire resetn,
    
    // APB从机接口
    input wire[31:0] paddr,
    input wire psel,
    input wire penable,
    input wire pwrite,
    input wire[31:0] pwdata,
    output wire pready_out, // const -> 1'b1
    output wire[31:0] prdata_out,
    output wire pslverr_out, // const -> 1'b0
    
    // UART
    output wire uart_tx,
    input wire uart_rx,
    
    // 中断
    output wire uart_itr
);

    /* UART发送和接收fifo */
    // 发送fifo写端口
    wire tx_fifo_wen;
    wire tx_fifo_full;
    wire[7:0] tx_fifo_din;
    // 发送fifo读端口
    wire tx_fifo_ren;
    wire tx_fifo_empty;
    wire[7:0] tx_fifo_dout;
    // 接收fifo写端口
    wire rx_fifo_wen;
    wire rx_fifo_full;
    wire[7:0] rx_fifo_din;
    // 接收fifo读端口
    wire rx_fifo_ren;
    wire rx_fifo_empty;
    wire[7:0] rx_fifo_dout;
    
    // 发送fifo
    ram_fifo_wrapper #(
        .fwft_mode("false"),
        .ram_type(tx_rx_fifo_ram_type),
        .en_bram_reg("false"),
        .fifo_depth(tx_fifo_depth),
        .fifo_data_width(8),
        .full_assert_polarity("high"),
        .empty_assert_polarity("high"),
        .almost_full_assert_polarity("no"),
        .almost_empty_assert_polarity("no"),
        .en_data_cnt("false"),
        .almost_full_th(),
        .almost_empty_th(),
        .simulation_delay(simulation_delay)
    )tx_fifo(
        .clk(clk),
        .rst_n(resetn),
        .fifo_wen(tx_fifo_wen),
        .fifo_din(tx_fifo_din),
        .fifo_full(tx_fifo_full),
        .fifo_ren(tx_fifo_ren),
        .fifo_dout(tx_fifo_dout),
        .fifo_empty(tx_fifo_empty)
    );
    
    // 接收fifo
    ram_fifo_wrapper #(
        .fwft_mode("false"),
        .ram_type(tx_rx_fifo_ram_type),
        .en_bram_reg("false"),
        .fifo_depth(rx_fifo_depth),
        .fifo_data_width(8),
        .full_assert_polarity("high"),
        .empty_assert_polarity("high"),
        .almost_full_assert_polarity("no"),
        .almost_empty_assert_polarity("no"),
        .en_data_cnt("false"),
        .almost_full_th(),
        .almost_empty_th(),
        .simulation_delay(simulation_delay)
    )rx_fifo(
        .clk(clk),
        .rst_n(resetn),
        .fifo_wen(rx_fifo_wen),
        .fifo_din(rx_fifo_din),
        .fifo_full(rx_fifo_full),
        .fifo_ren(rx_fifo_ren),
        .fifo_dout(rx_fifo_dout),
        .fifo_empty(rx_fifo_empty)
    );
    
    /** UART中断 **/
    wire uart_org_itr_pulse; // 原始的UART中断脉冲
    wire uart_org_itr_pulse_d; // 延迟1clk的原始的UART中断脉冲
    wire uart_itr_flag; // UART总中断标志
    wire[4:0] uart_itr_mask; // UART子中断标志向量(UART接收FIFO溢出中断使能, UART接收IDLE中断使能, UART接收达到规定字节数中断使能, UART发送IDLE中断使能, UART发送达到规定字节数中断使能)
    wire[4:0] uart_itr_mask_d; // 延迟1clk的UART子中断标志向量
    wire uart_global_itr_en; // UART全局中断使能
    wire[4:0] uart_itr_en; // UART中断使能(UART接收FIFO溢出中断使能, UART接收IDLE中断使能, UART接收达到规定字节数中断使能, UART发送IDLE中断使能, UART发送达到规定字节数中断使能)
    
    wire[15:0] tx_bytes_n_th; // UART发送中断字节数阈值
    wire[15:0] tx_bytes_n_th_sub1; // UART发送中断字节数阈值-1
    wire tx_bytes_n_th_eq0; // UART发送中断字节数阈值等于0(标志)
    wire[15:0] tx_idle_n_th; // UART发送中断IDLE周期数阈值
    wire[15:0] rx_bytes_n_th; // UART接收中断字节数阈值
    wire[15:0] rx_bytes_n_th_sub1; // UART接收中断字节数阈值-1
    wire rx_bytes_n_th_eq0; // UART接收中断字节数阈值等于0(标志)
    wire[15:0] rx_idle_n_th; // UART接收中断IDLE周期数阈值
    
    wire rx_err; // 接收溢出(脉冲)
    wire tx_idle; // 发送空闲(标志)
    wire rx_idle; // 接收空闲(标志)
    wire tx_done; // 发送完成(脉冲)
    wire rx_done; // 接收完成(脉冲)
    wire rx_start; // 接收开始(脉冲)
    
    generate
        if(en_itr == "true")
        begin
            reg[15:0] uart_tx_finished_bytes_n_cnt; // 已发送字节数(计数器)
            reg uart_tx_finished_bytes_n_cnt_eq_th_sub1; // 已发送字节数 == UART发送中断字节数阈值-1(标志)
            reg uart_tx_finished_bytes_n_itr_pulse; // UART发送达到规定字节数(原始中断脉冲)
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                begin
                    uart_tx_finished_bytes_n_cnt <= 16'd0;
                    uart_tx_finished_bytes_n_cnt_eq_th_sub1 <= 1'b0;
                end
                else if((~uart_itr_en[0]) | (~uart_global_itr_en))
                begin
                    # simulation_delay;
                    
                    uart_tx_finished_bytes_n_cnt <= 16'd0;
                    uart_tx_finished_bytes_n_cnt_eq_th_sub1 <= 1'b0;
                end
                else if(tx_done)
                begin
                    # simulation_delay;
                    
                    uart_tx_finished_bytes_n_cnt <= (uart_tx_finished_bytes_n_cnt_eq_th_sub1 | tx_bytes_n_th_eq0) ? 16'd0:(uart_tx_finished_bytes_n_cnt + 16'd1);
                    uart_tx_finished_bytes_n_cnt_eq_th_sub1 <= uart_tx_finished_bytes_n_cnt == tx_bytes_n_th_sub1;
                end
            end
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                    uart_tx_finished_bytes_n_itr_pulse <= 1'b0;
                else
                    # simulation_delay uart_tx_finished_bytes_n_itr_pulse <= (uart_itr_en[0] & uart_global_itr_en) &
                        (uart_tx_finished_bytes_n_cnt_eq_th_sub1 | tx_bytes_n_th_eq0) & tx_done;
            end
            
            reg is_waiting_for_uart_tx_done; // 是否正在等待UART发送完成脉冲
            reg[15:0] uart_tx_idle_cnt; // UART发送空闲周期数(计数器)
            reg uart_tx_idle_cnt_eq_th_sub1; // UART发送空闲周期数 == UART发送中断IDLE周期数阈值
            reg uart_tx_idle_itr_pulse; // UART发送空闲(原始中断脉冲)
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                    is_waiting_for_uart_tx_done <= 1'b1;
                else
                    # simulation_delay is_waiting_for_uart_tx_done <= is_waiting_for_uart_tx_done ? (~tx_done):(uart_tx_idle_cnt_eq_th_sub1 | (~tx_idle));
            end
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                begin
                    uart_tx_idle_cnt <= 16'd0;
                    uart_tx_idle_cnt_eq_th_sub1 <= 1'b0;
                end
                else if((~uart_itr_en[1]) | (~uart_global_itr_en))
                begin
                    # simulation_delay;
                    
                    uart_tx_idle_cnt <= 16'd0;
                    uart_tx_idle_cnt_eq_th_sub1 <= 1'b0;
                end
                else if(~is_waiting_for_uart_tx_done)
                begin
                    # simulation_delay;
                    
                    uart_tx_idle_cnt <= (uart_tx_idle_cnt_eq_th_sub1 | (~tx_idle)) ? 16'd0:(uart_tx_idle_cnt + 16'd1);
                    uart_tx_idle_cnt_eq_th_sub1 <= uart_tx_idle_cnt == tx_idle_n_th;
                end
            end
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                    uart_tx_idle_itr_pulse <= 1'b0;
                else
                    # simulation_delay uart_tx_idle_itr_pulse <= (~is_waiting_for_uart_tx_done) & uart_tx_idle_cnt_eq_th_sub1 & tx_idle;
            end
            
            reg[15:0] uart_rx_finished_bytes_n_cnt;
            reg uart_rx_finished_bytes_n_cnt_eq_th_sub1;
            reg uart_rx_finished_bytes_n_itr_pulse;
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                begin
                    uart_rx_finished_bytes_n_cnt <= 16'd0;
                    uart_rx_finished_bytes_n_cnt_eq_th_sub1 <= 1'b0;
                end
                else if((~uart_itr_en[2]) | (~uart_global_itr_en))
                begin
                    # simulation_delay;
                    
                    uart_rx_finished_bytes_n_cnt <= 16'd0;
                    uart_rx_finished_bytes_n_cnt_eq_th_sub1 <= 1'b0;
                end
                else if(rx_done)
                begin
                    # simulation_delay;
                    
                    uart_rx_finished_bytes_n_cnt <= (uart_rx_finished_bytes_n_cnt_eq_th_sub1 | rx_bytes_n_th_eq0) ? 16'd0:(uart_rx_finished_bytes_n_cnt + 16'd1);
                    uart_rx_finished_bytes_n_cnt_eq_th_sub1 <= uart_rx_finished_bytes_n_cnt == rx_bytes_n_th_sub1;
               end
            end
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                    uart_rx_finished_bytes_n_itr_pulse <= 1'b0;
                else
                    # simulation_delay uart_rx_finished_bytes_n_itr_pulse <= (uart_itr_en[2] & uart_global_itr_en) &
                        (uart_rx_finished_bytes_n_cnt_eq_th_sub1 | rx_bytes_n_th_eq0) & rx_done;
            end
            
            reg is_waiting_for_uart_rx_done;
            reg[15:0] uart_rx_idle_cnt;
            reg uart_rx_idle_cnt_eq_th_sub1;
            reg uart_rx_idle_itr_pulse;
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                    is_waiting_for_uart_rx_done <= 1'b1;
                else
                    # simulation_delay is_waiting_for_uart_rx_done <= is_waiting_for_uart_rx_done ? (~rx_done):(uart_rx_idle_cnt_eq_th_sub1 | rx_start);
            end
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                begin
                    uart_rx_idle_cnt <= 16'd0;
                    uart_rx_idle_cnt_eq_th_sub1 <= 1'b0;
                end
                else if((~uart_itr_en[3]) | (~uart_global_itr_en))
                begin
                    # simulation_delay;
                    
                    uart_rx_idle_cnt <= 16'd0;
                    uart_rx_idle_cnt_eq_th_sub1 <= 1'b0;
                end
                else if((~is_waiting_for_uart_rx_done) & (rx_start | rx_idle))
                begin
                    # simulation_delay;
                    
                    uart_rx_idle_cnt <= (uart_rx_idle_cnt_eq_th_sub1 | rx_start) ? 16'd0:(uart_rx_idle_cnt + 16'd1);
                    uart_rx_idle_cnt_eq_th_sub1 <= rx_start ? 1'b0:(uart_rx_idle_cnt == rx_idle_n_th);
                end
            end
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                    uart_rx_idle_itr_pulse <= 1'b0;
                else
                    # simulation_delay uart_rx_idle_itr_pulse <= (~is_waiting_for_uart_rx_done) & uart_rx_idle_cnt_eq_th_sub1 & rx_idle;
            end
            
            reg rx_err_d;
            reg uart_rx_err_itr_pulse;
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                    rx_err_d <= 1'b0;
                else
                    # simulation_delay rx_err_d <= rx_err;
            end
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                    uart_rx_err_itr_pulse <= 1'b0;
                else if((~uart_itr_en[4]) | (~uart_global_itr_en))
                    uart_rx_err_itr_pulse <= 1'b0;
                else
                    # simulation_delay uart_rx_err_itr_pulse <= rx_err & (~rx_err_d);
            end
            
            assign uart_org_itr_pulse = (uart_rx_err_itr_pulse | uart_rx_idle_itr_pulse |
                uart_rx_finished_bytes_n_itr_pulse | uart_tx_idle_itr_pulse | uart_tx_finished_bytes_n_itr_pulse)
                & (~uart_itr_flag);
            assign uart_itr_mask = {uart_rx_err_itr_pulse, uart_rx_idle_itr_pulse, uart_rx_finished_bytes_n_itr_pulse,
                uart_tx_idle_itr_pulse, uart_tx_finished_bytes_n_itr_pulse};
            
            reg uart_org_itr_pulse_delay;
            reg[4:0] uart_itr_mask_delay;
            
            assign {uart_org_itr_pulse_d, uart_itr_mask_d} = {uart_org_itr_pulse_delay, uart_itr_mask_delay};
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                begin
                    uart_org_itr_pulse_delay <= 1'b0;
                    uart_itr_mask_delay <= 5'd0;
                end
                else
                begin
                    # simulation_delay;
                    
                    uart_org_itr_pulse_delay <= uart_org_itr_pulse;
                    uart_itr_mask_delay <= uart_itr_mask;
                end
            end
            
            itr_generator #(
                .pulse_w(10),
                .simulation_delay(simulation_delay)
            )itr_generator_u(
                .clk(clk),
                .rst_n(resetn),
                .itr_org(uart_org_itr_pulse),
                .itr(uart_itr)
            );
        end
        else
        begin
            assign uart_itr = 1'b0;
            
            assign {uart_org_itr_pulse, uart_itr_mask} = 6'd0;
            assign {uart_org_itr_pulse_d, uart_itr_mask_d} = 6'd0;
        end
    endgenerate
    
    /** UART控制器 **/
    uart_rx_tx #(
        .clk_frequency_MHz(clk_frequency_MHz),
        .baud_rate(),
        .interface("fifo"),
        .simulation_delay(simulation_delay)
    )uart_ctrler(
        .clk(clk),
        .resetn(resetn),
        .rx(uart_rx),
        .tx(uart_tx),
        .m_axis_rx_byte_data(),
        .m_axis_rx_byte_valid(),
        .m_axis_rx_byte_ready(),
        .rx_buf_fifo_din(rx_fifo_din),
        .rx_buf_fifo_wen(rx_fifo_wen),
        .rx_buf_fifo_full(rx_fifo_full),
        .s_axis_tx_byte_data(),
        .s_axis_tx_byte_valid(),
        .s_axis_tx_byte_ready(),
        .tx_buf_fifo_dout(tx_fifo_dout),
        .tx_buf_fifo_empty(tx_fifo_empty),
        .tx_buf_fifo_almost_empty(),
        .tx_buf_fifo_ren(tx_fifo_ren),
        .rx_err(rx_err),
        .tx_idle(tx_idle),
        .rx_idle(rx_idle),
        .tx_done(tx_done),
        .rx_done(rx_done)
    );

    /*
    寄存器区->
    偏移量  |    含义                     |   读写特性    |        备注
    0x00    0:发送fifo是否满                    R
            1:发送fifo写使能                    W         发送fifo写使能取上升沿
            9~2:发送fifo写数据                  W
            10:接收fifo是否空                   R
            11:接收fifo读使能                   W         接收fifo读使能取上升沿
            19~12:接收fifo读数据                R
    0x04    0:UART全局中断使能                  W
            1:UART发送达到规定字节数中断使能     W
            2:UART发送IDLE中断使能              W
            3:UART接收达到规定字节数中断使能     W
            4:UART接收IDLE中断使能              W
            5:UART接收FIFO溢出中断使能          W
            16:UART中断标志                    RWC      请在中断服务函数中清除中断标志
            21~17:UART中断状态                  R
    0x08    15~0:UART发送中断字节数阈值         W               注意要减1
            31~16:UART发送中断IDLE周期数阈值    W               注意要减2
    0x0A    15~0:UART接收中断字节数阈值         W               注意要减1
            31~16:UART接收中断IDLE周期数阈值    W               注意要减2
    */
    // 控制/状态寄存器
    reg[31:0] uart_fifo_cs;
    reg[31:0] uart_itr_status_en;
    reg[31:0] uart_tx_itr_th;
    reg[31:0] uart_rx_itr_th;
    
    reg[15:0] tx_bytes_n_th_sub1_regs; // UART发送中断字节数阈值-1
    reg[15:0] rx_bytes_n_th_sub1_regs; // UART接收中断字节数阈值-1
    reg tx_bytes_n_th_eq0_reg; // UART发送中断字节数阈值等于0(标志)
    reg rx_bytes_n_th_eq0_reg; // UART接收中断字节数阈值等于0(标志)
    
    reg tx_fifo_wen_d;
    reg rx_fifo_ren_d;
    
    assign tx_fifo_wen = uart_fifo_cs[1] & (~tx_fifo_wen_d); // 发送fifo写使能取上升沿
    assign tx_fifo_din = uart_fifo_cs[9:2];
    assign rx_fifo_ren = uart_fifo_cs[11] & (~rx_fifo_ren_d); // 接收fifo读使能取上升沿
    
    assign {uart_itr_en, uart_global_itr_en} = uart_itr_status_en[5:0];
    assign uart_itr_flag = uart_itr_status_en[16];
    assign {tx_idle_n_th, tx_bytes_n_th} = uart_tx_itr_th;
    assign {rx_idle_n_th, rx_bytes_n_th} = uart_rx_itr_th;
    
    assign {tx_bytes_n_th_sub1, rx_bytes_n_th_sub1} = {tx_bytes_n_th_sub1_regs, rx_bytes_n_th_sub1_regs};
    assign {tx_bytes_n_th_eq0, rx_bytes_n_th_eq0} = {tx_bytes_n_th_eq0_reg, rx_bytes_n_th_eq0_reg};
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            {tx_fifo_wen_d, rx_fifo_ren_d} <= 2'b00;
        else
            # simulation_delay {tx_fifo_wen_d, rx_fifo_ren_d} <= {uart_fifo_cs[1], uart_fifo_cs[11]};
    end
    
    // APB写寄存器
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
        begin
            {uart_fifo_cs[11], uart_fifo_cs[9:1]} <= {1'b0, 9'd0};
            {uart_itr_status_en[16], uart_itr_status_en[5:0]} <= {1'b0, 6'd0};
            uart_tx_itr_th <= {16'd100, 16'd1};
            uart_rx_itr_th <= {16'd100, 16'd1};
        end
        else if(psel & pwrite & penable)
        begin
            # simulation_delay;
            
            case(paddr[3:2])
                2'd0: {uart_fifo_cs[11], uart_fifo_cs[9:1]} <= {pwdata[11], pwdata[9:1]}; // 接收fifo读使能, 发送fifo写数据, 发送fifo写使能
                2'd1: {uart_itr_status_en[16], uart_itr_status_en[5:0]} <= {1'b0, pwdata[5:0]}; // UART总中断标志, UART中断使能
                2'd2: uart_tx_itr_th <= pwdata; // UART发送中断IDLE周期数阈值, UART发送中断字节数阈值
                2'd3: uart_rx_itr_th <= pwdata; // UART接收中断IDLE周期数阈值, UART接收中断字节数阈值
            endcase
        end
        else
        begin
            # simulation_delay;
            
            if(~uart_itr_status_en[16])
                uart_itr_status_en[16] <= uart_org_itr_pulse; // UART总中断标志
        end
    end
    
    // UART发送中断字节数阈值-1
    // UART接收中断字节数阈值-1
    // UART发送中断字节数阈值等于0(标志)
    // UART接收中断字节数阈值等于0(标志)
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
        begin
            tx_bytes_n_th_eq0_reg <= 1'b1;
            tx_bytes_n_th_sub1_regs <= 16'hffff;
            rx_bytes_n_th_eq0_reg <= 1'b1;
            rx_bytes_n_th_sub1_regs <= 16'hffff;
        end
        else if(psel & pwrite & penable)
        begin
            # simulation_delay;
            
            if(paddr[3:2] == 2)
            begin
                tx_bytes_n_th_eq0_reg <= pwdata[15:0] == 16'd0;
                tx_bytes_n_th_sub1_regs <= pwdata[15:0] - 16'd1;
            end
            
            if(paddr[3:2] == 3)
            begin
                rx_bytes_n_th_eq0_reg <= pwdata[15:0] == 16'd0;
                rx_bytes_n_th_sub1_regs <= pwdata[15:0] - 16'd1;
            end
        end
    end
    
    // 子中断标志向量
    always @(posedge clk)
    begin
        if(uart_org_itr_pulse_d)
            # simulation_delay uart_itr_status_en[21:17] <= uart_itr_mask_d; // UART子中断标志
    end
    
    // APB读寄存器
    reg[31:0] prdata_out_regs;
    
	generate
		if(simulation_delay == 0)
		begin
			always @(posedge clk)
			begin
				if(psel & (~pwrite))
				begin
					# simulation_delay;
					
					case(paddr[3:2])
						2'd0:
						begin
							prdata_out_regs[0] <= tx_fifo_full; // 发送fifo是否满
							prdata_out_regs[10] <= rx_fifo_empty; // 接收fifo是否空
							prdata_out_regs[19:12] <= rx_fifo_dout; // 接收fifo读数据
							{prdata_out_regs[31:20], prdata_out_regs[11], prdata_out_regs[9:1]} <= 22'dx;
						end
						2'd1:
						begin
							prdata_out_regs[21:16] <= uart_itr_status_en[21:16];
							{prdata_out_regs[31:22], prdata_out_regs[15:0]} <= 26'dx;
						end
						default: prdata_out_regs <= 32'dx;
					endcase
				end
			end
		end
		else
		begin
			always @(posedge clk)
			begin
				if(psel & (~pwrite))
				begin
					# simulation_delay;
					
					case(paddr[3:2])
						2'd0:
						begin
							prdata_out_regs[0] <= tx_fifo_full; // 发送fifo是否满
							prdata_out_regs[10] <= rx_fifo_empty; // 接收fifo是否空
							prdata_out_regs[19:12] <= rx_fifo_dout; // 接收fifo读数据
							{prdata_out_regs[31:20], prdata_out_regs[11], prdata_out_regs[9:1]} <= 22'd0;
						end
						2'd1:
						begin
							prdata_out_regs[21:16] <= uart_itr_status_en[21:16];
							{prdata_out_regs[31:22], prdata_out_regs[15:0]} <= 26'd0;
						end
						default: prdata_out_regs <= 32'd0;
					endcase
				end
			end
		end
	endgenerate
    
    /** APB从机接口 **/
    assign pready_out = 1'b1;
    assign prdata_out = prdata_out_regs;
    assign pslverr_out = 1'b0;

endmodule
