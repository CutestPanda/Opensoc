RISCV_ARCH := rv32im
RISCV_ABI := ilp32
RISCV_MCMODEL := medlow

TARGET = breathing_led

CFLAGS += -g3
#CFLAGS += -DSIMULATION
#CFLAGS += -O2
#ASM_SRCS +=
#LDFLAGS +=
#INCLUDES += -I.

C_SRCS := $(wildcard *.c)

COMMON_DIR = ../..
TOOLCHAIN_DIR = ../../..
include ../../common.mk
