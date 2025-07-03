onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_panda_risc_v_ibus_ctrler/dut/aclk
add wave -noupdate /tb_panda_risc_v_ibus_ctrler/dut/aresetn
add wave -noupdate -expand -group ctrl_sts /tb_panda_risc_v_ibus_ctrler/dut/clr_inst_buf
add wave -noupdate -expand -group ctrl_sts /tb_panda_risc_v_ibus_ctrler/dut/suppressing_ibus_access
add wave -noupdate -expand -group ctrl_sts /tb_panda_risc_v_ibus_ctrler/dut/clr_inst_buf_while_suppressing
add wave -noupdate -expand -group ctrl_sts /tb_panda_risc_v_ibus_ctrler/dut/ibus_timeout
add wave -noupdate -expand -group req -radix unsigned /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_req_addr
add wave -noupdate -expand -group req -radix unsigned /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_req_tid
add wave -noupdate -expand -group req -radix unsigned /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_req_extra_msg
add wave -noupdate -expand -group req /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_req_valid
add wave -noupdate -expand -group req /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_req_ready
add wave -noupdate -expand -group resp -radix unsigned /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_resp_rdata
add wave -noupdate -expand -group resp -radix binary /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_resp_err
add wave -noupdate -expand -group resp -radix unsigned /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_resp_addr
add wave -noupdate -expand -group resp -radix unsigned /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_resp_tid
add wave -noupdate -expand -group resp -radix unsigned /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_resp_extra_msg
add wave -noupdate -expand -group resp /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_resp_pre_decoding_msg
add wave -noupdate -expand -group resp /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_resp_valid
add wave -noupdate -expand -group resp /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_resp_ready
add wave -noupdate -expand -group m_icb -radix unsigned /tb_panda_risc_v_ibus_ctrler/dut/m_icb_cmd_addr
add wave -noupdate -expand -group m_icb /tb_panda_risc_v_ibus_ctrler/dut/m_icb_cmd_valid
add wave -noupdate -expand -group m_icb /tb_panda_risc_v_ibus_ctrler/dut/m_icb_cmd_ready
add wave -noupdate -expand -group m_icb -radix unsigned /tb_panda_risc_v_ibus_ctrler/dut/m_icb_rsp_rdata
add wave -noupdate -expand -group m_icb /tb_panda_risc_v_ibus_ctrler/dut/m_icb_rsp_err
add wave -noupdate -expand -group m_icb /tb_panda_risc_v_ibus_ctrler/dut/m_icb_rsp_valid
add wave -noupdate -expand -group m_icb /tb_panda_risc_v_ibus_ctrler/dut/m_icb_rsp_ready
add wave -noupdate /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_addr_unaligned_flag
add wave -noupdate /tb_panda_risc_v_ibus_ctrler/dut/waiting_icb_resp
add wave -noupdate -radix unsigned /tb_panda_risc_v_ibus_ctrler/dut/ibus_timeout_cnt
add wave -noupdate /tb_panda_risc_v_ibus_ctrler/dut/ibus_timeout_flag
add wave -noupdate -radix binary /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_sts
add wave -noupdate /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_suppress_flag
add wave -noupdate -radix unsigned /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_addr
add wave -noupdate -radix unsigned /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_tid
add wave -noupdate -radix unsigned /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_data
add wave -noupdate -radix binary /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_err
add wave -noupdate -radix unsigned /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_req_wptr
add wave -noupdate -radix unsigned /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_cmd_rptr
add wave -noupdate -radix unsigned /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_resp_wptr
add wave -noupdate -radix unsigned /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_ack_rptr
add wave -noupdate -radix binary /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_buf_empty_vec
add wave -noupdate -radix binary /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_buf_wait_resp_vec
add wave -noupdate -radix unsigned /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_req_wptr_copy
add wave -noupdate -radix binary /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_resp_vec
add wave -noupdate -radix binary /tb_panda_risc_v_ibus_ctrler/dut/ibus_access_suppress_vec
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {131000 ps} 0}
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
WaveRestoreZoom {5175 ps} {316825 ps}
