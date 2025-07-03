onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_panda_risc_v_ras/dut/aclk
add wave -noupdate /tb_panda_risc_v_ras/dut/aresetn
add wave -noupdate /tb_panda_risc_v_ras/dut/ras_push_req
add wave -noupdate -radix unsigned /tb_panda_risc_v_ras/dut/ras_push_addr
add wave -noupdate /tb_panda_risc_v_ras/dut/ras_pop_req
add wave -noupdate -radix unsigned /tb_panda_risc_v_ras/dut/ras_pop_addr
add wave -noupdate /tb_panda_risc_v_ras/dut/ras_query_req
add wave -noupdate -radix unsigned /tb_panda_risc_v_ras/dut/ras_query_addr
add wave -noupdate -radix unsigned /tb_panda_risc_v_ras/dut/ras_reg_file
add wave -noupdate -radix unsigned /tb_panda_risc_v_ras/dut/ras_top_ptr
add wave -noupdate -radix unsigned /tb_panda_risc_v_ras/dut/ras_bot_ptr
add wave -noupdate /tb_panda_risc_v_ras/dut/ras_empty
add wave -noupdate /tb_panda_risc_v_ras/dut/ras_full
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 150
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
WaveRestoreZoom {9999050 ps} {10000050 ps}
