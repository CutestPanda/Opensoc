`timescale 1ns / 1ps
/********************************************************************
本模块: FSMC控制器

描述:
通用FSMC控制器

每次FSMC传输: 地址建立 -> 数据建立 -> 数据保持

注意：
无

协议:
AP CTRL
AXIS MASTER
FSMC MASTER

作者: 陈家耀
日期: 2024/07/18
********************************************************************/


module fsmc_ctrler #(
	parameter real simulation_delay = 0 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 流程控制
	input wire ctrler_start,
	output wire ctrler_idle,
	output wire ctrler_done,
	
	// 运行时参数
	// 断言:运行时参数在控制器开始工作后保持有效值不变!
	input wire[7:0] addr_set, // 地址建立周期数 - 1
	input wire[7:0] data_set, // 数据建立周期数 - 1
	input wire[7:0] data_hold, // 数据保持周期数 - 1
	
	// 传输参数
	input wire[15:0] wdata, // 写数据
	input wire[1:0] data_mask, // 字节使能掩码
	input wire[25:0] trans_addr, // 传输地址
	input wire is_rd, // 是否读传输
	
	// 读数据输出
	output wire[15:0] m_axis_rd_data,
	output wire m_axis_rd_valid,
	
	// FSMC MASTER
	output wire[1:0] fsmc_nbl, // 数据掩码
	output wire[25:0] fsmc_addr, // 地址线
	output wire fsmc_nwe, // 写入使能
	output wire fsmc_noe, // 输出使能(读使能)
	output wire fsmc_ne, // 片选信号
	// 数据线(1'b1 -> 输入, 1'b0 -> 输出)
	input wire[15:0] fsmc_data_i,
	output wire[15:0] fsmc_data_o,
	output wire[15:0] fsmc_data_t
);
	
	/** 锁存的传输信息 **/
	reg[15:0] wdata_latched; // 锁存的写数据
	reg[1:0] data_mask_latched; // 锁存的字节使能掩码
	reg[25:0] trans_addr_latched; // 锁存的传输地址
	reg is_rd_latched; // 锁存的是否读传输
	
	// 锁存的写数据
	always @(posedge clk)
	begin
		if(ctrler_start & ctrler_idle)
			# simulation_delay wdata_latched <= wdata;
	end
	// 锁存的字节使能掩码
	always @(posedge clk)
	begin
		if(ctrler_start & ctrler_idle)
			# simulation_delay data_mask_latched <= data_mask;
	end
	// 锁存的传输地址
	always @(posedge clk)
	begin
		if(ctrler_start & ctrler_idle)
			# simulation_delay trans_addr_latched <= trans_addr;
	end
	// 锁存的是否读传输
	always @(posedge clk)
	begin
		if(ctrler_start & ctrler_idle)
			# simulation_delay is_rd_latched <= is_rd;
	end
	
	/**
	流程控制
	
	空闲 -> 地址建立 -> 数据建立 -> 数据保持
	**/
	reg[3:0] proc_onehot; // 流程独热码
	reg[7:0] setup_cnt; // 地址/数据建立计数器
	reg[7:0] hold_cnt; // 数据保持计数器
	wire addr_set_done; // 地址建立完成指示
	wire data_set_done; // 数据建立完成指示
	wire data_hold_done; // 数据保持完成指示
	
	assign ctrler_idle = proc_onehot[0];
	assign ctrler_done = data_hold_done;
	
	assign addr_set_done = proc_onehot[1] & (setup_cnt == addr_set);
	assign data_set_done = proc_onehot[2] & (setup_cnt == data_set);
	assign data_hold_done = proc_onehot[3] & (hold_cnt == data_hold);
	
	// 流程独热码
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			proc_onehot <= 4'b0001;
		else if((proc_onehot[0] & ctrler_start) | 
			(proc_onehot[1] & (setup_cnt == addr_set)) | 
			(proc_onehot[2] & (setup_cnt == data_set)) | 
			(proc_onehot[3] & (hold_cnt == data_hold)))
			# simulation_delay proc_onehot <= {proc_onehot[2:0], proc_onehot[3]};
	end
	
	// 地址/数据建立计数器
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			setup_cnt <= 8'd0;
		else if(proc_onehot[1] | proc_onehot[2])
			# simulation_delay setup_cnt <= (setup_cnt == (proc_onehot[1] ? addr_set:data_set)) ? 
				8'd0:(setup_cnt + 8'd1);
	end
	
	// 数据保持计数器
	always @(posedge clk)
	begin
		if(proc_onehot[3])
			# simulation_delay hold_cnt <= hold_cnt + 8'd1;
		else
			# simulation_delay hold_cnt <= 8'd0;
	end
	
	/** FSMC主接口 **/
	reg fsmc_nwe_reg; // 写入使能
	reg fsmc_noe_reg; // 输出使能(读使能)
	reg fsmc_data_t_reg; // 数据三态方向选择
	
	assign fsmc_nbl = data_mask_latched;
	assign fsmc_addr = trans_addr_latched;
	assign fsmc_nwe = fsmc_nwe_reg;
	assign fsmc_noe = fsmc_noe_reg;
	assign fsmc_ne = ctrler_idle;
	assign fsmc_data_o = wdata_latched;
	assign fsmc_data_t = {16{fsmc_data_t_reg}};
	
	// 写入使能
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fsmc_nwe_reg <= 1'b1;
		else if((~is_rd_latched) & (addr_set_done | data_set_done))
			# simulation_delay fsmc_nwe_reg <= data_set_done;
	end
	// 输出使能(读使能)
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fsmc_noe_reg <= 1'b1;
		else if(is_rd_latched & (addr_set_done | data_hold_done))
			# simulation_delay fsmc_noe_reg <= data_hold_done;
	end
	// 数据三态方向选择
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			fsmc_data_t_reg <= 1'b1;
		else if(((~is_rd_latched) & addr_set_done) | data_hold_done)
			# simulation_delay fsmc_data_t_reg <= data_hold_done;
	end
	
	/** 读数据输出 **/
	assign m_axis_rd_data = fsmc_data_i;
	assign m_axis_rd_valid = is_rd_latched & proc_onehot[3] & (hold_cnt == 8'd0);
	
endmodule
