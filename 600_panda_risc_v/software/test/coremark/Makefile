RISCV_ARCH := rv32im
RISCV_ABI := ilp32
RISCV_MCMODEL := medlow

TARGET := coremark

C_SRCS := $(wildcard *.c)

CFLAGS := -O2 -fno-common -funroll-loops -finline-functions --param max-inline-insns-auto=20 -falign-functions=4 -falign-jumps=4 -falign-loops=4
CFLAGS += -DFLAGS_STR=\""$(CFLAGS)"\"
CFLAGS += -DITERATIONS=10000 -DPERFORMANCE_RUN=1

COMMON_DIR = ../..
TOOLCHAIN_DIR = ../../..
include ../../common.mk
