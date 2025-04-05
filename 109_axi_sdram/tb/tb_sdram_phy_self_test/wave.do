onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/clk
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/rst_n
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/s_axis_wt_data
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/s_axis_wt_keep
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/s_axis_wt_last
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/s_axis_wt_valid
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/s_axis_wt_ready
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/m_axis_rd_data
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/m_axis_rd_last
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/m_axis_rd_valid
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/m_axis_rd_ready
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/s_axis_usr_cmd_data
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/s_axis_usr_cmd_user
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/s_axis_usr_cmd_valid
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/s_axis_usr_cmd_ready
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/pcg_spcf_idle_bank_err
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/pcg_spcf_bank_tot_err
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/rw_idle_bank_err
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/rfs_with_act_banks_err
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/illegal_logic_cmd_err
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/rw_cross_line_err
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/ld_when_wdata_ext_fifo_empty_err
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/st_when_rdata_ext_fifo_full_err
add wave -noupdate -group sdram_ctrler /tb_sdram_phy_self_test/dut/rfs_timeout
add wave -noupdate -expand -group sdram_if /tb_sdram_phy_self_test/dut/sdram_clk
add wave -noupdate -expand -group sdram_if /tb_sdram_phy_self_test/dut/sdram_cke
add wave -noupdate -expand -group sdram_if /tb_sdram_phy_self_test/dut/sdram_cs_n
add wave -noupdate -expand -group sdram_if /tb_sdram_phy_self_test/dut/sdram_ras_n
add wave -noupdate -expand -group sdram_if /tb_sdram_phy_self_test/dut/sdram_cas_n
add wave -noupdate -expand -group sdram_if /tb_sdram_phy_self_test/dut/sdram_we_n
add wave -noupdate -expand -group sdram_if -radix unsigned /tb_sdram_phy_self_test/dut/sdram_ba
add wave -noupdate -expand -group sdram_if -radix binary /tb_sdram_phy_self_test/dut/sdram_addr
add wave -noupdate -expand -group sdram_if -radix binary /tb_sdram_phy_self_test/dut/sdram_dqm
add wave -noupdate -expand -group sdram_if -radix unsigned /tb_sdram_phy_self_test/dut/sdram_dq_i
add wave -noupdate -expand -group sdram_if -radix unsigned /tb_sdram_phy_self_test/dut/sdram_dq_o
add wave -noupdate -expand -group sdram_if /tb_sdram_phy_self_test/dut/sdram_dq_t
add wave -noupdate -group sdram_selftest /tb_sdram_phy_self_test/sdram_selftest_u/clk
add wave -noupdate -group sdram_selftest /tb_sdram_phy_self_test/sdram_selftest_u/rst_n
add wave -noupdate -group sdram_selftest /tb_sdram_phy_self_test/sdram_selftest_u/self_test_start
add wave -noupdate -group sdram_selftest /tb_sdram_phy_self_test/sdram_selftest_u/self_test_idle
add wave -noupdate -group sdram_selftest /tb_sdram_phy_self_test/sdram_selftest_u/self_test_done
add wave -noupdate -group sdram_selftest -radix binary /tb_sdram_phy_self_test/sdram_selftest_u/self_test_res
add wave -noupdate -group sdram_selftest /tb_sdram_phy_self_test/sdram_selftest_u/self_test_res_valid
add wave -noupdate -group sdram_selftest -radix unsigned /tb_sdram_phy_self_test/sdram_selftest_u/wt_burst_cnt
add wave -noupdate -group sdram_selftest -radix unsigned /tb_sdram_phy_self_test/sdram_selftest_u/rd_burst_cnt
add wave -noupdate -expand -group cmd_agent /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/clk
add wave -noupdate -expand -group cmd_agent /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/rst_n
add wave -noupdate -expand -group cmd_agent -radix binary /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/m_axis_cmd_data
add wave -noupdate -expand -group cmd_agent /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/m_axis_cmd_user
add wave -noupdate -expand -group cmd_agent /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/m_axis_cmd_valid
add wave -noupdate -expand -group cmd_agent /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/m_axis_cmd_ready
add wave -noupdate -expand -group cmd_agent /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/new_burst_start
add wave -noupdate -expand -group cmd_agent /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/is_write_burst
add wave -noupdate -expand -group cmd_agent /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/new_burst_len
add wave -noupdate -expand -group cmd_agent -radix binary /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/bank_active_same_cd_trigger
add wave -noupdate -expand -group cmd_agent -radix binary /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/bank_active_diff_cd_trigger
add wave -noupdate -expand -group cmd_agent -radix binary /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/bank_active_to_rw_itv_trigger
add wave -noupdate -expand -group cmd_agent -radix binary /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/bank_precharge_itv_trigger
add wave -noupdate -expand -group cmd_agent -radix binary /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/bank_precharge_same_cd_trigger
add wave -noupdate -expand -group cmd_agent /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/refresh_busy_n
add wave -noupdate -expand -group cmd_agent /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/auto_precharge_busy_n
add wave -noupdate -expand -group cmd_agent /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/auto_precharge_itv_done
add wave -noupdate -expand -group cmd_agent /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/bank_active_same_cd_ready
add wave -noupdate -expand -group cmd_agent /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/bank_active_diff_cd_ready
add wave -noupdate -expand -group cmd_agent /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/bank_active_to_rw_itv_ready
add wave -noupdate -expand -group cmd_agent /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/bank_precharge_itv_done
add wave -noupdate -expand -group cmd_agent -radix binary /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/bank_precharge_itv_ready
add wave -noupdate -expand -group cmd_agent -radix binary /tb_sdram_phy_self_test/dut/axis_sdram_cmd_agent_u/bank_precharge_same_cd_ready
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {31020203278 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 228
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {31019972916 ps} {31020193565 ps}
