# 设置伪路径
set_false_path -from [get_cells {audio_player_u/flash_dma_u/async_handshake_u0/ack}] -to [get_cells {audio_player_u/flash_dma_u/async_handshake_u0/ack_d}]
set_false_path -from [get_cells {audio_player_u/flash_dma_u/async_handshake_u0/req}] -to [get_cells {audio_player_u/flash_dma_u/async_handshake_u0/req_d}]
# 当(audio_sample_rate_fixed == "false")时需要
set_false_path -from [get_cells {audio_sample_rate[*]}]

set_false_path -from [get_cells audio_player_u/audio_fifo_u/async_fifo_u/rptr_gray_at_r[*]] -to [get_cells audio_player_u/audio_fifo_u/async_fifo_u/rptr_gray_at_w_p2[*]]
set_false_path -from [get_cells audio_player_u/audio_fifo_u/async_fifo_u/wptr_gray_at_w[*]] -to [get_cells audio_player_u/audio_fifo_u/async_fifo_u/wptr_gray_at_r_p2[*]]
