if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "*.sv" "../reg_adapters.sv" "../../*.sv" "rtl/*.v"

# 仿真
vsim -voptargs=+acc -c tb_apb_timer
do wave.do
