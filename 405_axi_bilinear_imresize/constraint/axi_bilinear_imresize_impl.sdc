# …Ë÷√Œ±¬∑æ∂
set_false_path -from [get_cells axis_bilinear_imresize_u/resize_fns_r] -to [get_cells single_bit_syn_u0/dff_chain[0].dffs[0]]
set_false_path -from [get_cells reg_if_for_imresize_u/cdc_rx_u/i_rdy_r] -to [get_cells reg_if_for_imresize_u/cdc_tx_u/o_rdy_a_d]
set_false_path -from [get_cells reg_if_for_imresize_u/cdc_tx_u/vld_r] -to [get_cells reg_if_for_imresize_u/cdc_rx_u/i_vld_a_d]
set_false_path -from [get_cells reg_if_for_imresize_u/cdc_tx_u/dat_r[*]] -to [get_cells reg_if_for_imresize_u/cdc_rx_u/buf_dat_r[*]]
