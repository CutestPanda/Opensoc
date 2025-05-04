/*
MIT License

Copyright (c) 2024 Panda, 2257691535@qq.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

`timescale 1ns / 1ps
/********************************************************************
��ģ��: ֡����ļĴ������ýӿ�

����:
�Ĵ���->
    ƫ����  |    ����                        |   ��д����    |        ��ע
     0x00    0:ʹ��֡����                          W1RZ
	         1:��ǰ֡�Ѵ���                        W1TRL
	 0x04    31~0:֡����������ַ                    RW
	 0x08    2~0:֡���������洢֡�� - 1           RW
	           8:�Ƿ�����֡�ĺ���                 RW
	 0x0C      0:ȫ���ж�ʹ��                       RW
	           8:֡д���ж�ʹ��                     RW
			   9:֡��ȡ�ж�ʹ��                     RW
	 0x10      0:֡д���жϵȴ�                    RW1C
	           1:֡��ȡ�жϵȴ�                    RW1C

ע�⣺
��

Э��:
APB SLAVE

����: �¼�ҫ
����: 2025/02/20
********************************************************************/


module reg_if_for_frame_buffer #(
	parameter real SIM_DELAY = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire resetn,
    
    // APB�ӻ��ӿ�
    input wire[31:0] paddr,
    input wire psel,
    input wire penable,
    input wire pwrite,
    input wire[31:0] pwdata,
    output wire pready_out, // const -> 1'b1
    output wire[31:0] prdata_out,
    output wire pslverr_out, // const -> 1'b0
	
	// ʹ���ź�
	output wire en_frame_buffer,
	
	// ����ʱ����
	output wire[31:0] frame_buffer_baseaddr, // ֡����������ַ
	output wire[2:0] frame_buffer_max_store_n_sub1, // ֡���������洢֡�� - 1
	output wire en_frame_pos_proc, // �Ƿ�����֡�ĺ���
	
	// ֡�������
	output wire frame_processed, // ��ǰ֡�Ѵ����־(ע��: ȡ������!)
	input wire frame_filled, // ��ǰ֡������־(ע��: ȡ������!)
	input wire frame_fetched, // ��ǰ֡��ȡ�߱�־(ע��: ȡ������!)
	
	// �ж�����
	output wire frame_wt_itr_req, // ֡д���ж�����
	output wire frame_rd_itr_req // ֡��ȡ�ж�����
);
	
	/** �жϴ��� **/
	reg frame_filled_d; // �ӳ�1clk�ĵ�ǰ֡������־
	reg frame_fetched_d; // �ӳ�1clk�ĵ�ǰ֡��ȡ�߱�־
	wire on_frame_filled; // ��ǰ֡�����ָʾ
	wire on_frame_fetched; // ��ǰ֡��ȡ��ָʾ
	reg global_itr_en_r; // ȫ���ж�ʹ��
	reg frame_wt_itr_en_r; // ֡д���ж�ʹ��
	reg frame_rd_itr_en_r; // ֡��ȡ�ж�ʹ��
	reg frame_wt_itr_pending; // ֡д���жϵȴ�
	reg frame_rd_itr_pending; // ֡��ȡ�жϵȴ�
	reg frame_wt_itr_req_r; // ֡д���ж�����
	reg frame_rd_itr_req_r; // ֡��ȡ�ж�����
	
	assign frame_wt_itr_req = frame_wt_itr_req_r;
	assign frame_rd_itr_req = frame_rd_itr_req_r;
	
	assign on_frame_filled = frame_filled & (~frame_filled_d);
	assign on_frame_fetched = frame_fetched & (~frame_fetched_d);
	
	// �ӳ�1clk�ĵ�ǰ֡������־, �ӳ�1clk�ĵ�ǰ֡��ȡ�߱�־
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			{frame_fetched_d, frame_filled_d} <= 2'b00;
		else
			{frame_fetched_d, frame_filled_d} <= # SIM_DELAY {frame_fetched, frame_filled};
	end
	
	// ֡д���жϵȴ�
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			frame_wt_itr_pending <= 1'b0;
		else if((psel & penable & pwrite & (paddr[4:2] == 3'd4) & pwdata[0]) | on_frame_filled)
			frame_wt_itr_pending <= # SIM_DELAY on_frame_filled | (~(psel & penable & pwrite & (paddr[4:2] == 3'd4) & pwdata[0]));
	end
	// ֡��ȡ�жϵȴ�
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			frame_rd_itr_pending <= 1'b0;
		else if((psel & penable & pwrite & (paddr[4:2] == 3'd4) & pwdata[1]) | on_frame_fetched)
			frame_rd_itr_pending <= # SIM_DELAY on_frame_fetched | (~(psel & penable & pwrite & (paddr[4:2] == 3'd4) & pwdata[1]));
	end
	
	// ֡д���ж�����
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			frame_wt_itr_req_r <= 1'b0;
		else
			frame_wt_itr_req_r <= # SIM_DELAY global_itr_en_r & frame_wt_itr_en_r & on_frame_filled;
	end
	// ֡��ȡ�ж�����
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			frame_rd_itr_req_r <= 1'b0;
		else
			frame_rd_itr_req_r <= # SIM_DELAY global_itr_en_r & frame_rd_itr_en_r & on_frame_fetched;
	end
	
	/** ���üĴ����� **/
    reg[31:0] prdata_out_r; // APB�ӻ�������
	reg en_frame_buffer_r; // ʹ��֡����
	reg frame_processed_r; // ��ǰ֡�Ѵ����־
	reg[31:0] frame_buffer_baseaddr_r; // ֡����������ַ
	reg[2:0] frame_buffer_max_store_n_sub1_r; // ֡���������洢֡�� - 1
	reg en_frame_pos_proc_r; // �Ƿ�����֡�ĺ���
	
	assign pready_out = 1'b1;
	assign prdata_out = prdata_out_r;
	assign pslverr_out = 1'b0;
	
	assign en_frame_buffer = en_frame_buffer_r;
	assign frame_buffer_baseaddr = frame_buffer_baseaddr_r;
	assign frame_buffer_max_store_n_sub1 = frame_buffer_max_store_n_sub1_r;
	assign en_frame_pos_proc = en_frame_pos_proc_r;
	
	assign frame_processed = frame_processed_r;
	
	// APB�ӻ�������
	always @(posedge clk)
	begin
		if(psel)
		begin
			case(paddr[4:2])
				3'd0: prdata_out_r <= # SIM_DELAY {30'd0, frame_processed_r, 1'b0};
				3'd1: prdata_out_r <= # SIM_DELAY frame_buffer_baseaddr_r;
				3'd2: prdata_out_r <= # SIM_DELAY {16'd0, 7'd0, en_frame_pos_proc_r, 5'd0, frame_buffer_max_store_n_sub1_r};
				3'd3: prdata_out_r <= # SIM_DELAY {16'd0, 6'd0, frame_rd_itr_en_r, frame_wt_itr_en_r, 7'd0, global_itr_en_r};
				3'd4: prdata_out_r <= # SIM_DELAY {30'd0, frame_rd_itr_pending, frame_wt_itr_pending};
				default: prdata_out_r <= # SIM_DELAY 32'd0;
			endcase
		end
	end
	
	// ʹ��֡����
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			en_frame_buffer_r <= 1'b0;
		else if(psel & penable & pwrite & (paddr[4:2] == 3'd0) & pwdata[0])
			en_frame_buffer_r <= # SIM_DELAY 1'b1;
	end
	
	// ��ǰ֡�Ѵ����־
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			frame_processed_r <= 1'b0;
		else if(psel & penable & pwrite & (paddr[4:2] == 3'd0) & pwdata[1])
			frame_processed_r <= # SIM_DELAY ~frame_processed_r;
	end
	
	// ֡����������ַ
	always @(posedge clk)
	begin
		if(psel & penable & pwrite & (paddr[4:2] == 3'd1))
			frame_buffer_baseaddr_r <= # SIM_DELAY pwdata;
	end
	
	// ֡���������洢֡�� - 1
	always @(posedge clk)
	begin
		if(psel & penable & pwrite & (paddr[4:2] == 3'd2))
			frame_buffer_max_store_n_sub1_r <= # SIM_DELAY pwdata[2:0];
	end
	
	// �Ƿ�����֡�ĺ���
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			en_frame_pos_proc_r <= 1'b0;
		else if(psel & penable & pwrite & (paddr[4:2] == 3'd2))
			en_frame_pos_proc_r <= # SIM_DELAY pwdata[8];
	end
	
	// ȫ���ж�ʹ��, ֡д���ж�ʹ��, ֡��ȡ�ж�ʹ��
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			{frame_rd_itr_en_r, frame_wt_itr_en_r, global_itr_en_r} <= 3'b000;
		else if(psel & penable & pwrite & (paddr[4:2] == 3'd3))
			{frame_rd_itr_en_r, frame_wt_itr_en_r, global_itr_en_r} <= # SIM_DELAY {pwdata[9], pwdata[8], pwdata[0]};
	end
	
endmodule
