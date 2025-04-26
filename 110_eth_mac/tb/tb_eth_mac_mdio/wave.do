onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_eth_mac_mdio/dut/aclk
add wave -noupdate /tb_eth_mac_mdio/dut/aresetn
add wave -noupdate -radix unsigned /tb_eth_mac_mdio/dut/mdc_div_rate
add wave -noupdate /tb_eth_mac_mdio/dut/mdio_access_start
add wave -noupdate /tb_eth_mac_mdio/dut/mdio_access_is_rd
add wave -noupdate /tb_eth_mac_mdio/dut/mdio_access_addr
add wave -noupdate -radix binary /tb_eth_mac_mdio/dut/mdio_access_wdata
add wave -noupdate /tb_eth_mac_mdio/dut/mdio_access_idle
add wave -noupdate -radix binary /tb_eth_mac_mdio/dut/mdio_access_rdata
add wave -noupdate /tb_eth_mac_mdio/dut/mdio_access_done
add wave -noupdate /tb_eth_mac_mdio/dut/mdc
add wave -noupdate /tb_eth_mac_mdio/dut/mdio_i
add wave -noupdate /tb_eth_mac_mdio/dut/mdio_o
add wave -noupdate /tb_eth_mac_mdio/dut/mdio_t
add wave -noupdate /tb_eth_mac_mdio/dut/mdc_en
add wave -noupdate -radix unsigned /tb_eth_mac_mdio/dut/mdc_div_cnt
add wave -noupdate /tb_eth_mac_mdio/dut/mdc_to_rise
add wave -noupdate /tb_eth_mac_mdio/dut/mdc_to_fall
add wave -noupdate /tb_eth_mac_mdio/dut/mdc_r
add wave -noupdate -radix unsigned /tb_eth_mac_mdio/dut/mdio_cnt
add wave -noupdate /tb_eth_mac_mdio/dut/mdio_is_rd_trans
add wave -noupdate /tb_eth_mac_mdio/dut/mdio_trans_data
add wave -noupdate /tb_eth_mac_mdio/dut/mdio_to_sample
add wave -noupdate -radix binary /tb_eth_mac_mdio/dut/mdio_rdata
add wave -noupdate /tb_eth_mac_mdio/dut/mdio_o_r
add wave -noupdate /tb_eth_mac_mdio/dut/mdio_t_r
add wave -noupdate /tb_eth_mac_mdio/dut/mdio_access_idle_r
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1501000 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 169
configure wave -valuecolwidth 135
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
WaveRestoreZoom {1198172 ps} {1623829 ps}
