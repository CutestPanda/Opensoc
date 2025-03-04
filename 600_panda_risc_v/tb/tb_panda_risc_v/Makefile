MODELSIM_PATH = D:/modelsim/win64

SIM_LOG = simulate.log
COMPILE_LOG = compile.log
CLEAN_OBJS = $(SIM_LOG) $(COMPILE_LOG)

MODELSIM_LIB_DIR_TAG = modelsim_lib/tag.txt
MODELSIM_WORK_DIR_TAG = modelsim_lib/work/tag.txt

COMPILE_FILE = to_compile/dut/*.v to_compile/tb/*.sv

.PHONY: all
all: $(SIM_LOG)

$(SIM_LOG): $(COMPILE_LOG)
	$(MODELSIM_PATH)/vsim.exe -c -do "do {modelsim_simulate.do}" -l $(SIM_LOG)

$(COMPILE_LOG): $(COMPILE_FILE) $(MODELSIM_LIB_DIR_TAG) $(MODELSIM_WORK_DIR_TAG)
	$(MODELSIM_PATH)/vsim.exe -c -do "do {modelsim_compile.do}" -l $(COMPILE_LOG)

$(MODELSIM_LIB_DIR_TAG):
	mkdir modelsim_lib
	echo tag > modelsim_lib/tag.txt

$(MODELSIM_WORK_DIR_TAG): $(MODELSIM_LIB_DIR_TAG)
	mkdir modelsim_lib/work
	echo tag > modelsim_lib/work/tag.txt

.PHONY: clean
clean:
	rm -f $(CLEAN_OBJS)
