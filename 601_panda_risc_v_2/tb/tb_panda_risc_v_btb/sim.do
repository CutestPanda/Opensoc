if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "*.sv" "../../core_rtl/panda_risc_v_btb.v" "../../core_rtl/bram_true_dual_port.v"

# 仿真
vsim -voptargs=+acc -c tb_panda_risc_v_btb
do wave.do
