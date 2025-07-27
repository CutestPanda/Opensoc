/************************************************************************************************************************
APB-TIMERʱ�ӻ�׼ʾ������
@brief  ����APB-TIMER����0.5s��ʱ��, ʵ��LED��ÿ��0.5s��˸
@attention �����Ӳ��ƽ̨������ȫ���жϿ�������ص�API
					 ����APB-TIMER��ʱ��Ϊ25MHz, 16λ��ʱ��
@date   2024/09/21
@author �¼�ҫ
@eidt   2024/09/21 1.00 �����˵�һ����ʽ�汾
************************************************************************************************************************/

#include "../apb_timer.h"
#include "apb_gpio.h"

#include "CMSDK_CM0.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define BASEADDR_TIMER 0x40000000 // APB-TIMER�������ַ
#define BASEADDR_GPIO 0x40001000 // APB-GPIO�������ַ

#define GPIO_LED_MASK 0x00000001 // LED��GPIO����

#define TIMER_ITR_ID 3 // APB-TIMER�жϺ�

#define TIMER_PSC 2500 // ��ʱ��Ԥ��Ƶϵ��
#define TIMER_ATL 5000 // ��ʱ���Զ�װ��ֵ

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static ApbGPIO gpio; // APB-GPIO����ṹ��
static ApbTimer timer; // APB-TIMER����ṹ��

static uint8_t led_out = 0; // ��ǰ��led�����ƽ

static uint8_t timer_period_elapsed = 0; // TIMER���������־

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@itr_handler
@private
@brief  APB-TIMER�жϷ������(ʾ��)
@param  none
@return none
*************************/
void USER_TIMER0_Handler(void){
	uint8_t itr_sts = apb_timer_get_itr_status(&timer); // ��ȡ�жϱ�־����
	
	if(itr_sts & ITR_TIMER_ELAPSED_MASK){ // ��������ж�
		timer_period_elapsed = 1;
	}
	
	apb_timer_clear_itr_flag(&timer); // ����жϱ�־
}

void apb_timer_timebase_example(void){
	// ��ʼ��APB-GPIO
	apb_gpio_init(&gpio, BASEADDR_GPIO);
	
	// ��ʼ��APB-TIMER
	ApbTimerConfig timer_config; // APB-TIMER(��ʼ�����ýṹ��)
	
	timer_config.prescale = TIMER_PSC - 1; // Ԥ��Ƶϵ�� - 1
	timer_config.auto_load = TIMER_ATL - 1; // �Զ�װ��ֵ - 1
	timer_config.chn_n = 0; // ͨ����
	timer_config.cap_cmp_sel = CAP_SEL_CHN0 | CAP_SEL_CHN1 | CAP_SEL_CHN2 | CAP_SEL_CHN3; // ����/�Ƚ�ѡ��
	// �Ƚ�ֵ
	timer_config.cmp[0] = 0;
	timer_config.cmp[1] = 0;
	timer_config.cmp[2] = 0;
	timer_config.cmp[3] = 0;
	// �Ƚ����ģʽ
	timer_config.oc_mode[0] = OC_MODE_GEQ_HIGH;
	timer_config.oc_mode[1] = OC_MODE_GEQ_HIGH;
	timer_config.oc_mode[2] = OC_MODE_GEQ_HIGH;
	timer_config.oc_mode[3] = OC_MODE_GEQ_HIGH;
	// ���ؼ������
	timer_config.edge_detect_type[0] = CAP_POS_EDGE;
	timer_config.edge_detect_type[1] = CAP_POS_EDGE;
	timer_config.edge_detect_type[2] = CAP_POS_EDGE;
	timer_config.edge_detect_type[3] = CAP_POS_EDGE;
	// �����˲���ֵ
	timer_config.edge_filter_th[0] = 0;
	timer_config.edge_filter_th[1] = 0;
	timer_config.edge_filter_th[2] = 0;
	timer_config.edge_filter_th[3] = 0;
	
	init_apb_timer(&timer, BASEADDR_TIMER, &timer_config);
	
	// ʹ��APB-TIMER��������ж�
	NVIC_SetPriority((IRQn_Type)TIMER_ITR_ID, 0x03); // NVIC����3���ж����ȼ�
	NVIC_EnableIRQ((IRQn_Type)TIMER_ITR_ID); // NVICʹ��3���ж�
	
	apb_timer_enable_itr(&timer, ITR_TIMER_ELAPSED_MASK);
	
	// ������ʱ��
	__apb_timer_set_cnt(&timer, TIMER_ATL - 1);
	__apb_timer_start(&timer);
	
	while(1){
		if(timer_period_elapsed){
			apb_gpio_write_pin(&gpio, GPIO_LED_MASK, (uint32_t)led_out);
			
			led_out = !led_out;
			
			timer_period_elapsed = 0;
		}
	}
}
