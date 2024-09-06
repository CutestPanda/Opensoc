`timescale 1ns / 1ps
/********************************************************************
��ģ��: ����AXIЭ���Bram������

����: 
AXI-Bram������
��ѡBram���ӳ�Ϊ1clk��2clk
��ѡ������fifo����߶������Ч��

ע�⣺
Bramλ��̶�Ϊ32bit
�����ȸ�����/д��ַ(AR/AW), �ٸ�����/д����(R/W), ��֧�ֵ�ַ����(outstanding)
��֧�ַǶ����խ������

Э��:
AXI SLAVE
MEM READ/WRITE

����: �¼�ҫ
����: 2023/12/09
********************************************************************/


module axi_bram_ctrler #(
    parameter integer bram_depth = 2048, // Bram���
    parameter integer bram_read_la = 1, // Bram���ӳ�(1 | 2)
    parameter en_read_buf_fifo = "true", // �Ƿ�ʹ�ö�����fifo
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // AXI SLAVE
    // ����ַͨ��
    input wire[31:0] s_axi_araddr, // assumed to be aligned
    // 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
    input wire[1:0] s_axi_arburst,
    input wire[3:0] s_axi_arcache, // ignored
    // �̶����� -> len <= 16; �ػ����� -> len = 2 | 4 | 8 | 16
    input wire[7:0] s_axi_arlen,
    input wire s_axi_arlock, // ignored
    input wire[2:0] s_axi_arprot, // ignored
    input wire[2:0] s_axi_arsize, // assumed to be 3'b010(4 byte)
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    // д��ַͨ��
    input wire[31:0] s_axi_awaddr, // assumed to be aligned
    // 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
    input wire[1:0] s_axi_awburst,
    input wire[3:0] s_axi_awcache, // ignored
    // �̶����� -> len <= 16; �ػ����� -> len = 2 | 4 | 8 | 16
    input wire[7:0] s_axi_awlen,
    input wire s_axi_awlock, // ignored
    input wire[2:0] s_axi_awprot, // ignored
    input wire[2:0] s_axi_awsize, // assumed to be 3'b010(4 byte)
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    // д��Ӧͨ��
    output wire[1:0] s_axi_bresp, // const -> 2'b00(OKAY)
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    // ������ͨ��
    output wire[31:0] s_axi_rdata,
    output wire s_axi_rlast,
    output wire[1:0] s_axi_rresp, // const -> 2'b00(OKAY)
    output wire s_axi_rvalid,
    input wire s_axi_rready,
    // д����ͨ��
    input wire[31:0] s_axi_wdata,
    input wire s_axi_wlast,
    input wire[3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    
    // �洢���ӿ�
    output wire bram_clk,
    output wire bram_rst,
    output wire bram_en,
    output wire[3:0] bram_wen,
    output wire[29:0] bram_addr,
    output wire[31:0] bram_din,
    input wire[31:0] bram_dout,
    
    // AXI-Bram��������������
    output wire[1:0] axi_bram_ctrler_err // {��֧�ֵķǶ��봫��, ��֧�ֵ�խ������}
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
    // bram������״̬����
    localparam bram_ctrler_status_wait_rw_req = 2'b00; // �ȴ���д����
    localparam bram_ctrler_status_reading = 2'b01; // ���ڶ�����
    localparam bram_ctrler_status_writing = 2'b10; // ����д����
    localparam bram_ctrler_status_send_wresp = 2'b11; // ���ڷ���д��Ӧ
    // �ػ�ͻ����ַ���䳤��
    localparam wrap_length_8byte = 2'b00; // 8byte����ػ�ͻ��
    localparam wrap_length_16byte = 2'b01; // 16byte����ػ�ͻ��
    localparam wrap_length_32byte = 2'b10; // 32byte����ػ�ͻ��
    localparam wrap_length_64byte = 2'b11; // 64byte����ػ�ͻ��
    // ͻ������
    localparam burst_fixed = 2'b00;
    localparam burst_incr = 2'b01;
    localparam burst_wrap = 2'b10;
    localparam burst_reserved = 2'b11;
    
    /** ������fifo(��ѡ) **/
    wire read_buf_fifo_wen;
    wire[32:0] read_buf_fifo_din;
    wire read_buf_fifo_almost_full_n;
    wire read_buf_fifo_ren;
    wire[32:0] read_buf_fifo_dout;
    wire read_buf_fifo_empty_n;
    
    assign read_buf_fifo_ren = s_axi_rready;
    
    ram_fifo_wrapper #(
        .fwft_mode("true"),
        .ram_type("lutram"),
        .en_bram_reg(),
        .fifo_depth(32),
        .fifo_data_width(33),
        .full_assert_polarity("low"),
        .empty_assert_polarity("low"),
        .almost_full_assert_polarity("low"),
        .almost_empty_assert_polarity("no"),
        .en_data_cnt("false"),
        .almost_full_th(30 - bram_read_la),
        .almost_empty_th(),
        .simulation_delay(simulation_delay)
    )read_buf_fifo(
        .clk(clk),
        .rst_n(rst_n),
        .fifo_wen(read_buf_fifo_wen),
        .fifo_din(read_buf_fifo_din),
        .fifo_almost_full_n(read_buf_fifo_almost_full_n),
        .fifo_ren(read_buf_fifo_ren),
        .fifo_dout(read_buf_fifo_dout),
        .fifo_empty_n(read_buf_fifo_empty_n)
    );
	
	/** AXI��д�ٲ� **/
	wire axi_rd_req; // AXI������
	wire axi_wt_req; // AXIд����
	wire axi_rd_grant; // AXI����Ȩ
	wire axi_wt_grant; // AXIд��Ȩ
	wire axi_rw_arb_valid; // AXI��д�ٲý����Ч
	reg axi_rw_arb_valid_d; // �ӳ�1clk��AXI��д�ٲý����Ч
	
	// �ӳ�1clk��AXI��д�ٲý����Ч
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			axi_rw_arb_valid_d <= 1'b0;
		else
			# simulation_delay axi_rw_arb_valid_d <= axi_rw_arb_valid;
	end
	
	round_robin_arbitrator #(
		.chn_n(2),
		.simulation_delay(simulation_delay)
	)round_robin_arbitrator_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.req({axi_rd_req, axi_wt_req}),
		.grant({axi_rd_grant, axi_wt_grant}),
		.sel(),
		.arb_valid(axi_rw_arb_valid)
	);
    
    /** AXI�ӻ��ӿ� **/
    // ��д���̿���״̬��
    reg[1:0] bram_ctrler_status; // bram������״̬
    reg[1:0] s_axi_aw_ar_ready_reg;
    reg s_axi_bvalid_reg;
    reg s_axi_wready_reg;
    reg now_rw; // ��ǰ���ڶ�д����(��־)
    
	assign {s_axi_awready, s_axi_arready} = s_axi_aw_ar_ready_reg;
	
	assign s_axi_bresp = 2'b00;
    assign s_axi_bvalid = s_axi_bvalid_reg;
	
    assign s_axi_rdata = (en_read_buf_fifo == "true") ? read_buf_fifo_dout[31:0]:bram_dout;
	assign s_axi_rresp = 2'b00;
	
	assign s_axi_wready = s_axi_wready_reg;
	
    assign read_buf_fifo_din[31:0] = bram_dout;
	
	assign axi_rd_req = s_axi_arvalid & (bram_ctrler_status == bram_ctrler_status_wait_rw_req) & (~axi_rw_arb_valid_d);
	assign axi_wt_req = s_axi_awvalid & (bram_ctrler_status == bram_ctrler_status_wait_rw_req) & (~axi_rw_arb_valid_d);
    
    // bram������״̬
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
        begin
            bram_ctrler_status <= bram_ctrler_status_wait_rw_req;
            s_axi_aw_ar_ready_reg <= 2'b00;
            s_axi_bvalid_reg <= 1'b0;
            s_axi_wready_reg <= 1'b0;
            now_rw <= 1'b0;
        end
        else
        begin
            # simulation_delay;
            
            case(bram_ctrler_status)
                bram_ctrler_status_wait_rw_req: // �ȴ���д����
                begin
					if((s_axi_arvalid & s_axi_arready) | (s_axi_awvalid & s_axi_awready))
						bram_ctrler_status <= (s_axi_arvalid & s_axi_arready) ? 
							bram_ctrler_status_reading:bram_ctrler_status_writing;
                    
                    s_axi_aw_ar_ready_reg <= ((s_axi_arvalid & s_axi_arready) | (s_axi_awvalid & s_axi_awready)) ? 
						2'b00:{axi_wt_grant, axi_rd_grant};
                    s_axi_bvalid_reg <= 1'b0;
                    s_axi_wready_reg <= s_axi_awvalid & s_axi_awready;
                    now_rw <= (s_axi_arvalid & s_axi_arready) | (s_axi_awvalid & s_axi_awready);
                end
                bram_ctrler_status_reading: // ���ڶ�����
                begin
                    bram_ctrler_status <= (s_axi_rvalid & s_axi_rready & s_axi_rlast) ? bram_ctrler_status_wait_rw_req:bram_ctrler_status_reading;
                    s_axi_aw_ar_ready_reg <= 2'b00;
                    s_axi_bvalid_reg <= 1'b0;
                    s_axi_wready_reg <= 1'b0;
                    now_rw <= ~(s_axi_rvalid & s_axi_rready & s_axi_rlast);
                end
                bram_ctrler_status_writing: // ����д����
                begin
                    bram_ctrler_status <= (s_axi_wvalid & s_axi_wlast) ? bram_ctrler_status_send_wresp:bram_ctrler_status_writing;
                    s_axi_aw_ar_ready_reg <= 2'b00;
                    s_axi_bvalid_reg <= s_axi_wvalid & s_axi_wlast;
                    s_axi_wready_reg <= ~(s_axi_wvalid & s_axi_wlast);
                    now_rw <= ~(s_axi_wvalid & s_axi_wlast);
                end
                bram_ctrler_status_send_wresp: // ���ڷ���д��Ӧ
                begin
                    bram_ctrler_status <= s_axi_bready ? bram_ctrler_status_wait_rw_req:bram_ctrler_status_send_wresp;
                    s_axi_aw_ar_ready_reg <= 2'b00;
                    s_axi_bvalid_reg <= ~s_axi_bready;
                    s_axi_wready_reg <= 1'b0;
                    now_rw <= 1'b0;
                end
                default:
                begin
                    bram_ctrler_status <= bram_ctrler_status_wait_rw_req;
                    s_axi_aw_ar_ready_reg <= 2'b00;
                    s_axi_bvalid_reg <= 1'b0;
                    s_axi_wready_reg <= 1'b0;
                    now_rw <= 1'b0;
                end
            endcase
        end
    end
    
    // �����д������Ϣ
    reg[clogb2(bram_depth - 1):0] aw_ar_addr_latched; // �����Bram����ʼ��ַ
    reg[1:0] aw_ar_burst_latched; // 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
    reg[7:0] aw_ar_len_latched; // �̶����� -> len <= 16; �ػ����� -> len = 2 | 4 | 8 | 16
    reg is_read_latched; // �Ƿ��ͻ��
    reg[1:0] wrap_addr_length; // �ػ�ͻ����ַ���� = 2'b00 -> 8 | 2'b01 -> 16 | 2'b10 -> 32 | 2'b11 -> 64
    
    always @(posedge clk)
    begin
        # simulation_delay;
        
        if((bram_ctrler_status == bram_ctrler_status_wait_rw_req) & ((s_axi_arvalid & s_axi_arready) | (s_axi_awvalid & s_axi_awready))) // ���񵽶�д����
        begin
            if(s_axi_arvalid & s_axi_arready) // ����������
            begin
                aw_ar_addr_latched <= s_axi_araddr[clogb2(bram_depth * 4 - 1):2];
                aw_ar_burst_latched <= s_axi_arburst;
                aw_ar_len_latched <= s_axi_arlen;
                is_read_latched <= 1'b1;
                wrap_addr_length <= {s_axi_arlen[2], s_axi_arlen[3] | ({s_axi_arlen[2], s_axi_arlen[1]} == 2'b01)};
            end
            else // ����д����
            begin
                aw_ar_addr_latched <= s_axi_awaddr[clogb2(bram_depth * 4 - 1):2];
                aw_ar_burst_latched <= s_axi_awburst;
                aw_ar_len_latched <= s_axi_awlen;
                is_read_latched <= 1'b0;
                wrap_addr_length <= {s_axi_awlen[2], s_axi_awlen[3] | ({s_axi_awlen[2], s_axi_awlen[1]} == 2'b01)};
            end
        end
    end
    
    // ���俪ʼ����
    reg rw_start_pulse;
    reg rw_start_pulse_d;
    
    always @(posedge clk)
    begin
        # simulation_delay;
        
        rw_start_pulse <= (bram_ctrler_status == bram_ctrler_status_wait_rw_req) & (s_axi_arvalid & s_axi_arready);
        rw_start_pulse_d <= rw_start_pulse;
    end
    
    // ������last�ź�
    // ���뵽MEM������
    reg s_axi_rlast_reg;
    reg[7:0] read_transfers_cnt; // ��ǰ����ɶ�����(������)
    // ���뵽MEM����ַ
    reg s_axi_rlast_reg_pre;
    reg[7:0] read_transfers_cnt_pre; // ��ǰ����ɶ�����(Ԥ������)
    
    wire bram_raddr_vld_w; // Bram����ַ��Ч
    reg bram_raddr_vld_d; // �ӳ�1clk��Bram����ַ��Ч
    
    assign s_axi_rlast = (en_read_buf_fifo == "true") ? read_buf_fifo_dout[32]:s_axi_rlast_reg;
    assign read_buf_fifo_din[32] = s_axi_rlast_reg;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            bram_raddr_vld_d <= 1'b0;
        else
            # simulation_delay bram_raddr_vld_d <= bram_raddr_vld_w;
    end
    
    always @(posedge clk)
    begin
        # simulation_delay;
        
        if((bram_ctrler_status == bram_ctrler_status_wait_rw_req) & (s_axi_arvalid & s_axi_arready)) // ���������
        begin
            s_axi_rlast_reg <= s_axi_arlen == 8'd0;
            read_transfers_cnt <= 8'd1;
        end
        else if((en_read_buf_fifo == "true") ? ((~s_axi_rlast_reg) & read_buf_fifo_wen):(s_axi_rvalid & s_axi_rready)) // ����
        begin
            s_axi_rlast_reg <= read_transfers_cnt == aw_ar_len_latched;
            read_transfers_cnt <= read_transfers_cnt + 8'd1;
        end
        
        if((bram_ctrler_status == bram_ctrler_status_wait_rw_req) & (s_axi_arvalid & s_axi_arready)) // ���������
        begin
            s_axi_rlast_reg_pre <= s_axi_arlen == 8'd0;
            read_transfers_cnt_pre <= 8'd1;
        end
        else if((~s_axi_rlast_reg_pre) & bram_raddr_vld_w) // ����
        begin
            s_axi_rlast_reg_pre <= read_transfers_cnt_pre == aw_ar_len_latched;
            read_transfers_cnt_pre <= read_transfers_cnt_pre + 8'd1;
        end
    end
    
    // ������valid�ź�
    reg s_axi_rvalid_reg;
    
    assign s_axi_rvalid = (en_read_buf_fifo == "true") ? read_buf_fifo_empty_n:s_axi_rvalid_reg;
    assign read_buf_fifo_wen = s_axi_rvalid_reg;
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            s_axi_rvalid_reg <= 1'b0;
        else
        begin
            # simulation_delay;
            
            if(en_read_buf_fifo == "true")
            begin
                s_axi_rvalid_reg <= now_rw & 
                    ((~s_axi_rlast_reg) | ((bram_read_la == 1) ? rw_start_pulse:rw_start_pulse_d)) &
                    ((bram_read_la == 1) ? bram_raddr_vld_w:bram_raddr_vld_d);
            end
            else
            begin
                if(~s_axi_rvalid_reg)
                    s_axi_rvalid_reg <= now_rw & 
                        ((bram_read_la == 1) ? bram_raddr_vld_w:bram_raddr_vld_d);
                else
                    s_axi_rvalid_reg <= ~s_axi_rready;
            end
        end
    end
    
    /** �洢���ӿ� **/
    // Bramʱ�Ӻ͸�λ
    assign bram_clk = clk;
    assign bram_rst = ~rst_n;
    
    // ����Bram��д��ַ
    reg[clogb2(bram_depth - 1):0] bram_incr_addr; // INCRͻ���µ�Bram��д��ַ
    reg[clogb2(bram_depth - 1):0] bram_wrap_addr; // WRAPͻ���µ�Bram��д��ַ
    reg bram_raddr_vld; // Bram����ַ��Ч
    
    assign bram_addr = ((aw_ar_burst_latched == burst_fixed) | (aw_ar_burst_latched == burst_reserved)) ? 
        aw_ar_addr_latched:((aw_ar_burst_latched == burst_incr) ? bram_incr_addr:bram_wrap_addr);
    assign bram_raddr_vld_w = bram_raddr_vld;
    
    always @(posedge clk)
    begin
        # simulation_delay;
        
        if((bram_ctrler_status == bram_ctrler_status_wait_rw_req) & ((s_axi_arvalid & s_axi_arready) | (s_axi_awvalid & s_axi_awready))) // ����
        begin
            bram_incr_addr <= (s_axi_arvalid & s_axi_arready) ? s_axi_araddr[clogb2(bram_depth * 4 - 1):2]:s_axi_awaddr[clogb2(bram_depth * 4 - 1):2];
            bram_wrap_addr <= (s_axi_arvalid & s_axi_arready) ? s_axi_araddr[clogb2(bram_depth * 4 - 1):2]:s_axi_awaddr[clogb2(bram_depth * 4 - 1):2];
        end
        else if(now_rw &
            (is_read_latched ? & ((en_read_buf_fifo == "true") ? ((~s_axi_rlast_reg_pre) & read_buf_fifo_almost_full_n):((~s_axi_rlast_reg) & s_axi_rvalid & s_axi_rready))
                :s_axi_wvalid)) // ����
        begin
            bram_incr_addr <= bram_incr_addr + 1;
            
            case(wrap_addr_length)
                wrap_length_8byte: // �ػ�ͻ����ַ����8�ֽ�
                begin
                    if(bram_wrap_addr[0] == 1'b1)
                        bram_wrap_addr <= {bram_wrap_addr[clogb2(bram_depth - 1):1], 1'b0};
                    else
                        bram_wrap_addr <= bram_wrap_addr + 1;
                end
                wrap_length_16byte: // �ػ�ͻ����ַ����16�ֽ�
                begin
                    if(bram_wrap_addr[1:0] == 2'b11)
                        bram_wrap_addr <= {bram_wrap_addr[clogb2(bram_depth - 1):2], 2'b00};
                    else
                        bram_wrap_addr <= bram_wrap_addr + 1;
                end
                wrap_length_32byte: // �ػ�ͻ����ַ����32�ֽ�
                begin
                    if(bram_wrap_addr[2:0] == 3'b111)
                        bram_wrap_addr <= {bram_wrap_addr[clogb2(bram_depth - 1):3], 3'b000};
                    else
                        bram_wrap_addr <= bram_wrap_addr + 1;
                end
                wrap_length_64byte: // �ػ�ͻ����ַ����64�ֽ�
                begin
                    if(bram_wrap_addr[3:0] == 4'b1111)
                        bram_wrap_addr <= {bram_wrap_addr[clogb2(bram_depth - 1):4], 4'b0000};
                    else
                        bram_wrap_addr <= bram_wrap_addr + 1;
                end
                default:
                    bram_wrap_addr <= {(clogb2(bram_depth - 1)+1){1'bx}};
            endcase
        end
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            bram_raddr_vld <= 1'b0;
        else
        begin
            # simulation_delay;
            
            if((bram_ctrler_status == bram_ctrler_status_wait_rw_req) & (s_axi_arvalid & s_axi_arready))
                bram_raddr_vld <= 1'b1;
            else
                bram_raddr_vld <= now_rw & is_read_latched &
                    ((en_read_buf_fifo == "true") ? ((~s_axi_rlast_reg_pre) & read_buf_fifo_almost_full_n):((~s_axi_rlast_reg) & s_axi_rvalid & s_axi_rready));
        end
    end
    
    // ����Bram��дʹ�ܺ�д����
    assign bram_en = bram_raddr_vld | (s_axi_wvalid & s_axi_wready);
    assign bram_wen = (s_axi_wvalid & s_axi_wready) ? s_axi_wstrb:4'b0000;
    assign bram_din = s_axi_wdata;
    
    /** �����־ **/
    reg[1:0] axi_bram_ctrler_err_regs; // {��֧�ֵķǶ��봫��, ��֧�ֵ�խ������}
    
    assign axi_bram_ctrler_err = axi_bram_ctrler_err_regs;
    
	// ��֧�ֵķǶ��봫��
	always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            axi_bram_ctrler_err_regs[1] <= 1'b0;
        else if((s_axi_arvalid & s_axi_arready) | (s_axi_awvalid & s_axi_awready))
        begin
			# simulation_delay axi_bram_ctrler_err_regs[1] <= (s_axi_arvalid & s_axi_arready) ? 
				(s_axi_araddr[1:0] != 2'b00):(s_axi_awaddr[1:0] != 2'b00);
        end
    end
	// ��֧�ֵ�խ������
	always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            axi_bram_ctrler_err_regs[0] <= 1'b0;
        else if((s_axi_arvalid & s_axi_arready) | (s_axi_awvalid & s_axi_awready))
        begin
			# simulation_delay axi_bram_ctrler_err_regs[0] <= (s_axi_arvalid & s_axi_arready) ? 
				(s_axi_arsize != 3'b010):(s_axi_awsize != 3'b010);
        end
    end

endmodule
