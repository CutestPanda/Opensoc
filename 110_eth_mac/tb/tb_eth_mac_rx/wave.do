onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_eth_mac_rx/dut/m_axis_aclk
add wave -noupdate /tb_eth_mac_rx/dut/m_axis_aresetn
add wave -noupdate /tb_eth_mac_rx/dut/eth_rx_aclk
add wave -noupdate /tb_eth_mac_rx/dut/eth_rx_aresetn
add wave -noupdate /tb_eth_mac_rx/dut/broadcast_accept
add wave -noupdate /tb_eth_mac_rx/dut/unicast_filter_mac
add wave -noupdate /tb_eth_mac_rx/dut/multicast_filter_mac_0
add wave -noupdate /tb_eth_mac_rx/dut/multicast_filter_mac_1
add wave -noupdate /tb_eth_mac_rx/dut/multicast_filter_mac_2
add wave -noupdate /tb_eth_mac_rx/dut/multicast_filter_mac_3
add wave -noupdate /tb_eth_mac_rx/dut/eth_rx_data
add wave -noupdate /tb_eth_mac_rx/dut/eth_rx_valid
add wave -noupdate /tb_eth_mac_rx/dut/m_axis_data
add wave -noupdate -radix binary /tb_eth_mac_rx/dut/m_axis_keep
add wave -noupdate /tb_eth_mac_rx/dut/m_axis_last
add wave -noupdate /tb_eth_mac_rx/dut/m_axis_valid
add wave -noupdate /tb_eth_mac_rx/dut/eth_frame_wen
add wave -noupdate /tb_eth_mac_rx/dut/eth_frame_full_n
add wave -noupdate -radix binary /tb_eth_mac_rx/dut/eth_frame_wptr_at_w
add wave -noupdate -radix binary /tb_eth_mac_rx/dut/eth_frame_rptr_at_w
add wave -noupdate -radix binary /tb_eth_mac_rx/dut/ping_pong_ram_wen_a
add wave -noupdate -radix unsigned /tb_eth_mac_rx/dut/ping_pong_ram_addr_a
add wave -noupdate /tb_eth_mac_rx/dut/ping_pong_ram_din_a
add wave -noupdate /tb_eth_mac_rx/dut/eth_frame_ren
add wave -noupdate /tb_eth_mac_rx/dut/eth_frame_empty_n
add wave -noupdate -radix binary /tb_eth_mac_rx/dut/eth_frame_wptr_at_r
add wave -noupdate -radix binary /tb_eth_mac_rx/dut/eth_frame_rptr_at_r
add wave -noupdate -radix binary /tb_eth_mac_rx/dut/ping_pong_ram_ren_b
add wave -noupdate -radix unsigned /tb_eth_mac_rx/dut/ping_pong_ram_addr_b
add wave -noupdate /tb_eth_mac_rx/dut/ping_pong_ram_dout_b
add wave -noupdate /tb_eth_mac_rx/dut/frame_buf_rsel
add wave -noupdate -radix unsigned /tb_eth_mac_rx/dut/frame_buf_raddr
add wave -noupdate /tb_eth_mac_rx/dut/frame_buf_ren_d1
add wave -noupdate /tb_eth_mac_rx/dut/frame_buf_dout_to_mask
add wave -noupdate /tb_eth_mac_rx/dut/frame_buf_dout_hw
add wave -noupdate /tb_eth_mac_rx/dut/frame_buf_dout_both_vld
add wave -noupdate /tb_eth_mac_rx/dut/frame_buf_dout_last
add wave -noupdate /tb_eth_mac_rx/dut/frame_buf_dout_vld
add wave -noupdate -radix unsigned /tb_eth_mac_rx/dut/eth_frame_id_out_r
add wave -noupdate /tb_eth_mac_rx/dut/eth_frame_data_out_r
add wave -noupdate -radix binary /tb_eth_mac_rx/dut/eth_frame_keep_out_r
add wave -noupdate /tb_eth_mac_rx/dut/eth_frame_last_out_r
add wave -noupdate /tb_eth_mac_rx/dut/eth_frame_valid_out_r
add wave -noupdate /tb_eth_mac_rx/dut/frame_buf_extra_wen
add wave -noupdate -radix binary /tb_eth_mac_rx/dut/eth_rx_sts
add wave -noupdate -radix unsigned /tb_eth_mac_rx/dut/eth_rx_field_byte_cnt
add wave -noupdate -radix unsigned /tb_eth_mac_rx/dut/eth_rx_timeout_cnt
add wave -noupdate /tb_eth_mac_rx/dut/frame_buf_wsel
add wave -noupdate /tb_eth_mac_rx/dut/eth_rx_timeout_flag
add wave -noupdate -radix unsigned /tb_eth_mac_rx/dut/frame_buf_waddr
add wave -noupdate -radix unsigned /tb_eth_mac_rx/dut/frame_buf_waddr_sub5
add wave -noupdate /tb_eth_mac_rx/dut/eth_rx_latest_6byte
add wave -noupdate /tb_eth_mac_rx/dut/eth_rx_dst_mac
add wave -noupdate /tb_eth_mac_rx/dut/eth_rx_crc32
add wave -noupdate /tb_eth_mac_rx/dut/eth_crc32_cal
add wave -noupdate /tb_eth_mac_rx/dut/eth_crc32_for_validate
add wave -noupdate /tb_eth_mac_rx/dut/eth_crc32_for_validate_latest4
add wave -noupdate /tb_eth_mac_rx/dut/eth_rx_dst_mac_accept
add wave -noupdate /tb_eth_mac_rx/dut/eth_rx_frame_len_agree
add wave -noupdate /tb_eth_mac_rx/dut/eth_rx_crc32_validated
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {313490 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 185
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
WaveRestoreZoom {284092 ps} {338371 ps}
