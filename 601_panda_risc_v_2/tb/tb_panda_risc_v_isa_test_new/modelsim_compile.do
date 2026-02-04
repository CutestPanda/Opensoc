vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xil_defaultlib

vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib

<<<<<<< HEAD
vlog -work xil_defaultlib "../../core_rtl/*.v"
=======
vlog -work xil_defaultlib "../../core_rtl/*.v" "../../soc_rtl/*.v" "panda_risc_v_sim.v"
>>>>>>> f159a4e146763038aa92fc830492fdebb5e4464f

vlog -sv -work xil_defaultlib "tb_isa_test.sv"

quit -force
