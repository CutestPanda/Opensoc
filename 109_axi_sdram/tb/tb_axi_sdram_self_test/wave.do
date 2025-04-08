onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group self_test /tb_axi_sdram_self_test/sdram_selftest_u/clk
add wave -noupdate -expand -group self_test /tb_axi_sdram_self_test/sdram_selftest_u/rst_n
add wave -noupdate -expand -group self_test /tb_axi_sdram_self_test/sdram_selftest_u/self_test_start
add wave -noupdate -expand -group self_test /tb_axi_sdram_self_test/sdram_selftest_u/self_test_idle
add wave -noupdate -expand -group self_test /tb_axi_sdram_self_test/sdram_selftest_u/self_test_done
add wave -noupdate -expand -group self_test /tb_axi_sdram_self_test/sdram_selftest_u/self_test_res
add wave -noupdate -expand -group self_test /tb_axi_sdram_self_test/sdram_selftest_u/self_test_res_valid
add wave -noupdate -expand -group self_test -radix unsigned /tb_axi_sdram_self_test/sdram_selftest_u/waddr_cnt
add wave -noupdate -expand -group self_test -radix unsigned /tb_axi_sdram_self_test/sdram_selftest_u/wdata_cnt
add wave -noupdate -expand -group self_test -radix unsigned /tb_axi_sdram_self_test/sdram_selftest_u/wburst_cnt
add wave -noupdate -expand -group self_test -radix unsigned /tb_axi_sdram_self_test/sdram_selftest_u/raddr_cnt
add wave -noupdate -expand -group self_test -radix unsigned /tb_axi_sdram_self_test/sdram_selftest_u/rdata_cnt
add wave -noupdate -expand -group self_test -radix unsigned /tb_axi_sdram_self_test/sdram_selftest_u/rburst_cnt
add wave -noupdate -expand -group self_test /tb_axi_sdram_self_test/sdram_selftest_u/now_rd_burst_check_res
add wave -noupdate -expand -group self_test /tb_axi_sdram_self_test/sdram_selftest_u/now_rd_data_mismatch
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/ctrler_aclk
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/ctrler_aresetn
add wave -noupdate -expand -group axi_sdram_ctrler -radix unsigned /tb_axi_sdram_self_test/dut/s_axi_araddr
add wave -noupdate -expand -group axi_sdram_ctrler -radix unsigned /tb_axi_sdram_self_test/dut/s_axi_arlen
add wave -noupdate -expand -group axi_sdram_ctrler -radix binary /tb_axi_sdram_self_test/dut/s_axi_arsize
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/s_axi_arvalid
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/s_axi_arready
add wave -noupdate -expand -group axi_sdram_ctrler -radix unsigned /tb_axi_sdram_self_test/dut/s_axi_rdata
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/s_axi_rlast
add wave -noupdate -expand -group axi_sdram_ctrler -radix binary /tb_axi_sdram_self_test/dut/s_axi_rresp
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/s_axi_rvalid
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/s_axi_rready
add wave -noupdate -expand -group axi_sdram_ctrler -radix unsigned /tb_axi_sdram_self_test/dut/s_axi_awaddr
add wave -noupdate -expand -group axi_sdram_ctrler -radix unsigned /tb_axi_sdram_self_test/dut/s_axi_awlen
add wave -noupdate -expand -group axi_sdram_ctrler -radix binary /tb_axi_sdram_self_test/dut/s_axi_awsize
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/s_axi_awvalid
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/s_axi_awready
add wave -noupdate -expand -group axi_sdram_ctrler -radix unsigned /tb_axi_sdram_self_test/dut/s_axi_wdata
add wave -noupdate -expand -group axi_sdram_ctrler -radix binary /tb_axi_sdram_self_test/dut/s_axi_wstrb
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/s_axi_wlast
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/s_axi_wvalid
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/s_axi_wready
add wave -noupdate -expand -group axi_sdram_ctrler -radix binary /tb_axi_sdram_self_test/dut/s_axi_bresp
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/s_axi_bvalid
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/s_axi_bready
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/sdram_clk
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/sdram_cke
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/sdram_cs_n
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/sdram_ras_n
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/sdram_cas_n
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/sdram_we_n
add wave -noupdate -expand -group axi_sdram_ctrler -radix unsigned /tb_axi_sdram_self_test/dut/sdram_ba
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/sdram_addr
add wave -noupdate -expand -group axi_sdram_ctrler -radix binary /tb_axi_sdram_self_test/dut/sdram_dqm
add wave -noupdate -expand -group axi_sdram_ctrler -radix unsigned /tb_axi_sdram_self_test/dut/sdram_dq_i
add wave -noupdate -expand -group axi_sdram_ctrler -radix unsigned /tb_axi_sdram_self_test/dut/sdram_dq_o
add wave -noupdate -expand -group axi_sdram_ctrler /tb_axi_sdram_self_test/dut/sdram_dq_t
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {256152000 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 213
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
WaveRestoreZoom {9999420372 ps} {10000045222 ps}
