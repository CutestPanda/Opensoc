`timescale 1ns / 1ps

`ifndef __ENV_H

`define __ENV_H

`include "transactions.sv"
`include "agents.sv"

/** 环境:LSU **/
class LsuEnv #(
	real simulation_delay = 1 // 仿真延时
)extends uvm_env;
	
	// 组件
	AXISMasterAgent #(.out_drive_t(simulation_delay), .data_width(64), .user_width(9)) m_axis_req_ls_agt; // 访存请求AXIS主机代理
	AXISSlaveAgent #(.out_drive_t(simulation_delay), .data_width(64), .user_width(8)) s_axis_resp_ls_agt; // 访存结果AXIS从机代理
	ICBSlaveAgent #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32)) s_data_icb_agt; // 数据ICB从机代理
	
	// 通信端口
	local uvm_blocking_get_port #(AXISTrans #(.data_width(64), .user_width(9))) m_axis_req_ls_trans_port;
	local uvm_blocking_get_port #(AXISTrans #(.data_width(64), .user_width(8))) s_axis_resp_ls_trans_port;
	local uvm_blocking_get_port #(ICBTrans #(.addr_width(32), .data_width(32))) s_data_icb_trans_port;
	
	// 通信fifo
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(64), .user_width(9))) m_axis_req_ls_agt_fifo;
	local uvm_tlm_analysis_fifo #(AXISTrans #(.data_width(64), .user_width(8))) s_axis_resp_ls_agt_fifo;
	local uvm_tlm_analysis_fifo #(ICBTrans #(.addr_width(32), .data_width(32))) s_data_icb_agt_fifo;
	
	// 事务
	local AXISTrans #(.data_width(64), .user_width(9)) m_axis_req_ls_trans;
	local AXISTrans #(.data_width(64), .user_width(8)) s_axis_resp_ls_trans;
	local ICBTrans #(.addr_width(32), .data_width(32)) s_data_icb_trans;
	
	// 文件句柄
	local integer req_ls_fid;
	local integer resp_ls_fid;
	local integer icb_fid;
	
	// 事务编号
	local int unsigned m_axis_req_ls_tid;
	local int unsigned s_axis_resp_ls_tid;
	local int unsigned s_data_icb_tid;
	
	// 注册component
	`uvm_component_param_utils(LsuEnv #(.simulation_delay(simulation_delay)))
	
	function new(string name = "LsuEnv", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 创建agent
		this.m_axis_req_ls_agt = AXISMasterAgent #(.out_drive_t(simulation_delay), .data_width(64), .user_width(9))::
			type_id::create("agt1", this);
		this.m_axis_req_ls_agt.is_active = UVM_ACTIVE;
		this.s_axis_resp_ls_agt = AXISSlaveAgent #(.out_drive_t(simulation_delay), .data_width(64), .user_width(8))::
			type_id::create("agt2", this);
		this.s_axis_resp_ls_agt.is_active = UVM_ACTIVE;
		this.s_axis_resp_ls_agt.use_sqr = 1'b1;
		this.s_data_icb_agt = ICBSlaveAgent #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32))::
			type_id::create("agt3", this);
		this.s_data_icb_agt.is_active = UVM_ACTIVE;
		
		// 创建通信端口
		this.m_axis_req_ls_trans_port = new("m_axis_req_ls_trans_port", this);
		this.s_axis_resp_ls_trans_port = new("s_axis_resp_ls_trans_port", this);
		this.s_data_icb_trans_port = new("s_data_icb_trans_port", this);
		
		// 创建通信fifo
		this.m_axis_req_ls_agt_fifo = new("m_axis_req_ls_agt_fifo", this);
		this.s_axis_resp_ls_agt_fifo = new("s_axis_resp_ls_agt_fifo", this);
		this.s_data_icb_agt_fifo = new("s_data_icb_agt_fifo", this);
		
		// 打开文件
		this.req_ls_fid = $fopen("req.txt", "w");
		this.resp_ls_fid = $fopen("resp.txt", "w");
		this.icb_fid = $fopen("icb.txt", "w");
		
		// 初始化事务编号
		this.m_axis_req_ls_tid = 0;
		this.s_axis_resp_ls_tid = 0;
		this.s_data_icb_tid = 0;
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.m_axis_req_ls_agt.axis_analysis_port.connect(this.m_axis_req_ls_agt_fifo.analysis_export);
		this.m_axis_req_ls_trans_port.connect(this.m_axis_req_ls_agt_fifo.blocking_get_export);
		this.s_axis_resp_ls_agt.axis_analysis_port.connect(this.s_axis_resp_ls_agt_fifo.analysis_export);
		this.s_axis_resp_ls_trans_port.connect(this.s_axis_resp_ls_agt_fifo.blocking_get_export);
		this.s_data_icb_agt.icb_analysis_port.connect(this.s_data_icb_agt_fifo.analysis_export);
		this.s_data_icb_trans_port.connect(this.s_data_icb_agt_fifo.blocking_get_export);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever
			begin
				this.m_axis_req_ls_trans_port.get(this.m_axis_req_ls_trans);
				this.m_axis_req_ls_tid++;
				this.print_m_axis_req_ls_trans(this.m_axis_req_ls_trans);
			end
			forever
			begin
				this.s_axis_resp_ls_trans_port.get(this.s_axis_resp_ls_trans);
				this.s_axis_resp_ls_tid++;
				this.print_s_axis_resp_ls_trans(this.s_axis_resp_ls_trans);
			end
			forever
			begin
				this.s_data_icb_trans_port.get(this.s_data_icb_trans);
				this.s_data_icb_tid++;
				this.print_s_data_icb_trans(this.s_data_icb_trans);
			end
		join
	endtask
	
	local function void print_m_axis_req_ls_trans(ref AXISTrans #(.data_width(64), .user_width(9)) trans);
		$fdisplay(this.req_ls_fid, "id = %d", this.m_axis_req_ls_tid);
		
		$fdisplay(this.req_ls_fid, "ls_sel = %s", trans.user[0][0] ? "Store(Write)":"Load(Read)");
		$fdisplay(this.req_ls_fid, "ls_type = %s", (trans.user[0][3:1] == 3'b000) ? "byte":
												   (trans.user[0][3:1] == 3'b001) ? "half_word":
												   (trans.user[0][3:1] == 3'b010) ? "word":
												   (trans.user[0][3:1] == 3'b100) ? "unsigned byte":
												                                    "unsigned half_word");
		$fdisplay(this.req_ls_fid, "rd_id_for_ld = %d", trans.user[0][8:4]);
		$fdisplay(this.req_ls_fid, "ls_addr = %d", trans.data[0][31:0]);
		$fdisplay(this.req_ls_fid, "ls_din = %8.8x", trans.data[0][63:32]);
		$fdisplay(this.req_ls_fid, "-------------------------------------------");
	endfunction
	
	local function void print_s_axis_resp_ls_trans(ref AXISTrans #(.data_width(64), .user_width(8)) trans);
		$fdisplay(this.resp_ls_fid, "id = %d", this.s_axis_resp_ls_tid);
		
		$fdisplay(this.resp_ls_fid, "ls_sel = %s", trans.user[0][0] ? "Store(Write)":"Load(Read)");
		$fdisplay(this.resp_ls_fid, "rd_id_for_ld = %d", trans.user[0][5:1]);
		$fdisplay(this.resp_ls_fid, "resp_err = %s", (trans.user[0][7:6] == 2'b00) ? "normal":
		                                             (trans.user[0][7:6] == 2'b01) ? "ls_unaligned":
													 (trans.user[0][7:6] == 2'b10) ? "bus_err":
													                                 "timeout");
		$fdisplay(this.resp_ls_fid, "data = %8.8x", trans.data[0][31:0]);
		$fdisplay(this.resp_ls_fid, "ls_addr = %d", trans.data[0][63:32]);
		$fdisplay(this.resp_ls_fid, "-------------------------------------------");
	endfunction
	
	local function void print_s_data_icb_trans(ref ICBTrans #(.addr_width(32), .data_width(32)) trans);
		$fdisplay(this.icb_fid, "id = %d", this.s_data_icb_tid);
		
		$fdisplay(this.icb_fid, "cmd_addr = %d", trans.cmd_addr);
		$fdisplay(this.icb_fid, "cmd_read = %s", trans.cmd_read ? "Load(Read)":"Store(Write)");
		
		if(!trans.cmd_read)
		begin
			$fdisplay(this.icb_fid, "cmd_wdata = %8.8x", trans.cmd_wdata);
			$fdisplay(this.icb_fid, "cmd_wmask = %4.4b", trans.cmd_wmask);
		end
		
		$fdisplay(this.icb_fid, "****************************");
		
		if(trans.cmd_read)
			$fdisplay(this.icb_fid, "rsp_rdata = %8.8x", trans.rsp_rdata);
		$fdisplay(this.icb_fid, "rsp_err = %1.1b", trans.rsp_err);
		$fdisplay(this.icb_fid, "-------------------------------------------");
	endfunction
	
	function void close_file();
		$fclose(this.req_ls_fid);
		$fclose(this.resp_ls_fid);
		$fclose(this.icb_fid);
	endfunction
	
endclass
	
`endif
