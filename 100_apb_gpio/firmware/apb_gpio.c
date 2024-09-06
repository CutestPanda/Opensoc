/************************************************************************************************************************
APB-GPIO����(��Դ�ļ�)
@brief  APB-GPIO����
@date   2024/08/23
@author �¼�ҫ
@eidt   2024/08/23 1.00 �����˵�һ����ʽ�汾
************************************************************************************************************************/

#include "apb_gpio.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  ��ʼ��APB-GPIO
@param  apb_gpio APB-GPIO(�ṹ��ָ��)
        base_addr APB-GPIO�������ַ
@return none
*************************/
void apb_gpio_init(ApbGPIO* apb_gpio, uint32_t base_addr){
	apb_gpio->hardware = (ApbGPIOHd*)base_addr;
}

/*************************
@io
@public
@brief  APB-GPIOд��ƽ
@param  apb_gpio APB-GPIO(�ṹ��ָ��)
        mask д��ƽ����
        value ��д��ƽֵ
@return none
*************************/
void apb_gpio_write_pin(ApbGPIO* apb_gpio, uint32_t mask, uint32_t value){
	apb_gpio->hardware->out_mask = mask;
	apb_gpio->hardware->out_v = value;
}

/*************************
@io
@public
@brief  APB-GPIO����ƽ
@param  apb_gpio APB-GPIO(�ṹ��ָ��)
@return ��ȡ���ĵ�ƽֵ
*************************/
uint32_t apb_gpio_read_pin(ApbGPIO* apb_gpio){
	return apb_gpio->hardware->in_v;
}

/*************************
@io
@public
@brief  APB-GPIO������̬�ŷ���
@param  apb_gpio APB-GPIO(�ṹ��ָ��)
        dire ��������(0��ʾ���, 1��ʾ����)
@return none
*************************/
void apb_gpio_set_direction(ApbGPIO* apb_gpio, uint32_t dire){
	apb_gpio->now_dire = dire;
	apb_gpio->hardware->dire = dire;
}

/*************************
@cfg
@public
@brief  APB-GPIOʹ���ж�
@param  apb_gpio APB-GPIO(�ṹ��ָ��)
        itr_en �ж�ʹ������
@return none
*************************/
void apb_gpio_enable_itr(ApbGPIO* apb_gpio, uint32_t itr_en){
	apb_gpio->hardware->itr_global = 0x00000001;
	apb_gpio->hardware->itr_en = itr_en;
}

/*************************
@cfg
@public
@brief  APB-GPIO�����ж�
@param  apb_gpio APB-GPIO(�ṹ��ָ��)
@return none
*************************/
void apb_gpio_disable_itr(ApbGPIO* apb_gpio){
	apb_gpio->hardware->itr_global = 0x00000000;
}

/*************************
@sts
@public
@brief  APB-GPIO��ȡ�ж�״̬
@param  apb_gpio APB-GPIO(�ṹ��ָ��)
@return �ж�״̬����
*************************/
uint32_t apb_gpio_get_itr_status(ApbGPIO* apb_gpio){
	return apb_gpio->hardware->itr_status;
}

/*************************
@cfg
@public
@brief  APB-GPIO����жϱ�־
@param  apb_gpio APB-GPIO(�ṹ��ָ��)
@return none
*************************/
void apb_gpio_clear_itr_flag(ApbGPIO* apb_gpio){
	apb_gpio->hardware->itr_global = 0x00000001;
}
