/************************************************************************************************************************
APB-GPIO驱动(主源文件)
@brief  APB-GPIO驱动
@date   2024/08/23
@author 陈家耀
@eidt   2024/08/23 1.00 创建了第一个正式版本
************************************************************************************************************************/

#include "apb_gpio.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  初始化APB-GPIO
@param  apb_gpio APB-GPIO(结构体指针)
        base_addr APB-GPIO外设基地址
@return none
*************************/
void apb_gpio_init(ApbGPIO* apb_gpio, uint32_t base_addr){
	apb_gpio->hardware = (ApbGPIOHd*)base_addr;
}

/*************************
@io
@public
@brief  APB-GPIO写电平
@param  apb_gpio APB-GPIO(结构体指针)
        mask 写电平掩码
        value 待写电平值
@return none
*************************/
void apb_gpio_write_pin(ApbGPIO* apb_gpio, uint32_t mask, uint32_t value){
	apb_gpio->hardware->out_mask = mask;
	apb_gpio->hardware->out_v = value;
}

/*************************
@io
@public
@brief  APB-GPIO读电平
@param  apb_gpio APB-GPIO(结构体指针)
@return 读取到的电平值
*************************/
uint32_t apb_gpio_read_pin(ApbGPIO* apb_gpio){
	return apb_gpio->hardware->in_v;
}

/*************************
@io
@public
@brief  APB-GPIO设置三态门方向
@param  apb_gpio APB-GPIO(结构体指针)
        dire 方向向量(0表示输出, 1表示输入)
@return none
*************************/
void apb_gpio_set_direction(ApbGPIO* apb_gpio, uint32_t dire){
	apb_gpio->now_dire = dire;
	apb_gpio->hardware->dire = dire;
}

/*************************
@cfg
@public
@brief  APB-GPIO使能中断
@param  apb_gpio APB-GPIO(结构体指针)
        itr_en 中断使能向量
@return none
*************************/
void apb_gpio_enable_itr(ApbGPIO* apb_gpio, uint32_t itr_en){
	apb_gpio->hardware->itr_global = 0x00000001;
	apb_gpio->hardware->itr_en = itr_en;
}

/*************************
@cfg
@public
@brief  APB-GPIO除能中断
@param  apb_gpio APB-GPIO(结构体指针)
@return none
*************************/
void apb_gpio_disable_itr(ApbGPIO* apb_gpio){
	apb_gpio->hardware->itr_global = 0x00000000;
}

/*************************
@sts
@public
@brief  APB-GPIO获取中断状态
@param  apb_gpio APB-GPIO(结构体指针)
@return 中断状态向量
*************************/
uint32_t apb_gpio_get_itr_status(ApbGPIO* apb_gpio){
	return apb_gpio->hardware->itr_status;
}

/*************************
@cfg
@public
@brief  APB-GPIO清除中断标志
@param  apb_gpio APB-GPIO(结构体指针)
@return none
*************************/
void apb_gpio_clear_itr_flag(ApbGPIO* apb_gpio){
	apb_gpio->hardware->itr_global = 0x00000001;
}
