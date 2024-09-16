`timescale 1ns / 1ps
/********************************************************************
本模块: AXI帧缓存(核心)

描述: 
实现了帧写入AXIS到AXI写通道, 帧读取AXIS到AXI读通道之间的转换
AXI主机的地址/数据位宽固定为32

注意：
帧大小(img_n * pix_data_width / 8)必须能被4整除
未对AXI主机实施4KB边界保护
AXI读地址缓冲深度(axi_raddr_outstanding)和AXI读通道数据buffer深度(axi_rchn_data_buffer_depth)共同决定AR通道的握手

将缓冲区帧个数(frame_n)和帧缓冲区首地址(frame_buffer_baseaddr)更改为运行时参数???

协议:
AXIS MASTER/SLAVE
AXI MASTER

作者: 陈家耀
日期: 2024/05/07
********************************************************************/


module axi_frame_buffer_core #(
    parameter integer frame_n = 4, // 缓冲区帧个数(必须在范围[3, 16]内)
    parameter integer frame_buffer_baseaddr = 0, // 帧缓冲区首地址(必须能被4整除)
    parameter integer img_n = 1920 * 1080, // 图像大小(以像素个数计)
    parameter integer pix_data_width = 24, // 像素位宽(必须能被8整除)
	parameter integer pix_per_clk_for_wt = 1, // 每clk写的像素个数
	parameter integer pix_per_clk_for_rd = 1, // 每clk读的像素个数
    parameter integer axi_raddr_outstanding = 2, // AXI读地址缓冲深度(1 | 2 | 4 | 8 | 16)
    parameter integer axi_rchn_max_burst_len = 64, // AXI读通道最大突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
    parameter integer axi_waddr_outstanding = 2, // AXI写地址缓冲深度(1 | 2 | 4 | 8 | 16)
    parameter integer axi_wchn_max_burst_len = 64, // AXI写通道最大突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
    parameter integer axi_wchn_data_buffer_depth = 512, // AXI写通道数据buffer深度(0 | 16 | 32 | 64 | ..., 设为0时表示不使用)
    parameter integer axi_rchn_data_buffer_depth = 512, // AXI读通道数据buffer深度(0 | 16 | 32 | 64 | ..., 设为0时表示不使用)
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 帧缓存控制和状态
    input wire disp_suspend, // 暂停取新的一帧(标志)
    output wire rd_new_frame, // 读取新的一帧(指示)
    
    // 帧写入AXIS
    input wire[pix_data_width*pix_per_clk_for_wt-1:0] s_axis_pix_data,
    input wire s_axis_pix_valid,
    output wire s_axis_pix_ready,
    
    // 帧读取AXIS
    output wire[pix_data_width*pix_per_clk_for_rd-1:0] m_axis_pix_data,
    output wire[7:0] m_axis_pix_user, // 当前读帧号
    output wire m_axis_pix_last, // 指示本帧最后1个像素
    output wire m_axis_pix_valid,
    input wire m_axis_pix_ready,
    
    // AXI主机
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

    // 计算log2(bit_depth)               
    function integer clogb2 (input integer bit_depth);
        integer temp;
    begin
        temp = bit_depth;
        for(clogb2 = -1;temp > 0;clogb2 = clogb2 + 1)
            temp = temp >> 1;
    end
    endfunction
    
    /** 常量 **/
    localparam integer frame_size = img_n * pix_data_width / 8; // 帧大小(以字节计)
    localparam integer frame_dwords_n = frame_size / 4; // 每帧的双字个数
    localparam integer baseaddr_of_last_frame = frame_buffer_baseaddr + (frame_n - 1) * frame_size; // 帧缓冲区里最后1帧的首地址
    
    /** 帧缓存 **/
    wire frame_buf_wen; // 帧缓冲区写使能
    wire frame_buf_full; // 帧缓冲区满标志
    reg[frame_n-1:0] frame_buf_wptr; // 帧缓冲区写指针(独热码)
    wire[frame_n-1:0] frame_buf_wptr_add1; // 帧缓冲区写指针(独热码) + 1
    wire frame_buf_ren; // 帧缓冲区读使能
    wire frame_buf_empty; // 帧缓冲区空标志
    reg[frame_n-1:0] frame_buf_rptr; // 帧缓冲区读指针(独热码)
    wire[frame_n-1:0] frame_buf_rptr_add1; // 帧缓冲区读指针(独热码) + 1
    reg[frame_n-1:0] frame_filled_vec; // 帧已填充(向量)
    reg rd_new_frame_reg; // 读取新的一帧(指示)
    
    assign rd_new_frame = rd_new_frame_reg;
    
    assign frame_buf_full = (frame_buf_wptr_add1 & frame_filled_vec) != {frame_n{1'b0}};
    assign frame_buf_wptr_add1 = {frame_buf_wptr[frame_n-2:0], frame_buf_wptr[frame_n-1]};
    
    assign frame_buf_empty = (frame_buf_rptr_add1 & frame_filled_vec) == {frame_n{1'b0}};
    assign frame_buf_rptr_add1 = {frame_buf_rptr[frame_n-2:0], frame_buf_rptr[frame_n-1]};
    
    // 帧缓冲区写指针(独热码)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            frame_buf_wptr <= {{(frame_n-1){1'b0}}, 1'b1};
        else if(frame_buf_wen & (~frame_buf_full))
            # simulation_delay frame_buf_wptr <= {frame_buf_wptr[frame_n-2:0], frame_buf_wptr[frame_n-1]};
    end
    // 帧缓冲区读指针(独热码)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            frame_buf_rptr <= {1'b1, {(frame_n-1){1'b0}}};
        else if(frame_buf_ren & (~frame_buf_empty) & (~disp_suspend))
            # simulation_delay frame_buf_rptr <= {frame_buf_rptr[frame_n-2:0], frame_buf_rptr[frame_n-1]};
    end
    
    // 帧已填充(向量)
    genvar frame_filled_vec_i;
    generate
        for(frame_filled_vec_i = 0;frame_filled_vec_i < frame_n;frame_filled_vec_i = frame_filled_vec_i + 1)
        begin
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    // 初始时帧缓冲区里最后1帧被填充空值!
                    frame_filled_vec[frame_filled_vec_i] <= frame_filled_vec_i == (frame_n - 1);
                else if((frame_buf_wen & (~frame_buf_full) & frame_buf_wptr[frame_filled_vec_i]) | 
                    (frame_buf_ren & (~frame_buf_empty) & (~disp_suspend) & frame_buf_rptr[frame_filled_vec_i]))
                    // 断言: 不可能同时产生有效的帧缓冲区写使能和读使能!
                    # simulation_delay frame_filled_vec[frame_filled_vec_i] <= frame_buf_wen & (~frame_buf_full);
            end
        end
    endgenerate
    
    // 读取新的一帧(指示)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_new_frame_reg <= 1'b0;
        else
            # simulation_delay rd_new_frame_reg <= frame_buf_ren & (~frame_buf_empty) & (~disp_suspend);
    end
    
    /** 
    帧写入AXIS位宽变换
    
    pix_data_width*pix_per_clk_for_wt -> 32
    **/
    // 位宽变换后的帧写入AXIS
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
    帧读取AXIS位宽变换
    
    32 -> pix_data_width*pix_per_clk_for_rd
    **/
    // 位宽变换前的帧读取AXIS
    wire[31:0] m_axis_pix_data_w;
    wire[31:0] m_axis_pix_user_w; // 当前读帧号(复制4个)
    wire m_axis_pix_last_w; // 指示本帧最后1个像素
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
        .m_axis_user(m_axis_pix_user), // 位宽pix_data_width*pix_per_clk_for_rd可能与位宽8不符, 截取低位
        .m_axis_last(m_axis_pix_last),
        .m_axis_valid(m_axis_pix_valid),
        .m_axis_ready(m_axis_pix_ready)
    );
    
    /** 位宽变换前的帧读取AXIS **/
    reg[clogb2(frame_dwords_n-1):0] rd_frame_cnt; // 帧读取计数器
    reg m_axis_pix_last_w_reg; // 位宽变换前的帧读取AXIS的last信号
    reg[7:0] now_rd_fid; // 当前读帧号
    // AXI读通道数据缓冲
    reg[clogb2(axi_rchn_data_buffer_depth/axi_rchn_max_burst_len):0] rburst_launched_n; // 已启动的读突发个数
    wire rburst_buffer_full; // AXI读通道数据缓冲满标志
    wire rburst_buffer_wen; // AXI读通道数据缓冲写使能
    wire rburst_buffer_ren; // AXI读通道数据缓冲读使能
	wire m_axis_pix_last_w2; // 传递的AXI读通道last信号
    
    assign rburst_buffer_ren = m_axis_pix_valid_w & m_axis_pix_ready_w & m_axis_pix_last_w2;
    
    generate
        if(axi_rchn_data_buffer_depth == 0)
        begin
            // 将AXI主机的R通道直接传递给位宽变换前的帧读取AXIS
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
            reg rburst_buffer_full_reg; // AXI读通道数据缓冲满标志
            wire[7:0] now_rd_fid_passed; // 传递的当前读帧号
            
            assign rburst_buffer_full = rburst_buffer_full_reg;
            assign m_axis_pix_user_w = {4{now_rd_fid_passed}};
            
            // 已启动的读突发个数
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rburst_launched_n <= 0;
                else if((rburst_buffer_wen & (~rburst_buffer_full)) ^ rburst_buffer_ren)
                    # simulation_delay rburst_launched_n <= rburst_buffer_ren ? (rburst_launched_n-1):(rburst_launched_n+1);
            end
            
            // AXI读通道数据缓冲满标志
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rburst_buffer_full_reg <= 1'b0;
                else if((rburst_buffer_wen & (~rburst_buffer_full)) ^ rburst_buffer_ren)
                    # simulation_delay rburst_buffer_full_reg <= rburst_buffer_ren ? 1'b0:(rburst_launched_n == (axi_rchn_data_buffer_depth/axi_rchn_max_burst_len-1));
            end
            
            // AXI读通道数据buffer
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
    
    // 帧读取计数器
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_frame_cnt <= 0;
        else if(m_axi_rvalid & m_axi_rready)
            # simulation_delay rd_frame_cnt <= (rd_frame_cnt == (frame_dwords_n-1)) ? 0:(rd_frame_cnt + 1);
    end
    // 位宽变换前的帧读取AXIS的last信号
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            m_axis_pix_last_w_reg <= 1'b0;
        else if(m_axi_rvalid & m_axi_rready)
            # simulation_delay m_axis_pix_last_w_reg <= rd_frame_cnt == (frame_dwords_n-2);
    end
    
    /** AXI主机的AR通道 **/
    wire rd_frame_last_trans; // 帧读取帧内最后1次传输(标志)
    reg[clogb2(frame_dwords_n):0] rd_frame_remaining_trans_n; // 帧读取帧内剩余传输次数
    reg[clogb2(baseaddr_of_last_frame):0] rd_frame_baseaddr; // 帧读取首地址
    reg[clogb2(frame_size-1):0] rd_frame_ofsaddr; // 帧读取偏移地址
    reg rd_frame_last_trans_running; // 帧读取帧内最后1次传输进行中(标志)
    wire rd_frame_last_trans_done; // 帧读取帧内最后1次传输完成(指示)
    // 帧读取传输事务fifo
    wire rd_frame_trans_fifo_wen;
    wire rd_frame_trans_fifo_din; // 当前是否帧内最后1次传输
    wire rd_frame_trans_fifo_full;
    // 断言:帧读取传输事务fifo读使能有效时fifo必定非空!
    wire rd_frame_trans_fifo_ren;
    wire rd_frame_trans_fifo_dout; // 当前是否帧内最后1次传输
    
    assign m_axi_araddr = rd_frame_baseaddr + rd_frame_ofsaddr;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlen = (rd_frame_last_trans ? rd_frame_remaining_trans_n:axi_rchn_max_burst_len) - 8'd1;
    assign m_axi_arsize = 3'b010;
    // AR通道握手条件:  (~rd_frame_trans_fifo_full) & (~rd_frame_last_trans_running) & (~rburst_buffer_full) & m_axi_arready
    // 仅当读数据缓存区非满时产生有效的读地址!
    assign m_axi_arvalid = (~rd_frame_trans_fifo_full) & (~rd_frame_last_trans_running) & (~rburst_buffer_full);
    
    assign frame_buf_ren = rd_frame_last_trans_done;
    assign rburst_buffer_wen = (~rd_frame_trans_fifo_full) & (~rd_frame_last_trans_running) & m_axi_arready;
    
    assign rd_frame_last_trans = rd_frame_remaining_trans_n <= axi_rchn_max_burst_len;
    assign rd_frame_trans_fifo_wen = m_axi_arvalid & m_axi_arready;
    assign rd_frame_trans_fifo_din = rd_frame_last_trans;
    assign rd_frame_trans_fifo_ren = m_axi_rvalid & m_axi_rready & m_axi_rlast;
    assign rd_frame_last_trans_done = rd_frame_trans_fifo_ren & rd_frame_trans_fifo_dout;
    
    // 当前读帧号
	always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
			now_rd_fid <= 8'd0;
		else if(frame_buf_ren & (~frame_buf_empty) & (~disp_suspend)) // 帧缓冲区非空且不暂停时跳到下1帧, 否则重复当前帧!
			# simulation_delay now_rd_fid <= now_rd_fid + 8'd1;
	end
    
    // 帧读取帧内剩余传输次数
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_frame_remaining_trans_n <= frame_dwords_n;
        else if(m_axi_arvalid & m_axi_arready)
            # simulation_delay rd_frame_remaining_trans_n <= rd_frame_last_trans ? frame_dwords_n:(rd_frame_remaining_trans_n - axi_rchn_max_burst_len);
    end
    // 帧读取首地址
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_frame_baseaddr <= baseaddr_of_last_frame;
        else if(frame_buf_ren & (~frame_buf_empty) & (~disp_suspend)) // 帧缓冲区非空时跳到下1帧, 空时重复当前帧!
            # simulation_delay rd_frame_baseaddr <= frame_buf_rptr[frame_n-1] ? frame_buffer_baseaddr:(rd_frame_baseaddr + frame_size);
    end
    // 帧读取偏移地址
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_frame_ofsaddr <= 0;
        else if(m_axi_arvalid & m_axi_arready)
            # simulation_delay rd_frame_ofsaddr <= rd_frame_last_trans ? 0:(rd_frame_ofsaddr + axi_rchn_max_burst_len * 4);
    end
    
    // 帧读取帧内最后1次传输进行中(标志)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_frame_last_trans_running <= 1'b0;
        else
            # simulation_delay rd_frame_last_trans_running <= rd_frame_last_trans_running ? (~rd_frame_last_trans_done):(m_axi_arvalid & m_axi_arready & rd_frame_last_trans);
    end
    
    /** 帧读取传输事务fifo **/
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
    
    /** AXI主机的W通道 **/
    reg[clogb2(frame_dwords_n-1):0] wt_frame_cnt; // 帧写入计数器
    reg[clogb2(axi_wchn_max_burst_len-1):0] trans_cnt_at_wchn; // 位于W通道的传输计数器
    wire s_axis_pix_last_w; // 写突发最后1次传输
    // AXI写通道数据缓冲
    // 断言: 已缓存的写突发个数不会超过axi_wchn_data_buffer_depth!
    reg[clogb2(axi_wchn_data_buffer_depth):0] wburst_buffered_n; // 已缓存的写突发个数
    wire wburst_buffer_empty; // AXI写通道数据缓冲空标志
    wire wburst_buffer_wen; // AXI写通道数据缓冲写使能
    wire wburst_buffer_ren; // AXI写通道数据缓冲读使能
    
    assign m_axi_wstrb = 4'b1111;
    
    assign s_axis_pix_last_w = (wt_frame_cnt == (frame_dwords_n-1)) | (trans_cnt_at_wchn == (axi_wchn_max_burst_len-1));
    assign wburst_buffer_wen = s_axis_pix_valid_w & s_axis_pix_ready_w & s_axis_pix_last_w;
    
    generate
        if(axi_wchn_data_buffer_depth == 0)
        begin
            // 将位宽变换后的帧写入AXIS直接传递给AXI主机的W通道
            assign m_axi_wdata = s_axis_pix_data_w;
            assign m_axi_wlast = s_axis_pix_last_w;
            assign m_axi_wvalid = s_axis_pix_valid_w;
            assign s_axis_pix_ready_w = m_axi_wready;
            
            assign wburst_buffer_empty = 1'b0;
        end
        else
        begin
            reg wburst_buffer_empty_reg; // AXI写通道数据缓冲空标志
            
            assign wburst_buffer_empty = wburst_buffer_empty_reg;
            
            // 已缓存的写突发个数
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wburst_buffered_n <= 0;
                else if(wburst_buffer_wen ^ (wburst_buffer_ren & (~wburst_buffer_empty)))
                    # simulation_delay wburst_buffered_n <= wburst_buffer_wen ? (wburst_buffered_n + 1):(wburst_buffered_n - 1);
            end
            
            // AXI写通道数据缓冲空标志
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wburst_buffer_empty_reg <= 1'b1;
                else if(wburst_buffer_wen ^ (wburst_buffer_ren & (~wburst_buffer_empty)))
                    # simulation_delay wburst_buffer_empty_reg <= wburst_buffer_wen ? 1'b0:(wburst_buffered_n == 1);
            end
            
            // AXI写通道数据buffer
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
    
    // 帧写入计数器
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_frame_cnt <= 0;
        else if(s_axis_pix_valid_w & s_axis_pix_ready_w)
            # simulation_delay wt_frame_cnt <= (wt_frame_cnt == (frame_dwords_n-1)) ? 0:(wt_frame_cnt + 1);
    end
    // 位于W通道的传输计数器
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            trans_cnt_at_wchn <= 0;
        else if(s_axis_pix_valid_w & s_axis_pix_ready_w)
            # simulation_delay trans_cnt_at_wchn <= ((wt_frame_cnt == (frame_dwords_n-1)) | (trans_cnt_at_wchn == (axi_wchn_max_burst_len-1))) ? 
                0:(trans_cnt_at_wchn + 1);
    end
    
    /** AXI主机的AW通道 **/
    wire wt_frame_last_trans; // 帧写入帧内最后1次传输(标志)
    reg[clogb2(frame_dwords_n):0] wt_frame_remaining_trans_n; // 帧写入帧内剩余传输次数
    reg[clogb2(baseaddr_of_last_frame):0] wt_frame_baseaddr; // 帧写入首地址
    reg[clogb2(frame_size-1):0] wt_frame_ofsaddr; // 帧写入偏移地址
    reg wt_frame_last_trans_running; // 帧写入帧内最后1次传输进行中(标志)
    wire wt_frame_last_trans_done; // 帧写入帧内最后1次传输完成(指示)
    reg frame_buf_wen_reg; // 帧缓冲区写使能
    // 帧写入传输事务fifo
    wire wt_frame_trans_fifo_wen;
    wire wt_frame_trans_fifo_din; // 当前是否帧内最后1次传输
    wire wt_frame_trans_fifo_full;
    // 断言:帧写入传输事务fifo读使能有效时fifo必定非空!
    wire wt_frame_trans_fifo_ren;
    wire wt_frame_trans_fifo_dout; // 当前是否帧内最后1次传输
    
    assign m_axi_awaddr = wt_frame_baseaddr + wt_frame_ofsaddr;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlen = (wt_frame_last_trans ? wt_frame_remaining_trans_n:axi_wchn_max_burst_len) - 8'd1;
    assign m_axi_awsize = 3'b010;
    // AW通道握手条件:  (~wt_frame_trans_fifo_full) & (~wt_frame_last_trans_running) & (~wburst_buffer_empty) & m_axi_awready
    // 仅当写数据缓存区非空时产生有效的写地址!
    assign m_axi_awvalid = (~wt_frame_trans_fifo_full) & (~wt_frame_last_trans_running) & (~wburst_buffer_empty);
    
    assign frame_buf_wen = frame_buf_wen_reg;
    assign wburst_buffer_ren = (~wt_frame_trans_fifo_full) & (~wt_frame_last_trans_running) & m_axi_awready;
    
    assign wt_frame_last_trans = wt_frame_remaining_trans_n <= axi_wchn_max_burst_len;
    assign wt_frame_trans_fifo_wen = m_axi_awvalid & m_axi_awready;
    assign wt_frame_trans_fifo_din = wt_frame_last_trans;
    assign wt_frame_trans_fifo_ren = m_axi_bvalid & m_axi_bready;
    assign wt_frame_last_trans_done = wt_frame_trans_fifo_ren & wt_frame_trans_fifo_dout;
    
    // 帧写入帧内剩余传输次数
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_frame_remaining_trans_n <= frame_dwords_n;
        else if(m_axi_awvalid & m_axi_awready)
            # simulation_delay wt_frame_remaining_trans_n <= wt_frame_last_trans ? frame_dwords_n:(wt_frame_remaining_trans_n - axi_wchn_max_burst_len);
    end
    // 帧写入首地址
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_frame_baseaddr <= frame_buffer_baseaddr;
        else if(frame_buf_wen & (~frame_buf_full))
            # simulation_delay wt_frame_baseaddr <= frame_buf_wptr[frame_n-1] ? frame_buffer_baseaddr:(wt_frame_baseaddr + frame_size);
    end
    // 帧写入偏移地址
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_frame_ofsaddr <= 0;
        else if(m_axi_awvalid & m_axi_awready)
            # simulation_delay wt_frame_ofsaddr <= wt_frame_last_trans ? 0:(wt_frame_ofsaddr + axi_wchn_max_burst_len * 4);
    end
    
    // 帧写入帧内最后1次传输进行中(标志)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_frame_last_trans_running <= 1'b0;
        else
            # simulation_delay wt_frame_last_trans_running <= wt_frame_last_trans_running ? (~(frame_buf_wen & (~frame_buf_full))):
                (m_axi_awvalid & m_axi_awready & wt_frame_last_trans);
    end
    
    // 帧缓冲区写使能
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            frame_buf_wen_reg <= 1'b0;
        else // 帧缓冲区写使能保持有效直到帧缓冲区非满!
            # simulation_delay frame_buf_wen_reg <= frame_buf_wen_reg ? frame_buf_full:wt_frame_last_trans_done;
    end
    
    /** 帧写入传输事务fifo **/
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
    
    /** AXI主机的B通道 **/
    assign m_axi_bready = 1'b1;
    
endmodule
