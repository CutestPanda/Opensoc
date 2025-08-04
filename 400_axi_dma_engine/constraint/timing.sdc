# 设置伪路径
# 对于vivado请在cell名字后面加上_reg后缀
# 以下仅当使能读通道(MM2S)时需要
set_false_path -from [get_cells dma_rchn_u/cmd_fifo/async_fifo_u/async_fifo_u/rptr_gray_at_r[*]] -to [get_cells dma_rchn_u/cmd_fifo/async_fifo_u/async_fifo_u/rptr_gray_at_w_p2[*]]
set_false_path -from [get_cells dma_rchn_u/cmd_fifo/async_fifo_u/async_fifo_u/wptr_gray_at_w[*]] -to [get_cells dma_rchn_u/cmd_fifo/async_fifo_u/async_fifo_u/wptr_gray_at_r_p2[*]]

set_false_path -from [get_cells dma_rchn_u/rdata_async_fifo/async_fifo_u/async_fifo_u/rptr_gray_at_r[*]] -to [get_cells dma_rchn_u/rdata_async_fifo/async_fifo_u/async_fifo_u/rptr_gray_at_w_p2[*]]
set_false_path -from [get_cells dma_rchn_u/rdata_async_fifo/async_fifo_u/async_fifo_u/wptr_gray_at_w[*]] -to [get_cells dma_rchn_u/rdata_async_fifo/async_fifo_u/async_fifo_u/wptr_gray_at_r_p2[*]]

set_false_path -from [get_cells dma_rchn_u/async_handshake_u/ack] -to [get_cells dma_rchn_u/async_handshake_u/ack_d]
set_false_path -from [get_cells dma_rchn_u/async_handshake_u/req] -to [get_cells dma_rchn_u/async_handshake_u/req_d]
# 以上仅当使能读通道(MM2S)时需要

# 以下仅当使能写通道(S2MM)时需要
set_false_path -from [get_cells dma_wchn_u/cmd_fifo/async_fifo_u/async_fifo_u/rptr_gray_at_r[*]] -to [get_cells dma_wchn_u/cmd_fifo/async_fifo_u/async_fifo_u/rptr_gray_at_w_p2[*]]
set_false_path -from [get_cells dma_wchn_u/cmd_fifo/async_fifo_u/async_fifo_u/wptr_gray_at_w[*]] -to [get_cells dma_wchn_u/cmd_fifo/async_fifo_u/async_fifo_u/wptr_gray_at_r_p2[*]]

set_false_path -from [get_cells dma_wchn_u/wr_async_fifo/async_fifo_u/async_fifo_u/rptr_gray_at_r[*]] -to [get_cells dma_wchn_u/wr_async_fifo/async_fifo_u/async_fifo_u/rptr_gray_at_w_p2[*]]
set_false_path -from [get_cells dma_wchn_u/wr_async_fifo/async_fifo_u/async_fifo_u/wptr_gray_at_w[*]] -to [get_cells dma_wchn_u/wr_async_fifo/async_fifo_u/async_fifo_u/wptr_gray_at_r_p2[*]]

# 以下仅当使能写字节数实时统计时需要
set_false_path -from [get_cells dma_wchn_u/axi_dma_engine_wdata_stat_u/s2mm_bytes_n_vld[*]] -to [get_cells dma_wchn_u/axi_dma_engine_wdata_stat_u/s2mm_bytes_n_vld_d[*]]
set_false_path -from [get_cells dma_wchn_u/axi_dma_engine_wdata_stat_u/s2mm_bytes_n_read[*]] -to [get_cells dma_wchn_u/axi_dma_engine_wdata_stat_u/s2mm_bytes_n_read_d[*]]
set_false_path -from [get_cells dma_wchn_u/axi_dma_engine_wdata_stat_u/s2mm_bytes_n[*]] -to [get_cells dma_wchn_u/axi_dma_engine_wdata_stat_u/cmd_btt[*]]
set_false_path -from [get_cells dma_wchn_u/axi_dma_engine_wdata_stat_u/s2mm_last_pkt[*]] -to [get_cells dma_wchn_u/axi_dma_engine_wdata_stat_u/cmd_is_last_pkt]
# 以上仅当使能写字节数实时统计时需要

set_false_path -from [get_cells dma_wchn_u/async_handshake_u/ack] -to [get_cells dma_wchn_u/async_handshake_u/ack_d]
set_false_path -from [get_cells dma_wchn_u/async_handshake_u/req] -to [get_cells dma_wchn_u/async_handshake_u/req_d]
# 以上仅当使能写通道(S2MM)时需要
