vsim -voptargs=+acc xil_defaultlib.tb_panda_risc_v -g IMEM_INIT_FILE="E:/RTL/design/panda_risc_v/tb/tb_panda_risc_v/inst_test/rv32um-p-remu.txt" -g DMEM_INIT_FILE="E:/RTL/design/panda_risc_v/tb/tb_panda_risc_v/inst_test/rv32um-p-remu.txt"
set NumericStdNoWarnings 1
set StdArithNoWarnings 1
run 40us
quit
