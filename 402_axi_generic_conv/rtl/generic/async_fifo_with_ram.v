`timescale 1ns / 1ps
/********************************************************************
��ģ��: �첽fifo

����: 
ʹ�ü�˫��RAM��Ϊfifo�洢��
֧��first word fall through����(READ LA = 0)

ע�⣺
��֧��RAM�Ķ��ӳ�=1

Э��:
FIFO READ/WRITE

����: �¼�ҫ
����: 2024/05/10
********************************************************************/


module async_fifo_with_ram #(
    parameter fwft_mode = "true", // �Ƿ�����first word fall through����
    parameter ram_type = "lutram", // RAM����(lutram | bram)
    parameter integer depth = 32, // fifo���(16 | 32 | 64 | ...)
    parameter integer data_width = 8, // ����λ��
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk_wt,
    input wire rst_n_wt,
    input wire clk_rd,
    input wire rst_n_rd,
    
    // fifo
    input wire fifo_wen,
    output wire fifo_full,
	output wire fifo_full_n,
    input wire[data_width-1:0] fifo_din,
    input wire fifo_ren,
    output wire fifo_empty,
	output wire fifo_empty_n,
    output wire[data_width-1:0] fifo_dout
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
    
    /** ��fifo������ **/
    wire ram_clk_w;
    wire[clogb2(depth-1):0] ram_waddr;
    wire ram_wen;
    wire[data_width-1:0] ram_din;
    wire ram_clk_r;
    wire ram_ren;
    wire[clogb2(depth-1):0] ram_raddr;
    wire[data_width-1:0] ram_dout;
    // ��fifoд�˿�
    wire m_fifo_ren;
    wire m_fifo_empty;
	wire m_fifo_empty_n;
    wire[data_width-1:0] m_fifo_dout;
    
    async_fifo #(
        .depth(depth),
        .data_width(data_width),
        .simulation_delay(simulation_delay)
    )async_fifo_u(
        .clk_wt(clk_wt),
        .rst_n_wt(rst_n_wt),
        .clk_rd(clk_rd),
        .rst_n_rd(rst_n_rd),
        
        .ram_clk_w(ram_clk_w),
        .ram_waddr(ram_waddr),
        .ram_wen(ram_wen),
        .ram_din(ram_din),
        .ram_clk_r(ram_clk_r),
        .ram_ren(ram_ren),
        .ram_raddr(ram_raddr),
        .ram_dout(ram_dout),
        
        .fifo_wen(fifo_wen),
        .fifo_full(fifo_full),
		.fifo_full_n(fifo_full_n),
        .fifo_din(fifo_din),
        .fifo_ren(m_fifo_ren),
        .fifo_empty(m_fifo_empty),
		.fifo_empty_n(m_fifo_empty_n),
        .fifo_dout(m_fifo_dout)
    );
    
    /** ��ѡ�Ĵ�fifo **/
    generate
        if(fwft_mode == "false")
        begin
            assign m_fifo_ren = fifo_ren;
            assign fifo_empty = m_fifo_empty;
			assign fifo_empty_n = m_fifo_empty_n;
            assign fifo_dout = m_fifo_dout;
        end
        else
        begin
			fifo_show_ahead_buffer #(
				.fifo_data_width(data_width),
				.simulation_delay(simulation_delay)
			)fifo_show_ahead_buffer_u(
				.clk(clk_rd),
				.rst_n(rst_n_rd),
				
				.std_fifo_ren(m_fifo_ren),
				.std_fifo_dout(m_fifo_dout),
				.std_fifo_empty(m_fifo_empty),
				
				.fwft_fifo_ren(fifo_ren),
				.fwft_fifo_dout(fifo_dout),
				.fwft_fifo_empty(fifo_empty),
				.fwft_fifo_empty_n(fifo_empty_n)
			);
        end
    endgenerate
    
    /** ��˫��RAM **/
    generate
        if(ram_type == "bram")
        begin
            bram_simple_dual_port_async #(
                .style("LOW_LATENCY"),
                .mem_width(data_width),
                .mem_depth(depth),
                .INIT_FILE("no_init"),
                .simulation_delay(simulation_delay)
            )ram_u(
                .clk_a(ram_clk_w),
                .clk_b(ram_clk_r),
                
                .wen_a(ram_wen),
                .addr_a(ram_waddr),
                .din_a(ram_din),
                
                .ren_b(ram_ren),
                .addr_b(ram_raddr),
                .dout_b(ram_dout)
            );
        end
        else
        begin
            dram_simple_dual_port_async #(
                .mem_width(data_width),
                .mem_depth(depth),
                .INIT_FILE("no_init"),
                .use_output_register("true"),
                .simulation_delay(simulation_delay)
            )ram_u(
                .clk_a(ram_clk_w),
                .clk_b(ram_clk_r),
                
                .wen_a(ram_wen),
                .addr_a(ram_waddr),
                .din_a(ram_din),
                
                .ren_b(ram_ren),
                .addr_b(ram_raddr),
                .dout_b(ram_dout)
            );
        end
    endgenerate
    
endmodule