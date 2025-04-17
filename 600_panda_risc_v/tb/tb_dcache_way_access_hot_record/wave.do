onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_dcache_way_access_hot_record/dut/aclk
add wave -noupdate /tb_dcache_way_access_hot_record/dut/aresetn
add wave -noupdate /tb_dcache_way_access_hot_record/dut/hot_tb_en
add wave -noupdate /tb_dcache_way_access_hot_record/dut/hot_tb_upd_en
add wave -noupdate -radix unsigned /tb_dcache_way_access_hot_record/dut/cache_index
add wave -noupdate -radix binary /tb_dcache_way_access_hot_record/dut/to_init_hot_item
add wave -noupdate -radix binary /tb_dcache_way_access_hot_record/dut/to_swp_lru_item
add wave -noupdate -radix unsigned /tb_dcache_way_access_hot_record/dut/cache_access_wid
add wave -noupdate -radix unsigned /tb_dcache_way_access_hot_record/dut/hot_tb_lru_wid
add wave -noupdate /tb_dcache_way_access_hot_record/dut/hot_sram_clk_a
add wave -noupdate /tb_dcache_way_access_hot_record/dut/hot_sram_wen_a
add wave -noupdate -radix unsigned /tb_dcache_way_access_hot_record/dut/hot_sram_waddr_a
add wave -noupdate -radix binary /tb_dcache_way_access_hot_record/dut/hot_sram_din_a
add wave -noupdate /tb_dcache_way_access_hot_record/dut/hot_sram_clk_b
add wave -noupdate /tb_dcache_way_access_hot_record/dut/hot_sram_ren_b
add wave -noupdate -radix unsigned /tb_dcache_way_access_hot_record/dut/hot_sram_raddr_b
add wave -noupdate -radix binary /tb_dcache_way_access_hot_record/dut/hot_sram_dout_b
add wave -noupdate /tb_dcache_way_access_hot_record/dut/hot_tb_wen
add wave -noupdate -radix unsigned /tb_dcache_way_access_hot_record/dut/hot_tb_upd_eid
add wave -noupdate -radix unsigned /tb_dcache_way_access_hot_record/dut/hot_tb_upd_wid
add wave -noupdate -radix binary /tb_dcache_way_access_hot_record/dut/to_init_hot_item_r
add wave -noupdate -radix binary /tb_dcache_way_access_hot_record/dut/to_swp_lru_item_r
add wave -noupdate -radix binary /tb_dcache_way_access_hot_record/dut/hot_tb_dout
add wave -noupdate -radix binary /tb_dcache_way_access_hot_record/dut/hot_code_new
add wave -noupdate /tb_dcache_way_access_hot_record/dut/sel_hot_code_new
add wave -noupdate -radix binary /tb_dcache_way_access_hot_record/dut/hot_code_new_d1
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
WaveRestoreZoom {0 ps} {1 ns}
