#include <stdint.h>

#include "../../include/utils.h"
#include "../../include/apb_gpio.h"
#include "../../include/apb_uart.h"
#include "../../include/xprintf.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设基地址
#define GPIO0_BASEADDE 0x40000000
#define UART0_BASEADDE 0x40003000

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static void uart_putc(uint8_t c);

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设句柄
static ApbGPIO gpio0;
static ApbUART uart0;

// 流水灯
const static uint8_t flow_led_out_value[9] = {0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01, 0x00}; // 流水灯样式
static uint8_t flow_led_id = 0; // 流水灯状态
static uint8_t flow_led_style_sel = 0; // 流水灯样式选择

// 串口打印
static uint8_t uart_print_num = 0; // 串口打印的数字

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static void uart_putc(uint8_t c){
	apb_uart_send_byte(&uart0, c);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(){
	apb_gpio_init(&gpio0, GPIO0_BASEADDE); // 初始化GPIO
	apb_gpio_set_direction(&gpio0, 0xFFFFFF00); // 设置GPIO方向
	
	apb_uart_init(&uart0, UART0_BASEADDE); // 初始化APB-UART
	
	xdev_out(uart_putc); // 重定向字符打印函数
	
	xprintf("hello world 1\r\nhello world 2\r\n");
	
    while(1){
        apb_gpio_write_pin(&gpio0, 0x000000FF, (uint32_t)flow_led_out_value[flow_led_style_sel ? (8 - flow_led_id):flow_led_id]);
		
		for(int i = 0;i < 2000000;i++);
		
		xprintf("num = %d\r\n", uart_print_num);
		
		uart_print_num++;
		
		if(apb_gpio_read_pin(&gpio0) & 0x00000100){
			flow_led_style_sel = 1;
		}else{
			flow_led_style_sel = 0;
		}
		
		if(flow_led_id == 8){
			flow_led_id = 0;
		}else{
			flow_led_id++;
		}
    }
}
