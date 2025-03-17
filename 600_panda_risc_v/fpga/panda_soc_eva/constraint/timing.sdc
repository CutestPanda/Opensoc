# 创建JTAG虚拟时钟
create_clock -period 1000.0 -name clock -waveform {0.000 500.0} [get_ports tck]

# 设置伪路径
set_false_path -from [get_cells {jtag_dtm_u/apb_clock_convert_u/req_at_slave}] -to [get_cells {jtag_dtm_u/apb_clock_convert_u/req_syn_u/dff_chain[0].dffs[0]}]
set_false_path -from [get_cells {jtag_dtm_u/apb_clock_convert_u/ack_at_master}] -to [get_cells {jtag_dtm_u/apb_clock_convert_u/ack_syn_u/dff_chain[0].dffs[0]}]
set_false_path -from [get_cells {jtag_dtm_u/apb_clock_convert_u/prdata_latched[*]}]
set_false_path -from [get_cells {jtag_dtm_u/apb_clock_convert_u/paddr_latched[*]}]
set_false_path -from [get_cells {jtag_dtm_u/apb_clock_convert_u/pwrite_latched}]
set_false_path -from [get_cells {jtag_dtm_u/apb_clock_convert_u/pwdata_latched[*]}]
set_false_path -from [get_cells {jtag_dtm_u/apb_clock_convert_u/prdata_latched[*]}]
