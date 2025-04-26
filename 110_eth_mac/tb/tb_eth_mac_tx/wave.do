onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/s_axis_aclk
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/s_axis_aresetn
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/eth_tx_aclk
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/eth_tx_aresetn
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/s_axis_data
add wave -noupdate -expand -group dut -radix binary /tb_eth_mac_tx/dut/s_axis_keep
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/s_axis_last
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/s_axis_valid
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/s_axis_ready
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/eth_tx_data
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/eth_tx_valid
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/eth_frame_wen
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/eth_frame_full_n
add wave -noupdate -expand -group dut -radix binary /tb_eth_mac_tx/dut/eth_frame_wptr_at_w
add wave -noupdate -expand -group dut -radix binary /tb_eth_mac_tx/dut/eth_frame_rptr_at_w
add wave -noupdate -expand -group dut -radix binary /tb_eth_mac_tx/dut/ping_pong_ram_wen_a
add wave -noupdate -expand -group dut -radix unsigned /tb_eth_mac_tx/dut/ping_pong_ram_addr_a
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/ping_pong_ram_din_a
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/eth_frame_ren
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/eth_frame_empty_n
add wave -noupdate -expand -group dut -radix binary /tb_eth_mac_tx/dut/eth_frame_wptr_at_r
add wave -noupdate -expand -group dut -radix binary /tb_eth_mac_tx/dut/eth_frame_rptr_at_r
add wave -noupdate -expand -group dut -radix binary /tb_eth_mac_tx/dut/ping_pong_ram_ren_b
add wave -noupdate -expand -group dut -radix unsigned /tb_eth_mac_tx/dut/ping_pong_ram_addr_b
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/ping_pong_ram_dout_b
add wave -noupdate -expand -group dut -radix unsigned /tb_eth_mac_tx/dut/eth_frame_buf_waddr
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/ifg_cd_trigger
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/ifg_cd_ready
add wave -noupdate -expand -group dut -radix binary /tb_eth_mac_tx/dut/eth_tx_sts
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/to_padding_eth_frame
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/to_padding_eth_frame_d1
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/at_padding_boundary
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/exceed_padding_boundary
add wave -noupdate -expand -group dut -radix unsigned /tb_eth_mac_tx/dut/eth_tx_field_cnt
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/ping_pong_ram_dout_sel
add wave -noupdate -expand -group dut -radix unsigned /tb_eth_mac_tx/dut/eth_frame_buf_raddr
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/eth_fbuf_rdata
add wave -noupdate -expand -group dut -radix unsigned /tb_eth_mac_tx/dut/eth_byte_strm_field
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/eth_byte_sel
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/eth_byte_strm_oen
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/eth_tx_byte_cur
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/eth_tx_last_dw_flag
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/eth_tx_dw_both_vld_flag
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/eth_crc32
add wave -noupdate -expand -group dut -radix unsigned /tb_eth_mac_tx/dut/eth_crc32_byte_sel
add wave -noupdate -expand -group dut -radix unsigned /tb_eth_mac_tx/dut/eth_byte_strm_field_cur
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/eth_byte_strm_valid
add wave -noupdate -expand -group dut -radix binary /tb_eth_mac_tx/dut/early_crc32_flag
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/eth_tx_data_r
add wave -noupdate -expand -group dut /tb_eth_mac_tx/dut/eth_tx_valid_r
add wave -noupdate -expand -group crc32 /tb_eth_mac_tx/dut/crc32_d8_u/clk
add wave -noupdate -expand -group crc32 /tb_eth_mac_tx/dut/crc32_d8_u/rst_n
add wave -noupdate -expand -group crc32 /tb_eth_mac_tx/dut/crc32_d8_u/data
add wave -noupdate -expand -group crc32 /tb_eth_mac_tx/dut/crc32_d8_u/crc_en
add wave -noupdate -expand -group crc32 /tb_eth_mac_tx/dut/crc32_d8_u/crc_clr
add wave -noupdate -expand -group crc32 /tb_eth_mac_tx/dut/crc32_d8_u/crc_data
add wave -noupdate -expand -group crc32 /tb_eth_mac_tx/dut/crc32_d8_u/crc_next
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {305613 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 199
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
WaveRestoreZoom {210403 ps} {726833 ps}
