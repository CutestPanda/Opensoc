`timescale 1ns / 1ps
/********************************************************************
��ģ��: AXISλ������

����: 
��axis�ӻ�������λ����������
��ѡ���������
��������ϵ��ѡ��mux����load/shiftģʽ

ע�⣺
��

Э��:
AXIS MASTER/SLAVE

����: �¼�ҫ
����: 2023/11/02
********************************************************************/


module axis_dw_cvt_downsizer #(
    parameter integer slave_data_width = 32, // �ӻ�����λ��(�����ܱ�8����, ��Ϊ��������λ��������)
    parameter integer slave_user_width_foreach_byte = 1, // �ӻ�ÿ�������ֽڵ�userλ��(����>=1, ����ʱ���ռ���)
    parameter integer master_data_width = 8, // ��������λ��(�����ܱ�8����)
    parameter en_keep = "true", // �Ƿ�ʹ��keep�ź�
    parameter en_out_isolation = "true", // �Ƿ������������
    parameter real simulation_delay = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // AXIS SLAVE
    input wire[slave_data_width-1:0] s_axis_data,
    input wire[slave_data_width/8-1:0] s_axis_keep,
    input wire[slave_data_width/8*slave_user_width_foreach_byte-1:0] s_axis_user,
    input wire s_axis_last,
    input wire s_axis_valid,
    output wire s_axis_ready,
    
    // AXIS MASTER
    output wire[master_data_width-1:0] m_axis_data,
    output wire[master_data_width/8-1:0] m_axis_keep,
    output wire[master_data_width/8*slave_user_width_foreach_byte-1:0] m_axis_user,
    output wire m_axis_last,
    output wire m_axis_valid,
    input wire m_axis_ready
);

    // ����bit_depth�������Чλ���(��λ��-1)             
    function integer clogb2 (input integer bit_depth);              
    begin                                                           
        for(clogb2=-1; bit_depth>0; clogb2=clogb2+1)                   
          bit_depth = bit_depth >> 1;                                 
    end                                        
    endfunction
    
    /** ���� **/
    localparam integer downsize_scale = slave_data_width/master_data_width; // λ����ϵ��
    localparam integer use_shift_load_th = 4; // ʹ�ü�����λģʽʱ��λ����ϵ����ֵ(>thʱʹ��)
    
    /** ������� **/
    wire[master_data_width-1:0] out_axis_data;
    wire[master_data_width/8-1:0] out_axis_keep;
    wire[master_data_width/8*slave_user_width_foreach_byte-1:0] out_axis_user;
    wire out_axis_last;
    wire out_axis_valid;
    wire out_axis_ready;
    
    generate
        if(en_out_isolation == "true")
        begin
            axis_reg_slice #(
                .data_width(master_data_width),
                .user_width(master_data_width/8*slave_user_width_foreach_byte),
                .en_ready("true"),
                .forward_registered("true"),
                .back_registered("true"),
                .simulation_delay(simulation_delay)
            )out_reg_slice(
                .clk(clk),
                .rst_n(rst_n),
                .s_axis_data(out_axis_data),
                .s_axis_keep(out_axis_keep),
                .s_axis_user(out_axis_user),
                .s_axis_last(out_axis_last),
                .s_axis_valid(out_axis_valid),
                .s_axis_ready(out_axis_ready),
                .m_axis_data(m_axis_data),
                .m_axis_keep(m_axis_keep),
                .m_axis_user(m_axis_user),
                .m_axis_last(m_axis_last),
                .m_axis_valid(m_axis_valid),
                .m_axis_ready(m_axis_ready)
            );
        end
        else
        begin
            assign m_axis_data = out_axis_data;
            assign m_axis_keep = out_axis_keep;
            assign m_axis_user = out_axis_user;
            assign m_axis_last = out_axis_last;
            assign m_axis_valid = out_axis_valid;
            assign out_axis_ready = m_axis_ready;
        end
    endgenerate

    /** λ���� **/
    wire downsize_last_flag; // ��ǰ�����ִν���(��־)
    reg[clogb2(downsize_scale-1):0] downsize_cnt; // ����������
    reg[downsize_scale-1:0] downsize_onehot; // ������һ�������
    reg[master_data_width-1:0] data_load_shift_buf[downsize_scale-1:1]; // data����/��λ������
    reg[master_data_width/8-1:0] keep_load_shift_buf[downsize_scale-1:1]; // keep����/��λ������
    reg[master_data_width/8*slave_user_width_foreach_byte-1:0] user_load_shift_buf[downsize_scale-1:1]; // user����/��λ������
    wire downsize_upd; // �����������ʹ��
    
    assign downsize_upd = (en_keep == "false") ? (out_axis_valid & out_axis_ready):((~(|s_axis_keep)) | (out_axis_valid & out_axis_ready));
    
    genvar keep_load_shift_buf_i;
    generate
        if(en_keep == "false")
            assign downsize_last_flag = downsize_onehot[downsize_scale-1];
        else
        begin
            wire[(master_data_width/8)*(downsize_scale-1)-1:0] keep_load_shift_buf_w;
            
            assign downsize_last_flag = downsize_onehot[downsize_scale-1] | (~(|keep_load_shift_buf_w));
            
            for(keep_load_shift_buf_i = 1;keep_load_shift_buf_i < downsize_scale;keep_load_shift_buf_i = keep_load_shift_buf_i + 1)
            begin
                assign keep_load_shift_buf_w[(master_data_width/8)*(keep_load_shift_buf_i-1)+(master_data_width/8)-1:(master_data_width/8)*(keep_load_shift_buf_i-1)] =
                    downsize_onehot[0] ? s_axis_keep[(master_data_width/8)*keep_load_shift_buf_i+(master_data_width/8)-1:
                    (master_data_width/8)*keep_load_shift_buf_i]:((keep_load_shift_buf_i == downsize_scale-1) ? 0:keep_load_shift_buf[keep_load_shift_buf_i+1]);
            end
        end
    endgenerate
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            downsize_cnt <= 0;
        else if(downsize_upd)
            # simulation_delay downsize_cnt <= downsize_last_flag ? 0:(downsize_cnt+1);
    end
    
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            downsize_onehot <= 1;
        else if(downsize_upd)
            # simulation_delay downsize_onehot <= downsize_last_flag ? 1:{downsize_onehot[downsize_scale-2:0], downsize_onehot[downsize_scale-1]};
    end
    
    always @(posedge clk)
    begin
        if(downsize_upd)
        begin
            if(downsize_onehot[0])
                # simulation_delay keep_load_shift_buf[downsize_scale-1] <= s_axis_keep[slave_data_width/8-1:slave_data_width/8-master_data_width/8];
            else
                # simulation_delay keep_load_shift_buf[downsize_scale-1] <= 0;
        end
    end
    
    always @(posedge clk)
    begin
        if(downsize_upd & downsize_onehot[0])
        begin
            # simulation_delay;
            
            data_load_shift_buf[downsize_scale-1] <= s_axis_data[slave_data_width-1:slave_data_width-master_data_width];
            user_load_shift_buf[downsize_scale-1] <= s_axis_user[slave_data_width/8*slave_user_width_foreach_byte-1:
                slave_data_width/8*slave_user_width_foreach_byte-master_data_width/8*slave_user_width_foreach_byte];
        end
    end
    
    genvar load_shift_buf_i;
    generate
        for(load_shift_buf_i = 1;load_shift_buf_i < downsize_scale-1;load_shift_buf_i = load_shift_buf_i + 1)
        begin
            always @(posedge clk)
            begin
                if(downsize_upd)
                begin
                    if(downsize_onehot[0])
                    begin
                        # simulation_delay;
                        // ����
                        data_load_shift_buf[load_shift_buf_i] <= s_axis_data[master_data_width*load_shift_buf_i+master_data_width-1:master_data_width*load_shift_buf_i];
                        keep_load_shift_buf[load_shift_buf_i] <= s_axis_keep[(master_data_width/8)*load_shift_buf_i+(master_data_width/8)-1:(master_data_width/8)*load_shift_buf_i];
                        user_load_shift_buf[load_shift_buf_i] <= 
                            s_axis_user[(master_data_width/8*slave_user_width_foreach_byte)*load_shift_buf_i+(master_data_width/8*slave_user_width_foreach_byte)-1:
                            (master_data_width/8*slave_user_width_foreach_byte)*load_shift_buf_i];
                    end
                    else
                    begin
                        # simulation_delay;
                        // ��λ
                        data_load_shift_buf[load_shift_buf_i] <= data_load_shift_buf[load_shift_buf_i+1];
                        keep_load_shift_buf[load_shift_buf_i] <= keep_load_shift_buf[load_shift_buf_i+1];
                        user_load_shift_buf[load_shift_buf_i] <= user_load_shift_buf[load_shift_buf_i+1];
                    end
                end
            end
        end
    endgenerate
    
    /** λ��任��� **/
    assign s_axis_ready = out_axis_ready & downsize_last_flag;
    
    genvar s_axis_data_user_i;
    generate
        if(downsize_scale <= use_shift_load_th)
        begin
            wire[master_data_width-1:0] s_axis_data_w[downsize_scale-1:0];
            wire[master_data_width/8*slave_user_width_foreach_byte-1:0] s_axis_user_w[downsize_scale-1:0];
            
            for(s_axis_data_user_i = 0;s_axis_data_user_i < downsize_scale;s_axis_data_user_i = s_axis_data_user_i + 1)
            begin
                assign s_axis_data_w[s_axis_data_user_i] = s_axis_data[s_axis_data_user_i*master_data_width+master_data_width-1:s_axis_data_user_i*master_data_width];
                assign s_axis_user_w[s_axis_data_user_i] = s_axis_user
                    [(master_data_width/8*slave_user_width_foreach_byte)*s_axis_data_user_i+(master_data_width/8*slave_user_width_foreach_byte)-1:
                    (master_data_width/8*slave_user_width_foreach_byte)*s_axis_data_user_i];
            end
            
            assign out_axis_data = s_axis_data_w[downsize_cnt];
            assign out_axis_user = s_axis_user_w[downsize_cnt];
        end
        else
        begin
            assign out_axis_data = downsize_onehot[0] ? s_axis_data[master_data_width-1:0]:data_load_shift_buf[1];
            assign out_axis_user = downsize_onehot[0] ? s_axis_user[master_data_width/8*slave_user_width_foreach_byte-1:0]:user_load_shift_buf[1];
        end
    endgenerate
    
    assign out_axis_keep = downsize_onehot[0] ? s_axis_keep[master_data_width/8-1:0]:keep_load_shift_buf[1];
    assign out_axis_last = s_axis_last & downsize_last_flag;
    assign out_axis_valid = (en_keep == "false") ? ((~downsize_onehot[0]) | s_axis_valid):(((~downsize_onehot[0]) | s_axis_valid) & (|s_axis_keep));

endmodule
