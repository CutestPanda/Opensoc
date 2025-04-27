if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "*.sv" "*.v" "../app_rtl/*.v" "../generic_rtl/*.v"

# 仿真
vsim -voptargs=+acc -c tb_axi_dma_engine_mm2s
do wave.do
