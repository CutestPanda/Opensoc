#include <stdio.h>
#include <stdlib.h>
#include "coremark.h"
#include "../../include/utils.h"
#include "../../include/apb_uart.h"
#include "../../include/xprintf.h"

// UART外设基地址
#define UART0_BASEADDE 0x40003000

static void uart_putc(uint8_t c);

#if VALIDATION_RUN
	volatile ee_s32 seed1_volatile=0x3415;
	volatile ee_s32 seed2_volatile=0x3415;
	volatile ee_s32 seed3_volatile=0x66;
#endif

#if PERFORMANCE_RUN
	volatile ee_s32 seed1_volatile=0x0;
	volatile ee_s32 seed2_volatile=0x0;
	volatile ee_s32 seed3_volatile=0x66;
#endif

#if PROFILE_RUN
	volatile ee_s32 seed1_volatile=0x8;
	volatile ee_s32 seed2_volatile=0x8;
	volatile ee_s32 seed3_volatile=0x8;
#endif

volatile ee_s32 seed4_volatile=ITERATIONS;
volatile ee_s32 seed5_volatile=0;

static CORE_TICKS t0, t1;

// UART外设句柄
static ApbUART uart0;

static void uart_putc(uint8_t c){
	apb_uart_send_byte(&uart0, c);
}

void start_time(void)
{
  t0 = get_cycle_value();
}

void stop_time(void)
{
  t1 = get_cycle_value();
}

CORE_TICKS get_time(void)
{
  return t1 - t0;
}

secs_ret time_in_secs(CORE_TICKS ticks)
{
  // scale timer down to avoid uint64_t -> double conversion in RV32
  int scale = 256;
  uint32_t delta = ticks / scale;
  uint32_t freq = CPU_FREQ_HZ / scale;
  return delta / (double)freq;
}

void portable_init(core_portable *p, int *argc, char *argv[])
{
    apb_uart_init(&uart0, UART0_BASEADDE); // 初始化APB-UART
	
	xdev_out(uart_putc); // 重定向字符打印函数
}
