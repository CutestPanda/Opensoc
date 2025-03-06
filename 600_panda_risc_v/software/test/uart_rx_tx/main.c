#include <stdint.h>

#include "../../include/utils.h"
#include "../../include/plic.h"

#include "../../include/apb_gpio.h"
#include "../../include/apb_uart.h"
#include "../../include/xprintf.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设基地址
#define GPIO0_BASEADDE 0x40000000
#define UART0_BASEADDE 0x40003000

// PLIC基地址
#define PLIC_BASEADDE 0xF0000000

// 中断号
#define GPIO0_ITR_ID 1 // GPIO0中断号
#define TIMER0_ITR_ID 2 // TIMER0中断号
#define UART0_ITR_ID 3 // UART0中断号

// UART
#define UART_RX_LEN 256 // UART接收缓冲区长度

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static void uart0_itr_handler();
static void uart_putc(uint8_t c);

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设句柄
static ApbGPIO gpio0;
static ApbUART uart0;

// PLIC句柄
static PLIC plic;

// 流水灯
const static uint8_t flow_led_out_value[9] = {0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01, 0x00}; // 流水灯样式
static uint8_t flow_led_id = 0; // 流水灯状态
static uint8_t flow_led_style_sel = 0; // 流水灯样式选择

// UART
static uint8_t uart_rx_buf[UART_RX_LEN]; // UART接收缓冲区
static uint16_t uart_rx_n = 0; // UART接收字节数

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void ext_irq_handler(){
	uint32_t now_itr_id = plic_claim_interrupt(&plic);
	
	switch(now_itr_id){
		case GPIO0_ITR_ID:
			break;
		case TIMER0_ITR_ID:
			break;
		case UART0_ITR_ID:
			uart0_itr_handler();
			break;
		default:
			break;
	}
	
	plic_complete_interrupt(&plic, now_itr_id);
}

static void uart0_itr_handler(){
	// 收集UART数据包
	uint8_t byte;
	
	while(!apb_uart_rev_byte(&uart0, &byte)){
		if(uart_rx_n < UART_RX_LEN){
			uart_rx_buf[uart_rx_n] = byte;
		}
		uart_rx_n++;
	}
	
	apb_uart_clear_itr_flag(&uart0); // 清零中断标志
}

static void uart_putc(uint8_t c){
	apb_uart_send_byte(&uart0, c);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(){
	// 使能外部中断
    // MSIE = 0, MTIE = 0, MEIE = 1
    write_csr(mie, 0x00000800);
	
	// 初始化PLIC
	plic_init(&plic, PLIC_BASEADDE);
	plic_set_threshold(&plic, 0);
	plic_set_priority(&plic, UART0_ITR_ID, 1);
	plic_enable_interrupt(&plic, UART0_ITR_ID);
	
	apb_gpio_init(&gpio0, GPIO0_BASEADDE); // 初始化GPIO
	apb_gpio_set_direction(&gpio0, 0xFFFFFF00); // 设置GPIO方向
	
	apb_uart_init(&uart0, UART0_BASEADDE); // 初始化APB-UART
	// 使能UART接收IDLE中断
	const ApbUartItrThConfig uart_config = {10, 100, 10, 100};
	apb_uart_enable_itr(&uart0, APB_UART_RX_IDLE_ITR_MASK, &uart_config);
	
	xdev_out(uart_putc); // 重定向字符打印函数
	
	xprintf("hello world 1\r\nhello world 2\r\n\r\n");
	
    while(1){
		xprintf("1 + 1 = ?\r\n");
		
		while(!uart_rx_n);
		
		xprintf("rx_n = %d content = ", uart_rx_n);
		for(uint16_t i = 0;i < uart_rx_n;i++){
			apb_uart_send_byte(&uart0, uart_rx_buf[i]);
		}
		apb_uart_send_byte(&uart0, (uint8_t)' ');
		
		if((uart_rx_n == 1) && (uart_rx_buf[0] == '2')){
			xprintf("good\r\n");
		}else{
			xprintf("bad\r\n");
		}
		
		uart_rx_n = 0;
    }
}
