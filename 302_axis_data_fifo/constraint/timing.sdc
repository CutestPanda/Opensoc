# ����α·��
# ����vivado����cell���ֺ������_reg��׺
# ����is_async == "true"ʱ��Ҫ
set_false_path -from [get_cells async_fifo_u/async_fifo_u/rptr_gray_at_r[*]] -to [get_cells async_fifo_u/async_fifo_u/rptr_gray_at_w_p2[*]]
set_false_path -from [get_cells async_fifo_u/async_fifo_u/wptr_gray_at_w[*]] -to [get_cells async_fifo_u/async_fifo_u/wptr_gray_at_r_p2[*]]
# ����is_async == "true"��ram_type == "lutram"ʱ��Ҫ
# ���ܻ�������ren_b�ϵ�ʱ��·��
set_false_path -to [get_cells async_fifo_u/ram_u/dout_b_regs[*]]
# ����is_async == "true"��en_packet_mode == "true"ʱ��Ҫ
set_false_path -from [get_cells axis_packet_stat_async_u/wptr_gray_at_w[*]] -to [get_cells axis_packet_stat_async_u/wptr_gray_at_w_d[*]]
set_false_path -to [get_cells axis_packet_stat_async_u/full_d]
