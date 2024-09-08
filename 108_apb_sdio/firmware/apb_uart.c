/************************************************************************************************************************
APB-UART����(��Դ�ļ�)
@brief  APB-UART����
@date   2024/08/28
@author �¼�ҫ
@eidt   2024/08/28 1.00 �����˵�һ����ʽ�汾
************************************************************************************************************************/

#include "apb_uart.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  ��ʼ��APB-UART
@param  uart APB-UART(�ṹ��ָ��)
        base_addr APB-UART�������ַ
@return none
*************************/
void apb_uart_init(ApbUART* uart, uint32_t base_addr){
	uart->hardware = (ApbUARTHd*)base_addr;
	uart->itr_en = 0x00;
}

/*************************
@io
@public
@brief  APB-UART����һ���ֽ�
@param  uart APB-UART(�ṹ��ָ��)
        byte �����͵��ֽ�����
@return �Ƿ�ɹ�
*************************/
int apb_uart_send_byte(ApbUART* uart, uint8_t byte){
	uint32_t fifo_cs = uart->hardware->fifo_cs;
	
	if(fifo_cs & 0x01){
		return -1;
	}else{
		fifo_cs &= (~0x3FC);
		fifo_cs |= ((uint32_t)byte) << 2;
		uart->hardware->fifo_cs = fifo_cs;
		
		uart->hardware->fifo_cs = (fifo_cs | 0x02);
		uart->hardware->fifo_cs = (fifo_cs & (~0x02));
		
		return 0;
	}
}

/*************************
@io
@public
@brief  APB-UART��ȡһ�������ֽ�
@param  uart APB-UART(�ṹ��ָ��)
        byte �����ֽ����ݻ�����(�׵�ַ)
@return �Ƿ�ɹ�
*************************/
int apb_uart_rev_byte(ApbUART* uart, uint8_t* byte){
	uint32_t fifo_cs = uart->hardware->fifo_cs;
	
	if(fifo_cs & 0x400){
		return -1;
	}else{
		uart->hardware->fifo_cs = (fifo_cs | 0x800);
		uart->hardware->fifo_cs = (fifo_cs & (~0x800));
		
		fifo_cs = uart->hardware->fifo_cs;
		*byte = (fifo_cs >> 12) & 0xFF;
		
		return 0;
	}
}

/*************************
@cfg
@public
@brief  APB-UARTʹ���ж�
@param  uart APB-UART(�ṹ��ָ��)
        itr_mask �ж�ʹ������
				config �շ��ж���ֵ����(�ṹ��ָ��)
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
@brief  APB-UART�����ж�
@param  uart APB-UART(�ṹ��ָ��)
@return none
*************************/
void apb_uart_disable_itr(ApbUART* uart){
	uart->hardware->itr_status_en = 0x00000000;
	uart->itr_en = 0x00;
}

/*************************
@sts
@public
@brief  APB-UART��ȡ�ж�״̬
@param  uart APB-UART(�ṹ��ָ��)
@return �ж�״̬
*************************/
uint8_t apb_uart_get_itr_status(ApbUART* uart){
	uint32_t itr_status_en = uart->hardware->itr_status_en;
	
	return (uint8_t)(itr_status_en >> 17) & 0x1F;
}

/*************************
@cfg
@public
@brief  APB-UART����жϱ�־
@param  uart APB-UART(�ṹ��ָ��)
@return none
*************************/
void apb_uart_clear_itr_flag(ApbUART* uart){
	uart->hardware->itr_status_en = 0x00000001 | (uart->itr_en << 1);
}

/*************************
@io
@public
@brief  APB-UART��ʽ�������ַ���
@param  uart APB-UART(�ṹ��ָ��)
			  fmt ��ʽ���ַ���
        ... �ַ������Ӳ���
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
