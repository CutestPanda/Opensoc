if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "tb_eth_mac_mdio.sv" "../../rtl/eth_mac_mdio.v"

# 仿真
vsim -voptargs=+acc -c tb_eth_mac_mdio
do wave.do
