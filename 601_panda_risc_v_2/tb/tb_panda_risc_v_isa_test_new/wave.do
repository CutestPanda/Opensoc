onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/aclk
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/aresetn
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/sys_reset_req
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/rst_pc
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/flush_req
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ifu_exclusive_flush_req
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/flush_addr
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/rst_ack
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/flush_ack
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/m_icb_cmd_inst_addr
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/m_icb_cmd_inst_valid
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/m_icb_cmd_inst_ready
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/m_icb_rsp_inst_rdata
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/m_icb_rsp_inst_valid
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/m_icb_rsp_inst_ready
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/suppressing_ibus_access
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/clr_inst_buf_while_suppressing
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_timeout
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_req_addr
add wave -noupdate -group ifu -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_req_tid
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_req_extra_msg
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_req_valid
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_req_ready
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_resp_rdata
add wave -noupdate -group ifu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_resp_err
add wave -noupdate -group ifu -radix hexadecimal /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_resp_addr
add wave -noupdate -group ifu -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_resp_tid
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_resp_valid
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_resp_ready
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/aclk
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/aresetn
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/sys_reset_req
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/flush_req
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/flush_addr
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/rst_ack
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/flush_ack
add wave -noupdate -group ifu -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/m_if_res_id
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/m_if_res_valid
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/m_if_res_ready
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/suppressing_ibus_access
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/clr_inst_buf_while_suppressing
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_timeout
add wave -noupdate -group ifu -radix hexadecimal /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_req_addr
add wave -noupdate -group ifu -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_req_tid
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_req_valid
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_req_ready
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_resp_rdata
add wave -noupdate -group ifu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_resp_err
add wave -noupdate -group ifu -radix hexadecimal /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_resp_addr
add wave -noupdate -group ifu -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_resp_tid
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_resp_valid
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_resp_ready
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/on_need_flush
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/correct_npc
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/on_start_flush
add wave -noupdate -group ifu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/flush_pending
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/aclk
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/aresetn
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/sys_reset_req
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/flush_req
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/flush_addr
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/rst_ack
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/flush_ack
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/clr_inst_buf
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/ibus_access_req_addr
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/ibus_access_req_tid
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/ibus_access_req_valid
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/ibus_access_req_ready
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_bdcst_tid
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_bdcst_vld
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_iftc_vld
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_iftc_tid
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_iftc_is_b_inst
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_iftc_is_jal_inst
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_iftc_is_jalr_inst
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_iftc_bta
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_luc_vld
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_luc_tid
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_luc_is_b_inst
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_luc_is_jal_inst
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_luc_is_jalr_inst
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_luc_bta
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/glb_brc_prdt_on_clr_retired_ghr
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/glb_brc_prdt_on_upd_retired_ghr
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/glb_brc_prdt_retired_ghr_shift_in
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/glb_brc_prdt_rstr_speculative_ghr
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/glb_brc_prdt_upd_i_req
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/glb_brc_prdt_upd_i_pc
add wave -noupdate -group pre_if -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/glb_brc_prdt_upd_i_ghr
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/glb_brc_prdt_upd_i_brc_taken
add wave -noupdate -group pre_if -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/glb_brc_prdt_retired_ghr_o
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_rplc_req
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_rplc_strgy
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_rplc_sel_wid
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_rplc_pc
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_rplc_btype
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_rplc_bta
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_rplc_jpdir
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_rplc_push_ras
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_rplc_pop_ras
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_unit_initializing
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_i_req
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_i_pc
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_i_nxt_pc
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_i_tid
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_vld
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_pc
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_brc_type
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_push_ras
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_pop_ras
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_taken
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_btb_hit
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_btb_wid
add wave -noupdate -group pre_if -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_btb_wvld
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_btb_bta
add wave -noupdate -group pre_if -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_glb_speculative_ghr
add wave -noupdate -group pre_if -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_glb_2bit_sat_cnt
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_tid
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/first_inst_flag
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/inst_id
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/rst_pre_if_pending
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/flush_pre_if_pending
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/common_pre_if_pending
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_hit_jalr_pending
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_hit_jalr_bdcst_gotten
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/to_rst
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/to_flush
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/flush_addr_saved
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/flush_addr_cur
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_addr_cur
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/pc_nxt
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/pc_r
add wave -noupdate -group pre_if -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/bdcst_bta_saved
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_prdt_u/ras_push_req
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_prdt_u/ras_push_addr
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_prdt_u/ras_pop_req
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_prdt_u/ras_query_req
add wave -noupdate -group pre_if /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_prdt_u/ras_query_addr
add wave -noupdate -group flush_ctrl /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/aclk
add wave -noupdate -group flush_ctrl /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/aresetn
add wave -noupdate -group flush_ctrl /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/sys_reset_req
add wave -noupdate -group flush_ctrl /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/glb_brc_prdt_on_clr_retired_ghr
add wave -noupdate -group flush_ctrl /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/glb_brc_prdt_rstr_speculative_ghr
add wave -noupdate -group flush_ctrl /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/bru_flush_req
add wave -noupdate -group flush_ctrl /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/bru_flush_addr
add wave -noupdate -group flush_ctrl /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/bru_flush_grant
add wave -noupdate -group flush_ctrl /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/cmt_flush_req
add wave -noupdate -group flush_ctrl /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/cmt_flush_addr
add wave -noupdate -group flush_ctrl /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/cmt_flush_grant
add wave -noupdate -group flush_ctrl /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/suppressing_ibus_access
add wave -noupdate -group flush_ctrl /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/global_flush_req
add wave -noupdate -group flush_ctrl /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/global_flush_addr
add wave -noupdate -group flush_ctrl /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/global_flush_ack
add wave -noupdate -group flush_ctrl /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/global_flush_pending
add wave -noupdate -group flush_ctrl /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/sel_bru_flush
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/aclk
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/aresetn
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_permitted_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/init_mem_bus_tr_store_inst_tid
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/clr_wr_mem_buf
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_access_permitted_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/init_perph_bus_tr_ls_inst_tid
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/cancel_subseq_perph_access
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/s_req_ls_sel
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/s_req_ls_type
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/s_req_rd_id_for_ld
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/s_req_ls_addr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/s_req_ls_din
add wave -noupdate -group lsu -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/s_req_lsu_inst_id
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/s_req_ls_mem_access
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/s_req_valid
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/s_req_ready
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_resp_ls_sel
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_resp_rd_id_for_ld
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_resp_dout_ls_addr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_resp_err
add wave -noupdate -group lsu -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_resp_lsu_inst_id
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_resp_valid
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_resp_ready
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_araddr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_arburst
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_arlen
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_arsize
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_arvalid
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_arready
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_rdata
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_rresp
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_rlast
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_rvalid
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_rready
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_awaddr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_awburst
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_awlen
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_awsize
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_awvalid
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_awready
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_bresp
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_bvalid
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_bready
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_wdata
add wave -noupdate -group lsu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_wstrb
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_wlast
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_wvalid
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_mem_wready
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_araddr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_arburst
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_arlen
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_arsize
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_arvalid
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_arready
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_rdata
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_rresp
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_rlast
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_rvalid
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_rready
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_awaddr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_awburst
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_awlen
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_awsize
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_awvalid
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_awready
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_bresp
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_bvalid
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_bready
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_wdata
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_wstrb
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_wlast
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_wvalid
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_axi_perph_wready
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/has_buffered_wr_mem_req
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/has_processing_perph_access_req
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_timeout
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_timeout
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_access_timeout
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_submit_new_wr_mem_req
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/is_allowed_to_submit_new_wr_mem_req
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_req_table_entry_wptr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_req_table_age_wptr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/aligned_addr_of_new_wr_mem_req
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wdata_of_new_wr_mem_req
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wmask_of_new_wr_mem_req
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/inst_id_of_new_wr_mem_req
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/is_vld_entry_in_wr_mem_req_table
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_wr_mem_req_permitted_to_bus
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_new_wr_mem_req_permitted_directly
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/permitting_wr_mem_req_entry_ptr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/permitting_wr_mem_req_age_ptr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_create_new_wr_mem_trans_record
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_req_table_sel_entry_onehot_id_of_creating_new_wr_mem_trans_record
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_req_table_sel_entry_bin_id_of_creating_new_wr_mem_trans_record
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/aligned_addr_of_creating_new_wr_mem_trans_record
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wdata_of_creating_new_wr_mem_trans_record
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wmask_of_creating_new_wr_mem_trans_record
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/new_wr_mem_trans_mergeable_onehot
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/creating_new_wr_mem_trans_entry_sel
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_trans_table_entry_wptr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_trans_to_be_initiated_cnt
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/has_wr_mem_trans_to_be_initiated
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_trans_detained_cnt
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_initiate_wr_mem_trans
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_complete_wr_mem_trans
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/aligned_addr_of_completed_wr_mem_trans
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/record_onehot_id_of_completed_wr_mem_trans
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_trans_addr_setup_ptr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_trans_data_transfer_ptr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/completed_wr_mem_trans_onehot_ptr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/completed_wr_mem_trans_bin_ptr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_timeout_cnt
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_timeout_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_req_table_aligned_addr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_req_table_wdata
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_req_table_wmask
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_req_table_inst_id
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_req_table_age_tbit
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_req_table_bonding_tr_record_onehot_id
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_req_table_vld_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_req_table_permitted_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_req_table_trans_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_req_table_vld_flag_nxt
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_trans_table_aligned_addr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_trans_table_wdata
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_trans_table_wmask
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_trans_table_vld_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_trans_table_trans_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_trans_table_addr_setup_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_trans_table_data_sent_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_initiate_rd_mem_trans
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/new_rd_mem_trans_org_addr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/new_rd_mem_trans_req_id
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/is_allowed_to_submit_new_rd_mem_req
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_initiate_wr_mem_buf_check
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/org_addr_for_wr_mem_buf_check
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/req_id_for_wr_mem_buf_check
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_return_wr_mem_buf_check_res
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/merging_data_of_wr_mem_buf_check_res
add wave -noupdate -group lsu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/merging_mask_of_wr_mem_buf_check_res
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/req_id_of_wr_mem_buf_check_res
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_trans_waiting_wr_mem_buf_check_res_ptr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_trans_wptr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_trans_addr_setup_ptr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_trans_waiting_resp_ptr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_trans_vld_cnt
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_trans_full_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_timeout_cnt
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_timeout_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_rd_mem_timeout
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_complete_rd_mem_trans
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_upd_req_entry_of_rd_mem_trans
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/req_id_of_completed_rd_mem_trans
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rdata_of_completed_rd_mem_trans
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/err_code_of_completed_rd_mem_trans
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_trans_table_org_addr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_trans_table_req_id
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_trans_table_vld_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_trans_table_check_done_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_trans_table_addr_setup_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_buf_entry_vld_flag_foreach_byte
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_buf_check_modified_byte_mask
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_buf_finding_newest_mdf_s0_vld_vec
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_buf_finding_newest_mdf_s0_age_tbit
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_buf_finding_newest_mdf_s0_id
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_buf_finding_newest_mdf_s1_vld_vec
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_buf_finding_newest_mdf_s1_age_tbit
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_buf_finding_newest_mdf_s1_id
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_buf_finding_newest_mdf_s2_vld_vec
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_buf_finding_newest_mdf_s2_age_tbit
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_buf_finding_newest_mdf_s2_id
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_buf_finding_newest_mdf_s3_vld_vec
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_buf_finding_newest_mdf_s3_age_tbit
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_buf_finding_newest_mdf_s3_id
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_buf_finding_newest_mdf_s4_vld_vec
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_buf_finding_newest_mdf_s4_id
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_buf_check_newest_mdf_entry_id_foreach_byte
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/wr_mem_req_table_wdata_d1
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/req_id_for_wr_mem_buf_check_d1
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_initiate_wr_mem_buf_check_d1
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_initiate_perph_trans
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/new_perph_trans_req_id
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/new_perph_trans_is_write_access
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_trans_aligned_addr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_trans_is_write_access
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_trans_wdata
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_trans_wmask
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_trans_req_id
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_trans_pending
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_complete_addr_setup_of_perph_trans
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_complete_wdata_sending_of_perph_trans
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_complete_resp_recv_of_perph_trans
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_trans_addr_setup
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_trans_wdata_sent
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_trans_req_id_entended
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_trans_timeout_cnt_clr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_trans_timeout_cnt_ce
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_trans_timeout_cnt
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_trans_timeout_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_perph_trans_timeout
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_get_perph_trans_res
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_trans_res_rdata
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_trans_res_err_code
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_access_req_table_req_id
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_access_req_table_wptr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_access_req_table_trans_ptr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_access_req_table_wptr_nxt
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_access_req_table_trans_ptr_nxt
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_access_req_table_empty_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/perph_access_req_table_full_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_launch_or_ignore_perph_access
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/cur_launching_perph_access_req_id
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/is_new_req_addr_unaligned
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/has_req_with_unaligned_addr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/store_din_pre_processed
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/store_wmask_pre_processed
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_ls_type_for_pos_prcs
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_ls_addr_for_pos_prcs
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_rdata_org_for_pos_prcs
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_rdata_algn_for_pos_prcs
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_mem_rdata_final_for_pos_prcs
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_perph_ls_type_for_pos_prcs
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_perph_ls_addr_for_pos_prcs
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_perph_rdata_org_for_pos_prcs
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_perph_rdata_algn_for_pos_prcs
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/rd_perph_rdata_final_for_pos_prcs
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/vld_entry_n_in_req_buf
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/req_buf_empty_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/req_buf_full_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/ls_req_wptr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/ls_res_rptr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/on_retiring_ls_req
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/ls_req_table_is_store
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/ls_req_table_is_mem_access
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/ls_req_table_ls_type
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/ls_req_table_rd_id_for_ld
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/ls_req_table_ls_addr
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/ls_req_table_ls_data
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/ls_req_table_merging_data
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/ls_req_table_byte_mask
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/ls_req_table_inst_id
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/ls_req_table_err_code
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/ls_req_table_vld_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/ls_req_table_permitted_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/ls_req_table_cancel_flag
add wave -noupdate -group lsu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/ls_req_table_completed_flag
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/aclk
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/aresetn
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/in_dbg_mode
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/rst_bru
add wave -noupdate -group bru -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/jal_inst_n_acpt
add wave -noupdate -group bru -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/jal_prdt_success_inst_n
add wave -noupdate -group bru -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/jalr_inst_n_acpt
add wave -noupdate -group bru -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/jalr_prdt_success_inst_n
add wave -noupdate -group bru -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/b_inst_n_acpt
add wave -noupdate -group bru -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/b_prdt_success_inst_n
add wave -noupdate -group bru -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/common_inst_n_acpt
add wave -noupdate -group bru -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/common_prdt_success_inst_n
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/bru_flush_req
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/bru_flush_addr
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/bru_flush_grant
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/s_bru_i_tid
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/s_bru_i_valid
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/s_bru_i_ready
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/m_bru_o_tid
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/m_bru_o_nxt_pc
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/m_bru_o_b_inst_res
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/m_bru_o_valid
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/is_brc_inst
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/prdt_success
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/actual_bta
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/nxt_seq_pc
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/prdt_jmp_addr
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/actual_jmp_addr
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/is_fence_i_inst
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/is_ebreak_inst
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/need_flush
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/flush_addr_cur
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/bru_flush_pending
add wave -noupdate -group bru /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/bru_flush_addr_gen
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/aclk
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/aresetn
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/cmt_flush_req
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/cmt_flush_addr
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/cmt_flush_grant
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_clr
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_vld
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_saved
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_err
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_is_csr_rw_inst
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_spec_inst_type
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_cancel
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_fu_res
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_pc
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_nxt_pc
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_b_inst_res
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_rtr_bdcst_vld
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_rtr_bdcst_excpt_proc_grant
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/inst_retire_cnt_en
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/mstatus_mie_v
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/mie_msie_v
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/mie_mtie_v
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/mie_meie_v
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/sw_itr_req_i
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/tmr_itr_req_i
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/ext_itr_req_i
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/itr_expt_enter
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/itr_expt_is_intr
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/itr_expt_cause
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/itr_expt_vec_baseaddr
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/itr_expt_ret_addr
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/itr_expt_val
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/itr_expt_ret
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/mepc_ret_addr
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/in_trap
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/dbg_mode_enter
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/dbg_mode_cause
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/dbg_mode_ret_addr
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/dbg_mode_ret
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/dpc_ret_addr
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/dbg_halt_req
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/dbg_halt_on_reset_req
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/dcsr_ebreakm_v
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/dcsr_step_v
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/in_dbg_mode
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/glb_brc_prdt_on_upd_retired_ghr
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/glb_brc_prdt_retired_ghr_shift_in
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/glb_brc_prdt_upd_i_req
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/glb_brc_prdt_upd_i_pc
add wave -noupdate -group commit -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/glb_brc_prdt_upd_i_ghr
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/glb_brc_prdt_upd_i_brc_taken
add wave -noupdate -group commit /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/glb_brc_prdt_retired_ghr_o
add wave -noupdate -group wr_bck /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/rob_prep_rtr_entry_rd_id
add wave -noupdate -group wr_bck /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/rob_prep_rtr_entry_is_csr_rw_inst
add wave -noupdate -group wr_bck /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/rob_prep_rtr_entry_cancel
add wave -noupdate -group wr_bck /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/rob_prep_rtr_entry_fu_res
add wave -noupdate -group wr_bck /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/rob_prep_rtr_entry_csr_rw_waddr
add wave -noupdate -group wr_bck /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/rob_prep_rtr_entry_csr_rw_upd_type
add wave -noupdate -group wr_bck /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/rob_prep_rtr_entry_csr_rw_upd_mask_v
add wave -noupdate -group wr_bck /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_pc
add wave -noupdate -group wr_bck /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/rob_rtr_bdcst_vld
add wave -noupdate -group wr_bck /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/rob_rtr_bdcst_excpt_proc_grant
add wave -noupdate -group wr_bck /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/reg_file_wen
add wave -noupdate -group wr_bck -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/reg_file_waddr
add wave -noupdate -group wr_bck -radix hexadecimal /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/reg_file_din
add wave -noupdate -group wr_bck /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/csr_atom_waddr
add wave -noupdate -group wr_bck /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/csr_atom_upd_type
add wave -noupdate -group wr_bck /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/csr_atom_upd_mask_v
add wave -noupdate -group wr_bck /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/csr_atom_wen
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/aclk
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/aresetn
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_icb_cmd_inst_addr
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_icb_cmd_inst_valid
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_icb_cmd_inst_ready
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_icb_rsp_inst_rdata
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_icb_rsp_inst_err
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_icb_rsp_inst_valid
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_icb_rsp_inst_ready
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_axi_dmem_araddr
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_axi_dmem_arvalid
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_axi_dmem_arready
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_axi_dmem_rdata
add wave -noupdate -group biu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_axi_dmem_rresp
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_axi_dmem_rvalid
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_axi_dmem_rready
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_axi_dmem_awaddr
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_axi_dmem_awvalid
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_axi_dmem_awready
add wave -noupdate -group biu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_axi_dmem_bresp
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_axi_dmem_bvalid
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_axi_dmem_bready
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_axi_dmem_wdata
add wave -noupdate -group biu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_axi_dmem_wstrb
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_axi_dmem_wlast
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_axi_dmem_wvalid
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/s_axi_dmem_wready
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_araddr
add wave -noupdate -group biu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_arburst
add wave -noupdate -group biu -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_arlen
add wave -noupdate -group biu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_arsize
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_arvalid
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_arready
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_rdata
add wave -noupdate -group biu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_rresp
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_rlast
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_rvalid
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_rready
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_awaddr
add wave -noupdate -group biu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_awburst
add wave -noupdate -group biu -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_awlen
add wave -noupdate -group biu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_awsize
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_awvalid
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_awready
add wave -noupdate -group biu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_bresp
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_bvalid
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_bready
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_wdata
add wave -noupdate -group biu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_wstrb
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_wlast
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_wvalid
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_imem_wready
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_araddr
add wave -noupdate -group biu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_arburst
add wave -noupdate -group biu -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_arlen
add wave -noupdate -group biu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_arsize
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_arvalid
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_arready
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_rdata
add wave -noupdate -group biu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_rresp
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_rlast
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_rvalid
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_rready
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_awaddr
add wave -noupdate -group biu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_awburst
add wave -noupdate -group biu -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_awlen
add wave -noupdate -group biu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_awsize
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_awvalid
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_awready
add wave -noupdate -group biu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_bresp
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_bvalid
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_bready
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_wdata
add wave -noupdate -group biu -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_wstrb
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_wlast
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_wvalid
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/m_axi_dmem_wready
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/imem_rd_access_msg_fifo_wen
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/imem_rd_access_msg_fifo_din_initiated_by_ibus
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/imem_rd_access_msg_fifo_din_rdata_buf_id
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/imem_rd_access_msg_fifo_din_word_sel
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/imem_rd_access_msg_fifo_full_n
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/imem_rd_access_msg_fifo_ren
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/imem_rd_access_msg_fifo_dout_initiated_by_ibus
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/imem_rd_access_msg_fifo_dout_rdata_buf_id
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/imem_rd_access_msg_fifo_dout_word_sel
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/imem_rd_access_msg_fifo_empty_n
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dmem_rd_access_msg_fifo_wen
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dmem_rd_access_msg_fifo_din_rdata_buf_id
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dmem_rd_access_msg_fifo_full_n
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dmem_rd_access_msg_fifo_ren
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dmem_rd_access_msg_fifo_dout_rdata_buf_id
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dmem_rd_access_msg_fifo_empty_n
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dbus_rd_chn_buf_rdata
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dbus_rd_chn_buf_rresp
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dbus_rd_chn_buf_filled_flag
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dbus_rd_chn_buf_wptr
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dbus_rd_chn_buf_rptr
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dbus_rd_chn_buf_vld_entry_n
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dbus_rd_chn_buf_full_flag
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dbus_rd_chn_fall_into_inst_region
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/imem_rd_access_req_from_ibus
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/imem_rd_access_req_from_dbus
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/imem_rd_access_instant_arb_res
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/imem_rd_access_grant_to_ibus
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/imem_rd_access_arb_locked_flag
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/imem_rd_access_locked_arb_res
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/imem_rd_access_grant_to_ibus_if_conflict
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dbus_wr_trans_table_to_access_inst_region
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dbus_wr_trans_table_vld_flag
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dbus_wr_trans_table_wdata_sent_flag
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dbus_wr_trans_table_vld_entry_n
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dbus_wr_trans_table_full_flag
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dbus_wr_trans_table_empty_flag
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dbus_wr_trans_addr_setup_ptr
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dbus_wr_trans_sending_wdata_ptr
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dbus_wr_trans_waiting_resp_ptr
add wave -noupdate -group biu /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/biu_u/dbus_wr_chn_fall_into_inst_region
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/aclk
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/aresetn
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_araddr
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_arburst
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_arlen
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_arsize
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_arvalid
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_arready
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_rdata
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_rlast
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_rresp
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_rvalid
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_rready
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_awaddr
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_awburst
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_awlen
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_awsize
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_awvalid
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_awready
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_bresp
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_bvalid
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_bready
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_wdata
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_wlast
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_wstrb
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_wvalid
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/s_axi_wready
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/tcm_clka
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/tcm_rsta
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/tcm_ena
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/tcm_wena
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/tcm_addra
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/tcm_dina
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/tcm_douta
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/tcm_clkb
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/tcm_rstb
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/tcm_enb
add wave -noupdate -group imem_ctrler -radix binary /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/tcm_wenb
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/tcm_addrb
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/tcm_dinb
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/tcm_doutb
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/rvalid_r
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/awaddr_latched
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/is_aw_content_latched
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/wdata_latched
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/wmask_latched
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/is_w_content_latched
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/mem_wr_s0_valid
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/mem_wr_s0_ready
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/mem_wr_s1_valid
add wave -noupdate -group imem_ctrler /tb_isa_test/panda_risc_v_sim_u/tcm_ctrler_u0/mem_wr_s1_ready
add wave -noupdate -group pref -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/jal_inst_n_acpt_r
add wave -noupdate -group pref -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/jal_prdt_success_inst_n_r
add wave -noupdate -group pref -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/jalr_inst_n_acpt_r
add wave -noupdate -group pref -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/jalr_prdt_success_inst_n_r
add wave -noupdate -group pref -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/b_inst_n_acpt_r
add wave -noupdate -group pref -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/b_prdt_success_inst_n_r
add wave -noupdate -group pref -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/common_inst_n_acpt_r
add wave -noupdate -group pref -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/bru_u/common_prdt_success_inst_n_r
add wave -noupdate -group pref -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/csr_u/mcycleh_mcycleh
add wave -noupdate -group pref -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/csr_u/mcycle_mcycle
add wave -noupdate -group pref -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/csr_u/minstreth_minstreth
add wave -noupdate -group pref -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/csr_u/minstret_minstret
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/aclk
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/aresetn
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/sys_reset_req
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/flush_req
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rob_full_n
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rob_csr_rw_inst_allowed
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rob_entry_id_to_be_written
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rob_entry_age_tbit_to_be_written
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/fu_res_data
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/fu_res_tid
add wave -noupdate -group op_pre_fetch -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/fu_res_vld
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/s_regs_rd_data
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/s_regs_rd_msg
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/s_regs_rd_id
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/s_regs_rd_is_first_inst_after_rst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/s_regs_rd_valid
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/s_regs_rd_ready
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq0_inst_id
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq0_fuid
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq0_rob_entry_id
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq0_age_tag
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq0_op1_lsn_fuid
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq0_op2_lsn_fuid
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq0_op1_lsn_inst_id
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq0_op2_lsn_inst_id
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq0_other_payload
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq0_op1_pre_fetched
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq0_op2_pre_fetched
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq0_op1_rdy
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq0_op2_rdy
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq0_valid
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq0_ready
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq1_inst_id
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq1_fuid
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq1_rob_entry_id
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq1_age_tag
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq1_op1_lsn_fuid
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq1_op2_lsn_fuid
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq1_op1_lsn_inst_id
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq1_op2_lsn_inst_id
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq1_other_payload
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq1_op1_pre_fetched
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq1_op2_pre_fetched
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq1_op1_rdy
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq1_op2_rdy
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq1_valid
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/m_wr_iq1_ready
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op1_ftc_rs1_id
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op1_ftc_from_reg_file
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op1_ftc_from_rob
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op1_ftc_from_byp
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op1_ftc_fuid
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op1_ftc_tid
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op1_ftc_rob_saved_data
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op2_ftc_rs2_id
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op2_ftc_from_reg_file
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op2_ftc_from_rob
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op2_ftc_from_byp
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op2_ftc_fuid
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op2_ftc_tid
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op2_ftc_rob_saved_data
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rob_luc_bdcst_vld
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rob_luc_bdcst_tid
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rob_luc_bdcst_fuid
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rob_luc_bdcst_rd_id
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rob_luc_bdcst_is_ls_inst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rob_luc_bdcst_is_csr_rw_inst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rob_luc_bdcst_csr_rw_inst_msg
add wave -noupdate -group op_pre_fetch -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rob_luc_bdcst_err
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rob_luc_bdcst_spec_inst_type
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rob_luc_bdcst_is_b_inst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rob_luc_bdcst_pc
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rob_luc_bdcst_nxt_pc
add wave -noupdate -group op_pre_fetch -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rob_luc_bdcst_org_2bit_sat_cnt
add wave -noupdate -group op_pre_fetch -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rob_luc_bdcst_bhr
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/reg_file_raddr_p0
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/reg_file_dout_p0
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/reg_file_raddr_p1
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/reg_file_dout_p1
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/fu_res_data_r
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/fu_res_tid_r
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/fu_res_vld_r
add wave -noupdate -group op_pre_fetch -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/fu_res_tid_match_op1_vec
add wave -noupdate -group op_pre_fetch -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/fu_res_tid_match_op2_vec
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/is_b_inst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/is_csr_rw_inst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/is_load_inst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/is_store_inst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/is_lui_inst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/is_auipc_inst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/is_csr_rw_imm_inst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/is_arth_imm_inst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/is_ecall_inst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/is_mret_inst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/is_ebreak_inst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/is_dret_inst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/is_illegal_inst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rs1_vld
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rs2_vld
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/rd_vld
add wave -noupdate -group op_pre_fetch -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/ls_type
add wave -noupdate -group op_pre_fetch -radix decimal /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/ls_ofs_imm
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/mul_res_sel
add wave -noupdate -group op_pre_fetch -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/mul_div_op_a_unsigned
add wave -noupdate -group op_pre_fetch -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/mul_div_op_b_unsigned
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/mul_div_res_sel
add wave -noupdate -group op_pre_fetch -radix hexadecimal /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/csr_addr
add wave -noupdate -group op_pre_fetch -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/csr_upd_type
add wave -noupdate -group op_pre_fetch -radix hexadecimal /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/csr_upd_imm
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/alu_op_mode
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/alu_op1
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/alu_op2
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/nxt_seq_pc
add wave -noupdate -group op_pre_fetch -radix decimal /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/brc_jump_ofs
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/actual_bta
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/dcd_res_inst_type_packeted
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/need_op1
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/need_op2
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op1_prefetched
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op2_prefetched
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op1_pftc_success
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op2_pftc_success
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op1_stage_regs_raw_dpc
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/op2_stage_regs_raw_dpc
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_inst_id
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_fuid
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_rd_id
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_op1_lsn_fuid
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_op2_lsn_fuid
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_op1_lsn_inst_id
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_op2_lsn_inst_id
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_op1_pre_fetched
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_op2_pre_fetched
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_op1_rdy
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_op2_rdy
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_other_payload
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_is_ls_inst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_is_csr_rw_inst
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_is_b_inst
add wave -noupdate -group op_pre_fetch -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_spec_inst_type
add wave -noupdate -group op_pre_fetch -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_csr_upd_type
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_pc
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_nxt_pc
add wave -noupdate -group op_pre_fetch -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_payload_err_code
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/instant_op1_pre_fetched
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/instant_op2_pre_fetched
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/instant_op1_rdy
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/instant_op2_rdy
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_valid
add wave -noupdate -group op_pre_fetch /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/op_pre_fetch_u/stage_regs_ready
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/aclk
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/aresetn
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/clr_iq0
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/clr_iq1
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/has_buffered_wr_mem_req
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/has_processing_perph_access_req
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/fu_res_data
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/fu_res_tid
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/fu_res_vld
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_bru_o_tid
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_bru_o_valid
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/bru_nominal_res_vld
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/bru_nominal_res_tid
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/bru_nominal_res
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq0_inst_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq0_fuid
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq0_rob_entry_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq0_age_tag
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq0_op1_lsn_fuid
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq0_op2_lsn_fuid
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq0_op1_lsn_inst_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq0_op2_lsn_inst_id
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq0_other_payload
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq0_op1_pre_fetched
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq0_op2_pre_fetched
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq0_op1_rdy
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq0_op2_rdy
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq0_valid
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq0_ready
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq1_inst_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq1_fuid
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq1_rob_entry_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq1_age_tag
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq1_op1_lsn_fuid
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq1_op2_lsn_fuid
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq1_op1_lsn_inst_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq1_op2_lsn_inst_id
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq1_other_payload
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq1_op1_pre_fetched
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq1_op2_pre_fetched
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq1_op1_rdy
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq1_op2_rdy
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq1_valid
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/s_wr_iq1_ready
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/brc_bdcst_luc_vld
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/brc_bdcst_luc_tid
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/brc_bdcst_luc_is_b_inst
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/brc_bdcst_luc_is_jal_inst
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/brc_bdcst_luc_is_jalr_inst
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/brc_bdcst_luc_bta
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/saving_csr_rw_msg_upd_mask_v
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/saving_csr_rw_msg_rob_entry_id
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/saving_csr_rw_msg_vld
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/on_upd_rob_field_nxt_pc
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/inst_id_of_upd_rob_field_nxt_pc
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/rob_field_nxt_pc
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_alu_op_mode
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_alu_op1
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_alu_op2
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_alu_tid
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_alu_use_res
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_alu_valid
add wave -noupdate -group issue_queue -radix hexadecimal /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_csr_addr
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_csr_tid
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_csr_valid
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_mul_op_a
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_mul_op_b
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_mul_res_sel
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_mul_rd_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_mul_inst_id
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_mul_valid
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_mul_ready
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_div_op_a
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_div_op_b
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_div_rem_sel
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_div_rd_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_div_inst_id
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_div_valid
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_div_ready
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_lsu_ls_sel
add wave -noupdate -group issue_queue -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_lsu_ls_type
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_lsu_rd_id_for_ld
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_lsu_ls_addr
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_lsu_ls_din
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_lsu_inst_id
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_lsu_valid
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_lsu_ready
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_bru_prdt_msg
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_bru_inst_type
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_bru_tid
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_bru_prdt_suc
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_bru_brc_cond_res
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_bru_valid
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/m_bru_ready
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/fu_res_data_r
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/fu_res_tid_r
add wave -noupdate -group issue_queue -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/fu_res_vld_r
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_table_inst_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_table_fuid
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_table_rob_entry_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_table_age_tag
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_table_op1_lsn_fuid
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_table_op2_lsn_fuid
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_table_op1_lsn_inst_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_table_op2_lsn_inst_id
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_table_other_payload
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_table_op1_saved
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_table_op2_saved
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_table_op1_rdy_flag
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_table_op2_rdy_flag
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_table_vld_flag
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/is_iq0_full_n
add wave -noupdate -group issue_queue -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_entry_to_wr_onehot
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/is_iq0_empty_n
add wave -noupdate -group issue_queue -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_fu_ready_flag
add wave -noupdate -group issue_queue -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_issue_allowed_flag
add wave -noupdate -group issue_queue -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_op1_instant_rdy_flag
add wave -noupdate -group issue_queue -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_op2_instant_rdy_flag
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_instant_op1
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_instant_op2
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_issue_arb_s0_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_issue_arb_s0_age_tag
add wave -noupdate -group issue_queue -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_issue_arb_s0_vld_flag
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_issue_arb_s1_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_issue_arb_s1_age_tag
add wave -noupdate -group issue_queue -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_issue_arb_s1_vld_flag
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_issue_arb_s2_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_issue_arb_s2_age_tag
add wave -noupdate -group issue_queue -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_issue_arb_s2_vld_flag
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_issue_arb_s3_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_issue_arb_s3_age_tag
add wave -noupdate -group issue_queue -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_issue_arb_s3_vld_flag
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_issue_arb_fnl_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_issue_arb_fnl_age_tag
add wave -noupdate -group issue_queue -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq0_issue_arb_fnl_vld_flag
add wave -noupdate -group issue_queue -radix unsigned -childformat {{{/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_inst_id[0]} -radix unsigned} {{/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_inst_id[1]} -radix unsigned} {{/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_inst_id[2]} -radix unsigned} {{/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_inst_id[3]} -radix unsigned}} -subitemconfig {{/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_inst_id[0]} {-height 15 -radix unsigned} {/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_inst_id[1]} {-height 15 -radix unsigned} {/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_inst_id[2]} {-height 15 -radix unsigned} {/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_inst_id[3]} {-height 15 -radix unsigned}} /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_inst_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_fuid
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_rob_entry_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_age_tag
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_op1_lsn_fuid
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_op2_lsn_fuid
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_op1_lsn_inst_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_op2_lsn_inst_id
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_other_payload
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_op1_saved
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_op2_saved
add wave -noupdate -group issue_queue -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_actual_brc_direction_saved
add wave -noupdate -group issue_queue -radix binary -childformat {{{/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_op1_rdy_flag[3]} -radix binary} {{/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_op1_rdy_flag[2]} -radix binary} {{/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_op1_rdy_flag[1]} -radix binary} {{/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_op1_rdy_flag[0]} -radix binary}} -subitemconfig {{/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_op1_rdy_flag[3]} {-height 15 -radix binary} {/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_op1_rdy_flag[2]} {-height 15 -radix binary} {/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_op1_rdy_flag[1]} {-height 15 -radix binary} {/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_op1_rdy_flag[0]} {-height 15 -radix binary}} /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_op1_rdy_flag
add wave -noupdate -group issue_queue -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_op2_rdy_flag
add wave -noupdate -group issue_queue -radix binary -childformat {{{/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_vld_flag[3]} -radix binary} {{/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_vld_flag[2]} -radix binary} {{/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_vld_flag[1]} -radix binary} {{/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_vld_flag[0]} -radix binary}} -subitemconfig {{/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_vld_flag[3]} {-height 15 -radix binary} {/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_vld_flag[2]} {-height 15 -radix binary} {/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_vld_flag[1]} {-height 15 -radix binary} {/tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_vld_flag[0]} {-height 15 -radix binary}} /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_table_vld_flag
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/is_iq1_full_n
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_wptr
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/is_iq1_empty_n
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_fu_ready_flag
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_rptr
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_pending_ebreak_fence_i_inst_id
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_pending_for_ebreak_fence_i_inst
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_fence_inst_allowed
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_inst_launched
add wave -noupdate -group issue_queue -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_op1_instant_rdy_flag
add wave -noupdate -group issue_queue -radix binary /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_op2_instant_rdy_flag
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_instant_op1
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_instant_op2
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_confirming_brc_inst_entry_id
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_confirming_brc_inst_inst_id
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/has_confirming_brc_inst_in_iq1
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_pending_for_brc_prdt_failure
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_is_confirming_brc_inst_classified_as_spec_case_0
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_actual_bta_of_confirming_brc_inst_rdy
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_actual_bta_of_confirming_brc_inst
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_actual_brc_direction_of_confirming_brc_inst_rdy
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_actual_brc_direction_of_confirming_brc_inst
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_is_confirming_brc_inst_prdt_success
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_corrected_prdt_addr_of_confirming_brc_inst
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_actual_bta_of_failed_brc_prdt_inst
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/iq1_corrected_prdt_addr_of_failed_brc_prdt_inst
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/brc_path_confirmed
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/saving_csr_rw_msg_vld_r
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/saving_csr_rw_msg_upd_mask_v_r
add wave -noupdate -group issue_queue -radix unsigned /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/saving_csr_rw_msg_rob_entry_id_r
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/on_upd_rob_field_nxt_pc_r
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/inst_id_of_upd_rob_field_nxt_pc_r
add wave -noupdate -group issue_queue /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/issue_queue_u/rob_field_nxt_pc_r
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/aclk
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/aresetn
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_clr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_full_n
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_empty_n
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_csr_rw_inst_allowed
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_has_ls_inst
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_entry_id_to_be_written
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_entry_age_tbit_to_be_written
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_sng_cancel_vld
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_sng_cancel_tid
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_yngr_cancel_vld
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_yngr_cancel_bchmk_wptr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/op1_ftc_rs1_id
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/op1_ftc_from_reg_file
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/op1_ftc_from_rob
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/op1_ftc_from_byp
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/op1_ftc_fuid
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/op1_ftc_tid
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/op1_ftc_rob_saved_data
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/op2_ftc_rs2_id
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/op2_ftc_from_reg_file
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/op2_ftc_from_rob
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/op2_ftc_from_byp
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/op2_ftc_fuid
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/op2_ftc_tid
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/op2_ftc_rob_saved_data
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_prep_rtr_entry_vld
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_prep_rtr_entry_saved
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_prep_rtr_entry_err
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_prep_rtr_entry_rd_id
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_prep_rtr_entry_is_csr_rw_inst
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_prep_rtr_entry_spec_inst_type
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_prep_rtr_entry_cancel
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_prep_rtr_entry_fu_res
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_prep_rtr_entry_pc
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_prep_rtr_entry_nxt_pc
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_prep_rtr_entry_b_inst_res
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_prep_rtr_entry_org_2bit_sat_cnt
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_prep_rtr_entry_bhr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_prep_rtr_is_b_inst
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_prep_rtr_entry_csr_rw_waddr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_prep_rtr_entry_csr_rw_upd_type
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_prep_rtr_entry_csr_rw_upd_mask_v
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/fu_res_vld
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/fu_res_tid
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/fu_res_data
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/fu_res_err
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/s_bru_o_tid
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/s_bru_o_b_inst_res
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/s_bru_o_valid
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/saving_csr_rw_msg_upd_mask_v
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/saving_csr_rw_msg_rob_entry_id
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/saving_csr_rw_msg_vld
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/on_upd_rob_field_nxt_pc
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/inst_id_of_upd_rob_field_nxt_pc
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_field_nxt_pc
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/wr_mem_permitted_flag
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/init_mem_bus_tr_store_inst_tid
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/perph_access_permitted_flag
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/init_perph_bus_tr_ls_inst_tid
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_luc_bdcst_vld
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_luc_bdcst_tid
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_luc_bdcst_fuid
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_luc_bdcst_rd_id
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_luc_bdcst_is_ls_inst
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_luc_bdcst_is_csr_rw_inst
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_luc_bdcst_csr_rw_inst_msg
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_luc_bdcst_err
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_luc_bdcst_spec_inst_type
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_luc_bdcst_is_b_inst
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_luc_bdcst_pc
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_luc_bdcst_nxt_pc
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_luc_bdcst_org_2bit_sat_cnt
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_luc_bdcst_bhr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rtr_bdcst_vld
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_vld_entry_n
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_full_n
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_empty_n
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_wptr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_rptr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/csr_rw_inst_stored_n
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/csr_rw_rcd_full_n
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/csr_rw_rcd_wptr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/csr_rw_rcd_rptr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/csr_rw_rcd_waddr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/csr_rw_rcd_upd_type
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/csr_rw_rcd_upd_mask_v
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/csr_rw_rcd_wptr_saved
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/csr_rw_rcd_valid
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/csr_rw_inst_collision
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/is_retiring_ls_inst
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_vld_ls_inst_n
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_has_ls_inst_r
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_tid
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_fuid
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_rd_id
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_is_ls_inst
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_is_csr_rw_inst
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_spec_inst_type
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_is_b_inst
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_cancel
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_err
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_wptr_saved
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_fu_res
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_pc
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_nxt_pc
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_b_inst_res
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_org_2bit_sat_cnt
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_bhr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_saved
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_rcd_tb_vld
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/on_rob_sng_cancel_vld
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/on_rob_yngr_cancel_vld
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/on_rob_sync_err_cancel_vld
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/fu_res_vld_r
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/fu_res_tid_r
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/fu_res_data_r
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/fu_res_err_r
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/fu_res_vld_arr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/fu_res_tid_arr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/fu_res_data_arr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/fu_res_err_arr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_entry_res_on_lsn
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_entry_res_vld_arr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_entry_res_tid_arr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_entry_res_data_arr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/rob_entry_res_err_arr
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/is_arct_reg_at_rob
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/arct_reg_rob_entry_i
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/op1_rs1_rob_entry_i
add wave -noupdate -group rob /tb_isa_test/panda_risc_v_sim_u/panda_risc_v_u/rob_u/op2_rs2_rob_entry_i
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {39990019 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 334
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
WaveRestoreZoom {39925364 ps} {40025580 ps}
