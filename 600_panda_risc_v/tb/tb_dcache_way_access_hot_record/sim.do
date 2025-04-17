if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "tb_dcache_way_access_hot_record.sv" "bram_simple_dual_port.v" "../../rtl/cache/dcache_way_access_hot_record.v"

# 仿真
vsim -voptargs=+acc -c tb_dcache_way_access_hot_record
do wave.do
