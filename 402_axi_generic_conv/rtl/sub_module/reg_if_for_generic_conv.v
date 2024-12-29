`timescale 1ns / 1ps
/********************************************************************
��ģ��: ͨ�þ�����㵥Ԫ�ļĴ������ýӿ�

����:
�Ĵ���->
    ƫ����  |    ����                        |   ��д����    |        ��ע
    0x00    0:��λ���Բ���������                   WO        д�üĴ����Ҹ�λΪ1'b1ʱִ�и�λ
	        1:��λ����ͨ·�ϵľ���˲�������       WO        д�üĴ����Ҹ�λΪ1'b1ʱִ�и�λ
			8:����������������DMA                  WO        д�üĴ����Ҹ�λΪ1'b1ʱִ������
			9:����д����������DMA                  WO        д�üĴ����Ҹ�λΪ1'b1ʱִ������
			16:������������DMA���б�־             RO
			17:д����������DMA���б�־             RO
	0x04    0:ȫ���ж�ʹ��                         RW
			8:������������DMA����������ж�ʹ��  RW
	        9:д����������DMA����������ж�ʹ��  RW
			10:д����������ж�ʹ��              RW
	0x08    0:ȫ���жϱ�־                         WC
	        8:������������DMA����������жϱ�־  RO
			9:д����������DMA����������жϱ�־  RO
			10:д����������жϱ�־              RO
	0x0C    31~0:д����������ж���ֵ            RW
	0x10    0:ʹ�ܾ������                         RW
	0x14    0:���������                           RW        1'b0 -> 1x1, 1'b1 -> 3x3
	        11~8:�������ʹ��                      RW
	0x18    31~0:�����󻺴����׵�ַ                RW
	0x1C    31~0:��������� - 1                    RW
	0x20    31~0:д���󻺴����׵�ַ                RW
	0x24    31~0:д������� - 1                    RW
	0x28    15~0:��������ͼ��� - 1                RW
	        31~16:��������ͼ�߶� - 1               RW
	0x2C    15~0:��������ͼͨ���� - 1              RW
	        31~16:����˸��� - 1                   RW
	0x30    31~0:Relu����ϵ��c[31:0]               RW
	0x34    31~0:Relu����ϵ��c[63:32]              RW
	0x38    31~0:����ɵ�д�������                RW
	0x3C    15~0:�������ͼ��� - 1                RW
	        31~16:�������ͼ�߶� - 1               RW
	0x40    2~0:ˮƽ���� - 1                       RW
	        10~8:��ֱ���� - 1                      RW
	        16:��������                            RW        1'b0 -> �ӵ�1��ROI��ʼ, 1'b1 -> ������1��ROI
	0x44    1~0:��������                           RW        2'b00 -> Relu, 2'b01 -> ����, 2'b10 -> Sigmoid, 2'b11 -> Tanh
	0x48    10~0:�����Լ�����ұ�д��ַ            WO        д�üĴ���ʱ�������ұ�дʹ��, д���ݵ���������ӦΪQ15
	        31~16:�����Լ�����ұ�д����           WO

ע�⣺
��

Э��:
AXI-Lite SLAVE
BLK CTRL
MEM WRITE

����: �¼�ҫ
����: 2024/12/29
********************************************************************/


module reg_if_for_generic_conv #(
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
	
	// �Ĵ������ýӿ�(AXI-Lite�ӻ�)
    // ����ַͨ��
    input wire[31:0] s_axi_lite_araddr,
	input wire[2:0] s_axi_lite_arprot, // ignored
    input wire s_axi_lite_arvalid,
    output wire s_axi_lite_arready,
    // д��ַͨ��
    input wire[31:0] s_axi_lite_awaddr,
	input wire[2:0] s_axi_lite_awprot, // ignored
    input wire s_axi_lite_awvalid,
    output wire s_axi_lite_awready,
    // д��Ӧͨ��
    output wire[1:0] s_axi_lite_bresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_bvalid,
    input wire s_axi_lite_bready,
    // ������ͨ��
    output wire[31:0] s_axi_lite_rdata,
    output wire[1:0] s_axi_lite_rresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_rvalid,
    input wire s_axi_lite_rready,
    // д����ͨ��
    input wire[31:0] s_axi_lite_wdata,
	input wire[3:0] s_axi_lite_wstrb,
    input wire s_axi_lite_wvalid,
    output wire s_axi_lite_wready,
	
	// �鼶����
	// ������������DMA
	output wire rd_req_dsc_dma_blk_start,
	input wire rd_req_dsc_dma_blk_idle,
	// д����������DMA
	output wire wt_req_dsc_dma_blk_start,
	input wire wt_req_dsc_dma_blk_idle,
	
	// ʹ��
	output wire en_conv_cal, // �Ƿ�ʹ�ܾ������
	
	// ��λ
	output wire rst_linear_pars_buf, // ��λ���Բ���������
	output wire rst_cal_path_kernal_buf, // ��λ����ͨ·�ϵľ���˲�������
	
	// �ж�
	output wire[31:0] wt_req_itr_th, // д����������ж���ֵ
	input wire[2:0] itr_req, // �ж�����({д����������ж�����, 
	                         //     д����������DMA����������ж�����, ������������DMA����������ж�����})
	output wire en_wt_req_fns_itr, // �Ƿ�ʹ��д����������ж�
	output wire itr, // �ж��ź�
	
	// ����ɵ�д�������
	output wire[3:0] to_set_wt_req_fns_n,
	output wire[31:0] wt_req_fns_n_set_v,
	input wire[31:0] wt_req_fns_n_cur_v,
	
	// �����Լ�����ұ�(д�˿�)
	output wire non_ln_act_lut_wen,
	output wire[10:0] non_ln_act_lut_waddr,
	output wire[15:0] non_ln_act_lut_din, // Q15
	
	// ����ʱ����
	output wire[63:0] act_rate_c, // Relu����ϵ��c
	output wire[31:0] rd_req_buf_baseaddr, // �����󻺴����׵�ַ
	output wire[31:0] rd_req_n, // ��������� - 1
	output wire[31:0] wt_req_buf_baseaddr, // д���󻺴����׵�ַ
	output wire[31:0] wt_req_n, // д������� - 1
	output wire kernal_type, // ���������(1'b0 -> 1x1, 1'b1 -> 3x3)
	output wire[15:0] feature_map_w, // ��������ͼ��� - 1
	output wire[15:0] feature_map_h, // ��������ͼ�߶� - 1
	output wire[15:0] feature_map_chn_n, // ��������ͼͨ���� - 1
	output wire[15:0] kernal_n, // ����˸��� - 1
	output wire[3:0] padding_en, // �������ʹ��(�������������Ϊ3x3ʱ����, {��, ��, ��, ��})
	output wire[15:0] o_ft_map_w, // �������ͼ��� - 1
	output wire[15:0] o_ft_map_h, // �������ͼ�߶� - 1
	output wire[2:0] horizontal_step, // ˮƽ���� - 1
	output wire[2:0] vertical_step, // ��ֱ���� - 1
	output wire step_type, // ��������(1'b0 -> �ӵ�1��ROI��ʼ, 1'b1 -> ������1��ROI)
	output wire[1:0] act_type // ��������(2'b00 -> Relu, 2'b01 -> ����, 2'b10 -> Sigmoid, 2'b11 -> Tanh)
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
	
	/** �ڲ����� **/
	localparam integer REGS_N = 19; // �Ĵ�������
	
	/** ���� **/
	// �Ĵ�������״̬��������
	localparam integer REG_CFG_STS_ADDR = 0; // ״̬:��ַ�׶�
	localparam integer REG_CFG_STS_RW_REG = 1; // ״̬:��/д�Ĵ���
	localparam integer REG_CFG_STS_RW_RESP = 2; // ״̬:��/д��Ӧ
	
	/** �Ĵ������ÿ��� **/
	reg[2:0] reg_cfg_sts; // �Ĵ�������״̬
	wire[1:0] rw_grant; // ��д���({д���, �����})
	reg[1:0] addr_ready; // ��ַͨ����ready�ź�({aw_ready, ar_ready})
	reg is_write; // �Ƿ�д�Ĵ���
	reg[clogb2(REGS_N-1):0] ofs_addr; // ��д�Ĵ�����ƫ�Ƶ�ַ
	reg wready; // д����ͨ����ready�ź�
	reg bvalid; // д��Ӧͨ����valid�ź�
	reg rvalid; // ������ͨ����valid�ź�
	wire regs_en; // �Ĵ�������ʹ��
	wire[3:0] regs_wen; // �Ĵ���дʹ��
	wire[clogb2(REGS_N-1):0] regs_addr; // �Ĵ������ʵ�ַ
	wire[31:0] regs_din; // �Ĵ���д����
	wire[31:0] regs_dout; // �Ĵ���������
	
	assign {s_axi_lite_awready, s_axi_lite_arready} = addr_ready;
	assign s_axi_lite_bresp = 2'b00;
	assign s_axi_lite_bvalid = bvalid;
	assign s_axi_lite_rdata = regs_dout;
	assign s_axi_lite_rresp = 2'b00;
	assign s_axi_lite_rvalid = rvalid;
	assign s_axi_lite_wready = wready;
	
	assign rw_grant = {s_axi_lite_awvalid, (~s_axi_lite_awvalid) & s_axi_lite_arvalid}; // д����
	
	assign regs_en = reg_cfg_sts[REG_CFG_STS_RW_REG] & ((~is_write) | s_axi_lite_wvalid);
	assign regs_wen = {4{is_write}} & s_axi_lite_wstrb;
	assign regs_addr = ofs_addr;
	assign regs_din = s_axi_lite_wdata;
	
	// �Ĵ�������״̬
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			reg_cfg_sts <= 3'b001;
		else if((reg_cfg_sts[REG_CFG_STS_ADDR] & (s_axi_lite_awvalid | s_axi_lite_arvalid)) | 
			(reg_cfg_sts[REG_CFG_STS_RW_REG] & ((~is_write) | s_axi_lite_wvalid)) | 
			(reg_cfg_sts[REG_CFG_STS_RW_RESP] & (is_write ? s_axi_lite_bready:s_axi_lite_rready)))
			reg_cfg_sts <= # simulation_delay {reg_cfg_sts[1:0], reg_cfg_sts[2]};
	end
	
	// ��ַͨ����ready�ź�
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			addr_ready <= 2'b00;
		else
			addr_ready <= # simulation_delay {2{reg_cfg_sts[REG_CFG_STS_ADDR]}} & rw_grant;
	end
	
	// �Ƿ�д�Ĵ���
	always @(posedge clk)
	begin
		if(reg_cfg_sts[REG_CFG_STS_ADDR] & (s_axi_lite_awvalid | s_axi_lite_arvalid))
			is_write <= # simulation_delay s_axi_lite_awvalid;
	end
	
	// ��д�Ĵ�����ƫ�Ƶ�ַ
	always @(posedge clk)
	begin
		if(reg_cfg_sts[REG_CFG_STS_ADDR] & (s_axi_lite_awvalid | s_axi_lite_arvalid))
			ofs_addr <= # simulation_delay s_axi_lite_awvalid ? 
				s_axi_lite_awaddr[2+clogb2(REGS_N-1):2]:s_axi_lite_araddr[2+clogb2(REGS_N-1):2];
	end
	
	// д����ͨ����ready�ź�
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wready <= 1'b0;
		else
			wready <= # simulation_delay wready ? 
				(~s_axi_lite_wvalid):(reg_cfg_sts[REG_CFG_STS_ADDR] & s_axi_lite_awvalid);
	end
	
	// д��Ӧͨ����valid�ź�
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			bvalid <= 1'b0;
		else
			bvalid <= # simulation_delay bvalid ? 
				(~s_axi_lite_bready):(s_axi_lite_wvalid & s_axi_lite_wready);
	end
	
	// ������ͨ����valid�ź�
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rvalid <= 1'b0;
		else
			rvalid <= # simulation_delay rvalid ? 
				(~s_axi_lite_rready):(reg_cfg_sts[REG_CFG_STS_RW_REG] & (~is_write));
	end
	
	/** �Ĵ����� **/
	// �жϿ���
	wire global_itr_req; // ȫ���ж�����
	// �Ĵ�����������
	wire[31:0] regs_region_rd_out_nxt;
	reg[31:0] regs_region_rd_out;
	// 0x00
	reg rst_linear_pars_buf_reg; // ��λ���Բ���������
	reg rst_cal_path_kernal_buf_reg; // ��λ����ͨ·�ϵľ���˲�������
	reg rd_req_dsc_dma_blk_start_reg; // ����������������DMA
	reg wt_req_dsc_dma_blk_start_reg; // ����д����������DMA
	reg rd_req_dsc_dma_blk_idle_reg; // ������������DMA���б�־
	reg wt_req_dsc_dma_blk_idle_reg; // д����������DMA���б�־
	// 0x04
	reg global_itr_en_reg; // ȫ���ж�ʹ��
	reg[2:0] itr_en_vec_regs; // ���ж�ʹ������
	// 0x08
	reg global_itr_flag_reg; // ȫ���жϱ�־
	reg[2:0] itr_flag_vec_regs; // ���жϱ�־����
	// 0x0C
	reg[31:0] wt_req_itr_th_regs; // д����������ж���ֵ
	// 0x10
	reg en_conv_cal_reg; // ʹ�ܾ������
	// 0x14
	reg kernal_type_reg; // ���������
	reg[3:0] padding_en_regs; // �������ʹ��
	// 0x18
	reg[31:0] rd_req_buf_baseaddr_regs; // �����󻺴����׵�ַ
	// 0x1C
	reg[31:0] rd_req_n_regs; // ��������� - 1 
	// 0x20
	reg[31:0] wt_req_buf_baseaddr_regs; // д���󻺴����׵�ַ
	// 0x24
	reg[31:0] wt_req_n_regs; // д������� - 1
	// 0x28
	reg[15:0] feature_map_w_regs; // ��������ͼ��� - 1
	reg[15:0] feature_map_h_regs; // ��������ͼ�߶� - 1
	// 0x2C
	reg[15:0] feature_map_chn_n_regs; // ��������ͼͨ���� - 1
	reg[15:0] kernal_n_regs; // ����˸��� - 1
	// 0x30, 0x34
	reg[63:0] act_rate_c_regs; // Relu����ϵ��c
	// 0x3C
	reg[15:0] o_ft_map_w_regs; // �������ͼ��� - 1
	reg[15:0] o_ft_map_h_regs; // �������ͼ�߶� - 1
	// 0x40
	reg[2:0] horizontal_step_regs; // ˮƽ���� - 1
	reg[2:0] vertical_step_regs; // ��ֱ���� - 1
	reg step_type_reg; // ��������
	// 0x44
	reg[1:0] act_type_regs; // ��������
	// 0x48
	reg non_ln_act_lut_wen_reg;
	reg[10:0] non_ln_act_lut_waddr_regs;
	reg[15:0] non_ln_act_lut_din_regs; // Q15
	
	assign rd_req_dsc_dma_blk_start = rd_req_dsc_dma_blk_start_reg;
	assign wt_req_dsc_dma_blk_start = wt_req_dsc_dma_blk_start_reg;
	
	assign en_conv_cal = en_conv_cal_reg;
	
	assign rst_linear_pars_buf = rst_linear_pars_buf_reg;
	assign rst_cal_path_kernal_buf = rst_cal_path_kernal_buf_reg;
	
	assign wt_req_itr_th = wt_req_itr_th_regs;
	assign en_wt_req_fns_itr = global_itr_en_reg & itr_en_vec_regs[2];
	
	assign to_set_wt_req_fns_n = {4{regs_en & (regs_addr == 14)}} & regs_wen;
	assign wt_req_fns_n_set_v = regs_din;
	
	assign non_ln_act_lut_wen = non_ln_act_lut_wen_reg;
	assign non_ln_act_lut_waddr = non_ln_act_lut_waddr_regs;
	assign non_ln_act_lut_din = non_ln_act_lut_din_regs;
	
	assign act_rate_c = act_rate_c_regs;
	assign rd_req_buf_baseaddr = rd_req_buf_baseaddr_regs;
	assign rd_req_n = rd_req_n_regs;
	assign wt_req_buf_baseaddr = wt_req_buf_baseaddr_regs;
	assign wt_req_n = wt_req_n_regs;
	assign kernal_type = kernal_type_reg;
	assign feature_map_w = feature_map_w_regs;
	assign feature_map_h = feature_map_h_regs;
	assign feature_map_chn_n = feature_map_chn_n_regs;
	assign kernal_n = kernal_n_regs;
	assign padding_en = padding_en_regs;
	assign o_ft_map_w = o_ft_map_w_regs;
	assign o_ft_map_h = o_ft_map_h_regs;
	assign horizontal_step = horizontal_step_regs;
	assign vertical_step = vertical_step_regs;
	assign step_type = step_type_reg;
	assign act_type = act_type_regs;
	
	assign regs_dout = regs_region_rd_out;
	
	assign global_itr_req = (|(itr_req & itr_en_vec_regs)) & global_itr_en_reg & (~global_itr_flag_reg);
	
	assign regs_region_rd_out_nxt = 
		({32{regs_addr == 0}} & {
			8'dx, 
			6'dx, wt_req_dsc_dma_blk_idle_reg, rd_req_dsc_dma_blk_idle_reg, 
			8'dx, 
			8'dx
		}) | 
		({32{regs_addr == 1}} & {
			8'dx, 
			8'dx, 
			5'dx, itr_en_vec_regs, 
			7'dx, global_itr_en_reg
		}) | 
		({32{regs_addr == 2}} & {
			8'dx, 
			8'dx, 
			5'dx, itr_flag_vec_regs, 
			7'dx, global_itr_flag_reg
		}) | 
		({32{regs_addr == 3}} & {
			wt_req_itr_th_regs[31:24], 
			wt_req_itr_th_regs[23:16], 
			wt_req_itr_th_regs[15:8], 
			wt_req_itr_th_regs[7:0]
		}) | 
		({32{regs_addr == 4}} & {
			8'dx, 
			8'dx, 
			8'dx, 
			7'dx, en_conv_cal_reg
		}) | 
		({32{regs_addr == 5}} & {
			8'dx, 
			8'dx, 
			4'dx, padding_en_regs, 
			7'dx, kernal_type_reg
		}) | 
		({32{regs_addr == 6}} & {
			rd_req_buf_baseaddr_regs[31:24], 
			rd_req_buf_baseaddr_regs[23:16], 
			rd_req_buf_baseaddr_regs[15:8], 
			rd_req_buf_baseaddr_regs[7:0]
		}) | 
		({32{regs_addr == 7}} & {
			rd_req_n_regs[31:24], 
			rd_req_n_regs[23:16], 
			rd_req_n_regs[15:8], 
			rd_req_n_regs[7:0]
		}) | 
		({32{regs_addr == 8}} & {
			wt_req_buf_baseaddr_regs[31:24], 
			wt_req_buf_baseaddr_regs[23:16], 
			wt_req_buf_baseaddr_regs[15:8], 
			wt_req_buf_baseaddr_regs[7:0]
		}) | 
		({32{regs_addr == 9}} & {
			wt_req_n_regs[31:24], 
			wt_req_n_regs[23:16], 
			wt_req_n_regs[15:8], 
			wt_req_n_regs[7:0]
		}) | 
		({32{regs_addr == 10}} & {
			feature_map_h_regs[15:8], 
			feature_map_h_regs[7:0], 
			feature_map_w_regs[15:8], 
			feature_map_w_regs[7:0]
		}) | 
		({32{regs_addr == 11}} & {
			kernal_n_regs[15:8], 
			kernal_n_regs[7:0], 
			feature_map_chn_n_regs[15:8], 
			feature_map_chn_n_regs[7:0]
		}) | 
		({32{regs_addr == 12}} & {
			act_rate_c_regs[31:24], 
			act_rate_c_regs[23:16], 
			act_rate_c_regs[15:8], 
			act_rate_c_regs[7:0]
		}) | 
		({32{regs_addr == 13}} & {
			act_rate_c_regs[63:56], 
			act_rate_c_regs[55:48], 
			act_rate_c_regs[47:40], 
			act_rate_c_regs[39:32]
		}) | 
		({32{regs_addr == 14}} & {
			wt_req_fns_n_cur_v[31:24], 
			wt_req_fns_n_cur_v[23:16], 
			wt_req_fns_n_cur_v[15:8], 
			wt_req_fns_n_cur_v[7:0]
		}) | 
		({32{regs_addr == 15}} & {
			o_ft_map_h_regs[15:8], 
			o_ft_map_h_regs[7:0], 
			o_ft_map_w_regs[15:8], 
			o_ft_map_w_regs[7:0]
		}) | 
		({32{regs_addr == 16}} & {
			8'dx, 
			7'dx, step_type_reg, 
			5'dx, vertical_step_regs, 
			5'dx, horizontal_step_regs
		}) | 
		({32{regs_addr == 17}} & {
			8'dx, 
			8'dx, 
			8'dx, 
			6'dx, act_type_regs
		});
	
	// �Ĵ�����������
	always @(posedge clk)
	begin
		if(regs_en & (~is_write))
			regs_region_rd_out <= # simulation_delay regs_region_rd_out_nxt;
	end
	
	// 0x00, 1~0
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			{rst_cal_path_kernal_buf_reg, rst_linear_pars_buf_reg} <= 2'b00;
		else
			{rst_cal_path_kernal_buf_reg, rst_linear_pars_buf_reg} <= # simulation_delay 
				{2{regs_en & regs_wen[0] & (regs_addr == 0)}} & regs_din[1:0];
	end
	
	// 0x00, 9~8
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			{wt_req_dsc_dma_blk_start_reg, rd_req_dsc_dma_blk_start_reg} <= 2'b00;
		else
			{wt_req_dsc_dma_blk_start_reg, rd_req_dsc_dma_blk_start_reg} <= # simulation_delay 
				{2{regs_en & regs_wen[1] & (regs_addr == 0)}} & regs_din[9:8];
	end
	
	// 0x00, 17~16
	always @(posedge clk)
	begin
		{wt_req_dsc_dma_blk_idle_reg, rd_req_dsc_dma_blk_idle_reg} <= # simulation_delay 
			{wt_req_dsc_dma_blk_idle, rd_req_dsc_dma_blk_idle};
	end
	
	// 0x04, 0
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			global_itr_en_reg <= 1'b0;
		else if(regs_en & regs_wen[0] & (regs_addr == 1))
			global_itr_en_reg <= # simulation_delay regs_din[0];
	end
	
	// 0x04, 10~8
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			itr_en_vec_regs <= 3'b000;
		else if(regs_en & regs_wen[1] & (regs_addr == 1))
			itr_en_vec_regs <= # simulation_delay regs_din[10:8];
	end
	
	// 0x08, 0
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			global_itr_flag_reg <= 1'b0;
		else if((regs_en & regs_wen[0] & (regs_addr == 2)) | (~global_itr_flag_reg))
			global_itr_flag_reg <= # simulation_delay 
				(~(regs_en & regs_wen[0] & (regs_addr == 2))) & // ����ȫ���жϱ�־
				((|(itr_req & itr_en_vec_regs)) & global_itr_en_reg);
	end
	
	// 0x08, 10~8
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			itr_flag_vec_regs <= 3'b000;
		else if(global_itr_req)
			itr_flag_vec_regs <= # simulation_delay itr_req & itr_en_vec_regs;
	end
	
	// 0x0C, 31~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 3))
			wt_req_itr_th_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 3))
			wt_req_itr_th_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 3))
			wt_req_itr_th_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 3))
			wt_req_itr_th_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x10, 0
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			en_conv_cal_reg <= 1'b0;
		else if(regs_en & regs_wen[0] & (regs_addr == 4))
			en_conv_cal_reg <= # simulation_delay regs_din[0];
	end
	
	// 0x14, 0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 5))
			kernal_type_reg <= # simulation_delay regs_din[0];
	end
	
	// 0x14, 11~8
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 5))
			padding_en_regs <= # simulation_delay regs_din[11:8];
	end
	
	// 0x18, 31~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 6))
			rd_req_buf_baseaddr_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 6))
			rd_req_buf_baseaddr_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 6))
			rd_req_buf_baseaddr_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 6))
			rd_req_buf_baseaddr_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x1C, 31~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 7))
			rd_req_n_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 7))
			rd_req_n_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 7))
			rd_req_n_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 7))
			rd_req_n_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x20, 31~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 8))
			wt_req_buf_baseaddr_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 8))
			wt_req_buf_baseaddr_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 8))
			wt_req_buf_baseaddr_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 8))
			wt_req_buf_baseaddr_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x24, 31~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 9))
			wt_req_n_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 9))
			wt_req_n_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 9))
			wt_req_n_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 9))
			wt_req_n_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x28, 15~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 10))
			feature_map_w_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 10))
			feature_map_w_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	
	// 0x28, 31~16
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 10))
			feature_map_h_regs[7:0] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 10))
			feature_map_h_regs[15:8] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x2C, 15~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 11))
			feature_map_chn_n_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 11))
			feature_map_chn_n_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	
	// 0x2C, 31~16
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 11))
			kernal_n_regs[7:0] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 11))
			kernal_n_regs[15:8] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x30, 31~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 12))
			act_rate_c_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 12))
			act_rate_c_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 12))
			act_rate_c_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 12))
			act_rate_c_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x34, 31~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 13))
			act_rate_c_regs[39:32] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 13))
			act_rate_c_regs[47:40] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 13))
			act_rate_c_regs[55:48] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 13))
			act_rate_c_regs[63:56] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x3C, 15~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 15))
			o_ft_map_w_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 15))
			o_ft_map_w_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	
	// 0x3C, 31~16
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 15))
			o_ft_map_h_regs[7:0] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 15))
			o_ft_map_h_regs[15:8] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x40, 2~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 16))
			horizontal_step_regs <= # simulation_delay regs_din[2:0];
	end
	
	// 0x40, 10~8
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 16))
			vertical_step_regs <= # simulation_delay regs_din[10:8];
	end
	
	// 0x40, 16
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 16))
			step_type_reg <= # simulation_delay regs_din[16];
	end
	
	// 0x44, 1~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 17))
			act_type_regs <= # simulation_delay regs_din[1:0];
	end
	
	// 0x48, 10~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 18))
			non_ln_act_lut_waddr_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 18))
			non_ln_act_lut_waddr_regs[10:8] <= # simulation_delay regs_din[10:8];
	end
	
	// 0x48, 31~16
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 18))
			non_ln_act_lut_din_regs[7:0] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 18))
			non_ln_act_lut_din_regs[15:8] <= # simulation_delay regs_din[31:24];
	end
	
	// Sigmoid/Tanh���ұ�дʹ��
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			non_ln_act_lut_wen_reg <= 1'b0;
		else
			non_ln_act_lut_wen_reg <= # simulation_delay regs_en & (|regs_wen) & (regs_addr == 18);
	end
	
	// �жϷ�����
    itr_generator #(
        .pulse_w(10),
        .simulation_delay(simulation_delay)
    )itr_generator_u(
        .clk(clk),
        .rst_n(rst_n),
        
        .itr_org(global_itr_req),
        
        .itr(itr)
    );
	
endmodule
