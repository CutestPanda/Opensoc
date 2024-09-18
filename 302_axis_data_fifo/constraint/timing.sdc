# 设置伪路径
# 对于vivado请在cell名字后面加上_reg后缀
# 仅当is_async == "true"时需要
set_false_path -from [get_cells async_fifo_u/async_fifo_u/rptr_gray_at_r[*]] -to [get_cells async_fifo_u/async_fifo_u/rptr_gray_at_w_p2[*]]
set_false_path -from [get_cells async_fifo_u/async_fifo_u/wptr_gray_at_w[*]] -to [get_cells async_fifo_u/async_fifo_u/wptr_gray_at_r_p2[*]]
# 仅当is_async == "true"且ram_type == "lutram"时需要
# 可能会多忽略了ren_b上的时序路径
set_false_path -to [get_cells async_fifo_u/ram_u/dout_b_regs[*]]
# 仅当is_async == "true"且en_packet_mode == "true"时需要
set_false_path -from [get_cells axis_packet_stat_async_u/wptr_gray_at_w[*]] -to [get_cells axis_packet_stat_async_u/wptr_gray_at_w_d[*]]
set_false_path -to [get_cells axis_packet_stat_async_u/full_d]
