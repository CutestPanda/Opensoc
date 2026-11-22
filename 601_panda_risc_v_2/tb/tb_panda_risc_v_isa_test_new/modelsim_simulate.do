vsim -voptargs=+acc xil_defaultlib.tb_isa_test -g IMEM_INIT_FILE="E:/github/Opensoc/601_panda_risc_v_2/tb/tb_panda_risc_v_isa_test_new/test_compiled/rv32um-p-remu.mem" -g DMEM_INIT_FILE="E:/github/Opensoc/601_panda_risc_v_2/tb/tb_panda_risc_v_isa_test_new/test_compiled/rv32um-p-remu.mem"
set NumericStdNoWarnings 1
set StdArithNoWarnings 1
run 100us
quit
