if [file exists work] {
    vdel -all
}
vlib work

# 编译
<<<<<<< HEAD
vlog "../../core_rtl/*.v"
=======
vlog "../core_rtl/*.v"
>>>>>>> f159a4e146763038aa92fc830492fdebb5e4464f
vlog -sv "tb_isa_test.sv"

# 仿真
vsim -voptargs=+acc -c tb_isa_test
do wave.do
