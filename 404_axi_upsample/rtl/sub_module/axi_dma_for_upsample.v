`timescale 1ns / 1ps
/********************************************************************
��ģ��: �ϲ�����Ԫ������/�������ͼDMA

����:
32λ��ַ64λ���ݵ�AXI����

��ѡ��AXI������buffer�����AXI��ͻ���Ĵ���Ч��
�ڲ���AXIд����buffer�����AXIдͻ���Ĵ���Ч��

ע�⣺
��֧�ַǶ��봫��
��֧��4KB�߽籣��, ���뱣֤����/�������ͼ�������׵�ַ�ܱ�(axi_max_burst_len*8)����, �Ӷ�ȷ��ÿ��ͻ�����䲻���Խ4KB�߽�
��������������ͼ��������˵, ���뱣֤ÿ�����ݰ����ֽ�����д�����ֽ���һ��

Э��:
BLK CTRL
AXIS MASTER/SLAVE
AXI MASTER

����: �¼�ҫ
����: 2024/11/25
********************************************************************/


module axi_dma_for_upsample #(
	parameter integer axi_max_burst_len = 32, // AXI�������ͻ������(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter integer axi_addr_outstanding = 4, // AXI��ַ�������(1~16)
	parameter integer max_rd_btt = 4 * 512, // ���Ķ��������ֽ���(256 | 512 | 1024 | ...)
	parameter integer axi_rdata_buffer_depth = 512, // AXI������buffer���(0 -> ������ | 512 | 1024 | ...)
	parameter integer max_wt_btt = 4 * 512, // ����д�������ֽ���(256 | 512 | 1024 | ...)
	parameter integer axi_wdata_buffer_depth = 512, // AXIд����buffer���(512 | 1024 | ...)
	parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
	input wire clk,
	input wire rst_n,
	
	// ����ʱ����
	input wire[31:0] in_ft_map_buf_baseaddr, // ��������ͼ����������ַ
	input wire[31:0] in_ft_map_buf_len, // ��������ͼ���������� - 1(���ֽڼ�)
	input wire[31:0] out_ft_map_buf_baseaddr, // �������ͼ����������ַ
	input wire[31:0] out_ft_map_buf_len, // �������ͼ���������� - 1(���ֽڼ�)
	
	// MM2S����
	input wire mm2s_start,
	output wire mm2s_idle,
	output wire mm2s_done,
	// S2MM����
	input wire s2mm_start,
	output wire s2mm_idle,
	output wire s2mm_done,
	
	// ����������ͼ������
	input wire[63:0] s_axis_out_ft_map_data,
	input wire[7:0] s_axis_out_ft_map_keep,
	input wire s_axis_out_ft_map_last,
	input wire s_axis_out_ft_map_valid,
	output wire s_axis_out_ft_map_ready,
	
	// �������������ͼ������
	output wire[63:0] m_axis_in_ft_map_data,
	output wire[7:0] m_axis_in_ft_map_keep,
	output wire m_axis_in_ft_map_last,
	output wire m_axis_in_ft_map_valid,
	input wire m_axis_in_ft_map_ready,
	
	// AXI����
	// AR
    output wire[31:0] m_axi_araddr,
    output wire[1:0] m_axi_arburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_arlen,
    output wire[2:0] m_axi_arsize, // const -> 3'b011
    output wire[3:0] m_axis_arcache, // const -> 4'b0011
    output wire m_axi_arvalid,
    input wire m_axi_arready,
	// AW
    output wire[31:0] m_axi_awaddr,
    output wire[1:0] m_axi_awburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_awlen,
    output wire[2:0] m_axi_awsize, // const -> 3'b011
    output wire[3:0] m_axis_awcache, // const -> 4'b0011
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    // B
    input wire[1:0] m_axi_bresp, // ignored
    input wire m_axi_bvalid,
    output wire m_axi_bready, // const -> 1'b1
    // R
    input wire[63:0] m_axi_rdata,
    input wire[1:0] m_axi_rresp, // ignored
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output wire m_axi_rready,
    // W
    output wire[63:0] m_axi_wdata,
    output wire[7:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready
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
	
	/** ���� **/
	// ������buffer�洢������ͻ������
	localparam integer MAX_RDATA_BUFFER_STORE_N = (axi_rdata_buffer_depth == 0) ? 4:(axi_rdata_buffer_depth / axi_max_burst_len);
	// д����buffer�洢�����дͻ������
	localparam integer MAX_WDATA_BUFFER_STORE_N = axi_wdata_buffer_depth / axi_max_burst_len;
	
	/** ���̿��� **/
	reg mm2s_idle_reg; // MM2Sͨ�����б�־
	reg s2mm_idle_reg; // S2MMͨ�����б�־
	
	assign mm2s_idle = mm2s_idle_reg;
	assign s2mm_idle = s2mm_idle_reg;
	
	// MM2Sͨ�����б�־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			mm2s_idle_reg <= 1'b1;
		else
			mm2s_idle_reg <= # simulation_delay mm2s_idle ? (~mm2s_start):mm2s_done;
	end
	// S2MMͨ�����б�־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			s2mm_idle_reg <= 1'b1;
		else
			s2mm_idle_reg <= # simulation_delay s2mm_idle ? (~s2mm_start):s2mm_done;
	end
	
	/** AXI����ַͨ�� **/
	reg[31:0] ar_addr; // ����ַ
	reg[clogb2(max_rd_btt/8-1):0] remaining_rd_trans_n; // ʣ���(��������� - 1)
	reg to_suppress_ar_addr; // ��ѹ����ַͨ��(��־)
	reg[clogb2(max_rd_btt/8-1):0] rd_trans_n_latched; // �����(��������� - 1)
	reg[7:0] last_rd_trans_keep_latched; // ��������1�ζ������keep�ź�
	wire last_rd_burst; // ���1�ζ�ͻ��(��־)
	wire rdata_buffer_allow_arvalid; // ������buffer�������ַͨ����Ч(��־)
	wire raddr_outstanding_ctrl_allow_arvalid; // ����ַoutstanding�����������ַͨ����Ч(��־)
	// ����ַ����
	reg[clogb2(axi_addr_outstanding):0] ar_outstanding_n; // ����Ķ��������
	reg ar_outstanding_full_n; // ����ַ��������־
	wire on_pre_launch_rd_burst; // Ԥ�����µĶ�ͻ��(ָʾ)
	wire on_rdata_return; // ��ͻ�������ѷ���(ָʾ)
	
	assign m_axi_araddr = ar_addr;
	assign m_axi_arburst = 2'b01;
	assign m_axi_arlen = last_rd_burst ? remaining_rd_trans_n:(axi_max_burst_len - 1);
	assign m_axi_arsize = 3'b011;
	assign m_axis_arcache = 4'b0011;
	assign m_axi_arvalid = (~mm2s_idle) & (~to_suppress_ar_addr) & rdata_buffer_allow_arvalid & raddr_outstanding_ctrl_allow_arvalid;
	
	assign last_rd_burst = remaining_rd_trans_n <= (axi_max_burst_len - 1);
	assign raddr_outstanding_ctrl_allow_arvalid = ar_outstanding_full_n;
	assign on_pre_launch_rd_burst = m_axi_arvalid & m_axi_arready;
	assign on_rdata_return = m_axi_rvalid & m_axi_rready & m_axi_rlast;
	
	// ����ַ
	always @(posedge clk)
	begin
		if((mm2s_idle & mm2s_start) | on_pre_launch_rd_burst)
			ar_addr <= # simulation_delay mm2s_idle ? in_ft_map_buf_baseaddr:(ar_addr + (axi_max_burst_len * 8));
	end
	
	// ʣ���(��������� - 1)
	always @(posedge clk)
	begin
		if((mm2s_idle & mm2s_start) | on_pre_launch_rd_burst)
			remaining_rd_trans_n <= # simulation_delay mm2s_idle ? 
				in_ft_map_buf_len[3+clogb2(max_rd_btt/8-1):3]:(remaining_rd_trans_n - axi_max_burst_len);
	end
	
	// ��ѹ����ַͨ��(��־)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			to_suppress_ar_addr <= 1'b0;
		else
			to_suppress_ar_addr <= # simulation_delay to_suppress_ar_addr ? 
				(~mm2s_done):(on_pre_launch_rd_burst & last_rd_burst);
	end
	
	// �����(��������� - 1)
	always @(posedge clk)
	begin
		if(mm2s_idle & mm2s_start)
			rd_trans_n_latched <= # simulation_delay in_ft_map_buf_len[3+clogb2(max_rd_btt/8-1):3];
	end
	
	// ��������1�ζ������keep�ź�
	always @(posedge clk)
	begin
		if(mm2s_idle & mm2s_start)
			/*
			case(in_ft_map_buf_len[2:0])
				3'd0: last_rd_trans_keep_latched <= # simulation_delay 8'b0000_0001;
				3'd1: last_rd_trans_keep_latched <= # simulation_delay 8'b0000_0011;
				3'd2: last_rd_trans_keep_latched <= # simulation_delay 8'b0000_0111;
				3'd3: last_rd_trans_keep_latched <= # simulation_delay 8'b0000_1111;
				3'd4: last_rd_trans_keep_latched <= # simulation_delay 8'b0001_1111;
				3'd5: last_rd_trans_keep_latched <= # simulation_delay 8'b0011_1111;
				3'd6: last_rd_trans_keep_latched <= # simulation_delay 8'b0111_1111;
				3'd7: last_rd_trans_keep_latched <= # simulation_delay 8'b1111_1111;
				default: last_rd_trans_keep_latched <= # simulation_delay 8'bxxxx_xxxx;
			endcase
			*/
			last_rd_trans_keep_latched <= # simulation_delay {
				in_ft_map_buf_len[2] & in_ft_map_buf_len[1] & in_ft_map_buf_len[0],
				in_ft_map_buf_len[2] & in_ft_map_buf_len[1],
				in_ft_map_buf_len[2] & (in_ft_map_buf_len[1] | in_ft_map_buf_len[0]),
				in_ft_map_buf_len[2],
				in_ft_map_buf_len[2] | (in_ft_map_buf_len[1] & in_ft_map_buf_len[0]),
				in_ft_map_buf_len[2] | in_ft_map_buf_len[1],
				in_ft_map_buf_len[2] | in_ft_map_buf_len[1] | in_ft_map_buf_len[0],
				1'b1
			};
	end
	
	// ����Ķ��������
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			ar_outstanding_n <= 0;
		else if(on_pre_launch_rd_burst ^ on_rdata_return)
			ar_outstanding_n <= # simulation_delay 
				on_pre_launch_rd_burst ? (ar_outstanding_n + 1):(ar_outstanding_n - 1);
	end
	// ����ַ��������־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			ar_outstanding_full_n <= 1'b1;
		else if(on_pre_launch_rd_burst ^ on_rdata_return)
			ar_outstanding_full_n <= # simulation_delay 
				// on_pre_launch_rd_burst ? (ar_outstanding_n != (axi_addr_outstanding - 1)):1'b1
				(~on_pre_launch_rd_burst) | (ar_outstanding_n != (axi_addr_outstanding - 1));
	end
	
	/** AXI������ͨ�� **/
	reg[clogb2(MAX_RDATA_BUFFER_STORE_N):0] pre_launched_rd_burst_n; // Ԥ�����Ķ�ͻ������
	reg rdata_buffer_pre_full_n; // ������bufferԤ��(��־)
	wire on_rd_burst_complete; // ��ͻ�����(ָʾ)
	reg[clogb2(max_rd_btt/8-1):0] rd_trans_out_cnt; // ������Ķ�����������(������)
	// ������bufferд�˿�
	wire rdata_buffer_wen;
	wire rdata_buffer_full_n;
	wire[63:0] rdata_buffer_din;
	wire rdata_buffer_din_burst_last; // ָʾ��ͻ�����1������
	// ������buffer���˿�
	wire rdata_buffer_ren;
	wire rdata_buffer_empty_n;
	wire[63:0] rdata_buffer_dout;
	wire[7:0] rdata_buffer_dout_keep;
	wire rdata_buffer_dout_ft_last; // ָʾ����ͼ���1������
	wire rdata_buffer_dout_burst_last; // ָʾ��ͻ�����1������
	
	assign mm2s_done = m_axis_in_ft_map_valid & m_axis_in_ft_map_ready & m_axis_in_ft_map_last;
	
	assign m_axis_in_ft_map_data = rdata_buffer_dout;
	assign m_axis_in_ft_map_keep = rdata_buffer_dout_keep;
	assign m_axis_in_ft_map_last = rdata_buffer_dout_ft_last;
	assign m_axis_in_ft_map_valid = rdata_buffer_empty_n;
	assign rdata_buffer_ren = m_axis_in_ft_map_ready;
	
	assign rdata_buffer_allow_arvalid = (axi_rdata_buffer_depth == 0) | rdata_buffer_pre_full_n;
	
	assign on_rd_burst_complete = rdata_buffer_ren & rdata_buffer_empty_n & rdata_buffer_dout_burst_last;
	
	assign rdata_buffer_wen = m_axi_rvalid;
	assign m_axi_rready = rdata_buffer_full_n;
	assign rdata_buffer_din = m_axi_rdata;
	assign rdata_buffer_din_burst_last = m_axi_rlast;
	
	// rdata_buffer_dout_ft_last ? last_rd_trans_keep_latched:8'hff
	assign rdata_buffer_dout_keep = {8{~rdata_buffer_dout_ft_last}} | last_rd_trans_keep_latched;
	assign rdata_buffer_dout_ft_last = rd_trans_out_cnt == rd_trans_n_latched;
	
	// Ԥ�����Ķ�ͻ������
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			pre_launched_rd_burst_n <= 0;
		else if(on_pre_launch_rd_burst ^ on_rd_burst_complete)
			pre_launched_rd_burst_n <= # simulation_delay 
				on_pre_launch_rd_burst ? (pre_launched_rd_burst_n + 1):(pre_launched_rd_burst_n - 1);
	end
	// ������bufferԤ��(��־)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rdata_buffer_pre_full_n <= 1'b1;
		else if(on_pre_launch_rd_burst ^ on_rd_burst_complete)
			rdata_buffer_pre_full_n <= # simulation_delay 
				// on_pre_launch_rd_burst ? (pre_launched_rd_burst_n != (MAX_RDATA_BUFFER_STORE_N - 1)):1'b1
				(~on_pre_launch_rd_burst) | (pre_launched_rd_burst_n != (MAX_RDATA_BUFFER_STORE_N - 1));
	end
	
	// ������Ķ�����������(������)
	always @(posedge clk)
	begin
		if((mm2s_idle & mm2s_start) | (m_axis_in_ft_map_valid & m_axis_in_ft_map_ready))
			// mm2s_idle ? 0:(rd_trans_out_cnt + 1)
			rd_trans_out_cnt <= # simulation_delay {(clogb2(max_rd_btt/8-1)+1){~mm2s_idle}} & (rd_trans_out_cnt + 1);
	end
	
	// ������buffer
	generate
		if(axi_rdata_buffer_depth > 0)
		begin
			ram_fifo_wrapper #(
				.fwft_mode("true"),
				.ram_type("bram"),
				.en_bram_reg("false"),
				.fifo_depth(axi_rdata_buffer_depth),
				.fifo_data_width(64 + 1),
				.full_assert_polarity("low"),
				.empty_assert_polarity("low"),
				.almost_full_assert_polarity("no"),
				.almost_empty_assert_polarity("no"),
				.en_data_cnt("false"),
				.almost_full_th(),
				.almost_empty_th(),
				.simulation_delay(simulation_delay)
			)rdata_buffer_fifo(
				.clk(clk),
				.rst_n(rst_n),
				
				.fifo_wen(rdata_buffer_wen),
				.fifo_din({rdata_buffer_din_burst_last, rdata_buffer_din}),
				.fifo_full_n(rdata_buffer_full_n),
				
				.fifo_ren(rdata_buffer_ren),
				.fifo_dout({rdata_buffer_dout_burst_last, rdata_buffer_dout}),
				.fifo_empty_n(rdata_buffer_empty_n)
			);
		end
		else
		begin
			assign {rdata_buffer_dout_burst_last, rdata_buffer_dout} = {rdata_buffer_din_burst_last, rdata_buffer_din};
			assign rdata_buffer_empty_n = rdata_buffer_wen;
			assign rdata_buffer_full_n = rdata_buffer_ren;
		end
	endgenerate
	
	/** AXIд��ַͨ�� **/
	reg[31:0] aw_addr; // д��ַ
	reg[clogb2(max_wt_btt/8-1):0] remaining_wt_trans_n; // ʣ���(д������� - 1)
	reg to_suppress_aw_addr; // ��ѹд��ַͨ��(��־)
	wire last_wt_burst; // ���1��дͻ��(��־)
	wire wdata_buffer_allow_awvalid; // д����buffer����д��ַͨ����Ч(��־)
	wire waddr_outstanding_ctrl_allow_awvalid; // д��ַoutstanding��������д��ַͨ����Ч(��־)
	// д��ַ����
	reg[clogb2(axi_addr_outstanding):0] aw_outstanding_n; // �����д�������
	reg aw_outstanding_full_n; // д��ַ��������־
	wire on_pre_launch_wt_burst; // Ԥ�����µ�дͻ��(ָʾ)
	wire on_bresp_gotten; // �õ�д��Ӧ(ָʾ)
	
	assign m_axi_awaddr = aw_addr;
	assign m_axi_awburst = 2'b01;
	assign m_axi_awlen = last_wt_burst ? remaining_wt_trans_n:(axi_max_burst_len - 1);
	assign m_axi_awsize = 3'b011;
	assign m_axis_awcache = 4'b0011;
	assign m_axi_awvalid = (~s2mm_idle) & (~to_suppress_aw_addr) & wdata_buffer_allow_awvalid & waddr_outstanding_ctrl_allow_awvalid;
	
	assign last_wt_burst = remaining_wt_trans_n <= (axi_max_burst_len - 1);
	assign waddr_outstanding_ctrl_allow_awvalid = aw_outstanding_full_n;
	assign on_pre_launch_wt_burst = m_axi_awvalid & m_axi_awready;
	assign on_bresp_gotten = m_axi_bvalid;
	
	// д��ַ
	always @(posedge clk)
	begin
		if((s2mm_idle & s2mm_start) | on_pre_launch_wt_burst)
			aw_addr <= # simulation_delay s2mm_idle ? out_ft_map_buf_baseaddr:(aw_addr + (axi_max_burst_len * 8));
	end
	
	// ʣ���(д������� - 1)
	always @(posedge clk)
	begin
		if((s2mm_idle & s2mm_start) | on_pre_launch_wt_burst)
			remaining_wt_trans_n <= # simulation_delay s2mm_idle ? 
				out_ft_map_buf_len[3+clogb2(max_wt_btt/8-1):3]:(remaining_wt_trans_n - axi_max_burst_len);
	end
	
	// ��ѹд��ַͨ��(��־)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			to_suppress_aw_addr <= 1'b0;
		else
			to_suppress_aw_addr <= # simulation_delay to_suppress_aw_addr ? 
				(~s2mm_done):(on_pre_launch_wt_burst & last_wt_burst);
	end
	
	// �����д�������
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			aw_outstanding_n <= 0;
		else if(on_pre_launch_wt_burst ^ on_bresp_gotten)
			aw_outstanding_n <= # simulation_delay 
				on_pre_launch_wt_burst ? (aw_outstanding_n + 1):(aw_outstanding_n - 1);
	end
	// д��ַ��������־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			aw_outstanding_full_n <= 1'b1;
		else if(on_pre_launch_wt_burst ^ on_bresp_gotten)
			aw_outstanding_full_n <= # simulation_delay 
				// on_pre_launch_wt_burst ? (aw_outstanding_n != (axi_addr_outstanding - 1)):1'b1
				(~on_pre_launch_wt_burst) | (aw_outstanding_n != (axi_addr_outstanding - 1));
	end
	
	/** AXIд��Ӧͨ�� **/
	// дͻ����Ϣfifoд�˿�
	wire wburst_msg_fifo_wen;
	wire wburst_msg_fifo_din; // ָʾ����д�������1��дͻ��
	// дͻ����Ϣfifo���˿�
	wire wburst_msg_fifo_ren;
	wire wburst_msg_fifo_dout; // ָʾ����д�������1��дͻ��
	
	assign s2mm_done = m_axi_bvalid & wburst_msg_fifo_dout;
	assign m_axi_bready = 1'b1;
	
	assign wburst_msg_fifo_wen = on_pre_launch_wt_burst;
	assign wburst_msg_fifo_din = last_wt_burst;
	assign wburst_msg_fifo_ren = m_axi_bvalid;
	
	// дͻ����Ϣfifo
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.fifo_depth(axi_addr_outstanding), // �����Ϊ1Ҳ�������
		.fifo_data_width(1),
		.almost_full_th(),
		.almost_empty_th(),
		.simulation_delay(simulation_delay)
	)wburst_msg_fifo(
		.clk(clk),
		.rst_n(rst_n),
		
		.fifo_wen(wburst_msg_fifo_wen),
		.fifo_din(wburst_msg_fifo_din),
		.fifo_full_n(),
		
		.fifo_ren(wburst_msg_fifo_ren),
		.fifo_dout(wburst_msg_fifo_dout),
		.fifo_empty_n()
	);
	
	/** AXIд����ͨ�� **/
	wire on_wdata_buffered; // ����1��дͻ����Ӧ������(ָʾ)
	reg[clogb2(MAX_WDATA_BUFFER_STORE_N):0] wdata_buffer_store_n; // д����buffer�ѻ����дͻ������
	reg wdata_buffer_has_stored_burst; // д����buffer����ǿձ�־
	reg[clogb2(axi_max_burst_len-1):0] wdata_tid_in_burst; // д������дͻ���еı��(������)
	// д����bufferд�˿�
	wire wdata_buffer_wen;
	wire wdata_buffer_full_n;
	wire[63:0] wdata_buffer_din;
	wire[2:0] wdata_buffer_din_kid; // �ֽ�ʹ��������
	wire wdata_buffer_din_last; // ָʾдͻ�����1������
	// д����buffer���˿�
	wire wdata_buffer_ren;
	wire wdata_buffer_empty_n;
	wire[63:0] wdata_buffer_dout;
	wire[2:0] wdata_buffer_dout_kid; // �ֽ�ʹ��������
	wire wdata_buffer_dout_last; // ָʾдͻ�����1������
	
	assign m_axi_wdata = wdata_buffer_dout;
	/*
	(wdata_buffer_dout_kid == 3'd0) ? 8'b0000_0001:
	(wdata_buffer_dout_kid == 3'd1) ? 8'b0000_0011:
	(wdata_buffer_dout_kid == 3'd2) ? 8'b0000_0111:
	(wdata_buffer_dout_kid == 3'd3) ? 8'b0000_1111:
	(wdata_buffer_dout_kid == 3'd4) ? 8'b0001_1111:
	(wdata_buffer_dout_kid == 3'd5) ? 8'b0011_1111:
	(wdata_buffer_dout_kid == 3'd6) ? 8'b0111_1111:
	                                  8'b1111_1111;
	*/
	assign m_axi_wstrb = {
		wdata_buffer_dout_kid[2] & wdata_buffer_dout_kid[1] & wdata_buffer_dout_kid[0],
		wdata_buffer_dout_kid[2] & wdata_buffer_dout_kid[1],
		wdata_buffer_dout_kid[2] & (wdata_buffer_dout_kid[1] | wdata_buffer_dout_kid[0]),
		wdata_buffer_dout_kid[2],
		wdata_buffer_dout_kid[2] | (wdata_buffer_dout_kid[1] & wdata_buffer_dout_kid[0]),
		wdata_buffer_dout_kid[2] | wdata_buffer_dout_kid[1],
		wdata_buffer_dout_kid[2] | wdata_buffer_dout_kid[1] | wdata_buffer_dout_kid[0],
		1'b1
	};
	assign m_axi_wlast = wdata_buffer_dout_last;
	assign m_axi_wvalid = wdata_buffer_empty_n;
	assign wdata_buffer_ren = m_axi_wready;
	
	assign wdata_buffer_allow_awvalid = wdata_buffer_has_stored_burst;
	
	assign on_wdata_buffered = wdata_buffer_wen & wdata_buffer_full_n & wdata_buffer_din_last;
	
	assign wdata_buffer_wen = s_axis_out_ft_map_valid;
	assign s_axis_out_ft_map_ready = wdata_buffer_full_n;
	assign wdata_buffer_din = s_axis_out_ft_map_data;
	/*
	s_axis_out_ft_map_keep[7] ? 3'd7:
	s_axis_out_ft_map_keep[6] ? 3'd6:
	s_axis_out_ft_map_keep[5] ? 3'd5:
	s_axis_out_ft_map_keep[4] ? 3'd4:
	s_axis_out_ft_map_keep[3] ? 3'd3:
	s_axis_out_ft_map_keep[2] ? 3'd2:
	s_axis_out_ft_map_keep[1] ? 3'd1:
	                           3'd0;
	*/
	assign wdata_buffer_din_kid = {
		s_axis_out_ft_map_keep[4], 
		s_axis_out_ft_map_keep[6] | ((~s_axis_out_ft_map_keep[4]) & s_axis_out_ft_map_keep[2]),
		((~s_axis_out_ft_map_keep[2]) & s_axis_out_ft_map_keep[1]) | 
			((~s_axis_out_ft_map_keep[4]) & s_axis_out_ft_map_keep[3]) | 
			((~s_axis_out_ft_map_keep[6]) & s_axis_out_ft_map_keep[5]) | 
			s_axis_out_ft_map_keep[7]
	};
	assign wdata_buffer_din_last = (wdata_tid_in_burst == (axi_max_burst_len - 1)) | s_axis_out_ft_map_last;
	
	// д����buffer�ѻ����дͻ������
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wdata_buffer_store_n <= 0;
		else if(on_wdata_buffered ^ on_pre_launch_wt_burst)
			wdata_buffer_store_n <= # simulation_delay on_pre_launch_wt_burst ? (wdata_buffer_store_n - 1):(wdata_buffer_store_n + 1);
	end
	// д����buffer����ǿձ�־
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wdata_buffer_has_stored_burst <= 1'b0;
		else if(on_wdata_buffered ^ on_pre_launch_wt_burst)
			// on_pre_launch_wt_burst ? (wdata_buffer_store_n != 1):1'b1
			wdata_buffer_has_stored_burst <= # simulation_delay (~on_pre_launch_wt_burst) | (wdata_buffer_store_n != 1);
	end
	
	// д������дͻ���еı��(������)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wdata_tid_in_burst <= 0;
		else if(wdata_buffer_wen & wdata_buffer_full_n)
			// s_axis_out_ft_map_last ? 0:(wdata_tid_in_burst + 1)
			wdata_tid_in_burst <= # simulation_delay {(clogb2(axi_max_burst_len-1)+1){~s_axis_out_ft_map_last}} & (wdata_tid_in_burst + 1);
	end
	
	// д����buffer
	ram_fifo_wrapper #(
		.fwft_mode("true"),
		.ram_type("bram"),
		.en_bram_reg("false"),
		.fifo_depth(axi_wdata_buffer_depth),
		.fifo_data_width(64 + 3 + 1),
		.full_assert_polarity("low"),
		.empty_assert_polarity("low"),
		.almost_full_assert_polarity("no"),
		.almost_empty_assert_polarity("no"),
		.en_data_cnt("false"),
		.almost_full_th(),
		.almost_empty_th(),
		.simulation_delay(simulation_delay)
	)wdata_buffer_fifo(
		.clk(clk),
		.rst_n(rst_n),
		
		.fifo_wen(wdata_buffer_wen),
		.fifo_din({wdata_buffer_din_last, wdata_buffer_din_kid, wdata_buffer_din}),
		.fifo_full_n(wdata_buffer_full_n),
		
		.fifo_ren(wdata_buffer_ren),
		.fifo_dout({wdata_buffer_dout_last, wdata_buffer_dout_kid, wdata_buffer_dout}),
		.fifo_empty_n(wdata_buffer_empty_n)
	);
    
endmodule
