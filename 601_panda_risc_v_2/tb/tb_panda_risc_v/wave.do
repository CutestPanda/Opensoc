onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/aclk
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/aresetn
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/sys_reset_req
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/flush_req
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/flush_addr
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/rst_ack
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/flush_ack
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/clr_inst_buf
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/ibus_access_req_addr
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/ibus_access_req_tid
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/ibus_access_req_valid
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/ibus_access_req_ready
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_bdcst_tid
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_bdcst_vld
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_iftc_vld
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_iftc_tid
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_iftc_is_b_inst
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_iftc_is_jal_inst
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_iftc_is_jalr_inst
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_iftc_bta
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_luc_vld
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_luc_tid
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_luc_is_b_inst
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_luc_is_jal_inst
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_luc_is_jalr_inst
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_bdcst_luc_bta
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/glb_brc_prdt_on_clr_retired_ghr
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/glb_brc_prdt_on_upd_retired_ghr
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/glb_brc_prdt_retired_ghr_shift_in
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/glb_brc_prdt_rstr_speculative_ghr
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/glb_brc_prdt_upd_i_req
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/glb_brc_prdt_upd_i_pc
add wave -noupdate -group pre_if -radix binary /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/glb_brc_prdt_upd_i_ghr
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/glb_brc_prdt_upd_i_brc_taken
add wave -noupdate -group pre_if -radix binary /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/glb_brc_prdt_retired_ghr_o
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_rplc_req
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_rplc_strgy
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_rplc_sel_wid
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_rplc_pc
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_rplc_btype
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_rplc_bta
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_rplc_jpdir
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_rplc_push_ras
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_rplc_pop_ras
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_unit_initializing
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_i_req
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_i_pc
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_i_nxt_pc
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_i_tid
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_vld
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_pc
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_brc_type
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_push_ras
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_pop_ras
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_taken
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_btb_hit
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_btb_wid
add wave -noupdate -group pre_if -radix binary /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_btb_wvld
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_btb_bta
add wave -noupdate -group pre_if -radix binary /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_glb_speculative_ghr
add wave -noupdate -group pre_if -radix binary /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_glb_2bit_sat_cnt
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_o_tid
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/first_inst_flag
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/inst_id
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/rst_pre_if_pending
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/flush_pre_if_pending
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/common_pre_if_pending
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_hit_jalr_pending
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_miss_pending
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_hit_jalr_bdcst_gotten
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/btb_miss_bdcst_gotten
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/to_rst
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/to_flush
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/flush_addr_saved
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/flush_addr_cur
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/prdt_addr_cur
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/pc_nxt
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/pc_r
add wave -noupdate -group pre_if -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/bdcst_bta_saved
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_prdt_u/ras_push_req
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_prdt_u/ras_push_addr
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_prdt_u/ras_pop_req
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_prdt_u/ras_pop_addr
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_prdt_u/ras_query_req
add wave -noupdate -group pre_if /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/pre_inst_fetch_u/brc_prdt_u/ras_query_addr
add wave -noupdate -group ifu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/aclk
add wave -noupdate -group ifu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/aresetn
add wave -noupdate -group ifu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/sys_reset_req
add wave -noupdate -group ifu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/flush_req
add wave -noupdate -group ifu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/flush_addr
add wave -noupdate -group ifu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/rst_ack
add wave -noupdate -group ifu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/flush_ack
add wave -noupdate -group ifu -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/m_if_res_id
add wave -noupdate -group ifu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/m_if_res_valid
add wave -noupdate -group ifu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/m_if_res_ready
add wave -noupdate -group ifu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/suppressing_ibus_access
add wave -noupdate -group ifu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/clr_inst_buf_while_suppressing
add wave -noupdate -group ifu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_timeout
add wave -noupdate -group ifu -radix hexadecimal /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_req_addr
add wave -noupdate -group ifu -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_req_tid
add wave -noupdate -group ifu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_req_valid
add wave -noupdate -group ifu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_req_ready
add wave -noupdate -group ifu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_resp_rdata
add wave -noupdate -group ifu -radix binary /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_resp_err
add wave -noupdate -group ifu -radix hexadecimal /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_resp_addr
add wave -noupdate -group ifu -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_resp_tid
add wave -noupdate -group ifu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_resp_valid
add wave -noupdate -group ifu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/ifu_u/ibus_access_resp_ready
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/aclk
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/aresetn
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/sys_reset_req
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/flush_req
add wave -noupdate -group op_fetch_idec -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/s_if_res_id
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/s_if_res_valid
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/s_if_res_ready
add wave -noupdate -group op_fetch_idec -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/m_op_ftc_id_res_id
add wave -noupdate -group op_fetch_idec -radix hexadecimal /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/m_op_ftc_id_res_op1
add wave -noupdate -group op_fetch_idec -radix hexadecimal /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/m_op_ftc_id_res_op2
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/m_op_ftc_id_res_with_ls_sdefc
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/m_op_ftc_id_res_valid
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/m_op_ftc_id_res_ready
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/rob_luc_bdcst_vld
add wave -noupdate -group op_fetch_idec -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/rob_luc_bdcst_tid
add wave -noupdate -group op_fetch_idec -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/rob_luc_bdcst_fuid
add wave -noupdate -group op_fetch_idec -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/rob_luc_bdcst_rd_id
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/rob_luc_bdcst_is_ls_inst
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/rob_luc_bdcst_with_ls_sdefc
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/rob_luc_bdcst_is_csr_rw_inst
add wave -noupdate -group op_fetch_idec -radix binary /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/rob_luc_bdcst_err
add wave -noupdate -group op_fetch_idec -radix binary /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/rob_luc_bdcst_spec_inst_type
add wave -noupdate -group op_fetch_idec -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op1_ftc_rs1_id
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op1_ftc_from_reg_file
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op1_ftc_from_rob
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op1_ftc_from_byp
add wave -noupdate -group op_fetch_idec -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op1_ftc_fuid
add wave -noupdate -group op_fetch_idec -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op1_ftc_tid
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op1_ftc_rob_saved_data
add wave -noupdate -group op_fetch_idec -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op2_ftc_rs2_id
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op2_ftc_from_reg_file
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op2_ftc_from_rob
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op2_ftc_from_byp
add wave -noupdate -group op_fetch_idec -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op2_ftc_fuid
add wave -noupdate -group op_fetch_idec -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op2_ftc_tid
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op2_ftc_rob_saved_data
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/fu_res_vld_arr
add wave -noupdate -group op_fetch_idec -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/fu_res_tid_arr
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/fu_res_data_arr
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/on_rst_flush
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/on_op1_fetch_from_bypass_network
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/on_op2_fetch_from_bypass_network
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/on_op1_fetch
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/on_op2_fetch
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op1_no_need
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op2_no_need
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op1_fetch_cur
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op2_fetch_cur
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op1_ready
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op2_ready
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op1_latched
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/op2_latched
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/to_sel_op1_latched
add wave -noupdate -group op_fetch_idec /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/op_fetch_idec_u/to_sel_op2_latched
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/aclk
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/aresetn
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/rob_full_n
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/rob_empty_n
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/rob_csr_rw_inst_allowed
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/rob_has_ls_inst
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/rob_has_ls_sdefc_inst
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/sys_reset_req
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/flush_req
add wave -noupdate -group launch -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/s_op_ftc_id_res_id
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/s_op_ftc_id_res_op1
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/s_op_ftc_id_res_op2
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/s_op_ftc_id_res_valid
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/s_op_ftc_id_res_ready
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/m_luc_op1
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/m_luc_op2
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/m_luc_valid
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/m_luc_ready
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/fence_csr_rw_allowed
add wave -noupdate -group launch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/launch_u/load_store_allowed
add wave -noupdate -group dispatch -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/s_dsptc_id
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/s_dsptc_valid
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/s_dsptc_ready
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_bru_i_id
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_bru_i_valid
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_bru_i_ready
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_alu_op_mode
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_alu_op1
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_alu_op2
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_alu_tid
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_alu_use_res
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_alu_valid
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_csr_addr
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_csr_tid
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_csr_valid
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_lsu_ls_sel
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_lsu_ls_type
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_lsu_rd_id_for_ld
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_lsu_ls_din
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_lsu_inst_id
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_lsu_valid
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_lsu_ready
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_mul_op_a
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_mul_op_b
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_mul_res_sel
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_mul_rd_id
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_mul_inst_id
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_mul_valid
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_mul_ready
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_div_op_a
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_div_op_b
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_div_rem_sel
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_div_rd_id
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_div_inst_id
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_div_valid
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/m_div_ready
add wave -noupdate -group dispatch /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/dispatch_u/fu_ready
add wave -noupdate -group flush_ctrl /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/aclk
add wave -noupdate -group flush_ctrl /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/aresetn
add wave -noupdate -group flush_ctrl /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/sys_reset_req
add wave -noupdate -group flush_ctrl /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/glb_brc_prdt_on_clr_retired_ghr
add wave -noupdate -group flush_ctrl /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/glb_brc_prdt_rstr_speculative_ghr
add wave -noupdate -group flush_ctrl /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/bru_flush_req
add wave -noupdate -group flush_ctrl /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/bru_flush_addr
add wave -noupdate -group flush_ctrl /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/bru_flush_grant
add wave -noupdate -group flush_ctrl /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/cmt_flush_req
add wave -noupdate -group flush_ctrl /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/cmt_flush_addr
add wave -noupdate -group flush_ctrl /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/cmt_flush_grant
add wave -noupdate -group flush_ctrl /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/suppressing_ibus_access
add wave -noupdate -group flush_ctrl /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/global_flush_req
add wave -noupdate -group flush_ctrl /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/global_flush_addr
add wave -noupdate -group flush_ctrl /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/global_flush_ack
add wave -noupdate -group flush_ctrl /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/global_flush_pending
add wave -noupdate -group flush_ctrl /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/flush_ctrl_u/sel_bru_flush
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/aclk
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/aresetn
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/in_dbg_mode
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/rst_bru
add wave -noupdate -group bru -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/jal_inst_n_acpt
add wave -noupdate -group bru -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/jal_prdt_success_inst_n
add wave -noupdate -group bru -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/jalr_inst_n_acpt
add wave -noupdate -group bru -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/jalr_prdt_success_inst_n
add wave -noupdate -group bru -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/b_inst_n_acpt
add wave -noupdate -group bru -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/b_prdt_success_inst_n
add wave -noupdate -group bru -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/common_inst_n_acpt
add wave -noupdate -group bru -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/common_prdt_success_inst_n
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/bru_flush_req
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/bru_flush_addr
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/bru_flush_grant
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/alu_brc_cond_res
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/s_bru_i_tid
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/s_bru_i_valid
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/s_bru_i_ready
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/m_bru_o_tid
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/m_bru_o_pc
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/m_bru_o_nxt_pc
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/m_bru_o_b_inst_res
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/m_bru_o_valid
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/is_brc_inst
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/prdt_success
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/actual_bta
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/nxt_seq_pc
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/prdt_jmp_addr
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/actual_jmp_addr
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/is_fence_i_inst
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/is_ebreak_inst
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/need_flush
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/flush_addr_cur
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/bru_flush_pending
add wave -noupdate -group bru /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/bru_u/bru_flush_addr_gen
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/aclk
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/aresetn
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/cmt_flush_req
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/cmt_flush_addr
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/cmt_flush_grant
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_clr
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_vld
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_saved
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_err
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_is_csr_rw_inst
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_spec_inst_type
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_cancel
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_fu_res
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_pc
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_nxt_pc
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_b_inst_res
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_rtr_bdcst_vld
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_rtr_bdcst_excpt_proc_grant
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/inst_retire_cnt_en
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/mstatus_mie_v
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/mie_msie_v
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/mie_mtie_v
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/mie_meie_v
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/sw_itr_req_i
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/tmr_itr_req_i
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/ext_itr_req_i
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/itr_expt_enter
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/itr_expt_is_intr
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/itr_expt_cause
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/itr_expt_vec_baseaddr
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/itr_expt_ret_addr
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/itr_expt_val
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/itr_expt_ret
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/mepc_ret_addr
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/in_trap
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/dbg_mode_enter
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/dbg_mode_cause
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/dbg_mode_ret_addr
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/dbg_mode_ret
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/dpc_ret_addr
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/dbg_halt_req
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/dbg_halt_on_reset_req
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/dcsr_ebreakm_v
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/dcsr_step_v
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/in_dbg_mode
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/glb_brc_prdt_on_upd_retired_ghr
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/glb_brc_prdt_retired_ghr_shift_in
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/glb_brc_prdt_upd_i_req
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/glb_brc_prdt_upd_i_pc
add wave -noupdate -group commit -radix binary /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/glb_brc_prdt_upd_i_ghr
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/glb_brc_prdt_upd_i_brc_taken
add wave -noupdate -group commit /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/glb_brc_prdt_retired_ghr_o
add wave -noupdate -group wr_bck /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/rob_prep_rtr_entry_rd_id
add wave -noupdate -group wr_bck /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/rob_prep_rtr_entry_is_csr_rw_inst
add wave -noupdate -group wr_bck /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/rob_prep_rtr_entry_cancel
add wave -noupdate -group wr_bck /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/rob_prep_rtr_entry_fu_res
add wave -noupdate -group wr_bck /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/rob_prep_rtr_entry_csr_rw_waddr
add wave -noupdate -group wr_bck /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/rob_prep_rtr_entry_csr_rw_upd_type
add wave -noupdate -group wr_bck /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/rob_prep_rtr_entry_csr_rw_upd_mask_v
add wave -noupdate -group wr_bck /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/commit_u/rob_prep_rtr_entry_pc
add wave -noupdate -group wr_bck /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/rob_rtr_bdcst_vld
add wave -noupdate -group wr_bck /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/rob_rtr_bdcst_excpt_proc_grant
add wave -noupdate -group wr_bck /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/reg_file_wen
add wave -noupdate -group wr_bck -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/reg_file_waddr
add wave -noupdate -group wr_bck -radix hexadecimal /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/reg_file_din
add wave -noupdate -group wr_bck /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/csr_atom_waddr
add wave -noupdate -group wr_bck /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/csr_atom_upd_type
add wave -noupdate -group wr_bck /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/csr_atom_upd_mask_v
add wave -noupdate -group wr_bck /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/wr_bck/csr_atom_wen
add wave -noupdate -group lsu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/clk
add wave -noupdate -group lsu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/resetn
add wave -noupdate -group lsu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/lsu_idle
add wave -noupdate -group lsu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/s_req_ls_sel
add wave -noupdate -group lsu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/s_req_ls_type
add wave -noupdate -group lsu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/s_req_rd_id_for_ld
add wave -noupdate -group lsu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/s_req_ls_addr
add wave -noupdate -group lsu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/s_req_ls_din
add wave -noupdate -group lsu -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/s_req_lsu_inst_id
add wave -noupdate -group lsu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/s_req_valid
add wave -noupdate -group lsu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/s_req_ready
add wave -noupdate -group lsu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_resp_ls_sel
add wave -noupdate -group lsu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_resp_rd_id_for_ld
add wave -noupdate -group lsu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_resp_dout
add wave -noupdate -group lsu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_resp_ls_addr
add wave -noupdate -group lsu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_resp_err
add wave -noupdate -group lsu -radix unsigned /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_resp_lsu_inst_id
add wave -noupdate -group lsu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_resp_valid
add wave -noupdate -group lsu /tb_panda_risc_v/panda_risc_v_sim_u/panda_risc_v_u/func_units/lsu_u/m_resp_ready
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1999993071 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 273
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
WaveRestoreZoom {397469784 ps} {400133170 ps}
