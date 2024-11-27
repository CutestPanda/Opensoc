`timescale 1ns / 1ps
/********************************************************************
本模块: AXIS非整数倍位宽变换器

描述: 
将axis从机的数据位宽变换非整数倍
基于寄存器片
可选的输出隔离

注意：
无

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2024/02/21
********************************************************************/


module axis_dw_cvt_not_tpc #(
    parameter integer slave_data_width = 64, // 从机数据位宽(必须能被8整除)
    parameter integer master_data_width = 48, // 主机数据位宽(必须能被8整除)
    parameter integer slave_user_width_foreach_byte = 1, // 从机每个数据字节的user位宽(必须>=1, 不用时悬空即可)
    parameter en_out_isolation = "true", // 是否启用输出隔离
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
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
    
    // 计算log2(bit_depth)
    function integer clogb2(input integer bit_depth);
        integer temp;
    begin
        temp = bit_depth;
        for(clogb2 = -1;temp > 0;clogb2 = clogb2 + 1)
            temp = temp >> 1;
    end
    endfunction

    // 计算两数的最大公约数
    function integer gcd(input integer a, input integer b);
        integer div_a;
        integer mod;
    begin
        gcd = b;
        div_a = a;
        
        while((div_a % gcd) != 0)
        begin
            mod = div_a % gcd;
            div_a = gcd;
            gcd = mod;
        end
    end
    endfunction
    
    /** 常量 **/
    localparam integer data_width_gcd = (slave_data_width > master_data_width) ?
        gcd(slave_data_width, master_data_width):
        gcd(master_data_width, slave_data_width); // 主从机数据位宽的最小公约数
    localparam integer data_width_lcm = slave_data_width * master_data_width / data_width_gcd; // 主从机数据位宽的最大公倍数
    localparam integer buf_len_div_s_data_width = data_width_lcm / slave_data_width; // 缓冲区长度 / 从机数据位宽
    localparam integer buf_len_div_m_data_width = data_width_lcm / master_data_width; // 缓冲区长度 / 主机数据位宽
    localparam integer dw_cvt_buf_width = 8 + 1 + slave_user_width_foreach_byte + 1;
    localparam integer dw_cvt_buf_for_rd_width = master_data_width + master_data_width / 8 + master_data_width / 8 * slave_user_width_foreach_byte + 1;
    localparam integer max_dw_cvt_buf_n = data_width_lcm/data_width_gcd; // 位宽变换缓冲区最大存储个数
    localparam integer wt_add_n = slave_data_width / data_width_gcd; // 写缓冲区时增加的存储个数
    localparam integer rd_sub_n = master_data_width / data_width_gcd; // 读缓冲区时减少的存储个数
    
    /** 输入端 **/
    wire[7:0] s_axis_data_w[slave_data_width/8-1:0];
    wire[slave_user_width_foreach_byte-1:0] s_axis_user_w[slave_data_width/8-1:0];
    
    genvar s_axis_data_w_i;
    generate
        for(s_axis_data_w_i = 0;s_axis_data_w_i < slave_data_width/8;s_axis_data_w_i = s_axis_data_w_i + 1)
        begin
            assign s_axis_data_w[s_axis_data_w_i] = s_axis_data[s_axis_data_w_i*8+7:s_axis_data_w_i*8];
            assign s_axis_user_w[s_axis_data_w_i] = s_axis_user[s_axis_data_w_i*slave_user_width_foreach_byte+slave_user_width_foreach_byte-1:
                s_axis_data_w_i*slave_user_width_foreach_byte];
        end
    endgenerate
    
    /** 输出寄存器片 **/
    wire[master_data_width-1:0] m_axis_data_w;
    wire[master_data_width/8-1:0] m_axis_keep_w;
    wire[master_data_width/8*slave_user_width_foreach_byte-1:0] m_axis_user_w;
    wire m_axis_last_w;
    wire m_axis_valid_w;
    wire m_axis_ready_w;
    
    generate
        if(en_out_isolation == "true")
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
                .s_axis_data(m_axis_data_w),
                .s_axis_keep(m_axis_keep_w),
                .s_axis_user(m_axis_user_w),
                .s_axis_last(m_axis_last_w),
                .s_axis_valid(m_axis_valid_w),
                .s_axis_ready(m_axis_ready_w),
                .m_axis_data(m_axis_data),
                .m_axis_keep(m_axis_keep),
                .m_axis_user(m_axis_user),
                .m_axis_last(m_axis_last),
                .m_axis_valid(m_axis_valid),
                .m_axis_ready(m_axis_ready)
            );
        else
        begin
            assign m_axis_data = m_axis_data_w;
            assign m_axis_keep = m_axis_keep_w;
            assign m_axis_user = m_axis_user_w;
            assign m_axis_last = m_axis_last_w;
            assign m_axis_valid = m_axis_valid_w;
            assign m_axis_ready_w = m_axis_ready;
        end
    endgenerate
    
     /** 位宽变换 **/
    reg s_axis_ready_reg; // 输入axis的ready
    reg m_axis_valid_w_reg; // 输出axis的valid
    // 位宽变换(缓冲区) 每字节 -> {last, user, keep, data}
    reg[dw_cvt_buf_width-1:0] dw_cvt_buf[data_width_lcm/8-1:0];
    // 存储计数
    reg[clogb2(max_dw_cvt_buf_n-1):0] dw_cvt_buf_n; // 位宽变换缓冲区存储个数
    // 写端口
    wire dw_cvt_wen; // 写使能
    reg[buf_len_div_s_data_width-1:0] dw_cvt_buf_ce; // 区域写使能
    // 读端口
    // 位宽变换(读组合) {last, user, keep, data}
    wire[dw_cvt_buf_for_rd_width-1:0] dw_cvt_buf_for_rd[buf_len_div_m_data_width-1:0];
    wire dw_cvt_ren; // 读使能
    reg[clogb2(buf_len_div_m_data_width-1):0] dw_cvt_rptr; // 读指针
    
    assign s_axis_ready = s_axis_ready_reg;
    assign m_axis_data_w = dw_cvt_buf_for_rd[dw_cvt_rptr][master_data_width-1:0];
    assign m_axis_keep_w = dw_cvt_buf_for_rd[dw_cvt_rptr][master_data_width+master_data_width/8-1:master_data_width];
    assign m_axis_user_w = dw_cvt_buf_for_rd[dw_cvt_rptr][master_data_width+master_data_width/8+master_data_width/8*slave_user_width_foreach_byte-1:
        master_data_width+master_data_width/8];
    assign m_axis_last_w = dw_cvt_buf_for_rd[dw_cvt_rptr][master_data_width+master_data_width/8+master_data_width/8*slave_user_width_foreach_byte];
    assign m_axis_valid_w = m_axis_valid_w_reg;
    
    assign dw_cvt_wen = s_axis_valid & s_axis_ready;
    assign dw_cvt_ren = m_axis_valid_w & m_axis_ready_w;
    
    genvar dw_cvt_buf_for_rd_i;
    genvar master_byte_i;
    generate
        for(dw_cvt_buf_for_rd_i = 0;dw_cvt_buf_for_rd_i < buf_len_div_m_data_width;dw_cvt_buf_for_rd_i = dw_cvt_buf_for_rd_i + 1)
        begin
            for(master_byte_i = 0;master_byte_i < master_data_width/8;master_byte_i = master_byte_i + 1)
            begin
                // data
                assign dw_cvt_buf_for_rd[dw_cvt_buf_for_rd_i][master_byte_i*8+7:master_byte_i*8] =
                    dw_cvt_buf[dw_cvt_buf_for_rd_i*master_data_width/8 + master_byte_i][7:0];
                // keep
                assign dw_cvt_buf_for_rd[dw_cvt_buf_for_rd_i][master_data_width + master_byte_i] =
                    dw_cvt_buf[dw_cvt_buf_for_rd_i*master_data_width/8 + master_byte_i][8];
                // user
                assign dw_cvt_buf_for_rd[dw_cvt_buf_for_rd_i][
                    master_data_width + master_data_width / 8 + master_byte_i*slave_user_width_foreach_byte + slave_user_width_foreach_byte - 1:
                    master_data_width + master_data_width / 8 + master_byte_i*slave_user_width_foreach_byte] =
                    dw_cvt_buf[dw_cvt_buf_for_rd_i*master_data_width/8 + master_byte_i][9+slave_user_width_foreach_byte-1:9];
            end
            // last
            assign dw_cvt_buf_for_rd[dw_cvt_buf_for_rd_i][master_data_width + master_data_width / 8 + master_data_width / 8 * slave_user_width_foreach_byte] =
                dw_cvt_buf[dw_cvt_buf_for_rd_i*master_data_width/8+master_data_width/8-1][9+slave_user_width_foreach_byte];
        end
    endgenerate
    
    // 输入axis的ready
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            s_axis_ready_reg <= 1'b1;
        else if(dw_cvt_wen | dw_cvt_ren)
        begin
            # simulation_delay;
            
            case({dw_cvt_wen, dw_cvt_ren})
                2'b01: s_axis_ready_reg <= dw_cvt_buf_n <= max_dw_cvt_buf_n - wt_add_n + rd_sub_n;
                2'b10: s_axis_ready_reg <= dw_cvt_buf_n <= max_dw_cvt_buf_n - wt_add_n * 2;
                2'b11: s_axis_ready_reg <= dw_cvt_buf_n <= max_dw_cvt_buf_n - wt_add_n * 2 + rd_sub_n;
                default: s_axis_ready_reg <= s_axis_ready_reg; // hold
            endcase
        end
    end
    // 输出axis的valid
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            m_axis_valid_w_reg <= 1'b0;
        else if(dw_cvt_wen | dw_cvt_ren)
        begin
            # simulation_delay;
            
            case({dw_cvt_wen, dw_cvt_ren})
                2'b01: m_axis_valid_w_reg <= dw_cvt_buf_n >= rd_sub_n * 2;
                2'b10: m_axis_valid_w_reg <= (rd_sub_n - wt_add_n <= 0) ? 1'b1:dw_cvt_buf_n >= rd_sub_n - wt_add_n;
                2'b11: m_axis_valid_w_reg <= dw_cvt_buf_n >= rd_sub_n * 2 - wt_add_n;
                default: m_axis_valid_w_reg <= m_axis_valid_w_reg; // hold
            endcase
        end
    end
    
    // 位宽变换缓冲区存储个数
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            dw_cvt_buf_n <= 4'd0;
        else if(dw_cvt_wen | dw_cvt_ren)
        begin
            # simulation_delay;
            
            case({dw_cvt_wen, dw_cvt_ren})
                2'b01: dw_cvt_buf_n <= dw_cvt_buf_n - rd_sub_n;
                2'b10: dw_cvt_buf_n <= dw_cvt_buf_n + wt_add_n;
                2'b11: dw_cvt_buf_n <= dw_cvt_buf_n + wt_add_n - rd_sub_n;
                default: dw_cvt_buf_n <= dw_cvt_buf_n; // hold
            endcase
        end
    end
    
    // 位宽变换(缓冲区)
    genvar dw_cvt_buf_i;
    generate
        for(dw_cvt_buf_i = 0;dw_cvt_buf_i < data_width_lcm/8;dw_cvt_buf_i = dw_cvt_buf_i + 1)
        begin
            integer dw_cnt_buf_region = dw_cvt_buf_i / (slave_data_width / 8); // 相对于从机的区域编号
            integer dw_cnt_buf_id_in_region = dw_cvt_buf_i % (slave_data_width / 8); // 相对于从机的区域内部编号
            
            always @(posedge clk)
            begin
                if(dw_cvt_wen & dw_cvt_buf_ce[dw_cnt_buf_region])
                    # simulation_delay dw_cvt_buf[dw_cvt_buf_i] <= {
                        (dw_cnt_buf_id_in_region == (slave_data_width / 8 - 1)) ? s_axis_last:1'b0, s_axis_user_w[dw_cnt_buf_id_in_region],
                        s_axis_keep[dw_cnt_buf_id_in_region], s_axis_data_w[dw_cnt_buf_id_in_region]};
            end
        end
    endgenerate
    
    // 区域写使能
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            dw_cvt_buf_ce <= {{(buf_len_div_s_data_width-1){1'b0}}, 1'b1};
        else if(dw_cvt_wen) // 循环左移
            # simulation_delay dw_cvt_buf_ce <= {dw_cvt_buf_ce[buf_len_div_s_data_width-2:0], dw_cvt_buf_ce[buf_len_div_s_data_width-1]};
    end
    
    // 读指针
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            dw_cvt_rptr <= 0;
        else if(dw_cvt_ren)
            # simulation_delay dw_cvt_rptr <= (dw_cvt_rptr == buf_len_div_m_data_width-1) ? 0:(dw_cvt_rptr + 1);
    end

endmodule
