`timescale 1ns / 1ps
/********************************************************************
本模块: AXIS寄存器片(核心)

描述:
s_payload -> (后向反馈的payload) -> 前向寄存器 -> m_payload
s_valid -> (后向反馈的valid) -> 前向寄存器 -> m_valid
s_ready <- 后向寄存器 <- (前向反馈的ready) <- m_ready

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/03/27
********************************************************************/


module axis_reg_slice_core #(
    parameter forward_registered = "false", // 是否使能前向寄存器
    parameter back_registered = "false", // 是否使能后向寄存器
    parameter payload_width = 32, // 负载位宽
    parameter real simulation_delay = 0 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,

    // 从机
    input wire[payload_width-1:0] s_payload,
    input wire s_valid,
    output wire s_ready,
    
    // 主机
    output wire[payload_width-1:0] m_payload,
    output wire m_valid,
    input wire m_ready
);

    generate
        if((forward_registered == "false") && (back_registered == "false"))
        begin
            // pass
            assign m_payload = s_payload;
            assign m_valid = s_valid;
            assign s_ready = m_ready;
        end
        else if((forward_registered == "true") && (back_registered == "false"))
        begin
            reg[payload_width-1:0] fwd_payload;
            reg fwd_valid;
            
            assign m_payload = fwd_payload;
            assign m_valid = fwd_valid;
            assign s_ready = (~m_valid) | m_ready;
            
            // 前向payload
            always @(posedge clk)
            begin
                if((~fwd_valid) | m_ready) 
                    # simulation_delay fwd_payload <= s_payload;
            end
            // 前向valid
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    fwd_valid <= 1'b0;
                else
                begin
                    if(s_valid)
                        # simulation_delay fwd_valid <= 1'b1;
                    else if(m_ready) // (~s_valid) & m_ready
                        # simulation_delay fwd_valid <= 1'b0;
                end 
            end
        end
        else if((forward_registered == "false") && (back_registered == "true"))
        begin
            reg[payload_width-1:0] bwd_payload;
            reg bwd_ready;
            
            assign m_payload = s_ready ? s_payload:bwd_payload;
            assign m_valid = (~s_ready) | s_valid;
            assign s_ready = bwd_ready;
            
            // 后向payload
            always @(posedge clk)
            begin
                if(s_ready)
                    # simulation_delay bwd_payload <= s_payload;
            end
            // 后向ready
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    bwd_ready <= 1'b1;
                else if(m_ready)
                    # simulation_delay bwd_ready <= 1'b1;
                else if(s_valid) // (~m_ready) & s_valid
                    # simulation_delay bwd_ready <= 1'b0;
            end
        end
        else
        begin
            reg[payload_width-1:0] fwd_payload;
            reg fwd_valid;
            wire fwd_ready_to_s;
            
            reg[payload_width-1:0] bwd_payload;
            wire[payload_width-1:0] bwd_payload_to_s;
            wire bwd_valid_to_s;
            reg bwd_ready;
            
            assign m_payload = fwd_payload;
            assign m_valid = fwd_valid;
            assign s_ready = bwd_ready;
            
            assign fwd_ready_to_s = (~fwd_valid) | m_ready; // 前向反馈给后向的ready
            assign bwd_payload_to_s = bwd_ready ? s_payload:bwd_payload; // 后向反馈给前向的payload
            assign bwd_valid_to_s = (~bwd_ready) | s_valid; // 后向反馈给前向的valid
            
            // 前向payload
            always @(posedge clk)
            begin
                if((~fwd_valid) | m_ready) 
                    # simulation_delay fwd_payload <= bwd_payload_to_s;
            end
            // 前向valid
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    fwd_valid <= 1'b0;
                else
                begin
                    if(bwd_valid_to_s)
                        # simulation_delay fwd_valid <= 1'b1;
                    else if(m_ready) // (~bwd_valid_to_s) & m_ready
                        # simulation_delay fwd_valid <= 1'b0;
                end 
            end
            
            // 后向payload
            always @(posedge clk)
            begin
                if(bwd_ready)
                    # simulation_delay bwd_payload <= s_payload;
            end
            // 后向ready
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    bwd_ready <= 1'b1;
                else if(fwd_ready_to_s)
                    # simulation_delay bwd_ready <= 1'b1;
                else if(s_valid) // (~fwd_ready_to_s) & s_valid
                    # simulation_delay bwd_ready <= 1'b0;
            end
        end
    endgenerate

endmodule
