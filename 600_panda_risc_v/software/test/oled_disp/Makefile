RISCV_ARCH := rv32im
RISCV_ABI := ilp32
RISCV_MCMODEL := medlow


TARGET = oled_disp


#CFLAGS += -DSIMULATION
#CFLAGS += -O2
#ASM_SRCS +=
#LDFLAGS +=
#INCLUDES += -I.

C_SRCS := \
	main.c \
	oled_i2c.c \

COMMON_DIR = ../..
TOOLCHAIN_DIR = ../../..
include ../../common.mk
