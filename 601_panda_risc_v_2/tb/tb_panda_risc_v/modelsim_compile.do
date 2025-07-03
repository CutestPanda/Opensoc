vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xil_defaultlib

vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib

vlog -64 -incr -work xil_defaultlib  \
"../../core_rtl/*.v" \
"../../soc_rtl/*.v" \
"panda_risc_v_sim.v" \

vlog -sv -64 -incr -work xil_defaultlib "tb_panda_risc_v.sv"

quit -force
