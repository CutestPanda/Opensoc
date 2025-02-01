#include <stdint.h>

#include "../../include/utils.h"
#include "../../include/clint.h"
#include "../../include/apb_gpio.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设基地址
#define GPIO0_BASEADDE 0x40000000
#define CLINT_BASEADDE 0xF4000000

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设句柄
static ApbGPIO gpio0;
static CLINT clint;

// LED
static uint8_t to_toggle_led = 0;
static uint8_t led_v = 0;

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void tmr_irq_handler(){
	to_toggle_led = 1;
	
	clint_set_mtime(&clint, 0);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(){
	apb_gpio_init(&gpio0, GPIO0_BASEADDE); // 初始化GPIO
	apb_gpio_set_direction(&gpio0, 0xFFFFFF00); // 设置GPIO方向
	
	// 初始化CLINT
	clint_init(&clint, CLINT_BASEADDE);
	clint_set_mtime(&clint, 0);
	clint_set_mtimecmp(&clint, 1000);
	
	// 使能计时器中断
    // MSIE = 0, MTIE = 1, MEIE = 0
    write_csr(mie, 0x00000080);
	
    while(1){
		if(to_toggle_led){
			apb_gpio_write_pin(&gpio0, 0x00000001, (uint32_t)led_v);
			
			led_v = !led_v;
			
			to_toggle_led = 0;
		}
    }
}
