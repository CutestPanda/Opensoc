`timescale 1ns / 1ps
/********************************************************************
��ģ��: SDIOʱ�ӷ�����

����:
�ɶ�̬���÷�Ƶ��
֧��������������Ƶ
ʹ��ODDR���

ע�⣺
��Ƶ���ͷ�Ƶ������ʹ��ֻ���ڹر�SDIOʱ�ӻ��߷�Ƶ���������ʱ�ı�

Э��:
��

����: �¼�ҫ
����: 2024/07/30
********************************************************************/


module sdio_sck_generator #(
    parameter integer div_cnt_width = 10, // ��Ƶ������λ��
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire resetn,
    
    // ����ʱ����
    input wire en_sdio_clk, // ����SDIOʱ��(��λʱ����Ϊ0)
    input wire[div_cnt_width-1:0] div_rate, // ��Ƶ�� - 1
    
    // ��Ƶ������ʹ��
    input wire div_cnt_en,
	
	// SDIO�������ָʾ
	output wire sdio_in_sample,
	// SDIO�������ָʾ
	output wire sdio_out_upd,
    
    // SDIOʱ��
    output wire sdio_clk
);
	
	/** �ڲ����� **/
	localparam en_oddr_in_reg = "false"; // �Ƿ�ʹ��ODDR����Ĵ���
	
    /** ODDR **/
	wire oddr_posedge_in_w; // ODDR��������������
	wire oddr_negedge_in_w; // ODDR�½�����������
	reg oddr_posedge_in; // ODDR��������������Ĵ���
	reg oddr_negedge_in; // ODDR�½�����������Ĵ���
	
	// ODDR��������������Ĵ���
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			oddr_posedge_in <= 1'b0;
		else
			# simulation_delay oddr_posedge_in <= oddr_posedge_in_w;
	end
	// ODDR�½�����������Ĵ���
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			oddr_negedge_in <= 1'b0;
		else
			# simulation_delay oddr_negedge_in <= oddr_negedge_in_w;
	end
	
	// ODDR
	EG_LOGIC_ODDR #(
		.ASYNCRST("ENABLE")
	)oddr_u(
		.q(sdio_clk),
		
		.clk(clk),
		
		.d0((en_oddr_in_reg == "true") ? oddr_posedge_in:oddr_posedge_in_w),
		.d1((en_oddr_in_reg == "true") ? oddr_negedge_in:oddr_negedge_in_w),
		
		.rst(~resetn)
	);
	
	/** SDIOʱ�ӷ�Ƶ **/
	reg div_cnt_en_shadow; // ��Ƶ������ʹ��(Ӱ�ӼĴ���)
	reg[div_cnt_width-1:0] div_rate_shadow; // ��Ƶ��(Ӱ�ӼĴ���)
	wire to_turn_off_sdio_clk; // �ر�SDIOʱ��(��־)
	wire on_div_cnt_rst; // ��Ƶ����������(ָʾ)
	wire div_cnt_eq_div_rate_shadow_rsh1; // ��Ƶ������ == (��Ƶ��(Ӱ�ӼĴ���) >> 1)
	reg[div_cnt_width-1:0] div_cnt; // ��Ƶ������
	
	assign oddr_posedge_in_w = (div_cnt > div_rate_shadow[div_cnt_width-1:1]) & (~to_turn_off_sdio_clk);
	assign oddr_negedge_in_w = ((div_cnt > div_rate_shadow[div_cnt_width-1:1]) | 
		(div_cnt_eq_div_rate_shadow_rsh1 & (~div_rate_shadow[0]))) & (~to_turn_off_sdio_clk);
	
	assign to_turn_off_sdio_clk = (~en_sdio_clk) | (~div_cnt_en_shadow);
	assign on_div_cnt_rst = div_cnt == div_rate_shadow;
	assign div_cnt_eq_div_rate_shadow_rsh1 = div_cnt == div_rate_shadow[div_cnt_width-1:1];
	
	// ��Ƶ������ʹ��(Ӱ�ӼĴ���)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			div_cnt_en_shadow <= 1'b0;
		else if(to_turn_off_sdio_clk | on_div_cnt_rst) // ����
			# simulation_delay div_cnt_en_shadow <= div_cnt_en;
	end
	// ��Ƶ��(Ӱ�ӼĴ���)
	always @(posedge clk)
	begin
		if(to_turn_off_sdio_clk | on_div_cnt_rst) // ����
			# simulation_delay div_rate_shadow <= div_rate;
	end
	
	// ��Ƶ������
	always @(posedge clk)
	begin
		if(to_turn_off_sdio_clk | on_div_cnt_rst) // ����
			# simulation_delay div_cnt <= 0;
		else // ����
			# simulation_delay div_cnt <= div_cnt + 1;
	end
	
	/** SDIO����������������ָʾ **/
	reg sdio_in_sample_reg; // SDIO�������ָʾ
	reg sdio_in_sample_reg_d; // �ӳ�1clk��SDIO�������ָʾ
	reg sdio_out_upd_reg; // SDIO�������ָʾ
	reg sdio_out_upd_reg_d; // �ӳ�1clk��SDIO�������ָʾ
	
	assign sdio_in_sample = (en_oddr_in_reg == "true") ? sdio_in_sample_reg_d:sdio_in_sample_reg;
	assign sdio_out_upd = (en_oddr_in_reg == "true") ? sdio_out_upd_reg_d:sdio_out_upd_reg;
	
	// SDIO�������ָʾ
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			sdio_in_sample_reg <= 1'b0;
		else // ��������
			# simulation_delay sdio_in_sample_reg <= (~to_turn_off_sdio_clk) & 
				(div_cnt == (div_rate_shadow[div_cnt_width-1:1] + div_rate_shadow[0]));
	end
	// SDIO�������ָʾ
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			sdio_out_upd_reg <= 1'b0;
		else // ��������
			# simulation_delay sdio_out_upd_reg <= (~to_turn_off_sdio_clk) & on_div_cnt_rst;
	end
	
	// �ӳ�1clk��SDIO�������ָʾ
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			sdio_in_sample_reg_d <= 1'b0;
		else // �ӳ�
			# simulation_delay sdio_in_sample_reg_d <= sdio_in_sample_reg;
	end
	// �ӳ�1clk��SDIO�������ָʾ
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			sdio_out_upd_reg_d <= 1'b0;
		else // �ӳ�
			# simulation_delay sdio_out_upd_reg_d <= sdio_out_upd_reg;
	end
	
endmodule
