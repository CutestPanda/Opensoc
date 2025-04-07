onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/ctrler_aclk
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/ctrler_aresetn
add wave -noupdate -expand -group s_axi_if -radix unsigned /tb_axi_sdram/dut/s_axi_araddr
add wave -noupdate -expand -group s_axi_if -radix unsigned /tb_axi_sdram/dut/s_axi_arlen
add wave -noupdate -expand -group s_axi_if -radix binary /tb_axi_sdram/dut/s_axi_arsize
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/s_axi_arvalid
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/s_axi_arready
add wave -noupdate -expand -group s_axi_if -radix unsigned /tb_axi_sdram/dut/s_axi_rdata
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/s_axi_rlast
add wave -noupdate -expand -group s_axi_if -radix binary /tb_axi_sdram/dut/s_axi_rresp
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/s_axi_rvalid
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/s_axi_rready
add wave -noupdate -expand -group s_axi_if -radix unsigned /tb_axi_sdram/dut/s_axi_awaddr
add wave -noupdate -expand -group s_axi_if -radix unsigned /tb_axi_sdram/dut/s_axi_awlen
add wave -noupdate -expand -group s_axi_if -radix binary /tb_axi_sdram/dut/s_axi_awsize
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/s_axi_awvalid
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/s_axi_awready
add wave -noupdate -expand -group s_axi_if -radix unsigned /tb_axi_sdram/dut/s_axi_wdata
add wave -noupdate -expand -group s_axi_if -radix binary /tb_axi_sdram/dut/s_axi_wstrb
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/s_axi_wlast
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/s_axi_wvalid
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/s_axi_wready
add wave -noupdate -expand -group s_axi_if -radix binary /tb_axi_sdram/dut/s_axi_bresp
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/s_axi_bvalid
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/s_axi_bready
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/m_axis_usr_cmd_data
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/m_axis_usr_cmd_user
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/m_axis_usr_cmd_valid
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/m_axis_usr_cmd_ready
add wave -noupdate -expand -group s_axi_if -radix unsigned /tb_axi_sdram/dut/m_axis_wt_data
add wave -noupdate -expand -group s_axi_if -radix binary /tb_axi_sdram/dut/m_axis_wt_keep
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/m_axis_wt_last
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/m_axis_wt_valid
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/m_axis_wt_ready
add wave -noupdate -expand -group s_axi_if -radix unsigned /tb_axi_sdram/dut/s_axis_rd_data
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/s_axis_rd_last
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/s_axis_rd_valid
add wave -noupdate -expand -group s_axi_if /tb_axi_sdram/dut/s_axis_rd_ready
add wave -noupdate -group sdram_if /tb_axi_sdram/dut/sdram_clk
add wave -noupdate -group sdram_if /tb_axi_sdram/dut/sdram_cke
add wave -noupdate -group sdram_if /tb_axi_sdram/dut/sdram_cs_n
add wave -noupdate -group sdram_if /tb_axi_sdram/dut/sdram_ras_n
add wave -noupdate -group sdram_if /tb_axi_sdram/dut/sdram_cas_n
add wave -noupdate -group sdram_if /tb_axi_sdram/dut/sdram_we_n
add wave -noupdate -group sdram_if -radix unsigned /tb_axi_sdram/dut/sdram_ba
add wave -noupdate -group sdram_if /tb_axi_sdram/dut/sdram_addr
add wave -noupdate -group sdram_if -radix binary /tb_axi_sdram/dut/sdram_dqm
add wave -noupdate -group sdram_if -radix unsigned /tb_axi_sdram/dut/sdram_dq_i
add wave -noupdate -group sdram_if -radix unsigned /tb_axi_sdram/dut/sdram_dq_o
add wave -noupdate -group sdram_if /tb_axi_sdram/dut/sdram_dq_t
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {92000 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 180
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
WaveRestoreZoom {0 ps} {271973 ps}
