if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "tb_axi_sdram_self_test.sv" "*.v" "../../common/*.v" "../../app/*.v"

# 仿真
vsim -voptargs=+acc -c tb_axi_sdram_self_test
do wave.do
