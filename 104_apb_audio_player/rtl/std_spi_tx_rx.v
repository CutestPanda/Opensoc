`timescale 1ns / 1ps
/********************************************************************
��ģ��: ��׼SPI������

����: 
ʹ�÷���/����fifo�ı�׼SPI������
MSB First
֧��ȫ˫��/��˫��/����
SPI��������λ��->8bit

ע�⣺
�շ�fifo��Ϊ��׼fifo
����Ҫʹ�ñ�׼SPI�ĵ���ģʽ, �̶���SPI���䷽�򼴿�

Э��:
FIFO READ/WRITE
SPI MASTER

����: �¼�ҫ
����: 2023/11/17
********************************************************************/


module std_spi_tx_rx #(
    parameter integer spi_slave_n = 1, // SPI�ӻ�����
    parameter integer spi_sck_div_n = 2, // SPIʱ�ӷ�Ƶϵ��(�����ܱ�2����, ��>=2)
    parameter integer spi_cpol = 0, // SPI����ʱ�ĵ�ƽ״̬(0->�͵�ƽ 1->�ߵ�ƽ)
    parameter integer spi_cpha = 0, // SPI���ݲ�����(0->������ 1->ż����)
    parameter integer tx_user_data_width = 0, // ����ʱ�û�����λ��(0~32)
    parameter tx_user_default_v = 16'hff_ff, // ����ʱ�û�����Ĭ��ֵ
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire spi_clk,
    input wire spi_resetn,
	// AMBA����ʱ�Ӻ͸�λ
	input wire amba_clk,
	input wire amba_resetn,
	
	// ����ʱ����
	input wire[clogb2(spi_slave_n-1):0] rx_tx_sel, // �ӻ�ѡ��
	input wire[1:0] rx_tx_dire, // ���䷽��(2'b11->�շ� 2'b10->���� 2'b01->���� 2'b00->����)
    
    // ����fifo���˿�
    output wire tx_fifo_ren,
    input wire tx_fifo_empty,
    input wire[7:0] tx_fifo_dout,
    input wire tx_fifo_dout_ss,
    input wire[tx_user_data_width-1:0] tx_fifo_dout_user,
    // ����fifoд�˿�
    output wire rx_fifo_wen,
    input wire rx_fifo_full,
    output wire[7:0] rx_fifo_din,
    
    // �������շ�ָʾ
    output wire rx_tx_start,
    output wire rx_tx_done,
    output wire rx_tx_idle,
    output wire rx_err, // �������ָʾ
    
    // SPI�����ӿ�
    output wire[spi_slave_n-1:0] spi_ss,
    output wire spi_sck,
    output wire spi_mosi,
    input wire spi_miso,
    output wire[tx_user_data_width-1:0] spi_user
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
    localparam integer sck_cnt_range = spi_sck_div_n/2-1; // SPIʱ�ӷ�Ƶ������������Χ(0~sck_cnt_range)
    
    /** SPI�շ����� **/
    // SPI����״̬����
    reg rx_tx_done_reg; // ����SPI�������(����)
    reg rx_tx_idle_reg; // SPI�������(��־)
    
    reg is_now_transmitting; // ��ǰ�Ƿ����ڴ���(��־)
    reg now_transmission_start; // ��ǰ���俪ʼ(����)
    wire now_transmission_end; // ��ǰ�������(����)
    
    assign tx_fifo_ren = (~is_now_transmitting) | (is_now_transmitting & now_transmission_end);
    
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
        begin
            rx_tx_done_reg <= 1'b0;
            rx_tx_idle_reg <= 1'b1;
            is_now_transmitting <= 1'b0;
            now_transmission_start <= 1'b0;
        end
        else
        begin
            # simulation_delay;
            
            rx_tx_done_reg <= now_transmission_end;
            rx_tx_idle_reg <= tx_fifo_empty & (rx_tx_idle_reg | ((~rx_tx_idle_reg) & now_transmission_end));
            is_now_transmitting <= is_now_transmitting ? (~(now_transmission_end & tx_fifo_empty)):(~tx_fifo_empty);
            now_transmission_start <= (~tx_fifo_empty) & ((~is_now_transmitting) | (is_now_transmitting & now_transmission_end));
        end
    end
    
    // SPIƬѡ
    reg[spi_slave_n-1:0] spi_ss_regs; // SPIƬѡ�ź�
    reg spi_ss_to_high; // SPIƬѡ����(��־)
    reg ss_latched; // ����ĵ�ǰbyte������SS��ƽ
    
    assign spi_ss = spi_ss_regs;
    
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
            spi_ss_to_high <= 1'b0;
        else
            # simulation_delay spi_ss_to_high <= is_now_transmitting & now_transmission_end & tx_fifo_empty;
    end
    
    genvar spi_slave_i;
    generate
        if(spi_slave_n == 1)
        begin
            always @(posedge spi_clk or negedge spi_resetn)
            begin
                if(~spi_resetn)
                    spi_ss_regs <= 1'b1;
                else if((~is_now_transmitting) & (~tx_fifo_empty))
                    # simulation_delay spi_ss_regs <= 1'b0;
                else if(spi_ss_to_high)
                    # simulation_delay spi_ss_regs <= ss_latched;
            end
        end
        else
        begin
            for(spi_slave_i = 0;spi_slave_i < spi_slave_n;spi_slave_i = spi_slave_i + 1)
            begin
                always @(posedge spi_clk or negedge spi_resetn)
                begin
                    if(~spi_resetn)
                        spi_ss_regs[spi_slave_i] <= 1'b1;
                    else if((~is_now_transmitting) & (~tx_fifo_empty))
                        # simulation_delay spi_ss_regs[spi_slave_i] <= (rx_tx_sel != spi_slave_i);
                    else if(spi_ss_to_high)
                        # simulation_delay spi_ss_regs[spi_slave_i] <= (rx_tx_sel != spi_slave_i) | ss_latched;
                end
            end
        end
    endgenerate
    
    // SPI�û�����
    reg tx_fifo_ren_d;
    reg[tx_user_data_width-1:0] spi_user_regs;
    
    assign spi_user = spi_user_regs;
    
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
            tx_fifo_ren_d <= 1'b0;
        else
            tx_fifo_ren_d <= tx_fifo_ren & (~tx_fifo_empty);
        
        if(~spi_resetn)
            spi_user_regs <= tx_user_default_v;
        else if(tx_fifo_ren_d)
            # simulation_delay spi_user_regs <= tx_fifo_dout_user;
        else if(spi_ss_to_high)
            # simulation_delay spi_user_regs <= tx_user_default_v;
    end
    
    // SPI��������
    reg[7:0] tx_byte; // �������ֽ�(����)
    wire tx_byte_load; // �������ֽ�(���ر�־)
    wire tx_byte_shift; // �������ֽ�(��λ��־)
    wire tx_bit_valid; // ����λ������Ϣ��Ч(��־)
    reg[2:0] tx_bit_cnt; // ��ǰ����λ���(������)
    reg tx_bit_last; // ��ǰ���͵������1bit(��־)
    
    assign spi_mosi = tx_byte[7];
    
    assign now_transmission_end = tx_bit_last & tx_byte_shift;
    assign tx_byte_load = now_transmission_start;
    assign tx_bit_valid = is_now_transmitting & (~now_transmission_start);
    
    always @(posedge spi_clk)
    begin
        if(tx_byte_load) // ����
            # simulation_delay ss_latched <= tx_fifo_dout_ss;
    end
    
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
            tx_bit_last <= 1'b0;
        else if(tx_byte_load) // ����
            # simulation_delay tx_bit_last <= 1'b0;
        else if(tx_byte_shift) // ��λ
            # simulation_delay tx_bit_last <= tx_bit_cnt == 3'd1;
    end
    
    always @(posedge spi_clk)
    begin
        if(tx_byte_load) // ����
        begin
            # simulation_delay;
            
            tx_byte <= rx_tx_dire[0] ? tx_fifo_dout:8'dx;
            tx_bit_cnt <= 3'd7;
        end
        else if(tx_byte_shift) // ��λ
        begin
            # simulation_delay;
            
            tx_byte <= {tx_byte[6:0], 1'bx};
            tx_bit_cnt <= tx_bit_cnt - 3'd1;
        end
    end
    
    // ����SPIʱ��
    reg sck_reg; // SPIʱ��
    reg[clogb2(sck_cnt_range):0] sck_div_cnt; // SPIʱ�ӷ�Ƶ������
    wire sck_toggle; // SPIʱ���źŷ�ת��־
    
    assign spi_sck = sck_reg;
    
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
            sck_reg <= spi_cpol;
        else if(sck_toggle)
            # simulation_delay sck_reg <= ~sck_reg;
    end
    
    generate
        wire sck_div_cnt_rst; // SPIʱ�ӷ�Ƶ����������(��־)
        
        assign tx_byte_shift = (spi_sck != (spi_cpol ^ spi_cpha)) & is_now_transmitting & (sck_toggle | (spi_cpha & sck_div_cnt_rst & (spi_sck == spi_cpol)));
        
        if(spi_cpha) // ż���ز���
            assign sck_toggle = tx_byte_load | (sck_div_cnt_rst & (~((spi_sck == spi_cpol) & tx_bit_last)));
        else // �����ز���
            assign sck_toggle = sck_div_cnt_rst;
        
        if(sck_cnt_range > 0)
        begin
            assign sck_div_cnt_rst = sck_div_cnt == sck_cnt_range;
        
            always @(posedge spi_clk or negedge spi_resetn)
            begin
                if(~spi_resetn)
                    sck_div_cnt <= 0;
                else if(~tx_bit_valid) // ������Ϣ��Ч -> SPIʱ�ӷ�Ƶ����������
                    # simulation_delay sck_div_cnt <= 0;
                else
                    # simulation_delay sck_div_cnt <= sck_div_cnt_rst ? 0:(sck_div_cnt + 1);
            end
        end
        else
            assign sck_div_cnt_rst = tx_bit_valid;
    endgenerate
    
    // SPI��������
    reg rx_fifo_wen_reg; // ����fifoдʹ��
    reg[7:0] rx_fifo_din_regs; // ����fifoд����
    
    wire rx_byte_shift; // �����ֽ�(��λ��־)
    reg[7:0] rx_byte; // �����ֽ�(����)
    reg[2:0] rx_bit_cnt; // ��ǰ����λ���(������)
    reg rx_bit_last; // ��ǰ���յ������1bit(��־)
    
    assign rx_fifo_wen = rx_fifo_wen_reg;
    assign rx_fifo_din = rx_fifo_din_regs;
    
    assign rx_byte_shift = (spi_sck == (spi_cpol ^ spi_cpha)) & is_now_transmitting & sck_toggle & rx_tx_dire[1];
    
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
            rx_fifo_wen_reg <= 1'b0;
        else
            # simulation_delay rx_fifo_wen_reg <= rx_bit_last & rx_byte_shift;
    end
    
    always @(posedge spi_clk)
    begin
        # simulation_delay rx_fifo_din_regs <= {rx_byte[6:0], spi_miso};
    end
    
    always @(posedge spi_clk)
    begin
        if(rx_byte_shift)
            # simulation_delay rx_byte <= {rx_byte[6:0], spi_miso};
    end
    
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
        begin
            rx_bit_cnt <= 3'b000;
            rx_bit_last <= 1'b0;
        end
        else if(rx_byte_shift)
        begin
            # simulation_delay;
            
            rx_bit_cnt <= rx_bit_cnt + 3'b001;
            rx_bit_last <= rx_bit_cnt == 3'b110;
        end
    end
    
    // ���ɽ������ָʾ
    reg rx_err_reg; // �������ָʾ
    
    always @(posedge spi_clk or negedge spi_resetn)
    begin
        if(~spi_resetn)
            rx_err_reg <= 1'b0;
        else
            # simulation_delay rx_err_reg <= rx_fifo_wen & rx_fifo_full;
    end
	
	/** �������շ�ָʾ **/
	reg rx_tx_idle_d; // �ӳ�1clk���շ�������(��־)
	reg rx_tx_idle_d2; // �ӳ�2clk���շ�������(��־)
	
	assign rx_tx_idle = rx_tx_idle_d2;
	
	// ��ʱ����: ����ͬ����!
	async_handshake #(
		.simulation_delay(simulation_delay)
	)async_handshake_u0(
		.clk1(spi_clk),
		.rst_n1(spi_resetn),
		
		.clk2(amba_clk),
		.rst_n2(amba_resetn),
		
		.req1(now_transmission_start),
		.busy(),
		
		.req2(rx_tx_start)
	);
	// ��ʱ����: ����ͬ����!
	async_handshake #(
		.simulation_delay(simulation_delay)
	)async_handshake_u1(
		.clk1(spi_clk),
		.rst_n1(spi_resetn),
		
		.clk2(amba_clk),
		.rst_n2(amba_resetn),
		
		.req1(rx_tx_done_reg),
		.busy(),
		
		.req2(rx_tx_done)
	);
	// ��ʱ����: ����ͬ����!
	async_handshake #(
		.simulation_delay(simulation_delay)
	)async_handshake_u2(
		.clk1(spi_clk),
		.rst_n1(spi_resetn),
		
		.clk2(amba_clk),
		.rst_n2(amba_resetn),
		
		.req1(rx_err_reg),
		.busy(),
		
		.req2(rx_err)
	);
	
	// ���շ�������(��־)��2��
	// ��ʱ����: rx_tx_idle_reg -> rx_tx_idle_d!
	always @(posedge amba_clk or negedge amba_resetn)
	begin
		if(~amba_resetn)
			{rx_tx_idle_d2, rx_tx_idle_d} <= 2'b11;
		else
			# simulation_delay {rx_tx_idle_d2, rx_tx_idle_d} <= {rx_tx_idle_d, rx_tx_idle_reg};
	end

endmodule
