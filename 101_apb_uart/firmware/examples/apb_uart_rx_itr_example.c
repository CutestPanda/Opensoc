/************************************************************************************************************************
APB-UART示例代码
@brief  UART接收IDLE中断示例
@attention 请根据硬件平台更换与全局中断控制器相关的API
@date   2024/08/28
@author 陈家耀
@eidt   2024/08/28 1.00 创建了第一个正式版本
************************************************************************************************************************/

#include "../apb_uart.h"

#include "CMSDK_CM0.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define APB_UART_BASEADDR 0x40000000 // APB-UART外设基地址

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static ApbUART uart; // APB-UART外设结构体

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@itr_handler
@private
@brief  APB-UART收发中断服务程序(示例)
@param  none
@return none
*************************/
void USER_UART_Handler(void){
	uint8_t byte;
	
	while(!apb_uart_rev_byte(&uart, &byte)){ // 收集UART数据包
		apb_uart_send_byte(&uart, byte); // 按原样发回
	}
	
	apb_uart_clear_itr_flag(&uart); // 清零中断标志
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_uart_rx_itr_example(void){
	apb_uart_init(&uart, APB_UART_BASEADDR); // 初始化APB-UART
	
	// 配置UART接收IDLE中断
	const ApbUartItrThConfig uart_config = {10, 100, 10, 100}; // UART接收中断IDLE周期数阈值 = 100
	
	apb_uart_enable_itr(&uart, APB_UART_RX_IDLE_ITR_MASK, &uart_config); // 使能UART接收IDLE中断
	
	NVIC_SetPriority((IRQn_Type)4, 0x03); // NVIC设置4号中断优先级
	NVIC_EnableIRQ((IRQn_Type)4); // NVIC使能4号中断
	
	while(1);
}
