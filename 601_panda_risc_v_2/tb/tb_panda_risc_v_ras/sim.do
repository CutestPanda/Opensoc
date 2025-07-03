if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "tb_panda_risc_v_ras.sv" "../../core_rtl/panda_risc_v_ras.v"

# 仿真
vsim -voptargs=+acc -c tb_panda_risc_v_ras
do wave.do
