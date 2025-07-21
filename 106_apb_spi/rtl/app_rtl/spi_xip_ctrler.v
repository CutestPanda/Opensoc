`timescale 1ns / 1ps
/********************************************************************
本模块: 片上执行SPI控制器

描述: 
片上执行SPI控制器(xip发送fifo写控制)
由"读flash首地址+字节数"生成spi传输: 读命令AXIS -> xip发送fifo写端口

注意：
本控制器与具体flash芯片的命令格式有关, 这里基于W25QXX芯片：
(1)标准SPI
    0x03
    地址[23:16]
    地址[15:8]
    地址[7:0]
    (N个读数据dummy)
(2)Dual SPI
    [0xBB]
    地址[23:16]
    地址[15:8]
    地址[7:0]
    0xAF
    (N个读数据dummy)
(3)Quad SPI
    [0xEB]
    地址[23:16]
    地址[15:8]
    地址[7:0]
    0xAF
    dummy
    dummy
    (N个读数据dummy)

协议:
AXIS MASTER/SLAVE
FIFO WRITE

作者: 陈家耀
日期: 2023/12/17
********************************************************************/


module spi_xip_ctrler #(
    parameter spi_type = "std", // SPI接口类型(标准->std 双口->dual 四口->quad)
    parameter real simulation_delay = 1 // 仿真延时
)(
    // AMBA总线时钟和复位
    input wire amba_clk,
    input wire amba_resetn,
    
    // 读命令AXIS从接口
    input wire[23:0] s_axis_data_addr, // 读flash首地址
    input wire[11:0] s_axis_user_len, // 读flash字节数-1
    input wire s_axis_valid,
    output wire s_axis_ready,
    
    // 使能片内执行
    input wire en_xip,
    // xip接收fifo满标志
    input wire xip_rev_fifo_full,
    
    // xip发送fifo写端口
    output wire xip_tx_fifo_wen,
    input wire xip_tx_fifo_full,
    output wire[7:0] xip_tx_fifo_din,
    output wire xip_tx_fifo_din_ss,
    output wire xip_tx_fifo_din_ignored,
    output wire xip_tx_fifo_din_last,
    output wire xip_tx_fifo_din_dire,
    output wire xip_tx_fifo_din_en_mul
);

    /** 常量 **/
    // flash读命令
    localparam FLASH_READ_CMD = (spi_type == "std")  ? 8'h03:
                                (spi_type == "dual") ? 8'hbb:
                                                        8'heb;
    // dummy数据
    localparam FLASH_DUMMY_DATA = 8'haf;
    // HPM命令
    localparam FLASH_HPM_CMD = 8'ha3;
    // 状态常量
    localparam STS_INIT = 3'b000; // 状态:初始化
    localparam STS_DELAY = 3'b001; // 状态:延迟
    localparam STS_IDLE_CMD = 3'b010; // 状态:空闲&发送命令
    localparam STS_ADDR = 3'b011; // 状态:发送地址
    localparam STS_DUMMY = 3'b100; // 状态:dummy
    localparam STS_DATA = 3'b101; // 状态:读数据
    // 上电等待周期数
    localparam integer power_on_delay_n = 2000;
    // flash设置高性能模式后延迟周期数
    localparam integer flash_hpm_delay_n = 1000;
    
    /** flash读命令生成状态机 **/
    reg[15:0] power_on_delay_cnt; // 上电等待(计数器)
    reg en_xip_stable; // 稳定的XIP使能
    reg[2:0] flash_cmd_status; // flash读命令生成状态
    reg[3:0] flash_init_cnt; // flash初始化计数器
    reg[15:0] flast_delay_cnt; // flash设置高性能模式后延迟计数器
    reg flash_hpm_set; // flash高性能模式设置完成(标志)
    reg read_instruction_omitted; // 省略读指令(标志)
    reg[2:0] dummy_cnt; // dummy计数器
    reg[23:0] flash_read_addr; // flash读地址
    reg[2:0] flash_send_raddr_cnt; // flash读地址生成(计数器)
    reg[11:0] flash_read_len; // flash读字节数-1
    reg flash_last_byte; // flash当前突发最后一个字节(标志)
    
    assign s_axis_ready = (flash_cmd_status == STS_IDLE_CMD) & en_xip_stable & (~xip_tx_fifo_full);
    
    generate
        if(spi_type == "std")
        begin
            assign xip_tx_fifo_wen = (flash_cmd_status == STS_IDLE_CMD) ? (s_axis_valid & en_xip_stable): // 状态:空闲&发送命令
                                         (flash_cmd_status == STS_DATA) ? (~xip_rev_fifo_full): // 状态:读数据
                                                                          1'b1; // 状态:发送地址
            assign xip_tx_fifo_din = (flash_cmd_status == STS_IDLE_CMD) ? FLASH_READ_CMD: // 状态:空闲&发送命令
                                                                          flash_read_addr[7:0]; // 状态:发送地址 | 读数据
            assign xip_tx_fifo_din_ss = (flash_cmd_status == STS_DATA) & flash_last_byte;
        end
        else
        begin
            assign xip_tx_fifo_wen = (flash_cmd_status == STS_INIT) ? en_xip_stable: // 状态:初始化
                                    (flash_cmd_status == STS_DELAY) ? 1'b0: // 状态:延迟
                                 (flash_cmd_status == STS_IDLE_CMD) ? (s_axis_valid & en_xip_stable & (~read_instruction_omitted)): // 状态:空闲&发送命令
                                     (flash_cmd_status == STS_DATA) ? (~xip_rev_fifo_full): // 状态:读数据
                                                                      1'b1; // 状态:发送地址 | dummy
            assign xip_tx_fifo_din = (flash_cmd_status == STS_INIT) ? FLASH_HPM_CMD: // 状态:初始化
                                 (flash_cmd_status == STS_IDLE_CMD) ? FLASH_READ_CMD: // 状态:空闲&发送命令
                                     (flash_cmd_status == STS_ADDR) ? flash_read_addr[7:0]: // 状态:发送地址
                                                                      FLASH_DUMMY_DATA; // 状态:延迟 | dummy | 读数据
            assign xip_tx_fifo_din_ss = (flash_cmd_status == STS_INIT) ? flash_init_cnt[3]: // 状态:初始化
                                        (flash_cmd_status == STS_DATA) ? flash_last_byte: // 状态:读数据
                                                                         1'b0; // 状态:延迟 | 空闲&发送命令 | 发送地址 | dummy
        end
    endgenerate
    
    assign xip_tx_fifo_din_ignored = flash_cmd_status != STS_DATA;
    assign xip_tx_fifo_din_last = flash_last_byte;
    // 1'b0->接收 1'b1->发送
    assign xip_tx_fifo_din_dire = (spi_type == "quad") ? (~((flash_cmd_status == STS_DATA) | ((flash_cmd_status == STS_DUMMY) & (~dummy_cnt[0])))):
                                                         (flash_cmd_status != STS_DATA);
    assign xip_tx_fifo_din_en_mul = (spi_type == "std") ? 1'b0:((flash_cmd_status != STS_IDLE_CMD) & (flash_cmd_status != STS_INIT));
    
    // 上电等待(计数器)
    always @(posedge amba_clk or negedge amba_resetn)
    begin
        if(~amba_resetn)
            power_on_delay_cnt <= 16'd0;
        else if(power_on_delay_cnt != (flash_hpm_delay_n - 1))
            # simulation_delay power_on_delay_cnt <= power_on_delay_cnt + 1;
    end
    // 稳定的XIP使能
    always @(posedge amba_clk or negedge amba_resetn)
    begin
        if(~amba_resetn)
            en_xip_stable <= 1'b0;
        else
            en_xip_stable <= en_xip & (power_on_delay_cnt == (flash_hpm_delay_n - 1));
    end
    
    // flash读命令生成状态
    generate
        if(spi_type == "std")
        begin // 标准SPI
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    flash_cmd_status <= STS_IDLE_CMD;
                else if(~xip_tx_fifo_full)
                begin
                    # simulation_delay;
                    
                    case(flash_cmd_status)
                        STS_IDLE_CMD: // 状态:空闲&发送命令
                            if(s_axis_valid & en_xip_stable)
                                flash_cmd_status <= STS_ADDR; // -> 状态:发送地址
                        STS_ADDR: // 状态:发送地址
                            if(flash_send_raddr_cnt[2])
                                flash_cmd_status <= STS_DATA; // -> 状态:读数据
                        STS_DATA: // 状态:读数据
                            if((~xip_rev_fifo_full) & flash_last_byte)
                                flash_cmd_status <= STS_IDLE_CMD; // -> 状态:空闲&发送命令
                        default:
                            flash_cmd_status <= STS_IDLE_CMD;
                    endcase
                end
            end
        end
        else
        begin // Dual/Quad SPI
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    flash_cmd_status <= STS_INIT;
                else if(~xip_tx_fifo_full)
                begin
                    # simulation_delay;
                    
                    case(flash_cmd_status)
                        STS_INIT: // 状态:初始化
                            if(en_xip_stable & flash_init_cnt[3])
                                flash_cmd_status <= STS_DELAY; // -> 状态:延迟
                        STS_DELAY: // 状态:延迟
                            if(flash_hpm_set)
                                flash_cmd_status <= STS_IDLE_CMD; // -> 状态:空闲&发送命令
                        STS_IDLE_CMD: // 状态:空闲&发送命令
                            if(en_xip_stable & s_axis_valid)
                                flash_cmd_status <= STS_ADDR; // -> 状态:发送地址
                        STS_ADDR: // 状态:发送地址
                            if(flash_send_raddr_cnt[2])
                                flash_cmd_status <= STS_DUMMY; // -> 状态:读数据
                        STS_DUMMY: // 状态:dummy
                            if((spi_type == "dual") | dummy_cnt[2])
                                flash_cmd_status <= STS_DATA; // -> 状态:读数据
                        STS_DATA: // 状态:读数据
                            if((~xip_rev_fifo_full) & flash_last_byte)
                                flash_cmd_status <= STS_IDLE_CMD; // -> 状态:空闲&发送命令
                        default:
                            flash_cmd_status <= STS_INIT;
                    endcase
                end
            end
        end
    endgenerate
    
    // flash初始化计数器
    always @(posedge amba_clk or negedge amba_resetn)
    begin
        if(~amba_resetn)
            flash_init_cnt <= 4'b0001;
        else if((flash_cmd_status == STS_INIT) & en_xip_stable)
            # simulation_delay flash_init_cnt <= {flash_init_cnt[2:0], flash_init_cnt[3]};
    end
    // flash设置高性能模式后延迟计数器
    always @(posedge amba_clk or negedge amba_resetn)
    begin
        if(~amba_resetn)
            flast_delay_cnt <= 16'd0;
        else if(flash_cmd_status == STS_DELAY)
            # simulation_delay flast_delay_cnt <= flast_delay_cnt + 16'd1;
    end
    // flash高性能模式设置完成(标志)
    always @(posedge amba_clk or negedge amba_resetn)
    begin
        if(~amba_resetn)
            flash_hpm_set <= 1'b0;
        else if(~flash_hpm_set)
            # simulation_delay flash_hpm_set <= flast_delay_cnt == (flash_hpm_delay_n - 1);
    end
    
    // 省略读指令(标志)
    // dummy计数器
    generate
        // 省略读指令(标志)
        if(spi_type != "std")
        begin
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    read_instruction_omitted <= 1'b0;
                else if(~read_instruction_omitted)
                    # simulation_delay read_instruction_omitted <= s_axis_valid & s_axis_ready;
            end
        end
    
        // dummy计数器
        if(spi_type == "quad")
        begin
            always @(posedge amba_clk or negedge amba_resetn)
            begin
                if(~amba_resetn)
                    dummy_cnt <= 3'b001;
                else if((flash_cmd_status == STS_DUMMY) & (~xip_tx_fifo_full))
                    # simulation_delay dummy_cnt <= {dummy_cnt[1:0], dummy_cnt[2]};
            end
        end
    endgenerate
    
    // flash读地址
    always @(posedge amba_clk)
    begin
        # simulation_delay;
        
        if(s_axis_valid & s_axis_ready)
            flash_read_addr <= {s_axis_data_addr[7:0], s_axis_data_addr[15:8], s_axis_data_addr[23:16]};
        else if((flash_cmd_status == STS_ADDR) & (~xip_tx_fifo_full))
            flash_read_addr <= {8'dx, flash_read_addr[23:8]};
    end
    // flash读地址生成(计数器)
    always @(posedge amba_clk or negedge amba_resetn)
    begin
        if(~amba_resetn)
            flash_send_raddr_cnt <= 2'b001;
        else if((flash_cmd_status == STS_ADDR) & (~xip_tx_fifo_full))
            flash_send_raddr_cnt <= {flash_send_raddr_cnt[1:0], flash_send_raddr_cnt[2]};
    end
    
    // flash读字节数-1
    // flash当前突发最后一个字节(标志)
    always @(posedge amba_clk)
    begin
        # simulation_delay;
        
        if(s_axis_valid & s_axis_ready) // 载入
        begin
            flash_read_len <= s_axis_user_len;
            flash_last_byte <= s_axis_user_len == 12'd0;
        end
        else if((flash_cmd_status == STS_DATA) & (~xip_rev_fifo_full) & (~xip_tx_fifo_full)) // 更新
        begin
            flash_read_len <= flash_read_len - 12'd1;
            flash_last_byte <= flash_read_len == 12'd1;
        end
    end

endmodule
