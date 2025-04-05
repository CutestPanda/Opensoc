if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "tb_cool_down_cnt.sv" "../../rtl/cool_down_cnt.v"

# 仿真
vsim -voptargs=+acc -c tb_cool_down_cnt
do wave.do
run 1us
