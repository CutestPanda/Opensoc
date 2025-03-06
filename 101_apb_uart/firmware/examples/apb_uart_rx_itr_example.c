/************************************************************************************************************************
APB-UARTʾ������
@brief  UART����IDLE�ж�ʾ��
@attention �����Ӳ��ƽ̨������ȫ���жϿ�������ص�API
@date   2024/08/28
@author �¼�ҫ
@eidt   2024/08/28 1.00 �����˵�һ����ʽ�汾
************************************************************************************************************************/

#include "../apb_uart.h"

#include "CMSDK_CM0.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define APB_UART_BASEADDR 0x40000000 // APB-UART�������ַ

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static ApbUART uart; // APB-UART����ṹ��

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@itr_handler
@private
@brief  APB-UART�շ��жϷ������(ʾ��)
@param  none
@return none
*************************/
void USER_UART_Handler(void){
	uint8_t byte;
	
	while(!apb_uart_rev_byte(&uart, &byte)){ // �ռ�UART���ݰ�
		apb_uart_send_byte(&uart, byte); // ��ԭ������
	}
	
	apb_uart_clear_itr_flag(&uart); // �����жϱ�־
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_uart_rx_itr_example(void){
	apb_uart_init(&uart, APB_UART_BASEADDR); // ��ʼ��APB-UART
	
	// ����UART����IDLE�ж�
	const ApbUartItrThConfig uart_config = {10, 100, 10, 100}; // UART�����ж�IDLE��������ֵ = 100
	
	apb_uart_enable_itr(&uart, APB_UART_RX_IDLE_ITR_MASK, &uart_config); // ʹ��UART����IDLE�ж�
	
	NVIC_SetPriority((IRQn_Type)4, 0x03); // NVIC����4���ж����ȼ�
	NVIC_EnableIRQ((IRQn_Type)4); // NVICʹ��4���ж�
	
	while(1);
}
