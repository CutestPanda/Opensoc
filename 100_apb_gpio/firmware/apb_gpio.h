/************************************************************************************************************************
APB-GPIO����(�ӿ�ͷ�ļ�)
@brief  APB-GPIO����
@date   2024/08/23
@author �¼�ҫ
************************************************************************************************************************/

#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __APB_GPIO_H
#define __APB_GPIO_H

typedef struct{
	uint32_t out_v; // GPIO���
	uint32_t out_mask; // GPIOд��ƽ����
	uint32_t dire; // GPIO����(0��ʾ���, 1��ʾ����)
	uint32_t in_v; // GPIO����
	uint32_t itr_global; // ȫ���ж�ʹ��, ȫ���жϱ�־
	uint32_t itr_status; // �ж�״̬
	uint32_t itr_en; // �ж�ʹ��
}ApbGPIOHd;

typedef struct{
	ApbGPIOHd* hardware; // APB-GPIO�Ĵ����ӿ�(�ṹ��ָ��)
	uint32_t now_dire; // ��ǰ��GPIO����(0��ʾ���, 1��ʾ����)
}ApbGPIO;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_gpio_init(ApbGPIO* apb_gpio, uint32_t base_addr); // ��ʼ��APB-GPIO
void apb_gpio_write_pin(ApbGPIO* apb_gpio, uint32_t mask, uint32_t value); // APB-GPIOд��ƽ
uint32_t apb_gpio_read_pin(ApbGPIO* apb_gpio); // APB-GPIO����ƽ
void apb_gpio_set_direction(ApbGPIO* apb_gpio, uint32_t dire); // APB-GPIO������̬�ŷ���

void apb_gpio_enable_itr(ApbGPIO* apb_gpio, uint32_t itr_en); // APB-GPIOʹ���ж�
void apb_gpio_disable_itr(ApbGPIO* apb_gpio); // APB-GPIO�����ж�
uint32_t apb_gpio_get_itr_status(ApbGPIO* apb_gpio); // APB-GPIO��ȡ�ж�״̬
void apb_gpio_clear_itr_flag(ApbGPIO* apb_gpio); // APB-GPIO����жϱ�־
