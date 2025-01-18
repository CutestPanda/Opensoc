`timescale 1ns / 1ps
/********************************************************************
��ģ��: APB-I2C�ļĴ����ӿ�

����: 
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

����: �¼�ҫ
����: 2024/06/14
********************************************************************/


module regs_if_for_i2c #(
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
    
    // ����fifoд�˿�
    output wire tx_fifo_wen,
    output wire[8:0] tx_fifo_din,
    input wire tx_fifo_full,
    // ����fifo���˿�
    output wire rx_fifo_ren,
    input wire[7:0] rx_fifo_dout,
    input wire rx_fifo_empty,
    
    // I2Cʱ�ӷ�Ƶϵ��
    output wire[7:0] i2c_scl_div_rate,
    
    // I2C�������ָʾ
    input wire i2c_tx_done,
    input wire[3:0] i2c_tx_bytes_n,
    // I2C�������ָʾ
    input wire i2c_rx_done,
    input wire[3:0] i2c_rx_bytes_n,
    // I2C�ӻ���Ӧ����
    input wire i2c_slave_resp_err,
    // I2C�������
    input wire i2c_rx_overflow,
    
    // �ж��ź�
    output wire itr
);
    
    /** APBд�Ĵ������жϴ��� **/
    // 0x00
    reg tx_fifo_wen_reg; // ����fifoдʹ��
    reg[8:0] tx_fifo_din_regs; // ����fifoд����
    reg rx_fifo_ren_reg; // ����fifo��ʹ��
    // 0x04
    reg global_itr_en; // ȫ���ж�ʹ��
    reg i2c_tx_reach_bytes_n_itr_en; // I2C����ָ���ֽ����ж�ʹ��
    reg i2c_slave_resp_err_itr_en; // I2C�ӻ���Ӧ�����ж�ʹ��
    reg i2c_rx_reach_bytes_n_itr_en; // I2C����ָ���ֽ����ж�ʹ��
    reg i2c_rx_overflow_itr_en; // I2C��������ж�ʹ��
    // 0x08
    reg[7:0] i2c_tx_bytes_n_th; // I2C�����ж��ֽ�����ֵ
    reg[7:0] i2c_rx_bytes_n_th; // I2C�����ж��ֽ�����ֵ
    reg[7:0] i2c_scl_div_rate_regs; // I2Cʱ�ӷ�Ƶϵ��
    // 0x0C
    reg global_itr_flag; // ȫ���жϱ�־
    reg[3:0] sub_itr_flag; // ���жϱ�־
    reg[11:0] i2c_bytes_n_sent; // I2C�����ֽ���
    reg[11:0] i2c_bytes_n_rev; // I2C�����ֽ���
    // �жϴ���
    reg i2c_tx_done_d; // �ӳ�1clk��I2C�������ָʾ
    reg i2c_rx_done_d; // �ӳ�1clk��I2C�������ָʾ
    reg i2c_tx_reach_bytes_n_itr_req; // I2C����ָ���ֽ����ж�����
    wire i2c_slave_resp_err_itr_req; // I2C�ӻ���Ӧ�����ж�����
    reg i2c_rx_reach_bytes_n_itr_req; // I2C����ָ���ֽ����ж�����
    wire i2c_rx_overflow_itr_req; // I2C��������ж�����
    wire[3:0] org_itr_req_vec; // ԭʼ�ж���������
    wire global_itr_req; // ���ж�����
    
    assign tx_fifo_wen = tx_fifo_wen_reg;
    assign tx_fifo_din = tx_fifo_din_regs;
    assign rx_fifo_ren = rx_fifo_ren_reg;
    
    assign i2c_scl_div_rate = i2c_scl_div_rate_regs;
    
    assign i2c_slave_resp_err_itr_req = i2c_slave_resp_err;
    assign i2c_rx_overflow_itr_req = i2c_rx_overflow;
    
    assign org_itr_req_vec = {i2c_rx_overflow_itr_req, i2c_rx_reach_bytes_n_itr_req, i2c_slave_resp_err_itr_req, i2c_tx_reach_bytes_n_itr_req} & 
        {i2c_rx_overflow_itr_en, i2c_rx_reach_bytes_n_itr_en, i2c_slave_resp_err_itr_en, i2c_tx_reach_bytes_n_itr_en};
    assign global_itr_req = (|org_itr_req_vec) & global_itr_en & (~global_itr_flag);
    
    // ����fifoдʹ��
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            tx_fifo_wen_reg <= 1'b0;
        else
            # simulation_delay tx_fifo_wen_reg <= psel & penable & pwrite & (paddr[3:2] == 2'd0) & pwdata[1];
    end
    // ����fifoд����
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[3:2] == 2'd0))
            # simulation_delay tx_fifo_din_regs <= pwdata[10:2];
    end
    // ����fifo��ʹ��
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            rx_fifo_ren_reg <= 1'b0;
        else
            # simulation_delay rx_fifo_ren_reg <= psel & penable & pwrite & (paddr[3:2] == 2'd0) & pwdata[17];
    end
    
    // ȫ���ж�ʹ��
    // I2C����ָ���ֽ����ж�ʹ��
    // I2C�ӻ���Ӧ�����ж�ʹ��
    // I2C����ָ���ֽ����ж�ʹ��
    // I2C��������ж�ʹ��
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            {i2c_rx_overflow_itr_en, i2c_rx_reach_bytes_n_itr_en, i2c_slave_resp_err_itr_en, i2c_tx_reach_bytes_n_itr_en, global_itr_en} <= 5'd0;
        else if(psel & penable & pwrite & (paddr[3:2] == 2'd1))
            # simulation_delay {i2c_rx_overflow_itr_en, i2c_rx_reach_bytes_n_itr_en, i2c_slave_resp_err_itr_en, i2c_tx_reach_bytes_n_itr_en, global_itr_en} <= 
                {pwdata[11:8], pwdata[0]};
    end
    
    // I2C�����ж��ֽ�����ֵ
    // I2C�����ж��ֽ�����ֵ
    // I2Cʱ�ӷ�Ƶϵ��
    always @(posedge clk)
    begin
        if(psel & penable & pwrite & (paddr[3:2] == 2'd2))
            # simulation_delay {i2c_scl_div_rate_regs, i2c_rx_bytes_n_th, i2c_tx_bytes_n_th} <= pwdata[23:0];
    end
    
    // ȫ���жϱ�־
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            global_itr_flag <= 1'b0;
        else if(psel & penable & pwrite & (paddr[3:2] == 2'd3))
            # simulation_delay global_itr_flag <= 1'b0;
        else if(~global_itr_flag)
            # simulation_delay global_itr_flag <= global_itr_req;
    end
    // ���жϱ�־
    always @(posedge clk)
    begin
        if(global_itr_req)
            # simulation_delay sub_itr_flag <= org_itr_req_vec;
    end
    // I2C�����ֽ���
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_bytes_n_sent <= 12'd0;
        else if(psel & penable & pwrite & (paddr[3:2] == 2'd3))
            # simulation_delay i2c_bytes_n_sent <= 12'd0;
        else if(i2c_tx_done)
            # simulation_delay i2c_bytes_n_sent <= i2c_bytes_n_sent + i2c_tx_bytes_n;
    end
    // I2C�����ֽ���
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_bytes_n_rev <= 12'd0;
        else if(psel & penable & pwrite & (paddr[3:2] == 2'd3))
            # simulation_delay i2c_bytes_n_rev <= 12'd0;
        else if(i2c_rx_done)
            # simulation_delay i2c_bytes_n_rev <= i2c_bytes_n_rev + i2c_rx_bytes_n;
    end
    
    // �ӳ�1clk��I2C�������ָʾ
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_tx_done_d <= 1'b0;
        else
            # simulation_delay i2c_tx_done_d <= i2c_tx_done;
    end
    // �ӳ�1clk��I2C�������ָʾ
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_rx_done_d <= 1'b0;
        else
            # simulation_delay i2c_rx_done_d <= i2c_rx_done;
    end
    // I2C����ָ���ֽ����ж�����
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_tx_reach_bytes_n_itr_req <= 1'b0;
        else
            # simulation_delay i2c_tx_reach_bytes_n_itr_req <= i2c_tx_done_d & (i2c_bytes_n_sent > i2c_tx_bytes_n_th);
    end
    // I2C����ָ���ֽ����ж�����
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            i2c_rx_reach_bytes_n_itr_req <= 1'b0;
        else
            # simulation_delay i2c_rx_reach_bytes_n_itr_req <= i2c_rx_done_d & (i2c_bytes_n_rev > i2c_rx_bytes_n_th);
    end
    
    // �жϷ�����
    itr_generator #(
        .pulse_w(10),
        .simulation_delay(simulation_delay)
    )itr_generator_u(
        .clk(clk),
        .rst_n(resetn),
        
        .itr_org(global_itr_req),
        
        .itr(itr)
    );
    
    /** APB���Ĵ��� **/
    reg[31:0] prdata_out_regs; // APB���������
    
    assign pready_out = 1'b1;
    assign prdata_out = prdata_out_regs;
    assign pslverr_out = 1'b0;
    
    // APB���������
	generate
		if(simulation_delay == 0)
		begin
			always @(posedge clk)
			begin
				if(psel & (~pwrite))
				begin
					# simulation_delay;
					
					case(paddr[3:2])
						2'd0: prdata_out_regs <= {6'dx, rx_fifo_dout, 1'bx, rx_fifo_empty, 15'dx, tx_fifo_full};
						2'd1: prdata_out_regs <= 32'dx;
						2'd2: prdata_out_regs <= 32'dx;
						2'd3: prdata_out_regs <= {i2c_bytes_n_rev, i2c_bytes_n_sent, 3'dx, sub_itr_flag, global_itr_flag};
						default: prdata_out_regs <= 32'dx;
					endcase
				end
			end
		end
		else
		begin
			always @(posedge clk)
			begin
				if(psel & (~pwrite))
				begin
					# simulation_delay;
					
					case(paddr[3:2])
						2'd0: prdata_out_regs <= {6'd0, rx_fifo_dout, 1'b0, rx_fifo_empty, 15'd0, tx_fifo_full};
						2'd1: prdata_out_regs <= 32'd0;
						2'd2: prdata_out_regs <= 32'd0;
						2'd3: prdata_out_regs <= {i2c_bytes_n_rev, i2c_bytes_n_sent, 3'd0, sub_itr_flag, global_itr_flag};
						default: prdata_out_regs <= 32'd0;
					endcase
				end
			end
		end
	endgenerate
    
endmodule
