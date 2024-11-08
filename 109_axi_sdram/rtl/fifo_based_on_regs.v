`timescale 1ns / 1ps
/********************************************************************
��ģ��: ���ڼĴ���Ƭ��ͬ��fifo

����: 
������ͬ��fifo
���ڼĴ���Ƭ
֧��first word fall through����(READ LA = 0)
��ѡ�Ĺ̶���ֵ����/�����ź�

ע�⣺
�����źŵ��洢���� >= almost_full_thʱ��Ч
�����źŵ��洢���� <= almost_empty_thʱ��Ч
almost_full_th��almost_empty_th������[1, fifo_depth-1]��Χ��
������FWFT����ʱ, fifo_dout�ǼĴ������

Э��:
FIFO READ/WRITE

����: �¼�ҫ
����: 2024/11/07
********************************************************************/


module fifo_based_on_regs #(
    parameter fwft_mode = "true", // �Ƿ�����first word fall through����
    parameter integer fifo_depth = 4, // fifo���(�����ڷ�Χ[2, 8]��)
    parameter integer fifo_data_width = 32, // fifoλ��
    parameter integer almost_full_th = 3, // fifo������ֵ
    parameter integer almost_empty_th = 1, // fifo������ֵ
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
	
    // ����bit_depth�������Чλ���(��λ��-1)
    function integer clogb2(input integer bit_depth);
    begin
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
    end
    endfunction
    
    /** ������־�ʹ洢���� **/
	reg[clogb2(fifo_depth):0] data_cnt_regs;
	wire[clogb2(fifo_depth):0] data_cnt_nxt;
    reg fifo_empty_reg;
    reg fifo_full_reg;
    reg fifo_almost_empty_reg;
    reg fifo_almost_full_reg;
    reg fifo_empty_n_reg;
    reg fifo_full_n_reg;
    reg fifo_almost_empty_n_reg;
    reg fifo_almost_full_n_reg;
	
	assign fifo_full = fifo_full_reg;
	assign fifo_full_n = fifo_full_n_reg;
	assign fifo_almost_full = fifo_almost_full_reg;
	assign fifo_almost_full_n = fifo_almost_full_n_reg;
	assign fifo_empty = fifo_empty_reg;
	assign fifo_empty_n = fifo_empty_n_reg;
	assign fifo_almost_empty = fifo_almost_empty_reg;
	assign fifo_almost_empty_n = fifo_almost_empty_n_reg;
	assign data_cnt = data_cnt_regs;
	
	assign data_cnt_nxt = (fifo_wen & fifo_full_n_reg) ? (data_cnt_regs + 1):(data_cnt_regs - 1);
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			data_cnt_regs <= 0;
		else if((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg))
			data_cnt_regs <= # simulation_delay data_cnt_nxt;
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fifo_empty_reg <= 1'b1;
		else if((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg))
			// (fifo_wen & fifo_full_n_reg) ? 1'b0:(data_cnt_regs == 1)
			fifo_empty_reg <= # simulation_delay (~(fifo_wen & fifo_full_n_reg)) & (data_cnt_regs == 1);
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fifo_empty_n_reg <= 1'b0;
		else if((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg))
			// (fifo_wen & fifo_full_n_reg) ? 1'b1:(data_cnt_regs != 1)
			fifo_empty_n_reg <= # simulation_delay (fifo_wen & fifo_full_n_reg) | (data_cnt_regs != 1);
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fifo_full_reg <= 1'b0;
		else if((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg))
			// (fifo_ren & fifo_empty_n_reg) ? 1'b0:(data_cnt_regs == (fifo_depth - 1))
			fifo_full_reg <= # simulation_delay (~(fifo_ren & fifo_empty_n_reg)) & (data_cnt_regs == (fifo_depth - 1));
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fifo_full_n_reg <= 1'b1;
		else if((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg))
			// (fifo_ren & fifo_empty_n_reg) ? 1'b1:(data_cnt_regs != (fifo_depth - 1))
			fifo_full_n_reg <= # simulation_delay (fifo_ren & fifo_empty_n_reg) | (data_cnt_regs != (fifo_depth - 1));
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fifo_almost_empty_reg <= 1'b1;
		else if((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg))
			fifo_almost_empty_reg <= # simulation_delay data_cnt_nxt <= almost_empty_th;
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fifo_almost_empty_n_reg <= 1'b0;
		else if((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg))
			// ~(data_cnt_nxt <= almost_empty_th)
			fifo_almost_empty_n_reg <= # simulation_delay data_cnt_nxt > almost_empty_th;
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fifo_almost_full_reg <= 1'b0;
		else if((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg))
			fifo_almost_full_reg <= # simulation_delay data_cnt_nxt >= almost_full_th;
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fifo_almost_full_n_reg <= 1'b1;
		else if((fifo_wen & fifo_full_n_reg) ^ (fifo_ren & fifo_empty_n_reg))
			// ~(data_cnt_nxt >= almost_full_th)
			fifo_almost_full_n_reg <= # simulation_delay data_cnt_nxt < almost_full_th;
	end
    
    /** ��дָ�� **/
    reg[clogb2(fifo_depth-1):0] fifo_rptr;
    reg[clogb2(fifo_depth-1):0] fifo_wptr;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            fifo_rptr <= 0;
        else if(fifo_ren & fifo_empty_n_reg)
			// (fifo_rptr == (fifo_depth - 1)) ? 0:(fifo_rptr + 1)
			fifo_rptr <= # simulation_delay {(clogb2(fifo_depth-1)+1){fifo_rptr != (fifo_depth - 1)}} & (fifo_rptr + 1);
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            fifo_wptr <= 0;
        else if(fifo_wen & fifo_full_n_reg)
			// (fifo_wptr == (fifo_depth - 1)) ? 0:(fifo_wptr + 1)
			fifo_wptr <= # simulation_delay {(clogb2(fifo_depth-1)+1){fifo_wptr != (fifo_depth - 1)}} & (fifo_wptr + 1);
    end
    
    /** ��д���� **/
    (* ram_style="register" *) reg[fifo_data_width-1:0] fifo_regs[0:fifo_depth-1];
    reg[fifo_data_width-1:0] fifo_dout_regs;
    
    assign fifo_dout = (fwft_mode == "true") ? fifo_regs[fifo_rptr]:fifo_dout_regs;
    
    genvar fifo_regs_w_i;
    generate
        for(fifo_regs_w_i = 0;fifo_regs_w_i < fifo_depth;fifo_regs_w_i = fifo_regs_w_i + 1)
        begin
            always @(posedge clk)
            begin
                if(fifo_wen & fifo_full_n_reg & (fifo_wptr == fifo_regs_w_i))
					fifo_regs[fifo_regs_w_i] <= # simulation_delay fifo_din;
            end
        end
    endgenerate
    
	always @(posedge clk)
	begin
		if(fifo_ren & fifo_empty_n_reg)
			fifo_dout_regs <= # simulation_delay fifo_regs[fifo_rptr];
	end
    
endmodule

