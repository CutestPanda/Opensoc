`timescale 1ns / 1ps
/********************************************************************
��ģ��: sdram�Լ�

����:
ÿ��ͻ�����������Ǵ�1��ʼ����
��ͻ������Ϊȫҳʱ, ʵ��ͻ����������sdram����(SDRAM_COL_N)

ע�⣺
�е�ַ�̶�Ϊ0
����λ�����>=clogb2(SDRAM_COL_N)

Э��:
AXIS MASTER/SLAVE

����: �¼�ҫ
����: 2025/03/03
********************************************************************/


module sdram_selftest #(
    parameter integer BURST_LEN = -1, // ͻ������(-1 -> ȫҳ; 1 | 2 | 4 | 8)
    parameter integer DATA_WIDTH = 32, // ����λ��
	parameter integer SDRAM_COL_N = 256, // sdram����(64 | 128 | 256 | 512 | 1024)
	parameter integer SDRAM_ROW_N = 8192, // sdram����(1024 | 2048 | 4096 | 8192 | 16384)
	parameter real SIM_DELAY = 1 // ������ʱ
)(
    // ʱ�Ӻ͸�λ
    input wire clk,
    input wire rst_n,
    
    // ���̿���
    input wire self_test_start,
    output wire self_test_idle,
    output wire self_test_done,
    
    // �Լ���
    // {�Ƿ�ɹ�(1bit), ����bank��(2bit), �����к�(16bit)}
    output wire[18:0] self_test_res,
    output wire self_test_res_valid,
    
    // д����AXIS
    output wire[DATA_WIDTH-1:0] m_axis_wt_data,
    output wire[DATA_WIDTH/8-1:0] m_axis_wt_keep, // const -> {(DATA_WIDTH/8){1'b1}}
    output wire m_axis_wt_last,
    output wire m_axis_wt_valid,
    input wire m_axis_wt_ready,
    // ������AXIS
    input wire[DATA_WIDTH-1:0] s_axis_rd_data,
    input wire s_axis_rd_last,
    input wire s_axis_rd_valid,
    output wire s_axis_rd_ready,
    
    // �û�����AXIS
    output wire[39:0] m_axis_usr_cmd_data, // {����(3bit), ba(2bit), �е�ַ(16bit), A15-0(16bit), �����(3bit)}
    output wire[16:0] m_axis_usr_cmd_user, // {�Ƿ��Զ����"ֹͣͻ��"����(1bit), ͻ������ - 1(16bit)}(����ȫҳͻ����Ч)
    output wire m_axis_usr_cmd_valid,
    input wire m_axis_usr_cmd_ready
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
    // ������߼�����
    localparam CMD_LOGI_WT_DATA = 3'b010; // ����:д����
    localparam CMD_LOGI_RD_DATA = 3'b011; // ����:������
    localparam CMD_LOGI_BANK_PRECHARGE = 3'b001; // ����:Ԥ���bank
    
    /** �û�����AXIS **/
    reg[36:0] now_cmd; // ��ǰ����
    reg now_cmd_valid; // ��ǰ������Ч
    
    assign m_axis_usr_cmd_data = {3'dx, now_cmd};
    assign m_axis_usr_cmd_user = {
        (BURST_LEN == -1) ? 1'b1:1'bx, // �Ƿ��Զ����"ֹͣͻ��"����(1bit)
        (BURST_LEN == -1) ? (SDRAM_COL_N[15:0] - 16'd1):16'dx // ͻ������ - 1(16bit)
    };
    assign m_axis_usr_cmd_valid = now_cmd_valid;
    
    // ��ǰ����
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            now_cmd <= {2'b00, 16'd0, 16'd0, CMD_LOGI_WT_DATA}; // дbank0��0
        else if(m_axis_usr_cmd_valid & m_axis_usr_cmd_ready)
        begin
			{now_cmd[36:35], now_cmd[19+clogb2(SDRAM_ROW_N-1):19]} <= # SIM_DELAY 
				{now_cmd[36:35], now_cmd[19+clogb2(SDRAM_ROW_N-1):19]} + 1;
            
            now_cmd[18:3] <= # SIM_DELAY 16'd0; // always 16'd0
            
            now_cmd[2:1] <= # SIM_DELAY 2'b01; // always 2'b01
            now_cmd[0] <= # SIM_DELAY (&{now_cmd[36:35], now_cmd[19+clogb2(SDRAM_ROW_N-1):19]}) ? (~now_cmd[0]):now_cmd[0];
        end
    end
    // ��ǰ������Ч
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            now_cmd_valid <= 1'b0;
        else
            now_cmd_valid <= # SIM_DELAY now_cmd_valid ? 
				(~(m_axis_usr_cmd_ready & (&{now_cmd[36:35], now_cmd[19+clogb2(SDRAM_ROW_N-1):19]}) & now_cmd[0])):
				(self_test_idle & self_test_start);
    end
    
    /** д����AXIS **/
    reg[clogb2(SDRAM_ROW_N-1)+2:0] wt_burst_cnt; // дͻ������(������)
    reg[DATA_WIDTH-1:0] wt_data; // д����
    reg wt_data_valid; // д������Ч
    
    assign m_axis_wt_data = wt_data;
    assign m_axis_wt_keep = {(DATA_WIDTH/8){1'b1}};
    assign m_axis_wt_last = (BURST_LEN == -1) ? (wt_data == SDRAM_COL_N):
                             (BURST_LEN == 1) ? 1'b1:
                                                (wt_data == BURST_LEN);
    assign m_axis_wt_valid = wt_data_valid;
    
    // дͻ������(������)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_burst_cnt <= 0;
        else if(m_axis_wt_valid & m_axis_wt_ready & m_axis_wt_last)
            wt_burst_cnt <= # SIM_DELAY wt_burst_cnt + 1;
    end
    
    // д����
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_data <= 1;
        else if(m_axis_wt_valid & m_axis_wt_ready)
            wt_data <= # SIM_DELAY m_axis_wt_last ? 1:(wt_data + 1);
    end
    // д������Ч
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wt_data_valid <= 1'b0;
        else
            wt_data_valid <= # SIM_DELAY wt_data_valid ? 
				(~(m_axis_wt_ready & m_axis_wt_last & (&wt_burst_cnt))):
				(self_test_idle & self_test_start);
    end
    
    /** ������AXIS **/
    reg[clogb2(SDRAM_ROW_N-1)+2:0] rd_burst_cnt; // ��ͻ������(������)
    reg rd_ready; // ������
    
    assign s_axis_rd_ready = rd_ready;
    
    // ��ͻ������(������)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_burst_cnt <= 0;
        else if(s_axis_rd_valid & s_axis_rd_ready & s_axis_rd_last)
            rd_burst_cnt <= # SIM_DELAY rd_burst_cnt + 1;
    end
    
    // ������
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_ready <= 1'b0;
        else
            rd_ready <= # SIM_DELAY 
				rd_ready ? 
					(~(s_axis_rd_valid & s_axis_rd_last & (&rd_burst_cnt))):
					(self_test_idle & self_test_start);
    end
    
    /** �����ݼ�� **/
    reg[clogb2(SDRAM_COL_N):0] rd_data_cnt; // �����ݼ�����
    reg now_rd_data_mismatch; // ��ǰ��ͻ�����ݲ�ƥ��(��־)
    wire now_rd_burst_check_res; // ��ǰ��ͻ�������
    reg[18:0] now_self_test_res; // ��ǰ���Լ���({�Ƿ�ɹ�(1bit), ����bank��(2bit), �����к�(16bit)})
    
    assign self_test_res = now_self_test_res;
    assign self_test_res_valid = self_test_done;
    
    assign now_rd_burst_check_res = now_rd_data_mismatch | (s_axis_rd_data != rd_data_cnt) | 
        (rd_data_cnt != ((BURST_LEN == -1) ? SDRAM_COL_N:BURST_LEN));
    
    // �����ݼ�����
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rd_data_cnt <= 1;
        else if(s_axis_rd_valid & s_axis_rd_ready)
            rd_data_cnt <= # SIM_DELAY s_axis_rd_last ? 1:(rd_data_cnt + 1);
    end
    
    // ��ǰ��ͻ�����ݲ�ƥ��(��־)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            now_rd_data_mismatch <= 1'b0;
        else if(s_axis_rd_valid & s_axis_rd_ready)
            now_rd_data_mismatch <= # SIM_DELAY s_axis_rd_last ? 1'b0:(now_rd_data_mismatch | (s_axis_rd_data != rd_data_cnt));
    end
    
    // ��ǰ���Լ���({�Ƿ�ɹ�(1bit), ����bank��(2bit), �����к�(16bit)})
    always @(posedge clk)
    begin
        if(self_test_idle & self_test_start)
            now_self_test_res <= # SIM_DELAY {1'b1, 2'bxx, 16'dx};
        else if(s_axis_rd_valid & s_axis_rd_ready & s_axis_rd_last & now_self_test_res[18])
            now_self_test_res <= # SIM_DELAY {
				now_self_test_res[18] & (~now_rd_burst_check_res), 
				rd_burst_cnt[clogb2(SDRAM_ROW_N-1)+2:clogb2(SDRAM_ROW_N-1)+1], 
				16'h0000 | rd_burst_cnt[clogb2(SDRAM_ROW_N-1):0]
			};
    end
    
    /** ���̿��� **/
    reg self_test_idle_reg;
    reg self_test_done_reg;
    
    assign self_test_idle = self_test_idle_reg;
    assign self_test_done = self_test_done_reg;
    
    // �Լ쵥Ԫ���б�־
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            self_test_idle_reg <= 1'b1;
        else
            self_test_idle_reg <= # SIM_DELAY self_test_idle_reg ? (~self_test_start):self_test_done;
    end
    // �Լ쵥Ԫ���ָʾ
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            self_test_done_reg <= 1'b0;
        else
            self_test_done_reg <= # SIM_DELAY s_axis_rd_valid & s_axis_rd_ready & s_axis_rd_last & ((&rd_burst_cnt) | now_rd_burst_check_res);
    end

endmodule
