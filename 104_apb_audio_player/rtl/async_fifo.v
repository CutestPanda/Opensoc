`timescale 1ns / 1ps
/********************************************************************
��ģ��: �첽fifo������

����: 
ʹ�ü�˫��RAM��Ϊfifo�洢��

ע�⣺
��˫��RAM�Ķ��ӳ� = 1clk
��֧�ֱ�׼ģʽ

Э��:
FIFO READ/WRITE
MEM READ/WRITE

����: �¼�ҫ
����: 2024/05/09
********************************************************************/


module async_fifo #(
    parameter integer depth = 32, // fifo���(16 | 32 | 64 | ...)
    parameter integer data_width = 32, // ����λ��
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk_wt,
    input wire rst_n_wt,
    input wire clk_rd,
    input wire rst_n_rd,
    
    // mem
    output wire ram_clk_w,
    output wire[clogb2(depth-1):0] ram_waddr,
    output wire ram_wen,
    output wire[data_width-1:0] ram_din,
    output wire ram_clk_r,
    output wire ram_ren,
    output wire[clogb2(depth-1):0] ram_raddr,
    input wire[data_width-1:0] ram_dout,
    
    // fifo
    input wire fifo_wen,
    output wire fifo_full,
    input wire[data_width-1:0] fifo_din,
    input wire fifo_ren,
    output wire fifo_empty,
    output wire[data_width-1:0] fifo_dout
);
    
    // ����log2(bit_depth)               
    function integer clogb2 (input integer bit_depth);
        integer temp;
    begin
        temp = bit_depth;
        for(clogb2 = -1;temp > 0;clogb2 = clogb2 + 1)
            temp = temp >> 1;
    end
    endfunction
    
    /** ���� **/
    localparam integer rw_ptr_width = clogb2(depth-1) + 2; // ��дָ��λ��
    
    /** д�˿� **/
    reg[rw_ptr_width-1:0] wptr_bin_at_w; // λ��д�˿ڵ�дָ��(��������)
    reg[rw_ptr_width-1:0] wptr_add1_bin_at_w; // λ��д�˿ڵ�дָ��+1(��������)
    wire[rw_ptr_width-1:0] wptr_gray_at_w_cvt_cmb; // λ��д�˿ڵ�дָ��ĸ�����ת������߼�
    wire[rw_ptr_width-1:0] wptr_add1_gray_at_w_cvt_cmb; // λ��д�˿ڵ�дָ��+1�ĸ�����ת������߼�
    reg[rw_ptr_width-1:0] wptr_gray_at_w; // λ��д�˿ڵ�дָ��(������)
    wire[rw_ptr_width-1:0] rptr_gray_at_w; // ͬ����д�˿ڵĶ�ָ��(������)
    reg fifo_full_reg; // fifo����־
    
    assign ram_clk_w = clk_wt;
    assign ram_waddr = wptr_bin_at_w[rw_ptr_width-2:0];
    assign ram_wen = fifo_wen & (~fifo_full);
    assign ram_din = fifo_din;
    
    assign fifo_full = fifo_full_reg;
    
    assign wptr_gray_at_w_cvt_cmb = {1'b0, wptr_bin_at_w[rw_ptr_width-1:1]} ^ wptr_bin_at_w;
    assign wptr_add1_gray_at_w_cvt_cmb = {1'b0, wptr_add1_bin_at_w[rw_ptr_width-1:1]} ^ wptr_add1_bin_at_w;
    
    // λ��д�˿ڵ�дָ��(��������)
    always @(posedge clk_wt or negedge rst_n_wt)
    begin
        if(~rst_n_wt)
            wptr_bin_at_w <= 0;
        else if(fifo_wen & (~fifo_full))
            # simulation_delay wptr_bin_at_w <= wptr_bin_at_w + 1;
    end
    // λ��д�˿ڵ�дָ��+1(��������)
    always @(posedge clk_wt or negedge rst_n_wt)
    begin
        if(~rst_n_wt)
            wptr_add1_bin_at_w <= 1;
        else if(fifo_wen & (~fifo_full))
            # simulation_delay wptr_add1_bin_at_w <= wptr_add1_bin_at_w + 1;
    end
    // λ��д�˿ڵ�дָ��(������)
    always @(posedge clk_wt or negedge rst_n_wt)
    begin
        if(~rst_n_wt)
            wptr_gray_at_w <= 0;
        else
            # simulation_delay wptr_gray_at_w <= wptr_gray_at_w_cvt_cmb;
    end
    
    // fifo����־
    // ͬ����д�˿ڵĶ�ָ���ͺ󼸸�clk, �����"����"
    always @(posedge clk_wt or negedge rst_n_wt)
    begin
        if(~rst_n_wt)
            fifo_full_reg <= 1'b0;
        else
            # simulation_delay fifo_full_reg <= ((fifo_wen & (~fifo_full)) ? wptr_add1_gray_at_w_cvt_cmb:wptr_gray_at_w_cvt_cmb) == 
                {~rptr_gray_at_w[rw_ptr_width-1:rw_ptr_width-2], rptr_gray_at_w[rw_ptr_width-3:0]};
    end
    
    /** ���˿� **/
    reg[rw_ptr_width-1:0] rptr_bin_at_r; // λ�ڶ��˿ڵĶ�ָ��(��������)
    reg[rw_ptr_width-1:0] rptr_add1_bin_at_r; // λ�ڶ��˿ڵĶ�ָ��+1(��������)
    wire[rw_ptr_width-1:0] rptr_gray_at_r_cvt_cmb; // λ�ڶ��˿ڵĶ�ָ��ĸ�����ת������߼�
    wire[rw_ptr_width-1:0] rptr_add1_gray_at_r_cvt_cmb; // λ�ڶ��˿ڵĶ�ָ��+1�ĸ�����ת������߼�
    reg[rw_ptr_width-1:0] rptr_gray_at_r; // λ�ڶ��˿ڵĶ�ָ��(������)
    wire[rw_ptr_width-1:0] wptr_gray_at_r; // ͬ�������˿ڵ�дָ��(������)
    reg fifo_empty_reg; // fifo�ձ�־
    
    assign ram_clk_r = clk_rd;
    assign ram_ren = fifo_ren & (~fifo_empty);
    assign ram_raddr = rptr_bin_at_r[rw_ptr_width-2:0];
    
    assign fifo_empty = fifo_empty_reg;
    assign fifo_dout = ram_dout;
    
    assign rptr_gray_at_r_cvt_cmb = {1'b0, rptr_bin_at_r[rw_ptr_width-1:1]} ^ rptr_bin_at_r;
    assign rptr_add1_gray_at_r_cvt_cmb = {1'b0, rptr_add1_bin_at_r[rw_ptr_width-1:1]} ^ rptr_add1_bin_at_r;
    
    // λ�ڶ��˿ڵĶ�ָ��(��������)
    always @(posedge clk_rd or negedge rst_n_rd)
    begin
        if(~rst_n_rd)
            rptr_bin_at_r <= 0;
        else if(fifo_ren & (~fifo_empty))
            # simulation_delay rptr_bin_at_r <= rptr_bin_at_r + 1;
    end
    // λ�ڶ��˿ڵĶ�ָ��+1(��������)
    always @(posedge clk_rd or negedge rst_n_rd)
    begin
        if(~rst_n_rd)
            rptr_add1_bin_at_r <= 1;
        else if(fifo_ren & (~fifo_empty))
            # simulation_delay rptr_add1_bin_at_r <= rptr_add1_bin_at_r + 1;
    end
    // λ�ڶ��˿ڵĶ�ָ��(������)
    always @(posedge clk_rd or negedge rst_n_rd)
    begin
        if(~rst_n_rd)
            rptr_gray_at_r <= 0;
        else
            # simulation_delay rptr_gray_at_r <= rptr_gray_at_r_cvt_cmb;
    end
    
    // fifo�ձ�־
    // ͬ�������˿ڵ�дָ���ͺ󼸸�clk, �����"���"
    always @(posedge clk_rd or negedge rst_n_rd)
    begin
        if(~rst_n_rd)
            fifo_empty_reg <= 1'b1;
        else
            # simulation_delay fifo_empty_reg <= ((fifo_ren & (~fifo_empty)) ? rptr_add1_gray_at_r_cvt_cmb:rptr_gray_at_r_cvt_cmb) == 
                wptr_gray_at_r;
    end
    
    /** ��дָ��ͬ�� **/
    // ͬ����ָ��
    reg[rw_ptr_width-1:0] rptr_gray_at_w_p2;
    reg[rw_ptr_width-1:0] rptr_gray_at_w_p1;
    // ͬ��дָ��
    reg[rw_ptr_width-1:0] wptr_gray_at_r_p2;
    reg[rw_ptr_width-1:0] wptr_gray_at_r_p1;
    
    assign rptr_gray_at_w = rptr_gray_at_w_p1;
    assign wptr_gray_at_r = wptr_gray_at_r_p1;
    
    // ��дʱ����ͬ�����˿ڵĶ�ָ��
    always @(posedge clk_wt or negedge rst_n_wt)
    begin
        if(~rst_n_wt)
        begin
            rptr_gray_at_w_p2 <= 0;
            rptr_gray_at_w_p1 <= 0;
        end
        else
            # simulation_delay {rptr_gray_at_w_p1, rptr_gray_at_w_p2} <= {rptr_gray_at_w_p2, rptr_gray_at_r};
    end
    
    // �ö�ʱ����ͬ��д�˿ڵ�дָ��
    always @(posedge clk_rd or negedge rst_n_rd)
    begin
        if(~rst_n_rd)
        begin
            wptr_gray_at_r_p2 <= 0;
            wptr_gray_at_r_p1 <= 0;
        end
        else
            # simulation_delay {wptr_gray_at_r_p1, wptr_gray_at_r_p2} <= {wptr_gray_at_r_p2, wptr_gray_at_w};
    end
    
endmodule
