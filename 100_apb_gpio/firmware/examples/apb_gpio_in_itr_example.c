/************************************************************************************************************************
APB-GPIO示例代码
@brief  GPIO输入中断示例
@attention 请根据硬件平台更换与全局中断控制器相关的API
@date   2024/08/23
@author 陈家耀
@eidt   2024/08/23 1.00 创建了第一个正式版本
************************************************************************************************************************/

#include "../apb_gpio.h"

#include "CMSDK_CM0.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define APB_GPIO_BASEADDR 0x40000000 // APB-GPIO基地址

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static ApbGPIO gpio; // APB-GPIO外设结构体

static uint8_t led_pin_value = 0x00; // 1号通道当前的输出电平值

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@itr_handler
@private
@brief  APB-GPIO输入中断服务程序(示例)
@param  none
@return none
*************************/
void USER_GPIO_Handler(void){
	// 翻转1号通道的输出电平
	led_pin_value = !led_pin_value;
	apb_gpio_write_pin(&gpio, 0x00000002, led_pin_value ? 0xFFFFFFFF:0x00000000);
	
	apb_gpio_clear_itr_flag(&gpio); // 清除中断标志
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_gpio_in_itr_toggle_example(void){
	apb_gpio_init(&gpio, APB_GPIO_BASEADDR); // 初始化APB-GPIO
	
	apb_gpio_set_direction(&gpio, 0xFFFFFFFD); // 设置0号通道方向为输入, 1号通道方向为输出
	apb_gpio_write_pin(&gpio, 0x00000002, 0x00000000); // 设置1号通道输出低电平
	
	NVIC_SetPriority((IRQn_Type)3, 0x03); // NVIC设置3号中断优先级
	NVIC_EnableIRQ((IRQn_Type)3); // NVIC使能3号中断
	
	apb_gpio_enable_itr(&gpio, 0x00000001); // APB-GPIO使能0号通道的输入中断
	
	while(1);
}
