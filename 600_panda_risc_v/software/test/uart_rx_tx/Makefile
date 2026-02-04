RISCV_ARCH := rv32im
RISCV_ABI := ilp32
RISCV_MCMODEL := medlow


TARGET = uart_rx_tx

CFLAGS += -D CPU_FREQ_MHZ=50
#CFLAGS += -DSIMULATION
#CFLAGS += -O2
#ASM_SRCS +=
#LDFLAGS +=
#INCLUDES += -I.

C_SRCS := $(wildcard *.c)


COMMON_DIR = ../..
TOOLCHAIN_DIR = ../../..
include ../../common.mk
