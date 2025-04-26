if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "*.sv" "../../common/*.v" "../../rtl/eth_mac_tx.v" "../../rtl/crc32_d8.v"

# 仿真
vsim -voptargs=+acc -c tb_eth_mac_tx
do wave.do
