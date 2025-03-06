/************************************************************************************************************************
APB-GPIO驱动(接口头文件)
@brief  APB-GPIO驱动
@date   2024/08/23
@author 陈家耀
************************************************************************************************************************/

#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __APB_GPIO_H
#define __APB_GPIO_H

typedef struct{
	uint32_t out_v; // GPIO输出
	uint32_t out_mask; // GPIO写电平掩码
	uint32_t dire; // GPIO方向(0表示输出, 1表示输入)
	uint32_t in_v; // GPIO输入
	uint32_t itr_global; // 全局中断使能, 全局中断标志
	uint32_t itr_status; // 中断状态
	uint32_t itr_en; // 中断使能
}ApbGPIOHd;

typedef struct{
	ApbGPIOHd* hardware; // APB-GPIO寄存器接口(结构体指针)
	uint32_t now_dire; // 当前的GPIO方向(0表示输出, 1表示输入)
}ApbGPIO;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_gpio_init(ApbGPIO* apb_gpio, uint32_t base_addr); // 初始化APB-GPIO
void apb_gpio_write_pin(ApbGPIO* apb_gpio, uint32_t mask, uint32_t value); // APB-GPIO写电平
uint32_t apb_gpio_read_pin(ApbGPIO* apb_gpio); // APB-GPIO读电平
void apb_gpio_set_direction(ApbGPIO* apb_gpio, uint32_t dire); // APB-GPIO设置三态门方向

void apb_gpio_enable_itr(ApbGPIO* apb_gpio, uint32_t itr_en); // APB-GPIO使能中断
void apb_gpio_disable_itr(ApbGPIO* apb_gpio); // APB-GPIO除能中断
uint32_t apb_gpio_get_itr_status(ApbGPIO* apb_gpio); // APB-GPIO获取中断状态
void apb_gpio_clear_itr_flag(ApbGPIO* apb_gpio); // APB-GPIO清除中断标志
