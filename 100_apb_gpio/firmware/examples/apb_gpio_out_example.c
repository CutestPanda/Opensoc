/************************************************************************************************************************
APB-GPIOʾ������
@brief  ����APB-GPIOʵ����ˮ��
				��ˮ�ư���GPIO�����0~5��ͨ��
@attention �����Ӳ��ƽ̨�������ӳ�(delay)��ص�API
@date   2024/08/23
@author �¼�ҫ
@eidt   2024/08/23 1.00 �����˵�һ����ʽ�汾
************************************************************************************************************************/

#include "../apb_gpio.h"
#include "delay.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define APB_GPIO_BASEADDR 0x40000000 // APB-GPIO����ַ

////////////////////////////////////////////////////////////////////////////////////////////////////////////

const static uint8_t flow_led_out_value[7] = {0x20, 0x10, 0x08, 0x04, 0x02, 0x01, 0x00}; // ��ˮ����ʽ

static ApbGPIO gpio; // APB-GPIO����ṹ��
static uint8_t flow_led_stage_cnt = 0; // ��ˮ�ƽ׶μ�����

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_gpio_flow_led_example(void){
	apb_gpio_init(&gpio, APB_GPIO_BASEADDR); // ��ʼ��APB-GPIO
	
	apb_gpio_set_direction(&gpio, 0xFFFFFFC0); // ����0~5��ͨ������Ϊ���
	apb_gpio_write_pin(&gpio, 0x0000003F, 0x00000000); // ����0~5��ͨ������͵�ƽ
	
	while(1){
		apb_gpio_write_pin(&gpio, 0x0000003F, (uint32_t)flow_led_out_value[flow_led_stage_cnt]); // �����ˮ�Ƶ�ƽ
		
		// ������ˮ�ƽ׶μ�����
		if(flow_led_stage_cnt == 6){
			flow_led_stage_cnt = 0;
		}else{
			flow_led_stage_cnt++;
		}
		
		delay_ms(500); // �ӳ�0.5s
	}
}
