if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "tb_sdram_phy_self_test.sv" "*.v" "../../rtl/*.v"

# 仿真
vsim -voptargs=+acc -c tb_sdram_phy_self_test
do wave.do
