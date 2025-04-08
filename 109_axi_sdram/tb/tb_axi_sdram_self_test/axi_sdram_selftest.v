`timescale 1ns / 1ps
/********************************************************************
本模块: axi-sdram自检

描述:
写整片sdram -> 读整片sdram并检查数据

写数据从0开始递增
突发长度固定为256

注意：
无

协议:
AXI MASTER

作者: 陈家耀
日期: 2025/04/07
********************************************************************/


module axi_sdram_selftest #(
	parameter integer DATA_WIDTH = 32, // 数据位宽(8 | 16 | 32 | 64)
	parameter integer LAST_BURST_BASEADDR = 4 * (8 * 1024) * 512 * (DATA_WIDTH / 8) - 256 * (DATA_WIDTH / 8), // 最后1次突发的首地址
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 流程控制
    input wire self_test_start,
    output wire self_test_idle,
    output wire self_test_done,
	
	// 自检结果
    // {是否成功(1bit), 错误突发号(18bit)}
    output wire[18:0] self_test_res,
    output wire self_test_res_valid,
    
    // AXI主机
    // AR
    output wire[31:0] m_axi_araddr,
    output wire[7:0] m_axi_arlen, // const -> 8'd255
    output wire[2:0] m_axi_arsize, // const -> clogb2(DATA_WIDTH/8)
    output wire m_axi_arvalid,
    input wire m_axi_arready,
    // R
    input wire[DATA_WIDTH-1:0] m_axi_rdata,
    input wire m_axi_rlast,
	input wire[1:0] m_axi_rresp, // ignored
    input wire m_axi_rvalid,
    output wire m_axi_rready,
    // AW
    output wire[31:0] m_axi_awaddr,
    output wire[7:0] m_axi_awlen, // const -> 8'd255
    output wire[2:0] m_axi_awsize, // const -> clogb2(DATA_WIDTH/8)
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    // W
    output wire[DATA_WIDTH-1:0] m_axi_wdata,
    output wire[DATA_WIDTH/8-1:0] m_axi_wstrb, // const -> {(DATA_WIDTH/8){1'b1}}
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready,
    // B
    input wire[1:0] m_axi_bresp, // ignored
    input wire m_axi_bvalid,
    output wire m_axi_bready // const -> 1'b1
);
	
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
    end
    endfunction
	
    /** AXI主机AW/W通道 **/
    reg[31:0] waddr_cnt; // 写地址计数器
    reg aw_valid; // AW通道的valid信号
    reg[DATA_WIDTH-1:0] wdata_cnt; // 写数据计数器
    reg[19:0] wburst_cnt; // 写突发计数器
    reg w_valid; // W通道的valid信号
    reg w_test_done; // 写测试完成
    
    assign m_axi_awaddr = waddr_cnt;
    assign m_axi_awlen = 8'd255;
    assign m_axi_awsize = clogb2(DATA_WIDTH/8);
    assign m_axi_awvalid = aw_valid;
    
    assign m_axi_wdata = wdata_cnt;
    assign m_axi_wstrb = {(DATA_WIDTH/8){1'b1}};
    assign m_axi_wlast = wdata_cnt[7:0] == 8'hff;
    assign m_axi_wvalid = w_valid;
    
    // 写地址计数器
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            waddr_cnt <= 32'd0;
        else if(m_axi_awvalid & m_axi_awready)
            waddr_cnt <= # SIM_DELAY waddr_cnt + (32'd256 * DATA_WIDTH / 8);
    end
    // AW通道的valid信号
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            aw_valid <= 1'b0;
        else
            aw_valid <= # SIM_DELAY 
				aw_valid ? 
					(~(m_axi_awready & (waddr_cnt == LAST_BURST_BASEADDR))):
					(self_test_idle & self_test_start);
    end
    
    // 写数据计数器
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wdata_cnt <= 0;
        else if(m_axi_wvalid & m_axi_wready)
            wdata_cnt <= # SIM_DELAY wdata_cnt + 1;
    end
    // 写突发计数器
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            wburst_cnt <= 20'd0;
        else if(m_axi_wvalid & m_axi_wready & m_axi_wlast)
            wburst_cnt <= # SIM_DELAY wburst_cnt + 20'd1;
    end
    // W通道的valid信号
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            w_valid <= 1'b0;
        else
            w_valid <= # SIM_DELAY 
				w_valid ? 
					(~(
						m_axi_wready & m_axi_wlast & 
						(wburst_cnt == (LAST_BURST_BASEADDR / (256 * (DATA_WIDTH / 8))))
					)):
					(self_test_idle & self_test_start);
    end
    // 写测试完成
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            w_test_done <= 1'd0;
        else
            w_test_done <= # SIM_DELAY 
				m_axi_wvalid & m_axi_wready & m_axi_wlast & (wburst_cnt == (LAST_BURST_BASEADDR / (256 * (DATA_WIDTH / 8))));
    end
    
    /** AXI主机AR/R通道 **/
    reg[31:0] raddr_cnt; // 读地址计数器
    reg ar_valid; // AW通道的valid信号
    reg[DATA_WIDTH-1:0] rdata_cnt; // 读数据计数器
    reg[19:0] rburst_cnt; // 读突发计数器
    reg r_ready; // R通道的ready信号
    wire now_rd_burst_check_res; // 当前读突发检查结果
    
    assign m_axi_araddr = raddr_cnt;
    assign m_axi_arlen = 8'd255;
    assign m_axi_arsize = clogb2(DATA_WIDTH/8);
    assign m_axi_arvalid = ar_valid;
    
    assign m_axi_rready = r_ready;
    
    // 读地址计数器
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            raddr_cnt <= 0;
        else if(m_axi_arvalid & m_axi_arready)
            raddr_cnt <= # SIM_DELAY raddr_cnt + (32'd256 * DATA_WIDTH / 8);
    end
    // AR通道的valid信号
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            ar_valid <= 1'b0;
        else
            ar_valid <= # SIM_DELAY 
				ar_valid ? 
					(~(m_axi_arready & (raddr_cnt == LAST_BURST_BASEADDR))):
					w_test_done;
    end
    
    // 读数据计数器
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rdata_cnt <= 0;
        else if(m_axi_rvalid & m_axi_rready)
            rdata_cnt <= # SIM_DELAY rdata_cnt + 1;
    end
    // 读突发计数器
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rburst_cnt <= 20'd0;
        else if(m_axi_rvalid & m_axi_rready & m_axi_rlast)
            rburst_cnt <= # SIM_DELAY rburst_cnt + 20'd1;
    end
    // R通道的ready信号
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            r_ready <= 1'b0;
        else
            r_ready <= # SIM_DELAY 
				r_ready ? 
				(~(
					m_axi_rvalid & m_axi_rlast & 
					((rburst_cnt == (LAST_BURST_BASEADDR / (256 * (DATA_WIDTH / 8)))) | now_rd_burst_check_res)
				)):
				w_test_done;
    end
    
    /** AXI主机B通道 **/
    assign m_axi_bready = 1'b1;
    
    /** 检查读数据 **/
    reg now_rd_data_mismatch; // 当前读突发数据不匹配(标志)
    reg[18:0] now_self_test_res; // 当前的自检结果({是否成功(1bit), 错误突发号(18bit)})
    
    assign self_test_res = now_self_test_res;
    assign self_test_res_valid = self_test_done;
    
    assign now_rd_burst_check_res = now_rd_data_mismatch | (m_axi_rdata != rdata_cnt) | (rdata_cnt[7:0] != 8'hff);
    
    // 当前读突发数据不匹配(标志)
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            now_rd_data_mismatch <= 1'b0;
        else if(m_axi_rvalid & m_axi_rready)
            now_rd_data_mismatch <= # SIM_DELAY 
				m_axi_rlast ? 
					1'b0:
					(now_rd_data_mismatch | (m_axi_rdata != rdata_cnt));
    end
    
    // 当前的自检结果({是否成功(1bit), 错误突发号(18bit)})
    always @(posedge clk)
    begin
        if(self_test_idle & self_test_start)
            now_self_test_res <= # SIM_DELAY {1'b1, 18'dx};
        else if(m_axi_rvalid & m_axi_rready & m_axi_rlast & now_self_test_res[18])
            now_self_test_res <= # SIM_DELAY {now_self_test_res[18] & (~now_rd_burst_check_res), rburst_cnt[17:0]};
    end
    
    /** 流程控制 **/
    reg self_test_idle_reg;
    reg self_test_done_reg;
    
    assign self_test_idle = self_test_idle_reg;
    assign self_test_done = self_test_done_reg;
    
    // 自检单元空闲标志
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            self_test_idle_reg <= 1'b1;
        else
            self_test_idle_reg <= # SIM_DELAY self_test_idle_reg ? (~self_test_start):self_test_done;
    end
    // 自检单元完成指示
    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            self_test_done_reg <= 1'b0;
        else
            self_test_done_reg <= # SIM_DELAY 
				m_axi_rvalid & m_axi_rready & m_axi_rlast & 
				((rburst_cnt == (LAST_BURST_BASEADDR / (256 * (DATA_WIDTH / 8)))) | now_rd_burst_check_res);
    end
    
endmodule
