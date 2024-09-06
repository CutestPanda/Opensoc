/************************************************************************************************************************
APB-GPIO示例代码
@brief  基于APB-GPIO实现流水灯
				流水灯绑定在GPIO外设的0~5号通道
@attention 请根据硬件平台更换与延迟(delay)相关的API
@date   2024/08/23
@author 陈家耀
@eidt   2024/08/23 1.00 创建了第一个正式版本
************************************************************************************************************************/

#include "../apb_gpio.h"
#include "delay.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define APB_GPIO_BASEADDR 0x40000000 // APB-GPIO基地址

////////////////////////////////////////////////////////////////////////////////////////////////////////////

const static uint8_t flow_led_out_value[7] = {0x20, 0x10, 0x08, 0x04, 0x02, 0x01, 0x00}; // 流水灯样式

static ApbGPIO gpio; // APB-GPIO外设结构体
static uint8_t flow_led_stage_cnt = 0; // 流水灯阶段计数器

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_gpio_flow_led_example(void){
	apb_gpio_init(&gpio, APB_GPIO_BASEADDR); // 初始化APB-GPIO
	
	apb_gpio_set_direction(&gpio, 0xFFFFFFC0); // 设置0~5号通道方向为输出
	apb_gpio_write_pin(&gpio, 0x0000003F, 0x00000000); // 设置0~5号通道输出低电平
	
	while(1){
		apb_gpio_write_pin(&gpio, 0x0000003F, (uint32_t)flow_led_out_value[flow_led_stage_cnt]); // 输出流水灯电平
		
		// 更新流水灯阶段计数器
		if(flow_led_stage_cnt == 6){
			flow_led_stage_cnt = 0;
		}else{
			flow_led_stage_cnt++;
		}
		
		delay_ms(500); // 延迟0.5s
	}
}
