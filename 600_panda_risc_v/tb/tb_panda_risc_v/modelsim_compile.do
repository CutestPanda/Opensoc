vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xil_defaultlib

vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib

vlog -sv -64 -incr -work xil_defaultlib  \
"to_compile/dut/*.v" \
"to_compile/tb/*.sv" \

quit -force
