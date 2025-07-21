# 设置伪路径
# 对于vivado请在cell名字后面加上_reg后缀
set_false_path -from [get_cells tx_fifo/async_fifo_u/rptr_gray_at_r[*]] -to [get_cells tx_fifo/async_fifo_u/rptr_gray_at_w_p2[*]]
set_false_path -from [get_cells tx_fifo/async_fifo_u/wptr_gray_at_w[*]] -to [get_cells tx_fifo/async_fifo_u/wptr_gray_at_r_p2[*]]

set_false_path -from [get_cells rx_fifo/async_fifo_u/rptr_gray_at_r[*]] -to [get_cells rx_fifo/async_fifo_u/rptr_gray_at_w_p2[*]]
set_false_path -from [get_cells rx_fifo/async_fifo_u/wptr_gray_at_w[*]] -to [get_cells rx_fifo/async_fifo_u/wptr_gray_at_r_p2[*]]

set_false_path -from [get_cells spi_trans_params[*]]

# set_false_path -from [get_cells spi_xip[*]]
