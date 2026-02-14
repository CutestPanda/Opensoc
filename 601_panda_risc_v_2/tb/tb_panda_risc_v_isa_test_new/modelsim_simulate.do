vsim -voptargs=+acc xil_defaultlib.tb_isa_test -g IMEM_INIT_FILE="C:/Users/22576/Desktop/panda_risc_v_test_new/tb/tb_panda_risc_v_isa_test_new/test_compiled/rv32um-p-remu.mem" -g DMEM_INIT_FILE="C:/Users/22576/Desktop/panda_risc_v_test_new/tb/tb_panda_risc_v_isa_test_new/test_compiled/rv32um-p-remu.mem"
set NumericStdNoWarnings 1
set StdArithNoWarnings 1
run 100us
quit
