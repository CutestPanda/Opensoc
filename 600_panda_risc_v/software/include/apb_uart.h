/************************************************************************************************************************
APB-UART����(�ӿ�ͷ�ļ�)
@brief  APB-UART����
@date   2024/08/28
@author �¼�ҫ
************************************************************************************************************************/

#include <stdint.h>
#include <stdarg.h>
#include <string.h>
#include <stdio.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __APB_UART_H
#define __APB_UART_H

typedef struct{
	uint32_t fifo_cs; // �շ�fifo����
	uint32_t itr_status_en; // �жϿ���
	uint32_t tx_itr_th; // �����ж���ֵ
	uint32_t rx_itr_th; // �����ж���ֵ
}ApbUARTHd;

typedef struct{
	ApbUARTHd* hardware; // APB-UART�Ĵ����ӿ�(�ṹ��ָ��)
	uint8_t itr_en; // ��ǰ���ж�ʹ������
}ApbUART;

typedef struct{
	uint16_t tx_bytes_n_th; // UART�����ж��ֽ�����ֵ
	uint16_t tx_idle_th; // UART�����ж�IDLE��������ֵ
	uint16_t rx_bytes_n_th; // UART�����ж��ֽ�����ֵ
	uint16_t rx_idle_th; // UART�����ж�IDLE��������ֵ
}ApbUartItrThConfig;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// �ж���������
#define APB_UART_TX_BYTES_N_ITR_MASK 0x01 // UART���ʹﵽ�涨�ֽ����ж�
#define APB_UART_TX_IDLE_ITR_MASK 0x02 // UART����IDLE�ж�
#define APB_UART_RX_BYTES_N_ITR_MASK 0x04 // UART���մﵽ�涨�ֽ����ж�
#define APB_UART_RX_IDLE_ITR_MASK 0x08 // UART����IDLE�ж�
#define APB_UART_RX_ERR_ITR_MASK 0x10 // UART����FIFO����ж�

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_uart_init(ApbUART* uart, uint32_t base_addr); // ��ʼ��APB-UART

int apb_uart_send_byte(ApbUART* uart, uint8_t byte); // APB-UART����һ���ֽ�
int apb_uart_rev_byte(ApbUART* uart, uint8_t* byte); // APB-UART��ȡһ�������ֽ�

void apb_uart_enable_itr(ApbUART* uart, uint8_t itr_mask, const ApbUartItrThConfig* config); // APB-UARTʹ���ж�
void apb_uart_disable_itr(ApbUART* uart); // APB-UART�����ж�
uint8_t apb_uart_get_itr_status(ApbUART* uart); // APB-UART��ȡ�ж�״̬
void apb_uart_clear_itr_flag(ApbUART* uart); // APB-UART����жϱ�־

void uart_printf(ApbUART* uart, char *fmt, ...); // APB-UART��ʽ�������ַ���
