`timescale 1ns / 1ps

`ifndef __DRIVER_H

`define __DRIVER_H

`include "transactions.sv"

// `define BlkCtrlDriver
// `define AXIDriver
// `define APBDriver
`define AXISDriver
// `define AHBDriver
// `define ReqAckDriver
`define ICBDriver

/** 驱动器:块级控制主机 **/
`ifdef BlkCtrlDriver
class BlkCtrlMasterDriver #(
	real out_drive_t = 1 // 输出驱动延迟量
)extends uvm_driver #(BlkCtrlTrans);
	
	local virtual BlkCtrl #(.out_drive_t(out_drive_t)).master blk_ctrl_if; // 块级控制虚接口
	
	// 注册component
	`uvm_component_param_utils(BlkCtrlMasterDriver #(.out_drive_t(out_drive_t)))
	
	function new(string name = "BlkCtrlMasterDriver", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase); 
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual BlkCtrl #(.out_drive_t(out_drive_t)).master)::get(this, "", "blk_ctrl_if", this.blk_ctrl_if))
		begin
			`uvm_fatal("BlkCtrlMasterDriver", "virtual interface must be set for blk_ctrl_if!!!")
		end
		
		`uvm_info("BlkCtrlMasterDriver", "BlkCtrlMasterDriver built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		// 初始化块级控制接口
		this.blk_ctrl_if.cb_master.start <= 1'b0;
		this.blk_ctrl_if.cb_master.to_continue <= 1'b1;
		
		// 等待复位释放
		@(posedge this.blk_ctrl_if.clk iff this.blk_ctrl_if.rst_n);
		
		forever
		begin
            this.seq_item_port.get_next_item(this.req); // 获取下一事务
			// this.req.print();
            this.drive_item(this.req); // 驱动当前事务
            this.seq_item_port.item_done(); // 发送信号:本事务已完成
        end
	endtask
	
	local task drive_item(ref BlkCtrlTrans tr);
		// 等待启动功能模块
		repeat(tr.start_wait_period_n)
			@(posedge this.blk_ctrl_if.clk iff this.blk_ctrl_if.rst_n);
		
		this.blk_ctrl_if.cb_master.start <= 1'b1;
		
		@(posedge this.blk_ctrl_if.clk iff this.blk_ctrl_if.rst_n);
		
		this.blk_ctrl_if.cb_master.start <= 1'b0;
		
		// 等待功能模块完成
		do
		begin
			@(posedge this.blk_ctrl_if.clk iff this.blk_ctrl_if.rst_n);
		end
		while(!this.blk_ctrl_if.done);
	endtask
	
endclass
`endif

/** 驱动器:AXI主机 **/
`ifdef AXIDriver
class AXIMasterDriver #(
	real out_drive_t = 1, // 输出驱动延迟量
	integer addr_width = 32, // 地址位宽(1~64)
	integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
    integer bresp_width = 2, // 写响应信号位宽(0 | 2 | 3)
    integer rresp_width = 2 // 读响应信号位宽(0 | 2 | 3)
)extends uvm_driver #(AXITrans #(.addr_width(addr_width), .data_width(data_width), 
	.bresp_width(bresp_width), .rresp_width(rresp_width)));
	
	local virtual AXI #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)).master axi_if; // AXI虚接口
	
	// 事务fifo
	local AXITrans #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_ar_trans_fifo[$];
	local AXITrans #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_aw_trans_fifo[$];
	local AXITrans #(.addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_w_trans_fifo[$];
	
	// 配置
	local int unsigned max_trans_buffer_n = 12; // 最大的事务缓存深度
	
	// 注册component
	`uvm_component_param_utils_begin(AXIMasterDriver #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), .bresp_width(bresp_width), .rresp_width(rresp_width)))
		`uvm_field_int(max_trans_buffer_n, UVM_ALL_ON)
	`uvm_component_utils_end
	
	function new(string name = "AXIMasterDriver", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase); 
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual AXI #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), 
			.bresp_width(bresp_width), .rresp_width(rresp_width)).master)::get(this, "", "axi_if", this.axi_if))
		begin
			`uvm_fatal("AXIMasterDriver", "virtual interface must be set for axi_if!!!")
		end
		
		`uvm_info("AXIMasterDriver", 
			$sformatf("AXIMasterDriver built(max_trans_buffer_n = %d)!", this.max_trans_buffer_n), UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		// 等待复位释放
		@(posedge this.axi_if.clk iff this.axi_if.rst_n);
		
		fork
			drive_ar();
			drive_r();
			drive_aw();
			drive_w();
			drive_b();
			
			forever
			begin
				wait((this.axi_ar_trans_fifo.size() < this.max_trans_buffer_n) && 
					(this.axi_aw_trans_fifo.size() < this.max_trans_buffer_n));
				
				this.seq_item_port.get_next_item(this.req); // 获取下一事务
				// this.req.print();
				
				if(this.req.is_rd_trans)
				begin
					this.axi_ar_trans_fifo.push_back(this.req);
				end
				else
				begin
					this.axi_aw_trans_fifo.push_back(this.req);
					this.axi_w_trans_fifo.push_back(this.req);
				end
				
				this.seq_item_port.item_done(); // 发送信号:本事务已完成
			end
		join_none
	endtask
	
	local task drive_ar();
		// 初始化AXI总线的AR通道
		this.axi_if.cb_master.araddr <= {addr_width{1'bx}};
		this.axi_if.cb_master.arburst <= 2'bxx;
		this.axi_if.cb_master.arcache <= 4'bxxxx;
		this.axi_if.cb_master.arlen <= 8'dx;
		this.axi_if.cb_master.arlock <= 1'bx;
		this.axi_if.cb_master.arprot <= 3'bxxx;
		this.axi_if.cb_master.arsize <= 3'bxxx;
		this.axi_if.cb_master.arvalid <= 1'b0;
		
		forever
		begin
			automatic AXITrans #(.addr_width(addr_width), .data_width(data_width), 
				.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_trans;
			
			wait(this.axi_ar_trans_fifo.size() > 0);
			
			axi_trans = this.axi_ar_trans_fifo.pop_front();
			
			// 等待AR通道有效
			repeat(axi_trans.addr_wait_period_n)
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			// 给出有效数据
			this.axi_if.cb_master.araddr <= axi_trans.addr;
			this.axi_if.cb_master.arburst <= axi_trans.burst;
			this.axi_if.cb_master.arcache <= axi_trans.cache;
			this.axi_if.cb_master.arlen <= axi_trans.len;
			this.axi_if.cb_master.arlock <= axi_trans.lock;
			this.axi_if.cb_master.arprot <= axi_trans.prot;
			this.axi_if.cb_master.arsize <= axi_trans.size;
			this.axi_if.cb_master.arvalid <= 1'b1;
			
			// 等待AR通道握手完成
			do
			begin
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			end
			while(!(this.axi_if.arvalid && this.axi_if.arready));
			
			// 将AXI总线的AR通道恢复到无效状态
			this.axi_if.cb_master.araddr <= {addr_width{1'bx}};
			this.axi_if.cb_master.arburst <= 2'bxx;
			this.axi_if.cb_master.arcache <= 4'bxxxx;
			this.axi_if.cb_master.arlen <= 8'dx;
			this.axi_if.cb_master.arlock <= 1'bx;
			this.axi_if.cb_master.arprot <= 3'bxxx;
			this.axi_if.cb_master.arsize <= 3'bxxx;
			this.axi_if.cb_master.arvalid <= 1'b0;
		end
	endtask
	
	local task drive_r();
		// 初始化AXI总线的R通道
		this.axi_if.cb_master.rready <= 1'b0;
		
		forever
		begin
			automatic byte unsigned r_wait_period_n = $urandom_range(0, 2);
			
			// 等待R通道就绪
			repeat(r_wait_period_n)
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			// R通道就绪
			this.axi_if.cb_master.rready <= 1'b1;
			
			// 等待R通道握手完成
			do
			begin
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			end
			while(!(this.axi_if.rvalid && this.axi_if.rready));
			
			// 将AXI总线的R通道恢复到无效状态
			this.axi_if.cb_master.rready <= 1'b0;
		end
	endtask
	
	local task drive_aw();
		// 初始化AXI总线的AW通道
		this.axi_if.cb_master.awaddr <= {addr_width{1'bx}};
		this.axi_if.cb_master.awburst <= 2'bxx;
		this.axi_if.cb_master.awcache <= 4'bxxxx;
		this.axi_if.cb_master.awlen <= 8'dx;
		this.axi_if.cb_master.awlock <= 1'bx;
		this.axi_if.cb_master.awprot <= 3'bxxx;
		this.axi_if.cb_master.awsize <= 3'bxxx;
		this.axi_if.cb_master.awvalid <= 1'b0;
		
		forever
		begin
			automatic AXITrans #(.addr_width(addr_width), .data_width(data_width), 
				.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_trans;
			
			wait(this.axi_aw_trans_fifo.size() > 0);
			
			axi_trans = this.axi_aw_trans_fifo.pop_front();
			
			// 等待AR通道有效
			repeat(axi_trans.addr_wait_period_n)
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			// 给出有效数据
			this.axi_if.cb_master.awaddr <= axi_trans.addr;
			this.axi_if.cb_master.awburst <= axi_trans.burst;
			this.axi_if.cb_master.awcache <= axi_trans.cache;
			this.axi_if.cb_master.awlen <= axi_trans.len;
			this.axi_if.cb_master.awlock <= axi_trans.lock;
			this.axi_if.cb_master.awprot <= axi_trans.prot;
			this.axi_if.cb_master.awsize <= axi_trans.size;
			this.axi_if.cb_master.awvalid <= 1'b1;
			
			// 等待AW通道握手完成
			do
			begin
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			end
			while(!(this.axi_if.awvalid && this.axi_if.awready));
			
			// 将AXI总线的AW通道恢复到无效状态
			this.axi_if.cb_master.awaddr <= {addr_width{1'bx}};
			this.axi_if.cb_master.awburst <= 2'bxx;
			this.axi_if.cb_master.awcache <= 4'bxxxx;
			this.axi_if.cb_master.awlen <= 8'dx;
			this.axi_if.cb_master.awlock <= 1'bx;
			this.axi_if.cb_master.awprot <= 3'bxxx;
			this.axi_if.cb_master.awsize <= 3'bxxx;
			this.axi_if.cb_master.awvalid <= 1'b0;
		end
	endtask
	
	local task drive_w();
		// 初始化AXI总线的W通道
		this.axi_if.cb_master.wdata <= {data_width{1'bx}};
		this.axi_if.cb_master.wlast <= 1'bx;
		this.axi_if.cb_master.wstrb <= {(data_width/8){1'bx}};
		this.axi_if.cb_master.wvalid <= 1'b0;
		
		forever
		begin
			automatic AXITrans #(.addr_width(addr_width), .data_width(data_width), 
				.bresp_width(bresp_width), .rresp_width(rresp_width)) axi_trans;
			
			wait(this.axi_w_trans_fifo.size() > 0);
			
			axi_trans = this.axi_w_trans_fifo.pop_front();
			
			for(int i = 0;i < axi_trans.data_n;i++)
			begin
				// 等待W通道有效
				repeat(axi_trans.wdata_wait_period_n[i])
					@(posedge this.axi_if.clk iff this.axi_if.rst_n);
				
				// 给出有效数据
				this.axi_if.cb_master.wdata <= axi_trans.wdata[i];
				this.axi_if.cb_master.wlast <= axi_trans.wlast[i];
				this.axi_if.cb_master.wstrb <= axi_trans.wstrb[i];
				this.axi_if.cb_master.wvalid <= 1'b1;
				
				// 等待AW通道握手完成
				do
				begin
					@(posedge this.axi_if.clk iff this.axi_if.rst_n);
				end
				while(!(this.axi_if.wvalid && this.axi_if.wready));
				
				// 将AXI总线的W通道恢复到无效状态
				this.axi_if.cb_master.wdata <= {data_width{1'bx}};
				this.axi_if.cb_master.wlast <= 1'bx;
				this.axi_if.cb_master.wstrb <= {(data_width/8){1'bx}};
				this.axi_if.cb_master.wvalid <= 1'b0;
			end
		end
	endtask
	
	local task drive_b();
		// 初始化AXI总线的B通道
		this.axi_if.cb_master.bready <= 1'b0;
		
		forever
		begin
			automatic byte unsigned b_wait_period_n = $urandom_range(0, 15);
			
			// 等待R通道就绪
			repeat(b_wait_period_n)
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			// B通道就绪
			this.axi_if.cb_master.bready <= 1'b1;
			
			// 等待R通道握手完成
			do
			begin
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			end
			while(!(this.axi_if.bvalid && this.axi_if.bready));
			
			// 将AXI总线的B通道恢复到无效状态
			this.axi_if.cb_master.bready <= 1'b0;
		end
	endtask
	
endclass
`endif

/** 驱动器:AXI从机 **/
`ifdef AXIDriver
class AXISlaveDriver #(
	real out_drive_t = 1, // 输出驱动延迟量
	integer addr_width = 32, // 地址位宽(1~64)
	integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
    integer bresp_width = 2, // 写响应信号位宽(0 | 2 | 3)
    integer rresp_width = 2 // 读响应信号位宽(0 | 2 | 3)
)extends uvm_driver #(AXITrans #(.addr_width(addr_width), .data_width(data_width), 
	.bresp_width(bresp_width), .rresp_width(rresp_width)));
	
	local virtual AXI #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), 
		.bresp_width(bresp_width), .rresp_width(rresp_width)).slave axi_if; // AXI虚接口
	
	local int unsigned rd_trans_to_resp_n; // 可响应的读事务个数
	local int unsigned wt_trans_to_resp_n_at_aw; // 可响应的写事务个数(保证AW在先)
	local int unsigned wt_trans_to_resp_n_at_w; // 可响应的写事务个数(保证W在先)
	
	// 注册component
	`uvm_component_param_utils(AXISlaveDriver #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), .bresp_width(bresp_width), .rresp_width(rresp_width)))
	
	function new(string name = "AXISlaveDriver", uvm_component parent = null);
		super.new(name, parent);
		
		this.rd_trans_to_resp_n = 0;
		this.wt_trans_to_resp_n_at_aw = 0;
		this.wt_trans_to_resp_n_at_w = 0;
	endfunction
	
	virtual function void build_phase(uvm_phase phase); 
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual AXI #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width), 
			.bresp_width(bresp_width), .rresp_width(rresp_width)).slave)::get(this, "", "axi_if", this.axi_if))
		begin
			`uvm_fatal("AXISlaveDriver", "virtual interface must be set for axi_if!!!")
		end
		
		`uvm_info("AXISlaveDriver", "AXISlaveDriver built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		// 初始化AXI总线
		this.axi_if.cb_slave.arready <= 1'b0;
		this.axi_if.cb_slave.awready <= 1'b0;
		this.axi_if.cb_slave.bresp <= {bresp_width{1'bx}};
		this.axi_if.cb_slave.bvalid <= 1'b0;
		this.axi_if.cb_slave.rdata <= {data_width{1'bx}};
		this.axi_if.cb_slave.rlast <= 1'bx;
		this.axi_if.cb_slave.rresp <= {rresp_width{1'bx}};
		this.axi_if.cb_slave.rvalid <= 1'b0;
		this.axi_if.cb_slave.wready <= 1'b0;
		
		// 等待复位释放
		@(posedge this.axi_if.clk iff this.axi_if.rst_n);
		
		fork
			this.drive_ar_chn(); // 驱动AR通道
			this.drive_aw_chn(); // 驱动AW通道
			this.drive_r_chn(); // 驱动R通道
			this.drive_w_chn(); // 驱动W通道
			this.drive_b_chn(); // 驱动B通道
		join_none
	endtask
	
	local task drive_ar_chn();
		forever
		begin
			automatic byte unsigned addr_wait_period_n = $urandom_range(0, 25);
			
			repeat(addr_wait_period_n)
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			this.axi_if.cb_slave.arready <= 1'b1;
			
			// 等待握手完成
			do
			begin
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			end
			while(!(this.axi_if.arvalid && this.axi_if.arready));
			
			this.rd_trans_to_resp_n++;
			
			this.axi_if.cb_slave.arready <= 1'b0;
		end
	endtask
	
	local task drive_aw_chn();
		forever
		begin
			automatic byte unsigned addr_wait_period_n = $urandom_range(0, 25);
			
			repeat(addr_wait_period_n)
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			this.axi_if.cb_slave.awready <= 1'b1;
			
			// 等待握手完成
			do
			begin
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			end
			while(!(this.axi_if.awvalid && this.axi_if.awready));
			
			this.wt_trans_to_resp_n_at_aw++;
			
			this.axi_if.cb_slave.awready <= 1'b0;
		end
	endtask
	
	local task drive_w_chn();
		forever
		begin
			automatic byte unsigned wdata_wait_period_n = $urandom_range(0, 2);
			
			repeat(wdata_wait_period_n)
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			this.axi_if.cb_slave.wready <= 1'b1;
			
			// 等待握手完成
			do
			begin
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			end
			while(!(this.axi_if.wvalid && this.axi_if.wready));
			
			if(this.axi_if.wlast)
				this.wt_trans_to_resp_n_at_w++;
			
			this.axi_if.cb_slave.wready <= 1'b0;
		end
	endtask
	
	local task drive_b_chn();
		forever
		begin
			automatic byte unsigned bresp_wait_period_n = $urandom_range(0, 8);
			
			// 等待一个可响应的写事务
			wait((this.wt_trans_to_resp_n_at_aw > 0) && (this.wt_trans_to_resp_n_at_w > 0));
			this.wt_trans_to_resp_n_at_aw--;
			this.wt_trans_to_resp_n_at_w--;
			
			repeat(bresp_wait_period_n)
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			
			this.axi_if.cb_slave.bresp <= 2'b00;
			this.axi_if.cb_slave.bvalid <= 1'b1;
			
			// 等待握手完成
			do
			begin
				@(posedge this.axi_if.clk iff this.axi_if.rst_n);
			end
			while(!(this.axi_if.bvalid && this.axi_if.bready));
			
			this.axi_if.cb_slave.bresp <= {bresp_width{1'bx}};
			this.axi_if.cb_slave.bvalid <= 1'b0;
		end
	endtask
	
	local task drive_r_chn();
		forever
		begin
			// 等待一个可响应的读事务
			wait(this.rd_trans_to_resp_n > 0);
			this.rd_trans_to_resp_n--;
			
			this.seq_item_port.get_next_item(this.req); // 获取下一个AXI读数据事务
			// this.req.print();
			
			for(int unsigned i = 0;i < this.req.rdata.size();i++)
			begin
				// 等待数据有效
				repeat(this.req.rdata_wait_period_n[i])
					@(posedge this.axi_if.clk iff this.axi_if.rst_n);
				
				// 给出有效数据
				this.axi_if.cb_slave.rdata <= this.req.rdata[i];
				this.axi_if.cb_slave.rlast <= this.req.rlast[i];
				this.axi_if.cb_slave.rresp <= this.req.rresp[i];
				this.axi_if.cb_slave.rvalid <= 1'b1;
				
				// 等待握手完成
				do
				begin
					@(posedge this.axi_if.clk iff this.axi_if.rst_n);
				end
				while(!(this.axi_if.rvalid && this.axi_if.rready));
				
				// 总线恢复到无效状态
				this.axi_if.cb_slave.rdata <= {data_width{1'bx}};
				this.axi_if.cb_slave.rlast <= 1'bx;
				this.axi_if.cb_slave.rresp <= {rresp_width{1'bx}};
				this.axi_if.cb_slave.rvalid <= 1'b0;
			end
			
			this.seq_item_port.item_done(); // 发送信号:本事务已完成
		end
	endtask
	
endclass
`endif

`ifdef APBDriver
/** 驱动器:APB主机 **/
class APBMasterDriver #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer addr_width = 32, // 地址位宽(1~32)
    integer data_width = 32 // 数据位宽(8 | 16 | 32)
)extends uvm_driver #(APBTrans #(.addr_width(addr_width), .data_width(data_width)));
	
	local virtual APB #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width)).master apb_if; // APB虚接口
	
	// 注册component
	`uvm_component_param_utils(APBMasterDriver #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width)))
	
	function new(string name = "APBMasterDriver", uvm_component parent = null);
		super.new(name, parent); 
	endfunction
	
	virtual function void build_phase(uvm_phase phase); 
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual APB #(.out_drive_t(out_drive_t), 
			.addr_width(addr_width), .data_width(data_width)).master)::get(this, "", "apb_if", this.apb_if))
		begin
			`uvm_fatal("APBMasterDriver", "virtual interface must be set for apb_if!!!")
		end
		
		`uvm_info("APBMasterDriver", "APBMasterDriver built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
	
		// 初始化APB总线
		this.apb_if.cb_master.paddr <= {addr_width{1'bx}};
		this.apb_if.cb_master.pselx <= 1'b0;
		this.apb_if.cb_master.penable <= 1'b0;
		this.apb_if.cb_master.pwrite <= 1'bx;
		this.apb_if.cb_master.pwdata <= {data_width{1'bx}};
		this.apb_if.cb_master.pstrb <= {(data_width/8){1'bx}};
		
		// 等待复位释放
		@(posedge this.apb_if.clk iff this.apb_if.rst_n);
		
		forever
		begin
            this.seq_item_port.get_next_item(this.req); // 获取下一事务
			// this.req.print();
            this.drive_item(this.req); // 驱动当前事务
            this.seq_item_port.item_done(); // 发送信号:本事务已完成
        end
	endtask
	
	local task drive_item(ref APBTrans #(.addr_width(addr_width), .data_width(data_width)) tr);
		@(posedge this.apb_if.clk iff this.apb_if.rst_n);
        
		// APB传输建立(setup)阶段
		this.apb_if.cb_master.paddr <= tr.addr;
		this.apb_if.cb_master.pselx <= 1'b1;
		this.apb_if.cb_master.penable <= 1'b0;
		this.apb_if.cb_master.pwrite <= tr.write;
		this.apb_if.cb_master.pwdata <= tr.write ? tr.wdata:{data_width{1'bx}};
		this.apb_if.cb_master.pstrb <= tr.write ? tr.wstrb:{(data_width/8){1'bx}};
		
		@(posedge this.apb_if.clk iff this.apb_if.rst_n);
		
		// APB传输数据(data)阶段
		this.apb_if.cb_master.penable <= 1'b1;
		
		@(posedge this.apb_if.clk iff this.apb_if.rst_n);
		
		// 等待APB传输完成(pready有效)
		while(!this.apb_if.pready)
			@(posedge this.apb_if.clk iff this.apb_if.rst_n);
		
		// APB传输完成
		this.apb_if.cb_master.paddr <= {addr_width{1'bx}};
		this.apb_if.cb_master.pselx <= 1'b0;
		this.apb_if.cb_master.penable <= 1'b0;
		this.apb_if.cb_master.pwrite <= 1'bx;
		this.apb_if.cb_master.pwdata <= {data_width{1'bx}};
		this.apb_if.cb_master.pstrb <= {(data_width/8){1'bx}};
	endtask
	
endclass

/** 驱动器:APB从机 **/
class APBSlaveDriver #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer addr_width = 32, // 地址位宽(1~32)
    integer data_width = 32 // 数据位宽(8 | 16 | 32)
)extends uvm_driver #(APBTrans #(.addr_width(addr_width), .data_width(data_width)));
	
	local virtual APB #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width)).slave apb_if; // APB虚接口
	
	// 注册component
	`uvm_component_param_utils(APBSlaveDriver #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width)))
	
	function new(string name = "APBSlaveDriver", uvm_component parent = null);
		super.new(name, parent); 
	endfunction
	
	virtual function void build_phase(uvm_phase phase); 
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual APB #(.out_drive_t(out_drive_t), 
			.addr_width(addr_width), .data_width(data_width)).slave)::get(this, "", "apb_if", this.apb_if))
		begin
			`uvm_fatal("APBSlaveDriver", "virtual interface must be set for apb_if!!!")
		end
		
		`uvm_info("APBSlaveDriver", "APBSlaveDriver built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
	
		// 初始化APB总线
		this.apb_if.cb_slave.pready <= 1'b0;
		this.apb_if.cb_slave.prdata <= {data_width{1'bx}};
		this.apb_if.cb_slave.pslverr <= 1'bx;
		
		// 等待复位释放
		@(posedge this.apb_if.clk iff this.apb_if.rst_n);
		
		forever
		begin
            this.seq_item_port.get_next_item(this.req); // 获取下一事务
			// this.req.print();
            this.drive_item(this.req); // 驱动当前事务
            this.seq_item_port.item_done(); // 发送信号:本事务已完成
        end
	endtask
	
	local task drive_item(ref APBTrans #(.addr_width(addr_width), .data_width(data_width)) tr);
		// 等待传输开始
		do
		begin
			@(posedge this.apb_if.clk iff this.apb_if.rst_n);
		end
		while(!(this.apb_if.pselx & this.apb_if.penable));
		
		// 等待传输完成
		repeat(tr.wait_period_n)
			@(posedge this.apb_if.clk iff this.apb_if.rst_n);
		
		// 发送传输完成信号
		this.apb_if.cb_slave.pready <= 1'b1;
		this.apb_if.cb_slave.prdata <= tr.rdata;
		this.apb_if.cb_slave.pslverr <= tr.slverr;
		
		@(posedge this.apb_if.clk iff this.apb_if.rst_n);
		
		// 总线恢复到无效状态
		this.apb_if.cb_slave.pready <= 1'b0;
		this.apb_if.cb_slave.prdata <= {data_width{1'bx}};
		this.apb_if.cb_slave.pslverr <= 1'bx;
	endtask
	
endclass
`endif

`ifdef AXISDriver
/** 驱动器:AXIS主机 **/
class AXISMasterDriver #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer data_width = 32, // 数据位宽(必须能被8整除)
    integer user_width = 0 // 用户数据位宽
)extends uvm_driver #(AXISTrans #(.data_width(data_width), .user_width(user_width)));
	
	local virtual AXIS #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)).master axis_if; // AXIS虚接口
	
	// 注册component
	`uvm_component_param_utils(AXISMasterDriver #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)))
	
	function new(string name = "AXISMasterDriver", uvm_component parent = null);
		super.new(name, parent); 
	endfunction
	
	virtual function void build_phase(uvm_phase phase); 
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual AXIS #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)).master)::
			get(this, "", "axis_if", this.axis_if))
		begin
			`uvm_fatal("AXISMasterDriver", "virtual interface must be set for axis_if!!!")
		end
		
		`uvm_info("AXISMasterDriver", "AXISMasterDriver built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		// 初始化总线为无效状态
		this.axis_if.cb_master.data <= {data_width{1'bx}};
		this.axis_if.cb_master.keep <= {(data_width/8){1'bx}};
		this.axis_if.cb_master.strb <= {(data_width/8){1'bx}};
		this.axis_if.cb_master.last <= 1'bx;
		// this.axis_if.cb_master.user <= {user_width{1'bx}};
		this.axis_if.cb_master.valid <= 1'b0;
		
		// 等待复位释放
		@(posedge this.axis_if.clk iff this.axis_if.rst_n);
		
		forever
		begin
            this.seq_item_port.get_next_item(this.req); // 获取下一事务
			// `uvm_info("AXISMasterDriver", "AXISMasterDriver got transaction!", UVM_LOW)
			// this.req.print();
            this.drive_item(this.req); // 驱动当前事务
            this.seq_item_port.item_done(); // 发送信号:本事务已完成
        end
	endtask
	
	local task drive_item(ref AXISTrans #(.data_width(data_width), .user_width(user_width)) tr);
		for(int unsigned i = 0;i < tr.data_n;i++)
		begin
			// 等待数据有效
			repeat(tr.wait_period_n[i])
				@(posedge this.axis_if.clk iff this.axis_if.rst_n);
			
			// 给出有效数据
			this.axis_if.cb_master.data <= tr.data[i];
			this.axis_if.cb_master.keep <= tr.keep[i];
			this.axis_if.cb_master.strb <= tr.strb[i];
			this.axis_if.cb_master.last <= tr.last[i];
			this.axis_if.cb_master.user <= tr.user[i];
			this.axis_if.cb_master.valid <= 1'b1;
			
			// 等待握手完成
			do
			begin
				@(posedge this.axis_if.clk iff this.axis_if.rst_n);
			end
			while(!(this.axis_if.valid && this.axis_if.ready));
			
			// 总线恢复到无效状态
			this.axis_if.cb_master.data <= {data_width{1'bx}};
			this.axis_if.cb_master.keep <= {(data_width/8){1'bx}};
			this.axis_if.cb_master.strb <= {(data_width/8){1'bx}};
			this.axis_if.cb_master.last <= 1'bx;
			// this.axis_if.cb_master.user <= {user_width{1'bx}};
			this.axis_if.cb_master.valid <= 1'b0;
		end
	endtask
	
endclass

/** 驱动器:AXIS从机 **/
class AXISSlaveDriver #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer data_width = 32, // 数据位宽(必须能被8整除)
    integer user_width = 0 // 用户数据位宽
)extends uvm_driver;
	
	local virtual AXIS #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)).slave axis_if; // AXIS虚接口
	
	// 注册component
	`uvm_component_param_utils(AXISSlaveDriver #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)))
	
	function new(string name = "AXISSlaveDriver", uvm_component parent = null);
		super.new(name, parent); 
	endfunction
	
	virtual function void build_phase(uvm_phase phase); 
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual AXIS #(.out_drive_t(out_drive_t), .data_width(data_width), .user_width(user_width)).slave)::
			get(this, "", "axis_if", this.axis_if))
		begin
			`uvm_fatal("AXISSlaveDriver", "virtual interface must be set for axis_if!!!")
		end
		
		`uvm_info("AXISSlaveDriver", "AXISSlaveDriver built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		// 初始化总线为无效状态
		this.axis_if.cb_slave.ready <= 1'b0;
		
		// 等待复位释放
		@(posedge this.axis_if.clk iff this.axis_if.rst_n);
		
		forever
		begin
            automatic int unsigned s_axis_wait_n = $urandom_range(0, 2);
			// automatic int unsigned s_axis_wait_n = 0;
			
			repeat(s_axis_wait_n)
				@(posedge this.axis_if.clk iff this.axis_if.rst_n);
			
			this.axis_if.cb_slave.ready <= 1'b1;
			
			// 等待AXIS握手
			do
			begin
				@(posedge this.axis_if.clk iff this.axis_if.rst_n);
			end
			while(!(this.axis_if.valid & this.axis_if.ready));
			
			// 总线恢复到无效状态
			this.axis_if.cb_slave.ready <= 1'b0;
        end
	endtask
	
endclass
`endif

`ifdef AHBDriver
/** 驱动器:AHB主机 **/
class AHBMasterDriver #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer slave_n = 1, // 从机个数
    integer addr_width = 32, // 地址位宽(10~64)
    integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
    integer burst_width = 3, // 突发类型位宽(0~3)
    integer prot_width = 4, // 保护类型位宽(0 | 4 | 7)
    integer master_width = 1 // 主机标识位宽(0~8)
)extends uvm_driver #(AHBTrans #(.addr_width(addr_width), .data_width(data_width), .burst_width(burst_width), 
	.prot_width(prot_width), .master_width(master_width)));
	
	// 常量
	// 传输类型
	localparam HTRANS_IDLE = 2'b00;
	localparam HTRANS_BUSY = 2'b01;
	localparam HTRANS_NONSEQ = 2'b10;
	localparam HTRANS_SEQ = 2'b11;
	// 突发类型
	localparam HBURST_SINGLE = 3'b000;
	localparam HBURST_INCR = 3'b001;
	localparam HBURST_WRAP4 = 3'b010;
	localparam HBURST_INCR4 = 3'b011;
	localparam HBURST_WRAP8 = 3'b100;
	localparam HBURST_INCR8 = 3'b101;
	localparam HBURST_WRAP16 = 3'b110;
	localparam HBURST_INCR16 = 3'b111;
	
	// AHB虚接口
	local virtual AHB #(.out_drive_t(out_drive_t), .slave_n(slave_n), .addr_width(addr_width), .data_width(data_width), 
		.burst_width(burst_width), .prot_width(prot_width), .master_width(master_width)).master ahb_if;
	
	// 注册component
	`uvm_component_param_utils(AHBMasterDriver #(.out_drive_t(out_drive_t), .slave_n(slave_n), .addr_width(addr_width), .data_width(data_width), .burst_width(burst_width), .prot_width(prot_width), .master_width(master_width)))
	
	function new(string name = "AHBMasterDriver", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase); 
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual AHB #(.out_drive_t(out_drive_t), .slave_n(slave_n), .addr_width(addr_width), 
			.data_width(data_width), .burst_width(burst_width), .prot_width(prot_width), .master_width(master_width)).master)::
			get(this, "", "ahb_if", this.ahb_if))
		begin
			`uvm_fatal("AHBMasterDriver", "virtual interface must be set for ahb_if!!!")
		end
		
		`uvm_info("AHBMasterDriver", "AHBMasterDriver built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		// 初始化总线为无效状态
		this.rst_bus();
		
		// 等待复位释放
		@(posedge this.ahb_if.clk iff this.ahb_if.rst_n);
		
		fork
			forever
			begin
				this.seq_item_port.get_next_item(this.req); // 获取下一事务
				// `uvm_info("AHBMasterDriver", "AHBMasterDriver got transaction!", UVM_LOW)
				// this.req.print();
				this.drive_item(this.req); // 驱动当前事务
				this.seq_item_port.item_done(); // 发送信号:本事务已完成
			end
		join_none
	endtask
	
	local task drive_item(ref AHBTrans #(.addr_width(addr_width), .data_width(data_width), 
		.burst_width(burst_width), .prot_width(prot_width), .master_width(master_width)) tr);
		for(int i = 0;i < tr.wait_period_n.size();i++)
		begin
			// 启动一次传输
			if((tr.hburst == HBURST_SINGLE) || (tr.hburst == HBURST_INCR) || 
				(tr.hburst == HBURST_INCR4) || (tr.hburst == HBURST_INCR8) || 
				(tr.hburst == HBURST_INCR16))
			begin // SINGLE或INCR传输
				this.ahb_if.cb_master.haddr <= tr.haddr + i * (2 ** tr.hsize);
			end
			else // WRAP传输
			begin
				automatic bit[addr_width-1:0] addr = tr.haddr + i * (2 ** tr.hsize);
				automatic int wrap_size = 2 ** tr.hsize;
				automatic bit[addr_width-1:0] wrap_mask;
				
				if(tr.hburst == HBURST_WRAP4)
					wrap_size *= 4;
				else if(tr.hburst == HBURST_WRAP8)
					wrap_size *= 8;
				else
					wrap_size *= 16;
				
				wrap_mask = wrap_size - 1;
				addr = (addr & wrap_mask) | (tr.haddr & (~wrap_mask));
				
				this.ahb_if.cb_master.haddr <= addr;
			end
			this.ahb_if.cb_master.hburst <= tr.hburst;
			this.ahb_if.cb_master.hmastllock <= tr.hmastllock;
			this.ahb_if.cb_master.hprot <= tr.hprot;
			this.ahb_if.cb_master.hsize <= tr.hsize;
			this.ahb_if.cb_master.hnonsec <= tr.hnonsec;
			this.ahb_if.cb_master.hexcl <= tr.hexcl;
			this.ahb_if.cb_master.hmaster <= tr.hmaster;
			this.ahb_if.cb_master.htrans <= (i == 0) ? HTRANS_NONSEQ:HTRANS_SEQ;
			this.ahb_if.cb_master.hwrite <= tr.hwrite;
			
			@(posedge this.ahb_if.clk iff this.ahb_if.rst_n);
			
			// 等待传输开始
			while(!this.ahb_if.hready)
			begin
				@(posedge this.ahb_if.clk iff this.ahb_if.rst_n);
			end
			
			if(tr.hwrite)
			begin
				this.ahb_if.cb_master.hwdata <= tr.hwdata[i];
				this.ahb_if.cb_master.hwstrb <= tr.hwstrb[i];
			end
			
			// 传输后等待
			repeat(tr.wait_period_n[i])
			begin
				this.ahb_if.cb_master.htrans <= (i == (tr.wait_period_n.size() - 1)) ? HTRANS_IDLE:HTRANS_BUSY;
				
				@(posedge this.ahb_if.clk iff this.ahb_if.rst_n);
			end
			
			this.rst_bus();
			
			// 在总线上保留写数据
			if(tr.hwrite)
			begin
				this.ahb_if.cb_master.hwdata <= tr.hwdata[i];
				this.ahb_if.cb_master.hwstrb <= tr.hwstrb[i];
			end
		end
	endtask
	
	local task rst_bus();
		this.ahb_if.cb_master.haddr <= {addr_width{1'bx}};
		this.ahb_if.cb_master.hburst <= {burst_width{1'bx}};
		this.ahb_if.cb_master.hmastllock <= 1'bx;
		this.ahb_if.cb_master.hprot <= {prot_width{1'bx}};
		this.ahb_if.cb_master.hsize <= 3'bxxx;
		this.ahb_if.cb_master.hnonsec <= 1'bx;
		this.ahb_if.cb_master.hexcl <= 1'bx;
		this.ahb_if.cb_master.hmaster <= {master_width{1'bx}};
		this.ahb_if.cb_master.htrans <= HTRANS_IDLE;
		this.ahb_if.cb_master.hwrite <= 1'bx;
		
		this.ahb_if.cb_master.hwdata <= {data_width{1'bx}};
		this.ahb_if.cb_master.hwstrb <= {(data_width/8){1'bx}};
	endtask
	
endclass
`endif

`ifdef ReqAckDriver
/** 驱动器:req-ack主机 **/
class ReqAckMasterDriver #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer req_payload_width = 32, // 请求数据位宽
	integer resp_payload_width = 32 // 响应数据位宽
)extends uvm_driver #(ReqAckTrans #(.req_payload_width(req_payload_width), .resp_payload_width(resp_payload_width)));
	
	// req-ack虚接口
	local virtual ReqAck #(.out_drive_t(out_drive_t), 
		.req_payload_width(req_payload_width), .resp_payload_width(resp_payload_width)).master req_ack_if;
	
	// 注册component
	`uvm_component_param_utils(ReqAckMasterDriver #(.out_drive_t(out_drive_t), .req_payload_width(req_payload_width), .resp_payload_width(resp_payload_width)))
	
	function new(string name = "ReqAckMasterDriver", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase); 
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual ReqAck #(.out_drive_t(out_drive_t), 
			.req_payload_width(req_payload_width), .resp_payload_width(resp_payload_width)).master)::
			get(this, "", "req_ack_if", this.req_ack_if))
		begin
			`uvm_fatal("ReqAckMasterDriver", "virtual interface must be set for req_ack_if!!!")
		end
		
		`uvm_info("ReqAckMasterDriver", "ReqAckMasterDriver built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		// 初始化总线为无效状态
		this.rst_bus();
		
		// 等待复位释放
		@(posedge this.req_ack_if.clk iff this.req_ack_if.rst_n);
		
		fork
			forever
			begin
				this.seq_item_port.get_next_item(this.req); // 获取下一事务
				// `uvm_info("ReqAckMasterDriver", "ReqAckMasterDriver got transaction!", UVM_LOW)
				// this.req.print();
				this.drive_item(this.req); // 驱动当前事务
				this.seq_item_port.item_done(); // 发送信号:本事务已完成
			end
		join_none
	endtask
	
	local task drive_item(ref ReqAckTrans #(.req_payload_width(req_payload_width), 
		.resp_payload_width(resp_payload_width)) tr);
		// 请求有效前等待
		repeat(tr.req_wait_period_n)
		begin
			@(posedge this.req_ack_if.clk iff this.req_ack_if.rst_n);
		end
		
		// 请求有效
		this.req_ack_if.cb_master.req <= 1'b1;
		this.req_ack_if.cb_master.req_payload <= tr.req_payload;
		
		// 等待响应有效
		do
		begin
			@(posedge this.req_ack_if.clk iff this.req_ack_if.rst_n);
		end
		while(!this.req_ack_if.ack);
		
		// 复位总线
		this.rst_bus();
	endtask
	
	local task rst_bus();
		this.req_ack_if.cb_master.req <= 1'b0;
		this.req_ack_if.cb_master.req_payload <= {req_payload_width{1'bx}};
	endtask
	
endclass
`endif

`ifdef ICBDriver
/** 驱动器:ICB从机 **/
class ICBSlaveDriver #(
	real out_drive_t = 1, // 输出驱动延迟量
    integer addr_width = 32, // 地址位宽
	integer data_width = 32 // 数据位宽
)extends uvm_driver #(ICBTrans #(.addr_width(addr_width), .data_width(data_width)));
	
	// ICB虚接口
	local virtual ICB #(.out_drive_t(out_drive_t), 
		.addr_width(addr_width), .data_width(data_width)).slave icb_if;
	
	// ICB事务
	local ICBTrans #(.addr_width(addr_width), .data_width(data_width)) icb_new_trans;
	local ICBTrans #(.addr_width(addr_width), .data_width(data_width)) icb_cmd_fifo[$];
	local ICBTrans #(.addr_width(addr_width), .data_width(data_width)) icb_rsp_fifo[$];
	
	// 注册component
	`uvm_component_param_utils(ICBSlaveDriver #(.out_drive_t(out_drive_t), .addr_width(addr_width), .data_width(data_width)))
	
	function new(string name = "ICBSlaveDriver", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase); 
		super.build_phase(phase);
		
		// 获取虚接口
		if(!uvm_config_db #(virtual ICB #(.out_drive_t(out_drive_t), 
			.addr_width(addr_width), .data_width(data_width)).slave)::
			get(this, "", "icb_if", this.icb_if))
		begin
			`uvm_fatal("ICBSlaveDriver", "virtual interface must be set for icb_if!!!")
		end
		
		`uvm_info("ICBSlaveDriver", "ICBSlaveDriver built!", UVM_LOW)
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		// 初始化总线为无效状态
		this.icb_if.cb_slave.cmd_ready <= 1'b0;
		this.icb_if.cb_slave.rsp_rdata <= {data_width{1'bx}};
		this.icb_if.cb_slave.rsp_err <= 1'bx;
		this.icb_if.cb_slave.rsp_valid <= 1'b0;
		
		// 等待复位释放
		@(posedge this.icb_if.clk iff this.icb_if.rst_n);
		
		fork
			this.get_trans();
			this.drive_cmd_chn();
			this.drive_rsp_chn();
		join_none
	endtask
	
	local task get_trans();
		forever
		begin
			wait((this.icb_cmd_fifo.size() <= 3) && (this.icb_rsp_fifo.size() <= 3));
			
			this.seq_item_port.get_next_item(this.req); // 获取下一事务
			// `uvm_info("ICBSlaveDriver", "ICBSlaveDriver got transaction!", UVM_LOW)
			// this.req.print();
			
			// 将ICB事务拆分装入命令和响应通道事务fifo
			this.icb_new_trans = new();
			this.icb_new_trans.cmd_wait_period_n = this.req.cmd_wait_period_n;
			this.icb_cmd_fifo.push_back(this.icb_new_trans);
			this.icb_new_trans = new();
			this.icb_new_trans.rsp_rdata = this.req.rsp_rdata;
			this.icb_new_trans.rsp_err = this.req.rsp_err;
			this.icb_new_trans.rsp_wait_period_n = this.req.rsp_wait_period_n;
			this.icb_rsp_fifo.push_back(this.icb_new_trans);
			
			this.seq_item_port.item_done(); // 发送信号:本事务已完成
		end
	endtask
	
	local task drive_cmd_chn();
		forever
		begin
			automatic ICBTrans #(.addr_width(addr_width), .data_width(data_width)) icb_trans;
			
			wait(this.icb_cmd_fifo.size() > 0);
			
			icb_trans = this.icb_cmd_fifo.pop_front();
			
			// ready前等待
			repeat(icb_trans.cmd_wait_period_n)
			begin
				@(posedge this.icb_if.clk iff this.icb_if.rst_n);
			end
			
			// 命令通道ready
			this.icb_if.cb_slave.cmd_ready <= 1'b1;
			
			// 等待命令通道握手
			do
			begin
				@(posedge this.icb_if.clk iff this.icb_if.rst_n);
			end
			while(!(this.icb_if.cmd_valid & this.icb_if.cmd_ready));
			
			// 复位命令通道
			this.icb_if.cb_slave.cmd_ready <= 1'b0;
		end
	endtask
	
	local task drive_rsp_chn();
		forever
		begin
			automatic ICBTrans #(.addr_width(addr_width), .data_width(data_width)) icb_trans;
			
			wait(this.icb_rsp_fifo.size() > 0);
			
			icb_trans = this.icb_rsp_fifo.pop_front();
			
			// valid前等待
			repeat(icb_trans.rsp_wait_period_n)
			begin
				@(posedge this.icb_if.clk iff this.icb_if.rst_n);
			end
			
			// 响应通道valid
			this.icb_if.cb_slave.rsp_rdata <= icb_trans.rsp_rdata;
			this.icb_if.cb_slave.rsp_err <= icb_trans.rsp_err;
			this.icb_if.cb_slave.rsp_valid <= 1'b1;
			
			// 等待响应通道握手
			do
			begin
				@(posedge this.icb_if.clk iff this.icb_if.rst_n);
			end
			while(!(this.icb_if.rsp_valid & this.icb_if.rsp_ready));
			
			// 复位响应通道
			this.icb_if.cb_slave.rsp_rdata <= {data_width{1'bx}};
			this.icb_if.cb_slave.rsp_err <= 1'bx;
			this.icb_if.cb_slave.rsp_valid <= 1'b0;
		end
	endtask
	
endclass
`endif

`endif
