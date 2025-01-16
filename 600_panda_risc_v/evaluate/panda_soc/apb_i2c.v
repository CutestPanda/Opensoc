`timescale 1ns / 1ps
/********************************************************************
��ģ��: ����APBЭ���I2C������

����: 
APB-I2C������
֧��I2C�շ��ж�
֧��7λ/10λ��ַ

����fifo���ݰ���ʽ��
    д���� -> last0 xxxx_xxx0 ��ַ�׶�
             [last0 xxxx_xxxx ��ַ�׶�(��10λ��ַʱ��Ҫ)]
             last0 xxxx_xxxx ���ݽ׶�
             ...
             last1 xxxx_xxxx ���ݽ׶�
    ������ -> last0 xxxx_xxx1 ��ַ�׶�
             [last0 xxxx_xxxx ��ַ�׶�(��10λ��ַʱ��Ҫ)]
             last1 8λ����ȡ�ֽ���

�Ĵ���->
    ƫ����  |    ����                     |   ��д����    |                 ��ע
    0x00    0:����fifo�Ƿ���                    R
            1:����fifoдʹ��                    W         д�üĴ����Ҹ�λΪ1'b1ʱ��������fifoдʹ��
            10~2:����fifoд����                 W                 {last(1bit), data(8bit)}
            16:����fifo�Ƿ��                   R
            17:����fifo��ʹ��                   W         д�üĴ����Ҹ�λΪ1'b1ʱ��������fifo��ʹ��
            25~18:����fifo������                R
    0x04    0:I2Cȫ���ж�ʹ��                   W
            8:I2C����ָ���ֽ����ж�ʹ��         W
            9:I2C�ӻ���Ӧ�����ж�ʹ��           W
            10:I2C����ָ���ֽ����ж�ʹ��        W
            11:I2C��������ж�ʹ��              W
    0x08    7~0:I2C�����ж��ֽ�����ֵ           W                  �����ֽ��� > ��ֵʱ�����ж�
            15~8:I2C�����ж��ֽ�����ֵ          W                  �����ֽ��� > ��ֵʱ�����ж�
			23~16:I2Cʱ�ӷ�Ƶϵ��               W                  ��Ƶ�� = (��Ƶϵ�� + 1) * 2
			                                                              ��Ƶϵ��Ӧ>=1
    0x0C    0:I2Cȫ���жϱ�־                  RWC                 �����жϷ�����������жϱ�־
            1:I2C����ָ���ֽ����жϱ�־         R
            2:I2C�ӻ���Ӧ�����жϱ�־           R
            3:I2C����ָ���ֽ����жϱ�־         R
            4:I2C��������жϱ�־               R
            19~8:I2C�����ֽ���                RWC                  ÿ������һ��I2C���ݰ������
            31~20:I2C�����ֽ���               RWC                  ÿ������һ��I2C���ݰ������

ע�⣺
I2C����/����ָ���ֽ����ж�ÿ������/����һ��I2C���ݰ����ж�
ÿ��I2C���ݰ����ܳ���15�ֽ�

Э��:
APB SLAVE
I2C MASTER

����: �¼�ҫ
����: 2024/06/14
********************************************************************/


module apb_i2c #(
    parameter integer addr_bits_n = 7, // ��ַλ��(7|10)
	parameter en_i2c_rx = "true", // �Ƿ�ʹ��i2c����
    parameter tx_rx_fifo_ram_type = "bram", // ���ͽ���fifo��RAM����(lutram|bram)
    parameter integer tx_fifo_depth = 1024, // ����fifo���(32|64|128|...)
    parameter integer rx_fifo_depth = 1024, // ����fifo���(32|64|128|...)
    parameter real simulation_delay = 1 // ������ʱ
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
    
    // I2C�����ӿ�
    // scl
    output wire scl_t, // 1'b1Ϊ����, 1'b0Ϊ���
    input wire scl_i,
    output wire scl_o,
    // sda
    output wire sda_t, // 1'b1Ϊ����, 1'b0Ϊ���
    input wire sda_i,
    output wire sda_o,
    
    // �ж��ź�
    output wire itr
);
	
    /** �շ�fifo **/
    // ����fifoд�˿�
    wire[8:0] tx_fifo_din;
    wire tx_fifo_wen;
    wire tx_fifo_full;
    // ����fifo���˿�
    wire tx_fifo_ren;
    wire tx_fifo_empty;
    wire[7:0] tx_fifo_dout;
    wire tx_fifo_dout_last;
    // ����fifoд�˿�
    wire rx_fifo_wen;
    wire rx_fifo_full;
    wire[7:0] rx_fifo_din;
    // ����fifo���˿�
    wire rx_fifo_ren;
    wire rx_fifo_empty;
    wire[7:0] rx_fifo_dout;
    
    // ����fifo
    ram_fifo_wrapper #(
        .fwft_mode("false"),
        .ram_type(tx_rx_fifo_ram_type),
        .en_bram_reg("false"),
        .fifo_depth(tx_fifo_depth),
        .fifo_data_width(9),
        .full_assert_polarity("high"),
        .empty_assert_polarity("high"),
        .almost_full_assert_polarity("no"),
        .almost_empty_assert_polarity("no"),
        .en_data_cnt("false"),
        .almost_full_th(),
        .almost_empty_th(),
        .simulation_delay(simulation_delay)
    )tx_fifo(
        .clk(clk),
        .rst_n(resetn),
        .fifo_wen(tx_fifo_wen),
        .fifo_din(tx_fifo_din),
        .fifo_full(tx_fifo_full),
        .fifo_ren(tx_fifo_ren),
        .fifo_dout({tx_fifo_dout_last, tx_fifo_dout}),
        .fifo_empty(tx_fifo_empty)
    );
    
    // ����fifo
	generate
		if(en_i2c_rx == "true")
		begin
			ram_fifo_wrapper #(
				.fwft_mode("false"),
				.ram_type(tx_rx_fifo_ram_type),
				.en_bram_reg("false"),
				.fifo_depth(rx_fifo_depth),
				.fifo_data_width(8),
				.full_assert_polarity("high"),
				.empty_assert_polarity("high"),
				.almost_full_assert_polarity("no"),
				.almost_empty_assert_polarity("no"),
				.en_data_cnt("false"),
				.almost_full_th(),
				.almost_empty_th(),
				.simulation_delay(simulation_delay)
			)rx_fifo(
				.clk(clk),
				.rst_n(resetn),
				.fifo_wen(rx_fifo_wen),
				.fifo_din(rx_fifo_din),
				.fifo_full(rx_fifo_full),
				.fifo_ren(rx_fifo_ren),
				.fifo_dout(rx_fifo_dout),
				.fifo_empty(rx_fifo_empty)
			);
		end
		else
		begin
			assign rx_fifo_full = 1'b0;
			
			assign rx_fifo_dout = 8'dx;
			assign rx_fifo_empty = 1'b1;
		end
	endgenerate
    
    /** �Ĵ����ӿں��жϴ��� **/
	// I2Cʱ�ӷ�Ƶϵ��
    wire[7:0] i2c_scl_div_rate;
    // I2C�������ָʾ
    wire i2c_tx_done;
    wire[3:0] i2c_tx_bytes_n;
    // I2C�������ָʾ
    wire i2c_rx_done;
    wire[3:0] i2c_rx_bytes_n;
    // I2C�ӻ���Ӧ����
    wire i2c_slave_resp_err;
    // I2C�������
    wire i2c_rx_overflow;
    
    // �Ĵ����ӿں��жϴ���
    regs_if_for_i2c #(
        .simulation_delay(simulation_delay)
    )regs_if_for_i2c_u(
        .clk(clk),
        .resetn(resetn),
        
        .paddr(paddr),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .pready_out(pready_out),
        .prdata_out(prdata_out),
        .pslverr_out(pslverr_out),
        
        .tx_fifo_wen(tx_fifo_wen),
        .tx_fifo_din(tx_fifo_din),
        .tx_fifo_full(tx_fifo_full),
        
        .rx_fifo_ren(rx_fifo_ren),
        .rx_fifo_dout(rx_fifo_dout),
        .rx_fifo_empty(rx_fifo_empty),
        
        .i2c_scl_div_rate(i2c_scl_div_rate),
        
        .i2c_tx_done(i2c_tx_done),
        .i2c_tx_bytes_n(i2c_tx_bytes_n),
        .i2c_rx_done(i2c_rx_done),
        .i2c_rx_bytes_n(i2c_rx_bytes_n),
        .i2c_slave_resp_err(i2c_slave_resp_err),
        .i2c_rx_overflow(i2c_rx_overflow),
        
        .itr(itr)
    );
    
    /** I2C������ **/
    i2c_ctrler #(
        .addr_bits_n(addr_bits_n),
        .simulation_delay(simulation_delay)
    )i2c_ctrler_u(
        .clk(clk),
        .resetn(resetn),
        
        .i2c_scl_div_rate(i2c_scl_div_rate),
        
        .tx_fifo_ren(tx_fifo_ren),
        .tx_fifo_empty(tx_fifo_empty),
        .tx_fifo_dout(tx_fifo_dout),
        .tx_fifo_dout_last(tx_fifo_dout_last),
        
        .rx_fifo_wen(rx_fifo_wen),
        .rx_fifo_full(rx_fifo_full),
        .rx_fifo_din(rx_fifo_din),
        
        .i2c_tx_done(i2c_tx_done),
        .i2c_tx_bytes_n(i2c_tx_bytes_n),
        .i2c_rx_done(i2c_rx_done),
        .i2c_rx_bytes_n(i2c_rx_bytes_n),
        .i2c_slave_resp_err(i2c_slave_resp_err),
        .i2c_rx_overflow(i2c_rx_overflow),
        
        .scl_t(scl_t),
        .scl_i(scl_i),
        .scl_o(scl_o),
        .sda_t(sda_t),
        .sda_i(sda_i),
        .sda_o(sda_o)
    );
    
endmodule
