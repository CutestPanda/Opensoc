`timescale 1ns / 1ps

`ifndef __CASE_H

`define __CASE_H

`include "transactions.sv"
`include "envs.sv"
`include "vsqr.sv"

class AXISLnActCalCase0MAxisLnParsSeq #(
	integer ab_quaz_acc = 12, // a/b系数量化精度(必须在范围[1, cal_width-1]内)
	integer cal_width = 16 // 计算位宽(对于x/y/z和a/b/c来说, 可选8 | 16)
)extends uvm_sequence #(AXISTrans #(.data_width(64), .user_width(2)));
	
	local int unsigned pars_n; // 线性参数A和B的个数
	local int unsigned trans_n; // 线性参数A和B的传输次数
	local bit[7:0] last_keep; // 线性参数A和B最后1次传输的keep信号
	local bit[1:0] en_par_ab; // 是否使能线性参数A和B
	
	local AXISTrans #(.data_width(64), .user_width(2)) m_axis_trans; // AXIS主机事务
	
	// 注册object
	`uvm_object_param_utils(AXISLnActCalCase0MAxisLnParsSeq #(.ab_quaz_acc(ab_quaz_acc), .cal_width(cal_width)))
	
	function new(string name = "AXISLnActCalCase0MAxisLnParsSeq");
		super.new(name);
	endfunction
	
	virtual task pre_body();
		
	endtask
	
	virtual task body();
		this.pars_n = 5;
		this.en_par_ab = 2'b11;
		
		this.trans_n = this.pars_n / (64 / cal_width);
		if(this.pars_n % (64 / cal_width))
			this.trans_n++;
		
		if(cal_width == 8)
		begin
			case(this.pars_n % 8)
				0: this.last_keep = 8'b1111_1111;
				1: this.last_keep = 8'b0000_0001;
				2: this.last_keep = 8'b0000_0011;
				3: this.last_keep = 8'b0000_0111;
				4: this.last_keep = 8'b0000_1111;
				5: this.last_keep = 8'b0001_1111;
				6: this.last_keep = 8'b0011_1111;
				7: this.last_keep = 8'b0111_1111;
			endcase
		end
		else
		begin
			case(this.pars_n % 4)
				0: this.last_keep = 8'b1111_1111;
				1: this.last_keep = 8'b0000_0011;
				2: this.last_keep = 8'b0000_1111;
				3: this.last_keep = 8'b0011_1111;
			endcase
		end
		
		`uvm_info("AXISLnActCalCase0MAxisLnParsSeq", $sformatf("trans_n = %d", this.trans_n), UVM_LOW)
		`uvm_info("AXISLnActCalCase0MAxisLnParsSeq", $sformatf("last_keep = %b", this.last_keep), UVM_LOW)
		`uvm_info("AXISLnActCalCase0MAxisLnParsSeq", $sformatf("en_par_ab = %b", this.en_par_ab), UVM_LOW)
		
		for(int k = 0;k < 2;k++)
		begin
			if(this.en_par_ab[k])
			begin
				`uvm_do_with(this.m_axis_trans, {
					data_n == trans_n;
					
					data.size() == trans_n;
					keep.size() == trans_n;
					user.size() == trans_n;
					last.size() == trans_n;
					wait_period_n.size() == trans_n;
					
					foreach(data[i]){
						if(cal_width == 8){
							($signed(data[i][7:0]) <= (2 ** (ab_quaz_acc + 1) - 1)) && 
							($signed(data[i][7:0]) >= -(2 ** (ab_quaz_acc + 1))) && 
							($signed(data[i][15:8]) <= (2 ** (ab_quaz_acc + 1) - 1)) && 
							($signed(data[i][15:8]) >= -(2 ** (ab_quaz_acc + 1))) && 
							($signed(data[i][23:16]) <= (2 ** (ab_quaz_acc + 1) - 1)) && 
							($signed(data[i][23:16]) >= -(2 ** (ab_quaz_acc + 1))) && 
							($signed(data[i][31:24]) <= (2 ** (ab_quaz_acc + 1) - 1)) && 
							($signed(data[i][31:24]) >= -(2 ** (ab_quaz_acc + 1))) && 
							($signed(data[i][39:32]) <= (2 ** (ab_quaz_acc + 1) - 1)) && 
							($signed(data[i][39:32]) >= -(2 ** (ab_quaz_acc + 1))) && 
							($signed(data[i][47:40]) <= (2 ** (ab_quaz_acc + 1) - 1)) && 
							($signed(data[i][47:40]) >= -(2 ** (ab_quaz_acc + 1))) && 
							($signed(data[i][55:48]) <= (2 ** (ab_quaz_acc + 1) - 1)) && 
							($signed(data[i][55:48]) >= -(2 ** (ab_quaz_acc + 1))) && 
							($signed(data[i][63:56]) <= (2 ** (ab_quaz_acc + 1) - 1)) && 
							($signed(data[i][63:56]) >= -(2 ** (ab_quaz_acc + 1)));
						}else{
							($signed(data[i][15:0]) <= (2 ** (ab_quaz_acc + 1) - 1)) && 
							($signed(data[i][15:0]) >= -(2 ** (ab_quaz_acc + 1))) && 
							($signed(data[i][31:16]) <= (2 ** (ab_quaz_acc + 1) - 1)) && 
							($signed(data[i][31:16]) >= -(2 ** (ab_quaz_acc + 1))) && 
							($signed(data[i][47:32]) <= (2 ** (ab_quaz_acc + 1) - 1)) && 
							($signed(data[i][47:32]) >= -(2 ** (ab_quaz_acc + 1))) && 
							($signed(data[i][63:48]) <= (2 ** (ab_quaz_acc + 1) - 1)) && 
							($signed(data[i][63:48]) >= -(2 ** (ab_quaz_acc + 1)));
						}
					}
					
					foreach(keep[i]){
						keep[i] == ((i == (trans_n - 1)) ? last_keep:8'b1111_1111);
					}
					
					foreach(user[i]){
						user[i][1] == 1'b1;
						user[i][0] == k;
					}
					
					foreach(last[i]){
						last[i] == (i == (trans_n - 1));
					}
					
					foreach(wait_period_n[i]){
						wait_period_n[i] <= 3;
					}
				})
			end
			else
			begin
				`uvm_do_with(this.m_axis_trans, {
					data_n == 1;
					
					data.size() == 1;
					keep.size() == 1;
					user.size() == 1;
					last.size() == 1;
					wait_period_n.size() == 1;
					
					keep[0] == 8'hff;
					user[0][1] == 1'b1;
					user[0][0] == k;
					last[0] == 1'b1;
					wait_period_n[0] <= 3;
				})
			end
		end
	endtask
	
endclass

class AXISLnActCalCase0MAxisConvResSeq #(
	integer cal_width = 16, // 计算位宽(对于x/y/z和a/b/c来说, 可选8 | 16)
	integer xyz_quaz_acc = 10, // x/y/z变量量化精度(必须在范围[1, cal_width-1]内)
	integer xyz_ext_int_width = 4, // x/y/z额外考虑的整数位数(必须<=(cal_width-xyz_quaz_acc))
	integer xyz_ext_frac_width = 4 // x/y/z额外考虑的小数位数(必须<=xyz_quaz_acc)
)extends uvm_sequence #(AXISTrans #(.data_width(cal_width*2), .user_width(16)));
	
	local AXISTrans #(.data_width(cal_width*2), .user_width(16)) m_axis_trans; // AXIS主机事务
	
	local int unsigned pars_n; // 线性参数A和B的个数
	local int unsigned test_row_n; // 测试的行数
	
	// 注册object
	`uvm_object_param_utils(AXISLnActCalCase0MAxisConvResSeq #(.cal_width(cal_width), .xyz_quaz_acc(xyz_quaz_acc), .xyz_ext_int_width(xyz_ext_int_width), .xyz_ext_frac_width(xyz_ext_frac_width)))
	
	function new(string name = "AXISLnActCalCase0MAxisConvResSeq");
		super.new(name);
	endfunction
	
	virtual task pre_body();
		
	endtask
	
	virtual task body();
		this.pars_n = 5;
		this.test_row_n = 3;
		
		`uvm_info("AXISLnActCalCase0MAxisConvResSeq", $sformatf("pars_n = %d", this.pars_n), UVM_LOW)
		`uvm_info("AXISLnActCalCase0MAxisConvResSeq", $sformatf("test_row_n = %d", this.test_row_n), UVM_LOW)
		
		for(int k = 0;k < this.test_row_n;k++)
		begin
			`uvm_do_with(this.m_axis_trans, {
				(data_n >= 1) && (data_n <= 10);
				
				data.size() == data_n;
				user.size() == data_n;
				last.size() == data_n;
				wait_period_n.size() == data_n;
				
				foreach(data[i]){
					($signed(data[i]) >= -(2 ** (xyz_quaz_acc + xyz_ext_frac_width + 1))) && 
					($signed(data[i]) <= ((2 ** (xyz_quaz_acc + xyz_ext_frac_width + 1)) - 1));
				}
				
				foreach(user[i]){
					user[i] <= (pars_n - 1);
				}
				
				foreach(last[i]){
					last[i] == (i == (data_n - 1));
				}
				
				foreach(wait_period_n[i]){
					wait_period_n[i] <= 3;
				}
			})
		end
	endtask
	
endclass

class AXISLnActCalCase0VSqr #(
	integer cal_width = 16, // 计算位宽(对于x/y/z和a/b/c来说, 可选8 | 16)
	integer ab_quaz_acc = 12, // a/b系数量化精度(必须在范围[1, cal_width-1]内)
	integer xyz_quaz_acc = 10, // x/y/z变量量化精度(必须在范围[1, cal_width-1]内)
	integer xyz_ext_int_width = 4, // x/y/z额外考虑的整数位数(必须<=(cal_width-xyz_quaz_acc))
	integer xyz_ext_frac_width = 4 // x/y/z额外考虑的小数位数(必须<=xyz_quaz_acc)
)extends uvm_sequence;
	
	// 注册object
	`uvm_object_param_utils(AXISLnActCalCase0VSqr #(.cal_width(cal_width), .ab_quaz_acc(ab_quaz_acc), .xyz_quaz_acc(xyz_quaz_acc), .xyz_ext_int_width(xyz_ext_int_width), .xyz_ext_frac_width(xyz_ext_frac_width)))
	
	// 声明p_sequencer
	`uvm_declare_p_sequencer(AXISLnActCalVsqr #(.cal_width(cal_width)))
	
	virtual task body();
		AXISLnActCalCase0MAxisLnParsSeq #(.ab_quaz_acc(ab_quaz_acc), .cal_width(cal_width)) seq0;
		AXISLnActCalCase0MAxisConvResSeq #(.cal_width(cal_width), .xyz_quaz_acc(xyz_quaz_acc), 
			.xyz_ext_int_width(xyz_ext_int_width), .xyz_ext_frac_width(xyz_ext_frac_width)) seq1;
		
		if(this.starting_phase != null) 
			this.starting_phase.raise_objection(this);
		
		`uvm_do_on(seq0, p_sequencer.m_axis_linear_pars_sqr)
		`uvm_do_on(seq1, p_sequencer.m_axis_conv_res_sqr)
		
		// 继续运行100us
		# (10 ** 5);
		
		if(this.starting_phase != null) 
			this.starting_phase.drop_objection(this);
	endtask
	
endclass

class AXISLnActCalBaseTest #(
	integer cal_width = 16, // 计算位宽(对于x/y/z和a/b/c来说, 可选8 | 16)
	real simulation_delay = 1 // 仿真延时
)extends uvm_test;
	
	// AXIS线性乘加与激活计算单元测试环境
	local AXISLnActCalEnv #(.cal_width(cal_width), .simulation_delay(simulation_delay)) env;
	
	// 虚拟Sequencer
	protected AXISLnActCalVsqr #(.cal_width(cal_width)) vsqr;
	
	// 注册component
	`uvm_component_param_utils(AXISLnActCalBaseTest #(.cal_width(cal_width), .simulation_delay(simulation_delay)))
	
	function new(string name = "AXISLnActCalBaseTest", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.env = AXISLnActCalEnv #(.cal_width(cal_width), .simulation_delay(simulation_delay))::
			type_id::create("env", this); // 创建env
		
		this.vsqr = AXISLnActCalVsqr #(.cal_width(cal_width))::
			type_id::create("v_sqr", this); // 创建虚拟Sequencer
	endfunction
	
	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		
		this.vsqr.m_axis_conv_res_sqr = this.env.m_axis_conv_res_agt.sequencer;
		this.vsqr.m_axis_linear_pars_sqr = this.env.m_axis_linear_pars_agt.sequencer;
	endfunction
	
endclass

class AXISLnActCalCase0Test extends AXISLnActCalBaseTest #(.cal_width(16), .simulation_delay(1));
	
	// 注册component
	`uvm_component_utils(AXISLnActCalCase0Test)
	
	function new(string name = "AXISLnActCalCase0Test", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		// 设置sequence
		uvm_config_db #(uvm_object_wrapper)::set(
			this, 
			"v_sqr.main_phase", 
			"default_sequence", 
			AXISLnActCalCase0VSqr #(.cal_width(16), .ab_quaz_acc(12), .xyz_quaz_acc(10), 
				.xyz_ext_int_width(4), .xyz_ext_frac_width(4))::type_id::get());
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info("AXISLnActCalCase0Test", "test finished!", UVM_LOW)
	endfunction
	
endclass

`endif
