`timescale 1ns / 1ps
/********************************************************************
��ģ��: ���ػ���Ԫ�ļĴ������ýӿ�

����:
�Ĵ���->
    ƫ����  |    ����                        |   ��д����    |        ��ע
    0x00    0:����DMA�Ķ�ͨ��                      WO        д�üĴ����Ҹ�λΪ1'b1ʱִ������
	        1:����DMA��дͨ��                      WO        д�üĴ����Ҹ�λΪ1'b1ʱִ������
			8:DMA��ͨ�����б�־                    RO
			9:DMAдͨ�����б�־                    RO
	0x04    31~0:��������ͼ����������ַ            RW
	0x08    31~0:��������ͼ���������� - 1          RW        ���ֽڼ�
	0x0C    31~0:�������ͼ����������ַ            RW
	0x10    31~0:�������ͼ���������� - 1          RW        ���ֽڼ�
	0x14    0:ȫ���ж�ʹ��                         RW
			8:DMA������ж�ʹ��                    RW
	        9:DMAд����ж�ʹ��                    RW
	0x18    0:ȫ���жϱ�־                         WC
			8:DMA������жϱ�־                    RO
	        9:DMAд����жϱ�־                    RO
	0x1C    15~0:����ͼͨ���� - 1                  RW
			31~16:����ͼ��� - 1                   RW
	0x20    15~0:����ͼ�߶� - 1                    RW

ע�⣺
��

Э��:
AXI-Lite SLAVE
BLK CTRL

����: �¼�ҫ
����: 2024/11/28
********************************************************************/


module reg_if_for_upsample #(
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
	
	// DMA��ͨ������
	output wire dma_mm2s_start,
	input wire dma_mm2s_idle,
	input wire dma_mm2s_done,
	// DMAдͨ������
	output wire dma_s2mm_start,
	input wire dma_s2mm_idle,
	input wire dma_s2mm_done,
	
	// ����ʱ����
	output wire[31:0] in_ft_map_buf_baseaddr, // ��������ͼ����������ַ
	output wire[31:0] in_ft_map_buf_len, // ��������ͼ���������� - 1(���ֽڼ�)
	output wire[31:0] out_ft_map_buf_baseaddr, // �������ͼ����������ַ
	output wire[31:0] out_ft_map_buf_len, // �������ͼ���������� - 1(���ֽڼ�)
	output wire[15:0] feature_map_chn_n, // ����ͼͨ���� - 1
	output wire[15:0] feature_map_w, // ����ͼ��� - 1
	output wire[15:0] feature_map_h, // ����ͼ�߶� - 1
	
	// �ж��ź�
	output wire itr
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
	localparam integer REGS_N = 9; // �Ĵ�������
	
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
	
	/** �жϿ��� **/
	wire global_itr_req; // ȫ���ж�����
	wire global_itr_en; // ȫ���ж�ʹ��
	wire global_itr_flag; // ȫ���жϱ�־
	wire[1:0] itr_en_vec; // �ж�ʹ������({DMAд����ж�ʹ��, DMA������ж�ʹ��})
	wire[1:0] itr_req_vec; // �ж���������({DMAд����ж�����, DMA������ж�����})
	
	assign global_itr_req = (|(itr_req_vec & itr_en_vec)) & global_itr_en & (~global_itr_flag);
	assign itr_req_vec = {dma_s2mm_done, dma_mm2s_done};
	
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
	
	/** �Ĵ����� **/
	// �Ĵ�����������
	wire[31:0] regs_region_rd_out_nxt;
	reg[31:0] regs_region_rd_out;
	// 0x00
	reg dma_mm2s_start_reg; // ����DMA�Ķ�ͨ��
	reg dma_s2mm_start_reg; // ����DMA��дͨ��
	reg dma_mm2s_idle_reg; // DMA��ͨ�����б�־
	reg dma_s2mm_idle_reg; // DMAдͨ�����б�־
	// 0x04
	reg[31:0] in_ft_map_buf_baseaddr_regs; // ��������ͼ����������ַ
	// 0x08
	reg[31:0] in_ft_map_buf_len_regs; // ��������ͼ���������� - 1(���ֽڼ�)
	// 0x0C
	reg[31:0] out_ft_map_buf_baseaddr_regs; // �������ͼ����������ַ
	// 0x10
	reg[31:0] out_ft_map_buf_len_regs; // �������ͼ���������� - 1(���ֽڼ�)
	// 0x14
	reg global_itr_en_reg; // ȫ���ж�ʹ��
	reg dma_mm2s_done_itr_en_reg; // DMA������ж�ʹ��
	reg dma_s2mm_done_itr_en_reg; // DMAд����ж�ʹ��
	// 0x18
	reg global_itr_flag_reg; // ȫ���жϱ�־
	reg dma_mm2s_done_itr_flag_reg; // DMA������жϱ�־
	reg dma_s2mm_done_itr_flag_reg; // DMAд����жϱ�־
	// 0x1C
	reg[15:0] feature_map_chn_n_regs; // ����ͼͨ���� - 1
	reg[15:0] feature_map_w_regs; // ����ͼ��� - 1
	// 0x20
	reg[15:0] feature_map_h_regs; // ����ͼ�߶� - 1
	
	assign dma_mm2s_start = dma_mm2s_start_reg;
	assign dma_s2mm_start = dma_s2mm_start_reg;
	
	assign in_ft_map_buf_baseaddr = in_ft_map_buf_baseaddr_regs;
	assign in_ft_map_buf_len = in_ft_map_buf_len_regs;
	assign out_ft_map_buf_baseaddr = out_ft_map_buf_baseaddr_regs;
	assign out_ft_map_buf_len = out_ft_map_buf_len_regs;
	assign feature_map_chn_n = feature_map_chn_n_regs;
	assign feature_map_w = feature_map_w_regs;
	assign feature_map_h = feature_map_h_regs;
	
	assign regs_dout = regs_region_rd_out;
	
	assign global_itr_en = global_itr_en_reg;
	assign global_itr_flag = global_itr_flag_reg;
	assign itr_en_vec = {dma_s2mm_done_itr_en_reg, dma_mm2s_done_itr_en_reg};
	
	assign regs_region_rd_out_nxt = 
		({32{regs_addr == 0}} & {
			8'dx, 
			8'dx, 
			6'dx, dma_s2mm_idle_reg, dma_mm2s_idle_reg, 
			8'dx
		}) | 
		({32{regs_addr == 1}} & {
			in_ft_map_buf_baseaddr_regs
		}) | 
		({32{regs_addr == 2}} & {
			in_ft_map_buf_len_regs
		}) | 
		({32{regs_addr == 3}} & {
			out_ft_map_buf_baseaddr_regs
		}) | 
		({32{regs_addr == 4}} & {
			out_ft_map_buf_len_regs
		}) | 
		({32{regs_addr == 5}} & {
			8'dx, 
			8'dx, 
			6'dx, dma_s2mm_done_itr_en_reg, dma_mm2s_done_itr_en_reg, 
			7'dx, global_itr_en_reg
		}) | 
		({32{regs_addr == 6}} & {
			8'dx, 
			8'dx, 
			6'dx, dma_s2mm_done_itr_flag_reg, dma_mm2s_done_itr_flag_reg, 
			7'dx, global_itr_flag_reg
		}) | 
		({32{regs_addr == 7}} & {
			feature_map_w_regs, 
			feature_map_chn_n_regs
		}) | 
		({32{regs_addr == 8}} & {
			16'dx, 
			feature_map_h_regs
		});
	
	// �Ĵ�����������
	always @(posedge clk)
	begin
		if(regs_en & (~is_write))
			regs_region_rd_out <= # simulation_delay regs_region_rd_out_nxt;
	end
	
	// ����DMA�Ķ�ͨ��, ����DMA��дͨ��
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			{dma_s2mm_start_reg, dma_mm2s_start_reg} <= 2'b00;
		else
			{dma_s2mm_start_reg, dma_mm2s_start_reg} <= # simulation_delay 
				{2{regs_en & regs_wen[0] & (regs_addr == 0)}} & regs_din[1:0];
	end
	// DMA��ͨ�����б�־, DMAдͨ�����б�־
	always @(posedge clk)
	begin
		{dma_s2mm_idle_reg, dma_mm2s_idle_reg} <= # simulation_delay 
			{dma_s2mm_idle, dma_mm2s_idle};
	end
	
	// ��������ͼ����������ַ
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 1))
			in_ft_map_buf_baseaddr_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 1))
			in_ft_map_buf_baseaddr_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 1))
			in_ft_map_buf_baseaddr_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 1))
			in_ft_map_buf_baseaddr_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// ��������ͼ���������� - 1(���ֽڼ�)
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 2))
			in_ft_map_buf_len_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 2))
			in_ft_map_buf_len_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 2))
			in_ft_map_buf_len_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 2))
			in_ft_map_buf_len_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// �������ͼ����������ַ
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 3))
			out_ft_map_buf_baseaddr_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 3))
			out_ft_map_buf_baseaddr_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 3))
			out_ft_map_buf_baseaddr_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 3))
			out_ft_map_buf_baseaddr_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// �������ͼ���������� - 1(���ֽڼ�)
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 4))
			out_ft_map_buf_len_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 4))
			out_ft_map_buf_len_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 4))
			out_ft_map_buf_len_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 4))
			out_ft_map_buf_len_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// ȫ���ж�ʹ��
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			global_itr_en_reg <= 1'b0;
		else if(regs_en & regs_wen[0] & (regs_addr == 5))
			global_itr_en_reg <= # simulation_delay regs_din[0];
	end
	// DMA������ж�ʹ��, DMAд����ж�ʹ��
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			{dma_s2mm_done_itr_en_reg, dma_mm2s_done_itr_en_reg} <= 2'b00;
		else if(regs_en & regs_wen[1] & (regs_addr == 5))
			{dma_s2mm_done_itr_en_reg, dma_mm2s_done_itr_en_reg} <= # simulation_delay 
				regs_din[9:8];
	end
	
	// ȫ���жϱ�־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			global_itr_flag_reg <= 1'b0;
		else if((regs_en & regs_wen[0] & (regs_addr == 6)) | (~global_itr_flag_reg))
			global_itr_flag_reg <= # simulation_delay 
				(~(regs_en & regs_wen[0] & (regs_addr == 6))) & // ����ȫ���жϱ�־
				((|(itr_req_vec & itr_en_vec)) & global_itr_en);
	end
	// DMA������жϱ�־, DMAд����жϱ�־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			{dma_s2mm_done_itr_flag_reg, dma_mm2s_done_itr_flag_reg} <= 2'b00;
		else if(global_itr_req)
			{dma_s2mm_done_itr_flag_reg, dma_mm2s_done_itr_flag_reg} <= # simulation_delay 
				itr_req_vec & itr_en_vec;
	end
	
	// ����ͼͨ���� - 1
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 7))
			feature_map_chn_n_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 7))
			feature_map_chn_n_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	// ����ͼ��� - 1
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 7))
			feature_map_w_regs[7:0] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 7))
			feature_map_w_regs[15:8] <= # simulation_delay regs_din[31:24];
	end
	
	// ����ͼ�߶� - 1
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 8))
			feature_map_h_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 8))
			feature_map_h_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	
endmodule
