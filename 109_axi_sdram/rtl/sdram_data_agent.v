`timescale 1ns / 1ps
/********************************************************************
��ģ��: sdram���ݴ���

����:
д���ݹ���fifo -> sdramд����
sdram������ -> �����ݹ���fifo

ע�⣺
д���ݹ���fifo��MEM���ӳ� = 1clk
д/�����ݹ���fifo����ȹ̶�Ϊ512
��ͻ������Ϊȫҳʱ, д/�����ݹ���fifo������Ƭ���Ϊ256, �������ʱΪͻ������

Э��:
EXT FIFO READ/WRITE

����: �¼�ҫ
����: 2024/04/14
********************************************************************/


module sdram_data_agent #(
    parameter integer rw_data_buffer_depth = 1024, // ��д����buffer���(512 | 1024 | 2048 | 4096)
    parameter integer burst_len = -1, // ͻ������(-1 -> ȫҳ; 1 | 2 | 4 | 8)
    parameter integer cas_latency = 2, // sdram��Ǳ����ʱ��(2 | 3)
    parameter integer data_width = 32, // ����λ��
    parameter en_expt_tip = "false", // �Ƿ�ʹ���쳣ָʾ
    parameter real sdram_if_signal_delay = 2.5 // sdram�ӿ��ź��ӳ�
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // ͻ����Ϣ
    input wire new_burst_start, // ͻ����ʼָʾ
    input wire is_write_burst, // �Ƿ�дͻ��
    input wire[7:0] new_burst_len, // ͻ������ - 1
    
    // д���ݹ���fifo���˿�
    output wire wdata_ext_fifo_ren,
    input wire wdata_ext_fifo_empty_n,
    output wire wdata_ext_fifo_mem_ren, // const -> 1'b1
    output wire[clogb2(rw_data_buffer_depth-1):0] wdata_ext_fifo_mem_raddr,
    input wire[data_width+data_width/8-1:0] wdata_ext_fifo_mem_dout, // {keep(data_width/8 bit), data(data_width bit)}
    
    // �����ݹ���fifoд�˿�
    output wire rdata_ext_fifo_wen,
    input wire rdata_ext_fifo_full_n,
    output wire rdata_ext_fifo_mem_wen,
    output wire[clogb2(rw_data_buffer_depth-1):0] rdata_ext_fifo_mem_waddr,
    output wire[data_width:0] rdata_ext_fifo_mem_din, // {last(1bit), data(data_width bit)}
    
    // sdram������
    output wire[data_width/8-1:0] sdram_dqm, // 1'b0 -> data write/output enable; 1'b1 -> data mask/output disable
    input wire[data_width-1:0] sdram_dq_i,
    output wire sdram_dq_t, // ��̬�ŷ���(1��ʾ����, 0��ʾ���)
    output wire[data_width-1:0] sdram_dq_o,
    
    // �쳣ָʾ
    output wire ld_when_wdata_ext_fifo_empty_err, // ��д���ݹ���fifo��ʱȡ����(�쳣ָʾ)
    output wire st_when_rdata_ext_fifo_full_err // �ڶ����ݹ���fifo��ʱ������(�쳣ָʾ)
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
    // ����д���ݹ���fifo�ж���ַ->������ʱ��Ϊ2clk, ���Զ�sdram�����ӳ�2clk, ��������2clk��sdramͻ����ʱ��
    localparam integer sdram_burst_rd_latency = cas_latency + 2; // sdramͻ����ʱ��
    
    /** sdram������ **/
    reg wt_burst_start_d; // �ӳ�1clk��дͻ����ʼ(ָʾ)
    wire wdata_ext_fifo_ren_d2; // �ӳ�2clk��д���ݹ���fifo��ʹ��
    reg sdram_dq_t_reg; // sdram������̬�ŷ���
    reg[data_width-1:0] wdata_ext_fifo_mem_dout_data_d; // �ӳ�1clk��д���ݹ���fifo��MEM�������е�data
    wire wdata_cmd_vld_p2; // ��ǰ2clk������д����(ָʾ)
    wire rdata_cmd_vld_p2; // ��ǰ2clk�����ڶ�����(ָʾ)
    reg wdata_cmd_vld_p1; // ��ǰ1clk������д����(ָʾ)
    reg rdata_cmd_vld_p1; // ��ǰ1clk�����ڶ�����(ָʾ)
    reg rdata_cmd_vld; // ���ڶ�����(ָʾ)
    reg[data_width/8-1:0] sdram_dqm_regs; // sdram�ֽ�����
    
    assign sdram_dqm = sdram_dqm_regs;
    assign sdram_dq_t = sdram_dq_t_reg;
    assign sdram_dq_o = wdata_ext_fifo_mem_dout_data_d;
    
    // ��ǰ1clk������д����(ָʾ)
    // ��ǰ1clk�����ڶ�����(ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            {wdata_cmd_vld_p1, rdata_cmd_vld_p1} <= 2'b00;
        else
            {wdata_cmd_vld_p1, rdata_cmd_vld_p1} <= {wdata_cmd_vld_p2, rdata_cmd_vld_p2};
    end
    
    // ���ڶ�����(ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rdata_cmd_vld <= 1'b0;
        else
            rdata_cmd_vld <= rdata_cmd_vld_p1;
    end
    
    // sdram�ֽ�����
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            sdram_dqm_regs <= {(data_width/8){1'b1}};
        else
        begin
            // ����:wdata_cmd_vld_p1��rdata_cmd_vld_p1������ͬʱΪ1
            case({wdata_cmd_vld_p1, (cas_latency == 2) ? rdata_cmd_vld_p1:rdata_cmd_vld})
                2'b01: sdram_dqm_regs <= # sdram_if_signal_delay {(data_width/8){1'b0}}; // ������ʱDQM����Ч, Ҳ��������obuffer���
                2'b10: sdram_dqm_regs <= # sdram_if_signal_delay (~wdata_ext_fifo_mem_dout[data_width+data_width/8-1:data_width]); // д����ʱȡkeep�źŵİ�λ��
                default: sdram_dqm_regs <= # sdram_if_signal_delay {(data_width/8){1'b1}}; // �Ƕ�дʱDQM����Ч
            endcase
        end
    end
    
    // �ӳ�1clk��дͻ����ʼ(ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_burst_start_d <= 1'b0;
        else
            wt_burst_start_d <= new_burst_start & is_write_burst;
    end
    
    // sdram������̬�ŷ���
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            sdram_dq_t_reg <= 1'b1;
        else if(wt_burst_start_d | wdata_ext_fifo_ren_d2)
            /*
            wt_burst_start_d wdata_ext_fifo_ren_d2 | sdram_dq_t_reg
                   0                  0                  hold
                   0                  1                 1, ����
                   1                  0                 0, ���
                   1                  1                 0, ���
            */
            sdram_dq_t_reg <= # sdram_if_signal_delay (~wt_burst_start_d);
    end
    
    // �ӳ�1clk��д���ݹ���fifo��MEM������
    always @(posedge clk)
        wdata_ext_fifo_mem_dout_data_d <= # sdram_if_signal_delay wdata_ext_fifo_mem_dout[data_width-1:0];
    
    // �ӳ�2clk��д���ݹ���fifo��ʹ��
    ram_based_shift_regs #(
        .data_width(1),
        .delay_n(2),
        .shift_type("ff"),
        .ram_type(),
        .INIT_FILE(),
        .en_output_register_init("true"),
        .output_register_init_v(1'b0),
        .simulation_delay(0)
    )delay_for_wdata_ext_fifo_ren(
        .clk(clk),
        .resetn(rst_n),
        .shift_in(wdata_ext_fifo_ren),
        .ce(1'b1),
        .shift_out(wdata_ext_fifo_ren_d2)
    );
    
    /** д���ݹ���fifo **/
    reg[clogb2(rw_data_buffer_depth-1):0] wdata_ext_fifo_mem_raddr_regs; // д���ݹ���fifo��MEM����ַ
    wire wdata_ext_fifo_ld_data; // ��д���ݹ���fifo��������(ָʾ)
    
    assign wdata_ext_fifo_mem_ren = 1'b1;
    assign wdata_ext_fifo_mem_raddr = wdata_ext_fifo_mem_raddr_regs;
    
    generate
        if(burst_len == 1)
        begin
            assign wdata_ext_fifo_ren = new_burst_start & is_write_burst;
            assign wdata_ext_fifo_ld_data = new_burst_start & is_write_burst;
            assign wdata_cmd_vld_p2 = new_burst_start & is_write_burst;
            
            // д���ݹ���fifo��MEM����ַ
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_raddr_regs <= 0;
                else if(new_burst_start & is_write_burst)
                    wdata_ext_fifo_mem_raddr_regs <= wdata_ext_fifo_mem_raddr_regs + 1;
            end
        end
        else if((burst_len == 2) | (burst_len == 4) | (burst_len == 8))
        begin
            reg[burst_len-1:0] wdata_ext_fifo_item_cnt; // д���ݹ���fifo����Ƭ��������
            
            assign wdata_ext_fifo_ren = wdata_ext_fifo_item_cnt[burst_len-1];
            assign wdata_ext_fifo_ld_data = (new_burst_start & is_write_burst) | (~wdata_ext_fifo_item_cnt[0]);
            assign wdata_cmd_vld_p2 = (new_burst_start & is_write_burst) | (~wdata_ext_fifo_item_cnt[0]);
            
            // д���ݹ���fifo����Ƭ��������
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_item_cnt <= {{(burst_len-1){1'b0}}, 1'b1};
                else if((new_burst_start & is_write_burst) | (~wdata_ext_fifo_item_cnt[0]))
                    wdata_ext_fifo_item_cnt <= {wdata_ext_fifo_item_cnt[burst_len-2:0], wdata_ext_fifo_item_cnt[burst_len-1]};
            end
            
            // д���ݹ���fifo��MEM����ַ
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_raddr_regs <= 0;
                else if((new_burst_start & is_write_burst) | (~wdata_ext_fifo_item_cnt[0]))
                    wdata_ext_fifo_mem_raddr_regs <= wdata_ext_fifo_mem_raddr_regs + 1;
            end
        end
        else // burst_len == -1, ȫҳͻ��
        begin
            reg[7:0] burst_len_latched; // �����(ͻ������ - 1)
            reg wt_burst_transmitting; // ���ڽ���дͻ��(��־)
            reg[7:0] wdata_ext_fifo_item_cnt; // д���ݹ���fifo����Ƭ��������
            
            assign wdata_ext_fifo_ren = wt_burst_transmitting ? 
                (wdata_ext_fifo_item_cnt == burst_len_latched):
                (new_burst_start & is_write_burst & (new_burst_len == 8'd0));
            assign wdata_ext_fifo_ld_data = (new_burst_start & is_write_burst) | wt_burst_transmitting;
            assign wdata_cmd_vld_p2 = (new_burst_start & is_write_burst) | wt_burst_transmitting;
            
            // �����(ͻ������ - 1)
            always @(posedge clk)
            begin
                if(new_burst_start & is_write_burst)
                    burst_len_latched <= new_burst_len;
            end
            
            // ���ڽ���дͻ��(��־)
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wt_burst_transmitting <= 1'b0;
                else
                    wt_burst_transmitting <= wt_burst_transmitting ? (wdata_ext_fifo_item_cnt != burst_len_latched):(new_burst_start & is_write_burst & (new_burst_len != 8'd0));
            end
            
            // д���ݹ���fifo����Ƭ��������
            always @(posedge clk)
            begin
                if(new_burst_start & is_write_burst)
                    wdata_ext_fifo_item_cnt <= 8'd1; // дͻ����ʼʱ����ȡ��1������, �������Ƭ����������ʼʱӦ����1
                else if(wt_burst_transmitting)
                    wdata_ext_fifo_item_cnt <= wdata_ext_fifo_item_cnt + 8'd1;
            end
            
            // д���ݹ���fifo��MEM����ַ
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_raddr_regs[clogb2(rw_data_buffer_depth-1):8] <= 0;
                else if(wdata_ext_fifo_ren)
                    wdata_ext_fifo_mem_raddr_regs[clogb2(rw_data_buffer_depth-1):8] <= wdata_ext_fifo_mem_raddr_regs[clogb2(rw_data_buffer_depth-1):8] + 1;
            end
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    wdata_ext_fifo_mem_raddr_regs[7:0] <= 8'd0;
                else if(wdata_ext_fifo_ren)
                    wdata_ext_fifo_mem_raddr_regs[7:0] <= 8'd0;
                else if(wt_burst_transmitting | (new_burst_start & is_write_burst))
                    wdata_ext_fifo_mem_raddr_regs[7:0] <= wdata_ext_fifo_mem_raddr_regs[7:0] + 8'd1;
            end
        end
    endgenerate
    
    /** �����ݹ���fifo **/
    reg[clogb2(rw_data_buffer_depth-1):0] rdata_ext_fifo_mem_waddr_regs; // �����ݹ���fifo��MEMд��ַ
    wire rdata_ext_fifo_st_data; // ������ݹ���fifo��������(ָʾ)
    
    assign rdata_ext_fifo_mem_waddr = rdata_ext_fifo_mem_waddr_regs;
    assign rdata_ext_fifo_mem_din = {rdata_ext_fifo_wen, sdram_dq_i};
    
    generate
        if(burst_len == 1)
        begin
            assign rdata_ext_fifo_wen = rdata_ext_fifo_mem_wen;
            assign rdata_ext_fifo_st_data = rdata_ext_fifo_mem_wen;
            assign rdata_cmd_vld_p2 = new_burst_start & (~is_write_burst);
            
            // �����ݹ���fifo��MEMдʹ��
            ram_based_shift_regs #(
                .data_width(1),
                .delay_n(sdram_burst_rd_latency),
                .shift_type("ff"),
                .ram_type(),
                .INIT_FILE(),
                .en_output_register_init("true"),
                .output_register_init_v(1'b0),
                .simulation_delay(0)
            )delay_for_rd_burst_start(
                .clk(clk),
                .resetn(rst_n),
                .shift_in(new_burst_start & (~is_write_burst)),
                .ce(1'b1),
                .shift_out(rdata_ext_fifo_mem_wen)
            );
            
            // �����ݹ���fifo��MEMд��ַ
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_waddr_regs <= 0;
                else if(rdata_ext_fifo_mem_wen)
                    rdata_ext_fifo_mem_waddr_regs <= rdata_ext_fifo_mem_waddr_regs + 1;
            end
        end
        else if((burst_len == 2) | (burst_len == 4) | (burst_len == 8))
        begin
            reg[burst_len-1:0] rdata_ext_fifo_item_cnt; // �����ݹ���fifo����Ƭд������
            
            assign rdata_ext_fifo_st_data = rdata_ext_fifo_mem_wen;
            assign rdata_cmd_vld_p2 = (new_burst_start & (~is_write_burst)) | (~rdata_ext_fifo_item_cnt[0]);
            
            // �����ݹ���fifo����Ƭд������
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_item_cnt <= {{(burst_len-1){1'b0}}, 1'b1};
                else if((new_burst_start & (~is_write_burst)) | (~rdata_ext_fifo_item_cnt[0]))
                    rdata_ext_fifo_item_cnt <= {rdata_ext_fifo_item_cnt[burst_len-2:0], rdata_ext_fifo_item_cnt[burst_len-1]};
            end
            
            // �����ݹ���fifo��MEMд��ַ
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_waddr_regs <= 0;
                else if(rdata_ext_fifo_mem_wen)
                    rdata_ext_fifo_mem_waddr_regs <= rdata_ext_fifo_mem_waddr_regs + 1;
            end
            
            // �����ݹ���fifoдʹ��
            ram_based_shift_regs #(
                .data_width(1),
                .delay_n(sdram_burst_rd_latency),
                .shift_type("ff"),
                .ram_type(),
                .INIT_FILE(),
                .en_output_register_init("true"),
                .output_register_init_v(1'b0),
                .simulation_delay(0)
            )delay_for_last_trans_at_burst(
                .clk(clk),
                .resetn(rst_n),
                .shift_in(rdata_ext_fifo_item_cnt[burst_len-1]),
                .ce(1'b1),
                .shift_out(rdata_ext_fifo_wen)
            );
            // �����ݹ���fifo��MEMдʹ��
            ram_based_shift_regs #(
                .data_width(1),
                .delay_n(sdram_burst_rd_latency),
                .shift_type("ff"),
                .ram_type(),
                .INIT_FILE(),
                .en_output_register_init("true"),
                .output_register_init_v(1'b0),
                .simulation_delay(0)
            )delay_for_rd_burst_transmitting(
                .clk(clk),
                .resetn(rst_n),
                .shift_in((new_burst_start & (~is_write_burst)) | (~rdata_ext_fifo_item_cnt[0])),
                .ce(1'b1),
                .shift_out(rdata_ext_fifo_mem_wen)
            );
        end
        else // burst_len == -1, ȫҳͻ��
        begin
            reg[7:0] burst_len_latched; // �����(ͻ������ - 1)
            reg rd_burst_transmitting; // ��ͻ��������(��־)
            reg[7:0] rdata_ext_fifo_item_cnt; // �����ݹ���fifo����Ƭд������
            
            assign rdata_ext_fifo_st_data = rdata_ext_fifo_wen | rdata_ext_fifo_mem_wen;
            assign rdata_cmd_vld_p2 = (new_burst_start & (~is_write_burst)) | rd_burst_transmitting;
            
            // �����(ͻ������ - 1)
            always @(posedge clk)
            begin
                if(new_burst_start & (~is_write_burst))
                    burst_len_latched <= new_burst_len;
            end
            
            // ��ͻ��������(��־)
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rd_burst_transmitting <= 1'b0;
                else
                    rd_burst_transmitting <= rd_burst_transmitting ? (rdata_ext_fifo_item_cnt != burst_len_latched):(new_burst_start & (~is_write_burst) & (new_burst_len != 8'd0));
            end
            
            // �����ݹ���fifo����Ƭд������
            always @(posedge clk)
            begin
                if(new_burst_start & (~is_write_burst))
                    rdata_ext_fifo_item_cnt <= 8'd1; // ��ͻ����ʼʱ����Ԥ��1������, �������Ƭд��������ʼʱӦ����1
                else if(rd_burst_transmitting)
                    rdata_ext_fifo_item_cnt <= rdata_ext_fifo_item_cnt + 8'd1;
            end
            
            // �����ݹ���fifo��MEMд��ַ
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_waddr_regs[clogb2(rw_data_buffer_depth-1):8] <= 0;
                else if(rdata_ext_fifo_wen)
                    rdata_ext_fifo_mem_waddr_regs[clogb2(rw_data_buffer_depth-1):8] <= rdata_ext_fifo_mem_waddr_regs[clogb2(rw_data_buffer_depth-1):8] + 1;
            end
            always @(posedge clk or negedge rst_n)
            begin
                if(~rst_n)
                    rdata_ext_fifo_mem_waddr_regs[7:0] <= 8'd0;
                else if(rdata_ext_fifo_wen)
                    rdata_ext_fifo_mem_waddr_regs[7:0] <= 8'd0;
                else if(rdata_ext_fifo_mem_wen)
                    rdata_ext_fifo_mem_waddr_regs[7:0] <= rdata_ext_fifo_mem_waddr_regs[7:0] + 8'd1;
            end
            
            // �����ݹ���fifoдʹ��
            ram_based_shift_regs #(
                .data_width(1),
                .delay_n(sdram_burst_rd_latency),
                .shift_type("ff"),
                .ram_type(),
                .INIT_FILE(),
                .en_output_register_init("true"),
                .output_register_init_v(1'b0),
                .simulation_delay(0)
            )delay_for_last_trans_at_burst(
                .clk(clk),
                .resetn(rst_n),
                .shift_in(rd_burst_transmitting ? 
                    (rdata_ext_fifo_item_cnt == burst_len_latched):
                    (new_burst_start & (~is_write_burst) & (new_burst_len == 8'd0))),
                .ce(1'b1),
                .shift_out(rdata_ext_fifo_wen)
            );
            // �����ݹ���fifo��MEMдʹ��
            ram_based_shift_regs #(
                .data_width(1),
                .delay_n(sdram_burst_rd_latency),
                .shift_type("ff"),
                .ram_type(),
                .INIT_FILE(),
                .en_output_register_init("true"),
                .output_register_init_v(1'b0),
                .simulation_delay(0)
            )delay_for_rd_burst_transmitting(
                .clk(clk),
                .resetn(rst_n),
                .shift_in((new_burst_start & (~is_write_burst)) | rd_burst_transmitting),
                .ce(1'b1),
                .shift_out(rdata_ext_fifo_mem_wen)
            );
        end
    endgenerate
    
    // �쳣ָʾ
    reg ld_when_wdata_ext_fifo_empty_err_reg; // ��д���ݹ���fifo��ʱȡ����(�쳣ָʾ)
    reg st_when_rdata_ext_fifo_full_err_reg; // �ڶ����ݹ���fifo��ʱ������(�쳣ָʾ)
    
    assign ld_when_wdata_ext_fifo_empty_err = (en_expt_tip == "true") ? ld_when_wdata_ext_fifo_empty_err_reg:1'b0;
    assign st_when_rdata_ext_fifo_full_err = (en_expt_tip == "true") ? st_when_rdata_ext_fifo_full_err_reg:1'b0;
    
    // ��д���ݹ���fifo��ʱȡ����(�쳣ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            ld_when_wdata_ext_fifo_empty_err_reg <= 1'b0;
        else
            ld_when_wdata_ext_fifo_empty_err_reg <= wdata_ext_fifo_ld_data & (~wdata_ext_fifo_empty_n);
    end
    // �ڶ����ݹ���fifo��ʱ������(�쳣ָʾ)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            st_when_rdata_ext_fifo_full_err_reg <= 1'b0;
        else
            st_when_rdata_ext_fifo_full_err_reg <= rdata_ext_fifo_st_data & (~rdata_ext_fifo_full_n);
    end
    
endmodule
