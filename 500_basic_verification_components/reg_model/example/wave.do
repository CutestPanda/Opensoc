onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_apb_timer/dut/clk
add wave -noupdate /tb_apb_timer/dut/resetn
add wave -noupdate -group APB -radix hexadecimal /tb_apb_timer/dut/paddr
add wave -noupdate -group APB /tb_apb_timer/dut/psel
add wave -noupdate -group APB /tb_apb_timer/dut/penable
add wave -noupdate -group APB /tb_apb_timer/dut/pwrite
add wave -noupdate -group APB /tb_apb_timer/dut/pwdata
add wave -noupdate -group APB /tb_apb_timer/dut/pready_out
add wave -noupdate -group APB /tb_apb_timer/dut/prdata_out
add wave -noupdate -group APB /tb_apb_timer/dut/pslverr_out
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/prescale_regs
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/autoload_regs
add wave -noupdate -group REGS /tb_apb_timer/dut/regs_if_for_timer_u/timer_cnt_to_set_reg
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/timer_cnt_set_v_regs
add wave -noupdate -group REGS /tb_apb_timer/dut/regs_if_for_timer_u/timer_started_reg
add wave -noupdate -group REGS /tb_apb_timer/dut/regs_if_for_timer_u/in_encoder_mode_reg
add wave -noupdate -group REGS -radix binary /tb_apb_timer/dut/regs_if_for_timer_u/cap_cmp_sel_regs
add wave -noupdate -group REGS -radix binary /tb_apb_timer/dut/regs_if_for_timer_u/cmp_oen_regs
add wave -noupdate -group REGS /tb_apb_timer/dut/regs_if_for_timer_u/global_itr_en
add wave -noupdate -group REGS /tb_apb_timer/dut/regs_if_for_timer_u/timer_expired_itr_en
add wave -noupdate -group REGS -radix binary /tb_apb_timer/dut/regs_if_for_timer_u/timer_cap_itr_en
add wave -noupdate -group REGS -radix binary /tb_apb_timer/dut/regs_if_for_timer_u/org_itr_req_vec
add wave -noupdate -group REGS /tb_apb_timer/dut/regs_if_for_timer_u/org_global_itr_req
add wave -noupdate -group REGS /tb_apb_timer/dut/regs_if_for_timer_u/global_itr_flag
add wave -noupdate -group REGS /tb_apb_timer/dut/regs_if_for_timer_u/timer_expired_itr_flag
add wave -noupdate -group REGS /tb_apb_timer/dut/regs_if_for_timer_u/timer_cap_itr_flag
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/timer_chn1_cmp_regs
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/timer_chn1_cap_filter_th_regs
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/timer_chn1_cap_edge_regs
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/timer_chn1_cmp_out_mode_regs
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/timer_chn2_cmp_regs
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/timer_chn2_cap_filter_th_regs
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/timer_chn2_cap_edge_regs
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/timer_chn2_cmp_out_mode_regs
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/timer_chn3_cmp_regs
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/timer_chn3_cap_filter_th_regs
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/timer_chn3_cap_edge_regs
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/timer_chn3_cmp_out_mode_regs
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/timer_chn4_cmp_regs
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/timer_chn4_cap_filter_th_regs
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/timer_chn4_cap_edge_regs
add wave -noupdate -group REGS -radix unsigned /tb_apb_timer/dut/regs_if_for_timer_u/timer_chn4_cmp_out_mode_regs
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1301000 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 231
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
WaveRestoreZoom {1095032 ps} {1264547 ps}
