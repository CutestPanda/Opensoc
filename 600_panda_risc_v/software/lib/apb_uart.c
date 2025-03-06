/************************************************************************************************************************
APB-UART驱动(主源文件)
@brief  APB-UART驱动
@date   2024/08/28
@author 陈家耀
@eidt   2024/08/28 1.00 创建了第一个正式版本
************************************************************************************************************************/

#include "../include/apb_uart.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  初始化APB-UART
@param  uart APB-UART(结构体指针)
        base_addr APB-UART外设基地址
@return none
*************************/
void apb_uart_init(ApbUART* uart, uint32_t base_addr){
	uart->hardware = (ApbUARTHd*)base_addr;
	uart->itr_en = 0x00;
}

/*************************
@io
@public
@brief  APB-UART发送一个字节
@param  uart APB-UART(结构体指针)
        byte 待发送的字节数据
@return 是否成功
*************************/
int apb_uart_send_byte(ApbUART* uart, uint8_t byte){
	uint32_t fifo_cs = uart->hardware->fifo_cs;
	
	if(fifo_cs & 0x01){
		return -1;
	}else{
		volatile uint32_t* LocalAddr = &(uart->hardware->fifo_cs);
		
		fifo_cs &= (~0x3FC);
		fifo_cs |= ((uint32_t)byte) << 2;
		
		*LocalAddr = fifo_cs;
		*LocalAddr = (fifo_cs | 0x02);
		*LocalAddr = (fifo_cs & (~0x02));
		
		return 0;
	}
}

/*************************
@io
@public
@brief  APB-UART获取一个接收字节
@param  uart APB-UART(结构体指针)
        byte 接收字节数据缓冲区(首地址)
@return 是否成功
*************************/
int apb_uart_rev_byte(ApbUART* uart, uint8_t* byte){
	uint32_t fifo_cs = uart->hardware->fifo_cs;
	
	if(fifo_cs & 0x400){
		return -1;
	}else{
		volatile uint32_t* LocalAddr = &(uart->hardware->fifo_cs);
		
		*LocalAddr = (fifo_cs | 0x800);
		*LocalAddr = (fifo_cs & (~0x800));
		
		fifo_cs = *LocalAddr;
		*byte = (fifo_cs >> 12) & 0xFF;
		
		return 0;
	}
}

/*************************
@cfg
@public
@brief  APB-UART使能中断
@param  uart APB-UART(结构体指针)
        itr_mask 中断使能向量
				config 收发中断阈值配置(结构体指针)
@return none
*************************/
void apb_uart_enable_itr(ApbUART* uart, uint8_t itr_mask, const ApbUartItrThConfig* config){
	uart->hardware->itr_status_en = 0x00000001 | (itr_mask << 1);
	uart->itr_en = itr_mask;
	
	uart->hardware->tx_itr_th = 
		((uint32_t)(config->tx_bytes_n_th - 1)) | (((uint32_t)(config->tx_idle_th - 2)) << 16);
	uart->hardware->rx_itr_th =
		((uint32_t)(config->rx_bytes_n_th - 1)) | (((uint32_t)(config->rx_idle_th - 2)) << 16);
}

/*************************
@cfg
@public
@brief  APB-UART除能中断
@param  uart APB-UART(结构体指针)
@return none
*************************/
void apb_uart_disable_itr(ApbUART* uart){
	uart->hardware->itr_status_en = 0x00000000;
	uart->itr_en = 0x00;
}

/*************************
@sts
@public
@brief  APB-UART获取中断状态
@param  uart APB-UART(结构体指针)
@return 中断状态
*************************/
uint8_t apb_uart_get_itr_status(ApbUART* uart){
	uint32_t itr_status_en = uart->hardware->itr_status_en;
	
	return (uint8_t)(itr_status_en >> 17) & 0x1F;
}

/*************************
@cfg
@public
@brief  APB-UART清除中断标志
@param  uart APB-UART(结构体指针)
@return none
*************************/
void apb_uart_clear_itr_flag(ApbUART* uart){
	uart->hardware->itr_status_en = 0x00000001 | (uart->itr_en << 1);
}

/*************************
@io
@public
@brief  APB-UART格式化发送字符串
@param  uart APB-UART(结构体指针)
			  fmt 格式化字符串
        ... 字符串附加参数
@return none
*************************/
void uart_printf(ApbUART* uart, char *fmt, ...){
	unsigned char UsartPrintfBuf[296];
	va_list ap;
	unsigned char* pStr = UsartPrintfBuf;
	
	va_start(ap, fmt);
	vsnprintf((char *)UsartPrintfBuf, sizeof(UsartPrintfBuf), (const char *)fmt, ap);                      
	va_end(ap);
	
	while(*pStr != 0){
		while (!apb_uart_send_byte(uart, *pStr));
		
		pStr++;
	}
}
