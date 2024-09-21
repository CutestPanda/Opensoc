/************************************************************************************************************************
APB-TIMER����Ƚ�ʾ������
@brief  ����APB-TIMERʵ�ֺ�����
@attention �����Ӳ��ƽ̨�������ӳ�(delay)��ص�API
					 ����APB-TIMER��ʱ��Ϊ25MHz, 16λ��ʱ��
					 ʹ��ͨ��0��Ϊ����Ƚ�ͨ��
@date   2024/09/21
@author �¼�ҫ
@eidt   2024/09/21 1.00 �����˵�һ����ʽ�汾
************************************************************************************************************************/

#include "../apb_timer.h"

#include "delay.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define BASEADDR_TIMER 0x40000000 // APB-TIMER�������ַ

#define TIMER_PSC 25 // ��ʱ��Ԥ��Ƶϵ��
#define TIMER_ATL 1000 // ��ʱ���Զ�װ��ֵ

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static ApbTimer timer; // APB-TIMER����ṹ��

static uint32_t now_cmp = 0; // ��ǰ�ıȽ�ֵ
static uint8_t to_incr_cmp = 1; // ����/��С�Ƚ�ֵ(��־)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_timer_pwm_example(void){
	// ��ʼ��APB-TIMER
	ApbTimerConfig timer_config; // APB-TIMER(��ʼ�����ýṹ��)
	
	timer_config.prescale = TIMER_PSC - 1; // Ԥ��Ƶϵ�� - 1
	timer_config.auto_load = TIMER_ATL - 1; // �Զ�װ��ֵ - 1
	timer_config.chn_n = 1; // ͨ����
	timer_config.cap_cmp_sel = CMP_SEL_CHN0 | CAP_SEL_CHN1 | CAP_SEL_CHN2 | CAP_SEL_CHN3; // ����/�Ƚ�ѡ��
	// �Ƚ�ֵ
	timer_config.cmp[0] = 0;
	timer_config.cmp[1] = 0;
	timer_config.cmp[2] = 0;
	timer_config.cmp[3] = 0;
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
	
	// ������ʱ��
	__apb_timer_set_cnt(&timer, TIMER_ATL - 1);
	__apb_timer_start(&timer);
	
	while(1){
		apb_timer_set_cmp(&timer, APB_TIMER_CH0, now_cmp);
		
		if(to_incr_cmp){
			if(now_cmp == 1000){
				to_incr_cmp = 0;
			}else{
				now_cmp += 100;
			}
		}else{
			if(now_cmp == 0){
				to_incr_cmp = 1;
			}else{
				now_cmp -= 100;
			}
		}
		
		delay_ms(100);
	}
}
