`timescale 1ns / 1ps

`ifndef __MONITOR_H

`define __MONITOR_H

`define AXIMon
// `define APBMon
// `define AXISMon

`include "transactions.sv"

/** 监测器:AXI **/
`ifdef AXIMon
class AXIMonitor #(
	real out_drive_t = 1, // 输出驱动延迟量
	integer addr_width = 32, // 地址位宽(1~64)
	integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
    integer bresp_width = 2, // 写响应信号位宽(0 | 2 | 3)
    integer rresp_width = 2 // 读响应信号位宽(0 | 2 | 3)
)extends uvm_monitor;
	
	// 虚接口
	local virtual AXI #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_if; // AXI虚接口
	
	// 事务
	local int unsigned rd_trans_i; // 读事务id
	local int unsigned wt_trans_i; // 写事务id
	local AXITrans #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_ar_trans_fifo[$]; // AXI读地址通道事务fifo
	local AXITrans #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_aw_trans_fifo[$]; // AXI写地址通道事务fifo
	local AXITrans #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_r_trans_fifo[$]; // AXI读数据通道事务fifo
	local AXITrans #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_w_trans_fifo[$]; // AXI写数据通道事务fifo
	local AXITrans #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_b_trans_fifo[$]; // AXI写响应通道事务fifo
	
	// 通信端口
	uvm_analysis_port #(AXITrans #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width))) rd_trans_analysis_port;
	uvm_analysis_port #(AXITrans #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width))) wt_trans_analysis_port;
	
	// 注册component
	`uvm_component_param_utils(AXIMonitor #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), .bresp_width(bresp_width), .rresp_width(rresp_width)))
	
	function new(string name = "AXIMonitor", uvm_component parent = null);
		super.new(name, parent);
		
		this.rd_trans_i = 0;
		this.wt_trans_i = 0;
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual AXI #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), 
			.bresp_width(bresp_width), .rresp_width(rresp_width)).monitor)::get(this, "", "axi_if", this.axi_if))
		begin
			`uvm_fatal("AXIMonitor", "virtual interface must be set for axi_if!!!")
		end
		
		// 创建通信端口
		this.rd_trans_analysis_port = new("rd_trans_analysis_port", this);
		this.wt_trans_analysis_port = new("wt_trans_analysis_port", this);
		
		`uvm_info("AXIMonitor", "AXIMonitor built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			this.monitor_ar(); // 监测AR通道
			this.monitor_aw(); // 监测AW通道
			this.monitor_r(); // 监测R通道
			this.monitor_w(); // 监测W通道
			this.monitor_b(); // 监测B通道
			
			this.gen_r_trans(); // 生成读事务
			this.gen_w_trans(); // 生成写事务
		join_none
	endtask
	
	local task gen_r_trans();
		forever
		begin
			automatic AXITrans #(.addr_width(addr_width), .data_width(data_width), 
				.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_ar_trans;
			automatic AXITrans #(.addr_width(addr_width), .data_width(data_width), 
				.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_r_trans;
			
			wait((this.axi_ar_trans_fifo.size() > 0) && (this.axi_r_trans_fifo.size() > 0));
			
			axi_ar_trans = this.axi_ar_trans_fifo.pop_front();
			axi_r_trans = this.axi_r_trans_fifo.pop_front();
			
			axi_r_trans.is_rd_trans = 1'b1;
			axi_r_trans.data_n = axi_r_trans.rdata.size();
			
			axi_r_trans.addr = axi_ar_trans.addr;
			axi_r_trans.burst = axi_ar_trans.burst;
			axi_r_trans.cache = axi_ar_trans.cache;
			axi_r_trans.len = axi_ar_trans.len;
			axi_r_trans.lock = axi_ar_trans.lock;
			axi_r_trans.prot = axi_ar_trans.prot;
			axi_r_trans.size = axi_ar_trans.size;
			
			// 打印并传递事务
			// `uvm_info("AXIMonitor", $sformatf("AXIMonitor got rd_trans(i = %d)!", this.rd_trans_i), UVM_LOW)
			// axi_r_trans.print();
			this.rd_trans_analysis_port.write(axi_r_trans);
			this.rd_trans_i++;
		end
	endtask
	
	local task gen_w_trans();
		forever
		begin
			automatic AXITrans #(.addr_width(addr_width), .data_width(data_width), 
				.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_aw_trans;
			automatic AXITrans #(.addr_width(addr_width), .data_width(data_width), 
				.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_w_trans;
			automatic AXITrans #(.addr_width(addr_width), .data_width(data_width), 
				.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_b_trans;
			
			wait((this.axi_aw_trans_fifo.size() > 0) && (this.axi_w_trans_fifo.size() > 0) && 
				(this.axi_b_trans_fifo.size() > 0));
			
			axi_aw_trans = this.axi_aw_trans_fifo.pop_front();
			axi_w_trans = this.axi_w_trans_fifo.pop_front();
			axi_b_trans = this.axi_b_trans_fifo.pop_front();
			
			axi_w_trans.is_rd_trans = 1'b0;
			axi_w_trans.data_n = axi_w_trans.wdata.size();
			
			axi_w_trans.addr = axi_aw_trans.addr;
			axi_w_trans.burst = axi_aw_trans.burst;
			axi_w_trans.cache = axi_aw_trans.cache;
			axi_w_trans.len = axi_aw_trans.len;
			axi_w_trans.lock = axi_aw_trans.lock;
			axi_w_trans.prot = axi_aw_trans.prot;
			axi_w_trans.size = axi_aw_trans.size;
			
			axi_w_trans.bresp = axi_b_trans.bresp;
			
			// 打印并传递事务
			// `uvm_info("AXIMonitor", $sformatf("AXIMonitor got wt_trans(i = %d)!", this.wt_trans_i), UVM_LOW)
			// axi_w_trans.print();
			this.wt_trans_analysis_port.write(axi_w_trans);
			this.wt_trans_i++;
		end
	endtask
	
	local task monitor_ar();
		forever
		begin
			@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			if(this.axi_if.arvalid & this.axi_if.arready)
			begin
				automatic AXITrans #(.addr_width(addr_width), .data_width(data_width), 
					.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_trans;
				
				axi_trans = new();
				
				axi_trans.addr = this.axi_if.araddr;
				axi_trans.burst = this.axi_if.arburst;
				axi_trans.cache = this.axi_if.arcache;
				axi_trans.len = this.axi_if.arlen;
				axi_trans.lock = this.axi_if.arlock;
				axi_trans.prot = this.axi_if.arprot;
				axi_trans.size = this.axi_if.arsize;
				
				this.axi_ar_trans_fifo.push_back(axi_trans);
			end
		end
	endtask
	
	local task monitor_aw();
		forever
		begin
			@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			if(this.axi_if.awvalid & this.axi_if.awready)
			begin
				automatic AXITrans #(.addr_width(addr_width), .data_width(data_width), 
					.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_trans;
				
				axi_trans = new();
				
				axi_trans.addr = this.axi_if.awaddr;
				axi_trans.burst = this.axi_if.awburst;
				axi_trans.cache = this.axi_if.awcache;
				axi_trans.len = this.axi_if.awlen;
				axi_trans.lock = this.axi_if.awlock;
				axi_trans.prot = this.axi_if.awprot;
				axi_trans.size = this.axi_if.awsize;
				
				this.axi_aw_trans_fifo.push_back(axi_trans);
			end
		end
	endtask
	
	local task monitor_r();
		automatic AXITrans #(.addr_width(addr_width), .data_width(data_width), 
			.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_trans;
		
		axi_trans = new();
		
		forever
		begin
			@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			if(this.axi_if.rvalid && (this.axi_ar_trans_fifo.size() == 0))
				`uvm_error("AXIMonitor", "ar -> r not meet!")
			
			if(this.axi_if.rvalid & this.axi_if.rready)
			begin
				axi_trans.rdata.push_back(this.axi_if.rdata);
				axi_trans.rlast.push_back(this.axi_if.rlast);
				axi_trans.rresp.push_back(this.axi_if.rresp);
				
				if(this.axi_if.rlast)
				begin
					this.axi_r_trans_fifo.push_back(axi_trans);
					
					axi_trans = new();
				end
			end
		end
	endtask
	
	local task monitor_w();
		automatic AXITrans #(.addr_width(addr_width), .data_width(data_width), 
			.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_trans;
		
		axi_trans = new();
		
		forever
		begin
			@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			if(this.axi_if.wvalid & this.axi_if.wready)
			begin
				axi_trans.wdata.push_back(this.axi_if.wdata);
				axi_trans.wlast.push_back(this.axi_if.wlast);
				axi_trans.wstrb.push_back(this.axi_if.wstrb);
				
				if(this.axi_if.wlast)
				begin
					this.axi_w_trans_fifo.push_back(axi_trans);
					
					axi_trans = new();
				end
			end
		end
	endtask
	
	local task monitor_b();
		forever
		begin
			@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			if(this.axi_if.bvalid && 
				((this.axi_aw_trans_fifo.size() == 0) || (this.axi_w_trans_fifo.size() == 0)))
				`uvm_error("AXIMonitor", "aw, w -> b not meet!")
			
			if(this.axi_if.bvalid & this.axi_if.bready)
			begin
				automatic AXITrans #(.addr_width(addr_width), .data_width(data_width), 
					.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_trans;
				
				axi_trans = new();
				
				axi_trans.bresp = this.axi_if.bresp;
				
				this.axi_b_trans_fifo.push_back(axi_trans);
			end
		end
	endtask
	
endclass
`endif

/** 监测器:APB **/
`ifdef APBMon
class APBMonitor extends uvm_monitor;

	local virtual APB.monitor apb_if; // APB虚接口
	
	local int unsigned trans_i; // 事务id
	local APBTrans apb_trans; // APB事务
	
	// 注册component
	`uvm_component_utils(APBMonitor)
	
	function new(string name = "APBMonitor", uvm_component parent = null);
		super.new(name, parent);
		
		this.trans_i = 0;
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual APB.monitor)::get(this, "", "apb_if", this.apb_if))
		begin
			`uvm_fatal("APBMonitor", "virtual interface must be set for apb_if!!!")
		end
		
		`uvm_info("APBMonitor", "APBMonitor built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		forever
		begin
            this.apb_trans = new();
			
			this.collect_item(this.apb_trans); // 收集APB事务
			
			// 打印事务
			// `uvm_info("APBMonitor", $sformatf("APBMonitor got transaction(i = %d)!", this.trans_i), UVM_LOW)
			// this.apb_trans.print();
			this.trans_i++;
        end
	endtask
	
	local task collect_item(ref APBTrans tr);
		while(1)
		begin
			@(posedge this.apb_if.clk iff this.apb_if.rst_n);
			
			if(this.apb_if.pselx & this.apb_if.penable & this.apb_if.pready)
			begin // 监测到APB传输
				tr.addr = this.apb_if.paddr;
				tr.wdata = this.apb_if.pwdata;
				tr.wstrb = this.apb_if.pstrb;
				tr.write = this.apb_if.pwrite;
				
				tr.rdata = this.apb_if.prdata;
				tr.slverr = this.apb_if.pslverr;
				
				break;
			end
		end
	endtask

endclass
`endif

/** 监测器:AXIS **/
`ifdef AXISMon
class AXISMonitor #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer data_width = 32, // 数据位宽(必须能被8整除)
    integer user_width = 0 // 用户数据位宽
)extends uvm_monitor;

	local virtual AXIS #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)).monitor axis_if; // AXIS虚接口
	
	local int unsigned trans_i; // 事务id
	local AXISTrans #(.data_width(data_width), .user_width(user_width)) axis_trans; // AXIS事务
	
	// 通信端口
	uvm_analysis_port #(AXISTrans #(.data_width(data_width), .user_width(user_width))) in_analysis_port;
	
	// 注册component
	`uvm_component_param_utils(AXISMonitor #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)))
	
	function new(string name = "AXISMonitor", uvm_component parent = null);
		super.new(name, parent);
		
		this.trans_i = 0;
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual AXIS #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)).monitor)::
			get(this, "", "axis_if", this.axis_if))
		begin
			`uvm_fatal("AXISMonitor", "virtual interface must be set for axis_if!!!")
		end
		
		// 创建通信端口
		this.in_analysis_port = new("monitor_in_analysis_port", this);
		
		`uvm_info("AXISMonitor", "AXISMonitor built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		forever
		begin
			// 创建AXIS事务
            this.axis_trans = new();
			
			// 收集AXIS事务
			this.collect_item(this.axis_trans);
			
			// 传递AXIS事务
			this.in_analysis_port.write(this.axis_trans);
			
			// 打印AXIS事务
			// `uvm_info("AXISMonitor", $sformatf("AXISMonitor got transaction(i = %d)!", this.trans_i), UVM_LOW)
			// this.axis_trans.print();
			this.trans_i++;
        end
	endtask
	
	local task collect_item(ref AXISTrans #(.data_width(data_width), .user_width(user_width)) tr);
		while(1)
		begin
			@(posedge this.axis_if.clk iff this.axis_if.rst_n);
			
			if(this.axis_if.valid && this.axis_if.ready)
			begin // 监测到AXIS握手
				tr.data.push_back(this.axis_if.data);
				tr.keep.push_back(this.axis_if.keep);
				tr.user.push_back(this.axis_if.user);
				tr.last.push_back(this.axis_if.last);
				
				if(this.axis_if.last)
				begin // 监测到AXIS数据包传输完成
					tr.data_n = tr.data.size();
					
					break;
				end
			end
		end
	endtask
	
endclass
`endif

`endif
