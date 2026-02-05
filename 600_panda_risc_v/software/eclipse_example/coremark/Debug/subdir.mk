################################################################################
# Automatically-generated file. Do not edit!
################################################################################

# Add inputs and outputs from these tool invocations to the build variables 
C_SRCS += \
../core_list_join.c \
../core_main.c \
../core_matrix.c \
../core_portme.c \
../core_state.c \
../core_util.c 

OBJS += \
./core_list_join.o \
./core_main.o \
./core_matrix.o \
./core_portme.o \
./core_state.o \
./core_util.o 

C_DEPS += \
./core_list_join.d \
./core_main.d \
./core_matrix.d \
./core_portme.d \
./core_state.d \
./core_util.d 


# Each subdirectory must supply rules for building sources it contributes
%.o: ../%.c subdir.mk
	@echo 'Building file: $<'
	@echo 'Invoking: GNU RISC-V Cross C Compiler'
	riscv-none-embed-gcc -march=rv32im -mabi=ilp32 -mcmodel=medlow -msmall-data-limit=8 -mno-save-restore -O2 -fmessage-length=0 -fsigned-char -ffunction-sections -fdata-sections -fno-common -funroll-loops -finline-functions --param max-inline-insns-auto=20 -falign-functions=4 -falign-jumps=4 -falign-loops=4 -g3 -DCPU_FREQ_MHZ=75 -std=gnu11 -MMD -MP -MF"$(@:%.o=%.d)" -MT"$@" -c -o "$@" "$<"
	@echo 'Finished building: $<'
	@echo ' '


