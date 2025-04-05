onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_cool_down_cnt/dut/clk
add wave -noupdate /tb_cool_down_cnt/dut/rst_n
add wave -noupdate -radix unsigned /tb_cool_down_cnt/dut/cd
add wave -noupdate /tb_cool_down_cnt/dut/timer_trigger
add wave -noupdate /tb_cool_down_cnt/dut/timer_done
add wave -noupdate /tb_cool_down_cnt/dut/timer_ready
add wave -noupdate -radix unsigned /tb_cool_down_cnt/dut/timer_v
add wave -noupdate -radix unsigned /tb_cool_down_cnt/dut/cd_cnt
add wave -noupdate /tb_cool_down_cnt/dut/timer_ready_reg
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {481000 ps} 0}
quietly wave cursor active 1
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
WaveRestoreZoom {125645 ps} {332610 ps}
