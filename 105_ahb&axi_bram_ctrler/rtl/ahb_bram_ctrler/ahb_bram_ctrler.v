`timescale 1ns / 1ps
/********************************************************************
��ģ��: ����AHBЭ���Bram������

����: 
AHB-Bram������
��ѡBram���ӳ�Ϊ1clk��2clk

ע�⣺
Bramλ��̶�Ϊ32bit

Э��:
AHB SLAVE
MEM READ/WRITE

����: �¼�ҫ
����: 2024/04/07
********************************************************************/


module ahb_bram_ctrler #(
    parameter integer bram_read_la = 1, // Bram���ӳ�(1 | 2)
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // AHB SLAVE
    input wire s_ahb_hsel,
    input wire[31:0] s_ahb_haddr,
    // 2'b00 -> IDLE; 2'b01 -> BUSY; 2'b10 -> NONSEQ; 2'b11 -> SEQ
    input wire[1:0] s_ahb_htrans,
    // 3'b000 -> SINGLE; 3'b001 -> INCR; 3'b010 -> WRAP4; 3'b011 -> INCR4;
    // 3'b100 -> WRAP8; 3'b101 -> INCR8; 3'b110 -> WRAP16; 3'b111 -> INCR16
    input wire[2:0] s_ahb_hburst, // ignored
    input wire[2:0] s_ahb_hsize,
    input wire[3:0] s_ahb_hprot, // ignored
    input wire s_ahb_hwrite,
    input wire s_ahb_hready,
    input wire[31:0] s_ahb_hwdata,
    input wire[3:0] s_ahb_hwstrb,
    output wire s_ahb_hready_out,
    output wire[31:0] s_ahb_hrdata,
    output wire s_ahb_hresp, // const -> 1'b0
    
    // �洢���ӿ�
    output wire bram_clk,
    output wire bram_rst,
    output wire bram_en,
    output wire[3:0] bram_wen,
    output wire[29:0] bram_addr,
    output wire[31:0] bram_din,
    input wire[31:0] bram_dout
);

    /** AHB -> ��дBram **/
    wire ahb_trans_start; // AHB���俪ʼ(ָʾ)
    reg[3:0] mem_wen; // Bramдʹ��
	reg to_wt_mem_d; // �ӳ�1clk��Bramдָʾ
	reg ahb_wt_transfering; // AHB���ڽ���д����(��־)
    reg ahb_rd_transfering; // AHB���ڽ��ж�����(��־)
    reg[31:0] haddr_latched; // �����AHB�����ַ
    
    assign bram_clk = clk;
    assign bram_rst = ~rst_n;
    assign bram_en = 1'b1;
    assign bram_wen = mem_wen & s_ahb_hwstrb;
    assign bram_addr = (ahb_wt_transfering | (ahb_rd_transfering & to_wt_mem_d)) ? haddr_latched[31:2]:s_ahb_haddr[31:2];
    assign bram_din = s_ahb_hwdata;
    
    assign ahb_trans_start = s_ahb_hsel & s_ahb_hready & s_ahb_htrans[1];
	
    // Bramдʹ��
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            mem_wen <= 4'b0000;
        else
        begin
            if(ahb_trans_start & s_ahb_hwrite)
            begin
                // ����:AHBͻ����Сֻ��Ϊ1/2/4�ֽ�!
                # simulation_delay;
                
                case({s_ahb_haddr[1:0], s_ahb_hsize[1:0]})
                    4'b00_00: mem_wen <= 4'b0001;
                    4'b00_01: mem_wen <= 4'b0011;
                    4'b00_10: mem_wen <= 4'b1111;
                    4'b01_00: mem_wen <= 4'b0010;
                    4'b01_01: mem_wen <= 4'b0110;
                    4'b01_10: mem_wen <= 4'b1110;
                    4'b10_00: mem_wen <= 4'b0100;
                    4'b10_01, 4'b10_10: mem_wen <= 4'b1100;
                    4'b11_00, 4'b11_01, 4'b11_10: mem_wen <= 4'b1000;
                    default: mem_wen <= 4'b0000;
                endcase
            end
            else
                # simulation_delay mem_wen <= 4'b0000;
        end
    end
	
	// �ӳ�1clk��Bramдָʾ
	always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
			to_wt_mem_d <= 1'b0;
		else
			# simulation_delay to_wt_mem_d <= |mem_wen;
	end
    
	// AHB���ڽ���д����(��־)
	always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            ahb_wt_transfering <= 1'b0;
        else
            # simulation_delay ahb_wt_transfering <= ahb_trans_start & s_ahb_hwrite;
    end
    // AHB���ڽ��ж�����(��־)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            ahb_rd_transfering <= 1'b0;
        else
            # simulation_delay ahb_rd_transfering <= ahb_trans_start & (~s_ahb_hwrite);
    end
	// �����AHB�����ַ
    always @(posedge clk)
	begin
		if(ahb_trans_start)
			# simulation_delay haddr_latched <= s_ahb_haddr;
	end
    
    /** AHB�ӻ����� **/
    reg hready_out; // AHB��һ���������
    
    assign s_ahb_hready_out = hready_out;
    assign s_ahb_hrdata = bram_dout;
    assign s_ahb_hresp = 1'b0;
    
    // AHB��һ���������
	generate
		if(bram_read_la == 1)
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					hready_out <= 1'b1;
				else
					# simulation_delay hready_out <= ~(ahb_trans_start & (~s_ahb_hwrite) & ahb_wt_transfering);
			end
		end
		else
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					hready_out <= 1'b1;
				else
					# simulation_delay hready_out <= ~((ahb_trans_start & (~s_ahb_hwrite)) | (ahb_rd_transfering & to_wt_mem_d));
			end
		end
	endgenerate
    
endmodule
