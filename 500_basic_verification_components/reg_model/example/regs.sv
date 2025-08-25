`timescale 1ns / 1ps

`ifndef __REG_H

`define __REG_H

`include "uvm_macros.svh"

import uvm_pkg::*;

class TimerRegPsc extends uvm_reg;

    rand uvm_reg_field field_psc_sub1;

    `uvm_object_utils(TimerRegPsc)

    function new(input string name = "TimerRegPsc");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        this.field_psc_sub1 = uvm_reg_field::type_id::create("field_psc_sub1");
        this.field_psc_sub1.configure(this, 32, 0, "RW", 1, 0, 0, 1, 0);
    endfunction

endclass

class TimerRegAtl extends uvm_reg;

    rand uvm_reg_field field_atl_sub1;

    `uvm_object_utils(TimerRegAtl)

    function new(input string name = "TimerRegAtl");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        this.field_atl_sub1 = uvm_reg_field::type_id::create("field_atl_sub1");
        this.field_atl_sub1.configure(this, 32, 0, "RW", 1, 0, 0, 1, 0);
    endfunction

endclass

class TimerRegCnt extends uvm_reg;

    rand uvm_reg_field field_cnt;

    `uvm_object_utils(TimerRegCnt)

    function new(input string name = "TimerRegCnt");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        this.field_cnt = uvm_reg_field::type_id::create("field_cnt");
        this.field_cnt.configure(this, 32, 0, "RW", 1, 0, 0, 1, 0);
    endfunction

endclass

class TimerRegCtrl extends uvm_reg;

    rand uvm_reg_field field_timer_started;
    rand uvm_reg_field field_cap_cmp_sel;
    rand uvm_reg_field field_cmp_oen;
    uvm_reg_field field_version;
    uvm_reg_field field_chn_n;
    rand uvm_reg_field field_in_ecd_mode;

    `uvm_object_utils(TimerRegCtrl)

    function new(input string name = "TimerRegCtrl");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        this.field_timer_started = uvm_reg_field::type_id::create("field_timer_started");
        this.field_timer_started.configure(this, 1, 0, "RW", 1, 0, 1, 1, 0);

        this.field_cap_cmp_sel = uvm_reg_field::type_id::create("field_cap_cmp_sel");
        this.field_cap_cmp_sel.configure(this, 4, 8, "RW", 1, 0, 0, 1, 0);

        this.field_cmp_oen = uvm_reg_field::type_id::create("field_cmp_oen");
        this.field_cmp_oen.configure(this, 4, 12, "RW", 1, 'b1111, 1, 1, 0);

        this.field_version = uvm_reg_field::type_id::create("field_version");
        this.field_version.configure(this, 8, 16, "RO", 1, 'd2, 1, 0, 0);

        this.field_chn_n = uvm_reg_field::type_id::create("field_chn_n");
        this.field_chn_n.configure(this, 3, 24, "RO", 1, 'd4, 1, 0, 0);

        this.field_in_ecd_mode = uvm_reg_field::type_id::create("field_in_ecd_mode");
        this.field_in_ecd_mode.configure(this, 1, 27, "RW", 1, 0, 1, 1, 0);
    endfunction

endclass

class TimerRegItrEn extends uvm_reg;

    rand uvm_reg_field field_global_itr_en;
    rand uvm_reg_field field_tmr_elapsed_itr_en;
    rand uvm_reg_field field_input_cap_itr_en;

    `uvm_object_utils(TimerRegItrEn)

    function new(input string name = "TimerRegItrEn");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        this.field_global_itr_en = uvm_reg_field::type_id::create("field_global_itr_en");
        this.field_global_itr_en.configure(this, 1, 0, "RW", 1, 0, 1, 1, 0);

        this.field_tmr_elapsed_itr_en = uvm_reg_field::type_id::create("field_tmr_elapsed_itr_en");
        this.field_tmr_elapsed_itr_en.configure(this, 1, 8, "RW", 1, 0, 1, 1, 0);

        this.field_input_cap_itr_en = uvm_reg_field::type_id::create("field_input_cap_itr_en");
        this.field_input_cap_itr_en.configure(this, 4, 9, "RW", 1, 0, 1, 1, 0);
    endfunction

endclass

class TimerRegItrFlag extends uvm_reg;

    rand uvm_reg_field field_global_itr_flag;
    rand uvm_reg_field field_tmr_elapsed_itr_flag;
    rand uvm_reg_field field_input_cap_itr_flag;

    `uvm_object_utils(TimerRegItrFlag)

    function new(input string name = "TimerRegItrFlag");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        this.field_global_itr_flag = uvm_reg_field::type_id::create("field_global_itr_flag");
        this.field_global_itr_flag.configure(this, 1, 0, "WC", 1, 0, 1, 1, 0);

        this.field_tmr_elapsed_itr_flag = uvm_reg_field::type_id::create("field_tmr_elapsed_itr_flag");
        this.field_tmr_elapsed_itr_flag.configure(this, 1, 8, "RO", 1, 0, 1, 1, 0);

        this.field_input_cap_itr_flag = uvm_reg_field::type_id::create("field_input_cap_itr_flag");
        this.field_input_cap_itr_flag.configure(this, 4, 9, "RO", 1, 0, 1, 1, 0);
    endfunction

endclass

class TimerRegChn0CapCmpV extends uvm_reg;

    rand uvm_reg_field field_cap_cmp_v;

    `uvm_object_utils(TimerRegChn0CapCmpV)

    function new(input string name = "TimerRegChn0CapCmpV");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        this.field_cap_cmp_v = uvm_reg_field::type_id::create("field_cap_cmp_v");
        this.field_cap_cmp_v.configure(this, 32, 0, "RW", 1, 0, 0, 1, 0);
    endfunction

endclass

class TimerRegChn0CapCmpCfg extends uvm_reg;

    rand uvm_reg_field field_input_cap_filter_th;
    rand uvm_reg_field field_input_cap_edge_type;
    rand uvm_reg_field field_output_cmp_mode;

    `uvm_object_utils(TimerRegChn0CapCmpCfg)

    function new(input string name = "TimerRegChn0CapCmpCfg");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        this.field_input_cap_filter_th = uvm_reg_field::type_id::create("field_input_cap_filter_th");
        this.field_input_cap_filter_th.configure(this, 8, 0, "WO", 1, 0, 0, 1, 0);

        this.field_input_cap_edge_type = uvm_reg_field::type_id::create("field_input_cap_edge_type");
        this.field_input_cap_edge_type.configure(this, 2, 8, "WO", 1, 0, 0, 1, 0);

        this.field_output_cmp_mode = uvm_reg_field::type_id::create("field_output_cmp_mode");
        this.field_output_cmp_mode.configure(this, 2, 10, "WO", 1, 0, 0, 1, 0);
    endfunction

endclass

class TimerRegChn1CapCmpV extends uvm_reg;

    rand uvm_reg_field field_cap_cmp_v;

    `uvm_object_utils(TimerRegChn1CapCmpV)

    function new(input string name = "TimerRegChn1CapCmpV");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        this.field_cap_cmp_v = uvm_reg_field::type_id::create("field_cap_cmp_v");
        this.field_cap_cmp_v.configure(this, 32, 0, "RW", 1, 0, 0, 1, 0);
    endfunction

endclass

class TimerRegChn1CapCmpCfg extends uvm_reg;

    rand uvm_reg_field field_input_cap_filter_th;
    rand uvm_reg_field field_input_cap_edge_type;
    rand uvm_reg_field field_output_cmp_mode;

    `uvm_object_utils(TimerRegChn1CapCmpCfg)

    function new(input string name = "TimerRegChn1CapCmpCfg");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        this.field_input_cap_filter_th = uvm_reg_field::type_id::create("field_input_cap_filter_th");
        this.field_input_cap_filter_th.configure(this, 8, 0, "WO", 1, 0, 0, 1, 0);

        this.field_input_cap_edge_type = uvm_reg_field::type_id::create("field_input_cap_edge_type");
        this.field_input_cap_edge_type.configure(this, 2, 8, "WO", 1, 0, 0, 1, 0);

        this.field_output_cmp_mode = uvm_reg_field::type_id::create("field_output_cmp_mode");
        this.field_output_cmp_mode.configure(this, 2, 10, "WO", 1, 0, 0, 1, 0);
    endfunction

endclass

class TimerRegChn2CapCmpV extends uvm_reg;

    rand uvm_reg_field field_cap_cmp_v;

    `uvm_object_utils(TimerRegChn2CapCmpV)

    function new(input string name = "TimerRegChn2CapCmpV");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        this.field_cap_cmp_v = uvm_reg_field::type_id::create("field_cap_cmp_v");
        this.field_cap_cmp_v.configure(this, 32, 0, "RW", 1, 0, 0, 1, 0);
    endfunction

endclass

class TimerRegChn2CapCmpCfg extends uvm_reg;

    rand uvm_reg_field field_input_cap_filter_th;
    rand uvm_reg_field field_input_cap_edge_type;
    rand uvm_reg_field field_output_cmp_mode;

    `uvm_object_utils(TimerRegChn2CapCmpCfg)

    function new(input string name = "TimerRegChn2CapCmpCfg");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        this.field_input_cap_filter_th = uvm_reg_field::type_id::create("field_input_cap_filter_th");
        this.field_input_cap_filter_th.configure(this, 8, 0, "WO", 1, 0, 0, 1, 0);

        this.field_input_cap_edge_type = uvm_reg_field::type_id::create("field_input_cap_edge_type");
        this.field_input_cap_edge_type.configure(this, 2, 8, "WO", 1, 0, 0, 1, 0);

        this.field_output_cmp_mode = uvm_reg_field::type_id::create("field_output_cmp_mode");
        this.field_output_cmp_mode.configure(this, 2, 10, "WO", 1, 0, 0, 1, 0);
    endfunction

endclass

class TimerRegChn3CapCmpV extends uvm_reg;

    rand uvm_reg_field field_cap_cmp_v;

    `uvm_object_utils(TimerRegChn3CapCmpV)

    function new(input string name = "TimerRegChn3CapCmpV");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        this.field_cap_cmp_v = uvm_reg_field::type_id::create("field_cap_cmp_v");
        this.field_cap_cmp_v.configure(this, 32, 0, "RW", 1, 0, 0, 1, 0);
    endfunction

endclass

class TimerRegChn3CapCmpCfg extends uvm_reg;

    rand uvm_reg_field field_input_cap_filter_th;
    rand uvm_reg_field field_input_cap_edge_type;
    rand uvm_reg_field field_output_cmp_mode;

    `uvm_object_utils(TimerRegChn3CapCmpCfg)

    function new(input string name = "TimerRegChn3CapCmpCfg");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        this.field_input_cap_filter_th = uvm_reg_field::type_id::create("field_input_cap_filter_th");
        this.field_input_cap_filter_th.configure(this, 8, 0, "WO", 1, 0, 0, 1, 0);

        this.field_input_cap_edge_type = uvm_reg_field::type_id::create("field_input_cap_edge_type");
        this.field_input_cap_edge_type.configure(this, 2, 8, "WO", 1, 0, 0, 1, 0);

        this.field_output_cmp_mode = uvm_reg_field::type_id::create("field_output_cmp_mode");
        this.field_output_cmp_mode.configure(this, 2, 10, "WO", 1, 0, 0, 1, 0);
    endfunction

endclass

`endif
