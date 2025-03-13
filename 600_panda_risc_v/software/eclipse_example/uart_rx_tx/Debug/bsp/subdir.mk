################################################################################
# Automatically-generated file. Do not edit!
################################################################################

# Add inputs and outputs from these tool invocations to the build variables 
C_SRCS += \
../bsp/apb_gpio.c \
../bsp/apb_i2c.c \
../bsp/apb_timer.c \
../bsp/apb_uart.c \
../bsp/clint.c \
../bsp/init.c \
../bsp/plic.c \
../bsp/trap_handler.c \
../bsp/utils.c \
../bsp/xprintf.c 

S_UPPER_SRCS += \
../bsp/start.S \
../bsp/trap_entry.S 

OBJS += \
./bsp/apb_gpio.o \
./bsp/apb_i2c.o \
./bsp/apb_timer.o \
./bsp/apb_uart.o \
./bsp/clint.o \
./bsp/init.o \
./bsp/plic.o \
./bsp/start.o \
./bsp/trap_entry.o \
./bsp/trap_handler.o \
./bsp/utils.o \
./bsp/xprintf.o 

S_UPPER_DEPS += \
./bsp/start.d \
./bsp/trap_entry.d 

C_DEPS += \
./bsp/apb_gpio.d \
./bsp/apb_i2c.d \
./bsp/apb_timer.d \
./bsp/apb_uart.d \
./bsp/clint.d \
./bsp/init.d \
./bsp/plic.d \
./bsp/trap_handler.d \
./bsp/utils.d \
./bsp/xprintf.d 


# Each subdirectory must supply rules for building sources it contributes
bsp/%.o: ../bsp/%.c bsp/subdir.mk
	@echo 'Building file: $<'
	@echo 'Invoking: GNU RISC-V Cross C Compiler'
	riscv-none-embed-gcc -march=rv32im -mabi=ilp32 -mcmodel=medlow -msmall-data-limit=8 -mno-save-restore -O0 -fmessage-length=0 -fsigned-char -ffunction-sections -fdata-sections -g3 -std=gnu11 -MMD -MP -MF"$(@:%.o=%.d)" -MT"$@" -c -o "$@" "$<"
	@echo 'Finished building: $<'
	@echo ' '

bsp/%.o: ../bsp/%.S bsp/subdir.mk
	@echo 'Building file: $<'
	@echo 'Invoking: GNU RISC-V Cross Assembler'
	riscv-none-embed-gcc -march=rv32im -mabi=ilp32 -mcmodel=medlow -msmall-data-limit=8 -mno-save-restore -O0 -fmessage-length=0 -fsigned-char -ffunction-sections -fdata-sections -g3 -x assembler-with-cpp -MMD -MP -MF"$(@:%.o=%.d)" -MT"$@" -c -o "$@" "$<"
	@echo 'Finished building: $<'
	@echo ' '


