if [file exists work] {
    vdel -all
}
vlib work

# 编译
vlog "../core_rtl/*.v"
vlog -sv "tb_isa_test.sv"

# 仿真
vsim -voptargs=+acc -c tb_isa_test
do wave.do
