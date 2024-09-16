`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXI֡����(����)

����: 
ʵ����֡д��AXIS��AXIдͨ��, ֡��ȡAXIS��AXI��ͨ��֮���ת��
AXI�����ĵ�ַ/����λ��̶�Ϊ32

ע�⣺
֡��С(img_n * pix_data_width / 8)�����ܱ�4����
δ��AXI����ʵʩ4KB�߽籣��
AXI����ַ�������(axi_raddr_outstanding)��AXI��ͨ������buffer���(axi_rchn_data_buffer_depth)��ͬ����ARͨ��������

��������֡����(frame_n)��֡�������׵�ַ(frame_buffer_baseaddr)����Ϊ����ʱ����???

Э��:
AXIS MASTER/SLAVE
AXI MASTER

����: �¼�ҫ
����: 2024/05/07
********************************************************************/


module axi_frame_buffer_core #(
    parameter integer frame_n = 4, // ������֡����(�����ڷ�Χ[3, 16]��)
    parameter integer frame_buffer_baseaddr = 0, // ֡�������׵�ַ(�����ܱ�4����)
    parameter integer img_n = 1920 * 1080, // ͼ���С(�����ظ�����)
    parameter integer pix_data_width = 24, // ����λ��(�����ܱ�8����)
	parameter integer pix_per_clk_for_wt = 1, // ÿclkд�����ظ���
	parameter integer pix_per_clk_for_rd = 1, // ÿclk�������ظ���
    parameter integer axi_raddr_outstanding = 2, // AXI����ַ�������(1 | 2 | 4 | 8 | 16)
    parameter integer axi_rchn_max_burst_len = 64, // AXI��ͨ�����ͻ������(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
    parameter integer axi_waddr_outstanding = 2, // AXIд��ַ�������(1 | 2 | 4 | 8 | 16)
    parameter integer axi_wchn_max_burst_len = 64, // AXIдͨ�����ͻ������(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
    parameter integer axi_wchn_data_buffer_depth = 512, // AXIдͨ������buffer���(0 | 16 | 32 | 64 | ..., ��Ϊ0ʱ��ʾ��ʹ��)
    parameter integer axi_rchn_data_buffer_depth = 512, // AXI��ͨ������buffer���(0 | 16 | 32 | 64 | ..., ��Ϊ0ʱ��ʾ��ʹ��)
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // ֡������ƺ�״̬
    input wire disp_suspend, // ��ͣȡ�µ�һ֡(��־)
    output wire rd_new_frame, // ��ȡ�µ�һ֡(ָʾ)
    
    // ֡д��AXIS
    input wire[pix_data_width*pix_per_clk_for_wt-1:0] s_axis_pix_data,
    input wire s_axis_pix_valid,
    output wire s_axis_pix_ready,
    
    // ֡��ȡAXIS
    output wire[pix_data_width*pix_per_clk_for_rd-1:0] m_axis_pix_data,
    output wire[7:0] m_axis_pix_user, // ��ǰ��֡��
    output wire m_axis_pix_last, // ָʾ��֡���1������
    output wire m_axis_pix_valid,
    input wire m_axis_pix_ready,
    
    // AXI����
    // AR
    output wire[31:0] m_axi_araddr,
    output wire[1:0] m_axi_arburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_arlen,
    output wire[2:0] m_axi_arsize, // const -> 3'b010
    output wire m_axi_arvalid,
    input wire m_axi_arready,
    // R
    input wire[31:0] m_axi_rdata,
    input wire[1:0] m_axi_rresp, // ignored
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output wire m_axi_rready,
    // AW
    output wire[31:0] m_axi_awaddr,
    output wire[1:0] m_axi_awburst, // const -> 2'b01(INCR)
    output wire[7:0] m_axi_awlen,
    output wire[2:0] m_axi_awsize, // const -> 3'b010
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    // B
    input wire[1:0] m_axi_bresp, // ignored
    input wire m_axi_bvalid,
    output wire m_axi_bready, // const -> 1'b1
    // W
    output wire[31:0] m_axi_wdata,
    output wire[3:0] m_axi_wstrb, // const -> 4'b1111
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready
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
    localparam integer frame_size = img_n * pix_data_width / 8; // ֡��С(���ֽڼ�)
    localparam integer frame_dwords_n = frame_size / 4; // ÿ֡��˫�ָ���
    localparam integer baseaddr_of_last_frame = frame_buffer_baseaddr + (frame_n - 1) * frame_size; // ֡�����������1֡���׵�ַ
    
    /** ֡���� **/
    wire frame_buf_wen; // ֡������дʹ��
    wire frame_buf_full; // ֡����������־
    reg[frame_n-1:0] frame_buf_wptr; // ֡������дָ��(������)
    wire[frame_n-1:0] frame_buf_wptr_add1; // ֡������дָ��(������) + 1
    wire frame_buf_ren; // ֡��������ʹ��
    wire frame_buf_empty; // ֡�������ձ�־
    reg[frame_n-1:0] frame_buf_rptr; // ֡��������ָ��(������)
    wire[frame_n-1:0] frame_buf_rptr_add1; // ֡��������ָ��(������) + 1
    reg[frame_n-1:0] frame_filled_vec; // ֡�����(����)
    reg rd_new_frame_reg; // ��ȡ�µ�һ֡(ָʾ)
    
    assign rd_new_frame = rd_new_frame_reg;
    
    assign frame_buf_full = (frame_buf_wptr_add1 & frame_filled_vec) != {frame_n{1'b0}};
    assign frame_buf_wptr_add1 = {frame_buf_wptr[frame_n-2:0], frame_buf_wptr[frame_n-1]};
    
    assign frame_buf_empty = (frame_buf_rptr_add1 & frame_filled_vec) == {frame_n{1'b0}};
    assign frame_buf_rptr_add1 = {frame_buf_rptr[frame_n-2:0], frame_buf_rptr[frame_n-1]};
    
    // ֡������дָ��(������)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            frame_buf_wptr <= {{(frame_n-1){1'b0}}, 1'b1};
        else if(frame_buf_wen & (~frame_buf_full))
            # simulation_delay frame_buf_wptr <= {frame_buf_wptr[frame_n-2:0], frame_buf_wptr[frame_n-1]};
    end
    // ֡��������ָ��(������)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            frame_buf_rptr <= {1'b1, {(frame_n-1){1'b0}}};
        else if(frame_buf_ren & (~frame_buf_empty) & (~disp_suspend))
            # simulation_delay frame_buf_rptr <= {frame_buf_rptr[frame_n-2:0], frame_buf_rptr[frame_n-1]};
    end
    
    // ֡�����(����)
    genvar frame_filled_vec_i;
    generate
        for(frame_filled_vec_i = 0;frame_filled_vec_i < frame_n;frame_filled_vec_i = frame_filled_vec_i + 1)
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    // ��ʼʱ֡�����������1֡������ֵ!
                    frame_filled_vec[frame_filled_vec_i] <= frame_filled_vec_i == (frame_n - 1);
                else if((frame_buf_wen & (~frame_buf_full) & frame_buf_wptr[frame_filled_vec_i]) | 
                    (frame_buf_ren & (~frame_buf_empty) & (~disp_suspend) & frame_buf_rptr[frame_filled_vec_i]))
                    // ����: ������ͬʱ������Ч��֡������дʹ�ܺͶ�ʹ��!
                    # simulation_delay frame_filled_vec[frame_filled_vec_i] <= frame_buf_wen & (~frame_buf_full);
            end
        end
    endgenerate
    
    // ��ȡ�µ�һ֡(ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_new_frame_reg <= 1'b0;
        else
            # simulation_delay rd_new_frame_reg <= frame_buf_ren & (~frame_buf_empty) & (~disp_suspend);
    end
    
    /** 
    ֡д��AXISλ��任
    
    pix_data_width*pix_per_clk_for_wt -> 32
    **/
    // λ��任���֡д��AXIS
    wire[31:0] s_axis_pix_data_w;
    wire s_axis_pix_valid_w;
    wire s_axis_pix_ready_w;
    
    axis_dw_cvt #(
        .slave_data_width(pix_data_width*pix_per_clk_for_wt),
        .master_data_width(32),
        .slave_user_width_foreach_byte(1),
        .en_keep("false"),
        .en_last("false"),
        .en_out_isolation("true"),
        .simulation_delay(simulation_delay)
    )wframe_dw_cvt(
        .clk(clk),
        .rst_n(rst_n),
        
        .s_axis_data(s_axis_pix_data),
        .s_axis_keep(),
        .s_axis_user(),
        .s_axis_last(),
        .s_axis_valid(s_axis_pix_valid),
        .s_axis_ready(s_axis_pix_ready),
        
        .m_axis_data(s_axis_pix_data_w),
        .m_axis_keep(),
        .m_axis_user(),
        .m_axis_last(),
        .m_axis_valid(s_axis_pix_valid_w),
        .m_axis_ready(s_axis_pix_ready_w)
    );
    
    /** 
    ֡��ȡAXISλ��任
    
    32 -> pix_data_width*pix_per_clk_for_rd
    **/
    // λ��任ǰ��֡��ȡAXIS
    wire[31:0] m_axis_pix_data_w;
    wire[31:0] m_axis_pix_user_w; // ��ǰ��֡��(����4��)
    wire m_axis_pix_last_w; // ָʾ��֡���1������
    wire m_axis_pix_valid_w;
    wire m_axis_pix_ready_w;
    
    axis_dw_cvt #(
        .slave_data_width(32),
        .master_data_width(pix_data_width*pix_per_clk_for_rd),
        .slave_user_width_foreach_byte(8),
        .en_keep("false"),
        .en_last("true"),
        .en_out_isolation("true"),
        .simulation_delay(simulation_delay)
    )rframe_dw_cvt(
        .clk(clk),
        .rst_n(rst_n),
        
        .s_axis_data(m_axis_pix_data_w),
        .s_axis_keep(),
        .s_axis_user(m_axis_pix_user_w),
        .s_axis_last(m_axis_pix_last_w),
        .s_axis_valid(m_axis_pix_valid_w),
        .s_axis_ready(m_axis_pix_ready_w),
        
        .m_axis_data(m_axis_pix_data),
        .m_axis_keep(),
        .m_axis_user(m_axis_pix_user), // λ��pix_data_width*pix_per_clk_for_rd������λ��8����, ��ȡ��λ
        .m_axis_last(m_axis_pix_last),
        .m_axis_valid(m_axis_pix_valid),
        .m_axis_ready(m_axis_pix_ready)
    );
    
    /** λ��任ǰ��֡��ȡAXIS **/
    reg[clogb2(frame_dwords_n-1):0] rd_frame_cnt; // ֡��ȡ������
    reg m_axis_pix_last_w_reg; // λ��任ǰ��֡��ȡAXIS��last�ź�
    reg[7:0] now_rd_fid; // ��ǰ��֡��
    // AXI��ͨ�����ݻ���
    reg[clogb2(axi_rchn_data_buffer_depth/axi_rchn_max_burst_len):0] rburst_launched_n; // �������Ķ�ͻ������
    wire rburst_buffer_full; // AXI��ͨ�����ݻ�������־
    wire rburst_buffer_wen; // AXI��ͨ�����ݻ���дʹ��
    wire rburst_buffer_ren; // AXI��ͨ�����ݻ����ʹ��
	wire m_axis_pix_last_w2; // ���ݵ�AXI��ͨ��last�ź�
    
    assign rburst_buffer_ren = m_axis_pix_valid_w & m_axis_pix_ready_w & m_axis_pix_last_w2;
    
    generate
        if(axi_rchn_data_buffer_depth == 0)
        begin
            // ��AXI������Rͨ��ֱ�Ӵ��ݸ�λ��任ǰ��֡��ȡAXIS
            assign m_axis_pix_data_w = m_axi_rdata;
            assign m_axis_pix_user_w = {4{now_rd_fid}};
            assign m_axis_pix_last_w = m_axis_pix_last_w_reg;
			assign m_axis_pix_last_w2 = m_axi_rlast;
            assign m_axis_pix_valid_w = m_axi_rvalid;
            assign m_axi_rready = m_axis_pix_ready_w;
            
            assign rburst_buffer_full = 1'b0;
        end
        else
        begin
            reg rburst_buffer_full_reg; // AXI��ͨ�����ݻ�������־
            wire[7:0] now_rd_fid_passed; // ���ݵĵ�ǰ��֡��
            
            assign rburst_buffer_full = rburst_buffer_full_reg;
            assign m_axis_pix_user_w = {4{now_rd_fid_passed}};
            
            // �������Ķ�ͻ������
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rburst_launched_n <= 0;
                else if((rburst_buffer_wen & (~rburst_buffer_full)) ^ rburst_buffer_ren)
                    # simulation_delay rburst_launched_n <= rburst_buffer_ren ? (rburst_launched_n-1):(rburst_launched_n+1);
            end
            
            // AXI��ͨ�����ݻ�������־
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rburst_buffer_full_reg <= 1'b0;
                else if((rburst_buffer_wen & (~rburst_buffer_full)) ^ rburst_buffer_ren)
                    # simulation_delay rburst_buffer_full_reg <= rburst_buffer_ren ? 1'b0:(rburst_launched_n == (axi_rchn_data_buffer_depth/axi_rchn_max_burst_len-1));
            end
            
            // AXI��ͨ������buffer
            ram_fifo_wrapper #(
                .fwft_mode("true"),
                .ram_type((axi_rchn_data_buffer_depth <= 64) ? "lutram":"bram"),
                .en_bram_reg("false"),
                .fifo_depth(axi_rchn_data_buffer_depth),
                .fifo_data_width(32 + 8 + 2),
                .full_assert_polarity("low"),
                .empty_assert_polarity("low"),
                .almost_full_assert_polarity("no"),
                .almost_empty_assert_polarity("no"),
                .en_data_cnt("false"),
                .almost_full_th(),
                .almost_empty_th(),
                .simulation_delay(simulation_delay)
            )axi_rchn_data_buffer_fifo(
                .clk(clk),
                .rst_n(rst_n),
                
                .fifo_wen(m_axi_rvalid),
                .fifo_din({m_axis_pix_last_w_reg, m_axi_rlast, now_rd_fid, m_axi_rdata}),
                .fifo_full_n(m_axi_rready),
                
                .fifo_ren(m_axis_pix_ready_w),
                .fifo_dout({m_axis_pix_last_w, m_axis_pix_last_w2, now_rd_fid_passed, m_axis_pix_data_w}),
                .fifo_empty_n(m_axis_pix_valid_w)
            );
        end
    endgenerate
    
    // ֡��ȡ������
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_frame_cnt <= 0;
        else if(m_axi_rvalid & m_axi_rready)
            # simulation_delay rd_frame_cnt <= (rd_frame_cnt == (frame_dwords_n-1)) ? 0:(rd_frame_cnt + 1);
    end
    // λ��任ǰ��֡��ȡAXIS��last�ź�
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            m_axis_pix_last_w_reg <= 1'b0;
        else if(m_axi_rvalid & m_axi_rready)
            # simulation_delay m_axis_pix_last_w_reg <= rd_frame_cnt == (frame_dwords_n-2);
    end
    
    /** AXI������ARͨ�� **/
    wire rd_frame_last_trans; // ֡��ȡ֡�����1�δ���(��־)
    reg[clogb2(frame_dwords_n):0] rd_frame_remaining_trans_n; // ֡��ȡ֡��ʣ�ഫ�����
    reg[clogb2(baseaddr_of_last_frame):0] rd_frame_baseaddr; // ֡��ȡ�׵�ַ
    reg[clogb2(frame_size-1):0] rd_frame_ofsaddr; // ֡��ȡƫ�Ƶ�ַ
    reg rd_frame_last_trans_running; // ֡��ȡ֡�����1�δ��������(��־)
    wire rd_frame_last_trans_done; // ֡��ȡ֡�����1�δ������(ָʾ)
    // ֡��ȡ��������fifo
    wire rd_frame_trans_fifo_wen;
    wire rd_frame_trans_fifo_din; // ��ǰ�Ƿ�֡�����1�δ���
    wire rd_frame_trans_fifo_full;
    // ����:֡��ȡ��������fifo��ʹ����Чʱfifo�ض��ǿ�!
    wire rd_frame_trans_fifo_ren;
    wire rd_frame_trans_fifo_dout; // ��ǰ�Ƿ�֡�����1�δ���
    
    assign m_axi_araddr = rd_frame_baseaddr + rd_frame_ofsaddr;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlen = (rd_frame_last_trans ? rd_frame_remaining_trans_n:axi_rchn_max_burst_len) - 8'd1;
    assign m_axi_arsize = 3'b010;
    // ARͨ����������:  (~rd_frame_trans_fifo_full) & (~rd_frame_last_trans_running) & (~rburst_buffer_full) & m_axi_arready
    // ���������ݻ���������ʱ������Ч�Ķ���ַ!
    assign m_axi_arvalid = (~rd_frame_trans_fifo_full) & (~rd_frame_last_trans_running) & (~rburst_buffer_full);
    
    assign frame_buf_ren = rd_frame_last_trans_done;
    assign rburst_buffer_wen = (~rd_frame_trans_fifo_full) & (~rd_frame_last_trans_running) & m_axi_arready;
    
    assign rd_frame_last_trans = rd_frame_remaining_trans_n <= axi_rchn_max_burst_len;
    assign rd_frame_trans_fifo_wen = m_axi_arvalid & m_axi_arready;
    assign rd_frame_trans_fifo_din = rd_frame_last_trans;
    assign rd_frame_trans_fifo_ren = m_axi_rvalid & m_axi_rready & m_axi_rlast;
    assign rd_frame_last_trans_done = rd_frame_trans_fifo_ren & rd_frame_trans_fifo_dout;
    
    // ��ǰ��֡��
	always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
			now_rd_fid <= 8'd0;
		else if(frame_buf_ren & (~frame_buf_empty) & (~disp_suspend)) // ֡�������ǿ��Ҳ���ͣʱ������1֡, �����ظ���ǰ֡!
			# simulation_delay now_rd_fid <= now_rd_fid + 8'd1;
	end
    
    // ֡��ȡ֡��ʣ�ഫ�����
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_frame_remaining_trans_n <= frame_dwords_n;
        else if(m_axi_arvalid & m_axi_arready)
            # simulation_delay rd_frame_remaining_trans_n <= rd_frame_last_trans ? frame_dwords_n:(rd_frame_remaining_trans_n - axi_rchn_max_burst_len);
    end
    // ֡��ȡ�׵�ַ
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_frame_baseaddr <= baseaddr_of_last_frame;
        else if(frame_buf_ren & (~frame_buf_empty) & (~disp_suspend)) // ֡�������ǿ�ʱ������1֡, ��ʱ�ظ���ǰ֡!
            # simulation_delay rd_frame_baseaddr <= frame_buf_rptr[frame_n-1] ? frame_buffer_baseaddr:(rd_frame_baseaddr + frame_size);
    end
    // ֡��ȡƫ�Ƶ�ַ
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_frame_ofsaddr <= 0;
        else if(m_axi_arvalid & m_axi_arready)
            # simulation_delay rd_frame_ofsaddr <= rd_frame_last_trans ? 0:(rd_frame_ofsaddr + axi_rchn_max_burst_len * 4);
    end
    
    // ֡��ȡ֡�����1�δ��������(��־)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_frame_last_trans_running <= 1'b0;
        else
            # simulation_delay rd_frame_last_trans_running <= rd_frame_last_trans_running ? (~rd_frame_last_trans_done):(m_axi_arvalid & m_axi_arready & rd_frame_last_trans);
    end
    
    /** ֡��ȡ��������fifo **/
    rw_frame_trans_fifo #(
        .axi_rwaddr_outstanding(axi_raddr_outstanding),
        .simulation_delay(simulation_delay)
    )rd_frame_trans_fifo_u(
        .clk(clk),
        .rst_n(rst_n),
        
        .rw_frame_trans_fifo_wen(rd_frame_trans_fifo_wen),
        .rw_frame_trans_fifo_full(rd_frame_trans_fifo_full),
        .rw_frame_trans_fifo_din(rd_frame_trans_fifo_din),
        
        .rw_frame_trans_fifo_ren(rd_frame_trans_fifo_ren),
        .rw_frame_trans_fifo_empty(),
        .rw_frame_trans_fifo_dout(rd_frame_trans_fifo_dout)
    );
    
    /** AXI������Wͨ�� **/
    reg[clogb2(frame_dwords_n-1):0] wt_frame_cnt; // ֡д�������
    reg[clogb2(axi_wchn_max_burst_len-1):0] trans_cnt_at_wchn; // λ��Wͨ���Ĵ��������
    wire s_axis_pix_last_w; // дͻ�����1�δ���
    // AXIдͨ�����ݻ���
    // ����: �ѻ����дͻ���������ᳬ��axi_wchn_data_buffer_depth!
    reg[clogb2(axi_wchn_data_buffer_depth):0] wburst_buffered_n; // �ѻ����дͻ������
    wire wburst_buffer_empty; // AXIдͨ�����ݻ���ձ�־
    wire wburst_buffer_wen; // AXIдͨ�����ݻ���дʹ��
    wire wburst_buffer_ren; // AXIдͨ�����ݻ����ʹ��
    
    assign m_axi_wstrb = 4'b1111;
    
    assign s_axis_pix_last_w = (wt_frame_cnt == (frame_dwords_n-1)) | (trans_cnt_at_wchn == (axi_wchn_max_burst_len-1));
    assign wburst_buffer_wen = s_axis_pix_valid_w & s_axis_pix_ready_w & s_axis_pix_last_w;
    
    generate
        if(axi_wchn_data_buffer_depth == 0)
        begin
            // ��λ��任���֡д��AXISֱ�Ӵ��ݸ�AXI������Wͨ��
            assign m_axi_wdata = s_axis_pix_data_w;
            assign m_axi_wlast = s_axis_pix_last_w;
            assign m_axi_wvalid = s_axis_pix_valid_w;
            assign s_axis_pix_ready_w = m_axi_wready;
            
            assign wburst_buffer_empty = 1'b0;
        end
        else
        begin
            reg wburst_buffer_empty_reg; // AXIдͨ�����ݻ���ձ�־
            
            assign wburst_buffer_empty = wburst_buffer_empty_reg;
            
            // �ѻ����дͻ������
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wburst_buffered_n <= 0;
                else if(wburst_buffer_wen ^ (wburst_buffer_ren & (~wburst_buffer_empty)))
                    # simulation_delay wburst_buffered_n <= wburst_buffer_wen ? (wburst_buffered_n + 1):(wburst_buffered_n - 1);
            end
            
            // AXIдͨ�����ݻ���ձ�־
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wburst_buffer_empty_reg <= 1'b1;
                else if(wburst_buffer_wen ^ (wburst_buffer_ren & (~wburst_buffer_empty)))
                    # simulation_delay wburst_buffer_empty_reg <= wburst_buffer_wen ? 1'b0:(wburst_buffered_n == 1);
            end
            
            // AXIдͨ������buffer
            ram_fifo_wrapper #(
                .fwft_mode("true"),
                .ram_type((axi_wchn_data_buffer_depth <= 64) ? "lutram":"bram"),
                .en_bram_reg("false"),
                .fifo_depth(axi_wchn_data_buffer_depth),
                .fifo_data_width(32 + 1),
                .full_assert_polarity("low"),
                .empty_assert_polarity("low"),
                .almost_full_assert_polarity("no"),
                .almost_empty_assert_polarity("no"),
                .en_data_cnt("false"),
                .almost_full_th(),
                .almost_empty_th(),
                .simulation_delay(simulation_delay)
            )axi_wchn_data_buffer_fifo(
                .clk(clk),
                .rst_n(rst_n),
                
                .fifo_wen(s_axis_pix_valid_w),
                .fifo_din({s_axis_pix_last_w, s_axis_pix_data_w}),
                .fifo_full_n(s_axis_pix_ready_w),
                
                .fifo_ren(m_axi_wready),
                .fifo_dout({m_axi_wlast, m_axi_wdata}),
                .fifo_empty_n(m_axi_wvalid)
            );
        end
    endgenerate
    
    // ֡д�������
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_frame_cnt <= 0;
        else if(s_axis_pix_valid_w & s_axis_pix_ready_w)
            # simulation_delay wt_frame_cnt <= (wt_frame_cnt == (frame_dwords_n-1)) ? 0:(wt_frame_cnt + 1);
    end
    // λ��Wͨ���Ĵ��������
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            trans_cnt_at_wchn <= 0;
        else if(s_axis_pix_valid_w & s_axis_pix_ready_w)
            # simulation_delay trans_cnt_at_wchn <= ((wt_frame_cnt == (frame_dwords_n-1)) | (trans_cnt_at_wchn == (axi_wchn_max_burst_len-1))) ? 
                0:(trans_cnt_at_wchn + 1);
    end
    
    /** AXI������AWͨ�� **/
    wire wt_frame_last_trans; // ֡д��֡�����1�δ���(��־)
    reg[clogb2(frame_dwords_n):0] wt_frame_remaining_trans_n; // ֡д��֡��ʣ�ഫ�����
    reg[clogb2(baseaddr_of_last_frame):0] wt_frame_baseaddr; // ֡д���׵�ַ
    reg[clogb2(frame_size-1):0] wt_frame_ofsaddr; // ֡д��ƫ�Ƶ�ַ
    reg wt_frame_last_trans_running; // ֡д��֡�����1�δ��������(��־)
    wire wt_frame_last_trans_done; // ֡д��֡�����1�δ������(ָʾ)
    reg frame_buf_wen_reg; // ֡������дʹ��
    // ֡д�봫������fifo
    wire wt_frame_trans_fifo_wen;
    wire wt_frame_trans_fifo_din; // ��ǰ�Ƿ�֡�����1�δ���
    wire wt_frame_trans_fifo_full;
    // ����:֡д�봫������fifo��ʹ����Чʱfifo�ض��ǿ�!
    wire wt_frame_trans_fifo_ren;
    wire wt_frame_trans_fifo_dout; // ��ǰ�Ƿ�֡�����1�δ���
    
    assign m_axi_awaddr = wt_frame_baseaddr + wt_frame_ofsaddr;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlen = (wt_frame_last_trans ? wt_frame_remaining_trans_n:axi_wchn_max_burst_len) - 8'd1;
    assign m_axi_awsize = 3'b010;
    // AWͨ����������:  (~wt_frame_trans_fifo_full) & (~wt_frame_last_trans_running) & (~wburst_buffer_empty) & m_axi_awready
    // ����д���ݻ������ǿ�ʱ������Ч��д��ַ!
    assign m_axi_awvalid = (~wt_frame_trans_fifo_full) & (~wt_frame_last_trans_running) & (~wburst_buffer_empty);
    
    assign frame_buf_wen = frame_buf_wen_reg;
    assign wburst_buffer_ren = (~wt_frame_trans_fifo_full) & (~wt_frame_last_trans_running) & m_axi_awready;
    
    assign wt_frame_last_trans = wt_frame_remaining_trans_n <= axi_wchn_max_burst_len;
    assign wt_frame_trans_fifo_wen = m_axi_awvalid & m_axi_awready;
    assign wt_frame_trans_fifo_din = wt_frame_last_trans;
    assign wt_frame_trans_fifo_ren = m_axi_bvalid & m_axi_bready;
    assign wt_frame_last_trans_done = wt_frame_trans_fifo_ren & wt_frame_trans_fifo_dout;
    
    // ֡д��֡��ʣ�ഫ�����
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_frame_remaining_trans_n <= frame_dwords_n;
        else if(m_axi_awvalid & m_axi_awready)
            # simulation_delay wt_frame_remaining_trans_n <= wt_frame_last_trans ? frame_dwords_n:(wt_frame_remaining_trans_n - axi_wchn_max_burst_len);
    end
    // ֡д���׵�ַ
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_frame_baseaddr <= frame_buffer_baseaddr;
        else if(frame_buf_wen & (~frame_buf_full))
            # simulation_delay wt_frame_baseaddr <= frame_buf_wptr[frame_n-1] ? frame_buffer_baseaddr:(wt_frame_baseaddr + frame_size);
    end
    // ֡д��ƫ�Ƶ�ַ
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_frame_ofsaddr <= 0;
        else if(m_axi_awvalid & m_axi_awready)
            # simulation_delay wt_frame_ofsaddr <= wt_frame_last_trans ? 0:(wt_frame_ofsaddr + axi_wchn_max_burst_len * 4);
    end
    
    // ֡д��֡�����1�δ��������(��־)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_frame_last_trans_running <= 1'b0;
        else
            # simulation_delay wt_frame_last_trans_running <= wt_frame_last_trans_running ? (~(frame_buf_wen & (~frame_buf_full))):
                (m_axi_awvalid & m_axi_awready & wt_frame_last_trans);
    end
    
    // ֡������дʹ��
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            frame_buf_wen_reg <= 1'b0;
        else // ֡������дʹ�ܱ�����Чֱ��֡����������!
            # simulation_delay frame_buf_wen_reg <= frame_buf_wen_reg ? frame_buf_full:wt_frame_last_trans_done;
    end
    
    /** ֡д�봫������fifo **/
    rw_frame_trans_fifo #(
        .axi_rwaddr_outstanding(axi_waddr_outstanding),
        .simulation_delay(simulation_delay)
    )wt_frame_trans_fifo_u(
        .clk(clk),
        .rst_n(rst_n),
        
        .rw_frame_trans_fifo_wen(wt_frame_trans_fifo_wen),
        .rw_frame_trans_fifo_full(wt_frame_trans_fifo_full),
        .rw_frame_trans_fifo_din(wt_frame_trans_fifo_din),
        
        .rw_frame_trans_fifo_ren(wt_frame_trans_fifo_ren),
        .rw_frame_trans_fifo_empty(),
        .rw_frame_trans_fifo_dout(wt_frame_trans_fifo_dout)
    );
    
    /** AXI������Bͨ�� **/
    assign m_axi_bready = 1'b1;
    
endmodule
