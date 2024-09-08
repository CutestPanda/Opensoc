/************************************************************************************************************************
APB-UART驱动(接口头文件)
@brief  APB-UART驱动
@date   2024/08/28
@author 陈家耀
************************************************************************************************************************/

#include <stdint.h>
#include <stdarg.h>
#include <string.h>
#include <stdio.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __APB_UART_H
#define __APB_UART_H

typedef struct{
	uint32_t fifo_cs; // 收发fifo控制
	uint32_t itr_status_en; // 中断控制
	uint32_t tx_itr_th; // 发送中断阈值
	uint32_t rx_itr_th; // 接收中断阈值
}ApbUARTHd;

typedef struct{
	ApbUARTHd* hardware; // APB-UART寄存器接口(结构体指针)
	uint8_t itr_en; // 当前的中断使能向量
}ApbUART;

typedef struct{
	uint16_t tx_bytes_n_th; // UART发送中断字节数阈值
	uint16_t tx_idle_th; // UART发送中断IDLE周期数阈值
	uint16_t rx_bytes_n_th; // UART接收中断字节数阈值
	uint16_t rx_idle_th; // UART接收中断IDLE周期数阈值
}ApbUartItrThConfig;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 中断类型掩码
#define APB_UART_TX_BYTES_N_ITR_MASK 0x01 // UART发送达到规定字节数中断
#define APB_UART_TX_IDLE_ITR_MASK 0x02 // UART发送IDLE中断
#define APB_UART_RX_BYTES_N_ITR_MASK 0x04 // UART接收达到规定字节数中断
#define APB_UART_RX_IDLE_ITR_MASK 0x08 // UART接收IDLE中断
#define APB_UART_RX_ERR_ITR_MASK 0x10 // UART接收FIFO溢出中断

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_uart_init(ApbUART* uart, uint32_t base_addr); // 初始化APB-UART

int apb_uart_send_byte(ApbUART* uart, uint8_t byte); // APB-UART发送一个字节
int apb_uart_rev_byte(ApbUART* uart, uint8_t* byte); // APB-UART获取一个接收字节

void apb_uart_enable_itr(ApbUART* uart, uint8_t itr_mask, const ApbUartItrThConfig* config); // APB-UART使能中断
void apb_uart_disable_itr(ApbUART* uart); // APB-UART除能中断
uint8_t apb_uart_get_itr_status(ApbUART* uart); // APB-UART获取中断状态
void apb_uart_clear_itr_flag(ApbUART* uart); // APB-UART清除中断标志

void uart_printf(ApbUART* uart, char *fmt, ...); // APB-UART格式化发送字符串
