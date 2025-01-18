`timescale 1ns / 1ps
/********************************************************************
��ģ��: ����APBЭ���GPIO������

����: 
APB-GPIO������
֧��GPIO�����ж�

�Ĵ���->
    ƫ����  |    ����                     |   ��д����   |    ��ע
    0x00    gpio_width-1~0:GPIO���             W
    0x04    gpio_width-1~0:GPIOд��ƽ����       W
    0x08    gpio_width-1~0:GPIO����             W         0Ϊ���, 1Ϊ����
    0x0C    gpio_width-1~0:GPIO����             R
    0x10    0:ȫ���ж�ʹ��                      W
            1:ȫ���жϱ�־                      RWC   �����жϷ�����������жϱ�־
    0x14    gpio_width-1~0:�ж�״̬             R
    0x18    gpio_width-1~0:�ж�ʹ��             W

ע�⣺
��

Э��:
APB SLAVE
GPIO

����: �¼�ҫ
����: 2023/11/06
********************************************************************/


module apb_gpio #(
    parameter integer gpio_width = 16, // GPIOλ��(1~32)
    parameter gpio_dire = "inout", // GPIO����(inout|input|output)
    parameter default_output_value = 32'hffff_ffff, // GPIOĬ�������ƽ
    parameter default_tri_value = 32'hffff_ffff, // GPIOĬ�Ϸ���(0->��� 1->����)(����inoutģʽ�¿���)
    parameter en_itr = "true", // �Ƿ�ʹ��GPIO�ж�
    parameter itr_edge = "neg", // �жϼ���(pos|neg)
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
    
    // GPIO
    output wire[gpio_width-1:0] gpio_o,
    output wire[gpio_width-1:0] gpio_t, // 0->���, 1->����
    input wire[gpio_width-1:0] gpio_i,
    
    // �ж�
    output wire gpio_itr
);
    
    /** GPIO��̬���� **/
    wire[gpio_width-1:0] gpio_o_w;
    wire[gpio_width-1:0] gpio_t_w;
    wire[gpio_width-1:0] gpio_i_w;
    
    generate
        if(gpio_dire != "input")
            assign gpio_o = gpio_o_w;
        else
            assign gpio_o = default_output_value;
        
        if(gpio_dire == "inout")
            assign gpio_t = gpio_t_w;
        else if(gpio_dire == "input")
            assign gpio_t = 32'hffff_ffff;
        else
            assign gpio_t = 32'h0000_0000;
        
        if(gpio_dire != "output")
        begin
            reg[gpio_width-1:0] gpio_i_d;
            reg[gpio_width-1:0] gpio_i_d2;
            
            assign gpio_i_w = gpio_i_d2;
            
            always @(posedge clk)
            begin
                # simulation_delay;
                
                gpio_i_d <= gpio_i;
                gpio_i_d2 <= gpio_i_d;
            end
        end
        else
            assign gpio_i_w = gpio_o_w;
    endgenerate
    
    /** GPIO�ж� **/
    wire[gpio_width-1:0] gpio_i_w_d; // �ӳ�1clk��gpio����
    wire gpio_global_itr_en_w; // ȫ���ж�ʹ��
    wire[gpio_width-1:0] gpio_itr_en_w; // �ж�ʹ��
    wire gpio_itr_flag_w; // �жϱ�־
    wire[gpio_width-1:0] gpio_itr_mask_w; // �ж�����
    wire[gpio_width-1:0] gpio_itr_mask_w_d; // �ӳ�1clk���ж�����
    wire gpio_org_itr_pulse; // ԭʼ�ж�����
    wire gpio_itr_w; // �ж��ź�
    
    assign gpio_itr = gpio_itr_w;
    
    generate
        if((en_itr == "true") && (gpio_dire != "output"))
        begin
            reg[gpio_width-1:0] gpio_org_itr_mask_regs;
            reg[gpio_width-1:0] gpio_itr_mask_regs_d;
            reg gpio_org_itr_pulse_reg;
            
            assign gpio_itr_mask_w = gpio_org_itr_mask_regs;
            assign gpio_itr_mask_w_d = gpio_itr_mask_regs_d;
            assign gpio_org_itr_pulse = gpio_org_itr_pulse_reg;
            
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                begin
                    gpio_org_itr_pulse_reg <= 1'b0;
                    gpio_org_itr_mask_regs <= {gpio_width{1'b0}};
                    gpio_itr_mask_regs_d <= {gpio_width{1'b0}};
                end
                else
                begin
                    # simulation_delay;
                    
                    gpio_org_itr_pulse_reg <= (gpio_org_itr_mask_regs != {gpio_width{1'b0}}) & gpio_global_itr_en_w & (~gpio_itr_flag_w); // ԭʼ�ж�����
                    gpio_org_itr_mask_regs <= ((itr_edge == "pos") ? (gpio_i_w & (~gpio_i_w_d)):((~gpio_i_w) & gpio_i_w_d)) & // ���������ػ��½���
                        gpio_t_w & // ����������ģʽgpio���ж�
                        gpio_itr_en_w; // gpio�����ж�ʹ��
                    gpio_itr_mask_regs_d <= gpio_org_itr_mask_regs; // ���ж�״̬��1��
                end
            end
            
            // ��ԭʼ�ж����������չ
            itr_generator #(
                .pulse_w(10),
                .simulation_delay(simulation_delay)
            )itr_generator_u(
                .clk(clk),
                .rst_n(resetn),
                .itr_org(gpio_org_itr_pulse),
                .itr(gpio_itr_w)
            );
        end
        else
        begin
            assign gpio_itr_w = 1'b0;
            
            assign gpio_itr_mask_w = 32'd0;
            assign gpio_org_itr_pulse = 1'b0;
        end
    endgenerate
    
    /** APBд�Ĵ��� **/
    reg[31:0] gpio_o_value_regs; // GPIO���
    reg[31:0] gpio_o_mask_regs; // GPIOд��ƽ����
    reg[31:0] gpio_direction_regs; // GPIO����
    reg[31:0] gpio_i_value_regs; // GPIO����
    reg[31:0] gpio_itr_status_regs; // ȫ���ж�ʹ��, �жϱ�־
    reg[31:0] gpio_itr_mask_regs; // �ж�״̬
    reg[31:0] gpio_itr_en_regs; // �ж�ʹ��
    
    assign gpio_o_w = gpio_o_value_regs[gpio_width-1:0];
    assign gpio_t_w = gpio_direction_regs[gpio_width-1:0];
    
    assign gpio_i_w_d = gpio_i_value_regs[gpio_width-1:0];
    assign gpio_global_itr_en_w = gpio_itr_status_regs[0];
    assign gpio_itr_en_w = gpio_itr_en_regs;
    assign gpio_itr_flag_w = gpio_itr_status_regs[1];
    
    genvar gpio_o_value_regs_i;
    generate
        for(gpio_o_value_regs_i = 0;gpio_o_value_regs_i < gpio_width;gpio_o_value_regs_i = gpio_o_value_regs_i + 1)
        begin
            always @(posedge clk or negedge resetn)
            begin
                if(~resetn)
                    gpio_o_value_regs[gpio_o_value_regs_i] <= default_output_value[gpio_o_value_regs_i];
                else if(psel & pwrite & penable & (paddr[4:2] == 3'd0) & gpio_o_mask_regs[gpio_o_value_regs_i]) // дGPIO�����ƽ
                    # simulation_delay gpio_o_value_regs[gpio_o_value_regs_i] <= pwdata[gpio_o_value_regs_i];
            end
        end
    endgenerate
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
        begin
            gpio_o_mask_regs[gpio_width-1:0] <= {gpio_width{1'b1}};
            
            if(gpio_dire == "inout")
                gpio_direction_regs[gpio_width-1:0] <= default_tri_value;
            else if(gpio_dire == "input")
                gpio_direction_regs[gpio_width-1:0] <= {gpio_width{1'b1}};
            else
                gpio_direction_regs[gpio_width-1:0] <= {gpio_width{1'b0}};
            
            gpio_itr_status_regs[0] <= 1'b0;
            gpio_itr_en_regs[gpio_width-1:0] <= {gpio_width{1'b0}};
        end
        else if(psel & pwrite & penable)
        begin
            # simulation_delay;
            
            case(paddr[4:2])
                3'd1: // дGPIOд��ƽ����
                    gpio_o_mask_regs[gpio_width-1:0] <= pwdata[gpio_width-1:0];
                3'd2: // дGPIO����, ��inout���޸���Ч
                    gpio_direction_regs[gpio_width-1:0] <= pwdata[gpio_width-1:0];
                3'd4: // дȫ���ж�ʹ��
                    gpio_itr_status_regs[0] <= pwdata[0];
                3'd6: // д�ж�ʹ��
                    gpio_itr_en_regs[gpio_width-1:0] <= pwdata[gpio_width-1:0];
                default: // hold
                begin
                    gpio_o_mask_regs[gpio_width-1:0] <= gpio_o_mask_regs[gpio_width-1:0];
                    gpio_direction_regs[gpio_width-1:0] <= gpio_direction_regs[gpio_width-1:0];
                    gpio_itr_status_regs[0] <= gpio_itr_status_regs[0];
                    gpio_itr_en_regs[gpio_width-1:0] <= gpio_itr_en_regs[gpio_width-1:0];
                end
            endcase
        end
    end
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            gpio_itr_status_regs[1] <= 1'b0;
        else if(psel & pwrite & penable & (paddr[4:2] == 3'd4)) // ����жϱ�־
            # simulation_delay gpio_itr_status_regs[1] <= 1'b0;
        else if(~gpio_itr_status_regs[1]) // �ȴ��µ�GPIO�ж�, �жϱ�־Ϊ��ʱ�����µ�GPIO�ж�
            # simulation_delay gpio_itr_status_regs[1] <= gpio_org_itr_pulse;
    end
    
    // ����״̬��Ϣ
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
        begin
            gpio_i_value_regs[gpio_width-1:0] <= (itr_edge == "pos") ? {gpio_width{1'b0}}:{gpio_width{1'b1}};
            gpio_itr_mask_regs[gpio_width-1:0] <= {gpio_width{1'b0}};
        end
        else
        begin
            # simulation_delay;
            
            gpio_i_value_regs[gpio_width-1:0] <= gpio_i_w; // ����GPIO�����ƽ
            
            if(gpio_org_itr_pulse) // �����ж�״̬
                gpio_itr_mask_regs[gpio_width-1:0] <= gpio_itr_mask_w_d;
        end
    end
    
    /** APB���Ĵ��� **/
    reg[31:0] prdata_out_regs;
	
	assign pready_out = 1'b1;
    assign pslverr_out = 1'b0;
    assign prdata_out = prdata_out_regs;
    
	generate
		if(simulation_delay == 0)
		begin
			always @(posedge clk)
			begin
				if(psel & (~pwrite))
				begin
					# simulation_delay;
					
					case(paddr[4:2])
						3'd3: // ��GPIO����
							prdata_out_regs <= {{(32-gpio_width){1'bx}}, gpio_i_value_regs[gpio_width-1:0]};
						3'd4: // ���жϱ�־
							prdata_out_regs <= {30'dx, gpio_itr_status_regs[1], 1'bx};
						3'd5: // ���ж�״̬
							prdata_out_regs <= {{(32-gpio_width){1'bx}}, gpio_itr_mask_regs[gpio_width-1:0]};
						default: // not care
							prdata_out_regs <= 32'dx;
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
					
					case(paddr[4:2])
						3'd3: // ��GPIO����
							prdata_out_regs <= {{(32-gpio_width){1'b0}}, gpio_i_value_regs[gpio_width-1:0]};
						3'd4: // ���жϱ�־
							prdata_out_regs <= {30'd0, gpio_itr_status_regs[1], 1'b0};
						3'd5: // ���ж�״̬
							prdata_out_regs <= {{(32-gpio_width){1'b0}}, gpio_itr_mask_regs[gpio_width-1:0]};
						default: // not care
							prdata_out_regs <= 32'd0;
					endcase
				end
			end
		end
	endgenerate
	
    

endmodule
