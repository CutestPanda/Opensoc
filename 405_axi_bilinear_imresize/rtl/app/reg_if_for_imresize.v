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
��ģ��: ͼ�����ŵļĴ������ýӿ�

����:
�Ĵ���->
    ƫ����  |    ����                        |   ��д����    |        ��ע
	 0x00         0:AXI����λ��                     RO          1'b0 -> 32λ, 1'b1 -> 64λ
	              1:��������æµ��־                RO
				  2:������������                   WARZ         ���λд1, ����������æµ��־Ϊ0, ������������
	 0x04         0:ȫ���ж�ʹ��                    RW
	              8:��������ж�ʹ��                RW
	 0x08         0:��������жϵȴ�               RW1C
     0x0C      31~0:�������������ַ                RW
	 0x10      31~0:ԴͼƬ����ַ                    RW
	 0x14      15~0:����������п��                RW
	          31~16:Ŀ��ͼƬ�п��                  RW
	 0x18      15~0:ԴͼƬ�п��                    RW
	          31~16:��ֱ���ű���                    RW          �޷��Ŷ�����: ԴͼƬ�߶� / Ŀ��ͼ��߶�
	 0x1C      15~0:ˮƽ���ű���                    RW          �޷��Ŷ�����: ԴͼƬ��� / Ŀ��ͼ����
	          31~16:Ŀ��ͼƬ�߶� - 1                RW
	 0x20      15~0:Ŀ��ͼƬ��� - 1                RW
	          31~16:ԴͼƬ�߶� - 1                  RW
	 0x24      15~0:ԴͼƬ��� - 1                  RW
	          31~16:Դ�������п��                  RW
	 0x28       1~0:ͼƬͨ���� - 1                  RW

ע�⣺
��

Э��:
APB SLAVE

����: �¼�ҫ
����: 2025/02/24
********************************************************************/


module reg_if_for_imresize #(
	parameter integer BUS_WIDTH = 32, // AXI��������λ��(32 | 64)
	parameter real SIM_DELAY = 1 // ������ʱ
)(
    // APB�ӻ���ʱ�Ӻ͸�λ
	input wire pclk,
	input wire presetn,
	// AXI������ʱ�Ӻ͸�λ
	input wire m_axi_aclk,
	input wire m_axi_aresetn,
    
    // APB�ӻ��ӿ�
    input wire[31:0] paddr,
    input wire psel,
    input wire penable,
    input wire pwrite,
    input wire[31:0] pwdata,
    output wire pready_out, // const -> 1'b1
    output wire[31:0] prdata_out,
    output wire pslverr_out, // const -> 1'b0
	
	// ���ſ���
	input wire resize_fns, // ������ɱ�־(ע��: ȡ������!)
	
	// ˫���Բ�ֵ����(AXIS����)
	output wire[231:0] m_req_axis_data,
	output wire m_req_axis_valid,
	input wire m_req_axis_ready,
	
	// �ж�����
	output wire resize_fns_itr_req // ��������ж�����
);
	
	/** �ڲ����� **/
	// ˫���Բ�ֵ���������λ��
	localparam integer REQ_WIDTH = 232;
	// ��������Ĵ���ռ�õ�����
	localparam integer REQ_REGS_WORDS_N = 8;
	// ��������Ĵ�������ַ
	localparam integer REQ_REGS_BASEADDR = 12;
	
	/** ˫���Բ�ֵ�����ʱ������ **/
	wire[REQ_WIDTH-1:0] i_pclk_req_axis_data;
	wire i_pclk_req_axis_valid;
	wire i_pclk_req_axis_ready;
	wire[REQ_WIDTH-1:0] o_pclk_req_axis_data;
	wire o_pclk_req_axis_valid;
	wire o_pclk_req_axis_ready;
	
	cdc_tx #(
		.DATA_WIDTH(REQ_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)cdc_tx_u(
		.clk(pclk),
		.rst_n(presetn),
		
		.i_dat(i_pclk_req_axis_data),
		.i_vld(i_pclk_req_axis_valid),
		.i_rdy(i_pclk_req_axis_ready),
		
		.o_dat(o_pclk_req_axis_data),
		.o_vld(o_pclk_req_axis_valid),
		.o_rdy_a(o_pclk_req_axis_ready)
	);
	
	cdc_rx #(
		.DATA_WIDTH(REQ_WIDTH),
		.SIM_DELAY(SIM_DELAY)
	)cdc_rx_u(
		.clk(m_axi_aclk),
		.rst_n(m_axi_aresetn),
		
		.i_dat(o_pclk_req_axis_data),
		.i_vld_a(o_pclk_req_axis_valid),
		.i_rdy(o_pclk_req_axis_ready),
		
		.o_dat(m_req_axis_data),
		.o_vld(m_req_axis_valid),
		.o_rdy(m_req_axis_ready)
	);
	
	/** �жϴ��� **/
	reg resize_fns_d; // �ӳ�1clk��������ɱ�־
	wire on_resize_fns; // �������(ָʾ)
	reg global_itr_en; // ȫ���ж�ʹ��
	reg resize_fns_itr_en; // ��������ж�ʹ��
	reg resize_fns_itr_pending; // ��������жϵȴ�
	reg resize_fns_itr_req_r; // ��������ж�����
	
	assign resize_fns_itr_req = resize_fns_itr_req_r;
	
	assign on_resize_fns = resize_fns & (~resize_fns_d);
	
	// �ӳ�1clk��������ɱ�־
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			resize_fns_d <= 1'b0;
		else
			resize_fns_d <= # SIM_DELAY resize_fns;
	end
	
	// ȫ���ж�ʹ��
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			global_itr_en <= 1'b0;
		else if(psel & penable & pwrite & (paddr[5:2] == 4'd1))
			global_itr_en <= # SIM_DELAY pwdata[0];
	end
	// ��������ж�ʹ��
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			resize_fns_itr_en <= 1'b0;
		else if(psel & penable & pwrite & (paddr[5:2] == 4'd1))
			resize_fns_itr_en <= # SIM_DELAY pwdata[8];
	end
	
	// ��������жϵȴ�
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			resize_fns_itr_pending <= 1'b0;
		else if(on_resize_fns | 
			(psel & penable & pwrite & (paddr[5:2] == 4'd1) & pwdata[0])
		)
			resize_fns_itr_pending <= # SIM_DELAY 
				on_resize_fns | (~(psel & penable & pwrite & (paddr[5:2] == 4'd1) & pwdata[0]));
	end
	
	// ��������ж�����
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			resize_fns_itr_req_r <= 1'b0;
		else
			resize_fns_itr_req_r <= # SIM_DELAY on_resize_fns & global_itr_en & resize_fns_itr_en;
	end
	
	/** ���������� **/
	wire on_start_resize_req; // ��ʼ������������(ָʾ)
	wire[REQ_WIDTH-1:0] resize_req; // �����͵���������
	reg resize_req_vld; // ����������������Ч(��־)
	wire resize_req_busy_flag; // ��������æµ(��־)
	
	assign i_pclk_req_axis_data = resize_req;
	assign i_pclk_req_axis_valid = resize_req_vld;
	
	assign on_start_resize_req = psel & penable & pwrite & (paddr[5:2] == 4'd0) & pwdata[2] & (~resize_req_busy_flag);
	assign resize_req_busy_flag = resize_req_vld;
	
	// ����������������Ч(��־)
	always @(posedge pclk or negedge presetn)
	begin
		if(~presetn)
			resize_req_vld <= 1'b0;
		else if(resize_req_vld ? 
			i_pclk_req_axis_ready:
			on_start_resize_req
		)
			resize_req_vld <= # SIM_DELAY ~resize_req_vld;
	end
	
	/** ��������Ĵ��� **/
	reg[REQ_REGS_WORDS_N*32-1:0] resize_req_r;
	
	assign resize_req = resize_req_r[REQ_WIDTH-1:0];
	
	genvar resize_req_r_i;
	generate
		for(resize_req_r_i = 0;resize_req_r_i < REQ_REGS_WORDS_N;resize_req_r_i = resize_req_r_i + 1)
		begin
			always @(posedge pclk)
			begin
				if(psel & penable & pwrite & (paddr[5:2] == (REQ_REGS_BASEADDR[5:2] + resize_req_r_i)))
					resize_req_r[32*resize_req_r_i+31:32*resize_req_r_i] <= # SIM_DELAY 
						pwdata;
			end
		end
	endgenerate
	
	/** APB������ **/
	reg[31:0] prdata_r;
	
	assign pready_out = 1'b1;
	assign prdata_out = prdata_r;
	assign pslverr_out = 1'b0;
	
	always @(posedge pclk)
	begin
		if(psel & (~pwrite))
		begin
			case(paddr[5:2])
				4'd0: prdata_r <= # SIM_DELAY {30'd0, resize_req_busy_flag, (BUS_WIDTH == 64) ? 1'b1:1'b0};
				4'd1: prdata_r <= # SIM_DELAY {16'd0, 7'd0, resize_fns_itr_en, 7'd0, global_itr_en};
				4'd2: prdata_r <= # SIM_DELAY {31'd0, resize_fns_itr_pending};
				4'd3: prdata_r <= # SIM_DELAY resize_req_r[31:0];
				4'd4: prdata_r <= # SIM_DELAY resize_req_r[63:32];
				4'd5: prdata_r <= # SIM_DELAY resize_req_r[95:64];
				4'd6: prdata_r <= # SIM_DELAY resize_req_r[127:96];
				4'd7: prdata_r <= # SIM_DELAY resize_req_r[159:128];
				4'd8: prdata_r <= # SIM_DELAY resize_req_r[191:160];
				4'd9: prdata_r <= # SIM_DELAY resize_req_r[223:192];
				4'd10: prdata_r <= # SIM_DELAY {30'd0, resize_req_r[225:224]};
				default: prdata_r <= # SIM_DELAY 32'h0000_0000;
			endcase
		end
	end
	
endmodule
