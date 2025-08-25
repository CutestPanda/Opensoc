`timescale 1ns / 1ps

`ifndef __REG_BLK_H

`define __REG_BLK_H

`include "regs.sv"

class TimerRegBlk extends uvm_reg_block;
    rand TimerRegPsc reg_psc;
    rand TimerRegAtl reg_atl;
    rand TimerRegCnt reg_cnt;
    rand TimerRegCtrl reg_ctrl;
    rand TimerRegItrEn reg_itr_en;
    rand TimerRegItrFlag reg_itr_flag;
    rand TimerRegChn0CapCmpV reg_chn0_v;
    rand TimerRegChn0CapCmpCfg reg_chn0_cfg;
    rand TimerRegChn1CapCmpV reg_chn1_v;
    rand TimerRegChn1CapCmpCfg reg_chn1_cfg;
    rand TimerRegChn2CapCmpV reg_chn2_v;
    rand TimerRegChn2CapCmpCfg reg_chn2_cfg;
    rand TimerRegChn3CapCmpV reg_chn3_v;
    rand TimerRegChn3CapCmpCfg reg_chn3_cfg;

    `uvm_object_utils(TimerRegBlk)

    function new(input string name = "TimerRegBlk");
        super.new(name, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        this.default_map = this.create_map("default_map", 32'h4000_0000, 4, UVM_LITTLE_ENDIAN, 0);

        this.reg_psc = TimerRegPsc::type_id::create("reg_psc");
        this.reg_psc.configure(this, null, "prescale_regs");
        this.reg_psc.build();

        this.reg_atl = TimerRegAtl::type_id::create("reg_atl");
        this.reg_atl.configure(this, null, "autoload_regs");
        this.reg_atl.build();

        this.reg_cnt = TimerRegCnt::type_id::create("reg_cnt");
        this.reg_cnt.configure(this, null, "");
        this.reg_cnt.build();

        this.reg_ctrl = TimerRegCtrl::type_id::create("reg_ctrl");
        this.reg_ctrl.configure(this, null, "");
        this.reg_ctrl.build();
		this.reg_ctrl.add_hdl_path_slice("timer_started_reg", 0, 1);
		this.reg_ctrl.add_hdl_path_slice("cap_cmp_sel_regs", 8, 4);
		this.reg_ctrl.add_hdl_path_slice("cmp_oen_regs", 12, 4);
		this.reg_ctrl.add_hdl_path_slice("in_encoder_mode_reg", 27, 1);

        this.reg_itr_en = TimerRegItrEn::type_id::create("reg_itr_en");
        this.reg_itr_en.configure(this, null, "");
        this.reg_itr_en.build();
		this.reg_itr_en.add_hdl_path_slice("global_itr_en", 0, 1);
		this.reg_itr_en.add_hdl_path_slice("timer_expired_itr_en", 8, 1);
		this.reg_itr_en.add_hdl_path_slice("timer_cap_itr_en", 9, 4);

        this.reg_itr_flag = TimerRegItrFlag::type_id::create("reg_itr_flag");
        this.reg_itr_flag.configure(this, null, "");
        this.reg_itr_flag.build();
		this.reg_itr_flag.add_hdl_path_slice("global_itr_flag", 0, 1);
		this.reg_itr_flag.add_hdl_path_slice("timer_expired_itr_flag", 8, 1);
		this.reg_itr_flag.add_hdl_path_slice("timer_cap_itr_flag", 9, 4);

        this.reg_chn0_v = TimerRegChn0CapCmpV::type_id::create("reg_chn0_v");
        this.reg_chn0_v.configure(this, null, "timer_chn1_cmp_regs");
        this.reg_chn0_v.build();

        this.reg_chn0_cfg = TimerRegChn0CapCmpCfg::type_id::create("reg_chn0_cfg");
        this.reg_chn0_cfg.configure(this, null, "");
        this.reg_chn0_cfg.build();
		this.reg_chn0_cfg.add_hdl_path_slice("timer_chn1_cap_filter_th_regs", 0, 8);
		this.reg_chn0_cfg.add_hdl_path_slice("timer_chn1_cap_edge_regs", 8, 2);
		this.reg_chn0_cfg.add_hdl_path_slice("timer_chn1_cmp_out_mode_regs", 10, 2);

        this.reg_chn1_v = TimerRegChn1CapCmpV::type_id::create("reg_chn1_v");
        this.reg_chn1_v.configure(this, null, "timer_chn2_cmp_regs");
        this.reg_chn1_v.build();

        this.reg_chn1_cfg = TimerRegChn1CapCmpCfg::type_id::create("reg_chn1_cfg");
        this.reg_chn1_cfg.configure(this, null, "");
        this.reg_chn1_cfg.build();
		this.reg_chn1_cfg.add_hdl_path_slice("timer_chn2_cap_filter_th_regs", 0, 8);
		this.reg_chn1_cfg.add_hdl_path_slice("timer_chn2_cap_edge_regs", 8, 2);
		this.reg_chn1_cfg.add_hdl_path_slice("timer_chn2_cmp_out_mode_regs", 10, 2);

        this.reg_chn2_v = TimerRegChn2CapCmpV::type_id::create("reg_chn2_v");
        this.reg_chn2_v.configure(this, null, "timer_chn3_cmp_regs");
        this.reg_chn2_v.build();

        this.reg_chn2_cfg = TimerRegChn2CapCmpCfg::type_id::create("reg_chn2_cfg");
        this.reg_chn2_cfg.configure(this, null, "");
        this.reg_chn2_cfg.build();
		this.reg_chn2_cfg.add_hdl_path_slice("timer_chn3_cap_filter_th_regs", 0, 8);
		this.reg_chn2_cfg.add_hdl_path_slice("timer_chn3_cap_edge_regs", 8, 2);
		this.reg_chn2_cfg.add_hdl_path_slice("timer_chn3_cmp_out_mode_regs", 10, 2);

        this.reg_chn3_v = TimerRegChn3CapCmpV::type_id::create("reg_chn3_v");
        this.reg_chn3_v.configure(this, null, "timer_chn4_cmp_regs");
        this.reg_chn3_v.build();

        this.reg_chn3_cfg = TimerRegChn3CapCmpCfg::type_id::create("reg_chn3_cfg");
        this.reg_chn3_cfg.configure(this, null, "");
        this.reg_chn3_cfg.build();
		this.reg_chn3_cfg.add_hdl_path_slice("timer_chn4_cap_filter_th_regs", 0, 8);
		this.reg_chn3_cfg.add_hdl_path_slice("timer_chn4_cap_edge_regs", 8, 2);
		this.reg_chn3_cfg.add_hdl_path_slice("timer_chn4_cmp_out_mode_regs", 10, 2);

        this.default_map.add_reg(this.reg_psc, 32'h00, "RW");
        this.default_map.add_reg(this.reg_atl, 32'h04, "RW");
        this.default_map.add_reg(this.reg_cnt, 32'h08, "RW");
        this.default_map.add_reg(this.reg_ctrl, 32'h0C, "RW");
        this.default_map.add_reg(this.reg_itr_en, 32'h10, "RW");
        this.default_map.add_reg(this.reg_itr_flag, 32'h14, "RW");
        this.default_map.add_reg(this.reg_chn0_v, 32'h18, "RW");
        this.default_map.add_reg(this.reg_chn0_cfg, 32'h1C, "RW");
        this.default_map.add_reg(this.reg_chn1_v, 32'h20, "RW");
        this.default_map.add_reg(this.reg_chn1_cfg, 32'h24, "RW");
        this.default_map.add_reg(this.reg_chn2_v, 32'h28, "RW");
        this.default_map.add_reg(this.reg_chn2_cfg, 32'h2C, "RW");
        this.default_map.add_reg(this.reg_chn3_v, 32'h30, "RW");
        this.default_map.add_reg(this.reg_chn3_cfg, 32'h34, "RW");
    endfunction

endclass

`endif
