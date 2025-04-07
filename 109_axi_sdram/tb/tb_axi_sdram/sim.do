if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "*.sv" "IS42s32200.v" "../../common/*.v" "../../app/*.v"

# 仿真
vsim -voptargs=+acc -c tb_axi_sdram
do wave.do
