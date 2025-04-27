onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/s_axis_aclk
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/s_axis_aresetn
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/m_axis_aclk
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/m_axis_aresetn
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/m_axi_aclk
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/m_axi_aresetn
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/cmd_done
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/s_cmd_axis_data
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/s_cmd_axis_user
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/s_cmd_axis_last
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/s_cmd_axis_valid
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/s_cmd_axis_ready
add wave -noupdate -radix hexadecimal /tb_axi_dma_engine_mm2s/dut/m_mm2s_axis_data
add wave -noupdate -radix binary /tb_axi_dma_engine_mm2s/dut/m_mm2s_axis_keep
add wave -noupdate -radix binary /tb_axi_dma_engine_mm2s/dut/m_mm2s_axis_user
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/m_mm2s_axis_last
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/m_mm2s_axis_valid
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/m_mm2s_axis_ready
add wave -noupdate -radix unsigned /tb_axi_dma_engine_mm2s/dut/m_axi_araddr
add wave -noupdate -radix binary /tb_axi_dma_engine_mm2s/dut/m_axi_arburst
add wave -noupdate -radix unsigned /tb_axi_dma_engine_mm2s/dut/m_axi_arlen
add wave -noupdate -radix binary /tb_axi_dma_engine_mm2s/dut/m_axi_arsize
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/m_axi_arvalid
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/m_axi_arready
add wave -noupdate -radix hexadecimal /tb_axi_dma_engine_mm2s/dut/m_axi_rdata
add wave -noupdate -radix binary /tb_axi_dma_engine_mm2s/dut/m_axi_rresp
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/m_axi_rlast
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/m_axi_rvalid
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/m_axi_rready
add wave -noupdate -radix unsigned /tb_axi_dma_engine_mm2s/dut/in_cmd_btt
add wave -noupdate -radix unsigned /tb_axi_dma_engine_mm2s/dut/in_cmd_baseaddr
add wave -noupdate -radix unsigned /tb_axi_dma_engine_mm2s/dut/in_cmd_trm_addr
add wave -noupdate -radix unsigned /tb_axi_dma_engine_mm2s/dut/in_cmd_trans_n
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/in_cmd_fixed
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/in_cmd_eof
add wave -noupdate -radix binary /tb_axi_dma_engine_mm2s/dut/in_cmd_first_keep
add wave -noupdate -radix binary /tb_axi_dma_engine_mm2s/dut/in_cmd_last_keep
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/in_cmd_valid
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/in_cmd_ready
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/burst_msg_fifo_full_n
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/rdata_buf_full_n
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/last_burst_of_req
add wave -noupdate -radix binary /tb_axi_dma_engine_mm2s/dut/first_keep_of_req
add wave -noupdate -radix binary /tb_axi_dma_engine_mm2s/dut/last_keep_of_req
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/eof_flag
add wave -noupdate -radix binary /tb_axi_dma_engine_mm2s/dut/ar_ctrl_sts
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/rmn_tn_sub1
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/rmn_tn_sub1_at_4KB
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/araddr
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/arburst
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/arlen
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/arvalid
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/min_cmp_en
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/min_cmp_op_a
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/min_cmp_op_b
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/min_cmp_a_leq_b
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/min_cmp_res
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/min_cmp_a_leq_b_pre
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/s_dre_axis_data
add wave -noupdate -radix binary /tb_axi_dma_engine_mm2s/dut/s_dre_axis_keep
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/s_dre_axis_last
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/s_dre_axis_valid
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/s_dre_axis_ready
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/dre_u/s_reg_slice_axis_data
add wave -noupdate -radix binary /tb_axi_dma_engine_mm2s/dut/dre_u/s_reg_slice_axis_keep
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/dre_u/s_reg_slice_axis_last
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/dre_u/s_reg_slice_axis_valid
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/dre_u/s_reg_slice_axis_ready
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/m_dre_axis_data
add wave -noupdate -radix binary /tb_axi_dma_engine_mm2s/dut/m_dre_axis_keep
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/m_dre_axis_last
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/m_dre_axis_valid
add wave -noupdate /tb_axi_dma_engine_mm2s/dut/m_dre_axis_ready
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {229644 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 191
configure wave -valuecolwidth 129
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
WaveRestoreZoom {131292 ps} {166635 ps}
