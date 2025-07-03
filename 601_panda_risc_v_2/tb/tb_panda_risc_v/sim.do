if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog "../../core_rtl/*.v" "panda_risc_v_sim.v" "../../soc_rtl/*.v"
vlog -sv "tb_panda_risc_v.sv"

# 仿真
vsim -voptargs=+acc -c tb_panda_risc_v
do wave.do
