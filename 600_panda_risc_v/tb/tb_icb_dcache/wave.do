onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_icb_dcache/dut/aclk
add wave -noupdate /tb_icb_dcache/dut/aresetn
add wave -noupdate -expand -group s_cpu_icb -radix unsigned /tb_icb_dcache/dut/s_icb_cmd_addr
add wave -noupdate -expand -group s_cpu_icb /tb_icb_dcache/dut/s_icb_cmd_read
add wave -noupdate -expand -group s_cpu_icb /tb_icb_dcache/dut/s_icb_cmd_wdata
add wave -noupdate -expand -group s_cpu_icb -radix binary /tb_icb_dcache/dut/s_icb_cmd_wmask
add wave -noupdate -expand -group s_cpu_icb /tb_icb_dcache/dut/s_icb_cmd_valid
add wave -noupdate -expand -group s_cpu_icb /tb_icb_dcache/dut/s_icb_cmd_ready
add wave -noupdate -expand -group s_cpu_icb /tb_icb_dcache/dut/s_icb_rsp_rdata
add wave -noupdate -expand -group s_cpu_icb /tb_icb_dcache/dut/s_icb_rsp_err
add wave -noupdate -expand -group s_cpu_icb /tb_icb_dcache/dut/s_icb_rsp_valid
add wave -noupdate -expand -group s_cpu_icb /tb_icb_dcache/dut/s_icb_rsp_ready
add wave -noupdate -expand -group m_ext_mem_icb -radix unsigned /tb_icb_dcache/dut/m_icb_cmd_addr
add wave -noupdate -expand -group m_ext_mem_icb /tb_icb_dcache/dut/m_icb_cmd_read
add wave -noupdate -expand -group m_ext_mem_icb /tb_icb_dcache/dut/m_icb_cmd_wdata
add wave -noupdate -expand -group m_ext_mem_icb -radix binary /tb_icb_dcache/dut/m_icb_cmd_wmask
add wave -noupdate -expand -group m_ext_mem_icb /tb_icb_dcache/dut/m_icb_cmd_valid
add wave -noupdate -expand -group m_ext_mem_icb /tb_icb_dcache/dut/m_icb_cmd_ready
add wave -noupdate -expand -group m_ext_mem_icb /tb_icb_dcache/dut/m_icb_rsp_rdata
add wave -noupdate -expand -group m_ext_mem_icb /tb_icb_dcache/dut/m_icb_rsp_err
add wave -noupdate -expand -group m_ext_mem_icb /tb_icb_dcache/dut/m_icb_rsp_valid
add wave -noupdate -expand -group m_ext_mem_icb /tb_icb_dcache/dut/m_icb_rsp_ready
add wave -noupdate -expand -group wbuf /tb_icb_dcache/dut/dcache_ctrl_u/m_wbuf_axis_data
add wave -noupdate -expand -group wbuf /tb_icb_dcache/dut/dcache_ctrl_u/m_wbuf_axis_valid
add wave -noupdate -expand -group wbuf /tb_icb_dcache/dut/dcache_ctrl_u/m_wbuf_axis_ready
add wave -noupdate -expand -group wbuf -radix unsigned /tb_icb_dcache/dut/dcache_ctrl_u/wbuf_sch_addr
add wave -noupdate -expand -group wbuf /tb_icb_dcache/dut/dcache_ctrl_u/wbuf_cln_found_flag
add wave -noupdate -expand -group wbuf /tb_icb_dcache/dut/dcache_ctrl_u/wbuf_sch_datblk
add wave -noupdate -expand -group hot_tb /tb_icb_dcache/dut/dcache_ctrl_u/hot_tb_en
add wave -noupdate -expand -group hot_tb /tb_icb_dcache/dut/dcache_ctrl_u/hot_tb_upd_en
add wave -noupdate -expand -group hot_tb -radix unsigned /tb_icb_dcache/dut/dcache_ctrl_u/hot_tb_cid
add wave -noupdate -expand -group hot_tb -radix unsigned /tb_icb_dcache/dut/dcache_ctrl_u/hot_tb_acs_wid
add wave -noupdate -expand -group hot_tb /tb_icb_dcache/dut/dcache_ctrl_u/hot_tb_init_item
add wave -noupdate -expand -group hot_tb /tb_icb_dcache/dut/dcache_ctrl_u/hot_tb_swp_lru_item
add wave -noupdate -expand -group hot_tb -radix unsigned /tb_icb_dcache/dut/dcache_ctrl_u/hot_tb_lru_wid
add wave -noupdate -expand -group hot_tb -radix binary /tb_icb_dcache/dut/dcache_way_access_hot_record_u/hot_tb_dout
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/cache_miss_processing
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/on_cache_miss
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/on_cache_miss_proc_done
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/to_continue_cache_miss_proc
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/on_cache_wt_hit_upd
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/cache_wt_hit_upd_pending
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/cache_hit_pending
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/is_cache_hit
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/has_invalid_cln
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/is_rd_cache
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/cache_wdata
add wave -noupdate -expand -group dcache_ctrl -radix binary /tb_icb_dcache/dut/dcache_ctrl_u/cache_wt_byte_en
add wave -noupdate -expand -group dcache_ctrl -radix unsigned /tb_icb_dcache/dut/dcache_ctrl_u/cache_acs_addr_word_ofs
add wave -noupdate -expand -group dcache_ctrl -radix unsigned /tb_icb_dcache/dut/dcache_ctrl_u/cache_acs_addr_index
add wave -noupdate -expand -group dcache_ctrl -radix unsigned /tb_icb_dcache/dut/dcache_ctrl_u/cache_acs_addr_tag
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/cache_rdata_valid
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/on_cache_rdata_valid
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/cache_hit_datblk
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/cache_hit_word
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/wbuf_cln_found_flag_r
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/wbuf_sch_datblk_r
add wave -noupdate -expand -group dcache_ctrl -radix unsigned /tb_icb_dcache/dut/dcache_ctrl_u/nxtlv_mem_acs_req_word_id
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/nxtlv_mem_acs_valid
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/cln_fetched_from_ext
add wave -noupdate -expand -group dcache_ctrl -radix binary /tb_icb_dcache/dut/dcache_ctrl_u/cln_fetched_word_id
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/cln_ext_fetch_fns
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/cln_fetch_fns
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/wbuf_addr
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/wbuf_data
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/wbuf_valid
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/wbuf_access_fns
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/sel_swp_invld_cln
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/swp_invld_wip
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/swp_cln_wip
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/swp_cln_wbk_addr
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/swp_cln_wbk_data
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/swp_cln_dirty
add wave -noupdate -expand -group dcache_ctrl -radix binary /tb_icb_dcache/dut/dcache_ctrl_u/swp_cache_way_sel
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/swp_cln_wbk_addr_latched
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/swp_cln_wbk_data_latched
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/swp_cln_dirty_latched
add wave -noupdate -expand -group dcache_ctrl -radix unsigned /tb_icb_dcache/dut/dcache_ctrl_u/miss_proc_sts
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/on_lacth_swp_cln_msg
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/on_lacth_swp_cln_msg_d1
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/on_access_wbuf
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/datblk_fetched
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/word_fetched
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/sel_tag_getting_tag_mem_port
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/sel_wt_hit_upd_tag_mem_port
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/sel_miss_proc_tag_mem_port
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/tag_getting_tag_mem_ren
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/tag_getting_tag_mem_addr_index
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/tag_getting_tag_for_cmp
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/wt_hit_upd_tag_mem_wen
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/wt_hit_upd_tag_mem_addr_index
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/wt_hit_upd_tag_mem_din_tag
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/wt_hit_upd_tag_mem_din_valid
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/wt_hit_upd_tag_mem_din_dirty
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/miss_proc_tag_mem_wen
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/miss_proc_tag_mem_addr_index
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/miss_proc_tag_mem_din_tag
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/miss_proc_tag_mem_din_valid
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/miss_proc_tag_mem_din_dirty
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/sel_rd_cache_data_mem_port
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/sel_wt_cache_data_mem_port
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/rd_cache_data_mem_ren
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/rd_cache_data_mem_addr_index
add wave -noupdate -expand -group dcache_ctrl -radix binary /tb_icb_dcache/dut/dcache_ctrl_u/wt_cache_data_mem_en
add wave -noupdate -expand -group dcache_ctrl -radix binary /tb_icb_dcache/dut/dcache_ctrl_u/wt_cache_data_mem_wen
add wave -noupdate -expand -group dcache_ctrl -radix unsigned /tb_icb_dcache/dut/dcache_ctrl_u/wt_cache_data_mem_addr_index
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/wt_cache_data_mem_din
add wave -noupdate -expand -group dcache_ctrl /tb_icb_dcache/dut/dcache_ctrl_u/datblk_modified
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {210508 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 248
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
WaveRestoreZoom {774299 ps} {1350367 ps}
