RISCV_ARCH := rv32im
RISCV_ABI := ilp32
RISCV_MCMODEL := medlow


TARGET = debug_rom


#CFLAGS += -DSIMULATION
#CFLAGS += -O2
#ASM_SRCS +=
#LDFLAGS +=
#INCLUDES += -I.

ASM_SRCS := $(wildcard *.S)


COMMON_DIR = ../..
TOOLCHAIN_DIR = ../../..
include ../../common_asm.mk
