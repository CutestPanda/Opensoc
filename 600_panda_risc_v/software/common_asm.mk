
RISCV_PATH := $(TOOLCHAIN_DIR)/tools/gnu-mcu-eclipse-riscv-none-gcc-8.2.0-2.2-20190521-0004-win64/

RISCV_GCC     := $(abspath $(RISCV_PATH)/bin/riscv-none-embed-gcc)
RISCV_AS      := $(abspath $(RISCV_PATH)/bin/riscv-none-embed-as)
RISCV_GXX     := $(abspath $(RISCV_PATH)/bin/riscv-none-embed-g++)
RISCV_OBJDUMP := $(abspath $(RISCV_PATH)/bin/riscv-none-embed-objdump)
RISCV_GDB     := $(abspath $(RISCV_PATH)/bin/riscv-none-embed-gdb)
RISCV_AR      := $(abspath $(RISCV_PATH)/bin/riscv-none-embed-ar)
RISCV_OBJCOPY := $(abspath $(RISCV_PATH)/bin/riscv-none-embed-objcopy)
RISCV_READELF := $(abspath $(RISCV_PATH)/bin/riscv-none-embed-readelf)

.PHONY: all
all: $(TARGET)

LINKER_SCRIPT := $(COMMON_DIR)/link_asm.lds

INCLUDES += -I$(COMMON_DIR)

LDFLAGS += -T $(LINKER_SCRIPT) -nostartfiles -Wl,--gc-sections -Wl,--check-sections

ASM_OBJS := $(ASM_SRCS:.S=.o)

LINK_OBJS += $(ASM_OBJS)
LINK_DEPS += $(LINKER_SCRIPT)

CLEAN_OBJS += $(TARGET) $(LINK_OBJS) $(TARGET).dump $(TARGET).bin

CFLAGS += -march=$(RISCV_ARCH)
CFLAGS += -mabi=$(RISCV_ABI)
CFLAGS += -mcmodel=$(RISCV_MCMODEL) -ffunction-sections -fdata-sections -fno-builtin-printf -fno-builtin-malloc

$(TARGET): $(LINK_OBJS) $(LINK_DEPS) Makefile
	$(RISCV_GCC) $(CFLAGS) $(INCLUDES) $(LINK_OBJS) -o $@ $(LDFLAGS)
	$(RISCV_OBJCOPY) -O binary $@ $@.bin
	$(RISCV_OBJDUMP) --disassemble-all $@ > $@.dump

$(ASM_OBJS): %.o: %.S
	$(RISCV_GCC) $(CFLAGS) $(INCLUDES) -c -o $@ $<

.PHONY: clean
clean:
	rm -f $(CLEAN_OBJS)
