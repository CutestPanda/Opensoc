`timescale 1ns / 1ps

`ifndef __TRANSACTION_H

`define __TRANSACTION_H

`include "uvm_macros.svh"

import uvm_pkg::*;

/** 事务:块级控制 **/
class BlkCtrlTrans extends uvm_sequence_item;
	
	rand int unsigned start_wait_period_n; // 启动功能模块的等待周期数
	
	// 域自动化
	`uvm_object_utils_begin(BlkCtrlTrans)
		`uvm_field_int(start_wait_period_n, UVM_ALL_ON)
	`uvm_object_utils_end
	
	function new(string name = "BlkCtrlTrans");
		super.new();
	endfunction
	
endclass

/** 事务:AXI **/
class AXITrans #(
	integer addr_width = 32, // 地址位宽(1~64)
	integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
    integer bresp_width = 2, // 写响应信号位宽(0 | 2 | 3)
    integer rresp_width = 2 // 读响应信号位宽(0 | 2 | 3)
)extends uvm_sequence_item;
	
	// 是否读传输
	rand bit is_rd_trans;
	
	// 数据个数
	rand int unsigned data_n;
	
	// 地址通道
	rand bit[addr_width-1:0] addr;
	rand bit[1:0] burst;
	rand bit[3:0] cache;
	rand bit[7:0] len;
	rand bit lock;
	rand bit[2:0] prot;
    rand bit[2:0] size;
    rand byte unsigned addr_wait_period_n; // 地址通道的等待周期数
	
	// 写数据通道
	rand bit[data_width-1:0] wdata[$];
    rand bit wlast[$];
    rand bit[data_width/8-1:0] wstrb[$];
	rand byte unsigned wdata_wait_period_n[]; // 写数据通道的等待周期数
	
	// 写响应通道
	rand bit[bresp_width-1:0] bresp;
	
	// 读数据通道
	rand bit[data_width-1:0] rdata[$];
    rand bit rlast[$];
    rand bit[rresp_width-1:0] rresp[$];
	rand byte unsigned rdata_wait_period_n[]; // 读数据通道的等待周期数
	
	// 域自动化
	`uvm_object_param_utils_begin(AXITrans #(.addr_width(addr_width), .data_width(data_width), .bresp_width(bresp_width), .rresp_width(rresp_width)))
		`uvm_field_int(data_n, UVM_ALL_ON)
		
		`uvm_field_int(addr, UVM_ALL_ON)
		`uvm_field_int(burst, UVM_ALL_ON)
		`uvm_field_int(cache, UVM_ALL_ON)
		`uvm_field_int(len, UVM_ALL_ON)
		`uvm_field_int(lock, UVM_ALL_ON)
		`uvm_field_int(prot, UVM_ALL_ON)
		`uvm_field_int(size, UVM_ALL_ON)
		`uvm_field_int(addr_wait_period_n, UVM_ALL_ON)
		
		`uvm_field_queue_int(wdata, UVM_ALL_ON)
		`uvm_field_queue_int(wstrb, UVM_ALL_ON)
		`uvm_field_array_int(wdata_wait_period_n, UVM_ALL_ON)
		
		`uvm_field_int(bresp, UVM_ALL_ON)
		
		`uvm_field_queue_int(rdata, UVM_ALL_ON)
		`uvm_field_queue_int(rresp, UVM_ALL_ON)
		`uvm_field_array_int(rdata_wait_period_n, UVM_ALL_ON)
	`uvm_object_utils_end
	
	function new(string name = "AXITrans");
		super.new();
	endfunction
	
endclass

/** 事务:APB **/
class APBTrans #(
	integer addr_width = 32, // 地址位宽(1~32)
    integer data_width = 32 // 数据位宽(8 | 16 | 32)
)extends uvm_sequence_item;
    
	// 主机
    rand bit[addr_width-1:0] addr; // 地址
    rand bit[data_width-1:0] wdata; // 写数据
    rand bit[data_width/8-1:0] wstrb; // 写字节掩码
    rand bit write; // 是否写传输
	
	// 从机
	rand bit[data_width-1:0] rdata; // 读数据
	rand bit slverr; // 从机错误
	
	// 从机
    rand byte unsigned wait_period_n; // 传输的等待周期数
	
	// 域自动化
	`uvm_object_utils_begin(APBTrans)
		`uvm_field_int(addr, UVM_ALL_ON)
		`uvm_field_int(wdata, UVM_ALL_ON)
		`uvm_field_int(wstrb, UVM_ALL_ON)
		`uvm_field_int(write, UVM_ALL_ON)
		`uvm_field_int(rdata, UVM_ALL_ON)
		`uvm_field_int(slverr, UVM_ALL_ON)
		`uvm_field_int(wait_period_n, UVM_ALL_ON)
	`uvm_object_utils_end
	
	function new(string name = "APBTrans");
		super.new();
	endfunction
    
endclass

/** 事务:AXIS **/
class AXISTrans #(
    integer data_width = 32, // 数据位宽(必须能被8整除)
    integer user_width = 0 // 用户数据位宽
)extends uvm_sequence_item;
	
	// 数据个数
	rand int unsigned data_n;
	
	// 主机
	rand bit[data_width-1:0] data[$];
    rand bit[data_width/8-1:0] keep[$];
	rand bit[data_width/8-1:0] strb[$];
    rand bit[user_width-1:0] user[$];
	rand bit last[$];
	
	// 主机或从机
    rand byte unsigned wait_period_n[]; // 每个数据的等待周期数
	
	// 域自动化
	`uvm_object_param_utils_begin(AXISTrans #(.data_width(data_width), .user_width(user_width)))
		`uvm_field_int(data_n, UVM_ALL_ON)
		`uvm_field_queue_int(data, UVM_ALL_ON)
		`uvm_field_queue_int(keep, UVM_ALL_ON)
		`uvm_field_queue_int(strb, UVM_ALL_ON)
		`uvm_field_queue_int(user, UVM_ALL_ON)
		`uvm_field_array_int(wait_period_n, UVM_ALL_ON)
	`uvm_object_utils_end
	
	function new(string name = "AXISTrans");
		super.new();
	endfunction
	
endclass

/** 事务:AHB **/
class AHBTrans #(
    integer addr_width = 32, // 地址位宽(10~64)
    integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
    integer burst_width = 3, // 突发类型位宽(0~3)
    integer prot_width = 4, // 保护类型位宽(0 | 4 | 7)
    integer master_width = 1 // 主机标识位宽(0~8)
)extends uvm_sequence_item;
	
	// 地址和附加传输信息
    rand bit[addr_width-1:0] haddr;
	rand bit[burst_width-1:0] hburst;
	rand bit hmastllock;
	rand bit[prot_width-1:0] hprot;
	rand bit[2:0] hsize;
	rand bit hnonsec;
    rand bit hexcl;
    rand bit[master_width-1:0] hmaster;
    rand bit hwrite;
	
	// 写数据和写字节选通
    rand bit[data_width-1:0] hwdata[$];
    rand bit[data_width/8-1:0] hwstrb[$];
	// 读数据
	rand bit[data_width-1:0] hrdata[$];
	// 从机响应
    rand bit hresp[$];
    rand bit hexokay[$];
    
	// 传输的等待周期数
	/*
	将该数组的长度作为突发长度
	用于主机事务时, 指定每次传输后BUSY或IDLE的周期数
	*/
	rand byte unsigned wait_period_n[];
	
	// 域自动化
	`uvm_object_param_utils_begin(AHBTrans #(.addr_width(addr_width), .data_width(data_width), .burst_width(burst_width), .prot_width(prot_width), .master_width(master_width)))
		`uvm_field_int(haddr, UVM_ALL_ON)
		`uvm_field_int(hburst, UVM_ALL_ON)
		`uvm_field_int(hmastllock, UVM_ALL_ON)
		`uvm_field_int(hprot, UVM_ALL_ON)
		`uvm_field_int(hsize, UVM_ALL_ON)
		`uvm_field_int(hnonsec, UVM_ALL_ON)
		`uvm_field_int(hexcl, UVM_ALL_ON)
		`uvm_field_int(hmaster, UVM_ALL_ON)
		`uvm_field_int(hwrite, UVM_ALL_ON)
		`uvm_field_queue_int(hwdata, UVM_ALL_ON)
		`uvm_field_queue_int(hwstrb, UVM_ALL_ON)
		`uvm_field_queue_int(hrdata, UVM_ALL_ON)
		`uvm_field_queue_int(hresp, UVM_ALL_ON)
		`uvm_field_queue_int(hexokay, UVM_ALL_ON)
		`uvm_field_array_int(wait_period_n, UVM_ALL_ON)
	`uvm_object_utils_end
	
endclass

/** 事务:req-ack **/
class ReqAckTrans #(
	integer req_payload_width = 32, // 请求数据位宽
	integer resp_payload_width = 32 // 响应数据位宽
)extends uvm_sequence_item;
	
	// 请求
	rand bit[req_payload_width-1:0] req_payload; // 数据
	rand byte unsigned req_wait_period_n; // 等待周期数
	
	// 响应
	rand bit[resp_payload_width-1:0] resp_payload; // 数据
	rand byte unsigned resp_wait_period_n; // 等待周期数
	
	`uvm_object_param_utils_begin(ReqAckTrans #(.req_payload_width(req_payload_width), .resp_payload_width(resp_payload_width)))
		`uvm_field_int(req_payload, UVM_ALL_ON)
		`uvm_field_int(req_wait_period_n, UVM_ALL_ON)
		`uvm_field_int(resp_payload, UVM_ALL_ON)
		`uvm_field_int(resp_wait_period_n, UVM_ALL_ON)
	`uvm_object_utils_end
	
endclass

/** 事务:ICB **/
class ICBTrans #(
	integer addr_width = 32, // 地址位宽
	integer data_width = 32 // 数据位宽
)extends uvm_sequence_item;
	
	rand bit[addr_width-1:0] cmd_addr;
	rand bit cmd_read;
	rand bit[data_width-1:0] cmd_wdata;
	rand bit[data_width/8-1:0] cmd_wmask;
	rand byte unsigned cmd_wait_period_n; // 等待周期数
	
	rand bit[data_width-1:0] rsp_rdata;
	rand bit rsp_err;
	rand byte unsigned rsp_wait_period_n; // 等待周期数
	
	`uvm_object_param_utils_begin(ICBTrans #(.addr_width(addr_width), .data_width(data_width)))
		`uvm_field_int(cmd_addr, UVM_ALL_ON)
		`uvm_field_int(cmd_read, UVM_ALL_ON)
		`uvm_field_int(cmd_wdata, UVM_ALL_ON)
		`uvm_field_int(cmd_wmask, UVM_ALL_ON)
		`uvm_field_int(cmd_wait_period_n, UVM_ALL_ON)
		`uvm_field_int(rsp_rdata, UVM_ALL_ON)
		`uvm_field_int(rsp_err, UVM_ALL_ON)
		`uvm_field_int(rsp_wait_period_n, UVM_ALL_ON)
	`uvm_object_utils_end
	
endclass

`endif
