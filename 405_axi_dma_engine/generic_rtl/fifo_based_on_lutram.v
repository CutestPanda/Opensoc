`timescale 1ns / 1ps
/********************************************************************
��ģ��: ����lutram��ͬ��fifo

����: 
ȫ��ˮ�ĸ�����ͬ��fifo
����lutram
֧��first word fall through����(READ LA = 0)
��ѡ�Ĺ̶���ֵ����/�����ź�

ע�⣺
�����źŵ��洢���� >= almost_full_thʱ��Ч
�����źŵ��洢���� <= almost_empty_thʱ��Ч
almost_full_th��almost_empty_th������[1, fifo_depth-1]��Χ��

Э��:
FIFO WRITE/READ

����: �¼�ҫ
����: 2023/10/13
********************************************************************/


module fifo_based_on_lutram #(
    parameter fwft_mode = "true", // �Ƿ�����first word fall through����
    parameter integer fifo_depth = 32, // fifo���(����Ϊ2|4|8|16|...)
    parameter integer fifo_data_width = 32, // fifoλ��
    parameter integer almost_full_th = 20, // fifo������ֵ
    parameter integer almost_empty_th = 5, // fifo������ֵ
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // FIFO WRITE(fifoд�˿�)
    input wire fifo_wen,
    input wire[fifo_data_width-1:0] fifo_din,
    output wire fifo_full,
    output wire fifo_full_n,
    output wire fifo_almost_full,
    output wire fifo_almost_full_n,
    
    // FIFO READ(fifo���˿�)
    input wire fifo_ren,
    output wire[fifo_data_width-1:0] fifo_dout,
    output wire fifo_empty,
    output wire fifo_empty_n,
    output wire fifo_almost_empty,
    output wire fifo_almost_empty_n,
    
    // �洢����
    output wire[clogb2(fifo_depth):0] data_cnt
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
    localparam integer use_cnt_th = 8;
    
    /** ������־�ʹ洢���� **/
    reg fifo_empty_reg;
    reg fifo_full_reg;
    reg fifo_almost_empty_reg;
    reg fifo_almost_full_reg;
    reg fifo_empty_n_reg;
    reg fifo_full_n_reg;
    reg fifo_almost_empty_n_reg;
    reg fifo_almost_full_n_reg;
    reg[clogb2(fifo_depth):0] data_cnt_regs;
    reg[fifo_depth:0] data_cnt_onehot_regs;
    
    assign {fifo_empty, fifo_full} = {fifo_empty_reg, fifo_full_reg};
    assign {fifo_empty_n, fifo_full_n} = {fifo_empty_n_reg, fifo_full_n_reg};
    assign {fifo_almost_empty, fifo_almost_full} = {fifo_almost_empty_reg, fifo_almost_full_reg};
    assign {fifo_almost_empty_n, fifo_almost_full_n} = {fifo_almost_empty_n_reg, fifo_almost_full_n_reg};
    assign data_cnt = data_cnt_regs;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
        begin
            fifo_empty_reg <= 1'b1;
            fifo_empty_n_reg <= 1'b0;
            fifo_full_reg <= 1'b0;
            fifo_full_n_reg <= 1'b1;
            fifo_almost_empty_reg <= 1'b1;
            fifo_almost_empty_n_reg <= 1'b0;
            fifo_almost_full_reg <= 1'b0;
            fifo_almost_full_n_reg <= 1'b1;
            
            data_cnt_regs <= 0;
            data_cnt_onehot_regs <= 1;
        end
        else if((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg))
		begin
            # simulation_delay;
			
            if(fifo_wen & fifo_full_n_reg)
            begin
                // fifo��������1��
                fifo_empty_reg <= 1'b0;
                fifo_empty_n_reg <= 1'b1;
                fifo_full_reg <= (fifo_depth >= use_cnt_th) ? data_cnt_regs == fifo_depth - 1:data_cnt_onehot_regs[fifo_depth-1];
                fifo_full_n_reg <= (fifo_depth >= use_cnt_th) ? data_cnt_regs != fifo_depth - 1:(~data_cnt_onehot_regs[fifo_depth-1]);
                fifo_almost_empty_reg <= (data_cnt_regs <= almost_empty_th - 1);
                fifo_almost_empty_n_reg <= ~(data_cnt_regs <= almost_empty_th - 1);
                fifo_almost_full_reg <= (data_cnt_regs >= almost_full_th - 1);
                fifo_almost_full_n_reg <= ~(data_cnt_regs >= almost_full_th - 1);
                
                data_cnt_regs <= data_cnt_regs + 1;
                data_cnt_onehot_regs <= {data_cnt_onehot_regs[fifo_depth-1:0], 1'b0}; // ����
            end
            else
            begin
                // fifo���ݼ���1��
                fifo_empty_reg <= (fifo_depth >= use_cnt_th) ? data_cnt_regs == 1:data_cnt_onehot_regs[1];
                fifo_empty_n_reg <= (fifo_depth >= use_cnt_th) ? data_cnt_regs != 1:(~data_cnt_onehot_regs[1]);
                fifo_full_reg <= 1'b0;
                fifo_full_n_reg <= 1'b1;
                fifo_almost_empty_reg <= (data_cnt_regs <= almost_empty_th + 1);
                fifo_almost_empty_n_reg <= ~(data_cnt_regs <= almost_empty_th + 1);
                fifo_almost_full_reg <= (data_cnt_regs >= almost_full_th + 1);
                fifo_almost_full_n_reg <= ~(data_cnt_regs >= almost_full_th + 1);
                
                data_cnt_regs <= data_cnt_regs - 1;
                data_cnt_onehot_regs <= {1'b0, data_cnt_onehot_regs[fifo_depth:1]}; // ����
            end
        end
    end
    
    /** ��дָ�� **/
    reg[clogb2(fifo_depth-1):0] fifo_rptr;
    reg[clogb2(fifo_depth-1):0] fifo_rptr_add1;
    reg[clogb2(fifo_depth-1):0] fifo_wptr;
    reg[fifo_depth-1:0] fifo_wptr_onehot;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            fifo_rptr <= 0;
        else if(fifo_ren & fifo_empty_n_reg)
            #simulation_delay fifo_rptr <= fifo_rptr + 1;
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            fifo_rptr_add1 <= 1;
        else if(fifo_ren & fifo_empty_n_reg)
            #simulation_delay fifo_rptr_add1 <= fifo_rptr_add1 + 1;
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            fifo_wptr <= 0;
        else if(fifo_wen & fifo_full_n_reg)
            #simulation_delay fifo_wptr <= fifo_wptr + 1;
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            fifo_wptr_onehot <= 1;
        else if(fifo_wen & fifo_full_n_reg)
            #simulation_delay fifo_wptr_onehot <= {fifo_wptr_onehot[fifo_depth-2:0], fifo_wptr_onehot[fifo_depth-1]}; // ѭ������
    end
    
    /** ��д���� **/
    (* ram_style="distributed" *) reg[fifo_data_width-1:0] fifo_regs[fifo_depth-1:0];
    reg[fifo_data_width-1:0] fifo_dout_regs;
    
    assign fifo_dout = fifo_dout_regs;
    
    always @(posedge clk)
    begin
        if(fifo_wen & fifo_full_n_reg)
            #simulation_delay fifo_regs[fifo_wptr] <= fifo_din;
    end
    
    generate
        if(fwft_mode == "true")
        begin
            always @(posedge clk)
            begin
                if({fifo_empty_n_reg, fifo_ren} != 2'b10)
                    #simulation_delay fifo_dout_regs <= fifo_empty_n_reg & (~(fifo_wen & ((fifo_depth >= use_cnt_th) ? data_cnt_regs == 1:data_cnt_onehot_regs[1]))) ?
                        fifo_regs[fifo_rptr_add1]:fifo_din;
            end
        end
        else
        begin
            always @(posedge clk)
            begin
                if(fifo_ren & fifo_empty_n_reg)
                    #simulation_delay fifo_dout_regs <= fifo_regs[fifo_rptr];
            end
        end
    endgenerate

endmodule

