`timescale 1ns / 1ps
/********************************************************************
本模块: 通用卷积计算单元的寄存器配置接口

描述:
寄存器->
    偏移量  |    含义                        |   读写特性    |        备注
    0x00    0:复位线性参数缓存区                   WO        写该寄存器且该位为1'b1时执行复位
	        1:复位数据通路上的卷积核参数缓存       WO        写该寄存器且该位为1'b1时执行复位
			8:启动读请求描述子DMA                  WO        写该寄存器且该位为1'b1时执行启动
			9:启动写请求描述子DMA                  WO        写该寄存器且该位为1'b1时执行启动
			16:读请求描述子DMA空闲标志             RO
			17:写请求描述子DMA空闲标志             RO
	0x04    0:全局中断使能                         RW
			8:读请求描述子DMA请求处理完成中断使能  RW
	        9:写请求描述子DMA请求处理完成中断使能  RW
			10:写请求处理完成中断使能              RW
	0x08    0:全局中断标志                         WC
	        8:读请求描述子DMA请求处理完成中断标志  RO
			9:写请求描述子DMA请求处理完成中断标志  RO
			10:写请求处理完成中断标志              RO
	0x0C    31~0:写请求处理完成中断阈值            RW
	0x10    0:使能卷积计算                         RW
	0x14    0:卷积核类型                           RW        1'b0 -> 1x1, 1'b1 -> 3x3
	        11~8:外拓填充使能                      RW
	0x18    31~0:读请求缓存区首地址                RW
	0x1C    31~0:读请求个数 - 1                    RW
	0x20    31~0:写请求缓存区首地址                RW
	0x24    31~0:写请求个数 - 1                    RW
	0x28    15~0:输入特征图宽度 - 1                RW
	        31~16:输入特征图高度 - 1               RW
	0x2C    15~0:输入特征图通道数 - 1              RW
	        31~16:卷积核个数 - 1                   RW
	0x30    31~0:Relu激活系数c[31:0]               RW
	0x34    31~0:Relu激活系数c[63:32]              RW
	0x38    31~0:已完成的写请求个数                RW
	0x3C    15~0:输出特征图宽度 - 1                RW
	        31~16:输出特征图高度 - 1               RW
	0x40    2~0:水平步长 - 1                       RW
	        10~8:垂直步长 - 1                      RW
	        16:步长类型                            RW        1'b0 -> 从第1个ROI开始, 1'b1 -> 舍弃第1个ROI
	0x44    1~0:激活类型                           RW        2'b00 -> Relu, 2'b01 -> 保留, 2'b10 -> Sigmoid, 2'b11 -> Tanh
	0x48    10~0:非线性激活查找表写地址            WO        写该寄存器时产生查找表写使能, 写数据的量化精度应为Q15
	        31~16:非线性激活查找表写数据           WO

注意：
无

协议:
AXI-Lite SLAVE
BLK CTRL
MEM WRITE

作者: 陈家耀
日期: 2024/12/29
********************************************************************/


module reg_if_for_generic_conv #(
	parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
	
	// 寄存器配置接口(AXI-Lite从机)
    // 读地址通道
    input wire[31:0] s_axi_lite_araddr,
	input wire[2:0] s_axi_lite_arprot, // ignored
    input wire s_axi_lite_arvalid,
    output wire s_axi_lite_arready,
    // 写地址通道
    input wire[31:0] s_axi_lite_awaddr,
	input wire[2:0] s_axi_lite_awprot, // ignored
    input wire s_axi_lite_awvalid,
    output wire s_axi_lite_awready,
    // 写响应通道
    output wire[1:0] s_axi_lite_bresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_bvalid,
    input wire s_axi_lite_bready,
    // 读数据通道
    output wire[31:0] s_axi_lite_rdata,
    output wire[1:0] s_axi_lite_rresp, // const -> 2'b00(OKAY)
    output wire s_axi_lite_rvalid,
    input wire s_axi_lite_rready,
    // 写数据通道
    input wire[31:0] s_axi_lite_wdata,
	input wire[3:0] s_axi_lite_wstrb,
    input wire s_axi_lite_wvalid,
    output wire s_axi_lite_wready,
	
	// 块级控制
	// 读请求描述子DMA
	output wire rd_req_dsc_dma_blk_start,
	input wire rd_req_dsc_dma_blk_idle,
	// 写请求描述子DMA
	output wire wt_req_dsc_dma_blk_start,
	input wire wt_req_dsc_dma_blk_idle,
	
	// 使能
	output wire en_conv_cal, // 是否使能卷积计算
	
	// 复位
	output wire rst_linear_pars_buf, // 复位线性参数缓存区
	output wire rst_cal_path_kernal_buf, // 复位数据通路上的卷积核参数缓存
	
	// 中断
	output wire[31:0] wt_req_itr_th, // 写请求处理完成中断阈值
	input wire[2:0] itr_req, // 中断请求({写请求处理完成中断请求, 
	                         //     写请求描述子DMA请求处理完成中断请求, 读请求描述子DMA请求处理完成中断请求})
	output wire en_wt_req_fns_itr, // 是否使能写请求处理完成中断
	output wire itr, // 中断信号
	
	// 已完成的写请求个数
	output wire[3:0] to_set_wt_req_fns_n,
	output wire[31:0] wt_req_fns_n_set_v,
	input wire[31:0] wt_req_fns_n_cur_v,
	
	// 非线性激活查找表(写端口)
	output wire non_ln_act_lut_wen,
	output wire[10:0] non_ln_act_lut_waddr,
	output wire[15:0] non_ln_act_lut_din, // Q15
	
	// 运行时参数
	output wire[63:0] act_rate_c, // Relu激活系数c
	output wire[31:0] rd_req_buf_baseaddr, // 读请求缓存区首地址
	output wire[31:0] rd_req_n, // 读请求个数 - 1
	output wire[31:0] wt_req_buf_baseaddr, // 写请求缓存区首地址
	output wire[31:0] wt_req_n, // 写请求个数 - 1
	output wire kernal_type, // 卷积核类型(1'b0 -> 1x1, 1'b1 -> 3x3)
	output wire[15:0] feature_map_w, // 输入特征图宽度 - 1
	output wire[15:0] feature_map_h, // 输入特征图高度 - 1
	output wire[15:0] feature_map_chn_n, // 输入特征图通道数 - 1
	output wire[15:0] kernal_n, // 卷积核个数 - 1
	output wire[3:0] padding_en, // 外拓填充使能(仅当卷积核类型为3x3时可用, {上, 下, 左, 右})
	output wire[15:0] o_ft_map_w, // 输出特征图宽度 - 1
	output wire[15:0] o_ft_map_h, // 输出特征图高度 - 1
	output wire[2:0] horizontal_step, // 水平步长 - 1
	output wire[2:0] vertical_step, // 垂直步长 - 1
	output wire step_type, // 步长类型(1'b0 -> 从第1个ROI开始, 1'b1 -> 舍弃第1个ROI)
	output wire[1:0] act_type // 激活类型(2'b00 -> Relu, 2'b01 -> 保留, 2'b10 -> Sigmoid, 2'b11 -> Tanh)
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
	
	/** 内部配置 **/
	localparam integer REGS_N = 19; // 寄存器总数
	
	/** 常量 **/
	// 寄存器配置状态独热码编号
	localparam integer REG_CFG_STS_ADDR = 0; // 状态:地址阶段
	localparam integer REG_CFG_STS_RW_REG = 1; // 状态:读/写寄存器
	localparam integer REG_CFG_STS_RW_RESP = 2; // 状态:读/写响应
	
	/** 寄存器配置控制 **/
	reg[2:0] reg_cfg_sts; // 寄存器配置状态
	wire[1:0] rw_grant; // 读写许可({写许可, 读许可})
	reg[1:0] addr_ready; // 地址通道的ready信号({aw_ready, ar_ready})
	reg is_write; // 是否写寄存器
	reg[clogb2(REGS_N-1):0] ofs_addr; // 读写寄存器的偏移地址
	reg wready; // 写数据通道的ready信号
	reg bvalid; // 写响应通道的valid信号
	reg rvalid; // 读数据通道的valid信号
	wire regs_en; // 寄存器访问使能
	wire[3:0] regs_wen; // 寄存器写使能
	wire[clogb2(REGS_N-1):0] regs_addr; // 寄存器访问地址
	wire[31:0] regs_din; // 寄存器写数据
	wire[31:0] regs_dout; // 寄存器读数据
	
	assign {s_axi_lite_awready, s_axi_lite_arready} = addr_ready;
	assign s_axi_lite_bresp = 2'b00;
	assign s_axi_lite_bvalid = bvalid;
	assign s_axi_lite_rdata = regs_dout;
	assign s_axi_lite_rresp = 2'b00;
	assign s_axi_lite_rvalid = rvalid;
	assign s_axi_lite_wready = wready;
	
	assign rw_grant = {s_axi_lite_awvalid, (~s_axi_lite_awvalid) & s_axi_lite_arvalid}; // 写优先
	
	assign regs_en = reg_cfg_sts[REG_CFG_STS_RW_REG] & ((~is_write) | s_axi_lite_wvalid);
	assign regs_wen = {4{is_write}} & s_axi_lite_wstrb;
	assign regs_addr = ofs_addr;
	assign regs_din = s_axi_lite_wdata;
	
	// 寄存器配置状态
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			reg_cfg_sts <= 3'b001;
		else if((reg_cfg_sts[REG_CFG_STS_ADDR] & (s_axi_lite_awvalid | s_axi_lite_arvalid)) | 
			(reg_cfg_sts[REG_CFG_STS_RW_REG] & ((~is_write) | s_axi_lite_wvalid)) | 
			(reg_cfg_sts[REG_CFG_STS_RW_RESP] & (is_write ? s_axi_lite_bready:s_axi_lite_rready)))
			reg_cfg_sts <= # simulation_delay {reg_cfg_sts[1:0], reg_cfg_sts[2]};
	end
	
	// 地址通道的ready信号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			addr_ready <= 2'b00;
		else
			addr_ready <= # simulation_delay {2{reg_cfg_sts[REG_CFG_STS_ADDR]}} & rw_grant;
	end
	
	// 是否写寄存器
	always @(posedge clk)
	begin
		if(reg_cfg_sts[REG_CFG_STS_ADDR] & (s_axi_lite_awvalid | s_axi_lite_arvalid))
			is_write <= # simulation_delay s_axi_lite_awvalid;
	end
	
	// 读写寄存器的偏移地址
	always @(posedge clk)
	begin
		if(reg_cfg_sts[REG_CFG_STS_ADDR] & (s_axi_lite_awvalid | s_axi_lite_arvalid))
			ofs_addr <= # simulation_delay s_axi_lite_awvalid ? 
				s_axi_lite_awaddr[2+clogb2(REGS_N-1):2]:s_axi_lite_araddr[2+clogb2(REGS_N-1):2];
	end
	
	// 写数据通道的ready信号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			wready <= 1'b0;
		else
			wready <= # simulation_delay wready ? 
				(~s_axi_lite_wvalid):(reg_cfg_sts[REG_CFG_STS_ADDR] & s_axi_lite_awvalid);
	end
	
	// 写响应通道的valid信号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			bvalid <= 1'b0;
		else
			bvalid <= # simulation_delay bvalid ? 
				(~s_axi_lite_bready):(s_axi_lite_wvalid & s_axi_lite_wready);
	end
	
	// 读数据通道的valid信号
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			rvalid <= 1'b0;
		else
			rvalid <= # simulation_delay rvalid ? 
				(~s_axi_lite_rready):(reg_cfg_sts[REG_CFG_STS_RW_REG] & (~is_write));
	end
	
	/** 寄存器区 **/
	// 中断控制
	wire global_itr_req; // 全局中断请求
	// 寄存器区读数据
	wire[31:0] regs_region_rd_out_nxt;
	reg[31:0] regs_region_rd_out;
	// 0x00
	reg rst_linear_pars_buf_reg; // 复位线性参数缓存区
	reg rst_cal_path_kernal_buf_reg; // 复位数据通路上的卷积核参数缓存
	reg rd_req_dsc_dma_blk_start_reg; // 启动读请求描述子DMA
	reg wt_req_dsc_dma_blk_start_reg; // 启动写请求描述子DMA
	reg rd_req_dsc_dma_blk_idle_reg; // 读请求描述子DMA空闲标志
	reg wt_req_dsc_dma_blk_idle_reg; // 写请求描述子DMA空闲标志
	// 0x04
	reg global_itr_en_reg; // 全局中断使能
	reg[2:0] itr_en_vec_regs; // 子中断使能向量
	// 0x08
	reg global_itr_flag_reg; // 全局中断标志
	reg[2:0] itr_flag_vec_regs; // 子中断标志向量
	// 0x0C
	reg[31:0] wt_req_itr_th_regs; // 写请求处理完成中断阈值
	// 0x10
	reg en_conv_cal_reg; // 使能卷积计算
	// 0x14
	reg kernal_type_reg; // 卷积核类型
	reg[3:0] padding_en_regs; // 外拓填充使能
	// 0x18
	reg[31:0] rd_req_buf_baseaddr_regs; // 读请求缓存区首地址
	// 0x1C
	reg[31:0] rd_req_n_regs; // 读请求个数 - 1 
	// 0x20
	reg[31:0] wt_req_buf_baseaddr_regs; // 写请求缓存区首地址
	// 0x24
	reg[31:0] wt_req_n_regs; // 写请求个数 - 1
	// 0x28
	reg[15:0] feature_map_w_regs; // 输入特征图宽度 - 1
	reg[15:0] feature_map_h_regs; // 输入特征图高度 - 1
	// 0x2C
	reg[15:0] feature_map_chn_n_regs; // 输入特征图通道数 - 1
	reg[15:0] kernal_n_regs; // 卷积核个数 - 1
	// 0x30, 0x34
	reg[63:0] act_rate_c_regs; // Relu激活系数c
	// 0x3C
	reg[15:0] o_ft_map_w_regs; // 输出特征图宽度 - 1
	reg[15:0] o_ft_map_h_regs; // 输出特征图高度 - 1
	// 0x40
	reg[2:0] horizontal_step_regs; // 水平步长 - 1
	reg[2:0] vertical_step_regs; // 垂直步长 - 1
	reg step_type_reg; // 步长类型
	// 0x44
	reg[1:0] act_type_regs; // 激活类型
	// 0x48
	reg non_ln_act_lut_wen_reg;
	reg[10:0] non_ln_act_lut_waddr_regs;
	reg[15:0] non_ln_act_lut_din_regs; // Q15
	
	assign rd_req_dsc_dma_blk_start = rd_req_dsc_dma_blk_start_reg;
	assign wt_req_dsc_dma_blk_start = wt_req_dsc_dma_blk_start_reg;
	
	assign en_conv_cal = en_conv_cal_reg;
	
	assign rst_linear_pars_buf = rst_linear_pars_buf_reg;
	assign rst_cal_path_kernal_buf = rst_cal_path_kernal_buf_reg;
	
	assign wt_req_itr_th = wt_req_itr_th_regs;
	assign en_wt_req_fns_itr = global_itr_en_reg & itr_en_vec_regs[2];
	
	assign to_set_wt_req_fns_n = {4{regs_en & (regs_addr == 14)}} & regs_wen;
	assign wt_req_fns_n_set_v = regs_din;
	
	assign non_ln_act_lut_wen = non_ln_act_lut_wen_reg;
	assign non_ln_act_lut_waddr = non_ln_act_lut_waddr_regs;
	assign non_ln_act_lut_din = non_ln_act_lut_din_regs;
	
	assign act_rate_c = act_rate_c_regs;
	assign rd_req_buf_baseaddr = rd_req_buf_baseaddr_regs;
	assign rd_req_n = rd_req_n_regs;
	assign wt_req_buf_baseaddr = wt_req_buf_baseaddr_regs;
	assign wt_req_n = wt_req_n_regs;
	assign kernal_type = kernal_type_reg;
	assign feature_map_w = feature_map_w_regs;
	assign feature_map_h = feature_map_h_regs;
	assign feature_map_chn_n = feature_map_chn_n_regs;
	assign kernal_n = kernal_n_regs;
	assign padding_en = padding_en_regs;
	assign o_ft_map_w = o_ft_map_w_regs;
	assign o_ft_map_h = o_ft_map_h_regs;
	assign horizontal_step = horizontal_step_regs;
	assign vertical_step = vertical_step_regs;
	assign step_type = step_type_reg;
	assign act_type = act_type_regs;
	
	assign regs_dout = regs_region_rd_out;
	
	assign global_itr_req = (|(itr_req & itr_en_vec_regs)) & global_itr_en_reg & (~global_itr_flag_reg);
	
	assign regs_region_rd_out_nxt = 
		({32{regs_addr == 0}} & {
			8'dx, 
			6'dx, wt_req_dsc_dma_blk_idle_reg, rd_req_dsc_dma_blk_idle_reg, 
			8'dx, 
			8'dx
		}) | 
		({32{regs_addr == 1}} & {
			8'dx, 
			8'dx, 
			5'dx, itr_en_vec_regs, 
			7'dx, global_itr_en_reg
		}) | 
		({32{regs_addr == 2}} & {
			8'dx, 
			8'dx, 
			5'dx, itr_flag_vec_regs, 
			7'dx, global_itr_flag_reg
		}) | 
		({32{regs_addr == 3}} & {
			wt_req_itr_th_regs[31:24], 
			wt_req_itr_th_regs[23:16], 
			wt_req_itr_th_regs[15:8], 
			wt_req_itr_th_regs[7:0]
		}) | 
		({32{regs_addr == 4}} & {
			8'dx, 
			8'dx, 
			8'dx, 
			7'dx, en_conv_cal_reg
		}) | 
		({32{regs_addr == 5}} & {
			8'dx, 
			8'dx, 
			4'dx, padding_en_regs, 
			7'dx, kernal_type_reg
		}) | 
		({32{regs_addr == 6}} & {
			rd_req_buf_baseaddr_regs[31:24], 
			rd_req_buf_baseaddr_regs[23:16], 
			rd_req_buf_baseaddr_regs[15:8], 
			rd_req_buf_baseaddr_regs[7:0]
		}) | 
		({32{regs_addr == 7}} & {
			rd_req_n_regs[31:24], 
			rd_req_n_regs[23:16], 
			rd_req_n_regs[15:8], 
			rd_req_n_regs[7:0]
		}) | 
		({32{regs_addr == 8}} & {
			wt_req_buf_baseaddr_regs[31:24], 
			wt_req_buf_baseaddr_regs[23:16], 
			wt_req_buf_baseaddr_regs[15:8], 
			wt_req_buf_baseaddr_regs[7:0]
		}) | 
		({32{regs_addr == 9}} & {
			wt_req_n_regs[31:24], 
			wt_req_n_regs[23:16], 
			wt_req_n_regs[15:8], 
			wt_req_n_regs[7:0]
		}) | 
		({32{regs_addr == 10}} & {
			feature_map_h_regs[15:8], 
			feature_map_h_regs[7:0], 
			feature_map_w_regs[15:8], 
			feature_map_w_regs[7:0]
		}) | 
		({32{regs_addr == 11}} & {
			kernal_n_regs[15:8], 
			kernal_n_regs[7:0], 
			feature_map_chn_n_regs[15:8], 
			feature_map_chn_n_regs[7:0]
		}) | 
		({32{regs_addr == 12}} & {
			act_rate_c_regs[31:24], 
			act_rate_c_regs[23:16], 
			act_rate_c_regs[15:8], 
			act_rate_c_regs[7:0]
		}) | 
		({32{regs_addr == 13}} & {
			act_rate_c_regs[63:56], 
			act_rate_c_regs[55:48], 
			act_rate_c_regs[47:40], 
			act_rate_c_regs[39:32]
		}) | 
		({32{regs_addr == 14}} & {
			wt_req_fns_n_cur_v[31:24], 
			wt_req_fns_n_cur_v[23:16], 
			wt_req_fns_n_cur_v[15:8], 
			wt_req_fns_n_cur_v[7:0]
		}) | 
		({32{regs_addr == 15}} & {
			o_ft_map_h_regs[15:8], 
			o_ft_map_h_regs[7:0], 
			o_ft_map_w_regs[15:8], 
			o_ft_map_w_regs[7:0]
		}) | 
		({32{regs_addr == 16}} & {
			8'dx, 
			7'dx, step_type_reg, 
			5'dx, vertical_step_regs, 
			5'dx, horizontal_step_regs
		}) | 
		({32{regs_addr == 17}} & {
			8'dx, 
			8'dx, 
			8'dx, 
			6'dx, act_type_regs
		});
	
	// 寄存器区读数据
	always @(posedge clk)
	begin
		if(regs_en & (~is_write))
			regs_region_rd_out <= # simulation_delay regs_region_rd_out_nxt;
	end
	
	// 0x00, 1~0
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			{rst_cal_path_kernal_buf_reg, rst_linear_pars_buf_reg} <= 2'b00;
		else
			{rst_cal_path_kernal_buf_reg, rst_linear_pars_buf_reg} <= # simulation_delay 
				{2{regs_en & regs_wen[0] & (regs_addr == 0)}} & regs_din[1:0];
	end
	
	// 0x00, 9~8
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			{wt_req_dsc_dma_blk_start_reg, rd_req_dsc_dma_blk_start_reg} <= 2'b00;
		else
			{wt_req_dsc_dma_blk_start_reg, rd_req_dsc_dma_blk_start_reg} <= # simulation_delay 
				{2{regs_en & regs_wen[1] & (regs_addr == 0)}} & regs_din[9:8];
	end
	
	// 0x00, 17~16
	always @(posedge clk)
	begin
		{wt_req_dsc_dma_blk_idle_reg, rd_req_dsc_dma_blk_idle_reg} <= # simulation_delay 
			{wt_req_dsc_dma_blk_idle, rd_req_dsc_dma_blk_idle};
	end
	
	// 0x04, 0
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			global_itr_en_reg <= 1'b0;
		else if(regs_en & regs_wen[0] & (regs_addr == 1))
			global_itr_en_reg <= # simulation_delay regs_din[0];
	end
	
	// 0x04, 10~8
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			itr_en_vec_regs <= 3'b000;
		else if(regs_en & regs_wen[1] & (regs_addr == 1))
			itr_en_vec_regs <= # simulation_delay regs_din[10:8];
	end
	
	// 0x08, 0
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			global_itr_flag_reg <= 1'b0;
		else if((regs_en & regs_wen[0] & (regs_addr == 2)) | (~global_itr_flag_reg))
			global_itr_flag_reg <= # simulation_delay 
				(~(regs_en & regs_wen[0] & (regs_addr == 2))) & // 清零全局中断标志
				((|(itr_req & itr_en_vec_regs)) & global_itr_en_reg);
	end
	
	// 0x08, 10~8
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			itr_flag_vec_regs <= 3'b000;
		else if(global_itr_req)
			itr_flag_vec_regs <= # simulation_delay itr_req & itr_en_vec_regs;
	end
	
	// 0x0C, 31~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 3))
			wt_req_itr_th_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 3))
			wt_req_itr_th_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 3))
			wt_req_itr_th_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 3))
			wt_req_itr_th_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x10, 0
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			en_conv_cal_reg <= 1'b0;
		else if(regs_en & regs_wen[0] & (regs_addr == 4))
			en_conv_cal_reg <= # simulation_delay regs_din[0];
	end
	
	// 0x14, 0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 5))
			kernal_type_reg <= # simulation_delay regs_din[0];
	end
	
	// 0x14, 11~8
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 5))
			padding_en_regs <= # simulation_delay regs_din[11:8];
	end
	
	// 0x18, 31~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 6))
			rd_req_buf_baseaddr_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 6))
			rd_req_buf_baseaddr_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 6))
			rd_req_buf_baseaddr_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 6))
			rd_req_buf_baseaddr_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x1C, 31~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 7))
			rd_req_n_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 7))
			rd_req_n_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 7))
			rd_req_n_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 7))
			rd_req_n_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x20, 31~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 8))
			wt_req_buf_baseaddr_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 8))
			wt_req_buf_baseaddr_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 8))
			wt_req_buf_baseaddr_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 8))
			wt_req_buf_baseaddr_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x24, 31~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 9))
			wt_req_n_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 9))
			wt_req_n_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 9))
			wt_req_n_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 9))
			wt_req_n_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x28, 15~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 10))
			feature_map_w_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 10))
			feature_map_w_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	
	// 0x28, 31~16
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 10))
			feature_map_h_regs[7:0] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 10))
			feature_map_h_regs[15:8] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x2C, 15~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 11))
			feature_map_chn_n_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 11))
			feature_map_chn_n_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	
	// 0x2C, 31~16
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 11))
			kernal_n_regs[7:0] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 11))
			kernal_n_regs[15:8] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x30, 31~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 12))
			act_rate_c_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 12))
			act_rate_c_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 12))
			act_rate_c_regs[23:16] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 12))
			act_rate_c_regs[31:24] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x34, 31~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 13))
			act_rate_c_regs[39:32] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 13))
			act_rate_c_regs[47:40] <= # simulation_delay regs_din[15:8];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 13))
			act_rate_c_regs[55:48] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 13))
			act_rate_c_regs[63:56] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x3C, 15~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 15))
			o_ft_map_w_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 15))
			o_ft_map_w_regs[15:8] <= # simulation_delay regs_din[15:8];
	end
	
	// 0x3C, 31~16
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 15))
			o_ft_map_h_regs[7:0] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 15))
			o_ft_map_h_regs[15:8] <= # simulation_delay regs_din[31:24];
	end
	
	// 0x40, 2~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 16))
			horizontal_step_regs <= # simulation_delay regs_din[2:0];
	end
	
	// 0x40, 10~8
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 16))
			vertical_step_regs <= # simulation_delay regs_din[10:8];
	end
	
	// 0x40, 16
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 16))
			step_type_reg <= # simulation_delay regs_din[16];
	end
	
	// 0x44, 1~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 17))
			act_type_regs <= # simulation_delay regs_din[1:0];
	end
	
	// 0x48, 10~0
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[0] & (regs_addr == 18))
			non_ln_act_lut_waddr_regs[7:0] <= # simulation_delay regs_din[7:0];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[1] & (regs_addr == 18))
			non_ln_act_lut_waddr_regs[10:8] <= # simulation_delay regs_din[10:8];
	end
	
	// 0x48, 31~16
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[2] & (regs_addr == 18))
			non_ln_act_lut_din_regs[7:0] <= # simulation_delay regs_din[23:16];
	end
	always @(posedge clk)
	begin
		if(regs_en & regs_wen[3] & (regs_addr == 18))
			non_ln_act_lut_din_regs[15:8] <= # simulation_delay regs_din[31:24];
	end
	
	// Sigmoid/Tanh查找表写使能
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			non_ln_act_lut_wen_reg <= 1'b0;
		else
			non_ln_act_lut_wen_reg <= # simulation_delay regs_en & (|regs_wen) & (regs_addr == 18);
	end
	
	// 中断发生器
    itr_generator #(
        .pulse_w(10),
        .simulation_delay(simulation_delay)
    )itr_generator_u(
        .clk(clk),
        .rst_n(rst_n),
        
        .itr_org(global_itr_req),
        
        .itr(itr)
    );
	
endmodule
