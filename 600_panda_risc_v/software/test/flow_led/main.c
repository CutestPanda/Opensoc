#include <stdint.h>

#include "../../include/utils.h"
#include "../../include/apb_gpio.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设基地址
#define GPIO0_BASEADDE 0x40000000

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设句柄
static ApbGPIO gpio0;

// 流水灯
const static uint8_t flow_led_out_value[9] = {0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01, 0x00}; // 流水灯样式
static uint8_t flow_led_id = 0; // 流水灯状态
static uint8_t flow_led_style_sel = 0; // 流水灯样式选择

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(){
	apb_gpio_init(&gpio0, GPIO0_BASEADDE); // 初始化GPIO
	apb_gpio_set_direction(&gpio0, 0xFFFFFF00); // 设置GPIO方向
	
    while(1){
        apb_gpio_write_pin(&gpio0, 0x000000FF, (uint32_t)flow_led_out_value[flow_led_style_sel ? (8 - flow_led_id):flow_led_id]);
		
		for(int i = 0;i < 1000000;i++);
		
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
