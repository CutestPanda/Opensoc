if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "*.sv" "../../core_rtl/panda_risc_v_ibus_ctrler.v" "../../core_rtl/panda_risc_v_pre_decoder.v"

# 仿真
vsim -voptargs=+acc -c tb_panda_risc_v_ibus_ctrler
do wave.do
