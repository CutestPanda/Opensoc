onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_panda_risc_v_btb/dut/aclk
add wave -noupdate /tb_panda_risc_v_btb/dut/aresetn
add wave -noupdate /tb_panda_risc_v_btb/dut/btb_initializing
add wave -noupdate /tb_panda_risc_v_btb/dut/btb_query_i_req
add wave -noupdate -radix unsigned /tb_panda_risc_v_btb/dut/btb_query_i_pc
add wave -noupdate -radix binary /tb_panda_risc_v_btb/dut/btb_query_o_btype
add wave -noupdate -radix unsigned /tb_panda_risc_v_btb/dut/btb_query_o_bta
add wave -noupdate /tb_panda_risc_v_btb/dut/btb_query_o_jpdir
add wave -noupdate /tb_panda_risc_v_btb/dut/btb_query_o_hit
add wave -noupdate /tb_panda_risc_v_btb/dut/btb_query_o_vld
add wave -noupdate /tb_panda_risc_v_btb/dut/btb_rplc_req
add wave -noupdate -radix unsigned /tb_panda_risc_v_btb/dut/btb_rplc_pc
add wave -noupdate -radix binary /tb_panda_risc_v_btb/dut/btb_rplc_btype
add wave -noupdate -radix unsigned /tb_panda_risc_v_btb/dut/btb_rplc_bta
add wave -noupdate /tb_panda_risc_v_btb/dut/btb_rplc_jpdir
add wave -noupdate -radix unsigned /tb_panda_risc_v_btb/dut/btb_rplc_lfsr
add wave -noupdate -radix unsigned /tb_panda_risc_v_btb/dut/btb_rplc_wid
add wave -noupdate -expand -group btb_mem_0 {/tb_panda_risc_v_btb/btb_mem_blk[0]/btb_mem_u/clk}
add wave -noupdate -expand -group btb_mem_0 {/tb_panda_risc_v_btb/btb_mem_blk[0]/btb_mem_u/ena}
add wave -noupdate -expand -group btb_mem_0 {/tb_panda_risc_v_btb/btb_mem_blk[0]/btb_mem_u/wea}
add wave -noupdate -expand -group btb_mem_0 -radix unsigned {/tb_panda_risc_v_btb/btb_mem_blk[0]/btb_mem_u/addra}
add wave -noupdate -expand -group btb_mem_0 {/tb_panda_risc_v_btb/btb_mem_blk[0]/btb_mem_u/dina}
add wave -noupdate -expand -group btb_mem_0 {/tb_panda_risc_v_btb/btb_mem_blk[0]/btb_mem_u/douta}
add wave -noupdate -expand -group btb_mem_0 {/tb_panda_risc_v_btb/btb_mem_blk[0]/btb_mem_u/enb}
add wave -noupdate -expand -group btb_mem_0 {/tb_panda_risc_v_btb/btb_mem_blk[0]/btb_mem_u/web}
add wave -noupdate -expand -group btb_mem_0 -radix unsigned {/tb_panda_risc_v_btb/btb_mem_blk[0]/btb_mem_u/addrb}
add wave -noupdate -expand -group btb_mem_0 {/tb_panda_risc_v_btb/btb_mem_blk[0]/btb_mem_u/dinb}
add wave -noupdate -expand -group btb_mem_0 {/tb_panda_risc_v_btb/btb_mem_blk[0]/btb_mem_u/doutb}
add wave -noupdate -expand -group btb_mem_1 {/tb_panda_risc_v_btb/btb_mem_blk[1]/btb_mem_u/clk}
add wave -noupdate -expand -group btb_mem_1 {/tb_panda_risc_v_btb/btb_mem_blk[1]/btb_mem_u/ena}
add wave -noupdate -expand -group btb_mem_1 {/tb_panda_risc_v_btb/btb_mem_blk[1]/btb_mem_u/wea}
add wave -noupdate -expand -group btb_mem_1 -radix unsigned {/tb_panda_risc_v_btb/btb_mem_blk[1]/btb_mem_u/addra}
add wave -noupdate -expand -group btb_mem_1 {/tb_panda_risc_v_btb/btb_mem_blk[1]/btb_mem_u/dina}
add wave -noupdate -expand -group btb_mem_1 {/tb_panda_risc_v_btb/btb_mem_blk[1]/btb_mem_u/douta}
add wave -noupdate -expand -group btb_mem_1 {/tb_panda_risc_v_btb/btb_mem_blk[1]/btb_mem_u/enb}
add wave -noupdate -expand -group btb_mem_1 {/tb_panda_risc_v_btb/btb_mem_blk[1]/btb_mem_u/web}
add wave -noupdate -expand -group btb_mem_1 -radix unsigned {/tb_panda_risc_v_btb/btb_mem_blk[1]/btb_mem_u/addrb}
add wave -noupdate -expand -group btb_mem_1 {/tb_panda_risc_v_btb/btb_mem_blk[1]/btb_mem_u/dinb}
add wave -noupdate -expand -group btb_mem_1 {/tb_panda_risc_v_btb/btb_mem_blk[1]/btb_mem_u/doutb}
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {6267828 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 183
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
WaveRestoreZoom {6159194 ps} {6399826 ps}
