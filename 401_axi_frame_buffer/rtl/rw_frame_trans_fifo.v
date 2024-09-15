`timescale 1ns / 1ps
/********************************************************************
��ģ��: ֡��д��������fifo

����: 
���ڼĴ�����fifo
λ�� = 1
��� = axi_rwaddr_outstanding
FWFT = true

ע�⣺
��

Э��:
FIFO READ/WRITE

����: �¼�ҫ
����: 2024/05/08
********************************************************************/


module rw_frame_trans_fifo #(
    parameter integer axi_rwaddr_outstanding = 2, // AXI��д��ַ�������(1 | 2 | 4 | 8 | 16)
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // fifoд�˿�
    input wire rw_frame_trans_fifo_wen,
    output wire rw_frame_trans_fifo_full,
    input wire rw_frame_trans_fifo_din, // ��ǰ�Ƿ�֡�����1�δ���
    // fifo���˿�
    input wire rw_frame_trans_fifo_ren,
    output wire rw_frame_trans_fifo_empty,
    output wire rw_frame_trans_fifo_dout // ��ǰ�Ƿ�֡�����1�δ���
);

    generate
        if(axi_rwaddr_outstanding > 1)
        begin
            fifo_based_on_regs #(
                .fwft_mode("true"),
                .fifo_depth(axi_rwaddr_outstanding),
                .fifo_data_width(1),
                .almost_full_th(),
                .almost_empty_th(),
                .simulation_delay(simulation_delay)
            )fifo_based_on_regs_u(
                .clk(clk),
                .rst_n(rst_n),
                .fifo_wen(rw_frame_trans_fifo_wen),
                .fifo_din(rw_frame_trans_fifo_din),
                .fifo_full(rw_frame_trans_fifo_full),
                .fifo_ren(rw_frame_trans_fifo_ren),
                .fifo_dout(rw_frame_trans_fifo_dout),
                .fifo_empty(rw_frame_trans_fifo_empty)
            );
        end
        else
        begin
            reg rw_frame_trans_fifo_buf;
            reg rw_frame_trans_fifo_full_reg;
            reg rw_frame_trans_fifo_empty_reg;
            
            assign rw_frame_trans_fifo_full = rw_frame_trans_fifo_full_reg;
            assign rw_frame_trans_fifo_empty = rw_frame_trans_fifo_empty_reg;
            assign rw_frame_trans_fifo_dout = rw_frame_trans_fifo_buf;
            
            always @(posedge clk)
            begin
                if(rw_frame_trans_fifo_wen & (~rw_frame_trans_fifo_full))
                    # simulation_delay rw_frame_trans_fifo_buf <= rw_frame_trans_fifo_din;
            end
            
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rw_frame_trans_fifo_full_reg <= 1'b0;
                else
                    # simulation_delay rw_frame_trans_fifo_full_reg <= rw_frame_trans_fifo_full_reg ? (~rw_frame_trans_fifo_ren):rw_frame_trans_fifo_wen;
            end
            
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rw_frame_trans_fifo_empty_reg <= 1'b1;
                else
                    # simulation_delay rw_frame_trans_fifo_empty_reg <= rw_frame_trans_fifo_empty_reg ? (~rw_frame_trans_fifo_wen):rw_frame_trans_fifo_ren;
            end
        end
    endgenerate
    
endmodule
