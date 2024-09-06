`timescale 1ns / 1ps
/********************************************************************
��ģ��: sdram���ݻ�����

����:
д����/�����ݹ���fifo

ע�⣺
д����/�����ݹ���fifo��MEM���ӳ� = 1clk
��ͻ������Ϊȫҳʱ, д/�����ݹ���fifo������Ƭ���Ϊ256, �������ʱΪͻ������
��д����/������AXIS��, ��last�ź����ָ�ÿ��ͻ��

Э��:
AXIS MASTER/SLAVE
EXT FIFO READ/WRITE

����: �¼�ҫ
����: 2024/04/14
********************************************************************/


module sdram_data_buffer #(
    parameter integer rw_data_buffer_depth = 1024, // ��д����buffer���(512 | 1024 | 2048 | 4096)
    parameter en_imdt_stat_wburst_len = "true", // �Ƿ�ʹ��ʵʱͳ��дͻ������(����ȫҳͻ����Ч)
    parameter integer burst_len = -1, // ͻ������(-1 -> ȫҳ; 1 | 2 | 4 | 8)
    parameter integer data_width = 32 // ����λ��
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // д����AXIS
    input wire[data_width-1:0] s_axis_wt_data,
    input wire[data_width/8-1:0] s_axis_wt_keep,
    input wire s_axis_wt_last,
    input wire s_axis_wt_valid,
    output wire s_axis_wt_ready,
    // ������AXIS
    output wire[data_width-1:0] m_axis_rd_data,
    output wire m_axis_rd_last,
    output wire m_axis_rd_valid,
    input wire m_axis_rd_ready,
    
    // д���ݹ���fifo���˿�
    input wire wdata_ext_fifo_ren,
    output wire wdata_ext_fifo_empty_n,
    input wire wdata_ext_fifo_mem_ren,
    input wire[clogb2(rw_data_buffer_depth-1):0] wdata_ext_fifo_mem_raddr,
    output wire[data_width+data_width/8-1:0] wdata_ext_fifo_mem_dout, // {keep(data_width/8 bit), data(data_width bit)}
    
    // �����ݹ���fifoд�˿�
    input wire rdata_ext_fifo_wen,
    output wire rdata_ext_fifo_full_n,
    input wire rdata_ext_fifo_mem_wen,
    input wire[clogb2(rw_data_buffer_depth-1):0] rdata_ext_fifo_mem_waddr,
    input wire[data_width:0] rdata_ext_fifo_mem_din, // {last(1bit), data(data_width bit)}
    
    // ʵʱͳ��дͻ������fifo���˿�
    input wire imdt_stat_wburst_len_fifo_ren,
    output wire[7:0] imdt_stat_wburst_len_fifo_dout
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
    localparam integer ext_fifo_item_n = (burst_len == -1) ? (rw_data_buffer_depth / 256):(rw_data_buffer_depth / burst_len); // д����/�����ݹ���fifo�Ĵ洢����
    
    /** д���ݹ���fifo **/
    reg[clogb2(ext_fifo_item_n):0] wdata_ext_fifo_item_n; // д���ݹ���fifo��ǰ�Ĵ洢����
    // д���ݹ���fifo���˿�
    reg wdata_ext_fifo_empty_n_reg;
    // д���ݹ���fifoд�˿�
    wire wdata_ext_fifo_wen;
    reg wdata_ext_fifo_full_n;
    wire wdata_ext_fifo_mem_wen;
    reg[clogb2(rw_data_buffer_depth-1):0] wdata_ext_fifo_mem_waddr;
    wire[data_width+data_width/8-1:0] wdata_ext_fifo_mem_din;
    
    assign s_axis_wt_ready = wdata_ext_fifo_full_n;
    assign wdata_ext_fifo_empty_n = wdata_ext_fifo_empty_n_reg;
    
    assign wdata_ext_fifo_wen = s_axis_wt_valid & s_axis_wt_ready & s_axis_wt_last;
    assign wdata_ext_fifo_mem_wen = s_axis_wt_valid & s_axis_wt_ready;
    assign wdata_ext_fifo_mem_din = {s_axis_wt_keep, s_axis_wt_data};
    
    // д���ݹ���fifo��ǰ�Ĵ洢����
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wdata_ext_fifo_item_n <= 0;
        else if((wdata_ext_fifo_wen & wdata_ext_fifo_full_n) ^ (wdata_ext_fifo_ren & wdata_ext_fifo_empty_n))
            wdata_ext_fifo_item_n <= (wdata_ext_fifo_wen & wdata_ext_fifo_full_n) ? (wdata_ext_fifo_item_n + 1):(wdata_ext_fifo_item_n - 1);
    end
    // д���ݹ���fifo�ձ�־
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wdata_ext_fifo_empty_n_reg <= 1'b0;
        else if((wdata_ext_fifo_wen & wdata_ext_fifo_full_n) ^ (wdata_ext_fifo_ren & wdata_ext_fifo_empty_n))
            wdata_ext_fifo_empty_n_reg <= (wdata_ext_fifo_wen & wdata_ext_fifo_full_n) | (wdata_ext_fifo_item_n != 1);
    end
    // д���ݹ���fifo����־
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wdata_ext_fifo_full_n <= 1'b1;
        else if((wdata_ext_fifo_wen & wdata_ext_fifo_full_n) ^ (wdata_ext_fifo_ren & wdata_ext_fifo_empty_n))
            wdata_ext_fifo_full_n <= (wdata_ext_fifo_ren & wdata_ext_fifo_empty_n) | (wdata_ext_fifo_item_n != (ext_fifo_item_n - 1));
    end
    
    // д���ݹ���fifo��MEMд��ַ
    generate
        if(burst_len == -1)
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_waddr[clogb2(rw_data_buffer_depth-1):8] <= 0;
                else if(s_axis_wt_valid & s_axis_wt_ready & s_axis_wt_last)
                    wdata_ext_fifo_mem_waddr[clogb2(rw_data_buffer_depth-1):8] <= wdata_ext_fifo_mem_waddr[clogb2(rw_data_buffer_depth-1):8] + 1;
            end
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_waddr[7:0] <= 8'd0;
                else if(s_axis_wt_valid & s_axis_wt_ready)
                    wdata_ext_fifo_mem_waddr[7:0] <= s_axis_wt_last ? 8'd0:(wdata_ext_fifo_mem_waddr[7:0] + 8'd1);
            end
        end
        else
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_waddr <= 0;
                else if(s_axis_wt_valid & s_axis_wt_ready)
                    wdata_ext_fifo_mem_waddr <= wdata_ext_fifo_mem_waddr + 1;
            end
        end
    endgenerate
    
    // MEM
    bram_simple_dual_port #(
        .style("LOW_LATENCY"),
        .mem_width(data_width + data_width / 8),
        .mem_depth(rw_data_buffer_depth),
        .INIT_FILE("no_init"),
        .simulation_delay(0)
    )wdata_ext_fifo_mem(
        .clk(clk),
        .wen_a(wdata_ext_fifo_mem_wen),
        .addr_a(wdata_ext_fifo_mem_waddr),
        .din_a(wdata_ext_fifo_mem_din),
        .ren_b(wdata_ext_fifo_mem_ren),
        .addr_b(wdata_ext_fifo_mem_raddr),
        .dout_b(wdata_ext_fifo_mem_dout)
    );
    
    /** ʵʱͳ��дͻ������ **/
    wire imdt_stat_wburst_len_fifo_wen;
    wire[7:0] imdt_stat_wburst_len_fifo_din;
    
    assign imdt_stat_wburst_len_fifo_wen = ((en_imdt_stat_wburst_len == "true") & (burst_len == -1)) & 
        s_axis_wt_valid & s_axis_wt_ready & s_axis_wt_last;
    assign imdt_stat_wburst_len_fifo_din = wdata_ext_fifo_mem_waddr[7:0];
    
    fifo_based_on_regs #(
        .fwft_mode("true"),
        .fifo_depth(2),
        .fifo_data_width(8),
        .almost_full_th(),
        .almost_empty_th(),
        .simulation_delay(0)
    )imdt_stat_wburst_len_fifo(
        .clk(clk),
        .rst_n(rst_n),
        .fifo_wen(imdt_stat_wburst_len_fifo_wen),
        .fifo_din(imdt_stat_wburst_len_fifo_din),
        .fifo_ren(imdt_stat_wburst_len_fifo_ren),
        .fifo_dout(imdt_stat_wburst_len_fifo_dout)
    );
    
    /** �����ݹ���fifo **/
    reg[clogb2(ext_fifo_item_n):0] rdata_ext_fifo_item_n; // �����ݹ���fifo��ǰ�Ĵ洢����
    // �����ݹ���fifo���˿�
    reg[burst_len-1:0] rdata_rcnt;
    wire rdata_ext_fifo_ren;
    reg rdata_ext_fifo_empty_n;
    wire rdata_ext_fifo_mem_ren;
    reg rdata_ext_fifo_mem_ren_d;
    reg[clogb2(rw_data_buffer_depth-1):0] rdata_ext_fifo_mem_raddr;
    wire[data_width:0] rdata_ext_fifo_mem_dout;
    // �����ݹ���fifoд�˿�
    reg rdata_ext_fifo_full_n_reg;
    // ���ڻ���ļĴ���fifo
    wire rdata_show_ahead_buffer_almost_full_n;
    
    assign rdata_ext_fifo_full_n = rdata_ext_fifo_full_n_reg; // ��ȫҳͻ����˵, ����fifo����־����Ч����Ч����1clkʱ��, ����ֻ�Ǹ��ӱ�����, ��Ӱ�칦��
    
    assign rdata_ext_fifo_ren = (burst_len == 1) ? rdata_ext_fifo_mem_ren:
                                ((burst_len == 2) | (burst_len == 4) | (burst_len == 8)) ? (rdata_ext_fifo_mem_ren & rdata_rcnt[burst_len-1]):
                                                                                           rdata_ext_fifo_mem_ren_d & rdata_ext_fifo_mem_dout[data_width]; // ȫҳͻ��
    assign rdata_ext_fifo_mem_ren = rdata_show_ahead_buffer_almost_full_n & rdata_ext_fifo_empty_n & 
        ((burst_len != -1) | (~rdata_ext_fifo_ren)); // ��ȫҳͻ����˵, ����fifo�ձ�־����Ч����Ч����1clkʱ��, �����Ҫ���ι���fifo��ʹ����1clk��MEM��, �ö���1clk������MEM����ַ
    
    // ����������Ƭ������
    generate
        if(burst_len != -1)
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_rcnt <= {{(burst_len-1){1'b0}}, 1'b1};
                else if(rdata_ext_fifo_mem_ren)
                    rdata_rcnt <= {rdata_rcnt[burst_len-2:0], rdata_rcnt[burst_len-1]};
            end
        end
    endgenerate
    
    // �����ݹ���fifo��ǰ�Ĵ洢����
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rdata_ext_fifo_item_n <= 0;
        else if((rdata_ext_fifo_wen & rdata_ext_fifo_full_n) ^ (rdata_ext_fifo_ren & rdata_ext_fifo_empty_n))
            rdata_ext_fifo_item_n <= (rdata_ext_fifo_wen & rdata_ext_fifo_full_n) ? (rdata_ext_fifo_item_n + 1):(rdata_ext_fifo_item_n - 1);
    end
    // �����ݹ���fifo�ձ�־
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rdata_ext_fifo_empty_n <= 1'b0;
        else if((rdata_ext_fifo_wen & rdata_ext_fifo_full_n) ^ (rdata_ext_fifo_ren & rdata_ext_fifo_empty_n))
            rdata_ext_fifo_empty_n <= (rdata_ext_fifo_wen & rdata_ext_fifo_full_n) | (rdata_ext_fifo_item_n != 1);
    end
    // �����ݹ���fifo����־
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rdata_ext_fifo_full_n_reg <= 1'b1;
        else if((rdata_ext_fifo_wen & rdata_ext_fifo_full_n) ^ (rdata_ext_fifo_ren & rdata_ext_fifo_empty_n))
            rdata_ext_fifo_full_n_reg <= (rdata_ext_fifo_ren & rdata_ext_fifo_empty_n) | (rdata_ext_fifo_item_n != (ext_fifo_item_n - 1));
    end
    
    // �ӳ�1clk�Ķ����ݹ���fifo��MEM��ʹ��
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rdata_ext_fifo_mem_ren_d <= 1'b0;
        else
            rdata_ext_fifo_mem_ren_d <= rdata_ext_fifo_mem_ren;
    end
    
    // �����ݹ���fifo��MEM����ַ
    generate
        if(burst_len == -1)
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_raddr[clogb2(rw_data_buffer_depth-1):8] <= 0;
                else if(rdata_ext_fifo_ren)
                    rdata_ext_fifo_mem_raddr[clogb2(rw_data_buffer_depth-1):8] <= rdata_ext_fifo_mem_raddr[clogb2(rw_data_buffer_depth-1):8] + 1;
            end
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_raddr[7:0] <= 8'd0;
                else if(rdata_ext_fifo_ren | rdata_ext_fifo_mem_ren)
                    rdata_ext_fifo_mem_raddr[7:0] <= rdata_ext_fifo_ren ? 8'd0:(rdata_ext_fifo_mem_raddr[7:0] + 8'd1);
            end
        end
        else
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_raddr <= 0;
                else if(rdata_ext_fifo_mem_ren)
                    rdata_ext_fifo_mem_raddr <= rdata_ext_fifo_mem_raddr + 1;
            end
        end
    endgenerate
    
    // MEM
    bram_simple_dual_port #(
        .style("LOW_LATENCY"),
        .mem_width(data_width + 1),
        .mem_depth(rw_data_buffer_depth),
        .INIT_FILE("no_init"),
        .simulation_delay(0)
    )rdata_ext_fifo_mem(
        .clk(clk),
        .wen_a(rdata_ext_fifo_mem_wen),
        .addr_a(rdata_ext_fifo_mem_waddr),
        .din_a(rdata_ext_fifo_mem_din),
        .ren_b(rdata_ext_fifo_mem_ren),
        .addr_b(rdata_ext_fifo_mem_raddr),
        .dout_b(rdata_ext_fifo_mem_dout)
    );
    
    // ���ڻ���ļĴ���fifo
    fifo_based_on_regs #(
        .fwft_mode("true"),
        .fifo_depth(4),
        .fifo_data_width(data_width + 1),
        .almost_full_th(3),
        .almost_empty_th(),
        .simulation_delay(0)
    )rdata_show_ahead_buffer(
        .clk(clk),
        .rst_n(rst_n),
        .fifo_wen(rdata_ext_fifo_mem_ren_d),
        .fifo_din(rdata_ext_fifo_mem_dout),
        .fifo_almost_full_n(rdata_show_ahead_buffer_almost_full_n),
        .fifo_ren(m_axis_rd_ready),
        .fifo_dout({m_axis_rd_last, m_axis_rd_data}),
        .fifo_empty_n(m_axis_rd_valid)
    );
    
endmodule
