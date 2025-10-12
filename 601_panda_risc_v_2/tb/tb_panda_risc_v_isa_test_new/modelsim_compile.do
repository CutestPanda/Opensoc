vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xil_defaultlib

vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib

vlog -work xil_defaultlib "../../core_rtl/*.v" "../../soc_rtl/*.v" "panda_risc_v_sim.v"

vlog -sv -work xil_defaultlib "tb_isa_test.sv"

quit -force
