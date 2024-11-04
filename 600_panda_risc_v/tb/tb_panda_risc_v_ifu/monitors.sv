`timescale 1ns / 1ps

`ifndef __MONITOR_H

`define __MONITOR_H

// 打开以下宏以启用monitor
// `define AXIMon
// `define APBMon
`define AXISMon
// `define AHBMon
// `define ReqAckMon
// `define ICBMon

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
class APBMonitor #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer addr_width = 32, // 地址位宽(1~32)
    integer data_width = 32 // 数据位宽(8 | 16 | 32)
)extends uvm_monitor;

	local virtual APB #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width)).monitor apb_if; // APB虚接口
	
	local int unsigned trans_i; // 事务id
	local APBTrans #(.addr_width(addr_width), .data_width(data_width)) apb_trans; // APB事务
	
	// 通信端口
	uvm_analysis_port #(APBTrans #(.addr_width(addr_width), .data_width(data_width))) in_analysis_port;
	
	// 注册component
	`uvm_component_utils(APBMonitor #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width)))
	
	function new(string name = "APBMonitor", uvm_component parent = null);
		super.new(name, parent);
		
		this.trans_i = 0;
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual APB #(.out_drive_t(out_drive_t), .addr_width(addr_width), 
			.data_width(data_width)).monitor)::get(this, "", "apb_if", this.apb_if))
		begin
			`uvm_fatal("APBMonitor", "virtual interface must be set for apb_if!!!")
		end
		
		// 创建通信端口
		this.in_analysis_port = new("monitor_in_analysis_port", this);
		
		`uvm_info("APBMonitor", "APBMonitor built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		forever
		begin
			// 创建APB事务
            this.apb_trans = new();
			
			// 收集APB事务
			this.collect_item(this.apb_trans);
			
			// 传递APB事务
			this.in_analysis_port.write(this.apb_trans);
			
			// 打印事务
			// `uvm_info("APBMonitor", $sformatf("APBMonitor got transaction(i = %d)!", this.trans_i), UVM_LOW)
			// this.apb_trans.print();
			this.trans_i++;
        end
	endtask
	
	local task collect_item(ref APBTrans #(.addr_width(addr_width), .data_width(data_width)) tr);
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
				tr.strb.push_back(this.axis_if.strb);
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

`ifdef AHBMon
/** 监测器:AHB **/
class AHBMonitor #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer slave_n = 1, // 从机个数
    integer addr_width = 32, // 地址位宽(10~64)
    integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
    integer burst_width = 3, // 突发类型位宽(0~3)
    integer prot_width = 4, // 保护类型位宽(0 | 4 | 7)
    integer master_width = 1 // 主机标识位宽(0~8)
)extends uvm_monitor;
	
	// 常量
	// 传输类型
	localparam HTRANS_IDLE = 2'b00;
	localparam HTRANS_BUSY = 2'b01;
	localparam HTRANS_NONSEQ = 2'b10;
	localparam HTRANS_SEQ = 2'b11;
	
	// AHB虚接口
	local virtual AHB #(.out_drive_t(out_drive_t), .slave_n(slave_n), .addr_width(addr_width), .data_width(data_width), 
		.burst_width(burst_width), .prot_width(prot_width), .master_width(master_width)).monitor ahb_if;
	
	local int unsigned trans_i; // 事务id
	local int unsigned trans_running_cnt; // 当前进行中的传输个数
	local AHBTrans #(.addr_width(addr_width), .data_width(data_width), 
		.burst_width(burst_width), .prot_width(prot_width), .master_width(master_width)) ahb_trans; // AHB事务
	
	// 通信端口
	uvm_analysis_port #(AHBTrans #(.addr_width(addr_width), .data_width(data_width), 
		.burst_width(burst_width), .prot_width(prot_width), .master_width(master_width))) in_analysis_port;
	
	// 注册component
	`uvm_component_param_utils(AHBMonitor #(.out_drive_t(out_drive_t), .slave_n(slave_n), .addr_width(addr_width), .data_width(data_width), .burst_width(burst_width), .prot_width(prot_width), .master_width(master_width)))
	
	function new(string name = "AHBMonitor", uvm_component parent = null);
		super.new(name, parent);
		
		this.trans_i = 0;
		this.trans_running_cnt = 0;
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual AHB #(.out_drive_t(out_drive_t), .slave_n(slave_n), .addr_width(addr_width), 
			.data_width(data_width), .burst_width(burst_width), .prot_width(prot_width), .master_width(master_width)).monitor)::
			get(this, "", "ahb_if", this.ahb_if))
		begin
			`uvm_fatal("AHBMonitor", "virtual interface must be set for ahb_if!!!")
		end
		
		// 创建通信端口
		this.in_analysis_port = new("monitor_in_analysis_port", this);
		
		`uvm_info("AHBMonitor", "AHBMonitor built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		@(posedge this.ahb_if.clk iff this.ahb_if.rst_n); // 等待复位释放
		
		forever
		begin
			// 等待传输开始
			while(!((this.ahb_if.hsel != 0) & (this.ahb_if.htrans == HTRANS_NONSEQ) & this.ahb_if.hready))
			begin
				@(posedge this.ahb_if.clk iff this.ahb_if.rst_n);
			end
			this.trans_running_cnt++;
			
			// 创建AHB事务
			this.ahb_trans = new();
			this.ahb_trans.haddr = this.ahb_if.haddr;
			this.ahb_trans.hburst = this.ahb_if.hburst;
			this.ahb_trans.hmastllock = this.ahb_if.hmastllock;
			this.ahb_trans.hprot = this.ahb_if.hprot;
			this.ahb_trans.hsize = this.ahb_if.hsize;
			this.ahb_trans.hnonsec = this.ahb_if.hnonsec;
			this.ahb_trans.hexcl = this.ahb_if.hexcl;
			this.ahb_trans.hmaster = this.ahb_if.hmaster;
			this.ahb_trans.hwrite = this.ahb_if.hwrite;
			
			// 收集读写数据
			do
			begin
				@(posedge this.ahb_if.clk iff this.ahb_if.rst_n);
				
				if((this.ahb_if.hsel != 0) & this.ahb_if.hready)
				begin
					if(this.trans_running_cnt)
					begin
						this.trans_running_cnt--;
						
						if(this.ahb_trans.hwrite)
						begin
							this.ahb_trans.hwdata.push_back(this.ahb_if.hwdata);
							this.ahb_trans.hwstrb.push_back(this.ahb_if.hwstrb);
						end
						else
							this.ahb_trans.hrdata.push_back(this.ahb_if.hrdata);
						
						this.ahb_trans.hresp.push_back(this.ahb_if.hresp);
						this.ahb_trans.hexokay.push_back(this.ahb_if.hexokay);
					end
					
					if(this.ahb_if.htrans == HTRANS_SEQ)
						this.trans_running_cnt++;
				end
			end
			while(!((this.ahb_if.hsel != 0) & this.ahb_if.hready & 
				((this.ahb_if.htrans == HTRANS_IDLE) | (this.ahb_if.htrans == HTRANS_NONSEQ))));
			
			// 传递AHB事务
			this.in_analysis_port.write(this.ahb_trans);
			
			// 打印AHB事务
			// `uvm_info("AHBMonitor", $sformatf("AHBMonitor got transaction(i = %d)!", this.trans_i), UVM_LOW)
			// this.ahb_trans.print();
			this.trans_i++;
		end
	endtask
	
endclass
`endif

`ifdef ReqAckMon
/** 监测器: req-ack **/
class ReqAckMonitor #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer req_payload_width = 32, // 请求数据位宽
	integer resp_payload_width = 32 // 响应数据位宽
)extends uvm_monitor;
	
	// req-ack虚接口
	local virtual ReqAck #(.out_drive_t(out_drive_t), 
		.req_payload_width(req_payload_width), .resp_payload_width(resp_payload_width)).monitor req_ack_if;
	
	local int unsigned trans_i; // 事务id
	
	local ReqAckTrans #(.req_payload_width(req_payload_width), 
		.resp_payload_width(resp_payload_width)) req_ack_trans; // req-ack事务
	
	// 通信端口
	uvm_analysis_port #(ReqAckTrans #(.req_payload_width(req_payload_width), 
		.resp_payload_width(resp_payload_width))) in_analysis_port;
	
	// 注册component
	`uvm_component_param_utils(ReqAckMonitor #(.out_drive_t(out_drive_t), .req_payload_width(req_payload_width), .resp_payload_width(resp_payload_width)))
	
	function new(string name = "ReqAckMonitor", uvm_component parent = null);
		super.new(name, parent);
		
		this.trans_i = 0;
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual ReqAck #(.out_drive_t(out_drive_t), 
			.req_payload_width(req_payload_width), .resp_payload_width(resp_payload_width)).monitor)::
			get(this, "", "req_ack_if", this.req_ack_if))
		begin
			`uvm_fatal("ReqAckMonitor", "virtual interface must be set for req_ack_if!!!")
		end
		
		// 创建通信端口
		this.in_analysis_port = new("monitor_in_analysis_port", this);
		
		`uvm_info("ReqAckMonitor", "ReqAckMonitor built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		@(posedge this.req_ack_if.clk iff this.req_ack_if.rst_n); // 等待复位释放
		
		forever
		begin
			// 等待响应
			while(!(this.req_ack_if.req & this.req_ack_if.ack))
			begin
				@(posedge this.req_ack_if.clk iff this.req_ack_if.rst_n);
			end
			
			// 创建req-ack事务
			this.req_ack_trans = new();
			this.req_ack_trans.req_payload = this.req_ack_if.req_payload;
			this.req_ack_trans.resp_payload = this.req_ack_if.resp_payload;
			
			// 传递req-ack事务
			this.in_analysis_port.write(this.req_ack_trans);
			
			// 打印req-ack事务
			// `uvm_info("ReqAckMonitor", $sformatf("ReqAckMonitor got transaction(i = %d)!", this.trans_i), UVM_LOW)
			// this.req_ack_trans.print();
			this.trans_i++;
			
			// 等待1clk
			@(posedge this.req_ack_if.clk iff this.req_ack_if.rst_n);
		end
	endtask
	
endclass
`endif

`ifdef ICBMon
/** 监测器:ICB **/
class ICBMonitor #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer addr_width = 32, // 地址位宽
	integer data_width = 32 // 数据位宽
)extends uvm_monitor;
	
	// ICB虚接口
	local virtual ICB #(.out_drive_t(out_drive_t), 
		.addr_width(addr_width), .data_width(data_width)).monitor icb_if;
	
	local int unsigned trans_i; // 事务id
	
	local ICBTrans #(.addr_width(addr_width), .data_width(data_width)) icb_cmd_trans; // ICB命令通道事务
	local ICBTrans #(.addr_width(addr_width), .data_width(data_width)) icb_cmd_trans_fifo[$]; // ICB命令通道事务fifo
	local ICBTrans #(.addr_width(addr_width), .data_width(data_width)) icb_trans; // ICB命令通道事务
	
	// 通信端口
	uvm_analysis_port #(ICBTrans #(.addr_width(addr_width), .data_width(data_width))) in_analysis_port;
	
	// 注册component
	`uvm_component_param_utils(ICBMonitor #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width)))
	
	function new(string name = "ICBMonitor", uvm_component parent = null);
		super.new(name, parent);
		
		this.trans_i = 0;
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual ICB #(.out_drive_t(out_drive_t), 
			.addr_width(addr_width), .data_width(data_width)).monitor)::
			get(this, "", "icb_if", this.icb_if))
		begin
			`uvm_fatal("ICBMonitor", "virtual interface must be set for icb_if!!!")
		end
		
		// 创建通信端口
		this.in_analysis_port = new("monitor_in_analysis_port", this);
		
		`uvm_info("ICBMonitor", "ICBMonitor built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		@(posedge this.icb_if.clk iff this.icb_if.rst_n); // 等待复位释放
		
		forever
		begin
			if(this.icb_if.cmd_valid & this.icb_if.cmd_ready) // 命令通道握手
			begin
				this.icb_cmd_trans = new();
				
				this.icb_cmd_trans.cmd_addr = this.icb_if.cmd_addr;
				this.icb_cmd_trans.cmd_read = this.icb_if.cmd_read;
				this.icb_cmd_trans.cmd_wdata = this.icb_if.cmd_wdata;
				this.icb_cmd_trans.cmd_wmask = this.icb_if.cmd_wmask;
				
				this.icb_cmd_trans_fifo.push_back(this.icb_cmd_trans);
			end
			
			if(this.icb_if.rsp_valid)
			begin
				if(this.icb_cmd_trans_fifo.size() == 0) // 响应通道在命令通道握手之前有效
				begin
					`uvm_error("ICBMonitor", "RSP vld before CMD!")
				end
				else if(this.icb_if.rsp_ready) // 响应通道握手且ICB命令通道事务fifo非空
				begin
					this.icb_trans = this.icb_cmd_trans_fifo.pop_front();
					
					this.icb_trans.rsp_rdata = this.icb_if.rsp_rdata;
					this.icb_trans.rsp_err = this.icb_if.rsp_err;
					
					// 传递ICB事务
					this.in_analysis_port.write(this.icb_trans);
					
					// 打印ICB事务
					// `uvm_info("ICBMonitor", $sformatf("ICBMonitor got transaction(i = %d)!", this.trans_i), UVM_LOW)
					// this.icb_trans.print();
					this.trans_i++;
				end
			end
			
			@(posedge this.icb_if.clk iff this.icb_if.rst_n);
		end
	endtask
	
endclass
`endif

`endif
