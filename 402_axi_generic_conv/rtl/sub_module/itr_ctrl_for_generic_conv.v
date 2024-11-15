`timescale 1ns / 1ps
/********************************************************************
��ģ��: ͨ�þ�����㵥Ԫ���жϿ���ģ��

����:
�����ж����� -> 
	������������DMA���������
	д����������DMA���������
	���д����

ע�⣺
��

Э��:
��

����: �¼�ҫ
����: 2024/11/12
********************************************************************/


module itr_ctrl_for_generic_conv #(
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
	
	// �ж��¼�ָʾ
	input wire rd_req_dsc_dma_blk_done, // ������������DMA���������(ָʾ)
	input wire wt_req_dsc_dma_blk_done, // д����������DMA���������(ָʾ)
	input wire wt_req_fns, // ���д����(ָʾ)
	
	// ����ɵ�д�������
	input wire[3:0] to_set_wt_req_fns_n,
	input wire[31:0] wt_req_fns_n_set_v,
	output wire[31:0] wt_req_fns_n_cur_v,
	
	// �ж�ʹ��
	input wire en_wt_req_fns_itr, // �Ƿ�ʹ��д����������ж�
	
	// �ж���ֵ
	input wire[31:0] wt_req_itr_th, // д����������ж���ֵ
	
	// �ж�����
	output wire[2:0] itr_req
);
	
	reg rd_req_dsc_dma_blk_done_d;
	reg wt_req_dsc_dma_blk_done_d;
	reg[31:0] wt_req_fns_n; // ����ɵ�д�������
	wire[31:0] wt_req_fns_n_add1; // ����ɵ�д������� + 1
	reg wt_req_fns_itr_req; // д����ж�����
	reg wt_req_fns_d;
	
	assign wt_req_fns_n_cur_v = wt_req_fns_n;
	assign itr_req = {wt_req_fns_itr_req, wt_req_dsc_dma_blk_done_d, rd_req_dsc_dma_blk_done_d};
	
	assign wt_req_fns_n_add1 = wt_req_fns_n + 32'd1;
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rd_req_dsc_dma_blk_done_d <= 1'b0;
		else
			rd_req_dsc_dma_blk_done_d <= # simulation_delay rd_req_dsc_dma_blk_done;
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wt_req_dsc_dma_blk_done_d <= 1'b0;
		else
			wt_req_dsc_dma_blk_done_d <= # simulation_delay wt_req_dsc_dma_blk_done;
	end
	
	// ����ɵ�д�������
	genvar wt_req_fns_n_i;
	
	generate
		for(wt_req_fns_n_i = 0;wt_req_fns_n_i < 4;wt_req_fns_n_i = wt_req_fns_n_i + 1)
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					wt_req_fns_n[wt_req_fns_n_i*8+7:wt_req_fns_n_i*8] <= 8'd0;
				else if(to_set_wt_req_fns_n[wt_req_fns_n_i] | wt_req_fns)
					wt_req_fns_n[wt_req_fns_n_i*8+7:wt_req_fns_n_i*8] <= # simulation_delay 
						to_set_wt_req_fns_n[wt_req_fns_n_i] ? wt_req_fns_n_set_v[wt_req_fns_n_i*8+7:wt_req_fns_n_i*8]:
							wt_req_fns_n_add1[wt_req_fns_n_i*8+7:wt_req_fns_n_i*8];
			end
		end
	endgenerate
	
	// д����ж�����
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wt_req_fns_itr_req <= 1'b0;
		else
			wt_req_fns_itr_req <= # simulation_delay wt_req_fns_d & (wt_req_fns_n == wt_req_itr_th);
	end
	
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wt_req_fns_d <= 1'b0;
		else
			wt_req_fns_d <= # simulation_delay en_wt_req_fns_itr & wt_req_fns;
	end
	
endmodule
