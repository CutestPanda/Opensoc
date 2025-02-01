`timescale 1ns / 1ps
/********************************************************************
本模块: 加载/存储控制单元

描述:
接收访存请求, 驱动数据ICB主机, 返回访存结果
包含深度为4的访存信息表

注意：
访存地址非对齐时不发起ICB传输, 且仅在访存信息表空时被接受
若发生数据总线响应超时, 则不再接受新的访存请求, 数据ICB主机停止传输
支持ICB滞外传输

协议:
ICB MASTER

作者: 陈家耀
日期: 2025/01/31
********************************************************************/


module panda_risc_v_lsu #(
	parameter integer inst_id_width = 4, // 指令编号的位宽
	parameter integer dbus_access_timeout_th = 16, // 数据总线访问超时周期数(必须>=1)
	parameter icb_zero_latency_supported = "false", // 是否支持零响应时延的ICB主机
    parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// 内存屏障处理
	output wire lsu_idle, // 访存单元空闲(标志)
	
	// 访存请求
	input wire s_req_ls_sel, // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	input wire[2:0] s_req_ls_type, // 访存类型
	input wire[4:0] s_req_rd_id_for_ld, // 用于加载的目标寄存器的索引
	input wire[31:0] s_req_ls_addr, // 访存地址
	input wire[31:0] s_req_ls_din, // 写数据
	input wire[inst_id_width-1:0] s_req_lsu_inst_id, // 指令编号
	input wire s_req_valid,
	output wire s_req_ready,
	
	// 访存结果
	output wire m_resp_ls_sel, // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	output wire[4:0] m_resp_rd_id_for_ld, // 用于加载的目标寄存器的索引
	output wire[31:0] m_resp_dout, // 读数据
	output wire[31:0] m_resp_ls_addr, // 访存地址
	output wire[1:0] m_resp_err, // 错误类型
	output wire[inst_id_width-1:0] m_resp_lsu_inst_id, // 指令编号
	output wire m_resp_valid,
	input wire m_resp_ready,
    
    // 数据ICB主机
	// 命令通道
	output wire[31:0] m_icb_cmd_addr,
	output wire m_icb_cmd_read,
	output wire[31:0] m_icb_cmd_wdata,
	output wire[3:0] m_icb_cmd_wmask,
	output wire m_icb_cmd_valid,
	input wire m_icb_cmd_ready,
	// 响应通道
	input wire[31:0] m_icb_rsp_rdata,
	input wire m_icb_rsp_err,
	input wire m_icb_rsp_valid,
	output wire m_icb_rsp_ready,
	
	// 数据总线访问超时标志
	output wire dbus_timeout
);
	
    // 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
        for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
			bit_depth = bit_depth >> 1;
    end
    endfunction
	
	/** 常量 **/
	// 访存类型
	localparam LS_TYPE_BYTE = 3'b000;
	localparam LS_TYPE_HALF_WORD = 3'b001;
	localparam LS_TYPE_WORD = 3'b010;
	localparam LS_TYPE_BYTE_UNSIGNED = 3'b100;
	localparam LS_TYPE_HALF_WORD_UNSIGNED = 3'b101;
	// 访存应答错误类型
	localparam DBUS_ACCESS_NORMAL = 2'b00; // 正常
	localparam DBUS_ACCESS_LS_UNALIGNED = 2'b01; // 访存地址非对齐
	localparam DBUS_ACCESS_BUS_ERR = 2'b10; // 数据总线访问错误
	localparam DBUS_ACCESS_TIMEOUT = 2'b11; // 响应超时
	// 访存信息各项的起始索引
	localparam integer LS_MSG_INST_ID = 79;
	localparam integer LS_MSG_LS_TYPE = 76;
	localparam integer LS_MSG_WMASK_SID = 72;
	localparam integer LS_MSG_IS_STORE_SID = 71;
	localparam integer LS_MSG_RD_ID_SID = 66;
	localparam integer LS_MSG_DIN_DOUT_SID = 34;
	localparam integer LS_MSG_ADDR_SID = 2;
	localparam integer LS_MSG_ERR_SID = 0;
	// 访存任务生命周期标志位索引
	localparam integer LS_TASK_START_STAGE_FID = 0;
	localparam integer LS_TASK_CMD_STAGE_FID = 1;
	localparam integer LS_TASK_RESP_STAGE_FID = 2;
	localparam integer LS_TASK_DONE_STAGE_FID = 3;
	
	/** 访存请求前处理 **/
	wire ls_addr_aligned; // 访存地址对齐(标志)
	wire[31:0] store_din; // 用于写存储映射的数据
	wire[3:0] store_wmask; // 用于写存储映射的字节有效掩码
	
	assign ls_addr_aligned = 
		(s_req_ls_type == LS_TYPE_BYTE) | 
		(s_req_ls_type == LS_TYPE_BYTE_UNSIGNED) | 
		(((s_req_ls_type == LS_TYPE_HALF_WORD) | (s_req_ls_type == LS_TYPE_HALF_WORD_UNSIGNED)) & (~s_req_ls_addr[0])) | 
		((s_req_ls_type == LS_TYPE_WORD) & (~s_req_ls_addr[0]) & (~s_req_ls_addr[1]));
	assign store_din = 
		({32{s_req_ls_type == LS_TYPE_BYTE}} & {4{s_req_ls_din[7:0]}}) | 
		({32{s_req_ls_type == LS_TYPE_HALF_WORD}} & {2{s_req_ls_din[15:0]}}) | 
		({32{s_req_ls_type == LS_TYPE_WORD}} & s_req_ls_din);
	assign store_wmask = 
		({32{s_req_ls_type == LS_TYPE_BYTE}} & (4'b0001 << s_req_ls_addr[1:0])) | 
		({32{s_req_ls_type == LS_TYPE_HALF_WORD}} & (4'b0011 << {s_req_ls_addr[1], 1'b0})) | 
		({32{s_req_ls_type == LS_TYPE_WORD}} & 4'b1111);
	
	/** 访存响应后处理 **/
	wire resp_is_store; // 当前访存响应是否对应写传输
	wire[2:0] resp_ls_type; // 当前访存响应对应的访存类型
	wire[31:0] resp_rdata_org; // 原始的访存读数据
	wire[31:0] resp_rdata_algn; // 对齐后的访存读数据
	wire[31:0] load_dout; // 从存储映射加载的数据
	
	assign load_dout = 
		resp_is_store ? resp_rdata_org:
			(({32{resp_ls_type == LS_TYPE_BYTE}} & {{24{resp_rdata_algn[7]}}, resp_rdata_algn[7:0]}) | 
			({32{resp_ls_type == LS_TYPE_HALF_WORD}} & {{16{resp_rdata_algn[15]}}, resp_rdata_algn[15:0]}) | 
			({32{resp_ls_type == LS_TYPE_WORD}} & resp_rdata_algn) | 
			({32{resp_ls_type == LS_TYPE_BYTE_UNSIGNED}} & {24'd0, resp_rdata_algn[7:0]}) | 
			({32{resp_ls_type == LS_TYPE_HALF_WORD_UNSIGNED}} & {16'd0, resp_rdata_algn[15:0]}));
	
	/** 数据总线访问超时计数器 **/
	reg[clogb2(dbus_access_timeout_th-1):0] m_icb_timeout_cnt; // 数据ICB主机访问超时计数器
	reg m_icb_timeout_flag; // 数据ICB主机访问超时标志
	reg m_icb_timeout_idct; // 数据ICB主机访问超时指示
	wire m_icb_timeout_cnt_en; // 数据ICB主机访问超时计数器使能标志
	wire m_icb_timeout_cnt_clr; // 数据ICB主机访问超时计数器清零指示
	
	assign dbus_timeout = m_icb_timeout_flag;
	
	// 数据ICB主机访问超时计数器
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			m_icb_timeout_cnt <= 0;
		else if((~m_icb_timeout_flag) & (m_icb_timeout_cnt_clr | m_icb_timeout_cnt_en))
			// m_icb_timeout_cnt_clr ? 0:(m_icb_timeout_cnt + 1)
			m_icb_timeout_cnt <= # simulation_delay 
				{(clogb2(dbus_access_timeout_th-1)+1){~m_icb_timeout_cnt_clr}} & (m_icb_timeout_cnt + 1);
	end
	
	// 数据ICB主机访问超时标志
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			m_icb_timeout_flag <= 1'b0;
		else if(~m_icb_timeout_flag)
			m_icb_timeout_flag <= # simulation_delay 
				(~m_icb_timeout_cnt_clr) & m_icb_timeout_cnt_en & (m_icb_timeout_cnt == (dbus_access_timeout_th - 1));
	end
	
	// 数据ICB主机访问超时指示
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			m_icb_timeout_idct <= 1'b0;
		else
			m_icb_timeout_idct <= # simulation_delay 
				(~m_icb_timeout_flag) & 
				(~m_icb_timeout_cnt_clr) & m_icb_timeout_cnt_en & (m_icb_timeout_cnt == (dbus_access_timeout_th - 1));
	end
	
	/** 访存信息表 **/
	// 存储寄存器组
	reg[79+inst_id_width-1:0] ls_msg_table[0:3]; // 访存信息寄存器组
	reg[3:0] ls_task_life_cycle_vec[0:3]; // 访存任务生命周期向量寄存器组
	// 滞外统计
	reg[2:0] launched_ls_task_n; // 已启动的访存任务个数
	reg[2:0] dbus_transmitting_ls_task_n; // 正在数据总线上进行传输的访存任务个数
	// 启动阶段
	wire launch_new_ls_task; // 启动新的访存任务(指示)
	reg ls_msg_table_empty_n; // 访存信息表空标志
	reg ls_msg_table_full_n; // 访存信息表满标志
	reg[3:0] ls_msg_table_wptr; // 访存信息表独热码写指针
	// 命令阶段
	wire start_icb_trans; // 启动新的ICB传输(指示)
	reg has_dbus_transmitting_ls_task; // 有正在数据总线上进行传输的访存任务(标志)
	wire ls_task_skip_cmd_stage; // 当前访存任务跳过命令阶段(指示)
	wire ls_task_fns_cmd_stage; // 当前访存任务完成命令阶段(指示)
	reg[1:0] ls_msg_table_cmd_stage_rptr; // 访存信息表命令阶段读指针
	// 响应阶段
	wire icb_resp_gotten; // 获得ICB响应(指示)
	wire ls_task_fns_resp_stage; // 当前访存任务完成响应阶段(指示)
	wire ls_task_skip_resp_stage_at_start; // 当前访存任务在启动阶段跳过响应阶段(指示)
	reg[3:0] ls_msg_table_resp_stage_wptr; // 访存信息表响应阶段独热码写指针
	// 完成阶段
	wire retire_ls_task; // 访存任务退休(指示)
	reg[1:0] ls_msg_table_rptr; // 访存信息表读指针
	
	assign lsu_idle = 
		(ls_task_life_cycle_vec[0][LS_TASK_START_STAGE_FID] | ls_task_life_cycle_vec[0][LS_TASK_DONE_STAGE_FID]) & 
		(ls_task_life_cycle_vec[1][LS_TASK_START_STAGE_FID] | ls_task_life_cycle_vec[1][LS_TASK_DONE_STAGE_FID]) & 
		(ls_task_life_cycle_vec[2][LS_TASK_START_STAGE_FID] | ls_task_life_cycle_vec[2][LS_TASK_DONE_STAGE_FID]) & 
		(ls_task_life_cycle_vec[3][LS_TASK_START_STAGE_FID] | ls_task_life_cycle_vec[3][LS_TASK_DONE_STAGE_FID]);
	
	assign s_req_ready = 
		(ls_addr_aligned | (~ls_msg_table_empty_n)) & // 访存地址非对齐时必须等待访存信息表空
		(~m_icb_timeout_flag) & // 发生数据总线响应超时后, 不再接受新的访存请求
		ls_msg_table_full_n; // 确保访存信息表非满
	
	assign m_resp_ls_sel = ls_msg_table[ls_msg_table_rptr][LS_MSG_IS_STORE_SID];
	assign m_resp_rd_id_for_ld = ls_msg_table[ls_msg_table_rptr][LS_MSG_RD_ID_SID+4:LS_MSG_RD_ID_SID];
	assign m_resp_dout = load_dout;
	assign m_resp_ls_addr = ls_msg_table[ls_msg_table_rptr][LS_MSG_ADDR_SID+31:LS_MSG_ADDR_SID];
	assign m_resp_err = ls_msg_table[ls_msg_table_rptr][LS_MSG_ERR_SID+1:LS_MSG_ERR_SID];
	assign m_resp_lsu_inst_id = ls_msg_table[ls_msg_table_rptr][LS_MSG_INST_ID+inst_id_width-1:LS_MSG_INST_ID];
	assign m_resp_valid = ls_task_life_cycle_vec[ls_msg_table_rptr][LS_TASK_DONE_STAGE_FID];
	
	assign m_icb_cmd_addr = ls_task_life_cycle_vec[ls_msg_table_cmd_stage_rptr][LS_TASK_CMD_STAGE_FID] ? 
		ls_msg_table[ls_msg_table_cmd_stage_rptr][LS_MSG_ADDR_SID+31:LS_MSG_ADDR_SID]:
		s_req_ls_addr; // 当访存信息表空时, 将访存请求直接旁路给数据ICB主机的命令通道
	assign m_icb_cmd_read = ls_task_life_cycle_vec[ls_msg_table_cmd_stage_rptr][LS_TASK_CMD_STAGE_FID] ? 
		(~ls_msg_table[ls_msg_table_cmd_stage_rptr][LS_MSG_IS_STORE_SID]):
		(~s_req_ls_sel); // 当访存信息表空时, 将访存请求直接旁路给数据ICB主机的命令通道
	assign m_icb_cmd_wdata = ls_task_life_cycle_vec[ls_msg_table_cmd_stage_rptr][LS_TASK_CMD_STAGE_FID] ? 
		ls_msg_table[ls_msg_table_cmd_stage_rptr][LS_MSG_DIN_DOUT_SID+31:LS_MSG_DIN_DOUT_SID]:
		store_din; // 当访存信息表空时, 将访存请求直接旁路给数据ICB主机的命令通道
	assign m_icb_cmd_wmask = ls_task_life_cycle_vec[ls_msg_table_cmd_stage_rptr][LS_TASK_CMD_STAGE_FID] ? 
		ls_msg_table[ls_msg_table_cmd_stage_rptr][LS_MSG_WMASK_SID+3:LS_MSG_WMASK_SID]:
		store_wmask; // 当访存信息表空时, 将访存请求直接旁路给数据ICB主机的命令通道
	assign m_icb_cmd_valid = (~m_icb_timeout_flag) & // 发生数据总线响应超时后, 不再发起新的ICB传输
		(ls_task_life_cycle_vec[ls_msg_table_cmd_stage_rptr][LS_TASK_CMD_STAGE_FID] | 
			(s_req_valid & ls_addr_aligned & ls_msg_table_full_n) // 若当前ICB主机的命令通道未被占用, 则将访存请求直接旁路出去, 
			                                                      // 访存地址非对齐时不发起ICB传输
		);
	
	assign m_icb_rsp_ready = ~m_icb_timeout_flag; // ICB响应通道的ready无需等待当前访存任务处于响应阶段; 
	                                              // 发生数据总线响应超时后, 不再接受新的ICB响应
	
	assign resp_is_store = ls_msg_table[ls_msg_table_rptr][LS_MSG_IS_STORE_SID];
	assign resp_ls_type = ls_msg_table[ls_msg_table_rptr][LS_MSG_LS_TYPE+2:LS_MSG_LS_TYPE];
	assign resp_rdata_org = ls_msg_table[ls_msg_table_rptr][LS_MSG_DIN_DOUT_SID+31:LS_MSG_DIN_DOUT_SID];
	assign resp_rdata_algn = resp_rdata_org >> 
			{ls_msg_table[ls_msg_table_rptr][LS_MSG_ADDR_SID+1:LS_MSG_ADDR_SID], 3'b000};
	
	assign m_icb_timeout_cnt_en = has_dbus_transmitting_ls_task;
	assign m_icb_timeout_cnt_clr = m_icb_rsp_valid & m_icb_rsp_ready;
	
	assign launch_new_ls_task = s_req_valid & s_req_ready;
	assign start_icb_trans = m_icb_cmd_valid & m_icb_cmd_ready;
	assign ls_task_skip_cmd_stage = 
		launch_new_ls_task & // 启动新的访存任务
		ls_addr_aligned & // 访存地址对齐
		(~ls_task_life_cycle_vec[ls_msg_table_cmd_stage_rptr][LS_TASK_CMD_STAGE_FID]) & // 当前ICB主机的命令通道未被占用时, 
		m_icb_cmd_ready;                                                                // 旁路的访存请求被数据ICB主机的命令通道接受
	assign ls_task_fns_cmd_stage = 
		(~m_icb_timeout_flag) & 
		// 当前ICB主机的命令通道被占用时, 访存信息表项被数据ICB主机的命令通道接受
		ls_task_life_cycle_vec[ls_msg_table_cmd_stage_rptr][LS_TASK_CMD_STAGE_FID] & m_icb_cmd_ready;
	assign icb_resp_gotten = 
		(m_icb_rsp_valid & m_icb_rsp_ready) | // ICB主机返回响应
		m_icb_timeout_idct; // 响应超时
	assign ls_task_fns_resp_stage = icb_resp_gotten;
	assign ls_task_skip_resp_stage_at_start = 
		launch_new_ls_task & // 启动新的访存任务
		(~ls_addr_aligned); // 访存地址非对齐
	assign retire_ls_task = m_resp_valid & m_resp_ready;
	
	// 已启动的访存任务个数
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			launched_ls_task_n <= 3'b000;
		else if(launch_new_ls_task ^ retire_ls_task)
			// launch_new_ls_task ? (launched_ls_task_n + 3'b001):(launched_ls_task_n - 3'b001)
			launched_ls_task_n <= # simulation_delay launched_ls_task_n + {{2{~launch_new_ls_task}}, 1'b1};
	end
	// 正在数据总线上进行传输的访存任务个数
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			dbus_transmitting_ls_task_n <= 3'b000;
		else if(start_icb_trans ^ icb_resp_gotten)
			// start_icb_trans ? (dbus_transmitting_ls_task_n + 3'b001):(dbus_transmitting_ls_task_n - 3'b001)
			dbus_transmitting_ls_task_n <= # simulation_delay dbus_transmitting_ls_task_n + {{2{~start_icb_trans}}, 1'b1};
	end
	
	// 访存信息表空标志
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			ls_msg_table_empty_n <= 1'b0;
		else if(launch_new_ls_task ^ retire_ls_task)
			// launch_new_ls_task ? 1'b1:(launched_ls_task_n != 3'b001)
			ls_msg_table_empty_n <= # simulation_delay launch_new_ls_task | (~launched_ls_task_n[0]) | launched_ls_task_n[1];
	end
	// 访存信息表满标志
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			ls_msg_table_full_n <= 1'b1;
		else if(launch_new_ls_task ^ retire_ls_task)
			// launch_new_ls_task ? (launched_ls_task_n != 3'b011):1'b1
			ls_msg_table_full_n <= # simulation_delay ~(launch_new_ls_task & launched_ls_task_n[0] & launched_ls_task_n[1]);
	end
	// 访存信息表独热码写指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			ls_msg_table_wptr <= 4'b0001;
		else if(launch_new_ls_task)
			ls_msg_table_wptr <= # simulation_delay {ls_msg_table_wptr[2:0], ls_msg_table_wptr[3]};
	end
	
	// 有正在数据总线上进行传输的访存任务(标志)
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			has_dbus_transmitting_ls_task <= 1'b0;
		else if(start_icb_trans ^ icb_resp_gotten)
			// start_icb_trans ? 1'b1:(dbus_transmitting_ls_task_n != 3'b001)
			has_dbus_transmitting_ls_task <= # simulation_delay 
				start_icb_trans | (~dbus_transmitting_ls_task_n[0]) | dbus_transmitting_ls_task_n[1];
	end
	
	// 访存信息表命令阶段读指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			ls_msg_table_cmd_stage_rptr <= 2'b00;
		else if(ls_task_fns_cmd_stage | ls_task_skip_resp_stage_at_start | ls_task_skip_cmd_stage)
			ls_msg_table_cmd_stage_rptr <= # simulation_delay ls_msg_table_cmd_stage_rptr + 2'b01;
	end
	
	// 访存信息表响应阶段独热码写指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			ls_msg_table_resp_stage_wptr <= 4'b0001;
		else if(ls_task_fns_resp_stage | ls_task_skip_resp_stage_at_start)
			ls_msg_table_resp_stage_wptr <= # simulation_delay 
				{ls_msg_table_resp_stage_wptr[2:0], ls_msg_table_resp_stage_wptr[3]};
	end
	
	// 访存信息表读指针
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			ls_msg_table_rptr <= 2'b00;
		else if(retire_ls_task)
			ls_msg_table_rptr <= # simulation_delay ls_msg_table_rptr + 2'b01;
	end
	
	// 写访存信息寄存器组
	genvar ls_msg_table_i;
	generate
		for(ls_msg_table_i = 0;ls_msg_table_i < 4;ls_msg_table_i = ls_msg_table_i + 1)
		begin
			// 错误类型
			always @(posedge clk)
			begin
				if( // 当前访存任务的响应返回
					(ls_task_fns_resp_stage & ls_msg_table_resp_stage_wptr[ls_msg_table_i]) | 
					// 启动新的访存任务时直接跳过响应阶段
					(ls_task_skip_resp_stage_at_start & ls_msg_table_wptr[ls_msg_table_i]))
					ls_msg_table[ls_msg_table_i][LS_MSG_ERR_SID+1:LS_MSG_ERR_SID] <= # simulation_delay 
						({2{ls_task_skip_resp_stage_at_start & ls_msg_table_wptr[ls_msg_table_i]}} & DBUS_ACCESS_LS_UNALIGNED) | 
						({2{m_icb_rsp_valid & m_icb_rsp_ready & m_icb_rsp_err & 
							ls_msg_table_resp_stage_wptr[ls_msg_table_i]}} & DBUS_ACCESS_BUS_ERR) | 
						({2{m_icb_rsp_valid & m_icb_rsp_ready & (~m_icb_rsp_err) & 
							ls_msg_table_resp_stage_wptr[ls_msg_table_i]}} & DBUS_ACCESS_NORMAL) | 
						({2{m_icb_timeout_idct & ls_msg_table_resp_stage_wptr[ls_msg_table_i]}} & DBUS_ACCESS_TIMEOUT);
			end
			
			// 访存地址
			always @(posedge clk)
			begin
				if(launch_new_ls_task & ls_msg_table_wptr[ls_msg_table_i]) // 启动阶段时载入
					ls_msg_table[ls_msg_table_i][LS_MSG_ADDR_SID+31:LS_MSG_ADDR_SID] <= # simulation_delay 
						s_req_ls_addr;
			end
			
			// 访存数据
			always @(posedge clk)
			begin
				if( // 启动新的访存任务
					(launch_new_ls_task & ls_msg_table_wptr[ls_msg_table_i]) | 
					// 当前访存任务的响应从ICB主机返回, 且为读访存
					((m_icb_rsp_valid & m_icb_rsp_ready) & ls_msg_table_resp_stage_wptr[ls_msg_table_i] & 
						(~ls_msg_table[ls_msg_table_i][LS_MSG_IS_STORE_SID])))
					ls_msg_table[ls_msg_table_i][LS_MSG_DIN_DOUT_SID+31:LS_MSG_DIN_DOUT_SID] <= # simulation_delay 
						(launch_new_ls_task & ls_msg_table_wptr[ls_msg_table_i] & 
							((icb_zero_latency_supported == "false") | s_req_ls_sel)) ? 
							store_din: // 若为写访存, 启动阶段载入写数据
							m_icb_rsp_rdata; // 响应阶段[或对于立即完成ICB传输的读访存]载入读数据
			end
			
			// 用于加载的目标寄存器的索引
			always @(posedge clk)
			begin
				if(launch_new_ls_task & ls_msg_table_wptr[ls_msg_table_i]) // 启动阶段时载入
					ls_msg_table[ls_msg_table_i][LS_MSG_RD_ID_SID+4:LS_MSG_RD_ID_SID] <= # simulation_delay 
						s_req_rd_id_for_ld;
			end
			
			// 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
			always @(posedge clk)
			begin
				if(launch_new_ls_task & ls_msg_table_wptr[ls_msg_table_i]) // 启动阶段时载入
					ls_msg_table[ls_msg_table_i][LS_MSG_IS_STORE_SID] <= # simulation_delay 
						s_req_ls_sel;
			end
			
			// 用于写存储映射的字节有效掩码
			always @(posedge clk)
			begin
				if(launch_new_ls_task & ls_msg_table_wptr[ls_msg_table_i]) // 启动阶段时载入
					ls_msg_table[ls_msg_table_i][LS_MSG_WMASK_SID+3:LS_MSG_WMASK_SID] <= # simulation_delay 
						store_wmask;
			end
			
			// 访存类型
			always @(posedge clk)
			begin
				if(launch_new_ls_task & ls_msg_table_wptr[ls_msg_table_i]) // 启动阶段时载入
					ls_msg_table[ls_msg_table_i][LS_MSG_LS_TYPE+2:LS_MSG_LS_TYPE] <= # simulation_delay 
						s_req_ls_type;
			end
			
			// 指令编号
			always @(posedge clk)
			begin
				if(launch_new_ls_task & ls_msg_table_wptr[ls_msg_table_i]) // 启动阶段时载入
					ls_msg_table[ls_msg_table_i][LS_MSG_INST_ID+inst_id_width-1:LS_MSG_INST_ID] <= # simulation_delay 
						s_req_lsu_inst_id;
			end
		end
	endgenerate
	
	// 访存任务生命周期向量寄存器组
	genvar ls_task_life_cycle_vec_i;
	generate
		for(ls_task_life_cycle_vec_i = 0;ls_task_life_cycle_vec_i < 4;ls_task_life_cycle_vec_i = ls_task_life_cycle_vec_i + 1)
		begin
			always @(posedge clk or negedge resetn)
			begin
				if(~resetn)
					ls_task_life_cycle_vec[ls_task_life_cycle_vec_i] <= (4'b0001 << LS_TASK_START_STAGE_FID);
				else if(
				// 启动新的访存任务
				(ls_task_life_cycle_vec[ls_task_life_cycle_vec_i][LS_TASK_START_STAGE_FID] & 
					ls_msg_table_wptr[ls_task_life_cycle_vec_i] & launch_new_ls_task) | 
				// 数据ICB主机命令通道完成传输
				(ls_task_life_cycle_vec[ls_task_life_cycle_vec_i][LS_TASK_CMD_STAGE_FID] & 
					(ls_msg_table_cmd_stage_rptr == ls_task_life_cycle_vec_i) & ls_task_fns_cmd_stage) | 
				// 数据ICB主机响应通道完成传输
				(ls_task_life_cycle_vec[ls_task_life_cycle_vec_i][LS_TASK_RESP_STAGE_FID] & 
					ls_msg_table_resp_stage_wptr[ls_task_life_cycle_vec_i] & ls_task_fns_resp_stage) | 
				// 后级取走访存结果
				(ls_task_life_cycle_vec[ls_task_life_cycle_vec_i][LS_TASK_DONE_STAGE_FID] & 
					(ls_msg_table_rptr == ls_task_life_cycle_vec_i) & retire_ls_task))
					ls_task_life_cycle_vec[ls_task_life_cycle_vec_i] <= # simulation_delay 
						// 现处于开始阶段, 不跳过命令阶段
						({4{ls_task_life_cycle_vec[ls_task_life_cycle_vec_i][LS_TASK_START_STAGE_FID] & 
							(~ls_task_skip_cmd_stage) & (~ls_task_skip_resp_stage_at_start)}} & 
								(4'b0001 << LS_TASK_CMD_STAGE_FID)) | 
						// 现处于开始阶段, 跳过命令阶段, 不跳过响应阶段, 
						// 在请求旁路到数据ICB主机命令通道并被立即接受[但响应未立即返回]时发生
						({4{ls_task_life_cycle_vec[ls_task_life_cycle_vec_i][LS_TASK_START_STAGE_FID] & 
							ls_task_skip_cmd_stage & ((icb_zero_latency_supported == "false") | 
							(~(m_icb_rsp_valid & m_icb_rsp_ready & ls_msg_table_resp_stage_wptr[ls_task_life_cycle_vec_i])))}} & 
								(4'b0001 << LS_TASK_RESP_STAGE_FID)) | 
						// 现处于开始阶段, 跳过命令阶段, 跳过响应阶段, 在访存地址非对齐[或旁路的请求立即完成ICB传输]时发生
						({4{ls_task_life_cycle_vec[ls_task_life_cycle_vec_i][LS_TASK_START_STAGE_FID] & 
							(ls_task_skip_resp_stage_at_start | ((icb_zero_latency_supported == "true") & 
							m_icb_rsp_valid & m_icb_rsp_ready & ls_msg_table_resp_stage_wptr[ls_task_life_cycle_vec_i]))}} & 
								(4'b0001 << LS_TASK_DONE_STAGE_FID)) | 
						// 现处于命令阶段, 直接更新为响应阶段
						({4{ls_task_life_cycle_vec[ls_task_life_cycle_vec_i][LS_TASK_CMD_STAGE_FID] & 
							((icb_zero_latency_supported == "false") | 
							(~(m_icb_rsp_valid & m_icb_rsp_ready & ls_msg_table_resp_stage_wptr[ls_task_life_cycle_vec_i])))}} & 
								(4'b0001 << LS_TASK_RESP_STAGE_FID)) | 
						// [现处于命令阶段, 跳过响应阶段, 在响应立即返回时发生]
						({4{ls_task_life_cycle_vec[ls_task_life_cycle_vec_i][LS_TASK_CMD_STAGE_FID] & 
							(icb_zero_latency_supported == "true") & 
							m_icb_rsp_valid & m_icb_rsp_ready & ls_msg_table_resp_stage_wptr[ls_task_life_cycle_vec_i]}} & 
								(4'b0001 << LS_TASK_DONE_STAGE_FID)) | 
						// 现处于响应阶段, 直接更新为完成阶段
						({4{ls_task_life_cycle_vec[ls_task_life_cycle_vec_i][LS_TASK_RESP_STAGE_FID]}} & 
							(4'b0001 << LS_TASK_DONE_STAGE_FID)) | 
						// 现处于完成阶段, 直接更新为开始阶段
						({4{ls_task_life_cycle_vec[ls_task_life_cycle_vec_i][LS_TASK_DONE_STAGE_FID]}} & 
							(4'b0001 << LS_TASK_START_STAGE_FID));
			end
		end
	endgenerate
	
endmodule
