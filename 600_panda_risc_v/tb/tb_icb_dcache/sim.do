if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "*.sv" "*.v" "../../rtl/cache/*.v" "../../rtl/generic/fifo_based_on_regs.v"

# 仿真
vsim -voptargs=+acc -c tb_icb_dcache
do wave.do
