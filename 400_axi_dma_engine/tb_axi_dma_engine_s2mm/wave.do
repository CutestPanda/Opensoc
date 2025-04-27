onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/s_cmd_axis_aclk
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/s_cmd_axis_aresetn
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/cmd_done
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/s_cmd_axis_data
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/s_cmd_axis_user
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/s_cmd_axis_valid
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/s_cmd_axis_ready
add wave -noupdate -radix unsigned /tb_axi_dma_engine_s2mm/dut/s_s2mm_axis_data
add wave -noupdate -radix binary /tb_axi_dma_engine_s2mm/dut/s_s2mm_axis_keep
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/s_s2mm_axis_last
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/s_s2mm_axis_valid
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/s_s2mm_axis_ready
add wave -noupdate -radix unsigned /tb_axi_dma_engine_s2mm/dut/m_axi_awaddr
add wave -noupdate -radix binary /tb_axi_dma_engine_s2mm/dut/m_axi_awburst
add wave -noupdate -radix unsigned /tb_axi_dma_engine_s2mm/dut/m_axi_awlen
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/m_axi_awvalid
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/m_axi_awready
add wave -noupdate -radix hexadecimal /tb_axi_dma_engine_s2mm/dut/m_axi_wdata
add wave -noupdate -radix binary /tb_axi_dma_engine_s2mm/dut/m_axi_wstrb
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/m_axi_wlast
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/m_axi_wvalid
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/m_axi_wready
add wave -noupdate -radix binary /tb_axi_dma_engine_s2mm/dut/m_axi_bresp
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/m_axi_bvalid
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/m_axi_bready
add wave -noupdate -radix binary /tb_axi_dma_engine_s2mm/dut/err_flag
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/axis_aclk
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/axis_aresetn
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/s_s2mm_axis_data
add wave -noupdate -radix binary /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/s_s2mm_axis_keep
add wave -noupdate -radix unsigned /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/s_s2mm_axis_user
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/s_s2mm_axis_last
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/s_s2mm_axis_valid
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/s_s2mm_axis_ready
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/s_reg_slice_axis_data
add wave -noupdate -radix binary /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/s_reg_slice_axis_keep
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/s_reg_slice_axis_last
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/s_reg_slice_axis_valid
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/s_reg_slice_axis_ready
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/m_s2mm_axis_data
add wave -noupdate -radix binary /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/m_s2mm_axis_keep
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/m_s2mm_axis_last
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/m_s2mm_axis_valid
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/m_s2mm_axis_ready
add wave -noupdate -radix hexadecimal /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/reorg_data_buf
add wave -noupdate -radix binary /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/reorg_keep_buf
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/is_first_trans
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/is_last_trans
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/need_buf_hdat
add wave -noupdate /tb_axi_dma_engine_s2mm/dut/genblk4/dre_u/to_flush_buf
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {219596 ps} 0}
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
WaveRestoreZoom {93062 ps} {179772 ps}
