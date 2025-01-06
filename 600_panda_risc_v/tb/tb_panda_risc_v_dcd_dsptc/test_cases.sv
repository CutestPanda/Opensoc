`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"
`include "vsqr.sv"

/** 枚举类型: 派遣类型 **/
typedef enum{
	MODE_CSRRW, 
	MODE_LS,
	MODE_LS_UNALIGNED,
	MODE_MUL, 
	MODE_DIV, 
	MODE_OTHER
}RiscVDsptcMode;

class DcdDsptcCase0VSqc extends uvm_sequence;
	
	local AXISTrans #(.data_width(128), .user_width(4)) m_if_res_axis_trans; // 取指结果AXIS主机事务
	local AXISTrans #(.data_width(160), .user_width(0)) s_exu_axis_trans[0:1]; // 执行单元AXIS从机事务
	local RiscVInstTrans inst_trans; // RV32指令事务
	
	local int unsigned test_n; // 测试译码/派遣次数
	local int unsigned fns_dsptc_n; // 完成的派遣次数
	
	local RiscVDsptcMode dispatch_fifo[$]; // 派遣队列
	
	local integer fid; // 用于打印取指结果的文件句柄
	
	// 注册object
	`uvm_object_utils(DcdDsptcCase0VSqc)
	
	// 声明p_sequencer
	`uvm_declare_p_sequencer(DcdDsptcVsqr)
	
	virtual task body();
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		this.fid = $fopen("inst_fetch_res.txt", "w");
		
		this.inst_trans = new();
		
		this.test_n = 400;
		this.fns_dsptc_n = 0;
		
		fork
			repeat(this.test_n)
				this.drive_m_if_res();
			
			forever
			begin
				this.drive_s_exu();
				
				if(this.fns_dsptc_n >= this.test_n)
					break;
			end
		join
		
		$fclose(this.fid);
		
		// 继续运行10us
		# (10 ** 4);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
	local task drive_m_if_res();
		automatic bit is_illegal_inst = $urandom_range(0, 6) == 6;
		automatic bit[1:0] err_code = ($urandom_range(0, 4) == 4) ? $urandom_range(1, 3):2'b00;
		automatic RiscVDsptcMode mode;
		
		// 随机化取指结果
		assert(this.inst_trans.randomize() with{
			if((!is_illegal_inst) && (err_code != 2'b00))
				inst == 32'h0000_0013;
			
			csr_addr <= 15;
			
			if((inst_type == JAL) || 
				(inst_type == BEQ) || (inst_type == BNE) || 
				(inst_type == BLT) || (inst_type == BGE) || 
				(inst_type == BLTU) || (inst_type == BGEU))
				(imm[1:0] == 2'b00) && (imm != 0);
			else if(inst_type == JALR){
				if(rs1 == 0)
					(imm >= 0) && (imm <= 256) && (imm[1:0] == 2'b00);
				else
					(imm >= -256) && (imm <= 256) && (imm[1:0] == 2'b00);
			}else
				(imm >= -1024) && (imm <= 1023);
			
			if(inst_type == JALR)
				rs1 dist {0:/1, 1:/3, [2:31]:/4};
		}) else $fatal("inst_trans failed to randomize!");
		
		if((!is_illegal_inst) & 
			((this.inst_trans.inst_type == CSRRW) || (this.inst_trans.inst_type == CSRRS) || 
			(this.inst_trans.inst_type == CSRRC) || (this.inst_trans.inst_type == CSRRWI) || 
			(this.inst_trans.inst_type == CSRRSI) || (this.inst_trans.inst_type == CSRRCI)))
		begin
			// CSR读写指令
			mode = MODE_CSRRW;
		end
		else if((!is_illegal_inst) & 
			((this.inst_trans.inst_type == LB) || (this.inst_trans.inst_type == LH) || 
			(this.inst_trans.inst_type == LW) || (this.inst_trans.inst_type == LBU) || 
			(this.inst_trans.inst_type == LHU) || (this.inst_trans.inst_type == SB) || 
			(this.inst_trans.inst_type == SH) || (this.inst_trans.inst_type == SW)))
		begin
			// LS指令
			if((this.inst_trans.inst_type == LB) || (this.inst_trans.inst_type == LBU) || (this.inst_trans.inst_type == SB) || 
				(((this.inst_trans.inst_type == LH) || (this.inst_trans.inst_type == LHU) || (this.inst_trans.inst_type == SH)) 
					&& (this.inst_trans.imm[0] == 1'b0)) || 
				(((this.inst_trans.inst_type == LW) || (this.inst_trans.inst_type == SW)) && (this.inst_trans.imm[1:0] == 2'b00)))
				mode = MODE_LS;
			else
				mode = MODE_LS_UNALIGNED;
		end
		else if((!is_illegal_inst) & 
			((this.inst_trans.inst_type == MUL) || (this.inst_trans.inst_type == MULH) || 
			(this.inst_trans.inst_type == MULHSU) || (this.inst_trans.inst_type == MULHU)))
		begin
			// 乘法指令
			mode = MODE_MUL;
		end
		else if((!is_illegal_inst) & 
			((this.inst_trans.inst_type == DIV) || (this.inst_trans.inst_type == DIVU) || 
			(this.inst_trans.inst_type == REM) || (this.inst_trans.inst_type == REMU)))
		begin
			// 除法/求余指令
			mode = MODE_DIV;
		end
		else
		begin
			// 其他或非法指令
			mode = MODE_OTHER;
		end
		
		this.inst_trans.file_print(this.fid);
		
		this.dispatch_fifo.push_back(mode);
		
		// 启动取指结果AXIS主机事务
		`uvm_do_on_with(this.m_if_res_axis_trans, p_sequencer.m_axis_if_res_sqr, {
			data_n == 1;
			
			data.size() == 1;
			user.size() == 1;
			last.size() == 1;
			wait_period_n.size() == 1;
			
			data[0][31:0] == inst_trans.inst;
			data[0][97:96] == 2'b00;
			
			user[0][2] == is_illegal_inst;
			user[0][1:0] == err_code;
			
			last[0] == 1'b1;
			wait_period_n[0] <= 2;
		})
	endtask
	
	local task drive_s_exu();
		wait((this.dispatch_fifo.size() > 0) || (this.fns_dsptc_n >= this.test_n));
		
		if(this.fns_dsptc_n < this.test_n)
		begin
			automatic RiscVDsptcMode mode = this.dispatch_fifo.pop_front();
			
			if(mode == MODE_CSRRW)
			begin
				fork
					`uvm_do_on_with(this.s_exu_axis_trans[0], p_sequencer.s_axis_alu_sqr, {
						wait_period_n.size() == 1;
						
						wait_period_n[0] dist {0:/1, 1:/3, [2:4]:/1};
					})
					
					`uvm_do_on_with(this.s_exu_axis_trans[1], p_sequencer.s_axis_csr_rw_sqr, {
						wait_period_n.size() == 1;
						
						wait_period_n[0] dist {0:/1, 1:/3, [2:4]:/1};
					})
				join
			end
			else if(mode == MODE_LS)
			begin
				fork
					`uvm_do_on_with(this.s_exu_axis_trans[0], p_sequencer.s_axis_alu_sqr, {
						wait_period_n.size() == 1;
						
						wait_period_n[0] dist {0:/1, 1:/3, [2:4]:/1};
					})
					
					`uvm_do_on_with(this.s_exu_axis_trans[1], p_sequencer.s_axis_lsu_sqr, {
						wait_period_n.size() == 1;
						
						wait_period_n[0] dist {0:/1, 1:/3, [2:4]:/1};
					})
				join
			end
			else if(mode == MODE_LS_UNALIGNED)
			begin
				`uvm_do_on_with(this.s_exu_axis_trans[0], p_sequencer.s_axis_alu_sqr, {
					wait_period_n.size() == 1;
					
					wait_period_n[0] dist {0:/1, 1:/3, [2:4]:/1};
				})
			end
			else if(mode == MODE_MUL)
			begin
				fork
					`uvm_do_on_with(this.s_exu_axis_trans[0], p_sequencer.s_axis_alu_sqr, {
						wait_period_n.size() == 1;
						
						wait_period_n[0] dist {0:/1, 1:/3, [2:4]:/1};
					})
					
					`uvm_do_on_with(this.s_exu_axis_trans[1], p_sequencer.s_axis_mul_sqr, {
						wait_period_n.size() == 1;
						
						wait_period_n[0] dist {0:/1, 1:/3, [2:4]:/1};
					})
				join
			end
			else if(mode == MODE_DIV)
			begin
				fork
					`uvm_do_on_with(this.s_exu_axis_trans[0], p_sequencer.s_axis_alu_sqr, {
						wait_period_n.size() == 1;
						
						wait_period_n[0] dist {0:/1, 1:/3, [2:4]:/1};
					})
					
					`uvm_do_on_with(this.s_exu_axis_trans[1], p_sequencer.s_axis_div_sqr, {
						wait_period_n.size() == 1;
						
						wait_period_n[0] dist {0:/1, 1:/3, [2:4]:/1};
					})
				join
			end
			else if(mode == MODE_OTHER)
			begin
				`uvm_do_on_with(this.s_exu_axis_trans[0], p_sequencer.s_axis_alu_sqr, {
					wait_period_n.size() == 1;
					
					wait_period_n[0] dist {0:/1, 1:/3, [2:4]:/1};
				})
			end
			
			this.fns_dsptc_n++;
		end
	endtask
	
endclass

class DcdDsptcBaseTest #(
	real simulation_delay = 1 // 仿真延时
)extends uvm_test;
	
	// 译码/派遣单元测试环境
	local DcdDsptcEnv #(.simulation_delay(simulation_delay)) env;
	
	// 注册component
	`uvm_component_param_utils(DcdDsptcBaseTest #(.simulation_delay(simulation_delay)))
	
	function new(string name = "DcdDsptcBaseTest", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = DcdDsptcEnv #(.simulation_delay(simulation_delay))::type_id::create("env", this); // 创建env
	endfunction
	
endclass

class DcdDsptcCase0Test extends DcdDsptcBaseTest #(.simulation_delay(1));
	
	// 注册component
	`uvm_component_utils(DcdDsptcCase0Test)
	
	function new(string name = "DcdDsptcCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"env.v_sqr.main_phase", 
			"default_sequence", 
			DcdDsptcCase0VSqc::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("DcdDsptcCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
