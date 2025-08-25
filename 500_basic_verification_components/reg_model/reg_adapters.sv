`timescale 1ns / 1ps

`ifndef __ADAPTER_H

`define __ADAPTER_H

`include "../transactions.sv"

/** 适配器: APB事务 <-> 寄存器操作 **/
class RegApbAdapter #(
	integer addr_width = 32, // 地址位宽(1~32)
    integer data_width = 32 // 数据位宽(8 | 16 | 32)
)extends uvm_reg_adapter;
	
	local rand byte unsigned wait_period_n; // APB传输的等待周期数
	
	constraint default_cstrt{
		wait_period_n <= 1;
	}
	
	`uvm_object_param_utils(RegApbAdapter #(.addr_width(addr_width), .data_width(data_width)))
	
	function new(string name = "RegApbAdapter");
		super.new(name);
	endfunction
	
	virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
		automatic APBTrans #(.addr_width(addr_width), .data_width(data_width)) apb_tr = 
			APBTrans #(.addr_width(addr_width), .data_width(data_width))::type_id::create("apb_tr");
		
		if(!this.randomize())
		begin
			`uvm_fatal("APBTr_Rand_Err", "Cannot randomize wait_period_n")
		end
		
		apb_tr.addr = rw.addr;
		apb_tr.wdata = rw.data;
		apb_tr.wstrb = {(data_width/8){1'b1}};
		apb_tr.write = rw.kind == UVM_WRITE;
		
		apb_tr.wait_period_n = wait_period_n;
		
		return apb_tr;
	endfunction
	
	virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
		automatic APBTrans #(.addr_width(addr_width), .data_width(data_width)) apb_tr_2;
		
		if(!$cast(apb_tr_2, bus_item))
		begin
			`uvm_fatal("CONVERT_APB2REG", "Bus item is not of type apb_tr")
		end
		
		rw.kind = apb_tr_2.write ? UVM_WRITE:UVM_READ;
		rw.addr = apb_tr_2.addr;
		rw.data = apb_tr_2.write ? apb_tr_2.wdata:apb_tr_2.rdata;
		rw.status = apb_tr_2.slverr ? UVM_NOT_OK:UVM_IS_OK;
	endfunction
	
endclass

`endif
