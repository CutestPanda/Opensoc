if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog "../../core_rtl/*.v" "../../soc_rtl/*.v"
vlog -sv "tb_panda_soc.sv"

# 仿真
vsim -voptargs=+acc -c tb_panda_soc
do wave.do
