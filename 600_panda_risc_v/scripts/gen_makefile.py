import os
import argparse

def parse_opt():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", type=str, default="unknown", help="target to make")
    parser.add_argument("--debug", action="store_true", help="attatch symbol message")
    opt = parser.parse_args()
    
    return opt

if __name__ == "__main__":
    opt = parse_opt()
    
    target = opt.target
    
    file = open("Makefile", 'w')
    
    file.writelines("RISCV_ARCH := rv32im\n")
    file.writelines("RISCV_ABI := ilp32\n")
    file.writelines("RISCV_MCMODEL := medlow\n")
    file.writelines("\n")
    file.writelines("TARGET = " + target + "\n")
    file.writelines("\n")
    if opt.debug == True:
        file.writelines("CFLAGS += -g\n")
    file.writelines("#CFLAGS += -DSIMULATION\n")
    file.writelines("#CFLAGS += -O2\n")
    file.writelines("#ASM_SRCS +=\n")
    file.writelines("#LDFLAGS +=\n")
    file.writelines("#INCLUDES += -I.\n")
    file.writelines("\n")
    file.writelines("C_SRCS := $(wildcard *.c)\n")
    file.writelines("\n")
    file.writelines("COMMON_DIR = ../..\n")
    file.writelines("TOOLCHAIN_DIR = ../../..\n")
    file.writelines("include ../../common.mk\n")
    
    file.close()
